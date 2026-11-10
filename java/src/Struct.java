package voxgig.struct;


import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.StringJoiner;
import java.util.function.Function;
import java.util.function.Supplier;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@SuppressWarnings({"unchecked", "rawtypes"})
public class Struct {
  private Struct() {}

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
  public static final String S_DERRS = "$ERRS";
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
  private static final Pattern R_CHECKER_NAME = Pattern.compile("^\\$[A-Z]+$");
  private static final Pattern R_INJECT_PART = Pattern.compile("`([^`]+)`");
  private static final Pattern R_CMD_KEY = Pattern.compile("^`(\\$[A-Z]+)(\\d*)`$");
  private static final Pattern R_BT_ESCAPE = Pattern.compile("\\$BT");
  private static final Pattern R_DS_ESCAPE = Pattern.compile("\\$DS");
  private static final Pattern R_TRANSFORM_NAME = Pattern.compile("`\\$([A-Z]+)`");
  private static final Pattern R_DOUBLE_DOLLAR = Pattern.compile("\\$\\$");
  private static final Pattern R_CLONE_REF = Pattern.compile("^`\\$REF:([0-9]+)`$");
  private static final Pattern R_LIST_INDEX = Pattern.compile("^(0|-?[1-9][0-9]*)$");

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
    return val instanceof Function
        || val instanceof Supplier
        || val instanceof Injector
        || val instanceof Modify;
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
    if (value instanceof Function
        || value instanceof Supplier
        || value instanceof Injector
        || value instanceof Modify) {
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
    // Group A rule: a key whose stored value is JSON null counts as "no value".
    // getprop unifies null/absent to the alt (UNDEF here), so a present-but-null
    // key yields UNDEF → false. Mirrors canonical TS `null != getprop(val,key)`.
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
      // Group B raw read: canonical items uses val[k], preserving a stored
      // JSON null (the Group A getprop would unify it to UNDEF).
      item.add(lookup(val, k));
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

    double idx = listIndex(key);
    if (idx < 0) {
      // A negative key counts from the end.
      idx += list.size();
    }
    if (!(0 <= idx && idx < list.size())) {
      if (alt instanceof Function<?, ?> f) {
        return ((Function<Object, Object>) f).apply(null);
      }
      return alt;
    }

    Object out = list.get((int) idx);
    // Group A null-unification: a JSON null (or absent) slot counts as "no
    // value" — return the alt. Mirrors canonical TS getelem `if (null == out)`.
    if (out == null || out == UNDEF) {
      if (alt instanceof Function<?, ?> f) {
        return ((Function<Object, Object>) f).apply(null);
      }
      return alt;
    }
    return out;
  }

  public static Object getprop(Object val, Object key) {
    return getprop(val, key, UNDEF);
  }

  public static Object getprop(Object val, Object key, Object alt) {
    if (val == null || val == UNDEF || key == null || key == UNDEF) {
      return alt;
    }

    Object out = UNDEF;

    if (val instanceof Map<?, ?> m) {
      String sk = mapKey(key);
      if (null != sk && m.containsKey(sk)) {
        out = ((Map<Object, Object>) m).get(sk);
      }
    } else if (val instanceof List<?> l) {
      double idx = listIndex(key);
      if (0 <= idx && idx < l.size()) {
        out = l.get((int) idx);
      }
    }

    // Group A null-unification: a stored JSON null (or absent) at the key is
    // treated as "no value" — return the alternative. Mirrors canonical TS
    // getprop `if (null == out) return alt`. Group B callers needing the raw
    // stored null use {@link #lookup}.
    if (out == null || out == UNDEF) {
      return alt;
    }

    return out;
  }

  /**
   * Group B raw value lookup: read the literally-stored value at a slot,
   * preserving JSON {@code null}. Returns {@link #UNDEF} when the key is absent
   * or the container is not a node. Mirrors canonical TS {@code _lookup} — used
   * by validate / transform / inject internals that must distinguish a stored
   * null from absence (where the public getprop/getelem unify the two).
   */
  public static Object lookup(Object val, Object key) {
    if (val == null || val == UNDEF || key == null || key == UNDEF) {
      return UNDEF;
    }
    if (val instanceof Map<?, ?> m) {
      String sk = mapKey(key);
      return null != sk && m.containsKey(sk) ? ((Map<Object, Object>) m).get(sk) : UNDEF;
    }
    if (val instanceof List<?> l) {
      double idx = listIndex(key);
      return 0 <= idx && idx < l.size() ? l.get((int) idx) : UNDEF;
    }
    return UNDEF;
  }

  // The key a map read takes, or null for one that is neither a string nor a
  // number, which misses.
  private static String mapKey(Object key) {
    return key instanceof String || key instanceof Number ? strkey(key) : null;
  }

  // A list key's index, or NaN: an integral number, or the string String(n)
  // prints for one, negative or not ("01", "+1", "1.0" and "-0" are not).
  private static double listIndex(Object key) {
    if (key instanceof Number n) {
      double d = n.doubleValue();
      return Double.isFinite(d) && Math.floor(d) == d ? d : Double.NaN;
    }
    return key instanceof String s && R_LIST_INDEX.matcher(s).matches() ? Double.parseDouble(s) : Double.NaN;
  }

  public static Object setprop(Object parent, Object key, Object val) {
    if (!iskey(key)) {
      return parent;
    }

    if (iscondensed(parent)) {
      throw new IllegalArgumentException(CONDENSE_IMMUTABLE);
    }

    if (parent instanceof Map<?, ?>) {
      Map<Object, Object> m = (Map<Object, Object>) parent;
      m.put(strkey(key), val);
      return parent;
    }

    if (parent instanceof List<?>) {
      List<Object> l = (List<Object>) parent;
      double idx = listIndex(key);
      if (Double.isNaN(idx)) {
        return parent;
      }

      if (idx >= 0) {
        if (idx < l.size()) {
          l.set((int) idx, val);
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

    if (iscondensed(parent)) {
      throw new IllegalArgumentException(CONDENSE_IMMUTABLE);
    }

    if (parent instanceof Map<?, ?> m) {
      ((Map<Object, Object>) m).remove(strkey(key));
      return parent;
    }

    if (parent instanceof List<?> l) {
      double idx = listIndex(key);
      if (0 <= idx && idx < l.size()) {
        ((List<Object>) l).remove((int) idx);
      }
      return parent;
    }

    return parent;
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
    if (val instanceof String
        || val instanceof Number
        || val instanceof Boolean
        || val instanceof Function
        || val instanceof Supplier
        || val instanceof Injector
        || val instanceof Modify) {
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

  // -------------------------------------------------------------------------
  // Regex utility — uniform re* API (see /REGEX_API.md). Java's
  // java.util.regex.Pattern is an ECMAScript-like engine; a strict superset
  // of RE2.
  // -------------------------------------------------------------------------

  public static java.util.regex.Pattern reCompile(String pattern) {
    return java.util.regex.Pattern.compile(pattern);
  }

  public static boolean reTest(String pattern, String input) {
    if (input == null) input = "";
    return java.util.regex.Pattern.compile(pattern).matcher(input).find();
  }

  public static String[] reFind(String pattern, String input) {
    if (input == null) input = "";
    java.util.regex.Matcher m = java.util.regex.Pattern.compile(pattern).matcher(input);
    if (!m.find()) return null;
    String[] out = new String[m.groupCount() + 1];
    for (int i = 0; i <= m.groupCount(); i++) {
      out[i] = m.group(i) == null ? "" : m.group(i);
    }
    return out;
  }

  public static java.util.List<String[]> reFindAll(String pattern, String input) {
    if (input == null) input = "";
    java.util.List<String[]> out = new java.util.ArrayList<>();
    java.util.regex.Matcher m = java.util.regex.Pattern.compile(pattern).matcher(input);
    while (m.find()) {
      String[] row = new String[m.groupCount() + 1];
      for (int i = 0; i <= m.groupCount(); i++) row[i] = m.group(i) == null ? "" : m.group(i);
      out.add(row);
    }
    return out;
  }

  public static String reReplace(String pattern, String input, String replacement) {
    if (input == null) input = "";
    // Translate JS-style $& / $1 to Java's $0 / $1
    String javaRepl = replacement.replace("$&", "\\$0");
    return java.util.regex.Pattern.compile(pattern).matcher(input).replaceAll(javaRepl);
  }

  public static String reReplaceFn(String pattern, String input,
                                   java.util.function.Function<String[], String> fn) {
    if (input == null) input = "";
    java.util.regex.Matcher m = java.util.regex.Pattern.compile(pattern).matcher(input);
    StringBuffer sb = new StringBuffer();
    while (m.find()) {
      String[] groups = new String[m.groupCount() + 1];
      for (int i = 0; i <= m.groupCount(); i++) groups[i] = m.group(i) == null ? "" : m.group(i);
      m.appendReplacement(sb, java.util.regex.Matcher.quoteReplacement(fn.apply(groups)));
    }
    m.appendTail(sb);
    return sb.toString();
  }

  public static String reEscape(String s) { return escre(s); }

  // Keeps what encodeURIComponent keeps: URLEncoder encodes `~!'()` and spaces as `+`.
  public static String escurl(Object s) {
    if (s == null || s == UNDEF) {
      return "";
    }
    return URLEncoder.encode(Objects.toString(s), StandardCharsets.UTF_8)
        .replace("+", "%20")
        .replace("%7E", "~")
        .replace("%21", "!")
        .replace("%27", "'")
        .replace("%28", "(")
        .replace("%29", ")");
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
      StringBuilder sb = new StringBuilder();
      _jsonifyInner(val, sb, indent, 0, new IdentityHashMap<>());
      String out = sb.toString();
      if (offset > 0 && out.contains("\n")) {
        String[] lines = out.split("\n", -1);
        StringBuilder pb = new StringBuilder(lines[0]);
        String pad = " ".repeat(offset);
        for (int i = 1; i < lines.length; i++) {
          pb.append("\n").append(pad).append(lines[i]);
        }
        out = pb.toString();
      }
      return out;
    } catch (Exception e) {
      return "__JSONIFY_FAILED__";
    }
  }

  // Pure-Java JSON emitter — mirrors c/src/utility.c::jsonify_inner. Map
  // keys are emitted in INSERTION order (matching TS canonical's
  // JSON.stringify behaviour). No third-party JSON library involved.
  private static void _jsonifyInner(Object v, StringBuilder out, int indent, int depth,
                                    IdentityHashMap<Object, Boolean> seen) {
    if (v == null || v == UNDEF) { out.append("null"); return; }
    if (v instanceof Boolean b) { out.append(b ? "true" : "false"); return; }
    if (v instanceof Number n) {
      double d = n.doubleValue();
      if (!Double.isFinite(d)) { out.append("null"); return; }
      if (Math.floor(d) == d && Math.abs(d) < 1e15) {
        out.append(Long.toString((long) d));
      } else {
        // %g-style: shortest round-trip-ish. Locale-independent.
        String s = String.format(java.util.Locale.ROOT, "%g", d);
        // Trim trailing zeros in the fractional part (matches C %g).
        if (s.contains(".") && !s.contains("e") && !s.contains("E")) {
          s = s.replaceAll("0+$", "").replaceAll("\\.$", "");
        }
        out.append(s);
      }
      return;
    }
    if (v instanceof String s) {
      out.append('"');
      _jsonEscape(s, out);
      out.append('"');
      return;
    }
    if (v instanceof Function) { out.append("null"); return; }
    if (seen.containsKey(v)) { out.append("null"); return; }
    seen.put(v, true);
    if (v instanceof List<?> l) {
      if (l.isEmpty()) { out.append("[]"); seen.remove(v); return; }
      out.append('[');
      boolean first = true;
      for (Object e : l) {
        if (!first) out.append(',');
        first = false;
        if (indent > 0) {
          out.append('\n').append(" ".repeat((depth + 1) * indent));
        }
        _jsonifyInner(e, out, indent, depth + 1, seen);
      }
      if (indent > 0) {
        out.append('\n').append(" ".repeat(depth * indent));
      }
      out.append(']');
      seen.remove(v);
      return;
    }
    if (v instanceof Map<?, ?> m) {
      if (m.isEmpty()) { out.append("{}"); seen.remove(v); return; }
      out.append('{');
      boolean first = true;
      for (Map.Entry<?, ?> e : m.entrySet()) {
        if (!first) out.append(',');
        first = false;
        if (indent > 0) {
          out.append('\n').append(" ".repeat((depth + 1) * indent));
        }
        out.append('"');
        _jsonEscape(java.util.Objects.toString(e.getKey()), out);
        out.append(indent > 0 ? "\": " : "\":");
        _jsonifyInner(e.getValue(), out, indent, depth + 1, seen);
      }
      if (indent > 0) {
        out.append('\n').append(" ".repeat(depth * indent));
      }
      out.append('}');
      seen.remove(v);
      return;
    }
    seen.remove(v);
    out.append("null");
  }

  private static void _jsonEscape(String s, StringBuilder out) {
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      switch (c) {
        case '"':  out.append("\\\""); break;
        case '\\': out.append("\\\\"); break;
        case '\b': out.append("\\b"); break;
        case '\f': out.append("\\f"); break;
        case '\n': out.append("\\n"); break;
        case '\r': out.append("\\r"); break;
        case '\t': out.append("\\t"); break;
        default:
          if (c < 0x20) {
            out.append(String.format("\\u%04x", (int) c));
          } else {
            out.append(c);
          }
      }
    }
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
    if (iscondensed(store)) {
      throw new IllegalArgumentException(CONDENSE_IMMUTABLE);
    }

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

            if (typify(v) == typify(tval)) {
              cur[pI] = tval;
            } else if ((typify(v) & T_instance) == 0) {
              // Otherwise the override wins: a plain node is copied, taking
              // nothing from the destination, so no later merge writes into it.
              cur[pI] = islist(v) ? new ArrayList<>() : new LinkedHashMap<String, Object>();
              dst[pI] = null;
            } else {
              // A class instance is kept as is, so there is nothing to descend.
              cur[pI] = v;
              return null;
            }
          }
          return v;
        };

        WalkApply after = (key, _val, parent, path) -> {
          int cI = path.size();
          if (key == null || cI <= 0) {
            return cur[0];
          }
          cur[cI - 1] = setprop(cur[cI - 1], key, cur[cI]);
          // walk writes this back into the override, so it is the override's
          // own child, leaving the override unchanged.
          return lookup(parent, key);
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
    return getpath(store, path, (Map<String, Object>) null);
  }

  public static Object getpath(Object store, Object path, Map<String, Object> inj) {
    List<String> parts = pathParts(path);
    if (null == parts) {
      return UNDEF;
    }

    // A condensed store answers as the node it was built from, touching only
    // the nodes on the path. A base changes what the path resolves against,
    // so that read needs the materialised store.
    if (iscondensed(store)) {
      if (null == inj || UNDEF == getprop(inj, "base")) {
        Object found = condenseMaterialise(store, condenseResolve(store, condenseRoot(store), parts));
        // Group A: a stored null reads as absent, as it does through getprop.
        return null == found ? UNDEF : found;
      }
      store = expand(store);
    }

    Object val = getpathInner(store, path, parts, inj);
    if (inj != null) {
      Object handlerObj = inj.get("handler");
      if (handlerObj instanceof Injector h) {
        String ref = pathifyForHandler(path);
        // The Injector signature requires an Injection instance; this Map-view
        // overload is only used by tests that supply Map-shaped state, so wrap
        // a synthetic Injection that exposes the same fields.
        Injection synth = new Injection(val, null);
        synth.errs = new ArrayList<>();
        if (inj.get("dparent") != null) synth.dparent = inj.get("dparent");
        if (inj.get("meta") instanceof Map<?, ?> mm) synth.meta = (Map<String, Object>) mm;
        if (inj.get("key") != null) synth.key = Objects.toString(inj.get("key"));
        val = h.apply(synth, val, ref, store);
      }
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

  // A new list, so the caller's path is never rewritten; null when it is no
  // path, or names a part that is neither a string nor a number.
  private static List<String> pathParts(Object path) {
    if (path instanceof String s) {
      if (s.isEmpty()) {
        return new ArrayList<>(List.of(S_MT));
      }
      return new ArrayList<>(List.of(s.split("\\.", -1)));
    }
    if (path instanceof Number n) {
      return new ArrayList<>(List.of(jsString(n)));
    }
    if (path instanceof List<?> l) {
      List<String> out = new ArrayList<>();
      for (Object x : l) {
        if (x instanceof String s) {
          out.add(s);
        } else if (x instanceof Number n) {
          out.add(jsString(n));
        } else {
          return null;
        }
      }
      return out;
    }
    return null;
  }

  private static Object getpathInner(Object store, Object pathOrig, List<String> parts, Map<String, Object> inj) {
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

        for (int pI = 0; val != null && val != UNDEF && pI < numparts; pI++) {
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
    return inject(val, store, (Injection) null);
  }

  /**
   * Map-based overload retained for back-compat with the legacy hand-rolled
   * transform/validate paths. Builds an {@link Injection} from the map's
   * {@code modify}, {@code extra}, {@code meta}, {@code handler}, {@code base},
   * {@code dparent}, {@code dpath} entries and delegates to
   * {@link #inject(Object, Object, Injection)}.
   */
  public static Object inject(Object val, Object store, Map<String, Object> injMap) {
    if (injMap == null) {
      return inject(val, store, (Injection) null);
    }
    Injection injdef = new Injection(val, null);
    injdef.prior = null; // partial — signals "build fresh state in inject()"
    if (injMap.get("base") instanceof String b) injdef.base = b;
    if (injMap.get("dparent") != null) injdef.dparent = injMap.get("dparent");
    if (injMap.get("dpath") instanceof List<?> dp) injdef.dpath = (List<String>) dp;
    if (injMap.get("meta") instanceof Map<?, ?> meta) injdef.meta = (Map<String, Object>) meta;
    if (injMap.get("modify") instanceof Modify mod) injdef.modify = mod;
    if (injMap.get("extra") != null) injdef.extra = injMap.get("extra");
    if (injMap.get("handler") instanceof Injector h) injdef.handler = h;
    return inject(val, store, injdef);
  }

  /**
   * Inject values from a {@code store} into a JSON-shaped {@code val}. Mirrors
   * TS {@code inject} (StructUtility.ts lines 1264–1387) using the
   * {@link Injection} state machine introduced in step 4.
   *
   * <p>For each map/list child the three injection phases run in order:
   * {@link #M_KEYPRE} (key transform pre-descent), {@link #M_VAL} (recurse
   * into the value), then {@link #M_KEYPOST} (key transform post-descent).
   * Map keys are partitioned: non-{@code $} keys before {@code $}-prefixed
   * keys, so transform commands run after data fields are resolved.
   */
  public static Object inject(Object val, Object store, Injection injdef) {
    Injection inj;
    boolean isInitial = injdef == null || injdef.prior == null;

    if (isInitial) {
      Map<String, Object> wrapper = new LinkedHashMap<>();
      wrapper.put(S_DTOP, val);
      inj = new Injection(val, wrapper);
      inj.dparent = store;
      Object errsRaw = getprop(store, S_DERRS, UNDEF);
      if (errsRaw instanceof List<?> el) {
        inj.errs = (List<Object>) el;
      }
      inj.meta.put("__d", 0);

      if (injdef != null) {
        if (injdef.modify != null) inj.modify = injdef.modify;
        if (injdef.extra != null) inj.extra = injdef.extra;
        if (injdef.meta != null) inj.meta = injdef.meta;
        if (injdef.handler != null) inj.handler = injdef.handler;
        if (injdef.base != null) inj.base = injdef.base;
        if (injdef.dparent != UNDEF) inj.dparent = injdef.dparent;
      }
      if (inj.handler == null) {
        inj.handler = _injecthandler;
      }
      // Top-level wrapper participates in nodes stack so setval can climb.
      inj.nodes.clear();
      inj.nodes.add(wrapper);
    } else {
      inj = injdef;
    }

    inj.descend();

    if (isnode(val)) {
      List<String> nodekeys = keysof(val);

      if (ismap(val)) {
        // $-suffix ordering: non-$ keys first, then $ keys.
        // Critical for transform command ordering (TS lines 1305-1310).
        List<String> nonDollar = new ArrayList<>();
        List<String> dollar = new ArrayList<>();
        for (String k : nodekeys) {
          if (k.contains("$")) {
            dollar.add(k);
          } else {
            nonDollar.add(k);
          }
        }
        nodekeys = new ArrayList<>(nonDollar.size() + dollar.size());
        nodekeys.addAll(nonDollar);
        nodekeys.addAll(dollar);
      }

      for (int nkI = 0; nkI < nodekeys.size(); nkI++) {
        Injection childinj = inj.child(nkI, nodekeys);
        String nodekey = childinj.key;
        childinj.mode = M_KEYPRE;

        Object prekey = _injectstr(nodekey, store, childinj);
        nkI = childinj.keyI;
        nodekeys = childinj.keys;

        if (prekey != UNDEF) {
          childinj.val = getprop(val, prekey);
          childinj.mode = M_VAL;
          inject(childinj.val, store, childinj);

          nkI = childinj.keyI;
          nodekeys = childinj.keys;

          childinj.mode = M_KEYPOST;
          _injectstr(nodekey, store, childinj);

          nkI = childinj.keyI;
          nodekeys = childinj.keys;
        }
      }
    } else if (val instanceof String s) {
      inj.mode = M_VAL;
      Object newVal = _injectstr(s, store, inj);
      if (newVal != SKIP) {
        inj.setval(newVal);
      }
      val = newVal;
    }

    if (inj.modify != null && val != SKIP) {
      Object mkey = inj.key;
      Object mparent = inj.parent;
      Object mval = getprop(mparent, mkey);
      inj.modify.apply(mval, mkey, mparent, inj, store);
    }

    inj.val = val;
    // Group B: the top-level result must preserve a stored JSON null (e.g.
    // injecting `$NULL`), so read the raw value. Mirrors TS _lookup(parent,$TOP).
    return lookup(inj.parent, S_DTOP);
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
      StringBuilder sb = new StringBuilder();
      _jsonifyInner(found, sb, 0, 0, new IdentityHashMap<>());
      return sb.toString();
    }
    return stringify(found);
  }

  // ===========================================================================
  // Inject substrate helpers (step 5a — declared here, wired in step 6)
  // ===========================================================================

  /**
   * Build a type-mismatch error message for {@link #validate}.
   * Mirrors TS {@code _invalidTypeMsg} (StructUtility.ts lines 2759–2771).
   *
   * @param path  ancestor key chain
   * @param needtype expected type (human name)
   * @param vt    actual type bit-flag
   * @param v     actual value
   * @param whence optional error code (currently ignored; reserved for debug)
   */
  static String _invalidTypeMsg(Object path, String needtype, int vt, Object v, String whence) {
    String vs = (v == null || v == UNDEF) ? "no value" : stringify(v);
    StringBuilder sb = new StringBuilder("Expected ");
    if (path instanceof List<?> p && p.size() > 1) {
      sb.append("field ").append(pathify(path, 1)).append(" to be ");
    }
    sb.append(needtype).append(", but found ");
    if (v != null && v != UNDEF) {
      sb.append(typename(vt)).append(": ");
    }
    sb.append(vs).append(".");
    return sb.toString();
  }

  /**
   * Adapter overload: dispatches {@link #getpath(Object, Object, Map)} given an
   * {@link Injection} value. Builds a transient {@link Map} view from the
   * injection's {@code base}, {@code dparent}, {@code dpath}, {@code meta}, and
   * {@code key} fields. The injection's {@code handler} (an {@link Injector}) is
   * applied <em>after</em> the path lookup so that step 6's three-phase machine
   * can hook command dispatch.
   */
  public static Object getpath(Object store, Object path, Injection inj) {
    // No path, or a condensed read without a base, returns before any handler
    // runs, as in canonical.
    if (inj == null || null == pathParts(path) || (inj.base == null && iscondensed(store))) {
      return getpath(store, path, (Map<String, Object>) null);
    }
    Map<String, Object> view = new LinkedHashMap<>();
    if (inj.base != null) view.put("base", inj.base);
    // Always set dparent (even UNDEF) so getpathInner distinguishes "no
    // dparent given" from "dparent given but absent".
    view.put("dparent", inj.dparent);
    if (inj.dpath != null) view.put("dpath", inj.dpath);
    if (inj.meta != null) view.put("meta", inj.meta);
    if (inj.key != null) view.put("key", inj.key);
    Object val = getpath(store, path, view);
    if (inj.handler != null) {
      String ref = path == null ? "" : pathify(path);
      val = inj.handler.apply(inj, val, ref, store);
    }
    return val;
  }

  /**
   * Inject values from a data store into a string. Internal — not part of the
   * public API. Mirrors TS {@code _injectstr} (StructUtility.ts lines 2840–2901).
   *
   * <p>If {@code val} is a "full" injection (whole string is a backtick path),
   * returns the resolved value with its original type. Otherwise replaces every
   * partial {@code `...`} reference inline, then calls {@code inj.handler} on
   * the assembled string for command dispatch.
   */
  static Object _injectstr(String val, Object store, Injection inj) {
    if (val == null || val.isEmpty()) {
      return S_MT;
    }
    Matcher full = R_INJECT_FULL.matcher(val);
    if (full.matches()) {
      if (inj != null) {
        inj.full = true;
      }
      String pathref = full.group(1);
      if (pathref != null && pathref.length() > 3) {
        pathref = R_BT_ESCAPE.matcher(pathref).replaceAll("`");
        pathref = R_DS_ESCAPE.matcher(pathref).replaceAll("\\$");
      }
      return getpath(store, pathref, inj);
    }

    Matcher m = R_INJECT_PART.matcher(val);
    StringBuilder out = new StringBuilder();
    int cursor = 0;
    while (m.find()) {
      out.append(val, cursor, m.start());
      String ref = m.group(1);
      if (ref != null && ref.length() > 3) {
        ref = R_BT_ESCAPE.matcher(ref).replaceAll("`");
        ref = R_DS_ESCAPE.matcher(ref).replaceAll("\\$");
      }
      if (inj != null) {
        inj.full = false;
      }
      Object found = getpath(store, ref, inj);
      out.append(injectPartialText(found));
      cursor = m.end();
    }
    out.append(val.substring(cursor));
    Object outVal = out.toString();
    if (inj != null && inj.handler != null) {
      inj.full = true;
      outVal = inj.handler.apply(inj, outVal, val, store);
    }
    return outVal;
  }

  /**
   * Validate that an injector is placed in an allowed mode and parent type.
   * Mirrors TS {@code checkPlacement} (StructUtility.ts lines 2920–2943).
   */
  public static boolean checkPlacement(int modes, String ijname, int parentTypes, Injection inj) {
    if ((modes & inj.mode) == 0) {
      List<String> allowed = new ArrayList<>();
      for (int m : new int[] {M_KEYPRE, M_KEYPOST, M_VAL}) {
        if ((modes & m) != 0) {
          allowed.add(PLACEMENT.get(m));
        }
      }
      inj.errs.add(
          "$"
              + ijname
              + ": invalid placement as "
              + PLACEMENT.get(inj.mode)
              + ", expected: "
              + String.join(",", allowed)
              + ".");
      return false;
    }
    if (parentTypes != 0) {
      int ptype = typify(inj.parent);
      if ((parentTypes & ptype) == 0) {
        inj.errs.add(
            "$"
                + ijname
                + ": invalid placement in parent "
                + typename(ptype)
                + ", expected: "
                + typename(parentTypes)
                + ".");
        return false;
      }
    }
    return true;
  }

  /**
   * Validate and unpack injector argument types. Returns an array of size
   * {@code argTypes.length + 1}: index 0 is the error message (or {@code null}),
   * indices 1..N are the validated args. Mirrors TS {@code injectorArgs}.
   */
  public static Object[] injectorArgs(int[] argTypes, List<Object> args) {
    int n = argTypes.length;
    Object[] found = new Object[n + 1];
    found[0] = null;
    for (int i = 0; i < n; i++) {
      Object arg = i < args.size() ? args.get(i) : UNDEF;
      int argType = typify(arg);
      if ((argTypes[i] & argType) == 0) {
        found[0] =
            "invalid argument: "
                + stringify(arg, 22)
                + " ("
                + typename(argType)
                + " at position "
                + (1 + i)
                + ") is not of type: "
                + typename(argTypes[i])
                + ".";
        break;
      }
      found[i + 1] = arg;
    }
    return found;
  }

  /**
   * Recurse {@link #inject} into a child node sharing the current injection's
   * state stack. Used by {@code $FORMAT} / {@code $APPLY} (and other injectors
   * that need to resolve a sub-spec). Mirrors TS {@code injectChild}.
   */
  public static Injection injectChild(Object child, Object store, Injection inj) {
    Injection cinj = inj;
    if (inj.prior != null) {
      if (inj.prior.prior != null) {
        cinj = inj.prior.prior.child(inj.prior.keyI, inj.prior.keys);
        cinj.val = child;
        setprop(cinj.parent, inj.prior.key, child);
      } else {
        cinj = inj.prior.child(inj.keyI, inj.keys);
        cinj.val = child;
        setprop(cinj.parent, inj.key, child);
      }
    }
    inject(child, store, cinj);
    return cinj;
  }

  /**
   * Default {@link Injector}: when a backtick reference resolves to a function
   * value (a {@code $NAME} command), call it. Otherwise pass-through, except
   * that in {@link #M_VAL} mode with a "full" injection, set the resolved
   * value back onto {@code inj.parent[inj.key]} to keep the spec tree
   * consistent. Mirrors TS {@code _injecthandler}.
   */
  static final Injector _injecthandler =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) {
          return val;
        }
        Object out = val;
        boolean iscmd = isfunc(val) && (ref == null || ref.startsWith("$"));
        if (iscmd) {
          if (val instanceof Injector ij) {
            out = ij.apply(inj, val, ref, store);
          } else if (val instanceof Function<?, ?> f) {
            out = ((Function<Object, Object>) f).apply(inj);
          } else if (val instanceof Supplier<?> s) {
            out = s.get();
          }
        } else if (inj.mode == M_VAL && inj.full) {
          inj.setval(val);
        }
        return out;
      };

  // ===========================================================================
  // Transform injectors (step 8)
  // ===========================================================================
  // Reference implementations of the 11 TS transform commands. These are
  // ported from TS lines 1393–1896 and exposed as public static Injector
  // fields. The current public transform(data, spec, options) below remains
  // the hand-rolled implementation — these injectors are wired in via a
  // future step 9 transform() rewrite.

  /** $DELETE: drop the current key. Mirrors TS lines 1393–1396. */
  public static final Injector transform_DELETE =
      (injObj, val, ref, store) -> {
        if (injObj instanceof Injection inj) {
          inj.setval(UNDEF);
        }
        return UNDEF;
      };

  /** $COPY: copy the value at the current key from {@code dparent}. */
  public static final Injector transform_COPY =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        if (!checkPlacement(M_VAL, "COPY", T_any, inj)) return UNDEF;
        // Group B: $COPY copies the raw stored value, preserving JSON null.
        Object out = lookup(inj.dparent, inj.key);
        inj.setval(out);
        return out;
      };

  /** $KEY: emit the parent key, optionally renamed via {@code `$KEY`}. */
  public static final Injector transform_KEY =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        if (inj.mode != M_VAL) return UNDEF;
        // Group B: the $KEY/$ANNO spec markers are read raw (TS _lookup).
        Object keyspec = lookup(inj.parent, "`$KEY`");
        if (keyspec != UNDEF) {
          delprop(inj.parent, "`$KEY`");
          return getprop(inj.dparent, keyspec);
        }
        Object anno = lookup(inj.parent, "`$ANNO`");
        Object annoKey = lookup(anno, "KEY");
        // TS: _lookup(_lookup(parent,$ANNO),KEY) ?? getelem(path,-2) — fall
        // back only when absent or JSON null.
        return (annoKey == UNDEF || annoKey == null) ? getelem(inj.path, -2) : annoKey;
      };

  /** $ANNO: drop the annotation marker. */
  public static final Injector transform_ANNO =
      (injObj, val, ref, store) -> {
        if (injObj instanceof Injection inj) {
          delprop(inj.parent, "`$ANNO`");
        }
        return UNDEF;
      };

  /** $MERGE: deep-merge a list of objects over the current parent. */
  public static final Injector transform_MERGE =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        if (inj.mode == M_KEYPRE) return inj.key;
        if (inj.mode != M_KEYPOST) return UNDEF;

        Object args = getprop(inj.parent, inj.key);
        List<Object> argList;
        if (args instanceof List<?> al) {
          argList = (List<Object>) al;
        } else {
          argList = new ArrayList<>();
          argList.add(args);
        }
        inj.setval(UNDEF);

        List<Object> mergelist = new ArrayList<>();
        mergelist.add(inj.parent);
        mergelist.addAll(argList);
        mergelist.add(clone(inj.parent));
        merge(mergelist);
        return inj.key;
      };

  /** Format functions used by {@link #transform_FORMAT} ($FORMAT command). */
  public static final Map<String, WalkApply> FORMATTER;

  /** JS-style scalar→string: integer-valued doubles render without {@code .0}. */
  private static String jsString(Object v) {
    if (v == null) return "null";
    if (v instanceof Number n) {
      double d = n.doubleValue();
      if (Double.isFinite(d) && Math.floor(d) == d) {
        return Long.toString((long) d);
      }
      return n.toString();
    }
    if (v instanceof Boolean b) return b ? "true" : "false";
    return v.toString();
  }

  static {
    Map<String, WalkApply> f = new LinkedHashMap<>();
    f.put("identity", (k, v, p, t) -> v);
    f.put("upper", (k, v, p, t) -> isnode(v) ? v : jsString(v).toUpperCase(Locale.ROOT));
    f.put("lower", (k, v, p, t) -> isnode(v) ? v : jsString(v).toLowerCase(Locale.ROOT));
    f.put("string", (k, v, p, t) -> isnode(v) ? v : jsString(v));
    f.put(
        "number",
        (k, v, p, t) -> {
          if (isnode(v)) return v;
          try {
            double d = Double.parseDouble("" + v);
            if (Double.isNaN(d)) return 0L;
            if (Math.floor(d) == d) return (long) d;
            return d;
          } catch (Exception e) {
            return 0L;
          }
        });
    f.put(
        "integer",
        (k, v, p, t) -> {
          if (isnode(v)) return v;
          try {
            return (long) Double.parseDouble("" + v);
          } catch (Exception e) {
            return 0L;
          }
        });
    f.put(
        "concat",
        (k, v, p, t) -> {
          if (k != null || !islist(v)) return v;
          StringBuilder sb = new StringBuilder();
          for (List<Object> item : items(v)) {
            Object x = item.get(1);
            if (!isnode(x)) sb.append(jsString(x));
          }
          return sb.toString();
        });
    FORMATTER = Collections.unmodifiableMap(f);
  }

  /** $FORMAT: walk a sub-spec applying a named formatter. */
  public static final Injector transform_FORMAT =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        if (inj.keys != null && !inj.keys.isEmpty()) {
          // Slice keys to first one to prevent further processing.
          List<String> keep = new ArrayList<>();
          if (!inj.keys.isEmpty()) keep.add(inj.keys.get(0));
          inj.keys.clear();
          inj.keys.addAll(keep);
        }
        if (inj.mode != M_VAL) return UNDEF;

        // Group B: $FORMAT args ['`$FORMAT`','name',child] are read raw so a
        // null child reaches the formatter (TS _lookup(parent,1/2)).
        Object name = lookup(inj.parent, 1);
        Object child = lookup(inj.parent, 2);

        Object tkey = getelem(inj.path, -2);
        Object target = getelem(inj.nodes, -2, getelem(inj.nodes, -1));

        Injection cinj = injectChild(child, store, inj);
        Object resolved = cinj.val;

        WalkApply formatter =
            name instanceof WalkApply wa ? wa : FORMATTER.get(Objects.toString(name, ""));
        if (formatter == null) {
          inj.errs.add("$FORMAT: unknown format: " + name + ".");
          return UNDEF;
        }
        Object out = walk(resolved, formatter);
        setprop(target, tkey, out);
        return out;
      };

  /** $APPLY: call a custom function on a resolved sub-spec value. */
  public static final Injector transform_APPLY =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        if (!checkPlacement(M_VAL, "APPLY", T_list, inj)) return UNDEF;

        List<Object> args = new ArrayList<>();
        if (inj.parent instanceof List<?> pl && pl.size() > 1) {
          for (int i = 1; i < pl.size(); i++) args.add(pl.get(i));
        }
        Object[] checked = injectorArgs(new int[] {T_function, T_any}, args);
        if (checked[0] != null) {
          inj.errs.add("$APPLY: " + checked[0]);
          return UNDEF;
        }
        Object apply = checked[1];
        Object child = checked[2];

        Object tkey = getelem(inj.path, -2);
        Object target = getelem(inj.nodes, -2, getelem(inj.nodes, -1));

        Injection cinj = injectChild(child, store, inj);
        Object resolved = cinj.val;

        Object out;
        if (apply instanceof Function<?, ?> fn) {
          out = ((Function<Object, Object>) fn).apply(resolved);
        } else {
          out = UNDEF;
        }
        setprop(target, tkey, out);
        return out;
      };

  /**
   * $EACH: convert a node into a list by cloning the child template per
   * source entry. Format: {@code ['`$EACH`', '<source-path>', child-template]}.
   * Mirrors TS lines 1484–1571.
   */
  public static final Injector transform_EACH =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        if (!checkPlacement(M_VAL, "EACH", T_list, inj)) return UNDEF;

        // Mutate inj.keys to keep only first element (prevent further key processing).
        if (inj.keys.size() > 1) {
          inj.keys.subList(1, inj.keys.size()).clear();
        }

        // Args from parent list after [0] = $EACH marker.
        List<Object> args = new ArrayList<>();
        if (inj.parent instanceof List<?> pl) {
          for (int i = 1; i < pl.size(); i++) args.add(pl.get(i));
        }
        Object[] checked = injectorArgs(new int[] {T_string, T_any}, args);
        if (checked[0] != null) {
          inj.errs.add("$EACH: " + checked[0]);
          return UNDEF;
        }
        String srcpath = (String) checked[1];
        Object child = checked[2];

        // Source data via getpath against the injection's base store.
        Object srcstore = getprop(store, inj.base, store);
        Object src = getpath(srcstore, srcpath, inj);
        int srctype = typify(src);

        Object tkey = getelem(inj.path, -2);
        Object target = getelem(inj.nodes, -2);
        if (target == UNDEF) target = getelem(inj.nodes, -1);

        // Build tval as cloned child templates per source entry.
        List<Object> tval = new ArrayList<>();
        if ((T_list & srctype) != 0 && src instanceof List<?> sl) {
          for (int i = 0; i < sl.size(); i++) {
            tval.add(clone(child));
          }
        } else if ((T_map & srctype) != 0 && src instanceof Map<?, ?> sm) {
          for (Map.Entry<?, ?> e : sm.entrySet()) {
            Object cloned = clone(child);
            Map<String, Object> annoMap = new LinkedHashMap<>();
            Map<String, Object> keyMap = new LinkedHashMap<>();
            keyMap.put("KEY", Objects.toString(e.getKey()));
            annoMap.put("`$ANNO`", keyMap);
            List<Object> mergeArgs = new ArrayList<>();
            mergeArgs.add(cloned);
            mergeArgs.add(annoMap);
            tval.add(merge(mergeArgs, 1));
          }
        }

        Object rval = new ArrayList<>();

        if (size(tval) > 0) {
          // tcur: list of source values for relative ref binding.
          Object tcur;
          if (src instanceof List<?> sl) {
            tcur = new ArrayList<>(sl);
          } else if (src instanceof Map<?, ?> sm) {
            tcur = new ArrayList<>(sm.values());
          } else {
            tcur = UNDEF;
          }

          Object ckey = getelem(inj.path, -2);
          String ckeyStr = strkey(ckey);

          Object tpathRaw = slice(inj.path, -1, null);
          List<String> tpath =
              tpathRaw instanceof List<?> tpl
                  ? new ArrayList<>((List<String>) tpl)
                  : new ArrayList<>();

          List<String> dpath = new ArrayList<>();
          dpath.add(S_DTOP);
          if (srcpath != null && !srcpath.isEmpty()) {
            for (String part : srcpath.split("\\.", -1)) dpath.add(part);
          }
          dpath.add("$:" + ckeyStr);

          // Wrap tcur in the parent key structure so relative paths work.
          Map<String, Object> tcurMap = new LinkedHashMap<>();
          tcurMap.put(ckeyStr, tcur);
          Object tcurOut = tcurMap;

          if (size(tpath) > 1) {
            Object pkey = getelem(inj.path, -3, S_DTOP);
            String pkeyStr = strkey(pkey);
            Map<String, Object> wrap = new LinkedHashMap<>();
            wrap.put(pkeyStr, tcurOut);
            tcurOut = wrap;
            dpath.add("$:" + pkeyStr);
          }

          List<String> singleKey = new ArrayList<>();
          singleKey.add(ckeyStr);
          Injection tinj = inj.child(0, singleKey);
          tinj.path = tpath;
          Object slicedNodes = slice(inj.nodes, -1, null);
          tinj.nodes =
              slicedNodes instanceof List<?> snl
                  ? new ArrayList<>((List<Object>) snl)
                  : new ArrayList<>();

          tinj.parent = getelem(tinj.nodes, -1);
          setprop(tinj.parent, ckey, tval);

          tinj.val = tval;
          tinj.dpath = dpath;
          tinj.dparent = tcurOut;

          inject(tval, store, tinj);
          rval = tinj.val;
        }

        setprop(target, tkey, rval);
        return rval instanceof List<?> rl && !rl.isEmpty() ? rl.get(0) : UNDEF;
      };

  /**
   * $PACK: convert a list/map into a keyed map. Format:
   * {@code {'`$PACK`': ['<source-path>', child-template]}}. Mirrors TS lines 1576–1707.
   */
  public static final Injector transform_PACK =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        if (!checkPlacement(M_KEYPRE, "PACK", T_map, inj)) return UNDEF;

        Object args = getprop(inj.parent, inj.key);
        List<Object> argList = new ArrayList<>();
        if (args instanceof List<?> al) {
          argList.addAll(al);
        }
        Object[] checked = injectorArgs(new int[] {T_string, T_any}, argList);
        if (checked[0] != null) {
          inj.errs.add("$PACK: " + checked[0]);
          return UNDEF;
        }
        String srcpath = (String) checked[1];
        Object origchildspec = checked[2];

        Object tkey = getelem(inj.path, -2);
        int pathsize = size(inj.path);
        Object target = getelem(inj.nodes, pathsize - 2);
        if (target == UNDEF) target = getelem(inj.nodes, pathsize - 1);

        Object srcstore = getprop(store, inj.base, store);
        Object src = getpath(srcstore, srcpath, inj);

        // Prepare source as a list of nodes.
        List<Object> srcList = null;
        if (src instanceof List<?> sl) {
          srcList = new ArrayList<>(sl);
        } else if (src instanceof Map<?, ?> sm) {
          srcList = new ArrayList<>();
          for (Map.Entry<?, ?> e : sm.entrySet()) {
            Object node = e.getValue();
            if (isnode(node)) {
              Map<String, Object> annoMap = new LinkedHashMap<>();
              annoMap.put("KEY", Objects.toString(e.getKey()));
              setprop(node, "`$ANNO`", annoMap);
              srcList.add(node);
            }
          }
        }

        if (srcList == null) {
          return UNDEF;
        }

        // Extract `$KEY` and `$VAL` from origchildspec (if it's a map).
        Object keypath = UNDEF;
        Object childspec = origchildspec;
        Object child = origchildspec;
        if (origchildspec instanceof Map<?, ?>) {
          keypath = getprop(origchildspec, "`$KEY`", UNDEF);
          delprop(origchildspec, "`$KEY`");
          child = getprop(origchildspec, "`$VAL`", origchildspec);
        }
        // After delprop the value may have been mutated.
        final Object keypathFinal = keypath;
        final Object childFinal = child;

        // Build parallel target object.
        Map<String, Object> tval = new LinkedHashMap<>();

        for (int i = 0; i < srcList.size(); i++) {
          Object item = srcList.get(i);
          // srcnode may be any value; for keypath==UNDEF, use the source index/key.
          String outKey;
          if (keypathFinal == UNDEF) {
            // For list source, use the iteration index.
            // For map source, srcList came from values() so we lost the key —
            // fall back to the item's $KEY annotation (set during list build).
            if (item instanceof Map<?, ?> imap2 && imap2.containsKey(S_DKEY)) {
              outKey = Objects.toString(imap2.get(S_DKEY), "");
            } else {
              outKey = String.valueOf(i);
            }
          } else if (keypathFinal instanceof String ks && ks.startsWith("`")) {
            // Inject the key spec against {$TOP: srcnode} merged into store.
            List<Object> mergeList = new ArrayList<>();
            mergeList.add(new LinkedHashMap<String, Object>());
            mergeList.add(store);
            Map<String, Object> topMap = new LinkedHashMap<>();
            topMap.put(S_DTOP, item);
            mergeList.add(topMap);
            Object merged = merge(mergeList, 1);
            outKey = Objects.toString(inject(keypathFinal, merged), "");
          } else {
            Object kv = getpath(item, keypathFinal, inj);
            outKey = Objects.toString(kv, "");
          }

          Object tchild = clone(childFinal);
          setprop(tval, outKey, tchild);

          // Preserve $ANNO if present.
          Object anno = getprop(item, "`$ANNO`", UNDEF);
          if (anno == UNDEF) {
            delprop(tchild, "`$ANNO`");
          } else {
            setprop(tchild, "`$ANNO`", anno);
          }
        }

        Map<String, Object> rval = new LinkedHashMap<>();

        if (!isempty(tval)) {
          // Build parallel source map keyed by outKey for relative ref binding.
          Map<String, Object> tsrc = new LinkedHashMap<>();
          for (int i = 0; i < srcList.size(); i++) {
            Object item = srcList.get(i);
            String kn;
            if (keypathFinal == UNDEF) {
              kn = String.valueOf(i);
            } else if (keypathFinal instanceof String ks && ks.startsWith("`")) {
              List<Object> mergeList = new ArrayList<>();
              mergeList.add(new LinkedHashMap<String, Object>());
              mergeList.add(store);
              Map<String, Object> topMap = new LinkedHashMap<>();
              topMap.put(S_DTOP, item);
              mergeList.add(topMap);
              Object merged = merge(mergeList, 1);
              kn = Objects.toString(inject(keypathFinal, merged), "");
            } else {
              Object kv = getpath(item, keypathFinal, inj);
              kn = Objects.toString(kv, "");
            }
            setprop(tsrc, kn, item);
          }

          Object tpathRaw = slice(inj.path, -1, null);
          List<String> tpath =
              tpathRaw instanceof List<?> tpl
                  ? new ArrayList<>((List<String>) tpl)
                  : new ArrayList<>();

          Object ckey = getelem(inj.path, -2);
          String ckeyStr = strkey(ckey);

          List<String> dpath = new ArrayList<>();
          dpath.add(S_DTOP);
          if (srcpath != null && !srcpath.isEmpty()) {
            for (String part : srcpath.split("\\.", -1)) dpath.add(part);
          }
          dpath.add("$:" + ckeyStr);

          Map<String, Object> tcur = new LinkedHashMap<>();
          tcur.put(ckeyStr, tsrc);
          Object tcurOut = tcur;

          if (size(tpath) > 1) {
            Object pkey = getelem(inj.path, -3, S_DTOP);
            String pkeyStr = strkey(pkey);
            Map<String, Object> wrap = new LinkedHashMap<>();
            wrap.put(pkeyStr, tcurOut);
            tcurOut = wrap;
            dpath.add("$:" + pkeyStr);
          }

          List<String> singleKey = new ArrayList<>();
          singleKey.add(ckeyStr);
          Injection tinj = inj.child(0, singleKey);
          tinj.path = tpath;
          Object slicedNodes = slice(inj.nodes, -1, null);
          tinj.nodes =
              slicedNodes instanceof List<?> snl
                  ? new ArrayList<>((List<Object>) snl)
                  : new ArrayList<>();

          tinj.parent = getelem(tinj.nodes, -1);
          tinj.val = tval;
          tinj.dpath = dpath;
          tinj.dparent = tcurOut;

          inject(tval, store, tinj);
          if (tinj.val instanceof Map<?, ?> rm) {
            rval = new LinkedHashMap<>();
            for (Map.Entry<?, ?> e : rm.entrySet()) {
              rval.put(Objects.toString(e.getKey()), e.getValue());
            }
          }
        }

        setprop(target, tkey, rval);
        // Drop transform key.
        return UNDEF;
      };

  /**
   * $REF: resolve a named reference within the original spec, enabling
   * recursive transformations. Format: {@code ['`$REF`', '<spec-path>']}.
   * Mirrors TS lines 1713–1785.
   */
  public static final Injector transform_REF =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        if (inj.mode != M_VAL) return UNDEF;

        // Group B: $REF arg ['`$REF`','ref-path'] read raw (TS _lookup(parent,1)).
        Object refpath = lookup(inj.parent, 1);
        inj.keyI = size(inj.keys);

        // $SPEC is stored as a Supplier<Object> that returns the original spec.
        Object specHolder = getprop(store, S_DSPEC);
        Object spec;
        if (specHolder instanceof Supplier<?> sup) {
          spec = sup.get();
        } else {
          spec = specHolder;
        }

        Object dpathRaw = slice(inj.path, 1, null);
        List<String> dpath =
            dpathRaw instanceof List<?> dl
                ? new ArrayList<>((List<String>) dl)
                : new ArrayList<>();
        Injection refInj = new Injection(null, null);
        refInj.dpath = dpath;
        refInj.dparent = getpath(spec, dpath);
        refInj.handler = _injecthandler;
        Object refResolved = getpath(spec, refpath, refInj);

        Object tref = clone(refResolved);

        boolean[] hasSubRef = {false};
        if (isnode(tref)) {
          walk(
              tref,
              (k, v, p, t) -> {
                if ("`$REF`".equals(v)) hasSubRef[0] = true;
                return v;
              });
        }

        Object cpathRaw = slice(inj.path, -3, null);
        List<String> cpath =
            cpathRaw instanceof List<?> cl
                ? new ArrayList<>((List<String>) cl)
                : new ArrayList<>();
        Object tpathRaw = slice(inj.path, -1, null);
        List<String> tpath =
            tpathRaw instanceof List<?> tpl
                ? new ArrayList<>((List<String>) tpl)
                : new ArrayList<>();
        Object tval = getpath(store, tpath);
        Object rval = UNDEF;

        if (!hasSubRef[0] || tval != UNDEF) {
          Object lastKey = getelem(tpath, -1);
          List<String> singleKey = new ArrayList<>();
          singleKey.add(strkey(lastKey));
          Injection tinj = inj.child(0, singleKey);
          tinj.path = tpath;
          Object slicedNodes = slice(inj.nodes, -1, null);
          tinj.nodes =
              slicedNodes instanceof List<?> snl
                  ? new ArrayList<>((List<Object>) snl)
                  : new ArrayList<>();
          tinj.parent = getelem(inj.nodes, -2);
          tinj.val = tref;

          List<String> flatCpath = new ArrayList<>(cpath);
          tinj.dpath = flatCpath;
          tinj.dparent = getpath(store, cpath);

          inject(tref, store, tinj);
          rval = tinj.val;
        }

        Object grandparent = inj.setval(rval, 2);
        if (islist(grandparent) && inj.prior != null) {
          inj.prior.keyI--;
        }

        return val;
      };

  public static Object transform(Object data, Object spec) {
    return transform(data, spec, (Map<String, Object>) null);
  }

  /**
   * TS-faithful transform: clone the spec and inject it against a store
   * containing the {@code transform_*} command injectors plus {@code $TOP},
   * {@code $SPEC}, {@code $BT}, {@code $DS}, {@code $WHEN}. Mirrors TS
   * {@code transform} (StructUtility.ts lines 1902–1973).
   */
  public static Object transform(Object data, Object spec, Map<String, Object> options) {
    final Object origspec = spec;
    Object workspec = clone(origspec);

    Object extraRaw = options == null ? null : options.get("extra");
    Object modifyRaw = options == null ? null : options.get("modify");
    Object handlerRaw = options == null ? null : options.get("handler");
    Object metaRaw = options == null ? null : options.get("meta");
    Object errsRaw = options == null ? null : options.get("errs");

    boolean collect = errsRaw instanceof List<?>;
    List<Object> errs = collect ? (List<Object>) errsRaw : new ArrayList<>();

    // Split extra into commands ($-keyed) and data (everything else).
    Map<String, Object> extraTransforms = new LinkedHashMap<>();
    Map<String, Object> extraData = new LinkedHashMap<>();
    if (extraRaw instanceof Map<?, ?> exm) {
      for (Map.Entry<?, ?> e : exm.entrySet()) {
        String k = Objects.toString(e.getKey(), "");
        if (k.startsWith("$")) extraTransforms.put(k, e.getValue());
        else extraData.put(k, e.getValue());
      }
    }

    List<Object> dataMergeList = new ArrayList<>();
    if (!isempty(extraData)) dataMergeList.add(clone(extraData));
    dataMergeList.add(clone(data));
    Object dataClone = merge(dataMergeList);

    // Build store: $TOP/data, $SPEC supplier, $BT/$DS/$WHEN escape helpers, all
    // transform_* injectors, then merge in extraTransforms, then $ERRS.
    Map<String, Object> baseStore = new LinkedHashMap<>();
    baseStore.put(S_DTOP, dataClone);
    baseStore.put(S_DSPEC, (Supplier<Object>) () -> origspec);
    baseStore.put("$BT", (Supplier<Object>) () -> "`");
    baseStore.put("$DS", (Supplier<Object>) () -> "$");
    baseStore.put(
        "$WHEN", (Supplier<Object>) () -> java.time.Instant.now().toString());
    baseStore.put("$DELETE", transform_DELETE);
    baseStore.put("$COPY", transform_COPY);
    baseStore.put("$KEY", transform_KEY);
    baseStore.put("$ANNO", transform_ANNO);
    baseStore.put("$MERGE", transform_MERGE);
    baseStore.put("$EACH", transform_EACH);
    baseStore.put("$PACK", transform_PACK);
    baseStore.put("$REF", transform_REF);
    baseStore.put("$FORMAT", transform_FORMAT);
    baseStore.put("$APPLY", transform_APPLY);

    List<Object> storeMergeList = new ArrayList<>();
    storeMergeList.add(baseStore);
    if (!extraTransforms.isEmpty()) storeMergeList.add(extraTransforms);
    Map<String, Object> errsHolder = new LinkedHashMap<>();
    errsHolder.put(S_DERRS, errs);
    storeMergeList.add(errsHolder);
    Object store = merge(storeMergeList, 1);

    // Build the injection definition (modify/handler/meta/errs).
    Injection injdef = new Injection(workspec, null);
    injdef.prior = null; // partial — inject() rebuilds top state
    if (modifyRaw instanceof Modify mod) injdef.modify = mod;
    if (handlerRaw instanceof Injector h) injdef.handler = h;
    if (metaRaw instanceof Map<?, ?> mm) injdef.meta = (Map<String, Object>) mm;
    injdef.errs = errs;

    Object out = inject(workspec, store, injdef);

    if (!errs.isEmpty() && !collect) {
      throw new IllegalArgumentException(String.join(" | ", errsAsStrings(errs)));
    }
    return out;
  }

  private static List<String> errsAsStrings(List<Object> errs) {
    List<String> out = new ArrayList<>(errs.size());
    for (Object e : errs) out.add(Objects.toString(e, ""));
    return out;
  }


  // ===========================================================================
  // Validate injectors (step 10) — reference declarations
  // ===========================================================================
  // Ported from TS lines 1977–2237. Wired in via a future step 11
  // validate() rewrite; until then the hand-rolled validate(data, spec)
  // below remains the active implementation.

  /** $STRING: require a non-empty string. */
  public static final Injector validate_STRING =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        // Group B: validate inspects the raw data value (a stored null must be
        // type-checked, not unified away). Mirrors TS _lookup(dparent,key).
        Object out = lookup(inj.dparent, inj.key);
        int t = typify(out);
        if ((T_string & t) == 0) {
          inj.errs.add(_invalidTypeMsg(inj.path, "string", t, out, "V1010"));
          return UNDEF;
        }
        if ("".equals(out)) {
          inj.errs.add("Empty string at " + pathify(inj.path, 1));
          return UNDEF;
        }
        return out;
      };

  /** Generic $TYPE handler: looks up the bit-flag matching {@code ref}'s name. */
  public static final Injector validate_TYPE =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        String tname = ref == null || ref.length() < 2 ? "" : ref.substring(1).toLowerCase(Locale.ROOT);
        int idx = -1;
        for (int i = 0; i < TYPENAME.length; i++) {
          if (tname.equals(TYPENAME[i])) {
            idx = i;
            break;
          }
        }
        if (idx < 0) return UNDEF;
        // $NIL is absent or null.
        int typev = (1 << (31 - idx)) | ("nil".equals(tname) ? T_null : 0);
        // Group B: type-check the raw data value (TS _lookup(dparent,key)).
        Object out = lookup(inj.dparent, inj.key);
        int t = typify(out);
        if ((t & typev) == 0) {
          inj.errs.add(_invalidTypeMsg(inj.path, tname, t, out, "V1001"));
          return UNDEF;
        }
        return out;
      };

  /** $ANY: accept any value. */
  public static final Injector validate_ANY =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        // Group B: $ANY returns the raw data value, preserving a stored null
        // (TS _lookup(dparent,key)).
        return lookup(inj.dparent, inj.key);
      };

  /**
   * $CHILD: validate every direct child of the current node against a template.
   * Map syntax: {@code {`$CHILD`: child-template}} (M_KEYPRE phase).
   * List syntax: {@code [`$CHILD`, child-template]} (M_VAL phase).
   * Mirrors TS lines 2028–2101.
   */
  public static final Injector validate_CHILD =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;

        if (inj.mode == M_KEYPRE) {
          Object childtm = getprop(inj.parent, inj.key);
          Object pkey = getelem(inj.path, -2);
          Object tval = getprop(inj.dparent, pkey);

          if (tval == UNDEF || tval == null) {
            tval = new LinkedHashMap<>();
          } else if (!ismap(tval)) {
            // _validation reports the mismatch, once.
            return UNDEF;
          }

          List<String> ckeys = keysof(tval);
          for (String ckey : ckeys) {
            setprop(inj.parent, ckey, clone(childtm));
            inj.keys.add(ckey);
          }
          inj.setval(UNDEF);
          return UNDEF;
        }

        if (inj.mode == M_VAL) {
          if (!islist(inj.parent)) {
            inj.errs.add("Invalid $CHILD as value");
            return UNDEF;
          }
          // Group B: the child template is read raw (TS _lookup(parent,1)).
          Object childtm = lookup(inj.parent, 1);

          if (inj.dparent == UNDEF || inj.dparent == null) {
            ((List<Object>) inj.parent).clear();
            return UNDEF;
          }

          if (!islist(inj.dparent)) {
            inj.keyI = size(inj.parent);
            return inj.dparent;
          }

          List<Object> dpl = (List<Object>) inj.dparent;
          List<Object> pl = (List<Object>) inj.parent;
          for (int i = 0; i < dpl.size(); i++) {
            setprop(pl, i, clone(childtm));
          }
          while (pl.size() > dpl.size()) pl.remove(pl.size() - 1);

          // NOTE: modifying inj! This extends the child value loop in inject
          // to cover every cloned child.
          for (int ckeyI = size(inj.keys); ckeyI < size(pl); ckeyI++) {
            inj.keys.add(strkey(ckeyI));
          }

          // Restart the child value loop at the first element (the loop
          // increments keyI on resume) so that the first element is also
          // validated against the child template.
          inj.keyI = -1;

          // SKIP leaves the cloned child template in place at the first
          // element so the resumed loop can validate it.
          return SKIP;
        }

        return UNDEF;
      };

  private static String _describeAlternatives(List<Object> tvals) {
    List<Object> parts = new ArrayList<>(tvals.size());
    for (Object tval : tvals) {
      parts.add(stringify(tval));
    }
    return _lowernames(join(parts, ", ", false));
  }

  // Lowers every `$NAME` marker in the description, nested ones included.
  private static String _lowernames(String desc) {
    Matcher m = R_TRANSFORM_NAME.matcher(desc);
    StringBuilder out = new StringBuilder();
    while (m.find()) {
      m.appendReplacement(out, Matcher.quoteReplacement(m.group(1).toLowerCase(Locale.ROOT)));
    }
    m.appendTail(out);
    return out.toString();
  }

  /**
   * $EXACT: validate against any one of a list of literal alternatives.
   * Format: {@code [`$EXACT`, lit0, lit1, ...]}. Mirrors TS {@code validate_EXACT}.
   */
  public static final Injector validate_EXACT =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;

        if (inj.mode == M_VAL) {
          if (!islist(inj.parent) || inj.keyI != 0) {
            inj.errs.add(
                "The $EXACT validator at field "
                    + pathify(inj.path, 1, 1)
                    + " must be the first element of an array.");
            return UNDEF;
          }

          Object cval = _slotval(inj);

          inj.keyI = size(inj.keys);

          // Replace [$EXACT, ...] with the data value; SKIP keeps inject off the detached list.
          inj.setval(cval, 2);

          inj.path = (List<String>) slice(inj.path, 0, -1);

          List<Object> tvals = (List<Object>) slice(inj.parent, 1, null);
          if (tvals.isEmpty()) {
            inj.errs.add(
                "The $EXACT validator at field "
                    + pathify(inj.path, 1, 1)
                    + " must have at least one argument.");
            return SKIP;
          }

          for (Object tval : tvals) {
            if (_deepequal(tval, cval)) return SKIP;
          }

          String valdesc = _describeAlternatives(tvals);
          inj.errs.add(
              _invalidTypeMsg(
                  inj.path,
                  (size(inj.path) > 1 ? "" : "value ")
                      + "exactly equal to "
                      + (size(tvals) == 1 ? "" : "one of ")
                      + valdesc,
                  typify(cval),
                  cval,
                  "V0110"));
          return SKIP;
        } else {
          delprop(inj.parent, inj.key);
          return UNDEF;
        }
      };

  /**
   * $NOF: count the specs that admit the value. Format:
   * {@code [`$NOF`, count, spec, ...]}, where count is an integer, or a map
   * holding {@code min}, {@code max} or both. Mirrors TS {@code validate_NOF}.
   */
  public static final Injector validate_NOF =
      (injObj, val, ref, store) ->
          injObj instanceof Injection inj ? _validatecount(inj, store, "$NOF", true) : UNDEF;

  /**
   * $ALL: every spec admits the value. Format: {@code [`$ALL`, spec, ...]}.
   * Mirrors TS {@code validate_ALL}.
   */
  public static final Injector validate_ALL =
      (injObj, val, ref, store) ->
          injObj instanceof Injection inj ? _validatecount(inj, store, "$ALL", false) : UNDEF;

  // The counting list directives. Without a count, every spec has to admit.
  private static Object _validatecount(Injection inj, Object store, String name, boolean counted) {
    if (inj.mode != M_VAL) {
      return UNDEF;
    }

    Object parent = inj.parent;

    if (!islist(parent) || inj.keyI != 0) {
      inj.errs.add(
          "The "
              + name
              + " validator at field "
              + pathify(inj.path, 1, 1)
              + " must be the first element of an array.");
      return UNDEF;
    }

    Object cval = _slotval(inj);

    inj.keyI = size(inj.keys);

    // Replace the directive's list with the data value. Each return is SKIP, so
    // that inject leaves the detached list alone and validates nothing in it.
    inj.setval(cval, 2);

    inj.path = (List<String>) slice(inj.path, -1, null);

    Object count = counted ? lookup(parent, 1) : UNDEF;
    List<Object> tvals = (List<Object>) slice(parent, counted ? 2 : 1, null);
    int numtvals = tvals.size();
    String field = "The " + name + " validator at field " + pathify(inj.path, 1);

    if (0 == numtvals) {
      inj.errs.add(
          field + (counted ? " must have a count and" : " must have") + " at least one argument.");
      return SKIP;
    }

    Object[] bounds =
        counted ? _nofcount(count, numtvals) : new Object[] {(long) numtvals, (long) numtvals, "all"};
    long lo = (Long) bounds[0];
    long hi = (Long) bounds[1];
    String countdesc = (String) bounds[2];

    if (null == countdesc) {
      inj.errs.add(field + " has an invalid count: " + stringify(count) + ".");
      return SKIP;
    }

    int admitted = 0;
    for (int tI = 0; tI < numtvals; tI++) {
      int left = numtvals - tI;

      // Stop once the specs left cannot change the verdict.
      if (hi < admitted || admitted + left < lo || (lo <= admitted && admitted + left <= hi)) {
        break;
      }

      if (_admits(cval, tvals.get(tI), inj, store)) {
        admitted++;
      }
    }

    if (admitted < lo || hi < admitted) {
      String valdesc = _describeAlternatives(tvals);
      inj.errs.add(
          _invalidTypeMsg(inj.path, countdesc + " of " + valdesc, typify(cval), cval, "V0310"));
    }

    return SKIP;
  }

  /**
   * $LEN: the value's length is within a bound. Format:
   * {@code [`$LEN`, bound, spec?]}, where the bound is as for a $NOF count. A
   * string's length is in code points. Mirrors TS {@code validate_LEN}.
   */
  public static final Injector validate_LEN =
      (injObj, val, ref, store) ->
          injObj instanceof Injection inj ? _validatebound(inj, store, "$LEN") : UNDEF;

  /**
   * $RANGE: the value is a number within a bound. Format:
   * {@code [`$RANGE`, bound, spec?]}, where the bound holds {@code min} or
   * {@code gt}, {@code max} or {@code lt}, or one of each. Mirrors TS
   * {@code validate_RANGE}.
   */
  public static final Injector validate_RANGE =
      (injObj, val, ref, store) ->
          injObj instanceof Injection inj ? _validatebound(inj, store, "$RANGE") : UNDEF;

  // The bounding list directives: a bound, then at most one spec that must also admit.
  private static Object _validatebound(Injection inj, Object store, String name) {
    if (inj.mode != M_VAL) {
      return UNDEF;
    }

    Object parent = inj.parent;

    if (!islist(parent) || inj.keyI != 0) {
      inj.errs.add(
          "The "
              + name
              + " validator at field "
              + pathify(inj.path, 1, 1)
              + " must be the first element of an array.");
      return UNDEF;
    }

    Object cval = _slotval(inj);

    inj.keyI = size(inj.keys);

    // As for the counting directives: SKIP keeps inject off the detached list.
    inj.setval(cval, 2);

    inj.path = (List<String>) slice(inj.path, -1, null);

    String field = "The " + name + " validator at field " + pathify(inj.path, 1);
    int nargs = size(parent) - 1;

    if (nargs < 1 || 2 < nargs) {
      inj.errs.add(field + " must have a bound and at most one spec.");
      return SKIP;
    }

    Object bound = lookup(parent, 1);
    boolean islen = "$LEN".equals(name);
    Object[] lenbound = islen ? _lenbound(bound) : null;
    String desc = islen ? (String) lenbound[2] : _rangedesc(bound);

    if (null == desc) {
      inj.errs.add(field + " has an invalid bound: " + stringify(bound) + ".");
      return SKIP;
    }

    int ctype = typify(cval);

    if (2 == nargs && !_admits(cval, lookup(parent, 2), inj, store)) {
      String specdesc = _lowernames(stringify(lookup(parent, 2)));
      inj.errs.add(_invalidTypeMsg(inj.path, specdesc, ctype, cval, "V0410"));
      return SKIP;
    }

    if (0 == ((islen ? T_string | T_list | T_map : T_number) & ctype)) {
      String needtype = islen ? "string, list or map" : "number";
      inj.errs.add(_invalidTypeMsg(inj.path, needtype, ctype, cval, "V0420"));
      return SKIP;
    }

    boolean inbound;
    if (islen) {
      long lo = (Long) lenbound[0];
      long hi = (Long) lenbound[1];
      int len = cval instanceof String s ? s.codePointCount(0, s.length()) : size(cval);
      inbound = lo <= len && (-1 == hi || len <= hi);
    } else {
      inbound = _inrange(bound, ((Number) cval).doubleValue());
    }

    if (!inbound) {
      String needtype = (1 < size(inj.path) ? "" : "value ") + desc;
      inj.errs.add(_invalidTypeMsg(inj.path, needtype, ctype, cval, "V0430"));
    }

    return SKIP;
  }

  // The bounds of a $LEN bound, with -1 for no maximum, and the words for it,
  // which are null when the bound is invalid.
  private static Object[] _lenbound(Object bound) {
    Object[] count = _nofcount(bound, -1);

    if (null == count[2]) {
      return new Object[] {0L, 0L, null};
    }

    long lo = (Long) count[0];
    long hi = (Long) count[1];

    String desc =
        lo == hi
            ? String.valueOf(lo)
            : -1 == hi ? "at least " + lo : 0 == lo ? "at most " + hi : lo + " to " + hi;

    return new Object[] {lo, hi, "of length " + desc};
  }

  // The words for a $RANGE bound, which are null when the bound is invalid.
  private static String _rangedesc(Object bound) {
    if (!ismap(bound)) {
      return null;
    }

    Object min = lookup(bound, "min");
    Object max = lookup(bound, "max");
    Object gt = lookup(bound, "gt");
    Object lt = lookup(bound, "lt");
    Object lower = UNDEF == min ? gt : min;
    Object upper = UNDEF == max ? lt : max;

    int numkeys = 0;
    for (Object n : new Object[] {min, max, gt, lt}) {
      if (UNDEF != n) {
        numkeys++;
      }
    }

    boolean valid =
        0 < size(bound)
            && size(bound) == numkeys
            && (UNDEF == min || UNDEF == gt)
            && (UNDEF == max || UNDEF == lt)
            && _isnum(min)
            && _isnum(max)
            && _isnum(gt)
            && _isnum(lt)
            && (UNDEF == lower
                || UNDEF == upper
                || ((Number) lower).doubleValue() <= ((Number) upper).doubleValue());

    if (!valid) {
      return null;
    }

    StringJoiner desc = new StringJoiner(" and ");
    if (UNDEF != min) {
      desc.add("at least " + stringify(min));
    } else if (UNDEF != gt) {
      desc.add("greater than " + stringify(gt));
    }
    if (UNDEF != max) {
      desc.add("at most " + stringify(max));
    } else if (UNDEF != lt) {
      desc.add("less than " + stringify(lt));
    }

    return desc.toString();
  }

  // A number within a valid $RANGE bound.
  private static boolean _inrange(Object bound, double val) {
    Object min = lookup(bound, "min");
    Object max = lookup(bound, "max");
    Object gt = lookup(bound, "gt");
    Object lt = lookup(bound, "lt");

    return (UNDEF == min || ((Number) min).doubleValue() <= val)
        && (UNDEF == max || val <= ((Number) max).doubleValue())
        && (UNDEF == gt || ((Number) gt).doubleValue() < val)
        && (UNDEF == lt || val < ((Number) lt).doubleValue());
  }

  private static boolean _isnum(Object n) {
    return UNDEF == n || 0 != (T_number & typify(n));
  }

  // Names a validate spec may use besides its checkers: transform's that it keeps, and $OPEN.
  private static final List<String> VALIDATE_NAMES =
      List.of("$TOP", "$SPEC", "$BT", "$DS", "$WHEN", "$ANNO", "$REF", "$FORMAT", "$APPLY", "$OPEN");

  // Report each checker the spec names that validate lacks; $EXACT's arguments are literals.
  private static void _checknames(Object spec, Object store, List<String> path, List<Object> errs) {
    String name = _refname(spec);
    if (null != name) {
      if (_unknownname(name, store)) {
        errs.add("Unknown validator " + name + " at field " + pathify(path) + ".");
      }
      return;
    }

    if (islist(spec) && "$EXACT".equals(_refname(lookup(spec, 0)))) {
      return;
    }

    for (String key : keysof(spec)) {
      if (ismap(spec)) {
        _checknames(key, store, path, errs);
      }
      List<String> kpath = new ArrayList<>(path);
      kpath.add(key);
      _checknames(lookup(spec, key), store, kpath, errs);
    }
  }

  // The name a whole-string reference gives, when it is a checker name in any case.
  private static String _refname(Object val) {
    Matcher m = val instanceof String s ? R_INJECT_FULL.matcher(s) : null;
    return null != m && m.matches() && R_CHECKER_NAME.matcher(m.group(1).toUpperCase(Locale.ROOT)).matches()
        ? m.group(1)
        : null;
  }

  // Unknown: undefined and upper case, or a defined name in another case. Null disables a name.
  private static boolean _unknownname(String name, Object store) {
    String upper = name.toUpperCase(Locale.ROOT);
    return !_knownname(name, store) && (upper.equals(name) || _knownname(upper, store));
  }

  private static boolean _knownname(String name, Object store) {
    Object val = lookup(store, name);
    return VALIDATE_NAMES.contains(name) || (null != val && UNDEF != val);
  }

  // The data value at a list directive's slot. The directive's own dparent was
  // read with getprop, which reports a stored null as absent.
  private static Object _slotval(Injection inj) {
    Injection prior = inj.prior;
    return null == prior ? inj.dparent : lookup(prior.dparent, prior.key);
  }

  // JSON equality: numbers by value, lists in order, maps by key in any order.
  private static boolean _deepequal(Object a, Object b) {
    // TS ===: identity, or value equality for numbers, strings and booleans.
    if (a == b
        || (a instanceof Number an && b instanceof Number bn && an.doubleValue() == bn.doubleValue())
        || ((a instanceof String || a instanceof Boolean) && a.equals(b))) {
      return true;
    }

    int atype = typify(a);
    if (atype != typify(b) || 0 == ((T_list | T_map) & atype)) {
      return false;
    }

    List<String> akeys = keysof(a);
    List<String> bkeys = keysof(b);
    if (akeys.size() != bkeys.size()) {
      return false;
    }

    for (int kI = 0; kI < akeys.size(); kI++) {
      String k = akeys.get(kI);
      if (!k.equals(bkeys.get(kI)) || !_deepequal(lookup(a, k), lookup(b, k))) {
        return false;
      }
    }

    return true;
  }

  // Every member val has is in out, unchanged. A member only out has is a
  // default the spec supplied, and is ignored.
  private static boolean _keeps(Object val, Object out) {
    if (UNDEF == val) {
      return true;
    }

    if (0 == ((T_list | T_map) & typify(val)) || islist(val) != islist(out) || !isnode(out)) {
      return _deepequal(val, out);
    }

    for (String k : keysof(val)) {
      if (!_keeps(lookup(val, k), lookup(out, k))) {
        return false;
      }
    }

    return true;
  }

  // A spec admits a value when validating the value against it finds no error
  // and gives back the value as it is.
  private static boolean _admits(Object val, Object spec, Injection inj, Object store) {
    List<Object> terrs = new ArrayList<>();

    List<Object> mergeList = new ArrayList<>();
    mergeList.add(new LinkedHashMap<String, Object>());
    mergeList.add(store);
    Map<String, Object> vstore = (Map<String, Object>) merge(mergeList, 1);
    vstore.put(S_DTOP, val);

    Map<String, Object> opts = new LinkedHashMap<>();
    opts.put("extra", vstore);
    opts.put("errs", terrs);
    opts.put("meta", inj.meta);
    Object out = validate(val, spec, opts);

    return terrs.isEmpty() && _keeps(val, out);
  }

  // The bounds of a $NOF count, and the words for it, which are null when the
  // count is invalid. Without a max, the bound is the number of specs.
  private static Object[] _nofcount(Object count, int numtvals) {
    if (_isnat(count)) {
      long n = ((Number) count).longValue();
      return new Object[] {n, n, 0 == n ? "none" : "exactly " + n};
    }

    Object min = lookup(count, "min");
    Object max = lookup(count, "max");

    boolean valid =
        ismap(count)
            && 0 < size(count)
            && size(count) == (UNDEF == min ? 0 : 1) + (UNDEF == max ? 0 : 1)
            && (UNDEF == min || _isnat(min))
            && (UNDEF == max || _isnat(max))
            && (UNDEF == min
                || UNDEF == max
                || ((Number) min).doubleValue() <= ((Number) max).doubleValue());

    if (!valid) {
      return new Object[] {0L, 0L, null};
    }

    long lo = UNDEF == min ? 0 : ((Number) min).longValue();
    long hi = UNDEF == max ? numtvals : ((Number) max).longValue();

    String desc =
        UNDEF == max
            ? "at least " + lo
            : 0 == hi
                ? "none"
                : UNDEF == min
                    ? "at most " + hi
                    : lo == hi
                        ? "exactly " + lo
                        : lo + " to " + hi;

    return new Object[] {lo, hi, desc};
  }

  private static boolean _isnat(Object n) {
    return 0 != (T_integer & typify(n)) && 0 <= ((Number) n).doubleValue();
  }

  /**
   * Modify hook used by {@link #validate(Object, Object)}: runs after each
   * inject step; performs type-mismatch checks, open-vs-closed map handling
   * via {@code `$OPEN`}, exact-mode comparison, and default-value copy-over.
   * Mirrors TS {@code _validation} (lines 2242–2333).
   */
  public static final Modify _validation =
      (pval, key, parent, injObj, store) -> {
        if (!(injObj instanceof Injection inj)) return;
        if (pval == SKIP) return;

        boolean exact = Boolean.TRUE.equals(getprop(inj.meta, "`$EXACT`", false));
        Object cval = getprop(inj.dparent, key);
        if (!exact && (cval == UNDEF || cval == null)) return;

        int ptype = typify(pval);
        // Skip strings containing $ (special command refs).
        if ((T_string & ptype) != 0 && pval instanceof String ps && ps.contains("$")) {
          return;
        }

        int ctype = typify(cval);
        if (ptype != ctype && pval != UNDEF) {
          inj.errs.add(_invalidTypeMsg(inj.path, typename(ptype), ctype, cval, "V0010"));
          return;
        }

        if (ismap(cval)) {
          if (!ismap(pval)) {
            inj.errs.add(_invalidTypeMsg(inj.path, typename(ptype), ctype, cval, "V0020"));
            return;
          }
          List<String> ckeys = keysof(cval);
          List<String> pkeys = keysof(pval);

          if (size(pkeys) > 0 && !Boolean.TRUE.equals(getprop(pval, "`$OPEN`"))) {
            List<String> badkeys = new ArrayList<>();
            for (String ck : ckeys) {
              // Group B literal presence: a key the SHAPE declares is allowed
              // even when its declared value is JSON null (TS _lookup, not the
              // Group A haskey which would miss null-valued shape slots).
              if (lookup(pval, ck) == UNDEF) badkeys.add(ck);
            }
            if (!badkeys.isEmpty()) {
              inj.errs.add(
                  "Unexpected keys at field "
                      + pathify(inj.path, 1)
                      + ": "
                      + String.join(", ", badkeys));
            }
          } else {
            List<Object> mergeArgs = new ArrayList<>();
            mergeArgs.add(pval);
            mergeArgs.add(cval);
            merge(mergeArgs);
            if (isnode(pval)) {
              delprop(pval, "`$OPEN`");
            }
          }
        } else if (islist(cval)) {
          if (!islist(pval)) {
            inj.errs.add(_invalidTypeMsg(inj.path, typename(ptype), ctype, cval, "V0030"));
          }
        } else if (exact) {
          if (!Objects.equals(cval, pval)) {
            String pathmsg =
                size(inj.path) > 1
                    ? "at field " + pathify(inj.path, 1) + ": "
                    : "";
            inj.errs.add(
                "Value " + pathmsg + jsString(cval) + " should equal " + jsString(pval) + ".");
          }
        } else {
          // Spec value was a default; copy data over.
          setprop(parent, key, cval);
        }
      };

  /**
   * Custom Injector used by {@link #validate(Object, Object)}: intercepts
   * meta-path syntax ({@code `<root>$=value`}, {@code `<root>$~spec`}) before
   * delegating to the default {@link #_injecthandler}. Mirrors TS lines 2801–2828.
   */
  public static final Injector _validatehandler =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return val;
        if (ref != null) {
          Matcher m = R_META_PATH.matcher(ref);
          if (m.matches()) {
            String op = m.group(2);
            if ("=".equals(op)) {
              List<Object> wrap = new ArrayList<>();
              wrap.add("`$EXACT`");
              wrap.add(val);
              inj.setval(wrap);
            } else {
              inj.setval(val);
            }
            inj.keyI = -1;
            return SKIP;
          }
        }
        return _injecthandler.apply(inj, val, ref, store);
      };

  // ===========================================================================
  // Select injectors (step 12) — reference declarations
  // ===========================================================================
  // Ported from TS lines 2414–2551. Wired in via a future step 12
  // select() rewrite; until then the hand-rolled select(children, query)
  // below remains the active implementation.

  /** Build the recursive validate options used by select_*: rebind $TOP to
   *  the current point and pass through meta + the existing store as extra. */
  private static Map<String, Object> selectRecOpts(
      Object store, Object point, Map<String, Object> meta, List<Object> errs) {
    Map<String, Object> vstore = new LinkedHashMap<>();
    if (store instanceof Map<?, ?> sm) {
      for (Map.Entry<?, ?> e : sm.entrySet()) {
        vstore.put(Objects.toString(e.getKey()), e.getValue());
      }
    }
    vstore.put(S_DTOP, point);
    Map<String, Object> opts = new LinkedHashMap<>();
    opts.put("errs", errs);
    opts.put("meta", meta);
    opts.put("extra", vstore);
    return opts;
  }

  /** $AND: require every sub-term to validate against the current point. */
  public static final Injector select_AND =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        if (inj.mode != M_KEYPRE) return UNDEF;
        // Group B: select operator terms are read raw (TS _lookup(parent,key)).
        Object terms = lookup(inj.parent, inj.key);
        if (!(terms instanceof List<?> tl)) return UNDEF;
        Object ppath = slice(inj.path, -1, null);
        Object point = getpath(store, ppath);
        for (Object term : tl) {
          List<Object> terrs = new ArrayList<>();
          Map<String, Object> opts = selectRecOpts(store, point, inj.meta, terrs);
          try {
            validate(point, term, opts);
          } catch (Exception e) {
            terrs.add(e.getMessage());
          }
          if (!terrs.isEmpty()) {
            inj.errs.add(
                "AND:" + pathify(ppath) + ": " + stringify(point) + " fail:" + stringify(terms));
          }
        }
        Object gkey = getelem(inj.path, -2);
        Object gp = getelem(inj.nodes, -2);
        setprop(gp, gkey, point);
        return UNDEF;
      };

  /** $OR: require at least one sub-term to validate. */
  public static final Injector select_OR =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        if (inj.mode != M_KEYPRE) return UNDEF;
        // Group B: select operator terms are read raw (TS _lookup(parent,key)).
        Object terms = lookup(inj.parent, inj.key);
        if (!(terms instanceof List<?> tl)) return UNDEF;
        Object ppath = slice(inj.path, -1, null);
        Object point = getpath(store, ppath);
        for (Object term : tl) {
          List<Object> terrs = new ArrayList<>();
          Map<String, Object> opts = selectRecOpts(store, point, inj.meta, terrs);
          try {
            validate(point, term, opts);
          } catch (Exception e) {
            terrs.add(e.getMessage());
          }
          if (terrs.isEmpty()) {
            Object gkey = getelem(inj.path, -2);
            Object gp = getelem(inj.nodes, -2);
            setprop(gp, gkey, point);
            return UNDEF;
          }
        }
        inj.errs.add(
            "OR:" + pathify(ppath) + ": " + stringify(point) + " fail:" + stringify(terms));
        return UNDEF;
      };

  /** $NOT: require the sub-term to fail validation. */
  public static final Injector select_NOT =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        if (inj.mode != M_KEYPRE) return UNDEF;
        // Group B: select $NOT term is read raw (TS _lookup(parent,key)).
        Object term = lookup(inj.parent, inj.key);
        Object ppath = slice(inj.path, -1, null);
        Object point = getpath(store, ppath);
        List<Object> terrs = new ArrayList<>();
        Map<String, Object> opts = selectRecOpts(store, point, inj.meta, terrs);
        try {
          validate(point, term, opts);
        } catch (Exception e) {
          terrs.add(e.getMessage());
        }
        if (terrs.isEmpty()) {
          inj.errs.add(
              "NOT:" + pathify(ppath) + ": " + stringify(point) + " fail:" + stringify(term));
        }
        Object gkey = getelem(inj.path, -2);
        Object gp = getelem(inj.nodes, -2);
        setprop(gp, gkey, point);
        return UNDEF;
      };

  /** $GT/$LT/$GTE/$LTE/$LIKE comparators dispatched by {@code ref}. */
  public static final Injector select_CMP =
      (injObj, val, ref, store) -> {
        if (!(injObj instanceof Injection inj)) return UNDEF;
        if (inj.mode != M_KEYPRE) return UNDEF;
        // Group B: select $CMP term is read raw (TS _lookup(parent,key)).
        Object term = lookup(inj.parent, inj.key);
        Object gkey = getelem(inj.path, -2);
        Object ppath = slice(inj.path, -1, null);
        Object point = getpath(store, ppath);
        boolean pass = false;
        if (point instanceof Number pn && term instanceof Number tn) {
          double a = pn.doubleValue();
          double b = tn.doubleValue();
          pass =
              switch (ref) {
                case "$GT" -> a > b;
                case "$LT" -> a < b;
                case "$GTE" -> a >= b;
                case "$LTE" -> a <= b;
                default -> false;
              };
        } else if ("$LIKE".equals(ref) && term instanceof String pattern) {
          try {
            pass = Pattern.compile(pattern).matcher(stringify(point)).find();
          } catch (Exception ignored) {
            pass = false;
          }
        }
        if (pass) {
          Object gp = getelem(inj.nodes, -2);
          setprop(gp, gkey, point);
        } else {
          inj.errs.add(
              "CMP: "
                  + pathify(ppath)
                  + ": "
                  + stringify(point)
                  + " fail:"
                  + ref
                  + " "
                  + stringify(term));
        }
        return UNDEF;
      };

  public static Object validate(Object data, Object spec) {
    return validate(data, spec, null);
  }

  /**
   * TS-faithful validate: build a store with validate_* injectors plus nulled
   * transform commands, then dispatch via {@link #transform} with
   * {@link #_validation} as modify and {@link #_validatehandler} as handler.
   * Mirrors TS {@code validate} (StructUtility.ts lines 2347–2411).
   */
  public static Object validate(Object data, Object spec, Map<String, Object> options) {
    Object extraRaw = options == null ? null : options.get("extra");
    Object errsRaw = options == null ? null : options.get("errs");
    Object metaRaw = options == null ? null : options.get("meta");

    boolean collect = errsRaw instanceof List<?>;
    List<Object> errs = collect ? (List<Object>) errsRaw : new ArrayList<>();

    // Build store: nullify transform commands, add validate_* injectors.
    Map<String, Object> baseStore = new LinkedHashMap<>();
    baseStore.put("$DELETE", null);
    baseStore.put("$COPY", null);
    baseStore.put("$KEY", null);
    baseStore.put("$META", null);
    baseStore.put("$MERGE", null);
    baseStore.put("$EACH", null);
    baseStore.put("$PACK", null);

    baseStore.put("$STRING", validate_STRING);
    baseStore.put("$NUMBER", validate_TYPE);
    baseStore.put("$INTEGER", validate_TYPE);
    baseStore.put("$DECIMAL", validate_TYPE);
    baseStore.put("$BOOLEAN", validate_TYPE);
    baseStore.put("$NULL", validate_TYPE);
    baseStore.put("$NIL", validate_TYPE);
    baseStore.put("$MAP", validate_TYPE);
    baseStore.put("$LIST", validate_TYPE);
    baseStore.put("$FUNCTION", validate_TYPE);
    baseStore.put("$INSTANCE", validate_TYPE);
    baseStore.put("$ANY", validate_ANY);
    baseStore.put("$CHILD", validate_CHILD);
    baseStore.put("$EXACT", validate_EXACT);
    baseStore.put("$NOF", validate_NOF);
    baseStore.put("$ALL", validate_ALL);
    baseStore.put("$LEN", validate_LEN);
    baseStore.put("$RANGE", validate_RANGE);

    List<Object> mergeList = new ArrayList<>();
    mergeList.add(baseStore);
    if (extraRaw instanceof Map<?, ?> em) mergeList.add(em);
    Map<String, Object> errsHolder = new LinkedHashMap<>();
    errsHolder.put(S_DERRS, errs);
    mergeList.add(errsHolder);
    Object store = merge(mergeList, 1);

    // Build meta with `$EXACT` default.
    Map<String, Object> meta;
    if (metaRaw instanceof Map<?, ?> mm) {
      meta = new LinkedHashMap<>();
      for (Map.Entry<?, ?> e : ((Map<?, ?>) mm).entrySet()) {
        meta.put(Objects.toString(e.getKey()), e.getValue());
      }
    } else {
      meta = new LinkedHashMap<>();
    }
    if (!meta.containsKey("`$EXACT`")) {
      meta.put("`$EXACT`", false);
    }

    Map<String, Object> opts = new LinkedHashMap<>();
    opts.put("meta", meta);
    opts.put("extra", store);
    opts.put("modify", _validation);
    opts.put("handler", _validatehandler);
    opts.put("errs", errs);

    // A spec that names an unknown checker validates nothing.
    int numerrs = errs.size();
    _checknames(spec, store, new ArrayList<>(), errs);

    Object out = numerrs < errs.size() ? clone(data) : transform(data, spec, opts);

    if (!errs.isEmpty() && !collect) {
      throw new IllegalArgumentException(String.join(" | ", errsAsStrings(errs)));
    }
    return out;
  }

  /**
   * TS-faithful select: tag each child node with {@code $KEY}, open the
   * (cloned) query's maps with {@code _openquery}, then run
   * {@link #validate} against each child with the {@code select_*} injectors
   * available as extras and {@code meta.`$EXACT`} = true.
   * Mirrors TS lines 2558–2609.
   */
  public static List<Object> select(Object children, Object query) {
    if (!isnode(children)) {
      return new ArrayList<>();
    }

    // Tag each node child with $KEY = original key/index; non-node children
    // (strings/numbers/etc.) are passed through as-is — TS setprop on a
    // non-node returns the value unchanged, so these are still selectable.
    List<Object> childList = new ArrayList<>();
    if (ismap(children)) {
      for (Map.Entry<?, ?> e : ((Map<?, ?>) children).entrySet()) {
        Object node = e.getValue();
        if (isnode(node)) {
          setprop(node, S_DKEY, Objects.toString(e.getKey()));
        }
        childList.add(node);
      }
    } else {
      List<?> cl = (List<?>) children;
      for (int i = 0; i < cl.size(); i++) {
        Object node = cl.get(i);
        if (isnode(node)) {
          setprop(node, S_DKEY, (long) i);
        }
        childList.add(node);
      }
    }

    // Build injdef: meta with $EXACT=true; extras for select_* operators.
    Map<String, Object> meta = new LinkedHashMap<>();
    meta.put("`$EXACT`", true);

    Map<String, Object> extra = new LinkedHashMap<>();
    extra.put("$AND", select_AND);
    extra.put("$OR", select_OR);
    extra.put("$NOT", select_NOT);
    extra.put("$GT", select_CMP);
    extra.put("$LT", select_CMP);
    extra.put("$GTE", select_CMP);
    extra.put("$LTE", select_CMP);
    extra.put("$LIKE", select_CMP);

    Object q = clone(query);
    _openquery(q);

    List<Object> results = new ArrayList<>();
    for (Object child : childList) {
      List<Object> errs = new ArrayList<>();
      Map<String, Object> opts = new LinkedHashMap<>();
      opts.put("errs", errs);
      opts.put("meta", meta);
      opts.put("extra", extra);
      try {
        validate(child, clone(q), opts);
      } catch (Exception e) {
        errs.add(e.getMessage());
      }
      if (errs.isEmpty()) {
        results.add(child);
      }
    }
    return results;
  }

  // Open every map in a select query, so a child may hold keys the query does
  // not name, but leave a directive's literals as written: what $EXACT
  // compares, and the count or bound of $NOF, $LEN and $RANGE.
  private static void _openquery(Object q) {
    if (q instanceof Map<?, ?> m) {
      setprop(q, "`$OPEN`", getprop(q, "`$OPEN`", true));
      for (String key : keysof(q)) {
        _openquery(m.get(key));
      }
    } else if (q instanceof List<?> l) {
      Object head = l.isEmpty() ? null : l.get(0);
      boolean exact = "`$EXACT`".equals(head);
      boolean bounded = "`$NOF`".equals(head) || "`$LEN`".equals(head) || "`$RANGE`".equals(head);
      for (int i = 0; i < l.size(); i++) {
        if (0 == i || !(exact || (bounded && 1 == i))) {
          _openquery(l.get(i));
        }
      }
    }
  }


  // ===========================================================================
  // Condense
  // ===========================================================================

  private static final int CONDENSE_VERSION = 1;

  private static final int CONDENSE_MAP = 0;
  private static final int CONDENSE_LIST = 1;
  private static final int CONDENSE_STR = 2;
  private static final int CONDENSE_NUM = 3;
  private static final int CONDENSE_TRUE = 4;
  private static final int CONDENSE_FALSE = 5;
  private static final int CONDENSE_NULL = 6;

  private static final String S_condense = "$condense";
  private static final String S_condsym = "sym";
  private static final String S_condnode = "node";
  private static final String S_condroot = "root";

  private static final String CONDENSE_IMMUTABLE =
      "struct: condensed structures are immutable - expand() first, then modify the copy";

  // Code point order: String.compareTo uses UTF-16 code unit order, which
  // puts U+FFFF after a supplementary character.
  private static int condenseCmp(String a, String b) {
    int i = 0;
    int j = 0;
    while (i < a.length() && j < b.length()) {
      int ca = a.codePointAt(i);
      int cb = b.codePointAt(j);
      if (ca != cb) {
        return ca < cb ? -1 : 1;
      }
      i += Character.charCount(ca);
      j += Character.charCount(cb);
    }
    return a.length() - i - (b.length() - j);
  }

  public static boolean iscondensed(Object val) {
    // The version must MATCH, not merely be numeric: a future profile would
    // otherwise be decoded under this one's schema.
    return val instanceof Map<?, ?> m
        && m.get(S_condense) instanceof Number version
        && CONDENSE_VERSION == version.doubleValue()
        && m.get(S_condsym) instanceof List
        && m.get(S_condnode) instanceof List
        && m.get(S_condroot) instanceof Number;
  }

  /**
   * Condense any JSON-shaped node. Pure: the same input always produces a
   * byte-identical result, on every port.
   */
  public static Map<String, Object> condense(Object val) {
    Set<String> symset = new HashSet<>();
    condenseCollect(val, symset);

    List<String> sym = new ArrayList<>(symset);
    sym.sort(Struct::condenseCmp);
    Map<String, Integer> symid = new HashMap<>();
    for (int i = 0; i < sym.size(); i++) {
      symid.put(sym.get(i), i);
    }

    List<Object> node = new ArrayList<>();
    int root = condenseBuild(val, symid, node, new HashMap<>());

    Map<String, Object> out = new LinkedHashMap<>();
    out.put(S_condense, CONDENSE_VERSION);
    out.put(S_condsym, new ArrayList<Object>(sym));
    out.put(S_condnode, node);
    out.put(S_condroot, root);
    return out;
  }

  private static void condenseCollect(Object n, Set<String> symset) {
    if (ismap(n)) {
      for (String key : keysof(n)) {
        symset.add(key);
        condenseCollect(((Map<?, ?>) n).get(key), symset);
      }
    } else if (n instanceof List<?> l) {
      for (Object item : l) {
        condenseCollect(item, symset);
      }
    } else if (n instanceof String s) {
      symset.add(s);
    }
  }

  // Post-order, so identical subtrees are already interned when a parent
  // refers to them.
  private static int condenseBuild(Object n, Map<String, Integer> symid, List<Object> node,
                                   Map<String, Integer> seen) {
    List<Object> enc = new ArrayList<>();
    if (ismap(n)) {
      enc.add(CONDENSE_MAP);
      // Code-point order, not keysof's code-unit order, so the key ids ascend.
      List<String> keys = new ArrayList<>(keysof(n));
      keys.sort(Struct::condenseCmp);
      for (String key : keys) {
        enc.add(symid.get(key));
        enc.add(condenseBuild(((Map<?, ?>) n).get(key), symid, node, seen));
      }
    } else if (n instanceof List<?> l) {
      enc.add(CONDENSE_LIST);
      for (Object item : l) {
        enc.add(condenseBuild(item, symid, node, seen));
      }
    } else if (n instanceof String s) {
      enc.add(CONDENSE_STR);
      enc.add(symid.get(s));
    } else if (n instanceof Number num) {
      enc.add(CONDENSE_NUM);
      enc.add(num);
    } else if (Boolean.TRUE.equals(n)) {
      enc.add(CONDENSE_TRUE);
    } else if (Boolean.FALSE.equals(n)) {
      enc.add(CONDENSE_FALSE);
    } else {
      enc.add(CONDENSE_NULL);
    }
    return condenseIntern(enc, node, seen);
  }

  private static int condenseIntern(List<Object> enc, List<Object> node, Map<String, Integer> seen) {
    StringBuilder key = new StringBuilder();
    for (Object part : enc) {
      key.append(condenseNumKey((Number) part)).append(',');
    }
    String enckey = key.toString();
    Integer hit = seen.get(enckey);
    if (null != hit) {
      return hit;
    }
    int idx = node.size();
    node.add(enc);
    seen.put(enckey, idx);
    return idx;
  }

  // By value, so an integer and a decimal that are equal share one node.
  private static String condenseNumKey(Number n) {
    if (n instanceof Integer || n instanceof Long || n instanceof Short || n instanceof Byte) {
      return Long.toString(n.longValue());
    }
    double d = n.doubleValue();
    return Math.floor(d) == d && Math.abs(d) < Long.MAX_VALUE ? Long.toString((long) d) : Double.toString(d);
  }

  private static List<?> condenseList(Object cond, String name) {
    return cond instanceof Map<?, ?> m && m.get(name) instanceof List<?> l ? l : List.of();
  }

  private static Object condenseAt(List<?> list, int i) {
    return 0 <= i && i < list.size() ? list.get(i) : UNDEF;
  }

  // A stored index: -1 when negative, past every node when not an integer.
  private static int condenseIndex(Object n) {
    if (!(n instanceof Number num)) {
      return -1;
    }
    double d = num.doubleValue();
    if (Double.isNaN(d) || d < 0) {
      return -1;
    }
    return Math.floor(d) == d && d < Integer.MAX_VALUE ? (int) d : Integer.MAX_VALUE;
  }

  private static int condenseRoot(Object cond) {
    return condenseIndex(((Map<?, ?>) cond).get(S_condroot));
  }

  private static Object condenseEnc(Object cond, int idx) {
    Object enc = condenseAt(condenseList(cond, S_condnode), idx);
    return UNDEF == enc ? null : enc;
  }

  private static boolean condenseIs(Object enc, int kind) {
    return enc instanceof List<?> l && !l.isEmpty() && l.get(0) instanceof Number n && n.doubleValue() == kind;
  }

  private static String condenseKey(Object key) {
    if (key instanceof String s) {
      return s;
    }
    return UNDEF == key ? "undefined" : jsString(key);
  }

  // Bisects the sorted symbol table; -1 when the string occurs nowhere.
  private static int condenseSymId(Object cond, String key) {
    List<?> sym = condenseList(cond, S_condsym);
    int lo = 0;
    int hi = sym.size() - 1;
    while (lo <= hi) {
      int mid = (lo + hi) >>> 1;
      Object s = sym.get(mid);
      if (key.equals(s)) {
        return mid;
      }
      if (0 > condenseCmp(condenseKey(s), key)) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }

  // The node index of key inside node idx, or -1. Touches only this node.
  private static int condenseChild(Object cond, int idx, Object key) {
    Object enc = condenseEnc(cond, idx);
    if (null == enc || !(key instanceof String || key instanceof Number)) {
      return -1;
    }

    if (condenseIs(enc, CONDENSE_MAP)) {
      int symid = condenseSymId(cond, condenseKey(key));
      if (0 > symid) {
        return -1;
      }
      // Pairs live at [1,2], [3,4], ... with keys ascending: bisect the pairs.
      List<?> pairs = (List<?>) enc;
      int lo = 0;
      int hi = (pairs.size() - 1) / 2 - 1;
      while (lo <= hi) {
        int mid = (lo + hi) >>> 1;
        double k = pairs.get(1 + mid * 2) instanceof Number n ? n.doubleValue() : Double.NaN;
        if (k == symid) {
          return condenseIndex(pairs.get(2 + mid * 2));
        }
        if (k < symid) {
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      return -1;
    }

    if (condenseIs(enc, CONDENSE_LIST)) {
      List<?> items = (List<?>) enc;
      double i = listIndex(key);
      if (!(0 <= i && i < items.size() - 1)) {
        return -1;
      }
      return condenseIndex(items.get(1 + (int) i));
    }

    return -1;
  }

  private static int condenseResolve(Object cond, int idx, Object path) {
    List<?> parts;
    if (path instanceof List<?> l) {
      parts = l;
    } else if (path instanceof String s) {
      parts = s.isEmpty() ? List.of() : Arrays.asList(s.split("\\.", -1));
    } else if (null == path || UNDEF == path) {
      parts = List.of();
    } else {
      parts = List.of(condenseKey(path));
    }

    int at = idx;
    for (Object part : parts) {
      if (0 > at) {
        return -1;
      }
      if (S_MT.equals(part)) {
        continue;
      }
      at = condenseChild(cond, at, part);
    }
    return at;
  }

  private static Object condenseMaterialise(Object cond, int idx) {
    return 0 > idx
        ? UNDEF
        : condenseRebuild(condenseList(cond, S_condsym), condenseList(cond, S_condnode), idx);
  }

  // Every call builds new containers, so materialisations never share one.
  private static Object condenseRebuild(List<?> sym, List<?> node, int i) {
    Object enc = condenseAt(node, i);
    if (null == enc || UNDEF == enc) {
      return UNDEF;
    }
    if (condenseIs(enc, CONDENSE_MAP)) {
      List<?> pairs = (List<?>) enc;
      Map<String, Object> out = new LinkedHashMap<>();
      for (int j = 1; j < pairs.size(); j += 2) {
        out.put(condenseKey(condenseAt(sym, condenseIndex(pairs.get(j)))),
            condenseRebuild(sym, node, condenseIndex(condenseAt(pairs, j + 1))));
      }
      return out;
    }
    if (condenseIs(enc, CONDENSE_LIST)) {
      List<?> items = (List<?>) enc;
      List<Object> out = new ArrayList<>(items.size() - 1);
      for (int j = 1; j < items.size(); j++) {
        out.add(condenseRebuild(sym, node, condenseIndex(items.get(j))));
      }
      return out;
    }
    if (condenseIs(enc, CONDENSE_STR)) {
      return condenseAt(sym, condenseIndex(condenseAt((List<?>) enc, 1)));
    }
    if (condenseIs(enc, CONDENSE_NUM)) {
      return condenseAt((List<?>) enc, 1);
    }
    if (condenseIs(enc, CONDENSE_TRUE)) {
      return true;
    }
    if (condenseIs(enc, CONDENSE_FALSE)) {
      return false;
    }
    return null;
  }

  /**
   * Fully materialise a condensed structure; any other value comes back
   * unchanged. Correct for any caller, but it gives up every benefit of
   * condensing, so prefer a view or a path read.
   */
  public static Object expand(Object cond) {
    if (!iscondensed(cond)) {
      return cond;
    }
    return condenseMaterialise(cond, condenseRoot(cond));
  }

  // The keys of node idx, without materialising any of its values.
  private static List<String> condenseKeys(Object cond, int idx) {
    Object enc = condenseEnc(cond, idx);
    List<String> out = new ArrayList<>();
    if (condenseIs(enc, CONDENSE_MAP)) {
      List<?> sym = condenseList(cond, S_condsym);
      List<?> pairs = (List<?>) enc;
      for (int j = 1; j < pairs.size(); j += 2) {
        out.add(condenseKey(condenseAt(sym, condenseIndex(pairs.get(j)))));
      }
    } else if (condenseIs(enc, CONDENSE_LIST)) {
      for (int j = 1; j < ((List<?>) enc).size(); j++) {
        out.add(Integer.toString(j - 1));
      }
    }
    return out;
  }

  /**
   * A cursor into a condensed structure. Reads resolve by integer index and
   * touch only the nodes on the path, so a lookup costs path depth and result
   * size, never total structure size.
   */
  public static final class CondenseView {
    private final Object cond;
    private final int start;
    private final Map<Integer, Object> refmemo;

    private CondenseView(Object cond, int start, Map<Integer, Object> refmemo) {
      this.cond = cond;
      this.start = start;
      this.refmemo = refmemo;
    }

    /** The value at path, materialised: a container comes back as an independent copy. */
    public Object get(Object path) {
      return condenseMaterialise(cond, condenseResolve(cond, start, path));
    }

    public Object get() {
      return get(UNDEF);
    }

    /** Key names at path, with no value decoding at all. */
    public List<String> keys(Object path) {
      int at = condenseResolve(cond, start, path);
      return 0 > at ? new ArrayList<>() : condenseKeys(cond, at);
    }

    public List<String> keys() {
      return keys(UNDEF);
    }

    public boolean has(Object path) {
      return 0 <= condenseResolve(cond, start, path);
    }

    public boolean has() {
      return has(UNDEF);
    }

    /** A view at path, sharing this view's ref() memo. No decoding happens here. */
    public CondenseView at(Object path) {
      return condenseview(cond, condenseResolve(cond, start, path), refmemo);
    }

    public CondenseView at() {
      return at(UNDEF);
    }

    public Object value() {
      return condenseMaterialise(cond, start);
    }

    public int size() {
      Object enc = condenseEnc(cond, start);
      if (condenseIs(enc, CONDENSE_MAP)) {
        return (((List<?>) enc).size() - 1) / 2;
      }
      if (condenseIs(enc, CONDENSE_LIST)) {
        return ((List<?>) enc).size() - 1;
      }
      return 0;
    }

    public boolean exists() {
      return 0 <= start;
    }

    /**
     * A SHARED materialisation: the same object for the same node, every time.
     * Mutating it corrupts every other reader of that node, including ones
     * reached by a different path, because the structure is a DAG.
     */
    public Object ref() {
      Object got = refmemo.getOrDefault(start, UNDEF);
      if (UNDEF == got) {
        got = condenseMaterialise(cond, start);
        refmemo.put(start, got);
      }
      return got;
    }
  }

  public static CondenseView condenseview(Object cond) {
    return condenseview(cond, null, null);
  }

  public static CondenseView condenseview(Object cond, Integer idx) {
    return condenseview(cond, idx, null);
  }

  public static CondenseView condenseview(Object cond, Integer idx, Map<Integer, Object> memo) {
    int start = null != idx ? idx : iscondensed(cond) ? condenseRoot(cond) : -1;
    // The memo is threaded through at(), so every view into one structure
    // hands out the same ref() node.
    return new CondenseView(cond, start, null == memo ? new HashMap<>() : memo);
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

  // ===========================================================================
  // StructUtility — instance-based facade
  // ===========================================================================

  /**
   * Instance-based wrapper around the static Struct API. Mirrors TS
   * {@code StructUtility} (StructUtility.ts lines 2991–3056) for SDK callers
   * that prefer dependency-injected utility access. All methods delegate
   * directly to the corresponding static; sentinels and constants are exposed
   * as instance fields.
   */
  public static class StructUtility {
    // Sentinels
    public final Object UNDEF = Struct.UNDEF;
    public final Map<String, Object> SKIP = Struct.SKIP;
    public final Map<String, Object> DELETE = Struct.DELETE;

    // Type bit-flags
    public final int T_any = Struct.T_any;
    public final int T_noval = Struct.T_noval;
    public final int T_boolean = Struct.T_boolean;
    public final int T_decimal = Struct.T_decimal;
    public final int T_integer = Struct.T_integer;
    public final int T_number = Struct.T_number;
    public final int T_string = Struct.T_string;
    public final int T_function = Struct.T_function;
    public final int T_symbol = Struct.T_symbol;
    public final int T_null = Struct.T_null;
    public final int T_list = Struct.T_list;
    public final int T_map = Struct.T_map;
    public final int T_instance = Struct.T_instance;
    public final int T_scalar = Struct.T_scalar;
    public final int T_node = Struct.T_node;

    // Mode flags
    public final int M_KEYPRE = Struct.M_KEYPRE;
    public final int M_KEYPOST = Struct.M_KEYPOST;
    public final int M_VAL = Struct.M_VAL;
    public final Map<Integer, String> MODENAME = Struct.MODENAME;

    // Minor utilities
    public boolean isnode(Object v) { return Struct.isnode(v); }
    public boolean ismap(Object v) { return Struct.ismap(v); }
    public boolean islist(Object v) { return Struct.islist(v); }
    public boolean iskey(Object v) { return Struct.iskey(v); }
    public boolean isempty(Object v) { return Struct.isempty(v); }
    public boolean isfunc(Object v) { return Struct.isfunc(v); }
    public Object getdef(Object v, Object alt) { return Struct.getdef(v, alt); }
    public int size(Object v) { return Struct.size(v); }
    public Object slice(Object v, Object s, Object e) { return Struct.slice(v, s, e); }
    public String pad(Object v, Object p, Object c) { return Struct.pad(v, p, c); }
    public int typify(Object v) { return Struct.typify(v); }
    public String typename(int t) { return Struct.typename(t); }
    public String tn(int t) { return Struct.typename(t); }
    public Object getelem(Object v, Object k) { return Struct.getelem(v, k); }
    public Object getelem(Object v, Object k, Object alt) { return Struct.getelem(v, k, alt); }
    public Object getprop(Object v, Object k) { return Struct.getprop(v, k); }
    public Object getprop(Object v, Object k, Object alt) { return Struct.getprop(v, k, alt); }
    public String strkey(Object k) { return Struct.strkey(k); }
    public List<String> keysof(Object v) { return Struct.keysof(v); }
    public boolean haskey(Object v, Object k) { return Struct.haskey(v, k); }
    public List<List<Object>> items(Object v) { return Struct.items(v); }
    public List<Object> flatten(Object v, Integer d) { return Struct.flatten(v, d); }
    public List<Object> filter(Object v, ItemCheck c) { return Struct.filter(v, c); }
    public String escre(Object s) { return Struct.escre(s); }
    public String escurl(Object s) { return Struct.escurl(s); }
    public String join(Object a, Object s, Object u) { return Struct.join(a, s, u); }
    public String jsonify(Object v) { return Struct.jsonify(v); }
    public String jsonify(Object v, Object f) { return Struct.jsonify(v, f); }
    public String stringify(Object v) { return Struct.stringify(v); }
    public String stringify(Object v, Integer m) { return Struct.stringify(v, m); }
    public String pathify(Object v) { return Struct.pathify(v); }
    public String pathify(Object v, Object s, Object e) { return Struct.pathify(v, s, e); }
    public Object clone(Object v) { return Struct.clone(v); }
    public Map<String, Object> jm(Object... kv) { return Struct.jm(kv); }
    public List<Object> jt(Object... v) { return Struct.jt(v); }
    public Object delprop(Object p, Object k) { return Struct.delprop(p, k); }
    public Object setprop(Object p, Object k, Object v) { return Struct.setprop(p, k, v); }

    // Major utilities
    public Object walk(Object v, WalkApply b) { return Struct.walk(v, b); }
    public Object walk(Object v, WalkApply b, WalkApply a) { return Struct.walk(v, b, a); }
    public Object walk(Object v, WalkApply b, WalkApply a, int md) {
      return Struct.walk(v, b, a, md);
    }
    public Object merge(Object v) { return Struct.merge(v); }
    public Object merge(Object v, int md) { return Struct.merge(v, md); }
    public Object getpath(Object s, Object p) { return Struct.getpath(s, p); }
    public Object getpath(Object s, Object p, Map<String, Object> i) {
      return Struct.getpath(s, p, i);
    }
    public Object setpath(Object s, Object p, Object v) { return Struct.setpath(s, p, v); }
    public Object inject(Object v, Object s) { return Struct.inject(v, s); }
    public Object inject(Object v, Object s, Map<String, Object> i) {
      return Struct.inject(v, s, i);
    }
    public Object transform(Object d, Object s) { return Struct.transform(d, s); }
    public Object transform(Object d, Object s, Map<String, Object> o) {
      return Struct.transform(d, s, o);
    }
    public Object validate(Object d, Object s) { return Struct.validate(d, s); }
    public Object validate(Object d, Object s, Map<String, Object> o) {
      return Struct.validate(d, s, o);
    }
    public List<Object> select(Object c, Object q) { return Struct.select(c, q); }

    // Condense
    public Map<String, Object> condense(Object v) { return Struct.condense(v); }
    public Object expand(Object c) { return Struct.expand(c); }
    public boolean iscondensed(Object v) { return Struct.iscondensed(v); }
    public CondenseView condenseview(Object c) { return Struct.condenseview(c); }
    public CondenseView condenseview(Object c, Integer i) { return Struct.condenseview(c, i); }
    public CondenseView condenseview(Object c, Integer i, Map<Integer, Object> m) {
      return Struct.condenseview(c, i, m);
    }

    // Injection helpers
    public boolean checkPlacement(int m, String n, int pt, Injection i) {
      return Struct.checkPlacement(m, n, pt, i);
    }

    public Object[] injectorArgs(int[] argTypes, List<Object> args) {
      return Struct.injectorArgs(argTypes, args);
    }

    public Injection injectChild(Object c, Object s, Injection i) {
      return Struct.injectChild(c, s, i);
    }
  }
}
