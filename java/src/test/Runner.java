package voxgig.struct;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.reflect.TypeToken;

import java.io.IOException;
import java.lang.reflect.Type;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.TreeMap;

/**
 * Java port of {@code js/test/runner.js}: drives the shared JSON test corpus
 * at {@code build/test/test.json} against a {@link Subject} that maps a test
 * entry's {@code in} to a function call result.
 *
 * <p>Each {@code testspec.set[]} entry provides:
 * <ul>
 *   <li>{@code in}: the input (cloned before each call); absent means {@link Struct#UNDEF}.</li>
 *   <li>{@code out}: the expected output; absent means {@code null} when {@code nullFlag} is true,
 *       or {@link Struct#UNDEF} when false.</li>
 *   <li>{@code err}: when present, the call is expected to throw.</li>
 * </ul>
 *
 * <p>Comparison is via {@link #normalize(Object)}: numbers collapse to {@code Long}/{@code Double},
 * maps to a {@link TreeMap} for stable key order, lists recurse, {@link Struct#UNDEF} treated as
 * {@code null}.
 */
@SuppressWarnings({"unchecked", "rawtypes"})
public class Runner {
  public static final String NULLMARK = "__NULL__";
  public static final String UNDEFMARK = "__UNDEF__";
  public static final String EXISTSMARK = "__EXISTS__";

  private static final Gson GSON = new GsonBuilder().serializeNulls().create();
  private static volatile Map<String, Object> CORPUS;

  private Runner() {}

  public static synchronized Map<String, Object> loadCorpus() throws IOException {
    if (CORPUS == null) {
      Path p = Path.of("..", "build", "test", "test.json");
      String json = Files.readString(p);
      Type t = new TypeToken<Map<String, Object>>() {}.getType();
      CORPUS = GSON.fromJson(json, t);
    }
    return CORPUS;
  }

  public static Map<String, Object> getSpec(String category, String name) throws IOException {
    Map<String, Object> all = loadCorpus();
    Map<String, Object> struct = (Map<String, Object>) all.get("struct");
    Map<String, Object> cat = (Map<String, Object>) struct.get(category);
    if (cat == null) {
      throw new IllegalArgumentException("Unknown category: " + category);
    }
    Map<String, Object> spec = (Map<String, Object>) cat.get(name);
    if (spec == null) {
      throw new IllegalArgumentException("Unknown spec: " + category + "." + name);
    }
    return spec;
  }

  /** Drives a {@code subject} against a test set; collects per-entry pass/fail. */
  @FunctionalInterface
  public interface Subject {
    Object apply(Object in) throws Exception;
  }

  public static class Result {
    public final String name;
    public int passed;
    public int total;
    public final List<String> failures = new ArrayList<>();

    public Result(String name) {
      this.name = name;
    }

    @Override
    public String toString() {
      return name + ": " + passed + "/" + total;
    }
  }

  public static Result runset(String fullName, Map<String, Object> testspec, Subject subject) {
    return runsetflags(fullName, testspec, true, subject);
  }

  public static Result runsetflags(
      String fullName, Map<String, Object> testspec, boolean nullFlag, Subject subject) {
    Result res = new Result(fullName);
    Object setObj = testspec.get("set");
    if (!(setObj instanceof List<?> set)) {
      return res;
    }

    for (int i = 0; i < set.size(); i++) {
      Object eo = set.get(i);
      if (!(eo instanceof Map<?, ?> em)) {
        continue;
      }
      Map<String, Object> entry = (Map<String, Object>) em;

      Object in =
          entry.containsKey("in")
              ? Struct.clone(entry.get("in"))
              : Struct.UNDEF;
      Object expected =
          entry.containsKey("out")
              ? entry.get("out")
              : (nullFlag ? null : Struct.UNDEF);

      res.total++;
      try {
        Object got = subject.apply(in);

        if (entry.containsKey("err")) {
          res.failures.add(
              String.format(
                  "[%d] expected err='%s' but call returned %s",
                  i, brief(entry.get("err")), brief(got)));
          continue;
        }

        if (deepEqual(got, expected)) {
          res.passed++;
        } else {
          res.failures.add(
              String.format(
                  "[%d] in=%s expected=%s got=%s",
                  i, brief(entry.get("in")), brief(expected), brief(got)));
        }
      } catch (Exception ex) {
        if (entry.containsKey("err")) {
          // Accept any thrown error when err is true, or substring match otherwise.
          Object expErr = entry.get("err");
          String msg = ex.getMessage() == null ? "" : ex.getMessage();
          if (Boolean.TRUE.equals(expErr)
              || (expErr instanceof String es
                  && (es.isEmpty() || msg.contains(es) || msg.toLowerCase().contains(es.toLowerCase())))) {
            res.passed++;
          } else {
            res.failures.add(
                String.format(
                    "[%d] err mismatch: expected '%s' got '%s'", i, brief(expErr), msg));
          }
        } else {
          res.failures.add(
              String.format(
                  "[%d] in=%s threw=%s", i, brief(entry.get("in")), ex.getMessage()));
        }
      }
    }
    return res;
  }

  /** Normalize then deep-equal. Treats {@link Struct#UNDEF} as {@code null}. */
  public static boolean deepEqual(Object a, Object b) {
    return Objects.equals(normalize(a), normalize(b));
  }

  /**
   * Canonicalize a value for comparison:
   * <ul>
   *   <li>{@link Struct#UNDEF} → {@code null} (test corpus uses {@code null} interchangeably).</li>
   *   <li>{@link Number} → {@code Long} if integer-valued, else {@code Double}.</li>
   *   <li>{@link Map} → {@link TreeMap} (sorted keys).</li>
   *   <li>{@link List} → recursively normalized {@link ArrayList}.</li>
   * </ul>
   */
  public static Object normalize(Object v) {
    if (v == Struct.UNDEF || v == null) {
      return null;
    }
    if (v instanceof Number n) {
      double d = n.doubleValue();
      if (Double.isFinite(d) && Math.floor(d) == d) {
        return (long) d;
      }
      return d;
    }
    if (v instanceof Boolean || v instanceof String) {
      return v;
    }
    if (v instanceof Map<?, ?> m) {
      Map<String, Object> out = new TreeMap<>();
      for (Map.Entry<?, ?> e : m.entrySet()) {
        out.put(Objects.toString(e.getKey(), ""), normalize(e.getValue()));
      }
      return out;
    }
    if (v instanceof List<?> l) {
      List<Object> out = new ArrayList<>(l.size());
      for (Object x : l) {
        out.add(normalize(x));
      }
      return out;
    }
    return v.toString();
  }

  private static String brief(Object v) {
    if (v == Struct.UNDEF) {
      return UNDEFMARK;
    }
    try {
      String s = GSON.toJson(v);
      return s.length() > 200 ? s.substring(0, 197) + "..." : s;
    } catch (Exception e) {
      return Objects.toString(v);
    }
  }

  /** Helper: walks nested map by dotted key path. */
  public static Object getNested(Object node, String dottedPath) {
    Object cur = node;
    for (String part : dottedPath.split("\\.")) {
      if (cur instanceof Map<?, ?> m) {
        cur = m.get(part);
      } else if (cur instanceof List<?> l) {
        try {
          cur = l.get(Integer.parseInt(part));
        } catch (Exception e) {
          return null;
        }
      } else {
        return null;
      }
    }
    return cur;
  }
}
