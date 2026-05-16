# Struct for Swift

> Swift port of the canonical TypeScript implementation.
> Status: **complete** — the full shared corpus passes
> (`swift test --enable-test-discovery`): all 25 minor utilities, `walk`,
> `merge`, `setpath`, `getpath`, `inject`, `transform` (all 11 commands),
> `validate` (all 15 checkers), `select` (all 4 operators), and the
> `Injection` state machine.

For motivation, the language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[`REPORT.md`](../REPORT.md).


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

- All 25 **minor utilities**: `isnode`, `ismap`, `islist`, `iskey`,
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

Uniform six-function regex API (see `/REGEX_API.md`). The Swift port
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

Patterns must stay inside the **RE2 subset** documented in `/REGEX.md`.
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

See `/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


## Tests

```bash
make test
```

Loads `../build/test/test.json` (the cross-port corpus) and runs
every wired subsystem. All 11 corpus subtests + smoke tests pass —
roughly 700 individual canonical test cases.
