# Struct for Go

> Full-parity Go port of the canonical TypeScript implementation.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../REPORT.md).


## Install

Module path: `github.com/voxgig/struct/go`.

```bash
go get github.com/voxgig/struct/go
```

```go
import voxgigstruct "github.com/voxgig/struct/go"
```


## Quick start

```go
package main

import (
    "fmt"
    voxgigstruct "github.com/voxgig/struct/go"
)

func main() {
    store := map[string]any{
        "db":   map[string]any{"host": "localhost"},
        "user": map[string]any{"first": "Ada", "last": "Lovelace"},
        "age":  36,
    }

    fmt.Println(voxgigstruct.GetPath(store, "db.host"))
    // localhost

    out, _ := voxgigstruct.Transform(store, map[string]any{
        "name":    "`user.first`",
        "surname": "`user.last`",
        "years":   "`age`",
    })
    fmt.Println(out)
    // map[name:Ada surname:Lovelace years:36]
}
```


## Naming convention

Go exports identifiers in PascalCase, so canonical lowercase
function names are uppercased:

| Canonical    | Go           |
|--------------|--------------|
| `getpath`    | `GetPath`    |
| `setpath`    | `SetPath`    |
| `getprop`    | `GetProp`    |
| `setprop`    | `SetProp`    |
| `isnode`     | `IsNode`     |
| `keysof`     | `KeysOf`     |
| `escre`      | `EscRe`      |
| `escurl`     | `EscUrl`     |

All other names follow the same rule.


## Function reference

Source: [`voxgigstruct.go`](./voxgigstruct.go).  Package
`voxgigstruct`.

### Predicates

```go
func IsNode(val any) bool
func IsMap(val any) bool
func IsList(val any) bool
func IsKey(val any) bool
func IsEmpty(val any) bool
func IsFunc(val any) bool
```

```go
voxgigstruct.IsNode(map[string]any{"a": 1})   // true
voxgigstruct.IsMap([]any{1})                  // false
voxgigstruct.IsList([]any{1, 2})              // true
voxgigstruct.IsKey("name")                    // true
voxgigstruct.IsKey("")                        // false
voxgigstruct.IsEmpty(nil)                     // true
voxgigstruct.IsFunc(func() {})                // true
```

### Type inspection

```go
func Typify(value any) int
func Typename(t int) string
```

```go
voxgigstruct.Typify(42)           // T_scalar | T_number | T_integer
voxgigstruct.Typify("hi")         // T_scalar | T_string
voxgigstruct.Typify(nil)          // T_scalar | T_null

voxgigstruct.Typename(voxgigstruct.Typify("hi"))  // "string"
```

### Size, slice, pad

```go
func Size(val any) int
func Slice(val any, args ...any) any
func Pad(str any, args ...any) string
```

`args` carries optional `(start, end, mutate)` for `Slice` and
`(padding, padchar)` for `Pad`.

```go
voxgigstruct.Size([]any{1, 2, 3})            // 3
voxgigstruct.Slice([]any{1, 2, 3, 4}, 1, 3)  // []any{2, 3}
voxgigstruct.Pad("hi", 5)                    // "hi   "
voxgigstruct.Pad("hi", -5, "*")              // "***hi"
```

### Property access

```go
func GetProp(val any, key any, alts ...any) any
func SetProp(parent any, key any, val any) any
func DelProp(parent any, key any) any
func GetElem(val any, key any, alts ...any) any
func GetDef(val any, alt any) any
func HasKey(val any, key any) bool
func KeysOf(val any) []string
func Items(val any) [][2]any
func ItemsApply(val any, apply func([2]any) any) []any
func StrKey(key any) string
```

```go
voxgigstruct.GetProp(map[string]any{"a": 1}, "a")           // 1
voxgigstruct.GetProp(map[string]any{}, "b", "fallback")     // "fallback"
voxgigstruct.GetElem([]any{1, 2, 3}, -1)                    // 3
voxgigstruct.GetDef(nil, "fb")                              // "fb"
voxgigstruct.HasKey(map[string]any{"a": 1}, "a")            // true
voxgigstruct.KeysOf(map[string]any{"b": 1, "a": 2})         // [a b]
voxgigstruct.Items(map[string]any{"a": 1})                  // [[a 1]]
voxgigstruct.StrKey(1)                                       // "1"
```

### Path operations

```go
func GetPath(store any, path any, injdefs ...*Injection) any
func SetPath(store any, path any, val any, injdefs ...map[string]any) any
func Pathify(val any, args ...any) string
```

```go
voxgigstruct.GetPath(
    map[string]any{"a": map[string]any{"b": 42}},
    "a.b",
)
// 42

voxgigstruct.GetPath(map[string]any{"a": []any{10, 20}}, "a.1")
// 20

store := map[string]any{}
voxgigstruct.SetPath(store, "db.host", "localhost")
// store == map[db:map[host:localhost]]

voxgigstruct.Pathify([]any{"a", "b", "c"})    // "a.b.c"
```

### Tree operations

```go
func Walk(val any, apply WalkApply, opts ...any) any
func WalkDescend(val any, before WalkApply, after WalkApply,
                 maxdepth int) any
func Merge(val any, maxdepths ...int) any
func Clone(val any) any
func CloneFlags(val any, flags map[string]bool) any
func Flatten(list any, depths ...int) any
func Filter(val any, check func([2]any) bool) []any

type WalkApply func(key any, val any, parent any, path []string) any
```

```go
voxgigstruct.Walk(tree, func(k, v, p any, path []string) any {
    if v == nil { return "DEFAULT" }
    return v
})

voxgigstruct.Merge([]any{
    map[string]any{"a": 1, "b": 2},
    map[string]any{"b": 3, "c": 4},
})
// map[a:1 b:3 c:4]

voxgigstruct.Clone(map[string]any{"a": []any{1, 2}})
voxgigstruct.Flatten([]any{1, []any{2, []any{3}}})
voxgigstruct.Filter([][2]any{{"a", 1}, {"b", 2}},
    func(kv [2]any) bool { return kv[1].(int) > 1 })
```

### String / URL / JSON

```go
func EscRe(s string) string
func EscUrl(s string) string
func Join(arr []any, args ...any) string
func JoinUrl(parts []any) string
func Jsonify(val any, flags ...map[string]any) string
func Stringify(val any, args ...any) string
```

```go
voxgigstruct.EscRe("a.b+c")                   // "a\\.b\\+c"
voxgigstruct.EscUrl("hello world")            // "hello%20world"
voxgigstruct.Join([]any{"a", "b"}, "/")       // "a/b"
voxgigstruct.JoinUrl([]any{"http:", "/foo/", "/bar"})
                                              // "http:/foo/bar"
voxgigstruct.Jsonify(map[string]any{"a": 1})  // `{"a":1}`
voxgigstruct.Stringify(map[string]any{"a": 1})// "a:1"
```

### Inject / transform / validate / select

```go
func Inject(val any, store any, injdefs ...*Injection) any
func Transform(data any, spec any) (any, error)
func TransformModify(data any, spec any, modify Modify) (any, error)
func TransformModifyHandler(data any, spec any, handler ...) (any, error)
func TransformCollect(data any, spec any, ...) (any, error)
func Validate(data any, spec any) (any, error)
func Select(children any, query any) []any
```

```go
voxgigstruct.Inject(
    map[string]any{"greeting": "hello `name`"},
    map[string]any{"name": "Ada"},
)

out, err := voxgigstruct.Transform(
    map[string]any{"hold": map[string]any{"x": 1}, "top": 99},
    map[string]any{"a": "`hold.x`", "b": "`top`"},
)
// out == map[a:1 b:99]

ok, err := voxgigstruct.Validate(
    map[string]any{"name": "Ada", "age": 36},
    map[string]any{"name": "`$STRING`", "age": "`$INTEGER`"},
)

voxgigstruct.Select(
    map[string]any{
        "a": map[string]any{"age": 30},
        "b": map[string]any{"age": 25},
    },
    map[string]any{"age": 30},
)
// [map[$KEY:a age:30]]
```

### Builders

```go
func Jm(args ...any) map[string]any   // JSON Object
func Jt(args ...any) []any            // JSON Tuple/Array
func Jo(args ...any) map[string]any   // alias for Jm
func Ja(args ...any) []any            // alias for Jt
```

```go
voxgigstruct.Jm("a", 1, "b", 2)       // map[a:1 b:2]
voxgigstruct.Jt(1, 2, 3)              // [1 2 3]
```

### Injection helpers

```go
func CheckPlacement(modes int, ijname string, parentTypes int,
                    inj *Injection) bool
func InjectorArgs(argTypes []int, args []any) []any
func InjectChild(child any, store any, inj *Injection) *Injection
```

### `ListRef[T]`

Generic wrapper providing pointer-stable list semantics.  Used
internally by `merge` and `inject`; you only need it when writing
custom modify callbacks that mutate lists.

```go
ref := &voxgigstruct.ListRef[int]{Data: []int{1, 2, 3}}
```


## Constants

### Sentinels

```go
voxgigstruct.SKIP        // emit nothing for this key
voxgigstruct.DELETE      // remove this key from the parent
```

### Type bit-flags

```go
const (
    voxgigstruct.T_any
    voxgigstruct.T_noval
    voxgigstruct.T_boolean
    voxgigstruct.T_decimal
    voxgigstruct.T_integer
    voxgigstruct.T_number
    voxgigstruct.T_string
    voxgigstruct.T_function
    voxgigstruct.T_symbol
    voxgigstruct.T_null
    voxgigstruct.T_list
    voxgigstruct.T_map
    voxgigstruct.T_instance
    voxgigstruct.T_scalar
    voxgigstruct.T_node
)
```

### Walk / inject phase flags

```go
voxgigstruct.M_KEYPRE
voxgigstruct.M_KEYPOST
voxgigstruct.M_VAL
voxgigstruct.MODENAME    // []string mapping flags to names
voxgigstruct.PLACEMENT   // placement helpers
```


## Transform commands

```
$DELETE  $COPY    $KEY     $META    $ANNO
$MERGE   $EACH    $PACK    $REF     $FORMAT  $APPLY
```


## Validate checkers

```
$MAP   $LIST   $STRING   $NUMBER   $INTEGER   $DECIMAL  $BOOLEAN
$NULL  $NIL    $FUNCTION $INSTANCE $ANY       $CHILD    $ONE     $EXACT
```


## Notes

### `nil` covers absent and JSON null

Go has only `nil`.  JSON null and "absent" both map to `nil` at the
user-facing API.  Where the test corpus needs to distinguish them,
the test runner uses string sentinels `__NULL__` and `__UNDEFMARK__`.

### Multiple variants instead of optional parameters

Go has no optional or named parameters.  Where canonical TypeScript
takes options, the Go port either:

- collects them in a variadic (e.g. `Pad(str, args ...any)`); or
- exposes a separate function (e.g. `WalkDescend` for the full
  shape; `CloneFlags` for clone-with-options).

`Walk` is the short form; `WalkDescend` exposes both `before` and
`after` callbacks plus an explicit `maxdepth`.

### `Validate` and `Transform` return `(any, error)`

This matches Go's idiom for fallible operations.  The error carries a
human-readable message describing the first mismatch (or an
aggregate, if the underlying call collected errors).

### `ListRef[T]`

Go slices are values: appending may allocate a new backing array,
breaking pointer-stability.  `ListRef[T]` is a thin generic wrapper
that gives every holder a stable reference -- preserving the
canonical "lists are reference-stable" assumption.

### Test status

92/92 tests pass against the shared corpus.


## Build and test

```bash
cd go
go build ./...
go test ./...
# or:
make test
```

Tests in [`voxgigstruct_test.go`](./voxgigstruct_test.go) consume
fixtures from [`../build/test/`](../build/test/).
