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

| Function                            | Returns         | Description                                                                 |
|-------------------------------------|-----------------|-----------------------------------------------------------------------------|
| `typename(t)`                       | string          | Human name (`"string"`, `"map"`, ...) for a type bit-flag from `typify`.    |
| `getdef(val, alt)`                  | any             | Returns `val` unless it is undefined, in which case returns `alt`.          |
| `isnode(val)`                       | bool            | True if `val` is a node -- either a map or a list.                          |
| `ismap(val)`                        | bool            | True if `val` is a map (object with string keys).                           |
| `islist(val)`                       | bool            | True if `val` is a list (array with integer indices).                       |
| `iskey(key)`                        | bool            | True if `key` is a non-empty string or an integer index.                    |
| `isempty(val)`                      | bool            | True if `val` is undefined, `null`, an empty string, list, or map.          |
| `isfunc(val)`                       | bool            | True if `val` is a callable function.                                       |
| `size(val)`                         | int             | Length for lists/strings; key count for maps; integer part for numbers.     |
| `slice(val, start?, end?, mutate?)` | any             | Sub-section of a list, string, or bounded number; negative indices count from the end. |
| `pad(str, width?, char?)`           | string          | Pad `str` to `width` with `char`; negative width pads on the left.          |
| `typify(val)`                       | int (bitfield)  | Type bit-code (e.g. `T_scalar | T_string`) describing the value.            |
| `getelem(list, key, alt?)`          | any             | List lookup by integer key, with `-1` counting from the end; `alt` if absent. |
| `getprop(node, key, alt?)`          | any             | Safe property lookup on a map or list; returns `alt` if missing.            |
| `strkey(key)`                       | string          | Coerce a key to a canonical string form (`""` for invalid keys).            |
| `keysof(node)`                      | string[]        | Sorted list of a node's keys (string indices for lists).                    |
| `haskey(node, key)`                 | bool            | True if the key is present and its value is defined.                        |
| `items(node)`                       | `[key, val][]`  | Entries of a map or list as `[key, value]` pairs.                           |
| `flatten(list, depth?)`             | list            | Concatenate nested lists down to `depth` levels.                            |
| `filter(node, predicate)`           | list            | Keep entries for which `predicate([key, val])` is truthy.                   |
| `escre(s)`                          | string          | Escape regex metacharacters in a string.                                    |
| `escurl(s)`                         | string          | URL-encode a string.                                                        |
| `join(arr, sep?, urlmode?)`         | string          | Join string parts with `sep`; in URL mode, collapse repeated separators.    |
| `jsonify(val, flags?)`              | string          | Strict JSON serialisation of a value, optionally pretty-printed.            |
| `stringify(val, maxlen?)`           | string          | Compact, human-friendly string form of a value, truncated to `maxlen`.      |
| `pathify(val, from?, to?)`          | string          | Render a path (string or array) as a canonical dotted string.               |
| `clone(val)`                        | any             | Deep copy of a JSON-shaped value.                                           |
| `delprop(parent, key)`              | parent          | Remove a key from a map or list (returns the mutated parent).               |
| `setprop(parent, key, val)`         | parent          | Set a key on a map or list to `val` (returns the mutated parent).           |

### Major utilities (8)

| Function                                       | Returns         | Description                                                                 |
|------------------------------------------------|-----------------|-----------------------------------------------------------------------------|
| `walk(node, apply, before?, after?, maxdepth?)`| node            | Depth-first walk of a tree, calling `apply` (and optional `before`/`after`) at each node and leaf, with replacement. |
| `merge(list, maxdepth?)`                       | any             | Deep-merge a list of maps, last-wins for scalars; lists are merged by index.|
| `getpath(path, store)`                         | any             | Look up the value at a dotted path (or array path) inside `store`.          |
| `setpath(store, path, val)`                    | store           | Set `val` at a deep path inside `store`, creating missing parents.          |
| `inject(val, store, modify?)`                  | any             | Substitute `` `path` `` references inside `val` with values from `store`.   |
| `transform(data, spec, extra?, modify?)`       | any             | Build a result by example: `spec` mirrors output shape, with refs into `data`. |
| `validate(data, spec, extra?, collecterrs?)`   | any             | Check `data` against a by-example shape; returns `data` on success, throws or collects on mismatch. |
| `select(query, obj)`                           | match[]         | Pick records from a node whose fields match the query, with `$KEY` operators. |

### Builders (2)

| Function       | Returns | Description                                                  |
|----------------|---------|--------------------------------------------------------------|
| `jm(...args)`  | map     | Build a map (JSON object) from alternating key/value pairs.  |
| `jt(...args)`  | list    | Build a list (JSON array/tuple) from positional args.        |

### Injection helpers (3)

These are exposed for callers that write custom injectors or modify
hooks; most users will not need them directly.

| Function                                    | Description                                                                |
|---------------------------------------------|----------------------------------------------------------------------------|
| `checkPlacement(inj, parent, ...)`          | Validate where an injection result may be placed (root vs branch vs leaf). |
| `injectorArgs(inj, store)`                  | Extract the argument list passed to a transform-command injector.          |
| `injectChild(inj, store, key)`              | Recurse `inject` into a child of the current node, sharing the state.      |

### Sentinels

| Symbol     | Description                                                                                |
|------------|--------------------------------------------------------------------------------------------|
| `SKIP`     | Returned from a transform/inject step to omit the current key from the output.             |
| `DELETE`   | Returned from a transform/inject step to delete the current key from the parent.           |

### Type bit-flags (15)

Returned by `typify(val)` and named by `typename(t)`.  Combine with
bitwise operators to test composite types (e.g. `T_node | T_map`).

| Constant      | Description                                                  |
|---------------|--------------------------------------------------------------|
| `T_any`       | Wildcard / "no constraint" type.                             |
| `T_noval`     | Property absent / undefined; **not** a scalar.               |
| `T_boolean`   | Boolean scalar.                                              |
| `T_decimal`   | Non-integer numeric scalar.                                  |
| `T_integer`   | Integer numeric scalar.                                      |
| `T_number`    | Any numeric scalar (set together with `T_integer`/`T_decimal`). |
| `T_string`    | String scalar.                                               |
| `T_function`  | Callable function value.                                     |
| `T_symbol`    | Symbolic atom (for languages that have them).                |
| `T_null`      | The actual JSON null value (distinct from absent).           |
| `T_list`      | List node (array).                                           |
| `T_map`       | Map node (object).                                           |
| `T_instance`  | Class instance (non-plain object).                           |
| `T_scalar`    | Set on every scalar type, alongside its specific flag.       |
| `T_node`      | Set on every node type (`T_list`, `T_map`, `T_instance`).    |

### Walk / inject mode flags

| Constant      | Description                                                  |
|---------------|--------------------------------------------------------------|
| `M_KEYPRE`    | Phase tag: about to descend into a child by key.             |
| `M_KEYPOST`   | Phase tag: returned from descending into a child by key.     |
| `M_VAL`       | Phase tag: visiting the value of a leaf.                     |
| `MODENAME`    | Lookup table mapping mode flags to human-readable names.     |

### Transform commands (used inside spec strings)

Quote the command in backticks inside a `transform` spec, e.g. `` `$COPY` ``.

| Command    | Description                                                                |
|------------|----------------------------------------------------------------------------|
| `$DELETE`  | Remove the current key from the output.                                    |
| `$COPY`    | Copy the matching value from `data` at the current path.                   |
| `$KEY`     | Insert the current key under another name in the output.                   |
| `$META`    | Attach or read metadata about the current path.                            |
| `$ANNO`    | Annotate the current node with extra fields from the spec.                 |
| `$MERGE`   | Deep-merge several sub-specs into the current node.                        |
| `$EACH`    | Apply a sub-spec to every entry of a list or map.                          |
| `$PACK`    | Repack a node by rewriting its keys / shape.                               |
| `$REF`     | Resolve a named reference inside the spec.                                 |
| `$FORMAT`  | Render a templated string using values from `data`.                        |
| `$APPLY`   | Call a function (from `extra`) on the current value and substitute result. |

### Validate checkers (used inside spec strings)

Quote the checker in backticks inside a `validate` spec, e.g. `` `$STRING` ``.

| Checker     | Description                                                              |
|-------------|--------------------------------------------------------------------------|
| `$MAP`      | The value must be a map.                                                 |
| `$LIST`     | The value must be a list.                                                |
| `$STRING`   | The value must be a string.                                              |
| `$NUMBER`   | The value must be a number (integer or decimal).                         |
| `$INTEGER`  | The value must be an integer.                                            |
| `$DECIMAL`  | The value must be a non-integer number.                                  |
| `$BOOLEAN`  | The value must be a boolean.                                             |
| `$NULL`     | The value must be JSON null.                                             |
| `$NIL`      | The value must be absent or null (lenient null check).                   |
| `$FUNCTION` | The value must be a callable function.                                   |
| `$INSTANCE` | The value must be a class instance (non-plain object).                   |
| `$ANY`      | The value matches anything (placeholder for "no constraint").            |
| `$CHILD`    | Apply a sub-spec to every direct child of the current node.              |
| `$ONE`      | The value must match exactly one of a list of alternative sub-specs.     |
| `$EXACT`    | The value must equal a literal value exactly (no shape coercion).        |


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
