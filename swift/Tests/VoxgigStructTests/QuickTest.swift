import XCTest
@testable import VoxgigStruct

final class QuickTest: XCTestCase {
    func testInjectStringDirect() throws {
        let store = try JSON.parse(#"{"a":1}"#)
        let r = inject(Value.string("`a`"), store)
        print("== Got:", r, "stringify:", stringify(r))
        XCTAssertEqual(r, .int(1))
    }
    func testInjectStringFromValEntry() throws {
        // Simulates inject.string entry 0: in={val:"`a`",store:{a:1}}, out=1
        let entry = try JSON.parse(#"{"in":{"val":"`a`","store":{"a":1}}}"#)
        let in0 = getprop(entry, .string("in"))
        let v = clone(getprop(in0, .string("val")))
        let s = getprop(in0, .string("store"))
        let r = inject(v, s)
        print("== Entry got:", r, "stringify:", stringify(r))
        XCTAssertEqual(r, .int(1))
    }
}
