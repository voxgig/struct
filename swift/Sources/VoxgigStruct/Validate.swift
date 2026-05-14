// Validate checkers — 15 injectors plus the top-level `validate`
// driver, the `_validation` modify hook, and the validate-mode
// `_validatehandler`. Mirrors canonical TS `validate*`.

import Foundation

// MARK: - Error formatter

private func invalidTypeMsg(
  _ path: [String], _ needtype: String, _ vt: Int, _ v: Value, _ whence: String
) -> String {
  let vs = v.isNoval ? "no value" : stringify(v)
  let field =
    path.count > 1
    ? "field " + pathify(.list(VList(path.map { Value.string($0) })), 1) + " to be " : ""
  let extra = v.isNoval ? "" : typename(vt) + S_VIZ
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
  let typev = TNAME_TO_BIT[tname] ?? 0
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
      inj.errs.items.append(
        .string(
          invalidTypeMsg(
            Array(inj.path.suffix(1)), S_object, typify(tval), tval, "V0220")))
      return .noval
    }
    let ckeys = keysof(tval)
    for ck in ckeys {
      setprop(parent, .string(ck), clone(childtm))
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
      let msg = invalidTypeMsg(
        Array(inj.path.suffix(1)),
        S_list, typify(inj.dparent), inj.dparent, "V0230")
      inj.errs.items.append(.string(msg))
      inj.keyI = size(parent)
      return inj.dparent
    }
    if case .list(let dl) = inj.dparent {
      for i in 0..<dl.items.count {
        setprop(parent, .int(Int64(i)), clone(childtm))
      }
      slice(parent, 0, dl.items.count, mutate: true)
      inj.keyI = 0
      return getprop(inj.dparent, .int(0))
    }
  }
  return .noval
}

// MARK: - validate_ONE

public func validate_ONE(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  let mode = inj.mode
  let parent = inj.parent
  let keyI = inj.keyI
  if mode == M_VAL {
    if !parent.isList || keyI != 0 {
      inj.errs.items.append(
        .string(
          "The $ONE validator at field "
            + pathify(.list(VList(inj.path.map { Value.string($0) })), 1)
            + " must be the first element of an array."))
      return .noval
    }
    inj.keyI = inj.keys.count
    inj.setval(inj.dparent, ancestor: 2)
    if inj.path.count > 1 {
      inj.path = Array(inj.path.suffix(inj.path.count - 1))
    }
    inj.key = inj.path.last ?? ""
    let tvals = slice(parent, 1)
    guard case .list(let tl) = tvals else { return .noval }
    if tl.items.isEmpty {
      inj.errs.items.append(
        .string(
          "The $ONE validator at field "
            + pathify(.list(VList(inj.path.map { Value.string($0) })), 1)
            + " must have at least one argument."))
      return .noval
    }
    for tval in tl.items {
      let terrs = VList()
      let vstoreBase = VMap()
      vstoreBase.entries[S_DTOP] = inj.dparent
      let vstore = merge(.list([.map(VMap()), store, .map(vstoreBase)]), 1)
      let subInj = Injection(val: .noval, parent: .noval)
      subInj.extra = vstore
      subInj.errs = terrs
      subInj.meta = inj.meta
      let vcurrent = validate(inj.dparent, tval, subInj)
      inj.setval(vcurrent, ancestor: -2)
      if terrs.items.isEmpty { return .noval }
    }
    var valdesc = tl.items.map { stringify($0) }.joined(separator: ", ")
    // Lower-case any `$NAME` references.
    valdesc = valdesc.replacingOccurrences(
      of: "`\\$([A-Z]+)`", with: "$1", options: .regularExpression)
    valdesc = valdesc.lowercased()
    inj.errs.items.append(
      .string(
        invalidTypeMsg(
          inj.path,
          (tl.items.count > 1 ? "one of " : "") + valdesc,
          typify(inj.dparent), inj.dparent, "V0210")))
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
            + pathify(.list(VList(inj.path.map { Value.string($0) })), 1)
            + " must be the first element of an array."))
      return .noval
    }
    inj.keyI = inj.keys.count
    inj.setval(inj.dparent, ancestor: 2)
    if !inj.path.isEmpty { inj.path = Array(inj.path.dropLast()) }
    inj.key = inj.path.last ?? ""
    let tvals = slice(parent, 1)
    guard case .list(let tl) = tvals else { return .noval }
    if tl.items.isEmpty {
      inj.errs.items.append(
        .string(
          "The $EXACT validator at field "
            + pathify(.list(VList(inj.path.map { Value.string($0) })), 1)
            + " must have at least one argument."))
      return .noval
    }
    var currentstr: String? = nil
    for tval in tl.items {
      var exactmatch = tval == inj.dparent
      if !exactmatch, isnode(tval) {
        if currentstr == nil { currentstr = stringify(inj.dparent) }
        let tvalstr = stringify(tval)
        exactmatch = tvalstr == currentstr
      }
      if exactmatch { return .noval }
    }
    var valdesc = tl.items.map { stringify($0) }.joined(separator: ", ")
    valdesc = valdesc.replacingOccurrences(
      of: "`\\$([A-Z]+)`", with: "$1", options: .regularExpression
    ).lowercased()
    inj.errs.items.append(
      .string(
        invalidTypeMsg(
          inj.path,
          (inj.path.count > 1 ? "" : "value ") + "exactly equal to "
            + (tl.items.count == 1 ? "" : "one of ") + valdesc,
          typify(inj.dparent), inj.dparent, "V0110")))
  } else {
    delprop(parent, .string(key))
  }
  return .noval
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
        delprop(.map(pm), .string(S_BOPEN))
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
    setprop(parent, key, cval)
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

public func validate(_ data: Value, _ spec: Value, _ injdef: Injection? = nil) -> Value {
  let extra = injdef?.extra ?? .noval
  let collect = injdef?.errs != nil
  let errs = injdef?.errs ?? VList()
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
  base.entries["$ONE"] = .function(validate_ONE)
  base.entries["$EXACT"] = .function(validate_EXACT)
  let errsMap = VMap()
  errsMap.entries[S_DERRS] = .list(errs)
  let extraMap = extra.isNoval ? Value.map(VMap()) : extra
  let store = merge(.list([.map(base), extraMap, .map(errsMap)]), 1)
  let meta = (injdef?.meta) ?? VMap()
  if meta.entries[S_BEXACT] == nil { meta.entries[S_BEXACT] = .bool(false) }
  let runInj = Injection(val: .noval, parent: .noval)
  runInj.meta = meta
  runInj.extra = store
  runInj.modify = _validation
  runInj.handler = _validatehandler
  runInj.errs = errs
  let out = transform(data, spec, runInj)
  _ = collect
  return out
}
