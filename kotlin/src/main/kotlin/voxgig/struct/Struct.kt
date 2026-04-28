package voxgig.struct

import com.google.gson.Gson
import com.google.gson.GsonBuilder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.IdentityHashMap
import java.util.Locale
import java.util.function.Supplier
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

    private val R_META_PATH = Pattern.compile("^([^$]+)\\$([=~])(.+)$")
    private val R_INJECT_FULL = Pattern.compile("^`(\\$[A-Z]+|[^`]*)[0-9]*`$")
    private val R_INJECT_PART = Pattern.compile("`([^`]+)`")
    private val R_CMD_KEY = Pattern.compile("^`(\\$[A-Z]+)(\\d*)`$")
    private val SKIP: Any = Any()
    private data class MergeCmd(val order: Int, val value: Any?)
    private data class TransformOptions(
        val modify: TransformModify?,
        val commandHandlers: Map<String, Any?>
    )

    fun interface WalkApply {
        fun apply(key: String?, value: Any?, parent: Any?, path: List<String>): Any?
    }

    fun interface PathHandler {
        fun apply(inj: MutableMap<String, Any?>, value: Any?, ref: String, store: Any?): Any?
    }

    fun interface TransformModify {
        fun apply(value: Any?, key: String?, parent: Any?)
    }

    private val TYPE_NAMES = arrayOf(
        "any", "nil", "boolean", "decimal", "integer", "number", "string",
        "function", "symbol", "null",
        "", "", "", "", "", "", "",
        "list", "map", "instance",
        "", "", "", "",
        "scalar", "node"
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
        value is Function<*> || value is Supplier<*>

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
                if (d.isNaN()) T_NOVAL
                else if (floor(d) == d) T_SCALAR or T_NUMBER or T_INTEGER
                else T_SCALAR or T_NUMBER or T_DECIMAL
            }
            is String -> T_SCALAR or T_STRING
            is Boolean -> T_SCALAR or T_BOOLEAN
            is Function<*> -> T_SCALAR or T_FUNCTION
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
        return keysof(value).map { k -> listOf(k, getprop(value, k, UNDEF)) }
    }

    fun getelem(value: Any?, key: Any?): Any? = getelem(value, key, UNDEF)

    fun getelem(value: Any?, key: Any?, alt: Any?): Any? {
        if (value !is List<*> || key == null || key === UNDEF) return resolveAlt(alt)
        val idx = parseIntKey(key) ?: return resolveAlt(alt)
        val useIdx = if (idx < 0) value.size + idx else idx
        if (useIdx < 0 || useIdx >= value.size) return resolveAlt(alt)
        val out = value[useIdx]
        return if (out === UNDEF) alt else out
    }

    fun getprop(value: Any?, key: Any?): Any? = getprop(value, key, UNDEF)

    fun getprop(value: Any?, key: Any?, alt: Any?): Any? {
        if (value == null || value === UNDEF || key == null || key === UNDEF) return alt
        return when (value) {
            is Map<*, *> -> {
                val sk = strkey(key)
                if (value.containsKey(sk)) value[sk] else alt
            }
            is List<*> -> {
                val idx = parseIntKey(key) ?: return alt
                if (idx < 0 || idx >= value.size) alt else value[idx]
            }
            else -> alt
        }
    }

    fun haskey(value: Any?, key: Any?): Boolean = getprop(value, key, UNDEF) !== UNDEF

    fun setprop(parent: Any?, key: Any?, value: Any?): Any? {
        if (!iskey(key)) return parent
        return when (parent) {
            is MutableMap<*, *> -> {
                (parent as MutableMap<String, Any?>)[strkey(key)] = value
                parent
            }
            is MutableList<*> -> {
                val list = parent as MutableList<Any?>
                val idx = parseIntKey(key) ?: return parent
                if (value == null) {
                    if (idx in list.indices) list.removeAt(idx)
                    return list
                }
                if (idx >= 0) {
                    val target = idx.coerceIn(0, list.size)
                    if (target < list.size) list[target] = value else list.add(value)
                } else {
                    list.add(0, value)
                }
                list
            }
            else -> parent
        }
    }

    fun delprop(parent: Any?, key: Any?): Any? {
        if (!iskey(key)) return parent
        return when (parent) {
            is MutableMap<*, *> -> {
                (parent as MutableMap<String, Any?>).remove(strkey(key))
                parent
            }
            is MutableList<*> -> {
                val idx = parseIntKey(key)
                val list = parent as MutableList<Any?>
                if (idx != null && idx in list.indices) list.removeAt(idx)
                list
            }
            else -> parent
        }
    }

    fun clone(value: Any?): Any? = cloneInner(value, IdentityHashMap())

    private fun cloneInner(value: Any?, seen: IdentityHashMap<Any, Any?>): Any? {
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

    fun flatten(value: Any?, depth: Int?): List<Any?> {
        if (value !is List<*>) return emptyList()
        val out = mutableListOf<Any?>()
        flattenInto(value, depth ?: 1, out)
        return out
    }

    private fun flattenInto(input: List<*>, depth: Int, out: MutableList<Any?>) {
        input.forEach {
            if (depth > 0 && it is List<*>) flattenInto(it, depth - 1, out)
            else out.add(it)
        }
    }

    fun filter(value: Any?, check: (List<Any?>) -> Boolean): List<Any?> {
        return items(value).filter { check(it) }.map { it[1] }
    }

    fun escre(s: Any?): String {
        val input = if (s == null || s === UNDEF) "" else s.toString()
        return input.replace(Regex("""([\\.\[\]{}()*+?^$|])"""), """\\$1""")
    }

    fun escurl(s: Any?): String {
        if (s == null || s === UNDEF) return ""
        return URLEncoder.encode(s.toString(), StandardCharsets.UTF_8).replace("+", "%20")
    }

    fun join(arr: Any?, sep: Any?, url: Any?): String {
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

    fun slice(value: Any?, startObj: Any?, endObj: Any?): Any? {
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
                if (end < 0) end = (vlen + end).coerceAtLeast(0)
                else if (vlen < end) end = vlen
            } else end = vlen
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

    fun pad(value: Any?, paddingObj: Any?, padcharObj: Any?): String {
        val s = if (value is String) value else stringify(value)
        val padding = if (paddingObj is Number) floor(paddingObj.toDouble()).toInt() else 44
        val pc = ((padcharObj?.toString() ?: " ") + " ").substring(0, 1)
        return if (padding >= 0) s + pc.repeat((padding - s.length).coerceAtLeast(0))
        else pc.repeat((-padding - s.length).coerceAtLeast(0)) + s
    }

    fun stringify(value: Any?): String = stringify(value, null)

    fun stringify(value: Any?, maxlen: Int?): String {
        val out = when {
            value === UNDEF -> ""
            value is String -> value
            else -> try {
                stringifyStable(value, IdentityHashMap())
            } catch (_: Exception) {
                "__STRINGIFY_FAILED__"
            }
        }
        return if (maxlen != null && maxlen >= 0 && out.length > maxlen) out.substring(0, (maxlen - 3).coerceAtLeast(0)) + "..." else out
    }

    private fun stringifyStable(value: Any?, seen: IdentityHashMap<Any, Boolean>): String {
        if (value == null) return "null"
        if (value is String) return value
        if (value is Number) return numstr(value)
        if (value is Boolean || value is Function<*>) return value.toString()
        if (seen.containsKey(value)) throw IllegalStateException("cycle")
        seen[value] = true
        return when (value) {
            is List<*> -> {
                val parts = value.map { stringifyStable(it, seen) }
                seen.remove(value); "[" + parts.joinToString(",") + "]"
            }
            is Map<*, *> -> {
                val keys = value.keys.map { it.toString() }.sorted()
                val parts = keys.map { "$it:${stringifyStable((value as Map<String, Any?>)[it], seen)}" }
                seen.remove(value); "{" + parts.joinToString(",") + "}"
            }
            else -> {
                seen.remove(value); value.toString()
            }
        }
    }

    fun jsonify(value: Any?): String = jsonify(value, null)

    fun jsonify(value: Any?, flags: Any?): String {
        if (value === UNDEF) return "null"
        var indent = 2
        var offset = 0
        if (flags is Map<*, *>) {
            val iv = flags["indent"]; val ov = flags["offset"]
            if (iv is Number) indent = iv.toInt()
            if (ov is Number) offset = ov.toInt()
        }
        return try {
            val safe = toJsonSafe(value, IdentityHashMap())
            val gson = if (indent > 0) GsonBuilder().setPrettyPrinting().create() else GsonBuilder().create()
            var out = gson.toJson(safe) ?: "null"
            if (indent != 2 && indent > 0) out = rewriteIndent(out, indent)
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

    private fun rewriteIndent(pretty: String, indent: Int): String {
        return pretty.split("\n").joinToString("\n") { line ->
            val spaces = line.takeWhile { it == ' ' }.length
            val level = spaces / 2
            " ".repeat(level * indent) + line.drop(spaces)
        }
    }

    private fun toJsonSafe(value: Any?, seen: IdentityHashMap<Any, Boolean>): Any? {
        if (value == null || value === UNDEF) return null
        if (value is String || value is Boolean) return value
        if (value is Number) return jsonNumber(value)
        if (value is Function<*>) return null
        if (seen.containsKey(value)) return null
        seen[value] = true
        return when (value) {
            is List<*> -> {
                val out = value.map { toJsonSafe(it, seen) }
                seen.remove(value); out
            }
            is Map<*, *> -> {
                val out = linkedMapOf<String, Any?>()
                value.forEach { (k, v) -> out[k.toString()] = toJsonSafe(v, seen) }
                seen.remove(value); out
            }
            else -> {
                seen.remove(value); null
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
    fun pathify(value: Any?, from: Any?): String = pathify(value, from, null)

    fun pathify(value: Any?, startIn: Any?, endIn: Any?): String {
        val start = if (startIn is Number) startIn.toInt().coerceAtLeast(0) else 0
        val end = if (endIn is Number) endIn.toInt().coerceAtLeast(0) else 0
        val path: MutableList<Any?>? = when (value) {
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

    fun setpath(store: Any?, path: Any?, value: Any?): Any? {
        val parts: MutableList<Any?> = when (path) {
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

    fun walk(value: Any?, apply: WalkApply): Any? = walk(value, apply, null, 32)
    fun walk(value: Any?, before: WalkApply?, after: WalkApply?): Any? = walk(value, before, after, 32)
    fun walk(value: Any?, before: WalkApply?, after: WalkApply?, maxdepth: Int): Any? {
        return walkDescend(value, before, after, maxdepth, null, null, mutableListOf())
    }

    private fun walkDescend(
        value: Any?,
        before: WalkApply?,
        after: WalkApply?,
        maxdepth: Int,
        key: String?,
        parent: Any?,
        path: MutableList<String>
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

    fun merge(value: Any?, maxdepthIn: Int): Any? {
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
                val before = WalkApply { key, v, _, path ->
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
                        cur[pI] = when {
                            tval == null && (typify(v) and T_INSTANCE) == 0 -> if (islist(v)) mutableListOf<Any?>() else linkedMapOf<String, Any?>()
                            typify(v) == typify(tval) -> tval
                            else -> v
                        }
                    }
                    v
                }
                val after = WalkApply { key, _, _, path ->
                    val cI = path.size
                    if (key == null || cI <= 0) return@WalkApply cur[0]
                    val v = cur[cI]
                    cur[cI - 1] = setprop(cur[cI - 1], key, v)
                    v
                }
                walk(obj, before, after, md)
                out = cur[0]
            }
        }
        if (md == 0) {
            out = getelem(value, -1)
            if (out is List<*>) out = mutableListOf<Any?>()
            else if (out is Map<*, *>) out = linkedMapOf<String, Any?>()
        }
        return out
    }

    fun getpath(store: Any?, path: Any?): Any? = getpath(store, path, null)

    fun getpath(store: Any?, path: Any?, inj: MutableMap<String, Any?>?): Any? {
        val parts = pathParts(path)
        var value = getpathInner(store, path, parts, inj)
        val handler = inj?.get("handler")
        if (handler is PathHandler) {
            value = handler.apply(inj, value, pathifyForHandler(path), store)
        }
        return value
    }

    fun inject(value: Any?, store: Any?): Any? = inject(value, store, null)

    fun inject(value: Any?, store: Any?, inj: MutableMap<String, Any?>?): Any? {
        if (value === UNDEF || value == null) return null
        return when (value) {
            is Map<*, *> -> {
                val out = linkedMapOf<String, Any?>()
                value.forEach { (k, v) -> out[k.toString()] = inject(v, store, inj) }
                out
            }
            is List<*> -> value.map { inject(it, store, inj) }.toMutableList()
            is String -> injectString(value, store, inj)
            else -> value
        }
    }

    private fun injectString(value: String, store: Any?, inj: MutableMap<String, Any?>?): Any? {
        if (value.isEmpty()) return ""
        val full = R_INJECT_FULL.matcher(value)
        if (full.matches()) {
            val pathref = unescapeInjectRef(full.group(1))
            return getpath(store, pathref, inj)
        }
        val matcher = R_INJECT_PART.matcher(value)
        val out = StringBuilder()
        var cursor = 0
        while (matcher.find()) {
            out.append(value, cursor, matcher.start())
            val ref = unescapeInjectRef(matcher.group(1))
            val found = getpath(store, ref, inj)
            out.append(injectPartialText(found))
            cursor = matcher.end()
        }
        out.append(value.substring(cursor))
        return out.toString()
    }

    fun transform(data: Any?, spec: Any?): Any? = transform(data, spec, null)

    fun transform(data: Any?, spec: Any?, options: Map<String, Any?>?): Any? {
        var useData = data
        var modify: TransformModify? = null
        val handlers = linkedMapOf<String, Any?>()
        if (options != null) {
            val m = options["modify"]
            if (m is TransformModify) modify = m
            val extra = options["extra"] as? Map<*, *>
            if (extra != null) {
                val extraData = linkedMapOf<String, Any?>()
                for ((kAny, v) in extra) {
                    val k = kAny.toString()
                    if (k.startsWith("$")) handlers[k] = v else extraData[k] = v
                }
                if (useData is Map<*, *>) {
                    useData = merge(listOf(extraData, useData), 1)
                } else if (extraData.isNotEmpty() && useData == null) {
                    useData = extraData
                }
            }
        }
        val opts = TransformOptions(modify, handlers)
        return transformInner(useData, spec, useData, useData, mutableListOf(), null, spec, linkedSetOf(), opts)
    }

    private fun transformInner(
        data: Any?,
        spec: Any?,
        currentData: Any?,
        dparent: Any?,
        dpath: MutableList<String>,
        keySpec: Any?,
        rootSpec: Any?,
        refGuard: MutableSet<String>,
        opts: TransformOptions?
    ): Any? {
        if (spec === UNDEF || spec == null) return null
        if (spec is String) return transformString(data, spec, dparent, dpath, keySpec, opts)
        if (spec is Map<*, *>) {
            val out = linkedMapOf<String, Any?>()
            val normalEntries = mutableListOf<Pair<String, Any?>>()
            val mergeCmds = mutableListOf<MergeCmd>()
            val packCmds = mutableListOf<Any?>()
            var localKeySpec = keySpec
            for ((kAny, vSpec) in spec) {
                val key = kAny.toString()
                val cmd = R_CMD_KEY.matcher(key)
                if (cmd.matches()) {
                    if (cmd.group(1) == "\$MERGE") {
                        val suffix = cmd.group(2)
                        val order = if (suffix.isNullOrEmpty()) 0 else suffix.toInt()
                        mergeCmds.add(MergeCmd(order, vSpec))
                    } else if (cmd.group(1) == "\$PACK") {
                        packCmds.add(vSpec)
                    } else if (cmd.group(1) == "\$KEY") {
                        val ks = transformInner(data, vSpec, currentData, dparent, dpath, keySpec, rootSpec, refGuard, opts)
                        if (ks !== SKIP && ks !== UNDEF && ks != null) localKeySpec = ks
                    }
                    continue
                }
                normalEntries.add(key to vSpec)
            }

            mergeCmds.sortByDescending { it.order }
            for (mc in mergeCmds) {
                val resolvedArg = transformInner(data, mc.value, currentData, dparent, dpath, localKeySpec, rootSpec, refGuard, opts)
                val merged = applyMergeCommand(out, resolvedArg)
                out.clear()
                out.putAll(merged)
            }
            for (packArg in packCmds) {
                val packed = applyPackCommand(data, packArg, localKeySpec, rootSpec, refGuard, opts)
                out.putAll(packed)
            }

            for ((key, vSpec) in normalEntries) {
                val childData = getprop(currentData, key, null)
                val childPath = dpath.toMutableList().apply { add(key) }
                val child = transformInner(data, vSpec, childData, currentData ?: dparent, childPath, localKeySpec, rootSpec, refGuard, opts)
                if (child !== SKIP) {
                    out[key] = child
                    opts?.modify?.apply(out[key], key, out)
                }
            }
            return out
        }
        if (spec is List<*>) {
            val eachCmd = extractFullCommand(getelem(spec, 0))
            if (eachCmd == "\$FORMAT" && spec.size >= 3) {
                val nameObj = transformInner(data, clone(spec[1]), currentData, dparent, dpath, keySpec, rootSpec, refGuard, opts)
                val child = transformInner(data, clone(spec[2]), currentData, dparent, dpath, keySpec, rootSpec, refGuard, opts)
                return applyFormatCommand(nameObj, child)
            }
            if (eachCmd == "\$APPLY" && spec.size >= 3) {
                val fnObj = transformInner(data, clone(spec[1]), currentData, dparent, dpath, keySpec, rootSpec, refGuard, opts)
                val child = transformInner(data, clone(spec[2]), currentData, dparent, dpath, keySpec, rootSpec, refGuard, opts)
                return when (fnObj) {
                    is java.util.function.Function<*, *> -> (fnObj as java.util.function.Function<Any?, Any?>).apply(child)
                    is Function1<*, *> -> (fnObj as (Any?) -> Any?).invoke(child)
                    else -> SKIP
                }
            }
            if (eachCmd == "\$REF" && spec.size >= 2) {
                val refPath = spec[1]?.toString() ?: ""
                if (currentData == null && shouldSkipRefOnMissingData(refPath, dpath)) return SKIP
                val guardKey = "$refPath#${System.identityHashCode(currentData)}"
                if (refGuard.contains(guardKey)) return SKIP
                val refSpec = getpath(rootSpec, refPath)
                if (refSpec == null || refSpec === UNDEF) return SKIP
                refGuard.add(guardKey)
                val out = transformInner(data, clone(refSpec), currentData, dparent, dpath, keySpec, rootSpec, refGuard, opts)
                refGuard.remove(guardKey)
                if (currentData == null && out is Map<*, *> && out.isEmpty()) return SKIP
                return out
            }
            if (eachCmd == "\$EACH" && spec.size >= 3) {
                val srcPathObj = spec[1]
                val template = spec[2]
                val srcPath = srcPathObj?.toString() ?: ""
                val src = when {
                    srcPath.isEmpty() -> data
                    srcPath == "." -> currentData
                    else -> getpath(data, srcPath)
                }
                val srcParts = if (srcPath.isEmpty()) mutableListOf<String>() else srcPath.split(".").toMutableList()
                val out = mutableListOf<Any?>()
                if (src is List<*>) {
                    for (i in src.indices) {
                        val item = src[i]
                        val itemPath = srcParts.toMutableList().apply { add(strkey(i)) }
                        val mapped = transformInner(data, clone(template), item, item, itemPath, keySpec, rootSpec, refGuard, opts)
                        if (mapped !== SKIP) out.add(mapped)
                    }
                } else if (src is Map<*, *>) {
                    for ((kAny, item) in src) {
                        val k = kAny.toString()
                        val itemPath = srcParts.toMutableList().apply { add(k) }
                        val mapped = transformInner(data, clone(template), item, item, itemPath, keySpec, rootSpec, refGuard, opts)
                        if (mapped !== SKIP) out.add(mapped)
                    }
                }
                return out
            }
            val out = mutableListOf<Any?>()
            for (i in spec.indices) {
                val childData = getprop(currentData, i, null)
                val childPath = dpath.toMutableList().apply { add(strkey(i)) }
                val child = transformInner(data, spec[i], childData, currentData ?: dparent, childPath, keySpec, rootSpec, refGuard, opts)
                if (child !== SKIP) {
                    out.add(child)
                    opts?.modify?.apply(out.last(), strkey(out.lastIndex), out)
                }
            }
            return out
        }
        return clone(spec)
    }

    private fun shouldSkipRefOnMissingData(refPath: String, dpath: MutableList<String>?): Boolean {
        if (refPath.isEmpty() || dpath == null || dpath.isEmpty()) return false
        val parts = refPath.split(".")
        if (parts.size > dpath.size) return false
        for (i in parts.indices) {
            if (parts[i] != dpath[i]) return false
        }
        return true
    }

    private fun applyFormatCommand(nameObj: Any?, resolved: Any?): Any? {
        if (nameObj !is String) return SKIP
        return when (nameObj) {
            "identity" -> resolved
            "concat" -> formatConcat(resolved)
            "upper" -> formatDeep(resolved, "upper")
            "lower" -> formatDeep(resolved, "lower")
            "string" -> formatDeep(resolved, "string")
            "number" -> formatDeep(resolved, "number")
            "integer" -> formatDeep(resolved, "integer")
            else -> SKIP
        }
    }

    private fun formatConcat(value: Any?): Any? {
        if (value !is List<*>) return value
        val out = StringBuilder()
        for (item in value) {
            if (isnode(item)) continue
            out.append(formatStringScalar(item))
        }
        return out.toString()
    }

    private fun formatDeep(value: Any?, mode: String): Any? {
        if (value is List<*>) {
            val out = mutableListOf<Any?>()
            for (item in value) out.add(formatDeep(item, mode))
            return out
        }
        if (value is Map<*, *>) {
            val out = linkedMapOf<String, Any?>()
            value.forEach { (k, v) -> out[k.toString()] = formatDeep(v, mode) }
            return out
        }
        return formatScalar(value, mode)
    }

    private fun formatScalar(value: Any?, mode: String): Any? {
        val sv = formatStringScalar(value)
        return when (mode) {
            "upper" -> sv.uppercase(Locale.ROOT)
            "lower" -> sv.lowercase(Locale.ROOT)
            "string" -> sv
            "number" -> formatNumberScalar(value, false)
            "integer" -> formatNumberScalar(value, true)
            else -> value
        }
    }

    private fun formatStringScalar(value: Any?): String {
        if (value == null || value === UNDEF) return "null"
        if (value is String) return value
        if (value is Number || value is Boolean) return stringify(value)
        return value.toString()
    }

    private fun formatNumberScalar(value: Any?, integerOnly: Boolean): Any {
        if (value is Number) {
            val d = value.toDouble()
            if (integerOnly) return d.toLong()
            if (floor(d) == d) return d.toLong()
            return d
        }
        if (value is String) {
            return try {
                val d = value.toDouble()
                if (integerOnly || floor(d) == d) d.toLong() else d
            } catch (_: Exception) {
                0L
            }
        }
        return 0L
    }

    private fun transformString(
        data: Any?,
        spec: String,
        dparent: Any?,
        dpath: MutableList<String>,
        keySpec: Any?,
        opts: TransformOptions?
    ): Any? {
        if (spec.isEmpty()) return ""
        val store = linkedMapOf<String, Any?>(S_DTOP to data)
        val inj = linkedMapOf<String, Any?>(
            "base" to S_DTOP,
            "dparent" to dparent,
            "dpath" to dpath
        )
        val full = R_INJECT_FULL.matcher(spec)
        if (full.matches()) {
            val ref = unescapeInjectRef(full.group(1)) ?: ""
            val custom = resolveCustomTransformCommand(ref, dparent, dpath, opts)
            val dot = if (custom === UNDEF) resolveDotRelativeRef(ref, dparent, data) else UNDEF
            val cmd = if (custom === UNDEF && dot === UNDEF) resolveTransformRef(ref, dparent, dpath, keySpec) else UNDEF
            val out = when {
                custom !== UNDEF -> custom
                dot !== UNDEF -> dot
                cmd !== UNDEF -> cmd
                else -> getpath(store, ref, inj)
            }
            return if (out == null || out === UNDEF) SKIP else out
        }
        val matcher = R_INJECT_PART.matcher(spec)
        val out = StringBuilder()
        var cursor = 0
        while (matcher.find()) {
            out.append(spec, cursor, matcher.start())
            val ref = unescapeInjectRef(matcher.group(1)) ?: ""
            val custom = resolveCustomTransformCommand(ref, dparent, dpath, opts)
            val dot = if (custom === UNDEF) resolveDotRelativeRef(ref, dparent, data) else UNDEF
            val cmd = if (custom === UNDEF && dot === UNDEF) resolveTransformRef(ref, dparent, dpath, keySpec) else UNDEF
            val found = when {
                custom !== UNDEF -> custom
                dot !== UNDEF -> dot
                cmd !== UNDEF -> cmd
                else -> getpath(store, ref, inj)
            }
            out.append(injectPartialText(found))
            cursor = matcher.end()
        }
        out.append(spec.substring(cursor))
        return out.toString()
    }

    private fun resolveTransformRef(ref: String, dparent: Any?, dpath: MutableList<String>, keySpec: Any?): Any? {
        if (!ref.startsWith("$")) return UNDEF
        if (ref.startsWith("\$BT")) return "`"
        if (ref.startsWith("\$DS")) return "$"
        if (ref.startsWith("\$DELETE")) return SKIP
        if (ref.startsWith("\$COPY")) {
            if (dpath.isEmpty()) return dparent
            if (!isnode(dparent)) return dparent
            val key = dpath.last()
            return getprop(dparent, key)
        }
        if (ref.startsWith("\$KEY")) {
            if (keySpec != null && keySpec !== UNDEF) {
                return getprop(dparent, keySpec)
            }
            if (dpath.isEmpty()) return null
            return if (dpath.size >= 2) dpath[dpath.size - 2] else dpath[0]
        }
        return UNDEF
    }

    private fun resolveCustomTransformCommand(
        ref: String,
        dparent: Any?,
        dpath: MutableList<String>,
        opts: TransformOptions?
    ): Any? {
        if (opts == null || !ref.startsWith("$")) return UNDEF
        val handler = opts.commandHandlers[ref]
        val state = linkedMapOf<String, Any?>("path" to dpath.toMutableList(), "dparent" to dparent)
        return when (handler) {
            is java.util.function.Function<*, *> -> (handler as java.util.function.Function<Any?, Any?>).apply(state)
            is Function1<*, *> -> (handler as (Any?) -> Any?).invoke(state)
            else -> UNDEF
        }
    }

    private fun resolveDotRelativeRef(ref: String, dparent: Any?, data: Any?): Any? {
        if (ref.startsWith("...")) {
            var rem = ref.substring(3)
            while (rem.startsWith(".")) rem = rem.substring(1)
            if (rem.isEmpty()) return data
            return getpath(data, rem)
        }
        if (ref.startsWith("..")) {
            var rem = ref.substring(2)
            while (rem.startsWith(".")) rem = rem.substring(1)
            if (rem.isEmpty()) return dparent
            return getpath(dparent, rem)
        }
        return UNDEF
    }

    private fun extractFullCommand(value: Any?): String? {
        if (value !is String) return null
        val full = R_INJECT_FULL.matcher(value)
        if (!full.matches()) return null
        val ref = unescapeInjectRef(full.group(1))
        return if (ref != null && ref.startsWith("$")) ref else null
    }

    private fun applyMergeCommand(current: LinkedHashMap<String, Any?>, resolvedArg: Any?): LinkedHashMap<String, Any?> {
        val mergeArgs = mutableListOf<Any?>()
        mergeArgs.add(current)
        when (resolvedArg) {
            is List<*> -> mergeArgs.addAll(resolvedArg)
            null, UNDEF, SKIP -> {}
            else -> mergeArgs.add(resolvedArg)
        }
        val merged = merge(mergeArgs)
        if (merged is Map<*, *>) {
            val out = linkedMapOf<String, Any?>()
            merged.forEach { (k, v) -> out[k.toString()] = v }
            return out
        }
        return current
    }

    private fun applyPackCommand(
        data: Any?,
        packArg: Any?,
        inheritedKeySpec: Any?,
        rootSpec: Any?,
        refGuard: MutableSet<String>,
        opts: TransformOptions?
    ): LinkedHashMap<String, Any?> {
        if (packArg !is List<*> || packArg.size < 2) return linkedMapOf()
        val srcPath = packArg[0]?.toString() ?: ""
        val childSpecRaw = packArg[1]
        val src = if (srcPath.isEmpty()) data else getpath(data, srcPath)
        val srcParts = if (srcPath.isEmpty()) mutableListOf<String>() else srcPath.split(".").toMutableList()

        val childMap = childSpecRaw as? Map<*, *>
        var packKeySpec: Any? = null
        var valueSpec: Any? = null
        var baseTemplate: Any? = childSpecRaw

        if (childMap != null) {
            val template = linkedMapOf<String, Any?>()
            childMap.forEach { (kAny, v) -> template[kAny.toString()] = v }
            for ((k, v) in childMap) {
                val m = R_CMD_KEY.matcher(k.toString())
                if (!m.matches()) continue
                if (m.group(1) == "\$KEY") {
                    packKeySpec = v
                    template.remove(k.toString())
                } else if (m.group(1) == "\$VAL") {
                    valueSpec = v
                    template.remove(k.toString())
                }
            }
            baseTemplate = template
        }

        val out = linkedMapOf<String, Any?>()
        if (src is List<*>) {
            for (i in src.indices) {
                val item = src[i]
                val itemPath = srcParts.toMutableList().apply { add(strkey(i)) }
                putPackedItem(out, data, item, itemPath, packKeySpec, inheritedKeySpec, valueSpec, baseTemplate, strkey(i), rootSpec, refGuard, opts)
            }
        } else if (src is Map<*, *>) {
            for ((kAny, item) in src) {
                val k = kAny.toString()
                val itemPath = srcParts.toMutableList().apply { add(k) }
                putPackedItem(out, data, item, itemPath, packKeySpec, inheritedKeySpec, valueSpec, baseTemplate, k, rootSpec, refGuard, opts)
            }
        }
        return out
    }

    private fun putPackedItem(
        out: LinkedHashMap<String, Any?>,
        data: Any?,
        item: Any?,
        itemPath: MutableList<String>,
        packKeySpec: Any?,
        inheritedKeySpec: Any?,
        valueSpec: Any?,
        baseTemplate: Any?,
        fallbackKey: String,
        rootSpec: Any?,
        refGuard: MutableSet<String>,
        opts: TransformOptions?
    ) {
        var kObj: Any? = fallbackKey
        if (packKeySpec != null && packKeySpec !== UNDEF) {
            if (packKeySpec is String) {
                val full = R_INJECT_FULL.matcher(packKeySpec)
                kObj = if (full.matches()) transformInner(data, clone(packKeySpec), item, item, itemPath, inheritedKeySpec, rootSpec, refGuard, opts)
                else getpath(item, packKeySpec)
            } else {
                kObj = transformInner(data, clone(packKeySpec), item, item, itemPath, inheritedKeySpec, rootSpec, refGuard, opts)
            }
        }
        val outKey = kObj?.toString() ?: ""
        if (outKey.isEmpty()) return
        val bodyPath = itemPath.toMutableList().also {
            if (usesFullCopyCommand(packKeySpec) && it.isNotEmpty()) {
                it[it.lastIndex] = outKey
            }
        }
        val outVal = if (valueSpec != null) {
            transformInner(data, clone(valueSpec), item, item, bodyPath, inheritedKeySpec, rootSpec, refGuard, opts)
        } else {
            transformInner(data, clone(baseTemplate), item, item, bodyPath, inheritedKeySpec, rootSpec, refGuard, opts)
        }
        if (outVal !== SKIP) out[outKey] = outVal
    }

    private fun usesFullCopyCommand(spec: Any?): Boolean {
        if (spec !is String) return false
        val m = R_INJECT_FULL.matcher(spec)
        if (!m.matches()) return false
        val ref = unescapeInjectRef(m.group(1))
        return ref == "\$COPY"
    }

    private fun pathifyForHandler(path: Any?): String {
        return when (path) {
            null -> pathify(UNDEF)
            is String, is List<*>, is Number -> pathify(path)
            else -> pathify(path)
        }
    }

    private fun pathParts(path: Any?): MutableList<String>? {
        return when (path) {
            is String -> if (path.isEmpty()) mutableListOf("") else path.split(".").toMutableList()
            is List<*> -> path.map {
                when (it) {
                    is String -> it
                    is Number -> strkey(it)
                    else -> strkey(it)
                }
            }.toMutableList()
            else -> null
        }
    }

    private fun getpathInner(store: Any?, pathOrig: Any?, parts: MutableList<String>?, inj: MutableMap<String, Any?>?): Any? {
        if (parts == null) return null
        val base = inj?.get("base")
        val src = getprop(store, base, store)
        val dparent = inj?.get("dparent")
        val dpath = when (val dp = inj?.get("dpath")) {
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
                            ascends++; pI++
                        }
                        if (inj != null && ascends > 0) {
                            if (pI == numparts - 1) ascends--
                            if (ascends == 0) value = dparent
                            else if (dpath != null) {
                                val cutLen = (dpath.size - ascends).coerceAtLeast(0)
                                val fullpath = mutableListOf<String>()
                                for (i in 0 until cutLen) fullpath.add(dpath[i])
                                if (pI + 1 < numparts) for (j in pI + 1 until numparts) fullpath.add(parts[j])
                                value = if (ascends <= size(dpath)) getpath(store, fullpath) else null
                                break
                            }
                        } else value = dparent
                    } else {
                        value = getprop(value, part)
                    }
                    pI++
                }
            }
        }
        return value
    }

    private fun parseIntKey(key: Any?): Int? {
        return when (key) {
            is Number -> floor(key.toDouble()).toInt()
            is String -> key.toIntOrNull()
            else -> null
        }
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
            val safe = toJsonSafe(found, IdentityHashMap())
            return Gson().toJson(safe)
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

    fun validate(data: Any?, spec: Any?): Any? = validate(data, spec, null)

    fun validate(data: Any?, spec: Any?, options: Map<String, Any?>?): Any? {
        val opts = linkedMapOf<String, Any?>()
        if (options != null) opts.putAll(options)
        val errsObj = opts["errs"]
        val collect = errsObj is MutableList<*>
        @Suppress("UNCHECKED_CAST")
        val errs = if (errsObj is MutableList<*>) errsObj as MutableList<String> else mutableListOf()
        if (!collect) opts["errs"] = errs
        opts["__topdata__"] = data
        opts["__topspec__"] = spec
        val out = validateNode(data, spec, mutableListOf(), opts, null)
        if (errs.isNotEmpty() && !collect) {
            throw IllegalArgumentException(errs.joinToString(" | "))
        }
        return out
    }

    private fun validateNode(
        data: Any?,
        spec: Any?,
        path: MutableList<String>,
        options: MutableMap<String, Any?>,
        dparent: Any?
    ): Any? {
        @Suppress("UNCHECKED_CAST")
        val errs = options["errs"] as MutableList<String>
        val meta = (options["meta"] as? Map<*, *>)?.let {
            val m = linkedMapOf<String, Any?>()
            it.forEach { (k, v) -> m[k.toString()] = v }
            m
        } ?: linkedMapOf()

        if (spec === UNDEF) return data
        if (spec == null) return if (data === UNDEF) null else data

        if (spec is String) {
            val cmd = extractFullCommand(spec)
            if (cmd != null) {
                val extra = options["extra"] as? Map<*, *>
                if (extra != null && extra.containsKey(cmd)) {
                    val fn = extra[cmd]
                    val inj = linkedMapOf<String, Any?>(
                        "key" to (if (path.isEmpty()) null else path.last()),
                        "path" to path.toMutableList(),
                        "dparent" to dparent,
                        "errs" to errs
                    )
                    val out = when (fn) {
                        is java.util.function.Function<*, *> -> (fn as java.util.function.Function<Any?, Any?>).apply(inj)
                        is Function1<*, *> -> (fn as (Any?) -> Any?).invoke(inj)
                        else -> null
                    }
                    return out ?: data
                }

                when (cmd) {
                    "\$ANY" -> return data
                    "\$STRING" -> {
                        if (data == null || data === UNDEF || data !is String) errs.add(expectedMsg(path, "string", data))
                        else if (data.isEmpty()) errs.add("Empty string at ${pathify(path)}")
                        return data
                    }
                    "\$NUMBER" -> {
                        if (data !is Number) errs.add(expectedMsg(path, "number", data)); return data
                    }
                    "\$INTEGER" -> {
                        if (data !is Number || floor(data.toDouble()) != data.toDouble()) errs.add(expectedMsg(path, "integer", data)); return data
                    }
                    "\$DECIMAL" -> {
                        if (data !is Number || floor(data.toDouble()) == data.toDouble()) errs.add(expectedMsg(path, "decimal", data)); return data
                    }
                    "\$BOOLEAN" -> {
                        if (data !is Boolean) errs.add(expectedMsg(path, "boolean", data)); return data
                    }
                    "\$MAP", "\$OBJECT" -> {
                        if (data !is Map<*, *>) errs.add(expectedMsg(path, "map", data)); return data
                    }
                    "\$LIST", "\$ARRAY" -> {
                        if (data !is List<*>) errs.add(expectedMsg(path, "list", data)); return data
                    }
                    "\$NULL" -> {
                        if (data != null) errs.add(expectedMsg(path, "null", data)); return data
                    }
                    "\$NIL" -> {
                        if (!(data == null || data === UNDEF)) errs.add(expectedMsg(path, "nil", data)); return data
                    }
                    "\$FUNCTION" -> {
                        if (!isfunc(data)) errs.add(expectedMsg(path, "function", data)); return data
                    }
                    "\$INSTANCE" -> {
                        if (data == null || data === UNDEF || data is String || data is Number || data is Boolean || data is Map<*, *> || data is List<*> || isfunc(data)) {
                            errs.add(expectedMsg(path, "instance", data))
                        }
                        return data
                    }
                }
                return data
            }

            val m = Regex("^`([^`$]+)\\$(=|~)([^`]+)`$").matchEntire(spec)
            if (m != null) {
                val mroot = m.groupValues[1]
                val op = m.groupValues[2]
                val mpath = m.groupValues[3]
                val mv = getpath(meta, "$mroot.$mpath")
                if (op == "=") {
                    if (!deepEqualNode(data, mv)) errs.add(expectedExactMsg(path, mv, data))
                } else {
                    val mt = typify(mv)
                    val dt = typify(data)
                    if (mt != dt) errs.add(expectedMsg(path, typename(mt), data))
                }
                return data
            }

            if (spec.length >= 2 && spec.startsWith("`") && spec.endsWith("`")) {
                val raw = spec.substring(1, spec.length - 1)
                val ref = unescapeInjectRef(raw)
                if (ref != null && !ref.startsWith("$")) {
                    if (data !== UNDEF) return data
                    val store = linkedMapOf<String, Any?>(S_DTOP to options["__topdata__"])
                    val inj = linkedMapOf<String, Any?>("base" to S_DTOP)
                    val resolved = getpath(store, ref, inj)
                    return if (resolved === UNDEF) spec else resolved
                }
            }

            if (data === UNDEF) return spec
            val exact = meta["`\$EXACT`"] == true || meta["\$EXACT"] == true
            if (exact) {
                if (data != spec) errs.add(valueEqualMsg(path, data, spec))
            } else if (data !is String) {
                errs.add(expectedMsg(path, "string", data))
            }
            return data
        }

        if (spec is Map<*, *>) {
            val specMap = linkedMapOf<String, Any?>().also { spec.forEach { (k, v) -> it[k.toString()] = v } }
            var out = if (data is Map<*, *>) {
                linkedMapOf<String, Any?>().also { data.forEach { (k, v) -> it[k.toString()] = v } }
            } else linkedMapOf()

            var childTemplate: Any? = null
            for ((k, v) in specMap) {
                if (extractFullCommand(k) == "\$CHILD") childTemplate = v
            }
            if (childTemplate != null && data is Map<*, *>) {
                out = linkedMapOf()
                for ((kAny, v) in data) {
                    val k = kAny.toString()
                    val cpath = path.toMutableList().apply { add(k) }
                    out[k] = validateNode(v, clone(childTemplate), cpath, options, data)
                }
                return out
            }

            if (data is Map<*, *> && specMap.isNotEmpty() && specMap["`\$OPEN`"] != true) {
                for ((kAny, _) in data) {
                    val k = kAny.toString()
                    if (!specMap.containsKey(k) && !k.startsWith("`$")) {
                        errs.add("Unexpected keys at field ${pathify(path)}: $k")
                    }
                }
            }

            for ((k, sv) in specMap) {
                if (extractFullCommand(k) != null) continue
                val cpath = path.toMutableList().apply { add(k) }
                val dval = if (data is Map<*, *>) getprop(data, k, UNDEF) else UNDEF
                if (dval === UNDEF) {
                    if (sv is String && extractFullCommand(sv) != null) {
                        val v = validateNode(UNDEF, sv, cpath, options, data)
                        if (v !== UNDEF && v != null) out[k] = v
                        continue
                    }
                    if (sv is List<*> && extractFullCommand(getelem(sv, 0)) == "\$CHILD") {
                        out[k] = mutableListOf<Any?>()
                        continue
                    }
                    out[k] = validateNode(UNDEF, sv, cpath, options, data)
                } else {
                    out[k] = validateNode(dval, sv, cpath, options, data)
                }
            }
            return out
        }

        if (spec is List<*>) {
            val cmd = extractFullCommand(getelem(spec, 0))
            if (cmd == "\$REF" && spec.size >= 2) {
                if (data !== UNDEF) return data
                val rootSpec = options["__topspec__"]
                val refSpec = getpath(rootSpec, spec[1]?.toString() ?: "")
                if (refSpec === UNDEF) return data
                return validateNode(UNDEF, clone(refSpec), path, options, dparent)
            }
            if (cmd == "\$EXACT" && spec.size >= 2) {
                for (i in 1 until spec.size) if (deepEqualNode(data, spec[i])) return data
                if (spec.size == 2) errs.add(expectedExactMsg(path, spec[1], data))
                else errs.add(expectedExactDescMsg(path, "one of ${describeValues(spec.subList(1, spec.size))}", data))
                return data
            }
            if (cmd == "\$ONE" && spec.size >= 2) {
                for (i in 1 until spec.size) if (validateMatches(data, spec[i])) return data
                errs.add(expectedMsg(path, "one of ${describeValues(spec.subList(1, spec.size))}", data))
                return data
            }
            if (cmd == "\$CHILD" && spec.size >= 2) {
                val tmpl = spec[1]
                if (data is List<*>) {
                    val out = mutableListOf<Any?>()
                    for (i in data.indices) {
                        val cpath = path.toMutableList().apply { add(strkey(i)) }
                        out.add(validateNode(data[i], clone(tmpl), cpath, options, data))
                    }
                    return out
                }
                if (data !== UNDEF) errs.add(expectedMsg(path, "list", data))
                return data
            }
            val out = if (data is List<*>) data.toMutableList() else mutableListOf()
            for (i in spec.indices) {
                val cpath = path.toMutableList().apply { add(strkey(i)) }
                val dval = if (data is List<*>) getprop(data, i, UNDEF) else UNDEF
                val sv = spec[i]
                if (dval === UNDEF) {
                    if (sv is String && extractFullCommand(sv) != null) continue
                    if (i < out.size) out[i] = clone(sv) else out.add(clone(sv))
                } else {
                    val v = validateNode(dval, sv, cpath, options, data)
                    if (i < out.size) out[i] = v else out.add(v)
                }
            }
            return out
        }

        val exact = meta["`\$EXACT`"] == true || meta["\$EXACT"] == true
        if (data === UNDEF) return clone(spec)
        if (exact) {
            if (!deepEqualNode(data, spec)) errs.add(valueEqualMsg(path, data, spec))
            return data
        }
        if (typify(data) != typify(spec)) errs.add(expectedMsg(path, typename(typify(spec)), data))
        return if (data === UNDEF) clone(spec) else data
    }

    private fun expectedMsg(path: MutableList<String>, expected: String, found: Any?): String =
        if (path.isEmpty()) "Expected $expected, but found ${foundDesc(found)}."
        else "Expected field ${pathify(path)} to be $expected, but found ${foundDesc(found)}."

    private fun expectedExactMsg(path: MutableList<String>, expected: Any?, found: Any?): String =
        expectedExactDescMsg(path, stringify(expected), found)

    private fun expectedExactDescMsg(path: MutableList<String>, expectedDesc: String, found: Any?): String =
        if (path.isEmpty()) "Expected value exactly equal to $expectedDesc, but found ${foundDesc(found)}."
        else "Expected field ${pathify(path)} to be exactly equal to $expectedDesc, but found ${foundDesc(found)}."

    private fun valueEqualMsg(path: MutableList<String>, data: Any?, spec: Any?): String =
        if (path.isEmpty()) "Value ${stringify(data)} should equal ${stringify(spec)}."
        else "Value at field ${pathify(path)}: ${stringify(data)} should equal ${stringify(spec)}."

    private fun foundDesc(found: Any?): String =
        if (found == null || found === UNDEF) "no value" else "${typename(typify(found))}: ${stringify(found)}"

    private fun describeValues(vals: List<Any?>): String = vals.joinToString(", ") { v ->
        if (v is String) {
            val cmd = extractFullCommand(v)
            if (cmd != null) return@joinToString cmd.substring(1).lowercase(Locale.ROOT)
        }
        stringify(v)
    }

    private fun deepEqualNode(a: Any?, b: Any?): Boolean = normalizeNode(a) == normalizeNode(b)

    private fun normalizeNode(v: Any?): Any? = when (v) {
        is Number -> {
            val d = v.toDouble()
            if (floor(d) == d) d.toLong() else d
        }
        is List<*> -> v.map { normalizeNode(it) }
        is Map<*, *> -> linkedMapOf<String, Any?>().also { v.forEach { (k, vv) -> it[k.toString()] = normalizeNode(vv) } }
        else -> v
    }

    private fun validateMatches(data: Any?, spec: Any?): Boolean {
        if (spec == null) return data == null
        if (spec is String) {
            val cmd = extractFullCommand(spec) ?: return data == spec
            return when (cmd) {
                "\$STRING" -> data is String && data.isNotEmpty()
                "\$NUMBER" -> data is Number
                "\$INTEGER" -> data is Number && floor(data.toDouble()) == data.toDouble()
                "\$DECIMAL" -> data is Number && floor(data.toDouble()) != data.toDouble()
                "\$BOOLEAN" -> data is Boolean
                "\$MAP", "\$OBJECT" -> data is Map<*, *>
                "\$LIST", "\$ARRAY" -> data is List<*>
                "\$NULL" -> data == null
                "\$NIL" -> data == null || data === UNDEF
                else -> true
            }
        }
        if (spec is Number || spec is Boolean) return spec == data
        return true
    }

    fun select(children: Any?, query: Any?): MutableList<Any?> {
        if (!isnode(children)) return mutableListOf()
        val out = mutableListOf<Any?>()
        when (children) {
            is Map<*, *> -> {
                for ((kAny, v) in children) {
                    val key = kAny.toString()
                    var child = clone(v)
                    if (child is Map<*, *>) {
                        val node = linkedMapOf<String, Any?>()
                        child.forEach { (ck, cv) -> node[ck.toString()] = cv }
                        node[S_DKEY] = key
                        child = node
                    }
                    if (selectMatch(child, query)) out.add(child)
                }
            }
            is List<*> -> {
                for (i in children.indices) {
                    var child = clone(children[i])
                    if (child is Map<*, *>) {
                        val node = linkedMapOf<String, Any?>()
                        child.forEach { (ck, cv) -> node[ck.toString()] = cv }
                        node[S_DKEY] = i
                        child = node
                    }
                    if (selectMatch(child, query)) out.add(child)
                }
            }
        }
        return out
    }

    private fun selectMatch(child: Any?, query: Any?): Boolean = selectEval(child, query)

    private fun selectEval(point: Any?, query: Any?): Boolean {
        if (query !is Map<*, *>) return deepEqualNode(point, query)
        val q = linkedMapOf<String, Any?>()
        query.forEach { (k, v) -> q[k.toString()] = v }
        if (q.isEmpty()) return true

        for ((key, term) in q) {
            val cmd = extractFullCommand(key)
            if (cmd != null) {
                if (!selectEvalCommand(point, cmd, term)) return false
                continue
            }
            if (point !is Map<*, *>) return false
            val pointMap = linkedMapOf<String, Any?>().also { point.forEach { (k, v) -> it[k.toString()] = v } }
            if (!pointMap.containsKey(key)) return false
            val child = pointMap[key]
            if (!selectEval(child, term)) return false
        }
        return true
    }

    private fun selectEvalCommand(point: Any?, cmd: String, term: Any?): Boolean {
        return when (cmd) {
            "\$AND" -> {
                if (term !is List<*>) false else term.all { selectEval(point, it) }
            }
            "\$OR" -> {
                if (term !is List<*>) false else term.any { selectEval(point, it) }
            }
            "\$NOT" -> !selectEval(point, term)
            "\$GT", "\$LT", "\$GTE", "\$LTE" -> selectCompare(point, term, cmd)
            "\$LIKE" -> {
                if (term !is String) false else Pattern.compile(term).matcher(stringify(point)).find()
            }
            else -> false
        }
    }

    private fun selectCompare(point: Any?, term: Any?, op: String): Boolean {
        if (point is Number && term is Number) {
            val a = point.toDouble()
            val b = term.toDouble()
            return when (op) {
                "\$GT" -> a > b
                "\$LT" -> a < b
                "\$GTE" -> a >= b
                "\$LTE" -> a <= b
                else -> false
            }
        }
        if (point is Comparable<*> && term != null && point::class == term::class) {
            @Suppress("UNCHECKED_CAST")
            val cmp = (point as Comparable<Any?>).compareTo(term)
            return when (op) {
                "\$GT" -> cmp > 0
                "\$LT" -> cmp < 0
                "\$GTE" -> cmp >= 0
                "\$LTE" -> cmp <= 0
                else -> false
            }
        }
        return false
    }
}
