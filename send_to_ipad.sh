#!/bin/bash

PORT=8000

read -rp "Enter file path: " FILE

if [ ! -f "$FILE" ]; then
    echo "File not found: $FILE"
    exit 1
fi

DIR=$(dirname "$FILE")
NAME=$(basename "$FILE")
IP=$(hostname -I | awk '{print $1}')

echo
echo "Open this on iPad:"
echo "http://$IP:$PORT/$NAME"
echo

cd "$DIR" || exit 1
python3 -m http.server "$PORT" --bind 0.0.0.0