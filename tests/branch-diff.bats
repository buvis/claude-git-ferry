#!/usr/bin/env bats
# Characterizes skills/catchup/scripts/branch-diff.sh — current observable behavior.

load helpers/common

SCRIPT="$BATS_TEST_DIRNAME/../skills/catchup/scripts/branch-diff.sh"

@test "branch-diff: on master prints SKIP and exits 0" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP: On base branch (master), no branch diff needed"* ]]
}

@test "branch-diff: feature branch prints info, stats, log, and diff sections" {
  git checkout -q -b feature
  echo "change" > file.txt
  git add file.txt
  git commit -q -m "feature change"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Branch Info ==="* ]]
  [[ "$output" == *"=== Changed Files ==="* ]]
  [[ "$output" == *"=== Diff Stats ==="* ]]
  [[ "$output" == *"=== Commit History ==="* ]]
  [[ "$output" == *"=== Full Diff ==="* ]]
}

@test "branch-diff: detached HEAD prints SKIP and exits 0" {
  sha="$(git rev-parse HEAD)"
  git checkout -q "$sha"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP: Detached HEAD state (commit "* ]]
}

@test "branch-diff: missing master base exits 1 with ERROR" {
  git checkout -q -b feature
  git branch -D master

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: Cannot find master branch"* ]]
}
