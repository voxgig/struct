/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

// Non-failing corpus scoreboard. Drives every (category, name) pair in
// build/test/test.json against the C# port, counts pass/fail per spec,
// and prints a per-.jsonic-file summary plus a totals line. Mirrors
// java/src/test/StructCorpusTest.java and cpp/tests/struct_corpus_test.cpp.

using System.Text;
using System.Text.Json;
using Voxgig.Struct;
using Xunit;
using Xunit.Abstractions;

namespace Voxgig.Struct.Tests;


public class CorpusScoreboard
{
    private readonly ITestOutputHelper _out;
    private readonly Dictionary<string, object?> _spec;

    public CorpusScoreboard(ITestOutputHelper output)
    {
        _out = output;
        _spec = Runner.LoadSpec();
    }

    private static readonly Dictionary<string, string> CategoryToFile = new()
    {
        { "minor",     "minor.jsonic" },
        { "walk",      "walk.jsonic" },
        { "merge",     "merge.jsonic" },
        { "getpath",   "getpath.jsonic" },
        { "inject",    "inject.jsonic" },
        { "transform", "transform.jsonic" },
        { "validate",  "validate.jsonic" },
        { "select",    "select.jsonic" },
    };

    public class Result
    {
        public string Name = "";
        public int Passed;
        public int Total;
        public List<string> Failures = new();
    }

    private readonly SortedDictionary<string, Result> _scoreboard = new();

    private static object? Get(object? src, string key)
    {
        if (src is Dictionary<string, object?> m && m.TryGetValue(key, out object? v)) return v;
        return null;
    }

    private object? GetCat(string cat, string name)
    {
        var c = _spec.TryGetValue(cat, out object? v) ? v as Dictionary<string, object?> : null;
        if (c == null) return null;
        return c.TryGetValue(name, out object? v2) ? v2 : null;
    }

    // Non-failing variant of Runner.RunSet — counts pass/fail per entry,
    // captures the first few failure messages.
    private void Run(string cat, string name, bool nullFlag, Func<object?, object?> subject)
    {
        var spec = GetCat(cat, name) as Dictionary<string, object?>;
        var key = $"{cat}.{name}";
        var r = new Result { Name = key };
        _scoreboard[key] = r;
        if (spec == null) return;
        var set = spec.TryGetValue("set", out object? sv) ? sv as List<object?> : null;
        if (set == null) return;

        for (int i = 0; i < set.Count; i++)
        {
            var entry = set[i] as Dictionary<string, object?>;
            if (entry == null) continue;
            r.Total++;

            // "in" absent -> StructUtils.NONE (sentinel matching TS undefined).
            // "in" present and null -> Java null (JSON null).
            bool hasIn = entry.ContainsKey("in");
            object? rawInput = hasIn ? entry["in"] : StructUtils.NONE;
            object? input = hasIn ? Runner.FixJson(rawInput, nullFlag) : StructUtils.NONE;

            bool hasOut = entry.ContainsKey("out");
            bool hasErr = entry.ContainsKey("err");
            object? expected = hasOut ? entry["out"] : null;
            expected = Runner.FixJson(expected, nullFlag);

            object? got = null;
            string? thrownMsg = null;
            try { got = subject(input); }
            catch (Exception ex) { thrownMsg = ex.Message; }

            if (hasErr)
            {
                if (thrownMsg != null)
                {
                    string es = entry["err"]?.ToString() ?? "";
                    bool match = es.Length == 0 || thrownMsg.Contains(es) ||
                                 thrownMsg.ToLowerInvariant().Contains(es.ToLowerInvariant());
                    if (match) r.Passed++;
                    else r.Failures.Add(
                        $"[{i}] err mismatch: expected '{Brief(es)}' got '{thrownMsg}'");
                }
                else
                {
                    r.Failures.Add(
                        $"[{i}] expected err but got {Brief(got)}");
                }
                continue;
            }

            if (thrownMsg != null)
            {
                r.Failures.Add($"[{i}] in={Brief(rawInput)} threw={thrownMsg}");
                continue;
            }

            got = Runner.FixJson(got, nullFlag);
            if (Runner.DeepEqual(expected, got)) r.Passed++;
            else r.Failures.Add(
                $"[{i}] in={Brief(rawInput)} expected={Brief(expected)} got={Brief(got)}");
        }
    }

    private static string Brief(object? v)
    {
        if (v == null) return "null";
        try
        {
            var json = JsonSerializer.Serialize(v);
            if (json.Length > 200) json = json.Substring(0, 197) + "...";
            return json;
        }
        catch { return v?.ToString() ?? "null"; }
    }

    private static int? OptInt(object? v) => v switch
    {
        long l => (int)l,
        int i => i,
        _ => null,
    };

    [Fact]
    public void Scoreboard()
    {
        // ===== minor =====
        Run("minor", "isnode",  true,  in_ => StructUtils.IsNode(in_));
        Run("minor", "ismap",   true,  in_ => StructUtils.IsMap(in_));
        Run("minor", "islist",  true,  in_ => StructUtils.IsList(in_));
        Run("minor", "iskey",   false, in_ => StructUtils.IsKey(in_));
        Run("minor", "strkey",  false, in_ => StructUtils.StrKey(in_));
        Run("minor", "isempty", false, in_ => StructUtils.IsEmpty(in_));
        Run("minor", "isfunc",  true,  in_ => StructUtils.IsFunc(in_));
        Run("minor", "getprop", true,  in_ =>
        {
            var m = in_ as Dictionary<string, object?>;
            if (m == null) return null;
            object? alt = m.TryGetValue("alt", out object? a) ? a : null;
            return m.ContainsKey("alt")
                ? StructUtils.GetProp(Get(in_, "val"), Get(in_, "key"), alt)
                : StructUtils.GetProp(Get(in_, "val"), Get(in_, "key"));
        });
        Run("minor", "getelem", true,  in_ =>
        {
            var m = in_ as Dictionary<string, object?>;
            if (m == null) return null;
            object? alt = m.TryGetValue("alt", out object? a) ? a : null;
            return m.ContainsKey("alt")
                ? StructUtils.GetElem(Get(in_, "val"), Get(in_, "key"), alt)
                : StructUtils.GetElem(Get(in_, "val"), Get(in_, "key"));
        });
        Run("minor", "clone",   false, in_ => StructUtils.Clone(in_));
        Run("minor", "items",   true,  in_ => StructUtils.Items(in_));
        Run("minor", "keysof",  true,  in_ => StructUtils.KeysOf(in_));
        Run("minor", "haskey",  true,  in_ => StructUtils.HasKey(Get(in_, "src"), Get(in_, "key")));
        Run("minor", "setprop", true,  in_ =>
            StructUtils.SetProp(Get(in_, "parent"), Get(in_, "key"), Get(in_, "val")));
        Run("minor", "delprop", true,  in_ =>
            StructUtils.DelProp(Get(in_, "parent"), Get(in_, "key")));
        Run("minor", "stringify", true, in_ =>
        {
            var m = in_ as Dictionary<string, object?>;
            object? val = (m != null && m.ContainsKey("val")) ? m["val"] : StructUtils.NONE;
            if (val is string s && s == Runner.NULLMARK) val = "null";
            int? max = OptInt(Get(in_, "max"));
            return StructUtils.Stringify(val, max);
        });
        Run("minor", "jsonify", true, in_ =>
        {
            object? val = Get(in_, "val");
            object? flags = Get(in_, "flags");
            int indent = 2;
            int offset = 0;
            if (flags is Dictionary<string, object?> fm)
            {
                if (fm.TryGetValue("indent", out object? iv) && OptInt(iv) is int i) indent = i;
                if (fm.TryGetValue("offset", out object? ov) && OptInt(ov) is int o) offset = o;
            }
            return StructUtils.Jsonify(val, indent, offset);
        });
        Run("minor", "pathify", true, in_ =>
        {
            var m = in_ as Dictionary<string, object?>;
            bool hasPath = m != null && m.ContainsKey("path");
            object? path = hasPath ? m!["path"] : StructUtils.NONE;
            if (path is string ps && ps == Runner.NULLMARK) path = null;
            int from = 0;
            if (m != null && m.TryGetValue("from", out object? fv) && fv != null)
                from = (int)Convert.ToInt64(fv);
            string result = StructUtils.Pathify(path, from);
            if (hasPath && m!["path"] is string origPath && origPath == Runner.NULLMARK)
                result = result.Replace(">", ":null>");
            result = result.Replace(Runner.NULLMARK + ".", "");
            return result;
        });
        Run("minor", "escre",   true,  in_ => StructUtils.EscRe(in_ as string));
        Run("minor", "escurl",  true,  in_ => StructUtils.EscUrl(in_ as string));
        Run("minor", "join",    true,  in_ =>
        {
            object? val = Get(in_, "val");
            object? sep = Get(in_, "sep");
            object? url = Get(in_, "url");
            var list = val as List<object?> ?? new List<object?>();
            return StructUtils.Join(list, sep as string, url as bool? ?? false);
        });
        Run("minor", "flatten", true, in_ =>
        {
            object? val = Get(in_, "val");
            int d = OptInt(Get(in_, "depth")) ?? 1;
            var list = val as List<object?> ?? new List<object?>();
            return StructUtils.Flatten(list, d);
        });
        Run("minor", "filter",  true, in_ =>
        {
            object? val = Get(in_, "val");
            string check = Get(in_, "check") as string ?? "";
            Func<List<object?>, bool> pred = check == "gt3"
                ? p => p.Count > 1 && Runner.IsNumericValue(p[1]) && Runner.ToDoubleVal(p[1]) > 3
                : p => p.Count > 1 && Runner.IsNumericValue(p[1]) && Runner.ToDoubleVal(p[1]) < 3;
            return StructUtils.Filter(val, pred);
        });
        Run("minor", "typename", true, in_ =>
        {
            if (in_ is long l) return StructUtils.TypeName((int)l);
            if (in_ is int i)  return StructUtils.TypeName(i);
            return StructUtils.TypeName(StructUtils.Typify(in_));
        });
        Run("minor", "typify",   true, in_ => StructUtils.Typify(in_));
        Run("minor", "size",     true, in_ => StructUtils.Size(in_));
        Run("minor", "slice",    true, in_ =>
        {
            object? val = Get(in_, "val");
            int? start = OptInt(Get(in_, "start"));
            int? end = OptInt(Get(in_, "end"));
            return StructUtils.Slice(val, start, end);
        });
        Run("minor", "pad",      true, in_ =>
        {
            object? val = Get(in_, "val");
            int p = OptInt(Get(in_, "pad")) ?? 44;
            string? c = Get(in_, "char") as string;
            return StructUtils.Pad(val, p, c);
        });
        Run("minor", "setpath",  false, in_ =>
            StructUtils.SetPath(Get(in_, "store"), Get(in_, "path"), Get(in_, "val")));

        // ===== walk =====
        Run("walk", "basic", true, in_ =>
            StructUtils.Walk(in_, null, (k, v, p, path) =>
            {
                if (v is string s)
                    return s + "~" + string.Join(".", path.Select(x => x?.ToString() ?? ""));
                return v;
            }));
        Run("walk", "depth", false, in_ =>
        {
            object? src = Get(in_, "src");
            int maxdepth = OptInt(Get(in_, "maxdepth")) ?? 32;
            object? top = null;
            object? cur = null;
            WalkApply copy = (k, v, p, path) =>
            {
                if (k == null || StructUtils.IsNode(v))
                {
                    object child = StructUtils.IsList(v)
                        ? new List<object?>()
                        : (object)new Dictionary<string, object?>();
                    if (k == null) { top = child; cur = child; }
                    else { StructUtils.SetProp(cur, k, child); cur = child; }
                }
                else
                {
                    StructUtils.SetProp(cur, k, v);
                }
                return v;
            };
            StructUtils.Walk(src, copy, null, maxdepth);
            return top;
        });
        Run("walk", "copy", true, in_ =>
        {
            object?[] cur = new object?[64];
            WalkApply walkcopy = (k, v, p, path) =>
            {
                if (k == null)
                {
                    cur[0] = StructUtils.IsMap(v) ? (object?)new Dictionary<string, object?>()
                          : StructUtils.IsList(v) ? (object?)new List<object?>()
                          : v;
                    return v;
                }
                object? vv = v;
                int i = path.Count;
                if (StructUtils.IsNode(vv))
                {
                    vv = StructUtils.IsMap(vv) ? (object?)new Dictionary<string, object?>()
                       : (object?)new List<object?>();
                    cur[i] = vv;
                }
                StructUtils.SetProp(cur[i - 1], k, vv);
                return v;
            };
            StructUtils.Walk(in_, walkcopy);
            return cur[0];
        });

        // ===== merge =====
        Run("merge", "cases",     true, in_ => StructUtils.Merge(in_));
        Run("merge", "array",     true, in_ => StructUtils.Merge(in_));
        Run("merge", "integrity", true, in_ => StructUtils.Merge(in_));
        Run("merge", "depth",     true, in_ =>
        {
            object? val = Get(in_, "val");
            int d = OptInt(Get(in_, "depth")) ?? 32;
            return StructUtils.Merge(val, d);
        });

        // ===== getpath =====
        Run("getpath", "basic", true, in_ =>
            StructUtils.GetPath(Get(in_, "store"), Get(in_, "path")));
        Run("getpath", "relative", true, in_ =>
        {
            var inj = new InjectState();
            if (in_ is Dictionary<string, object?> m)
            {
                if (m.ContainsKey("dparent")) inj.DParent = m["dparent"];
                if (m.ContainsKey("dpath"))
                {
                    object? dp = m["dpath"];
                    inj.DPath.Clear();
                    if (dp is List<object?> dpl)
                        foreach (var p in dpl) inj.DPath.Add(StructUtils.StrKey(p));
                    else if (dp is string dps)
                        foreach (var p in dps.Split('.')) inj.DPath.Add(p);
                }
                if (m.ContainsKey("base") && m["base"] is string b) inj.Base = b;
            }
            bool any = (in_ is Dictionary<string, object?> mm) &&
                (mm.ContainsKey("dparent") || mm.ContainsKey("dpath") || mm.ContainsKey("base"));
            return StructUtils.GetPath(Get(in_, "store"), Get(in_, "path"), null, any ? inj : null);
        });
        Run("getpath", "special", true, in_ =>
        {
            object? injv = Get(in_, "inj");
            if (injv is not Dictionary<string, object?> im)
                return StructUtils.GetPath(Get(in_, "store"), Get(in_, "path"));
            var inj = new InjectState();
            if (im.ContainsKey("key") && im["key"] is string k) inj.Key = k;
            if (im.ContainsKey("meta") && im["meta"] is Dictionary<string, object?> mm) inj.Meta = mm;
            if (im.ContainsKey("dparent")) inj.DParent = im["dparent"];
            if (im.ContainsKey("dpath"))
            {
                object? dp = im["dpath"];
                inj.DPath.Clear();
                if (dp is List<object?> dpl)
                    foreach (var p in dpl) inj.DPath.Add(StructUtils.StrKey(p));
                else if (dp is string dps)
                    foreach (var p in dps.Split('.')) inj.DPath.Add(p);
            }
            return StructUtils.GetPath(Get(in_, "store"), Get(in_, "path"), null, inj);
        });

        // ===== inject =====
        Run("inject", "string", true, in_ =>
            StructUtils.Inject(Get(in_, "val"), Get(in_, "store")));
        Run("inject", "deep",   true, in_ =>
            StructUtils.Inject(Get(in_, "val"), Get(in_, "store")));

        // ===== transform =====
        Run("transform", "paths",  true, in_ => StructUtils.Transform(Get(in_, "data"), Get(in_, "spec")));
        Run("transform", "cmds",   true, in_ => StructUtils.Transform(Get(in_, "data"), Get(in_, "spec")));
        Run("transform", "each",   true, in_ => StructUtils.Transform(Get(in_, "data"), Get(in_, "spec")));
        Run("transform", "pack",   true, in_ => StructUtils.Transform(Get(in_, "data"), Get(in_, "spec")));
        Run("transform", "modify", true, in_ =>
        {
            var inj = new InjectState();
            inj.ModifyFn = (val, key, parent, ij, store) =>
            {
                if (key != null && parent is Dictionary<string, object?> p && val is string s)
                    p[StructUtils.StrKey(key) ?? ""] = "@" + s;
                return null;
            };
            return StructUtils.Transform(Get(in_, "data"), Get(in_, "spec"), inj);
        });
        Run("transform", "ref",    true, in_ => StructUtils.Transform(Get(in_, "data"), Get(in_, "spec")));
        Run("transform", "format", false, in_ => StructUtils.Transform(Get(in_, "data"), Get(in_, "spec")));
        Run("transform", "apply",  true, in_ =>
        {
            var inj = new InjectState();
            var extra = new Dictionary<string, object?>();
            Injector applyFn = (ij, val, refStr, store) =>
                val is string s ? s.ToUpperInvariant() : val;
            extra["apply"] = applyFn;
            inj.Extra = extra;
            return StructUtils.Transform(Get(in_, "data"), Get(in_, "spec"), inj);
        });

        // ===== validate =====
        Run("validate", "basic",   true, in_ => StructUtils.Validate(Get(in_, "data"), Get(in_, "spec")));
        Run("validate", "child",   true, in_ => StructUtils.Validate(Get(in_, "data"), Get(in_, "spec")));
        Run("validate", "one",     true, in_ => StructUtils.Validate(Get(in_, "data"), Get(in_, "spec")));
        Run("validate", "exact",   true, in_ => StructUtils.Validate(Get(in_, "data"), Get(in_, "spec")));
        Run("validate", "invalid", true, in_ => StructUtils.Validate(Get(in_, "data"), Get(in_, "spec")));
        Run("validate", "special", true, in_ =>
        {
            object? injMap = Get(in_, "inj");
            InjectState? inj = null;
            if (injMap is Dictionary<string, object?> im)
            {
                inj = new InjectState();
                if (im.ContainsKey("meta") && im["meta"] is Dictionary<string, object?> mm) inj.Meta = mm;
                if (im.ContainsKey("extra")) inj.Extra = im["extra"];
            }
            return StructUtils.Validate(Get(in_, "data"), Get(in_, "spec"), inj);
        });

        // ===== select =====
        Run("select", "basic",     true, in_ => StructUtils.Select(Get(in_, "obj"), Get(in_, "query")));
        Run("select", "operators", true, in_ => StructUtils.Select(Get(in_, "obj"), Get(in_, "query")));
        Run("select", "edge",      true, in_ => StructUtils.Select(Get(in_, "obj"), Get(in_, "query")));
        Run("select", "alts",      true, in_ => StructUtils.Select(Get(in_, "obj"), Get(in_, "query")));

        // Aggregate per-file scoreboard.
        var byFile = new SortedDictionary<string, (int passed, int total)>();
        var details = new SortedDictionary<string, List<(string name, string tally)>>();
        int totalP = 0, totalT = 0;
        foreach (var (key, r) in _scoreboard)
        {
            string cat = key.Substring(0, key.IndexOf('.'));
            string file = CategoryToFile.TryGetValue(cat, out string? f) ? f : cat + ".jsonic";
            if (!byFile.ContainsKey(file)) byFile[file] = (0, 0);
            var (p, t) = byFile[file];
            byFile[file] = (p + r.Passed, t + r.Total);
            if (!details.ContainsKey(file)) details[file] = new();
            details[file].Add((key, $"{r.Passed}/{r.Total}"));
            totalP += r.Passed;
            totalT += r.Total;
        }

        var sb = new StringBuilder();
        sb.AppendLine();
        sb.AppendLine("========= STRUCT CORPUS SCOREBOARD =========");
        foreach (var (file, (p, t)) in byFile)
        {
            sb.AppendLine($"  {file,-18} {p,4} / {t,4}");
            foreach (var (n, tally) in details[file])
                sb.AppendLine($"      {n,-30} {tally}");
        }
        sb.AppendLine($"  {"TOTAL",-18} {totalP,4} / {totalT,4}");
        sb.AppendLine("============================================");
        _out.WriteLine(sb.ToString());

        if (Environment.GetEnvironmentVariable("CORPUS_VERBOSE") is string v && v != "0")
        {
            foreach (var (key, r) in _scoreboard)
            {
                if (r.Failures.Count == 0) continue;
                _out.WriteLine($"\n--- {key} ({r.Passed}/{r.Total}) ---");
                int shown = 0;
                foreach (var fail in r.Failures)
                {
                    _out.WriteLine("  " + fail);
                    if (++shown >= 5)
                    {
                        _out.WriteLine($"  ... {r.Failures.Count - shown} more");
                        break;
                    }
                }
            }
        }

        var fileJson = new Dictionary<string, object>();
        foreach (var (file, (p, t)) in byFile)
            fileJson[file] = new { passed = p, total = t };
        var json = JsonSerializer.Serialize(
            new { files = fileJson, total = new { passed = totalP, total = totalT } },
            new JsonSerializerOptions { WriteIndented = true });
        try { File.WriteAllText("corpus-scoreboard.json", json); } catch { }
    }
}
