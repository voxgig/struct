# AGENTS.md — Zig port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the Zig port.

> **This is a port, not the canonical.** Behaviour is defined by
> [`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts)
> and pinned by [`../build/test/`](../build/test/). If this port disagrees
> with the corpus, the port is wrong — fix the port, never the corpus.

## Layout

```
zig/
├── src/struct.zig    # the port: JsonValue, all public functions, constants
├── src/regex.zig     # in-tree RE2-subset Thompson NFA engine (no third-party dep)
├── test/runner.zig   # loads ../build/test/*.jsonic and asserts equality
├── test/struct_test.zig        # the 60 corpus `test` blocks (the suite)
├── test/regex_pathological.zig # regex edge-case panel
├── test/walk_bench.zig         # optional walk benchmark (zig build bench, WALK_BENCH=1)
├── build.zig         # module "voxgig-struct", test + bench steps
├── build.zig.zon     # .dependencies = .{}  (empty — zero third-party deps)
└── Makefile
```

The parity tool [`../tools/check_parity.py`](../tools/check_parity.py)
scans only `zig/src/struct.zig` for the public names.

## Commands

```bash
zig build test                          # build + run the corpus suite
make test                               # same, tolerating the teardown SIGSEGV
zig build                               # compile the library
zig fmt --check src test build.zig      # formatting check
make lint                               # = fmt-check; the compiler is the analyser
make inspect                            # print Zig + project version
make clean                              # rm -rf .zig-cache zig-out
```

There is no separate community linter for Zig: `zig build` (the compiler)
is the static analyser, and `zig fmt --check` is the style gate. `make
lint` runs only the format check.

## Conventions specific to this port

- **Allocator-first.** Every function that can allocate takes `Allocator`
  as its **first** parameter and returns `!T`; argument order *after* the
  allocator is Zig-side too (`getpath(allocator, path, store)`, not
  `(store, path)`). This is the defining quirk of the port — keep it.
- **Casing:** lowercase canonical names (`getpath`, `setpath`, …); parity
  is checked case/underscore-insensitively.
- **Custom `JsonValue`, not `std.json.Value`.** Containers are
  heap-allocated `*MapRef` / `*ListRef` so they are **reference-stable**
  (mutations visible to every holder), as `merge`/`walk`/`inject` require.
  Convert at the boundary with `fromStdJson` / `toStdJson` only.
- **Insertion-ordered maps.** `MapRef` wraps `std.StringArrayHashMap`; key
  order is observable through `keysof`/`items`/`jsonify`. Never swap in an
  unordered map — the `minor.jsonify` corpus pins key order.
- **`validate` returns `struct { out, err }`**, it does not throw (the
  canonical TS throws). Check `err`.

## Gotchas

- **Teardown SIGSEGV is expected.** The test process can raise signal 11
  during cleanup *after* all tests pass, due to `*MapRef`/`*ListRef`
  cross-references in arena teardown. Use `make test`, which treats
  `N/N tests passed` (N == total) as success. Don't "fix" a passing run by
  chasing this crash. (`zig build test` shows the raw output.)
- **Regex parity gap is intentional.** `re_find` / `re_find_all` /
  `re_replace` are listed in `KNOWN_GAPS["zig"]` in
  `../tools/check_parity.py` — accepted, documented divergence, not a bug
  to silence. `re_compile` / `re_test` / `re_escape` are the wired surface.
  Do not edit the corpus or the gap list to "pass" without actually wiring
  and verifying the missing three.
- **Editing here is port-local.** A behaviour change is a cross-port event
  that must start in the canonical TS + corpus. After matching it here, run
  `zig build test` and `python3 ../tools/check_parity.py`; if multiple
  ports fail the same way, suspect the corpus/canonical, not this port.
- **`null` is "absent" here.** Zig has no JSON `undefined`; the port uses
  the `.null` case and the Group A/B rule (Group A readers treat stored
  `.null` as absent; Group B preserve it). Re-read
  [`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md) before touching any read/merge/clone
  path.
- **Tested on Zig 0.13.0.** The build assumes that toolchain; newer Zig has
  moved `std.ArrayList`/build APIs, so confirm the version (`make inspect`)
  before assuming a failure is a port bug.

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  [`../tools/check_parity.py`](../tools/check_parity.py)
