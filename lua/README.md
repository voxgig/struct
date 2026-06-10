# Struct for Lua

> Full-parity Lua port of the canonical TypeScript implementation.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../design/REPORT.md).


## Setup

The module is a single file: [`src/struct.lua`](./src/struct.lua).

### First-time setup

Install Lua 5.3+, LuaRocks, and the test dependencies:

```bash
cd lua
make setup
```

This installs Lua and LuaRocks if not already present, plus the
required packages: `busted`, `luassert`, `dkjson`, `luafilesystem`.

Verify:

```bash
lua -v
luarocks list
```

### Manual dependency install

If you prefer to install dependencies yourself:

```bash
luarocks install busted
luarocks install luassert
luarocks install dkjson
luarocks install luafilesystem
```


## Quick start

```lua
package.path = './src/?.lua;' .. package.path
local struct = require('struct')

local store = {
  db   = { host = 'localhost' },
  user = { first = 'Ada', last = 'Lovelace' },
  age  = 36,
}

print(struct.getpath(store, 'db.host'))
-- localhost

local out = struct.transform(store, {
  name    = '`user.first`',
  surname = '`user.last`',
  years   = '`age`',
})
-- out == { name = 'Ada', surname = 'Lovelace', years = 36 }

struct.validate(store, {
  user = {
    first = '`$STRING`',
    last  = '`$STRING`',
  },
  age = '`$INTEGER`',
})
```


## Function reference

Source: [`src/struct.lua`](./src/struct.lua).

### Predicates

```lua
struct.isnode(val)     -- map or list (table)
struct.ismap(val)      -- map (object-shaped table)
struct.islist(val)     -- list (array-shaped table)
struct.iskey(key)      -- non-empty string or integer
struct.isempty(val)
struct.isfunc(val)     -- callable
```

<!-- example: minor/isnode#map -->
```lua
struct.isnode({ a = 1 })             -- true
```
<!-- => true -->

```lua
struct.ismap({ a = 1 })              -- true
struct.islist({ 1, 2, 3 })           -- true
struct.iskey('name')                 -- true
struct.iskey('')                     -- false
struct.isempty(nil)                  -- true
struct.isfunc(function() end)        -- true
```

### Type inspection

```lua
struct.typify(val)        -- -> integer (bit-field)
struct.typename(t)        -- -> string
```

```lua
struct.typify(42)                    -- T_scalar | T_number | T_integer
struct.typify('hi')                  -- T_scalar | T_string
struct.typify(nil)                   -- T_noval (Lua has no separate null)
struct.typename(struct.typify('hi')) -- 'string'
```

### Size, slice, pad

```lua
struct.size(val)
struct.slice(val, start, finish, mutate)
struct.pad(str, padding, padchar)
```

<!-- example: minor/size#three -->
```lua
struct.size({ 1, 2, 3 })             -- 3
```
<!-- => 3 -->

`slice` keeps the first *N*; a negative `start` drops the last *|start|*
items, and `finish` is exclusive:

<!-- example: minor/slice#mid -->
```lua
struct.slice({ 1, 2, 3, 4, 5 }, 1, 4)  -- { 2, 3, 4 }
```
<!-- => [2, 3, 4] -->

<!-- example: minor/slice#strhead -->
```lua
struct.slice('abcdef', -3)           -- 'abc'  (drops the last 3)
```
<!-- => "abc" -->

<!-- example: minor/pad#right -->
```lua
struct.pad('a', 3)                   -- 'a  '
```
<!-- => "a  " -->

```lua
struct.pad('hi', 5)                  -- 'hi   '
struct.pad('hi', -5, '*')            -- '***hi'
```

### Property access

```lua
struct.getprop(val, key, alt)
struct.setprop(parent, key, val)
struct.delprop(parent, key)
struct.getelem(val, key, alt)
struct.getdef(val, alt)
struct.haskey(val, key)
struct.keysof(val)
struct.items(val)        -- { {key, val}, ... }
struct.strkey(key)
```

<!-- example: minor/getprop#hit -->
```lua
struct.getprop({ x = 1 }, 'x')              -- 1
```
<!-- => 1 -->

```lua
struct.getprop({}, 'b', 'fallback')         -- 'fallback'
struct.setprop({ a = 1 }, 'b', 2)           -- { a = 1, b = 2 }
struct.delprop({ a = 1, b = 2 }, 'a')       -- { b = 2 }
struct.getelem({ 1, 2, 3 }, -1)             -- 3
struct.haskey({ a = 1 }, 'a')               -- true
struct.items({ a = 1, b = 2 })              -- { {'a', 1}, {'b', 2} }
struct.strkey(1)                            -- '1'
```

<!-- example: minor/keysof#sorted -->
```lua
struct.keysof({ b = 4, a = 5 })             -- { 'a', 'b' }  (sorted)
```
<!-- => ["a", "b"] -->

### Path operations

```lua
struct.getpath(store, path, injdef)
struct.setpath(store, path, val, injdef)
struct.pathify(val, startin, endin)
```

<!-- example: getpath/basic#deep -->
```lua
struct.getpath({ a = { b = { c = 42 } } }, 'a.b.c')   -- 42
```
<!-- => 42 -->

```lua
struct.getpath({ a = { 10, 20 } }, 'a.0')             -- 10
struct.getpath({}, 'missing')                         -- nil

local store = {}
struct.setpath(store, 'db.host', 'localhost')
-- store.db.host == 'localhost'

struct.pathify({ 'a', 'b', 'c' })                     -- 'a.b.c'
```

### Tree operations

```lua
struct.walk(val, before, after, maxdepth)
struct.merge(val, maxdepth)
struct.clone(val)
struct.flatten(list, depth)
struct.filter(val, check)
```

```lua
struct.walk(tree, nil, function(key, val, parent, path)
  if val == nil then
    return 'DEFAULT'
  end
  return val
end)

struct.merge({
  { a = 1, b = 2 },
  { b = 3, c = 4 },
})
-- { a = 1, b = 3, c = 4 }

struct.clone({ a = { 1, 2 } })
struct.flatten({ 1, { 2, { 3 } } })
```

`filter` passes each `{ key, value }` pair to the check and returns the
matching **values** (not the pairs):

<!-- example: minor/filter#gt3 -->
```lua
struct.filter({ 1, 2, 3, 4, 5 },
              function(kv) return kv[2] > 3 end)
-- { 4, 5 }
```
<!-- => [4, 5] -->

### String / URL / JSON

```lua
struct.escre(s)
struct.escurl(s)
struct.join(arr, sep, url)
struct.jsonify(val, flags)
struct.stringify(val, maxlen, pretty)
struct.replace(s, from, to)
```

```lua
struct.escre('a.b+c')                    -- 'a%.b%+c'  (Lua patterns)
struct.escurl('hello world')             -- 'hello%20world'
struct.join({ 'a', 'b', 'c' }, '/')      -- 'a/b/c'
```

`jsonify` pretty-prints by default (indent 2); pass `{ indent = 0 }` for the
compact form:

<!-- example: minor/jsonify#map -->
```lua
struct.jsonify({ a = 1 })
-- {
--   "a": 1
-- }
```
<!-- => "{\n  \"a\": 1\n}" -->

<!-- example: minor/jsonify#compact -->
```lua
struct.jsonify({ a = 1, b = 2 }, { indent = 0 })  -- '{"a":1,"b":2}'
```
<!-- => "{\"a\":1,\"b\":2}" -->

`stringify` is the compact, quote-light form — keys are sorted and object
braces are kept; the second argument caps the length (the `...` counts):

<!-- example: minor/stringify#brace -->
```lua
struct.stringify({ a = 1, b = { 2, 3 } })  -- '{a:1,b:[2,3]}'
```
<!-- => "{a:1,b:[2,3]}" -->

<!-- example: minor/stringify#max -->
```lua
struct.stringify('verylongstring', 5)    -- 've...'
```
<!-- => "ve..." -->

### Inject / transform / validate / select

```lua
struct.inject(val, store, injdef)
struct.transform(data, spec, injdef)
struct.validate(data, spec, injdef)
struct.select(children, query)
```

```lua
struct.inject(
  { greeting = 'hello `name`' },
  { name = 'Ada' }
)
-- { greeting = 'hello Ada' }

struct.transform(
  { hold = { x = 1 }, top = 99 },
  { a = '`hold.x`', b = '`top`' }
)
-- { a = 1, b = 99 }

struct.validate({ name = 'Ada' }, { name = '`$STRING`' })

struct.select(
  { a = { age = 30 }, b = { age = 25 } },
  { age = 30 }
)
```

Transform commands drive structural ops. A command like `$EACH` appears in
**value** position — as the first element of a list
`{ '`$EACH`', path, subspec }` — mapping the sub-spec over every entry at
`path`:

<!-- example: transform/each#basic -->
```lua
struct.transform(
  { v = 1, a = struct.jt({ q = 13 }, { q = 23 }) },
  { x = { y = struct.jt('`$EACH`', 'a',
              { q = '`$COPY`', r = '`.q`', p = '`...v`' }) } }
)
-- { x = { y = { { q = 13, r = 13, p = 1 }, { q = 23, r = 23, p = 1 } } } }
```
<!-- => {"x": {"y": [{"q": 13, "r": 13, "p": 1}, {"q": 23, "r": 23, "p": 1}]}} -->

Putting a command in **key** position (or, for `$APPLY`, directly under a map)
is an error — commands must be list values:

<!-- example: transform/apply#badkey -->
```lua
struct.transform({}, { x = '`$APPLY`' })
-- errors: $APPLY: invalid placement in parent map, expected: list.
```
<!-- throws: invalid placement in parent map -->

### Builders

```lua
struct.jm(...)   -- map (JSON object)
struct.jt(...)   -- list (JSON array)
```

```lua
struct.jm('a', 1, 'b', 2)        -- { a = 1, b = 2 } with array metatable
struct.jt(1, 2, 3)               -- { 1, 2, 3 } with array metatable
```

### Injection helpers

```lua
struct.checkPlacement(modes, ijname, parentTypes, inj)
struct.injectorArgs(argTypes, args)
struct.injectChild(child, store, inj)
```


## Constants

### Sentinels

```lua
struct.SKIP
struct.DELETE
```

### Type bit-flags

```lua
struct.T_any   struct.T_noval   struct.T_boolean   struct.T_decimal
struct.T_integer   struct.T_number   struct.T_string   struct.T_function
struct.T_symbol   struct.T_null   struct.T_list   struct.T_map
struct.T_instance   struct.T_scalar   struct.T_node
```

### Walk / inject phase flags

```lua
struct.M_KEYPRE   struct.M_KEYPOST   struct.M_VAL
struct.MODENAME
```


## Transform commands

```
$DELETE  $COPY    $KEY     $META    $ANNO
$MERGE   $EACH    $PACK    $REF     $FORMAT  $APPLY
```


## Validate checkers

```
$MAP   $LIST   $STRING   $NUMBER   $INTEGER   $DECIMAL  $BOOLEAN
$NULL  $NIL    $FUNCTION $INSTANCE $ANY       $CHILD    $ONE     $EXACT
```


## Notes

### One container type, two roles

Lua tables are unified: a "list" and a "map" are both tables.  The
port distinguishes them via the `__jsontype` metatable field
(`'array'` vs `'object'`).  `ismap` and `islist` consult this field;
`stringify` and `jsonify` use it when serialising.

When you build a table from Lua literals, hint with:

```lua
setmetatable(t, { __jsontype = 'array' })
```

Or use the `jt(...)` / `jm(...)` builders.

### 1-based vs 0-based indexing

Lua arrays are 1-based natively.  The external API still presents
0-based indexing for consistency with the canonical API:
`getpath(list, '0')` returns the first element, even though
internally the list is stored at index 1.  The translation happens
inside the port.

### `items()` returns paired tables

`items()` returns `{ {key, val}, ... }` (table-of-tables) rather
than `[[key, val], ...]` (array-of-arrays), matching Lua idioms.
The keys and values match canonical positions.

### `escre` escapes Lua patterns

Lua does not have full PCRE; it has Lua patterns.  `escre` escapes
the metacharacters used in Lua patterns, not in PCRE.  The function
exists for callers handing the result to `string.match` /
`string.gsub`.

### `nil` is "absent"

Lua has no separate undefined keyword; `nil` covers both "absent"
and "JSON null".  Where the test corpus needs to distinguish them,
the runner uses string sentinels.

### Lists are mutable in place

Lua tables are reference types, so the canonical "lists are
reference-stable" assumption holds without a wrapper.

### Test status

75/75 tests pass against the shared corpus.


## Regex

Uniform six-function regex API (see `/design/REGEX_API.md`). The Lua port
**ships its own RE2-subset engine** in `src/regex.lua` (~500 LOC of
pure Lua — Lua's built-in pattern language is intentionally not
regex, so we vendor one). No LuaRocks dependency, no FFI.

### API

| Function | Returns |
|---|---|
| `re.re_compile(pattern)`              | compiled regex object |
| `re.re_test(pattern, input)`          | `true` / `false` |
| `re.re_find(pattern, input)`          | `{whole, group1, …}` or `nil` |
| `re.re_find_all(pattern, input)`      | `{ {whole, group1, …}, … }` |
| `re.re_replace(pattern, input, repl)` | `string` |
| `re.re_escape(literal)`               | `string` |

### Dialect

The in-tree engine implements the RE2 subset documented in
`/design/REGEX.md`: literals + escapes, `.`, `^`/`$`, `* + ? {n} {n,} {n,m}`
(greedy + lazy), classes incl. `\d \w \s` and friends, `\b`/`\B`,
`(...)` / `(?:...)`, alternation.

**Not supported** (by design — RE2 doesn't either): backreferences,
lookaround, possessive quantifiers, atomic groups. Backref patterns
compile (the parser treats `\1` as a literal `1`) but never match
back-reference semantics, so `re.re_test("^(a+)\\1$", "aaaa")` returns
`false`. Don't rely on this — write portable patterns.

### Sharp edges (Lua-specific)

- **It's a Lua VM regex engine.** P7 (`a{0,10000}b$`) takes ~80 ms
  here — fine functionally, slow versus native engines. The library's
  hot paths don't use bounded quantifiers anywhere near that size.
- **No catastrophic backtracking.** Thompson-NFA construction; P1/P2
  finish in microseconds.
- **Zero-width `re_replace`.** `re.re_replace("a*", "abc", "X")`
  returns `"XXbXcX"` — the convention shared with PCRE/ECMA/Java/.NET
  and the other in-tree Thompson ports (Rust / C / Zig). Go (RE2)
  returns `"XbXcX"` instead. (Pre-fix the Lua engine produced
  `"XaXbXcX"`; the `OP_MATCH` handler in `regex.lua` is now
  priority-correct, matching the C port's fix.)

See `/design/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


## Build and test

```bash
cd lua
make test
```

Or manually:

```bash
export LUA_PATH="./src/?.lua;./test/?.lua;./?.lua;$LUA_PATH"
busted test/struct_test.lua
```

Tests live in [`test/struct_test.lua`](./test/struct_test.lua) and
consume fixtures from [`../build/test/`](../build/test/).


## Directory layout

```
.
├── makefile
├── setup.sh                # bootstrap script (lua + luarocks deps)
├── struct.rockspec
├── src/
│   └── struct.lua          # the library
└── test/
    ├── runner.lua          # JSONIC test driver
    └── struct_test.lua     # busted suite
```
