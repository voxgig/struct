# Lean port — the full guide

This document covers the Lean-specific details of `voxgig/struct`. For the
language-neutral concepts, tutorial and full reference, read the top-level
[`DOCS.md`](../DOCS.md); for the user overview, [`README.md`](./README.md).
TypeScript is canonical and the shared `build/test` corpus is the contract.

## Installation

The library is two source files under `src/` and needs nothing but the
Lean 4 toolchain (pinned by `lean-toolchain`, managed by
[elan](https://github.com/leanprover/elan)). Use it as a lake dependency, or
copy `src/VoxgigStruct.lean` and `src/Vregex.lean` into your project and
`import VoxgigStruct`.

## Representation of data

| JSON-shape thing        | Lean representation                     |
|-------------------------|-----------------------------------------|
| object / map            | `Value.map id` (heap handle, ordered)   |
| array / list            | `Value.list id` (heap handle)           |
| string                  | `Value.str s`                           |
| number (int or decimal) | `Value.num n` (`Float`)                 |
| boolean                 | `Value.bool b`                          |
| JSON `null`             | `Value.null`                            |
| undefined / absent      | `Value.noval`                           |
| function (commands)     | `Value.func fid` (registry handle)      |

Nodes are **mutable and reference-stable** on purpose: `merge`, `walk`,
`inject`, `transform`, `validate` mutate nodes in place and depend on shared
references. Lean's strict positivity rules forbid `IO.Ref` fields inside the
`Value` inductive, so lists and maps are handles (indices) into a mutable
node heap — the same design as the Elixir port's ETS heap — and function
values are handles into a registry. Map entries preserve insertion order.

### The `SIO` monad and `Ctx`

All mutable state (the node heap, the function registries, the injection
arena) lives in a `Ctx`, and the whole API runs in `SIO := ReaderT Ctx IO`:

```lean
def demo : IO Unit := do
  let ctx ← mkCtx
  let go : SIO Unit := do
    let store ← jm [.str "a", ← jm [.str "b", .num 1.0]]
    IO.println (← stringify (← getpath store (.str "a.b")))   -- "1"
  go.run ctx
```

The state is *not* kept in module-`initialize` globals deliberately: values
stored in a persistent global `IO.Ref` are marked as shared by the Lean
runtime, which defeats functional-but-in-place array updates and would make
every heap write O(heap). Runtime-created refs stay unshared and update in
place, so heap writes are O(1).

### `noval` vs `null`

Unlike the single-`nil` ports (Python, Clojure, Lua), Lean keeps the two
canonical concepts apart, exactly like TypeScript, OCaml and Haskell:

- `Value.noval` — the TS `undefined`: a property is absent. **Not** a scalar.
- `Value.null` — JSON `null`: a real value.

The Group A / Group B rules ([`design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md))
decide which one a slot collapses to:

- **Group A** readers — `getprop`, `getelem`, `haskey` — treat a stored
  `null` as "no value" (they return the default).
- **Group B** processors — `setprop`, `clone`, `merge`, `walk`, `inject`,
  `transform`, `validate`, `select` — preserve `null` literally. The
  internal `lookupRaw` is the raw reader they use when null must survive.

```lean
typify .noval            -- T_NOVAL
typify .null             -- T_SCALAR ||| T_NULL
← stringify .noval       -- ""
← stringify .null        -- "null"
```

## The public API

Names are the canonical names, lower-smushed or camelCased:

- **Lookups / paths:** `getpath`, `setpath`, `getprop`, `setprop`, `getelem`,
  `delprop`, `haskey`, `keysof`, `items`, `pathify`
- **Shape:** `isnode`, `ismap`, `islist`, `iskey`, `isempty`, `isfunc`,
  `typify`, `typename`, `size`
- **Processing:** `clone`, `merge`, `walk`, `inject`, `transform`,
  `validate`, `select`, `filter`, `flatten`, `slice`
- **Strings:** `stringify`, `jsonify`, `escre`, `escurl`, `join`, `joinurl`,
  `pad`, `strkey`, `getdef`
- **Regex:** `reCompile`, `reFind`, `reFindAll`, `reReplace`, `reTest`,
  `reEscape` (backed by the in-tree `Vregex` RE2-subset engine with capture
  tracking, at the Go-stdlib minimum of `design/REGEX_API.md`)
- **Builders:** `jm` (map from alternating key/value list), `jt` (list)
- **Injection internals (canonical):** `checkPlacement`, `injectorArgs`,
  `injectChild`

Optional arguments use Lean default parameters, e.g.
`getprop v key (alt := .noval)`, `slice v (start := …) (stop := …)
(mutate := false)`, `walk v (before := some f) (after := …)`.

Injection state (`Injection` in the canonical TS) is the `InjData`
structure, held in an arena and addressed by `InjId`; the public API accepts
an `InjArg` (`.iinj id | .idef injdef | .inone`), where `InjDef` is the
loose `Partial<Injection>` options record.

Errors (failed `transform`/`validate`) are thrown as `IO.userError` with the
canonical joined message; catch with `try … catch`.

## Numbers

`Value.num` is a `Float` (like the OCaml and Rust ports). `typify` splits
integer/decimal with `Number.isInteger` semantics (`2.0` is an integer).
String conversion follows JS `Number::toString`: shortest round-trip decimal
digits computed with exact `Nat` arithmetic (see `numToString`), so `1.1`
prints as `"1.1"`, not `"1.100000"`.

## Testing

```
make test    # run the shared corpus on voxgig/omni (77 groups)
make build   # type-check the library alone (no omni)
make lint    # clean, warnings-free compile = pass
```

`make test` runs the shared corpus (`../build/test/test.json`) through the
port on [voxgig/omni](https://github.com/voxgig/omni), the shared test runner
— so the entry loop, the comparison and the `err` and `match` handling are
literally the same code every other port runs. **1360** entries over 77
groups. omni is a local checkout the Makefile finds via `$OMNI_HOME` or
beside this repository and copies into `.omni-build/`; `lakefile.toml`
declares it as a lean_lib only the runner imports, so `make build` compiles
the library alone.

`test/Runner.lean` is now only a bridge and a list of subjects. It converts
omni's `Val` into this port's heap-backed `Value` and back — so what a
subject receives is a real mutable node, and the arguments go back to omni
after the call, which is what `match.args` asserts on in `minor/setpath` and
`merge/integrity`.

One thing to know: omni's Lean port uses `Lean.Data.Json`, which stores
objects in a **sorted** tree. Every map in the corpus is written key-sorted,
so a sorted read and an insertion-ordered one agree today — but an entry
authored out of key order would be silently reordered on the way in. The
port's own reader used to preserve insertion order for exactly that reason.
