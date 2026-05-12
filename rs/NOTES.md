# Rust Implementation Notes

Port of the canonical TypeScript implementation (`ts/src/StructUtility.ts`).
Design rationale and the full challenge analysis live in [`PLAN.md`](./PLAN.md);
this file records the concrete decisions and the current state.

## Status

| Subsystem | State | Corpus |
|---|---|---|
| Value type, type bit-flags, mode flags, sentinels, jsnum coercions | done | — |
| Minor utilities (`typename`, `typify`, predicates, `getprop`/`getelem`/`setprop`/`delprop`, `keysof`/`items`/`haskey`, `flatten`/`filter`, `escre`/`escurl`/`join`, `jsonify`/`stringify`/`pathify`/`clone`, `size`/`slice`/`pad`, `jm`/`jt`, `getdef`/`strkey`) | done | `minor.*` ✓ |
| `walk` | done | `walk.basic` ✓ |
| `merge` | done (walk-based, `Rc<RefCell>` scratch vectors) | `merge.cases` / `merge.array` / `merge.integrity` / `merge.basic` ✓ |
| `getpath` / `setpath` | done (incl. relative `..` ascents, `$KEY`/`$GET:`/`$REF:`/`$META:`, `$$` escape, meta-path `$=`/`$~`, custom handler) | `getpath.basic` / `getpath.relative` / `getpath.special` / `getpath.handler` ✓ |
| `inject`, `transform` (+ 11 commands), `validate` (+ 15 checkers), `select` (+ operators) | **staged** — `unimplemented!()` stubs pointing at `PLAN.md`; the `Injection` state machine, `InjectDef`, the default handler, and the structural plumbing are in place | not yet wired |
| Corpus test runner (`tests/corpus.rs`) | covers the implemented subsets (712 checks) | — |
| Top-level `primary` / SDK tests (mock client / `makeContext`) | not started | — |

Running `cargo test` exercises the implemented corpus subsets.

## Key decisions (see PLAN.md for the reasoning)

- **`Value` enum** with `Rc<RefCell<Vec<Value>>>` lists, `Rc<RefCell<IndexMap<String, Value>>>`
  maps (insertion-ordered via the `indexmap` crate), `Noval` (TS `undefined`) distinct
  from `Null` (JSON null), `Func(Rc<dyn Fn(&Inj, &Value, &str, &Value) -> Value>)`, and
  `Sentinel(&'static Sentinel)` (SKIP / DELETE, pointer identity).
- **Single numeric variant `Num(f64)`** — integer-ness derived via `f.fract() == 0.0`
  (`Number.isInteger(2.0) === true`). JS coercions (`+x`, `Number(x)`, `String(x)`,
  `n | 0`) live in `value.rs` as `js_to_number` / `js_string` / `js_to_int32`.
  Known gap: Rust `{}` on very large/small magnitudes doesn't switch to exponent
  notation like JS (`1e21` → `"1000000000000000000000"` vs `"1e+21"`); not exercised
  by the corpus.
- **idiomatic `snake_case`** public API (`get_path`, `is_node`, `set_prop`, `esc_re`, …);
  see the TS→Rust name table in [`README.md`](./README.md). No `#![allow(non_snake_case)]`.
  Internal `$NAME` handlers keep their canonical names for audit comparability.
- **`undefined` vs `null`**: `Value::Noval` vs `Value::Null`, never collapsed and never
  represented by a sentinel string. The corpus runner uses the `__NULL__` / `__UNDEF__`
  / `__EXISTS__` marker strings exactly as `ts/test/runner.ts` does.
- **`merge`** is implemented walk-based to track the canonical; the `cur`/`dst` scratch
  vectors are `Rc<RefCell<Vec<Value>>>` (two `FnMut` callbacks can't both hold `&mut` to
  the same `Vec`). Result is `list[0]` mutated in place, as the canonical requires.
- **`walk`** uses push/pop path backtracking (not the canonical's reusable array pool);
  callbacks are `&mut dyn FnMut(&Value, &Value, &Value, &[String]) -> Value` with `key`
  = `Noval` at the root and a `Str` for every descendant.
- **`Injection`** is `Rc<RefCell<Injection>>` (`Inj`) because the inject machinery keeps
  live mutable back-references (`prior`) — see PLAN.md §9. The borrow discipline (PLAN.md
  §3) — accessors return owned `Value`s, never leak a `Ref`/`RefMut` guard across a call —
  is the rule that keeps `RefCell` from panicking.
- **`transform` / `validate`** return `Result<Value, StructError>` (the `throw new Error`
  case becomes `Err`); the infallible utilities return `Value`.
- **`escre`** does regex-metachar escaping via a closure replacement (`$&` → `format!("\\{}",
  &caps[0])`); `escurl` is `encodeURIComponent` hand-rolled over UTF-8 bytes (not escaping
  `A-Za-z0-9-_.!~*'()`).

## What's not done / next

- `inject` + the three-phase child loop + `_injectstr` (full-match vs partial, `$BT`/`$DS`
  escapes, `$NAME999` transform-name syntax).
- `transform` + the 11 commands (`$DELETE`/`$COPY`/`$KEY`/`$ANNO`/`$META`/`$MERGE`/`$EACH`/
  `$PACK`/`$REF`/`$FORMAT`/`$APPLY`), `checkPlacement`/`injectorArgs`/`injectChild`, the
  `FORMATTER` table. The `prior.keyI--` in `$REF`/`injectChild` is the studied exception
  (PLAN.md §9 item 3).
- `validate` + the 15 checkers, `_validation`/`_validatehandler`, `$OPEN` open-object
  handling, `_invalidTypeMsg` text.
- `select` + `$AND`/`$OR`/`$NOT`/`$GT`/`$LT`/`$GTE`/`$LTE`/`$LIKE`.
- The top-level `primary` SDK tests (mock client / utility / `makeContext`; cf.
  `go/testutil/`).
