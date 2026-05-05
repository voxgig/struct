package voxgig.struct;

import com.google.gson.GsonBuilder;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.TreeMap;
import java.util.function.Function;

/**
 * Drives the canonical shared corpus at {@code build/test/test.json} against the Java port.
 *
 * <p>Each {@code (category, name)} pair becomes a {@link DynamicTest} that runs the test set,
 * records pass/fail, and contributes to a per-{@code .jsonic}-file scoreboard written to
 * {@code target/corpus-scoreboard.json} and printed to stdout in {@link #printScoreboard()}.
 *
 * <p>This test never fails the build for corpus shortfalls — its job is to track parity progress
 * across the refactor steps. The hand-rolled tests in {@code StructMinorTest} and
 * {@code StructWalkMergeGetpathTest} remain the green-bar regression baseline.
 */
@SuppressWarnings({"unchecked", "rawtypes"})
class StructCorpusTest {

  private static final Map<String, Runner.Result> SCOREBOARD = new TreeMap<>();
  private static final Map<String, String> CATEGORY_TO_FILE = new LinkedHashMap<>();

  static {
    CATEGORY_TO_FILE.put("minor", "minor.jsonic");
    CATEGORY_TO_FILE.put("walk", "walk.jsonic");
    CATEGORY_TO_FILE.put("merge", "merge.jsonic");
    CATEGORY_TO_FILE.put("getpath", "getpath.jsonic");
    CATEGORY_TO_FILE.put("inject", "inject.jsonic");
    CATEGORY_TO_FILE.put("transform", "transform.jsonic");
    CATEGORY_TO_FILE.put("validate", "validate.jsonic");
    CATEGORY_TO_FILE.put("select", "select.jsonic");
  }

  private static Object getp(Object in, String key) {
    if (in instanceof Map<?, ?> m) {
      return ((Map<String, Object>) m).get(key);
    }
    return null;
  }

  private static Object getpDef(Object in, String key, Object def) {
    if (in instanceof Map<?, ?> m && ((Map<String, Object>) m).containsKey(key)) {
      return ((Map<String, Object>) m).get(key);
    }
    return def;
  }

  @TestFactory
  Iterable<DynamicTest> corpus() {
    List<DynamicTest> tests = new ArrayList<>();

    // ===== minor (29 names) =====
    add(tests, "minor", "isnode", true, in -> Struct.isnode(in));
    add(tests, "minor", "ismap", true, in -> Struct.ismap(in));
    add(tests, "minor", "islist", true, in -> Struct.islist(in));
    add(tests, "minor", "iskey", false, in -> Struct.iskey(in));
    add(tests, "minor", "strkey", false, in -> Struct.strkey(in));
    add(tests, "minor", "isempty", false, in -> Struct.isempty(in));
    add(tests, "minor", "isfunc", true, in -> Struct.isfunc(in));
    add(tests, "minor", "getprop", true, in -> {
      Object val = getp(in, "val");
      Object key = getp(in, "key");
      Object alt = getpDef(in, "alt", Struct.UNDEF);
      return alt == Struct.UNDEF
          ? Struct.getprop(val, key)
          : Struct.getprop(val, key, alt);
    });
    add(tests, "minor", "getelem", true, in -> {
      Object val = getp(in, "val");
      Object key = getp(in, "key");
      Object alt = getpDef(in, "alt", Struct.UNDEF);
      return alt == Struct.UNDEF
          ? Struct.getelem(val, key)
          : Struct.getelem(val, key, alt);
    });
    add(tests, "minor", "clone", false, in -> Struct.clone(in));
    add(tests, "minor", "items", true, in -> Struct.items(in));
    add(tests, "minor", "keysof", true, in -> Struct.keysof(in));
    add(tests, "minor", "haskey", true, in -> Struct.haskey(getp(in, "src"), getp(in, "key")));
    add(tests, "minor", "setprop", true, in -> {
      Object parent = getpDef(in, "parent", Struct.UNDEF);
      Object key = getp(in, "key");
      Object val = getp(in, "val");
      return Struct.setprop(parent == Struct.UNDEF ? null : parent, key, val);
    });
    add(tests, "minor", "delprop", true, in -> {
      Object parent = getpDef(in, "parent", Struct.UNDEF);
      Object key = getp(in, "key");
      return Struct.delprop(parent == Struct.UNDEF ? null : parent, key);
    });
    add(tests, "minor", "stringify", true, in -> {
      // Use UNDEF for absent val so stringify renders "" instead of "null".
      Object val = getpDef(in, "val", Struct.UNDEF);
      Object max = getp(in, "max");
      Integer m = max instanceof Number n ? n.intValue() : null;
      return Struct.stringify(val, m);
    });
    add(tests, "minor", "jsonify", true, in -> {
      Object val = getp(in, "val");
      Object flags = getp(in, "flags");
      return Struct.jsonify(val, flags);
    });
    add(tests, "minor", "pathify", true, in -> {
      // Use UNDEF for absent keys so pathify renders "<unknown-path>" instead
      // of "<unknown-path:null>" (matches JS undefined-vs-null semantics).
      Object path = getpDef(in, "path", Struct.UNDEF);
      Object from = getp(in, "from");
      Object to = getp(in, "to");
      return Struct.pathify(path, from, to);
    });
    add(tests, "minor", "escre", true, in -> Struct.escre(in));
    add(tests, "minor", "escurl", true, in -> Struct.escurl(in));
    add(tests, "minor", "join", true, in -> {
      Object val = getp(in, "val");
      Object sep = getp(in, "sep");
      Object url = getp(in, "url");
      return Struct.join(val, sep, url);
    });
    add(tests, "minor", "flatten", true, in -> {
      Object val = getp(in, "val");
      Object depth = getp(in, "depth");
      Integer d = depth instanceof Number n ? n.intValue() : null;
      return Struct.flatten(val, d == null ? 1 : d);
    });
    add(tests, "minor", "filter", true, in -> {
      Object val = getp(in, "val");
      String check = Objects.toString(getp(in, "check"), "");
      Struct.ItemCheck pred = "gt3".equals(check)
          ? (Struct.ItemCheck) item -> {
            Object v = item.get(1);
            return v instanceof Number n && n.doubleValue() > 3;
          }
          : (Struct.ItemCheck) item -> {
            Object v = item.get(1);
            return v instanceof Number n && n.doubleValue() < 3;
          };
      return Struct.filter(val, pred);
    });
    add(tests, "minor", "typename", true, in -> Struct.typename(in));
    add(tests, "minor", "typify", true, in -> Struct.typify(in));
    add(tests, "minor", "size", true, in -> Struct.size(in));
    add(tests, "minor", "slice", true, in -> {
      Object val = getp(in, "val");
      Object start = getp(in, "start");
      Object end = getp(in, "end");
      return Struct.slice(val, start, end);
    });
    add(tests, "minor", "pad", true, in -> {
      Object val = getp(in, "val");
      Object pad = getp(in, "pad");
      Object pc = getp(in, "char");
      return Struct.pad(val, pad, pc);
    });
    add(tests, "minor", "setpath", false, in -> {
      Object store = getp(in, "store");
      Object path = getp(in, "path");
      Object val = getp(in, "val");
      return Struct.setpath(store, path, val);
    });

    // ===== walk =====
    add(tests, "walk", "basic", true, in -> Struct.walk(in,
        (k, v, p, t) -> v instanceof String s ? s + "~" + String.join(".", t) : v));
    add(tests, "walk", "depth", false, in -> {
      Object src = getp(in, "src");
      Object md = getp(in, "maxdepth");
      int maxdepth = md instanceof Number n ? n.intValue() : 32;
      Object[] top = new Object[1];
      Object[] cur = new Object[1];
      Struct.WalkApply copy =
          (key, val, parent, path) -> {
            if (key == null || Struct.isnode(val)) {
              Object child =
                  Struct.islist(val) ? new ArrayList<Object>() : new LinkedHashMap<String, Object>();
              if (key == null) {
                top[0] = child;
                cur[0] = child;
              } else {
                Struct.setprop(cur[0], key, child);
                cur[0] = child;
              }
            } else {
              Struct.setprop(cur[0], key, val);
            }
            return val;
          };
      Struct.walk(src, copy, null, maxdepth);
      return top[0];
    });
    add(tests, "walk", "copy", true, in -> {
      Object[] cur = new Object[64];
      Struct.WalkApply walkcopy =
          (key, val, parent, path) -> {
            if (key == null) {
              cur[0] =
                  Struct.ismap(val)
                      ? new LinkedHashMap<String, Object>()
                      : Struct.islist(val) ? new ArrayList<Object>() : val;
              return val;
            }
            Object v = val;
            int i = path.size();
            if (Struct.isnode(v)) {
              v =
                  Struct.ismap(v)
                      ? new LinkedHashMap<String, Object>()
                      : new ArrayList<Object>();
              cur[i] = v;
            }
            Struct.setprop(cur[i - 1], key, v);
            return val;
          };
      Struct.walk(in, walkcopy);
      return cur[0];
    });

    // ===== merge =====
    add(tests, "merge", "cases", true, in -> Struct.merge(in));
    add(tests, "merge", "array", true, in -> Struct.merge(in));
    add(tests, "merge", "integrity", true, in -> Struct.merge(in));
    add(tests, "merge", "depth", true, in -> {
      Object val = getp(in, "val");
      Object depth = getp(in, "depth");
      int d = depth instanceof Number n ? n.intValue() : 32;
      return Struct.merge(val, d);
    });

    // ===== getpath =====
    add(tests, "getpath", "basic", true, in -> Struct.getpath(getp(in, "store"), getp(in, "path")));
    add(tests, "getpath", "relative", true, in -> {
      Map<String, Object> inj = new LinkedHashMap<>();
      if (in instanceof Map<?, ?> m) {
        Map<String, Object> mm = (Map<String, Object>) m;
        if (mm.containsKey("dparent")) inj.put("dparent", mm.get("dparent"));
        if (mm.containsKey("dpath")) inj.put("dpath", mm.get("dpath"));
        if (mm.containsKey("base")) inj.put("base", mm.get("base"));
      }
      return Struct.getpath(getp(in, "store"), getp(in, "path"), inj.isEmpty() ? null : inj);
    });
    add(tests, "getpath", "special", true, in -> {
      Object inj = getp(in, "inj");
      Map<String, Object> injMap = inj instanceof Map<?, ?> m ? (Map<String, Object>) m : null;
      return Struct.getpath(getp(in, "store"), getp(in, "path"), injMap);
    });

    // ===== inject =====
    add(tests, "inject", "string", true, in -> Struct.inject(getp(in, "val"), getp(in, "store")));
    add(tests, "inject", "deep", true, in -> Struct.inject(getp(in, "val"), getp(in, "store")));

    // ===== transform =====
    add(tests, "transform", "paths", true, in -> Struct.transform(getp(in, "data"), getp(in, "spec")));
    add(tests, "transform", "cmds", true, in -> Struct.transform(getp(in, "data"), getp(in, "spec")));
    add(tests, "transform", "each", true, in -> Struct.transform(getp(in, "data"), getp(in, "spec")));
    add(tests, "transform", "pack", true, in -> Struct.transform(getp(in, "data"), getp(in, "spec")));
    add(tests, "transform", "modify", true, in -> {
      Map<String, Object> opts = new LinkedHashMap<>();
      // Match JS test guard: only mutate string leaves.
      opts.put(
          "modify",
          (Struct.Modify)
              (val, key, parent, inj, store) -> {
                if (key != null && parent instanceof Map<?, ?> m && val instanceof String s) {
                  ((Map<String, Object>) m).put(Objects.toString(key), "@" + s);
                }
              });
      return Struct.transform(getp(in, "data"), getp(in, "spec"), opts);
    });
    add(tests, "transform", "ref", true, in -> Struct.transform(getp(in, "data"), getp(in, "spec")));
    add(tests, "transform", "format", false, in -> Struct.transform(getp(in, "data"), getp(in, "spec")));
    add(tests, "transform", "apply", true, in -> {
      Map<String, Object> opts = new LinkedHashMap<>();
      Map<String, Object> extra = new LinkedHashMap<>();
      extra.put(
          "apply",
          (Function<Object, Object>) v -> v instanceof String s ? s.toUpperCase(Locale.ROOT) : v);
      opts.put("extra", extra);
      return Struct.transform(getp(in, "data"), getp(in, "spec"), opts);
    });

    // ===== validate =====
    add(tests, "validate", "basic", true, in -> Struct.validate(getp(in, "data"), getp(in, "spec")));
    add(tests, "validate", "child", true, in -> Struct.validate(getp(in, "data"), getp(in, "spec")));
    add(tests, "validate", "one", true, in -> Struct.validate(getp(in, "data"), getp(in, "spec")));
    add(tests, "validate", "exact", true, in -> Struct.validate(getp(in, "data"), getp(in, "spec")));
    add(tests, "validate", "invalid", true, in -> Struct.validate(getp(in, "data"), getp(in, "spec")));
    add(tests, "validate", "special", true, in -> {
      Map<String, Object> inj = null;
      if (in instanceof Map<?, ?> m) {
        Object injObj = ((Map<String, Object>) m).get("inj");
        if (injObj instanceof Map<?, ?> im) {
          inj = (Map<String, Object>) im;
        }
      }
      return Struct.validate(getp(in, "data"), getp(in, "spec"), inj);
    });

    // ===== select =====
    add(tests, "select", "basic", true, in -> Struct.select(getp(in, "obj"), getp(in, "query")));
    add(tests, "select", "operators", true, in -> Struct.select(getp(in, "obj"), getp(in, "query")));
    add(tests, "select", "edge", true, in -> Struct.select(getp(in, "obj"), getp(in, "query")));
    add(tests, "select", "alts", true, in -> Struct.select(getp(in, "obj"), getp(in, "query")));

    return tests;
  }

  private void add(
      List<DynamicTest> tests,
      String category,
      String name,
      boolean nullFlag,
      Runner.Subject subject) {
    tests.add(
        DynamicTest.dynamicTest(
            category + "-" + name,
            () -> {
              Map<String, Object> spec = Runner.getSpec(category, name);
              Runner.Result r =
                  Runner.runsetflags(category + "." + name, spec, nullFlag, subject);
              SCOREBOARD.put(category + "." + name, r);
              // Don't fail the build: corpus is the parity scoreboard, not a green-bar test.
            }));
  }

  @AfterAll
  static void printScoreboard() throws IOException {
    Map<String, int[]> byFile = new TreeMap<>();
    Map<String, List<String[]>> failsByFile = new TreeMap<>();
    int totalP = 0;
    int totalT = 0;

    for (Map.Entry<String, Runner.Result> e : SCOREBOARD.entrySet()) {
      String key = e.getKey();
      Runner.Result r = e.getValue();
      String cat = key.substring(0, key.indexOf('.'));
      String file = CATEGORY_TO_FILE.getOrDefault(cat, cat + ".jsonic");
      byFile.computeIfAbsent(file, _k -> new int[2]);
      byFile.get(file)[0] += r.passed;
      byFile.get(file)[1] += r.total;
      failsByFile.computeIfAbsent(file, _k -> new ArrayList<>());
      failsByFile.get(file).add(new String[] {key, r.passed + "/" + r.total});
      totalP += r.passed;
      totalT += r.total;
    }

    StringBuilder banner = new StringBuilder();
    banner.append("\n========= STRUCT CORPUS SCOREBOARD =========\n");
    for (Map.Entry<String, int[]> e : byFile.entrySet()) {
      banner.append(
          String.format("  %-18s %4d / %4d%n", e.getKey(), e.getValue()[0], e.getValue()[1]));
      for (String[] sub : failsByFile.get(e.getKey())) {
        banner.append(String.format("      %-30s %s%n", sub[0], sub[1]));
      }
    }
    banner.append(String.format("  %-18s %4d / %4d%n", "TOTAL", totalP, totalT));
    banner.append("============================================\n");
    System.out.println(banner);

    Map<String, Object> out = new LinkedHashMap<>();
    Map<String, Map<String, Integer>> filesOut = new LinkedHashMap<>();
    for (Map.Entry<String, int[]> e : byFile.entrySet()) {
      Map<String, Integer> v = new LinkedHashMap<>();
      v.put("passed", e.getValue()[0]);
      v.put("total", e.getValue()[1]);
      filesOut.put(e.getKey(), v);
    }
    out.put("files", filesOut);
    Map<String, Integer> totals = new LinkedHashMap<>();
    totals.put("passed", totalP);
    totals.put("total", totalT);
    out.put("total", totals);

    Path target = Path.of("target", "corpus-scoreboard.json");
    Files.createDirectories(target.getParent());
    Files.writeString(
        target, new GsonBuilder().setPrettyPrinting().create().toJson(out) + "\n");
  }
}
