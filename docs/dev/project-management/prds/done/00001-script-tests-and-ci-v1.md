# Shell Helper Test Suite and CI

## Overview

### Problem Statement
git-ferry ships six deterministic bash helper scripts (`branch-diff.sh`, `github-state.sh`, `load-memories.sh`, `list-task-sessions.sh`, `dump-tasks.sh`, `list-dep-prs.sh`) with zero automated tests and no CI. The v0.2.1 fix ("fail loud when task-restore index schema drifts") was a reactive patch for exactly the regression class a test would catch up front. The scripts carry real edge logic: macOS-vs-GNU `date` fallbacks (`github-state.sh:73-74`), JSON parsing of Claude's task index, branch-age filtering. A refactor or a platform change breaks any of it silently. The plugin even ships a `watch-ci` skill, yet the repo it lives in has no CI of its own.

### Target Users
The plugin maintainer and contributors, who need a safety net before changing scripts. Indirectly, every git-ferry user who relies on `catchup` not breaking quietly.

### Success Metrics
- `shellcheck -S warning` passes clean on all six scripts plus `dev/bin/release`.
- bats suite exercises each script's branches; coverage of script logic >= 80% (project rule).
- CI runs shellcheck + bats on every push and PR, green on the default branch.
- CI matrix runs on `ubuntu-latest` and `macos-latest`, so both `date` code paths execute for real.

## Functional Decomposition

### Capability: Automated script verification
Lint and behavioral testing of the bash helpers, fully offline.

#### Feature: Shell lint gate
- **Description**: Run shellcheck across every `*.sh` and fail on warnings.
- **Inputs**: All scripts under `skills/**/scripts/` and `dev/bin/`.
- **Outputs**: Pass/fail with per-line diagnostics.
- **Behavior**: `shellcheck -S warning`; zero findings required to pass.

#### Feature: Behavioral test suite
- **Description**: bats tests asserting each script's observable output per branch.
- **Inputs**: A bats runner, a temp git repo per test, a stubbed `gh`.
- **Outputs**: Test pass/fail and assertion diagnostics.
- **Behavior**: Arrange a fixture repo/state, run the script, assert on stdout and exit code.

#### Feature: Fixtures and stubs
- **Description**: Reusable scaffolding: temp git repos, a `gh` stub on PATH, canned JSON, a fake task index.
- **Inputs**: Fixture data files.
- **Outputs**: An isolated environment per test.
- **Behavior**: `setup()` builds a temp repo and prepends a stub dir to PATH; `teardown()` removes it.

### Capability: Continuous integration
Run the lint gate and test suite automatically.

#### Feature: CI workflow
- **Description**: GitHub Actions workflow running lint + bats on a two-OS matrix.
- **Inputs**: `push` and `pull_request` events.
- **Outputs**: Status checks.
- **Behavior**: Install shellcheck + bats, run both, on `ubuntu-latest` and `macos-latest`.

## Structural Decomposition

### Repository Structure

```
tests/                          # Maps to: Automated script verification
├── helpers/
│   ├── common.bash             # setup/teardown, temp repo, PATH stub dir
│   └── stubs/
│       └── gh                  # fake gh: emits fixtures JSON, configurable exit code
├── fixtures/
│   ├── issues.json
│   ├── prs.json
│   └── task-index/             # sample Claude task index + task json
├── branch-diff.bats            # Maps to: branch-diff.sh
├── github-state.bats           # Maps to: github-state.sh
├── list-task-sessions.bats     # Maps to: list-task-sessions.sh
├── dump-tasks.bats             # Maps to: dump-tasks.sh
├── load-memories.bats          # Maps to: load-memories.sh
└── list-dep-prs.bats           # Maps to: list-dep-prs.sh
.github/
└── workflows/
    └── ci.yml                  # Maps to: Continuous integration
```

### Module: tests
- **Maps to capability**: Automated script verification
- **Responsibility**: Assert each helper script's behavior per branch, offline.
- **Exports**:
  - `*.bats` files - one suite per script
  - `helpers/common.bash` - shared `setup`/`teardown`, temp-repo and PATH-stub helpers
  - `helpers/stubs/gh` - PATH-shadowing fake `gh`
  - `fixtures/*` - canned API JSON and task-index samples

### Module: .github/workflows
- **Maps to capability**: Continuous integration
- **Responsibility**: Run lint + tests on push/PR across two OSes.
- **Exports**:
  - `ci.yml` - the workflow

## Dependency Graph

### Foundation Layer (Phase 0)
No dependencies - built first.

- **tests/helpers + tests/fixtures**: temp-repo builder, `gh` stub, canned data. Everything else needs this.

### Core Layer (Phase 1)
- **tests/*.bats**: Depends on [tests/helpers, tests/fixtures]. One suite per script.

### Integration Layer (Phase 2)
- **.github/workflows/ci.yml**: Depends on [tests/*.bats, shellcheck]. Wires lint + tests into CI.

## Implementation Phases

### Phase 0: Foundation
**Goal**: Offline test scaffolding any suite can reuse.

**Tasks**:
- [ ] Add bats-core (git submodule under `tests/lib/` or a pinned setup action) and a `bats tests/` entrypoint (no deps) - Acceptance: `bats tests/` runs and reports 0 tests.
- [ ] Write `tests/helpers/common.bash` with temp-repo `setup`/`teardown` and a PATH-stub helper (no deps) - Acceptance: a smoke test creating a temp repo passes and leaves no temp dirs behind.
- [ ] Write `tests/helpers/stubs/gh` plus `tests/fixtures/*` (no deps) - Acceptance: the stub `gh issue list ...` prints fixture JSON; an env var makes it exit non-zero.

**Exit Criteria**: A trivial bats test using the temp repo and gh stub passes locally.

### Phase 1: Core
**Goal**: Characterize current behavior of every script.

**Tasks**:
- [ ] `branch-diff.bats`: on-master SKIP, feature-branch diff, detached HEAD, missing base (depends on: Phase 0) - Acceptance: all four cases asserted on stdout + exit code.
- [ ] `list-task-sessions.bats`: each documented result (`no_project_data`, `no_tasks_dir`, `no_index`, `schema_unexpected`, `index_unreadable`, populated) (depends on: Phase 0) - Acceptance: each path returns the documented JSON.
- [ ] `dump-tasks.bats`, `load-memories.bats`, `list-dep-prs.bats`: happy + empty paths (depends on: Phase 0) - Acceptance: output shape asserted.
- [ ] `github-state.bats`: gh missing, gh unauthenticated, not-a-repo, populated repo via stub (depends on: Phase 0) - Acceptance: prerequisite failures exit non-zero with the documented message; populated case renders issues/PRs/releases.
- [ ] Make `shellcheck -S warning` clean; fix or justify each finding (depends on: Phase 0) - Acceptance: shellcheck exits 0.

**Exit Criteria**: `bats tests/` green locally; shellcheck clean; script-logic coverage >= 80%.

### Phase 2: Integration
**Goal**: Run the gate automatically.

**Tasks**:
- [ ] Add `.github/workflows/ci.yml`: matrix [ubuntu-latest, macos-latest]; install shellcheck + bats; run lint then `bats tests/` (depends on: Phase 1) - Acceptance: workflow green on both OSes for a test PR.
- [ ] Add a CI status badge to README and a CHANGELOG `Added` entry (depends on: Phase 1) - Acceptance: README shows the badge; CHANGELOG updated under Unreleased.

**Exit Criteria**: CI green on the default branch; checks run on every push/PR.

## Test Strategy

### Critical Scenarios
- **Happy path**: populated repo via gh stub -> github-state renders issues, PRs, releases, CI runs.
- **Happy path**: feature branch with commits -> branch-diff prints stats, commit log, full diff.
- **Edge case**: macOS vs GNU `date` -> branch-age filter yields the same set on both CI OSes.
- **Edge case**: detached HEAD -> branch-diff prints SKIP, exit 0.
- **Error case**: `gh` absent or unauthenticated -> github-state exits non-zero with the documented message.
- **Error case**: task index schema drift -> list-task-sessions returns `{"error":"schema_unexpected"}`.

## Risks

- **github-state.sh is network/gh-coupled**: mitigate with a PATH-shadowing `gh` stub returning fixture JSON and a configurable exit code; never call real GitHub in tests.
- **Date portability is the bug most likely to hide**: run the CI matrix on ubuntu-latest and macos-latest so both `date` branches execute.
- **bats availability for contributors**: vendor bats-core as a submodule or pin a setup action; document the one-line local install.
- **Bash coverage tooling is weak**: use `kcov` if practical; otherwise track branch coverage by explicit case enumeration per script and state the method in the completion note (fail loud about how coverage was measured).
