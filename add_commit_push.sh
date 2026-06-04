#!/bin/bash

export GIT_PAGER=cat

cd ~/Dropbox/repo || exit 1

for dir in */ ; do
    repo_path="${PWD}/${dir}"
    cd "$repo_path" || continue

    if [ -d ".git" ]; then
        echo -e "\n📁 Syncing repository: $dir"

        # Ensure we are on the main branch
        git checkout main 2>/dev/null || { echo "❌ Branch 'main' not found in $dir"; cd ..; continue; }

        git add .

        # Show status
        if ! git diff --cached --quiet; then
            echo "📝 Changes staged for commit in $dir:"
            git --no-pager diff --cached --name-only

            # Ask user if they want to commit (with input validation)
            while true; do
                read -p "Do you want to commit and push these changes? [y/N]: " confirm
                case "$confirm" in
                    [Yy])
                        read -p "Enter commit message: " msg
                        git commit -m "$msg"
                        git push mghub main
                        break
                        ;;
                    [Nn]|"")
                        echo "⏭️ Skipped commit and push in $dir"
                        break
                        ;;
                    *)
                        echo "❓ Please enter 'y' or 'n'"
                        ;;
                esac
            done
        else
            echo "✔️ No changes to commit in $dir"
        fi
    else
        echo "🚫 Not a Git repo: $dir"
    fi

    cd ..
done

export GIT_PAGER=cat

MODEL_PATH="/home/donkarlo/Dropbox/repo/nd_ai_project/data/language/natural/large_model/qwen2.5-3b-instruct-q4_k_m.gguf"
BASE_REPO_DIR="$HOME/Dropbox/repo"

find_llama_executable() {
    local candidates=(
        "$HOME/llama.cpp/build/bin/llama-cli"
        "$HOME/llama.cpp/llama-cli"
        "$HOME/llama.cpp/main"
        "/usr/local/bin/llama-cli"
        "/usr/bin/llama-cli"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

generate_fallback_commit_message() {
    local changed_files="$1"
    local keywords=()

    if echo "$changed_files" | grep -Eqi '(^|/)(README|readme)'; then
        keywords+=("README")
    fi
    if echo "$changed_files" | grep -Eqi '\.(ya?ml|json|toml|ini|cfg)$'; then
        keywords+=("config")
    fi
    if echo "$changed_files" | grep -Eqi '(^|/)(test|tests)(/|$)|pytest'; then
        keywords+=("tests")
    fi
    if echo "$changed_files" | grep -Eqi '(^|/)(doc|docs)(/|$)|\.(tex|bib|md)$|paper'; then
        keywords+=("docs")
    fi
    if echo "$changed_files" | grep -Eqi 'model'; then
        keywords+=("model")
    fi
    if echo "$changed_files" | grep -Eqi 'sensor'; then
        keywords+=("sensor")
    fi
    if echo "$changed_files" | grep -Eqi 'robot'; then
        keywords+=("robot")
    fi
    if echo "$changed_files" | grep -Eqi 'data'; then
        keywords+=("data")
    fi
    if echo "$changed_files" | grep -Eqi 'train'; then
        keywords+=("training")
    fi
    if echo "$changed_files" | grep -Eqi 'experiment'; then
        keywords+=("experiment")
    fi
    if echo "$changed_files" | grep -Eqi '\.py$'; then
        keywords+=("python")
    fi

    if [ ${#keywords[@]} -eq 0 ]; then
        local first_file
        first_file="$(echo "$changed_files" | head -n 1)"
        if [ -n "$first_file" ]; then
            echo "update $(basename "$first_file")"
        else
            echo "update files"
        fi
        return 0
    fi

    local message="update"
    local keyword
    for keyword in "${keywords[@]}"; do
        if [[ "$message" != *"$keyword"* ]]; then
            message="$message $keyword,"
        fi
    done

    message="${message%,}"
    echo "$message"
}

generate_ai_commit_message() {
    local changed_files="$1"
    local llama_executable="$2"

    if [ ! -f "$MODEL_PATH" ]; then
        generate_fallback_commit_message "$changed_files"
        return 0
    fi

    if [ -z "$llama_executable" ]; then
        generate_fallback_commit_message "$changed_files"
        return 0
    fi

    local prompt
    prompt=$(
        cat <<EOF
You are generating a git commit message.

Rules:
- Output only the commit message.
- Use imperative mood.
- Keep it natural and concise.
- Maximum 10 words.
- Do not use quotes.
- Do not use bullet points.
- Do not mention file extensions unless necessary.

Changed files:
$changed_files

Commit message:
EOF
    )

    local raw_output
    raw_output="$(
        printf "%s" "$prompt" | "$llama_executable" \
            -m "$MODEL_PATH" \
            -n 32 \
            --temp 0.2 \
            --ctx-size 2048 \
            2>/dev/null
    )"

    local cleaned_output
    cleaned_output="$(
        echo "$raw_output" \
        | tr -d '\r' \
        | sed '/^[[:space:]]*$/d' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
        | head -n 1
    )"

    if [ -z "$cleaned_output" ]; then
        generate_fallback_commit_message "$changed_files"
        return 0
    fi

    echo "$cleaned_output"
}

cd "$BASE_REPO_DIR" || exit 1

LLAMA_EXECUTABLE="$(find_llama_executable)"
if [ -n "$LLAMA_EXECUTABLE" ]; then
    echo "Using llama executable: $LLAMA_EXECUTABLE"
else
    echo "No llama executable found. Fallback commit messages will be used."
fi

for dir in */; do
    repo_path="${PWD}/${dir}"
    cd "$repo_path" || continue

    if [ -d ".git" ]; then
        echo
        echo "Repository: $dir"

        git checkout main >/dev/null 2>&1 || {
            echo "Branch 'main' not found in $dir"
            cd ..
            continue
        }

        git add .

        if ! git diff --cached --quiet; then
            changed_files="$(git --no-pager diff --cached --name-only)"

            echo "Changed files in $dir:"
            echo "$changed_files"

            suggested_message="$(generate_ai_commit_message "$changed_files" "$LLAMA_EXECUTABLE")"
            echo "Suggested commit message: $suggested_message"

            while true; do
                read -p "Do you want to commit and push these changes? [y/N]: " confirm
                case "$confirm" in
                    [Yy])
                        read -p "Enter commit message [$suggested_message]: " msg
                        if [ -z "$msg" ]; then
                            msg="$suggested_message"
                        fi

                        git commit -m "$msg" || {
                            echo "Commit failed in $dir"
                            break
                        }

                        git push mghub main || {
                            echo "Push failed in $dir"
                            break
                        }

                        break
                        ;;
                    [Nn]|"")
                        echo "Skipped commit and push in $dir"
                        break
                        ;;
                    *)
                        echo "Please enter 'y' or 'n'"
                        ;;
                esac
            done
        else
            echo "No changes to commit in $dir"
        fi
    else
        echo "Not a Git repo: $dir"
    fi

    cd ..
done