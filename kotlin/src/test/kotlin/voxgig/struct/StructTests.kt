package voxgig.struct

import java.util.function.Function
import java.util.function.Supplier
import kotlin.math.floor
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotSame
import kotlin.test.assertSame
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

    // The `minor.isfunc` corpus group is nine entries and every one expects
    // FALSE - no JSON value is callable, so the corpus alone cannot tell a
    // working isfunc from `return false`. This is the positive case, and it
    // matters beyond the predicate: isfunc is what gates injector command
    // dispatch. It carried over from StructMinorTest.exists(), which the
    // migration deleted along with the rest of that file.
    @Test
    fun isfuncPositive() {
        assertTrue(Struct.isfunc { _: Any? -> null })
        assertEquals("map", Struct.typename(Struct.T_MAP))
    }

    // A null list element is stored, not removed: the corpus runner turns
    // nulls into markers, so it cannot see the slot.
    @Test
    fun setpropNull() {
        assertEquals(listOf<Any?>(1, null, 3), Struct.setprop(mutableListOf<Any?>(1, 2, 3), 1, null))
        assertEquals(listOf<Any?>(1, null, 3), Struct.setprop(mutableListOf<Any?>(1, 2, 3), "1", null))
        assertEquals(listOf<Any?>(1, 2, 3, null), Struct.setprop(mutableListOf<Any?>(1, 2, 3), 5, null))
        assertEquals(listOf<Any?>(null, 1, 2, 3), Struct.setprop(mutableListOf<Any?>(1, 2, 3), -1, null))
    }

    @Test
    fun setpathNull() {
        val store = linkedMapOf<String, Any?>("a" to mutableListOf<Any?>(1, 2, 3))
        assertEquals(listOf<Any?>(1, null, 3), Struct.setpath(store, "a.1", null))
        assertEquals(mapOf<String, Any?>("a" to listOf(1, null, 3)), store)
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

    // The corpus runner turns nulls into markers, so it cannot see a list
    // slot that walk's write-back removes.
    @Test
    fun walkNull() {
        val list = mutableListOf<Any?>(null, 2, 3)
        val out = Struct.walk(list, Struct.WalkApply { _, v, _, _ -> v })
        assertEquals(listOf<Any?>(null, 2, 3), out)
        assertEquals(listOf<Any?>(null, 2, 3), list)
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

        // A later element keeps its nulls: the corpus runner turns them into
        // markers, so it cannot see a list slot removed.
        val n0 =
            linkedMapOf<String, Any?>(
                "a" to linkedMapOf<String, Any?>("c" to null),
                "d" to null,
                "e" to mutableListOf<Any?>(null),
            )
        val base =
            linkedMapOf<String, Any?>(
                "a" to linkedMapOf<String, Any?>("b" to 1),
                "e" to mutableListOf<Any?>(2, 3),
            )
        var out = Struct.merge(listOf(base, n0))
        assertEquals(
            mapOf<String, Any?>("a" to mapOf("b" to 1, "c" to null), "d" to null, "e" to listOf(null, 3)),
            out,
        )
        assertEquals(mapOf<String, Any?>("a" to mapOf("c" to null), "d" to null, "e" to listOf(null)), n0)

        val l0 = mutableListOf<Any?>(1, null, 3)
        out = Struct.merge(listOf(mutableListOf<Any?>(7, 8, 9, 10), l0))
        assertEquals(listOf<Any?>(1, null, 3, 10), out)
        assertEquals(listOf<Any?>(1, null, 3), l0)

        val l1 = mutableListOf<Any?>(null, 5)
        out = Struct.merge(listOf(mutableListOf<Any?>(7, 8, 9), l1), 1)
        assertEquals(listOf<Any?>(null, 5, 9), out)
        assertEquals(listOf<Any?>(null, 5), l1)

        // At the depth limit a longer override still grows the output.
        val g0 = linkedMapOf<String, Any?>("a" to mutableListOf<Any?>(7, 8))
        out = Struct.merge(listOf(linkedMapOf<String, Any?>("a" to mutableListOf<Any?>(1)), g0), 2)
        assertEquals(mapOf<String, Any?>("a" to listOf(7, 8)), out)
        assertEquals(mapOf<String, Any?>("a" to listOf(7, 8)), g0)

        val g1 = mutableListOf<Any?>(6, 5)
        out = Struct.merge(listOf(mutableListOf<Any?>(7), g1), 1)
        assertEquals(listOf<Any?>(6, 5), out)
        assertEquals(listOf<Any?>(6, 5), g1)

        val g2 = mutableListOf<Any?>(null, null, null)
        out = Struct.merge(listOf(mutableListOf<Any?>(1, 2), g2), 1)
        assertEquals(listOf<Any?>(null, null, null), out)
        assertEquals(listOf<Any?>(null, null, null), g2)
    }

    @Test
    fun getpathExists() {
        assertEquals(1L, normalize(Struct.getpath(mapOf("a" to 1), "a")))
    }

    // Condense: identity, sharing, laziness and the immutability contract.

    @Test
    fun condenseDeterministic() {
        val src = Struct.jm("b", Struct.jm("m", "GET"), "a", Struct.jm("m", "GET"), "l", Struct.jt(1, "x", true))
        assertEquals(Struct.jsonify(Struct.condense(src)), Struct.jsonify(Struct.condense(src)))
        // Insertion order must not change the bytes: keys are stored by symbol id.
        val reordered = Struct.jm("l", Struct.jt(1, "x", true), "a", Struct.jm("m", "GET"), "b", Struct.jm("m", "GET"))
        assertEquals(Struct.jsonify(Struct.condense(src)), Struct.jsonify(Struct.condense(reordered)))
    }

    @Test
    fun condenseSharesIdenticalSubtrees() {
        val one = Struct.condense(Struct.jm("x", Struct.jm("m", "GET", "p", "/1")))
        val two = Struct.condense(Struct.jm("x", Struct.jm("m", "GET", "p", "/1"), "y", Struct.jm("m", "GET", "p", "/1")))
        // A second reference to an identical subtree adds no node.
        assertEquals(Struct.size(one["node"]), Struct.size(two["node"]))
        val three = Struct.condense(Struct.jm("x", Struct.jm("m", "GET"), "y", Struct.jm("m", "PUT"), "z", Struct.jm("m", "POST")))
        assertTrue(Struct.size(three["node"]) > Struct.size(two["node"]))
    }

    @Test
    fun condenseRoundTripsByValue() {
        val src = Struct.jm("a", Struct.jm("b", Struct.jt(1, "x", true, null, Struct.jm())), "c", "z")
        assertEquals<Any?>(src, Struct.expand(Struct.condense(src)))
    }

    @Test
    fun condenseGetpathIsTransparent() {
        val src = Struct.jm("entity", Struct.jm("p", Struct.jm("op", Struct.jm("list", Struct.jm("method", "GET")))))
        val c = Struct.condense(src)
        assertEquals(
            Struct.getpath(src, listOf("entity", "p", "op", "list")),
            Struct.getpath(c, listOf("entity", "p", "op", "list")),
        )
        assertEquals<Any?>("GET", Struct.getpath(c, listOf("entity", "p", "op", "list", "method")))
        assertSame(Struct.UNDEF, Struct.getpath(c, listOf("entity", "nope")))
    }

    @Test
    fun condenseViewReadsWithoutMaterialising() {
        val c = Struct.condense(Struct.jm("entity", Struct.jm("a", Struct.jm("v", 1), "b", Struct.jm("v", 2)), "other", 9))
        val v = Struct.condenseview(c)
        // keys() answers from the node and symbol tables alone.
        assertEquals(listOf("a", "b"), v.keys("entity"))
        assertEquals<Any?>(2, v.at("entity").at("b").get("v"))
        assertTrue(v.has("entity.a"))
        assertFalse(v.has("entity.zz"))
        assertEquals(2, v.size())
    }

    @Test
    fun condenseValueCopiesAndRefShares() {
        val c = Struct.condense(Struct.jm("a", Struct.jm("m", "GET"), "b", Struct.jm("m", "GET")))
        val v = Struct.condenseview(c)
        // a and b share one node; get() must not let that be observable.
        val x = v.get("a") as MutableMap<String, Any?>
        val y = v.get("b")
        assertEquals<Any?>(x, y)
        assertNotSame<Any?>(x, y)
        x["m"] = "MUTATED"
        assertEquals<Any?>("GET", Struct.getprop(v.get("b"), "m"))
        // ref() is the opt-in escape hatch and does share.
        assertSame(v.at("a").ref(), v.at("a").ref())
    }

    @Test
    fun condensePreservesProtoNamedKeysAndValues() {
        val asValue = Struct.jm("x", "__proto__")
        assertEquals<Any?>(asValue, Struct.expand(Struct.condense(asValue)))
        val asKey = Struct.jm("__proto__", 1)
        assertEquals("{\"__proto__\":1}", Struct.jsonify(Struct.expand(Struct.condense(asKey)), mapOf("indent" to 0)))
    }

    @Test
    fun condenseGetpathMatchesPlainOnNullAndOptions() {
        // Group A: a stored null reads as absent either way.
        val nullval = Struct.jm("a", null)
        assertEquals(Struct.getpath(nullval, "a"), Struct.getpath(Struct.condense(nullval), "a"))
        assertSame(Struct.UNDEF, Struct.getpath(Struct.condense(nullval), "a"))
        // A base must not be ignored by the condensed fast path.
        val store = Struct.jm("base", Struct.jm("x", 1))
        val inj = Struct.Injection(null, null).apply { base = "base" }
        assertEquals(Struct.getpath(store, "x", inj), Struct.getpath(Struct.condense(store), "x", inj))
        assertEquals<Any?>(1, Struct.getpath(Struct.condense(store), "x", inj))
    }

    @Test
    fun condenseListKeysAreCanonicalIntegers() {
        val plain = Struct.jm("l", Struct.jt(10, 20))
        val c = Struct.condense(plain)
        // A plain list read misses each of these, and condensing must not change
        // which value a path selects.
        for (k in listOf("01", "1e0", " 1", "+1", "1.0", "-0")) {
            assertEquals(Struct.getpath(plain, listOf("l", k)), Struct.getpath(c, listOf("l", k)), "list key $k")
        }
        assertEquals<Any?>(20, Struct.getpath(c, listOf("l", "1")))
    }

    @Test
    fun condenseSymbolsSortByCodePoint() {
        val sym = Struct.condense(Struct.jm("a", "\uD800\uDC00", "b", "\uFFFF"))["sym"] as List<Any?>
        assertTrue(sym.indexOf("\uFFFF") < sym.indexOf("\uD800\uDC00"), "symbol table is not in code-point order: $sym")
    }

    @Test
    fun condenseInvalidKeyMutationsStayNoOps() {
        // An invalid key is ignored, so a call that cannot write must not raise.
        val c = Struct.condense(Struct.jm("a", 1))
        assertSame(c, Struct.delprop(c, Struct.UNDEF))
        assertSame(c, Struct.setprop(c, Struct.UNDEF, 1))
        // A call that could write still raises.
        assertImmutable { Struct.delprop(c, "sym") }
    }

    @Test
    fun condenseIsImmutable() {
        val c = Struct.condense(Struct.jm("a", 1))
        assertImmutable { Struct.setpath(c, "a", 2) }
        assertImmutable { Struct.setprop(c, "a", 2) }
        assertImmutable { Struct.delprop(c, "sym") }
        // The expanded copy is ordinary and mutable.
        val e = Struct.expand(c) as Map<*, *>
        Struct.setpath(e, "a", 2)
        assertEquals<Any?>(2, e["a"])
    }

    private fun assertImmutable(call: () -> Unit) {
        val err = assertFailsWith<IllegalArgumentException> { call() }
        assertTrue(err.message.orEmpty().contains("immutable"), err.message)
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
    fun validateUnknownEdge() {
        // Only the unknown name is reported, and the data comes back as it is.
        val errs = mutableListOf<Any?>()
        val data = linkedMapOf<String, Any?>("a" to "x")
        var out =
            Struct.validate(
                data,
                mapOf("a" to listOf("`\$ONE`", "`\$STRING`", "`\$NIL`")),
                linkedMapOf<String, Any?>("errs" to errs),
            )
        assertEquals(listOf<Any?>("Unknown validator \$ONE at field a.0."), errs)
        assertEquals(normalize(data), normalize(out))

        // A checker supplied in extra is defined, in any case.
        val even =
            Struct.Injector { inj, _, _, _ ->
                val n = Struct.getprop(inj.dparent, inj.key)
                if (0L != (n as Number).toLong() % 2) {
                    inj.errs.add("Odd at " + inj.path.drop(1).joinToString(".") + ": " + Struct.stringify(n))
                }
                n
            }

        errs.clear()
        var extra = linkedMapOf<String, Any?>("\$EVEN" to even)
        out = Struct.validate(mapOf("n" to 2), mapOf("n" to "`\$EVEN`"), linkedMapOf("extra" to extra, "errs" to errs))
        assertEquals(normalize(mapOf("n" to 2)), normalize(out))
        extra = linkedMapOf("\$even" to even)
        out = Struct.validate(mapOf("n" to 3), mapOf("n" to "`\$even`"), linkedMapOf("extra" to extra, "errs" to errs))
        assertEquals(normalize(mapOf("n" to 3)), normalize(out))
        assertEquals(listOf<Any?>("Odd at n: 3"), errs)

        // A null in extra takes a checker away.
        errs.clear()
        Struct.validate("x", "`\$STRING`", linkedMapOf("extra" to linkedMapOf<String, Any?>("\$STRING" to null), "errs" to errs))
        assertEquals(listOf<Any?>("Unknown validator \$STRING at field <root>."), errs)
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
