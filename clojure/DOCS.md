# Clojure port — comprehensive guide

This document covers the Clojure-specific details of `voxgig/struct`. For the
language-neutral concepts, tutorial and full reference, read the top-level
[`DOCS.md`](../DOCS.md); for the user overview, [`README.md`](./README.md).
TypeScript is canonical and the shared `build/test` corpus is the contract.

## Installation

Add the Clojure source to your project (Clojars coordinates are published per
release) or depend on this directory directly via a local `deps.edn` `:paths`
entry. Then `(require '[voxgig.struct :as s])`.

Requirements: a JDK and the Clojure CLI. No third-party runtime dependencies.

## Representation of data

| JSON-shape thing        | Clojure representation                       |
|-------------------------|----------------------------------------------|
| object / map            | `java.util.LinkedHashMap` (insertion order)  |
| array / list            | `java.util.ArrayList`                         |
| string                  | `java.lang.String`                            |
| integer                 | `java.lang.Long`                              |
| decimal                 | `java.lang.Double`                            |
| boolean                 | `java.lang.Boolean`                           |
| JSON `null` / undefined | `nil`                                         |
| function (commands)     | a Clojure fn (`fn?`)                          |

Nodes are **mutable and reference-stable** on purpose: the canonical
algorithms (`merge`, `walk`, `inject`, `transform`, `validate`) mutate nodes
in place and depend on shared references. Build nodes with `LinkedHashMap` /
`ArrayList` (or the `jm` / `jt` helpers); do not hand the library a persistent
Clojure map or vector as a node.

### `nil`: undefined vs JSON null

Clojure has a single `nil`, used for both the canonical `undefined` and JSON
`null`. The library follows the Group A / Group B rules
([`design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)):

- **Group A** readers — `getprop`, `getelem`, `haskey`, `isnode`, `isempty` —
  treat a stored `nil` as "no value" (it yields the default / `false`).
- **Group B** processors — `setprop`, `clone`, `merge`, `walk`, `inject`,
  `transform`, `validate`, `select` — preserve `nil` literally.

Where a function must tell "no argument" from an explicit `nil`, pass the
public `NOARG` sentinel (this mirrors the absent/undefined case):

```clojure
(s/typify)            ;=> T_noval     (no argument = undefined)
(s/typify nil)        ;=> T_scalar|T_null
(s/stringify)         ;=> ""          (undefined)
(s/stringify nil)     ;=> "null"      (JSON null)
(s/pathify s/NOARG)   ;=> "<unknown-path>"
```

## The public API

Names are lower-smushed, identical to the canonical export list:

- **Lookups / paths:** `getpath`, `setpath`, `getprop`, `setprop`, `getelem`,
  `delprop`, `haskey`, `keysof`, `items`.
- **Predicates / kinds:** `isnode`, `ismap`, `islist`, `iskey`, `isfunc`,
  `isempty`, `typify`, `typename`.
- **Values:** `clone`, `merge`, `walk`, `size`, `slice`, `pad`, `flatten`,
  `filter`, `getdef`, `strkey`.
- **Strings / formatting:** `stringify`, `jsonify`, `pathify`, `join`,
  `escre`, `escurl`.
- **Regex (RE2-subset uniform API):** `re_compile`, `re_find`, `re_find_all`,
  `re_replace`, `re_test`, `re_escape`.
- **By-example engine:** `inject`, `transform`, `validate`, `select`, plus the
  injector helpers `checkPlacement`, `injectorArgs`, `injectChild`.
- **Builders / markers:** `jm`, `jt`, `SKIP`, `DELETE`, and the `T_*` /
  `M_*` constants.

`struct-utility` returns a map of every public function, mirroring the
`StructUtility` container in the other ports.

## Examples

```clojure
(require '[voxgig.struct :as s])

;; merge (later wins; the first node is modified in place)
(s/merge (s/jt (s/jm "a" 1) (s/jm "b" 2)))         ;=> {a 1, b 2}

;; transform: spec mirrors the desired output, backticks pull from data
(s/transform (s/jm "name" "alice")
             (s/jm "user" (s/jm "id" "`name`")))   ;=> {user {id alice}}

;; validate: plain values are typed defaults; `$STRING` etc. are commands
(s/validate (s/jm "a" "x") (s/jm "a" "`$STRING`")) ;=> {a x}

;; select: MongoDB-style query over children
(s/select (s/jt (s/jm "a" 1) (s/jm "a" 2))
          (s/jm "a" (s/jm "`$GT`" 1)))             ;=> ({a 2, $KEY 1})
```

## Testing

`make test` runs the entire shared corpus (`../build/test/test.json`) through
the port via an in-tree JSON reader and the same runner logic as every other
port. Keep it green, keep `python3 ../tools/check_parity.py` green, and add no
runtime dependencies.

## Implementation notes

- The injection state is a distinct `deftype Inj` (over a mutable `HashMap`)
  so it is never confused with a data map.
- `SKIP` / `DELETE` are identity markers — compared with `identical?`.
- Numbers follow JS formatting in `stringify` / `jsonify` (an integral
  `Double` prints without a trailing `.0`).
- The `voxgig.struct` namespace `:refer-clojure :exclude`s `merge`, `filter`,
  `flatten` and `replace` to reuse those canonical names.
