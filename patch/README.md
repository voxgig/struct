# `patch/` — two workflow changes this session could not push

`.github/workflows/` is refused to the session that wrote these changes, on
both write paths: `git push` without `workflow` scope, and the GitHub App's
file API. Both changes are workflow-only, so they travel as patches. This
folder is transient: delete it once the patches are applied.

## Apply them

From an up-to-date `main`:

```sh
git am patch/0001-ci-swift-run-the-Linux-leg-on-ubuntu-24.04.patch \
       patch/0002-ci-zig-move-the-macOS-leg-from-macos-14-to-macos-15.patch
git rm -r -q patch && git commit -m "patch: drop the applied workflow patches"
```

The two touch different jobs in `build.yml` and apply in either order, or
one without the other. `git apply --check <file>` answers whether one has
already landed. Both apply cleanly to `main` at `a7790de` and to
`claude/wizardly-keller-f9p1er`, the branch of
[pull request 178](https://github.com/voxgig/struct/pull/178), whose CI
they unblock once `main` carries them.

## 0001 — test-swift's Linux leg on `ubuntu-24.04`

`ubuntu-latest` now resolves to the `ubuntu-26.04` image.
`SwiftyLab/setup-swift` still installs the `swift-6.0.2-RELEASE-ubuntu2404`
toolchain there, and `make test` fails before compiling anything:

```text
swift-test: error while loading shared libraries: libxml2.so.2: cannot open shared object file: No such file or directory
```

The leg passed on `main` on 2026-10-19, on the 24.04 image the patch pins
back to. A toolchain built for 26.04 is the longer fix, and a separate one.
When the Linux leg fails, fail-fast cancels the macOS leg with it, so this
one patch clears two red jobs.

## 0002 — test-zig's macOS leg on `macos-15`

`test-zig (macos-14)` was not assigned a runner in any of four attempts on
2026-11-08 and -09: `runner_id` 0, cancelled before a step ran. It passed
on `main` on 2026-10-19.

`macos-15` rather than `macos-latest`, because under the 0.13 pin the
macOS 26 SDK on `macos-latest` left every libc symbol undefined, and 0.16
has not been measured against it. `macos-15` is arm64, so it takes the
`macosx_12_0_arm64` wheel that `.github/zig-requirements.txt` already
hashes, and its SDK is the nearest to the 14 this leg last linked against.
The two comments that named the `macos-14` pin now say what they hold.

This leg is unmeasured until a run picks it up.

## Checks

- each patch applies alone, and both apply with `git am`, onto `main` and
  onto the pull request's branch
- `build.yml` parses as YAML after each
- `actionlint` is not installed in the session that wrote these, so it was
  not run

## Not covered

`test-php (macos-latest)` failed twice on the pull request's head in the
`Setup PHP` step (`shivammathur/setup-php`: "Could not setup PHP 8.3",
after 17 and 29 minutes), where the same job had passed in 4 minutes on
the commit before. That reads as intermittent rather than as a pin to
move, so no change is proposed for it.
