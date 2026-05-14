import XCTest
@testable import VoxgigStruct

final class SmokeTests: XCTestCase {
    func testParseAndInject() throws {
        let store = try JSON.parse(#"{"a":1,"b":"hello"}"#)
        let spec  = try JSON.parse(#"{"x":"`a`","y":"`b`"}"#)
        let out   = inject(spec, store)
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
}
