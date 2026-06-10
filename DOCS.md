# Voxgig Struct — Comprehensive Guide

> Uniform JSON-shaped data structure manipulation, defined once and ported
> to every language.

This is the in-depth, language-neutral companion to the
[`README.md`](./README.md) overview. It has four parts, each with a
different job:

- **[Tutorial](#1-tutorial-a-guided-tour)** — start here if you are new.
  A hands-on tour that builds up the whole API step by step.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks you
  already know you need.
- **[Reference](#3-reference)** — the complete API, function by function,
  with exact semantics and edge cases.
- **[Explanation](#4-explanation)** — the ideas behind the design: why it
  works the way it does, and the concepts (null-vs-absent, by-example
  specs, the test corpus) that make the rest make sense.

Examples use the canonical JavaScript/TypeScript form. Every call has an
equivalent in every port — see your language's `DOCS.md` (e.g.
[`python/DOCS.md`](./python/DOCS.md), [`go/DOCS.md`](./go/DOCS.md)) for the
exact local spelling, and [`README.md`](./README.md#per-language-documentation)
for the full list.

---

## 1. Tutorial: a guided tour

You will read deep values, set them, merge maps, transform one shape into
another, validate data, and walk a tree — the whole core API — in one
sitting. Run the snippets in a Node REPL after `npm install` in
[`typescript/`](./typescript/), or translate them to your language as you go.

```js
const S = require('@voxgig/struct')
```

### Step 1 — Reach into nested data

The most common need is "give me the value at this path". `getpath` takes a
store and a dotted path:

```js
const store = { db: { host: 'localhost', port: 5432, replicas: ['r1', 'r2'] } }

S.getpath(store, 'db.host')        // 'localhost'
S.getpath(store, 'db.replicas.1')  // 'r2'   — integer steps index into lists
S.getpath(store, 'db.timeout')     // undefined — missing is not an error
```

Paths can also be arrays (`['db', 'host']`), which is handy when a key
itself contains a dot. Nothing throws on a missing key; you get `undefined`.

If you want a fallback instead of `undefined`, reach for `getprop` (single
key) or `getdef` (any value):

```js
S.getprop(store.db, 'timeout', 30) // 30 — the default, because the key is absent
S.getdef(undefined, 'fallback')    // 'fallback'
```

### Step 2 — Build paths that don't exist yet

`setpath` is the mirror of `getpath`. It creates intermediate maps as
needed and returns the (mutated) store:

```js
const cfg = {}
S.setpath(cfg, 'service.db.host', 'db.internal')
// cfg is now { service: { db: { host: 'db.internal' } } }
```

### Step 3 — Merge a chain of maps

Configuration usually comes in layers: defaults, then environment, then
overrides. `merge` folds a list left-to-right — later entries win for
scalars, maps deep-merge, lists merge by index:

```js
S.merge([
  { a: 1, b: 2, x: { y: 5, z: 6 } }, // defaults
  { b: 3,       x: { y: 7 }       }, // override
])
// { a: 1, b: 3, x: { y: 7, z: 6 } }
```

Note `x.z` survived (deep merge), `b` was overwritten (last wins), and
`x.y` was overwritten inside the nested map.

### Step 4 — Reshape data by example

`transform` builds a new structure from a *spec that looks like the output
you want*. Backtick-quoted strings are references into the source data:

```js
S.transform(
  { user: { first: 'Ada', last: 'Lovelace' }, age: 36 }, // data
  { name: '`user.first`', surname: '`user.last`', years: '`age`' } // spec
)
// { name: 'Ada', surname: 'Lovelace', years: 36 }
```

The spec's shape *is* the output shape. A reference can be embedded in a
larger string, and multiple references concatenate:

```js
S.transform({ a: 3, b: 4 }, { label: 'X`a`Y`b`Z' })
// { label: 'X3Y4Z' }
```

### Step 5 — Validate data by example

`validate` uses the same by-example idea, but the leaves are *type
checkers* rather than references. It returns the data on success and throws
on mismatch:

```js
S.validate({ name: 'Ada', age: 36 }, { name: '`$STRING`', age: '`$INTEGER`' })
// { name: 'Ada', age: 36 }   — ok

S.validate({ name: 'Ada', age: 'old' }, { name: '`$STRING`', age: '`$INTEGER`' })
// throws: age expected integer
```

### Step 6 — Walk the whole tree

`walk` visits every node and leaf depth-first. Pass a function as the
*after* callback to replace values as you ascend:

```js
// Replace every null with a default.
S.walk(tree, undefined, (key, val, parent, path) => (val === null ? 'DEFAULT' : val))
```

The callback receives the current key, value, parent node, and the path
(array of keys) to that value — enough to make context-sensitive decisions.

### Step 7 — Select records by query

`select` filters the children of a node, returning the matches annotated
with their key under `$KEY`:

```js
S.select(
  { a: { name: 'Alice', age: 30 }, b: { name: 'Bob', age: 25 } },
  { age: 30 }
)
// [ { name: 'Alice', age: 30, $KEY: 'a' } ]
```

That is the whole core. From here, the **How-to guides** show task-shaped
combinations, the **Reference** gives exact semantics, and the
**Explanation** covers the model underneath.

---

## 2. How-to guides

### Read a deep value, with a default
```js
S.getpath(store, 'a.b.c')          // undefined if missing
S.getprop(node, 'c', fallback)     // fallback if the single key is missing
S.getdef(maybeUndefined, fallback) // fallback only when the value is undefined
```
Use an **array path** when a key contains a dot: `S.getpath(store, ['a.b', 'c'])`.

### Set a deep value, creating parents
```js
S.setpath(store, 'a.b.c', 42)      // creates a, a.b as maps if absent
S.setpath(store, ['list', 2], 'x') // grows a list, padding with holes
```

### Layer configuration
```js
const config = S.merge([defaults, fileConfig, envConfig, cliOverrides])
```
Earlier entries are the base; later entries win. Maps deep-merge; lists
merge index-by-index; scalars replace.

### Rename / project fields
```js
S.transform(record, { id: '`userId`', label: '`profile.displayName`' })
```

### Copy a subtree verbatim
```js
S.transform({ a: { b: { c: 1 } } }, { a: '`$COPY`' })
// { a: { b: { c: 1 } } }   — $COPY pulls the same path from data
```

### Use the current key as a value
```js
S.transform(
  { items: { x: { v: 1 }, y: { v: 2 } } },
  { out: ['`$EACH`', 'items', { id: '`$KEY`', value: '`.v`' }] }
)
// { out: [ { id: 'x', value: 1 }, { id: 'y', value: 2 } ] }
```
`$EACH` is a **list directive**: it must be the first element of a list
value, followed by the source path and a per-entry sub-spec. It applies the
sub-spec to every child of the source; `$KEY` is that child's key and a
leading-dot reference (`` `.v` ``) reads from inside that child.

### Deep-merge sub-specs into a node
```js
S.transform({ a: { b: 3 } }, { a: { '`$MERGE`': '`a`', c: 3 } })
// { a: { b: 3, c: 3 } }
```

### Reformat a value with a named formatter
```js
S.transform({ first: 'Ada', last: 'Lovelace' },
            { name: ['`$FORMAT`', 'upper', '`first`'] })
// { name: 'ADA' }
```
`$FORMAT` is a **list directive** — `['`$FORMAT`', <formatter>, <valueSpec>]`
— that runs a *registered, named* formatter over the resolved value spec.
Built-in formatters include `upper`, `lower`, `string`, `number`, `integer`
and `concat` (which joins a list of scalars):
```js
S.transform({ first: 'Ada', last: 'Lovelace' },
            { name: ['`$FORMAT`', 'concat', ['`first`', ' ', '`last`']] })
// { name: 'Ada Lovelace' }
```
There is no brace-template form; `{first}` text is passed through verbatim.

### Run your own function during a transform
```js
S.transform(data, { total: { '`$APPLY`': 'sum' } }, { extra: { sum: (k, v, parent) => /* … */ } })
```
Register the function in `extra`; reference it by name with `$APPLY`. (The
exact callback signature varies slightly by port — see
[`NOTES.md`](design/NOTES.md).)

### Validate incoming data, throwing on mismatch
```js
S.validate(payload, { id: '`$INTEGER`', tags: ['`$STRING`'] })
```
A one-element list spec (`['`$STRING`']`) means "a list whose every element
matches".

### Validate and collect *all* errors instead of throwing
```js
const errs = []
S.validate(payload, spec, { errs })
if (errs.length) { /* report them */ }
```

### Validate "one of several shapes"
```js
S.validate(value, ['`$ONE`', '`$STRING`', '`$NUMBER`'])
// passes if value is a string OR a number; throws otherwise
```
`$ONE` is a **flat list directive**: the first element is the directive and
each remaining element is an alternative spec — not a map key over a list.

### Require an exact literal (no type coercion)
```js
S.validate(value, ['`$EXACT`', 9]) // value must equal 9
```

### Replace every null/empty in a tree
```js
S.walk(tree, undefined, (k, v) => (S.isempty(v) ? '∅' : v))
```

### Substitute references into a template (no reshaping)
```js
S.inject({ greeting: 'hello `name`' }, { name: 'Ada' })
// { greeting: 'hello Ada' }
```
`inject` is the substitution engine that `transform` is built on; use it
directly when your spec *is* the output shape and you only need reference
expansion.

### Pick records out of a collection
```js
S.select(users, { role: 'admin' })        // matching maps, each tagged $KEY
S.select(list,  {})                        // all children (empty query matches all)
```

### Build a JSON string deterministically
```js
S.jsonify(value)               // pretty, 2-space indent (the default)
S.jsonify(value, { indent: 0 })// compact, insertion-ordered keys
S.jsonify(value, { indent: 4 })// pretty, 4-space indent
S.stringify(value, 40)         // compact human form, truncated to 40 chars (for logs)
```
The second argument is an options object `{ indent, offset }`; a bare
number is ignored, so `jsonify(value, 2)` is still the default pretty form.

### Test a value's shape
```js
S.isnode(v) S.ismap(v) S.islist(v) S.iskey(k) S.isempty(v) S.isfunc(v)
S.typify(v)            // bit-code, e.g. T_scalar | T_string
S.typename(S.typify(v))// 'string'
```

---

## 3. Reference

The canonical signatures live in
[`typescript/src/StructUtility.ts`](./typescript/src/StructUtility.ts); the
parity tool treats its `export { … }` block as the definitive public API
(48 names). Function names are shown in canonical casing; substitute your
port's convention (`GetPath`, `get_path`, `voxgig_getpath`, …).

### Predicates and type inspection

| Function | Returns | Semantics |
|---|---|---|
| `isnode(val)` | bool | `val` is a map **or** a list. |
| `ismap(val)` | bool | `val` is a map (string-keyed object). |
| `islist(val)` | bool | `val` is a list (integer-indexed array). |
| `iskey(key)` | bool | `key` is a non-empty string or an integer. |
| `isempty(val)` | bool | `val` is undefined, null, `''`, `[]`, or `{}`. |
| `isfunc(val)` | bool | `val` is callable. |
| `typify(val)` | int | Bit-field of type flags (see [type flags](#type-flags)). |
| `typename(t)` | string | Human name for a `typify` bit-code (`"string"`, `"map"`, …). |

`isempty`, `isnode` (and the property readers below) are **Group A**: a
stored `null` counts as "no value". See [Explanation](#null-versus-absent-group-ab).

### Property access

| Function | Returns | Semantics |
|---|---|---|
| `getprop(node, key, alt?)` | any | Value at `key`; `alt` (default undefined) if missing. **Group A**. |
| `getelem(list, key, alt?)` | any | List element by index; `-1` counts from the end; `alt` if absent (a callable `alt` is invoked). **Group A**. |
| `getdef(val, alt)` | any | `val` unless it is undefined, else `alt`. |
| `haskey(node, key)` | bool | Key present *and* its value defined. **Group A**. |
| `setprop(parent, key, val)` | parent | Set `key` to `val`; returns the mutated parent. **Group B** (stores null). |
| `delprop(parent, key)` | parent | Remove `key`; returns the mutated parent. |
| `keysof(node)` | string[] | Sorted keys (string indices for lists). |
| `items(node)` | `[key,val][]` | Entries as pairs. |
| `strkey(key)` | string | Canonical string form of a key (`''` for invalid keys). |

### Path operations

| Function | Returns | Semantics |
|---|---|---|
| `getpath(store, path, injdef?)` | any | Value at a dotted or array `path`; undefined if any step is missing. A trailing `.` ascends to an ancestor data parent (used inside transforms). |
| `setpath(store, path, val)` | store | Set `val` at a deep path, creating missing maps/lists. |
| `pathify(val, from?, to?)` | string | Render a path (string or array) as a canonical dotted string. |

### Tree operations

| Function | Returns | Semantics |
|---|---|---|
| `walk(val, before?, after?, maxdepth?)` | node | Depth-first walk. `before(key,val,parent,path)` runs on descent, `after` on ascent; each may return a replacement value. |
| `merge(list, maxdepth?)` | any | Deep-merge a list of maps. Last wins for scalars; maps deep-merge; lists merge by index. |
| `clone(val)` | any | Deep copy of a JSON-shaped value. **Group B** (preserves null). |
| `flatten(list, depth?)` | list | Concatenate nested lists down to `depth` levels. |
| `filter(node, predicate)` | list | Keep `[key,val]` entries where `predicate` is truthy. |
| `size(val)` | int | List/string length; map key count; integer part of a number. |
| `slice(val, start?, end?, mutate?)` | any | Sub-section of a list/string/bounded number; negative indices from the end. |
| `pad(str, width?, char?)` | string | Pad to `width` with `char`; negative `width` pads on the left. |

### Composition: inject, transform, validate, select

| Function | Returns | Semantics |
|---|---|---|
| `inject(val, store, modify?)` | any | Replace backtick references inside `val` with values from `store`. The engine under `transform`. |
| `transform(data, spec, extra?, modify?)` | any | Build output from a by-example `spec`; references and `$`-commands pull from `data`. `extra` supplies `$APPLY` functions and `errs`. |
| `validate(data, spec, extra?, collecterrs?)` | any | Check `data` against a by-example `spec` of `$`-checkers. Returns `data`; throws unless an `errs` collector is supplied. |
| `select(children, query)` | match[] | Children whose fields match `query`, each tagged with its `$KEY`. Empty query matches all; non-node input yields `[]`. |

### Strings, URLs, JSON

| Function | Returns | Semantics |
|---|---|---|
| `escre(s)` | string | Escape regex metacharacters. |
| `escurl(s)` | string | URL-encode. |
| `join(arr, sep?, urlmode?)` | string | Join parts with `sep`; URL mode collapses repeated separators. |
| `jsonify(val, flags?)` | string | Strict JSON; `flags` is an options object `{ indent, offset }` (`indent` defaults to 2; `{ indent: 0 }` is compact). Insertion-ordered keys; `%g`-style doubles. |
| `stringify(val, maxlen?)` | string | Compact, human-friendly form for logs, truncated to `maxlen`. |

### Builders and injection helpers

| Function | Returns | Semantics |
|---|---|---|
| `jm(...kv)` | map | Build a map from alternating key/value args. |
| `jt(...vals)` | list | Build a list from positional args. |
| `checkPlacement(inj, parent, …)` | bool | Validate where an injection result may be placed. |
| `injectorArgs(inj, store)` | any | Extract the argument list for a transform-command injector. |
| `injectChild(inj, store, key)` | — | Recurse `inject` into a child, sharing state. |

### Sentinels

| Symbol | Meaning |
|---|---|
| `SKIP` | Omit the current key from the output. |
| `DELETE` | Remove the current key from the parent. |

### Type flags

`typify` returns a bitwise-OR of these; `typename` names the dominant one.

`T_any`, `T_noval`, `T_boolean`, `T_decimal`, `T_integer`, `T_number`,
`T_string`, `T_function`, `T_symbol`, `T_null`, `T_list`, `T_map`,
`T_instance`, `T_scalar` (set on every scalar), `T_node` (set on every
node). `T_symbol`/`T_instance` are only ever produced on JS/TS — see
[`NOTES.md`](design/NOTES.md).

### Walk / inject phase flags

`M_KEYPRE` (about to descend by key), `M_KEYPOST` (returned from
descending), `M_VAL` (visiting a leaf value); `MODENAME` maps them to names.

### Transform commands (inside backticks in a `transform` spec)

`$COPY` (copy the data value at this path), `$KEY` (the current key),
`$DELETE`, `$META`, `$ANNO`, `$MERGE` (deep-merge sub-specs), `$EACH`
(apply a sub-spec to every entry of a list/map), `$PACK` (repack keys/shape),
`$REF` (named reference), `$FORMAT` (template a string), `$APPLY` (call a
named function from `extra`).

### Validate checkers (inside backticks in a `validate` spec)

`$MAP`, `$LIST`, `$STRING`, `$NUMBER`, `$INTEGER`, `$DECIMAL`, `$BOOLEAN`,
`$NULL`, `$NIL` (absent or null), `$FUNCTION`, `$INSTANCE`, `$ANY`,
`$CHILD` (apply a sub-spec to every child), `$ONE` (match exactly one
alternative), `$EXACT` (equal a literal exactly).

### Regex API

A uniform six-function regex layer wraps each host engine so call sites
read the same everywhere: `re_compile`, `re_test`, `re_find`,
`re_find_all`, `re_replace`, `re_escape`. Patterns must stay inside the
**RE2 subset**. Full spec: [`REGEX_API.md`](design/REGEX_API.md),
[`REGEX.md`](design/REGEX.md); cross-engine edge cases:
[`REGEX_PATHOLOGICAL.md`](design/REGEX_PATHOLOGICAL.md).

---

## 4. Explanation

### One API, one source of truth, many ports

A Voxgig SDK exists in many languages, and each needs the same data
operations. Re-implementing them per language drifts — edge cases get
fixed in one place and not another until "the same call" quietly means
different things. `struct` removes that drift by construction: there is
**one** definition (the canonical TypeScript), and every other language is
a *port* held to it. The payoff is that `getpath(store, 'a.b.c')` is the
same answer in fifteen languages, forever.

### By-example over a DSL

`transform` and `validate` are driven by *specs that look like the data
they describe*. A transform spec for `{ name, age }` is itself a map with
keys `name` and `age`; a validate spec is the same shape with type checkers
at the leaves. There is no second mini-language to learn — you write the
shape you want and annotate the leaves. Backtick references (`` `a.b` ``)
and `$`-commands (`` `$COPY` ``, `` `$EACH` ``) are the only special
syntax, and they live *inside* the by-example structure.

### The test corpus is the contract

Behaviour is not pinned by prose; it is pinned by data. The
[`build/test/*.jsonic`](./build/test/) files are a language-independent
list of `{ in, out }` cases that every port runs through an identical
runner. "Correct" means "matches the corpus." This is what lets fifteen
independent implementations stay genuinely identical: there is an
executable oracle, and CI runs it everywhere. When you change canonical
behaviour you change the corpus *and* the canonical TS together, then make
every port pass again.

### Null versus absent ("Group A/B")

Most JSON tooling treats `null` and "missing" as the same thing. `struct`
deliberately distinguishes them, because configuration and validation care
about the difference ("the user set this to null" ≠ "the user didn't set
it"). The rule (full text in [`UNDEF_SPEC.md`](design/UNDEF_SPEC.md)):

- **Group A — readers** (`getprop`, `getelem`, `haskey`, `isempty`,
  `isnode`): a stored `null` is treated as *no value*; you get the `alt`
  or `false`.
- **Group B — value processors** (`setprop`, `delprop`, `clone`,
  `stringify`, `jsonify`, `pad`, `typify`, `walk`, `merge`, `inject`,
  `transform`, `validate`, `select`): `null` is preserved *literally*.

Because some host languages can't represent "absent" distinctly, the
corpus uses the string `"__NULL__"` for a real null and `"__UNDEF__"` /
`"__EXISTS__"` markers in `match` assertions. This is the single most
common source of port bugs; when a read/merge/clone test fails, check the
Group A/B handling first.

### Ordered maps

JavaScript objects iterate in insertion order, and the canonical
`jsonify` depends on that. Ports whose stdlib lacks an insertion-ordered
map (C, C++, Zig, Rust, Perl, Swift) ship a small in-tree ordered map
(`OrderedMap`, `OrderedHash`, `OrderedDictionary`, …). Never substitute an
unordered map; key order is observable through `keysof`, `items`, and
`jsonify`.

### Sentinels: SKIP and DELETE

Some transform/inject steps need to say "emit nothing here" or "remove this
key" — neither of which has an in-band JSON value. `SKIP` and `DELETE` are
out-of-band marker values for exactly that. A custom injector or `$APPLY`
function returns them to omit or delete the current key.

### Zero runtime dependencies

Every port's *library proper* uses only its host standard library (plus a
small in-tree helper or two: an ordered map, a JSON printer, sometimes a
regex engine). Test harnesses may pull in a JSON/test library, but the
shipped library never does. This keeps `struct` safe to embed inside an SDK
without dragging a dependency tree along, and it is enforced — see
[`REPORT.md`](design/REPORT.md) and `make audit`.

### The regex subset

Internal code uses a six-function regex layer, and all patterns stay inside
the **RE2 subset** (no backreferences, no lookaround). This is what lets
backtracking-engine ports (JS, Python, PHP, Perl, Ruby) and linear-time
RE2/NFA ports (Go, Rust, C, C++, Zig, Lua) agree. A handful of pathological
inputs still differ between engine families (notably zero-width
`re_replace` and catastrophic backtracking); those differences are
documented, not "fixed", in [`REGEX_PATHOLOGICAL.md`](design/REGEX_PATHOLOGICAL.md).

### Where everything is written down

| Topic | File |
|---|---|
| Overview + at-a-glance reference | [`README.md`](./README.md) |
| This guide | `DOCS.md` |
| Working in the repo (for agents) | [`AGENTS.md`](./AGENTS.md) |
| Per-port parity matrix | [`REPORT.md`](design/REPORT.md) |
| Cross-cutting quirks | [`NOTES.md`](design/NOTES.md) |
| Absent-vs-null spec | [`UNDEF.md`](design/UNDEF.md), [`UNDEF_SPEC.md`](design/UNDEF_SPEC.md) |
| Regex dialect + API | [`REGEX.md`](design/REGEX.md), [`REGEX_API.md`](design/REGEX_API.md), [`REGEX_PATHOLOGICAL.md`](design/REGEX_PATHOLOGICAL.md) |
| Per-port specifics | `<lang>/DOCS.md`, `<lang>/README.md`, `<lang>/AGENTS.md` |
</content>
