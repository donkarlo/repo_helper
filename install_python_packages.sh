#!/bin/bash
set -euo pipefail

BASE_DIR="$HOME/Dropbox/repo"

# Optional flags
DRY_RUN="${DRY_RUN:-0}"            # DRY_RUN=1 فقط گزارش می‌دهد و نصب نمی‌کند
FORCE_REINSTALL="${FORCE_REINSTALL:-0}"  # FORCE_REINSTALL=1 => pip install -e . --force-reinstall

echo "Scanning $BASE_DIR ..."
echo

shopt -s nullglob
for project in "$BASE_DIR"/*; do
  [ -d "$project" ] || continue

  name="$(basename "$project")"
  has_pyproj=0
  has_setup_cfg=0
  has_setup_py=0

  [[ -f "$project/pyproject.toml" ]] && has_pyproj=1
  [[ -f "$project/setup.cfg" ]] && has_setup_cfg=1
  [[ -f "$project/setup.py" ]] && has_setup_py=1

  if (( has_pyproj || has_setup_cfg || has_setup_py )); then
    echo ">> Found Python project: $name"
    cmd=(pip install -e .)
    (( FORCE_REINSTALL )) && cmd+=(--force-reinstall)

    if (( DRY_RUN )); then
      echo "   DRY-RUN: (cd \"$project\" && ${cmd[*]})"
    else
      ( cd "$project" && "${cmd[@]}" )
    fi
    echo
    continue
  fi

  # fallback: if has src/ try anyway
  if [[ -d "$project/src" ]]; then
    echo ">> No pyproject/setup found but has src/: trying install => $name"
    if (( DRY_RUN )); then
      echo "   DRY-RUN: (cd \"$project\" && pip install -e .)"
    else
      ( cd "$project" && pip install -e . ) || {
        echo "   Failed to install $name (no config). Skipping."
      }
    fi
    echo
    continue
  fi

  echo "Skipping $name (no pyproject.toml/setup.cfg/setup.py and no src/)"
done

