// Test Provider (prototype) — Java port of the canonical ts/provider.ts.
//
// Reads the shared corpus (build/test/test.json) and hands test code clean,
// normalized cases. It is NOT a test runner: it never calls the subject and
// never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
//
// Zero runtime dependencies (JDK standard library only) — uses the bundled
// minimal Json parser instead of Gson/Jackson.

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@SuppressWarnings({"unchecked", "rawtypes"})
public class Provider {

  public static final String NULLMARK = "__NULL__";
  public static final String UNDEFMARK = "__UNDEF__";
  public static final String EXISTSMARK = "__EXISTS__";

  // Sentinel distinguishing "key absent" from "value is null" in getpath.
  private static final Object MISSING = new Object();

  private final Object spec;

  public Provider(Object spec) {
    this.spec = spec;
  }

  // ─── loading ─────────────────────────────────────────────────────────────

  // Default corpus path resolves to build/test/test.json relative to the repo
  // root (this file lives at test/proto/java). A non-null path is used as-is,
  // so callers (e.g. the smoke harness running from the repo root) may pass an
  // absolute or repo-relative path directly.
  public static Provider load(String path) {
    String file = path != null ? path : defaultTestFile();
    try {
      String json = new String(Files.readAllBytes(Paths.get(file)), StandardCharsets.UTF_8);
      return new Provider(Json.parse(json));
    } catch (IOException e) {
      throw new RuntimeException("Failed to read corpus: " + file, e);
    }
  }

  private static String defaultTestFile() {
    // This source is at test/proto/java; the corpus is four levels up.
    Path here = Paths.get(System.getProperty("user.dir"));
    return here.resolve(Paths.get("build", "test", "test.json")).toString();
  }

  public Object raw() {
    return spec;
  }

  private Map<String, Object> root() {
    if (spec instanceof Map) {
      Object struct = ((Map<String, Object>) spec).get("struct");
      if (struct instanceof Map) {
        return (Map<String, Object>) struct;
      }
      return (Map<String, Object>) spec;
    }
    return new LinkedHashMap<>();
  }

  private Map<String, Object> fnNode(String fn) {
    Object node = null;
    if (spec instanceof Map) {
      Object struct = ((Map<String, Object>) spec).get("struct");
      if (struct instanceof Map && ((Map<String, Object>) struct).containsKey(fn)) {
        node = ((Map<String, Object>) struct).get(fn);
      } else if (((Map<String, Object>) spec).containsKey(fn)) {
        node = ((Map<String, Object>) spec).get(fn);
      }
    }
    if (node == null) {
      throw new IllegalArgumentException("Unknown function: " + fn);
    }
    return (Map<String, Object>) node;
  }

  public List<String> functions() {
    Map<String, Object> root = root();
    List<String> out = new ArrayList<>();
    for (Map.Entry<String, Object> e : root.entrySet()) {
      if (isGroupBag(e.getValue()) || hasGroups(e.getValue())) {
        out.add(e.getKey());
      }
    }
    return out;
  }

  public List<String> groups(String fn) {
    Map<String, Object> node = fnNode(fn);
    List<String> out = new ArrayList<>();
    for (Map.Entry<String, Object> e : node.entrySet()) {
      if (!"name".equals(e.getKey()) && isGroupBag(e.getValue())) {
        out.add(e.getKey());
      }
    }
    return out;
  }

  // group == null means "all groups for the function".
  public List<Entry> entries(String fn, String group) {
    Map<String, Object> node = fnNode(fn);
    List<String> groupList = group != null ? List.of(group) : groups(fn);
    List<Entry> out = new ArrayList<>();
    for (String g : groupList) {
      Object bag = node.get(g);
      if (!isGroupBag(bag)) {
        continue;
      }
      List<Object> set = (List<Object>) ((Map<String, Object>) bag).get("set");
      for (int i = 0; i < set.size(); i++) {
        out.add(normalize(fn, g, i, (Map<String, Object>) set.get(i)));
      }
    }
    return out;
  }

  // A group bag is a map with a `set` list.
  private static boolean isGroupBag(Object v) {
    return v instanceof Map && ((Map<String, Object>) v).get("set") instanceof List;
  }

  // A function node has at least one child group bag.
  private static boolean hasGroups(Object v) {
    if (!(v instanceof Map)) {
      return false;
    }
    for (Map.Entry<String, Object> e : ((Map<String, Object>) v).entrySet()) {
      if (!"name".equals(e.getKey()) && isGroupBag(e.getValue())) {
        return true;
      }
    }
    return false;
  }

  // ─── normalized records ──────────────────────────────────────────────────

  public static final class Input {
    public enum Kind {
      IN,
      ARGS,
      CTX
    }

    public Kind kind;
    public Object in;
    public List<Object> args;
    public Map<String, Object> ctx;
  }

  public static final class ErrorCheck {
    public boolean any;
    public String text;
    public boolean regex;
  }

  public static final class Expect {
    public enum Kind {
      VALUE,
      ERROR,
      MATCH,
      ABSENT
    }

    public Kind kind;
    public boolean hasValue;
    public Object value;
    public ErrorCheck error;
    public Object match;
  }

  public static final class Entry {
    public String function;
    public String group;
    public int index;
    public String id;
    public boolean doc;
    public String client;
    public Input input;
    public Expect expect;
    public Object raw;
  }

  public static final class MatchResult {
    public boolean ok;
    public List<String> path;
    public Object expected;
    public Object actual;
  }

  private static boolean has(Map<String, Object> raw, String key) {
    return raw.containsKey(key);
  }

  private static Entry normalize(String fn, String group, int index, Map<String, Object> raw) {
    Entry e = new Entry();
    e.function = fn;
    e.group = group;
    e.index = index;
    Object id = raw.get("id");
    e.id = id != null ? String.valueOf(id) : null;
    e.doc = Boolean.TRUE.equals(raw.get("doc"));
    Object client = raw.get("client");
    e.client = client != null ? String.valueOf(client) : null;
    e.input = resolveInput(raw);
    e.expect = resolveExpect(raw);
    e.raw = raw;
    return e;
  }

  private static Input resolveInput(Map<String, Object> raw) {
    Input in = new Input();
    if (has(raw, "ctx")) {
      in.kind = Input.Kind.CTX;
      in.ctx = (Map<String, Object>) raw.get("ctx");
      return in;
    }
    if (has(raw, "args")) {
      in.kind = Input.Kind.ARGS;
      in.args = (List<Object>) raw.get("args");
      return in;
    }
    in.kind = Input.Kind.IN;
    in.in = has(raw, "in") ? raw.get("in") : null;
    return in;
  }

  private static ErrorCheck parseErr(Object err) {
    ErrorCheck c = new ErrorCheck();
    if (Boolean.TRUE.equals(err)) {
      c.any = true;
      return c;
    }
    if (err instanceof String) {
      String s = (String) err;
      Matcher m = Pattern.compile("^/(.+)/$").matcher(s);
      if (m.matches()) {
        c.regex = true;
        c.text = m.group(1);
        return c;
      }
      c.text = s;
      return c;
    }
    // Non-true, non-string err spec: treat as "any error".
    c.any = true;
    return c;
  }

  private static Expect resolveExpect(Map<String, Object> raw) {
    Object matchPart = has(raw, "match") ? raw.get("match") : null;
    Expect ex = new Expect();
    if (has(raw, "err")) {
      ex.kind = Expect.Kind.ERROR;
      ex.error = parseErr(raw.get("err"));
      ex.match = matchPart;
      return ex;
    }
    // KEY PRESENCE, not null-check: "out" present even if null => VALUE.
    if (has(raw, "out")) {
      ex.kind = Expect.Kind.VALUE;
      ex.hasValue = true;
      ex.value = raw.get("out");
      ex.match = matchPart;
      return ex;
    }
    if (has(raw, "match")) {
      ex.kind = Expect.Kind.MATCH;
      ex.match = raw.get("match");
      return ex;
    }
    ex.kind = Expect.Kind.ABSENT;
    return ex;
  }

  // ─── pure comparison helpers ─────────────────────────────────────────────

  // stringify(x) = x if it is already a String, else compact JSON.
  public static String stringify(Object x) {
    return x instanceof String ? (String) x : Json.stringify(x);
  }

  private static Object normNull(Object x) {
    if (NULLMARK.equals(x) || x == null) {
      return null;
    }
    if (x instanceof List) {
      List<Object> out = new ArrayList<>();
      for (Object v : (List<Object>) x) {
        out.add(normNull(v));
      }
      return out;
    }
    if (x instanceof Map) {
      Map<String, Object> out = new LinkedHashMap<>();
      for (Map.Entry<String, Object> e : ((Map<String, Object>) x).entrySet()) {
        out.put(e.getKey(), normNull(e.getValue()));
      }
      return out;
    }
    return x;
  }

  private static Object normMark(Object x) {
    if (NULLMARK.equals(x)) {
      return null;
    }
    if (x instanceof List) {
      List<Object> out = new ArrayList<>();
      for (Object v : (List<Object>) x) {
        out.add(normMark(v));
      }
      return out;
    }
    if (x instanceof Map) {
      Map<String, Object> out = new LinkedHashMap<>();
      for (Map.Entry<String, Object> e : ((Map<String, Object>) x).entrySet()) {
        out.put(e.getKey(), normMark(e.getValue()));
      }
      return out;
    }
    return x;
  }

  public static boolean matchval(Object check, Object base) {
    if (scalarEq(check, base)) {
      return true;
    }
    if (check instanceof String) {
      String chk = (String) check;
      String basestr = stringify(base);
      Matcher rem = Pattern.compile("^/(.+)/$").matcher(chk);
      if (rem.matches()) {
        return Pattern.compile(rem.group(1)).matcher(basestr).find();
      }
      return basestr.toLowerCase().contains(chk.toLowerCase());
    }
    // A "function" check (not representable from JSON) would return true; no
    // such value arises from the parsed corpus.
    return false;
  }

  public static boolean equal(Object expected, Object actual) {
    return deepEq(normNull(expected), normNull(actual));
  }

  // Strict variant for the runner's { null: false } functions, where an absent
  // value is distinct from JSON null. Only __NULL__ is normalized.
  public static boolean equalStrict(Object expected, Object actual) {
    return deepEq(normMark(expected), normMark(actual));
  }

  // Scalar identity mirroring JS ===: distinguishes Boolean from Number, and
  // compares numbers/strings/booleans by value.
  private static boolean scalarEq(Object a, Object b) {
    if (a == b) {
      return true;
    }
    if (a == null || b == null) {
      return false;
    }
    if ((a instanceof Boolean) != (b instanceof Boolean)) {
      return false;
    }
    if (a instanceof Number && b instanceof Number) {
      return ((Number) a).doubleValue() == ((Number) b).doubleValue();
    }
    return a.equals(b);
  }

  private static boolean deepEq(Object a, Object b) {
    if (a == b) {
      return true;
    }
    if (a instanceof List && b instanceof List) {
      List<Object> la = (List<Object>) a;
      List<Object> lb = (List<Object>) b;
      if (la.size() != lb.size()) {
        return false;
      }
      for (int i = 0; i < la.size(); i++) {
        if (!deepEq(la.get(i), lb.get(i))) {
          return false;
        }
      }
      return true;
    }
    if (a instanceof List || b instanceof List) {
      return false;
    }
    if (a instanceof Map && b instanceof Map) {
      Map<String, Object> ma = (Map<String, Object>) a;
      Map<String, Object> mb = (Map<String, Object>) b;
      if (ma.size() != mb.size()) {
        return false;
      }
      for (Map.Entry<String, Object> e : ma.entrySet()) {
        if (!mb.containsKey(e.getKey()) || !deepEq(e.getValue(), mb.get(e.getKey()))) {
          return false;
        }
      }
      return true;
    }
    if (a instanceof Map || b instanceof Map) {
      return false;
    }
    return scalarEq(a, b);
  }

  public static boolean errorMatches(ErrorCheck check, String message) {
    if (check.any) {
      return true;
    }
    if (check.text == null) {
      return false;
    }
    if (check.regex) {
      return Pattern.compile(check.text).matcher(message).find();
    }
    return message.toLowerCase().contains(check.text.toLowerCase());
  }

  // Partial structural match: every leaf of `check` must match `base` at its path.
  public static MatchResult structMatch(Object check, Object base) {
    MatchResult result = new MatchResult();
    result.ok = true;
    walkLeaves(
        check,
        new ArrayList<>(),
        (val, path) -> {
          if (!result.ok) {
            return;
          }
          Object baseval = getpath(base, path);
          if (baseval != MISSING && scalarEq(val, baseval)) {
            return;
          }
          if (UNDEFMARK.equals(val) && baseval == MISSING) {
            return;
          }
          if (EXISTSMARK.equals(val) && baseval != MISSING && baseval != null) {
            return;
          }
          Object compareBase = baseval == MISSING ? null : baseval;
          if (!matchval(val, compareBase)) {
            result.ok = false;
            result.path = path;
            result.expected = val;
            result.actual = compareBase;
          }
        });
    return result;
  }

  private interface LeafFn {
    void visit(Object val, List<String> path);
  }

  private static void walkLeaves(Object node, List<String> path, LeafFn fn) {
    if (node instanceof List) {
      List<Object> l = (List<Object>) node;
      for (int i = 0; i < l.size(); i++) {
        List<String> next = new ArrayList<>(path);
        next.add(String.valueOf(i));
        walkLeaves(l.get(i), next, fn);
      }
    } else if (node instanceof Map) {
      for (Map.Entry<String, Object> e : ((Map<String, Object>) node).entrySet()) {
        List<String> next = new ArrayList<>(path);
        next.add(e.getKey());
        walkLeaves(e.getValue(), next, fn);
      }
    } else {
      fn.visit(node, path);
    }
  }

  // Returns MISSING for an absent path (distinct from a present null).
  private static Object getpath(Object store, List<String> path) {
    Object cur = store;
    for (String key : path) {
      if (cur == null || cur == MISSING) {
        return MISSING;
      }
      if (cur instanceof List) {
        List<Object> l = (List<Object>) cur;
        int idx;
        try {
          idx = Integer.parseInt(key);
        } catch (NumberFormatException nfe) {
          return MISSING;
        }
        cur = (idx >= 0 && idx < l.size()) ? l.get(idx) : MISSING;
      } else if (cur instanceof Map) {
        Map<String, Object> m = (Map<String, Object>) cur;
        cur = m.containsKey(key) ? m.get(key) : MISSING;
      } else {
        return MISSING;
      }
    }
    return cur;
  }
}
