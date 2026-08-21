import XCTest

@testable import VoxgigStruct

// The corpus never supplies an error sink - every `err:` entry calls
// `validate`/`transform` with no injdef, or (`validate/special`) with one
// carrying only `meta` - so it pins the THROWING half of canonical's
// `collect = null != injdef?.errs` and nothing else. These pin the other half,
// which is why the collecting path could regress unnoticed.
final class ErrSinkTests: XCTestCase {
  private func badspec() throws -> (Value, Value) {
    return (try JSON.parse(#"{"a":"s"}"#), try JSON.parse(#"{"a":"`$NUMBER`"}"#))
  }

  func testValidateThrowsWithoutSink() throws {
    let (data, spec) = try badspec()
    XCTAssertThrowsError(try validate(data, spec))
  }

  // An injdef that carries no sink is still a throw - `validate/special#7`
  // depends on it, so "an injdef was passed" cannot stand in for "collect".
  func testValidateThrowsWithSinklessInjection() throws {
    let (data, spec) = try badspec()
    let inj = Injection(val: .noval, parent: .noval)
    inj.meta = VMap()
    XCTAssertThrowsError(try validate(data, spec, inj))
  }

  func testValidateCollectsIntoSuppliedSink() throws {
    let (data, spec) = try badspec()
    let inj = Injection(val: .noval, parent: .noval)
    let errs = VList()
    inj.errs = errs
    XCTAssertNoThrow(try validate(data, spec, inj))
    XCTAssertEqual(1, errs.items.count)
    guard case .string(let msg) = errs.items[0] else {
      return XCTFail("expected a string error, got \(errs.items[0])")
    }
    XCTAssertTrue(msg.contains("a"), "error should name the failing field: \(msg)")
  }

  // `transform/format#12`, verbatim - the corpus asserts it throws; here it
  // must land in the sink instead.
  private func badformat() throws -> (Value, Value) {
    return (.null, try JSON.parse(#"["`$FORMAT`","not-a-format","a"]"#))
  }

  func testTransformCollectsIntoSuppliedSink() throws {
    let (data, spec) = try badformat()
    let inj = Injection(val: .noval, parent: .noval)
    let errs = VList()
    inj.errs = errs
    XCTAssertNoThrow(try transform(data, spec, inj))
    XCTAssertEqual(1, errs.items.count)
    guard case .string(let msg) = errs.items[0] else {
      return XCTFail("expected a string error, got \(errs.items[0])")
    }
    XCTAssertTrue(msg.contains("not-a-format"), "error should name the format: \(msg)")
  }

  func testTransformThrowsWithoutSink() throws {
    let (data, spec) = try badformat()
    XCTAssertThrowsError(try transform(data, spec))
  }

  // Reading `errs` is what the collecting internals do on every error; only
  // assigning it may flip the gate.
  func testReadingErrsDoesNotSupplyASink() {
    let inj = Injection(val: .noval, parent: .noval)
    XCTAssertFalse(inj.errssupplied)
    inj.errs.items.append(.string("internal"))
    XCTAssertFalse(inj.errssupplied)
    inj.errs = VList()
    XCTAssertTrue(inj.errssupplied)
  }
}
