# Struct for Kotlin

> Kotlin/JVM port of the canonical TypeScript implementation.
>
> **Status: complete.** Carries the **full** TS-canonical public API and
> passes the shared corpus in full (1315/1315). All 48 functions, 15 type
> bit-flags, 3 mode constants (`M_KEYPRE`/`M_KEYPOST`/`M_VAL`),
> `SKIP`/`DELETE` sentinels, and the `Injection` state machine.
> `inject()`/`transform()`/`validate()`/`select()` all dispatch through
> the canonical injector machinery: 10 transform commands
> (`$DELETE`/`$COPY`/`$KEY`/`$ANNO`/`$MERGE`/`$EACH`/`$PACK`/`$REF`/
> `$FORMAT`/`$APPLY`), 6 validate checkers (`$STRING`/`$TYPE`/`$ANY`/
> `$CHILD`/`$ONE`/`$EXACT`), and 4 select operators (`$AND`/`$OR`/
> `$NOT`/`$CMP`). `python3 ../tools/check_parity.py` reports it `ok`.
>
> Passes the shared corpus suite (1259/1259 assertions across 8
> files, run as 60 dynamic corpus subtests). Run locally with
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
`Struct.UNDEF` marker stands for "absent" (see [Notes](#notes)). All 48
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

<!-- example: minor/isnode#map -->
```kotlin
Struct.isnode(linkedMapOf("a" to 1))   // true
```
<!-- => true -->

<!-- example: minor/ismap#map -->
```kotlin
Struct.ismap(linkedMapOf("a" to 1))   // true
```

<!-- => true -->

<!-- example: minor/islist#list -->
```kotlin
Struct.islist(listOf(1, 2))   // true
```

<!-- => true -->

<!-- example: minor/iskey#str -->
```kotlin
Struct.iskey("name")   // true
```

<!-- => true -->

<!-- example: minor/isempty#empty -->
```kotlin
Struct.isempty(listOf<Any?>())   // true
```

<!-- => true -->

### Type inspection

```kotlin
fun typify(value: Any?): Int
fun typename(typeValue: Any?): String
```

`typify` returns a bit-field combining a "kind" flag (`T_SCALAR` or
`T_NODE`) with a specific type flag. `typename` looks up a
human-friendly name.

<!-- example: minor/typify#int -->
```kotlin
Struct.typify(1)   // T_SCALAR or T_NUMBER or T_INTEGER  (201326720)
```

<!-- => 201326720 -->

<!-- example: minor/typename#map -->
```kotlin
Struct.typename(8192)   // "map"  (8192 == T_MAP)
```

<!-- => "map" -->

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

<!-- example: minor/getprop#hit -->
```kotlin
Struct.getprop(linkedMapOf("x" to 1), "x")   // 1
```
<!-- => 1 -->

<!-- example: minor/setprop#set -->
```kotlin
Struct.setprop(linkedMapOf("a" to 1), "b", 2)   // {a=1, b=2}
```

<!-- => {"a": 1, "b": 2} -->

<!-- example: minor/delprop#del -->
```kotlin
Struct.delprop(linkedMapOf("a" to 1, "b" to 2), "a")   // {b=2}
```

<!-- => {"b": 2} -->

<!-- example: minor/getelem#neg -->
```kotlin
Struct.getelem(listOf(10, 20, 30), -1)   // 30
```

<!-- => 30 -->

<!-- example: minor/haskey#hit -->
```kotlin
Struct.haskey(linkedMapOf("a" to 1), "a")   // true
```

<!-- => true -->

<!-- example: minor/keysof#sorted -->
```kotlin
Struct.keysof(linkedMapOf("b" to 4, "a" to 5))   // ["a", "b"]  (sorted)
```
<!-- => ["a", "b"] -->

<!-- example: minor/items#map -->
```kotlin
Struct.items(linkedMapOf("a" to 1, "b" to 2))   // [[a, 1], [b, 2]]
```

<!-- => [["a", 1], ["b", 2]] -->

<!-- example: minor/strkey#num -->
```kotlin
Struct.strkey(2.2)   // "2"
```

<!-- => "2" -->

### Path operations

```kotlin
fun getpath(store: Any?, path: Any?): Any?
fun getpath(store: Any?, path: Any?, inj: Injection?): Any?
fun setpath(store: Any?, path: Any?, value: Any?): Any?
fun pathify(value: Any?): String
fun pathify(value: Any?, from: Any?): String
fun pathify(value: Any?, startIn: Any?, endIn: Any?): String
```

<!-- example: getpath/basic#deep -->
```kotlin
Struct.getpath(linkedMapOf("a" to linkedMapOf("b" to linkedMapOf("c" to 42))), "a.b.c")   // 42
```
<!-- => 42 -->

<!-- example: minor/setpath#nested -->
```kotlin
Struct.setpath(linkedMapOf("a" to 1, "b" to 2), "b", 22)   // {a=1, b=22}
```

<!-- => {"a": 1, "b": 22} -->

<!-- example: minor/pathify#parts -->
```kotlin
Struct.pathify(listOf("a", "b", "c"))   // "a.b.c"
```

<!-- => "a.b.c" -->

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

Last input wins; maps deep-merge; lists merge by index:

<!-- example: merge#basic -->
```kotlin
Struct.merge(listOf(
    linkedMapOf("a" to 1, "b" to 2, "k" to listOf(10, 20), "x" to linkedMapOf("y" to 5, "z" to 6)),
    linkedMapOf("b" to 3, "d" to 4, "e" to 8, "k" to listOf(11), "x" to linkedMapOf("y" to 7)),
))
// {a=1, b=3, d=4, e=8, k=[11, 20], x={y=7, z=6}}
```

<!-- => {"a": 1, "b": 3, "d": 4, "e": 8, "k": [11, 20], "x": {"y": 7, "z": 6}} -->

<!-- example: minor/clone#deep -->
```kotlin
Struct.clone(linkedMapOf("a" to linkedMapOf("b" to listOf(1, 2))))   // {a={b=[1, 2]}}  (a deep copy)
```

<!-- => {"a": {"b": [1, 2]}} -->

<!-- example: minor/flatten#nested -->
```kotlin
Struct.flatten(listOf(1, listOf(2, listOf(3))))   // [1, 2, [3]]  (one level by default)
```

<!-- => [1, 2, [3]] -->

<!-- example: minor/size#three -->
```kotlin
Struct.size(listOf(1, 2, 3))   // 3
```
<!-- => 3 -->

`slice` keeps the first *N*; a negative `start` drops the last *|start|*
items, and `end` is exclusive (pass `null` for an open end):

<!-- example: minor/slice#mid -->
```kotlin
Struct.slice(listOf(1, 2, 3, 4, 5), 1, 4)   // [2, 3, 4]
```
<!-- => [2, 3, 4] -->

<!-- example: minor/slice#strhead -->
```kotlin
Struct.slice("abcdef", -3, null)   // "abc"  (drops the last 3)
```
<!-- => "abc" -->

<!-- example: minor/pad#right -->
```kotlin
Struct.pad("a", 3, null)   // "a  "
```
<!-- => "a  " -->

`filter` passes each `[key, value]` pair to the check and returns the
matching **values** (not the pairs):

<!-- example: minor/filter#gt3 -->
```kotlin
Struct.filter(listOf(1, 2, 3, 4, 5)) { (it[1] as Int) > 3 }   // [4, 5]
```
<!-- => [4, 5] -->

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

Backtick refs in strings are replaced by store values:

<!-- example: inject#basic -->
```kotlin
Struct.inject(linkedMapOf("x" to "`a`", "y" to 2), linkedMapOf("a" to 1))   // {x=1, y=2}
```

<!-- => {"x": 1, "y": 2} -->

A transform command like `$EACH` appears in **value** position — as the
first element of a list `['`$EACH`', path, subspec]` — mapping the
sub-spec over every entry at `path` (in Kotlin source the `$` is escaped
as `\$` because it starts a string template):

<!-- example: transform/each#basic -->
```kotlin
Struct.transform(
    linkedMapOf("v" to 1, "a" to listOf(linkedMapOf("q" to 13), linkedMapOf("q" to 23))),
    linkedMapOf("x" to linkedMapOf("y" to listOf("`\$EACH`", "a",
        linkedMapOf("q" to "`\$COPY`", "r" to "`.q`", "p" to "`...v`")))),
)
// { x: { y: [ { q: 13, r: 13, p: 1 }, { q: 23, r: 23, p: 1 } ] } }
```
<!-- => {"x": {"y": [{"q": 13, "r": 13, "p": 1}, {"q": 23, "r": 23, "p": 1}]}} -->

Putting a command in **key** position (or, for `$APPLY`, directly under a
map) is an error — commands must be list values:

<!-- example: transform/apply#badkey -->
```kotlin
Struct.transform(linkedMapOf<String, Any?>(), linkedMapOf("x" to "`\$APPLY`"))
// throws: $APPLY: invalid placement in parent map, expected: list.
```
<!-- throws: invalid placement in parent map -->

Validate against a shape (throws on mismatch):

<!-- example: validate#shape -->
```kotlin
Struct.validate(
    linkedMapOf("name" to "Ada", "age" to 36),
    linkedMapOf("name" to "`\$STRING`", "age" to "`\$INTEGER`"),
)
// {name=Ada, age=36}  (throws on mismatch)
```

<!-- => {"name": "Ada", "age": 36} -->

Find children matching a query:

<!-- example: select#query -->
```kotlin
Struct.select(
    linkedMapOf("a" to linkedMapOf("name" to "Alice", "age" to 30),
                "b" to linkedMapOf("name" to "Bob", "age" to 25)),
    linkedMapOf("age" to 30),
)
// [{name=Alice, age=30, $KEY=a}]
```

<!-- => [{"name": "Alice", "age": 30, "$KEY": "a"}] -->

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

<!-- example: minor/escre#dots -->
```kotlin
Struct.escre("a.b+c")   // "a\.b\+c"
```

<!-- => "a\\.b\\+c" -->

<!-- example: minor/escurl#space -->
```kotlin
Struct.escurl("hello world?")   // "hello%20world%3F"
```

<!-- => "hello%20world%3F" -->

<!-- example: minor/join#sep -->
```kotlin
Struct.join(listOf("a", "b", "c"), "/", false)   // "a/b/c"
```

<!-- => "a/b/c" -->

`jsonify` pretty-prints by default (indent 2); pass `mapOf("indent" to 0)`
for the compact form:

<!-- example: minor/jsonify#map -->
```kotlin
Struct.jsonify(linkedMapOf("a" to 1))
// {
//   "a": 1
// }
```
<!-- => "{\n  \"a\": 1\n}" -->

<!-- example: minor/jsonify#compact -->
```kotlin
Struct.jsonify(linkedMapOf("a" to 1, "b" to 2), mapOf("indent" to 0))   // {"a":1,"b":2}
```
<!-- => "{\"a\":1,\"b\":2}" -->

`stringify` is the compact, quote-light form — keys are sorted and object
braces are kept; the second argument caps the length (the `...` counts):

<!-- example: minor/stringify#max -->
```kotlin
Struct.stringify("verylongstring", 5)   // "ve..."
```
<!-- => "ve..." -->

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

Inside backticks in a `transform` spec, the 10 canonical commands are
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

### Status

The Kotlin port is **Complete**: it implements the entire canonical public
surface, `check_parity.py` reports it `ok`, and it passes the shared corpus
in full (1315/1315). Treat behavioural authority as resting with the
canonical TypeScript and the shared corpus.

### `null` conventions

The data model is `Any?`. Kotlin `null` is the JSON null scalar; a
distinct sentinel `Struct.UNDEF` (a private `Any()` identity) represents
"absent". This is the [Group A/B rule](../DOCS.md#null-versus-absent-group-ab):
Group A readers (`getprop`, `getelem`, `haskey`, `isempty`, `isnode`)
treat a stored `null` as no value; Group B processors (`clone`, `merge`,
`walk`, `transform`, …) preserve it literally. REPORT.md lists Kotlin as
"already Group A"; the shared corpus passes 1259/1259 assertions here.

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
