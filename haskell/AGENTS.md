# AGENTS.md — Haskell port of `voxgig/struct`

Read the repo-root [`../AGENTS.md`](../AGENTS.md) first. This file covers only
what is specific to the Haskell port. **TypeScript is canonical; the shared
`build/test/*.jsonic` corpus is the contract.** This port follows the
distinct-`undefined`/`null` model of the OCaml / Scala ports (it has separate
`VNoval` / `VNull` constructors), not the single-`null` model of the
Python / Clojure / Dart / Elixir ports.

## How to build / test / lint

```
cd haskell
make test    # ghc … test/Runner.hs && runner  — runs build/test/test.json
make lint    # ghc -fno-code  (a clean type-check = pass)
```

Requires only GHC and its boot libraries (`base`, `array`). **Zero third-party
runtime dependencies** — no Cabal/Stack packages, no `aeson`, no `regex-*`. The
test runner ships a hand-written JSON reader; the library vendors a small
RE2-subset regex engine (`src/Vregex.hs`).

## Releasing to Hackage

The package is `voxgig-struct` (`voxgig-struct.cabal`); the version lives in
`VERSION` and is mirrored in the `.cabal` (the `publish` targets guard that the
two match). **Hackage uploads are permanent** — a version can be deprecated but
never changed or removed — so the workflow is candidate-first:

```
make publish-candidate   # changeable/removable candidate; verify the page + Haddock
make publish             # permanent upload + git tag haskell/vX.Y.Z
```

Both need `HACKAGE_TOKEN` (account → tokens); `publish` also needs a token to
push the tag. With the aql dry-run filler token in the env, both targets no-op
loudly instead of touching the network.

Dependency bounds follow PVP — **lower AND upper on every unique dependency**,
declared once (`base >=4.14 && <5`, `array >=0.5 && <0.6` in the `library`
stanza; there is no separate `test-suite` stanza to duplicate them into).
Re-run `cabal gen-bounds` if the dependency set ever changes.

## The value model

The canonical algorithm mutates nodes in place and relies on reference-stable
nodes. Haskell has no mutable native collection, so a node holds an `IORef`:

- **maps → `VMap (IORef [(String, Value)])`** — an ordered association list
  (insertion order; re-assigning an existing key keeps its position).
- **lists → `VList (IORef [Value])`**.

`ismap`/`islist`/`isnode` pattern-match the constructor; `isfunc` matches
`VFunc`. **The entire API runs in `IO`** because every read/mutate touches an
`IORef`. Always build nodes with `jm` / `jt` (or the engines) — never fabricate
the `IORef` by hand outside those.

## `VNoval` vs `VNull`

Distinct constructors, mirroring canonical TS (and OCaml / Scala):

- `VNoval` = canonical `undefined` (property absent).
- `VNull` = JSON `null`.

`getprop` / `getelem` / `haskey` / `isempty` / `isnode` treat *both* as "no
value" (the Group-A rule is automatic: they test `isNullish`). Group-B
processors (`setprop`, `clone`, `merge`, `walk`, `inject`, `transform`,
`validate`, `select`) preserve `VNull` literally; `lookup_` is the internal raw
reader. There is **no** NOARG sentinel — the distinct constructors already
carry the distinction (`typify VNoval` = `t_noval`, `stringify VNoval` = `""`,
`pathifyFull … absent=True` = `<unknown-path>`).

## Naming

Public names are the canonical lower-smushed / snake_cased names (`getpath`,
`ismap`, `re_find_all`, `check_placement`, `injector_args`, `inject_child`), so
the case/underscore-insensitive parity check matches them. The parity tool reads
top-level `name ::` type signatures (the `_HASKELL_DECL` extractor in
`tools/check_parity.py`), so **every public function needs a standalone type
signature**. Many functions come in arity pairs (`getprop`/`getpropAlt`,
`stringify`/`stringifyMax`, `merge`/`mergeD`, `slice`/`sliceM`,
`pathify`/`pathifyFull`).

## Gotchas

- **`skip` / `delete`** are `VSentinel "skip"` / `VSentinel "delete"`, compared
  by tag via `is_skip` / `is_delete`.
- **One-line `case … of … -> do …; _ -> …`** does not parse — the `_` arm is
  swallowed into the `do`. Use explicit braces `case x of { A -> do { … }; _ -> … }`
  or multiple lines.
- **`filter`** shadows `Prelude.filter` (it is a canonical name). The library
  does `import Prelude hiding (filter)` and uses `L.filter` (`qualified Data.List
  as L`) internally; the runner calls the library one as `VoxgigStruct.filter`.
- **Numbers** are `VNum Double`. `typify` treats a whole `Double` as an integer
  (`Number.isInteger` semantics); `numToString` prints integral values without
  `.0` and otherwise the shortest round-tripping `%g`.
- `dummyInj` (an `unsafePerformIO` singleton) only backs corpus-unreached
  `Inj`-needing paths; do not rely on its mutable state.
- Keep `make test` and `python3 ../tools/check_parity.py` green, and add no
  runtime dependencies. Change canonical (TS + corpus) first, then propagate.
