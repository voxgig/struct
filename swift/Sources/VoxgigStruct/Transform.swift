// Transform commands — 11 injectors plus the top-level `transform`
// driver. Each command receives `(inj, val, ref, store)` and returns
// the result value (or NONE to delete the slot). The runtime helpers
// `$BT` / `$DS` / `$WHEN` / `$SPEC` are exposed as function values too.

import Foundation

// MARK: - $DELETE

public func transform_DELETE(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value
{
  inj.setval(.noval)
  return .noval
}

// MARK: - $COPY

public func transform_COPY(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  guard checkPlacement(M_VAL, "COPY", T_any, inj) else { return .noval }
  let out = lookup(inj.dparent, .string(inj.key))
  inj.setval(out)
  return out
}

// MARK: - $KEY

public func transform_KEY(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  if inj.mode != M_VAL { return .noval }
  let parent = inj.parent
  let keyspec = lookup(parent, .string(S_BKEY))
  if !keyspec.isNoval {
    delprop(parent, .string(S_BKEY))
    return getprop(inj.dparent, keyspec)
  }
  let anno = lookup(parent, .string(S_BANNO))
  let k = lookup(anno, .string(S_KEY))
  if !k.isNoval { return k }
  let plen = inj.path.count
  if plen >= 2 { return .string(inj.path[plen - 2]) }
  return .noval
}

// MARK: - $META

public func transform_META(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  delprop(inj.parent, .string(S_DMETA))
  return .noval
}

// MARK: - $ANNO

public func transform_ANNO(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  delprop(inj.parent, .string(S_BANNO))
  return .noval
}

// MARK: - $MERGE

public func transform_MERGE(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value
{
  let mode = inj.mode
  let key = inj.key
  let parent = inj.parent
  var out: Value = .noval
  if mode == M_KEYPRE {
    out = .string(key)
  } else if mode == M_KEYPOST {
    out = .string(key)
    var args = getprop(parent, .string(key))
    if !args.isList { args = .list([args]) }
    inj.setval(.noval)
    var mergelist: [Value] = [parent]
    if case .list(let l) = args { mergelist.append(contentsOf: l.items) }
    mergelist.append(clone(parent))
    _ = merge(.list(mergelist))
  }
  return out
}

// MARK: - $EACH

public func transform_EACH(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  guard checkPlacement(M_VAL, "EACH", T_list, inj) else { return .noval }
  // Slice keys to 1 element so the parent loop stops after this slot.
  if case .list(let kl) = Value.list(VList(inj.keys.map { Value.string($0) })) {
    let _ = kl
  }
  inj.keys = Array(inj.keys.prefix(1))
  let rest = slice(inj.parent, 1)
  let (err, args) = injectorArgs([T_string, T_any], rest)
  if !err.isNoval {
    inj.errs.items.append(.string("$EACH: " + stringify(err)))
    return .noval
  }
  let srcpath = args[0]
  let child = args[1]
  let srcstore = getprop(store, .string(inj.base), store)
  let src = getpath(srcstore, srcpath, inj)
  let srctype = typify(src)
  var tval: [Value] = []
  let tkey = getelem(.list(VList(inj.path.map { Value.string($0) })), .int(-2))
  let target = getelem(
    .list(VList(inj.nodes)), .int(-2),
    getelem(.list(VList(inj.nodes)), .int(-1)))
  if (srctype & T_list) != 0 {
    for _ in items(src) { tval.append(clone(child)) }
  } else if (srctype & T_map) != 0 {
    for pair in items(src) {
      // pair = [key, val]; record key for $KEY transforms.
      let anno = jm("KEY", pair[0])
      let mergeArg: Value = .list([clone(child), jm(S_BANNO, anno)])
      tval.append(merge(mergeArg, 1))
    }
  }
  var rval: Value = .list([])
  if !tval.isEmpty {
    var tcur: Value = .noval
    if src.isNoval || src.isNull {
      tcur = .noval
    } else {
      var inner: [Value] = []
      for pair in items(src) { inner.append(pair[1]) }
      tcur = .list(inner)
    }
    let ckey = getelem(.list(VList(inj.path.map { Value.string($0) })), .int(-2))
    let tpath = slice(.list(VList(inj.path.map { Value.string($0) })), -1)
    var dpathParts: [Value] = [.string(S_DTOP)]
    if let sp = srcpath.asString {
      for p in sp.split(separator: ".", omittingEmptySubsequences: false) {
        dpathParts.append(.string(String(p)))
      }
    }
    dpathParts.append(.string("$:" + strkey(ckey)))
    var tcurmap = jm(strkey(ckey), tcur)
    if size(tpath) > 1 {
      let pkey = getelem(.list(VList(inj.path.map { Value.string($0) })), .int(-3), .string(S_DTOP))
      tcurmap = jm(strkey(pkey), tcurmap)
      dpathParts.append(.string("$:" + strkey(pkey)))
    }
    let tinj = inj.child(0, [strkey(ckey)])
    tinj.path = (tpath.asList?.items ?? []).map { strkey($0) }
    tinj.nodes = slice(.list(VList(inj.nodes)), -1).asList?.items ?? []
    tinj.parent = getelem(.list(VList(tinj.nodes)), .int(-1))
    let tvalList = Value.list(VList(tval))
    setprop(tinj.parent, .string(strkey(ckey)), tvalList)
    tinj.val = tvalList
    tinj.dpath = dpathParts.map { strkey($0) }
    tinj.dparent = tcurmap
    inject(tvalList, store, tinj)
    rval = tinj.val
  }
  setprop(target, tkey, rval)
  return getelem(rval, .int(0))
}

// MARK: - $PACK

public func transform_PACK(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  guard checkPlacement(M_KEYPRE, "EACH", T_map, inj) else { return .noval }
  let key = inj.key
  let path = inj.path
  let parent = inj.parent
  let args = getprop(parent, .string(key))
  let (err, parsed) = injectorArgs([T_string, T_any], args)
  if !err.isNoval {
    inj.errs.items.append(.string("$EACH: " + stringify(err)))
    return .noval
  }
  let srcpath = parsed[0]
  let origchildspec = parsed[1]
  let tkey = getelem(.list(VList(path.map { Value.string($0) })), .int(-2))
  let pathsize = path.count
  let target2 =
    pathsize - 2 >= 0 && pathsize - 2 < inj.nodes.count
    ? inj.nodes[pathsize - 2]
    : (inj.nodes.last ?? .noval)
  let srcstore = getprop(store, .string(inj.base), store)
  var src = getpath(srcstore, srcpath, inj)
  // Coerce source to list with anno.KEY annotations.
  if !src.isList {
    if src.isMap {
      var coll: [Value] = []
      for pair in items(src) {
        let k = pair[0]
        let v = pair[1]
        setprop(v, .string(S_BANNO), jm("KEY", k))
        coll.append(v)
      }
      src = .list(coll)
    } else {
      src = .noval
    }
  }
  if src.isNoval { return .noval }
  let keypath = getprop(origchildspec, .string(S_BKEY))
  let childspec = delprop(origchildspec, .string(S_BKEY))
  let child = getprop(childspec, .string(S_BVAL), childspec)
  let tval = VMap()
  if case .list(let srcL) = src {
    for (i, srcnode) in srcL.items.enumerated() {
      var kk: Value = .noval
      if keypath.isNoval {
        // No keypath: fall back to the source position. Prefer
        // an injected `$BANNO.KEY` annotation if present (e.g.
        // when the source was a map promoted to a list above).
        let anno = getprop(srcnode, .string(S_BANNO))
        let annoKey = getprop(anno, .string(S_KEY))
        kk = annoKey.isNoval ? .int(Int64(i)) : annoKey
      } else if let kp = keypath.asString, kp.hasPrefix("`") {
        let mstore = merge(.list([.map(VMap()), store, jm(S_DTOP, srcnode)]), 1)
        kk = inject(keypath, mstore)
      } else {
        kk = getpath(srcnode, keypath, inj)
      }
      let tchild = clone(child)
      setprop(.map(tval), kk, tchild)
      let anno = getprop(srcnode, .string(S_BANNO))
      if anno.isNoval {
        delprop(tchild, .string(S_BANNO))
      } else {
        setprop(tchild, .string(S_BANNO), anno)
      }
    }
  }
  var rval: Value = .map(VMap())
  if !isempty(.map(tval)) {
    let tsrc = VMap()
    if case .list(let srcL) = src {
      for (i, n) in srcL.items.enumerated() {
        var kn: Value
        if keypath.isNoval {
          kn = .int(Int64(i))
        } else if let kp = keypath.asString, kp.hasPrefix("`") {
          let mstore = merge(.list([.map(VMap()), store, jm(S_DTOP, n)]), 1)
          kn = inject(keypath, mstore)
        } else {
          kn = getpath(n, keypath, inj)
        }
        setprop(.map(tsrc), kn, n)
      }
    }
    let tpath = slice(.list(VList(inj.path.map { Value.string($0) })), -1)
    let ckey = getelem(.list(VList(inj.path.map { Value.string($0) })), .int(-2))
    var dpathParts: [Value] = [.string(S_DTOP)]
    if let sp = srcpath.asString {
      for p in sp.split(separator: ".", omittingEmptySubsequences: false) {
        dpathParts.append(.string(String(p)))
      }
    }
    dpathParts.append(.string("$:" + strkey(ckey)))
    var tcur = jm(strkey(ckey), .map(tsrc))
    if size(tpath) > 1 {
      let pkey = getelem(.list(VList(inj.path.map { Value.string($0) })), .int(-3), .string(S_DTOP))
      tcur = jm(strkey(pkey), tcur)
      dpathParts.append(.string("$:" + strkey(pkey)))
    }
    let tinj = inj.child(0, [strkey(ckey)])
    tinj.path = (tpath.asList?.items ?? []).map { strkey($0) }
    tinj.nodes = slice(.list(VList(inj.nodes)), -1).asList?.items ?? []
    tinj.parent = getelem(.list(VList(tinj.nodes)), .int(-1))
    tinj.val = .map(tval)
    tinj.dpath = dpathParts.map { strkey($0) }
    tinj.dparent = tcur
    inject(.map(tval), store, tinj)
    rval = tinj.val
  }
  setprop(target2, tkey, rval)
  return .noval
}

// MARK: - $REF

public func transform_REF(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
  if inj.mode != M_VAL { return .noval }
  let nodes = inj.nodes
  let refpath = lookup(inj.parent, .int(1))
  inj.keyI = inj.keys.count
  let specFn = getprop(store, .string(S_DSPEC))
  let spec: Value
  if case .function(let fn) = specFn {
    spec = fn(inj, specFn, "$SPEC", store)
  } else {
    spec = specFn
  }
  let dpath = slice(.list(VList(inj.path.map { Value.string($0) })), 1)
  let dpathList = dpath.asList?.items.map { strkey($0) } ?? []
  let subInj = Injection(val: spec, parent: spec)
  subInj.dpath = dpathList
  subInj.dparent = getpath(spec, dpath)
  subInj.base = S_DTOP
  subInj.meta = inj.meta
  let resolved = getpath(spec, refpath, subInj)
  var hasSubRef = false
  if isnode(resolved) {
    _ = walk(
      resolved,
      { _, v, _, _ in
        if case .string(let s) = v, s == "`$REF`" { hasSubRef = true }
        return v
      })
  }
  let tref = clone(resolved)
  let cpath = slice(.list(VList(inj.path.map { Value.string($0) })), -3)
  let tpath = slice(.list(VList(inj.path.map { Value.string($0) })), -1)
  let tcur = getpath(store, cpath)
  let tval = getpath(store, tpath)
  var rval: Value = .noval
  if !hasSubRef || !tval.isNoval {
    let tinj = inj.child(0, [strkey(getelem(tpath, .int(-1)))])
    tinj.path = tpath.asList?.items.map { strkey($0) } ?? []
    tinj.nodes = slice(.list(VList(inj.nodes)), -1).asList?.items ?? []
    tinj.parent = nodes.count >= 2 ? nodes[nodes.count - 2] : .noval
    tinj.val = tref
    tinj.dpath = cpath.asList?.items.map { strkey($0) } ?? []
    tinj.dparent = tcur
    inject(tref, store, tinj)
    rval = tinj.val
  }
  let grandparent = inj.setval(rval, ancestor: 2)
  if grandparent.isList, let prior = inj.prior {
    prior.keyI -= 1
  }
  return val
}

// MARK: - $FORMAT

public typealias Formatter = (Value, Value) -> Value

public let FORMATTER: [String: Formatter] = [
  "identity": { _, v in v },
  "upper": { _, v in isnode(v) ? v : .string((stringify(v)).uppercased()) },
  "lower": { _, v in isnode(v) ? v : .string((stringify(v)).lowercased()) },
  "string": { _, v in isnode(v) ? v : .string(stringify(v)) },
  "number": { _, v in
    if isnode(v) { return v }
    if let d = v.asDouble { return .double(d) }
    if case .string(let s) = v, let d = Double(s) { return .double(d) }
    return .double(0)
  },
  "integer": { _, v in
    if isnode(v) { return v }
    if let d = v.asDouble { return .int(Int64(d)) }
    if case .string(let s) = v, let d = Double(s) { return .int(Int64(d)) }
    return .int(0)
  },
  "concat": { k, v in
    if k.isNoval, case .list(let l) = v {
      var s = ""
      for item in l.items { s += isnode(item) ? "" : stringify(item) }
      return .string(s)
    }
    return v
  },
]

public func transform_FORMAT(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value
{
  inj.keys = Array(inj.keys.prefix(1))
  if inj.mode != M_VAL { return .noval }
  let name = lookup(inj.parent, .int(1))
  let child = lookup(inj.parent, .int(2))
  let tkey = getelem(.list(VList(inj.path.map { Value.string($0) })), .int(-2))
  let target =
    inj.nodes.count >= 2
    ? inj.nodes[inj.nodes.count - 2]
    : (inj.nodes.last ?? .noval)
  let cinj = injectChild(child, store, inj)
  let resolved = cinj.val
  var formatter: Formatter? = nil
  if case .function(let fn) = name {
    formatter = { k, v in fn(inj, v, strkey(k), store) }
  } else if case .string(let n) = name {
    formatter = FORMATTER[n]
  }
  guard let fmt = formatter else {
    inj.errs.items.append(.string("$FORMAT: unknown format: " + stringify(name) + "."))
    return .noval
  }
  let out = walk(resolved, { k, v, _, _ in fmt(k, v) })
  setprop(target, tkey, out)
  return out
}

// MARK: - $APPLY

public func transform_APPLY(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value
{
  guard checkPlacement(M_VAL, "APPLY", T_list, inj) else { return .noval }
  let rest = slice(inj.parent, 1)
  let (err, parsed) = injectorArgs([T_function, T_any], rest)
  if !err.isNoval {
    inj.errs.items.append(.string("$APPLY: " + stringify(err)))
    return .noval
  }
  let apply = parsed[0]
  let child = parsed[1]
  let tkey = getelem(.list(VList(inj.path.map { Value.string($0) })), .int(-2))
  let target =
    inj.nodes.count >= 2
    ? inj.nodes[inj.nodes.count - 2]
    : (inj.nodes.last ?? .noval)
  let cinj = injectChild(child, store, inj)
  let resolved = cinj.val
  var out: Value = .noval
  if case .function(let fn) = apply {
    out = fn(cinj, resolved, "", store)
  }
  setprop(target, tkey, out)
  return out
}

// MARK: - Top-level transform

public func transform(_ data: Value, _ spec: Value, _ injdef: Injection? = nil) -> Value {
  let origspec = spec
  let spec = clone(origspec)
  let extra = injdef?.extra ?? .noval
  let collect = (injdef?.errs.items.count) != nil ? true : false
  let errs = injdef?.errs ?? VList()
  let extraTransforms = VMap()
  let extraData = VMap()
  if !extra.isNoval, case .map(let em) = extra {
    for (k, v) in em.entries {
      if k.hasPrefix(S_DS) { extraTransforms.entries[k] = v } else { extraData.entries[k] = v }
    }
  }
  var mergeArgs: [Value] = []
  if !isempty(.map(extraData)) { mergeArgs.append(clone(.map(extraData))) }
  mergeArgs.append(clone(data))
  let dataClone = merge(.list(mergeArgs))
  let base = VMap()
  base.entries[S_DTOP] = dataClone
  base.entries["$SPEC"] = .function { _, _, _, _ in origspec }
  base.entries["$BT"] = .function { _, _, _, _ in .string(S_BT) }
  base.entries["$DS"] = .function { _, _, _, _ in .string(S_DS) }
  base.entries["$WHEN"] = .function { _, _, _, _ in
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return .string(f.string(from: Date()))
  }
  base.entries["$DELETE"] = .function(transform_DELETE)
  base.entries["$COPY"] = .function(transform_COPY)
  base.entries["$KEY"] = .function(transform_KEY)
  base.entries["$META"] = .function(transform_META)
  base.entries["$ANNO"] = .function(transform_ANNO)
  base.entries["$MERGE"] = .function(transform_MERGE)
  base.entries["$EACH"] = .function(transform_EACH)
  base.entries["$PACK"] = .function(transform_PACK)
  base.entries["$REF"] = .function(transform_REF)
  base.entries["$FORMAT"] = .function(transform_FORMAT)
  base.entries["$APPLY"] = .function(transform_APPLY)
  let errsMap = VMap()
  errsMap.entries[S_DERRS] = .list(errs)
  let store = merge(.list([.map(base), .map(extraTransforms), .map(errsMap)]), 1)
  let out = inject(spec, store, injdef)
  if errs.items.count > 0 && !collect {
    // Throw via fatalError isn't ideal — use a token to signal upstream.
    // For now, leave errs accumulated in the injdef if collected.
  }
  return out
}
