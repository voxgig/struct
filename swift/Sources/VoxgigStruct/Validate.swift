// Validate checkers — 18 injectors plus the top-level `validate`
// driver, the `_validation` modify hook, and the validate-mode
// `_validatehandler`. Mirrors canonical TS `validate*`.

import Foundation

// MARK: - Error formatter

private func invalidTypeMsg(
  _ path: [String], _ needtype: String, _ vt: Int, _ v: Value, _ whence: String
) -> String {
  // Canonical: `null == v ? 'no value' : stringify(v)`. In JS `null == v` is
  // true for BOTH undefined and null, so a null value also reads "no value" -
  // this port tested only for absent, and `validate/invalid#0` (`data: null`
  // against `$STRING`) is the entry that notices.
  let novalue = v.isNoval || v.isNull
  let vs = novalue ? "no value" : stringify(v)
  let field =
    path.count > 1
    ? "field " + pathify(.list(VList(path.map { Value.string($0) })), 1) + " to be " : ""
  let extra = novalue ? "" : typename(vt) + S_VIZ
  return "Expected " + field + needtype + ", but found " + extra + vs + "."
}

// MARK: - validate_STRING / TYPE / ANY

public func validate_STRING(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value
{
  let out = lookup(inj.dparent, .string(inj.key))
  let t = typify(out)
  if (t & T_string) == 0 {
    inj.errs.items.append(.string(invalidTypeMsg(inj.path, S_string, t, out, "V1010")))
    return .noval
  }
  if case .string(let s) = out, s.isEmpty {
    inj.errs.items.append(
      .string("Empty string at " + pathify(.list(VList(inj.path.map { Value.string($0) })), 1)))
    return .noval
  }
  return out
}

private let TNAME_TO_BIT: [String: Int] = [
  S_nil: T_noval,
  S_boolean: T_boolean,
  S_decimal: T_decimal,
  S_integer: T_integer,
  S_number: T_integer | T_decimal | T_number,
  S_string: T_string,
  S_function: T_function,
  S_symbol: T_symbol,
  S_null: T_null,
  S_list: T_list,
  S_map: T_map,
  S_instance: T_instance,
  S_scalar: T_scalar,
  S_node: T_node,
  S_any: T_any,
]

public func validate_TYPE(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  let tname = String(ref.dropFirst()).lowercased()

  // $NIL is absent or null.
  let typev = (TNAME_TO_BIT[tname] ?? 0) | (S_nil == tname ? T_null : 0)
  let out = lookup(inj.dparent, .string(inj.key))
  let t = typify(out)
  if (t & typev) == 0 {
    inj.errs.items.append(.string(invalidTypeMsg(inj.path, tname, t, out, "V1001")))
    return .noval
  }
  return out
}

public func validate_ANY(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  return lookup(inj.dparent, .string(inj.key))
}

// MARK: - validate_CHILD

public func validate_CHILD(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  let mode = inj.mode
  let key = inj.key
  let parent = inj.parent
  let path = inj.path
  if mode == M_KEYPRE {
    let childtm = getprop(parent, .string(key))
    let pkey = path.count >= 2 ? path[path.count - 2] : ""
    var tval = getprop(inj.dparent, .string(pkey))
    if tval.isNoval {
      tval = .map(VMap())
    } else if !tval.isMap {
      // _validation reports the mismatch, once.
      return .noval
    }
    let ckeys = keysof(tval)
    for ck in ckeys {
      _setprop(parent, .string(ck), clone(childtm))
      inj.keys.append(ck)
    }
    inj.setval(.noval)
    return .noval
  }
  if mode == M_VAL {
    if !parent.isList {
      inj.errs.items.append(.string("Invalid $CHILD as value"))
      return .noval
    }
    let childtm = lookup(parent, .int(1))
    if inj.dparent.isNoval {
      slice(parent, 0, 0, mutate: true)
      return .noval
    }
    if !inj.dparent.isList {
      inj.keyI = size(parent)
      return inj.dparent
    }
    if case .list(let dl) = inj.dparent {
      for i in 0..<dl.items.count {
        _setprop(parent, .int(Int64(i)), clone(childtm))
      }
      slice(parent, 0, dl.items.count, mutate: true)

      // NOTE: modifying inj! This extends the child value loop in inject
      // to cover every cloned child (the loop re-reads `childinj.keys`
      // after each phase). Canonical's counting `for` is a no-op when the
      // data list is shorter than the template keys; a Swift `a..<b`
      // range would trap there, so use `while`.
      var ckeyI = inj.keys.count
      while ckeyI < size(parent) {
        inj.keys.append(strkey(.int(Int64(ckeyI))))
        ckeyI += 1
      }

      // Restart the child value loop at the first element (the loop
      // increments keyI on resume) so that the first element is also
      // validated against the child template.
      inj.keyI = -1

      // SKIP leaves the cloned child template in place at the first
      // element so the resumed loop can validate it.
      return .sentinel(SKIP)
    }
  }
  return .noval
}

// MARK: - validate_EXACT

public func validate_EXACT(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  let mode = inj.mode
  let parent = inj.parent
  let key = inj.key
  let keyI = inj.keyI
  if mode == M_VAL {
    if !parent.isList || keyI != 0 {
      inj.errs.items.append(
        .string(
          "The $EXACT validator at field "
            + pathify(.list(VList(inj.path.map { Value.string($0) })), 1, 1)
            + " must be the first element of an array."))
      return .noval
    }
    let cval = _slotval(inj)
    inj.keyI = inj.keys.count

    // Replace [$EXACT, ...] with the data value; SKIP keeps inject off the
    // detached list.
    inj.setval(cval, ancestor: 2)

    if !inj.path.isEmpty { inj.path = Array(inj.path.dropLast()) }
    guard case .list(let tl) = slice(parent, 1) else { return .sentinel(SKIP) }
    if tl.items.isEmpty {
      inj.errs.items.append(
        .string(
          "The $EXACT validator at field "
            + pathify(.list(VList(inj.path.map { Value.string($0) })), 1, 1)
            + " must have at least one argument."))
      return .sentinel(SKIP)
    }
    for tval in tl.items {
      if _deepequal(tval, cval) { return .sentinel(SKIP) }
    }
    inj.errs.items.append(
      .string(
        invalidTypeMsg(
          inj.path,
          (inj.path.count > 1 ? "" : "value ") + "exactly equal to "
            + (tl.items.count == 1 ? "" : "one of ") + _valdesc(tl.items),
          typify(cval), cval, "V0110")))
    return .sentinel(SKIP)
  }
  _delprop(parent, .string(key))
  return .noval
}

// MARK: - validate_NOF / validate_ALL

// Count the specs that admit the value: ['`$NOF`', count, spec, ...], where
// count is an integer, or a map holding min, max or both.
public func validate_NOF(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  return _validatecount(inj, store, "$NOF", true)
}

// Every spec admits the value: ['`$ALL`', spec, ...].
public func validate_ALL(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  return _validatecount(inj, store, "$ALL", false)
}

// The counting list directives. Without a count, every spec has to admit.
private func _validatecount(
  _ inj: Injection, _ store: Value, _ name: String, _ counted: Bool
) -> Value {
  let parent = inj.parent
  if inj.mode != M_VAL { return .noval }

  if !parent.isList || inj.keyI != 0 {
    inj.errs.items.append(
      .string(
        "The " + name + " validator at field "
          + pathify(.list(VList(inj.path.map { Value.string($0) })), 1, 1)
          + " must be the first element of an array."))
    return .noval
  }

  let cval = _slotval(inj)
  inj.keyI = inj.keys.count

  // Replace the directive's list with the data value. Each return is SKIP, so
  // that inject leaves the detached list alone and validates nothing in it.
  inj.setval(cval, ancestor: 2)

  if !inj.path.isEmpty { inj.path = Array(inj.path.dropLast()) }

  let count = counted ? lookup(parent, .int(1)) : Value.noval
  guard case .list(let tl) = slice(parent, counted ? 2 : 1) else { return .sentinel(SKIP) }
  let tvals = tl.items
  let field =
    "The " + name + " validator at field "
    + pathify(.list(VList(inj.path.map { Value.string($0) })), 1)

  if tvals.isEmpty {
    inj.errs.items.append(
      .string(
        field + (counted ? " must have a count and" : " must have") + " at least one argument."))
    return .sentinel(SKIP)
  }

  var lo = tvals.count
  var hi = tvals.count
  var countdesc: String? = "all"
  if counted { (lo, hi, countdesc) = _nofcount(count, tvals.count) }

  guard let words = countdesc else {
    inj.errs.items.append(.string(field + " has an invalid count: " + stringify(count) + "."))
    return .sentinel(SKIP)
  }

  var admitted = 0
  for tI in 0..<tvals.count {
    let left = tvals.count - tI

    // Stop once the specs left cannot change the verdict.
    if hi < admitted || admitted + left < lo || (lo <= admitted && admitted + left <= hi) {
      break
    }

    if _admits(cval, tvals[tI], inj, store) {
      admitted += 1
    }
  }

  if admitted < lo || hi < admitted {
    inj.errs.items.append(
      .string(
        invalidTypeMsg(inj.path, words + " of " + _valdesc(tvals), typify(cval), cval, "V0310")))
  }

  return .sentinel(SKIP)
}

// MARK: - validate_LEN / validate_RANGE

// The value's length is within a bound: ['`$LEN`', bound, spec?], where the
// bound is as for a $NOF count. A string's length is in code points.
public func validate_LEN(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  return _validatebound(inj, store, "$LEN")
}

// The value is a number within a bound: ['`$RANGE`', bound, spec?], where the
// bound holds min or gt, max or lt, or one of each.
public func validate_RANGE(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  return _validatebound(inj, store, "$RANGE")
}

// The bounding list directives: a bound, then at most one spec that must also
// admit.
private func _validatebound(_ inj: Injection, _ store: Value, _ name: String) -> Value {
  let parent = inj.parent
  if inj.mode != M_VAL { return .noval }

  if !parent.isList || inj.keyI != 0 {
    inj.errs.items.append(
      .string(
        "The " + name + " validator at field "
          + pathify(.list(VList(inj.path.map { Value.string($0) })), 1, 1)
          + " must be the first element of an array."))
    return .noval
  }

  let cval = _slotval(inj)
  inj.keyI = inj.keys.count

  // As for the counting directives: SKIP keeps inject off the detached list.
  inj.setval(cval, ancestor: 2)

  if !inj.path.isEmpty { inj.path = Array(inj.path.dropLast()) }

  let field =
    "The " + name + " validator at field "
    + pathify(.list(VList(inj.path.map { Value.string($0) })), 1)
  let nargs = size(parent) - 1

  if nargs < 1 || 2 < nargs {
    inj.errs.items.append(.string(field + " must have a bound and at most one spec."))
    return .sentinel(SKIP)
  }

  let bound = lookup(parent, .int(1))
  let islen = "$LEN" == name
  let (lo, hi, desc) = islen ? _lenbound(bound) : (0, 0, _rangedesc(bound))

  guard let words = desc else {
    inj.errs.items.append(.string(field + " has an invalid bound: " + stringify(bound) + "."))
    return .sentinel(SKIP)
  }

  let ctype = typify(cval)
  let spec = lookup(parent, .int(2))

  if 2 == nargs && !_admits(cval, spec, inj, store) {
    inj.errs.items.append(
      .string(invalidTypeMsg(inj.path, _valdesc([spec]), ctype, cval, "V0410")))
    return .sentinel(SKIP)
  }

  if 0 == ((islen ? T_string | T_list | T_map : T_number) & ctype) {
    let needtype = islen ? "string, list or map" : S_number
    inj.errs.items.append(.string(invalidTypeMsg(inj.path, needtype, ctype, cval, "V0420")))
    return .sentinel(SKIP)
  }

  let len = islen ? (cval.asString?.unicodeScalars.count ?? size(cval)) : 0
  let inbound = islen ? lo <= len && (-1 == hi || len <= hi) : _inrange(bound, cval)

  if !inbound {
    let needtype = (inj.path.count > 1 ? "" : "value ") + words
    inj.errs.items.append(.string(invalidTypeMsg(inj.path, needtype, ctype, cval, "V0430")))
  }

  return .sentinel(SKIP)
}

// The bounds of a $LEN bound, with -1 for no maximum, and the words for it,
// which are nil when the bound is invalid.
private func _lenbound(_ bound: Value) -> (Int, Int, String?) {
  let (lo, hi, countdesc) = _nofcount(bound, -1)
  if nil == countdesc { return (0, 0, nil) }

  let desc: String
  if lo == hi {
    desc = String(lo)
  } else if -1 == hi {
    desc = "at least " + String(lo)
  } else if 0 == lo {
    desc = "at most " + String(hi)
  } else {
    desc = String(lo) + " to " + String(hi)
  }

  return (lo, hi, "of length " + desc)
}

// The words for a $RANGE bound, which are nil when the bound is invalid.
private func _rangedesc(_ bound: Value) -> String? {
  if !ismap(bound) { return nil }

  let min = lookup(bound, .string("min"))
  let max = lookup(bound, .string("max"))
  let gt = lookup(bound, .string("gt"))
  let lt = lookup(bound, .string("lt"))
  let lower = (min.isNoval ? gt : min).asDouble
  let upper = (max.isNoval ? lt : max).asDouble
  let numkeys = [min, max, gt, lt].filter { !$0.isNoval }.count
  func isnum(_ n: Value) -> Bool { n.isNoval || 0 < (T_number & typify(n)) }

  let valid =
    0 < numkeys && size(bound) == numkeys
    && (min.isNoval || gt.isNoval) && (max.isNoval || lt.isNoval)
    && isnum(min) && isnum(max) && isnum(gt) && isnum(lt)
    && (nil == lower || nil == upper || lower! <= upper!)

  if !valid { return nil }

  var words: [String] = []
  if !min.isNoval {
    words.append("at least " + stringify(min))
  } else if !gt.isNoval {
    words.append("greater than " + stringify(gt))
  }
  if !max.isNoval {
    words.append("at most " + stringify(max))
  } else if !lt.isNoval {
    words.append("less than " + stringify(lt))
  }

  return words.joined(separator: " and ")
}

// A number within a valid $RANGE bound.
private func _inrange(_ bound: Value, _ val: Value) -> Bool {
  guard let v = val.asDouble else { return false }
  let min = lookup(bound, .string("min")).asDouble
  let max = lookup(bound, .string("max")).asDouble
  let gt = lookup(bound, .string("gt")).asDouble
  let lt = lookup(bound, .string("lt")).asDouble
  return (nil == min || min! <= v) && (nil == max || v <= max!)
    && (nil == gt || gt! < v) && (nil == lt || v < lt!)
}

// MARK: - _validation modify hook

public func _validation(
  _ pval: Value, _ key: Value, _ parent: Value, _ inj: Injection, _ store: Value
) {
  // Skip if pval is a SKIP sentinel.
  if case .sentinel(let s) = pval, s === SKIP { return }
  let exactRaw = getprop(.map(inj.meta), .string(S_BEXACT), .bool(false))
  let exact: Bool = exactRaw.asBool ?? false
  let cval = getprop(inj.dparent, key)
  if !exact && cval.isNoval { return }
  let ptype = typify(pval)
  // String spec containing $ → skip (already-processed command).
  if (ptype & T_string) != 0, case .string(let s) = pval, s.contains(S_DS) {
    return
  }
  let ctype = typify(cval)
  if ptype != ctype && !pval.isNoval {
    inj.errs.items.append(.string(invalidTypeMsg(inj.path, typename(ptype), ctype, cval, "V0010")))
    return
  }
  if cval.isMap {
    if !pval.isMap {
      inj.errs.items.append(
        .string(invalidTypeMsg(inj.path, typename(ptype), ctype, cval, "V0020")))
      return
    }
    if case .map(let cm) = cval, case .map(let pm) = pval {
      let ckeys = keysof(.map(cm))
      let pkeys = keysof(.map(pm))
      let openV = getprop(.map(pm), .string(S_BOPEN))
      let isOpen: Bool = openV.asBool ?? false
      if pkeys.count > 0 && !isOpen {
        var badkeys: [String] = []
        for ck in ckeys {
          if lookup(.map(pm), .string(ck)).isNoval { badkeys.append(ck) }
        }
        if !badkeys.isEmpty {
          inj.errs.items.append(
            .string(
              "Unexpected keys at field "
                + pathify(.list(VList(inj.path.map { Value.string($0) })), 1) + S_VIZ
                + badkeys.joined(separator: ", ")))
        }
      } else {
        _ = merge(.list([.map(pm), .map(cm)]))
        _delprop(.map(pm), .string(S_BOPEN))
      }
    }
  } else if cval.isList {
    if !pval.isList {
      inj.errs.items.append(
        .string(invalidTypeMsg(inj.path, typename(ptype), ctype, cval, "V0030")))
    }
  } else if exact {
    if cval != pval {
      let pathmsg =
        inj.path.count > 1
        ? "at field " + pathify(.list(VList(inj.path.map { Value.string($0) })), 1) + S_VIZ
        : S_MT
      inj.errs.items.append(
        .string("Value " + pathmsg + stringify(cval) + " should equal " + stringify(pval) + S_DT))
    }
  } else {
    _setprop(parent, key, cval)
  }
}

// MARK: - _validatehandler

public func _validatehandler(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value
{
  let ns = ref as NSString
  let mr = NSRange(location: 0, length: ns.length)
  if let m = R_META_PATH.firstMatch(in: ref, range: mr) {
    let sym = ns.substring(with: m.range(at: 2))
    if sym == "=" {
      inj.setval(.list([.string(S_BEXACT), val]))
    } else {
      inj.setval(val)
    }
    inj.keyI = -1
    return .sentinel(SKIP)
  }
  return _injecthandler(inj, val, ref, store)
}

// MARK: - validate top-level

/// Validate `data` against the by-example `spec`.
///
/// Throws a `StructError` carrying the collected errors, joined with " | ",
/// unless the caller supplied an error sink - canonical's
/// `collect = null != injdef?.errs`, which here is `Injection.errssupplied`
/// (assign `inj.errs` to collect). This port read `collect` off
/// `injdef?.errs != nil`, and `errs` was a non-optional VList, so `collect` was
/// true whenever ANY injdef was passed and every corpus entry with an `err:`
/// expectation passed vacuously.
public func validate(_ data: Value, _ spec: Value, _ injdef: Injection? = nil) throws -> Value {
  let collect = injdef?.errssupplied ?? false
  let errs = injdef?.errs ?? VList()
  let out = validateCollect(data, spec, injdef, errs)
  if 0 < errs.items.count && !collect {
    throw StructError(join(.list(errs), " | "))
  }
  return out
}

// The collecting core: never throws, and appends to the caller's `errs`.
func validateCollect(
  _ data: Value, _ spec: Value, _ injdef: Injection?, _ errs: VList
) -> Value {
  let extra = injdef?.extra ?? .noval
  let base = VMap()
  // Suppress transform commands.
  base.entries["$DELETE"] = .null
  base.entries["$COPY"] = .null
  base.entries["$KEY"] = .null
  base.entries["$META"] = .null
  base.entries["$MERGE"] = .null
  base.entries["$EACH"] = .null
  base.entries["$PACK"] = .null
  base.entries["$STRING"] = .function(validate_STRING)
  base.entries["$NUMBER"] = .function(validate_TYPE)
  base.entries["$INTEGER"] = .function(validate_TYPE)
  base.entries["$DECIMAL"] = .function(validate_TYPE)
  base.entries["$BOOLEAN"] = .function(validate_TYPE)
  base.entries["$NULL"] = .function(validate_TYPE)
  base.entries["$NIL"] = .function(validate_TYPE)
  base.entries["$MAP"] = .function(validate_TYPE)
  base.entries["$LIST"] = .function(validate_TYPE)
  base.entries["$FUNCTION"] = .function(validate_TYPE)
  base.entries["$INSTANCE"] = .function(validate_TYPE)
  base.entries["$ANY"] = .function(validate_ANY)
  base.entries["$CHILD"] = .function(validate_CHILD)
  base.entries["$EXACT"] = .function(validate_EXACT)
  base.entries["$NOF"] = .function(validate_NOF)
  base.entries["$ALL"] = .function(validate_ALL)
  base.entries["$LEN"] = .function(validate_LEN)
  base.entries["$RANGE"] = .function(validate_RANGE)
  let errsMap = VMap()
  errsMap.entries[S_DERRS] = .list(errs)
  let extraMap = extra.isNoval ? Value.map(VMap()) : extra
  let store = merge(.list([.map(base), extraMap, .map(errsMap)]), 1)
  let meta = (injdef?.meta) ?? VMap()
  if meta.entries[S_BEXACT] == nil { meta.entries[S_BEXACT] = .bool(false) }

  // A spec that names an unknown checker validates nothing.
  let numerrs = errs.items.count
  _checknames(spec, store, [], errs)
  if numerrs < errs.items.count { return clone(data) }

  let runInj = Injection(val: .noval, parent: .noval)
  runInj.meta = meta
  runInj.extra = store
  runInj.modify = _validation
  runInj.handler = _validatehandler
  runInj.errs = errs
  // The core, not the throwing wrapper: this `validate` decides what to do
  // with what transform collects.
  return transformCollect(data, spec, runInj, errs)
}

// MARK: - Validate helpers

// Names a validate spec may use besides its checkers: transform's that it
// keeps, and $OPEN.
private let VALIDATE_NAMES = [
  "$TOP", "$SPEC", "$BT", "$DS", "$WHEN", "$ANNO", "$REF", "$FORMAT", "$APPLY", "$OPEN",
]

// Report each checker the spec names that validate lacks; $EXACT's arguments
// are literals.
private func _checknames(_ spec: Value, _ store: Value, _ path: [String], _ errs: VList) {
  if let name = _refname(spec) {
    if _unknownname(name, store) {
      errs.items.append(
        .string(
          "Unknown validator " + name + " at field "
            + pathify(.list(VList(path.map { Value.string($0) }))) + "."))
    }
    return
  }

  if case .list(let l) = spec, let first = l.items.first, "$EXACT" == _refname(first) {
    return
  }

  for key in keysof(spec) {
    if ismap(spec) {
      _checknames(.string(key), store, path, errs)
    }
    _checknames(lookup(spec, .string(key)), store, path + [key], errs)
  }
}

// The name a whole-string reference gives, when it is a checker name in any
// case.
private func _refname(_ val: Value) -> String? {
  guard case .string(let s) = val else { return nil }
  let ns = s as NSString
  let r = NSRange(location: 0, length: ns.length)
  guard let m = R_INJECTION_FULL.firstMatch(in: s, range: r), m.range == r else { return nil }
  let name = ns.substring(with: m.range(at: 1))
  let upper = name.uppercased()
  let ur = NSRange(location: 0, length: (upper as NSString).length)
  guard let c = R_CHECKER_NAME.firstMatch(in: upper, range: ur), c.range == ur else { return nil }
  return name
}

// Unknown: undefined and upper case, or a defined name in another case. Null
// disables a name.
private func _unknownname(_ name: String, _ store: Value) -> Bool {
  func known(_ n: String) -> Bool {
    let v = lookup(store, .string(n))
    return VALIDATE_NAMES.contains(n) || !(v.isNoval || v.isNull)
  }
  let upper = name.uppercased()
  return !known(name) && (upper == name || known(upper))
}

// The data value at a list directive's slot. The directive's own dparent was
// read with getprop, which reports a stored null as absent.
private func _slotval(_ inj: Injection) -> Value {
  guard let prior = inj.prior else { return inj.dparent }
  return lookup(prior.dparent, .string(prior.key))
}

// JSON equality, which is Value's ==: numbers by value, lists in order, maps
// by key in any order. A function has no identity here, so equals nothing.
private func _deepequal(_ a: Value, _ b: Value) -> Bool {
  return a == b
}

// Every member val has is in out, unchanged. A member only out has is a
// default the spec supplied, and is ignored.
private func _keeps(_ val: Value, _ out: Value) -> Bool {
  if val.isNoval { return true }
  if 0 == ((T_list | T_map) & typify(val)) || islist(val) != islist(out) || !isnode(out) {
    return _deepequal(val, out)
  }
  for k in keysof(val) {
    if !_keeps(lookup(val, .string(k)), lookup(out, .string(k))) { return false }
  }
  return true
}

// A spec admits a value when validating the value against it finds no error
// and gives back the value as it is.
private func _admits(_ val: Value, _ spec: Value, _ inj: Injection, _ store: Value) -> Bool {
  let terrs = VList()
  let vstore = merge(.list([.map(VMap()), store]), 1)
  if case .map(let vm) = vstore { vm.entries[S_DTOP] = val }
  let sub = Injection(val: .noval, parent: .noval)
  sub.extra = vstore
  sub.errs = terrs
  sub.meta = inj.meta
  let out = validateCollect(val, spec, sub, terrs)
  return terrs.items.isEmpty && _keeps(val, out)
}

// The bounds of a $NOF count, and the words for it, which are nil when the
// count is invalid. Without a max, the bound is the number of specs.
private func _nofcount(_ count: Value, _ numtvals: Int) -> (Int, Int, String?) {
  // An integral decimal counts too: 2.0 is 2 in JavaScript.
  func nat(_ n: Value) -> Int? {
    switch n {
    case .int(let i): return 0 <= i ? Int(exactly: i) : nil
    case .double(let d): return 0 <= d && d == d.rounded() ? Int(exactly: d) : nil
    default: return nil
    }
  }

  if let c = nat(count) {
    return (c, c, 0 == c ? "none" : "exactly " + String(c))
  }

  let min = lookup(count, .string("min"))
  let max = lookup(count, .string("max"))
  let minn = nat(min)
  let maxn = nat(max)

  let valid =
    ismap(count) && 0 < size(count)
    && size(count) == (min.isNoval ? 0 : 1) + (max.isNoval ? 0 : 1)
    && (min.isNoval || nil != minn)
    && (max.isNoval || nil != maxn)
    && (nil == minn || nil == maxn || minn! <= maxn!)

  if !valid { return (0, 0, nil) }

  let lo = minn ?? 0
  let hi = maxn ?? numtvals

  let desc: String
  if max.isNoval {
    desc = "at least " + String(lo)
  } else if 0 == hi {
    desc = "none"
  } else if min.isNoval {
    desc = "at most " + String(hi)
  } else if lo == hi {
    desc = "exactly " + String(lo)
  } else {
    desc = String(lo) + " to " + String(hi)
  }

  return (lo, hi, desc)
}

// The specs as a message lists them, each `$NAME` as its lower-case name.
private func _valdesc(_ tvals: [Value]) -> String {
  let parts: [Value] = tvals.map { Value.string(stringify($0)) }
  let s = join(.list(parts), ", ")
  let ns = s as NSString
  var out = ""
  var last = 0
  for m in R_TRANSFORM_NAME.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
    out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
    out += ns.substring(with: m.range(at: 1)).lowercased()
    last = m.range.location + m.range.length
  }
  return out + ns.substring(from: last)
}
