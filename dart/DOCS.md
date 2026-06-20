# Dart port — comprehensive guide

This document covers the Dart-specific details of `voxgig/struct`. For the
language-neutral concepts, tutorial and full reference, read the top-level
[`../DOCS.md`](../DOCS.md); for the user overview, [`README.md`](./README.md).
TypeScript is canonical and the shared `build/test` corpus is the contract.

## Installation

The whole library is one file (`lib/voxgig_struct.dart`) with no third-party
dependencies. Depend on it as a package and
`import 'package:voxgig_struct/voxgig_struct.dart' as s;` (a prefix is
recommended — several names, e.g. `clone`, would otherwise collide).

## Representation of data

| JSON-shape thing        | Dart representation                       |
|-------------------------|-------------------------------------------|
| object / map            | `Map<String, dynamic>` (insertion order)  |
| array / list            | growable `List<dynamic>`                   |
| string                  | `String`                                   |
| integer                 | `int`                                      |
| decimal                 | `double`                                   |
| boolean                 | `bool`                                     |
| JSON `null` / undefined | `null`                                     |
| function (commands)     | a Dart `Function`                          |

Nodes are **mutable and reference-stable** on purpose: `merge`, `walk`,
`inject`, `transform`, `validate` mutate nodes in place and depend on shared
references. Build nodes with map/list literals (or `jm` / `jt`); Dart's default
`Map` preserves insertion order and keeps a key's position on re-assignment.

### `null`: undefined vs JSON null

Dart has a single `null`, used for both the canonical `undefined` and JSON
`null`. The library follows the Group A / Group B rules
([`../design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)):

- **Group A** readers — `getprop`, `getelem`, `haskey`, `isnode`, `isempty` —
  treat a stored `null` as "no value".
- **Group B** processors — `setprop`, `clone`, `merge`, `walk`, `inject`,
  `transform`, `validate`, `select` — preserve `null` literally.

Where a function must tell "no argument" from an explicit `null`, pass the
public `pathifyNoArg` sentinel:

```dart
s.typify();              // T_noval     (no argument = undefined)
s.typify(null);          // T_scalar | T_null
s.stringify();           // ""          (undefined)
s.stringify(null);       // "null"      (JSON null)
s.pathify(s.pathifyNoArg); // "<unknown-path>"
```

## The public API

Names are lower-smushed / camelCased, identical (case/underscore-insensitively)
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
  `re_replace`, `re_test`, `re_escape`. Backed by the core `RegExp`.
- **By-example engine:** `inject`, `transform`, `validate`, `select`, and the
  injector helpers `checkPlacement`, `injectorArgs`, `injectChild`.
- **Builders / markers:** `jm`, `jt`, `SKIP`, `DELETE`, the `T_*` type
  constants and `M_KEYPRE` / `M_KEYPOST` / `M_VAL`.

`walk` takes named optional parameters (`before:` / `after:` / `maxdepth:`);
most other optional arguments are positional, e.g. `getprop(val, key, [alt])`,
`slice(val, [start, end, mutate])`, `stringify([val, maxlen, pretty])`,
`merge(objs, [maxdepth])`.

## Examples

```dart
import 'package:voxgig_struct/voxgig_struct.dart' as s;

// merge (later wins; the first node is modified in place)
s.merge([{'a': 1}, {'b': 2}]);                       // {a: 1, b: 2}

// transform: spec mirrors the desired output, backticks pull from data
s.transform({'name': 'alice'}, {'user': {'id': '`name`'}}); // {user: {id: alice}}

// validate: plain values are typed defaults; `$STRING` etc. are commands
s.validate({'a': 'x'}, {'a': '`\$STRING`'});         // {a: x}

// select: MongoDB-style query over children
s.select([{'a': 1}, {'a': 2}], {'a': {'`\$GT`': 1}}); // [{a: 2, $KEY: 1}]
```

## Testing

`make test` runs the entire shared corpus (`../build/test/test.json`) through
the port via `dart run test/runner.dart`, using the SDK's `dart:convert` to
read the corpus into the same native types the library operates on, and the
same runner logic as every other port. Keep it green, keep
`python3 ../tools/check_parity.py` green, and add no runtime dependencies.

## Implementation notes

- The injection state (`Inj`) is a plain class; a caller-supplied `injdef` is
  just a `Map` (functions can live in a `Map<String, dynamic>`).
- `SKIP` / `DELETE` are `_Sentinel` markers compared with `identical`.
- Numbers follow JS formatting in `stringify` / `jsonify` (an integral `double`
  prints without a trailing `.0`).
- The only regex is the core `RegExp`, which covers the RE2 subset the corpus
  uses for `$LIKE` and the `re_*` API.
