# Struct for Rust

> Rust port of the canonical TypeScript implementation.
> Status: **complete** — the full shared corpus passes (`cargo test` → 1309
> checks; `cargo clippy` clean): minor utilities, `walk`, `merge`, `getpath`,
> `setpath`, `inject`, `transform` (all 10 commands), `validate` (all 15
> checkers), `select` (all operators), and the `primary.check` SDK test.

For motivation, the language-neutral concepts, and the cross-language parity
matrix, see the [top-level README](../README.md) and [`REPORT.md`](../design/REPORT.md).

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
    Map(Rc<RefCell<OrderedMap<Value>>>),   // insertion-ordered, reference-stable
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

See [`REPORT.md`](../design/REPORT.md#rust-rust) for the rust-port adaptations
write-up, and [`../NOTES.md`](../design/NOTES.md) for cross-port quirks.


## Minor utility examples

Concrete examples for the most-used minor utilities. Each call is the Rust
expression of the canonical input; the comment shows the Rust-native result.

`is_node` reports whether a value is a node (map or list):

<!-- example: minor/isnode#map -->
```rust
is_node(&Value::map_of([("a".into(), Value::Num(1.0))])); // true
```
<!-- => true -->

`is_map` / `is_list` distinguish the two node kinds; `is_key` accepts a
non-empty string or a number; `is_empty` reports the empty/absent values:

<!-- example: minor/ismap#map -->
```rust
is_map(&Value::map_of([("a".into(), Value::Num(1.0))])); // true
```

<!-- => true -->

<!-- example: minor/islist#list -->
```rust
is_list(&Value::list(vec![Value::Num(1.0), Value::Num(2.0)])); // true
```

<!-- => true -->

<!-- example: minor/iskey#str -->
```rust
is_key(&Value::str("name")); // true
```

<!-- => true -->

<!-- example: minor/isempty#empty -->
```rust
is_empty(&Value::empty_list()); // true
```

<!-- => true -->

`size` counts entries of a list/map (or the length of a string):

<!-- example: minor/size#three -->
```rust
size(&Value::list(vec![Value::Num(1.0), Value::Num(2.0), Value::Num(3.0)])); // 3
```
<!-- => 3 -->

`slice` keeps the first *N*; a negative `start` drops the last *|start|* items,
and `end` is exclusive:

<!-- example: minor/slice#mid -->
```rust
slice(
    Value::list(vec![
        Value::Num(1.0), Value::Num(2.0), Value::Num(3.0), Value::Num(4.0), Value::Num(5.0),
    ]),
    Some(1),
    Some(4),
    false,
); // Value::List([2, 3, 4])
```
<!-- => [2, 3, 4] -->

<!-- example: minor/slice#strhead -->
```rust
slice(Value::str("abcdef"), Some(-3), None, false); // Value::Str("abc")  (drops the last 3)
```
<!-- => "abc" -->

`pad` pads on the right (negative padding pads on the left):

<!-- example: minor/pad#right -->
```rust
pad(Value::str("a"), Some(3), None); // "a  "
```
<!-- => "a  " -->

`typify` returns an `i64` bit-field (a "kind" flag OR'd with a specific type
flag); `type_name` maps a flag back to a human name:

<!-- example: minor/typify#int -->
```rust
typify(&Value::Num(1.0)); // 201326720  (T_SCALAR | T_NUMBER | T_INTEGER)
```

<!-- => 201326720 -->

<!-- example: minor/typename#map -->
```rust
type_name(8192); // "map"  (8192 == T_MAP)
```

<!-- => "map" -->

`get_prop` reads a key from a map or list:

<!-- example: minor/getprop#hit -->
```rust
get_prop(&Value::map_of([("x".into(), Value::Num(1.0))]), &Value::str("x"), Value::Noval); // Value::Num(1.0)
```
<!-- => 1 -->

`set_prop` / `del_prop` return the parent with the key set/removed:

<!-- example: minor/setprop#set -->
```rust
set_prop(Value::map_of([("a".into(), Value::Num(1.0))]), &Value::str("b"), Value::Num(2.0));
// Value::Map({ a: 1, b: 2 })
```

<!-- => {"a": 1, "b": 2} -->

<!-- example: minor/delprop#del -->
```rust
del_prop(
    Value::map_of([("a".into(), Value::Num(1.0)), ("b".into(), Value::Num(2.0))]),
    &Value::str("a"),
);
// Value::Map({ b: 2 })
```

<!-- => {"b": 2} -->

`get_elem` is list-specific and supports negative indexing from the end:

<!-- example: minor/getelem#neg -->
```rust
get_elem(
    &Value::list(vec![Value::Num(10.0), Value::Num(20.0), Value::Num(30.0)]),
    &Value::Num(-1.0),
    Value::Noval,
); // Value::Num(30.0)
```

<!-- => 30 -->

`has_key` tests presence of a key (a stored `Null` counts as absent):

<!-- example: minor/haskey#hit -->
```rust
has_key(&Value::map_of([("a".into(), Value::Num(1.0))]), &Value::str("a")); // true
```

<!-- => true -->

`items` returns the `[key, value]` pairs of a map (or list) as a `Value::List`:

<!-- example: minor/items#map -->
```rust
items(&Value::map_of([("a".into(), Value::Num(1.0)), ("b".into(), Value::Num(2.0))]));
// Value::List([["a", 1], ["b", 2]])
```

<!-- => [["a", 1], ["b", 2]] -->

`str_key` coerces a key to its canonical string form (numbers truncate):

<!-- example: minor/strkey#num -->
```rust
str_key(Value::Num(2.2)); // "2"
```

<!-- => "2" -->

`keys_of` returns sorted string keys of a map:

<!-- example: minor/keysof#sorted -->
```rust
keys_of(&Value::map_of([("b".into(), Value::Num(4.0)), ("a".into(), Value::Num(5.0))]));
// Value::List(["a", "b"])  (sorted)
```
<!-- => ["a", "b"] -->

`filter` passes each `(key, value)` pair to the check and returns the matching
**values** (not the pairs), as a `Value::List`:

<!-- example: minor/filter#gt3 -->
```rust
filter(
    &Value::list(vec![
        Value::Num(1.0), Value::Num(2.0), Value::Num(3.0), Value::Num(4.0), Value::Num(5.0),
    ]),
    |(_k, v)| matches!(v, Value::Num(n) if *n > 3.0),
);
// Value::List([4, 5])
```
<!-- => [4, 5] -->

`set_path` writes a value at a dot path, returning the (mutated) store;
`pathify` renders a path list back to a dot string:

<!-- example: minor/setpath#nested -->
```rust
set_path(
    &Value::map_of([("a".into(), Value::Num(1.0)), ("b".into(), Value::Num(2.0))]),
    &Value::str("b"),
    Value::Num(22.0),
    None,
);
// Value::Map({ a: 1, b: 22 })
```

<!-- => {"a": 1, "b": 22} -->

<!-- example: minor/pathify#parts -->
```rust
pathify(&Value::list(vec![Value::str("a"), Value::str("b"), Value::str("c")]), None, None);
// "a.b.c"
```

<!-- => "a.b.c" -->

`merge` folds a list of nodes — last input wins, maps deep-merge, lists merge
by index; `clone` makes a deep copy; `flatten` removes one level of nesting:

<!-- example: merge#basic -->
```rust
merge(
    &Value::list(vec![
        Value::map_of([
            ("a".into(), Value::Num(1.0)),
            ("b".into(), Value::Num(2.0)),
            ("k".into(), Value::list(vec![Value::Num(10.0), Value::Num(20.0)])),
            ("x".into(), Value::map_of([
                ("y".into(), Value::Num(5.0)), ("z".into(), Value::Num(6.0)),
            ])),
        ]),
        Value::map_of([
            ("b".into(), Value::Num(3.0)),
            ("d".into(), Value::Num(4.0)),
            ("e".into(), Value::Num(8.0)),
            ("k".into(), Value::list(vec![Value::Num(11.0)])),
            ("x".into(), Value::map_of([("y".into(), Value::Num(7.0))])),
        ]),
    ]),
    None,
);
// Value::Map({ a: 1, b: 3, d: 4, e: 8, k: [11, 20], x: { y: 7, z: 6 } })
```

<!-- => {"a": 1, "b": 3, "d": 4, "e": 8, "k": [11, 20], "x": {"y": 7, "z": 6}} -->

<!-- example: minor/clone#deep -->
```rust
clone(&Value::map_of([(
    "a".into(),
    Value::map_of([("b".into(), Value::list(vec![Value::Num(1.0), Value::Num(2.0)]))]),
)]));
// Value::Map({ a: { b: [1, 2] } })  (a deep copy)
```

<!-- => {"a": {"b": [1, 2]}} -->

<!-- example: minor/flatten#nested -->
```rust
flatten(
    &Value::list(vec![
        Value::Num(1.0),
        Value::list(vec![
            Value::Num(2.0),
            Value::list(vec![Value::Num(3.0)]),
        ]),
    ]),
    None,
);
// Value::List([1, 2, [3]])  (one level by default)
```

<!-- => [1, 2, [3]] -->

`esc_re` / `esc_url` escape for regex / URL contexts; `join` concatenates with
a separator:

<!-- example: minor/escre#dots -->
```rust
esc_re(&Value::str("a.b+c")); // "a\\.b\\+c"
```

<!-- => "a\\.b\\+c" -->

<!-- example: minor/escurl#space -->
```rust
esc_url(&Value::str("hello world?")); // "hello%20world%3F"
```

<!-- => "hello%20world%3F" -->

<!-- example: minor/join#sep -->
```rust
join(
    &Value::list(vec![Value::str("a"), Value::str("b"), Value::str("c")]),
    Some("/"),
    false,
); // "a/b/c"
```

<!-- => "a/b/c" -->

`inject` replaces backtick refs in strings with store values; `validate`
checks data against a by-example shape (`Err` on mismatch); `select` finds
children matching a query, each tagged with its `$KEY`:

<!-- example: inject#basic -->
```rust
inject(
    Value::map_of([("x".into(), Value::str("`a`")), ("y".into(), Value::Num(2.0))]),
    &Value::map_of([("a".into(), Value::Num(1.0))]),
    None,
);
// Value::Map({ x: 1, y: 2 })
```

<!-- => {"x": 1, "y": 2} -->

<!-- example: validate#shape -->
```rust
validate(
    &Value::map_of([
        ("name".into(), Value::str("Ada")),
        ("age".into(), Value::Num(36.0)),
    ]),
    &Value::map_of([
        ("name".into(), Value::str("`$STRING`")),
        ("age".into(), Value::str("`$INTEGER`")),
    ]),
    None,
).unwrap();
// Value::Map({ name: "Ada", age: 36 })  (Err on mismatch)
```

<!-- => {"name": "Ada", "age": 36} -->

<!-- example: select#query -->
```rust
select(
    &Value::map_of([
        ("a".into(), Value::map_of([
            ("name".into(), Value::str("Alice")), ("age".into(), Value::Num(30.0)),
        ])),
        ("b".into(), Value::map_of([
            ("name".into(), Value::str("Bob")), ("age".into(), Value::Num(25.0)),
        ])),
    ]),
    &Value::map_of([("age".into(), Value::Num(30.0))]),
);
// Value::List([{ name: "Alice", age: 30, $KEY: "a" }])
```

<!-- => [{"name": "Alice", "age": 30, "$KEY": "a"}] -->


## Regex

Uniform six-function regex API (see `/design/REGEX_API.md`). The Rust port
**ships its own RE2-subset engine** in `src/re.rs` — no `regex` crate
dependency, no third-party crates at all (`Cargo.toml` lists none for
runtime).

### API

| Function | Returns |
|---|---|
| `re_compile(pattern)`           | `Result<Regex, RegexError>` |
| `re_test(pattern, input)`       | `bool` |
| `re_find(pattern, input)`       | `Option<Vec<String>>` — `[whole, group1, …]` |
| `re_find_all(pattern, input)`   | `Vec<Vec<String>>` |
| `re_replace(pattern, input, r)` | `String` |
| `re_escape(s)`                  | `String` |

### Dialect

The in-tree engine implements the RE2 subset documented in
`/design/REGEX.md`: literals + escapes, `.`, `^`/`$`, `* + ? {n} {n,} {n,m}`
(greedy + lazy), classes incl. `\d \w \s` and friends, `\b`/`\B`,
`(...)` / `(?:...)`, alternation.

**Not supported** (by design — RE2 doesn't either):
backreferences, lookaround, possessive quantifiers, atomic groups.
Backref patterns like `^(a+)\1$` *compile* (the parser doesn't reject
`\1`) but never match the back-reference semantically, so `re_test`
returns `false` rather than erroring. Don't rely on this — write
portable patterns.

### Sharp edges (Rust-specific)

- **Bounded quantifiers are unrolled.** `a{0,10000}` compiles into
  10 000 Split+atom-clone pairs. The matcher was previously recursive
  during epsilon-closure and stack-overflowed on such patterns; it is
  now iterative (`Threads::add` uses an explicit work stack).
  `re_test("^a{0,10000}b$", …)` now runs in ~10 ms here.
- **No catastrophic backtracking.** Thompson-NFA construction means
  P1/P2 from the discovery panel run in microseconds.
- **Zero-width `re_replace`.** `re_replace("a*", "abc", "X")` returns
  `"XXbXcX"` — the convention shared with all PCRE/ECMA/Java/.NET
  engines and the other in-tree Thompson ports (C / Lua / Zig). Go
  (RE2) returns `"XbXcX"` instead; see `/design/REGEX_PATHOLOGICAL.md`.
- **Single-threaded.** `Value` uses `Rc<RefCell<…>>` so it is
  `!Send + !Sync`. The regex statics use `std::sync::LazyLock` and
  are thread-safe in isolation, but the public API isn't.

See `/design/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.
