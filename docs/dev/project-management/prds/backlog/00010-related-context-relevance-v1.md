# Make catchup's Related context section return prior art, not the topic it was built from

Source: finding 1 of engram PRD 00002's close-out
(`engram/dev/local/reviews/00002-code-retrieval-investigation.md`, 2026-08-06). Observed
on the feature's first real run, in `doogat/ddb`.

## Overview

### Problem Statement

The `## Related context` capsule section shipped in git-ferry v0.3.0 is correct and
useless at the same time. On its maiden run it returned five hits, at both repo and
portfolio scope, and **every one of them was the wip PRD the topic had been built from**.

The mechanism is circular by construction. Catchup builds the topic from the single wip
PRD's title (on master the branch name contributes nothing), then queries an index that
contains that very PRD. The PRD's own title block is the single best lexical and semantic
match for its own title, so it and its neighbouring chunks occupy the whole top-5 and
crowd out anything else. Portfolio scope returned the identical five rows - the wider
query surfaced nothing at all.

The capsule said so in its own words: "the results are thin", "no external context to
carry in". The reader is shown five pointers into a file they already have open, which is
worse than showing nothing, because it reads as "engram searched and there is no prior
art" when engram was never given a chance to look for any.

Cost per catchup today: one `engram index` refresh plus three `engram query`/`status`
calls, for zero prior art on the case the feature was built for.

This is not an engram retrieval defect. Retrieval did exactly what it was asked. The
defect is in how catchup forms the question and what it accepts as an answer.

### Target Users

Any agent starting work via `/catchup` - the section exists to put prior work on the page
before the first edit, and today it does not.

### Success Metrics

- On a repo with exactly one wip PRD, the section either contains at least one hit that
  is **not** the topic-source PRD, or states explicitly that a widened query still found
  no external prior art. Never five rows of the topic source presented as results.
- Topic construction and hit filtering are exercised by `bats` tests rather than living
  only as SKILL.md prose a model may or may not follow.
- The section is still always written, and still degrades to a one-line gap note when
  engram is absent, the repo is unregistered, or there is no topic. No regression to the
  never-silently-absent rule.
- Measured on `doogat/ddb` at its 2026-08-06 state: the section carries at least one hit
  outside `dev/local/prds/wip/`, or an explicit "no external prior art" line.

## Functional Decomposition

### Capability: Ask a question worth answering

#### Feature: Topic built from substance, not title

- **Description**: Derive the query text from what the PRD is *about*, not from the
  string that names it.
- **Inputs**: Branch name; the single wip PRD path when present.
- **Outputs**: One topic string.
- **Behavior**: Prefer the PRD's Problem Statement prose over its title - a title is a
  label optimised for uniqueness, which is precisely what makes it retrieve only itself,
  while the problem statement describes the domain and matches other work in that domain.
  Keep the branch-name contribution for feature branches. On master with no single wip
  PRD there is still no topic, unchanged.

#### Feature: Exclude the topic's own source

- **Description**: A hit that is the document the question came from is not prior art.
- **Inputs**: Query results; the topic-source path(s).
- **Outputs**: Results with the topic source removed.
- **Behavior**: Filter the topic-source PRD path out of both scopes' results before
  rendering. Filtering after the query (rather than trying to scope it away) keeps engram's
  interface unchanged and keeps the rule visible where a reader of the section can check
  it.

#### Feature: Widen once when everything was self

- **Description**: Distinguish "no prior art exists" from "we only asked about ourselves".
- **Inputs**: The filtered result set.
- **Outputs**: Either a widened result set, or an explicit no-prior-art statement.
- **Behavior**: If filtering empties the results, re-query once with a broader topic (the
  PRD's capability headings, or the branch name alone) before concluding. If the widened
  query is also empty, say so in one line - that is a real and useful finding, but it must
  be earned by a query that could have succeeded.

### Capability: Testable extraction

#### Feature: related-context.sh

- **Description**: Move topic construction, filtering, and the widen decision out of
  SKILL.md prose into a script the repo can test.
- **Inputs**: Repo root; optional `--base`; the engram binary on PATH.
- **Outputs**: The rendered section body on stdout, or a gap-note line.
- **Behavior**: Follows the repo's existing convention of `skills/<name>/scripts/*.sh`
  driven from SKILL.md with `bats` coverage, the same shape as `branch-diff.sh` and
  `list-task-sessions.sh`. The topic remains untrusted input and is passed as a quoted
  variable, never interpolated - v0.3.0's `2131a62` fix must survive the move.

## Structural Decomposition

### Repository Structure

```
claude-git-ferry/
├── skills/catchup/
│   ├── SKILL.md                              # EDIT: call the script, drop the inline recipe
│   └── scripts/
│       └── related-context.sh                # NEW: topic, query, filter, widen, render
├── tests/
│   ├── related-context.bats                  # NEW
│   └── fixtures/                             # EXTEND: repo with a wip PRD; fake engram on PATH
└── CHANGELOG.md                              # EDIT: Fixed entry
```

### Module: skills/catchup/scripts/related-context.sh

- **Maps to capability**: Ask a question worth answering; Testable extraction
- **Responsibility**: Every decision that today lives as prose - which PRD is "the single
  wip PRD", what the topic is, which hits are self, whether to widen, what the gap note
  says. Read-only apart from stdout.
- **Exports**: CLI: `related-context.sh [--base <branch>]`; section body on stdout;
  gap-note line and exit 0 when engram is unavailable or unusable, so catchup can never
  be blocked by it.

### Module: skills/catchup/SKILL.md

- **Maps to capability**: Ask a question worth answering (consumer)
- **Responsibility**: Invoke the script via `${CLAUDE_SKILL_DIR}`, paste its output into
  the capsule section, and keep the never-silently-absent rule.
- **Exports**: Skill entry; no code.

## Dependency Graph

### Foundation Layer (Phase 0)

- **Fixtures + fake engram**: a stub `engram` on PATH returning canned rows, so tests
  never depend on a real index or an embedding server.

### Core Layer (Phase 1)

- **related-context.sh**: Depends on [fixtures].

### Integration Layer (Phase 2)

- **SKILL.md rewrite + CHANGELOG + release**: Depends on [Phase 1].

## Implementation Phases

### Phase 0: Foundation

**Goal**: The behaviour can be tested without an index.

**Tasks**:

- [ ] Build a bats fixture repo with one wip PRD, plus a stub `engram` whose `query`
      output is scripted per-test (no deps) - Acceptance: a test can make engram return
      all-self rows, mixed rows, or nothing, and can assert the stub was called with the
      topic as a single argv entry.

**Exit Criteria**: Fixture harness green and callable from bats.

### Phase 1: Core

**Goal**: The script asks a better question and refuses to pass off self-hits as answers.

**Tasks**:

- [ ] TDD topic construction (depends on: Phase 0) - Acceptance: master + one wip PRD
      yields a topic drawn from the Problem Statement, not the title; feature branch
      contributes its cleaned branch name; master + zero or multiple wip PRDs yields no
      topic and the documented gap note.
- [ ] TDD self-filtering and the single widen (depends on: previous) - Acceptance: rows
      pointing at the topic-source PRD are removed; when that empties the set the stub is
      queried a second time with the widened topic; when the widened query is also empty
      the output is the explicit no-prior-art line, not an empty section.
- [ ] TDD injection safety (depends on: Phase 0) - Acceptance: a PRD title containing
      `"`, a backtick and `$(...)` reaches the stub as one literal argument and executes
      nothing.

**Exit Criteria**: `bats tests/` green.

### Phase 2: Integration

**Goal**: Catchup uses it and the plugin ships.

**Tasks**:

- [ ] Rewrite SKILL.md's Related context step to call the script (depends on: Phase 1) -
      Acceptance: the inline command recipe is gone; the never-silently-absent rule and
      the capsule template section survive; create-skill validator passes.
- [ ] CHANGELOG `### Fixed` entry prefixed `**catchup**:` and release (depends on:
      previous) - Acceptance: entry states the circularity and what changed; `dev/bin/release`.

**Exit Criteria**: A real catchup run in a repo with a wip PRD produces a section whose
hits are not all the topic source.

## Test Strategy

### Critical Scenarios

- **Happy path**: repo with a wip PRD and genuine related work elsewhere → Expected:
  at least one non-self hit rendered.
- **Edge case**: the only matches are the topic source → Expected: widened re-query, then
  an explicit no-prior-art line.
- **Edge case**: PRD title with shell metacharacters → Expected: one literal argv entry,
  nothing executed.
- **Error case**: `engram` absent, or present but the repo is not gita-registered (its
  `index` exits nonzero) → Expected: section still written, one-line gap note, exit 0.

## Risks

- **Problem-statement topics may be too broad** and return loosely-related noise instead
  of nothing. Mitigation: the section already prints scores; judge on the ddb measurement
  in Success Metrics before widening further, and keep the title as a fallback if the
  prose topic underperforms.
- **Moving logic out of SKILL.md changes who is in control.** A script cannot use judgment
  the way the model could. Mitigation: the script only gathers and filters; the model
  still writes the prose "why it is relevant" half-line per hit.
- **Self-filtering could hide a legitimately relevant PRD** when the topic source really
  is the best answer for a different reason. Mitigation: filter only the exact
  topic-source path, never the whole `prds/` tree.
