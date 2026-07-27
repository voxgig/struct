# voxgig-struct (Lean)

Lean 4 port of [`voxgig/struct`](https://github.com/voxgig/struct) — one
small, fixed API for manipulating JSON-shaped data: lookups, deep merge,
by-example transform, by-example validate, tree walk, path get/set,
selection. The behaviour is defined by the canonical TypeScript
implementation and the shared `build/test/*.jsonic` corpus; this port passes
the full corpus (1329/1329).

## Requirements

- The Lean 4 toolchain, installed via [elan](https://github.com/leanprover/elan)
  (the exact version is pinned by [`lean-toolchain`](./lean-toolchain);
  `lake` fetches it automatically on first build).
- **Zero third-party dependencies** — the library uses only the Lean core
  library. The test runner has an in-tree JSON reader, and regex is the
  in-tree `src/Vregex.lean` engine (RE2 subset).

## Build & test

```
cd lean
make test    # lake build + run the shared build/test/test.json corpus
make lint    # type-check (a clean, warnings-free compile = pass)
```

## Usage sketch

The whole API runs in `SIO` (`ReaderT Ctx IO`): nodes are mutable,
reference-stable handles into a per-context heap, exactly like the mutable
nodes of the canonical TypeScript. Create a context once, then run library
operations against it:

```lean
import VoxgigStruct
open VoxgigStruct

def demo : IO Unit := do
  let ctx ← mkCtx
  let go : SIO Unit := do
    let store ← jm [.str "a", ← jm [.str "b", .num 1.0]]
    let v ← getpath store (.str "a.b")
    IO.println (← stringify v)     -- "1"
  go.run ctx
```

- `Value.noval` is the TS `undefined` (property absent); `Value.null` is
  JSON null. They are distinct, as in the canonical implementation.
- `Value.list`/`Value.map` are heap handles; use `jm`/`jt`/`newMap`/`newList`
  to build them and `getprop`/`setprop`/`getpath`/… to work with them.

## Layout

```
lean/
├── lakefile.toml        # lake package: VoxgigStruct + Vregex libs, runner exe
├── lean-toolchain       # pinned Lean version (managed by elan)
├── src/
│   ├── VoxgigStruct.lean  # the library (canonical API)
│   └── Vregex.lean        # in-tree RE2-subset regex engine
└── test/
    └── Runner.lean        # shared-corpus test runner (in-tree JSON reader)
```

Documentation: [`DOCS.md`](./DOCS.md) (comprehensive guide),
[`AGENTS.md`](./AGENTS.md) (notes for AI coding agents), and the
language-neutral [`../README.md`](../README.md) / [`../DOCS.md`](../DOCS.md).
