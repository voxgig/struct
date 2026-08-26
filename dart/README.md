# voxgig_struct — Dart

A Dart port of [`voxgig/struct`](../README.md): one small, fixed API for
manipulating JSON-shaped data — lookups, deep merge, by-example transform,
by-example validate, tree walk, path get/set, selection — that returns the
**same answer** as the canonical TypeScript implementation and every other
port. The behavioural contract is the shared JSON corpus in
[`build/test/`](../build/test); this port passes it in full.

## Status

Complete. Every canonical public function is implemented and the shared corpus
passes in full (`make test`) on [voxgig/omni](https://github.com/voxgig/omni),
the shared test runner — 1358 entries in 72 groups, plus the two `check`
entries and three single entries that are not part of any set. **Zero
third-party dependencies** — only the Dart SDK is required, and omni is a
test-time override that the published package never names.

## Requirements

- The [Dart SDK](https://dart.dev/get-dart) 3.0 or later.
- For the tests only: [voxgig/omni](https://github.com/voxgig/omni), fetched
  by `dart pub get` from its `dart/v0.1.0` release tag. No checkout needed.

## Use

```dart
import 'package:voxgig_struct/voxgig_struct.dart' as s;

void main() {
  final store = {'a': {'b': 2}};
  print(s.getpath(store, 'a.b')); // 2

  print(s.stringify(s.transform({'a': 1}, {'x': '`a`'}))); // {x:1}
}
```

`jm` / `jt` are convenient JSON-object / JSON-array builders (they take a list
of arguments):

```dart
s.jsonify(s.jm(['a', 1, 'b', s.jt([2, 3])]));
```

### Data model

Nodes are native Dart collections so the library's in-place, reference-stable
algorithms behave exactly as in the canonical TypeScript:

- maps → `Map<String, dynamic>` (a `LinkedHashMap`, insertion-ordered),
- lists → growable `List<dynamic>`,
- `null` plays the role of both `undefined` and JSON `null` (the Group A/B
  rules recover the distinction — see
  [`../design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)).

## API

The public surface matches the canonical export list, in lower-smushed /
camelCased names:

`clone delprop escre escurl filter flatten getdef getelem getpath getprop
haskey inject isempty isfunc iskey islist ismap isnode items join jsonify
keysof merge pad pathify select setpath setprop size slice strkey stringify
transform typify typename validate walk re_compile re_find re_find_all
re_replace re_test re_escape jm jt checkPlacement injectorArgs injectChild`

See [`DOCS.md`](./DOCS.md) for the full guide and
[the language-neutral docs](../DOCS.md) for concepts and examples.

## Develop

```
make test     # run the shared corpus on voxgig/omni (fetched from its tag)
make lint     # dart analyze over lib + test
make build    # compile lib/ alone
make format   # dart format check
```

## License

MIT. See [`../LICENSE`](../LICENSE).
