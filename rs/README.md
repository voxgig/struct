# Struct for Rust

> Rust port of the canonical TypeScript implementation.
> Status: **complete** — the full shared corpus passes (`cargo test` → 1122
> checks; `cargo clippy` clean): minor utilities, `walk`, `merge`, `getpath`,
> `setpath`, `inject`, `transform` (all 11 commands), `validate` (all 15
> checkers), `select` (all operators), and the `primary.check` SDK test. See
> [`NOTES.md`](./NOTES.md) and [`PLAN.md`](./PLAN.md).

For motivation, the language-neutral concepts, and the cross-language parity
matrix, see the [top-level README](../README.md) and [`REPORT.md`](../REPORT.md).

## Build & test

Inside the monorepo:

```bash
cd rs
cargo build
cargo test          # runs the shared corpus (../build/test/test.json) against
                    # the implemented subsets
```

Tested with a recent stable Rust (edition 2021). Crate: `voxgig-struct`;
library path `voxgig_struct`.

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

See [`NOTES.md`](./NOTES.md) for the full set of decisions and what's still staged.
