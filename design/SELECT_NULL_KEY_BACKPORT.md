# Design Note: `select` drops records with a present-but-null field (open-match "unexpected keys")

Status: **Proposed** — back-port required across ports
Origin: field failure in the Voxgig SDK generator (bluefin fleet, Dart target)
Scope: the `validate` "unexpected keys" check used by `select` under an open (`$AND`) shape

---

## TL;DR

The canonical TypeScript `validate` decides whether a child key is "unexpected"
by testing **literal presence** in the shape — `NONE === _lookup(pval, ckey)`.
Several ports instead test **value-definedness** — `haskey(pval, ckey)` /
`_lookup(pval, ckey) == null` — which treats a key that is *present but null* the
same as an *absent* key.

Consequence: `select(store, {})` (open match, e.g. an unfiltered `list`) silently
**drops any record that carries a null-valued field**, because the `$AND` machinery
merges the record into the shape and the null slot is then misread as "not
declared" → "unexpected key" → validation error → record excluded.

`haskey` is *intentionally* value-based (`null != getprop`) and must **not** be
changed. The fix is local to the `validate` unexpected-keys loop: use the
`_lookup`/`NONE` (Noval) sentinel — literal presence — exactly as canonical TS.

---

## Symptom (how we found it)

Generated Dart SDK, `device` entity, basic CRUD flow:

1. `create` a device; the mock returns the created record. The record has an
   **optional `serial_number` that is null** (the create body did not set it).
2. `list` (no filter) — the mock does `select(store, buildArgs({}))`, where
   `buildArgs({})` yields `{ $AND: [] }` (match everything).
3. The `ItemExists` assertion — "the created record appears in the list" — **fails**:
   the created record is missing from the list result, though the store provably
   contained it (verified: store had 4 entries, `select` returned 3).

Every fixture record (non-null `serial_number`) survived; only the freshly
created record (null `serial_number`) was dropped.

## Root cause

`select` validates each child against the query with `exact` mode. An `$AND`
term merges the child *into the shape node* (so, for an empty `$AND`, the shape
node effectively becomes the child record). `validate` then reaches the
map-vs-map "closed object" branch and computes the set of child keys not
declared by the shape:

```ts
// canonical: typescript/src/StructUtility.ts  (CORRECT)
const badkeys = []
for (const ckey of ckeys) {
  // Literal presence: _validation needs to know if the SHAPE declares this
  // key, regardless of whether the validator stored null in that slot. The
  // Group A haskey would miss null-valued slots.
  if (NONE === _lookup(pval, ckey)) {
    badkeys.push(ckey)
  }
}
```

`_lookup` returns the `NONE`/Noval **sentinel** when a key is absent, and the
stored value (including `null`) when the key is present. So `NONE === _lookup(...)`
is true **only for genuinely absent keys**.

The buggy ports instead ask "is this key's value defined?":

```go
// go  (BUGGY): value-based — HasKey := (nil != GetProp)
if !HasKey(val, ckey) { badkeys = append(badkeys, ckey) }
```

For the created record, `serial_number` **is present** but its value is `null`,
so `HasKey` returns false → it is added to `badkeys` → "Unexpected keys" →
the record fails validation and `select` drops it.

### Why this is subtle
`haskey`'s value-based definition is **correct and deliberate** for its public
contract ("null at a key counts as no value — same rule as getprop"). The defect
is *using* `haskey` where the algorithm needs *literal presence*. Canonical TS
draws exactly this distinction (its comment calls value-based `haskey`
"Group A", and this call site "Group B / literal presence").

## The invariant

> In the `validate` open-object "unexpected keys" check, a child key is
> *unexpected* **iff the shape does not declare it**. A shape key that is
> declared with a `null` value is declared, and must not make the child key
> unexpected.

Equivalent correct idioms:
- **Sentinel lookup** (matches canonical): `NONE == _lookup(pval, ck)` /
  `isNoval(lookup_(pval, ck))`.
- **Native literal presence** for maps: `pval.containsKey(ck)` (what Dart now
  uses) — only valid where the container's "has key" is presence, not value.

Do **not** fix this by changing `haskey`. Fix only the badkeys predicate.

## Port audit

| Port | Predicate today | Verdict |
|---|---|---|
| typescript (canonical) | `NONE === _lookup(pval, ckey)` | ✅ correct |
| csharp | `ReferenceEquals(Lookup(pval, ck), NONE)` | ✅ correct |
| java | `_lookup`-sentinel (has the "TS _lookup, not haskey" note) | ✅ correct |
| scala | `isNoval(lookup_(pval, VStr(ck)))` | ✅ correct |
| kotlin | `_lookup`-sentinel (has "null value is NOT a bad key" note) | ✅ correct |
| swift | `lookup(...).isNoval` | ✅ correct |
| rust | `_lookup`/NONE (has canonical note) | ✅ correct |
| ocaml | `is_noval (lookup_ pval (Str ck))` | ✅ correct |
| haskell | `isNoval` of `lookup_` | ✅ correct |
| perl | `is_none(_lookup($pval, $ck))` | ✅ correct |
| cpp | `NONE === _lookup` (has canonical note) | ✅ correct |
| c | `voxgig_lookup(pval, kv) != NULL` — returns a non-NULL Noval wrapper for present-null | ✅ correct |
| **dart** | was `_lookup(pval, ck) == null`; **fixed** → `pval.containsKey(_mapKey(ck))` | ✅ fixed (SDKgen `a997471`) |
| **go** | `!HasKey(val, ckey)` | ❌ **fix** |
| **python** | `not haskey(pval, ckey)` | ❌ **fix** |
| **ruby** | `ckeys.reject { \|ck\| haskey(pval, ck) }` | ❌ **fix** |
| **php** | `!self::haskey($pval, $ckey)` | ❌ **fix** |
| **clojure** | `(not (haskey pval %))` | ❌ **fix** |
| **zig** | `!(haskey(allocator, pval, ck) catch false)` | ❌ **fix** |
| **elixir** | `lookup_(pval, ck) == nil` (its `lookup_` returns plain `nil` for **both** absent and present-null) | ❌ **fix** |

Note: the seven buggy ports currently **pass** the shared corpus — the defect is
**latent** there (no existing corpus case exercises an open match over a record
with a present-null field). Dart is the one confirmed to fail in the field. Fix
all seven for canonical parity and to prevent the same class of silent
`select` drop.

## Fix recipe

Each fix is a one-line change at the badkeys predicate in `validate`.

- **go** — add/keep a presence helper and use it here (do not repurpose `HasKey`):
  ```go
  // literal presence: the shape declares ckey even when its value is nil
  if NONE == _lookup(pval, ckey) { badkeys = append(badkeys, ckey) }
  ```
  (Use the existing `_lookup`/Noval sentinel that the other Group-B sites use.)

- **python** — `if _lookup(pval, ckey) is NONE:` (or `is UNDEF`, per this port's
  sentinel name) instead of `if not haskey(pval, ckey):`.

- **ruby** — `ckeys.reject { |ck| !Struct.noval?(lookup_(pval, ck)) }` (i.e. keep
  keys whose lookup is the Noval sentinel), instead of `reject { haskey(...) }`.

- **php** — `if (self::is_none(self::_lookup($pval, $ckey)))` instead of
  `if (!self::haskey($pval, $ckey))`.

- **clojure** — `(filter #(noval? (lookup_ pval %)) ckeys)` instead of
  `(filter #(not (haskey pval %)) ckeys)`.

- **zig** — `if (isNoval(lookup_(allocator, pval, ck)))` instead of
  `if (!haskey(...))`.

- **elixir** — the deeper issue is that `lookup_` returns plain `nil` for both
  absent and present-null. Either (a) make `lookup_` return the port's Noval
  sentinel for the `:error` (absent) branch and keep `{:ok, v} -> v`, then test
  `is_noval(lookup_(pval, ck))`; or (b) at this call site test map presence
  directly (`ismap(pval) and Struct.has_literal_key?(pval, ck)`). Option (a) is
  preferred — it aligns `lookup_` with canonical `_lookup` and fixes any other
  present-null-sensitive call sites at once.

Each port should confirm the local `_lookup`/`lookup_` returns the Noval sentinel
(not plain null) for an absent key; if it collapses absent→null (as elixir's
does), fix `lookup_` rather than papering over it at the call site.

## Regression test (add to the shared corpus)

Add a `select` case that exercises an open match over records with a present-null
field, so every port is protected:

```jsonic
# select: open match keeps a record whose optional field is null
select-null-field: {
  in: {
    store: {
      a: { id: a, opt: x }
      b: { id: b, opt: null }   # present, null
    }
    query: { `$AND`: [] }        # match everything
  }
  out: [ { id: a, opt: x }, { id: b, opt: null } ]
}
```

Expected: both records returned. Before the fix, value-based ports return only
`a`. This belongs in the canonical corpus (`test/`), which every port's suite
runs, so it fails loudly on any regression or un-back-ported port.

## Roll-out

The struct source is **vendored** into every generated SDK (via the SDK
generator's per-language templates). After fixing a port here and updating the
generator's vendored copy, SDKs pick up the fix on regeneration. For the Voxgig
SDK generator the Dart fix shipped in `sdkgen a997471` (template
`tm/dart/lib/utility/voxgig_struct.dart`); the remaining ports should be fixed
here first, then the generator's vendored copies refreshed and the fleet
regenerated.

## Appendix: do NOT "fix" `haskey`

`haskey(val, key) := (null != getprop(val, key))` is correct by contract and is
relied on elsewhere (e.g. `$TOP` presence checks). Changing it to literal
presence would be a wider semantic change with its own fallout. The fix is
strictly the `validate` unexpected-keys predicate.
