package voxgig.struct

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlin.math.floor
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import java.util.function.Function
import java.nio.file.Files
import java.nio.file.Path

@Suppress("UNCHECKED_CAST")
class StructMinorTest {
    private val gson = Gson()
    private lateinit var minorSpec: Map<String, Any?>

    @BeforeTest
    fun loadSpec() {
        val json = Files.readString(Path.of("..", "build", "test", "test.json"))
        val mapType = object : TypeToken<Map<String, Any?>>() {}.type
        val all = gson.fromJson<Map<String, Any?>>(json, mapType)
        val struct = all["struct"] as Map<String, Any?>
        minorSpec = struct["minor"] as Map<String, Any?>
    }

    @Test
    fun exists() {
        assertTrue(Struct.isfunc { _: Any? -> null })
        assertEquals("map", Struct.typename(Struct.T_MAP))
    }

    @Test
    fun minorIsnode() = runSet("isnode") { Struct.isnode(it) }

    @Test
    fun minorIsmap() = runSet("ismap") { Struct.ismap(it) }

    @Test
    fun minorIslist() = runSet("islist") { Struct.islist(it) }

    @Test
    fun minorIskey() = runSet("iskey") { Struct.iskey(it) }

    @Test
    fun minorStrkey() = runSet("strkey") { Struct.strkey(it) }

    @Test
    fun minorIsempty() = runSet("isempty") { Struct.isempty(it) }

    @Test
    fun minorIsfunc() = runSet("isfunc") { Struct.isfunc(it) }

    @Test
    fun minorClone() = runSet("clone") { Struct.clone(it) }

    @Test
    fun minorGetprop() = runSet("getprop") {
        val m = it as? Map<*, *> ?: return@runSet Struct.getprop(Struct.UNDEF, Struct.UNDEF)
        val v = if (m.containsKey("val")) m["val"] else Struct.UNDEF
        val k = if (m.containsKey("key")) m["key"] else Struct.UNDEF
        if (m.containsKey("alt")) Struct.getprop(v, k, m["alt"]) else Struct.getprop(v, k)
    }

    @Test
    fun minorGetelem() = runSet("getelem") {
        val m = it as? Map<*, *> ?: return@runSet Struct.getelem(Struct.UNDEF, Struct.UNDEF)
        val v = if (m.containsKey("val")) m["val"] else Struct.UNDEF
        val k = if (m.containsKey("key")) m["key"] else Struct.UNDEF
        if (m.containsKey("alt")) Struct.getelem(v, k, m["alt"]) else Struct.getelem(v, k)
    }

    @Test
    fun minorItems() = runSet("items") { Struct.items(it) }

    @Test
    fun minorKeysof() = runSet("keysof") { Struct.keysof(it) }

    @Test
    fun minorHaskey() = runSet("haskey") {
        val m = it as? Map<*, *> ?: return@runSet Struct.haskey(Struct.UNDEF, Struct.UNDEF)
        val src = if (m.containsKey("src")) m["src"] else Struct.UNDEF
        val key = if (m.containsKey("key")) m["key"] else Struct.UNDEF
        Struct.haskey(src, key)
    }

    @Test
    fun minorSetprop() = runSet("setprop") {
        val m = it as? Map<*, *> ?: return@runSet Struct.UNDEF
        val parent = if (m.containsKey("parent")) Struct.clone(m["parent"]) else Struct.UNDEF
        val key = if (m.containsKey("key")) m["key"] else Struct.UNDEF
        val value = if (m.containsKey("val")) m["val"] else Struct.UNDEF
        Struct.setprop(parent, key, value)
    }

    @Test
    fun minorDelprop() = runSet("delprop") {
        val m = it as? Map<*, *> ?: return@runSet Struct.UNDEF
        val parent = if (m.containsKey("parent")) Struct.clone(m["parent"]) else Struct.UNDEF
        val key = if (m.containsKey("key")) m["key"] else Struct.UNDEF
        Struct.delprop(parent, key)
    }

    @Test
    fun minorSize() = runSet("size") { Struct.size(it) }

    @Test
    fun minorTypify() = runSet("typify") { Struct.typify(it) }

    @Test
    fun minorTypename() = runSet("typename") { Struct.typename(it) }

    @Test
    fun minorSlice() = runSet("slice") {
        val m = it as? Map<*, *> ?: return@runSet Struct.UNDEF
        Struct.slice(if (m.containsKey("val")) m["val"] else Struct.UNDEF, m["start"], m["end"])
    }

    @Test
    fun minorPad() = runSet("pad") {
        val m = it as? Map<*, *> ?: return@runSet Struct.UNDEF
        Struct.pad(m["val"], m["pad"], m["char"])
    }

    @Test
    fun minorFlatten() = runSet("flatten") {
        val m = it as? Map<*, *> ?: return@runSet Struct.UNDEF
        Struct.flatten(m["val"], (m["depth"] as? Number)?.toInt())
    }

    @Test
    fun minorFilter() = runSet("filter") {
        val m = it as? Map<*, *> ?: return@runSet Struct.UNDEF
        val check = m["check"]?.toString() ?: ""
        val checkMap = mapOf<String, (List<Any?>) -> Boolean>(
            "gt3" to { n -> ((n[1] as Number).toDouble() > 3) },
            "lt3" to { n -> ((n[1] as Number).toDouble() < 3) }
        )
        Struct.filter(m["val"]) { item -> checkMap[check]!!.invoke(item) }
    }

    @Test
    fun minorEscre() = runSet("escre") { Struct.escre(it) }

    @Test
    fun minorEscurl() = runSet("escurl") { Struct.escurl(it) }

    @Test
    fun minorJoin() = runSet("join") {
        val m = it as? Map<*, *> ?: return@runSet Struct.UNDEF
        Struct.join(m["val"], m["sep"], m["url"])
    }

    @Test
    fun minorStringify() = runSet("stringify") {
        val m = it as? Map<*, *> ?: return@runSet Struct.stringify(Struct.UNDEF)
        if (!m.containsKey("val")) return@runSet Struct.stringify(Struct.UNDEF)
        var value: Any? = m["val"]
        if ("__NULL__" == value) value = "null"
        if (m.containsKey("max")) Struct.stringify(value, (m["max"] as Number).toInt()) else Struct.stringify(value)
    }

    @Test
    fun minorJsonify() = runSet("jsonify") {
        val m = it as? Map<*, *> ?: return@runSet Struct.jsonify(Struct.UNDEF)
        Struct.jsonify(if (m.containsKey("val")) m["val"] else Struct.UNDEF, m["flags"])
    }

    @Test
    fun minorPathify() = runSet("pathify") {
        val m = it as? Map<*, *> ?: return@runSet Struct.pathify(Struct.UNDEF)
        Struct.pathify(if (m.containsKey("path")) m["path"] else Struct.UNDEF, m["from"])
    }

    @Test
    fun minorSetpath() = runSet("setpath") {
        val m = it as? Map<*, *> ?: return@runSet Struct.UNDEF
        val store = if (m.containsKey("store")) Struct.clone(m["store"]) else Struct.UNDEF
        val path = m["path"]
        val value = if (m.containsKey("val")) m["val"] else Struct.UNDEF
        Struct.setpath(store, path, value)
    }

    private fun runSet(name: String, fn: (Any?) -> Any?) {
        runSet(name, fn, false)
    }

    private fun runSet(name: String, fn: (Any?) -> Any?, nullFlag: Boolean) {
        val testspec = minorSpec[name] as Map<String, Any?>
        val set = testspec["set"] as List<Any?>
        for (entryObj in set) {
            if (entryObj !is Map<*, *>) continue
            val inVal = if (entryObj.containsKey("in")) Struct.clone(entryObj["in"]) else Struct.UNDEF
            val outVal = if (entryObj.containsKey("out")) entryObj["out"] else if (nullFlag) "__NULL__" else Struct.UNDEF
            val got = fn(inVal)
            assertTrue(equalNorm(outVal, got), "Mismatch in $name expected=${json(outVal)} got=${json(got)}")
        }
    }

    private fun json(v: Any?): String = try {
        gson.toJson(if (v === Struct.UNDEF) "__UNDEF__" else v)
    } catch (_: Exception) {
        v.toString()
    }

    private fun equalNorm(a: Any?, b: Any?): Boolean {
        return normalize(a) == normalize(b)
    }

    private fun normalize(v: Any?): Any? {
        if (v === Struct.UNDEF) return "__UNDEF__"
        return when (v) {
            is Number -> {
                val d = v.toDouble()
                if (floor(d) == d) d.toLong() else d
            }
            is List<*> -> v.map { normalize(it) }
            is Map<*, *> -> v.entries.associate { (k, value) -> k.toString() to normalize(value) }.toSortedMap()
            else -> v
        }
    }
}
