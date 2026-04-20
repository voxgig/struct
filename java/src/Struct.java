import java.util.*;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import java.io.*;
import java.util.function.*;

enum InjectMode {
    KEY_PRE("key:pre"),
    KEY_POST("key:post"),
    VAL("val");
    
    private final String value;
    
    InjectMode(String value) {
        this.value = value;
    }
    
    public String getValue() {
        return value;
    }
}

// Injection state class
class InjectState {
    InjectMode mode;
    boolean full;
    int keyI;
    List<String> keys;
    String key;
    Object val;
    Object parent;
    List<String> path;
    List<Object> nodes;
    Function<InjectState, Object> handler;
    List<Object> errs;
    String base;
    BiFunction<Object, InjectState, Void> modify;
}

public class Struct {
    
    // String constants are explicitly defined.
    public static class S {
        public static final String MKEYPRE = "key:pre";
        public static final String MKEYPOST = "key:post";
        public static final String MVAL = "val";
        public static final String MKEY = "key";
        public static final String DKEY = "`$KEY`";
        public static final String DTOP = "$TOP";
        public static final String DERRS = "$ERRS";
        public static final String DMETA = "`$META`";
        public static final String ANY = "any";
        public static final String ARRAY = "array";
        public static final String BASE = "base";
        public static final String BOOLEAN = "boolean";
        public static final String DECIMAL = "decimal";
        public static final String EMPTY = "";
        public static final String FUNCTION = "function";
        public static final String INSTANCE = "instance";
        public static final String INTEGER = "integer";
        public static final String LIST = "list";
        public static final String MAP = "map";
        public static final String NIL = "nil";
        public static final String NODE = "node";
        public static final String NULL = "null";
        public static final String NUMBER = "number";
        public static final String OBJECT = "object";
        public static final String SCALAR = "scalar";
        public static final String STRING = "string";
        public static final String SYMBOL = "symbol";
        public static final String KEY = "key";
        public static final String PARENT = "parent";
        public static final String BT = "`";
        public static final String DS = "$";
        public static final String DT = ".";
        public static final String SP = " ";
        public static final String VIZ = ": ";
        public static final String KEY_NAME = "KEY";
    }

    // Type constants - bitfield integers matching TypeScript canonical.
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
        S.ANY, S.NIL, S.BOOLEAN, S.DECIMAL, S.INTEGER, S.NUMBER, S.STRING,
        S.FUNCTION, S.SYMBOL, S.NULL,
        "", "", "", "", "", "", "",
        S.LIST, S.MAP, S.INSTANCE,
        "", "", "", "",
        S.SCALAR, S.NODE,
    };
    
    /**
     * Callback invoked by {@link Struct#walk} at each node and leaf.
     *
     * <p><b>Path-reuse contract.</b> The {@code path} argument is a single
     * mutable list per depth, shared across all callback invocations for the
     * lifetime of a top-level {@code walk} call. Callers that need to retain
     * the path beyond the current invocation MUST clone it
     * (e.g. {@code new ArrayList<>(path)}); the contents will otherwise be
     * overwritten by subsequent visits.
     */
    @FunctionalInterface
    public interface WalkApply {
        Object apply(String key, Object val, Object parent, List<String> path);
    }

    @FunctionalInterface
    public interface WalkApplyOptional {
        Object apply(String key, Object val);
    }

    // Utility Methods
    public static boolean isNode(Object val) {
        return val instanceof Map || val instanceof List;
    }

    public static boolean isMap(Object val) {
        return val instanceof Map;
    }

    public static boolean isList(Object val) {
        return val instanceof List;
    }

    public static boolean isKey(Object key) {
        return (key instanceof String && !((String) key).isEmpty()) || key instanceof Integer;
    }

    public static boolean isEmpty(Object val) {
        return val == null ||
               (val instanceof String && ((String) val).isEmpty()) ||
               (val instanceof List && ((List<?>) val).isEmpty()) ||
               (val instanceof Map && ((Map<?, ?>) val).isEmpty());
    }

    public static boolean isFunc(Object val) {
        return val instanceof Runnable || val instanceof Function;
    }

    // Get type name string from type bitfield value.
    public static String typename(int t) {
        String tname = "";
        for (int tI = 0; tI < TYPENAME.length; tI++) {
            if (!TYPENAME[tI].isEmpty() && 0 < (t & (1 << (31 - tI)))) {
                tname = TYPENAME[tI];
            }
        }
        return tname;
    }

    // Determine the type of a value as a bitfield integer.
    public static int typify(Object value) {
        if (value == null) {
            return T_noval;
        }

        if (value instanceof Boolean) {
            return T_scalar | T_boolean;
        }

        if (value instanceof Integer || value instanceof Long) {
            return T_scalar | T_number | T_integer;
        }

        if (value instanceof Float || value instanceof Double) {
            double d = ((Number) value).doubleValue();
            if (Double.isNaN(d)) {
                return T_noval;
            }
            if (d == Math.floor(d) && !Double.isInfinite(d)) {
                return T_scalar | T_number | T_integer;
            }
            return T_scalar | T_number | T_decimal;
        }

        if (value instanceof String) {
            return T_scalar | T_string;
        }

        if (value instanceof Runnable || value instanceof Function) {
            return T_scalar | T_function;
        }

        if (value instanceof List) {
            return T_node | T_list;
        }

        if (value instanceof Map) {
            return T_node | T_map;
        }

        return T_any;
    }

    @SuppressWarnings("unchecked")
    public static List<Map.Entry<Object, Object>> items(Object val) {
    /*
        switch(val) {
          case Map _val -> {
            return new ArrayList<>(((Map<Object, Object>) _val).entrySet());
          }
          default -> Collections.emptyList();
        }
        */
        
        
        if (isMap(val)) {
            return new ArrayList<>(((Map<Object, Object>) val).entrySet());
        } else if (isList(val)) {
            List<?> list = (List<?>) val;
            List<Map.Entry<Object, Object>> result = new ArrayList<>();
            for (int i = 0; i < list.size(); i++) {
                result.add(new AbstractMap.SimpleEntry<>(i, list.get(i)));
            }
            return result;
        }
        return Collections.emptyList();
    }

    public static List<Object> keysof(Object val) {
        if (!isNode(val)) return Collections.emptyList();
        if (isMap(val)) return new ArrayList<>(((Map<?, ?>) val).keySet());
        if (isList(val)) return new ArrayList<>(
                Collections.nCopies(((List<?>) val).size(), 0)
        );
        return Collections.emptyList();
    }

    public static boolean hasKey(Object val, Object key) {
        return getProp(val, key, null) != null;
    }

    public static String stringify(Object val, Integer maxlen) {
        String json;
        try {
            json = Objects.toString(val, "");
        } catch (Exception e) {
            json = "";
        }
        json = json.replaceAll("\"", "");
        if (maxlen != null && maxlen < json.length()) {
            return json.substring(0, maxlen - 3) + "...";
        }
        return json;
    }
    
    public static String stringify(Object val) {
        String json;
        try {
            json = Objects.toString(val, "");
        } catch (Exception e) {
            json = "";
        }
        json = json.replaceAll("\"", "");
        return json;
    }
 
 /*   
    public static Object clone(Object val) {
        if (val == null) return null;

        List<Object> refs = new ArrayList<>();
        Pattern functionPattern = Pattern.compile("^`\\$FUNCTION:([0-9]+)`$");

        String jsonString = serialize(val, refs);
        return deserialize(jsonString, refs, functionPattern);
    }

    private static String serialize(Object val, List<Object> refs) {
        if (val == null) return "null";
        if (val instanceof Number || val instanceof Boolean) return val.toString();
        if (val instanceof String) return "\"" + val + "\"";

        if (val instanceof Function<?, ?>) {
            refs.add(val);
            return "\"`$FUNCTION:" + (refs.size() - 1) + "`\"";
        }

        if (val instanceof Map<?, ?>) {
            StringBuilder json = new StringBuilder("{");
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) val).entrySet()) {
                json.append("\"").append(entry.getKey()).append("\":")
                    .append(serialize(entry.getValue(), refs)).append(",");
            }
            if (json.length() > 1) json.setLength(json.length() - 1);
            return json.append("}").toString();
        }

        if (val instanceof List<?>) {
            StringBuilder json = new StringBuilder("[");
            for (Object item : (List<?>) val) {
                json.append(serialize(item, refs)).append(",");
            }
            if (json.length() > 1) json.setLength(json.length() - 1);
            return json.append("]").toString();
        }

        return "\"Unsupported Type\"";
    }

    private static Object deserialize(String jsonString, List<Object> refs, Pattern functionPattern) {
        
        // System.out.println(jsonString);
        
        // System.out.println(jsonString.matches(functionPattern.toString()));
        
        // if(jsonString.matches(functionPattern.toString())) return "F";
        if (jsonString.equals("null")) return null;
        if (jsonString.matches("^\".*\"$")) return jsonString.substring(1, jsonString.length() - 1);
        if (jsonString.matches("^-?\\d+(\\.\\d+)?$")) return jsonString.contains(".") ? Double.parseDouble(jsonString) : Integer.parseInt(jsonString);
        if (jsonString.equals("true") || jsonString.equals("false")) return Boolean.parseBoolean(jsonString);
        

        
        
        if(jsonString.matches(functionPattern.toString())) return "F";

        if (jsonString.startsWith("[") && jsonString.endsWith("]")) {
            List<Object> list = new ArrayList<>();
            String content = jsonString.substring(1, jsonString.length() - 1);
            String[] elements = content.split(",");
            for (String element : elements) {
                list.add(deserialize(element.trim(), refs, functionPattern));
            }
            return list;
        }

        if (jsonString.startsWith("{") && jsonString.endsWith("}")) {
            Map<String, Object> map = new HashMap<>();
            String content = jsonString.substring(1, jsonString.length() - 1);
            String[] pairs = content.split(",");
            for (String pair : pairs) {
                String[] kv = pair.split(":", 2);
                if (kv.length == 2) {
                    String key = kv[0].trim().replaceAll("^\"|\"$", "");
                    Object value = deserialize(kv[1].trim(), refs, functionPattern);
                    map.put(key, value);
                }
            }
            return map;
        }

        Matcher matcher = functionPattern.matcher(jsonString);
        if (matcher.matches()) {
            return refs.get(Integer.parseInt(matcher.group(1)));
        }

        return jsonString;
    }
    */

    public static Object clone(Object val) {
        if (val == null) return null;
        if (val instanceof Map) {
            Map<Object, Object> copy = new HashMap<>();
            ((Map<?, ?>) val).forEach((k, v) -> copy.put(k, clone(v)));
            return copy;
        } else if (val instanceof List) {
            List<Object> copy = new ArrayList<>();
            ((List<?>) val).forEach(v -> copy.add(clone(v)));
            return copy;
        }
        return val;
    }

    public static String escapeRegex(String s) {
        return s == null ? "" : Pattern.quote(s);
    }

    public static String escapeUrl(String s) throws UnsupportedEncodingException {
        return s == null ? "" : java.net.URLEncoder.encode(s, "UTF-8");
    }

    public static String joinUrl(String... parts) {
        return Arrays.stream(parts)
                .filter(Objects::nonNull)
                .map(s -> s.replaceAll("/+$", "").replaceAll("^/+", ""))
                .collect(Collectors.joining("/"));
    }

    @SuppressWarnings("unchecked")
    public static Object getProp(Object val, Object key, Object alt) {
        if (val instanceof Map && key instanceof String) {
            return ((Map<Object, Object>) val).getOrDefault(key, alt);
        } else if (val instanceof List && key instanceof Integer) {
            List<?> list = (List<?>) val;
            int index = (Integer) key;
            return (index >= 0 && index < list.size()) ? list.get(index) : alt;
        }
        return alt;
    }

    @SuppressWarnings("unchecked")
    public static <P> P setProp(P parent, Object key, Object val) {
        if (!isKey(key)) return parent;
        if (parent instanceof Map) {
            Map<Object, Object> map = (Map<Object, Object>) parent;
            if (val == null) {
                map.remove(key);
            } else {
                map.put(key, val);
            }
        } else if (parent instanceof List) {
            List<Object> list = (List<Object>) parent;
            int index = (Integer) key;
            if (index < 0) {
                list.add(0, val);
            } else if (index < list.size()) {
                list.set(index, val);
            } else {
                list.add(val);
            }
        }
        return parent;
    }
    
    // Walk a data structure depth first, applying a function to each value.
    // The `path` argument passed to the callback is a single mutable list per
    // depth, shared across all callback invocations for the lifetime of this
    // top-level walk call. Callbacks that need to store the path MUST clone
    // it (e.g. `new ArrayList<>(path)`); the contents will otherwise be
    // overwritten by subsequent visits.
    public static Object walk(Object val, WalkApply apply, String key, Object parent, List<String> path) {
        // Allocate a single pool of path arrays for this top-level call.
        // pool.get(n) is a list of length n holding the current path at depth n.
        List<List<String>> pool = new ArrayList<>();
        List<String> root = path == null ? new ArrayList<>() : path;
        pool.add(root);
        return walk(val, apply, key, parent, root, pool);
    }

    // Internal recursive walk that reuses path lists via a pool, avoiding
    // per-node allocation of fresh path arrays.
    private static Object walk(
        Object val,
        WalkApply apply,
        String key,
        Object parent,
        List<String> path,
        List<List<String>> pool
    ) {
        int depth = path.size();

        // If the value is a node (Map or List), recursively walk through it
        if (isNode(val)) {
            int childDepth = depth + 1;

            // Grow pool on demand; allocate each slot pre-sized to its depth.
            while (pool.size() <= childDepth) {
                int n = pool.size();
                pool.add(new ArrayList<>(Collections.nCopies(n, null)));
            }
            List<String> childPath = pool.get(childDepth);

            // Sync prefix [0..depth-1] from the current path. Only needed
            // once per parent: siblings share the same prefix and each
            // overwrite slot [depth] below.
            for (int i = 0; i < depth; i++) {
                childPath.set(i, path.get(i));
            }

            for (Map.Entry<Object, Object> entry : items(val)) {
                Object child = entry.getValue();
                String ckey = entry.getKey().toString();
                childPath.set(depth, S.EMPTY + ckey);
                // Recursively walk and update the value at each step
                setProp(val, entry.getKey(), walk(child, apply, ckey, val, childPath, pool));
            }
        }

        // Apply the function to the current node, after processing its children
        return apply.apply(key, val, parent, path);
    }
    
    // Walk function (Java version)
    public static Object walk(Object val, WalkApplyOptional apply, String key) {
        
        // If the value is a node (Map or List), recursively walk through it
        if (isNode(val)) {
            for (Map.Entry<Object, Object> entry : items(val)) {
                Object child = entry.getValue();
                String childKey = entry.getKey().toString();
                // Recursively walk and update the value at each step
                setProp(val, entry.getKey(), walk(child, apply, childKey));
            }
        }
        
        // Apply the function to the current node, after processing its children
        return apply.apply(key, val);
    }
    
  /*
      public static Object getPath(Object path, Map<String, Object> store, Object current, InjectState state) {
        // Operate on a string array
        String[] parts = null;

        if (isList(path)) {
            parts = (String[]) path;
        } else if (path instanceof String) {
            parts = splitPath((String) path);
        }

        if (parts == null) {
            return UNDEF;
        }

        Object root = store;
        Object val = store;

        // An empty path (including empty string) just finds the store.
        if (path == null || store == null || (parts.length == 1 && EMPTY.equals(parts[0]))) {
            // The actual store data may be in a store sub-property, defined by state.base.
            val = getProp(store, getProp(state, "base").toString());
        } else if (parts.length > 0) {
            int pI = 0;

            // Relative path uses `current` argument.
            if (EMPTY.equals(parts[0])) {
                pI = 1;
                root = current;
            }

            String part = (pI < parts.length) ? parts[pI] : null;
            Object first = getProp(root, part);

            // At top level, check state.base if provided
            val = (first == UNDEF && pI == 0) ? getProp(getProp(root, getProp(state, "base").toString()), part) : first;

            // Move along the path, trying to descend into the store.
            for (pI++; val != UNDEF && pI < parts.length; pI++) {
                val = getProp(val, parts[pI]);
            }
        }

        // State may provide a custom handler to modify the found value.
        if (state != null && state.getHandler() != null) {
            val = state.getHandler().apply(state, val, current, pathify(path), store);
        }

        return val;
    }
    
    
    
  public static Object merge(List<Object> objs) {
        Object out = null; // Equivalent to UNDEF in JS

        // Handle edge cases
        if (!isList(objs)) {
            out = objs;
        } else if (objs.isEmpty()) {
            out = null;
        } else if (objs.size() == 1) {
            out = objs.get(0);
        } else {
            out = getProp(objs, 0, new HashMap<>()); // Initialize with an empty map

            // Merge remaining down onto first
            for (int oI = 1; oI < objs.size(); oI++) {
                Object obj = objs.get(oI);

                if (!isNode(obj)) {
                    out = obj; // Non-node values override
                } else {
                    if (!isNode(out) || (isMap(obj) && isList(out)) || (isList(obj) && isMap(out))) {
                        out = obj; // Node type mismatch handling
                    } else {
                        // Node stack - traversing and merging
                        List<Object> cur = new ArrayList<>();
                        cur.add(out);
                        int cI = 0;

                        // Walk overriding node, creating paths in output as needed
                        walk(obj, (key, val, parent, path) -> {
                            if (key == null) {
                                return val; // Skip null keys
                            }

                            int lenPath = path.size();
                            cI = lenPath - 1;

                            // Get the current value at the path in out (not efficient, should optimize)
                            if (cur.get(cI) == null) {
                                cur.set(cI, getPath(path.subList(0, lenPath - 1), out));
                            }

                            // Create node if needed
                            if (!isNode(cur.get(cI))) {
                                cur.set(cI, isList(parent) ? new ArrayList<>() : new HashMap<>());
                            }

                            // If node child is just ahead on the stack
                            if (isNode(val) && !isEmpty(val)) {
                                setProp(cur.get(cI), key, cur.get(cI + 1));
                                cur.set(cI + 1, null);
                            } else {
                                setProp(cur.get(cI), key, val);
                            }

                            return val;
                        }, null, null, null);
                    }
                }
            }
        }

        return out;
    }
    */
    
    public static String pathify(Object val, Integer from) {
        if (from == null) {
            from = 1;  // Default value for from
        } else if (from < 1) {
            from = 1;  // Ensure from is at least 1
        }

        // If the value is a List (equivalent to Array.isArray in JS)
        if (val instanceof List) {
            List<?> listVal = (List<?>) val;
            // Slice the list starting from 'from' index
            List<?> path = listVal.subList(from, listVal.size());

            // If the path is empty, return <root>
            if (path.isEmpty()) {
                return "<root>";
            }
            // Join the list elements with '.' separator
            return String.join(".", (CharSequence[]) path.toArray(new String[0]));
        }

        // If val is not a list, just return its stringified value
        return stringify(val);
    }
    

   @SuppressWarnings("unchecked")
   public static void main(String[] args) {
        // Example usage with a sample Map
        Map<String, Object> sampleMap = new HashMap<>();
        sampleMap.put("key1", "value1");
        sampleMap.put("key2", new HashMap<>());
        
        walk(sampleMap, (key, val) -> {
            System.out.println("Walking key: " + key + ", value: " + val);
            return val;
        }, null);
        
        /*
        walk(sampleMap, (key, val, parent, path) -> {
            System.out.println("Walking key: " + key + ", value: " + val);
            return val;
        }, null, null, new ArrayList<>());
        */
        
        
        {
		Map<String, Object> original = new HashMap<>();
		Function<Integer, Integer> sampleFunction = (x) -> x * 2;
		original.put("name", "test");
		original.put("fn", sampleFunction);
		original.put("nested", Map.of("key", "value"));

		Object cloned = clone(original);
		
		// ((Map<String, Object>)cloned).put("name", "test1");
		
		System.out.println(original);
		System.out.println(cloned);
        }
        
    }
}

