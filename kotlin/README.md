# Struct for Kotlin

> Kotlin/JVM port of the canonical TypeScript implementation.
>
> **Status: partial port** (alongside Java) — but it currently carries
> the **full** TS-canonical public API: all 40 functions, 15 type
> bit-flags, 3 mode constants (`M_KEYPRE`/`M_KEYPOST`/`M_VAL`),
> `SKIP`/`DELETE` sentinels, and the `Injection` state machine.
> `inject()`/`transform()`/`validate()`/`select()` all dispatch through
> the canonical injector machinery: 11 transform commands
> (`$DELETE`/`$COPY`/`$KEY`/`$ANNO`/`$MERGE`/`$EACH`/`$PACK`/`$REF`/
> `$FORMAT`/`$APPLY`), 6 validate checkers (`$STRING`/`$TYPE`/`$ANY`/
> `$CHILD`/`$ONE`/`$EXACT`), and 4 select operators (`$AND`/`$OR`/
> `$NOT`/`$CMP`). `python3 ../tools/check_parity.py` reports it `ok`.
>
> Passes the shared corpus suite (135/135). Run locally with
> `./gradlew test` from `kotlin/`.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md),
[`../DOCS.md`](../DOCS.md), and [`../REPORT.md`](../design/REPORT.md). The
Kotlin port guide is [`DOCS.md`](./DOCS.md).


## Install

In the monorepo:

```bash
cd kotlin
./gradlew build        # or `make build` (compiles), `make test` (runs the suite)
```

Gradle (Kotlin DSL) project; group `voxgig.struct`. The implementation
is a single Kotlin `object` (singleton): `voxgig.struct.Struct`. The
library proper has **zero runtime dependencies** — JSON output is a
hand-rolled printer. Gson appears only in `testImplementation` scope
(corpus loading + assertion diffs).

```kotlin
import voxgig.struct.Struct
```


## Quick start

```kotlin
import voxgig.struct.Struct

val store = linkedMapOf(
    "db" to linkedMapOf("host" to "localhost", "port" to 5432),
)

val host = Struct.getpath(store, "db.host")   // "localhost"
val port = Struct.getpath(store, "db.port")   // 5432
```

`Struct` is an `object`, so every function is called on it directly
(`Struct.getpath(...)`); there is no instance to construct. Maps are
`LinkedHashMap` (insertion-ordered) and lists are `MutableList`.


## Naming convention

Canonical public names are kept **lowercase**, matching the canonical
TypeScript exactly (`getpath`, `getprop`, `isnode`, `keysof`). Only the
regex-API extension uses camelCase (`reCompile`, `reTest`, …), as do
the three injection helpers. Parity is checked case-insensitively
([`../tools/check_parity.py`](../tools/check_parity.py)).

| Canonical    | Kotlin        |
|--------------|---------------|
| `getprop`    | `getprop`     |
| `setprop`    | `setprop`     |
| `isnode`     | `isnode`      |
| `keysof`     | `keysof`      |
| `escre`      | `escre`       |
| `escurl`     | `escurl`      |
| `re_compile` | `reCompile`   |


## Function reference

Source: [`src/main/kotlin/voxgig/struct/Struct.kt`](./src/main/kotlin/voxgig/struct/Struct.kt).
Package `voxgig.struct`; everything is a member of `object Struct`. The
data model is JSON-shaped `Any?`: `null` is the JSON null scalar and the
`Struct.UNDEF` marker stands for "absent" (see [Notes](#notes)). All 40
canonical functions are present.

### Predicates

```kotlin
fun isnode(value: Any?): Boolean
fun ismap(value: Any?): Boolean
fun islist(value: Any?): Boolean
fun iskey(key: Any?): Boolean
fun isempty(value: Any?): Boolean
fun isfunc(value: Any?): Boolean
```

### Type inspection

```kotlin
fun typify(value: Any?): Int
fun typename(typeValue: Any?): String
```

### Property access

```kotlin
fun getprop(value: Any?, key: Any?): Any?
fun getprop(value: Any?, key: Any?, alt: Any?): Any?
fun getelem(value: Any?, key: Any?): Any?           // -1 indexes from the end
fun getelem(value: Any?, key: Any?, alt: Any?): Any?
fun getdef(value: Any?, alt: Any?): Any?
fun haskey(value: Any?, key: Any?): Boolean
fun setprop(parent: Any?, key: Any?, value: Any?): Any?
fun delprop(parent: Any?, key: Any?): Any?
fun keysof(value: Any?): List<String>               // sorted; string indices for lists
fun items(value: Any?): List<List<Any?>>
fun strkey(key: Any?): String
```

### Path operations

```kotlin
fun getpath(store: Any?, path: Any?): Any?
fun getpath(store: Any?, path: Any?, inj: Injection?): Any?
fun setpath(store: Any?, path: Any?, value: Any?): Any?
fun pathify(value: Any?): String
fun pathify(value: Any?, from: Any?): String
fun pathify(value: Any?, startIn: Any?, endIn: Any?): String
```

### Tree operations

```kotlin
fun clone(value: Any?): Any?
fun merge(value: Any?): Any?
fun merge(value: Any?, maxdepthIn: Int): Any?
fun flatten(value: Any?): List<Any?>
fun flatten(value: Any?, depth: Int?): List<Any?>
fun filter(value: Any?, check: (List<Any?>) -> Boolean): List<Any?>
fun size(value: Any?): Int
fun slice(value: Any?, startObj: Any?, endObj: Any?): Any?
fun pad(value: Any?, paddingObj: Any?, padcharObj: Any?): String

fun walk(value: Any?, apply: WalkApply): Any?
fun walk(value: Any?, before: WalkApply?, after: WalkApply?): Any?
fun walk(value: Any?, before: WalkApply?, after: WalkApply?, maxdepth: Int): Any?

fun interface WalkApply {
    fun apply(key: String?, value: Any?, parent: Any?, path: List<String>): Any?
}
```

### Composition: inject, transform, validate, select

```kotlin
fun inject(value: Any?, store: Any?): Any?
fun inject(value: Any?, store: Any?, injdef: Injection?): Any?
fun transform(data: Any?, spec: Any?): Any?
fun transform(data: Any?, spec: Any?, options: Map<String, Any?>?): Any?
fun validate(data: Any?, spec: Any?): Any?
fun validate(data: Any?, spec: Any?, options: Map<String, Any?>?): Any?
fun select(children: Any?, query: Any?): MutableList<Any?>
```

`options` carries `extra` (custom `$APPLY` functions and data),
`modify`, `handler`, `meta`, and `errs` (an `errs` `MutableList`
collects errors instead of throwing).

### Strings / URL / JSON

```kotlin
fun stringify(value: Any?): String
fun stringify(value: Any?, maxlen: Int?): String
fun jsonify(value: Any?): String
fun jsonify(value: Any?, flags: Any?): String       // flags map: "indent","offset"
fun escre(s: Any?): String
fun escurl(s: Any?): String
fun join(arr: Any?, sep: Any?, url: Any?): String
fun replace(s: Any?, from: Any?, to: Any?): String
fun pathify(value: Any?): String                     // (also above)
```

### Builders and injection helpers

```kotlin
fun jm(vararg kv: Any?): MutableMap<String, Any?>    // map from key/value pairs
fun jt(vararg v: Any?): MutableList<Any?>            // list from positional args
fun checkPlacement(modes: Int, ijname: String, parentTypes: Int, inj: Injection): Boolean
fun injectorArgs(argTypes: IntArray, args: List<Any?>): Array<Any?>
fun injectChild(child: Any?, store: Any?, inj: Injection): Injection
```

The injector state machine is exposed via the `Injection` class plus the
`Injector` and `Modify` functional interfaces.


## Constants

### Sentinels

```kotlin
Struct.UNDEF     // the "absent" marker (Group A "no value")
Struct.SKIP      // omit the current key from the output
Struct.DELETE    // remove the current key from the parent
```

### Type bit-flags

All 15 are `Int` constants on `Struct`:

```kotlin
Struct.T_ANY        Struct.T_NOVAL     Struct.T_BOOLEAN
Struct.T_DECIMAL    Struct.T_INTEGER   Struct.T_NUMBER
Struct.T_STRING     Struct.T_FUNCTION  Struct.T_SYMBOL
Struct.T_NULL       Struct.T_LIST      Struct.T_MAP
Struct.T_INSTANCE   Struct.T_SCALAR    Struct.T_NODE
```

Flags combine bitwise: `typify("hi")` is `T_SCALAR or T_STRING`; test
with `0 != (Struct.T_STRING and t)`. `typify(Struct.UNDEF)` is
`T_NOVAL`; `typify(null)` is `T_SCALAR or T_NULL`.

### Mode constants

```kotlin
Struct.M_KEYPRE     // about to descend by key
Struct.M_KEYPOST    // returned from descending
Struct.M_VAL        // visiting a leaf value
Struct.MODENAME     // Map<Int,String> of mode -> name
```


## Transform commands

Inside backticks in a `transform` spec, the 11 canonical commands are
implemented as `Injector` values (`transform_DELETE`, `transform_COPY`,
…) and registered in the store by `transform()`:

`$DELETE`, `$COPY`, `$KEY`, `$ANNO`, `$MERGE`, `$EACH`, `$PACK`, `$REF`,
`$FORMAT`, `$APPLY`.

`$FORMAT` ships the named formatters `identity`, `upper`, `lower`,
`string`, `number`, `integer`, `concat` (the `FORMATTER` map).


## Validate checkers

Inside backticks in a `validate` spec (implemented as `validate_STRING`,
`validate_TYPE`, `validate_ANY`, `validate_CHILD`, `validate_ONE`,
`validate_EXACT`):

`$STRING`, `$NUMBER`, `$INTEGER`, `$DECIMAL`, `$BOOLEAN`, `$NULL`,
`$NIL`, `$MAP`, `$LIST`, `$FUNCTION`, `$INSTANCE`, `$ANY`, `$CHILD`,
`$ONE`, `$EXACT`. (`$NUMBER`..`$INSTANCE` all share `validate_TYPE`.)

`select()` adds the operators `$AND`, `$OR`, `$NOT`, and the comparators
`$GT`/`$LT`/`$GTE`/`$LTE`/`$LIKE` (the `select_CMP` injector).


## Notes

### Why partial?

The Kotlin port is classified **Partial** in the parity matrix
([`../REPORT.md`](../design/REPORT.md)) in the same bracket as Java. In
practice it implements the entire canonical public surface and
`check_parity.py` reports it `ok`; the classification reflects port
maturity rather than a missing API. Treat behavioural authority as
resting with the canonical TypeScript and the shared corpus.

### `null` conventions

The data model is `Any?`. Kotlin `null` is the JSON null scalar; a
distinct sentinel `Struct.UNDEF` (a private `Any()` identity) represents
"absent". This is the [Group A/B rule](../DOCS.md#null-versus-absent-group-ab):
Group A readers (`getprop`, `getelem`, `haskey`, `isempty`, `isnode`)
treat a stored `null` as no value; Group B processors (`clone`, `merge`,
`walk`, `transform`, …) preserve it literally. REPORT.md lists Kotlin as
"already Group A" (135/135).

### Object model

Maps default to `LinkedHashMap<String, Any?>` (insertion-ordered, which
the hand-rolled `jsonify` relies on) and lists to `MutableList<Any?>`.
Both are reference-stable, so the canonical "lists are mutable in place"
property holds without a wrapper — unlike Go/PHP, which need a `ListRef`.

### Function values

`isfunc`/`typify` recognise Kotlin lambdas (`Function1`), Java
`Function`/`Supplier`, and the `Injector`/`Modify`/`WalkApply` interfaces
as callable. A callable `alt` to `getelem` is invoked when the element
is absent.


## Regex

Uniform six-function regex API (see [`../REGEX_API.md`](../design/REGEX_API.md)).
The Kotlin port backs onto `kotlin.text.Regex` / `java.util.regex` (a
backtracking engine, RE2 superset).

### API

| Function | Maps to |
|---|---|
| `reCompile(pattern)`               | `Regex(pattern)` |
| `reTest(pattern, input)`           | `Regex(pattern).containsMatchIn(input)` |
| `reFind(pattern, input)`           | first match as `List<String>` (`groupValues`) or `null` |
| `reFindAll(pattern, input)`        | `List<List<String>>` |
| `reReplace(pattern, input, repl)`  | `Regex(pattern).replace(...)` (`$&` is translated to `$0`) |
| `reEscape(s)`                      | escape regex metacharacters (delegates to `escre`) |

### Dialect

Patterns must stay inside the **RE2 subset** documented in
[`../REGEX.md`](../design/REGEX.md). Kotlin/Java regex supports backreferences
and lookaround; using them will not be portable.

### Sharp edges

- **Catastrophic backtracking.** `java.util.regex` is a backtracking
  engine; the discovery panel times P1 (`^(a+)+$` over 22 a's plus `!`)
  at ~24 ms here. Other shapes can be worse. Prefer flat patterns.
- **Zero-width `replace`.** `reReplace("a*", "abc", "X")` returns
  `"XXbXcX"` — the ECMA/backtracking convention shared by all
  PCRE/ECMA/.NET/Java/Onigmo engines. Go (RE2) returns `"XbXcX"`; see
  [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md). Kotlin's edges
  align with the other backtracking-family ports.

See [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md) for the
cross-port pathological-input panel.


## Build and test

The build cannot reach Gradle plugins without network access, so these
are the real targets from the [`Makefile`](./Makefile); run them in an
environment with network for the first resolve:

```bash
cd kotlin
make build       # ./gradlew compileKotlin
make test        # ./gradlew test
make lint        # ./gradlew detekt ktlintCheck
make clean       # ./gradlew clean
make reset       # clean + rm -rf .gradle build
```

Lint is detekt (static analysis) + ktlint (style). Tests live in
[`src/test/kotlin/voxgig/struct/`](./src/test/kotlin/voxgig/struct/) and
load the shared corpus from [`../build/test/`](../build/test/). JVM
target 17.
