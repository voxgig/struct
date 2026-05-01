# Struct for C#

> C# / .NET port of the canonical TypeScript implementation.
> Status: in progress.  See [`../REPORT.md`](../REPORT.md) for parity.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md).


## Install

Inside the monorepo:

```bash
cd cs
dotnet restore
dotnet build
```

- Project: `VoxgigStruct` targeting `net8.0`.
- Namespace: `Voxgig.Struct`.
- Static class: `StructUtils` (alias for `Struct`, used in tests).


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

var host = Struct.GetPath(store, "db.host");
// host == "localhost"

var named = Struct.Transform(store, new Dictionary<string, object?> {
    ["name"]    = "`user.first`",
    ["surname"] = "`user.last`",
    ["years"]   = "`age`",
});

Struct.Validate(named, new Dictionary<string, object?> {
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
Struct.IsNode(object? val)    // bool
Struct.IsMap(object? val)     // bool
Struct.IsList(object? val)    // bool
Struct.IsKey(object? val)     // bool
Struct.IsEmpty(object? val)   // bool
Struct.IsFunc(object? val)    // bool
```

### Type inspection

```csharp
Struct.Typify(object? value)   // int — bit-field
Struct.Typename(int t)          // string
```

```csharp
Struct.Typify(42);                       // T.Scalar | T.Number | T.Integer
Struct.Typename(Struct.Typify("hi"));   // "string"
```

### Size, slice, pad

```csharp
Struct.Size(object? val)
Struct.Slice(object? val, int? start = null, int? end = null,
             bool mutate = false)
Struct.Pad(object? str, int? padding = null, string? padchar = null)
```

### Property access

```csharp
Struct.GetProp(object? val, object? key, object? alt = null)
Struct.SetProp(object? parent, object? key, object? val)
Struct.DelProp(object? parent, object? key)
Struct.GetElem(object? val, object? key, object? alt = null)
Struct.GetDef(object? val, object? alt)
Struct.HasKey(object? val, object? key)
Struct.KeysOf(object? val)
Struct.Items(object? val)
Struct.StrKey(object? key)
```

### Path operations

```csharp
Struct.GetPath(object? store, object? path,
               object? current = null, InjectState? state = null)
Struct.SetPath(object? store, object? path, object? val)
Struct.Pathify(object? val, int? startin = null, int? endin = null)
```

```csharp
var store = new Dictionary<string, object?> {
    ["a"] = new Dictionary<string, object?> {
        ["b"] = new Dictionary<string, object?> { ["c"] = 42 }
    }
};
Struct.GetPath(store, "a.b.c");        // 42

var fresh = new Dictionary<string, object?>();
Struct.SetPath(fresh, "db.host", "localhost");
```

### Tree operations

```csharp
Struct.Walk(object? val, WalkApply? before = null,
            WalkApply? after = null, int? maxdepth = null)
Struct.Merge(object? val, int? maxdepth = null)
Struct.Clone(object? val)
Struct.Flatten(object? list, int? depth = null)
Struct.Filter(object? val, Func<object?, bool> check)

public delegate object? WalkApply(
    object? key, object? val, object? parent, IList<string> path);
```

### String / URL / JSON

```csharp
Struct.EscRe(string s)
Struct.EscUrl(string s)
Struct.Join(IList<object?> arr, string? sep = null, bool? url = null)
Struct.Jsonify(object? val, IDictionary<string, object?>? flags = null)
Struct.Stringify(object? val, int? maxlen = null, object? pretty = null)
```

### Inject / transform / validate / select

```csharp
Struct.Inject(object? val, object? store, InjectState? state = null)
Struct.Transform(object? data, object? spec, InjectState? state = null)
Struct.Validate(object? data, object? spec, InjectState? state = null)
Struct.Select(object? children, object? query)
```

### Builders

```csharp
Struct.Jm(params object?[] kv)        // dictionary
Struct.Jt(params object?[] v)         // list
```


## Constants

### Sentinels

```csharp
Struct.SKIP        // emit nothing
Struct.DELETE      // remove from parent
```

### Type bit-flags (`Voxgig.Struct.T`)

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
M.KeyPre   M.KeyPost   M.Val
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

In progress.  Coverage of canonical functions is broad; check
[`../REPORT.md`](../REPORT.md) for the latest status.


## Build and test

```bash
cd cs
dotnet restore
dotnet test
```

Tests in [`tests/`](./tests/) consume fixtures from
[`../build/test/`](../build/test/).
