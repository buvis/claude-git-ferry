# Fail-Loud GitHub State Reporting

## Overview

### Problem Statement
`github-state.sh` sets `set -e` but defeats it with about twenty trailing `2>/dev/null || true`, `|| echo "(none)"`, and `|| echo "?"` guards. A failed `gh` call and a genuinely empty result both render as "(none)", so `catchup` reports "no open issues" or "no CI failures" when the query actually died. This violates the project's fail-loud principle: a reader of the output cannot tell absent from broken. The newer `list-task-sessions.sh` already solves this with structured `{"error": ...}` markers that `catchup/SKILL.md:106` distinguishes from real emptiness; `github-state.sh` predates that convention. A concrete latent bug rides along: `github-state.sh:40` calls `gh issue list --label "critical,urgent,P0,P1"`, and `gh` reads the comma-joined string as a single label name, so high-priority detection silently matches nothing.

### Target Users
Anyone who trusts catchup's GitHub state. Acting on "CI is green" when the CI query failed is the failure this prevents.

### Success Metrics
- Every gh/git call in github-state.sh that can fail emits a distinguishable failure marker, never "(none)", when it errors.
- The script ends with a gap summary listing any sections that failed.
- catchup's Phase 5 report surfaces partial GitHub state ("GitHub state partial: X unavailable").
- High-priority issue detection returns real results on a repo using `bug`/`critical` labels (verified by fixture).
- One failed section does not abort the rest of the survey.

## Functional Decomposition

### Capability: Trustworthy GitHub-state reporting
Separate "query failed" from "nothing there", without aborting the survey.

#### Feature: Distinguish failure from emptiness
- **Description**: Each section prints a failure marker on error and "(none)" only on a true empty result.
- **Inputs**: Exit status and output of each gh/git call.
- **Outputs**: `(none)` for empty; `(unavailable: <what> failed)` for error.
- **Behavior**: Capture status explicitly; branch on it; never collapse error into empty.

#### Feature: Correct high-priority label filter
- **Description**: Replace the comma-joined single-label query with correct semantics.
- **Inputs**: Repo labels (overridable via env var).
- **Outputs**: Issues that actually carry priority labels.
- **Behavior**: Use repeated `--label` flags or a per-label query loop (OR semantics); do not hardcode a taxonomy most repos lack; allow an env-var override with a sane default, or sort recent issues by reactions when no known label exists.

#### Feature: Gap summary
- **Description**: A trailing summary of which sections were unavailable.
- **Inputs**: Per-section failure flags.
- **Outputs**: A `=== Gaps ===` block, or "(none)" when everything succeeded.
- **Behavior**: Accumulate failures during the run; print the summary last.

### Capability: Skill consumption of gaps
Make catchup report the gaps honestly.

#### Feature: Phase 5 surfaces partial state
- **Description**: catchup/SKILL.md tells the agent to flag partial GitHub state from the gap markers.
- **Inputs**: github-state.sh output including the gap summary.
- **Outputs**: A gap line in the catchup report when sections failed.
- **Behavior**: Phase 5 reads the gap summary; if non-empty, report it rather than implying clean state.

## Structural Decomposition

### Repository Structure

```
skills/catchup/scripts/
└── github-state.sh        # Maps to: Trustworthy GitHub-state reporting
skills/catchup/SKILL.md    # Maps to: Phase 5 surfaces partial state
tests/
└── github-state.bats      # Maps to: failure-vs-empty assertions (extends existing suite from 00001)
```

### Module: skills/catchup/scripts/github-state.sh
- **Maps to capability**: Trustworthy GitHub-state reporting
- **Responsibility**: Survey GitHub state and report honestly, distinguishing failure from emptiness.
- **Exports**:
  - the script's stdout contract: per-section markers plus a trailing gap summary

### Module: skills/catchup/SKILL.md
- **Maps to capability**: Skill consumption of gaps
- **Responsibility**: Consume the gap summary in Phase 5.
- **Exports**: catchup Phase 5 prose and the error-handling table

## Dependency Graph

### Foundation Layer (Phase 0)
No dependencies - built first. Tests extend the existing `tests/github-state.bats` (11 tests, 00001 harness landed on master) rather than creating it; `tests/README.md` branch tables must be re-enumerated after the rework.

- **Marker convention**: the exact strings for failure vs empty, and the gap-summary format.

### Core Layer (Phase 1)
- **github-state.sh**: Depends on [Marker convention].

### Integration Layer (Phase 2)
- **catchup/SKILL.md**: Depends on [github-state.sh].

## Implementation Phases

### Phase 0: Foundation
**Goal**: Agree the contract and write failing tests.

**Tasks**:
- [ ] Define the marker strings and gap-summary format; document them in a header comment in github-state.sh (no deps) - Acceptance: convention written so SKILL.md can reference exact strings.
- [ ] Write failing tests: gh stub exits non-zero for issue list -> expect failure marker; stub returns `[]` -> expect "(none)"; label fixture with a `bug` issue -> expect it under high-priority (no deps) - Acceptance: tests fail before the rework.

**Exit Criteria**: Tests exist and fail for the right reasons.

### Phase 1: Core
**Goal**: Rework the script.

**Tasks**:
- [ ] Replace blanket `|| true` / `|| echo "(none)"` with explicit status capture per section; emit failure markers; guard each section so one failure does not abort the rest (depends on: Phase 0) - Acceptance: failure tests pass; survey continues after one section fails.
- [ ] Fix the priority-label query (repeated `--label` / loop / env-overridable set) (depends on: Phase 0) - Acceptance: the `bug`-labeled fixture issue appears under high priority.
- [ ] Add the trailing gap summary (depends on: Phase 0) - Acceptance: summary lists failed sections, or "(none)".
- [ ] Adopt `set -euo pipefail` in github-state.sh (assessment G8: adopt as touched) (depends on: Phase 0) - Acceptance: the full github-state suite passes under strict mode; unset-variable and mid-pipeline failures no longer pass silently.
- [ ] Fix the pipe-defeated log guards at `github-state.sh:115,138`: `gh run view … --log-failed 2>/dev/null | tail -100 || echo "(could not fetch logs)"` — the `|| echo` guards the pipeline's status, which is `tail`'s exit 0, so it can never fire. Capture the gh output first (explicit status check, per the marker convention) rather than relying on pipefail alone (depends on: Phase 0) - Acceptance: a stubbed failing `gh run view --log-failed` produces the failure marker, not silence or an empty log section.

**Exit Criteria**: github-state.bats green; shellcheck clean; no path collapses error into "(none)".

### Phase 2: Integration
**Goal**: catchup reports gaps.

**Tasks**:
- [ ] Update catchup/SKILL.md Phase 5 to surface the gap summary; extend the error-handling table for partial GitHub state (depends on: Phase 1) - Acceptance: instructions tell the agent to flag partial state, not imply clean state.
- [ ] CHANGELOG `Fixed` entry (depends on: Phase 1) - Acceptance: entry under Unreleased.

**Exit Criteria**: A simulated gh failure produces a catchup report that names the gap instead of implying clean state.

## Test Strategy

### Critical Scenarios
- **Happy path**: populated repo -> sections render; gap summary is "(none)".
- **Edge case**: empty issue list -> "(none)", and gap summary still "(none)".
- **Edge case**: `bug`-labeled issue present -> shows under high priority (the label-fix regression test).
- **Error case**: gh issue list exits non-zero -> "(unavailable: ...)" marker, issue absent from output, listed in gap summary, and PRs/releases sections still run.
- **Error case**: gh unauthenticated at startup -> top-level exit non-zero with the existing message (unchanged).
- **Error case**: `gh run view --log-failed` exits non-zero -> failure marker in the logs section (regression test for the pipe-defeated `|| echo` guards at lines 115/138).

## Risks

- **set -e interaction**: removing blanket `|| true` could let one failed section abort the script. Capture status explicitly per section and continue; this is the core tension, stay resilient (do not abort) yet honest (do not hide).
- **Marker noise**: keep markers terse plus one aggregate gap summary, not a wall of warnings.
- **Label taxonomy is repo-specific**: prefer recency/reactions or an env-overridable label set over a hardcoded list; never silently match nothing.
- **Shared files with 00002**: both edit `github-state.sh` and `catchup/SKILL.md`. Run 00003 after 00002.
