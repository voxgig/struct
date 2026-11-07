import XCTest

@testable import VoxgigStruct

private func compact(_ v: Value) -> String {
  return jsonify(v, indent: 0)
}

private func segs(_ parts: String...) -> Value {
  return .list(parts.map { Value.string($0) })
}

private func isImmutableError(_ err: Error) -> Bool {
  return (err as? StructError)?.message.contains("immutable") ?? false
}

private func symbols(_ cond: Value) -> [String] {
  guard case .list(let sym) = getprop(cond, .string("sym")) else { return [] }
  return sym.items.compactMap { $0.asString }
}

// What the corpus shape cannot express: identity, sharing and the
// immutability contract.
final class CondenseTests: XCTestCase {
  func testDeterministic() throws {
    let src = try JSON.parse(#"{"b":{"m":"GET"},"a":{"m":"GET"},"l":[1,"x",true]}"#)
    XCTAssertEqual(compact(condense(src)), compact(condense(src)))
    // Insertion order must not change the bytes: keys are stored by symbol id.
    let reordered = try JSON.parse(#"{"l":[1,"x",true],"a":{"m":"GET"},"b":{"m":"GET"}}"#)
    XCTAssertEqual(compact(condense(src)), compact(condense(reordered)))
  }

  func testSharesIdenticalSubtrees() throws {
    let one = condense(try JSON.parse(#"{"x":{"m":"GET","p":"/1"}}"#))
    let two = condense(try JSON.parse(#"{"x":{"m":"GET","p":"/1"},"y":{"m":"GET","p":"/1"}}"#))
    XCTAssertEqual(size(getprop(two, .string("node"))), size(getprop(one, .string("node"))))
    let three = condense(try JSON.parse(#"{"x":{"m":"GET"},"y":{"m":"PUT"},"z":{"m":"POST"}}"#))
    XCTAssertGreaterThan(
      size(getprop(three, .string("node"))), size(getprop(two, .string("node"))))
  }

  func testRoundTripsByValue() throws {
    let src = try JSON.parse(#"{"a":{"b":[1,"x",true,null,{}]},"c":"z"}"#)
    XCTAssertEqual(expand(condense(src)), src)
  }

  func testGetpathIsTransparent() throws {
    let src = try JSON.parse(#"{"entity":{"p":{"op":{"list":{"method":"GET"}}}}}"#)
    let c = condense(src)
    let list = segs("entity", "p", "op", "list")
    XCTAssertEqual(getpath(c, list), getpath(src, list))
    XCTAssertEqual(getpath(c, segs("entity", "p", "op", "list", "method")), .string("GET"))
    XCTAssertEqual(getpath(c, segs("entity", "nope")), .noval)
  }

  func testViewReadsWithoutMaterialising() throws {
    let c = condense(try JSON.parse(#"{"entity":{"a":{"v":1},"b":{"v":2}},"other":9}"#))
    let v = condenseview(c)
    XCTAssertEqual(v.keys(.string("entity")), ["a", "b"])
    XCTAssertEqual(v.at(.string("entity")).at(.string("b")).get(.string("v")), .int(2))
    XCTAssertTrue(v.has(.string("entity.a")))
    XCTAssertFalse(v.has(.string("entity.zz")))
    XCTAssertEqual(v.size(), 2)
  }

  func testValueCopiesAndRefShares() throws {
    let c = condense(try JSON.parse(#"{"a":{"m":"GET"},"b":{"m":"GET"}}"#))
    let v = condenseview(c)
    // a and b share one node; get() must not let that be observable.
    let x = v.get(.string("a"))
    let y = v.get(.string("b"))
    XCTAssertEqual(x, y)
    XCTAssertFalse(x.sameNode(as: y))
    try setprop(x, .string("m"), .string("MUTATED"))
    XCTAssertEqual(getprop(v.get(.string("b")), .string("m")), .string("GET"))
    XCTAssertTrue(v.at(.string("a")).ref().sameNode(as: v.at(.string("a")).ref()))
  }

  func testPreservesProtoNamedKeysAndValues() throws {
    let asValue = try JSON.parse(#"{"x":"__proto__"}"#)
    XCTAssertEqual(expand(condense(asValue)), asValue)
    let asKey = try JSON.parse(#"{"__proto__":1}"#)
    XCTAssertEqual(compact(expand(condense(asKey))), #"{"__proto__":1}"#)
  }

  func testGetpathMatchesPlainOnNullAndOptions() throws {
    let withnull = try JSON.parse(#"{"a":null}"#)
    XCTAssertEqual(getpath(condense(withnull), .string("a")), getpath(withnull, .string("a")))
    XCTAssertEqual(getpath(condense(withnull), .string("a")), .noval)
    // injdef.base must not be ignored by the condensed fast read.
    let store = try JSON.parse(#"{"base":{"x":1}}"#)
    let inj = Injection(val: .noval, parent: .noval)
    inj.base = "base"
    XCTAssertEqual(getpath(condense(store), .string("x"), inj), getpath(store, .string("x"), inj))
    XCTAssertEqual(getpath(condense(store), .string("x"), inj), .int(1))
  }

  // Canonical selects nothing for these. This port's plain list read still
  // parses "01", "+1" and "-0" as indexes, so compare with canonical instead.
  func testListKeysAreCanonicalIntegers() throws {
    let c = condense(try JSON.parse(#"{"l":[10,20]}"#))
    for k in ["01", "1e0", " 1", "+1", "1.0", "-0"] {
      XCTAssertEqual(getpath(c, segs("l", k)), .noval, "list key \(k)")
    }
    XCTAssertEqual(getpath(c, segs("l", "1")), .int(20))
  }

  func testSymbolsSortByCodePoint() throws {
    let c = condense(.map([("a", .string("\u{10000}")), ("b", .string("\u{FFFF}"))]))
    let strs = symbols(c)
    let bmp = strs.firstIndex(of: "\u{FFFF}") ?? -1
    let astral = strs.firstIndex(of: "\u{10000}") ?? -1
    XCTAssertTrue(0 <= bmp && bmp < astral, "symbol table is not in code-point order: \(strs)")
  }

  // An invalid key is ignored, so it must not start throwing on a condensed
  // structure; a call that could write still throws.
  func testInvalidKeyMutationsStayNoOps() throws {
    let c = condense(try JSON.parse(#"{"a":1}"#))
    XCTAssertTrue(try delprop(c, .noval).sameNode(as: c))
    XCTAssertTrue(try setprop(c, .noval, .int(1)).sameNode(as: c))
    XCTAssertThrowsError(try delprop(c, .string("sym"))) { XCTAssertTrue(isImmutableError($0)) }
  }

  func testIsImmutable() throws {
    let c = condense(try JSON.parse(#"{"a":1}"#))
    XCTAssertThrowsError(try setpath(c, .string("a"), .int(2))) {
      XCTAssertTrue(isImmutableError($0))
    }
    XCTAssertThrowsError(try setprop(c, .string("a"), .int(2))) {
      XCTAssertTrue(isImmutableError($0))
    }
    XCTAssertThrowsError(try delprop(c, .string("sym"))) { XCTAssertTrue(isImmutableError($0)) }
    // The expanded copy is ordinary and mutable.
    let e = expand(c)
    try setpath(e, .string("a"), .int(2))
    XCTAssertEqual(getprop(e, .string("a")), .int(2))
  }
}
