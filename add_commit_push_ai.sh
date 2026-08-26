#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="$SCRIPT_DIR/add_commit_push_ai_core.sh"
PYTHON_EXECUTABLE="/home/donkarlo/phd-venv/bin/python"

if [ -t 0 ] && [ -t 1 ]; then
    exec /bin/bash "$CORE_SCRIPT" "$@"
fi

if [ ! -x "$PYTHON_EXECUTABLE" ]; then
    PYTHON_EXECUTABLE="$(command -v python3)"
fi
exec "$PYTHON_EXECUTABLE" "$SCRIPT_DIR/add_commit_push_gui.py" "$CORE_SCRIPT"
