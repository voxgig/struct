# Rust Port — Porting Plan & Challenge Analysis

> Status: **implementation in progress.** The foundation (`Value` type,
> constants, jsnum coercions), all minor utilities, `walk`, `merge`, and
> `getpath`/`setpath` are implemented and pass their corpus slices (712
> checks via `cargo test`). `inject` / `transform` / `validate` / `select`
> are staged — the `Injection` state machine and plumbing are in place,
> the bodies are `unimplemented!()` stubs pointing here. See
> [`NOTES.md`](./NOTES.md) for the current state and [`README.md`](./README.md)
> for the API. The rest of this document is the original challenge analysis
> and roadmap — still the reference for the remaining work.
>
> The canonical implementation is
> [`ts/src/StructUtility.ts`](../ts/src/StructUtility.ts) (~3,135 lines);
> the contract every port must satisfy is the shared corpus in
> [`build/test/`](../build/test/) (`test.json`, compiled from the
> `*.jsonic` sources).

---

## 1. Goal and ground rules

- **One API, one set of semantics.** The Rust port exposes the same 40
  public functions, 2 sentinels, 15 type bit-flags, 3 mode flags, 11
  transform commands, and 15 validate checkers as the TypeScript
  canonical (see [`../README.md`](../README.md) and
  [`../REPORT.md`](../REPORT.md)).
- **The corpus is the spec.** Disagreement between the port and
  `build/test/test.json` is a port bug, never a corpus bug. So a corpus
  test runner is part of the deliverable, not an afterthought.
- **Human-comparable where it's free, idiomatic where it isn't.** The TS
  source keeps "functionally redundant" code so ports stay line-by-line
  comparable. Rust's ownership model makes a 1:1 transcription
  impossible in a few spots (`merge`'s walk-callbacks, the `walk` path
  pool, optional/overloaded parameters). Diverge there, and record each
  divergence in `NOTES.md` — the way `go/NOTES.md`, `php/NOTES.md`, and
  `cpp/REFACTOR_PLAN.md` do.
- **Not a rewrite of behaviour.** Quirks are deliberate: `stringify`
  strips *all* `"`; `keysof` sorts list indices as strings; JSON `null`
  is not `undefined`; lists are mutable and reference-stable. Reproduce
  them, don't "fix" them.

---

## 2. The decision that drives everything: the in-memory value type

Every other choice follows from how JSON-shaped data is represented in
memory. This mirrors the analysis in
[`cpp/REFACTOR_PLAN.md`](../cpp/REFACTOR_PLAN.md), adapted to Rust.

### Recommendation

```rust
// sketch — not final
pub enum Value {
    Noval,                                  // TS `undefined` — property absent. NOT a scalar.
    Null,                                   // JSON null — a real value, distinct from Noval.
    Bool(bool),
    Num(f64),                               // see §4 — one numeric kind, integer-ness derived
    Str(String),
    List(Rc<RefCell<Vec<Value>>>),          // reference-stable, mutable in place
    Map(Rc<RefCell<IndexMap<String, Value>>>), // insertion-ordered, reference-stable
    Func(Func),                             // callable values live in the data, see §6
    Sentinel(&'static Sentinel),            // SKIP / DELETE — pointer identity
}

pub struct Sentinel { pub tag: &'static str }
pub static SKIP: Sentinel = Sentinel { tag: "`$SKIP`" };
pub static DELETE: Sentinel = Sentinel { tag: "`$DELETE`" };

pub type Injector = Rc<dyn Fn(&mut Injection, &Value, &str, &Value) -> Value>;
pub type Modify   = Rc<dyn Fn(&Value, &Value /*key*/, &Value /*parent*/, &mut Injection, &Value /*store*/)>;
pub type WalkApply<'a> = &'a mut dyn FnMut(Option<&str>, &Value, &Value, &[String]) -> Value;
pub enum Func { Injector(Injector), Modify(Modify) }   // or unify behind one closure type
```

### Why each piece

1. **A custom enum, not `serde_json::Value`.** `serde_json::Value` has
   no place for callables (the `$COPY`/`$EACH`/… injectors live *inside*
   the `store` map alongside data and are looked up with `getprop`), no
   sentinel identity that survives `clone`, and `Value::Map` is a
   `BTreeMap`/`Map` that does not preserve insertion order. We keep
   `serde_json` only as the *JSON-text parser* for loading the corpus
   (and possibly as a serialise bridge), exactly as the C++ plan keeps
   `nlohmann::json` only as a parse bridge.

2. **`Rc<RefCell<…>>` for `List` and `Map` interiors.** The library's
   core invariant (see [`../README.md`](../README.md) "Design notes" and
   the `StructUtility.ts` header comment) is *"Lists are assumed to be
   mutable and reference-stable."* `merge` builds its output by walking
   and mutating nodes in place; `inject` mutates the cloned spec in
   place; the `Injection` struct keeps `nodes` — a stack of ancestor
   node *references* — and `setprop`/`delprop`/`setval` write through
   them. JS gets this for free (objects/arrays are heap refs). Go and
   PHP needed a `ListRef` wrapper; C++ uses `shared_ptr<List>`; Zig uses
   heap-allocated `MapRef`/`ListRef`. Rust's equivalent is
   `Rc<RefCell<_>>`: cheap `Rc`-clone "copies", shared mutation visible
   to every holder, forked only by `clone()`.

3. **`IndexMap` (the `indexmap` crate), not `HashMap`/`BTreeMap`.** TS
   objects preserve insertion order, and `inject` depends on it: it
   partitions a node's keys into "no `$`" then "`$`-bearing" (transform
   commands run last), and the spec-clone that becomes the transform
   *output* carries the spec's key order. `keysof` then *sorts* keys
   explicitly where sorting is wanted. `IndexMap` gives us insertion
   order to preserve and `.sort_keys()` / `keys().sorted()` where we
   need it. (`BTreeMap` would be permanently sorted — wrong for output;
   `HashMap` has no order at all.)

4. **`Func` as a first-class variant.** `transform`'s `store` literally
   contains `$COPY: transform_COPY`, `$WHEN: || iso_now()`,
   `$SPEC: || origspec.clone()`, the `FORMATTER` closures, etc.
   `getprop(store, "$COPY")` returns one; `isfunc` tests it; the inject
   handler calls it. So `Value::Func` must exist. Closures that capture
   environment go in `Rc<dyn Fn>`. There is no need for *function
   equality* except inside `Value`'s `PartialEq` (used by
   `validate_EXACT` and the test runner) — define `Func == Func` as
   `Rc::ptr_eq` (or always `false`); it never matters in practice.

5. **Distinct `Noval` and `Null`.** TS treats `undefined` (absent) and
   `null` (JSON null) as different values and the corpus relies on it
   (`getprop`/`getelem` "absent vs present-but-null", several validate
   tests, the `$NIL` vs `$NULL` checkers). Rust can model this cleanly
   with two variants — *do not* collapse them into `Option<Value>` and
   *do not* use a `"__UNDEFINED__"` sentinel string the way PHP had to.
   The corpus runner uses the marker strings `__NULL__`, `__UNDEF__`,
   `__EXISTS__` to talk about these over the JSON wire (see
   `ts/test/runner.ts`).

6. **`Sentinel` by `&'static` reference.** `SKIP`/`DELETE` are compared
   by identity (`SKIP === val`, `DELETE === val`). Two `static`
   instances, compared with `std::ptr::eq`. `clone()` must short-circuit
   on the `Sentinel` variant so identity survives a deep copy (TS does
   the same via its `$REF:N` round-trip dance — we just skip the dance).

7. **One numeric variant `Num(f64)`** — see §4 for the full argument.
   Short version: JS has one number type; faithfulness beats Rust's
   `i64` instinct here, and it sidesteps a `2.0`-vs-`2` parse mismatch
   and `i64`-overflow corner cases. (Alternative: `enum N { Int(i64),
   Float(f64) }` like the C++ plan — listed as an open question.)

### Threading

`Rc<RefCell>` is single-threaded. That matches the JS model the library
is transcribed from, and it is the cheapest option. A `Send + Sync`
variant would mean `Arc<Mutex<_>>` (or `RwLock`), which changes every
single access site and adds lock overhead. **Recommendation:** ship the
`Rc<RefCell>` version, document "not thread-safe — single-threaded data
model, like the JS canonical" in `NOTES.md`, and treat an `Arc` variant
as out of scope (open question §11).

---

## 3. The borrow-checker discipline (the thing most likely to bite)

`RefCell` turns aliasing-with-mutation from a compile error into a
runtime panic. A naive transcription of the canonical code *will*
double-borrow. The rule that makes it work:

> **Accessor functions return owned `Value`s. A `Ref`/`RefMut` guard
> never outlives the smallest possible block, and is never held across a
> call to anything that might touch the same cell.**

Concretely:

- `getprop` / `getelem`: `borrow()` the cell, clone the slot out
  (`Value::clone` on a node is just an `Rc::clone` — cheap), drop the
  borrow, return the owned `Value`. Never return `Ref<…>`.
- `setprop` / `delprop` / `Injection::setval`: `borrow_mut()`, mutate,
  drop. Take `&Value` for the parent (not `&mut`) — the mutation goes
  through the `RefCell`, so the *handle* is shared-immutable while the
  *contents* change. This is exactly how JS behaves.
- `items` / `keysof`: collect into a fresh `Vec<(String, Value)>` /
  `Vec<String>` and drop the borrow *before* the caller iterates — the
  TS versions already return fresh arrays, so mirroring "snapshot then
  iterate" is both faithful and panic-safe. `walk` and `inject` mutate
  the node they're iterating; the snapshot is what makes that legal.
- `Injection` holds `parent: Value`, `nodes: Vec<Value>`, `val: Value`,
  `meta: Value` — all cheap (`Rc`-backed for nodes). It's passed
  `&mut Injection`. When an injector needs to call the modify/handler
  hook *that is stored on the injection* (`inj.modify(…, inj, …)`),
  clone the `Rc<dyn Fn>` out first (`let m = inj.modify.clone()`), then
  call `m(…, &mut inj, …)`. Same for `inj.handler`.

This discipline is the price of the `Rc<RefCell>` design. It's
manageable, but it's the part to write carefully and test hard.

---

## 4. Numbers: integer vs decimal

TS: `typify` returns `T_integer` when `Number.isInteger(v)` (note
`Number.isInteger(2.0) === true`), `T_decimal` otherwise, `T_noval` for
`NaN`. `size(number)` is `Math.floor(v)`. `slice(number, …)` clamps to
`[start, end-1]` with `Number.MIN/MAX_SAFE_INTEGER` defaults.
`strkey(2.2) === "2"` (truncate). FORMATTER `integer` does `n | 0`
(ToInt32 — wraps at 2³²!). `getelem` parses keys with `parseInt`.

Two viable models:

| | `Value::Num(f64)` (recommended) | `enum N { Int(i64), Float(f64) }` |
|---|---|---|
| JSON parse | `serde_json` literal `2.0` → f64 `2.0` → `is_integer()` true. No normalisation drama. | Must normalise: `2.0` literal should behave as integer (JS `JSON.parse("2.0")` → `2`). And `1e100` is "integer" in JS but doesn't fit `i64`. |
| Fidelity to JS | Exact, including JS's own 2⁵³ precision ceiling. | Diverges at the `i64`/`f64` boundary. |
| Rust ergonomics | Users must `as i64`. Slightly un-idiomatic. | Idiomatic. |
| Effort | Lower. | Higher (normalisation rules everywhere). |

**Recommendation:** `Num(f64)` with helpers `is_integer(f) -> bool`
(= `f.is_finite() && f.fract() == 0.0`) and a JS-flavoured
`to_int32(f)` for the FORMATTER. Document the choice. Carry the
`Int/Float` split as a noted alternative.

Either way you need faithful coercion helpers, because the canonical
code leans on JS coercions that have no Rust stdlib equivalent:

- `+x` (unary plus / `ToNumber`): `"12"`→12, `""`→0, `"  "`→0,
  `"12abc"`→NaN, `true`→1, `null`→0, `[]`→0, `[5]`→5, `{}`→NaN. Used in
  `setprop`/`delprop` (`let keyI = +key; if isNaN(keyI) { return }`).
- `parseInt(x)`: lenient prefix parse, hex auto-detect (`"0x1f"`→31),
  `"12abc"`→12, `"abc"`→NaN. Used in `getelem`, but always behind the
  `/^[-0-9]+$/` guard, so a `str::parse::<i64>()` covers the live cases
  (modulo pathological `"--5"`, `"5-5"` — likely untested).
- `Number(x)`: like `+x` but used in FORMATTER `number`/`integer`.
- `String(x)` / `"" + x`: JS number→string (`2.0`→`"2"`, `2.5`→`"2.5"`,
  `1e21`→`"1e+21"` — Rust's `{}` gives `"1000000000000000000000"`,
  a divergence at large magnitudes; `1e-7`→`"1e-7"` likewise). Mostly
  used as `"" + index` where index is a small non-negative integer, so
  the exotic cases are unlikely to surface in the corpus.

Implement these as a small `jsnum` module; treat the exponential-
notation stringification gap as a documented known-difference unless the
corpus exercises it.

---

## 5. Regular expressions

The canonical uses ~14 static JS regexes plus a couple built
dynamically:

- Static patterns are all plain enough for the `regex` crate:
  `^[-0-9]+$`, the regex-metachar class, the URL-slash patterns,
  ``^`\$REF:([0-9]+)`$``, `^([^$]+)\$([=~])(.+)$`, `\$\$`,
  ``\`\$([A-Z]+)\``, ``^\`(\$[A-Z]+|[^`]*)[0-9]*\`$``, `\$BT`, `\$DS`,
  ``\`([^`]+)\``. None use backreferences or lookaround, so Rust
  `regex` is fine.
- Dynamic: `join` builds `RegExp(sepre + "+$")` etc. from an *escaped*
  separator — fine. `select`'s `$LIKE` does `RegExp(term)` on a
  user-supplied string — Rust `regex` will reject some JS-isms; accept
  that as a documented limitation.
- The test runner itself uses `^/(.+)/$` to detect `/regex/` literals in
  expected values — fine.

Gotchas:

- **Replacement string syntax.** JS `String.replace(re, repl)` uses
  `$&` (whole match), `$1`, `$$`. Rust `regex` replacement uses `$0` /
  `${0}` (whole match), `$1` / `${1}`, `$$` for a literal `$`, and `\`
  is *not* special. So `escre`'s `replace(s, R_ESCAPE_REGEXP, "\\$&")`
  becomes `re.replace_all(s, r"\${0}")` (a literal backslash then the
  matched char). Write a tiny `replace(s, pat, repl)` wrapper that
  matches the canonical `replace` helper's contract (it also stringifies
  non-strings and maps `undefined`/`null` to `""` — see
  `StructUtility.ts` `replace`).
- **`g` flag.** The canonical uses `/…/g` for replace-all and a couple
  of `.match()` calls without `/g`. Map to `replace_all` vs `captures` /
  `find` accordingly.

---

## 6. Functions stored in data; closures with captured state

- `Value::Func` carries `Rc<dyn Fn(&mut Injection, &Value, &str, &Value)
  -> Value>` for injectors. `$WHEN` captures nothing but calls the
  clock; `$SPEC: || origspec` captures the original spec; `FORMATTER`
  entries are stateless closures; `select`'s `$AND`/`$OR`/`$NOT`/`$CMP`
  call back into `validate` (which calls `transform` → `inject` → a
  fresh `Injection`) — recursion through the public API is fine.
- The `Modify` hook (`_validation`) is *stored on* the `Injection` and
  *takes* the `Injection` — `inj.modify(val, key, parent, inj, store)`.
  Clone the `Rc<dyn Fn>` out before calling (see §3). Same for
  `inj.handler` (`_injecthandler` / `_validatehandler`).
- `clone()` semantics: *"function and instance values are copied, not
  cloned"* — i.e. `Rc::clone` the closure, deep-copy maps/lists into
  fresh `Rc<RefCell>`s, copy scalars, preserve sentinel identity. Much
  simpler than the TS `JSON.parse(JSON.stringify(…, $REF:N …))` trick —
  no marker dance needed. Assumes acyclic data (so does TS; a cycle
  stack-overflows in both).
- One real awkwardness: `WalkApply` is a closure passed *into* `walk`,
  and `merge` builds two of them (`before`, `after`) that both need
  `&mut` access to the same `cur`/`dst` scratch vectors. See §8.

---

## 7. Optional parameters, overloads, and `Partial<Injection>`

Rust has none of: default args, optional trailing args, overloads. The
canonical leans on all three. Options per function:

- `getprop(node, key, alt?)`, `getelem(list, key, alt?)`,
  `getdef(val, alt)`: provide a 3-arg form `get_prop(node, key, alt)`
  taking `alt: Value` (callers pass `Value::Noval` for the bare case),
  plus a 2-arg convenience `get_prop2(node, key)` *or* take
  `alt: impl Into<Value>` with a unit-ish impl. Note `getelem`'s `alt`
  can be a *function* that gets called when the element is absent
  (`0 < (T_function & typify(alt)) ? alt() : alt`) — keep that.
- `slice(val, start?, end?, mutate?)`: 4-ary; pass `Option<i64>` /
  `bool`. The numeric-input branch (clamp a number) and the
  `mutate`-in-place branch both matter (`merge` calls
  `slice(maxdepth ?? 32, 0)`; `transform_EACH` calls
  `slice(inj.keys, 0, 1, true)`).
- `items(val)` vs `items(val, apply)`: ship `items(val) ->
  Vec<(String, Value)>`; callers do `.into_iter().map(apply)`
  themselves. (Optionally `items_apply`.) The TS `apply` returns a
  generic `T`; in practice `T` is always `Value` in this codebase.
- `walk(val, before?, after?, maxdepth?, …recursion-state)`: public
  `walk(val, before, after, maxdepth)` (each callback `Option<&mut dyn
  FnMut(…)>` or a pair of overloads), private recursive `walk_impl(…,
  key, parent, path, …)` for the state. The exposed `path` slice is
  `&[String]` valid only for the callback (see §8).
- `transform(data, spec, injdef?)`, `validate(…)`, `inject(val, store,
  injdef?)`, `getpath(store, path, injdef?)`, `setpath(store, path, val,
  injdef?)`, `merge(val, maxdepth?)`: take `injdef: Option<InjectDef>`
  where `InjectDef` is a small `#[derive(Default)]` struct with the
  publicly-meaningful `Partial<Injection>` fields (`extra`, `errs`,
  `meta`, `modify`, `handler`, `base`, and the relative-path bits
  `dpath`/`dparent` used by `$REF`). Internally fold it into a full
  `Injection`.

The C++ and Go ports already grappled with this (Go added
`TransformModify`/`TransformCollect`/etc. variants because it can't even
do optional `injdef`). A Rust port can do better than Go here — one
`Option<InjectDef>` argument is enough.

---

## 8. `walk`, the path pool, and `merge`'s callbacks

`walk` (canonical, lines ~915–975):

- Recurses depth-first, calls `before` on descend and `after` on ascend,
  each callback may *replace* the value (`setprop(out, ckey, walk(child,
  …))`).
- Uses a `string[][]` *pool* — one reusable array per depth — so the
  `path` handed to callbacks isn't reallocated each step; the contract
  is "the path is valid only during the callback; clone it if you need
  to keep it" (the corpus's `match` machinery does `path.slice()`).

Rust translation choices:

1. **Drop the pool; use push/pop backtracking.** `walk_impl(val,
   before, after, maxdepth, key, parent, path: &mut Vec<String>)`:
   push the child key, recurse, pop. Hand callbacks `&path[..]`. Clean,
   idiomatic, no aliasing. Slightly more allocation than the pool but a
   `Vec<String>` reused via push/pop barely allocates after warm-up.
   (There's a `walk-bench` test in `ts/test/`, so this is on the
   project's radar — benchmark it, but correctness first.)
2. **Callbacks as `&mut dyn FnMut(Option<&str>, &Value, &Value,
   &[String]) -> Value`.** The recursive call reborrows them — fine.

`merge` (canonical, lines ~982–1098) is the gnarliest piece:

- For each input after the first, it `walk`s the override node with a
  `before` that figures out the target slot in the output and a `after`
  that writes it back, using two scratch arrays `cur` and `dst` captured
  by *both* closures. Two `FnMut`s can't both hold `&mut` to the same
  `Vec` in Rust.
- **Option A (faithful):** wrap `cur`/`dst` as
  `Rc<RefCell<Vec<Value>>>`; both closures hold `Rc` clones and
  `borrow_mut()` in tight scopes. Keeps the code shape close to
  canonical.
- **Option B (idiomatic, recommended):** reimplement `merge` as a
  direct recursive deep-merge — for two maps, merge key-by-key; for two
  lists, merge by index; node-kind mismatch → override wins; scalars →
  override wins; depth cap as in canonical. Document it in `NOTES.md` as
  a deliberate divergence "for the same reason the TS port keeps it
  walk-based: clarity in the host language." Several other ports already
  treat `merge` as a hand-written recursion rather than literally
  reusing `walk`. **This is the recommended path** — it removes the only
  genuinely hostile borrow-checker fight in the library.

Either way, watch `merge`'s in-place semantics: the canonical mutates
`list[0]` (the first input) and returns it; `transform_MERGE` relies on
that (it merges `[parent, …args, clone(parent)]` so the live `parent`
node object is the one updated, keeping node-tree references intact).
Reproduce that — `merge`'s result must *be* the (mutated) first node,
same `Rc`, not a fresh one.

---

## 9. The `Injection` state machine

`class Injection` (~20 fields: `mode`, `full`, `keyI`, `keys`, `key`,
`val`, `parent`, `path`, `nodes`, `handler`, `errs`, `meta`, `dparent`,
`dpath`, `base`, `modify`, `prior`, `extra`) plus methods `descend`,
`child`, `setval`, `toString`.

- Straightforward as a Rust struct passed `&mut`. The fields that hold
  nodes (`parent`, `val`, `dparent`, `meta`, and the `Vec<Value>`
  `nodes`) are cheap because nodes are `Rc`-backed.
- `meta` is *shared by reference* across the whole injection subtree
  (`child()` does `cinj.meta = this.meta`) and mutated (`this.meta.__d++`
  in `descend`, `S_BEXACT` flag in validate/select). Modelling `meta` as
  `Value::Map(Rc<RefCell<…>>)` makes this Just Work — `getprop`/`setprop`
  on it behave like JS's by-reference object. This is a spot where the
  `Rc<RefCell>` design pays for itself.
- `errs` is likewise a shared list (`Value::List` or `Rc<RefCell<Vec<…>>>`)
  — push-only. `child()` shares it; the root `inject` may take it from
  `injdef.errs`.
- `prior` is the parent injection. TS holds a reference; Rust can't hold
  `&mut Injection` back-references safely, and `transform_REF` /
  `injectChild` walk `inj.prior.prior` and *mutate* it (`inj.prior.keyI--`).
  Options: (a) `prior: Option<Box<Injection>>` and accept that the
  `keyI--` write lands on a *detached copy* — **wrong**, the canonical
  needs that decrement visible to the in-flight parent loop in `inject`;
  (b) restructure so `inject`'s child loop passes the relevant
  `&mut`-able state down explicitly rather than via a back-pointer; (c)
  `prior: Option<Rc<RefCell<Injection>>>` and make the whole injection
  tree `Rc<RefCell>`-managed. **This needs a decision before
  `transform_REF`/`$EACH`/`$PACK`/`$FORMAT`/`$APPLY` are implemented**
  — it's the second-trickiest structural issue after `merge`. Likely
  answer: (b) for the common case, with `child()` returning the new
  injection by value and the parent loop re-reading `childinj.keyI` /
  `childinj.keys` after each phase (which is *already* what `inject`
  does — see the `nkI = childinj.keyI; nodekeys = childinj.keys`
  re-reads after each of the three phases). The `inj.prior.keyI--` in
  `transform_REF`/`injectChild` is the awkward exception; study those
  three call sites carefully.
- `child()` allocates a new `Injection` with `path`/`nodes` extended by
  one — that's a `Vec` clone-plus-push each time (the TS uses
  `flatten([this.path, key])`). Fine; could optimise later.

---

## 10. JSON & string formatting fidelity

- **`jsonify`** must match `JSON.stringify(val, null, 2)`: 2-space
  indent, `": "` after keys, `null` for `NaN`/`Infinity`, *drop*
  `undefined`/function-valued object keys, *convert* `undefined`/
  function array elements to `null`. Plus the `offset` flag that
  left-pads every line but the first. `serde_json::to_string_pretty`
  is close but won't make these JS-specific value substitutions and uses
  its own spacing in a couple of spots — **write a small custom
  serialiser** over `Value` rather than leaning on serde. The `catch →
  "__JSONIFY_FAILED__"` branch becomes near-dead in Rust (nothing
  throws; a cycle would stack-overflow, not be catchable).
- **`stringify`** (human, *not* JSON): JSON-encodes with object keys
  sorted, then deletes *every* `"` via `R_QUOTES = /"/g` (yes, including
  quotes inside string values — a deliberate quirk), then truncates to
  `maxlen` with a `"..."` tail. There's also an ANSI-colour "pretty"
  branch (depth-coloured braces) — almost certainly not exercised by the
  corpus but present; can stub-then-fill.
- **`pathify`** renders a path (string | number | array) as a dotted
  string, dropping non-`iskey` parts, stripping `.` from string parts,
  flooring numeric parts, with `<root>` / `<unknown-path…>` fallbacks.
  Straight port.
- **`clone`** — see §6: recursive deep-copy, `Rc::clone` for funcs,
  identity-preserve for sentinels.
- **JS object integer-key reordering** is the one fidelity risk to flag:
  `JSON.stringify({b:1, "2":2, a:3})` yields `{"2":2,"b":1,"a":3}`
  because JS reorders integer-like keys to the front. An `IndexMap`
  preserves *our* insertion order instead. This only leaks through
  `jsonify` (and raw `JSON.stringify`-equivalents); `items`/`keysof`
  sort and so don't expose it. Decide whether to emulate the reorder in
  `jsonify` or accept the difference (probably accept; note it).
- **`escurl`** = `encodeURIComponent`: percent-encode UTF-8 bytes,
  uppercase hex, *not* escaping `A-Za-z0-9-_.!~*'()`. The
  `percent-encoding` crate with a custom `AsciiSet`, or ~15 hand-rolled
  lines.
- **`escre`** escapes regex metacharacters char-by-char (`[.*+?^${}()|[\]\\]`
  → `\` + char) — note it must be *regex* escaping (cf. Lua's port which
  escapes Lua-pattern chars instead — not our problem, we have a real
  regex engine).
- **`$WHEN`** → ISO-8601 UTC string `"YYYY-MM-DDTHH:MM:SS.mmmZ"`. Pull
  in `chrono` or `time`; the millisecond `.000Z` shape and calendar math
  aren't worth hand-rolling. The corpus can't assert the exact value (it
  changes) — it just needs *a* valid ISO string, possibly matched by a
  regex in a `match` block.

---

## 11. Error handling

- `transform` / `validate` `throw new Error(errs.join(" | "))` when no
  `errs` collector was supplied; otherwise they collect into it.
  Rust: return `Result<Value, StructError>` where `StructError {
  message: String }` implements `Display`/`Error` (Go does `(any,
  error)`; same idea). When `injdef.errs` is `Some`, return `Ok` and
  fill the collector; when `None`, return `Err` if any errors.
- `getpath`/`setpath`/`inject`/`merge`/all minor utils don't throw —
  keep them infallible (return `Value`, not `Result`).
- `jsonify`/`stringify`/`clone`'s internal `try/catch` → handled with
  `match`/`Result` *inside* the function, producing the
  `"__JSONIFY_FAILED__"` / `"__STRINGIFY_FAILED__"` strings; from the
  caller's view these stay infallible.
- The corpus runner matches expected errors by substring/regex against
  `err.message` (see `ts/test/runner.ts` `handleError`/`matchval`), so
  `StructError`'s `Display` must reproduce the canonical message text.

---

## 12. Names and constants

**Decided: idiomatic Rust `snake_case` for the public API**, with a
"TS name → Rust name" table in `README.md` (the top-level README already
documents per-language casing — `getpath` in JS/Py/Lua/Rb/PHP, `GetPath`
in Go/C#, `getPath` in Java — so a fourth, Rust-idiomatic convention is
in keeping with how the project already works; Go, the closest sibling,
went fully idiomatic `PascalCase` rather than mimicking TS). No
`#![allow(non_snake_case)]` escape hatch; `clippy` runs clean. The
transcription stays "human-comparable" via the name table and matching
*structure*, not matching *identifiers*.

Note that most canonical names are already lint-clean lowercase
(`rustc`'s `non_snake_case` lint only fires on *uppercase* letters, so
`getpath`/`typify`/`escre` would pass as-is) — but the API guidelines'
`snake_case` means word-separated, so we add underscores at compound
boundaries. Coined single words stay verbatim.

| TS canonical | Rust |
|---|---|
| `typename` | `type_name` |
| `getdef` | `get_def` |
| `isnode` / `ismap` / `islist` / `iskey` / `isempty` / `isfunc` | `is_node` / `is_map` / `is_list` / `is_key` / `is_empty` / `is_func` |
| `size` / `slice` / `pad` / `typify` | `size` / `slice` / `pad` / `typify` |
| `getelem` / `getprop` / `setprop` / `delprop` | `get_elem` / `get_prop` / `set_prop` / `del_prop` |
| `strkey` / `keysof` / `haskey` | `str_key` / `keys_of` / `has_key` |
| `items` / `flatten` / `filter` | `items` / `flatten` / `filter` |
| `escre` / `escurl` | `esc_re` / `esc_url` |
| `join` / `jsonify` / `stringify` / `pathify` / `clone` | `join` / `jsonify` / `stringify` / `pathify` / `clone` |
| `walk` / `merge` / `inject` / `transform` / `validate` / `select` | same |
| `getpath` / `setpath` | `get_path` / `set_path` |
| `jm` / `jt` | `jm` / `jt` (terse builders, kept verbatim) |
| `checkPlacement` / `injectorArgs` / `injectChild` | `check_placement` / `injector_args` / `inject_child` |
| `SKIP` / `DELETE` | `SKIP` / `DELETE` |
| `T_any` … `T_node` (15) | `T_ANY` … `T_NODE` (Rust const = SCREAMING_SNAKE) |
| `M_KEYPRE` / `M_KEYPOST` / `M_VAL` / `MODENAME` | `M_KEYPRE` / `M_KEYPOST` / `M_VAL` / `MODENAME` |
| `StructUtility` (class) | `StructUtility` (struct/impl bundling the free fns) |
| `Injection` / `Injector` / `WalkApply` / `Modify` (types) | same |

Internal `$NAME` transform/validate/select handlers (`transform_COPY`,
`validate_STRING`, `select_AND`, …) keep their canonical names — they're
crate-private, so casing is moot, and matching them aids the audit.
The `$DELETE`/`$COPY`/`$STRING`/`$AND`/… *spec tokens themselves* are
data strings, unchanged in every port.
- Type bit-flags: `1 << 31` overflows `i32` (the C++ port hit this too),
  so the bitfield type is **`u32`** (or `i64`). Constants: `T_ANY =
  (1u32 << 31) - 1`, `T_NOVAL = 1 << 30`, … down to `T_NODE`. Rust has
  no `t--`, so either hardcode the literals or generate them with a
  `const fn` / small macro. `typename` uses `Math.clz32(t)` →
  `t.leading_zeros() as usize` indexing into the `TYPENAME` table.
  Mode flags `M_KEYPRE=1`, `M_KEYPOST=2`, `M_VAL=4` and the `MODENAME`
  table — trivial.
- `T_symbol`, `T_instance`, and the `bigint → T_any` branch have no
  Rust analog in a JSON-shaped model. Keep the *constants* for parity
  (`validate`'s `$INSTANCE`/`$FUNCTION` checkers and `merge`'s
  `T_instance` guards reference them), but `typify` will essentially
  never *return* `T_symbol`/`T_instance`. If the corpus turns out to
  need a real "class instance", add a `Value::Instance(Rc<dyn Any>)`
  escape-hatch variant later — don't build it speculatively.
- `NONE` (TS's `undefined`) → `Value::Noval`. `S_*` string constants →
  plain `&str` / `const` items. The `R_*` regexes → `once_cell::Lazy<Regex>`
  (or `std::sync::LazyLock` on recent Rust).

---

## 13. Project layout

Mirror the other language dirs (`go/`, `php/`, `zig/` are the closest
templates):

```
rs/
  Cargo.toml            # crate "voxgig-struct" (or "voxgig_struct"); deps below
  src/
    lib.rs              # public re-exports + the StructUtility-equivalent surface
    value.rs            # Value enum, Sentinel, Func, PartialEq, Display helpers
    struct_util.rs      # the port of StructUtility.ts (minor + major utils)
                        #   — could stay one big file to track the canonical,
                        #     or split: predicates / paths / merge / inject /
                        #     transform / validate / select
    injection.rs        # Injection struct + descend/child/setval
    jsnum.rs            # JS-coercion helpers (+x, parseInt, Number, String(x))
    jsonio.rs           # custom jsonify / stringify / clone-deep
  tests/
    corpus.rs           # loads ../build/test/test.json, drives every test set
    runner/             # the runner.ts analog: marker handling (__NULL__ etc.),
                        #   order-independent deep compare, name→fn dispatch,
                        #   the mock client/utility/makeContext for SDK-flavoured
                        #   tests (cf. go/testutil/{runner,sdk,direct}.go)
    walk_bench.rs       # optional: the walk-bench analog (cargo bench / criterion)
  Makefile              # inspect / build / test / clean / reset  (slots into ../Makefile)
  README.md             # per-language guide + TS→Rust name table
  NOTES.md              # undefined-vs-null, Rc<RefCell>, merge divergence, num model, …
  REVIEW.md             # parity audit vs the TS canonical (written once it passes)
```

Also: add `rs/target/` (and `rs/Cargo.lock` policy — commit it, it's a
bin-test crate effectively) handling to the top-level `.gitignore`; add
`rs` to `LANGS` in the top-level [`Makefile`](../Makefile) and a
`test-rs` target. Bump nothing else.

**Dependencies (keep minimal):**

- `indexmap` — insertion-ordered map. **Required.**
- `regex` + `once_cell` (or stdlib `LazyLock`) — the `R_*` patterns and
  dynamic regexes. **Required.**
- `serde_json` — parse `build/test/test.json` (and maybe a serialise
  bridge). **Test-only**, ideally; the library's own `jsonify` is
  hand-rolled.
- `chrono` *or* `time` — `$WHEN`. Small; or hand-roll if avoiding deps
  matters.
- `percent-encoding` — `escurl`. Optional (hand-rollable).
- For `tests/`: a JSONic-aware parse isn't needed since `test.json` is
  already plain JSON.
- Edition 2021, MSRV pick something recent enough for `LazyLock` if used
  (else `once_cell`).

---

## 14. Implementation roadmap (phased, each phase corpus-gated)

The corpus splits naturally (`build/test/*.jsonic`): `minor`,
`getpath`, `inject`, `merge`, `walk`, `transform`, `validate`, `select`,
plus the top-level `primary` (SDK-flavoured) tests. Build bottom-up; run
the relevant corpus slice at the end of each phase.

1. **Foundation.** `Value`, `Sentinel`, `Func`, `PartialEq`/deep-equal,
   `Rc<RefCell>` plumbing, `jsnum` helpers, the `R_*` regexes, type/mode
   constants, `StructError`. No public functions yet.
2. **Predicates & trivial accessors.** `typify`, `typename`, `isnode`,
   `ismap`, `islist`, `iskey`, `isempty`, `isfunc`, `size`, `getdef`,
   `strkey`. → first chunk of `minor.jsonic`.
3. **Node ops.** `getprop`, `getelem`, `setprop`, `delprop`, `keysof`,
   `haskey`, `items`, `flatten`, `filter`. → more of `minor.jsonic`.
4. **Strings/JSON utils.** `escre`, `escurl`, `replace` (internal),
   `join`, `pad`, `slice` (incl. number-input and `mutate` branches),
   `pathify`, `jsonify`, `stringify`, `clone`, `jm`, `jt`. → rest of
   `minor.jsonic`.
5. **`walk`.** Push/pop path, callback signature. → `walk.jsonic`.
6. **`merge`.** Direct recursive deep-merge (the §8 divergence),
   in-place-on-first-node semantics. → `merge.jsonic`.
7. **`getpath` / `setpath`.** Dotted + array paths, the empty-path =
   store rule, the `injdef` relative-path bits (`$KEY`, `$GET:`,
   `$REF:`, `$META:`, `$$` escape, the trailing-`.` ascend logic, the
   `$=`/`$~` meta-path syntax), the `handler` hook. → `getpath.jsonic`.
8. **`Injection` + `inject` core.** `descend`/`child`/`setval`, the
   three-phase child loop (`M_KEYPRE`/`M_VAL`/`M_KEYPOST`), `_injectstr`
   (full-match vs partial-match injection, `$BT`/`$DS` escapes inside
   backticks, the `$NAME999` transform-name syntax), `_injecthandler`.
   → `inject.jsonic`.
9. **`transform` + the 11 commands.** `$DELETE`, `$COPY`, `$KEY`,
   `$ANNO`, `$META`, `$MERGE`, then the structural ones `$EACH`,
   `$PACK`, `$REF` (resolve the `prior`-pointer question from §9 here),
   `$FORMAT` (+ `FORMATTER` table + `injectChild`), `$APPLY`.
   `checkPlacement`, `injectorArgs`, `injectChild`. → `transform.jsonic`.
10. **`validate` + the 15 checkers.** `validate_STRING`, `validate_TYPE`
    (covers `$NUMBER`/`$INTEGER`/`$DECIMAL`/`$BOOLEAN`/`$NULL`/`$NIL`/
    `$MAP`/`$LIST`/`$FUNCTION`/`$INSTANCE`), `$ANY`, `$CHILD`, `$ONE`,
    `$EXACT`; `_validation` (the modify hook), `_validatehandler`;
    `$OPEN` open-object handling; `_invalidTypeMsg` text. →
    `validate.jsonic`.
11. **`select` + operators.** `$AND`/`$OR`/`$NOT`/`$GT`/`$LT`/`$GTE`/
    `$LTE`/`$LIKE`, the `$KEY`-injection trick, the `$OPEN` walk over the
    query. → `select.jsonic`.
12. **`StructUtility`-equivalent surface + the SDK/`primary` tests.**
    The struct/module that bundles everything (TS's `StructUtility`
    class), the mock client/utility/`makeContext` in `tests/runner/`
    (port `go/testutil/sdk.go` + `direct.go`), the `primary.check`
    tests. → full `test.json` green.
13. **Docs & audit.** `README.md` (name table, install, quick-start),
    `NOTES.md` (the divergences), `REVIEW.md` (parity matrix entry),
    wire `rs` into the top-level `Makefile` and `REPORT.md`.
14. **Polish.** `clippy`, `walk-bench` parity, doc-comments, decide the
    `Cargo.lock` / `target/` ignore bits.

---

## 15. Risk register / open questions

| # | Item | Why it matters | Leaning |
|---|------|----------------|---------|
| 1 | `Rc<RefCell>` borrow discipline | A naive transcription panics at runtime; this is the pervasive cost of the design. | Accept; enforce the "accessors return owned `Value`, never leak a guard" rule (§3); test hard. |
| 2 | `merge` walk-callbacks → two `&mut`-capturing `FnMut`s | Borrow-checker-hostile as written. | Reimplement `merge` as direct recursion (§8 Option B); document the divergence. |
| 3 | `Injection.prior` back-pointer + `inj.prior.keyI--` in `$REF`/`injectChild` | Can't safely hold `&mut` back-references; the decrement must be visible to the in-flight parent loop. | Pass mutable child-loop state down explicitly, re-reading `childinj.keyI`/`childinj.keys` (already the pattern in `inject`); treat `$REF`/`injectChild` as the studied exceptions (§9). Fallback: `Rc<RefCell<Injection>>` throughout. |
| 4 | `Num(f64)` vs `enum N { Int, Float }` | Affects every numeric site; `f64` is more JS-faithful but less Rust-idiomatic; `Int/Float` needs normalisation rules. | `Num(f64)` + `is_integer`/`to_int32` helpers (§4); note the alternative. |
| 5 | API naming | "Real Rust crate" + clippy vs line-by-line comparability with TS. | **Decided:** idiomatic `snake_case` (`get_path`, `is_node`, …), no `allow(non_snake_case)`, with a TS→Rust name table in `README.md` (§12). |
| 6 | `Rc<RefCell>` vs `Arc<Mutex>` (thread safety) | `Send`/`Sync` would touch every access site and add lock cost. | Single-threaded `Rc<RefCell>`; document "not thread-safe, like the JS canonical". Arc variant = out of scope. |
| 7 | Number→string and large-magnitude exponent notation | Rust `{}` on `1e21` ≠ JS `"1e+21"`; `0.0000001` likewise. | Mostly used on small integer indices, so likely a non-issue; document as a known difference unless the corpus hits it. |
| 8 | JS object integer-key reordering in `JSON.stringify` | `jsonify` could differ from canonical for maps with numeric-string keys. | Probably accept the `IndexMap`-order behaviour; note it; emulate only if the corpus demands. |
| 9 | `T_symbol` / `T_instance` / `bigint` | No JSON-shaped Rust analog. | Keep constants for parity; `typify` won't return them; add a `Value::Instance` escape hatch only if the corpus needs it (§12). |
| 10 | SDK/`primary` test machinery (mock client/utility/`makeContext`) | A non-trivial slice of the corpus needs it; it's ~3 files in `go/testutil/`. | Port it in phase 12; until then, run the per-function corpus slices and skip `primary`. |
| 11 | Corpus runner deep-equality + marker semantics (`__NULL__`/`__UNDEF__`/`__EXISTS__`) and `/regex/` `match` entries | Getting the comparator wrong = false reds/greens. | Port `ts/test/runner.ts` carefully; map `deepStrictEqual` to an order-independent deep compare over `Value`; reuse the canonical's own `walk`/`getpath`/`stringify` in the `match` path exactly as the TS runner does. |
| 12 | `$LIKE` / user-supplied `RegExp(term)` in `select` | Rust `regex` rejects some JS regex syntax. | Document the limitation; the corpus's `$LIKE` patterns are simple. |
| 13 | Crate name & module split | `voxgig-struct` (crate) vs `voxgig_struct` (lib path); one big file vs modules. | Crate `voxgig-struct`, lib `voxgig_struct`; start with a near-monolithic `struct_util.rs` for comparability, split if it helps. |

---

## 16. Bottom line

The hard 20% is all in one place: **shared mutable, reference-stable
nodes** (`merge`, `inject`/`transform`/`validate`/`select`, the
`Injection` state machine). `Rc<RefCell<…>>` + `IndexMap` is the right
substrate — it's the direct analog of what C++ (`shared_ptr<List/Map>`),
Go/PHP (`ListRef`), and Zig (`MapRef`/`ListRef`) already did — and the
borrow-checker tax is paid up front by one discipline rule (§3) plus two
or three studied exceptions (`merge`'s callbacks, `$REF`'s
`prior.keyI--`). The other 80% — predicates, path ops, string/JSON
utilities, the type bitfield, the transform/validate command tables — is
a mechanical, well-understood transcription. The corpus
(`build/test/test.json`) is the unambiguous oracle at every step, so the
work is checkable phase by phase. Estimated shape: ~2,500–3,500 lines of
library + ~800–1,200 lines of test harness, comparable to the Go port.
