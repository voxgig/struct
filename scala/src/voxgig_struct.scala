// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
//
// Voxgig Struct — Scala port.
//
// A faithful port of the canonical TypeScript implementation
// (typescript/src/StructUtility.ts). Like TypeScript (and the Rust / OCaml
// ports), Scala keeps `undefined` (Noval) and JSON `null` (VNull) distinct, so
// this port mirrors the canonical TS logic directly. Nodes are mutable and
// reference-stable: lists are `ArrayBuffer[Value]`, maps are an insertion-
// ordered `LinkedHashMap[String, Value]`. The only regex used is the JVM
// standard `java.util.regex`; there are no third-party runtime dependencies.

package voxgig

import scala.collection.mutable.{ArrayBuffer, HashMap, HashSet, LinkedHashMap}

object struct {

  // ---------------------------------------------------------------------------
  // Value model
  // ---------------------------------------------------------------------------

  sealed trait Value
  case object Noval extends Value                       // TS undefined — absent
  case object VNull extends Value                       // JSON null
  final case class VBool(b: Boolean) extends Value
  final case class VNum(n: Double) extends Value
  final case class VStr(s: String) extends Value
  final case class VList(buf: ArrayBuffer[Value]) extends Value
  final case class VMap(map: LinkedHashMap[String, Value]) extends Value
  final case class VFunc(f: Injector) extends Value
  final case class VSentinel(tag: String) extends Value

  type Injector = (Inj, Value, String, Value) => Value
  type Modify = (Value, Value, Value, Inj) => Unit
  type WalkFn = (Value, Value, Value, Value) => Value

  final class Inj {
    var mode: Int = M_VAL
    var full: Boolean = false
    var keyi: Int = 0
    var keys: Value = mkList(Seq(VStr(S_DTOP)))
    var key: Value = VStr(S_DTOP)
    var ival: Value = Noval
    var parent: Value = Noval
    var path: Value = mkList(Seq(VStr(S_DTOP)))
    var nodes: Value = mkList(Seq())
    var handler: Injector = injectHandler
    var errs: Value = mkList(Seq())
    var meta: Value = emptyMap()
    var dparent: Value = Noval
    var dpath: Value = mkList(Seq(VStr(S_DTOP)))
    var base: Value = VStr(S_DTOP)
    var modify: Option[Modify] = None
    var prior: Option[Inj] = None
    var extra: Value = Noval
  }

  final class InjDef {
    var dMeta: Value = Noval
    var dExtra: Value = Noval
    var dErrs: Value = Noval
    var dModify: Option[Modify] = None
    var dHandler: Option[Injector] = None
    var dBase: Value = Noval
    var dParent: Value = Noval
    var dPath: Value = Noval
    var dKey: Value = Noval
  }

  sealed trait InjArg
  case object INone extends InjArg
  final case class IInj(inj: Inj) extends InjArg
  final case class IDef(d: InjDef) extends InjArg

  final case class StructError(msg: String) extends RuntimeException(msg)

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------

  val M_KEYPRE = 1
  val M_KEYPOST = 2
  val M_VAL = 4

  val S_DKEY = "$KEY"
  val S_BANNO = "`$ANNO`"
  val S_DTOP = "$TOP"
  val S_DERRS = "$ERRS"
  val S_DSPEC = "$SPEC"
  val S_BEXACT = "`$EXACT`"
  val S_BVAL = "`$VAL`"
  val S_BKEY = "`$KEY`"
  val S_BOPEN = "`$OPEN`"

  val S_MT = ""
  val S_BT = "`"
  val S_DS = "$"
  val S_DT = "."
  val S_CN = ":"
  val S_KEY = "KEY"
  val S_VIZ = ": "

  val S_string = "string"
  val S_object = "object"
  val S_list = "list"
  val S_map = "map"
  val S_nil = "nil"
  val S_null = "null"

  val T_any = (1 << 31) - 1
  val T_noval = 1 << 30
  val T_boolean = 1 << 29
  val T_decimal = 1 << 28
  val T_integer = 1 << 27
  val T_number = 1 << 26
  val T_string = 1 << 25
  val T_function = 1 << 24
  val T_null = 1 << 22
  val T_list = 1 << 14
  val T_map = 1 << 13
  val T_instance = 1 << 12
  val T_scalar = 1 << 7
  val T_node = 1 << 6

  val TYPENAME = Array(
    "any", "nil", "boolean", "decimal", "integer", "number", "string", "function",
    "symbol", "null", "", "", "", "", "", "", "", "list", "map", "instance",
    "", "", "", "", "scalar", "node")

  val SKIP: Value = VSentinel("skip")
  val DELETE: Value = VSentinel("delete")

  val MAXDEPTH = 32

  // ---------------------------------------------------------------------------
  // Constructors / tiny helpers
  // ---------------------------------------------------------------------------

  def mkList(xs: Seq[Value]): Value = VList(ArrayBuffer.from(xs))
  def emptyList(): Value = VList(ArrayBuffer.empty[Value])
  def emptyMap(): Value = VMap(LinkedHashMap.empty[String, Value])
  def mkMap(pairs: Seq[(String, Value)]): Value = {
    val m = LinkedHashMap.empty[String, Value]
    pairs.foreach { case (k, v) => m.put(k, v) }
    VMap(m)
  }
  def vint(i: Int): Value = VNum(i.toDouble)

  def isNoval(v: Value): Boolean = v == Noval
  def isNullish(v: Value): Boolean = v == Noval || v == VNull
  def isSkip(v: Value): Boolean = v == VSentinel("skip")
  def isDelete(v: Value): Boolean = v == VSentinel("delete")

  def isIntegerF(n: Double): Boolean = !n.isNaN && !n.isInfinite && n == Math.floor(n)

  def numToString(n: Double): String = {
    if (n.isNaN) "NaN"
    else if (isIntegerF(n) && Math.abs(n) < 1e16) n.toLong.toString
    else n.toString
  }

  def jsString(v: Value): String = v match {
    case Noval => "undefined"
    case VNull => "null"
    case VBool(b) => if (b) "true" else "false"
    case VNum(n) => numToString(n)
    case VStr(s) => s
    case VList(b) => b.map(x => x match { case Noval | VNull => ""; case _ => jsString(x) }).mkString(",")
    case VMap(_) => "[object Object]"
    case VFunc(_) => "function"
    case VSentinel(t) => t
  }

  def clz32(x0: Int): Int = if (x0 == 0) 32 else Integer.numberOfLeadingZeros(x0)

  // ordered map ops on the underlying LinkedHashMap
  def omapGet(m: LinkedHashMap[String, Value], k: String): Option[Value] = m.get(k)
  def omapHas(m: LinkedHashMap[String, Value], k: String): Boolean = m.contains(k)
  def omapKeys(m: LinkedHashMap[String, Value]): Seq[String] = m.keysIterator.toSeq
  def omapLen(m: LinkedHashMap[String, Value]): Int = m.size
  def omapSet(m: LinkedHashMap[String, Value], k: String, v: Value): Unit = m.put(k, v)
  def omapDel(m: LinkedHashMap[String, Value], k: String): Unit = m.remove(k)

  // ---------------------------------------------------------------------------
  // Minor utilities
  // ---------------------------------------------------------------------------

  def isnode(v: Value): Boolean = v match { case VMap(_) | VList(_) => true; case _ => false }
  def ismap(v: Value): Boolean = v match { case VMap(_) => true; case _ => false }
  def islist(v: Value): Boolean = v match { case VList(_) => true; case _ => false }
  def isfunc(v: Value): Boolean = v match { case VFunc(_) => true; case _ => false }

  def iskey(k: Value): Boolean = k match {
    case VStr(s) => s.nonEmpty
    case VNum(_) => true
    case _ => false
  }

  def isempty(v: Value): Boolean =
    isNullish(v) || v == VStr("") || (v match {
      case VList(b) => b.isEmpty
      case VMap(m) => m.isEmpty
      case _ => false
    })

  def getdef(v: Value, alt: Value): Value = if (isNoval(v)) alt else v

  def typify(v: Value): Int = v match {
    case Noval => T_noval
    case VNull => T_scalar | T_null
    case VBool(_) => T_scalar | T_boolean
    case VNum(n) =>
      if (n.isNaN) T_noval
      else if (isIntegerF(n)) T_scalar | T_number | T_integer
      else T_scalar | T_number | T_decimal
    case VStr(_) => T_scalar | T_string
    case VFunc(_) => T_scalar | T_function
    case VList(_) => T_node | T_list
    case VMap(_) => T_node | T_map
    case VSentinel(_) => T_node | T_map
  }

  def typename(t: Int): String = {
    val i = clz32(t)
    if (i >= 0 && i < TYPENAME.length) TYPENAME(i) else TYPENAME(0)
  }

  def size(v: Value): Int = v match {
    case VList(b) => b.length
    case VMap(m) => m.size
    case VStr(s) => s.length
    case VBool(b) => if (b) 1 else 0
    case VNum(n) => Math.floor(n).toInt
    case _ => 0
  }

  def strkey(key: Value = Noval): String = key match {
    case Noval => S_MT
    case VStr(s) => s
    case VBool(_) => S_MT
    case VNum(n) => if (isIntegerF(n)) numToString(n) else numToString(Math.floor(n))
    case _ => S_MT
  }

  def keysof(v: Value): Seq[String] = v match {
    case VMap(m) => omapKeys(m).sorted
    case VList(b) => b.indices.map(_.toString)
    case _ => Seq.empty
  }

  private val R_LIST_INDEX = java.util.regex.Pattern.compile("^(0|-?[1-9][0-9]*)$")

  // A list key's index, or NaN: an integral number, or the string String(n)
  // prints for one, negative or not ("01", "+1", "1.0" and "-0" are not).
  private def listIndex(key: Value): Double = key match {
    case VNum(n) => if (isIntegerF(n)) n else Double.NaN
    case VStr(s) if R_LIST_INDEX.matcher(s).matches() => s.toDouble
    case _ => Double.NaN
  }

  private def listGet(b: ArrayBuffer[Value], key: Value): Value = {
    val i = listIndex(key)
    if (0.0 <= i && i < b.length) b(i.toInt) else Noval
  }

  // A string or a number: a read misses at any other key.
  private def isKeyType(key: Value): Boolean = key match {
    case VStr(_) | VNum(_) => true
    case _ => false
  }

  private def mapGet(m: LinkedHashMap[String, Value], key: Value): Value =
    if (isKeyType(key)) omapGet(m, jsString(key)).getOrElse(Noval) else Noval

  def getprop(v: Value, key: Value, alt: Value = Noval): Value = {
    if (isNoval(v) || isNoval(key)) alt
    else {
      val out = v match {
        case VMap(m) => mapGet(m, key)
        case VList(b) => listGet(b, key)
        case _ => Noval
      }
      if (isNullish(out)) alt else out
    }
  }

  // Raw lookup that preserves stored VNull (Group B), like TS _lookup.
  def lookup_(v: Value, key: Value): Value = {
    if (isNoval(v) || isNoval(key)) Noval
    else v match {
      case VMap(m) => mapGet(m, key)
      case VList(b) => listGet(b, key)
      case _ => Noval
    }
  }

  def haskey(v: Value, key: Value): Boolean = !isNullish(getprop(v, key))

  // dummy inj for the (corpus-unreached) getelem function-alt path
  private lazy val dummyInj: Inj = { val i = new Inj; i.parent = mkMap(Seq((S_DTOP, Noval))); i }

  def getelem(v: Value, key: Value, alt: Value = Noval): Value = {
    if (isNoval(v) || isNoval(key)) alt
    else {
      var out: Value = Noval
      v match {
        case VList(b) =>
          val i = listIndex(key)
          // A negative key counts from the end.
          val nk = if (i < 0.0) b.length + i else i
          if (0.0 <= nk && nk < b.length) out = b(nk.toInt)
        case _ =>
      }
      if (isNullish(out)) (alt match {
        case VFunc(f) => f(dummyInj, Noval, "", Noval)
        case _ => alt
      })
      else out
    }
  }

  private def getpropRaw(v: Value, k: String): Value = v match {
    case VMap(m) => omapGet(m, k).getOrElse(Noval)
    case VList(b) => try b(k.toInt) catch { case _: Throwable => Noval }
    case _ => Noval
  }

  def itemsPairs(v: Value): Seq[(String, Value)] =
    if (!isnode(v)) Seq.empty else keysof(v).map(k => (k, getpropRaw(v, k)))

  def itemsV(v: Value, f: ((String, Value)) => Value): Value =
    mkList(itemsPairs(v).map(f))

  def items(v: Value): Value =
    mkList(itemsPairs(v).map { case (k, x) => mkList(Seq(VStr(k), x)) })

  def flatten(l: Value, depth: Int = 1): Value =
    if (!islist(l)) l
    else {
      val out = ArrayBuffer.empty[Value]
      l match {
        case VList(b) => b.foreach { item =>
          if (islist(item) && depth > 0) flatten(item, depth - 1) match {
            case VList(b2) => b2.foreach(out.append)
            case _ =>
          }
          else out.append(item)
        }
        case _ =>
      }
      VList(out)
    }

  def filter(v: Value, check: ((String, Value)) => Boolean): Value = {
    val out = ArrayBuffer.empty[Value]
    itemsPairs(v).foreach { case (k, x) => if (check((k, x))) out.append(x) }
    VList(out)
  }

  def setprop(parent: Value, key: Value, v: Value): Value = {
    if (iskey(key) && iscondensed(parent)) throw StructError(CONDENSE_IMMUTABLE)
    if (iskey(key)) parent match {
      case VMap(m) => omapSet(m, jsString(key), v)
      case VList(b) =>
        val ki = listIndex(key)
        if (!ki.isNaN) {
          if (ki < 0.0) b.insert(0, v)
          else if (ki < b.length) b(ki.toInt) = v
          else b.append(v)
        }
      case _ =>
    }
    parent
  }

  def delprop(parent: Value, key: Value): Value = {
    if (iskey(key) && iscondensed(parent)) throw StructError(CONDENSE_IMMUTABLE)
    if (iskey(key)) parent match {
      case VMap(m) => omapDel(m, jsString(key))
      case VList(b) =>
        val ki = listIndex(key)
        if (0.0 <= ki && ki < b.length) b.remove(ki.toInt)
      case _ =>
    }
    parent
  }

  def clone(v: Value): Value = v match {
    case VList(b) => VList(b.map(clone))
    case VMap(m) =>
      val nm = LinkedHashMap.empty[String, Value]
      m.foreach { case (k, x) => nm.put(k, clone(x)) }
      VMap(nm)
    case _ => v
  }

  def slice(v: Value, start: Value = Noval, stop: Value = Noval, mutate: Boolean = false): Value = v match {
    case VNum(n) =>
      val lo = start match { case VNum(s) => s; case _ => Double.NegativeInfinity }
      val hi = stop match { case VNum(e) => e - 1.0; case _ => Double.PositiveInfinity }
      VNum(Math.max(lo, Math.min(n, hi)))
    case VList(_) | VStr(_) =>
      val vlen = size(v)
      val start2 = (start, stop) match { case (Noval, x) if !isNoval(x) => VNum(0.0); case _ => start }
      start2 match {
        case VNum(sf) =>
          val s0 = sf.toInt
          var s = s0
          var e = 0
          if (s0 < 0) { s = 0; e = { val ee = vlen + s0; if (ee < 0) 0 else ee } }
          else stop match {
            case VNum(ef) =>
              val e0 = ef.toInt
              if (e0 < 0) { e = { val ee = vlen + e0; if (ee < 0) 0 else ee } }
              else if (vlen < e0) e = vlen
              else e = e0
            case _ => e = vlen
          }
          if (vlen < s) s = vlen
          if (s > -1 && s <= e && e <= vlen) v match {
            case VList(b) =>
              if (mutate) { val sub = b.slice(s, e); b.clear(); b ++= sub; v }
              else VList(b.slice(s, e))
            case VStr(str) => VStr(str.substring(s, e))
            case _ => v
          } else v match {
            case VList(b) => if (mutate) { b.clear(); v } else emptyList()
            case VStr(_) => VStr(S_MT)
            case _ => v
          }
        case _ => v
      }
    case _ => v
  }

  // ---------------------------------------------------------------------------
  // Regex (uniform re_* API over java.util.regex)
  // ---------------------------------------------------------------------------

  private def reStr(p: Value): String = p match { case VStr(s) => s; case _ => jsString(p) }

  def re_compile(p: Value, flags: Value = Noval): Value = p match { case VStr(_) => p; case _ => VStr(jsString(p)) }
  def re_test(p: Value, input: Value): Value =
    VBool(java.util.regex.Pattern.compile(reStr(p)).matcher(reStr(input)).find())
  def re_find(p: Value, input: Value): Value = {
    val m = java.util.regex.Pattern.compile(reStr(p)).matcher(reStr(input))
    if (m.find()) {
      val buf = ArrayBuffer[Value](VStr(m.group(0)))
      for (i <- 1 to m.groupCount()) buf.append(VStr(Option(m.group(i)).getOrElse("")))
      VList(buf)
    } else VNull
  }
  def re_find_all(p: Value, input: Value): Value = {
    val m = java.util.regex.Pattern.compile(reStr(p)).matcher(reStr(input))
    val out = ArrayBuffer.empty[Value]
    while (m.find()) {
      val buf = ArrayBuffer[Value](VStr(m.group(0)))
      for (i <- 1 to m.groupCount()) buf.append(VStr(Option(m.group(i)).getOrElse("")))
      out.append(VList(buf))
    }
    VList(out)
  }
  def re_replace(p: Value, input: Value, repl: Value): Value = {
    // String replacement with JS-style refs: translate $& to Java's $0;
    // $1..$9 are native java.util.regex syntax.
    val jrepl = reStr(repl).replace("$&", "$0")
    VStr(java.util.regex.Pattern.compile(reStr(p)).matcher(reStr(input)).replaceAll(jrepl))
  }
  def re_escape(s: Value): Value = escre(s)

  def escre(s: Value): Value = {
    val str = s match { case VStr(x) => x; case Noval => S_MT; case _ => jsString(s) }
    val b = new StringBuilder
    str.foreach { c =>
      c match {
        case '.' | '*' | '+' | '?' | '^' | '$' | '{' | '}' | '(' | ')' | '|' | '[' | ']' | '\\' => b.append('\\')
        case _ =>
      }
      b.append(c)
    }
    VStr(b.toString)
  }

  def escurl(s: Value): Value = {
    val str = s match { case VStr(x) => x; case Noval => S_MT; case _ => jsString(s) }
    val b = new StringBuilder
    str.getBytes("UTF-8").foreach { bt =>
      val c = (bt & 0xff).toChar
      val unreserved = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
        c == '-' || c == '_' || c == '.' || c == '!' || c == '~' || c == '*' || c == '\'' || c == '(' || c == ')'
      if (unreserved) b.append(c) else b.append("%%%02X".format(bt & 0xff))
    }
    VStr(b.toString)
  }

  // ---------------------------------------------------------------------------
  // JSON-ish serialization / stringify / jsonify
  // ---------------------------------------------------------------------------

  private def escJson(s: String, b: StringBuilder): Unit = {
    b.append('"')
    s.foreach {
      case '"' => b.append("\\\"")
      case '\\' => b.append("\\\\")
      case '\n' => b.append("\\n")
      case '\r' => b.append("\\r")
      case '\t' => b.append("\\t")
      case c if c < 32 => b.append("\\u%04x".format(c.toInt))
      case c => b.append(c)
    }
    b.append('"')
  }

  def jsonEncode(v: Value, sort: Boolean = false, indent: Int = -1): String = {
    val b = new StringBuilder
    def enc(v: Value, level: Int): Unit = v match {
      case Noval | VNull => b.append("null")
      case VBool(x) => b.append(if (x) "true" else "false")
      case VNum(n) => b.append(numToString(n))
      case VStr(s) => escJson(s, b)
      case VFunc(_) | VSentinel(_) => b.append("null")
      case VList(buf) =>
        if (buf.isEmpty) b.append("[]")
        else if (indent >= 0) {
          val pad = " " * (indent * (level + 1)); val cpad = " " * (indent * level)
          b.append("[\n")
          buf.zipWithIndex.foreach { case (x, i) => if (i > 0) b.append(",\n"); b.append(pad); enc(x, level + 1) }
          b.append("\n"); b.append(cpad); b.append(']')
        } else {
          b.append('[')
          buf.zipWithIndex.foreach { case (x, i) => if (i > 0) b.append(','); enc(x, level + 1) }
          b.append(']')
        }
      case VMap(m) =>
        val ks0 = m.keysIterator.toSeq
        val ks = if (sort) ks0.sorted else ks0
        if (ks.isEmpty) b.append("{}")
        else if (indent >= 0) {
          val pad = " " * (indent * (level + 1)); val cpad = " " * (indent * level)
          b.append("{\n")
          ks.zipWithIndex.foreach { case (k, i) =>
            if (i > 0) b.append(",\n"); b.append(pad); escJson(k, b); b.append(": "); enc(m(k), level + 1)
          }
          b.append("\n"); b.append(cpad); b.append('}')
        } else {
          b.append('{')
          ks.zipWithIndex.foreach { case (k, i) =>
            if (i > 0) b.append(','); escJson(k, b); b.append(':'); enc(m(k), level + 1)
          }
          b.append('}')
        }
    }
    enc(v, 0); b.toString
  }

  private def hasCycle(v: Value): Boolean = {
    // Identity set: O(1) membership by reference. `add` returns false when the
    // node was already present, matching the previous linear `exists(_ eq _)`
    // scan (same add-never-remove semantics) but O(n) overall, not O(n^2).
    val seen = java.util.Collections.newSetFromMap(
      new java.util.IdentityHashMap[AnyRef, java.lang.Boolean]()
    )
    def go(v: Value): Boolean = v match {
      case VList(b) => if (!seen.add(b)) true else b.exists(go)
      case VMap(m) => if (!seen.add(m)) true else m.valuesIterator.exists(go)
      case _ => false
    }
    go(v)
  }

  def stringify(v: Value, maxlen: Value = Noval, pretty: Boolean = false): String = v match {
    case Noval => if (pretty) "<>" else S_MT
    case _ =>
      var valstr = v match {
        case VStr(s) => s
        case _ =>
          if (hasCycle(v)) "__STRINGIFY_FAILED__"
          else try jsonEncode(v, sort = true).replace("\"", "") catch { case _: Throwable => "__STRINGIFY_FAILED__" }
      }
      maxlen match {
        case VNum(m) if m > -1.0 =>
          val mm = m.toInt; val l = valstr.length
          if (mm < l) valstr = valstr.substring(0, Math.max(0, mm - 3)) + "..."
        case _ =>
      }
      if (pretty) {
        val colors = Array(81, 118, 213, 39, 208, 201, 45, 190, 129, 51, 160, 121, 226, 33, 207, 69)
        val c = colors.map(n => s"[38;5;${n}m")
        val r = "[0m"
        var d = 0; var o = c(0); val t = new StringBuilder; t.append(c(0))
        valstr.foreach { ch =>
          if (ch == '{' || ch == '[') { d += 1; o = c(d % c.length); t.append(o); t.append(ch) }
          else if (ch == '}' || ch == ']') { t.append(o); t.append(ch); d -= 1; o = c(((d % c.length) + c.length) % c.length) }
          else { t.append(o); t.append(ch) }
        }
        t.append(r); t.toString
      } else valstr
  }

  def jsonify(v: Value, flags: Value = Noval): String = v match {
    case Noval => S_null
    case _ =>
      val indent = getprop(flags, VStr("indent"), VNum(2.0)) match { case VNum(n) => n.toInt; case _ => 2 }
      try {
        val str = if (indent > 0) jsonEncode(v, indent = indent) else jsonEncode(v)
        val offset = getprop(flags, VStr("offset"), VNum(0.0)) match { case VNum(n) => n.toInt; case _ => 0 }
        if (offset > 0) {
          val lines = str.split("\n", -1).toSeq
          if (lines.nonEmpty) "{\n" + lines.tail.map(l => (" " * offset) + l).mkString("\n") else str
        } else str
      } catch { case _: Throwable => S_null }
  }

  def pad(s: Value, padding: Value = Noval, padchar: Value = Noval): String = {
    val str = s match { case VStr(x) => x; case VNull => "null"; case _ => stringify(s) }
    val p = padding match { case VNum(n) => n.toInt; case _ => 44 }
    val pc = padchar match { case VStr(x) => (x + " ").substring(0, 1); case _ => " " }
    if (p > -1) { val n = p - str.length; if (n > 0) str + (pc * n) else str }
    else { val n = (-p) - str.length; if (n > 0) (pc * n) + str else str }
  }

  // ---------------------------------------------------------------------------
  // join / pathify / replace
  // ---------------------------------------------------------------------------

  def join(arr: Value, sep: Value = Noval, url: Boolean = false): String = {
    if (!islist(arr)) S_MT
    else {
      val sepdef = sep match { case Noval | VNull => ","; case VStr(s) => s; case _ => jsString(sep) }
      val single = sepdef.length == 1
      val sc = if (single) sepdef.charAt(0) else ' '
      val itemsL = arr match { case VList(b) => b.toSeq; case _ => Seq.empty }
      val sarr = itemsL.length
      def stripTrailing(s: String) = { var i = s.length; while (i > 0 && s.charAt(i - 1) == sc) i -= 1; s.substring(0, i) }
      def stripLeading(s: String) = { var i = 0; while (i < s.length && s.charAt(i) == sc) i += 1; s.substring(i) }
      def collapse(s: String) = {
        val b = new StringBuilder; var i = 0; val n = s.length
        while (i < n) {
          if (s.charAt(i) != sc) { b.append(s.charAt(i)); i += 1 }
          else {
            var j = i; while (j < n && s.charAt(j) == sc) j += 1
            val beforeNon = i > 0 && s.charAt(i - 1) != sc
            val afterNon = j < n
            if (beforeNon && afterNon) b.append(sc) else b.append(s.substring(i, j))
            i = j
          }
        }
        b.toString
      }
      val out = ArrayBuffer.empty[String]
      itemsL.zipWithIndex.foreach {
        case (VStr(s0), idx) if s0 != S_MT =>
          val s = if (single) {
            if (url && idx == 0) stripTrailing(s0)
            else {
              var x = if (idx > 0) stripLeading(s0) else s0
              x = if (idx < sarr - 1 || !url) stripTrailing(x) else x
              collapse(x)
            }
          } else s0
          if (s != S_MT) out.append(s)
        case _ =>
      }
      out.mkString(sepdef)
    }
  }

  def joinurl(arr: Value): String = join(arr, VStr("/"), url = true)

  def replace(s: Value, from: Value, to: Value): String = {
    val ts = typify(s)
    val rs = if ((T_string & ts) == 0) stringify(s)
    else if (((T_noval | T_null) & ts) > 0) S_MT
    else stringify(s)
    val toS = to match { case VStr(x) => x; case _ => jsString(to) }
    from match {
      case VStr(f) if f.nonEmpty => rs.replace(f, toS)
      case _ => rs
    }
  }

  def pathify(v: Value, startin: Value = Noval, endin: Value = Noval, absent: Boolean = false): String = {
    val path: Option[Seq[Value]] =
      if (islist(v)) Some(v match { case VList(b) => b.toSeq; case _ => Seq.empty })
      else if (iskey(v)) Some(Seq(v))
      else None
    val start = startin match { case VNum(n) => if (n > -1.0) n.toInt else 0; case _ => 0 }
    val endn = endin match { case VNum(n) => if (n > -1.0) n.toInt else 0; case _ => 0 }
    val pathstr: Option[String] = path match {
      case Some(p) if start >= 0 =>
        val len = p.length
        val e = Math.max(0, len - endn)
        val s = Math.min(start, len)
        val sub = if (s <= e) p.slice(s, e) else Seq.empty
        if (sub.isEmpty) Some("<root>")
        else {
          val fp = sub.filter(iskey)
          val mapped = fp.map {
            case VNum(n) => numToString(Math.floor(n))
            case pp => jsString(pp).replace(".", S_MT)
          }
          Some(mapped.mkString("."))
        }
      case _ => None
    }
    pathstr match {
      case Some(s) => s
      case None => "<unknown-path" + (if (absent) S_MT else S_CN + stringify(v, VNum(47.0))) + ">"
    }
  }

  // ---------------------------------------------------------------------------
  // walk / merge
  // ---------------------------------------------------------------------------

  def walk(v: Value, before: Option[WalkFn] = None, after: Option[WalkFn] = None,
           maxdepth: Value = Noval, key: Value = Noval, parent: Value = Noval, path: Value = null): Value = {
    val p = if (path == null) emptyList() else path
    val depth = size(p)
    var out = before match { case Some(f) => f(key, v, parent, p); case None => v }
    val mdv = maxdepth match { case VNum(n) if n >= 0 => n.toInt; case _ => MAXDEPTH }
    if (mdv == 0 || (mdv > 0 && mdv <= depth)) out
    else {
      if (isnode(out)) {
        val prefix = p match { case VList(b) => b.toSeq; case _ => Seq.empty }
        itemsPairs(out).foreach { case (ckey, child) =>
          val childpath = mkList(prefix :+ VStr(ckey))
          val result = walk(child, before, after, VNum(mdv.toDouble), VStr(ckey), out, childpath)
          out match {
            case VMap(m) => m.put(ckey, result)
            case VList(b) => b(ckey.toInt) = result
            case _ =>
          }
        }
      }
      after match { case Some(f) => f(key, out, parent, p); case None => out }
    }
  }

  def merge(objs: Value, maxdepth: Value = Noval): Value = {
    val md = maxdepth match { case VNum(n) => if (n < 0) 0 else n.toInt; case _ => MAXDEPTH }
    if (!islist(objs)) objs
    else {
      val l = objs match { case VList(b) => b; case _ => ArrayBuffer.empty[Value] }
      val lenlist = l.length
      if (lenlist == 0) Noval
      else if (lenlist == 1) l(0)
      else {
        var out = getprop(objs, VNum(0.0), emptyMap())
        for (oi <- 1 until lenlist) {
          val obj = l(oi)
          if (!isnode(obj)) out = obj
          else {
            val cur = ArrayBuffer[Value](out)
            val dst = ArrayBuffer[Value](out)
            def grow(a: ArrayBuffer[Value], n: Int): Unit = while (a.length <= n) a.append(Noval)
            val before: WalkFn = (key, v, _parent, path) => {
              val pi = size(path)
              if (md <= pi) {
                grow(cur, pi); cur(pi) = v
                if (pi > 0) setprop(cur(pi - 1), key, v)
                Noval
              } else if (!isnode(v)) {
                grow(cur, pi); cur(pi) = v; v
              } else {
                grow(dst, pi); grow(cur, pi)
                dst(pi) = if (pi > 0) getprop(dst(pi - 1), key) else dst(pi)
                val tval = dst(pi)
                if ((islist(v) && islist(tval)) || (ismap(v) && ismap(tval))) cur(pi) = tval
                else {
                  // Otherwise the override wins: it is copied, taking nothing
                  // from the destination, so no later merge writes into it.
                  cur(pi) = if (islist(v)) emptyList() else emptyMap()
                  dst(pi) = Noval
                }
                v
              }
            }
            val after: WalkFn = (key, _v, parent, path) => {
              val ci = size(path)
              if (ci < 1) (if (cur.nonEmpty) cur(0) else _v)
              else {
                val target = if (ci - 1 < cur.length) cur(ci - 1) else Noval
                val value = if (ci < cur.length) cur(ci) else Noval
                setprop(target, key, value)
                // walk writes this back into the override, so it is the
                // override's own child, leaving the override unchanged.
                lookup_(parent, key)
              }
            }
            out = walk(obj, Some(before), Some(after))
          }
        }
        if (md == 0) {
          val o = getprop(objs, VNum((lenlist - 1).toDouble))
          out = if (islist(o)) emptyList() else if (ismap(o)) emptyMap() else o
        }
        out
      }
    }
  }

  // ---------------------------------------------------------------------------
  // getpath / setpath
  // ---------------------------------------------------------------------------

  private def iaBase(ia: InjArg): Value = ia match { case IInj(i) => i.base; case IDef(d) => d.dBase; case INone => Noval }
  private def iaDparent(ia: InjArg): Value = ia match { case IInj(i) => i.dparent; case IDef(d) => d.dParent; case INone => Noval }
  private def iaMeta(ia: InjArg): Value = ia match { case IInj(i) => i.meta; case IDef(d) => d.dMeta; case INone => Noval }
  private def iaKey(ia: InjArg): Value = ia match { case IInj(i) => i.key; case IDef(d) => d.dKey; case INone => Noval }
  private def iaDpath(ia: InjArg): Value = ia match { case IInj(i) => i.dpath; case IDef(d) => d.dPath; case INone => Noval }
  private def iaHandler(ia: InjArg): Option[Injector] = ia match { case IInj(i) => Some(i.handler); case IDef(d) => d.dHandler; case INone => None }
  private def iaIsSome(ia: InjArg): Boolean = ia != INone

  private def startsWith(s: String, pre: String): Boolean = s.startsWith(pre)
  private def replaceAll(s: String, find: String, repl: String): String = if (find.isEmpty) s else s.replace(find, repl)

  // R_META_PATH = ^([^$]+)\$([=~])(.+)$
  private def metaPathMatch(s: String): Option[(String, String, String)] = {
    val i = s.indexOf('$')
    if (i > 0 && i + 1 < s.length && (s.charAt(i + 1) == '=' || s.charAt(i + 1) == '~') && i + 2 <= s.length - 1)
      Some((s.substring(0, i), s.charAt(i + 1).toString, s.substring(i + 2)))
    else None
  }

  def getpath(store: Value, path: Value, inj: InjArg = INone): Value = {
    // A new array, so the caller's path is never rewritten. A number part reads
    // as its string; any other non-string part makes the whole path miss.
    val pa: Option[Array[Value]] = path match {
      case VList(b) if b.forall(isKeyType) => Some(b.map(p => VStr(jsString(p))).toArray)
      case VStr(s) => Some(s.split("\\.", -1).map(x => VStr(x)).toArray)
      case VNum(_) => Some(Array(VStr(jsString(path))))
      case _ => None
    }
    pa match {
      case None => Noval
      // A condensed store answers as the node it was built from, touching only
      // the nodes on the path. A base changes what the path resolves against,
      // so that read needs the materialised store.
      case Some(parts) if iscondensed(store) && isNullish(iaBase(inj)) =>
        val found = condenseMaterialise(store, condenseResolve(store, condenseRoot(store), mkList(parts.toSeq)))
        // Group A: a stored null reads as absent, as it does through getprop.
        if (isNullish(found)) Noval else found
      case Some(parts) => getpathParts(if (iscondensed(store)) expand(store) else store, path, parts, inj)
    }
  }

  private def getpathParts(store: Value, path: Value, parts: Array[Value], inj: InjArg): Value = {
    val base = iaBase(inj)
    val dparent = iaDparent(inj)
    val injMeta = iaMeta(inj)
    val injKey = iaKey(inj)
    val dpath = iaDpath(inj)
    val src = if (iskey(base)) getprop(store, base, store) else store
    val numparts = parts.length
    var v: Value = store
    def arrGet(i: Int): Value = if (i >= 0 && i < parts.length) parts(i) else Noval
    if (isNoval(path) || isNoval(store) || (numparts == 1 && parts(0) == VStr(S_MT)) || numparts == 0) {
      v = src
    } else {
      if (numparts == 1) v = getprop(store, parts(0))
      if (!isfunc(v)) {
        v = src
        parts(0) match {
          case VStr(s0) =>
            metaPathMatch(s0) match {
              case Some((g1, _, g3)) if !isNoval(injMeta) && iaIsSome(inj) =>
                v = getprop(injMeta, VStr(g1)); parts(0) = VStr(g3)
              case _ =>
            }
          case _ =>
        }
        var pi = 0
        var continue = true
        while (continue && !isNoval(v) && pi < numparts) {
          val raw = parts(pi)
          val part0: Value = raw match {
            case VStr(s) if iaIsSome(inj) && s == S_DKEY => if (!isNoval(injKey)) injKey else raw
            case VStr(s) if startsWith(s, "$GET:") =>
              VStr(stringify(getpath(src, slice(VStr(s), VNum(5.0), VNum(-1.0)), INone)))
            case VStr(s) if startsWith(s, "$REF:") =>
              VStr(stringify(getpath(getprop(store, VStr(S_DSPEC)), slice(VStr(s), VNum(5.0), VNum(-1.0)), INone)))
            case VStr(s) if iaIsSome(inj) && startsWith(s, "$META:") =>
              VStr(stringify(getpath(injMeta, slice(VStr(s), VNum(6.0), VNum(-1.0)), INone)))
            case _ => raw
          }
          val part: Value = part0 match {
            case VStr(s) => VStr(replaceAll(s, "$$", "$"))
            case _ => VStr(strkey(part0))
          }
          if (part == VStr(S_MT)) {
            var ascends = 0
            while (arrGet(pi + 1) == VStr(S_MT)) { ascends += 1; pi += 1 }
            if (iaIsSome(inj) && ascends > 0) {
              if (pi == numparts - 1) ascends -= 1
              if (ascends == 0) { v = dparent }
              else {
                val tail = parts.slice(pi + 1, numparts).toSeq
                val fullpath = flatten(mkList(Seq(slice(dpath, VNum((-ascends).toDouble)), mkList(tail))))
                v = if (ascends <= size(dpath)) getpath(store, fullpath, INone) else Noval
                continue = false
              }
            } else { v = dparent }
          } else v = getprop(v, part)
          if (continue) pi += 1
        }
      }
    }
    iaHandler(inj) match {
      case Some(h) if iaIsSome(inj) =>
        val refp = pathify(path)
        inj match {
          case IInj(i) => v = h(i, v, refp, store)
          case _ => v = h(dummyInj, v, refp, store)
        }
      case _ =>
    }
    v
  }

  def setpath(store: Value, path: Value, v: Value, inj: InjArg = INone): Value = {
    if (iscondensed(store)) throw StructError(CONDENSE_IMMUTABLE)
    val ptype = typify(path)
    val parts: Value =
      if ((T_list & ptype) > 0) (path match { case VList(b) => mkList(b.toSeq); case _ => emptyList() })
      else if ((T_string & ptype) > 0) (path match { case VStr(s) => mkList(s.split("\\.", -1).map(x => VStr(x)).toSeq); case _ => emptyList() })
      else if ((T_number & ptype) > 0) mkList(Seq(path))
      else Noval
    if (isNoval(parts)) Noval
    else {
      val base = inj match { case INone => Noval; case _ => iaBase(inj) }
      val numparts = size(parts)
      var parent = if (iskey(base)) getprop(store, base, store) else store
      for (pi <- 0 until numparts - 1) {
        val pkey = getelem(parts, VNum(pi.toDouble))
        var np = getprop(parent, pkey)
        if (!isnode(np)) {
          val nextpart = getelem(parts, VNum((pi + 1).toDouble))
          np = if ((T_number & typify(nextpart)) > 0) emptyList() else emptyMap()
          setprop(parent, pkey, np)
        }
        parent = np
      }
      if (isDelete(v)) delprop(parent, getelem(parts, VNum(-1.0)))
      else setprop(parent, getelem(parts, VNum(-1.0)), v)
      parent
    }
  }

  // ---------------------------------------------------------------------------
  // backtick-string helpers
  // ---------------------------------------------------------------------------

  // R_INJECTION_FULL: whole string is one backtick injection -> captured ref.
  private def injectionFull(s: String): Option[String] = {
    val n = s.length
    if (n >= 2 && s.charAt(0) == '`' && s.charAt(n - 1) == '`') {
      val inner = s.substring(1, n - 1)
      if (inner.indexOf('`') >= 0) None
      else {
        val isDollarUpper = inner.length > 1 && inner.charAt(0) == '$' && {
          var j = 1; while (j < inner.length && inner.charAt(j) >= 'A' && inner.charAt(j) <= 'Z') j += 1
          val lettersEnd = j
          lettersEnd > 1 && {
            var k = lettersEnd; while (k < inner.length && inner.charAt(k) >= '0' && inner.charAt(k) <= '9') k += 1
            k == inner.length
          }
        }
        if (isDollarUpper) {
          var j = 1; while (j < inner.length && inner.charAt(j) >= 'A' && inner.charAt(j) <= 'Z') j += 1
          Some(inner.substring(0, j))
        } else Some(inner)
      }
    } else None
  }

  private def injectionPartialReplace(s: String, f: String => String): String = {
    val n = s.length; val b = new StringBuilder; var i = 0
    while (i < n) {
      if (s.charAt(i) == '`') {
        val j = s.indexOf('`', i + 1)
        if (j >= 0) { b.append(f(s.substring(i + 1, j))); i = j + 1 }
        else { b.append(s.charAt(i)); i += 1 }
      } else { b.append(s.charAt(i)); i += 1 }
    }
    b.toString
  }

  private def replaceTransformNames(s: String): String = {
    val n = s.length; val b = new StringBuilder; var i = 0
    while (i < n) {
      if (s.charAt(i) == '`' && i + 1 < n && s.charAt(i + 1) == '$') {
        var j = i + 2; while (j < n && s.charAt(j) >= 'A' && s.charAt(j) <= 'Z') j += 1
        if (j < n && s.charAt(j) == '`' && j > i + 2) {
          b.append(s.substring(i + 2, j).toLowerCase); i = j + 1
        } else { b.append(s.charAt(i)); i += 1 }
      } else { b.append(s.charAt(i)); i += 1 }
    }
    b.toString
  }

  // ---------------------------------------------------------------------------
  // Injection methods
  // ---------------------------------------------------------------------------

  private def newInj(v: Value, parent: Value): Inj = {
    val i = new Inj
    i.mode = M_VAL; i.full = false; i.keyi = 0
    i.keys = mkList(Seq(VStr(S_DTOP))); i.key = VStr(S_DTOP); i.ival = v; i.parent = parent
    i.path = mkList(Seq(VStr(S_DTOP))); i.nodes = mkList(Seq(parent)); i.handler = injectHandler
    i.errs = emptyList(); i.meta = emptyMap(); i.dparent = Noval; i.dpath = mkList(Seq(VStr(S_DTOP)))
    i.base = VStr(S_DTOP); i.modify = None; i.prior = None; i.extra = Noval
    i
  }

  private def injDescend(inj: Inj): Value = {
    inj.meta match {
      case VMap(m) =>
        val d = m.get("__d") match { case Some(VNum(n)) => n; case _ => 0.0 }
        m.put("__d", VNum(d + 1.0))
      case _ =>
    }
    val parentkey = getelem(inj.path, VNum(-2.0))
    if (isNoval(inj.dparent)) {
      if (size(inj.dpath) > 1) inj.dpath = inj.dpath match { case VList(b) => mkList(b.toSeq :+ parentkey); case _ => inj.dpath }
    } else if (!isNoval(parentkey)) {
      inj.dparent = getprop(inj.dparent, parentkey)
      val lastpart = getelem(inj.dpath, VNum(-1.0))
      if (lastpart == VStr("$:" + jsString(parentkey))) inj.dpath = slice(inj.dpath, VNum(-1.0))
      else inj.dpath = inj.dpath match { case VList(b) => mkList(b.toSeq :+ parentkey); case _ => inj.dpath }
    }
    inj.dparent
  }

  private def injChild(inj: Inj, keyi: Int, keys: Value): Inj = {
    val key = strkey(getelem(keys, VNum(keyi.toDouble)))
    val v = inj.ival
    val c = new Inj
    c.mode = inj.mode; c.full = inj.full; c.keyi = keyi; c.keys = keys; c.key = VStr(key)
    c.ival = getprop(v, VStr(key)); c.parent = v
    c.path = inj.path match { case VList(b) => mkList(b.toSeq :+ VStr(key)); case _ => mkList(Seq(VStr(key))) }
    c.nodes = inj.nodes match { case VList(b) => mkList(b.toSeq :+ v); case _ => mkList(Seq(v)) }
    c.handler = inj.handler; c.errs = inj.errs; c.meta = inj.meta; c.base = inj.base
    c.modify = inj.modify; c.prior = Some(inj)
    c.dpath = inj.dpath match { case VList(b) => mkList(b.toSeq); case _ => inj.dpath }
    c.dparent = inj.dparent; c.extra = inj.extra
    c
  }

  private def injSetval(inj: Inj, v: Value, ancestor: Int = 1): Value = {
    val (target, key) =
      if (ancestor < 2) (inj.parent, inj.key)
      else (getelem(inj.nodes, VNum((-ancestor).toDouble)), getelem(inj.path, VNum((-ancestor).toDouble)))
    if (isNoval(v)) delprop(target, key) else setprop(target, key, v)
  }

  // ---------------------------------------------------------------------------
  // inject
  // ---------------------------------------------------------------------------

  def inject(v: Value, store: Value, inj: InjArg = INone): Value = {
    val state: Inj = inj match {
      case IInj(i) => i
      case _ =>
        val parent = mkMap(Seq((S_DTOP, v)))
        val i = newInj(v, parent)
        i.dparent = store
        i.errs = getprop(store, VStr(S_DERRS), emptyList())
        i.meta match { case VMap(m) => m.put("__d", VNum(0.0)); case _ => }
        inj match {
          case IDef(d) =>
            d.dModify match { case Some(_) => i.modify = d.dModify; case None => }
            if (!isNoval(d.dExtra)) i.extra = d.dExtra
            if (!isNoval(d.dMeta)) i.meta = d.dMeta
            d.dHandler match { case Some(h) => i.handler = h; case None => }
          case _ =>
        }
        i
    }
    injDescend(state)

    val rv: Value =
      if (isnode(v)) {
        var nodekeys: Seq[String] = v match {
          case VMap(m) =>
            val ks = m.keysIterator.toSeq
            val normal = ks.filter(k => k.indexOf('$') < 0).sorted
            val trans = ks.filter(k => k.indexOf('$') >= 0).sorted
            normal ++ trans
          case VList(b) => b.indices.map(_.toString)
          case _ => Seq.empty
        }
        var nki = 0
        while (nki < nodekeys.length) {
          val childinj = injChild(state, nki, mkList(nodekeys.map(s => VStr(s))))
          val nodekey = childinj.key
          childinj.mode = M_KEYPRE
          val prekey = injectstr(jsString(nodekey), store, Some(childinj))
          nodekeys = (childinj.keys match { case VList(b) => b.toSeq; case _ => Seq.empty }).map(jsString)
          if (!isNoval(prekey)) {
            childinj.ival = getprop(v, prekey)
            childinj.mode = M_VAL
            inject(childinj.ival, store, IInj(childinj))
            nodekeys = (childinj.keys match { case VList(b) => b.toSeq; case _ => Seq.empty }).map(jsString)
            childinj.mode = M_KEYPOST
            injectstr(jsString(nodekey), store, Some(childinj))
            nodekeys = (childinj.keys match { case VList(b) => b.toSeq; case _ => Seq.empty }).map(jsString)
          }
          nki = childinj.keyi + 1
        }
        v
      } else v match {
        case VStr(_) =>
          state.mode = M_VAL
          val nv = injectstr(jsString(v), store, Some(state))
          if (!isSkip(nv)) injSetval(state, nv)
          nv
        case _ => v
      }

    state.modify match {
      case Some(f) if !isSkip(rv) =>
        val mkey = state.key; val mparent = state.parent; val mval = getprop(mparent, mkey)
        f(mval, mkey, mparent, state)
      case _ =>
    }
    state.ival = rv
    lookup_(state.parent, VStr(S_DTOP))
  }

  private def injectHandler(inj: Inj, v: Value, refstr: String, store: Value): Value = {
    val iscmd = isfunc(v) && (refstr == "" || startsWith(refstr, S_DS))
    if (iscmd) v match { case VFunc(f) => f(inj, v, refstr, store); case _ => v }
    else if (inj.mode == M_VAL && inj.full) { injSetval(inj, v); v }
    else v
  }

  private def injectstr(v: String, store: Value, injOpt: Option[Inj]): Value = {
    if (v == S_MT) VStr(S_MT)
    else injectionFull(v) match {
      case Some(pathref0) =>
        injOpt.foreach(_.full = true)
        val pathref = if (pathref0.length > 3) replaceAll(replaceAll(pathref0, "$BT", S_BT), "$DS", S_DS) else pathref0
        val ia = injOpt match { case Some(i) => IInj(i); case None => INone }
        getpath(store, VStr(pathref), ia)
      case None =>
        val out = injectionPartialReplace(v, ref0 => {
          val refp = if (ref0.length > 3) replaceAll(replaceAll(ref0, "$BT", S_BT), "$DS", S_DS) else ref0
          injOpt.foreach(_.full = false)
          val ia = injOpt match { case Some(i) => IInj(i); case None => INone }
          getpath(store, VStr(refp), ia) match {
            case Noval => S_MT
            case VStr(s) => if (s == "__NULL__") "null" else s
            case VFunc(_) => S_MT
            case found => try jsonEncode(found) catch { case _: Throwable => stringify(found) }
          }
        })
        injOpt match {
          case Some(i) => i.full = true; i.handler(i, VStr(out), v, store)
          case None => VStr(out)
        }
    }
  }

  // ---------------------------------------------------------------------------
  // transform commands
  // ---------------------------------------------------------------------------

  private val transformDelete: Injector = (inj, _v, _r, _s) => { delprop(inj.parent, inj.key); Noval }

  private val transformCopy: Injector = (inj, _v, _r, _s) => {
    if (inj.mode == M_KEYPRE || inj.mode == M_KEYPOST) inj.key
    else { val out = lookup_(inj.dparent, inj.key); injSetval(inj, out); out }
  }

  private val transformKey: Injector = (inj, _v, _r, _s) => {
    if (inj.mode != M_VAL) Noval
    else {
      val keyspec = lookup_(inj.parent, VStr(S_BKEY))
      if (!isNoval(keyspec)) { delprop(inj.parent, VStr(S_BKEY)); getprop(inj.dparent, keyspec) }
      else {
        val anno = lookup_(inj.parent, VStr(S_BANNO))
        val fromanno = lookup_(anno, VStr(S_KEY))
        if (!isNoval(fromanno)) fromanno else getelem(inj.path, VNum(-2.0))
      }
    }
  }

  private val transformAnno: Injector = (inj, _v, _r, _s) => { delprop(inj.parent, VStr(S_BANNO)); Noval }

  private val transformMerge: Injector = (inj, _v, _r, _s) => {
    if (inj.mode == M_KEYPRE) inj.key
    else if (inj.mode == M_KEYPOST) {
      val args0 = getprop(inj.parent, inj.key)
      val args = if (islist(args0)) args0 else mkList(Seq(args0))
      injSetval(inj, Noval)
      val mergelist = flatten(mkList(Seq(mkList(Seq(inj.parent)), args, mkList(Seq(clone(inj.parent))))))
      merge(mergelist)
      inj.key
    } else Noval
  }

  private val transformEach: Injector = (inj, _v, _r, store) => {
    if (islist(inj.keys)) slice(inj.keys, VNum(0.0), VNum(1.0), mutate = true)
    if (inj.mode != M_VAL) Noval
    else {
      val parent = inj.parent
      val srcpath = if (size(parent) > 1) getelem(parent, VNum(1.0)) else Noval
      val childTm = if (size(parent) > 2) clone(getelem(parent, VNum(2.0))) else Noval
      val srcstore = getprop(store, inj.base, store)
      val src = getpath(srcstore, srcpath, IInj(inj))
      val tkey = getelem(inj.path, VNum(-2.0))
      val nodes = inj.nodes
      val target = { val t = getelem(nodes, VNum(-2.0)); if (isNullish(t)) getelem(nodes, VNum(-1.0)) else t }
      val tval = ArrayBuffer.empty[Value]
      var rval: Value = emptyList()
      if (isnode(src)) {
        src match {
          case VList(b) => b.foreach(_ => tval.append(clone(childTm)))
          case VMap(m) => m.foreach { case (k, _) =>
            val cc = clone(childTm)
            if (ismap(cc)) setprop(cc, VStr(S_BANNO), mkMap(Seq((S_KEY, VStr(k)))))
            tval.append(cc)
          }
          case _ =>
        }
        val tvalv = VList(tval)
        val tcurrent = src match { case VMap(m) => mkList(m.valuesIterator.toSeq); case VList(b) => mkList(b.toSeq); case _ => src }
        if (tval.nonEmpty) {
          val path = inj.path
          val ckey = getelem(path, VNum(-2.0))
          val plist = path match { case VList(b) => b.toSeq; case _ => Seq.empty }
          val tpath = mkList(if (plist.isEmpty) Seq.empty else plist.take(plist.length - 1))
          val dpath = ArrayBuffer[Value](VStr(S_DTOP))
          srcpath match { case VStr(sp) if sp != S_MT => sp.split("\\.", -1).foreach(p => if (p != S_MT) dpath.append(VStr(p))); case _ => }
          if (!isNoval(ckey)) dpath.append(VStr("$:" + jsString(ckey)))
          var tcur: Value = mkMap(Seq((jsString(ckey), tcurrent)))
          if (size(tpath) > 1) {
            val pkey = getelem(path, VNum(-3.0), VStr(S_DTOP))
            dpath.append(VStr("$:" + jsString(pkey)))
            tcur = mkMap(Seq((jsString(pkey), tcur)))
          }
          val tinj = injChild(inj, 0, if (!isNoval(ckey)) mkList(Seq(ckey)) else emptyList())
          tinj.path = tpath
          val nlist = nodes match { case VList(b) => b.toSeq; case _ => Seq.empty }
          tinj.nodes = mkList(if (nlist.isEmpty) Seq.empty else nlist.take(nlist.length - 1))
          tinj.parent = if (size(tinj.nodes) > 0) getelem(tinj.nodes, VNum(-1.0)) else Noval
          if (!isNoval(ckey) && !isNoval(tinj.parent)) setprop(tinj.parent, ckey, tvalv)
          tinj.ival = tvalv
          tinj.dpath = VList(dpath)
          tinj.dparent = tcur
          inject(tvalv, store, IInj(tinj))
          rval = tinj.ival
        }
      }
      setprop(target, tkey, rval)
      if (islist(rval) && size(rval) > 0) getelem(rval, VNum(0.0)) else Noval
    }
  }

  private val transformPack: Injector = (inj, _v, _r, store) => {
    if (inj.mode != M_KEYPRE || !(inj.key match { case VStr(_) => true; case _ => false })) Noval
    else {
      val parent = inj.parent; val path = inj.path; val nodes = inj.nodes
      val argsVal = getprop(parent, inj.key)
      if (!islist(argsVal) || size(argsVal) < 2) Noval
      else {
        val srcpath = getelem(argsVal, VNum(0.0))
        val origchildspec = getelem(argsVal, VNum(1.0))
        val tkey = getelem(path, VNum(-2.0))
        val pathsize = size(path)
        val target = { val t = getelem(nodes, VNum((pathsize - 2).toDouble)); if (isNullish(t)) getelem(nodes, VNum((pathsize - 1).toDouble)) else t }
        val srcstore = getprop(store, inj.base, store)
        val src0 = getpath(srcstore, srcpath, IInj(inj))
        val src =
          if (!islist(src0)) {
            if (ismap(src0)) mkList(itemsPairs(src0).map { case (k, node) =>
              setprop(node, VStr(S_BANNO), mkMap(Seq((S_KEY, VStr(k))))); node
            })
            else Noval
          } else src0
        if (isNoval(src)) Noval
        else {
          val keypath = getprop(origchildspec, VStr(S_BKEY))
          val childspec = delprop(origchildspec, VStr(S_BKEY))
          val child = getprop(childspec, VStr(S_BVAL), childspec)
          val tval = emptyMap()
          itemsPairs(src).foreach { case (srckey, srcnode) =>
            val k =
              if (isNoval(keypath)) VStr(srckey)
              else keypath match {
                case VStr(kp) if startsWith(kp, S_BT) =>
                  inject(VStr(kp), merge(mkList(Seq(emptyMap(), store, mkMap(Seq((S_DTOP, srcnode))))), VNum(1.0)))
                case _ => getpath(srcnode, keypath, IInj(inj))
              }
            val tchild = clone(child)
            setprop(tval, k, tchild)
            val anno = getprop(srcnode, VStr(S_BANNO))
            if (isNoval(anno)) delprop(tchild, VStr(S_BANNO)) else setprop(tchild, VStr(S_BANNO), anno)
          }
          var rval: Value = emptyMap()
          if (!isempty(tval)) {
            val tsrc = emptyMap()
            val srcSeq = src match { case VList(b) => b.toSeq; case _ => Seq.empty }
            srcSeq.zipWithIndex.foreach { case (node, i) =>
              val kn =
                if (isNoval(keypath)) vint(i)
                else keypath match {
                  case VStr(kp) if startsWith(kp, S_BT) =>
                    inject(VStr(kp), merge(mkList(Seq(emptyMap(), store, mkMap(Seq((S_DTOP, node))))), VNum(1.0)))
                  case _ => getpath(node, keypath, IInj(inj))
                }
              setprop(tsrc, kn, node)
            }
            val tpath = slice(inj.path, VNum(-1.0))
            val ckey = getelem(inj.path, VNum(-2.0))
            val dpath = ArrayBuffer[Value](VStr(S_DTOP))
            srcpath match { case VStr(sp) => sp.split("\\.", -1).foreach(p => if (p != S_MT) dpath.append(VStr(p))); case _ => }
            dpath.append(VStr("$:" + jsString(ckey)))
            var tcur: Value = mkMap(Seq((jsString(ckey), tsrc)))
            if (size(tpath) > 1) {
              val pkey = getelem(inj.path, VNum(-3.0), VStr(S_DTOP))
              dpath.append(VStr("$:" + jsString(pkey)))
              tcur = mkMap(Seq((jsString(pkey), tcur)))
            }
            val tinj = injChild(inj, 0, mkList(Seq(ckey)))
            tinj.path = tpath
            tinj.nodes = slice(inj.nodes, VNum(-1.0))
            tinj.parent = getelem(tinj.nodes, VNum(-1.0))
            tinj.ival = tval
            tinj.dpath = VList(dpath)
            tinj.dparent = tcur
            inject(tval, store, IInj(tinj))
            rval = tinj.ival
          }
          setprop(target, tkey, rval)
          Noval
        }
      }
    }
  }

  private val transformRef: Injector = (inj, v, _r, store) => {
    if (inj.mode != M_VAL) Noval
    else {
      val nodes = inj.nodes
      val refpath = lookup_(inj.parent, VNum(1.0))
      inj.keyi = size(inj.keys)
      getprop(store, VStr(S_DSPEC)) match {
        case VFunc(f) =>
          val spec = f(inj, Noval, "", Noval)
          val refv = getpath(spec, refpath, INone)
          var hasSub = false
          if (isnode(refv)) walk(refv, before = Some((_k, v2, _p, _path) => { if (v2 == VStr("`$REF`")) hasSub = true; v2 }))
          val tref = clone(refv)
          val cpath = slice(inj.path, VNum(0.0), VNum((size(inj.path) - 3).toDouble))
          val tpath = slice(inj.path, VNum(0.0), VNum((size(inj.path) - 1).toDouble))
          val tcur = getpath(store, cpath, INone)
          val tval = getpath(store, tpath, INone)
          var rval: Value = Noval
          if (!isNoval(refv) && (!hasSub || !isNoval(tval))) {
            val cs = injChild(inj, 0, mkList(Seq(getelem(tpath, VNum(-1.0)))))
            cs.path = tpath
            cs.nodes = slice(inj.nodes, VNum(0.0), VNum((size(inj.nodes) - 1).toDouble))
            cs.parent = getelem(nodes, VNum(-2.0))
            cs.ival = tref
            cs.dparent = tcur
            inject(tref, store, IInj(cs))
            rval = cs.ival
          }
          injSetval(inj, rval, 2)
          inj.prior match {
            case Some(p) if islist(inj.parent) => p.keyi = p.keyi - 1
            case _ =>
          }
          v
        case _ => Noval
      }
    }
  }

  private def jsstr(v: Value): String = v match {
    case VNull => "null"; case VBool(b) => if (b) "true" else "false"; case _ => jsString(v)
  }

  private val formatterTbl: Seq[(String, (Value, Value) => Value)] = Seq(
    "identity" -> ((_k, v) => v),
    "upper" -> ((_k, v) => if (isnode(v)) v else VStr(jsstr(v).toUpperCase)),
    "lower" -> ((_k, v) => if (isnode(v)) v else VStr(jsstr(v).toLowerCase)),
    "string" -> ((_k, v) => if (isnode(v)) v else VStr(jsstr(v))),
    "number" -> ((_k, v) => if (isnode(v)) v else { val n = try jsstr(v).toDouble catch { case _: Throwable => 0.0 }; VNum(if (n.isNaN) 0.0 else n) }),
    "integer" -> ((_k, v) => if (isnode(v)) v else { val n = try jsstr(v).toDouble catch { case _: Throwable => 0.0 }; VNum((if (n.isNaN) 0.0 else n).toInt.toDouble) }),
    "concat" -> ((k, v) => if (isNoval(k) && islist(v)) VStr(join(itemsV(v, { case (_, x) => if (isnode(x)) VStr(S_MT) else VStr(jsstr(x)) }), VStr(S_MT))) else v)
  )

  def checkPlacement(modes: Int, ijname: String, parentTypes: Int, inj: Inj): Boolean = {
    val modenum = inj.mode
    if ((modes & modenum) == 0) {
      val allowed = Seq(M_KEYPRE, M_KEYPOST, M_VAL).filter(m => (modes & m) != 0)
      val placements = allowed.map(m => if (m == M_VAL) "value" else "key").mkString(",")
      val cur = if (modenum == M_VAL) "value" else "key"
      setprop(inj.errs, VNum(size(inj.errs).toDouble), VStr(s"$$$ijname: invalid placement as $cur, expected: $placements."))
      false
    } else if (!isempty(VNum(parentTypes.toDouble))) {
      val ptype = typify(inj.parent)
      if ((parentTypes & ptype) == 0) {
        setprop(inj.errs, VNum(size(inj.errs).toDouble), VStr(s"$$$ijname: invalid placement in parent ${typename(ptype)}, expected: ${typename(parentTypes)}."))
        false
      } else true
    } else true
  }

  def injectorArgs(argTypes: Seq[Int], args: Value): Value = {
    val numargs = argTypes.length
    val found = ArrayBuffer.fill[Value](1 + numargs)(Noval)
    var stop = false
    var argi = 0
    while (argi < numargs && !stop) {
      val arg = getelem(args, VNum(argi.toDouble))
      val argType = typify(arg)
      if ((argTypes(argi) & argType) == 0) {
        found(0) = VStr(s"invalid argument: ${stringify(arg, VNum(22.0))} (${typename(argType)} at position ${1 + argi}) is not of type: ${typename(argTypes(argi))}.")
        stop = true
      } else { found(1 + argi) = arg; argi += 1 }
    }
    VList(found)
  }

  def injectChild(child: Value, store: Value, inj: Inj): Inj = {
    var cinj = inj
    inj.prior match {
      case Some(prior) =>
        prior.prior match {
          case Some(pprior) =>
            val c = injChild(pprior, prior.keyi, prior.keys); c.ival = child
            setprop(c.parent, prior.key, child); cinj = c
          case None =>
            val c = injChild(prior, inj.keyi, inj.keys); c.ival = child
            setprop(c.parent, inj.key, child); cinj = c
        }
      case None =>
    }
    inject(child, store, IInj(cinj))
    cinj
  }

  private val transformFormat: Injector = (inj, _v, _r, store) => {
    slice(inj.keys, VNum(0.0), VNum(1.0), mutate = true)
    if (inj.mode != M_VAL) Noval
    else {
      val name = lookup_(inj.parent, VNum(1.0))
      val child = lookup_(inj.parent, VNum(2.0))
      val tkey = getelem(inj.path, VNum(-2.0))
      val target = { val t = getelem(inj.nodes, VNum(-2.0)); if (isNullish(t)) getelem(inj.nodes, VNum(-1.0)) else t }
      val cinj = injectChild(child, store, inj)
      val resolved = cinj.ival
      val formatter: Option[(Value, Value) => Value] =
        if ((T_function & typify(name)) > 0) Some((k, v) => name match { case VFunc(f) => f(dummyInj, v, jsString(k), Noval); case _ => v })
        else formatterTbl.find(_._1 == jsString(name)).map(_._2)
      formatter match {
        case None => setprop(inj.errs, VNum(size(inj.errs).toDouble), VStr(s"$$FORMAT: unknown format: ${jsString(name)}.")); Noval
        case Some(f) =>
          val out = walk(resolved, before = Some((k, v, _p, _path) => f(k, v)))
          setprop(target, tkey, out); out
      }
    }
  }

  private val transformApply: Injector = (inj, _v, _r, store) => {
    if (!checkPlacement(M_VAL, "APPLY", T_list, inj)) Noval
    else {
      val res = injectorArgs(Seq(T_function, T_any), slice(inj.parent, VNum(1.0)))
      val err = getelem(res, VNum(0.0))
      val applyFn = getelem(res, VNum(1.0))
      val child = if (size(res) > 2) getelem(res, VNum(2.0)) else Noval
      if (!isNoval(err)) { setprop(inj.errs, VNum(size(inj.errs).toDouble), VStr("$APPLY: " + jsString(err))); Noval }
      else {
        val tkey = getelem(inj.path, VNum(-2.0))
        val target = { val t = getelem(inj.nodes, VNum(-2.0)); if (isNullish(t)) getelem(inj.nodes, VNum(-1.0)) else t }
        val cinj = injectChild(child, store, inj)
        val resolved = cinj.ival
        val out = applyFn match { case VFunc(f) => f(cinj, resolved, "", store); case _ => Noval }
        setprop(target, tkey, out); out
      }
    }
  }

  def transform(data: Value, spec0: Value, inj: InjArg = INone): Value = {
    val origspec = spec0
    val spec = clone(spec0)
    val extra = inj match { case IDef(d) => d.dExtra; case _ => Noval }
    val collect = inj match { case IDef(d) => !isNoval(d.dErrs); case _ => false }
    val errs = inj match { case IDef(d) if collect => d.dErrs; case _ => emptyList() }
    val extraTransforms = emptyMap()
    val extraData = emptyMap()
    if (!isNoval(extra)) itemsPairs(extra).foreach { case (k, v) =>
      if (startsWith(k, S_DS)) setprop(extraTransforms, VStr(k), v) else setprop(extraData, VStr(k), v)
    }
    val dataClone = merge(mkList(Seq(if (isempty(extraData)) Noval else clone(extraData), clone(data))))
    val store = emptyMap()
    def put(k: String, v: Value): Unit = setprop(store, VStr(k), v)
    put(S_DTOP, dataClone)
    put(S_DSPEC, VFunc((_, _, _, _) => origspec))
    put("$BT", VFunc((_, _, _, _) => VStr(S_BT)))
    put("$DS", VFunc((_, _, _, _) => VStr(S_DS)))
    put("$WHEN", VFunc((_, _, _, _) => VStr("1970-01-01T00:00:00.000Z")))
    put("$DELETE", VFunc(transformDelete))
    put("$COPY", VFunc(transformCopy))
    put("$KEY", VFunc(transformKey))
    put("$ANNO", VFunc(transformAnno))
    put("$MERGE", VFunc(transformMerge))
    put("$EACH", VFunc(transformEach))
    put("$PACK", VFunc(transformPack))
    put("$REF", VFunc(transformRef))
    put("$FORMAT", VFunc(transformFormat))
    put("$APPLY", VFunc(transformApply))
    itemsPairs(extraTransforms).foreach { case (k, v) => put(k, v) }
    put(S_DERRS, errs)
    val idef = new InjDef
    idef.dErrs = errs
    inj match {
      case IDef(d) => idef.dMeta = d.dMeta; idef.dModify = d.dModify; idef.dHandler = d.dHandler; idef.dBase = d.dBase
      case _ =>
    }
    val out = inject(spec, store, IDef(idef))
    if (size(errs) > 0 && !collect) throw StructError(join(errs, VStr(" | ")))
    out
  }

  // ---------------------------------------------------------------------------
  // validate
  // ---------------------------------------------------------------------------

  private def invalidTypeMsg(path: Value, needtype: String, vt: Int, v: Value, whence: String): String = {
    val vs = if (isNullish(v)) "no value" else stringify(v)
    "Expected " +
      (if (size(path) > 1) "field " + pathify(path, VNum(1.0)) + " to be " else "") +
      needtype + ", but found " +
      (if (!isNullish(v)) typename(vt) + S_VIZ else "") + vs + "."
  }

  private def pushErr(inj: Inj, msg: String): Unit = setprop(inj.errs, VNum(size(inj.errs).toDouble), VStr(msg))

  private val validateString: Injector = (inj, _v, _r, _s) => {
    val out = lookup_(inj.dparent, inj.key)
    val t = typify(out)
    if ((T_string & t) == 0) { pushErr(inj, invalidTypeMsg(inj.path, S_string, t, out, "V1010")); Noval }
    else if (out == VStr(S_MT)) { pushErr(inj, "Empty string at " + pathify(inj.path, VNum(1.0))); Noval }
    else out
  }

  private val validateType: Injector = (inj, _v, refstr, _s) => {
    val tname = if (refstr.length > 1) refstr.substring(1).toLowerCase else "any"
    val idx = TYPENAME.indexOf(tname)
    val typev0 = if (idx >= 0) 1 << (31 - idx) else 0
    val typev = if (tname == S_nil) typev0 | T_null else typev0
    val out = lookup_(inj.dparent, inj.key)
    val t = typify(out)
    if ((t & typev) == 0) { pushErr(inj, invalidTypeMsg(inj.path, tname, t, out, "V1001")); Noval }
    else out
  }

  private val validateAny: Injector = (inj, _v, _r, _s) => lookup_(inj.dparent, inj.key)

  private val validateChild: Injector = (inj, _v, _r, _s) => {
    val parent = inj.parent; val key = inj.key; val path = inj.path; val keys = inj.keys
    if (inj.mode == M_KEYPRE) {
      val childtm = getprop(parent, key)
      val pkey = getelem(path, VNum(-2.0))
      val tval = getprop(inj.dparent, pkey)
      if (isNoval(tval)) {
        keysof(emptyMap()).foreach { ckey => setprop(parent, VStr(ckey), clone(childtm)); setprop(keys, VNum(size(keys).toDouble), VStr(ckey)) }
        delprop(parent, key); Noval
      } else if (!ismap(tval)) {
        // _validation reports the mismatch, once.
        Noval
      } else {
        keysof(tval).foreach { ckey => setprop(parent, VStr(ckey), clone(childtm)); setprop(keys, VNum(size(keys).toDouble), VStr(ckey)) }
        delprop(parent, key); Noval
      }
    } else if (inj.mode == M_VAL) {
      val childtm = getprop(parent, VNum(1.0))
      if (!islist(parent)) { pushErr(inj, "Invalid $CHILD as value"); Noval }
      else if (isNoval(inj.dparent)) { parent match { case VList(b) => b.clear(); case _ => }; Noval }
      else if (!islist(inj.dparent)) {
        inj.keyi = size(parent); inj.dparent
      } else {
        // Clone children and reset inj key index.
        // The inject child loop will now iterate over the cloned children,
        // validating them against the current list values.
        itemsPairs(inj.dparent).foreach { case (k, _) => setprop(parent, VStr(k), clone(childtm)) }
        parent match { case VList(b) => val n = size(inj.dparent); if (b.length > n) b.remove(n, b.length - n); case _ => }

        // NOTE: modifying inj! This extends the child value loop in inject
        // to cover every cloned child.
        for (ckeyi <- size(keys) until size(parent))
          setprop(keys, VNum(size(keys).toDouble), VStr(strkey(VNum(ckeyi.toDouble))))

        // Restart the child value loop at the first element (the loop
        // increments keyi on resume) so that the first element is also
        // validated against the child template.
        inj.keyi = -1

        // SKIP leaves the cloned child template in place at the first
        // element so the resumed loop can validate it.
        SKIP
      }
    } else Noval
  }

  // Lowers every `$NAME` marker in the joined description, nested ones included.
  private def describeAlternatives(tvals: Value): String =
    replaceTransformNames(join(itemsV(tvals, { case (_, x) => VStr(stringify(x)) }), VStr(", ")))

  private val validateExact: Injector = (inj, _v, _r, _s) => {
    if (inj.mode == M_VAL) {
      val parent = inj.parent
      if (!islist(parent) || inj.keyi != 0) { pushErr(inj, "The $EXACT validator at field " + pathify(inj.path, VNum(1.0), VNum(1.0)) + " must be the first element of an array."); Noval }
      else {
        val cval = slotval(inj)
        inj.keyi = size(inj.keys)
        // Replace [$EXACT, ...] with the data value; SKIP keeps inject off the detached list.
        injSetval(inj, cval, 2)
        inj.path = slice(inj.path, VNum(0.0), VNum((size(inj.path) - 1).toDouble))
        val tvals = slice(parent, VNum(1.0))
        if (size(tvals) == 0) pushErr(inj, "The $EXACT validator at field " + pathify(inj.path, VNum(1.0), VNum(1.0)) + " must have at least one argument.")
        else if (!listItems(tvals).exists(tval => deepequal(tval, cval))) {
          val valdesc = describeAlternatives(tvals)
          pushErr(inj, invalidTypeMsg(inj.path, (if (size(inj.path) > 1) "" else "value ") + "exactly equal to " + (if (size(tvals) == 1) "" else "one of ") + valdesc, typify(cval), cval, "V0110"))
        }
        SKIP
      }
    } else { delprop(inj.parent, inj.key); Noval }
  }

  // Count the specs that admit the value: ['`$NOF`', count, spec, ...], where
  // count is an integer, or a map holding min, max or both.
  private val validateNof: Injector = (inj, _v, _r, store) => validatecount(inj, store, "$NOF", true)

  // Every spec admits the value: ['`$ALL`', spec, ...].
  private val validateAll: Injector = (inj, _v, _r, store) => validatecount(inj, store, "$ALL", false)

  private def listItems(v: Value): Seq[Value] = v match { case VList(b) => b.toSeq; case _ => Seq.empty }

  // The counting list directives. Without a count, every spec has to admit.
  private def validatecount(inj: Inj, store: Value, name: String, counted: Boolean): Value = {
    val parent = inj.parent
    if (inj.mode != M_VAL) Noval
    else if (!islist(parent) || inj.keyi != 0) {
      pushErr(inj, "The " + name + " validator at field " + pathify(inj.path, VNum(1.0), VNum(1.0)) + " must be the first element of an array.")
      Noval
    } else {
      val cval = slotval(inj)
      inj.keyi = size(inj.keys)

      // Replace the directive's list with the data value. Each return is SKIP, so
      // that inject leaves the detached list alone and validates nothing in it.
      injSetval(inj, cval, 2)

      inj.path = slice(inj.path, VNum(-1.0))

      val count = if (counted) lookup_(parent, VNum(1.0)) else Noval
      val tvals = listItems(slice(parent, VNum(if (counted) 2.0 else 1.0)))
      val numtvals = tvals.length
      val field = "The " + name + " validator at field " + pathify(inj.path, VNum(1.0))

      if (numtvals == 0) pushErr(inj, field + (if (counted) " must have a count and" else " must have") + " at least one argument.")
      else {
        val (lo, hi, countdesc) = if (counted) nofcount(count, numtvals) else (numtvals.toDouble, numtvals.toDouble, Some("all"))
        countdesc match {
          case None => pushErr(inj, field + " has an invalid count: " + stringify(count) + ".")
          case Some(words) =>
            var admitted = 0
            var tI = 0

            // Stop once the specs left cannot change the verdict.
            def decided: Boolean = {
              val left = numtvals - tI
              hi < admitted || admitted + left < lo || (lo <= admitted && admitted + left <= hi)
            }

            while (tI < numtvals && !decided) {
              if (admits(cval, tvals(tI), inj, store)) admitted += 1
              tI += 1
            }

            if (admitted < lo || hi < admitted) {
              val valdesc = describeAlternatives(mkList(tvals))
              pushErr(inj, invalidTypeMsg(inj.path, words + " of " + valdesc, typify(cval), cval, "V0310"))
            }
        }
      }
      SKIP
    }
  }

  // Names a validate spec may use besides its checkers: transform's that it keeps, and $OPEN.
  private val VALIDATE_NAMES = Seq("$TOP", "$SPEC", "$BT", "$DS", "$WHEN", "$ANNO", "$REF", "$FORMAT", "$APPLY", "$OPEN")

  // Report each checker the spec names that validate lacks; $EXACT's arguments are literals.
  private def checknames(spec: Value, store: Value, path: Seq[Value], errs: Value): Unit =
    refname(spec) match {
      case Some(name) =>
        if (unknownname(name, store))
          setprop(errs, VNum(size(errs).toDouble), VStr("Unknown validator " + name + " at field " + pathify(mkList(path)) + "."))
      case None =>
        if (!(islist(spec) && refname(lookup_(spec, VNum(0.0))).contains("$EXACT")))
          keysof(spec).foreach { key =>
            if (ismap(spec)) checknames(VStr(key), store, path, errs)
            checknames(lookup_(spec, VStr(key)), store, path :+ VStr(key), errs)
          }
    }

  // R_CHECKER_NAME = ^\$[A-Z]+$
  private def checkerName(s: String): Boolean =
    s.length > 1 && s.charAt(0) == '$' && s.substring(1).forall(c => c >= 'A' && c <= 'Z')

  // The name a whole-string reference gives, when it is a checker name in any case.
  private def refname(v: Value): Option[String] = v match {
    case VStr(s) => injectionFull(s).filter(n => checkerName(n.toUpperCase(java.util.Locale.ROOT)))
    case _ => None
  }

  // Unknown: undefined and upper case, or a defined name in another case. Null disables a name.
  private def unknownname(name: String, store: Value): Boolean = {
    def known(n: String): Boolean = VALIDATE_NAMES.contains(n) || !isNullish(lookup_(store, VStr(n)))
    val upper = name.toUpperCase(java.util.Locale.ROOT)
    !known(name) && (upper == name || known(upper))
  }

  // The data value at a list directive's slot. The directive's own dparent was
  // read with getprop, which reports a stored null as absent.
  private def slotval(inj: Inj): Value = inj.prior match {
    case Some(prior) => lookup_(prior.dparent, prior.key)
    case None => inj.dparent
  }

  // JSON equality: numbers by value, lists in order, maps by key in any order.
  private def deepequal(a: Value, b: Value): Boolean =
    a == b || {
      val atype = typify(a)
      atype == typify(b) && 0 != ((T_list | T_map) & atype) && {
        val akeys = keysof(a)
        val bkeys = keysof(b)
        akeys.length == bkeys.length && akeys.indices.forall { kI =>
          val k = akeys(kI)
          k == bkeys(kI) && deepequal(lookup_(a, VStr(k)), lookup_(b, VStr(k)))
        }
      }
    }

  // Every member `v` has is in `out`, unchanged. A member only `out` has is a
  // default the spec supplied, and is ignored.
  private def keeps(v: Value, out: Value): Boolean =
    if (isNoval(v)) true
    else if (0 == ((T_list | T_map) & typify(v)) || islist(v) != islist(out) || !isnode(out)) deepequal(v, out)
    else keysof(v).forall(k => keeps(lookup_(v, VStr(k)), lookup_(out, VStr(k))))

  // A spec admits a value when validating the value against it finds no error
  // and gives back the value as it is.
  private def admits(v: Value, spec: Value, inj: Inj, store: Value): Boolean = {
    val terrs = emptyList()
    val vstore = merge(mkList(Seq(emptyMap(), store)), VNum(1.0))
    setprop(vstore, VStr(S_DTOP), v)
    val d = new InjDef; d.dExtra = vstore; d.dErrs = terrs; d.dMeta = inj.meta
    val out = validate(v, spec, IDef(d))
    size(terrs) == 0 && keeps(v, out)
  }

  // The bounds of a $NOF count, and the words for it, which are absent when
  // the count is invalid. Without a max, the bound is the number of specs.
  private def nofcount(count: Value, numtvals: Int): (Double, Double, Option[String]) = {
    def isnat(n: Value): Boolean = 0 < (T_integer & typify(n)) && (n match { case VNum(x) => 0.0 <= x; case _ => false })
    def num(n: Value): Double = n match { case VNum(x) => x; case _ => 0.0 }

    if (isnat(count)) {
      val n = num(count)
      (n, n, Some(if (n == 0.0) "none" else "exactly " + numToString(n)))
    } else {
      val min = lookup_(count, VStr("min"))
      val max = lookup_(count, VStr("max"))

      val valid =
        ismap(count) &&
          0 < size(count) &&
          size(count) == (if (isNoval(min)) 0 else 1) + (if (isNoval(max)) 0 else 1) &&
          (isNoval(min) || isnat(min)) &&
          (isNoval(max) || isnat(max)) &&
          (isNoval(min) || isNoval(max) || num(min) <= num(max))

      if (!valid) (0.0, 0.0, None)
      else {
        val lo = if (isNoval(min)) 0.0 else num(min)
        val hi = if (isNoval(max)) numtvals.toDouble else num(max)
        val desc =
          if (isNoval(max)) "at least " + numToString(lo)
          else if (hi == 0.0) "none"
          else if (isNoval(min)) "at most " + numToString(hi)
          else if (lo == hi) "exactly " + numToString(lo)
          else numToString(lo) + " to " + numToString(hi)
        (lo, hi, Some(desc))
      }
    }
  }

  def veq(a: Value, b: Value): Boolean = (a, b) match {
    case (Noval, Noval) => true
    case (VNull, VNull) => true
    case (VBool(x), VBool(y)) => x == y
    case (VNum(x), VNum(y)) => x == y
    case (VStr(x), VStr(y)) => x == y
    case (VSentinel(x), VSentinel(y)) => x == y
    case (VList(x), VList(y)) => x.length == y.length && x.indices.forall(i => veq(x(i), y(i)))
    case (VMap(x), VMap(y)) =>
      x.size == y.size && x.forall { case (k, v) => y.get(k) match { case Some(w) => veq(v, w); case None => false } }
    case _ => false
  }

  private val validation: Modify = (pval, key, parent, inj) => {
    if (!isSkip(pval)) {
      val exact = getprop(inj.meta, VStr(S_BEXACT), VBool(false))
      val cval = getprop(inj.dparent, key)
      val exactB = exact match { case VBool(true) => true; case _ => false }
      if (!(!exactB && isNoval(cval))) {
        val ptype = typify(pval)
        if (!((T_string & ptype) > 0 && jsString(pval).indexOf('$') >= 0)) {
          val ctype = typify(cval)
          if (ptype != ctype && !isNoval(pval)) pushErr(inj, invalidTypeMsg(inj.path, typename(ptype), ctype, cval, "V0010"))
          else if (ismap(cval)) {
            if (!ismap(pval)) pushErr(inj, invalidTypeMsg(inj.path, typename(ptype), ctype, cval, "V0020"))
            else {
              val ckeys = keysof(cval)
              val pkeys = keysof(pval)
              if (pkeys.nonEmpty && !(getprop(pval, VStr(S_BOPEN)) == VBool(true))) {
                val badkeys = ckeys.filter(ck => isNoval(lookup_(pval, VStr(ck))))
                if (badkeys.nonEmpty) pushErr(inj, "Unexpected keys at field " + pathify(inj.path, VNum(1.0)) + S_VIZ + badkeys.mkString(", "))
              } else {
                merge(mkList(Seq(pval, cval)))
                if (isnode(pval)) delprop(pval, VStr(S_BOPEN))
              }
            }
          } else if (islist(cval)) {
            if (!islist(pval)) pushErr(inj, invalidTypeMsg(inj.path, typename(ptype), ctype, cval, "V0030"))
          } else if (exactB) {
            if (!veq(cval, pval)) {
              val pathmsg = if (size(inj.path) > 1) "at field " + pathify(inj.path, VNum(1.0)) + ": " else ""
              pushErr(inj, "Value " + pathmsg + jsString(cval) + " should equal " + jsString(pval) + ".")
            }
          } else setprop(parent, key, cval)
        }
      }
    }
  }

  private def validateHandler(inj: Inj, v: Value, refstr: String, store: Value): Value = {
    metaPathMatch(refstr) match {
      case Some((_, g2, _)) =>
        if (g2 == "=") injSetval(inj, mkList(Seq(VStr(S_BEXACT), v))) else injSetval(inj, v)
        inj.keyi = -1; SKIP
      case None => injectHandler(inj, v, refstr, store)
    }
  }

  def validate(data: Value, spec: Value, inj: InjArg = INone): Value = {
    val extra = inj match { case IDef(d) => d.dExtra; case _ => Noval }
    val collect = inj match { case IDef(d) => !isNoval(d.dErrs); case _ => false }
    val errs = inj match { case IDef(d) if collect => d.dErrs; case _ => emptyList() }
    val base = emptyMap()
    def put(k: String, v: Value): Unit = setprop(base, VStr(k), v)
    Seq("$DELETE", "$COPY", "$KEY", "$META", "$MERGE", "$EACH", "$PACK").foreach(k => put(k, VNull))
    put("$STRING", VFunc(validateString))
    Seq("$NUMBER", "$INTEGER", "$DECIMAL", "$BOOLEAN", "$NULL", "$NIL", "$MAP", "$LIST", "$FUNCTION", "$INSTANCE").foreach(k => put(k, VFunc(validateType)))
    put("$ANY", VFunc(validateAny))
    put("$CHILD", VFunc(validateChild))
    put("$EXACT", VFunc(validateExact))
    put("$NOF", VFunc(validateNof))
    put("$ALL", VFunc(validateAll))
    val store = merge(mkList(Seq(base, if (isNoval(extra)) emptyMap() else extra, mkMap(Seq((S_DERRS, errs))))), VNum(1.0))
    val meta = inj match { case IDef(d) if !isNoval(d.dMeta) => d.dMeta; case _ => emptyMap() }
    setprop(meta, VStr(S_BEXACT), getprop(meta, VStr(S_BEXACT), VBool(false)))
    val idef = new InjDef
    idef.dMeta = meta; idef.dExtra = store; idef.dModify = Some(validation); idef.dHandler = Some(validateHandler); idef.dErrs = errs

    // A spec that names an unknown checker validates nothing.
    val numerrs = size(errs)
    checknames(spec, store, Seq.empty, errs)

    val out = if (numerrs < size(errs)) clone(data) else transform(data, spec, IDef(idef))
    if (size(errs) > 0 && !collect) throw StructError(join(errs, VStr(" | ")))
    out
  }

  // ---------------------------------------------------------------------------
  // select
  // ---------------------------------------------------------------------------

  private val selectAnd: Injector = (inj, _v, _r, store) => {
    if (inj.mode == M_KEYPRE) {
      val terms = getprop(inj.parent, inj.key)
      val ppath = slice(inj.path, VNum(-1.0))
      val point = getpath(store, ppath, INone)
      val vstore = merge(mkList(Seq(emptyMap(), store)), VNum(1.0))
      setprop(vstore, VStr(S_DTOP), point)
      itemsPairs(terms).foreach { case (_, term) =>
        val terrs = emptyList()
        val d = new InjDef; d.dExtra = vstore; d.dErrs = terrs; d.dMeta = inj.meta
        validate(point, term, IDef(d))
        if (size(terrs) != 0) pushErr(inj, "AND:" + pathify(ppath) + "⨯" + stringify(point) + " fail:" + stringify(terms))
      }
      val gkey = getelem(inj.path, VNum(-2.0)); val gp = getelem(inj.nodes, VNum(-2.0))
      setprop(gp, gkey, point)
    }
    Noval
  }

  private val selectOr: Injector = (inj, _v, _r, store) => {
    if (inj.mode == M_KEYPRE) {
      val terms = getprop(inj.parent, inj.key)
      val ppath = slice(inj.path, VNum(-1.0))
      val point = getpath(store, ppath, INone)
      val vstore = merge(mkList(Seq(emptyMap(), store)), VNum(1.0))
      setprop(vstore, VStr(S_DTOP), point)
      var done = false
      itemsPairs(terms).foreach { case (_, term) =>
        if (!done) {
          val terrs = emptyList()
          val d = new InjDef; d.dExtra = vstore; d.dErrs = terrs; d.dMeta = inj.meta
          validate(point, term, IDef(d))
          if (size(terrs) == 0) {
            val gkey = getelem(inj.path, VNum(-2.0)); val gp = getelem(inj.nodes, VNum(-2.0))
            setprop(gp, gkey, point); done = true
          }
        }
      }
      if (!done) pushErr(inj, "OR:" + pathify(ppath) + "⨯" + stringify(point) + " fail:" + stringify(terms))
    }
    Noval
  }

  private val selectNot: Injector = (inj, _v, _r, store) => {
    if (inj.mode == M_KEYPRE) {
      val term = getprop(inj.parent, inj.key)
      val ppath = slice(inj.path, VNum(-1.0))
      val point = getpath(store, ppath, INone)
      val vstore = merge(mkList(Seq(emptyMap(), store)), VNum(1.0))
      setprop(vstore, VStr(S_DTOP), point)
      val terrs = emptyList()
      val d = new InjDef; d.dExtra = vstore; d.dErrs = terrs; d.dMeta = inj.meta
      validate(point, term, IDef(d))
      if (size(terrs) == 0) pushErr(inj, "NOT:" + pathify(ppath) + "⨯" + stringify(point) + " fail:" + stringify(term))
      val gkey = getelem(inj.path, VNum(-2.0)); val gp = getelem(inj.nodes, VNum(-2.0))
      setprop(gp, gkey, point)
    }
    Noval
  }

  private def numCmp(a: Value, b: Value, op: String): Boolean = (a, b) match {
    case (VNum(x), VNum(y)) => op match { case "gt" => x > y; case "lt" => x < y; case "gte" => x >= y; case "lte" => x <= y; case _ => false }
    case _ => false
  }

  private val selectCmp: Injector = (inj, _v, refstr, store) => {
    if (inj.mode == M_KEYPRE) {
      val term = getprop(inj.parent, inj.key)
      val gkey = getelem(inj.path, VNum(-2.0))
      val ppath = slice(inj.path, VNum(-1.0))
      val point = getpath(store, ppath, INone)
      val pass =
        if (refstr == "$GT") numCmp(point, term, "gt")
        else if (refstr == "$LT") numCmp(point, term, "lt")
        else if (refstr == "$GTE") numCmp(point, term, "gte")
        else if (refstr == "$LTE") numCmp(point, term, "lte")
        else if (refstr == "$LIKE") (term match { case VStr(t) => java.util.regex.Pattern.compile(t).matcher(stringify(point)).find(); case _ => false })
        else false
      if (pass) { val gp = getelem(inj.nodes, VNum(-2.0)); setprop(gp, gkey, point) }
      else pushErr(inj, "CMP: " + pathify(ppath) + "⨯" + stringify(point) + " fail:" + refstr + " " + stringify(term))
    }
    Noval
  }

  def select(children0: Value, query: Value): Value = {
    if (!isnode(children0)) emptyList()
    else {
      val children =
        if (ismap(children0)) mkList(itemsPairs(children0).map { case (k, n) => setprop(n, VStr(S_DKEY), VStr(k)); n })
        else mkList((children0 match { case VList(b) => b.toSeq; case _ => Seq.empty }).zipWithIndex.map { case (n, i) => if (ismap(n)) { setprop(n, VStr(S_DKEY), vint(i)); n } else n })
      val results = emptyList()
      val extra = emptyMap()
      Seq(("$AND", selectAnd), ("$OR", selectOr), ("$NOT", selectNot), ("$GT", selectCmp), ("$LT", selectCmp), ("$GTE", selectCmp), ("$LTE", selectCmp), ("$LIKE", selectCmp))
        .foreach { case (k, f) => setprop(extra, VStr(k), VFunc(f)) }
      val q = clone(query)
      walk(q, before = Some((_k, v, _p, _path) => { if (ismap(v)) setprop(v, VStr(S_BOPEN), getprop(v, VStr(S_BOPEN), VBool(true))); v }))
      (children match { case VList(b) => b.toSeq; case _ => Seq.empty }).foreach { child =>
        val errs = emptyList()
        val d = new InjDef
        d.dErrs = errs
        d.dMeta = { val m = emptyMap(); setprop(m, VStr(S_BEXACT), VBool(true)); m }
        d.dExtra = extra
        validate(child, clone(q), IDef(d))
        if (size(errs) == 0) setprop(results, VNum(size(results).toDouble), child)
      }
      results
    }
  }

  // ---------------------------------------------------------------------------
  // condense
  // ---------------------------------------------------------------------------

  private val CONDENSE_VERSION = 1

  private val CONDENSE_MAP = 0
  private val CONDENSE_LIST = 1
  private val CONDENSE_STR = 2
  private val CONDENSE_NUM = 3
  private val CONDENSE_TRUE = 4
  private val CONDENSE_FALSE = 5
  private val CONDENSE_NULL = 6

  private val S_condense = "$condense"
  private val S_condsym = "sym"
  private val S_condnode = "node"
  private val S_condroot = "root"

  private val CONDENSE_IMMUTABLE =
    "struct: condensed structures are immutable - expand() first, then modify the copy"

  // Code point order: String.compareTo uses UTF-16 code unit order, which
  // puts U+FFFF after a supplementary character.
  private def condenseCmp(a: String, b: String): Int = {
    var i = 0
    var j = 0
    while (i < a.length && j < b.length) {
      val ca = a.codePointAt(i)
      val cb = b.codePointAt(j)
      if (ca != cb) return if (ca < cb) -1 else 1
      i += Character.charCount(ca)
      j += Character.charCount(cb)
    }
    a.length - i - (b.length - j)
  }

  // The version must MATCH, not merely be numeric: a future profile would
  // otherwise be decoded under this one's schema.
  def iscondensed(v: Value = Noval): Boolean = v match {
    case VMap(m) =>
      m.get(S_condense).contains(vint(CONDENSE_VERSION)) &&
        m.get(S_condsym).exists(islist) &&
        m.get(S_condnode).exists(islist) &&
        m.get(S_condroot).exists { case VNum(_) => true; case _ => false }
    case _ => false
  }

  // Condense any JSON-shaped node. Pure: the same input always produces a
  // byte-identical result, on every port.
  def condense(v: Value): Value = {
    val symset = HashSet.empty[String]
    def collect(n: Value): Unit = n match {
      case VMap(m) => keysof(n).foreach { k => symset += k; collect(m(k)) }
      case VList(b) => b.foreach(collect)
      case VStr(s) => symset += s
      case _ =>
    }
    collect(v)

    val sym = symset.toSeq.sortWith((a, b) => condenseCmp(a, b) < 0)
    val symid = sym.zipWithIndex.toMap

    val node = ArrayBuffer.empty[Value]
    val seen = HashMap.empty[String, Int]

    def intern(enc: ArrayBuffer[Value]): Int = {
      val enckey = enc.map { case VNum(n) => condenseNumKey(n); case _ => "" }.mkString(",")
      seen.getOrElseUpdate(enckey, { node.append(VList(enc)); node.length - 1 })
    }

    // Post-order, so identical subtrees are already interned when a parent
    // refers to them.
    def build(n: Value): Int = n match {
      case VMap(m) =>
        val enc = ArrayBuffer[Value](vint(CONDENSE_MAP))
        // Code-point order, not keysof's code-unit order, so the key ids ascend.
        keysof(n).sortWith((a, b) => condenseCmp(a, b) < 0).foreach { k => enc.append(vint(symid(k))); enc.append(vint(build(m(k)))) }
        intern(enc)
      case VList(b) =>
        val enc = ArrayBuffer[Value](vint(CONDENSE_LIST))
        b.foreach(x => enc.append(vint(build(x))))
        intern(enc)
      case VStr(s) => intern(ArrayBuffer(vint(CONDENSE_STR), vint(symid(s))))
      case VNum(_) => intern(ArrayBuffer(vint(CONDENSE_NUM), n))
      case VBool(true) => intern(ArrayBuffer(vint(CONDENSE_TRUE)))
      case VBool(false) => intern(ArrayBuffer(vint(CONDENSE_FALSE)))
      case _ => intern(ArrayBuffer(vint(CONDENSE_NULL)))
    }

    val root = build(v)

    mkMap(Seq(
      S_condense -> vint(CONDENSE_VERSION),
      S_condsym -> mkList(sym.map(VStr(_))),
      S_condnode -> VList(node),
      S_condroot -> vint(root)))
  }

  // By value, with -0 and 0 as one number.
  private def condenseNumKey(n: Double): String =
    if (isIntegerF(n) && Math.abs(n) < Long.MaxValue.toDouble) n.toLong.toString else n.toString

  private def condenseList(cond: Value, name: String): ArrayBuffer[Value] = cond match {
    case VMap(m) => m.get(name) match { case Some(VList(b)) => b; case _ => ArrayBuffer.empty[Value] }
    case _ => ArrayBuffer.empty[Value]
  }

  private def condenseAt(b: ArrayBuffer[Value], i: Int): Value = if (i >= 0 && i < b.length) b(i) else Noval

  // A stored index: -1 when negative, past every node when not an integer.
  private def condenseIndex(v: Value): Int = v match {
    case VNum(d) if !d.isNaN && d >= 0 => if (isIntegerF(d) && d < Int.MaxValue) d.toInt else Int.MaxValue
    case _ => -1
  }

  private def condenseRoot(cond: Value): Int = condenseIndex(lookup_(cond, VStr(S_condroot)))

  private def condenseEnc(cond: Value, idx: Int): Value = condenseAt(condenseList(cond, S_condnode), idx)

  private def condenseIs(enc: Value, kind: Int): Boolean = enc match {
    case VList(b) => b.nonEmpty && b(0) == vint(kind)
    case _ => false
  }

  // Bisects the sorted symbol table; -1 when the string occurs nowhere.
  private def condenseSymId(cond: Value, key: String): Int = {
    val sym = condenseList(cond, S_condsym)
    var lo = 0
    var hi = sym.length - 1
    while (lo <= hi) {
      val mid = (lo + hi) >>> 1
      if (sym(mid) == VStr(key)) return mid
      if (condenseCmp(jsString(sym(mid)), key) < 0) lo = mid + 1 else hi = mid - 1
    }
    -1
  }

  // The node index of key inside node idx, or -1. Touches only this node.
  private def condenseChild(cond: Value, idx: Int, key: Value): Int = {
    val enc = condenseEnc(cond, idx)
    enc match {
      case _ if !isKeyType(key) => -1
      case VList(pairs) if condenseIs(enc, CONDENSE_MAP) =>
        val symid = condenseSymId(cond, jsString(key))
        if (symid < 0) return -1
        // Pairs live at [1,2], [3,4], ... with keys ascending: bisect the pairs.
        var lo = 0
        var hi = (pairs.length - 1) / 2 - 1
        while (lo <= hi) {
          val mid = (lo + hi) >>> 1
          val k = pairs(1 + mid * 2) match { case VNum(n) => n; case _ => Double.NaN }
          if (k == symid) return condenseIndex(pairs(2 + mid * 2))
          if (k < symid) lo = mid + 1 else hi = mid - 1
        }
        -1
      case VList(items) if condenseIs(enc, CONDENSE_LIST) =>
        val i = listIndex(key)
        if (0.0 <= i && i < items.length - 1) condenseIndex(items(1 + i.toInt)) else -1
      case _ => -1
    }
  }

  private def condenseResolve(cond: Value, idx: Int, path: Value): Int = {
    val parts: Seq[Value] = path match {
      case VList(b) => b.toSeq
      case VStr(s) => if (s.isEmpty) Seq.empty else s.split("\\.", -1).toSeq.map(VStr(_))
      case Noval | VNull => Seq.empty
      case _ => Seq(VStr(jsString(path)))
    }

    var at = idx
    var i = 0
    while (i < parts.length) {
      if (at < 0) return -1
      if (parts(i) != VStr(S_MT)) at = condenseChild(cond, at, parts(i))
      i += 1
    }
    at
  }

  private def condenseMaterialise(cond: Value, idx: Int): Value = {
    val sym = condenseList(cond, S_condsym)
    val node = condenseList(cond, S_condnode)

    // Every call builds new containers, so materialisations never share one.
    def rebuild(i: Int): Value = {
      val enc = condenseAt(node, i)
      enc match {
        case _ if isNullish(enc) => Noval
        case VList(pairs) if condenseIs(enc, CONDENSE_MAP) =>
          val out = LinkedHashMap.empty[String, Value]
          var j = 1
          while (j < pairs.length) {
            out.put(jsString(condenseAt(sym, condenseIndex(pairs(j)))), rebuild(condenseIndex(condenseAt(pairs, j + 1))))
            j += 2
          }
          VMap(out)
        case VList(items) if condenseIs(enc, CONDENSE_LIST) =>
          VList(ArrayBuffer.from(items.iterator.drop(1).map(x => rebuild(condenseIndex(x)))))
        case VList(e) if condenseIs(enc, CONDENSE_STR) => condenseAt(sym, condenseIndex(condenseAt(e, 1)))
        case VList(e) if condenseIs(enc, CONDENSE_NUM) => condenseAt(e, 1)
        case _ if condenseIs(enc, CONDENSE_TRUE) => VBool(true)
        case _ if condenseIs(enc, CONDENSE_FALSE) => VBool(false)
        case _ => VNull
      }
    }

    if (idx < 0) Noval else rebuild(idx)
  }

  // Fully materialise a condensed structure; any other value comes back
  // unchanged. Correct for any caller, but it gives up every benefit of
  // condensing, so prefer a view or a path read.
  def expand(cond: Value): Value =
    if (!iscondensed(cond)) cond else condenseMaterialise(cond, condenseRoot(cond))

  // The keys of node idx, without materialising any of its values.
  private def condenseKeys(cond: Value, idx: Int): Seq[String] = {
    val enc = condenseEnc(cond, idx)
    enc match {
      case VList(pairs) if condenseIs(enc, CONDENSE_MAP) =>
        val sym = condenseList(cond, S_condsym)
        (1 until pairs.length by 2).map(j => jsString(condenseAt(sym, condenseIndex(pairs(j)))))
      case VList(items) if condenseIs(enc, CONDENSE_LIST) => (1 until items.length).map(j => (j - 1).toString)
      case _ => Seq.empty
    }
  }

  // A cursor into a condensed structure. Reads resolve by integer index and
  // touch only the nodes on the path, so a lookup costs path depth and result
  // size, never total structure size.
  final class CondenseView private[struct] (cond: Value, start: Int, refmemo: HashMap[Int, Value]) {
    // The value at path, materialised: a container comes back as an independent copy.
    def get(path: Value = Noval): Value = condenseMaterialise(cond, condenseResolve(cond, start, path))

    // Key names at path, with no value decoding at all.
    def keys(path: Value = Noval): Seq[String] = {
      val found = condenseResolve(cond, start, path)
      if (found < 0) Seq.empty else condenseKeys(cond, found)
    }

    def has(path: Value = Noval): Boolean = condenseResolve(cond, start, path) >= 0

    // A view at path, sharing this view's ref() memo. No decoding happens here.
    def at(path: Value = Noval): CondenseView = new CondenseView(cond, condenseResolve(cond, start, path), refmemo)

    def value(): Value = condenseMaterialise(cond, start)

    def size(): Int = {
      val enc = condenseEnc(cond, start)
      enc match {
        case VList(pairs) if condenseIs(enc, CONDENSE_MAP) => (pairs.length - 1) / 2
        case VList(items) if condenseIs(enc, CONDENSE_LIST) => items.length - 1
        case _ => 0
      }
    }

    def exists(): Boolean = start >= 0

    // A SHARED materialisation: the same node for the same index, every time.
    // Mutating it corrupts every other reader of that node, including ones
    // reached by a different path, because the structure is a DAG.
    def ref(): Value = refmemo.getOrElse(start, Noval) match {
      case Noval =>
        val got = condenseMaterialise(cond, start)
        refmemo.put(start, got)
        got
      case got => got
    }
  }

  def condenseview(cond: Value, idx: Value = Noval, memo: Option[HashMap[Int, Value]] = None): CondenseView = {
    val start = if (isNullish(idx)) (if (iscondensed(cond)) condenseRoot(cond) else -1) else condenseIndex(idx)
    // The memo is threaded through at(), so every view into one structure
    // hands out the same ref() node.
    new CondenseView(cond, start, memo.getOrElse(HashMap.empty[Int, Value]))
  }

  // ---------------------------------------------------------------------------
  // builders
  // ---------------------------------------------------------------------------

  def jm(kv: Value*): Value = {
    val m = LinkedHashMap.empty[String, Value]
    val arr = kv.toArray
    val n = arr.length
    var i = 0
    while (i < n) {
      val k0 = arr(i)
      val k = k0 match { case VNull => "null"; case VStr(s) => s; case _ => stringify(k0) }
      m.put(k, if (i + 1 < n) arr(i + 1) else VNull)
      i += 2
    }
    VMap(m)
  }

  def jt(v: Value*): Value = mkList(v)

  def tn(t: Int): String = typename(t)
}
