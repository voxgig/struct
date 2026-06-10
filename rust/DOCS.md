# Struct for Rust — Comprehensive Guide

> A **port** of the canonical TypeScript implementation. Behaviour is
> defined by the canonical source and pinned by the shared corpus; this
> port reproduces it in idiomatic Rust. This guide is the in-depth
> companion to [`README.md`](./README.md) (the quick-start + signature
> reference) and the language-neutral [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — install and learn the whole API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md); this section adds the exact Rust semantics
  and types.
- **[Explanation](#4-explanation--port-specifics)** — the model, the port's
  role, and Rust-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Install

`voxgig-struct` is part of the monorepo; work from a clone:

```bash
cd rust
cargo build
cargo test          # runs the shared corpus from ../build/test/test.json
```

Crate `voxgig-struct`; library `voxgig_struct`; edition 2021; stable Rust
1.80+ (needs `std::sync::LazyLock`). **Zero runtime dependencies** —
`serde_json` is a dev-dependency only, used by the test corpus loader.

### Your first program

Everything flows through the in-tree [`Value`](#the-value-enum) enum.
Construct it with the helper constructors; read it back with pattern
matching or the typed accessors.

```rust
use voxgig_struct::{merge, get_path, Value};

let config = merge(
    &Value::list(vec![
        // defaults
        Value::map_of([(
            "db".into(),
            Value::map_of([
                ("host".into(), Value::str("localhost")),
                ("port".into(), Value::Num(5432.0)),
            ]),
        )]),
        // overrides
        Value::map_of([(
            "db".into(),
            Value::map_of([("host".into(), Value::str("db.internal"))]),
        )]),
    ]),
    None,
);

get_path(&config, &Value::str("db.host"), None); // Value::Str("db.internal")
get_path(&config, &Value::str("db.port"), None); // Value::Num(5432.0) — survived the merge
```

### Build up the rest of the API

Each call below has the same meaning in every port; only the syntax
changes. Read [`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the
full language-neutral walkthrough; the Rust-flavoured version:

```rust
use voxgig_struct::{transform, validate, walk, select, Value};

// Reshape by example — the spec mirrors the output you want.
transform(
    &Value::map_of([
        ("user".into(), Value::map_of([
            ("first".into(), Value::str("Ada")),
            ("last".into(),  Value::str("Lovelace")),
        ])),
        ("age".into(), Value::Num(36.0)),
    ]),
    &Value::map_of([
        ("name".into(),    Value::str("`user.first`")),
        ("surname".into(), Value::str("`user.last`")),
        ("years".into(),   Value::str("`age`")),
    ]),
    None,
).unwrap(); // { name: "Ada", surname: "Lovelace", years: 36 }

// Validate by example — leaves are type checkers; Err on mismatch.
validate(&data, &Value::map_of([
    ("name".into(), Value::str("`$STRING`")),
    ("age".into(),  Value::str("`$INTEGER`")),
]), None).unwrap();

// Walk the tree — replace values on ascent (the `after` callback).
let mut after = |_k: &Value, val: &Value, _p: &Value, _path: &[String]| {
    if val.is_null() { Value::str("DEFAULT") } else { val.clone() }
};
walk(tree, None, Some(&mut after), None);

// Select children by query — each match tagged with its $KEY.
select(&children, &Value::map_of([("age".into(), Value::Num(30.0))]));
// [ { age: 30, $KEY: "a" } ]
```

`transform` and `validate` return `Result<Value, StructError>`; the rest
return a `Value` directly. A missing path is never an error — `get_path`
returns `Value::Noval`.

---

## 2. How-to guides

### Read a deep value, with a default

`get_path(store, path, injdef)` walks a dot path into the store:

<!-- example: getpath/basic#deep -->
```rust
let store = Value::map_of([(
    "a".into(),
    Value::map_of([(
        "b".into(),
        Value::map_of([("c".into(), Value::Num(42.0))]),
    )]),
)]);
get_path(&store, &Value::str("a.b.c"), None); // Value::Num(42.0)
```
<!-- => 42 -->

```rust
get_path(&store, &Value::str("a.b.c"), None);          // Noval if missing
get_prop(&node, &Value::str("c"), Value::str("alt"));  // alt if the single key is missing
get_def(maybe, Value::str("alt"));                     // alt only when `maybe` is Noval
```
`get_path` also takes an **array path** when a key contains a dot:
`get_path(&store, &Value::list(vec![Value::str("a.b"), Value::str("c")]), None)`.

### Collect all validation errors instead of returning `Err`
```rust
use voxgig_struct::{validate, InjectDef, Value};

let errs = Value::empty_list();
let def = InjectDef { errs: Some(errs.clone()), ..Default::default() };
validate(&payload, &spec, Some(&def)).ok();
// `errs` (a Value::List) now holds the collected messages; inspect it.
```
Supply an `errs` collector via `InjectDef` and `validate` returns `Ok`
instead of `Err`, accumulating messages into the list you passed.

### Map a sub-spec over a list (`$EACH`)

A command like `$EACH` appears in **value** position — as the first element of a
list `["`$EACH`", path, subspec]` — mapping the sub-spec over every entry at
`path`:

<!-- example: transform/each#basic -->
```rust
transform(
    &Value::map_of([
        ("v".into(), Value::Num(1.0)),
        ("a".into(), Value::list(vec![
            Value::map_of([("q".into(), Value::Num(13.0))]),
            Value::map_of([("q".into(), Value::Num(23.0))]),
        ])),
    ]),
    &Value::map_of([(
        "x".into(),
        Value::map_of([(
            "y".into(),
            Value::list(vec![
                Value::str("`$EACH`"),
                Value::str("a"),
                Value::map_of([
                    ("q".into(), Value::str("`$COPY`")),
                    ("r".into(), Value::str("`.q`")),
                    ("p".into(), Value::str("`...v`")),
                ]),
            ]),
        )]),
    )]),
    None,
).unwrap();
// { x: { y: [ { q: 13, r: 13, p: 1 }, { q: 23, r: 23, p: 1 } ] } }
```
<!-- => {"x": {"y": [{"q": 13, "r": 13, "p": 1}, {"q": 23, "r": 23, "p": 1}]}} -->

### Write a custom transform function (`$APPLY`)
```rust
use voxgig_struct::{transform, InjectDef, Value};

let sum = Value::func(|_inj, val, _ref, _store| {
    // `val` is the resolved child argument to $APPLY.
    /* fold it and return a Value::Num */ val.clone()
});
let def = InjectDef {
    extra: Some(Value::map_of([("sum".into(), sum)])),
    ..Default::default()
};
transform(&data, &spec, Some(&def)).unwrap();
```
Register the function under `extra`; reference it by name in the spec
(`{ total: { "`$APPLY`": ["sum", "`items`"] } }`). A custom function may
return the `SKIP` / `DELETE` sentinels to omit/remove the current key. See
the [function-value table](./README.md#function-values) for the exact call
shape per command — it differs slightly from TS.

A command must be a **list value**. Putting `$APPLY` directly under a map (in
key/value position rather than as the first element of a list) is an error —
`transform` returns `Err`:

<!-- example: transform/apply#badkey -->
```rust
transform(&Value::empty_map(), &Value::map_of([("x".into(), Value::str("`$APPLY`"))]), None);
// Err: "$APPLY: invalid placement in parent map, expected: list."
```
<!-- throws: invalid placement in parent map -->

### Keep a `walk` path past the callback
```rust
let mut seen: Vec<Vec<String>> = Vec::new();
let mut before = |_k: &Value, val: &Value, _p: &Value, path: &[String]| {
    seen.push(path.to_vec());   // the path slice is reused — clone to retain it
    val.clone()
};
walk(tree, Some(&mut before), None, None);
```

### Serialise deterministically

`jsonify` pretty-prints by default (2-space indent); pass `JsonFlags { indent: 0, .. }`
for the compact form. `stringify` is the quote-light human form (keys sorted), for logs.

<!-- example: minor/jsonify#map -->
```rust
jsonify(&Value::map_of([("a".into(), Value::Num(1.0))]), None);
// "{\n  \"a\": 1\n}"   (pretty, indent 2)
```
<!-- => "{\n  \"a\": 1\n}" -->

<!-- example: minor/jsonify#compact -->
```rust
jsonify(
    &Value::map_of([("a".into(), Value::Num(1.0)), ("b".into(), Value::Num(2.0))]),
    Some(&JsonFlags { indent: 0, offset: 0 }),
);
// "{\"a\":1,\"b\":2}"
```
<!-- => "{\"a\":1,\"b\":2}" -->

<!-- example: minor/jsonify#brace -->
```rust
jsonify(
    &Value::map_of([
        ("a".into(), Value::Num(1.0)),
        ("b".into(), Value::list(vec![Value::Num(2.0), Value::Num(3.0)])),
    ]),
    None,
);
// "{\n  \"a\": 1,\n  \"b\": [\n    2,\n    3\n  ]\n}"   (pretty, indent 2)
```
<!-- => "{\n  \"a\": 1,\n  \"b\": [\n    2,\n    3\n  ]\n}" -->

`stringify` keeps object braces and sorts keys; the second argument caps the
length (the `...` counts):

<!-- example: minor/stringify#brace -->
```rust
stringify(
    &Value::map_of([
        ("a".into(), Value::Num(1.0)),
        ("b".into(), Value::list(vec![Value::Num(2.0), Value::Num(3.0)])),
    ]),
    None,
    false,
);
// "{a:1,b:[2,3]}"
```
<!-- => "{a:1,b:[2,3]}" -->

<!-- example: minor/stringify#max -->
```rust
stringify(&Value::str("verylongstring"), Some(5), false);
// "ve..."
```
<!-- => "ve..." -->

For more task recipes (merge configs, rename fields, `$EACH`, `$MERGE`,
`$FORMAT`, `$ONE`, `$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical;
only the host literals differ.

---

## 3. Reference

The full Rust signatures, with the TS→Rust name table, the `Value` enum,
the function-value call conventions, and the optional-parameter mapping,
are in [`README.md`](./README.md). The canonical public surface is the
`pub use` block in [`src/lib.rs`](./src/lib.rs) — that re-export list is
what [`../tools/check_parity.py`](../tools/check_parity.py) checks against
the canonical export (parity is compared case/underscore-insensitively, so
`get_path` matches `getpath`).

Rust-specific points the signatures don't show:

- **`snake_case` names.** `get_path`, `set_path`, `re_compile`, `type_name`,
  `keys_of`, … — the full map is the [name table](./README.md#name-mapping-ts-canonical--rust).
  Type constants are `SCREAMING_SNAKE` (`T_STRING`, `M_VAL`); sentinels are
  `SKIP` / `DELETE`.
- **No optional/overloaded parameters.** Trailing optionals become
  `Option<_>` (`maxdepth: Option<i64>`, `injdef: Option<&InjectDef>`) or an
  explicit `Value::Noval` argument (`get_prop(node, key, Value::Noval)`).
  `get_elem_or_else` takes a lazy `alt` closure; the callable-`alt` form of
  `get_elem` is handled there.
- **`get_prop` vs `get_elem`.** `get_prop` works on maps and lists;
  `get_elem` is list-specific and supports `-1`-from-the-end indexing.
  `get_elem_or_else` *invokes* its closure `alt` when the element is absent.
- **`items` / `keys_of` / `filter` return a `Value::List`**; the `_vec`
  variants (`items_vec`, `keysof_vec`, `filter_vals`) return native
  `Vec<(String, Value)>` / `Vec<Value>` when you want to iterate in Rust.
- **`walk` extra parameters** (`key`, `parent`, `path`) are recursion state
  delivered to the callback `FnMut(&Value, &Value, &Value, &[String]) -> Value`;
  callers pass `(val, before?, after?, maxdepth?)`.
- **`typify` returns `i64`** — a bitwise-OR of type flags. `typify(&Value::Str)`
  is `T_SCALAR | T_STRING`; test with `0 < (T_STRING & t)`. `typify(&Value::Noval)`
  is `T_NOVAL` (not a scalar); `typify(&Value::Null)` is `T_SCALAR | T_NULL`.
- **No type guards.** Rust has no narrowing predicates; `is_node` / `is_map`
  / `is_list` take `&Value` and return `bool`. Match on the `Value` enum to
  destructure.

---

## 4. Explanation & port specifics

### The port's role

This is a faithful port, not a re-design. The canonical TypeScript is the
source of truth; the shared corpus in [`../build/test/`](../build/test/) is
generated from it and this port is held to that corpus. Practically:

- A behaviour question is answered by reading the canonical TS (and the
  corpus), not by reading this port.
- A change to canonical behaviour starts in TypeScript, then flows to the
  corpus and out to every port — see
  [`../AGENTS.md`](../AGENTS.md#standard-workflows). Do **not** "fix"
  behaviour here alone.

### The `Value` enum

The data model is an in-tree enum (in [`src/value.rs`](./src/value.rs)),
not `serde_json::Value`:

```rust
pub enum Value {
    Noval, Null, Bool(bool), Num(f64), Str(String),
    List(Rc<RefCell<Vec<Value>>>),               // reference-stable
    Map(Rc<RefCell<OrderedMap<Value>>>),         // insertion-ordered, reference-stable
    Func(Rc<dyn Fn(&Inj, &Value, &str, &Value) -> Value>),  // callables in data
    Sentinel(&'static Sentinel),                 // SKIP / DELETE, by pointer identity
}
```

`Num` is a single numeric kind (`f64`); integer-ness is derived. `List` and
`Map` are `Rc<RefCell<…>>`, so a mutation through one `Value` is visible to
every holder — this reproduces the canonical "lists are mutable and
reference-stable" invariant that `walk`, `merge`, `inject`, and `set_path`
rely on. The model is **single-threaded** (`Rc`/`RefCell` are `!Send`).

### `Null` versus `Noval` (absent)

TypeScript has both `null` and `undefined`; Rust splits them into
`Value::Null` and `Value::Noval`, and `struct` keeps them distinct — the
[Group A/B rule](../DOCS.md#null-versus-absent-group-ab) in language-neutral
form. This port is **already Group A**:

- `Value::Noval` = **absent**. `get_prop` on a missing key returns `Noval`;
  Group A readers (`get_prop`, `get_elem`, `has_key`, `is_empty`, `is_node`)
  treat a stored `Null` as absent too.
- `Value::Null` = the JSON null scalar; `typify(&Value::Null)` is
  `T_SCALAR | T_NULL`, and Group B processors (`clone`, `merge`, `walk`, …)
  preserve it literally.

### The in-tree ordered map

JSON object key order is observable through `keys_of`, `items`, and
`jsonify`, and the inject machinery's `$`-suffix key partition depends on
it. Rust's `std::collections::HashMap` does not preserve insertion order, so
this port hand-rolls [`OrderedMap`](./src/ordered_map.rs) (parallel
keys/values vectors plus a `HashMap` index for O(1) lookup) — keeping the
port dependency-free. Never swap in an unordered map.

### Regex

The canonical regex is a uniform six-function API (`re_compile` / `re_test`
/ `re_find` / `re_find_all` / `re_replace` / `re_escape`). This port
**ships its own RE2-subset engine** in [`src/re.rs`](./src/re.rs) — a
Thompson NFA ported from the C engine, with **no `regex` crate** and no
third-party crates at all. It is linear-time (no catastrophic
backtracking), and its epsilon-closure is iterative so unrolled bounded
quantifiers like `a{0,10000}` don't overflow the stack. Stay inside the
**RE2 subset** — backreferences and lookaround don't port (a `\1` backref
*compiles* but never matches). Zero-width `re_replace` follows the
ECMA/PCRE convention: `re_replace("a*", "abc", "X")` returns `"XXbXcX"`
(Go's RE2 returns `"XbXcX"`). See [`README.md` → Regex](./README.md#regex)
and [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md).

---

## Build, test, and extend

```bash
cd rust
cargo build
cargo test          # runs the shared corpus suite (../build/test/test.json)
make lint           # cargo clippy --all-targets --all-features -- -D warnings
                    #   + cargo fmt --all -- --check
make audit          # cargo audit (RustSec advisory DB)
```

`make build` / `make test` / `make lint` wrap the same commands;
`make inspect` prints the toolchain and crate version.

Tests load the shared corpus from [`../build/test/`](../build/test/) via the
`serde_json` dev-dependency and assert the same way every port's runner
does (the TypeScript runner is the reference).

**To change canonical behaviour:** this does not start here. Edit the
canonical TypeScript and the corpus first, then port the change into
[`src/major.rs`](./src/major.rs) / [`src/mini.rs`](./src/mini.rs), run
`cargo test` until green, re-run `make lint`, and re-run
`python3 ../tools/check_parity.py` plus every other port's tests. The full
checklist is in [`../AGENTS.md`](../AGENTS.md).
