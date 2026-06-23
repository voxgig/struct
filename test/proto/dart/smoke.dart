// Smoke check (not a test): prove the provider loads and normalizes, and that
// the summary numbers match the canonical TS reference.
//
// Run from the repo root once a Dart toolchain is available:
//   dart run test/proto/dart/smoke.dart
// or with an explicit corpus path:
//   dart run test/proto/dart/smoke.dart build/test/test.json

import 'provider.dart';

void main(List<String> args) {
  final p = args.isNotEmpty ? TestProvider.load(args[0]) : TestProvider.load();

  final fns = p.functions();
  print('functions: ${fns.join(', ')}');

  var total = 0;
  final expectKinds = <String, int>{};
  final inputKinds = <String, int>{};
  for (final fn in fns) {
    for (final e in p.entries(fn)) {
      total++;
      expectKinds[e.expect.kindName] = (expectKinds[e.expect.kindName] ?? 0) + 1;
      inputKinds[e.input.kindName] = (inputKinds[e.input.kindName] ?? 0) + 1;
    }
  }

  print('total entries: $total');
  print('expect kinds: value=${expectKinds['value'] ?? 0}, '
      'absent=${expectKinds['absent'] ?? 0}, '
      'match=${expectKinds['match'] ?? 0}, '
      'error=${expectKinds['error'] ?? 0}');
  print('input kinds: in=${inputKinds['in'] ?? 0}, '
      'args=${inputKinds['args'] ?? 0}, '
      'ctx=${inputKinds['ctx'] ?? 0}');

  final gp = p.entries('getpath', 'basic');
  if (gp.isNotEmpty) {
    final e = gp[0];
    print('getpath/basic[0]: id=${e.id}, doc=${e.doc}, '
        'input.kind=${e.input.kindName}, expect.kind=${e.expect.kindName}, '
        'expect.value=${e.expect.value}');
  }

  // helper sanity
  print('equal(42,42): ${equal(42, 42)}');
  print('equal(null,null): ${equal(null, null)}');
  print('errorMatches(any): '
      '${errorMatches(const ErrorCheck(any: true), 'boom')}');
  print('errorMatches(substr): '
      '${errorMatches(const ErrorCheck(any: false, text: 'not found'), 'Key NOT FOUND here')}');
  print('structMatch ok: '
      '${structMatch({'a': {'b': 2}}, {'a': {'b': 2}, 'c': 9}).ok}');
  final sm = structMatch({'a': {'b': 2}}, {'a': {'b': 3}});
  print('structMatch fail: ok=${sm.ok}, path=${sm.path}, '
      'expected=${sm.expected}, actual=${sm.actual}');
}
