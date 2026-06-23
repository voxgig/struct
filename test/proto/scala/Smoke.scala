// Smoke test for the Scala test provider port. Prints summary stats that must
// match the canonical TS output documented in PROVIDER.md.
//
// Run from the repo root (Scala 3 toolchain required):
//   cd test/proto/scala && scalac Provider.scala Smoke.scala -d out \
//     && (cd /home/user/struct && scala -cp test/proto/scala/out Smoke)

import scala.collection.immutable.TreeMap

object Smoke {

  def main(args: Array[String]): Unit = {
    val path = if (args.length > 0) Some(args(0)) else Some("build/test/test.json")
    val prov = TestProvider.load(path)

    val fns = prov.functions()
    println("functions: " + fns.mkString(", "))

    var total = 0
    var expectKinds = TreeMap.empty[String, Int]
    var inputKinds = TreeMap.empty[String, Int]
    for (fn <- fns) {
      for (e <- prov.entries(fn)) {
        total += 1
        val ek = e.expect.kind.toString.toLowerCase
        val ik = e.input.kind.toString.toLowerCase
        expectKinds = expectKinds.updated(ek, expectKinds.getOrElse(ek, 0) + 1)
        inputKinds = inputKinds.updated(ik, inputKinds.getOrElse(ik, 0) + 1)
      }
    }

    println("total entries: " + total)
    println("expect kinds: " + joinCounts(expectKinds))
    println("input kinds: " + joinCounts(inputKinds))

    val e = prov.entries("getpath", Some("basic")).head
    println(
      "getpath/basic[0]: id=" + e.id.orNull +
        ", doc=" + e.doc +
        ", input.kind=" + e.input.kind.toString.toLowerCase +
        ", expect.kind=" + e.expect.kind.toString.toLowerCase +
        ", expect.value=" + e.expect.value.map(TestMatch.stringify).orNull
    )
  }

  private def joinCounts(counts: TreeMap[String, Int]): String =
    counts.map { case (k, v) => s"$k=$v" }.mkString(", ")
}
