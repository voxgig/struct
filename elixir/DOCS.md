# Elixir port — comprehensive guide

This document covers the Elixir-specific details of `voxgig/struct`. For the
language-neutral concepts, tutorial and full reference, read the top-level
[`../DOCS.md`](../DOCS.md); for the user overview, [`README.md`](./README.md).
TypeScript is canonical and the shared `build/test` corpus is the contract.

## Installation

The whole library is one file (`lib/voxgig_struct.ex`) with no third-party
dependencies. Drop it into your project (or depend on the published Hex
package) and `alias Voxgig.Struct, as: S`.

## Representation of data

| JSON-shape thing        | Elixir representation                       |
|-------------------------|---------------------------------------------|
| object / map            | `{:vmap, id}` heap node (insertion order)   |
| array / list            | `{:vlist, id}` heap node                     |
| string                  | `binary` (`String`)                          |
| integer                 | `integer`                                    |
| decimal                 | `float`                                      |
| boolean                 | `boolean`                                     |
| JSON `null` / undefined | `nil`                                        |
| function (commands)     | a 4-arity (or 0-arity) anonymous function    |

Nodes are **mutable and reference-stable** on purpose: `merge`, `walk`,
`inject`, `transform`, `validate` mutate nodes in place and depend on shared
references. The BEAM has no mutable native collection, so the port keeps node
contents in a small **ETS-backed heap** (ETS is OTP stdlib, like the JVM heap
the Clojure port uses or Rust's `Rc<RefCell>`). A node is a tagged reference;
the contents in the heap table are replaced on mutation while the reference
stays stable, so every holder observes the update.

Build nodes with the public `jm` (object) and `jt` (array) constructors, or by
running the `transform` / `inject` engines — never assemble the `{:vmap, _}` /
`{:vlist, _}` tuples by hand.

### `nil`: undefined vs JSON null

Elixir has a single `nil`, used for both the canonical `undefined` and JSON
`null`. The library follows the Group A / Group B rules
([`../design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)):

- **Group A** readers — `getprop`, `getelem`, `haskey`, `isnode`, `isempty` —
  treat a stored `nil` as "no value".
- **Group B** processors — `setprop`, `clone`, `merge`, `walk`, `inject`,
  `transform`, `validate`, `select` — preserve `nil` literally.

Where a function must tell "no argument" from an explicit `nil`, pass the
public `noarg/0` sentinel:

```elixir
S.typify()              # T_noval     (no argument = undefined)
S.typify(nil)           # T_scalar | T_null
S.stringify()           # ""          (undefined)
S.stringify(nil)        # "null"      (JSON null)
S.pathify(S.noarg())    # "<unknown-path>"
```

## The public API

Names are lower-smushed / snake_cased, identical (case/underscore-insensitively)
to the canonical export list:

- **Lookups / paths:** `getpath`, `setpath`, `getprop`, `setprop`, `getelem`,
  `delprop`, `haskey`, `keysof`, `items`.
- **Predicates / kinds:** `isnode`, `ismap`, `islist`, `iskey`, `isfunc`,
  `isempty`, `typify`, `typename`.
- **Values:** `clone`, `merge`, `walk`, `size`, `slice`, `pad`, `flatten`,
  `filter`, `getdef`, `strkey`.
- **Strings / formatting:** `stringify`, `jsonify`, `pathify`, `join`,
  `escre`, `escurl`.
- **Regex (RE2-subset uniform API):** `re_compile`, `re_find`, `re_find_all`,
  `re_replace`, `re_test`, `re_escape`. Backed by the core `Regex`/`:re`.
- **By-example engine:** `inject`, `transform`, `validate`, `select`, and the
  injector helpers `check_placement`, `injector_args`, `inject_child`.
- **Builders / markers:** `jm`, `jt`, `skip/0`, `delete/0`, `noarg/0`, the
  `t_*` type constants and `m_keypre` / `m_keypost` / `m_val`.

`walk` takes a keyword list of options (`before:` / `after:` / `maxdepth:`);
most other optional arguments are positional, e.g. `getprop(val, key, alt \\ nil)`,
`slice(val, start \\ nil, stop \\ nil, mutate \\ false)`,
`stringify(val \\ noarg, maxlen \\ nil, pretty \\ nil)`,
`merge(objs, maxdepth \\ nil)`. Walk callbacks are `fn key, val, parent, path -> val end`.

## Examples

```elixir
alias Voxgig.Struct, as: S

# merge (later wins; the first node is modified in place)
S.merge(S.jt([S.jm(["a", 1]), S.jm(["b", 2])]))           # {a:1, b:2}

# transform: spec mirrors the desired output, backticks pull from data
S.transform(S.jm(["name", "alice"]), S.jm(["user", S.jm(["id", "`name`"])]))

# validate: plain values are typed defaults; `$STRING` etc. are commands
S.validate(S.jm(["a", "x"]), S.jm(["a", "`$STRING`"]))    # {a:x}

# select: MongoDB-style query over children
S.select(S.jt([S.jm(["a", 1]), S.jm(["a", 2])]), S.jm(["a", S.jm(["`$GT`", 1])]))
```

## Testing

`make test` runs the entire shared corpus (`../build/test/test.json`) through
the port via `elixir test/runner.exs`. The runner ships a tiny JSON parser that
reads the corpus straight into heap nodes (via the public `jm` / `jt`
constructors) — the same native types the library operates on — and uses the
same runner logic as every other port. Keep it green, keep
`python3 ../tools/check_parity.py` green, and add no runtime dependencies.

## Implementation notes

- The injection state (`Inj`) is a heap cell (`{:vinj, id}`) with atom-keyed
  fields; a caller-supplied `injdef` is just a `{:vmap, _}` node (functions can
  live in a map node).
- `skip/0` / `delete/0` are atom sentinels compared with `==` (`is_skip` /
  `is_delete`).
- Numbers follow JS formatting in `stringify` / `jsonify` (an integral `float`
  prints without a trailing `.0`; `:erlang.float_to_binary(n, [:short])` gives
  the shortest round-tripping form otherwise).
- The only regex engine is the core `Regex` (`:re`), which covers the RE2
  subset the corpus uses for `$LIKE` and the `re_*` API.
- The heap is a single named public ETS table created lazily; node ids come
  from `:erlang.unique_integer([:positive, :monotonic])`.
