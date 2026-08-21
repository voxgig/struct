// The shared corpus, run on the shared runner.
//
// The in-situ runner - a private `fixJson`, `eqv`, `doMatch`, `matchval`,
// `resolveArgs`, `checkResult` and `handleError`, all of it this port's own
// copy of omni's algorithm - is gone. Every group is driven through
// voxgig/omni, so this file only says WHICH subject answers each group and
// with which flags.
//
// omni is consumed as a local checkout, wired in by `pubspec_overrides.yaml`
// which the Makefile generates from $OMNI_HOME. The published `pubspec.yaml`
// never names it, so nothing that depends on this package depends on omni
// (register 4.13).
//
// Flags mirror canonical: typescript/test/utility/StructUtility.test.ts.

import 'dart:io';

import 'package:voxgig_omni/omni.dart' as o;

import '../lib/voxgig_struct.dart' as s;

const nullmark = '__NULL__';

// ---------------------------------------------------------------------------
// The bridge
// ---------------------------------------------------------------------------

// omni's model and this port's are the same plain Dart types - Map, List, num,
// String, bool, null - so there is nothing to copy in either direction, and a
// node a subject mutates IS the node omni is holding. That is what makes
// `match.args` work here without omni's `runsetflags_args`: the in-place
// rewrite `minor/setpath` and `merge/integrity` assert on is directly visible.
//
// The one difference is omni's ABSENT, which this port spells `null` - it has
// a single null for both canonical `undefined` and JSON null, like the Python,
// Clojure and Lua ports. Shallow, because ABSENT only ever arrives as a whole
// argument: the spec data itself comes from JSON and has no absent in it.
dynamic tostruct(dynamic val) => o.isabsent(val) ? null : val;

// ---------------------------------------------------------------------------
// Result tracking
// ---------------------------------------------------------------------------

int npass = 0;
int nfail = 0;
List<String> failures = [];

void record(String group, bool ok, String msg) {
  if (ok) {
    npass++;
  } else {
    nfail++;
    failures.add('FAIL $group - $msg');
  }
}

String errmsg(Object err) => err is o.OmniError
    ? err.message
    : (err is s.StructError ? err.message : err.toString());

// ---------------------------------------------------------------------------
// Running a group
// ---------------------------------------------------------------------------

// Each group is one assertion: omni stops at its first failing entry and
// reports the index, the entry and both values.
void runSet(o.RunPack pack, String group, dynamic node, o.Subject subject,
    [bool flagNull = true]) {
  try {
    pack.runsetflags(node, o.Flags(nulls: flagNull, name: group), subject);
    record(group, true, '');
  } catch (e) {
    record(group, false, errmsg(e));
  }
}

// `merge.basic`, `inject.basic` and `transform.basic` are single entries, not
// sets, so the runner cannot drive them. Compared here, through omni's own
// deepequal so the rule is the one every group uses.
void runSingle(String group, dynamic node, dynamic Function(dynamic) actualFn) {
  try {
    final expected = s.getprop(node, 'out');
    final actual = actualFn(s.getprop(node, 'in'));
    if (o.deepequal(expected, actual)) {
      record(group, true, '');
    } else {
      record(group, false,
          'Expected: ${s.stringify(expected)}, got: ${s.stringify(actual)}');
    }
  } catch (e) {
    record(group, false, errmsg(e));
  }
}

// ---------------------------------------------------------------------------
// Arg helpers
// ---------------------------------------------------------------------------

o.Subject arg1(dynamic Function(dynamic) f) =>
    (args) => f(tostruct(args.isEmpty ? null : args[0]));

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

// ---------------------------------------------------------------------------
// Groups the runner cannot drive
// ---------------------------------------------------------------------------

void runWalkLog(String group, dynamic node) {
  try {
    final testData = s.clone(node);
    final log = <dynamic>[];
    dynamic walklog(key, v, parent, path) {
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
    final expected = s.getprop(s.getprop(testData, 'out'), 'after');
    if (o.deepequal(expected, log)) {
      record(group, true, '');
    } else {
      record(group, false,
          'Expected: ${s.stringify(expected)}, got: ${s.stringify(log)}');
    }
  } catch (e) {
    record(group, false, errmsg(e));
  }
}

dynamic walkCopySubject(dynamic vin) {
  final cur = <dynamic>[null];
  dynamic walkcopy(key, v, parent, path) {
    if (key == null) {
      cur[0] = [
        s.ismap(v) ? <String, dynamic>{} : (s.islist(v) ? <dynamic>[] : v)
      ];
      return v;
    }
    final i = s.size(path);
    dynamic nv;
    if (s.isnode(v)) {
      final c = cur[0] as List;
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
  final state = <String, dynamic>{'top': null, 'cur': null};
  dynamic copy(key, v, parent, path) {
    if (key == null || s.isnode(v)) {
      final child = s.islist(v) ? <dynamic>[] : <String, dynamic>{};
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

// ---------------------------------------------------------------------------
// Test groups
// ---------------------------------------------------------------------------

void runAll(o.RunPack pack, dynamic spec) {
  dynamic g(String k) => s.getprop(spec, k);
  final minor = g('minor');
  final walks = g('walk');
  final merges = g('merge');
  final getpaths = g('getpath');
  final injects = g('inject');
  final transforms = g('transform');
  final validates = g('validate');
  final selects = g('select');
  final sentinels = g('sentinels');
  final regexs = g('regex');
  dynamic mg(String n) => s.getprop(minor, n);

  void rs(String group, dynamic node, o.Subject subject,
          [bool flagNull = true]) =>
      runSet(pack, group, node, subject, flagNull);

  rs('minor.isnode', mg('isnode'), arg1((v) => s.isnode(v)));
  rs('minor.ismap', mg('ismap'), arg1((v) => s.ismap(v)));
  rs('minor.islist', mg('islist'), arg1((v) => s.islist(v)));
  rs('minor.iskey', mg('iskey'), arg1((v) => s.iskey(v)), false);
  rs('minor.strkey', mg('strkey'), arg1((v) => s.strkey(v)), false);
  rs('minor.isempty', mg('isempty'), arg1((v) => s.isempty(v)), false);
  rs('minor.isfunc', mg('isfunc'), arg1((v) => s.isfunc(v)));
  rs('minor.clone', mg('clone'), arg1((v) => s.clone(v)), false);
  rs('minor.escre', mg('escre'), arg1((v) => s.escre(v)));
  rs('minor.escurl', mg('escurl'), arg1((v) => s.escurl(v)));
  rs(
      'minor.stringify',
      mg('stringify'),
      arg1((vin) => vhas(vin, 'val')
          ? s.stringify(vget(vin, 'val'), vget(vin, 'max'))
          : s.stringify()),
      false);
  rs('minor.jsonify', mg('jsonify'),
      arg1((vin) => s.jsonify(vget(vin, 'val'), vget(vin, 'flags'))), false);
  rs('minor.getelem', mg('getelem'), arg1((vin) {
    final alt = vget(vin, 'alt');
    return alt == null
        ? s.getelem(vget(vin, 'val'), vget(vin, 'key'))
        : s.getelem(vget(vin, 'val'), vget(vin, 'key'), alt);
  }), false);
  rs('minor.delprop', mg('delprop'),
      arg1((vin) => s.delprop(vget(vin, 'parent'), vget(vin, 'key'))));
  rs('minor.size', mg('size'), arg1((v) => s.size(v)), false);
  rs(
      'minor.slice',
      mg('slice'),
      arg1((vin) =>
          s.slice(vget(vin, 'val'), vget(vin, 'start'), vget(vin, 'end'))),
      false);
  rs(
      'minor.pad',
      mg('pad'),
      arg1((vin) =>
          s.pad(vget(vin, 'val'), vget(vin, 'pad'), vget(vin, 'char'))),
      false);
  rs(
      'minor.pathify',
      mg('pathify'),
      arg1((vin) => vhas(vin, 'path')
          ? s.pathify(vget(vin, 'path'), vget(vin, 'from'))
          : s.pathify(s.pathifyNoArg, vget(vin, 'from'))),
      false);
  rs('minor.items', mg('items'), arg1((v) => s.items(v)));
  // Canonical omits `alt` only when the KEY is missing (`undefined ===
  // vin.alt`), so a present `alt: null` still goes through; getelem's rule is
  // the looser `null == vin.alt`. This port cannot tell the two apart - one
  // null for both - so it keeps the getelem reading here, which is what the
  // corpus's `minor/getprop#51` costs it. See the note in AGENTS.md.
  rs('minor.getprop', mg('getprop'), arg1((vin) {
    final alt = vget(vin, 'alt');
    return alt == null
        ? s.getprop(vget(vin, 'val'), vget(vin, 'key'))
        : s.getprop(vget(vin, 'val'), vget(vin, 'key'), alt);
  }), false);
  rs(
      'minor.setprop',
      mg('setprop'),
      arg1((vin) =>
          s.setprop(vget(vin, 'parent'), vget(vin, 'key'), vget(vin, 'val'))));
  rs('minor.haskey', mg('haskey'),
      arg1((vin) => s.haskey(vget(vin, 'src'), vget(vin, 'key'))), false);
  rs('minor.keysof', mg('keysof'), arg1((v) => s.keysof(v)));
  rs(
      'minor.join',
      mg('join'),
      arg1((vin) =>
          s.join(vget(vin, 'val'), vget(vin, 'sep'), vget(vin, 'url'))),
      false);
  // The one group that needs to tell "no argument" from "a null argument":
  // the corpus has both `{in: null, out: T_null}` and `{out: T_noval}`, and
  // omni supplies ABSENT for the second (register 4.12).
  rs(
      'minor.typify',
      mg('typify'),
      (args) => s.typify(
          (args.isEmpty || o.isabsent(args[0])) ? s.pathifyNoArg : args[0]),
      false);
  rs(
      'minor.setpath',
      mg('setpath'),
      arg1((vin) =>
          s.setpath(vget(vin, 'store'), vget(vin, 'path'), vget(vin, 'val'))),
      false);
  rs('minor.filter', mg('filter'), arg1((vin) {
    bool Function(List<dynamic>) check;
    final c = vget(vin, 'check');
    if (c == 'gt3') {
      check = (n) => n[1] is num && n[1] > 3;
    } else if (c == 'lt3') {
      check = (n) => n[1] is num && n[1] < 3;
    } else {
      check = (n) => false;
    }
    return s.filter(vget(vin, 'val'), check);
  }));
  rs('minor.typename', mg('typename'),
      arg1((v) => s.typename(v is num ? v.toInt() : 0)));
  rs('minor.flatten', mg('flatten'), arg1((vin) {
    final d = vget(vin, 'depth');
    return s.flatten(vget(vin, 'val'), d is num ? d.toInt() : 1);
  }));

  runWalkLog('walk.log', s.getprop(walks, 'log'));
  rs(
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
  rs('walk.copy', s.getprop(walks, 'copy'), arg1(walkCopySubject));
  rs('walk.depth', s.getprop(walks, 'depth'), arg1(walkDepthSubject), false);

  runSingle('merge.basic', s.getprop(merges, 'basic'),
      (in_) => s.merge(s.clone(in_)));
  rs('merge.cases', s.getprop(merges, 'cases'), arg1((v) => s.merge(v)));
  rs('merge.array', s.getprop(merges, 'array'), arg1((v) => s.merge(v)));
  rs('merge.integrity', s.getprop(merges, 'integrity'),
      arg1((v) => s.merge(v)));
  rs('merge.depth', s.getprop(merges, 'depth'),
      arg1((vin) => s.merge(vget(vin, 'val'), vget(vin, 'depth'))));

  rs('getpath.basic', s.getprop(getpaths, 'basic'),
      arg1((vin) => s.getpath(vget(vin, 'store'), vget(vin, 'path'))));
  rs('getpath.relative', s.getprop(getpaths, 'relative'), arg1((vin) {
    final dp = vget(vin, 'dpath');
    final dpath = dp is String ? dp.split('.') : null;
    final injdef = {'dparent': vget(vin, 'dparent'), 'dpath': dpath};
    return s.getpath(vget(vin, 'store'), vget(vin, 'path'), injdef);
  }));
  rs(
      'getpath.special',
      s.getprop(getpaths, 'special'),
      arg1((vin) =>
          s.getpath(vget(vin, 'store'), vget(vin, 'path'), vget(vin, 'inj'))));
  rs('getpath.handler', s.getprop(getpaths, 'handler'), arg1((vin) {
    final store = {'\$TOP': vget(vin, 'store'), '\$FOO': () => 'foo'};
    dynamic handler(inj, val, ref, st) => s.isfunc(val) ? val() : val;
    return s.getpath(store, vget(vin, 'path'), {'handler': handler});
  }));

  runSingle(
      'inject.basic',
      s.getprop(injects, 'basic'),
      (in_) => s.inject(
          s.clone(s.getprop(in_, 'val')), s.clone(s.getprop(in_, 'store'))));
  rs(
      'inject.string',
      s.getprop(injects, 'string'),
      arg1((vin) => s.inject(vget(vin, 'val'), vget(vin, 'store'),
          {'modify': nullModifier, 'extra': vget(vin, 'current')})));
  rs('inject.deep', s.getprop(injects, 'deep'),
      arg1((vin) => s.inject(vget(vin, 'val'), vget(vin, 'store'))));

  runSingle('transform.basic', s.getprop(transforms, 'basic'),
      (in_) => s.transform(s.getprop(in_, 'data'), s.getprop(in_, 'spec')));
  for (final gn in ['paths', 'cmds', 'each', 'pack', 'ref']) {
    rs('transform.$gn', s.getprop(transforms, gn),
        arg1((vin) => s.transform(vget(vin, 'data'), vget(vin, 'spec'))));
  }
  rs('transform.modify', s.getprop(transforms, 'modify'), arg1((vin) {
    void modifier(v, key, parent, inj) {
      if (v is String && key != null && parent != null) {
        s.setprop(parent, key, '@' + v);
      }
    }

    return s.transform(vget(vin, 'data'), vget(vin, 'spec'),
        {'modify': modifier, 'extra': vget(vin, 'store')});
  }));
  rs('transform.format', s.getprop(transforms, 'format'),
      arg1((vin) => s.transform(vget(vin, 'data'), vget(vin, 'spec'))), false);
  rs('transform.apply', s.getprop(transforms, 'apply'),
      arg1((vin) => s.transform(vget(vin, 'data'), vget(vin, 'spec'))));

  rs('validate.basic', s.getprop(validates, 'basic'),
      arg1((vin) => s.validate(vget(vin, 'data'), vget(vin, 'spec'))), false);
  for (final gn in ['child', 'one', 'exact']) {
    rs('validate.$gn', s.getprop(validates, gn),
        arg1((vin) => s.validate(vget(vin, 'data'), vget(vin, 'spec'))));
  }
  rs('validate.invalid', s.getprop(validates, 'invalid'),
      arg1((vin) => s.validate(vget(vin, 'data'), vget(vin, 'spec'))), false);
  rs(
      'validate.special',
      s.getprop(validates, 'special'),
      arg1((vin) =>
          s.validate(vget(vin, 'data'), vget(vin, 'spec'), vget(vin, 'inj'))));

  for (final gn in ['basic', 'operators', 'edge', 'alts']) {
    rs('select.$gn', s.getprop(selects, gn),
        arg1((vin) => s.select(vget(vin, 'obj'), vget(vin, 'query'))));
  }
  // `null: false` keeps a JSON null an ACTUAL null rather than the NULLMARK
  // string, so select sees a present-but-null field.
  rs('select.nullkey', s.getprop(selects, 'nullkey'),
      arg1((vin) => s.select(vget(vin, 'obj'), vget(vin, 'query'))), false);

  // regex (parity floor: Go stdlib regexp — see design/REGEX_API.md)
  rs('regex.test', s.getprop(regexs, 'test'),
      arg1((vin) => s.re_test(vget(vin, 'pattern'), vget(vin, 'input'))));
  rs('regex.find', s.getprop(regexs, 'find'),
      arg1((vin) => s.re_find(vget(vin, 'pattern'), vget(vin, 'input'))));
  rs('regex.find_all', s.getprop(regexs, 'find_all'),
      arg1((vin) => s.re_find_all(vget(vin, 'pattern'), vget(vin, 'input'))));
  rs(
      'regex.replace',
      s.getprop(regexs, 'replace'),
      arg1((vin) => s.re_replace(
          vget(vin, 'pattern'), vget(vin, 'input'), vget(vin, 'replacement'))));
  rs('regex.escape', s.getprop(regexs, 'escape'),
      arg1((vin) => s.re_escape(vget(vin, 'val'))));

  rs(
      'sentinels.getprop_unify',
      s.getprop(sentinels, 'getprop_unify'),
      arg1((vin) =>
          s.getprop(vget(vin, 'val'), vget(vin, 'key'), vget(vin, 'alt'))),
      false);
  rs(
      'sentinels.getelem_absent',
      s.getprop(sentinels, 'getelem_absent'),
      arg1((vin) =>
          s.getelem(vget(vin, 'val'), vget(vin, 'key'), vget(vin, 'alt'))),
      false);
  rs('sentinels.haskey_unify', s.getprop(sentinels, 'haskey_unify'),
      arg1((vin) => s.haskey(vget(vin, 'val'), vget(vin, 'key'))), false);
  rs('sentinels.isempty_unify', s.getprop(sentinels, 'isempty_unify'),
      arg1((v) => s.isempty(v)), false);
  rs('sentinels.isnode_unify', s.getprop(sentinels, 'isnode_unify'),
      arg1((v) => s.isnode(v)), false);
  rs('sentinels.stringify_null', s.getprop(sentinels, 'stringify_null'),
      arg1((vin) => s.stringify(vin)), false);
}

// ---------------------------------------------------------------------------
// The client path
// ---------------------------------------------------------------------------

// `DEF.client`, client-scoped options, and `contextify`. This port had no such
// test. It is the only thing that exercises subject resolution through a
// PROVIDER rather than through a callback this file hands over - so nothing
// here had ever checked that a corpus `client` key resolves, or that a
// `DEF.client` entry's options reach the subject.
//
// The subject talks to omni DIRECTLY: the runner resolves it by name off the
// provider, so there is no `in` to convert and no result to convert back.
dynamic check(dynamic options, List<dynamic> args) {
  final foo = (options is Map) ? options['foo'] : null;
  final foos = (null == foo || o.isabsent(foo)) ? '' : o.stringify(foo);
  final ctx = args.isNotEmpty ? args[0] : null;
  final meta = (ctx is Map) ? ctx['meta'] : null;
  final bar = (meta is Map) ? meta['bar'] : null;
  final bars = (null == bar || o.isabsent(bar)) ? '0' : o.stringify(bar);
  return <String, dynamic>{'zed': 'ZED${foos}_$bars'};
}

o.Provider clientProvider(dynamic options) => o.Provider(
      subject: (name) =>
          'check' == name ? (args) => check(options, args) : null,
      // A DEF.client entry becomes another provider, carrying its options.
      client: clientProvider,
      // This port adds nothing to a context; the hook must exist so omni
      // installs `client` on it.
      contextify: (val) => val,
    );

void runClient(String testfile) {
  final pack = o
      .makeRunner(testfile, clientProvider(<String, dynamic>{}))
      .runner('check');
  try {
    // No subject: the runner resolves it by name off the provider, which is
    // the whole point of the group.
    pack.runsetflags(pack.set('basic'), const o.Flags(name: 'check.basic'));
    record('check.basic', true, '');
  } catch (e) {
    record('check.basic', false, errmsg(e));
  }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

void main(List<String> argv) {
  final testfile = argv.isNotEmpty ? argv[0] : '../build/test/test.json';
  final pack = o.makeRunner(testfile).runner('struct');
  runAll(pack, pack.spec);
  runClient(testfile);
  for (final f in failures) {
    print(f);
  }
  print('\n${npass + nfail} groups, $nfail failed');
  if (nfail > 0) exitCode = 1;
}
