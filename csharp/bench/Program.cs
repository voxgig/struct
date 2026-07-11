// Performance bench for the C# port. Emits one JSON line per
// build/bench/README.md; diagnostics go to stderr.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Text;
using Voxgig.Struct;

class Bench
{
    static long sink = 0;

    static int Envi(string k, int d) =>
        int.TryParse(Environment.GetEnvironmentVariable(k), out var n) ? n : d;

    static object Build(int w, int d, int leaf)
    {
        if (d == 0) return leaf;
        var m = new Dictionary<string, object?>();
        for (int i = 0; i < w; i++) m["k" + i] = Build(w, d - 1, leaf);
        return m;
    }

    static long NodeCount(int w, int d)
    {
        long n = 0, p = 1;
        for (int i = 0; i <= d; i++) { n += p; p *= w; }
        return n;
    }

    static double[] Measure(int warm, int runs, Action fn)
    {
        for (int i = 0; i < warm; i++) fn();
        var t = new double[runs];
        var sw = new Stopwatch();
        for (int r = 0; r < runs; r++) { sw.Restart(); fn(); sw.Stop(); t[r] = sw.Elapsed.TotalMilliseconds; }
        Array.Sort(t);
        double s = 0; foreach (var x in t) s += x;
        return new[] { t[0], t[runs / 2], s / runs };
    }

    static string F(double x) => x.ToString("R", CultureInfo.InvariantCulture);

    static void Main()
    {
        int W = Envi("BENCH_WIDTH", 5), D = Envi("BENCH_DEPTH", 6),
            WARM = Envi("BENCH_WARMUP", 3), RUNS = Envi("BENCH_RUNS", 21),
            GP = Envi("BENCH_GETPATH_ITERS", 2000);

        var tree = Build(W, D, 0);
        long nodes = NodeCount(W, D);
        var treeA = Build(W, D, 1);
        var treeB = Build(W, D, 2);
        string path = string.Join(".", Enumerable.Repeat("k0", D));
        WalkApply cb = (k, v, p, pathL) => { sink += pathL.Count; return v; };

        var names = new[] { "clone", "walk", "merge", "stringify", "getpath" };
        var ucs = new long[] { nodes, nodes, nodes, nodes, GP };
        var fns = new Action[]
        {
            () => { if (StructUtils.Clone(tree) != null) sink++; },
            () => StructUtils.Walk(tree, cb),
            () => { if (StructUtils.Merge(new List<object?> { treeA, treeB }) != null) sink++; },
            () => { sink += StructUtils.Stringify(tree).Length; },
            () => { long a = 0; for (int i = 0; i < GP; i++) if (StructUtils.GetPath(tree, path) != null) a++; sink += a; },
        };

        var ops = new StringBuilder();
        for (int i = 0; i < names.Length; i++)
        {
            var m = Measure(WARM, RUNS, fns[i]);
            if (i > 0) ops.Append(',');
            ops.Append($"{{\"op\":\"{names[i]}\",\"runs\":{RUNS},\"unit_count\":{ucs[i]},\"min_ms\":{F(m[0])},\"median_ms\":{F(m[1])},\"mean_ms\":{F(m[2])}}}");
        }

        Console.Error.WriteLine($"csharp: sink={sink}");
        Console.WriteLine($"{{\"lang\":\"csharp\",\"runtime\":\".NET {Environment.Version}\",\"nodes\":{nodes},\"params\":{{\"width\":{W},\"depth\":{D},\"warmup\":{WARM},\"runs\":{RUNS},\"getpath_iters\":{GP}}},\"ops\":[{ops}]}}");
    }
}
