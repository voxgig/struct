# AGENTS.md — C port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the C port.

> **This is a port, not the source of truth.** Behaviour is defined by the
> canonical TypeScript and pinned by [`../build/test/`](../build/test/). A
> divergence is a C bug to fix here, never a reason to edit the corpus.

## Layout

```
c/
├── src/voxgig_struct.h   # umbrella public header (pulls in value/value_io/regex)
├── src/value.h / value.c # vs_value tagged union; refcounted vs_list / vs_map
│                         #   (insertion-ordered, hash-indexed); sentinels; T_ flags
├── src/value_io.h/.c     # in-tree JSON parse/print (vs_parse_json / vs_to_json)
├── src/utility.c         # minor utils + walk / merge / getpath / setpath / jsonify
├── src/inject.c          # vs_injection state machine, _injectstr, _injecthandler
├── src/transform.c       # transform / validate / select + all commands/checkers/ops
├── src/regex.h / regex.c # in-tree RE2-subset Thompson NFA (vs_regex_*)
├── src/re_util.c         # uniform vs_re_* wrappers over the engine
├── tests/struct_corpus_test.c  # corpus driver (loads ../build/test/test.json)
├── tests/smoke.c         # 13-check API smoke test
├── tests/regex_test.c    # regex unit checks
├── tests/regex_pathological.c  # pathological-input panel
└── Makefile
```

The public surface is the set of `vs_`-prefixed declarations in
`voxgig_struct.h` (plus the `vs_new_*` constructors in `value.h`).
`../tools/check_parity.py` checks this port by stripping the `vs_` prefix
and the `_v` / `_va` suffixes, then matching against the canonical
`export { … }` block.

## Commands

```bash
make test         # compile every src/*.c + the corpus driver, then run it
make smoke        # the small API smoke test
make corpus       # just the corpus driver (test is an alias of this)
make sanitize     # corpus driver under ASan + UBSan
make check_leak   # corpus driver under valgrind
make lint         # clang-format --dry-run --Werror  +  clang-tidy
make format       # apply clang-format in place
make clean        # remove *.out + corpus-scoreboard.json
```

No package step and no third-party deps: the build is `$(CC) src/*.c
tests/<driver>.c -lm`. `make test-c` from the repo root wraps `make test`.

## Conventions specific to this port

- **Casing:** every public function is `vs_`-prefixed lowercase
  (`vs_getpath`, `vs_setprop`, …). The regex engine is `vs_regex_*`; the
  uniform wrappers are `vs_re_*` (canonical `re_*`).
- **`NULL` = omitted optional argument.** TS optional params become trailing
  `NULL`s (e.g. `vs_getpath(store, path, NULL)`).
- **`_v` / `_va` suffixes** disambiguate from C identifiers or mark variadic
  builders: `vs_items_v`, `vs_join_v`, `vs_jm_va`, `vs_jt_va`. Parity
  tooling strips them; keep them.
- **Ownership is explicit, refcounted, and uniform.** Public `vs_*`
  functions borrow their `vs_value*` inputs and return one owned reference;
  the low-level container ops are the exception (`vs_map_set` / `vs_list_push`
  *take* ownership, `vs_map_get` / `vs_list_get` return *borrowed*). Honour
  the per-declaration `/* borrowed */` / `/* takes ownership */` comments.

## Gotchas

- **Memory ownership is the #1 source of bugs.** Every `vs_value*` you
  receive from a `vs_*` function must be `vs_release`d; every `char*`
  (`vs_jsonify`, `vs_stringify`, `vs_pathify`, the `vs_re_*` results) must be
  `free`d; `vs_strvec` / `vs_strvec_vec` / `vs_regex*` have their own
  `_free`. Run `make sanitize` and `make check_leak` after any change that
  touches allocation. Known top-level leaks in `vs_select` / `vs_validate`
  are documented in [`README.md`](./README.md#known-issues) — no
  use-after-free / double-free.
- **`null` is not `undefined`.** `VS_VAL_NULL` and `VS_VAL_UNDEF` are
  distinct kinds. Group A readers treat stored `null` as absent; Group B
  processors preserve it (raw reads go through `vs_lookup`). Re-read
  [`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md) before touching any read/merge/clone
  path.
- **Don't reorder map keys.** `vs_map` is insertion-ordered on purpose (the
  inject machinery partitions keys by `$`-suffix); order is observable via
  `vs_keysof` / `vs_items_v` / `vs_jsonify`.
- **Regex is the in-tree NFA**, not a system library — no catastrophic
  backtracking, captures cap at `VS_REGEX_MAX_GROUPS` (16), and zero-width
  `vs_re_replace` is ECMA-style (`"XXbXcX"`). `$LIKE` dispatches through
  `vs_re_test`. Don't "fix" the cross-engine differences in
  [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md).
- **A behaviour change is a cross-port event.** Change the canonical TS and
  the corpus first; then port here, `make test` + `make lint` green, and
  re-run `python3 ../tools/check_parity.py` and the other ports.

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  [`../tools/check_parity.py`](../tools/check_parity.py)
