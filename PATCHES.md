# Patches to apply locally

Changes that could not be pushed from the session that wrote them, plus one
that is genuinely unfinished. Everything referenced here lives in
[`patches/`](./patches).

Both entries exist for the same reason: the authoring session's credentials
are refused on `.github/workflows/`, so anything touching a workflow file has
to be applied by someone whose git has `workflow` scope.

    ! [remote rejected] refusing to allow an OAuth App to create or update
      workflow `.github/workflows/build.yml` without `workflow` scope

**Delete this file and `patches/` once both are done.**

## 1. `patches/omni-ref-bump-REQUIRED.patch` — ready to apply

    git apply patches/omni-ref-bump-REQUIRED.patch
    git commit -am "ci: take omni 064af05, five commits on from the pin"

Two lines, one in `build.yml` and one in `lint.yml`:

    -  OMNI_REF: 95c59eb1a0e6270a82aed6a056ea93e28f67f909
    +  OMNI_REF: 064af05a693adfda4400cbdfd85d24d894172da5

The pin was set when omni's tip was `95c59eb`. omni has since merged #45, #46
and #47 — `deepequal(NaN, NaN)` fixed in six ports and then pinned
across all 23, where the shared corpus cannot reach it — plus its own
`struct-compat` checkout pin. Every port still on the checkout route is
therefore testing against a stale omni.

Bumping this one line is the mechanism working as intended: the bump is the
commit CI re-tests every port against, deliberately rather than by drift.

Verified before proposing: `064af05a693adfda4400cbdfd85d24d894172da5` is a
real commit and is omni's `origin/main` tip, and seven ports on the checkout
route — javascript, python, c, cpp, perl, ruby, rust — all pass against it.

## 2. `patches/zig-omni-swap-WIP.patch` + `patches/zig-test-omni.zig` — unfinished

The zig-onto-omni migration. **63 of 72 groups pass.** Apply only to continue
the work, not to land it:

    git apply patches/zig-omni-swap-WIP.patch
    cp patches/zig-test-omni.zig zig/test/omni.zig

To run it — the zig port needs 0.16, and PyPI carries the official build
where a restricted network may not reach ziglang.org:

    pip install ziglang==0.16.0
    printf '#!/bin/sh\nexec python3 -m ziglang "$@"\n' > /usr/local/bin/zig
    chmod +x /usr/local/bin/zig
    cd zig && zig build test -Domni=/path/to/omni/zig/src/omni.zig

### What it contains

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

## Not started

Nothing below has a patch; these are the remaining items of the omni
migration.

- **The omni boru port.** Its prerequisite is merged: struct/boru had drifted
  off a current boru engine entirely — the bundled module namespace moved
  `aql:` → `boru:` with no alias, and the word-reference modifier `/r` became
  `/v`. Nothing caught it because boru is the one port with no CI job. It is
  green again at 1367 entries. The omni port itself is untouched, and it is
  what blocks struct/boru from migrating at all.
- **clojure, dart, lean and rust onto their release tags.** The tags exist
  (`<port>/v0.1.0`); go is done and is the worked example — `testutil/go.mod`
  requires `github.com/voxgig/omni/go v0.1.0` with a checksum-pinned
  `go.sum`, and no checkout is involved.
- **A boru CI job.** `build.yml` has 23 and none for boru, though `boru` is in
  the root Makefile's `LANGS`. That gap is why the engine drift above went
  unnoticed for two days.
