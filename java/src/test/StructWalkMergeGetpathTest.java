package voxgig.struct;

import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.lang.reflect.Type;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.function.Supplier;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SuppressWarnings({"unchecked", "rawtypes"})
class StructWalkMergeGetpathTest {
  private static final Gson GSON = new Gson();
  private static final Pattern CMD_REF = Pattern.compile("`(\\$[A-Z]+[0-9]*)`");
  private static Map<String, Object> walkSpec;
  private static Map<String, Object> mergeSpec;
  private static Map<String, Object> getpathSpec;
  private static Map<String, Object> injectSpec;
  private static Map<String, Object> transformSpec;
  private static Map<String, Object> eachSpec;
  private static Map<String, Object> packSpec;
  private static Map<String, Object> formatSpec;
  private static Map<String, Object> refSpec;
  private static Map<String, Object> validateSpec;
  private static Map<String, Object> validateOneSpec;
  private static Map<String, Object> validateExactSpec;
  private static Map<String, Object> validateInvalidSpec;
  private static Map<String, Object> validateSpecialSpec;
  private static Map<String, Object> selectSpec;

  @BeforeAll
  static void init() throws IOException {
    Path p = Path.of("..", "build", "test", "test.json");
    String json = Files.readString(p);
    Type t = new TypeToken<Map<String, Object>>() {}.getType();
    Map<String, Object> all = GSON.fromJson(json, t);
    Map<String, Object> struct = (Map<String, Object>) all.get("struct");
    walkSpec = (Map<String, Object>) struct.get("walk");
    mergeSpec = (Map<String, Object>) struct.get("merge");
    getpathSpec = (Map<String, Object>) struct.get("getpath");
    injectSpec = (Map<String, Object>) struct.get("inject");
    transformSpec = (Map<String, Object>) struct.get("transform");
    eachSpec = (Map<String, Object>) transformSpec.get("each");
    packSpec = (Map<String, Object>) transformSpec.get("pack");
    formatSpec = (Map<String, Object>) transformSpec.get("format");
    refSpec = (Map<String, Object>) transformSpec.get("ref");
    validateSpec = (Map<String, Object>) struct.get("validate");
    validateOneSpec = (Map<String, Object>) validateSpec.get("one");
    validateExactSpec = (Map<String, Object>) validateSpec.get("exact");
    validateInvalidSpec = (Map<String, Object>) validateSpec.get("invalid");
    validateSpecialSpec = (Map<String, Object>) validateSpec.get("special");
    selectSpec = (Map<String, Object>) struct.get("select");
  }

  private static String slog(Object v) {
    if (v == null) {
      return "";
    }
    return Struct.stringify(v);
  }

  private static Object normalize(Object v) {
    if (v == Struct.UNDEF) {
      return "__UNDEF__";
    }
    if (v instanceof Number n) {
      double d = n.doubleValue();
      if (Math.floor(d) == d) {
        return (long) d;
      }
      return d;
    }
    if (v instanceof List<?> l) {
      List<Object> out = new ArrayList<>();
      for (Object n : l) {
        out.add(normalize(n));
      }
      return out;
    }
    if (v instanceof Map<?, ?> m) {
      Map<String, Object> out = new LinkedHashMap<>();
      for (Map.Entry<?, ?> e : m.entrySet()) {
        out.put(Objects.toString(e.getKey()), normalize(e.getValue()));
      }
      return out;
    }
    return v;
  }

  private static boolean equalNorm(Object a, Object b) {
    return Objects.equals(normalize(a), normalize(b));
  }

  private static String json(Object v) {
    try {
      return GSON.toJson(v == Struct.UNDEF ? "__UNDEF__" : v);
    } catch (Exception e) {
      return Objects.toString(v);
    }
  }

  private static void runSet(Map<String, Object> testspec, RunnerFn fn) {
    runSet(testspec, fn, null);
  }

  private static void runSet(Map<String, Object> testspec, RunnerFn fn, EntryFilter filter) {
    Map<String, Object> testspecMap = testspec;
    List<Object> set = (List<Object>) testspecMap.get("set");
    for (Object eo : set) {
      if (!(eo instanceof Map)) {
        continue;
      }
      Map<String, Object> entry = (Map<String, Object>) eo;
      if (filter != null && !filter.allow(entry)) {
        continue;
      }
      if (!entry.containsKey("in") || !entry.containsKey("out")) {
        continue;
      }
      Object in = entry.containsKey("in") ? Struct.clone(entry.get("in")) : Struct.UNDEF;
      Object out = entry.get("out");
      Object got = fn.apply(in);
      assertTrue(
          equalNorm(out, got),
          () -> "Mismatch in=" + json(in) + " expected=" + json(out) + " got=" + json(got));
    }
  }

  private interface RunnerFn {
    Object apply(Object in);
  }

  private interface EntryFilter {
    boolean allow(Map<String, Object> entry);
  }

  private static void runValidateSet(Map<String, Object> testspec, boolean useInj) {
    List<Object> set = (List<Object>) testspec.get("set");
    for (Object eo : set) {
      if (!(eo instanceof Map<?, ?> em)) {
        continue;
      }
      Map<String, Object> entry = toStringObjectMap(em);
      Object inObj = entry.get("in");
      if (!(inObj instanceof Map<?, ?> im)) {
        continue;
      }
      Map<String, Object> in = toStringObjectMap(im);
      Object data = in.get("data");
      Object spec = in.get("spec");
      Map<String, Object> inj = useInj && in.get("inj") instanceof Map<?, ?> injm ? toStringObjectMap(injm) : null;

      if (entry.containsKey("err")) {
        String expectedErr = Objects.toString(entry.get("err"), "");
        String gotErr = "";
        try {
          Struct.validate(data, spec, inj);
        } catch (Exception ex) {
          gotErr = ex.getMessage();
        }
        assertEquals(
            canonicalErr(expectedErr),
            canonicalErr(gotErr),
            "Expected err=" + expectedErr + " got err=" + gotErr);
      } else {
        Object got = Struct.validate(data, spec, inj);
        assertTrue(
            equalNorm(entry.get("out"), got),
            () -> "Mismatch in=" + json(in) + " expected=" + json(entry.get("out")) + " got=" + json(got));
      }
    }
  }

  private static Map<String, Object> toStringObjectMap(Map<?, ?> in) {
    Map<String, Object> out = new LinkedHashMap<>();
    for (Map.Entry<?, ?> e : in.entrySet()) {
      out.put(Objects.toString(e.getKey(), ""), e.getValue());
    }
    return out;
  }

  private static String canonicalErr(String err) {
    if (err == null) {
      return "";
    }
    String out = err;
    out = out.replaceAll("\\.$", "");
    out = out.replaceAll("\\. \\|", " |");
    return out.trim();
  }

  private static void collectCommands(Object node, Set<String> out) {
    if (node instanceof String s) {
      Matcher m = CMD_REF.matcher(s);
      while (m.find()) {
        out.add(m.group(1));
      }
      return;
    }
    if (node instanceof Map<?, ?> map) {
      for (Map.Entry<?, ?> e : map.entrySet()) {
        collectCommands(Objects.toString(e.getKey(), ""), out);
        collectCommands(e.getValue(), out);
      }
      return;
    }
    if (node instanceof List<?> list) {
      for (Object child : list) {
        collectCommands(child, out);
      }
    }
  }

  private static boolean isCopyEscapeOnlyCmdCase(Map<String, Object> entry) {
    Object inObj = entry.get("in");
    if (!(inObj instanceof Map<?, ?> inMap)) {
      return false;
    }
    Set<String> cmds = new LinkedHashSet<>();
    collectCommands(inMap.get("spec"), cmds);
    if (cmds.isEmpty()) {
      return false;
    }
    for (String c : cmds) {
      if (!"$BT".equals(c) && !"$DS".equals(c) && !"$COPY".equals(c) && !"$DELETE".equals(c)) {
        if (!c.startsWith("$MERGE")) {
          return false;
        }
      }
    }
    return true;
  }

  private static boolean isEachCopyKeyOnlyCase(Map<String, Object> entry) {
    Object inObj = entry.get("in");
    if (!(inObj instanceof Map<?, ?> inMap)) {
      return false;
    }
    Set<String> cmds = new LinkedHashSet<>();
    collectCommands(inMap.get("spec"), cmds);
    if (cmds.isEmpty()) {
      return false;
    }
    for (String c : cmds) {
      if (!"$COPY".equals(c) && !"$KEY".equals(c)) {
        return false;
      }
    }
    return true;
  }

  private static boolean isEachCommandBasicCase(Map<String, Object> entry) {
    Object inObj = entry.get("in");
    if (!(inObj instanceof Map<?, ?> inMap)) {
      return false;
    }
    Object spec = inMap.get("spec");
    if (containsDotAscend(spec)) {
      return false;
    }
    Set<String> cmds = new LinkedHashSet<>();
    collectCommands(spec, cmds);
    if (!cmds.contains("$EACH")) {
      return false;
    }
    for (String c : cmds) {
      if (!"$EACH".equals(c) && !"$COPY".equals(c) && !"$KEY".equals(c)) {
        return false;
      }
    }
    return true;
  }

  private static boolean isPackBasicCase(Map<String, Object> entry) {
    Object inObj = entry.get("in");
    if (!(inObj instanceof Map<?, ?> inMap)) {
      return false;
    }
    Set<String> cmds = new LinkedHashSet<>();
    collectCommands(inMap.get("spec"), cmds);
    if (!cmds.contains("$PACK")) {
      return false;
    }
    for (String c : cmds) {
      if (!"$PACK".equals(c) && !"$COPY".equals(c) && !"$KEY".equals(c) && !"$VAL".equals(c) && !"$FORMAT".equals(c)) {
        return false;
      }
    }
    return true;
  }

  private static boolean containsDotAscend(Object node) {
    if (node instanceof String s) {
      return false;
    }
    if (node instanceof Map<?, ?> map) {
      for (Map.Entry<?, ?> e : map.entrySet()) {
        if (containsDotAscend(Objects.toString(e.getKey(), "")) || containsDotAscend(e.getValue())) {
          return true;
        }
      }
      return false;
    }
    if (node instanceof List<?> list) {
      for (Object item : list) {
        if (containsDotAscend(item)) {
          return true;
        }
      }
    }
    return false;
  }

  private static int intish(Object o) {
    if (o instanceof Number n) {
      return n.intValue();
    }
    throw new IllegalArgumentException("expected number, got " + o);
  }

  @Test
  void walkExists() {
    assertTrue(Struct.walk(Map.of(), (k, v, p, t) -> v) instanceof Map);
  }

  @Test
  void walkLog() {
    Map<String, Object> test = (Map<String, Object>) Struct.clone(walkSpec.get("log"));
    Map<String, Object> outMap = (Map<String, Object>) test.get("out");

    List<Object> logAfter = new ArrayList<>();
    Struct.WalkApply walklogAfter =
        (key, val, parent, path) -> {
          String ks = key == null ? "" : key;
          String entry =
              "k="
                  + Struct.stringify(ks)
                  + ", v="
                  + Struct.stringify(val)
                  + ", p="
                  + slog(parent)
                  + ", t="
                  + Struct.pathify(path);
          logAfter.add(entry);
          return val;
        };
    Struct.walk(test.get("in"), null, walklogAfter);
    assertEquals(outMap.get("after"), logAfter);

    List<Object> logBefore = new ArrayList<>();
    Struct.WalkApply walklogBefore =
        (key, val, parent, path) -> {
          String ks = key == null ? "" : key;
          String entry =
              "k="
                  + Struct.stringify(ks)
                  + ", v="
                  + Struct.stringify(val)
                  + ", p="
                  + slog(parent)
                  + ", t="
                  + Struct.pathify(path);
          logBefore.add(entry);
          return val;
        };
    Struct.walk(test.get("in"), walklogBefore);
    assertEquals(outMap.get("before"), logBefore);

    List<Object> logBoth = new ArrayList<>();
    Struct.WalkApply walklogBoth =
        (key, val, parent, path) -> {
          String ks = key == null ? "" : key;
          String entry =
              "k="
                  + Struct.stringify(ks)
                  + ", v="
                  + Struct.stringify(val)
                  + ", p="
                  + slog(parent)
                  + ", t="
                  + Struct.pathify(path);
          logBoth.add(entry);
          return val;
        };
    Struct.walk(test.get("in"), walklogBoth, walklogBoth);
    assertEquals(outMap.get("both"), logBoth);
  }

  @Test
  void walkBasic() {
    Struct.WalkApply walkpath =
        (key, val, parent, path) -> {
          if (val instanceof String s) {
            return s + "~" + String.join(".", path);
          }
          return val;
        };
    runSet((Map<String, Object>) walkSpec.get("basic"), in -> Struct.walk(in, walkpath));
  }

  @Test
  void walkDepth() {
    runSet(
        (Map<String, Object>) walkSpec.get("depth"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          Object src = m.get("src");
          Object maxdepth = m.get("maxdepth");
          Object[] top = new Object[1];
          Object[] cur = new Object[1];
          Struct.WalkApply copy =
              (key, val, parent, path) -> {
                if (Struct.isnode(val)) {
                  Object child;
                  if (Struct.islist(val)) {
                    child = new ArrayList<Object>();
                  } else {
                    child = new LinkedHashMap<String, Object>();
                  }
                  if (key == null) {
                    top[0] = child;
                    cur[0] = child;
                  } else {
                    cur[0] = Struct.setprop(cur[0], key, child);
                    cur[0] = child;
                  }
                } else if (key != null) {
                  cur[0] = Struct.setprop(cur[0], key, val);
                }
                return val;
              };
          if (maxdepth == null) {
            Struct.walk(src, copy);
          } else {
            Struct.walk(src, copy, null, intish(maxdepth));
          }
          return top[0];
        });
  }

  @Test
  void walkCopy() {
    runSet(
        (Map<String, Object>) walkSpec.get("copy"),
        v -> {
          Object[] cur = new Object[33];
          String[] keys = new String[33];
          Struct.WalkApply walkcopy =
              (key, val, parent, path) -> {
                if (key == null) {
                  Arrays.fill(cur, null);
                  Arrays.fill(keys, null);
                  if (Struct.ismap(val)) {
                    cur[0] = new LinkedHashMap<String, Object>();
                  } else if (Struct.islist(val)) {
                    cur[0] = new ArrayList<Object>();
                  } else {
                    cur[0] = val;
                  }
                  return val;
                }
                Object node = val;
                int i = path.size();
                keys[i] = key;
                if (Struct.isnode(node)) {
                  if (Struct.ismap(node)) {
                    cur[i] = new LinkedHashMap<String, Object>();
                  } else {
                    cur[i] = new ArrayList<Object>();
                  }
                  node = cur[i];
                }
                cur[i - 1] = Struct.setprop(cur[i - 1], key, node);
                for (int j = i - 1; j > 0; j--) {
                  cur[j - 1] = Struct.setprop(cur[j - 1], keys[j], cur[j]);
                }
                return val;
              };
          Struct.walk(v, walkcopy);
          return cur[0];
        });
  }

  @Test
  void mergeExists() {
    assertTrue(Struct.merge(List.of()) == null);
  }

  @Test
  void mergeBasic() {
    Map<String, Object> test = (Map<String, Object>) mergeSpec.get("basic");
    Object got = Struct.merge(test.get("in"));
    assertEquals(normalize(test.get("out")), normalize(got));
  }

  @Test
  void mergeCases() {
    runSet((Map<String, Object>) mergeSpec.get("cases"), Struct::merge);
  }

  @Test
  void mergeArray() {
    runSet((Map<String, Object>) mergeSpec.get("array"), Struct::merge);
  }

  @Test
  void mergeIntegrity() {
    runSet((Map<String, Object>) mergeSpec.get("integrity"), Struct::merge);
  }

  @Test
  void mergeDepth() {
    runSet(
        (Map<String, Object>) mergeSpec.get("depth"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          Object val = m.get("val");
          Object depth = m.get("depth");
          if (depth == null) {
            return Struct.merge(val);
          }
          return Struct.merge(val, intish(depth));
        });
  }

  @Test
  void mergeSpecial() {
    Supplier<Integer> f0 = () -> 11;
    Object result0 = Struct.merge(List.of(f0));
    assertEquals(11, ((Supplier<Integer>) result0).get());

    List<Object> withNull = new ArrayList<>();
    withNull.add(null);
    withNull.add(f0);
    Object result1 = Struct.merge(withNull);
    assertEquals(11, ((Supplier<Integer>) result1).get());

    Map<String, Object> m2 = new LinkedHashMap<>();
    m2.put("a", f0);
    Map<String, Object> result2 = (Map<String, Object>) Struct.merge(List.of(m2));
    assertEquals(11, ((Supplier<Integer>) result2.get("a")).get());

    List<Object> result3 = (List<Object>) Struct.merge(List.of(List.of(f0)));
    assertEquals(11, ((Supplier<Integer>) result3.get(0)).get());

    Map<String, Object> inner = new LinkedHashMap<>();
    inner.put("b", f0);
    Map<String, Object> outer = new LinkedHashMap<>();
    outer.put("a", inner);
    Map<String, Object> result4 = (Map<String, Object>) Struct.merge(List.of(outer));
    assertEquals(11, ((Supplier<Integer>) ((Map<?, ?>) result4.get("a")).get("b")).get());
  }

  @Test
  void getpathExists() {
    assertEquals(1, Struct.getpath(Map.of("a", 1), "a"));
  }

  @Test
  void getpathBasic() {
    runSet(
        (Map<String, Object>) getpathSpec.get("basic"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.getpath(m.get("store"), m.get("path"));
        });
  }

  @Test
  void getpathRelative() {
    runSet(
        (Map<String, Object>) getpathSpec.get("relative"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          Map<String, Object> inj = new LinkedHashMap<>();
          inj.put("dparent", m.get("dparent"));
          Object dpath = m.get("dpath");
          if (dpath instanceof String s && !s.isEmpty()) {
            inj.put("dpath", Arrays.asList(s.split("\\.", -1)));
          }
          return Struct.getpath(m.get("store"), m.get("path"), inj);
        });
  }

  @Test
  void getpathSpecial() {
    runSet(
        (Map<String, Object>) getpathSpec.get("special"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          Object injObj = m.get("inj");
          if (injObj instanceof Map<?, ?> injMap) {
            Map<String, Object> inj = new LinkedHashMap<>();
            for (Map.Entry<?, ?> e : injMap.entrySet()) {
              inj.put(Objects.toString(e.getKey()), e.getValue());
            }
            return Struct.getpath(m.get("store"), m.get("path"), inj);
          }
          return Struct.getpath(m.get("store"), m.get("path"));
        });
  }

  @Test
  void getpathHandler() {
    runSet(
        (Map<String, Object>) getpathSpec.get("handler"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          Map<String, Object> store = new LinkedHashMap<>();
          store.put(Struct.S_DTOP, m.get("store"));
          store.put("$FOO", (Supplier<String>) () -> "foo");
          Map<String, Object> inj = new LinkedHashMap<>();
          inj.put(
              "handler",
              (Struct.PathHandler)
                  (_inj, val, _ref, _store) -> {
                    if (val instanceof Supplier<?> s) {
                      return s.get();
                    }
                    return val;
                  });
          return Struct.getpath(store, m.get("path"), inj);
        });
  }

  @Test
  void injectExists() {
    assertEquals(1L, normalize(Struct.inject("`a`", Map.of("a", 1))));
  }

  @Test
  void injectBasic() {
    Map<String, Object> test = (Map<String, Object>) injectSpec.get("basic");
    Map<String, Object> in = (Map<String, Object>) test.get("in");
    Object got = Struct.inject(in.get("val"), in.get("store"));
    assertTrue(equalNorm(test.get("out"), got));
  }

  @Test
  void injectString() {
    runSet(
        (Map<String, Object>) injectSpec.get("string"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.inject(m.get("val"), m.get("store"));
        });
  }

  @Test
  void injectDeep() {
    runSet(
        (Map<String, Object>) injectSpec.get("deep"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          Object val = m.containsKey("val") ? m.get("val") : null;
          Object store = m.containsKey("store") ? m.get("store") : null;
          return Struct.inject(val, store);
        });
  }

  @Test
  void transformExists() {
    assertEquals("A", Struct.transform(Map.of(), "A"));
  }

  @Test
  void transformBasic() {
    Map<String, Object> test = (Map<String, Object>) transformSpec.get("basic");
    Map<String, Object> in = (Map<String, Object>) test.get("in");
    Object got = Struct.transform(in.get("data"), in.get("spec"));
    assertTrue(equalNorm(test.get("out"), got));
  }

  @Test
  void transformPaths() {
    runSet(
        (Map<String, Object>) transformSpec.get("paths"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          Object data = m.get("data");
          Object spec = m.get("spec");
          return Struct.transform(data, spec);
        });
  }

  @Test
  void transformCmdsCopyEscapes() {
    runSet(
        (Map<String, Object>) transformSpec.get("cmds"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.transform(m.get("data"), m.get("spec"));
        },
        StructWalkMergeGetpathTest::isCopyEscapeOnlyCmdCase);
  }

  @Test
  void transformCmdsAll() {
    runSet(
        (Map<String, Object>) transformSpec.get("cmds"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.transform(m.get("data"), m.get("spec"));
        });
  }

  @Test
  void transformEachCopyKeySubset() {
    runSet(
        eachSpec,
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.transform(m.get("data"), m.get("spec"));
        },
        StructWalkMergeGetpathTest::isEachCopyKeyOnlyCase);
  }

  @Test
  void transformEachCommandBasicSubset() {
    runSet(
        eachSpec,
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.transform(m.get("data"), m.get("spec"));
        },
        StructWalkMergeGetpathTest::isEachCommandBasicCase);
  }

  @Test
  void transformPackBasicSubset() {
    runSet(
        packSpec,
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.transform(m.get("data"), m.get("spec"));
        },
        StructWalkMergeGetpathTest::isPackBasicCase);
  }

  @Test
  void transformEachAll() {
    runSet(
        eachSpec,
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.transform(m.get("data"), m.get("spec"));
        });
  }

  @Test
  void transformPackAll() {
    runSet(
        packSpec,
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.transform(m.get("data"), m.get("spec"));
        });
  }

  @Test
  void transformFormat() {
    runSet(
        formatSpec,
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.transform(m.get("data"), m.get("spec"));
        });
  }

  @Test
  void transformRef() {
    runSet(
        refSpec,
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.transform(m.get("data"), m.get("spec"));
        });
  }

  @Test
  void validateBasic() {
    runSet(
        (Map<String, Object>) validateSpec.get("basic"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          Map<String, Object> opts = new LinkedHashMap<>();
          opts.put("errs", new ArrayList<String>());
          return Struct.validate(m.get("data"), m.get("spec"), opts);
        });
  }

  @Test
  void validateChild() {
    runSet(
        (Map<String, Object>) validateSpec.get("child"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          Map<String, Object> opts = new LinkedHashMap<>();
          opts.put("errs", new ArrayList<String>());
          return Struct.validate(m.get("data"), m.get("spec"), opts);
        });
  }

  @Test
  void validateOne() {
    runSet(
        validateOneSpec,
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          Map<String, Object> opts = new LinkedHashMap<>();
          opts.put("errs", new ArrayList<String>());
          return Struct.validate(m.get("data"), m.get("spec"), opts);
        });
  }

  @Test
  void validateExact() {
    runSet(
        validateExactSpec,
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          Map<String, Object> opts = new LinkedHashMap<>();
          opts.put("errs", new ArrayList<String>());
          return Struct.validate(m.get("data"), m.get("spec"), opts);
        });
  }

  @Test
  void validateInvalid() {
    runValidateSet(validateInvalidSpec, false);
  }

  @Test
  void validateSpecial() {
    runValidateSet(validateSpecialSpec, true);
  }

  @Test
  void validateEdge() {
    List<String> errs = new ArrayList<>();
    Map<String, Object> opts = new LinkedHashMap<>();
    opts.put("errs", errs);

    Struct.validate(Map.of("x", 1), Map.of("x", "`$INSTANCE`"), opts);
    assertEquals("Expected field x to be instance, but found integer: 1.", errs.get(0));

    errs.clear();
    Struct.validate(Map.of("x", Map.of()), Map.of("x", "`$INSTANCE`"), opts);
    assertEquals("Expected field x to be instance, but found map: {}.", errs.get(0));

    errs.clear();
    Struct.validate(Map.of("x", List.of()), Map.of("x", "`$INSTANCE`"), opts);
    assertEquals("Expected field x to be instance, but found list: [].", errs.get(0));

    class C {}
    errs.clear();
    Struct.validate(Map.of("x", new C()), Map.of("x", "`$INSTANCE`"), opts);
    assertEquals(0, errs.size());
  }

  @Test
  void validateCustom() {
    List<String> errs = new ArrayList<>();
    Map<String, Object> extra = new LinkedHashMap<>();
    extra.put(
        "$INTEGER",
        (java.util.function.Function<Object, Object>)
            state -> {
              if (state instanceof Map<?, ?> sm) {
                Object key = sm.get("key");
                Object dparent = sm.get("dparent");
                Object out = Struct.getprop(dparent, key);
                if (!(out instanceof Number n) || Math.floor(n.doubleValue()) != n.doubleValue()) {
                  List<String> path = sm.get("path") instanceof List<?> p ? (List<String>) p : List.of();
                  List<String> localErrs = sm.get("errs") instanceof List<?> le ? (List<String>) le : errs;
                  localErrs.add("Not an integer at " + String.join(".", path) + ": " + out);
                  return null;
                }
                return out;
              }
              return null;
            });

    Map<String, Object> shape = Map.of("a", "`$INTEGER`");
    Map<String, Object> opts = new LinkedHashMap<>();
    opts.put("extra", extra);
    opts.put("errs", errs);

    Object out = Struct.validate(Map.of("a", 1), shape, opts);
    assertTrue(equalNorm(Map.of("a", 1), out));
    assertEquals(0, errs.size());

    errs.clear();
    out = Struct.validate(Map.of("a", "A"), shape, opts);
    assertTrue(equalNorm(Map.of("a", "A"), out));
    assertEquals(List.of("Not an integer at a: A"), errs);
  }

  @Test
  void selectBasic() {
    runSet(
        (Map<String, Object>) selectSpec.get("basic"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.select(m.get("obj"), m.get("query"));
        });
  }

  @Test
  void selectOperators() {
    runSet(
        (Map<String, Object>) selectSpec.get("operators"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.select(m.get("obj"), m.get("query"));
        });
  }

  @Test
  void selectEdge() {
    runSet(
        (Map<String, Object>) selectSpec.get("edge"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.select(m.get("obj"), m.get("query"));
        });
  }

  @Test
  void selectAlts() {
    runSet(
        (Map<String, Object>) selectSpec.get("alts"),
        v -> {
          Map<String, Object> m = (Map<String, Object>) v;
          return Struct.select(m.get("obj"), m.get("query"));
        });
  }

  @Test
  void transformEdgeApply() {
    List<Object> spec = new ArrayList<>();
    spec.add("`$APPLY`");
    spec.add((java.util.function.Function<Object, Object>) v -> 1 + ((Number) v).intValue());
    spec.add(1);
    assertEquals(2L, normalize(Struct.transform(new LinkedHashMap<>(), spec)));
  }

  @Test
  void transformModify() {
    Map<String, Object> data = new LinkedHashMap<>();
    data.put("x", "X");
    Map<String, Object> spec = new LinkedHashMap<>();
    spec.put("z", "`x`");
    Map<String, Object> opts = new LinkedHashMap<>();
    opts.put(
        "modify",
        (Struct.TransformModify)
            (val, key, parent) -> {
              if (key != null && parent instanceof Map<?, ?> p && val instanceof String s) {
                ((Map<String, Object>) p).put(key, "@" + s);
              }
            });
    Object got = Struct.transform(data, spec, opts);
    assertTrue(equalNorm(Map.of("z", "@X"), got));
  }

  @Test
  void transformExtra() {
    Map<String, Object> data = new LinkedHashMap<>();
    data.put("a", 1);
    Map<String, Object> spec = new LinkedHashMap<>();
    spec.put("x", "`a`");
    spec.put("b", "`$COPY`");
    spec.put("c", "`$UPPER`");

    Map<String, Object> extra = new LinkedHashMap<>();
    extra.put("b", 2);
    extra.put(
        "$UPPER",
        (java.util.function.Function<Object, Object>)
            state -> {
              if (state instanceof Map<?, ?> sm && sm.get("path") instanceof List<?> path && !path.isEmpty()) {
                String last = Objects.toString(path.get(path.size() - 1), "");
                return last.toUpperCase();
              }
              return "";
            });
    Map<String, Object> opts = new LinkedHashMap<>();
    opts.put("extra", extra);

    Object got = Struct.transform(data, spec, opts);
    assertTrue(equalNorm(Map.of("x", 1, "b", 2, "c", "C"), got));
  }

  @Test
  void transformFuncval() {
    java.util.function.Supplier<Integer> f0 = () -> 99;
    assertTrue(equalNorm(Map.of("x", 1), Struct.transform(Map.of(), Map.of("x", 1))));
    assertTrue(equalNorm(Map.of("x", f0), Struct.transform(Map.of(), Map.of("x", f0))));
    assertTrue(equalNorm(Map.of("x", 1), Struct.transform(Map.of("a", 1), Map.of("x", "`a`"))));
    Object got = Struct.transform(Map.of("f0", f0), Map.of("x", "`f0`"));
    assertEquals(99, ((java.util.function.Supplier<Integer>) ((Map<?, ?>) got).get("x")).get().intValue());
  }
}
