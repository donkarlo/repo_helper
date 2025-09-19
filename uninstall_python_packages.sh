#!/bin/bash
set -euo pipefail

BASE_DIR="$HOME/Dropbox/repo"

echo ">>> Starting uninstall of all editable projects in $BASE_DIR"
echo

for project in "$BASE_DIR"/*; do
    [ -d "$project" ] || continue

    name=$(basename "$project")

  
    if [[ -f "$project/pyproject.toml" || -f "$project/setup.cfg" || -f "$project/setup.py" ]]; then
        pkgname=$(basename "$project" | sed 's/_project$//')

        echo ">>> Uninstalling $pkgname from $name ..."
        pip uninstall -y "$pkgname" || true

 
        find "$project/src" -maxdepth 2 -type d -name "*.egg-info" -exec rm -rf {} +

        echo ">>> Done with $name"
        echo
    fi
done

echo ">>> Uninstall finished."
