# Cross-Port Implementation Notes

> Cross-cutting quirks, edge cases, and follow-ups that don't fit
> [`README.md`](./README.md) (user-facing), [`REPORT.md`](./REPORT.md)
> (per-port parity matrix), [`UNDEF.md`](./UNDEF.md) /
> [`UNDEF_SPEC.md`](./UNDEF_SPEC.md) (absent-vs-null), or
> [`REGEX.md`](./REGEX.md) / [`REGEX_API.md`](./REGEX_API.md) (regex
> dialect). Per-port adaptations that are still relevant live in each
> port's own `README.md`; this file collects the leftovers.


## Open follow-ups

- **`getpath` trailing-dot ascending path is undocumented in the
  canonical TypeScript.** A path ending in one or more `.` (e.g.
  `.foo..`) ascends to an ancestor data parent; the implementation is
  in [`typescript/src/StructUtility.ts`](./typescript/src/StructUtility.ts)
  (`for (let pI = 0; …; pI++) { … if (S_MT === part) { let ascends =
  0; while …` block), but there's no docstring or test naming the
  feature. The Perl, Rust, and other ports replicate the behaviour
  faithfully; the gap is purely in the TS docstring.


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
