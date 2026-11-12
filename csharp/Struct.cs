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

using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Voxgig.Struct
{

    // Type bit-flags (matching TypeScript).
    public static class T
    {
        private static int _t = 31;
        public static readonly int Any = (1 << _t--) - 1;
        public static readonly int NoVal = 1 << _t--;
        public static readonly int Boolean = 1 << _t--;
        public static readonly int Decimal = 1 << _t--;
        public static readonly int Integer = 1 << _t--;
        public static readonly int Number = 1 << _t--;
        public static readonly int Str = 1 << _t--;
        public static readonly int Func = 1 << _t--;
        public static readonly int Symbol = 1 << _t--;
        public static readonly int Null = 1 << _t--;

        static T() { _t -= 7; }

        private static int _t2 = 31 - 10 - 7;
        public static readonly int List = 1 << (_t2--);
        public static readonly int Map = 1 << (_t2--);
        public static readonly int Instance = 1 << (_t2--);

        private static int _t3 = 31 - 10 - 7 - 3 - 4;
        public static readonly int Scalar = 1 << (_t3--);
        public static readonly int Node = 1 << (_t3--);
    }


    /// <summary>
    /// Callback invoked for each node visited by <see cref="StructUtils.Walk"/>.
    /// </summary>
    /// <remarks>
    /// The <paramref name="path"/> argument is a single mutable list per depth,
    /// shared across all callback invocations for the lifetime of the top-level
    /// Walk call. Callbacks that need to retain the path MUST clone it
    /// (e.g. <c>new List&lt;object?&gt;(path)</c> or <c>path.ToList()</c>);
    /// otherwise its contents will be overwritten by subsequent visits.
    /// </remarks>
    public delegate object? WalkApply(object? key, object? val, object? parent, List<object?> path);
    public delegate object? Modify(object? val, object? key, object? parent, object? inj, object? store);
    public delegate object? Injector(InjectState inj, object? val, string? refStr, object? store);


    public class InjectState
    {
        public int Mode { get; set; }  // M_KEYPRE | M_KEYPOST | M_VAL
        public bool Full { get; set; }
        public int KeyI { get; set; }
        public List<object?> Keys { get; set; } = [];
        public string? Key { get; set; }
        public object? Val { get; set; }
        public object? Parent { get; set; }
        public List<object?> Path { get; set; } = [];
        public List<object?> Nodes { get; set; } = [];
        public Injector? Handler { get; set; }
        public List<object?>? Errs { get; set; }
        public string? Base { get; set; }
        public Modify? ModifyFn { get; set; }
        public object? DParent { get; set; }
        public List<object?> DPath { get; set; } = [];
        public InjectState? Prior { get; set; }
        public Dictionary<string, object?> Meta { get; set; } = [];
        public object? Extra { get; set; }
        public object? Root { get; set; }

        public object? Descend()
        {
            if (!Meta.TryGetValue("__d", out object? value))
            {
                value = 0;
                Meta["__d"] = value;
            }

            Meta["__d"] = Convert.ToInt64(value, CultureInfo.InvariantCulture) + 1L;

            object? parentkey = StructUtils.GetElem(Path, -2);

            if (DParent == null)
            {
                if (StructUtils.Size(DPath) > 1)
                {
                    DPath = [.. DPath, parentkey];
                }
            }
            else
            {
                if (parentkey != null)
                {
                    DParent = StructUtils.GetProp(DParent, parentkey);
                    string pkStr = StructUtils.StrKey(parentkey);
                    object? lastpart = StructUtils.GetElem(DPath, -1);
                    string? lastStr = lastpart as string;
                    DPath = lastStr == "$:" + pkStr ? ([.. DPath.Take(DPath.Count - 1)]) : ([.. DPath, parentkey]);
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
                Mode = Mode,
                Full = false,
                KeyI = keyI,
                Keys = keys,
                Key = keyStr,
                Val = StructUtils.GetProp(parentNode, keyStr),
                Parent = parentNode,
                Path = [.. Path, keyStr],
                Nodes = [.. Nodes, parentNode],
                Handler = Handler,
                Errs = Errs,
                Meta = Meta,
                Base = Base,
                ModifyFn = ModifyFn,
                Prior = this,
                DPath = [.. DPath],
                DParent = DParent,
                Extra = Extra,
                Root = Root
            };
            return cinj;
        }

        public object? SetVal(object? val, int ancestor = 0)
        {
            // Match TS: setval(NONE) deletes the key; null also deletes.
            bool del = val == null || ReferenceEquals(val, StructUtils.NONE);
            if (ancestor < 2)
            {
                if (del)
                {
                    StructUtils.DelProp(Parent, Key);
                }
                else
                {
                    StructUtils.SetProp(Parent, Key, val);
                }

                return Parent;
            }
            object? anode = StructUtils.GetElem(Nodes, -ancestor);
            object? akey = StructUtils.GetElem(Path, -ancestor);
            if (del)
            {
                StructUtils.DelProp(anode, akey);
            }
            else
            {
                StructUtils.SetProp(anode, akey, val);
            }

            return anode;
        }
    }


    public static partial class StructUtils
    {
        // Inject mode flags.
        public const int M_KEYPRE = 1;
        public const int M_KEYPOST = 2;
        public const int M_VAL = 4;

        // Special strings.
        public const string S_BKEY = "`$KEY`";
        public const string S_BANNO = "`$ANNO`";
        public const string S_BEXACT = "`$EXACT`";
        public const string S_BVAL = "`$VAL`";
        public const string S_DKEY = "$KEY";
        public const string S_DTOP = "$TOP";
        public const string S_DERRS = "$ERRS";
        public const string S_DSPEC = "$SPEC";

        // General strings.
        public const string S_list = "list";
        public const string S_base = "base";
        public const string S_boolean = "boolean";
        public const string S_function = "function";
        public const string S_number = "number";
        public const string S_object = "object";
        public const string S_string = "string";
        public const string S_decimal = "decimal";
        public const string S_integer = "integer";
        public const string S_map = "map";
        public const string S_scalar = "scalar";
        public const string S_node = "node";
        public const string S_instance = "instance";
        public const string S_any = "any";
        public const string S_nil = "nil";
        public const string S_null = "null";
        public const string S_key = "key";

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

        // Cached JSON serializer options (avoid allocating per call - CA1869).
        private static readonly JsonSerializerOptions JSON_OPTS_COMPACT = new()
        {
            Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            WriteIndented = false,
        };
        private static readonly JsonSerializerOptions JSON_OPTS_INDENTED = new()
        {
            Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            WriteIndented = true,
        };

        // Private markers.
        public static readonly Dictionary<string, object?> SKIP = new() { ["`$SKIP`"] = true };
        public static readonly Dictionary<string, object?> DELETE = new() { ["`$DELETE`"] = true };

        // Sentinel for "value is not defined / absent" (analogous to TS undefined).
        // Use this to distinguish "value is null (JSON null)" from "value is not present".
        public static readonly object NONE = new();

        // Typename lookup (indexed by bit position from MSB of type code).
        private static readonly string[] TYPENAME =
        [
            S_any,
            S_nil,
            S_boolean,
            S_decimal,
            S_integer,
            S_number,
            S_string,
            S_function,
            S_nil,
            S_null,
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            S_list,
            S_map,
            S_instance,
            "",
            "",
            "",
            "",
            S_scalar,
            S_node
        ];

        // Regular expressions (compile-time generated; see partial methods at end of class).
        private static readonly Regex R_ESCAPE_REGEXP = R_EscapeRegexpGen();
        private static readonly Regex R_CLONE_REF = R_CloneRefGen();
        private static readonly Regex R_INJECTION_FULL = R_InjectionFullGen();
        private static readonly Regex R_INJECTION_PARTIAL = R_InjectionPartialGen();
        private static readonly Regex R_DOUBLE_DOLLAR = R_DoubleDollarGen();
        private static readonly Regex R_META_PATH = R_MetaPathGen();
        private static readonly Regex R_TRANSFORM_NAME = R_TransformNameGen();
        private static readonly Regex R_CHECKER_NAME = R_CheckerNameGen();
        private static readonly Regex R_DOT = R_DotGen();

        public const int MAXDEPTH = 32;


        // ========================================================================
        // Minor utilities
        // ========================================================================

        // Value is a node - a map (Dictionary) or list (List).
        public static bool IsNode(object? val)
        {
            return val is Dictionary<string, object?> or List<object?>;
        }

        // Value is a map (Dictionary with string keys).
        public static bool IsMap(object? val)
        {
            return val is Dictionary<string, object?>;
        }

        // Value is a list (List).
        public static bool IsList(object? val)
        {
            return val is List<object?>;
        }

        // Value is a valid key: non-empty string or any number (matches TS where numbers are keys).
        public static bool IsKey(object? key)
        {
            return key is string s ? s.Length > 0 : key is int or long or double or float;
        }

        // Value is "empty": null, empty string, empty list, or empty map.
        public static bool IsEmpty(object? val)
        {
            // Match TS isempty: undefined/null/empty-string/empty-array/empty-object → true.
            if (val == null || ReferenceEquals(val, NONE))
            {
                return true;
            }

            if (val is string s)
            {
                return s.Length == 0;
            }

            return val is List<object?> l ? l.Count == 0 : val is Dictionary<string, object?> d && d.Count == 0;
        }

        // Value is a delegate/function.
        public static bool IsFunc(object? val)
        {
            return val is Delegate;
        }

        // Get a defined value; return alt if val is null.
        public static object? GetDef(object? val, object? alt)
        {
            return val ?? alt;
        }

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
            return ReferenceEquals(value, NONE)
                ? T.NoVal
                : value == null
                ? T.Scalar | T.Null
                : value switch
                {
                    bool => T.Scalar | T.Boolean,
                    int => T.Scalar | T.Number | T.Integer,
                    long => T.Scalar | T.Number | T.Integer,
                    double d => double.IsNaN(d) ? T.NoVal : double.IsInteger(d)
                                    ? T.Scalar | T.Number | T.Integer
                                    : T.Scalar | T.Number | T.Decimal,
                    float f => float.IsNaN(f) ? T.NoVal : (f % 1 == 0)
                                    ? T.Scalar | T.Number | T.Integer
                                    : T.Scalar | T.Number | T.Decimal,
                    string => T.Scalar | T.Str,
                    Delegate => T.Scalar | T.Func,
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
                List<string> ls => ls.Count,
                List<object?> l => l.Count,
                Dictionary<string, object?> d => d.Count,
                string s => s.Length,
                int i => i,
                long lg => (int)lg,
                double d => (int)Math.Floor(d),
                float f => (int)Math.Floor(f),
                bool b => b ? 1 : 0,
                _ => 0,
            };
        }

        // Extract a sub-range from a list or string (negative indices count from end).
        // For numbers: clamp between start (inclusive) and end (exclusive).
        public static object? Slice(object? val, int? start = null, int? end = null, bool mutate = false)
        {
            if (val is int or long or double or float)
            {
                long lv = Convert.ToInt64(val, CultureInfo.InvariantCulture);
                long lo = start ?? long.MinValue;
                long hi = end.HasValue ? (long)end.Value - 1 : long.MaxValue;
                return Math.Min(Math.Max(lv, lo), hi);
            }

            int vlen = Size(val);

            if (end != null && start == null)
            {
                start = 0;
            }

            if (start == null)
            {
                return val;
            }

            int s = start.Value;
            int e;

            if (s < 0)
            {
                e = vlen + s;
                if (e < 0)
                {
                    e = 0;
                }

                s = 0;
            }
            else if (end != null)
            {
                e = end.Value;
                if (e < 0)
                {
                    e = vlen + e;
                    if (e < 0)
                    {
                        e = 0;
                    }
                }
                else if (vlen < e)
                {
                    e = vlen;
                }
            }
            else
            {
                e = vlen;
            }

            if (s > vlen)
            {
                s = vlen;
            }

            if (s < 0 || s > e || e > vlen)
            {
                return val is List<object?> ? new List<object?>() : val is string ? S_MT : val;
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
            return val is string str ? str[s..e] : val;
        }

        // String padding.
        public static string Pad(object? str, int padding = 44, string? padchar = null)
        {
            string s = str is string ss ? ss : Stringify(str);
            string pc = padchar != null ? (padchar + S_SP)[0].ToString() : S_SP;
            return padding >= 0 ? s.PadRight(padding, pc[0]) : s.PadLeft(-padding, pc[0]);
        }

        // A list key this far from zero is past any list: a write appends or prepends, a read misses.
        private const long LISTKEY_HUGE = 1_000_000_000_000_000_000;

        // ^(0|-?[1-9][0-9]*)$, the form String(n) gives an integer n, as that integer. So "01",
        // "+1", " 1", "1.0" and "-0" are not list keys.
        private static bool CanonListIndex(string key, out long index)
        {
            index = 0;
            int j = key.StartsWith('-') ? 1 : 0;
            if (j == key.Length || ('0' == key[j] && 1 < key.Length))
            {
                return false;
            }

            long i = 0;
            for (; j < key.Length; j++)
            {
                if (key[j] is < '0' or > '9')
                {
                    return false;
                }

                i = i < LISTKEY_HUGE / 10 ? (i * 10) + (key[j] - '0') : LISTKEY_HUGE;
            }

            index = key.StartsWith('-') ? -i : i;
            return true;
        }

        // The canonical _listkey: an integral number, or a string CanonListIndex accepts.
        private static bool ListKey(object? key, out long index)
        {
            if (key is string s)
            {
                return CanonListIndex(s, out index);
            }

            double d = ListKeyNumber(key);
            if (!double.IsFinite(d) || d != Math.Floor(d))
            {
                index = 0;
                return false;
            }

            index = Math.Abs(d) < LISTKEY_HUGE ? (long)d : d < 0 ? -LISTKEY_HUGE : LISTKEY_HUGE;
            return true;
        }

        // The element a list read selects, else -1. Only GetElem counts a negative key from the end.
        private static long ListIndex(object? key)
        {
            return ListKey(key, out long i) && 0 <= i ? i : -1;
        }

        // A map reads a string or number key; any other key names no member.
        private static bool MapReadKey(object? key)
        {
            return key is string or int or long or double or float;
        }

        // A numeric key's value; NaN for any other key.
        private static double ListKeyNumber(object? key)
        {
            return key is IConvertible c && c.GetTypeCode() is >= TypeCode.SByte and <= TypeCode.Decimal
                ? c.ToDouble(CultureInfo.InvariantCulture)
                : double.NaN;
        }

        // Get a list element by integer index (negative counts from end).
        public static object? GetElem(object? val, object? key, object? alt = null)
        {
            if (val == null || key == null)
            {
                return alt;
            }

            object? out2 = alt;
            if (val is List<object?> list && ListKey(key, out long nkey))
            {
                if (nkey < 0)
                {
                    nkey += list.Count;
                }

                if (nkey >= 0 && nkey < list.Count)
                {
                    out2 = list[(int)nkey];
                }
            }

            // null at a slot counts as "no value" — same Group A rule as getprop.
            if (out2 == null)
            {
                return alt is Delegate d2 ? d2.DynamicInvoke() : alt;
            }

            return out2;
        }

        // Safely get a property of a node.
        public static object? GetProp(object? val, object? key, object? alt = null)
        {
            if (val == null || key == null)
            {
                return alt;
            }

            object? out2 = alt;
            if (val is Dictionary<string, object?> map)
            {
                string k = StrKey(key) ?? S_MT;
                if (MapReadKey(key) && map.TryGetValue(k, out object? v))
                {
                    out2 = v;
                }
            }
            else if (val is List<object?> list)
            {
                long i = ListIndex(key);
                if (i >= 0 && i < list.Count)
                {
                    out2 = list[(int)i];
                }
            }

            // JSON null at a key is treated as "no value" for the default-substitution
            // rule (Group A). This unifies cross-port behaviour.
            if (out2 == null)
            {
                return alt;
            }

            return out2;
        }

        // Internal: literal value lookup that preserves stored JSON null. Group B
        // callers (validate / transform commands / builders / inject internals) use
        // this when they need to inspect the raw stored value at a slot regardless
        // of whether it is null. The public GetProp / GetElem / HasKey APIs treat
        // null as absent (Group A) per UNDEF_SPEC.md. Returns NONE when truly absent.
        public static object? Lookup(object? val, object? key)
        {
            if (val == null || key == null || ReferenceEquals(val, NONE))
            {
                return NONE;
            }

            if (val is Dictionary<string, object?> map)
            {
                string k = StrKey(key) ?? S_MT;
                return MapReadKey(key) && map.TryGetValue(k, out object? v) ? v : NONE;
            }
            if (val is List<object?> list)
            {
                long i = ListIndex(key);
                return i >= 0 && i < list.Count ? list[(int)i] : NONE;
            }
            return NONE;
        }

        // Convert a key to its string representation.
        public static string? StrKey(object? key = null)
        {
            if (key == null)
            {
                return S_MT;
            }

            int t = Typify(key);
            if (0 < (T.Str & t))
            {
                return (string)key;
            }

            if (0 < (T.Boolean & t))
            {
                return S_MT;
            }

            if (0 < (T.Number & t))
            {
                double d = Convert.ToDouble(key, CultureInfo.InvariantCulture);
                return ((long)Math.Floor(d)).ToString(CultureInfo.InvariantCulture);
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
            return val is List<object?> list
                ? Enumerable.Range(0, list.Count)
                                 .Select(i => i.ToString(CultureInfo.InvariantCulture))
                                 .ToList()
                : (List<string>)([]);
        }

        // True if the key exists with a non-null value in val.
        // Canonical: haskey is `null != getprop(val, key)`, so a present-but-null
        // key is false (Group A null unification).
        public static bool HasKey(object? val, object? key)
        {
            return GetProp(val, key) != null;
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
            if (!IsList(list))
            {
                return list;
            }

            if (depth <= 0)
            {
                return list;
            }

            var result = new List<object?>();
            foreach (var item in list)
            {
                if (item is List<object?> inner)
                {
                    result.AddRange(depth > 1 ? Flatten(inner, depth - 1) : inner);
                }
                else
                {
                    result.Add(item);
                }
            }
            return result;
        }

        // Filter items using a predicate on [key, value] pairs.
        public static List<object?> Filter(object? val, Func<List<object?>, bool> check)
        {
            var all = Items(val);
            var result = new List<object?>();
            foreach (var item in all)
            {
                if (check(item))
                {
                    result.Add(item[1]);
                }
            }

            return result;
        }

        // Escape for use in a regular expression.
        public static string EscRe(string? s)
        {
            return s == null ? S_MT : R_ESCAPE_REGEXP.Replace(s, m => @"\" + m.Value);
        }

        // ---------------------------------------------------------------
        // Regex utility — uniform Re* API (see /REGEX_API.md).
        // .NET's System.Text.RegularExpressions is a strict superset of RE2.
        // ---------------------------------------------------------------

        public static Regex ReCompile(string pattern)
        {
            return new(pattern);
        }

        public static bool ReTest(string pattern, string input)
        {
            return new Regex(pattern).IsMatch(input ?? "");
        }

        public static string[]? ReFind(string pattern, string input)
        {
            var m = new Regex(pattern).Match(input ?? "");
            if (!m.Success)
            {
                return null;
            }

            var groups = m.Groups;
            var out_ = new string[groups.Count];
            for (int i = 0; i < groups.Count; i++)
            {
                out_[i] = groups[i].Success ? groups[i].Value : "";
            }

            return out_;
        }

        public static List<string[]> ReFindAll(string pattern, string input)
        {
            var rx = new Regex(pattern);
            var outs = new List<string[]>();
            foreach (Match m in rx.Matches(input ?? "").Cast<Match>())
            {
                var row = new string[m.Groups.Count];
                for (int i = 0; i < m.Groups.Count; i++)
                {
                    row[i] = m.Groups[i].Success ? m.Groups[i].Value : "";
                }

                outs.Add(row);
            }
            return outs;
        }

        public static string ReReplace(string pattern, string input, string replacement)
        {
            // Translate JS-style $& to $0
            var dotnetRepl = replacement.Replace("$&", "$0");
            return new Regex(pattern).Replace(input ?? "", dotnetRepl);
        }

        public static string ReEscape(string s)
        {
            return EscRe(s);
        }

        // URL-encode a string, keeping what encodeURIComponent keeps.
        public static string EscUrl(string? s)
        {
            return s == null ? S_MT : Uri.EscapeDataString(s)
                .Replace("%21", "!").Replace("%2A", "*").Replace("%27", "'")
                .Replace("%28", "(").Replace("%29", ")");
        }

        // Replace in a string (all occurrences).
        private static string ReplaceStr(string? s, Regex from, string to)
        {
            return s == null ? S_MT : from.Replace(s, to);
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
                int i = int.Parse((string)n[0]!, CultureInfo.InvariantCulture);
                string s = (string)n[1]!;

                if (sepre is not null and not S_MT)
                {
                    if (url && i == 0)
                    {
                        return Regex.Replace(s, sepre + @"+$", S_MT);
                    }

                    if (i > 0)
                    {
                        s = Regex.Replace(s, @"^" + sepre + @"+", S_MT);
                    }

                    if (i < sarr - 1 || !url)
                    {
                        s = Regex.Replace(s, sepre + @"+$", S_MT);
                    }

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
        public static string JoinUrl(params string[] parts)
        {
            return Join(parts.Cast<object?>().ToList(), S_FS, url: true);
        }

        // JSON.stringify-style output (indent = spaces per level, like TS jsonify flags.indent).
        public static string Jsonify(object? val, int indent = 2, int offset = 0)
        {
            if (val == null)
            {
                return S_null;
            }

            try
            {
                var opts = indent > 0 ? JSON_OPTS_INDENTED : JSON_OPTS_COMPACT;
                string str = JsonSerializer.Serialize(SortKeys(val), opts);
                // System.Text.Json on .NET 8 emits Environment.NewLine for indented
                // output, which is "\r\n" on Windows. The TS-canonical corpus expects
                // "\n", so normalise here. (.NET 9 adds JsonWriterOptions.NewLine.)
                if (indent > 0)
                {
                    str = str.Replace("\r\n", "\n");
                }
                // System.Text.Json always uses 2 spaces per level; rescale to match TS JSON.stringify(,,indent).
                if (indent is > 0 and not 2)
                {
                    const int netPerLevel = 2;
                    var lines = str.Split('\n');
                    var rescaled = new List<string>(lines.Length);
                    foreach (string line in lines)
                    {
                        int lead = 0;
                        while (lead < line.Length && line[lead] == ' ')
                        {
                            lead++;
                        }

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
            // Match TS: NONE (undefined) -> "" but JSON null -> "null".
            if (ReferenceEquals(val, NONE))
            {
                return S_MT;
            }

            if (val is string s)
            {
                valstr = s;
            }
            else
            {
                try
                {
                    valstr = JsonSerializer.Serialize(SortKeys(val), JSON_OPTS_COMPACT);
                    valstr = valstr.Replace("\"", S_MT);
                }
                catch
                {
                    return "__STRINGIFY_FAILED__";
                }
            }

            if (maxlen is not null and >= 0)
            {
                if (valstr.Length > maxlen)
                {
                    valstr = valstr[..Math.Max(0, maxlen.Value - 3)] + "...";
                }
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
                {
                    sorted[k] = SortKeys(map[k]);
                }

                return sorted;
            }
            return val is List<object?> list ? list.Select(SortKeys).ToList() : val;
        }

        // Build a human-friendly path string.
        // Pass StructUtils.NONE (not null) to indicate "path was not provided at all".
        public static string Pathify(object? val, int startIn = 0, int endIn = 0)
        {
            // Distinguish "truly absent" (NONE) from "explicitly null" (null).
            bool isNone = ReferenceEquals(val, NONE);
            if (isNone)
            {
                val = null;
            }

            List<object?>? path = null;

            if (val is List<object?> lv)
            {
                path = lv;
            }
            else if (val is string sv)
            {
                path = [sv];
            }
            else if (val is int or long or double or float)
            {
                path = [val];
            }

            int start = startIn >= 0 ? startIn : 0;
            int end = endIn >= 0 ? endIn : 0;

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
                if (sub.Count == 0)
                {
                    return "<root>";
                }

                var parts = Filter(sub, n => IsKey(n[1]))
                            .Select(p =>
                            {
                                if (p is int pi)
                                {
                                    return ((long)pi).ToString(CultureInfo.InvariantCulture);
                                }

                                if (p is long pl)
                                {
                                    return pl.ToString(CultureInfo.InvariantCulture);
                                }

                                return p is double pd
                                    ? ((long)Math.Floor(pd)).ToString(CultureInfo.InvariantCulture)
                                    : p is float pf
                                        ? ((long)Math.Floor(pf)).ToString(CultureInfo.InvariantCulture)
                                        : R_DOT.Replace((string)p!, S_MT);
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
            if (val == null)
            {
                return null;
            }

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
                    {
                        return refs[idx];
                    }
                }
                return v;
            }

            return DeepClone(val, Replacer, Reviver);
        }

        private static object? DeepClone(object? val, Func<object?, object?> replacer, Func<object?, object?> reviver)
        {
            if (val == null)
            {
                return null;
            }

            var replaced = replacer(val);
            if (replaced is string refStr && R_CLONE_REF.IsMatch(refStr))
            {
                return reviver(refStr);
            }

            if (val is Dictionary<string, object?> map)
            {
                var result = new Dictionary<string, object?>();
                foreach (var kv in map)
                {
                    result[kv.Key] = DeepClone(kv.Value, replacer, reviver);
                }

                return result;
            }
            return val is List<object?> list ? list.Select(item => DeepClone(item, replacer, reviver)).ToList() : val;
        }

        // Define a JSON object (dictionary) from alternating key/value arguments.
        // Jm("a", 1, "b", 2) => { "a": 1, "b": 2 }. A missing trailing value is null.
        public static Dictionary<string, object?> Jm(params object?[] kv)
        {
            var o = new Dictionary<string, object?>();
            for (int i = 0; i < kv.Length; i += 2)
            {
                var k = kv[i];
                var ks = k is string s ? s : Stringify(k);
                o[ks] = i + 1 < kv.Length ? kv[i + 1] : null;
            }

            return o;
        }

        // Define a JSON array (list) from positional arguments.
        // Jt(1, "x", true) => [1, "x", true].
        public static List<object?> Jt(params object?[] v)
        {
            var a = new List<object?>(v.Length);
            a.AddRange(v);
            return a;
        }

        // Safely set a property. Returns the (possibly modified) parent.
        public static object? SetProp(object? parent, object? key, object? val)
        {
            if (!IsKey(key))
            {
                return parent;
            }

            if (IsCondensed(parent))
            {
                throw new InvalidOperationException(S_IMMUTABLE);
            }

            if (parent is Dictionary<string, object?> map)
            {
                string k = StrKey(key) ?? S_MT;
                map[k] = val;
            }
            else if (parent is List<object?> list)
            {
                if (!ListKey(key, out long keyI))
                {
                    return parent;
                }

                if (keyI >= 0)
                {
                    int clamped = Convert.ToInt32(Slice(keyI, 0, list.Count + 1), CultureInfo.InvariantCulture);
                    while (list.Count <= clamped)
                    {
                        list.Add(null);
                    }

                    list[clamped] = val;
                }
                else
                {
                    list.Insert(0, val);
                }
            }

            return parent;
        }

        // Safely delete a property. Returns the (possibly modified) parent.
        public static object? DelProp(object? parent, object? key)
        {
            if (!IsKey(key))
            {
                return parent;
            }

            if (IsCondensed(parent))
            {
                throw new InvalidOperationException(S_IMMUTABLE);
            }

            if (parent is Dictionary<string, object?> map)
            {
                string k = StrKey(key) ?? S_MT;
                map.Remove(k);
            }
            else if (parent is List<object?> list && ListKey(key, out long keyI) && keyI >= 0 && keyI < list.Count)
            {
                list.RemoveAt((int)keyI);
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
            if (IsCondensed(store))
            {
                throw new InvalidOperationException(S_IMMUTABLE);
            }

            if (store == null)
            {
                return null;
            }

            int pathType = Typify(path);
            List<object?> parts;

            if (0 < (T.List & pathType) && path is List<object?> lp)
            {
                parts = lp;
            }
            else if (0 < (T.Str & pathType) && path is string ps)
            {
                parts = ps.Split('.').Cast<object?>().ToList();
            }
            else if (0 < (T.Number & pathType))
            {
                parts = [path];
            }
            else
            {
                return null;
            }

            if (parts.Count == 0)
            {
                return null;
            }

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
            {
                DelProp(parent, lastKey);
            }
            else
            {
                SetProp(parent, lastKey, val);
            }

            return parent;
        }


        // ========================================================================
        // GetPath
        // ========================================================================

        // Get the value at a dot-separated key path deep inside a store.
        // path: string ("a.b.c"), List<object?>, or number.
        // state: optional InjectState providing base, dparent, dpath, meta,
        //        key, and a post-processing handler.
        public static object? GetPath(object? store, object? path,
                                       object? current = null, InjectState? state = null)
        {
            // Resolve path to a mutable list of string parts.
            List<string> parts;
            if (path is List<object?> lp)
            {
                // A number part reads as its string form; any other part makes the whole path miss.
                parts = new List<string>(lp.Count);
                foreach (object? part in lp)
                {
                    if (part is string ps)
                    {
                        parts.Add(ps);
                    }
                    else if (part is int or long or double or float)
                    {
                        parts.Add(CondenseStr(part));
                    }
                    else
                    {
                        return null;
                    }
                }
            }
            else if (path is List<string> ls)
            {
                parts = new List<string>(ls);
            }
            else if (path is string sp)
            {
                parts = sp == S_MT ? [S_MT] : [.. sp.Split('.')];
            }
            else if (0 < (T.Number & Typify(path)))
            {
                parts = [CondenseStr(path)];
            }
            else
            {
                return null;
            }

            // A base changes what the path resolves against, so honour it on the expansion.
            if (IsCondensed(store))
            {
                if (state?.Base == null)
                {
                    object? found = CondenseRebuild(store, CondenseResolve(store, CondenseRoot(store), path));
                    // Group A, as a plain getpath reads it: a stored null is absent.
                    return ReferenceEquals(found, NONE) ? null : found;
                }

                store = Expand(store);
            }

            string? baseKey = state?.Base;
            object? src = GetProp(store, baseKey, store) ?? store;
            object? dparent = state?.DParent;
            int numparts = parts.Count;

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
                {
                    val = GetProp(store, parts[0]);
                }

                if (!IsFunc(val))
                {
                    val = src;

                    // Meta path syntax: "q0$~x" or "q0$=x" — navigate into meta.
                    var m = R_META_PATH.Match(parts[0]);
                    if (m.Success && state?.Meta != null)
                    {
                        val = GetProp(state.Meta, m.Groups[1].Value);
                        parts[0] = m.Groups[3].Value;
                    }

                    List<object?> dpath = state?.DPath ?? [];

                    for (int pI = 0; val != null && pI < numparts; pI++)
                    {
                        string part = parts[pI];

                        // Special path keywords and dynamic substitution.
                        if (state != null && part == S_DKEY)
                        {
                            part = state.Key ?? S_MT;
                        }
                        else if (state != null && part.StartsWith("$GET:", StringComparison.Ordinal))
                        {
                            string sub = part[5..^1];
                            part = Stringify(GetPath(src, sub));
                        }
                        else if (state != null && part.StartsWith("$REF:", StringComparison.Ordinal))
                        {
                            string sub = part[5..^1];
                            object? specVal = GetProp(store, S_DSPEC);
                            part = specVal != null ? Stringify(GetPath(specVal, sub)) : S_MT;
                        }
                        else if (state != null && part.StartsWith("$META:", StringComparison.Ordinal))
                        {
                            string sub = part[6..^1];
                            part = Stringify(GetPath(state.Meta, sub));
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
                                if (pI == numparts - 1)
                                {
                                    ascends--;
                                }

                                if (ascends == 0)
                                {
                                    val = dparent;
                                }
                                else
                                {
                                    int dpathLen = dpath.Count;
                                    int cutLen = Math.Max(0, dpathLen - ascends);
                                    var fullpath = new List<string>();
                                    for (int i = 0; i < cutLen; i++)
                                    {
                                        fullpath.Add(StrKey(dpath[i]) ?? S_MT);
                                    }

                                    if (pI + 1 < numparts)
                                    {
                                        fullpath.AddRange(parts.Skip(pI + 1));
                                    }

                                    val = ascends <= dpathLen
                                        ? GetPath(store, fullpath.Cast<object?>().ToList())
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
        //
        // The `path` argument passed to the before/after callbacks is a single
        // mutable list per depth, shared across all callback invocations for the
        // lifetime of this top-level Walk call. Callbacks that need to store the
        // path MUST clone it (e.g. new List<object?>(path)); the contents will
        // otherwise be overwritten by subsequent visits.
        public static object? Walk(
            object? val,
            WalkApply? before = null,
            WalkApply? after = null,
            int? maxdepth = null,
            object? key = null,
            object? parent = null,
            List<object?>? path = null,
            List<List<object?>>? pool = null)
        {
            pool ??= [[]];
            path ??= pool[0];

            int depth = path.Count;

            object? out_ = before == null ? val : before(key, val, parent, path);

            int md = (maxdepth.HasValue && maxdepth.Value >= 0) ? maxdepth.Value : MAXDEPTH;
            if (md == 0 || depth >= md)
            {
                return out_;
            }

            if (IsNode(out_))
            {
                int childDepth = depth + 1;

                // Grow pool on demand so pool[childDepth] exists.
                while (pool.Count <= childDepth)
                {
                    pool.Add(new List<object?>(pool.Count));
                }

                List<object?> childPath = pool[childDepth];

                // Ensure childPath has exactly childDepth slots (mutated in place below).
                if (childPath.Count < childDepth)
                {
                    while (childPath.Count < childDepth)
                    {
                        childPath.Add(null);
                    }
                }
                else if (childPath.Count > childDepth)
                {
                    childPath.RemoveRange(childDepth, childPath.Count - childDepth);
                }

                // Sync prefix [0..depth-1] from the current path. Only needed once per
                // parent: siblings share the same prefix and will each overwrite slot
                // [depth] below.
                for (int i = 0; i < depth; i++)
                {
                    childPath[i] = path[i];
                }

                foreach (var item in Items(out_))
                {
                    string ckey = StrKey(item[0]) ?? S_MT;
                    object? child = item[1];
                    childPath[depth] = ckey;
                    SetProp(out_, ckey, Walk(child, before, after, maxdepth, ckey, out_, childPath, pool));
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
            if (!IsList(val))
            {
                return val;
            }

            int md = maxdepth.HasValue ? (maxdepth.Value < 0 ? 0 : maxdepth.Value) : MAXDEPTH;

            var list = (List<object?>)val!;
            int lenlist = list.Count;

            if (lenlist == 0)
            {
                return null;
            }

            if (lenlist == 1)
            {
                return list[0];
            }

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

                    object? mergeBefore(object? key, object? mval, object? _parent, List<object?> path)
                    {
                        int pI = path.Count;

                        if (md <= pI)
                        {
                            // Beyond max depth: copy directly.
                            if (key != null)
                            {
                                SetProp(cur[pI - 1], key, mval);
                            }
                        }
                        else if (!IsNode(mval))
                        {
                            cur[pI] = mval;
                        }
                        else
                        {
                            // Navigate destination parallel to current override path.
                            if (pI > 0 && key != null)
                            {
                                dst[pI] = GetProp(dst[pI - 1], key);
                            }

                            object? tval = dst[pI];

                            if (Typify(mval) == Typify(tval))
                            {
                                // Same type → merge into existing destination node.
                                cur[pI] = tval;
                            }
                            else if (0 == (T.Instance & Typify(mval)))
                            {
                                // Otherwise the override wins: a plain node is copied, taking
                                // nothing from the destination, so no later merge writes into it.
                                cur[pI] = IsList(mval)
                                    ? (object?)new List<object?>()
                                    : new Dictionary<string, object?>();
                                dst[pI] = null;
                            }
                            else
                            {
                                // A class instance is kept as is, so there is nothing to descend.
                                cur[pI] = mval;
                                mval = null;
                            }
                        }

                        return mval;
                    }

                    object? mergeAfter(object? key, object? _, object? parent, List<object?> path)
                    {
                        int cI = path.Count;
                        if (key == null || cI <= 0)
                        {
                            return cur[0];
                        }

                        cur[cI - 1] = SetProp(cur[cI - 1], key, cur[cI]) ?? cur[cI - 1];

                        // Walk writes this back into the override, so it is the
                        // override's own child, leaving the override unchanged.
                        return Lookup(parent, key);
                    }

                    Walk(obj, mergeBefore, mergeAfter, md);
                    out_ = cur[0];
                }
            }

            // md=0: return empty shell of last element's type.
            if (md == 0)
            {
                out_ = GetElem(list, -1);
                if (IsList(out_))
                {
                    out_ = new List<object?>();
                }
                else if (IsMap(out_))
                {
                    out_ = new Dictionary<string, object?>();
                }
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
            bool iscmd = IsFunc(val) && (refStr == null || refStr.StartsWith(S_DS, StringComparison.Ordinal));
            if (iscmd && val is Injector injFn)
            {
                out_ = injFn(inj, val, refStr, store);
            }
            else if (inj.Mode == M_VAL && inj.Full)
            {
                inj.SetVal(val);
            }

            return out_;
        };


        // Inject store values into a string. Not a public utility – used by Inject.
        // Backtick-delimited references (e.g. "`a.b`") are resolved via GetPath.
        // A string that is entirely one reference returns the raw resolved value.
        // A string with embedded references has each one stringified in-place.
        private static object? _InjectStr(string val, object? store, object? current, InjectState? state)
        {
            if (val == S_MT)
            {
                return S_MT;
            }

            var m = R_INJECTION_FULL.Match(val);

            if (m.Success)
            {
                if (state != null)
                {
                    state.Full = true;
                }

                string pathref = m.Groups[1].Value;
                // Unescape $BT → ` and $DS → $
                if (pathref.Length > 3)
                {
                    pathref = pathref.Replace("$BT", S_BT).Replace("$DS", S_DS);
                }

                return GetPath(store, pathref, current, state);
            }

            // Replace every embedded `ref` with its stringified resolved value.
            object? outStr = R_INJECTION_PARTIAL.Replace(val, match =>
            {
                string ref_ = match.Groups[1].Value;
                if (ref_.Length > 3)
                {
                    ref_ = ref_.Replace("$BT", S_BT).Replace("$DS", S_DS);
                }

                if (state != null)
                {
                    state.Full = false;
                }

                object? found = GetPath(store, ref_, current, state);
                if (found == null)
                {
                    // Distinguish an explicit null value (key exists) from a
                    // missing key. Only top-level single-segment paths are checked.
                    bool keyExists = !ref_.Contains('.')
                        && store is Dictionary<string, object?> sm
                        && sm.ContainsKey(ref_);
                    return keyExists ? S_null : S_MT;
                }
                if (found is string fs)
                {
                    return fs;
                }
                // Non-string, non-null → serialize as compact JSON.
                try
                {
                    return JsonSerializer.Serialize(found, JSON_OPTS_COMPACT);
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
                    Mode = M_VAL,
                    Full = false,
                    KeyI = 0,
                    Keys = [(object?)S_DTOP],
                    Key = S_DTOP,
                    Val = val,
                    Parent = parent,
                    Path = [(object?)S_DTOP],
                    Nodes = [(object?)parent],
                    Handler = _InjectHandler,
                    Base = S_DTOP,
                    Errs = (GetProp(store, S_DERRS) as List<object?>) ?? [],
                    Meta = new Dictionary<string, object?> { ["__d"] = 0L },
                    DParent = store,
                    DPath = [(object?)S_DTOP],
                };

                // Allow a partial injdef to override defaults.
                if (state != null)
                {
                    if (state.ModifyFn != null)
                    {
                        newState.ModifyFn = state.ModifyFn;
                    }

                    if (state.Extra != null)
                    {
                        newState.Extra = state.Extra;
                    }

                    if (state.Meta != null)
                    {
                        newState.Meta = state.Meta;
                    }

                    if (state.Handler != null)
                    {
                        newState.Handler = state.Handler;
                    }
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
                    var normal = allKeys.Where(k => !k.Contains(S_DS)).ToList();
                    var transform = allKeys.Where(k => k.Contains(S_DS)).ToList();
                    keys = [.. normal.Cast<object?>(), .. transform.Cast<object?>()];
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
                    nkI = childinj.KeyI;
                    keys = childinj.Keys;
                    val = childinj.Parent;

                    // TS: if (NONE !== prekey) — skip NONE/undefined (e.g. $CHILD KEYPRE). Also skip null prekey.
                    if (preKey != null && !ReferenceEquals(preKey, NONE))
                    {
                        object? childval = GetProp(val, preKey);
                        childinj.Val = childval;
                        childinj.Mode = M_VAL;

                        Inject(childval, store, childinj);

                        nkI = childinj.KeyI;
                        keys = childinj.Keys;
                        val = childinj.Parent;

                        childinj.Mode = M_KEYPOST;
                        _InjectStr(nodekey, store, state.DParent, childinj);

                        nkI = childinj.KeyI;
                        keys = childinj.Keys;
                        val = childinj.Parent;
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
                {
                    state.SetVal(injected);
                }

                val = injected;
            }

            // ── Custom modify callback ───────────────────────────────────────────
            if (state.ModifyFn != null)
            {
                bool isSkip = val is Dictionary<string, object?> sd2 && sd2.ContainsKey("`$SKIP`");
                if (!isSkip)
                {
                    object? mparent = state.Parent;
                    object? mval = GetProp(mparent, state.Key);
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
            static string PlacementName(int mode)
            {
                return mode == M_VAL ? "value" : S_key;
            }

            if (0 == (modes & state.Mode))
            {
                var expected = new List<string>();
                foreach (int m in new[] { M_KEYPRE, M_KEYPOST, M_VAL })
                {
                    if (0 != (modes & m))
                    {
                        expected.Add(PlacementName(m));
                    }
                }

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
            int numargs = argTypes.Count;
            var found = new List<object?> { null };   // found[0] = null means OK

            for (int ai = 0; ai < numargs; ai++)
            {
                object? arg = GetElem(argslist, ai);
                int argType = Typify(arg);
                if (0 == (argTypes[ai] & argType))
                {
                    found[0] = $"invalid argument: {Stringify(arg, 22)} " +
                               $"({TypeName(argType)} at position {1 + ai}) " +
                               $"is not of type: {TypeName(argTypes[ai])}.";
                    while (found.Count <= numargs)
                    {
                        found.Add(null);
                    }

                    return found;
                }
                found.Add(arg);
            }
            while (found.Count <= numargs)
            {
                found.Add(null);
            }

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
            if (!CheckPlacement(M_VAL, "COPY", T.Any, inj))
            {
                return null;
            }

            object? out_ = GetProp(inj.DParent, inj.Key);
            inj.SetVal(out_);
            return out_;
        };

        // Return the key of the current node from $KEY meta or $ANNO or path.
        private static readonly Injector _TransformKey = (inj, val, refStr, store) =>
        {
            if (inj.Mode != M_VAL)
            {
                return null;
            }

            object? keyspec = GetProp(inj.Parent, S_BKEY);
            if (keyspec != null)
            {
                DelProp(inj.Parent, S_BKEY);
                return GetProp(inj.DParent, keyspec);
            }

            object? anno = GetProp(inj.Parent, S_BANNO);
            object? pkey = GetProp(anno, S_KEY);
            return pkey ?? GetElem(inj.Path, -2);
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
            if (inj.Mode == M_KEYPRE)
            {
                return inj.Key;
            }

            if (inj.Mode == M_KEYPOST)
            {
                object? args = GetProp(inj.Parent, inj.Key);
                if (args is string sa && sa == S_MT)
                {
                    args = new List<object?> { GetProp(store, S_DTOP) };
                }
                else if (!IsList(args))
                {
                    args = new List<object?> { args };
                }

                inj.SetVal(null);   // remove the $MERGE key from parent

                if (args is not List<object?> list)
                {
                    return inj.Key;
                }

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
            if (!CheckPlacement(M_VAL, "EACH", T.List, inj))
            {
                return null;
            }

            // Truncate keys to just the first element.
            if (inj.Keys.Count > 1)
            {
                inj.Keys.RemoveRange(1, inj.Keys.Count - 1);
            }

            // Get args: ['`$EACH`', 'source-path', child-template]
            var parentList = inj.Parent as List<object?> ?? [];
            var sliced = parentList.Count > 1 ? parentList.GetRange(1, parentList.Count - 1) : [];
            var args = InjectorArgs([T.Str, T.Any], sliced);
            if (args[0] != null)
            {
                inj.Errs.Add("$EACH: " + args[0]);
                return null;
            }

            string srcpath = (string)args[1]!;
            object? child = args[2];

            // Source data.
            object? srcstore = GetProp(store, inj.Base, store);
            object? src = GetPath(srcstore, srcpath, null, inj);
            int srctype = Typify(src);

            object? tval = null;

            if (0 < (T.List & srctype))
            {
                var sl = (List<object?>)src!;
                tval = sl.Select(_ => Clone(child)).ToList();
            }
            else if (0 < (T.Map & srctype))
            {
                tval = Items(src).Select(item => Merge(
                    new List<object?> {
                        Clone(child),
                        new Dictionary<string, object?> { [S_BANNO] = new Dictionary<string, object?> { [S_KEY] = item[0] } }
                    }, 1)).ToList();
            }

            var rval = new List<object?>();

            if (tval != null && Size(tval) > 0)
            {
                var tvalList = (List<object?>)tval;

                // Source values for DParent navigation.
                List<object?> srcVals = IsMap(src) ? Items(src).Select(item => item[1]).ToList() : src as List<object?> ?? [];
                string ckey = StrKey(GetElem(inj.Path, -2)) ?? S_DTOP;
                string tkey = ckey;
                object? target = GetElem(inj.Nodes, -2) ?? GetElem(inj.Nodes, -1);

                // tpath = path[:-1] (all but last element, same as Go)
                var tpath = inj.Path.Count > 0
                    ? inj.Path.GetRange(0, inj.Path.Count - 1).Cast<object?>().ToList()
                    : [];

                // dpath: [$TOP, ...srcpath.split('.'), $:ckey, ...]
                var dpath = new List<object?> { (object?)S_DTOP };
                foreach (var p in srcpath.Split('.'))
                {
                    dpath.Add(p);
                }

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
                var tinj = inj.Child(0, [(object?)ckey]);
                tinj.Path = tpath;
                tinj.Nodes = inj.Nodes.Count > 0
                    ? [inj.Nodes[^1]]
                    : [];
                tinj.Parent = tinj.Nodes.Count > 0 ? tinj.Nodes[^1] : null;

                SetProp(tinj.Parent, ckey, tvalList);
                tinj.Val = tvalList;
                tinj.DPath = dpath;
                tinj.DParent = tcur;

                Inject(tvalList, store, tinj);

                rval = tinj.Val as List<object?> ?? rval;
            }

            // Set result on the parent target.
            string ftkey = StrKey(GetElem(inj.Path, -2)) ?? S_DTOP;
            object? ftarget = GetElem(inj.Nodes, -2) ?? GetElem(inj.Nodes, -1);
            SetProp(ftarget, ftkey, rval);

            return rval.Count > 0 ? rval[0] : null;
        };

        // Convert a node to a map by packing source items.
        private static readonly Injector _TransformPack = (inj, val, refStr, store) =>
        {
            if (!CheckPlacement(M_KEYPRE, "PACK", T.Map, inj))
            {
                return null;
            }

            // Get args: [srcpath, childspec]
            object? argsRaw = GetProp(inj.Parent, inj.Key);
            var argsList = argsRaw as List<object?> ?? [];
            var args = InjectorArgs([T.Str, T.Any], argsList);
            if (args[0] != null)
            {
                inj.Errs.Add("$PACK: " + args[0]);
                return null;
            }

            string srcpath = (string)args[1]!;
            object? origchildspec = args[2];

            // Target key and node.
            string tkey = StrKey(GetElem(inj.Path, -2)) ?? S_DTOP;
            int psz = inj.Path.Count;
            object? target = psz >= 2 ? inj.Nodes[psz - 2] : (psz >= 1 ? inj.Nodes[psz - 1] : null);

            // Source data.
            object? srcstore = GetProp(store, inj.Base, store);
            object? src = GetPath(srcstore, srcpath, null, inj);

            // Normalise src to a flat list.
            if (!IsList(src))
            {
                if (IsMap(src))
                {
                    src = Items(src).Select(item =>
                    {
                        var node = item[1];
                        if (IsMap(node))
                        {
                            SetProp(node, S_BANNO, new Dictionary<string, object?> { [S_KEY] = item[0] });
                        }

                        return node;
                    }).ToList();
                }
                else
                {
                    return null;
                }
            }

            if (src == null)
            {
                return null;
            }

            // Extract keypath and child template.
            object? keypath = GetProp(origchildspec, S_BKEY);
            object? childspec = DelProp(Clone(origchildspec), S_BKEY) ?? origchildspec;
            object? child = GetProp(childspec, S_BVAL, childspec);

            var srclist = (List<object?>)src;

            // Resolve output key for a source item.
            string ResolveKey(object? srcItem, int idx)
            {
                if (keypath == null)
                {
                    return idx.ToString(CultureInfo.InvariantCulture);
                }

                if (keypath is not string kpStr)
                {
                    return "";
                }

                if (kpStr.StartsWith('`'))
                {
                    // inject keypath with srcItem as $TOP
                    var ks = new Dictionary<string, object?>(store is Dictionary<string, object?> sd ? sd : []) { [S_DTOP] = srcItem };
                    var kr = Inject(kpStr, ks);
                    return kr?.ToString() ?? "";
                }
                else
                {
                    var kval = GetPath(srcItem, kpStr, null, inj);
                    return kval?.ToString() ?? "";
                }
            }

            // Build tval (output map with injected children).
            var tval = new Dictionary<string, object?>();

            for (int i = 0; i < srclist.Count; i++)
            {
                object? srcItem = srclist[i];
                string outKey = ResolveKey(srcItem, i);
                if (outKey == "")
                {
                    continue;
                }

                object? tchild = Clone(child);

                // Forward $ANNO from src (for map sources annotated above).
                object? anno = GetProp(srcItem, S_BANNO);
                if (anno != null && IsMap(tchild))
                {
                    SetProp(tchild, S_BANNO, anno);
                }
                else if (anno == null && IsMap(tchild))
                {
                    DelProp(tchild, S_BANNO);
                }

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
                    if (ok != "")
                    {
                        tsrc[ok] = srclist[i];
                    }
                }

                string ckey = tkey;
                var tpath = inj.Path.Count > 0
                    ? inj.Path.GetRange(0, inj.Path.Count - 1).Cast<object?>().ToList()
                    : [];

                var dpath = new List<object?> { (object?)S_DTOP };
                foreach (var p in srcpath.Split('.'))
                {
                    dpath.Add(p);
                }

                dpath.Add("$:" + ckey);

                object? tcur = (object?)new Dictionary<string, object?> { [ckey] = (object?)tsrc };

                if (tpath.Count > 1)
                {
                    string pkey = StrKey(GetElem(inj.Path, -3)) ?? S_DTOP;
                    tcur = new Dictionary<string, object?> { [pkey] = tcur };
                    dpath.Add("$:" + pkey);
                }

                var tinj = inj.Child(0, [(object?)ckey]);
                tinj.Path = tpath;
                tinj.Nodes = [inj.Nodes.Count > 0 ? inj.Nodes[^1] : null];
                tinj.Parent = tinj.Nodes[0];
                tinj.Val = tval;
                tinj.DPath = dpath;
                tinj.DParent = tcur;

                Inject(tval, store, tinj);

                if (tinj.Val is Dictionary<string, object?> rv)
                {
                    rval = rv;
                }
            }

            SetProp(target, tkey, rval);
            return null;
        };

        // Reference a value from the original spec.
        private static readonly Injector _TransformRef = (inj, val, refStr, store) =>
        {
            if (inj.Mode != M_VAL)
            {
                return null;
            }

            // Get refpath from parent list element 1.
            object? refpath = GetProp(inj.Parent, 1);
            inj.KeyI = inj.Keys.Count;   // skip remaining keys

            // Get the original spec via $SPEC function.
            object? specFn = GetProp(store, S_DSPEC);
            if (specFn == null)
            {
                return null;
            }

            object? spec = specFn is Injector si ? si(inj, null, null, store) : null;
            if (spec == null)
            {
                return null;
            }

            // Build dpath from current path (skip first element "$TOP").
            var dpath = inj.Path.Count > 1
                ? inj.Path.GetRange(1, inj.Path.Count - 1).Select(p => (object?)(StrKey(p) ?? S_MT)).ToList()
                : [];
            var dpathInj = new InjectState
            {
                DPath = dpath,
                DParent = GetPath(spec, dpath.Cast<object?>().ToList())
            };

            object? refResult = GetPath(spec, refpath, null, dpathInj);

            // Check if refResult contains sub-references.
            bool hasSubRef = false;
            if (IsNode(refResult))
            {
                Walk(refResult, (k, v, parent2, path2) =>
                {
                    if (v is string sv && sv == "`$REF`")
                    {
                        hasSubRef = true;
                    }

                    return v;
                });
            }

            // A recursive reference stops where the data does.
            int pathLen = inj.Path.Count;
            var tpath = pathLen >= 1
                ? inj.Path.GetRange(0, pathLen - 1).Cast<object?>().ToList()
                : [];
            object? tvalRef = GetPath(store, tpath, null, null);
            object? rval = !hasSubRef || tvalRef != null ? Clone(refResult) : NONE;

            // The enclosing loop injects the referenced spec in this list's place, so
            // neither this pass nor this element leaves a value for modify to check.
            object? grandparent = inj.SetVal(rval, 2);

            InjectState? prior = inj.Prior;
            if (prior != null)
            {
                prior.ModifyFn = null;
                if (IsList(grandparent) || (rval != null && !ReferenceEquals(rval, NONE)))
                {
                    prior.KeyI--;
                }
            }

            return SKIP;
        };

        // Apply a named format function to a child value.
        private static readonly Injector _TransformFormat = (inj, val, refStr, store) =>
        {
            // Truncate remaining keys.
            if (inj.Keys.Count > 1)
            {
                inj.Keys.RemoveRange(1, inj.Keys.Count - 1);
            }

            if (inj.Mode != M_VAL)
            {
                return null;
            }

            object? name = GetProp(inj.Parent, 1);
            object? child = GetProp(inj.Parent, 2);

            // Resolve child through injection using the proper DParent context.
            var rcInj = _InjectChild(child, store, inj);
            object? resolved = rcInj.Val;

            // Target key and node.
            string tkey = StrKey(GetElem(inj.Path, -2)) ?? S_DTOP;
            int psz = inj.Path.Count;
            object? target = psz >= 2 ? GetElem(inj.Nodes, -2) : GetElem(inj.Nodes, -1);

            // Helper: scalar to string.
            static string FmtStr(object? v)
            {
                return v switch
                {
                    null => "null",
                    bool b => b ? "true" : "false",
                    _ => v.ToString() ?? "null",
                };
            }

            // Determine formatter.
            WalkApply? formatter = null;

            if (name is string nameStr)
            {
                formatter = nameStr switch
                {
                    "upper" => (k, v, p, path) => IsNode(v) ? v : (object?)FmtStr(v).ToUpperInvariant(),
                    "lower" => (k, v, p, path) => IsNode(v) ? v : (object?)FmtStr(v).ToLowerInvariant(),
                    "string" => (k, v, p, path) => IsNode(v) ? v : (object?)FmtStr(v),
                    "number" => (k, v, p, path) =>
                    {
                        if (IsNode(v))
                        {
                            return v;
                        }

                        if (v is long li)
                        {
                            return (object?)li;
                        }

                        return v is double di ? (object?)di : v is string sv ? double.TryParse(sv, out double d) ? (object?)d : 0 : (object?)0;
                    }
                    ,
                    "integer" => (k, v, p, path) =>
                    {
                        if (IsNode(v))
                        {
                            return v;
                        }

                        if (v is long li)
                        {
                            return (object?)li;
                        }

                        return v is double di
                            ? (object?)(long)di
                            : v is string sv ? double.TryParse(sv, out double d) ? (object?)(long)d : (object?)0L : (object?)0L;
                    }
                    ,
                    "concat" => (k, v, p, path) =>
                    {
                        if (k == null && IsList(v))
                        {
                            var parts2 = (v as List<object?>)!.Select(x => IsNode(x) ? "" : FmtStr(x));
                            return (object?)string.Join("", parts2);
                        }
                        return v;
                    }
                    ,
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
            object? out_ = !IsNode(resolved)
                ? formatter(null, resolved, null, [])
                : name is string ns && ns == "concat" ? formatter(null, resolved, null, []) : Walk(resolved, before: formatter);
            SetProp(target, tkey, out_);
            return out_;
        };

        // Apply a function to a child value.
        private static readonly Injector _TransformApply = (inj, val, refStr, store) =>
        {
            if (inj.Keys.Count > 1)
            {
                inj.Keys.RemoveRange(1, inj.Keys.Count - 1);
            }

            if (!CheckPlacement(M_VAL, "APPLY", T.List, inj))
            {
                return null;
            }

            var parentList = inj.Parent as List<object?> ?? [];
            var sliced = parentList.Count > 1 ? parentList.GetRange(1, parentList.Count - 1) : [];
            var args = InjectorArgs([T.Func, T.Any], sliced);

            string tkey = StrKey(GetElem(inj.Path, -2)) ?? S_DTOP;
            object? target = GetElem(inj.Nodes, -2) ?? GetElem(inj.Nodes, -1);

            if (args[0] != null)
            {
                inj.Errs.Add("$APPLY: " + args[0]);
                SetProp(target, tkey, null);
                return null;
            }

            object? applyFn = args[1];
            object? child2 = args[2];

            // Resolve child.
            object? resolved = child2;
            if (child2 is string cs)
            {
                resolved = _InjectStr(cs, store, inj.DParent, inj);
            }

            // Invoke.
            object? out_ = null;
            if (applyFn is Func<object?, object?> fn1)
            {
                out_ = fn1(resolved);
            }
            else if (applyFn is Func<object?, object?, object?, object?> fn3)
            {
                out_ = fn3(resolved, store, inj);
            }
            else if (applyFn is Injector aInj)
            {
                out_ = aInj(inj, resolved, null, store);
            }

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
            var extraData = new Dictionary<string, object?>();

            object? extra = injdef?.Extra;
            if (extra != null)
            {
                foreach (var kv in Items(extra))
                {
                    string k = kv[0]?.ToString() ?? "";
                    if (k.StartsWith(S_DS, StringComparison.Ordinal))
                    {
                        extraTransforms[k] = kv[1];
                    }
                    else
                    {
                        extraData[k] = kv[1];
                    }
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
                [S_DTOP] = dataClone,
                [S_DSPEC] = (Injector)((inj2, v, r, s) => Clone(origspec)),
                ["$BT"] = (Injector)((inj2, v, r, s) => (object?)S_BT),
                ["$DS"] = (Injector)((inj2, v, r, s) => (object?)S_DS),
                ["$WHEN"] = (Injector)((inj2, v, r, s) => (object?)DateTime.UtcNow.ToString("o")),
                ["$DELETE"] = _TransformDelete,
                ["$COPY"] = _TransformCopy,
                ["$KEY"] = _TransformKey,
                ["$ANNO"] = _TransformAnno,
                ["$META"] = _TransformMeta,
                ["$MERGE"] = _TransformMerge,
                ["$MERGE0"] = _TransformMerge,
                ["$MERGE1"] = _TransformMerge,
                ["$EACH"] = _TransformEach,
                ["$PACK"] = _TransformPack,
                ["$REF"] = _TransformRef,
                ["$FORMAT"] = _TransformFormat,
                ["$APPLY"] = _TransformApply,
            };

            // Merge extra transforms into the store.
            foreach (var kv in extraTransforms)
            {
                store[kv.Key] = kv.Value;
            }

            // Error collection: collect=true when caller explicitly provided an errs list.
            bool collect = injdef?.Errs != null;
            List<object?> errs = injdef?.Errs ?? [];
            store[S_DERRS] = errs;

            // Build an inject state with any overrides from injdef.
            var injState = new InjectState
            {
                ModifyFn = injdef?.ModifyFn,
                Extra = injdef?.Extra,
                Meta = injdef?.Meta ?? [],
                Handler = injdef?.Handler,
            };

            object? out_ = Inject(spec, store, injState);

            return errs.Count > 0 && !collect
                ? throw new InvalidOperationException(string.Join(" | ", errs.Select(e => e?.ToString() ?? "")))
                : out_;
        }


        // ========================================================================
        // VALIDATE
        // ========================================================================

        // Build a "Expected X, but found Y: v." error message.
        private static string _InvalidTypeMsg(object? path, string needtype, int vt, object? v)
        {
            // TS: null == v → "no value"; NONE is undefined in TS and uses the same wording.
            bool absent = v == null || ReferenceEquals(v, NONE);
            string vs = absent ? "no value" : Stringify(v);
            string loc = Size(path) > 1 ? "field " + Pathify(path, 1) + " to be " : "";
            string found = !absent ? TypeName(vt) + S_VIZ : "";
            return "Expected " + loc + needtype + ", but found " + found + vs + S_DT;
        }

        // Require a non-empty string.
        private static readonly Injector _ValidateString = (inj, val, refStr, store) =>
        {
            bool keyExists = TryGetDataValue(inj.DParent, inj.Key, out object? out_);
            int t = keyExists ? Typify(out_) : T.NoVal;

            if (0 == (T.Str & t))
            {
                inj.Errs.Add(_InvalidTypeMsg(inj.Path, S_string, t, keyExists ? out_ : NONE));
                return NONE;
            }

            if (S_MT == (out_ as string))
            {
                inj.Errs.Add("Empty string at " + Pathify(inj.Path, 1));
                return NONE;
            }

            return out_;
        };

        // Require a value of the named type ($NUMBER, $INTEGER, etc.).
        private static readonly Injector _ValidateType = (inj, val, refStr, store) =>
        {
            string tname = refStr != null && refStr.Length > 1 ? refStr[1..].ToLowerInvariant() : "";
            int idx = Array.IndexOf(TYPENAME, tname);

            // $NIL is absent or null.
            int typev = (idx >= 0 ? (1 << (31 - idx)) : 0) | (S_nil == tname ? T.Null : 0);

            bool keyExists = TryGetDataValue(inj.DParent, inj.Key, out object? out_);
            int t = keyExists ? Typify(out_) : T.NoVal;

            if (0 == (t & typev))
            {
                inj.Errs.Add(_InvalidTypeMsg(inj.Path, tname, t, keyExists ? out_ : NONE));
                return NONE;
            }

            return keyExists && null == out_ ? _KeepNull(inj) : out_;
        };

        // Allow any value without type check.
        private static readonly Injector _ValidateAny = (inj, val, refStr, store) =>
            TryGetDataValue(inj.DParent, inj.Key, out object? out_) && null == out_ ? _KeepNull(inj) : out_;

        // Keep an accepted null in place: SetVal deletes on null, which in a list
        // shifts the elements after it. Validation has nothing to check for a null.
        private static Dictionary<string, object?> _KeepNull(InjectState inj)
        {
            SetProp(inj.Parent, inj.Key, null);
            return SKIP;
        }

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
                {
                    tval = new Dictionary<string, object?>();
                }
                else if (!IsMap(tval))
                {
                    // _Validation reports the mismatch, once.
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
                    inj.KeyI = Size(inj.Parent);
                    return inj.DParent;
                }

                // Clone children and reset inj key index.
                // The inject child loop will now iterate over the cloned children,
                // validating them against the current list values.
                var dpList = (List<object?>)inj.DParent;
                foreach (var item in Items(inj.DParent))
                {
                    SetProp(inj.Parent, item[0], Clone(childtm));
                }

                Slice(inj.Parent, 0, dpList.Count, true);

                // NOTE: modifying inj! This extends the child value loop in inject
                // to cover every cloned child.
                for (int ckeyI = Size(inj.Keys); ckeyI < Size(inj.Parent); ckeyI++)
                {
                    inj.Keys.Add(StrKey(ckeyI));
                }

                // Restart the child value loop at the first element (the loop
                // increments keyI on resume) so that the first element is also
                // validated against the child template.
                inj.KeyI = -1;

                // SKIP leaves the cloned child template in place at the first
                // element so the resumed loop can validate it.
                return SKIP;
            }

            return NONE;
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

                object? cval = _SlotVal(inj);

                inj.KeyI = Size(inj.Keys);

                // Replace [$EXACT, ...] with the data value; SKIP keeps inject off the detached list.
                _SetSlot(inj, cval);

                inj.Path = (List<object?>)Slice(inj.Path, 0, -1)!;

                var tvals = (List<object?>)Slice(inj.Parent, 1)!;
                if (0 == Size(tvals))
                {
                    inj.Errs.Add("The $EXACT validator at field " +
                        Pathify(inj.Path, 1, 1) +
                        " must have at least one argument.");
                    return SKIP;
                }

                foreach (object? tval in tvals)
                {
                    if (_DeepEqual(tval, cval))
                    {
                        return SKIP;
                    }
                }

                string valdesc = R_TRANSFORM_NAME.Replace(
                    Join(Items(tvals, n => (object?)Stringify(n[1])), ", "),
                    m => m.Groups[1].Value.ToLowerInvariant());

                inj.Errs.Add(_InvalidTypeMsg(
                    inj.Path,
                    (1 < Size(inj.Path) ? "" : "value ") +
                    "exactly equal to " + (1 == Size(tvals) ? "" : "one of ") + valdesc,
                    Typify(cval), cval));

                return SKIP;
            }

            DelProp(inj.Parent, inj.Key);
            return null;
        };

        // Count the specs that admit the value: ['`$NOF`', count, spec, ...], where
        // count is an integer, or a map holding min, max or both.
        private static readonly Injector _ValidateNof = (inj, val, refStr, store) =>
            _ValidateCount(inj, store, "$NOF", true);

        // Every spec admits the value: ['`$ALL`', spec, ...].
        private static readonly Injector _ValidateAll = (inj, val, refStr, store) =>
            _ValidateCount(inj, store, "$ALL", false);

        // The counting list directives. Without a count, every spec has to admit.
        private static object? _ValidateCount(InjectState inj, object? store, string name, bool counted)
        {
            if (M_VAL != inj.Mode)
            {
                return NONE;
            }

            if (!IsList(inj.Parent) || 0 != inj.KeyI)
            {
                inj.Errs.Add("The " + name + " validator at field " +
                    Pathify(inj.Path, 1, 1) +
                    " must be the first element of an array.");
                return NONE;
            }

            object? cval = _SlotVal(inj);

            inj.KeyI = Size(inj.Keys);

            // Replace the directive's list with the data value. Each return is SKIP, so
            // that inject leaves the detached list alone and validates nothing in it.
            _SetSlot(inj, cval);

            inj.Path = (List<object?>)Slice(inj.Path, -1)!;

            object? count = counted ? Lookup(inj.Parent, 1) : NONE;
            var tvals = (List<object?>)Slice(inj.Parent, counted ? 2 : 1)!;
            int numtvals = Size(tvals);
            string field = "The " + name + " validator at field " + Pathify(inj.Path, 1);

            if (0 == numtvals)
            {
                inj.Errs.Add(field + (counted ? " must have a count and" : " must have") +
                    " at least one argument.");
                return SKIP;
            }

            var (lo, hi, countdesc) = counted
                ? _NofCount(count, numtvals)
                : (numtvals, numtvals, "all");

            if (null == countdesc)
            {
                inj.Errs.Add(field + " has an invalid count: " + Stringify(count) + ".");
                return SKIP;
            }

            int admitted = 0;
            for (int tI = 0; tI < numtvals; tI++)
            {
                int left = numtvals - tI;

                // Stop once the specs left cannot change the verdict.
                if (hi < admitted || admitted + left < lo || (lo <= admitted && admitted + left <= hi))
                {
                    break;
                }

                if (_Admits(cval, tvals[tI], inj, store))
                {
                    admitted++;
                }
            }

            if (admitted < lo || hi < admitted)
            {
                string valdesc = R_TRANSFORM_NAME.Replace(
                    Join(Items(tvals, n => (object?)Stringify(n[1])), ", "),
                    m => m.Groups[1].Value.ToLowerInvariant());

                inj.Errs.Add(_InvalidTypeMsg(inj.Path, countdesc + " of " + valdesc, Typify(cval), cval));
            }

            return SKIP;
        }

        // The value's length is within a bound: ['`$LEN`', bound, spec?], where the
        // bound is as for a $NOF count. A string's length is in code points.
        private static readonly Injector _ValidateLen = (inj, val, refStr, store) =>
            _ValidateBound(inj, store, "$LEN");

        // The value is a number within a bound: ['`$RANGE`', bound, spec?], where the
        // bound holds min or gt, max or lt, or one of each.
        private static readonly Injector _ValidateRange = (inj, val, refStr, store) =>
            _ValidateBound(inj, store, "$RANGE");

        // The bounding list directives: a bound, then at most one spec that must also admit.
        private static object? _ValidateBound(InjectState inj, object? store, string name)
        {
            if (M_VAL != inj.Mode)
            {
                return NONE;
            }

            if (!IsList(inj.Parent) || 0 != inj.KeyI)
            {
                inj.Errs.Add("The " + name + " validator at field " +
                    Pathify(inj.Path, 1, 1) +
                    " must be the first element of an array.");
                return NONE;
            }

            object? cval = _SlotVal(inj);

            inj.KeyI = Size(inj.Keys);

            // As for the counting directives: SKIP keeps inject off the detached list.
            _SetSlot(inj, cval);

            inj.Path = (List<object?>)Slice(inj.Path, -1)!;

            string field = "The " + name + " validator at field " + Pathify(inj.Path, 1);
            int nargs = Size(inj.Parent) - 1;

            if (nargs is < 1 or > 2)
            {
                inj.Errs.Add(field + " must have a bound and at most one spec.");
                return SKIP;
            }

            object? bound = Lookup(inj.Parent, 1);
            bool islen = "$LEN" == name;
            var (lo, hi, desc) = islen ? _LenBound(bound) : (0d, 0d, _RangeDesc(bound));

            if (null == desc)
            {
                inj.Errs.Add(field + " has an invalid bound: " + Stringify(bound) + ".");
                return SKIP;
            }

            int ctype = Typify(cval);

            if (2 == nargs && !_Admits(cval, Lookup(inj.Parent, 2), inj, store))
            {
                string specdesc = R_TRANSFORM_NAME.Replace(
                    Stringify(Lookup(inj.Parent, 2)),
                    m => m.Groups[1].Value.ToLowerInvariant());

                inj.Errs.Add(_InvalidTypeMsg(inj.Path, specdesc, ctype, cval));
                return SKIP;
            }

            if (0 == ((islen ? T.Str | T.List | T.Map : T.Number) & ctype))
            {
                string needtype = islen ? "string, list or map" : S_number;
                inj.Errs.Add(_InvalidTypeMsg(inj.Path, needtype, ctype, cval));
                return SKIP;
            }

            int len = !islen ? 0 : cval is string s ? s.EnumerateRunes().Count() : Size(cval);
            bool inbound = islen ? lo <= len && (-1 == hi || len <= hi) : _InRange(bound, cval);

            if (!inbound)
            {
                string needtype = (1 < Size(inj.Path) ? "" : "value ") + desc;
                inj.Errs.Add(_InvalidTypeMsg(inj.Path, needtype, ctype, cval));
            }

            return SKIP;
        }

        // The bounds of a $LEN bound, with -1 for no maximum, and the words for it,
        // which are null when the bound is invalid.
        private static (double lo, double hi, string? desc) _LenBound(object? bound)
        {
            var (lo, hi, countdesc) = _NofCount(bound, -1);

            if (null == countdesc)
            {
                return (0, 0, null);
            }

            string desc = "of length " +
                (lo == hi
                    ? Stringify(lo)
                    : -1 == hi
                        ? "at least " + Stringify(lo)
                        : 0 == lo
                            ? "at most " + Stringify(hi)
                            : Stringify(lo) + " to " + Stringify(hi));

            return (lo, hi, desc);
        }

        // The words for a $RANGE bound, which are null when the bound is invalid.
        private static string? _RangeDesc(object? bound)
        {
            if (!IsMap(bound))
            {
                return null;
            }

            object? min = Lookup(bound, "min");
            object? max = Lookup(bound, "max");
            object? gt = Lookup(bound, "gt");
            object? lt = Lookup(bound, "lt");
            object? lower = Has(min) ? min : gt;
            object? upper = Has(max) ? max : lt;

            static bool Has(object? n)
            {
                return !ReferenceEquals(n, NONE);
            }

            static bool IsNum(object? n)
            {
                return !Has(n) || (n is int or long or double or float && 0 < (T.Number & Typify(n)));
            }

            bool valid =
                0 < Size(bound) &&
                Size(bound) == new[] { min, max, gt, lt }.Count(Has) &&
                (!Has(min) || !Has(gt)) &&
                (!Has(max) || !Has(lt)) &&
                IsNum(min) &&
                IsNum(max) &&
                IsNum(gt) &&
                IsNum(lt) &&
                (!Has(lower) || !Has(upper) || _BoundNum(lower) <= _BoundNum(upper));

            if (!valid)
            {
                return null;
            }

            return Join(
                [
                    Has(min) ? "at least " + Stringify(min) : Has(gt) ? "greater than " + Stringify(gt) : NONE,
                    Has(max) ? "at most " + Stringify(max) : Has(lt) ? "less than " + Stringify(lt) : NONE,
                ],
                " and ");
        }

        // A number within a valid $RANGE bound.
        private static bool _InRange(object? bound, object? val)
        {
            object? min = Lookup(bound, "min");
            object? max = Lookup(bound, "max");
            object? gt = Lookup(bound, "gt");
            object? lt = Lookup(bound, "lt");
            double v = _BoundNum(val);

            return (ReferenceEquals(min, NONE) || _BoundNum(min) <= v) &&
                (ReferenceEquals(max, NONE) || v <= _BoundNum(max)) &&
                (ReferenceEquals(gt, NONE) || _BoundNum(gt) < v) &&
                (ReferenceEquals(lt, NONE) || v < _BoundNum(lt));
        }

        // Typify flags a type it does not know as any, number included: NaN puts it out of range.
        private static double _BoundNum(object? n)
        {
            return n is int or long or double or float
                ? Convert.ToDouble(n, CultureInfo.InvariantCulture)
                : double.NaN;
        }

        // True if key exists on node (JSON null counts as present); sets value when present.
        private static bool TryGetDataValue(object? node, object? key, out object? value)
        {
            value = null;
            if (node == null || key == null)
            {
                return false;
            }

            if (node is Dictionary<string, object?> map)
            {
                string k = StrKey(key) ?? S_MT;
                return map.TryGetValue(k, out value);
            }
            if (node is List<object?> list)
            {
                long i = ListIndex(key);
                if (i >= 0 && i < list.Count)
                {
                    value = list[(int)i];
                    return true;
                }
                return false;
            }
            return false;
        }

        // Modify callback: runs after each inject step to perform type/structure validation.
        private static object? _Validation(
            object? pval, object? key, object? parent, object? injObj, object? store)
        {
            if (injObj is not InjectState inj)
            {
                return null;
            }

            bool isSkipVal = pval is Dictionary<string, object?> sd && sd.ContainsKey("`$SKIP`");
            if (isSkipVal)
            {
                return null;
            }

            // TS reads the spec value through getprop, so a null spec value is NONE.
            pval ??= NONE;

            bool exact = GetProp(inj.Meta, S_BEXACT) is bool b && b;

            bool cKeyExists = TryGetDataValue(inj.DParent, key, out object? cval);

            // TS's getprop answers NONE for a null value too, so a null keeps
            // the spec default exactly as an absent key does, and so does a
            // NONE that a $NOF or $ALL trial passes down.
            if (!exact && (!cKeyExists || cval == null || ReferenceEquals(cval, NONE)))
            {
                return null;
            }

            int ptype = Typify(pval);

            // Skip if spec value still contains a $ command name.
            if (0 < (T.Str & ptype) && pval is string ps && ps.Contains(S_DS))
            {
                return null;
            }

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
                bool isOpen = true == (openFlag as bool?);

                // Empty spec map means open (accepts any keys).
                if (0 < Size(pkeys) && !isOpen)
                {
                    var badkeys = new List<string>();
                    foreach (string ck in ckeys)
                    {
                        // Literal presence: validation needs to know if the SHAPE
                        // declares this key, regardless of whether the validator
                        // stored null in that slot. Group A HasKey would miss
                        // null-valued slots (canonical uses _lookup here).
                        if (ReferenceEquals(Lookup(pval, ck), NONE))
                        {
                            badkeys.Add(ck);
                        }
                    }

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
                    if (IsNode(pval))
                    {
                        DelProp(pval, "`$OPEN`");
                    }
                }
            }
            else if (IsList(cval))
            {
                if (!IsList(pval))
                {
                    inj.Errs.Add(_InvalidTypeMsg(inj.Path, TypeName(ptype), ctype, cval));
                }
            }
            else if (exact)
            {
                // TS getprop answers NONE for an absent key and a null alike.
                object? cExact = cKeyExists && cval != null ? cval : NONE;
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
            if (refStr == null)
            {
                return _InjectHandler(inj, val, refStr, store);
            }

            var m = R_META_PATH.Match(refStr);
            if (m.Success)
            {
                if (m.Groups[2].Value == "=")
                {
                    inj.SetVal(new List<object?> { (object?)S_BEXACT, val });
                }
                else
                {
                    inj.SetVal(val);
                }

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
            var errs = injdef?.Errs ?? [];

            // Extra validation commands override / supplement default store.
            var extraStore = new Dictionary<string, object?>();
            if (injdef?.Extra != null)
            {
                foreach (var kv in Items(injdef.Extra))
                {
                    extraStore[kv[0]?.ToString() ?? ""] = kv[1];
                }
            }

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
                    ["$STRING"]   = _ValidateString,
                    ["$NUMBER"]   = _ValidateType,
                    ["$INTEGER"]  = _ValidateType,
                    ["$DECIMAL"]  = _ValidateType,
                    ["$BOOLEAN"]  = _ValidateType,
                    ["$NULL"]     = _ValidateType,
                    ["$NIL"]      = _ValidateType,
                    ["$MAP"]      = _ValidateType,
                    ["$LIST"]     = _ValidateType,
                    ["$FUNCTION"] = _ValidateType,
                    ["$INSTANCE"] = _ValidateType,
                    ["$ANY"]      = _ValidateAny,
                    ["$CHILD"]    = _ValidateChild,
                    ["$EXACT"]    = _ValidateExact,
                    ["$NOF"]      = _ValidateNof,
                    ["$ALL"]      = _ValidateAll,
                    ["$LEN"]      = _ValidateLen,
                    ["$RANGE"]    = _ValidateRange,

                    [S_DERRS] = errs,
                },
                // Match TS merge([..., getdef(extra, {}), ...]): empty extra is {}, not null —
                // null would be treated as a scalar and wipe the validation command map.
                IsEmpty(extraStore) ? [] : extraStore,
                new Dictionary<string, object?> { [S_DERRS] = errs },
            }, 1)!;

            var meta = injdef?.Meta ?? [];
            SetProp(meta, S_BEXACT, GetProp(meta, S_BEXACT) ?? false);

            // A spec that names an unknown checker validates nothing.
            int numerrs = errs.Count;
            _CheckNames(spec, store, [], errs);

            // Pass errs explicitly so Transform collects (doesn't throw) internally.
            object? out_ = numerrs < errs.Count
                ? Clone(data)
                : Transform(data, spec, new InjectState
                {
                    Extra = store,
                    ModifyFn = _Validation,
                    Handler = _ValidateHandler,
                    Meta = meta,
                    Errs = errs,
                });

            return errs.Count > 0 && !collect
                ? throw new InvalidOperationException(
                    string.Join(" | ", errs.Select(e => e?.ToString() ?? "")))
                : out_;
        }

        // Names a validate spec may use besides its checkers: transform's that it keeps, and $OPEN.
        private static readonly string[] VALIDATE_NAMES =
        [
            "$TOP",
            "$SPEC",
            "$BT",
            "$DS",
            "$WHEN",
            "$ANNO",
            "$REF",
            "$FORMAT",
            "$APPLY",
            "$OPEN",
        ];

        // Report each checker the spec names that validate lacks; $EXACT's arguments are literals.
        private static void _CheckNames(object? spec, object? store, List<object?> path, List<object?> errs)
        {
            string? name = _RefName(spec);
            if (null != name)
            {
                if (_UnknownName(name, store))
                {
                    errs.Add("Unknown validator " + name + " at field " + Pathify(path) + ".");
                }
                return;
            }

            if (IsList(spec) && "$EXACT" == _RefName(Lookup(spec, 0)))
            {
                return;
            }

            foreach (string key in KeysOf(spec))
            {
                if (IsMap(spec))
                {
                    _CheckNames(key, store, path, errs);
                }
                _CheckNames(Lookup(spec, key), store, [.. path, key], errs);
            }
        }

        // The name a whole-string reference gives, when it is a checker name in any case.
        private static string? _RefName(object? val)
        {
            Match? m = val is string s ? R_INJECTION_FULL.Match(s) : null;
            return null != m && m.Success && R_CHECKER_NAME.IsMatch(m.Groups[1].Value.ToUpperInvariant())
                ? m.Groups[1].Value
                : null;
        }

        // Unknown: undefined and upper case, or a defined name in another case. Null disables a name.
        private static bool _UnknownName(string name, object? store)
        {
            bool Known(string n)
            {
                object? v = Lookup(store, n);
                return 0 <= Array.IndexOf(VALIDATE_NAMES, n) || (null != v && !ReferenceEquals(v, NONE));
            }

            string upper = name.ToUpperInvariant();
            return !Known(name) && (upper == name || Known(upper));
        }

        // The data value at a list directive's slot. The directive's own DParent was
        // read with GetProp, which reports a stored null as absent.
        private static object? _SlotVal(InjectState inj)
        {
            InjectState? prior = inj.Prior;
            return null == prior ? inj.DParent : Lookup(prior.DParent, prior.Key);
        }

        // Set the slot that holds a list directive, as setval(val, 2) does. SetVal
        // deletes on null, and a null at the slot is a value.
        private static void _SetSlot(InjectState inj, object? val)
        {
            if (null == val)
            {
                SetProp(GetElem(inj.Nodes, -2), GetElem(inj.Path, -2), null);
            }
            else
            {
                inj.SetVal(val, 2);
            }
        }

        // JSON equality: numbers by value, lists in order, maps by key in any order.
        // A boolean is never a number, and a function or instance equals only itself.
        private static bool _DeepEqual(object? a, object? b)
        {
            if (ReferenceEquals(a, b))
            {
                return true;
            }

            if (a is int or long or double or float && b is int or long or double or float)
            {
                return Convert.ToDouble(a, CultureInfo.InvariantCulture) ==
                    Convert.ToDouble(b, CultureInfo.InvariantCulture);
            }

            if (a is string or bool)
            {
                return a.Equals(b);
            }

            if (!(IsList(a) && IsList(b)) && !(IsMap(a) && IsMap(b)))
            {
                return false;
            }

            var akeys = KeysOf(a);
            var bkeys = KeysOf(b);
            if (akeys.Count != bkeys.Count)
            {
                return false;
            }

            for (int kI = 0; kI < akeys.Count; kI++)
            {
                string k = akeys[kI];
                if (k != bkeys[kI] || !_DeepEqual(Lookup(a, k), Lookup(b, k)))
                {
                    return false;
                }
            }

            return true;
        }

        // Every member val has is in out, unchanged. A member only out has is a
        // default the spec supplied, and is ignored.
        private static bool _Keeps(object? val, object? out_)
        {
            if (ReferenceEquals(val, NONE))
            {
                return true;
            }

            if (!IsNode(val) || IsList(val) != IsList(out_) || !IsNode(out_))
            {
                return _DeepEqual(val, out_);
            }

            foreach (string k in KeysOf(val))
            {
                if (!_Keeps(Lookup(val, k), Lookup(out_, k)))
                {
                    return false;
                }
            }

            return true;
        }

        // A spec admits a value when validating the value against it finds no error
        // and gives back the value as it is.
        private static bool _Admits(object? val, object? spec, InjectState inj, object? store)
        {
            var terrs = new List<object?>();

            var vstore = (Dictionary<string, object?>)Merge(
                new List<object?> { new Dictionary<string, object?>(), store }, 1)!;
            vstore[S_DTOP] = val;

            object? out_ = Validate(val, spec, new InjectState
            {
                Extra = vstore,
                Errs = terrs,
                Meta = inj.Meta,
            });

            return 0 == Size(terrs) && _Keeps(val, out_);
        }

        // The bounds of a $NOF count, and the words for it, which are null when
        // the count is invalid. Without a max, the bound is the number of specs.
        private static (double lo, double hi, string? desc) _NofCount(object? count, int numtvals)
        {
            static bool IsNat(object? n)
            {
                return n is int or long or double or float && 0 < (T.Integer & Typify(n)) &&
                    0 <= Convert.ToDouble(n, CultureInfo.InvariantCulture);
            }

            static string Num(double n)
            {
                return Stringify(n);
            }

            if (IsNat(count))
            {
                double c = Convert.ToDouble(count, CultureInfo.InvariantCulture);
                return (c, c, 0 == c ? "none" : "exactly " + Num(c));
            }

            object? min = Lookup(count, "min");
            object? max = Lookup(count, "max");
            bool hasmin = !ReferenceEquals(min, NONE);
            bool hasmax = !ReferenceEquals(max, NONE);

            bool valid =
                IsMap(count) &&
                0 < Size(count) &&
                Size(count) == (hasmin ? 1 : 0) + (hasmax ? 1 : 0) &&
                (!hasmin || IsNat(min)) &&
                (!hasmax || IsNat(max)) &&
                (!hasmin || !hasmax ||
                    Convert.ToDouble(min, CultureInfo.InvariantCulture) <=
                    Convert.ToDouble(max, CultureInfo.InvariantCulture));

            if (!valid)
            {
                return (0, 0, null);
            }

            double lo = hasmin ? Convert.ToDouble(min, CultureInfo.InvariantCulture) : 0;
            double hi = hasmax ? Convert.ToDouble(max, CultureInfo.InvariantCulture) : numtvals;

            string desc =
                !hasmax
                    ? "at least " + Num(lo)
                    : 0 == hi
                        ? "none"
                        : !hasmin
                            ? "at most " + Num(hi)
                            : lo == hi
                                ? "exactly " + Num(lo)
                                : Num(lo) + " to " + Num(hi);

            return (lo, hi, desc);
        }


        // ========================================================================
        // SELECT
        // ========================================================================

        private static double _SelectToDouble(object? v)
        {
            return v switch
            {
                int i => i,
                long l => l,
                double d => d,
                float f => f,
                _ => double.TryParse(v?.ToString(), NumberStyles.Any,
                    CultureInfo.InvariantCulture, out double x)
                    ? x : double.NaN,
            };
        }

        // $AND: all terms must match.
        private static readonly Injector _SelectAnd = (inj, val, refStr, store) =>
        {
            if (M_KEYPRE != inj.Mode)
            {
                return null;
            }

            var terms = GetProp(inj.Parent, inj.Key) as List<object?> ?? [];
            var ppath = (List<object?>)Slice(inj.Path, -1)!;
            object? point = GetPath(store, ppath);

            var vstore = (Dictionary<string, object?>)Merge(
                new List<object?> { new Dictionary<string, object?>(), store }, 1)!;
            vstore[S_DTOP] = point;

            foreach (object? term in terms)
            {
                var terrs = new List<object?>();
                Validate(point, term, new InjectState { Extra = vstore, Errs = terrs, Meta = inj.Meta });
                if (0 != Size(terrs))
                {
                    inj.Errs.Add("AND:" + Pathify(ppath) + S_VIZ + Stringify(point) +
                        " fail:" + Stringify(terms));
                }
            }

            object? gkey = GetElem(inj.Path, -2);
            object? gp = GetElem(inj.Nodes, -2);
            SetProp(gp, gkey, point);
            return null;
        };

        // $OR: at least one term must match.
        private static readonly Injector _SelectOr = (inj, val, refStr, store) =>
        {
            if (M_KEYPRE != inj.Mode)
            {
                return null;
            }

            var terms = GetProp(inj.Parent, inj.Key) as List<object?> ?? [];
            var ppath = (List<object?>)Slice(inj.Path, -1)!;
            object? point = GetPath(store, ppath);

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
                    object? gp2 = GetElem(inj.Nodes, -2);
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
            if (M_KEYPRE != inj.Mode)
            {
                return null;
            }

            object? term = GetProp(inj.Parent, inj.Key);
            var ppath = (List<object?>)Slice(inj.Path, -1)!;
            object? point = GetPath(store, ppath);

            var vstore = (Dictionary<string, object?>)Merge(
                new List<object?> { new Dictionary<string, object?>(), store }, 1)!;
            vstore[S_DTOP] = point;

            var terrs = new List<object?>();
            Validate(point, term, new InjectState { Extra = vstore, Errs = terrs, Meta = inj.Meta });

            if (0 == Size(terrs))
            {
                inj.Errs.Add("NOT:" + Pathify(ppath) + S_VIZ + Stringify(point) +
                    " fail:" + Stringify(term));
            }

            object? gkey = GetElem(inj.Path, -2);
            object? gp = GetElem(inj.Nodes, -2);
            SetProp(gp, gkey, point);
            return null;
        };

        // $GT, $LT, $GTE, $LTE, $LIKE: comparison operators.
        private static readonly Injector _SelectCmp = (inj, val, refStr, store) =>
        {
            if (M_KEYPRE != inj.Mode)
            {
                return NONE;
            }

            object? term = GetProp(inj.Parent, inj.Key);
            object? gkey = GetElem(inj.Path, -2);
            var ppath = (List<object?>)Slice(inj.Path, -1)!;
            object? point = GetPath(store, ppath);

            bool pass = false;

            double pd = _SelectToDouble(point);
            double td = _SelectToDouble(term);
            if (!double.IsNaN(pd) && !double.IsNaN(td))
            {
                if (refStr == "$GT" && pd > td)
                {
                    pass = true;
                }
                else if (refStr == "$LT" && pd < td)
                {
                    pass = true;
                }
                else if (refStr == "$GTE" && pd >= td)
                {
                    pass = true;
                }
                else if (refStr == "$LTE" && pd <= td)
                {
                    pass = true;
                }
            }

            if (!pass && refStr == "$LIKE")
            {
                string pattern = term?.ToString() ?? "";
                string subject2 = Stringify(point);
                try
                {
                    if (Regex.IsMatch(subject2, pattern))
                    {
                        pass = true;
                    }
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
            if (!IsNode(children))
            {
                return [];
            }

            List<object?> childList = IsMap(children)
                ? Items(children, n =>
                {
                    SetProp(n[1], S_DKEY, n[0]);
                    return n[1];
                })
                : Items(children, n =>
                {
                    object? idx = n[0];
                    if (idx is string s && long.TryParse(s, out long li))
                    {
                        SetProp(n[1], S_DKEY, (object?)li);
                    }
                    else
                    {
                        SetProp(n[1], S_DKEY, idx);
                    }

                    return n[1];
                });
            var results = new List<object?>();

            var selectExtra = new Dictionary<string, object?>
            {
                ["`$AND`"] = _SelectAnd,
                ["`$OR`"] = _SelectOr,
                ["`$NOT`"] = _SelectNot,
                ["$AND"] = _SelectAnd,
                ["$OR"] = _SelectOr,
                ["$NOT"] = _SelectNot,
                // JSON/test fixtures use backtick-wrapped keys (`$GT`, etc.); GetPath resolves bare $NAME.
                ["`$GT`"] = _SelectCmp,
                ["`$LT`"] = _SelectCmp,
                ["`$GTE`"] = _SelectCmp,
                ["`$LTE`"] = _SelectCmp,
                ["`$LIKE`"] = _SelectCmp,
                ["$GT"] = _SelectCmp,
                ["$LT"] = _SelectCmp,
                ["$GTE"] = _SelectCmp,
                ["$LTE"] = _SelectCmp,
                ["$LIKE"] = _SelectCmp,
            };

            var meta = new Dictionary<string, object?> { [S_BEXACT] = true };
            var q = Clone(query);

            _OpenQuery(q);

            foreach (object? child in childList)
            {
                var errs = new List<object?>();
                Validate(child, Clone(q), new InjectState
                {
                    Extra = selectExtra,
                    Errs = errs,
                    Meta = meta,
                });

                if (0 == Size(errs))
                {
                    results.Add(child);
                }
            }

            return results;
        }

        // Open every map in a select query, so a child may hold keys the query does
        // not name, but leave a directive's literals as written: what $EXACT
        // compares, and the count or bound of $NOF, $LEN and $RANGE.
        private static void _OpenQuery(object? q)
        {
            if (q is Dictionary<string, object?> map)
            {
                SetProp(map, "`$OPEN`", GetProp(map, "`$OPEN`", true));
                foreach (string key in KeysOf(map))
                {
                    _OpenQuery(map[key]);
                }
            }
            else if (q is List<object?> list)
            {
                object? head = 0 < list.Count ? list[0] : null;
                bool exact = head is "`$EXACT`";
                bool bounded = head is "`$NOF`" or "`$LEN`" or "`$RANGE`";
                for (int i = 0; i < list.Count; i++)
                {
                    if (0 == i || !(exact || (bounded && 1 == i)))
                    {
                        _OpenQuery(list[i]);
                    }
                }
            }
        }


        // ========================================================================
        // Condense
        // ========================================================================

        private const long CONDENSE_VERSION = 1;

        private const long CONDENSE_MAP = 0;
        private const long CONDENSE_LIST = 1;
        private const long CONDENSE_STR = 2;
        private const long CONDENSE_NUM = 3;
        private const long CONDENSE_TRUE = 4;
        private const long CONDENSE_FALSE = 5;
        private const long CONDENSE_NULL = 6;

        private const string S_condense = "$condense";
        private const string S_condsym = "sym";
        private const string S_condnode = "node";
        private const string S_condroot = "root";

        private const string S_IMMUTABLE =
            "struct: condensed structures are immutable - expand() first, then modify the copy";

        private const double TWO_POW_63 = 9223372036854775808.0;

        public static bool IsCondensed(object? val = null)
        {
            return val is Dictionary<string, object?> map
                && map.TryGetValue(S_condense, out object? version)
                && CondenseInt(version, out long v)
                && CONDENSE_VERSION == v
                && map.TryGetValue(S_condsym, out object? sym) && sym is List<object?>
                && map.TryGetValue(S_condnode, out object? node) && node is List<object?>
                && map.TryGetValue(S_condroot, out object? root) && root is int or long or double or float;
        }

        // Pure: the same input gives the same bytes, on every port.
        public static object? Condense(object? val)
        {
            var symset = new HashSet<string>(StringComparer.Ordinal);
            CondenseCollect(val, symset);
            List<string> sym = [.. symset];
            sym.Sort(CondenseCmp);
            var symid = new Dictionary<string, long>(StringComparer.Ordinal);
            for (int i = 0; i < sym.Count; i++)
            {
                symid[sym[i]] = i;
            }

            List<object?> node = [];
            var seen = new Dictionary<string, long>(StringComparer.Ordinal);
            long root = CondenseBuild(val, symid, node, seen);

            return new Dictionary<string, object?>
            {
                [S_condense] = CONDENSE_VERSION,
                [S_condsym] = sym.Cast<object?>().ToList(),
                [S_condnode] = node,
                [S_condroot] = root,
            };
        }

        // A value that is not condensed comes back as itself.
        public static object? Expand(object? cond)
        {
            if (!IsCondensed(cond))
            {
                return cond;
            }

            object? out2 = CondenseRebuild(cond, CondenseRoot(cond));
            return ReferenceEquals(out2, NONE) ? null : out2;
        }

        public static CondenseView CondenseView(object? cond, long? idx = null,
                                                Dictionary<string, object?>? memo = null)
        {
            long start = idx ?? (IsCondensed(cond) ? CondenseRoot(cond) : -1);
            return new CondenseView(cond, start, memo ?? []);
        }

        private static void CondenseCollect(object? n, HashSet<string> symset)
        {
            if (n is Dictionary<string, object?> map)
            {
                foreach (KeyValuePair<string, object?> entry in map)
                {
                    symset.Add(entry.Key);
                    CondenseCollect(entry.Value, symset);
                }
            }
            else if (n is List<object?> list)
            {
                foreach (object? item in list)
                {
                    CondenseCollect(item, symset);
                }
            }
            else if (n is string s)
            {
                symset.Add(s);
            }
        }

        // Post-order, so identical subtrees are already interned when a parent names them.
        private static long CondenseBuild(object? n, Dictionary<string, long> symid,
                                          List<object?> node, Dictionary<string, long> seen)
        {
            List<object?> enc;
            if (n is Dictionary<string, object?> map)
            {
                enc = [CONDENSE_MAP];
                foreach (KeyValuePair<string, object?> entry in map.OrderBy(e => symid[e.Key]))
                {
                    enc.Add(symid[entry.Key]);
                    enc.Add(CondenseBuild(entry.Value, symid, node, seen));
                }
            }
            else if (n is List<object?> list)
            {
                enc = [CONDENSE_LIST];
                foreach (object? item in list)
                {
                    enc.Add(CondenseBuild(item, symid, node, seen));
                }
            }
            else if (n is string s)
            {
                enc = [CONDENSE_STR, symid[s]];
            }
            else if (n is int or long or double or float)
            {
                enc = [CONDENSE_NUM, n];
            }
            else if (n is bool b)
            {
                enc = [b ? CONDENSE_TRUE : CONDENSE_FALSE];
            }
            else
            {
                enc = [CONDENSE_NULL];
            }

            string key = string.Join(S_CM, enc.Select(CondenseNumKey));
            if (seen.TryGetValue(key, out long hit))
            {
                return hit;
            }

            long idx = node.Count;
            node.Add(enc);
            seen[key] = idx;
            return idx;
        }

        // Equal numbers spell the same, so an integer and a decimal of one value share a node.
        private static string CondenseNumKey(object? v)
        {
            return CondenseInt(v, out long n)
                ? n.ToString(CultureInfo.InvariantCulture)
                : Convert.ToDouble(v, CultureInfo.InvariantCulture).ToString("R", CultureInfo.InvariantCulture);
        }

        // The integer a number holds: false for anything else, a fraction included.
        private static bool CondenseInt(object? v, out long n)
        {
            if (v is int i)
            {
                n = i;
                return true;
            }

            if (v is long l)
            {
                n = l;
                return true;
            }

            double d = v is double dv ? dv : v is float fv ? fv : double.NaN;
            if (Math.Floor(d) == d && -TWO_POW_63 <= d && d < TWO_POW_63)
            {
                n = (long)d;
                return true;
            }

            n = -1;
            return false;
        }

        // An index read from the format, or -1 when the value cannot be one.
        private static long CondenseIdx(object? v)
        {
            return CondenseInt(v, out long n) ? n : -1;
        }

        private static List<object?>? CondenseField(object? cond, string name)
        {
            return cond is Dictionary<string, object?> map && map.TryGetValue(name, out object? v)
                ? v as List<object?>
                : null;
        }

        internal static long CondenseRoot(object? cond)
        {
            return cond is Dictionary<string, object?> map && map.TryGetValue(S_condroot, out object? root)
                ? CondenseIdx(root)
                : -1;
        }

        // Node idx's encoding; NONE when it is absent or null.
        private static object? CondenseEnc(object? cond, long idx)
        {
            List<object?>? node = CondenseField(cond, S_condnode);
            object? enc = node != null && 0 <= idx && idx < node.Count ? node[(int)idx] : null;
            return enc ?? NONE;
        }

        private static long CondenseKind(List<object?>? el)
        {
            return el != null && 0 < el.Count ? CondenseIdx(el[0]) : -1;
        }

        // sym[id]; NONE when id does not index sym.
        private static object? CondenseSym(object? cond, object? id)
        {
            List<object?>? sym = CondenseField(cond, S_condsym);
            long i = CondenseIdx(id);
            return sym != null && 0 <= i && i < sym.Count ? sym[(int)i] : NONE;
        }

        // sym[id] as a map key: its string form when it is not a string.
        private static string CondenseKeyName(object? cond, object? id)
        {
            object? s = CondenseSym(cond, id);
            return s as string ?? CondenseStr(s);
        }

        // Code-point order, unlike string.CompareOrdinal: a surrogate pair sorts as the
        // character it encodes, after every other character up to U+FFFF.
        private static int CondenseCmp(string a, string b)
        {
            int i = 0;
            int j = 0;
            while (i < a.Length && j < b.Length)
            {
                int ca = CondenseCodePoint(a, i);
                int cb = CondenseCodePoint(b, j);
                if (ca != cb)
                {
                    return ca < cb ? -1 : 1;
                }

                i += 0xffff < ca ? 2 : 1;
                j += 0xffff < cb ? 2 : 1;
            }

            return a.Length - i - (b.Length - j);
        }

        private static int CondenseCodePoint(string s, int i)
        {
            return char.IsHighSurrogate(s[i]) && i + 1 < s.Length && char.IsLowSurrogate(s[i + 1])
                ? char.ConvertToUtf32(s[i], s[i + 1])
                : s[i];
        }

        // JS `'' + v`.
        private static string CondenseStr(object? v)
        {
            return v switch
            {
                null => S_null,
                string s => s,
                bool b => b ? "true" : "false",
                int or long => Convert.ToString(v, CultureInfo.InvariantCulture) ?? S_MT,
                double or float => CondenseNumStr(Convert.ToDouble(v, CultureInfo.InvariantCulture)),
                List<object?> l => string.Join(S_CM, l.Select(e => e == null || ReferenceEquals(e, NONE)
                    ? S_MT
                    : CondenseStr(e))),
                _ => ReferenceEquals(v, NONE) ? "undefined" : "[object Object]",
            };
        }

        private static string CondenseNumStr(double d)
        {
            if (double.IsNaN(d))
            {
                return "NaN";
            }

            if (double.IsInfinity(d))
            {
                return d < 0 ? "-Infinity" : "Infinity";
            }

            return Math.Floor(d) == d && Math.Abs(d) < 1e21
                ? (0 == d ? 0.0 : d).ToString("F0", CultureInfo.InvariantCulture)
                : d.ToString("R", CultureInfo.InvariantCulture);
        }

        private static long CondenseSymId(object? cond, string key)
        {
            List<object?>? sym = CondenseField(cond, S_condsym);
            if (sym == null)
            {
                return -1;
            }

            long lo = 0;
            long hi = sym.Count - 1;
            while (lo <= hi)
            {
                long mid = (lo + hi) / 2;
                int c = CondenseCmp(sym[(int)mid] as string ?? S_MT, key);
                if (0 == c)
                {
                    return mid;
                }

                if (0 > c)
                {
                    lo = mid + 1;
                }
                else
                {
                    hi = mid - 1;
                }
            }

            return -1;
        }

        // The node index of key inside node idx, or -1. Touches only this node.
        private static long CondenseChild(object? cond, long idx, string key)
        {
            List<object?>? el = CondenseEnc(cond, idx) as List<object?>;
            long kind = CondenseKind(el);

            if (CONDENSE_MAP == kind)
            {
                long symid = CondenseSymId(cond, key);
                long lo = 0;
                long hi = ((el!.Count - 1) / 2) - 1;
                while (0 <= symid && lo <= hi)
                {
                    long mid = (lo + hi) / 2;
                    long k = CondenseIdx(el[(int)(1 + (mid * 2))]);
                    if (k == symid)
                    {
                        return CondenseIdx(el[(int)(2 + (mid * 2))]);
                    }

                    if (k < symid)
                    {
                        lo = mid + 1;
                    }
                    else
                    {
                        hi = mid - 1;
                    }
                }

                return -1;
            }

            if (CONDENSE_LIST == kind)
            {
                return CanonListIndex(key, out long i) && 0 <= i && i < el!.Count - 1
                    ? CondenseIdx(el[(int)(1 + i)])
                    : -1;
            }

            return -1;
        }

        // Walk a path from node idx: the node index reached, or -1.
        internal static long CondenseResolve(object? cond, long idx, object? path)
        {
            long at = idx;

            if (path is System.Collections.IList parts)
            {
                foreach (object? part in parts)
                {
                    if (0 > at || part is not (string or int or long or double or float))
                    {
                        return -1;
                    }

                    if (part is not string { Length: 0 })
                    {
                        at = CondenseChild(cond, at, CondenseStr(part));
                    }
                }
            }
            else if (path is string s)
            {
                foreach (string part in 0 < s.Length ? s.Split('.') : [])
                {
                    if (0 > at)
                    {
                        return -1;
                    }

                    if (0 < part.Length)
                    {
                        at = CondenseChild(cond, at, part);
                    }
                }
            }
            else if (path != null && !ReferenceEquals(path, NONE))
            {
                if (0 > at)
                {
                    return -1;
                }

                at = CondenseChild(cond, at, CondenseStr(path));
            }

            return at;
        }

        // A fresh, independent tree for node idx; NONE when there is no such node.
        internal static object? CondenseRebuild(object? cond, long idx)
        {
            object? enc = CondenseEnc(cond, idx);
            if (ReferenceEquals(enc, NONE))
            {
                return NONE;
            }

            List<object?>? el = enc as List<object?>;
            long kind = CondenseKind(el);

            if (CONDENSE_MAP == kind)
            {
                Dictionary<string, object?> out2 = [];
                for (int j = 1; j < el!.Count; j += 2)
                {
                    object? child = CondenseRebuild(cond, j + 1 < el.Count ? CondenseIdx(el[j + 1]) : -1);
                    string key = CondenseKeyName(cond, el[j]);
                    // As setprop does for an absent value, the key goes.
                    if (ReferenceEquals(child, NONE))
                    {
                        out2.Remove(key);
                    }
                    else
                    {
                        out2[key] = child;
                    }
                }

                return out2;
            }

            if (CONDENSE_LIST == kind)
            {
                List<object?> out2 = new(el!.Count - 1);
                for (int j = 1; j < el.Count; j++)
                {
                    object? child = CondenseRebuild(cond, CondenseIdx(el[j]));
                    out2.Add(ReferenceEquals(child, NONE) ? null : child);
                }

                return out2;
            }

            if (CONDENSE_STR == kind)
            {
                object? s = 1 < el!.Count ? CondenseSym(cond, el[1]) : NONE;
                return ReferenceEquals(s, NONE) ? NONE : Clone(s);
            }

            if (CONDENSE_NUM == kind)
            {
                return 1 < el!.Count ? Clone(el[1]) : NONE;
            }

            if (kind is CONDENSE_TRUE or CONDENSE_FALSE)
            {
                return CONDENSE_TRUE == kind;
            }

            return null;
        }

        internal static List<string> CondenseKeys(object? cond, long idx)
        {
            List<string> out2 = [];
            List<object?>? el = CondenseEnc(cond, idx) as List<object?>;
            long kind = CondenseKind(el);

            if (CONDENSE_MAP == kind)
            {
                for (int j = 1; j < el!.Count; j += 2)
                {
                    out2.Add(CondenseKeyName(cond, el[j]));
                }
            }
            else if (CONDENSE_LIST == kind)
            {
                for (int j = 1; j < el!.Count; j++)
                {
                    out2.Add((j - 1).ToString(CultureInfo.InvariantCulture));
                }
            }

            return out2;
        }

        internal static int CondenseSize(object? cond, long idx)
        {
            List<object?>? el = CondenseEnc(cond, idx) as List<object?>;
            long kind = CondenseKind(el);
            if (CONDENSE_MAP == kind)
            {
                return (el!.Count - 1) / 2;
            }

            return CONDENSE_LIST == kind ? el!.Count - 1 : 0;
        }

        [GeneratedRegex(@"[.*+?^${}()|[\]\\]")]
        private static partial Regex R_EscapeRegexpGen();
        [GeneratedRegex(@"^`\$REF:([0-9]+)`$")]
        private static partial Regex R_CloneRefGen();
        [GeneratedRegex(@"^`(\$[A-Z]+|[^`]*)[0-9]*`$")]
        private static partial Regex R_InjectionFullGen();
        [GeneratedRegex(@"`([^`]+)`")]
        private static partial Regex R_InjectionPartialGen();
        [GeneratedRegex(@"\$\$")]
        private static partial Regex R_DoubleDollarGen();
        [GeneratedRegex(@"^([^$]+)\$([=~])(.+)$")]
        private static partial Regex R_MetaPathGen();
        [GeneratedRegex(@"`\$([A-Z]+)`")]
        private static partial Regex R_TransformNameGen();
        // \z, since .NET's $ also matches before a final newline.
        [GeneratedRegex(@"^\$[A-Z]+\z")]
        private static partial Regex R_CheckerNameGen();
        [GeneratedRegex(@"\.")]
        private static partial Regex R_DotGen();
    }


    // A cursor into a condensed structure. Views made by At share the memo, so Ref hands
    // every one of them the same node.
    public sealed class CondenseView
    {
        private readonly object? _cond;
        private readonly long _start;
        private readonly Dictionary<string, object?> _memo;

        internal CondenseView(object? cond, long start, Dictionary<string, object?> memo)
        {
            _cond = cond;
            _start = start;
            _memo = memo;
        }

        public object? Get(object? path = null)
        {
            return Present(StructUtils.CondenseRebuild(_cond, StructUtils.CondenseResolve(_cond, _start, path)));
        }

        public List<string> Keys(object? path = null)
        {
            return StructUtils.CondenseKeys(_cond, StructUtils.CondenseResolve(_cond, _start, path));
        }

        public bool Has(object? path = null)
        {
            return 0 <= StructUtils.CondenseResolve(_cond, _start, path);
        }

        public CondenseView At(object? path = null)
        {
            return new CondenseView(_cond, StructUtils.CondenseResolve(_cond, _start, path), _memo);
        }

        public object? Value()
        {
            return Present(StructUtils.CondenseRebuild(_cond, _start));
        }

        public int Size()
        {
            return StructUtils.CondenseSize(_cond, _start);
        }

        public bool Exists()
        {
            return 0 <= _start;
        }

        // Shared, unlike Get and Value: mutating the result changes every reader of the node.
        public object? Ref()
        {
            string k = _start.ToString(CultureInfo.InvariantCulture);
            if (_memo.TryGetValue(k, out object? hit))
            {
                return hit;
            }

            object? out2 = StructUtils.CondenseRebuild(_cond, _start);
            if (ReferenceEquals(out2, StructUtils.NONE))
            {
                return null;
            }

            _memo[k] = out2;
            return out2;
        }

        private static object? Present(object? val)
        {
            return ReferenceEquals(val, StructUtils.NONE) ? null : val;
        }
    }
}
