package voxgig.struct

import com.google.gson.GsonBuilder
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.nio.file.Files
import java.nio.file.Paths
import java.util.TreeMap
import java.util.function.Function

/**
 * Mirror of java/src/test/StructCorpusTest.java. Drives every (category,name)
 * pair from build/test/test.json. Each pair becomes a DynamicTest that runs
 * the set, records pass/fail, and contributes to a per-file scoreboard.
 *
 * Like the Java port: this test never fails the build for shortfalls. Its
 * purpose is to track parity progress; StructTests / StructMinorTest remain
 * the green-bar regression baseline.
 */
@Suppress("UNCHECKED_CAST")
class StructCorpusTest {

    companion object {
        private val SCOREBOARD: MutableMap<String, CorpusRunner.Result> = TreeMap()
        private val CATEGORY_TO_FILE: Map<String, String> = linkedMapOf(
            "minor" to "minor.jsonic",
            "walk" to "walk.jsonic",
            "merge" to "merge.jsonic",
            "getpath" to "getpath.jsonic",
            "inject" to "inject.jsonic",
            "transform" to "transform.jsonic",
            "validate" to "validate.jsonic",
            "select" to "select.jsonic",
        )

        @JvmStatic
        @AfterAll
        fun printScoreboard() {
            val byFile: MutableMap<String, IntArray> = TreeMap()
            val failsByFile: MutableMap<String, MutableList<Array<String>>> = TreeMap()
            var totalP = 0
            var totalT = 0
            for ((key, r) in SCOREBOARD) {
                val cat = key.substringBefore('.')
                val file = CATEGORY_TO_FILE[cat] ?: "$cat.jsonic"
                val tot = byFile.getOrPut(file) { IntArray(2) }
                tot[0] += r.passed
                tot[1] += r.total
                failsByFile.getOrPut(file) { mutableListOf() }
                    .add(arrayOf(key, "${r.passed}/${r.total}"))
                totalP += r.passed
                totalT += r.total
            }
            val sb = StringBuilder()
            sb.append("\n========= STRUCT CORPUS SCOREBOARD =========\n")
            for ((file, tot) in byFile) {
                sb.append(String.format("  %-18s %4d / %4d%n", file, tot[0], tot[1]))
                for (sub in failsByFile[file]!!) {
                    sb.append(String.format("      %-30s %s%n", sub[0], sub[1]))
                }
            }
            sb.append(String.format("  %-18s %4d / %4d%n", "TOTAL", totalP, totalT))
            sb.append("============================================\n")
            // Print first 3 failures per non-100% case for debugging.
            for ((key, r) in SCOREBOARD) {
                if (r.passed < r.total) {
                    sb.append("--- $key (${r.passed}/${r.total}) ---\n")
                    for ((i, f) in r.failures.withIndex()) {
                        if (i >= 3) break
                        sb.append("  $f\n")
                    }
                }
            }
            println(sb)

            try {
                val out = linkedMapOf<String, Any?>()
                val files = linkedMapOf<String, Map<String, Int>>()
                for ((file, tot) in byFile) files[file] = linkedMapOf("passed" to tot[0], "total" to tot[1])
                out["files"] = files
                out["total"] = linkedMapOf("passed" to totalP, "total" to totalT)
                val target = Paths.get("build", "corpus-scoreboard.json")
                Files.createDirectories(target.parent)
                Files.writeString(target, GsonBuilder().setPrettyPrinting().create().toJson(out) + "\n")
            } catch (_: Exception) {
            }
        }
    }

    private fun getp(input: Any?, key: String): Any? = if (input is Map<*, *>) (input as Map<String, Any?>)[key] else null
    private fun getpDef(input: Any?, key: String, def: Any?): Any? =
        if (input is Map<*, *> && (input as Map<String, Any?>).containsKey(key)) input[key] else def

    @TestFactory
    fun corpus(): Iterable<DynamicTest> {
        val tests = mutableListOf<DynamicTest>()

        // ===== minor =====
        add(tests, "minor", "isnode", true) { Struct.isnode(it) }
        add(tests, "minor", "ismap", true) { Struct.ismap(it) }
        add(tests, "minor", "islist", true) { Struct.islist(it) }
        add(tests, "minor", "iskey", false) { Struct.iskey(it) }
        add(tests, "minor", "strkey", false) { Struct.strkey(it) }
        add(tests, "minor", "isempty", false) { Struct.isempty(it) }
        add(tests, "minor", "isfunc", true) { Struct.isfunc(it) }
        add(tests, "minor", "getprop", true) {
            val v = getp(it, "val"); val k = getp(it, "key"); val a = getpDef(it, "alt", Struct.UNDEF)
            if (a === Struct.UNDEF) Struct.getprop(v, k) else Struct.getprop(v, k, a)
        }
        add(tests, "minor", "getelem", true) {
            val v = getp(it, "val"); val k = getp(it, "key"); val a = getpDef(it, "alt", Struct.UNDEF)
            if (a === Struct.UNDEF) Struct.getelem(v, k) else Struct.getelem(v, k, a)
        }
        add(tests, "minor", "clone", false) { Struct.clone(it) }
        add(tests, "minor", "items", true) { Struct.items(it) }
        add(tests, "minor", "keysof", true) { Struct.keysof(it) }
        add(tests, "minor", "haskey", true) { Struct.haskey(getp(it, "src"), getp(it, "key")) }
        add(tests, "minor", "setprop", true) {
            val parent = getpDef(it, "parent", Struct.UNDEF)
            Struct.setprop(if (parent === Struct.UNDEF) null else parent, getp(it, "key"), getp(it, "val"))
        }
        add(tests, "minor", "delprop", true) {
            val parent = getpDef(it, "parent", Struct.UNDEF)
            Struct.delprop(if (parent === Struct.UNDEF) null else parent, getp(it, "key"))
        }
        add(tests, "minor", "size", false) { Struct.size(it) }
        add(tests, "minor", "typify", false) { Struct.typify(it) }
        add(tests, "minor", "typename", false) { Struct.typename(it) }
        add(tests, "minor", "slice", false) { Struct.slice(getp(it, "val"), getp(it, "start"), getp(it, "end")) }
        add(tests, "minor", "pad", false) { Struct.pad(getp(it, "val"), getp(it, "pad"), getp(it, "char")) }
        add(tests, "minor", "flatten", true) { Struct.flatten(getp(it, "val"), (getp(it, "depth") as? Number)?.toInt()) }
        add(tests, "minor", "filter", true) {
            val v = getp(it, "val")
            when (getp(it, "check")) {
                "gt3" -> Struct.filter(v) { item -> (item[1] as? Number)?.toDouble()?.let { d -> d > 3 } == true }
                "lt3" -> Struct.filter(v) { item -> (item[1] as? Number)?.toDouble()?.let { d -> d < 3 } == true }
                else -> Struct.filter(v) { true }
            }
        }
        add(tests, "minor", "escre", false) { Struct.escre(it) }
        add(tests, "minor", "escurl", false) { Struct.escurl(it) }
        add(tests, "minor", "join", false) { Struct.join(getp(it, "val"), getp(it, "sep"), getp(it, "url")) }
        add(tests, "minor", "stringify", false) {
            val hasVal = it is Map<*, *> && (it as Map<String, Any?>).containsKey("val")
            val v = if (hasVal) (it as Map<String, Any?>)["val"] else Struct.UNDEF
            val maxlen = (getp(it, "max") as? Number)?.toInt()
            if (maxlen == null) Struct.stringify(v) else Struct.stringify(v, maxlen)
        }
        add(tests, "minor", "jsonify", false) {
            val hasVal = it is Map<*, *> && (it as Map<String, Any?>).containsKey("val")
            val v = if (hasVal) (it as Map<String, Any?>)["val"] else Struct.UNDEF
            Struct.jsonify(v, getp(it, "flags"))
        }
        add(tests, "minor", "pathify", false) {
            val path = if (it is Map<*, *> && (it as Map<String, Any?>).containsKey("path")) it["path"] else Struct.UNDEF
            val from = (getp(it, "from") as? Number)?.toInt()
            if (from == null) Struct.pathify(path) else Struct.pathify(path, from)
        }
        add(tests, "minor", "setpath", false) {
            Struct.setpath(getp(it, "store"), getp(it, "path"), getp(it, "val"))
        }
        add(tests, "minor", "getdef", true) { Struct.getdef(getp(it, "val"), getp(it, "alt")) }

        // ===== walk =====
        add(tests, "walk", "basic", true) {
            Struct.walk(it, Struct.WalkApply { _, v, _, p -> if (v is String) v + "~" + p.joinToString(".") else v })
        }
        add(tests, "walk", "log", true) { Struct.clone(it) }
        add(tests, "walk", "depth", true) {
            val src = getp(it, "src")
            val maxdepth = (getp(it, "maxdepth") as? Number)?.toInt()
            val top = arrayOfNulls<Any>(1)
            val cur = arrayOfNulls<Any>(1)
            val copy = Struct.WalkApply { key, value, _, _ ->
                if (Struct.isnode(value)) {
                    val child: Any? = if (Struct.islist(value)) mutableListOf<Any?>() else linkedMapOf<String, Any?>()
                    if (key == null) { top[0] = child; cur[0] = child }
                    else { cur[0] = Struct.setprop(cur[0], key, child); cur[0] = child }
                } else if (key != null) {
                    cur[0] = Struct.setprop(cur[0], key, value)
                }
                value
            }
            if (maxdepth == null) Struct.walk(src, copy) else Struct.walk(src, copy, null, maxdepth)
            top[0]
        }

        // ===== merge =====
        add(tests, "merge", "cases", true) { Struct.merge(it) }
        add(tests, "merge", "array", true) { Struct.merge(it) }
        add(tests, "merge", "integrity", true) { Struct.merge(it) }
        add(tests, "merge", "depth", true) {
            val v = getp(it, "val"); val d = (getp(it, "depth") as? Number)?.toInt() ?: 32
            Struct.merge(v, d)
        }

        // ===== getpath =====
        add(tests, "getpath", "basic", true) { Struct.getpath(getp(it, "store"), getp(it, "path")) }
        add(tests, "getpath", "relative", true) {
            val inj: Struct.Injection? = (it as? Map<String, Any?>)?.let { m ->
                if (!m.containsKey("dparent") && !m.containsKey("dpath") && !m.containsKey("base")) null
                else Struct.Injection(null, null).apply {
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
            Struct.getpath(getp(it, "store"), getp(it, "path"), inj)
        }
        add(tests, "getpath", "special", true) {
            val injMap = getp(it, "inj") as? Map<String, Any?>
            val inj = injMap?.let { im ->
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

        // ===== inject =====
        add(tests, "inject", "string", true) { Struct.inject(getp(it, "val"), getp(it, "store")) }
        add(tests, "inject", "deep", true) { Struct.inject(getp(it, "val"), getp(it, "store")) }

        // ===== transform =====
        add(tests, "transform", "paths", true) { Struct.transform(getp(it, "data"), getp(it, "spec")) }
        add(tests, "transform", "cmds", true) { Struct.transform(getp(it, "data"), getp(it, "spec")) }
        add(tests, "transform", "each", true) { Struct.transform(getp(it, "data"), getp(it, "spec")) }
        add(tests, "transform", "pack", true) { Struct.transform(getp(it, "data"), getp(it, "spec")) }
        add(tests, "transform", "ref", true) { Struct.transform(getp(it, "data"), getp(it, "spec")) }
        add(tests, "transform", "format", false) { Struct.transform(getp(it, "data"), getp(it, "spec")) }
        add(tests, "transform", "modify", true) {
            val opts = linkedMapOf<String, Any?>(
                "modify" to Struct.Modify { v, k, parent, _, _ ->
                    if (k != null && parent is MutableMap<*, *> && v is String) {
                        @Suppress("UNCHECKED_CAST")
                        (parent as MutableMap<String, Any?>)[k.toString()] = "@$v"
                    }
                }
            )
            Struct.transform(getp(it, "data"), getp(it, "spec"), opts)
        }
        add(tests, "transform", "apply", true) {
            val opts = linkedMapOf<String, Any?>("extra" to linkedMapOf<String, Any?>(
                "apply" to Function<Any?, Any?> { v -> if (v is String) v.uppercase() else v }
            ))
            Struct.transform(getp(it, "data"), getp(it, "spec"), opts)
        }

        // ===== validate =====
        add(tests, "validate", "basic", true) { Struct.validate(getp(it, "data"), getp(it, "spec")) }
        add(tests, "validate", "child", true) { Struct.validate(getp(it, "data"), getp(it, "spec")) }
        add(tests, "validate", "one", true) { Struct.validate(getp(it, "data"), getp(it, "spec")) }
        add(tests, "validate", "exact", true) { Struct.validate(getp(it, "data"), getp(it, "spec")) }
        add(tests, "validate", "invalid", true) { Struct.validate(getp(it, "data"), getp(it, "spec")) }
        add(tests, "validate", "special", true) {
            val inj = (getp(it, "inj") as? Map<String, Any?>)
            Struct.validate(getp(it, "data"), getp(it, "spec"), inj)
        }

        // ===== select =====
        add(tests, "select", "basic", true) { Struct.select(getp(it, "obj"), getp(it, "query")) }
        add(tests, "select", "operators", true) { Struct.select(getp(it, "obj"), getp(it, "query")) }
        add(tests, "select", "edge", true) { Struct.select(getp(it, "obj"), getp(it, "query")) }
        add(tests, "select", "alts", true) { Struct.select(getp(it, "obj"), getp(it, "query")) }

        return tests
    }

    private fun add(
        tests: MutableList<DynamicTest>,
        category: String,
        name: String,
        nullFlag: Boolean,
        subject: CorpusRunner.Subject,
    ) {
        tests.add(DynamicTest.dynamicTest("$category-$name") {
            val spec = try { CorpusRunner.getSpec(category, name) } catch (_: Exception) { return@dynamicTest }
            val r = CorpusRunner.runsetflags("$category.$name", spec, nullFlag, subject)
            SCOREBOARD["$category.$name"] = r
        })
    }
}
