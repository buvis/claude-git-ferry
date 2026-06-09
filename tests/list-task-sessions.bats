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

@test "list-task-sessions: entries with no sessionId/modified return schema_unexpected" {
  home="$(fake_home)"
  mkdir -p "$home/.claude/projects/-proj" "$home/.claude/tasks"
  # Entries array exists but entries carry neither sessionId nor modified — the
  # third schema check (L40-43) fires.
  printf '{"entries": [{"foo": "bar"}]}' > "$home/.claude/projects/-proj/sessions-index.json"
  HOME="$home" run bash "$SCRIPT" /proj
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.error == "schema_unexpected"'
  echo "$output" | jq -e '.detail | test("sessionId/modified")'
}

@test "list-task-sessions: session with zero task files is excluded from output" {
  home="$(fake_home)"
  mkdir -p "$home/.claude/projects/-proj" "$home/.claude/tasks"
  cp "$FIX/sessions-index.json" "$home/.claude/projects/-proj/sessions-index.json"
  # Copy only sess-newer tasks; leave sess-older with no task files.
  mkdir -p "$home/.claude/tasks/sess-newer"
  cp "$FIX/tasks/sess-newer/task-1.json" "$home/.claude/tasks/sess-newer/task-1.json"

  HOME="$home" run bash "$SCRIPT" /proj
  [ "$status" -eq 0 ]
  # Only sess-newer has tasks; sess-older is filtered out (count == 0).
  echo "$output" | jq -e '.sessions | length == 1'
  echo "$output" | jq -e '.sessions[0].sessionId == "sess-newer"'
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
