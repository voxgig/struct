package voxgig.struct

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlin.math.floor
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import java.nio.file.Files
import java.nio.file.Path
import java.util.function.Function
import java.util.function.Supplier
import java.util.regex.Pattern

@Suppress("UNCHECKED_CAST")
class StructTests {
    private val gson = Gson()
    private lateinit var walkSpec: Map<String, Any?>
    private lateinit var mergeSpec: Map<String, Any?>
    private lateinit var getpathSpec: Map<String, Any?>
    private lateinit var injectSpec: Map<String, Any?>
    private lateinit var transformSpec: Map<String, Any?>
    private lateinit var eachSpec: Map<String, Any?>
    private lateinit var packSpec: Map<String, Any?>
    private lateinit var formatSpec: Map<String, Any?>
    private lateinit var refSpec: Map<String, Any?>
    private lateinit var validateSpec: Map<String, Any?>
    private lateinit var validateOneSpec: Map<String, Any?>
    private lateinit var validateExactSpec: Map<String, Any?>
    private lateinit var validateInvalidSpec: Map<String, Any?>
    private lateinit var validateSpecialSpec: Map<String, Any?>
    private lateinit var selectSpec: Map<String, Any?>
    private val cmdRef = Pattern.compile("`(\\$[A-Z]+[0-9]*)`")

    @BeforeTest
    fun init() {
        val json = Files.readString(Path.of("..", "build", "test", "test.json"))
        val mapType = object : TypeToken<Map<String, Any?>>() {}.type
        val all = gson.fromJson<Map<String, Any?>>(json, mapType)
        val struct = all["struct"] as Map<String, Any?>
        walkSpec = struct["walk"] as Map<String, Any?>
        mergeSpec = struct["merge"] as Map<String, Any?>
        getpathSpec = struct["getpath"] as Map<String, Any?>
        injectSpec = struct["inject"] as Map<String, Any?>
        transformSpec = struct["transform"] as Map<String, Any?>
        eachSpec = transformSpec["each"] as Map<String, Any?>
        packSpec = transformSpec["pack"] as Map<String, Any?>
        formatSpec = transformSpec["format"] as Map<String, Any?>
        refSpec = transformSpec["ref"] as Map<String, Any?>
        validateSpec = struct["validate"] as Map<String, Any?>
        validateOneSpec = validateSpec["one"] as Map<String, Any?>
        validateExactSpec = validateSpec["exact"] as Map<String, Any?>
        validateInvalidSpec = validateSpec["invalid"] as Map<String, Any?>
        validateSpecialSpec = validateSpec["special"] as Map<String, Any?>
        selectSpec = struct["select"] as Map<String, Any?>
    }

    @Test
    fun walkExists() {
        assertTrue(Struct.walk(linkedMapOf<String, Any?>(), Struct.WalkApply { _, v, _, _ -> v }) is Map<*, *>)
    }

    @Test
    fun walkBasic() {
        val walkPath = Struct.WalkApply { _, v, _, p ->
            if (v is String) v + "~" + p.joinToString(".") else v
        }
        runSet(walkSpec["basic"] as Map<String, Any?>) { input -> Struct.walk(input, walkPath) }
    }

    @Test
    fun walkLog() {
        val test = Struct.clone(walkSpec["log"]) as Map<*, *>
        val outMap = test["out"] as Map<*, *>

        val logAfter = mutableListOf<Any?>()
        val walklogAfter = Struct.WalkApply { key, value, parent, path ->
            val ks = key ?: ""
            val entry = "k=${Struct.stringify(ks)}, v=${Struct.stringify(value)}, p=${slog(parent)}, t=${Struct.pathify(path)}"
            logAfter.add(entry)
            value
        }
        Struct.walk(test["in"], null, walklogAfter)
        assertEquals(outMap["after"], logAfter)

        val logBefore = mutableListOf<Any?>()
        val walklogBefore = Struct.WalkApply { key, value, parent, path ->
            val ks = key ?: ""
            val entry = "k=${Struct.stringify(ks)}, v=${Struct.stringify(value)}, p=${slog(parent)}, t=${Struct.pathify(path)}"
            logBefore.add(entry)
            value
        }
        Struct.walk(test["in"], walklogBefore)
        assertEquals(outMap["before"], logBefore)

        val logBoth = mutableListOf<Any?>()
        val walklogBoth = Struct.WalkApply { key, value, parent, path ->
            val ks = key ?: ""
            val entry = "k=${Struct.stringify(ks)}, v=${Struct.stringify(value)}, p=${slog(parent)}, t=${Struct.pathify(path)}"
            logBoth.add(entry)
            value
        }
        Struct.walk(test["in"], walklogBoth, walklogBoth)
        assertEquals(outMap["both"], logBoth)
    }

    @Test
    fun walkDepth() {
        runSet(walkSpec["depth"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            val src = m["src"]
            val maxdepth = m["maxdepth"]
            val top = arrayOfNulls<Any>(1)
            val cur = arrayOfNulls<Any>(1)
            val copy = Struct.WalkApply { key, value, _, _ ->
                if (Struct.isnode(value)) {
                    val child: Any? = if (Struct.islist(value)) mutableListOf<Any?>() else linkedMapOf<String, Any?>()
                    if (key == null) {
                        top[0] = child
                        cur[0] = child
                    } else {
                        cur[0] = Struct.setprop(cur[0], key, child)
                        cur[0] = child
                    }
                } else if (key != null) {
                    cur[0] = Struct.setprop(cur[0], key, value)
                }
                value
            }
            if (maxdepth == null) Struct.walk(src, copy) else Struct.walk(src, copy, null, intish(maxdepth))
            top[0]
        }
    }

    @Test
    fun walkCopy() {
        runSet(walkSpec["copy"] as Map<String, Any?>) { v ->
            val cur = arrayOfNulls<Any>(33)
            val keys = arrayOfNulls<String>(33)
            val walkcopy = Struct.WalkApply { key, value, _, path ->
                if (key == null) {
                    java.util.Arrays.fill(cur, null)
                    java.util.Arrays.fill(keys, null)
                    cur[0] = when {
                        Struct.ismap(value) -> linkedMapOf<String, Any?>()
                        Struct.islist(value) -> mutableListOf<Any?>()
                        else -> value
                    }
                    return@WalkApply value
                }
                var node: Any? = value
                val i = path.size
                keys[i] = key
                if (Struct.isnode(node)) {
                    cur[i] = if (Struct.ismap(node)) linkedMapOf<String, Any?>() else mutableListOf<Any?>()
                    node = cur[i]
                }
                cur[i - 1] = Struct.setprop(cur[i - 1], key, node)
                for (j in i - 1 downTo 1) {
                    cur[j - 1] = Struct.setprop(cur[j - 1], keys[j], cur[j])
                }
                value
            }
            Struct.walk(v, walkcopy)
            cur[0]
        }
    }

    @Test
    fun mergeExists() {
        assertEquals(null, Struct.merge(emptyList<Any?>()))
    }

    @Test
    fun mergeBasic() {
        val t = mergeSpec["basic"] as Map<String, Any?>
        val got = Struct.merge(t["in"])
        assertEquals(normalize(t["out"]), normalize(got))
    }

    @Test
    fun mergeCases() {
        runSet(mergeSpec["cases"] as Map<String, Any?>) { Struct.merge(it) }
    }

    @Test
    fun mergeArray() {
        runSet(mergeSpec["array"] as Map<String, Any?>) { Struct.merge(it) }
    }

    @Test
    fun mergeIntegrity() {
        runSet(mergeSpec["integrity"] as Map<String, Any?>) { Struct.merge(it) }
    }

    @Test
    fun mergeDepth() {
        runSet(mergeSpec["depth"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            val value = m["val"]
            val depth = m["depth"]
            if (depth == null) Struct.merge(value) else Struct.merge(value, (depth as Number).toInt())
        }
    }

    @Test
    fun mergeSpecial() {
        val f0 = Supplier { 11 }
        val result0 = Struct.merge(listOf(f0)) as Supplier<*>
        assertEquals(11, result0.get())
    }

    @Test
    fun getpathExists() {
        assertEquals(1L, normalize(Struct.getpath(mapOf("a" to 1), "a")))
    }

    @Test
    fun getpathBasic() {
        runSet(getpathSpec["basic"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            Struct.getpath(m["store"], m["path"])
        }
    }

    @Test
    fun getpathRelative() {
        runSet(getpathSpec["relative"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            val inj = linkedMapOf<String, Any?>()
            inj["dparent"] = m["dparent"]
            val dpath = m["dpath"]
            if (dpath is String && dpath.isNotEmpty()) inj["dpath"] = dpath.split(".")
            Struct.getpath(m["store"], m["path"], inj)
        }
    }

    @Test
    fun getpathSpecial() {
        runSet(getpathSpec["special"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            val injObj = m["inj"]
            if (injObj is Map<*, *>) {
                val inj = linkedMapOf<String, Any?>()
                injObj.forEach { (k, vv) -> inj[k.toString()] = vv }
                Struct.getpath(m["store"], m["path"], inj)
            } else Struct.getpath(m["store"], m["path"])
        }
    }

    @Test
    fun getpathHandler() {
        runSet(getpathSpec["handler"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            val store = linkedMapOf<String, Any?>()
            store[Struct.S_DTOP] = m["store"]
            store["\$FOO"] = Supplier { "foo" }
            val inj = linkedMapOf<String, Any?>()
            inj["handler"] = Struct.PathHandler { _, value, _, _ ->
                if (value is Supplier<*>) value.get() else value
            }
            Struct.getpath(store, m["path"], inj)
        }
    }

    @Test
    fun injectExists() {
        assertEquals(1L, normalize(Struct.inject("`a`", mapOf("a" to 1))))
    }

    @Test
    fun injectBasic() {
        val t = injectSpec["basic"] as Map<String, Any?>
        val input = t["in"] as Map<String, Any?>
        val got = Struct.inject(input["val"], input["store"])
        assertTrue(normalize(t["out"]) == normalize(got))
    }

    @Test
    fun injectString() {
        runSet(injectSpec["string"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            Struct.inject(m["val"], m["store"])
        }
    }

    @Test
    fun injectDeep() {
        runSet(injectSpec["deep"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            Struct.inject(m["val"], m["store"])
        }
    }

    @Test
    fun transformExists() {
        assertEquals("A", Struct.transform(emptyMap<String, Any?>(), "A"))
    }

    @Test
    fun transformBasic() {
        val t = transformSpec["basic"] as Map<String, Any?>
        val input = t["in"] as Map<String, Any?>
        val got = Struct.transform(input["data"], input["spec"])
        assertTrue(normalize(t["out"]) == normalize(got))
    }

    @Test
    fun transformPathsSubset() {
        runSet(transformSpec["paths"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            Struct.transform(m["data"], m["spec"])
        }
    }

    @Test
    fun transformCmdsCopyEscapesSubset() {
        runSet(
            transformSpec["cmds"] as Map<String, Any?>,
            { v ->
                val m = v as Map<*, *>
                Struct.transform(m["data"], m["spec"])
            },
            ::isCopyEscapeOnlyCmdCase
        )
    }

    @Test
    fun transformEachCopyKeySubset() {
        runSet(
            eachSpec,
            { v ->
                val m = v as Map<*, *>
                Struct.transform(m["data"], m["spec"])
            },
            ::isEachCopyKeyOnlyCase
        )
    }

    @Test
    fun transformPackBasicSubset() {
        runSet(
            packSpec,
            { v ->
                val m = v as Map<*, *>
                Struct.transform(m["data"], m["spec"])
            },
            ::isPackBasicCase
        )
    }

    @Test
    fun transformFormat() {
        runSet(formatSpec) { v ->
            val m = v as Map<*, *>
            Struct.transform(m["data"], m["spec"])
        }
    }

    @Test
    fun transformRef() {
        runSet(refSpec) { v ->
            val m = v as Map<*, *>
            Struct.transform(m["data"], m["spec"])
        }
    }

    @Test
    fun validateBasic() {
        runSet(validateSpec["basic"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            val opts = linkedMapOf<String, Any?>("errs" to mutableListOf<String>())
            Struct.validate(m["data"], m["spec"], opts)
        }
    }

    @Test
    fun validateChild() {
        runSet(validateSpec["child"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            val opts = linkedMapOf<String, Any?>("errs" to mutableListOf<String>())
            Struct.validate(m["data"], m["spec"], opts)
        }
    }

    @Test
    fun validateOne() {
        runSet(validateOneSpec) { v ->
            val m = v as Map<*, *>
            val opts = linkedMapOf<String, Any?>("errs" to mutableListOf<String>())
            Struct.validate(m["data"], m["spec"], opts)
        }
    }

    @Test
    fun validateExact() {
        runSet(validateExactSpec) { v ->
            val m = v as Map<*, *>
            val opts = linkedMapOf<String, Any?>("errs" to mutableListOf<String>())
            Struct.validate(m["data"], m["spec"], opts)
        }
    }

    @Test
    fun validateInvalid() {
        runValidateSet(validateInvalidSpec, false)
    }

    @Test
    fun validateSpecial() {
        runValidateSet(validateSpecialSpec, true)
    }

    @Test
    fun validateEdge() {
        val errs = mutableListOf<String>()
        val opts = linkedMapOf<String, Any?>("errs" to errs)

        Struct.validate(mapOf("x" to 1), mapOf("x" to "`\$INSTANCE`"), opts)
        assertEquals("Expected field x to be instance, but found integer: 1.", errs[0])

        errs.clear()
        Struct.validate(mapOf("x" to mapOf<String, Any?>()), mapOf("x" to "`\$INSTANCE`"), opts)
        assertEquals("Expected field x to be instance, but found map: {}.", errs[0])

        errs.clear()
        Struct.validate(mapOf("x" to listOf<Any?>()), mapOf("x" to "`\$INSTANCE`"), opts)
        assertEquals("Expected field x to be instance, but found list: [].", errs[0])

        class C
        errs.clear()
        Struct.validate(mapOf("x" to C()), mapOf("x" to "`\$INSTANCE`"), opts)
        assertEquals(0, errs.size)
    }

    @Test
    fun validateCustom() {
        val errs = mutableListOf<String>()
        val extra = linkedMapOf<String, Any?>()
        extra["\$INTEGER"] = java.util.function.Function<Any?, Any?> { state ->
            if (state is Map<*, *>) {
                val key = state["key"]
                val dparent = state["dparent"]
                val out = Struct.getprop(dparent, key)
                if (out !is Number || floor(out.toDouble()) != out.toDouble()) {
                    val path = (state["path"] as? List<*>)?.map { it.toString() } ?: emptyList()
                    @Suppress("UNCHECKED_CAST")
                    val localErrs = (state["errs"] as? MutableList<String>) ?: errs
                    localErrs.add("Not an integer at ${path.joinToString(".")}: $out")
                    return@Function null
                }
                return@Function out
            }
            null
        }

        val shape = mapOf("a" to "`\$INTEGER`")
        val opts = linkedMapOf<String, Any?>("extra" to extra, "errs" to errs)

        var out = Struct.validate(mapOf("a" to 1), shape, opts)
        assertTrue(normalize(mapOf("a" to 1)) == normalize(out))
        assertEquals(0, errs.size)

        errs.clear()
        out = Struct.validate(mapOf("a" to "A"), shape, opts)
        assertTrue(normalize(mapOf("a" to "A")) == normalize(out))
        assertEquals(listOf("Not an integer at a: A"), errs)
    }

    @Test
    fun selectBasic() {
        runSet(selectSpec["basic"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            Struct.select(m["obj"], m["query"])
        }
    }

    @Test
    fun selectOperators() {
        runSet(selectSpec["operators"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            Struct.select(m["obj"], m["query"])
        }
    }

    @Test
    fun selectEdge() {
        runSet(selectSpec["edge"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            Struct.select(m["obj"], m["query"])
        }
    }

    @Test
    fun selectAlts() {
        runSet(selectSpec["alts"] as Map<String, Any?>) { v ->
            val m = v as Map<*, *>
            Struct.select(m["obj"], m["query"])
        }
    }

    @Test
    fun transformEdgeApply() {
        val spec = mutableListOf<Any?>(
            "`\$APPLY`",
            Function<Any?, Any?> { v -> 1 + (v as Number).toInt() },
            1
        )
        assertEquals(2L, normalize(Struct.transform(linkedMapOf<String, Any?>(), spec)))
    }

    @Test
    fun transformModify() {
        val data = linkedMapOf<String, Any?>("x" to "X")
        val spec = linkedMapOf<String, Any?>("z" to "`x`")
        val opts = linkedMapOf<String, Any?>(
            "modify" to Struct.TransformModify { value, key, parent ->
                if (key != null && parent is MutableMap<*, *> && value is String) {
                    @Suppress("UNCHECKED_CAST")
                    (parent as MutableMap<String, Any?>)[key] = "@$value"
                }
            }
        )
        val got = Struct.transform(data, spec, opts)
        assertTrue(normalize(mapOf("z" to "@X")) == normalize(got))
    }

    @Test
    fun transformExtra() {
        val data = linkedMapOf<String, Any?>("a" to 1)
        val spec = linkedMapOf<String, Any?>(
            "x" to "`a`",
            "b" to "`\$COPY`",
            "c" to "`\$UPPER`"
        )
        val extra = linkedMapOf<String, Any?>(
            "b" to 2,
            "\$UPPER" to Function<Any?, Any?> { state ->
                if (state is Map<*, *>) {
                    val path = state["path"] as? List<*>
                    if (!path.isNullOrEmpty()) return@Function path.last().toString().uppercase()
                }
                ""
            }
        )
        val opts = linkedMapOf<String, Any?>("extra" to extra)
        val got = Struct.transform(data, spec, opts)
        assertTrue(normalize(mapOf("x" to 1, "b" to 2, "c" to "C")) == normalize(got))
    }

    @Test
    fun transformFuncval() {
        val f0 = Supplier { 99 }
        assertTrue(normalize(mapOf("x" to 1)) == normalize(Struct.transform(mapOf<String, Any?>(), mapOf("x" to 1))))
        assertTrue(normalize(mapOf("x" to f0)) == normalize(Struct.transform(mapOf<String, Any?>(), mapOf("x" to f0))))
        assertTrue(normalize(mapOf("x" to 1)) == normalize(Struct.transform(mapOf("a" to 1), mapOf("x" to "`a`"))))
        val got = Struct.transform(mapOf("f0" to f0), mapOf("x" to "`f0`")) as Map<*, *>
        assertEquals(99, ((got["x"] as Supplier<*>).get() as Number).toInt())
    }

    private fun runSet(testspec: Map<String, Any?>, fn: (Any?) -> Any?) {
        runSet(testspec, fn, null)
    }

    private fun runSet(
        testspec: Map<String, Any?>,
        fn: (Any?) -> Any?,
        filter: ((Map<*, *>) -> Boolean)?
    ) {
        val set = testspec["set"] as List<*>
        for (eo in set) {
            if (eo !is Map<*, *>) continue
            if (filter != null && !filter(eo)) continue
            if (!eo.containsKey("in") || !eo.containsKey("out")) continue
            val input = Struct.clone(eo["in"])
            val out = eo["out"]
            val got = fn(input)
            assertTrue(normalize(out) == normalize(got), "Mismatch in=${json(input)} expected=${json(out)} got=${json(got)}")
        }
    }

    private fun runValidateSet(testspec: Map<String, Any?>, useInj: Boolean) {
        val set = testspec["set"] as List<*>
        for (eo in set) {
            if (eo !is Map<*, *>) continue
            val entry = eo
            val input = entry["in"] as? Map<*, *> ?: continue
            val data = input["data"]
            val spec = input["spec"]
            val inj = if (useInj) input["inj"] as? Map<*, *> else null
            val options = linkedMapOf<String, Any?>()
            if (inj != null) inj.forEach { (k, v) -> options[k.toString()] = v }
            if (entry.containsKey("err")) {
                val expectedErr = entry["err"]?.toString() ?: ""
                val ex = assertFailsWith<IllegalArgumentException> { Struct.validate(data, spec, options) }
                assertEquals(canonicalErr(expectedErr), canonicalErr(ex.message ?: ""))
            } else {
                val got = Struct.validate(data, spec, options)
                assertTrue(
                    normalize(entry["out"]) == normalize(got),
                    "Mismatch in=${json(input)} expected=${json(entry["out"])} got=${json(got)}"
                )
            }
        }
    }

    private fun canonicalErr(err: String?): String {
        if (err == null) return ""
        return err.replace(Regex("\\.$"), "").replace(". |", " |").trim()
    }

    private fun slog(v: Any?): String = if (v == null) "" else Struct.stringify(v)

    private fun intish(o: Any?): Int {
        if (o is Number) return o.toInt()
        throw IllegalArgumentException("expected number, got $o")
    }

    private fun isCopyEscapeOnlyCmdCase(entry: Map<*, *>): Boolean {
        val inObj = entry["in"] as? Map<*, *> ?: return false
        val spec = inObj["spec"]
        val cmds = linkedSetOf<String>()
        collectCommands(spec, cmds)
        if (cmds.isEmpty()) return false
        for (c in cmds) {
            if (c != "\$BT" && c != "\$DS" && c != "\$COPY" && c != "\$DELETE" && !c.startsWith("\$MERGE")) {
                return false
            }
        }
        return true
    }

    private fun isEachCopyKeyOnlyCase(entry: Map<*, *>): Boolean {
        val inObj = entry["in"] as? Map<*, *> ?: return false
        val spec = inObj["spec"]
        val cmds = linkedSetOf<String>()
        collectCommands(spec, cmds)
        if (cmds.isEmpty()) return false
        for (c in cmds) {
            if (c != "\$COPY" && c != "\$KEY" && c != "\$EACH") return false
        }
        return true
    }

    private fun isPackBasicCase(entry: Map<*, *>): Boolean {
        val inObj = entry["in"] as? Map<*, *> ?: return false
        val spec = inObj["spec"]
        val cmds = linkedSetOf<String>()
        collectCommands(spec, cmds)
        if (!cmds.contains("\$PACK")) return false
        for (c in cmds) {
            if (c != "\$PACK" && c != "\$COPY" && c != "\$KEY" && c != "\$VAL") return false
        }
        return true
    }

    private fun collectCommands(node: Any?, out: MutableSet<String>) {
        when (node) {
            is String -> {
                val m = cmdRef.matcher(node)
                while (m.find()) out.add(m.group(1))
            }
            is Map<*, *> -> node.forEach { (k, v) ->
                collectCommands(k?.toString(), out)
                collectCommands(v, out)
            }
            is List<*> -> node.forEach { collectCommands(it, out) }
        }
    }

    private fun json(v: Any?): String = try {
        gson.toJson(if (v === Struct.UNDEF) "__UNDEF__" else v)
    } catch (_: Exception) {
        v.toString()
    }

    private fun normalize(v: Any?): Any? {
        if (v === Struct.UNDEF) return "__UNDEF__"
        return when (v) {
            is Number -> {
                val d = v.toDouble()
                if (floor(d) == d) d.toLong() else d
            }
            is List<*> -> v.map { normalize(it) }
            is Map<*, *> -> v.entries.associate { it.key.toString() to normalize(it.value) }.toSortedMap()
            else -> v
        }
    }
}
