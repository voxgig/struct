# AGENTS.md — Elixir port of `voxgig/struct`

Read the repo-root [`../AGENTS.md`](../AGENTS.md) first. This file covers only
what is specific to the Elixir port. **TypeScript is canonical; the shared
`build/test/*.jsonic` corpus is the contract.** This port follows the
single-`nil` model of the Python / Clojure / Dart ports (Elixir has one `nil`),
not the distinct-`undefined`/`null` model of the OCaml / Scala ports.

## How to build / test / lint

```
cd elixir
make test    # elixir test/runner.exs  — runs build/test/test.json
make lint    # elixirc lib/voxgig_struct.ex  (a clean compile = pass)
```

Requires only Elixir / Erlang OTP. **Zero third-party runtime dependencies** —
the library uses only the standard library (ETS for the heap, `Regex`/`:re` for
the regex API). The test runner additionally ships a tiny hand-written JSON
parser (no `Jason`/`Poison`) so it, too, has no third-party deps.

## The value model

The canonical algorithm mutates nodes in place and relies on reference-stable
nodes. The BEAM has no mutable, reference-stable native collection, so nodes
live in a small **ETS-backed heap**:

- **maps → `{:vmap, id}`** — contents are an ordered list of `{key, value}`
  pairs (Elixir maps are unordered, so they can't be used directly);
  re-assigning an existing key keeps its position.
- **lists → `{:vlist, id}`** — contents are a plain list of items.
- **inject state → `{:vinj, id}`** — an atom-keyed field map.

The contents live in one lazily-created named public ETS table; a node tuple
holds only the id, so mutating the heap entry is observed through every holder
of the reference. `ismap`/`islist`/`isnode` pattern-match the tag; `isfunc`
tests `is_function`. **Always** build nodes with `jm` / `jt` (or the engines) —
never hand-assemble the tuples.

## `nil` is both `undefined` and JSON `null`

Like Python, Elixir has a single `nil`, so the canonical `undefined` (absent)
and JSON `null` both map to `nil`. The Group A/B rules
([`../design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)) recover the distinction:

- Group A readers (`getprop`, `getelem`, `haskey`, `isnode`, `isempty`) treat a
  stored `nil` as "no value".
- Group B processors (`setprop`, `clone`, `merge`, `walk`, `inject`,
  `transform`, `validate`, `select`) preserve `nil` literally; `lookup_` is
  the internal raw reader.

A `@noarg` atom sentinel (exposed publicly as `noarg/0`) distinguishes
"no argument supplied" from `nil` for `typify` (→ `T_noval` vs `T_null`),
`stringify` (→ `""` vs `"null"`), and `pathify` (→ `<unknown-path>` vs
`<unknown-path:null>`).

## Naming

Public names are the canonical lower-smushed / snake_cased names (`getpath`,
`ismap`, `re_find_all`, `check_placement`, `injector_args`, `inject_child`), so
the case/underscore-insensitive parity check matches them. Type constants and
mode/marker accessors are 0-arity functions (`t_string/0`, `m_val/0`,
`skip/0`, `delete/0`, `noarg/0`).

## Gotchas

- **`skip` / `delete`** are atoms (`:vox_skip` / `:vox_delete`) compared with
  `==` (`is_skip` / `is_delete`).
- The `Inj` injection state is a `{:vinj, _}` heap cell; an `injdef` passed by
  callers is just a `{:vmap, _}` node (functions can live in a map node), so
  there is no separate options type.
- **Numbers.** JSON integers parse to `integer`, decimals to `float`. `typify`
  treats a whole `float` as an integer (`Number.isInteger` semantics);
  `stringify`/`jsonify` follow JS formatting (an integral `float` prints
  without `.0`). Guard `Float.floor/1` against integer arguments.
- The heap is process-independent (a named public ETS table), so nodes are
  shared across the whole VM; this is intentional and matches the canonical
  shared-reference semantics.
- Keep `make test` and `python3 ../tools/check_parity.py` green, and add no
  runtime dependencies. Change canonical (TS + corpus) first, then propagate.
