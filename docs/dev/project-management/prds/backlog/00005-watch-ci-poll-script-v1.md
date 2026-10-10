# Deterministic Watch-CI Polling Script

## Overview

### Problem Statement
`skills/watch-ci/SKILL.md` is prose-only: it instructs the agent to resolve the run id, poll `gh run view` every 30 seconds, time out after 15 minutes, back off to 60 seconds on rate limits, collect failure logs, and fire an optional ntfy notification. Every poll is an LLM round trip, so a 10-minute CI run burns ~20 model turns doing `sleep`-shaped work. This violates the project's ai-app-design rule (retries, backoff, and polling belong in code, not the model) and contradicts the plugin's own architecture, where catchup and review-deps-prs delegate deterministic work to tested scripts. Prose also cannot be tested: the existing bats harness covers every script in the repo, but watch-ci has none.

### Target Users
Anyone running watch-ci after a push: they get the same outcome with one tool call instead of a poll-per-turn loop, at lower token cost and with tested timeout/backoff behavior.

### Success Metrics
- One script invocation covers identify, poll, timeout, failure-log collection, and notification; SKILL.md contains no polling loop instructions.
- The script's branches are covered by bats tests using the existing gh stub (>= 80%, per project rule).
- Poll interval and timeout are env-overridable, so tests run in milliseconds and users can tune waits.
- The script's final `RESULT:` line is machine-readable; the skill branches on it without re-querying gh.

## Functional Decomposition

### Capability: Deterministic CI watching
One blocking script call that returns when CI finishes or limits are hit.

#### Feature: Resolve target run
- **Description**: Find the workflow run for the current branch HEAD.
- **Inputs**: Current branch, `git rev-parse HEAD`, gh.
- **Outputs**: A run id, or a `RESULT: no_runs` outcome.
- **Behavior**: `gh run list --branch <branch>` filtered to `headSha == HEAD`; if absent, wait 10s and retry once (a just-pushed run may not be registered yet); still absent -> report no_runs.

#### Feature: Poll until completion
- **Description**: Block until the run completes or the timeout fires.
- **Inputs**: Run id; `WATCH_CI_POLL_SECONDS` (default 30), `WATCH_CI_TIMEOUT_SECONDS` (default 900).
- **Outputs**: Final status/conclusion, or a timeout outcome with the last-seen status.
- **Behavior**: Loop on `gh run view --json status,conclusion`; sleep the interval between polls; on gh stderr indicating rate limiting, double the interval (cap 60s); on timeout, stop and report.

#### Feature: Collect failure details
- **Description**: On failure, gather what the agent needs to debug.
- **Inputs**: The completed run id.
- **Outputs**: Failed-job names and `gh run view --log-failed` output, printed in labeled sections.
- **Behavior**: Only on `conclusion: failure`; a log-fetch error prints an `(unavailable: ...)` marker instead of failing the whole watch.

#### Feature: Notify via ntfy
- **Description**: Optional push notification on completion.
- **Inputs**: `NTFY_URL`, `NTFY_TOPIC` env vars; the conclusion and branch.
- **Outputs**: A curl POST, or nothing when unset.
- **Behavior**: Fire only when both vars are set; a notification failure is reported but never changes the exit outcome.

#### Feature: Structured outcome
- **Description**: A machine-readable final line plus matching exit code.
- **Inputs**: The watch outcome.
- **Outputs**: `RESULT: success | failure | cancelled | timeout | no_runs` as the last stdout line; exit 0 for success, non-zero otherwise.
- **Behavior**: Exactly one RESULT line, always emitted; gh missing/unauthenticated exits non-zero with the message before any RESULT line.

### Capability: Skill delegation
Make the SKILL.md a thin consumer of the script.

#### Feature: SKILL.md invokes the script
- **Description**: Replace the manual loop with one script call and result interpretation.
- **Inputs**: The script's stdout and RESULT line.
- **Outputs**: The user-facing summary; on failure, the debugging offer (`superpowers:systematic-debugging` if available).
- **Behavior**: Run `"${CLAUDE_SKILL_DIR}/scripts/watch-run.sh"`; branch on RESULT; keep the existing error-handling table semantics (no remote, unauthenticated, no runs).

## Structural Decomposition

### Repository Structure

```
skills/watch-ci/
├── SKILL.md               # Maps to: SKILL.md invokes the script
└── scripts/
    └── watch-run.sh       # Maps to: Deterministic CI watching
tests/
└── watch-run.bats         # Maps to: watch-run.sh coverage (existing harness + gh stub)
```

### Module: skills/watch-ci/scripts
- **Maps to capability**: Deterministic CI watching
- **Responsibility**: Block until the relevant run completes; report outcome, failure detail, and notification deterministically.
- **Exports**:
  - `watch-run.sh` - the blocking watcher with env-tunable interval/timeout and a final RESULT line

### Module: skills/watch-ci/SKILL.md
- **Maps to capability**: Skill delegation
- **Responsibility**: Invoke the script, interpret RESULT, summarize for the user, offer debugging on failure.
- **Exports**: watch-ci workflow prose

## Dependency Graph

### Foundation Layer (Phase 0)
No dependencies - built first. Tests reuse the existing 00001 harness (temp repos, gh PATH stub); the stub gains `gh run view`/`gh run list` behaviors driven by fixture files.

- **gh-stub run-watching fixtures**: canned run-list/run-view responses, including a sequence that flips from in_progress to completed.

### Core Layer (Phase 1)
- **watch-run.sh**: Depends on [gh-stub run-watching fixtures].

### Integration Layer (Phase 2)
- **SKILL.md rewrite**: Depends on [watch-run.sh].

## Implementation Phases

### Phase 0: Foundation
**Goal**: Failing tests that pin the contract.

**Tasks**:
- [ ] Extend the gh stub/fixtures so `gh run list`/`gh run view` replay a scripted sequence (in_progress -> completed) and can simulate rate-limit stderr (no deps) - Acceptance: stub replays a sequence file deterministically.
- [ ] Write failing `watch-run.bats`: success path, failure path with log collection, no_runs after retry, timeout with tiny `WATCH_CI_TIMEOUT_SECONDS`, ntfy fired only when both env vars set (no deps) - Acceptance: tests fail before the script exists.

**Exit Criteria**: Test list covers every RESULT value; all red.

### Phase 1: Core
**Goal**: The watcher itself.

**Tasks**:
- [ ] Implement `watch-run.sh` (resolve, poll, timeout, backoff, failure detail, ntfy, RESULT line) (depends on: Phase 0) - Acceptance: all watch-run tests green; shellcheck clean; coverage table added to `tests/README.md`.

**Exit Criteria**: `bats tests/` green including the new suite, fast (no real 30s sleeps in tests).

### Phase 2: Integration
**Goal**: The skill consumes it.

**Tasks**:
- [ ] Rewrite SKILL.md to call the script and branch on RESULT; keep the debugging offer and error-handling table (depends on: Phase 1) - Acceptance: SKILL.md contains no poll-loop instructions; manual run on a real push reports the CI outcome in one call.
- [ ] CHANGELOG `Changed` entry (watch-ci now polls via a script) (depends on: Phase 1) - Acceptance: entry under Unreleased.

**Exit Criteria**: watch-ci end-to-end on this repo's CI completes with a single script invocation.

## Test Strategy

### Critical Scenarios
- **Happy path**: stub replays in_progress -> completed/success -> `RESULT: success`, exit 0.
- **Happy path**: completed/failure -> failed-job section, log-failed section, `RESULT: failure`, non-zero exit.
- **Edge case**: no run for HEAD on first query, present on retry -> watched normally; absent on both -> `RESULT: no_runs`.
- **Edge case**: timeout reached while in_progress -> `RESULT: timeout`, last-seen status reported.
- **Error case**: gh unauthenticated -> non-zero exit, documented message, no RESULT line.

## Risks

- **Sleeps make tests slow**: all intervals env-overridable; tests set them near zero. Never hardcode the 30s/900s values inline.
- **Polling semantics drift from gh's JSON shape**: the stub fixtures mirror real `gh run list/view --json` output captured once; a comment in the fixture notes the gh version.
- **Long-blocking Bash call in the harness**: the Bash tool default timeout (120s) is below the 15-minute watch ceiling; SKILL.md must tell the agent to pass an explicit timeout when invoking the script.
- **Default-branch coupling**: the script takes the current branch from git, never hardcodes `master`/`main`, consistent with the distributed-plugin rule (see PRD 00002).
