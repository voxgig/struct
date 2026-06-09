# Struct for Kotlin — Comprehensive Guide

> Kotlin/JVM port of the canonical TypeScript implementation. This is the
> in-depth companion to [`README.md`](./README.md) (the quick-start +
> signature reference) and the language-neutral [`../DOCS.md`](../DOCS.md).
> Behaviour is defined by the canonical TypeScript and pinned by the shared
> corpus in [`../build/test/`](../build/test/); this guide shows the Kotlin
> spelling and the Kotlin-specific details.

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — install and learn the core API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the
  Kotlin-specific semantics and types.
- **[Explanation](#4-explanation--port-specifics)** — the model, the
  port's status, and Kotlin-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Install

Work from a clone of the monorepo and build with Gradle (commands and
caveats are in [Build, test, extend](#build-test-and-extend)). The whole
library is one Kotlin `object`, `voxgig.struct.Struct` (Gradle project,
Kotlin DSL, root project `struct-kt`, group `voxgig.struct`), so there is
no instance to construct — every function is a member you call directly.

```kotlin
import voxgig.struct.Struct
```

### Your first program

Each call below has the same meaning in every port; only the syntax
changes. Read [`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the
full language-neutral walkthrough; the Kotlin-flavoured version:

```kotlin
import voxgig.struct.Struct as S

val config = S.merge(
    listOf(
        linkedMapOf("db" to linkedMapOf("host" to "localhost", "port" to 5432), "debug" to false),
        linkedMapOf("db" to linkedMapOf("host" to "db.internal"), "debug" to true),
    ),
)

S.getpath(config, "db.host")   // "db.internal"
S.getpath(config, "db.port")   // 5432  (survived the deep merge)
```

### Build up the rest of the API

```kotlin
// Reshape by example — the spec mirrors the output you want.
S.transform(
    linkedMapOf("user" to linkedMapOf("first" to "Ada", "last" to "Lovelace"), "age" to 36),
    linkedMapOf("name" to "`user.first`", "surname" to "`user.last`", "years" to "`age`"),
)                                              // { name: "Ada", surname: "Lovelace", years: 36 }

// Validate by example — leaves are type checkers; throws on mismatch.
S.validate(mapOf("age" to 36), linkedMapOf("age" to "`\$INTEGER`"))

// Walk the tree — replace values on ascent.
S.walk(tree, null, S.WalkApply { _, v, _, _ -> if (v == null) "DEFAULT" else v })

// Select children by query — each match carries its $KEY.
S.select(linkedMapOf("a" to linkedMapOf("age" to 30), "b" to linkedMapOf("age" to 25)),
         linkedMapOf("age" to 30))             // [ { age: 30, $KEY: "a" } ]
```

Backtick commands (`` `$STRING` ``) are ordinary strings; in Kotlin
source the `$` is escaped (`"`\$STRING`"`) because `$` starts a string
template.

---

## 2. How-to guides

### Read a deep value, with a fallback
```kotlin
S.getpath(store, "a.b.c")          // Struct.UNDEF if any step is missing
S.getprop(node, "c", fallback)     // fallback if the single key is absent
S.getdef(maybe, fallback)          // fallback only when maybe === Struct.UNDEF
```
Use a **`List` path** when a key contains a dot: `S.getpath(store, listOf("a.b", "c"))`.

### Collect all validation errors instead of throwing
```kotlin
val errs = mutableListOf<Any?>()
S.validate(payload, spec, mapOf("errs" to errs))
if (errs.isNotEmpty()) println(errs)
```
Passing an `errs` `MutableList` switches `validate`/`transform` from
throwing to collecting.

### Write a custom transform function (`$APPLY`)
```kotlin
S.transform(
    linkedMapOf("items" to listOf(1, 2, 3)),
    linkedMapOf("total" to linkedMapOf("`\$APPLY`" to "sum")),
    mapOf("extra" to mapOf<String, Any?>(
        "sum" to { v: Any? -> (v as List<*>).sumOf { (it as Number).toInt() } },
    )),
)
```
Register the function under `extra` and reference it by name. It may
return `Struct.SKIP` / `Struct.UNDEF` to omit/remove the current key.
`extra` keys starting with `$` register injectors; the rest merge into
the transform data. (Callback signatures vary by port — see
[`../NOTES.md`](../design/NOTES.md).)

### Keep a `walk` path past the callback
The `path` list passed to a `WalkApply` is reused, so copy it
(`path.toList()`) if you need to retain it past the call.

### Serialise deterministically
```kotlin
S.jsonify(value)                       // 2-space indent, insertion-ordered keys
S.jsonify(value, mapOf("indent" to 0)) // compact
S.stringify(value, 80)                 // truncated human form, for logs
```

For more task recipes (rename fields, `$COPY`, `$EACH`, `$MERGE`,
`$FORMAT`, `$ONE`, `$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is
identical; only the host literals differ.

---

## 3. Reference

The full Kotlin signatures, grouped by area, are in
[`README.md` → Function reference](./README.md#function-reference). The
canonical public surface is the `export { … }` block in
[`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts);
[`../tools/check_parity.py`](../tools/check_parity.py) checks this port
against it case/underscore-insensitively, and reports it `ok`.

Kotlin-specific points the signatures don't show:

- **`Any?` at the boundaries.** The model is JSON-shaped `Any?`: maps are
  `Map<*, *>` (mutated as `MutableMap<String, Any?>`), lists are `List<*>`
  (mutated as `MutableList<Any?>`), scalars are `String`/`Number`/
  `Boolean`, JSON null is `null`, and `Struct.UNDEF` (an identity object,
  tested with `===`) is "absent" — `getprop`/`getelem`/`getpath` return it
  for a missing key. Numbers are normalised by `floor(d) == d`: integral
  doubles read as integers (`T_INTEGER`), others as `T_DECIMAL`.
- **`getprop` vs `getelem`.** `getprop` works on maps and lists; `getelem`
  is list-specific, supports `-1`-from-the-end indexing, and *invokes* a
  callable `alt` when the element is absent (`getprop`/`getdef` do not).
- **`items` returns `List<List<Any?>>`** — each inner list is `[key, val]`
  with the key as a `String`. `walk` callers pass
  `(value, before?, after?, maxdepth?)` and supply callbacks via the
  `WalkApply` `fun interface`; the `key`/`parent`/`path` params are
  recursion state.
- **Type flags** are `Int` constants and combine bitwise: `typify("hi")`
  is `T_SCALAR or T_STRING`; test with `0 != (T_STRING and t)`.
  `typify(Struct.UNDEF)` is `T_NOVAL`; `typify(null)` is
  `T_SCALAR or T_NULL`.
- **Function values.** `isfunc`/`typify` recognise Kotlin lambdas
  (`Function1`), Java `Function`/`Supplier`, and the `Injector`/`Modify`/
  `WalkApply` interfaces as callable.

---

## 4. Explanation & port specifics

### Status: partial, but full-surface

The root [`README.md`](../README.md) and [`../AGENTS.md`](../AGENTS.md)
classify Kotlin as a **Partial** port (the same bracket as Java), yet it
already carries the entire canonical public surface — all 40 functions,
15 type flags, the three mode constants, the sentinels, and the full
`Injection` machine — and `check_parity.py` reports it `ok`. "Partial"
reflects port maturity, not a missing API. Behavioural authority rests
with the canonical TypeScript and the corpus, never with this port.

### `null` versus absent ("Group A/B")

Kotlin has `null`, and `struct` keeps "null" distinct from "absent" by
using a dedicated `Struct.UNDEF` sentinel for absence — the
[Group A/B rule](../DOCS.md#null-versus-absent-group-ab) in
language-neutral form:

- `Struct.UNDEF` = **absent**. `getprop` on a missing key returns it;
  Group A readers (`getprop`, `getelem`, `haskey`, `isempty`, `isnode`)
  treat a stored `null` as absent too.
- `null` = the JSON null scalar; `typify(null)` is `T_SCALAR or T_NULL`,
  and Group B processors (`clone`, `merge`, `walk`, `transform`,
  `validate`, `select`, …) preserve it literally.

[`../REPORT.md`](../design/REPORT.md) records this port as **already Group A**
(135/135). If your data source returns `null` for "not set", decide which
you mean before handing it to `struct`. The corpus bridges the two with
the `"__NULL__"` / `"__UNDEF__"` / `"__EXISTS__"` markers (see
[`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)).

### Object model: reference-stable, zero-dependency JSON

`walk`, `merge`, `inject`, and `setpath` rely on a mutation through one
handle being visible through all. Kotlin's `ArrayList`/`LinkedHashMap`
provide this directly, so — unlike Go and PHP — no `ListRef` wrapper is
needed. Maps are built with `linkedMapOf` so key order is insertion
order. `jsonify` then uses an in-tree, pure-Kotlin emitter
(`_jsonifyInner`), not Gson, so the library proper has **zero runtime
dependencies** (Gson is `testImplementation` only); keys serialise in
insertion order, matching canonical `JSON.stringify`, and doubles use
`%g`-style formatting.

### Regex

The regex layer wraps `kotlin.text.Regex` (backed by `java.util.regex`,
an RE2 superset) behind the uniform six-function API (`reCompile` /
`reTest` / `reFind` / `reFindAll` / `reReplace` / `reEscape`). Stay
inside the **RE2 subset** — `Regex` *allows* backreferences and
lookaround, but those don't port. Being a backtracking engine, this port
aligns with the ECMA/backtracking family on the two documented sharp
edges: catastrophic backtracking (`^(a+)+$` over 22 a's plus `!` ≈ 24 ms
here) and zero-width `reReplace` returning `"XXbXcX"` (Go's RE2 returns
`"XbXcX"`). See [`README.md` → Regex](./README.md#regex) and
[`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md);
`python3 ../tools/check_corpus_regex.py` keeps the corpus in-subset.

---

## Build, test, and extend

```bash
cd kotlin
./gradlew build              # compile src + test          (make build = compileKotlin)
./gradlew test               # corpus + unit tests         (make test)
./gradlew detekt ktlintCheck # static analysis + style     (make lint)
./gradlew clean              # make clean
```

The build cannot run in a network-isolated environment — Gradle resolves
the Kotlin 2.2, detekt 1.23, and ktlint 12.1 plugins from Maven Central
on first use. JVM target is 17.

Tests live under [`src/test/kotlin/voxgig/struct/`](./src/test/kotlin/voxgig/struct/);
the runner loads the shared corpus from [`../build/test/`](../build/test/),
mirroring the reference runner in
[`../typescript/test/runner.ts`](../typescript/test/runner.ts).

**To change behaviour:** this is a *port*, so behaviour changes start in
the canonical TypeScript, not here. Edit `../typescript/src/StructUtility.ts`,
adjust the corpus case in `../build/test/*.jsonic`, make the canonical
pass, then bring the same logic to `Struct.kt`, run `./gradlew test`, and
re-run `python3 ../tools/check_parity.py`. The full cross-port checklist
is in [`../AGENTS.md`](../AGENTS.md) and this port's
[`AGENTS.md`](./AGENTS.md).
