package voxgig.struct

import voxgig.omni.Flags
import voxgig.omni.Json
import voxgig.omni.Provider
import voxgig.omni.RunPack
import voxgig.omni.Subject
import voxgig.omni.makeRunner

/**
 * The bridge to voxgig/omni, the shared test runner.
 *
 * The corpus runner is not in this repository. omni is consumed as a local
 * checkout, resolved by build.gradle.kts ($OMNI_HOME first, then sibling
 * paths, taking the first directory that carries spec/fib.json) and joined to
 * the TEST source set. Only the tests use it: nothing published from
 * src/main/kotlin can reach it (register 4.13).
 *
 * This is the Kotlin counterpart of java/src/test/Omni.java,
 * csharp/tests/Omni.cs, cpp/tests/omni_bridge.hpp, c/tests/omni_bridge.h,
 * rust/corpus/tests/omni.rs and perl/t/OmniBridge.pm.
 *
 * ## Two value models
 *
 * omni has a sealed `Json`; this port has plain `Any?` - `Map`, `List`,
 * `String`, `Boolean`, `Double`, `null`, and `Struct.UNDEF` for absent. Both
 * draw the same absent/null/value distinction, so nothing is guessed. Numbers
 * cross as `Double`, which is what Gson hands this port and what `typify`
 * already reads integer-ness out of (`floor(d) == d`).
 *
 * ## Mutated arguments
 *
 * `tostruct` builds new containers, so an in-place rewrite by the subject is
 * invisible to the runner - and `match.args` asserts exactly that: eight of
 * `minor/setpath`'s nine entries, and all six of `merge/integrity`.
 *
 * omni's `Subject` takes an immutable `List<Json>`, but the ELEMENTS are not
 * immutable: `Json.JMap` holds a `LinkedHashMap` and `Json.JList` a
 * `MutableList`. So `writeback` refills omni's own container in place after
 * the call, which `checkresult` then matches against. cpp and rust needed a
 * new runner entry point for this; here the container is already mutable.
 *
 * It is safe because `resolveargs` clones `entry.in` before handing it over.
 */
object Omni {
    /** Value is JSON null. */
    const val NULLMARK = "__NULL__"

    /** Value is not present. */
    const val UNDEFMARK = "__UNDEF__"

    /** Value exists. */
    const val EXISTSMARK = "__EXISTS__"

    /** The shared corpus, relative to the port directory as the tests run. */
    const val CORPUSPATH = "../build/test/test.json"

    /** omni's model -> this port's. */
    fun tostruct(value: Json): Any? =
        when (value) {
            is Json.Absent -> Struct.UNDEF
            is Json.Null -> null
            is Json.Bool -> value.value
            is Json.Num -> value.value
            is Json.Str -> value.value
            is Json.JList -> value.value.mapTo(mutableListOf()) { tostruct(it) }
            is Json.JMap ->
                LinkedHashMap<String, Any?>().also { out ->
                    value.value.forEach { (key, entry) -> out[key] = tostruct(entry) }
                }
        }

    /**
     * This port's model -> omni's. A function or a sentinel has no JSON form
     * and omni only ever stringifies one, so it becomes its own rendering
     * rather than silently collapsing to null.
     */
    @Suppress("UNCHECKED_CAST")
    fun toomni(value: Any?): Json =
        when {
            value === Struct.UNDEF -> Json.Absent
            null == value -> Json.Null
            value is Boolean -> Json.Bool(value)
            value is Number -> Json.Num(value.toDouble())
            value is String -> Json.Str(value)
            value is List<*> -> Json.JList(value.mapTo(mutableListOf()) { toomni(it) })
            value is Map<*, *> ->
                Json.JMap(
                    LinkedHashMap<String, Json>().also { out ->
                        value.forEach { (key, entry) -> out["$key"] = toomni(entry) }
                    },
                )
            else -> Json.Str(Struct.stringify(value))
        }

    /** Refill omni's own container from the (possibly rewritten) argument. */
    private fun writeback(
        target: Json,
        source: Any?,
    ) {
        if (target is Json.JMap && source is Map<*, *>) {
            target.value.clear()
            source.forEach { (key, entry) -> target.value["$key"] = toomni(entry) }
        } else if (target is Json.JList && source is List<*>) {
            target.value.clear()
            source.forEach { entry -> target.value.add(toomni(entry)) }
        }
    }

    /** A subject in this port's shape: one argument in, one value out. */
    fun interface StructSubject {
        fun apply(input: Any?): Any?
    }

    /** What the runner returns for one named spec section. */
    class Run(private val pack: RunPack) {
        /** The resolved spec section. */
        val spec: Json get() = pack.spec

        /** A group of the resolved spec, by path. */
        fun group(vararg path: String): Json = path.fold(pack.spec) { node, key -> node.get(key) }

        /** Run one group with omni's default flags. */
        fun runset(
            testspec: Json,
            subject: StructSubject,
        ) = runsetflags(testspec, Flags(), subject)

        /** Run one group with an explicit `null` flag. */
        fun runsetnull(
            testspec: Json,
            donull: Boolean,
            subject: StructSubject,
        ) = runsetflags(testspec, Flags(nulls = donull), subject)

        /** Run one group with explicit flags. */
        fun runsetflags(
            testspec: Json,
            flags: Flags,
            subject: StructSubject,
        ) {
            val wrapped: Subject = { args ->
                val raw = if (args.isEmpty()) Json.Absent else args[0]
                val input = tostruct(raw)
                val got = subject.apply(input)
                writeback(raw, input)
                toomni(got)
            }
            pack.runsetflags(testspec, flags, wrapped)
        }

        /** Run one group against the subject the spec itself names - the client path. */
        fun runsetnamed(
            testspec: Json,
            flags: Flags = Flags(),
        ) = pack.runsetflags(testspec, flags, null)

        companion object {
            /** A runner over one section of the shared corpus. */
            fun of(
                name: String,
                provider: Provider = Provider(),
            ): Run = Run(makeRunner(CORPUSPATH, provider).runner(name))
        }
    }
}
