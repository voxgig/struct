# AGENTS.md — OCaml port of `voxgig/struct`

Read the repo-root [`AGENTS.md`](../AGENTS.md) first. This file covers only
what is specific to the OCaml port. **TypeScript is canonical; the shared
`build/test/*.jsonic` corpus is the contract.** This port mirrors the
canonical TypeScript logic directly (not the Python port), because OCaml — like
TypeScript and Rust — keeps `undefined` and JSON `null` as distinct values.

## How to build / test / lint

```
cd ocaml
make test    # ocamlc compiles src + test, runs build/test/test.json
make lint    # type-checks the library (a clean compile = pass)
```

Requires only the OCaml compiler (`ocamlc`). **Zero third-party
dependencies** — no opam packages, no `Str`. The test runner has an in-tree
JSON reader, and regex is the in-tree `src/vregex.ml` engine.

## The value model

Everything is one variant type (`value`) so the functions are effectively
dynamic within it:

```
Noval | Null | Bool | Num of float | Str | List of value list ref
      | Map of omap | Func of injector | Sentinel of string
```

- **`Noval` is the TS `undefined`** (property absent); **`Null` is JSON null**.
  They are distinct — this is the canonical TS model. `is_nullish` covers both
  (JS `null == v`); `is_noval` is `undefined` only. Group A readers (`getprop`,
  `getelem`, `haskey`) return the default on either; Group B processors use the
  raw `lookup_` to preserve `Null`. **Getting `getprop` (Group A) vs `lookup_`
  (raw) right is the single most common source of port bugs** — e.g. validate's
  bad-key check and `transform_FORMAT`/`$REF` argument reads must use `lookup_`.
- **Numbers are a single `Num of float`** (like Rust). `typify` splits
  integer/decimal via `Number.isInteger` semantics (`2.0` is an integer).
- **Nodes are mutable and reference-stable:** lists are `value list ref`, maps
  are the in-tree ordered `omap` (insertion order preserved). The algorithm
  mutates them in place; never swap in an immutable structure.
- **`skip` / `delete`** are `Sentinel` values compared structurally by tag.

## Injection state

`inj` is a mutable record (the `Injection`). The public API accepts a loose
`injdef` record (the `Partial<Injection>` of the canonical) wrapped in the
`injarg` variant (`IInj | IDef | INone`), so `getpath` / `inject` / `transform`
/ `validate` work both with a live `inj` (recursion) and a caller-supplied
options record.

## Naming

Public names are the canonical names, lower-smushed or snake_cased so they
match case/underscore-insensitively (`getpath`, `ismap`, `re_find_all`,
`check_placement` ≡ `checkPlacement`, `injector_args` ≡ `injectorArgs`,
`inject_child` ≡ `injectChild`). Avoid the OCaml keyword `val` as an
identifier — local value parameters are named `v`.

## Gotchas

- **Comments cannot contain `*)`** — regex-bearing comments are reworded.
- **`Group A` vs raw `lookup_`** — see above; re-check before touching any
  read path in validate / transform.
- Keep `make test` and `python3 ../tools/check_parity.py` green, and add no
  runtime dependencies. Change canonical (TS + corpus) first, then propagate.
