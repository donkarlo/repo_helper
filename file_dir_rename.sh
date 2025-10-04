#!/usr/bin/env bash
# rename-part.sh
# Only show a report in terminal, then let user Apply / Redo / Quit. No file is written.

set -euo pipefail

replace_basename() {
  # $1: basename, $2: OLD, $3: NEW, $4: CI(y/N)
  local base="$1" old="$2" new="$3" ci="${4:-N}"
  if [[ "$ci" =~ ^[Yy]$ ]]; then
    printf '%s' "$base" | perl -pe 's/\Q'"$old"'\E/'"$new"'/gi'
  else
    printf '%s' "${base//$old/$new}"
  fi
}

generate_report() {
  # outputs to terminal; fills globals: PAIRS_FILE, COUNT
  PAIRS_FILE="$(mktemp)"
  COUNT=0

  echo "---- Planned renames (preview only) ----"
  while IFS= read -r PATHX; do
    local BASEX DIRX NEWBASE NEWPATH
    BASEX=$(basename "$PATHX")
    DIRX=$(dirname "$PATHX")
    NEWBASE="$(replace_basename "$BASEX" "$OLD" "$NEW" "$CI")"
    NEWPATH="$DIRX/$NEWBASE"

    [[ "$PATHX" == "$NEWPATH" ]] && continue
    if [[ -e "$NEWPATH" ]]; then
      echo "SKIP (exists): $PATHX  ->  $NEWPATH"
      continue
    fi

    echo "PLAN: $PATHX  ->  $NEWPATH"
    printf '%s\t%s\n' "$PATHX" "$NEWPATH" >> "$PAIRS_FILE"
    COUNT=$((COUNT+1))
  done < <(find "$BASE" -depth $FINDOPT "*$OLD*")
  echo "----------------------------------------"
  echo "Planned renames: $COUNT"
}

apply_changes() {
  local APPLIED=0
  while IFS=$'\t' read -r SRC DST; do
    [[ "$SRC" == "$DST" ]] && continue
    if [[ -e "$DST" ]]; then
      echo "SKIP (now exists): $SRC -> $DST"
      continue
    fi
    echo "Renaming: $SRC -> $DST"
    mv -- "$SRC" "$DST"
    APPLIED=$((APPLIED+1))
  done < "$PAIRS_FILE"
  echo "Applied renames: $APPLIED"
}

# --- main loop ---
while :; do
  read -e -p "Base directory [default: /home/donkarlo/Dropbox/repo]: " BASE
  BASE=${BASE:-/home/donkarlo/Dropbox/repo}
  [[ -d "$BASE" ]] || { echo "Not found: $BASE" >&2; exit 1; }

  read -p "Enter substring to replace (OLD): " OLD
  read -p "Enter new substring (NEW): " NEW
  read -p "Case insensitive? (y/N): " CI
  [[ -n "$OLD" && -n "$NEW" ]] || { echo "OLD and NEW must be non-empty." >&2; exit 1; }

  if [[ "$CI" =~ ^[Yy]$ ]]; then FINDOPT="-iname"; else FINDOPT="-name"; fi

  generate_report

  if [[ "$COUNT" -eq 0 ]]; then
    read -p "[R] Redo with new parameters, [Q] Quit? " choice
    case "${choice^^}" in
      R) continue ;;
      Q|*) exit 0 ;;
    esac
  fi

  while :; do
    echo "[A] Apply  |  [R] Redo  |  [Q] Quit"
    read -p "Your choice: " CH
    case "${CH^^}" in
      A) apply_changes; exit 0 ;;
      R) rm -f "$PAIRS_FILE"; break ;;
      Q|*) echo "Exit without applying."; exit 0 ;;
    esac
  done
done
