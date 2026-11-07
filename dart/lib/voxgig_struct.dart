// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
//
// Voxgig Struct — Dart port.
//
// A faithful port of the canonical TypeScript implementation
// (typescript/src/StructUtility.ts), following the same "by-example" design.
// Like the Python, Clojure and Lua ports, Dart has a single `null`, so the
// canonical `undefined` and JSON `null` are both represented by `null`; the
// Group A/B rules (design/UNDEF_SPEC.md) recover the distinction where it
// matters, and a private NOARG sentinel distinguishes "no argument supplied".
//
// Nodes are native Dart collections — `Map<String, dynamic>` (a LinkedHashMap,
// insertion-ordered) and growable `List<dynamic>` — which are mutable and
// reference-stable, exactly as the algorithm requires. The only regex used is
// the Dart core `RegExp`. There are no third-party runtime dependencies.

// ---------------------------------------------------------------------------
// Sentinels / constants
// ---------------------------------------------------------------------------

class _NoArg {
  const _NoArg();
}

const _noarg = _NoArg();

/// Public alias for the "no argument supplied" sentinel, used by callers (e.g.
/// the test runner) to drive `pathify` with an *absent* value (not `null`).
const pathifyNoArg = _noarg;

class _Sentinel {
  final String tag;
  _Sentinel(this.tag);
}

final SKIP = _Sentinel('skip');
final DELETE = _Sentinel('delete');

const S_MKEYPRE = 'key:pre';
const S_MKEYPOST = 'key:post';
const S_MVAL = 'val';

const M_KEYPRE = 1;
const M_KEYPOST = 2;
const M_VAL = 4;

final Map<String, int> _MODE_TO_NUM = {
  S_MKEYPRE: M_KEYPRE,
  S_MKEYPOST: M_KEYPOST,
  S_MVAL: M_VAL,
};

const MODENAME = {M_VAL: 'val', M_KEYPRE: 'key:pre', M_KEYPOST: 'key:post'};

const S_DKEY = '\$KEY';
const S_BANNO = '`\$ANNO`';
const S_DTOP = '\$TOP';
const S_DERRS = '\$ERRS';
const S_DSPEC = '\$SPEC';
const S_BEXACT = '`\$EXACT`';
const S_BVAL = '`\$VAL`';
const S_BKEY = '`\$KEY`';
const S_BOPEN = '`\$OPEN`';

const S_MT = '';
const S_BT = '`';
const S_DS = '\$';
const S_DT = '.';
const S_CN = ':';
const S_KEY = 'KEY';
const S_VIZ = ': ';

const S_string = 'string';
const S_object = 'object';
const S_list = 'list';
const S_map = 'map';
const S_nil = 'nil';
const S_null = 'null';

const T_any = (1 << 31) - 1;
const T_noval = 1 << 30;
const T_boolean = 1 << 29;
const T_decimal = 1 << 28;
const T_integer = 1 << 27;
const T_number = 1 << 26;
const T_string = 1 << 25;
const T_function = 1 << 24;
const T_null = 1 << 22;
const T_list = 1 << 14;
const T_map = 1 << 13;
const T_instance = 1 << 12;
const T_scalar = 1 << 7;
const T_node = 1 << 6;

const _TYPENAME = [
  'any',
  'nil',
  'boolean',
  'decimal',
  'integer',
  'number',
  'string',
  'function',
  'symbol',
  'null',
  '',
  '',
  '',
  '',
  '',
  '',
  '',
  'list',
  'map',
  'instance',
  '',
  '',
  '',
  '',
  'scalar',
  'node'
];

const MAXDEPTH = 32;

final _R_INJECT_FULL = RegExp(r'^`(\$[A-Z]+|[^`]*)[0-9]*`$');
final _R_INJECT_PART = RegExp(r'`([^`]*)`');
final _R_META_PATH = RegExp(r'^([^$]+)\$([=~])(.+)$');
final _R_TRANSFORM_NAME = RegExp(r'`\$([A-Z]+)`');
final _R_CHECKER_NAME = RegExp(r'^\$[A-Z]+$');

// ---------------------------------------------------------------------------
// Low-level helpers
// ---------------------------------------------------------------------------

bool isSkip(dynamic v) => identical(v, SKIP);
bool isDelete(dynamic v) => identical(v, DELETE);

bool _isInteger(num n) =>
    n is int || (n is double && n.isFinite && n == n.truncateToDouble());

String numToString(num n) {
  if (n is double) {
    if (n.isNaN) return 'NaN';
    if (n.isInfinite) return n > 0 ? 'Infinity' : '-Infinity';
    if (n == n.truncateToDouble() && n.abs() < 1e16)
      return n.toInt().toString();
    return n.toString();
  }
  return n.toString();
}

String jsString(dynamic v) {
  if (v == null) return 'null';
  if (v is bool) return v ? 'true' : 'false';
  if (v is num) return numToString(v);
  if (v is String) return v;
  if (v is List) return v.map((x) => (x == null) ? '' : jsString(x)).join(',');
  if (v is Map) return '[object Object]';
  if (v is Function) return 'function';
  return v.toString();
}

String _mapKey(dynamic k) =>
    k is String ? k : (k is num ? numToString(k) : jsString(k));

int? _toInt(dynamic k) {
  if (k is bool) return null;
  if (k is int) return k;
  if (k is double) return k.floor();
  if (k is String) return int.tryParse(k.trim());
  return null;
}

int _clz32(int n0) {
  var n = n0 & 0xFFFFFFFF;
  if (n == 0) return 32;
  var r = 0;
  while ((n & 0x80000000) == 0) {
    r++;
    n = (n << 1) & 0xFFFFFFFF;
  }
  return r;
}

// ---------------------------------------------------------------------------
// Minor utilities
// ---------------------------------------------------------------------------

bool isnode(dynamic v) => v is Map || v is List;
bool ismap(dynamic v) => v is Map;
bool islist(dynamic v) => v is List;
bool isfunc(dynamic v) => v is Function;

bool iskey(dynamic k) {
  if (k is String) return k.isNotEmpty;
  if (k is bool) return false;
  if (k is num) return true;
  return false;
}

bool isempty([dynamic v]) {
  if (v == null) return true;
  if (v == '') return true;
  if (v is List) return v.isEmpty;
  if (v is Map) return v.isEmpty;
  return false;
}

dynamic getdef(dynamic v, dynamic alt) => v == null ? alt : v;

int typify([dynamic value = _noarg]) {
  if (identical(value, _noarg)) return T_noval;
  if (value == null) return T_scalar | T_null;
  if (value is bool) return T_scalar | T_boolean;
  if (value is int) return T_scalar | T_number | T_integer;
  if (value is double) {
    if (value.isNaN) return T_noval;
    if (value == value.truncateToDouble())
      return T_scalar | T_number | T_integer;
    return T_scalar | T_number | T_decimal;
  }
  if (value is num) return T_scalar | T_number | T_integer;
  if (value is String) return T_scalar | T_string;
  if (value is Function) return T_scalar | T_function;
  if (value is List) return T_node | T_list;
  if (value is Map) return T_node | T_map;
  return T_node | T_instance;
}

String typename([int t = 0]) {
  var i = _clz32(t);
  return (i >= 0 && i < _TYPENAME.length) ? _TYPENAME[i] : _TYPENAME[0];
}

int size([dynamic v]) {
  if (v is List) return v.length;
  if (v is Map) return v.length;
  if (v is String) return v.length;
  if (v is bool) return v ? 1 : 0;
  if (v is num) return v.floor();
  return 0;
}

String strkey([dynamic key]) {
  if (key == null) return S_MT;
  if (key is String) return key;
  if (key is bool) return S_MT;
  if (key is num)
    return _isInteger(key)
        ? numToString(key)
        : numToString(key.floorToDouble());
  return S_MT;
}

List<String> keysof([dynamic v]) {
  if (v is Map) {
    var ks = v.keys.map((k) => k.toString()).toList();
    ks.sort();
    return ks;
  }
  if (v is List) return List.generate(v.length, (i) => i.toString());
  return [];
}

dynamic getprop(dynamic val, dynamic key, [dynamic alt]) {
  if (val == null || key == null) return alt;
  dynamic out = alt;
  if (val is Map) {
    var sk = _mapKey(key);
    if (val.containsKey(sk)) out = val[sk];
  } else if (val is List) {
    var ki = _toInt(key);
    if (ki != null && ki >= 0 && ki < val.length) out = val[ki];
  }
  if (out == null || identical(out, _noarg)) return alt;
  return out;
}

dynamic _lookup(dynamic val, dynamic key) {
  if (val == null || key == null) return null;
  if (val is Map) {
    var sk = _mapKey(key);
    return val.containsKey(sk) ? val[sk] : null;
  }
  if (val is List) {
    var ki = _toInt(key);
    return (ki != null && ki >= 0 && ki < val.length) ? val[ki] : null;
  }
  return null;
}

bool haskey([dynamic val, dynamic key]) => getprop(val, key) != null;

final _R_INTKEY = RegExp(r'^-?[0-9]+$');

dynamic getelem(dynamic val, dynamic key, [dynamic alt]) {
  if (val == null || key == null) return alt;
  dynamic out;
  if (val is List) {
    var ks = key is String ? key : (key is num ? numToString(key) : '');
    if (_R_INTKEY.hasMatch(ks)) {
      var len = val.length;
      var nk0 = int.parse(ks);
      var nk = nk0 < 0 ? len + nk0 : nk0;
      if (nk >= 0 && nk < len) out = val[nk];
    }
  }
  if (out == null) {
    return isfunc(alt) ? alt() : alt;
  }
  return out;
}

dynamic _getpropRaw(dynamic v, String k) {
  if (v is Map) return v.containsKey(k) ? v[k] : null;
  if (v is List) {
    var i = int.tryParse(k);
    return (i != null && i >= 0 && i < v.length) ? v[i] : null;
  }
  return null;
}

List<List<dynamic>> itemsPairs(dynamic v) {
  if (!isnode(v)) return [];
  return keysof(v).map((k) => [k, _getpropRaw(v, k)]).toList();
}

dynamic items([dynamic v]) =>
    itemsPairs(v).map((p) => <dynamic>[p[0], p[1]]).toList();

dynamic itemsV(dynamic v, dynamic Function(List<dynamic>) f) =>
    itemsPairs(v).map(f).toList();

dynamic flatten(dynamic l, [int depth = 1]) {
  if (l is! List) return l;
  var out = <dynamic>[];
  for (var item in l) {
    if (item is List && depth > 0) {
      for (var x in (flatten(item, depth - 1) as List)) {
        out.add(x);
      }
    } else {
      out.add(item);
    }
  }
  return out;
}

dynamic filter(dynamic val, bool Function(List<dynamic>) check) {
  var out = <dynamic>[];
  for (var p in itemsPairs(val)) {
    if (check(p)) out.add(p[1]);
  }
  return out;
}

dynamic setprop(dynamic parent, dynamic key, dynamic val) {
  if (!iskey(key)) return parent;
  if (iscondensed(parent)) throw StructError(_CONDENSE_IMMUTABLE);
  if (parent is Map) {
    parent[_mapKey(key)] = val;
  } else if (parent is List) {
    var ki = _toInt(key is num ? key.floor() : key);
    if (ki == null) return parent;
    var len = parent.length;
    if (ki >= 0) {
      if (ki > len) ki = len;
      if (ki >= len) {
        parent.add(val);
      } else {
        parent[ki] = val;
      }
    } else {
      parent.insert(0, val);
    }
  }
  return parent;
}

dynamic delprop(dynamic parent, dynamic key) {
  if (!iskey(key)) return parent;
  if (iscondensed(parent)) throw StructError(_CONDENSE_IMMUTABLE);
  if (parent is Map) {
    parent.remove(_mapKey(key));
  } else if (parent is List) {
    var ki = _toInt(key);
    if (ki != null && ki >= 0 && ki < parent.length) parent.removeAt(ki);
  }
  return parent;
}

dynamic clone([dynamic v]) {
  if (v is Map) {
    var o = <String, dynamic>{};
    v.forEach((k, x) => o[k.toString()] = clone(x));
    return o;
  }
  if (v is List) {
    return v.map((x) => clone(x)).toList();
  }
  return v;
}

dynamic slice(dynamic val, [dynamic start, dynamic end, bool mutate = false]) {
  if (val is num) {
    num? lo = start is num ? start : null;
    num? hi = end is num ? (end - 1) : null;
    if (hi != null && val > hi) return hi;
    if (lo != null && val < lo) return lo;
    return val;
  }
  if (val is List || val is String) {
    var vlen = size(val);
    if (start == null && end != null) start = 0;
    if (start == null) return val;
    var s = (start as num).toInt();
    var e = 0;
    if (s < 0) {
      e = vlen + s;
      if (e < 0) e = 0;
      s = 0;
    } else if (end != null) {
      e = (end as num).toInt();
      if (e < 0) {
        e = vlen + e;
        if (e < 0) e = 0;
      } else if (vlen < e) {
        e = vlen;
      }
    } else {
      e = vlen;
    }
    if (vlen < s) s = vlen;
    if (s > -1 && s <= e && e <= vlen) {
      if (val is List) {
        if (mutate) {
          var sub = val.sublist(s, e);
          val
            ..clear()
            ..addAll(sub);
          return val;
        }
        return val.sublist(s, e);
      }
      return (val as String).substring(s, e);
    } else {
      if (val is List) {
        if (mutate) {
          val.clear();
          return val;
        }
        return <dynamic>[];
      }
      return S_MT;
    }
  }
  return val;
}

// ---------------------------------------------------------------------------
// Regex helpers (uniform re_* API over RegExp)
// ---------------------------------------------------------------------------

RegExp _rx(dynamic p) =>
    p is RegExp ? p : RegExp(p is String ? p : jsString(p));

dynamic re_compile(dynamic p, [dynamic flags]) => _rx(p);
dynamic re_test(dynamic p, dynamic input) =>
    _rx(p).hasMatch(input is String ? input : jsString(input));
dynamic re_find(dynamic p, dynamic input) {
  var m = _rx(p).firstMatch(input is String ? input : jsString(input));
  if (m == null) return null;
  return [for (var i = 0; i <= m.groupCount; i++) m.group(i) ?? ''];
}

dynamic re_find_all(dynamic p, dynamic input) {
  var out = <dynamic>[];
  for (var m in _rx(p).allMatches(input is String ? input : jsString(input))) {
    out.add([for (var i = 0; i <= m.groupCount; i++) m.group(i) ?? '']);
  }
  return out;
}

dynamic re_replace(dynamic p, dynamic input, dynamic repl) {
  var s = input is String ? input : jsString(input);
  if (repl is Function) {
    return s.replaceAllMapped(_rx(p), (m) {
      var groups = [for (var i = 0; i <= m.groupCount; i++) m.group(i) ?? ''];
      return (repl(groups)).toString();
    });
  }
  // String replacement with JS-style refs: $& (whole), $1..$9, $$ (literal $).
  var template = repl is String ? repl : jsString(repl);
  return s.replaceAllMapped(_rx(p), (m) {
    return template.replaceAllMapped(RegExp(r'\$(\$|&|[1-9])'), (t) {
      var ref = t.group(1)!;
      if (ref == r'$') return r'$';
      if (ref == '&') return m.group(0) ?? '';
      var gi = int.parse(ref);
      return gi <= m.groupCount ? (m.group(gi) ?? '') : '';
    });
  });
}

dynamic re_escape(dynamic s) => escre(s);

dynamic escre([dynamic s]) {
  var str = s is String ? s : (s == null ? S_MT : jsString(s));
  var b = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    var c = str[i];
    if ('.*+?^\$\{\}()|[]\\'.contains(c)) b.write('\\');
    b.write(c);
  }
  return b.toString();
}

const _urlUnreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*\'()';

dynamic escurl([dynamic s]) {
  var str = s is String ? s : (s == null ? S_MT : jsString(s));
  var b = StringBuffer();
  for (var byte in _utf8(str)) {
    var c = String.fromCharCode(byte);
    if (_urlUnreserved.contains(c)) {
      b.write(c);
    } else {
      b.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return b.toString();
}

List<int> _utf8(String s) {
  // Minimal UTF-8 encoder (avoids importing dart:convert in the library).
  var out = <int>[];
  for (var rune in s.runes) {
    if (rune < 0x80) {
      out.add(rune);
    } else if (rune < 0x800) {
      out.add(0xC0 | (rune >> 6));
      out.add(0x80 | (rune & 0x3F));
    } else if (rune < 0x10000) {
      out.add(0xE0 | (rune >> 12));
      out.add(0x80 | ((rune >> 6) & 0x3F));
      out.add(0x80 | (rune & 0x3F));
    } else {
      out.add(0xF0 | (rune >> 18));
      out.add(0x80 | ((rune >> 12) & 0x3F));
      out.add(0x80 | ((rune >> 6) & 0x3F));
      out.add(0x80 | (rune & 0x3F));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// JSON-ish serialization / stringify / jsonify
// ---------------------------------------------------------------------------

void _escJson(String s, StringBuffer b) {
  b.write('"');
  for (var i = 0; i < s.length; i++) {
    var c = s[i];
    var code = s.codeUnitAt(i);
    if (c == '"') {
      b.write('\\"');
    } else if (c == '\\') {
      b.write('\\\\');
    } else if (c == '\n') {
      b.write('\\n');
    } else if (c == '\r') {
      b.write('\\r');
    } else if (c == '\t') {
      b.write('\\t');
    } else if (code < 32) {
      b.write('\\u${code.toRadixString(16).padLeft(4, '0')}');
    } else {
      b.write(c);
    }
  }
  b.write('"');
}

String jsonEncode(dynamic v, {bool sort = false, int? indent}) {
  var b = StringBuffer();
  void enc(dynamic v, int level) {
    if (v == null) {
      b.write('null');
    } else if (v is bool) {
      b.write(v ? 'true' : 'false');
    } else if (v is num) {
      b.write(numToString(v));
    } else if (v is String) {
      _escJson(v, b);
    } else if (v is Function || v is _Sentinel) {
      b.write('null');
    } else if (v is List) {
      if (v.isEmpty) {
        b.write('[]');
      } else if (indent != null) {
        var pad = ' ' * (indent * (level + 1));
        var cpad = ' ' * (indent * level);
        b.write('[\n');
        for (var i = 0; i < v.length; i++) {
          if (i > 0) b.write(',\n');
          b.write(pad);
          enc(v[i], level + 1);
        }
        b.write('\n');
        b.write(cpad);
        b.write(']');
      } else {
        b.write('[');
        for (var i = 0; i < v.length; i++) {
          if (i > 0) b.write(',');
          enc(v[i], level + 1);
        }
        b.write(']');
      }
    } else if (v is Map) {
      var ks = v.keys.map((k) => k.toString()).toList();
      if (sort) ks.sort();
      if (ks.isEmpty) {
        b.write('{}');
      } else if (indent != null) {
        var pad = ' ' * (indent * (level + 1));
        var cpad = ' ' * (indent * level);
        b.write('{\n');
        for (var i = 0; i < ks.length; i++) {
          if (i > 0) b.write(',\n');
          b.write(pad);
          _escJson(ks[i], b);
          b.write(': ');
          enc(v[ks[i]], level + 1);
        }
        b.write('\n');
        b.write(cpad);
        b.write('}');
      } else {
        b.write('{');
        for (var i = 0; i < ks.length; i++) {
          if (i > 0) b.write(',');
          _escJson(ks[i], b);
          b.write(':');
          enc(v[ks[i]], level + 1);
        }
        b.write('}');
      }
    } else {
      _escJson(v.toString(), b);
    }
  }

  enc(v, 0);
  return b.toString();
}

bool _hasCycle(dynamic v) {
  // Identity set: O(1) membership. `add` returns false if already present,
  // which is exactly the previous "seen before" test (same add-never-remove
  // semantics as the old linear-scan list, but O(n) overall instead of O(n^2)).
  var seen = Set<dynamic>.identity();
  bool go(dynamic v) {
    if (v is List) {
      if (!seen.add(v)) return true;
      return v.any(go);
    }
    if (v is Map) {
      if (!seen.add(v)) return true;
      return v.values.any(go);
    }
    return false;
  }

  return go(v);
}

String stringify([dynamic v = _noarg, dynamic maxlen, dynamic pretty]) {
  var pr = pretty == true;
  if (identical(v, _noarg)) return pr ? '<>' : S_MT;
  String valstr;
  if (v is String) {
    valstr = v;
  } else if (_hasCycle(v)) {
    valstr = '__STRINGIFY_FAILED__';
  } else {
    try {
      valstr = jsonEncode(v, sort: true).replaceAll('"', '');
    } catch (_) {
      valstr = '__STRINGIFY_FAILED__';
    }
  }
  if (maxlen is num && maxlen > -1) {
    var m = maxlen.toInt();
    if (m < valstr.length) {
      valstr = valstr.substring(0, m - 3 < 0 ? 0 : m - 3) + '...';
    }
  }
  if (pr) {
    var colors = [
      81,
      118,
      213,
      39,
      208,
      201,
      45,
      190,
      129,
      51,
      160,
      121,
      226,
      33,
      207,
      69
    ];
    var c = colors.map((n) => '\x1b[38;5;${n}m').toList();
    var r = '\x1b[0m';
    var d = 0;
    var o = c[0];
    var t = StringBuffer(c[0]);
    for (var i = 0; i < valstr.length; i++) {
      var ch = valstr[i];
      if (ch == '{' || ch == '[') {
        d++;
        o = c[d % c.length];
        t.write(o);
        t.write(ch);
      } else if (ch == '}' || ch == ']') {
        t.write(o);
        t.write(ch);
        d--;
        o = c[((d % c.length) + c.length) % c.length];
      } else {
        t.write(o);
        t.write(ch);
      }
    }
    t.write(r);
    return t.toString();
  }
  return valstr;
}

String jsonify([dynamic v, dynamic flags]) {
  if (v == null) return S_null;
  var indent = getprop(flags, 'indent', 2);
  var ind = indent is num ? indent.toInt() : 2;
  try {
    var str = ind > 0 ? jsonEncode(v, indent: ind) : jsonEncode(v);
    var offset = getprop(flags, 'offset', 0);
    var off = offset is num ? offset.toInt() : 0;
    if (off > 0) {
      var lines = str.split('\n');
      if (lines.isNotEmpty) {
        return '{\n' + lines.sublist(1).map((l) => (' ' * off) + l).join('\n');
      }
    }
    return str;
  } catch (_) {
    return S_null;
  }
}

String pad([dynamic s, dynamic padding, dynamic padchar]) {
  var str = s is String ? s : (s == null ? 'null' : stringify(s));
  var p = padding is num ? padding.toInt() : 44;
  var pc = padchar is String ? (padchar + ' ').substring(0, 1) : ' ';
  if (p > -1) {
    var n = p - str.length;
    return n > 0 ? str + (pc * n) : str;
  } else {
    var n = (-p) - str.length;
    return n > 0 ? (pc * n) + str : str;
  }
}

// ---------------------------------------------------------------------------
// join / pathify / replace
// ---------------------------------------------------------------------------

String join(dynamic arr, [dynamic sep, dynamic url]) {
  if (arr is! List) return S_MT;
  var sepdef = (sep == null) ? ',' : (sep is String ? sep : jsString(sep));
  var single = sepdef.length == 1;
  var sc = single ? sepdef[0] : ' ';
  var isUrl = url == true;
  var sarr = arr.length;
  String stripTrailing(String s) {
    var i = s.length;
    while (i > 0 && s[i - 1] == sc) i--;
    return s.substring(0, i);
  }

  String stripLeading(String s) {
    var i = 0;
    while (i < s.length && s[i] == sc) i++;
    return s.substring(i);
  }

  String collapse(String s) {
    var b = StringBuffer();
    var i = 0;
    var n = s.length;
    while (i < n) {
      if (s[i] != sc) {
        b.write(s[i]);
        i++;
      } else {
        var j = i;
        while (j < n && s[j] == sc) j++;
        var beforeNon = i > 0 && s[i - 1] != sc;
        var afterNon = j < n;
        if (beforeNon && afterNon) {
          b.write(sc);
        } else {
          b.write(s.substring(i, j));
        }
        i = j;
      }
    }
    return b.toString();
  }

  var out = <String>[];
  for (var idx = 0; idx < arr.length; idx++) {
    var s0 = arr[idx];
    if (s0 is String && s0 != S_MT) {
      String s;
      if (single) {
        if (isUrl && idx == 0) {
          s = stripTrailing(s0);
        } else {
          var x = idx > 0 ? stripLeading(s0) : s0;
          x = (idx < sarr - 1 || !isUrl) ? stripTrailing(x) : x;
          s = collapse(x);
        }
      } else {
        s = s0;
      }
      if (s != S_MT) out.add(s);
    }
  }
  return out.join(sepdef);
}

String joinurl(dynamic arr) => join(arr, '/', true);

String replace(dynamic s, dynamic from, dynamic to) {
  var ts = typify(s);
  String rs;
  if ((T_string & ts) == 0) {
    rs = stringify(s);
  } else if (((T_noval | T_null) & ts) > 0) {
    rs = S_MT;
  } else {
    rs = stringify(s);
  }
  var toS = to is String ? to : jsString(to);
  if (from is String && from.isNotEmpty) return rs.replaceAll(from, toS);
  if (from is RegExp) return rs.replaceAll(from, toS);
  return rs;
}

String pathify([dynamic v = _noarg, dynamic startin, dynamic endin]) {
  var absent = identical(v, _noarg);
  var val = absent ? null : v;
  List<dynamic>? path;
  if (val is List) {
    path = val;
  } else if (iskey(val)) {
    path = [val];
  } else {
    path = null;
  }
  var start = startin is num ? (startin > -1 ? startin.toInt() : 0) : 0;
  var endn = endin is num ? (endin > -1 ? endin.toInt() : 0) : 0;
  String? pathstr;
  if (path != null && start >= 0) {
    var len = path.length;
    var e = len - endn;
    if (e < 0) e = 0;
    var s = start > len ? len : start;
    var sub = s <= e ? path.sublist(s, e) : <dynamic>[];
    if (sub.isEmpty) {
      pathstr = '<root>';
    } else {
      var mapped = sub.where(iskey).map((p) {
        if (p is num) return numToString(p.floorToDouble());
        return jsString(p).replaceAll('.', S_MT);
      });
      pathstr = mapped.join('.');
    }
  }
  if (pathstr == null) {
    pathstr =
        '<unknown-path' + (absent ? S_MT : S_CN + stringify(val, 47)) + '>';
  }
  return pathstr;
}

// ---------------------------------------------------------------------------
// walk / merge
// ---------------------------------------------------------------------------

dynamic walk(dynamic val,
    {Function? before,
    Function? after,
    dynamic maxdepth,
    dynamic key,
    dynamic parent,
    dynamic path}) {
  path ??= <dynamic>[];
  var depth = size(path);
  var out = before == null ? val : before(key, val, parent, path);
  var md = (maxdepth is num && maxdepth >= 0) ? maxdepth.toInt() : MAXDEPTH;
  if (md == 0 || (md > 0 && md <= depth)) return out;
  if (isnode(out)) {
    var prefix = List<dynamic>.from(path as List);
    for (var pair in itemsPairs(out)) {
      var ckey = pair[0] as String;
      var child = pair[1];
      var childpath = [...prefix, ckey];
      var result = walk(child,
          before: before,
          after: after,
          maxdepth: md,
          key: ckey,
          parent: out,
          path: childpath);
      if (out is Map) {
        out[ckey] = result;
      } else if (out is List) {
        out[int.parse(ckey)] = result;
      }
    }
  }
  return after == null ? out : after(key, out, parent, path);
}

dynamic merge(dynamic objs, [dynamic maxdepth]) {
  var md = maxdepth is num ? (maxdepth < 0 ? 0 : maxdepth.toInt()) : MAXDEPTH;
  if (objs is! List) return objs;
  var lenlist = objs.length;
  if (lenlist == 0) return null;
  if (lenlist == 1) return objs[0];
  dynamic out = getprop(objs, 0, <String, dynamic>{});
  for (var oi = 1; oi < lenlist; oi++) {
    var obj = objs[oi];
    if (!isnode(obj)) {
      out = obj;
    } else {
      var cur = <dynamic>[out];
      var dst = <dynamic>[out];
      void grow(List<dynamic> a, int n) {
        while (a.length <= n) a.add(null);
      }

      dynamic before(dynamic key, dynamic val, dynamic parent, dynamic path) {
        var pi = size(path);
        if (md <= pi) {
          grow(cur, pi);
          cur[pi] = val;
          if (pi > 0) setprop(cur[pi - 1], key, val);
          return null;
        } else if (!isnode(val)) {
          grow(cur, pi);
          cur[pi] = val;
          return val;
        } else {
          grow(dst, pi);
          grow(cur, pi);
          dst[pi] = pi > 0 ? getprop(dst[pi - 1], key) : dst[pi];
          var tval = dst[pi];
          if ((islist(val) && islist(tval)) || (ismap(val) && ismap(tval))) {
            cur[pi] = tval;
          } else {
            // Otherwise the override wins: it is copied, taking nothing from
            // the destination, so no later merge writes into it.
            cur[pi] = islist(val) ? <dynamic>[] : <String, dynamic>{};
            dst[pi] = null;
          }
          return val;
        }
      }

      dynamic after(dynamic key, dynamic val, dynamic parent, dynamic path) {
        var ci = size(path);
        if (ci < 1) return cur.isNotEmpty ? cur[0] : val;
        var target = ci - 1 < cur.length ? cur[ci - 1] : null;
        var value = ci < cur.length ? cur[ci] : null;
        setprop(target, key, value);
        // walk writes this back into the override, so it is the override's
        // own child, leaving the override unchanged.
        return _lookup(parent, key);
      }

      out = walk(obj, before: before, after: after);
    }
  }
  if (md == 0) {
    var o = getprop(objs, lenlist - 1);
    out = islist(o) ? <dynamic>[] : (ismap(o) ? <String, dynamic>{} : o);
  }
  return out;
}

// ---------------------------------------------------------------------------
// getpath / setpath
// ---------------------------------------------------------------------------

dynamic _idef(dynamic injdef, String field) {
  if (injdef is Inj) {
    switch (field) {
      case 'base':
        return injdef.base;
      case 'dparent':
        return injdef.dparent;
      case 'meta':
        return injdef.meta;
      case 'key':
        return injdef.key;
      case 'dpath':
        return injdef.dpath;
      case 'handler':
        return injdef.handler;
    }
    return null;
  }
  return getprop(injdef, field);
}

dynamic getpath(dynamic store, dynamic path, [dynamic injdef]) {
  List<dynamic>? parts;
  if (path is List) {
    parts = List<dynamic>.from(path);
  } else if (path is String) {
    parts = path.split(S_DT);
  } else if (path is num && path is! bool) {
    parts = [strkey(path)];
  } else {
    return null;
  }

  if (iscondensed(store)) {
    // Reads only the nodes on the path. A base changes what the path resolves
    // against, so that read walks the expanded copy instead.
    if (_idef(injdef, 'base') == null) {
      return _condenseMaterialise(
          store, _condenseResolve(store, store[_S_condroot], parts));
    }
    store = expand(store);
  }

  var hasInj = injdef != null;
  var base = _idef(injdef, 'base');
  var dparent = _idef(injdef, 'dparent');
  var injMeta = _idef(injdef, 'meta');
  var injKey = _idef(injdef, 'key');
  var dpath = _idef(injdef, 'dpath');
  var src = iskey(base) ? getprop(store, base, store) : store;
  var numparts = parts.length;
  dynamic val = store;

  if (path == null ||
      store == null ||
      (numparts == 1 && parts[0] == S_MT) ||
      numparts == 0) {
    val = src;
  } else {
    if (numparts == 1) val = getprop(store, parts[0]);
    if (!isfunc(val)) {
      val = src;
      if (parts[0] is String) {
        var m = _R_META_PATH.firstMatch(parts[0]);
        if (m != null && injMeta != null && hasInj) {
          val = getprop(injMeta, m.group(1));
          parts[0] = m.group(3);
        }
      }
      var pi = 0;
      var cont = true;
      while (cont && val != null && pi < numparts) {
        var raw = parts[pi];
        dynamic part;
        if (hasInj && raw == S_DKEY) {
          part = injKey != null ? injKey : raw;
        } else if (raw is String && raw.startsWith('\$GET:')) {
          part = stringify(getpath(src, slice(raw, 5, -1)));
        } else if (raw is String && raw.startsWith('\$REF:')) {
          part = stringify(getpath(getprop(store, S_DSPEC), slice(raw, 5, -1)));
        } else if (hasInj && raw is String && raw.startsWith('\$META:')) {
          part = stringify(getpath(injMeta, slice(raw, 6, -1)));
        } else {
          part = raw;
        }
        part = part is String
            ? (part.contains('\$') ? part.replaceAll('\$\$', '\$') : part)
            : strkey(part);
        if (part == S_MT) {
          var ascends = 0;
          while (pi + 1 < parts.length && parts[pi + 1] == S_MT) {
            ascends++;
            pi++;
          }
          if (hasInj && ascends > 0) {
            if (pi == numparts - 1) ascends--;
            if (ascends == 0) {
              val = dparent;
            } else {
              var tail = parts.sublist(pi + 1);
              var fullpath = flatten([slice(dpath, -ascends), tail]);
              val = ascends <= size(dpath) ? getpath(store, fullpath) : null;
              cont = false;
            }
          } else {
            val = dparent;
          }
        } else {
          val = getprop(val, part);
        }
        if (cont) pi++;
      }
    }
  }

  var handler = _idef(injdef, 'handler');
  if (hasInj && isfunc(handler)) {
    var ref = pathify(path);
    if (injdef is Inj) {
      val = handler(injdef, val, ref, store);
    } else {
      val = handler(_dummyInj(), val, ref, store);
    }
  }
  return val;
}

dynamic setpath(dynamic store, dynamic path, dynamic val, [dynamic injdef]) {
  if (iscondensed(store)) throw StructError(_CONDENSE_IMMUTABLE);
  var ptype = typify(path);
  dynamic parts;
  if ((T_list & ptype) > 0) {
    parts = List<dynamic>.from(path as List);
  } else if ((T_string & ptype) > 0) {
    parts = (path as String).split(S_DT);
  } else if ((T_number & ptype) > 0) {
    parts = [path];
  } else {
    return null;
  }
  var base = injdef != null ? _idef(injdef, 'base') : null;
  var numparts = size(parts);
  var parent = iskey(base) ? getprop(store, base, store) : store;
  for (var pi = 0; pi < numparts - 1; pi++) {
    var pkey = getelem(parts, pi);
    var np = getprop(parent, pkey);
    if (!isnode(np)) {
      var nextpart = getelem(parts, pi + 1);
      np =
          (T_number & typify(nextpart)) > 0 ? <dynamic>[] : <String, dynamic>{};
      setprop(parent, pkey, np);
    }
    parent = np;
  }
  if (isDelete(val)) {
    delprop(parent, getelem(parts, -1));
  } else {
    setprop(parent, getelem(parts, -1), val);
  }
  return parent;
}

// ---------------------------------------------------------------------------
// Injection state
// ---------------------------------------------------------------------------

class Inj {
  String mode = S_MVAL;
  bool full = false;
  int keyi = 0;
  dynamic keys;
  dynamic key;
  dynamic ival;
  dynamic parent;
  dynamic path;
  dynamic nodes;
  Function handler = injectHandler;
  dynamic errs;
  dynamic meta;
  dynamic dparent;
  dynamic dpath;
  dynamic base;
  Function? modify;
  Inj? prior;
  dynamic extra;
  dynamic root;
}

Inj? _dummy;
Inj _dummyInj() {
  _dummy ??= _newInj(null, <String, dynamic>{S_DTOP: null});
  return _dummy!;
}

Inj _newInj(dynamic val, dynamic parent) {
  var i = Inj();
  i.mode = S_MVAL;
  i.full = false;
  i.keyi = 0;
  i.keys = [S_DTOP];
  i.key = S_DTOP;
  i.ival = val;
  i.parent = parent;
  i.path = [S_DTOP];
  i.nodes = [parent];
  i.handler = injectHandler;
  i.errs = <dynamic>[];
  i.meta = <String, dynamic>{};
  i.dparent = null;
  i.dpath = [S_DTOP];
  i.base = S_DTOP;
  i.modify = null;
  i.prior = null;
  i.extra = null;
  i.root = null;
  return i;
}

dynamic _injDescend(Inj inj) {
  if (inj.meta is Map) {
    var d = (inj.meta['__d'] is num) ? inj.meta['__d'] as num : 0;
    inj.meta['__d'] = d + 1;
  }
  var parentkey = getelem(inj.path, -2);
  if (inj.dparent == null) {
    if (size(inj.dpath) > 1) {
      inj.dpath = [...(inj.dpath as List), parentkey];
    }
  } else if (parentkey != null) {
    inj.dparent = getprop(inj.dparent, parentkey);
    var lastpart = getelem(inj.dpath, -1);
    if (lastpart == '\$:' + jsString(parentkey)) {
      inj.dpath = slice(inj.dpath, -1);
    } else {
      inj.dpath = [...(inj.dpath as List), parentkey];
    }
  }
  return inj.dparent;
}

Inj _injChild(Inj inj, int keyi, dynamic keys) {
  var key = strkey(getelem(keys, keyi));
  var val = inj.ival;
  var c = Inj();
  c.mode = inj.mode;
  c.full = inj.full;
  c.keyi = keyi;
  c.keys = keys;
  c.key = key;
  c.ival = getprop(val, key);
  c.parent = val;
  c.path = [...(inj.path as List), key];
  c.nodes = [...(inj.nodes as List), val];
  c.handler = inj.handler;
  c.errs = inj.errs;
  c.meta = inj.meta;
  c.base = inj.base;
  c.modify = inj.modify;
  c.prior = inj;
  c.dpath = [...(inj.dpath as List)];
  c.dparent = inj.dparent;
  c.extra = inj.extra;
  c.root = inj.root;
  return c;
}

dynamic _injSetval(Inj inj, dynamic val, [int ancestor = 1]) {
  dynamic target;
  dynamic key;
  if (ancestor < 2) {
    target = inj.parent;
    key = inj.key;
  } else {
    target = getelem(inj.nodes, -ancestor);
    key = getelem(inj.path, -ancestor);
  }
  if (val == null) return delprop(target, key);
  return setprop(target, key, val);
}

// ---------------------------------------------------------------------------
// inject
// ---------------------------------------------------------------------------

dynamic inject(dynamic val, dynamic store, [dynamic injdef]) {
  Inj inj;
  if (injdef is Inj) {
    inj = injdef;
  } else {
    var parent = <String, dynamic>{S_DTOP: val};
    inj = _newInj(val, parent);
    inj.dparent = store;
    inj.errs = getprop(store, S_DERRS, <dynamic>[]);
    if (inj.meta is Map) inj.meta['__d'] = 0;
    inj.root = parent;
    if (injdef != null) {
      if (getprop(injdef, 'modify') != null)
        inj.modify = getprop(injdef, 'modify');
      if (getprop(injdef, 'extra') != null)
        inj.extra = getprop(injdef, 'extra');
      if (getprop(injdef, 'meta') != null) inj.meta = getprop(injdef, 'meta');
      if (getprop(injdef, 'handler') != null)
        inj.handler = getprop(injdef, 'handler');
    }
  }

  _injDescend(inj);

  dynamic rv;
  if (isnode(val)) {
    List<dynamic> nodekeys;
    if (val is Map) {
      var ks = val.keys.map((k) => k.toString()).toList();
      var normal = ks.where((k) => !k.contains(S_DS)).toList()..sort();
      var trans = ks.where((k) => k.contains(S_DS)).toList()..sort();
      nodekeys = [...normal, ...trans];
    } else {
      nodekeys = List.generate((val as List).length, (i) => i.toString());
    }

    var nki = 0;
    while (nki < nodekeys.length) {
      var childinj = _injChild(inj, nki, List<dynamic>.from(nodekeys));
      var nodekey = childinj.key;
      childinj.mode = S_MKEYPRE;
      var prekey = _injectstr(jsString(nodekey), store, childinj);
      nodekeys = (childinj.keys as List).map((e) => jsString(e)).toList();
      if (prekey != null) {
        childinj.ival = getprop(val, prekey);
        childinj.mode = S_MVAL;
        inject(childinj.ival, store, childinj);
        nodekeys = (childinj.keys as List).map((e) => jsString(e)).toList();
        childinj.mode = S_MKEYPOST;
        _injectstr(jsString(nodekey), store, childinj);
        nodekeys = (childinj.keys as List).map((e) => jsString(e)).toList();
      }
      nki = childinj.keyi + 1;
    }
    rv = val;
  } else if (val is String) {
    inj.mode = S_MVAL;
    var nv = _injectstr(val, store, inj);
    if (!isSkip(nv)) _injSetval(inj, nv);
    rv = nv;
  } else {
    rv = val;
  }

  if (inj.modify != null && !isSkip(rv)) {
    var mkey = inj.key;
    var mparent = inj.parent;
    var mval = getprop(mparent, mkey);
    inj.modify!(mval, mkey, mparent, inj);
  }

  inj.ival = rv;

  // Literal presence: a list directive at the root can leave a null there.
  if (inj.prior == null && _has(inj.root, S_DTOP)) {
    return inj.root[S_DTOP];
  }
  if (inj.key == S_DTOP && inj.parent != null && haskey(inj.parent, S_DTOP)) {
    return getprop(inj.parent, S_DTOP);
  }
  return rv;
}

dynamic injectHandler(dynamic inj, dynamic val, dynamic ref, dynamic store) {
  var iscmd =
      isfunc(val) && (ref == null || (ref is String && ref.startsWith(S_DS)));
  if (iscmd) {
    return val(inj, val, ref, store);
  } else if ((inj as Inj).mode == S_MVAL && inj.full) {
    _injSetval(inj, val);
    return val;
  }
  return val;
}

dynamic _injectstr(String val, dynamic store, [Inj? inj]) {
  if (val == S_MT) return S_MT;
  var m = _R_INJECT_FULL.firstMatch(val);
  if (m != null) {
    if (inj != null) inj.full = true;
    var pathref0 = m.group(1)!;
    var pathref = pathref0.length > 3
        ? pathref0.replaceAll('\$BT', S_BT).replaceAll('\$DS', S_DS)
        : pathref0;
    return getpath(store, pathref, inj);
  }
  var out = val.replaceAllMapped(_R_INJECT_PART, (mm) {
    var ref0 = mm.group(1)!;
    var ref = ref0.length > 3
        ? ref0.replaceAll('\$BT', S_BT).replaceAll('\$DS', S_DS)
        : ref0;
    if (inj != null) inj.full = false;
    var found = getpath(store, ref, inj);
    if (found == null) return S_MT;
    if (found is String) return found == '__NULL__' ? 'null' : found;
    if (isfunc(found)) return S_MT;
    try {
      return jsonEncode(found);
    } catch (_) {
      return stringify(found);
    }
  });
  if (inj != null && isfunc(inj.handler)) {
    inj.full = true;
    return inj.handler(inj, out, val, store);
  }
  return out;
}

// ---------------------------------------------------------------------------
// transform commands
// ---------------------------------------------------------------------------

dynamic _transformDelete(dynamic inj, dynamic val, dynamic ref, dynamic store) {
  delprop((inj as Inj).parent, inj.key);
  return null;
}

dynamic _transformCopy(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  if (inj.mode == S_MKEYPRE || inj.mode == S_MKEYPOST) return inj.key;
  var out = _lookup(inj.dparent, inj.key);
  _injSetval(inj, out);
  return out;
}

dynamic _transformKey(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  if (inj.mode != S_MVAL) return null;
  var keyspec = _lookup(inj.parent, S_BKEY);
  if (keyspec != null) {
    delprop(inj.parent, S_BKEY);
    return getprop(inj.dparent, keyspec);
  }
  var anno = _lookup(inj.parent, S_BANNO);
  var fromanno = _lookup(anno, S_KEY);
  if (fromanno != null) return fromanno;
  return getelem(inj.path, -2);
}

dynamic _transformAnno(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  delprop((inj0 as Inj).parent, S_BANNO);
  return null;
}

dynamic _transformMerge(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  if (inj.mode == S_MKEYPRE) return inj.key;
  if (inj.mode == S_MKEYPOST) {
    var args0 = getprop(inj.parent, inj.key);
    var args = islist(args0) ? args0 : [args0];
    _injSetval(inj, null);
    var mergelist = flatten([
      [inj.parent],
      args,
      [clone(inj.parent)]
    ]);
    merge(mergelist);
    return inj.key;
  }
  return null;
}

dynamic _transformEach(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  if (islist(inj.keys)) slice(inj.keys, 0, 1, true);
  if (inj.mode != S_MVAL) return null;
  var parent = inj.parent;
  var srcpath = size(parent) > 1 ? getelem(parent, 1) : null;
  var childTm = size(parent) > 2 ? clone(getelem(parent, 2)) : null;
  var srcstore = getprop(store, inj.base, store);
  var src = getpath(srcstore, srcpath, inj);
  var tkey = getelem(inj.path, -2);
  var nodes = inj.nodes;
  var target = () {
    var t = getelem(nodes, -2);
    return t == null ? getelem(nodes, -1) : t;
  }();
  var tval = <dynamic>[];
  dynamic rval = <dynamic>[];
  if (isnode(src)) {
    if (src is List) {
      for (var _ in src) {
        tval.add(clone(childTm));
      }
    } else if (src is Map) {
      src.forEach((k, _) {
        var cc = clone(childTm);
        if (ismap(cc)) setprop(cc, S_BANNO, <String, dynamic>{S_KEY: k});
        tval.add(cc);
      });
    }
    var tcurrent = src is Map
        ? src.values.toList()
        : (src is List ? List<dynamic>.from(src) : src);
    if (tval.isNotEmpty) {
      var path = inj.path;
      var ckey = getelem(path, -2);
      var plist = path is List ? List<dynamic>.from(path) : <dynamic>[];
      var tpath =
          plist.isEmpty ? <dynamic>[] : plist.sublist(0, plist.length - 1);
      var dpath = <dynamic>[S_DTOP];
      if (srcpath is String && srcpath != S_MT) {
        for (var p in srcpath.split(S_DT)) {
          if (p != S_MT) dpath.add(p);
        }
      }
      if (ckey != null) dpath.add('\$:' + jsString(ckey));
      dynamic tcur = <String, dynamic>{jsString(ckey): tcurrent};
      if (size(tpath) > 1) {
        var pkey = getelem(path, -3, S_DTOP);
        dpath.add('\$:' + jsString(pkey));
        tcur = <String, dynamic>{jsString(pkey): tcur};
      }
      var tinj = _injChild(inj, 0, ckey != null ? [ckey] : <dynamic>[]);
      tinj.path = tpath;
      var nlist = nodes is List ? List<dynamic>.from(nodes) : <dynamic>[];
      tinj.nodes =
          nlist.isEmpty ? <dynamic>[] : nlist.sublist(0, nlist.length - 1);
      tinj.parent = size(tinj.nodes) > 0 ? getelem(tinj.nodes, -1) : null;
      if (ckey != null && tinj.parent != null) setprop(tinj.parent, ckey, tval);
      tinj.ival = tval;
      tinj.dpath = dpath;
      tinj.dparent = tcur;
      inject(tval, store, tinj);
      rval = tinj.ival;
    }
  }
  setprop(target, tkey, rval);
  return (islist(rval) && size(rval) > 0) ? getelem(rval, 0) : null;
}

dynamic _transformPack(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  if (inj.mode != S_MKEYPRE || inj.key is! String) return null;
  var parent = inj.parent;
  var path = inj.path;
  var nodes = inj.nodes;
  var argsVal = getprop(parent, inj.key);
  if (!islist(argsVal) || size(argsVal) < 2) return null;
  var srcpath = getelem(argsVal, 0);
  var origchildspec = getelem(argsVal, 1);
  var tkey = getelem(path, -2);
  var pathsize = size(path);
  var target = () {
    var t = getelem(nodes, pathsize - 2);
    return t == null ? getelem(nodes, pathsize - 1) : t;
  }();
  var srcstore = getprop(store, inj.base, store);
  var src0 = getpath(srcstore, srcpath, inj);
  dynamic src;
  if (!islist(src0)) {
    if (ismap(src0)) {
      var ns = <dynamic>[];
      for (var p in itemsPairs(src0)) {
        setprop(p[1], S_BANNO, <String, dynamic>{S_KEY: p[0]});
        ns.add(p[1]);
      }
      src = ns;
    } else {
      src = null;
    }
  } else {
    src = src0;
  }
  if (src == null) return null;
  var keypath = getprop(origchildspec, S_BKEY);
  var childspec = delprop(origchildspec, S_BKEY);
  var child = getprop(childspec, S_BVAL, childspec);
  var tval = <String, dynamic>{};
  for (var p in itemsPairs(src)) {
    var srckey = p[0];
    var srcnode = p[1];
    dynamic k;
    if (keypath == null) {
      k = srckey;
    } else if (keypath is String && keypath.startsWith(S_BT)) {
      k = inject(
          keypath,
          merge([
            <String, dynamic>{},
            store,
            <String, dynamic>{S_DTOP: srcnode}
          ], 1));
    } else {
      k = getpath(srcnode, keypath, inj);
    }
    var tchild = clone(child);
    setprop(tval, k, tchild);
    var anno = getprop(srcnode, S_BANNO);
    if (anno == null) {
      delprop(tchild, S_BANNO);
    } else {
      setprop(tchild, S_BANNO, anno);
    }
  }
  dynamic rval = <String, dynamic>{};
  if (!isempty(tval)) {
    var tsrc = <String, dynamic>{};
    var srcList = src is List ? src : <dynamic>[];
    for (var i = 0; i < srcList.length; i++) {
      var node = srcList[i];
      dynamic kn;
      if (keypath == null) {
        kn = i;
      } else if (keypath is String && keypath.startsWith(S_BT)) {
        kn = inject(
            keypath,
            merge([
              <String, dynamic>{},
              store,
              <String, dynamic>{S_DTOP: node}
            ], 1));
      } else {
        kn = getpath(node, keypath, inj);
      }
      setprop(tsrc, kn, node);
    }
    var tpath = slice(inj.path, -1);
    var ckey = getelem(inj.path, -2);
    var dpath = flatten(
        [S_DTOP, (srcpath as String).split(S_DT), '\$:' + jsString(ckey)]);
    dynamic tcur = <String, dynamic>{jsString(ckey): tsrc};
    if (size(tpath) > 1) {
      var pkey = getelem(inj.path, -3, S_DTOP);
      (dpath as List).add('\$:' + jsString(pkey));
      tcur = <String, dynamic>{jsString(pkey): tcur};
    }
    var tinj = _injChild(inj, 0, [ckey]);
    tinj.path = tpath;
    tinj.nodes = slice(inj.nodes, -1);
    tinj.parent = getelem(tinj.nodes, -1);
    tinj.ival = tval;
    tinj.dpath = dpath;
    tinj.dparent = tcur;
    inject(tval, store, tinj);
    rval = tinj.ival;
  }
  setprop(target, tkey, rval);
  return null;
}

dynamic _transformRef(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  if (inj.mode != S_MVAL) return null;
  var nodes = inj.nodes;
  var refpath = _lookup(inj.parent, 1);
  inj.keyi = size(inj.keys);
  var specFunc = getprop(store, S_DSPEC);
  if (!isfunc(specFunc)) return null;
  var spec = specFunc();
  var refv = getpath(spec, refpath);
  var hasSub = false;
  if (isnode(refv)) {
    walk(refv, after: (k, v, p, pp) {
      if (v == '`\$REF`') hasSub = true;
      return v;
    });
  }
  var tref = clone(refv);
  var cpath = slice(inj.path, 0, size(inj.path) - 3);
  var tpath = slice(inj.path, 0, size(inj.path) - 1);
  var tcur = getpath(store, cpath);
  var tval = getpath(store, tpath);
  dynamic rval;
  if (refv != null && (!hasSub || tval != null)) {
    var cs = _injChild(inj, 0, [getelem(tpath, -1)]);
    cs.path = tpath;
    cs.nodes = slice(inj.nodes, 0, size(inj.nodes) - 1);
    cs.parent = getelem(nodes, -2);
    cs.ival = tref;
    cs.dparent = tcur;
    inject(tref, store, cs);
    rval = cs.ival;
  }
  _injSetval(inj, rval, 2);
  if (islist(inj.parent) && inj.prior != null) {
    inj.prior!.keyi = inj.prior!.keyi - 1;
  }
  return val;
}

String _jsstr(dynamic v) {
  if (v == null) return 'null';
  if (v is bool) return v ? 'true' : 'false';
  return jsString(v);
}

final Map<String, dynamic Function(dynamic, dynamic)> _FORMATTER = {
  'identity': (k, v) => v,
  'upper': (k, v) => isnode(v) ? v : _jsstr(v).toUpperCase(),
  'lower': (k, v) => isnode(v) ? v : _jsstr(v).toLowerCase(),
  'string': (k, v) => isnode(v) ? v : _jsstr(v),
  'number': (k, v) {
    if (isnode(v)) return v;
    var n = num.tryParse(_jsstr(v)) ?? 0;
    if (n is double && n.isNaN) n = 0;
    return (n == n.truncateToDouble()) ? n.toInt() : n;
  },
  'integer': (k, v) {
    if (isnode(v)) return v;
    var n = num.tryParse(_jsstr(v)) ?? 0;
    if (n is double && n.isNaN) n = 0;
    return n.toInt();
  },
  'concat': (k, v) {
    if (k == null && islist(v)) {
      return join(itemsV(v, (n) => isnode(n[1]) ? S_MT : _jsstr(n[1])), S_MT);
    }
    return v;
  },
};

bool checkPlacement(int modes, String ijname, int parentTypes, Inj inj) {
  var modenum = _MODE_TO_NUM[inj.mode] ?? 0;
  if ((modes & modenum) == 0) {
    var allowed = [M_KEYPRE, M_KEYPOST, M_VAL].where((m) => (modes & m) != 0);
    var placements = allowed.map((m) => m == M_VAL ? 'value' : 'key').join(',');
    var cur = modenum == M_VAL ? 'value' : 'key';
    setprop(inj.errs, size(inj.errs),
        '\$$ijname: invalid placement as $cur, expected: $placements.');
    return false;
  }
  if (!isempty(parentTypes)) {
    var ptype = typify(inj.parent);
    if ((parentTypes & ptype) == 0) {
      setprop(inj.errs, size(inj.errs),
          '\$$ijname: invalid placement in parent ${typename(ptype)}, expected: ${typename(parentTypes)}.');
      return false;
    }
  }
  return true;
}

dynamic injectorArgs(List<int> argTypes, dynamic args) {
  var numargs = argTypes.length;
  var found = List<dynamic>.filled(1 + numargs, null, growable: true);
  for (var argi = 0; argi < numargs; argi++) {
    var arg = getelem(args, argi);
    var argType = typify(arg);
    if ((argTypes[argi] & argType) == 0) {
      found[0] =
          'invalid argument: ${stringify(arg, 22)} (${typename(argType)} at position ${1 + argi}) is not of type: ${typename(argTypes[argi])}.';
      return found;
    }
    found[1 + argi] = arg;
  }
  return found;
}

Inj injectChild(dynamic child, dynamic store, Inj inj) {
  var cinj = inj;
  if (inj.prior != null) {
    if (inj.prior!.prior != null) {
      var c = _injChild(inj.prior!.prior!, inj.prior!.keyi, inj.prior!.keys);
      c.ival = child;
      setprop(c.parent, inj.prior!.key, child);
      cinj = c;
    } else {
      var c = _injChild(inj.prior!, inj.keyi, inj.keys);
      c.ival = child;
      setprop(c.parent, inj.key, child);
      cinj = c;
    }
  }
  inject(child, store, cinj);
  return cinj;
}

dynamic _transformFormat(
    dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  slice(inj.keys, 0, 1, true);
  if (inj.mode != S_MVAL) return null;
  var name = _lookup(inj.parent, 1);
  var child = _lookup(inj.parent, 2);
  var tkey = getelem(inj.path, -2);
  var target = () {
    var t = getelem(inj.nodes, -2);
    return t == null ? getelem(inj.nodes, -1) : t;
  }();
  var cinj = injectChild(child, store, inj);
  var resolved = cinj.ival;
  dynamic Function(dynamic, dynamic)? formatter;
  if ((T_function & typify(name)) > 0) {
    formatter = (k, v) => name(_dummyInj(), v, jsString(k), null);
  } else {
    formatter = _FORMATTER[jsString(name)];
  }
  if (formatter == null) {
    setprop(inj.errs, size(inj.errs),
        '\$FORMAT: unknown format: ${jsString(name)}.');
    return null;
  }
  var out = walk(resolved, after: (k, v, p, pp) => formatter!(k, v));
  setprop(target, tkey, out);
  return out;
}

dynamic _transformApply(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  if (!checkPlacement(M_VAL, 'APPLY', T_list, inj)) return null;
  var res = injectorArgs([T_function, T_any], slice(inj.parent, 1));
  var err = getelem(res, 0);
  var applyFn = getelem(res, 1);
  var child = size(res) > 2 ? getelem(res, 2) : null;
  if (err != null) {
    setprop(inj.errs, size(inj.errs), '\$APPLY: ' + jsString(err));
    return null;
  }
  var tkey = getelem(inj.path, -2);
  var target = () {
    var t = getelem(inj.nodes, -2);
    return t == null ? getelem(inj.nodes, -1) : t;
  }();
  var cinj = injectChild(child, store, inj);
  var resolved = cinj.ival;
  var out = applyFn(resolved, store, cinj);
  setprop(target, tkey, out);
  return out;
}

dynamic transform(dynamic data, dynamic spec0, [dynamic injdef]) {
  var origspec = spec0;
  var spec = clone(spec0);
  var extra = injdef != null ? getprop(injdef, 'extra') : null;
  var collect = injdef != null && getprop(injdef, 'errs') != null;
  var errs = collect ? getprop(injdef, 'errs') : <dynamic>[];
  var extraTransforms = <String, dynamic>{};
  var extraData = <String, dynamic>{};
  if (extra != null) {
    for (var p in itemsPairs(extra)) {
      if ((p[0] as String).startsWith(S_DS)) {
        extraTransforms[p[0]] = p[1];
      } else {
        extraData[p[0]] = p[1];
      }
    }
  }
  var dataClone =
      merge([isempty(extraData) ? null : clone(extraData), clone(data)]);
  var store = <String, dynamic>{};
  store[S_DTOP] = dataClone;
  store[S_DSPEC] = ([a, b, c, d]) => origspec;
  store['\$BT'] = ([a, b, c, d]) => S_BT;
  store['\$DS'] = ([a, b, c, d]) => S_DS;
  store['\$WHEN'] = ([a, b, c, d]) => '1970-01-01T00:00:00.000Z';
  store['\$DELETE'] = _transformDelete;
  store['\$COPY'] = _transformCopy;
  store['\$KEY'] = _transformKey;
  store['\$ANNO'] = _transformAnno;
  store['\$MERGE'] = _transformMerge;
  store['\$EACH'] = _transformEach;
  store['\$PACK'] = _transformPack;
  store['\$REF'] = _transformRef;
  store['\$FORMAT'] = _transformFormat;
  store['\$APPLY'] = _transformApply;
  for (var p in itemsPairs(extraTransforms)) {
    store[p[0]] = p[1];
  }
  store[S_DERRS] = errs;

  var idef = <String, dynamic>{};
  if (injdef is Map) {
    injdef.forEach((k, v) => idef[k.toString()] = v);
  }
  idef['errs'] = errs;
  var out = inject(spec, store, idef);
  if (size(errs) > 0 && !collect) {
    throw StructError(join(errs, ' | '));
  }
  return out;
}

class StructError implements Exception {
  final String message;
  StructError(this.message);
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// validate
// ---------------------------------------------------------------------------

String _invalidTypeMsg(
    dynamic path, String needtype, int vt, dynamic v, String whence) {
  final novalue = v == null || identical(v, _noarg);
  var vs = novalue ? 'no value' : stringify(v);
  return 'Expected ' +
      (size(path) > 1 ? 'field ' + pathify(path, 1) + ' to be ' : '') +
      needtype +
      ', but found ' +
      (novalue ? '' : typename(vt) + S_VIZ) +
      vs +
      '.';
}

void _pushErr(Inj inj, String msg) => setprop(inj.errs, size(inj.errs), msg);

dynamic _validateString(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  var out = _lookup(inj.dparent, inj.key);
  var t = typify(out);
  if ((T_string & t) == 0) {
    _pushErr(inj, _invalidTypeMsg(inj.path, S_string, t, out, 'V1010'));
    return null;
  }
  if (out == S_MT) {
    _pushErr(inj, 'Empty string at ' + pathify(inj.path, 1));
    return null;
  }
  return out;
}

dynamic _validateType(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  var tname = (ref is String && ref.length > 1)
      ? ref.substring(1).toLowerCase()
      : 'any';
  var idx = _TYPENAME.indexOf(tname);
  var typev0 = idx >= 0 ? (1 << (31 - idx)) : 0;
  var typev = tname == S_nil ? (typev0 | T_null) : typev0;
  var out = _lookup(inj.dparent, inj.key);
  var t = typify(out);
  if ((t & typev) == 0) {
    _pushErr(inj, _invalidTypeMsg(inj.path, tname, t, out, 'V1001'));
    return null;
  }
  return out;
}

dynamic _validateAny(dynamic inj0, dynamic val, dynamic ref, dynamic store) =>
    _lookup((inj0 as Inj).dparent, inj0.key);

dynamic _validateChild(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  var parent = inj.parent;
  var key = inj.key;
  var path = inj.path;
  var keys = inj.keys;
  if (inj.mode == S_MKEYPRE) {
    var childtm = getprop(parent, key);
    var pkey = getelem(path, -2);
    var tval = getprop(inj.dparent, pkey);
    if (tval == null) {
      for (var ckey in keysof(<String, dynamic>{})) {
        setprop(parent, ckey, clone(childtm));
        setprop(keys, size(keys), ckey);
      }
      delprop(parent, key);
      return null;
    } else if (!ismap(tval)) {
      _pushErr(
          inj,
          _invalidTypeMsg(slice(path, 0, size(path) - 1), S_object,
              typify(tval), tval, 'V0220'));
      return null;
    } else {
      for (var ckey in keysof(tval)) {
        setprop(parent, ckey, clone(childtm));
        setprop(keys, size(keys), ckey);
      }
      delprop(parent, key);
      return null;
    }
  } else if (inj.mode == S_MVAL) {
    var childtm = getprop(parent, 1);
    if (!islist(parent)) {
      _pushErr(inj, 'Invalid \$CHILD as value');
      return null;
    } else if (inj.dparent == null) {
      (parent as List).clear();
      return null;
    } else if (!islist(inj.dparent)) {
      _pushErr(
          inj,
          _invalidTypeMsg(slice(path, 0, size(path) - 1), S_list,
              typify(inj.dparent), inj.dparent, 'V0230'));
      inj.keyi = size(parent);
      return inj.dparent;
    } else {
      for (var p in itemsPairs(inj.dparent)) {
        setprop(parent, p[0], clone(childtm));
      }
      var n = size(inj.dparent);
      var pl = parent as List;
      while (pl.length > n) {
        pl.removeLast();
      }

      // NOTE: modifying inj! This extends the child value loop in inject
      // to cover every cloned child.
      for (var ckeyi = size(keys); ckeyi < size(parent); ckeyi++) {
        setprop(keys, size(keys), strkey(ckeyi));
      }

      // Restart the child value loop at the first element (the loop
      // increments keyi on resume) so that the first element is also
      // validated against the child template.
      inj.keyi = -1;

      // SKIP leaves the cloned child template in place at the first
      // element so the resumed loop can validate it.
      return SKIP;
    }
  }
  return null;
}

dynamic _validateExact(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  if (inj.mode != S_MVAL) {
    delprop(inj.parent, inj.key);
    return null;
  }
  var parent = inj.parent;
  if (!islist(parent) || inj.keyi != 0) {
    _pushErr(
        inj,
        'The \$EXACT validator at field ' +
            pathify(inj.path, 1, 1) +
            ' must be the first element of an array.');
    return null;
  }
  var cval = _slotval(inj);
  var has = _slothas(inj);
  inj.keyi = size(inj.keys);

  // Replace [$EXACT, ...] with the data value; SKIP keeps inject off the
  // detached list.
  _setslot(inj, cval, has);

  inj.path = slice(inj.path, 0, size(inj.path) - 1);
  var tvals = slice(parent, 1) as List;
  if (tvals.isEmpty) {
    _pushErr(
        inj,
        'The \$EXACT validator at field ' +
            pathify(inj.path, 1, 1) +
            ' must have at least one argument.');
    return SKIP;
  }
  for (var tv in tvals) {
    if (has && veq(tv, cval)) return SKIP;
  }
  _pushErr(
      inj,
      _invalidTypeMsg(
          inj.path,
          (size(inj.path) > 1 ? '' : 'value ') +
              'exactly equal to ' +
              (tvals.length == 1 ? '' : 'one of ') +
              _valdesc(tvals),
          typify(cval),
          cval,
          'V0110'));
  return SKIP;
}

// Count the specs that admit the value: ['`$NOF`', count, spec, ...], where
// count is an integer, or a map holding min, max or both.
dynamic _validateNof(dynamic inj0, dynamic val, dynamic ref, dynamic store) =>
    _validatecount(inj0 as Inj, store, '\$NOF', true);

// Every spec admits the value: ['`$ALL`', spec, ...].
dynamic _validateAll(dynamic inj0, dynamic val, dynamic ref, dynamic store) =>
    _validatecount(inj0 as Inj, store, '\$ALL', false);

// The counting list directives. Without a count, every spec has to admit.
dynamic _validatecount(Inj inj, dynamic store, String name, bool counted) {
  if (inj.mode != S_MVAL) return null;
  var parent = inj.parent;
  if (!islist(parent) || inj.keyi != 0) {
    _pushErr(
        inj,
        'The ' +
            name +
            ' validator at field ' +
            pathify(inj.path, 1, 1) +
            ' must be the first element of an array.');
    return null;
  }

  var cval = _slotval(inj);
  var has = _slothas(inj);
  inj.keyi = size(inj.keys);

  // Replace the directive's list with the data value. Each return is SKIP, so
  // that inject leaves the detached list alone and validates nothing in it.
  _setslot(inj, cval, has);

  inj.path = slice(inj.path, 0, size(inj.path) - 1);

  var count = counted ? _lookup(parent, 1) : null;
  var tvals = slice(parent, counted ? 2 : 1) as List;
  var numtvals = tvals.length;
  var field = 'The ' + name + ' validator at field ' + pathify(inj.path, 1);

  if (numtvals == 0) {
    _pushErr(
        inj,
        field +
            (counted ? ' must have a count and' : ' must have') +
            ' at least one argument.');
    return SKIP;
  }

  List<dynamic> nc = counted
      ? _nofcount(count, numtvals)
      : <dynamic>[numtvals, numtvals, 'all'];
  num lo = nc[0];
  num hi = nc[1];
  var countdesc = nc[2];

  if (countdesc == null) {
    _pushErr(inj, field + ' has an invalid count: ' + stringify(count) + '.');
    return SKIP;
  }

  var admitted = 0;
  for (var ti = 0; ti < numtvals; ti++) {
    var left = numtvals - ti;

    // Stop once the specs left cannot change the verdict.
    if (hi < admitted ||
        admitted + left < lo ||
        (lo <= admitted && admitted + left <= hi)) {
      break;
    }

    if (_admits(cval, has, tvals[ti], inj, store)) {
      admitted++;
    }
  }

  if (admitted < lo || hi < admitted) {
    _pushErr(
        inj,
        _invalidTypeMsg(inj.path, '$countdesc of ' + _valdesc(tvals),
            typify(cval), cval, 'V0310'));
  }

  return SKIP;
}

// The specs as a message lists them, each `$NAME` as its lower-case name.
String _valdesc(List tvals) =>
    join(tvals.map((x) => stringify(x)).toList(), ', ').replaceAllMapped(
        _R_TRANSFORM_NAME, (m) => m.group(1)!.toLowerCase());

bool veq(dynamic a, dynamic b) {
  if (a == null && b == null) return true;
  if (a is bool || b is bool) return a == b;
  if (a is num && b is num) return a == b;
  if (a is String && b is String) return a == b;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!veq(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (var k in a.keys) {
      if (!b.containsKey(k) || !veq(a[k], b[k])) return false;
    }
    return true;
  }
  return identical(a, b);
}

void _validation(dynamic pval, dynamic key, dynamic parent, dynamic inj0) {
  var inj = inj0 as Inj;
  if (isSkip(pval)) return;
  var exact = getprop(inj.meta, S_BEXACT, false);
  var cval = getprop(inj.dparent, key);
  var exactB = exact == true;
  if (!exactB && cval == null) return;
  var ptype = typify(pval);
  if ((T_string & ptype) > 0 && jsString(pval).contains(S_DS)) return;
  var ctype = typify(cval);
  if (ptype != ctype && pval != null) {
    _pushErr(
        inj, _invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0010'));
  } else if (ismap(cval)) {
    if (!ismap(pval)) {
      _pushErr(inj,
          _invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0020'));
    } else {
      var ckeys = keysof(cval);
      var pkeys = keysof(pval);
      if (pkeys.isNotEmpty && getprop(pval, S_BOPEN) != true) {
        // Literal presence: the shape declares ck even when its value is null.
        // Canonical uses `NONE === _lookup`; `_lookup(...) == null` conflates
        // present-null with absent and drops null-field records from open selects.
        var badkeys = ckeys
            .where((ck) => !(pval is Map && pval.containsKey(_mapKey(ck))))
            .toList();
        if (badkeys.isNotEmpty) {
          _pushErr(
              inj,
              'Unexpected keys at field ' +
                  pathify(inj.path, 1) +
                  S_VIZ +
                  badkeys.join(', '));
        }
      } else {
        merge([pval, cval]);
        if (isnode(pval)) delprop(pval, S_BOPEN);
      }
    }
  } else if (islist(cval)) {
    if (!islist(pval)) {
      _pushErr(inj,
          _invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0030'));
    }
  } else if (exactB) {
    if (!veq(cval, pval)) {
      var pathmsg =
          size(inj.path) > 1 ? 'at field ' + pathify(inj.path, 1) + ': ' : '';
      _pushErr(
          inj,
          'Value ' +
              pathmsg +
              jsString(cval) +
              ' should equal ' +
              jsString(pval) +
              '.');
    }
  } else {
    setprop(parent, key, cval);
  }
}

dynamic _validateHandler(
    dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  var m = (ref is String) ? _R_META_PATH.firstMatch(ref) : null;
  if (m != null) {
    if (m.group(2) == '=') {
      _injSetval(inj, [S_BEXACT, val]);
    } else {
      _injSetval(inj, val);
    }
    inj.keyi = -1;
    return SKIP;
  }
  return injectHandler(inj, val, ref, store);
}

dynamic validate(dynamic data, dynamic spec, [dynamic injdef]) {
  var extra = getprop(injdef, 'extra');
  var collect = injdef != null && getprop(injdef, 'errs') != null;
  var errs = collect ? getprop(injdef, 'errs') : <dynamic>[];
  var base = <String, dynamic>{};
  for (var k in [
    '\$DELETE',
    '\$COPY',
    '\$KEY',
    '\$META',
    '\$MERGE',
    '\$EACH',
    '\$PACK'
  ]) {
    base[k] = null;
  }
  base['\$STRING'] = _validateString;
  for (var k in [
    '\$NUMBER',
    '\$INTEGER',
    '\$DECIMAL',
    '\$BOOLEAN',
    '\$NULL',
    '\$NIL',
    '\$MAP',
    '\$LIST',
    '\$FUNCTION',
    '\$INSTANCE'
  ]) {
    base[k] = _validateType;
  }
  base['\$ANY'] = _validateAny;
  base['\$CHILD'] = _validateChild;
  base['\$EXACT'] = _validateExact;
  base['\$NOF'] = _validateNof;
  base['\$ALL'] = _validateAll;
  var store = merge([
    base,
    extra == null ? <String, dynamic>{} : extra,
    <String, dynamic>{S_DERRS: errs}
  ], 1);
  var meta = getprop(injdef, 'meta', <String, dynamic>{});
  setprop(meta, S_BEXACT, getprop(meta, S_BEXACT, false));

  // A spec that names an unknown checker validates nothing.
  var numerrs = size(errs);
  _checknames(spec, store, <dynamic>[], errs);

  var out = numerrs < size(errs)
      ? clone(data)
      : transform(data, spec, {
          'meta': meta,
          'extra': store,
          'modify': _validation,
          'handler': _validateHandler,
          'errs': errs,
        });
  if (size(errs) > 0 && !collect) {
    throw StructError(join(errs, ' | '));
  }
  return out;
}

// Names a validate spec may use besides its checkers: transform's that it
// keeps, and $OPEN.
const _VALIDATE_NAMES = [
  '\$TOP',
  '\$SPEC',
  '\$BT',
  '\$DS',
  '\$WHEN',
  '\$ANNO',
  '\$REF',
  '\$FORMAT',
  '\$APPLY',
  '\$OPEN',
];

// Report each checker the spec names that validate lacks; $EXACT's arguments
// are literals.
void _checknames(
    dynamic spec, dynamic store, List<dynamic> path, dynamic errs) {
  var name = _refname(spec);
  if (name != null) {
    if (_unknownname(name, store)) {
      setprop(errs, size(errs),
          'Unknown validator ' + name + ' at field ' + pathify(path) + '.');
    }
    return;
  }

  if (islist(spec) && _refname(_lookup(spec, 0)) == '\$EXACT') return;

  for (var key in keysof(spec)) {
    if (ismap(spec)) _checknames(key, store, path, errs);
    _checknames(_lookup(spec, key), store, [...path, key], errs);
  }
}

// The name a whole-string reference gives, when it is a checker name in any
// case.
String? _refname(dynamic val) {
  var m = val is String ? _R_INJECT_FULL.firstMatch(val) : null;
  return m != null && _R_CHECKER_NAME.hasMatch(m.group(1)!.toUpperCase())
      ? m.group(1)
      : null;
}

// Unknown: undefined and upper case, or a defined name in another case. Null
// disables a name.
bool _unknownname(String name, dynamic store) {
  bool known(String n) =>
      _VALIDATE_NAMES.contains(n) || _lookup(store, n) != null;
  var upper = name.toUpperCase();
  return !known(name) && (upper == name || known(upper));
}

// Whether key is present in val, a null value included.
bool _has(dynamic val, dynamic key) {
  if (val is Map) return val.containsKey(_mapKey(key));
  if (val is List) {
    var ki = _toInt(key);
    return ki != null && ki >= 0 && ki < val.length;
  }
  return false;
}

// The data value at a list directive's slot. The directive's own dparent was
// read with getprop, which reports a stored null as absent. A trial hands an
// absent value down as _noarg, which holds no value.
dynamic _slotval(Inj inj) {
  final prior = inj.prior;
  final val = prior == null ? inj.dparent : _lookup(prior.dparent, prior.key);
  return identical(val, _noarg) ? null : val;
}

// Whether the slot holds a value: with one null, _slotval cannot say.
bool _slothas(Inj inj) {
  final prior = inj.prior;
  final val = prior == null ? inj.dparent : _lookup(prior.dparent, prior.key);
  if (identical(val, _noarg)) return false;
  return prior == null ? val != null : _has(prior.dparent, prior.key);
}

// Set the slot that holds a list directive, as setval(val, 2) does. An absent
// value deletes the slot; _injSetval deletes on null too, and here a null is
// a value.
void _setslot(Inj inj, dynamic val, bool has) {
  if (has && val == null) {
    setprop(getelem(inj.nodes, -2), getelem(inj.path, -2), null);
  } else {
    _injSetval(inj, val, 2);
  }
}

// Every member val has is in out, unchanged, compared as JSON by veq. A member
// only out has is a default the spec supplied, and is ignored.
bool _keeps(dynamic val, dynamic out) {
  if (!isnode(val) || islist(val) != islist(out) || !isnode(out)) {
    return veq(val, out);
  }
  for (var k in keysof(val)) {
    if (!_has(out, k) || !_keeps(_lookup(val, k), _lookup(out, k))) {
      return false;
    }
  }
  return true;
}

// A spec admits a value when validating the value against it finds no error
// and gives back the value as it is. An absent value has nothing to give
// back, and goes down as _noarg so that the nested validation reads it as no
// value.
bool _admits(dynamic val, bool has, dynamic spec, Inj inj, dynamic store) {
  final tval = has ? val : _noarg;
  var terrs = <dynamic>[];
  var vstore = merge([<String, dynamic>{}, store], 1);
  setprop(vstore, S_DTOP, tval);
  var out = validate(
      tval, spec, {'extra': vstore, 'errs': terrs, 'meta': inj.meta});
  return size(terrs) == 0 && (!has || _keeps(val, out));
}

// The bounds of a $NOF count, and the words for it, which are null when the
// count is invalid. Without a max, the bound is the number of specs.
List<dynamic> _nofcount(dynamic count, int numtvals) {
  bool isnat(dynamic n) => n is num && _isInteger(n) && n >= 0;

  if (isnat(count)) {
    return <dynamic>[
      count,
      count,
      count == 0 ? 'none' : 'exactly ' + numToString(count)
    ];
  }

  var min = _lookup(count, 'min');
  var max = _lookup(count, 'max');
  var hasmin = _has(count, 'min');
  var hasmax = _has(count, 'max');

  var valid = ismap(count) &&
      size(count) > 0 &&
      size(count) == (hasmin ? 1 : 0) + (hasmax ? 1 : 0) &&
      (!hasmin || isnat(min)) &&
      (!hasmax || isnat(max)) &&
      (!hasmin || !hasmax || min <= max);

  if (!valid) return <dynamic>[0, 0, null];

  num lo = hasmin ? min : 0;
  num hi = hasmax ? max : numtvals;

  var desc = !hasmax
      ? 'at least ' + numToString(lo)
      : hi == 0
          ? 'none'
          : !hasmin
              ? 'at most ' + numToString(hi)
              : lo == hi
                  ? 'exactly ' + numToString(lo)
                  : numToString(lo) + ' to ' + numToString(hi);

  return <dynamic>[lo, hi, desc];
}

// ---------------------------------------------------------------------------
// select
// ---------------------------------------------------------------------------

dynamic _selectAnd(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  if (inj.mode == S_MKEYPRE) {
    var terms = getprop(inj.parent, inj.key);
    var ppath = slice(inj.path, -1);
    var point = getpath(store, ppath);
    var vstore = merge([<String, dynamic>{}, store], 1);
    setprop(vstore, S_DTOP, point);
    for (var p in itemsPairs(terms)) {
      var terrs = <dynamic>[];
      validate(point, p[1], {'extra': vstore, 'errs': terrs, 'meta': inj.meta});
      if (size(terrs) != 0) {
        _pushErr(
            inj,
            'AND:' +
                pathify(ppath) +
                '⨯' +
                stringify(point) +
                ' fail:' +
                stringify(terms));
      }
    }
    var gkey = getelem(inj.path, -2);
    var gp = getelem(inj.nodes, -2);
    setprop(gp, gkey, point);
  }
  return null;
}

dynamic _selectOr(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  if (inj.mode == S_MKEYPRE) {
    var terms = getprop(inj.parent, inj.key);
    var ppath = slice(inj.path, -1);
    var point = getpath(store, ppath);
    var vstore = merge([<String, dynamic>{}, store], 1);
    setprop(vstore, S_DTOP, point);
    var done = false;
    for (var p in itemsPairs(terms)) {
      if (done) break;
      var terrs = <dynamic>[];
      validate(point, p[1], {'extra': vstore, 'errs': terrs, 'meta': inj.meta});
      if (size(terrs) == 0) {
        var gkey = getelem(inj.path, -2);
        var gp = getelem(inj.nodes, -2);
        setprop(gp, gkey, point);
        done = true;
      }
    }
    if (!done) {
      _pushErr(
          inj,
          'OR:' +
              pathify(ppath) +
              '⨯' +
              stringify(point) +
              ' fail:' +
              stringify(terms));
    }
  }
  return null;
}

dynamic _selectNot(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  if (inj.mode == S_MKEYPRE) {
    var term = getprop(inj.parent, inj.key);
    var ppath = slice(inj.path, -1);
    var point = getpath(store, ppath);
    var vstore = merge([<String, dynamic>{}, store], 1);
    setprop(vstore, S_DTOP, point);
    var terrs = <dynamic>[];
    validate(point, term, {'extra': vstore, 'errs': terrs, 'meta': inj.meta});
    if (size(terrs) == 0) {
      _pushErr(
          inj,
          'NOT:' +
              pathify(ppath) +
              '⨯' +
              stringify(point) +
              ' fail:' +
              stringify(term));
    }
    var gkey = getelem(inj.path, -2);
    var gp = getelem(inj.nodes, -2);
    setprop(gp, gkey, point);
  }
  return null;
}

bool _numCmp(dynamic a, dynamic b, String op) {
  if (a is num && b is num) {
    switch (op) {
      case 'gt':
        return a > b;
      case 'lt':
        return a < b;
      case 'gte':
        return a >= b;
      case 'lte':
        return a <= b;
    }
  }
  return false;
}

dynamic _selectCmp(dynamic inj0, dynamic val, dynamic ref, dynamic store) {
  var inj = inj0 as Inj;
  if (inj.mode == S_MKEYPRE) {
    var term = getprop(inj.parent, inj.key);
    var gkey = getelem(inj.path, -2);
    var ppath = slice(inj.path, -1);
    var point = getpath(store, ppath);
    bool pass;
    if (ref == '\$GT') {
      pass = _numCmp(point, term, 'gt');
    } else if (ref == '\$LT') {
      pass = _numCmp(point, term, 'lt');
    } else if (ref == '\$GTE') {
      pass = _numCmp(point, term, 'gte');
    } else if (ref == '\$LTE') {
      pass = _numCmp(point, term, 'lte');
    } else if (ref == '\$LIKE') {
      pass = term is String ? RegExp(term).hasMatch(stringify(point)) : false;
    } else {
      pass = false;
    }
    if (pass) {
      var gp = getelem(inj.nodes, -2);
      setprop(gp, gkey, point);
    } else {
      _pushErr(
          inj,
          'CMP: ' +
              pathify(ppath) +
              '⨯' +
              stringify(point) +
              ' fail:' +
              jsString(ref) +
              ' ' +
              stringify(term));
    }
  }
  return null;
}

dynamic select(dynamic children0, dynamic query) {
  if (!isnode(children0)) return <dynamic>[];
  dynamic children;
  if (ismap(children0)) {
    children = itemsPairs(children0).map((p) {
      setprop(p[1], S_DKEY, p[0]);
      return p[1];
    }).toList();
  } else {
    var src = children0 as List;
    var out = <dynamic>[];
    for (var i = 0; i < src.length; i++) {
      var n = src[i];
      if (ismap(n)) {
        setprop(n, S_DKEY, i);
        out.add(n);
      } else {
        out.add(n);
      }
    }
    children = out;
  }
  var results = <dynamic>[];
  var extra = <String, dynamic>{
    '\$AND': _selectAnd,
    '\$OR': _selectOr,
    '\$NOT': _selectNot,
    '\$GT': _selectCmp,
    '\$LT': _selectCmp,
    '\$GTE': _selectCmp,
    '\$LTE': _selectCmp,
    '\$LIKE': _selectCmp,
  };
  var q = clone(query);
  walk(q, after: (k, v, p, pp) {
    if (ismap(v)) setprop(v, S_BOPEN, getprop(v, S_BOPEN, true));
    return v;
  });
  for (var child in (children as List)) {
    var errs = <dynamic>[];
    var injdef = {
      'errs': errs,
      'meta': <String, dynamic>{S_BEXACT: true},
      'extra': extra,
    };
    validate(child, clone(q), injdef);
    if (size(errs) == 0) results.add(child);
  }
  return results;
}

// ---------------------------------------------------------------------------
// condense
// ---------------------------------------------------------------------------

const _CONDENSE_VERSION = 1;
const _CONDENSE_MAP = 0;
const _CONDENSE_LIST = 1;
const _CONDENSE_STR = 2;
const _CONDENSE_NUM = 3;
const _CONDENSE_TRUE = 4;
const _CONDENSE_FALSE = 5;
const _CONDENSE_NULL = 6;

const _S_condense = '\$condense';
const _S_condsym = 'sym';
const _S_condnode = 'node';
const _S_condroot = 'root';

const _CONDENSE_IMMUTABLE = 'struct: condensed structures are immutable - '
    'expand() first, then modify the copy';

final _R_CONDENSE_INDEX = RegExp(r'^(0|[1-9][0-9]*)$');

// Code-point order, the order the format sorts symbols in. String.compareTo
// orders by code unit, which would put U+10000 before U+FFFF.
int _condenseCmp(String a, String b) {
  final ra = a.runes.iterator;
  final rb = b.runes.iterator;
  while (true) {
    final hasa = ra.moveNext();
    final hasb = rb.moveNext();
    if (!hasa || !hasb) return hasa ? 1 : (hasb ? -1 : 0);
    if (ra.current != rb.current) return ra.current < rb.current ? -1 : 1;
  }
}

// The version has to match, not merely be a number: a later format read with
// this one's schema would decode wrongly without failing.
bool iscondensed([dynamic val]) {
  if (val is! Map) return false;
  final v = val[_S_condense];
  return v is num &&
      v == _CONDENSE_VERSION &&
      val[_S_condsym] is List &&
      val[_S_condnode] is List &&
      val[_S_condroot] is num;
}

void _condenseCollect(dynamic val, Set<String> acc) {
  if (val is Map) {
    val.forEach((k, v) {
      acc.add(k.toString());
      _condenseCollect(v, acc);
    });
  } else if (val is List) {
    for (final x in val) {
      _condenseCollect(x, acc);
    }
  } else if (val is String) {
    acc.add(val);
  }
}

// An integral number keys as its integer, so 1 and 1.0 share one node.
String _condenseNumKey(num n) {
  final d = n.toDouble();
  return d == d.truncateToDouble() && d.abs() < 9007199254740992.0
      ? d.toInt().toString()
      : d.toString();
}

dynamic condense(dynamic val) {
  final symset = <String>{};
  _condenseCollect(val, symset);
  final sym = symset.toList()..sort(_condenseCmp);
  final symid = <String, int>{};
  for (var i = 0; i < sym.length; i++) {
    symid[sym[i]] = i;
  }

  final node = <dynamic>[];
  final seen = <String, int>{};

  int intern(List<dynamic> enc) {
    final enckey =
        enc.map((x) => x is num ? _condenseNumKey(x) : '$x').join(',');
    final hit = seen[enckey];
    if (hit != null) return hit;
    seen[enckey] = node.length;
    node.add(enc);
    return node.length - 1;
  }

  // Post-order, so a subtree is interned before its parent refers to it, and
  // map pairs in ascending symbol id, so that a lookup can bisect them.
  int build(dynamic n) {
    if (n is Map) {
      final enc = <dynamic>[_CONDENSE_MAP];
      final keys = n.keys.map((k) => k.toString()).toList()
        ..sort(_condenseCmp);
      for (final k in keys) {
        enc.add(symid[k]);
        enc.add(build(n[k]));
      }
      return intern(enc);
    }
    if (n is List) {
      final enc = <dynamic>[_CONDENSE_LIST];
      for (final x in n) {
        enc.add(build(x));
      }
      return intern(enc);
    }
    if (n is String) return intern(<dynamic>[_CONDENSE_STR, symid[n]]);
    if (n is num) return intern(<dynamic>[_CONDENSE_NUM, n]);
    if (n == true) return intern(<dynamic>[_CONDENSE_TRUE]);
    if (n == false) return intern(<dynamic>[_CONDENSE_FALSE]);
    return intern(<dynamic>[_CONDENSE_NULL]);
  }

  final root = build(val);

  return <String, dynamic>{
    _S_condense: _CONDENSE_VERSION,
    _S_condsym: List<dynamic>.from(sym),
    _S_condnode: node,
    _S_condroot: root,
  };
}

int? _condenseIndex(dynamic idx) {
  if (idx is int) return idx;
  if (idx is double &&
      idx.isFinite &&
      idx == idx.truncateToDouble() &&
      idx.abs() < 4294967296.0) {
    return idx.toInt();
  }
  return null;
}

bool _condenseFound(dynamic idx) => idx is num && 0 <= idx;

dynamic _condenseSym(dynamic cond, dynamic id) {
  final sym = cond is Map ? cond[_S_condsym] : null;
  final i = _condenseIndex(id);
  return sym is List && i != null && 0 <= i && i < sym.length ? sym[i] : null;
}

// Node idx as the list of its encoding, or null when there is no such node.
List<dynamic>? _condenseEnc(dynamic cond, dynamic idx) {
  final node = cond is Map ? cond[_S_condnode] : null;
  final i = _condenseIndex(idx);
  if (node is! List || i == null || i < 0 || i >= node.length) return null;
  final enc = node[i];
  if (enc == null) return null;
  return enc is List ? enc : <dynamic>[];
}

dynamic _condenseKind(List<dynamic> enc) => enc.isEmpty ? null : enc[0];

int _condenseSymId(dynamic cond, String key) {
  final sym = cond is Map ? cond[_S_condsym] : null;
  if (sym is! List) return -1;
  var lo = 0;
  var hi = sym.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final s = sym[mid];
    if (s == key) return mid;
    if (s is String && _condenseCmp(s, key) < 0) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return -1;
}

dynamic _condenseChild(dynamic cond, dynamic idx, dynamic key) {
  final enc = _condenseEnc(cond, idx);
  if (enc == null) return -1;
  final kind = _condenseKind(enc);

  if (kind == _CONDENSE_MAP) {
    final symid = _condenseSymId(cond, jsString(key));
    if (symid < 0) return -1;
    var lo = 0;
    var hi = (enc.length - 1) ~/ 2 - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final k = enc[1 + mid * 2];
      if (k == symid) return enc[2 + mid * 2];
      if (k is num && k < symid) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }

  // Canonical integer keys only: getprop would also take "01" or " 1", and
  // condensing must not change which value a path selects.
  if (kind == _CONDENSE_LIST) {
    final k = jsString(key);
    final i = _R_CONDENSE_INDEX.hasMatch(k) ? int.tryParse(k) : null;
    return i != null && i < enc.length - 1 ? enc[1 + i] : -1;
  }

  return -1;
}

// Walk a path from node idx: the node index reached, or -1.
dynamic _condenseResolve(dynamic cond, dynamic idx, dynamic path) {
  final List<dynamic> parts = path is List
      ? path
      : path is String
          ? (path == S_MT ? <dynamic>[] : path.split(S_DT))
          : (path == null || identical(path, _noarg))
              ? <dynamic>[]
              : <dynamic>[jsString(path)];
  dynamic at = idx;
  for (final part in parts) {
    if (at is num && at < 0) return -1;
    if (part == S_MT) continue;
    at = _condenseChild(cond, at, part);
  }
  return at;
}

// A fresh tree each call: no materialisation shares a container with another,
// even where the condensed form shares the node.
dynamic _condenseMaterialise(dynamic cond, dynamic idx) {
  dynamic rebuild(dynamic i) {
    final enc = _condenseEnc(cond, i);
    if (enc == null) return null;
    final kind = _condenseKind(enc);
    if (kind == _CONDENSE_MAP) {
      final out = <String, dynamic>{};
      for (var j = 1; j < enc.length; j += 2) {
        out[jsString(_condenseSym(cond, enc[j]))] =
            rebuild(j + 1 < enc.length ? enc[j + 1] : null);
      }
      return out;
    }
    if (kind == _CONDENSE_LIST) {
      final out = <dynamic>[];
      for (var j = 1; j < enc.length; j++) {
        out.add(rebuild(enc[j]));
      }
      return out;
    }
    if (kind == _CONDENSE_STR) {
      return enc.length > 1 ? _condenseSym(cond, enc[1]) : null;
    }
    if (kind == _CONDENSE_NUM) return enc.length > 1 ? enc[1] : null;
    if (kind == _CONDENSE_TRUE) return true;
    if (kind == _CONDENSE_FALSE) return false;
    return null;
  }

  return idx is num && idx < 0 ? null : rebuild(idx);
}

dynamic expand(dynamic cond) =>
    iscondensed(cond) ? _condenseMaterialise(cond, cond[_S_condroot]) : cond;

List<String> _condenseKeys(dynamic cond, dynamic idx) {
  final enc = _condenseEnc(cond, idx);
  if (enc == null) return <String>[];
  final kind = _condenseKind(enc);
  if (kind == _CONDENSE_MAP) {
    final out = <String>[];
    for (var j = 1; j < enc.length; j += 2) {
      out.add(jsString(_condenseSym(cond, enc[j])));
    }
    return out;
  }
  if (kind == _CONDENSE_LIST) {
    return List<String>.generate(enc.length - 1, (j) => j.toString());
  }
  return <String>[];
}

int _condenseSize(dynamic cond, dynamic idx) {
  final enc = _condenseEnc(cond, idx);
  if (enc == null) return 0;
  final kind = _condenseKind(enc);
  if (kind == _CONDENSE_MAP) return (enc.length - 1) ~/ 2;
  if (kind == _CONDENSE_LIST) return enc.length - 1;
  return 0;
}

/// A cursor into a condensed structure. [ref] hands out ONE shared
/// materialisation per node, through a memo every view reached by [at]
/// shares; mutating it changes what every other [ref] of that node sees.
class CondenseView {
  final dynamic _cond;
  final dynamic _start;
  final Map<String, dynamic> _memo;

  CondenseView._(this._cond, this._start, this._memo);

  dynamic get([dynamic path]) =>
      _condenseMaterialise(_cond, _condenseResolve(_cond, _start, path));

  List<String> keys([dynamic path]) =>
      _condenseKeys(_cond, _condenseResolve(_cond, _start, path));

  bool has([dynamic path]) =>
      _condenseFound(_condenseResolve(_cond, _start, path));

  CondenseView at([dynamic path]) =>
      CondenseView._(_cond, _condenseResolve(_cond, _start, path), _memo);

  dynamic value() => _condenseMaterialise(_cond, _start);

  int size() => _condenseSize(_cond, _start);

  bool exists() => _condenseFound(_start);

  dynamic ref() {
    final k = jsString(_start);
    if (!_memo.containsKey(k)) _memo[k] = _condenseMaterialise(_cond, _start);
    return _memo[k];
  }
}

CondenseView condenseview(dynamic cond,
    [dynamic idx, Map<String, dynamic>? memo]) {
  final start = idx ?? (iscondensed(cond) ? cond[_S_condroot] : -1);
  return CondenseView._(cond, start, memo ?? <String, dynamic>{});
}

// ---------------------------------------------------------------------------
// builders
// ---------------------------------------------------------------------------

dynamic jm(List<dynamic> kv) {
  var m = <String, dynamic>{};
  var n = kv.length;
  for (var i = 0; i < n; i += 2) {
    var k0 = kv[i];
    var k = k0 == null ? 'null' : (k0 is String ? k0 : stringify(k0));
    m[k] = (i + 1 < n) ? kv[i + 1] : null;
  }
  return m;
}

dynamic jt(List<dynamic> v) => List<dynamic>.from(v);

String tn(int t) => typename(t);
