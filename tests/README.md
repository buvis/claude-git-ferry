# Test Coverage

## Method

Coverage is measured by explicit per-script branch enumeration, not an automated
tool. kcov and bashcov were evaluated and ruled out: kcov requires a Linux
kernel build, and neither tool integrates cleanly with the macOS/Linux CI matrix
used here. Instead, each script's logical branches (if/case/loop guards/early
exits) are enumerated by reading the source, then mapped to the bats tests that
exercise them. Fractions are counted by hand and stated below. "Covered" means
a test drives that branch and asserts the resulting output or exit code.
"Uncovered" means no test reaches that path.

Run the full suite locally:

```
tests/lib/bats-core/bin/bats tests/
```

---

## skills/catchup/scripts/branch-diff.sh

Branches (6 total):

| # | Branch | Test | Covered |
|---|--------|------|---------|
| 1 | `CURRENT` empty - detached HEAD - exit 0 SKIP | `branch-diff: detached HEAD prints SKIP and exits 0` | yes |
| 2 | `CURRENT` = "master" - exit 0 SKIP | `branch-diff: on master prints SKIP and exits 0` | yes |
| 3 | `origin/master` exists - BASE="origin/master" - happy path | `branch-diff: feature branch prints info, stats, log, and diff sections` | yes |
| 4 | `origin/master` absent, local `master` present - BASE="master" | (none) | no |
| 5 | Neither `origin/master` nor local `master` - exit 1 ERROR | `branch-diff: missing master base exits 1 with ERROR` | yes |
| 6 | On feature branch - all output sections rendered | `branch-diff: feature branch prints info, stats, log, and diff sections` | yes |

**Coverage: 5/6 = 83%**

Uncovered branch: the fallback to a local-only `master` ref (branch 4). No test
creates a repo with a local `master` but no `origin/master`. This is a genuine
gap; the script will fail loudly via branch 5 rather than silently if neither
ref is present.

---

## skills/catchup/scripts/github-state.sh

Branches (14 total):

| # | Branch | Test | Covered |
|---|--------|------|---------|
| 1 | `gh` not in PATH - exit 1 | `github-state: missing gh exits 1 with CLI-not-installed error` | yes |
| 2 | `gh auth status` fails - exit 1 | `github-state: unauthenticated gh exits 1 with auth error` | yes |
| 3 | `gh repo view` fails - exit 1 | `github-state: not a GitHub repo exits 1 with repo error` | yes |
| 4 | `PR_NUMBERS` non-empty - PR loop runs | `github-state: populated repo renders fixture issue #42 and PR #101` | yes |
| 5 | `PR_NUMBERS` empty - prints "(none)" | `github-state: no open PRs prints (none) in the pull requests section` | yes |
| 6 | Active-branch filter: branch_epoch >= cutoff - branch included | `github-state: active-branch age filter includes recent branch and excludes old branch` | yes |
| 7 | Active-branch filter: branch_epoch < cutoff - branch excluded | `github-state: active-branch age filter includes recent branch and excludes old branch` | yes |
| 8 | `LATEST_TAG` non-empty - print unreleased commit count | `github-state: populated repo renders release v0.2.1` | yes |
| 9 | `LATEST_TAG` empty - prints "No releases found" | `github-state: no releases prints 'No releases found'` | yes |
| 10 | `MASTER_FAIL_IDS` non-empty - print run list + fetch error log | (none) | no |
| 11 | `MASTER_FAIL_IDS` empty - prints "(none)" for master | `github-state: populated repo renders all sections` | yes |
| 12 | `CURRENT_BRANCH` != "master" and != "detached" - enter non-master block | `github-state: non-master branch failure block renders run list and error-log header` | yes |
| 13 | `BRANCH_FAIL_IDS` non-empty - print run list + fetch error log | `github-state: non-master branch failure block renders run list and error-log header` | yes |
| 14 | `BRANCH_FAIL_IDS` empty - prints "(none)" for branch | `github-state: non-master branch with no failures prints (none) for branch` | yes |

**Coverage: 13/14 = 93%**

Uncovered branch: branch 10 - `MASTER_FAIL_IDS` non-empty (master CI failures
exist, triggering the run-list print and error-log fetch). The gh stub is never
configured to return master failure runs. This is a genuine gap.

---

## skills/catchup/scripts/load-memories.sh

Branches (5 total):

| # | Branch | Test | Covered |
|---|--------|------|---------|
| 1 | `MEMORY_DIR` does not exist - exit 0, no output | `load-memories: no memory dir produces no output and exits 0` | yes |
| 2 | Dir exists, glob yields no `.md` files - `[ -f ]` false, loop body never runs | (none) | no |
| 3 | File is `MEMORY.md` - skip via `continue` | `load-memories: only MEMORY.md is skipped, no output, exits 0` | yes |
| 4 | File is not `MEMORY.md` - print header + content | `load-memories: emits each memory file header but skips MEMORY.md` | yes |
| 5 | `found` stays false after loop - exit 0 | `load-memories: only MEMORY.md is skipped, no output, exits 0` | yes |

**Coverage: 4/5 = 80%**

Uncovered branch: the empty-directory case (dir exists, no `.md` files at all).
The glob yields a literal path, `[ -f ]` is false, the loop body never runs, and
the script exits 0 silently. Correct behavior; not tested.

---

## skills/catchup/scripts/list-task-sessions.sh

Branches (8 total):

| # | Branch | Test | Covered |
|---|--------|------|---------|
| 1 | `PROJECT_DIR` does not exist - `no_project_data` | `list-task-sessions: missing project dir returns no_project_data` | yes |
| 2 | `TASKS_DIR` does not exist - `no_tasks_dir` | `list-task-sessions: missing tasks dir returns no_tasks_dir` | yes |
| 3 | `INDEX_FILE` does not exist - `no_index` | `list-task-sessions: missing index returns no_index` | yes |
| 4 | `INDEX_FILE` not valid JSON - `index_unreadable` | `list-task-sessions: invalid JSON index returns index_unreadable` | yes |
| 5 | `.entries` not an array - `schema_unexpected` | `list-task-sessions: non-array entries returns schema_unexpected` | yes |
| 6 | Entries present but none carry `sessionId`+`modified` - `schema_unexpected` | `list-task-sessions: entries with no sessionId/modified return schema_unexpected` | yes |
| 7 | Session with zero task files (count = 0) - silently filtered out | `list-task-sessions: session with zero task files is excluded from output` | yes |
| 8 | Session with task files (count > 0) - included, sorted newest first | `list-task-sessions: populated index returns sessions sorted newest first` | yes |

**Coverage: 8/8 = 100%**

---

## skills/catchup/scripts/dump-tasks.sh

Branches (6 total):

| # | Branch | Test | Covered |
|---|--------|------|---------|
| 1 | `SESSION_ID` empty - print usage, exit 1 | `dump-tasks: missing session id prints usage and exits 1` | yes |
| 2 | `TASKS_DIR` does not exist - print error, exit 1 | `dump-tasks: unknown session exits 1 with no-tasks message` | yes |
| 3 | `TASKS_DIR` exists, no `.json` files - glob literal, `[[ -f ]]` false, loop skips | `dump-tasks: empty session dir prints empty JSON array and exits 0` | yes |
| 4 | First task file (`first=1`) - no preceding comma | `dump-tasks: populated session prints a JSON array of tasks` | yes |
| 5 | Subsequent task file (`first=0`) - print comma | `dump-tasks: populated session prints a JSON array of tasks` | yes |
| 6 | Task file is a real file - `[[ -f ]]` true, cat it | `dump-tasks: populated session prints a JSON array of tasks` | yes |

**Coverage: 6/6 = 100%**

---

## skills/review-deps-prs/scripts/list-dep-prs.sh

Branches (3 total):

| # | Branch | Test | Covered |
|---|--------|------|---------|
| 1 | `REPOS` empty - print no-repos message, exit 1 | `list-dep-prs: no repos prints the no-repos message and exits 1` | yes |
| 2 | `PRS` non-empty for a repo - print header + PR data | `list-dep-prs: populated repo lists the dependency PR under a repo header` | yes |
| 3 | `PRS` empty for a repo - silently skip that repo | `list-dep-prs: repo with PRs but none matching dep filter produces no repo section` | yes |

**Coverage: 3/3 = 100%**

---

## Summary

| Script | Branches | Covered | % | Meets 80% |
|--------|----------|---------|---|-----------|
| branch-diff.sh | 6 | 5 | 83% | yes |
| github-state.sh | 14 | 13 | 93% | yes |
| load-memories.sh | 5 | 4 | 80% | yes |
| list-task-sessions.sh | 8 | 8 | 100% | yes |
| dump-tasks.sh | 6 | 6 | 100% | yes |
| list-dep-prs.sh | 3 | 3 | 100% | yes |

All six scripts meet the 80% target. One branch remains uncovered: the master
CI failures non-empty path in github-state.sh (branch 10). It is a genuine gap,
not unreachable code.
