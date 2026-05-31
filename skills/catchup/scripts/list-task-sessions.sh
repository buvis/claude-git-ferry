#!/bin/bash
# List sessions that have persisted tasks for the current project.
# Output: {"sessions": [{sessionId, summary, modified, taskCount}, ...]}
#   sorted by modified (most recent first), or {"error": ...} if unavailable.

set -e

PROJECT_PATH="${1:-$(pwd)}"
TASKS_DIR="$HOME/.claude/tasks"
# Encode path: /Users/bob/foo.bar -> -Users-bob-foo-bar
PROJECT_DIR="$HOME/.claude/projects/$(echo "$PROJECT_PATH" | sed 's|^/|-|' | tr '/.' '-')"
INDEX_FILE="$PROJECT_DIR/sessions-index.json"

[[ -d "$PROJECT_DIR" ]] || { echo '{"error": "no_project_data"}'; exit 1; }
[[ -d "$TASKS_DIR" ]]   || { echo '{"error": "no_tasks_dir"}'; exit 1; }
[[ -f "$INDEX_FILE" ]]  || { echo '{"error": "no_index"}'; exit 1; }

# Emit one session object per index entry (sorted newest first), keeping only
# those with at least one task file. taskCount comes from the shell, not jq.
jq -c '.entries | sort_by(.modified) | reverse | .[]
       | {sessionId, summary: (.summary // "No summary"), modified}' "$INDEX_FILE" \
| while read -r session; do
    session_id=$(echo "$session" | jq -r '.sessionId')
    count=$(ls -1 "$TASKS_DIR/$session_id"/*.json 2>/dev/null | wc -l | tr -d ' ')
    [[ "$count" -gt 0 ]] && echo "$session" | jq -c --argjson c "$count" '.taskCount = $c'
done \
| jq -s '{sessions: .}'
