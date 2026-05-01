# Struct for C#

> C# / .NET port of the canonical TypeScript implementation.

For the language-neutral overview, motivation, and concepts, see the
[top-level README](../README.md).

These docs follow the [Diataxis](https://diataxis.fr/) framework.


## Tutorial: your first transform

### Install

Inside the monorepo:

```bash
cd cs
dotnet restore
```

The project is `VoxgigStruct` targeting `net8.0`.  Namespace is
`Voxgig.Struct`.

### A first transform

```csharp
using Voxgig.Struct;

var data = new Dictionary<string, object?> {
    ["user"] = new Dictionary<string, object?> {
        ["first"] = "Ada", ["last"] = "Lovelace",
    },
    ["age"] = 36,
};

var spec = new Dictionary<string, object?> {
    ["name"]    = "`user.first`",
    ["surname"] = "`user.last`",
    ["years"]   = "`age`",
};

var out_ = Struct.Transform(data, spec);
// out_ == { name: "Ada", surname: "Lovelace", years: 36 }
```

### Validate

```csharp
Struct.Validate(out_, new Dictionary<string, object?> {
    ["name"]    = "`$STRING`",
    ["surname"] = "`$STRING`",
    ["years"]   = "`$INTEGER`",
});
```


## How-to recipes

### Read a deep value safely

```csharp
Struct.GetPath(config, "db.host");
Struct.GetProp(node, "count", 0);
Struct.GetDef(maybe, "fallback");
```

### Set a deep value

```csharp
var store = new Dictionary<string, object?>();
Struct.SetPath(store, "db.host", "localhost");
```

### Merge

```csharp
var cfg = Struct.Merge(new List<object?> { defaults, file, env });
```

### Walk

```csharp
Struct.Walk(tree, (key, val, parent, path) =>
    val is null ? "DEFAULT" : val);
```


## Reference

Source: [`Struct.cs`](./Struct.cs).  Namespace `Voxgig.Struct`.  All
API is on the `Struct` static class.

### Naming convention

C# uses PascalCase for public members:

| Canonical   | C#            |
|-------------|---------------|
| `getpath`   | `GetPath`     |
| `setpath`   | `SetPath`     |
| `getprop`   | `GetProp`     |
| `isnode`    | `IsNode`      |
| `keysof`    | `KeysOf`      |

### Type bit-flags

```csharp
Voxgig.Struct.T.Any
Voxgig.Struct.T.NoVal
Voxgig.Struct.T.Boolean
Voxgig.Struct.T.Decimal
Voxgig.Struct.T.Integer
Voxgig.Struct.T.Number
Voxgig.Struct.T.Str           // String reserved -> "Str"
Voxgig.Struct.T.Func
Voxgig.Struct.T.Symbol
Voxgig.Struct.T.Null
// ... List, Map, Instance, Scalar, Node
```

### Tests

```bash
cd cs
dotnet test
```

Tests live in [`tests/`](./tests/) and consume fixtures from
[`../build/test/`](../build/test/).


## Explanation

### `null` and `object?`

C# 8+ nullable reference types are enabled (`<Nullable>enable</Nullable>`)
and the API exposes nullable references throughout.  `null` represents
JSON null and "absent" alike, the same convention used in Go and
Java.

### Identifier name collisions

Some canonical names collide with C# reserved or stdlib identifiers:

- `T.Str` instead of `T.String` (avoids the BCL `System.String`).
- `T.Func` instead of `T.Function`.

The functional behaviour is unchanged.

### Status

In progress.  Coverage is being expanded; check the parity matrix in
[`../REPORT.md`](../REPORT.md) for the latest function and command
status.


## Build and test

```bash
cd cs
dotnet restore
dotnet test
```
