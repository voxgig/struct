# OCaml port — comprehensive guide

This document covers the OCaml-specific details of `voxgig/struct`. For the
language-neutral concepts, tutorial and full reference, read the top-level
[`DOCS.md`](../DOCS.md); for the user overview, [`README.md`](./README.md).
TypeScript is canonical and the shared `build/test` corpus is the contract.

## Installation

The whole library is two source files under `src/` and needs nothing but the
OCaml compiler. Compile it into your project (`ocamlc -I src src/vregex.ml
src/voxgig_struct.ml ...`) and `open Voxgig_struct`.

## Representation of data

| JSON-shape thing        | OCaml representation               |
|-------------------------|------------------------------------|
| object / map            | `Map of omap` (insertion-ordered)  |
| array / list            | `List of value list ref`           |
| string                  | `Str of string`                     |
| number (int or decimal) | `Num of float`                      |
| boolean                 | `Bool of bool`                      |
| JSON `null`             | `Null`                              |
| undefined / absent      | `Noval`                             |
| function (commands)     | `Func of injector`                  |

Nodes are **mutable and reference-stable** on purpose: `merge`, `walk`,
`inject`, `transform`, `validate` mutate nodes in place and depend on shared
references. Build nodes directly (or with `jm` / `jt`); the in-tree `omap`
preserves insertion order.

### `Noval` vs `Null`

Unlike the single-`nil` ports (Python, Clojure, Lua), OCaml keeps the two
canonical concepts apart, exactly like TypeScript and Rust:

- `Noval` — the TS `undefined`: a property is absent. **Not** a scalar.
- `Null` — JSON `null`: a real value.

The Group A / Group B rules ([`design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md))
decide which one a slot collapses to:

- **Group A** readers — `getprop`, `getelem`, `haskey` — treat a stored `Null`
  as "no value" (they return the default).
- **Group B** processors — `setprop`, `clone`, `merge`, `walk`, `inject`,
  `transform`, `validate`, `select` — preserve `Null` literally. The internal
  `lookup_` is the raw reader they use when null must survive.

```ocaml
typify Noval            (* T_noval *)
typify Null             (* T_scalar lor T_null *)
stringify Noval         (* "" *)
stringify Null          (* "null" *)
```

## The public API

Names are the canonical names, lower-smushed or snake_cased:

- **Lookups / paths:** `getpath`, `setpath`, `getprop`, `setprop`, `getelem`,
  `delprop`, `haskey`, `keysof`, `items`.
- **Predicates / kinds:** `isnode`, `ismap`, `islist`, `iskey`, `isfunc`,
  `isempty`, `typify`, `typename`.
- **Values:** `clone`, `merge`, `walk`, `size`, `slice`, `pad`, `flatten`,
  `filter`, `getdef`, `strkey`.
- **Strings / formatting:** `stringify`, `jsonify`, `pathify`, `join`,
  `escre`, `escurl`.
- **Regex (RE2-subset uniform API):** `re_compile`, `re_find`, `re_find_all`,
  `re_replace`, `re_test`, `re_escape`. Backed by the in-tree `Vregex` engine.
- **By-example engine:** `inject`, `transform`, `validate`, `select`, and the
  injector helpers `check_placement`, `injector_args`, `inject_child`.
- **Builders / markers:** `jm`, `jt`, `skip`, `delete`, the `t_*` type
  constants and `m_keypre` / `m_keypost` / `m_val`.

Many functions take OCaml optional arguments where the canonical has optional
parameters, e.g. `getprop ?alt v key`, `slice ?start ?stop ?mutate v`,
`stringify ?maxlen ?pretty v`, `merge ?maxdepth objs`.

## Examples

```ocaml
open Voxgig_struct

(* merge: later wins; the first node is modified in place *)
merge (jt [jm [Str "a"; Num 1.0]; jm [Str "b"; Num 2.0]])   (* {a:1,b:2} *)

(* transform: spec mirrors the output; backticks pull from the data *)
transform (jm [Str "name"; Str "alice"])
          (jm [Str "user"; jm [Str "id"; Str "`name`"]])     (* {user:{id:alice}} *)

(* validate: plain values are typed defaults; `$STRING` etc. are commands *)
validate (jm [Str "a"; Str "x"]) (jm [Str "a"; Str "`$STRING`"])  (* {a:x} *)

(* select: MongoDB-style query over children *)
select (jt [jm [Str "a"; Num 1.0]; jm [Str "a"; Num 2.0]])
       (jm [Str "a"; jm [Str "`$GT`"; Num 1.0]])             (* [{$KEY:1,a:2}] *)
```

## Testing

`make test` compiles `src/` + `test/runner.ml` with `ocamlc` and runs the
entire shared corpus (`../build/test/test.json`) through the port, using an
in-tree JSON reader and the same runner logic as every other port. Keep it
green, keep `python3 ../tools/check_parity.py` green, and add no runtime
dependencies.

## Implementation notes

- The injection state (`inj`) is a mutable record; callers pass a loose
  `injdef` record via the `injarg` variant, so it is never confused with data.
- `skip` / `delete` are `Sentinel` markers.
- Numbers follow JS formatting in `stringify` / `jsonify` (an integral float
  prints without a trailing `.0`); `num_to_string` finds the shortest
  round-tripping representation.
- `src/vregex.ml` is a small backtracking regex engine covering the RE2 subset
  the corpus uses (classes, `\d \w \s \b`, `{n,m}`, groups, alternation, lazy
  quantifiers) — enough for `$LIKE` and the `re_*` API, with no dependency.
