// Test Provider (prototype) — Dart port of the canonical TypeScript
// implementation (../ts/provider.ts).
//
// Reads the shared corpus (build/test/test.json) and hands test code clean,
// normalized cases. It is NOT a test runner: it never calls the subject and
// never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
//
// Zero runtime dependencies (Dart standard library only), matching repo policy.
// dart:convert jsonDecode returns LinkedHashMap (insertion-ordered) for objects
// and List for arrays, so corpus key order is preserved natively — unlike the
// Go port, no separate order-tracking pass is needed. JSON numbers decode to
// int (e.g. 42) when integral, double otherwise.

import 'dart:convert';
import 'dart:io';

const String nullMark = '__NULL__';
const String undefMark = '__UNDEF__';
const String existsMark = '__EXISTS__';

/// How the input is supplied to the subject (mirrors the runner's
/// ctx → args → in precedence).
enum InputKind { inp, args, ctx }

/// How a result is expected (value | error | match | absent).
enum ExpectKind { value, error, match, absent }

/// A tagged invocation: exactly one of value/args/ctx is meaningful, selected
/// by [kind]. The single-argument `in` value is named [value] because `in` is
/// a reserved word in Dart.
class Input {
  final InputKind kind;
  final dynamic value; // kind == InputKind.inp  — the single argument
  final List<dynamic>? args; // kind == InputKind.args
  final Map<String, dynamic>? ctx; // kind == InputKind.ctx

  const Input(this.kind, {this.value, this.args, this.ctx});

  String get kindName {
    switch (kind) {
      case InputKind.inp:
        return 'in';
      case InputKind.args:
        return 'args';
      case InputKind.ctx:
        return 'ctx';
    }
  }
}

/// The parsed form of a raw `err` spec.
class ErrorCheck {
  final bool any;
  final String? text;
  final bool regex;

  const ErrorCheck({required this.any, this.text, this.regex = false});
}

/// A tagged expectation: value | error | match | absent.
class Expect {
  final ExpectKind kind;
  final bool hasValue; // distinguishes present-null from absent
  final dynamic value; // kind == ExpectKind.value
  final ErrorCheck? error; // kind == ExpectKind.error
  final dynamic match; // populated whenever a `match` key is present

  const Expect(
    this.kind, {
    this.hasValue = false,
    this.value,
    this.error,
    this.match,
  });

  String get kindName {
    switch (kind) {
      case ExpectKind.value:
        return 'value';
      case ExpectKind.error:
        return 'error';
      case ExpectKind.match:
        return 'match';
      case ExpectKind.absent:
        return 'absent';
    }
  }
}

/// The normalized record for a single corpus test case.
class Entry {
  final String function;
  final String group;
  final int index;
  final String? id;
  final bool doc;
  final String? client;
  final Input input;
  final Expect expect;
  final dynamic raw; // the original entry, untouched (escape hatch)

  const Entry({
    required this.function,
    required this.group,
    required this.index,
    required this.id,
    required this.doc,
    required this.client,
    required this.input,
    required this.expect,
    required this.raw,
  });
}

/// The outcome of a structural match.
class MatchResult {
  final bool ok;
  final List<String>? path;
  final dynamic expected;
  final dynamic actual;

  const MatchResult(this.ok, {this.path, this.expected, this.actual});
}

/// Default corpus path: build/test/test.json relative to the repo root.
///
/// Resolved from the location of this source file (Platform.script), so it
/// works regardless of the current working directory. This file lives at
/// test/proto/dart/provider.dart, so the repo root is three directories up.
/// When Platform.script does not point at a file path (e.g. some snapshot
/// runs) we fall back to the documented relative path used by the runner.
String _defaultTestFile() {
  try {
    final script = Platform.script;
    if (script.scheme == 'file') {
      // .../test/proto/dart/<entrypoint>.dart -> repo root is 4 segments up.
      final dir = File.fromUri(script).parent; // test/proto/dart (or smoke dir)
      // Walk up to repo root: dart -> proto -> test -> root.
      final root = dir.parent.parent.parent;
      return '${root.path}/build/test/test.json';
    }
  } catch (_) {
    // Fall through to the relative default below.
  }
  // Documented fallback (matches dart/test/runner.dart's relative default,
  // adjusted for this file's deeper location): run from the repo root.
  return 'build/test/test.json';
}

/// Holds the parsed corpus.
class TestProvider {
  final dynamic spec;

  const TestProvider(this.spec);

  /// Parse test.json. A null [path] means the default corpus path.
  static TestProvider load([String? path]) {
    final file = path ?? _defaultTestFile();
    final raw = File(file).readAsStringSync();
    return TestProvider(jsonDecode(raw));
  }

  /// The parsed test.json (escape hatch).
  dynamic raw() => spec;

  /// spec.struct if present, else spec itself, as a Map.
  Map<String, dynamic>? _root() {
    if (spec is Map) {
      final m = spec as Map;
      final st = m['struct'];
      if (st is Map) {
        return _asStrMap(st);
      }
      return _asStrMap(m);
    }
    return null;
  }

  /// Resolve the node for a function (under struct, falling back to root).
  Map<String, dynamic> _fnNode(String fn) {
    if (spec is Map) {
      final m = spec as Map;
      final st = m['struct'];
      if (st is Map && st[fn] is Map) {
        return _asStrMap(st[fn] as Map);
      }
      if (m[fn] is Map) {
        return _asStrMap(m[fn] as Map);
      }
    }
    throw StateError('Unknown function: $fn');
  }

  /// The function names, in corpus order.
  List<String> functions() {
    final root = _root();
    if (root == null) return <String>[];
    final out = <String>[];
    for (final k in root.keys) {
      final v = root[k];
      if (_isGroupBag(v) || _hasGroups(v)) {
        out.add(k);
      }
    }
    return out;
  }

  /// The group names for a function, in corpus order.
  List<String> groups(String fn) {
    final node = _fnNode(fn);
    final out = <String>[];
    for (final k in node.keys) {
      if (k != 'name' && _isGroupBag(node[k])) {
        out.add(k);
      }
    }
    return out;
  }

  /// All entries for a function, or for one specific group.
  List<Entry> entries(String fn, [String? group]) {
    final node = _fnNode(fn);
    final groupNames = group != null ? <String>[group] : groups(fn);
    final out = <Entry>[];
    for (final g in groupNames) {
      final bag = node[g];
      if (!_isGroupBag(bag)) continue;
      final set = (bag as Map)['set'];
      if (set is! List) continue;
      for (var i = 0; i < set.length; i++) {
        out.add(_normalize(fn, g, i, set[i]));
      }
    }
    return out;
  }
}

Map<String, dynamic> _asStrMap(Map m) {
  if (m is Map<String, dynamic>) return m;
  final o = <String, dynamic>{};
  m.forEach((k, v) => o[k.toString()] = v);
  return o;
}

/// A group bag is a Map with a `set` List.
bool _isGroupBag(dynamic v) => v is Map && v['set'] is List;

/// A function node has at least one child group bag.
bool _hasGroups(dynamic v) {
  if (v is! Map) return false;
  for (final k in v.keys) {
    if (k != 'name' && _isGroupBag(v[k])) return true;
  }
  return false;
}

bool _has(dynamic m, String key) => m is Map && m.containsKey(key);

Entry _normalize(String fn, String group, int index, dynamic raw) {
  String? id;
  if (_has(raw, 'id') && (raw as Map)['id'] != null) {
    id = _stringify(raw['id']);
  }
  String? client;
  if (_has(raw, 'client') && (raw as Map)['client'] != null) {
    client = _stringify(raw['client']);
  }
  final doc = raw is Map && raw['doc'] == true;
  return Entry(
    function: fn,
    group: group,
    index: index,
    id: id,
    doc: doc,
    client: client,
    input: _resolveInput(raw),
    expect: _resolveExpect(raw),
    raw: raw,
  );
}

Input _resolveInput(dynamic raw) {
  if (_has(raw, 'ctx')) {
    final ctx = (raw as Map)['ctx'];
    return Input(InputKind.ctx, ctx: ctx is Map ? _asStrMap(ctx) : null);
  }
  if (_has(raw, 'args')) {
    final args = (raw as Map)['args'];
    return Input(InputKind.args,
        args: args is List ? List<dynamic>.from(args) : null);
  }
  // kind == in: key absent => native null.
  return Input(InputKind.inp, value: _has(raw, 'in') ? (raw as Map)['in'] : null);
}

final RegExp _reErr = RegExp(r'^/(.+)/$');

ErrorCheck _parseErr(dynamic err) {
  if (err == true) {
    return const ErrorCheck(any: true);
  }
  if (err is String) {
    final m = _reErr.firstMatch(err);
    if (m != null) {
      return ErrorCheck(any: false, text: m.group(1), regex: true);
    }
    return ErrorCheck(any: false, text: err, regex: false);
  }
  // Non-true, non-string err spec: treat as "any error".
  return const ErrorCheck(any: true);
}

Expect _resolveExpect(dynamic raw) {
  final hasMatch = _has(raw, 'match');
  final matchPart = hasMatch ? (raw as Map)['match'] : null;
  if (_has(raw, 'err')) {
    return Expect(ExpectKind.error,
        error: _parseErr((raw as Map)['err']), match: matchPart);
  }
  if (_has(raw, 'out')) {
    // KEY PRESENCE: "out" present even if null => value.
    return Expect(ExpectKind.value,
        hasValue: true, value: (raw as Map)['out'], match: matchPart);
  }
  if (hasMatch) {
    return Expect(ExpectKind.match, match: matchPart);
  }
  return const Expect(ExpectKind.absent);
}

// ─── pure comparison helpers ───────────────────────────────────────────────

/// The string itself if [x] is a String, else compact JSON. JSON-encoded ints
/// print without a decimal point (42, not 42.0).
String _stringify(dynamic x) => x is String ? x : jsonEncode(x);

dynamic _normNull(dynamic x) {
  if (x == nullMark || x == null) return null;
  if (x is List) return x.map(_normNull).toList();
  if (x is Map) {
    final o = <String, dynamic>{};
    x.forEach((k, v) => o[k.toString()] = _normNull(v));
    return o;
  }
  return x;
}

dynamic _normMark(dynamic x) {
  if (x == nullMark) return null;
  if (x is List) return x.map(_normMark).toList();
  if (x is Map) {
    final o = <String, dynamic>{};
    x.forEach((k, v) => o[k.toString()] = _normMark(v));
    return o;
  }
  return x;
}

bool _deepEq(dynamic a, dynamic b) {
  if (_scalarEq(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEq(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_deepEq(a[k], b[k])) return false;
    }
    return true;
  }
  return false;
}

bool _scalarEq(dynamic a, dynamic b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a is num && b is num) return a == b;
  if (a is String && b is String) return a == b;
  if (a is bool && b is bool) return a == b;
  return false;
}

/// `check === base`; else if check is a String: `"/re/"` ⇒ regex test against
/// stringify(base), otherwise case-insensitive substring; else if check is a
/// Function ⇒ true.
bool matchval(dynamic check, dynamic base) {
  if (equalStrict(check, base)) return true;
  if (check is String) {
    final basestr = _stringify(base);
    final m = _reErr.firstMatch(check);
    if (m != null) {
      return RegExp(m.group(1)!).hasMatch(basestr);
    }
    return basestr.toLowerCase().contains(check.toLowerCase());
  }
  if (check is Function) return true;
  return false;
}

/// Deep equality, null/undef collapsed (runner default null:true): "__NULL__"
/// and null collapse to null on both sides.
bool equal(dynamic expected, dynamic actual) =>
    _deepEq(_normNull(expected), _normNull(actual));

/// Deep equality where undefined ≠ null (runner null:false functions): only
/// "__NULL__" is normalized to null.
bool equalStrict(dynamic expected, dynamic actual) =>
    _deepEq(_normMark(expected), _normMark(actual));

/// An ErrorCheck against a thrown message: any ⇒ true; regex ⇒ RegExp test;
/// else case-insensitive substring.
bool errorMatches(ErrorCheck check, String message) {
  if (check.any) return true;
  if (check.text == null) return false;
  if (check.regex) return RegExp(check.text!).hasMatch(message);
  return message.toLowerCase().contains(check.text!.toLowerCase());
}

/// Partial structural match: every leaf of [check] must match [base] at its
/// path. First failure returns its path plus the two values.
MatchResult structMatch(dynamic check, dynamic base) {
  var result = const MatchResult(true);
  _walkLeaves(check, <String>[], (val, path) {
    if (!result.ok) return;
    final found = _getpath(base, path);
    final baseval = found.value;
    if (found.present && _scalarEq(baseval, val)) return;
    if (val == undefMark && (!found.present || baseval == null)) return;
    if (val == existsMark && found.present && baseval != null) return;
    if (!matchval(val, baseval)) {
      result = MatchResult(false, path: path, expected: val, actual: baseval);
    }
  });
  return result;
}

void _walkLeaves(
    dynamic node, List<String> path, void Function(dynamic, List<String>) fn) {
  if (node is List) {
    for (var i = 0; i < node.length; i++) {
      _walkLeaves(node[i], [...path, i.toString()], fn);
    }
  } else if (node is Map) {
    node.forEach((k, v) => _walkLeaves(v, [...path, k.toString()], fn));
  } else {
    fn(node, path);
  }
}

class _Found {
  final dynamic value;
  final bool present;
  const _Found(this.value, this.present);
}

/// Descend store following path. `present` is false if it ran off a null or a
/// missing key/index.
_Found _getpath(dynamic store, List<String> path) {
  dynamic cur = store;
  for (final key in path) {
    if (cur is Map) {
      if (!cur.containsKey(key)) return const _Found(null, false);
      cur = cur[key];
    } else if (cur is List) {
      final idx = int.tryParse(key);
      if (idx == null || idx < 0 || idx >= cur.length) {
        return const _Found(null, false);
      }
      cur = cur[idx];
    } else {
      return const _Found(null, false);
    }
  }
  return _Found(cur, true);
}
