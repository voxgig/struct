// Performance bench for the Dart port. Emits one JSON line per
// build/bench/README.md; diagnostics go to stderr.
import 'dart:convert';
import 'dart:io';

import '../lib/voxgig_struct.dart' as s;

int envi(String k, int d) => int.tryParse(Platform.environment[k] ?? '') ?? d;

dynamic build(int w, int d, int leaf) {
  if (d == 0) return leaf;
  final m = <String, dynamic>{};
  for (var i = 0; i < w; i++) {
    m['k$i'] = build(w, d - 1, leaf);
  }
  return m;
}

int nodecount(int w, int d) {
  var n = 0, p = 1;
  for (var i = 0; i <= d; i++) {
    n += p;
    p *= w;
  }
  return n;
}

var sink = 0;

Map<String, double> measure(int warm, int runs, void Function() fn) {
  for (var i = 0; i < warm; i++) fn();
  final t = <double>[];
  final sw = Stopwatch();
  for (var r = 0; r < runs; r++) {
    sw
      ..reset()
      ..start();
    fn();
    sw.stop();
    t.add(sw.elapsedMicroseconds / 1000.0);
  }
  t.sort();
  final mean = t.reduce((a, b) => a + b) / t.length;
  return {'min_ms': t.first, 'median_ms': t[t.length ~/ 2], 'mean_ms': mean};
}

void main() {
  final W = envi('BENCH_WIDTH', 5),
      D = envi('BENCH_DEPTH', 6),
      WARM = envi('BENCH_WARMUP', 3),
      RUNS = envi('BENCH_RUNS', 21),
      GP = envi('BENCH_GETPATH_ITERS', 2000);

  final tree = build(W, D, 0);
  final nodes = nodecount(W, D);
  final treeA = build(W, D, 1), treeB = build(W, D, 2);
  final path = List.filled(D, 'k0').join('.');
  cb(key, val, parent, p) {
    sink += (p as List).length;
    return val;
  }

  final specs = <List<dynamic>>[
    ['clone', nodes, () => sink += s.clone(tree) != null ? 1 : 0],
    ['walk', nodes, () => s.walk(tree, before: cb)],
    ['merge', nodes, () => sink += s.merge([treeA, treeB]) != null ? 1 : 0],
    ['stringify', nodes, () => sink += s.stringify(tree).length as int],
    ['getpath', GP, () {
      var acc = 0;
      for (var i = 0; i < GP; i++) {
        if (s.getpath(tree, path) == 0) acc++;
      }
      sink += acc;
    }],
  ];

  final ops = specs.map((sp) {
    final m = measure(WARM, RUNS, sp[2] as void Function());
    return {'op': sp[0], 'runs': RUNS, 'unit_count': sp[1], ...m};
  }).toList();

  stderr.writeln('dart: sink=$sink');
  print(jsonEncode({
    'lang': 'dart',
    'runtime': 'dart ${Platform.version.split(' ').first}',
    'nodes': nodes,
    'params': {'width': W, 'depth': D, 'warmup': WARM, 'runs': RUNS, 'getpath_iters': GP},
    'ops': ops,
  }));
}
