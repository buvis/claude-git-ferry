# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
