# Haskell port — comprehensive guide

This document covers the Haskell-specific details of `voxgig/struct`. For the
language-neutral concepts, tutorial and full reference, read the top-level
[`../DOCS.md`](../DOCS.md); for the user overview, [`README.md`](./README.md).
TypeScript is canonical and the shared `build/test` corpus is the contract.

## Installation

The library is two files (`src/VoxgigStruct.hs` and the in-tree regex engine
`src/Vregex.hs`) with no third-party dependencies — only the GHC boot
libraries. Add `src/` to your include path (`ghc -isrc`) and
`import VoxgigStruct`.

## Representation of data

| JSON-shape thing | Haskell representation                         |
|------------------|------------------------------------------------|
| object / map     | `VMap (IORef [(String, Value)])` (insertion order) |
| array / list     | `VList (IORef [Value])`                         |
| string           | `VStr String`                                  |
| number           | `VNum Double` (integers are whole `Double`s)   |
| boolean          | `VBool Bool`                                    |
| JSON `null`      | `VNull`                                         |
| undefined        | `VNoval`                                        |
| function         | `VFunc Injector`                               |
| SKIP / DELETE    | `VSentinel "skip"` / `VSentinel "delete"`      |

Nodes are **mutable and reference-stable** on purpose: `merge`, `walk`,
`inject`, `transform`, `validate` mutate nodes in place and depend on shared
references. Haskell has no mutable native collection, so a node holds an
`IORef` to its contents (the analog of OCaml's `ref` or Rust's `Rc<RefCell>`).
A consequence is that **the entire public API runs in `IO`** — every reader and
mutator returns `IO`. Build nodes with `jm` / `jt`, or by running the
`transform` / `inject` engines.

### `VNoval` vs `VNull`: undefined vs JSON null

Like the OCaml and Scala ports (and the canonical TypeScript), this port keeps
the canonical `undefined` and JSON `null` as **distinct constructors**
(`VNoval` / `VNull`). So it mirrors the canonical logic directly and does not
need the Group-A/B `null`-collapsing rules of the single-`null` ports
(Python / Clojure / Dart / Elixir). `getprop` / `getelem` / `haskey` collapse
*both* to the alt (their "no value" rule); the Group-B processors preserve
`VNull` literally; `lookup_` is the internal raw reader.

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
  `re_replace`, `re_test`, `re_escape`. Backed by the in-tree `Vregex`.
- **By-example engine:** `inject`, `transform`, `validate`, `select`, and the
  injector helpers `check_placement`, `injector_args`, `inject_child`.
- **Builders / markers:** `jm`, `jt`, `skip`, `delete`, the `t_*` type
  constants and `m_keypre` / `m_keypost` / `m_val`.

Optional arguments are explicit. `walk` takes `Maybe WalkFn` before/after and a
`Value` maxdepth: `walk before after maxdepth v` (a `WalkFn` is
`Value -> Value -> Value -> Value -> IO Value` = key/val/parent/path). The
many-arity helpers come in pairs, e.g. `getprop` / `getpropAlt`,
`getelem` / `getelemAlt`, `stringify` / `stringifyMax`, `merge` / `mergeD`,
`slice` / `sliceM`, `pathify` / `pathifyFull`. The injection-aware API takes an
`InjArg` (`INone` / `IDef InjDef` / `IInj Inj`).

## Examples

```haskell
import VoxgigStruct

demo :: IO ()
demo = do
  -- merge (later wins; the first node is modified in place)
  a <- jm [VStr "a", VNum 1]; b <- jm [VStr "b", VNum 2]; xs <- jt [a, b]
  putStrLn =<< stringify =<< merge xs            -- {a:1,b:2}

  -- transform: spec mirrors the desired output, backticks pull from data
  dat <- jm [VStr "name", VStr "alice"]
  idsp <- jm [VStr "id", VStr "`name`"]; spec <- jm [VStr "user", idsp]
  putStrLn =<< stringify =<< transform INone dat spec
```

## Testing

`make test` compiles `test/Runner.hs` and runs the entire shared corpus
(`../build/test/test.json`). The runner ships a tiny hand-written JSON reader
(no `aeson`) that builds the library's `IORef`-backed nodes directly — the same
representation the library operates on — and uses the same runner logic as
every other port. Keep it green, keep `python3 ../tools/check_parity.py` green,
and add no runtime dependencies.

## Implementation notes

- The injection state (`Inj`) is a record of `IORef`s (one per mutable field);
  a caller-supplied `injdef` is the plain `InjDef` record.
- `skip` / `delete` are `VSentinel` values compared by tag (`is_skip` /
  `is_delete`).
- Numbers follow JS formatting in `stringify` / `jsonify` (an integral `Double`
  prints without `.0`; otherwise the shortest round-tripping `%g` form, matching
  the canonical implementation).
- The only regex engine is the in-tree `Vregex` (a small backtracking matcher
  covering the RE2 subset the corpus uses for `$LIKE` and the `re_*` API).
- A single `dummyInj` placeholder (built with `unsafePerformIO`) backs the two
  corpus-unreached paths that need an `Inj` without one in hand
  (`getelem`'s function-alt, `$FORMAT`'s function-formatter).
