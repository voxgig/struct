package voxgig.struct

import voxgig.omni.Flags
import voxgig.omni.Json
import java.util.function.Function
import kotlin.test.BeforeTest
import kotlin.test.Test

/**
 * The shared corpus, run on the shared runner.
 *
 * The in-situ runner (CorpusRunner.kt) is gone. Every group is driven through
 * voxgig/omni, so this file only says WHICH subject answers each group and
 * with which flags - the entry loop, the comparison, the `err` and `match`
 * handling all live in the runner, identically for every port.
 *
 * Flags mirror canonical: typescript/test/utility/StructUtility.test.ts.
 */
@Suppress("UNCHECKED_CAST", "LargeClass", "TooManyFunctions")
class StructCorpusTest {
    private lateinit var run: Omni.Run

    @BeforeTest
    fun init() {
        run = Omni.Run.of("struct")
    }

    private fun group(vararg path: String): Json = run.group(*path)

    private fun runset(
        vararg path: String,
        subject: Omni.StructSubject,
    ) = run.runsetflags(group(*path), Flags(name = path.joinToString(".")), subject)

    private fun runsetnull(
        vararg path: String,
        donull: Boolean,
        subject: Omni.StructSubject,
    ) = run.runsetflags(group(*path), Flags(nulls = donull, name = path.joinToString(".")), subject)

    private fun getp(
        input: Any?,
        key: String,
    ): Any? = if (input is Map<*, *>) (input as Map<String, Any?>)[key] else null

    private fun getpDef(
        input: Any?,
        key: String,
        def: Any?,
    ): Any? = if (input is Map<*, *> && (input as Map<String, Any?>).containsKey(key)) input[key] else def

    // ===== minor =====

    @Test fun minorIsnode() = runset("minor", "isnode") { Struct.isnode(it) }

    @Test fun minorIsmap() = runset("minor", "ismap") { Struct.ismap(it) }

    @Test fun minorIslist() = runset("minor", "islist") { Struct.islist(it) }

    @Test fun minorIskey() = runsetnull("minor", "iskey", donull = false) { Struct.iskey(it) }

    @Test fun minorStrkey() = runsetnull("minor", "strkey", donull = false) { Struct.strkey(it) }

    @Test fun minorIsempty() = runsetnull("minor", "isempty", donull = false) { Struct.isempty(it) }

    @Test fun minorIsfunc() = runset("minor", "isfunc") { Struct.isfunc(it) }

    @Test
    fun minorGetprop() =
        runsetnull("minor", "getprop", donull = false) {
            val v = getp(it, "val")
            val k = getp(it, "key")
            // Canonical omits `alt` only when the KEY is missing
            // (`undefined === vin.alt`), so an explicit `alt: null` is passed
            // through - unlike getelem below, which omits a null alt too.
            if (it is Map<*, *> && (it as Map<String, Any?>).containsKey("alt")) {
                Struct.getprop(v, k, it["alt"])
            } else {
                Struct.getprop(v, k)
            }
        }

    @Test
    fun minorGetelem() =
        runsetnull("minor", "getelem", donull = false) {
            val v = getp(it, "val")
            val k = getp(it, "key")
            val a = getpDef(it, "alt", Struct.UNDEF)
            if (a === Struct.UNDEF || null == a) Struct.getelem(v, k) else Struct.getelem(v, k, a)
        }

    @Test fun minorClone() = runsetnull("minor", "clone", donull = false) { Struct.clone(it) }

    @Test fun minorItems() = runset("minor", "items") { Struct.items(it) }

    @Test fun minorKeysof() = runset("minor", "keysof") { Struct.keysof(it) }

    @Test
    fun minorHaskey() = runsetnull("minor", "haskey", donull = false) { Struct.haskey(getp(it, "src"), getp(it, "key")) }

    @Test
    fun minorSetprop() =
        runset("minor", "setprop") {
            val parent = getpDef(it, "parent", Struct.UNDEF)
            Struct.setprop(if (parent === Struct.UNDEF) null else parent, getp(it, "key"), getp(it, "val"))
        }

    @Test
    fun minorDelprop() =
        runset("minor", "delprop") {
            val parent = getpDef(it, "parent", Struct.UNDEF)
            Struct.delprop(if (parent === Struct.UNDEF) null else parent, getp(it, "key"))
        }

    @Test fun minorSize() = runsetnull("minor", "size", donull = false) { Struct.size(it) }

    @Test fun minorTypify() = runsetnull("minor", "typify", donull = false) { Struct.typify(it) }

    @Test fun minorTypename() = runset("minor", "typename") { Struct.typename(it) }

    @Test
    fun minorSlice() =
        runsetnull("minor", "slice", donull = false) {
            Struct.slice(getp(it, "val"), getp(it, "start"), getp(it, "end"))
        }

    @Test
    fun minorPad() =
        runsetnull("minor", "pad", donull = false) {
            Struct.pad(getp(it, "val"), getp(it, "pad"), getp(it, "char"))
        }

    @Test
    fun minorFlatten() = runset("minor", "flatten") { Struct.flatten(getp(it, "val"), (getp(it, "depth") as? Number)?.toInt()) }

    @Test
    fun minorFilter() =
        runset("minor", "filter") {
            val v = getp(it, "val")
            when (getp(it, "check")) {
                "gt3" -> Struct.filter(v) { item -> (item[1] as? Number)?.toDouble()?.let { d -> d > 3 } == true }
                "lt3" -> Struct.filter(v) { item -> (item[1] as? Number)?.toDouble()?.let { d -> d < 3 } == true }
                else -> Struct.filter(v) { true }
            }
        }

    @Test fun minorEscre() = runset("minor", "escre") { Struct.escre(it) }

    @Test fun minorEscurl() = runset("minor", "escurl") { Struct.escurl(it) }

    @Test
    fun minorJoin() =
        runsetnull("minor", "join", donull = false) {
            Struct.join(getp(it, "val"), getp(it, "sep"), getp(it, "url"))
        }

    @Test
    fun minorStringify() =
        runset("minor", "stringify") {
            val hasVal = it is Map<*, *> && (it as Map<String, Any?>).containsKey("val")
            // This group runs with `null: true`, so a corpus null arrives as
            // the NULLMARK string. Canonical hands `stringify` the word it
            // would print.
            val raw = if (hasVal) (it as Map<String, Any?>)["val"] else Struct.UNDEF
            val v = if (Omni.NULLMARK == raw) "null" else raw
            val maxlen = (getp(it, "max") as? Number)?.toInt()
            if (maxlen == null) Struct.stringify(v) else Struct.stringify(v, maxlen)
        }

    @Test
    fun minorJsonify() =
        runsetnull("minor", "jsonify", donull = false) {
            val hasVal = it is Map<*, *> && (it as Map<String, Any?>).containsKey("val")
            val v = if (hasVal) (it as Map<String, Any?>)["val"] else Struct.UNDEF
            Struct.jsonify(v, getp(it, "flags"))
        }

    @Test
    fun minorPathify() =
        runset("minor", "pathify") {
            // `null: true`, so an absent path arrives as NULLMARK and the
            // rendered path has to be put back the way canonical renders a
            // real undefined.
            val raw = if (it is Map<*, *> && (it as Map<String, Any?>).containsKey("path")) it["path"] else Struct.UNDEF
            val marked = Omni.NULLMARK == raw
            val path = if (marked) Struct.UNDEF else raw
            val from = (getp(it, "from") as? Number)?.toInt()
            var text = if (from == null) Struct.pathify(path) else Struct.pathify(path, from)
            text = text.replaceFirst(Omni.NULLMARK + ".", "")
            if (marked) text.replace(">", ":null>") else text
        }

    @Test
    fun minorSetpath() =
        runsetnull("minor", "setpath", donull = false) {
            Struct.setpath(getp(it, "store"), getp(it, "path"), getp(it, "val"))
        }

    // ===== walk =====

    @Test
    fun walkBasic() =
        runset("walk", "basic") {
            Struct.walk(it, Struct.WalkApply { _, v, _, p -> if (v is String) v + "~" + p.joinToString(".") else v })
        }

    @Test
    fun walkDepth() =
        runsetnull("walk", "depth", donull = false) {
            val src = getp(it, "src")
            val maxdepth = (getp(it, "maxdepth") as? Number)?.toInt()
            val top = arrayOfNulls<Any>(1)
            val cur = arrayOfNulls<Any>(1)
            val copy =
                Struct.WalkApply { key, value, _, _ ->
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
            if (maxdepth == null) Struct.walk(src, copy) else Struct.walk(src, copy, null, maxdepth)
            top[0]
        }

    @Test
    fun walkCopy() =
        runset("walk", "copy") {
            val cur = mutableListOf<Any?>()
            val walkcopy =
                Struct.WalkApply { key, value, _, path ->
                    if (key == null) {
                        cur.clear()
                        cur.add(
                            if (Struct.ismap(value)) {
                                linkedMapOf<String, Any?>()
                            } else if (Struct.islist(value)) {
                                mutableListOf<Any?>()
                            } else {
                                value
                            },
                        )
                    } else {
                        val depth = path.size
                        var child = value
                        if (Struct.isnode(value)) {
                            child = if (Struct.ismap(value)) linkedMapOf<String, Any?>() else mutableListOf<Any?>()
                            while (cur.size <= depth) cur.add(null)
                            cur[depth] = child
                        }
                        Struct.setprop(cur[depth - 1], key, child)
                    }
                    value
                }
            Struct.walk(it, walkcopy)
            cur.firstOrNull()
        }

    // ===== merge =====

    @Test fun mergeCases() = runset("merge", "cases") { Struct.merge(it) }

    @Test fun mergeArray() = runset("merge", "array") { Struct.merge(it) }

    @Test fun mergeIntegrity() = runset("merge", "integrity") { Struct.merge(it) }

    @Test
    fun mergeDepth() =
        runset("merge", "depth") {
            val v = getp(it, "val")
            val d = (getp(it, "depth") as? Number)?.toInt() ?: 32
            Struct.merge(v, d)
        }

    // ===== getpath =====

    @Test
    fun getpathBasic() = runset("getpath", "basic") { Struct.getpath(getp(it, "store"), getp(it, "path")) }

    @Test
    fun getpathRelative() =
        runset("getpath", "relative") {
            val inj: Struct.Injection? =
                (it as? Map<String, Any?>)?.let { m ->
                    if (!m.containsKey("dparent") && !m.containsKey("dpath") && !m.containsKey("base")) {
                        null
                    } else {
                        Struct.Injection(null, null).apply {
                            if (m.containsKey("dparent")) dparent = m["dparent"]
                            if (m.containsKey("dpath")) {
                                when (val dp = m["dpath"]) {
                                    is List<*> -> dpath = dp.map { e -> e?.toString() ?: "" }.toMutableList()
                                    is String -> if (dp.isNotEmpty()) dpath = dp.split(".").toMutableList()
                                }
                            }
                            if (m.containsKey("base") && m["base"] is String) base = m["base"] as String
                        }
                    }
                }
            Struct.getpath(getp(it, "store"), getp(it, "path"), inj)
        }

    @Test
    fun getpathSpecial() =
        runset("getpath", "special") {
            val injMap = getp(it, "inj") as? Map<String, Any?>
            val inj =
                injMap?.let { im ->
                    Struct.Injection(null, null).apply {
                        if (im.containsKey("key")) key = im["key"]?.toString() ?: ""
                        if (im.containsKey("dparent")) dparent = im["dparent"]
                        if (im.containsKey("dpath")) {
                            val dp = im["dpath"]
                            if (dp is List<*>) dpath = dp.map { e -> e?.toString() ?: "" }.toMutableList()
                        }
                        if (im.containsKey("meta")) {
                            val mm = im["meta"]
                            if (mm is Map<*, *>) {
                                meta = linkedMapOf<String, Any?>().also { for ((k, v) in mm) it[k.toString()] = v }
                            }
                        }
                    }
                }
            Struct.getpath(getp(it, "store"), getp(it, "path"), inj)
        }

    @Test
    fun getpathHandler() =
        runset("getpath", "handler") {
            // The handler resolves a `$`-prefixed store entry that is a
            // FUNCTION: the store holds `$FOO`, and the handler calls it.
            // Nothing else in the corpus exercises `Injection.handler`.
            val store =
                linkedMapOf<String, Any?>(
                    "\$TOP" to getp(it, "store"),
                    "\$FOO" to Struct.Injector { _, _, _, _ -> "foo" },
                )
            val inj =
                Struct.Injection(null, null).apply {
                    handler =
                        Struct.Injector { cinj, v, ref, cstore ->
                            if (v is Struct.Injector) v.apply(cinj, v, ref, cstore) else v
                        }
                }
            Struct.getpath(store, getp(it, "path"), inj)
        }

    // ===== inject =====

    @Test
    fun injectString() =
        runset("inject", "string") {
            // The runner encodes "value is JSON null" as NULLMARK so it
            // survives a JSON round trip; this modifier puts a real null back
            // as the structure is built.
            val inj = Struct.Injection(null, null)
            inj.modify =
                Struct.Modify { v, k, parent, _, _ ->
                    if (k != null && Struct.isnode(parent) && v is String) {
                        if (Omni.NULLMARK == v) {
                            Struct.setprop(parent, k, null)
                        } else if (v.contains(Omni.NULLMARK)) {
                            Struct.setprop(parent, k, v.replace(Omni.NULLMARK, "null"))
                        }
                    }
                }
            Struct.inject(getp(it, "val"), getp(it, "store"), inj)
        }

    @Test fun injectDeep() = runset("inject", "deep") { Struct.inject(getp(it, "val"), getp(it, "store")) }

    // ===== transform =====

    @Test fun transformPaths() = runset("transform", "paths") { Struct.transform(getp(it, "data"), getp(it, "spec")) }

    @Test fun transformCmds() = runset("transform", "cmds") { Struct.transform(getp(it, "data"), getp(it, "spec")) }

    @Test fun transformEach() = runset("transform", "each") { Struct.transform(getp(it, "data"), getp(it, "spec")) }

    @Test fun transformPack() = runset("transform", "pack") { Struct.transform(getp(it, "data"), getp(it, "spec")) }

    @Test fun transformRef() = runset("transform", "ref") { Struct.transform(getp(it, "data"), getp(it, "spec")) }

    @Test
    fun transformFormat() = runsetnull("transform", "format", donull = false) { Struct.transform(getp(it, "data"), getp(it, "spec")) }

    @Test
    fun transformModify() =
        runset("transform", "modify") {
            val opts =
                linkedMapOf<String, Any?>(
                    "modify" to
                        Struct.Modify { v, k, parent, _, _ ->
                            if (k != null && parent is MutableMap<*, *> && v is String) {
                                (parent as MutableMap<String, Any?>)[k.toString()] = "@$v"
                            }
                        },
                )
            Struct.transform(getp(it, "data"), getp(it, "spec"), opts)
        }

    @Test
    fun transformApply() =
        runset("transform", "apply") {
            val opts =
                linkedMapOf<String, Any?>(
                    "extra" to
                        linkedMapOf<String, Any?>(
                            "apply" to Function<Any?, Any?> { v -> if (v is String) v.uppercase() else v },
                        ),
                )
            Struct.transform(getp(it, "data"), getp(it, "spec"), opts)
        }

    // ===== validate =====

    @Test
    fun validateBasic() = runsetnull("validate", "basic", donull = false) { Struct.validate(getp(it, "data"), getp(it, "spec")) }

    @Test fun validateChild() = runset("validate", "child") { Struct.validate(getp(it, "data"), getp(it, "spec")) }

    @Test fun validateOne() = runset("validate", "one") { Struct.validate(getp(it, "data"), getp(it, "spec")) }

    @Test fun validateExact() = runset("validate", "exact") { Struct.validate(getp(it, "data"), getp(it, "spec")) }

    @Test
    fun validateInvalid() = runsetnull("validate", "invalid", donull = false) { Struct.validate(getp(it, "data"), getp(it, "spec")) }

    @Test
    fun validateSpecial() =
        runset("validate", "special") {
            val inj = (getp(it, "inj") as? Map<String, Any?>)
            Struct.validate(getp(it, "data"), getp(it, "spec"), inj)
        }

    // ===== select =====

    @Test fun selectBasic() = runset("select", "basic") { Struct.select(getp(it, "obj"), getp(it, "query")) }

    @Test fun selectOperators() = runset("select", "operators") { Struct.select(getp(it, "obj"), getp(it, "query")) }

    @Test fun selectEdge() = runset("select", "edge") { Struct.select(getp(it, "obj"), getp(it, "query")) }

    @Test fun selectAlts() = runset("select", "alts") { Struct.select(getp(it, "obj"), getp(it, "query")) }

    @Test
    fun selectNullkey() =
        // `null: false` keeps a JSON null an ACTUAL null rather than the
        // NULLMARK string, so select sees a present-but-null field.
        runsetnull("select", "nullkey", donull = false) { Struct.select(getp(it, "obj"), getp(it, "query")) }

    // ===== regex (parity floor: Go stdlib regexp; REGEX_API.md) =====

    @Test
    fun regexTest() = runset("regex", "test") { Struct.reTest(getp(it, "pattern") as String, getp(it, "input") as String) }

    @Test
    fun regexFind() = runset("regex", "find") { Struct.reFind(getp(it, "pattern") as String, getp(it, "input") as String) }

    @Test
    fun regexFindAll() = runset("regex", "find_all") { Struct.reFindAll(getp(it, "pattern") as String, getp(it, "input") as String) }

    @Test
    fun regexReplace() =
        runset("regex", "replace") {
            Struct.reReplace(
                getp(it, "pattern") as String,
                getp(it, "input") as String,
                getp(it, "replacement") as String,
            )
        }

    @Test fun regexEscape() = runset("regex", "escape") { Struct.reEscape(getp(it, "val") as String) }

    // ===== sentinels: null and absent unified on observation =====

    @Test
    fun sentinelsGetpropUnify() =
        runsetnull("sentinels", "getprop_unify", donull = false) {
            Struct.getprop(getp(it, "val"), getp(it, "key"), getp(it, "alt"))
        }

    @Test
    fun sentinelsGetelemAbsent() =
        runsetnull("sentinels", "getelem_absent", donull = false) {
            Struct.getelem(getp(it, "val"), getp(it, "key"), getp(it, "alt"))
        }

    @Test
    fun sentinelsHaskeyUnify() =
        runsetnull("sentinels", "haskey_unify", donull = false) {
            Struct.haskey(getp(it, "val"), getp(it, "key"))
        }

    @Test
    fun sentinelsIsemptyUnify() = runsetnull("sentinels", "isempty_unify", donull = false) { Struct.isempty(it) }

    @Test
    fun sentinelsIsnodeUnify() = runsetnull("sentinels", "isnode_unify", donull = false) { Struct.isnode(it) }

    @Test
    fun sentinelsStringifyNull() = runsetnull("sentinels", "stringify_null", donull = false) { Struct.stringify(it) }
}
