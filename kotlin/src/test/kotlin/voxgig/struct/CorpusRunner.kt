package voxgig.struct

import com.google.gson.GsonBuilder
import com.google.gson.reflect.TypeToken
import java.nio.file.Files
import java.nio.file.Paths
import java.util.TreeMap

/**
 * Mirrors java/src/test/Runner.java: drives the shared corpus at
 * build/test/test.json against a `Subject` mapping each entry's `in` to a
 * call result. Counts per-entry pass/fail; never throws on shortfall.
 */
object CorpusRunner {
    private val GSON = GsonBuilder().serializeNulls().create()

    @Volatile
    private var CORPUS: Map<String, Any?>? = null

    fun loadCorpus(): Map<String, Any?> {
        var c = CORPUS
        if (c != null) return c
        synchronized(this) {
            c = CORPUS
            if (c != null) return c!!
            val candidates =
                listOf(
                    Paths.get("..", "build", "test", "test.json"),
                    Paths.get("build", "test", "test.json"),
                )
            val path =
                candidates.firstOrNull { Files.exists(it) }
                    ?: throw IllegalStateException("corpus not found: tried ${candidates.joinToString()}")
            val json = Files.readString(path)
            val type = object : TypeToken<Map<String, Any?>>() {}.type
            val parsed: Map<String, Any?> = GSON.fromJson(json, type)
            CORPUS = parsed
            return parsed
        }
    }

    @Suppress("UNCHECKED_CAST")
    fun getSpec(
        category: String,
        name: String,
    ): Map<String, Any?> {
        val all = loadCorpus()
        val struct = all["struct"] as Map<String, Any?>
        val cat =
            struct[category] as? Map<String, Any?>
                ?: throw IllegalArgumentException("Unknown category: $category")
        return (cat[name] as? Map<String, Any?>)
            ?: throw IllegalArgumentException("Unknown spec: $category.$name")
    }

    fun interface Subject {
        fun apply(input: Any?): Any?
    }

    // NULLMARK convention (mirrors java/src/test/Runner.java + canonical TS
    // runner.ts). When a set runs with nullFlag=true (the canonical default),
    // every JSON null in the input and expected output is encoded as the
    // sentinel string "__NULL__", and the function result is encoded the same
    // way before comparison — preserving null-vs-absent across the round-trip.
    const val NULLMARK = "__NULL__"

    fun fixJSON(v: Any?): Any? {
        if (v == null || v === Struct.UNDEF) return NULLMARK
        return when (v) {
            is Map<*, *> -> v.entries.associateTo(LinkedHashMap<String, Any?>()) { (it.key?.toString() ?: "") to fixJSON(it.value) }
            is List<*> -> v.mapTo(mutableListOf<Any?>()) { fixJSON(it) }
            else -> v
        }
    }

    /** Modify callback: swap NULLMARK back to real null / literal "null" text. */
    @Suppress("UNCHECKED_CAST")
    val NULL_MODIFIER =
        Struct.Modify { value, key, parent, _, _ ->
            if (value !is String) return@Modify
            val repl: Any? =
                when {
                    value == NULLMARK -> null
                    value.contains(NULLMARK) -> value.replace(NULLMARK, "null")
                    else -> return@Modify
                }
            when {
                parent is MutableMap<*, *> && key != null -> (parent as MutableMap<String, Any?>)[key.toString()] = repl
                parent is MutableList<*> && key is Number -> (parent as MutableList<Any?>)[key.toInt()] = repl
            }
        }

    class Result(val name: String) {
        var passed: Int = 0
        var total: Int = 0
        val failures: MutableList<String> = mutableListOf()

        override fun toString(): String = "$name: $passed/$total"
    }

    fun runset(
        fullName: String,
        testspec: Map<String, Any?>,
        subject: Subject,
    ): Result = runsetflags(fullName, testspec, true, subject)

    @Suppress("UNCHECKED_CAST")
    fun runsetflags(
        fullName: String,
        testspec: Map<String, Any?>,
        nullFlag: Boolean,
        subject: Subject,
    ): Result {
        val res = Result(fullName)
        val set = testspec["set"] as? List<Any?> ?: return res
        for ((i, eo) in set.withIndex()) {
            if (eo !is Map<*, *>) continue
            val entry = eo as Map<String, Any?>
            var input = if (entry.containsKey("in")) Struct.clone(entry["in"]) else Struct.UNDEF
            var expected: Any? =
                if (entry.containsKey("out")) {
                    entry["out"]
                } else if (nullFlag) {
                    null
                } else {
                    Struct.UNDEF
                }
            // NULLMARK round-trip: encode JSON nulls in input and expected when
            // nullFlag is set, matching the canonical runner (flags.null). A
            // genuinely-absent "in" stays UNDEF (the canonical subject receives
            // `undefined`, not the "__NULL__" sentinel) so walk/inject of a
            // missing value behave like the reference runner.
            if (nullFlag) {
                if (entry.containsKey("in")) input = fixJSON(input)
                expected = fixJSON(expected)
            }
            res.total++
            try {
                var got = subject.apply(input)
                if (nullFlag) got = fixJSON(got)
                if (entry.containsKey("err")) {
                    res.failures.add("[$i] expected err='${brief(entry["err"])}' but call returned ${brief(got)}")
                    continue
                }
                if (deepEqual(got, expected)) {
                    res.passed++
                } else {
                    res.failures.add("[$i] in=${brief(entry["in"])} expected=${brief(expected)} got=${brief(got)}")
                }
            } catch (ex: Exception) {
                if (entry.containsKey("err")) {
                    val expErr = entry["err"]
                    val msg = ex.message ?: ""
                    val ok =
                        expErr == true ||
                            (expErr is String && (expErr.isEmpty() || msg.contains(expErr) || msg.lowercase().contains(expErr.lowercase())))
                    if (ok) {
                        res.passed++
                    } else {
                        res.failures.add("[$i] err mismatch: expected '${brief(expErr)}' got '$msg'")
                    }
                } else {
                    res.failures.add("[$i] in=${brief(entry["in"])} threw=${ex.message}")
                }
            }
        }
        return res
    }

    fun deepEqual(
        a: Any?,
        b: Any?,
    ): Boolean = normalize(a) == normalize(b)

    fun normalize(v: Any?): Any? {
        if (v === Struct.UNDEF || v == null) return null
        return when (v) {
            is Number -> {
                val d = v.toDouble()
                if (d.isFinite() && Math.floor(d) == d) d.toLong() else d
            }
            is Boolean, is String -> v
            is Map<*, *> -> {
                val out = TreeMap<String, Any?>()
                for ((k, vv) in v) out[k?.toString() ?: ""] = normalize(vv)
                out
            }
            is List<*> -> v.map { normalize(it) }
            else -> v.toString()
        }
    }

    private fun brief(v: Any?): String {
        if (v === Struct.UNDEF) return "__UNDEF__"
        return try {
            val s = GSON.toJson(v)
            if (s.length > 200) s.substring(0, 197) + "..." else s
        } catch (_: Exception) {
            v.toString()
        }
    }
}
