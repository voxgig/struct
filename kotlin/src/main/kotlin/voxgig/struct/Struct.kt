package voxgig.struct

import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.IdentityHashMap
import java.util.Locale
import java.util.function.Supplier
import java.util.regex.Matcher
import java.util.regex.Pattern
import kotlin.math.floor

@Suppress("MemberVisibilityCanBePrivate")
object Struct {
    val UNDEF: Any = Any()
    val DELETE: Any = Any()

    const val T_ANY: Int = (1 shl 31) - 1
    const val T_NOVAL: Int = 1 shl 30
    const val T_BOOLEAN: Int = 1 shl 29
    const val T_DECIMAL: Int = 1 shl 28
    const val T_INTEGER: Int = 1 shl 27
    const val T_NUMBER: Int = 1 shl 26
    const val T_STRING: Int = 1 shl 25
    const val T_FUNCTION: Int = 1 shl 24
    const val T_SYMBOL: Int = 1 shl 23
    const val T_NULL: Int = 1 shl 22
    const val T_LIST: Int = 1 shl 14
    const val T_MAP: Int = 1 shl 13
    const val T_INSTANCE: Int = 1 shl 12
    const val T_SCALAR: Int = 1 shl 7
    const val T_NODE: Int = 1 shl 6
    const val S_DTOP: String = "\$TOP"
    const val S_DSPEC: String = "\$SPEC"
    const val S_DKEY: String = "\$KEY"

    const val M_KEYPRE: Int = 1
    const val M_KEYPOST: Int = 2
    const val M_VAL: Int = 4

    val MODENAME: Map<Int, String> =
        mapOf(
            M_VAL to "val",
            M_KEYPRE to "key:pre",
            M_KEYPOST to "key:post",
        )

    private val R_META_PATH = Pattern.compile("^([^$]+)\\$([=~])(.+)$")
    private val R_INJECT_FULL = Pattern.compile("^`(\\$[A-Z]+|[^`]*)[0-9]*`$")
    private val R_CHECKER_NAME = Pattern.compile("^\\$[A-Z]+$")
    private val R_INJECT_PART = Pattern.compile("`([^`]+)`")
    private val R_CMD_KEY = Pattern.compile("^`(\\$[A-Z]+)(\\d*)`$")
    private val R_TRANSFORM_NAME = Pattern.compile("`\\$([A-Z]+)`")
    private val R_LIST_INDEX = Pattern.compile("^(0|-?[1-9][0-9]*)$")
    val SKIP: Any = Any()

    fun interface WalkApply {
        fun apply(
            key: String?,
            value: Any?,
            parent: Any?,
            path: List<String>,
        ): Any?
    }

    /**
     * Mirrors TS/Java Injector functional interface. Custom dispatch hook for
     * `$NAME` references during inject/transform/validate.
     */
    fun interface Injector {
        fun apply(
            inj: Injection,
            value: Any?,
            ref: String?,
            store: Any?,
        ): Any?
    }

    /**
     * Mirrors TS/Java Modify functional interface. Custom value-mutation hook
     * applied after inject finishes a node.
     */
    fun interface Modify {
        fun apply(
            value: Any?,
            key: Any?,
            parent: Any?,
            inj: Injection?,
            store: Any?,
        )
    }

    /**
     * Injection state used for recursive injection into JSON-like data
     * structures. Mirrors TS `class Injection` (StructUtility.ts:2613) and
     * Java `static class Injection` (Struct.java:3077).
     */
    class Injection(value: Any?, parent: Any?) {
        var mode: Int = M_VAL // M_KEYPRE | M_KEYPOST | M_VAL
        var full: Boolean = false // injection consumed the whole key string
        var keyI: Int = 0 // index of current key in keys
        var keys: MutableList<String> // sibling keys list (shared with prior)
        var key: String // current key string
        var `val`: Any? // current child value
        var parent: Any? // current parent in spec
        var path: MutableList<String> // ancestor key chain ending in key
        var nodes: MutableList<Any?> // ancestor node stack ending in parent
        var handler: Injector? = null // dispatch hook for `$NAME` references
        var errs: MutableList<Any?> // shared error collector
        var meta: MutableMap<String, Any?> // shared metadata bag (do not deep-copy)
        var dparent: Any? = UNDEF // current data-side parent
        var dpath: MutableList<String> // current data-side path
        var base: String? = null // base key in store, if any
        var modify: Modify? = null // optional value-mutation hook
        var prior: Injection? = null // calling injection (chain upwards)
        var extra: Any? = null // free-form passthrough

        init {
            this.`val` = value
            this.parent = parent
            this.errs = mutableListOf()
            this.dpath = mutableListOf(S_DTOP)
            this.keys = mutableListOf(S_DTOP)
            this.key = S_DTOP
            this.path = mutableListOf(S_DTOP)
            this.nodes = mutableListOf(parent)
            this.base = S_DTOP
            this.meta = linkedMapOf()
        }

        /** Resolve current data-side parent for relative paths and bump depth. */
        fun descend(): Any? {
            val dRaw = meta["__d"]
            val d = if (dRaw is Number) dRaw.toInt() else 0
            meta["__d"] = d + 1

            val parentkey: String? = if (path.size >= 2) path[path.size - 2] else null

            if (dparent === UNDEF) {
                if (size(dpath) > 1 && parentkey != null) {
                    val nd = dpath.toMutableList()
                    nd.add(strkey(parentkey))
                    this.dpath = nd
                }
            } else {
                if (parentkey != null) {
                    this.dparent = getprop(this.dparent, parentkey)
                    val lastpart = if (dpath.isEmpty()) null else dpath.last()
                    val marker = "$:" + strkey(parentkey)
                    if (marker == lastpart) {
                        @Suppress("UNCHECKED_CAST")
                        val sliced = slice(this.dpath, -1, null)
                        this.dpath = if (sliced is List<*>) sliced.map { it.toString() }.toMutableList() else mutableListOf()
                    } else {
                        val nd = dpath.toMutableList()
                        nd.add(strkey(parentkey))
                        this.dpath = nd
                    }
                }
            }
            return dparent
        }

        /** Build a child injection at keys[keyI], sharing meta/errs/handler/keys. */
        fun child(
            keyI: Int,
            keys: MutableList<String>,
        ): Injection {
            val key = strkey(keys[keyI])
            val v = this.`val`
            val cinj = Injection(getprop(v, key), v)
            cinj.keyI = keyI
            cinj.keys = keys
            cinj.key = key
            val np = path.toMutableList()
            np.add(key)
            cinj.path = np
            val nn = nodes.toMutableList()
            nn.add(v)
            cinj.nodes = nn
            cinj.mode = this.mode
            cinj.handler = this.handler
            cinj.modify = this.modify
            cinj.base = this.base
            cinj.meta = this.meta // shared
            cinj.errs = this.errs // shared
            cinj.prior = this
            cinj.dpath = this.dpath.toMutableList()
            cinj.dparent = this.dparent
            return cinj
        }

        /** Set the current child value on the immediate parent. */
        fun setval(value: Any?): Any? = setval(value, 0)

        /** Set/delete on parent or an ancestor at -ancestor in nodes/path. */
        fun setval(
            value: Any?,
            ancestor: Int,
        ): Any? {
            val out: Any?
            if (ancestor < 2) {
                out =
                    if (value === UNDEF) {
                        val p = delprop(this.parent, this.key)
                        this.parent = p
                        p
                    } else {
                        setprop(this.parent, this.key, value)
                    }
            } else {
                val aval = getelem(this.nodes, 0 - ancestor)
                val akey = getelem(this.path, 0 - ancestor)
                out = if (value === UNDEF) delprop(aval, akey) else setprop(aval, akey, value)
            }
            return out
        }

        override fun toString(): String = toString(null)

        fun toString(prefix: String?): String {
            val sb = StringBuilder()
            sb.append("INJ")
            if (prefix != null) sb.append("/").append(prefix)
            sb.append(":").append(pathify(path, 1))
            sb.append(":").append(MODENAME[mode] ?: "?")
            if (full) sb.append("/full")
            sb.append(": key=").append(keyI).append("/").append(key)
            sb.append(" keys=").append(keys)
            sb.append(" parent=").append(stringify(parent, 60))
            sb.append(" dpath=").append(dpath)
            return sb.toString()
        }
    }

    private val TYPE_NAMES =
        arrayOf(
            "any", "nil", "boolean", "decimal", "integer", "number", "string",
            "function", "symbol", "null",
            "", "", "", "", "", "", "",
            "list", "map", "instance",
            "", "", "", "",
            "scalar", "node",
        )

    fun isnode(value: Any?): Boolean = value is Map<*, *> || value is List<*>

    fun ismap(value: Any?): Boolean = value is Map<*, *>

    fun islist(value: Any?): Boolean = value is List<*>

    fun iskey(key: Any?): Boolean {
        if (key == null || key === UNDEF) return false
        if (key is String) return key.isNotEmpty()
        return key is Number
    }

    fun strkey(key: Any?): String {
        if (key == null || key === UNDEF) return ""
        val t = typify(key)
        if (t and T_STRING != 0) return key as String
        if (t and T_NUMBER != 0) {
            val d = (key as Number).toDouble()
            return if (floor(d) == d) d.toLong().toString() else floor(d).toLong().toString()
        }
        return ""
    }

    fun isempty(value: Any?): Boolean {
        if (value == null || value === UNDEF) return true
        return when (value) {
            is String -> value.isEmpty()
            is List<*> -> value.isEmpty()
            is Map<*, *> -> value.isEmpty()
            else -> false
        }
    }

    fun isfunc(value: Any?): Boolean =
        value is Function<*> || value is Supplier<*> || value is Injector || value is Modify || value is WalkApply

    fun size(value: Any?): Int {
        return when (value) {
            is List<*> -> value.size
            is Map<*, *> -> value.size
            is String -> value.length
            is Number -> floor(value.toDouble()).toInt()
            is Boolean -> if (value) 1 else 0
            else -> 0
        }
    }

    fun typify(value: Any?): Int {
        if (value === UNDEF) return T_NOVAL
        if (value == null) return T_SCALAR or T_NULL
        return when (value) {
            is Number -> {
                val d = value.toDouble()
                if (d.isNaN()) {
                    T_NOVAL
                } else if (floor(d) == d) {
                    T_SCALAR or T_NUMBER or T_INTEGER
                } else {
                    T_SCALAR or T_NUMBER or T_DECIMAL
                }
            }
            is String -> T_SCALAR or T_STRING
            is Boolean -> T_SCALAR or T_BOOLEAN
            is Function<*>, is java.util.function.Function<*, *>, is Supplier<*>,
            is Injector, is Modify, is WalkApply,
            -> T_SCALAR or T_FUNCTION
            is List<*> -> T_NODE or T_LIST
            is Map<*, *> -> T_NODE or T_MAP
            else -> T_NODE or T_INSTANCE
        }
    }

    fun typename(typeValue: Any?): String {
        if (typeValue !is Number) return "any"
        val t = typeValue.toInt()
        if (t == 0) return "any"
        val idx = Integer.numberOfLeadingZeros(t)
        if (idx < 0 || idx >= TYPE_NAMES.size) return "any"
        val out = TYPE_NAMES[idx]
        return if (out.isEmpty()) "any" else out
    }

    fun keysof(value: Any?): List<String> {
        if (!isnode(value)) return emptyList()
        if (value is List<*>) return value.indices.map { it.toString() }
        val keys = (value as Map<*, *>).keys.map { it.toString() }.toMutableList()
        keys.sort()
        return keys
    }

    fun items(value: Any?): List<List<Any?>> {
        if (!isnode(value)) return emptyList()
        return keysof(value).map { k -> listOf(k, lookup(value, k)) }
    }

    fun getelem(
        value: Any?,
        key: Any?,
    ): Any? = getelem(value, key, UNDEF)

    fun getelem(
        value: Any?,
        key: Any?,
        alt: Any?,
    ): Any? {
        if (value !is List<*> || key == null || key === UNDEF) return resolveAlt(alt)
        var idx = listIndex(key)
        // A negative key counts from the end.
        if (idx < 0.0) idx += value.size
        if (!(0.0 <= idx && idx < value.size)) return resolveAlt(alt)
        val out = value[idx.toInt()]
        // Group A null-unification: a JSON null (or absent) slot counts as "no
        // value" — return the alt (canonical TS getelem `if (null == out)`).
        if (out == null || out === UNDEF) return resolveAlt(alt)
        return out
    }

    fun getprop(
        value: Any?,
        key: Any?,
    ): Any? = getprop(value, key, UNDEF)

    fun getprop(
        value: Any?,
        key: Any?,
        alt: Any?,
    ): Any? {
        if (value == null || value === UNDEF || key == null || key === UNDEF) return alt
        var out: Any? = UNDEF
        when (value) {
            is Map<*, *> -> {
                val sk = mapKey(key)
                if (sk != null && value.containsKey(sk)) out = value[sk]
            }
            is List<*> -> {
                val idx = listIndex(key)
                if (0.0 <= idx && idx < value.size) out = value[idx.toInt()]
            }
            else -> {}
        }
        // Group A null-unification: a stored JSON null (or absent) counts as
        // "no value" → return the alt. Group B callers needing the raw stored
        // null use `lookup`.
        if (out == null || out === UNDEF) return alt
        return out
    }

    /**
     * Group B raw value lookup (canonical TS `_lookup`): read the literally
     * stored value at a slot, preserving JSON null; UNDEF when absent. Used by
     * the validate checkers, closed-map check, transform command handlers and
     * select operators that must distinguish a stored null from absence.
     */
    fun lookup(
        value: Any?,
        key: Any?,
    ): Any? {
        if (value == null || value === UNDEF || key == null || key === UNDEF) return UNDEF
        return when (value) {
            is Map<*, *> -> {
                val sk = mapKey(key)
                if (sk != null && value.containsKey(sk)) value[sk] else UNDEF
            }
            is List<*> -> {
                val idx = listIndex(key)
                if (0.0 <= idx && idx < value.size) value[idx.toInt()] else UNDEF
            }
            else -> UNDEF
        }
    }

    // The key a map read takes, or null for one that is neither a string nor a
    // number, which misses.
    private fun mapKey(key: Any?): String? = if (key is String || key is Number) strkey(key) else null

    // A list key's index, or NaN: an integral number, or the string String(n)
    // prints for one, negative or not ("01", "+1", "1.0" and "-0" are not).
    private fun listIndex(key: Any?): Double =
        when (key) {
            is Number -> key.toDouble().let { if (it.isFinite() && floor(it) == it) it else Double.NaN }
            is String -> if (R_LIST_INDEX.matcher(key).matches()) key.toDouble() else Double.NaN
            else -> Double.NaN
        }

    fun haskey(
        value: Any?,
        key: Any?,
    ): Boolean = getprop(value, key, UNDEF) !== UNDEF

    fun setprop(
        parent: Any?,
        key: Any?,
        value: Any?,
    ): Any? {
        if (!iskey(key)) return parent
        if (iscondensed(parent)) throw IllegalArgumentException(CONDENSE_IMMUTABLE)
        return when (parent) {
            is MutableMap<*, *> -> {
                (parent as MutableMap<String, Any?>)[strkey(key)] = value
                parent
            }
            is MutableList<*> -> {
                val list = parent as MutableList<Any?>
                val idx = listIndex(key)
                if (idx.isNaN()) return parent
                if (idx >= 0.0) {
                    if (idx < list.size) list[idx.toInt()] = value else list.add(value)
                } else {
                    list.add(0, value)
                }
                list
            }
            else -> parent
        }
    }

    fun delprop(
        parent: Any?,
        key: Any?,
    ): Any? {
        if (!iskey(key)) return parent
        if (iscondensed(parent)) throw IllegalArgumentException(CONDENSE_IMMUTABLE)
        return when (parent) {
            is MutableMap<*, *> -> {
                (parent as MutableMap<String, Any?>).remove(strkey(key))
                parent
            }
            is MutableList<*> -> {
                val idx = listIndex(key)
                val list = parent as MutableList<Any?>
                if (0.0 <= idx && idx < list.size) list.removeAt(idx.toInt())
                list
            }
            else -> parent
        }
    }

    fun clone(value: Any?): Any? = cloneInner(value, IdentityHashMap())

    private fun cloneInner(
        value: Any?,
        seen: IdentityHashMap<Any, Any?>,
    ): Any? {
        if (value == null || value === UNDEF) return value
        if (value is String || value is Number || value is Boolean || value is Function<*>) return value
        if (seen.containsKey(value)) return seen[value]
        return when (value) {
            is List<*> -> {
                val out = mutableListOf<Any?>()
                seen[value] = out
                value.forEach { out.add(cloneInner(it, seen)) }
                out
            }
            is Map<*, *> -> {
                val out = linkedMapOf<String, Any?>()
                seen[value] = out
                value.forEach { (k, v) -> out[k.toString()] = cloneInner(v, seen) }
                out
            }
            else -> value
        }
    }

    fun flatten(value: Any?): List<Any?> = flatten(value, 1)

    fun flatten(
        value: Any?,
        depth: Int?,
    ): List<Any?> {
        if (value !is List<*>) return emptyList()
        val out = mutableListOf<Any?>()
        flattenInto(value, depth ?: 1, out)
        return out
    }

    private fun flattenInto(
        input: List<*>,
        depth: Int,
        out: MutableList<Any?>,
    ) {
        input.forEach {
            if (depth > 0 && it is List<*>) {
                flattenInto(it, depth - 1, out)
            } else {
                out.add(it)
            }
        }
    }

    fun filter(
        value: Any?,
        check: (List<Any?>) -> Boolean,
    ): List<Any?> {
        return items(value).filter { check(it) }.map { it[1] }
    }

    fun getdef(
        value: Any?,
        alt: Any?,
    ): Any? = if (value === UNDEF) alt else value

    fun jm(vararg kv: Any?): MutableMap<String, Any?> {
        val out = linkedMapOf<String, Any?>()
        var i = 0
        while (i < kv.size) {
            val raw = if (i < kv.size) kv[i] else UNDEF
            val k = if (raw is String) raw else stringify(raw)
            val v = if (i + 1 < kv.size) kv[i + 1] else null
            out[k] = v
            i += 2
        }
        return out
    }

    fun jt(vararg v: Any?): MutableList<Any?> {
        val out = mutableListOf<Any?>()
        v.forEach { out.add(it) }
        return out
    }

    fun replace(
        s: Any?,
        from: Any?,
        to: Any?,
    ): String {
        val rs =
            when {
                s === UNDEF || s == null -> ""
                s is String -> s
                else -> stringify(s)
            }
        val toStr =
            when {
                to === UNDEF || to == null -> ""
                to is String -> to
                else -> stringify(to)
            }
        return when (from) {
            is Pattern -> from.matcher(rs).replaceAll(java.util.regex.Matcher.quoteReplacement(toStr))
            is Regex -> from.replace(rs, toStr)
            null -> rs
            else -> rs.replace(from.toString(), toStr)
        }
    }

    fun escre(s: Any?): String {
        val input = if (s == null || s === UNDEF) "" else s.toString()
        return input.replace(Regex("""([\\.\[\]{}()*+?^$|])"""), """\\$1""")
    }

    // -----------------------------------------------------------------
    // Regex utility — uniform re* API (see /REGEX_API.md). Kotlin's Regex
    // backs onto java.util.regex.Pattern (an RE2 superset).
    // -----------------------------------------------------------------

    fun reCompile(pattern: String): Regex = Regex(pattern)

    fun reTest(
        pattern: String,
        input: String,
    ): Boolean = Regex(pattern).containsMatchIn(input)

    fun reFind(
        pattern: String,
        input: String,
    ): List<String>? {
        val m = Regex(pattern).find(input) ?: return null
        return m.groupValues
    }

    fun reFindAll(
        pattern: String,
        input: String,
    ): List<List<String>> = Regex(pattern).findAll(input).map { it.groupValues }.toList()

    fun reReplace(
        pattern: String,
        input: String,
        replacement: String,
    ): String {
        // Translate JS $& to Kotlin $0
        val kRepl = replacement.replace("$&", "\$0")
        return Regex(pattern).replace(input, kRepl)
    }

    fun reEscape(s: String): String = escre(s)

    // Keeps what encodeURIComponent keeps: URLEncoder encodes `~!'()` and spaces as `+`.
    fun escurl(s: Any?): String {
        if (s == null || s === UNDEF) return ""
        return URLEncoder.encode(s.toString(), StandardCharsets.UTF_8)
            .replace("+", "%20")
            .replace("%7E", "~")
            .replace("%21", "!")
            .replace("%27", "'")
            .replace("%28", "(")
            .replace("%29", ")")
    }

    fun join(
        arr: Any?,
        sep: Any?,
        url: Any?,
    ): String {
        if (arr !is List<*>) return ""
        val sepDef = if (sep == null || sep === UNDEF) "," else sep.toString()
        val urlMode = url == true
        val parts = arr.filterIsInstance<String>().filter { it.isNotEmpty() }.toMutableList()
        val sepre = Regex(escre(sepDef))
        val clean = mutableListOf<String>()
        for (i in parts.indices) {
            var s = parts[i]
            if (sepDef.length == 1 && sepDef.isNotEmpty()) {
                if (urlMode && i == 0) s = s.replace(Regex("${sepre.pattern}+$"), "")
                if (i > 0) s = s.replace(Regex("^${sepre.pattern}+"), "")
                if (i < parts.size - 1 || !urlMode) s = s.replace(Regex("${sepre.pattern}+$"), "")
            }
            clean.add(s)
        }
        var out = clean.joinToString(sepDef)
        if (!urlMode && sepDef.length == 1 && sepDef.isNotEmpty()) {
            val cc = Regex.escape(sepDef)
            out = out.replace(Regex("([^$cc])$cc+([^$cc])"), "$1$sepDef$2")
        }
        return out
    }

    fun slice(
        value: Any?,
        startObj: Any?,
        endObj: Any?,
    ): Any? {
        var start = if (startObj is Number) floor(startObj.toDouble()).toInt() else null
        var end = if (endObj is Number) floor(endObj.toDouble()).toInt() else null

        if (value is Number) {
            val min = start ?: Int.MIN_VALUE
            val max = (end ?: Int.MAX_VALUE) - 1
            return value.toDouble().coerceIn(min.toDouble(), max.toDouble())
        }

        val vlen = size(value)
        if (end != null && start == null) start = 0
        if (start != null) {
            if (start < 0) {
                end = (vlen + start).coerceAtLeast(0)
                start = 0
            } else if (end != null) {
                if (end < 0) {
                    end = (vlen + end).coerceAtLeast(0)
                } else if (vlen < end) {
                    end = vlen
                }
            } else {
                end = vlen
            }
            if (vlen < start) start = vlen
            if (start >= 0 && start <= (end ?: 0) && (end ?: 0) <= vlen) {
                if (value is List<*>) return value.subList(start, end!!).toMutableList()
                if (value is String) return value.substring(start, end!!)
            } else {
                if (value is List<*>) return mutableListOf<Any?>()
                if (value is String) return ""
            }
        }
        return value
    }

    fun pad(
        value: Any?,
        paddingObj: Any?,
        padcharObj: Any?,
    ): String {
        val s = if (value is String) value else stringify(value)
        val padding = if (paddingObj is Number) floor(paddingObj.toDouble()).toInt() else 44
        val pc = ((padcharObj?.toString() ?: " ") + " ").substring(0, 1)
        return if (padding >= 0) {
            s + pc.repeat((padding - s.length).coerceAtLeast(0))
        } else {
            pc.repeat((-padding - s.length).coerceAtLeast(0)) + s
        }
    }

    fun stringify(value: Any?): String = stringify(value, null)

    fun stringify(
        value: Any?,
        maxlen: Int?,
    ): String {
        val out =
            when {
                value === UNDEF -> ""
                value is String -> value
                else ->
                    try {
                        stringifyStable(value, IdentityHashMap())
                    } catch (_: Exception) {
                        "__STRINGIFY_FAILED__"
                    }
            }
        return if (maxlen != null && maxlen >= 0 && out.length > maxlen) out.substring(0, (maxlen - 3).coerceAtLeast(0)) + "..." else out
    }

    private fun stringifyStable(
        value: Any?,
        seen: IdentityHashMap<Any, Boolean>,
    ): String {
        if (value == null) return "null"
        if (value is String) return value
        if (value is Number) return numstr(value)
        if (value is Boolean || value is Function<*>) return value.toString()
        if (seen.containsKey(value)) throw IllegalStateException("cycle")
        seen[value] = true
        return when (value) {
            is List<*> -> {
                val parts = value.map { stringifyStable(it, seen) }
                seen.remove(value)
                "[" + parts.joinToString(",") + "]"
            }
            is Map<*, *> -> {
                val keys = value.keys.map { it.toString() }.sorted()
                val parts = keys.map { "$it:${stringifyStable((value as Map<String, Any?>)[it], seen)}" }
                seen.remove(value)
                "{" + parts.joinToString(",") + "}"
            }
            else -> {
                seen.remove(value)
                value.toString()
            }
        }
    }

    fun jsonify(value: Any?): String = jsonify(value, null)

    fun jsonify(
        value: Any?,
        flags: Any?,
    ): String {
        if (value === UNDEF) return "null"
        var indent = 2
        var offset = 0
        if (flags is Map<*, *>) {
            val iv = flags["indent"]
            val ov = flags["offset"]
            if (iv is Number) indent = iv.toInt()
            if (ov is Number) offset = ov.toInt()
        }
        return try {
            val sb = StringBuilder()
            _jsonifyInner(value, sb, indent, 0, IdentityHashMap())
            var out = sb.toString()
            if (offset > 0 && out.contains('\n')) {
                val lines = out.split("\n")
                val pad = " ".repeat(offset)
                out = lines.first() + lines.drop(1).joinToString("") { "\n$pad$it" }
            }
            out
        } catch (_: Exception) {
            "__JSONIFY_FAILED__"
        }
    }

    // Pure-Kotlin JSON emitter — mirrors c/src/utility.c::jsonify_inner.
    // Map keys are emitted in INSERTION order (matching TS canonical's
    // JSON.stringify). No third-party JSON library involved.
    private fun _jsonifyInner(
        v: Any?,
        out: StringBuilder,
        indent: Int,
        depth: Int,
        seen: IdentityHashMap<Any, Boolean>,
    ) {
        if (v == null || v === UNDEF) {
            out.append("null")
            return
        }
        if (v is Boolean) {
            out.append(if (v) "true" else "false")
            return
        }
        if (v is Number) {
            val d = v.toDouble()
            if (!d.isFinite()) {
                out.append("null")
                return
            }
            if (floor(d) == d && Math.abs(d) < 1e15) {
                out.append(d.toLong().toString())
            } else {
                var s = String.format(Locale.ROOT, "%g", d)
                if (s.contains('.') && !s.contains('e') && !s.contains('E')) {
                    s = s.trimEnd('0').trimEnd('.')
                }
                out.append(s)
            }
            return
        }
        if (v is String) {
            out.append('"')
            _jsonEscape(v, out)
            out.append('"')
            return
        }
        if (v is Function<*>) {
            out.append("null")
            return
        }
        if (seen.containsKey(v)) {
            out.append("null")
            return
        }
        seen[v] = true
        if (v is List<*>) {
            if (v.isEmpty()) {
                out.append("[]")
                seen.remove(v)
                return
            }
            out.append('[')
            var first = true
            for (e in v) {
                if (!first) out.append(',')
                first = false
                if (indent > 0) {
                    out.append('\n').append(" ".repeat((depth + 1) * indent))
                }
                _jsonifyInner(e, out, indent, depth + 1, seen)
            }
            if (indent > 0) {
                out.append('\n').append(" ".repeat(depth * indent))
            }
            out.append(']')
            seen.remove(v)
            return
        }
        if (v is Map<*, *>) {
            if (v.isEmpty()) {
                out.append("{}")
                seen.remove(v)
                return
            }
            out.append('{')
            var first = true
            for ((k, e) in v) {
                if (!first) out.append(',')
                first = false
                if (indent > 0) {
                    out.append('\n').append(" ".repeat((depth + 1) * indent))
                }
                out.append('"')
                _jsonEscape(k.toString(), out)
                out.append(if (indent > 0) "\": " else "\":")
                _jsonifyInner(e, out, indent, depth + 1, seen)
            }
            if (indent > 0) {
                out.append('\n').append(" ".repeat(depth * indent))
            }
            out.append('}')
            seen.remove(v)
            return
        }
        seen.remove(v)
        out.append("null")
    }

    private fun _jsonEscape(
        s: String,
        out: StringBuilder,
    ) {
        for (c in s) {
            when (c) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\b' -> out.append("\\b")
                '' -> out.append("\\f")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                else -> {
                    if (c.code < 0x20) {
                        out.append(String.format("\\u%04x", c.code))
                    } else {
                        out.append(c)
                    }
                }
            }
        }
    }

    private fun numstr(n: Number): String {
        val d = n.toDouble()
        return if (d.isFinite() && floor(d) == d) d.toLong().toString() else n.toString().lowercase(Locale.ROOT)
    }

    private fun jsonNumber(n: Number): Number {
        val d = n.toDouble()
        return if (d.isFinite() && floor(d) == d) d.toLong() else d
    }

    fun pathify(value: Any?): String = pathify(value, null, null)

    fun pathify(
        value: Any?,
        from: Any?,
    ): String = pathify(value, from, null)

    fun pathify(
        value: Any?,
        startIn: Any?,
        endIn: Any?,
    ): String {
        val start = if (startIn is Number) startIn.toInt().coerceAtLeast(0) else 0
        val end = if (endIn is Number) endIn.toInt().coerceAtLeast(0) else 0
        val path: MutableList<Any?>? =
            when (value) {
                is List<*> -> value.toMutableList()
                is String, is Number -> mutableListOf(value)
                else -> null
            }
        if (path != null) {
            val sp = slice(path, start, path.size - end)
            val use = (sp as? List<*>) ?: emptyList<Any?>()
            if (use.isEmpty()) return "<root>"
            return use.filter { iskey(it) }.joinToString(".") {
                when (it) {
                    is Number -> floor(it.toDouble()).toLong().toString()
                    else -> it.toString().replace(".", "")
                }
            }
        }
        return "<unknown-path" + (if (value === UNDEF) "" else ":" + stringify(value, 47)) + ">"
    }

    fun setpath(
        store: Any?,
        path: Any?,
        value: Any?,
    ): Any? {
        if (iscondensed(store)) throw IllegalArgumentException(CONDENSE_IMMUTABLE)
        val parts: MutableList<Any?> =
            when (path) {
                is List<*> -> path.toMutableList()
                is String -> path.split(".").toMutableList()
                is Number -> mutableListOf(path)
                else -> return UNDEF
            }
        if (parts.isEmpty()) return UNDEF
        var parent = store
        for (i in 0 until parts.size - 1) {
            val key = parts[i]
            var next = getprop(parent, key, UNDEF)
            if (!isnode(next)) {
                val nk = parts[i + 1]
                next = if (nk is Number) mutableListOf<Any?>() else linkedMapOf<String, Any?>()
                setprop(parent, key, next)
            }
            parent = next
        }
        val last = parts.last()
        if (value === DELETE) delprop(parent, last) else setprop(parent, last, value)
        return parent
    }

    fun walk(
        value: Any?,
        apply: WalkApply,
    ): Any? = walk(value, apply, null, 32)

    fun walk(
        value: Any?,
        before: WalkApply?,
        after: WalkApply?,
    ): Any? = walk(value, before, after, 32)

    fun walk(
        value: Any?,
        before: WalkApply?,
        after: WalkApply?,
        maxdepth: Int,
    ): Any? {
        return walkDescend(value, before, after, maxdepth, null, null, mutableListOf())
    }

    private fun walkDescend(
        value: Any?,
        before: WalkApply?,
        after: WalkApply?,
        maxdepth: Int,
        key: String?,
        parent: Any?,
        path: MutableList<String>,
    ): Any? {
        var out = value
        if (before != null) out = before.apply(key, out, parent, path)
        val plen = path.size
        if (maxdepth == 0 || (maxdepth > 0 && maxdepth <= plen)) return out
        if (isnode(out)) {
            for (item in items(out)) {
                val ckey = item[0].toString()
                val child = item[1]
                val newPath = path.toMutableList()
                newPath.add(ckey)
                val newChild = walkDescend(child, before, after, maxdepth, ckey, out, newPath)
                out = setprop(out, ckey, newChild)
            }
            if (parent != null && key != null) setprop(parent, key, out)
        }
        if (after != null) out = after.apply(key, out, parent, path)
        return out
    }

    fun merge(value: Any?): Any? = merge(value, 32)

    fun merge(
        value: Any?,
        maxdepthIn: Int,
    ): Any? {
        val md = if (maxdepthIn < 0) 0 else maxdepthIn
        if (value !is List<*>) return value
        if (value.isEmpty()) return null
        if (value.size == 1) return value[0]
        var out: Any? = getprop(value, 0, linkedMapOf<String, Any?>())
        for (oI in 1 until value.size) {
            val obj = value[oI]
            if (!isnode(obj)) {
                out = obj
            } else {
                val cur = arrayOfNulls<Any>(33)
                val dst = arrayOfNulls<Any>(33)
                cur[0] = out
                dst[0] = out
                val before =
                    WalkApply { key, v, _, path ->
                        val pI = path.size
                        if (md <= pI) {
                            if (key != null) cur[pI - 1] = setprop(cur[pI - 1], key, v)
                        } else if (!isnode(v)) {
                            cur[pI] = v
                        } else {
                            if (pI > 0 && key != null) {
                                dst[pI] = getprop(dst[pI - 1], key, UNDEF).let { if (it === UNDEF) null else it }
                            }
                            val tval = dst[pI]
                            if (typify(v) == typify(tval)) {
                                cur[pI] = tval
                            } else if ((typify(v) and T_INSTANCE) == 0) {
                                // Otherwise the override wins: a plain node is copied, taking
                                // nothing from the destination, so no later merge writes into it.
                                cur[pI] = if (islist(v)) mutableListOf<Any?>() else linkedMapOf<String, Any?>()
                                dst[pI] = null
                            } else {
                                // A class instance is kept as is, so there is nothing to descend.
                                cur[pI] = v
                                return@WalkApply null
                            }
                        }
                        v
                    }
                val after =
                    WalkApply { key, _, parent, path ->
                        val cI = path.size
                        if (key == null || cI <= 0) return@WalkApply cur[0]
                        cur[cI - 1] = setprop(cur[cI - 1], key, cur[cI])
                        // walk writes this back into the override, so it is the
                        // override's own child, leaving the override unchanged.
                        lookup(parent, key)
                    }
                walk(obj, before, after, md)
                out = cur[0]
            }
        }
        if (md == 0) {
            out = getelem(value, -1)
            if (out is List<*>) {
                out = mutableListOf<Any?>()
            } else if (out is Map<*, *>) {
                out = linkedMapOf<String, Any?>()
            }
        }
        return out
    }

    fun getpath(
        store: Any?,
        path: Any?,
    ): Any? = getpath(store, path, null as Injection?)

    /**
     * Injection-based getpath. Builds a transient view from inj.base/dparent/dpath/
     * meta/key for getpathInner's special-path syntax ($KEY/$REF/$META), runs the
     * lookup, then invokes inj.handler if set. Mirrors Java getpath(Object, Object,
     * Injection) (Struct.java:1461).
     */
    fun getpath(
        store: Any?,
        path: Any?,
        inj: Injection?,
    ): Any? {
        val parts = pathParts(path) ?: return UNDEF
        var target = store

        // A condensed store answers as the node it was built from, touching only
        // the nodes on the path. A base changes what the path resolves against,
        // so that read needs the materialised store.
        if (iscondensed(store)) {
            if (inj?.base == null) {
                val found = condenseMaterialise(store, condenseResolve(store, condenseRoot(store), parts))
                // Group A: a stored null reads as absent, as it does through getprop.
                return found ?: UNDEF
            }
            target = expand(store)
        }

        val view: MutableMap<String, Any?>? =
            if (inj == null) {
                null
            } else {
                linkedMapOf<String, Any?>().also {
                    if (inj.base != null) it["base"] = inj.base
                    it["dparent"] = inj.dparent
                    it["dpath"] = inj.dpath
                    it["meta"] = inj.meta
                    it["key"] = inj.key
                }
            }
        var value = getpathInner(target, path, parts, view)
        if (inj?.handler != null) {
            value = inj.handler!!.apply(inj, value, pathifyForHandler(path), target)
        }
        return value
    }

    fun inject(
        value: Any?,
        store: Any?,
    ): Any? = inject(value, store, null as Injection?)

    /**
     * Canonical Injection-based inject. Mirrors TS inject (StructUtility.ts:1264)
     * and Java inject(Object, Object, Injection) (Struct.java:1308). Drives the
     * three-phase machine (M_KEYPRE / M_VAL / M_KEYPOST) for map/list children
     * and dispatches `$NAME` references via inj.handler.
     */
    fun inject(
        value: Any?,
        store: Any?,
        injdef: Injection?,
    ): Any? {
        var v = value
        val inj: Injection
        val isInitial = injdef == null || injdef.prior == null

        if (isInitial) {
            val wrapper = linkedMapOf<String, Any?>(S_DTOP to v)
            inj = Injection(v, wrapper)
            inj.dparent = store
            val errsRaw = getprop(store, "\$ERRS", UNDEF)
            @Suppress("UNCHECKED_CAST")
            if (errsRaw is MutableList<*>) inj.errs = errsRaw as MutableList<Any?>
            inj.meta["__d"] = 0
            if (injdef != null) {
                if (injdef.modify != null) inj.modify = injdef.modify
                if (injdef.extra != null) inj.extra = injdef.extra
                if (injdef.meta != null && injdef.meta.isNotEmpty()) inj.meta = injdef.meta.also { if (!it.containsKey("__d")) it["__d"] = 0 }
                if (injdef.handler != null) inj.handler = injdef.handler
                if (injdef.base != null) inj.base = injdef.base
                if (injdef.dparent !== UNDEF) inj.dparent = injdef.dparent
            }
            if (inj.handler == null) inj.handler = _injecthandler
            inj.nodes.clear()
            inj.nodes.add(wrapper)
        } else {
            inj = injdef!!
        }

        inj.descend()

        if (isnode(v)) {
            var nodekeys: MutableList<String> = keysof(v).toMutableList()
            if (ismap(v)) {
                // $-suffix ordering: non-$ keys first, then $ keys.
                val nonDollar = mutableListOf<String>()
                val dollar = mutableListOf<String>()
                for (k in nodekeys) if (k.contains("$")) dollar.add(k) else nonDollar.add(k)
                nodekeys =
                    mutableListOf<String>().also {
                        it.addAll(nonDollar)
                        it.addAll(dollar)
                    }
            }
            var nkI = 0
            while (nkI < nodekeys.size) {
                val childinj = inj.child(nkI, nodekeys)
                val nodekey = childinj.key
                childinj.mode = M_KEYPRE
                val prekey = _injectstr(nodekey, store, childinj)
                nkI = childinj.keyI
                nodekeys = childinj.keys
                if (prekey !== UNDEF) {
                    childinj.`val` = getprop(v, prekey)
                    childinj.mode = M_VAL
                    inject(childinj.`val`, store, childinj)
                    nkI = childinj.keyI
                    nodekeys = childinj.keys
                    childinj.mode = M_KEYPOST
                    _injectstr(nodekey, store, childinj)
                    nkI = childinj.keyI
                    nodekeys = childinj.keys
                }
                nkI++
            }
        } else if (v is String) {
            inj.mode = M_VAL
            val newVal = _injectstr(v, store, inj)
            if (newVal !== SKIP) inj.setval(newVal)
            v = newVal
        }

        if (inj.modify != null && v !== SKIP) {
            val mkey = inj.key
            val mparent = inj.parent
            val mval = getprop(mparent, mkey)
            inj.modify!!.apply(mval, mkey, mparent, inj, store)
        }

        inj.`val` = v
        return lookup(inj.parent, S_DTOP)
    }

    /**
     * String-injection helper. Mirrors TS _injectstr (StructUtility.ts) and Java
     * _injectstr (Struct.java:1490). Handles full `\`...\`` patterns (whole-string
     * match) and partial inline patterns, then invokes inj.handler on the result.
     */
    private fun _injectstr(
        value: String?,
        store: Any?,
        inj: Injection?,
    ): Any? {
        if (value.isNullOrEmpty()) return ""
        val full = R_INJECT_FULL.matcher(value)
        if (full.matches()) {
            inj?.full = true
            val pathref = unescapeInjectRef(full.group(1))
            return getpath(store, pathref, inj)
        }
        val m = R_INJECT_PART.matcher(value)
        val sb = StringBuilder()
        var cursor = 0
        while (m.find()) {
            sb.append(value, cursor, m.start())
            val ref = unescapeInjectRef(m.group(1))
            inj?.full = false
            val found = getpath(store, ref, inj)
            sb.append(injectPartialText(found))
            cursor = m.end()
        }
        sb.append(value.substring(cursor))
        var outVal: Any? = sb.toString()
        if (inj?.handler != null) {
            inj.full = true
            outVal = inj.handler!!.apply(inj, outVal, value, store)
        }
        return outVal
    }

    /**
     * Default Injector. When a backtick reference resolves to a callable, invoke
     * it with the Injection. In M_VAL mode with a "full" injection, set the
     * resolved value back onto inj.parent[inj.key]. Mirrors TS _injecthandler
     * (StructUtility.ts) and Java _injecthandler (Struct.java:1631).
     */
    val _injecthandler: Injector =
        Injector { inj, value, ref, store ->
            var out = value
            val iscmd = isfunc(value) && (ref == null || ref.startsWith("$"))
            if (iscmd) {
                out =
                    when (value) {
                        is Injector -> value.apply(inj, value, ref, store)
                        is java.util.function.Function<*, *> -> {
                            @Suppress("UNCHECKED_CAST")
                            (value as java.util.function.Function<Any?, Any?>).apply(inj)
                        }
                        is Function1<*, *> -> {
                            @Suppress("UNCHECKED_CAST")
                            (value as (Any?) -> Any?).invoke(inj)
                        }
                        is java.util.function.Supplier<*> -> value.get()
                        else -> value
                    }
            } else if (inj.mode == M_VAL && inj.full) {
                inj.setval(value)
            }
            out
        }

    // Mirrors TS checkPlacement (StructUtility.ts:2920) and Java (Struct.java:1537).
    private val PLACEMENT: Map<Int, String> =
        mapOf(
            M_VAL to "value",
            M_KEYPRE to "key",
            M_KEYPOST to "key",
        )

    fun checkPlacement(
        modes: Int,
        ijname: String,
        parentTypes: Int,
        inj: Injection,
    ): Boolean {
        if ((modes and inj.mode) == 0) {
            val expected =
                listOf(M_KEYPRE, M_KEYPOST, M_VAL)
                    .filter { (modes and it) != 0 }
                    .joinToString(",") { PLACEMENT[it] ?: "?" }
            inj.errs.add("\$$ijname: invalid placement as ${PLACEMENT[inj.mode]}, expected: $expected.")
            return false
        }
        if (parentTypes != 0) {
            val ptype = typify(inj.parent)
            if ((parentTypes and ptype) == 0) {
                inj.errs.add("\$$ijname: invalid placement in parent ${typename(ptype)}, expected: ${typename(parentTypes)}.")
                return false
            }
        }
        return true
    }

    // Mirrors TS injectorArgs (StructUtility.ts:2947). Returns [errOrUNDEF, arg1, arg2, ...].
    fun injectorArgs(
        argTypes: IntArray,
        args: List<Any?>,
    ): Array<Any?> {
        val numargs = argTypes.size
        val found = arrayOfNulls<Any?>(1 + numargs)
        found[0] = UNDEF
        for (argI in 0 until numargs) {
            val arg = if (argI < args.size) args[argI] else UNDEF
            val argType = typify(arg)
            if ((argTypes[argI] and argType) == 0) {
                found[0] = "invalid argument: ${stringify(arg, 22)} (${typename(argType)} at position ${1 + argI}) is not of type: ${typename(argTypes[argI])}."
                break
            }
            found[1 + argI] = arg
        }
        return found
    }

    // Mirrors TS injectChild (StructUtility.ts:2967). Walks inj.prior/inj.prior.prior
    // to relocate the child within a $FORMAT chain, then re-injects.
    fun injectChild(
        child: Any?,
        store: Any?,
        inj: Injection,
    ): Injection {
        var cinj: Injection = inj
        val prior = inj.prior
        if (prior != null) {
            val priorPrior = prior.prior
            if (priorPrior != null) {
                cinj = priorPrior.child(prior.keyI, prior.keys)
                cinj.`val` = child
                setprop(cinj.parent, prior.key, child)
            } else {
                cinj = prior.child(inj.keyI, inj.keys)
                cinj.`val` = child
                setprop(cinj.parent, inj.key, child)
            }
        }
        inject(child, store, cinj)
        return cinj
    }

    // ===========================================================================
    // Transform Injectors
    // ===========================================================================
    // Mirrors Java Struct.java:1660-2240 and TS StructUtility.ts:1393-1896.
    // Each Injector implements one of the 11 canonical transform commands.

    /** $DELETE: drop the current key. */
    val transform_DELETE: Injector =
        Injector { inj, _, _, _ ->
            inj.setval(UNDEF)
            UNDEF
        }

    /** $COPY: copy the value at the current key from dparent. */
    val transform_COPY: Injector =
        Injector { inj, _, _, _ ->
            if (!checkPlacement(M_VAL, "COPY", T_ANY, inj)) return@Injector UNDEF
            val out = lookup(inj.dparent, inj.key)
            inj.setval(out)
            out
        }

    /** $KEY: emit the parent key, optionally renamed via `$KEY` or `$ANNO.KEY`. */
    val transform_KEY: Injector =
        Injector { inj, _, _, _ ->
            if (inj.mode != M_VAL) return@Injector UNDEF
            // Group B: the $KEY/$ANNO spec markers are read raw (TS _lookup).
            val keyspec = lookup(inj.parent, "`\$KEY`")
            if (keyspec !== UNDEF) {
                delprop(inj.parent, "`\$KEY`")
                return@Injector getprop(inj.dparent, keyspec)
            }
            val anno = lookup(inj.parent, "`\$ANNO`")
            // TS: _lookup(_lookup(parent,$ANNO),KEY) ?? getelem(path,-2) — fall
            // back only when absent or JSON null.
            val annoKey = lookup(anno, "KEY")
            if (annoKey === UNDEF || annoKey == null) getelem(inj.path, -2) else annoKey
        }

    /** $ANNO: drop the annotation marker. */
    val transform_ANNO: Injector =
        Injector { inj, _, _, _ ->
            delprop(inj.parent, "`\$ANNO`")
            UNDEF
        }

    /** $MERGE: deep-merge a list of objects over the current parent. */
    val transform_MERGE: Injector =
        Injector { inj, _, _, _ ->
            if (inj.mode == M_KEYPRE) return@Injector inj.key
            if (inj.mode != M_KEYPOST) return@Injector UNDEF
            val args = getprop(inj.parent, inj.key)
            val argList: MutableList<Any?> =
                if (args is List<*>) {
                    @Suppress("UNCHECKED_CAST")
                    (args.toMutableList() as MutableList<Any?>)
                } else {
                    mutableListOf<Any?>(args)
                }
            inj.setval(UNDEF)
            val mergelist = mutableListOf<Any?>()
            mergelist.add(inj.parent)
            mergelist.addAll(argList)
            mergelist.add(clone(inj.parent))
            merge(mergelist)
            inj.key
        }

    // FORMATTER: name → WalkApply for $FORMAT.
    private fun jsString(v: Any?): String {
        if (v == null) return "null"
        if (v is Number) {
            val d = v.toDouble()
            if (d.isFinite() && floor(d) == d) return d.toLong().toString()
            return v.toString()
        }
        if (v is Boolean) return if (v) "true" else "false"
        return v.toString()
    }

    val FORMATTER: Map<String, WalkApply> =
        linkedMapOf(
            "identity" to WalkApply { _, v, _, _ -> v },
            "upper" to WalkApply { _, v, _, _ -> if (isnode(v)) v else jsString(v).uppercase(Locale.ROOT) },
            "lower" to WalkApply { _, v, _, _ -> if (isnode(v)) v else jsString(v).lowercase(Locale.ROOT) },
            "string" to WalkApply { _, v, _, _ -> if (isnode(v)) v else jsString(v) },
            "number" to
                WalkApply { _, v, _, _ ->
                    if (isnode(v)) {
                        v
                    } else {
                        try {
                            val d = ("" + v).toDouble()
                            when {
                                d.isNaN() -> 0L
                                floor(d) == d -> d.toLong()
                                else -> d
                            }
                        } catch (_: Exception) {
                            0L
                        }
                    }
                },
            "integer" to
                WalkApply { _, v, _, _ ->
                    if (isnode(v)) {
                        v
                    } else {
                        try {
                            ("" + v).toDouble().toLong()
                        } catch (_: Exception) {
                            0L
                        }
                    }
                },
            "concat" to
                WalkApply { k, v, _, _ ->
                    if (k != null || v !is List<*>) {
                        v
                    } else {
                        val sb = StringBuilder()
                        for (item in items(v)) {
                            val x = item[1]
                            if (!isnode(x)) sb.append(jsString(x))
                        }
                        sb.toString()
                    }
                },
        )

    /** $FORMAT: walk a sub-spec applying a named formatter. */
    val transform_FORMAT: Injector =
        Injector { inj, _, _, store ->
            if (inj.keys.size > 1) {
                val first = inj.keys[0]
                inj.keys.clear()
                inj.keys.add(first)
            }
            if (inj.mode != M_VAL) return@Injector UNDEF

            val name = lookup(inj.parent, 1)
            val child = lookup(inj.parent, 2)

            val tkey = getelem(inj.path, -2)
            var target = getelem(inj.nodes, -2)
            if (target === UNDEF) target = getelem(inj.nodes, -1)

            val cinj = injectChild(child, store, inj)
            val resolved = cinj.`val`

            val formatter: WalkApply? = if (name is WalkApply) name else FORMATTER[name?.toString() ?: ""]
            if (formatter == null) {
                inj.errs.add("\$FORMAT: unknown format: $name.")
                return@Injector UNDEF
            }
            val out = walk(resolved, formatter)
            setprop(target, tkey, out)
            out
        }

    /** $APPLY: call a custom function on a resolved sub-spec value. */
    val transform_APPLY: Injector =
        Injector { inj, _, _, store ->
            if (!checkPlacement(M_VAL, "APPLY", T_LIST, inj)) return@Injector UNDEF

            val args = mutableListOf<Any?>()
            val parent = inj.parent
            if (parent is List<*> && parent.size > 1) {
                for (i in 1 until parent.size) args.add(parent[i])
            }
            val checked = injectorArgs(intArrayOf(T_FUNCTION, T_ANY), args)
            if (checked[0] !== UNDEF) {
                inj.errs.add("\$APPLY: ${checked[0]}")
                return@Injector UNDEF
            }
            val applyFn = checked[1]
            val child = checked[2]

            val tkey = getelem(inj.path, -2)
            var target = getelem(inj.nodes, -2)
            if (target === UNDEF) target = getelem(inj.nodes, -1)

            val cinj = injectChild(child, store, inj)
            val resolved = cinj.`val`

            val out: Any? =
                when (applyFn) {
                    is java.util.function.Function<*, *> -> {
                        @Suppress("UNCHECKED_CAST")
                        (applyFn as java.util.function.Function<Any?, Any?>).apply(resolved)
                    }
                    is Function1<*, *> -> {
                        @Suppress("UNCHECKED_CAST")
                        (applyFn as (Any?) -> Any?).invoke(resolved)
                    }
                    else -> UNDEF
                }
            setprop(target, tkey, out)
            out
        }

    /** $EACH: convert a node into a list by cloning the child template per source entry. */
    val transform_EACH: Injector =
        Injector { inj, _, _, store ->
            if (!checkPlacement(M_VAL, "EACH", T_LIST, inj)) return@Injector UNDEF
            if (inj.keys.size > 1) inj.keys.subList(1, inj.keys.size).clear()

            val args = mutableListOf<Any?>()
            val parent = inj.parent
            if (parent is List<*>) for (i in 1 until parent.size) args.add(parent[i])
            val checked = injectorArgs(intArrayOf(T_STRING, T_ANY), args)
            if (checked[0] !== UNDEF) {
                inj.errs.add("\$EACH: ${checked[0]}")
                return@Injector UNDEF
            }
            val srcpath = checked[1] as String
            val child = checked[2]

            val srcstore = getprop(store, inj.base, store)
            val src = getpath(srcstore, srcpath, inj)
            val srctype = typify(src)

            val tkey = getelem(inj.path, -2)
            var target = getelem(inj.nodes, -2)
            if (target === UNDEF) target = getelem(inj.nodes, -1)

            val tval = mutableListOf<Any?>()
            if ((T_LIST and srctype) != 0 && src is List<*>) {
                for (i in src.indices) tval.add(clone(child))
            } else if ((T_MAP and srctype) != 0 && src is Map<*, *>) {
                for ((kAny, _) in src) {
                    val cloned = clone(child)
                    val keyMap = linkedMapOf<String, Any?>("KEY" to kAny.toString())
                    val annoMap = linkedMapOf<String, Any?>("`\$ANNO`" to keyMap)
                    val mergeArgs = mutableListOf<Any?>(cloned, annoMap)
                    tval.add(merge(mergeArgs, 1))
                }
            }

            var rval: Any? = mutableListOf<Any?>()

            if (size(tval) > 0) {
                val tcur: Any? =
                    when (src) {
                        is List<*> -> src.toMutableList()
                        is Map<*, *> -> src.values.toMutableList()
                        else -> UNDEF
                    }

                val ckey = getelem(inj.path, -2)
                val ckeyStr = strkey(ckey)

                val tpathRaw = slice(inj.path, -1, null)

                @Suppress("UNCHECKED_CAST")
                val tpath: MutableList<String> = if (tpathRaw is List<*>) (tpathRaw as List<String>).toMutableList() else mutableListOf()

                val dpath = mutableListOf(S_DTOP)
                if (srcpath.isNotEmpty()) for (part in srcpath.split(".")) dpath.add(part)
                dpath.add("\$:$ckeyStr")

                val tcurMap = linkedMapOf<String, Any?>(ckeyStr to tcur)
                var tcurOut: Any? = tcurMap

                if (size(tpath) > 1) {
                    val pkey = getelem(inj.path, -3, S_DTOP)
                    val pkeyStr = strkey(pkey)
                    val wrap = linkedMapOf<String, Any?>(pkeyStr to tcurOut)
                    tcurOut = wrap
                    dpath.add("\$:$pkeyStr")
                }

                val singleKey = mutableListOf(ckeyStr)
                val tinj = inj.child(0, singleKey)
                tinj.path = tpath
                val slicedNodes = slice(inj.nodes, -1, null)
                @Suppress("UNCHECKED_CAST")
                tinj.nodes = if (slicedNodes is List<*>) (slicedNodes as List<Any?>).toMutableList() else mutableListOf()

                tinj.parent = getelem(tinj.nodes, -1)
                setprop(tinj.parent, ckey, tval)

                tinj.`val` = tval
                tinj.dpath = dpath
                tinj.dparent = tcurOut

                inject(tval, store, tinj)
                rval = tinj.`val`
            }

            setprop(target, tkey, rval)
            if (rval is List<*> && rval.isNotEmpty()) rval[0] else UNDEF
        }

    /** $PACK: convert a list/map into a keyed map. */
    val transform_PACK: Injector =
        Injector { inj, _, _, store ->
            if (!checkPlacement(M_KEYPRE, "PACK", T_MAP, inj)) return@Injector UNDEF

            val argsRaw = getprop(inj.parent, inj.key)
            val argList = mutableListOf<Any?>()
            if (argsRaw is List<*>) argList.addAll(argsRaw)
            val checked = injectorArgs(intArrayOf(T_STRING, T_ANY), argList)
            if (checked[0] !== UNDEF) {
                inj.errs.add("\$PACK: ${checked[0]}")
                return@Injector UNDEF
            }
            val srcpath = checked[1] as String
            val origchildspec = checked[2]

            val tkey = getelem(inj.path, -2)
            val pathsize = size(inj.path)
            var target = getelem(inj.nodes, pathsize - 2)
            if (target === UNDEF) target = getelem(inj.nodes, pathsize - 1)

            val srcstore = getprop(store, inj.base, store)
            val src = getpath(srcstore, srcpath, inj)

            var srcList: MutableList<Any?>? = null
            if (src is List<*>) {
                srcList = src.toMutableList()
            } else if (src is Map<*, *>) {
                srcList = mutableListOf()
                for ((kAny, node) in src) {
                    if (isnode(node)) {
                        val annoMap = linkedMapOf<String, Any?>("KEY" to kAny.toString())
                        setprop(node, "`\$ANNO`", annoMap)
                        srcList.add(node)
                    }
                }
            }
            if (srcList == null) return@Injector UNDEF

            var keypath: Any? = UNDEF
            var child: Any? = origchildspec
            if (origchildspec is Map<*, *>) {
                keypath = getprop(origchildspec, "`\$KEY`", UNDEF)
                delprop(origchildspec, "`\$KEY`")
                child = getprop(origchildspec, "`\$VAL`", origchildspec)
            }
            val keypathFinal = keypath
            val childFinal = child

            val tval = linkedMapOf<String, Any?>()
            for (i in srcList.indices) {
                val item = srcList[i]
                val outKey: String =
                    when {
                        keypathFinal === UNDEF -> {
                            if (item is Map<*, *> && item.containsKey(S_DKEY)) {
                                item[S_DKEY]?.toString() ?: ""
                            } else {
                                i.toString()
                            }
                        }
                        keypathFinal is String && keypathFinal.startsWith("`") -> {
                            val mergeList =
                                mutableListOf<Any?>(linkedMapOf<String, Any?>(), store, linkedMapOf<String, Any?>(S_DTOP to item))
                            val merged = merge(mergeList, 1)
                            inject(keypathFinal, merged)?.toString() ?: ""
                        }
                        else -> getpath(item, keypathFinal, inj)?.toString() ?: ""
                    }

                val tchild = clone(childFinal)
                setprop(tval, outKey, tchild)

                val anno = getprop(item, "`\$ANNO`", UNDEF)
                if (anno === UNDEF) {
                    delprop(tchild, "`\$ANNO`")
                } else {
                    setprop(tchild, "`\$ANNO`", anno)
                }
            }

            var rval: Map<String, Any?> = linkedMapOf()

            if (!isempty(tval)) {
                val tsrc = linkedMapOf<String, Any?>()
                for (i in srcList.indices) {
                    val item = srcList[i]
                    val kn: String =
                        when {
                            keypathFinal === UNDEF -> i.toString()
                            keypathFinal is String && keypathFinal.startsWith("`") -> {
                                val mergeList =
                                    mutableListOf<Any?>(linkedMapOf<String, Any?>(), store, linkedMapOf<String, Any?>(S_DTOP to item))
                                val merged = merge(mergeList, 1)
                                inject(keypathFinal, merged)?.toString() ?: ""
                            }
                            else -> getpath(item, keypathFinal, inj)?.toString() ?: ""
                        }
                    setprop(tsrc, kn, item)
                }

                val tpathRaw = slice(inj.path, -1, null)

                @Suppress("UNCHECKED_CAST")
                val tpath: MutableList<String> = if (tpathRaw is List<*>) (tpathRaw as List<String>).toMutableList() else mutableListOf()

                val ckey = getelem(inj.path, -2)
                val ckeyStr = strkey(ckey)

                val dpath = mutableListOf(S_DTOP)
                if (srcpath.isNotEmpty()) for (part in srcpath.split(".")) dpath.add(part)
                dpath.add("\$:$ckeyStr")

                var tcurOut: Any? = linkedMapOf<String, Any?>(ckeyStr to tsrc)
                if (size(tpath) > 1) {
                    val pkey = getelem(inj.path, -3, S_DTOP)
                    val pkeyStr = strkey(pkey)
                    tcurOut = linkedMapOf<String, Any?>(pkeyStr to tcurOut)
                    dpath.add("\$:$pkeyStr")
                }

                val singleKey = mutableListOf(ckeyStr)
                val tinj = inj.child(0, singleKey)
                tinj.path = tpath
                val slicedNodes = slice(inj.nodes, -1, null)
                @Suppress("UNCHECKED_CAST")
                tinj.nodes = if (slicedNodes is List<*>) (slicedNodes as List<Any?>).toMutableList() else mutableListOf()

                tinj.parent = getelem(tinj.nodes, -1)
                tinj.`val` = tval
                tinj.dpath = dpath
                tinj.dparent = tcurOut

                inject(tval, store, tinj)
                val tv = tinj.`val`
                if (tv is Map<*, *>) {
                    val out = linkedMapOf<String, Any?>()
                    for ((k, vv) in tv) out[k.toString()] = vv
                    rval = out
                }
            }

            setprop(target, tkey, rval)
            UNDEF
        }

    /** $REF: resolve a named reference within the original spec, enabling recursive transformations. */
    val transform_REF: Injector =
        Injector { inj, _, _, store ->
            if (inj.mode != M_VAL) return@Injector UNDEF

            val refpath = lookup(inj.parent, 1)
            inj.keyI = size(inj.keys)

            val specHolder = getprop(store, S_DSPEC)
            val spec: Any? =
                when (specHolder) {
                    is java.util.function.Supplier<*> -> specHolder.get()
                    is Function0<*> -> specHolder.invoke()
                    else -> specHolder
                }

            val dpathRaw = slice(inj.path, 1, null)

            @Suppress("UNCHECKED_CAST")
            val dpath: MutableList<String> = if (dpathRaw is List<*>) (dpathRaw as List<String>).toMutableList() else mutableListOf()
            val refInj = Injection(null, null)
            refInj.dpath = dpath
            refInj.dparent = getpath(spec, dpath)
            refInj.handler = _injecthandler
            val refResolved = getpath(spec, refpath, refInj)

            val tref = clone(refResolved)

            val hasSubRef = booleanArrayOf(false)
            if (isnode(tref)) {
                walk(
                    tref,
                    WalkApply { _, v, _, _ ->
                        if ("`\$REF`" == v) hasSubRef[0] = true
                        v
                    },
                )
            }

            // A recursive reference stops where the data does.
            val tval = getpath(store, slice(inj.path, -1, null))
            val rval = if (!hasSubRef[0] || tval !== UNDEF) tref else UNDEF

            // The enclosing loop injects the referenced spec in this list's place, so
            // neither this pass nor this element leaves a value for modify to check.
            val grandparent = inj.setval(rval, 2)

            val prior = inj.prior
            if (prior != null) {
                prior.modify = null
                if (islist(grandparent) || rval !== UNDEF) {
                    prior.keyI--
                }
            }
            SKIP
        }

    fun transform(
        data: Any?,
        spec: Any?,
    ): Any? = transform(data, spec, null)

    /**
     * Canonical TS-faithful transform: clone the spec, build a store with
     * transform_* injectors registered, then call inject(workspec, store, injdef).
     * Mirrors Java transform (Struct.java:2269) and TS transform (StructUtility.ts:1902).
     */
    fun transform(
        data: Any?,
        spec: Any?,
        options: Map<String, Any?>?,
    ): Any? {
        val origspec = spec
        val workspec = clone(origspec)

        val extraRaw = options?.get("extra")
        val modifyRaw = options?.get("modify")
        val handlerRaw = options?.get("handler")
        val metaRaw = options?.get("meta")
        val errsRaw = options?.get("errs")

        val collect = errsRaw is MutableList<*>

        @Suppress("UNCHECKED_CAST")
        val errs: MutableList<Any?> = if (collect) errsRaw as MutableList<Any?> else mutableListOf()

        val extraTransforms = linkedMapOf<String, Any?>()
        val extraData = linkedMapOf<String, Any?>()
        if (extraRaw is Map<*, *>) {
            for ((kAny, v) in extraRaw) {
                val k = kAny.toString()
                if (k.startsWith("$")) extraTransforms[k] = v else extraData[k] = v
            }
        }

        val dataMergeList = mutableListOf<Any?>()
        if (!isempty(extraData)) dataMergeList.add(clone(extraData))
        dataMergeList.add(clone(data))
        val dataClone = merge(dataMergeList)

        val baseStore = linkedMapOf<String, Any?>()
        baseStore[S_DTOP] = dataClone
        baseStore[S_DSPEC] = java.util.function.Supplier<Any?> { origspec }
        baseStore["\$BT"] = java.util.function.Supplier<Any?> { "`" }
        baseStore["\$DS"] = java.util.function.Supplier<Any?> { "$" }
        baseStore["\$WHEN"] = java.util.function.Supplier<Any?> { java.time.Instant.now().toString() }
        baseStore["\$DELETE"] = transform_DELETE
        baseStore["\$COPY"] = transform_COPY
        baseStore["\$KEY"] = transform_KEY
        baseStore["\$ANNO"] = transform_ANNO
        baseStore["\$MERGE"] = transform_MERGE
        baseStore["\$EACH"] = transform_EACH
        baseStore["\$PACK"] = transform_PACK
        baseStore["\$REF"] = transform_REF
        baseStore["\$FORMAT"] = transform_FORMAT
        baseStore["\$APPLY"] = transform_APPLY

        val storeMergeList = mutableListOf<Any?>()
        storeMergeList.add(baseStore)
        if (extraTransforms.isNotEmpty()) storeMergeList.add(extraTransforms)
        val errsHolder = linkedMapOf<String, Any?>("\$ERRS" to errs)
        storeMergeList.add(errsHolder)
        val store = merge(storeMergeList, 1)

        val injdef = Injection(workspec, null)
        injdef.prior = null
        if (modifyRaw is Modify) injdef.modify = modifyRaw
        if (handlerRaw is Injector) injdef.handler = handlerRaw
        if (metaRaw is Map<*, *>) {
            @Suppress("UNCHECKED_CAST")
            injdef.meta = (metaRaw as Map<String, Any?>).toMutableMap()
        }
        injdef.errs = errs

        val out = inject(workspec, store, injdef)
        if (errs.isNotEmpty() && !collect) {
            throw IllegalArgumentException(errs.joinToString(" | ") { it?.toString() ?: "" })
        }
        return if (out === SKIP || out === UNDEF) null else out
    }

    private fun pathifyForHandler(path: Any?): String {
        return when (path) {
            null -> pathify(UNDEF)
            is String, is List<*>, is Number -> pathify(path)
            else -> pathify(path)
        }
    }

    // A new list, so the caller's path is never rewritten; null when it is no
    // path, or names a part that is neither a string nor a number.
    private fun pathParts(path: Any?): MutableList<String>? {
        return when (path) {
            is String -> if (path.isEmpty()) mutableListOf("") else path.split(".").toMutableList()
            is Number -> mutableListOf(jsString(path))
            is List<*> ->
                path.map {
                    when (it) {
                        is String -> it
                        is Number -> jsString(it)
                        else -> return null
                    }
                }.toMutableList()
            else -> null
        }
    }

    private fun getpathInner(
        store: Any?,
        pathOrig: Any?,
        parts: MutableList<String>,
        inj: MutableMap<String, Any?>?,
    ): Any? {
        val base = inj?.get("base")
        val src = getprop(store, base, store)
        val dparent = inj?.get("dparent")
        val dpath =
            when (val dp = inj?.get("dpath")) {
                is List<*> -> dp.map { it.toString() }.toMutableList()
                is String -> dp.split(".").toMutableList()
                else -> null
            }
        val numparts = parts.size
        var value: Any? = store
        if (pathOrig == null || store == null || (numparts == 1 && parts[0].isEmpty())) {
            value = src
        } else if (numparts > 0) {
            if (numparts == 1) value = getprop(store, parts[0])
            if (!isfunc(value)) {
                value = src
                val m0 = R_META_PATH.matcher(parts[0])
                if (m0.matches() && inj?.get("meta") is Map<*, *>) {
                    value = getprop(inj["meta"], m0.group(1))
                    parts[0] = m0.group(3)
                }
                var pI = 0
                while (value != null && pI < numparts) {
                    var part = parts[pI]
                    if (inj != null && part == S_DKEY) {
                        part = inj["key"]?.toString() ?: ""
                    } else if (inj != null && part.startsWith("\$GET:")) {
                        part = stringify(getpath(src, part.substring(5, part.length - 1)))
                    } else if (inj != null && part.startsWith("\$REF:")) {
                        val specVal = getprop(store, S_DSPEC)
                        if (specVal != null) part = stringify(getpath(specVal, part.substring(5, part.length - 1)))
                    } else if (inj != null && part.startsWith("\$META:")) {
                        part = stringify(getpath(inj["meta"], part.substring(6, part.length - 1)))
                    }
                    part = part.replace("\$\$", "$")
                    if (part.isEmpty()) {
                        var ascends = 0
                        while (pI + 1 < numparts && parts[pI + 1].isEmpty()) {
                            ascends++
                            pI++
                        }
                        if (inj != null && ascends > 0) {
                            if (pI == numparts - 1) ascends--
                            if (ascends == 0) {
                                value = dparent
                            } else if (dpath != null) {
                                val cutLen = (dpath.size - ascends).coerceAtLeast(0)
                                val fullpath = mutableListOf<String>()
                                for (i in 0 until cutLen) fullpath.add(dpath[i])
                                if (pI + 1 < numparts) for (j in pI + 1 until numparts) fullpath.add(parts[j])
                                value = if (ascends <= size(dpath)) getpath(store, fullpath) else null
                                break
                            }
                        } else {
                            value = dparent
                        }
                    } else {
                        value = getprop(value, part)
                    }
                    pI++
                }
            }
        }
        return value
    }

    private fun unescapeInjectRef(ref: String?): String? {
        if (ref != null && ref.length > 3) {
            return ref.replace("\$BT", "`").replace("\$DS", "$")
        }
        return ref
    }

    private fun injectPartialText(found: Any?): String {
        if (found === UNDEF) return ""
        if (found == null) return "null"
        if (found is String) return found
        if (found is Map<*, *> || found is List<*>) {
            val sb = StringBuilder()
            _jsonifyInner(found, sb, 0, 0, IdentityHashMap())
            return sb.toString()
        }
        return stringify(found)
    }

    private fun resolveAlt(alt: Any?): Any? {
        return when (alt) {
            is java.util.function.Function<*, *> -> (alt as java.util.function.Function<Any?, Any?>).apply(null)
            is Function1<*, *> -> (alt as (Any?) -> Any?).invoke(null)
            else -> alt
        }
    }

    // ===========================================================================
    // Validate Injectors
    // ===========================================================================

    /** Build a type-mismatch error message. Mirrors Java _invalidTypeMsg (Struct.java:1439). */
    private fun _invalidTypeMsg(
        path: Any?,
        needtype: String,
        vt: Int,
        v: Any?,
        @Suppress("UNUSED_PARAMETER") whence: String,
    ): String {
        val vs = if (v == null || v === UNDEF) "no value" else stringify(v)
        val sb = StringBuilder("Expected ")
        if (path is List<*> && path.size > 1) sb.append("field ").append(pathify(path, 1)).append(" to be ")
        sb.append(needtype).append(", but found ")
        if (v != null && v !== UNDEF) sb.append(typename(vt)).append(": ")
        sb.append(vs).append(".")
        return sb.toString()
    }

    /** $STRING: require a non-empty string. */
    val validate_STRING: Injector =
        Injector { inj, _, _, _ ->
            val out = lookup(inj.dparent, inj.key)
            val t = typify(out)
            when {
                (T_STRING and t) == 0 -> {
                    inj.errs.add(_invalidTypeMsg(inj.path, "string", t, out, "V1010"))
                    UNDEF
                }
                "" == out -> {
                    inj.errs.add("Empty string at " + pathify(inj.path, 1))
                    UNDEF
                }
                else -> out
            }
        }

    /** Generic $TYPE handler. */
    val validate_TYPE: Injector =
        Injector { inj, _, ref, _ ->
            val tname = if (ref == null || ref.length < 2) "" else ref.substring(1).lowercase(Locale.ROOT)
            var idx = -1
            for (i in TYPE_NAMES.indices) {
                if (tname == TYPE_NAMES[i]) {
                    idx = i
                    break
                }
            }
            if (idx < 0) {
                UNDEF
            } else {
                // $NIL is absent or null.
                val typev = (1 shl (31 - idx)) or (if ("nil" == tname) T_NULL else 0)
                val out = lookup(inj.dparent, inj.key)
                val t = typify(out)
                if ((t and typev) == 0) {
                    inj.errs.add(_invalidTypeMsg(inj.path, tname, t, out, "V1001"))
                    UNDEF
                } else {
                    out
                }
            }
        }

    /** $ANY: accept any value. */
    val validate_ANY: Injector = Injector { inj, _, _, _ -> lookup(inj.dparent, inj.key) }

    /** $CHILD: validate every direct child of the current node against a template. */
    val validate_CHILD: Injector =
        Injector { inj, _, _, _ ->
            when (inj.mode) {
                M_KEYPRE -> {
                    val childtm = getprop(inj.parent, inj.key)
                    val pkey = getelem(inj.path, -2)
                    var tval: Any? = getprop(inj.dparent, pkey)
                    if (tval === UNDEF || tval == null) {
                        tval = linkedMapOf<String, Any?>()
                    } else if (!ismap(tval)) {
                        // _validation reports the mismatch, once.
                        return@Injector UNDEF
                    }
                    val ckeys = keysof(tval)
                    for (ck in ckeys) {
                        setprop(inj.parent, ck, clone(childtm))
                        inj.keys.add(ck)
                    }
                    inj.setval(UNDEF)
                    UNDEF
                }
                M_VAL -> {
                    if (!islist(inj.parent)) {
                        inj.errs.add("Invalid \$CHILD as value")
                        return@Injector UNDEF
                    }
                    val childtm = lookup(inj.parent, 1)
                    if (inj.dparent === UNDEF || inj.dparent == null) {
                        @Suppress("UNCHECKED_CAST")
                        (inj.parent as MutableList<Any?>).clear()
                        return@Injector UNDEF
                    }
                    if (!islist(inj.dparent)) {
                        inj.keyI = size(inj.parent)
                        return@Injector inj.dparent
                    }
                    @Suppress("UNCHECKED_CAST")
                    val dpl = inj.dparent as List<Any?>

                    @Suppress("UNCHECKED_CAST")
                    val pl = inj.parent as MutableList<Any?>
                    for (i in dpl.indices) setprop(pl, i, clone(childtm))
                    while (pl.size > dpl.size) pl.removeAt(pl.size - 1)

                    // NOTE: modifying inj! This extends the child value loop in inject
                    // to cover every cloned child.
                    for (ckeyI in size(inj.keys) until size(pl)) {
                        inj.keys.add(strkey(ckeyI))
                    }

                    // Restart the child value loop at the first element (the loop
                    // increments keyI on resume) so that the first element is also
                    // validated against the child template.
                    inj.keyI = -1

                    // SKIP leaves the cloned child template in place at the first
                    // element so the resumed loop can validate it.
                    SKIP
                }
                else -> UNDEF
            }
        }

    private fun describeAlternatives(tvals: List<Any?>): String {
        return lowernames(join(tvals.map { stringify(it) }, ", ", false))
    }

    // Lowers every `$NAME` marker in the description, nested ones included.
    private fun lowernames(desc: String): String {
        val mm = R_TRANSFORM_NAME.matcher(desc)
        val out = StringBuilder()
        while (mm.find()) {
            mm.appendReplacement(out, Matcher.quoteReplacement(mm.group(1).lowercase(Locale.ROOT)))
        }
        mm.appendTail(out)
        return out.toString()
    }

    /** $EXACT: validate against any one of a list of literal alternatives. */
    val validate_EXACT: Injector =
        Injector { inj, _, _, _ ->
            if (inj.mode == M_VAL) {
                if (!islist(inj.parent) || inj.keyI != 0) {
                    inj.errs.add("The \$EXACT validator at field " + pathify(inj.path, 1, 1) + " must be the first element of an array.")
                    return@Injector UNDEF
                }

                val cval = _slotval(inj)

                inj.keyI = size(inj.keys)

                // Replace [$EXACT, ...] with the data value; SKIP keeps inject off the detached list.
                inj.setval(cval, 2)

                @Suppress("UNCHECKED_CAST")
                inj.path = slice(inj.path, 0, -1) as MutableList<String>

                @Suppress("UNCHECKED_CAST")
                val tvals = slice(inj.parent, 1, null) as List<Any?>
                if (tvals.isEmpty()) {
                    inj.errs.add("The \$EXACT validator at field " + pathify(inj.path, 1, 1) + " must have at least one argument.")
                    return@Injector SKIP
                }

                for (tval in tvals) {
                    if (_deepequal(tval, cval)) return@Injector SKIP
                }

                val valdesc = describeAlternatives(tvals)
                inj.errs.add(
                    _invalidTypeMsg(
                        inj.path,
                        (if (size(inj.path) > 1) "" else "value ") + "exactly equal to " + (if (size(tvals) == 1) "" else "one of ") + valdesc,
                        typify(cval),
                        cval,
                        "V0110",
                    ),
                )
                SKIP
            } else {
                delprop(inj.parent, inj.key)
                UNDEF
            }
        }

    /** $NOF: count the specs that admit the value, `[$NOF, count, spec, ...]`; count is an integer or a map of min and max. */
    val validate_NOF: Injector = Injector { inj, _, _, store -> _validatecount(inj, store, "\$NOF", true) }

    /** $ALL: every spec admits the value, `[$ALL, spec, ...]`. */
    val validate_ALL: Injector = Injector { inj, _, _, store -> _validatecount(inj, store, "\$ALL", false) }

    // The counting list directives. Without a count, every spec has to admit.
    private fun _validatecount(
        inj: Injection,
        store: Any?,
        name: String,
        counted: Boolean,
    ): Any? {
        if (M_VAL != inj.mode) return UNDEF

        val parent = inj.parent

        if (!islist(parent) || 0 != inj.keyI) {
            inj.errs.add("The " + name + " validator at field " + pathify(inj.path, 1, 1) + " must be the first element of an array.")
            return UNDEF
        }

        val cval = _slotval(inj)

        inj.keyI = size(inj.keys)

        // Replace the directive's list with the data value. Each return is SKIP, so
        // that inject leaves the detached list alone and validates nothing in it.
        inj.setval(cval, 2)

        @Suppress("UNCHECKED_CAST")
        inj.path = slice(inj.path, -1, null) as MutableList<String>

        val count = if (counted) lookup(parent, 1) else UNDEF

        @Suppress("UNCHECKED_CAST")
        val tvals = slice(parent, if (counted) 2 else 1, null) as List<Any?>
        val numtvals = tvals.size
        val field = "The " + name + " validator at field " + pathify(inj.path, 1)

        if (0 == numtvals) {
            inj.errs.add(field + (if (counted) " must have a count and" else " must have") + " at least one argument.")
            return SKIP
        }

        val (lo, hi, countdesc) =
            if (counted) _nofcount(count, numtvals) else Triple(numtvals.toLong(), numtvals.toLong(), "all")

        if (null == countdesc) {
            inj.errs.add(field + " has an invalid count: " + stringify(count) + ".")
            return SKIP
        }

        var admitted = 0
        for (tI in 0 until numtvals) {
            val left = numtvals - tI

            // Stop once the specs left cannot change the verdict.
            if (hi < admitted || admitted + left < lo || (lo <= admitted && admitted + left <= hi)) break

            if (_admits(cval, tvals[tI], inj, store)) admitted++
        }

        if (admitted < lo || hi < admitted) {
            val valdesc = describeAlternatives(tvals)
            inj.errs.add(_invalidTypeMsg(inj.path, countdesc + " of " + valdesc, typify(cval), cval, "V0310"))
        }

        return SKIP
    }

    /** $LEN: the value's length is within a bound, `[$LEN, bound, spec?]`; the bound is as for a $NOF count, and a string counts code points. */
    val validate_LEN: Injector = Injector { inj, _, _, store -> _validatebound(inj, store, "\$LEN") }

    /** $RANGE: the value is a number within a bound, `[$RANGE, bound, spec?]`; the bound holds min or gt, max or lt, or one of each. */
    val validate_RANGE: Injector = Injector { inj, _, _, store -> _validatebound(inj, store, "\$RANGE") }

    // The bounding list directives: a bound, then at most one spec that must also admit.
    private fun _validatebound(
        inj: Injection,
        store: Any?,
        name: String,
    ): Any? {
        if (M_VAL != inj.mode) return UNDEF

        val parent = inj.parent

        if (!islist(parent) || 0 != inj.keyI) {
            inj.errs.add("The " + name + " validator at field " + pathify(inj.path, 1, 1) + " must be the first element of an array.")
            return UNDEF
        }

        val cval = _slotval(inj)

        inj.keyI = size(inj.keys)

        // As for the counting directives: SKIP keeps inject off the detached list.
        inj.setval(cval, 2)

        @Suppress("UNCHECKED_CAST")
        inj.path = slice(inj.path, -1, null) as MutableList<String>

        val field = "The " + name + " validator at field " + pathify(inj.path, 1)
        val nargs = size(parent) - 1

        if (nargs < 1 || 2 < nargs) {
            inj.errs.add(field + " must have a bound and at most one spec.")
            return SKIP
        }

        val bound = lookup(parent, 1)
        val islen = "\$LEN" == name
        val (lo, hi, desc) = if (islen) _lenbound(bound) else Triple(0L, 0L, _rangedesc(bound))

        if (null == desc) {
            inj.errs.add(field + " has an invalid bound: " + stringify(bound) + ".")
            return SKIP
        }

        val ctype = typify(cval)

        if (2 == nargs && !_admits(cval, lookup(parent, 2), inj, store)) {
            val specdesc = lowernames(stringify(lookup(parent, 2)))
            inj.errs.add(_invalidTypeMsg(inj.path, specdesc, ctype, cval, "V0410"))
            return SKIP
        }

        if (0 == ((if (islen) T_STRING or T_LIST or T_MAP else T_NUMBER) and ctype)) {
            val needtype = if (islen) "string, list or map" else "number"
            inj.errs.add(_invalidTypeMsg(inj.path, needtype, ctype, cval, "V0420"))
            return SKIP
        }

        val inbound =
            if (islen) {
                val len = if (cval is String) cval.codePointCount(0, cval.length) else size(cval)
                lo <= len && (-1L == hi || len <= hi)
            } else {
                _inrange(bound, (cval as Number).toDouble())
            }

        if (!inbound) {
            val needtype = (if (1 < size(inj.path)) "" else "value ") + desc
            inj.errs.add(_invalidTypeMsg(inj.path, needtype, ctype, cval, "V0430"))
        }

        return SKIP
    }

    // The bounds of a $LEN bound, with -1 for no maximum, and the words for it,
    // which are null when the bound is invalid.
    private fun _lenbound(bound: Any?): Triple<Long, Long, String?> {
        val (lo, hi, countdesc) = _nofcount(bound, -1)

        if (null == countdesc) return Triple(0L, 0L, null)

        val desc =
            when {
                lo == hi -> "$lo"
                -1L == hi -> "at least $lo"
                0L == lo -> "at most $hi"
                else -> "$lo to $hi"
            }

        return Triple(lo, hi, "of length $desc")
    }

    // The words for a $RANGE bound, which are null when the bound is invalid.
    private fun _rangedesc(bound: Any?): String? {
        if (!ismap(bound)) return null

        val min = lookup(bound, "min")
        val max = lookup(bound, "max")
        val gt = lookup(bound, "gt")
        val lt = lookup(bound, "lt")
        val lower = if (UNDEF === min) gt else min
        val upper = if (UNDEF === max) lt else max
        val isnum = { n: Any? -> UNDEF === n || 0 != (T_NUMBER and typify(n)) }

        val valid =
            0 < size(bound) &&
                size(bound) == listOf(min, max, gt, lt).count { UNDEF !== it } &&
                (UNDEF === min || UNDEF === gt) &&
                (UNDEF === max || UNDEF === lt) &&
                isnum(min) &&
                isnum(max) &&
                isnum(gt) &&
                isnum(lt) &&
                (UNDEF === lower || UNDEF === upper || (lower as Number).toDouble() <= (upper as Number).toDouble())

        if (!valid) return null

        val lowerdesc =
            when {
                UNDEF !== min -> "at least " + stringify(min)
                UNDEF !== gt -> "greater than " + stringify(gt)
                else -> null
            }
        val upperdesc =
            when {
                UNDEF !== max -> "at most " + stringify(max)
                UNDEF !== lt -> "less than " + stringify(lt)
                else -> null
            }

        return listOfNotNull(lowerdesc, upperdesc).joinToString(" and ")
    }

    // A number within a valid $RANGE bound.
    private fun _inrange(
        bound: Any?,
        value: Double,
    ): Boolean {
        val min = lookup(bound, "min")
        val max = lookup(bound, "max")
        val gt = lookup(bound, "gt")
        val lt = lookup(bound, "lt")

        return (UNDEF === min || (min as Number).toDouble() <= value) &&
            (UNDEF === max || value <= (max as Number).toDouble()) &&
            (UNDEF === gt || (gt as Number).toDouble() < value) &&
            (UNDEF === lt || value < (lt as Number).toDouble())
    }

    // Names a validate spec may use besides its checkers: transform's that it keeps, and $OPEN.
    private val VALIDATE_NAMES =
        listOf("\$TOP", "\$SPEC", "\$BT", "\$DS", "\$WHEN", "\$ANNO", "\$REF", "\$FORMAT", "\$APPLY", "\$OPEN")

    // Report each checker the spec names that validate lacks; $EXACT's arguments are literals.
    private fun _checknames(
        spec: Any?,
        store: Any?,
        path: List<String>,
        errs: MutableList<Any?>,
    ) {
        val name = _refname(spec)
        if (null != name) {
            if (_unknownname(name, store)) {
                errs.add("Unknown validator " + name + " at field " + pathify(path) + ".")
            }
            return
        }

        if (islist(spec) && "\$EXACT" == _refname(lookup(spec, 0))) return

        for (key in keysof(spec)) {
            if (ismap(spec)) _checknames(key, store, path, errs)
            _checknames(lookup(spec, key), store, path + key, errs)
        }
    }

    // The name a whole-string reference gives, when it is a checker name in any case.
    private fun _refname(value: Any?): String? {
        val m = if (value is String) R_INJECT_FULL.matcher(value) else null
        return if (null != m && m.matches() && R_CHECKER_NAME.matcher(m.group(1).uppercase(Locale.ROOT)).matches()) m.group(1) else null
    }

    // Unknown: undefined and upper case, or a defined name in another case. Null disables a name.
    private fun _unknownname(
        name: String,
        store: Any?,
    ): Boolean {
        val known = { n: String -> VALIDATE_NAMES.contains(n) || lookup(store, n).let { null != it && UNDEF !== it } }
        val upper = name.uppercase(Locale.ROOT)
        return !known(name) && (upper == name || known(upper))
    }

    // The data value at a list directive's slot. The directive's own dparent was
    // read with getprop, which reports a stored null as absent.
    private fun _slotval(inj: Injection): Any? {
        val prior = inj.prior
        return if (null == prior) inj.dparent else lookup(prior.dparent, prior.key)
    }

    // JSON equality: numbers by value, lists in order, maps by key in any order.
    private fun _deepequal(
        a: Any?,
        b: Any?,
    ): Boolean {
        // TS ===: identity, or value equality for numbers, strings and booleans.
        if (a === b || (a is Number && b is Number && a.toDouble() == b.toDouble()) || ((a is String || a is Boolean) && a == b)) {
            return true
        }

        val atype = typify(a)
        if (atype != typify(b) || 0 == ((T_LIST or T_MAP) and atype)) return false

        val akeys = keysof(a)
        val bkeys = keysof(b)
        if (akeys.size != bkeys.size) return false

        for (kI in akeys.indices) {
            val k = akeys[kI]
            if (k != bkeys[kI] || !_deepequal(lookup(a, k), lookup(b, k))) return false
        }

        return true
    }

    // Every member `value` has is in `out`, unchanged. A member only `out` has
    // is a default the spec supplied, and is ignored.
    private fun _keeps(
        value: Any?,
        out: Any?,
    ): Boolean {
        if (UNDEF === value) return true

        if (0 == ((T_LIST or T_MAP) and typify(value)) || islist(value) != islist(out) || !isnode(out)) {
            return _deepequal(value, out)
        }

        for (k in keysof(value)) {
            if (!_keeps(lookup(value, k), lookup(out, k))) return false
        }

        return true
    }

    // A spec admits a value when validating the value against it finds no error
    // and gives back the value as it is.
    private fun _admits(
        value: Any?,
        spec: Any?,
        inj: Injection,
        store: Any?,
    ): Boolean {
        val terrs = mutableListOf<Any?>()

        @Suppress("UNCHECKED_CAST")
        val vstore = merge(mutableListOf(linkedMapOf<String, Any?>(), store), 1) as MutableMap<String, Any?>
        vstore[S_DTOP] = value

        val out =
            validate(
                value,
                spec,
                linkedMapOf<String, Any?>(
                    "extra" to vstore,
                    "errs" to terrs,
                    "meta" to inj.meta,
                ),
            )

        return terrs.isEmpty() && _keeps(value, out)
    }

    // The bounds of a $NOF count, and the words for it, which are null when the
    // count is invalid. Without a max, the bound is the number of specs.
    private fun _nofcount(
        count: Any?,
        numtvals: Int,
    ): Triple<Long, Long, String?> {
        val isnat = { n: Any? -> 0 != (T_INTEGER and typify(n)) && 0.0 <= (n as Number).toDouble() }

        if (isnat(count)) {
            val n = (count as Number).toLong()
            return Triple(n, n, if (0L == n) "none" else "exactly $n")
        }

        val min = lookup(count, "min")
        val max = lookup(count, "max")

        val valid =
            ismap(count) &&
                0 < size(count) &&
                size(count) == (if (UNDEF === min) 0 else 1) + (if (UNDEF === max) 0 else 1) &&
                (UNDEF === min || isnat(min)) &&
                (UNDEF === max || isnat(max)) &&
                (UNDEF === min || UNDEF === max || (min as Number).toDouble() <= (max as Number).toDouble())

        if (!valid) return Triple(0L, 0L, null)

        val lo = if (UNDEF === min) 0L else (min as Number).toLong()
        val hi = if (UNDEF === max) numtvals.toLong() else (max as Number).toLong()

        val desc =
            when {
                UNDEF === max -> "at least $lo"
                0L == hi -> "none"
                UNDEF === min -> "at most $hi"
                lo == hi -> "exactly $lo"
                else -> "$lo to $hi"
            }

        return Triple(lo, hi, desc)
    }

    /** Modify hook used by validate(): runs after each inject step. */
    val _validation: Modify =
        Modify { pval, key, parent, inj, _ ->
            if (inj == null) return@Modify
            if (pval === SKIP) return@Modify
            val exact = (getprop(inj.meta, "`\$EXACT`", false) == true)
            val cval = getprop(inj.dparent, key)
            if (!exact && (cval === UNDEF || cval == null)) return@Modify

            val ptype = typify(pval)
            if ((T_STRING and ptype) != 0 && pval is String && pval.contains("$")) return@Modify

            val ctype = typify(cval)
            if (ptype != ctype && pval !== UNDEF) {
                inj.errs.add(_invalidTypeMsg(inj.path, typename(ptype), ctype, cval, "V0010"))
                return@Modify
            }

            if (ismap(cval)) {
                if (!ismap(pval)) {
                    inj.errs.add(_invalidTypeMsg(inj.path, typename(ptype), ctype, cval, "V0020"))
                    return@Modify
                }
                val ckeys = keysof(cval)
                val pkeys = keysof(pval)
                if (size(pkeys) > 0 && getprop(pval, "`\$OPEN`") != true) {
                    val badkeys = mutableListOf<String>()
                    // Group B: a key present with a JSON null value is NOT a bad
                    // key, so test raw presence (TS _lookup(pval,ck) === UNDEF).
                    for (ck in ckeys) if (lookup(pval, ck) === UNDEF) badkeys.add(ck)
                    if (badkeys.isNotEmpty()) {
                        inj.errs.add("Unexpected keys at field " + pathify(inj.path, 1) + ": " + badkeys.joinToString(", "))
                    }
                } else {
                    val mergeArgs = mutableListOf<Any?>(pval, cval)
                    merge(mergeArgs)
                    if (isnode(pval)) delprop(pval, "`\$OPEN`")
                }
            } else if (islist(cval)) {
                if (!islist(pval)) {
                    inj.errs.add(_invalidTypeMsg(inj.path, typename(ptype), ctype, cval, "V0030"))
                }
            } else if (exact) {
                if (cval != pval) {
                    val pathmsg = if (size(inj.path) > 1) "at field " + pathify(inj.path, 1) + ": " else ""
                    inj.errs.add("Value " + pathmsg + jsString(cval) + " should equal " + jsString(pval) + ".")
                }
            } else {
                setprop(parent, key, cval)
            }
        }

    /** Custom Injector used by validate(): handles meta-path syntax `<root>$=value` / `<root>$~spec`. */
    val _validatehandler: Injector =
        Injector { inj, value, ref, store ->
            if (ref != null) {
                val m = R_META_PATH.matcher(ref)
                if (m.matches()) {
                    val op = m.group(2)
                    if ("=" == op) {
                        val wrap = mutableListOf<Any?>("`\$EXACT`", value)
                        inj.setval(wrap)
                    } else {
                        inj.setval(value)
                    }
                    inj.keyI = -1
                    return@Injector SKIP
                }
            }
            _injecthandler.apply(inj, value, ref, store)
        }

    fun validate(
        data: Any?,
        spec: Any?,
    ): Any? = validate(data, spec, null)

    /**
     * Canonical TS-faithful validate. Build a store with validate_* injectors plus
     * nulled transform commands, then dispatch via transform() with _validation as
     * modify and _validatehandler as handler. Mirrors Java validate (Struct.java:2903)
     * and TS validate (StructUtility.ts:2347).
     */
    fun validate(
        data: Any?,
        spec: Any?,
        options: Map<String, Any?>?,
    ): Any? {
        val extraRaw = options?.get("extra")
        val errsRaw = options?.get("errs")
        val metaRaw = options?.get("meta")

        val collect = errsRaw is MutableList<*>

        @Suppress("UNCHECKED_CAST")
        val errs: MutableList<Any?> = if (collect) errsRaw as MutableList<Any?> else mutableListOf()

        val baseStore = linkedMapOf<String, Any?>()
        baseStore["\$DELETE"] = null
        baseStore["\$COPY"] = null
        baseStore["\$KEY"] = null
        baseStore["\$META"] = null
        baseStore["\$MERGE"] = null
        baseStore["\$EACH"] = null
        baseStore["\$PACK"] = null

        baseStore["\$STRING"] = validate_STRING
        baseStore["\$NUMBER"] = validate_TYPE
        baseStore["\$INTEGER"] = validate_TYPE
        baseStore["\$DECIMAL"] = validate_TYPE
        baseStore["\$BOOLEAN"] = validate_TYPE
        baseStore["\$NULL"] = validate_TYPE
        baseStore["\$NIL"] = validate_TYPE
        baseStore["\$MAP"] = validate_TYPE
        baseStore["\$LIST"] = validate_TYPE
        baseStore["\$FUNCTION"] = validate_TYPE
        baseStore["\$INSTANCE"] = validate_TYPE
        baseStore["\$ANY"] = validate_ANY
        baseStore["\$CHILD"] = validate_CHILD
        baseStore["\$EXACT"] = validate_EXACT
        baseStore["\$NOF"] = validate_NOF
        baseStore["\$ALL"] = validate_ALL
        baseStore["\$LEN"] = validate_LEN
        baseStore["\$RANGE"] = validate_RANGE

        val mergeList = mutableListOf<Any?>(baseStore)
        if (extraRaw is Map<*, *>) mergeList.add(extraRaw)
        val errsHolder = linkedMapOf<String, Any?>("\$ERRS" to errs)
        mergeList.add(errsHolder)
        val store = merge(mergeList, 1)

        val meta = linkedMapOf<String, Any?>()
        if (metaRaw is Map<*, *>) for ((k, v) in metaRaw) meta[k.toString()] = v
        if (!meta.containsKey("`\$EXACT`")) meta["`\$EXACT`"] = false

        val opts =
            linkedMapOf<String, Any?>(
                "meta" to meta,
                "extra" to store,
                "modify" to _validation,
                "handler" to _validatehandler,
                "errs" to errs,
            )

        // A spec that names an unknown checker validates nothing.
        val numerrs = errs.size
        _checknames(spec, store, emptyList(), errs)

        val out = if (numerrs < errs.size) clone(data) else transform(data, spec, opts)
        if (errs.isNotEmpty() && !collect) {
            throw IllegalArgumentException(errs.joinToString(" | ") { it?.toString() ?: "" })
        }
        return out
    }

    // ===========================================================================
    // Select Injectors
    // ===========================================================================

    /** Build the recursive validate options used by select_*. */
    private fun selectRecOpts(
        store: Any?,
        point: Any?,
        meta: MutableMap<String, Any?>,
        errs: MutableList<Any?>,
    ): MutableMap<String, Any?> {
        val vstore = linkedMapOf<String, Any?>()
        if (store is Map<*, *>) for ((k, v) in store) vstore[k.toString()] = v
        vstore[S_DTOP] = point
        return linkedMapOf("errs" to errs, "meta" to meta, "extra" to vstore)
    }

    /** $AND: require every sub-term to validate against the current point. */
    val select_AND: Injector =
        Injector { inj, _, _, store ->
            if (inj.mode != M_KEYPRE) return@Injector UNDEF
            val terms = lookup(inj.parent, inj.key)
            if (terms !is List<*>) return@Injector UNDEF
            val ppath = slice(inj.path, -1, null)
            val point = getpath(store, ppath)
            for (term in terms) {
                val terrs = mutableListOf<Any?>()
                val opts = selectRecOpts(store, point, inj.meta, terrs)
                try {
                    validate(point, term, opts)
                } catch (e: Exception) {
                    terrs.add(e.message)
                }
                if (terrs.isNotEmpty()) {
                    inj.errs.add("AND:${pathify(ppath)}: ${stringify(point)} fail:${stringify(terms)}")
                }
            }
            val gkey = getelem(inj.path, -2)
            val gp = getelem(inj.nodes, -2)
            setprop(gp, gkey, point)
            UNDEF
        }

    /** $OR: require at least one sub-term to validate. */
    val select_OR: Injector =
        Injector { inj, _, _, store ->
            if (inj.mode != M_KEYPRE) return@Injector UNDEF
            val terms = lookup(inj.parent, inj.key)
            if (terms !is List<*>) return@Injector UNDEF
            val ppath = slice(inj.path, -1, null)
            val point = getpath(store, ppath)
            for (term in terms) {
                val terrs = mutableListOf<Any?>()
                val opts = selectRecOpts(store, point, inj.meta, terrs)
                try {
                    validate(point, term, opts)
                } catch (e: Exception) {
                    terrs.add(e.message)
                }
                if (terrs.isEmpty()) {
                    val gkey = getelem(inj.path, -2)
                    val gp = getelem(inj.nodes, -2)
                    setprop(gp, gkey, point)
                    return@Injector UNDEF
                }
            }
            inj.errs.add("OR:${pathify(ppath)}: ${stringify(point)} fail:${stringify(terms)}")
            UNDEF
        }

    /** $NOT: require the sub-term to fail validation. */
    val select_NOT: Injector =
        Injector { inj, _, _, store ->
            if (inj.mode != M_KEYPRE) return@Injector UNDEF
            val term = lookup(inj.parent, inj.key)
            val ppath = slice(inj.path, -1, null)
            val point = getpath(store, ppath)
            val terrs = mutableListOf<Any?>()
            val opts = selectRecOpts(store, point, inj.meta, terrs)
            try {
                validate(point, term, opts)
            } catch (e: Exception) {
                terrs.add(e.message)
            }
            if (terrs.isEmpty()) {
                inj.errs.add("NOT:${pathify(ppath)}: ${stringify(point)} fail:${stringify(term)}")
            }
            val gkey = getelem(inj.path, -2)
            val gp = getelem(inj.nodes, -2)
            setprop(gp, gkey, point)
            UNDEF
        }

    /** $GT/$LT/$GTE/$LTE/$LIKE comparators dispatched by ref. */
    val select_CMP: Injector =
        Injector { inj, _, ref, store ->
            if (inj.mode != M_KEYPRE) return@Injector UNDEF
            val term = lookup(inj.parent, inj.key)
            val gkey = getelem(inj.path, -2)
            val ppath = slice(inj.path, -1, null)
            val point = getpath(store, ppath)
            var pass = false
            if (point is Number && term is Number) {
                val a = point.toDouble()
                val b = term.toDouble()
                pass =
                    when (ref) {
                        "\$GT" -> a > b
                        "\$LT" -> a < b
                        "\$GTE" -> a >= b
                        "\$LTE" -> a <= b
                        else -> false
                    }
            } else if ("\$LIKE" == ref && term is String) {
                pass =
                    try {
                        Pattern.compile(term).matcher(stringify(point)).find()
                    } catch (_: Exception) {
                        false
                    }
            }
            if (pass) {
                val gp = getelem(inj.nodes, -2)
                setprop(gp, gkey, point)
            } else {
                inj.errs.add("CMP: ${pathify(ppath)}: ${stringify(point)} fail:$ref ${stringify(term)}")
            }
            UNDEF
        }

    /**
     * Canonical TS-faithful select. Tag each child node with $KEY, open the
     * (cloned) query's maps with _openquery, then run validate
     * against each child with the select_* injectors as extras and
     * meta.`$EXACT` = true. Mirrors Java select (Struct.java:2981).
     */
    fun select(
        children: Any?,
        query: Any?,
    ): MutableList<Any?> {
        if (!isnode(children)) return mutableListOf()

        val childList = mutableListOf<Any?>()
        if (ismap(children)) {
            for ((kAny, node) in (children as Map<*, *>)) {
                if (isnode(node)) setprop(node, S_DKEY, kAny.toString())
                childList.add(node)
            }
        } else {
            val cl = children as List<*>
            for (i in cl.indices) {
                val node = cl[i]
                if (isnode(node)) setprop(node, S_DKEY, i.toLong())
                childList.add(node)
            }
        }

        val meta = linkedMapOf<String, Any?>("`\$EXACT`" to true)

        val extra =
            linkedMapOf<String, Any?>(
                "\$AND" to select_AND,
                "\$OR" to select_OR,
                "\$NOT" to select_NOT,
                "\$GT" to select_CMP,
                "\$LT" to select_CMP,
                "\$GTE" to select_CMP,
                "\$LTE" to select_CMP,
                "\$LIKE" to select_CMP,
            )

        val q = clone(query)
        _openquery(q)

        val results = mutableListOf<Any?>()
        for (child in childList) {
            val errs = mutableListOf<Any?>()
            val opts = linkedMapOf<String, Any?>("errs" to errs, "meta" to meta, "extra" to extra)
            try {
                validate(child, clone(q), opts)
            } catch (e: Exception) {
                errs.add(e.message)
            }
            if (errs.isEmpty()) results.add(child)
        }
        return results
    }

    // Open every map in a select query, so a child may hold keys the query does
    // not name, but leave a directive's literals as written: what $EXACT
    // compares, and the count or bound of $NOF, $LEN and $RANGE.
    private fun _openquery(q: Any?) {
        if (q is Map<*, *>) {
            setprop(q, "`\$OPEN`", getprop(q, "`\$OPEN`", true))
            for (key in keysof(q)) {
                _openquery(q[key])
            }
        } else if (q is List<*>) {
            val head = q.firstOrNull()
            val exact = "`\$EXACT`" == head
            val bounded = "`\$NOF`" == head || "`\$LEN`" == head || "`\$RANGE`" == head
            for (i in q.indices) {
                if (0 == i || !(exact || (bounded && 1 == i))) {
                    _openquery(q[i])
                }
            }
        }
    }

    // ===========================================================================
    // Condense
    // ===========================================================================

    private const val CONDENSE_VERSION = 1

    private const val CONDENSE_MAP = 0
    private const val CONDENSE_LIST = 1
    private const val CONDENSE_STR = 2
    private const val CONDENSE_NUM = 3
    private const val CONDENSE_TRUE = 4
    private const val CONDENSE_FALSE = 5
    private const val CONDENSE_NULL = 6

    private const val S_CONDENSE = "\$condense"
    private const val S_CONDSYM = "sym"
    private const val S_CONDNODE = "node"
    private const val S_CONDROOT = "root"

    private const val CONDENSE_IMMUTABLE =
        "struct: condensed structures are immutable - expand() first, then modify the copy"

    // Code point order: String.compareTo uses UTF-16 code unit order, which
    // puts U+FFFF after a supplementary character.
    private fun condenseCmp(
        a: String,
        b: String,
    ): Int {
        var i = 0
        var j = 0
        while (i < a.length && j < b.length) {
            val ca = a.codePointAt(i)
            val cb = b.codePointAt(j)
            if (ca != cb) return if (ca < cb) -1 else 1
            i += Character.charCount(ca)
            j += Character.charCount(cb)
        }
        return a.length - i - (b.length - j)
    }

    fun iscondensed(value: Any?): Boolean {
        // The version must MATCH, not merely be numeric: a future profile would
        // otherwise be decoded under this one's schema.
        if (value !is Map<*, *>) return false
        val version = value[S_CONDENSE]
        return version is Number &&
            CONDENSE_VERSION.toDouble() == version.toDouble() &&
            value[S_CONDSYM] is List<*> &&
            value[S_CONDNODE] is List<*> &&
            value[S_CONDROOT] is Number
    }

    /**
     * Condense any JSON-shaped node. Pure: the same input always produces a
     * byte-identical result, on every port.
     */
    fun condense(value: Any?): MutableMap<String, Any?> {
        val symset = HashSet<String>()
        condenseCollect(value, symset)

        val sym = symset.sortedWith { a, b -> condenseCmp(a, b) }
        val symid = HashMap<String, Int>()
        sym.forEachIndexed { i, s -> symid[s] = i }

        val node = mutableListOf<Any?>()
        val root = condenseBuild(value, symid, node, HashMap())

        return linkedMapOf(
            S_CONDENSE to CONDENSE_VERSION,
            S_CONDSYM to sym.toMutableList<Any?>(),
            S_CONDNODE to node,
            S_CONDROOT to root,
        )
    }

    private fun condenseCollect(
        n: Any?,
        symset: MutableSet<String>,
    ) {
        when (n) {
            is Map<*, *> ->
                for (key in keysof(n)) {
                    symset.add(key)
                    condenseCollect(n[key], symset)
                }
            is List<*> -> for (item in n) condenseCollect(item, symset)
            is String -> symset.add(n)
        }
    }

    // Post-order, so identical subtrees are already interned when a parent
    // refers to them.
    private fun condenseBuild(
        n: Any?,
        symid: Map<String, Int>,
        node: MutableList<Any?>,
        seen: MutableMap<String, Int>,
    ): Int {
        val enc = mutableListOf<Any?>()
        when {
            n is Map<*, *> -> {
                enc.add(CONDENSE_MAP)
                // Code-point order, not keysof's code-unit order, so the key ids ascend.
                for (key in keysof(n).sortedWith { a, b -> condenseCmp(a, b) }) {
                    enc.add(symid[key])
                    enc.add(condenseBuild(n[key], symid, node, seen))
                }
            }
            n is List<*> -> {
                enc.add(CONDENSE_LIST)
                for (item in n) enc.add(condenseBuild(item, symid, node, seen))
            }
            n is String -> {
                enc.add(CONDENSE_STR)
                enc.add(symid[n])
            }
            n is Number -> {
                enc.add(CONDENSE_NUM)
                enc.add(n)
            }
            true == n -> enc.add(CONDENSE_TRUE)
            false == n -> enc.add(CONDENSE_FALSE)
            else -> enc.add(CONDENSE_NULL)
        }
        val enckey = enc.joinToString(",") { condenseNumKey(it as Number) }
        return seen.getOrPut(enckey) {
            node.add(enc)
            node.size - 1
        }
    }

    // By value, so an integer and a decimal that are equal share one node.
    private fun condenseNumKey(n: Number): String {
        if (n is Int || n is Long || n is Short || n is Byte) return n.toLong().toString()
        val d = n.toDouble()
        return if (floor(d) == d && Math.abs(d) < Long.MAX_VALUE) d.toLong().toString() else d.toString()
    }

    private fun condenseList(
        cond: Any?,
        name: String,
    ): List<*> = (cond as? Map<*, *>)?.get(name) as? List<*> ?: emptyList<Any?>()

    private fun condenseAt(
        list: List<*>,
        i: Int,
    ): Any? = if (0 <= i && i < list.size) list[i] else UNDEF

    // A stored index: -1 when negative, past every node when not an integer.
    private fun condenseIndex(n: Any?): Int {
        if (n !is Number) return -1
        val d = n.toDouble()
        if (d.isNaN() || d < 0) return -1
        return if (floor(d) == d && d < Int.MAX_VALUE) d.toInt() else Int.MAX_VALUE
    }

    private fun condenseRoot(cond: Any?): Int = condenseIndex((cond as Map<*, *>)[S_CONDROOT])

    private fun condenseEnc(
        cond: Any?,
        idx: Int,
    ): Any? {
        val enc = condenseAt(condenseList(cond, S_CONDNODE), idx)
        return if (enc === UNDEF) null else enc
    }

    private fun condenseIs(
        enc: Any?,
        kind: Int,
    ): Boolean {
        val tag = (enc as? List<*>)?.firstOrNull()
        return tag is Number && tag.toDouble() == kind.toDouble()
    }

    private fun condenseKey(key: Any?): String =
        when {
            key is String -> key
            key === UNDEF -> "undefined"
            else -> jsString(key)
        }

    // Bisects the sorted symbol table; -1 when the string occurs nowhere.
    private fun condenseSymId(
        cond: Any?,
        key: String,
    ): Int {
        val sym = condenseList(cond, S_CONDSYM)
        var lo = 0
        var hi = sym.size - 1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            val s = sym[mid]
            if (key == s) return mid
            if (0 > condenseCmp(condenseKey(s), key)) lo = mid + 1 else hi = mid - 1
        }
        return -1
    }

    // The node index of key inside node idx, or -1. Touches only this node.
    private fun condenseChild(
        cond: Any?,
        idx: Int,
        key: Any?,
    ): Int {
        val enc = condenseEnc(cond, idx) ?: return -1
        if (key !is String && key !is Number) return -1

        if (condenseIs(enc, CONDENSE_MAP)) {
            val symid = condenseSymId(cond, condenseKey(key))
            if (0 > symid) return -1
            // Pairs live at [1,2], [3,4], ... with keys ascending: bisect the pairs.
            val pairs = enc as List<*>
            var lo = 0
            var hi = (pairs.size - 1) / 2 - 1
            while (lo <= hi) {
                val mid = (lo + hi) ushr 1
                val k = (pairs[1 + mid * 2] as? Number)?.toDouble() ?: Double.NaN
                if (k == symid.toDouble()) return condenseIndex(pairs[2 + mid * 2])
                if (k < symid) lo = mid + 1 else hi = mid - 1
            }
            return -1
        }

        if (condenseIs(enc, CONDENSE_LIST)) {
            val items = enc as List<*>
            val i = listIndex(key)
            if (!(0.0 <= i && i < items.size - 1)) return -1
            return condenseIndex(items[1 + i.toInt()])
        }

        return -1
    }

    private fun condenseResolve(
        cond: Any?,
        idx: Int,
        path: Any?,
    ): Int {
        val parts: List<*> =
            when {
                path is List<*> -> path
                path is String -> if (path.isEmpty()) emptyList<Any?>() else path.split(".")
                null == path || UNDEF === path -> emptyList<Any?>()
                else -> listOf(condenseKey(path))
            }

        var at = idx
        for (part in parts) {
            if (0 > at) return -1
            if ("" == part) continue
            at = condenseChild(cond, at, part)
        }
        return at
    }

    private fun condenseMaterialise(
        cond: Any?,
        idx: Int,
    ): Any? = if (0 > idx) UNDEF else condenseRebuild(condenseList(cond, S_CONDSYM), condenseList(cond, S_CONDNODE), idx)

    // Every call builds new containers, so materialisations never share one.
    private fun condenseRebuild(
        sym: List<*>,
        node: List<*>,
        i: Int,
    ): Any? {
        val enc = condenseAt(node, i)
        if (null == enc || UNDEF === enc) return UNDEF
        if (condenseIs(enc, CONDENSE_MAP)) {
            val pairs = enc as List<*>
            val out = linkedMapOf<String, Any?>()
            for (j in 1 until pairs.size step 2) {
                out[condenseKey(condenseAt(sym, condenseIndex(pairs[j])))] =
                    condenseRebuild(sym, node, condenseIndex(condenseAt(pairs, j + 1)))
            }
            return out
        }
        if (condenseIs(enc, CONDENSE_LIST)) {
            val items = enc as List<*>
            val out = mutableListOf<Any?>()
            for (j in 1 until items.size) out.add(condenseRebuild(sym, node, condenseIndex(items[j])))
            return out
        }
        if (condenseIs(enc, CONDENSE_STR)) return condenseAt(sym, condenseIndex(condenseAt(enc as List<*>, 1)))
        if (condenseIs(enc, CONDENSE_NUM)) return condenseAt(enc as List<*>, 1)
        if (condenseIs(enc, CONDENSE_TRUE)) return true
        if (condenseIs(enc, CONDENSE_FALSE)) return false
        return null
    }

    /**
     * Fully materialise a condensed structure; any other value comes back
     * unchanged. Correct for any caller, but it gives up every benefit of
     * condensing, so prefer a view or a path read.
     */
    fun expand(cond: Any?): Any? {
        if (!iscondensed(cond)) return cond
        return condenseMaterialise(cond, condenseRoot(cond))
    }

    // The keys of node idx, without materialising any of its values.
    private fun condenseKeys(
        cond: Any?,
        idx: Int,
    ): MutableList<String> {
        val enc = condenseEnc(cond, idx)
        val out = mutableListOf<String>()
        if (condenseIs(enc, CONDENSE_MAP)) {
            val sym = condenseList(cond, S_CONDSYM)
            val pairs = enc as List<*>
            for (j in 1 until pairs.size step 2) out.add(condenseKey(condenseAt(sym, condenseIndex(pairs[j]))))
        } else if (condenseIs(enc, CONDENSE_LIST)) {
            for (j in 1 until (enc as List<*>).size) out.add((j - 1).toString())
        }
        return out
    }

    /**
     * A cursor into a condensed structure. Reads resolve by integer index and
     * touch only the nodes on the path, so a lookup costs path depth and result
     * size, never total structure size.
     */
    class CondenseView internal constructor(
        private val cond: Any?,
        private val start: Int,
        private val refmemo: MutableMap<Int, Any?>,
    ) {
        /** The value at path, materialised: a container comes back as an independent copy. */
        fun get(path: Any?): Any? = condenseMaterialise(cond, condenseResolve(cond, start, path))

        fun get(): Any? = get(UNDEF)

        /** Key names at path, with no value decoding at all. */
        fun keys(path: Any?): MutableList<String> {
            val at = condenseResolve(cond, start, path)
            return if (0 > at) mutableListOf() else condenseKeys(cond, at)
        }

        fun keys(): MutableList<String> = keys(UNDEF)

        fun has(path: Any?): Boolean = 0 <= condenseResolve(cond, start, path)

        fun has(): Boolean = has(UNDEF)

        /** A view at path, sharing this view's ref() memo. No decoding happens here. */
        fun at(path: Any?): CondenseView = condenseview(cond, condenseResolve(cond, start, path), refmemo)

        fun at(): CondenseView = at(UNDEF)

        fun value(): Any? = condenseMaterialise(cond, start)

        fun size(): Int {
            val enc = condenseEnc(cond, start)
            if (condenseIs(enc, CONDENSE_MAP)) return ((enc as List<*>).size - 1) / 2
            if (condenseIs(enc, CONDENSE_LIST)) return (enc as List<*>).size - 1
            return 0
        }

        fun exists(): Boolean = 0 <= start

        /**
         * A SHARED materialisation: the same object for the same node, every time.
         * Mutating it corrupts every other reader of that node, including ones
         * reached by a different path, because the structure is a DAG.
         */
        fun ref(): Any? {
            var got = refmemo.getOrDefault(start, UNDEF)
            if (UNDEF === got) {
                got = condenseMaterialise(cond, start)
                refmemo[start] = got
            }
            return got
        }
    }

    fun condenseview(cond: Any?): CondenseView = condenseview(cond, null, null)

    fun condenseview(
        cond: Any?,
        idx: Int?,
    ): CondenseView = condenseview(cond, idx, null)

    fun condenseview(
        cond: Any?,
        idx: Int?,
        memo: MutableMap<Int, Any?>?,
    ): CondenseView {
        val start = idx ?: if (iscondensed(cond)) condenseRoot(cond) else -1
        // The memo is threaded through at(), so every view into one structure
        // hands out the same ref() node.
        return CondenseView(cond, start, memo ?: HashMap())
    }
}
