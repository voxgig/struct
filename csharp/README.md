# Struct for C#

> C# / .NET port of the canonical TypeScript implementation.
>
> **Status: complete.**  Full TS-canonical parity: all 40 functions,
> 15 type bit-flags, 3 mode constants (`M_KEYPRE`/`M_KEYPOST`/`M_VAL`),
> `SKIP`/`DELETE` sentinels, and the `InjectState` machinery.
> `Inject`/`Transform`/`Validate`/`Select` all dispatch through the
> canonical injector machinery: 11 transform commands, 6 validate
> checkers, 4 select operators.
>
> Passes the full shared corpus (1178/1178). The xUnit suite
> (`StructTest.cs`, 78 tests) is the green-bar regression baseline;
> the `CorpusScoreboard` test mirrors the Java/C++ runners and writes
> `corpus-scoreboard.json` after each run with per-`.jsonic`-file pass
> counts. The committed baseline lives at `test-baseline.json`.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md).


## Install

Inside the monorepo:

```bash
cd csharp
dotnet restore
dotnet build
```

- Project: `VoxgigStruct` targeting `net8.0`.
- Namespace: `Voxgig.Struct`.
- Static class: `StructUtils` (all functions are static methods).


## Quick start

```csharp
using Voxgig.Struct;

var store = new Dictionary<string, object?> {
    ["db"]   = new Dictionary<string, object?> { ["host"] = "localhost" },
    ["user"] = new Dictionary<string, object?> {
        ["first"] = "Ada", ["last"] = "Lovelace",
    },
    ["age"]  = 36,
};

var host = StructUtils.GetPath(store, "db.host");
// host == "localhost"

var named = StructUtils.Transform(store, new Dictionary<string, object?> {
    ["name"]    = "`user.first`",
    ["surname"] = "`user.last`",
    ["years"]   = "`age`",
});

StructUtils.Validate(named, new Dictionary<string, object?> {
    ["name"]    = "`$STRING`",
    ["surname"] = "`$STRING`",
    ["years"]   = "`$INTEGER`",
});
```


## Naming convention

C# uses PascalCase for all public members:

| Canonical    | C#           |
|--------------|--------------|
| `getpath`    | `GetPath`    |
| `setpath`    | `SetPath`    |
| `getprop`    | `GetProp`    |
| `setprop`    | `SetProp`    |
| `isnode`     | `IsNode`     |
| `keysof`     | `KeysOf`     |
| `escre`      | `EscRe`      |
| `escurl`     | `EscUrl`     |


## Function reference

Source: [`Struct.cs`](./Struct.cs).

### Predicates

```csharp
StructUtils.IsNode(object? val)    // bool
StructUtils.IsMap(object? val)     // bool
StructUtils.IsList(object? val)    // bool
StructUtils.IsKey(object? val)     // bool
StructUtils.IsEmpty(object? val)   // bool
StructUtils.IsFunc(object? val)    // bool
```

### Type inspection

```csharp
StructUtils.Typify(object? value)   // int — bit-field
StructUtils.TypeName(int t)          // string
```

```csharp
StructUtils.Typify(42);                       // T.Scalar | T.Number | T.Integer
StructUtils.TypeName(StructUtils.Typify("hi"));   // "string"
```

### Size, slice, pad

```csharp
StructUtils.Size(object? val)
StructUtils.Slice(object? val, int? start = null, int? end = null,
             bool mutate = false)
StructUtils.Pad(object? str, int? padding = null, string? padchar = null)
```

### Property access

```csharp
StructUtils.GetProp(object? val, object? key, object? alt = null)
StructUtils.SetProp(object? parent, object? key, object? val)
StructUtils.DelProp(object? parent, object? key)
StructUtils.GetElem(object? val, object? key, object? alt = null)
StructUtils.GetDef(object? val, object? alt)
StructUtils.HasKey(object? val, object? key)
StructUtils.KeysOf(object? val)
StructUtils.Items(object? val)
StructUtils.StrKey(object? key)
```

### Path operations

```csharp
StructUtils.GetPath(object? store, object? path,
               object? current = null, InjectState? state = null)
StructUtils.SetPath(object? store, object? path, object? val)
StructUtils.Pathify(object? val, int? startin = null, int? endin = null)
```

```csharp
var store = new Dictionary<string, object?> {
    ["a"] = new Dictionary<string, object?> {
        ["b"] = new Dictionary<string, object?> { ["c"] = 42 }
    }
};
StructUtils.GetPath(store, "a.b.c");        // 42

var fresh = new Dictionary<string, object?>();
StructUtils.SetPath(fresh, "db.host", "localhost");
```

### Tree operations

```csharp
StructUtils.Walk(object? val, WalkApply? before = null,
            WalkApply? after = null, int? maxdepth = null)
StructUtils.Merge(object? val, int? maxdepth = null)
StructUtils.Clone(object? val)
StructUtils.Flatten(object? list, int? depth = null)
StructUtils.Filter(object? val, Func<object?, bool> check)

public delegate object? WalkApply(
    object? key, object? val, object? parent, IList<string> path);
```

### String / URL / JSON

```csharp
StructUtils.EscRe(string s)
StructUtils.EscUrl(string s)
StructUtils.Join(IList<object?> arr, string? sep = null, bool? url = null)
StructUtils.Jsonify(object? val, int indent = 2, int offset = 0)
StructUtils.Stringify(object? val, int? maxlen = null, object? pretty = null)
```

### Inject / transform / validate / select

```csharp
StructUtils.Inject(object? val, object? store, InjectState? state = null)
StructUtils.Transform(object? data, object? spec, InjectState? state = null)
StructUtils.Validate(object? data, object? spec, InjectState? state = null)
StructUtils.Select(object? children, object? query)
```

### Builders

```csharp
StructUtils.Jm(params object?[] kv)        // dictionary
StructUtils.Jt(params object?[] v)         // list
```


## Constants

### Sentinels

```csharp
StructUtils.SKIP        // emit nothing
StructUtils.DELETE      // remove from parent
```

### Type bit-flags (`Voxgig.StructUtils.T`)

```csharp
T.Any         T.NoVal       T.Boolean    T.Decimal
T.Integer     T.Number      T.Str        T.Func
T.Symbol      T.Null        T.List       T.Map
T.Instance    T.Scalar      T.Node
```

`T.Str` and `T.Func` use shortened names because `String` and
`Function` collide with BCL types.

### Walk / inject phase flags

```csharp
M_KEYPRE   M_KEYPOST   M_VAL
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

### `null` and `object?`

Nullable reference types are enabled
(`<Nullable>enable</Nullable>`).  The API exposes nullable
references throughout.  As in Go and Java, `null` covers both JSON
null and "absent".

### Identifier collisions

Some canonical names collide with C# reserved or stdlib identifiers:

- `T.Str` instead of `T.String` (collides with `System.String`).
- `T.Func` instead of `T.Function` (collides with `Func<>`).

Behaviour is unchanged.

### Status

Complete: the full canonical API is present and the parity check
([`../tools/check_parity.py`](../tools/check_parity.py)) reports C# `ok`.
See [`../REPORT.md`](../design/REPORT.md) for the cross-port matrix.


## Regex

Uniform six-function regex API (see `/design/REGEX_API.md`). The C# port
wraps `System.Text.RegularExpressions.Regex`.

### API

| Function | Maps to |
|---|---|
| `ReCompile(pattern)`             | `new Regex(pattern)` (throws `RegexParseException` on bad pattern) |
| `ReTest(pattern, input)`         | `Regex.IsMatch(input, pattern)` |
| `ReFind(pattern, input)`         | first match as `string[]` of `[whole, group1, …]` or `null` |
| `ReFindAll(pattern, input)`      | `List<string[]>` |
| `ReReplace(pattern, input, rep)` | `Regex.Replace(input, pattern, rep)` |
| `ReEscape(s)`                    | `Regex.Escape(s)` |

### Dialect

Patterns must stay inside the **RE2 subset** documented in `/design/REGEX.md`.
.NET regex supports backreferences and lookaround; using them will not
be portable.

### Sharp edges

- **Catastrophic backtracking.** .NET's regex is backtracking; the
  discovery panel sees P1 (`^(a+)+$` over 22 a's plus `!`) in
  ~390 ms here. .NET 7+ ships a non-backtracking engine you can opt
  into via `RegexOptions.NonBacktracking` — consider it for
  untrusted patterns. Stay inside the RE2 subset and prefer flat
  patterns.
- **Zero-width `replace`.** `ReReplace("a*", "abc", "X")` returns
  `"XXbXcX"` — the ECMA convention shared by all PCRE/ECMA/.NET/Java/Onigmo engines plus the in-tree Thompson ports. Go (RE2) returns `"XbXcX"` instead; see `/design/REGEX_PATHOLOGICAL.md`.

See `/design/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


## Build and test

```bash
cd csharp
dotnet restore
dotnet test
```

Tests in [`tests/`](./tests/) consume fixtures from
[`../build/test/`](../build/test/).
