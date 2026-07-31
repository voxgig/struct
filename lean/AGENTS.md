# AGENTS.md — Lean port of `voxgig/struct`

Read the repo-root [`AGENTS.md`](../AGENTS.md) first. This file covers only
what is specific to the Lean port. **TypeScript is canonical; the shared
`build/test/*.aontu` corpus is the contract.** This port mirrors the
canonical TypeScript logic directly (via the OCaml port's structure),
because Lean — like TypeScript, OCaml and Haskell — keeps `undefined` and
JSON `null` as distinct values.

## How to build / test / lint

```
cd lean
make test    # lake build + runs build/test/test.json (expect 1360/1360)
make lint    # type-checks the library (a clean, warnings-free compile = pass)
```

Requires only the Lean 4 toolchain via elan (`lean-toolchain` pins the
version; `lake` auto-fetches it). **Zero third-party dependencies** — no
lake `require` lines, ever. The test runner has an in-tree JSON reader, and
regex is the in-tree `src/Vregex.lean` engine (captures tracked; the corpus
`regex` group holds it to the Go-stdlib floor of `design/REGEX_API.md`).

## The value model

`Value` is one small inductive; nodes and functions are *handles*:

```
noval | null | bool | num (Float) | str | list (heap id) | map (heap id)
      | func (registry id) | sentinel (tag)
```

- **`noval` is the TS `undefined`** (property absent); **`null` is JSON
  null.** They are distinct — this is the canonical TS model. `isNullish`
  covers both; `isNoval` is `undefined` only. Group A readers (`getprop`,
  `getelem`, `haskey`) return the default on either; Group B processors use
  the raw `lookupRaw` to preserve `null`. **Getting `getprop` (Group A) vs
  `lookupRaw` (raw) right is the single most common source of port bugs.**
- **Nodes are mutable and reference-stable** through the heap: Lean's strict
  positivity rules forbid `IO.Ref` fields inside `Value`, so lists/maps are
  indices into `Ctx.valueHeap` (the Elixir port uses the same heap design
  with ETS). Never replace this with an immutable structure — the algorithms
  mutate shared nodes in place.
- **Numbers are a single `num (Float)`** (like OCaml/Rust). JS-style string
  conversion is hand-rolled (`numToString`, shortest round-trip via exact
  `Nat` arithmetic) because Lean's `Float.toString` prints `1.100000`.
- **`SKIP` / `DELETE`** are `sentinel` values compared by tag.

## The `SIO` monad (important)

Everything runs in `SIO := ReaderT Ctx IO`; `mkCtx : IO Ctx` builds the
mutable state (node heap, function/modify registries, injection arena,
dummy inj). Do **not** move the heaps into module-`initialize` globals: the
Lean runtime marks values stored in persistent global `IO.Ref`s as shared,
so every array update copies the whole heap (this was measured — a 100×+
slowdown). Runtime-created refs update in place.

Registered injector/modify functions are stored as plain `IO` closures with
the ctx captured at registration (`registerFunc`), which keeps `Ctx`
non-recursive.

## Injection state

`InjData` is the mutable `Injection` record, held in the `Ctx.injHeap`
arena and addressed by `InjId` (field mutation via `modInj`). The public
API accepts `InjArg` (`.iinj | .idef | .inone`); `InjDef` is the loose
`Partial<Injection>` record. The field for canonical `meta` is named
**`imeta`** (`meta` is a Lean keyword).

## Naming

Public names are the canonical names, lower-smushed or camelCased so they
match the parity check case/underscore-insensitively (`getpath`, `ismap`,
`reFindAll` ≡ `re_find_all`, `checkPlacement`, `injectorArgs`,
`injectChild`). Internal helpers deliberately avoid canonical names
(`makeChildInj` is the internal child-state builder; `injectChild` is the
canonical public helper).

## Gotchas

- **Lean keywords** bit this port before: `meta`, `prefix`, `end`, `open`
  cannot be identifiers — rename (`imeta`, `pfx`, …).
- **`String.take`/`String.drop` return `String.Slice`** on the pinned
  toolchain — use the in-file `strTake`/`strDrop` helpers.
- **Statement-`match` for `mut`:** a parenthesised `(match … )` is a term —
  `let mut` variables cannot be mutated inside it. Use an unparenthesised
  statement-level `match`.
- **Multi-line record updates** need `{ x with` at the end of the first
  line, not `{ x with a := 1,` continued.
- Keep `make test` and `python3 ../tools/check_parity.py` green, and add no
  runtime dependencies. Change canonical (TS + corpus) first, then propagate.
