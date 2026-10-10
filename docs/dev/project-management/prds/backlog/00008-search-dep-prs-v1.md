# Search-Based Dependency-PR Discovery

## Overview

### Problem Statement
`skills/review-deps-prs/scripts/list-dep-prs.sh:18-24` discovers dependency PRs by looping over every repo from `gh repo list --limit 200` and running one serial `gh pr list … || continue` per repo. Two defects ride that loop. Fail-loud: `|| continue` swallows every failure, so a rate-limited or erroring repo is indistinguishable from a repo with no dependency PRs — and 200 rapid serial calls are exactly how you get rate-limited, so triage silently loses repos precisely when the sweep is largest (assessment finding G7). Cost: up to 200 gh round trips take minutes for what GitHub's search API answers in 1-3 queries. The plugin already defines the vocabulary for honest partial results — PRD 00003's `(unavailable: …)` markers plus a trailing gap summary in github-state.sh — and this script should speak it.

### Target Users
Anyone triaging dependency PRs across many repos with review-deps-prs. Their merge decisions are only sound if "no dep PRs in repo X" really means none, and the sweep should finish in seconds, not minutes.

### Success Metrics
- Discovery issues a fixed handful of gh calls (one repo/owner scoping call plus at most 3 `gh search prs` queries, plus owner-chunk repeats only when search-qualifier limits force them), independent of repo count.
- A failed or rate-limited query never renders as "no dependency PRs": it emits an `(unavailable: <scope>)` marker and the run ends with a gap count (same convention as 00003).
- Detection semantics preserved: renovate[bot]/dependabot[bot] authors plus today's anchored title regexes, still enforced by the client-side jq filter.
- Output stays grouped per repo (`--- owner/repo ---` sections) so the SKILL's tier classification (step 2) needs no change.
- `bats tests/` green with the reworked list-dep-prs suite; shellcheck clean.

## Functional Decomposition

### Capability: Search-based discovery
Replace the per-repo fan-out with a constant number of owner-scoped search queries.

#### Feature: Owner-scoped search queries
- **Description**: Fetch candidate PRs with 1-3 `gh search prs` queries instead of N `gh pr list` calls.
- **Inputs**: Owner set derived from one `gh repo list --json owner` call; gh.
- **Outputs**: Combined candidate JSON (number, title, author, labels, createdAt, url, repository).
- **Behavior**: One query per detection axis — `--author app/renovate`, `--author app/dependabot`, and a title-keyword query covering the manual patterns (`chore(deps)`, `fix(deps)`, `bump`, `update`, `[security]` as `in:title` terms) — each `--state open`, scoped to the user's owners so results never include foreign repos, with an explicit `--limit` (gh's default of 30 truncates silently). If the owner list overflows GitHub's search-qualifier length limit, chunk owners across repeated queries.

#### Feature: Precise client-side filter
- **Description**: Keep the anchored jq filter as the source of truth for what counts as a dependency PR.
- **Inputs**: Combined search results.
- **Outputs**: Filtered, deduplicated PR set.
- **Behavior**: Search matching is word-based and unanchored (wide net); the existing jq `select()` — bot authors or `^(chore\(deps\)|bump |update |\[security\])` / `^fix\(deps\)` — narrows it. Dedupe on repository+number, since one PR can match both an author query and the title query.

### Capability: Loud gaps
A failed query names what is missing instead of vanishing (00003 marker convention).

#### Feature: Unavailable-scope markers and gap count
- **Description**: Per-query status capture with markers and a trailing gap summary.
- **Inputs**: Exit status of each gh call; result counts vs the search `--limit`.
- **Outputs**: `(unavailable: <scope>)` marker lines naming the failed query axis and owner chunk; a trailing gap-count line; a truncation marker when a query returns exactly `--limit` rows.
- **Behavior**: No `|| continue`. Capture each query's output and status explicitly; on failure print the marker and keep going with the remaining queries; end the report with the gap count (zero when clean). Exit non-zero only when nothing was searchable at all (owner scoping call failed / gh unauthenticated), preserving today's top-level abort contract.

#### Feature: Per-repo grouped output
- **Description**: Preserve the section format downstream steps parse.
- **Inputs**: Filtered PR set.
- **Outputs**: `--- owner/repo ---` header per repo followed by that repo's PR JSON, as today.
- **Behavior**: Group the deduped results by repository; repos with no matches print nothing (unchanged).

### Capability: Skill and harness alignment

#### Feature: SKILL.md gap consumption
- **Description**: The skill reports partial coverage instead of implying a full sweep.
- **Inputs**: Script output including markers and the gap count.
- **Outputs**: Step 1 wording matches the search mechanism; step 3 flags "triage partial: N scopes unavailable" when the gap count is non-zero; the error-handling "Rate limited" row points at the markers.
- **Behavior**: Prose update only; tiering and action steps unchanged.

#### Feature: gh stub search support
- **Description**: The offline gh stub learns `gh search prs`.
- **Inputs**: Fixture files; an env knob to fail a chosen query.
- **Outputs**: Deterministic search replies; injectable per-query failure.
- **Behavior**: Extends `tests/helpers/stubs/gh` and `tests/fixtures/` following the existing fixture-backed pattern; unsupported invocations keep failing loud.

## Structural Decomposition

### Repository Structure

```
skills/review-deps-prs/
├── SKILL.md                # Maps to: SKILL.md gap consumption
└── scripts/
    └── list-dep-prs.sh     # Maps to: Search-based discovery, Loud gaps
tests/
├── list-dep-prs.bats       # Maps to: reworked coverage
├── helpers/stubs/gh        # Maps to: gh stub search support (EXTEND)
└── fixtures/               # search-result fixtures (EXTEND)
```

### Module: skills/review-deps-prs/scripts/list-dep-prs.sh
- **Maps to capability**: Search-based discovery; Loud gaps
- **Responsibility**: Constant-call discovery with explicit per-query status, dedupe, grouping, markers, and the gap count. Adopts `set -euo pipefail` (assessment G8: adopt as touched).
- **Exports**: stdout contract: repo sections + `(unavailable: …)` markers + trailing gap count; exit 0 on any successful search, 1 when nothing searchable.

### Module: skills/review-deps-prs/SKILL.md
- **Maps to capability**: Skill and harness alignment
- **Responsibility**: Describe the search mechanism; consume the gap count in the summary.
- **Exports**: review-deps-prs workflow prose.

### Module: tests (list-dep-prs.bats, helpers/stubs/gh, fixtures)
- **Maps to capability**: all (test surface)
- **Responsibility**: Pin query shape (owner scoping, explicit limit), dedupe, markers, gap count, and the abort contract.
- **Exports**: bats cases; stub behaviors.

## Dependency Graph

### Foundation Layer (Phase 0)
No hard dependencies. Soft sequencing: this PRD reuses the exact marker/gap-summary strings PRD 00003 defines for github-state.sh — run after 00003 so the convention exists to copy; if this lands first, define the strings here and 00003 aligns to them.

- **gh stub `search prs` + fixtures**: deterministic replies and failure injection.

### Core Layer (Phase 1)
- **list-dep-prs.sh rewrite**: Depends on [gh stub `search prs` + fixtures].

### Integration Layer (Phase 2)
- **SKILL.md + CHANGELOG**: Depends on [list-dep-prs.sh rewrite].

## Implementation Phases

### Phase 0: Foundation
**Goal**: Failing tests that pin the new contract.

**Tasks**:
- [ ] Extend the gh stub and fixtures: `gh search prs` replays fixture JSON per query axis (renovate author, dependabot author, title keywords); an env knob fails one chosen query; `gh repo list --json owner` returns an owner fixture (no deps) - Acceptance: stub answers all three query shapes deterministically; the knob makes exactly one query exit non-zero; unsupported invocations still fail loud.
- [ ] Write failing tests: happy path (renovate PR listed once under its repo header), dedupe (PR matching author and title queries appears once), injected query failure yields the `(unavailable: …)` marker plus non-zero gap count while other results still print, clean run ends with a zero-gap trailer, owner-scoping failure exits 1 with the existing "No repos found or gh not authenticated" message (no deps) - Acceptance: red before the rewrite; the 3 existing characterization tests are updated or replaced, not silently deleted.

**Exit Criteria**: New suite fails for the right reasons; `tests/README.md` plan updated.

### Phase 1: Core
**Goal**: The rewritten script.

**Tasks**:
- [ ] Rewrite list-dep-prs.sh: owner derivation, <= 3 owner-scoped `gh search prs` queries with explicit `--limit`, per-query status capture (no `|| continue`), jq filter + dedupe, per-repo grouping, `(unavailable: …)` markers + trailing gap count, truncation marker at the limit, `set -euo pipefail` (depends on: Phase 0) - Acceptance: all list-dep-prs bats green; shellcheck clean; coverage table in `tests/README.md` re-enumerated.

**Exit Criteria**: Full `bats tests/` green; no code path collapses a query failure into empty output.

### Phase 2: Integration
**Goal**: The skill consumes the new contract.

**Tasks**:
- [ ] Update SKILL.md: step 1 describes search-based discovery; step 3 flags partial triage when the gap count is non-zero; the error-handling rate-limit row references the markers (depends on: Phase 1) - Acceptance: no wording claims a full sweep when gaps exist.
- [ ] CHANGELOG `Fixed` entry (rate-limited repos no longer vanish from dep triage; discovery is constant-call) (depends on: Phase 1) - Acceptance: entry under Unreleased.

**Exit Criteria**: A simulated failed query produces a skill-level report that names the gap.

## Test Strategy

### Critical Scenarios
- **Happy path**: renovate-authored fixture PR -> listed once under `--- owner/repo ---`; trailing gap count zero.
- **Edge case**: PR matching both the dependabot author query and the title query -> appears exactly once (dedupe).
- **Edge case**: a query returns exactly `--limit` rows -> truncation marker fires.
- **Error case**: title query fails (injected) -> `(unavailable: …)` marker, gap count 1, author-query results still listed.
- **Error case**: `gh repo list` empty or unauthenticated -> exit 1 with the existing "No repos found or gh not authenticated" message.

## Risks

- **Unscoped search queries all of GitHub**: owner scoping is mandatory; a bats assertion pins that the stub receives owner qualifiers so a regression cannot slip in.
- **Search net narrower than the regexes**: the jq filter can only narrow, never recover a PR the search missed, so the search terms must be a superset of every anchored pattern; fixtures include one title per regex branch to prove coverage.
- **Search API quirks**: the search endpoint has its own 30 req/min budget — ample for <= 3 calls; results can be seconds-stale, acceptable for triage and noted in the script header.
- **Qualifier length limit with many owners**: chunk owners across queries; each chunk carries its own marker scope so a failed chunk names its owners.
- **Convention drift vs 00003**: soft-sequence after 00003 and reference its exact marker strings; if this lands first, 00003 adopts the strings defined here.
- **Same-file overlap with 00009**: both edit review-deps-prs/SKILL.md (this PRD steps 1-3, 00009 step 5); run 00008 before 00009 when both are queued.
