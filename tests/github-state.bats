#!/usr/bin/env bats
# Characterizes skills/catchup/scripts/github-state.sh — prerequisite failures
# and the populated path. Never calls real GitHub: a PATH-shadowing gh stub
# (tests/helpers/stubs/gh) returns fixture data.

load helpers/common

SCRIPT="$BATS_TEST_DIRNAME/../skills/catchup/scripts/github-state.sh"
STUBS="$BATS_TEST_DIRNAME/helpers/stubs"

@test "github-state: missing gh exits 1 with CLI-not-installed error" {
  # Resolve bash now (normal PATH), then run with an empty PATH so `command -v
  # gh` fails. The script exits at the gh check before any external binary.
  bash_bin="$(command -v bash)"
  mkdir -p "$TEST_TEMP_DIR/empty"
  PATH="$TEST_TEMP_DIR/empty" run "$bash_bin" "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: gh CLI not installed"* ]]
}

@test "github-state: unauthenticated gh exits 1 with auth error" {
  GH_STUB_EXIT=1 PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: gh not authenticated (run 'gh auth login')"* ]]
}

@test "github-state: not a GitHub repo exits 1 with repo error" {
  GH_STUB_REPO_FAIL=1 PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: not a GitHub repository"* ]]
}

@test "github-state: populated repo renders all sections" {
  PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== GitHub State for buvis/claude-git-ferry ==="* ]]
  [[ "$output" == *"=== Open Issues ==="* ]]
  [[ "$output" == *"=== Open Pull Requests ==="* ]]
  [[ "$output" == *"=== Active Branches"* ]]
  [[ "$output" == *"=== Releases ==="* ]]
  [[ "$output" == *"=== Failed Workflow Runs ==="* ]]
}
