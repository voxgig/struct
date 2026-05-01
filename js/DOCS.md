# Struct for JavaScript

> The plain-JavaScript port.  Runtime-identical to the TypeScript
> canonical implementation.

For the language-neutral overview, motivation, and concepts, see the
[top-level README](../README.md).

These docs follow the [Diataxis](https://diataxis.fr/) framework.


## Tutorial: your first transform

### Install

The JS source lives in [`src/struct.js`](./src/struct.js) as a
CommonJS module.  Inside the monorepo:

```js
const struct = require('./js/src/struct.js')
```

### A first transform

```js
const { transform } = require('./js/src/struct.js')

const data = { user: { first: 'Ada', last: 'Lovelace' }, age: 36 }

const spec = {
  name: '`user.first`',
  surname: '`user.last`',
  years: '`age`',
}

console.log(transform(data, spec))
// { name: 'Ada', surname: 'Lovelace', years: 36 }
```

### Validate the result

```js
const { validate } = require('./js/src/struct.js')

validate(out, {
  name: '`$STRING`',
  surname: '`$STRING`',
  years: '`$INTEGER`',
})
```

`validate` returns the value on success and throws on mismatch.


## How-to recipes

### Read a deep value safely

```js
const { getpath, getprop, getdef } = require('./js/src/struct.js')

getpath('db.host', config)              // value or undefined
getprop(node, 'count', 0)               // 0 if absent
getdef(maybe, 'fallback')               // returns maybe unless undefined
```

### Set a deep value

```js
const { setpath } = require('./js/src/struct.js')

const store = {}
setpath(store, 'db.host', 'localhost')
// store.db.host === 'localhost'
```

### Deep-merge configs

```js
const { merge } = require('./js/src/struct.js')

const cfg = merge([defaults, file, env])
```

### Walk a tree

```js
const { walk } = require('./js/src/struct.js')

walk(tree, (key, val, parent, path) => {
  return val === null ? 'DEFAULT' : val
})
```

The `path` argument is reused; clone with `path.slice()` to keep it.

### Inject references into a template

```js
const { inject } = require('./js/src/struct.js')

inject(
  { greeting: 'hello `name`', age: '`years`' },
  { name: 'Ada', years: 36 }
)
// { greeting: 'hello Ada', age: 36 }
```

### Select records by query

```js
const { select } = require('./js/src/struct.js')

select(
  { age: 30 },
  { a: { name: 'Alice', age: 30 }, b: { name: 'Bob', age: 25 } }
)
// [ { name: 'Alice', age: 30, $KEY: 'a' } ]
```


## Reference

### Module shape

```js
module.exports = {
  StructUtility, Injection,

  // 41 functions (40 canonical + replace exposed publicly)
  clone, delprop, escre, escurl, filter, flatten, getdef, getelem,
  getpath, getprop, haskey, inject, isempty, isfunc, iskey, islist,
  ismap, isnode, items, join, jsonify, keysof, merge, pad, pathify,
  replace, select, setpath, setprop, size, slice, strkey, stringify,
  transform, typify, typename, validate, walk, jm, jt,
  checkPlacement, injectorArgs, injectChild,

  // sentinels
  SKIP, DELETE,

  // 15 type bit-flags
  T_any, T_noval, T_boolean, T_decimal, T_integer, T_number, T_string,
  T_function, T_symbol, T_null, T_list, T_map, T_instance, T_scalar,
  T_node,

  // mode flags
  M_KEYPRE, M_KEYPOST, M_VAL, MODENAME,
}
```

### Differences from canonical TypeScript

- `replace(s, fromPat, toStr)` is exported (internal in TS).
- Identical runtime semantics -- both run on V8/JS engines.
- Test count: 84/84 passing.

For full signatures, see the [canonical TypeScript
docs](../ts/DOCS.md#reference).


## Explanation

### `null` vs `undefined`

JavaScript distinguishes the two natively, and `struct` preserves the
distinction:

- `undefined` means "absent" -- `getprop` returns `undefined` for a
  missing key, and most predicates treat `undefined` as not-a-node.
- `null` is the JSON null value -- a defined scalar.

When a JSON parser hands you `null` for an absent field, you may want
to convert it to `undefined` (or use `'__NULL__'` as a placeholder)
before passing into `struct`.  See [README §Concepts](../README.md#concepts).

### Lists are mutated in place

`merge`, `setpath`, and `inject` rely on lists being reference-stable.
This is JavaScript's natural behaviour; no wrapper needed.

### Why a hand-written JS file alongside the TypeScript

The JS file is hand-maintained for legibility and ports that want to
follow the JS code rather than read TypeScript types.  Both files
agree on behaviour, enforced by the shared test corpus.


## Build and test

```bash
cd js
npm install
make test           # runs the .jsonic corpus
```

Tests live in [`test/`](./test/) and read fixtures from
[`../build/test/`](../build/test/).
