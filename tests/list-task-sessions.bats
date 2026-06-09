#!/usr/bin/env bats
# Characterizes skills/catchup/scripts/list-task-sessions.sh — each documented result.
#
# The script keys off $HOME. With project arg "/proj" the encoded project dir is
# "-proj" (sed 's|^/|-|' | tr '/.' '-'), so PROJECT_DIR=$HOME/.claude/projects/-proj
# and TASKS_DIR=$HOME/.claude/tasks.

load helpers/common

SCRIPT="$BATS_TEST_DIRNAME/../skills/catchup/scripts/list-task-sessions.sh"
FIX="$BATS_TEST_DIRNAME/fixtures/task-index"

# Echo the fake HOME used by each case.
fake_home() { echo "$TEST_TEMP_DIR/home"; }

@test "list-task-sessions: missing project dir returns no_project_data" {
  home="$(fake_home)"; mkdir -p "$home"
  HOME="$home" run bash "$SCRIPT" /proj
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.error == "no_project_data"'
}

@test "list-task-sessions: missing tasks dir returns no_tasks_dir" {
  home="$(fake_home)"; mkdir -p "$home/.claude/projects/-proj"
  HOME="$home" run bash "$SCRIPT" /proj
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.error == "no_tasks_dir"'
}

@test "list-task-sessions: missing index returns no_index" {
  home="$(fake_home)"
  mkdir -p "$home/.claude/projects/-proj" "$home/.claude/tasks"
  HOME="$home" run bash "$SCRIPT" /proj
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.error == "no_index"'
}

@test "list-task-sessions: invalid JSON index returns index_unreadable" {
  home="$(fake_home)"
  mkdir -p "$home/.claude/projects/-proj" "$home/.claude/tasks"
  printf 'not valid json{' > "$home/.claude/projects/-proj/sessions-index.json"
  HOME="$home" run bash "$SCRIPT" /proj
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.error == "index_unreadable"'
}

@test "list-task-sessions: non-array entries returns schema_unexpected" {
  home="$(fake_home)"
  mkdir -p "$home/.claude/projects/-proj" "$home/.claude/tasks"
  printf '{"entries": "nope"}' > "$home/.claude/projects/-proj/sessions-index.json"
  HOME="$home" run bash "$SCRIPT" /proj
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.error == "schema_unexpected"'
}

@test "list-task-sessions: populated index returns sessions sorted newest first" {
  home="$(fake_home)"
  mkdir -p "$home/.claude/projects/-proj" "$home/.claude/tasks"
  cp "$FIX/sessions-index.json" "$home/.claude/projects/-proj/sessions-index.json"
  cp -R "$FIX/tasks/." "$home/.claude/tasks/"

  HOME="$home" run bash "$SCRIPT" /proj
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.sessions | length == 2'
  echo "$output" | jq -e '.sessions[0].sessionId == "sess-newer"'
  echo "$output" | jq -e '.sessions[0].taskCount == 1'
}
