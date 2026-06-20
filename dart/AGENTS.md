# AGENTS.md — Dart port of `voxgig/struct`

Read the repo-root [`../AGENTS.md`](../AGENTS.md) first. This file covers only
what is specific to the Dart port. **TypeScript is canonical; the shared
`build/test/*.jsonic` corpus is the contract.** This port follows the
single-`null` model of the Python / Clojure / Lua ports (Dart has one `null`),
not the distinct-`undefined`/`null` model of the OCaml / Scala ports.

## How to build / test / lint

```
cd dart
make test    # dart run test/runner.dart  — runs build/test/test.json
make lint    # dart analyze  (a clean analysis = pass)
```

Requires only the Dart SDK. **Zero third-party runtime dependencies** — the
library uses only `dart:core`; the test runner additionally uses the SDK's
`dart:convert` (to read the corpus) and `dart:io` (to read the file).

## The value model

Nodes are **native Dart collections**, which are mutable and reference-stable
exactly as the algorithm needs:

- **maps → `Map<String, dynamic>`** — Dart's default `{}` is a `LinkedHashMap`
  (insertion-ordered; re-assigning an existing key keeps its position).
- **lists → growable `List<dynamic>`**.

`ismap`/`islist`/`isnode` test `is Map` / `is List`; `isfunc` tests
`is Function`. All node-creating code builds `<String, dynamic>{}` /
`<dynamic>[]`. **Never** hand a node an unmodifiable/fixed-length list.

## `null` is both `undefined` and JSON `null`

Like Python, Dart has a single `null`, so the canonical `undefined` (absent)
and JSON `null` both map to `null`. The Group A/B rules
([`../design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)) recover the distinction:

- Group A readers (`getprop`, `getelem`, `haskey`, `isnode`, `isempty`) treat a
  stored `null` as "no value".
- Group B processors (`setprop`, `clone`, `merge`, `walk`, `inject`,
  `transform`, `validate`, `select`) preserve `null` literally; `_lookup` is
  the internal raw reader.

A private `_noarg` sentinel (exposed publicly as `pathifyNoArg`) distinguishes
"no argument supplied" from `null` for `typify` (→ `T_noval` vs `T_null`),
`stringify` (→ `""` vs `"null"`), and `pathify` (→ `<unknown-path>` vs
`<unknown-path:null>`).

## Naming

Public names are the canonical lower-smushed / camelCased names (`getpath`,
`ismap`, `re_find_all`, `checkPlacement`, `injectorArgs`, `injectChild`), so the
case/underscore-insensitive parity check matches them. (A leading underscore is
*private* in Dart, so canonical names never start with `_`.)

## Gotchas

- **`SKIP` / `DELETE`** are `_Sentinel` instances compared with `identical`
  (`isSkip` / `isDelete`).
- The `Inj` injection state is a plain class; an `injdef` passed by callers is
  just a `Map` (functions can live in a `Map<String, dynamic>`), so there is no
  separate options type.
- **Numbers.** JSON integers parse to `int`, decimals to `double`. `typify`
  treats a whole `double` as an integer (`Number.isInteger` semantics);
  `stringify`/`jsonify` follow JS formatting (an integral `double` prints
  without `.0`).
- Keep `make test` and `python3 ../tools/check_parity.py` green, and add no
  runtime dependencies. Change canonical (TS + corpus) first, then propagate.
