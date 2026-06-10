# Struct for C++

> C++ port of the canonical TypeScript implementation.
>
> **Status: complete.**  Full TS-canonical parity: all 48 functions,
> 15 type bit-flags, 3 mode constants (`M_KEYPRE`/`M_KEYPOST`/`M_VAL`),
> `SKIP`/`DELETE` sentinels (pointer-identity), and the `Injection`
> state machine.  `inject`/`transform`/`validate`/`select` all
> dispatch through the canonical injector machinery: 10 transform
> commands, 6 validate checkers, 4 select operators.
>
> Passes the full shared corpus. Run locally with `make test` from
> `cpp/`. Per-file pass counts are written to `corpus-scoreboard.json`
> after each run; the committed baseline lives at `test-baseline.json`.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../design/REPORT.md).  For the in-depth guide (tutorial, recipes,
explanation), see [`DOCS.md`](./DOCS.md).


## Install

In the monorepo:

```bash
cd cpp
make test        # smoke + corpus driver (the default build target)
make smoke       # just the smoke test
make corpus      # just the corpus driver
make sanitize    # build + run with ASan + UBSan
make check_leak  # build + run under valgrind
```

The library is header-only across three files in `src/`:
- [`value.hpp`](./src/value.hpp) — `Value` (a `std::variant`-based tagged
  type), the in-tree `OrderedMap`, `Sentinel`, type bit-flags, predicates.
- [`value_io.hpp`](./src/value_io.hpp) — JSON parse/serialise via an
  in-tree, hand-written recursive-descent parser/printer (no third-party
  dependency).
- [`voxgig_struct.hpp`](./src/voxgig_struct.hpp) — main API: utilities,
  `getpath`/`setpath`/`walk`/`merge`/`inject`/`transform`/`validate`/
  `select` plus all `transform_*`/`validate_*`/`select_*` injectors.

Namespace `voxgig::structlib`.  Requires C++17 (for `std::variant` /
structured bindings).  The library proper has **no third-party
dependency** — runtime values use the custom `Value` type and JSON text is
handled in-tree.  [nlohmann/json](https://github.com/nlohmann/json) is used
only by the test harness (corpus loading), so `make test` expects its
header on the include path (e.g. `/usr/include/nlohmann/json.hpp`).


## Quick start

```cpp
#include "value_io.hpp"   // pulls in value.hpp + voxgig_struct.hpp, plus parse_json
using namespace voxgig::structlib;

int main() {
    // Build a value and read a deep path.
    Value store = parse_json(R"({"db":{"host":"localhost","port":5432}})");
    Value host = getpath_v(store, Value("db.host"));   // "localhost"

    // Reshape by example.
    Value out = transform(
        parse_json(R"({"user":{"first":"Ada"},"age":36})"),
        parse_json(R"({"name":"`user.first`","years":"`age`"})"));
    // {"name":"Ada","years":36}

    return 0;
}
```

(Construct `Value`s with `parse_json(json_text)` (declared in
[`value_io.hpp`](./src/value_io.hpp)) or the typed constructors; see
[`DOCS.md`](./DOCS.md) and `src/value.hpp` for the full set.)


## Function reference

Functions take `const Value&` arguments and return `Value` (or
`std::vector<Value>` for `select`). The full, example-by-example reference
is in [`DOCS.md`](./DOCS.md); the canonical semantics for every function
are in the [top-level reference](../DOCS.md#3-reference).

Two C++-specific naming points (the names are otherwise the canonical
ones):

- **`_v` ("value-style") suffix** on `walk_v`, `merge_v`, `getpath_v`,
  `setpath_v` — disambiguates the public value API from header-internal
  helpers of the same root name.
- **`typename_str`** instead of `typename` — `typename` is a reserved C++
  keyword.

The parity check (`../tools/check_parity.py`) maps these back to the
canonical names, so the port reports full parity.

Build `Value`s with the typed constructors, `jm({...})` (map) and
`jt({...})` (list), or `parse_json(text)`. The examples below use whichever
is clearest.

### Predicates

```cpp
bool ismap(const Value& v);
bool islist(const Value& v);
bool iskey(const Value& v);
bool isempty(const Value& v);
```

<!-- example: minor/ismap#map -->
```cpp
ismap(jm({"a", 1}));        // true
```

<!-- => true -->

<!-- example: minor/islist#list -->
```cpp
islist(jt({1, 2}));         // true
```

<!-- => true -->

<!-- example: minor/iskey#str -->
```cpp
iskey(Value("name"));       // true
```

<!-- => true -->

<!-- example: minor/isempty#empty -->
```cpp
isempty(jt({}));            // true
```

<!-- => true -->

### Type inspection

```cpp
int typify(const Value& value);
std::string typename_str(int t);          // also: typename_str(const Value&)
```

<!-- example: minor/typify#int -->
```cpp
typify(Value(int64_t(1)));  // T_scalar | T_number | T_integer  (201326720)
```

<!-- => 201326720 -->

<!-- example: minor/typename#map -->
```cpp
typename_str(8192);         // "map"  (8192 == T_map)
```

<!-- => "map" -->

### Property access

```cpp
std::string strkey(const Value& key);
Value getelem(const Value& val, const Value& key, const Value& alt = Value::undef());
Value setprop(Value parent, const Value& key, const Value& val);
Value delprop(Value parent, const Value& key);
bool haskey(const Value& v, const Value& key);
std::vector<Value> items(const Value& v);   // [key, val] pairs
```

<!-- example: minor/strkey#num -->
```cpp
strkey(Value(2.2));                  // "2"
```

<!-- => "2" -->

<!-- example: minor/getelem#neg -->
```cpp
getelem(jt({10, 20, 30}), Value(-1));   // 30
```

<!-- => 30 -->

<!-- example: minor/setprop#set -->
```cpp
setprop(jm({"a", 1}), Value("b"), Value(2));    // {a:1, b:2}
```

<!-- => {"a": 1, "b": 2} -->

<!-- example: minor/delprop#del -->
```cpp
delprop(jm({"a", 1, "b", 2}), Value("a"));      // {b:2}
```

<!-- => {"b": 2} -->

<!-- example: minor/haskey#hit -->
```cpp
haskey(jm({"a", 1}), Value("a"));    // true
```

<!-- => true -->

<!-- example: minor/items#map -->
```cpp
items(jm({"a", 1, "b", 2}));         // {{"a", 1}, {"b", 2}}
```

<!-- => [["a", 1], ["b", 2]] -->

### Path operations

```cpp
Value setpath_v(const Value& store, const Value& path, const Value& val);
std::string pathify(const Value& v, int startin = 0, int endin = 0);
```

<!-- example: minor/setpath#nested -->
```cpp
setpath_v(jm({"a", 1, "b", 2}), Value("b"), Value(22));   // {a:1, b:22}
```

<!-- => {"a": 1, "b": 22} -->

<!-- example: minor/pathify#parts -->
```cpp
pathify(jt({"a", "b", "c"}));        // "a.b.c"
```

<!-- => "a.b.c" -->

### Tree operations

```cpp
Value merge_v(const Value& list, int maxdepth = MAXDEPTH);
Value clone(const Value& v);
Value flatten(const Value& list, int depth = 1);
```

Last input wins; maps deep-merge; lists merge by index:

<!-- example: merge#basic -->
```cpp
merge_v(jt({
  jm({"a", 1, "b", 2, "k", jt({10, 20}), "x", jm({"y", 5, "z", 6})}),
  jm({"b", 3, "d", 4, "e", 8, "k", jt({11}), "x", jm({"y", 7})}),
}));
// {a:1, b:3, d:4, e:8, k:[11, 20], x:{y:7, z:6}}
```

<!-- => {"a": 1, "b": 3, "d": 4, "e": 8, "k": [11, 20], "x": {"y": 7, "z": 6}} -->

<!-- example: minor/clone#deep -->
```cpp
clone(jm({"a", jm({"b", jt({1, 2})})}));   // {a:{b:[1,2]}}  (a deep copy)
```

<!-- => {"a": {"b": [1, 2]}} -->

<!-- example: minor/flatten#nested -->
```cpp
flatten(jt({1, jt({2, jt({3})})}));        // [1, 2, [3]]  (one level by default)
```

<!-- => [1, 2, [3]] -->

### String / URL / JSON

```cpp
std::string escre(const Value& v);
std::string escurl(const Value& v);
std::string join(const Value& arr, const std::string& sep = ",", bool url = false);
```

<!-- example: minor/escre#dots -->
```cpp
escre(Value("a.b+c"));               // "a\\.b\\+c"
```

<!-- => "a\\.b\\+c" -->

<!-- example: minor/escurl#space -->
```cpp
escurl(Value("hello world?"));       // "hello%20world%3F"
```

<!-- => "hello%20world%3F" -->

<!-- example: minor/join#sep -->
```cpp
join(jt({"a", "b", "c"}), "/");      // "a/b/c"
```

<!-- => "a/b/c" -->

### Injection / merge / validate / select

```cpp
Value inject(const Value& val, const Value& store, Injection* injdef = nullptr);
Value validate(const Value& data, const Value& spec, const Value& options = Value::undef());
std::vector<Value> select(const Value& children, const Value& query);
```

<!-- example: inject#basic -->
```cpp
// Backtick refs in strings are replaced by store values.
inject(jm({"x", "`a`", "y", 2}), jm({"a", 1}));   // {x:1, y:2}
```

<!-- => {"x": 1, "y": 2} -->

<!-- example: validate#shape -->
```cpp
// Validate against a shape (throws on mismatch).
validate(jm({"name", "Ada", "age", 36}),
         jm({"name", "`$STRING`", "age", "`$INTEGER`"}));
// {name:"Ada", age:36}
```

<!-- => {"name": "Ada", "age": 36} -->

<!-- example: select#query -->
```cpp
// Find children matching a query.
select(jm({"a", jm({"name", "Alice", "age", 30}),
           "b", jm({"name", "Bob", "age", 25})}),
       jm({"age", 30}));
// [{name:"Alice", age:30, $KEY:"a"}]
```

<!-- => [{"name": "Alice", "age": 30, "$KEY": "a"}] -->


## Notes

### Object model

Runtime values are the in-tree `Value` type (a `std::variant` tagged
union) with an in-tree insertion-ordered `OrderedMap`. Nested maps and
lists are reference-stable — the property the canonical algorithm relies on
for `walk`/`merge`/`inject`/`setpath`.

### JSON I/O

`value.hpp`/`value_io.hpp` parse and serialise JSON in-tree; the library
links no JSON dependency. `nlohmann/json` appears only in the test driver.

### `null` versus absent

The port follows the shared Group A/B rule (see
[`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)): readers treat a stored null as
"no value"; value-processors preserve it. `Value::undef()` is the absent
sentinel used as the default `alt`.


## Regex

Uniform six-function regex API (see `/design/REGEX_API.md`). The C++ port
wraps `<regex>` (C++11), which defaults to the ECMAScript dialect.

### API

| Function | Maps to |
|---|---|
| `re_compile(pattern)`             | `std::regex(pattern)` (throws `std::regex_error` on bad pattern) |
| `re_test(pattern, input)`         | `std::regex_search` → bool |
| `re_find(pattern, input)`         | first match groups as `std::vector<std::string>` (empty if no match) |
| `re_find_all(pattern, input)`     | `std::vector<std::vector<std::string>>` |
| `re_replace(pattern, input, rep)` | `std::regex_replace(input, re, rep)` |
| `re_escape(s)`                    | escape regex metacharacters |

### Dialect

Patterns must stay inside the **RE2 subset** documented in `/design/REGEX.md`.
`std::regex` defaults to ECMAScript syntax and supports backreferences
and lookaround; using them will not be portable.

### Sharp edges (C++-specific)

- **libstdc++ `<regex>` has the worst-in-class catastrophic
  backtracking.** The discovery panel measures **~1.2 s** for
  `^(a+)+$` over 22 a's plus `!`. This is well-known and is the
  reason many production C++ projects avoid `<regex>` in favour of
  RE2 or PCRE2. Stay inside the RE2 subset and avoid nested
  quantifiers; even then, performance won't match the dedicated
  engines.
- **Zero-width `replace`.** `re_replace("a*", "abc", "X")` returns
  `"XXbXcX"` — the ECMA convention shared by all PCRE/ECMA/.NET/Java/Onigmo engines plus the in-tree Thompson ports. Go (RE2) returns `"XbXcX"` instead; see `/design/REGEX_PATHOLOGICAL.md`.

See `/design/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


## Build and test

```bash
cd cpp
make test        # compile + run the corpus driver
make lint        # clang-tidy + clang-format check
```

Tests live in [`tests/`](./tests/); the corpus driver reads the shared
fixtures from [`../build/test/`](../build/test/).
</content>
