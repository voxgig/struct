# Struct for TypeScript — Comprehensive Guide

> The **canonical** port. Behaviour defined here is the behaviour every
> other language must match. This guide is the in-depth companion to
> [`README.md`](./README.md) (the quick-start + signature reference) and the
> language-neutral [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — install and learn the whole API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the exact
  TypeScript semantics and types.
- **[Explanation](#4-explanation--port-specifics)** — the model, the
  canonical role, and TypeScript-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Install

```bash
npm install @voxgig/struct
```

Package `@voxgig/struct`; entry `dist/StructUtility.js`; types
`dist/StructUtility.d.ts`; CommonJS module.

Working from a clone instead (you'll do this to extend the canonical
source):

```bash
cd typescript
npm install
npm run build      # tsc --build src test  ->  dist/ + dist-test/
npm test           # node --test dist-test/**/*.test.js
```

### Your first program

```ts
import { getpath, merge, transform, validate } from '@voxgig/struct'

const config = merge([
  { db: { host: 'localhost', port: 5432 }, debug: false }, // defaults
  { db: { host: 'db.internal' }, debug: true },            // overrides
])

getpath(config, 'db.host')   // 'db.internal'
getpath(config, 'db.port')   // 5432  (survived the deep merge)
```

### Build up the rest of the API

Each call below has the same meaning in every port; only the syntax
changes. Read [`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the
full language-neutral walkthrough; the TypeScript-flavoured version:

```ts
import * as S from '@voxgig/struct'

// Reshape by example — the spec mirrors the output you want.
S.transform(
  { user: { first: 'Ada', last: 'Lovelace' }, age: 36 },
  { name: '`user.first`', surname: '`user.last`', years: '`age`' },
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
```ts
import { StructUtility } from '@voxgig/struct'
const su = new StructUtility()
su.getpath({ a: { b: 1 } }, 'a.b')   // 1
```
Every function and constant is also an instance member of `StructUtility`,
which is convenient when a consumer wants to swap the implementation.

### Collect all validation errors instead of throwing
```ts
const errs: any[] = []
validate(payload, spec, { errs })
if (errs.length) console.error(errs)
```

### Write a custom transform function (`$APPLY`)
```ts
transform(
  { items: [1, 2, 3] },
  { total: { '`$APPLY`': 'sum' } },
  { extra: { sum: (_key: any, val: any, parent: any) => parent.items.reduce((a: number, b: number) => a + b, 0) } },
)
```
Register the function under `extra`; reference it by name in the spec. A
custom function may return the `SKIP` / `DELETE` sentinels to omit/remove
the current key.

### Keep a `walk` path past the callback
```ts
const seen: string[][] = []
walk(tree, (key, val, parent, path) => {
  seen.push(path.slice())   // the path array is reused — clone to retain it
  return val
})
```

### Serialise deterministically
```ts
jsonify(value)              // compact, insertion-ordered keys
jsonify(value, { indent: 2 })
stringify(value, 80)        // truncated human form, for logs
```

For more task recipes (merge configs, rename fields, `$EACH`, `$MERGE`,
`$FORMAT`, `$ONE`, `$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical;
only the host literals differ.

---

## 3. Reference

The full TypeScript signatures, with examples for every function, are in
[`README.md` → Function reference](./README.md#function-reference). The
canonical public surface (48 names) is the `export { … }` block in
[`src/StructUtility.ts`](./src/StructUtility.ts) — that block *is* the
definition the parity tool checks every other port against.

TypeScript-specific points the signatures don't show:

- **`any` at the boundaries.** The API is intentionally "JSON-shaped
  `any`": inputs and outputs are untyped JSON. `isnode`/`ismap`/`islist`
  are typed as **type guards** (`val is …`) so they narrow usefully in
  consumer code, but the data model itself is dynamic.
- **`getprop` vs `getelem`.** `getprop` works on maps and lists; `getelem`
  is list-specific, supports `-1`-from-the-end indexing, and *invokes* a
  callable `alt` when the element is absent (`getprop`/`getdef` do not).
- **`items` is overloaded** — `items(node)` returns `[key, val][]`;
  `items(node, fn)` maps each pair through `fn`.
- **`walk` extra parameters** (`key`, `parent`, `path`, `pool`) are
  recursion state; callers pass only `(val, before?, after?, maxdepth?)`.
- **Type flags** combine bitwise: `typify('hi')` is `T_scalar | T_string`;
  test with `0 < (T_string & t)`. `typify(undefined)` is `T_noval` (not a
  scalar); `typify(null)` is `T_scalar | T_null`.

---

## 4. Explanation & port specifics

### The canonical role

This port is the source of truth. The shared corpus in
[`../build/test/`](../build/test/) is generated to match *this* code, and
every other language is held to that corpus. Practically:

- A behaviour question is answered by reading
  [`src/StructUtility.ts`](./src/StructUtility.ts), not by polling the
  ports.
- A change to canonical behaviour starts here, then flows to the corpus and
  out to every port (see [`../AGENTS.md`](../AGENTS.md#standard-workflows)).

### `null` versus `undefined`

TypeScript has both, and `struct` keeps them distinct — the
[Group A/B rule](../DOCS.md#null-versus-absent-group-ab) in language-neutral
form:

- `undefined` = **absent**. `getprop` on a missing key returns `undefined`;
  Group A readers treat a stored `null` as absent too.
- `null` = the JSON null scalar; `typify(null)` is `T_scalar | T_null`, and
  Group B processors (`clone`, `merge`, `walk`, …) preserve it literally.

If your data source returns `null` for "not set", decide which you mean
before handing it to `struct`.

### Lists are reference-stable

`walk`, `merge`, `inject`, and `setpath` rely on JavaScript arrays being
mutable and shared by reference — a mutation through one handle is visible
to all. Ports in languages without that property (Go, PHP) introduce a
`ListRef` wrapper to reproduce it; TypeScript needs none.

### Regex

The canonical regex engine is ECMAScript `RegExp`, wrapped by the uniform
six-function API (`re_compile` / `re_test` / `re_find` / `re_find_all` /
`re_replace` / `re_escape`). Stay inside the **RE2 subset** — `RegExp`
*allows* backreferences and lookaround, but those don't port. Two sharp
edges (catastrophic backtracking; zero-width `re_replace` returning
`"XXbXcX"`) are detailed in [`README.md` → Regex](./README.md#regex) and
[`../REGEX_PATHOLOGICAL.md`](../REGEX_PATHOLOGICAL.md).

---

## Build, test, and extend

```bash
cd typescript
npm install
npm run build        # compile src + test
npm test             # run the corpus + unit tests (89 cases)
npm run lint         # ESLint 10 (flat config) + Prettier check
npm run typecheck    # tsc --build --force
```

Tests live in [`test/`](./test/); the runner
([`test/runner.ts`](./test/runner.ts)) loads the shared corpus from
[`../build/test/`](../build/test/) and is the reference every port's runner
mirrors.

**To change canonical behaviour:** edit `src/StructUtility.ts`, add or
adjust the corpus case in `../build/test/*.jsonic`, `npm run build && npm
test` until green, then propagate to every port and re-run
`python3 ../tools/check_parity.py` and the per-port tests. The full
checklist is in [`../AGENTS.md`](../AGENTS.md). Tooling versions: Node 22+,
TypeScript 6, ESLint 10.
</content>
