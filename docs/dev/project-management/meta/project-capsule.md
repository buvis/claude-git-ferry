# Project Capsule: git-ferry

Generated: 2026-06-09

## Key Invariants

- **Runtime must not hardcode `master`.** git-ferry is published MIT on the buvis marketplace and runs on other people's repos, where `main` is the GitHub default. Detect the default branch dynamically (`git symbolic-ref refs/remotes/origin/HEAD` → `gh repo view` → ref existence → `master` fallback). This overrides the global "master everywhere" rule. Currently VIOLATED in `branch-diff.sh` (lines 16, 22-24) and `github-state.sh` (master-specific failure queries) — PRD 00002 fixes this. Exception: `dev/bin/release` is maintainer-only and may keep `git push origin master`.
- **Helper scripts are pure shell, offline-testable.** The six helpers under `skills/**/scripts/` produce deterministic stdout from git/gh/filesystem state. `gh`-coupled scripts must be testable via a PATH-shadowing stub — never call real GitHub in tests.
- **`list-task-sessions.sh` reads undocumented Claude Code internals** (`sessions-index.json` `.entries[]`, `~/.claude/tasks/<id>/*.json`). It fails LOUD (`schema_unexpected`, `index_unreadable`) when that layout drifts, vs benign skips (`no_project_data`, `no_tasks_dir`, `no_index`). v0.2.1 added this.

## Architecture Decisions

- **Plugin = skills only.** No application code. Each skill is a `SKILL.md` plus optional `scripts/` and `references/`. Six skills: catchup, catchup-upstream, resolve-git-conflicts, review-deps-prs, sync-plan-issue, watch-ci.
- **Deterministic work lives in bash scripts, not skill prose** (per ai-app-design rule): catchup delegates diff/github-state/memory-loading/task-restore to scripts.
- **Releases via `dev/bin/release`**: bumps version in 3 places (plugin.json, self marketplace.json, central buvis-plugins marketplace.json), stamps CHANGELOG, commits, tags, pushes both repos. Already runs `test_*.py` if any exist (none yet).

## Component Boundaries

- `skills/catchup/scripts/`: branch-diff.sh, github-state.sh, load-memories.sh, list-task-sessions.sh, dump-tasks.sh (5 of the 6 tested scripts).
- `skills/review-deps-prs/scripts/list-dep-prs.sh`: the 6th tested script.
- `dev/bin/release`: maintainer tooling (in shellcheck scope; preflight only looks for `test_*.py`, so it does NOT run the bats suite — gap, PRD 00004).
- `tests/`: 33 bats tests, vendored bats-core v1.11.0 submodule, gh PATH stub, fixtures. Coverage by hand-enumerated branch tables in `tests/README.md` (80-100% per script) — those tables must be re-enumerated whenever script branches change.
- `.github/workflows/ci.yml`: shellcheck + bats on ubuntu + macos matrix.

## Active Work

Autopilot batch 202606091450:
- [x] 00001-script-tests-and-ci — DONE on master (33 tests, CI green, badge, coverage docs); moved to done/ 2026-06-09.
- [ ] 00002-dynamic-default-branch — fix hardcoded `master` in runtime scripts (backlog; run before 00003)
- [ ] 00003-failloud-github-state (backlog; shares files with 00002, run after)

New PRDs 00004-00006 created 2026-06-09 (release-pipeline hardening, watch-ci poll script, plugin consistency lint).

## GitHub State

- 0 open issues, 0 open PRs. Only `origin/master` branch active.
- 2026-06-09: pushed 19 local-only commits (the whole 00001 test/CI batch had never been pushed); first-ever CI run completed green (run 27234584156).
- No releases published on GitHub (despite v0.2.1 tag). `dev/bin/release` tags and pushes but never runs `gh release create` — PRD 00004.

## Project Health

- Working tree clean; `.gitignore` now covers `dev/local/` and `.serena/`.
- All 33 bats tests green locally (2026-06-09). One known uncovered branch: github-state.sh branch 10 (master-failures non-empty path).
- No security/dependency advisories surfaced.

## Project Memories

- See `[[distributed-plugin-supports-main]]`: runtime must support `main`-default repos; never hardcode `master` in plugin runtime code.
