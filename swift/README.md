# Struct for Swift

> Swift port of the canonical TypeScript implementation.
> Status: **complete** — the full shared corpus passes
> (`swift test --enable-test-discovery`): all 29 minor utilities, `walk`,
> `merge`, `setpath`, `getpath`, `inject`, `transform` (all 11 commands),
> `validate` (all 15 checkers), `select` (all 4 operators), and the
> `Injection` state machine.

For motivation, the language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[`REPORT.md`](../design/REPORT.md).


## Install

Inside the monorepo:

```bash
cd swift
make test
```

Tested with Swift 6.0.2. **Zero runtime third-party dependencies** —
only Foundation. The insertion-ordered map type lives in-tree at
[`Sources/VoxgigStruct/OrderedDictionary.swift`](./Sources/VoxgigStruct/OrderedDictionary.swift).


## Quick start

```swift
import VoxgigStruct

let store = try JSON.parse(#"{"db":{"host":"localhost"}}"#)
let host  = getpath(store, .string("db.host"))
// host == .string("localhost")

let spec = try JSON.parse(#"{"x":"`db.host`"}"#)
let out  = inject(spec, store)
// out == { "x": "localhost" }
```


## Function reference

Source: [`Sources/VoxgigStruct/`](./Sources/VoxgigStruct/), split per
subsystem (`Value.swift`, `Constants.swift`, `JSON.swift`, `Minor.swift`,
`Walk.swift`, `Merge.swift`, `Path.swift`, `Inject.swift`,
`Transform.swift`, `Validate.swift`, `Select.swift`, `Injection.swift`).

Functions live as top-level `public func`s in module `VoxgigStruct`. The
port keeps the canonical TS names (`isnode`, `getpath`, `keysof`, …)
rather than `camelCase`ing them — this means the function-name table is
the same across every Voxgig port.

### Core types

The Swift port models JSON-shaped data plus the language-runtime extras
the canonical inject machinery needs:

| JSON type     | Swift form                                                |
|---------------|-----------------------------------------------------------|
| object        | `.map(VMap)` — `VMap` wraps an `OrderedDictionary<String, Value>` so insertion order is preserved through every operation. Reference type. |
| array         | `.list(VList)` — `VList` wraps `[Value]`. Reference type. |
| string        | `.string(String)`                                          |
| integer       | `.int(Int64)`                                              |
| decimal       | `.double(Double)`                                          |
| true / false  | `.bool(Bool)`                                              |
| null          | `.null` — JSON null, distinct from "absent".               |
| absent        | `.noval` — corresponds to TS `undefined` / `NONE`.         |
| function      | `.function(Injector)` — for transform / validate / select handlers and `$BT` / `$DS` / `$WHEN` / `$SPEC` thunks. |
| sentinel      | `.sentinel(Sentinel)` — pointer-identity singletons; the two pre-allocated `SKIP` and `DELETE` are recognised by `setprop`. |

`Value` is an `indirect enum`. Container cases hold class instances
(`VList` / `VMap`) so list/map references are reference-stable across
calls — required by the canonical merge/walk semantics where an
ancestor mutates a child in place.

### Sentinels

`SKIP` and `DELETE` are top-level `let`s of type `Sentinel`, compared
by identity (`===`). `setprop` recognises them and either preserves
or removes the slot.

### JSON parser

`JSON.parse(text)` returns a `Value` that uses the type rules above
(in particular, the in-tree `OrderedDictionary`-backed
maps and `.int` vs `.double` for integers vs decimals). The Foundation
`JSONSerialization` is not used because it doesn't preserve insertion
order. `JSON.stringify(value, indent: 2)` serialises back.

### What's wired

- All 29 **minor utilities**: `isnode`, `ismap`, `islist`, `iskey`,
  `isempty`, `isfunc`, `size`, `slice`, `pad`, `typify`, `getelem`,
  `getprop`, `strkey`, `keysof`, `haskey`, `items`, `flatten`,
  `filter`, `escre`, `escurl`, `join`, `jsonify`, `stringify`,
  `pathify`, `clone`, `delprop`, `setprop`, `typename`, `getdef`.
- Major utilities: `walk`, `merge`, `setpath`, `getpath`.
- `inject` (three-phase key processing) with `_injectstr` (full and
  partial backtick refs) and `_injecthandler` (default command
  dispatcher).
- `transform` and the 11 transform commands: `$DELETE`, `$COPY`,
  `$KEY`, `$META`, `$ANNO`, `$MERGE`, `$EACH`, `$PACK`, `$REF`,
  `$FORMAT`, `$APPLY` (plus the `FORMATTER` table for `$FORMAT`:
  `identity`, `upper`, `lower`, `string`, `number`, `integer`,
  `concat`).
- `validate` and the 15 validate checkers: `$STRING`, `$NUMBER`,
  `$INTEGER`, `$DECIMAL`, `$BOOLEAN`, `$NULL`, `$NIL`, `$MAP`,
  `$LIST`, `$FUNCTION`, `$INSTANCE`, `$ANY`, `$CHILD`, `$ONE`,
  `$EXACT`.
- `select` and the 4 select operators: `$AND`, `$OR`, `$NOT`,
  `$CMP` (with `$GT`, `$LT`, `$GTE`, `$LTE`, `$LIKE`).
- Type constants (`T_any`, `T_noval`, …, `T_node`), mode constants
  (`M_KEYPRE` / `M_KEYPOST` / `M_VAL`), modename table, sentinels
  (`SKIP`, `DELETE`).
- `Injection` reference type with `child` / `descend` / `setval`,
  plus helpers `checkPlacement`, `injectorArgs`, `injectChild`.
- Builder helpers: `jm` (alternating key/value), `jmd` (from
  `OrderedDictionary`), `jt` (list literal).
- Regex helper wrappers: `re_compile` / `re_test` / `re_find` /
  `re_find_all` / `re_replace` / `re_escape`.

### Examples

Every value crossing the API boundary is a `Value`; build literals with the
`.map([(k, v)…])` / `.list([…])` / `.string` / `.int` constructors, or parse a
JSON string with `JSON.parse(_:)`. Each call below has the same meaning in every
port — only the syntax changes.

#### Predicates

<!-- example: minor/ismap#map -->
```swift
ismap(.map([("a", .int(1))]))   // true
```

<!-- => true -->

<!-- example: minor/islist#list -->
```swift
islist(.list([.int(1), .int(2)]))   // true
```

<!-- => true -->

<!-- example: minor/iskey#str -->
```swift
iskey(.string("name"))   // true
```

<!-- => true -->

<!-- example: minor/isempty#empty -->
```swift
isempty(.list([]))   // true
```

<!-- => true -->

#### Type inspection

`typify(_:)` maps a `Value` to a type flag; `typename(_:)` looks up its name.
The canonical corpus pins the TypeScript bit-field result (`T_scalar |
T_number | T_integer`); see the [Reference](./DOCS.md#3-reference) for how this
port's single-flag enum relates to it.

<!-- example: minor/typify#int -->
```swift
typify(.int(1))   // T_scalar | T_number | T_integer  (201326720)
```

<!-- => 201326720 -->

<!-- example: minor/typename#map -->
```swift
typename(8192)   // "map"
```

<!-- => "map" -->

#### Property access

<!-- example: minor/getelem#neg -->
```swift
getelem(.list([.int(10), .int(20), .int(30)]), .int(-1))   // .int(30)
```

<!-- => 30 -->

<!-- example: minor/setprop#set -->
```swift
setprop(.map([("a", .int(1))]), .string("b"), .int(2))   // { a: 1, b: 2 }
```

<!-- => {"a": 1, "b": 2} -->

<!-- example: minor/delprop#del -->
```swift
delprop(.map([("a", .int(1)), ("b", .int(2))]), .string("a"))   // { b: 2 }
```

<!-- => {"b": 2} -->

<!-- example: minor/haskey#hit -->
```swift
haskey(.map([("a", .int(1))]), .string("a"))   // true
```

<!-- => true -->

<!-- example: minor/items#map -->
```swift
items(.map([("a", .int(1)), ("b", .int(2))]))   // [["a", 1], ["b", 2]]
```

<!-- => [["a", 1], ["b", 2]] -->

<!-- example: minor/strkey#num -->
```swift
strkey(.double(2.2))   // "2"
```

<!-- => "2" -->

#### Path operations

<!-- example: minor/setpath#nested -->
```swift
setpath(.map([("a", .int(1)), ("b", .int(2))]), .string("b"), .int(22))   // { a: 1, b: 22 }
```

<!-- => {"a": 1, "b": 22} -->

<!-- example: minor/pathify#parts -->
```swift
pathify(.list([.string("a"), .string("b"), .string("c")]))   // "a.b.c"
```

<!-- => "a.b.c" -->

#### Tree operations

Last input wins; maps deep-merge; lists merge by index:

<!-- example: merge#basic -->
```swift
merge(.list([
  try JSON.parse(#"{"a":1,"b":2,"k":[10,20],"x":{"y":5,"z":6}}"#),
  try JSON.parse(#"{"b":3,"d":4,"e":8,"k":[11],"x":{"y":7}}"#),
]))
// { a: 1, b: 3, d: 4, e: 8, k: [11, 20], x: { y: 7, z: 6 } }
```

<!-- => {"a": 1, "b": 3, "d": 4, "e": 8, "k": [11, 20], "x": {"y": 7, "z": 6}} -->

<!-- example: minor/clone#deep -->
```swift
clone(.map([("a", .map([("b", .list([.int(1), .int(2)]))]))]))
// { a: { b: [1, 2] } }  (a deep copy)
```

<!-- => {"a": {"b": [1, 2]}} -->

`flatten` collapses one level by default:

<!-- example: minor/flatten#nested -->
```swift
flatten(.list([.int(1), .list([.int(2), .list([.int(3)])])]))
// [1, 2, [3]]  (one level by default)
```

<!-- => [1, 2, [3]] -->

#### String / URL

<!-- example: minor/escre#dots -->
```swift
escre(.string("a.b+c"))   // "a\\.b\\+c"
```

<!-- => "a\\.b\\+c" -->

<!-- example: minor/escurl#space -->
```swift
escurl(.string("hello world?"))   // "hello%20world%3F"
```

<!-- => "hello%20world%3F" -->

<!-- example: minor/join#sep -->
```swift
join(.list([.string("a"), .string("b"), .string("c")]), "/")   // "a/b/c"
```

<!-- => "a/b/c" -->

#### Injection / validate / select

<!-- example: inject#basic -->
```swift
// Backtick refs in strings are replaced by store values.
inject(
  try JSON.parse(#"{"x":"`a`","y":2}"#),
  try JSON.parse(#"{"a":1}"#))
// { x: 1, y: 2 }
```

<!-- => {"x": 1, "y": 2} -->

<!-- example: validate#shape -->
```swift
// Validate against a shape (the leaves are type checkers).
validate(
  try JSON.parse(#"{"name":"Ada","age":36}"#),
  try JSON.parse(#"{"name":"`$STRING`","age":"`$INTEGER`"}"#))
// { name: "Ada", age: 36 }
```

<!-- => {"name": "Ada", "age": 36} -->

<!-- example: select#query -->
```swift
// Find children matching a query; each match tagged with its $KEY.
select(
  try JSON.parse(#"{"a":{"name":"Alice","age":30},"b":{"name":"Bob","age":25}}"#),
  try JSON.parse(#"{"age":30}"#))
// [ { name: "Alice", age: 30, $KEY: "a" } ]
```

<!-- => [{"name": "Alice", "age": 30, "$KEY": "a"}] -->

### Language adaptations

- **Insertion-ordered maps:** Swift dictionaries don't preserve
  insertion order, so every map is backed by `OrderedDictionary`
  from the in-tree `OrderedDictionary`. The JSON parser builds
  these directly so object key order survives parsing.
- **Number representation:** TS's `Number` is a single double; the
  port splits into `.int(Int64)` and `.double(Double)` so `typify`
  is direct (no integer-ness probe at runtime). Mixed-int/double
  equality works in `==`.
- **Sentinels & sentinel-shaped maps:** `.sentinel(SKIP)` /
  `.sentinel(DELETE)` are blessed singletons. The canonical's
  ``"`$SKIP`": true``-style map sentinels parse to `.map(...)` from
  JSON; `setprop` only short-circuits on `.sentinel(_)`.
- **`Injection` as a reference type:** the canonical machinery
  mutates `inj.keyI`, `inj.keys`, `inj.dpath`, etc. across
  recursive calls. Swift class semantics give that for free.
- **Test runner:** `XCTest`-based driver in
  `Tests/VoxgigStructTests/CorpusTests.swift` loads
  `../build/test/test.json` and applies the canonical `NULLMARK`
  `__NULL__` round-trip for the `inject.string` and `select.*`
  sets exactly as the canonical TS runner does.

## Regex

Uniform six-function regex API (see `/design/REGEX_API.md`). The Swift port
wraps `NSRegularExpression`.

### API

| Function | Returns |
|---|---|
| `re_compile(pattern, flags?)`         | `NSRegularExpression?` (nil on bad pattern) |
| `re_test(pattern, input)`             | `Bool` |
| `re_find(pattern, input)`             | `Value.list([whole, group1, …])` or `.noval` |
| `re_find_all(pattern, input)`         | `Value.list([...])` |
| `re_replace(pattern, input, repl)`    | `String` |
| `re_escape(v)`                        | `String` |

### Dialect

Patterns must stay inside the **RE2 subset** documented in `/design/REGEX.md`.
`NSRegularExpression` (ICU-based) supports backreferences and lookaround;
using them will not be portable.

### Sharp edges

- **Catastrophic backtracking.** ICU regex is backtracking. Stay
  inside the RE2 subset and prefer flat patterns.
- **Compile failures are nil, not throws.** `re_compile` returns
  `nil` on bad pattern (the underlying `try?` swallows the error).
  Callers should check the optional rather than rely on an exception.
- **`Value` shape for `re_find` / `re_find_all`.** The Swift port
  threads results through the in-tree `Value` enum (matching the
  rest of the API surface), not raw arrays.

See `/design/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


## Tests

```bash
make test
```

Loads `../build/test/test.json` (the cross-port corpus) and runs
every wired subsystem. All 11 corpus subtests + smoke tests pass —
roughly 700 individual canonical test cases.
