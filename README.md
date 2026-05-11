[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

# git-ferry

> Skills that carry you across git's awkward crossings: branch context, upstream drift, merge conflicts, CI waits, GitHub busywork.

## What's inside

| Skill | Triggers on |
|---|---|
| `catchup` | "catchup", "what changed on this branch", "project overview", "refresh capsule" |
| `catchup-upstream` | "sync upstream", "catchup upstream", "sync fork", "check upstream" |
| `resolve-git-conflicts` | merge/rebase/cherry-pick/stash conflicts; "unmerged paths", "rebase in progress" |
| `watch-ci` | "watch CI", "wait for CI", "check CI", "are checks passing", "monitor build" |
| `sync-plan-issue` | "sync plan to github", "update issue with plan", "share plan", "create issue from plan" |
| `review-deps-prs` | "review deps", "check dep updates", "dependency prs", "dep updates" |

## Install

```
/plugin marketplace add buvis/claude-plugins
/plugin install git-ferry@buvis-plugins
```

## Update

```
/plugin update git-ferry@buvis-plugins
```

## Alternative: install directly from this repo

```
/plugin marketplace add buvis/claude-git-ferry
/plugin install git-ferry@claude-git-ferry
```

## Why "git-ferry"

A ferry's job is unglamorous: get you from one bank to the other without losing cargo. These skills are the same — they shuttle you across branch boundaries, upstream drift, conflict resolution, and CI gates. Nothing flashy; just safe passage.

## License

MIT
