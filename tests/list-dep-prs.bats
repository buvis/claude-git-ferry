#!/usr/bin/env bats
# Characterizes skills/review-deps-prs/scripts/list-dep-prs.sh — happy, empty,
# organization-repo, bot-login and failed-enumeration paths.

load helpers/common

SCRIPT="$BATS_TEST_DIRNAME/../skills/review-deps-prs/scripts/list-dep-prs.sh"
STUBS="$BATS_TEST_DIRNAME/helpers/stubs"

@test "list-dep-prs: no repos prints the no-repos message and exits 1" {
  # `gh api user/repos` must exit 0 with empty output: a non-zero exit takes
  # the enumeration-failed branch instead of this message.
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
  # repo header is silently skipped (L28-32).
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

@test "list-dep-prs: lists dependency PRs from an organization repo" {
  # user-repos.json holds acme/org-repo, which `gh repo list` (repos.json)
  # never returns: without an owner argument it lists only the account's own.
  PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--- acme/org-repo ---"* ]]
}

@test "list-dep-prs: finds a renovate PR by its app/renovate login" {
  # gh reports bot authors as app/<name>; "Pin dependencies" matches no title
  # pattern, so only the author branch can select it.
  GH_STUB_DEP_AUTHORS=1 PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pin dependencies"* ]]
}

@test "list-dep-prs: finds a dependabot PR by its dependabot[bot] login" {
  GH_STUB_DEP_AUTHORS=1 PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pin jq to 1.7"* ]]
}

@test "list-dep-prs: finds a dependabot PR by its app/dependabot login" {
  GH_STUB_DEP_AUTHORS=1 PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pin actions/checkout digest"* ]]
}

@test "list-dep-prs: failed repo enumeration exits 1 with a message" {
  # A bad token or a rate limit makes `gh api` exit non-zero; `set -e` must
  # not swallow that silently.
  GH_STUB_EXIT=1 PATH="$STUBS:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh api user/repos failed"* ]]
}
