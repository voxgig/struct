# Struct for C++

> C++ port of the canonical TypeScript implementation.
>
> **Status: partial.**  Basic type/property utilities only.  The
> major subsystems (`inject`, `transform`, `validate`, `select`)
> and path operations (`getpath`, `setpath`) are not yet implemented.
> Use the canonical TS or one of the complete ports for production
> work.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../REPORT.md).


## Install

In the monorepo:

```bash
cd cpp
make build
make test
```

The library is header-only at
[`src/voxgig_struct.hpp`](./src/voxgig_struct.hpp), namespace
`VoxgigStruct`.  It depends on
[nlohmann/json](https://github.com/nlohmann/json) for the JSON
container.

```cpp
#include "voxgig_struct.hpp"
#include <nlohmann/json.hpp>
using nlohmann::json;
using namespace VoxgigStruct;
```


## Quick start

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


## Calling convention

Most functions accept `args_container&&` (a `std::vector<json>`)
rather than typed parameters.  This is a porting shortcut that
mirrors the variadic shape of the canonical functions; it will be
replaced with type-safe signatures.


## Function reference (currently implemented)

Source: [`src/voxgig_struct.hpp`](./src/voxgig_struct.hpp).
Namespace `VoxgigStruct`.

20 of the 40 canonical functions are present:

### Predicates

```cpp
bool isnode(args_container&& args);
bool ismap(args_container&& args);
bool islist(args_container&& args);
bool iskey(args_container&& args);
bool isempty(args_container&& args);
bool isfunc(args_container&& args);
```

### Type inspection

```cpp
std::string typename_of(args_container&& args);
int         typify(args_container&& args);
```

### Property access

```cpp
json getprop(args_container&& args);
json setprop(args_container&& args);
std::vector<std::string> keysof(args_container&& args);
bool                      haskey(args_container&& args);
std::vector<json>         items(args_container&& args);
```

### Tree operations

```cpp
json clone(args_container&& args);     // shallow currently — see notes
json walk(args_container&& args);      // see notes (UB issue)
json merge(args_container&& args);     // partial implementation
```

### Strings

```cpp
std::string escre(args_container&& args);
std::string escurl(args_container&& args);
std::string joinurl(args_container&& args);
std::string stringify(args_container&& args);
```


## Function reference (not yet implemented)

The following canonical functions are missing.  Items marked **P0**
are foundational for the other missing pieces:

### Path operations (P0)

```cpp
json getpath(...);     // missing
json setpath(...);     // missing
```

### Major subsystems (P0)

```cpp
json              inject(...);     // missing
json              transform(...);  // missing
json              validate(...);   // missing
std::vector<json> select(...);     // missing
```

### Minor utilities

```cpp
getdef, getelem, delprop, size, slice, flatten, filter,
pad, replace, join, jsonify, strkey, pathify
```

### Builders

```cpp
jm, jt
```

### Injection helpers

```cpp
checkPlacement, injectorArgs, injectChild
```

### Sentinels and mode constants

```cpp
SKIP, DELETE
M_KEYPRE, M_KEYPOST, M_VAL, MODENAME
```

(Type bit-flags `T_any`..`T_node` are present as `constexpr int`.)


## Constants

### Type bit-flags

```cpp
constexpr int VoxgigStruct::T_any
constexpr int VoxgigStruct::T_noval
// ... 15 total
```


## Notes

### Why partial?

The C++ port covers value-shape utilities and basic `walk` /
`merge`.  Major subsystems are not implemented yet.  Tracked as
P0/P1/P2 in [`../REPORT.md`](../REPORT.md).

### Known issues

- **`walk()`** casts function pointers through `intptr_t` via the
  JSON value -- this is undefined behaviour and needs replacing
  with a proper callback type.
- **`clone()`** is a shallow copy; canonical is deep.
- **`merge()`** is partially implemented; significant blocks are
  commented out.
- All functions use `args_container&&` (`std::vector<json>`); types
  are not yet enforced.
- Debug `std::cout` calls remain in the source.

### Object model

The port uses `nlohmann::json` for the container type.  This is
reference-stable for nested values, which is the property the
canonical algorithm requires.

### Path syntax not yet supported

`getpath` / `setpath` are missing.  Use repeated `getprop` calls
to walk into nested data, or wait for the path API to land.

### Test status

Catch2 framework with limited test coverage.  See the
[overview](./overview/) directory for current API examples.


## Build and test

```bash
cd cpp
make build
make test
```

The overview / scratch examples in [`overview/`](./overview/) show
the current API in use.
