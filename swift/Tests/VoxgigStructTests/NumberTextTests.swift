import XCTest

@testable import VoxgigStruct

// Canonical's number text is ECMA-262's Number::toString. Every expectation
// below is what `String(Number(x))` actually prints under node, not what
// `Double.description` happens to give: the two agree on the digits and
// disagree on where the point goes.
final class NumberTextTests: XCTestCase {
  func testMatchesJSNotation() {
    let cases: [(Double, String)] = [
      (0, "0"),
      (-0.0, "0"),
      (1, "1"),
      (-1, "-1"),
      (100, "100"),
      (0.1, "0.1"),
      (4.4, "4.4"),
      (-4.4, "-4.4"),
      (123.456, "123.456"),
      (1234567890.5, "1234567890.5"),
      (0.0001, "0.0001"),
      // Positional up to 1e21, where Swift goes exponential from 1e16.
      (1e15, "1000000000000000"),
      (1e16, "10000000000000000"),
      (1e17, "100000000000000000"),
      (1e20, "100000000000000000000"),
      (1.2345678901234568e18, "1234567890123456800"),
      (1.2345678901234568e20, "123456789012345680000"),
      (-1e16, "-10000000000000000"),
      // 1e21 and up is exponential in both.
      (1e21, "1e+21"),
      (1e22, "1e+22"),
      (-1e21, "-1e+21"),
      (1.5e300, "1.5e+300"),
      (1.7976931348623157e308, "1.7976931348623157e+308"),
      // Positional down to 1e-6, and no zero-padded exponent below it.
      (1e-5, "0.00001"),
      (1e-6, "0.000001"),
      (1e-7, "1e-7"),
      (-1e-7, "-1e-7"),
      (1e-10, "1e-10"),
      (2.5e-10, "2.5e-10"),
      (Double("1e-323")!, "1e-323"),
      // Shortest round-tripping digits, unchanged.
      (3.0000000000000004, "3.0000000000000004"),
      // Not representable: it rounds to 9007199254740992, and JS prints that.
      (Double("9007199254740993")!, "9007199254740992"),
    ]
    for (d, want) in cases {
      XCTAssertEqual(want, JSON.formatDouble(d), "formatDouble(\(d.description))")
    }
  }

  // Whatever the notation, the text must read back as the same double.
  func testRoundTrips() {
    let vals: [Double] = [
      0.1, 4.4, -4.4, 123.456, 1e15, 1e16, 1e17, 1e20, 1e21, 1e22, 1e-5, 1e-6, 1e-7, 1e-10,
      1.5e300, 1.7976931348623157e308, 3.0000000000000004, 2.5e-10, 1.2345678901234568e20,
    ]
    for d in vals {
      XCTAssertEqual(d, Double(JSON.formatDouble(d)), "round trip of \(d.description)")
    }
  }
}
