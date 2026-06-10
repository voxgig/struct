# Struct for JavaScript

> Plain JavaScript port; runtime-identical to the canonical
> TypeScript implementation.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../design/REPORT.md).


## Install

The JS source is a single CommonJS module:
[`src/struct.js`](./src/struct.js).  Inside the monorepo:

```js
const struct = require('./javascript/src/struct.js')
```

When packaged the public name is `@voxgig/struct` (see
[`package.json`](./package.json)).


## Quick start

```js
const {
  getpath, setpath, merge, walk,
  inject, transform, validate, select,
} = require('./javascript/src/struct.js')

getpath({ db: { host: 'localhost' } }, 'db.host')
// 'localhost'

transform(
  { user: { first: 'Ada', last: 'Lovelace' }, age: 36 },
  { name: '`user.first`', surname: '`user.last`', years: '`age`' }
)
// { name: 'Ada', surname: 'Lovelace', years: 36 }

validate(
  { name: 'Ada', age: 36 },
  { name: '`$STRING`', age: '`$INTEGER`' }
)
// { name: 'Ada', age: 36 }   (throws on mismatch)
```


## Module exports

```js
module.exports = {
  StructUtility, Injection,

  // 41 functions (40 canonical + replace exposed)
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


## Function reference

Source: [`src/struct.js`](./src/struct.js).

### Predicates

```js
isnode(val)     // true for maps and lists
ismap(val)      // true for plain objects
islist(val)    // true for arrays
iskey(key)      // true for non-empty strings or numbers
isempty(val)   // true for null/undefined/''/{}/[]
isfunc(val)    // true for functions
```

<!-- example: minor/isnode#map -->
```js
isnode({ a: 1 })          // true
```
<!-- => true -->

```js
isnode([1])               // true
isnode('x')               // false
ismap({})                 // true
islist([])                // true
iskey(0)                  // true
iskey('')                 // false
isempty(null)             // true
isempty([])               // true
isempty(0)                // false
isfunc(() => 1)           // true
```

### Type inspection

```js
typify(val)               // -> int bitfield
typename(t)               // -> human-friendly type name
```

```js
typify(42)                // T_scalar | T_number | T_integer
typify('hi')              // T_scalar | T_string
typify(undefined)         // T_noval
typify(null)              // T_scalar | T_null

typename(typify('hi'))    // 'string'
typename(typify({}))      // 'map'
```

### Size, slice, pad

```js
size(val)                            // -> int
slice(val, start?, end?, mutate?)    // sub-section of list/string/number
pad(str, padding?, padchar?)         // pad to width; negative -> left
```

<!-- example: minor/size#three -->
```js
size([1,2,3])             // 3
```
<!-- => 3 -->

```js
size({a:1,b:2})           // 2
size('abc')               // 3
```

`slice` keeps the first *N*; a negative `start` drops the last *|start|*
items, and `end` is exclusive:

<!-- example: minor/slice#mid -->
```js
slice([1,2,3,4,5], 1, 4)  // [2, 3, 4]
```
<!-- => [2, 3, 4] -->

<!-- example: minor/slice#strhead -->
```js
slice('abcdef', -3)       // 'abc'  (drops the last 3)
```
<!-- => "abc" -->

<!-- example: minor/pad#right -->
```js
pad('a', 3)               // 'a  '
```
<!-- => "a  " -->

```js
pad('hi', 5)              // 'hi   '
pad('hi', -5, '*')        // '***hi'
```

### Property access

```js
getprop(val, key, alt?)           // -> any
setprop(parent, key, val)         // mutates and returns parent
delprop(parent, key)              // mutates and returns parent
getelem(list, key, alt?)          // list lookup; -1 from end
getdef(val, alt)                  // val unless undefined
haskey(val, key)                  // -> bool
keysof(val)                       // sorted keys
items(val)                        // [[key,val], ...]
items(val, fn)                    // map over entries
strkey(key)                       // canonical string form
```

<!-- example: minor/getprop#hit -->
```js
getprop({x:1}, 'x')               // 1
```
<!-- => 1 -->

```js
getprop({a:1}, 'b', 'def')        // 'def'

setprop({a:1}, 'b', 2)            // { a:1, b:2 }
delprop({a:1, b:2}, 'a')          // { b:2 }

getelem([1,2,3], -1)              // 3
getdef(undefined, 'fb')           // 'fb'
haskey({a:1}, 'a')                // true
items({a:1, b:2})                 // [['a',1], ['b',2]]
strkey(1)                         // '1'
```

<!-- example: minor/keysof#sorted -->
```js
keysof({b:4, a:5})                // ['a','b']  (sorted)
```
<!-- => ["a", "b"] -->

### Path operations

```js
getpath(store, path, injdef?)      // -> any
setpath(store, path, val, injdef?) // mutates and returns store
pathify(val, startin?, endin?)     // canonical dotted string
```

<!-- example: getpath/basic#deep -->
```js
getpath({ a: { b: { c: 42 } } }, 'a.b.c')   // 42
```
<!-- => 42 -->

```js
getpath({ a: [10,20] }, 'a.1')              // 20
getpath({}, 'missing')                      // undefined

const store = {}
setpath(store, 'db.host', 'localhost')
// store === { db: { host: 'localhost' } }

pathify(['a','b','c'])                      // 'a.b.c'
```

### Tree operations

```js
walk(val, before?, after?, maxdepth?)
  // before/after :: (key, val, parent, path) => any
merge(list, maxdepth?)
clone(val)
flatten(list, depth?)
filter(val, check)
```

```js
walk(tree, undefined, (k, v) => v == null ? 'X' : v)

merge([
  { a:1, b:2, x:{y:5,z:6} },
  { b:3,     x:{y:7}     },
])
// { a:1, b:3, x:{y:7,z:6} }

clone({ a:[1,2] })              // deep copy
flatten([1,[2,[3,[4]]]])        // [1, 2, [3, [4]]]
flatten([1,[2,[3,[4]]]], 2)     // [1, 2, 3, [4]]
```

`filter` passes each `[key, value]` pair to the check and returns the
matching **values** (not the pairs):

<!-- example: minor/filter#gt3 -->
```js
filter([1, 2, 3, 4, 5], ([k, v]) => v > 3)
// [4, 5]
```
<!-- => [4, 5] -->

### String / URL / JSON

```js
escre(s)                           // escape regex metachars
escurl(s)                          // URL-encode
join(arr, sep?, url?)              // join parts
jsonify(val, flags?)               // JSON serialise
stringify(val, maxlen?, pretty?)   // human-friendly compact
replace(s, from, to)               // string/regex replace
```

```js
escre('a.b+c')                      // 'a\\.b\\+c'
escurl('hello world')               // 'hello%20world'
join(['a','b','c'], '/')            // 'a/b/c'
join(['http:', '/foo/'], '/', true) // 'http:/foo'
```

`jsonify` pretty-prints by default (indent 2); pass `{ indent: 0 }` for the
compact form:

<!-- example: minor/jsonify#map -->
```js
jsonify({ a: 1 })
// {
//   "a": 1
// }
```
<!-- => "{\n  \"a\": 1\n}" -->

<!-- example: minor/jsonify#compact -->
```js
jsonify({ a: 1, b: 2 }, { indent: 0 })  // '{"a":1,"b":2}'
```
<!-- => "{\"a\":1,\"b\":2}" -->

`stringify` is the compact, quote-light form — keys are sorted and object
braces are kept; the second argument caps the length (the `...` counts):

<!-- example: minor/stringify#brace -->
```js
stringify({ a: 1, b: [2, 3] })          // '{a:1,b:[2,3]}'
```
<!-- => "{a:1,b:[2,3]}" -->

<!-- example: minor/stringify#max -->
```js
stringify('verylongstring', 5)          // 've...'
```
<!-- => "ve..." -->

### Inject / transform / validate / select

```js
inject(val, store, injdef?)
transform(data, spec, injdef?)
validate(data, spec, injdef?)
select(children, query)
```

```js
inject(
  { greeting: 'hello `name`' },
  { name: 'Ada' }
)
// { greeting: 'hello Ada' }

transform(
  { hold: { x: 1 }, top: 99 },
  { a: '`hold.x`', b: '`top`' }
)
// { a: 1, b: 99 }

validate({ name: 'Ada' }, { name: '`$STRING`' })
// { name: 'Ada' }    (throws on mismatch)

select(
  { a: { age:30 }, b: { age:25 } },
  { age: 30 }
)
// [{ age: 30, $KEY: 'a' }]
```

Transform commands drive structural ops. A command like `$EACH` appears in
**value** position — as the first element of a list `['`$EACH`', path, subspec]`
— mapping the sub-spec over every entry at `path`:

<!-- example: transform/each#basic -->
```js
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
```js
transform({}, { x: '`$APPLY`' })
// throws: $APPLY: invalid placement in parent map, expected: list.
```
<!-- throws: invalid placement in parent map -->

### Builders

```js
jm('a', 1, 'b', 2)        // { a: 1, b: 2 }
jt(1, 2, 3)               // [1, 2, 3]
```

### Injection helpers

Exposed for callers writing custom injectors:

```js
checkPlacement(modes, ijname, parentTypes, inj)  // -> bool
injectorArgs(argTypes, args)                      // -> any
injectChild(child, store, inj)                    // -> Injection
```


## Constants

### Sentinels

```js
SKIP        // emit nothing for this key
DELETE      // remove this key from the parent
```

### Type bit-flags

```js
T_any T_noval T_boolean T_decimal T_integer T_number T_string
T_function T_symbol T_null T_list T_map T_instance T_scalar T_node
```

`typify(val)` returns a bit-field combining a kind flag (`T_scalar`
or `T_node`) with a specific type flag.

### Walk / inject phase flags

```js
M_KEYPRE       // pre-descent
M_KEYPOST      // post-descent
M_VAL          // leaf-value visit
MODENAME       // string[] mapping mode flags to names
```


## Transform commands

Used as backtick-quoted strings inside a `transform` spec.

```
$DELETE  $COPY    $KEY     $META    $ANNO
$MERGE   $EACH    $PACK    $REF     $FORMAT  $APPLY
```

See the [top-level README](../README.md) for purpose of each.


## Validate checkers

Used as backtick-quoted strings inside a `validate` spec.

```
$MAP   $LIST   $STRING   $NUMBER   $INTEGER   $DECIMAL  $BOOLEAN
$NULL  $NIL    $FUNCTION $INSTANCE $ANY       $CHILD    $ONE     $EXACT
```


## Notes

### `null` versus `undefined`

JavaScript distinguishes the two natively; `struct` preserves the
distinction:

- `undefined` -> "absent".  `getprop` returns it for a missing key.
- `null` -> JSON null, a defined scalar.

If your JSON parser returns `null` for absent fields, convert to
`undefined` (or use `'__NULL__'` placeholders) before passing in.

### Lists mutate in place

`merge`, `setpath`, and `inject` rely on lists being reference-stable
-- a mutation through one reference is visible to every holder.
JavaScript arrays satisfy this natively.

### Difference from canonical TypeScript

The JS port additionally exports `replace` (internal-only in TS).
Otherwise functionally identical -- both run on V8.

### Test status

84/84 tests pass against the shared corpus.


## Regex

Uniform six-function regex API (see `/design/REGEX_API.md`). On JavaScript
this is the ECMAScript `RegExp` built-in.

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

Patterns must stay inside the **RE2 subset** documented in `/design/REGEX.md`.
`RegExp` itself supports backreferences and lookaround, but other ports
do not, so using those will not be portable.

### Sharp edges

- **Catastrophic backtracking.** `RegExp` is a backtracking engine;
  nested quantifiers like `(a+)+` against a non-matching suffix can be
  exponential in input length (the discovery panel sees ~180 ms on
  Node 22 vs <0.1 ms on RE2-style engines). Prefer flat patterns and
  character classes over alternations.
- **Zero-width `replace`.** `re_replace("a*", "abc", "X")` returns
  `"XXbXcX"` — the ECMA convention shared by all PCRE/ECMA/.NET/Java/Onigmo engines plus the in-tree Thompson ports. Go (RE2) returns `"XbXcX"` instead; see `/design/REGEX_PATHOLOGICAL.md`.

See `/design/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input
panel.


## Build and test

```bash
cd javascript
make test           # runs the shared .jsonic corpus
```

Tests live in [`test/`](./test/) and read fixtures from
[`../build/test/`](../build/test/).
