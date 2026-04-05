#!/usr/bin/env bash

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 /path/to/folder"
    exit 1
fi

TARGET_DIR="$1"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: '$TARGET_DIR' is not a valid directory."
    exit 1
fi

copy_to_clipboard() {
    if command -v wl-copy >/dev/null 2>&1; then
        wl-copy
        return 0
    elif command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard
        return 0
    elif command -v xsel >/dev/null 2>&1; then
        xsel --clipboard --input
        return 0
    elif command -v pbcopy >/dev/null 2>&1; then
        pbcopy
        return 0
    else
        return 1
    fi
}

generate_tree() {
    if command -v tree >/dev/null 2>&1; then
        tree -a "$TARGET_DIR"
    else
        echo "[tree is not installed, using find instead]"
        find "$TARGET_DIR" | sed -e "s|[^/]*/|│   |g" -e "s|│   \([^│]\)|├── \1|"
    fi
}

OUTPUT="$(generate_tree)"

printf '%s\n' "$OUTPUT"

if printf '%s' "$OUTPUT" | copy_to_clipboard; then
    echo
    echo "Output has also been copied to the clipboard."
else
    echo
    echo "Clipboard tool was not found. Output was only shown in the terminal."
fi