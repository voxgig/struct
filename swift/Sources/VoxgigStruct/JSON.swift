// Insertion-order-preserving JSON parser and serialiser.
//
// `JSONSerialization` (Foundation) returns plain `[String: Any]` whose
// iteration order is unspecified. The canonical contract — and the
// inject machinery's `$`-suffix key partitioning — both require
// insertion order survives the parse round-trip. We hand-roll a small
// recursive-descent parser that builds `VMap` directly.

import Foundation

public enum JSONParseError: Error {
    case unexpected(String, Int)
    case unterminated(Int)
    case trailing(Int)
}

public enum JSON {

    public static func parse(_ text: String) throws -> Value {
        var p = Parser(text: text)
        p.skipWS()
        let v = try p.parseValue()
        p.skipWS()
        if p.pos < p.bytes.count {
            throw JSONParseError.trailing(p.pos)
        }
        return v
    }

    public static func stringify(_ v: Value, indent: Int = 0) -> String {
        var out = ""
        emit(v, into: &out, indent: indent, depth: 0)
        return out
    }

    // MARK: - Parser

    fileprivate struct Parser {
        let bytes: [UInt8]
        var pos: Int = 0
        init(text: String) { self.bytes = Array(text.utf8) }

        mutating func skipWS() {
            while pos < bytes.count {
                let b = bytes[pos]
                if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { pos += 1 } else { break }
            }
        }

        mutating func parseValue() throws -> Value {
            skipWS()
            guard pos < bytes.count else { throw JSONParseError.unexpected("end", pos) }
            let c = bytes[pos]
            switch c {
            case UInt8(ascii: "{"): return try parseObject()
            case UInt8(ascii: "["): return try parseArray()
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"), UInt8(ascii: "f"), UInt8(ascii: "n"): return try parseKeyword()
            default: return try parseNumber()
            }
        }

        mutating func parseObject() throws -> Value {
            pos += 1 // consume {
            var d = OrderedDictionary<String, Value>()
            skipWS()
            if pos < bytes.count, bytes[pos] == UInt8(ascii: "}") { pos += 1; return .map(VMap(d)) }
            while true {
                skipWS()
                guard pos < bytes.count, bytes[pos] == UInt8(ascii: "\"") else {
                    throw JSONParseError.unexpected("expected key", pos)
                }
                let key = try parseString()
                skipWS()
                guard pos < bytes.count, bytes[pos] == UInt8(ascii: ":") else {
                    throw JSONParseError.unexpected("expected :", pos)
                }
                pos += 1
                let val = try parseValue()
                d[key] = val
                skipWS()
                guard pos < bytes.count else { throw JSONParseError.unexpected("end", pos) }
                let next = bytes[pos]
                if next == UInt8(ascii: ",") { pos += 1; continue }
                if next == UInt8(ascii: "}") { pos += 1; break }
                throw JSONParseError.unexpected("expected , or }", pos)
            }
            return .map(VMap(d))
        }

        mutating func parseArray() throws -> Value {
            pos += 1 // consume [
            var a: [Value] = []
            skipWS()
            if pos < bytes.count, bytes[pos] == UInt8(ascii: "]") { pos += 1; return .list(VList(a)) }
            while true {
                a.append(try parseValue())
                skipWS()
                guard pos < bytes.count else { throw JSONParseError.unexpected("end", pos) }
                let next = bytes[pos]
                if next == UInt8(ascii: ",") { pos += 1; continue }
                if next == UInt8(ascii: "]") { pos += 1; break }
                throw JSONParseError.unexpected("expected , or ]", pos)
            }
            return .list(VList(a))
        }

        mutating func parseString() throws -> String {
            pos += 1 // consume "
            var out: [UInt8] = []
            while pos < bytes.count {
                let c = bytes[pos]
                if c == UInt8(ascii: "\"") { pos += 1; return String(decoding: out, as: UTF8.self) }
                if c == UInt8(ascii: "\\") {
                    guard pos + 1 < bytes.count else { throw JSONParseError.unterminated(pos) }
                    let e = bytes[pos + 1]
                    switch e {
                    case UInt8(ascii: "\""): out.append(UInt8(ascii: "\"")); pos += 2
                    case UInt8(ascii: "\\"): out.append(UInt8(ascii: "\\")); pos += 2
                    case UInt8(ascii: "/"):  out.append(UInt8(ascii: "/"));  pos += 2
                    case UInt8(ascii: "b"):  out.append(0x08); pos += 2
                    case UInt8(ascii: "f"):  out.append(0x0C); pos += 2
                    case UInt8(ascii: "n"):  out.append(0x0A); pos += 2
                    case UInt8(ascii: "r"):  out.append(0x0D); pos += 2
                    case UInt8(ascii: "t"):  out.append(0x09); pos += 2
                    case UInt8(ascii: "u"):
                        guard pos + 5 < bytes.count else { throw JSONParseError.unterminated(pos) }
                        let hex = String(decoding: bytes[(pos + 2)..<(pos + 6)], as: UTF8.self)
                        guard let code = UInt32(hex, radix: 16),
                              let scalar = Unicode.Scalar(code) else {
                            throw JSONParseError.unexpected("bad \\u escape", pos)
                        }
                        out.append(contentsOf: String(scalar).utf8)
                        pos += 6
                    default:
                        out.append(e); pos += 2
                    }
                } else {
                    out.append(c); pos += 1
                }
            }
            throw JSONParseError.unterminated(pos)
        }

        mutating func parseKeyword() throws -> Value {
            if pos + 4 <= bytes.count,
               bytes[pos] == 0x74, bytes[pos + 1] == 0x72,
               bytes[pos + 2] == 0x75, bytes[pos + 3] == 0x65 {
                pos += 4; return .bool(true)
            }
            if pos + 5 <= bytes.count,
               bytes[pos] == 0x66, bytes[pos + 1] == 0x61,
               bytes[pos + 2] == 0x6C, bytes[pos + 3] == 0x73,
               bytes[pos + 4] == 0x65 {
                pos += 5; return .bool(false)
            }
            if pos + 4 <= bytes.count,
               bytes[pos] == 0x6E, bytes[pos + 1] == 0x75,
               bytes[pos + 2] == 0x6C, bytes[pos + 3] == 0x6C {
                pos += 4; return .null
            }
            throw JSONParseError.unexpected("expected true/false/null", pos)
        }

        mutating func parseNumber() throws -> Value {
            let start = pos
            if pos < bytes.count, bytes[pos] == UInt8(ascii: "-") { pos += 1 }
            var hasFraction = false
            while pos < bytes.count {
                let b = bytes[pos]
                if (b >= 0x30 && b <= 0x39) || b == UInt8(ascii: ".")
                    || b == UInt8(ascii: "e") || b == UInt8(ascii: "E")
                    || b == UInt8(ascii: "+") || b == UInt8(ascii: "-") {
                    if b == UInt8(ascii: ".") || b == UInt8(ascii: "e") || b == UInt8(ascii: "E") {
                        hasFraction = true
                    }
                    pos += 1
                } else {
                    break
                }
            }
            let raw = String(decoding: bytes[start..<pos], as: UTF8.self)
            if hasFraction {
                guard let d = Double(raw) else { throw JSONParseError.unexpected("bad number", start) }
                return .double(d)
            }
            if let n = Int64(raw) { return .int(n) }
            if let d = Double(raw) { return .double(d) }
            throw JSONParseError.unexpected("bad number", start)
        }
    }

    // MARK: - Stringify

    fileprivate static func emit(_ v: Value, into out: inout String, indent: Int, depth: Int) {
        switch v {
        case .noval, .null: out += "null"
        case .bool(let b):   out += b ? "true" : "false"
        case .int(let n):    out += String(n)
        case .double(let d): out += formatDouble(d)
        case .string(let s): out += quoted(s)
        case .list(let l):
            if l.items.isEmpty { out += "[]"; return }
            if indent > 0 {
                let pad = String(repeating: " ", count: indent * (depth + 1))
                let end = String(repeating: " ", count: indent * depth)
                out += "[\n"
                for (i, item) in l.items.enumerated() {
                    out += pad
                    emit(item, into: &out, indent: indent, depth: depth + 1)
                    if i < l.items.count - 1 { out += "," }
                    out += "\n"
                }
                out += end + "]"
            } else {
                out += "["
                for (i, item) in l.items.enumerated() {
                    emit(item, into: &out, indent: 0, depth: depth + 1)
                    if i < l.items.count - 1 { out += "," }
                }
                out += "]"
            }
        case .map(let m):
            if m.entries.isEmpty { out += "{}"; return }
            if indent > 0 {
                let pad = String(repeating: " ", count: indent * (depth + 1))
                let end = String(repeating: " ", count: indent * depth)
                out += "{\n"
                let count = m.entries.count
                for (i, kv) in m.entries.enumerated() {
                    out += pad + quoted(kv.key) + ": "
                    emit(kv.value, into: &out, indent: indent, depth: depth + 1)
                    if i < count - 1 { out += "," }
                    out += "\n"
                }
                out += end + "}"
            } else {
                out += "{"
                let count = m.entries.count
                for (i, kv) in m.entries.enumerated() {
                    out += quoted(kv.key) + ":"
                    emit(kv.value, into: &out, indent: 0, depth: depth + 1)
                    if i < count - 1 { out += "," }
                }
                out += "}"
            }
        case .function:    out += "\"<function>\""
        case .sentinel(let s): out += quoted(s.marker)
        }
    }

    internal static func quoted(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\u{08}": out += "\\b"
            case "\u{09}": out += "\\t"
            case "\u{0A}": out += "\\n"
            case "\u{0C}": out += "\\f"
            case "\u{0D}": out += "\\r"
            default:
                if c.value < 0x20 {
                    out += String(format: "\\u%04x", c.value)
                } else {
                    out.unicodeScalars.append(c)
                }
            }
        }
        out += "\""
        return out
    }
}
