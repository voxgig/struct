# voxgig_struct — boru

A [boru](https://github.com/boru-lang/boru) port of
[`voxgig/struct`](../README.md): one small, fixed API for manipulating
JSON-shaped data — lookups, deep merge, by-example transform, by-example
validate, tree walk, path get/set, selection — that returns the **same
answer** as the canonical TypeScript implementation and every other port.
The behavioural contract is the shared JSON corpus in
[`build/test/`](../build/test); this port passes it in full.

The port is written **in the boru language itself** (a concatenative,
strongly-typed query language on Go) — it deliberately does not wrap the
engine's native `boru:struct-util` module, so it exercises boru as an
application language.

## Status

Complete. Every canonical public function is implemented and the entire
shared corpus passes (`make test`). **Zero third-party dependencies** —
only the `boru` CLI is required (the library imports only the engine's
bundled `boru:` modules: `string-util`, `math-util`, `bin-util`,
`minilang`, `emitlang`, `time-util`; the test runner additionally
uses `boru:io` to read the corpus).

## Requirements

- The [`boru`](https://github.com/boru-lang/boru) CLI on your PATH (or pass
  `make test BORU=/path/to/boru`).

## Use

```boru
import "./src/struct.boru" end

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

boru has no optional parameters, no variadics, and no `undefined`:

- **Optional arguments** are passed explicitly as `Struct.NOARG`
  ("argument not given"). `getpath(store, path)` becomes
  `Struct.getpath store path Struct.NOARG`.
- **`jm` / `jt`** take one list argument instead of variadic arguments:
  `Struct.jm ["a" 1 "b" 2]` / `Struct.jt [1 2 3]`.
- **Function values** (walk callbacks, transform commands, `modify`
  hooks) travel in carriers: a one-element list `[f/v]` for pure
  callbacks, or an fn box `` {"`$FN`": f/v} `` where the canonical API
  `isfunc`-tests the value (store commands, handlers). See
  [`AGENTS.md`](./AGENTS.md) for the full convention.
- **`none` plays both `undefined` and JSON `null`** (the single-null
  model of the Python / Dart / Lua ports). The Group A/B rules
  ([`../design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)) recover the
  distinction.

### Data model

Nodes are boru **flex** collections (`flex {}` / `flex []`), which are
mutable and reference-stable exactly as the algorithms require: `merge`,
`walk`, `inject`, `transform` and `validate` mutate nodes in place and
depend on shared references. Plain (immutable) maps and lists are
accepted as inputs; node-creating code always builds flex nodes.

## Layout

- [`src/struct.boru`](./src/struct.boru) — the whole library (one module).
- [`test/runner.boru`](./test/runner.boru) — corpus runner entry point.
- [`test/runner-lib.boru`](./test/runner-lib.boru) — the runner module
  (mirrors `typescript/test/runner.ts`).
- [`test/lint.boru`](./test/lint.boru) — the `make lint` load smoke.

## Test / lint

```
cd boru
make test    # boru run -no-check -no-compile test/runner.boru
make lint    # boru check src/struct.boru + a module load smoke
```

See [`DOCS.md`](./DOCS.md) for the comprehensive guide and
[`AGENTS.md`](./AGENTS.md) for contributor/agent notes.
