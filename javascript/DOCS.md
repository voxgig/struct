# Struct for JavaScript — Comprehensive Guide

> A faithful **port** of the canonical TypeScript implementation. Behaviour
> is defined by [`../typescript/`](../typescript/) and pinned by the shared
> corpus; this port reproduces it in plain CommonJS. This guide is the
> in-depth companion to [`README.md`](./README.md) (the quick-start +
> signature reference) and the language-neutral [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — install and learn the whole API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the exact
  JavaScript semantics.
- **[Explanation](#4-explanation--port-specifics)** — the model, the port's
  role, and JavaScript-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Install

The library is a single CommonJS module: [`src/struct.js`](./src/struct.js),
with zero runtime dependencies. The published package name is in
[`package.json`](./package.json); inside the monorepo, require the source
directly:

```js
const { getpath } = require('@voxgig/structjs')
// or, from a clone:
const { getpath } = require('./javascript/src/struct.js')
```

Working from a clone (you'll do this to run the suite or experiment):

```bash
cd javascript
npm install
npm test           # node --test — no build step
```

### Your first program

```js
const { getpath, merge } = require('@voxgig/structjs')

const config = merge([
  { db: { host: 'localhost', port: 5432 }, debug: false }, // defaults
  { db: { host: 'db.internal' }, debug: true }, // overrides
])

getpath(config, 'db.host') // 'db.internal'
getpath(config, 'db.port') // 5432  (survived the deep merge)
```

### Build up the rest of the API

Each call below has the same meaning in every port; only the syntax
changes. Read [`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the
full language-neutral walkthrough; the JavaScript-flavoured version:

```js
const S = require('@voxgig/structjs')

// Reshape by example — the spec mirrors the output you want.
S.transform(
  { user: { first: 'Ada', last: 'Lovelace' }, age: 36 },
  { name: '`user.first`', surname: '`user.last`', years: '`age`' }
)
// { name: 'Ada', surname: 'Lovelace', years: 36 }

// Validate by example — leaves are type checkers; throws on mismatch.
S.validate({ name: 'Ada', age: 36 }, { name: '`$STRING`', age: '`$INTEGER`' })

// Walk the tree — replace values on ascent.
S.walk(tree, undefined, (key, val) => (val === null ? 'DEFAULT' : val))

// Select children by query — each match tagged with its $KEY.
S.select({ a: { age: 30 }, b: { age: 25 } }, { age: 30 })
// [ { age: 30, $KEY: 'a' } ]
```

---

## 2. How-to guides

### Inject the API as an object (for stubbing in tests)

```js
const { StructUtility } = require('@voxgig/structjs')
const su = new StructUtility()
su.getpath({ a: { b: 1 } }, 'a.b') // 1
```

Every function and constant is also an instance member of `StructUtility`,
which is convenient when a consumer wants to swap the implementation (the
test SDK in [`test/sdk.js`](./test/sdk.js) does exactly this).

### Collect all validation errors instead of throwing

```js
const errs = []
validate(payload, spec, { errs })
if (errs.length) console.error(errs)
```

### Write a custom transform function (`$APPLY`)

`$APPLY` must sit in **value** position as a three-element list
`['`$APPLY`', fn, child]`: the second element must resolve to a function,
and the third is the child spec passed to it (here a `'`items`'` path that
copies the source array). The function receives `(resolvedChild, store, inj)`
and its return value replaces the slot:

```js
const sum = (val) => val.reduce((a, b) => a + b, 0)

transform(
  { items: [1, 2, 3] },
  { total: ['`$APPLY`', sum, '`items`'] }
)
// { total: 6 }
```

Putting `$APPLY` in key position (`{ '`$APPLY`': 'sum' }`) or directly under
a map (`{ x: '`$APPLY`' }`) is an error — it must be a list value, and the
function has to be an actual function value, not a name looked up elsewhere.

### Keep a `walk` path past the callback

```js
const seen = []
walk(tree, (key, val, parent, path) => {
  seen.push(path.slice()) // the path array is reused — clone to retain it
  return val
})
```

### Serialise deterministically

`jsonify` pretty-prints by default (indent 2); pass `{ indent: 0 }` for compact.
`stringify` is the quote-light human form (keys sorted), for logs.

<!-- example: minor/jsonify#brace -->
```js
jsonify({ a: 1, b: [2, 3] })
// {
//   "a": 1,
//   "b": [
//     2,
//     3
//   ]
// }
```
<!-- => "{\n  \"a\": 1,\n  \"b\": [\n    2,\n    3\n  ]\n}" -->

<!-- example: minor/stringify#brace -->
```js
stringify({ a: 1, b: [2, 3] })   // '{a:1,b:[2,3]}'
```
<!-- => "{a:1,b:[2,3]}" -->

For more task recipes (merge configs, rename fields, `$EACH`, `$MERGE`,
`$FORMAT`, `$ONE`, `$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical;
only the host literals differ.

---

## 3. Reference

The full JavaScript signatures, with examples for every function, are in
[`README.md` → Function reference](./README.md#function-reference). The
public surface is the `module.exports = { … }` block at the bottom of
[`src/struct.js`](./src/struct.js); `../tools/check_parity.py` checks it
against the canonical export list.

JavaScript-specific points the signatures don't show:

- **Untyped, JSON-shaped values.** Inputs and outputs are plain JSON
  (`null`, booleans, numbers, strings, arrays, objects). `isnode` / `ismap`
  / `islist` are runtime predicates; there are no compile-time guards (this
  is plain JS, not the canonical TS).
- **`getprop` vs `getelem`.** `getprop` works on maps and lists; `getelem`
  is list-specific, supports `-1`-from-the-end indexing, and *invokes* a
  callable `alt` when the element is absent (`getprop`/`getdef` do not).
- **`items` is overloaded** — `items(node)` returns `[key, val][]`;
  `items(node, fn)` maps each pair through `fn`.
- **`walk` extra parameters** (`key`, `parent`, `path`) are recursion
  state; callers pass only `(val, before?, after?, maxdepth?)`.
- **Type flags** combine bitwise: `typify('hi')` is `T_scalar | T_string`;
  test with `0 < (T_string & t)`. `typify(undefined)` is `T_noval` (not a
  scalar); `typify(null)` is `T_scalar | T_null`.

---

## 4. Explanation & port specifics

### A faithful port, not the source of truth

The canonical implementation is the TypeScript port; this JavaScript port
reproduces it. The shared corpus in [`../build/test/`](../build/test/) is
generated to match the canonical code, and this port is held to it.
Practically:

- A behaviour question is answered by reading the canonical TS
  ([`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts)),
  not by reading this port in isolation.
- A change to canonical behaviour starts in TypeScript, then flows to the
  corpus and out to every port including this one (see
  [`../AGENTS.md`](../AGENTS.md#standard-workflows)).

Because both ports run on V8, runtime semantics are effectively identical;
the difference is types, not behaviour.

### `null` versus `undefined`

JavaScript has both, and `struct` keeps them distinct — the
[Group A/B rule](../DOCS.md#null-versus-absent-group-ab) in language-neutral
form:

- `undefined` = **absent**. `getprop` on a missing key returns `undefined`;
  Group A readers (`getprop`, `getelem`, `haskey`, `isempty`, `isnode`)
  treat a stored `null` as absent too.
- `null` = the JSON null scalar; `typify(null)` is `T_scalar | T_null`, and
  Group B processors (`clone`, `merge`, `walk`, `setprop`, …) preserve it
  literally.

If your JSON source returns `null` for "not set", decide which you mean —
convert to `undefined`, or use the corpus `'__NULL__'` marker — before
handing the value to `struct`.

### Lists are reference-stable

`walk`, `merge`, `inject`, and `setpath` rely on JavaScript arrays being
mutable and shared by reference — a mutation through one handle is visible
to all. Ports in languages without that property (Go, PHP) introduce a
`ListRef` wrapper to reproduce it; JavaScript needs none.

### Regex

The host engine is ECMAScript `RegExp`, wrapped by the uniform six-function
API (`re_compile` / `re_test` / `re_find` / `re_find_all` / `re_replace` /
`re_escape`) — all six are exported from [`src/struct.js`](./src/struct.js).
Stay inside the **RE2 subset**: `RegExp` *allows* backreferences and
lookaround, but those don't port. Two sharp edges to know about:

- **Catastrophic backtracking.** `RegExp` is a backtracking engine; nested
  quantifiers like `(a+)+` against a non-matching suffix can be exponential
  in input length. Prefer flat patterns and character classes.
- **Zero-width `re_replace`.** `re_replace("a*", "abc", "X")` returns
  `"XXbXcX"` (the ECMA convention); RE2 ports like Go return `"XbXcX"`.

Both are detailed in [`README.md` → Regex](./README.md#regex) and
[`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md).

---

## Build, test, and extend

```bash
cd javascript
npm install
npm test             # node --test (the shared corpus suite); no build step
npm run lint         # ESLint 10 (flat config)
npm run format:check # Prettier check
```

`make test` / `make lint` from this dir wrap the same commands (`make lint`
runs both ESLint and the Prettier check); `make audit` runs `npm audit`.
There is **no build step** — `make build` is a no-op, and `npm test` runs
the source directly under `node --test`.

Tests live in [`test/`](./test/); the runner
([`test/runner.js`](./test/runner.js)) loads the shared corpus from
[`../build/test/`](../build/test/), mirroring the canonical TS runner.

**This port follows; it does not lead.** To change canonical behaviour,
edit the canonical TS and corpus first (the checklist is in
[`../AGENTS.md`](../AGENTS.md)), then update this port to match,
`npm test` until green, and re-run `python3 ../tools/check_parity.py`.
Tooling: Node.js, ESLint 10, Prettier 3.
