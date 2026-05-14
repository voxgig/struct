# Struct for Rust

> Rust port of the canonical TypeScript implementation.
> Status: **complete** — the full shared corpus passes (`cargo test` → 1187
> checks; `cargo clippy` clean): minor utilities, `walk`, `merge`, `getpath`,
> `setpath`, `inject`, `transform` (all 11 commands), `validate` (all 15
> checkers), `select` (all operators), and the `primary.check` SDK test.

For motivation, the language-neutral concepts, and the cross-language parity
matrix, see the [top-level README](../README.md) and [`REPORT.md`](../REPORT.md).

## Build & test

Inside the monorepo:

```bash
cd rust
cargo build
cargo test          # runs the shared corpus (../build/test/test.json) against
                    # the implemented subsets
```

Tested with stable Rust 1.80+ (edition 2021). Crate: `voxgig-struct`;
library path `voxgig_struct`. **Zero runtime third-party dependencies** —
the insertion-ordered map type lives in-tree at
[`src/ordered_map.rs`](./src/ordered_map.rs); lazy statics use
`std::sync::LazyLock`; the regex engine lives at
[`src/re.rs`](./src/re.rs). `serde_json` appears under
`[dev-dependencies]` only — used by the test corpus loader.

```rust
use voxgig_struct::{Value, get_path};

let store = Value::map_of([(
    "db".to_string(),
    Value::map_of([("host".to_string(), Value::str("localhost"))]),
)]);
let host = get_path(&store, &Value::str("db.host"), None);
// host == Value::Str("localhost")
```

## In-memory data model

```rust
pub enum Value {
    Noval,                                       // TS `undefined` — property absent
    Null,                                        // JSON null — distinct from Noval
    Bool(bool),
    Num(f64),                                    // one numeric kind; integer-ness derived
    Str(String),
    List(Rc<RefCell<Vec<Value>>>),               // reference-stable, mutable in place
    Map(Rc<RefCell<IndexMap<String, Value>>>),   // insertion-ordered, reference-stable
    Func(Rc<dyn Fn(&Inj, &Value, &str, &Value) -> Value>),  // callable values in data
    Sentinel(&'static Sentinel),                 // SKIP / DELETE — pointer identity
}
```

`List` / `Map` are heap-allocated and reference-counted, so a mutation through
one `Value` is visible to every holder — this is the canonical "lists are
mutable and reference-stable" invariant. Not thread-safe (single-threaded data
model, like the JS canonical).

## Function values

Callables embedded *in* the data (`Value::Func`) all use **one signature** —
`Fn(&Inj, &Value /*val*/, &str /*ref*/, &Value /*store*/) -> Value` — created
with `Value::func(closure)`. The TypeScript canonical is dynamically typed and
uses a few different shapes for the same slots; the Rust port unifies them onto
this signature, so the calling conventions differ slightly from TS:

| Where | Rust call | Read for | TS canonical |
|---|---|---|---|
| Transform commands / validate checkers / select operators / the `handler` | `f(inj, val, ref, store)` | all four | `(inj, val, ref, store)` — same |
| `$WHEN` / `$BT` / `$DS` / `$SPEC` thunks | `f(inj, val, ref, store)` (args ignored) | — | `()` — args ignored either way |
| `$APPLY` (`['`$APPLY`', applyFn, child]`) | `f(inj, val, "", store)` | `val` = the resolved `child`; `store`; `inj` = the child injection | `apply(resolved, store, cinj)` — same data, different order |
| `$FORMAT` user formatter (`['`$FORMAT`', fn, child]`) | applied to **each node** of the resolved `child`; `f(inj, val, "", store)` | `val` = the current node | `walk(resolved, formatter)` — TS's `formatter` also gets `(key, parent, path)`; the Rust form only sees `val` |
| `get_elem(list, key, alt)` when `alt` is callable and the element is absent | `f(inj, val, "", store)` (a fresh throwaway injection, `Noval` val/store, empty ref) | — | `alt()` — args ignored either way |

In short: a `Value::func` closure that reads its `val` argument (and `store` /
`inj` if needed) behaves correctly everywhere. For `$FORMAT`, prefer the seven
**built-in named formatters** — `identity`, `upper`, `lower`, `string`,
`number`, `integer`, `concat` — passed as a string; a user function works but
can't see the walk key / parent / path. (Note: callbacks passed as *parameters*
— `walk`'s `before`/`after`, `filter`'s `check`, `InjectDef::modify` /
`::handler` — are ordinary Rust closures and keep their full signatures.)

## Name mapping (TS canonical → Rust)

The Rust API uses idiomatic `snake_case`. The repo already documents per-language
casing (`getpath` in JS/Py/Lua/Rb/PHP, `GetPath` in Go/C#, `getPath` in Java); the
Rust convention is `get_path`.

| TS | Rust | TS | Rust |
|---|---|---|---|
| `typename` | `type_name` | `keysof` | `keys_of` |
| `getdef` | `get_def` | `haskey` | `has_key` |
| `isnode` / `ismap` / `islist` | `is_node` / `is_map` / `is_list` | `strkey` | `str_key` |
| `iskey` / `isempty` / `isfunc` | `is_key` / `is_empty` / `is_func` | `escre` / `escurl` | `esc_re` / `esc_url` |
| `getelem` / `getprop` | `get_elem` / `get_prop` | `getpath` / `setpath` | `get_path` / `set_path` |
| `setprop` / `delprop` | `set_prop` / `del_prop` | `checkPlacement` | `check_placement` |
| `getdef` | `get_def` | `injectorArgs` / `injectChild` | `injector_args` / `inject_child` |
| `size` / `slice` / `pad` / `typify` | (same) | `clone` / `walk` / `merge` / `inject` | (same) |
| `items` / `flatten` / `filter` / `join` | (same) | `transform` / `validate` / `select` | (same) |
| `jsonify` / `stringify` / `pathify` | (same) | `jm` / `jt` | (same) |

Type constants are SCREAMING_SNAKE: `T_ANY` … `T_NODE`, `M_KEYPRE` / `M_KEYPOST`
/ `M_VAL`. Sentinels: `SKIP`, `DELETE`.

## Optional parameters

Rust has no optional/overloaded parameters, so:

- `get_prop(node, key, alt)` / `get_elem(list, key, alt)` / `get_def(val, alt)`
  take `alt: Value` (pass `Value::Noval` for the bare case). `get_elem_or_else`
  takes a lazy alt closure.
- `slice(val, start: Option<i64>, end: Option<i64>, mutate: bool)`.
- `pad(s, padding: Option<i64>, padchar: Option<String>)`.
- `walk(val, before: Option<&mut WalkClosure>, after: Option<&mut WalkClosure>, maxdepth: Option<i64>)`.
- `merge(list, maxdepth: Option<i64>)`.
- `get_path` / `set_path` / `transform` / `validate` / `inject` take
  `injdef: Option<&InjectDef>` (a small `Default` struct of the publicly-set
  `Partial<Injection>` fields).
- `items(node)` returns a `Value::List` of `[key, value]` pairs; `items_vec`
  returns `Vec<(String, Value)>`. Likewise `keys_of` / `keysof_vec`, `filter` /
  `filter_vals`.

See [`REPORT.md`](../REPORT.md#rust-rust) for the rust-port adaptations
write-up, and [`../NOTES.md`](../NOTES.md) for cross-port quirks.
