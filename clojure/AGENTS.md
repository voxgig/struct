# AGENTS.md — Clojure port of `voxgig/struct`

Read the repo-root [`AGENTS.md`](../AGENTS.md) first. This file covers only
what is specific to the Clojure port. **TypeScript is canonical; the shared
`build/test/*.aontu` corpus is the contract.** This port is a faithful
translation of the canonical implementation (modelled most closely on the
Python port, which shares Clojure's single-`nil` world).

## How to build / test / lint

```
cd clojure
make test     # the shared corpus, on voxgig/omni
make lint     # compiles the library + runner namespaces (a clean load = pass)
make build    # compiles the LIBRARY alone (no omni)
```

Requires the Clojure CLI (`clojure`/`clj`) and a JDK on `PATH`. The library
itself has **zero third-party runtime dependencies**.

- **The corpus runner is voxgig/omni, taken from its release tag.** `deps.edn`
  declares `io.github.voxgig/omni` at `clojure/v0.1.0` — with the sha that tag
  must resolve to, and `:deps/root "clojure"` for the subdirectory — inside an
  `:omni` ALIAS. There is no checkout to find and no `$OMNI_HOME`. The alias is
  the isolation device: an alias is never transitive, so nothing the published
  jar carries depends on omni
  (register 4.13).
- **`test/voxgig/struct_runner.clj` is a bridge plus a list of subjects.**
  `tostruct` / `toomni` convert between omni's persistent Clojure data and
  this port's mutable `java.util.LinkedHashMap` / `ArrayList` nodes;
  everything else — the entry loop, `fixjson`, deep equality, `err` and
  `match` handling — is omni's.
- **`match.args` needs the arguments back.** The conversion is a copy in both
  directions, so a subject cannot write through omni's argument list.
  `:runsetflags-args` takes a subject returning `[args result]`. Delete the
  write-back and `minor.setpath` and `merge.integrity` fail — which is the
  check that it is load-bearing.
- **An integral number becomes a `Long`.** omni parses every JSON number with
  `Double/parseDouble`; this port's `typify` reads T_integer / T_decimal off
  the JVM type, so `tostruct` normalises an integral double back. struct/go's
  shim needed the same (voxgig/omni#13).
- **A zero-argument entry is CALLED with no argument.** omni supplies `ABSENT`
  (voxgig/omni#30, register 4.12) and `run-set` turns that into `(subject)`,
  falling back to `(subject nil)` for a function with no nullary arity. It is
  the only way a port with one `nil` can separate `minor/typify`'s
  `{in: null}` from its `{}`.

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
