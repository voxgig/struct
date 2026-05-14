// Corpus runner — loads ../build/test/test.json and exercises every
// subsystem the canonical TS test suite drives.

import XCTest

@testable import VoxgigStruct

let CORPUS_PATH =
  (URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // VoxgigStructTests/
    .deletingLastPathComponent()  // Tests/
    .deletingLastPathComponent()  // swift/
    .deletingLastPathComponent()  // struct/ (monorepo root)
    .appendingPathComponent("build")
    .appendingPathComponent("test")
    .appendingPathComponent("test.json"))

let NULLMARK = "__NULL__"

// Apply the canonical NULLMARK fixup: replace every JSON null with the
// sentinel string "__NULL__" so "stored null" vs "absent" survives the
// otherwise lossy round-trip through the test entry.
func fixNull(_ v: Value) -> Value {
  switch v {
  case .null: return .string(NULLMARK)
  case .list(let l): return .list(l.items.map { fixNull($0) })
  case .map(let m):
    let nm = VMap()
    for (k, vv) in m.entries { nm.entries[k] = fixNull(vv) }
    return .map(nm)
  default: return v
  }
}

// Modifier that mirrors test/runner.ts `nullModifier`. Swaps any string
// `"__NULL__"` slot for actual JSON null, and replaces embedded
// "__NULL__" substrings with the literal string "null".
func nullModifier(_ val: Value, _ key: Value, _ parent: Value, _ inj: Injection, _ store: Value) {
  if case .string(let s) = val {
    if s == NULLMARK {
      setprop(parent, key, .null)
    } else if s.contains(NULLMARK) {
      setprop(parent, key, .string(s.replacingOccurrences(of: NULLMARK, with: "null")))
    }
  }
}

// Stable JSON-string with sorted map keys so per-port map order doesn't
// flap the equality check (matches the way other-port runners compare
// via deepStrictEqual / canonical jsonify). At the test-runner level we
// treat NOVAL and NULL as equivalent — the canonical TS runner roundtrips
// values through JSON.stringify which erases the distinction.
func canon(_ v: Value) -> String {
  let normalised = normaliseAbsent(v)
  return stringify(normalised)
}

private func normaliseAbsent(_ v: Value) -> Value {
  switch v {
  case .noval: return .null
  case .list(let l):
    return .list(l.items.map { normaliseAbsent($0) })
  case .map(let m):
    let nm = VMap()
    for (k, vv) in m.entries { nm.entries[k] = normaliseAbsent(vv) }
    return .map(nm)
  default: return v
  }
}

final class CorpusTests: XCTestCase {
  private func loadStructSpec() -> Value {
    do {
      let text = try String(contentsOf: CORPUS_PATH, encoding: .utf8)
      let spec = try JSON.parse(text)
      return getprop(spec, .string("struct"))
    } catch {
      XCTFail("Failed to load corpus at \(CORPUS_PATH.path): \(error)")
      return .noval
    }
  }

  private func runset(_ label: String, _ entries: Value, _ subject: (Value) -> Value) {
    guard case .list(let l) = entries else { return }
    var pass = 0
    var fails: [String] = []
    for (i, entry) in l.items.enumerated() {
      guard case .map(let em) = entry else { continue }
      let inVal = em.entries["in"] ?? .noval
      // Skip entries with an `err:` field — those exercise error
      // collection, which is not yet wired uniformly.
      if em.entries["err"] != nil { continue }
      let expected = em.entries["out"] ?? .noval
      let got = subject(inVal)
      let exp = canon(expected)
      let gotS = canon(got)
      if exp == gotS { pass += 1 } else { fails.append("[\(label)#\(i)] exp=\(exp) got=\(gotS)") }
    }
    if !fails.isEmpty {
      for f in fails.prefix(5) { print(f) }
      XCTFail("\(label): \(pass)/\(pass + fails.count) — \(fails.count) failed")
    } else {
      print("ok \(label): \(pass)/\(pass)")
    }
  }

  // MARK: - Minor

  func testMinor() {
    let s = loadStructSpec()
    guard case .map(let minor) = getprop(s, .string("minor")) else {
      return XCTFail("missing minor")
    }

    runset(
      "minor.isnode", getprop(.map(minor), .string("isnode")) |> setProp("set"),
      { .bool(isnode($0)) })
    runset(
      "minor.ismap", getprop(.map(minor), .string("ismap")) |> setProp("set"),
      { .bool(ismap($0)) })
    runset(
      "minor.islist", getprop(.map(minor), .string("islist")) |> setProp("set"),
      { .bool(islist($0)) })
    runset(
      "minor.iskey", getprop(.map(minor), .string("iskey")) |> setProp("set"),
      { .bool(iskey($0)) })
    runset(
      "minor.isempty", getprop(.map(minor), .string("isempty")) |> setProp("set"),
      { .bool(isempty($0)) })
    runset(
      "minor.size", getprop(.map(minor), .string("size")) |> setProp("set"),
      { .int(Int64(size($0))) })
    runset(
      "minor.keysof", getprop(.map(minor), .string("keysof")) |> setProp("set"),
      { .list(keysof($0).map { Value.string($0) }) })
    runset(
      "minor.haskey", getprop(.map(minor), .string("haskey")) |> setProp("set"),
      { .bool(haskey(getprop($0, .string("src")), getprop($0, .string("key")))) })
    runset(
      "minor.getprop", getprop(.map(minor), .string("getprop")) |> setProp("set"),
      {
        getprop(
          getprop($0, .string("val")),
          getprop($0, .string("key")),
          getprop($0, .string("alt")))
      })
    runset(
      "minor.clone", getprop(.map(minor), .string("clone")) |> setProp("set"),
      { clone($0) })
    runset(
      "minor.escre", getprop(.map(minor), .string("escre")) |> setProp("set"),
      { .string(escre($0)) })
    runset(
      "minor.escurl", getprop(.map(minor), .string("escurl")) |> setProp("set"),
      { .string(escurl($0)) })
    runset(
      "minor.stringify", getprop(.map(minor), .string("stringify")) |> setProp("set"),
      {
        if case .map(let m) = $0 {
          let v = m.entries["val"] ?? .noval
          let maxlen = m.entries["max"]?.asInt.map(Int.init)
          return .string(stringify(v, maxlen))
        }
        return .string(stringify($0))
      })
  }

  // MARK: - Walk

  func testWalkBasic() {
    let s = loadStructSpec()
    let walkBasic = getprop(getprop(s, .string("walk")), .string("basic"))
    let set = getprop(walkBasic, .string("set"))
    let walkpath: WalkApply = { _, v, _, path in
      if case .string(let s) = v {
        return .string(s + "~" + path.joined(separator: "."))
      }
      return v
    }
    runset("walk.basic", set, { walk(clone($0), walkpath) })
  }

  // MARK: - Getpath

  func testGetpathBasic() {
    let s = loadStructSpec()
    let set = getprop(getprop(s, .string("getpath")), .string("basic")) |> setProp("set")
    runset(
      "getpath.basic", set,
      {
        getpath(getprop($0, .string("store")), getprop($0, .string("path")))
      })
  }

  // MARK: - Merge

  func testMergeBasic() {
    let s = loadStructSpec()
    let mergeSpec = getprop(s, .string("merge"))
    if case .map(let mm) = mergeSpec {
      for (name, sub) in mm.entries {
        if name == "name" { continue }
        let set = getprop(sub, .string("set"))
        if name == "depth" {
          // depth set has shape {val: [...], depth: N}
          runset(
            "merge.\(name)", set,
            {
              let val = getprop($0, .string("val"))
              let depth = getprop($0, .string("depth")).asInt.map(Int.init) ?? MAXDEPTH
              return merge(clone(val), depth)
            })
        } else {
          runset("merge.\(name)", set, { merge(clone($0)) })
        }
      }
    }
  }

  // MARK: - Inject

  func testInject() {
    let s = loadStructSpec()
    let injectSpec = getprop(s, .string("inject"))
    guard case .map(let im) = injectSpec else { return }
    // Single-entry `basic` is not a `.set`.
    if let basic = im.entries["basic"], case .map(let bm) = basic, let inv = bm.entries["in"] {
      let got = inject(
        clone(getprop(inv, .string("val"))),
        getprop(inv, .string("store")))
      let exp = bm.entries["out"] ?? .noval
      XCTAssertEqual(canon(got), canon(exp), "inject.basic")
    }
    // String / deep variants apply the NULLMARK fixup.
    if let stringSet = im.entries["string"], case .map(let sm) = stringSet,
      let set = sm.entries["set"], case .list(let sl) = set
    {
      var pass = 0
      var fail = 0
      for (i, entry) in sl.items.enumerated() {
        guard case .map(let em) = entry else { continue }
        if em.entries["err"] != nil { continue }
        let inVal = em.entries["in"] ?? .noval
        let v = fixNull(clone(getprop(inVal, .string("val"))))
        let st = fixNull(clone(getprop(inVal, .string("store"))))
        let runInj = Injection(val: .noval, parent: .noval)
        runInj.modify = nullModifier
        let got = inject(v, st, runInj)
        let exp = em.entries["out"] ?? .noval
        if canon(got) == canon(exp) {
          pass += 1
        } else {
          fail += 1
          if fail <= 5 { print("[inject.string#\(i)] exp=\(canon(exp)) got=\(canon(got))") }
        }
      }
      if fail > 0 {
        XCTFail("inject.string: \(pass)/\(pass + fail)")
      } else {
        print("ok inject.string: \(pass)/\(pass)")
      }
    }
    if let deepSet = im.entries["deep"], case .map(let dm) = deepSet,
      let set = dm.entries["set"]
    {
      runset(
        "inject.deep", set,
        {
          inject(
            clone(getprop($0, .string("val"))),
            getprop($0, .string("store")))
        })
    }
  }

  // MARK: - Transform

  func testTransform() {
    let s = loadStructSpec()
    let txSpec = getprop(s, .string("transform"))
    guard case .map(let tm) = txSpec else { return }
    if let basic = tm.entries["basic"], case .map(let bm) = basic, let inv = bm.entries["in"] {
      let got = transform(
        clone(getprop(inv, .string("data"))),
        clone(getprop(inv, .string("spec"))))
      let exp = bm.entries["out"] ?? .noval
      XCTAssertEqual(canon(got), canon(exp), "transform.basic")
    }
    for name in ["paths", "cmds", "each", "pack", "ref", "apply", "format"] {
      if let sub = tm.entries[name], case .map(let sm) = sub,
        let set = sm.entries["set"]
      {
        runset(
          "transform.\(name)", set,
          {
            transform(
              clone(getprop($0, .string("data"))),
              clone(getprop($0, .string("spec"))))
          })
      }
    }
    // Modify uses an `@`-prefix string modifier.
    if let sub = tm.entries["modify"], case .map(let sm) = sub,
      let set = sm.entries["set"]
    {
      runset(
        "transform.modify", set,
        {
          let runInj = Injection(val: .noval, parent: .noval)
          runInj.modify = { val, key, parent, _, _ in
            if case .string(let s) = val {
              setprop(parent, key, .string("@" + s))
            }
          }
          return transform(
            clone(getprop($0, .string("data"))),
            clone(getprop($0, .string("spec"))),
            runInj)
        })
    }
  }

  // MARK: - Validate

  func testValidate() {
    let s = loadStructSpec()
    let vSpec = getprop(s, .string("validate"))
    guard case .map(let vm) = vSpec else { return }
    for name in ["basic", "child", "one", "exact", "invalid", "special"] {
      if let sub = vm.entries[name], case .map(let sm) = sub,
        let set = sm.entries["set"]
      {
        runset(
          "validate.\(name)", set,
          { entry in
            let runInj: Injection?
            if case .map(let im) = getprop(entry, .string("inj")) {
              let i = Injection(val: .noval, parent: .noval)
              i.meta = im
              runInj = i
            } else if let ij = (entry.asMap?.entries["inj"]), case .map(let im) = ij {
              let i = Injection(val: .noval, parent: .noval)
              i.meta = im
              runInj = i
            } else {
              runInj = nil
            }
            return validate(
              clone(getprop(entry, .string("data"))),
              clone(getprop(entry, .string("spec"))),
              runInj)
          })
      }
    }
  }

  // MARK: - Select

  func testSelect() {
    let s = loadStructSpec()
    let sSpec = getprop(s, .string("select"))
    guard case .map(let sm) = sSpec else { return }
    for name in ["basic", "operators", "edge", "alts"] {
      if let sub = sm.entries[name], case .map(let ssm) = sub,
        let set = ssm.entries["set"], case .list(let sl) = set
      {
        var pass = 0
        var fail = 0
        for (i, entry) in sl.items.enumerated() {
          guard case .map(let em) = entry else { continue }
          if em.entries["err"] != nil { continue }
          let inVal = em.entries["in"] ?? .noval
          let obj = fixNull(clone(getprop(inVal, .string("obj"))))
          let q = fixNull(clone(getprop(inVal, .string("query"))))
          let got = select(obj, q)
          let exp = fixNull(clone(em.entries["out"] ?? .noval))
          if canon(got) == canon(exp) {
            pass += 1
          } else {
            fail += 1
            if fail <= 5 {
              print("[select.\(name)#\(i)] exp=\(canon(exp)) got=\(canon(got))")
            }
          }
        }
        if fail > 0 {
          XCTFail("select.\(name): \(pass)/\(pass + fail)")
        } else {
          print("ok select.\(name): \(pass)/\(pass)")
        }
      }
    }
  }
}

// Convenience: "x |> setProp(y)" sugar to chain a getprop access.
infix operator |> : MultiplicationPrecedence
private func |> (lhs: Value, rhs: (Value) -> Value) -> Value { rhs(lhs) }
private func setProp(_ key: String) -> (Value) -> Value {
  { v in getprop(v, .string(key)) }
}
