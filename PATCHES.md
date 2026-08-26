# One patch to apply locally

boru is the only port with **no CI job at all** — which is how it once spent
two days broken on an engine rename without anyone noticing
(`boru/AGENTS.md` records that). Now that the port runs on voxgig/omni, it
also needs `OMNI_REF` moved to the omni commit that carries omni's boru port:
without it there is no runner for `boru/test/omni.boru` to import.

Both changes are in `.github/workflows/build.yml`, which the authoring
session's credentials are refused on:

    ! [remote rejected] refusing to allow an OAuth App to create or update
      workflow `.github/workflows/build.yml` without `workflow` scope

So the fix is in [`patches/`](./patches) rather than committed.

**Delete this file and `patches/` once it is applied.** Until it is,
`boru/AGENTS.md`'s line about `test-boru` describes a job that is not there
yet.

## `patches/boru-ci-REQUIRED.patch`

    git am patches/boru-ci-REQUIRED.patch

(or `git apply` it and commit yourself — the message is in the patch header.)

Two changes:

- **Adds `test-boru`.** Builds the boru CLI from a pinned `boru-lang/boru`
  commit, checks out voxgig/omni at `OMNI_REF`, then runs `make lint` and
  `make test`. Lint first, because it needs neither omni nor the corpus: a
  static-checker regression is then reported in seconds rather than after a
  corpus that takes minutes on an interpreter. One runner, no matrix, and
  `timeout-minutes: 45` to match.

- **Moves `OMNI_REF` to `1ae6606`**, the tip of voxgig/omni's
  `claude/struct-omni-tests-ylr39r` — omni's boru port plus the two runner
  fixes struct's corpus found. **Merge [voxgig/omni#49](https://github.com/voxgig/omni/pull/49)
  first**; the commit is reachable either way, but pinning to an unmerged
  branch tip is not what the pin is for.

### Why the engine is pinned to a commit

boru has no release channel of any kind: no tags, no published binaries, and
no `go install` — `cmd/go` is a module of its own whose `go.mod` carries
`replace` directives into sibling modules, which `go install` refuses
outright (*"the go.mod file for the module providing named packages contains
one or more replace directives"*). A commit is the only reproducible version
there is, and pinning it is the same argument `OMNI_REF` already makes:
unpinned, a green run is not reproducible from this repo's commit alone.

`8181f78fae7cd335ae3a3513507c7474b5f03663` is the engine every number below
was measured on. Its full hash came from the Go module proxy's own record of
the commit (`.info`, `Origin.Hash`), not from expanding a short one.

### Verified locally, on that engine

- `cd boru && make test` → **PASS 75  FAIL 0** (71 corpus groups plus the
  four single in/out nodes every port hand-writes).
- `cd boru && make lint` → **0 errors**, 49 advisory warnings, `lint ok`.
  Runs with no omni present, which is the register 4.13 claim in practice.
- A deliberate off-by-one in `vg-size` turns the suite red with the entry id
  and both values (`minor/size#three: expected 3, actual 4`) and exits
  non-zero — a green suite that cannot go red proves nothing.
- `python3 tools/omni_isolation.py` → **all clean**;
  `python3 tools/check_parity.py` → **ok boru**.

The job's own steps are not verified — they cannot be, from here. What is
verified is everything they run.
