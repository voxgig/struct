# Struct for Lua

> Full-parity Lua port of the canonical TypeScript implementation.

For the language-neutral overview, motivation, and concepts, see the
[top-level README](../README.md).  For build / test setup specifics
see [`README.md`](./README.md).

These docs follow the [Diataxis](https://diataxis.fr/) framework.


## Tutorial: your first transform

### Install

The module is a single file: [`src/struct.lua`](./src/struct.lua).
Tests use LuaRocks; see [`README.md`](./README.md) for full setup.

```bash
cd lua
make setup       # installs lua + luarocks deps
```

### A first transform

```lua
package.path = './src/?.lua;' .. package.path
local struct = require('struct')

local data = {
  user = { first = 'Ada', last = 'Lovelace' },
  age  = 36,
}

local spec = {
  name    = '`user.first`',
  surname = '`user.last`',
  years   = '`age`',
}

local out = struct.transform(data, spec)
-- out == { name = 'Ada', surname = 'Lovelace', years = 36 }
```

### Validate

```lua
struct.validate(out, {
  name    = '`$STRING`',
  surname = '`$STRING`',
  years   = '`$INTEGER`',
})
```


## How-to recipes

### Read a deep value safely

```lua
struct.getpath(config, 'db.host')
struct.getprop(node, 'count', 0)
struct.getdef(maybe, 'fallback')
```

### Set a deep value

```lua
local store = {}
struct.setpath(store, 'db.host', 'localhost')
-- store.db.host == 'localhost'
```

### Merge configs

```lua
local cfg = struct.merge({ defaults, file, env })
```

### Walk a tree

```lua
-- walk takes optional before/after callbacks.
struct.walk(tree, nil, function(key, val, parent, path)
  if val == nil then
    return 'DEFAULT'
  end
  return val
end)
```

### Inject and select

```lua
struct.inject(
  { greeting = 'hello `name`' },
  { name = 'Ada' }
)

struct.select(records, { age = 30 })
```


## Reference

Source: [`src/struct.lua`](./src/struct.lua).

### Module shape

```lua
return {
  -- 41 functions
  clone, delprop, escre, escurl, filter, flatten, getdef, getelem,
  getpath, getprop, haskey, inject, isempty, isfunc, iskey, islist,
  ismap, isnode, items, join, jsonify, keysof, merge, pad, pathify,
  replace, select, setpath, setprop, size, slice, strkey, stringify,
  transform, typify, typename, validate, walk, jm, jt,
  checkPlacement, injectorArgs, injectChild,

  -- sentinels and constants
  SKIP, DELETE,
  T_any, T_noval, T_boolean, T_decimal, T_integer, T_number,
  T_string, T_function, T_symbol, T_null,
  T_list, T_map, T_instance, T_scalar, T_node,
  M_KEYPRE, M_KEYPOST, M_VAL,
  MODENAME,
}
```

### Tests

```bash
cd lua
make test           # 75/75 passing
```


## Explanation

### One container type, two roles

Lua tables are unified: a "list" and a "map" are both tables.  The
port distinguishes them with the `__jsontype` metatable field
(`'array'` vs `'object'`).  `ismap` and `islist` consult this field;
`stringify` and `jsonify` use it when serialising.

When you build a table from Lua literals, you can hint with
`setmetatable(t, { __jsontype = 'array' })`, or simply use `jt(...)`
/ `jm(...)` builders.

### 1-based versus 0-based indexing

Lua arrays are 1-based natively.  The external API still presents
0-based indexing for consistency with the canonical API:
`getpath(list, '0')` returns the first element, even though internally
the list is stored at index 1.  The translation happens inside the
port.

`items()` returns Lua tables of the form `{key, val}` rather than
two-element arrays.  The keys and values match the canonical
positions.

### `escre` escapes Lua patterns

Lua does not have full regex; it has Lua patterns.  `escre` escapes
the metacharacters used in Lua patterns, not in PCRE.  The function
exists only for callers that hand the result to `string.match` /
`string.gsub`; downstream regex engines are not affected.

### `nil` is "absent"

Lua has no separate undefined keyword; `nil` covers both "absent"
and "JSON null".  Where the test corpus needs to distinguish them,
the runner uses string sentinels.

### Lists are mutable in place

Lua tables are reference types, so the canonical "lists are
reference-stable" assumption holds without a wrapper.


## Build and test

```bash
cd lua
make setup
make test
```

Tests live in [`test/struct_test.lua`](./test/struct_test.lua) and
consume fixtures from [`../build/test/`](../build/test/).  See
[`README.md`](./README.md) for the original test-runner setup guide.
