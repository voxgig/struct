# Struct for Go

> Full-parity Go port of the canonical TypeScript implementation.

For the language-neutral overview, motivation, and concepts, see the
[top-level README](../README.md).

These docs follow the [Diataxis](https://diataxis.fr/) framework.


## Tutorial: your first transform

### Install

Module path: `github.com/voxgig/struct/go`.

```bash
go get github.com/voxgig/struct/go
```

### A first transform

```go
package main

import (
    "fmt"
    voxgigstruct "github.com/voxgig/struct/go"
)

func main() {
    data := map[string]any{
        "user": map[string]any{"first": "Ada", "last": "Lovelace"},
        "age":  36,
    }

    spec := map[string]any{
        "name":    "`user.first`",
        "surname": "`user.last`",
        "years":   "`age`",
    }

    out, _ := voxgigstruct.Transform(data, spec)
    fmt.Println(out)
    // map[name:Ada surname:Lovelace years:36]
}
```

### Validate

```go
out, err := voxgigstruct.Validate(data, map[string]any{
    "name":    "`$STRING`",
    "surname": "`$STRING`",
    "years":   "`$INTEGER`",
})
if err != nil {
    // shape did not match
}
```


## How-to recipes

### Read a deep value safely

```go
v := voxgigstruct.GetPath("db.host", config)        // any (nil if absent)
v := voxgigstruct.GetProp(node, "count", 0)         // 0 if absent
v := voxgigstruct.GetDef(maybe, "fallback")         // maybe unless nil
```

### Set a deep value

```go
store := map[string]any{}
voxgigstruct.SetPath(store, "db.host", "localhost")
// store == map[db:map[host:localhost]]
```

### Merge a chain of maps

```go
cfg := voxgigstruct.Merge([]any{defaults, file, env})
```

### Walk a tree

```go
voxgigstruct.Walk(tree, func(key any, val any, parent any, path []string) any {
    if val == nil {
        return "DEFAULT"
    }
    return val
})
```

### Inject and select

```go
voxgigstruct.Inject(spec, store)
voxgigstruct.Select(map[string]any{"age": 30}, db)
```


## Reference

Source: [`voxgigstruct.go`](./voxgigstruct.go).  Package
`voxgigstruct`.

### Naming convention

Go uses PascalCase for exported identifiers, so functions are
capitalised:

| Canonical   | Go            |
|-------------|---------------|
| `getpath`   | `GetPath`     |
| `setpath`   | `SetPath`     |
| `getprop`   | `GetProp`     |
| `setprop`   | `SetProp`     |
| `isnode`    | `IsNode`      |
| `keysof`    | `KeysOf`      |

All other names follow the same rule.

### Major functions

```go
func Walk(node any, apply WalkApply) any
func WalkDescend(node any, apply WalkApply, before WalkApply, after WalkApply, maxdepth int) any
func Merge(list []any, maxdepth ...int) any
func GetPath(path any, store any) any
func SetPath(store any, path any, val any) any
func Inject(val any, store any) any
func Transform(data any, spec any) (any, error)
func Validate(data any, spec any) (any, error)
func Select(query any, obj any) []any
```

### Go-specific extras

- `ItemsApply(val, apply)` -- separate from `Items` (Go has no
  overloading).
- `CloneFlags(val, flags)` -- clone with options (Go lacks optional
  parameters).
- `TransformModify`, `TransformModifyHandler`, `TransformCollect` --
  variants of `Transform` for callback styles.
- `JoinUrl(parts)` -- URL-mode join.
- `Jo(...)` / `Ja(...)` -- aliases for `Jm` / `Jt` (JSON Object /
  JSON Array).
- `ListRef[T]` -- generic wrapper for mutable list references; see
  Explanation.

### Constants

```go
const (
    T_any, T_noval, T_boolean, T_decimal, T_integer, T_number,
    T_string, T_function, T_symbol, T_null,
    T_list, T_map, T_instance, T_scalar, T_node int = ...
)
const (
    M_KEYPRE, M_KEYPOST, M_VAL int = ...
)
var SKIP, DELETE any           // sentinel objects
var MODENAME []string
var PLACEMENT ...
```

### Tests

```bash
cd go
make test           # 92/92 passing
```


## Explanation

### `nil` covers both undefined and null

Go has only `nil`.  JSON null and "absent" both map to `nil` in the
port.  Where the test corpus needs to distinguish them, the test
runner uses the string sentinels `__NULL__` and `__UNDEFMARK__`.

### Validate returns `(any, error)`

This matches Go's idiom for fallible operations.  Errors carry a
human-readable message describing the first mismatch (or an
aggregate, if the underlying call collected errors).

### Why `ListRef[T]`

Go slices are values: appending to a slice may allocate a new
backing array, breaking pointer-stability that the canonical
algorithm relies on.  `ListRef[T]` is a thin generic wrapper
(`*[]T`) that gives every holder a stable reference.  You only see
it when you need to share a list across `walk` callbacks or mutate
during a `merge`.

### Multiple variants instead of optional parameters

Go has no optional or named parameters, so utilities that take
options in the canonical API (e.g. `Walk` with `before`/`after`)
appear as multiple variants: `Walk`, `WalkDescend`, etc.  Pick the
shortest that gives you what you need.

### Naming

Tests and code use the Go canonical capitalisation.  When a
documentation source mentions `getpath`, the Go equivalent is
`GetPath`; when it mentions `KEYPRE`, Go has `M_KEYPRE`.


## Build and test

```bash
cd go
go build ./...
go test ./...           # or `make test`
```

Tests in `voxgigstruct_test.go` consume fixtures from
[`../build/test/`](../build/test/).
