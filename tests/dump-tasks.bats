#!/usr/bin/env bats
# Characterizes skills/catchup/scripts/dump-tasks.sh — happy + empty/error paths.
# The script reads $HOME/.claude/tasks/$SESSION_ID/*.json.

load helpers/common

SCRIPT="$BATS_TEST_DIRNAME/../skills/catchup/scripts/dump-tasks.sh"

@test "dump-tasks: missing session id prints usage and exits 1" {
  HOME="$TEST_TEMP_DIR/home" run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: dump-tasks.sh <session-id>"* ]]
}

@test "dump-tasks: unknown session exits 1 with no-tasks message" {
  mkdir -p "$TEST_TEMP_DIR/home"
  HOME="$TEST_TEMP_DIR/home" run bash "$SCRIPT" nosuch
  [ "$status" -eq 1 ]
  [[ "$output" == *"No tasks found for session: nosuch"* ]]
}

@test "dump-tasks: empty session dir prints empty JSON array and exits 0" {
  sess="$TEST_TEMP_DIR/home/.claude/tasks/emptysess"
  mkdir -p "$sess"

  HOME="$TEST_TEMP_DIR/home" run bash "$SCRIPT" emptysess
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == []'
}

@test "dump-tasks: populated session prints a JSON array of tasks" {
  sess="$TEST_TEMP_DIR/home/.claude/tasks/sess1"
  mkdir -p "$sess"
  printf '{"id": "1"}' > "$sess/a.json"
  printf '{"id": "2"}' > "$sess/b.json"

  HOME="$TEST_TEMP_DIR/home" run bash "$SCRIPT" sess1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type == "array"'
  echo "$output" | jq -e 'length == 2'
}
