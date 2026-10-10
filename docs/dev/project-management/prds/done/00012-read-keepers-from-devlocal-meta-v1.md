# Read and write dev/local keepers at their meta/ home

Source: 2026-08-23 `~/.claude` layout change - keepers moved from `dev/local`
root to `dev/local/meta/` (canonical), with compat symlinks left at root so
released plugins keep working. This PRD repoints git-ferry so the symlinks can
retire (`~/.claude` PRD 00139 removes them once all three plugin repoints ship).

## Overview

### Problem Statement

Two shipped skills hard-code root keeper paths:

- `skills/catchup/SKILL.md` reads and writes `dev/local/project-capsule.md`.
- `skills/catchup-upstream/SKILL.md` reads and writes `dev/local/upstream-cursor`.

Both still work today only because every migrated store carries a root symlink
into `meta/`. The moment the symlinks retire, catchup writes a root stray (the
layout hook then blocks it) and catchup-upstream loses its cursor.

### Success Metrics

- `rg -n "dev/local/(project-capsule|upstream-cursor)" skills/` returns only
  `dev/local/meta/...` forms.
- `/catchup` on a migrated store updates `dev/local/meta/project-capsule.md`
  (root symlink untouched); on an unmigrated store it still finds the root file.

## Functional Decomposition

### Capability: keeper paths are meta-first with root fallback

Reads try `dev/local/meta/<name>` first and fall back to `dev/local/<name>`
(unmigrated stores, other machines). Writes go to `dev/local/meta/<name>`,
creating `meta/` if absent.

## Implementation Phases

### Phase 1: Repoint and release

1. `skills/catchup/SKILL.md`: capsule path -> `dev/local/meta/project-capsule.md`
   (write target), read instruction gains the root fallback sentence.
2. `skills/catchup-upstream/SKILL.md`: same treatment for
   `dev/local/upstream-cursor`.
3. Sweep the repo (`README`, scripts, tests) for the two keeper names; repoint
   any stragglers.
4. CHANGELOG entry under `### Changed`.
5. Release and update the installed plugin - a plugin fix is not done until it
   ships (`~/.claude` PRD 00118 precedent).

*Acceptance:* success metrics above; plugin script tests green.

## Test Strategy

- If the repo has prose-lint tests over shipped skill files, bind the
  meta-first path there; otherwise the acceptance sweep is the check.

## Risks

- **Foreign repos without meta/**: the write step creates `meta/` on demand;
  the read fallback covers stores migrated later.
