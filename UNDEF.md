# UNDEF vs JSON-null Distinguishability — Per-Language Report

> **Question.** When code reads a value from a map (or holds it in a
> variable), can it tell the difference between "the key was never set"
> (TS `undefined`) and "the key was set to JSON null"?
>
> This matters because the canonical TypeScript port treats `NONE` and
> `null` as distinct, and several library behaviours depend on the
> distinction: `getprop` returns `alt` on absent, but the actual value on
> stored null; `setval` only deletes when `val === NONE`; `_validation`
> short-circuits on absent for non-exact validators but rejects on null
> when the type doesn't match. A port that conflates the two will pass
> the basic corpus tests but silently misbehave on edge cases like
> `validate({a:null}, {a:'`$ANY`'})` — which is exactly the bug that
> surfaced in the Python port (`{}` instead of `{a:null}`).

## How each language can / does distinguish

| # | Lang | Built-in distinction? | Map-level test | Variable-level test | Port currently uses |
|---|---|---|---|---|---|
| 1 | **ts** | **native** — `undefined ≠ null` | `key in obj`, `obj[k] === undefined` | `=== undefined` | `const NONE = undefined` |
| 2 | **js** | **native** — same as TS | same | same | `const NONE = undefined` |
| 3 | **go** | partial — `nil` is the only "null-ish" value, but maps return `(value, ok)` | `v, ok := m[k]` (the comma-ok pattern) | hard at the value level; use `*T` or sentinel | uses raw `nil`; the port uses NULLMARK string in test corpus only |
| 4 | **rb** | **emulated** — only `nil` natively, but `h.key?(k)` and `h.fetch(k, sentinel)` distinguish | `h.key?(k)`, `h.fetch(k, UNDEF)` | unique-object sentinel | `UNDEF = Object.new.freeze` |
| 5 | **php** | **emulated** — `null` is a value, `isset($a[$k])` returns false for both unset and null-valued, but `array_key_exists($k, $a)` returns true only when present | `array_key_exists` | string sentinel | `UNDEF = '__UNDEFINED__'` string + `$UNDEF` `stdClass` ref |
| 6 | **lua** | **impossible at map level** — assigning `nil` to a table key deletes it; you literally cannot store nil. Variables can hold nil but there's no "absent" variable | use a sentinel table/value to represent stored-null | unique-table sentinel | currently no UNDEF sentinel; uses `nil` (conflated) |
| 7 | **rs** | **native** — `Option<T>` is part of the language. `None` vs `Some(value)`; map `.get(k)` returns `Option<&V>` → `None` for absent | `map.get(k).is_none()` for absent; `Some(&Value::Null)` for stored null | naturally distinct | `enum Value { Noval, Null, ... }` — distinct variants |
| 8 | **zig** | **native** — optional types `?T`. `null` is a value, `?T` carries absence. Maps return `?V` from `.get()` | `?V` from `get()`; `null` distinct from `Some(.null)` | naturally distinct | `JsonValue` union has `null` only (no Noval); port relies on Zig's `?` optionals at the API |
| 9 | **java** | **emulated** — `null` is a value, but `Map.containsKey()` distinguishes presence | `m.containsKey(k)` true even when value is null | unique-object sentinel | `static final Object UNDEF = new Object()` |
| 10 | **cs** | **emulated** — same idea as Java; `Dictionary.ContainsKey()` / `TryGetValue` distinguish | `ContainsKey` / `TryGetValue` | unique-object sentinel | `static readonly object NONE = new()` |
| 11 | **cpp** | **native** — `std::optional<T>` (C++17), `std::variant` with `std::monostate`, `std::any` with `has_value()` | `m.count(k)`, `optional::has_value()` | `monostate` variant alternative | `std::variant<std::monostate, std::nullptr_t, ...>` — distinct |
| 12 | **kt** | **emulated** — null safety doesn't help; `null` is a value. `Map.containsKey()` distinguishes | `m.containsKey(k)` | unique-object sentinel | `val UNDEF: Any = Any()` |
| 13 | **c** | **native** — port models it explicitly | absent: caller's choice of `NULL` pointer or `vs_new_undef()`; stored null: `vs_value*` with `kind == VS_VAL_NULL` | distinct tag | `enum vs_kind { VS_VAL_UNDEF, VS_VAL_NULL, ... }` — distinct |

## What "emulated" means

Languages marked emulated have only one null-like value in the language
proper (`nil`/`null`/`None`), but provide a map API that lets you tell
"key absent" from "key present with null value":

- **rb / java / cs / kt** — `h.key?(k)` / `containsKey()`.
- **php** — `array_key_exists()` (not `isset()`, which returns false for both).
- **go** — comma-ok: `v, ok := m[k]`.

To use the distinction *at the value level* (e.g. in a function return,
a local variable, or as a list element), these languages need a
**sentinel** — a unique object whose identity is checked with `===` /
`is` / `equals(SAME-REF)`. Every port that needs this uses one.

## Which ports currently conflate the two

| Port | UNDEF object | Distinct from null? |
|---|---|---|
| ts, js | `undefined` | ✅ language-native |
| py | `UNDEF = None` | ❌ **same as null** (this was the bug fixed today) |
| go | `nil` | ❌ at value level — only map-lookup distinguishes |
| rb | `UNDEF = Object.new.freeze` | ✅ unique sentinel |
| php | `'__UNDEFINED__'` string | ✅ unique string value |
| lua | (none) | ❌ no sentinel — `nil` is the only marker |
| rs | `Value::Noval` | ✅ enum variant |
| java | `static final Object UNDEF = new Object()` | ✅ unique sentinel |
| cs | `static readonly object NONE = new()` | ✅ unique sentinel |
| cpp | `std::monostate` | ✅ variant alternative |
| kt | `val UNDEF: Any = Any()` | ✅ unique sentinel |
| zig | `?JsonValue` at API boundary; `JsonValue.null` is the only null | ⚠️ partial — language supports `?T` but the JsonValue union itself has no Noval |
| c | `VS_VAL_UNDEF` | ✅ enum variant |

## Recommendations

### Python (highest priority)

`UNDEF = None` is a known cause of the bugs fixed in this branch. **Change to a unique sentinel:**

```python
class _UndefType:
    def __repr__(self): return 'UNDEF'
    def __bool__(self): return False
UNDEF = _UndefType()
```

Then every `val == UNDEF` becomes `val is UNDEF` (identity, not equality). About 191 references, but the change is mostly mechanical. With this in place, `pad(None)` and `stringify(None)` produce `"null"` (right behaviour), `getprop({a:None}, 'a')` returns `None` (right), and the `setval` delete-on-undef logic can be made unambiguous.

Today's fixes worked around this on a per-call-site basis. A central sentinel would let those workarounds go away.

### Lua (next priority)

Lua **cannot store nil in tables** — assignment removes the key. So:

- "Absent" and "stored nil" are *identical* in any Lua table.
- The port currently uses `nil` for UNDEF and never stores null in tables (the corpus's null becomes nil → key vanishes when round-tripped).

If the library ever needs to round-trip JSON containing stored null without dropping the key, define a sentinel:

```lua
local UNDEF = setmetatable({}, {__tostring = function() return "UNDEF" end})
-- And a NULLMARK table value to mean "this slot holds JSON null":
local NULL = setmetatable({}, {__tostring = function() return "null" end})
```

Then map values that came from JSON `null` are stored as the `NULL` sentinel, and the port's `is_null` / `is_undef` / `clone` / `stringify` etc. all special-case both. This is invasive but it's the only way to faithfully round-trip JSON-null through Lua tables.

### Go (low priority for now)

Go's `nil` is a single shared value, but `v, ok := m[k]` distinguishes at map-lookup. As long as internal call sites that need the distinction use the comma-ok pattern, the port is fine. If you want value-level distinction (e.g. functions returning "absent" without a flag), use `*any` (pointer to interface) or a sentinel:

```go
var UNDEF = struct{}{}
```

The corpus today doesn't push Go into this corner; the test runner already special-cases `__NULL__` strings.

### Zig

`JsonValue` currently has no `noval` variant — only `null`. Where the port needs to distinguish, it uses `?JsonValue` (optional) at API boundaries. Workable but inconsistent with the canonical's value-level distinction. **Adding `noval` to the JsonValue union** is a small change and would let internal code mirror the canonical line-for-line.

### Everyone else

The other ports (rb, php, java, cs, cpp, kt, rs, c, ts, js) already represent UNDEF distinctly. No action needed — but it's worth verifying that **internal call sites** use the sentinel consistently. The Python episode showed that even when the language *can* distinguish, the port may still conflate in specific helpers (Python had the sentinel mechanism via `is UNDEF` but `UNDEF = None` and `out == UNDEF` defeated it).

## TL;DR

Of the 13 ports:
- **10 distinguish today** (ts, js, rb, php, rs, java, cs, cpp, kt, c) — either natively or via a unique sentinel object.
- **1 distinguishes only at map level, not value level** (go) — sufficient for the corpus but awkward at the API.
- **1 has a partial mismatch** (zig) — `?JsonValue` at the API but no value variant.
- **1 still conflates** (lua) — language limitation: tables cannot hold nil. Surface-level fixes in today's commits cover the visible cases; a sentinel-based deeper fix is possible but invasive.

**Python** previously conflated (`UNDEF = None`) and was the source of today's bugs; the surgical fixes in `getprop` / `setval` / `pad` get the suite green, but moving to a distinct sentinel is the architecturally correct follow-up.
