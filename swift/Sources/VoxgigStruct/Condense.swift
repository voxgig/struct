// condense / expand / condenseview — an interned encoding of a JSON-shaped
// value: a sorted symbol table plus post-order nodes. Mirrors canonical TS.

import Foundation

let CONDENSE_VERSION = 1

let CONDENSE_MAP = 0
let CONDENSE_LIST = 1
let CONDENSE_STR = 2
let CONDENSE_NUM = 3
let CONDENSE_TRUE = 4
let CONDENSE_FALSE = 5
let CONDENSE_NULL = 6

let S_condense = "$condense"
let S_condsym = "sym"
let S_condnode = "node"
let S_condroot = "root"

let S_condimmutable =
  "struct: condensed structures are immutable - expand() first, then modify the copy"

// MARK: - iscondensed / condense / expand

public func iscondensed(_ val: Value) -> Bool {
  // The version must match, not merely be numeric: a future profile would
  // otherwise be decoded under this one's schema.
  guard case .map(let m) = val, m.entries[S_condense] == .int(Int64(CONDENSE_VERSION)) else {
    return false
  }
  return islist(m.entries[S_condsym] ?? .noval) && islist(m.entries[S_condnode] ?? .noval)
    && (m.entries[S_condroot]?.isNumber ?? false)
}

public func condense(_ val: Value) -> Value {
  // Symbols are keyed by their bytes in UTF-8: a String key would merge
  // canonically equivalent strings that canonical keeps apart.
  var symset = Set<[UInt8]>()
  condenseCollect(val, &symset)
  let symbytes = symset.sorted { $0.lexicographicallyPrecedes($1) }
  var symid: [[UInt8]: Int] = [:]
  for (i, s) in symbytes.enumerated() { symid[s] = i }
  let sym = symbytes.map { Value.string(String(decoding: $0, as: UTF8.self)) }

  var node: [Value] = []
  var seen: [String: Int] = [:]
  let root = condenseBuild(val, symid, &node, &seen)

  let out = VMap()
  out.entries[S_condense] = .int(Int64(CONDENSE_VERSION))
  out.entries[S_condsym] = .list(sym)
  out.entries[S_condnode] = .list(node)
  out.entries[S_condroot] = .int(Int64(root))
  return .map(out)
}

public func expand(_ cond: Value) -> Value {
  if !iscondensed(cond) { return cond }
  return condenseMaterialise(cond, condenseRoot(cond))
}

// MARK: - condenseview

public func condenseview(_ cond: Value, _ idx: Int? = nil, _ memo: VMap? = nil) -> CondenseView {
  let start = idx ?? (iscondensed(cond) ? condenseRoot(cond) : -1)
  return CondenseView(cond: cond, start: start, memo: memo ?? VMap())
}

// A cursor into a condensed structure: reads touch only the nodes on a path.
public struct CondenseView {
  let cond: Value
  let start: Int
  // Threaded through at(), so every cursor into one structure shares it.
  let memo: VMap

  public func get(_ path: Value = .noval) -> Value {
    return condenseMaterialise(cond, condenseResolve(cond, start, path))
  }

  public func keys(_ path: Value = .noval) -> [String] {
    let found = condenseResolve(cond, start, path)
    return 0 > found ? [] : condenseKeys(cond, found)
  }

  public func has(_ path: Value = .noval) -> Bool {
    return 0 <= condenseResolve(cond, start, path)
  }

  public func at(_ path: Value = .noval) -> CondenseView {
    return condenseview(cond, condenseResolve(cond, start, path), memo)
  }

  public func value() -> Value {
    return condenseMaterialise(cond, start)
  }

  public func size() -> Int {
    guard let enc = condenseEnc(cond, start), let first = enc.first else { return 0 }
    let kind = condenseInt(first)
    if CONDENSE_MAP == kind { return (enc.count - 1) / 2 }
    if CONDENSE_LIST == kind { return enc.count - 1 }
    return 0
  }

  public func exists() -> Bool {
    return 0 <= start
  }

  // Shared: the same node for the same index, from every view on the memo.
  // Mutating it corrupts every other reader of that node.
  public func ref() -> Value {
    let k = String(start)
    if let shared = memo.entries[k] { return shared }
    let made = condenseMaterialise(cond, start)
    memo.entries[k] = made
    return made
  }
}

// MARK: - Building

private func condenseCollect(_ n: Value, _ symset: inout Set<[UInt8]>) {
  switch n {
  case .map(let m):
    for k in keysof(n) {
      symset.insert(Array(k.utf8))
      condenseCollect(m.entries[k] ?? .noval, &symset)
    }
  case .list(let l):
    for item in l.items { condenseCollect(item, &symset) }
  case .string(let s):
    symset.insert(Array(s.utf8))
  default:
    break
  }
}

// Post-order, so an identical subtree is already interned when its parent
// refers to it.
private func condenseBuild(
  _ n: Value, _ symid: [[UInt8]: Int], _ node: inout [Value], _ seen: inout [String: Int]
) -> Int {
  switch n {
  case .map(let m):
    var enc: [Value] = [.int(Int64(CONDENSE_MAP))]
    // Code-point order, as the symbols sort, so the ids ascend for bisection.
    for k in keysof(n).sorted(by: condensePrecedes) {
      enc.append(.int(Int64(symid[Array(k.utf8)] ?? -1)))
      enc.append(.int(Int64(condenseBuild(m.entries[k] ?? .noval, symid, &node, &seen))))
    }
    return condenseIntern(enc, &node, &seen)
  case .list(let l):
    var enc: [Value] = [.int(Int64(CONDENSE_LIST))]
    for item in l.items {
      enc.append(.int(Int64(condenseBuild(item, symid, &node, &seen))))
    }
    return condenseIntern(enc, &node, &seen)
  case .string(let s):
    let sid = symid[Array(s.utf8)] ?? -1
    return condenseIntern([.int(Int64(CONDENSE_STR)), .int(Int64(sid))], &node, &seen)
  case .int, .double:
    return condenseIntern([.int(Int64(CONDENSE_NUM)), n], &node, &seen)
  case .bool(let b):
    return condenseIntern([.int(Int64(b ? CONDENSE_TRUE : CONDENSE_FALSE))], &node, &seen)
  default:
    return condenseIntern([.int(Int64(CONDENSE_NULL))], &node, &seen)
  }
}

// Keyed on the encoding's text, as canonical joins it, so an integer and a
// decimal of one value share a node. The kind leads, so kinds never collide.
private func condenseIntern(
  _ enc: [Value], _ node: inout [Value], _ seen: inout [String: Int]
) -> Int {
  let enckey = enc.map { condenseKeystr($0) }.joined(separator: S_CM)
  if let hit = seen[enckey] { return hit }
  let idx = node.count
  node.append(.list(enc))
  seen[enckey] = idx
  return idx
}

// MARK: - Reading

// JS String(key), which canonical applies to a path part and to an encoding
// element.
private func condenseKeystr(_ key: Value) -> String {
  switch key {
  case .string(let s): return s
  case .int(let n): return String(n)
  case .double(let d):
    if d.isNaN { return "NaN" }
    if d.isInfinite { return 0 < d ? "Infinity" : "-Infinity" }
    return JSON.formatDouble(d)
  case .bool(let b): return b ? "true" : "false"
  case .null: return "null"
  case .noval: return "undefined"
  default: return stringify(key)
  }
}

private func condenseInt(_ v: Value) -> Int? {
  switch v {
  case .int(let n): return Int(exactly: n)
  case .double(let d): return Int(exactly: d)
  default: return nil
  }
}

func condenseRoot(_ cond: Value) -> Int {
  return condenseInt(lookup(cond, .string(S_condroot))) ?? -1
}

private func condenseEnc(_ cond: Value, _ idx: Int) -> [Value]? {
  guard 0 <= idx, case .list(let nodes) = lookup(cond, .string(S_condnode)) else { return nil }
  guard idx < nodes.items.count, case .list(let enc) = nodes.items[idx] else { return nil }
  return enc.items
}

private func condenseSym(_ cond: Value, _ id: Value) -> Value {
  guard let i = condenseInt(id), 0 <= i else { return .noval }
  guard case .list(let sym) = lookup(cond, .string(S_condsym)), i < sym.items.count else {
    return .noval
  }
  return sym.items[i]
}

// Code-point order, which is the byte order of UTF-8. String's < compares
// by canonical equivalence instead.
private func condensePrecedes(_ a: String, _ b: String) -> Bool {
  return a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars)
}

private func condenseSymId(_ cond: Value, _ key: String) -> Int {
  guard case .list(let sym) = lookup(cond, .string(S_condsym)) else { return -1 }
  var lo = 0
  var hi = sym.items.count - 1
  while lo <= hi {
    let mid = (lo + hi) >> 1
    if case .string(let s) = sym.items[mid] {
      if s.unicodeScalars.elementsEqual(key.unicodeScalars) { return mid }
      if condensePrecedes(s, key) {
        lo = mid + 1
        continue
      }
    }
    hi = mid - 1
  }
  return -1
}

private func condenseChild(_ cond: Value, _ idx: Int, _ key: String) -> Int {
  guard let enc = condenseEnc(cond, idx), let first = enc.first else { return -1 }
  let kind = condenseInt(first)

  if CONDENSE_MAP == kind {
    let symid = condenseSymId(cond, key)
    if 0 > symid { return -1 }
    // Pairs sit at [1,2], [3,4], ... in ascending symbol id.
    var lo = 0
    var hi = (enc.count - 1) / 2 - 1
    while lo <= hi {
      let mid = (lo + hi) >> 1
      guard let k = condenseInt(enc[1 + mid * 2]) else { return -1 }
      if k == symid { return condenseInt(enc[2 + mid * 2]) ?? -1 }
      if k < symid { lo = mid + 1 } else { hi = mid - 1 }
    }
    return -1
  }

  // The plain list read's rule: condensing must not change which value a path
  // selects.
  if CONDENSE_LIST == kind {
    guard isListIndex(key), let i = Int(key), i < enc.count - 1 else { return -1 }
    return condenseInt(enc[1 + i]) ?? -1
  }

  return -1
}

func condenseResolve(_ cond: Value, _ idx: Int, _ path: Value) -> Int {
  var parts: [Value] = []
  switch path {
  case .list(let l): parts = l.items
  case .string(let s):
    if !s.isEmpty {
      parts = s.split(separator: ".", omittingEmptySubsequences: false).map {
        Value.string(String($0))
      }
    }
  case .noval, .null: break
  default: parts = [.string(condenseKeystr(path))]
  }

  var at = idx
  for part in parts {
    if 0 > at { return -1 }
    if case .string(let s) = part, s.isEmpty { continue }
    at = condenseChild(cond, at, condenseKeystr(part))
  }
  return at
}

// A fresh tree on every call: materialisations never share a container, even
// where the condensed form shares a node.
func condenseMaterialise(_ cond: Value, _ idx: Int) -> Value {
  guard let enc = condenseEnc(cond, idx), let first = enc.first else { return .noval }
  let kind = condenseInt(first)

  if CONDENSE_MAP == kind {
    let out = VMap()
    for j in stride(from: 1, to: enc.count, by: 2) {
      guard case .string(let k) = condenseSym(cond, enc[j]) else { continue }
      out.entries[k] =
        j + 1 < enc.count ? condenseMaterialise(cond, condenseInt(enc[j + 1]) ?? -1) : .noval
    }
    return .map(out)
  }
  if CONDENSE_LIST == kind {
    return .list(enc.dropFirst().map { condenseMaterialise(cond, condenseInt($0) ?? -1) })
  }
  if CONDENSE_STR == kind {
    return 1 < enc.count ? condenseSym(cond, enc[1]) : .noval
  }
  if CONDENSE_NUM == kind {
    return 1 < enc.count ? enc[1] : .noval
  }
  if CONDENSE_TRUE == kind { return .bool(true) }
  if CONDENSE_FALSE == kind { return .bool(false) }
  return .null
}

private func condenseKeys(_ cond: Value, _ idx: Int) -> [String] {
  guard let enc = condenseEnc(cond, idx), let first = enc.first else { return [] }
  let kind = condenseInt(first)
  if CONDENSE_MAP == kind {
    var out: [String] = []
    for j in stride(from: 1, to: enc.count, by: 2) {
      if case .string(let k) = condenseSym(cond, enc[j]) { out.append(k) }
    }
    return out
  }
  if CONDENSE_LIST == kind {
    return (1..<enc.count).map { String($0 - 1) }
  }
  return []
}
