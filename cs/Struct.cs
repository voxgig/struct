/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

// VERSION: @voxgig/struct 0.0.10

/* Voxgig Struct
 * =============
 *
 * Utility functions to manipulate in-memory JSON-like data
 * structures. These structures assumed to be composed of nested
 * "nodes", where a node is a list or map, and has named or indexed
 * fields.  The general design principle is "by-example". Transform
 * specifications mirror the desired output.  This implementation is
 * designed for porting to multiple language, and to be tolerant of
 * undefined values.
 *
 * Main utilities
 * - GetPath: get the value at a key path deep inside an object.
 * - Merge: merge multiple nodes, overriding values in earlier nodes.
 * - Walk: walk a node tree, applying a function at each node and leaf.
 * - Inject: inject values from a data store into a new data structure.
 * - Transform: transform a data structure to an example structure.
 * - Validate: validate a data structure against a shape specification.
 *
 * Minor utilities
 * - IsNode, IsMap, IsKey, IsList, IsFunc: identify value kinds.
 * - IsEmpty: undefined values, or empty nodes.
 * - KeysOf: sorted list of node keys (ascending).
 * - HasKey: true if key value is defined.
 * - Clone: create a copy of a JSON-like data structure.
 * - Items: list entries of a map or list as [key, value] pairs.
 * - GetProp: safely get a property value by key.
 * - SetProp: safely set a property value by key.
 * - Stringify: human-friendly string version of a value.
 * - EscRe: escape a regular expression string.
 * - EscUrl: escape a url.
 * - Join: join parts of a string, merging sep chars as needed.
 */

using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Voxgig.Struct;


// Type bit-flags (matching TypeScript).
public static class T
{
    private static int _t = 31;
    public static readonly int Any     = (1 << _t--) - 1;
    public static readonly int NoVal   = 1 << _t--;
    public static readonly int Boolean = 1 << _t--;
    public static readonly int Decimal = 1 << _t--;
    public static readonly int Integer = 1 << _t--;
    public static readonly int Number  = 1 << _t--;
    public static readonly int Str     = 1 << _t--;
    public static readonly int Func    = 1 << _t--;
    public static readonly int Symbol  = 1 << _t--;
    public static readonly int Null    = 1 << _t--;

    static T() { _t -= 7; }

    private static int _t2 = 31 - 10 - 7;
    public static readonly int List     = 1 << (_t2--);
    public static readonly int Map      = 1 << (_t2--);
    public static readonly int Instance = 1 << (_t2--);

    private static int _t3 = 31 - 10 - 7 - 3 - 4;
    public static readonly int Scalar = 1 << (_t3--);
    public static readonly int Node   = 1 << (_t3--);
}


public delegate object? WalkApply(object? key, object? val, object? parent, List<object?> path);
public delegate object? Modify(object? val, object? key, object? parent, object? inj, object? store);
public delegate object? Injector(InjectState inj, object? val, string? refStr, object? store);


public class InjectState
{
    public int      Mode    { get; set; }  // M_KEYPRE | M_KEYPOST | M_VAL
    public bool     Full    { get; set; }
    public int      KeyI    { get; set; }
    public List<object?> Keys   { get; set; } = [];
    public string?  Key     { get; set; }
    public object?  Val     { get; set; }
    public object?  Parent  { get; set; }
    public List<object?> Path   { get; set; } = [];
    public List<object?> Nodes  { get; set; } = [];
    public Injector? Handler { get; set; }
    public List<object?>? Errs  { get; set; } = null;
    public string?  Base    { get; set; }
    public Modify?  ModifyFn { get; set; }
    public object?  DParent { get; set; }
    public List<object?> DPath  { get; set; } = [];
    public InjectState? Prior  { get; set; }
    public Dictionary<string, object?> Meta { get; set; } = [];
    public object?  Extra   { get; set; }
    public object?  Root    { get; set; }

    public object? Descend()
    {
        if (!Meta.ContainsKey("__d")) Meta["__d"] = 0;
        Meta["__d"] = Convert.ToInt64(Meta["__d"]) + 1L;

        object? parentkey = StructUtils.GetElem(Path, -2);

        if (DParent == null)
        {
            if (StructUtils.Size(DPath) > 1)
                DPath = [..DPath, parentkey];
        }
        else
        {
            if (parentkey != null)
            {
                DParent = StructUtils.GetProp(DParent, parentkey);
                string pkStr = StructUtils.StrKey(parentkey);
                object? lastpart = StructUtils.GetElem(DPath, -1);
                string? lastStr = lastpart as string;
                if (lastStr == "$:" + pkStr)
                    DPath = [..DPath.Take(DPath.Count - 1)];
                else
                    DPath = [..DPath, parentkey];
            }
        }

        return DParent;
    }

    public InjectState Child(int keyI, List<object?> keys)
    {
        string keyStr = StructUtils.StrKey(keys[keyI]);
        // Parent / nodes must be the container (this.Val), not the child — same as TS
        // cinj.parent = val; cinj.val = getprop(val, key). Object initializer Val is assigned first,
        // so Parent = Val would wrongly use the child if written as a single block.
        object? parentNode = Val;
        var cinj = new InjectState
        {
            Mode    = Mode,
            Full    = false,
            KeyI    = keyI,
            Keys    = keys,
            Key     = keyStr,
            Val     = StructUtils.GetProp(parentNode, keyStr),
            Parent  = parentNode,
            Path    = [..Path, keyStr],
            Nodes   = [..Nodes, parentNode],
            Handler = Handler,
            Errs    = Errs,
            Meta    = Meta,
            Base    = Base,
            ModifyFn = ModifyFn,
            Prior   = this,
        };
        cinj.DPath   = [..DPath];
        cinj.DParent = DParent;
        cinj.Extra   = Extra;
        cinj.Root    = Root;
        return cinj;
    }

    public object? SetVal(object? val, int ancestor = 0)
    {
        // Match TS: setval(NONE) deletes the key; null also deletes.
        bool del = val == null || ReferenceEquals(val, StructUtils.NONE);
        if (ancestor < 2)
        {
            if (del) StructUtils.DelProp(Parent, Key);
            else     StructUtils.SetProp(Parent, Key, val);
            return Parent;
        }
        object? anode = StructUtils.GetElem(Nodes, -ancestor);
        object? akey  = StructUtils.GetElem(Path,  -ancestor);
        if (del) StructUtils.DelProp(anode, akey);
        else     StructUtils.SetProp(anode, akey, val);
        return anode;
    }
}


public static class StructUtils
{
    // Inject mode flags.
    public const int M_KEYPRE  = 1;
    public const int M_KEYPOST = 2;
    public const int M_VAL     = 4;

    // Special strings.
    public const string S_BKEY    = "`$KEY`";
    public const string S_BANNO   = "`$ANNO`";
    public const string S_BEXACT  = "`$EXACT`";
    public const string S_BVAL    = "`$VAL`";
    public const string S_DKEY    = "$KEY";
    public const string S_DTOP    = "$TOP";
    public const string S_DERRS   = "$ERRS";
    public const string S_DSPEC   = "$SPEC";

    // General strings.
    public const string S_list     = "list";
    public const string S_base     = "base";
    public const string S_boolean  = "boolean";
    public const string S_function = "function";
    public const string S_number   = "number";
    public const string S_object   = "object";
    public const string S_string   = "string";
    public const string S_decimal  = "decimal";
    public const string S_integer  = "integer";
    public const string S_map      = "map";
    public const string S_scalar   = "scalar";
    public const string S_node     = "node";
    public const string S_instance = "instance";
    public const string S_any      = "any";
    public const string S_nil      = "nil";
    public const string S_null     = "null";
    public const string S_key      = "key";

    // Character strings.
    public const string S_BT = "`";
    public const string S_CN = ":";
    public const string S_CS = "]";
    public const string S_DS = "$";
    public const string S_DT = ".";
    public const string S_FS = "/";
    public const string S_KEY = "KEY";
    public const string S_MT = "";
    public const string S_OS = "[";
    public const string S_SP = " ";
    public const string S_CM = ",";
    public const string S_VIZ = ": ";

    // Private markers.
    public static readonly Dictionary<string, object?> SKIP   = new() { ["`$SKIP`"] = true };
    public static readonly Dictionary<string, object?> DELETE = new() { ["`$DELETE`"] = true };

    // Sentinel for "value is not defined / absent" (analogous to TS undefined).
    // Use this to distinguish "value is null (JSON null)" from "value is not present".
    public static readonly object NONE = new();

    // Typename lookup (indexed by bit position from MSB of type code).
    private static readonly string[] TYPENAME =
    [
        S_any, S_nil, S_boolean, S_decimal, S_integer, S_number,
        S_string, S_function, S_nil, S_null,
        "", "", "", "", "", "", "",
        S_list, S_map, S_instance,
        "", "", "", "",
        S_scalar, S_node
    ];

    // Regular expressions.
    private static readonly Regex R_INTEGER_KEY        = new(@"^[-0-9]+$");
    private static readonly Regex R_ESCAPE_REGEXP      = new(@"[.*+?^${}()|[\]\\]");
    private static readonly Regex R_CLONE_REF          = new(@"^`\$REF:([0-9]+)`$");
    private static readonly Regex R_INJECTION_FULL     = new(@"^`(\$[A-Z]+|[^`]*)[0-9]*`$");
    private static readonly Regex R_INJECTION_PARTIAL  = new(@"`([^`]+)`");
    private static readonly Regex R_DOUBLE_DOLLAR      = new(@"\$\$");
    private static readonly Regex R_META_PATH          = new(@"^([^$]+)\$([=~])(.+)$");
    private static readonly Regex R_TRANSFORM_NAME     = new(@"`\$([A-Z]+)`");
    private static readonly Regex R_DOT                = new(@"\.");

    public const int MAXDEPTH = 32;


    // ========================================================================
    // Minor utilities
    // ========================================================================

    // Value is a node - a map (Dictionary) or list (List).
    public static bool IsNode(object? val) =>
        val is Dictionary<string, object?> || val is List<object?>;

    // Value is a map (Dictionary with string keys).
    public static bool IsMap(object? val) =>
        val is Dictionary<string, object?>;

    // Value is a list (List).
    public static bool IsList(object? val) =>
        val is List<object?>;

    // Value is a valid key: non-empty string or any number (matches TS where numbers are keys).
    public static bool IsKey(object? key)
    {
        if (key is string s) return s.Length > 0;
        if (key is int or long or double or float) return true;
        return false;
    }

    // Value is "empty": null, empty string, empty list, or empty map.
    public static bool IsEmpty(object? val)
    {
        if (val == null) return true;
        if (val is string s) return s.Length == 0;
        if (val is List<object?> l) return l.Count == 0;
        if (val is Dictionary<string, object?> d) return d.Count == 0;
        return false;
    }

    // Value is a delegate/function.
    public static bool IsFunc(object? val) =>
        val is Delegate;

    // Get a defined value; return alt if val is null.
    public static object? GetDef(object? val, object? alt) =>
        val ?? alt;

    // Return the typename for the narrowest type bit-flag.
    public static string TypeName(int t)
    {
        int pos = System.Numerics.BitOperations.LeadingZeroCount((uint)t);
        return pos < TYPENAME.Length ? TYPENAME[pos] : S_any;
    }

    // Determine the type of a value as a bit code.
    public static int Typify(object? value)
    {
        // Match TS: undefined/NONE → noval; JSON null is its own type (T_null), not noval.
        if (ReferenceEquals(value, NONE)) return T.NoVal;
        if (value == null) return T.Scalar | T.Null;

        return value switch
        {
            bool      => T.Scalar | T.Boolean,
            int       => T.Scalar | T.Number | T.Integer,
            long      => T.Scalar | T.Number | T.Integer,
            double d  => double.IsNaN(d) ? T.NoVal : double.IsInteger(d)
                            ? T.Scalar | T.Number | T.Integer
                            : T.Scalar | T.Number | T.Decimal,
            float f   => float.IsNaN(f) ? T.NoVal : (f % 1 == 0)
                            ? T.Scalar | T.Number | T.Integer
                            : T.Scalar | T.Number | T.Decimal,
            string    => T.Scalar | T.Str,
            Delegate  => T.Scalar | T.Func,
            List<object?> => T.Node | T.List,
            Dictionary<string, object?> => T.Node | T.Map,
            _ => T.Any,
        };
    }

    // The integer size of a value.
    public static int Size(object? val)
    {
        return val switch
        {
            List<string> ls            => ls.Count,
            List<object?> l            => l.Count,
            Dictionary<string, object?> d => d.Count,
            string s                   => s.Length,
            int i                      => i,
            long lg                    => (int)lg,
            double d                   => (int)Math.Floor(d),
            float f                    => (int)Math.Floor(f),
            bool b                     => b ? 1 : 0,
            _                          => 0,
        };
    }

    // Extract a sub-range from a list or string (negative indices count from end).
    // For numbers: clamp between start (inclusive) and end (exclusive).
    public static object? Slice(object? val, int? start = null, int? end = null, bool mutate = false)
    {
        if (val is int or long or double or float)
        {
            long lv = Convert.ToInt64(val);
            long lo = start.HasValue ? start.Value : long.MinValue;
            long hi = end.HasValue ? (long)end.Value - 1 : long.MaxValue;
            return Math.Min(Math.Max(lv, lo), hi);
        }

        int vlen = Size(val);

        if (end != null && start == null) start = 0;

        if (start == null) return val;

        int s = start.Value;
        int e;

        if (s < 0)
        {
            e = vlen + s;
            if (e < 0) e = 0;
            s = 0;
        }
        else if (end != null)
        {
            e = end.Value;
            if (e < 0)
            {
                e = vlen + e;
                if (e < 0) e = 0;
            }
            else if (vlen < e)
                e = vlen;
        }
        else
            e = vlen;

        if (s > vlen) s = vlen;

        if (s < 0 || s > e || e > vlen)
        {
            if (val is List<object?>) return new List<object?>();
            if (val is string) return S_MT;
            return val;
        }

        if (val is List<object?> list)
        {
            var sub = list.GetRange(s, e - s);
            if (mutate)
            {
                list.Clear();
                list.AddRange(sub);
                return list;
            }
            return sub;
        }
        if (val is string str)
            return str.Substring(s, e - s);

        return val;
    }

    // String padding.
    public static string Pad(object? str, int padding = 44, string? padchar = null)
    {
        string s = str is string ss ? ss : Stringify(str);
        string pc = padchar != null ? (padchar + S_SP)[0].ToString() : S_SP;
        if (padding >= 0)
            return s.PadRight(padding, pc[0]);
        return s.PadLeft(-padding, pc[0]);
    }

    // Get a list element by integer index (negative counts from end).
    public static object? GetElem(object? val, object? key, object? alt = null)
    {
        if (val == null || key == null) return alt;

        if (val is List<object?> list)
        {
            if (!int.TryParse(key?.ToString(), out int nkey)) return alt;
            if (!R_INTEGER_KEY.IsMatch(key!.ToString()!)) return alt;
            if (nkey < 0) nkey = list.Count + nkey;
            if (nkey < 0 || nkey >= list.Count) return alt;
            return list[nkey];
        }
        return alt is Delegate d2 ? d2.DynamicInvoke() : alt;
    }

    // Safely get a property of a node.
    public static object? GetProp(object? val, object? key, object? alt = null)
    {
        if (val == null || key == null) return alt;

        if (val is Dictionary<string, object?> map)
        {
            string k = StrKey(key) ?? S_MT;
            // Key present with JSON null → return null (TS: missing vs null).
            return map.TryGetValue(k, out object? v) ? v : alt;
        }
        if (val is List<object?> list)
        {
            string? ks = key?.ToString();
            if (ks != null && int.TryParse(ks, out int i))
            {
                if (i < 0) i = list.Count + i;
                if (i >= 0 && i < list.Count)
                    return list[i];
            }
            return alt;
        }

        return alt;
    }

    // Convert a key to its string representation.
    public static string? StrKey(object? key = null)
    {
        if (key == null) return S_MT;
        int t = Typify(key);
        if (0 < (T.Str & t)) return (string)key;
        if (0 < (T.Boolean & t)) return S_MT;
        if (0 < (T.Number & t))
        {
            double d = Convert.ToDouble(key);
            return ((long)Math.Floor(d)).ToString();
        }
        return S_MT;
    }

    // Sorted keys of a map (strings) or list (index strings).
    public static List<string> KeysOf(object? val)
    {
        if (val is Dictionary<string, object?> map)
        {
            var keys = map.Keys.ToList();
            keys.Sort(StringComparer.Ordinal);
            return keys;
        }
        if (val is List<object?> list)
            return Enumerable.Range(0, list.Count)
                             .Select(i => i.ToString())
                             .ToList();
        return [];
    }

    // True if the key exists with a non-null value in val.
    public static bool HasKey(object? val, object? key)
    {
        if (val == null || key == null) return false;
        if (val is Dictionary<string, object?> map)
        {
            string k = StrKey(key) ?? S_MT;
            return map.ContainsKey(k);
        }
        if (val is List<object?> list)
        {
            string? ks = key?.ToString();
            if (ks != null && int.TryParse(ks, out int i))
            {
                if (i < 0) i = list.Count + i;
                return i >= 0 && i < list.Count;
            }
            return false;
        }
        return false;
    }

    // Items of a map/list as [[key, value], ...] pairs.
    public static List<List<object?>> Items(object? val)
    {
        var keys = KeysOf(val);
        return keys.Select(k => (List<object?>)[k, GetProp(val, k)]).ToList();
    }

    // Items with a transform applied to each [key, value] pair.
    public static List<T2> Items<T2>(object? val, Func<List<object?>, T2> apply)
    {
        return Items(val).Select(apply).ToList();
    }

    // Flatten nested lists up to the given depth (default 1).
    public static List<object?> Flatten(List<object?> list, int depth = 1)
    {
        if (!IsList(list)) return list;
        if (depth <= 0) return list;
        var result = new List<object?>();
        foreach (var item in list)
        {
            if (item is List<object?> inner)
                result.AddRange(depth > 1 ? Flatten(inner, depth - 1) : inner);
            else
                result.Add(item);
        }
        return result;
    }

    // Filter items using a predicate on [key, value] pairs.
    public static List<object?> Filter(object? val, Func<List<object?>, bool> check)
    {
        var all = Items(val);
        var result = new List<object?>();
        foreach (var item in all)
            if (check(item)) result.Add(item[1]);
        return result;
    }

    // Escape for use in a regular expression.
    public static string EscRe(string? s)
    {
        if (s == null) return S_MT;
        return R_ESCAPE_REGEXP.Replace(s, m => @"\" + m.Value);
    }

    // URL-encode a string.
    public static string EscUrl(string? s)
    {
        if (s == null) return S_MT;
        return Uri.EscapeDataString(s);
    }

    // Replace in a string (all occurrences).
    private static string ReplaceStr(string? s, Regex from, string to)
    {
        if (s == null) return S_MT;
        return from.Replace(s, to);
    }

    // Join an array of strings with a separator, stripping leading/trailing separators.
    // Matches TypeScript: filter(items(filter(arr, string-non-empty), strip), non-empty).join(sep)
    public static string Join(List<object?> arr, string? sep = null, bool url = false)
    {
        string sepdef = sep ?? S_CM;
        string? sepre = sepdef.Length == 1 ? EscRe(sepdef) : null;
        int sarr = Size(arr);

        // Step 1: filter arr to non-empty strings.
        var step1 = Filter(arr, n => (0 < (T.Str & Typify(n[1]))) && (string?)n[1] != S_MT);

        // Step 2: items(step1, apply sep-stripping per element).
        var step2 = Items(step1, n =>
        {
            int i = int.Parse((string)n[0]!);
            string s = (string)n[1]!;

            if (sepre != null && sepre != S_MT)
            {
                if (url && i == 0)
                    return Regex.Replace(s, sepre + @"+$", S_MT);

                if (i > 0)
                    s = Regex.Replace(s, @"^" + sepre + @"+", S_MT);

                if (i < sarr - 1 || !url)
                    s = Regex.Replace(s, sepre + @"+$", S_MT);

                s = Regex.Replace(s, @"([^" + sepre + @"])" + sepre + @"+([^" + sepre + @"])",
                    "$1" + sepdef + "$2");
            }

            return s;
        });

        // Step 3: filter out empty and join.
        var nonEmpty = step2.Where(s => s != S_MT).ToList();
        return string.Join(sepdef, nonEmpty);
    }

    // Join URL parts.
    public static string JoinUrl(params string[] parts) =>
        Join(parts.Cast<object?>().ToList(), S_FS, url: true);

    // JSON.stringify-style output (indent = spaces per level, like TS jsonify flags.indent).
    public static string Jsonify(object? val, int indent = 2, int offset = 0)
    {
        if (val == null) return S_null;
        try
        {
            var opts = new JsonSerializerOptions
            {
                WriteIndented = indent > 0,
                Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            };
            string str = JsonSerializer.Serialize(SortKeys(val), opts);
            // System.Text.Json always uses 2 spaces per level; rescale to match TS JSON.stringify(,,indent).
            if (indent > 0 && indent != 2)
            {
                const int netPerLevel = 2;
                var lines = str.Split('\n');
                var rescaled = new List<string>(lines.Length);
                foreach (string line in lines)
                {
                    int lead = 0;
                    while (lead < line.Length && line[lead] == ' ') lead++;
                    int levels = lead / netPerLevel;
                    string rest = line[lead..];
                    rescaled.Add(levels == 0 ? rest : new string(' ', levels * indent) + rest);
                }
                str = string.Join("\n", rescaled);
            }
            if (offset > 0)
            {
                var lines = str.Split('\n').Skip(1).Select(l =>
                    Pad(l, -(offset + Size(l)))).ToList();
                return "{\n" + Join(lines.Cast<object?>().ToList(), "\n");
            }
            return str;
        }
        catch
        {
            return "__JSONIFY_FAILED__";
        }
    }

    // Human-friendly stringify (NOT JSON, removes quotes). Keys are sorted alphabetically.
    public static string Stringify(object? val, int? maxlen = null)
    {
        string valstr;
        if (val == null) return S_MT;

        if (val is string s)
        {
            valstr = s;
        }
        else
        {
            try
            {
                valstr = JsonSerializer.Serialize(SortKeys(val),
                    new JsonSerializerOptions
                    {
                        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
                    });
                valstr = valstr.Replace("\"", S_MT);
            }
            catch
            {
                return "__STRINGIFY_FAILED__";
            }
        }

        if (maxlen != null && maxlen >= 0)
        {
            if (valstr.Length > maxlen)
                valstr = valstr.Substring(0, Math.Max(0, maxlen.Value - 3)) + "...";
        }

        return valstr;
    }

    // Recursively sort dictionary keys for deterministic output (matches TS behavior).
    private static object? SortKeys(object? val)
    {
        if (val is Dictionary<string, object?> map)
        {
            var sorted = new Dictionary<string, object?>();
            foreach (var k in map.Keys.OrderBy(k => k, StringComparer.Ordinal))
                sorted[k] = SortKeys(map[k]);
            return sorted;
        }
        if (val is List<object?> list)
            return list.Select(SortKeys).ToList();
        return val;
    }

    // Build a human-friendly path string.
    // Pass StructUtils.NONE (not null) to indicate "path was not provided at all".
    public static string Pathify(object? val, int startIn = 0, int endIn = 0)
    {
        // Distinguish "truly absent" (NONE) from "explicitly null" (null).
        bool isNone = ReferenceEquals(val, NONE);
        if (isNone) val = null;

        List<object?>? path = null;

        if (val is List<object?> lv)          path = lv;
        else if (val is string sv)            path = [sv];
        else if (val is int or long or double or float)
            path = [val];

        int start = startIn >= 0 ? startIn : 0;
        int end   = endIn   >= 0 ? endIn   : 0;

        if (path == null)
        {
            // val=null → <unknown-path:null>, val=absent(NONE) → <unknown-path>
            string suffix = (val == null && !isNone) ? S_CN + "null" :
                            (val != null) ? S_CN + Stringify(val, 47) : S_MT;
            return "<unknown-path" + suffix + ">";
        }

        if (start >= 0)
        {
            var sub = Slice(path, start, path.Count - end) as List<object?> ?? [];
            if (sub.Count == 0) return "<root>";

            var parts = Filter(sub, n => IsKey(n[1]))
                        .Select(p =>
                        {
                            if (p is int pi)    return ((long)pi).ToString();
                            if (p is long pl)   return pl.ToString();
                            if (p is double pd) return ((long)Math.Floor(pd)).ToString();
                            if (p is float pf)  return ((long)Math.Floor(pf)).ToString();
                            return R_DOT.Replace((string)p!, S_MT);
                        })
                        .Cast<object?>()
                        .ToList();

            return Join(parts, S_DT);
        }

        string sfx = (val == null && !isNone) ? S_CN + "null" :
                     (val != null) ? S_CN + Stringify(val, 47) : S_MT;
        return "<unknown-path" + sfx + ">";
    }

    // Deep-clone a JSON-like structure (functions/instances are shallow-copied).
    public static object? Clone(object? val)
    {
        if (val == null) return null;

        var refs = new List<object?>();
        int reftype = T.Func | T.Instance;

        object? Replacer(object? v)
        {
            int tv = Typify(v);
            if (0 < (reftype & tv))
            {
                refs.Add(v);
                return "`$REF:" + (refs.Count - 1) + "`";
            }
            return v;
        }

        object? Reviver(object? v)
        {
            if (v is string sv)
            {
                var m = R_CLONE_REF.Match(sv);
                if (m.Success && int.TryParse(m.Groups[1].Value, out int idx))
                    return refs[idx];
            }
            return v;
        }

        return DeepClone(val, Replacer, Reviver);
    }

    private static object? DeepClone(object? val, Func<object?, object?> replacer, Func<object?, object?> reviver)
    {
        if (val == null) return null;
        var replaced = replacer(val);
        if (replaced is string refStr && R_CLONE_REF.IsMatch(refStr))
            return reviver(refStr);

        if (val is Dictionary<string, object?> map)
        {
            var result = new Dictionary<string, object?>();
            foreach (var kv in map)
                result[kv.Key] = DeepClone(kv.Value, replacer, reviver);
            return result;
        }
        if (val is List<object?> list)
            return list.Select(item => DeepClone(item, replacer, reviver)).ToList();

        return val;
    }

    // Safely set a property. Returns the (possibly modified) parent.
    public static object? SetProp(object? parent, object? key, object? val)
    {
        if (!IsKey(key)) return parent;

        if (parent is Dictionary<string, object?> map)
        {
            string k = StrKey(key) ?? S_MT;
            map[k] = val;
        }
        else if (parent is List<object?> list)
        {
            string? ks = key?.ToString();
            if (ks == null || !long.TryParse(ks, out long keyL)) return parent;
            int keyI = (int)Math.Floor((double)keyL);
            if (keyI >= 0)
            {
                int clamped = Convert.ToInt32(Slice(keyI, 0, list.Count + 1));
                while (list.Count <= clamped) list.Add(null);
                list[clamped] = val;
            }
            else
                list.Insert(0, val);
        }

        return parent;
    }

    // Safely delete a property. Returns the (possibly modified) parent.
    public static object? DelProp(object? parent, object? key)
    {
        if (!IsKey(key)) return parent;

        if (parent is Dictionary<string, object?> map)
        {
            string k = StrKey(key) ?? S_MT;
            map.Remove(k);
        }
        else if (parent is List<object?> list)
        {
            if (!int.TryParse(key?.ToString(), out int keyI)) return parent;
            keyI = (int)Math.Floor((double)keyI);
            if (keyI >= 0 && keyI < list.Count)
                list.RemoveAt(keyI);
        }

        return parent;
    }


    // ========================================================================
    // SetPath
    // ========================================================================

    // Set a value at path inside store. Returns the parent node where the
    // last key was set (matches TypeScript behavior).
    public static object? SetPath(object? store, object? path, object? val)
    {
        if (store == null) return null;

        int pathType = Typify(path);
        List<object?> parts;

        if (0 < (T.List & pathType) && path is List<object?> lp)
            parts = lp;
        else if (0 < (T.Str & pathType) && path is string ps)
            parts = ps.Split('.').Cast<object?>().ToList();
        else if (0 < (T.Number & pathType))
            parts = [path];
        else
            return null;

        if (parts.Count == 0) return null;

        object? parent = store;

        for (int pI = 0; pI < parts.Count - 1; pI++)
        {
            object? partKey = parts[pI];
            object? nextParent = GetProp(parent, partKey);
            if (!IsNode(nextParent))
            {
                // Create list if next key is numeric, otherwise map.
                object? nextPartKey = GetElem(parts, pI + 1);
                nextParent = (0 < (T.Number & Typify(nextPartKey)))
                    ? (object?)new List<object?>()
                    : new Dictionary<string, object?>();
                SetProp(parent, partKey, nextParent);
            }
            parent = nextParent;
        }

        object? lastKey = GetElem(parts, -1);
        if (val is Dictionary<string, object?> deleteMarker &&
            deleteMarker.ContainsKey("`$DELETE`"))
            DelProp(parent, lastKey);
        else
            SetProp(parent, lastKey, val);

        return parent;
    }


    // ========================================================================
    // GetPath
    // ========================================================================

    // Get the value at a dot-separated key path deep inside a store.
    // path: string ("a.b.c"), List<object?>, or number.
    // state: optional InjectState providing base, dparent, dpath, meta,
    //        key, and a post-processing handler.
    public static object? GetPath(object? path, object? store,
                                   object? current = null, InjectState? state = null)
    {
        // Resolve path to a mutable list of string parts.
        List<string> parts;
        if (path is List<object?> lp)
            parts = lp.Select(p => StrKey(p) ?? S_MT).ToList();
        else if (path is List<string> ls)
            parts = new List<string>(ls);
        else if (path is string sp)
            parts = sp == S_MT ? [S_MT] : sp.Split('.').ToList();
        else if (0 < (T.Number & Typify(path)))
            parts = [StrKey(path) ?? S_MT];
        else
            return null;

        string? baseKey = state?.Base;
        object? src     = GetProp(store, baseKey, store) ?? store;
        object? dparent = state?.DParent;
        int     numparts = parts.Count;

        object? val = store;

        // Empty path (or empty string path) → return src.
        if (path == null || store == null || (numparts == 1 && S_MT == parts[0]))
        {
            val = src;
        }
        else if (numparts > 0)
        {
            // Single-part path: check for $ACTION functions stored in the root.
            if (numparts == 1)
                val = GetProp(store, parts[0]);

            if (!IsFunc(val))
            {
                val = src;

                // Meta path syntax: "q0$~x" or "q0$=x" — navigate into meta.
                var m = R_META_PATH.Match(parts[0]);
                if (m.Success && state?.Meta != null)
                {
                    val     = GetProp(state.Meta, m.Groups[1].Value);
                    parts[0] = m.Groups[3].Value;
                }

                List<object?> dpath = state?.DPath ?? [];

                for (int pI = 0; val != null && pI < numparts; pI++)
                {
                    string part = parts[pI];

                    // Special path keywords and dynamic substitution.
                    if (state != null && part == S_DKEY)
                        part = state.Key ?? S_MT;
                    else if (state != null && part.StartsWith("$GET:"))
                    {
                        string sub = part[5..^1];
                        part = Stringify(GetPath(sub, src));
                    }
                    else if (state != null && part.StartsWith("$REF:"))
                    {
                        string sub     = part[5..^1];
                        object? specVal = GetProp(store, S_DSPEC);
                        part = specVal != null ? Stringify(GetPath(sub, specVal)) : S_MT;
                    }
                    else if (state != null && part.StartsWith("$META:"))
                    {
                        string sub = part[6..^1];
                        part = Stringify(GetPath(sub, state.Meta));
                    }

                    // $$ is an escape for a literal $.
                    part = part.Replace("$$", "$");

                    if (S_MT == part)
                    {
                        // Count consecutive empty parts (each "." adds one).
                        int ascends = 0;
                        while (1 + pI < numparts && S_MT == parts[1 + pI])
                        {
                            ascends++;
                            pI++;
                        }

                        if (state != null && ascends > 0)
                        {
                            // Last empty part cancels one ascend (the "." that
                            // ended the path string is a trailing separator).
                            if (pI == numparts - 1) ascends--;

                            if (ascends == 0)
                            {
                                val = dparent;
                            }
                            else
                            {
                                int dpathLen = dpath.Count;
                                int cutLen   = Math.Max(0, dpathLen - ascends);
                                var fullpath = new List<string>();
                                for (int i = 0; i < cutLen; i++)
                                    fullpath.Add(StrKey(dpath[i]) ?? S_MT);
                                if (pI + 1 < numparts)
                                    fullpath.AddRange(parts.Skip(pI + 1));

                                val = ascends <= dpathLen
                                    ? GetPath(fullpath.Cast<object?>().ToList(), store)
                                    : null;
                                break;
                            }
                        }
                        else
                        {
                            val = dparent;
                        }
                    }
                    else
                    {
                        val = GetProp(val, part);
                    }
                }
            }
        }

        // Optional post-processing via a handler function in the state.
        if (state?.Handler != null)
        {
            string refStr = Pathify(path);
            val = state.Handler(state, val, refStr, store);
        }

        return val;
    }


    // ========================================================================
    // Walk
    // ========================================================================

    // Walk a data structure depth-first, applying before/after callbacks.
    // key=null and parent=null at the root. path contains string keys.
    // maxdepth: null or negative → MAXDEPTH. 0 → no descent at all.
    // Stops descending when path.Count >= md (children beyond depth are not visited).
    public static object? Walk(
        object? val,
        WalkApply? before = null,
        WalkApply? after = null,
        int? maxdepth = null,
        object? key = null,
        object? parent = null,
        List<object?>? path = null)
    {
        path ??= [];

        object? out_ = before == null ? val : before(key, val, parent, path);

        int md = (maxdepth.HasValue && maxdepth.Value >= 0) ? maxdepth.Value : MAXDEPTH;
        if (md == 0 || path.Count >= md)
            return out_;

        if (IsNode(out_))
        {
            foreach (var item in Items(out_))
            {
                string ckey = StrKey(item[0]) ?? S_MT;
                object? child = item[1];
                var childPath = new List<object?>(path) { ckey };
                SetProp(out_, ckey, Walk(child, before, after, maxdepth, ckey, out_, childPath));
            }
        }

        out_ = after == null ? out_ : after(key, out_, parent, path);

        return out_;
    }


    // ========================================================================
    // Merge
    // ========================================================================

    // Merge a list of values into each other. Later values take precedence.
    // Nodes override scalars; mismatched node kinds override rather than merge.
    // maxdepth: null/-1 → MAXDEPTH (full deep merge). 0 → empty-shell output.
    public static object? Merge(object? val, int? maxdepth = null)
    {
        if (!IsList(val)) return val;

        int md = maxdepth.HasValue ? (maxdepth.Value < 0 ? 0 : maxdepth.Value) : MAXDEPTH;

        var list = (List<object?>)val!;
        int lenlist = list.Count;

        if (lenlist == 0) return null;
        if (lenlist == 1) return list[0];

        // Start with first element (or empty map if null).
        object? out_ = GetProp(list, 0) ?? new Dictionary<string, object?>();

        for (int oI = 1; oI < lenlist; oI++)
        {
            object? obj = list[oI];

            if (!IsNode(obj))
            {
                out_ = obj; // Scalar wins.
            }
            else
            {
                // cur[pI] = working value at depth pI in the output.
                // dst[pI] = existing value at depth pI in the destination (out_).
                var cur = new object?[MAXDEPTH + 2];
                var dst = new object?[MAXDEPTH + 2];
                cur[0] = out_;
                dst[0] = out_;

                WalkApply mergeBefore = (key, mval, _parent, path) =>
                {
                    int pI = path.Count;

                    if (md <= pI)
                    {
                        // Beyond max depth: copy directly.
                        if (key != null) SetProp(cur[pI - 1], key, mval);
                    }
                    else if (!IsNode(mval))
                    {
                        cur[pI] = mval;
                    }
                    else
                    {
                        // Navigate destination parallel to current override path.
                        if (pI > 0 && key != null)
                            dst[pI] = GetProp(dst[pI - 1], key);

                        object? tval = dst[pI];

                        if (tval == null && 0 == (T.Instance & Typify(mval)))
                        {
                            // Destination absent → create empty node.
                            cur[pI] = IsList(mval)
                                ? (object?)new List<object?>()
                                : new Dictionary<string, object?>();
                        }
                        else if (Typify(mval) == Typify(tval))
                        {
                            // Same type → merge into existing destination node.
                            cur[pI] = tval;
                        }
                        else
                        {
                            // Type mismatch → override wins, skip descending.
                            cur[pI] = mval;
                            mval = null;
                        }
                    }

                    return mval;
                };

                WalkApply mergeAfter = (key, _, _parent, path) =>
                {
                    int cI = path.Count;
                    if (key == null || cI <= 0) return cur[0];

                    object? value = cur[cI];
                    cur[cI - 1] = SetProp(cur[cI - 1], key, value) ?? cur[cI - 1];
                    return value;
                };

                Walk(obj, mergeBefore, mergeAfter, md);
                out_ = cur[0];
            }
        }

        // md=0: return empty shell of last element's type.
        if (md == 0)
        {
            out_ = GetElem(list, -1);
            if (IsList(out_)) out_ = new List<object?>();
            else if (IsMap(out_)) out_ = new Dictionary<string, object?>();
        }

        return out_;
    }


    // ========================================================================
    // Inject
    // ========================================================================

    // Default handler: invokes transform functions (keys starting with $)
    // or updates the parent node when a full-match injection is resolved.
    private static readonly Injector _InjectHandler = (inj, val, refStr, store) =>
    {
        object? out_ = val;
        bool iscmd = IsFunc(val) && (refStr == null || refStr.StartsWith(S_DS));
        if (iscmd && val is Injector injFn)
            out_ = injFn(inj, val, refStr, store);
        else if (inj.Mode == M_VAL && inj.Full)
            inj.SetVal(val);
        return out_;
    };


    // Inject store values into a string. Not a public utility – used by Inject.
    // Backtick-delimited references (e.g. "`a.b`") are resolved via GetPath.
    // A string that is entirely one reference returns the raw resolved value.
    // A string with embedded references has each one stringified in-place.
    private static object? _InjectStr(string val, object? store, object? current, InjectState? state)
    {
        if (val == S_MT) return S_MT;

        var m = R_INJECTION_FULL.Match(val);

        if (m.Success)
        {
            if (state != null) state.Full = true;
            string pathref = m.Groups[1].Value;
            // Unescape $BT → ` and $DS → $
            if (pathref.Length > 3)
                pathref = pathref.Replace("$BT", S_BT).Replace("$DS", S_DS);
            return GetPath(pathref, store, current, state);
        }

        // Replace every embedded `ref` with its stringified resolved value.
        object? outStr = R_INJECTION_PARTIAL.Replace(val, match =>
        {
            string ref_ = match.Groups[1].Value;
            if (ref_.Length > 3)
                ref_ = ref_.Replace("$BT", S_BT).Replace("$DS", S_DS);
            if (state != null) state.Full = false;
            object? found = GetPath(ref_, store, current, state);
            if (found == null)
            {
                // Distinguish an explicit null value (key exists) from a
                // missing key. Only top-level single-segment paths are checked.
                bool keyExists = !ref_.Contains('.')
                    && store is Dictionary<string, object?> sm
                    && sm.ContainsKey(ref_);
                return keyExists ? S_null : S_MT;
            }
            if (found is string fs) return fs;
            // Non-string, non-null → serialize as compact JSON.
            try
            {
                return System.Text.Json.JsonSerializer.Serialize(found,
                    new System.Text.Json.JsonSerializerOptions
                    {
                        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
                        WriteIndented = false,
                    });
            }
            catch { return Stringify(found); }
        });

        // Custom handler on the whole string (e.g. for post-processing by transforms).
        if (state?.Handler != null && IsFunc(state.Handler))
        {
            state.Full = true;
            outStr = state.Handler(state, outStr, val, store);
        }

        return outStr;
    }


    // Inject values from a data store into a node recursively.
    // Backtick-delimited path references in string values are replaced with
    // the resolved store values.  The optional state carries context for
    // recursive calls; callers at the root should pass null.
    public static object? Inject(object? val, object? store, InjectState? state = null)
    {
        // ── Root initialisation ──────────────────────────────────────────────
        if (state == null || state.Mode == 0)
        {
            // Wrap val inside a virtual {$TOP: val} parent so every code path
            // can use the same "set value in parent" logic.
            var parent = new Dictionary<string, object?> { [S_DTOP] = val };
            var newState = new InjectState
            {
                Mode    = M_VAL,
                Full    = false,
                KeyI    = 0,
                Keys    = [(object?)S_DTOP],
                Key     = S_DTOP,
                Val     = val,
                Parent  = parent,
                Path    = [(object?)S_DTOP],
                Nodes   = [(object?)parent],
                Handler = _InjectHandler,
                Base    = S_DTOP,
                Errs    = (GetProp(store, S_DERRS) as List<object?>) ?? [],
                Meta    = new Dictionary<string, object?> { ["__d"] = 0L },
                DParent = store,
                DPath   = [(object?)S_DTOP],
            };

            // Allow a partial injdef to override defaults.
            if (state != null)
            {
                if (state.ModifyFn != null) newState.ModifyFn = state.ModifyFn;
                if (state.Extra   != null) newState.Extra    = state.Extra;
                if (state.Meta    != null) newState.Meta     = state.Meta;
                if (state.Handler != null) newState.Handler  = state.Handler;
            }

            state = newState;
        }

        state.Descend();

        // ── Node: recurse into children ──────────────────────────────────────
        if (IsNode(val))
        {
            // Non-$ keys first (deterministic order), then $ transform keys.
            var allKeys = KeysOf(val);
            List<object?> keys;
            if (IsMap(val))
            {
                var normal    = allKeys.Where(k => !k.Contains(S_DS)).ToList();
                var transform = allKeys.Where(k =>  k.Contains(S_DS)).ToList();
                keys = [..normal.Cast<object?>(), ..transform.Cast<object?>()];
            }
            else
            {
                keys = allKeys.Cast<object?>().ToList();
            }

            int nkI = 0;
            while (nkI < keys.Count)
            {
                string nodekey = StrKey(keys[nkI]) ?? S_MT;
                var childinj = state.Child(nkI, keys);
                childinj.Mode = M_KEYPRE;

                object? preKey = _InjectStr(nodekey, store, state.DParent, childinj);

                // Read back any key-list / index modifications from the child.
                nkI  = childinj.KeyI;
                keys = childinj.Keys;
                val  = childinj.Parent;

                // TS: if (NONE !== prekey) — skip NONE/undefined (e.g. $CHILD KEYPRE). Also skip null prekey.
                if (preKey != null && !ReferenceEquals(preKey, NONE))
                {
                    object? childval = GetProp(val, preKey);
                    childinj.Val  = childval;
                    childinj.Mode = M_VAL;

                    Inject(childval, store, childinj);

                    nkI  = childinj.KeyI;
                    keys = childinj.Keys;
                    val  = childinj.Parent;

                    childinj.Mode = M_KEYPOST;
                    _InjectStr(nodekey, store, state.DParent, childinj);

                    nkI  = childinj.KeyI;
                    keys = childinj.Keys;
                    val  = childinj.Parent;
                }

                nkI++;
            }
        }

        // ── String scalar: resolve backtick references ──────────────────────
        else if (0 < (T.Str & Typify(val)) && val is string strVal)
        {
            state.Mode = M_VAL;
            object? injected = _InjectStr(strVal, store, state.DParent, state);
            bool isSkip = injected is Dictionary<string, object?> sd && sd.ContainsKey("`$SKIP`");
            if (!isSkip)
                state.SetVal(injected);
            val = injected;
        }

        // ── Custom modify callback ───────────────────────────────────────────
        if (state.ModifyFn != null)
        {
            bool isSkip = val is Dictionary<string, object?> sd2 && sd2.ContainsKey("`$SKIP`");
            if (!isSkip)
            {
                object? mparent = state.Parent;
                object? mval    = GetProp(mparent, state.Key);
                state.ModifyFn(mval, state.Key, mparent, state, store);
            }
        }

        state.Val = val;

        // The top-level return is the injected value extracted from its wrapper.
        return GetProp(state.Parent, S_DTOP);
    }


    // ========================================================================
    // Transform helpers
    // ========================================================================

    // Verify the injection mode is valid for a given transform.
    public static bool CheckPlacement(int modes, string name, int parentType, InjectState state)
    {
        static string PlacementName(int mode) =>
            mode == M_VAL ? "value" : S_key;

        if (0 == (modes & state.Mode))
        {
            var expected = new List<string>();
            foreach (int m in new[] { M_KEYPRE, M_KEYPOST, M_VAL })
                if (0 != (modes & m))
                    expected.Add(PlacementName(m));
            string exp = Join(expected.Cast<object?>().ToList(), ", ");
            state.Errs.Add($"${name}: invalid placement as {PlacementName(state.Mode)}, expected: {exp}.");
            return false;
        }
        if (parentType != 0 && parentType != T.Any && 0 == (parentType & Typify(state.Parent)))
        {
            state.Errs.Add($"${name}: invalid placement in parent {TypeName(Typify(state.Parent))}, " +
                $"expected: {TypeName(parentType)}.");
            return false;
        }
        return true;
    }

    // Validate injector arguments: returns [null|errMsg, arg0, arg1, ...].
    public static List<object?> InjectorArgs(List<int> argTypes, object? args)
    {
        var argslist = args as List<object?> ?? [];
        int numargs  = argTypes.Count;
        var found    = new List<object?> { null };   // found[0] = null means OK

        for (int ai = 0; ai < numargs; ai++)
        {
            object? arg     = GetElem(argslist, ai);
            int     argType = Typify(arg);
            if (0 == (argTypes[ai] & argType))
            {
                found[0] = $"invalid argument: {Stringify(arg, 22)} " +
                           $"({TypeName(argType)} at position {1 + ai}) " +
                           $"is not of type: {TypeName(argTypes[ai])}.";
                while (found.Count <= numargs) found.Add(null);
                return found;
            }
            found.Add(arg);
        }
        while (found.Count <= numargs) found.Add(null);
        return found;
    }

    // Create an inject child context to re-inject a sub-value in the right scope.
    private static InjectState _InjectChild(object? child, object? store, InjectState inj)
    {
        InjectState cinj = inj;
        if (inj.Prior != null)
        {
            if (inj.Prior.Prior != null)
            {
                cinj = inj.Prior.Prior.Child(inj.Prior.KeyI, inj.Prior.Keys);
                cinj.Val = child;
                SetProp(cinj.Parent, inj.Prior.Key, child);
            }
            else
            {
                cinj = inj.Prior.Child(inj.KeyI, inj.Keys);
                cinj.Val = child;
                SetProp(cinj.Parent, inj.Key, child);
            }
        }
        Inject(child, store, cinj);
        return cinj;
    }

    // ========================================================================
    // Transform sub-transforms
    // ========================================================================

    // Delete a key from its parent.
    private static readonly Injector _TransformDelete = (inj, val, refStr, store) =>
    {
        inj.SetVal(null);
        return null;
    };

    // Copy value from source data (DParent) at the same key.
    private static readonly Injector _TransformCopy = (inj, val, refStr, store) =>
    {
        if (!CheckPlacement(M_VAL, "COPY", T.Any, inj)) return null;
        object? out_ = GetProp(inj.DParent, inj.Key);
        inj.SetVal(out_);
        return out_;
    };

    // Return the key of the current node from $KEY meta or $ANNO or path.
    private static readonly Injector _TransformKey = (inj, val, refStr, store) =>
    {
        if (inj.Mode != M_VAL) return null;

        object? keyspec = GetProp(inj.Parent, S_BKEY);
        if (keyspec != null)
        {
            DelProp(inj.Parent, S_BKEY);
            return GetProp(inj.DParent, keyspec);
        }

        object? anno = GetProp(inj.Parent, S_BANNO);
        object? pkey = GetProp(anno, S_KEY);
        if (pkey != null) return pkey;

        return GetElem(inj.Path, -2);
    };

    // Remove the $ANNO annotation from the parent node.
    private static readonly Injector _TransformAnno = (inj, val, refStr, store) =>
    {
        DelProp(inj.Parent, S_BANNO);
        return null;
    };

    // Remove the $META annotation from the parent node.
    private static readonly Injector _TransformMeta = (inj, val, refStr, store) =>
    {
        DelProp(inj.Parent, "`$META`");
        return null;
    };

    // Merge a list of objects into the current node.
    private static readonly Injector _TransformMerge = (inj, val, refStr, store) =>
    {
        if (inj.Mode == M_KEYPRE) return inj.Key;

        if (inj.Mode == M_KEYPOST)
        {
            object? args = GetProp(inj.Parent, inj.Key);
            if (args is string sa && sa == S_MT)
                args = new List<object?> { GetProp(store, S_DTOP) };
            else if (!IsList(args))
                args = new List<object?> { args };

            inj.SetVal(null);   // remove the $MERGE key from parent

            if (args is not List<object?> list) return inj.Key;

            var mergeList = new List<object?> { inj.Parent };
            mergeList.AddRange(list);
            mergeList.Add(Clone(inj.Parent));
            Merge(mergeList);

            return inj.Key;
        }

        return null;  // VAL mode: skip
    };

    // Convert a node to a list by iterating over a source path.
    private static readonly Injector _TransformEach = (inj, val, refStr, store) =>
    {
        if (!CheckPlacement(M_VAL, "EACH", T.List, inj)) return null;

        // Truncate keys to just the first element.
        if (inj.Keys.Count > 1)
            inj.Keys.RemoveRange(1, inj.Keys.Count - 1);

        // Get args: ['`$EACH`', 'source-path', child-template]
        var parentList = inj.Parent as List<object?> ?? [];
        var sliced     = parentList.Count > 1 ? parentList.GetRange(1, parentList.Count - 1) : [];
        var args       = InjectorArgs([T.Str, T.Any], sliced);
        if (args[0] != null)
        {
            inj.Errs.Add("$EACH: " + args[0]);
            return null;
        }

        string  srcpath = (string)args[1]!;
        object? child   = args[2];

        // Source data.
        object? srcstore = GetProp(store, inj.Base, store);
        object? src      = GetPath(srcpath, srcstore, null, inj);
        int     srctype  = Typify(src);

        object? tval = null;

        if (0 < (T.List & srctype))
        {
            var sl = (List<object?>)src!;
            tval = sl.Select(_ => Clone(child)).ToList<object?>();
        }
        else if (0 < (T.Map & srctype))
        {
            tval = Items(src).Select(item => (object?)Merge(
                new List<object?> {
                    Clone(child),
                    new Dictionary<string, object?> { [S_BANNO] = new Dictionary<string, object?> { [S_KEY] = item[0] } }
                }, 1)).ToList<object?>();
        }

        var rval = new List<object?>();

        if (tval != null && Size(tval) > 0)
        {
            var tvalList = (List<object?>)tval;

            // Source values for DParent navigation.
            List<object?> srcVals;
            if (IsMap(src))
                srcVals = Items(src).Select(item => item[1]).ToList();
            else
                srcVals = src as List<object?> ?? [];

            string  ckey   = StrKey(GetElem(inj.Path, -2)) ?? S_DTOP;
            string  tkey   = ckey;
            object? target = GetElem(inj.Nodes, -2) ?? GetElem(inj.Nodes, -1);

            // tpath = path[:-1] (all but last element, same as Go)
            var tpath = inj.Path.Count > 0
                ? inj.Path.GetRange(0, inj.Path.Count - 1).Cast<object?>().ToList()
                : new List<object?>();

            // dpath: [$TOP, ...srcpath.split('.'), $:ckey, ...]
            var dpath = new List<object?> { (object?)S_DTOP };
            foreach (var p in srcpath.Split('.'))
                dpath.Add(p);
            dpath.Add("$:" + ckey);

            // tcur: {ckey: srcVals}
            object? tcur = (object?)new Dictionary<string, object?> { [ckey] = (object?)srcVals };

            if (tpath.Count > 1)
            {
                string pkey = StrKey(GetElem(inj.Path, -3)) ?? S_DTOP;
                tcur = new Dictionary<string, object?> { [pkey] = tcur };
                dpath.Add("$:" + pkey);
            }

            // Build tinj child state.
            var tinj = inj.Child(0, new List<object?> { (object?)ckey });
            tinj.Path  = tpath;
            tinj.Nodes = inj.Nodes.Count > 0
                ? new List<object?> { inj.Nodes[inj.Nodes.Count - 1] }
                : new List<object?>();
            tinj.Parent = tinj.Nodes.Count > 0 ? tinj.Nodes[tinj.Nodes.Count - 1] : null;

            SetProp(tinj.Parent, ckey, tvalList);
            tinj.Val     = tvalList;
            tinj.DPath   = dpath;
            tinj.DParent = tcur;

            Inject(tvalList, store, tinj);

            rval = tinj.Val as List<object?> ?? rval;
        }

        // Set result on the parent target.
        string  ftkey   = StrKey(GetElem(inj.Path, -2)) ?? S_DTOP;
        object? ftarget = GetElem(inj.Nodes, -2) ?? GetElem(inj.Nodes, -1);
        SetProp(ftarget, ftkey, rval);

        return rval.Count > 0 ? rval[0] : null;
    };

    // Convert a node to a map by packing source items.
    private static readonly Injector _TransformPack = (inj, val, refStr, store) =>
    {
        if (!CheckPlacement(M_KEYPRE, "PACK", T.Map, inj)) return null;

        // Get args: [srcpath, childspec]
        object? argsRaw  = GetProp(inj.Parent, inj.Key);
        var     argsList = argsRaw as List<object?> ?? [];
        var     args     = InjectorArgs([T.Str, T.Any], argsList);
        if (args[0] != null)
        {
            inj.Errs.Add("$PACK: " + args[0]);
            return null;
        }

        string  srcpath       = (string)args[1]!;
        object? origchildspec = args[2];

        // Target key and node.
        string  tkey   = StrKey(GetElem(inj.Path, -2)) ?? S_DTOP;
        int     psz    = inj.Path.Count;
        object? target = psz >= 2 ? inj.Nodes[psz - 2] : (psz >= 1 ? inj.Nodes[psz - 1] : null);

        // Source data.
        object? srcstore = GetProp(store, inj.Base, store);
        object? src      = GetPath(srcpath, srcstore, null, inj);

        // Normalise src to a flat list.
        if (!IsList(src))
        {
            if (IsMap(src))
            {
                src = Items(src).Select(item =>
                {
                    var node = item[1];
                    if (IsMap(node))
                        SetProp(node, S_BANNO, new Dictionary<string, object?> { [S_KEY] = item[0] });
                    return node;
                }).ToList<object?>();
            }
            else return null;
        }

        if (src == null) return null;

        // Extract keypath and child template.
        object? keypath   = GetProp(origchildspec, S_BKEY);
        object? childspec = DelProp(Clone(origchildspec), S_BKEY) ?? origchildspec;
        object? child     = GetProp(childspec, S_BVAL, childspec);

        var srclist = (List<object?>)src;

        // Resolve output key for a source item.
        string ResolveKey(object? srcItem, int idx)
        {
            if (keypath == null) return idx.ToString();
            if (keypath is not string kpStr) return "";
            if (kpStr.StartsWith("`"))
            {
                // inject keypath with srcItem as $TOP
                var ks = new Dictionary<string, object?>(store is Dictionary<string, object?> sd ? sd : []) { [S_DTOP] = srcItem };
                var kr = Inject(kpStr, ks);
                return kr?.ToString() ?? "";
            }
            else
            {
                var kval = GetPath(kpStr, srcItem, null, inj);
                return kval?.ToString() ?? "";
            }
        }

        // Build tval (output map with injected children).
        var tval = new Dictionary<string, object?>();

        for (int i = 0; i < srclist.Count; i++)
        {
            object? srcItem = srclist[i];
            string  outKey  = ResolveKey(srcItem, i);
            if (outKey == "") continue;

            object? tchild = Clone(child);

            // Forward $ANNO from src (for map sources annotated above).
            object? anno = GetProp(srcItem, S_BANNO);
            if (anno != null && IsMap(tchild))
                SetProp(tchild, S_BANNO, anno);
            else if (anno == null && IsMap(tchild))
                DelProp(tchild, S_BANNO);

            tval[outKey] = tchild;
        }

        var rval = new Dictionary<string, object?>();

        if (tval.Count > 0)
        {
            // Build parallel source map for DParent navigation.
            var tsrc = new Dictionary<string, object?>();
            for (int i = 0; i < srclist.Count; i++)
            {
                string ok = ResolveKey(srclist[i], i);
                if (ok != "") tsrc[ok] = srclist[i];
            }

            string  ckey  = tkey;
            var     tpath = inj.Path.Count > 0
                ? inj.Path.GetRange(0, inj.Path.Count - 1).Cast<object?>().ToList()
                : new List<object?>();

            var dpath = new List<object?> { (object?)S_DTOP };
            foreach (var p in srcpath.Split('.'))
                dpath.Add(p);
            dpath.Add("$:" + ckey);

            object? tcur = (object?)new Dictionary<string, object?> { [ckey] = (object?)tsrc };

            if (tpath.Count > 1)
            {
                string pkey = StrKey(GetElem(inj.Path, -3)) ?? S_DTOP;
                tcur = new Dictionary<string, object?> { [pkey] = tcur };
                dpath.Add("$:" + pkey);
            }

            var tinj = inj.Child(0, new List<object?> { (object?)ckey });
            tinj.Path  = tpath;
            tinj.Nodes = new List<object?> { inj.Nodes.Count > 0 ? inj.Nodes[inj.Nodes.Count - 1] : null };
            tinj.Parent = tinj.Nodes[0];
            tinj.Val    = tval;
            tinj.DPath  = dpath;
            tinj.DParent = tcur;

            Inject(tval, store, tinj);

            if (tinj.Val is Dictionary<string, object?> rv) rval = rv;
        }

        SetProp(target, tkey, rval);
        return null;
    };

    // Reference a value from the original spec.
    private static readonly Injector _TransformRef = (inj, val, refStr, store) =>
    {
        if (inj.Mode != M_VAL) return null;

        // Get refpath from parent list element 1.
        object? refpath = GetProp(inj.Parent, 1);
        inj.KeyI = inj.Keys.Count;   // skip remaining keys

        // Get the original spec via $SPEC function.
        object? specFn = GetProp(store, S_DSPEC);
        if (specFn == null) return null;
        object? spec = specFn is Injector si ? si(inj, null, null, store) : null;
        if (spec == null) return null;

        // Build dpath from current path (skip first element "$TOP").
        var dpath = inj.Path.Count > 1
            ? inj.Path.GetRange(1, inj.Path.Count - 1).Select(p => (object?)(StrKey(p) ?? S_MT)).ToList()
            : new List<object?>();
        var dpathInj = new InjectState
        {
            DPath   = dpath,
            DParent = GetPath(dpath.Cast<object?>().ToList(), spec)
        };

        object? refResult = GetPath(refpath, spec, null, dpathInj);

        // Check if refResult contains sub-references.
        bool hasSubRef = false;
        if (IsNode(refResult))
            Walk(refResult, (k, v, parent2, path2) =>
            {
                if (v is string sv && sv == "`$REF`") hasSubRef = true;
                return v;
            });

        object? tref    = Clone(refResult);
        int     pathLen = inj.Path.Count;

        var cpath = pathLen > 3
            ? inj.Path.GetRange(0, pathLen - 3).Cast<object?>().ToList()
            : new List<object?>();
        var tpath = pathLen >= 1
            ? inj.Path.GetRange(0, pathLen - 1).Cast<object?>().ToList()
            : new List<object?>();

        object? tcur    = GetPath(cpath, store, null, null);
        object? tvalRef = GetPath(tpath, store, null, null);

        if (!hasSubRef || tvalRef != null)
        {
            string lastPath = tpath.Count > 0
                ? (StrKey(tpath[tpath.Count - 1]) ?? S_DTOP)
                : S_DTOP;

            var tinj = inj.Child(0, new List<object?> { (object?)lastPath });
            tinj.Path = tpath;

            int nodesLen = inj.Nodes.Count;
            tinj.Nodes  = nodesLen > 1
                ? inj.Nodes.GetRange(0, nodesLen - 1).Cast<object?>().ToList()
                : new List<object?>();
            tinj.Parent  = nodesLen >= 2 ? inj.Nodes[nodesLen - 2] : null;
            tinj.Val     = tref;
            tinj.DPath   = cpath;
            tinj.DParent = tcur;

            Inject(tref, store, tinj);
            object? rval = tinj.Val;

            inj.SetVal(rval, 2);

            if (IsList(GetElem(inj.Nodes, -2)) && inj.Prior != null)
                inj.Prior.KeyI--;
        }
        else
        {
            // Circular self-reference with no data: delete the key from the grandparent.
            inj.SetVal(null, 2);
            if (IsList(GetElem(inj.Nodes, -2)) && inj.Prior != null)
                inj.Prior.KeyI--;
        }

        return val;
    };

    // Apply a named format function to a child value.
    private static readonly Injector _TransformFormat = (inj, val, refStr, store) =>
    {
        // Truncate remaining keys.
        if (inj.Keys.Count > 1)
            inj.Keys.RemoveRange(1, inj.Keys.Count - 1);

        if (inj.Mode != M_VAL) return null;

        object? name  = GetProp(inj.Parent, 1);
        object? child = GetProp(inj.Parent, 2);

        // Resolve child through injection using the proper DParent context.
        var rcInj = _InjectChild(child, store, inj);
        object? resolved = rcInj.Val;

        // Target key and node.
        string  tkey   = StrKey(GetElem(inj.Path, -2)) ?? S_DTOP;
        int     psz    = inj.Path.Count;
        object? target = psz >= 2 ? GetElem(inj.Nodes, -2) : GetElem(inj.Nodes, -1);

        // Helper: scalar to string.
        static string FmtStr(object? v) => v switch
        {
            null   => "null",
            bool b => b ? "true" : "false",
            _      => v.ToString() ?? "null",
        };

        // Determine formatter.
        WalkApply? formatter = null;

        if (name is string nameStr)
        {
            formatter = nameStr switch
            {
                "upper"  => (k, v, p, path) => IsNode(v) ? v : (object?)FmtStr(v).ToUpper(),
                "lower"  => (k, v, p, path) => IsNode(v) ? v : (object?)FmtStr(v).ToLower(),
                "string" => (k, v, p, path) => IsNode(v) ? v : (object?)FmtStr(v),
                "number" => (k, v, p, path) =>
                {
                    if (IsNode(v)) return v;
                    if (v is long li) return (object?)li;
                    if (v is double di) return (object?)di;
                    if (v is string sv) return double.TryParse(sv, out double d) ? (object?)d : 0;
                    return (object?)0;
                },
                "integer" => (k, v, p, path) =>
                {
                    if (IsNode(v)) return v;
                    if (v is long li) return (object?)li;
                    if (v is double di) return (object?)(long)di;
                    if (v is string sv) return double.TryParse(sv, out double d) ? (object?)(long)d : (object?)0L;
                    return (object?)0L;
                },
                "concat" => (k, v, p, path) =>
                {
                    if (k == null && IsList(v))
                    {
                        var parts2 = (v as List<object?>)!.Select(x => IsNode(x) ? "" : FmtStr(x));
                        return (object?)string.Join("", parts2);
                    }
                    return v;
                },
                "identity" => (k, v, p, path) => v,
                _ => null,
            };

            if (formatter == null)
            {
                inj.Errs.Add($"$FORMAT: unknown format: {nameStr}.");
                SetProp(target, tkey, null);
                return null;
            }
        }
        else
        {
            inj.Errs.Add($"$FORMAT: unknown format: {Stringify(name)}.");
            SetProp(target, tkey, null);
            return null;
        }

        // Apply formatter.
        object? out_;
        if (!IsNode(resolved))
            out_ = formatter(null, resolved, null, []);
        else if (name is string ns && ns == "concat")
            out_ = formatter(null, resolved, null, []);
        else
            out_ = Walk(resolved, before: formatter);

        SetProp(target, tkey, out_);
        return out_;
    };

    // Apply a function to a child value.
    private static readonly Injector _TransformApply = (inj, val, refStr, store) =>
    {
        if (inj.Keys.Count > 1)
            inj.Keys.RemoveRange(1, inj.Keys.Count - 1);

        if (!CheckPlacement(M_VAL, "APPLY", T.List, inj)) return null;

        var parentList = inj.Parent as List<object?> ?? [];
        var sliced     = parentList.Count > 1 ? parentList.GetRange(1, parentList.Count - 1) : [];
        var args       = InjectorArgs([T.Func, T.Any], sliced);

        string  tkey   = StrKey(GetElem(inj.Path, -2)) ?? S_DTOP;
        object? target = GetElem(inj.Nodes, -2) ?? GetElem(inj.Nodes, -1);

        if (args[0] != null)
        {
            inj.Errs.Add("$APPLY: " + args[0]);
            SetProp(target, tkey, null);
            return null;
        }

        object? applyFn = args[1];
        object? child2  = args[2];

        // Resolve child.
        object? resolved = child2;
        if (child2 is string cs)
            resolved = _InjectStr(cs, store, inj.DParent, inj);

        // Invoke.
        object? out_ = null;
        if (applyFn is Func<object?, object?> fn1)
            out_ = fn1(resolved);
        else if (applyFn is Func<object?, object?, object?, object?> fn3)
            out_ = fn3(resolved, store, inj);
        else if (applyFn is Injector aInj)
            out_ = aInj(inj, resolved, null, store);

        SetProp(target, tkey, out_);
        return out_;
    };


    // ========================================================================
    // Transform
    // ========================================================================

    public static object? Transform(object? data, object? spec, InjectState? injdef = null)
    {
        object? origspec = spec;
        spec = Clone(spec);

        // Separate extra-data from extra-transforms (keys starting with $).
        var extraTransforms = new Dictionary<string, object?>();
        var extraData       = new Dictionary<string, object?>();

        object? extra = injdef?.Extra;
        if (extra != null)
        {
            foreach (var kv in Items(extra))
            {
                string k = kv[0]?.ToString() ?? "";
                if (k.StartsWith(S_DS))
                    extraTransforms[k] = kv[1];
                else
                    extraData[k] = kv[1];
            }
        }

        // Merge extra data + source data (match TS: clone(data), no default map when data is null).
        object? dataClone = Merge(new List<object?>
        {
            IsEmpty(extraData) ? null : Clone(extraData),
            Clone(data),
        });

        // Build the transform store.
        var store = new Dictionary<string, object?>
        {
            [S_DTOP]     = dataClone,
            [S_DSPEC]    = (Injector)((inj2, v, r, s) => Clone(origspec)),
            ["$BT"]      = (Injector)((inj2, v, r, s) => (object?)S_BT),
            ["$DS"]      = (Injector)((inj2, v, r, s) => (object?)S_DS),
            ["$WHEN"]    = (Injector)((inj2, v, r, s) => (object?)DateTime.UtcNow.ToString("o")),
            ["$DELETE"]  = (Injector)_TransformDelete,
            ["$COPY"]    = (Injector)_TransformCopy,
            ["$KEY"]     = (Injector)_TransformKey,
            ["$ANNO"]    = (Injector)_TransformAnno,
            ["$META"]    = (Injector)_TransformMeta,
            ["$MERGE"]   = (Injector)_TransformMerge,
            ["$MERGE0"]  = (Injector)_TransformMerge,
            ["$MERGE1"]  = (Injector)_TransformMerge,
            ["$EACH"]    = (Injector)_TransformEach,
            ["$PACK"]    = (Injector)_TransformPack,
            ["$REF"]     = (Injector)_TransformRef,
            ["$FORMAT"]  = (Injector)_TransformFormat,
            ["$APPLY"]   = (Injector)_TransformApply,
        };

        // Merge extra transforms into the store.
        foreach (var kv in extraTransforms)
            store[kv.Key] = kv.Value;

        // Error collection: collect=true when caller explicitly provided an errs list.
        bool            collect = injdef?.Errs != null;
        List<object?>   errs    = injdef?.Errs ?? [];
        store[S_DERRS] = errs;

        // Build an inject state with any overrides from injdef.
        var injState = new InjectState
        {
            ModifyFn = injdef?.ModifyFn,
            Extra    = injdef?.Extra,
            Meta     = injdef?.Meta ?? new Dictionary<string, object?>(),
            Handler  = injdef?.Handler,
        };

        object? out_ = Inject(spec, store, injState);

        if (errs.Count > 0 && !collect)
            throw new InvalidOperationException(string.Join(" | ", errs.Select(e => e?.ToString() ?? "")));

        return out_;
    }


    // ========================================================================
    // VALIDATE
    // ========================================================================

    // Build a "Expected X, but found Y: v." error message.
    private static string _InvalidTypeMsg(object? path, string needtype, int vt, object? v)
    {
        // TS: null == v → "no value"; NONE is undefined in TS and uses the same wording.
        bool absent = v == null || ReferenceEquals(v, NONE);
        string vs   = absent ? "no value" : Stringify(v);
        string loc  = Size(path) > 1 ? "field " + Pathify(path, 1) + " to be " : "";
        string found = !absent ? TypeName(vt) + S_VIZ : "";
        return "Expected " + loc + needtype + ", but found " + found + vs + S_DT;
    }

    // Require a non-empty string.
    private static readonly Injector _ValidateString = (inj, val, refStr, store) =>
    {
        bool keyExists = TryGetDataValue(inj.DParent, inj.Key, out object? out_);
        int  t         = keyExists ? Typify(out_) : T.NoVal;

        if (0 == (T.Str & t))
        {
            inj.Errs.Add(_InvalidTypeMsg(inj.Path, S_string, t, keyExists ? out_ : NONE));
            return NONE;
        }

        if (S_MT == out_ as string)
        {
            inj.Errs.Add("Empty string at " + Pathify(inj.Path, 1));
            return NONE;
        }

        return out_;
    };

    // Require a value of the named type ($NUMBER, $INTEGER, etc.).
    private static readonly Injector _ValidateType = (inj, val, refStr, store) =>
    {
        string tname = refStr != null && refStr.Length > 1 ? refStr.Substring(1).ToLower() : "";
        int idx   = Array.IndexOf(TYPENAME, tname);
        int typev = idx >= 0 ? (1 << (31 - idx)) : 0;

        bool keyExists = TryGetDataValue(inj.DParent, inj.Key, out object? out_);
        int  t         = keyExists ? Typify(out_) : T.NoVal;

        if (0 == (t & typev))
        {
            inj.Errs.Add(_InvalidTypeMsg(inj.Path, tname, t, keyExists ? out_ : NONE));
            return NONE;
        }

        return out_;
    };

    // Allow any value without type check.
    private static readonly Injector _ValidateAny = (inj, val, refStr, store) =>
        GetProp(inj.DParent, inj.Key);

    // Validate every child of a map or list against a template.
    private static readonly Injector _ValidateChild = (inj, val, refStr, store) =>
    {
        int mode = inj.Mode;

        // Map syntax: {'`$CHILD`': childTemplate} — runs at M_KEYPRE.
        if (M_KEYPRE == mode)
        {
            object? childtm = GetProp(inj.Parent, inj.Key);

            object? pkey = GetElem(inj.Path, -2);
            object? tval = GetProp(inj.DParent, pkey);

            if (tval == NONE || tval == null)
                tval = new Dictionary<string, object?>();
            else if (!IsMap(tval))
            {
                inj.Errs.Add(_InvalidTypeMsg(Slice(inj.Path, -1), S_object, Typify(tval), tval));
                inj.SetVal(NONE);
                return NONE;
            }

            foreach (string ckey in KeysOf(tval))
            {
                SetProp(inj.Parent, ckey, Clone(childtm));
                inj.Keys.Add(ckey);
            }

            inj.SetVal(NONE);
            return NONE;
        }

        // List syntax: ['`$CHILD`', childTemplate] — runs at M_VAL.
        if (M_VAL == mode)
        {
            if (!IsList(inj.Parent))
            {
                inj.Errs.Add("Invalid $CHILD as value");
                return NONE;
            }

            object? childtm = GetProp(inj.Parent, 1);

            if (inj.DParent == NONE || inj.DParent == null)
            {
                Slice(inj.Parent, 0, 0, true);
                return NONE;
            }

            if (!IsList(inj.DParent))
            {
                string msg = _InvalidTypeMsg(
                    Slice(inj.Path, -1), S_list, Typify(inj.DParent), inj.DParent);
                inj.Errs.Add(msg);
                inj.KeyI = Size(inj.Parent);
                return inj.DParent;
            }

            var dpList = (List<object?>)inj.DParent;
            foreach (var item in Items(inj.DParent))
                SetProp(inj.Parent, item[0], Clone(childtm));
            Slice(inj.Parent, 0, dpList.Count, true);
            inj.KeyI = 0;

            return GetProp(inj.DParent, 0);
        }

        return NONE;
    };

    // Match at least one of the provided alternatives.
    private static readonly Injector _ValidateOne = (inj, val, refStr, store) =>
    {
        if (M_VAL != inj.Mode) return null;

        if (!IsList(inj.Parent) || 0 != inj.KeyI)
        {
            inj.Errs.Add("The $ONE validator at field " +
                Pathify(inj.Path, 1, 1) +
                " must be the first element of an array.");
            return null;
        }

        inj.KeyI = Size(inj.Keys);

        inj.SetVal(inj.DParent, 2);
        inj.Path = (List<object?>)Slice(inj.Path, -1)!;
        inj.Key  = StrKey(GetElem(inj.Path, -1)) ?? S_MT;

        var tvals = (List<object?>)Slice(inj.Parent, 1)!;
        if (0 == Size(tvals))
        {
            inj.Errs.Add("The $ONE validator at field " +
                Pathify(inj.Path, 1, 1) +
                " must have at least one argument.");
            return null;
        }

        foreach (object? tval in tvals)
        {
            var terrs  = new List<object?>();
            var vstore = (Dictionary<string, object?>)Merge(
                new List<object?> { new Dictionary<string, object?>(), store }, 1)!;
            vstore[S_DTOP] = inj.DParent;

            object? vcurrent = Validate(inj.DParent, tval, new InjectState
            {
                Extra = vstore,
                Errs  = terrs,
                Meta  = inj.Meta,
            });

            inj.SetVal(vcurrent, -2);

            if (0 == Size(terrs)) return null;
        }

        // No match found.
        string valdesc = R_TRANSFORM_NAME.Replace(
            Join(Items(tvals, n => (object?)Stringify(n[1])), ", "),
            m => m.Groups[1].Value.ToLower());

        inj.Errs.Add(_InvalidTypeMsg(
            inj.Path,
            (1 < Size(tvals) ? "one of " : "") + valdesc,
            Typify(inj.DParent), inj.DParent));

        return null;
    };

    // Match one of the provided exact values.
    private static readonly Injector _ValidateExact = (inj, val, refStr, store) =>
    {
        if (M_VAL == inj.Mode)
        {
            if (!IsList(inj.Parent) || 0 != inj.KeyI)
            {
                inj.Errs.Add("The $EXACT validator at field " +
                    Pathify(inj.Path, 1, 1) +
                    " must be the first element of an array.");
                return null;
            }

            inj.KeyI = Size(inj.Keys);

            inj.SetVal(inj.DParent, 2);
            inj.Path = (List<object?>)Slice(inj.Path, 0, -1)!;
            inj.Key  = StrKey(GetElem(inj.Path, -1)) ?? S_MT;

            var tvals = (List<object?>)Slice(inj.Parent, 1)!;
            if (0 == Size(tvals))
            {
                inj.Errs.Add("The $EXACT validator at field " +
                    Pathify(inj.Path, 1, 1) +
                    " must have at least one argument.");
                return null;
            }

            string? currentStr = null;
            foreach (object? tval in tvals)
            {
                bool exactMatch = Equals(tval, inj.DParent);
                if (!exactMatch && IsNode(tval))
                {
                    currentStr ??= Stringify(inj.DParent);
                    exactMatch = Stringify(tval) == currentStr;
                }
                if (exactMatch) return null;
            }

            string valdesc = R_TRANSFORM_NAME.Replace(
                Join(Items(tvals, n => (object?)Stringify(n[1])), ", "),
                m => m.Groups[1].Value.ToLower());

            inj.Errs.Add(_InvalidTypeMsg(
                inj.Path,
                (1 < Size(inj.Path) ? "" : "value ") +
                "exactly equal to " + (1 == Size(tvals) ? "" : "one of ") + valdesc,
                Typify(inj.DParent), inj.DParent));
        }
        else
        {
            DelProp(inj.Parent, inj.Key);
        }

        return null;
    };

    // True if key exists on node (JSON null counts as present); sets value when present.
    private static bool TryGetDataValue(object? node, object? key, out object? value)
    {
        value = null;
        if (node == null || key == null) return false;
        if (node is Dictionary<string, object?> map)
        {
            string k = StrKey(key) ?? S_MT;
            return map.TryGetValue(k, out value);
        }
        if (node is List<object?> list)
        {
            string? ks = key?.ToString();
            if (ks != null && int.TryParse(ks, out int i))
            {
                if (i < 0) i = list.Count + i;
                if (i >= 0 && i < list.Count)
                {
                    value = list[i];
                    return true;
                }
            }
            return false;
        }
        return false;
    }

    // Modify callback: runs after each inject step to perform type/structure validation.
    private static object? _Validation(
        object? pval, object? key, object? parent, object? injObj, object? store)
    {
        var inj = injObj as InjectState;
        if (inj == null) return null;

        bool isSkipVal = pval is Dictionary<string, object?> sd && sd.ContainsKey("`$SKIP`");
        if (isSkipVal) return null;

        bool exact = GetProp(inj.Meta, S_BEXACT) is bool b && b;

        bool cKeyExists = TryGetDataValue(inj.DParent, key, out object? cval);

        // TS: if (!exact && NONE === cval) return — only skip when key is absent, not when value is JSON null.
        if (!exact && !cKeyExists) return null;

        int ptype = Typify(pval);

        // Skip if spec value still contains a $ command name.
        if (0 < (T.Str & ptype) && pval is string ps && ps.Contains(S_DS)) return null;

        int ctype = Typify(cval);

        // TS: ptype !== ctype && NONE !== pval — deleted spec keys read as undefined; C# GetProp gives null.
        // Distinguish absent key (skip) vs JSON null present (Typify null) via TryGetDataValue on parent.
        bool specKeyPresent = TryGetDataValue(parent, key, out _);

        // Type mismatch.
        if (ptype != ctype && !ReferenceEquals(pval, NONE) && specKeyPresent)
        {
            inj.Errs.Add(_InvalidTypeMsg(inj.Path, TypeName(ptype), ctype, cval));
            return null;
        }

        if (IsMap(cval))
        {
            if (!IsMap(pval))
            {
                inj.Errs.Add(_InvalidTypeMsg(inj.Path, TypeName(ptype), ctype, cval));
                return null;
            }

            var ckeys = KeysOf(cval);
            var pkeys = KeysOf(pval);

            object? openFlag = GetProp(pval, "`$OPEN`");
            bool isOpen      = true == openFlag as bool?;

            // Empty spec map means open (accepts any keys).
            if (0 < Size(pkeys) && !isOpen)
            {
                var badkeys = new List<string>();
                foreach (string ck in ckeys)
                    if (!HasKey(pval, ck)) badkeys.Add(ck);

                if (0 < badkeys.Count)
                {
                    string msg = "Unexpected keys at field " + Pathify(inj.Path, 1) +
                        S_VIZ + Join(badkeys.Cast<object?>().ToList());
                    inj.Errs.Add(msg);
                    return null;
                }
            }
            else
            {
                Merge(new List<object?> { pval, cval });
                if (IsNode(pval)) DelProp(pval, "`$OPEN`");
            }
        }
        else if (IsList(cval))
        {
            if (!IsList(pval))
                inj.Errs.Add(_InvalidTypeMsg(inj.Path, TypeName(ptype), ctype, cval));
        }
        else if (exact)
        {
            // Missing key (TS undefined) must not match JSON null in the spec.
            object? cExact = cKeyExists ? cval : NONE;
            if (!Equals(cExact, pval))
            {
                string pathmsg = 1 < Size(inj.Path)
                    ? "at field " + Pathify(inj.Path, 1) + S_VIZ
                    : S_MT;
                inj.Errs.Add("Value " + pathmsg + Stringify(cExact) +
                    " should equal " + Stringify(pval) + S_DT);
            }
        }
        else
        {
            // Use data value as output.
            SetProp(parent, key, cval);
        }

        return null;
    }

    // Inject handler for validation: intercepts meta-path syntax.
    private static readonly Injector _ValidateHandler = (inj, val, refStr, store) =>
    {
        if (refStr == null) return _InjectHandler(inj, val, refStr, store);

        var m = R_META_PATH.Match(refStr);
        if (m.Success)
        {
            if (m.Groups[2].Value == "=")
                inj.SetVal(new List<object?> { (object?)S_BEXACT, val });
            else
                inj.SetVal(val);

            inj.KeyI = -1;
            return SKIP;
        }

        return _InjectHandler(inj, val, refStr, store);
    };

    // Validate a data structure against a shape specification.
    public static object? Validate(
        object? data,
        object? spec,
        InjectState? injdef = null)
    {
        bool collect = injdef?.Errs != null;
        var  errs    = injdef?.Errs ?? new List<object?>();

        // Extra validation commands override / supplement default store.
        var extraStore = new Dictionary<string, object?>();
        if (injdef?.Extra != null)
            foreach (var kv in Items(injdef.Extra))
                extraStore[kv[0]?.ToString() ?? ""] = kv[1];

        var store = (Dictionary<string, object?>)Merge(new List<object?>
        {
            new Dictionary<string, object?>
            {
                // Null out transform-only commands so they don't fire.
                ["$DELETE"] = null,
                ["$COPY"]   = null,
                ["$KEY"]    = null,
                ["$META"]   = null,
                ["$MERGE"]  = null,
                ["$EACH"]   = null,
                ["$PACK"]   = null,

                // Validation commands.
                ["$STRING"]   = (Injector)_ValidateString,
                ["$NUMBER"]   = (Injector)_ValidateType,
                ["$INTEGER"]  = (Injector)_ValidateType,
                ["$DECIMAL"]  = (Injector)_ValidateType,
                ["$BOOLEAN"]  = (Injector)_ValidateType,
                ["$NULL"]     = (Injector)_ValidateType,
                ["$NIL"]      = (Injector)_ValidateType,
                ["$MAP"]      = (Injector)_ValidateType,
                ["$LIST"]     = (Injector)_ValidateType,
                ["$FUNCTION"] = (Injector)_ValidateType,
                ["$INSTANCE"] = (Injector)_ValidateType,
                ["$ANY"]      = (Injector)_ValidateAny,
                ["$CHILD"]    = (Injector)_ValidateChild,
                ["$ONE"]      = (Injector)_ValidateOne,
                ["$EXACT"]    = (Injector)_ValidateExact,

                [S_DERRS] = errs,
            },
            // Match TS merge([..., getdef(extra, {}), ...]): empty extra is {}, not null —
            // null would be treated as a scalar and wipe the validation command map.
            IsEmpty(extraStore) ? new Dictionary<string, object?>() : extraStore,
            new Dictionary<string, object?> { [S_DERRS] = errs },
        }, 1)!;

        var meta = injdef?.Meta ?? new Dictionary<string, object?>();
        SetProp(meta, S_BEXACT, GetProp(meta, S_BEXACT) ?? false);

        // Pass errs explicitly so Transform collects (doesn't throw) internally.
        object? out_ = Transform(data, spec, new InjectState
        {
            Extra    = store,
            ModifyFn = _Validation,
            Handler  = _ValidateHandler,
            Meta     = meta,
            Errs     = errs,
        });

        if (errs.Count > 0 && !collect)
            throw new InvalidOperationException(
                string.Join(" | ", errs.Select(e => e?.ToString() ?? "")));

        return out_;
    }


    // ========================================================================
    // SELECT
    // ========================================================================

    private static double _SelectToDouble(object? v) =>
        v switch
        {
            int i   => i,
            long l  => l,
            double d => d,
            float f => f,
            _ => double.TryParse(v?.ToString(), System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out double x)
                ? x : double.NaN,
        };

    // $AND: all terms must match.
    private static readonly Injector _SelectAnd = (inj, val, refStr, store) =>
    {
        if (M_KEYPRE != inj.Mode) return null;

        var terms = GetProp(inj.Parent, inj.Key) as List<object?> ?? [];
        var ppath = (List<object?>)Slice(inj.Path, -1)!;
        object? point = GetPath(ppath, store);

        var vstore = (Dictionary<string, object?>)Merge(
            new List<object?> { new Dictionary<string, object?>(), store }, 1)!;
        vstore[S_DTOP] = point;

        foreach (object? term in terms)
        {
            var terrs = new List<object?>();
            Validate(point, term, new InjectState { Extra = vstore, Errs = terrs, Meta = inj.Meta });
            if (0 != Size(terrs))
                inj.Errs.Add("AND:" + Pathify(ppath) + S_VIZ + Stringify(point) +
                    " fail:" + Stringify(terms));
        }

        object? gkey = GetElem(inj.Path, -2);
        object? gp   = GetElem(inj.Nodes, -2);
        SetProp(gp, gkey, point);
        return null;
    };

    // $OR: at least one term must match.
    private static readonly Injector _SelectOr = (inj, val, refStr, store) =>
    {
        if (M_KEYPRE != inj.Mode) return null;

        var terms = GetProp(inj.Parent, inj.Key) as List<object?> ?? [];
        var ppath = (List<object?>)Slice(inj.Path, -1)!;
        object? point = GetPath(ppath, store);

        var vstore = (Dictionary<string, object?>)Merge(
            new List<object?> { new Dictionary<string, object?>(), store }, 1)!;
        vstore[S_DTOP] = point;

        foreach (object? term in terms)
        {
            var terrs = new List<object?>();
            Validate(point, term, new InjectState { Extra = vstore, Errs = terrs, Meta = inj.Meta });
            if (0 == Size(terrs))
            {
                object? gkey2 = GetElem(inj.Path, -2);
                object? gp2   = GetElem(inj.Nodes, -2);
                SetProp(gp2, gkey2, point);
                return null;
            }
        }

        inj.Errs.Add("OR:" + Pathify(ppath) + S_VIZ + Stringify(point) +
            " fail:" + Stringify(terms));
        return null;
    };

    // $NOT: term must NOT match.
    private static readonly Injector _SelectNot = (inj, val, refStr, store) =>
    {
        if (M_KEYPRE != inj.Mode) return null;

        object? term  = GetProp(inj.Parent, inj.Key);
        var ppath     = (List<object?>)Slice(inj.Path, -1)!;
        object? point = GetPath(ppath, store);

        var vstore = (Dictionary<string, object?>)Merge(
            new List<object?> { new Dictionary<string, object?>(), store }, 1)!;
        vstore[S_DTOP] = point;

        var terrs = new List<object?>();
        Validate(point, term, new InjectState { Extra = vstore, Errs = terrs, Meta = inj.Meta });

        if (0 == Size(terrs))
            inj.Errs.Add("NOT:" + Pathify(ppath) + S_VIZ + Stringify(point) +
                " fail:" + Stringify(term));

        object? gkey = GetElem(inj.Path, -2);
        object? gp   = GetElem(inj.Nodes, -2);
        SetProp(gp, gkey, point);
        return null;
    };

    // $GT, $LT, $GTE, $LTE, $LIKE: comparison operators.
    private static readonly Injector _SelectCmp = (inj, val, refStr, store) =>
    {
        if (M_KEYPRE != inj.Mode) return NONE;

        object? term  = GetProp(inj.Parent, inj.Key);
        object? gkey  = GetElem(inj.Path, -2);
        var ppath     = (List<object?>)Slice(inj.Path, -1)!;
        object? point = GetPath(ppath, store);

        bool pass = false;

        double pd = _SelectToDouble(point);
        double td = _SelectToDouble(term);
        if (!double.IsNaN(pd) && !double.IsNaN(td))
        {
            if (refStr == "$GT"  && pd > td)  pass = true;
            else if (refStr == "$LT"  && pd < td)  pass = true;
            else if (refStr == "$GTE" && pd >= td) pass = true;
            else if (refStr == "$LTE" && pd <= td) pass = true;
        }

        if (!pass && refStr == "$LIKE")
        {
            string pattern  = term?.ToString() ?? "";
            string subject2 = Stringify(point);
            try
            {
                if (Regex.IsMatch(subject2, pattern)) pass = true;
            }
            catch { /* invalid pattern */ }
        }

        if (pass)
        {
            object? gp = GetElem(inj.Nodes, -2);
            SetProp(gp, gkey, point);
        }
        else
        {
            inj.Errs.Add("CMP: " + Pathify(ppath) + S_VIZ + Stringify(point) +
                " fail:" + refStr + " " + Stringify(term));
        }

        return NONE;
    };

    // Select children from a collection that match a query.
    public static List<object?> Select(object? children, object? query)
    {
        if (!IsNode(children)) return [];

        List<object?> childList;
        if (IsMap(children))
        {
            childList = Items(children, n =>
            {
                SetProp(n[1], S_DKEY, n[0]);
                return (object?)n[1];
            });
        }
        else
        {
            childList = Items(children, n =>
            {
                object? idx = n[0];
                if (idx is string s && long.TryParse(s, out long li))
                    SetProp(n[1], S_DKEY, (object?)li);
                else
                    SetProp(n[1], S_DKEY, idx);
                return (object?)n[1];
            });
        }

        var results = new List<object?>();

        var selectExtra = new Dictionary<string, object?>
        {
            ["`$AND`"] = (Injector)_SelectAnd,
            ["`$OR`"]  = (Injector)_SelectOr,
            ["`$NOT`"] = (Injector)_SelectNot,
            ["$AND"]   = (Injector)_SelectAnd,
            ["$OR"]    = (Injector)_SelectOr,
            ["$NOT"]   = (Injector)_SelectNot,
            // JSON/test fixtures use backtick-wrapped keys (`$GT`, etc.); GetPath resolves bare $NAME.
            ["`$GT`"]   = (Injector)_SelectCmp,
            ["`$LT`"]   = (Injector)_SelectCmp,
            ["`$GTE`"]  = (Injector)_SelectCmp,
            ["`$LTE`"]  = (Injector)_SelectCmp,
            ["`$LIKE`"] = (Injector)_SelectCmp,
            ["$GT"]    = (Injector)_SelectCmp,
            ["$LT"]    = (Injector)_SelectCmp,
            ["$GTE"]   = (Injector)_SelectCmp,
            ["$LTE"]   = (Injector)_SelectCmp,
            ["$LIKE"]  = (Injector)_SelectCmp,
        };

        var meta = new Dictionary<string, object?> { [S_BEXACT] = true };
        var q    = Clone(query);

        Walk(q, (k, v, p, path) =>
        {
            if (IsMap(v))
            {
                object? existing = GetProp(v, "`$OPEN`");
                if (existing == null) SetProp(v, "`$OPEN`", true);
            }
            return v;
        });

        foreach (object? child in childList)
        {
            var errs = new List<object?>();
            Validate(child, Clone(q), new InjectState
            {
                Extra = selectExtra,
                Errs  = errs,
                Meta  = meta,
            });

            if (0 == Size(errs)) results.Add(child);
        }

        return results;
    }
}
