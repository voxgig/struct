# AGENTS.md — Clojure port of `voxgig/struct`

Read the repo-root [`AGENTS.md`](../AGENTS.md) first. This file covers only
what is specific to the Clojure port. **TypeScript is canonical; the shared
`build/test/*.jsonic` corpus is the contract.** This port is a faithful
translation of the canonical implementation (modelled most closely on the
Python port, which shares Clojure's single-`nil` world).

## How to build / test / lint

```
cd clojure
make test     # clojure -M:test   — runs build/test/test.json through the port
make lint     # compiles the library + runner namespaces (a clean load = pass)
```

Requires the Clojure CLI (`clojure`/`clj`) and a JDK on `PATH`. The library
itself has **zero third-party runtime dependencies**; the test runner reads
the corpus with a small in-tree JSON reader (no JSON library).

## The one thing to understand: nodes are mutable Java collections

The canonical algorithm assumes nodes are **mutable and reference-stable**:
`walk`, `merge`, `inject`, `transform`, `validate` and the `Injection`
state machine mutate nodes in place and rely on shared references. Idiomatic
immutable Clojure maps/vectors cannot model that without rewriting the
algorithm, which would break uniformity. So this port represents nodes with:

- **maps → `java.util.LinkedHashMap`** (insertion-ordered, like a JS object),
- **lists → `java.util.ArrayList`** (mutable, reference-stable).

`ismap`/`islist`/`isnode` test `java.util.Map`/`java.util.List`. All node-
creating code (`{}`/`[]` in the canonical) builds `LinkedHashMap`/`ArrayList`
via the private `lhm`/`alist` helpers. **Never** introduce a persistent
Clojure map/vector as a *node* — only as a short-lived read-only intermediate.

## `nil` is both `undefined` and JSON `null`

Like Python, Clojure has only `nil`. The canonical `undefined` (absent) and
JSON `null` both map to `nil`. The Group A/B rules (see
[`design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)) recover the distinction
where it matters:

- Group A readers (`getprop`, `getelem`, `haskey`, `isnode`, `isempty`)
  treat a stored `nil` as "no value".
- Group B processors (`setprop`, `clone`, `merge`, `walk`, `inject`, …)
  preserve `nil` literally. `_lookup` is the internal raw reader.

A few functions distinguish "no argument supplied" from `nil` via the public
`NOARG` sentinel (mirrors Python's `_ABSENT`): `typify` (→ `T_noval` vs
`T_null`), `stringify` (→ `""` vs `"null"`), `pathify`.

## Naming

Public function names are **lower-smushed, exactly the canonical names**
(`getpath`, `getprop`, `ismap`, `isnode`, `setpath`, `checkPlacement`,
`re_find_all`, …) so the case/underscore-insensitive parity check in
`tools/check_parity.py` matches them directly. The namespace `:refer-clojure
:exclude`s `merge`, `filter`, `flatten` and `replace` to reuse those names.

## Gotchas

- **Identity markers.** `SKIP` and `DELETE` are specific `LinkedHashMap`
  instances; compare with `identical?` (never `=`).
- **The `Injection` is a distinct type** (`deftype Inj` over a mutable
  `HashMap`), so it is never mistaken for a data map by `ismap`. Access its
  fields only through the internal `ig`/`is!` helpers.
- **Numbers.** JSON integers parse to `Long`, decimals to `Double`. `typify`
  splits integer/decimal on that; `stringify`/`jsonify` follow JS number
  formatting (an integral `Double` prints without `.0`).
- **Keep `make test` and `python3 tools/check_parity.py` green**, and add no
  runtime dependencies. If you change canonical behaviour, change the
  TypeScript + corpus first, then propagate here.
