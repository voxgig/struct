// Test Provider (prototype) — C# port of the canonical TypeScript
// implementation (../ts/provider.ts).
//
// Reads the shared corpus (build/test/test.json) and hands test code clean,
// normalized cases. It is NOT a test runner: it never calls the subject and
// never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
//
// Zero runtime dependencies (.NET standard library only — System.Text.Json is
// part of the BCL), matching repo policy.

using System.Collections;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Voxgig.Struct.Proto;

public enum InputKind { In, Args, Ctx }

public enum ExpectKind { Value, Error, Match, Absent }

// Input is a tagged invocation: exactly one of In/Args/Ctx is meaningful,
// selected by Kind (mirrors the runner's ctx -> args -> in precedence).
public sealed class Input
{
    public InputKind Kind;
    public object? In;                       // Kind==In  (absent => null)
    public List<object?>? Args;              // Kind==Args
    public Dictionary<string, object?>? Ctx; // Kind==Ctx
}

// ErrorCheck is the parsed form of a raw `err` spec.
public sealed class ErrorCheck
{
    public bool Any;
    public string? Text;
    public bool Regex;
}

// Expect is a tagged expectation: value | error | match | absent.
public sealed class Expect
{
    public ExpectKind Kind;
    public bool HasValue;       // distinguishes present-null from absent
    public object? Value;       // Kind==Value
    public ErrorCheck? Error;   // Kind==Error
    public object? Match;       // populated whenever a `match` key is present
}

// Entry is the normalized record for a single corpus test case.
public sealed class Entry
{
    public string Function = "";
    public string Group = "";
    public int Index;
    public string? Id;
    public bool Doc;
    public string? Client;
    public Input Input = new();
    public Expect Expect = new();
    public object? Raw;
}

// MatchResult is the outcome of a structural match.
public sealed class MatchResult
{
    public bool Ok;
    public List<string>? Path;
    public object? Expected;
    public object? Actual;
}

public sealed class TestProvider
{
    public const string NULLMARK   = "__NULL__";
    public const string UNDEFMARK  = "__UNDEF__";
    public const string EXISTSMARK = "__EXISTS__";

    // The parsed corpus as native objects. Objects are represented by
    // OrderedMap so corpus property order (preserved by JsonDocument's
    // EnumerateObject) is retained for Functions()/Groups().
    private readonly object? _spec;

    private TestProvider(object? spec)
    {
        _spec = spec;
    }

    // Default corpus path: build/test/test.json relative to the repo root,
    // resolved from this source file's location so it works regardless of cwd.
    private static string DefaultTestFile([CallerFilePath] string here = "")
    {
        // here = .../test/proto/csharp/Provider.cs
        string dir = Path.GetDirectoryName(here)!; // test/proto/csharp
        return Path.GetFullPath(
            Path.Combine(dir, "..", "..", "..", "build", "test", "test.json"));
    }

    public static TestProvider Load(string? testfile = null)
    {
        string file = testfile ?? DefaultTestFile();
        string json = File.ReadAllText(file);
        using var doc = JsonDocument.Parse(json);
        return new TestProvider(Convert(doc.RootElement));
    }

    // Raw returns the parsed test.json (escape hatch).
    public object? Raw() => _spec;

    // root returns spec.struct if present, else spec itself, as an OrderedMap.
    private OrderedMap? Root()
    {
        if (_spec is OrderedMap m)
        {
            if (m.TryGetValue("struct", out object? s) && s is OrderedMap sm)
            {
                return sm;
            }
            return m;
        }
        return null;
    }

    // fnNode resolves the node for a function (under struct, falling back to root).
    private OrderedMap? FnNode(string fn)
    {
        if (_spec is OrderedMap m)
        {
            if (m.TryGetValue("struct", out object? s) && s is OrderedMap sm
                && sm.TryGetValue(fn, out object? n) && n is OrderedMap nm)
            {
                return nm;
            }
            if (m.TryGetValue(fn, out object? n2) && n2 is OrderedMap nm2)
            {
                return nm2;
            }
        }
        return null;
    }

    // Functions lists the function names in corpus order.
    public List<string> Functions()
    {
        var root = Root();
        var output = new List<string>();
        if (root == null)
        {
            return output;
        }
        foreach (string k in root.Keys)
        {
            object? v = root[k];
            if (IsGroupBag(v) || HasGroups(v))
            {
                output.Add(k);
            }
        }
        return output;
    }

    // Groups lists the group names for a function in corpus order.
    public List<string> Groups(string fn)
    {
        var node = FnNode(fn) ?? throw new ArgumentException($"Unknown function: {fn}");
        var output = new List<string>();
        foreach (string k in node.Keys)
        {
            if (k != "name" && IsGroupBag(node[k]))
            {
                output.Add(k);
            }
        }
        return output;
    }

    // Entries returns all entries for a function, or for one specific group.
    public List<Entry> Entries(string fn, string? group = null)
    {
        var node = FnNode(fn) ?? throw new ArgumentException($"Unknown function: {fn}");
        var groups = group != null ? new List<string> { group } : Groups(fn);
        var output = new List<Entry>();
        foreach (string g in groups)
        {
            if (!node.TryGetValue(g, out object? bagVal) || bagVal is not OrderedMap bag
                || !IsGroupBag(bag))
            {
                continue;
            }
            if (!bag.TryGetValue("set", out object? setVal) || setVal is not List<object?> set)
            {
                continue;
            }
            for (int i = 0; i < set.Count; i++)
            {
                output.Add(Normalize(fn, g, i, set[i] as OrderedMap));
            }
        }
        return output;
    }

    // ─── shape predicates ──────────────────────────────────────────────────

    // A group bag is a map with a `set` array.
    private static bool IsGroupBag(object? v)
        => v is OrderedMap m && m.TryGetValue("set", out object? s) && s is List<object?>;

    // A function node has at least one child group bag (besides `name`).
    private static bool HasGroups(object? v)
    {
        if (v is not OrderedMap m)
        {
            return false;
        }
        foreach (string k in m.Keys)
        {
            if (k != "name" && IsGroupBag(m[k]))
            {
                return true;
            }
        }
        return false;
    }

    // ─── normalization ─────────────────────────────────────────────────────

    private static Entry Normalize(string fn, string group, int index, OrderedMap? raw)
    {
        raw ??= new OrderedMap();
        string? id = (Has(raw, "id") && raw["id"] != null) ? Stringify(raw["id"]) : null;
        string? client = (Has(raw, "client") && raw["client"] != null)
            ? Stringify(raw["client"]) : null;
        bool doc = raw.TryGetValue("doc", out object? dv) && dv is bool db && db;
        return new Entry
        {
            Function = fn,
            Group = group,
            Index = index,
            Id = id,
            Doc = doc,
            Client = client,
            Input = ResolveInput(raw),
            Expect = ResolveExpect(raw),
            Raw = raw,
        };
    }

    private static bool Has(OrderedMap raw, string key) => raw.ContainsKey(key);

    private static Input ResolveInput(OrderedMap raw)
    {
        if (Has(raw, "ctx"))
        {
            return new Input { Kind = InputKind.Ctx, Ctx = raw["ctx"] as Dictionary<string, object?> ?? AsDict(raw["ctx"]) };
        }
        if (Has(raw, "args"))
        {
            return new Input { Kind = InputKind.Args, Args = raw["args"] as List<object?> };
        }
        // Kind==In: key absent => native null.
        return new Input { Kind = InputKind.In, In = Has(raw, "in") ? raw["in"] : null };
    }

    private static Dictionary<string, object?>? AsDict(object? v)
    {
        if (v is OrderedMap m)
        {
            var d = new Dictionary<string, object?>();
            foreach (string k in m.Keys)
            {
                d[k] = m[k];
            }
            return d;
        }
        return null;
    }

    private static readonly Regex ReErr = new(@"^/(.+)/$", RegexOptions.Compiled);

    private static ErrorCheck ParseErr(object? err)
    {
        if (err is bool b && b)
        {
            return new ErrorCheck { Any = true, Text = null, Regex = false };
        }
        if (err is string s)
        {
            Match m = ReErr.Match(s);
            if (m.Success)
            {
                return new ErrorCheck { Any = false, Text = m.Groups[1].Value, Regex = true };
            }
            return new ErrorCheck { Any = false, Text = s, Regex = false };
        }
        // Non-true, non-string err spec: treat as "any error".
        return new ErrorCheck { Any = true, Text = null, Regex = false };
    }

    private static Expect ResolveExpect(OrderedMap raw)
    {
        bool hasMatch = Has(raw, "match");
        object? matchPart = hasMatch ? raw["match"] : null;
        if (Has(raw, "err"))
        {
            return new Expect { Kind = ExpectKind.Error, Error = ParseErr(raw["err"]), Match = matchPart };
        }
        if (Has(raw, "out"))
        {
            return new Expect { Kind = ExpectKind.Value, HasValue = true, Value = raw["out"], Match = matchPart };
        }
        if (hasMatch)
        {
            return new Expect { Kind = ExpectKind.Match, Match = matchPart };
        }
        return new Expect { Kind = ExpectKind.Absent };
    }

    // ─── pure comparison helpers ───────────────────────────────────────────

    public static string Stringify(object? x)
        => x is string s ? s : CompactJson(x);

    private static object? NormNull(object? x)
    {
        if (x is string s && s == NULLMARK)
        {
            return null;
        }
        if (x == null)
        {
            return null;
        }
        if (x is List<object?> list)
        {
            var output = new List<object?>(list.Count);
            foreach (object? e in list)
            {
                output.Add(NormNull(e));
            }
            return output;
        }
        if (x is OrderedMap map)
        {
            var output = new OrderedMap();
            foreach (string k in map.Keys)
            {
                output[k] = NormNull(map[k]);
            }
            return output;
        }
        return x;
    }

    private static object? NormMark(object? x)
    {
        if (x is string s && s == NULLMARK)
        {
            return null;
        }
        if (x is List<object?> list)
        {
            var output = new List<object?>(list.Count);
            foreach (object? e in list)
            {
                output.Add(NormMark(e));
            }
            return output;
        }
        if (x is OrderedMap map)
        {
            var output = new OrderedMap();
            foreach (string k in map.Keys)
            {
                output[k] = NormMark(map[k]);
            }
            return output;
        }
        return x;
    }

    // Matchval reproduces the runner's scalar match: equal, then string rules.
    public static bool Matchval(object? check, object? @base)
    {
        if (ScalarEq(check, @base))
        {
            return true;
        }
        if (check is string cs)
        {
            string basestr = Stringify(@base);
            Match m = ReErr.Match(cs);
            if (m.Success)
            {
                try
                {
                    return Regex.IsMatch(basestr, m.Groups[1].Value);
                }
                catch (ArgumentException)
                {
                    return false;
                }
            }
            return basestr.ToLowerInvariant().Contains(cs.ToLowerInvariant());
        }
        return false;
    }

    // Equal is deep equality collapsing "__NULL__" and null to null on both sides
    // (runner default null:true).
    public static bool Equal(object? expected, object? actual)
        => DeepEq(NormNull(expected), NormNull(actual));

    // EqualStrict is deep equality normalizing only "__NULL__" to null
    // (runner null:false functions; absent stays distinct from null).
    public static bool EqualStrict(object? expected, object? actual)
        => DeepEq(NormMark(expected), NormMark(actual));

    private static bool DeepEq(object? a, object? b)
    {
        if (ScalarEq(a, b))
        {
            return true;
        }
        if (a is List<object?> al && b is List<object?> bl)
        {
            if (al.Count != bl.Count)
            {
                return false;
            }
            for (int i = 0; i < al.Count; i++)
            {
                if (!DeepEq(al[i], bl[i]))
                {
                    return false;
                }
            }
            return true;
        }
        if (a is OrderedMap am && b is OrderedMap bm)
        {
            if (am.Count != bm.Count)
            {
                return false;
            }
            foreach (string k in am.Keys)
            {
                if (!bm.TryGetValue(k, out object? bv) || !DeepEq(am[k], bv))
                {
                    return false;
                }
            }
            return true;
        }
        return false;
    }

    // ScalarEq compares scalars; numeric values compare by value across
    // long/double. null==null is true here.
    private static bool ScalarEq(object? a, object? b)
    {
        if (a == null && b == null)
        {
            return true;
        }
        if (a == null || b == null)
        {
            return false;
        }
        bool aNum = TryToDouble(a, out double ad);
        bool bNum = TryToDouble(b, out double bd);
        if (aNum && bNum)
        {
            return ad == bd;
        }
        if (aNum != bNum)
        {
            return false;
        }
        if (a is string sa && b is string sb)
        {
            return sa == sb;
        }
        if (a is bool ba && b is bool bb)
        {
            return ba == bb;
        }
        return false;
    }

    private static bool TryToDouble(object? v, out double d)
    {
        switch (v)
        {
            case long l: d = l; return true;
            case int i: d = i; return true;
            case double db: d = db; return true;
            case float f: d = f; return true;
            default: d = 0; return false;
        }
    }

    // ErrorMatches checks an ErrorCheck against a thrown message.
    public static bool ErrorMatches(ErrorCheck check, string message)
    {
        if (check.Any)
        {
            return true;
        }
        if (check.Text == null)
        {
            return false;
        }
        if (check.Regex)
        {
            try
            {
                return Regex.IsMatch(message, check.Text);
            }
            catch (ArgumentException)
            {
                return false;
            }
        }
        return message.ToLowerInvariant().Contains(check.Text.ToLowerInvariant());
    }

    // StructMatch performs a partial structural match: every leaf of check must
    // match base at its path. First failure returns its path + the two values.
    public static MatchResult StructMatch(object? check, object? @base)
    {
        var result = new MatchResult { Ok = true };
        WalkLeaves(check, new List<string>(), (val, path) =>
        {
            if (!result.Ok)
            {
                return;
            }
            (object? baseval, bool found) = GetPath(@base, path);
            if (found && ScalarEq(baseval, val))
            {
                return;
            }
            if (val is string us && us == UNDEFMARK && (!found || baseval == null))
            {
                return;
            }
            if (val is string es && es == EXISTSMARK && found && baseval != null)
            {
                return;
            }
            if (!Matchval(val, baseval))
            {
                result = new MatchResult { Ok = false, Path = path, Expected = val, Actual = baseval };
            }
        });
        return result;
    }

    private static void WalkLeaves(object? node, List<string> path, Action<object?, List<string>> fn)
    {
        if (node is List<object?> list)
        {
            for (int i = 0; i < list.Count; i++)
            {
                WalkLeaves(list[i], AppendPath(path, i.ToString(CultureInfo.InvariantCulture)), fn);
            }
        }
        else if (node is OrderedMap map)
        {
            foreach (string k in map.Keys)
            {
                WalkLeaves(map[k], AppendPath(path, k), fn);
            }
        }
        else
        {
            fn(node, path);
        }
    }

    private static List<string> AppendPath(List<string> path, string key)
    {
        var output = new List<string>(path.Count + 1);
        output.AddRange(path);
        output.Add(key);
        return output;
    }

    // GetPath descends store following path. The bool reports whether the leaf
    // was present (false means it ran off a null or a missing key/index).
    private static (object?, bool) GetPath(object? store, List<string> path)
    {
        object? cur = store;
        foreach (string key in path)
        {
            if (cur == null)
            {
                return (null, false);
            }
            if (cur is OrderedMap map)
            {
                if (!map.TryGetValue(key, out object? v))
                {
                    return (null, false);
                }
                cur = v;
            }
            else if (cur is List<object?> list)
            {
                if (!int.TryParse(key, NumberStyles.Integer, CultureInfo.InvariantCulture, out int idx)
                    || idx < 0 || idx >= list.Count)
                {
                    return (null, false);
                }
                cur = list[idx];
            }
            else
            {
                return (null, false);
            }
        }
        return (cur, true);
    }

    // ─── JSON conversion + compact serialization ───────────────────────────

    // Convert a JsonElement tree into native objects. Objects become OrderedMap
    // (document order preserved via EnumerateObject); arrays become
    // List<object?>; numbers become long when integral, else double — so that
    // an integer like 42 prints as "42", not "42.0".
    private static object? Convert(JsonElement el)
    {
        switch (el.ValueKind)
        {
            case JsonValueKind.Object:
            {
                var m = new OrderedMap();
                foreach (JsonProperty p in el.EnumerateObject())
                {
                    m[p.Name] = Convert(p.Value);
                }
                return m;
            }
            case JsonValueKind.Array:
            {
                var list = new List<object?>();
                foreach (JsonElement e in el.EnumerateArray())
                {
                    list.Add(Convert(e));
                }
                return list;
            }
            case JsonValueKind.String:
                return el.GetString();
            case JsonValueKind.Number:
                return el.TryGetInt64(out long l) ? l : el.GetDouble();
            case JsonValueKind.True:
                return true;
            case JsonValueKind.False:
                return false;
            case JsonValueKind.Null:
            default:
                return null;
        }
    }

    // CompactJson serializes a native value tree to compact JSON, mirroring
    // JSON.stringify for the value shapes the corpus produces.
    private static string CompactJson(object? x)
    {
        var sb = new StringBuilder();
        WriteJson(sb, x);
        return sb.ToString();
    }

    private static void WriteJson(StringBuilder sb, object? x)
    {
        switch (x)
        {
            case null:
                sb.Append("null");
                break;
            case bool b:
                sb.Append(b ? "true" : "false");
                break;
            case string s:
                WriteJsonString(sb, s);
                break;
            case long l:
                sb.Append(l.ToString(CultureInfo.InvariantCulture));
                break;
            case int i:
                sb.Append(i.ToString(CultureInfo.InvariantCulture));
                break;
            case double d:
                sb.Append(FormatDouble(d));
                break;
            case float f:
                sb.Append(FormatDouble(f));
                break;
            case OrderedMap map:
            {
                sb.Append('{');
                bool first = true;
                foreach (string k in map.Keys)
                {
                    if (!first)
                    {
                        sb.Append(',');
                    }
                    first = false;
                    WriteJsonString(sb, k);
                    sb.Append(':');
                    WriteJson(sb, map[k]);
                }
                sb.Append('}');
                break;
            }
            case IDictionary dict:
            {
                sb.Append('{');
                bool first = true;
                foreach (DictionaryEntry de in dict)
                {
                    if (!first)
                    {
                        sb.Append(',');
                    }
                    first = false;
                    WriteJsonString(sb, de.Key?.ToString() ?? "");
                    sb.Append(':');
                    WriteJson(sb, de.Value);
                }
                sb.Append('}');
                break;
            }
            case IEnumerable en:
            {
                sb.Append('[');
                bool first = true;
                foreach (object? e in en)
                {
                    if (!first)
                    {
                        sb.Append(',');
                    }
                    first = false;
                    WriteJson(sb, e);
                }
                sb.Append(']');
                break;
            }
            default:
                WriteJsonString(sb, x.ToString() ?? "");
                break;
        }
    }

    private static string FormatDouble(double d)
    {
        // Integral doubles print without a decimal point (JSON.stringify style).
        if (d == Math.Floor(d) && !double.IsInfinity(d))
        {
            return ((long)d).ToString(CultureInfo.InvariantCulture);
        }
        return d.ToString("R", CultureInfo.InvariantCulture);
    }

    private static void WriteJsonString(StringBuilder sb, string s)
    {
        sb.Append('"');
        foreach (char c in s)
        {
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\b': sb.Append("\\b"); break;
                case '\f': sb.Append("\\f"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20)
                    {
                        sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                    }
                    else
                    {
                        sb.Append(c);
                    }
                    break;
            }
        }
        sb.Append('"');
    }
}

// OrderedMap is an insertion-ordered string-keyed map. Dictionary<,> does not
// contractually preserve order; this thin wrapper guarantees corpus property
// order for Functions()/Groups() and faithful structural walks.
public sealed class OrderedMap
{
    private readonly List<string> _keys = new();
    private readonly Dictionary<string, object?> _map = new();

    public IReadOnlyList<string> Keys => _keys;

    public int Count => _keys.Count;

    public object? this[string key]
    {
        get => _map[key];
        set
        {
            if (!_map.ContainsKey(key))
            {
                _keys.Add(key);
            }
            _map[key] = value;
        }
    }

    public bool ContainsKey(string key) => _map.ContainsKey(key);

    public bool TryGetValue(string key, out object? value) => _map.TryGetValue(key, out value);
}
