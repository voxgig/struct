# Cross-Port Implementation Notes

> Cross-cutting quirks, edge cases, and follow-ups that don't fit
> [`README.md`](../README.md) (user-facing), [`REPORT.md`](REPORT.md)
> (per-port parity matrix), [`UNDEF.md`](UNDEF.md) /
> [`UNDEF_SPEC.md`](UNDEF_SPEC.md) (absent-vs-null), or
> [`REGEX.md`](REGEX.md) / [`REGEX_API.md`](REGEX_API.md) (regex
> dialect). Per-port adaptations that are still relevant live in each
> port's own `README.md`; this file collects the leftovers.


## Open follow-ups

- **`getpath` trailing-dot ascending path is undocumented in the
  canonical TypeScript.** A path ending in one or more `.` (e.g.
  `.foo..`) ascends to an ancestor data parent; the implementation is
  in [`typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts)
  (`for (let pI = 0; …; pI++) { … if (S_MT === part) { let ascends =
  0; while …` block), but there's no docstring or test naming the
  feature. The Perl, Rust, and other ports replicate the behaviour
  faithfully; the gap is purely in the TS docstring.

- **Edge cases no corpus entry reaches, where ports still differ.** List
  keys, a numeric `getpath` part, a null written back into a list, a `2.0`
  count and one `$CHILD` error per failure are pinned and agree in every
  port. What is left:
  - A decimal number key on a map: the canonical `setprop` and `getprop`
    use `String(n)` (`1.5` is `"1.5"`), but `delprop` floors it through
    `strkey` (`"1"`). The ports split between the two.
  - Number spelling at the edges: a map key or path part built from an
    exponent-form or non-finite number follows each host's float formatter
    (`1.5e-07` against JavaScript's `1.5e-7`; OCaml prints `inf`).
  - `$COPY` of a null in the single-null ports (Elixir and boru at least):
    `transform([null,1], ['$COPY','$COPY'])` loses the null that TypeScript
    keeps.
  - Go's `select` drops a child that lacks a key checked with `$NIL` or
    `$ANY`, and a checker injected into part of a string over a null gives
    `x` where TypeScript gives `xnull`.
  - Ruby's `getpath(store, ['x', ''])` without injection options returns the
    store; Haskell's `jm('', v)` drops the empty key; Swift's `setpath`
    returns nothing for a numeric path; Zig's `delprop` panics on a NaN map
    key; PHP answers `[]` for some empty-map data where TypeScript answers
    `{}`.


## Documented JS-fidelity gaps

These behaviours are JS-specific and not exercised by the shared
corpus, so non-JS ports replicate them only approximately.

- **Number → string at extreme magnitudes.** JavaScript's
  `JSON.stringify`/`String(n)` switches to exponent notation around
  `|n| ≥ 1e21` (`String(1e21) === "1e+21"`). Most ports use their
  language's default float formatter, which keeps the full digit
  expansion (e.g. Rust's `{}` formatter emits
  `"1000000000000000000000"`). The corpus doesn't reach these
  magnitudes.

- **Integer-keyed object stringification order.** When `JSON.stringify`
  serialises a JS object, integer-looking keys come first in numeric
  order, then string keys in insertion order. Ports that use a
  language-native ordered map (Perl `Tie::IxHash`, Rust `indexmap`,
  Python 3.7+ dict, Lua `OrderedMap`, …) preserve insertion order
  uniformly. Order-independent equality in the test runners hides the
  difference; the corpus has no test that would distinguish them.

- **`T_symbol` / `T_instance`.** These bit-flags exist in every port
  for parity, but `typify` only ever returns them on JS/TS where
  `Symbol` and class instances are first-class values. Other ports
  have no JSON-shaped analogue and never produce those tags. The
  `minor-edge-typify` corpus assertions that mention them are
  effectively JS-only.


## Function-value signature variants

Several injectors and helpers accept a callable value. The canonical
TypeScript uses dynamic argument lists; ports with static typing
collapse them to a single signature. The corpus is JSON-only so it
can't exercise these paths — every port covers them with
language-specific unit tests instead.

- **`$APPLY` user callback.** TS passes `(value, store, inj)` to the
  apply function. Ports with one signature receive the same positional
  arguments under that signature.

- **`$FORMAT` user formatter.** TS passes `(key, value, parent, path)`
  to formatters registered in `FORMATTER`. Ports with one signature
  see the resolved value as `val`, the injection as `inj`; `key` /
  `parent` / `path` are reachable through `inj`.

- **`getelem(list, key, alt)` with a callable `alt`.** TS invokes the
  callable when the element is absent. `getprop` and `getdef` do
  **not** invoke a callable default — neither does the canonical.

If you're adding a new injector that takes a user callback, mirror the
existing patterns and add a unit test in the port-specific test suite
(not in the JSON corpus).

## boru port quirks

The boru port is written in the boru language itself (not Go) and does not
wrap the engine's native `aql:struct-util` module. Its quirks are
engine-driven; the full list lives in `boru/AGENTS.md` ("Engine caveats").
The load-bearing ones:

- **Function carriers.** A bare Function-valued name auto-dispatches when
  stepped, so function values travel in carriers: an fn box
  `` {"`$FN`": f/r} `` where the canonical code `isfunc`-tests the value
  (store commands, `handler`, `modify`, formatters), or a one-element
  list `[f/r]` for pure callback slots. `isfunc` recognises the box.
- **bind-then-return everywhere.** A fn body that ends in a bare call
  loses a `none` result at the return boundary in deep `apply` chains
  (and a paired `drop` then corrupts an ancestor frame), so every body
  ends `def r (...)` `r`.
- **No `and`/`or` short-circuit** and **no variadics** (`jm`/`jt` take
  one list argument; canonical optional parameters are explicit `NOARG`
  sentinel arguments).
- **Interpreter-pinned tests, checker-clean source.** The corpus runs
  `boru run -no-check -no-compile` for deterministic runs, but the module
  now also passes `boru check` with 0 errors and the full corpus passes
  under the default compiled mode. `make lint` runs the checker plus a
  module-load smoke. Reaching this took engine fixes in boru (store-shaped
  flex-carrier checker nil-derefs, guard-fact/narrowing precision,
  forward-reference placeholders, multi-result `pop` poly, dynamic-pattern
  `mini re` compilation); an older `boru` binary crashes or reports phantom
  errors on it.
