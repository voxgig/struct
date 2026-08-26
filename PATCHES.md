# One patch to apply locally

`test-zig` cannot compile on CI. The zig port is now driven by voxgig/omni,
but its CI job neither checks omni out nor passes the `-Domni` build option
the test module needs, so the job fails before running anything:

    test/omni.zig:3:22: error: no module named 'omni' available within module 'root'

Reproduced by running exactly what the job runs — `cd zig && zig build test
--summary all`, with no `-Domni`.

The fix is in [`patches/`](./patches) rather than committed because it edits
`.github/workflows/`, which the authoring session's credentials are refused
on:

    ! [remote rejected] refusing to allow an OAuth App to create or update
      workflow `.github/workflows/build.yml` without `workflow` scope

**Delete this file and `patches/` once it is applied.**

## `patches/zig-ci-omni-REQUIRED.patch`

    git apply patches/zig-ci-omni-REQUIRED.patch
    git commit -am "ci(zig): give test-zig the omni checkout its suite now needs"

Two changes to the `test-zig` job:

- **Adds the omni checkout**, pinned to `OMNI_REF` like every other job's.
  This job never had one, because until the swap the zig port carried its own
  runner and needed nothing.
- **Runs `make test` instead of `zig build test`.** The Makefile resolves the
  checkout into `-Domni`, and it already carries the same "N/N tests passed"
  parsing the workflow step duplicated inline, so that block goes with it.

`lint-zig` needs no change: `zig fmt --check` is syntactic and never resolves
the module.

Verified locally against `zig/Makefile` as it stands on main: `make test`
with the checkout present gives **72/72**, and without any omni on the
candidate paths it fails with `struct: voxgig/omni checkout not found - set
OMNI_HOME` rather than a compiler error, which is the message a runner will
get if the checkout step is ever dropped again.

## Everything else from the migration is done

For the record, since this file has shrunk each time:

- **zig is fully migrated and green** — 72/72 through omni, including the
  nine groups that were failing when the swap was handed over as a WIP patch.
- **boru is back on a current engine** — 1367 entries, after the `aql:` →
  `boru:` and `/r` → `/v` sweep.
- **go takes omni from `go/v0.1.0`**, with a checksum-pinned `go.sum` and no
  checkout involved.
- **Both CI pins are in** — `OMNI_REF` here at `064af05`, `STRUCT_REF` in
  omni's `struct-compat` job.

## Still not started

No patch exists for these; they are the remaining items of the omni
migration.

- **The omni boru port.** boru is the one port still on an in-situ runner,
  and it cannot move until omni has a boru port to move onto. Its
  prerequisite is merged: struct/boru had drifted off a current engine
  entirely, and nothing caught it because boru is also the one port with no
  CI job.
- **clojure, dart, lean and rust onto their release tags.** The tags exist
  (`<port>/v0.1.0`); go is the worked example.
- **A boru CI job.** `build.yml` has 23 and none for boru, though `boru` is in
  the root Makefile's `LANGS`. That gap is why the engine drift above went
  unnoticed.
