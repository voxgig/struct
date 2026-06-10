# Struct for C++ — Comprehensive Guide

> A **port** of the canonical TypeScript implementation. Behaviour is
> defined by TypeScript and pinned by the shared corpus; this port follows
> it. This guide is the in-depth companion to [`README.md`](./README.md)
> (quick start + signature reference) and the language-neutral
> [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — build and learn the API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the
  C++-specific semantics and types.
- **[Explanation](#4-explanation--port-specifics)** — the model, the port's
  place in it, and C++-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Install

The library is **header-only** and lives in three files under
[`src/`](./src/):

- [`value.hpp`](./src/value.hpp) — the `Value` type (a `std::variant`
  tagged union), the in-tree `OrderedMap`, `Sentinel`, type bit-flags, mode
  constants, and predicates.
- [`value_io.hpp`](./src/value_io.hpp) — JSON text I/O via a hand-written
  recursive-descent parser (`parse_json` / `dump_json`); no third-party
  deps.
- [`voxgig_struct.hpp`](./src/voxgig_struct.hpp) — the main API.

There is nothing to compile to use it — just include the header and target
C++17:

```cpp
#include "voxgig_struct.hpp"
using namespace voxgig::structlib;
```

Working from a clone (you'll do this to run the corpus or extend the port):

```bash
cd cpp
make build        # smoke + corpus driver  (==  make test)
```

`make test` compiles the test harness, which needs the header-only
[`nlohmann/json`](https://github.com/nlohmann/json) on the include path
(e.g. `/usr/include`) to load the corpus. The library proper does **not**
use it. Override the location with `make JSON_INC=/path test`; `make
inspect` prints the compiler version and the located header.

### Your first program

```cpp
#include "voxgig_struct.hpp"
using namespace voxgig::structlib;

int main() {
  Value config = merge_v(parse_json(R"([
    {"db": {"host": "localhost", "port": 5432}, "debug": false},
    {"db": {"host": "db.internal"}, "debug": true}
  ])"));

  getpath_v(config, Value("db.host"));   // "db.internal"
  getpath_v(config, Value("db.port"));   // 5432  (survived the deep merge)
}
```

Note the `_v` suffix on `merge_v` / `getpath_v` — see
[Casing](#casing-and-the-_v--_str-renames).

`getpath_v` takes the store first, then a dot-path, and reads the deep value:

<!-- example: getpath/basic#deep -->
```cpp
getpath_v(parse_json(R"({"a":{"b":{"c":42}}})"), Value("a.b.c"));   // 42
```
<!-- => 42 -->

### Build up the rest of the API

Each call has the same meaning in every port; only the spelling changes.
Read [`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the full
language-neutral walkthrough. The C++ flavour:

```cpp
// Reshape by example — the spec mirrors the output you want.
transform(parse_json(R"({"user":{"first":"Ada","last":"Lovelace"},"age":36})"),
          parse_json(R"({"name":"`user.first`","surname":"`user.last`","years":"`age`"})"));
// {"name":"Ada","surname":"Lovelace","years":36}

// Validate by example — leaves are type checkers; throws on mismatch.
validate(parse_json(R"({"name":"Ada","age":36})"),
         parse_json(R"({"name":"`$STRING`","age":"`$INTEGER`"})"));

// Select children by query — each match tagged with its $KEY.
select(parse_json(R"({"a":{"age":30},"b":{"age":25}})"), parse_json(R"({"age":30})"));
// [ {"age":30,"$KEY":"a"} ]
```

A transform command like `$EACH` appears in **value** position — the first
element of a list `["`$EACH`", path, subspec]` — mapping the sub-spec over
every entry at `path`:

<!-- example: transform/each#basic -->
```cpp
transform(parse_json(R"({"v":1,"a":[{"q":13},{"q":23}]})"),
          parse_json(R"({"x":{"y":["`$EACH`","a",{"q":"`$COPY`","r":"`.q`","p":"`...v`"}]}})"));
// {"x":{"y":[{"q":13,"r":13,"p":1},{"q":23,"r":23,"p":1}]}}
```
<!-- => {"x": {"y": [{"q": 13, "r": 13, "p": 1}, {"q": 23, "r": 23, "p": 1}]}} -->

---

## 2. How-to guides

### Walk the tree, replacing values on ascent
`walk_v` takes `WalkApply` callbacks — `std::function`s receiving
`(key, val, parent, path)` and returning the replacement value:

```cpp
walk_v(tree, nullptr, [](const Value& key, const Value& val,
                         const Value& parent, const std::vector<std::string>& path) {
  return val.is_null() ? Value("DEFAULT") : val;
});
```

Pass `nullptr` for an unused `before`/`after` slot.

### Build literals without parsing JSON text
`jm` builds a map from alternating key/value args; `jt` builds a list:

```cpp
Value m = jm({"host", Value("localhost"), "port", Value(5432)});
Value l = jt({Value(1), Value(2), Value(3)});
```

### Serialise deterministically

`jsonify` pretty-prints by default (2-space indent, insertion-ordered keys);
pass `0` for the compact form. `stringify` is the quote-light human form, for
logs.

<!-- example: minor/jsonify#map -->
```cpp
jsonify(parse_json(R"({"a":1})"));
// {
//   "a": 1
// }
```
<!-- => "{\n  \"a\": 1\n}" -->

<!-- example: minor/jsonify#brace -->
```cpp
jsonify(parse_json(R"({"a":1,"b":[2,3]})"));
// {
//   "a": 1,
//   "b": [
//     2,
//     3
//   ]
// }
```
<!-- => "{\n  \"a\": 1,\n  \"b\": [\n    2,\n    3\n  ]\n}" -->

<!-- example: minor/jsonify#compact -->
```cpp
jsonify(parse_json(R"({"a":1,"b":2})"), 0);   // {"a":1,"b":2}
```
<!-- => "{\"a\":1,\"b\":2}" -->

<!-- example: minor/stringify#brace -->
```cpp
stringify(parse_json(R"({"a":1,"b":[2,3]})"));   // {a:1,b:[2,3]}
```
<!-- => "{a:1,b:[2,3]}" -->

<!-- example: minor/stringify#max -->
```cpp
stringify(Value("verylongstring"), 5);   // ve...
```
<!-- => "ve..." -->

`parse_json` / `dump_json` in [`value_io.hpp`](./src/value_io.hpp) are the
text bridge; `jsonify` is the canonical printer they share.

### Run your own function during a transform (`$APPLY`)
Register an `Injector` (`std::function`) and reference it by name in the
spec. The function may return the `SKIP()` / `DELETE_V()` sentinels to omit
or remove the current key.

A transform command must sit in **value** position. Putting `$APPLY`
directly under a map (in **key** position) is an error:

<!-- example: transform/apply#badkey -->
```cpp
transform(parse_json("{}"), parse_json(R"({"x":"`$APPLY`"})"));
// throws: $APPLY: invalid placement in parent map, expected: list.
```
<!-- throws: invalid placement in parent map -->

For the full recipe set (merge configs, rename fields, `$EACH`, `$MERGE`,
`$FORMAT`, `$ONE`, `$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical;
only the host literals differ.

---

## 3. Reference

The canonical public surface (40 names) is the `export { … }` block in
[`typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts);
`../tools/check_parity.py` checks every port against it. The C++
implementations are declared near the top of
[`src/voxgig_struct.hpp`](./src/voxgig_struct.hpp) (forward declarations)
and defined below; everything public lives in namespace
`voxgig::structlib`.

C++-specific points the signatures don't show:

- **`Value` is the data model.** It is a `std::variant` over undefined
  (`std::monostate`), JSON null (`std::nullptr_t`), `bool`, `int64_t`,
  `double`, `std::string`, `shared_ptr<List>`, `shared_ptr<Map>`,
  `Injector`, `Modify`, and `const Sentinel*`. `undefined` and `null` are
  **distinct** storage slots — see [null vs absent](#null-versus-absent).
- **Most functions take `const Value&` and return `Value`.** Optional
  arguments default to `Value::undef()`. `keysof` returns
  `std::vector<std::string>`; `items` returns `std::vector<Value>` of
  `[key, val]` pairs; `select` returns `std::vector<Value>`.
- **Callbacks are `std::function`.** `WalkApply` is the walk callback type;
  `Injector` / `Modify` are the transform/inject hook types (defined in
  [`value.hpp`](./src/value.hpp)). Pass `nullptr` to skip an optional slot.
- **Type flags combine bitwise.** `typify(Value("hi"))` is
  `T_scalar | T_string`; test with `0 != (T_string & t)`. `typify` of
  undefined is `T_noval`; `typify(Value(nullptr))` is `T_scalar | T_null`.
  `typename_str(int)` (and `typename_str(const Value&)`) names the dominant
  flag.
- **Sentinels are pointer-identity singletons.** `SKIP()` / `DELETE_V()`
  return `Value`s wrapping `const Sentinel*`, so `==` identity survives
  `clone`. (`DELETE_V` carries the `_V` suffix because `DELETE` collides
  with a common macro/keyword expectation.)

### Casing and the `_v` / `_str` renames

Names are lowercase canonical, with a handful of unavoidable C++ renames
(`../tools/check_parity.py` strips the suffixes for this port):

| Canonical | C++ name | Why |
|---|---|---|
| `walk` | `walk_v` | the `_v` ("value-style") suffix disambiguates from a header-internal helper of the same root name |
| `merge` | `merge_v` | same |
| `getpath` | `getpath_v` | same |
| `setpath` | `setpath_v` | same |
| `typename` | `typename_str` | `typename` is a reserved C++ keyword |

Everything else keeps its canonical spelling (`getprop`, `setprop`,
`inject`, `transform`, `validate`, `select`, `isnode`, `ismap`, …).

---

## 4. Explanation & port specifics

### This is a port, not the source of truth

Behaviour is defined by the canonical TypeScript and pinned by the shared
corpus in [`../build/test/`](../build/test/). When this port disagrees with
the corpus, the port is wrong — fix it here, never edit the corpus. A
genuine behaviour change starts in TypeScript and flows out to every port
(see [`../AGENTS.md`](../AGENTS.md#standard-workflows)).

### null versus absent

C++ here has both, kept distinct — the
[Group A/B rule](../DOCS.md#null-versus-absent-group-ab) in language-neutral
form (full text in [`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)):

- **Absent** is `Value::undef()` (`std::monostate`). `getprop` on a missing
  key returns the `alt`; Group A readers (`getprop`, `getelem`, `haskey`,
  `isempty`, `isnode`) treat a stored `null` as absent too.
- **null** is the JSON null scalar (`std::nullptr_t`); `typify` is
  `T_scalar | T_null`, and Group B value-processors (`clone`, `merge_v`,
  `walk_v`, `setprop`, …) preserve it literally.

This distinction is the single most common source of port bugs; check it
first when a read/merge/clone case fails.

### Reference-stable containers

`walk_v`, `merge_v`, `inject`, and `setpath_v` rely on lists and maps being
shared by reference so a mutation through one handle is visible to all. The
port gets this from `shared_ptr<List>` / `shared_ptr<Map>` inside `Value` —
no `ListRef` wrapper is needed.

### Ordered maps

Map key order must match insertion order (the inject machinery partitions
non-`$` keys before `$` keys, and `jsonify` emits in order). C++'s stdlib
has no insertion-ordered map, so the port ships the in-tree `OrderedMap`
(vector + index) in [`value.hpp`](./src/value.hpp). Never substitute an
unordered map.

### Zero runtime dependencies

The library proper uses only the C++17 standard library plus its own
in-tree helpers: the `OrderedMap`, the hand-written JSON parser in
[`value_io.hpp`](./src/value_io.hpp), and `jsonify` as the printer.
`nlohmann/json` is a **test-harness-only** build requirement (corpus
loading); the shipped headers never include it.

### Regex

The regex layer wraps the C++ standard `<regex>` (ECMAScript dialect)
behind the uniform six-function API: `re_compile`, `re_test`, `re_find`,
`re_find_all`, `re_replace`, `re_escape`. Stay inside the **RE2 subset** —
`std::regex` *allows* backreferences and lookaround, but those don't port.
Two sharp edges: libstdc++'s `<regex>` has the worst-in-class catastrophic
backtracking, and zero-width `re_replace("a*", "abc", "X")` returns
`"XXbXcX"` (the ECMA convention; Go's RE2 returns `"XbXcX"`). Details in
[`README.md` → Regex](./README.md#regex) and
[`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md).

---

## Build, test, and extend

```bash
cd cpp
make build        # smoke + corpus driver  (default target; == make test)
make smoke        # just the smoke test
make corpus       # just the corpus driver
make sanitize     # corpus built + run under ASan + UBSan
make check_leak   # corpus under valgrind (full leak check)
make lint         # clang-tidy + clang-format --dry-run --Werror
make inspect      # print g++ version and the located nlohmann/json header
```

Tests live in [`tests/`](./tests/); the corpus driver
(`tests/struct_corpus_test.cpp`, via `tests/runner.hpp`) loads the shared
corpus from [`../build/test/`](../build/test/) and mirrors the reference
runner in [`../typescript/test/runner.ts`](../typescript/test/runner.ts).
The header path for `nlohmann/json` defaults to `/usr/include`; override
with `make JSON_INC=/path …`.

**To change behaviour:** behaviour is canonical. Edit
[`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts)
and the corpus first, then port the change into the three headers here,
`make test` until green, run `make lint`, and re-run
`python3 ../tools/check_parity.py`. The full cross-port checklist is in
[`../AGENTS.md`](../AGENTS.md).
