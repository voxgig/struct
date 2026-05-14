// Select — MongoDB-style query/filter over a list or map of children.
// Each operator (`$AND` / `$OR` / `$NOT` / `$CMP` family) runs as an
// injector in M_KEYPRE mode and modifies the grandparent slot to
// match-or-replace `point`, so the validator's modify hook is satisfied.

import Foundation

// MARK: - $AND

public func select_AND(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  guard inj.mode == M_KEYPRE else { return .noval }
  let terms = lookup(inj.parent, .string(inj.key))
  let ppath = slice(.list(VList(inj.path.map { Value.string($0) })), -1)
  let point = getpath(store, ppath)
  let vstoreBase = VMap()
  vstoreBase.entries[S_DTOP] = point
  let vstore = merge(.list([.map(VMap()), store, .map(vstoreBase)]), 1)
  if case .list(let tl) = terms {
    for term in tl.items {
      let terrs = VList()
      let subInj = Injection(val: .noval, parent: .noval)
      subInj.extra = vstore
      subInj.errs = terrs
      subInj.meta = inj.meta
      _ = validate(point, term, subInj)
      if !terrs.items.isEmpty {
        inj.errs.items.append(
          .string("AND:" + pathify(ppath) + S_VIZ + stringify(point) + " fail:" + stringify(terms)))
      }
    }
  }
  let gkey = getelem(.list(VList(inj.path.map { Value.string($0) })), .int(-2))
  let gp = inj.nodes.count >= 2 ? inj.nodes[inj.nodes.count - 2] : .noval
  setprop(gp, gkey, point)
  return .noval
}

// MARK: - $OR

public func select_OR(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  guard inj.mode == M_KEYPRE else { return .noval }
  let terms = lookup(inj.parent, .string(inj.key))
  let ppath = slice(.list(VList(inj.path.map { Value.string($0) })), -1)
  let point = getpath(store, ppath)
  let vstoreBase = VMap()
  vstoreBase.entries[S_DTOP] = point
  let vstore = merge(.list([.map(VMap()), store, .map(vstoreBase)]), 1)
  if case .list(let tl) = terms {
    for term in tl.items {
      let terrs = VList()
      let subInj = Injection(val: .noval, parent: .noval)
      subInj.extra = vstore
      subInj.errs = terrs
      subInj.meta = inj.meta
      _ = validate(point, term, subInj)
      if terrs.items.isEmpty {
        let gkey = getelem(.list(VList(inj.path.map { Value.string($0) })), .int(-2))
        let gp = inj.nodes.count >= 2 ? inj.nodes[inj.nodes.count - 2] : .noval
        setprop(gp, gkey, point)
        return .noval
      }
    }
  }
  inj.errs.items.append(
    .string("OR:" + pathify(ppath) + S_VIZ + stringify(point) + " fail:" + stringify(terms)))
  return .noval
}

// MARK: - $NOT

public func select_NOT(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  guard inj.mode == M_KEYPRE else { return .noval }
  let term = lookup(inj.parent, .string(inj.key))
  let ppath = slice(.list(VList(inj.path.map { Value.string($0) })), -1)
  let point = getpath(store, ppath)
  let vstoreBase = VMap()
  vstoreBase.entries[S_DTOP] = point
  let vstore = merge(.list([.map(VMap()), store, .map(vstoreBase)]), 1)
  let terrs = VList()
  let subInj = Injection(val: .noval, parent: .noval)
  subInj.extra = vstore
  subInj.errs = terrs
  subInj.meta = inj.meta
  _ = validate(point, term, subInj)
  if terrs.items.isEmpty {
    inj.errs.items.append(
      .string("NOT:" + pathify(ppath) + S_VIZ + stringify(point) + " fail:" + stringify(term)))
  }
  let gkey = getelem(.list(VList(inj.path.map { Value.string($0) })), .int(-2))
  let gp = inj.nodes.count >= 2 ? inj.nodes[inj.nodes.count - 2] : .noval
  setprop(gp, gkey, point)
  return .noval
}

// MARK: - $CMP family

public func select_CMP(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  guard inj.mode == M_KEYPRE else { return .noval }
  let term = lookup(inj.parent, .string(inj.key))
  let gkey = getelem(.list(VList(inj.path.map { Value.string($0) })), .int(-2))
  let ppath = slice(.list(VList(inj.path.map { Value.string($0) })), -1)
  let point = getpath(store, ppath)
  var pass = false
  // Numeric comparison if both sides are numeric.
  let bothNum: Bool = {
    switch (point, term) {
    case (.int, .int), (.int, .double), (.double, .int), (.double, .double): return true
    default: return false
    }
  }()
  if ref == "$GT" {
    if bothNum, let a = point.asDouble, let b = term.asDouble {
      pass = a > b
    } else if case .string(let a) = point, case .string(let b) = term {
      pass = a > b
    }
  } else if ref == "$LT" {
    if bothNum, let a = point.asDouble, let b = term.asDouble {
      pass = a < b
    } else if case .string(let a) = point, case .string(let b) = term {
      pass = a < b
    }
  } else if ref == "$GTE" {
    if bothNum, let a = point.asDouble, let b = term.asDouble {
      pass = a >= b
    } else if case .string(let a) = point, case .string(let b) = term {
      pass = a >= b
    }
  } else if ref == "$LTE" {
    if bothNum, let a = point.asDouble, let b = term.asDouble {
      pass = a <= b
    } else if case .string(let a) = point, case .string(let b) = term {
      pass = a <= b
    }
  } else if ref == "$LIKE" {
    let s = stringify(point)
    if case .string(let pat) = term {
      if let re = try? NSRegularExpression(pattern: pat) {
        let r = NSRange(location: 0, length: (s as NSString).length)
        if re.firstMatch(in: s, range: r) != nil { pass = true }
      }
    }
  }
  if pass {
    let gp = inj.nodes.count >= 2 ? inj.nodes[inj.nodes.count - 2] : .noval
    setprop(gp, gkey, point)
  } else {
    inj.errs.items.append(
      .string(
        "CMP: " + pathify(ppath) + S_VIZ + stringify(point) + " fail:" + ref + " " + stringify(term)
      ))
  }
  return .noval
}

// MARK: - select top-level

public func select(_ children: Value, _ query: Value) -> Value {
  if !isnode(children) { return .list([]) }
  var childList: [Value] = []
  switch children {
  case .map(let m):
    for (k, v) in m.entries {
      setprop(v, .string(S_DKEY), .string(k))
      childList.append(v)
    }
  case .list(let l):
    for (i, v) in l.items.enumerated() {
      setprop(v, .string(S_DKEY), .int(Int64(i)))
      childList.append(v)
    }
  default: break
  }
  var results: [Value] = []
  let meta = VMap()
  meta.entries[S_BEXACT] = .bool(true)
  let extra = VMap()
  extra.entries["$AND"] = .function(select_AND)
  extra.entries["$OR"] = .function(select_OR)
  extra.entries["$NOT"] = .function(select_NOT)
  extra.entries["$GT"] = .function(select_CMP)
  extra.entries["$LT"] = .function(select_CMP)
  extra.entries["$GTE"] = .function(select_CMP)
  extra.entries["$LTE"] = .function(select_CMP)
  extra.entries["$LIKE"] = .function(select_CMP)
  // Walk the query and add $OPEN flag to every map (allows extra keys).
  let q = clone(query)
  _ = walk(
    q,
    { _, v, _, _ in
      if case .map(let m) = v {
        let existing = m.entries[S_BOPEN] ?? .bool(true)
        m.entries[S_BOPEN] = existing
      }
      return v
    })
  for child in childList {
    let errs = VList()
    let inj = Injection(val: .noval, parent: .noval)
    inj.meta = meta
    inj.extra = .map(extra)
    inj.errs = errs
    _ = validate(child, clone(q), inj)
    if errs.items.isEmpty { results.append(child) }
  }
  return .list(results)
}

// MARK: - re_* helper wrappers (uniform API across ports)

public func re_compile(_ pattern: String, _ flags: String = "") -> NSRegularExpression? {
  var opts: NSRegularExpression.Options = []
  if flags.contains("i") { opts.insert(.caseInsensitive) }
  if flags.contains("m") { opts.insert(.anchorsMatchLines) }
  return try? NSRegularExpression(pattern: pattern, options: opts)
}

public func re_test(_ pattern: Value, _ input: String) -> Bool {
  guard case .string(let pat) = pattern, let re = re_compile(pat) else { return false }
  let r = NSRange(location: 0, length: (input as NSString).length)
  return re.firstMatch(in: input, range: r) != nil
}

public func re_find(_ pattern: Value, _ input: String) -> Value {
  guard case .string(let pat) = pattern, let re = re_compile(pat) else { return .noval }
  let ns = input as NSString
  let r = NSRange(location: 0, length: ns.length)
  guard let m = re.firstMatch(in: input, range: r) else { return .noval }
  var out: [Value] = [.string(ns.substring(with: m.range))]
  for i in 1..<m.numberOfRanges {
    let rr = m.range(at: i)
    out.append(rr.location == NSNotFound ? .noval : .string(ns.substring(with: rr)))
  }
  return .list(out)
}

public func re_find_all(_ pattern: Value, _ input: String) -> Value {
  guard case .string(let pat) = pattern, let re = re_compile(pat) else { return .list([]) }
  let ns = input as NSString
  let r = NSRange(location: 0, length: ns.length)
  var out: [Value] = []
  for m in re.matches(in: input, range: r) {
    var match: [Value] = [.string(ns.substring(with: m.range))]
    for i in 1..<m.numberOfRanges {
      let rr = m.range(at: i)
      match.append(rr.location == NSNotFound ? .noval : .string(ns.substring(with: rr)))
    }
    out.append(.list(match))
  }
  return .list(out)
}

public func re_replace(_ pattern: Value, _ input: String, _ replacement: String) -> String {
  guard case .string(let pat) = pattern, let re = re_compile(pat) else { return input }
  let r = NSRange(location: 0, length: (input as NSString).length)
  return re.stringByReplacingMatches(in: input, range: r, withTemplate: replacement)
}

public func re_escape(_ v: Value) -> String { escre(v) }
