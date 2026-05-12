# Rust Implementation Notes

Port of the canonical TypeScript implementation (`ts/src/StructUtility.ts`).
The full challenge analysis and the original phased roadmap live in
[`PLAN.md`](./PLAN.md).

## Status

The library is **functionally complete** against the shared corpus: all eight
`struct/*` test files pass (`cargo test` → 1120 checks). The only thing not
ported is the top-level `primary` SDK-integration test (the mock client /
utility / `makeContext` harness — cf. `go/testutil/`), which exercises an
example SDK *built on* `struct`, not `struct` itself.

| Subsystem | State | Corpus |
|---|---|---|
| `Value` type, type bit-flags, mode flags, sentinels, jsnum coercions | done | — |
| Minor utilities (`typename`, `typify`, predicates, `getprop`/`getelem`/`setprop`/`delprop`, `keysof`/`items`/`haskey`, `flatten`/`filter`, `escre`/`escurl`/`join`, `jsonify`/`stringify`/`pathify`/`clone`, `size`/`slice`/`pad`, `jm`/`jt`, `getdef`/`strkey`) | done | `minor.*` ✓ |
| `walk` | done | `walk.basic` ✓ |
| `merge` | done (walk-based, `Rc<RefCell>` scratch vectors) | `merge.*` ✓ |
| `getpath` / `setpath` | done | `getpath.*` ✓ |
| `Injection` state machine, `inject`, `_injectstr`, `_injecthandler` | done | `inject.*` ✓ |
| `transform` + all 11 commands (`$DELETE`, `$COPY`, `$KEY`, `$ANNO`, `$MERGE`, `$EACH`, `$PACK`, `$REF`, `$FORMAT`, `$APPLY`; `$META` recognised) + `$BT`/`$DS`/`$WHEN`/`$SPEC` thunks + `checkPlacement`/`injectorArgs`/`injectChild` + `FORMATTER` | done | `transform.*` ✓ |
| `validate` + all 15 checkers (`$STRING`, `$NUMBER`/`$INTEGER`/`$DECIMAL`/`$BOOLEAN`/`$NULL`/`$NIL`/`$MAP`/`$LIST`/`$FUNCTION`/`$INSTANCE` via `validate_TYPE`, `$ANY`, `$CHILD`, `$ONE`, `$EXACT`) + `_validation` (modify hook) + `_validatehandler` + `_invalidTypeMsg` + `$OPEN` open-objects | done | `validate.*` ✓ |
| `select` + operators (`$AND`, `$OR`, `$NOT`, `$GT`, `$LT`, `$GTE`, `$LTE`, `$LIKE`) | done | `select.*` ✓ |
| Corpus test runner (`tests/corpus.rs`) | covers all `struct/*` slices (1120 checks) | — |
| Top-level `primary` / SDK tests (mock client / `makeContext`) | not ported (out of scope — example SDK, not the library) | — |

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
  live mutable back-references (`prior`) — e.g. `$REF`/`injectChild` mutate `inj.prior.key_i`.
  The borrow discipline (PLAN.md §3) — accessors return owned `Value`s, never leak a
  `Ref`/`RefMut` guard across a call — is the rule that keeps `RefCell` from panicking.
- **`transform` / `validate`** return `Result<Value, StructError>` (the `throw new Error`
  case becomes `Err`); the infallible utilities return `Value`.
- **`escre`** does regex-metachar escaping via a closure replacement; `escurl` is
  `encodeURIComponent` hand-rolled over UTF-8 bytes (not escaping `A-Za-z0-9-_.!~*'()`).
- **`$WHEN`** uses `std::time::SystemTime` + a hand-rolled ISO-8601 UTC formatter (no
  `chrono`/`time` dependency).

## Not ported

- The top-level `primary.check` SDK-integration test (mock client / utility /
  `makeContext`, cf. `ts/test/sdk.ts` + `ts/test/utility/`). This is an example
  SDK that uses `struct`, not part of the library.
- `T_symbol` / `T_instance` constants exist for parity but are never returned by
  `typify` (no JSON-shaped Rust analog); user-supplied `$APPLY` functions and
  user formatters in `$FORMAT` are best-effort (the corpus only exercises named
  formatters and the `$APPLY` error paths).
