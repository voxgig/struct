package voxgig.struct;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.function.Function;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SuppressWarnings({"unchecked", "rawtypes"})
class StructMinorTest {
  private static Omni.Run run;
  private static Map<String, Object> minorSpec;

  @BeforeAll
  static void init() throws IOException {
    // The spec comes off the runner, not from a second loader, so the
    // bindings and the runner cannot disagree about what the corpus says.
    run = Omni.Run.of("struct");
    minorSpec = (Map<String, Object>) run.set("minor");
  }

  private interface RunnerFn {
    Object apply(Object in);
  }

  private void runSet(String name, RunnerFn fn) {
    runSet(name, fn, false);
  }

  private void runSet(String name, RunnerFn fn, boolean nullFlag) {
    // Delegates. The loop that stood here compared entries itself and, like
    // every hand-rolled loop in this port, understood only `in` and `out`.
    run.runsetnull(minorSpec.get(name), nullFlag, fn::apply);
  }




  @Test
  void minorIsnode() { runSet("isnode", Struct::isnode, true); }

  @Test
  void minorIsmap() { runSet("ismap", Struct::ismap, true); }

  @Test
  void minorIslist() { runSet("islist", Struct::islist, true); }

  @Test
  void minorIskey() { runSet("iskey", Struct::iskey, false); }

  @Test
  void minorStrkey() { runSet("strkey", Struct::strkey, false); }

  @Test
  void minorIsempty() { runSet("isempty", Struct::isempty, false); }

  @Test
  void minorIsfunc() { runSet("isfunc", Struct::isfunc, true); }

  @Test
  void minorClone() { runSet("clone", Struct::clone, false); }

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
    }, false);
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
    }, false);
  }

  @Test
  void minorItems() { runSet("items", Struct::items, true); }

  @Test
  void minorKeysof() { runSet("keysof", Struct::keysof, true); }

  @Test
  void minorHaskey() {
    runSet("haskey", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.haskey(Struct.UNDEF, Struct.UNDEF);
      Object src = m.containsKey("src") ? m.get("src") : Struct.UNDEF;
      Object key = m.containsKey("key") ? m.get("key") : Struct.UNDEF;
      return Struct.haskey(src, key);
    }, false);
  }

  @Test
  void minorSetprop() {
    runSet("setprop", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      Object parent = m.containsKey("parent") ? Struct.clone(m.get("parent")) : Struct.UNDEF;
      Object key = m.containsKey("key") ? m.get("key") : Struct.UNDEF;
      Object val = m.containsKey("val") ? m.get("val") : Struct.UNDEF;
      return Struct.setprop(parent, key, val);
    }, true);
  }

  @Test
  void minorDelprop() {
    runSet("delprop", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      Object parent = m.containsKey("parent") ? Struct.clone(m.get("parent")) : Struct.UNDEF;
      Object key = m.containsKey("key") ? m.get("key") : Struct.UNDEF;
      return Struct.delprop(parent, key);
    }, true);
  }

  @Test
  void minorTypename() { runSet("typename", Struct::typename, true); }

  @Test
  void minorTypify() { runSet("typify", Struct::typify, false); }

  @Test
  void minorSize() { runSet("size", Struct::size, false); }

  @Test
  void minorSlice() {
    runSet("slice", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      return Struct.slice(
          m.containsKey("val") ? m.get("val") : Struct.UNDEF,
          m.get("start"),
          m.get("end"));
    }, false);
  }

  @Test
  void minorPad() {
    runSet("pad", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      return Struct.pad(m.get("val"), m.get("pad"), m.get("char"));
    }, false);
  }

  @Test
  void minorFlatten() {
    runSet("flatten", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      return Struct.flatten(m.get("val"), m.containsKey("depth") ? ((Number) m.get("depth")).intValue() : null);
    }, true);
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
    }, true);
  }

  @Test
  void minorEscre() { runSet("escre", Struct::escre, true); }

  @Test
  void minorEscurl() { runSet("escurl", Struct::escurl, true); }

  @Test
  void minorJoin() {
    runSet("join", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      return Struct.join(m.get("val"), m.get("sep"), m.get("url"));
    }, false);
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
    }, true);
  }

  @Test
  void minorJsonify() {
    runSet("jsonify", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.jsonify(Struct.UNDEF);
      return Struct.jsonify(m.containsKey("val") ? m.get("val") : Struct.UNDEF,
          m.get("flags"));
    }, false);
  }

  @Test
  void minorPathify() {
    runSet("pathify", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.pathify(Struct.UNDEF);

      // Mirrors javascript/test/struct.test.js, and its two compensations are
      // not decoration. This group runs with nulls MARKED, and the runner
      // marks them inside `in` as well as `out` - so a real null authored in a
      // path arrives as the string "__NULL__", which `iskey` accepts as an
      // ordinary key (canonical's does too). Canonical strips the resulting
      // segment back out of the answer; so does this. Register 4.2's third
      // channel defect showing through, not a defect in this port.
      Object path = m.containsKey("path") ? m.get("path") : Struct.UNDEF;
      boolean marked = Omni.NULLMARK.equals(path);
      if (marked) {
        path = Struct.UNDEF;
      }

      String pathstr = String.valueOf(Struct.pathify(path, m.get("from")))
          .replace(Omni.NULLMARK + ".", "");
      return marked ? pathstr.replace(">", ":null>") : pathstr;
    }, true);
  }

  @Test
  void minorSetpath() {
    runSet("setpath", in -> {
      if (!(in instanceof Map<?, ?> m)) return Struct.UNDEF;
      // NOT cloned. Canonical passes the store straight through
      // (`struct.setpath(vin.store, ...)`), because `match.args` asserts that
      // setpath rewrote it IN PLACE - eight of this group's nine entries do.
      // Cloning here landed every mutation on a copy the runner never saw.
      Object store = m.containsKey("store") ? m.get("store") : Struct.UNDEF;
      Object path = m.get("path");
      Object val = m.containsKey("val") ? m.get("val") : Struct.UNDEF;
      return Struct.setpath(store, path, val);
    }, false);
  }

  @Test
  void exists() {
    assertTrue(Struct.isfunc((Function<Object, Object>) v -> v));
    assertEquals("map", Struct.typename(Struct.T_map));
  }
}
