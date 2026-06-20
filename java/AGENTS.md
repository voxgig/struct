# AGENTS.md — Java port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the Java port.

> **This is a port, not the canonical.** Behaviour is defined by
> [`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts)
> and pinned by [`../build/test/`](../build/test/). If Java disagrees with
> the corpus, Java is wrong — fix the port, never the corpus.

## Status (read this)

**Complete.** The source defines the **full canonical API** — all 40
functions, the `Injection` state machine, `SKIP`/`DELETE`, mode constants +
`MODENAME`, all 11 transform commands, the validate checkers, and the 4
select operators — `python3 ../tools/check_parity.py` reports it `ok`, and
the shared corpus passes in full (1300/1300; the committed baseline
[`test-baseline.json`](./test-baseline.json) records the per-file counts).

## Layout

```
java/
├── src/Struct.java          # THE implementation: static API on voxgig.struct.Struct
│                            #   + nested Injection and StructUtility classes
├── src/test/Runner.java          # corpus driver (mirrors typescript/test/runner.ts)
├── src/test/StructCorpusTest.java # JUnit entry — runs build/test/*.jsonic, writes scoreboard
├── src/test/{StructMinorTest,StructTests,RegexPathologicalTest}.java  # unit + regex panel
├── pom.xml                  # Maven; source/target 17; JUnit 6.1 + gson (test scope)
├── checkstyle.xml / spotbugs-exclude.xml   # lint config
└── test-baseline.json       # committed per-file corpus pass counts
```

`sourceDirectory` is `src/` (flat — no `src/main/java`); tests in
`src/test/`. The public surface is the `public static` methods (and
`public static final` constants/sentinels) on `Struct`; the parity tool
matches them case/underscore-insensitively against the canonical TS
`export { … }` block.

## Commands

```bash
mvn -DskipTests compile      # build               (make build)
mvn test                     # run the corpus suite (make test)
make lint                    # compile + checkstyle:check + spotbugs:check
```

`make test` / `make lint` (from this dir, or `make test-java` /
`make lint-java` from the repo root) wrap these. Also: `make checkstyle` /
`make spotbugs` (one check each), `make clean`, `make inspect` (tool
versions). The corpus driver writes `target/corpus-scoreboard.json`.

## Conventions specific to this port

- **Casing:** lowercase single-word names (`getprop`, `getpath`, `isnode`,
  `escre`, …), camelCase only for multi-word ones (`getElem`, `getDef`,
  `delProp`, `hasKey`, `strKey`, `joinUrl`, `checkPlacement`,
  `injectorArgs`, `injectChild`, and the `re*` regex layer). Full table in
  [`DOCS.md`](./DOCS.md#casing). `getProp`/`escapeRegex`/`escapeUrl` do not
  exist.
- **`UNDEF` is the absent sentinel.** `Struct.UNDEF` (a singleton `Object`)
  stands in for TS `undefined`, kept distinct from JSON `null`; compare with
  `==`, never `.equals()`. Same for `SKIP` / `DELETE` (unmodifiable marker
  maps; clone short-circuits to preserve their identity).
- **Optional params → overloads** (no default args): `walk` / `getprop` /
  `getElem` / `transform` / `validate` / `inject` / `merge` / `slice` /
  `pathify` / `jsonify` / `stringify`. Options ride in a `Map<String,Object>`
  (`extra`, `modify`, `errs`, `meta`, `handler`).
- **Containers:** `LinkedHashMap<String,Object>` (insertion-ordered, as
  `jsonify` requires) + `ArrayList<Object>`. Both are reference-stable, so
  there is **no `ListRef` wrapper** — don't add one.

## Gotchas

- **`null` is not `UNDEF`.** Group A readers (`getprop`, `getElem`,
  `hasKey`, `isempty`, `isnode`) treat a stored `null` as absent; Group B
  processors preserve it. Re-read [`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)
  before touching any read/merge/clone path.
- **`Map.of(...)` is immutable** — fine to read, but `merge`/`setpath`/`walk`
  write back into nodes; pass `LinkedHashMap`/`ArrayList` (or
  `Struct.clone(...)`) when mutating. Don't reorder map keys to satisfy a
  diff — order is observable via `keysof`/`items`/`jsonify`.
- **Zero runtime deps.** Gson is **test scope only** (corpus loading); the
  library hand-rolls `jsonify`. Never add a runtime third-party dependency.
- **Function-value signatures** (`$APPLY`, `$FORMAT`, callable `alt`) use
  `java.util.function.Function`; covered by port-local unit tests, not the
  JSON corpus — see [`../NOTES.md`](../design/NOTES.md).
- **The corpus test won't red-bar on a shortfall** — `StructCorpusTest`
  records counts to the scoreboard. Diff `target/corpus-scoreboard.json`
  against `test-baseline.json` to catch regressions.
- **Editing here must not diverge.** A behaviour change is a cross-port
  event: canonical TS + corpus first, port here, `mvn test`, then
  `python3 ../tools/check_parity.py`.

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  `../tools/check_parity.py`
