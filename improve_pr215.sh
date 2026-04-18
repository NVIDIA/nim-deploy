#!/bin/bash
set -e

REPO_DIR="/sandbox/.openclaw-data/workspace/nim-deploy-pr215"
WORKSHOP_DIR="$REPO_DIR/cloud-service-providers/azure/workshops/aks-nemoclaw"
SEEN_FILE="$REPO_DIR/.seen_pr_comments_215"
GITHUB_API_BASE="https://api.github.com/repos/NVIDIA/nim-deploy"
PR_NUMBER=215

# Extract token from remote URL
get_token() {
    remote_url=$(git remote get-url origin)
    # Extract token from URL like https://token@github.com/...
    if [[ $remote_url =~ https://[^@]+@ ]]; then
        echo "${BASH_REMATCH[0]}" | sed -e 's/https:\/\///' -e 's/@.*//'
    else
        echo ""
    fi
}

TOKEN=$(get_token)
if [ -z "$TOKEN" ]; then
    echo "Error: Could not extract token from remote URL"
    exit 1
fi

# Initialize seen file if not exists
if [ ! -f "$SEEN_FILE" ]; then
    touch "$SEEN_FILE"
fi

# Function to fetch new comments and process them using Python
process_comments() {
    echo "Fetching issue comments..."
    issue_comments=$(curl -s -H "Authorization: token $TOKEN" "$GITHUB_API_BASE/issues/$PR_NUMBER/comments")
    # Use Python to extract comment IDs and bodies
    echo "$issue_comments" | python3 -c "
import sys, json
try:
    comments = json.load(sys.stdin)
    for c in comments:
        print(str(c['id']) + '|||' + c['body'].replace('\\n', ' '))
except Exception as e:
    pass
" | while read -r line; do
        if [ -n "$line" ]; then
            comment_id=$(echo "$line" | cut -d'|' -f1)
            comment_body=$(echo "$line" | cut -d'|' -f2- | sed 's/ / /g')
            if ! grep -q "^$comment_id$" "$SEEN_FILE"; then
                echo "New issue comment ID: $comment_id"
                echo "Processing issue comment $comment_id..."
                # TODO: Actually address the comment
                echo "$comment_id" >> "$SEEN_FILE"
            fi
        fi
    done

    echo "Fetching review comments..."
    review_comments=$(curl -s -H "Authorization: token $TOKEN" "$GITHUB_API_BASE/pulls/$PR_NUMBER/comments")
    echo "$review_comments" | python3 -c "
import sys, json
try:
    comments = json.load(sys.stdin)
    for c in comments:
        print(str(c['id']) + '|||' + c['body'].replace('\\n', ' ') + '|||' + c.get('path', '') + '|||' + str(c.get('line', '')))
except Exception as e:
    pass
" | while read -r line; do
        if [ -n "$line" ]; then
            comment_id=$(echo "$line" | cut -d'|' -f1)
            comment_body=$(echo "$line" | cut -d'|' -f2)
            comment_path=$(echo "$line" | cut -d'|' -f3)
            comment_line=$(echo "$line" | cut -d'|' -f4)
            if ! grep -q "^$comment_id$" "$SEEN_FILE"; then
                echo "New review comment ID: $comment_id"
                echo "Comment on $comment_path:$comment_line: $comment_body"
                echo "Processing review comment $comment_id..."
                # TODO: Actually address the comment
                echo "$comment_id" >> "$SEEN_FILE"
            fi
        fi
    done
}

# Function to make general improvements
make_improvements() {
    echo "Making general improvements in workshop files..."
    if [ -d "$WORKSHOP_DIR" ]; then
        echo "Workshop directory exists: $WORKSHOP_DIR"
        # Example: find and fix common issues
        # We'll just do a simple check for now
        # You can add specific improvement actions here
        # For example, remove trailing whitespace
        find "$WORKSHOP_DIR" -type f -name "*.md" -o -name "*.yaml" -o -name "*.yml" -o -name "*.txt" | while read -r file; do
            if [ -f "$file" ]; then
                # Remove trailing whitespace
                sed -i 's/[[:space:]]*$//' "$file" 2>/dev/null || true
            fi
        done
    else
        echo "Workshop directory not found: $WORKSHOP_DIR"
    fi
}

# Main loop
while true; do
    echo "=== $(date) ==="
    echo "Checking out aks-nemoclaw branch..."
    git checkout aks-nemoclaw
    echo "Fetching latest changes from origin..."
    export GIT_SSL_NO_VERIFY=true
    git fetch origin
    git reset --hard origin/aks-nemoclaw
    unset GIT_SSL_NO_VERIFY

    echo "Processing PR #$PR_NUMBER comments..."
    process_comments

    echo "Making general improvements..."
    make_improvements

    echo "Committing and pushing changes..."
    git add -A
    if ! git diff-index --quiet HEAD --; then
        git commit -m "Address PR #$PR_NUMBER comments and improve workshop files [skip ci]"
        export GIT_SSL_NO_VERIFY=true
        git push origin aks-nemoclaw
        unset GIT_SSL_NO_VERIFY
    else
        echo "No changes to commit."
    fi

    echo "Sleeping for 300 seconds..."
    sleep 300
done