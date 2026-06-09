# Struct for C# — Comprehensive Guide

> A **port**. The canonical behaviour is defined in TypeScript
> ([`../typescript/`](../typescript/)); this C# port is held to the same
> shared corpus. This guide is the in-depth companion to
> [`README.md`](./README.md) (the quick-start + signature reference) and the
> language-neutral [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — install and learn the whole API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the exact
  C# semantics and types.
- **[Explanation](#4-explanation--port-specifics)** — the model, the port's
  role, and C#-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Install

Work from a clone inside the monorepo (there is no published NuGet package):

```bash
cd csharp
dotnet restore
dotnet build          # builds VoxgigStruct.csproj -> net8.0
dotnet test           # runs the shared corpus suite
```

The library targets `net8.0`, assembly `VoxgigStruct`, namespace
`Voxgig.Struct`. The public surface is the static class `StructUtils`. It
uses only `System.Text.Json` and `System.Text.RegularExpressions` from the
framework — **zero third-party runtime dependencies**.

### Your first program

The data model is JSON-shaped `object?`: maps are
`Dictionary<string, object?>`, lists are `List<object?>` (or any `IList`),
and scalars are the boxed CLR primitives.

```csharp
using Voxgig.Struct;

var config = StructUtils.Merge(new List<object?> {
    new Dictionary<string, object?> {                          // defaults
        ["db"] = new Dictionary<string, object?> { ["host"] = "localhost", ["port"] = 5432 },
        ["debug"] = false,
    },
    new Dictionary<string, object?> {                          // overrides
        ["db"] = new Dictionary<string, object?> { ["host"] = "db.internal" },
        ["debug"] = true,
    },
});

StructUtils.GetPath(config, "db.host");   // "db.internal"
StructUtils.GetPath(config, "db.port");   // 5432  (survived the deep merge)
```

### Build up the rest of the API

Each call below has the same meaning in every port; only the syntax
changes. Read [`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the
full language-neutral walkthrough; the C#-flavoured version:

```csharp
// Reshape by example — the spec mirrors the output you want.
StructUtils.Transform(
    new Dictionary<string, object?> {
        ["user"] = new Dictionary<string, object?> { ["first"] = "Ada", ["last"] = "Lovelace" },
        ["age"] = 36,
    },
    new Dictionary<string, object?> { ["name"] = "`user.first`", ["surname"] = "`user.last`", ["years"] = "`age`" });
// { name = "Ada", surname = "Lovelace", years = 36 }

// Validate by example — leaves are type checkers; throws on mismatch.
StructUtils.Validate(
    new Dictionary<string, object?> { ["name"] = "Ada", ["age"] = 36 },
    new Dictionary<string, object?> { ["name"] = "`$STRING`", ["age"] = "`$INTEGER`" });

// Walk the tree — replace values on ascent.
StructUtils.Walk(tree, null, (key, val, parent, path) => val is null ? "DEFAULT" : val);

// Select children by query — each match tagged with its $KEY.
StructUtils.Select(
    new Dictionary<string, object?> {
        ["a"] = new Dictionary<string, object?> { ["age"] = 30 },
        ["b"] = new Dictionary<string, object?> { ["age"] = 25 },
    },
    new Dictionary<string, object?> { ["age"] = 30 });
// [ { age = 30, $KEY = "a" } ]
```

---

## 2. How-to guides

### Build maps and lists without the verbose initializers

`Jm` builds a map from alternating key/value args; `Jt` builds a list:

```csharp
StructUtils.GetPath(StructUtils.Jm("a", StructUtils.Jm("b", 1)), "a.b");   // 1
StructUtils.Jt(1, 2, 3);                                                   // List<object?> { 1, 2, 3 }
```

### Collect all validation errors instead of throwing

`Validate` throws on the first mismatch unless you hand it an `InjectState`
with an `Errs` collector; then it fills the list and returns:

```csharp
var state = new InjectState { Errs = new List<object?>() };
StructUtils.Validate(payload, spec, state);
if (state.Errs!.Count > 0) Console.Error.WriteLine(string.Join("\n", state.Errs));
```

### Write a custom transform function (`$APPLY`)

Register the function in the `InjectState.Extra` map and reference it by
name in the spec. A custom function may return the `SKIP` / `DELETE`
sentinels to omit/remove the current key.

```csharp
var state = new InjectState {
    Extra = new Dictionary<string, object?> {
        ["sum"] = (Injector)((inj, val, refStr, store) =>
            ((List<object?>)((Dictionary<string, object?>)store!)["items"]!)
                .Sum(x => Convert.ToInt32(x))),
    },
};
StructUtils.Transform(
    new Dictionary<string, object?> { ["items"] = StructUtils.Jt(1, 2, 3) },
    new Dictionary<string, object?> { ["total"] = new Dictionary<string, object?> { ["`$APPLY`"] = "sum" } },
    state);
```

### Keep a `Walk` path past the callback

The `path` argument is one mutable `List<object?>` reused for the whole
walk — clone it if you need to retain it:

```csharp
var seen = new List<List<object?>>();
StructUtils.Walk(tree, (key, val, parent, path) => {
    seen.Add(new List<object?>(path));   // the path list is reused — clone to keep it
    return val;
}, null);
```

### Serialise deterministically

```csharp
StructUtils.Jsonify(value);               // indent defaults to 2 (pretty)
StructUtils.Jsonify(value, indent: 0);    // compact, insertion-ordered keys
StructUtils.Stringify(value, 80);         // truncated human form, for logs
```

For more task recipes (merge configs, rename fields, `$EACH`, `$MERGE`,
`$FORMAT`, `$ONE`, `$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical;
only the host literals differ.

---

## 3. Reference

The full C# signatures, with examples for every function, are in
[`README.md` → Function reference](./README.md#function-reference). The
canonical public surface (the 40 functions, 15 type flags, 2 sentinels)
is checked against the canonical TypeScript by
[`../tools/check_parity.py`](../tools/check_parity.py), case- and
underscore-insensitively (`GetPath` ↔ `getpath`).

C#-specific points the signatures don't show:

- **`object?` at the boundaries.** The API is intentionally "JSON-shaped
  `object?`": maps are `Dictionary<string, object?>`, lists are `IList`,
  scalars are boxed primitives. The predicates (`IsNode`, `IsMap`,
  `IsList`) inspect the runtime type rather than narrowing a static one.
- **`GetProp` vs `GetElem`.** `GetProp(val, key, alt)` works on maps and
  lists; `GetElem(val, key, alt)` is list-specific, supports `-1`-from-the-
  end indexing, and *invokes* a callable `alt` when the element is absent.
- **The static class is `StructUtils`.** Call everything as
  `StructUtils.GetPath(...)` etc.; the methods are `public static`.
- **Mode constants live on `StructUtils`** as `const int`: `M_KEYPRE`,
  `M_KEYPOST`, `M_VAL` (= 1, 2, 4). The type-name helper is `TypeName`.
- **Type flags** combine bitwise on the `T` class: `Typify("hi")` is
  `T.Scalar | T.Str`; test with `0 != (T.Str & t)`. `T.Str`/`T.Func` are
  named short because `String`/`Func` collide with BCL types.
- **`Jsonify(val, indent = 2, offset = 0)`** takes an integer indent
  directly (0 = compact), not a flags map.

---

## 4. Explanation & port specifics

### This is a port, not the canonical

Behaviour is defined by the canonical TypeScript and pinned by the shared
corpus in [`../build/test/`](../build/test/). Practically:

- A behaviour question is answered by reading
  [`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts)
  and the corpus, not by reading this port in isolation.
- A change to canonical behaviour starts in TypeScript, then flows to the
  corpus and out to every port including this one (see
  [`../AGENTS.md`](../AGENTS.md#standard-workflows)).

### `null` and `object?`

C# nullable reference types are enabled (`<Nullable>enable</Nullable>`), and
the API exposes `object?` throughout. As in Go and Java, a single `null`
covers both JSON null and "absent" — there is no separate undefined value.
The [Group A/B rule](../DOCS.md#null-versus-absent-group-ab) is still
honoured by behaviour:

- **Group A readers** (`GetProp`, `GetElem`, `HasKey`, `IsEmpty`, `IsNode`)
  treat a stored `null` as *no value*; you get the `alt` or `false`.
- **Group B value-processors** (`SetProp`, `Clone`, `Walk`, `Merge`,
  `Inject`, `Transform`, `Validate`, `Select`, …) preserve `null`
  literally. The corpus marks a real null with `"__NULL__"` and uses
  `"__UNDEF__"`/`"__EXISTS__"` in match assertions to keep the two distinct
  across the JSON round-trip.

### Reference-stable containers

`Walk`, `Merge`, `Inject`, and `SetPath` rely on `Dictionary`/`List` being
reference types — a mutation through one handle is visible through every
alias. C# gives this for free, so (unlike Go, PHP, Rust, C) this port needs
no `ListRef`-style wrapper. Map key order is insertion order via
`Dictionary<string, object?>`, which `Jsonify`/`KeysOf`/`Items` observe.

### Regex

The regex layer is the uniform six-function API (`ReCompile` / `ReTest` /
`ReFind` / `ReFindAll` / `ReReplace` / `ReEscape`) wrapping
`System.Text.RegularExpressions.Regex`. Stay inside the **RE2 subset** —
.NET *allows* backreferences and lookaround, but those don't port. Because
.NET's engine backtracks, this port lands with the
ECMA/PCRE/Java backtracking family on the two sharp edges (catastrophic
backtracking; zero-width `ReReplace("a*", "abc", "X")` returning
`"XXbXcX"`, where RE2/Go returns `"XbXcX"`). Both are detailed in
[`README.md` → Regex](./README.md#regex) and
[`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md). .NET 7+ offers
`RegexOptions.NonBacktracking` if you must accept untrusted patterns.

---

## Build, test, and extend

From [`Makefile`](./Makefile) (the `.NET` SDK must be on PATH):

```bash
cd csharp
make build          # dotnet build VoxgigStruct.csproj
make test           # dotnet test tests/VoxgigStructTest.csproj
make lint           # dotnet build -warnaserror  +  dotnet format --verify-no-changes
make audit          # dotnet list package --vulnerable (fails on a known CVE)
```

Lint is **Roslyn analyzers**, not a separate tool: the csproj turns on
`EnableNETAnalyzers` + `EnforceCodeStyleInBuild` at `AnalysisLevel 8.0`, and
`make lint` promotes those warnings to errors and then runs
`dotnet format --verify-no-changes`. The analysis level is pinned to `8.0`
on purpose (see the csproj comment) so a newer SDK can't introduce a new
default-on rule and break CI.

Tests live in [`tests/`](./tests/); the runner
([`tests/Runner.cs`](./tests/Runner.cs)) loads the shared corpus from
[`../build/test/`](../build/test/) the same way every port's runner does.
The xUnit panel ([`tests/StructTest.cs`](./tests/StructTest.cs)) is the
green-bar regression baseline, and `tests/RegexPathologicalTest.cs` holds
the regex edge-case panel.

**To change behaviour:** this port follows the canonical TypeScript. Fix a
disagreement by matching `Struct.cs` to the canonical and the corpus — do
not edit the corpus. A genuine canonical change starts in TypeScript, then
propagates here; re-run `make test` and
`python3 ../tools/check_parity.py`. The full checklist is in
[`../AGENTS.md`](../AGENTS.md). Toolchain: .NET SDK 8.0.100 (pinned in
[`global.json`](./global.json)), LangVersion 12.
