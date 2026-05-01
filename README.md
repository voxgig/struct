# Voxgig Struct

> Uniform JSON-shaped data structure manipulations, in many languages.

`struct` is the data manipulation primitive used inside the Voxgig
SDKs.  Every Voxgig SDK -- whatever its host language -- needs to look
up values inside nested JSON, merge configurations, transform data
between shapes, and validate that incoming data matches an expected
shape.  Rewriting that work for each language drifts: behaviours
diverge, edge cases get patched in one place but not another, and the
semantics of "the same" call become subtly different.

`struct` solves that by defining one canonical API, in one canonical
implementation (TypeScript), and porting it to every language a
Voxgig SDK runs in.  The same names, the same arguments, the same
return values, and the same JSON-driven test corpus run against every
port.  When you call `getpath('a.b.c', store)` in Python, Go, PHP, or
Lua, you get the same answer.


## Documentation map (Diataxis)

These docs follow the [Diataxis](https://diataxis.fr/) framework, which
splits documentation into four quadrants by purpose:

| Quadrant      | Purpose                | Where to find it                                                  |
|---------------|------------------------|-------------------------------------------------------------------|
| Tutorial      | Learning by doing      | [Quick start](#quick-start) below + each language's `DOCS.md`     |
| How-to guides | Solving a task         | [Common recipes](#common-recipes) below + each language's docs    |
| Reference     | Looking things up      | [API reference](#language-neutral-api-reference) below + per-lang |
| Explanation   | Understanding the why  | [Motivation](#motivation) and [Concepts](#concepts) below         |

Per-language docs live next to each implementation:

| Language   | Status     | Docs                              |
|------------|------------|-----------------------------------|
| TypeScript | Canonical  | [`ts/DOCS.md`](./ts/DOCS.md)      |
| JavaScript | Complete   | [`js/DOCS.md`](./js/DOCS.md)      |
| Python     | Complete   | [`py/DOCS.md`](./py/DOCS.md)      |
| Go         | Complete   | [`go/DOCS.md`](./go/DOCS.md)      |
| PHP        | Complete   | [`php/DOCS.md`](./php/DOCS.md)    |
| Ruby       | Complete   | [`rb/DOCS.md`](./rb/DOCS.md)      |
| Lua        | Complete   | [`lua/DOCS.md`](./lua/DOCS.md)    |
| C#         | In progress| [`cs/DOCS.md`](./cs/DOCS.md)      |
| Zig        | In progress| [`zig/DOCS.md`](./zig/DOCS.md)    |
| Java       | Partial    | [`java/DOCS.md`](./java/DOCS.md)  |
| C++        | Partial    | [`cpp/DOCS.md`](./cpp/DOCS.md)    |

The cross-language parity matrix lives in [`REPORT.md`](./REPORT.md).


## Motivation

Voxgig SDKs work with structured data: configuration trees, API
request and response payloads, validation specs, transform recipes.
These are JSON-shaped: nested maps and lists of scalars.  The same
operations come up over and over:

- "Give me the value at path `service.db.host`."
- "Merge these three config maps, last one wins, but deep-merge maps."
- "Walk this tree and replace any `null` value with a default."
- "Take this template, and populate it from this data store."
- "Check that this incoming record matches the expected shape."

The naive answer is "use the host language's stdlib".  But:

- The host language may not have a deep merge.  Or its deep merge
  may have different rules than the next language's deep merge.
- "Get a value at a path" is one line in JavaScript and ten in C++.
- The semantics of `null` versus "absent" versus "empty" differ
  between languages, between JSON parsers, and between developers on
  the same team.
- Once you have transforms and validation, you really do not want to
  reimplement them per language.

`struct` is the answer: one API, one set of semantics, one JSON test
corpus, ported faithfully to every language Voxgig SDKs support.  An
SDK can rely on the same primitive operations everywhere.  A bug fix
in the canonical TypeScript flows through to every other port.

The shared test corpus (`build/test/*.jsonic`) is the contract.  Any
implementation passes only if it matches the canonical answers
case-for-case.


## Concepts

A few terms recur throughout the API.

- **Node**: a map (object) or list (array).  Anything that can have
  children.
- **Key**: a non-empty string (for maps) or an integer index (for
  lists).
- **Path**: a sequence of keys, written as a dotted string
  (`'a.b.0.c'`) or an array (`['a','b',0,'c']`).
- **Store**: the source data for an injection or path lookup.
- **Spec**: a by-example data structure that drives `transform` and
  `validate`.  The spec mirrors the desired output shape.
- **Injection**: substituting backtick-quoted references inside a
  spec with values pulled from a store, e.g. ``` `a.b` ``` becomes the
  value at path `a.b` in the store.
- **Sentinel**: a special marker value with no in-band JSON
  representation.  `SKIP` means "don't write this key", `DELETE`
  means "remove this key".

By-example design: the shape of the output is described by data that
*looks like* the output.  A transform spec for `{name, age}` is itself
a map with keys `name` and `age`.  A validate spec is the same shape
as the data it accepts, with type tokens (e.g. ``` `$STRING` ```) at
the leaves.


## Quick start

Pick your language's `DOCS.md` for installation instructions.  Once
installed, the calls below all mean the same thing.

### Look up a value at a path

JavaScript / TypeScript:

```js
const { getpath } = require('@voxgig/struct')
getpath('db.host', { db: { host: 'localhost', port: 5432 } })
// => 'localhost'
```

Python:

```python
from voxgig_struct import getpath
getpath('db.host', {'db': {'host': 'localhost', 'port': 5432}})
# => 'localhost'
```

Go:

```go
voxgigstruct.GetPath("db.host", map[string]any{
    "db": map[string]any{"host": "localhost", "port": 5432},
})
// => "localhost"
```

### Merge a chain of maps

```js
merge([
  { a: 1, b: 2, x: { y: 5, z: 6 } },
  { b: 3,       x: { y: 7 }       },
])
// => { a: 1, b: 3, x: { y: 7, z: 6 } }
```

Last input wins for scalars; maps deep-merge; lists are merged by
index.

### Transform by example

```js
transform(
  { user: { first: 'Ada', last: 'Lovelace' }, age: 36 },
  { name: '`user.first`', surname: '`user.last`', years: '`age`' }
)
// => { name: 'Ada', surname: 'Lovelace', years: 36 }
```

### Validate by example

```js
validate(
  { name: 'Ada', age: 36 },
  { name: '`$STRING`', age: '`$INTEGER`' }
)
// => { name: 'Ada', age: 36 }   // ok
```

### Walk a tree

```js
walk(tree, (key, val, parent, path) => {
  return val === null ? 'DEFAULT' : val
})
```


## Common recipes

These map directly to the per-language API.  Substitute the function
names that match your language's casing convention.

| Goal                                       | Function                       |
|--------------------------------------------|--------------------------------|
| Read a deep value, with a default          | `getpath`, `getprop`, `getdef` |
| Set a deep value, creating intermediate    | `setpath`                      |
| Test a value's shape                       | `isnode`, `ismap`, `islist`, `iskey`, `isempty`, `isfunc` |
| Get a type bitcode for a value             | `typify`                       |
| Get a human type name                      | `typename`                     |
| Sorted keys of a node                      | `keysof`                       |
| Iterate `[key, value]` pairs               | `items`                        |
| Deep copy                                  | `clone`                        |
| Deep merge a list of maps                  | `merge`                        |
| Walk a tree applying a function            | `walk`                         |
| Slice / pad / flatten / filter             | `slice`, `pad`, `flatten`, `filter` |
| Substitute references in a spec            | `inject`                       |
| Build an output by example                 | `transform`                    |
| Check a value against a shape              | `validate`                     |
| Pick records out of a node by query        | `select`                       |
| Build a JSON string                        | `jsonify`, `stringify`         |
| Escape for regex / URL                     | `escre`, `escurl`              |
| Join URL parts                             | `join`                         |


## Language-neutral API reference

This is the canonical API surface, defined in TypeScript at
[`ts/src/StructUtility.ts`](./ts/src/StructUtility.ts).  Every port
exposes equivalents.  The casing varies by language convention
(`getpath` in JS/Py/Lua/Rb/PHP; `GetPath` in Go/C#; `getPath` in
Java).

### Minor utilities (25)

```
typename(t)                            -> string
getdef(val, alt)                       -> any
isnode(val) / ismap(val) / islist(val) -> bool
iskey(key) / isempty(val) / isfunc(val)-> bool
size(val)                              -> int
slice(val, start?, end?, mutate?)      -> any
pad(str, width?, char?)                -> string
typify(val)                            -> int (bitfield)
getelem(list, key, alt?)               -> any
getprop(node, key, alt?)               -> any
strkey(key)                            -> string
keysof(node)                           -> string[]
haskey(node, key)                      -> bool
items(node)                            -> [key, val][]
flatten(list, depth?)                  -> list
filter(node, predicate)                -> list
escre(s) / escurl(s)                   -> string
join(arr, sep?, urlmode?)              -> string
jsonify(val, flags?)                   -> string
stringify(val, maxlen?)                -> string
pathify(val, from?, to?)               -> string
clone(val)                             -> any
delprop(parent, key)                   -> parent
setprop(parent, key, val)              -> parent
```

### Major utilities (8)

```
walk(node, apply, before?, after?, maxdepth?) -> node
merge(list, maxdepth?)                        -> any
setpath(store, path, val)                     -> store
getpath(path, store)                          -> any
inject(val, store, modify?)                   -> any
transform(data, spec, extra?, modify?)        -> any
validate(data, spec, extra?, collecterrs?)    -> any  (throws or collects on mismatch)
select(query, obj)                            -> match[]
```

### Builders (2)

```
jm(...)   // build a map (JSON object) from key/value args
jt(...)   // build a list (JSON tuple/array) from args
```

### Sentinels and constants

```
SKIP, DELETE                              // sentinel markers
T_any, T_noval, T_boolean, T_decimal,
T_integer, T_number, T_string, T_function,
T_symbol, T_null, T_list, T_map,
T_instance, T_scalar, T_node              // 15 type bit-flags
M_KEYPRE, M_KEYPOST, M_VAL                // walk/inject phase tags
MODENAME                                  // human name table for modes
```

### Transform commands (used inside spec strings)

```
$DELETE  $COPY  $KEY  $META  $ANNO
$MERGE   $EACH  $PACK  $REF   $FORMAT  $APPLY
```

### Validate checkers (used inside spec strings)

```
$MAP  $LIST  $STRING  $NUMBER  $INTEGER  $DECIMAL  $BOOLEAN
$NULL $NIL   $FUNCTION $INSTANCE $ANY $CHILD $ONE $EXACT
```


## Design notes

- **By-example over DSL.**  A transform/validate spec looks like the
  output it describes.  No second language to learn.
- **Tolerant of "absent".**  Functions return a defined alternative
  (`alt`) rather than throwing on missing keys.  Each language port
  handles its own undefined/null distinction; see per-language docs.
- **Lists are mutable and reference-stable.**  In languages where
  this is not native (Go, PHP), the port introduces a wrapper
  (`ListRef`).
- **JSON null is not undefined.**  Most JSON parsers conflate them;
  `struct` distinguishes them.  The shared test corpus uses the
  string `"__NULL__"` to stand in for JSON null where the test
  language can't represent it directly.
- **The TypeScript implementation is canonical.**  Disagreement
  between a port and the test corpus is a port bug.


## Repository layout

```
.
├── README.md         # this file
├── REPORT.md         # cross-language parity matrix
├── build/test/       # shared JSON test corpus (.jsonic)
├── ts/  js/  py/     # canonical + JS-family ports
├── go/  rb/  php/    # other complete ports
├── lua/ cs/ zig/
├── java/ cpp/        # partial ports
└── LICENSE
```

Each language directory contains:

- the implementation source,
- a test runner that consumes `build/test/*.jsonic`,
- a `Makefile` with at minimum a `make test` target,
- a `DOCS.md` with the per-language guide,
- `NOTES.md` and `REVIEW.md` with implementation history.


## License

MIT.  See [`LICENSE`](./LICENSE).
