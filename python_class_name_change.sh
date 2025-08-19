#!/usr/bin/env bash
set -euo pipefail

# --- choose python interpreter (prefer user's 3.13 venvs) ---
PY_CANDIDATES=(
  "$HOME/phd-venv/bin/python"
  "/home/donkarlo/phd_venv/bin/python"
  "$(command -v python3 || true)"
)
PYBIN=""
for p in "${PY_CANDIDATES[@]}"; do
  if [[ -x "${p}" ]]; then PYBIN="${p}"; break; fi
done
if [[ -z "${PYBIN}" ]]; then
  echo "Error: no python interpreter found." >&2; exit 1
fi

# --- args ---
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <path/to/file.py> <OldClassName>"
  exit 1
fi
FILE_PATH="$1"
OLD_CLASS="$2"

[[ -f "$FILE_PATH" ]] || { echo "Error: file not found: $FILE_PATH" >&2; exit 1; }

# --- extract NEW class name ---
CLASS_COUNT="$(grep -P '^\s*class\s+[A-Za-z_][A-Za-z0-9_]*' "$FILE_PATH" | wc -l | tr -d ' ')"
if [[ "$CLASS_COUNT" -ne 1 ]]; then
  echo "WARNING: expected exactly one class in $FILE_PATH but found $CLASS_COUNT." >&2
fi
NEW_CLASS="$(grep -Po '^\s*class\s+\K[A-Za-z_][A-Za-z0-9_]*' "$FILE_PATH" | head -1 || true)"
[[ -n "${NEW_CLASS:-}" ]] || { echo "Error: no class definition found in $FILE_PATH" >&2; exit 1; }
if [[ ! "$NEW_CLASS" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
  echo "WARNING: '$NEW_CLASS' is not PascalCase (expected e.g. 'MyAwesomeClass')." >&2
fi

# --- PascalCase -> snake_case ---
to_snake() {
  "$PYBIN" - "$1" << 'PY'
import re, sys
name = sys.argv[1]
s1 = re.sub(r'(.)([A-Z][a-z0-9]+)', r'\1_\2', name)
s2 = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', s1)
print(s2.replace('__','_').lower())
PY
}
NEW_MODULE="$(to_snake "$NEW_CLASS")"

DIR="$(dirname "$FILE_PATH")"
OLD_BASENAME="$(basename "$FILE_PATH")"
OLD_MODULE="${OLD_BASENAME%.py}"
NEW_FILE_PATH="$DIR/$NEW_MODULE.py"

# --- rename file (git mv if possible) ---
if [[ "$NEW_FILE_PATH" != "$FILE_PATH" ]]; then
  if git -C "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" rev-parse >/dev/null 2>&1; then
    git mv -f "$FILE_PATH" "$NEW_FILE_PATH"
  else
    mv -f "$FILE_PATH" "$NEW_FILE_PATH"
  fi
  echo "Renamed: $FILE_PATH -> $NEW_FILE_PATH"
else
  echo "File name already matches target: $NEW_FILE_PATH"
fi

# --- repo root ---
DEFAULT_REPOS="$HOME/repos"
if [[ -n "${REPO_ROOT_OVERRIDE:-}" ]]; then
  REPO_ROOT="$REPO_ROOT_OVERRIDE"
elif [[ -d "$DEFAULT_REPOS" ]]; then
  REPO_ROOT="$DEFAULT_REPOS"
elif git -C "$(pwd)" rev-parse >/dev/null 2>&1; then
  REPO_ROOT="$(git rev-parse --show-toplevel)"
else
  REPO_ROOT="$(dirname "$FILE_PATH")"
fi
echo "Scanning Python files under: $REPO_ROOT"

mapfile -t PY_FILES < <(find "$REPO_ROOT" -type f -name '*.py' \
  -not -path '*/.git/*' -not -path '*/.venv/*' -not -path '*/venv/*' -not -path '*/__pycache__/*')
[[ ${#PY_FILES[@]} -gt 0 ]] || { echo "No Python files found to update."; exit 0; }

# --- helpers ---
esc() { printf '%s' "$1" | sed 's/[.[\*^$()+?{}|\\]/\\&/g'; }
OLD_MOD_ESC="$(esc "$OLD_MODULE")"
NEW_MOD_ESC="$(esc "$NEW_MODULE")"
OLD_CLASS_ESC="$(esc "$OLD_CLASS")"
NEW_CLASS_ESC="$(esc "$NEW_CLASS")"

perl_update_imports() {
  perl -0777 -i -pe "
    s/\\bfrom\\s+(([\\.\\w]+\\.)?)${OLD_MOD_ESC}\\b\\s+import\\s+${OLD_CLASS_ESC}\\b(?!\\s+as)/
      'from ' . \$1 . '${NEW_MOD_ESC}' . ' import ' . '${NEW_CLASS_ESC}'/ge;
    s/\\bfrom\\s+(([\\.\\w]+\\.)?)${OLD_MOD_ESC}\\b\\s+import\\s+${OLD_CLASS_ESC}\\s+as\\s+(\\w+)/
      'from ' . \$1 . '${NEW_MOD_ESC}' . ' import ' . '${NEW_CLASS_ESC}' . ' as ' . \$3/ge;
    s/\\bimport\\s+(([\\.\\w]+\\.)?)${OLD_MOD_ESC}\\b/import \$1${NEW_MOD_ESC}/g;
  " "$1"
}

# --- token-based safe rename, supports both 3.8 and 3.13 ---
python_token_rename() {
  "$PYBIN" - "$OLD_CLASS" "$NEW_CLASS" "$1" << 'PY'
import io, os, re, sys, tokenize

old, new, path = sys.argv[1], sys.argv[2], sys.argv[3]

def rename_with_generate_tokens(src_text: str) -> bytes:
    """Python 3.8-safe: operate on text; generate_tokens yields TokenInfo without ENCODING."""
    out_tokens = []
    rl = io.StringIO(src_text).readline
    for tok in tokenize.generate_tokens(rl):  # TokenInfo(type, string, start, end, line)
        if tok.type == tokenize.NAME and tok.string == old:
            tok = tokenize.TokenInfo(tok.type, new, tok.start, tok.end, tok.line)
        out_tokens.append(tok)
    result = tokenize.untokenize(out_tokens)
    if isinstance(result, str):
        return result.encode('utf-8')
    return result

def rename_with_tokenize(src_bytes: bytes) -> bytes:
    """Python 3.13 path: bytes reader; includes ENCODING/ENDMARKER."""
    out_tokens = []
    rl = io.BytesIO(src_bytes).readline
    for tok in tokenize.tokenize(rl):
        if tok.type == tokenize.NAME and tok.string == old:
            tok = tokenize.TokenInfo(tok.type, new, tok.start, tok.end, tok.line)
        out_tokens.append(tok)
    result = tokenize.untokenize(out_tokens)
    if isinstance(result, str):
        return result.encode('utf-8')
    return result

with open(path, 'rb') as f:
    raw = f.read()

try:
    if sys.version_info < (3,9):
        new_raw = rename_with_generate_tokens(raw.decode('utf-8'))
    else:
        new_raw = rename_with_tokenize(raw)
except Exception:
    # FINAL FALLBACK (regex on code-only, skipping obvious strings/comments heuristically)
    text = raw.decode('utf-8')
    # crude but safe-ish: replace only identifier boundaries
    new_text = re.sub(rf'\\b{re.escape(old)}\\b', new, text)
    new_raw = new_text.encode('utf-8')

if new_raw != raw:
    with open(path, 'wb') as f:
        f.write(new_raw)
PY
}

cleanup_redundant_alias() {
  perl -0777 -i -pe "
    s/\\bfrom\\s+([\\.\\w]+)\\s+import\\s+${NEW_CLASS_ESC}\\s+as\\s+${NEW_CLASS_ESC}\\b/from \\1 import ${NEW_CLASS_ESC}/g;
  " "$1"
}

UPDATED_IMPORTS=0
for f in "${PY_FILES[@]}"; do
  perl_update_imports "$f" && UPDATED_IMPORTS=1 || true
done
[[ $UPDATED_IMPORTS -eq 1 ]] && echo "Imports updated to new module/class."

RENAMED_USES=0
for f in "${PY_FILES[@]}"; do
  python_token_rename "$f" && RENAMED_USES=1 || true
  cleanup_redundant_alias "$f" || true
done
[[ $RENAMED_USES -eq 1 ]] && echo "All code usages of ${OLD_CLASS} renamed to ${NEW_CLASS}."

echo "Done. New class: ${NEW_CLASS}   New module: ${NEW_MODULE}"

