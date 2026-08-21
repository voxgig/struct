# AGENTS.md — C++ port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the C++ port.

> **This is a port, not the canonical.** Behaviour is defined by the
> TypeScript source and the shared corpus. If this port disagrees with the
> corpus, the port is wrong — fix it here, never edit the corpus.

## Layout

```
cpp/
├── src/value.hpp            # Value (std::variant), OrderedMap, Sentinel, flags, predicates
├── src/value_io.hpp         # hand-written JSON parser/serialiser (no third-party deps)
├── src/voxgig_struct.hpp    # main API: all 40 canonical fns + injectors
├── tests/omni_bridge.hpp    # the bridge to voxgig/omni: both value types, both ways
├── tests/struct_corpus_test.cpp  # the shared corpus, run on the shared runner
├── tests/client_test.cpp    # the client path (DEF.client, client options, contextify)
├── tests/smoke.cpp          # smoke test
├── tests/regex_pathological.cpp  # regex edge-case panel
├── overview/                # scratch examples (not part of the suite)
├── Makefile · .clang-tidy · .clang-format
```

Everything public lives in namespace `voxgig::structlib`. The
implementations are declared near the top of `voxgig_struct.hpp` and
defined below.

## Commands

```bash
make test         # smoke + corpus driver + client test
make build        # the smoke test alone (needs nothing but this port)
make smoke        # smoke test only
make corpus       # corpus driver only
make client       # client test only
make sanitize     # corpus under ASan + UBSan
make check_leak   # corpus under valgrind
make lint         # clang-tidy + clang-format --dry-run --Werror
make inspect      # g++ version + located nlohmann/json header
```

- **The corpus runner is voxgig/omni**, header-only and consumed as a local
  checkout the Makefile finds via `$OMNI_HOME` or beside this repository. It
  is on the include path of the TEST translation units only; `make build`
  compiles the smoke test, which does not include it (register 4.13).
- **`tests/omni_bridge.hpp` converts both value types.** `omni::Json` carries
  one `double`; `Value` separates integers from decimals. Both draw the same
  absent/null/value distinction, so nothing is guessed. `omni::Json` is a
  value type with nothing to share, so the wrapper writes the converted
  argument back through omni's `runsetflags_args` - that is what lets
  `match.args` see an in-place `setpath`.

## Conventions specific to this port

- **Casing:** lowercase canonical names, with five renames that
  `../tools/check_parity.py` knows about: `walk_v`, `merge_v`, `getpath_v`,
  `setpath_v` (the `_v` "value-style" suffix disambiguates each from a
  header-internal helper of the same root name), and `typename_str`
  (`typename` is a reserved C++ keyword). Do not "clean up" these names —
  parity depends on them.
- **Data model:** `Value` is a `std::variant`. `std::monostate` is
  undefined/absent; `std::nullptr_t` is JSON null; they are **distinct**.
  Sentinels `SKIP()` / `DELETE_V()` are pointer-identity singletons.
- **Reference stability:** lists/maps are `shared_ptr<List>` /
  `shared_ptr<Map>` so mutations propagate to all aliases — the property
  `merge`/`walk`/`inject` require. Don't deep-copy on assignment.
- **Ordered maps:** the in-tree `OrderedMap` in `value.hpp` preserves
  insertion order (required by inject's `$`-suffix key partition). Never
  swap in `std::map`/`std::unordered_map`.
- **Zero runtime deps:** JSON I/O is the hand-written parser in
  `value_io.hpp`; `value.hpp` is intentionally self-contained. Keep
  `nlohmann/json` out of `src/`.

## Gotchas

- **`null` is not `undefined`.** Re-read the Group A/B rule
  ([`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)) before touching any
  read/merge/clone path: Group A readers (`getprop`, `getelem`, `haskey`,
  `isempty`, `isnode`) treat stored `null` as absent; Group B
  value-processors preserve it literally.
- **Regex is `std::regex` (`<regex>`, ECMAScript).** Stay inside the RE2
  subset — no backreferences/lookaround. libstdc++'s `<regex>` backtracks
  catastrophically; the documented zero-width-`re_replace` and
  catastrophic-backtracking differences in
  [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md) are expected — do
  not "fix" them by diverging.
- **The README is stale.** It describes an earlier partial state (namespace
  `VoxgigStruct`, an `args_container&&` calling convention, missing
  `getpath`/`setpath`/`inject`/`transform`/`validate`/`select`, JSON via an
  nlohmann bridge, `typename_of`). The source is the truth: complete port,
  `voxgig::structlib`, `const Value&` signatures, hand-written parser,
  `typename_str`. Trust the headers over the README prose.
- **Editing here is local.** A behaviour fix that makes the corpus pass
  stays in this port. A behaviour *change* is a cross-port event: do it in
  TypeScript + corpus first, then propagate (see `../AGENTS.md`).

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  `../tools/check_parity.py` · Matrix: [`../REPORT.md`](../design/REPORT.md)
