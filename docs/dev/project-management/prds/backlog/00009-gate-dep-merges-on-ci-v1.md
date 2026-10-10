# Gate Dependency-PR Merges on CI Status

## Overview

### Problem Statement
review-deps-prs merges with no CI gate: `skills/review-deps-prs/SKILL.md:64-74` runs `gh pr merge --repo {repo} {number} --squash` directly, for individual merges and for batch "merge all minor/patch". On branch-protected repos GitHub itself refuses red merges, but on unprotected repos — the common case for personal projects — `gh pr merge` merges a PR whose checks failed, and batch mode sweeps several red PRs into the default branch in one command. The skill's own error-handling table assumes "PR merge fails (CI not passing…)", which only holds under branch protection (assessment git-ferry section, proposed 00009). Prose-only fix: verify check state before every merge; skip red or pending PRs loudly.

### Target Users
The maintainer batch-merging minor/patch dependency PRs across many personal repos. Merge safety must not depend on each repo's protection settings.

### Success Metrics
- Every merge path (individual and batch) verifies check state first; a PR with failing or pending checks is never merged and is reported as skipped with its state.
- A repo with no checks configured still merges (no false blocking).
- Batch results report three buckets: merged, skipped-with-reason, failed (merge-command error).
- SKILL.md-only change; create-skill validator passes; no script or test-suite surface touched.

## Functional Decomposition

### Capability: Pre-merge CI gate

#### Feature: Check-state verification
- **Description**: Classify a PR's checks before merging.
- **Inputs**: repo, PR number; gh.
- **Outputs**: Verdict: green, red, pending, no-checks, or conflicting.
- **Behavior**: `gh pr view --repo {repo} {number} --json statusCheckRollup,mergeable`. green = every rollup entry SUCCESS/SKIPPED/NEUTRAL; red = any FAILURE/ERROR/CANCELLED/TIMED_OUT; pending = any entry still running or queued; no-checks = empty rollup; `mergeable: CONFLICTING` -> conflicting. An unknown conclusion value is treated as not-green (skip, quoting the raw value) — fail safe, never guess.

#### Feature: Gate on both merge paths
- **Description**: Individual and batch merges pass through the verdict.
- **Inputs**: The per-PR verdict.
- **Outputs**: `gh pr merge` runs only on green and no-checks verdicts; everything else is a skip.
- **Behavior**: Individual merge: verify, then merge or report the skip reason. Batch merge: verify each candidate, merge only green/no-checks, accumulate skips; one bad PR never aborts the rest. Where a repo has auto-merge enabled, `gh pr merge --auto` may be offered as an alternative that delegates the gate to GitHub — but the explicit gate stays the default, because auto-merge is unavailable exactly on the unprotected repos at risk.

### Capability: Loud skip reporting

#### Feature: Skipped-with-reason results
- **Description**: The action report never silently drops a requested merge.
- **Inputs**: Per-PR verdicts and merge outcomes.
- **Outputs**: Final report buckets: merged / skipped (with "checks failing", "checks pending", "merge conflict", or the raw unknown state) / failed (merge command errored).
- **Behavior**: Skipped PRs include a follow-up hint (re-run after CI goes green, or watch-ci on that repo; conflicts point at resolve-git-conflicts); the error-handling table gains a "checks failing/pending" row.

## Structural Decomposition

### Repository Structure

```
skills/review-deps-prs/
└── SKILL.md          # Maps to: Pre-merge CI gate, Loud skip reporting (prose-only)
```

### Module: skills/review-deps-prs/SKILL.md
- **Maps to capability**: Pre-merge CI gate; Loud skip reporting
- **Responsibility**: Step 5 (Execute actions) gains the mandatory verification command and the verdict table; the results report gains the three buckets; the error-handling table is extended.
- **Exports**: review-deps-prs workflow prose.

## Dependency Graph

### Foundation Layer (Phase 0)
No dependencies. Same-file note: PRD 00008 rewrites steps 1-3 of this SKILL.md; when both are queued, run 00009 after 00008 to avoid conflicting edits (no semantic dependency).

- **Verdict table**: the statusCheckRollup-to-verdict mapping.

### Core Layer (Phase 1)
- **SKILL.md step-5 rewrite**: Depends on [Verdict table].

### Integration Layer (Phase 2)
- **CHANGELOG**: Depends on [SKILL.md step-5 rewrite].

## Implementation Phases

### Phase 0: Foundation
**Goal**: An unambiguous verdict mapping.

**Tasks**:
- [ ] Write the verdict table (rollup conclusion/status values -> green/red/pending/no-checks/conflicting; unknown -> not-green) (no deps) - Acceptance: every documented statusCheckRollup conclusion value maps to exactly one verdict; empty rollup maps to proceed; the table is checked against real `gh pr view --json statusCheckRollup,mergeable` output from one green and one red PR.

**Exit Criteria**: Verdict table complete and verified against live gh output.

### Phase 1: Core
**Goal**: The gated merge flow in prose.

**Tasks**:
- [ ] Rewrite SKILL.md step 5: mandatory `gh pr view --repo {repo} {number} --json statusCheckRollup,mergeable` before each merge; verdict table inline; batch loop merges only green/no-checks and accumulates skips; three-bucket result report; extend the error-handling table; note the `--auto` alternative (depends on: Phase 0) - Acceptance: no `gh pr merge` appears in SKILL.md without the preceding verification step; create-skill validator passes.

**Exit Criteria**: A dry read of the skill gives an agent no path to merge an unverified PR.

### Phase 2: Integration
**Goal**: Releasable.

**Tasks**:
- [ ] CHANGELOG `Fixed` entry (dep merges now gated on CI status; red/pending PRs skipped loudly) (depends on: Phase 1) - Acceptance: entry under Unreleased.

**Exit Criteria**: CHANGELOG updated; skill validates.

## Test Strategy

### Critical Scenarios
Prose-only change: there is no script surface for bats, so verification is a manual walkthrough against live PRs; the completion note must state that method explicitly (fail loud about the method).

- **Happy path**: green PR -> merged exactly as before.
- **Edge case**: repo with no checks configured -> merged; no false block.
- **Edge case**: pending checks -> skipped with "checks pending" and a watch-ci hint; not merged.
- **Error case**: batch of three with one red PR -> two merged, one skipped with "checks failing"; final report buckets match.
- **Error case**: `mergeable: CONFLICTING` -> skipped with "merge conflict", pointing at resolve-git-conflicts.

## Risks

- **Prose gates rely on the model obeying them**: keep the verification a single mandatory command inside the merge step (the same pattern the skill already uses for the merge command itself), not an optional aside; the "no merge without verification" acceptance is greppable.
- **statusCheckRollup shape variance**: check runs and legacy commit statuses mix in the rollup; the verdict table enumerates conclusions and fails safe (unknown -> skip with the raw value).
- **Race between view and merge**: checks can flip in the seconds between; acceptable for dep triage, and the `--auto` alternative removes it where auto-merge exists.
- **Extra gh call per merge**: one `gh pr view` per PR — negligible next to a red merge landing on the default branch.
- **Same-file overlap with 00008**: both edit review-deps-prs/SKILL.md; sequence 00009 after 00008 when both are queued.
