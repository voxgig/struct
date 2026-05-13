# Absent vs Null — Uniform Cross-Port Semantics (Corrected)

> **What this is.** A specification for how every port of voxgig-struct
> handles three states — *absent*, *JSON null*, and *any other value*
> — given the hard constraint that most languages cannot reliably
> distinguish JSON null from absent at the value level.
>
> The previous draft of this spec required ports to expose a distinct
> `UNDEF` sentinel through the public API. That assumption was wrong:
> Python, Lua, PHP, Go (and arguably Ruby) cannot enforce that
> distinction without either contaminating returned data with non-JSON
> sentinel objects (forcing all client code to know about them) or
> forcing every API site through awkward boxing types. The corrected
> design accepts the constraint and **moves the distinction entirely
> inside the test corpus**.
>
> Companion to `UNDEF.md` (what each language can do natively).

## The two states the library exposes

For every value position the library deals with — map value, list
element, struct field, function parameter, function return — the
**public API recognises only two observable states**:

| State | Meaning |
|---|---|
| **VALUE** | The slot holds a concrete value (a non-null/non-nil/non-None primitive, list, or map). |
| **NO-VALUE** | The slot is empty. This unifies "key absent", "JSON null", and the language's native null/nil/None. |

This is a deliberate choice. JSON has three states at the syntactic
level (value, null, key omitted) but the library exposes them as two,
because:

- Python, Ruby, Go, PHP, Lua cannot tell `null` from absent at the
  value level without a sentinel object that clients would then have
  to import and identity-check.
- Returning a sentinel from the API leaks an implementation type into
  every client and makes round-tripping through JSON impossible
  (the sentinel can't be serialised back out without ambiguity).
- The behaviours most code wants — "give me a value or a default",
  "is this key meaningful?", "what's the shape of this tree?" —
  treat null and absent identically anyway.

So the API rule is: **the language's native null/nil/None is
synonymous with absent throughout the library's surface.** Clients
who need PATCH-vs-PUT semantics (the rare case where the distinction
genuinely matters) handle it themselves at the protocol layer.

## Public-API behaviour

`X` denotes any non-null value. `NULL` denotes the language's native
null/nil/None.

| Call | Returns |
|---|---|
| `getprop({a:X}, 'a')` | X |
| `getprop({a:NULL}, 'a')` | NULL (which the caller should treat as "no value") |
| `getprop({}, 'a')` | NULL |
| `getprop({a:X}, 'a', alt)` | X |
| **`getprop({a:NULL}, 'a', alt)`** | **alt** — null is treated as absent for the default-substitution rule |
| `getprop({}, 'a', alt)` | alt |
| `haskey({a:X}, 'a')` | true |
| **`haskey({a:NULL}, 'a')`** | **false** — null counts as "no value" |
| `haskey({}, 'a')` | false |
| `setprop(p, 'a', X)` | p with `a = X` |
| **`setprop(p, 'a', NULL)`** | **p with `a` removed** — null means "no value", so deletes |
| `delprop(p, 'a')` | p with `a` removed |
| `isempty(NULL)` | true |
| `isempty('')` / `isempty([])` / `isempty({})` | true |
| `isnode(NULL)` | false |
| `typify(NULL)` | `T_NOVAL` (one bit, the same value the canonical previously gave to undefined) |
| `stringify(NULL)` | `""` (empty — null is "no value", so nothing to stringify) |
| `pad(NULL, 6)` | `"      "` (six spaces — stringify yields empty, then pad) |

This is the single source of truth. Every port satisfies it.

> **Note on the canonical TS.** Today's canonical TS distinguishes
> `undefined` from `null` and returns `null` from
> `getprop({a:null}, 'a', alt)`. To match this spec, the canonical
> TS also needs to be updated so that `getprop({a:null}, 'a', alt)`
> returns `alt`. The change is small (one extra `null ===` test in
> `getprop` and `haskey`, swap `NONE === val` for `null == val` in
> `setval`'s delete check, etc.), but it does mean the canonical's
> ts test corpus needs the same updates other ports' corpora need.
> Treat this as part of the rollout.

## The three states still matter — for testing

Although the library exposes only two states, the **test corpus
must encode all three** so we can verify that the library actually
unifies null and absent into NO-VALUE (rather than silently
preserving one of them). Without separate corpus encodings, you
cannot tell whether a port is correctly conflating them or has a
latent bug that happens to be invisible against the tests you
wrote.

So the corpus needs to express, for any value position:

- VALUE — a concrete JSON value
- NULL — JSON null (the wire-level "value is null" case)
- ABSENT — key omitted (the wire-level "value is missing" case)

And the corpus is parsed using the **language's standard JSON
parser** — we cannot ship a bespoke parser per port. Therefore the
corpus must encode these three states in a way that any JSON parser
can represent. That gives us:

- VALUE: any literal JSON value (e.g. `1`, `"x"`, `[]`).
- NULL: the JSON token `null`. Parsed natively as the language's
  null/nil/None. Same as absent from the library's POV — but the
  test still needs to verify that.
- ABSENT: in a map-value position, omit the key entirely. In any
  other position (root, list slot, function arg), use the **marker
  string `"__UNDEF__"`** which the runner preprocessor removes from
  its parent / treats as absent on the way in.

JSON syntax already gives us VALUE and NULL. The only thing it
cannot express is ABSENT in a non-map-value position. That's what
`"__UNDEF__"` is for.

## Corpus markers

| Marker (string literal) | Meaning in the corpus | After preprocessing |
|---|---|---|
| `"__UNDEF__"` | "this should be ABSENT" | The marker is **removed from its parent**: at a map-value position, the key is deleted; at a list slot, the slot is removed and indices renumber; at the root or a function-arg position, the value is replaced with the language's native null (since that's how the library represents NO-VALUE on return). |
| `"__EXISTS__"` | "in an expected output: assert the key is present, value irrelevant" | Used in expected outputs only; the comparison routine special-cases it. |

That's the entire marker surface. **No `__NULL__` marker is needed**
— JSON null is already JSON null, and the runner can pass it through
to the library unchanged. The library treats it as NO-VALUE because
the API contract says so.

The corpus author writes tests like:

```jsonic
getprop: {
  set: [
    # VALUE case
    { in: { val:{a:1}, key:'a', alt:'D' }, out: 1 }

    # NULL case (JSON null in source data)
    { in: { val:{a:null}, key:'a', alt:'D' }, out: 'D' }

    # ABSENT case (key omitted entirely)
    { in: { val:{}, key:'a', alt:'D' }, out: 'D' }
  ]
}
```

All three tests verify the library does the right thing. The middle
one (NULL) is the case ports historically got wrong by returning
null instead of `'D'`.

And for the rare positions JSON can't express absence in:

```jsonic
# Root-position ABSENT — the library is called with no first arg
# (or the language equivalent). __UNDEF__ tells the preprocessor
# to convert this slot to the language's native null on the way in,
# which the library then treats as NO-VALUE.
{ in: { val: '__UNDEF__', key:'a', alt:'D' }, out: 'D' }

# List-slot ABSENT — the marker is removed from the list during
# preprocessing, so this is equivalent to ['a']:
{ in: { val: ['__UNDEF__', 'a'], key: 0 }, out: 'a' }
```

## Test runner preprocessing

The corpus is parsed once with the language's standard JSON parser.
Then, before any test is run, the runner does **one walk** of the
parsed tree:

```
preprocess(value):
    if value is the string "__UNDEF__":
        # Removed by the parent walker (see below). At root, returned as null.
        return REMOVE_MARKER
    if value is a map:
        out = {}
        for k, v in value.items():
            pv = preprocess(v)
            if pv is REMOVE_MARKER:
                continue  # drop this key
            out[k] = pv
        return out
    if value is a list:
        out = []
        for v in value:
            pv = preprocess(v)
            if pv is REMOVE_MARKER:
                continue  # drop this slot (indices shift)
            out.append(pv)
        return out
    return value
```

After this single pass:

- VALUE inputs are unchanged.
- NULL inputs are unchanged — language's native null.
- ABSENT-in-map inputs are unchanged — the key was never in the JSON.
- `"__UNDEF__"` marker inputs have been **removed from their
  containers**, producing the absent-key / shorter-list shape the
  library actually receives.
- Root-position `"__UNDEF__"` becomes the language's null (since the
  library accepts null = NO-VALUE there anyway).

The library now operates on perfectly natural language-native data.
It never sees a marker. It never knows the corpus existed.

## Output comparison

When a test asserts `out: X`, the runner compares the library's
actual return value to `X`. Because the library unifies null and
absent on its output side (returning null in most languages, removing
the key in a returned map for ABSENT positions), the comparison
routine uses a simple rule:

```
deep_equal_for_test(actual, expected):
    # Normalise both sides: treat NULL and "key not present"
    # as equivalent (just like the library does).
    ...
```

Concretely:
- A map `{a: 1}` (no `b`) and a map `{a: 1, b: null}` compare equal.
- A list `[1, 2]` and `[1, null, 2]` do NOT — list slots are
  positional, and a JSON null in the middle of a list is a real
  position holding a "no-value" value. The corpus should write
  what it actually means.
- For root / scalar positions, `null` and `"__UNDEF__"` (post-preprocess
  → null) compare equal.

The runner exposes one knob per test category (`null:true` or
`null:false`, already present in today's runner):

- `null:true` (default) — apply the null-and-absent-equal rule.
- `null:false` — treat null and absent as distinct on the output
  side. This is the mode `stringify` / `pad` / `typify` / `isnull`
  tests use, because those functions exist specifically to inspect
  the null-ness of a value and would be meaningless if their tests
  conflated the two.

## What this removes from the previous draft

The previous draft of this spec required each port to:

- Define a unique `UNDEF` sentinel value identity-distinct from null.
- Define `JNULL` sentinel in Lua.
- Export `is_undef` / `is_null` predicates to clients.
- Convert markers ↔ sentinels in both directions through the runner.

The corrected design **removes all of this**. The library has no
`UNDEF` sentinel in its public API. There is no `JNULL`. There is no
`is_undef` (or rather: `is_undef(v)` and `is_null(v)` mean the same
thing, both true for "no value"). The runner has no
`sentinels_to_markers` step. Internal sentinels in Python's old code
(`UNDEF = None`) are unnecessary at the API boundary — the
language's native null *is* "no value".

The benefit is enormous portability simplification:

- Python keeps `UNDEF = None` (its natural state).
- Lua keeps `nil` for "no value", and doesn't need a `JNULL` sentinel
  to round-trip JSON null (because the library doesn't distinguish
  null from absent on output anyway — JSON null in input is treated
  as "no value", and the library either returns nil or omits the
  key, both of which serialise back to either nothing or `null`).
- Go uses `nil` end-to-end.
- PHP uses `null` end-to-end.
- Ruby drops the `Object.new.freeze` sentinel.
- TS / JS still have `undefined` and `null` as language-distinct
  values, but the library treats both as "no value" identically.
- Rust / Zig / C# / Java / C++ / Kotlin / C — same: the language's
  native null suffices; the in-port `Noval` / `monostate` /
  `VS_VAL_UNDEF` variants are an internal modelling choice for
  things like "no current parent during inject descent", **not**
  something that escapes through the public API.

## What stays the same

- The `SKIP` and `DELETE` sentinels remain unchanged. They are
  pointer/identity sentinels used **inside** transform/inject specs
  to signal "skip this key" and "delete this key". They never appear
  in client data or test output; they are spec-internal markers.

- The shared test corpus structure is unchanged. We just add (a)
  the `"__UNDEF__"` marker (and document it), and (b) the
  conformance category below.

- The 13 ports already largely match the new model — every port
  except Python and Lua already conflates null with absent at the
  API. Python's recent fixes (getprop, setval, pad, setprop) were
  half-right and half-wrong; under this corrected spec, some of
  them need to be reverted. See the rollout below.

## Conformance test category

Add `build/test/sentinels.jsonic` exercising the API table:

```jsonic
sentinels: {

  # getprop unifies null and absent for the default-substitution rule.
  getprop_unify: {
    set: [
      { in: { val:{a:1},    key:'a', alt:'D' }, out: 1   }
      { in: { val:{a:null}, key:'a', alt:'D' }, out: 'D' }
      { in: { val:{},       key:'a', alt:'D' }, out: 'D' }
    ]
  }

  # haskey: null counts as "no value", so haskey returns false.
  haskey_unify: {
    set: [
      { in: { src:{a:1},    key:'a' }, out: true  }
      { in: { src:{a:null}, key:'a' }, out: false }
      { in: { src:{},       key:'a' }, out: false }
    ]
  }

  # setprop: storing null is equivalent to delprop.
  setprop_unify: {
    set: [
      { in: { parent:{a:1,b:2}, key:'b', val:7 },    out: {a:1, b:7} }
      { in: { parent:{a:1,b:2}, key:'b', val:null }, out: {a:1}      }
    ]
  }

  # ABSENT in a list slot — preprocessor removes the marker, list shortens.
  list_absent: {
    set: [
      { in: { val:['a', '__UNDEF__', 'b'], key:1 }, out: 'b' }
    ]
  }

  # isempty unifies null and absent (and empty containers).
  isempty_unify: {
    set: [
      { in: null, out: true  }
      { in: '',   out: true  }
      { in: [],   out: true  }
      { in: {},   out: true  }
      { in: 0,    out: false }
    ]
  }
}
```

A port passing this category demonstrates conformance with the
spec. The Python and Lua fixes in this branch would be caught and
adjusted by this category.

## Rollout

1. **Add `UNDEF.md` cross-reference** (the language-semantics doc)
   to clarify that the spec is about library API behaviour, not
   about what each host language can do natively.

2. **Land `sentinels.jsonic`** in the corpus and wire it into every
   port's test runner.

3. **Per-port adjustments:**
   - **ts / js (canonical)** — make `getprop` / `haskey` / `setval`
     / `setprop` treat null and undefined as identical for the
     default-substitution and delete rules. Currently TS distinguishes
     them; this is the cosmetic change that aligns canonical with
     the new spec.
   - **py** — partially revert the recent fix. `getprop` must
     return `alt` for `{a:None}`. `setprop(p,'a',None)` deletes
     (the pre-existing behaviour). `setval` reverts to the simple
     form. `pad(None, 6)` returns `"      "` not `"null  "`.
     `stringify(None)` returns `""`. These reverts move the port
     into spec conformance and are smaller than the previous fix.
   - **lua** — no `JNULL` sentinel needed. Continue using nil
     end-to-end. The previous `pad(nil)` fix reverts.
   - **php** — keep current "null is absent" semantics. The string
     `'__UNDEFINED__'` and `stdClass` sentinels can be removed
     entirely (or kept as port-internal-only details).
   - **go** — `nil` for both. No `UNDEF` value needed.
   - **rb** — `nil` for both. `Object.new.freeze` sentinel can be
     dropped.
   - **rs / zig / cpp / c** — these distinguish internally for good
     reasons (their value types are tagged unions / variants and
     a `Noval` variant is convenient for the inject machinery's
     "no current parent" representation). But the **public API**
     of `getprop` / `haskey` / `setprop` / `isempty` / etc. must
     treat the `Noval` variant and the `Null` variant as the same
     for the default-substitution rule.
   - **java / cs / kt** — same as rs: an internal `UNDEF` sentinel
     is fine for the inject state machine, but the public API
     conflates null and absent.

4. **Update the corpus runners** to honour the `null:true` /
   `null:false` flag in the manner this spec describes (most already
   do).

## TL;DR

- The library has **two** observable value states: VALUE and NO-VALUE.
- NO-VALUE = the language's native null/nil/None = absent key. The
  library doesn't distinguish them anywhere in its public API.
- Sentinels exist **only in the test corpus**, **only on input**, and
  **only to encode ABSENT in positions JSON can't express it**
  (root, list slots, function args). The one marker is `"__UNDEF__"`.
- A preprocessor walks the parsed JSON once and **removes**
  `"__UNDEF__"` markers from their containers, leaving the library to
  see ordinary language-native data.
- The library never sees sentinels. Clients never see sentinels.
- Lua needs no `JNULL`. Python needs no separate `UNDEF` object.
  Ruby / PHP / Go drop their existing sentinels.
- A `sentinels.jsonic` conformance category proves a port unifies
  null and absent correctly via three side-by-side test cases per
  affected API.
