# Struct for Go

> Full-parity Go port of the canonical TypeScript implementation.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../design/REPORT.md).


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

    out := voxgigstruct.Transform(store, map[string]any{
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

<!-- example: minor/isnode#map -->
```go
voxgigstruct.IsNode(map[string]any{"a": 1})   // true
```
<!-- => true -->

<!-- example: minor/ismap#map -->
```go
voxgigstruct.IsMap(map[string]any{"a": 1})    // true
```

<!-- => true -->

<!-- example: minor/islist#list -->
```go
voxgigstruct.IsList([]any{1, 2})              // true
```

<!-- => true -->

<!-- example: minor/iskey#str -->
```go
voxgigstruct.IsKey("name")                    // true
```

<!-- => true -->

<!-- example: minor/isempty#empty -->
```go
voxgigstruct.IsEmpty([]any{})                 // true
```

<!-- => true -->

```go
voxgigstruct.IsMap([]any{1})                  // false
voxgigstruct.IsKey("")                        // false
voxgigstruct.IsEmpty(nil)                     // true
voxgigstruct.IsFunc(func() {})                // true
```

### Type inspection

```go
func Typify(value any) int
func Typename(t int) string
```

<!-- example: minor/typify#int -->
```go
voxgigstruct.Typify(1)            // T_scalar | T_number | T_integer  (201326720)
```

<!-- => 201326720 -->

```go
voxgigstruct.Typify(42)           // T_scalar | T_number | T_integer
voxgigstruct.Typify("hi")         // T_scalar | T_string
voxgigstruct.Typify(nil)          // T_scalar | T_null
```

<!-- example: minor/typename#map -->
```go
voxgigstruct.Typename(8192)       // "map"  (8192 == T_map)
```

<!-- => "map" -->

```go
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

<!-- example: minor/size#three -->
```go
voxgigstruct.Size([]any{1, 2, 3})            // 3
```
<!-- => 3 -->

`Slice(val, start, end)` takes a `start` offset (a positive `start` drops the
first *start* items, so `("abcdef", 2)` returns `"cdef"`); a negative `start`
counts from the end and drops the last *|start|* items (so `("abcdef", -3)`
keeps the first three), and `end` is exclusive:

<!-- example: minor/slice#mid -->
```go
voxgigstruct.Slice([]any{1, 2, 3, 4, 5}, 1, 4)  // []any{2, 3, 4}
```
<!-- => [2, 3, 4] -->

<!-- example: minor/slice#strhead -->
```go
voxgigstruct.Slice("abcdef", -3)             // "abc"  (drops the last 3)
```
<!-- => "abc" -->

`Pad` right-pads to the target width with spaces by default:

<!-- example: minor/pad#right -->
```go
voxgigstruct.Pad("a", 3)                     // "a  "
```
<!-- => "a  " -->

```go
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

<!-- example: minor/getprop#hit -->
```go
voxgigstruct.GetProp(map[string]any{"x": 1}, "x")           // 1
```
<!-- => 1 -->

<!-- example: minor/setprop#set -->
```go
voxgigstruct.SetProp(map[string]any{"a": 1}, "b", 2)        // map[a:1 b:2]
```

<!-- => {"a": 1, "b": 2} -->

<!-- example: minor/delprop#del -->
```go
voxgigstruct.DelProp(map[string]any{"a": 1, "b": 2}, "a")   // map[b:2]
```

<!-- => {"b": 2} -->

<!-- example: minor/getelem#neg -->
```go
voxgigstruct.GetElem([]any{10, 20, 30}, -1)                 // 30
```

<!-- => 30 -->

<!-- example: minor/haskey#hit -->
```go
voxgigstruct.HasKey(map[string]any{"a": 1}, "a")            // true
```

<!-- => true -->

<!-- example: minor/items#map -->
```go
voxgigstruct.Items(map[string]any{"a": 1, "b": 2})          // [[a 1] [b 2]]
```

<!-- => [["a", 1], ["b", 2]] -->

<!-- example: minor/strkey#num -->
```go
voxgigstruct.StrKey(2.2)                                    // "2"
```

<!-- => "2" -->

```go
voxgigstruct.GetProp(map[string]any{}, "b", "fallback")     // "fallback"
voxgigstruct.GetDef(nil, "fb")                              // "fb"
voxgigstruct.StrKey(1)                                       // "1"
```

`KeysOf` returns map keys sorted:

<!-- example: minor/keysof#sorted -->
```go
voxgigstruct.KeysOf(map[string]any{"b": 4, "a": 5})         // [a b]  (sorted)
```
<!-- => ["a", "b"] -->

### Path operations

```go
func GetPath(store any, path any, injdefs ...*Injection) any
func SetPath(store any, path any, val any, injdefs ...map[string]any) any
func Pathify(val any, args ...any) string
```

<!-- example: getpath/basic#deep -->
```go
voxgigstruct.GetPath(
    map[string]any{"a": map[string]any{"b": map[string]any{"c": 42}}},
    "a.b.c",
)
// 42
```
<!-- => 42 -->

```go
voxgigstruct.GetPath(map[string]any{"a": []any{10, 20}}, "a.1")
// 20

store := map[string]any{}
voxgigstruct.SetPath(store, "db.host", "localhost")
// store == map[db:map[host:localhost]]
```

<!-- example: minor/setpath#nested -->
```go
voxgigstruct.SetPath(map[string]any{"a": 1, "b": 2}, "b", 22)   // map[a:1 b:22]
```

<!-- => {"a": 1, "b": 22} -->

<!-- example: minor/pathify#parts -->
```go
voxgigstruct.Pathify([]any{"a", "b", "c"})    // "a.b.c"
```

<!-- => "a.b.c" -->

### Tree operations

```go
func Walk(val any, apply WalkApply, opts ...any) any
func WalkDescend(val any, apply WalkApply, key *string, parent any,
                 path []string) any
func Merge(val any, maxdepths ...int) any
func Clone(val any) any
func CloneFlags(val any, flags map[string]bool) any
func Flatten(list any, depths ...int) any
func Filter(val any, check func([2]any) bool) []any

type WalkApply func(key *string, val any, parent any, path []string) any
```

`key` is a `*string` — `nil` at the root, otherwise the map key or the
string form of a list index. `Walk`'s `opts` carry the optional `after`
callback and `maxdepth`; `WalkDescend` starts a descent from a non-root
position with an explicit `key`, `parent`, and starting `path`.

```go
voxgigstruct.Walk(tree, func(k *string, v, p any, path []string) any {
    if v == nil { return "DEFAULT" }
    return v
})
```

Last input wins; maps deep-merge; lists merge by index:

<!-- example: merge#basic -->
```go
voxgigstruct.Merge([]any{
    map[string]any{"a": 1, "b": 2, "k": []any{10, 20}, "x": map[string]any{"y": 5, "z": 6}},
    map[string]any{"b": 3, "d": 4, "e": 8, "k": []any{11}, "x": map[string]any{"y": 7}},
})
// map[a:1 b:3 d:4 e:8 k:[11 20] x:map[y:7 z:6]]
```

<!-- => {"a": 1, "b": 3, "d": 4, "e": 8, "k": [11, 20], "x": {"y": 7, "z": 6}} -->

<!-- example: minor/clone#deep -->
```go
voxgigstruct.Clone(map[string]any{"a": map[string]any{"b": []any{1, 2}}})
// map[a:map[b:[1 2]]]  (a deep copy)
```

<!-- => {"a": {"b": [1, 2]}} -->

<!-- example: minor/flatten#nested -->
```go
voxgigstruct.Flatten([]any{1, []any{2, []any{3}}})   // []any{1, 2, []any{3}}  (one level by default)
```

<!-- => [1, 2, [3]] -->

`Filter` passes each `[key, value]` pair to the check and returns the
matching **values** (not the pairs):

<!-- example: minor/filter#gt3 -->
```go
voxgigstruct.Filter([]any{1, 2, 3, 4, 5},
    func(kv [2]any) bool { return kv[1].(int) > 3 })
// []any{4, 5}
```
<!-- => [4, 5] -->

### String / URL / JSON

```go
func EscRe(s string) string
func EscUrl(s string) string
func Join(arr []any, args ...any) string
func JoinUrl(parts []any) string
func Jsonify(val any, flags ...map[string]any) string
func Stringify(val any, args ...any) string
```

<!-- example: minor/escre#dots -->
```go
voxgigstruct.EscRe("a.b+c")                   // "a\\.b\\+c"
```

<!-- => "a\\.b\\+c" -->

<!-- example: minor/escurl#space -->
```go
voxgigstruct.EscUrl("hello world?")           // "hello%20world%3F"
```

<!-- => "hello%20world%3F" -->

<!-- example: minor/join#sep -->
```go
voxgigstruct.Join([]any{"a", "b", "c"}, "/")  // "a/b/c"
```

<!-- => "a/b/c" -->

```go
voxgigstruct.JoinUrl([]any{"http:", "/foo/", "/bar"})
                                              // "http:/foo/bar"
```

`Jsonify` pretty-prints by default (indent 2); pass `{"indent": 0}` for the
compact form:

<!-- example: minor/jsonify#map -->
```go
voxgigstruct.Jsonify(map[string]any{"a": 1})
// {
//   "a": 1
// }
```
<!-- => "{\n  \"a\": 1\n}" -->

<!-- example: minor/jsonify#compact -->
```go
voxgigstruct.Jsonify(map[string]any{"a": 1, "b": 2}, map[string]any{"indent": 0})
// {"a":1,"b":2}
```
<!-- => "{\"a\":1,\"b\":2}" -->

`Stringify` is the compact, quote-light form — keys are sorted and object
braces are kept; a second argument caps the length (the `...` counts):

<!-- example: minor/stringify#brace -->
```go
voxgigstruct.Stringify(map[string]any{"a": 1, "b": []any{2, 3}})  // "{a:1,b:[2,3]}"
```
<!-- => "{a:1,b:[2,3]}" -->

<!-- example: minor/stringify#max -->
```go
voxgigstruct.Stringify("verylongstring", 5)   // "ve..."
```
<!-- => "ve..." -->

### Inject / transform / validate / select

```go
func Inject(val any, store any, injdefs ...*Injection) any
func Transform(data any, spec any, injdefs ...*Injection) any
func TransformModify(data any, spec any, extra any, modify Modify) any
func TransformModifyHandler(data any, spec any, extra any, modify Modify,
                            handler Injector, errs *ListRef[any],
                            meta map[string]any) any
func TransformCollect(data any, spec any) (any, []string)
func Validate(data any, spec any, injdefs ...*Injection) (any, error)
func Select(children any, query any) []any
```

<!-- example: inject#basic -->
```go
// Backtick refs in strings are replaced by store values.
voxgigstruct.Inject(
    map[string]any{"x": "`a`", "y": 2},
    map[string]any{"a": 1},
)
// map[x:1 y:2]
```

<!-- => {"x": 1, "y": 2} -->

```go
voxgigstruct.Inject(
    map[string]any{"greeting": "hello `name`"},
    map[string]any{"name": "Ada"},
)

out := voxgigstruct.Transform(
    map[string]any{"hold": map[string]any{"x": 1}, "top": 99},
    map[string]any{"a": "`hold.x`", "b": "`top`"},
)
// out == map[a:1 b:99]
```

<!-- example: validate#shape -->
```go
// Validate against a shape (returns the data, or an error on mismatch).
out, err := voxgigstruct.Validate(
    map[string]any{"name": "Ada", "age": 36},
    map[string]any{"name": "`$STRING`", "age": "`$INTEGER`"},
)
// out == map[age:36 name:Ada]
```

<!-- => {"name": "Ada", "age": 36} -->

<!-- example: select#query -->
```go
// Find children matching a query.
voxgigstruct.Select(
    map[string]any{
        "a": map[string]any{"name": "Alice", "age": 30},
        "b": map[string]any{"name": "Bob", "age": 25},
    },
    map[string]any{"age": 30},
)
// [map[$KEY:a age:30 name:Alice]]
```

<!-- => [{"name": "Alice", "age": 30, "$KEY": "a"}] -->

Transform commands drive structural ops. A command like `$EACH` appears in
**value** position — as the first element of a list
`[]any{"`$EACH`", path, subspec}` — mapping the sub-spec over every entry at
`path`:

<!-- example: transform/each#basic -->
```go
out, _ := voxgigstruct.Transform(
    map[string]any{"v": 1, "a": []any{map[string]any{"q": 13}, map[string]any{"q": 23}}},
    map[string]any{"x": map[string]any{"y": []any{"`$EACH`", "a",
        map[string]any{"q": "`$COPY`", "r": "`.q`", "p": "`...v`"}}}},
)
// out == map[x:map[y:[map[p:1 q:13 r:13] map[p:1 q:23 r:23]]]]
```
<!-- => {"x": {"y": [{"q": 13, "r": 13, "p": 1}, {"q": 23, "r": 23, "p": 1}]}} -->

Putting a command in **key** position (or, for `$APPLY`, directly under a
map) is an error — commands must be list values:

<!-- example: transform/apply#badkey -->
```go
_, err := voxgigstruct.Transform(map[string]any{}, map[string]any{"x": "`$APPLY`"})
// err: $APPLY: invalid placement in parent map, expected: list.
```
<!-- throws: invalid placement in parent map -->

### Builders

```go
func Jm(args ...any) map[string]any   // JSON Object
func Jt(args ...any) []any            // JSON Tuple/Array
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
ref := &voxgigstruct.ListRef[int]{List: []int{1, 2, 3}}
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
the test runner uses string sentinels `__NULL__` and `__UNDEF__`.

### Multiple variants instead of optional parameters

Go has no optional or named parameters.  Where canonical TypeScript
takes options, the Go port either:

- collects them in a variadic (e.g. `Pad(str, args ...any)`,
  `Walk(val, apply, opts ...any)` where `opts` carry the optional `after`
  callback and `maxdepth`); or
- exposes a separate function (e.g. `WalkDescend` for an ad-hoc descent
  from a non-root position; `CloneFlags` for clone-with-options).

`Walk` is the short form. `WalkDescend(val, apply, key, parent, path)`
starts a recursive descent from a non-root position, taking an explicit
`key`, `parent`, and starting `path`.

### `Validate` returns `(any, error)`

Only `Validate` returns `(any, error)`, matching Go's idiom for fallible
operations.  The error carries a human-readable message describing the
first mismatch (or an aggregate, if the underlying call collected
errors).  `Transform`, `TransformModify`, and `TransformModifyHandler`
return a plain `any`; `TransformCollect` returns `(any, []string)` —
the data plus any collected error strings.

### `ListRef[T]`

Go slices are values: appending may allocate a new backing array,
breaking pointer-stability.  `ListRef[T]` is a thin generic wrapper
that gives every holder a stable reference -- preserving the
canonical "lists are reference-stable" assumption.

### Test status

92/92 tests pass against the shared corpus.


## Regex

Uniform six-function regex API (see `/design/REGEX_API.md`). The Go port
wraps the stdlib `regexp` package — Go's `regexp` *is* the RE2
reference implementation.

### API

| Function | Maps to |
|---|---|
| `ReCompile(pattern)`              | `regexp.MustCompile(pattern)` (panics on bad pattern) |
| `ReTest(pattern, input)`          | `re.MatchString(input)` |
| `ReFind(pattern, input)`          | `re.FindStringSubmatch(input)` |
| `ReFindAll(pattern, input)`       | `re.FindAllStringSubmatch(input, -1)` |
| `ReReplace(pattern, input, rep)`  | `re.ReplaceAllString(input, rep)` |
| `ReReplaceFunc(pattern, input,f)` | `re.ReplaceAllStringFunc(input, f)` |
| `ReEscape(s)`                     | alias for `EscRe(s)` |

### Dialect

Patterns must stay inside the **RE2 subset** documented in `/design/REGEX.md`.
Since Go's regexp engine *is* RE2, this is the natural ceiling: there is
no PCRE escape hatch.

### Sharp edges (Go-specific)

- **`ReCompile` panics.** It's a pass-through to `regexp.MustCompile`,
  so an invalid pattern aborts via `panic`. This matches the
  throw/raise behaviour of every other port; wrap in `recover()` if
  you accept user-supplied patterns.
- **Bounded quantifier cap.** RE2 refuses `{n,m}` with `m > 1000`.
  `^a{0,10000}b$` *panics* at compile time with "invalid repeat
  count". This is a hard RE2 limit — no portable workaround. The
  canonical patterns and `$LIKE` operator stay well below it.
- **No backreferences or lookaround.** RE2 does not support them by
  design. `^(a+)\1$` panics on compile. The cross-port dialect already
  forbids them; this is the engine that enforces the rule hardest.
- **Zero-width `re_replace` uses RE2's convention.**
  `re_replace("a*", "abc", "X")` returns `"XbXcX"` — RE2 suppresses
  an empty match immediately after a non-empty match at the same
  offset. PCRE / ECMA / .NET / Java / the in-tree Thompson ports all
  return `"XXbXcX"` instead. This is inherent to Go's host regex
  package and is **not** wrapped: portable callers should not depend
  on cross-port identity of zero-width replacement output.

See `/design/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


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
