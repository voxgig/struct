import XCTest

@testable import VoxgigStruct

final class SmokeTests: XCTestCase {
  func testParseAndInject() throws {
    let store = try JSON.parse(#"{"a":1,"b":"hello"}"#)
    let spec = try JSON.parse(#"{"x":"`a`","y":"`b`"}"#)
    let out = inject(spec, store)
    XCTAssertEqual(getprop(out, .string("x")), .int(1))
    XCTAssertEqual(getprop(out, .string("y")), .string("hello"))
  }

  func testGetpath() throws {
    let store = try JSON.parse(#"{"a":{"b":{"c":42}}}"#)
    XCTAssertEqual(getpath(store, .string("a.b.c")), .int(42))
  }

  func testMerge() throws {
    let a = try JSON.parse(#"{"a":1,"b":{"x":1}}"#)
    let b = try JSON.parse(#"{"b":{"y":2},"c":3}"#)
    let m = merge(.list([a, b]))
    XCTAssertEqual(getprop(m, .string("a")), .int(1))
    XCTAssertEqual(getprop(getprop(m, .string("b")), .string("x")), .int(1))
    XCTAssertEqual(getprop(getprop(m, .string("b")), .string("y")), .int(2))
    XCTAssertEqual(getprop(m, .string("c")), .int(3))
  }

  // The corpus compiler writes 2.0 as 2, so the host decimal is built here: an
  // integral one is a `$NOF` count, as 2.0 is 2 in JavaScript.
  func testNofCountTakesAnIntegralDecimal() throws {
    let two = Value.list([
      .string("`$NOF`"), .double(2.0), .string("`$NUMBER`"), .string("`$INTEGER`"),
    ])
    XCTAssertEqual(try validate(.int(1), two), .int(1))

    let range = Value.list([
      .string("`$NOF`"), .map([("min", .double(1.0)), ("max", .double(2.0))]),
      .string("`$NUMBER`"), .string("`$INTEGER`"),
    ])
    XCTAssertEqual(try validate(.double(1.5), range), .double(1.5))

    let short = Value.list([
      .string("`$NOF`"), .double(2.0), .string("`$NUMBER`"), .string("`$STRING`"),
    ])
    XCTAssertThrowsError(try validate(.int(1), short)) {
      XCTAssertEqual(
        "Expected exactly 2 of number, string, but found integer: 1.",
        ($0 as? StructError)?.message)
    }
  }
}
