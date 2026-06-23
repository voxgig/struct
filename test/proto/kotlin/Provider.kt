// Test Provider (prototype) — Kotlin (JVM) port of the canonical ts/provider.ts.
//
// Reads the shared corpus (build/test/test.json) and hands test code clean,
// normalized cases. It is NOT a test runner: it never calls the subject and
// never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
//
// DEPENDENCY-FREE: Kotlin/Java standard library only. The JVM has no stdlib
// JSON, so this file bundles its own minimal parser (see object Json). No
// kotlinx.serialization, no Gson, no Jackson.

package voxgig.struct.proto

import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Paths

// ─── minimal JSON parser ─────────────────────────────────────────────────────
//
// Parses into JVM object trees that preserve insertion order:
//   objects     -> LinkedHashMap<String, Any?>  (PRESERVES key order)
//   arrays      -> ArrayList<Any?>
//   strings     -> String
//   numbers     -> Double
//   true/false  -> Boolean
//   null        -> null
object Json {
    class JsonException(msg: String) : RuntimeException(msg)

    fun parse(text: String): Any? {
        val p = Parser(text)
        p.skipWs()
        val v = p.parseValue()
        p.skipWs()
        if (!p.atEnd()) {
            throw JsonException("Trailing content at position ${p.pos}")
        }
        return v
    }

    private class Parser(val s: String) {
        var pos: Int = 0

        fun atEnd(): Boolean = pos >= s.length

        fun skipWs() {
            while (pos < s.length) {
                val c = s[pos]
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                    pos++
                } else {
                    break
                }
            }
        }

        fun peek(): Char {
            if (pos >= s.length) {
                throw JsonException("Unexpected end of input")
            }
            return s[pos]
        }

        fun parseValue(): Any? {
            skipWs()
            val c = peek()
            return when (c) {
                '{' -> parseObject()
                '[' -> parseArray()
                '"' -> parseString()
                't', 'f' -> parseBool()
                'n' -> parseNull()
                else -> {
                    if (c == '-' || (c in '0'..'9')) {
                        parseNumber()
                    } else {
                        throw JsonException("Unexpected char '$c' at position $pos")
                    }
                }
            }
        }

        fun parseObject(): LinkedHashMap<String, Any?> {
            val m = LinkedHashMap<String, Any?>()
            pos++ // consume '{'
            skipWs()
            if (peek() == '}') {
                pos++
                return m
            }
            while (true) {
                skipWs()
                if (peek() != '"') {
                    throw JsonException("Expected string key at position $pos")
                }
                val key = parseString()
                skipWs()
                if (peek() != ':') {
                    throw JsonException("Expected ':' at position $pos")
                }
                pos++ // consume ':'
                val v = parseValue()
                m[key] = v
                skipWs()
                val c = peek()
                if (c == ',') {
                    pos++
                    continue
                }
                if (c == '}') {
                    pos++
                    break
                }
                throw JsonException("Expected ',' or '}' at position $pos")
            }
            return m
        }

        fun parseArray(): ArrayList<Any?> {
            val list = ArrayList<Any?>()
            pos++ // consume '['
            skipWs()
            if (peek() == ']') {
                pos++
                return list
            }
            while (true) {
                val v = parseValue()
                list.add(v)
                skipWs()
                val c = peek()
                if (c == ',') {
                    pos++
                    continue
                }
                if (c == ']') {
                    pos++
                    break
                }
                throw JsonException("Expected ',' or ']' at position $pos")
            }
            return list
        }

        fun parseString(): String {
            pos++ // consume opening '"'
            val sb = StringBuilder()
            while (true) {
                if (pos >= s.length) {
                    throw JsonException("Unterminated string")
                }
                val c = s[pos++]
                if (c == '"') {
                    break
                }
                if (c == '\\') {
                    if (pos >= s.length) {
                        throw JsonException("Unterminated escape")
                    }
                    val e = s[pos++]
                    when (e) {
                        '"' -> sb.append('"')
                        '\\' -> sb.append('\\')
                        '/' -> sb.append('/')
                        'b' -> sb.append('\b')
                        'f' -> sb.append('\u000C')
                        'n' -> sb.append('\n')
                        'r' -> sb.append('\r')
                        't' -> sb.append('\t')
                        'u' -> {
                            if (pos + 4 > s.length) {
                                throw JsonException("Invalid \\u escape")
                            }
                            val hex = s.substring(pos, pos + 4)
                            pos += 4
                            try {
                                sb.append(hex.toInt(16).toChar())
                            } catch (nfe: NumberFormatException) {
                                throw JsonException("Invalid \\u escape: $hex")
                            }
                        }
                        else -> throw JsonException("Invalid escape '\\$e'")
                    }
                } else {
                    sb.append(c)
                }
            }
            return sb.toString()
        }

        fun parseBool(): Boolean {
            if (s.startsWith("true", pos)) {
                pos += 4
                return true
            }
            if (s.startsWith("false", pos)) {
                pos += 5
                return false
            }
            throw JsonException("Invalid literal at position $pos")
        }

        fun parseNull(): Any? {
            if (s.startsWith("null", pos)) {
                pos += 4
                return null
            }
            throw JsonException("Invalid literal at position $pos")
        }

        fun parseNumber(): Double {
            val start = pos
            if (peek() == '-') {
                pos++
            }
            while (pos < s.length && s[pos].isDigit()) {
                pos++
            }
            if (pos < s.length && s[pos] == '.') {
                pos++
                while (pos < s.length && s[pos].isDigit()) {
                    pos++
                }
            }
            if (pos < s.length && (s[pos] == 'e' || s[pos] == 'E')) {
                pos++
                if (pos < s.length && (s[pos] == '+' || s[pos] == '-')) {
                    pos++
                }
                while (pos < s.length && s[pos].isDigit()) {
                    pos++
                }
            }
            val num = s.substring(start, pos)
            try {
                return num.toDouble()
            } catch (nfe: NumberFormatException) {
                throw JsonException("Invalid number '$num'")
            }
        }
    }

    // ─── serialization ───────────────────────────────────────────────────────
    //
    // Compact JSON. Whole-number Doubles render without a trailing ".0"
    // (so 42.0 -> "42"), matching the canonical stringify expectations.
    fun stringify(v: Any?): String {
        val sb = StringBuilder()
        write(v, sb)
        return sb.toString()
    }

    private fun write(v: Any?, sb: StringBuilder) {
        when (v) {
            null -> sb.append("null")
            is String -> writeString(v, sb)
            is Double -> writeNumber(v, sb)
            is Number -> writeNumber(v.toDouble(), sb)
            is Boolean -> sb.append(if (v) "true" else "false")
            is Map<*, *> -> {
                sb.append('{')
                var first = true
                for ((k, value) in v) {
                    if (!first) sb.append(',')
                    first = false
                    writeString(k.toString(), sb)
                    sb.append(':')
                    write(value, sb)
                }
                sb.append('}')
            }
            is List<*> -> {
                sb.append('[')
                var first = true
                for (x in v) {
                    if (!first) sb.append(',')
                    first = false
                    write(x, sb)
                }
                sb.append(']')
            }
            else -> writeString(v.toString(), sb)
        }
    }

    private fun writeNumber(d: Double, sb: StringBuilder) {
        if (d.isFinite() && Math.floor(d) == d && Math.abs(d) < 1e15) {
            sb.append(d.toLong().toString())
        } else {
            sb.append(d.toString())
        }
    }

    private fun writeString(s: String, sb: StringBuilder) {
        sb.append('"')
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\b' -> sb.append("\\b")
                '\u000C' -> sb.append("\\f")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> {
                    if (c < ' ') {
                        sb.append("\\u%04x".format(c.code))
                    } else {
                        sb.append(c)
                    }
                }
            }
        }
        sb.append('"')
    }
}

// ─── normalized records ──────────────────────────────────────────────────────

enum class InputKind { IN, ARGS, CTX }

enum class ExpectKind { VALUE, ERROR, MATCH, ABSENT }

data class Input(
    val kind: InputKind,
    val value: Any?,
)

data class ErrorCheck(
    val any: Boolean,
    val text: String?,
    val regex: Boolean,
)

data class Expect(
    val kind: ExpectKind,
    val hasValue: Boolean,
    val value: Any?,
    val error: ErrorCheck?,
    val match: Any?,
)

data class Entry(
    val function: String,
    val group: String,
    val index: Int,
    val id: String?,
    val doc: Boolean,
    val client: String?,
    val input: Input,
    val expect: Expect,
    val raw: Any?,
)

data class MatchResult(
    val ok: Boolean,
    val path: List<String>? = null,
    val expected: Any? = null,
    val actual: Any? = null,
)

// ─── provider ────────────────────────────────────────────────────────────────

class TestProvider(private val spec: Any?) {
    companion object {
        const val NULLMARK = "__NULL__"
        const val UNDEFMARK = "__UNDEF__"
        const val EXISTSMARK = "__EXISTS__"

        // Default corpus path resolves to build/test/test.json relative to the
        // process working directory (mirrors the Java port). A non-null path is
        // used as-is, so callers may pass an absolute or repo-relative path.
        fun load(path: String? = null): TestProvider {
            val file = path ?: defaultTestFile()
            val json = String(Files.readAllBytes(Paths.get(file)), StandardCharsets.UTF_8)
            return TestProvider(Json.parse(json))
        }

        private fun defaultTestFile(): String {
            val here = Paths.get(System.getProperty("user.dir"))
            return here.resolve(Paths.get("build", "test", "test.json")).toString()
        }
    }

    fun raw(): Any? = spec

    @Suppress("UNCHECKED_CAST")
    private fun root(): Map<String, Any?> {
        if (spec is Map<*, *>) {
            val struct = (spec as Map<String, Any?>)["struct"]
            if (struct is Map<*, *>) {
                return struct as Map<String, Any?>
            }
            return spec as Map<String, Any?>
        }
        return LinkedHashMap()
    }

    @Suppress("UNCHECKED_CAST")
    private fun fnNode(fn: String): Map<String, Any?> {
        var node: Any? = null
        if (spec is Map<*, *>) {
            val sp = spec as Map<String, Any?>
            val struct = sp["struct"]
            if (struct is Map<*, *> && (struct as Map<String, Any?>).containsKey(fn)) {
                node = (struct as Map<String, Any?>)[fn]
            } else if (sp.containsKey(fn)) {
                node = sp[fn]
            }
        }
        if (node == null) {
            throw IllegalArgumentException("Unknown function: $fn")
        }
        return node as Map<String, Any?>
    }

    fun functions(): List<String> {
        val out = ArrayList<String>()
        for ((k, v) in root()) {
            if (isGroupBag(v) || hasGroups(v)) {
                out.add(k)
            }
        }
        return out
    }

    fun groups(fn: String): List<String> {
        val out = ArrayList<String>()
        for ((k, v) in fnNode(fn)) {
            if (k != "name" && isGroupBag(v)) {
                out.add(k)
            }
        }
        return out
    }

    // group == null means "all groups for the function".
    @Suppress("UNCHECKED_CAST")
    fun entries(fn: String, group: String? = null): List<Entry> {
        val node = fnNode(fn)
        val groupList = if (group != null) listOf(group) else groups(fn)
        val out = ArrayList<Entry>()
        for (g in groupList) {
            val bag = node[g]
            if (!isGroupBag(bag)) {
                continue
            }
            val set = (bag as Map<String, Any?>)["set"] as List<Any?>
            for (i in set.indices) {
                out.add(normalize(fn, g, i, set[i] as Map<String, Any?>))
            }
        }
        return out
    }
}

// ─── group detection ─────────────────────────────────────────────────────────

// A group bag is a map with a `set` list.
private fun isGroupBag(v: Any?): Boolean {
    return v is Map<*, *> && v["set"] is List<*>
}

// A function node has at least one child group bag.
private fun hasGroups(v: Any?): Boolean {
    if (v !is Map<*, *>) {
        return false
    }
    for ((k, value) in v) {
        if (k != "name" && isGroupBag(value)) {
            return true
        }
    }
    return false
}

// ─── normalization ───────────────────────────────────────────────────────────

private fun has(raw: Map<String, Any?>, key: String): Boolean = raw.containsKey(key)

private fun normalize(fn: String, group: String, index: Int, raw: Map<String, Any?>): Entry {
    val id = raw["id"]
    val client = raw["client"]
    return Entry(
        function = fn,
        group = group,
        index = index,
        id = if (id != null) id.toString() else null,
        doc = raw["doc"] == true,
        client = if (client != null) client.toString() else null,
        input = resolveInput(raw),
        expect = resolveExpect(raw),
        raw = raw,
    )
}

private fun resolveInput(raw: Map<String, Any?>): Input {
    // Precedence ctx > args > in (mirrors resolveArgs).
    if (has(raw, "ctx")) {
        return Input(InputKind.CTX, raw["ctx"])
    }
    if (has(raw, "args")) {
        return Input(InputKind.ARGS, raw["args"])
    }
    // IN: key absent => native null.
    return Input(InputKind.IN, if (has(raw, "in")) raw["in"] else null)
}

private fun parseErr(err: Any?): ErrorCheck {
    if (err == true) {
        return ErrorCheck(any = true, text = null, regex = false)
    }
    if (err is String) {
        val m = Regex("^/(.+)/$").matchEntire(err)
        if (m != null) {
            return ErrorCheck(any = false, text = m.groupValues[1], regex = true)
        }
        return ErrorCheck(any = false, text = err, regex = false)
    }
    // Non-true, non-string err spec: treat as "any error".
    return ErrorCheck(any = true, text = null, regex = false)
}

private fun resolveExpect(raw: Map<String, Any?>): Expect {
    // Attach match whenever a "match" key exists (even alongside err/out).
    val matchPart = if (has(raw, "match")) raw["match"] else null
    // Precedence err > out > match > absent.
    if (has(raw, "err")) {
        return Expect(ExpectKind.ERROR, hasValue = false, value = null, error = parseErr(raw["err"]), match = matchPart)
    }
    // KEY PRESENCE, not null-check: "out" present even if null => VALUE.
    if (has(raw, "out")) {
        return Expect(ExpectKind.VALUE, hasValue = true, value = raw["out"], error = null, match = matchPart)
    }
    if (has(raw, "match")) {
        return Expect(ExpectKind.MATCH, hasValue = false, value = null, error = null, match = raw["match"])
    }
    return Expect(ExpectKind.ABSENT, hasValue = false, value = null, error = null, match = null)
}

// ─── pure comparison helpers ─────────────────────────────────────────────────

// Sentinel distinguishing "key absent" from "value is null" in getpath.
private val MISSING = Any()

// stringify(x) = x if it is already a String, else compact JSON.
fun stringify(x: Any?): String = if (x is String) x else Json.stringify(x)

private fun normNull(x: Any?): Any? {
    if (x == TestProvider.NULLMARK || x == null) {
        return null
    }
    if (x is List<*>) {
        return x.map { normNull(it) }
    }
    if (x is Map<*, *>) {
        val out = LinkedHashMap<String, Any?>()
        for ((k, v) in x) {
            out[k.toString()] = normNull(v)
        }
        return out
    }
    return x
}

private fun normMark(x: Any?): Any? {
    if (x == TestProvider.NULLMARK) {
        return null
    }
    if (x is List<*>) {
        return x.map { normMark(it) }
    }
    if (x is Map<*, *>) {
        val out = LinkedHashMap<String, Any?>()
        for ((k, v) in x) {
            out[k.toString()] = normMark(v)
        }
        return out
    }
    return x
}

// Scalar identity mirroring JS ===: distinguishes Boolean from Number, and
// compares numbers/strings/booleans by value.
private fun scalarEq(a: Any?, b: Any?): Boolean {
    if (a === b) {
        return true
    }
    if (a == null || b == null) {
        return false
    }
    if ((a is Boolean) != (b is Boolean)) {
        return false
    }
    if (a is Number && b is Number) {
        return a.toDouble() == b.toDouble()
    }
    return a == b
}

fun matchval(check: Any?, base: Any?): Boolean {
    if (scalarEq(check, base)) {
        return true
    }
    if (check is String) {
        val basestr = stringify(base)
        val rem = Regex("^/(.+)/$").matchEntire(check)
        if (rem != null) {
            return Regex(rem.groupValues[1]).containsMatchIn(basestr)
        }
        return basestr.lowercase().contains(check.lowercase())
    }
    // A "function" check (not representable from JSON) would return true; no
    // such value arises from the parsed corpus.
    return false
}

fun equal(expected: Any?, actual: Any?): Boolean = deepEq(normNull(expected), normNull(actual))

// Strict variant for the runner's { null: false } functions, where an absent
// value is distinct from JSON null. Only __NULL__ is normalized.
fun equalStrict(expected: Any?, actual: Any?): Boolean = deepEq(normMark(expected), normMark(actual))

private fun deepEq(a: Any?, b: Any?): Boolean {
    if (a === b) {
        return true
    }
    if (a is List<*> && b is List<*>) {
        if (a.size != b.size) {
            return false
        }
        for (i in a.indices) {
            if (!deepEq(a[i], b[i])) {
                return false
            }
        }
        return true
    }
    if (a is List<*> || b is List<*>) {
        return false
    }
    if (a is Map<*, *> && b is Map<*, *>) {
        if (a.size != b.size) {
            return false
        }
        for ((k, v) in a) {
            if (!b.containsKey(k) || !deepEq(v, b[k])) {
                return false
            }
        }
        return true
    }
    if (a is Map<*, *> || b is Map<*, *>) {
        return false
    }
    return scalarEq(a, b)
}

fun errorMatches(check: ErrorCheck, message: String): Boolean {
    if (check.any) {
        return true
    }
    if (check.text == null) {
        return false
    }
    if (check.regex) {
        return Regex(check.text).containsMatchIn(message)
    }
    return message.lowercase().contains(check.text.lowercase())
}

// Partial structural match: every leaf of `check` must match `base` at its path.
fun structMatch(check: Any?, base: Any?): MatchResult {
    var result = MatchResult(ok = true)
    walkLeaves(check, ArrayList()) { value, path ->
        if (!result.ok) {
            return@walkLeaves
        }
        val baseval = getpath(base, path)
        if (baseval !== MISSING && scalarEq(value, baseval)) {
            return@walkLeaves
        }
        if (TestProvider.UNDEFMARK == value && baseval === MISSING) {
            return@walkLeaves
        }
        if (TestProvider.EXISTSMARK == value && baseval !== MISSING && baseval != null) {
            return@walkLeaves
        }
        val compareBase = if (baseval === MISSING) null else baseval
        if (!matchval(value, compareBase)) {
            result = MatchResult(ok = false, path = path, expected = value, actual = compareBase)
        }
    }
    return result
}

private fun walkLeaves(node: Any?, path: List<String>, fn: (Any?, List<String>) -> Unit) {
    if (node is List<*>) {
        for (i in node.indices) {
            walkLeaves(node[i], path + i.toString(), fn)
        }
    } else if (node is Map<*, *>) {
        for ((k, v) in node) {
            walkLeaves(v, path + k.toString(), fn)
        }
    } else {
        fn(node, path)
    }
}

// Returns MISSING for an absent path (distinct from a present null).
private fun getpath(store: Any?, path: List<String>): Any? {
    var cur: Any? = store
    for (key in path) {
        if (cur == null || cur === MISSING) {
            return MISSING
        }
        cur = when (cur) {
            is List<*> -> {
                val idx = key.toIntOrNull() ?: return MISSING
                if (idx >= 0 && idx < cur.size) cur[idx] else MISSING
            }
            is Map<*, *> -> if (cur.containsKey(key)) cur[key] else MISSING
            else -> return MISSING
        }
    }
    return cur
}
