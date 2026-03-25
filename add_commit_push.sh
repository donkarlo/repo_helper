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

trim_whitespace() {
    local value="$1"
    value="$(echo "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    echo "$value"
}

sanitize_commit_message() {
    local raw_message="$1"
    local cleaned_message

    cleaned_message="$(echo "$raw_message" | tr -d '\r')"
    cleaned_message="$(echo "$cleaned_message" | sed '/^[[:space:]]*$/d' | head -n 1)"
    cleaned_message="$(trim_whitespace "$cleaned_message")"

    cleaned_message="$(echo "$cleaned_message" | sed 's/^["'"'"'`[:space:]-]*//; s/["'"'"'`[:space:]]*$//')"
    cleaned_message="$(echo "$cleaned_message" | sed 's/^commit message[:[:space:]]*//I')"
    cleaned_message="$(echo "$cleaned_message" | sed 's/^summary[:[:space:]]*//I')"
    cleaned_message="$(echo "$cleaned_message" | sed 's/[.]$//')"

    echo "$cleaned_message"
}

build_fallback_commit_message() {
    local repo_name="$1"
    local name_status="$2"
    local diff_stat="$3"
    local patch_summary="$4"

    local has_addition="0"
    local has_modification="0"
    local has_deletion="0"
    local has_rename="0"
    local has_copy="0"
    local mentions_docs="0"
    local mentions_tests="0"
    local mentions_config="0"
    local mentions_transformer="0"
    local mentions_robot="0"
    local mentions_training="0"
    local mentions_memory="0"
    local mentions_active_inference="0"
    local mentions_assets="0"
    local mentions_latex="0"

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

    if echo "$name_status $patch_summary" | grep -Eqi '(^|/)(doc|docs|paper|review)(/|$)|\.(tex|bib|md|pdf|odg)$'; then
        mentions_docs="1"
    fi
    if echo "$name_status $patch_summary" | grep -Eqi '(^|/)(test|tests)(/|$)|pytest'; then
        mentions_tests="1"
    fi
    if echo "$name_status $patch_summary" | grep -Eqi '\.(ya?ml|json|toml|ini|cfg)$'; then
        mentions_config="1"
    fi
    if echo "$name_status $patch_summary" | grep -Eqi 'transformer|attention|embedding|position_encoding|sequence_to_sequence'; then
        mentions_transformer="1"
    fi
    if echo "$name_status $patch_summary" | grep -Eqi 'robot|uav|lidar|sensor'; then
        mentions_robot="1"
    fi
    if echo "$name_status $patch_summary" | grep -Eqi 'train|training|validation'; then
        mentions_training="1"
    fi
    if echo "$name_status $patch_summary" | grep -Eqi 'memory|trace|mission|run'; then
        mentions_memory="1"
    fi
    if echo "$name_status $patch_summary" | grep -Eqi 'active_inference'; then
        mentions_active_inference="1"
    fi
    if echo "$name_status $patch_summary" | grep -Eqi '(^|/)assets(/|$)'; then
        mentions_assets="1"
    fi
    if echo "$name_status $patch_summary" | grep -Eqi '\.tex$'; then
        mentions_latex="1"
    fi

    local verb="update"
    if [ "$has_addition" = "1" ] && [ "$has_modification" = "0" ] && [ "$has_deletion" = "0" ]; then
        verb="add"
    elif [ "$has_rename" = "1" ] && [ "$has_modification" = "0" ] && [ "$has_addition" = "0" ] && [ "$has_deletion" = "0" ]; then
        verb="rename"
    elif [ "$has_deletion" = "1" ] && [ "$has_modification" = "0" ] && [ "$has_addition" = "0" ]; then
        verb="remove"
    fi

    local topics=()

    if [ "$mentions_transformer" = "1" ]; then
        topics+=("transformer architecture")
    fi
    if [ "$mentions_active_inference" = "1" ]; then
        topics+=("active inference")
    fi
    if [ "$mentions_memory" = "1" ]; then
        topics+=("memory materials")
    fi
    if [ "$mentions_robot" = "1" ]; then
        topics+=("robotics content")
    fi
    if [ "$mentions_training" = "1" ]; then
        topics+=("training notes")
    fi
    if [ "$mentions_docs" = "1" ] && [ ${#topics[@]} -eq 0 ]; then
        topics+=("documentation")
    fi
    if [ "$mentions_assets" = "1" ] && [ ${#topics[@]} -eq 0 ]; then
        topics+=("asset files")
    fi
    if [ "$mentions_latex" = "1" ] && [ ${#topics[@]} -eq 0 ]; then
        topics+=("LaTeX sources")
    fi
    if [ "$mentions_tests" = "1" ] && [ ${#topics[@]} -eq 0 ]; then
        topics+=("tests")
    fi
    if [ "$mentions_config" = "1" ] && [ ${#topics[@]} -eq 0 ]; then
        topics+=("configuration")
    fi

    if [ ${#topics[@]} -eq 0 ]; then
        local first_path
        first_path="$(echo "$name_status" | head -n 1 | awk '{print $NF}')"
        if [ -n "$first_path" ]; then
            topics+=("$(basename "$first_path")")
        else
            topics+=("repository files")
        fi
    fi

    local joined_topics=""
    local index
    for index in "${!topics[@]}"; do
        if [ "$index" -eq 0 ]; then
            joined_topics="${topics[$index]}"
        elif [ "$index" -eq $((${#topics[@]} - 1)) ]; then
            joined_topics="$joined_topics and ${topics[$index]}"
        else
            joined_topics="$joined_topics, ${topics[$index]}"
        fi
    done

    echo "$verb $joined_topics"
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
    prompt=$(
        cat <<EOF
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
- Consider additions, removals, modifications, renames, and moves.
- If the changes mainly expand or revise documentation, say so naturally.
- If the changes mainly refine architecture notes, reviews, or assets, reflect that naturally.

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

    local raw_output
    raw_output="$(
        printf "%s" "$prompt" | "$llama_executable" \
            -m "$MODEL_PATH" \
            -n 48 \
            --temp 0.15 \
            --top-p 0.9 \
            --ctx-size 8192 \
            2>/dev/null
    )"

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

    git add .

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
    local commit_message

    name_status="$(collect_name_status_summary)"
    numstat="$(collect_numstat_summary)"
    diff_stat="$(collect_diff_stat_summary)"
    patch_summary="$(collect_patch_summary)"

    show_staged_change_summaries "$repo_name" "$name_status" "$numstat" "$diff_stat"

    suggested_message="$(generate_ai_commit_message "$repo_name" "$name_status" "$numstat" "$diff_stat" "$patch_summary" "$LLAMA_EXECUTABLE")"
    echo "Suggested commit message: $suggested_message"

    while true; do
        read -r -p "Do you want to commit and push these changes? [y/N]: " confirm
        case "$confirm" in
            [Yy])
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
                ;;
            [Nn]|"")
                echo "Skipped commit and push in $repo_name"
                return 0
                ;;
            *)
                echo "Please enter 'y' or 'n'"
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