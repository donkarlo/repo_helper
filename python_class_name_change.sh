#!/usr/bin/env bash
set -euo pipefail

# rename_class_and_fix_imports.sh
# Renames a single-class Python file to snake_case based on the NEW class name
# inside the file, updates imports across the repository, and renames every code
# usage of the old class name to the new one (without touching strings/comments).
#
# Usage:
#   ./rename_class_and_fix_imports.sh <path/to/file.py> <OldClassName>
#
# Defaults:
#   - Repository root scanned for updates: $HOME/repos  (i.e., /home/donkarlo/repos)
#   - Override root by exporting REPO_ROOT_OVERRIDE=/path/to/dir

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <path/to/file.py> <OldClassName>"
  exit 1
fi

FILE_PATH="$1"
OLD_CLASS="$2"

if [[ ! -f "$FILE_PATH" ]]; then
  echo "Error: file not found: $FILE_PATH" >&2
  exit 1
fi

# Ensure the file contains exactly ONE top-level class definition (best-effort).
CLASS_COUNT="$(grep -P '^\s*class\s+[A-Za-z_][A-Za-z0-9_]*' "$FILE_PATH" | wc -l | tr -d ' ')"
if [[ "$CLASS_COUNT" -ne 1 ]]; then
  echo "WARNING: expected exactly one class in $FILE_PATH but found $CLASS_COUNT." >&2
fi

# Extract the NEW class name (first class defined in the file).
NEW_CLASS="$(grep -Po '^\s*class\s+\K[A-Za-z_][A-Za-z0-9_]*' "$FILE_PATH" | head -1 || true)"
if [[ -z "${NEW_CLASS:-}" ]]; then
  echo "Error: no class definition found in $FILE_PATH" >&2
  exit 1
fi

# Check PascalCase: starts with uppercase and contains only letters/digits thereafter.
if [[ ! "$NEW_CLASS" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
  echo "WARNING: '$NEW_CLASS' is not PascalCase (expected e.g. 'MyAwesomeClass')." >&2
fi

# Convert PascalCase to snake_case for the module file name.
to_snake() {
  python3 - "$1" << 'PY'
import re, sys
name = sys.argv[1]
# Convert "PascalCase" -> "pascal_case"
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

# Rename the file to the new snake_case module (git mv if available).
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

# --- Determine repository root to scan ---
DEFAULT_REPOS="$HOME/repos"     # i.e., /home/donkarlo/repos
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

# Collect all .py files (skip obvious noise).
mapfile -t PY_FILES < <(find "$REPO_ROOT" -type f -name '*.py' \
  -not -path '*/.git/*' -not -path '*/.venv/*' -not -path '*/venv/*' -not -path '*/__pycache__/*')

if [[ ${#PY_FILES[@]} -eq 0 ]]; then
  echo "No Python files found to update."
  exit 0
fi

# Escape names for regex safety.
esc() { printf '%s' "$1" | sed 's/[.[\*^$()+?{}|\\]/\\&/g'; }
OLD_MOD_ESC="$(esc "$OLD_MODULE")"
NEW_MOD_ESC="$(esc "$NEW_MODULE")"
OLD_CLASS_ESC="$(esc "$OLD_CLASS")"
NEW_CLASS_ESC="$(esc "$NEW_CLASS")"

# 1) Update imports to point to the NEW module and NEW class.
#    - from pkg.old_module import OldClassName     -> from pkg.new_module import NewClassName
#    - from pkg.old_module import OldClassName as A -> from pkg.new_module import NewClassName as A
#    - import pkg.old_module                        -> import pkg.new_module
#    (handles relative imports as well)
perl_update_imports() {
  perl -0777 -i -pe "
    # from ...old_module import OldClassName  (no alias)
    s/\\bfrom\\s+(([\\.\\w]+\\.)?)${OLD_MOD_ESC}\\b\\s+import\\s+${OLD_CLASS_ESC}\\b(?!\\s+as)/
      'from ' . \$1 . '${NEW_MOD_ESC}' . ' import ' . '${NEW_CLASS_ESC}'/ge;

    # from ...old_module import OldClassName as Alias
    s/\\bfrom\\s+(([\\.\\w]+\\.)?)${OLD_MOD_ESC}\\b\\s+import\\s+${OLD_CLASS_ESC}\\s+as\\s+(\\w+)/
      'from ' . \$1 . '${NEW_MOD_ESC}' . ' import ' . '${NEW_CLASS_ESC}' . ' as ' . \$3/ge;

    # import ...old_module
    s/\\bimport\\s+(([\\.\\w]+\\.)?)${OLD_MOD_ESC}\\b/import \$1${NEW_MOD_ESC}/g;
  " "$1"
}

# 2) Rename all NAME tokens OldClassName -> NewClassName WITHOUT touching strings/comments.
python_token_rename() {
  python3 - "$OLD_CLASS" "$NEW_CLASS" "$1" << 'PY'
import io, os, sys, tokenize

old, new, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, 'rb') as f:
    src = f.read()

out = io.BytesIO()
tokgen = tokenize.tokenize(io.BytesIO(src).readline)

def repl(tok):
    tok_type, tok_str, start, end, line = tok
    # Only replace NAME tokens that exactly match the old identifier
    if tok_type == tokenize.NAME and tok_str == old:
        tok_str = new
    return tokenize.TokenInfo(tok_type, tok_str, start, end, line)

tokens = [repl(t) for t in tokgen]
# Re-serialize tokens; tokenize.detect_encoding handled by tokenize()
tokenize.untokenize(tokens, out)
new_src = out.getvalue()

if new_src != src:
    with open(path, 'wb') as f:
        f.write(new_src)
PY
}

# 3) Optional cleanup: turn "from x import NewClassName as NewClassName" -> "from x import NewClassName"
cleanup_redundant_alias() {
  perl -0777 -i -pe "
    s/\\bfrom\\s+([\\.\\w]+)\\s+import\\s+${NEW_CLASS_ESC}\\s+as\\s+${NEW_CLASS_ESC}\\b/from \\1 import ${NEW_CLASS_ESC}/g;
  " "$1"
}

UPDATED_IMPORTS=0
for f in "${PY_FILES[@]}"; do
  perl_update_imports "$f" && UPDATED_IMPORTS=1
done
[[ $UPDATED_IMPORTS -eq 1 ]] && echo "Imports updated to new module/class."

RENAMED_USES=0
for f in "${PY_FILES[@]}"; do
  python_token_rename "$f" && RENAMED_USES=1
  cleanup_redundant_alias "$f" || true
done
[[ $RENAMED_USES -eq 1 ]] && echo "All code usages of ${OLD_CLASS} renamed to ${NEW_CLASS}."

echo "Done. New class: ${NEW_CLASS}   New module: ${NEW_MODULE}"

