// Minimal in-tree insertion-ordered dictionary.
//
// Swift's built-in `Dictionary` doesn't preserve insertion order, and the
// canonical contract requires that JSON object key order survive every
// operation. Other ports either get this for free (Python 3.7+ dict,
// Ruby Hash, PHP array, JS object), or hand-roll an OrderedMap
// (C / C++ / Zig). This file is the Swift equivalent — keeps the port
// dependency-free.
//
// Only the operations the rest of VoxgigStruct uses are implemented:
// subscript get/set/remove, `keys`, ordered iteration, `count`,
// `isEmpty`, `removeValue(forKey:)`, and a dictionary-literal init.

import Foundation

public struct OrderedDictionary<Key: Hashable, Value>: Sequence, ExpressibleByDictionaryLiteral {
  public typealias Element = (key: Key, value: Value)

  // Parallel keys + values arrays preserve insertion order. A separate
  // hash table maps key -> index for O(1) lookup. Mutations keep all
  // three in sync; the size is bounded by the corpus's modest map
  // sizes, so even removeValue's O(n) shift on the index is fine.
  @usableFromInline internal var _keys: [Key] = []
  @usableFromInline internal var _values: [Value] = []
  @usableFromInline internal var _indexOf: [Key: Int] = [:]

  public init() {}

  public init(dictionaryLiteral elements: (Key, Value)...) {
    for (k, v) in elements { self[k] = v }
  }

  public var count: Int { _keys.count }
  public var isEmpty: Bool { _keys.isEmpty }
  public var keys: [Key] { _keys }
  public var values: [Value] { _values }

  public subscript(key: Key) -> Value? {
    get {
      guard let i = _indexOf[key] else { return nil }
      return _values[i]
    }
    set {
      if let nv = newValue {
        if let i = _indexOf[key] {
          _values[i] = nv
        } else {
          _indexOf[key] = _keys.count
          _keys.append(key)
          _values.append(nv)
        }
      } else {
        removeValue(forKey: key)
      }
    }
  }

  @discardableResult
  public mutating func removeValue(forKey key: Key) -> Value? {
    guard let i = _indexOf.removeValue(forKey: key) else { return nil }
    let v = _values[i]
    _keys.remove(at: i)
    _values.remove(at: i)
    for j in i..<_keys.count {
      _indexOf[_keys[j]] = j
    }
    return v
  }

  public func makeIterator() -> AnyIterator<Element> {
    var i = 0
    return AnyIterator {
      guard i < self._keys.count else { return nil }
      let e: Element = (key: self._keys[i], value: self._values[i])
      i += 1
      return e
    }
  }
}
