# Dynamic Default-Branch Detection in Catchup

## Overview

### Problem Statement
The `catchup` skill hardcodes `master` as the base branch in roughly fifteen places across `branch-diff.sh`, `github-state.sh`, and `catchup/SKILL.md`. On a repo whose default branch is `main` (the GitHub default since 2020), `branch-diff.sh` hard-errors with "Cannot find master branch", `github-state.sh` reports no unreleased commits and no CI failures (it queries `--branch master`), and the SKILL's `git merge-base origin/master HEAD` commands fail. catchup breaks for most public repos. This is an oversight, not a decision: `catchup-upstream/SKILL.md:34` already says "use whatever branch upstream considers default (usually main or master)."

### Target Users
Anyone running git-ferry on a `main`-default repo (the majority of public repos). The maintainer, whose `master`-default repos must behave exactly as before.

### Success Metrics
- catchup runs end to end on a `main`-default repo: branch-diff produces a diff, github-state reports unreleased commits and CI failures against `main`.
- Zero behavior change on `master`-default repos (master remains the final fallback).
- No hardcoded `master` remains in the catchup runtime path (`branch-diff.sh`, `github-state.sh`, `catchup/SKILL.md` command blocks), verified by grep.

Scope note: this PRD covers the catchup runtime path only, where the breakage is. `dev/bin/release` intentionally pushes `origin master` for this specific repo and is out of scope (maintainer release tooling, not distributed runtime). The `master` mentions in `resolve-git-conflicts/SKILL.md` are illustrative prose, not executable, and are out of scope.

## Functional Decomposition

### Capability: Default-branch resolution
Determine the repo's default branch once, with layered fallbacks.

#### Feature: Detect default branch
- **Description**: Resolve the remote's default branch name.
- **Inputs**: A git repo, optionally a GitHub remote and `gh`.
- **Outputs**: A branch name (e.g. `main`), or `master` as the last-resort fallback.
- **Behavior**: Try `git symbolic-ref --short refs/remotes/origin/HEAD` (strip `origin/`); else `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`; else first existing of `origin/main`, `origin/master`; else `master`.

#### Feature: Base-ref resolution for diffs
- **Description**: branch-diff.sh uses the detected default as its diff base.
- **Inputs**: Detected default branch, current branch.
- **Outputs**: `$BASE` (e.g. `origin/main`) and the printed "Base branch:" line.
- **Behavior**: Replace the master-only lookup; keep the no-remote local fallback.

#### Feature: Default-aware GitHub state
- **Description**: github-state.sh queries the detected default, not literal master.
- **Inputs**: Detected default branch.
- **Outputs**: Unreleased-commit count and default-branch CI failures against the right branch; the "current != default" guard uses the detected name.
- **Behavior**: Substitute the detected default into `git rev-list`, `gh run list --branch`, and the current-branch comparison.

### Capability: Skill instruction alignment
Make the LLM-facing instructions use the detected base.

#### Feature: SKILL.md uses reported base
- **Description**: catchup/SKILL.md stops hardcoding `origin/master` in its merge-base/log commands.
- **Inputs**: The base branch reported by branch-diff.sh.
- **Outputs**: Phase 2 commands and the error-handling table refer to the default branch.
- **Behavior**: Reuse branch-diff.sh's reported base; reword the "On master" table rows to "On the default branch".

## Structural Decomposition

### Repository Structure

```
lib/
└── resolve-base.sh        # Maps to: Detect default branch (shared, sourced; PLUGIN ROOT — see amendment note)
skills/catchup/scripts/
├── branch-diff.sh         # Maps to: Base-ref resolution for diffs
└── github-state.sh        # Maps to: Default-aware GitHub state
skills/catchup/SKILL.md    # Maps to: SKILL.md uses reported base
```

> **Amendment (2026-07-09)**: the shared resolver MUST live at the **plugin root** (`lib/resolve-base.sh`, referenced via `${CLAUDE_PLUGIN_ROOT}/lib/resolve-base.sh`, with a `$(dirname "$0")`-relative fallback for the bats harness where that var is unset), NOT under `skills/catchup/scripts/lib/`. Reason: PRDs 00005 (watch-ci) and 00007 (prune-worktrees) also need default-branch resolution, and no cross-skill path exists today — a resolver buried inside one skill would force each later skill to duplicate it.

### Module: lib (plugin root)
- **Maps to capability**: Default-branch resolution
- **Responsibility**: One place that resolves the default branch with fallbacks.
- **Exports**:
  - `resolve_base_branch()` - prints the resolved branch name; sourced by both scripts

### Module: skills/catchup/scripts (branch-diff.sh, github-state.sh)
- **Maps to capability**: Default-branch resolution
- **Responsibility**: Consume the resolver for diffs and GitHub queries.
- **Exports**:
  - `branch-diff.sh` - branch diff against the detected base
  - `github-state.sh` - GitHub survey against the detected default

### Module: skills/catchup/SKILL.md
- **Maps to capability**: Skill instruction alignment
- **Responsibility**: Instruct the agent to use the detected/reported base, not literal master.
- **Exports**: catchup workflow prose (Phase 2 commands, error-handling table)

## Dependency Graph

### Foundation Layer (Phase 0)
No dependencies - built first. Verification reuses the 00001 test harness (landed on master: `tests/` bats suite, gh stub, fixtures, two-OS CI). Note the existing tests characterize the master-hardcoded behavior (e.g. `branch-diff: missing master base exits 1 with ERROR`); they must be updated alongside the scripts, and `tests/README.md` branch tables re-enumerated.

- **lib/resolve-base.sh**: the detection function with fallbacks.

### Core Layer (Phase 1)
- **branch-diff.sh, github-state.sh**: Depend on [lib/resolve-base.sh].

### Integration Layer (Phase 2)
- **catchup/SKILL.md**: Depends on [branch-diff.sh] (reuses its reported base).

## Implementation Phases

### Phase 0: Foundation
**Goal**: A single, tested default-branch resolver.

**Tasks**:
- [ ] Write failing tests first for the resolver: main-default, master-default, no-remote (TDD) (no deps) - Acceptance: tests fail before the function exists.
- [ ] Write `lib/resolve-base.sh` with the four-tier fallback (no deps) - Acceptance: returns `main` on a main-default fixture, `master` on a master-default fixture, `master` when no remote and neither ref exists.

**Exit Criteria**: Resolver passes its tests on main-default, master-default, and no-remote fixtures.

### Phase 1: Core
**Goal**: Thread the resolver through both scripts.

**Tasks**:
- [ ] branch-diff.sh sources the resolver, sets `$BASE` from it, keeps the local fallback; update branch-diff tests (depends on: Phase 0) - Acceptance: produces a diff on a main-default feature branch; master-default output unchanged; `tests/README.md` branch table updated.
- [ ] github-state.sh uses the resolver for `rev-list`, `gh run list --branch`, and the current-branch guard; update github-state tests (depends on: Phase 0) - Acceptance: unreleased count and default-branch failures query the detected default; `tests/README.md` branch table updated.
- [ ] Absorb the merge-base guard (assessment G6): `branch-diff.sh:36` `FORK_POINT=$(git merge-base "$BASE" HEAD)` dies under `set -e` with no output on shallow clones or unrelated histories — append `|| { echo "ERROR: no merge base with $BASE" >&2; exit 1; }`; add a bats case (depends on: Phase 0) - Acceptance: an unrelated-history fixture exits 1 with the ERROR line on stderr instead of a silent death.

**Exit Criteria**: Both scripts work on a main-default repo; master-default behavior unchanged where it matters.

### Phase 2: Integration
**Goal**: Align the skill instructions.

**Tasks**:
- [ ] Update catchup/SKILL.md Phase 2 to reuse the base reported by branch-diff.sh instead of `origin/master`; reword the error-handling "master" rows to "default branch" (depends on: Phase 1) - Acceptance: no literal `origin/master` in SKILL.md command blocks; instructions read correctly for a main repo.
- [ ] CHANGELOG `Fixed` entry (depends on: Phase 1) - Acceptance: entry present under Unreleased.

**Exit Criteria**: grep finds no hardcoded `master` in the catchup runtime path (excluding the documented exclusions).

## Test Strategy

### Critical Scenarios
- **Happy path**: main-default repo, feature branch -> branch-diff bases on `origin/main`, prints a diff.
- **Happy path**: master-default repo -> identical output to today.
- **Edge case**: `git symbolic-ref refs/remotes/origin/HEAD` unset -> falls back to `gh`, then to ref existence, then to master.
- **Edge case**: no remote -> local default used, no error.
- **Error case**: neither main nor master exists and no remote -> clear error, not a silent empty diff.
- **Error case**: no merge base between HEAD and the resolved base (shallow clone / unrelated histories) -> exit 1 with an explicit ERROR line, never a silent `set -e` abort.

## Risks

- **`origin/HEAD` is often unset** on older or freshly-fetched clones: the `gh` and ref-existence fallbacks cover it; `git remote set-head origin -a` is not assumed.
- **Resolver adds a `gh` call**: only on the fallback path; the fast path is pure git, so no latency on the common case.
- **Two PRDs touch the same files**: 00002 and 00003 both edit `github-state.sh` and `catchup/SKILL.md`. Run sequentially, 00002 before 00003, to avoid conflicts.
- **Maintainer convention**: the global "master everywhere" rule is about the maintainer's own repos; this plugin is distributed, so `main` support is required. master stays the final fallback, so nothing regresses for the maintainer.
