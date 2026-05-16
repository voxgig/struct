// RUN: mvn -Dtest=RegexPathologicalTest test
//
// Discovery test: pathological regex inputs run against the port's re* API.
// Goal is to surface failures across ports, not to assert behaviour.
// Panel is the same in every port (see REGEX.md).

package voxgig.struct;

import com.google.gson.Gson;
import org.junit.jupiter.api.Test;

import java.util.function.Supplier;

class RegexPathologicalTest {
  private static final Gson GSON = new Gson();

  private static void record(String label, Supplier<Object> fn) {
    long t0 = System.nanoTime();
    String outcome;
    try {
      Object r = fn.get();
      outcome = "OK | " + GSON.toJson(r);
    } catch (Throwable e) {
      outcome = "ERR | " + e.getClass().getSimpleName() + ": " + e.getMessage();
    }
    double ms = (System.nanoTime() - t0) / 1e6;
    System.out.printf("[regex-discovery] %s | %.2fms | %s%n", label, ms, outcome);
  }

  @Test
  void panel() {
    String a22 = "a".repeat(22);
    String nest40 = "(".repeat(40) + "a" + ")".repeat(40);

    record("P1_redos_nested_plus",      () -> Struct.reTest("^(a+)+$", a22 + "!"));
    record("P2_redos_alt_overlap",      () -> Struct.reTest("^(a|aa)+$", a22 + "!"));
    record("P3_empty_repeat_replace",   () -> Struct.reReplace("a*", "abc", "X"));
    record("P4_unicode_replace_dot",    () -> Struct.reReplace("\\.", "café.au.lait", "/"));
    record("P5_unicode_find_codepoint", () -> Struct.reFind("é", "café au lait"));
    record("P6_deep_nesting_compile",   () -> Struct.reTest(nest40, "a"));
    record("P7_big_bounded_quantifier", () -> Struct.reTest("^a{0,10000}b$", "a".repeat(10) + "b"));
    record("P8_invalid_pattern",        () -> Struct.reCompile("[abc"));
    record("P9_backref_re2_forbidden",  () -> Struct.reTest("^(a+)\\1$", "aaaa"));
    record("P10_find_all_zero_width",   () -> Struct.reFindAll("a*", "bbb"));
  }
}
