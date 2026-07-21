# voxgig_struct — AQL

An [AQL](https://github.com/aql-lang/aql) port of
[`voxgig/struct`](../README.md): one small, fixed API for manipulating
JSON-shaped data — lookups, deep merge, by-example transform, by-example
validate, tree walk, path get/set, selection — that returns the **same
answer** as the canonical TypeScript implementation and every other port.
The behavioural contract is the shared JSON corpus in
[`build/test/`](../build/test); this port passes it in full.

The port is written **in the AQL language itself** (a concatenative,
strongly-typed query language on Go) — it deliberately does not wrap the
engine's native `aql:struct-util` module, so it exercises AQL as an
application language.

## Status

Complete. Every canonical public function is implemented and the entire
shared corpus passes (`make test`). **Zero third-party dependencies** —
only the `aql` CLI is required (the library imports only the engine's
bundled `aql:` modules: `string-util`, `math-util`, `bin-util`,
`minilang`, `emitlang`, `time-util`; the test runner additionally
uses `aql:io` to read the corpus).

## Requirements

- The [`aql`](https://github.com/aql-lang/aql) CLI on your PATH (or pass
  `make test AQL=/path/to/aql`).

## Use

```aql
import "./src/struct.aql" end

def store (flex {a: {b: 2}})
print (Struct.getpath store "a.b" Struct.NOARG)          ;# 2

def out (Struct.transform (flex {a: 1}) (flex {x: "`a`"}) Struct.NOARG)
print (Struct.stringify out Struct.NOARG Struct.NOARG)   ;# {x:1}
```

The canonical public names are the keys of the `Struct` export map —
`Struct.getpath`, `Struct.merge`, `Struct.transform`, `Struct.validate`,
`Struct.select`, … — plus the `T_*`/`M_*` constants and the `NOARG`,
`SKIP` and `DELETE` sentinels.

### Calling conventions (differences from the canonical API)

AQL has no optional parameters, no variadics, and no `undefined`:

- **Optional arguments** are passed explicitly as `Struct.NOARG`
  ("argument not given"). `getpath(store, path)` becomes
  `Struct.getpath store path Struct.NOARG`.
- **`jm` / `jt`** take one list argument instead of variadic arguments:
  `Struct.jm ["a" 1 "b" 2]` / `Struct.jt [1 2 3]`.
- **Function values** (walk callbacks, transform commands, `modify`
  hooks) travel in carriers: a one-element list `[f/r]` for pure
  callbacks, or an fn box `` {"`$FN`": f/r} `` where the canonical API
  `isfunc`-tests the value (store commands, handlers). See
  [`AGENTS.md`](./AGENTS.md) for the full convention.
- **`none` plays both `undefined` and JSON `null`** (the single-null
  model of the Python / Dart / Lua ports). The Group A/B rules
  ([`../design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)) recover the
  distinction.

### Data model

Nodes are AQL **flex** collections (`flex {}` / `flex []`), which are
mutable and reference-stable exactly as the algorithms require: `merge`,
`walk`, `inject`, `transform` and `validate` mutate nodes in place and
depend on shared references. Plain (immutable) maps and lists are
accepted as inputs; node-creating code always builds flex nodes.

## Layout

- [`src/struct.aql`](./src/struct.aql) — the whole library (one module).
- [`test/runner.aql`](./test/runner.aql) — corpus runner entry point.
- [`test/runner-lib.aql`](./test/runner-lib.aql) — the runner module
  (mirrors `typescript/test/runner.ts`).
- [`test/lint.aql`](./test/lint.aql) — the `make lint` load smoke.

## Test / lint

```
cd aql
make test    # aql run -no-check -no-compile test/runner.aql
make lint    # module load smoke (see AGENTS.md for why not `aql check`)
```

See [`DOCS.md`](./DOCS.md) for the comprehensive guide and
[`AGENTS.md`](./AGENTS.md) for contributor/agent notes.
