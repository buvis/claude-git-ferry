# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-08-05

### Added

- **catchup**: catchup now harvests the repo's review files into engram so their findings outlive those files.
- **catchup**: the capsule gains a "Related context" section - catchup refreshes the repo's engram index, queries it at repo and portfolio scope for the session's own topic (branch name plus the wip PRD's title), and records the scored hits with a staleness stamp, so prior work related to what you are about to do is on the page before you start. The section is always written: when engram is unavailable, the session has no topic, or nothing matched, it says so in one line rather than vanishing, because a missing section reads as "nothing related exists". The staleness stamp is taken at portfolio scope so it covers the widest query above it, and the topic - built from a branch name and a PRD title, both of which can contain shell metacharacters - is passed as a quoted variable rather than interpolated into a command string.

## [0.2.2] - 2026-07-19

### Fixed

- **sync-plan-issue**: issue-body update flow is now file-based (`--body-file` + Edit tool). The previous `body=$(...)`/`"$updated_body"` shape cannot work under per-call shells - variables reset between tool calls, so the edit shipped an empty body - and the assignment prefix broke permission matching.

### Added

- **ci**: offline bats test suite characterizing the six helper scripts, gated by `shellcheck -S warning` (covers scripts, test helpers, and `dev/bin/release`) and run on `ubuntu-latest` and `macos-latest` via GitHub Actions on every push and PR.

## [0.2.1] - 2026-06-09

### Fixed

- **catchup**: task restore now fails loud — if Claude Code's `sessions-index.json` layout drifts, `list-task-sessions.sh` returns a distinct `schema_unexpected`/`index_unreadable` error that catchup surfaces in its report, instead of silently restoring nothing.

## [0.2.0] - 2026-05-13

### Changed

- **catchup**: Phase 4 now auto-restores tasks from the most-recent prior session for the current project (silent if none), absorbing the standalone `restore-tasks` skill. Adds `list-task-sessions.sh` and `dump-tasks.sh` under `catchup/scripts/`.

## [0.1.0] - 2026-05-11

### Added

- Initial release with 6 skills:
  - `catchup` — hydrate context before starting work: branch diff, GitHub state, capsule refresh, memory load.
  - `catchup-upstream` — selectively replay upstream commits onto a fork using a merge-graph cursor.
  - `resolve-git-conflicts` — guided resolution for merge, rebase, cherry-pick, and stash conflicts.
  - `watch-ci` — poll GitHub Actions to completion after a push or PR; summarize failures.
  - `sync-plan-issue` — push the active plan summary to a new or existing GitHub issue.
  - `review-deps-prs` — triage Renovate/Dependabot/manual dependency PRs across all repos by severity.
- Skill helper scripts (`catchup/scripts/*.sh`, `review-deps-prs/scripts/list-dep-prs.sh`) reference `${CLAUDE_SKILL_DIR}` for plugin-compatible paths.
