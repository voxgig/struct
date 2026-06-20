# AGENTS.md — Scala port of `voxgig/struct`

Read the repo-root [`AGENTS.md`](../AGENTS.md) first. This file covers only
what is specific to the Scala port. **TypeScript is canonical; the shared
`build/test/*.jsonic` corpus is the contract.** This port mirrors the
canonical TypeScript logic directly (it was ported from the OCaml port), because
Scala — like TypeScript, Rust and OCaml — keeps `undefined` and JSON `null`
distinct.

## How to build / test / lint

```
cd scala
make test    # scalac compiles src + test, scala runs build/test/test.json
make lint    # type-checks the library (a clean compile = pass)
```

Requires the Scala 3 compiler (`scalac` / `scala`) and a JDK on `PATH`. **Zero
third-party dependencies** — the test runner has an in-tree JSON reader, and
the only regex used is the JVM standard `java.util.regex`.

## The value model

Everything is one sealed ADT (`Value`) so the functions are effectively
dynamic within it:

```
Noval | VNull | VBool | VNum(Double) | VStr | VList(ArrayBuffer[Value])
      | VMap(LinkedHashMap[String, Value]) | VFunc(Injector) | VSentinel(String)
```

- **`Noval` is the TS `undefined`** (property absent); **`VNull` is JSON null**.
  Distinct — the canonical TS model. `isNullish` covers both (JS `null == v`);
  `isNoval` is `undefined` only. Group A readers (`getprop`, `getelem`,
  `haskey`) return the default on either; Group B processors use the raw
  `lookup_` to preserve `VNull`. **Getting `getprop` (Group A) vs `lookup_`
  (raw) right is the single most common source of port bugs** — e.g. validate's
  bad-key check and `transform`'s `$FORMAT`/`$REF` argument reads use `lookup_`.
- **Numbers are a single `VNum(Double)`** (like Rust/OCaml). `typify` splits
  integer/decimal via `Number.isInteger` semantics (`2.0` is an integer).
- **Nodes are mutable and reference-stable:** lists are `ArrayBuffer[Value]`,
  maps are `scala.collection.mutable.LinkedHashMap[String, Value]` (insertion
  order preserved; re-assigning an existing key keeps its position). The
  algorithm mutates them in place; never swap in an immutable collection.
- **`SKIP` / `DELETE`** are `VSentinel` values compared by tag.

## Injection state

`Inj` is a mutable class (the `Injection`). The public API accepts a loose
`InjDef` (the `Partial<Injection>` of the canonical) wrapped in the `InjArg`
ADT (`IInj | IDef | INone`), so `getpath` / `inject` / `transform` / `validate`
work both with a live `Inj` (recursion) and a caller-supplied options object.

## Naming

Public names are the canonical names, lower-smushed or camelCased so they
match case/underscore-insensitively (`getpath`, `ismap`, `re_find_all`,
`checkPlacement`, `injectorArgs`, `injectChild`). Everything lives in
`object voxgig.struct`.

## Gotchas

- **`clone` collides with `java.lang.Object#clone`** in code that doesn't live
  inside the `struct` object (e.g. the runner imports it as `sclone`). Inside
  the object the library's own `clone` shadows the inherited one.
- **`Group A` vs raw `lookup_`** — see above; re-check before touching any read
  path in validate / transform.
- Keep `make test` and `python3 ../tools/check_parity.py` green, and add no
  runtime dependencies. Change canonical (TS + corpus) first, then propagate.
