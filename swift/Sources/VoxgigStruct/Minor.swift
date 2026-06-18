// Minor utilities — type predicates, property access, slicing,
// formatting. Each function mirrors its canonical TS counterpart in
// typescript/src/StructUtility.ts.

import Foundation

// MARK: - typename / typify / getdef

public func typename(_ t: Int) -> String {
  let masked = t & 0x7FFF_FFFF
  if masked == 0 { return TYPENAME_ARR[0] }
  // clz32: the human name is the name of the highest set bit.
  var hb = 0
  var v = masked
  while v > 1 {
    v >>= 1
    hb += 1
  }
  let clz = 31 - hb
  if clz >= 0, clz < TYPENAME_ARR.count {
    let name = TYPENAME_ARR[clz]
    if !name.isEmpty { return name }
  }
  return S_any
}

public func getdef(_ v: Value, _ alt: Value) -> Value {
  return v.isNoval ? alt : v
}

public func typify(_ v: Value) -> Int {
  switch v {
  case .noval: return T_noval
  case .null: return T_scalar | T_null
  case .bool: return T_scalar | T_boolean
  case .int: return T_scalar | T_number | T_integer
  case .double: return T_scalar | T_number | T_decimal
  case .string: return T_scalar | T_string
  case .list: return T_node | T_list
  case .map, .sentinel: return T_node | T_map
  case .function: return T_scalar | T_function
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
  let e = end
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
  let p = padding ?? 44
  let s = stringify(str)
  let need = abs(p) - s.count
  if need <= 0 { return .string(s) }
  let fill = String(repeating: String(padchar), count: need)
  return .string(p < 0 ? fill + s : s + fill)
}

// MARK: - strkey

public func strkey(_ key: Value) -> String {
  switch key {
  case .noval, .null: return ""
  case .string(let s): return s
  case .int(let n): return String(n)
  case .double(let d):
    // Integers stringify as-is; non-integers truncate via floor (canonical
    // strkey: key % 1 === 0 ? String(key) : String(Math.floor(key))).
    if d == d.rounded() { return String(Int64(d)) }
    return String(Int64(d.rounded(.down)))
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
  // Group A: a null (or absent) slot counts as "no value" → alt.
  return (v.isNoval || v.isNull) ? alt : v
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
    guard let idx = k else { return val }
    if idx >= 0 {
      // Set or append; an out-of-range index clamps to the end (no null gap).
      let target = min(idx, l.items.count)
      if target < l.items.count { l.items[target] = newval } else { l.items.append(newval) }
    } else {
      // A negative index prepends.
      l.items.insert(newval, at: 0)
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
    guard let idx = k else { return val }
    // A negative or out-of-range index is a no-op (no end-relative delete).
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
  // keysof() sorts map keys (and yields "0","1",… for lists), so items are in
  // the same order the canonical implementation produces. lookup preserves a
  // stored JSON null in the tuple.
  if !isnode(v) { return [] }
  return keysof(v).map { k in [.string(k), lookup(v, .string(k))] }
}

public func flatten(_ v: Value, _ depth: Int? = nil) -> Value {
  guard case .list(let l) = v else { return v }
  return .list(flattenDepth(l.items, depth ?? 1))
}

private func flattenDepth(_ items: [Value], _ depth: Int) -> [Value] {
  var out: [Value] = []
  for item in items {
    if depth > 0, case .list(let inner) = item {
      out.append(contentsOf: flattenDepth(inner.items, depth - 1))
    } else {
      out.append(item)
    }
  }
  return out
}

public func filter(_ v: Value, _ pred: (Value, Value) -> Bool) -> Value {
  // Canonical filter passes each [key,value] pair to the check and returns the
  // matched VALUES (not the pairs).
  var out: [Value] = []
  for pair in items(v) where pred(pair[0], pair[1]) {
    out.append(pair[1])
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
public func join(_ parts: Value, _ sep: String = ",", _ url: Bool = false) -> String {
  guard case .list(let l) = parts else { return "" }
  let sarr = l.items.count
  let sc: Character? = sep.count == 1 ? sep.first : nil
  // Keep only the non-empty string elements.
  var inner: [String] = []
  for it in l.items {
    if case .string(let s) = it, !s.isEmpty { inner.append(s) }
  }
  var mapped: [String] = []
  for (i, orig) in inner.enumerated() {
    var s = orig
    if let sc = sc {
      let scs = String(sc)
      if url && i == 0 {
        while s.hasSuffix(scs) { s.removeLast() }
        mapped.append(s)
        continue
      }
      if i > 0 {
        while s.hasPrefix(scs) { s.removeFirst() }
      }
      if i < sarr - 1 || !url {
        while s.hasSuffix(scs) { s.removeLast() }
      }
      s = collapseSep(s, sc, sep)
    }
    mapped.append(s)
  }
  return mapped.filter { !$0.isEmpty }.joined(separator: sep)
}

// Collapse internal runs of the separator (when bounded by non-separator chars
// on both sides) down to a single separator. Mirrors the canonical regex
// `([^sep])sep+([^sep]) -> $1 sepdef $2`.
private func collapseSep(_ s: String, _ sc: Character, _ sepdef: String) -> String {
  let chars = Array(s)
  var out = ""
  var i = 0
  while i < chars.count {
    if chars[i] == sc {
      var j = i
      while j < chars.count && chars[j] == sc { j += 1 }
      let prevNon = i > 0 && chars[i - 1] != sc
      let nextNon = j < chars.count && chars[j] != sc
      if prevNon && nextNon {
        out += sepdef
      } else {
        out += String(repeating: String(sc), count: j - i)
      }
      i = j
    } else {
      out.append(chars[i])
      i += 1
    }
  }
  return out
}

public func pathify(_ v: Value, _ startin: Int? = nil, _ endin: Int? = nil) -> String {
  var path: [Value]? = nil
  switch v {
  case .list(let l): path = l.items
  case .string, .int, .double: path = [v]
  default: path = nil
  }
  let start = startin == nil ? 0 : (startin! > -1 ? startin! : 0)
  let end = endin == nil ? 0 : (endin! > -1 ? endin! : 0)

  var pathstr: String? = nil
  if let p = path, start >= 0 {
    let lo = min(start, p.count)
    let hiRaw = p.count - end
    let hi = hiRaw < lo ? lo : min(hiRaw, p.count)
    let sliced = lo < hi ? Array(p[lo..<hi]) : []
    if sliced.isEmpty {
      pathstr = "<root>"
    } else {
      // Keep only key segments; floor numbers and strip dots from strings.
      let segs = sliced.filter { iskey($0) }.map { seg -> String in
        switch seg {
        case .int(let n): return String(n)
        case .double(let d): return String(Int64(d.rounded(.down)))
        case .string(let s): return s.replacingOccurrences(of: ".", with: "")
        default: return ""
        }
      }
      pathstr = segs.joined(separator: ".")
    }
  }
  if pathstr == nil {
    let suffix = v.isNoval ? "" : (":" + stringify(v, 47))
    pathstr = "<unknown-path" + suffix + ">"
  }
  return pathstr!
}

// MARK: - jsonify / stringify

public func jsonify(_ v: Value, indent: Int = 2, offset: Int = 0) -> String {
  var str = JSON.stringify(v, indent: indent)
  if offset > 0 {
    // Left-offset the entire indented JSON so it aligns with surrounding code
    // indented by `offset`; the first brace stays on the assignment line.
    var lines = str.components(separatedBy: "\n")
    if !lines.isEmpty { lines.removeFirst() }
    let pad = String(repeating: " ", count: offset)
    str = "{\n" + lines.map { pad + $0 }.joined(separator: "\n")
  }
  return str
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
