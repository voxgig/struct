# @voxgig/struct — OCaml

An OCaml port of [`voxgig/struct`](../README.md): one small, fixed API for
manipulating JSON-shaped data — lookups, deep merge, by-example transform,
by-example validate, tree walk, path get/set, selection — that returns the
**same answer** as the canonical TypeScript implementation and every other
port. The behavioural contract is the shared JSON corpus in
[`build/test/`](../build/test); this port passes it in full.

## Status

Complete. Every canonical public function is implemented and the entire
shared corpus passes (`make test`), on
[voxgig/omni](https://github.com/voxgig/omni) — the shared test runner.
**Zero third-party dependencies** — only the OCaml compiler is required, and
omni is a test-time source file, never part of the library.

## Requirements

- The OCaml compiler (`ocamlc`), version 4.14 or later.
- For the tests only: a [voxgig/omni](https://github.com/voxgig/omni)
  checkout. The Makefile finds it via `$OMNI_HOME` or beside this
  repository.

## Use

The library lives in the `Voxgig_struct` module:

```ocaml
open Voxgig_struct

let store =
  Map { entries = [("a", Map { entries = [("b", Num 2.0)] })] }

let () =
  print_endline (stringify (getpath store (Str "a.b")));   (* 2 *)
  print_endline (stringify (transform
    (Map { entries = [("a", Num 1.0)] })
    (Map { entries = [("x", Str "`a`")] })))                (* {x:1} *)
```

`jm` / `jt` are convenient JSON-object / JSON-array builders:

```ocaml
jsonify (jm [Str "a"; Num 1.0; Str "b"; jt [Num 2.0; Num 3.0]])
```

### Data model

A single `value` variant represents JSON-shaped data:

```
Noval | Null | Bool of bool | Num of float | Str of string
      | List of value list ref | Map of omap | Func of injector
      | Sentinel of string
```

`Noval` is the canonical `undefined` (absent); `Null` is JSON null — distinct,
exactly as in the canonical TypeScript. Nodes (`List` / `Map`) are mutable and
reference-stable, so the library's in-place algorithms behave identically to
the reference implementation. See [`DOCS.md`](./DOCS.md) and
[the language-neutral docs](../DOCS.md).

## API

The public surface matches the canonical export list (lower-smushed /
snake_cased): `clone delprop escre escurl filter flatten getdef getelem
getpath getprop haskey inject isempty isfunc iskey islist ismap isnode items
join jsonify keysof merge pad pathify select setpath setprop size slice strkey
stringify transform typify typename validate walk re_compile re_find
re_find_all re_replace re_test re_escape jm jt check_placement injector_args
inject_child`.

## Develop

```
make test     # run the shared corpus on voxgig/omni (needs $OMNI_HOME)
make lint     # type-check the library (no omni)
make inspect  # compiler version
```

## License

MIT. See [`../LICENSE`](../LICENSE).
