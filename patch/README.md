# `patch/` — a workflow change this session could not push

`.github/workflows/` is refused to the session that wrote this change, on
both write paths: `git push` without `workflow` scope, and the GitHub App's
file API. The change is workflow-only, so it travels as a patch. This
folder is transient: delete it once the patch is applied.

## Apply it

From an up-to-date `main`:

```sh
git am patch/0001-ci-php-run-the-macOS-leg-on-macos-15.patch
git rm -r -q patch && git commit -m "patch: drop the applied workflow patch"
```

`git apply --check <file>` answers whether it has already landed. It
applies cleanly to `main` at `18d6237` and to
`claude/wizardly-keller-f9p1er`, the branch of
[pull request 178](https://github.com/voxgig/struct/pull/178).

## 0001 — test-php's macOS leg on `macos-15`

`test-php (macos-latest)` has failed in its `Setup PHP` step in six of its
last seven attempts, on `main` and on the pull request alike.
`shivammathur/setup-php` reports "Could not setup PHP 8.3" after 7 to 29
minutes, `php` is never on `PATH`, and no test runs.

Every attempt, passing or failing, ran on the `macos-26-arm64` image, so
the image did not change under the job. On 2026-10-19 the step installed
PHP 8.3.35 there in 44 seconds. The one recent pass, on 2026-11-09, took
4 minutes to install 8.3.36, and the failures began alongside that
release. The action hides Homebrew's output, so the cause is a reading of
those timings, not of a log line.

`macos-15` takes the leg off the image where the install broke, as
`test-zig` already does.

This leg is unmeasured on `macos-15` until a run picks it up. If it fails
there too, the alternatives are to wait for the upstream install to
recover, or to test a different PHP minor version on macOS. That second
one is a decision about the test matrix, so it is left to the maintainer.

## Checks

- the patch applies with `git am` onto `main` and onto the pull request's
  branch
- `build.yml` parses as YAML after it
- `actionlint` is not installed in the session that wrote this, so it was
  not run
