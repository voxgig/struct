# AGENTS.md — Rust port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the Rust port.

> **This is a port, not the canonical.** Behaviour is defined by the
> TypeScript source and pinned by the shared corpus. A wrong output here is
> a *port* bug to fix against the corpus — never change behaviour in this
> port alone.

## Layout

```
rust/
├── src/lib.rs           # crate root: module decls + the `pub use` public surface
├── src/value.rs         # the `Value` enum (Noval/Null/.../Func/Sentinel) + coercions
├── src/consts.rs        # T_* type flags, M_* mode constants
├── src/ordered_map.rs   # in-tree insertion-ordered map (no `indexmap` crate)
├── src/re.rs            # in-tree RE2-subset Thompson NFA (no `regex` crate)
├── src/mini.rs          # minor utilities + the re_* regex wrappers
├── src/major.rs         # walk, merge, get/set_path, inject, transform, validate, select
├── Cargo.toml           # crate `voxgig-struct`, lib `voxgig_struct`, edition 2021
└── Makefile             # build / test / lint / audit / inspect targets
```

The public API is the `pub use …` re-export block in `src/lib.rs`.
`../tools/check_parity.py` compares that list against the canonical export,
so adding/removing a public name there changes what parity requires (it
matches case/underscore-insensitively, e.g. `get_path` ↔ `getpath`).

## Commands

```bash
cargo build
cargo test          # runs the shared corpus (../build/test/test.json)
make lint           # cargo clippy --all-targets --all-features -- -D warnings
                    #   + cargo fmt --all -- --check
make audit          # cargo audit (RustSec advisory DB)
make inspect        # print toolchain + crate version
```

`make build` / `make test` / `make lint` wrap the same commands; from the
repo root, `make test-rust` / `make lint-rust` do too. Stable Rust 1.80+
(needs `std::sync::LazyLock`).

## Conventions specific to this port

- **Casing:** idiomatic `snake_case` (`get_path`, `set_path`, `get_prop`,
  `re_compile`, `type_name`, `keys_of`, …). Type constants are
  `SCREAMING_SNAKE` (`T_STRING`, `M_VAL`); sentinels are `SKIP` / `DELETE`.
  The full TS→Rust name table is in [`README.md`](./README.md#name-mapping-ts-canonical--rust).
- **Zero runtime dependencies.** `Cargo.toml` lists none under
  `[dependencies]`; `serde_json` is `[dev-dependencies]` only (the corpus
  loader). Do **not** add `indexmap`, `regex`, or any runtime crate — the
  ordered map and regex engine are in-tree on purpose.
- **No optional parameters.** Trailing optionals are `Option<_>`
  (`maxdepth: Option<i64>`, `injdef: Option<&InjectDef>`) or an explicit
  `Value::Noval` argument. Keep the `_vec` / `_vals` companions
  (`items_vec`, `keysof_vec`, `filter_vals`) alongside the `Value`-returning
  canonical names.
- **`transform` / `validate` return `Result<Value, StructError>`** — they do
  not panic on validation failure. The other entry points return `Value`.

## Gotchas

- **`Noval` is not `Null`.** `Value::Noval` is TS `undefined` (absent);
  `Value::Null` is JSON null. Group A readers (`get_prop`, `get_elem`,
  `has_key`, `is_empty`, `is_node`) treat a stored `Null` as absent; Group B
  processors preserve it. Re-read the Group A/B rule before touching any
  read/merge/clone path — it is the most common port bug.
- **Don't reorder map keys.** Key order is observable through `keys_of`,
  `items`, and `jsonify`, and the inject machinery's `$`-suffix partition
  relies on it. Fix comparisons or `OrderedMap` usage, not the order.
- **Function values use one signature.** Callables in the data are
  `Fn(&Inj, &Value, &str, &Value) -> Value` (`Value::func`), so `$APPLY` /
  `$FORMAT` calling conventions differ slightly from TS — see the table in
  [`README.md`](./README.md#function-values). Parameter callbacks (`walk`'s
  `before`/`after`, `filter`'s `check`, `InjectDef::modify`/`::handler`) are
  ordinary closures with full signatures.
- **`Value` is `!Send + !Sync`** (`Rc<RefCell<…>>`). The model is
  single-threaded, like the JS canonical; don't try to share a `Value`
  across threads.
- **Regex stays in the RE2 subset.** The in-tree engine is a Thompson NFA;
  backref/lookaround patterns may *compile* but won't match (`re_test`
  returns `false`). Zero-width `re_replace` returns `"XXbXcX"` (ECMA
  convention), differing from Go's RE2 — that divergence is documented in
  [`../REGEX_PATHOLOGICAL.md`](../REGEX_PATHOLOGICAL.md); do not "fix" it.
- **Editing here is downstream.** A behaviour change starts in canonical
  TypeScript + the corpus, then ports here. After it: `cargo test` +
  `make lint` green, then `python3 ../tools/check_parity.py` and the other
  ports' tests.

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  [`../tools/check_parity.py`](../tools/check_parity.py)
