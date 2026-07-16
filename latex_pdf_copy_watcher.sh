#!/usr/bin/env bash
set -uo pipefail

# Directory containing all of your LaTeX projects.
# You may also pass another directory as the first argument.
WATCH_ROOT="${1:-/home/donkarlo/Dropbox/repo}"

if ! command -v inotifywait >/dev/null 2>&1; then
    echo "Error: inotifywait is not installed." >&2
    echo "Install it with: sudo apt install inotify-tools" >&2
    exit 1
fi

if [[ ! -d "$WATCH_ROOT" ]]; then
    echo "Error: directory does not exist: $WATCH_ROOT" >&2
    exit 1
fi

copy_pdf_next_to_source() {
    local pdf_path="$1"
    local output_dir stem synctex_path source_path=""
    local source_dir destination project_root
    local -a candidates=()

    # Ignore all events except PDF files directly inside an "out" directory.
    [[ -f "$pdf_path" ]] || return 0
    [[ "$pdf_path" == *.pdf ]] || return 0

    output_dir="$(dirname -- "$pdf_path")"
    [[ "$(basename -- "$output_dir")" == "out" ]] || return 0

    stem="$(basename -- "$pdf_path" .pdf)"
    synctex_path="$output_dir/$stem.synctex.gz"

    # LuaLaTeX may finish the PDF slightly before the SyncTeX file is ready.
    for _ in {1..30}; do
        [[ -s "$synctex_path" ]] && break
        sleep 0.1
    done

    # SyncTeX normally records the exact path of the compiled main .tex file.
    if [[ -s "$synctex_path" ]]; then
        source_path="$(
            gzip -dc -- "$synctex_path" 2>/dev/null |
                awk 'sub(/^Input:1:/, "") { print; exit }'
        )"

        if [[ -n "$source_path" ]]; then
            source_path="$(realpath -m -- "$source_path")"
        fi
    fi

    # Fallback when SyncTeX is unavailable: locate a uniquely named .tex file.
    if [[ ! -f "$source_path" ]]; then
        project_root="$(dirname -- "$output_dir")"

        mapfile -d '' candidates < <(
            find "$project_root" -type f -name "$stem.tex" \
                -not -path '*/out/*' -print0
        )

        if (( ${#candidates[@]} == 1 )); then
            source_path="${candidates[0]}"
        else
            echo "Skipped: cannot uniquely locate source for $pdf_path" >&2
            return 0
        fi
    fi

    source_dir="$(dirname -- "$source_path")"
    destination="$source_dir/$(basename -- "$pdf_path")"

    # Avoid copying a file onto itself.
    if [[ -e "$destination" && "$pdf_path" -ef "$destination" ]]; then
        return 0
    fi

    # -f replaces an older PDF beside the .tex file.
    cp -f -- "$pdf_path" "$destination"
    echo "Copied: $pdf_path -> $destination"
}

echo "Watching: $WATCH_ROOT"
echo "Press Ctrl+C to stop."

# Ubuntu 20.04 ships an older inotifywait without the --include option.
# Therefore all relevant file-close/move events are received and filtered
# inside copy_pdf_next_to_source().
inotifywait \
    --monitor \
    --recursive \
    --quiet \
    --event close_write \
    --event moved_to \
    --format '%w%f' \
    "$WATCH_ROOT" |
while IFS= read -r changed_path; do
    copy_pdf_next_to_source "$changed_path"
done