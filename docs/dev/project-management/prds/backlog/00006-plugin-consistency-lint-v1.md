# Plugin Consistency Lint

## Overview

### Problem Statement
git-ferry's integrity rests on cross-file invariants nothing checks. The version lives in two in-repo places (`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` `plugins[0].version`) plus the latest stamped CHANGELOG heading; `dev/bin/release` bumps them together, but a manual edit desyncs them silently. SKILL.md files invoke scripts via `${CLAUDE_SKILL_DIR}/scripts/...` - a renamed or non-executable script breaks the skill only at user runtime, on someone else's machine. The README skill table mirrors `skills/` by hand. Because this is a distributed plugin, every such drift ships to every installer; CI currently proves the scripts work but not that the plugin packaging is coherent.

### Target Users
The maintainer and contributors, who get packaging drift caught in CI instead of in a user's broken session. Indirectly every installer of the plugin.

### Success Metrics
- CI fails when: a SKILL.md references a missing or non-executable script; a script exists that no SKILL.md references; SKILL.md frontmatter is missing `name`/`description` or `name` mismatches its directory; in-repo versions disagree; the newest stamped CHANGELOG version disagrees with plugin.json; a skill directory is absent from the README table (or vice versa).
- The lint passes on the current repo as-is (any findings it surfaces on first run are fixed in this PRD).
- The lint script's own branches are bats-covered >= 80% via fixture trees.

## Functional Decomposition

### Capability: Packaging invariant checks
One script that verifies every cross-file invariant and reports all violations at once.

#### Feature: Script reference check
- **Description**: Every `${CLAUDE_SKILL_DIR}/scripts/<name>` mentioned in a SKILL.md resolves to an existing executable file, and every file under `skills/*/scripts/` is referenced by its own SKILL.md.
- **Inputs**: `skills/*/SKILL.md`, `skills/*/scripts/*`.
- **Outputs**: One violation line per missing/non-executable/unreferenced script.
- **Behavior**: Extract referenced paths by pattern; compare both directions against the filesystem; `lib/` helper scripts sourced (not invoked) by other scripts are exempt from the reference direction.

#### Feature: Frontmatter check
- **Description**: Each SKILL.md has valid minimal frontmatter.
- **Inputs**: `skills/*/SKILL.md` frontmatter blocks.
- **Outputs**: Violation lines for missing block, missing `name`/`description`, or `name` != directory name.
- **Behavior**: Parse the `---` block; compare `name:` to the parent directory.

#### Feature: Version agreement check
- **Description**: All in-repo version declarations agree.
- **Inputs**: `plugin.json` `.version`, self `marketplace.json` `.plugins[0].version`, newest `## [X.Y.Z]` heading in CHANGELOG.md.
- **Outputs**: A violation naming each mismatching pair.
- **Behavior**: jq + grep the three values; all-equal passes. The central buvis-plugins marketplace lives in a sibling repo and is out of scope (release script owns it).

#### Feature: README table check
- **Description**: The README skill table and `skills/` agree.
- **Inputs**: README.md table rows, `skills/*/` directory names.
- **Outputs**: Violations for skills missing from the table and rows naming nonexistent skills.
- **Behavior**: Extract backticked skill names from the table; set-compare with directory listing.

#### Feature: Aggregate report
- **Description**: Run every check, print all violations, fail once.
- **Inputs**: All checks above.
- **Outputs**: Violation list and a final `LINT: ok` or `LINT: N violations`; exit 0 only when clean.
- **Behavior**: Never stop at the first violation; the CI log shows everything wrong in one run.

### Capability: CI enforcement
Make the lint a required check.

#### Feature: CI lint step
- **Description**: Run the lint in the existing workflow.
- **Inputs**: Push/PR events.
- **Outputs**: A failing check on violations.
- **Behavior**: A step in `ci.yml` invoking the script (ubuntu only - the checks are platform-independent).

## Structural Decomposition

### Repository Structure

```
dev/bin/
└── lint-plugin            # Maps to: Packaging invariant checks
tests/
├── lint-plugin.bats       # Maps to: lint coverage via fixture trees
└── fixtures/
    └── lint-plugin/       # broken-fixture trees: missing script, bad frontmatter, version skew, table drift
.github/workflows/
└── ci.yml                 # Maps to: CI enforcement (new step)
```

### Module: dev/bin/lint-plugin
- **Maps to capability**: Packaging invariant checks
- **Responsibility**: Verify all packaging invariants against a repo root and report every violation.
- **Exports**:
  - `dev/bin/lint-plugin [repo-root]` - defaults to the repo containing the script; the root argument is what makes fixture-tree testing possible

### Module: .github/workflows/ci.yml
- **Maps to capability**: CI enforcement
- **Responsibility**: Run the lint on every push/PR.
- **Exports**:
  - the `lint-plugin` step

## Dependency Graph

### Foundation Layer (Phase 0)
No dependencies - built first. Reuses the 00001 bats harness.

- **tests/fixtures/lint-plugin + lint-plugin.bats**: one minimal fixture tree per violation class, plus a clean tree.

### Core Layer (Phase 1)
- **dev/bin/lint-plugin**: Depends on [fixture trees and failing tests].

### Integration Layer (Phase 2)
- **ci.yml step**: Depends on [dev/bin/lint-plugin].

## Implementation Phases

### Phase 0: Foundation
**Goal**: The contract, pinned by failing tests.

**Tasks**:
- [ ] Build fixture trees: clean, missing-script, non-executable script, unreferenced script, bad frontmatter, version skew, README drift (no deps) - Acceptance: each tree isolates exactly one violation class.
- [ ] Write failing `lint-plugin.bats` asserting per-tree violations and the clean tree's `LINT: ok` (no deps) - Acceptance: all red before the script exists.

**Exit Criteria**: Tests enumerate every check; all fail.

### Phase 1: Core
**Goal**: The lint script.

**Tasks**:
- [ ] Implement `dev/bin/lint-plugin` with all five checks and the aggregate report (depends on: Phase 0) - Acceptance: all bats tests green; shellcheck clean; coverage table added to `tests/README.md`.
- [ ] Run it on the real repo; fix any violations it finds (depends on: Phase 0) - Acceptance: `dev/bin/lint-plugin` exits 0 on this repo; each fix listed in the completion note.

**Exit Criteria**: Lint green on the repo and fully tested on fixtures.

### Phase 2: Integration
**Goal**: Enforcement.

**Tasks**:
- [ ] Add the ci.yml step (ubuntu job) (depends on: Phase 1) - Acceptance: CI runs the lint; a deliberately broken branch fails the check.
- [ ] No CHANGELOG entry (CI-only change, per changelog rule) - note this explicitly in the completion message (depends on: Phase 1) - Acceptance: completion note states why no entry was added.

**Exit Criteria**: Lint is a passing check on master and fails on seeded violations.

## Test Strategy

### Critical Scenarios
- **Happy path**: clean fixture tree -> `LINT: ok`, exit 0.
- **Edge case**: two simultaneous violations -> both reported in one run, `LINT: 2 violations`.
- **Edge case**: sourced `lib/*.sh` helper not invoked from SKILL.md -> not flagged as unreferenced.
- **Error case**: missing script reference -> named violation, non-zero exit.
- **Error case**: plugin.json and CHANGELOG disagree -> violation names both values.

## Risks

- **Reference extraction is pattern-based**: SKILL.md prose could mention scripts in unanticipated formats; pin the recognized pattern (`${CLAUDE_SKILL_DIR}/scripts/...`) in a header comment and test it. A miss fails toward "unreferenced script", which is loud, not silent.
- **Check creep**: keep this to packaging invariants; behavioral checks belong in the bats suites. New invariants need a fixture tree before a check.
- **First real-repo run may surface existing drift**: fixing those findings is in scope (Phase 1) so the CI step lands green, not red.
