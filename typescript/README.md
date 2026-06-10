# Struct for TypeScript

> The canonical implementation.  Every other language port matches
> the behaviour defined here.  When the shared test corpus
> ([`../build/test/`](../build/test/)) and another port disagree, the
> corpus -- generated from this code -- is right.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../design/REPORT.md).


## Install

```bash
npm install @voxgig/struct
```

Package: `@voxgig/struct`.  Entry: `dist/StructUtility.js`.  Types:
`dist/StructUtility.d.ts`.  Module type: CommonJS.


## Quick start

```ts
import {
  getpath, setpath, merge, walk,
  inject, transform, validate, select,
} from '@voxgig/struct'

// Read a deep value.
getpath({ db: { host: 'localhost' } }, 'db.host')
// => 'localhost'

// Build by example: spec mirrors the desired output, with backtick
// references into the data.
transform(
  { user: { first: 'Ada', last: 'Lovelace' }, age: 36 },
  { name: '`user.first`', surname: '`user.last`', years: '`age`' }
)
// => { name: 'Ada', surname: 'Lovelace', years: 36 }

// Check the shape of incoming data.
validate(
  { name: 'Ada', age: 36 },
  { name: '`$STRING`', age: '`$INTEGER`' }
)
// => { name: 'Ada', age: 36 }   (throws on mismatch)
```


## Imports

```ts
import {
  // 29 minor utilities
  typename, getdef, isnode, ismap, islist, iskey, isempty, isfunc,
  size, slice, pad, typify, getelem, getprop, strkey, keysof,
  haskey, items, flatten, filter, escre, escurl, join, jsonify,
  stringify, pathify, clone, delprop, setprop,

  // 8 major utilities
  walk, merge, setpath, getpath, inject, transform, validate, select,

  // 2 builders
  jm, jt,

  // 3 injection helpers
  checkPlacement, injectorArgs, injectChild,

  // sentinels
  SKIP, DELETE,

  // 15 type bit-flags
  T_any, T_noval, T_boolean, T_decimal, T_integer, T_number, T_string,
  T_function, T_symbol, T_null, T_list, T_map, T_instance, T_scalar,
  T_node,

  // walk/inject mode flags
  M_KEYPRE, M_KEYPOST, M_VAL, MODENAME,

  // class wrapper
  StructUtility,

  // type-only
  Injection,
} from '@voxgig/struct'
```


## Function reference

Every function is documented with its TypeScript signature, a one-line
description, and a usage example.  Source:
[`src/StructUtility.ts`](./src/StructUtility.ts).

### Predicates

```ts
function isnode(val: any): val is Indexable
function ismap(val: any): val is { [key: string]: any }
function islist(val: any): val is any[]
function iskey(key: any): key is string | number
function isempty(val: any): boolean
function isfunc(val: any): val is Function
```

<!-- example: minor/isnode#map -->
```ts
isnode({ a: 1 })          // true
```
<!-- => true -->

```ts
isnode([1, 2])            // true
isnode('a')               // false
```

<!-- example: minor/ismap#map -->
```ts
ismap({ a: 1 })           // true
```

<!-- => true -->

```ts
ismap([1])                // false
```

<!-- example: minor/islist#list -->
```ts
islist([1, 2])            // true
```

<!-- => true -->

```ts
islist({ a: 1 })          // false
```

<!-- example: minor/iskey#str -->
```ts
iskey('name')             // true
```

<!-- => true -->

```ts
iskey(0)                  // true
iskey('')                 // false
iskey(true)               // false
```

<!-- example: minor/isempty#empty -->
```ts
isempty([])               // true
```

<!-- => true -->

```ts
isempty(null)             // true
isempty('')               // true
isempty({})               // true
isempty(0)                // false

isfunc(() => 1)           // true
isfunc('foo')             // false
```

### Type inspection

```ts
function typify(value: any): number
function typename(t: number): string
```

`typify` returns a bit-field combining a "kind" flag (`T_scalar` or
`T_node`) with a specific type flag.  `typename` looks up a
human-friendly name.

<!-- example: minor/typify#int -->
```ts
typify(1)                 // T_scalar | T_number | T_integer  (201326720)
```

<!-- => 201326720 -->

```ts
typify(42)                // T_scalar | T_number | T_integer
typify('hi')              // T_scalar | T_string
typify(null)              // T_scalar | T_null
typify(undefined)         // T_noval
typify({})                // T_node | T_map
typify([])                // T_node | T_list
```

<!-- example: minor/typename#map -->
```ts
typename(8192)            // "map"  (8192 === T_map)
```

<!-- => "map" -->

```ts
typename(typify(42))      // "integer"
typename(typify('hi'))    // "string"
typename(typify({}))      // "map"
```

### Size, slice, pad

```ts
function size(val: any): number
function slice<V>(val: V, start?: number, end?: number, mutate?: boolean): V
function pad(str: any, padding?: number, padchar?: string): string
```

<!-- example: minor/size#three -->
```ts
size([1, 2, 3])           // 3
```
<!-- => 3 -->

```ts
size({ a: 1, b: 2 })      // 2
size('abc')               // 3
size(7.9)                 // 7
```

`slice` keeps the first *N*; a negative `start` drops the last *|start|*
items, and `end` is exclusive:

<!-- example: minor/slice#mid -->
```ts
slice([1, 2, 3, 4, 5], 1, 4)   // [2, 3, 4]
```
<!-- => [2, 3, 4] -->

<!-- example: minor/slice#strhead -->
```ts
slice('abcdef', -3)            // 'abc'  (drops the last 3)
```
<!-- => "abc" -->

```ts
slice(10, 0, 5)                // 4  (number bounding; end is exclusive)
```

<!-- example: minor/pad#right -->
```ts
pad('a', 3)               // 'a  '
```
<!-- => "a  " -->

```ts
pad('hi', 5)              // 'hi   '
pad('hi', -5)             // '   hi'
pad('hi', 5, '*')         // 'hi***'
```

### Property access

```ts
function getprop(val: any, key: any, alt?: any): any
function setprop<P>(parent: P, key: any, val: any): P
function delprop<P>(parent: P, key: any): P
function getelem(val: any, key: any, alt?: any): any
function getdef(val: any, alt: any): any
function haskey(val: any, key: any): boolean
function keysof(val: any): string[]
function items(val: any): [string, any][]
function items<T>(val: any, apply: (item: [string, any]) => T): T[]
function strkey(key?: any): string
```

<!-- example: minor/getprop#hit -->
```ts
getprop({ x: 1 }, 'x')               // 1
```
<!-- => 1 -->

```ts
getprop({ a: 1 }, 'b', 'default')    // 'default'
getprop([10, 20, 30], 1)             // 20
```

<!-- example: minor/setprop#set -->
```ts
setprop({ a: 1 }, 'b', 2)            // { a: 1, b: 2 }
```

<!-- => {"a": 1, "b": 2} -->

```ts
setprop([1, 2, 3], 0, 9)             // [9, 2, 3]
```

<!-- example: minor/delprop#del -->
```ts
delprop({ a: 1, b: 2 }, 'a')         // { b: 2 }
```

<!-- => {"b": 2} -->

<!-- example: minor/getelem#neg -->
```ts
getelem([10, 20, 30], -1)            // 30
```

<!-- => 30 -->

```ts
getelem([1, 2, 3], 5, 'none')        // 'none'

getdef(undefined, 'fallback')        // 'fallback'
getdef('value', 'fallback')          // 'value'
```

<!-- example: minor/haskey#hit -->
```ts
haskey({ a: 1 }, 'a')                // true
```

<!-- => true -->

```ts
haskey({ a: undefined }, 'a')        // false

keysof([10, 20, 30])                 // ['0', '1', '2']
```

<!-- example: minor/keysof#sorted -->
```ts
keysof({ b: 4, a: 5 })               // ['a', 'b']  (sorted)
```
<!-- => ["a", "b"] -->

<!-- example: minor/items#map -->
```ts
items({ a: 1, b: 2 })                // [['a', 1], ['b', 2]]
```

<!-- => [["a", 1], ["b", 2]] -->

```ts
items([10, 20])                      // [['0', 10], ['1', 20]]
items({ a: 1 }, ([k, v]) => `${k}=${v}`)
                                     // ['a=1']
```

<!-- example: minor/strkey#num -->
```ts
strkey(2.2)                          // '2'
```

<!-- => "2" -->

```ts
strkey(1)                            // '1'
strkey('foo')                        // 'foo'
strkey(true)                         // ''  (invalid keys -> '')
```

### Path operations

```ts
function getpath(store: any, path: number | string | string[], injdef?: Partial<Injection>): any
function setpath(store: any, path: number | string | string[], val: any, injdef?: Partial<Injection>): any
function pathify(val: any, startin?: number, endin?: number): string
```

<!-- example: getpath/basic#deep -->
```ts
getpath({ a: { b: { c: 42 } } }, 'a.b.c')       // 42
```
<!-- => 42 -->

```ts
getpath({ a: { b: { c: 42 } } }, ['a', 'b', 'c'])
getpath({ a: [10, 20] }, 'a.1')                 // 20
getpath({ a: 1 }, 'missing')                    // undefined

const store = {}
setpath(store, 'db.host', 'localhost')
// store === { db: { host: 'localhost' } }

setpath({ a: [1, 2, 3] }, 'a.1', 99)
// { a: [1, 99, 3] }
```

<!-- example: minor/setpath#nested -->
```ts
setpath({ a: 1, b: 2 }, 'b', 22)                // { a: 1, b: 22 }
```

<!-- => {"a": 1, "b": 22} -->

<!-- example: minor/pathify#parts -->
```ts
pathify(['a', 'b', 'c'])                        // 'a.b.c'
```

<!-- => "a.b.c" -->

```ts
pathify('a.b.c')                                // 'abc'  (a plain string is not split on dots)
pathify(['a', 'b', 'c'], 1)                     // 'b.c'
```

### Tree operations

```ts
function walk(
  val: any,
  before?: WalkApply,
  after?: WalkApply,
  maxdepth?: number,
  // recursive state args:
  key?, parent?, path?, pool?
): any

function merge(val: any[], maxdepth?: number): any
function clone(val: any): any
function flatten(list: any[], depth?: number): any[]
function filter(val: any, check: (item: [string, any]) => boolean): any[]

type WalkApply = (
  key: string | number | undefined,
  val: any,
  parent: any,
  path: string[]
) => any
```

```ts
// Replace nulls with 'DEFAULT' on ascend.
walk(tree, undefined, (key, val, parent, path) =>
  val === null ? 'DEFAULT' : val
)
```

Last input wins; maps deep-merge; lists merge by index:

<!-- example: merge#basic -->
```ts
merge([
  { a: 1, b: 2, k: [10, 20], x: { y: 5, z: 6 } },
  { b: 3, d: 4, e: 8, k: [11], x: { y: 7 } },
])
// { a: 1, b: 3, d: 4, e: 8, k: [11, 20], x: { y: 7, z: 6 } }
```

<!-- => {"a": 1, "b": 3, "d": 4, "e": 8, "k": [11, 20], "x": {"y": 7, "z": 6}} -->

<!-- example: minor/clone#deep -->
```ts
clone({ a: { b: [1, 2] } })             // { a: { b: [1, 2] } }  (a deep copy)
```

<!-- => {"a": {"b": [1, 2]}} -->

<!-- example: minor/flatten#nested -->
```ts
flatten([1, [2, [3]]])                  // [1, 2, [3]]  (one level by default)
```

<!-- => [1, 2, [3]] -->

```ts
flatten([1, [2, [3, [4]]]])             // [1, 2, [3, [4]]]
flatten([1, [2, [3, [4]]]], 2)          // [1, 2, 3, [4]]
```

`filter` passes each `[key, value]` pair to the check and returns the
matching **values** (not the pairs):

<!-- example: minor/filter#gt3 -->
```ts
filter([1, 2, 3, 4, 5], ([k, v]) => v > 3)
// [4, 5]
```
<!-- => [4, 5] -->

### String / URL / JSON

```ts
function escre(s: string): string
function escurl(s: string): string
function join(arr: any[], sep?: string, url?: boolean): string
function jsonify(val: any, flags?: { indent?: number, offset?: number }): string
function stringify(val: any, maxlen?: number, pretty?: any): string
```

<!-- example: minor/escre#dots -->
```ts
escre('a.b+c')                          // 'a\\.b\\+c'
```

<!-- => "a\\.b\\+c" -->

<!-- example: minor/escurl#space -->
```ts
escurl('hello world?')                  // 'hello%20world%3F'
```

<!-- => "hello%20world%3F" -->

<!-- example: minor/join#sep -->
```ts
join(['a', 'b', 'c'], '/')              // 'a/b/c'
```

<!-- => "a/b/c" -->

```ts
join(['http:', '/foo/', '/bar'], '/', true)
                                        // 'http:/foo/bar'  (URL-mode collapses)
```

`jsonify` pretty-prints by default (indent 2); pass `{ indent: 0 }` for the
compact form:

<!-- example: minor/jsonify#map -->
```ts
jsonify({ a: 1 })
// {
//   "a": 1
// }
```
<!-- => "{\n  \"a\": 1\n}" -->

<!-- example: minor/jsonify#compact -->
```ts
jsonify({ a: 1, b: 2 }, { indent: 0 })  // '{"a":1,"b":2}'
```
<!-- => "{\"a\":1,\"b\":2}" -->

`stringify` is the compact, quote-light form — keys are sorted and object
braces are kept; the second argument caps the length (the `...` counts):

<!-- example: minor/stringify#brace -->
```ts
stringify({ a: 1, b: [2, 3] })          // '{a:1,b:[2,3]}'
```
<!-- => "{a:1,b:[2,3]}" -->

<!-- example: minor/stringify#max -->
```ts
stringify('verylongstring', 5)          // 've...'
```
<!-- => "ve..." -->

### Injection / transform / validate / select

```ts
function inject(
  val: any,
  store: any,
  injdef?: Partial<Injection>,
): any

function transform(
  data: any,         // source data
  spec: any,         // by-example output shape
  injdef?: Partial<Injection>
): any

function validate(
  data: any,         // input to check
  spec: any,         // expected shape with checker tokens
  injdef?: Partial<Injection>
): any

function select(children: any, query: any): any[]
```

<!-- example: inject#basic -->
```ts
// Backtick refs in strings are replaced by store values.
inject({ x: '`a`', y: 2 }, { a: 1 })    // { x: 1, y: 2 }
```

<!-- => {"x": 1, "y": 2} -->

```ts
inject(
  { greeting: 'hello `name`', age: '`years`' },
  { name: 'Ada', years: 36 }
)
// { greeting: 'hello Ada', age: 36 }

// Build a result by example.
transform(
  { hold: { x: 1 }, top: 99 },
  { a: '`hold.x`', b: '`top`' }
)
// { a: 1, b: 99 }
```

Transform commands drive structural ops. A command like `$EACH` appears in
**value** position — as the first element of a list `['`$EACH`', path, subspec]`
— mapping the sub-spec over every entry at `path`:

<!-- example: transform/each#basic -->
```ts
transform(
  { v: 1, a: [{ q: 13 }, { q: 23 }] },
  { x: { y: ['`$EACH`', 'a', { q: '`$COPY`', r: '`.q`', p: '`...v`' }] } }
)
// { x: { y: [ { q: 13, r: 13, p: 1 }, { q: 23, r: 23, p: 1 } ] } }
```
<!-- => {"x": {"y": [{"q": 13, "r": 13, "p": 1}, {"q": 23, "r": 23, "p": 1}]}} -->

Putting a command in **key** position (or, for `$APPLY`, directly under a map)
is an error — commands must be list values:

<!-- example: transform/apply#badkey -->
```ts
transform({}, { x: '`$APPLY`' })
// throws: $APPLY: invalid placement in parent map, expected: list.
```
<!-- throws: invalid placement in parent map -->

<!-- example: validate#shape -->
```ts
// Validate against a shape (throws on mismatch).
validate(
  { name: 'Ada', age: 36 },
  { name: '`$STRING`', age: '`$INTEGER`' }
)
// { name: 'Ada', age: 36 }
```

<!-- => {"name": "Ada", "age": 36} -->

<!-- example: select#query -->
```ts
// Find children matching a query.
select(
  { a: { name: 'Alice', age: 30 }, b: { name: 'Bob', age: 25 } },
  { age: 30 }
)
// [{ name: 'Alice', age: 30, $KEY: 'a' }]
```

<!-- => [{"name": "Alice", "age": 30, "$KEY": "a"}] -->

### Builders

```ts
function jm(...kv: any[]): Record<string, any>
function jt(...v: any[]): any[]
```

```ts
jm('a', 1, 'b', 2)        // { a: 1, b: 2 }
jt(1, 2, 3)               // [1, 2, 3]
```

Useful for building literal-looking JSON shapes inside expressions.

### Injection helpers

These are exposed for callers writing custom injectors or modify
hooks; most users will not need them directly.

```ts
function checkPlacement(
  modes: number,            // bitmask of M_KEYPRE | M_KEYPOST | M_VAL
  ijname: string,           // injection name (transform/validate command)
  parentTypes: number,      // expected parent types
  inj: Injection
): boolean

function injectorArgs(argTypes: number[], args: any[]): any
function injectChild(child: any, store: any, inj: Injection): Injection
```


## Constants

### Sentinels

```ts
SKIP        // emit nothing for this key
DELETE      // remove this key from the parent
```

Returned from a transform / inject step to signal these structural
operations to the caller.

### Type bit-flags

`typify(val)` returns a bit-field combining a kind flag with a
specific type:

```ts
T_any         // wildcard / no constraint
T_noval       // property absent / undefined (NOT a scalar)
T_boolean     // boolean scalar
T_decimal     // non-integer numeric scalar
T_integer     // integer numeric scalar
T_number      // any number (set together with T_integer/T_decimal)
T_string      // string scalar
T_function    // function value
T_symbol      // symbolic atom (for languages that have them)
T_null        // JSON null (distinct from absent)
T_list        // list node (array)
T_map         // map node (object)
T_instance    // class instance (non-plain object)
T_scalar      // bit set on every scalar type
T_node        // bit set on every node type
```

```ts
const t = typify('hi')
0 < (T_string & t)        // true
0 < (T_scalar & t)        // true
typename(t)               // 'string'
```

### Walk / inject phase flags

```ts
M_KEYPRE      // about to descend into a child by key
M_KEYPOST     // returned from descending into a child by key
M_VAL         // visiting the value of a leaf
MODENAME      // string[] — human names by mode flag
```


## Transform commands

Quote inside a `transform` spec, e.g. `` '`$COPY`' ``.

| Command   | Purpose                                                           |
|-----------|-------------------------------------------------------------------|
| `$DELETE` | Remove the current key from the output.                           |
| `$COPY`   | Copy the matching value from `data` at the current path.          |
| `$KEY`    | Emit the current key under another name.                          |
| `$ANNO`   | Annotate the current node with extra fields.                      |
| `$MERGE`  | Deep-merge several sub-specs into the current node.               |
| `$EACH`   | Apply a sub-spec to every entry of a list or map.                 |
| `$PACK`   | Repack a node by rewriting its keys / shape.                      |
| `$REF`    | Resolve a named reference inside the spec.                        |
| `$FORMAT` | Render a templated string using values from `data`.               |
| `$APPLY`  | Call a function (from `extra` / `injdef`) on the current value.   |
| `$DS`     | Emit a literal `$` (escape the dollar sign).                      |
| `$WHEN`   | Insert the current date and time as an ISO-8601 string.           |


## Validate checkers

Quote inside a `validate` spec, e.g. `` '`$STRING`' ``.

| Checker     | Accepts                                                         |
|-------------|-----------------------------------------------------------------|
| `$MAP`      | A map.                                                          |
| `$LIST`     | A list.                                                         |
| `$STRING`   | A string.                                                       |
| `$NUMBER`   | A number (integer or decimal).                                  |
| `$INTEGER`  | An integer.                                                     |
| `$DECIMAL`  | A non-integer number.                                           |
| `$BOOLEAN`  | A boolean.                                                      |
| `$NULL`     | JSON null.                                                      |
| `$NIL`      | Null or absent (lenient).                                       |
| `$FUNCTION` | A callable function.                                            |
| `$INSTANCE` | A class instance.                                               |
| `$ANY`      | Any value (placeholder for "no constraint").                    |
| `$CHILD`    | Apply a sub-spec to every direct child.                         |
| `$ONE`      | Match exactly one of a list of alternative sub-specs.           |
| `$EXACT`    | Match a literal value exactly (no shape coercion).              |


## `StructUtility` class

Wraps every function and constant as instance properties.  Useful
when you want to inject the API surface (e.g. for stubbing in tests):

```ts
import { StructUtility } from '@voxgig/struct'

const su = new StructUtility()
su.getpath({ a: { b: 1 } }, 'a.b')      // 1
su.merge([{ a: 1 }, { b: 2 }])          // { a: 1, b: 2 }
```


## Notes

### `null` versus `undefined`

TypeScript distinguishes the two; `struct` preserves the
distinction:

- `undefined` means "absent".  `getprop` returns `undefined` for a
  missing key, and most predicates treat `undefined` as not-a-node.
- `null` is the JSON null value -- a defined scalar.  `typify(null)`
  returns `T_scalar | T_null`.

Most JSON parsers conflate them; if your data source returns `null`
for absent fields, convert them before passing into `struct` -- or
adopt the `'__NULL__'` placeholder used by the shared test corpus.

### Lists are mutable and reference-stable

`walk`, `merge`, `inject`, and `setpath` all rely on lists being
reference-stable: a mutation through one reference is visible to
every holder.  This is JavaScript's natural behaviour; no wrapper
needed.

### Path syntax

Paths can be:

- a dot-separated string: `'a.b.0.c'`
- an array: `['a', 'b', 0, 'c']`

Integer-looking string keys index into lists; everything else
indexes maps.

### `walk` paths are reused

The `path` array passed to a `WalkApply` callback is reused across
calls (one shared array per depth).  Clone it (`path.slice()`) if
you need to retain it past the callback.


## Regex

The library exposes a uniform six-function regex API across every
port (see `/design/REGEX_API.md` for the contract and `/design/REGEX.md` for the
supported dialect). On TypeScript the canonical implementation is
ECMAScript `RegExp`.

### API

| Function | Maps to |
|---|---|
| `re_compile(pattern, flags?)`     | `new RegExp(pattern, flags ?? 'g')` |
| `re_test(pattern, input)`         | `pattern.test(input)` |
| `re_find(pattern, input)`         | `input.match(pattern)` (non-global pattern) |
| `re_find_all(pattern, input)`     | `[...input.matchAll(pattern)]` |
| `re_replace(pattern, input, rep)` | `input.replace(pattern, rep)` (global pattern) |
| `re_escape(s)`                    | escape `[.*+?^${}()|[\]\\]` in `s` |

### Dialect

Patterns must stay inside the **RE2 subset** documented in `/design/REGEX.md`:
literals + escapes, `.`, `^`/`$`, `* + ? {n} {n,} {n,m}` (greedy + lazy),
character classes incl. `\d \w \s` etc., `\b`/`\B`, `(...)` / `(?:...)` /
`(?<name>...)`, alternation. ECMAScript `RegExp` supports backreferences
and lookaround, but other ports do not — using those will not be
portable.

### Sharp edges

- **Catastrophic backtracking.** ECMAScript `RegExp` uses backtracking;
  nested quantifiers (e.g. `(a+)+`) against a non-matching suffix can be
  exponential in the input length. The discovery panel measures ~180 ms
  on Node 22 for `^(a+)+$` against 22 a's plus `!`. RE2-style engines
  finish the same case in under 0.1 ms. Write linear-friendly patterns
  (`a+` instead of `(a+)+`) and keep injected user input in
  character classes, not in alternations.
- **Zero-width `replace`.** `re_replace("a*", "abc", "X")` returns
  `"XXbXcX"` here — the ECMA convention shared by every port whose
  host engine is PCRE/ECMA/.NET/Java/Onigmo, plus the in-tree
  Thompson NFA ports (Rust / C / Lua / Zig). Go is the exception:
  RE2 returns `"XbXcX"`. Don't rely on cross-port identity of
  zero-width replacement output — see `/design/REGEX_PATHOLOGICAL.md`.

See `/design/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input
panel and per-port outcomes.


## Build and test

```bash
cd typescript
npm install
npm run build              # tsc -> dist/
npm test                   # node --test on dist-test/
```

Tests live in [`test/`](./test/) and read fixtures from
[`../build/test/`](../build/test/).  The test runner consumes the
shared JSONIC corpus shared by every language port.
