# voxgig_struct — Elixir

An Elixir port of [`voxgig/struct`](../README.md): one small, fixed API for
manipulating JSON-shaped data — lookups, deep merge, by-example transform,
by-example validate, tree walk, path get/set, selection — that returns the
**same answer** as the canonical TypeScript implementation and every other
port. The behavioural contract is the shared JSON corpus in
[`build/test/`](../build/test); this port passes it in full.

## Status

Complete. Every canonical public function is implemented and the entire
shared corpus passes (`make test`). **Zero third-party dependencies** — only
Elixir / Erlang OTP (ETS and `Regex`/`:re`) is required.

## Requirements

- Elixir 1.14 or later (Erlang/OTP 24+).

## Use

```elixir
alias Voxgig.Struct, as: S

store = S.jm(["a", S.jm(["b", 2])])
S.getpath(store, "a.b")            # 2

S.stringify(S.transform(S.jm(["a", 1]), S.jm(["x", "`a`"])))  # "{x:1}"
```

`jm` / `jt` are the JSON-object / JSON-array builders (`jm` takes a flat
`[k1, v1, k2, v2, ...]` list; `jt` takes a list of items):

```elixir
S.jsonify(S.jm(["a", 1, "b", S.jt([2, 3])]))
```

### Data model

The canonical algorithm mutates nodes in place and relies on **reference-stable**
nodes (a node updated through one reference is seen through every other). The
BEAM has no mutable native collection, so this port keeps nodes in a small
**ETS-backed heap**: a node is a tagged reference — `{:vmap, id}` (object) or
`{:vlist, id}` (array) — whose contents live in the heap and are replaced on
mutation, so the reference stays stable. Build nodes with `jm` / `jt` (or the
`transform` / `inject` engines); never construct the tuples by hand.

- maps → `{:vmap, id}` (insertion-ordered key/value pairs),
- lists → `{:vlist, id}`,
- `nil` plays the role of both `undefined` and JSON `null` (the Group A/B
  rules recover the distinction — see
  [`../design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)).

## API

The public surface matches the canonical export list, in lower-smushed /
snake_cased names:

`clone delprop escre escurl filter flatten getdef getelem getpath getprop
haskey inject isempty isfunc iskey islist ismap isnode items join jsonify
keysof merge pad pathify select setpath setprop size slice strkey stringify
transform typify typename validate walk re_compile re_find re_find_all
re_replace re_test re_escape jm jt check_placement injector_args inject_child`

See [`DOCS.md`](./DOCS.md) for the full guide and
[the language-neutral docs](../DOCS.md) for concepts and examples.

## Develop

```
make test     # run the shared corpus
make lint     # compile the library (a clean compile = pass)
```

## License

MIT. See [`../LICENSE`](../LICENSE).
