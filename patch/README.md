# patch/: a change this session could not push

`0001-ci-publish-a-go-target.patch` adds a `go` target to
`.github/workflows/publish.yml`, and says so in `AGENTS.md`. A session's push
access refuses any change under `.github/workflows/`, so the change arrives
as a patch. It applies to `main` at `d47ba41`.

Apply it on `main`, push, and then this folder can go:

```sh
git checkout main && git pull
git fetch origin claude/bold-newton-4of9bo
git show FETCH_HEAD:patch/0001-ci-publish-a-go-target.patch | git am
git push origin main
```

**What it touches.** `publish.yml` gains `go` among the dispatch targets, and
two jobs:

- `verify-go` (`contents: read`) runs `make build`, `make vet` and
  `make test` in `go/`, which are the steps `make publish-go` runs before it
  tags.
- `tag-go` (`contents: write`) then writes the annotated tag
  `go/v<go/VERSION>`, as `go/Makefile` does.

It keeps the other targets' guards: a dispatch from `main` only,
`expect_sha`, refusing a tag already on another commit, and `dry_run`
writing no tag. There is no push trigger for `go/v*`, since a Go tag pushed
by hand is already the release.

**Why.** Go has no registry, so a Go release is the tag alone, and until now
only `make publish-go` on a workstation could write it. With this,
`go/v0.2.0` is one dispatch: target `go`, with `expect_sha` set to `main`
after the patch. `go/` there is the same tree as at `d47ba41`, the commit
npm's `@voxgig/struct` 0.4.0 and `@voxgig/struct-js` 0.2.0 were built from.

**Checked.** actionlint 1.7.7, with shellcheck, passes on the changed
workflow, and `make build`, `make vet` and `make test` pass in `go/` at
`d47ba41`.
