// Performance bench for the Scala port. Emits one JSON line per
// build/bench/README.md; diagnostics go to stderr.
import voxgig.struct.{clone as sclone, *}

def envi(k: String, d: Int): Int =
  Option(System.getenv(k)).flatMap(_.toIntOption).getOrElse(d)

def build(w: Int, d: Int, leaf: Int): Value =
  if d == 0 then vint(leaf)
  else mkMap((0 until w).map(i => (s"k$i", build(w, d - 1, leaf))))

def nodecount(w: Int, d: Int): Int =
  var n = 0; var p = 1
  for _ <- 0 to d do { n += p; p *= w }
  n

var sink = 0L

def measure(warm: Int, runs: Int, f: () => Unit): (Double, Double, Double) =
  for _ <- 0 until warm do f()
  val t = Array.fill(runs)(0.0)
  for r <- 0 until runs do
    val a = System.nanoTime(); f(); t(r) = (System.nanoTime() - a) / 1e6
  scala.util.Sorting.quickSort(t)
  (t(0), t(runs / 2), t.sum / runs)

@main def bench(): Unit =
  val W = envi("BENCH_WIDTH", 5); val D = envi("BENCH_DEPTH", 6)
  val WARM = envi("BENCH_WARMUP", 3); val RUNS = envi("BENCH_RUNS", 21)
  val GP = envi("BENCH_GETPATH_ITERS", 2000)

  val tree = build(W, D, 0)
  val nodes = nodecount(W, D)
  val treeA = build(W, D, 1)
  val treeB = build(W, D, 2)
  val mlist = mkList(Seq(treeA, treeB))
  val path = VStr((0 until D).map(_ => "k0").mkString("."))
  val cb: WalkFn = (_, v, _, p) => { sink += size(p); v }

  val specs: Seq[(String, Int, () => Unit)] = Seq(
    ("clone", nodes, () => { sclone(tree); sink += 1 }),
    ("walk", nodes, () => { walk(tree, Some(cb)) }),
    ("merge", nodes, () => { merge(mlist); sink += 1 }),
    ("stringify", nodes, () => { sink += stringify(tree).length }),
    ("getpath", GP, () => { for _ <- 0 until GP do getpath(tree, path); sink += GP })
  )

  val parts = specs.map { (op, uc, f) =>
    val (mn, md, mean) = measure(WARM, RUNS, f)
    s"""{"op":"$op","runs":$RUNS,"unit_count":$uc,"min_ms":$mn,"median_ms":$md,"mean_ms":$mean}"""
  }

  System.err.println(s"scala: sink=$sink")
  val rt = Option(System.getenv("BENCH_SCALA")).getOrElse("scala 3")
  println(
    s"""{"lang":"scala","runtime":"$rt","nodes":$nodes,"params":{"width":$W,"depth":$D,"warmup":$WARM,"runs":$RUNS,"getpath_iters":$GP},"ops":[${parts.mkString(",")}]}"""
  )
