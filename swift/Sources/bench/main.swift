// Performance bench for the Swift port. Emits one JSON line per
// build/bench/README.md; diagnostics go to stderr.
import Foundation
import VoxgigStruct

func envi(_ k: String, _ d: Int) -> Int { Int(ProcessInfo.processInfo.environment[k] ?? "") ?? d }

func build(_ w: Int, _ d: Int, _ leaf: Int64) -> Value {
    if d == 0 { return .int(leaf) }
    var pairs: [(String, Value)] = []
    for i in 0..<w { pairs.append(("k\(i)", build(w, d - 1, leaf))) }
    return Value.map(pairs)
}

func nodecount(_ w: Int, _ d: Int) -> Int {
    var n = 0, p = 1
    for _ in 0...d { n += p; p *= w }
    return n
}

var sink = 0

func measure(_ warm: Int, _ runs: Int, _ f: () -> Void) -> (Double, Double, Double) {
    for _ in 0..<warm { f() }
    var t = [Double]()
    for _ in 0..<runs {
        let a = DispatchTime.now().uptimeNanoseconds
        f()
        let b = DispatchTime.now().uptimeNanoseconds
        t.append(Double(b &- a) / 1e6)
    }
    t.sort()
    let sum = t.reduce(0, +)
    return (t[0], t[t.count / 2], sum / Double(t.count))
}

let W = envi("BENCH_WIDTH", 5), D = envi("BENCH_DEPTH", 6),
    WARM = envi("BENCH_WARMUP", 3), RUNS = envi("BENCH_RUNS", 21),
    GP = envi("BENCH_GETPATH_ITERS", 2000)

let tree = build(W, D, 0)
let nodes = nodecount(W, D)
let treeA = build(W, D, 1)
let treeB = build(W, D, 2)
let mlist = Value.list([treeA, treeB])
let path = Value.string(Array(repeating: "k0", count: D).joined(separator: "."))
let cb: WalkApply = { _, v, _, p in sink += p.count; return v }

let specs: [(String, Int, () -> Void)] = [
    ("clone", nodes, { _ = clone(tree); sink += 1 }),
    ("walk", nodes, { _ = walk(tree, cb) }),
    ("merge", nodes, { _ = merge(mlist); sink += 1 }),
    ("stringify", nodes, { sink += stringify(tree).count }),
    ("getpath", GP, {
        var a = 0
        for _ in 0..<GP { if case .int(0) = getpath(tree, path) { a += 1 } }
        sink += a
    }),
]

var parts = [String]()
for (op, uc, f) in specs {
    let (mn, md, mean) = measure(WARM, RUNS, f)
    parts.append("{\"op\":\"\(op)\",\"runs\":\(RUNS),\"unit_count\":\(uc),\"min_ms\":\(mn),\"median_ms\":\(md),\"mean_ms\":\(mean)}")
}

let runtime = ProcessInfo.processInfo.environment["BENCH_SWIFT"] ?? "swift"
FileHandle.standardError.write("swift: sink=\(sink)\n".data(using: .utf8)!)
let head = "{\"lang\":\"swift\",\"runtime\":\"\(runtime)\",\"nodes\":\(nodes),"
let params = "\"params\":{\"width\":\(W),\"depth\":\(D),\"warmup\":\(WARM)," +
    "\"runs\":\(RUNS),\"getpath_iters\":\(GP)},"
let opsJson = "\"ops\":[\(parts.joined(separator: ","))]}"
print(head + params + opsJson)
