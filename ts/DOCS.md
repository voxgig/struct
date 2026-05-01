# Struct for TypeScript

> The canonical implementation.  Every other port matches the
> behaviour defined here.

This is the reference implementation of `@voxgig/struct`.  When other
ports disagree with the shared test corpus, the corpus -- and this
TypeScript code -- is right.

For the language-neutral overview, motivation, and concepts, see the
[top-level README](../README.md).

These docs follow the [Diataxis](https://diataxis.fr/) framework.


## Tutorial: your first transform

### Install

```bash
npm install @voxgig/struct
```

### A first transform

Create `hello.ts`:

```ts
import { transform, validate } from '@voxgig/struct'

const data = {
  user: { first: 'Ada', last: 'Lovelace' },
  age: 36,
}

// A spec is data that mirrors the desired output.
// Backtick-quoted strings are path references into `data`.
const spec = {
  name: '`user.first`',
  surname: '`user.last`',
  years: '`age`',
}

const out = transform(data, spec)
console.log(out)
// { name: 'Ada', surname: 'Lovelace', years: 36 }
```

### Add validation

```ts
const shape = {
  name: '`$STRING`',
  surname: '`$STRING`',
  years: '`$INTEGER`',
}

validate(out, shape)   // returns out unchanged on success
```

If you hand `validate` a value that doesn't match, it throws.  Pass an
errors-collector array as the fourth argument to collect rather than
throw -- see [Reference](#reference).


## How-to recipes

### Read a deep value safely

```ts
import { getpath, getprop, getdef } from '@voxgig/struct'

getpath(config, 'db.host')              // 'localhost' or undefined
getpath(config, ['db', 'host'])         // same, array form

getprop(node, 'count', 0)               // 0 if absent
getdef(maybe, 'fallback')               // returns maybe unless undefined
```

### Set a deep value, creating missing parents

```ts
import { setpath } from '@voxgig/struct'

const store = {}
setpath(store, 'db.host', 'localhost')
// store === { db: { host: 'localhost' } }
```

### Merge a chain of configs

```ts
import { merge } from '@voxgig/struct'

const cfg = merge([defaults, fileConfig, envOverrides])
```

Last input wins for scalars; maps deep-merge; lists merge by index.

### Walk a tree

```ts
import { walk } from '@voxgig/struct'

// walk takes optional before/after callbacks; pass an `after` callback
// to replace values once their children have been visited.
walk(tree, undefined, (key, val, parent, path) => {
  // Return a replacement value, or `val` to leave unchanged.
  return val === null ? 'DEFAULT' : val
})
```

The `path` array is reused across calls; clone it (`path.slice()`)
if you need to retain it.

### Inject values into a template

```ts
import { inject } from '@voxgig/struct'

inject(
  { greeting: 'hello `name`', age: '`years`' },
  { name: 'Ada', years: 36 }
)
// => { greeting: 'hello Ada', age: 36 }
```

### Pick records out of a node by query

```ts
import { select } from '@voxgig/struct'

select(
  { age: 30 },
  { a: { name: 'Alice', age: 30 }, b: { name: 'Bob', age: 25 } }
)
// => [ { name: 'Alice', age: 30, $KEY: 'a' } ]
```


## Reference

Source: [`src/StructUtility.ts`](./src/StructUtility.ts).

### Installation

```
npm install @voxgig/struct
```

Package: `@voxgig/struct`.  Entry: `dist/StructUtility.js` /
`dist/StructUtility.d.ts`.

### Imports

```ts
import {
  // minor utilities
  typename, getdef, isnode, ismap, islist, iskey, isempty, isfunc,
  size, slice, pad, typify, getelem, getprop, strkey, keysof,
  haskey, items, flatten, filter, escre, escurl, join, jsonify,
  stringify, pathify, clone, delprop, setprop,

  // major utilities
  walk, merge, setpath, getpath, inject, transform, validate, select,

  // builders
  jm, jt,

  // injection helpers
  checkPlacement, injectorArgs, injectChild,

  // sentinels
  SKIP, DELETE,

  // type bit-flags
  T_any, T_noval, T_boolean, T_decimal, T_integer, T_number, T_string,
  T_function, T_symbol, T_null, T_list, T_map, T_instance, T_scalar,
  T_node,

  // walk/inject mode flags
  M_KEYPRE, M_KEYPOST, M_VAL, MODENAME,

  // class wrapper
  StructUtility,

  // type only
  Injection,
} from '@voxgig/struct'
```

### Major functions

```ts
function walk(
  val: any,
  before?: WalkApply,
  after?: WalkApply,
  maxdepth?: number,
): any

function merge(list: any[], maxdepth?: number): any

function getpath(store: any, path: string | string[], injdef?: Partial<Injection>): any
function setpath(store: any, path: string | string[], val: any): any

function inject(val: any, store: any, modify?: Modify): any

function transform(
  data: any,
  spec: any,
  extra?: any,
  modify?: Modify,
): any

function validate(
  data: any,
  spec: any,
  extra?: any,
  collecterrs?: string[],
): any

function select(children: any, query: any): any[]
```

### Sentinels

- `SKIP` -- returned from a transform/inject step to omit the key.
- `DELETE` -- returned to remove the key from the parent.

### `StructUtility` class

`StructUtility` exposes every function and constant as instance
properties, useful for dependency-injecting the API or stubbing it in
tests.

```ts
import { StructUtility } from '@voxgig/struct'
const su = new StructUtility()
su.getpath({ a: { b: 1 } }, 'a.b')   // 1
```

### Transform commands

Used as quoted strings inside a `transform` spec:

`$DELETE`, `$COPY`, `$KEY`, `$META`, `$ANNO`, `$MERGE`, `$EACH`,
`$PACK`, `$REF`, `$FORMAT`, `$APPLY`.

### Validate checkers

Used as quoted strings inside a `validate` spec:

`$MAP`, `$LIST`, `$STRING`, `$NUMBER`, `$INTEGER`, `$DECIMAL`,
`$BOOLEAN`, `$NULL`, `$NIL`, `$FUNCTION`, `$INSTANCE`, `$ANY`,
`$CHILD`, `$ONE`, `$EXACT`.


## Explanation

### Why TypeScript is canonical

TypeScript is expressive enough to model `null` vs `undefined` vs
absent without ceremony, has fast iteration on V8, and produces a
.d.ts type signature that becomes the "contract" the other ports
target.  The shared test corpus
([`build/test/*.jsonic`](../build/test/)) is consumed by every port,
so the canonical answers are produced from this implementation.

### `null` versus `undefined`

In TypeScript, `undefined` means "absent" and `null` is the JSON null
value.  Most `getprop`/`getelem` paths return `undefined` when the
key is missing, and accept an `alt` argument for a fallback.  When
porting, this distinction matters: see the language-specific docs for
each port's chosen sentinel.

### Lists are mutable and reference-stable

`walk`, `merge`, `inject`, and `setpath` all assume that mutating a
list in place is visible to other holders of the same list.  This is
free in JS/TS; ports to value-array languages (Go, PHP) introduce a
`ListRef` wrapper to preserve the property.

### Path syntax

Paths are either:

- a dot-separated string: `'a.b.0.c'`
- an array: `['a', 'b', 0, 'c']`

Integer-looking string keys index into lists; everything else indexes
maps.

### By-example specs

A `transform` spec mirrors the desired output: keys, nesting, and
default values are all literal.  The only special tokens are
backtick-quoted strings (`` `path` ``, `` `$CMD` ``).  Likewise a
`validate` spec is the shape of the accepted data with type tokens at
the leaves.


## Build and test

```bash
cd ts
npm install
npm run build      # tsc → dist/
npm test           # node --test on dist-test
```

Tests live in [`test/`](./test/) and read fixtures from
[`../build/test/`](../build/test/).
