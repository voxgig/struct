# AGENTS.md — Dart port of `voxgig/struct`

Read the repo-root [`../AGENTS.md`](../AGENTS.md) first. This file covers only
what is specific to the Dart port. **TypeScript is canonical; the shared
`build/test/*.aontu` corpus is the contract.** This port follows the
single-`null` model of the Python / Clojure / Lua ports (Dart has one `null`),
not the distinct-`undefined`/`null` model of the OCaml / Scala ports.

## How to build / test / lint

```
cd dart
make test    # the shared corpus, on voxgig/omni
make lint    # dart analyze over lib + test (a clean analysis = pass)
make build   # compile lib/ ALONE (no omni)
```

Requires only the Dart SDK. **Zero third-party runtime dependencies** — the
library uses only `dart:core`.

- **The corpus runner is voxgig/omni**, a local checkout the Makefile finds via
  `$OMNI_HOME` or beside this repository. It reaches the analyzer through a
  GENERATED, gitignored `pubspec_overrides.yaml` — pub's own local-development
  override file — so the published `pubspec.yaml` never names omni
  (register 4.13), and `make build` compiles `lib/` alone to prove it.
- **`test/runner.dart` is a list of subjects and one line of bridge.** omni's
  value model and this port's are the same plain Dart types, so `tostruct` is
  just `isabsent(val) ? null : val`; there is nothing to copy. A node a subject
  mutates IS omni's node, which is why `match.args` works here without omni's
  `runsetflags_args` (the compiled ports need that second entry point).
- **A zero-argument entry arrives as `ABSENT`**, not `null` — omni's
  `_resolveargs` says so explicitly for the dynamic ports (voxgig/omni#29,
  register 4.12). `minor.typify` is the group that needs it: the corpus has
  both `{in: null, out: T_null}` and `{out: T_noval}`, and this port answers
  the second only if it can see that no argument came.

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
