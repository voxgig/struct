# Struct for Swift — Comprehensive Guide

> A **port**, not the canonical. Behaviour is defined by the canonical
> TypeScript and pinned by the shared corpus; this port must match it.
> This guide is the in-depth companion to [`README.md`](./README.md) (the
> quick-start + signature reference) and the language-neutral
> [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — install and learn the whole API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the
  Swift-specific types and semantics.
- **[Explanation](#4-explanation--port-specifics)** — the model and the
  Swift-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Install

`VoxgigStruct` is a SwiftPM package (swift-tools 5.9) with **zero runtime
third-party dependencies** — only Foundation. Add it as a local package, or
work from the clone:

```bash
cd swift
make build         # swift build
make test          # swift test --enable-test-discovery
```

The insertion-ordered map type lives in-tree at
[`Sources/VoxgigStruct/OrderedDictionary.swift`](./Sources/VoxgigStruct/OrderedDictionary.swift),
so the library proper pulls in nothing beyond the stdlib.

### Your first program

Everything flows through one in-tree value type, `Value` (an `indirect
enum`). Parse JSON into it, then operate:

```swift
import VoxgigStruct

let config = merge(.list([
  try JSON.parse(#"{"db":{"host":"localhost","port":5432},"debug":false}"#), // defaults
  try JSON.parse(#"{"db":{"host":"db.internal"},"debug":true}"#),            // overrides
]))

getpath(config, .string("db.host"))   // .string("db.internal")
getpath(config, .string("db.port"))   // .int(5432)  (survived the deep merge)
```

`getpath(store, path)` descends a dotted path (store first, then the path):

<!-- example: getpath/basic#deep -->
```swift
getpath(.map([("a", .map([("b", .map([("c", .int(42))]))]))]), .string("a.b.c"))   // .int(42)
```
<!-- => 42 -->

`JSON.parse(_:)` throws on malformed input (the only throwing function in the
API). The parser builds `OrderedDictionary`-backed maps so object key order
survives.

### Build up the rest of the API

Each call has the same meaning in every port; only the syntax changes. Read
[`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the full
language-neutral walkthrough; the Swift-flavoured version:

```swift
// Reshape by example — the spec mirrors the output you want.
transform(
  try JSON.parse(#"{"user":{"first":"Ada","last":"Lovelace"},"age":36}"#),
  try JSON.parse(#"{"name":"`user.first`","surname":"`user.last`","years":"`age`"}"#))
// { name: "Ada", surname: "Lovelace", years: 36 }

// Validate by example — leaves are type checkers.
validate(
  try JSON.parse(#"{"name":"Ada","age":36}"#),
  try JSON.parse(#"{"name":"`$STRING`","age":"`$INTEGER`"}"#))

// Walk the tree — replace values on ascent.
walk(tree, nil) { _, val, _, _ in val.isNull ? .string("DEFAULT") : val }

// Select children by query — each match tagged with its $KEY.
select(
  try JSON.parse(#"{"a":{"age":30},"b":{"age":25}}"#),
  try JSON.parse(#"{"age":30}"#))
// [ { age: 30, $KEY: "a" } ]
```

---

## 2. How-to guides

### Collect validation errors instead of failing silently
`validate` and `transform` do **not** throw in this port — they accumulate
messages on the `Injection.errs` list. Pass an `Injection` to read them:

```swift
let inj = Injection(val: .noval, parent: .noval)
let out = validate(payload, spec, inj)
if !inj.errs.items.isEmpty { /* report inj.errs.items */ }
```

### Write a custom transform function (`$APPLY`)
`$APPLY` lives in **value** position as the first element of a list,
``["`$APPLY`", fn, arg]``. The function value goes in the list *directly* —
there is no name lookup, so the spec can't be a pure JSON string; build it as a
`Value`. The closure has the `Injector` shape
`(Injection, Value, String, Value) -> Value`; its second argument is the
resolved `arg`, and it may return `.sentinel(SKIP)` / `.sentinel(DELETE)` to
omit/remove the key:

```swift
let sum: Injector = { _, resolved, _, _ in
  guard case .list(let l) = resolved else { return .int(0) }
  return .int(l.items.reduce(0) { $0 + ($1.asInt ?? 0) })
}
let inj = Injection(val: .noval, parent: .noval)
let spec: Value = .map([
  ("total", .list([.string("`$APPLY`"), .function(sum), .string("`items`")]))
])
transform(try JSON.parse(#"{"items":[1,2,3]}"#), spec, inj)
// { total: 6 }
```

Putting ``$APPLY`` in **key** position (e.g.
``{"total":{"`$APPLY`":[…]}}``) is the invalid-placement case shown in the
anchored `transform/apply#badkey` example below — the spec passes through
literally and the error lands on `inj.errs`.

### Read with a fallback, distinguish absent from null
A plain hit returns the stored value:

<!-- example: minor/getprop#hit -->
```swift
getprop(.map([("x", .int(1))]), .string("x"))   // .int(1)
```
<!-- => 1 -->

```swift
getprop(node, .string("timeout"), .int(30))   // .int(30) if key is absent OR stored null (Group A)
getdef(maybeNoval, .string("fallback"))        // fallback only when value is .noval
getelem(list, .int(-1))                         // last element; -1 counts from the end
```

### Set a deep value, creating parents
```swift
setpath(store, .string("service.db.host"), .string("db.internal"))
setpath(store, .list([.string("list"), .int(2)]), .string("x"))  // grows a list
```

### Serialise deterministically
`jsonify` defaults to compact (`indent: 0`); pass `indent: 2` for the pretty,
two-space form.

<!-- example: minor/jsonify#compact -->
```swift
jsonify(.map([("a", .int(1)), ("b", .int(2))]))   // {"a":1,"b":2}
```
<!-- => "{\"a\":1,\"b\":2}" -->

<!-- example: minor/jsonify#map -->
```swift
jsonify(.map([("a", .int(1))]), indent: 2)
// {
//   "a": 1
// }
```
<!-- => "{\n  \"a\": 1\n}" -->

<!-- example: minor/jsonify#brace -->
```swift
jsonify(.map([("a", .int(1)), ("b", .list([.int(2), .int(3)]))]), indent: 2)
// {
//   "a": 1,
//   "b": [
//     2,
//     3
//   ]
// }
```
<!-- => "{\n  \"a\": 1,\n  \"b\": [\n    2,\n    3\n  ]\n}" -->

`stringify` is the quote-light human form (map keys sorted, braces kept); the
second argument caps the length and the `...` counts toward it.

<!-- example: minor/stringify#brace -->
```swift
stringify(.map([("a", .int(1)), ("b", .list([.int(2), .int(3)]))]))   // {a:1,b:[2,3]}
```
<!-- => "{a:1,b:[2,3]}" -->

<!-- example: minor/stringify#max -->
```swift
stringify(.string("verylongstring"), 5)   // ve...
```
<!-- => "ve..." -->

`JSON.stringify(value, indent: 2)` is the underlying serialiser that `jsonify`
wraps.

### Map a sub-spec over a list (`$EACH`)
A `$EACH` command sits in **value** position as the first element of a list
`["`$EACH`", path, subspec]`, mapping the sub-spec over every entry at `path`:

<!-- example: transform/each#basic -->
```swift
transform(
  try JSON.parse(#"{"v":1,"a":[{"q":13},{"q":23}]}"#),
  try JSON.parse(#"{"x":{"y":["`$EACH`","a",{"q":"`$COPY`","r":"`.q`","p":"`...v`"}]}}"#))
// { x: { y: [ { q: 13, r: 13, p: 1 }, { q: 23, r: 23, p: 1 } ] } }
```
<!-- => {"x": {"y": [{"q": 13, "r": 13, "p": 1}, {"q": 23, "r": 23, "p": 1}]}} -->

Putting a command in **key** position (or, for `$APPLY`, directly under a map)
is an error — commands must be list values. This port does not throw; the
message lands on `inj.errs`:

<!-- example: transform/apply#badkey -->
```swift
let inj = Injection(val: .noval, parent: .noval)
transform(.map([]), try JSON.parse(#"{"x":"`$APPLY`"}"#), inj)
// inj.errs.items contains:
//   "$APPLY: invalid placement in parent map, expected: list."
```
<!-- throws: invalid placement in parent map -->

For more task recipes (`$EACH`, `$MERGE`, `$FORMAT`, `$ONE`, `$EXACT`,
`select` operators, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical;
only the host literals differ.

---

## 3. Reference

The canonical public surface (48 names) is defined by the `export { … }`
block in the canonical TypeScript; `../tools/check_parity.py` checks this
port against it. The Swift signatures, with examples, are in
[`README.md` → Function reference](./README.md#function-reference).

Swift-specific points the signatures don't show:

- **Top-level functions, canonical casing.** Library functions are
  top-level `public func`s named exactly as canonical (`isnode`, `getpath`,
  `keysof`, `setprop`, …) — **not** camelCased — so the name table matches
  every port. Methods *on* `Value`/`Injection` (`Value.isNode`,
  `inj.setval`, `inj.child`) do use Swift camelCase; they aren't part of the
  canonical surface.
- **`Value` everywhere at the boundary.** Inputs and outputs are the in-tree
  `Value` enum, not native Swift collections. Build with the convenience
  constructors (`.list([…])`, `.map([(k,v)…])`, `.string`, `.int`); unwrap
  with `asString`/`asInt`/`asDouble`/`asList`/`asMap`.
- **`getprop` vs `getelem`.** `getprop(node, key, alt?)` works on maps and
  lists and is **Group A** (a stored `.null` reads as absent → `alt`).
  `getelem(list, key, alt?)` is list-specific and supports `-1`-from-the-end
  indexing. `lookup(_:_:)` is the Group-B raw reader (returns stored `.null`
  literally) used internally.
- **No throwing API surface.** Apart from `JSON.parse`, nothing throws.
  `validate`/`transform` accumulate `inj.errs.items`; bad regex patterns
  make `re_compile` return `nil` rather than throw.
- **`typify` returns one flag per `Value` case** (`T_string`, `T_integer`,
  `T_decimal`, `T_list`, `T_map`, `T_noval`, `T_null`, …) — the enum makes
  the type direct, so it does not OR in `T_scalar`/`T_node`. `typename(_:)`
  maps a flag back to a name. The checkers (e.g. `$NUMBER`) combine flags
  with `&` internally against this single-flag result.

---

## 4. Explanation & port specifics

### One source of truth

This Swift code is a *port*. The shared corpus in
[`../build/test/`](../build/test/) is generated from the canonical
TypeScript, and this port is held to it. A behaviour question is answered by
reading the canonical TS, not by reading this code; a change to canonical
behaviour starts in TS, flows to the corpus, then to every port (see
[`../AGENTS.md`](../AGENTS.md#standard-workflows)).

### `noval` versus `null`

Swift has no `undefined`, so the port models the canonical distinction with
two enum cases — the [Group A/B rule](../DOCS.md#null-versus-absent-group-ab):

- `.noval` = **absent** (canonical `undefined`/`NONE`). `getprop` on a
  missing key returns `.noval`; Group A readers treat a stored `.null` as
  absent too.
- `.null` = the JSON null scalar; `typify(.null)` is `T_null`, and Group B
  processors (`clone`, `merge`, `walk`, `setprop`, …) preserve it literally.

`.noval` and `.null` are distinct under `==` (see `Value.swift`). This is the
single most common source of port bugs — get it right.

### Reference-stable, insertion-ordered containers

`walk`, `merge`, `inject`, and `setpath` rely on a child being shared by
reference so a mutation through one handle is visible to all — and map key
order must match insertion order (canonical object semantics; observable
through `jsonify`/`keysof`/`items`). Swift value types give neither, so the
container cases wrap **classes**: `.list(VList)` and `.map(VMap)`, where
`VMap.entries` is the in-tree `OrderedDictionary<String, Value>` (the JSON
parser builds these directly). Never substitute a plain `Array`/`Dictionary`;
`Value.sameNode(as:)` compares container identity (`===`).

### Sentinels: SKIP and DELETE

`SKIP` and `DELETE` are top-level `let`s of type `Sentinel`, compared by
identity (`===`). A custom injector or `$APPLY` function returns
`.sentinel(SKIP)` / `.sentinel(DELETE)` to omit or remove the current key;
`setprop` recognises them. Note that map-shaped sentinels (e.g. a
`` "`$SKIP`": true `` literal parsed from JSON) arrive as `.map(_)` —
`setprop` only short-circuits on the `.sentinel(_)` case.

### Regex

The uniform six-function API (`re_compile` / `re_test` / `re_find` /
`re_find_all` / `re_replace` / `re_escape`) wraps `NSRegularExpression`
(ICU). Stay inside the **RE2 subset** — ICU *allows* backreferences and
lookaround, but those don't port. Two Swift-specific edges: `re_compile`
returns `nil` (not a throw) on a bad pattern, and `re_find`/`re_find_all`
thread results through `Value.list`, not raw arrays. Cross-engine
pathological inputs (catastrophic backtracking; zero-width replace) are in
[`README.md` → Regex](./README.md#regex) and
[`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md).

---

## Build, test, and extend

```bash
cd swift
make build          # swift build
make test           # swift test --enable-test-discovery
make lint           # swift-format lint --strict --recursive Sources Tests (soft-skip if absent)
make inspect        # swift --version + package describe
make clean          # swift package clean + rm -rf .build
```

Tests live in [`Tests/VoxgigStructTests/`](./Tests/VoxgigStructTests/); the
XCTest driver
([`CorpusTests.swift`](./Tests/VoxgigStructTests/CorpusTests.swift)) loads
the shared corpus from [`../build/test/test.json`](../build/test/) and
applies the `__NULL__` round-trip exactly as the canonical TS runner does.
The Swift port passes the full shared corpus suite at full canonical parity
(all 48 functions).

**To change behaviour:** behaviour is canonical-first — edit the TypeScript,
adjust the corpus, then port the same logic here and re-run `make test` plus
`python3 ../tools/check_parity.py`. The full checklist is in
[`../AGENTS.md`](../AGENTS.md). The Swift toolchain may be absent in some
environments; if you can't build, say so rather than guessing.
