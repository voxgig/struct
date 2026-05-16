// Discovery test: pathological regex inputs run against the port's re_* API.
// Goal is to surface failures across ports, not to assert behaviour.
// Panel is the same in every port (see REGEX.md).

import XCTest

@testable import VoxgigStruct

final class RegexPathologicalTests: XCTestCase {
  private func record(_ label: String, _ fn: () -> Any?) {
    let t0 = DispatchTime.now()
    let r = fn()
    let elapsedNs = DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds
    let ms = Double(elapsedNs) / 1_000_000.0
    let outcome: String
    if let r = r {
      outcome = "OK | \(r)"
    } else {
      outcome = "OK | null"
    }
    print(String(format: "[regex-discovery] %@ | %.2fms | %@", label, ms, outcome))
  }

  func testPanel() {
    let a22 = String(repeating: "a", count: 22)
    let nest40 = String(repeating: "(", count: 40) + "a" + String(repeating: ")", count: 40)

    record("P1_redos_nested_plus")      { re_test(.string("^(a+)+$"), a22 + "!") }
    record("P2_redos_alt_overlap")      { re_test(.string("^(a|aa)+$"), a22 + "!") }
    record("P3_empty_repeat_replace")   { re_replace(.string("a*"), "abc", "X") }
    record("P4_unicode_replace_dot")    { re_replace(.string("\\."), "café.au.lait", "/") }
    record("P5_unicode_find_codepoint") { re_find(.string("é"), "café au lait") }
    record("P6_deep_nesting_compile")   { re_test(.string(nest40), "a") }
    record("P7_big_bounded_quantifier") { re_test(.string("^a{0,10000}b$"), String(repeating: "a", count: 10) + "b") }
    record("P8_invalid_pattern")        { re_compile("[abc") as Any? }
    record("P9_backref_re2_forbidden")  { re_test(.string("^(a+)\\1$"), "aaaa") }
    record("P10_find_all_zero_width")   { re_find_all(.string("a*"), "bbb") }
  }
}
