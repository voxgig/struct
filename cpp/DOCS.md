# Struct for C++

> C++ port of the canonical TypeScript implementation.
> **Status: partial.**  Basic type/property utilities only; major
> subsystems (`inject`, `transform`, `validate`, `select`,
> `getpath`, `setpath`) are not yet implemented.  Use the canonical
> TS or one of the complete ports for production work.

For the language-neutral overview, motivation, and concepts, see the
[top-level README](../README.md).  For the parity matrix see
[`../REPORT.md`](../REPORT.md).

These docs follow the [Diataxis](https://diataxis.fr/) framework.


## Tutorial: your first call

### Build

Inside the monorepo:

```bash
cd cpp
make build         # builds with Catch2
make test          # runs Catch2 tests
```

The library is header-only at
[`src/voxgig_struct.hpp`](./src/voxgig_struct.hpp), namespace
`VoxgigStruct`.  It depends on
[nlohmann/json](https://github.com/nlohmann/json) for the JSON
container.

### A first call

```cpp
#include "voxgig_struct.hpp"
#include <nlohmann/json.hpp>

using nlohmann::json;
using namespace VoxgigStruct;

int main() {
    json store = { {"db", {{"host", "localhost"}}} };

    args_container args = { store, json("db") };
    json db = getprop(std::move(args));
    // db == { "host": "localhost" }

    return 0;
}
```


## How-to recipes (current scope)

The currently-implemented functions are:

```
typename_of, typify, isnode, ismap, islist, iskey, isempty, isfunc,
getprop, setprop, keysof, haskey, items, escre, escurl, joinurl,
stringify, clone, walk, merge (partial)
```

### Test a value's shape

```cpp
isnode(value);
ismap(value);
islist(value);
```

### Read a single property

```cpp
args_container args = { node, json("key") };
json v = getprop(std::move(args));
```

### Walk

```cpp
walk(tree, [](const json& key, const json& val,
              const json& parent, const json& path) {
    return val.is_null() ? json("DEFAULT") : val;
});
```


## Reference

Source: [`src/voxgig_struct.hpp`](./src/voxgig_struct.hpp).
Namespace `VoxgigStruct`.

### Constants

All 15 type bit-flags as `constexpr int`:

```cpp
VoxgigStruct::T_any
VoxgigStruct::T_noval
VoxgigStruct::T_boolean
// ... etc
```

Sentinels (`SKIP`, `DELETE`) and mode constants are not yet defined.

### Calling convention

Most functions accept `args_container&&` (a `std::vector<json>`)
rather than typed parameters.  This is a porting shortcut that
mirrors the variadic shape of the canonical functions; it will be
replaced with type-safe signatures.

### Tests

```bash
cd cpp
make test
```

Tests use Catch2 and live in [`tests/`](./tests/).


## Explanation

### Why partial?

The C++ port covers value-shape utilities and basic `walk` / `merge`.
Major subsystems are not implemented yet.  Tracked in
[`../REPORT.md`](../REPORT.md).

### Known issues

- `walk()` casts function pointers through `intptr_t` via the JSON
  value -- this is undefined behaviour and needs replacing with a
  proper callback type.
- `clone()` is a shallow copy; the canonical is deep.
- `merge()` is partially implemented; significant blocks are
  commented out.
- All functions use `args_container&&`; types are not yet enforced.
- Debug `std::cout` calls remain in the source.

These are tracked as P0/P1/P2 in [`../REPORT.md`](../REPORT.md).

### Object model

The port uses `nlohmann::json` for the container type.  This is
reference-stable for nested values, which is the property the
canonical algorithm requires.

### Path syntax not yet supported

`getpath` / `setpath` are missing, so the canonical
"path-as-dot-string" calls do not work yet.  Use repeated
`getprop` calls to walk into nested data, or wait for the path API
to land.


## Build and test

```bash
cd cpp
make build
make test
```

The overview / scratch examples in [`overview/`](./overview/) show
the current API in use.
