# `patch/` — a change this session could not push

`.github/workflows/` is refused to the session that wrote this change, on
both write paths:

- **git push** — `refusing to allow an OAuth App to create or update workflow
  .github/workflows/lint.yml without workflow scope`
- **the GitHub App's file API** — fails on that path while writing any other
  file in the same breath

The change is entirely a workflow change, so it cannot travel as a branch.
This folder is transient: delete it once the patch is applied.

## Apply it

```sh
git show origin/claude/struct-omni-pin-patch:patch/0001-ci-OMNI_REF-is-one-pin-written-three-times-so-make-t.patch | git am
```

The command streams the patch out of the delivery commit rather than reading
it from the worktree, so it works from any checkout — including `main` after
this merges.

## What it fixes

`OMNI_REF` is defined three times, because GitHub gives workflow files no way
to share an `env`. It had two values:

| file | pin |
|---|---|
| `build.yml` | `fbf1da64e3c90fc54e3c6b237b0b5835890df8c4` |
| `publish.yml` | `fbf1da64e3c90fc54e3c6b237b0b5835890df8c4` |
| `lint.yml` | `064af05a693adfda4400cbdfd85d24d894172da5` — **eight commits behind** |

`064af05` is an ancestor of `fbf1da6`, so `lint.yml` was the stale copy. The
patch bumps it to what the other two already use, and moves no other pin —
which omni this repository tests against is a deliberate act, as `build.yml`'s
own comment says.

## Why it matters

Every port's lint job checks out omni at `OMNI_REF` and hands its sources to
the linter alongside the tests. A green lint run against one omni and a green
build run against another do not compose into a claim about either: the two
gates were reading different corpus runners and reporting one verdict.

## And why a comment was not enough

`publish.yml` already stated the invariant in writing — *"pinned to the same
commit build.yml checks out"* — and `lint.yml` drifted anyway. So the patch
adds a step to `security.yml`'s `workflows` job that fails when the three
disagree. It is deliberately a `grep` rather than a Python tool: it reads the
same three lines a person reads, and a disagreement between workflow files is
what that job already exists for.

## Checks

- the guard was run against the drift it is meant to catch: **before**, two
  values, exit 1, all three lines named; **after**, one value, pass
- `actionlint` with `shellcheck`: clean across every workflow in the repo
- `git am` onto `main`: clean, and all three touched files parse as YAML

## A separate observation, not fixed here

**Neither pin value is on `voxgig/omni`'s `main`.** Both `fbf1da6` and
`064af05` are reachable only from unmerged `claude/*` branches there. That may
be intentional — the comment describes pinning to a paired omni commit while
that work is in flight — but if it is not, the fix is the one-line bump the
comment already describes, to a commit on omni's default branch. That is a
decision about which omni this repository tests against, so it is left to the
maintainer rather than folded into a consistency fix.
