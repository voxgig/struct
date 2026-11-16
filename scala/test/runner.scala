// The shared corpus, run on the shared runner.
//
// The in-situ runner - a JSON reader, `fixJson`, `eqv`, `doMatch`, `matchval`,
// `resolveArgs`, `checkResult` and `handleError`, all of it this port's own
// copy of omni's algorithm - is gone. Every group is driven through
// voxgig/omni, so this file only says WHICH subject answers each group and
// with which flags.
//
// omni is consumed as a local checkout: the Makefile finds it via $OMNI_HOME
// or beside this repository and hands its sources to scala-cli alongside the
// tests. Only the tests use it - `make build` compiles src/ alone, and nothing
// published names omni (register 4.13).
//
// Flags mirror canonical: typescript/test/utility/StructUtility.test.ts.

import voxgig.struct.{clone as sclone, *}
import voxgig.omni.{Json, Flags, Provider, OmniError, Runner as O, Util as OU}
import scala.collection.mutable.{ArrayBuffer, LinkedHashMap}
import scala.collection.immutable.ListMap

object Runner {

  val NULLMARK = "__NULL__"

  // ---------------- the bridge ----------------

  // omni's model -> this port's. Both draw the same absent/null/value
  // distinction (`Noval` is canonical `undefined`), so nothing is guessed.
  // Nodes are built as ArrayBuffer / LinkedHashMap, so what a subject receives
  // is a real mutable node it may rewrite in place.
  def tostruct(value: Json): Value = value match {
    case Json.Absent => Noval
    case Json.Null => VNull
    case Json.Bool(b) => VBool(b)
    case Json.Num(n) => VNum(n)
    case Json.Str(t) => VStr(t)
    case Json.JList(items) => VList(ArrayBuffer.from(items.map(tostruct)))
    case Json.JMap(entries) =>
      val m = LinkedHashMap.empty[String, Value]
      entries.foreach { case (k, v) => m.put(k, tostruct(v)) }
      VMap(m)
  }

  // This port's model -> omni's. A function or a sentinel has no JSON form and
  // omni only ever stringifies one, so it becomes its own rendering rather
  // than silently collapsing to null.
  def toomni(value: Value): Json = value match {
    case Noval => Json.Absent
    case VNull => Json.Null
    case VBool(b) => Json.Bool(b)
    case VNum(n) => Json.Num(n)
    case VStr(t) => Json.Str(t)
    case VList(buf) => Json.JList(buf.toList.map(toomni))
    case VMap(m) => Json.JMap(ListMap.from(m.toSeq.map { case (k, v) => (k, toomni(v)) }))
    case VFunc(_) => Json.Str("[Function]")
    case other => Json.Str(stringify(other))
  }

  // Order-independent deep equality, through omni's own rule so the
  // hand-written comparisons below match the way every group is checked.
  def eqv(a: Value, b: Value): Boolean = OU.deepequal(toomni(a), toomni(b))

  // ---------------- result tracking ----------------

  var npass = 0
  var nfail = 0
  val failures = ArrayBuffer.empty[String]
  def record(group: String, ok: Boolean, msg: String): Unit =
    if (ok) npass += 1 else { nfail += 1; failures.append(s"FAIL $group - $msg") }

  def errmsg(err: Throwable): String = err match {
    case o: OmniError => o.text
    case StructError(m) => m
    case e => String.valueOf(e.getMessage)
  }

  // ---------------- running a group ----------------

  var pack: voxgig.omni.RunPack = null

  // Each group is one assertion: omni stops at its first failing entry and
  // reports the index, the entry and both values.
  //
  // The subject is handed omni's arguments converted into this port's mutable
  // nodes, and hands the converted arguments BACK - `match.args` asserts an
  // in-place rewrite in eight of `minor/setpath`'s nine entries and all six of
  // `merge/integrity`, and omni's Json is an immutable value model. rust, cpp,
  // ocaml, elixir, haskell and clojure needed the same entry point for the
  // same reason.
  def runSet(group: String, node: Value, subject: Seq[Value] => Value, flagNull: Boolean = true): Unit = {
    val call: List[Json] => (List[Json], Json) = cells => {
      val args = cells.map(tostruct)
      val res = subject(args)
      (args.map(toomni), toomni(res))
    }
    try {
      pack.runsetflagsargs(toomni(node), Flags(nulls = flagNull, name = Some(group)), call)
      record(group, true, "")
    } catch { case e: Throwable => record(group, false, errmsg(e)) }
  }

  // `merge.basic`, `inject.basic` and `transform.basic` are single entries,
  // not sets, so the runner cannot drive them. Compared here, through omni's
  // own deepequal so the rule is the one every group uses.
  def runSingle(group: String, node: Value, actualFn: Value => Value): Unit = {
    try {
      val expected = eget(node, "out")
      val actual = actualFn(eget(node, "in"))
      if (eqv(expected, actual)) record(group, true, "")
      else record(group, false, s"Expected: ${stringify(expected)}, got: ${stringify(actual)}")
    } catch { case e: Throwable => record(group, false, errmsg(e)) }
  }

  def omapV(kvs: (String, Value)*): Value = {
    val m = LinkedHashMap.empty[String, Value]
    kvs.foreach { case (k, v) => m.put(k, v) }
    VMap(m)
  }
  def eget(e: Value, k: String): Value = e match { case VMap(m) => m.get(k).getOrElse(Noval); case _ => Noval }
  def arg1(f: Value => Value): Seq[Value] => Value = args => f(args.headOption.getOrElse(Noval))
  def vget(vin: Value, k: String): Value = vin match { case VMap(m) => m.get(k).getOrElse(Noval); case _ => Noval }
  def vhas(vin: Value, k: String): Boolean = vin match { case VMap(m) => m.contains(k); case _ => false }

  // ---------------- walk subjects ----------------

  val nullModifier: Modify = (v, key, parent, _inj) => {
    if (v == VStr(NULLMARK)) setprop(parent, key, VNull)
    else v match { case VStr(s) => setprop(parent, key, VStr(s.replace(NULLMARK, "null"))); case _ => () }
  }

  def runWalkLog(group: String, node: Value): Unit = {
    try {
      val testData = sclone(node)
      val log = emptyList()
      val walklog: WalkFn = (key, v, parent, path) => {
        setprop(log, VNum(size(log).toDouble), VStr(
          "k=" + (if (isNullish(key)) stringify(Noval) else stringify(key)) +
          ", v=" + stringify(v) +
          ", p=" + (if (isNullish(parent)) stringify(Noval) else stringify(parent)) +
          ", t=" + pathify(path)))
        v
      }
      walk(eget(testData, "in"), after = Some(walklog))
      val expected = getprop(eget(testData, "out"), VStr("after"))
      if (eqv(expected, log)) record(group, true, "")
      else record(group, false, s"Expected: ${stringify(expected)}, got: ${stringify(log)}")
    } catch { case e: Throwable => record(group, false, errmsg(e)) }
  }

  def walkCopySubject(vin: Value): Value = {
    var cur: Value = mkList(Seq(Noval))
    val walkcopy: WalkFn = (key, v, _parent, path) => {
      if (isNullish(key)) {
        cur = mkList(Seq(if (ismap(v)) emptyMap() else if (islist(v)) emptyList() else v))
        v
      } else {
        val i = size(path)
        val nv = if (isnode(v)) {
          cur match { case VList(b) => while (b.length <= i) b.append(Noval); case _ => }
          val n = if (ismap(v)) emptyMap() else emptyList()
          cur match { case VList(b) => b(i) = n; case _ => }
          n
        } else v
        setprop(getelem(cur, VNum((i - 1).toDouble)), key, nv)
        v
      }
    }
    walk(vin, before = Some(walkcopy))
    getelem(cur, VNum(0.0))
  }

  def walkDepthSubject(vin: Value): Value = {
    var top: Value = Noval
    var curr: Value = Noval
    val copy: WalkFn = (key, v, _parent, _path) => {
      if (isNullish(key) || isnode(v)) {
        val child = if (islist(v)) emptyList() else emptyMap()
        if (isNullish(key)) { top = child; curr = child }
        else { setprop(curr, key, child); curr = child }
      } else setprop(curr, key, v)
      v
    }
    walk(vget(vin, "src"), before = Some(copy), maxdepth = vget(vin, "maxdepth"))
    top
  }

  // ---------------- condense: what the corpus cannot express ----------------

  // Identity, sharing, laziness and the immutability contract, one recorded
  // check each, named as canonical's port-local tests are.
  def runLocal(group: String)(ok: => Boolean): Unit =
    try record(group, ok, "check failed") catch { case e: Throwable => record(group, false, errmsg(e)) }

  def raisesImmutable(call: => Any): Boolean =
    try { call; false } catch { case StructError(m) => m.contains("immutable") }

  def runCondenseLocal(): Unit = {
    runLocal("condense-deterministic") {
      val src = jm(VStr("b"), jm(VStr("m"), VStr("GET")), VStr("a"), jm(VStr("m"), VStr("GET")),
        VStr("l"), jt(VNum(1), VStr("x"), VBool(true)))
      // Insertion order must not change the bytes: keys are stored by symbol id.
      val reordered = jm(VStr("l"), jt(VNum(1), VStr("x"), VBool(true)),
        VStr("a"), jm(VStr("m"), VStr("GET")), VStr("b"), jm(VStr("m"), VStr("GET")))
      jsonify(condense(src)) == jsonify(condense(src)) && jsonify(condense(src)) == jsonify(condense(reordered))
    }

    runLocal("condense-shares-identical-subtrees") {
      def nodes(c: Value): Int = size(getprop(c, VStr("node")))
      val one = condense(jm(VStr("x"), jm(VStr("m"), VStr("GET"), VStr("p"), VStr("/1"))))
      val two = condense(jm(VStr("x"), jm(VStr("m"), VStr("GET"), VStr("p"), VStr("/1")),
        VStr("y"), jm(VStr("m"), VStr("GET"), VStr("p"), VStr("/1"))))
      val three = condense(jm(VStr("x"), jm(VStr("m"), VStr("GET")), VStr("y"), jm(VStr("m"), VStr("PUT")),
        VStr("z"), jm(VStr("m"), VStr("POST"))))
      // A second reference to an identical subtree adds no node.
      nodes(two) == nodes(one) && nodes(three) > nodes(two)
    }

    runLocal("condense-round-trips-by-value") {
      val src = jm(VStr("a"), jm(VStr("b"), jt(VNum(1), VStr("x"), VBool(true), VNull, jm())), VStr("c"), VStr("z"))
      expand(condense(src)) == src
    }

    runLocal("condense-getpath-is-transparent") {
      val src = jm(VStr("entity"), jm(VStr("p"), jm(VStr("op"), jm(VStr("list"), jm(VStr("method"), VStr("GET"))))))
      val c = condense(src)
      val path = jt(VStr("entity"), VStr("p"), VStr("op"), VStr("list"))
      getpath(c, path) == getpath(src, path) &&
        getpath(c, jt(VStr("entity"), VStr("p"), VStr("op"), VStr("list"), VStr("method"))) == VStr("GET") &&
        getpath(c, jt(VStr("entity"), VStr("nope"))) == Noval
    }

    runLocal("condense-view-reads-without-materialising") {
      val c = condense(jm(VStr("entity"), jm(VStr("a"), jm(VStr("v"), VNum(1)), VStr("b"), jm(VStr("v"), VNum(2))),
        VStr("other"), VNum(9)))
      val v = condenseview(c)
      // keys() answers from the node and symbol tables alone.
      v.keys(VStr("entity")) == Seq("a", "b") &&
        v.at(VStr("entity")).at(VStr("b")).get(VStr("v")) == VNum(2) &&
        v.has(VStr("entity.a")) && !v.has(VStr("entity.zz")) && v.size() == 2
    }

    runLocal("condense-value-copies-and-ref-shares") {
      val v = condenseview(condense(jm(VStr("a"), jm(VStr("m"), VStr("GET")), VStr("b"), jm(VStr("m"), VStr("GET")))))
      // a and b share one node; get() must not let that be observable.
      val x = v.get(VStr("a"))
      val y = v.get(VStr("b"))
      val copies = x == y && (x ne y)
      setprop(x, VStr("m"), VStr("MUTATED"))
      // ref() is the opt-in escape hatch and does share.
      copies && getprop(v.get(VStr("b")), VStr("m")) == VStr("GET") && (v.at(VStr("a")).ref() eq v.at(VStr("a")).ref())
    }

    runLocal("condense-preserves-proto-named-keys-and-values") {
      val asValue = jm(VStr("x"), VStr("__proto__"))
      val asKey = jm(VStr("__proto__"), VNum(1))
      expand(condense(asValue)) == asValue &&
        jsonify(expand(condense(asKey)), jm(VStr("indent"), VNum(0))) == "{\"__proto__\":1}"
    }

    runLocal("condense-getpath-matches-plain-on-null-and-options") {
      // Group A: a stored null reads as absent either way.
      val nullval = jm(VStr("a"), VNull)
      // A base must not be ignored by the condensed fast path.
      val store = jm(VStr("base"), jm(VStr("x"), VNum(1)))
      val d = new InjDef
      d.dBase = VStr("base")
      getpath(condense(nullval), VStr("a")) == getpath(nullval, VStr("a")) &&
        getpath(condense(nullval), VStr("a")) == Noval &&
        getpath(condense(store), VStr("x"), IDef(d)) == getpath(store, VStr("x"), IDef(d)) &&
        getpath(condense(store), VStr("x"), IDef(d)) == VNum(1)
    }

    runLocal("condense-list-keys-are-canonical-integers") {
      val plain = jm(VStr("l"), jt(VNum(10), VNum(20)))
      val c = condense(plain)
      // A plain list read misses each of these, and condensing must not change
      // which value a path selects.
      Seq("01", "1e0", " 1", "+1", "1.0", "-0").forall(k =>
        getpath(c, jt(VStr("l"), VStr(k))) == getpath(plain, jt(VStr("l"), VStr(k)))) &&
        getpath(c, jt(VStr("l"), VStr("1"))) == VNum(20)
    }

    runLocal("condense-symbols-sort-by-code-point") {
      getprop(condense(jm(VStr("a"), VStr("\uD800\uDC00"), VStr("b"), VStr("\uFFFF"))), VStr("sym")) match {
        case VList(sym) => sym.indexOf(VStr("\uFFFF")) < sym.indexOf(VStr("\uD800\uDC00"))
        case _ => false
      }
    }

    runLocal("condense-invalid-key-mutations-stay-no-ops") {
      // An invalid key is ignored, so a call that cannot write must not raise.
      val c = condense(jm(VStr("a"), VNum(1)))
      (delprop(c, Noval) eq c) && (setprop(c, Noval, VNum(1)) eq c) && raisesImmutable(delprop(c, VStr("sym")))
    }

    runLocal("condense-is-immutable") {
      val c = condense(jm(VStr("a"), VNum(1)))
      val raises = raisesImmutable(setpath(c, VStr("a"), VNum(2))) &&
        raisesImmutable(setprop(c, VStr("a"), VNum(2))) &&
        raisesImmutable(delprop(c, VStr("sym")))
      // The expanded copy is ordinary and mutable.
      val e = expand(c)
      setpath(e, VStr("a"), VNum(2))
      raises && getprop(e, VStr("a")) == VNum(2)
    }
  }

  // ---------------- validate: what the corpus cannot express ----------------

  def runValidateLocal(): Unit = {
    runLocal("validate-child-one-error-per-failure") {
      def errs(data: Value, spec: Value): Value = {
        val d = new InjDef
        d.dErrs = emptyList()
        validate(data, spec, IDef(d))
        d.dErrs
      }
      Seq(jm(VStr("x"), jm(VStr("`$CHILD`"), VStr("`$NUMBER`"))), jm(VStr("x"), jt(VStr("`$CHILD`"), VStr("`$NUMBER`"))))
        .forall(spec => size(errs(jm(VStr("x"), VNum(1)), spec)) == 1) &&
        errs(VNum(1), jm(VStr("`$CHILD`"), VStr("`$NUMBER`"))) == jt(VStr("Expected map, but found integer: 1.")) &&
        errs(VNum(1), jt(VStr("`$CHILD`"), VStr("`$NUMBER`"))) == jt(VStr("Expected list, but found integer: 1."))
    }
  }

  // ---------------- groups ----------------

  def runAll(spec: Value): Unit = {
    def g(k: String): Value = getprop(spec, VStr(k))
    val minor = g("minor"); val walks = g("walk"); val merges = g("merge")
    val getpaths = g("getpath"); val injects = g("inject"); val transforms = g("transform")
    val validates = g("validate"); val selects = g("select"); val sentinels = g("sentinels")
    val regexs = g("regex")
    def mg(n: String): Value = getprop(minor, VStr(n))

    val condenses = g("condense")
    runSet("condense.condense", getprop(condenses, VStr("condense")), arg1(condense), false)
    runSet("condense.expand", getprop(condenses, VStr("expand")), arg1(expand), false)
    runSet("condense.iscondensed", getprop(condenses, VStr("iscondensed")), arg1(v => VBool(iscondensed(v))), false)
    runCondenseLocal()

    runSet("minor.isnode", mg("isnode"), arg1(v => VBool(isnode(v))))
    runSet("minor.ismap", mg("ismap"), arg1(v => VBool(ismap(v))))
    runSet("minor.islist", mg("islist"), arg1(v => VBool(islist(v))))
    runSet("minor.iskey", mg("iskey"), arg1(v => VBool(iskey(v))), false)
    runSet("minor.strkey", mg("strkey"), arg1(v => VStr(strkey(v))), false)
    runSet("minor.isempty", mg("isempty"), arg1(v => VBool(isempty(v))), false)
    runSet("minor.isfunc", mg("isfunc"), arg1(v => VBool(isfunc(v))))
    runSet("minor.clone", mg("clone"), arg1(v => sclone(v)), false)
    runSet("minor.escre", mg("escre"), arg1(escre))
    runSet("minor.escurl", mg("escurl"), arg1(escurl))
    runSet("minor.stringify", mg("stringify"), arg1(vin => if (vhas(vin, "val")) VStr(stringify(vget(vin, "val"), vget(vin, "max"))) else VStr(stringify(Noval))), false)
    runSet("minor.jsonify", mg("jsonify"), arg1(vin => VStr(jsonify(vget(vin, "val"), vget(vin, "flags")))), false)
    runSet("minor.getelem", mg("getelem"), arg1(vin => { val alt = vget(vin, "alt"); if (isNullish(alt)) getelem(vget(vin, "val"), vget(vin, "key")) else getelem(vget(vin, "val"), vget(vin, "key"), alt) }), false)
    runSet("minor.delprop", mg("delprop"), arg1(vin => delprop(vget(vin, "parent"), vget(vin, "key"))))
    runSet("minor.size", mg("size"), arg1(v => vint(size(v))), false)
    runSet("minor.slice", mg("slice"), arg1(vin => slice(vget(vin, "val"), vget(vin, "start"), vget(vin, "end"))), false)
    runSet("minor.pad", mg("pad"), arg1(vin => VStr(pad(vget(vin, "val"), vget(vin, "pad"), vget(vin, "char")))), false)
    runSet("minor.pathify", mg("pathify"), arg1(vin => if (vhas(vin, "path")) VStr(pathify(vget(vin, "path"), vget(vin, "from"))) else VStr(pathify(Noval, vget(vin, "from"), absent = true))), false)
    runSet("minor.items", mg("items"), arg1(items))
    // Canonical omits `alt` only when the KEY is missing (`undefined ===
    // vin.alt`), so a present `alt: null` still goes through; getelem's rule
    // is the looser `null == vin.alt`. `minor/getprop#51` is the entry that
    // separates them - csharp, c and ocaml carried the same confusion.
    runSet("minor.getprop", mg("getprop"), arg1(vin =>
      if (vhas(vin, "alt")) getprop(vget(vin, "val"), vget(vin, "key"), vget(vin, "alt"))
      else getprop(vget(vin, "val"), vget(vin, "key"))), false)
    runSet("minor.setprop", mg("setprop"), arg1(vin => setprop(vget(vin, "parent"), vget(vin, "key"), vget(vin, "val"))))
    runSet("minor.haskey", mg("haskey"), arg1(vin => VBool(haskey(vget(vin, "src"), vget(vin, "key")))), false)
    runSet("minor.keysof", mg("keysof"), arg1(v => mkList(keysof(v).map(s => VStr(s)))))
    runSet("minor.join", mg("join"), arg1(vin => VStr(join(vget(vin, "val"), vget(vin, "sep"), vget(vin, "url") match { case VBool(true) => true; case _ => false }))), false)
    runSet("minor.typify", mg("typify"), arg1(v => vint(typify(v))), false)
    runSet("minor.setpath", mg("setpath"), arg1(vin => setpath(vget(vin, "store"), vget(vin, "path"), vget(vin, "val"))), false)
    runSet("minor.filter", mg("filter"), arg1(vin => {
      val check: ((String, Value)) => Boolean = vget(vin, "check") match {
        case VStr("gt3") => { case (_, x) => x match { case VNum(n) => n > 3.0; case _ => false } }
        case VStr("lt3") => { case (_, x) => x match { case VNum(n) => n < 3.0; case _ => false } }
        case _ => _ => false
      }
      filter(vget(vin, "val"), check)
    }))
    runSet("minor.typename", mg("typename"), arg1(v => VStr(typename(v match { case VNum(n) => n.toInt; case _ => 0 }))))
    runSet("minor.flatten", mg("flatten"), arg1(vin => flatten(vget(vin, "val"), vget(vin, "depth") match { case VNum(n) => n.toInt; case _ => 1 })))

    runWalkLog("walk.log", getprop(walks, VStr("log")))
    runSet("walk.basic", getprop(walks, VStr("basic")), arg1(vin => walk(vin, after = Some((_k, v, _p, path) => v match {
      case VStr(s) => VStr(s + "~" + (path match { case VList(b) => b.toSeq; case _ => Seq.empty }).map(jsString).mkString("."))
      case _ => v
    }))))
    runSet("walk.copy", getprop(walks, VStr("copy")), arg1(walkCopySubject))
    runSet("walk.depth", getprop(walks, VStr("depth")), arg1(walkDepthSubject), false)

    runSingle("merge.basic", getprop(merges, VStr("basic")), in_ => merge(sclone(in_)))
    runSet("merge.cases", getprop(merges, VStr("cases")), arg1(v => merge(v)))
    runSet("merge.array", getprop(merges, VStr("array")), arg1(v => merge(v)))
    runSet("merge.integrity", getprop(merges, VStr("integrity")), arg1(v => merge(v)))
    runSet("merge.depth", getprop(merges, VStr("depth")), arg1(vin => merge(vget(vin, "val"), vget(vin, "depth"))))

    runSet("getpath.basic", getprop(getpaths, VStr("basic")), arg1(vin => getpath(vget(vin, "store"), vget(vin, "path"))))
    runSet("getpath.relative", getprop(getpaths, VStr("relative")), arg1(vin => {
      val dpath = vget(vin, "dpath") match { case VStr(s) => mkList(s.split("\\.", -1).map(x => VStr(x)).toSeq); case _ => Noval }
      val d = new InjDef; d.dParent = vget(vin, "dparent"); d.dPath = dpath
      getpath(vget(vin, "store"), vget(vin, "path"), IDef(d))
    }))
    runSet("getpath.special", getprop(getpaths, VStr("special")), arg1(vin => {
      val injm = vget(vin, "inj")
      val d = new InjDef
      d.dBase = getprop(injm, VStr("base")); d.dMeta = getprop(injm, VStr("meta"))
      d.dParent = getprop(injm, VStr("dparent")); d.dPath = getprop(injm, VStr("dpath")); d.dKey = getprop(injm, VStr("key"))
      getpath(vget(vin, "store"), vget(vin, "path"), if (isNullish(injm)) INone else IDef(d))
    }))
    runSet("getpath.handler", getprop(getpaths, VStr("handler")), arg1(vin => {
      val store = omapV("$TOP" -> vget(vin, "store"), "$FOO" -> VFunc((_, _, _, _) => VStr("foo")))
      val d = new InjDef
      d.dHandler = Some((_inj, v, _ref, _store) => v match { case VFunc(f) => f(_inj, Noval, "", Noval); case _ => v })
      getpath(store, vget(vin, "path"), IDef(d))
    }))

    runSingle("inject.basic", getprop(injects, VStr("basic")), in_ => inject(sclone(getprop(in_, VStr("val"))), sclone(getprop(in_, VStr("store")))))
    runSet("inject.string", getprop(injects, VStr("string")), arg1(vin => {
      val d = new InjDef; d.dModify = Some(nullModifier); d.dExtra = vget(vin, "current")
      inject(vget(vin, "val"), vget(vin, "store"), IDef(d))
    }))
    runSet("inject.deep", getprop(injects, VStr("deep")), arg1(vin => inject(vget(vin, "val"), vget(vin, "store"))))

    runSingle("transform.basic", getprop(transforms, VStr("basic")), in_ => transform(getprop(in_, VStr("data")), getprop(in_, VStr("spec"))))
    Seq("paths", "cmds", "each", "pack", "ref").foreach { gn =>
      runSet("transform." + gn, getprop(transforms, VStr(gn)), arg1(vin => transform(vget(vin, "data"), vget(vin, "spec"))))
    }
    runSet("transform.modify", getprop(transforms, VStr("modify")), arg1(vin => {
      val d = new InjDef
      d.dModify = Some((v, key, parent, _inj) => v match {
        case VStr(s) if !isNullish(key) && !isNullish(parent) => setprop(parent, key, VStr("@" + s))
        case _ => ()
      })
      d.dExtra = vget(vin, "store")
      transform(vget(vin, "data"), vget(vin, "spec"), IDef(d))
    }))
    runSet("transform.format", getprop(transforms, VStr("format")), arg1(vin => transform(vget(vin, "data"), vget(vin, "spec"))), false)
    runSet("transform.apply", getprop(transforms, VStr("apply")), arg1(vin => transform(vget(vin, "data"), vget(vin, "spec"))))

    runSet("validate.basic", getprop(validates, VStr("basic")), arg1(vin => validate(vget(vin, "data"), vget(vin, "spec"))), false)
    Seq("child", "exact").foreach { gn =>
      runSet("validate." + gn, getprop(validates, VStr(gn)), arg1(vin => validate(vget(vin, "data"), vget(vin, "spec"))))
    }
    runSet("validate.invalid", getprop(validates, VStr("invalid")), arg1(vin => validate(vget(vin, "data"), vget(vin, "spec"))), false)
    runSet("validate.special", getprop(validates, VStr("special")), arg1(vin => {
      val injm = vget(vin, "inj")
      val d = new InjDef; d.dMeta = getprop(injm, VStr("meta"))
      validate(vget(vin, "data"), vget(vin, "spec"), if (isNullish(injm)) INone else IDef(d))
    }))
    Seq("directive", "nof", "all", "unknown").foreach { gn =>
      runSet("validate." + gn, getprop(validates, VStr(gn)), arg1(vin => validate(vget(vin, "data"), vget(vin, "spec"))), false)
    }
    runValidateLocal()

    Seq("basic", "operators", "edge", "alts").foreach { gn =>
      runSet("select." + gn, getprop(selects, VStr(gn)), arg1(vin => select(vget(vin, "obj"), vget(vin, "query"))))
    }

    // `null: false` keeps a JSON null an ACTUAL null rather than the NULLMARK
    // string, so select sees a present-but-null field.
    runSet("select.nullkey", getprop(selects, VStr("nullkey")), arg1(vin => select(vget(vin, "obj"), vget(vin, "query"))), false)

    // regex (parity floor: Go stdlib regexp — see design/REGEX_API.md)
    runSet("regex.test", getprop(regexs, VStr("test")), arg1(vin => re_test(vget(vin, "pattern"), vget(vin, "input"))))
    runSet("regex.find", getprop(regexs, VStr("find")), arg1(vin => re_find(vget(vin, "pattern"), vget(vin, "input"))))
    runSet("regex.find_all", getprop(regexs, VStr("find_all")), arg1(vin => re_find_all(vget(vin, "pattern"), vget(vin, "input"))))
    runSet("regex.replace", getprop(regexs, VStr("replace")), arg1(vin => re_replace(vget(vin, "pattern"), vget(vin, "input"), vget(vin, "replacement"))))
    runSet("regex.escape", getprop(regexs, VStr("escape")), arg1(vin => re_escape(vget(vin, "val"))))

    runSet("sentinels.getprop_unify", getprop(sentinels, VStr("getprop_unify")), arg1(vin => getprop(vget(vin, "val"), vget(vin, "key"), vget(vin, "alt"))), false)
    runSet("sentinels.getelem_absent", getprop(sentinels, VStr("getelem_absent")), arg1(vin => getelem(vget(vin, "val"), vget(vin, "key"), vget(vin, "alt"))), false)
    runSet("sentinels.haskey_unify", getprop(sentinels, VStr("haskey_unify")), arg1(vin => VBool(haskey(vget(vin, "val"), vget(vin, "key")))), false)
    runSet("sentinels.isempty_unify", getprop(sentinels, VStr("isempty_unify")), arg1(v => VBool(isempty(v))), false)
    runSet("sentinels.isnode_unify", getprop(sentinels, VStr("isnode_unify")), arg1(v => VBool(isnode(v))), false)
    runSet("sentinels.stringify_null", getprop(sentinels, VStr("stringify_null")), arg1(vin => VStr(stringify(vin))), false)
  }

  // ---------------- the client path ----------------

  // `DEF.client`, client-scoped options, and `contextify`. This port had no
  // such test. It is the only thing that exercises subject resolution through
  // a PROVIDER rather than through a callback this file hands over - so
  // nothing here had ever checked that a corpus `client` key resolves, or that
  // a `DEF.client` entry's options reach the subject.
  //
  // The subject talks to omni DIRECTLY, in omni's own value type: the runner
  // resolves it by name off the provider, so there is no `in` to convert and
  // no result for the bridge to convert back.
  def check(options: Json)(args: List[Json]): Json = {
    val foo = options.get("foo")
    val foos = if (foo.isabsent) "" else OU.stringify(foo)
    val ctx = args.headOption.getOrElse(Json.Absent)
    val bar = ctx.get("meta").get("bar")
    val bars = if (bar.isnone) "0" else OU.stringify(bar)
    Json.JMap(ListMap("zed" -> Json.Str("ZED" + foos + "_" + bars)))
  }

  def clientProvider(options: Json): Provider = Provider(
    subject = Some(name => if (name == "check") Some(check(options)) else None),
    // A DEF.client entry becomes another provider, carrying its options.
    client = Some(clientProvider),
    // This port adds nothing to a context; the hook must exist so omni
    // installs `client` on it.
    contextify = Some(value => value),
  )

  def runClient(testfile: String): Unit = {
    try {
      val resolved = O.makeRunner(testfile, clientProvider(Json.JMap(ListMap.empty))).runner("check")
      // No subject: the runner resolves it by name off the provider, which is
      // the whole point of the group.
      resolved.runsetflags(resolved.set("basic"), Flags(name = Some("check.basic")))
      record("check.basic", true, "")
    } catch { case e: Throwable => record("check.basic", false, errmsg(e)) }
  }

  def main(args: Array[String]): Unit = {
    val testfile = if (args.length > 0) args(0) else "../build/test/test.json"
    val resolved = O.makeRunner(testfile, Provider()).runner("struct")
    pack = resolved
    runAll(tostruct(resolved.spec))
    runClient(testfile)
    failures.foreach(println)
    println(s"\n${npass + nfail} groups, $nfail failed")
    if (nfail > 0) System.exit(1)
  }
}
