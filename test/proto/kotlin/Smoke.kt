// Smoke harness for the Kotlin test provider port. Prints summary stats that
// must match the canonical TS output documented in PROVIDER.md.
//
// Run (from the repo root, once a Kotlin toolchain is available), e.g.:
//   kotlinc test/proto/kotlin/Provider.kt test/proto/kotlin/Smoke.kt -include-runtime -d /tmp/proto.jar
//   java -jar /tmp/proto.jar
// The default corpus path resolves to build/test/test.json relative to the
// process working directory.

package voxgig.struct.proto

fun main() {
    val prov = TestProvider.load()

    val fns = prov.functions()
    println("functions: " + fns.joinToString(", "))

    var total = 0
    val expectKinds = LinkedHashMap<String, Int>()
    val inputKinds = LinkedHashMap<String, Int>()
    for (fn in fns) {
        for (entry in prov.entries(fn)) {
            total++
            val ek = entry.expect.kind.name.lowercase()
            val ik = entry.input.kind.name.lowercase()
            expectKinds[ek] = (expectKinds[ek] ?: 0) + 1
            inputKinds[ik] = (inputKinds[ik] ?: 0) + 1
        }
    }

    println("total entries: $total")
    println(
        "expect kinds: " +
            expectKinds.keys.sorted().joinToString(", ") { "$it=${expectKinds[it]}" },
    )
    println(
        "input kinds: " +
            inputKinds.keys.sorted().joinToString(", ") { "$it=${inputKinds[it]}" },
    )

    val e = prov.entries("getpath", "basic")[0]
    println(
        "getpath/basic[0]: " +
            "id=${e.id}, doc=${e.doc}, " +
            "input.kind=${e.input.kind.name.lowercase()}, " +
            "expect.kind=${e.expect.kind.name.lowercase()}, " +
            "expect.value=${stringify(e.expect.value)}",
    )

    // ─── helper sanity checks ──────────────────────────────────────────────
    println("equal(null, absent) lenient: " + equal(null, null))
    println(
        "equalStrict distinguishes null vs __NULL__-collapse: " +
            equalStrict(null, TestProvider.NULLMARK) + " / " + equalStrict(null, 1.0),
    )
    println(
        "errorMatches substring case-insensitive: " +
            errorMatches(ErrorCheck(any = false, text = "Foo", regex = false), "a foobar error"),
    )
    val sm = structMatch(
        linkedMapOf("a" to linkedMapOf("b" to 2.0)),
        linkedMapOf("a" to linkedMapOf("b" to 3.0)),
    )
    println("structMatch failure: ok=${sm.ok}, path=${sm.path}, expected=${sm.expected}, actual=${sm.actual}")
}
