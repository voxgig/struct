# Struct for C++

> C++ port of the canonical TypeScript implementation.
>
> **Status: complete.**  Full TS-canonical parity: all 40 functions,
> 15 type bit-flags, 3 mode constants (`M_KEYPRE`/`M_KEYPOST`/`M_VAL`),
> `SKIP`/`DELETE` sentinels (pointer-identity), and the `Injection`
> state machine.  `inject`/`transform`/`validate`/`select` all
> dispatch through the canonical injector machinery: 11 transform
> commands, 6 validate checkers, 4 select operators.
>
> Passes the full shared corpus. Run locally with `make test` from
> `cpp/`. Per-file pass counts are written to `corpus-scoreboard.json`
> after each run; the committed baseline lives at `test-baseline.json`.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../REPORT.md).  For the in-depth guide (tutorial, recipes,
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
#include "voxgig_struct.hpp"
using namespace voxgig::structlib;

int main() {
    // Build a value and read a deep path.
    Value store = Value::parse(R"({"db":{"host":"localhost","port":5432}})");
    Value host = getpath_v(store, Value("db.host"));   // "localhost"

    // Reshape by example.
    Value out = transform(
        Value::parse(R"({"user":{"first":"Ada"},"age":36})"),
        Value::parse(R"({"name":"`user.first`","years":"`age`"})"));
    // {"name":"Ada","years":36}

    return 0;
}
```

(Construct `Value`s with `Value::parse(json_text)` or the typed
constructors; see [`DOCS.md`](./DOCS.md) and `src/value.hpp` for the full
set.)


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
[`../UNDEF_SPEC.md`](../UNDEF_SPEC.md)): readers treat a stored null as
"no value"; value-processors preserve it. `Value::undef()` is the absent
sentinel used as the default `alt`.


## Regex

Uniform six-function regex API (see `/REGEX_API.md`). The C++ port
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

Patterns must stay inside the **RE2 subset** documented in `/REGEX.md`.
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
  `"XXbXcX"` — the ECMA convention shared by all PCRE/ECMA/.NET/Java/Onigmo engines plus the in-tree Thompson ports. Go (RE2) returns `"XbXcX"` instead; see `/REGEX_PATHOLOGICAL.md`.

See `/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


## Build and test

```bash
cd cpp
make test        # compile + run the corpus driver
make lint        # clang-tidy + clang-format check
```

Tests live in [`tests/`](./tests/); the corpus driver reads the shared
fixtures from [`../build/test/`](../build/test/).
</content>
