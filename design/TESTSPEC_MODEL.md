# Test Spec Model — Structure Analysis & a Type-Based Proposal

**Status:** analysis / proposal (2026-06). Nothing here is implemented yet.
This document analyses the current `build/test/*.jsonic` model and proposes a
more coherent, *type-based* structure that uses aontu's unification features
instead of leaving the entry schema implicit in the TypeScript runner.

> Scope note. The compiled `build/test/test.json` is the behavioural contract
> consumed by all 21 ports (see [`AGENTS.md`](../AGENTS.md)). **Any restructure
> must leave the emitted `test.json` byte-equivalent** — otherwise it is a
> behavioural change to every port, not a refactor. §5 (Migration) is built
> around that constraint.


## 1. How the model is built today

The corpus is an aontu/`@voxgig/model` program, not hand-written JSON:

```
build/test/*.jsonic          # aontu source (the model)
        │  voxgig-model test/test.jsonic         (build/package.json: "test-model")
        ▼
build/test/test.json         # 390 KB compiled output — the actual contract
        │  read by typescript/test/runner.ts → resolveSpec()
        ▼
every port's test runner      # ts, py, go, rust, c, … all read test.json
```

`test.jsonic` is the entry point. It wires the per-function files together and
seeds one template:

```jsonic
struct: &: {            # '&' = a template unified into EVERY child of `struct`
  name: key()           # each function gets name = its own key
  set: []               # …and a default empty `set`
}

struct: minor:    @"minor.jsonic"     # '@' = import/include
struct: getpath:  @"getpath.jsonic"
struct: validate: @"validate.jsonic"
…
primary: check: { DEF: { … }, basic: { set: [ … ] } }
```

So aontu *is* already doing type-ish work here — the single `struct.&`
template is a for-all-children rule that stamps `name`/`set` onto every
function. That mechanism is the lever this proposal pulls on; today it is
used exactly once.


## 2. The model has three nesting levels

```
struct
└── <function>      e.g. getpath, merge, validate, minor.isnode …   (one per .jsonic, or one per minor fn)
    └── <group>     e.g. basic, edge, operators, child …            ({ set:[…], + ad-hoc fixtures })
        └── set[]   list of test ENTRIES                            (the leaf units)
```

* **Function** — one file per public function (`getpath.jsonic`, `merge.jsonic`,
  …), except `minor.jsonic` which packs ~30 small functions (`isnode`, `ismap`,
  `clone`, `slice`, …) as siblings.
* **Group** — a named bucket of entries (`basic`, `relative`, `handler`,
  `operators`, `child`, `exact`, …). A group is `{ set: [...] }`, sometimes with
  extra sibling keys used as **fixtures** (see §3.3) and optionally a `DEF`
  block (see §3.4).
* **Entry** — the leaf. A single map describing one call: inputs, expected
  output, and metadata.


## 3. The entry "type" exists — but only in the runner

There is no declared schema for an entry anywhere in the model. Its shape is
defined *operationally* by `typescript/test/runner.ts` (`resolveArgs`,
`checkResult`, `handleError`, `resolveEntry`). Reverse-engineered, an entry is:

| Field    | Role | Notes |
|----------|------|-------|
| `in`     | input (single arg) | cloned, passed as the sole argument — the common case (1319 uses) |
| `args`   | input (arg vector) | explicit positional args; mutually exclusive with `in`/`ctx` (15 uses) |
| `ctx`    | input (context map) | wrapped via `makeContext`, gets `client`/`utility` attached (2 uses) |
| `out`    | expectation | deep-equal against result; `null` → `__NULL__` sentinel (1192 uses) |
| `err`    | expectation | `true` = any error, or string = substring/`/regex/` match of message (59 uses) |
| `match`  | expectation | structural matcher: regex strings, `__UNDEF__`, `__EXISTS__` (15 uses) |
| `id`     | metadata | doc anchor, format `"<fn>/<group>#<label>"` — consumed by `tools/gen_doc_examples.py` (44 uses) |
| `doc`    | metadata | `true` ⇒ extract as a documentation example (39 uses) |
| `client` | routing | names a client from the group's `DEF.client` (2 uses) |

Internal-only fields the runner *adds* at runtime (`res`, `thrown`, `ctx`
rebinding) are not part of the source model.

### 3.1 Problem: the schema is invisible to aontu

Because nothing declares the entry type, **aontu cannot validate it**. A typo
(`otu:` for `out:`, `inn:` for `in:`) compiles cleanly and the entry silently
asserts nothing — the runner just sees `out === undefined`. The model has all
of aontu's unification machinery available and uses none of it to guard its own
shape.

### 3.2 Problem: mutually-exclusive fields are unmodelled

`in` / `args` / `ctx` are three input modes; `out` / `err` / `match` are
expectation modes. The runner resolves them by precedence, but the model never
states the constraint, so `{ in:…, args:… }` or `{ out:…, err:… }` are
expressible nonsense.

### 3.3 Problem: fixtures are ad-hoc siblings reached by absolute paths

Shared data lives as extra keys *inside* a group, next to `set`, and is
referenced by long absolute `$` paths:

```jsonic
alts: {
  data: obj0: [ { select:foo_id:true, x:1 }, … ]       # fixture, sibling of set
  set: [
    { in: { query:select:{foo_id:true}, obj: $.struct.select.alts.data.obj0 },
      out: [ … ] }
  ]
}
```

`$.struct.select.alts.data.obj0` repeats the entire path from the root. There is
no convention marking `data` as "fixture, not a test group", so tooling that
walks groups must special-case it.

### 3.4 Problem: `DEF` is a one-off

`primary.check.DEF.client` is the only `DEF` in the corpus. It is a
group-scoped definitions block the runner reads (`resolveClients`). Its
existence is fine; that it is undocumented and unique makes it look like an
accident rather than a designed slot.

### 3.5 Net: aontu is used as a glorified `#include`

Of aontu's features, the corpus uses only `@` (import), one `&:` map template,
`$` absolute refs, and `key()`. Everything else is literal JSON. (Note: the
`` `$STRING` ``/`` `$COPY` `` backtick tokens scattered through `validate.jsonic`
and `transform.jsonic` are **struct's own** by-example sentinels — string
*payloads* under test — not aontu syntax. Easy to conflate; they are data.)


## 4. Proposal: declare the types, let unification enforce them

The goal is a model where the entry/group/spec shapes are **declared once as
aontu types** and unified onto the data, so that (a) malformed entries fail at
build time, (b) defaults are centralised, and (c) the structure documents
itself.

> The complete structure as runnable-shaped code is in
> [`testspec-schema.jsonic`](./testspec-schema.jsonic) — base types, wiring,
> per-function refinements, a worked entry, and the fixtures slot. The sections
> below explain it piece by piece.

The aontu features used below are confirmed from
[`rjrodger/aontu`](https://github.com/rjrodger/aontu) `docs/reference-language.md`:

| Feature | Syntax | Use here |
|---|---|---|
| scalar types | `string` `number` `integer` `boolean` `top` | constrain fields |
| unification | `&` | apply a type to a value |
| defaults | `*value` (e.g. `*false`) | centralise per-field defaults |
| disjunction | `\|` (e.g. `string\|boolean`) | the exclusive input/expectation modes |
| optional fields | `x?:` — *dropped if unresolved* | every non-required entry field |
| map template | `&: {…}` — *template not emitted* | already used; extend it |
| list template | `[ &:{…}, … ]` — *template not emitted* | type every `set` element |
| references | `$.a.b` (absolute), `.a.b` (relative) | fixtures |
| imports | `@"file"` | already used |
| **`hide()`** | marks a value **excluded from output** | schema lives in the model, emits nothing |
| **`close()`/`open()`** | closed vs. open struct | reject unknown fields (the typo guard) |
| `key()` | ancestor key (`key(0)`=own) | already used (`name: key()`) |

The two in bold are what make this both safe and worthwhile: `hide()` keeps the
schema out of the compiled `test.json` (so the contract stays byte-equivalent),
and `close()` is what catches a typoed *field name* — without forbidding any
*combination* of the known fields (§4.2).

### 4.1 A shared, hidden, adaptive base type

Add one `build/test/schema.jsonic`, imported by `test.jsonic`, defining the base
`Entry` under a `hide()`-marked block so it contributes constraints but emits
nothing. Every field is **optional with a default** — the type *adapts* to
whichever fields an entry supplies rather than demanding a fixed shape:

```jsonic
# schema.jsonic — hidden definitions; contribute constraints, emit no JSON.

# Adaptive base: all fields optional, all defaulted. An entry is whatever
# subset of these it sets; the type adds constraints/defaults, never excludes.
Entry: close({
  # metadata
  id?:     string
  doc?:    *false & boolean

  # inputs — any of in | args | ctx (the runner's precedence picks one)
  in?:     *top
  args?:   *[] & list
  ctx?:    *{} & map

  # expectations — any of out | err | match
  out?:    *top
  err?:    *false & (string | boolean)
  match?:  *{} & map

  # routing
  client?: string
})

Group: close({
  set:      [ &:Entry ]   # the &: template unifies Entry into every element
  fixtures?: map          # declared data slot (§4.4)
  DEF?:      map          # declared definitions slot (§3.4)
})
```

`close(...)` makes `{ otu: 42 }` a **build error** (unknown field in a closed
struct) — but `{ in:1, out:2, id:'x' }` and `{ ctx:{…}, match:{…} }` are both
fine, because closedness is about the *vocabulary of field names*, not which of
them co-occur. `[ &:Entry ]` is aontu's list-template form: the leading
`&:Entry` is consumed (not emitted) and unified into every real element.

### 4.2 Adaptive entries, not mutually-exclusive modes

The earlier draft modelled inputs as a closed disjunction
`({in} | {args} | {ctx})` so a build would *prove* "exactly one input mode."
That is the wrong tool here, for two reasons:

1. **It doesn't match the runner.** `resolveArgs` does not reject
   `{ in, args }` — it applies a precedence (`ctx` → `args` → `in`). A schema
   that forbids what the runtime quietly tolerates is a second, conflicting
   source of truth.
2. **It fights unification.** Aontu has no conditionals, no field
   interdependence, and no comprehensions (confirmed in
   `reference-language.md`); its model is *monotonic, additive* unification.
   Disjunction of closed structs is brittle under that model — adding any
   shared field (a new `id`, a `doc` flag) must be threaded into every arm, and
   a mistake silently changes which arm an entry selects.

So the entry is **adaptive**: one open-ended-but-closed-on-names base (§4.1)
whose fields are all optional and `*`-defaulted. Presence of a field *adds* its
constraint; absence *falls back* to the default. Nothing is excluded. This is
exactly the grain of aontu — defaults via `*`/`pref()`, refinement via `&`,
generalisation via `super()` — and it mirrors the runner instead of contradicting
it.

The positive expression of structure then comes from **refinement, not
exclusion**: each function adapts the base `Entry` to its own input/output shape
by unifying a refinement through the `&:` template (§4.3) — see §4.3.1.

### 4.3 Centralise defaults via the existing `&:` mechanism

Extend the template that already exists in `test.jsonic` from "per function" to
"per group", so group shape/defaults are stated once:

```jsonic
struct: &: {
  name: key()
  set: []
  &: Group        # for-all-children of each function = each GROUP, typed
}
```

Per-field defaults move into `Entry` via `*value` (e.g. `doc?: *false`). The
emitted `test.json` is unchanged **iff** each default equals what the runner
already assumes (`doc` absent ≡ `doc:false`, `set` absent ≡ `[]`) — which it
does, and which step 2 below verifies by diff.

#### 4.3.1 Per-function adaptation — the structure that earns the keep

Today `in`/`out` are `top`: the model says nothing about what a `getpath` input
or a `validate` input *looks like*. The adaptive lever is to let each function
**refine** the base `Entry` through the same `&:` template, so the entry type
adapts to the function under test:

```jsonic
# in getpath.jsonic — refine every entry of every getpath group
struct: getpath: &: &: {           # each group → each entry
  in?:  { path?: string | list,  store?: top }
  out?: top
}

# in validate.jsonic
struct: validate: &: &: {
  in?:  { data?: top,  spec?: top }
}

# in merge.jsonic — merge takes a single list argument
struct: merge: &: &: {
  in?:  list
}
```

Each refinement is unified *onto* the shared `Entry` (it never replaces it), so
metadata/expectation fields and their defaults are inherited while the
function-specific input shape is layered on. A `getpath` entry that writes
`in:{ pth:'a.b' }` now fails the build (if the inner shape is `close()`d),
catching the field-level typo the base type alone can't see. This is "adaptive
structure" in the aontu idiom: a base type generalises, per-function templates
specialise, and unification composes the two — no disjunction, no exclusion.

`minor.jsonic` (many functions per file) refines per sibling rather than per
file: `struct: minor: isnode: &: { in?: top, out?: boolean }`, etc., or leaves
the base as-is where inputs are genuinely heterogeneous.

### 4.4 Promote fixtures to a named, referenced slot

Replace ad-hoc `data:` siblings + root-absolute paths with the declared
`fixtures` slot and relative refs:

```jsonic
alts: {
  fixtures: obj0: [ { select:foo_id:true, x:1 }, … ]
  set: [
    { in: { query:select:{foo_id:true}, obj: .fixtures.obj0 },  # relative ref
      out: [ … ] }
  ]
}
```

`Group.fixtures?: map` makes "this key is data, not tests" explicit by type, so
doc/coverage tooling skips it structurally instead of name-matching `data`. The
relative `.fixtures.obj0` replaces `$.struct.select.alts.data.obj0`. If a
fixture must *not* appear in `test.json`, wrap it in `hide()`.

### 4.5 Resulting shape

```
struct : Spec
└── <function> : Function          name=key(); refines Entry → function's in/out shape (§4.3.1)
    └── <group> : Group  (closed)   { set:[&:Entry'], fixtures?:map, DEF?:map }
        ├── fixtures?              declared data slot (was ad-hoc siblings)
        ├── DEF?                   declared definitions slot (was one-off)
        └── set : [ &:Entry' ]     Entry' = base Entry & the function's refinement
```

Same three levels as today — but each level is a **named type**, defaults live
in one place, fixtures and definitions are first-class, and the entry type is
**adaptive**: a closed-on-names base that each function specialises by
unification (`Entry'`), never a disjunction that forbids field combinations.


## 5. Migration (test.json must not move)

The hard constraint: `git diff` on the regenerated `build/test/test.json` must
be empty after each step. Recommended order, smallest-blast-radius first:

1. **Add `schema.jsonic` with `hide()`-marked types; don't reference them yet.**
   Regenerate `test.json`; confirm zero diff. This validates locally that
   `hide()` excludes definitions from output on the pinned `@voxgig/model`
   build before anything depends on it. (If the pinned version's `hide()`
   behaves differently, fall back to a standalone `tools/check_testspec.py`
   that unifies the model against the schema out-of-band and never touches the
   build output.)
2. **Apply defaults (§4.3)** — `&: Group` group template + `*value` field
   defaults. Regenerate; confirm zero diff. Pure cleanup.
3. **Type one file's `set` with `[ &:Entry ]` + `close()`** — start with
   `minor.jsonic` (simplest, most uniform entries). Regenerate; confirm zero
   diff; then roll across files one at a time. Each file's first build is where
   a latent typo would surface as a `close()` error — fix the data, not the
   schema.
4. **Migrate fixtures (§4.4)** file by file (`select`, then `transform`).
   Regenerate; confirm zero diff per file.
5. **Layer per-function refinements (§4.3.1)** last, one function at a time —
   `struct: getpath: &: &: { in?: {…} }`, etc. These only *add* constraints to
   already-valid data, so a green build proves each function's entries already
   fit their declared input/output shape; the first build per function is where
   a stray inner typo (`pth:` for `path:`) surfaces.

Each step is independently revertible and gated by the same `make corpus`
freshness check that CI already runs (`corpus-freshness` job, see
[`DOC_EXAMPLES.md`](./DOC_EXAMPLES.md)).

A `make`-level guard worth adding: regenerate `test.json` into a temp file and
`diff` it against the committed one, failing on any difference — so "refactor
the model, keep the contract" is mechanically enforced rather than trusted.


## 6. What this buys

* **One source of truth for the entry shape** — declared in `schema.jsonic`,
  not reverse-engineered from `runner.ts`. New ports/tools read the type.
* **Build-time rejection** of typoed field names (the `otu:`/`pth:` class of
  silent no-op test) via `close()` — at both the entry and per-function level.
* **Adaptive, not exclusive** — the entry type *refines* per function instead of
  forbidding field combinations, so it tracks the runner's precedence semantics
  rather than contradicting them, and stays robust under aontu's additive
  unification (no arms to re-thread when a shared field is added).
* **Centralised defaults** — entries stop repeating `doc`; defaults live once in
  the base type.
* **First-class fixtures & defs** — no more root-absolute `$` paths or
  name-special-cased `data` siblings.
* **Aontu earns its keep** — the model uses unification (base + `&:` refinement
  + `*` defaults) to guard itself instead of being JSON behind an `@include`.

## 7. Loose ends to confirm against the **pinned** `@voxgig/model`

The language features are confirmed from upstream aontu docs; what remains is
version- and integration-specific, all checkable in minutes during step 1:

1. **Does this aontu build's `hide()` exclude from `voxgig-model`'s emitted
   JSON?** Gates the zero-diff strategy. Confirmed by the step-1 diff itself;
   fallback is the out-of-band `tools/check_testspec.py`.
2. **Does `close()` compose with the `&:` map/list templates and with
   refinement** the way §4.1/§4.3.1 assume — i.e. unifying a per-function
   refinement *into* a closed base adds the refinement's fields rather than
   tripping closedness? This is the crux of the adaptive design. If aontu treats
   `close()` as final (no later additions), the fix is to close *after*
   refinement: keep the base and refinements open, and `close()` the composed
   `Entry'` at the leaf where the `&:Entry` list template is applied.
3. **`voxgig-model` import resolution for a non-spec file** — `schema.jsonic` is
   imported for types only, not as a `struct.<fn>`. Confirm the builder doesn't
   try to treat it as a function spec.

Each has a stated fallback that still reaches §4.5's typed shape; worst case the
proposal degrades to "schema declared in-tree + validated by a `tools/` script",
already a strict improvement over the schema living only in `runner.ts`.
