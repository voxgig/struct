package voxgig.struct;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.function.Function;
import java.util.function.Supplier;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@SuppressWarnings({"unchecked", "rawtypes"})
public class Struct {
  private Struct() {}

  private static final class MergeCmd {
    final int order;
    final Object value;

    MergeCmd(int order, Object value) {
      this.order = order;
      this.value = value;
    }
  }

  @FunctionalInterface
  public interface TransformModify {
    void apply(Object val, String key, Object parent);
  }

  private static final class TransformOptions {
    final TransformModify modify;
    final Map<String, Object> commandHandlers;

    TransformOptions(TransformModify modify, Map<String, Object> commandHandlers) {
      this.modify = modify;
      this.commandHandlers = commandHandlers;
    }
  }

  /**
   * "No value" sentinel — distinct from {@code null} (which is JSON null).
   * Mirrors TypeScript's {@code undefined} for the canonical port.
   */
  public static final Object UNDEF = new Object();

  /**
   * Sentinel returned from a transform/inject step to delete the current key.
   * Always compared with {@code ==} identity (never {@code .equals()}). Mirrors
   * the TS marker {@code {`$DELETE`: true}}; declared as {@link Map} so it can
   * survive a pass through {@link #inject(Object, Object)} without losing
   * structural shape, while {@link #clone(Object)} short-circuits to preserve
   * identity.
   */
  public static final Map<String, Object> DELETE = makeSentinelMap("`$DELETE`");

  private static final String S_MT = "";

  public static final String S_DTOP = "$TOP";
  public static final String S_DSPEC = "$SPEC";
  public static final String S_DKEY = "$KEY";
  private static final String S_DT = ".";

  // Inject mode bitfield (TS lines 60–62).
  public static final int M_KEYPRE = 1;
  public static final int M_KEYPOST = 2;
  public static final int M_VAL = 4;

  // Default max recursive depth (walk, merge, etc).
  public static final int MAXDEPTH = 32;

  /** Maps mode bit to its human-readable name. */
  public static final Map<Integer, String> MODENAME;

  /** Maps mode bit to a placement label used in error messages. */
  public static final Map<Integer, String> PLACEMENT;

  static {
    Map<Integer, String> mn = new LinkedHashMap<>();
    mn.put(M_VAL, "val");
    mn.put(M_KEYPRE, "key:pre");
    mn.put(M_KEYPOST, "key:post");
    MODENAME = Collections.unmodifiableMap(mn);

    Map<Integer, String> pl = new LinkedHashMap<>();
    pl.put(M_VAL, "value");
    pl.put(M_KEYPRE, "key");
    pl.put(M_KEYPOST, "key");
    PLACEMENT = Collections.unmodifiableMap(pl);
  }

  private static final Pattern R_META_PATH = Pattern.compile("^([^$]+)\\$([=~])(.+)$");
  private static final Pattern R_INJECT_FULL = Pattern.compile("^`(\\$[A-Z]+|[^`]*)[0-9]*`$");
  private static final Pattern R_INJECT_PART = Pattern.compile("`([^`]+)`");
  private static final Pattern R_CMD_KEY = Pattern.compile("^`(\\$[A-Z]+)(\\d*)`$");

  /**
   * Sentinel returned from a transform/inject step to omit the current key.
   * Always compared with {@code ==} identity. See {@link #DELETE} for the
   * marker-map rationale.
   */
  public static final Map<String, Object> SKIP = makeSentinelMap("`$SKIP`");

  private static Map<String, Object> makeSentinelMap(String name) {
    Map<String, Object> m = new LinkedHashMap<>();
    m.put(name, true);
    return Collections.unmodifiableMap(m);
  }

  /**
   * Walk callback. Root key is {@code null}; otherwise key is the property
   * name (or list-index string) of {@code val} inside {@code parent}.
   * {@code path} is the dotted ancestor key chain ending in {@code key}.
   */
  @FunctionalInterface
  public interface WalkApply {
    Object apply(String key, Object val, Object parent, List<String> path);
  }

  /** Optional handler for {@link #getpath}; not JSON-serializable — use from tests/code only. */
  @FunctionalInterface
  public interface PathHandler {
    Object apply(Map<String, Object> inj, Object val, String ref, Object store);
  }

  /**
   * Inject step handler. Mirrors TS {@code Injector}.
   * The {@code inj} parameter will be tightened to {@code Injection} once the
   * {@code Injection} class lands (step 4); callers should pass the same value
   * through unchanged.
   */
  @FunctionalInterface
  public interface Injector {
    Object apply(Object inj, Object val, String ref, Object store);
  }

  /**
   * Custom modification applied during {@link #inject} / {@link #transform} / {@link #validate}.
   * Mirrors TS {@code Modify}.
   */
  @FunctionalInterface
  public interface Modify {
    void apply(Object val, Object key, Object parent, Object inj, Object store);
  }

  public static final int T_any      = (1 << 31) - 1;
  public static final int T_noval    = 1 << 30;
  public static final int T_boolean  = 1 << 29;
  public static final int T_decimal  = 1 << 28;
  public static final int T_integer  = 1 << 27;
  public static final int T_number   = 1 << 26;
  public static final int T_string   = 1 << 25;
  public static final int T_function = 1 << 24;
  public static final int T_symbol   = 1 << 23;
  public static final int T_null     = 1 << 22;
  public static final int T_list     = 1 << 14;
  public static final int T_map      = 1 << 13;
  public static final int T_instance = 1 << 12;
  public static final int T_scalar   = 1 << 7;
  public static final int T_node     = 1 << 6;

  private static final String[] TYPENAME = {
      "any", "nil", "boolean", "decimal", "integer", "number", "string",
      "function", "symbol", "null",
      "", "", "", "", "", "", "",
      "list", "map", "instance",
      "", "", "", "",
      "scalar", "node"
  };

  public interface ItemCheck {
    boolean test(List<Object> item);
  }

  public static boolean isnode(Object val) {
    return val instanceof Map || val instanceof List;
  }

  public static boolean ismap(Object val) {
    return val instanceof Map;
  }

  public static boolean islist(Object val) {
    return val instanceof List;
  }

  public static boolean iskey(Object key) {
    if (key == null || key == UNDEF) {
      return false;
    }
    if (key instanceof String s) {
      return !s.isEmpty();
    }
    return key instanceof Number;
  }

  public static String strkey(Object key) {
    if (key == null || key == UNDEF) {
      return S_MT;
    }
    int t = typify(key);
    if ((t & T_string) != 0) {
      return (String) key;
    }
    if ((t & T_number) != 0) {
      double d = ((Number) key).doubleValue();
      if (Math.floor(d) == d) {
        return Long.toString((long) d);
      }
      return Long.toString((long) Math.floor(d));
    }
    return S_MT;
  }

  public static boolean isempty(Object val) {
    if (val == null || val == UNDEF) {
      return true;
    }
    if (val instanceof String s) {
      return s.isEmpty();
    }
    if (val instanceof List<?> l) {
      return l.isEmpty();
    }
    if (val instanceof Map<?, ?> m) {
      return m.isEmpty();
    }
    return false;
  }

  public static boolean isfunc(Object val) {
    return val instanceof Function || val instanceof Supplier;
  }

  public static Object getdef(Object val, Object alt) {
    return (val == UNDEF) ? alt : val;
  }

  public static int size(Object val) {
    if (val instanceof List<?> l) {
      return l.size();
    }
    if (val instanceof Map<?, ?> m) {
      return m.size();
    }
    if (val instanceof String s) {
      return s.length();
    }
    if (val instanceof Number n) {
      return (int) Math.floor(n.doubleValue());
    }
    if (val instanceof Boolean b) {
      return b ? 1 : 0;
    }
    return 0;
  }

  public static int typify(Object value) {
    if (value == UNDEF) {
      return T_noval;
    }
    if (value == null) {
      return T_scalar | T_null;
    }
    if (value instanceof Number n) {
      double d = n.doubleValue();
      if (Double.isNaN(d)) {
        return T_noval;
      }
      if (Math.floor(d) == d) {
        return T_scalar | T_number | T_integer;
      }
      return T_scalar | T_number | T_decimal;
    }
    if (value instanceof String) {
      return T_scalar | T_string;
    }
    if (value instanceof Boolean) {
      return T_scalar | T_boolean;
    }
    if (value instanceof Function) {
      return T_scalar | T_function;
    }
    if (value instanceof List) {
      return T_node | T_list;
    }
    if (value instanceof Map) {
      return T_node | T_map;
    }
    return T_node | T_instance;
  }

  public static String typename(Object tValue) {
    if (!(tValue instanceof Number n)) {
      return "any";
    }
    return typename(n.intValue());
  }

  /**
   * TS-canonical {@code typename(t)}: human-readable name for a type bit-flag
   * returned by {@link #typify(Object)}. The flag with the highest set bit
   * (lowest leading-zero count) wins.
   */
  public static String typename(int t) {
    if (t == 0) {
      return "any";
    }
    int idx = Integer.numberOfLeadingZeros(t);
    if (idx < 0 || idx >= TYPENAME.length) {
      return "any";
    }
    String out = TYPENAME[idx];
    return out.isEmpty() ? "any" : out;
  }

  public static List<String> keysof(Object val) {
    if (!isnode(val)) {
      return new ArrayList<>();
    }
    if (val instanceof List<?> l) {
      List<String> out = new ArrayList<>(l.size());
      for (int i = 0; i < l.size(); i++) {
        out.add(Integer.toString(i));
      }
      return out;
    }
    Map<Object, Object> m = (Map<Object, Object>) val;
    List<String> out = new ArrayList<>();
    for (Object k : m.keySet()) {
      out.add(Objects.toString(k));
    }
    out.sort(Comparator.naturalOrder());
    return out;
  }

  public static boolean haskey(Object val, Object key) {
    return getprop(val, key, UNDEF) != UNDEF;
  }

  public static List<List<Object>> items(Object val) {
    List<List<Object>> out = new ArrayList<>();
    if (!isnode(val)) {
      return out;
    }
    for (String k : keysof(val)) {
      List<Object> item = new ArrayList<>(2);
      item.add(k);
      item.add(getprop(val, k, UNDEF));
      out.add(item);
    }
    return out;
  }

  public static Object getelem(Object val, Object key) {
    return getelem(val, key, UNDEF);
  }

  public static Object getelem(Object val, Object key, Object alt) {
    if (!(val instanceof List<?> list) || key == null || key == UNDEF) {
      if (alt instanceof Function<?, ?> f) {
        return ((Function<Object, Object>) f).apply(null);
      }
      return alt;
    }

    Integer idx = parseIntKey(key);
    if (idx == null || !isIntegerKeyString(key)) {
      if (alt instanceof Function<?, ?> f) {
        return ((Function<Object, Object>) f).apply(null);
      }
      return alt;
    }

    if (idx < 0) {
      idx = list.size() + idx;
    }
    if (idx < 0 || idx >= list.size()) {
      if (alt instanceof Function<?, ?> f) {
        return ((Function<Object, Object>) f).apply(null);
      }
      return alt;
    }

    Object out = list.get(idx);
    return out == UNDEF ? alt : out;
  }

  public static Object getprop(Object val, Object key) {
    return getprop(val, key, UNDEF);
  }

  public static Object getprop(Object val, Object key, Object alt) {
    if (val == null || val == UNDEF || key == null || key == UNDEF) {
      return alt;
    }

    if (val instanceof Map<?, ?> m) {
      String sk = strkey(key);
      if (m.containsKey(sk)) {
        return ((Map<Object, Object>) m).get(sk);
      }
      return alt;
    }

    if (val instanceof List<?> l) {
      Integer idx = parseIntKey(key);
      if (idx == null) {
        return alt;
      }
      if (idx < 0 || idx >= l.size()) {
        return alt;
      }
      return l.get(idx);
    }

    return alt;
  }

  public static Object setprop(Object parent, Object key, Object val) {
    if (!iskey(key)) {
      return parent;
    }

    if (parent instanceof Map<?, ?>) {
      Map<Object, Object> m = (Map<Object, Object>) parent;
      m.put(strkey(key), val);
      return parent;
    }

    if (parent instanceof List<?>) {
      List<Object> l = (List<Object>) parent;
      Integer idx = parseIntKey(key);
      if (idx == null) {
        return parent;
      }
      idx = (int) Math.floor(idx);

      if (val == null) {
        if (idx >= 0 && idx < l.size()) {
          l.remove((int) idx);
        }
        return l;
      }

      if (idx >= 0) {
        int target = Math.min(Math.max(idx, 0), l.size());
        if (target < l.size()) {
          l.set(target, val);
        } else {
          l.add(val);
        }
      } else {
        l.add(0, val);
      }
      return l;
    }

    return parent;
  }

  public static Object delprop(Object parent, Object key) {
    if (!iskey(key)) {
      return parent;
    }

    if (parent instanceof Map<?, ?> m) {
      ((Map<Object, Object>) m).remove(strkey(key));
      return parent;
    }

    if (parent instanceof List<?> l) {
      Integer idx = parseIntKey(key);
      if (idx != null && idx >= 0 && idx < l.size()) {
        ((List<Object>) l).remove((int) idx);
      }
      return parent;
    }

    return parent;
  }

  public static boolean isIntegerKeyString(Object key) {
    if (key instanceof Number) {
      return true;
    }
    if (!(key instanceof String s)) {
      return false;
    }
    return s.matches("^[-0-9]+$");
  }

  private static Integer parseIntKey(Object key) {
    if (key instanceof Number n) {
      return (int) Math.floor(n.doubleValue());
    }
    if (key instanceof String s) {
      try {
        return Integer.parseInt(s);
      } catch (Exception e) {
        return null;
      }
    }
    return null;
  }

  public static Object clone(Object val) {
    return cloneInner(val, new IdentityHashMap<>());
  }

  /**
   * Build a {@link LinkedHashMap} (JSON object) from alternating key/value pairs.
   * Mirrors TS {@code jm}. Missing trailing values become {@code null}; non-string
   * keys are coerced via {@link #stringify(Object)}.
   */
  public static Map<String, Object> jm(Object... kv) {
    Map<String, Object> out = new LinkedHashMap<>();
    int n = kv == null ? 0 : kv.length;
    for (int i = 0; i < n; i += 2) {
      Object k = kv[i];
      String sk = k instanceof String s ? s : stringify(k);
      if (sk.isEmpty() && k != null) {
        sk = "$KEY" + i;
      } else if (k == null) {
        sk = "$KEY" + i;
      }
      Object v = (i + 1) < n ? kv[i + 1] : null;
      out.put(sk, v);
    }
    return out;
  }

  /**
   * Build an {@link ArrayList} (JSON array) from positional args.
   * Mirrors TS {@code jt}.
   */
  public static List<Object> jt(Object... v) {
    int n = v == null ? 0 : v.length;
    List<Object> out = new ArrayList<>(n);
    for (int i = 0; i < n; i++) {
      out.add(v[i]);
    }
    return out;
  }

  private static Object cloneInner(Object val, IdentityHashMap<Object, Object> seen) {
    if (val == null || val == UNDEF) {
      return val;
    }
    // Preserve sentinel identity. Without this, a cloned spec containing SKIP
    // or DELETE produces a structurally-identical map that fails `==` checks
    // downstream and breaks transform/inject control flow.
    if (val == SKIP || val == DELETE) {
      return val;
    }
    if (val instanceof String || val instanceof Number || val instanceof Boolean || val instanceof Function) {
      return val;
    }
    if (seen.containsKey(val)) {
      return seen.get(val);
    }
    if (val instanceof List<?> l) {
      List<Object> out = new ArrayList<>(l.size());
      seen.put(val, out);
      for (Object n : l) {
        out.add(cloneInner(n, seen));
      }
      return out;
    }
    if (val instanceof Map<?, ?> m) {
      Map<String, Object> out = new LinkedHashMap<>();
      seen.put(val, out);
      for (Map.Entry<?, ?> e : m.entrySet()) {
        out.put(Objects.toString(e.getKey()), cloneInner(e.getValue(), seen));
      }
      return out;
    }
    return val;
  }

  public static List<Object> flatten(Object val) {
    return flatten(val, 1);
  }

  public static List<Object> flatten(Object val, Integer depth) {
    if (!(val instanceof List<?> l)) {
      return Collections.emptyList();
    }
    int d = depth == null ? 1 : depth;
    List<Object> out = new ArrayList<>();
    flattenInto(l, d, out);
    return out;
  }

  private static void flattenInto(List<?> in, int depth, List<Object> out) {
    for (Object n : in) {
      if (depth > 0 && n instanceof List<?> ln) {
        flattenInto(ln, depth - 1, out);
      } else {
        out.add(n);
      }
    }
  }

  public static List<Object> filter(Object val, ItemCheck check) {
    List<Object> out = new ArrayList<>();
    for (List<Object> item : items(val)) {
      if (check.test(item)) {
        out.add(item.get(1));
      }
    }
    return out;
  }

  public static String escre(Object s) {
    String in = (s == null || s == UNDEF) ? "" : Objects.toString(s);
    return in.replaceAll("([\\\\.\\[\\]{}()*+?^$|])", "\\\\$1");
  }

  public static String escurl(Object s) {
    if (s == null || s == UNDEF) {
      return "";
    }
    return URLEncoder.encode(Objects.toString(s), StandardCharsets.UTF_8)
        .replace("+", "%20");
  }

  public static String join(Object arr, Object sep, Object url) {
    if (!(arr instanceof List<?> l)) {
      return "";
    }
    String sepDef = (sep == null || sep == UNDEF) ? "," : Objects.toString(sep);
    boolean urlMode = Boolean.TRUE.equals(url);

    List<String> parts = new ArrayList<>();
    for (Object n : l) {
      if (n instanceof String s && !s.isEmpty()) {
        parts.add(s);
      }
    }

    String sepre = escre(sepDef);
    List<String> clean = new ArrayList<>();
    for (int i = 0; i < parts.size(); i++) {
      String s = parts.get(i);
      if (sepDef.length() == 1 && !sepDef.isEmpty()) {
        if (urlMode && i == 0) {
          s = s.replaceAll(sepre + "+$", "");
        }
        if (i > 0) {
          s = s.replaceAll("^" + sepre + "+", "");
        }
        if (i < parts.size() - 1 || !urlMode) {
          s = s.replaceAll(sepre + "+$", "");
        }
      }
      clean.add(s);
    }

    String out = String.join(sepDef, clean);
    if (!urlMode && sepDef.length() == 1 && !sepDef.isEmpty()) {
      String cc = Pattern.quote(sepDef);
      out = out.replaceAll("([^" + cc + "])" + cc + "+([^" + cc + "])", "$1" + sepDef + "$2");
    }
    return out;
  }

  public static Object slice(Object val, Object startObj, Object endObj) {
    Integer start = (startObj instanceof Number) ? (int) Math.floor(((Number) startObj).doubleValue()) : null;
    Integer end = (endObj instanceof Number) ? (int) Math.floor(((Number) endObj).doubleValue()) : null;

    if (val instanceof Number n) {
      int min = start == null ? Integer.MIN_VALUE : start;
      int max = (end == null ? Integer.MAX_VALUE : end - 1);
      double d = n.doubleValue();
      return Math.min(Math.max(d, min), max);
    }

    int vlen = size(val);
    if (end != null && start == null) {
      start = 0;
    }

    if (start != null) {
      if (start < 0) {
        end = vlen + start;
        if (end < 0) {
          end = 0;
        }
        start = 0;
      } else if (end != null) {
        if (end < 0) {
          end = vlen + end;
          if (end < 0) {
            end = 0;
          }
        } else if (vlen < end) {
          end = vlen;
        }
      } else {
        end = vlen;
      }

      if (vlen < start) {
        start = vlen;
      }

      if (-1 < start && start <= end && end <= vlen) {
        if (val instanceof List<?> l) {
          return new ArrayList<>(l.subList(start, end));
        }
        if (val instanceof String s) {
          return s.substring(start, end);
        }
      } else {
        if (val instanceof List<?>) {
          return new ArrayList<>();
        }
        if (val instanceof String) {
          return "";
        }
      }
    }

    return val;
  }

  public static String pad(Object val, Object paddingObj, Object padcharObj) {
    String s = (val instanceof String) ? (String) val : stringify(val);
    int padding = (paddingObj instanceof Number) ? (int) Math.floor(((Number) paddingObj).doubleValue()) : 44;
    String pc = (padcharObj == null || padcharObj == UNDEF) ? " " : (Objects.toString(padcharObj) + " ").substring(0, 1);
    if (padding >= 0) {
      return s + pc.repeat(Math.max(0, padding - s.length()));
    }
    return pc.repeat(Math.max(0, -padding - s.length())) + s;
  }

  public static String stringify(Object val) {
    return stringify(val, null);
  }

  public static String stringify(Object val, Integer maxlen) {
    String valstr = "";
    if (val == UNDEF) {
      return "";
    }
    if (val instanceof String s) {
      valstr = s;
    } else {
      try {
        valstr = stringifyStable(val, new IdentityHashMap<>());
      } catch (Exception e) {
        valstr = "__STRINGIFY_FAILED__";
      }
    }
    if (maxlen != null && maxlen >= 0 && valstr.length() > maxlen) {
      return valstr.substring(0, Math.max(0, maxlen - 3)) + "...";
    }
    return valstr;
  }

  private static String stringifyStable(Object val, IdentityHashMap<Object, Boolean> seen) {
    if (val == null) return "null";
    if (val instanceof String s) return s;
    if (val instanceof Number n) return numstr(n);
    if (val instanceof Boolean) return Objects.toString(val);
    if (val instanceof Function) return Objects.toString(val);

    if (seen.containsKey(val)) {
      throw new IllegalStateException("cycle");
    }
    seen.put(val, true);
    if (val instanceof List<?> l) {
      List<String> parts = new ArrayList<>();
      for (Object n : l) {
        parts.add(stringifyStable(n, seen));
      }
      seen.remove(val);
      return "[" + String.join(",", parts) + "]";
    }
    if (val instanceof Map<?, ?> m) {
      List<String> keys = new ArrayList<>();
      for (Object k : m.keySet()) keys.add(Objects.toString(k));
      keys.sort(String::compareTo);
      List<String> parts = new ArrayList<>();
      for (String k : keys) {
        parts.add(k + ":" + stringifyStable(((Map<Object, Object>) m).get(k), seen));
      }
      seen.remove(val);
      return "{" + String.join(",", parts) + "}";
    }
    seen.remove(val);
    return Objects.toString(val);
  }

  public static String jsonify(Object val) {
    return jsonify(val, null);
  }

  public static String jsonify(Object val, Object flags) {
    if (val == UNDEF) {
      return "null";
    }
    int indent = 2;
    int offset = 0;
    if (flags instanceof Map<?, ?> fm) {
      Object iv = ((Map<Object, Object>) fm).get("indent");
      Object ov = ((Map<Object, Object>) fm).get("offset");
      if (iv instanceof Number n) indent = n.intValue();
      if (ov instanceof Number n) offset = n.intValue();
    }
    try {
      Object jsonSafe = toJsonSafe(val, new IdentityHashMap<>());
      Gson gson = indent > 0
          ? new GsonBuilder().setPrettyPrinting().create()
          : new GsonBuilder().create();
      String out = gson.toJson(jsonSafe);
      if (indent != 2 && indent > 0) {
        out = rewriteIndent(out, indent);
      }
      if (offset > 0 && out.contains("\n")) {
        String[] lines = out.split("\n", -1);
        StringBuilder sb = new StringBuilder(lines[0]);
        String pad = " ".repeat(offset);
        for (int i = 1; i < lines.length; i++) {
          sb.append("\n").append(pad).append(lines[i]);
        }
        out = sb.toString();
      }
      return out == null ? "null" : out;
    } catch (Exception e) {
      return "__JSONIFY_FAILED__";
    }
  }

  private static String rewriteIndent(String pretty, int indent) {
    String[] lines = pretty.split("\n", -1);
    StringBuilder sb = new StringBuilder();
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];
      int spaces = 0;
      while (spaces < line.length() && line.charAt(spaces) == ' ') spaces++;
      int level = spaces / 2;
      sb.append(" ".repeat(level * indent)).append(line.substring(spaces));
      if (i < lines.length - 1) sb.append('\n');
    }
    return sb.toString();
  }

  private static Object toJsonSafe(Object val, IdentityHashMap<Object, Boolean> seen) {
    if (val == null || val == UNDEF) return null;
    if (val instanceof String || val instanceof Boolean) return val;
    if (val instanceof Number n) return jsonNumber(n);
    if (val instanceof Function) return null;
    if (seen.containsKey(val)) return null;
    seen.put(val, true);
    if (val instanceof List<?> l) {
      List<Object> out = new ArrayList<>();
      for (Object n : l) out.add(toJsonSafe(n, seen));
      seen.remove(val);
      return out;
    }
    if (val instanceof Map<?, ?> m) {
      Map<String, Object> out = new LinkedHashMap<>();
      for (Map.Entry<?, ?> e : m.entrySet()) {
        out.put(Objects.toString(e.getKey()), toJsonSafe(e.getValue(), seen));
      }
      seen.remove(val);
      return out;
    }
    seen.remove(val);
    return null;
  }

  private static String numstr(Number n) {
    double d = n.doubleValue();
    if (Double.isFinite(d) && Math.floor(d) == d) {
      return Long.toString((long) d);
    }
    return n.toString().toLowerCase(Locale.ROOT);
  }

  private static Number jsonNumber(Number n) {
    double d = n.doubleValue();
    if (Double.isFinite(d) && Math.floor(d) == d) {
      return (long) d;
    }
    return d;
  }

  public static String pathify(Object val) {
    return pathify(val, null, null);
  }

  public static String pathify(Object val, Object startIn) {
    return pathify(val, startIn, null);
  }

  public static String pathify(Object val, Object startIn, Object endIn) {
    Integer start = (startIn instanceof Number) ? Math.max(0, ((Number) startIn).intValue()) : 0;
    Integer end = (endIn instanceof Number) ? Math.max(0, ((Number) endIn).intValue()) : 0;
    List<Object> path;
    if (val instanceof List<?> l) {
      path = new ArrayList<>(l);
    } else if (val instanceof String || val instanceof Number) {
      path = new ArrayList<>();
      path.add(val);
    } else {
      path = null;
    }

    if (path != null) {
      Object sp = slice(path, start, path.size() - end);
      List<Object> use = (sp instanceof List<?>) ? (List<Object>) sp : new ArrayList<>();
      if (use.isEmpty()) return "<root>";
      List<String> parts = new ArrayList<>();
      for (Object p : use) {
        if (iskey(p)) {
          if (p instanceof Number n) {
            parts.add(Long.toString((long) Math.floor(n.doubleValue())));
          } else {
            parts.add(Objects.toString(p).replace(".", ""));
          }
        }
      }
      return String.join(".", parts);
    }
    return "<unknown-path" + (val == UNDEF ? "" : ":" + stringify(val, 47)) + ">";
  }

  public static Object setpath(Object store, Object path, Object val) {
    List<Object> parts;
    if (path instanceof List<?> l) {
      parts = new ArrayList<>(l);
    } else if (path instanceof String s) {
      parts = new ArrayList<>(List.of(s.split("\\.")));
    } else if (path instanceof Number) {
      parts = new ArrayList<>(List.of(path));
    } else {
      return UNDEF;
    }
    if (parts.isEmpty()) return UNDEF;
    Object parent = store;
    for (int i = 0; i < parts.size() - 1; i++) {
      Object key = parts.get(i);
      Object next = getprop(parent, key, UNDEF);
      if (!isnode(next)) {
        Object nk = parts.get(i + 1);
        next = (nk instanceof Number) ? new ArrayList<>() : new LinkedHashMap<String, Object>();
        setprop(parent, key, next);
      }
      parent = next;
    }
    Object last = parts.get(parts.size() - 1);
    if (val == DELETE) {
      delprop(parent, last);
    } else {
      setprop(parent, last, val);
    }
    return parent;
  }

  public static Object walk(Object val, WalkApply apply) {
    return walk(val, apply, null, 32);
  }

  public static Object walk(Object val, WalkApply before, WalkApply after) {
    return walk(val, before, after, 32);
  }

  public static Object walk(Object val, WalkApply before, WalkApply after, int maxdepth) {
    return walkDescend(val, before, after, maxdepth, null, null, new ArrayList<>());
  }

  private static Object walkDescend(
      Object val,
      WalkApply before,
      WalkApply after,
      int maxdepth,
      String key,
      Object parent,
      List<String> path) {
    Object out = val;

    if (before != null) {
      out = before.apply(key, out, parent, path);
    }

    int plen = path.size();
    if (maxdepth == 0 || (maxdepth > 0 && maxdepth <= plen)) {
      return out;
    }

    if (isnode(out)) {
      for (List<Object> item : items(out)) {
        String ckey = (String) item.get(0);
        Object child = item.get(1);
        List<String> newPath = new ArrayList<>(path);
        newPath.add(ckey);
        Object newChild = walkDescend(child, before, after, maxdepth, ckey, out, newPath);
        out = setprop(out, ckey, newChild);
      }
      if (parent != null && key != null) {
        setprop(parent, key, out);
      }
    }

    if (after != null) {
      out = after.apply(key, out, parent, path);
    }

    return out;
  }

  public static Object merge(Object val) {
    return merge(val, 32);
  }

  public static Object merge(Object val, int maxdepthIn) {
    int md = maxdepthIn < 0 ? 0 : maxdepthIn;

    if (!(val instanceof List<?> list)) {
      return val;
    }
    if (list.isEmpty()) {
      return null;
    }
    if (list.size() == 1) {
      return list.get(0);
    }

    Object out = getprop(list, 0, new LinkedHashMap<String, Object>());

    for (int oI = 1; oI < list.size(); oI++) {
      Object obj = list.get(oI);

      if (!isnode(obj)) {
        out = obj;
      } else {
        Object[] cur = new Object[33];
        Object[] dst = new Object[33];
        cur[0] = out;
        dst[0] = out;

        WalkApply before = (key, v, _parent, path) -> {
          int pI = path.size();
          if (md <= pI) {
            if (key != null) {
              cur[pI - 1] = setprop(cur[pI - 1], key, v);
            }
          } else if (!isnode(v)) {
            cur[pI] = v;
          } else {
            if (0 < pI && key != null) {
              dst[pI] = getprop(dst[pI - 1], key, UNDEF);
              if (dst[pI] == UNDEF) {
                dst[pI] = null;
              }
            }
            Object tval = dst[pI];

            if (tval == null && (typify(v) & T_instance) == 0) {
              cur[pI] = islist(v) ? new ArrayList<>() : new LinkedHashMap<String, Object>();
            } else if (typify(v) == typify(tval)) {
              cur[pI] = tval;
            } else {
              cur[pI] = v;
              return null;
            }
          }
          return v;
        };

        WalkApply after = (key, _val, _parent, path) -> {
          int cI = path.size();
          if (key == null || cI <= 0) {
            return cur[0];
          }
          Object value = cur[cI];
          cur[cI - 1] = setprop(cur[cI - 1], key, value);
          return value;
        };

        walk(obj, before, after, md);
        out = cur[0];
      }
    }

    if (md == 0) {
      out = getelem(list, -1);
      if (out instanceof List) {
        out = new ArrayList<>();
      } else if (out instanceof Map) {
        out = new LinkedHashMap<String, Object>();
      }
    }

    return out;
  }

  public static Object getpath(Object store, Object path) {
    return getpath(store, path, null);
  }

  public static Object getpath(Object store, Object path, Map<String, Object> inj) {
    List<String> parts = pathParts(path);
    Object val = getpathInner(store, path, parts, inj);
    if (inj != null && inj.get("handler") instanceof PathHandler h) {
      String ref = pathifyForHandler(path);
      val = h.apply(inj, val, ref, store);
    }
    return val;
  }

  private static String pathifyForHandler(Object path) {
    if (path == null) {
      return pathify(UNDEF);
    }
    if (path instanceof String) {
      return pathify(path);
    }
    if (path instanceof List<?>) {
      return pathify(path);
    }
    if (path instanceof Number n) {
      return pathify(n);
    }
    return pathify(path);
  }

  private static List<String> pathParts(Object path) {
    if (path instanceof String s) {
      if (s.isEmpty()) {
        return new ArrayList<>(List.of(S_MT));
      }
      return new ArrayList<>(List.of(s.split("\\.", -1)));
    }
    if (path instanceof List<?> l) {
      List<String> out = new ArrayList<>();
      for (Object x : l) {
        if (x instanceof String) {
          out.add((String) x);
        } else if (x instanceof Number n) {
          out.add(strkey(n));
        } else {
          out.add(strkey(x));
        }
      }
      return out;
    }
    return null;
  }

  private static Object getpathInner(Object store, Object pathOrig, List<String> parts, Map<String, Object> inj) {
    if (parts == null) {
      return null;
    }

    Object base = inj != null ? inj.get("base") : null;
    Object src = getprop(store, base, store);
    Object dparent = inj != null ? inj.get("dparent") : null;
    @SuppressWarnings("unchecked")
    List<String> dpath = inj != null && inj.get("dpath") instanceof List
        ? (List<String>) inj.get("dpath")
        : inj != null && inj.get("dpath") instanceof String s
            ? new ArrayList<>(List.of(s.split("\\.", -1)))
            : null;

    int numparts = parts.size();
    Object val = store;

    if (pathOrig == null || store == null || (numparts == 1 && S_MT.equals(parts.get(0)))) {
      val = src;
    } else if (numparts > 0) {

      if (numparts == 1) {
        val = getprop(store, parts.get(0));
      }

      if (!isfunc(val)) {
        val = src;

        Matcher m0 = R_META_PATH.matcher(parts.get(0));
        if (m0.matches() && inj != null && inj.get("meta") instanceof Map<?, ?> meta) {
          val = getprop(meta, m0.group(1));
          parts.set(0, m0.group(3));
        }

        for (int pI = 0; val != null && pI < numparts; pI++) {
          String part = parts.get(pI);

          if (inj != null && S_DKEY.equals(part)) {
            part = Objects.toString(inj.get("key"), "");
          } else if (inj != null && part.startsWith("$GET:")) {
            String subpath = part.substring(5, part.length() - 1);
            Object result = getpath(src, subpath);
            part = stringify(result);
          } else if (inj != null && part.startsWith("$REF:")) {
            String subpath = part.substring(5, part.length() - 1);
            Object specVal = getprop(store, S_DSPEC);
            if (specVal != null) {
              Object result = getpath(specVal, subpath);
              part = stringify(result);
            }
          } else if (inj != null && part.startsWith("$META:")) {
            String subpath = part.substring(6, part.length() - 1);
            Object meta = inj.get("meta");
            Object result = getpath(meta, subpath);
            part = stringify(result);
          }

          part = part.replace("$$", "$");

          if (S_MT.equals(part)) {
            int ascends = 0;
            while (1 + pI < numparts && S_MT.equals(parts.get(1 + pI))) {
              ascends++;
              pI++;
            }

            if (inj != null && ascends > 0) {
              if (pI == numparts - 1) {
                ascends--;
              }

              if (ascends == 0) {
                val = dparent;
              } else if (dpath != null) {
                int cutLen = dpath.size() - ascends;
                if (cutLen < 0) {
                  cutLen = 0;
                }
                List<String> fullpath = new ArrayList<>();
                for (int i = 0; i < cutLen; i++) {
                  fullpath.add(dpath.get(i));
                }
                if (pI + 1 < numparts) {
                  for (int j = pI + 1; j < numparts; j++) {
                    fullpath.add(parts.get(j));
                  }
                }
                if (ascends <= size(dpath)) {
                  val = getpath(store, fullpath);
                } else {
                  val = null;
                }
                break;
              }
            } else {
              val = dparent;
            }
          } else {
            val = getprop(val, part);
          }
        }
      }
    }

    return val;
  }

  public static Object inject(Object val, Object store) {
    return inject(val, store, null);
  }

  public static Object inject(Object val, Object store, Map<String, Object> inj) {
    if (val == UNDEF || val == null) {
      return null;
    }

    if (val instanceof Map<?, ?> m) {
      Map<String, Object> out = new LinkedHashMap<>();
      for (Map.Entry<?, ?> e : m.entrySet()) {
        String key = Objects.toString(e.getKey(), "");
        out.put(key, inject(e.getValue(), store, inj));
      }
      return out;
    }

    if (val instanceof List<?> l) {
      List<Object> out = new ArrayList<>();
      for (Object child : l) {
        out.add(inject(child, store, inj));
      }
      return out;
    }

    if (val instanceof String s) {
      return injectString(s, store, inj);
    }

    return val;
  }

  private static Object injectString(String val, Object store, Map<String, Object> inj) {
    if (val.isEmpty()) {
      return S_MT;
    }

    Matcher full = R_INJECT_FULL.matcher(val);
    if (full.matches()) {
      String pathref = unescapeInjectRef(full.group(1));
      return getpath(store, pathref, inj);
    }

    Matcher matcher = R_INJECT_PART.matcher(val);
    StringBuilder out = new StringBuilder();
    int cursor = 0;
    while (matcher.find()) {
      out.append(val, cursor, matcher.start());
      String ref = unescapeInjectRef(matcher.group(1));
      Object found = getpath(store, ref, inj);
      out.append(injectPartialText(found));
      cursor = matcher.end();
    }
    out.append(val.substring(cursor));
    return out.toString();
  }

  private static String unescapeInjectRef(String ref) {
    if (ref != null && ref.length() > 3) {
      return ref.replace("$BT", "`").replace("$DS", "$");
    }
    return ref;
  }

  private static String injectPartialText(Object found) {
    if (found == UNDEF) {
      return S_MT;
    }
    if (found == null) {
      return "null";
    }
    if (found instanceof String s) {
      return s;
    }
    if (found instanceof Map<?, ?> || found instanceof List<?>) {
      Object safe = toJsonSafe(found, new IdentityHashMap<>());
      return new Gson().toJson(safe);
    }
    return stringify(found);
  }

  public static Object transform(Object data, Object spec) {
    return transform(data, spec, null);
  }

  public static Object transform(Object data, Object spec, Map<String, Object> options) {
    Object useData = data;
    TransformModify modify = null;
    Map<String, Object> handlers = new LinkedHashMap<>();

    if (options != null) {
      Object m = options.get("modify");
      if (m instanceof TransformModify tm) {
        modify = tm;
      }
      Object extra = options.get("extra");
      if (extra instanceof Map<?, ?> exm) {
        Map<String, Object> extraData = new LinkedHashMap<>();
        for (Map.Entry<?, ?> e : exm.entrySet()) {
          String k = Objects.toString(e.getKey(), "");
          if (k.startsWith("$")) {
            handlers.put(k, e.getValue());
          } else {
            extraData.put(k, e.getValue());
          }
        }
        if (useData instanceof Map<?, ?>) {
          useData = merge(List.of(extraData, useData), 1);
        } else if (!extraData.isEmpty() && useData == null) {
          useData = extraData;
        }
      }
    }

    TransformOptions opts = new TransformOptions(modify, handlers);
    return transformInner(useData, spec, useData, useData, new ArrayList<>(), null, spec, new HashSet<>(), opts);
  }

  private static Object transformInner(
      Object data,
      Object spec,
      Object currentData,
      Object dparent,
      List<String> dpath,
      Object keySpec,
      Object rootSpec,
      Set<String> refGuard,
      TransformOptions opts) {
    if (spec == UNDEF || spec == null) {
      return null;
    }

    if (spec instanceof String s) {
      return transformString(data, s, dparent, dpath, keySpec, opts);
    }

    if (spec instanceof Map<?, ?> sm) {
      Map<String, Object> out = new LinkedHashMap<>();
      List<Map.Entry<?, ?>> normalEntries = new ArrayList<>();
      List<MergeCmd> mergeCmds = new ArrayList<>();
      List<Object> packCmds = new ArrayList<>();
      Object localKeySpec = keySpec;
      for (Map.Entry<?, ?> e : sm.entrySet()) {
        String key = Objects.toString(e.getKey(), "");
        Matcher cmd = R_CMD_KEY.matcher(key);
        if (cmd.matches()) {
          String cmdName = cmd.group(1);
          if ("$MERGE".equals(cmdName)) {
            String suffix = cmd.group(2);
            int order = suffix == null || suffix.isEmpty() ? 0 : Integer.parseInt(suffix);
            mergeCmds.add(new MergeCmd(order, e.getValue()));
          } else if ("$PACK".equals(cmdName)) {
            packCmds.add(e.getValue());
          } else if ("$KEY".equals(cmdName)) {
            Object ks = transformInner(data, e.getValue(), currentData, dparent, dpath, keySpec, rootSpec, refGuard, opts);
            if (ks != SKIP && ks != UNDEF && ks != null) {
              localKeySpec = ks;
            }
          }
          continue;
        }
        normalEntries.add(e);
      }

      mergeCmds.sort((a, b) -> Integer.compare(b.order, a.order));
      for (MergeCmd mc : mergeCmds) {
        Object resolvedArg = transformInner(data, mc.value, currentData, dparent, dpath, localKeySpec, rootSpec, refGuard, opts);
        out = applyMergeCommand(out, resolvedArg);
      }
      for (Object packArg : packCmds) {
        Map<String, Object> packed = applyPackCommand(data, packArg, localKeySpec, rootSpec, refGuard, opts);
        out.putAll(packed);
      }

      for (Map.Entry<?, ?> e : normalEntries) {
        String key = Objects.toString(e.getKey(), "");
        Object childData = getprop(currentData, key, null);
        List<String> childPath = new ArrayList<>(dpath);
        childPath.add(key);
        Object childDparent = currentData != null ? currentData : dparent;
        Object child = transformInner(data, e.getValue(), childData, childDparent, childPath, localKeySpec, rootSpec, refGuard, opts);
        if (child != SKIP) {
          out.put(key, child);
          if (opts != null && opts.modify != null) {
            opts.modify.apply(out.get(key), key, out);
          }
        }
      }
      return out;
    }

    if (spec instanceof List<?> sl) {
      String eachCmd = extractFullCommand(getelem(sl, 0));
      if ("$FORMAT".equals(eachCmd) && 3 <= sl.size()) {
        Object nameObj = transformInner(data, clone(sl.get(1)), currentData, dparent, dpath, keySpec, rootSpec, refGuard, opts);
        Object child = transformInner(data, clone(sl.get(2)), currentData, dparent, dpath, keySpec, rootSpec, refGuard, opts);
        return applyFormatCommand(nameObj, child);
      }
      if ("$APPLY".equals(eachCmd) && 3 <= sl.size()) {
        Object fnObj = transformInner(data, clone(sl.get(1)), currentData, dparent, dpath, keySpec, rootSpec, refGuard, opts);
        Object child = transformInner(data, clone(sl.get(2)), currentData, dparent, dpath, keySpec, rootSpec, refGuard, opts);
        if (fnObj instanceof Function<?, ?> fn) {
          return ((Function<Object, Object>) fn).apply(child);
        }
        return SKIP;
      }
      if ("$REF".equals(eachCmd) && 2 <= sl.size()) {
        Object pathObj = sl.get(1);
        String refPath = pathObj == null ? "" : Objects.toString(pathObj, "");
        if (currentData == null && shouldSkipRefOnMissingData(refPath, dpath)) {
          return SKIP;
        }
        String guardKey = refPath + "#" + System.identityHashCode(currentData);
        if (refGuard.contains(guardKey)) {
          return SKIP;
        }
        Object refSpec = getpath(rootSpec, refPath);
        if (refSpec == null || refSpec == UNDEF) {
          return SKIP;
        }
        refGuard.add(guardKey);
        Object out = transformInner(data, clone(refSpec), currentData, dparent, dpath, keySpec, rootSpec, refGuard, opts);
        refGuard.remove(guardKey);
        if (currentData == null && out instanceof Map<?, ?> m && m.isEmpty()) {
          return SKIP;
        }
        return out;
      }
      if ("$EACH".equals(eachCmd) && 3 <= sl.size()) {
        Object srcPathObj = sl.get(1);
        Object template = sl.get(2);
        String srcPath = srcPathObj == null ? "" : Objects.toString(srcPathObj, "");
        Object src = srcPath.isEmpty() ? data : ".".equals(srcPath) ? currentData : getpath(data, srcPath);
        List<String> srcParts = srcPath.isEmpty() ? new ArrayList<>() : new ArrayList<>(List.of(srcPath.split("\\.", -1)));
        List<Object> out = new ArrayList<>();
        if (src instanceof List<?> srcList) {
          for (int i = 0; i < srcList.size(); i++) {
            Object item = srcList.get(i);
            List<String> itemPath = new ArrayList<>(srcParts);
            itemPath.add(strkey(i));
            Object mapped = transformInner(data, clone(template), item, item, itemPath, keySpec, rootSpec, refGuard, opts);
            if (mapped != SKIP) {
              out.add(mapped);
            }
          }
        } else if (src instanceof Map<?, ?> srcMap) {
          for (Map.Entry<?, ?> entry : srcMap.entrySet()) {
            String k = Objects.toString(entry.getKey(), "");
            Object item = entry.getValue();
            List<String> itemPath = new ArrayList<>(srcParts);
            itemPath.add(k);
            Object mapped = transformInner(data, clone(template), item, item, itemPath, keySpec, rootSpec, refGuard, opts);
            if (mapped != SKIP) {
              out.add(mapped);
            }
          }
        }
        return out;
      }

      List<Object> out = new ArrayList<>();
      for (int i = 0; i < sl.size(); i++) {
        Object childData = getprop(currentData, i, null);
        List<String> childPath = new ArrayList<>(dpath);
        childPath.add(strkey(i));
        Object childDparent = currentData != null ? currentData : dparent;
        Object child = transformInner(data, sl.get(i), childData, childDparent, childPath, keySpec, rootSpec, refGuard, opts);
        if (child != SKIP) {
          out.add(child);
          if (opts != null && opts.modify != null) {
            opts.modify.apply(out.get(out.size() - 1), strkey(out.size() - 1), out);
          }
        }
      }
      return out;
    }

    return clone(spec);
  }

  private static boolean shouldSkipRefOnMissingData(String refPath, List<String> dpath) {
    if (refPath == null || refPath.isEmpty() || dpath == null || dpath.isEmpty()) {
      return false;
    }
    List<String> parts = new ArrayList<>(List.of(refPath.split("\\.", -1)));
    if (parts.size() > dpath.size()) {
      return false;
    }
    for (int i = 0; i < parts.size(); i++) {
      if (!Objects.equals(parts.get(i), dpath.get(i))) {
        return false;
      }
    }
    return true;
  }

  private static String extractFullCommand(Object val) {
    if (!(val instanceof String s)) {
      return null;
    }
    Matcher full = R_INJECT_FULL.matcher(s);
    if (!full.matches()) {
      return null;
    }
    String ref = unescapeInjectRef(full.group(1));
    if (ref != null && ref.startsWith("$")) {
      return ref;
    }
    return null;
  }

  private static Object applyFormatCommand(Object nameObj, Object resolved) {
    if (!(nameObj instanceof String name)) {
      return SKIP;
    }
    return switch (name) {
      case "identity" -> resolved;
      case "concat" -> formatConcat(resolved);
      case "upper" -> formatDeep(resolved, "upper");
      case "lower" -> formatDeep(resolved, "lower");
      case "string" -> formatDeep(resolved, "string");
      case "number" -> formatDeep(resolved, "number");
      case "integer" -> formatDeep(resolved, "integer");
      default -> SKIP;
    };
  }

  private static Object formatConcat(Object val) {
    if (!(val instanceof List<?> list)) {
      return val;
    }
    StringBuilder out = new StringBuilder();
    for (Object item : list) {
      if (isnode(item)) {
        continue;
      }
      out.append(formatStringScalar(item));
    }
    return out.toString();
  }

  private static Object formatDeep(Object val, String mode) {
    if (val instanceof List<?> list) {
      List<Object> out = new ArrayList<>();
      for (Object item : list) {
        out.add(formatDeep(item, mode));
      }
      return out;
    }
    if (val instanceof Map<?, ?> map) {
      Map<String, Object> out = new LinkedHashMap<>();
      for (Map.Entry<?, ?> e : map.entrySet()) {
        out.put(Objects.toString(e.getKey(), ""), formatDeep(e.getValue(), mode));
      }
      return out;
    }
    return formatScalar(val, mode);
  }

  private static Object formatScalar(Object val, String mode) {
    String sv = formatStringScalar(val);
    return switch (mode) {
      case "upper" -> sv.toUpperCase(Locale.ROOT);
      case "lower" -> sv.toLowerCase(Locale.ROOT);
      case "string" -> sv;
      case "number" -> formatNumberScalar(val, false);
      case "integer" -> formatNumberScalar(val, true);
      default -> val;
    };
  }

  private static String formatStringScalar(Object val) {
    if (val == null || val == UNDEF) {
      return "null";
    }
    if (val instanceof String s) {
      return s;
    }
    if (val instanceof Number || val instanceof Boolean) {
      return stringify(val);
    }
    return Objects.toString(val);
  }

  private static Object formatNumberScalar(Object val, boolean integerOnly) {
    if (val instanceof Number n) {
      double d = n.doubleValue();
      if (integerOnly) {
        return (long) d;
      }
      if (Math.floor(d) == d) {
        return (long) d;
      }
      return d;
    }
    if (val instanceof String s) {
      try {
        double d = Double.parseDouble(s);
        if (integerOnly || Math.floor(d) == d) {
          return (long) d;
        }
        return d;
      } catch (Exception ignored) {
        return 0L;
      }
    }
    return 0L;
  }

  private static Map<String, Object> applyMergeCommand(Map<String, Object> current, Object resolvedArg) {
    List<Object> mergeArgs = new ArrayList<>();
    mergeArgs.add(current);
    if (resolvedArg instanceof List<?> l) {
      mergeArgs.addAll(l);
    } else if (resolvedArg != null && resolvedArg != SKIP && resolvedArg != UNDEF) {
      mergeArgs.add(resolvedArg);
    }

    Object merged = merge(mergeArgs);
    if (merged instanceof Map<?, ?> map) {
      Map<String, Object> out = new LinkedHashMap<>();
      for (Map.Entry<?, ?> e : map.entrySet()) {
        out.put(Objects.toString(e.getKey()), e.getValue());
      }
      return out;
    }
    return current;
  }

  private static Map<String, Object> applyPackCommand(
      Object data,
      Object packArg,
      Object inheritedKeySpec,
      Object rootSpec,
      Set<String> refGuard,
      TransformOptions opts) {
    if (!(packArg instanceof List<?> args) || args.size() < 2) {
      return new LinkedHashMap<>();
    }
    String srcPath = Objects.toString(args.get(0), "");
    Object childSpecRaw = args.get(1);
    Object src = srcPath.isEmpty() ? data : getpath(data, srcPath);
    List<String> srcParts = srcPath.isEmpty() ? new ArrayList<>() : new ArrayList<>(List.of(srcPath.split("\\.", -1)));

    Map<String, Object> childMap = childSpecRaw instanceof Map<?, ?> ? toStringMap((Map<?, ?>) childSpecRaw) : null;
    Object packKeySpec = null;
    Object valueSpec = null;
    Object baseTemplate = childSpecRaw;

    if (childMap != null) {
      Map<String, Object> template = new LinkedHashMap<>(childMap);
      for (Map.Entry<String, Object> e : childMap.entrySet()) {
        Matcher m = R_CMD_KEY.matcher(e.getKey());
        if (!m.matches()) {
          continue;
        }
        if ("$KEY".equals(m.group(1))) {
          packKeySpec = e.getValue();
          template.remove(e.getKey());
        } else if ("$VAL".equals(m.group(1))) {
          valueSpec = e.getValue();
          template.remove(e.getKey());
        }
      }
      baseTemplate = template;
    }

    Map<String, Object> out = new LinkedHashMap<>();
    if (src instanceof List<?> list) {
      for (int i = 0; i < list.size(); i++) {
        Object item = list.get(i);
        List<String> itemPath = new ArrayList<>(srcParts);
        itemPath.add(strkey(i));
        putPackedItem(out, data, item, itemPath, packKeySpec, inheritedKeySpec, valueSpec, baseTemplate, strkey(i), rootSpec, refGuard, opts);
      }
    } else if (src instanceof Map<?, ?> map) {
      for (Map.Entry<?, ?> e : map.entrySet()) {
        String k = Objects.toString(e.getKey(), "");
        Object item = e.getValue();
        List<String> itemPath = new ArrayList<>(srcParts);
        itemPath.add(k);
        putPackedItem(out, data, item, itemPath, packKeySpec, inheritedKeySpec, valueSpec, baseTemplate, k, rootSpec, refGuard, opts);
      }
    }
    return out;
  }

  private static void putPackedItem(
      Map<String, Object> out,
      Object data,
      Object item,
      List<String> itemPath,
      Object packKeySpec,
      Object inheritedKeySpec,
      Object valueSpec,
      Object baseTemplate,
      String fallbackKey,
      Object rootSpec,
      Set<String> refGuard,
      TransformOptions opts) {
    Object kObj = fallbackKey;
    if (packKeySpec != null && packKeySpec != UNDEF) {
      if (packKeySpec instanceof String ks) {
        Matcher full = R_INJECT_FULL.matcher(ks);
        if (full.matches()) {
          kObj = transformInner(data, clone(packKeySpec), item, item, itemPath, inheritedKeySpec, rootSpec, refGuard, opts);
        } else {
          kObj = getpath(item, ks);
        }
      } else {
        kObj = transformInner(data, clone(packKeySpec), item, item, itemPath, inheritedKeySpec, rootSpec, refGuard, opts);
      }
    }
    String outKey = Objects.toString(kObj, "");
    if (outKey.isEmpty()) {
      return;
    }
    List<String> bodyPath = itemPath;
    if (usesFullCopyCommand(packKeySpec) && !bodyPath.isEmpty()) {
      bodyPath = new ArrayList<>(itemPath);
      bodyPath.set(bodyPath.size() - 1, outKey);
    }
    Object outVal;
    if (valueSpec != null) {
      outVal = transformInner(data, clone(valueSpec), item, item, bodyPath, inheritedKeySpec, rootSpec, refGuard, opts);
    } else {
      outVal = transformInner(data, clone(baseTemplate), item, item, bodyPath, inheritedKeySpec, rootSpec, refGuard, opts);
    }
    if (outVal != SKIP) {
      out.put(outKey, outVal);
    }
  }

  private static boolean usesFullCopyCommand(Object spec) {
    if (!(spec instanceof String s)) {
      return false;
    }
    Matcher m = R_INJECT_FULL.matcher(s);
    if (!m.matches()) {
      return false;
    }
    String ref = unescapeInjectRef(m.group(1));
    return "$COPY".equals(ref);
  }

  private static Map<String, Object> toStringMap(Map<?, ?> in) {
    Map<String, Object> out = new LinkedHashMap<>();
    for (Map.Entry<?, ?> e : in.entrySet()) {
      out.put(Objects.toString(e.getKey(), ""), e.getValue());
    }
    return out;
  }

  private static Object transformString(
      Object data,
      String spec,
      Object dparent,
      List<String> dpath,
      Object keySpec,
      TransformOptions opts) {
    if (spec.isEmpty()) {
      return "";
    }

    Map<String, Object> store = new LinkedHashMap<>();
    store.put(S_DTOP, data);

    Map<String, Object> inj = new LinkedHashMap<>();
    inj.put("base", S_DTOP);
    inj.put("dparent", dparent);
    inj.put("dpath", dpath);

    Matcher full = R_INJECT_FULL.matcher(spec);
    if (full.matches()) {
      String pathref = unescapeInjectRef(full.group(1));
      Object out = resolveCustomTransformCommand(pathref, dparent, dpath, opts);
      if (out == UNDEF) {
        out = resolveDotRelativeRef(pathref, dparent, data);
      }
      if (out == UNDEF) {
        out = resolveTransformRef(pathref, dparent, dpath, keySpec);
      }
      if (out == UNDEF) {
        out = getpath(store, pathref, inj);
      }
      return out == null || out == UNDEF ? SKIP : out;
    }

    Matcher matcher = R_INJECT_PART.matcher(spec);
    StringBuilder out = new StringBuilder();
    int cursor = 0;
    while (matcher.find()) {
      out.append(spec, cursor, matcher.start());
      String ref = unescapeInjectRef(matcher.group(1));
      Object found = resolveCustomTransformCommand(ref, dparent, dpath, opts);
      if (found == UNDEF) {
        found = resolveDotRelativeRef(ref, dparent, data);
      }
      if (found == UNDEF) {
        found = resolveTransformRef(ref, dparent, dpath, keySpec);
      }
      if (found == UNDEF) {
        found = getpath(store, ref, inj);
      }
      out.append(injectPartialText(found));
      cursor = matcher.end();
    }
    out.append(spec.substring(cursor));
    return out.toString();
  }

  private static Object resolveDotRelativeRef(String ref, Object dparent, Object data) {
    if (ref == null) {
      return UNDEF;
    }
    if (ref.startsWith("...")) {
      String rem = ref.substring(3);
      while (rem.startsWith(".")) {
        rem = rem.substring(1);
      }
      if (rem.isEmpty()) {
        return data;
      }
      return getpath(data, rem);
    }
    if (ref.startsWith("..")) {
      String rem = ref.substring(2);
      while (rem.startsWith(".")) {
        rem = rem.substring(1);
      }
      if (rem.isEmpty()) {
        return dparent;
      }
      return getpath(dparent, rem);
    }
    return UNDEF;
  }

  private static Object resolveCustomTransformCommand(
      String ref,
      Object dparent,
      List<String> dpath,
      TransformOptions opts) {
    if (opts == null || opts.commandHandlers == null || ref == null || !ref.startsWith("$")) {
      return UNDEF;
    }
    Object handler = opts.commandHandlers.get(ref);
    if (handler instanceof Function<?, ?> fn) {
      Map<String, Object> state = new LinkedHashMap<>();
      state.put("path", dpath == null ? new ArrayList<>() : new ArrayList<>(dpath));
      state.put("dparent", dparent);
      return ((Function<Object, Object>) fn).apply(state);
    }
    return UNDEF;
  }

  private static Object resolveTransformRef(String ref, Object dparent, List<String> dpath, Object keySpec) {
    if (ref == null || !ref.startsWith("$")) {
      return UNDEF;
    }
    if (ref.startsWith("$BT")) {
      return "`";
    }
    if (ref.startsWith("$DS")) {
      return "$";
    }
    if (ref.startsWith("$COPY")) {
      if (dpath == null || dpath.isEmpty()) {
        return dparent;
      }
      if (!isnode(dparent)) {
        return dparent;
      }
      String key = dpath.get(dpath.size() - 1);
      return getprop(dparent, key);
    }
    if (ref.startsWith("$KEY")) {
      if (keySpec != null && keySpec != UNDEF) {
        return getprop(dparent, keySpec);
      }
      if (dpath == null || dpath.isEmpty()) {
        return null;
      }
      if (dpath.size() >= 2) {
        return dpath.get(dpath.size() - 2);
      }
      return dpath.get(0);
    }
    if (ref.startsWith("$DELETE")) {
      return SKIP;
    }
    return UNDEF;
  }

  public static Object validate(Object data, Object spec) {
    return validate(data, spec, null);
  }

  public static Object validate(Object data, Object spec, Map<String, Object> options) {
    Map<String, Object> opts = options == null ? new LinkedHashMap<>() : new LinkedHashMap<>(options);
    boolean collect = false;
    List<String> errs;
    Object errsObj = opts.get("errs");
    if (errsObj instanceof List<?> l) {
      errs = (List<String>) l;
      collect = true;
    } else {
      errs = new ArrayList<>();
      opts.put("errs", errs);
    }
    opts.put("__topdata__", data);
    opts.put("__topspec__", spec);

    Object out = validateNode(data, spec, new ArrayList<>(), opts, null);
    if (!errs.isEmpty() && !collect) {
      throw new IllegalArgumentException(String.join(" | ", errs));
    }
    return out;
  }

  private static Object validateNode(
      Object data, Object spec, List<String> path, Map<String, Object> options, Object dparent) {
    List<String> errs = (List<String>) options.get("errs");
    Map<String, Object> meta =
        options.get("meta") instanceof Map<?, ?> mm ? toStringMap(mm) : new LinkedHashMap<>();

    if (spec == UNDEF) {
      return data;
    }
    if (spec == null) {
      return data == UNDEF ? null : data;
    }

    if (spec instanceof String s) {
      String cmd = extractFullCommand(s);
      if (cmd != null) {
        if (options.get("extra") instanceof Map<?, ?> extra && extra.containsKey(cmd)) {
          Object fn = extra.get(cmd);
          if (fn instanceof Function<?, ?> f) {
            Map<String, Object> inj = new LinkedHashMap<>();
            inj.put("key", path.isEmpty() ? null : path.get(path.size() - 1));
            inj.put("path", new ArrayList<>(path));
            inj.put("dparent", dparent);
            inj.put("errs", errs);
            Object out = ((Function<Object, Object>) f).apply(inj);
            return out == null ? data : out;
          }
        }

        if ("$ANY".equals(cmd)) {
          return data;
        }
        if ("$STRING".equals(cmd)) {
          if (data == null || data == UNDEF) {
            errs.add(expectedMsg(path, "string", data));
            return data;
          }
          if (!(data instanceof String ds)) {
            errs.add(expectedMsg(path, "string", data));
            return data;
          }
          if (ds.isEmpty()) {
            errs.add("Empty string at " + pathify(path));
          }
          return data;
        }
        if ("$NUMBER".equals(cmd)) {
          if (!(data instanceof Number)) {
            errs.add(expectedMsg(path, "number", data));
          }
          return data;
        }
        if ("$INTEGER".equals(cmd)) {
          if (!(data instanceof Number n) || Math.floor(n.doubleValue()) != n.doubleValue()) {
            errs.add(expectedMsg(path, "integer", data));
          }
          return data;
        }
        if ("$DECIMAL".equals(cmd)) {
          if (!(data instanceof Number n) || Math.floor(n.doubleValue()) == n.doubleValue()) {
            errs.add(expectedMsg(path, "decimal", data));
          }
          return data;
        }
        if ("$BOOLEAN".equals(cmd)) {
          if (!(data instanceof Boolean)) {
            errs.add(expectedMsg(path, "boolean", data));
          }
          return data;
        }
        if ("$MAP".equals(cmd) || "$OBJECT".equals(cmd)) {
          if (!(data instanceof Map<?, ?>)) {
            errs.add(expectedMsg(path, "map", data));
          }
          return data;
        }
        if ("$LIST".equals(cmd) || "$ARRAY".equals(cmd)) {
          if (!(data instanceof List<?>)) {
            errs.add(expectedMsg(path, "list", data));
          }
          return data;
        }
        if ("$NULL".equals(cmd)) {
          if (data != null) {
            errs.add(expectedMsg(path, "null", data));
          }
          return data;
        }
        if ("$NIL".equals(cmd)) {
          if (!(data == null || data == UNDEF)) {
            errs.add(expectedMsg(path, "nil", data));
          }
          return data;
        }
        if ("$FUNCTION".equals(cmd)) {
          if (!isfunc(data)) {
            errs.add(expectedMsg(path, "function", data));
          }
          return data;
        }
        if ("$INSTANCE".equals(cmd)) {
          if (data == null || data == UNDEF || data instanceof String || data instanceof Number
              || data instanceof Boolean || data instanceof Map<?, ?> || data instanceof List<?>
              || isfunc(data)) {
            errs.add(expectedMsg(path, "instance", data));
          }
          return data;
        }
        return data;
      }

      Matcher m = Pattern.compile("^`([^`$]+)\\$(=|~)([^`]+)`$").matcher(s);
      if (m.matches()) {
        String mroot = m.group(1);
        String op = m.group(2);
        String mpath = m.group(3);
        Object mv = getpath(meta, mroot + "." + mpath);
        if ("=".equals(op)) {
          if (!deepEqualNode(data, mv)) {
            errs.add(expectedExactMsg(path, mv, data));
          }
        } else {
          int mt = typify(mv);
          int dt = typify(data);
          if (mt != dt) {
            errs.add(expectedMsg(path, typename(mt), data));
          }
        }
        return data;
      }

      if (s.length() >= 2 && s.startsWith("`") && s.endsWith("`")) {
        String raw = s.substring(1, s.length() - 1);
        String ref = unescapeInjectRef(raw);
        if (ref != null && !ref.startsWith("$")) {
          if (data != UNDEF) {
            return data;
          }
          Map<String, Object> store = new LinkedHashMap<>();
          store.put(S_DTOP, options.get("__topdata__"));
          Map<String, Object> inj = new LinkedHashMap<>();
          inj.put("base", S_DTOP);
          Object resolved = getpath(store, ref, inj);
          return resolved == UNDEF ? s : resolved;
        }
      }

      if (data == UNDEF) {
        return s;
      }
      boolean exact = Boolean.TRUE.equals(meta.get("`$EXACT`")) || Boolean.TRUE.equals(meta.get("$EXACT"));
      if (exact) {
        if (!Objects.equals(data, s)) {
          errs.add(valueEqualMsg(path, data, s));
        }
      } else if (!(data instanceof String)) {
        errs.add(expectedMsg(path, "string", data));
      }
      return data;
    }

    if (spec instanceof Map<?, ?> sm) {
      Map<String, Object> specMap = toStringMap(sm);
      Map<String, Object> out = data instanceof Map<?, ?> dm ? toStringMap(dm) : new LinkedHashMap<>();

      Object childTemplate = null;
      for (Map.Entry<String, Object> e : specMap.entrySet()) {
        String cmd = extractFullCommand(e.getKey());
        if ("$CHILD".equals(cmd)) {
          childTemplate = e.getValue();
        }
      }

      if (childTemplate != null && data instanceof Map<?, ?> dm) {
        out = new LinkedHashMap<>();
        for (Map.Entry<?, ?> e : dm.entrySet()) {
          String k = Objects.toString(e.getKey(), "");
          List<String> cpath = new ArrayList<>(path);
          cpath.add(k);
          out.put(k, validateNode(e.getValue(), clone(childTemplate), cpath, options, dm));
        }
        return out;
      }

      if (data instanceof Map<?, ?> dm && !specMap.isEmpty()) {
        if (!Boolean.TRUE.equals(specMap.get("`$OPEN`"))) {
          for (Map.Entry<?, ?> e : dm.entrySet()) {
            String k = Objects.toString(e.getKey(), "");
            if (!specMap.containsKey(k) && !k.startsWith("`$")) {
              errs.add("Unexpected keys at field " + pathify(path) + ": " + k);
            }
          }
        }
      }

      for (Map.Entry<String, Object> e : specMap.entrySet()) {
        String k = e.getKey();
        if (extractFullCommand(k) != null) {
          continue;
        }
        List<String> cpath = new ArrayList<>(path);
        cpath.add(k);
        Object dval = data instanceof Map<?, ?> dm ? getprop(dm, k, UNDEF) : UNDEF;
        if (dval == UNDEF) {
          if (e.getValue() instanceof String sv && extractFullCommand(sv) != null) {
            Object v = validateNode(UNDEF, sv, cpath, options, data);
            if (v != UNDEF && v != null) {
              out.put(k, v);
            }
            continue;
          }
          if (e.getValue() instanceof List<?> sl && "$CHILD".equals(extractFullCommand(getelem(sl, 0)))) {
            out.put(k, new ArrayList<>());
            continue;
          }
          out.put(k, validateNode(UNDEF, e.getValue(), cpath, options, data));
        } else {
          out.put(k, validateNode(dval, e.getValue(), cpath, options, data));
        }
      }
      return out;
    }

    if (spec instanceof List<?> sl) {
      String cmd = extractFullCommand(getelem(sl, 0));
      if ("$REF".equals(cmd) && sl.size() >= 2) {
        if (data != UNDEF) {
          return data;
        }
        Object rootSpec = options.get("__topspec__");
        Object refSpec = getpath(rootSpec, Objects.toString(sl.get(1), ""));
        if (refSpec == UNDEF) {
          return data;
        }
        return validateNode(UNDEF, clone(refSpec), path, options, dparent);
      }
      if ("$EXACT".equals(cmd) && sl.size() >= 2) {
        for (int i = 1; i < sl.size(); i++) {
          if (deepEqualNode(data, sl.get(i))) {
            return data;
          }
        }
        if (sl.size() == 2) {
          errs.add(expectedExactMsg(path, sl.get(1), data));
        } else {
          errs.add(expectedExactDescMsg(path, "one of " + describeValues(sl.subList(1, sl.size())), data));
        }
        return data;
      }
      if ("$ONE".equals(cmd) && sl.size() >= 2) {
        for (int i = 1; i < sl.size(); i++) {
          if (validateMatches(data, sl.get(i))) {
            return data;
          }
        }
        errs.add(expectedMsg(path, "one of " + describeValues(sl.subList(1, sl.size())), data));
        return data;
      }
      if ("$CHILD".equals(cmd) && sl.size() >= 2) {
        Object tmpl = sl.get(1);
        if (data instanceof List<?> dl) {
          List<Object> out = new ArrayList<>();
          for (int i = 0; i < dl.size(); i++) {
            List<String> cpath = new ArrayList<>(path);
            cpath.add(strkey(i));
            out.add(validateNode(dl.get(i), clone(tmpl), cpath, options, dl));
          }
          return out;
        }
        if (data != UNDEF) {
          errs.add(expectedMsg(path, "list", data));
        }
        return data;
      }

      List<Object> out = data instanceof List<?> dl ? new ArrayList<>(dl) : new ArrayList<>();
      for (int i = 0; i < sl.size(); i++) {
        List<String> cpath = new ArrayList<>(path);
        cpath.add(strkey(i));
        Object dval = data instanceof List<?> dl ? getprop(dl, i, UNDEF) : UNDEF;
        Object sv = sl.get(i);
        if (dval == UNDEF) {
          if (sv instanceof String s && extractFullCommand(s) != null) {
            continue;
          }
          if (i < out.size()) out.set(i, clone(sv));
          else out.add(clone(sv));
        } else {
          Object v = validateNode(dval, sv, cpath, options, data);
          if (i < out.size()) out.set(i, v);
          else out.add(v);
        }
      }
      return out;
    }

    boolean exact = Boolean.TRUE.equals(meta.get("`$EXACT`")) || Boolean.TRUE.equals(meta.get("$EXACT"));
    if (data == UNDEF) {
      return clone(spec);
    }
    if (exact) {
      if (!deepEqualNode(data, spec)) {
        errs.add(valueEqualMsg(path, data, spec));
      }
      return data;
    }
    if (typify(data) != typify(spec)) {
      errs.add(expectedMsg(path, typename(typify(spec)), data));
    }
    return data == UNDEF ? clone(spec) : data;
  }

  private static String expectedMsg(List<String> path, String expected, Object found) {
    if (path.isEmpty()) {
      return "Expected " + expected + ", but found " + foundDesc(found) + ".";
    }
    return "Expected field " + pathify(path) + " to be " + expected + ", but found " + foundDesc(found) + ".";
  }

  private static String expectedExactMsg(List<String> path, Object expected, Object found) {
    return expectedExactDescMsg(path, stringify(expected), found);
  }

  private static String expectedExactDescMsg(List<String> path, String expectedDesc, Object found) {
    if (path.isEmpty()) {
      return "Expected value exactly equal to " + expectedDesc + ", but found " + foundDesc(found) + ".";
    }
    return "Expected field " + pathify(path) + " to be exactly equal to " + expectedDesc + ", but found " + foundDesc(found) + ".";
  }

  private static String valueEqualMsg(List<String> path, Object data, Object spec) {
    if (path.isEmpty()) {
      return "Value " + stringify(data) + " should equal " + stringify(spec) + ".";
    }
    return "Value at field " + pathify(path) + ": " + stringify(data) + " should equal " + stringify(spec) + ".";
  }

  private static String foundDesc(Object found) {
    if (found == null || found == UNDEF) {
      return "no value";
    }
    return typename(typify(found)) + ": " + stringify(found);
  }

  private static String describeValues(List<?> vals) {
    List<String> parts = new ArrayList<>();
    for (Object v : vals) {
      if (v instanceof String s) {
        String cmd = extractFullCommand(s);
        if (cmd != null) {
          parts.add(cmd.substring(1).toLowerCase(Locale.ROOT));
          continue;
        }
      }
      parts.add(stringify(v));
    }
    return String.join(", ", parts);
  }

  private static boolean deepEqualNode(Object a, Object b) {
    return Objects.equals(normalizeNode(a), normalizeNode(b));
  }

  private static Object normalizeNode(Object v) {
    if (v instanceof Number n) {
      double d = n.doubleValue();
      if (Math.floor(d) == d) {
        return (long) d;
      }
      return d;
    }
    if (v instanceof List<?> l) {
      List<Object> out = new ArrayList<>();
      for (Object x : l) out.add(normalizeNode(x));
      return out;
    }
    if (v instanceof Map<?, ?> m) {
      Map<String, Object> out = new LinkedHashMap<>();
      for (Map.Entry<?, ?> e : m.entrySet()) {
        out.put(Objects.toString(e.getKey(), ""), normalizeNode(e.getValue()));
      }
      return out;
    }
    return v;
  }

  private static boolean validateMatches(Object data, Object spec) {
    if (spec == null) {
      return data == null;
    }
    if (spec instanceof String s) {
      String cmd = extractFullCommand(s);
      if (cmd == null) {
        return Objects.equals(data, s);
      }
      return switch (cmd) {
        case "$STRING" -> data instanceof String ds && !ds.isEmpty();
        case "$NUMBER" -> data instanceof Number;
        case "$INTEGER" -> data instanceof Number n && Math.floor(n.doubleValue()) == n.doubleValue();
        case "$DECIMAL" -> data instanceof Number n && Math.floor(n.doubleValue()) != n.doubleValue();
        case "$BOOLEAN" -> data instanceof Boolean;
        case "$MAP", "$OBJECT" -> data instanceof Map;
        case "$LIST", "$ARRAY" -> data instanceof List;
        case "$NULL" -> data == null;
        case "$NIL" -> data == null || data == UNDEF;
        default -> true;
      };
    }
    if (spec instanceof Number || spec instanceof Boolean) {
      return Objects.equals(spec, data);
    }
    return true;
  }

  public static List<Object> select(Object children, Object query) {
    if (!isnode(children)) {
      return new ArrayList<>();
    }
    List<Object> out = new ArrayList<>();
    if (children instanceof Map<?, ?> m) {
      for (Map.Entry<?, ?> e : m.entrySet()) {
        String key = Objects.toString(e.getKey(), "");
        Object child = clone(e.getValue());
        if (child instanceof Map<?, ?> cm) {
          Map<String, Object> node = toStringMap(cm);
          node.put(S_DKEY, key);
          child = node;
        }
        if (selectMatch(child, query)) {
          out.add(child);
        }
      }
    } else if (children instanceof List<?> l) {
      for (int i = 0; i < l.size(); i++) {
        Object child = clone(l.get(i));
        if (child instanceof Map<?, ?> cm) {
          Map<String, Object> node = toStringMap(cm);
          node.put(S_DKEY, i);
          child = node;
        }
        if (selectMatch(child, query)) {
          out.add(child);
        }
      }
    }
    return out;
  }

  private static boolean selectMatch(Object child, Object query) {
    return selectEval(child, query);
  }

  private static boolean selectEval(Object point, Object query) {
    if (!(query instanceof Map<?, ?> qm)) {
      return deepEqualNode(point, query);
    }
    Map<String, Object> q = toStringMap(qm);
    if (q.isEmpty()) {
      return true;
    }

    for (Map.Entry<String, Object> e : q.entrySet()) {
      String key = e.getKey();
      Object term = e.getValue();
      String cmd = extractFullCommand(key);
      if (cmd != null) {
        if (!selectEvalCommand(point, cmd, term)) {
          return false;
        }
        continue;
      }

      if (!(point instanceof Map<?, ?> pm)) {
        return false;
      }
      Map<String, Object> pointMap = toStringMap(pm);
      if (!pointMap.containsKey(key)) {
        return false;
      }
      Object child = pointMap.get(key);
      if (!selectEval(child, term)) {
        return false;
      }
    }

    return true;
  }

  private static boolean selectEvalCommand(Object point, String cmd, Object term) {
    switch (cmd) {
      case "$AND":
        if (!(term instanceof List<?> andTerms)) {
          return false;
        }
        for (Object t : andTerms) {
          if (!selectEval(point, t)) {
            return false;
          }
        }
        return true;
      case "$OR":
        if (!(term instanceof List<?> orTerms)) {
          return false;
        }
        for (Object t : orTerms) {
          if (selectEval(point, t)) {
            return true;
          }
        }
        return false;
      case "$NOT":
        return !selectEval(point, term);
      case "$GT":
      case "$LT":
      case "$GTE":
      case "$LTE":
        return selectCompare(point, term, cmd);
      case "$LIKE":
        if (!(term instanceof String s)) {
          return false;
        }
        return Pattern.compile(s).matcher(stringify(point)).find();
      default:
        return false;
    }
  }

  private static boolean selectCompare(Object point, Object term, String op) {
    if (point instanceof Number pn && term instanceof Number tn) {
      double a = pn.doubleValue();
      double b = tn.doubleValue();
      return switch (op) {
        case "$GT" -> a > b;
        case "$LT" -> a < b;
        case "$GTE" -> a >= b;
        case "$LTE" -> a <= b;
        default -> false;
      };
    }
    if (point instanceof Comparable<?> pc && term != null && point.getClass().isInstance(term)) {
      @SuppressWarnings("unchecked")
      int cmp = ((Comparable<Object>) pc).compareTo(term);
      return switch (op) {
        case "$GT" -> cmp > 0;
        case "$LT" -> cmp < 0;
        case "$GTE" -> cmp >= 0;
        case "$LTE" -> cmp <= 0;
        default -> false;
      };
    }
    return false;
  }

  // ===========================================================================
  // Injection
  // ===========================================================================

  /**
   * Recursive state passed through {@link #inject}, {@link #transform}, and
   * {@link #validate}. Mirrors TS {@code class Injection} (StructUtility.ts
   * lines 2613–2744).
   *
   * <h3>Sharing semantics (critical)</h3>
   * <ul>
   *   <li>{@link #child(int, List)} shares {@link #keys}, {@link #errs},
   *       and {@link #meta} <em>by reference</em> with the parent. The
   *       {@code $EACH} and {@code $PACK} injectors mutate {@code keys} during
   *       descent — defensively copying them silently breaks those tests.</li>
   *   <li>{@link #path}, {@link #nodes}, and {@link #dpath} are flattened
   *       (copied) per child.</li>
   * </ul>
   *
   * <p>This class is package-private to its own file and is intentionally not
   * Gson-serializable: a circular {@link #prior} reference would stack-overflow
   * any default serializer.
   */
  public static class Injection {
    public int mode;                         // M_KEYPRE | M_KEYPOST | M_VAL
    public boolean full;                     // injection consumed the whole key string
    public int keyI;                         // index of current key in keys
    public List<String> keys;                // sibling keys list (shared with prior)
    public String key;                       // current key string
    public Object val;                       // current child value
    public Object parent;                    // current parent in spec
    public List<String> path;                // ancestor key chain ending in key
    public List<Object> nodes;               // ancestor node stack ending in parent
    public Injector handler;                 // dispatch hook for `$NAME` references
    public List<Object> errs;                // shared error collector
    public Map<String, Object> meta;         // shared metadata bag (do not deep-copy)
    public Object dparent = UNDEF;           // current data-side parent
    public List<String> dpath;               // current data-side path
    public String base;                      // base key in store, if any
    public Modify modify;                    // optional value-mutation hook
    public Injection prior;                  // calling injection (chain upwards)
    public Object extra;                     // free-form passthrough

    /** Top-level constructor: mirrors {@code new Injection(val, parent)} in TS. */
    public Injection(Object val, Object parent) {
      this.val = val;
      this.parent = parent;
      this.errs = new ArrayList<>();
      this.dparent = UNDEF;
      this.dpath = new ArrayList<>(List.of(S_DTOP));
      this.mode = M_VAL;
      this.full = false;
      this.keyI = 0;
      this.keys = new ArrayList<>(List.of(S_DTOP));
      this.key = S_DTOP;
      this.path = new ArrayList<>(List.of(S_DTOP));
      this.nodes = new ArrayList<>();
      this.nodes.add(parent);
      this.handler = null; // wired in step 5a (_injecthandler)
      this.base = S_DTOP;
      this.meta = new LinkedHashMap<>();
    }

    /**
     * Resolve current data-side parent for relative paths and bump depth.
     * Mirrors TS {@code Injection.descend()}.
     */
    public Object descend() {
      Object dRaw = meta.get("__d");
      int d = dRaw instanceof Number n ? n.intValue() : 0;
      meta.put("__d", d + 1);

      Object parentkey = path.size() >= 2 ? path.get(path.size() - 2) : null;

      if (dparent == UNDEF) {
        if (size(dpath) > 1 && parentkey != null) {
          List<String> nd = new ArrayList<>(dpath);
          nd.add(strkey(parentkey));
          this.dpath = nd;
        }
      } else {
        if (parentkey != null) {
          this.dparent = getprop(this.dparent, parentkey);
          String lastpart = dpath.isEmpty() ? null : dpath.get(dpath.size() - 1);
          String marker = "$:" + strkey(parentkey);
          if (marker.equals(lastpart)) {
            Object sliced = slice(this.dpath, -1, null);
            this.dpath =
                sliced instanceof List<?> l ? new ArrayList<>((List<String>) l) : new ArrayList<>();
          } else {
            List<String> nd = new ArrayList<>(dpath);
            nd.add(strkey(parentkey));
            this.dpath = nd;
          }
        }
      }
      return dparent;
    }

    /**
     * Build a child injection at {@code keys[keyI]}. Sharing semantics: see
     * class javadoc.
     */
    public Injection child(int keyI, List<String> keys) {
      String key = strkey(keys.get(keyI));
      Object val = this.val;

      Injection cinj = new Injection(getprop(val, key), val);
      cinj.keyI = keyI;
      cinj.keys = keys;        // shared reference
      cinj.key = key;

      List<String> np = path == null ? new ArrayList<>() : new ArrayList<>(path);
      np.add(key);
      cinj.path = np;

      List<Object> nn = nodes == null ? new ArrayList<>() : new ArrayList<>(nodes);
      nn.add(val);
      cinj.nodes = nn;

      cinj.mode = this.mode;
      cinj.handler = this.handler;
      cinj.modify = this.modify;
      cinj.base = this.base;
      cinj.meta = this.meta;   // shared reference
      cinj.errs = this.errs;   // shared reference
      cinj.prior = this;
      cinj.dpath = new ArrayList<>(this.dpath);  // flattened
      cinj.dparent = this.dparent;

      return cinj;
    }

    /** Set the current child value on the immediate parent. */
    public Object setval(Object val) {
      return setval(val, 0);
    }

    /**
     * Set / delete a value on an ancestor.
     * <ul>
     *   <li>{@code ancestor < 2} → operate on {@link #parent} at {@link #key}.</li>
     *   <li>{@code ancestor >= 2} → walk back to {@code nodes[-ancestor]} and
     *       use {@code path[-ancestor]} as the key.</li>
     * </ul>
     * When {@code val == UNDEF}, the key is deleted via {@link Struct#delprop}.
     */
    public Object setval(Object val, int ancestor) {
      Object parent;
      if (ancestor < 2) {
        if (val == UNDEF) {
          parent = delprop(this.parent, this.key);
          this.parent = parent;
        } else {
          parent = setprop(this.parent, this.key, val);
        }
      } else {
        Object aval = getelem(this.nodes, 0 - ancestor);
        Object akey = getelem(this.path, 0 - ancestor);
        if (val == UNDEF) {
          parent = delprop(aval, akey);
        } else {
          parent = setprop(aval, akey, val);
        }
      }
      return parent;
    }

    @Override
    public String toString() {
      return toString(null);
    }

    public String toString(String prefix) {
      StringBuilder sb = new StringBuilder();
      sb.append("INJ");
      if (prefix != null) {
        sb.append("/").append(prefix);
      }
      sb.append(":").append(pathify(path, 1));
      sb.append(":").append(MODENAME.getOrDefault(mode, "?"));
      if (full) {
        sb.append("/full");
      }
      sb.append(": key=").append(keyI).append("/").append(key);
      sb.append(" keys=").append(keys);
      sb.append(" parent=").append(stringify(parent, 60));
      sb.append(" dpath=").append(dpath);
      return sb.toString();
    }
  }
}
