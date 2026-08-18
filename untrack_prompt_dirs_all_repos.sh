#!/usr/bin/env bash

# untrack_prompt_dirs_all_repos.sh
#
# WHAT THIS SCRIPT DOES
# ---------------------
# Run this script from a directory that contains one or more Git repositories.
#
# Example:
#
#   ~/Dropbox/repo/
#   ├── project_a/.git/
#   ├── project_b/.git/
#   └── group/project_c/.git/
#
# First navigate to that parent directory:
#
#   cd ~/Dropbox/repo
#
# Then run:
#
#   bash untrack_prompt_dirs_all_repos.sh
#
# If the directory from which you run the script is itself a Git repository
# (it contains .git), that repository is processed too.
#
# For EVERY Git repository found at the current directory or below it, the
# script:
#
#   1. Adds:
#
#        prompt/
#
#      to that repository's .gitignore.
#
#      This ignores every directory named exactly "prompt", at any depth.
#
#   2. Removes already tracked prompt directories from the Git index using
#      "git rm --cached".
#
#      IMPORTANT:
#      The local prompt directories and their files are NOT deleted.
#
#   3. Creates a commit:
#
#        Stop tracking prompt directories
#
#   4. Pushes that commit to the remote repository.
#
# Therefore, after a successful push:
#
#   - prompt directories still exist on your computer.
#   - Git stops tracking them.
#   - they disappear from the remote repository in the new commit.
#   - future files inside any directory named "prompt" stay ignored.
#
# SAFETY
# ------
# If a repository already has staged changes before this script touches it,
# that repository is skipped. This prevents unrelated staged work from being
# accidentally included in the automatic commit.

set -u

ROOT="$(pwd)"
COMMIT_MESSAGE="Stop tracking prompt directories"

echo "Searching for Git repositories under:"
echo "  $ROOT"
echo

# Find every .git directory or .git file.
# A .git file can occur in Git worktrees and some submodule setups.
while IFS= read -r -d '' git_marker; do
    repo="$(dirname "$git_marker")"

    # Resolve the actual repository root when possible.
    repo_root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)"

    if [[ -z "$repo_root" ]]; then
        echo "Skipping invalid Git repository marker: $git_marker"
        echo
        continue
    fi

    repo="$repo_root"

    echo "============================================================"
    echo "Repository: $repo"
    echo "============================================================"

    # Do not automatically commit if the user already has staged changes.
    if ! git -C "$repo" diff --cached --quiet --; then
        echo "SKIPPED: this repository already has staged changes."
        echo "Commit or unstage those changes first, then run this script again."
        echo
        continue
    fi

    gitignore="$repo/.gitignore"

    # Add prompt/ only if the exact rule is not already present.
    if ! grep -qxF 'prompt/' "$gitignore" 2>/dev/null; then
        printf '\nprompt/\n' >> "$gitignore"
        echo "Added 'prompt/' to .gitignore"
    else
        echo "'prompt/' is already present in .gitignore"
    fi

    # Collect every tracked directory whose path contains a directory
    # component named exactly "prompt".
    declare -A prompt_dirs=()

    while IFS= read -r -d '' tracked_path; do
        prompt_dir=""

        if [[ "$tracked_path" == prompt/* ]]; then
            prompt_dir="prompt"
        elif [[ "$tracked_path" == */prompt/* ]]; then
            prefix="${tracked_path%%/prompt/*}"
            prompt_dir="$prefix/prompt"
        fi

        if [[ -n "$prompt_dir" ]]; then
            prompt_dirs["$prompt_dir"]=1
        fi
    done < <(git -C "$repo" ls-files -z)

    if (( ${#prompt_dirs[@]} > 0 )); then
        for prompt_dir in "${!prompt_dirs[@]}"; do
            echo "Untracking: $prompt_dir"
            git -C "$repo" rm -r --cached --ignore-unmatch -- "$prompt_dir"
        done
    else
        echo "No currently tracked prompt directories found."
    fi

    # Stage only .gitignore here. The git rm --cached commands above have
    # already staged the removals from the Git index.
    git -C "$repo" add .gitignore

    # If nothing changed, there is nothing to commit or push.
    if git -C "$repo" diff --cached --quiet --; then
        echo "No Git changes were necessary."
        echo
        continue
    fi

    echo
    echo "Staged changes:"
    git -C "$repo" status --short
    echo

    if ! git -C "$repo" commit -m "$COMMIT_MESSAGE"; then
        echo "ERROR: commit failed for $repo"
        echo
        continue
    fi

    branch="$(git -C "$repo" branch --show-current)"
    upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"

    if [[ -n "$upstream" ]]; then
        echo "Pushing to configured upstream: $upstream"
        if ! git -C "$repo" push; then
            echo "WARNING: push failed for $repo"
        fi
    elif [[ -n "$branch" ]] && git -C "$repo" remote get-url origin >/dev/null 2>&1; then
        echo "No upstream is configured."
        echo "Pushing branch '$branch' to origin and setting upstream."
        if ! git -C "$repo" push -u origin "$branch"; then
            echo "WARNING: push failed for $repo"
        fi
    else
        echo "WARNING: commit was created locally, but no usable remote/upstream was found."
        echo "You must push this repository manually."
    fi

    echo

done < <(
    find "$ROOT" \
        \( -type d -o -type f \) \
        -name .git \
        -print0
)

echo "Finished."
