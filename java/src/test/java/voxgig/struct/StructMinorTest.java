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
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.function.Function;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SuppressWarnings({"unchecked", "rawtypes"})
class StructMinorTest {
  private static final Gson GSON = new Gson();
  private static Map<String, Object> minorSpec;

  @BeforeAll
  static void init() throws IOException {
    Path p = Path.of("..", "build", "test", "test.json");
    String json = Files.readString(p);
    Type t = new TypeToken<Map<String, Object>>() {}.getType();
    Map<String, Object> all = GSON.fromJson(json, t);
    Map<String, Object> struct = (Map<String, Object>) all.get("struct");
    minorSpec = (Map<String, Object>) struct.get("minor");
  }

  private interface RunnerFn {
    Object apply(Object in);
  }

  private void runSet(String name, RunnerFn fn) {
    runSet(name, fn, false);
  }

  private void runSet(String name, RunnerFn fn, boolean nullFlag) {
    Map<String, Object> testspec = (Map<String, Object>) minorSpec.get(name);
    List<Object> set = (List<Object>) testspec.get("set");
    for (Object eo : set) {
      Map<String, Object> entry = (Map<String, Object>) eo;
      Object in = entry.containsKey("in") ? Struct.clone(entry.get("in")) : Struct.UNDEF;
      Object out = entry.containsKey("out")
          ? entry.get("out")
          : (nullFlag ? "__NULL__" : Struct.UNDEF);

      Object got = fn.apply(in);
      assertTrue(equalNorm(out, got), () -> "Mismatch in " + name + " for in=" + json(in) +
          " expected=" + json(out) + " got=" + json(got));
    }
  }

  private static String json(Object v) {
    try {
      return GSON.toJson(v == Struct.UNDEF ? "__UNDEF__" : v);
    } catch (Exception e) {
      return Objects.toString(v);
    }
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
      for (Object n : l) out.add(normalize(n));
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
    Object na = normalize(a);
    Object nb = normalize(b);
    return Objects.equals(na, nb);
  }

  @Test
  void minorIsnode() { runSet("isnode", Struct::isnode); }

  @Test
  void minorIsmap() { runSet("ismap", Struct::ismap); }

  @Test
  void minorIslist() { runSet("islist", Struct::islist); }

  @Test
  void minorIskey() { runSet("iskey", Struct::iskey); }

  @Test
  void minorStrkey() { runSet("strkey", Struct::strkey); }

  @Test
  void minorIsempty() { runSet("isempty", Struct::isempty); }

  @Test
  void minorIsfunc() { runSet("isfunc", Struct::isfunc); }

  @Test
  void minorClone() { runSet("clone", Struct::clone); }

  @Test
  void minorGetprop() {
    runSet("getprop", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.getprop(Struct.UNDEF, Struct.UNDEF);
      Object val = m.containsKey("val") ? m.get("val") : Struct.UNDEF;
      Object key = m.containsKey("key") ? m.get("key") : Struct.UNDEF;
      if (m.containsKey("alt")) {
        return Struct.getprop(val, key, m.get("alt"));
      }
      return Struct.getprop(val, key);
    });
  }

  @Test
  void minorGetelem() {
    runSet("getelem", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.getelem(Struct.UNDEF, Struct.UNDEF);
      Object val = m.containsKey("val") ? m.get("val") : Struct.UNDEF;
      Object key = m.containsKey("key") ? m.get("key") : Struct.UNDEF;
      if (m.containsKey("alt")) {
        return Struct.getelem(val, key, m.get("alt"));
      }
      return Struct.getelem(val, key);
    });
  }

  @Test
  void minorItems() { runSet("items", Struct::items); }

  @Test
  void minorKeysof() { runSet("keysof", Struct::keysof); }

  @Test
  void minorHaskey() {
    runSet("haskey", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.haskey(Struct.UNDEF, Struct.UNDEF);
      Object src = m.containsKey("src") ? m.get("src") : Struct.UNDEF;
      Object key = m.containsKey("key") ? m.get("key") : Struct.UNDEF;
      return Struct.haskey(src, key);
    });
  }

  @Test
  void minorSetprop() {
    runSet("setprop", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      Object parent = m.containsKey("parent") ? Struct.clone(m.get("parent")) : Struct.UNDEF;
      Object key = m.containsKey("key") ? m.get("key") : Struct.UNDEF;
      Object val = m.containsKey("val") ? m.get("val") : Struct.UNDEF;
      return Struct.setprop(parent, key, val);
    });
  }

  @Test
  void minorDelprop() {
    runSet("delprop", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      Object parent = m.containsKey("parent") ? Struct.clone(m.get("parent")) : Struct.UNDEF;
      Object key = m.containsKey("key") ? m.get("key") : Struct.UNDEF;
      return Struct.delprop(parent, key);
    });
  }

  @Test
  void minorTypename() { runSet("typename", Struct::typename); }

  @Test
  void minorTypify() { runSet("typify", Struct::typify); }

  @Test
  void minorSize() { runSet("size", Struct::size); }

  @Test
  void minorSlice() {
    runSet("slice", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      return Struct.slice(
          m.containsKey("val") ? m.get("val") : Struct.UNDEF,
          m.get("start"),
          m.get("end"));
    });
  }

  @Test
  void minorPad() {
    runSet("pad", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      return Struct.pad(m.get("val"), m.get("pad"), m.get("char"));
    });
  }

  @Test
  void minorFlatten() {
    runSet("flatten", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      return Struct.flatten(m.get("val"), m.containsKey("depth") ? ((Number) m.get("depth")).intValue() : null);
    });
  }

  @Test
  void minorFilter() {
    Map<String, Function<List<Object>, Boolean>> checkmap = new LinkedHashMap<>();
    checkmap.put("gt3", n -> ((Number) n.get(1)).doubleValue() > 3);
    checkmap.put("lt3", n -> ((Number) n.get(1)).doubleValue() < 3);

    runSet("filter", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      String check = Objects.toString(m.get("check"));
      return Struct.filter(m.get("val"), item -> checkmap.get(check).apply(item));
    });
  }

  @Test
  void minorEscre() { runSet("escre", Struct::escre); }

  @Test
  void minorEscurl() { runSet("escurl", Struct::escurl); }

  @Test
  void minorJoin() {
    runSet("join", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      return Struct.join(m.get("val"), m.get("sep"), m.get("url"));
    });
  }

  @Test
  void minorStringify() {
    runSet("stringify", in -> {
      if (!(in instanceof Map<?, ?> m)) {
        return Struct.stringify(Struct.UNDEF);
      }
      if (!m.containsKey("val")) {
        return Struct.stringify(Struct.UNDEF);
      }
      Object val = m.get("val");
      if ("__NULL__".equals(val)) {
        val = "null";
      }
      if (m.containsKey("max")) {
        return Struct.stringify(val, ((Number) m.get("max")).intValue());
      }
      return Struct.stringify(val);
    });
  }

  @Test
  void minorJsonify() {
    runSet("jsonify", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.jsonify(Struct.UNDEF);
      return Struct.jsonify(m.containsKey("val") ? m.get("val") : Struct.UNDEF,
          m.get("flags"));
    });
  }

  @Test
  void minorPathify() {
    runSet("pathify", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.pathify(Struct.UNDEF);
      return Struct.pathify(m.containsKey("path") ? m.get("path") : Struct.UNDEF, m.get("from"));
    });
  }

  @Test
  void minorSetpath() {
    runSet("setpath", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      Object store = m.containsKey("store") ? Struct.clone(m.get("store")) : Struct.UNDEF;
      Object path = m.get("path");
      Object val = m.containsKey("val") ? m.get("val") : Struct.UNDEF;
      return Struct.setpath(store, path, val);
    });
  }

  @Test
  void exists() {
    assertTrue(Struct.isfunc((Function<Object, Object>) v -> v));
    assertEquals("map", Struct.typename(Struct.T_map));
  }
}
