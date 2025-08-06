#!/bin/bash

PYTHON_BIN=$(which python)
PIP_BIN=$(which pip)

echo "Using Python: $PYTHON_BIN"
echo "Using Pip: $PIP_BIN"
echo

for pkg in ~/repos/*; do
    if [ -d "$pkg" ]; then
        if [ -f "$pkg/pyproject.toml" ] || [ -f "$pkg/setup.py" ]; then
            echo "Installing package: $(basename "$pkg")"
            "$PIP_BIN" install -e "$pkg"
        else
            echo "Skipping non-package: $(basename "$pkg")"
        fi
    fi
done

echo
echo "Done! All editable packages reinstalled for Python $($PYTHON_BIN --version)"

