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

Of aontu's features, the corpus uses only `@` (import), one `&` template,
`$` absolute refs, and `key()`. Everything else is literal JSON. (Note: the
`` `$STRING` ``/`` `$COPY` `` backtick tokens scattered through `validate.jsonic`
and `transform.jsonic` are **struct's own** by-example sentinels — string
*payloads* under test — not aontu syntax. Easy to conflate; they are data.)


## 4. Proposal: declare the types, let unification enforce them

The goal is a model where the entry/group/spec shapes are **declared once as
aontu types** and unified onto the data, so that (a) malformed entries fail at
build time, (b) defaults are centralised, and (c) the structure documents
itself. Below, "confident" = demonstrated in this repo; "verify" = standard
unification-language features to confirm against the pinned `@voxgig/model`
/ aontu version before relying on them, each with a fallback that needs only
the confident set.

### 4.1 A shared schema unit

Add one `build/test/schema.jsonic`, imported by `test.jsonic`, holding hidden
**definitions** (names that unify into the data but are *projected out* of the
emitted JSON — the property that keeps `test.json` byte-equivalent):

```jsonic
# schema.jsonic — types only; emits nothing on its own.

# An Entry: one call under test.
Entry: {
  # metadata
  id?:     string
  doc?:    boolean

  # input mode — exactly one of in | args | ctx
  in?:     top
  args?:   list
  ctx?:    map

  # expectation mode — at least one of out | err | match
  out?:    top
  err?:    string | boolean
  match?:  map

  # routing
  client?: string
}

# A Group: a bucket of entries plus optional definitions/fixtures.
Group: {
  set:   [ ...Entry ]      # every element unified with Entry
  DEF?:  map
}
```

* `?` optional fields + scalar atoms (`string`, `boolean`, `map`, `list`,
  `top`) — **verify**. Fallback if aontu lacks `?`/atoms: drop the atoms and
  keep `Entry` as a defaults-only template (§4.3); validation is then
  structural (closedness) rather than per-field typed.
* `[ ...Entry ]` list-element template (apply `Entry` to every `set` item) —
  **verify** (this is the single highest-value feature here). Fallback: a
  build-time check script (sibling to `tools/check_corpus_regex.py`) that
  unifies each `set` element with `Entry` and reports failures, instead of
  doing it inline.

### 4.2 Express the exclusive input / expectation modes

If aontu supports disjunction of closed structs (**verify**), the
"exactly-one-input" rule becomes declarative:

```jsonic
Entry: ({ in: top } | { args: list } | { ctx: map }) & {
  id?: string,  doc?: boolean,  client?: string
  out?: top,    err?: string|boolean,  match?: map
}
```

Fallback without disjunction: keep all three optional (§4.1) and assert the
exclusivity in the same build-time check script. The *value* is that the rule
is written down once, near the data, instead of living only in `resolveArgs`.

### 4.3 Centralise defaults via the existing `&` mechanism

This needs **only confident features** and can ship on its own. Extend the
template that already exists in `test.jsonic` from "per function" to "per group"
and "per entry":

```jsonic
struct: &: {
  name: key()
  set: []
  &: {                 # for-all-children of each function = each GROUP
    # group-level defaults / shape here
  }
}
```

and fold `doc:false` / metadata defaults into `Entry` so individual entries stop
repeating them. The emitted `test.json` is unchanged **iff** the defaults equal
what the runner already assumes (`doc` absent ≡ `doc:false`, `set` absent ≡
`[]`) — which they do.

### 4.4 Promote fixtures to a named, referenced slot

Replace ad-hoc `data:` siblings + root-absolute paths with a declared
`fixtures` block and relative/anchored refs:

```jsonic
alts: {
  fixtures: obj0: [ { select:foo_id:true, x:1 }, … ]
  set: [
    { in: { query:select:{foo_id:true}, obj: $fixtures.obj0 },   # or a let/alias
      out: [ … ] }
  ]
}
```

`Group.fixtures?: map` makes "this key is data, not tests" explicit, so doc/
coverage tooling can skip it by type instead of by name. (Alias/relative-ref
ergonomics — **verify**; absolute `$` refs already work as the fallback.)

### 4.5 Resulting shape

```
struct : Spec
└── <function> : Function          name=key(), set defaulted
    └── <group> : Group            { set:[...Entry], fixtures?:map, DEF?:map }
        ├── fixtures?              declared data slot (was ad-hoc siblings)
        ├── DEF?                   declared definitions slot (was one-off)
        └── set : [ ...Entry ]     each element typed & defaulted
```

Same three levels as today — but each level is a **named type**, defaults live
in one place, fixtures and definitions are first-class, and malformed entries
fail the build.


## 5. Migration (test.json must not move)

The hard constraint: `git diff` on the regenerated `build/test/test.json` must
be empty after each step. Recommended order, smallest-blast-radius first:

1. **Add `schema.jsonic` as definitions only; don't reference it.** Regenerate
   `test.json`; confirm zero diff (definitions emit nothing). This proves the
   "projected-out" property on the pinned aontu version before anything depends
   on it. *If it does* change `test.json`, stop — fall back to a standalone
   `tools/check_testspec.py` that validates the model out-of-band and never
   touches the build. (§4.1 fallback path.)
2. **Adopt §4.3 defaults** (`&` group template + `Entry` metadata defaults).
   Regenerate; confirm zero diff. This is pure cleanup and needs only confident
   features.
3. **Wire `set: [ ...Entry ]`** on one file (`minor.jsonic` — simplest, most
   uniform entries) behind the verified list-template feature. Regenerate;
   confirm zero diff; then roll across files.
4. **Migrate fixtures (§4.4)** file by file (`select`, `transform`).
   Regenerate; confirm zero diff per file.
5. **Add the exclusivity constraint (§4.2)** last; it only *rejects* bad input,
   so a green build proves the existing corpus already satisfies it.

Each step is independently revertible and gated by the same `make corpus`
freshness check that CI already runs (`corpus-freshness` job, see
[`DOC_EXAMPLES.md`](./DOC_EXAMPLES.md)).

A `make`-level guard worth adding: regenerate `test.json` into a temp file and
`diff` it against the committed one, failing on any difference — so "refactor
the model, keep the contract" is mechanically enforced rather than trusted.


## 6. What this buys

* **One source of truth for the entry shape** — declared in `schema.jsonic`,
  not reverse-engineered from `runner.ts`. New ports/tools read the type.
* **Build-time rejection** of typoed/!malformed entries (the `otu:` class of
  silent no-op test).
* **Centralised defaults** — entries stop repeating `doc`, and the input/
  expectation contract is written down once.
* **First-class fixtures & defs** — no more root-absolute `$` paths or
  name-special-cased `data` siblings.
* **Aontu earns its keep** — the model uses unification to guard itself instead
  of being JSON behind an `@include`.

## 7. Open questions to settle against the pinned aontu version

1. Do hidden **definitions** project out of compiled output? (Gates step 1 —
   the whole "zero diff" strategy.)
2. **List-element templates** `[ ...T ]`? (Gates §4.1 inline typing; §4.5 still
   works via the check-script fallback.)
3. **Optional fields** `field?` and **scalar type atoms** (`string`, `number`,
   `map`, …)? (Gates per-field typing vs. defaults-only templates.)
4. **Disjunction of structs** `A | B`? (Gates §4.2 declarative exclusivity vs.
   a check-script assertion.)
5. **Relative / alias references** for fixtures? (Ergonomics only; absolute `$`
   is the fallback.)

Every "no" above has a stated fallback that still reaches §4.5's typed shape;
the proposal degrades to "schema declared + validated by a `tools/` script"
in the worst case, which is already a strict improvement over today.
