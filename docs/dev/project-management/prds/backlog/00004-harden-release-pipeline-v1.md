# Release Preflight Gates and Published GitHub Releases

## Overview

### Problem Statement
`dev/bin/release` predates the test suite. Its preflight runs tests only if `test_*.py` files exist (`dev/bin/release:86-92`); the repo's actual suite is 33 bats tests plus a shellcheck gate, and neither runs before a release. A release can ship broken scripts that CI would have caught. Separately, the script tags `v$VERSION` and pushes, but never calls `gh release create`: `gh release list` is empty despite the v0.2.1 tag. Users get no release notes, the GitHub Releases page is blank, and catchup's own `github-state.sh` reports "No releases found" on this very repo.

### Target Users
The maintainer, who needs releases gated on the real test suite. Plugin users, who need a Releases page with notes to judge whether to update.

### Success Metrics
- A release aborts when `bats tests/` fails or `shellcheck -S warning` reports findings; nothing is committed, tagged, or pushed.
- Each release publishes a GitHub Release `vX.Y.Z` whose body is that version's CHANGELOG section.
- `gh release list` shows every tag from v0.1.0 onward after the one-time backfill.
- Notes extraction is covered by bats tests (>= 80% branch coverage, per project rule).

## Functional Decomposition

### Capability: Release gating on the real test suite
Block a release unless the same checks CI runs are green locally.

#### Feature: bats preflight
- **Description**: Run the bats suite as a preflight step.
- **Inputs**: `tests/` and the vendored `tests/lib/bats-core` runner.
- **Outputs**: Pass, or abort with the bats failure output.
- **Behavior**: If `tests/` exists, run `tests/lib/bats-core/bin/bats tests/`; non-zero aborts the release. If the runner is missing (submodule not initialized), abort loudly with the init command - never skip silently.

#### Feature: shellcheck preflight
- **Description**: Run the lint gate as a preflight step.
- **Inputs**: All `*.sh` under `skills/**/scripts/` and `dev/bin/`.
- **Outputs**: Pass, or abort with shellcheck diagnostics.
- **Behavior**: `shellcheck -S warning` on the same file set CI lints; non-zero aborts. If shellcheck is not installed, abort with an install hint - never skip silently.

### Capability: GitHub Release publication
Turn the pushed tag into a Release with human-readable notes.

#### Feature: Extract version notes from CHANGELOG
- **Description**: Print the CHANGELOG section for one version.
- **Inputs**: `CHANGELOG.md`, a version string.
- **Outputs**: The section body between `## [X.Y.Z]` and the next `## [` heading, on stdout.
- **Behavior**: awk extraction (same pattern the script already uses for `[Unreleased]`); empty result is an error, not empty notes.

#### Feature: Publish the release
- **Description**: Create the GitHub Release for the new tag.
- **Inputs**: The tag `vX.Y.Z`, the extracted notes.
- **Outputs**: A published Release; its URL echoed in the step log.
- **Behavior**: `gh release create "v$VERSION" --title "v$VERSION" --notes "$NOTES"` after the tag push. On failure, abort loudly with remediation (the tag is already pushed; re-running publication must be possible without re-tagging).

#### Feature: Backfill existing tags
- **Description**: One-time publication of Releases for tags that predate this change.
- **Inputs**: Existing tags, their CHANGELOG sections.
- **Outputs**: A Release per historical tag.
- **Behavior**: For each tag without a Release, extract that version's notes and `gh release create`; idempotent (skip tags that already have one).

## Structural Decomposition

### Repository Structure

```
dev/bin/
├── release                # Maps to: Release gating, Publish the release
└── print-release-notes    # Maps to: Extract version notes from CHANGELOG (also used for backfill)
tests/
└── print-release-notes.bats   # Maps to: notes-extraction coverage
```

### Module: dev/bin/release
- **Maps to capability**: Release gating on the real test suite; GitHub Release publication
- **Responsibility**: The one release pipeline: preflight (now including bats + shellcheck), bump, stamp, commit, tag, push, publish.
- **Exports**:
  - `dev/bin/release [patch|minor|major]` - the release entrypoint

### Module: dev/bin/print-release-notes
- **Maps to capability**: GitHub Release publication
- **Responsibility**: Deterministic, testable CHANGELOG section extraction.
- **Exports**:
  - `dev/bin/print-release-notes <version>` - prints the section body, exits non-zero when the version heading is absent or the section is empty

## Dependency Graph

### Foundation Layer (Phase 0)
No dependencies - built first.

- **dev/bin/print-release-notes**: notes extraction both the release step and the backfill need.

### Core Layer (Phase 1)
- **dev/bin/release (preflight + publish)**: Depends on [dev/bin/print-release-notes].

### Integration Layer (Phase 2)
- **Backfill + CHANGELOG entry**: Depends on [dev/bin/release publish step].

## Implementation Phases

### Phase 0: Foundation
**Goal**: Tested notes extraction.

**Tasks**:
- [ ] Write failing bats tests for `print-release-notes`: existing version, missing version, empty section, version is the last section in the file (no deps) - Acceptance: tests fail before the script exists.
- [ ] Write `dev/bin/print-release-notes` (no deps) - Acceptance: all extraction tests pass; shellcheck clean.

**Exit Criteria**: `tests/print-release-notes.bats` green; coverage table added to `tests/README.md`.

### Phase 1: Core
**Goal**: Gated, publishing release script.

**Tasks**:
- [ ] Add a branch/freshness guard before preflight (assessment G5): `dev/bin/release` currently commits and tags on whatever branch is checked out, then runs `git push origin master` — a release from a feature branch pushes stale master and leaves the tag pointing at a feature-branch commit. Assert `git branch --show-current` is `master` and run `git pull --ff-only` before any preflight step (no deps) - Acceptance: invoking release from a non-master branch aborts with a message naming the branch, before any file is modified; a diverged local master aborts at the `--ff-only` pull; on a current master the release proceeds unchanged.
- [ ] Replace the `test_*.py` preflight with bats + shellcheck steps that abort loudly when the tool or suite is missing (depends on: Phase 0) - Acceptance: a deliberately broken test aborts the release before any version bump.
- [ ] Add the publish step calling `print-release-notes` and `gh release create` after the tag push (depends on: Phase 0) - Acceptance: a dry inspection of the script shows publish ordered after tag push, with loud failure and a re-run path that does not re-tag.

**Exit Criteria**: `shellcheck -S warning dev/bin/release` clean; preflight provably blocks on red tests.

### Phase 2: Integration
**Goal**: Visible release history.

**Tasks**:
- [ ] Backfill Releases for existing tags (depends on: Phase 1) - Acceptance: `gh release list` shows every existing `v*` tag with notes matching its CHANGELOG section.
- [ ] CHANGELOG `Added` entry for published GitHub Releases (depends on: Phase 1) - Acceptance: entry under Unreleased.

**Exit Criteria**: Next `dev/bin/release` run produces a gated release plus a published GitHub Release.

## Test Strategy

### Critical Scenarios
- **Happy path**: `print-release-notes 0.2.1` -> prints the 0.2.1 section, exit 0.
- **Edge case**: version is the newest (section ends at next heading) and the oldest (section ends at EOF) -> both extract correctly.
- **Error case**: unknown version or empty section -> non-zero exit with a clear message, never empty stdout with exit 0.
- **Error case**: bats suite red during preflight -> release aborts before any file is modified.
- **Error case**: release invoked from a feature branch, or local master behind/diverged from origin -> aborts before preflight with a clear message (branch/freshness guard).

## Risks

- **`dev/bin/release` itself is hard to test end-to-end** (it commits, tags, pushes): keep all new logic either trivial (calling the gates) or extracted into `print-release-notes`, which is fully bats-tested. State in the completion note which paths were verified by test vs by inspection (fail loud about the method).
- **Publish failing after tag push** leaves a tag without a Release: make the publish step re-runnable standalone and document the recovery command in the script's failure message.
- **gh unauthenticated on the release machine**: preflight `gh auth status` before touching anything, alongside the existing jq/git checks.
- **Maintainer-only scope**: this script intentionally hardcodes `master` pushes for this repo; the distributed-runtime "no hardcoded master" rule does not apply here (documented exception).
