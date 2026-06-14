#!/bin/bash
export GIT_PAGER=cat

BASE_REPO_DIR="$HOME/Dropbox/repo"
MODEL_PATH="/home/donkarlo/Dropbox/repo/nd_ai_project/data/language/natural/large_model/qwen2.5-3b-instruct-q4_k_m.gguf"
LLAMA_EXECUTABLE_CANDIDATES=(
    "$HOME/llama.cpp/build/bin/llama-cli"
    "$HOME/llama.cpp/llama-cli"
    "$HOME/llama.cpp/main"
    "/usr/local/bin/llama-cli"
    "/usr/bin/llama-cli"
)

MAX_FILES_FOR_PATCH=20
MAX_PATCH_LINES_PER_FILE=80
MAX_TOTAL_PROMPT_CHARS=24000


find_llama_executable() {
    local candidate_path
    for candidate_path in "${LLAMA_EXECUTABLE_CANDIDATES[@]}"; do
        if [ -x "$candidate_path" ]; then
            echo "$candidate_path"
            return 0
        fi
    done
    return 1
}

llama_supports_no_display_prompt() {
    local llama_executable="$1"
    "$llama_executable" --help 2>&1 | grep -q -- '--no-display-prompt'
}

trim_whitespace() {
    local value="$1"
    value="$(echo "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    echo "$value"
}

is_prompt_or_metadata_line() {
    local line="$1"

    echo "$line" | grep -Eqi '^(you are|repository:|task:|rules:|staged file status:|staged line statistics:|diff stat:|patch summary:|output only|use imperative|keep it specific|prefer one line|maximum [0-9]+ words|do not mention|use the actual nature|consider additions|if the changes|write one concise|commit message:$)'
}

sanitize_commit_message() {
    local raw_message="$1"
    local line
    local cleaned_line
    local selected_message=""

    while IFS= read -r line; do
        cleaned_line="$(echo "$line" | tr -d '\r')"
        cleaned_line="$(trim_whitespace "$cleaned_line")"
        [ -z "$cleaned_line" ] && continue

        cleaned_line="$(echo "$cleaned_line" | sed 's/^```[[:alpha:]]*//; s/```$//')"
        cleaned_line="$(trim_whitespace "$cleaned_line")"
        [ -z "$cleaned_line" ] && continue

        cleaned_line="$(echo "$cleaned_line" | sed 's/^[-*[:space:]]*//')"
        cleaned_line="$(echo "$cleaned_line" | sed 's/^[0-9][0-9]*[.)][[:space:]]*//')"
        cleaned_line="$(echo "$cleaned_line" | sed 's/^commit message[:[:space:]]*//I')"
        cleaned_line="$(echo "$cleaned_line" | sed 's/^summary[:[:space:]]*//I')"
        cleaned_line="$(echo "$cleaned_line" | sed 's/^suggested commit message[:[:space:]]*//I')"
        cleaned_line="$(echo "$cleaned_line" | sed 's/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//; s/^`//; s/`$//')"
        cleaned_line="$(trim_whitespace "$cleaned_line")"
        [ -z "$cleaned_line" ] && continue

        if is_prompt_or_metadata_line "$cleaned_line"; then
            continue
        fi

        if echo "$cleaned_line" | grep -Eqi '^(repository|task|rules|staged|diff stat|patch summary)$'; then
            continue
        fi

        if [ "$(echo "$cleaned_line" | wc -w)" -gt 20 ]; then
            continue
        fi

        selected_message="$cleaned_line"
    done <<< "$raw_message"

    selected_message="$(trim_whitespace "$selected_message")"
    selected_message="$(echo "$selected_message" | sed 's/[.]$//')"

    echo "$selected_message"
}

first_changed_path() {
    local name_status="$1"
    echo "$name_status" | head -n 1 | awk '{print $NF}'
}

build_fallback_commit_message() {
    local repo_name="$1"
    local name_status="$2"
    local diff_stat="$3"
    local patch_summary="$4"

    local combined_text="$name_status
$diff_stat
$patch_summary"
    local has_addition="0"
    local has_modification="0"
    local has_deletion="0"
    local has_rename="0"
    local has_copy="0"

    if echo "$name_status" | grep -q '^A'; then
        has_addition="1"
    fi
    if echo "$name_status" | grep -q '^M'; then
        has_modification="1"
    fi
    if echo "$name_status" | grep -q '^D'; then
        has_deletion="1"
    fi
    if echo "$name_status" | grep -q '^R'; then
        has_rename="1"
    fi
    if echo "$name_status" | grep -q '^C'; then
        has_copy="1"
    fi

    if echo "$combined_text" | grep -q 'src/kind/presentation' && echo "$combined_text" | grep -q 'src/kind/journal_2026/presentation'; then
        echo "move presentation materials under kind"
        return 0
    fi

    if echo "$combined_text" | grep -Eqi '(^|/)presentation(_old)?(/|$)'; then
        if [ "$has_deletion" = "1" ] && [ "$has_addition" = "1" ]; then
            echo "move presentation materials"
        elif [ "$has_addition" = "1" ] && [ "$has_modification" = "0" ]; then
            echo "add presentation materials"
        else
            echo "update presentation materials"
        fi
        return 0
    fi

    if echo "$combined_text" | grep -Eqi '(^|/)slides?(/|$)|beamer'; then
        echo "update slide materials"
        return 0
    fi

    if echo "$combined_text" | grep -Eqi '(^|/)(doc|docs|paper|review)(/|$)|\.(tex|bib|md|pdf|odg)$'; then
        if echo "$combined_text" | grep -Eqi '\.tex$'; then
            echo "update LaTeX sources"
        else
            echo "update documentation materials"
        fi
        return 0
    fi

    if echo "$combined_text" | grep -Eqi '(^|/)(test|tests)(/|$)|pytest'; then
        echo "update tests"
        return 0
    fi

    if echo "$combined_text" | grep -Eqi '\.(ya?ml|json|toml|ini|cfg)$'; then
        echo "update configuration"
        return 0
    fi

    local verb="update"
    if [ "$has_addition" = "1" ] && [ "$has_modification" = "0" ] && [ "$has_deletion" = "0" ]; then
        verb="add"
    elif [ "$has_rename" = "1" ] && [ "$has_modification" = "0" ] && [ "$has_addition" = "0" ] && [ "$has_deletion" = "0" ]; then
        verb="rename"
    elif [ "$has_deletion" = "1" ] && [ "$has_modification" = "0" ] && [ "$has_addition" = "0" ]; then
        verb="remove"
    elif [ "$has_deletion" = "1" ] && [ "$has_addition" = "1" ]; then
        verb="move"
    fi

    local first_path
    local first_name
    first_path="$(first_changed_path "$name_status")"
    first_name="$(basename "$first_path")"

    if [ -n "$first_name" ] && [ "$first_name" != "." ]; then
        echo "$verb $first_name"
    else
        echo "$verb repository files"
    fi
}

collect_name_status_summary() {
    git diff --cached --name-status -M -C
}

collect_numstat_summary() {
    git diff --cached --numstat -M -C
}

collect_diff_stat_summary() {
    git diff --cached --stat -M -C
}

collect_patch_summary() {
    local patch_output=""
    local processed_files=0
    local name_status_lines

    name_status_lines="$(git diff --cached --name-status -M -C)"

    while IFS= read -r status_line; do
        [ -z "$status_line" ] && continue

        processed_files=$((processed_files + 1))
        if [ "$processed_files" -gt "$MAX_FILES_FOR_PATCH" ]; then
            patch_output="${patch_output}"$'\n'"[Patch summary truncated after ${MAX_FILES_FOR_PATCH} files]"
            break
        fi

        local status_code
        local first_path
        local second_path
        local file_path
        local file_patch

        status_code="$(echo "$status_line" | awk '{print $1}')"
        first_path="$(echo "$status_line" | awk '{print $2}')"
        second_path="$(echo "$status_line" | awk '{print $3}')"

        if [[ "$status_code" =~ ^R|^C ]]; then
            file_path="$second_path"
        else
            file_path="$first_path"
        fi

        if [ -z "$file_path" ]; then
            continue
        fi

        file_patch="$(git diff --cached --unified=0 --no-color -- "$file_path" | head -n "$MAX_PATCH_LINES_PER_FILE")"

        patch_output="${patch_output}"$'\n'"===== FILE: $file_path ====="$'\n'
        patch_output="${patch_output}${file_patch}"$'\n'
    done <<< "$name_status_lines"

    echo "$patch_output"
}

truncate_prompt_if_needed() {
    local prompt_content="$1"
    local prompt_length

    prompt_length="${#prompt_content}"

    if [ "$prompt_length" -le "$MAX_TOTAL_PROMPT_CHARS" ]; then
        echo "$prompt_content"
        return 0
    fi

    echo "${prompt_content:0:$MAX_TOTAL_PROMPT_CHARS}"$'\n'"[Prompt truncated]"
}

build_llm_prompt() {
    local repo_name="$1"
    local name_status="$2"
    local numstat="$3"
    local diff_stat="$4"
    local patch_summary="$5"

    local prompt
    prompt=$(cat <<EOF
You are generating a Git commit message for a staged commit.

Repository:
$repo_name

Task:
Write one concise and natural Git commit message that summarizes the staged changes.

Rules:
- Output only the commit message.
- Use imperative mood.
- Keep it specific and natural.
- Prefer one line.
- Maximum 14 words.
- Do not mention file extensions unless necessary.
- Use the actual nature of the changes if it can be inferred.
- Mention the most specific changed directory or topic.
- If files are added in one directory and deleted from another similar directory, describe it as a move.
- Do not use generic messages like "update documentation" unless nothing clearer exists.
- Do not repeat these instructions.

Staged file status:
$name_status

Staged line statistics:
$numstat

Diff stat:
$diff_stat

Patch summary:
$patch_summary

Commit message:
EOF
    )

    truncate_prompt_if_needed "$prompt"
}

generate_ai_commit_message() {
    local repo_name="$1"
    local name_status="$2"
    local numstat="$3"
    local diff_stat="$4"
    local patch_summary="$5"
    local llama_executable="$6"

    if [ ! -f "$MODEL_PATH" ]; then
        build_fallback_commit_message "$repo_name" "$name_status" "$diff_stat" "$patch_summary"
        return 0
    fi

    if [ -z "$llama_executable" ]; then
        build_fallback_commit_message "$repo_name" "$name_status" "$diff_stat" "$patch_summary"
        return 0
    fi

    local prompt
    prompt="$(build_llm_prompt "$repo_name" "$name_status" "$numstat" "$diff_stat" "$patch_summary")"

    local llama_arguments=(
        -m "$MODEL_PATH"
        -n 64
        --temp 0.2
        --top-p 0.9
        --ctx-size 8192
    )

    if llama_supports_no_display_prompt "$llama_executable"; then
        llama_arguments+=(--no-display-prompt)
    fi

    local raw_output
    raw_output="$({ printf "%s" "$prompt" | "$llama_executable" "${llama_arguments[@]}"; } 2>/dev/null)"

    local cleaned_output
    cleaned_output="$(sanitize_commit_message "$raw_output")"

    if [ -z "$cleaned_output" ]; then
        build_fallback_commit_message "$repo_name" "$name_status" "$diff_stat" "$patch_summary"
        return 0
    fi

    echo "$cleaned_output"
}

ensure_main_branch() {
    git checkout main >/dev/null 2>&1
}

ensure_remote_exists() {
    git remote get-url mghub >/dev/null 2>&1
}

show_repository_header() {
    local repo_name="$1"
    echo
    echo "Repository: $repo_name"
}

show_staged_change_summaries() {
    local repo_name="$1"
    local name_status="$2"
    local numstat="$3"
    local diff_stat="$4"

    echo "Staged file status in $repo_name:"
    echo "$name_status"
    echo

    echo "Staged line statistics in $repo_name:"
    echo "$numstat"
    echo

    echo "Diff stat in $repo_name:"
    echo "$diff_stat"
    echo
}

commit_and_push_repository() {
    local repo_name="$1"
    local suggested_message="$2"
    local commit_message

    read -r -p "Enter commit message [$suggested_message]: " commit_message
    if [ -z "$commit_message" ]; then
        commit_message="$suggested_message"
    fi

    git commit -m "$commit_message" || {
        echo "Commit failed in $repo_name"
        return 0
    }

    git push mghub main || {
        echo "Push failed in $repo_name"
        return 0
    }

    return 0
}

process_repository() {
    local repo_name="$1"

    if [ ! -d ".git" ]; then
        echo "Not a Git repo: $repo_name"
        return 0
    fi

    show_repository_header "$repo_name"

    if ! ensure_main_branch; then
        echo "Branch 'main' not found in $repo_name"
        return 0
    fi

    if ! ensure_remote_exists; then
        echo "Remote 'mghub' not found in $repo_name"
        return 0
    fi

    git add -A

    if git diff --cached --quiet; then
        echo "No staged changes to commit in $repo_name"
        return 0
    fi

    local name_status
    local numstat
    local diff_stat
    local patch_summary
    local suggested_message
    local confirm

    name_status="$(collect_name_status_summary)"
    numstat="$(collect_numstat_summary)"
    diff_stat="$(collect_diff_stat_summary)"
    patch_summary="$(collect_patch_summary)"

    show_staged_change_summaries "$repo_name" "$name_status" "$numstat" "$diff_stat"

    suggested_message="$(generate_ai_commit_message "$repo_name" "$name_status" "$numstat" "$diff_stat" "$patch_summary" "$LLAMA_EXECUTABLE")"
    echo "Suggested commit message: $suggested_message"

    while true; do
        read -r -p "Commit and push these changes? [Y/n]: " confirm
        case "$confirm" in
            [Nn]|[Nn][Oo])
                git reset -q
                echo "Skipped commit and push in $repo_name"
                return 0
                ;;
            [Yy]|[Yy][Ee][Ss]|"")
                commit_and_push_repository "$repo_name" "$suggested_message"
                return 0
                ;;
            *)
                echo "Press Enter or type 'y' to commit and push; type 'n' to skip."
                ;;
        esac
    done
}

main() {
    cd "$BASE_REPO_DIR" || exit 1

    LLAMA_EXECUTABLE="$(find_llama_executable)"

    if [ -n "$LLAMA_EXECUTABLE" ]; then
        echo "Using llama executable: $LLAMA_EXECUTABLE"
    else
        echo "No llama executable found. Fallback commit messages will be used."
    fi

    local directory_name
    for directory_name in */; do
        cd "$BASE_REPO_DIR/$directory_name" || continue
        process_repository "$directory_name"
    done
}

main
