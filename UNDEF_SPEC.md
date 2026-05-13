# Absent vs Null — Uniform Cross-Port Semantics

> **What this is.** A specification for how every port of voxgig-struct
> represents and exchanges three states — *absent*, *JSON null*, and
> *any other value* — so that the shared test corpus is unambiguous,
> the public API behaves the same in every language, and ordinary
> language JSON parsers can be used unchanged with a small
> preprocessing layer on top.
>
> Companion to `UNDEF.md` (which documents what each language can do
> natively) and `REGEX_API.md` / `REGEX.md` (which apply the same
> "uniform-API plus minimal preprocessing" pattern to regex).

## The three states

For every value position the library deals with — map value, list
element, struct field, function parameter, function return — exactly
one of three states applies:

| State | Meaning | Library symbol | JSON serialisation |
|---|---|---|---|
| **VALUE** | The slot holds a concrete value (a string, number, bool, list, map, etc.) | the value itself | the value's JSON form |
| **NULL** | The slot holds JSON `null` as a real value | the language's "null" (or a sentinel — see Lua) | `null` |
| **ABSENT** | The slot has no value at all (key not present / variable unset / return omitted) | the language's `UNDEF` sentinel | the key is omitted entirely |

Both NULL and ABSENT are *empty* (`isempty` returns true for both),
but they are not interchangeable: `getprop({a:null}, 'a')` must
return NULL, `getprop({}, 'a')` must return ABSENT. The test corpus
encodes the difference; every port must preserve it.

## The corpus encoding

The shared corpus (`build/test/test.json`) is plain JSON. JSON can
already express two of the three states directly:

- VALUE: any normal JSON value.
- NULL: literal `null`.
- ABSENT: the key is omitted from the containing object.

That covers most cases. Three positions are not natively expressible
in JSON and need string markers:

1. **An expected output that should be the ABSENT sentinel.** JSON can
   leave the key out of the *containing* object, but if the value
   appears at the root or as a list element, there's no "omit it"
   syntax. Use the marker string `"__UNDEF__"`.

2. **A NULL value in a context where the runner has converted nulls to
   markers.** Some ports' runners replace JSON null with the marker
   `"__NULL__"` so the library never sees the language's native null
   (which would, in those languages, be indistinguishable from
   ABSENT). Use the marker string `"__NULL__"`.

3. **"This key must exist, regardless of value"** in an output
   assertion. Use the marker string `"__EXISTS__"`.

These three markers are the only special-cased strings. They were
chosen to be unlikely to collide with real data; if a test ever needs
to assert on the literal string `"__NULL__"`, escape it (e.g.
`"$__NULL__"`).

## Preprocessing — input side

For every test entry the runner does this *after* JSON-parsing:

```
markers_to_sentinels(value):
    if value is the string "__UNDEF__":
        return UNDEF
    if value is the string "__NULL__":
        return NULL
    if value is a map:
        return {k: markers_to_sentinels(v) for k, v in value.items()}
    if value is a list:
        return [markers_to_sentinels(v) for v in value]
    return value
```

After this pass, the value the library receives has:
- Native JSON nulls → language null (or `JNULL` sentinel in Lua — see below).
- Marker strings → real sentinels.
- Everything else unchanged.

## Preprocessing — output side

When a function's actual output is compared against the corpus's
expected output, the runner does the inverse on both sides:

```
sentinels_to_markers(value):
    if value is UNDEF:
        return "__UNDEF__"
    if value is NULL (or JNULL in Lua):
        return "__NULL__"
    if value is a map:
        return {k: sentinels_to_markers(v) for k, v in value.items()}
    if value is a list:
        return [sentinels_to_markers(v) for v in value]
    return value
```

Then deep-compare. (Or compare the two as compact-JSON strings — the
markers survive JSON round-trip because they're just strings.)

Either side can short-circuit: if the language already distinguishes
absent / null / value at the value level, the runner can compare
directly. The marker form is the lowest-common-denominator that every
port can produce, so it's the canonical comparison form.

## Per-language sentinel implementation

Every port declares a constant `UNDEF` that is:

1. **Identity-distinct from null.** `UNDEF == null` is false; `UNDEF
   is null` is false; `is_undef(null)` is false; `is_null(UNDEF)` is
   false.
2. **Identity-distinct from every other library value.** The sentinel
   is a singleton — `UNDEF == UNDEF` is true; `UNDEF == anything_else`
   is false.
3. **Identifiable by `is_undef(v)`.** Every port exports an
   `is_undef` / `isUndef` / `IsUndef` predicate matching the port's
   naming convention.

Concrete choice per language:

| Port | UNDEF | NULL |
|---|---|---|
| ts / js | `undefined` | `null` |
| py | a `class _Undef:` singleton instance | `None` |
| go | `var UNDEF = struct{ _voxgig_undef bool }{}` (a singleton struct value, or a `*sentinel` shared address) | `nil` |
| rb | `UNDEF = Object.new.freeze` | `nil` |
| php | `class _Undef {} ; UNDEF = new _Undef()` (and an `array_key_exists` style API at map sites) | `null` |
| lua | `UNDEF = setmetatable({}, {__tostring=function() return 'UNDEF' end})` plus the **JNULL sentinel** (see next section) | **JNULL = setmetatable({}, {__tostring=function() return 'JNULL' end})** — Lua tables cannot store nil, so JSON null must be a sentinel value |
| rs | `enum Value::Noval` | `enum Value::Null` |
| java | `static final Object UNDEF = new Object()` | `null` |
| cs | `static readonly object UNDEF = new()` | `null` |
| cpp | `std::monostate{}` (a variant alternative) | `nullptr_t` (another alternative) |
| kt | `val UNDEF: Any = Any()` | `null` |
| zig | `Value{ .noval = {} }` variant | `Value{ .null = {} }` variant |
| c | `VS_VAL_UNDEF` tagged enum case | `VS_VAL_NULL` tagged enum case |

The crucial property is that `is_undef(v)` checks **object identity**
(via `===`, `is`, `===` again in Ruby, `equal?`, `===` in Kotlin,
pointer identity in C, variant tag in Rust/Zig/C++, etc.), not
structural equality. This rules out cases like Python's old
`UNDEF = None` (where `==` could not distinguish them) and PHP's
old `'__UNDEFINED__'` string (where a JSON corpus containing that
exact string would be misinterpreted).

## Lua's JNULL — the special case

Lua tables literally cannot hold `nil` as a value: assignment is
equivalent to deletion. Therefore JSON `null` cannot survive a
round-trip through a Lua table using native nil. Required behaviour:

1. The Lua JSON parser produces `JNULL` (a unique sentinel table) for
   every JSON `null` it sees.
2. Every library function that distinguishes null from undef does so
   by checking against the `JNULL` sentinel — not against `nil`.
3. The Lua JSON serializer converts `JNULL` back to JSON `null`.
4. Lua's `nil` is reserved for the `UNDEF` semantic (and for "this
   variable simply isn't bound").

`is_null(v)` returns `true` only when `v == JNULL` (table identity).
`is_undef(v)` returns `true` when `v == nil` *or* `v == UNDEF`
(because Lua has no other choice for unbound names). Both queries
remain disjoint.

The same pattern applies to any future port whose host language has
the "no nil in containers" property.

## Public-API behaviour table

These are the contract every port must satisfy. `U` denotes the
language's UNDEF sentinel; `N` denotes its NULL representation; `V`
is any non-empty value.

| Call | Input | Returns |
|---|---|---|
| `getprop({a:V}, 'a')` | key present, value V | V |
| `getprop({a:N}, 'a')` | key present, value NULL | N (**not** U, **not** alt) |
| `getprop({}, 'a')` | key absent | U (or alt if supplied) |
| `getprop({a:V}, 'a', alt)` | key present, value V | V |
| `getprop({}, 'a', alt)` | key absent | alt |
| `getprop({a:N}, 'a', alt)` | key present, value NULL | **N** (not alt — null is a real value) |
| `haskey({a:N}, 'a')` | key present, value NULL | true |
| `haskey({}, 'a')` | key absent | false |
| `setprop(p, 'a', V)` | sets a→V | p (with a=V) |
| `setprop(p, 'a', N)` | sets a→NULL | p (with a=NULL) |
| `setprop(p, 'a', U)` | "set to undef" | **equivalent to delprop**; key removed |
| `setval(inj, U)` | same logic in the Injection setter | delete |
| `setval(inj, N)` | sets the slot to NULL | the value is N |
| `delprop(p, 'a')` | removes key | p (a gone) |
| `isempty(U)` | | true |
| `isempty(N)` | | true |
| `isempty('')` / `isempty([])` / `isempty({})` | | true |
| `isnode(N)` | | false |
| `isnode(U)` | | false |
| `typify(U)` | | `T_NOVAL` |
| `typify(N)` | | `T_SCALAR \| T_NULL` |
| `is_undef(U)` | | true |
| `is_undef(N)` | | false |
| `is_null(N)` | | true |
| `is_null(U)` | | false |
| `clone(N)` returns a value v such that `is_null(v)` | | true |
| `clone(U)` returns a value v such that `is_undef(v)` | | true |
| `stringify(U)` | | `""` (empty) |
| `stringify(N)` | | `"null"` |
| `pad(U, 6)` | | `"      "` (6 spaces — empty string padded) |
| `pad(N, 6)` | | `"null  "` (stringify(NULL) padded) |

The Python and Lua ports failed two of the `null`-related rows above
(`getprop({a:N},'a')` → `N`; `pad(N,6)` → `"null  "`) before this
branch's surgical fixes — the conflation `UNDEF == NULL` made them
indistinguishable. Codifying the table here makes those bugs
catchable by a single shared conformance test (see below).

## JSON I/O contract

Every port exposes two JSON entry points whose behaviour is fixed:

```
parse_json(text) -> value
    JSON null               -> NULL (or JNULL in Lua)
    Missing key             -> not present in the parsed map (no marker emitted)
    All other JSON          -> the obvious native representation

to_json(value) -> text
    UNDEF                   -> if a map value, omit the key; if at root or list slot, emit "null"
    NULL / JNULL            -> emit "null"
    Other                   -> the obvious JSON form
```

The "if a map value, omit the key" rule is the inverse of the JSON
encoding rule for ABSENT. It's the only place `to_json` can encode
ABSENT, because list slots and root values cannot be "absent" in
JSON syntax.

## Test-corpus authoring rules

When adding tests:

1. **Default behaviour.** Write tests as plain JSON. A `null` is
   JSON null; omitting a key means the key is absent. The runner's
   preprocessing pipeline converts these to the language's sentinels.

2. **Need to express the UNDEF sentinel as a value?** Write the string
   `"__UNDEF__"`. The input preprocessor replaces it with U before
   the library sees it. The output preprocessor replaces U with
   `"__UNDEF__"` before comparison.

3. **Need to express JSON null as a value in marker-mode tests?**
   Write the string `"__NULL__"`. Same input/output substitution
   rules apply.

4. **Need to assert "this key must exist, value irrelevant"?** Write
   `"__EXISTS__"` in the expected output.

5. **Choose the runner mode per category.** Most tests run with
   marker substitution enabled (`null:true`) — this is the most
   portable mode. Tests that specifically exercise null-handling
   (`stringify(null)`, `pad(null,6)`, `typify(null)`, `isnull(null)`)
   use `null:false` and operate on the language's native null
   directly.

6. **Lua caveat.** Tests that put null into a list slot and expect to
   read it back unchanged will only pass in Lua if the JSON parser
   was wired up to produce JNULL (not nil). The Lua port's runner
   handles this automatically.

## Shared conformance test

To make the API table mechanically checkable, add a category
`build/test/sentinels.jsonic` exercising each row of the table:

```jsonic
sentinels: {
  is_undef: {
    set: [
      { in: '__UNDEF__', out: true }
      { in: '__NULL__',  out: false }
      { in: 0,           out: false }
      { in: '',          out: false }
      { in: '__EXISTS__', out: false }   # only meaningful in expected-output
    ]
  }

  is_null: {
    set: [
      { in: '__UNDEF__', out: false }
      { in: '__NULL__',  out: true }
      { in: 0,           out: false }
      { in: '',          out: false }
    ]
  }

  getprop: {
    set: [
      { in: { val: {a: 1},          key: 'a' }, out: 1 }
      { in: { val: {a: '__NULL__'}, key: 'a' }, out: '__NULL__' }
      { in: { val: {},              key: 'a' }, out: '__UNDEF__' }
      { in: { val: {a: '__NULL__'}, key: 'a', alt: 99 }, out: '__NULL__' }
      { in: { val: {},              key: 'a', alt: 99 }, out: 99 }
    ]
  }

  haskey: {
    set: [
      { in: { src: {a: '__NULL__'}, key: 'a' }, out: true }
      { in: { src: {a: 1},          key: 'a' }, out: true }
      { in: { src: {},              key: 'a' }, out: false }
    ]
  }

  setprop: {
    set: [
      # setprop(parent, key, UNDEF) deletes the key.
      { in: { parent: {a: 1, b: 2}, key: 'b', val: '__UNDEF__' },
        out: { a: 1 } }
      # setprop(parent, key, NULL) sets the key to JSON null.
      { in: { parent: {a: 1}, key: 'b', val: '__NULL__' },
        out: { a: 1, b: '__NULL__' } }
    ]
  }

  isempty: {
    set: [
      { in: '__UNDEF__', out: true }
      { in: '__NULL__',  out: true }
      { in: '',          out: true }
      { in: [],          out: true }
      { in: {},          out: true }
      { in: 0,           out: false }   # 0 is a value, not empty
    ]
  }

  typify: {
    set: [
      { in: '__UNDEF__', out: 1073741824 }     # T_NOVAL
      { in: '__NULL__',  out: 4194432  }       # T_SCALAR | T_NULL
    ]
  }

  stringify: {
    set: [
      { in: { val: '__UNDEF__' }, out: '' }
      { in: { val: '__NULL__'  }, out: 'null' }
    ]
  }

  pad: {
    set: [
      { in: { val: '__UNDEF__', pad: 6 }, out: '      ' }
      { in: { val: '__NULL__',  pad: 6 }, out: 'null  ' }
    ]
  }
}
```

A port passing this category demonstrates conformance with the
sentinel spec. The Python and Lua ports' fixes in this branch would
be caught by this category if the corpus included it.

## Rollout

The mechanical changes implied by this spec:

1. **Adopt a new shared corpus category** (`sentinels.jsonic` per
   above). This is the conformance test.

2. **Document the markers** (`__UNDEF__`, `__NULL__`, `__EXISTS__`) at
   the top of `build/test/test.jsonic` so authors don't have to read
   this spec to find them.

3. **Port-by-port audit.**
   - **ts, js, rs, java, cs, cpp, kt, zig, c**: already conformant.
     Just verify the conformance category passes.
   - **rb**: should be conformant (already uses `UNDEF = Object.new.freeze`); verify.
   - **php**: has the string `'__UNDEFINED__'` plus a `stdClass`
     instance. Pick one for `UNDEF` and document. Probably the
     stdClass instance (string sentinels can collide with corpus
     data).
   - **go**: define `var UNDEF struct{}` (a unique struct instance)
     and update internal call sites that currently use `nil` as
     both. Map-level absent-detection remains via the comma-ok
     idiom.
   - **py**: replace `UNDEF: Any = None` with a sentinel object.
     The surgical fixes in this branch (`getprop`, `setval`,
     `setprop`, `pad`) are correct workarounds, but with a real
     sentinel they become principled. ~191 references to update,
     mostly mechanical (`val == UNDEF` → `val is UNDEF` is already
     correct usage).
   - **lua**: introduce the `JNULL` sentinel. Wire it into the JSON
     parser. Update `is_null` / `is_undef` / `clone` / `stringify`
     / `pad` accordingly. This is the most invasive port-side
     change but the cleanest.

4. **Tests' default null-flag.** Keep the existing `null:true`/
   `null:false` per-category flags. The new markers compose with
   them; nothing changes for tests that don't need the distinction.

After this, every port can be diff-read against canonical TS for
sentinel handling, and a new test that exercises the corner case
catches regressions in every port simultaneously.

## TL;DR

- Define three states: VALUE, NULL, ABSENT. Every port must
  distinguish them.
- Each port picks a sentinel for ABSENT (`UNDEF`) that is identity-
  distinct from its NULL. Lua additionally picks a sentinel for NULL
  (`JNULL`) because Lua tables can't store nil.
- The shared corpus uses plain JSON (which encodes VALUE / NULL / ABSENT
  natively) plus three reserved marker strings — `"__UNDEF__"`,
  `"__NULL__"`, `"__EXISTS__"` — for the few corner cases JSON
  syntax can't express.
- The test runner's preprocessing pipeline translates between markers
  and sentinels in both directions. Library code only sees real
  sentinels; the corpus never sees them.
- A shared conformance category (`sentinels.jsonic`) makes the
  contract mechanically testable.
