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

@test "github-state: populated repo renders fixture issue #42 and PR #101" {
  PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # Issue #42 appears in the Recent Issues section
  [[ "$output" == *"### #42 Sample open issue"* ]]
  # PR #101 appears in the Open Pull Requests section
  [[ "$output" == *"#101 chore(deps): bump actions/checkout from 3 to 4"* ]]
}

@test "github-state: populated repo renders release v0.2.1" {
  PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v0.2.1 (published: 2026-05-15"* ]]
}

@test "github-state: active-branch age filter includes recent branch and excludes old branch" {
  # Point a remote ref at HEAD (committed during setup, committerdate is today —
  # well within the 14-day window).
  head_sha=$(git -C "$TEST_TEMP_DIR" rev-parse HEAD)
  git -C "$TEST_TEMP_DIR" update-ref refs/remotes/origin/active-branch "$head_sha"

  # Create a commit with a committer date 30 days in the past so it falls outside
  # the 14-day window, then point a remote ref at it.
  old_date="$(date -v-30d "+%Y-%m-%dT%H:%M:%S" 2>/dev/null || date -d "30 days ago" "+%Y-%m-%dT%H:%M:%S")"
  GIT_COMMITTER_DATE="$old_date" GIT_AUTHOR_DATE="$old_date" \
    git -C "$TEST_TEMP_DIR" commit --allow-empty -q -m "old commit"
  old_sha=$(git -C "$TEST_TEMP_DIR" rev-parse HEAD)
  git -C "$TEST_TEMP_DIR" update-ref refs/remotes/origin/old-branch "$old_sha"

  # Restore master to the original commit so CURRENT_BRANCH stays on master.
  git -C "$TEST_TEMP_DIR" reset -q --hard "$head_sha"

  PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # The recent branch must appear in the Active Branches section (L76)
  [[ "$output" == *"origin/active-branch"* ]]
  # The old branch must not appear (filtered out by the 14-day cutoff, L75)
  [[ "$output" != *"origin/old-branch"* ]]
}

@test "github-state: non-master branch failure block renders run list and error-log header" {
  # Check out a non-master branch so CURRENT_BRANCH != master, triggering L124-145.
  git -C "$TEST_TEMP_DIR" checkout -q -b feature/add-tests

  GH_STUB_BRANCH_FAIL=1 PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # Section header for the current branch (L125)
  [[ "$output" == *"--- feature/add-tests failures ---"* ]]
  # Run list line from the fixture (L130-131): databaseId=9001, workflowName=CI
  [[ "$output" == *"Run 9001: CI"* ]]
  # Error-log header for the most recent failure (L137)
  [[ "$output" == *"--- Error log for most recent feature/add-tests failure (run 9001) ---"* ]]
}
