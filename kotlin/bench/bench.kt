// Performance bench for the Kotlin port. Emits one JSON line per
// build/bench/README.md; diagnostics go to stderr.
import voxgig.struct.Struct

var sink = 0L

fun envi(k: String, d: Int): Int = System.getenv(k)?.toIntOrNull() ?: d

fun build(w: Int, d: Int, leaf: Int): Any {
    if (d == 0) return leaf
    val m = LinkedHashMap<String, Any?>()
    for (i in 0 until w) m["k$i"] = build(w, d - 1, leaf)
    return m
}

fun nodecount(w: Int, d: Int): Long {
    var n = 0L; var p = 1L
    for (i in 0..d) { n += p; p *= w }
    return n
}

fun measure(warm: Int, runs: Int, f: () -> Unit): DoubleArray {
    for (i in 0 until warm) f()
    val t = DoubleArray(runs)
    for (r in 0 until runs) { val a = System.nanoTime(); f(); t[r] = (System.nanoTime() - a) / 1e6 }
    t.sort()
    var s = 0.0; for (x in t) s += x
    return doubleArrayOf(t[0], t[runs / 2], s / runs)
}

fun main() {
    val W = envi("BENCH_WIDTH", 5); val D = envi("BENCH_DEPTH", 6)
    val WARM = envi("BENCH_WARMUP", 3); val RUNS = envi("BENCH_RUNS", 21)
    val GP = envi("BENCH_GETPATH_ITERS", 2000)

    val tree = build(W, D, 0)
    val nodes = nodecount(W, D)
    val treeA = build(W, D, 1)
    val treeB = build(W, D, 2)
    val path = (0 until D).joinToString(".") { "k0" }
    val cb = Struct.WalkApply { _, v, _, p -> sink += p.size; v }

    val names = arrayOf("clone", "walk", "merge", "stringify", "getpath")
    val ucs = longArrayOf(nodes, nodes, nodes, nodes, GP.toLong())
    val fns = arrayOf<() -> Unit>(
        { if (Struct.clone(tree) != null) sink++ },
        { Struct.walk(tree, cb) },
        { if (Struct.merge(listOf(treeA, treeB)) != null) sink++ },
        { sink += Struct.stringify(tree).length },
        { var a = 0L; for (i in 0 until GP) if (Struct.getpath(tree, path) != null) a++; sink += a },
    )

    val sb = StringBuilder()
    for (i in names.indices) {
        val m = measure(WARM, RUNS, fns[i])
        if (i > 0) sb.append(',')
        sb.append("{\"op\":\"${names[i]}\",\"runs\":$RUNS,\"unit_count\":${ucs[i]},\"min_ms\":${m[0]},\"median_ms\":${m[1]},\"mean_ms\":${m[2]}}")
    }

    System.err.println("kotlin: sink=$sink")
    println("{\"lang\":\"kotlin\",\"runtime\":\"kotlin/jvm ${System.getProperty("java.version")}\",\"nodes\":$nodes,\"params\":{\"width\":$W,\"depth\":$D,\"warmup\":$WARM,\"runs\":$RUNS,\"getpath_iters\":$GP},\"ops\":[$sb]}")
}
