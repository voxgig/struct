// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
// Voxgig Struct — Swift port of the canonical TypeScript implementation.
// See ../REPORT.md for cross-language parity.

import Foundation
import OrderedCollections

// MARK: - Sentinel
//
// Singleton "marker" objects compared by reference identity. Two
// pre-allocated sentinels — `SKIP` and `DELETE` — are recognised by
// `setprop` to skip or delete a slot. Map literals such as
// ``"`$SKIP`": true`` (which serialise to/from JSON) compare equal to the
// matching sentinel when emitted via `Value.sentinel(SKIP)`.

public final class Sentinel: @unchecked Sendable {
    public let tag: String
    public let marker: String
    public init(tag: String, marker: String) { self.tag = tag; self.marker = marker }
}

public let SKIP = Sentinel(tag: "SKIP", marker: "`$SKIP`")
public let DELETE = Sentinel(tag: "DELETE", marker: "`$DELETE`")

// MARK: - Collection wrappers (reference-stable lists and maps)

public final class VList: @unchecked Sendable {
    public var items: [Value]
    public init(_ items: [Value] = []) { self.items = items }
}

public final class VMap: @unchecked Sendable {
    public var entries: OrderedDictionary<String, Value>
    public init(_ entries: OrderedDictionary<String, Value> = [:]) { self.entries = entries }
    public init(_ pairs: [(String, Value)]) {
        var d = OrderedDictionary<String, Value>()
        for (k, v) in pairs { d[k] = v }
        self.entries = d
    }
}

// MARK: - Injector / Modify function types

public typealias Injector = (Injection, Value, String, Value) -> Value
public typealias Modify = (Value, Value, Value, Injection, Value) -> Void

// MARK: - Value
//
// One JSON-shaped node plus the language-runtime extras the canonical
// inject machinery needs: a `.noval` case for "absent" (TS undefined,
// distinct from JSON null), a `.function` case for transform command
// handlers, and a `.sentinel` case for the SKIP/DELETE markers.

public indirect enum Value: @unchecked Sendable {
    case noval
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case list(VList)
    case map(VMap)
    case function(Injector)
    case sentinel(Sentinel)

    // MARK: Convenience constructors

    public static func list(_ items: [Value]) -> Value { .list(VList(items)) }
    public static func map(_ pairs: [(String, Value)]) -> Value { .map(VMap(pairs)) }
    public static func map(_ entries: OrderedDictionary<String, Value>) -> Value { .map(VMap(entries)) }

    // MARK: Predicates

    public var isNoval: Bool   { if case .noval = self { return true } else { return false } }
    public var isNull: Bool    { if case .null = self  { return true } else { return false } }
    public var isBool: Bool    { if case .bool = self  { return true } else { return false } }
    public var isInt: Bool     { if case .int = self   { return true } else { return false } }
    public var isDouble: Bool  { if case .double = self { return true } else { return false } }
    public var isNumber: Bool  { isInt || isDouble }
    public var isString: Bool  { if case .string = self { return true } else { return false } }
    public var isList: Bool    { if case .list = self  { return true } else { return false } }
    public var isMap: Bool     { if case .map = self   { return true } else { return false } }
    public var isFunction: Bool { if case .function = self { return true } else { return false } }
    public var isSentinel: Bool { if case .sentinel = self { return true } else { return false } }
    public var isNode: Bool    { isList || isMap }

    // MARK: Unwrap helpers

    public var asBool: Bool?       { if case .bool(let b) = self { return b } else { return nil } }
    public var asInt: Int64?       { if case .int(let n) = self { return n } else { return nil } }
    public var asDouble: Double?   {
        switch self {
        case .int(let n): return Double(n)
        case .double(let d): return d
        default: return nil
        }
    }
    public var asString: String?   { if case .string(let s) = self { return s } else { return nil } }
    public var asList: VList?      { if case .list(let l) = self { return l } else { return nil } }
    public var asMap: VMap?        { if case .map(let m) = self { return m } else { return nil } }
    public var asFunction: Injector? { if case .function(let f) = self { return f } else { return nil } }
    public var asSentinel: Sentinel? { if case .sentinel(let s) = self { return s } else { return nil } }

    // MARK: Reference identity for nodes

    public func sameNode(as other: Value) -> Bool {
        switch (self, other) {
        case (.list(let a), .list(let b)): return a === b
        case (.map(let a), .map(let b)):   return a === b
        case (.sentinel(let a), .sentinel(let b)): return a === b
        default: return false
        }
    }
}

// MARK: - Equatable
//
// Structural equality. `.noval` and `.null` are distinct; numeric values
// compare by value across `int`/`double` so `1 == 1.0`; sentinels match by
// pointer identity; function values are never equal (no callable identity).

extension Value: Equatable {
    public static func == (lhs: Value, rhs: Value) -> Bool {
        switch (lhs, rhs) {
        case (.noval, .noval), (.null, .null): return true
        case (.bool(let a), .bool(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.int(let a), .double(let b)): return Double(a) == b
        case (.double(let a), .int(let b)): return a == Double(b)
        case (.string(let a), .string(let b)): return a == b
        case (.list(let a), .list(let b)):
            if a === b { return true }
            if a.items.count != b.items.count { return false }
            for i in 0..<a.items.count { if a.items[i] != b.items[i] { return false } }
            return true
        case (.map(let a), .map(let b)):
            if a === b { return true }
            if a.entries.count != b.entries.count { return false }
            for (k, v) in a.entries {
                guard let bv = b.entries[k], bv == v else { return false }
            }
            return true
        case (.sentinel(let a), .sentinel(let b)): return a === b
        case (.function, .function): return false
        default: return false
        }
    }
}
