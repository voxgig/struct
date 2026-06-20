// Test runner for the shared JSON corpus (build/test/test.json).
// Self-contained: uses the SDK's dart:convert to read the corpus into native
// Map/List/num/String/bool/null — exactly the types the library operates on.

import 'dart:convert';
import 'dart:io';
import '../lib/voxgig_struct.dart' as s;

const nullmark = '__NULL__';
const undefmark = '__UNDEF__';
const existsmark = '__EXISTS__';

dynamic fixJson(dynamic v, bool flagNull) {
  if (v == null) return flagNull ? nullmark : null;
  if (v is Map) {
    var o = <String, dynamic>{};
    v.forEach((k, x) => o[k.toString()] = fixJson(x, flagNull));
    return o;
  }
  if (v is List) return v.map((x) => fixJson(x, flagNull)).toList();
  return v;
}

bool eqv(dynamic a, dynamic b) {
  if (a == null && b == null) return true;
  if (a is bool || b is bool) return a == b;
  if (a is num && b is num) return a == b;
  if (a is String && b is String) return a == b;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!eqv(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (var k in a.keys) {
      if (!b.containsKey(k) || !eqv(a[k], b[k])) return false;
    }
    return true;
  }
  return identical(a, b);
}

bool matchval(dynamic check0, dynamic base) {
  var check = (check0 == undefmark || check0 == nullmark) ? null : check0;
  if (eqv(check, base)) return true;
  if (check is String) {
    var basestr = s.stringify(base);
    if (check.length >= 2 && check.startsWith('/') && check.endsWith('/')) {
      return RegExp(check.substring(1, check.length - 1)).hasMatch(basestr);
    }
    return basestr.toLowerCase().contains(s.stringify(check).toLowerCase());
  }
  if (check is Function) return true;
  return false;
}

void doMatch(dynamic check, dynamic base0) {
  var base = s.clone(base0);
  s.walk(check, before: (k, v, p, path) {
    if (!s.isnode(v)) {
      var baseval = s.getpath(base, path);
      if (eqv(baseval, v)) {
      } else if (v == undefmark && baseval == null) {
      } else if (v == existsmark && baseval != null) {
      } else if (!matchval(v, baseval)) {
        var pstr = (path as List).map((e) => s.jsString(e)).join('.');
        throw s.StructError(
            'MATCH: $pstr: [${s.stringify(v)}] <=> [${s.stringify(baseval)}]');
      }
    }
    return v;
  });
}

int npass = 0;
int nfail = 0;
List<String> failures = [];
void record(String group, String name, bool ok, String msg) {
  if (ok) {
    npass++;
  } else {
    nfail++;
    failures.add('FAIL $group $name - $msg');
  }
}

dynamic omapV(Map<String, dynamic> kvs) => Map<String, dynamic>.from(kvs);
dynamic eget(dynamic e, String k) =>
    (e is Map && e.containsKey(k)) ? e[k] : null;
bool ehas(dynamic e, String k) => e is Map && e.containsKey(k);

List<dynamic> resolveArgs(dynamic entry) {
  if (ehas(entry, 'ctx')) return [eget(entry, 'ctx')];
  if (ehas(entry, 'args'))
    return (eget(entry, 'args') is List)
        ? List<dynamic>.from(eget(entry, 'args'))
        : [];
  if (ehas(entry, 'in')) return [s.clone(eget(entry, 'in'))];
  return <dynamic>[];
}

void checkResult(dynamic entry, List<dynamic> args, dynamic res) {
  var matched = false;
  if (ehas(entry, 'match')) {
    doMatch(
        eget(entry, 'match'),
        omapV({
          'in': eget(entry, 'in'),
          'args': List<dynamic>.from(args),
          'out': eget(entry, 'res'),
          'ctx': eget(entry, 'ctx')
        }));
    matched = true;
  }
  var out = eget(entry, 'out');
  if (eqv(out, res)) return;
  if (matched && (out == nullmark || out == null)) return;
  throw s.StructError(
      'Expected: ${s.stringify(out)}, got: ${s.stringify(res)}');
}

void handleError(dynamic entry, Object err) {
  var msg = err is s.StructError ? err.message : err.toString();
  if (ehas(entry, 'err')) {
    var entryErr = eget(entry, 'err');
    if (entryErr == true || matchval(entryErr, msg)) {
      if (ehas(entry, 'match')) {
        doMatch(
            eget(entry, 'match'),
            omapV({
              'in': eget(entry, 'in'),
              'out': eget(entry, 'res'),
              'ctx': eget(entry, 'ctx'),
              'err': msg
            }));
      }
    } else {
      throw s.StructError('ERROR MATCH: [${s.stringify(entryErr)}] <=> [$msg]');
    }
  } else {
    throw err;
  }
}

void runSet(String group, dynamic node, dynamic Function(List<dynamic>) subject,
    [bool flagNull = true]) {
  var fixed = fixJson(node, flagNull);
  var testset = s.getprop(fixed, 'set');
  if (testset is! List) return;
  for (var entry in testset) {
    var name = s.jsString(eget(entry, 'name'));
    try {
      if (!ehas(entry, 'out') && flagNull) s.setprop(entry, 'out', nullmark);
      var args = resolveArgs(entry);
      var res = fixJson(subject(args), flagNull);
      s.setprop(entry, 'res', res);
      checkResult(entry, args, res);
      record(group, name, true, '');
    } catch (e) {
      try {
        handleError(entry, e);
        record(group, name, true, '');
      } catch (e2) {
        record(group, name, false,
            e2 is s.StructError ? e2.message : e2.toString());
      }
    }
  }
}

void runSingle(String group, dynamic node, dynamic Function(dynamic) actualFn) {
  try {
    var expected = eget(node, 'out');
    var actual = actualFn(eget(node, 'in'));
    if (eqv(expected, actual)) {
      record(group, 'single', true, '');
    } else {
      record(group, 'single', false,
          'Expected: ${s.stringify(expected)}, got: ${s.stringify(actual)}');
    }
  } catch (e) {
    record(
        group, 'single', false, e is s.StructError ? e.message : e.toString());
  }
}

dynamic Function(List<dynamic>) arg1(dynamic Function(dynamic) f) =>
    (args) => f(args.isNotEmpty ? args[0] : null);
dynamic vget(dynamic vin, String k) =>
    (vin is Map && vin.containsKey(k)) ? vin[k] : null;
bool vhas(dynamic vin, String k) => vin is Map && vin.containsKey(k);

void nullModifier(dynamic v, dynamic key, dynamic parent, dynamic inj) {
  if (v == nullmark) {
    s.setprop(parent, key, null);
  } else if (v is String) {
    s.setprop(parent, key, v.replaceAll(nullmark, 'null'));
  }
}

void runWalkLog(String group, dynamic node) {
  try {
    var testData = s.clone(node);
    var log = <dynamic>[];
    walklog(key, v, parent, path) {
      s.setprop(
          log,
          s.size(log),
          'k=' +
              (key == null ? s.stringify() : s.stringify(key)) +
              ', v=' +
              s.stringify(v) +
              ', p=' +
              (parent == null ? s.stringify() : s.stringify(parent)) +
              ', t=' +
              s.pathify(path));
      return v;
    }

    s.walk(s.getprop(testData, 'in'), after: walklog);
    var expected = s.getprop(s.getprop(testData, 'out'), 'after');
    if (eqv(expected, log)) {
      record(group, 'log', true, '');
    } else {
      record(group, 'log', false,
          'Expected: ${s.stringify(expected)}, got: ${s.stringify(log)}');
    }
  } catch (e) {
    record(group, 'log', false, e is s.StructError ? e.message : e.toString());
  }
}

dynamic walkCopySubject(dynamic vin) {
  var cur = <dynamic>[null];
  walkcopy(key, v, parent, path) {
    if (key == null) {
      cur[0] = [
        s.ismap(v) ? <String, dynamic>{} : (s.islist(v) ? <dynamic>[] : v)
      ];
      return v;
    }
    var i = s.size(path);
    dynamic nv;
    if (s.isnode(v)) {
      var c = cur[0] as List;
      while (c.length <= i) {
        c.add(null);
      }
      nv = s.ismap(v) ? <String, dynamic>{} : <dynamic>[];
      c[i] = nv;
    } else {
      nv = v;
    }
    s.setprop(s.getelem(cur[0], i - 1), key, nv);
    return v;
  }

  s.walk(vin, before: walkcopy);
  return s.getelem(cur[0], 0);
}

dynamic walkDepthSubject(dynamic vin) {
  var state = <String, dynamic>{'top': null, 'cur': null};
  copy(key, v, parent, path) {
    if (key == null || s.isnode(v)) {
      var child = s.islist(v) ? <dynamic>[] : <String, dynamic>{};
      if (key == null) {
        state['top'] = child;
        state['cur'] = child;
      } else {
        s.setprop(state['cur'], key, child);
        state['cur'] = child;
      }
    } else {
      s.setprop(state['cur'], key, v);
    }
    return v;
  }

  s.walk(vget(vin, 'src'), before: copy, maxdepth: vget(vin, 'maxdepth'));
  return state['top'];
}

void runAll(dynamic spec) {
  g(k) => s.getprop(spec, k);
  var minor = g('minor');
  var walks = g('walk');
  var merges = g('merge');
  var getpaths = g('getpath');
  var injects = g('inject');
  var transforms = g('transform');
  var validates = g('validate');
  var selects = g('select');
  var sentinels = g('sentinels');
  mg(n) => s.getprop(minor, n);

  runSet('minor.isnode', mg('isnode'), arg1((v) => s.isnode(v)));
  runSet('minor.ismap', mg('ismap'), arg1((v) => s.ismap(v)));
  runSet('minor.islist', mg('islist'), arg1((v) => s.islist(v)));
  runSet('minor.iskey', mg('iskey'), arg1((v) => s.iskey(v)), false);
  runSet('minor.strkey', mg('strkey'), arg1((v) => s.strkey(v)), false);
  runSet('minor.isempty', mg('isempty'), arg1((v) => s.isempty(v)), false);
  runSet('minor.isfunc', mg('isfunc'), arg1((v) => s.isfunc(v)));
  runSet('minor.clone', mg('clone'), arg1((v) => s.clone(v)), false);
  runSet('minor.escre', mg('escre'), arg1((v) => s.escre(v)));
  runSet('minor.escurl', mg('escurl'), arg1((v) => s.escurl(v)));
  runSet(
      'minor.stringify',
      mg('stringify'),
      arg1((vin) => vhas(vin, 'val')
          ? s.stringify(vget(vin, 'val'), vget(vin, 'max'))
          : s.stringify()),
      false);
  runSet('minor.jsonify', mg('jsonify'),
      arg1((vin) => s.jsonify(vget(vin, 'val'), vget(vin, 'flags'))), false);
  runSet('minor.getelem', mg('getelem'), arg1((vin) {
    var alt = vget(vin, 'alt');
    return alt == null
        ? s.getelem(vget(vin, 'val'), vget(vin, 'key'))
        : s.getelem(vget(vin, 'val'), vget(vin, 'key'), alt);
  }), false);
  runSet('minor.delprop', mg('delprop'),
      arg1((vin) => s.delprop(vget(vin, 'parent'), vget(vin, 'key'))));
  runSet('minor.size', mg('size'), arg1((v) => s.size(v)), false);
  runSet(
      'minor.slice',
      mg('slice'),
      arg1((vin) =>
          s.slice(vget(vin, 'val'), vget(vin, 'start'), vget(vin, 'end'))),
      false);
  runSet(
      'minor.pad',
      mg('pad'),
      arg1((vin) =>
          s.pad(vget(vin, 'val'), vget(vin, 'pad'), vget(vin, 'char'))),
      false);
  runSet(
      'minor.pathify',
      mg('pathify'),
      arg1((vin) => vhas(vin, 'path')
          ? s.pathify(vget(vin, 'path'), vget(vin, 'from'))
          : s.pathify(s.pathifyNoArg, vget(vin, 'from'))),
      false);
  runSet('minor.items', mg('items'), arg1((v) => s.items(v)));
  runSet('minor.getprop', mg('getprop'), arg1((vin) {
    var alt = vget(vin, 'alt');
    return alt == null
        ? s.getprop(vget(vin, 'val'), vget(vin, 'key'))
        : s.getprop(vget(vin, 'val'), vget(vin, 'key'), alt);
  }), false);
  runSet(
      'minor.setprop',
      mg('setprop'),
      arg1((vin) =>
          s.setprop(vget(vin, 'parent'), vget(vin, 'key'), vget(vin, 'val'))));
  runSet('minor.haskey', mg('haskey'),
      arg1((vin) => s.haskey(vget(vin, 'src'), vget(vin, 'key'))), false);
  runSet('minor.keysof', mg('keysof'), arg1((v) => s.keysof(v)));
  runSet(
      'minor.join',
      mg('join'),
      arg1((vin) =>
          s.join(vget(vin, 'val'), vget(vin, 'sep'), vget(vin, 'url'))),
      false);
  runSet('minor.typify', mg('typify'),
      (args) => s.typify(args.isEmpty ? s.pathifyNoArg : args[0]), false);
  runSet(
      'minor.setpath',
      mg('setpath'),
      arg1((vin) =>
          s.setpath(vget(vin, 'store'), vget(vin, 'path'), vget(vin, 'val'))),
      false);
  runSet('minor.filter', mg('filter'), arg1((vin) {
    bool Function(List<dynamic>) check;
    var c = vget(vin, 'check');
    if (c == 'gt3') {
      check = (n) => n[1] is num && n[1] > 3;
    } else if (c == 'lt3') {
      check = (n) => n[1] is num && n[1] < 3;
    } else {
      check = (n) => false;
    }
    return s.filter(vget(vin, 'val'), check);
  }));
  runSet('minor.typename', mg('typename'),
      arg1((v) => s.typename(v is num ? v.toInt() : 0)));
  runSet('minor.flatten', mg('flatten'), arg1((vin) {
    var d = vget(vin, 'depth');
    return s.flatten(vget(vin, 'val'), d is num ? d.toInt() : 1);
  }));

  runWalkLog('walk.log', s.getprop(walks, 'log'));
  runSet(
      'walk.basic',
      s.getprop(walks, 'basic'),
      arg1((vin) => s.walk(vin, after: (k, v, p, path) {
            if (v is String) {
              return v +
                  '~' +
                  (path as List).map((e) => s.jsString(e)).join('.');
            }
            return v;
          })));
  runSet('walk.copy', s.getprop(walks, 'copy'), arg1(walkCopySubject));
  runSet(
      'walk.depth', s.getprop(walks, 'depth'), arg1(walkDepthSubject), false);

  runSingle('merge.basic', s.getprop(merges, 'basic'),
      (in_) => s.merge(s.clone(in_)));
  runSet('merge.cases', s.getprop(merges, 'cases'), arg1((v) => s.merge(v)));
  runSet('merge.array', s.getprop(merges, 'array'), arg1((v) => s.merge(v)));
  runSet('merge.integrity', s.getprop(merges, 'integrity'),
      arg1((v) => s.merge(v)));
  runSet('merge.depth', s.getprop(merges, 'depth'),
      arg1((vin) => s.merge(vget(vin, 'val'), vget(vin, 'depth'))));

  runSet('getpath.basic', s.getprop(getpaths, 'basic'),
      arg1((vin) => s.getpath(vget(vin, 'store'), vget(vin, 'path'))));
  runSet('getpath.relative', s.getprop(getpaths, 'relative'), arg1((vin) {
    var dp = vget(vin, 'dpath');
    var dpath = dp is String ? dp.split('.') : null;
    var injdef = {'dparent': vget(vin, 'dparent'), 'dpath': dpath};
    return s.getpath(vget(vin, 'store'), vget(vin, 'path'), injdef);
  }));
  runSet(
      'getpath.special',
      s.getprop(getpaths, 'special'),
      arg1((vin) =>
          s.getpath(vget(vin, 'store'), vget(vin, 'path'), vget(vin, 'inj'))));
  runSet('getpath.handler', s.getprop(getpaths, 'handler'), arg1((vin) {
    var store = {'\$TOP': vget(vin, 'store'), '\$FOO': () => 'foo'};
    handler(inj, val, ref, st) => s.isfunc(val) ? val() : val;
    return s.getpath(store, vget(vin, 'path'), {'handler': handler});
  }));

  runSingle(
      'inject.basic',
      s.getprop(injects, 'basic'),
      (in_) => s.inject(
          s.clone(s.getprop(in_, 'val')), s.clone(s.getprop(in_, 'store'))));
  runSet(
      'inject.string',
      s.getprop(injects, 'string'),
      arg1((vin) => s.inject(vget(vin, 'val'), vget(vin, 'store'),
          {'modify': nullModifier, 'extra': vget(vin, 'current')})));
  runSet('inject.deep', s.getprop(injects, 'deep'),
      arg1((vin) => s.inject(vget(vin, 'val'), vget(vin, 'store'))));

  runSingle('transform.basic', s.getprop(transforms, 'basic'),
      (in_) => s.transform(s.getprop(in_, 'data'), s.getprop(in_, 'spec')));
  for (var gn in ['paths', 'cmds', 'each', 'pack', 'ref']) {
    runSet('transform.$gn', s.getprop(transforms, gn),
        arg1((vin) => s.transform(vget(vin, 'data'), vget(vin, 'spec'))));
  }
  runSet('transform.modify', s.getprop(transforms, 'modify'), arg1((vin) {
    modifier(v, key, parent, inj) {
      if (v is String && key != null && parent != null)
        s.setprop(parent, key, '@' + v);
    }

    return s.transform(vget(vin, 'data'), vget(vin, 'spec'),
        {'modify': modifier, 'extra': vget(vin, 'store')});
  }));
  runSet('transform.format', s.getprop(transforms, 'format'),
      arg1((vin) => s.transform(vget(vin, 'data'), vget(vin, 'spec'))), false);
  runSet('transform.apply', s.getprop(transforms, 'apply'),
      arg1((vin) => s.transform(vget(vin, 'data'), vget(vin, 'spec'))));

  runSet('validate.basic', s.getprop(validates, 'basic'),
      arg1((vin) => s.validate(vget(vin, 'data'), vget(vin, 'spec'))), false);
  for (var gn in ['child', 'one', 'exact']) {
    runSet('validate.$gn', s.getprop(validates, gn),
        arg1((vin) => s.validate(vget(vin, 'data'), vget(vin, 'spec'))));
  }
  runSet('validate.invalid', s.getprop(validates, 'invalid'),
      arg1((vin) => s.validate(vget(vin, 'data'), vget(vin, 'spec'))), false);
  runSet(
      'validate.special',
      s.getprop(validates, 'special'),
      arg1((vin) =>
          s.validate(vget(vin, 'data'), vget(vin, 'spec'), vget(vin, 'inj'))));

  for (var gn in ['basic', 'operators', 'edge', 'alts']) {
    runSet('select.$gn', s.getprop(selects, gn),
        arg1((vin) => s.select(vget(vin, 'obj'), vget(vin, 'query'))));
  }

  runSet(
      'sentinels.getprop_unify',
      s.getprop(sentinels, 'getprop_unify'),
      arg1((vin) =>
          s.getprop(vget(vin, 'val'), vget(vin, 'key'), vget(vin, 'alt'))),
      false);
  runSet(
      'sentinels.getelem_absent',
      s.getprop(sentinels, 'getelem_absent'),
      arg1((vin) =>
          s.getelem(vget(vin, 'val'), vget(vin, 'key'), vget(vin, 'alt'))),
      false);
  runSet('sentinels.haskey_unify', s.getprop(sentinels, 'haskey_unify'),
      arg1((vin) => s.haskey(vget(vin, 'val'), vget(vin, 'key'))), false);
  runSet('sentinels.isempty_unify', s.getprop(sentinels, 'isempty_unify'),
      arg1((v) => s.isempty(v)), false);
  runSet('sentinels.isnode_unify', s.getprop(sentinels, 'isnode_unify'),
      arg1((v) => s.isnode(v)), false);
  runSet('sentinels.stringify_null', s.getprop(sentinels, 'stringify_null'),
      arg1((vin) => s.stringify(vin)), false);
}

void main(List<String> args) {
  var testfile = args.isNotEmpty ? args[0] : '../build/test/test.json';
  var raw = File(testfile).readAsStringSync();
  var alltests = jsonDecode(raw);
  var spec = s.getprop(alltests, 'struct');
  runAll(spec);
  for (var f in failures) {
    print(f);
  }
  print('\nPASS $npass  FAIL $nfail');
  if (nfail > 0) exitCode = 1;
}
