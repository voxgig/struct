/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

// Benchmark for Walk on wide and deep trees. Not run by default.
// To enable:
//   WALK_BENCH=1 dotnet test --filter "DisplayName~WalkBench" --logger "console;verbosity=detailed"

using System.Diagnostics;
using Voxgig.Struct;
using Xunit;
using Xunit.Abstractions;

namespace Voxgig.Struct.Tests;


public class WalkBenchTests
{
    private readonly ITestOutputHelper _out;
    private static readonly bool BENCH =
        "1" == Environment.GetEnvironmentVariable("WALK_BENCH");


    public WalkBenchTests(ITestOutputHelper outputHelper)
    {
        _out = outputHelper;
    }


    // Build a balanced tree of maps with given width and depth.
    // Total nodes: (width^(depth+1) - 1) / (width - 1).
    private static object? BuildTree(int width, int depth)
    {
        if (0 == depth)
        {
            return 0;
        }
        var outMap = new Dictionary<string, object?>(width);
        for (int i = 0; i < width; i++)
        {
            outMap["k" + i] = BuildTree(width, depth - 1);
        }
        return outMap;
    }


    private static long CountNodes(object? val)
    {
        if (val is Dictionary<string, object?> m)
        {
            long n = 1;
            foreach (var kv in m)
            {
                n += CountNodes(kv.Value);
            }
            return n;
        }
        if (val is List<object?> l)
        {
            long n = 1;
            foreach (var c in l)
            {
                n += CountNodes(c);
            }
            return n;
        }
        return 1;
    }


    private void Measure(string label, object? tree, int runs)
    {
        // Touch path.Count to simulate a minimal consumer. Keeps work O(1).
        long sink = 0;
        WalkApply cb = (_k, v, _p, path) =>
        {
            sink += path.Count;
            return v;
        };

        // Warm-up.
        for (int i = 0; i < 2; i++)
        {
            StructUtils.Walk(tree, cb);
        }

        var times = new List<double>(runs);
        for (int r = 0; r < runs; r++)
        {
            var sw = Stopwatch.StartNew();
            StructUtils.Walk(tree, cb);
            sw.Stop();
            times.Add(sw.Elapsed.TotalMilliseconds);
        }
        times.Sort();
        double median = times[times.Count / 2];
        double min    = times[0];
        double max    = times[times.Count - 1];
        double mean   = times.Sum() / times.Count;

        long nodes     = CountNodes(tree);
        double nsPerNode = (median * 1e6) / nodes;

        _out.WriteLine(
            $"[walk-bench] {label}: nodes={nodes} runs={runs} " +
            $"min={min:F2}ms median={median:F2}ms " +
            $"mean={mean:F2}ms max={max:F2}ms " +
            $"ns/node={nsPerNode:F1} sink={sink}");
    }


    [Fact]
    public void WalkBenchWideAndDeep()
    {
        if (!BENCH) return;
        // ~299k nodes: width=8, depth=6.
        var tree = BuildTree(8, 6);
        Measure("wide+deep (w=8,d=6)", tree, 7);
    }


    [Fact]
    public void WalkBenchVeryWide()
    {
        if (!BENCH) return;
        // width=1000, depth=2 -> 1,001,001 nodes, shallow.
        var tree = BuildTree(1000, 2);
        Measure("wide (w=1000,d=2)", tree, 7);
    }


    [Fact]
    public void WalkBenchVeryDeep()
    {
        if (!BENCH) return;
        // width=2, depth=20 -> (2^21 - 1) = 2,097,151 nodes.
        var tree = BuildTree(2, 20);
        Measure("deep (w=2,d=20)", tree, 5);
    }
}
