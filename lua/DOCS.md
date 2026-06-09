# Struct for Lua — Comprehensive Guide

> A **port** of the canonical TypeScript implementation. Behaviour is
> defined by TypeScript and pinned by the shared corpus; this port follows
> it. This guide is the in-depth companion to [`README.md`](./README.md)
> (quick-start + signature reference) and the language-neutral
> [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — install and learn the whole API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the exact
  Lua semantics.
- **[Explanation](#4-explanation--port-specifics)** — the model, the port's
  role, and Lua-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Install

The library is a single file, [`src/struct.lua`](./src/struct.lua), with a
sibling [`src/regex.lua`](./src/regex.lua). It needs **Lua >= 5.3** and has
**zero third-party runtime dependencies** — only the Lua stdlib. The
test-only deps (`busted`, `luassert`, `dkjson`, `luafilesystem`) are
declared in [`struct.rockspec`](./struct.rockspec).

```bash
cd lua
make setup          # runs ./setup.sh: installs lua/luarocks + test deps
```

Put `src/` on the module path, then `require` the module table:

```lua
package.path = './src/?.lua;' .. package.path
local struct = require('struct')
```

`require('struct')` returns a table; every function is a field on it
(`struct.getpath(...)`), and so is the `StructUtility` class (see
[How-to](#2-how-to-guides)).

### Your first program

```lua
local struct = require('struct')

local config = struct.merge({
  { db = { host = 'localhost', port = 5432 }, debug = false }, -- defaults
  { db = { host = 'db.internal' },            debug = true },  -- overrides
})

struct.getpath(config, 'db.host')   -- 'db.internal'
struct.getpath(config, 'db.port')   -- 5432  (survived the deep merge)
```

### Build up the rest of the API

Each call below has the same meaning in every port; only the syntax
changes. Read [`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the
full language-neutral walkthrough; the Lua-flavoured version:

```lua
local struct = require('struct')

-- Reshape by example — the spec mirrors the output you want.
struct.transform(
  { user = { first = 'Ada', last = 'Lovelace' }, age = 36 },
  { name = '`user.first`', surname = '`user.last`', years = '`age`' }
)
-- { name = 'Ada', surname = 'Lovelace', years = 36 }

-- Validate by example — leaves are type checkers; errors on mismatch.
struct.validate({ name = 'Ada', age = 36 },
                { name = '`$STRING`', age = '`$INTEGER`' })

-- Walk the tree — replace values on ascent.
struct.walk(tree, nil, function(key, val) if val == nil then return 'DEFAULT' end return val end)

-- Select children by query — each match tagged with its $KEY.
struct.select({ a = { age = 30 }, b = { age = 25 } }, { age = 30 })
-- { { age = 30, ['$KEY'] = 'a' } }
```

---

## 2. How-to guides

### Inject the API as an object (for stubbing in tests)
```lua
local struct = require('struct')
local su = struct.StructUtility:new()
su:getpath({ a = { b = 1 } }, 'a.b')   -- 1  (called with ':' — self-style)
```
Every function and constant is also a member of `StructUtility`; the
`:new(o)` constructor sets the metatable so a consumer can override fields
on `o` and still inherit the rest.

### Collect all validation errors instead of erroring
```lua
local errs = {}
struct.validate(payload, spec, { errs = errs })
if #errs > 0 then
  -- report them
end
```
Unlike canonical TS, the optional fourth argument is folded into a single
**`injdef` table**: `validate(data, spec, injdef)` reads `injdef.errs`,
`injdef.extra`, and `injdef.modify`.

### Write a custom transform function (`$APPLY`)
```lua
struct.transform(
  { items = { 1, 2, 3 } },
  { total = { ['`$APPLY`'] = { 'sum', '`items`' } } },
  { extra = { sum = function(resolved, store, inj)
                      local s = 0
                      for _, n in ipairs(resolved) do s = s + n end
                      return s
                    end } }
)
```
Register the function under `injdef.extra`; reference it by name in the
spec. The Lua `$APPLY` function is invoked as `fn(resolved, store, inj)` —
the resolved child value, the injection store, and the child injection
object. A custom function may return the `SKIP` / `DELETE` sentinels to
omit/remove the current key. Function-value signatures are port-local and
covered by unit tests, not the JSON corpus — see [`../NOTES.md`](../design/NOTES.md).

### Keep a `walk` path past the callback
```lua
struct.walk(tree, function(key, val, parent, path)
  local copy = { table.unpack(path) }   -- path is reused — clone to retain it
  seen[#seen + 1] = copy
  return val
end)
```

### Serialise deterministically
```lua
struct.jsonify(value)        -- compact, insertion-ordered keys
struct.jsonify(value, 2)     -- pretty, 2-space indent
struct.stringify(value, 80)  -- truncated human form, for logs
```

For more task recipes (merge configs, rename fields, `$EACH`, `$MERGE`,
`$FORMAT`, `$ONE`, `$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical;
only the host literals differ.

---

## 3. Reference

The full Lua call list, with examples for every function, is in
[`README.md` → Function reference](./README.md#function-reference). The
canonical public surface is the `export { … }` block in the canonical TS;
[`../tools/check_parity.py`](../tools/check_parity.py) checks this port
against it (parity is case/underscore-insensitive). The names exposed on the
returned module table are the definition this port presents.

Lua-specific points the signatures don't show:

- **One container type.** A map and a list are both Lua tables. The port
  tells them apart via the `__jsontype` metatable field (`'object'` vs
  `'array'`); `ismap`/`islist`, `jsonify`, and `stringify` consult it. Build
  tagged tables with `struct.jm(...)` / `struct.jt(...)`, or
  `setmetatable(t, { __jsontype = 'array' })`.
- **0-based external paths.** `getpath(list, '0')` returns the first element
  even though Lua stores it at index 1; the translation is internal.
- **`getprop` vs `getelem`.** `getprop` works on maps and lists; `getelem`
  is list-specific, supports `-1`-from-the-end indexing, and *invokes* a
  callable `alt` when the element is absent.
- **`items` shape.** `items(node)` returns `{ {key, val}, ... }`
  (table-of-pairs), matching Lua idiom rather than the canonical
  array-of-arrays.
- **`walk` extra parameters** (`key`, `parent`, `path`, `pool`) are
  recursion state; callers pass only `(val, before, after, maxdepth)`.
- **`injdef` collapses the trailing args.** `transform`/`validate` take a
  single optional `injdef` table (`{ extra =, errs =, modify = }`) where
  canonical TS spreads `extra`/`modify`/`collecterrs` across parameters.
- **`escre` escapes Lua patterns, not PCRE** — it is for callers handing the
  result to `string.match` / `string.gsub`, distinct from the `re_*` engine
  (see [Regex](#regex)).
- **Type flags** combine bitwise: `typify('hi')` is `T_scalar | T_string`;
  test with `0 < (T_string & t)`. `typify(nil)` is `T_noval` (Lua has no
  separate null), so the `null`-vs-absent split below is muted in Lua.

---

## 4. Explanation & port specifics

### The port's role

TypeScript is canonical; this port is held to the shared corpus in
[`../build/test/`](../build/test/), which is generated to match the
canonical code. Practically:

- A behaviour question is answered by reading the canonical TS and the
  corpus, not by trusting this port in isolation.
- A change to canonical behaviour starts in TypeScript, flows to the corpus,
  and only then reaches Lua (see
  [`../AGENTS.md`](../AGENTS.md#standard-workflows)).

### `nil` is "absent" (Group A)

Lua has only `nil`, which covers both "absent" and "JSON null" — there is no
distinct null value. So the language-neutral
[Group A/B rule](../DOCS.md#null-versus-absent-group-ab) collapses: this port
is **Group A throughout** (a stored `nil` is simply "no value"). Where the
corpus must distinguish a real null from absent, the test runner uses the
string sentinels `"__NULL__"` / `"__UNDEF__"` / `"__EXISTS__"`; the library
itself never sees a separate null. See [`../REPORT.md`](../design/REPORT.md) and
[`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md).

### Lists are reference-stable

`walk`, `merge`, `inject`, and `setpath` rely on lists being mutable and
shared by reference — a mutation through one handle is visible to all. Lua
tables are reference types, so this port needs no `ListRef`-style wrapper
(unlike Go or PHP).

### Regex

Lua's built-in `string` library uses *Lua patterns*, which are intentionally
**not** a regex dialect, so this port **ships its own engine** in
[`src/regex.lua`](./src/regex.lua) (~660 lines of pure Lua, no LuaRocks dep,
no FFI). It is a **Thompson-NFA matcher** — the same construction as the C
port — implementing the **RE2 subset** and wrapped by the uniform
six-function API (`re_compile` / `re_test` / `re_find` / `re_find_all` /
`re_replace` / `re_escape`).

Because it is Thompson NFA there is **no catastrophic backtracking**
(P1/P2 finish in microseconds), and backreferences/lookaround are
unsupported by design (a `\1` parses as a literal `1` and never matches
back-reference semantics — don't rely on it). Two sharp edges: bounded
quantifiers run on the Lua VM and are slow versus native engines
(`a{0,10000}b$` ≈ 80 ms), and zero-width `re_replace` returns `"XXbXcX"`
(the ECMA/PCRE/Java/.NET convention, shared with the other in-tree Thompson
ports Rust/C/Zig; Go's RE2 returns `"XbXcX"`). Details:
[`README.md` → Regex](./README.md#regex) and
[`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md).

---

## Build, test, and extend

From the lowercase [`makefile`](./makefile) in this directory:

```bash
cd lua
make setup           # ./setup.sh — install lua/luarocks + test deps
make test            # busted over test/*test.lua (the shared corpus suite)
make lint            # luacheck src test  +  stylua --check src test
make format-check    # stylua --check src test
make bench           # WALK_BENCH=1 lua test/walk_bench.lua
make clean           # rm luacov.* .busted
```

The corpus suite reports **75/75 cases passing** (per
[`../REPORT.md`](../design/REPORT.md)). Tests live in
[`test/`](./test/); [`test/struct_test.lua`](./test/struct_test.lua) is the
busted suite and [`test/runner.lua`](./test/runner.lua) is the JSONIC driver
that loads the shared corpus from [`../build/test/`](../build/test/).

To run busted directly without make:

```bash
export LUA_PATH="./src/?.lua;./test/?.lua;./?.lua;$LUA_PATH"
busted test/struct_test.lua
```

**This is a port, not the canonical.** To change behaviour, edit the
canonical TypeScript and the corpus first; then mirror the logic here,
`make test` until green, and re-run [`../tools/check_parity.py`](../tools/check_parity.py)
plus the per-port tests. The full cross-port checklist is in
[`../AGENTS.md`](../AGENTS.md). Tooling: Lua 5.3+, LuaRocks, `busted`,
`luacheck`, StyLua (built with the `lua54` feature for 5.3+ bitwise ops).
