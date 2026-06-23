// Test Provider (prototype) — Swift port of the canonical ts/provider.ts.
//
// Reads the shared corpus (build/test/test.json) and hands test code clean,
// normalized cases. It is NOT a test runner: it never calls the subject and
// never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
//
// Dependency-free: Foundation (stdlib) only, no SwiftPM third-party deps.
//
// IMPORTANT: Foundation's JSONSerialization yields NSDictionary, which does
// not preserve key order. functions()/groups() must return corpus order
// (minor first), so this file ships a small order-preserving JSON parser that
// yields a JSON enum with ordered object pairs.

import Foundation

private let NULLMARK = "__NULL__"
private let UNDEFMARK = "__UNDEF__"
private let EXISTSMARK = "__EXISTS__"

// ─── order-preserving JSON value ───────────────────────────────────────────

/// An order-preserving JSON value. Object pairs keep their source order so
/// functions()/groups() can return corpus order.
public enum JSON {
  case null
  case bool(Bool)
  case num(Double)
  case str(String)
  case arr([JSON])
  case obj([(String, JSON)])
}

extension JSON {
  /// Whether this is an object (map) node.
  public var isObject: Bool {
    if case .obj = self { return true }
    return false
  }

  /// Whether this is an array (list) node.
  public var isArray: Bool {
    if case .arr = self { return true }
    return false
  }

  /// The ordered object pairs, or nil if not an object.
  public var pairs: [(String, JSON)]? {
    if case .obj(let p) = self { return p }
    return nil
  }

  /// The array items, or nil if not an array.
  public var items: [JSON]? {
    if case .arr(let a) = self { return a }
    return nil
  }

  /// Whether the (object) node contains `key` — KEY PRESENCE, not null-check.
  public func has(_ key: String) -> Bool {
    if case .obj(let p) = self {
      for (k, _) in p where k == key { return true }
    }
    return false
  }

  /// Value for `key` in an object node, by key presence. Returns nil if the
  /// key is absent. A present key whose value is JSON null returns `.null`.
  public func get(_ key: String) -> JSON? {
    if case .obj(let p) = self {
      for (k, v) in p where k == key { return v }
    }
    return nil
  }

  /// String value if `.str`, else nil.
  public var asString: String? {
    if case .str(let s) = self { return s }
    return nil
  }

  /// The ordered keys of an object node (empty for non-objects).
  public var keys: [String] {
    if case .obj(let p) = self { return p.map { $0.0 } }
    return []
  }

  /// Compact JSON serialization with stable (source) object order.
  public func compact() -> String {
    switch self {
    case .null:
      return "null"
    case .bool(let b):
      return b ? "true" : "false"
    case .num(let n):
      return JSON.numString(n)
    case .str(let s):
      return JSON.encodeString(s)
    case .arr(let a):
      return "[" + a.map { $0.compact() }.joined(separator: ",") + "]"
    case .obj(let p):
      return "{"
        + p.map { JSON.encodeString($0.0) + ":" + $0.1.compact() }.joined(separator: ",")
        + "}"
    }
  }

  // Render a Double the way JSON expects: integral values without a trailing
  // ".0", non-integral values via Swift's shortest round-trippable form.
  static func numString(_ n: Double) -> String {
    if n == n.rounded() && abs(n) < 1e15 && n.isFinite {
      return String(Int64(n))
    }
    return String(n)
  }

  static func encodeString(_ s: String) -> String {
    var out = "\""
    for ch in s.unicodeScalars {
      switch ch {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      case "\u{08}": out += "\\b"
      case "\u{0C}": out += "\\f"
      default:
        if ch.value < 0x20 {
          out += String(format: "\\u%04x", ch.value)
        } else {
          out.unicodeScalars.append(ch)
        }
      }
    }
    out += "\""
    return out
  }
}

// ─── hand-rolled, order-preserving JSON parser ─────────────────────────────

public enum JSONParseError: Error, CustomStringConvertible {
  case unexpected(String, Int)

  public var description: String {
    switch self {
    case .unexpected(let msg, let pos): return "JSON parse error at \(pos): \(msg)"
    }
  }
}

public enum JSONParser {
  public static func parse(_ text: String) throws -> JSON {
    var p = Cursor(Array(text.unicodeScalars))
    p.skipWhitespace()
    let value = try p.parseValue()
    p.skipWhitespace()
    if !p.atEnd {
      throw JSONParseError.unexpected("trailing content", p.pos)
    }
    return value
  }

  struct Cursor {
    let s: [Unicode.Scalar]
    var pos: Int = 0

    init(_ s: [Unicode.Scalar]) { self.s = s }

    var atEnd: Bool { pos >= s.count }

    func peek() -> Unicode.Scalar? { pos < s.count ? s[pos] : nil }

    mutating func next() -> Unicode.Scalar? {
      guard pos < s.count else { return nil }
      defer { pos += 1 }
      return s[pos]
    }

    mutating func skipWhitespace() {
      while pos < s.count {
        let c = s[pos]
        if c == " " || c == "\t" || c == "\n" || c == "\r" {
          pos += 1
        } else {
          break
        }
      }
    }

    mutating func parseValue() throws -> JSON {
      skipWhitespace()
      guard let c = peek() else {
        throw JSONParseError.unexpected("unexpected end of input", pos)
      }
      switch c {
      case "{": return try parseObject()
      case "[": return try parseArray()
      case "\"": return .str(try parseString())
      case "t", "f": return try parseBool()
      case "n": return try parseNull()
      default: return try parseNumber()
      }
    }

    mutating func parseObject() throws -> JSON {
      pos += 1  // consume '{'
      var pairs: [(String, JSON)] = []
      skipWhitespace()
      if peek() == "}" {
        pos += 1
        return .obj(pairs)
      }
      while true {
        skipWhitespace()
        guard peek() == "\"" else {
          throw JSONParseError.unexpected("expected object key string", pos)
        }
        let key = try parseString()
        skipWhitespace()
        guard next() == ":" else {
          throw JSONParseError.unexpected("expected ':' after object key", pos)
        }
        let value = try parseValue()
        pairs.append((key, value))
        skipWhitespace()
        let sep = next()
        if sep == "," { continue }
        if sep == "}" { break }
        throw JSONParseError.unexpected("expected ',' or '}' in object", pos)
      }
      return .obj(pairs)
    }

    mutating func parseArray() throws -> JSON {
      pos += 1  // consume '['
      var items: [JSON] = []
      skipWhitespace()
      if peek() == "]" {
        pos += 1
        return .arr(items)
      }
      while true {
        let value = try parseValue()
        items.append(value)
        skipWhitespace()
        let sep = next()
        if sep == "," { continue }
        if sep == "]" { break }
        throw JSONParseError.unexpected("expected ',' or ']' in array", pos)
      }
      return .arr(items)
    }

    mutating func parseString() throws -> String {
      pos += 1  // consume opening quote
      var out = String.UnicodeScalarView()
      while let c = next() {
        if c == "\"" {
          return String(out)
        }
        if c == "\\" {
          guard let e = next() else {
            throw JSONParseError.unexpected("unterminated escape", pos)
          }
          switch e {
          case "\"": out.append("\"")
          case "\\": out.append("\\")
          case "/": out.append("/")
          case "n": out.append("\n")
          case "t": out.append("\t")
          case "r": out.append("\r")
          case "b": out.append("\u{08}")
          case "f": out.append("\u{0C}")
          case "u":
            let scalar = try parseUnicodeEscape()
            out.append(scalar)
          default:
            throw JSONParseError.unexpected("invalid escape \\\(e)", pos)
          }
        } else {
          out.append(c)
        }
      }
      throw JSONParseError.unexpected("unterminated string", pos)
    }

    mutating func parseUnicodeEscape() throws -> Unicode.Scalar {
      let high = try hex4()
      // Surrogate pair handling.
      if high >= 0xD800 && high <= 0xDBFF {
        if peek() == "\\" {
          pos += 1
          guard next() == "u" else {
            throw JSONParseError.unexpected("expected low surrogate", pos)
          }
          let low = try hex4()
          if low >= 0xDC00 && low <= 0xDFFF {
            let combined = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
            guard let scalar = Unicode.Scalar(combined) else {
              throw JSONParseError.unexpected("invalid surrogate pair", pos)
            }
            return scalar
          }
          throw JSONParseError.unexpected("invalid low surrogate", pos)
        }
        throw JSONParseError.unexpected("unpaired high surrogate", pos)
      }
      guard let scalar = Unicode.Scalar(high) else {
        throw JSONParseError.unexpected("invalid unicode scalar", pos)
      }
      return scalar
    }

    mutating func hex4() throws -> Int {
      var value = 0
      for _ in 0..<4 {
        guard let c = next(), let d = hexDigit(c) else {
          throw JSONParseError.unexpected("invalid \\u escape", pos)
        }
        value = value * 16 + d
      }
      return value
    }

    func hexDigit(_ c: Unicode.Scalar) -> Int? {
      switch c {
      case "0"..."9": return Int(c.value - 48)
      case "a"..."f": return Int(c.value - 87)
      case "A"..."F": return Int(c.value - 55)
      default: return nil
      }
    }

    mutating func parseBool() throws -> JSON {
      if match("true") { return .bool(true) }
      if match("false") { return .bool(false) }
      throw JSONParseError.unexpected("invalid literal", pos)
    }

    mutating func parseNull() throws -> JSON {
      if match("null") { return .null }
      throw JSONParseError.unexpected("invalid literal", pos)
    }

    mutating func match(_ literal: String) -> Bool {
      let lit = Array(literal.unicodeScalars)
      guard pos + lit.count <= s.count else { return false }
      for (i, ch) in lit.enumerated() where s[pos + i] != ch { return false }
      pos += lit.count
      return true
    }

    mutating func parseNumber() throws -> JSON {
      let start = pos
      if peek() == "-" { pos += 1 }
      while let c = peek(), isNumberChar(c) { pos += 1 }
      let scalars = s[start..<pos]
      let str = String(String.UnicodeScalarView(scalars))
      guard let value = Double(str), !str.isEmpty else {
        throw JSONParseError.unexpected("invalid number '\(str)'", start)
      }
      return .num(value)
    }

    func isNumberChar(_ c: Unicode.Scalar) -> Bool {
      switch c {
      case "0"..."9", ".", "e", "E", "+", "-": return true
      default: return false
      }
    }
  }
}

// ─── tagged Input / Expect / Entry ─────────────────────────────────────────

public enum InputKind: String {
  case `in`
  case args
  case ctx
}

public enum ExpectKind: String {
  case value
  case error
  case match
  case absent
}

public struct Input {
  public let kind: InputKind
  /// The single argument (kind .in; absent "in" key => .null), the positional
  /// argument vector (kind .args), or the context map (kind .ctx).
  public let value: JSON
}

public struct ErrorCheck {
  public let any: Bool
  public let text: String?
  public let regex: Bool
}

public struct Expect {
  public let kind: ExpectKind
  /// Present for kind .value (may be literal JSON null).
  public let value: JSON?
  /// Present for kind .error.
  public let error: ErrorCheck?
  /// Set whenever a "match" key co-exists (also the payload for kind .match).
  public let match: JSON?
}

public struct Entry {
  public let function: String
  public let group: String
  public let index: Int
  public let id: String?
  public let doc: Bool
  public let client: String?
  public let input: Input
  public let expect: Expect
  public let raw: JSON
}

public struct MatchResult {
  public let ok: Bool
  public let path: [String]?
  public let expected: JSON?
  public let actual: JSON?

  public init(ok: Bool, path: [String]? = nil, expected: JSON? = nil, actual: JSON? = nil) {
    self.ok = ok
    self.path = path
    self.expected = expected
    self.actual = actual
  }
}

// ─── the provider ──────────────────────────────────────────────────────────

public final class TestProvider {
  public let spec: JSON

  public init(_ spec: JSON) {
    self.spec = spec
  }

  /// Load and parse the corpus. Default resolves to build/test/test.json
  /// relative to this source file (test/proto/swift -> repo root).
  public static func load(_ path: String? = nil) -> TestProvider {
    let file = path ?? defaultTestFile()
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else {
      fatalError("Failed to read corpus at \(file)")
    }
    do {
      let spec = try JSONParser.parse(text)
      return TestProvider(spec)
    } catch {
      fatalError("Failed to parse corpus at \(file): \(error)")
    }
  }

  private static func defaultTestFile() -> String {
    // #filePath = test/proto/swift/Provider.swift
    let here = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // swift/
      .deletingLastPathComponent()  // proto/
      .deletingLastPathComponent()  // test/
      .deletingLastPathComponent()  // struct/ (repo root)
      .appendingPathComponent("build")
      .appendingPathComponent("test")
      .appendingPathComponent("test.json")
    return here.path
  }

  /// The parsed test.json (escape hatch).
  public func raw() -> JSON {
    return spec
  }

  private func root() -> JSON {
    if let structNode = spec.get("struct") {
      return structNode
    }
    return spec
  }

  private func fnNode(_ fn: String) -> JSON {
    if let node = spec.get("struct")?.get(fn) {
      return node
    }
    if let node = spec.get(fn) {
      return node
    }
    fatalError("Unknown function: \(fn)")
  }

  /// The function names in corpus order (minor first).
  public func functions() -> [String] {
    let r = root()
    return r.keys.filter { k in
      let v = r.get(k)!
      return isGroupBag(v) || hasGroups(v)
    }
  }

  /// The group names for `fn` in corpus order.
  public func groups(_ fn: String) -> [String] {
    let node = fnNode(fn)
    return node.keys.filter { k in
      k != "name" && isGroupBag(node.get(k)!)
    }
  }

  /// All entries across `fn`'s groups, or one group's entries.
  public func entries(_ fn: String, group: String? = nil) -> [Entry] {
    let node = fnNode(fn)
    let groupNames = group != nil ? [group!] : groups(fn)
    var out: [Entry] = []
    for g in groupNames {
      guard let bag = node.get(g), isGroupBag(bag) else { continue }
      guard let set = bag.get("set")?.items else { continue }
      for (i, rawEntry) in set.enumerated() {
        out.append(normalize(fn, g, i, rawEntry))
      }
    }
    return out
  }
}

// A group bag is an object with a `set` array.
private func isGroupBag(_ v: JSON) -> Bool {
  guard v.isObject else { return false }
  return v.get("set")?.isArray == true
}

// A function node has at least one child group bag.
private func hasGroups(_ v: JSON) -> Bool {
  guard case .obj(let pairs) = v else { return false }
  for (k, child) in pairs where k != "name" && isGroupBag(child) { return true }
  return false
}

private func normalize(_ fn: String, _ group: String, _ index: Int, _ raw: JSON) -> Entry {
  return Entry(
    function: fn,
    group: group,
    index: index,
    id: stringField(raw, "id"),
    doc: raw.get("doc").map { isTrue($0) } ?? false,
    client: stringField(raw, "client"),
    input: resolveInput(raw),
    expect: resolveExpect(raw),
    raw: raw
  )
}

private func isTrue(_ v: JSON) -> Bool {
  if case .bool(true) = v { return true }
  return false
}

// Mirror `null != raw.<key>` then String(...): present-and-not-null => string.
private func stringField(_ raw: JSON, _ key: String) -> String? {
  guard let v = raw.get(key) else { return nil }
  switch v {
  case .null: return nil
  case .str(let s): return s
  case .bool(let b): return b ? "true" : "false"
  case .num(let n): return JSON.numString(n)
  default: return v.compact()
  }
}

private func resolveInput(_ raw: JSON) -> Input {
  if raw.has("ctx") {
    return Input(kind: .ctx, value: raw.get("ctx")!)
  }
  if raw.has("args") {
    return Input(kind: .args, value: raw.get("args")!)
  }
  // kind .in, with the single argument; absent "in" key => native null.
  return Input(kind: .in, value: raw.has("in") ? raw.get("in")! : .null)
}

private func parseErr(_ err: JSON) -> ErrorCheck {
  if case .bool(true) = err {
    return ErrorCheck(any: true, text: nil, regex: false)
  }
  if case .str(let s) = err {
    if let inner = regexInner(s) {
      return ErrorCheck(any: false, text: inner, regex: true)
    }
    return ErrorCheck(any: false, text: s, regex: false)
  }
  // Non-true, non-string err spec: treat as "any error".
  return ErrorCheck(any: true, text: nil, regex: false)
}

// "/re/" => "re"; otherwise nil. Mirrors /^\/(.+)\/$/.
private func regexInner(_ s: String) -> String? {
  guard s.count >= 3, s.hasPrefix("/"), s.hasSuffix("/") else { return nil }
  let inner = String(s.dropFirst().dropLast())
  return inner.isEmpty ? nil : inner
}

private func resolveExpect(_ raw: JSON) -> Expect {
  // Attach match whenever a "match" key exists (key presence).
  let matchPart: JSON? = raw.has("match") ? raw.get("match")! : nil
  if raw.has("err") {
    return Expect(
      kind: .error, value: nil, error: parseErr(raw.get("err")!), match: matchPart)
  }
  // "out" present even if JSON null => value (KEY PRESENCE, not null-check).
  if raw.has("out") {
    return Expect(kind: .value, value: raw.get("out")!, error: nil, match: matchPart)
  }
  if raw.has("match") {
    return Expect(kind: .match, value: nil, error: nil, match: raw.get("match")!)
  }
  return Expect(kind: .absent, value: nil, error: nil, match: nil)
}

// ─── pure comparison helpers ───────────────────────────────────────────────

/// `x` if already a string, else compact JSON.
public func stringify(_ x: JSON) -> String {
  if case .str(let s) = x { return s }
  return x.compact()
}

private func normNull(_ x: JSON) -> JSON {
  switch x {
  case .str(let s) where s == NULLMARK:
    return .null
  case .arr(let a):
    return .arr(a.map { normNull($0) })
  case .obj(let p):
    return .obj(p.map { ($0.0, normNull($0.1)) })
  default:
    return x
  }
}

private func normMark(_ x: JSON) -> JSON {
  // Only __NULL__ is normalized; absent stays distinct from null.
  switch x {
  case .str(let s) where s == NULLMARK:
    return .null
  case .arr(let a):
    return .arr(a.map { normMark($0) })
  case .obj(let p):
    return .obj(p.map { ($0.0, normMark($0.1)) })
  default:
    return x
  }
}

/// Scalar primitive match. `check == base`; else if `check` is a string:
/// "/re/" => regex test; otherwise case-insensitive substring containment.
public func matchval(_ check: JSON, _ base: JSON) -> Bool {
  if jsonEqual(check, base) {
    return true
  }
  if case .str(let cs) = check {
    let basestr = stringify(base)
    if let inner = regexInner(cs) {
      return regexTest(inner, basestr)
    }
    return basestr.lowercased().contains(cs.lowercased())
  }
  return false
}

/// Deep equality with null/undefined collapsed (runner default null:true).
public func equal(_ expected: JSON, _ actual: JSON) -> Bool {
  return deepEq(normNull(expected), normNull(actual))
}

/// Strict deep equality: __NULL__ is normalized but absent (here .null carries
/// JSON null only) stays distinct (runner null:false functions).
public func equalStrict(_ expected: JSON, _ actual: JSON) -> Bool {
  return deepEq(normMark(expected), normMark(actual))
}

// Raw structural equality on JSON values (no NULLMARK normalization).
private func jsonEqual(_ a: JSON, _ b: JSON) -> Bool {
  switch (a, b) {
  case (.null, .null): return true
  case (.bool(let x), .bool(let y)): return x == y
  case (.num(let x), .num(let y)): return x == y
  case (.str(let x), .str(let y)): return x == y
  case (.arr(let x), .arr(let y)):
    return x.count == y.count && zip(x, y).allSatisfy { jsonEqual($0.0, $0.1) }
  case (.obj(let x), .obj(let y)):
    guard x.count == y.count else { return false }
    let bm = Dictionary(y.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
    for (k, v) in x {
      guard let bv = bm[k], jsonEqual(v, bv) else { return false }
    }
    return true
  default:
    return false
  }
}

private func deepEq(_ a: JSON, _ b: JSON) -> Bool {
  return jsonEqual(a, b)
}

/// ErrorCheck vs a thrown message. `any` => true; `regex` => regex test;
/// else case-insensitive substring.
public func errorMatches(_ check: ErrorCheck, _ message: String) -> Bool {
  if check.any {
    return true
  }
  guard let text = check.text else {
    return false
  }
  if check.regex {
    return regexTest(text, message)
  }
  return message.lowercased().contains(text.lowercased())
}

/// Partial structural match: every leaf of `check` must match `base` at its
/// path. equal => ok; __UNDEF__ => require absent; __EXISTS__ => require
/// present; else fall back to matchval. First failure returns its path + the
/// two values.
public func structMatch(_ check: JSON, _ base: JSON) -> MatchResult {
  var result = MatchResult(ok: true)
  walkLeaves(check, []) { val, path in
    if !result.ok { return }
    let baseval = getpath(base, path)
    if let bv = baseval, jsonEqual(val, bv) {
      return
    }
    if case .str(let s) = val, s == UNDEFMARK, baseval == nil {
      return
    }
    if case .str(let s) = val, s == EXISTSMARK, let bv = baseval, !isJSONNull(bv) {
      return
    }
    if !matchval(val, baseval ?? .null) {
      result = MatchResult(ok: false, path: path, expected: val, actual: baseval)
    }
  }
  return result
}

private func isJSONNull(_ v: JSON) -> Bool {
  if case .null = v { return true }
  return false
}

private func isNode(_ v: JSON) -> Bool {
  return v.isObject || v.isArray
}

private func walkLeaves(_ node: JSON, _ path: [String], _ fn: (JSON, [String]) -> Void) {
  switch node {
  case .arr(let a):
    for (i, v) in a.enumerated() {
      walkLeaves(v, path + [String(i)], fn)
    }
  case .obj(let p):
    for (k, v) in p {
      walkLeaves(v, path + [k], fn)
    }
  default:
    fn(node, path)
  }
}

// getpath over the JSON tree. Returns nil when a segment is missing (the
// equivalent of `undefined` in the canonical reference).
private func getpath(_ store: JSON, _ path: [String]) -> JSON? {
  var cur: JSON? = store
  for key in path {
    guard let node = cur else { return nil }
    switch node {
    case .arr(let a):
      guard let idx = Int(key), idx >= 0, idx < a.count else { return nil }
      cur = a[idx]
    case .obj:
      cur = node.get(key)  // nil if key absent
    default:
      return nil
    }
  }
  return cur
}

// NSRegularExpression-backed regex test (dependency-free; Foundation only).
private func regexTest(_ pattern: String, _ subject: String) -> Bool {
  guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
  let range = NSRange(subject.startIndex..<subject.endIndex, in: subject)
  return re.firstMatch(in: subject, options: [], range: range) != nil
}
