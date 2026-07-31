# AGENTS.md — C# port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the C# port.

> **This is a port, not the canonical.** Behaviour is defined by the
> TypeScript in [`../typescript/`](../typescript/) and pinned by the shared
> corpus. If this port and the corpus disagree, the **port** is wrong — fix
> `Struct.cs` to match, never the corpus.

## Layout

```
csharp/
├── Struct.cs                 # the whole port: namespace Voxgig.Struct
├── VoxgigStruct.csproj        # net8.0, analyzers, AssemblyName VoxgigStruct
├── global.json                # SDK pinned to 8.0.100
├── Makefile                   # build / test / lint / audit / inspect
├── .editorconfig              # code-style rules the analyzers enforce
├── test-baseline.json         # committed corpus-scoreboard baseline
└── tests/
    ├── VoxgigStructTest.csproj # xUnit test project
    ├── Runner.cs               # shared-corpus runner (loads ../build/test/)
    ├── StructTest.cs           # green-bar regression panel
    ├── CorpusScoreboard.cs     # per-.aontu pass counts -> scoreboard json
    └── RegexPathologicalTest.cs
```

The public surface is the static class **`StructUtils`** in `Struct.cs`.
`../tools/check_parity.py` matches its `public static` members against the
canonical TS [`export { … }`](../typescript/src/StructUtility.ts) block,
case- and underscore-insensitively (`GetPath` ↔ `getpath`). Adding or
removing a public function changes parity.

## Commands

```bash
make build          # dotnet build VoxgigStruct.csproj
make test           # dotnet test tests/VoxgigStructTest.csproj
make lint           # dotnet build -warnaserror  +  dotnet format --verify-no-changes
make format-check   # dotnet format --verify-no-changes only
make audit          # fail on any NuGet package with a known vulnerability
make inspect        # print the resolved .NET SDK version
make clean / reset  # remove bin/ obj/ (clean); reset == clean
```

From the repo root, `make test-csharp` / `make lint-csharp` wrap the same
commands. First run restores NuGet packages.

## Conventions specific to this port

- **Casing:** PascalCase for every public member (`GetPath`, `SetProp`,
  `EscRe`, …). See the [naming table](./README.md#naming-convention).
- **Data model:** maps are `Dictionary<string, object?>`, lists are
  `List<object?>`, scalars are boxed primitives. `Dictionary` preserves
  insertion order, which `Jsonify`/`KeysOf`/`Items` rely on — don't swap in
  an unordered map.
- **Two BCL-collision renames:** the type flag is `T.Str` (not `T.String`)
  and `T.Func` (not `T.Function`). Keep these; behaviour is unchanged.
- **`InjectState`** is this port's name for the canonical `Injection` state
  object; it is the optional trailing arg to `GetPath`/`Inject`/`Transform`/
  `Validate` and carries `Errs`, `Mode`, and `Extra`.
- **No `ListRef` wrapper.** `Dictionary`/`List` are reference types, so
  reference-stable mutation (which `Merge`/`Walk`/`Inject`/`SetPath` need)
  works without the wrapper that Go, PHP, C, Rust, and Zig require.
- **`null` is "absent" and "JSON null" both** — there is no separate
  undefined. Behaviour still splits Group A (treat stored null as absent)
  from Group B (preserve null); see Gotchas.

## Gotchas

- **`AnalysisLevel` is pinned to `8.0` on purpose** (csproj comment), *not*
  `latest`, so a newer SDK patch can't turn on a new default rule and break
  CI. Don't bump it to chase newer analyzers; that pin is the point. The
  same reasoning is why `global.json` pins the SDK to `8.0.100`.
- **Group A/B is the #1 source of port bugs.** Group A readers (`GetProp`,
  `GetElem`, `HasKey`, `IsEmpty`, `IsNode`) return alt/`false` for a stored
  `null`; Group B processors (`SetProp`, `Clone`, `Walk`, `Merge`, `Inject`,
  `Transform`, `Validate`, `Select`, …) preserve it. The port distinguishes
  a stored null from a missing slot internally via the `NONE` sentinel — do
  not collapse the two when touching a read/merge/clone path.
- **Lint == analyzers + format.** There is no standalone linter; `make lint`
  is `dotnet build -warnaserror` (Roslyn `.NET` + code-style analyzers, from
  the csproj's `EnableNETAnalyzers`/`EnforceCodeStyleInBuild`) plus a
  `dotnet format --verify-no-changes` style check against `.editorconfig`.
- **Editing here is *not* a cross-port event by default.** A fix here should
  make the port match the canonical TS + corpus. Only a deliberate canonical
  change starts in TypeScript and fans out to every port; after one, re-run
  `make test` here and `python3 ../tools/check_parity.py`.
- **The .NET SDK may be missing** in a given environment. If you can't build
  or test, say so — don't claim a change passes.
- **The regex engine backtracks** (`System.Text.RegularExpressions`), so
  this port shares the ECMA/PCRE/Java edge cases, not the RE2 ones. Stay in
  the RE2 subset; don't "fix" documented pathological differences by
  diverging (see [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md)).

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  `../tools/check_parity.py` · Status: [`../REPORT.md`](../design/REPORT.md)
