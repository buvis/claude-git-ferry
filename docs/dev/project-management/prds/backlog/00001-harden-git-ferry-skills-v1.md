# 00001 - Harden git-ferry skills against blocked commands and silent failures

## Problem

The 2026-07-19 authoring audit (buvis home, dev/local/audit-results/2026-07-19-authoring-efficiency-audit.md) confirmed five defects in shipped skills beyond the v0.2.2 sync-plan-issue hot-fix: instructions the common aegis hook profile blocks, a poll loop no harness can run, a fail-silent error path, a hardcoded default branch, and an inconsistent script contract.

## Goal

Every git-ferry skill's instructions execute cleanly under a per-call shell with the aegis hook profile active, and failures surface loudly.

## Requirements

- R1 watch-ci: replace the sleep/poll procedure (SKILL.md:26-41) with `gh run watch <run-id> --exit-status` (optionally background + notification); add rows for run cancelled/skipped while polling; add a PR-checks variant (`gh pr checks`); drop or replace the dead `superpowers:systematic-debugging` pointer (:64) with a generic "debug it" instruction (the plugin cannot assume buvis-personal skills either).
- R2 review-deps-prs: list-dep-prs.sh stops swallowing per-repo failures (`2>/dev/null || continue`); emit `--- $REPO ERROR ---` with the gh stderr so the SKILL's documented rate-limit/auth branches can actually trigger.
- R3 catchup: detect the default branch (`git symbolic-ref refs/remotes/origin/HEAD` fallback chain, as catchup-upstream already does) instead of hardcoding master in SKILL.md:37 and branch-diff.sh:16-29; add a "no default branch detectable" error row.
- R4 catchup-upstream: replace `git remote show <remote> | grep 'HEAD branch'` (:31) with a pipe-free form (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, fallback: run `git remote show` bare and read).
- R5 catchup scripts: load-memories.sh accepts the optional project-path argument its siblings accept (`${1:-$(pwd)}`).
- R6 Portability note: skills' helper scripts are bash; document the Windows posture (WSL/git-bash requirement) in README, or state non-support explicitly.

## Acceptance

- bats suite extended: list-dep-prs error-line emission, branch-diff default-branch detection (bare `master`-less fixture), load-memories arg.
- rg finds no `| grep`, `sleep`-loop instructions, or hardcoded `master` branch assumptions in skills/.
- CHANGELOG entries per user-visible fix; minor release at the end.

## Out of scope

- sync-plan-issue (shipped in v0.2.2).

## Notes

Severities from the audit: R1 MEDIUM (two findings), R2 MEDIUM (fail-loud), R3 LOW-published/HIGH-for-main-repos, R4 MEDIUM, R5 LOW.
