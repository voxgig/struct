package voxgig.struct

import java.util.function.Function
import java.util.function.Supplier
import kotlin.math.floor
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The properties the corpus shape cannot express: identity, the presence of a
 * value rather than its shape, and the hand-built injectors and modifiers a
 * JSON entry has no way to carry.
 *
 * Everything the corpus DOES express lives in StructCorpusTest, which runs it
 * on voxgig/omni. This file used to carry its own entry loop as well - one
 * that dropped every entry missing `in` or `out`, and every entry with `err`
 * - and those loops are gone with it.
 *
 * The four `*Basic` cases read a single corpus entry that is not part of any
 * set, so the runner cannot drive them; the spec comes off the runner rather
 * than from a second loader.
 */
@Suppress("UNCHECKED_CAST")
class StructTests {
    private lateinit var walkSpec: Map<String, Any?>
    private lateinit var mergeSpec: Map<String, Any?>
    private lateinit var injectSpec: Map<String, Any?>
    private lateinit var transformSpec: Map<String, Any?>

    @BeforeTest
    fun init() {
        val struct = Omni.tostruct(Omni.Run.of("struct").spec) as Map<String, Any?>
        walkSpec = struct["walk"] as Map<String, Any?>
        mergeSpec = struct["merge"] as Map<String, Any?>
        injectSpec = struct["inject"] as Map<String, Any?>
        transformSpec = struct["transform"] as Map<String, Any?>
    }

    @Test
    fun walkExists() {
        assertTrue(Struct.walk(linkedMapOf<String, Any?>(), Struct.WalkApply { _, v, _, _ -> v }) is Map<*, *>)
    }

    @Test
    fun walkLog() {
        val test = Struct.clone(walkSpec["log"]) as Map<*, *>
        val outMap = test["out"] as Map<*, *>

        val logAfter = mutableListOf<Any?>()
        val walklogAfter =
            Struct.WalkApply { key, value, parent, path ->
                val ks = key ?: ""
                val entry = "k=${Struct.stringify(ks)}, v=${Struct.stringify(value)}, p=${slog(parent)}, t=${Struct.pathify(path)}"
                logAfter.add(entry)
                value
            }
        Struct.walk(test["in"], null, walklogAfter)
        assertEquals(outMap["after"], logAfter)

        val logBefore = mutableListOf<Any?>()
        val walklogBefore =
            Struct.WalkApply { key, value, parent, path ->
                val ks = key ?: ""
                val entry = "k=${Struct.stringify(ks)}, v=${Struct.stringify(value)}, p=${slog(parent)}, t=${Struct.pathify(path)}"
                logBefore.add(entry)
                value
            }
        Struct.walk(test["in"], walklogBefore)
        assertEquals(outMap["before"], logBefore)

        val logBoth = mutableListOf<Any?>()
        val walklogBoth =
            Struct.WalkApply { key, value, parent, path ->
                val ks = key ?: ""
                val entry = "k=${Struct.stringify(ks)}, v=${Struct.stringify(value)}, p=${slog(parent)}, t=${Struct.pathify(path)}"
                logBoth.add(entry)
                value
            }
        Struct.walk(test["in"], walklogBoth, walklogBoth)
        assertEquals(outMap["both"], logBoth)
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
        val errs = mutableListOf<Any?>()
        val extra = linkedMapOf<String, Any?>()
        // Custom $INTEGER validator using the canonical Injector signature.
        // Returns the data value either way so the output keeps the original key.
        extra["\$INTEGER"] =
            Struct.Injector { inj, _, _, _ ->
                val v = Struct.getprop(inj.dparent, inj.key)
                if (v !is Number || floor(v.toDouble()) != v.toDouble()) {
                    inj.errs.add("Not an integer at ${Struct.pathify(inj.path, 1)}: $v")
                }
                v
            }

        val shape = mapOf("a" to "`\$INTEGER`")
        val opts = linkedMapOf<String, Any?>("extra" to extra, "errs" to errs)

        var out = Struct.validate(mapOf("a" to 1), shape, opts)
        assertTrue(normalize(mapOf("a" to 1)) == normalize(out))
        assertEquals(0, errs.size)

        errs.clear()
        out = Struct.validate(mapOf("a" to "A"), shape, opts)
        assertTrue(normalize(mapOf("a" to "A")) == normalize(out))
        assertEquals(listOf<Any?>("Not an integer at a: A"), errs)
    }

    @Test
    fun transformEdgeApply() {
        val spec =
            mutableListOf<Any?>(
                "`\$APPLY`",
                Function<Any?, Any?> { v -> 1 + (v as Number).toInt() },
                1,
            )
        assertEquals(2L, normalize(Struct.transform(linkedMapOf<String, Any?>(), spec)))
    }

    @Test
    fun transformModify() {
        val data = linkedMapOf<String, Any?>("x" to "X")
        val spec = linkedMapOf<String, Any?>("z" to "`x`")
        val opts =
            linkedMapOf<String, Any?>(
                "modify" to
                    Struct.Modify { value, key, parent, _, _ ->
                        if (key != null && parent is MutableMap<*, *> && value is String) {
                            @Suppress("UNCHECKED_CAST")
                            (parent as MutableMap<String, Any?>)[key.toString()] = "@$value"
                        }
                    },
            )
        val got = Struct.transform(data, spec, opts)
        assertTrue(normalize(mapOf("z" to "@X")) == normalize(got))
    }

    @Test
    fun transformExtra() {
        val data = linkedMapOf<String, Any?>("a" to 1)
        val spec =
            linkedMapOf<String, Any?>(
                "x" to "`a`",
                "b" to "`\$COPY`",
                "c" to "`\$UPPER`",
            )
        val extra =
            linkedMapOf<String, Any?>(
                "b" to 2,
                "\$UPPER" to
                    Struct.Injector { inj, _, _, _ ->
                        if (inj.path.isNotEmpty()) inj.path.last().uppercase() else ""
                    },
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

    private fun normalize(v: Any?): Any? {
        // Treat the "no value" sentinel (UNDEF) and JSON null as equal, mirroring
        // canonical JS where `undefined == null`. The shared corpus uses null to
        // denote a "no value" result (e.g. getpath/inject of a null-valued slot,
        // which the Group A null-unification rule resolves to "no value"). Sets
        // that must distinguish stored null from absence use the NULLMARK fixup
        // (fixNull) to turn null into a distinct sentinel string before this runs.
        if (v === Struct.UNDEF || v == null) return null
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

    private fun slog(v: Any?): String = if (v == null) "" else Struct.stringify(v)

    private fun intish(o: Any?): Int {
        if (o is Number) return o.toInt()
        throw IllegalArgumentException("expected number, got $o")
    }
}
