#!/usr/bin/env python3
import argparse, re, sys, shutil
from pathlib import Path

def parse_args():
    p = argparse.ArgumentParser(
        description="Dedup refs.bib and drop unknown cite keys from .tex files."
    )
    p.add_argument("project_root", type=Path)
    p.add_argument("--bibrel", default="src/refs.bib",
                   help="refs.bib path relative to PROJECT_ROOT (default: src/refs.bib)")
    return p.parse_args()

# --- Bib helpers -------------------------------------------------------------

ENTRY_START = re.compile(r'^\s*@(?P<type>[A-Za-z]+)\s*\{\s*(?P<key>[^,\s]+)\s*,', re.ASCII)

def iter_bib_entries(text: str):
    """Yield (key, entry_text) by scanning braces from each @entry start."""
    lines = text.splitlines(keepends=True)
    i = 0
    n = len(lines)
    while i < n:
        m = ENTRY_START.match(lines[i])
        if not m:
            i += 1
            continue
        key = m.group("key")
        buf = [lines[i]]
        brace_balance = lines[i].count("{") - lines[i].count("}")
        i += 1
        while i < n and brace_balance > 0:
            buf.append(lines[i])
            brace_balance += lines[i].count("{") - lines[i].count("}")
            i += 1
        yield key, "".join(buf)

def dedup_bib(bib_path: Path):
    original = bib_path.read_text(encoding="utf-8", errors="ignore")
    seen = set()
    kept = []
    i = 0
    # Keep header/comments before the first @entry:
    # find first @ that starts an entry line
    head_end = 0
    for i, line in enumerate(original.splitlines(keepends=True)):
        if ENTRY_START.match(line):
            break
        head_end += len(line)
    header = original[:head_end]
    body = original[head_end:]

    for key, entry in iter_bib_entries(body):
        if key not in seen:
            kept.append(entry)
            seen.add(key)

    out = header + ("".join(kept))
    if out != original:
        shutil.copyfile(bib_path, bib_path.with_suffix(bib_path.suffix + ".bak"))
        bib_path.write_text(out, encoding="utf-8")
        changed = True
    else:
        changed = False
    return seen, changed

# --- TeX helpers -------------------------------------------------------------

# Matches \nocite[...]?{k1, k2 , ...}
NOCITE_RE = re.compile(
    r'''\\nocite
        (\[[^\]]*\])?      # optional []
        \{([^{}]*)\}       # body with keys
    ''', re.X
)

# Matches \*cite* with up to two optional [] and a {keys}
CITE_RE = re.compile(
    r'''
    \\([A-Za-z]*cite[A-Za-z]*)   # command name
    \s*
    (\[[^\]]*\]\s*)?             # optional []
    (\[[^\]]*\]\s*)?             # optional []
    \{([^{}]*)\}                 # body with keys
    ''', re.X
)

def filter_keys_str(keys_str: str, ok: set[str]):
    keys = [k.strip() for k in keys_str.split(",")]
    keep = [k for k in keys if k and k in ok]
    return keep

def fix_tex_text(text: str, ok: set[str]):
    changed = False

    # \nocite
    def repl_nocite(m):
        nonlocal changed
        opt = m.group(1) or ""
        body = m.group(2) or ""
        keep = filter_keys_str(body, ok)
        if keep:
            if len(keep) != len([k.strip() for k in body.split(",") if k.strip()]):
                changed = True
            return f"\\nocite{opt}{{{','.join(keep)}}}"
        else:
            changed = True
            return ""  # drop empty nocite
    text2 = NOCITE_RE.sub(repl_nocite, text)

    # all *cite*
    def repl_cite(m):
        nonlocal changed
        cmd, o1, o2, body = m.group(1), (m.group(2) or ""), (m.group(3) or ""), (m.group(4) or "")
        keep = filter_keys_str(body, ok)
        if keep:
            if len(keep) != len([k.strip() for k in body.split(",") if k.strip()]):
                changed = True
            return f"\\{cmd}{o1}{o2}{{{','.join(keep)}}}"
        else:
            changed = True
            # drop the whole command including its optionals
            return ""
    text3 = CITE_RE.sub(repl_cite, text2)

    return text3, changed

def main():
    args = parse_args()
    project_root = args.project_root.resolve()
    bib_path = (project_root / args.bibrel).resolve()

    print(f"[1/3] Deduping bib: {bib_path}")
    ok_keys, bib_changed = dedup_bib(bib_path)

    print(f"[2/3] Collecting keys... Found {len(ok_keys)} unique keys.")

    print(f"[3/3] Rewriting .tex files to drop unknown citations...")
    tex_files = sorted(project_root.rglob("*.tex"))
    changed_count = 0
    for f in tex_files:
        original = f.read_text(encoding="utf-8", errors="ignore")
        fixed, did_change = fix_tex_text(original, ok_keys)
        if did_change:
            # backup next to file
            shutil.copyfile(f, f.with_suffix(f.suffix + ".bak"))
            f.write_text(fixed, encoding="utf-8")
            print(f"    fixed: {f}")
            changed_count += 1
    print(f"Done. Updated {changed_count} .tex file(s).")
    if bib_changed:
        print(f"Backups:\n  - Bib backup: {bib_path}.bak\n  - .tex backups: *.bak next to each changed file")
    else:
        print(f"Backups:\n  - .tex backups: *.bak next to each changed file")

if __name__ == "__main__":
    sys.exit(main())
