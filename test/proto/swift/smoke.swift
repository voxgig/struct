// Smoke check for the Swift Test Provider port. Loads the corpus and prints a
// summary that must match the canonical TS reference numbers.
//
// Build/run (when a Swift toolchain is available), from test/proto/swift/:
//   swiftc Provider.swift smoke.swift -o smoke && ./smoke
//
// Expected output:
//   functions: minor, getpath, inject, merge, transform, walk, validate, select, sentinels
//   total entries: 1325
//   expect kinds: value=1181, absent=84, match=1, error=59
//   input kinds: in=1325, args=0, ctx=0
//   getpath/basic[0]: id=getpath/basic#deep, doc=true, input.kind=in, expect.kind=value, expect.value=42

import Foundation

let provider = TestProvider.load()

let functions = provider.functions()
print("functions: " + functions.joined(separator: ", "))

var total = 0
var expectCounts: [String: Int] = [:]
var inputCounts: [String: Int] = [:]

for fn in functions {
  for entry in provider.entries(fn) {
    total += 1
    expectCounts[entry.expect.kind.rawValue, default: 0] += 1
    inputCounts[entry.input.kind.rawValue, default: 0] += 1
  }
}

print("total entries: \(total)")
print(
  "expect kinds: value=\(expectCounts["value", default: 0]), "
    + "absent=\(expectCounts["absent", default: 0]), "
    + "match=\(expectCounts["match", default: 0]), "
    + "error=\(expectCounts["error", default: 0])")
print(
  "input kinds: in=\(inputCounts["in", default: 0]), "
    + "args=\(inputCounts["args", default: 0]), "
    + "ctx=\(inputCounts["ctx", default: 0])")

let basic = provider.entries("getpath", group: "basic")
if let e0 = basic.first {
  let id = e0.id ?? "<none>"
  let expectValue = e0.expect.value.map { stringify($0) } ?? "<none>"
  print(
    "getpath/basic[0]: id=\(id), doc=\(e0.doc), "
      + "input.kind=\(e0.input.kind.rawValue), "
      + "expect.kind=\(e0.expect.kind.rawValue), "
      + "expect.value=\(expectValue)")
}
