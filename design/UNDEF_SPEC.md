# Absent vs Null — Uniform Cross-Port Semantics (Revised)

> **What this is.** A specification for how every port of voxgig-struct
> handles three states — *absent*, *JSON null*, and *any other value*
> — given two hard constraints:
>
> 1. Most languages cannot reliably distinguish JSON null from "no
>    value" at the value level.
> 2. The test corpus is plain JSON parsed with each language's
>    standard parser.
>
> This draft replaces the earlier two drafts. The corrections from
> review:
>
> - `setprop(p, k, null)` **literally sets**; it does not delete.
>   `delprop(p, k)` is the only deletion API. If the host language's
>   own semantics turn "set to nil" into "delete" (Lua), that's the
>   language's behaviour, not the library's.
> - Goal: **the test runner has one unified code path for every
>   test.** No per-test null-substitution flags. No NULLMARK/markers
>   inserted into corpus input. No ad-hoc "replace nulls here, don't
>   replace them there."
>
> Companion to `UNDEF.md` (native language semantics).

## Library semantics: per-function

The library's public functions split into two groups based on how
they treat JSON null. The split is principled — observation
functions ask "is there a meaningful value at this slot?" and treat
null as "no", while mutation/inspection functions treat null as a
real, distinct value.

### Group A — "is there a value?" — null is absent

These functions cannot reliably distinguish null from absent on input
across all 13 host languages. They treat the two as identical:

| Function | null behaviour |
|---|---|
| `getprop(obj, k, alt)` | If `obj[k]` is absent **or** null, return `alt`. |
| `getelem(arr, i, alt)` | If `arr[i]` is out of range **or** null, return `alt`. (Lists are positional, so "out of range" rather than "absent".) |
| `haskey(obj, k)` | true only if `obj[k]` is present **and not null**. |
| `isempty(v)` | true if v is null, absent, empty string, empty list, empty map. |
| `isnode(v)` | false for null, false for absent. |

This is the change from canonical TS: today's canonical
`getprop({a:null}, 'a', 'D')` returns `null`; under this spec it
returns `'D'`. Same for `haskey({a:null}, 'a')`: returns `false`
where today's canonical returns `true`.

### Group B — value-processing functions — null is a value

These functions either explicitly inspect or transform values; they
treat null as a legitimate, distinct value (matching today's
canonical TS):

| Function | null behaviour |
|---|---|
| `setprop(p, k, v)` | Literally assigns `v` at `k`. If `v` is null, the slot is set to null. *Side note: in Lua, the language collapses `t[k] = nil` to delete; that's the language's behaviour, not a library choice.* |
| `delprop(p, k)` | The only deletion API. Removes the key regardless of its value. |
| `setval(inj, v)` | Mirrors `setprop`. |
| `clone(v)` | Preserves null (deep copy returns null where the source was null). |
| `stringify(v)` | `stringify(null)` returns `"null"`. |
| `jsonify(v)` | `jsonify(null)` returns `"null"`. |
| `pad(v, w)` | `pad(null, 6)` returns `"null  "`. |
| `typify(v)` | `typify(null)` returns `T_SCALAR \| T_NULL`. Distinct from `T_NOVAL`. |
| `walk(v, …)` | Calls the callback with null where null appears. |
| `merge([…])` | Null values are merged just like any other scalar. |
| `inject / transform / validate / select` | Pass null through to whatever the per-spec rule dictates; each transform command / validate checker has its own behaviour documented separately. |

The principle: **observation conflates, mutation/inspection
preserves.**

## The three states in the test corpus

To verify the library actually behaves per Group A's rules, the
corpus must encode all three states distinctly. JSON itself does
two of them natively:

- **VALUE**: any JSON value.
- **NULL**: literal `null` in the JSON.
- **ABSENT**: in a map-value position, the key is simply omitted.

The one position JSON syntax cannot express ABSENT is "everywhere
that isn't a map-value position" — root values, list slots, and
function-arg positions in a test input record. For those positions
the corpus uses **one** marker string: `"__UNDEF__"`.

That's the entire marker surface. No `__NULL__`, no `__EXISTS__`, no
output-side markers. The corpus is plain JSON plus one input-only
marker.

## Runner preprocessing — a single pass

After the corpus is parsed by the language's standard JSON parser,
the runner walks the parsed tree exactly once and applies one rule:

```
preprocess(value):
    if value is the string "__UNDEF__":
        return REMOVE_MARKER          # parent drops this slot
    if value is a map:
        out = {}
        for k, v in items(value):
            pv = preprocess(v)
            if pv is REMOVE_MARKER:
                continue              # key dropped entirely
            out[k] = pv
        return out
    if value is a list:
        out = []
        for v in value:
            pv = preprocess(v)
            if pv is REMOVE_MARKER:
                continue              # slot removed; indices shift
            out.append(pv)
        return out
    return value                       # primitives unchanged
```

Root-level `"__UNDEF__"` is whatever the runner needs for that
position — typically the language's native null/nil/None, because
that's how the library represents NO-VALUE at function-arg
positions on the receiving side. The Group A functions already
unify null and absent, so passing the language's null in for a
"truly absent" test produces the same result as actually having
nothing.

**That is the entire preprocessing pipeline.** No per-test flags.
No marker substitution into the library's value space. No fixups on
the output side. One walk, one rule.

## Test comparison — strict structural equality

The runner's `deep_equal(actual, expected)` is plain structural
equality. No special-casing of null vs absent. No NULLMARK round-
trip. Same rule for every test:

- Two values are equal if they are the same primitive, or two
  lists of equal length with element-wise equal elements, or two
  maps with the same key set whose values are pairwise equal.
- Null equals null. Absent-key vs null-value: **not** equal.

The runner makes no comparison concessions to Lua's "set-nil =
delete" quirk. **The corpus is written so that tests don't hit that
quirk.** See "Writing portable tests" below.

## Writing portable tests

Two rules for corpus authors:

1. **Test observable behaviour, not raw structure.** Instead of
   asserting "after `setprop(p, 'b', null)` the result is
   `{a:1, b:null}`", assert the observable: `getprop(result, 'b',
   'X')` returns `'X'`, `haskey(result, 'b')` returns `false`. Those
   assertions hold under both TS canonical's literal-set semantics
   AND Lua's set-nil-deletes-the-key semantics, because the Group A
   rules already conflate null and absent.

2. **Don't put nulls in mid-list positions in expected output.** A
   list `[1, null, 3]` is a fine *input* (it tests value-preservation
   through transforms), but expecting it as *output* of a function
   that round-trips through a Lua table would fail in Lua only.
   Either test the elements via `getelem` indices, or use a
   non-null placeholder.

These rules let the runner stay free of comparison hacks. They
don't restrict what the library can do — they restrict how tests
*assert* what the library does, in a way that's portable.

## Conformance test category

`build/test/sentinels.jsonic` exercises Group A's rules with the
three states side-by-side:

```jsonic
sentinels: {

  # getprop: null and absent both yield alt.
  getprop_unify: {
    set: [
      { in: { val:{a:1},    key:'a', alt:'D' }, out: 1   }
      { in: { val:{a:null}, key:'a', alt:'D' }, out: 'D' }
      { in: { val:{},       key:'a', alt:'D' }, out: 'D' }
    ]
  }

  # getelem on a list slot, with __UNDEF__ removing the slot entirely
  # so index 0 reaches the next element.
  getelem_absent: {
    set: [
      { in: { val:[10,20],          key:0, alt:'D' }, out: 10  }
      { in: { val:[null,20],        key:0, alt:'D' }, out: 'D' }
      { in: { val:['__UNDEF__',20], key:0, alt:'D' }, out: 20  }
    ]
  }

  # haskey: null counts as no-value.
  haskey_unify: {
    set: [
      { in: { src:{a:1},    key:'a' }, out: true  }
      { in: { src:{a:null}, key:'a' }, out: false }
      { in: { src:{},       key:'a' }, out: false }
    ]
  }

  # isempty: null and absent and empty containers all empty.
  isempty_unify: {
    set: [
      { in: null,          out: true  }
      { in: '',            out: true  }
      { in: [],            out: true  }
      { in: {},            out: true  }
      { in: 0,             out: false }
      { in: 'a',           out: false }
      { in: [1],           out: false }
    ]
  }

  # setprop: literal. setprop(p,k,null) sets to null; the slot remains.
  # Test the observable behaviour, not the raw shape (Lua-portable).
  setprop_literal: {
    set: [
      # After setting key 'b' to null, haskey returns false (null = no value).
      { in: { parent:{a:1}, key:'b', val:null },
        out: { observe_haskey_b: false, observe_haskey_a: true } }
      # After delprop, same.
      { in: { parent:{a:1, b:2}, key:'b', val:'__delete_via_delprop__' },
        out: { observe_haskey_b: false, observe_haskey_a: true } }
    ]
  }

  # stringify treats null as a value, not as no-value.
  stringify_null: {
    set: [
      { in: null, out: 'null' }
    ]
  }
}
```

Three side-by-side input cases for each Group A function expose any
port that fails the unification. The setprop_literal entry uses an
indirection — observe haskey on the result rather than asserting
the result's raw shape — so it passes in every port including Lua.

## Rollout

The rollout from this draft:

1. **Canonical TS.** Update `getprop` and `haskey` so they treat
   null at a key as equivalent to absent:
   ```ts
   function getprop(val, key, alt) {
     let out = alt
     if (NONE === val || NONE === key) return alt
     if (isnode(val)) out = val[key]
     if (null == out) return alt    // was: NONE === out
     return out
   }

   function haskey(val, key) {
     const v = getprop(val, key)
     return NONE !== v && null !== v
   }
   ```
   Other functions (`setprop`, `stringify`, `typify`, etc.) are
   unchanged.

2. **Python.** Partially revert the recent fixes:
   - `getprop({a:None}, 'a', alt)` returns `alt` (the most recent fix
     returns `None`; that was wrong — it's the right answer for "key
     present with value" but not for the unified Group A rule).
   - `setprop(p, 'a', None)` literally sets `p['a'] = None`. The
     "delete on None" branch is gone.
   - `setval` is just `setprop` again (no delete-on-undef shortcut).
   - `pad(None, 6)` returns `"null  "` (the recent fix added this;
     keep it — `pad` is Group B).
   - `stringify(None)` returns `"null"`. (Likewise Group B.)

3. **Lua.** Drop the `pad(nil) -> "null"` workaround if/when the
   Group A rules are uniformly enforced. Lua's `string.match` /
   table-can't-store-nil quirks are already accepted as part of
   the rules above ("test observable behaviour, not raw structure").

4. **PHP / Ruby / Go.** Stop pretending to maintain an explicit
   UNDEF sentinel where it doesn't help. The few internal uses
   (e.g., `S_BANNO` deletion in Py's transform commands) should
   call `delprop` explicitly rather than `setprop(parent, key, null)`.

5. **rs / zig / cpp / c / java / cs / kt.** Internal `Noval` /
   `monostate` / `VS_VAL_UNDEF` variants are fine for inject-state
   bookkeeping. They must not leak through the public API in a way
   that distinguishes them from null on Group A function returns.

6. **Test runner.** Remove the `null:true` / `null:false` per-test
   flag. Remove NULLMARK conversion. Apply the single preprocess
   pass above. Use strict structural deep-equal.

7. **Add `sentinels.jsonic`** as a conformance category. A port
   passing it demonstrates the unification.

## What this design preserves

- `setprop` is symmetric with the host language's "set". It's not
  the library's job to redefine assignment.
- `delprop` is the explicit deletion API. Anyone wanting to delete
  calls it directly.
- The library makes no claims that exceed what every host language
  can deliver: GET-side null and absent are unified because they
  *have to be* in Py/Lua/PHP/Go/Rb. Mutation-side null is preserved
  literally because it *can be* in every language except Lua's
  table-as-map case — and that one case is handled by the "test
  observable behaviour" rule rather than by runner machinery.
- The runner has no special-cases. One preprocess. One compare.

## What this design gives up

- Canonical TS today returns `null` from `getprop({a:null}, 'a',
  alt)`. This spec changes that to return `alt`. Existing clients
  that relied on the old behaviour and pass `alt = some-sentinel`
  to detect "key absent" while accepting null-as-value will break.
  Migration: use `haskey` to distinguish, or rely on the new
  unified semantics.

- The `$ANY` validator on null input becomes ambiguous: is the
  null preserved (canonical) or treated as absent and the slot
  defaulted? **Decision: each validate checker documents its own
  null behaviour.** `$ANY` accepts null as a value and preserves
  it on output (Group B); `$STRING` rejects null with a type error;
  `$NIL` accepts null specifically. The validate framework as a
  whole sits in Group B.

## TL;DR

- Two function groups:
  - **A (observation):** `getprop`, `getelem`, `haskey`, `isempty`,
    `isnode`. **null counts as absent.**
  - **B (everything else):** `setprop`, `delprop`, `clone`,
    `stringify`, `jsonify`, `pad`, `typify`, `walk`, `merge`,
    `inject`, `transform`, `validate`, `select`. **null is a real
    value.**
- The test corpus is plain JSON. The only marker is `"__UNDEF__"`,
  used only to encode ABSENT in positions JSON can't express it
  (root, list slot, function arg). The runner preprocesses it in
  one pass before any test runs.
- The runner has no other special-cases: no `null:true/false`
  flag, no NULLMARK round-trip, no on-output marker injection.
  `deep_equal` is strict structural equality.
- Tests are written to **assert observable behaviour** (via Group A
  functions) rather than raw structural shape, so Lua's "set-nil
  deletes" can't break them.
- Conformance test category `sentinels.jsonic` provides three
  side-by-side cases per Group A function and verifies any port
  unifies null and absent on observation.
