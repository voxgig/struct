// Test Provider (prototype) — Scala 3 port of the canonical ts/provider.ts.
//
// Reads the shared corpus (build/test/test.json) and hands test code clean,
// normalized cases. It is NOT a test runner: it never calls the subject and
// never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
//
// Zero runtime dependencies (Scala/Java standard library only). There is no
// JSON parser in the JVM stdlib, so a minimal one is bundled below — no
// play-json / circe / jackson / gson.

import scala.collection.mutable.ArrayBuffer
import scala.util.matching.Regex
import java.util.regex.Pattern

// ─── JSON ADT ────────────────────────────────────────────────────────────────
//
// An order-preserving JSON model. JObj keeps its pairs as a Vector so that
// iteration order (and "key presence" decisions) match the source document.

sealed trait Json
case object JNull extends Json
final case class JBool(value: Boolean) extends Json
final case class JNum(value: Double) extends Json
final case class JStr(value: String) extends Json
final case class JArr(items: Vector[Json]) extends Json
final case class JObj(pairs: Vector[(String, Json)]) extends Json {
  // First value for a key (mirrors LinkedHashMap.get / last-wins is avoided —
  // a well-formed corpus has unique keys, so first == only).
  def get(key: String): Option[Json] = pairs.collectFirst { case (k, v) if k == key => v }
  def has(key: String): Boolean = pairs.exists(_._1 == key)
  def keys: Vector[String] = pairs.map(_._1)
}

object Json {

  // ─── parsing ───────────────────────────────────────────────────────────────

  final class JsonException(msg: String) extends RuntimeException(msg)

  def parse(text: String): Json = {
    val p = new Parser(text)
    p.skipWs()
    val v = p.parseValue()
    p.skipWs()
    if (!p.atEnd) throw new JsonException(s"Trailing content at position ${p.pos}")
    v
  }

  private final class Parser(val s: String) {
    var pos: Int = 0
    private val n: Int = s.length

    def atEnd: Boolean = pos >= n

    def skipWs(): Unit =
      while (pos < n) {
        val c = s.charAt(pos)
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') pos += 1
        else return
      }

    def peek(): Char = {
      if (pos >= n) throw new JsonException("Unexpected end of input")
      s.charAt(pos)
    }

    def parseValue(): Json = {
      skipWs()
      val c = peek()
      c match {
        case '{' => parseObject()
        case '[' => parseArray()
        case '"' => JStr(parseString())
        case 't' | 'f' => parseBool()
        case 'n' => parseNull()
        case _ =>
          if (c == '-' || (c >= '0' && c <= '9')) parseNumber()
          else throw new JsonException(s"Unexpected char '$c' at position $pos")
      }
    }

    def parseObject(): JObj = {
      val buf = ArrayBuffer.empty[(String, Json)]
      pos += 1 // consume '{'
      skipWs()
      if (peek() == '}') { pos += 1; return JObj(buf.toVector) }
      var cont = true
      while (cont) {
        skipWs()
        if (peek() != '"') throw new JsonException(s"Expected string key at position $pos")
        val key = parseString()
        skipWs()
        if (peek() != ':') throw new JsonException(s"Expected ':' at position $pos")
        pos += 1 // consume ':'
        val v = parseValue()
        buf.append(key -> v)
        skipWs()
        val ch = peek()
        if (ch == ',') pos += 1
        else if (ch == '}') { pos += 1; cont = false }
        else throw new JsonException(s"Expected ',' or '}' at position $pos")
      }
      JObj(buf.toVector)
    }

    def parseArray(): JArr = {
      val buf = ArrayBuffer.empty[Json]
      pos += 1 // consume '['
      skipWs()
      if (peek() == ']') { pos += 1; return JArr(buf.toVector) }
      var cont = true
      while (cont) {
        buf.append(parseValue())
        skipWs()
        val ch = peek()
        if (ch == ',') pos += 1
        else if (ch == ']') { pos += 1; cont = false }
        else throw new JsonException(s"Expected ',' or ']' at position $pos")
      }
      JArr(buf.toVector)
    }

    def parseString(): String = {
      pos += 1 // consume opening '"'
      val b = new StringBuilder
      var cont = true
      while (cont) {
        if (pos >= n) throw new JsonException("Unterminated string")
        val c = s.charAt(pos); pos += 1
        if (c == '"') cont = false
        else if (c == '\\') {
          if (pos >= n) throw new JsonException("Unterminated escape")
          val e = s.charAt(pos); pos += 1
          e match {
            case '"'  => b.append('"')
            case '\\' => b.append('\\')
            case '/'  => b.append('/')
            case 'b'  => b.append('\b')
            case 'f'  => b.append('\f')
            case 'n'  => b.append('\n')
            case 'r'  => b.append('\r')
            case 't'  => b.append('\t')
            case 'u' =>
              if (pos + 4 > n) throw new JsonException("Invalid \\u escape")
              val hex = s.substring(pos, pos + 4); pos += 4
              try b.append(Integer.parseInt(hex, 16).toChar)
              catch { case _: NumberFormatException => throw new JsonException(s"Invalid \\u escape: $hex") }
            case other => throw new JsonException(s"Invalid escape '\\$other'")
          }
        } else b.append(c)
      }
      b.toString
    }

    def parseBool(): Json = {
      if (s.startsWith("true", pos)) { pos += 4; JBool(true) }
      else if (s.startsWith("false", pos)) { pos += 5; JBool(false) }
      else throw new JsonException(s"Invalid literal at position $pos")
    }

    def parseNull(): Json = {
      if (s.startsWith("null", pos)) { pos += 4; JNull }
      else throw new JsonException(s"Invalid literal at position $pos")
    }

    def parseNumber(): Json = {
      val start = pos
      if (peek() == '-') pos += 1
      while (pos < n && Character.isDigit(s.charAt(pos))) pos += 1
      if (pos < n && s.charAt(pos) == '.') {
        pos += 1
        while (pos < n && Character.isDigit(s.charAt(pos))) pos += 1
      }
      if (pos < n && (s.charAt(pos) == 'e' || s.charAt(pos) == 'E')) {
        pos += 1
        if (pos < n && (s.charAt(pos) == '+' || s.charAt(pos) == '-')) pos += 1
        while (pos < n && Character.isDigit(s.charAt(pos))) pos += 1
      }
      val num = s.substring(start, pos)
      try JNum(num.toDouble)
      catch { case _: NumberFormatException => throw new JsonException(s"Invalid number '$num'") }
    }
  }

  // ─── serialization ───────────────────────────────────────────────────────────

  // Compact JSON serialization. Whole-number Doubles render without a trailing
  // ".0" (so 42.0 -> "42"), matching the canonical stringify expectations.
  def stringify(v: Json): String = {
    val sb = new StringBuilder
    write(v, sb)
    sb.toString
  }

  private def write(v: Json, sb: StringBuilder): Unit = v match {
    case JNull       => sb.append("null")
    case JBool(b)    => sb.append(if (b) "true" else "false")
    case JNum(d)     => writeNumber(d, sb)
    case JStr(s)     => writeString(s, sb)
    case JArr(items) =>
      sb.append('[')
      var first = true
      items.foreach { x =>
        if (!first) sb.append(',')
        first = false
        write(x, sb)
      }
      sb.append(']')
    case JObj(pairs) =>
      sb.append('{')
      var first = true
      pairs.foreach { case (k, x) =>
        if (!first) sb.append(',')
        first = false
        writeString(k, sb)
        sb.append(':')
        write(x, sb)
      }
      sb.append('}')
  }

  private def writeNumber(d: Double, sb: StringBuilder): Unit =
    if (d.isFinite && Math.floor(d) == d && Math.abs(d) < 1e15) sb.append(java.lang.Long.toString(d.toLong))
    else sb.append(java.lang.Double.toString(d))

  private def writeString(s: String, sb: StringBuilder): Unit = {
    sb.append('"')
    var i = 0
    while (i < s.length) {
      val c = s.charAt(i)
      c match {
        case '"'  => sb.append("\\\"")
        case '\\' => sb.append("\\\\")
        case '\b' => sb.append("\\b")
        case '\f' => sb.append("\\f")
        case '\n' => sb.append("\\n")
        case '\r' => sb.append("\\r")
        case '\t' => sb.append("\\t")
        case _ =>
          if (c < 0x20) sb.append("\\u%04x".format(c.toInt))
          else sb.append(c)
      }
      i += 1
    }
    sb.append('"')
  }
}

// ─── normalized records ────────────────────────────────────────────────────────

enum InputKind { case In, Args, Ctx }
enum ExpectKind { case Value, Error, Match, Absent }

// Tagged input mirroring the runner's precedence (ctx -> args -> in). `value`
// carries the relevant payload: the single `in` value (JNull if absent), the
// `args` JArr, or the `ctx` JObj.
final case class Input(kind: InputKind, value: Json)

final case class ErrorCheck(any: Boolean, text: Option[String], regex: Boolean)

// Tagged expectation. `value` is Some only for Value (presence-driven, may be
// Some(JNull)). `match` is populated for Match and whenever a `match` block
// co-exists with an err/out.
final case class Expect(
    kind: ExpectKind,
    value: Option[Json],
    error: Option[ErrorCheck],
    `match`: Option[Json]
)

final case class Entry(
    function: String,
    group: String,
    index: Int,
    id: Option[String],
    doc: Boolean,
    client: Option[String],
    input: Input,
    expect: Expect,
    raw: Json
)

// Result of a partial structural match: ok plus, on failure, the failing path
// and the two compared values.
final case class MatchResult(
    ok: Boolean,
    path: Seq[String] = Seq.empty,
    expected: Option[Json] = None,
    actual: Option[Json] = None
)

object TestProvider {

  val NULLMARK = "__NULL__"
  val UNDEFMARK = "__UNDEF__"
  val EXISTSMARK = "__EXISTS__"

  // Default corpus path resolves to build/test/test.json relative to the repo
  // root. A provided path is used as-is, so callers (e.g. the smoke harness
  // running from the repo root) may pass an absolute or repo-relative path.
  def load(path: Option[String] = None): TestProvider = {
    val file = path.getOrElse(defaultTestFile())
    val text = new String(
      java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(file)),
      java.nio.charset.StandardCharsets.UTF_8
    )
    new TestProvider(Json.parse(text))
  }

  private def defaultTestFile(): String = {
    val here = java.nio.file.Paths.get(System.getProperty("user.dir"))
    here.resolve(java.nio.file.Paths.get("build", "test", "test.json")).toString
  }
}

final class TestProvider(val spec: Json) {

  import TestProvider.*

  def raw(): Json = spec

  // The root map under which functions live: prefer spec.struct, else spec.
  private def root(): JObj = spec match {
    case o: JObj =>
      o.get("struct") match {
        case Some(s: JObj) => s
        case _             => o
      }
    case _ => JObj(Vector.empty)
  }

  private def fnNode(fn: String): JObj = {
    val node: Option[Json] = spec match {
      case o: JObj =>
        o.get("struct") match {
          case Some(s: JObj) if s.has(fn) => s.get(fn)
          case _ if o.has(fn)             => o.get(fn)
          case _                          => None
        }
      case _ => None
    }
    node match {
      case Some(m: JObj) => m
      case _             => throw new IllegalArgumentException(s"Unknown function: $fn")
    }
  }

  def functions(): Seq[String] =
    root().pairs.collect { case (k, v) if isGroupBag(v) || hasGroups(v) => k }

  def groups(fn: String): Seq[String] =
    fnNode(fn).pairs.collect { case (k, v) if k != "name" && isGroupBag(v) => k }

  // group == None means "all groups for the function".
  def entries(fn: String, group: Option[String] = None): Seq[Entry] = {
    val node = fnNode(fn)
    val groupList = group match {
      case Some(g) => Seq(g)
      case None    => groups(fn)
    }
    val out = ArrayBuffer.empty[Entry]
    for (g <- groupList) {
      node.get(g) match {
        case Some(bag: JObj) if isGroupBag(bag) =>
          bag.get("set") match {
            case Some(JArr(set)) =>
              set.zipWithIndex.foreach { case (raw, i) => out.append(normalize(fn, g, i, raw)) }
            case _ => ()
          }
        case _ => ()
      }
    }
    out.toSeq
  }

  // A group bag is a map with a `set` array.
  private def isGroupBag(v: Json): Boolean = v match {
    case o: JObj =>
      o.get("set") match {
        case Some(_: JArr) => true
        case _             => false
      }
    case _ => false
  }

  // A function node has at least one child group bag.
  private def hasGroups(v: Json): Boolean = v match {
    case o: JObj => o.pairs.exists { case (k, gv) => k != "name" && isGroupBag(gv) }
    case _       => false
  }

  // ─── normalization ─────────────────────────────────────────────────────────

  private def normalize(fn: String, group: String, index: Int, raw: Json): Entry = {
    val o = raw match {
      case m: JObj => m
      case _       => JObj(Vector.empty)
    }
    Entry(
      function = fn,
      group = group,
      index = index,
      id = strOrNull(o.get("id")),
      doc = o.get("doc").contains(JBool(true)),
      client = strOrNull(o.get("client")),
      input = resolveInput(o),
      expect = resolveExpect(o),
      raw = raw
    )
  }

  // Mirror TS `null != x ? String(x) : null`: a present JSON null is treated as
  // absent (None); other present values stringify (JStr stays as-is).
  private def strOrNull(v: Option[Json]): Option[String] = v match {
    case None | Some(JNull) => None
    case Some(JStr(s))      => Some(s)
    case Some(other)        => Some(Json.stringify(other))
  }

  private def resolveInput(raw: JObj): Input = {
    if (raw.has("ctx")) Input(InputKind.Ctx, raw.get("ctx").get)
    else if (raw.has("args")) Input(InputKind.Args, raw.get("args").get)
    else Input(InputKind.In, if (raw.has("in")) raw.get("in").get else JNull)
  }

  private val reSlash = "^/(.+)/$".r

  private def parseErr(err: Json): ErrorCheck = err match {
    case JBool(true) => ErrorCheck(any = true, text = None, regex = false)
    case JStr(s) =>
      reSlash.findFirstMatchIn(s) match {
        case Some(m) => ErrorCheck(any = false, text = Some(m.group(1)), regex = true)
        case None    => ErrorCheck(any = false, text = Some(s), regex = false)
      }
    // Non-true, non-string err spec: treat as "any error".
    case _ => ErrorCheck(any = true, text = None, regex = false)
  }

  private def resolveExpect(raw: JObj): Expect = {
    val matchPart = if (raw.has("match")) raw.get("match") else None
    if (raw.has("err"))
      Expect(ExpectKind.Error, value = None, error = Some(parseErr(raw.get("err").get)), `match` = matchPart)
    // KEY PRESENCE, not null-check: "out" present even if null => Value.
    else if (raw.has("out"))
      Expect(ExpectKind.Value, value = Some(raw.get("out").get), error = None, `match` = matchPart)
    else if (raw.has("match"))
      Expect(ExpectKind.Match, value = None, error = None, `match` = raw.get("match"))
    else
      Expect(ExpectKind.Absent, value = None, error = None, `match` = None)
  }
}

// ─── pure comparison helpers ────────────────────────────────────────────────────
//
// Side-effect-free; the test calls them to assert. They reproduce the runner's
// comparison logic so each port doesn't re-derive it. Semantics per PROVIDER.md §5.

object TestMatch {

  import TestProvider.{NULLMARK, UNDEFMARK, EXISTSMARK}

  // Mirrors TS /^\/(.+)\/$/ — a "/re/" delimited regex literal.
  private val reSlashMatch: Regex = "^/(.+)/$".r

  // stringify(x) = x if it is already a string, else compact JSON.
  def stringify(x: Json): String = x match {
    case JStr(s) => s
    case _       => Json.stringify(x)
  }

  // Normalize __NULL__ marks (and JNull) to JNull, recursively.
  private def normNull(x: Json): Json = x match {
    case JStr(NULLMARK) => JNull
    case JNull          => JNull
    case JArr(items)    => JArr(items.map(normNull))
    case JObj(pairs)    => JObj(pairs.map { case (k, v) => k -> normNull(v) })
    case _              => x
  }

  // Strict variant: only __NULL__ is normalized (JNull stays JNull anyway).
  private def normMark(x: Json): Json = x match {
    case JStr(NULLMARK) => JNull
    case JArr(items)    => JArr(items.map(normMark))
    case JObj(pairs)    => JObj(pairs.map { case (k, v) => k -> normMark(v) })
    case _              => x
  }

  // matchval(check, base): check === base; else string check is "/re/" regex or
  // case-insensitive substring on stringify(base). (Function checks aren't
  // representable in parsed JSON.)
  def matchval(check: Json, base: Json): Boolean = {
    if (scalarEq(check, base)) true
    else
      check match {
        case JStr(chk) =>
          val basestr = stringify(base)
          reSlashMatch.findFirstMatchIn(chk) match {
            case Some(m) => Pattern.compile(m.group(1)).matcher(basestr).find()
            case None    => basestr.toLowerCase.contains(chk.toLowerCase)
          }
        case _ => false
      }
  }

  // equal: deep equality with __NULL__/JNull collapsed on both sides.
  def equal(expected: Json, actual: Json): Boolean = deepEq(normNull(expected), normNull(actual))

  // equalStrict: deep equality where absent (None at a path) is distinct from
  // JNull; only __NULL__ is normalized.
  def equalStrict(expected: Json, actual: Json): Boolean = deepEq(normMark(expected), normMark(actual))

  // Scalar identity mirroring JS ===: numbers compared by value, JNull == JNull.
  private def scalarEq(a: Json, b: Json): Boolean = (a, b) match {
    case (JNull, JNull)         => true
    case (JBool(x), JBool(y))   => x == y
    case (JNum(x), JNum(y))     => x == y
    case (JStr(x), JStr(y))     => x == y
    case _                      => false
  }

  private def deepEq(a: Json, b: Json): Boolean = (a, b) match {
    case (JArr(la), JArr(lb)) =>
      la.length == lb.length && la.indices.forall(i => deepEq(la(i), lb(i)))
    case (JArr(_), _) | (_, JArr(_)) => false
    case (JObj(pa), JObj(pb)) =>
      val mb = pb.toMap
      pa.length == pb.length && pa.forall { case (k, v) => mb.get(k).exists(w => deepEq(v, w)) }
    case (JObj(_), _) | (_, JObj(_)) => false
    case _                           => scalarEq(a, b)
  }

  def errorMatches(check: ErrorCheck, message: String): Boolean = {
    if (check.any) true
    else
      check.text match {
        case None => false
        case Some(t) =>
          if (check.regex) Pattern.compile(t).matcher(message).find()
          else message.toLowerCase.contains(t.toLowerCase)
      }
  }

  // Partial structural match: every leaf of `check` must match `base` at its path.
  def structMatch(check: Json, base: Json): MatchResult = {
    var result = MatchResult(ok = true)
    walkLeaves(
      check,
      Vector.empty,
      (value, path) => {
        if (result.ok) {
          val baseval: Option[Json] = getpath(base, path) // None == absent
          value match {
            case _ if baseval.exists(bv => scalarEq(value, bv)) => () // equal
            case JStr(UNDEFMARK) if baseval.isEmpty             => () // require absent
            case JStr(EXISTSMARK) if baseval.exists(_ != JNull) => () // require present & non-null
            case _ =>
              val compareBase = baseval.getOrElse(JNull)
              if (!matchval(value, compareBase))
                result = MatchResult(ok = false, path = path, expected = Some(value), actual = baseval)
          }
        }
      }
    )
    result
  }

  private def walkLeaves(node: Json, path: Vector[String], fn: (Json, Vector[String]) => Unit): Unit =
    node match {
      case JArr(items) =>
        items.zipWithIndex.foreach { case (v, i) => walkLeaves(v, path :+ i.toString, fn) }
      case JObj(pairs) =>
        pairs.foreach { case (k, v) => walkLeaves(v, path :+ k, fn) }
      case leaf => fn(leaf, path)
    }

  // Returns None for an absent path (distinct from a present JNull).
  private def getpath(store: Json, path: Vector[String]): Option[Json] = {
    var cur: Json = store
    var i = 0
    var missing = false
    while (i < path.length && !missing) {
      val key = path(i)
      cur match {
        case JArr(items) =>
          key.toIntOption match {
            case Some(idx) if idx >= 0 && idx < items.length => cur = items(idx)
            case _                                           => missing = true
          }
        case o: JObj =>
          o.get(key) match {
            case Some(v) => cur = v
            case None    => missing = true
          }
        case _ => missing = true
      }
      i += 1
    }
    if (missing) None else Some(cur)
  }
}
