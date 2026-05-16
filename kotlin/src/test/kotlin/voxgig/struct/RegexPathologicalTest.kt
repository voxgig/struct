// Discovery test: pathological regex inputs run against the port's re* API.
// Goal is to surface failures across ports, not to assert behaviour.
// Panel is the same in every port (see REGEX.md).

package voxgig.struct

import com.google.gson.Gson
import kotlin.test.Test

class RegexPathologicalTest {
    private val gson = Gson()

    private fun record(
        label: String,
        fn: () -> Any?,
    ) {
        val t0 = System.nanoTime()
        val outcome: String =
            try {
                val r = fn()
                "OK | " + gson.toJson(r)
            } catch (e: Throwable) {
                "ERR | ${e::class.simpleName}: ${e.message}"
            }
        val ms = (System.nanoTime() - t0) / 1e6
        println("[regex-discovery] %s | %.2fms | %s".format(label, ms, outcome))
    }

    @Test
    fun panel() {
        val a22 = "a".repeat(22)
        val nest40 = "(".repeat(40) + "a" + ")".repeat(40)

        record("P1_redos_nested_plus") { Struct.reTest("^(a+)+\$", a22 + "!") }
        record("P2_redos_alt_overlap") { Struct.reTest("^(a|aa)+\$", a22 + "!") }
        record("P3_empty_repeat_replace") { Struct.reReplace("a*", "abc", "X") }
        record("P4_unicode_replace_dot") { Struct.reReplace("\\.", "café.au.lait", "/") }
        record("P5_unicode_find_codepoint") { Struct.reFind("é", "café au lait") }
        record("P6_deep_nesting_compile") { Struct.reTest(nest40, "a") }
        record("P7_big_bounded_quantifier") { Struct.reTest("^a{0,10000}b\$", "a".repeat(10) + "b") }
        record("P8_invalid_pattern") { Struct.reCompile("[abc") }
        record("P9_backref_re2_forbidden") { Struct.reTest("^(a+)\\1\$", "aaaa") }
        record("P10_find_all_zero_width") { Struct.reFindAll("a*", "bbb") }
    }
}
