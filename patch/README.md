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

`AGENTS.md` §"An agent session cannot write `.github/workflows/`" gives the
form, and this folder follows it. **Apply it from this branch, while the
branch still exists:**

```sh
git fetch origin claude/struct-omni-pin-patch
git checkout claude/struct-omni-pin-patch
git am < patch/0001-ci-OMNI_REF-is-one-pin-written-three-times-so-make-t.patch
```

**Do not merge this pull request to get the patch onto `main`.** The same
section is explicit that *"a `patch/` on `main` is a bug; a `patch/` on a
short-lived branch, with an open PR explaining it, is the mechanism
working"* — applied, the file only duplicates the history it just created,
and left behind it blocks releases, because `make publish-all` and the port
`publish` targets refuse to run against `git status --porcelain` output. So
this PR is a **carrier**: take the patch out of it and close it.

Two earlier drafts of this section were wrong, and both are corrected rather
than quietly replaced, because the wrong forms are the ones quoted in the
pull request description:

1. It read the patch from `origin/claude/struct-omni-pin-patch:…` through
   `git show`. That fails once the branch is deleted, and a fresh clone never
   had it.
2. It then said the command works from `main` "once the delivery commit is
   merged" — which contradicts the rule above. The carrier is not supposed to
   reach `main` at all.

`git apply --check` answers quickly whether the change already landed, which
is worth running first if this branch has been sitting.

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

**Agreeing is not enough, and the first draft of the check only checked that.**
Comparing distinct values passes when a definition goes *missing*, because the
survivors still agree with each other — and a workflow that lost its
`env.OMNI_REF` while keeping its `ref:` uses resolves the ref to the empty
string, which `actions/checkout` reads as the default branch. That is the exact
floating checkout the pin exists to prevent, reached silently and with the
consistency gate green. The check now asserts the definition is present exactly
once in every workflow that uses the value, and compares the values afterwards.

It counts a use as an anchored `key: ${{ ... }}` rather than the bare name,
because `security.yml` would otherwise match itself — its comment and its
failure message both spell the name. That is not hypothetical: it is what the
first run of the hardened loop did.

## Checks

Four cases, with the step's script extracted verbatim from the YAML:

| case | result |
|---|---|
| patched tree | pass |
| `lint.yml` loses its definition, keeps its five uses | fail, naming the file |
| `lint.yml` back to `064af05` | fail, naming all three |
| restored | pass |

The second is the case the first draft of the check passed.

- `actionlint` with `shellcheck`: clean across every workflow in the repo
- `git am` of this patch: clean, and all three touched files parse as YAML

## A separate observation, not fixed here

**Neither pin value is on `voxgig/omni`'s `main`.** Both `fbf1da6` and
`064af05` are reachable only from unmerged `claude/*` branches there. That may
be intentional — the comment describes pinning to a paired omni commit while
that work is in flight — but if it is not, the fix is the one-line bump the
comment already describes, to a commit on omni's default branch. That is a
decision about which omni this repository tests against, so it is left to the
maintainer rather than folded into a consistency fix.
