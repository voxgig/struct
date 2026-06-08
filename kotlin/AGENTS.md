# AGENTS.md — Kotlin port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter
most (canonical-first, corpus-is-contract, parity, zero-deps). This file
covers only what is specific to the Kotlin port.

> **This is a port, not the canonical.** Behaviour is defined by the
> TypeScript in [`../typescript/`](../typescript/) and pinned by the
> shared corpus in [`../build/test/`](../build/test/). If this port
> disagrees with the corpus, the port is wrong — fix `Struct.kt`, never
> the corpus.

## Status

Classified **Partial** in [`../README.md`](../README.md) and
[`../REPORT.md`](../REPORT.md) (same bracket as Java). In practice the
full canonical surface is present (40 functions, 15 type flags, 3 mode
constants, the sentinels, the `Injection` machine) and
`../tools/check_parity.py` reports it `ok`. REPORT.md records it as
**already Group A**, passing 135/135.

## Layout

```
kotlin/
├── src/main/kotlin/voxgig/struct/Struct.kt   # THE implementation (object Struct)
├── src/test/kotlin/voxgig/struct/            # corpus-driven tests + regex panel
├── build.gradle.kts                          # Kotlin DSL build (plugins, deps)
├── settings.gradle.kts                       # rootProject.name = "struct-kt"
├── detekt.yml                                # detekt config
├── .editorconfig                             # ktlint reads style from here
└── Makefile                                  # thin wrapper over ./gradlew
```

The public API is everything declared on `object Struct` in `Struct.kt`.
`tools/check_parity.py` matches it against the canonical TS export block
case/underscore-insensitively.

## Commands

```bash
./gradlew build              # compile src + test     (make build = compileKotlin)
./gradlew test               # corpus + unit tests     (make test)
./gradlew detekt ktlintCheck # static analysis + style (make lint)
./gradlew clean              # make clean
make reset                   # clean + rm -rf .gradle build
```

`make build/test/lint/clean/reset` from this dir wrap the same Gradle
calls. **The build needs network on first use** — Gradle resolves the
Kotlin 2.2, detekt 1.23, and ktlint 12.1 plugins from Maven Central. If
you cannot build in this environment, say so; do not claim a change
passes that you could not run.

## Conventions specific to this port

- **Casing:** canonical core names are kept **lowercase**, matching the
  canonical TS exactly (`getpath`, `getprop`, `isnode`, `keysof`). Only
  the regex layer (`reCompile`, `reTest`, …) and three injection helpers
  (`checkPlacement`, `injectorArgs`, `injectChild`) use camelCase. Parity
  is case-insensitive, so don't "fix" the casing.
- **Data model:** JSON-shaped `Any?`. Maps are `Map<*, *>` (build with
  `linkedMapOf` for insertion order), lists are `List<*>` (build with
  `mutableListOf`). Never swap in an unordered map — order is observable
  through `keysof`/`items`/`jsonify`.
- **Sentinels:** `Struct.UNDEF` = absent, `Struct.SKIP` = omit key,
  `Struct.DELETE` = remove key. Compare with `===` (identity), not `==`.
- **Zero runtime deps:** the library uses only the JVM stdlib plus the
  in-tree JSON emitter. Gson is `testImplementation` only — never move it
  to `implementation`.
- **`null` vs absent (Group A/B):** the single most common port bug.
  Group A readers treat a stored `null` as absent; Group B processors
  preserve it. Re-read [`../UNDEF_SPEC.md`](../UNDEF_SPEC.md) before
  touching any read/merge/clone path.

## Gotchas

- **Editing here is *not* a canonical change.** A behaviour fix starts in
  the TS + corpus, then comes here. If only Kotlin fails a corpus case,
  it's a port bug — match the canonical TS for that function.
- **Escape `$` in source strings.** Backtick commands like `` `$STRING` ``
  are written `"`\$STRING`"` in Kotlin because `$` begins a string
  template. Watch this in tests and `$`-command keys.
- **`var \`val\``** — the `Injection` field is named `val`, a Kotlin
  keyword, so it is backtick-quoted in source. Keep it; it mirrors the
  canonical field name.
- **Regex edges are intentional.** Zero-width `reReplace` → `"XXbXcX"`
  and catastrophic backtracking are the backtracking-engine behaviour
  shared with the ECMA family; do not "fix" them by diverging. See
  [`../REGEX_PATHOLOGICAL.md`](../REGEX_PATHOLOGICAL.md).
- **Function-value signatures** (`$APPLY`, `$FORMAT`, callable `alt`) are
  covered by port-local unit tests, not the JSON corpus — see
  [`../NOTES.md`](../NOTES.md).

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  [`../tools/check_parity.py`](../tools/check_parity.py) · Matrix:
  [`../REPORT.md`](../REPORT.md)
