// The shared corpus, run on the shared runner.
//
// The in-situ runner - a private `runset` with its own `fixNull`, `canon` and
// entry loop - is gone. Every group is driven through voxgig/omni, so this
// file only says WHICH subject answers each group and with which flags.
//
// What the old one did NOT do is why this matters. It skipped every entry with
// an `err:` field (59 of them), never looked at a `match:` block (15), never
// read `args` or `ctx`, and its `canon` deliberately folded absent into null,
// so the distinction the sentinels groups exist to test could not fail. Whole
// groups were absent too: merge.integrity, validate.*, select.nullkey,
// walk.copy, walk.depth, walk.log, getpath.relative/special/handler,
// inject.string's flags, transform.format's flags.
//
// omni is consumed as a local checkout: Package.swift finds it via $OMNI_HOME
// or beside this repository and makes it a dependency of the TEST target only.
// `swift build` compiles the library alone (register 4.13).
//
// Flags mirror canonical: typescript/test/utility/StructUtility.test.ts.

import Omni
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

// MARK: - The bridge

// omni's model -> this port's. Both draw the same absent/null/value
// distinction (`.noval` is canonical `undefined`), so nothing is guessed.
// Nodes are built as VMap / VList, which are classes, so what a subject
// receives is a real mutable node it may rewrite in place.
//
// An integral number becomes `.int`. omni parses every JSON number as a
// Double - right for a model whose only number is "JSON number" - but this
// port's `typify` answers T_integer or T_decimal from the case, so 36 would
// classify as a decimal. The corpus has no integral-with-point literal for the
// two to disagree on. struct/go's shim and struct/clojure's bridge needed the
// same normalisation (voxgig/omni#13).
func tostruct(_ value: Omni.Json) -> Value {
  switch value {
  case .absent: return .noval
  case .null: return .null
  case .bool(let flag): return .bool(flag)
  case .num(let entry):
    if entry == entry.rounded() && abs(entry) < 9_007_199_254_740_992 {
      return .int(Int64(entry))
    }
    return .double(entry)
  case .str(let text): return .string(text)
  case .list(let entries): return .list(entries.map(tostruct))
  case .map(let entries): return .map(entries.map { ($0.0, tostruct($0.1)) })
  case .provider: return .string("[Provider]")
  }
}

// This port's model -> omni's. A function or a sentinel has no JSON form and
// omni only ever stringifies one, so it becomes its own rendering rather than
// silently collapsing to null.
func toomni(_ value: Value) -> Omni.Json {
  switch value {
  case .noval: return .absent
  case .null: return .null
  case .bool(let flag): return .bool(flag)
  case .int(let entry): return .num(Double(entry))
  case .double(let entry): return .num(entry)
  case .string(let text): return .str(text)
  case .list(let node): return .list(node.items.map(toomni))
  case .map(let node): return .map(node.entries.map { ($0.0, toomni($0.1)) })
  case .function: return .str("[Function]")
  case .sentinel(let tag): return .str("`$\(tag)`")
  }
}

// Order-independent deep equality, through omni's own rule so the hand-written
// comparisons below match the way every group is checked.
func eqv(_ a: Value, _ b: Value) -> Bool {
  return Omni.deepequal(toomni(a), toomni(b))
}

// MARK: - The corpus

final class CorpusTests: XCTestCase {

  private var pack: Omni.RunPack! = nil

  // Each group is one assertion: omni stops at its first failing entry and
  // reports the index, the entry and both values.
  //
  // The subject is handed omni's arguments converted into this port's mutable
  // nodes, and hands the converted arguments BACK - `match.args` asserts an
  // in-place rewrite in eight of `minor/setpath`'s nine entries and all six of
  // `merge/integrity`, and omni's `Json` is a value type. rust, cpp, ocaml,
  // elixir, haskell, clojure and scala needed the same entry point for the
  // same reason.
  private func runSet(
    _ group: String, _ node: Value, _ flagNull: Bool = true,
    _ subject: @escaping ([Value]) throws -> Value
  ) {
    let call: Omni.SubjectArgs = { cells in
      let args = cells.map(tostruct)
      // A subject may throw - `transform` and `validate` do, for the 59
      // corpus entries that assert an error - and omni's handleerror is what
      // matches it against the entry's `err:`.
      let res = try subject(args)
      return (args.map(toomni), toomni(res))
    }
    var flags = Omni.Flags()
    flags.null = flagNull
    flags.name = group
    do {
      try pack.runsetflagsargs(toomni(node), flags, call)
    } catch let err as Omni.OmniError {
      XCTFail("\(group) - \(err.message)")
    } catch {
      XCTFail("\(group) - \(error)")
    }
  }

  // `merge.basic`, `inject.basic` and `transform.basic` are single entries,
  // not sets, so the runner cannot drive them. Compared here, through omni's
  // own deepequal so the rule is the one every group uses.
  private func runSingle(
    _ group: String, _ node: Value, _ actualFn: (Value) throws -> Value
  ) {
    do {
      let expected = getprop(node, .string("out"))
      let actual = try actualFn(getprop(node, .string("in")))
      if !eqv(expected, actual) {
        XCTFail("\(group) - Expected: \(stringify(expected)), got: \(stringify(actual))")
      }
    } catch {
      XCTFail("\(group) - \(error)")
    }
  }

  private func arg1(_ f: @escaping (Value) throws -> Value) -> ([Value]) throws -> Value {
    return { args in try f(args.first ?? .noval) }
  }

  // A RAW map read, not `getprop`: the entry's `in` fields carry the arguments
  // verbatim, and the Group-A rule `getprop` applies would turn an authored
  // null into absent. `minor/getprop#51` (`alt: null`) and
  // `minor/stringify#6` (`val: null`) are the entries that notice.
  private func vget(_ vin: Value, _ key: String) -> Value {
    return lookup(vin, .string(key))
  }

  private func vhas(_ vin: Value, _ key: String) -> Bool {
    if case .map(let node) = vin { return nil != node.entries[key] }
    return false
  }

  private func vint(_ vin: Value, _ key: String) -> Int? {
    return getprop(vin, .string(key)).asInt.map(Int.init)
  }

  private func vstr(_ vin: Value, _ key: String) -> String {
    if case .string(let text) = getprop(vin, .string(key)) { return text }
    return ""
  }

  func testCorpus() throws {
    let runner = try Omni.makeRunner(CORPUS_PATH.path, Omni.Provider())
    pack = try runner.runner("struct")
    runAll(tostruct(pack.spec))
    runClient()
  }

  // MARK: - Groups

  private func runAll(_ spec: Value) {
    let minor = getprop(spec, .string("minor"))
    let walks = getprop(spec, .string("walk"))
    let merges = getprop(spec, .string("merge"))
    let getpaths = getprop(spec, .string("getpath"))
    let injects = getprop(spec, .string("inject"))
    let transforms = getprop(spec, .string("transform"))
    let validates = getprop(spec, .string("validate"))
    let selects = getprop(spec, .string("select"))
    let sentinels = getprop(spec, .string("sentinels"))
    let regexs = getprop(spec, .string("regex"))
    func mg(_ name: String) -> Value { getprop(minor, .string(name)) }
    func sub(_ node: Value, _ name: String) -> Value { getprop(node, .string(name)) }

    // minor
    runSet("minor.isnode", mg("isnode"), true, arg1 { .bool(isnode($0)) })
    runSet("minor.ismap", mg("ismap"), true, arg1 { .bool(ismap($0)) })
    runSet("minor.islist", mg("islist"), true, arg1 { .bool(islist($0)) })
    runSet("minor.iskey", mg("iskey"), false, arg1 { .bool(iskey($0)) })
    runSet("minor.strkey", mg("strkey"), false, arg1 { .string(strkey($0)) })
    runSet("minor.isempty", mg("isempty"), false, arg1 { .bool(isempty($0)) })
    runSet("minor.isfunc", mg("isfunc"), true, arg1 { .bool(isfunc($0)) })
    runSet("minor.clone", mg("clone"), false, arg1 { clone($0) })
    runSet("minor.escre", mg("escre"), true, arg1 { .string(escre($0)) })
    runSet("minor.escurl", mg("escurl"), true, arg1 { .string(escurl($0)) })
    runSet(
      "minor.stringify", mg("stringify"), false,
      arg1 { vin in
        if self.vhas(vin, "val") {
          return .string(stringify(self.vget(vin, "val"), self.vint(vin, "max")))
        }
        return .string(stringify(.noval))
      })
    runSet(
      "minor.jsonify", mg("jsonify"), false,
      arg1 { vin in
        var indent = 2
        var offset = 0
        let flags = self.vget(vin, "flags")
        if case .map = flags {
          if let n = self.vint(flags, "indent") { indent = n }
          if let n = self.vint(flags, "offset") { offset = n }
        }
        return .string(jsonify(lookup(vin, .string("val")), indent: indent, offset: offset))
      })
    runSet(
      "minor.getelem", mg("getelem"), false,
      arg1 { vin in
        getelem(self.vget(vin, "val"), self.vget(vin, "key"), self.vget(vin, "alt"))
      })
    runSet(
      "minor.delprop", mg("delprop"), true,
      arg1 { vin in delprop(self.vget(vin, "parent"), self.vget(vin, "key")) })
    runSet("minor.size", mg("size"), false, arg1 { .int(Int64(size($0))) })
    runSet(
      "minor.slice", mg("slice"), false,
      arg1 { vin in
        slice(self.vget(vin, "val"), self.vint(vin, "start"), self.vint(vin, "end"))
      })
    runSet(
      "minor.pad", mg("pad"), false,
      arg1 { vin in
        var padchar: Character = " "
        if case .string(let text) = self.vget(vin, "char"), let first = text.first {
          padchar = first
        }
        return pad(lookup(vin, .string("val")), self.vint(vin, "pad"), padchar)
      })
    runSet(
      "minor.pathify", mg("pathify"), false,
      arg1 { vin in
        .string(pathify(lookup(vin, .string("path")), self.vint(vin, "from")))
      })
    runSet("minor.items", mg("items"), true, arg1 { .list(items($0).map { Value.list($0) }) })
    // Canonical omits `alt` only when the KEY is missing (`undefined ===
    // vin.alt`), so a present `alt: null` still goes through; getelem's rule
    // is the looser `null == vin.alt`. `minor/getprop#51` separates them.
    runSet(
      "minor.getprop", mg("getprop"), false,
      arg1 { vin in
        if self.vhas(vin, "alt") {
          return getprop(self.vget(vin, "val"), self.vget(vin, "key"), self.vget(vin, "alt"))
        }
        return getprop(self.vget(vin, "val"), self.vget(vin, "key"))
      })
    runSet(
      "minor.setprop", mg("setprop"), true,
      arg1 { vin in
        setprop(self.vget(vin, "parent"), self.vget(vin, "key"), lookup(vin, .string("val")))
      })
    runSet(
      "minor.haskey", mg("haskey"), false,
      arg1 { vin in .bool(haskey(self.vget(vin, "src"), self.vget(vin, "key"))) })
    runSet(
      "minor.keysof", mg("keysof"), true,
      arg1 { .list(keysof($0).map { Value.string($0) }) })
    runSet(
      "minor.join", mg("join"), false,
      arg1 { vin in
        var sep = ","
        if case .string(let text) = self.vget(vin, "sep") { sep = text }
        var url = false
        if case .bool(let flag) = self.vget(vin, "url") { url = flag }
        return .string(join(self.vget(vin, "val"), sep, url))
      })
    runSet("minor.typify", mg("typify"), false, arg1 { .int(Int64(typify($0))) })
    runSet(
      "minor.setpath", mg("setpath"), false,
      arg1 { vin in
        setpath(self.vget(vin, "store"), self.vget(vin, "path"), lookup(vin, .string("val")))
      })
    let filterChecks: [String: (Value, Value) -> Bool] = [
      "gt3": { _, v in (v.asDouble ?? 0) > 3 },
      "lt3": { _, v in (v.asDouble ?? 0) < 3 },
    ]
    runSet(
      "minor.filter", mg("filter"), true,
      arg1 { vin in
        let check = strkey(self.vget(vin, "check"))
        return filter(self.vget(vin, "val"), filterChecks[check] ?? { _, _ in false })
      })
    runSet(
      "minor.typename", mg("typename"), true,
      arg1 { .string(typename(Int($0.asInt ?? 0))) })
    runSet(
      "minor.flatten", mg("flatten"), true,
      arg1 { vin in flatten(self.vget(vin, "val"), self.vint(vin, "depth")) })

    // walk
    runWalkLog("walk.log", sub(walks, "log"))
    runSet(
      "walk.basic", sub(walks, "basic"), true,
      arg1 { vin in
        walk(
          vin, nil,
          { _, val, _, path in
            if case .string(let text) = val {
              return .string(text + "~" + path.joined(separator: "."))
            }
            return val
          })
      })
    runSet("walk.copy", sub(walks, "copy"), true, arg1 { self.walkCopySubject($0) })
    runSet("walk.depth", sub(walks, "depth"), false, arg1 { self.walkDepthSubject($0) })

    // merge
    runSingle("merge.basic", sub(merges, "basic")) { merge(clone($0)) }
    runSet("merge.cases", sub(merges, "cases"), true, arg1 { merge($0) })
    runSet("merge.array", sub(merges, "array"), true, arg1 { merge($0) })
    runSet("merge.integrity", sub(merges, "integrity"), true, arg1 { merge($0) })
    runSet(
      "merge.depth", sub(merges, "depth"), true,
      arg1 { vin in merge(self.vget(vin, "val"), self.vint(vin, "depth") ?? MAXDEPTH) })

    // getpath
    runSet(
      "getpath.basic", sub(getpaths, "basic"), true,
      arg1 { vin in getpath(self.vget(vin, "store"), self.vget(vin, "path")) })
    runSet(
      "getpath.relative", sub(getpaths, "relative"), true,
      arg1 { vin in
        let inj = Injection(val: .noval, parent: .noval)
        inj.dparent = self.vget(vin, "dparent")
        if case .string(let text) = self.vget(vin, "dpath") {
          inj.dpath = text.components(separatedBy: ".")
        }
        return getpath(self.vget(vin, "store"), self.vget(vin, "path"), inj)
      })
    runSet(
      "getpath.special", sub(getpaths, "special"), true,
      arg1 { vin in
        let injm = self.vget(vin, "inj")
        guard case .map = injm else {
          return getpath(self.vget(vin, "store"), self.vget(vin, "path"))
        }
        let inj = Injection(val: .noval, parent: .noval)
        if case .string(let text) = self.vget(injm, "base") { inj.base = text }
        if case .map(let meta) = self.vget(injm, "meta") { inj.meta = meta }
        inj.dparent = self.vget(injm, "dparent")
        if case .list(let dpath) = self.vget(injm, "dpath") {
          inj.dpath = dpath.items.map { strkey($0) }
        }
        if case .string(let text) = self.vget(injm, "key") { inj.key = text }
        return getpath(self.vget(vin, "store"), self.vget(vin, "path"), inj)
      })
    runSet(
      "getpath.handler", sub(getpaths, "handler"), true,
      arg1 { vin in
        let store = Value.map([
          ("$TOP", self.vget(vin, "store")),
          ("$FOO", .function { _, _, _, _ in .string("foo") }),
        ])
        let inj = Injection(val: .noval, parent: .noval)
        inj.handler = { innerinj, val, ref, innerstore in
          if case .function(let call) = val { return call(innerinj, .noval, "", .noval) }
          return _injecthandler(innerinj, val, ref, innerstore)
        }
        return getpath(store, self.vget(vin, "path"), inj)
      })

    // inject
    runSingle("inject.basic", sub(injects, "basic")) { vin in
      inject(clone(getprop(vin, .string("val"))), clone(getprop(vin, .string("store"))))
    }
    runSet(
      "inject.string", sub(injects, "string"), true,
      arg1 { vin in
        let inj = Injection(val: .noval, parent: .noval)
        inj.modify = { val, key, parent, _, _ in
          if case .string(let text) = val {
            if text == NULLMARK {
              setprop(parent, key, .null)
            } else if text.contains(NULLMARK) {
              setprop(
                parent, key,
                .string(text.replacingOccurrences(of: NULLMARK, with: "null")))
            }
          }
        }
        inj.extra = self.vget(vin, "current")
        return inject(self.vget(vin, "val"), self.vget(vin, "store"), inj)
      })
    runSet(
      "inject.deep", sub(injects, "deep"), true,
      arg1 { vin in inject(self.vget(vin, "val"), self.vget(vin, "store")) })

    // transform
    runSingle("transform.basic", sub(transforms, "basic")) { vin in
      try transform(getprop(vin, .string("data")), getprop(vin, .string("spec")))
    }
    for name in ["paths", "cmds", "each", "pack", "ref"] {
      runSet(
        "transform.\(name)", sub(transforms, name), true,
        arg1 { vin in try transform(self.vget(vin, "data"), self.vget(vin, "spec")) })
    }
    runSet(
      "transform.modify", sub(transforms, "modify"), true,
      arg1 { vin in
        let inj = Injection(val: .noval, parent: .noval)
        inj.modify = { val, key, parent, _, _ in
          if case .string(let text) = val, !key.isNoval, !parent.isNoval {
            setprop(parent, key, .string("@" + text))
          }
        }
        inj.extra = self.vget(vin, "store")
        return try transform(self.vget(vin, "data"), self.vget(vin, "spec"), inj)
      })
    runSet(
      "transform.format", sub(transforms, "format"), false,
      arg1 { vin in try transform(self.vget(vin, "data"), self.vget(vin, "spec")) })
    runSet(
      "transform.apply", sub(transforms, "apply"), true,
      arg1 { vin in try transform(self.vget(vin, "data"), self.vget(vin, "spec")) })

    // validate
    runSet(
      "validate.basic", sub(validates, "basic"), false,
      arg1 { vin in try validate(self.vget(vin, "data"), self.vget(vin, "spec")) })
    for name in ["child", "one", "exact"] {
      runSet(
        "validate.\(name)", sub(validates, name), true,
        arg1 { vin in try validate(self.vget(vin, "data"), self.vget(vin, "spec")) })
    }
    runSet(
      "validate.invalid", sub(validates, "invalid"), false,
      arg1 { vin in try validate(self.vget(vin, "data"), self.vget(vin, "spec")) })
    runSet(
      "validate.special", sub(validates, "special"), true,
      arg1 { vin in
        let injm = self.vget(vin, "inj")
        guard case .map = injm else {
          return try validate(self.vget(vin, "data"), self.vget(vin, "spec"))
        }
        let inj = Injection(val: .noval, parent: .noval)
        if case .map(let meta) = self.vget(injm, "meta") { inj.meta = meta }
        return try validate(self.vget(vin, "data"), self.vget(vin, "spec"), inj)
      })

    // select
    for name in ["basic", "operators", "edge", "alts"] {
      runSet(
        "select.\(name)", sub(selects, name), true,
        arg1 { vin in select(self.vget(vin, "obj"), self.vget(vin, "query")) })
    }
    // `null: false` keeps a JSON null an ACTUAL null rather than the NULLMARK
    // string, so select sees a present-but-null field.
    runSet(
      "select.nullkey", sub(selects, "nullkey"), false,
      arg1 { vin in select(self.vget(vin, "obj"), self.vget(vin, "query")) })

    // regex (parity floor: Go stdlib regexp — see design/REGEX_API.md)
    runSet(
      "regex.test", sub(regexs, "test"), true,
      arg1 { vin in .bool(re_test(self.vget(vin, "pattern"), self.vstr(vin, "input"))) })
    runSet(
      "regex.find", sub(regexs, "find"), true,
      arg1 { vin in re_find(self.vget(vin, "pattern"), self.vstr(vin, "input")) })
    runSet(
      "regex.find_all", sub(regexs, "find_all"), true,
      arg1 { vin in re_find_all(self.vget(vin, "pattern"), self.vstr(vin, "input")) })
    runSet(
      "regex.replace", sub(regexs, "replace"), true,
      arg1 { vin in
        .string(
          re_replace(
            self.vget(vin, "pattern"), self.vstr(vin, "input"),
            self.vstr(vin, "replacement")))
      })
    runSet(
      "regex.escape", sub(regexs, "escape"), true,
      arg1 { vin in .string(re_escape(self.vget(vin, "val"))) })

    // sentinels
    runSet(
      "sentinels.getprop_unify", sub(sentinels, "getprop_unify"), false,
      arg1 { vin in
        getprop(self.vget(vin, "val"), self.vget(vin, "key"), self.vget(vin, "alt"))
      })
    runSet(
      "sentinels.getelem_absent", sub(sentinels, "getelem_absent"), false,
      arg1 { vin in
        getelem(self.vget(vin, "val"), self.vget(vin, "key"), self.vget(vin, "alt"))
      })
    runSet(
      "sentinels.haskey_unify", sub(sentinels, "haskey_unify"), false,
      arg1 { vin in .bool(haskey(self.vget(vin, "val"), self.vget(vin, "key"))) })
    runSet(
      "sentinels.isempty_unify", sub(sentinels, "isempty_unify"), false,
      arg1 { .bool(isempty($0)) })
    runSet(
      "sentinels.isnode_unify", sub(sentinels, "isnode_unify"), false,
      arg1 { .bool(isnode($0)) })
    runSet(
      "sentinels.stringify_null", sub(sentinels, "stringify_null"), false,
      arg1 { .string(stringify($0)) })
  }

  // MARK: - Groups the runner cannot drive

  private func runWalkLog(_ group: String, _ node: Value) {
    let testData = clone(node)
    let log = VList()
    _ = walk(
      getprop(testData, .string("in")), nil,
      { key, val, parent, path in
        log.items.append(
          .string(
            "k=" + (key.isNoval || key.isNull ? stringify(.noval) : stringify(key))
              + ", v=" + stringify(val)
              + ", p="
              + (parent.isNoval || parent.isNull ? stringify(.noval) : stringify(parent))
              + ", t=" + pathify(.list(path.map { Value.string($0) }))))
        return val
      })
    let expected = getprop(getprop(testData, .string("out")), .string("after"))
    if !eqv(expected, .list(log)) {
      XCTFail(
        "\(group) - Expected: \(stringify(expected)), got: \(stringify(.list(log)))")
    }
  }

  private func walkCopySubject(_ vin: Value) -> Value {
    var cur = VList([.noval])
    _ = walk(
      vin,
      { key, val, _, path in
        if key.isNoval || key.isNull {
          let inner: Value = ismap(val) ? .map(VMap()) : (islist(val) ? .list(VList()) : val)
          cur = VList([inner])
          return val
        }
        let index = path.count
        var next = val
        if isnode(val) {
          while cur.items.count <= index { cur.items.append(.noval) }
          next = ismap(val) ? .map(VMap()) : .list(VList())
          cur.items[index] = next
        }
        _ = setprop(cur.items[index - 1], key, next)
        return val
      }, nil)
    return cur.items[0]
  }

  private func walkDepthSubject(_ vin: Value) -> Value {
    var top: Value = .noval
    var curr: Value = .noval
    _ = walk(
      getprop(vin, .string("src")),
      { key, val, _, _ in
        if key.isNoval || key.isNull || isnode(val) {
          let child: Value = islist(val) ? .list(VList()) : .map(VMap())
          if key.isNoval || key.isNull {
            top = child
            curr = child
          } else {
            _ = setprop(curr, key, child)
            curr = child
          }
        } else {
          _ = setprop(curr, key, val)
        }
        return val
      }, nil,
      getprop(vin, .string("maxdepth")).asInt.map(Int.init) ?? MAXDEPTH)
    return top
  }

  // MARK: - The client path

  // `DEF.client`, client-scoped options, and `contextify`. This port had no
  // such test. It is the only thing that exercises subject resolution through
  // a PROVIDER rather than through a callback this file hands over - so
  // nothing here had ever checked that a corpus `client` key resolves, or that
  // a `DEF.client` entry's options reach the subject.
  //
  // The subject talks to omni DIRECTLY, in omni's own value type: the runner
  // resolves it by name off the provider, so there is no `in` to convert and
  // no result for the bridge to convert back.
  private func runClient() {
    func check(_ options: Omni.Json) -> Omni.Subject {
      return { args in
        let foo = options.get("foo")
        let foos = foo.isabsent ? "" : Omni.stringify(foo)
        let ctx = args.first ?? .absent
        let bar = ctx.get("meta").get("bar")
        let bars = bar.isnone ? "0" : Omni.stringify(bar)
        return .map([("zed", .str("ZED\(foos)_\(bars)"))])
      }
    }

    func clientProvider(_ options: Omni.Json) -> Omni.Provider {
      var provider = Omni.Provider()
      provider.subject = { name in "check" == name ? check(options) : nil }
      // A DEF.client entry becomes another provider, carrying its options.
      provider.client = { copts in clientProvider(copts) }
      // This port adds nothing to a context; the hook must exist so omni
      // installs `client` on it.
      provider.contextify = { value in value }
      return provider
    }

    do {
      let runner = try Omni.makeRunner(CORPUS_PATH.path, clientProvider(.map([])))
      let resolved = try runner.runner("check")
      var flags = Omni.Flags()
      flags.name = "check.basic"
      // No subject: the runner resolves it by name off the provider, which is
      // the whole point of the group.
      try resolved.runsetflags(resolved.set("basic"), flags, nil)
    } catch let err as Omni.OmniError {
      XCTFail("check.basic - \(err.message)")
    } catch {
      XCTFail("check.basic - \(error)")
    }
  }
}
