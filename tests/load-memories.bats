#!/usr/bin/env bats
# Characterizes skills/catchup/scripts/load-memories.sh — happy + empty paths.
#
# MEMORY_DIR = $HOME/.claude/projects/$(pwd | tr '/.' '-')/memory
# (note: the script does NOT apply the leading-slash sed that
# list-task-sessions.sh does — it encodes pwd with `tr '/.' '-'` only).

load helpers/common

SCRIPT="$BATS_TEST_DIRNAME/../skills/catchup/scripts/load-memories.sh"

# Build the memory dir path the script will derive for the current pwd + fake HOME.
mem_dir() {
  local enc
  enc="$(pwd | tr '/.' '-')"
  echo "$TEST_TEMP_DIR/home/.claude/projects/$enc/memory"
}

@test "load-memories: no memory dir produces no output and exits 0" {
  HOME="$TEST_TEMP_DIR/home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "load-memories: only MEMORY.md is skipped, no output, exits 0" {
  mem="$(mem_dir)"; mkdir -p "$mem"
  printf '# index\n' > "$mem/MEMORY.md"

  HOME="$TEST_TEMP_DIR/home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "load-memories: emits each memory file header but skips MEMORY.md" {
  mem="$(mem_dir)"; mkdir -p "$mem"
  printf 'hello memory\n' > "$mem/foo.md"
  printf '# index\n' > "$mem/MEMORY.md"

  HOME="$TEST_TEMP_DIR/home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--- foo.md ---"* ]]
  [[ "$output" == *"hello memory"* ]]
  [[ "$output" != *"--- MEMORY.md ---"* ]]
}
