# Prune worktrees safely via deterministic lifecycle states

## Overview

### Problem Statement

The user's global CLAUDE.md mandates cleaning up stale worktrees and orphan branches after completing work, but no tooling backs that mandate. Cleanup today is ad-hoc `git worktree list` plus judgment, which risks both failure modes: deleting a tree that still holds unmerged or uncommitted work, and leaving dead trees and branches to pile up. ECC (affaan-m/everything-claude-code, commit `c8caf19`, reviewed 2026-06-09 via /catchup-ecc) shipped a reference design that fixes this with code, not judgment: every worktree gets a lifecycle state derived deterministically from git facts, and a GC planner proposes removal only for provably safe trees. Port that design to git-ferry as a skill plus a bash helper script (repo convention: bash scripts under `skills/<name>/scripts/`, bats tests in `tests/`).

### Target Users

Solo developer running multi-worktree workflows (autopilot, parallel agents) who needs end-of-work cleanup that is safe to run without re-deriving each tree's status by hand.

### Success Metrics

- Every worktree of a repo is classified into exactly one state: `main`, `detached`, `dirty`, `conflict`, `merge-ready`, `merged`, `stale`, or `idle`, from git facts alone (no heuristics on names).
- The GC plan never proposes a tree that is dirty, merge-ready, or conflict-state, and never a tree with unmerged commits; on the test fixtures, every proposed removal is a tree whose deletion loses zero commits and zero uncommitted changes.
- Conflict prediction agrees with an actual merge attempt on the fixtures; on git < 2.38 it reports `unknown` instead of guessing.
- `bats tests/` green.

## Functional Decomposition

### Capability: Worktree state classification

#### Feature: list-worktree-states script

- **Description**: Emit one TSV row per worktree with its lifecycle state and the facts behind it.
- **Inputs**: Current repo (via `git worktree list --porcelain`); base branch (default: the repo's default branch via PRD 00002's shared resolver — see the sequencing note in the Dependency Graph; `--base` flag override); stale threshold in days (default 14, `GIT_FERRY_WORKTREE_STALE_DAYS` override).
- **Outputs**: TSV to stdout: `path  branch  state  ahead  behind  dirty  last_commit_date  gc_safe  reason`.
- **Behavior**: Port of ECC's state derivation. Per tree: `main` if it is the primary worktree; `detached` if no branch; `dirty` if `git status --porcelain` is non-empty (never GC); else compute ahead/behind vs base (`git rev-list --left-right --count`). Ahead == 0 → `merged`. Ahead > 0 and clean: predict conflicts with `git merge-tree --write-tree` (git >= 2.38) → `conflict` or `merge-ready`; on older git, prediction is `unknown` and the state falls back to `merge-ready` with `reason=conflict-prediction-unavailable`. Clean, nothing to merge, but last activity older than the stale threshold → `stale`; otherwise `idle`. Unmerged-but-quiet trees are `stale` only as salvage candidates, never blind deletes.

### Capability: Safe GC planning

#### Feature: gc_safe flag and reason

- **Description**: Mark exactly the trees that are provably safe to remove, with the reason stated.
- **Inputs**: The per-tree facts from the classification pass.
- **Outputs**: `gc_safe=yes` only for `merged` trees and for `stale` trees that are clean AND have ahead == 0 (or no tracked branch); `gc_safe=no` with a reason for everything else.
- **Behavior**: Mirrors ECC's safety rule verbatim: dirty, merge-ready, and conflict trees are never proposed, so in-progress or unmerged work is preserved. The reason column makes "kept and why" reportable without re-deriving facts.

#### Feature: Orphan branch listing

- **Description**: List local branches that are fully merged into base and have no worktree, as branch-deletion candidates.
- **Inputs**: `git branch --merged <base>`, the worktree list, the base branch.
- **Outputs**: One TSV row per candidate branch (separate `--orphans` mode or trailing section), excluding base itself and branches checked out anywhere.
- **Behavior**: Pure read; deletion itself happens in the skill flow with `git branch -d` (never `-D`), so git re-verifies merge status at deletion time.

### Capability: Skill-driven cleanup flow

#### Feature: prune-worktrees SKILL.md

- **Description**: Skill that runs the script, presents the table, and executes only user-confirmed removals.
- **Inputs**: User invocation ("prune worktrees", "clean up worktrees"); script TSV output.
- **Outputs**: A rendered state table; after confirmation, `git worktree remove` (never `--force`) per approved tree, `git branch -d` per approved orphan branch, and a closing report of what was removed, what was kept, and why.
- **Behavior**: Present-confirm-execute. The skill never removes anything `gc_safe=no`, even on user insistence; it instead names the blocking fact (dirty, unmerged commits, predicted conflict) and the manual command the user can run themselves. `stale` trees with unmerged commits are surfaced as salvage candidates (merge or cherry-pick first), not deletion targets.

## Structural Decomposition

### Repository Structure

```
claude-git-ferry/
├── skills/
│   └── prune-worktrees/
│       ├── SKILL.md                          # Maps to: Skill-driven cleanup flow (NEW)
│       └── scripts/
│           └── list-worktree-states.sh       # Maps to: classification + GC planning (NEW)
├── tests/
│   ├── list-worktree-states.bats             # Maps to: classification + GC planning (NEW)
│   └── fixtures/                             # worktree fixture builders (EXTEND)
└── CHANGELOG.md                              # Maps to: release notes (EDIT)
```

### Module: skills/prune-worktrees/scripts/list-worktree-states.sh

- **Maps to capability**: Worktree state classification; Safe GC planning
- **Responsibility**: All git-fact gathering and state/gc_safe derivation; the single source of truth the skill consumes. Read-only - it never mutates the repo.
- **Exports**: CLI: `list-worktree-states.sh [--base <branch>] [--orphans]`; TSV on stdout; non-zero exit with a message on stderr when not in a git repo.

### Module: skills/prune-worktrees/SKILL.md

- **Maps to capability**: Skill-driven cleanup flow
- **Responsibility**: Frontmatter (trigger-led description per skill conventions), the present-confirm-execute workflow, the safety rules the model must follow, and the `$CLAUDE_SKILL_DIR` script invocation.
- **Exports**: Skill entry; no code exports.

### Module: tests/list-worktree-states.bats

- **Maps to capability**: both script capabilities (test surface)
- **Responsibility**: Build fixture repos with worktrees in each state and assert classification, gc_safe verdicts, conflict prediction, and orphan listing.
- **Exports**: bats test cases; no public API.

## Dependency Graph

### Foundation Layer (Phase 0)

No dependencies within this PRD - built first.

> **Sequencing note (2026-07-09)**: the `--base` default must consume PRD 00002's shared default-branch resolver (`lib/resolve-base.sh` at the plugin root, referenced via `${CLAUDE_PLUGIN_ROOT}`), not a hardcoded `master`. Schedule this PRD after 00002 lands; if 00002 has not landed, this PRD is blocked — do not inline a second resolver.

- **list-worktree-states.sh (classification)**: provides the facts everything else consumes.

### Core Layer (Phase 1)

- **gc_safe + orphan listing**: Depends on [classification] (same script, derived columns).

### Integration Layer (Phase 2)

- **SKILL.md + CHANGELOG**: Depends on [Phase 0, Phase 1] - the skill documents and consumes the finished script contract.

## Implementation Phases

### Phase 0: Foundation

**Goal**: Deterministic state classification, locked by fixtures.

**Tasks**:

- [ ] Build bats fixtures covering each state: main, detached, dirty, merged, merge-ready, conflict (two branches touching the same line), stale (backdated commit), idle (no deps) - Acceptance: fixture helper creates a repo whose worktrees reproduce all eight states; `bats tests/list-worktree-states.bats` runs the helper without error.
- [ ] TDD the classification pass of `list-worktree-states.sh` (depends on: previous) - Acceptance: each fixture tree is classified to its expected state; on git < 2.38 (or with prediction stubbed unavailable) the conflict fixture reports `merge-ready` with `reason=conflict-prediction-unavailable`, never a guess.

**Exit Criteria**: All state-classification bats cases green.

### Phase 1: Core

**Goal**: The script says what is safe to remove, and why, and lists orphan branches.

**Tasks**:

- [ ] TDD `gc_safe`/`reason` columns (depends on: Phase 0) - Acceptance: `merged` and clean-stale-with-nothing-unmerged fixtures get `gc_safe=yes`; dirty, merge-ready, conflict, and stale-with-unmerged-commits get `gc_safe=no` with the blocking fact in `reason`.
- [ ] TDD `--orphans` listing (depends on: Phase 0) - Acceptance: a merged branch with no worktree is listed; the base branch and any checked-out branch are not.

**Exit Criteria**: Full `bats tests/` suite green.

### Phase 2: Integration

**Goal**: The skill ships and the plugin is releasable.

**Tasks**:

- [ ] Write `skills/prune-worktrees/SKILL.md` (depends on: Phase 1) - Acceptance: trigger-led frontmatter description (<= 250 chars); workflow uses `$CLAUDE_SKILL_DIR/scripts/list-worktree-states.sh`; safety rules (never remove gc_safe=no, never `--force`, never `-D`) stated; create-skill validator passes.
- [ ] CHANGELOG `### Added` entry prefixed `**git-ferry**:` (depends on: previous) - Acceptance: entry describes the user-visible capability; plugin consistency expectations (manifest/marketplace) checked against the repo's release flow.

**Exit Criteria**: Skill validates; suite green; CHANGELOG updated.

## Test Strategy

### Critical Scenarios

- **Happy path**: repo with a merged worktree → Expected: state `merged`, `gc_safe=yes`; skill removes it only after confirmation.
- **Edge case**: dirty worktree that is also fully merged → Expected: state `dirty`, `gc_safe=no` (dirty wins; uncommitted work is never proposed).
- **Edge case**: stale tree with 3 unmerged commits → Expected: state `stale`, `gc_safe=no`, surfaced as a salvage candidate.
- **Edge case**: clean ahead branch whose merge would conflict → Expected: state `conflict`, `gc_safe=no`.
- **Error case**: run outside a git repo → Expected: non-zero exit, clear stderr message, no TSV.

## Risks

- **Conflict prediction depends on git >= 2.38 (`merge-tree --write-tree`)**: older git would silently misclassify. Mitigation: version-check in the script; below threshold report `unknown` prediction with an explicit reason (fail loud, never guess); bats covers the fallback.
- **Worktree fixtures are fiddly in bats**: backdated commits and porcelain parsing vary across git versions. Mitigation: reuse the existing `tests/fixtures` and `tests/helpers` patterns from PRD 00001's suite; pin assertions to porcelain formats, not human output.
- **Skill executes destructive git commands**: a wrong removal loses work even with a correct script. Mitigation: removal commands run only on `gc_safe=yes` rows after explicit confirmation; `git worktree remove` without `--force` and `git branch -d` both make git itself the final safety check.
