# Pending patches

Work from the omni-migration session of 2026-08-26 that could not be pushed
from where it was written. Everything referenced here lives in
[`patches/`](./patches).

**Delete this file and `patches/` once the two REQUIRED patches have landed.**

## Why these are patches and not commits

The session's credentials could not write `.github/workflows/`:

    ! [remote rejected] refusing to allow an OAuth App to create or update
      workflow `.github/workflows/build.yml` without `workflow` scope

The GitHub MCP server was the fallback route, and the only way to open a pull
request from that environment; its token had expired and the session was
non-interactive, so the OAuth flow could not be run. Everything that does
*not* touch a workflow file was pushed normally.

## 1. `patches/struct-workflows-REQUIRED.patch` — this repo

**Apply this first: the branch is red without it.** The zig port now needs
Zig 0.16 (`build.zig.zon` uses an enum-literal name and a
`minimum_zig_version`, neither of which 0.13 can parse) and CI still installs
0.13, because the step that installs 0.16 is in a workflow file.

    git apply patches/struct-workflows-REQUIRED.patch
    git commit -am "ci: pin the omni checkout, and take Zig 0.16 from PyPI"

`git apply`, not `git am` — this one is `git diff` output, so it carries no
commit message of its own.

Three changes, all in `build.yml` and `lint.yml`:

- **Pins the omni checkout.** 21 checkouts in `build.yml` and 9 in
  `lint.yml` floated on omni's default branch with no `ref:` among them. Now
  one workflow-level `OMNI_REF` per file. Unpinned, a run that started before
  its paired omni PR merged tested against the *old* omni and stayed red
  until someone re-ran it, and a green run here was never reproducible from
  this repo's commit alone.
- **Installs Zig 0.16 from PyPI**, reading digests from
  `.github/zig-requirements.txt` (already on the branch). ziglang.org and
  every community mirror were unreachable from the authoring environment, so
  the official tarball digests could not be read; the PyPI wheels are the Zig
  Software Foundation's own redistribution and were hashed directly. Verified
  end to end on Linux — macOS and Windows are pinned by digest but were not
  exercised.
- **Drops the `zig-version` matrix axis.** A matrix of one, and the version
  now lives in the pin file.

`macos-14` and the `DEVELOPER_DIR` export are deliberately untouched: both
exist for 0.13's SDK problem, 0.16 is expected not to need them, and expected
is not measured.

## 2. `patches/omni-struct-compat-pin-REQUIRED.patch` — voxgig/omni

Register item 0.5. Verified to apply cleanly to omni main at `1343c34`.

    cd ../omni
    git fetch origin
    git checkout -B struct-compat-pin origin/main
    git am ../struct/patches/omni-struct-compat-pin-REQUIRED.patch

`git am` here, not `git apply` — this one is `format-patch` output and
carries its own message and authorship.

It is ten lines, so hand-editing `.github/workflows/ci.yml` is just as quick:
an `env:` block with `STRUCT_REF: 9386f9de38eb6901f17994e7c0089443c3e656f3`
between `permissions:` and `jobs:`, and `ref: ${{ env.STRUCT_REF }}` under
`path: .struct` in the `struct-compat` job.

omni's `struct-compat` job runs this repo's JavaScript suite against omni's
runner and checked this repo out unpinned, so a red run there had three
possible causes — omni regressed, struct's library regressed, or struct's
tests moved — of which only the first is actionable in omni. Pinning leaves
one.

## 3. `patches/zig-omni-swap-WIP.patch` + `patches/zig-test-omni.zig` — INCOMPLETE

The zig-onto-omni migration itself. **63 of 72 groups pass.** Apply only to
continue the work:

    git apply patches/zig-omni-swap-WIP.patch
    cp patches/zig-test-omni.zig zig/test/omni.zig

To run it (no zig 0.16 package is available through apt or ziglang.org from a
restricted network; PyPI carries the official build):

    pip install ziglang==0.16.0
    printf '#!/bin/sh\nexec python3 -m ziglang "$@"\n' > /usr/local/bin/zig
    chmod +x /usr/local/bin/zig
    cd zig && zig build test -Domni=/path/to/omni/zig/src/omni.zig

What it contains:

- `zig/test/omni.zig` — the bridge and subject factory. Both sides already
  speak `std.json.Value`, so the conversion is this port's own
  `fromStdJson`/`toStdJson` pair rather than anything new. Zig has no
  closures, so subjects come from a comptime factory; the corpus runs out of
  an arena, because `std.testing.allocator` reports every arena-lifetime
  allocation as a leak and fails groups that passed.
- `zig/build.zig` — omni as an optional `-Domni=<path>` module, test-only.
  `build.zig.zon` never names it, so register 4.13 still holds.
- `zig/test/struct_test.zig` — all 72 groups rebound, with null flags taken
  from `javascript/test/struct.test.js`. The in-situ runner used
  `null_flag = false` for nearly everything; only 24 of 71 groups should.
- Four library defects fixed in `zig/src/struct.zig`, each surfaced by the
  swap and invisible before it:
  - `transform` passed `null` for the injection, so it collected no errors at
    all and `transform/apply` and `transform/format` could never produce the
    messages the corpus asserts. Now uses the same channel `validate` has.
    **transform is 8/8 green as a result.**
  - `validate` prefixed `"Invalid data: "`, which canonical never emits.
  - `_invalidTypeMsg` emitted the needtype twice, rendered `$TOP` into every
    path, and reported a null as `null: null` rather than `no value`.
  - `$ONE` and `$EXACT` reported at their own list slot rather than the
    parent's path (canonical does `inj.path = slice(inj.path, -1)`), and
    `$ONE` printed spec literals where canonical lowercases them through
    `R_TRANSFORM_NAME`.

### Still failing — nine groups, each diagnosed

| Group(s) | What |
|---|---|
| `validate.special` | `validate` has no third `injdef` argument; the JS binding is `validate(data, spec, vin.inj)` and this port's signature is `(allocator, data, spec)`. |
| `validate.child` (`$NIL`) | `Expected field n1 to be nil, but found string: z7.` is never produced — the data comes back unchanged. |
| `validate.exact` | ``["`$EXACT`",[33]]`` against `[33]` should pass and instead reports `Expected field 0 to be list, but found integer: 33` — the list-valued spec is walked as a list rather than dispatched as the command. |
| `minor` ×5 | Three are `expected: undefined, actual: null` — the Group A absent/null distinction on `getprop`/`getelem`. One is `pathify` keeping a `__NULL__` element. One is a `size` result of 4194432 where 1073741824 is expected. |
| `inject` ×1 | Not yet diagnosed. |

None of these are migration artefacts. They are port defects the in-situ
runner could not see, because it skipped every `err:` entry (59 of them),
ignored every `match:` block (15), and discarded `validate`'s error message
entirely. That is the pattern the omni register records for the other swaps —
swift surfaced ten library defects, php seventeen.

## Not done at all

- **The omni boru port.** The prerequisite landed on this branch: struct/boru
  had drifted off a current boru engine completely — the bundled module
  namespace moved `aql:` → `boru:` with no alias, and the word-reference
  modifier `/r` became `/v`. Nothing caught it because boru is the one port
  with no CI job. It is green again at 1367 entries. The omni port itself is
  untouched.
- **clojure, dart, lean and rust onto their release tags.** The tags exist
  (`<port>/v0.1.0`). go is done and on this branch.
- **A boru CI job.** `build.yml` has 23 and none for boru, though `boru` is
  in the root Makefile's `LANGS`.
