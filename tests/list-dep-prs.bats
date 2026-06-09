#!/usr/bin/env bats
# Characterizes skills/review-deps-prs/scripts/list-dep-prs.sh — happy + empty paths.

load helpers/common

SCRIPT="$BATS_TEST_DIRNAME/../skills/review-deps-prs/scripts/list-dep-prs.sh"
STUBS="$BATS_TEST_DIRNAME/helpers/stubs"

@test "list-dep-prs: no repos prints the no-repos message and exits 1" {
  # `gh repo list` must exit 0 with empty output: under `set -e` a non-zero
  # exit would abort at the assignment before the message is printed.
  make_stub_path
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/gh"
  chmod +x "$STUB_BIN/gh"

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No repos found or gh not authenticated"* ]]
}

@test "list-dep-prs: repo with PRs but none matching dep filter produces no repo section" {
  # prs-no-deps.json has a PR by octocat with a plain feature title — no
  # renovate/dependabot author and no dep-matching title pattern.  The jq
  # select() in list-dep-prs.sh yields empty output, so PRS is empty and the
  # repo header is silently skipped (L26-30).
  GH_STUB_NO_DEP_PRS=1 PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Dependency Update PRs ==="* ]]
  [[ "$output" != *"--- buvis/claude-git-ferry ---"* ]]
}

@test "list-dep-prs: populated repo lists the dependency PR under a repo header" {
  # Use the real fixture-backed stub at its own location so it resolves
  # tests/fixtures relative to itself.
  PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Dependency Update PRs ==="* ]]
  [[ "$output" == *"--- buvis/claude-git-ferry ---"* ]]
  [[ "$output" == *"renovate[bot]"* ]]
}
