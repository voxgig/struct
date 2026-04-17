/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

// RUN: cd cs/tests && dotnet test
// RUN-SOME: cd cs/tests && dotnet test --filter "DisplayName~minor-isnode"

using Voxgig.Struct;
using Xunit;

namespace Voxgig.Struct.Tests;


public class StructTests
{
    private readonly Dictionary<string, object?> _spec;
    private readonly Dictionary<string, object?> _minor;

    public StructTests()
    {
        _spec  = Runner.LoadSpec();
        _minor = _spec["minor"] as Dictionary<string, object?> ?? [];
    }


    // ========================================================================
    // minor-exists: verify all expected functions exist
    // ========================================================================

    [Fact]
    public void MinorExists()
    {
        // Verify all expected functions resolve as delegates (callable).
        var checks = new (string name, Delegate fn)[]
        {
            ("isnode",    (Func<object?, bool>)   StructUtils.IsNode),
            ("ismap",     (Func<object?, bool>)   StructUtils.IsMap),
            ("islist",    (Func<object?, bool>)   StructUtils.IsList),
            ("iskey",     (Func<object?, bool>)   StructUtils.IsKey),
            ("isempty",   (Func<object?, bool>)   StructUtils.IsEmpty),
            ("isfunc",    (Func<object?, bool>)   StructUtils.IsFunc),
            ("size",      (Func<object?, int>)    StructUtils.Size),
            ("typify",    (Func<object?, int>)    StructUtils.Typify),
            ("typename",  (Func<int, string>)     StructUtils.TypeName),
            ("strkey",    (Func<object?, string?>) StructUtils.StrKey),
            ("keysof",    (Func<object?, List<string>>) StructUtils.KeysOf),
            ("haskey",    (Func<object?, object?, bool>) StructUtils.HasKey),
            ("getelem",   (Func<object?, object?, object?, object?>) StructUtils.GetElem),
            ("getprop",   (Func<object?, object?, object?, object?>) StructUtils.GetProp),
            ("setprop",   (Func<object?, object?, object?, object?>) StructUtils.SetProp),
            ("delprop",   (Func<object?, object?, object?>)          StructUtils.DelProp),
            ("clone",     (Func<object?, object?>)  StructUtils.Clone),
            ("escre",     (Func<string?, string>)   StructUtils.EscRe),
            ("escurl",    (Func<string?, string>)   StructUtils.EscUrl),
            ("stringify", (Func<object?, int?, string>) StructUtils.Stringify),
        };

        foreach (var (name, fn) in checks)
            Assert.True(fn != null, $"{name} should exist");
    }


    // ========================================================================
    // Minor utility tests (driven from test.json)
    // ========================================================================

    [Fact]
    public void MinorIsNode()
    {
        Runner.RunSet(_minor["isnode"], input =>
            StructUtils.IsNode(input));
    }

    [Fact]
    public void MinorIsMap()
    {
        Runner.RunSet(_minor["ismap"], input =>
            StructUtils.IsMap(input));
    }

    [Fact]
    public void MinorIsList()
    {
        Runner.RunSet(_minor["islist"], input =>
            StructUtils.IsList(input));
    }

    [Fact]
    public void MinorIsKey()
    {
        Runner.RunSet(_minor["iskey"],
            input => StructUtils.IsKey(input),
            flags: new() { ["null"] = false });
    }

    [Fact]
    public void MinorStrKey()
    {
        Runner.RunSet(_minor["strkey"],
            input => StructUtils.StrKey(input),
            flags: new() { ["null"] = false });
    }

    [Fact]
    public void MinorIsEmpty()
    {
        Runner.RunSet(_minor["isempty"],
            input => StructUtils.IsEmpty(input),
            flags: new() { ["null"] = false });
    }

    [Fact]
    public void MinorIsFunc()
    {
        Runner.RunSet(_minor["isfunc"],
            input => StructUtils.IsFunc(input));

        // Edge: actual delegates should be recognised.
        Func<object?> f0 = () => null;
        Assert.True(StructUtils.IsFunc(f0));
        Assert.True(StructUtils.IsFunc((Action)(() => { })));
    }

    [Fact]
    public void MinorClone()
    {
        Runner.RunSet(_minor["clone"],
            input => StructUtils.Clone(input),
            flags: new() { ["null"] = false });

        // Edge: functions should be shallow-copied, not cloned.
        Func<object?> f0 = () => null;
        var src = new Dictionary<string, object?> { ["a"] = f0 };
        var cloned = StructUtils.Clone(src) as Dictionary<string, object?>;
        Assert.NotNull(cloned);
        Assert.Same(f0, cloned["a"]);
    }

    [Fact]
    public void MinorEscRe()
    {
        Runner.RunSet(_minor["escre"],
            input => StructUtils.EscRe(input as string));
    }

    [Fact]
    public void MinorEscUrl()
    {
        Runner.RunSet(_minor["escurl"],
            input => StructUtils.EscUrl(input as string)
                         ?.Replace("+", "%20"));
    }

    [Fact]
    public void MinorStringify()
    {
        Runner.RunSet(_minor["stringify"], input =>
        {
            var m = input as Dictionary<string, object?>;
            if (m == null) return StructUtils.Stringify(input);

            object? val = m.TryGetValue("val", out object? v) ? v : null;
            if (val is string s && s == Runner.NULLMARK) val = "null";

            if (m.TryGetValue("max", out object? maxObj) && maxObj != null)
                return StructUtils.Stringify(val, (int)Convert.ToInt64(maxObj));

            return StructUtils.Stringify(val);
        });
    }

    [Fact]
    public void MinorPathify()
    {
        Runner.RunSet(_minor["pathify"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return StructUtils.Pathify(input);

                // If the "path" key is absent entirely, pass NONE (not null) so
                // Pathify can distinguish "not provided" from "explicitly null".
                bool hasPath = m.ContainsKey("path");
                object? path = hasPath ? m["path"] : StructUtils.NONE;
                if (path is string ps && ps == Runner.NULLMARK) path = null;

                int from = 0;
                if (m.TryGetValue("from", out object? fv) && fv != null)
                    from = (int)Convert.ToInt64(fv);

                string result = StructUtils.Pathify(path, from);

                // Match TS/Go behaviour: replace __NULL__. in path.
                if (hasPath && m["path"] is string origPath && origPath == Runner.NULLMARK)
                    result = result.Replace(">", ":null>");

                result = result.Replace(Runner.NULLMARK + ".", "");
                return result;
            },
            flags: new() { ["null"] = true });
    }

    [Fact]
    public void MinorItems()
    {
        Runner.RunSet(_minor["items"],
            input => StructUtils.Items(input));
    }

    [Fact]
    public void MinorGetProp()
    {
        Runner.RunSet(_minor["getprop"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;
                object? val = m.TryGetValue("val", out object? v) ? v : null;
                object? key = m.TryGetValue("key", out object? k) ? k : null;
                if (m.TryGetValue("alt", out object? alt) && alt != null)
                    return StructUtils.GetProp(val, key, alt);
                return StructUtils.GetProp(val, key);
            },
            flags: new() { ["null"] = false });
    }

    [Fact]
    public void MinorEdgeGetProp()
    {
        // String arrays.
        var strarr = new List<object?> { "a", "b", "c", "d", "e" };
        Assert.Equal("c", StructUtils.GetProp(strarr, 2));
        Assert.Equal("c", StructUtils.GetProp(strarr, "2"));
    }

    [Fact]
    public void MinorGetElem()
    {
        Runner.RunSet(_minor["getelem"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;
                object? val = m.TryGetValue("val", out object? v) ? v : null;
                object? key = m.TryGetValue("key", out object? k) ? k : null;
                if (m.TryGetValue("alt", out object? alt) && alt != null)
                    return StructUtils.GetElem(val, key, alt);
                return StructUtils.GetElem(val, key);
            },
            flags: new() { ["null"] = false });
    }

    [Fact]
    public void MinorSetProp()
    {
        Runner.RunSet(_minor["setprop"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;
                object? parent = m.TryGetValue("parent", out object? pv) ? pv : null;
                object? key    = m.TryGetValue("key",    out object? kv) ? kv : null;
                object? val    = m.TryGetValue("val",    out object? vv) ? vv : null;
                return StructUtils.SetProp(parent, key, val);
            },
            flags: new() { ["null"] = true });
    }

    [Fact]
    public void MinorEdgeSetProp()
    {
        var strarr0 = new List<object?> { "a", "b", "c", "d", "e" };
        var strarr1 = new List<object?> { "a", "b", "c", "d", "e" };
        Assert.True(Runner.DeepEqual(
            new List<object?> { "a", "b", "C", "d", "e" },
            StructUtils.SetProp(strarr0, 2, "C")));
        Assert.True(Runner.DeepEqual(
            new List<object?> { "a", "b", "CC", "d", "e" },
            StructUtils.SetProp(strarr1, "2", "CC")));
    }

    [Fact]
    public void MinorDelProp()
    {
        Runner.RunSet(_minor["delprop"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;
                object? parent = m.TryGetValue("parent", out object? pv) ? pv : null;
                object? key    = m.TryGetValue("key",    out object? kv) ? kv : null;
                return StructUtils.DelProp(parent, key);
            },
            flags: new() { ["null"] = true });
    }

    [Fact]
    public void MinorKeysOf()
    {
        Runner.RunSet(_minor["keysof"],
            input => StructUtils.KeysOf(input));
    }

    [Fact]
    public void MinorHasKey()
    {
        Runner.RunSet(_minor["haskey"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return false;
                object? val = m.TryGetValue("src", out object? v) ? v : null;
                object? key = m.TryGetValue("key", out object? k) ? k : null;
                return StructUtils.HasKey(val, key);
            });
    }

    [Fact]
    public void MinorStringifyEdge()
    {
        // Basic edge cases beyond what the JSON spec covers.
        Assert.Equal("1",      StructUtils.Stringify(1));
        Assert.Equal("true",   StructUtils.Stringify(true));
        Assert.Equal("hello",  StructUtils.Stringify("hello"));
        Assert.Equal(S_MT,     StructUtils.Stringify(null));
    }

    private const string S_MT = "";

    [Fact]
    public void MinorTypify()
    {
        Runner.RunSet(_minor["typify"],
            input => StructUtils.Typify(input));
    }

    [Fact]
    public void MinorTypeName()
    {
        Runner.RunSet(_minor["typename"],
            input => StructUtils.TypeName((int)Convert.ToInt64(input)));
    }

    [Fact]
    public void MinorSize()
    {
        Runner.RunSet(_minor["size"],
            input => StructUtils.Size(input));
    }

    [Fact]
    public void MinorSlice()
    {
        Runner.RunSet(_minor["slice"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return StructUtils.Slice(input);

                object? val   = m.TryGetValue("val",   out object? v) ? v : null;
                int? start = m.TryGetValue("start", out object? sv) && sv != null
                    ? (int?)Convert.ToInt32(sv) : null;
                int? end   = m.TryGetValue("end",   out object? ev) && ev != null
                    ? (int?)Convert.ToInt32(ev) : null;
                return StructUtils.Slice(val, start, end);
            });
    }

    [Fact]
    public void MinorFlatten()
    {
        Runner.RunSet(_minor["flatten"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return StructUtils.Flatten(input as List<object?> ?? []);
                var val   = m.TryGetValue("val",   out object? v) ? v as List<object?> : null;
                int depth = m.TryGetValue("depth", out object? d) && d != null
                    ? (int)Convert.ToInt64(d) : 1;
                return StructUtils.Flatten(val ?? [], depth);
            });
    }

    // Named filter predicates used in test.json.
    private static readonly Dictionary<string, Func<List<object?>, bool>> FilterChecks = new()
    {
        ["gt3"] = n => Runner.IsNumericValue(n[1]) && Runner.ToDoubleVal(n[1]) > 3,
        ["lt3"] = n => Runner.IsNumericValue(n[1]) && Runner.ToDoubleVal(n[1]) < 3,
    };

    [Fact]
    public void MinorFilter()
    {
        Runner.RunSet(_minor["filter"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;
                object? val  = m.TryGetValue("val",   out object? v) ? v : null;
                string? chk  = m.TryGetValue("check", out object? c) ? c as string : null;
                if (chk != null && FilterChecks.TryGetValue(chk, out var check))
                    return StructUtils.Filter(val, check);
                return StructUtils.Filter(val, n => n[1] is string s && s.Length > 0);
            });
    }

    [Fact]
    public void MinorPad()
    {
        Runner.RunSet(_minor["pad"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return StructUtils.Pad(input);
                object? str     = m.TryGetValue("val",    out object? sv) ? sv : null;
                object? padding = m.TryGetValue("pad",    out object? pv) ? pv : null;
                // spec uses "char" as key for the pad character
                object? padchar = m.TryGetValue("char",   out object? cv) ? cv
                    : m.TryGetValue("padchar", out object? cv2) ? cv2 : null;

                int pad = padding != null ? (int)Convert.ToInt64(padding) : 44;
                string? pc = padchar as string;
                return StructUtils.Pad(str, pad, pc);
            });
    }

    [Fact]
    public void MinorJoin()
    {
        Runner.RunSet(_minor["join"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return StructUtils.Join([input]);
                object? arr = m.TryGetValue("val", out object? av) ? av : null;
                object? sep = m.TryGetValue("sep", out object? sv) ? sv : null;
                bool url = m.TryGetValue("url", out object? uv) && uv is bool b && b;
                return StructUtils.Join(arr as List<object?> ?? [], sep as string, url);
            });
    }

    // ========================================================================
    // Walk tests
    // ========================================================================

    [Fact]
    public void WalkBasic()
    {
        // subject: Walk(val, walkpath) where walkpath appends "~path.join('.')"
        WalkApply walkpath = (key, val, parent, path) =>
        {
            if (val is string s)
                return s + "~" + string.Join(".", path.Cast<string>());
            return val;
        };

        Runner.RunSet(_spec["walk"] is Dictionary<string, object?> ws ? ws["basic"] : null,
            input => StructUtils.Walk(input, walkpath));
    }

    [Fact]
    public void WalkLog()
    {
        var walkSpec = _spec["walk"] as Dictionary<string, object?>;
        var logSpec  = walkSpec?["log"] as Dictionary<string, object?>;
        if (logSpec == null) return;

        var testIn  = StructUtils.Clone(logSpec["in"]);
        var outSpec = logSpec["out"] as Dictionary<string, object?>;

        WalkApply makeWalkLog(List<object?> log)
        {
            return (key, val, parent, path) =>
            {
                string ks = key is string sk ? sk : "";
                string entry =
                    "k=" + StructUtils.Stringify(ks) +
                    ", v=" + StructUtils.Stringify(val) +
                    ", p=" + StructUtils.Stringify(parent) +
                    ", t=" + StructUtils.Pathify(path);
                log.Add(entry);
                return val;
            };
        }

        // Test after (post-order).
        var logAfter = new List<object?>();
        StructUtils.Walk(testIn, null, makeWalkLog(logAfter));
        Assert.True(Runner.DeepEqual(outSpec?["after"], logAfter),
            $"walk-log after:\n  got:  {StructUtils.Stringify(logAfter)}\n  want: {StructUtils.Stringify(outSpec?["after"])}");

        // Test before (pre-order).
        var logBefore = new List<object?>();
        StructUtils.Walk(testIn, makeWalkLog(logBefore));
        Assert.True(Runner.DeepEqual(outSpec?["before"], logBefore),
            $"walk-log before:\n  got:  {StructUtils.Stringify(logBefore)}\n  want: {StructUtils.Stringify(outSpec?["before"])}");

        // Test both.
        var logBoth = new List<object?>();
        var bothCb = makeWalkLog(logBoth);
        StructUtils.Walk(testIn, bothCb, bothCb);
        Assert.True(Runner.DeepEqual(outSpec?["both"], logBoth),
            $"walk-log both:\n  got:  {StructUtils.Stringify(logBoth)}\n  want: {StructUtils.Stringify(outSpec?["both"])}");
    }

    [Fact]
    public void WalkDepth()
    {
        var walkSpec = _spec["walk"] as Dictionary<string, object?>;
        Runner.RunSet(walkSpec?["depth"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;

                object? src = m.TryGetValue("src", out object? sv) ? sv : null;
                int? md = m.TryGetValue("maxdepth", out object? dv) && dv != null
                    ? (int?)Convert.ToInt32(dv) : null;

                // Build a copy using a single current-node pointer (matches Go walk-depth test).
                object? top = null;
                object? cur = null;

                WalkApply copy = (key, val, parent, path) =>
                {
                    if (StructUtils.IsNode(val))
                    {
                        object? child = StructUtils.IsList(val)
                            ? (object?)new List<object?>()
                            : new Dictionary<string, object?>();
                        if (key == null) { top = child; cur = child; }
                        else { StructUtils.SetProp(cur, key, child); cur = child; }
                    }
                    else if (key != null)
                        StructUtils.SetProp(cur, key, val);
                    return val;
                };

                StructUtils.Walk(src, copy, null, md);
                return top;
            },
            flags: new() { ["null"] = false });
    }

    [Fact]
    public void WalkCopy()
    {
        var walkSpec = _spec["walk"] as Dictionary<string, object?>;
        Runner.RunSet(walkSpec?["copy"],
            input =>
            {
                var cur = new object?[MAXDEPTH + 1];

                WalkApply walkcopy = (key, val, parent, path) =>
                {
                    if (key == null) // root
                    {
                        cur[0] = StructUtils.IsMap(val)
                            ? (object?)new Dictionary<string, object?>()
                            : StructUtils.IsList(val)
                                ? new List<object?>()
                                : val;
                        return val;
                    }

                    int i = path.Count;
                    object? v = val;

                    if (StructUtils.IsNode(val))
                    {
                        cur[i] = StructUtils.IsMap(val)
                            ? (object?)new Dictionary<string, object?>()
                            : new List<object?>();
                        v = cur[i];
                    }

                    cur[i - 1] = StructUtils.SetProp(cur[i - 1], key, v) ?? cur[i - 1];
                    return val;
                };

                StructUtils.Walk(input, walkcopy);
                return cur[0];
            });
    }

    private const int MAXDEPTH = StructUtils.MAXDEPTH;


    // ========================================================================
    // Merge tests
    // ========================================================================

    [Fact]
    public void MergeBasic()
    {
        var mergeSpec = _spec["merge"] as Dictionary<string, object?>;
        var basic = mergeSpec?["basic"] as Dictionary<string, object?>;
        if (basic == null) return;

        object? result = StructUtils.Merge(basic["in"]);
        Assert.True(Runner.DeepEqual(basic["out"], result),
            $"merge-basic: expected {StructUtils.Stringify(basic["out"])} but got {StructUtils.Stringify(result)}");
    }

    [Fact]
    public void MergeCases()
    {
        var mergeSpec = _spec["merge"] as Dictionary<string, object?>;
        Runner.RunSet(mergeSpec?["cases"],
            input => StructUtils.Merge(input));
    }

    [Fact]
    public void MergeArray()
    {
        var mergeSpec = _spec["merge"] as Dictionary<string, object?>;
        Runner.RunSet(mergeSpec?["array"],
            input => StructUtils.Merge(input));
    }

    [Fact]
    public void MergeIntegrity()
    {
        var mergeSpec = _spec["merge"] as Dictionary<string, object?>;
        Runner.RunSet(mergeSpec?["integrity"],
            input => StructUtils.Merge(input));
    }

    [Fact]
    public void MergeDepth()
    {
        var mergeSpec = _spec["merge"] as Dictionary<string, object?>;
        Runner.RunSet(mergeSpec?["depth"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return StructUtils.Merge(input);

                object? val = m.TryGetValue("val", out object? v) ? v : null;
                int? depth = m.TryGetValue("depth", out object? d) && d != null
                    ? (int?)Convert.ToInt32(d) : null;
                return StructUtils.Merge(val, depth);
            });
    }

    [Fact]
    public void MergeSpecial()
    {
        // Functions should survive merge as shallow copies.
        Func<int> f0 = () => 11;

        var r0 = StructUtils.Merge(new List<object?> { f0 }) as Func<int>;
        Assert.NotNull(r0);
        Assert.Equal(f0(), r0!());

        var r1 = StructUtils.Merge(new List<object?> { null, f0 }) as Func<int>;
        Assert.NotNull(r1);
        Assert.Equal(f0(), r1!());

        var r2 = StructUtils.Merge(new List<object?> {
            new Dictionary<string, object?> { ["a"] = f0 }
        }) as Dictionary<string, object?>;
        Assert.NotNull(r2);
        var fr2 = r2!["a"] as Func<int>;
        Assert.NotNull(fr2);
        Assert.Equal(f0(), fr2!());
    }

    [Fact]
    public void MinorSetPath()
    {
        Runner.RunSet(_minor["setpath"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;
                object? store = m.TryGetValue("store", out object? sv) ? sv : null;
                object? path  = m.TryGetValue("path",  out object? pv) ? pv : null;
                object? val   = m.TryGetValue("val",   out object? vv) ? vv : null;
                return StructUtils.SetPath(store, path, val);
            },
            flags: new() { ["null"] = true });
    }


    // ========================================================================
    // GetPath tests
    // ========================================================================

    // ========================================================================
    // Inject tests
    // ========================================================================

    [Fact]
    public void InjectExists()
    {
        Delegate fn = (Func<object?, object?, InjectState?, object?>)StructUtils.Inject;
        Assert.NotNull(fn);
    }

    [Fact]
    public void InjectBasic()
    {
        var injectSpec = _spec["inject"] as Dictionary<string, object?>;
        var basic = injectSpec?["basic"] as Dictionary<string, object?>;
        if (basic == null) return;

        var inVal = basic["in"] as Dictionary<string, object?>;
        if (inVal == null) return;
        object? val   = inVal.TryGetValue("val",   out object? v) ? v : null;
        object? store = inVal.TryGetValue("store", out object? s) ? s : null;
        object? expected = basic["out"];

        object? result = StructUtils.Inject(val, store);
        Assert.True(Runner.DeepEqual(expected, result),
            $"inject-basic: expected {StructUtils.Stringify(expected)} but got {StructUtils.Stringify(result)}");
    }

    [Fact]
    public void InjectString()
    {
        var injectSpec = _spec["inject"] as Dictionary<string, object?>;
        Runner.RunSet(injectSpec?["string"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;
                object? val   = m.TryGetValue("val",   out object? v) ? v : null;
                object? store = m.TryGetValue("store", out object? s) ? s : null;
                return StructUtils.Inject(val, store);
            },
            flags: new() { ["null"] = true });
    }

    [Fact]
    public void InjectDeep()
    {
        var injectSpec = _spec["inject"] as Dictionary<string, object?>;
        Runner.RunSet(injectSpec?["deep"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;
                object? val   = m.TryGetValue("val",   out object? v) ? v : null;
                object? store = m.TryGetValue("store", out object? s) ? s : null;
                return StructUtils.Inject(val, store);
            });
    }


    // ========================================================================
    // Transform tests
    // ========================================================================

    [Fact]
    public void TransformExists()
    {
        Delegate fn = (Func<object?, object?, InjectState?, object?>)StructUtils.Transform;
        Assert.NotNull(fn);
    }

    [Fact]
    public void TransformBasic()
    {
        var tSpec = _spec["transform"] as Dictionary<string, object?>;
        var basic = tSpec?["basic"] as Dictionary<string, object?>;
        if (basic == null) return;

        var inVal    = basic["in"] as Dictionary<string, object?>;
        if (inVal == null) return;
        object? data = inVal.TryGetValue("data", out object? d) ? d : null;
        object? spec = inVal.TryGetValue("spec", out object? s) ? s : null;
        object? expected = basic["out"];

        object? result = StructUtils.Transform(data, spec);
        Assert.True(Runner.DeepEqual(expected, result),
            $"transform-basic: expected {StructUtils.Stringify(expected)} " +
            $"but got {StructUtils.Stringify(result)}");
    }

    [Fact]
    public void TransformPaths()
    {
        var tSpec = _spec["transform"] as Dictionary<string, object?>;
        Runner.RunSet(tSpec?["paths"], input =>
        {
            var m = input as Dictionary<string, object?>;
            if (m == null) return null;
            object? data = m.TryGetValue("data", out object? d) ? d : null;
            object? spec = m.TryGetValue("spec", out object? s) ? s : null;
            return StructUtils.Transform(data, spec);
        });
    }

    [Fact]
    public void TransformCmds()
    {
        var tSpec = _spec["transform"] as Dictionary<string, object?>;
        Runner.RunSet(tSpec?["cmds"], input =>
        {
            var m = input as Dictionary<string, object?>;
            if (m == null) return null;
            object? data = m.TryGetValue("data", out object? d) ? d : null;
            object? spec = m.TryGetValue("spec", out object? s) ? s : null;
            return StructUtils.Transform(data, spec);
        });
    }

    [Fact]
    public void TransformEach()
    {
        var tSpec = _spec["transform"] as Dictionary<string, object?>;
        Runner.RunSet(tSpec?["each"], input =>
        {
            var m = input as Dictionary<string, object?>;
            if (m == null) return null;
            object? data = m.TryGetValue("data", out object? d) ? d : null;
            object? spec = m.TryGetValue("spec", out object? s) ? s : null;
            return StructUtils.Transform(data, spec);
        });
    }

    [Fact]
    public void TransformPack()
    {
        var tSpec = _spec["transform"] as Dictionary<string, object?>;
        Runner.RunSet(tSpec?["pack"], input =>
        {
            var m = input as Dictionary<string, object?>;
            if (m == null) return null;
            object? data = m.TryGetValue("data", out object? d) ? d : null;
            object? spec = m.TryGetValue("spec", out object? s) ? s : null;
            return StructUtils.Transform(data, spec);
        });
    }

    [Fact]
    public void TransformRef()
    {
        var tSpec = _spec["transform"] as Dictionary<string, object?>;
        Runner.RunSet(tSpec?["ref"], input =>
        {
            var m = input as Dictionary<string, object?>;
            if (m == null) return null;
            object? data = m.TryGetValue("data", out object? d) ? d : null;
            object? spec = m.TryGetValue("spec", out object? s) ? s : null;
            return StructUtils.Transform(data, spec);
        });
    }

    [Fact]
    public void TransformFormat()
    {
        var tSpec = _spec["transform"] as Dictionary<string, object?>;
        Runner.RunSet(tSpec?["format"], input =>
        {
            var m = input as Dictionary<string, object?>;
            if (m == null) return null;
            object? data = m.TryGetValue("data", out object? d) ? d : null;
            object? spec = m.TryGetValue("spec", out object? s) ? s : null;
            return StructUtils.Transform(data, spec);
        }, flags: new() { ["null"] = true });
    }

    [Fact]
    public void TransformModify()
    {
        var tSpec  = _spec["transform"] as Dictionary<string, object?>;
        var modSet = tSpec?["modify"] as Dictionary<string, object?>;
        if (modSet == null) return;

        var set = modSet.TryGetValue("set", out object? sv) ? sv as List<object?> : null;
        if (set == null || set.Count == 0) return;

        var entry = set[0] as Dictionary<string, object?>;
        if (entry == null || !entry.ContainsKey("out")) return;

        var inVal = entry["in"] as Dictionary<string, object?>;
        if (inVal == null) return;

        object? data     = inVal.TryGetValue("data", out object? d) ? d : null;
        object? spec     = inVal.TryGetValue("spec", out object? s) ? s : null;
        object? expected = entry["out"];

        // Modify callback that prefixes every injected string value with "@".
        Modify myModify = (val, key, parent, inj, store) =>
        {
            if (val is string sv2 && sv2.Length > 0)
                StructUtils.SetProp(parent, key, "@" + sv2);
            return val;
        };

        var injState = new InjectState { ModifyFn = myModify };
        object? result = StructUtils.Transform(data, spec, injState);

        Assert.True(Runner.DeepEqual(expected, result),
            $"transform-modify: expected {StructUtils.Stringify(expected)} " +
            $"but got {StructUtils.Stringify(result)}");
    }

    // ========================================================================
    // GetPath tests
    // ========================================================================

    [Fact]
    public void GetpathExists()
    {
        Delegate fn = (Func<object?, object?, object?, InjectState?, object?>)StructUtils.GetPath;
        Assert.NotNull(fn);
    }

    [Fact]
    public void GetpathBasic()
    {
        var getpathSpec = _spec["getpath"] as Dictionary<string, object?>;
        Runner.RunSet(getpathSpec?["basic"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;
                object? path  = m.TryGetValue("path",  out object? pv) ? pv : null;
                object? store = m.TryGetValue("store", out object? sv) ? sv : null;
                return StructUtils.GetPath(path, store);
            });
    }

    [Fact]
    public void GetpathRelative()
    {
        var getpathSpec = _spec["getpath"] as Dictionary<string, object?>;
        Runner.RunSet(getpathSpec?["relative"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;
                object? path    = m.TryGetValue("path",    out object? pv) ? pv : null;
                object? store   = m.TryGetValue("store",   out object? sv) ? sv : null;
                object? dparent = m.TryGetValue("dparent", out object? dv) ? dv : null;

                var state = new InjectState { DParent = dparent };

                if (m.TryGetValue("dpath", out object? dpv) && dpv is string dpathStr && dpathStr.Length > 0)
                    state.DPath = dpathStr.Split('.').Cast<object?>().ToList();

                return StructUtils.GetPath(path, store, null, state);
            });
    }

    [Fact]
    public void GetpathSpecial()
    {
        var getpathSpec = _spec["getpath"] as Dictionary<string, object?>;
        Runner.RunSet(getpathSpec?["special"],
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;
                object? path  = m.TryGetValue("path",  out object? pv) ? pv : null;
                object? store = m.TryGetValue("store", out object? sv) ? sv : null;

                InjectState? state = null;
                if (m.TryGetValue("inj", out object? injv) && injv is Dictionary<string, object?> injMap)
                {
                    state = new InjectState();
                    if (injMap.TryGetValue("key", out object? kv) && kv != null)
                        state.Key = StructUtils.Stringify(kv);
                    if (injMap.TryGetValue("meta", out object? mv) && mv is Dictionary<string, object?> metaMap)
                        state.Meta = metaMap;
                }

                return StructUtils.GetPath(path, store, null, state);
            });
    }

    [Fact]
    public void GetpathHandler()
    {
        var getpathSpec = _spec["getpath"] as Dictionary<string, object?>;
        var handlerSpec = getpathSpec?["handler"] as Dictionary<string, object?>;
        if (handlerSpec == null) return;

        // Handler that turns any ref lookup into "<ref>" (e.g. "$FOO" → "foo").
        var refMap = new Dictionary<string, object?> { ["$FOO"] = "foo" };

        var state = new InjectState
        {
            Handler = (inj, val, refStr, st) =>
                refStr != null && refMap.TryGetValue(refStr, out object? mapped) ? mapped : val,
        };

        Runner.RunSet(handlerSpec,
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;
                object? path  = m.TryGetValue("path",  out object? pv) ? pv : null;
                object? store = m.TryGetValue("store", out object? sv) ? sv : null;
                return StructUtils.GetPath(path, store, null, state);
            });
    }

    // ── minor.jsonify ────────────────────────────────────────────────────────

    [Fact]
    public void MinorJsonify()
    {
        var jsonifySpec = _minor["jsonify"] as Dictionary<string, object?>;
        Runner.RunSet(jsonifySpec,
            input =>
            {
                var m = input as Dictionary<string, object?>;
                if (m == null) return null;
                object? val = m.TryGetValue("val", out object? vv) ? vv : null;
                if (m.TryGetValue("flags", out object? fv) && fv is Dictionary<string, object?> flags)
                {
                    int indent = flags.TryGetValue("indent", out object? iv) && iv is long li ? (int)li : 2;
                    int offset = flags.TryGetValue("offset", out object? ov) && ov is long lo ? (int)lo : 0;
                    return StructUtils.Jsonify(val, indent, offset);
                }
                return StructUtils.Jsonify(val);
            }, new() { ["null"] = true });
    }

    // ── transform.apply ──────────────────────────────────────────────────────

    [Fact]
    public void TransformApply()
    {
        var applySpec = (_spec["transform"] as Dictionary<string,object?>)?["apply"] as Dictionary<string, object?>;
        Runner.RunSetFull(applySpec,
            input =>
            {
                object? data = input?.GetValueOrDefault("data");
                object? spec = input?.GetValueOrDefault("spec");
                return StructUtils.Transform(data, spec);
            }, new() { ["null"] = true });
    }

    // ── validate ─────────────────────────────────────────────────────────────

    [Fact]
    public void ValidateExists()
    {
        Assert.NotNull((object)(StructUtils.Validate));
    }

    [Fact]
    public void ValidateBasic()
    {
        var validateSpec = (_spec["validate"] as Dictionary<string,object?>)?["basic"] as Dictionary<string, object?>;
        Runner.RunSetFull(validateSpec, input =>
        {
            object? data = input?.GetValueOrDefault("data");
            object? spec = input?.GetValueOrDefault("spec");
            return StructUtils.Validate(data, spec);
        }, new() { ["null"] = true });
    }

    [Fact]
    public void ValidateChild()
    {
        var validateSpec = (_spec["validate"] as Dictionary<string,object?>)?["child"] as Dictionary<string, object?>;
        Runner.RunSetFull(validateSpec, input =>
        {
            object? data = input?.GetValueOrDefault("data");
            object? spec = input?.GetValueOrDefault("spec");
            return StructUtils.Validate(data, spec);
        }, new() { ["null"] = true });
    }

    [Fact]
    public void ValidateOne()
    {
        var validateSpec = (_spec["validate"] as Dictionary<string,object?>)?["one"] as Dictionary<string, object?>;
        Runner.RunSetFull(validateSpec, input =>
        {
            object? data = input?.GetValueOrDefault("data");
            object? spec = input?.GetValueOrDefault("spec");
            return StructUtils.Validate(data, spec);
        }, new() { ["null"] = true });
    }

    [Fact]
    public void ValidateExact()
    {
        var validateSpec = (_spec["validate"] as Dictionary<string,object?>)?["exact"] as Dictionary<string, object?>;
        Runner.RunSetFull(validateSpec, input =>
        {
            object? data = input?.GetValueOrDefault("data");
            object? spec = input?.GetValueOrDefault("spec");
            return StructUtils.Validate(data, spec);
        }, new() { ["null"] = true });
    }

    [Fact]
    public void ValidateInvalid()
    {
        var validateSpec = (_spec["validate"] as Dictionary<string,object?>)?["invalid"] as Dictionary<string, object?>;
        Runner.RunSetFull(validateSpec, input =>
        {
            object? data = input?.GetValueOrDefault("data");
            object? spec = input?.GetValueOrDefault("spec");
            return StructUtils.Validate(data, spec);
        }, new() { ["null"] = true });
    }

    [Fact]
    public void ValidateSpecial()
    {
        var validateSpec = (_spec["validate"] as Dictionary<string,object?>)?["special"] as Dictionary<string, object?>;
        Runner.RunSetFull(validateSpec, input =>
        {
            object? data = input?.GetValueOrDefault("data");
            object? spec = input?.GetValueOrDefault("spec");
            var injEntry = input?.GetValueOrDefault("inj") as Dictionary<string, object?>;
            var injdef   = new InjectState();
            if (injEntry != null)
            {
                var meta = injEntry.GetValueOrDefault("meta") as Dictionary<string, object?>;
                if (meta != null) injdef.Meta = meta;
            }
            return StructUtils.Validate(data, spec, injdef);
        }, new() { ["null"] = true });
    }

    // ── select ───────────────────────────────────────────────────────────────

    [Fact]
    public void SelectExists()
    {
        Assert.NotNull((object)(StructUtils.Select));
    }

    [Fact]
    public void SelectBasic()
    {
        var selectSpec = (_spec["select"] as Dictionary<string,object?>)?["basic"] as Dictionary<string, object?>;
        Runner.RunSet(selectSpec,
            input =>
            {
                var m = input as Dictionary<string, object?>;
                object? query = m?.GetValueOrDefault("query");
                object? obj   = m?.GetValueOrDefault("obj");
                return (object?)StructUtils.Select(obj, query);
            }, new() { ["null"] = true });
    }

    [Fact]
    public void SelectOperators()
    {
        var selectSpec = (_spec["select"] as Dictionary<string,object?>)?["operators"] as Dictionary<string, object?>;
        Runner.RunSet(selectSpec,
            input =>
            {
                var m = input as Dictionary<string, object?>;
                object? query = m?.GetValueOrDefault("query");
                object? obj   = m?.GetValueOrDefault("obj");
                return (object?)StructUtils.Select(obj, query);
            }, new() { ["null"] = true });
    }

    [Fact]
    public void SelectEdge()
    {
        var selectSpec = (_spec["select"] as Dictionary<string,object?>)?["edge"] as Dictionary<string, object?>;
        Runner.RunSet(selectSpec,
            input =>
            {
                var m = input as Dictionary<string, object?>;
                object? query = m?.GetValueOrDefault("query");
                object? obj   = m?.GetValueOrDefault("obj");
                return (object?)StructUtils.Select(obj, query);
            }, new() { ["null"] = true });
    }

    [Fact]
    public void SelectAlts()
    {
        var selectSpec = (_spec["select"] as Dictionary<string,object?>)?["alts"] as Dictionary<string, object?>;
        Runner.RunSet(selectSpec,
            input =>
            {
                var m = input as Dictionary<string, object?>;
                object? query = m?.GetValueOrDefault("query");
                object? obj   = m?.GetValueOrDefault("obj");
                return (object?)StructUtils.Select(obj, query);
            }, new() { ["null"] = true });
    }
}
