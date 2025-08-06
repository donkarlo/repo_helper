#!/bin/bash

export GIT_PAGER=cat

cd ~/repos || exit 1

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
