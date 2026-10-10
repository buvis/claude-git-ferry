# Retire catchup's task-restore phase, which is built on tools that no longer exist

Source: deferred finding of `~/.claude` PRD 00120's cycle-1 review
(`~/.claude/dev/local/autopilot/deferred/202608162223-deferred.json`, HIGH, raised by
Bob, 2026-08-16). Confirmed at git-ferry HEAD on 2026-08-17.

## Overview

### Problem Statement

`skills/catchup/SKILL.md:143` instructs the model to call `TaskCreate` with
`subject`/`description`/`activeForm`, then `TaskUpdate` with `addBlockedBy`, to restore the
previous session's tasks. **Neither tool exists.** `CLAUDE_CODE_ENABLE_TODO_TOOLS` was
removed from the user's `settings.json` when `~/.claude` PRD 00120 migrated autopilot task
tracking to `statectl`, and the task tools are not available on this model tier at all.

The two readers behind the phase are dead as well: no `tasks/` directory exists under any
`~/.claude/projects/*/` on this machine, so `list-task-sessions.sh` returns
`no_tasks_dir` and Phase 4 already skips silently on every run.

So the phase is dormant rather than broken today, which is the trap. The instruction is
live prose a model executes. The moment a session does find a `tasks/` directory - an older
transcript, a different tier, a machine where the flag is still set - catchup reaches Phase
4, follows line 143, and calls a tool that is not there. A skill whose documented path ends
in a nonexistent tool call is a defect whether or not it fires this week.

`rg 'TaskCreate|TaskUpdate|TaskList|TaskGet|TodoWrite'` over the whole repo returns exactly
one file and one line, so the blast radius is small and known.

### Target Users

The operator running `/catchup` at the start of a session, and any other user of the
released git-ferry plugin (v0.3.0 is the installed version and carries the same line).

### Success Metrics

- `rg 'TaskCreate|TaskUpdate|TaskList|TaskGet|TodoWrite'` over the repo: **0 hits**.
- No shipped script reads a task store that no longer exists.
- `/catchup` Phase 5 report is unchanged for a session with no prior tasks - the common
  case today - so the retirement is invisible to normal use.

## Functional Decomposition

### Capability: Catchup stops promising a restore it cannot perform

Phase 4 is removed from `SKILL.md`, together with the two helper scripts that exist only to
feed it (`list-task-sessions.sh`, `dump-tasks.sh`) and their tests. The Phase 5 report loses
its `Restored N tasks from session …` line.

**Recommended over the alternative, and why:** the alternative is to keep the readers and
degrade the phase to a report-only summary ("N unfinished tasks from the last session"),
which preserves some value. It is rejected because the store it reads no longer exists on
this platform, so the degraded phase would print nothing forever while still costing two
script invocations per catchup. Delete beats a feature that can only ever say "none".

## Structural Decomposition

### Module: skills/catchup/SKILL.md

Delete Phase 4 (the block from the `list-task-sessions.sh` invocation through the
`Restored N tasks` note, currently lines ~124-145) and renumber Phase 5 → Phase 4. Check the
skill body for any other reference to task restore, including the frontmatter description
and any phase count stated up front.

### Module: skills/catchup/scripts/

Delete `list-task-sessions.sh` and `dump-tasks.sh`, plus their tests under `dev/` or
`tests/` if any exist. Leave `branch-diff.sh`, `github-state.sh`, `load-memories.sh` and
`related-context.sh` untouched.

## Dependency Graph

### Core Layer (Phase 1)

The SKILL.md edit and the script deletions are one change; the scripts are referenced only
by the deleted phase.

## Implementation Phases

### Phase 1: Core

1. Delete Phase 4 from `SKILL.md`, renumber the phase that follows it, and remove the
   `Restored N tasks` reporting line.
2. Delete the two scripts and any test that covers them.
3. Sweep the repo for the five retired tool names and for `dump-tasks` /
   `list-task-sessions` string references (README, CHANGELOG guidance, plugin manifest).
4. CHANGELOG entry under `### Removed` (breaking-ish: a documented capability disappears).
5. Release via `dev/bin/release` and update the installed plugin. **A plugin fix is not
   done until it ships** - `~/.claude` PRD 00118 sat fully implemented and inert for ten
   days because its release was never cut.

*Acceptance:* the sweep returns 0 hits; the plugin's own script tests stay green;
`/catchup` runs end to end on a repo and its report reads correctly with the phase gone.

## Test Strategy

### Critical Scenarios

- Repo-wide sweep for the retired tool names returns nothing (bind it as a test if the repo
  already has a lint-style test for shipped-file contents; otherwise the acceptance sweep
  is the check).
- `/catchup` on a clean master and on a feature branch: report renders, no missing-phase
  artifacts, no reference to task restore.

## Risks

- **Someone wanted the restore.** It has been silently skipping on this machine already, so
  nothing observable is lost. If task tools return to the tier, the phase can come back
  against whatever the new store is - the deleted version would not have worked with it
  anyway.
