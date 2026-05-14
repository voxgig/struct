// Minor utilities — type predicates, property access, slicing,
// formatting. Each function mirrors its canonical TS counterpart in
// typescript/src/StructUtility.ts.

import Foundation

// MARK: - typename / typify / getdef

public func typename(_ t: Int) -> String { TYPENAME[t] ?? S_any }

public func getdef(_ v: Value, _ alt: Value) -> Value {
  return v.isNoval ? alt : v
}

public func typify(_ v: Value) -> Int {
  switch v {
  case .noval: return T_noval
  case .null: return T_null
  case .bool: return T_boolean
  case .int: return T_integer
  case .double: return T_decimal
  case .string: return T_string
  case .list: return T_list
  case .map, .sentinel: return T_map
  case .function: return T_function
  }
}

// MARK: - isnode / ismap / islist / iskey / isempty / isfunc

public func isnode(_ v: Value) -> Bool { v.isNode }
public func ismap(_ v: Value) -> Bool { v.isMap }
public func islist(_ v: Value) -> Bool { v.isList }

public func iskey(_ v: Value) -> Bool {
  switch v {
  case .string(let s): return !s.isEmpty
  case .int, .double: return true
  default: return false
  }
}

public func isempty(_ v: Value) -> Bool {
  switch v {
  case .noval, .null: return true
  case .string(let s): return s.isEmpty
  case .list(let l): return l.items.isEmpty
  case .map(let m): return m.entries.isEmpty
  default: return false
  }
}

public func isfunc(_ v: Value) -> Bool { v.isFunction }

// MARK: - size

public func size(_ v: Value) -> Int {
  switch v {
  case .list(let l): return l.items.count
  case .map(let m): return m.entries.count
  case .string(let s): return s.count
  case .int(let n): return Int(n)
  case .double(let d): return d.isFinite ? Int(d.rounded(.down)) : 0
  case .bool(let b): return b ? 1 : 0
  default: return 0
  }
}

// MARK: - slice

@discardableResult
public func slice(_ val: Value, _ start: Int? = nil, _ end: Int? = nil, mutate: Bool = false)
  -> Value
{
  // Numeric input: clamp.
  if val.isInt || val.isDouble {
    let nv: Double = val.asDouble ?? 0
    let lo = start.map(Double.init) ?? -Double.greatestFiniteMagnitude
    let hi = end.map { Double($0) - 1 } ?? Double.greatestFiniteMagnitude
    var v = nv
    if v < lo { v = lo }
    if v > hi { v = hi }
    return val.isInt ? .int(Int64(v)) : .double(v)
  }
  let vlen = size(val)
  var s = start
  var e = end
  if e != nil, s == nil { s = 0 }
  guard var ss = s else { return val }
  var ee = e ?? vlen
  if ss < 0 {
    ee = vlen + ss
    if ee < 0 { ee = 0 }
    ss = 0
  } else if e != nil {
    if ee < 0 {
      ee = vlen + ee
      if ee < 0 { ee = 0 }
    } else if vlen < ee {
      ee = vlen
    }
  } else {
    ee = vlen
  }
  if vlen < ss { ss = vlen }
  if ss <= ee, ee <= vlen, ss >= 0 {
    switch val {
    case .list(let l):
      let sliced = Array(l.items[ss..<ee])
      if mutate {
        l.items = sliced
        return val
      }
      return .list(VList(sliced))
    case .string(let s):
      let utf16 = s.utf16
      let start = utf16.index(utf16.startIndex, offsetBy: ss)
      let end = utf16.index(utf16.startIndex, offsetBy: ee)
      return .string(String(utf16[start..<end]) ?? "")
    default: return val
    }
  } else {
    switch val {
    case .list(let l):
      if mutate {
        l.items = []
        return val
      }
      return .list([])
    case .string: return .string("")
    default: return val
    }
  }
}

// MARK: - pad

public func pad(_ str: Value, _ padding: Int? = nil, _ padchar: Character = " ") -> Value {
  guard let padding = padding, padding != 0 else { return str }
  let s = stringify(str)
  let need = abs(padding) - s.count
  if need <= 0 { return .string(s) }
  let fill = String(repeating: String(padchar), count: need)
  return .string(padding < 0 ? fill + s : s + fill)
}

// MARK: - strkey

public func strkey(_ key: Value) -> String {
  switch key {
  case .noval, .null: return ""
  case .string(let s): return s
  case .int(let n): return String(n)
  case .double(let d): return JSON.formatDouble(d)
  default: return ""
  }
}

// MARK: - getelem

public func getelem(_ val: Value, _ key: Value, _ alt: Value = .noval) -> Value {
  guard case .list(let l) = val else { return alt }
  var k: Int? = nil
  switch key {
  case .int(let n): k = Int(n)
  case .double(let d): k = Int(d)
  case .string(let s): k = Int(s)
  default: break
  }
  guard var idx = k else { return alt }
  if idx < 0 { idx = l.items.count + idx }
  guard idx >= 0, idx < l.items.count else { return alt }
  let v = l.items[idx]
  return v.isNoval ? alt : v
}

// MARK: - getprop (Group A: stored null counts as absent)

public func getprop(_ val: Value, _ key: Value, _ alt: Value = .noval) -> Value {
  switch val {
  case .list(let l):
    return getelem(.list(l), key, alt)
  case .map(let m):
    let k = strkey(key)
    if k.isEmpty { return alt }
    guard let v = m.entries[k] else { return alt }
    if v.isNoval || v.isNull { return alt }
    return v
  default:
    return alt
  }
}

// Group B: read raw stored value (including JSON null) at a slot.
public func lookup(_ val: Value, _ key: Value) -> Value {
  switch val {
  case .list(let l):
    var k: Int? = nil
    switch key {
    case .int(let n): k = Int(n)
    case .double(let d): k = Int(d)
    case .string(let s): k = Int(s)
    default: break
    }
    guard var idx = k else { return .noval }
    if idx < 0 { idx = l.items.count + idx }
    guard idx >= 0, idx < l.items.count else { return .noval }
    return l.items[idx]
  case .map(let m):
    let k = strkey(key)
    if k.isEmpty { return .noval }
    return m.entries[k] ?? .noval
  case .sentinel(let s):
    // Sentinels look like maps with one marker key for inject's
    // setval-of-NONE detection.
    if strkey(key) == s.marker { return .bool(true) }
    return .noval
  default:
    return .noval
  }
}

// MARK: - setprop / delprop

@discardableResult
public func setprop(_ val: Value, _ key: Value, _ newval: Value) -> Value {
  // Sentinel handling.
  if case .sentinel(let s) = newval {
    if s === SKIP { return val }
    if s === DELETE { return delprop(val, key) }
  }
  if newval.isNoval { return delprop(val, key) }
  switch val {
  case .list(let l):
    var k: Int? = nil
    switch key {
    case .int(let n): k = Int(n)
    case .double(let d): k = Int(d)
    case .string(let s): k = Int(s)
    default: break
    }
    guard var idx = k else { return val }
    if idx < 0 { idx = l.items.count + idx }
    if idx >= l.items.count {
      while l.items.count < idx { l.items.append(.null) }
      l.items.append(newval)
    } else if idx >= 0 {
      l.items[idx] = newval
    }
    return val
  case .map(let m):
    let k = strkey(key)
    if k.isEmpty { return val }
    m.entries[k] = newval
    return val
  default:
    return val
  }
}

@discardableResult
public func delprop(_ val: Value, _ key: Value) -> Value {
  switch val {
  case .list(let l):
    var k: Int? = nil
    switch key {
    case .int(let n): k = Int(n)
    case .double(let d): k = Int(d)
    case .string(let s): k = Int(s)
    default: break
    }
    guard var idx = k else { return val }
    if idx < 0 { idx = l.items.count + idx }
    if idx >= 0, idx < l.items.count { l.items.remove(at: idx) }
    return val
  case .map(let m):
    let k = strkey(key)
    if !k.isEmpty { m.entries.removeValue(forKey: k) }
    return val
  default:
    return val
  }
}

// MARK: - keysof / haskey / items / flatten / filter

public func keysof(_ v: Value) -> [String] {
  switch v {
  case .list(let l): return (0..<l.items.count).map { String($0) }
  case .map(let m): return m.entries.keys.sorted()
  default: return []
  }
}

public func haskey(_ v: Value, _ key: Value) -> Bool {
  switch v {
  case .list(let l):
    var k: Int? = nil
    switch key {
    case .int(let n): k = Int(n)
    case .double(let d): k = Int(d)
    case .string(let s): k = Int(s)
    default: break
    }
    guard var idx = k else { return false }
    if idx < 0 { idx = l.items.count + idx }
    guard idx >= 0, idx < l.items.count else { return false }
    let v = l.items[idx]
    return !(v.isNoval || v.isNull)
  case .map(let m):
    let k = strkey(key)
    guard !k.isEmpty, let v = m.entries[k] else { return false }
    return !(v.isNoval || v.isNull)
  default: return false
  }
}

public func items(_ v: Value) -> [[Value]] {
  var out: [[Value]] = []
  switch v {
  case .list(let l):
    for (i, it) in l.items.enumerated() {
      out.append([.string(String(i)), it])
    }
  case .map(let m):
    for (k, it) in m.entries {
      out.append([.string(k), it])
    }
  default: break
  }
  return out
}

public func flatten(_ v: Value) -> Value {
  guard case .list(let l) = v else { return .list([]) }
  var out: [Value] = []
  var stack: [Value] = l.items.reversed()
  while let item = stack.popLast() {
    if case .list(let inner) = item {
      stack.append(contentsOf: inner.items.reversed())
    } else {
      out.append(item)
    }
  }
  return .list(out)
}

public func filter(_ v: Value, _ pred: (Value, Value) -> Bool) -> Value {
  var out: [Value] = []
  switch v {
  case .list(let l):
    for (i, it) in l.items.enumerated() {
      if pred(.string(String(i)), it) {
        out.append(.list([.string(String(i)), it]))
      }
    }
  case .map(let m):
    for (k, it) in m.entries {
      if pred(.string(k), it) {
        out.append(.list([.string(k), it]))
      }
    }
  default: break
  }
  return .list(out)
}

// MARK: - escre / escurl / join / pathify

public func escre(_ v: Value) -> String {
  let s = (v.asString) ?? ""
  var out = ""
  for c in s {
    switch c {
    case ".", "*", "+", "?", "^", "$", "{", "}", "(", ")", "|", "[", "]", "\\":
      out.append("\\")
      out.append(c)
    default: out.append(c)
    }
  }
  return out
}

public func escurl(_ v: Value) -> String {
  let s = (v.asString) ?? ""
  var allowed = CharacterSet.urlPathAllowed
  allowed.remove(charactersIn: "/:?#[]@!$&'()*+,;=%")
  return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
}

// Named `join` to match the canonical TS export. Free function, doesn't
// shadow `Array.joined(separator:)` (different signature, different name).
public func join(_ parts: Value, _ sep: String = "") -> String {
  guard case .list(let l) = parts else { return "" }
  return l.items.map { stringify($0) }.joined(separator: sep)
}

public func pathify(_ v: Value, _ depth: Int = 0) -> String {
  var parts: [String] = []
  switch v {
  case .list(let l):
    parts = l.items.compactMap { iv -> String? in
      if iv.isNoval { return nil }
      return stringify(iv)
    }
  case .string(let s): parts = s.split(separator: ".").map(String.init)
  case .int(let n): parts = [String(n)]
  case .double(let d): parts = [JSON.formatDouble(d)]
  default: return "<unknown-path>"
  }
  if depth > 0, parts.count > depth { parts.removeFirst(depth) }
  if parts.isEmpty { return "<root>" }
  return parts.joined(separator: ".")
}

// MARK: - jsonify / stringify

public func jsonify(_ v: Value, indent: Int = 0) -> String {
  JSON.stringify(v, indent: indent)
}

// Human-friendly stringification — sorts map keys alphabetically and
// strips double-quotes (matches canonical TS stringify).
public func stringify(_ v: Value, _ maxlen: Int? = nil) -> String {
  var s: String
  switch v {
  case .noval: s = ""
  case .null: s = "null"
  case .bool(let b): s = b ? "true" : "false"
  case .int(let n): s = String(n)
  case .double(let d): s = JSON.formatDouble(d)
  case .string(let str): s = str
  case .sentinel(let sen): s = sen.marker
  case .function: s = "<function>"
  case .list, .map:
    s = emitSorted(v)
    s = s.replacingOccurrences(of: "\"", with: "")
  }
  if let m = maxlen, m > 0, s.count > m {
    if m < 3 {
      s = String(s.prefix(m))
    } else {
      s = String(s.prefix(m - 3)) + "..."
    }
  }
  return s
}

private func emitSorted(_ v: Value) -> String {
  switch v {
  case .list(let l):
    if l.items.isEmpty { return "[]" }
    return "[" + l.items.map { emitSorted($0) }.joined(separator: ",") + "]"
  case .map(let m):
    if m.entries.isEmpty { return "{}" }
    let keys = m.entries.keys.sorted()
    return "{"
      + keys.map { JSON.quotedKey($0) + ":" + emitSorted(m.entries[$0]!) }.joined(separator: ",")
      + "}"
  case .noval, .null: return "null"
  case .bool(let b): return b ? "true" : "false"
  case .int(let n): return String(n)
  case .double(let d): return JSON.formatDouble(d)
  case .string(let s): return JSON.quotedKey(s)
  case .sentinel(let s): return "\"" + s.marker + "\""
  case .function: return "\"<function>\""
  }
}

// MARK: - clone

public func clone(_ v: Value) -> Value {
  var seen: [ObjectIdentifier: Value] = [:]
  return cloneInner(v, &seen)
}

private func cloneInner(_ v: Value, _ seen: inout [ObjectIdentifier: Value]) -> Value {
  switch v {
  case .list(let l):
    let id = ObjectIdentifier(l)
    if let c = seen[id] { return c }
    let nl = VList()
    let nv: Value = .list(nl)
    seen[id] = nv
    for item in l.items { nl.items.append(cloneInner(item, &seen)) }
    return nv
  case .map(let m):
    let id = ObjectIdentifier(m)
    if let c = seen[id] { return c }
    let nm = VMap()
    let nv: Value = .map(nm)
    seen[id] = nv
    for (k, item) in m.entries { nm.entries[k] = cloneInner(item, &seen) }
    return nv
  default: return v
  }
}

// MARK: - quotedKey helper exposed for stringify

extension JSON {
  internal static func quotedKey(_ s: String) -> String { quoted(s) }

  public static func formatDouble(_ d: Double) -> String {
    if d.isNaN || d.isInfinite { return "null" }
    if d == d.rounded() && abs(d) < 1e16 {
      return String(Int64(d))
    }
    return String(format: "%.17g", d)
  }
}
