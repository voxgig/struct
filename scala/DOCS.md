# Scala port — comprehensive guide

This document covers the Scala-specific details of `voxgig/struct`. For the
language-neutral concepts, tutorial and full reference, read the top-level
[`DOCS.md`](../DOCS.md); for the user overview, [`README.md`](./README.md).
TypeScript is canonical and the shared `build/test` corpus is the contract.

## Installation

The library is a single source file (`src/voxgig_struct.scala`) and needs
nothing but the Scala 3 toolchain. Compile it into your project and
`import voxgig.struct.*`.

## Representation of data

| JSON-shape thing        | Scala representation                                  |
|-------------------------|-------------------------------------------------------|
| object / map            | `VMap(LinkedHashMap[String, Value])` (insertion order)|
| array / list            | `VList(ArrayBuffer[Value])`                            |
| string                  | `VStr(String)`                                         |
| number (int or decimal) | `VNum(Double)`                                         |
| boolean                 | `VBool(Boolean)`                                       |
| JSON `null`             | `VNull`                                                |
| undefined / absent      | `Noval`                                                |
| function (commands)     | `VFunc(Injector)`                                      |

Nodes are **mutable and reference-stable** on purpose: `merge`, `walk`,
`inject`, `transform`, `validate` mutate nodes in place and depend on shared
references. Build nodes with `mkMap` / `mkList` (or `jm` / `jt`); the mutable
`LinkedHashMap` preserves insertion order and keeps a key's position when it is
re-assigned.

### `Noval` vs `VNull`

Unlike the single-`nil` ports (Python, Clojure, Lua), Scala keeps the two
canonical concepts apart, exactly like TypeScript, Rust and OCaml:

- `Noval` — the TS `undefined`: a property is absent. **Not** a scalar.
- `VNull` — JSON `null`: a real value.

The Group A / Group B rules ([`design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md))
decide which one a slot collapses to:

- **Group A** readers — `getprop`, `getelem`, `haskey` — treat a stored `VNull`
  as "no value" (they return the default).
- **Group B** processors — `setprop`, `clone`, `merge`, `walk`, `inject`,
  `transform`, `validate`, `select` — preserve `VNull` literally. The internal
  `lookup_` is the raw reader they use when null must survive.

```scala
typify(Noval)            // T_noval
typify(VNull)            // T_scalar | T_null
stringify(Noval)         // ""
stringify(VNull)         // "null"
```

## The public API

Names are the canonical names, lower-smushed or camelCased:

- **Lookups / paths:** `getpath`, `setpath`, `getprop`, `setprop`, `getelem`,
  `delprop`, `haskey`, `keysof`, `items`.
- **Predicates / kinds:** `isnode`, `ismap`, `islist`, `iskey`, `isfunc`,
  `isempty`, `typify`, `typename`.
- **Values:** `clone`, `merge`, `walk`, `size`, `slice`, `pad`, `flatten`,
  `filter`, `getdef`, `strkey`.
- **Strings / formatting:** `stringify`, `jsonify`, `pathify`, `join`,
  `escre`, `escurl`.
- **Regex (RE2-subset uniform API):** `re_compile`, `re_find`, `re_find_all`,
  `re_replace`, `re_test`, `re_escape`. Backed by `java.util.regex`.
- **By-example engine:** `inject`, `transform`, `validate`, `select`, and the
  injector helpers `checkPlacement`, `injectorArgs`, `injectChild`.
- **Builders / markers:** `jm`, `jt`, `SKIP`, `DELETE`, the `T_*` type
  constants and `M_KEYPRE` / `M_KEYPOST` / `M_VAL`.

Many functions take Scala default arguments where the canonical has optional
parameters, e.g. `getprop(v, key, alt = Noval)`, `slice(v, start, stop,
mutate)`, `stringify(v, maxlen, pretty)`, `merge(objs, maxdepth)`.

## Examples

```scala
import voxgig.struct.*

// merge: later wins; the first node is modified in place
merge(jt(jm(VStr("a"), VNum(1.0)), jm(VStr("b"), VNum(2.0))))      // {a:1,b:2}

// transform: spec mirrors the output; backticks pull from the data
transform(jm(VStr("name"), VStr("alice")),
          jm(VStr("user"), jm(VStr("id"), VStr("`name`"))))        // {user:{id:alice}}

// validate: plain values are typed defaults; `$STRING` etc. are commands
validate(jm(VStr("a"), VStr("x")), jm(VStr("a"), VStr("`$STRING`"))) // {a:x}

// select: MongoDB-style query over children
select(jt(jm(VStr("a"), VNum(1.0)), jm(VStr("a"), VNum(2.0))),
       jm(VStr("a"), jm(VStr("`$GT`"), VNum(1.0))))                // [{$KEY:1,a:2}]
```

## Testing

`make test` compiles `src/` + `test/runner.scala` with `scalac` and runs the
entire shared corpus (`../build/test/test.json`) through the port via `scala`,
using an in-tree JSON reader and the same runner logic as every other port.
Keep it green, keep `python3 ../tools/check_parity.py` green, and add no runtime
dependencies.

## Implementation notes

- The injection state (`Inj`) is a mutable class; callers pass a loose `InjDef`
  via the `InjArg` ADT, so it is never confused with data.
- `SKIP` / `DELETE` are `VSentinel` markers.
- Numbers follow JS formatting in `stringify` / `jsonify` (an integral
  `VNum` prints without a trailing `.0`); `numToString` relies on Java's
  shortest round-tripping `Double.toString` for non-integers.
- The only regex is the JVM standard `java.util.regex`, which covers the RE2
  subset the corpus uses for `$LIKE` and the `re_*` API.
