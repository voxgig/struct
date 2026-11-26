# patch/: a change this session could not push

`0001-ci-publish-registry-less-targets.patch` adds six dispatch targets to
`.github/workflows/publish.yml`: `php`, `c`, `cpp`, `swift`, `zig` and
`lean`. It also says so in `AGENTS.md`. A session's push access refuses any
change under `.github/workflows/`, so the change arrives as a patch. It was
made from `main` at `320fafe`.

Apply it on `main` straight from this branch, so the folder never reaches
`main`, then close the pull request that carries it:

```sh
git checkout main && git pull
git fetch origin claude/wizardly-keller-f9p1er
git show FETCH_HEAD:patch/0001-ci-publish-registry-less-targets.patch | git am
git push origin main
```

**What it touches.** `publish.yml` gains the six ports among the dispatch
targets, and one pair of jobs, modelled on the go target's:

- `verify-registryless` (`contents: read`) sets up the target's toolchain
  as `build.yml`'s Linux lane does. It checks that every copy of the
  version agrees, and runs `make test`, the step each port's
  `make publish` runs before it tags.
- `tag-registryless` (`contents: write`) then writes the annotated
  `<lang>/v<version>` that the port's Makefile writes, named by
  `tools/bump.py --plan`.

It keeps the other targets' guards:

- a dispatch from `main` only
- `expect_sha`
- refusing a tag already on another commit
- `dry_run` writing no tag

There is no push trigger, since a tag pushed by hand is already the release.

**Why.** These six ports have no registry, so each release is the tag
alone. Until now only `make publish-<lang>` on a workstation could write it.
With this, each is one dispatch: target `php`, `c`, `cpp`, `swift`, `zig`
or `lean`, with `expect_sha` set to `main` after the patch.

**What a dispatch would release now.** `php/v0.2.0`, `c/v0.2.0`,
`cpp/v0.2.0`, `swift/v0.2.0`, `zig/v0.1.0` and `lean/v0.2.0`. These are the
versions the minor bump set, and none of those tags exists yet.

**Checked.**

- actionlint 1.7.7 with shellcheck 0.11.0 passes on the changed workflow.
- The version step resolves those six tags at `320fafe`.
- `make test` passes for `c`, `cpp` and `php` there.
- `swift`, `zig` and `lean` passed in Build run 601 on the same code.
- The patch applies to `main` at `320fafe` with `git am`.

A `dry_run: true` dispatch of each target is the rehearsal to run first,
since this changes `publish.yml`.
