/* Test runner that reads from build/test/test.json and drives xUnit tests. */

using System.Text.Json;
using Voxgig.Struct;
using Xunit;

namespace Voxgig.Struct.Tests;


public static class Runner
{
    public const string NULLMARK   = "__NULL__";
    public const string UNDEFMARK  = "__UNDEF__";
    public const string EXISTSMARK = "__EXISTS__";

    // Load the shared test JSON and extract the "struct" sub-spec.
    public static Dictionary<string, object?> LoadSpec()
    {
        // Walk up from the test binary to find build/test/test.json.
        string dir = AppContext.BaseDirectory;
        string? testFile = null;
        for (int i = 0; i < 10; i++)
        {
            string candidate = Path.Combine(dir, "build", "test", "test.json");
            if (File.Exists(candidate)) { testFile = candidate; break; }
            dir = Path.GetDirectoryName(dir)!;
        }
        if (testFile == null)
            throw new FileNotFoundException("Could not find build/test/test.json");

        string json = File.ReadAllText(testFile);
        var all = JsonSerializer.Deserialize<JsonElement>(json);
        return ConvertElement(all.GetProperty("struct")) as Dictionary<string, object?> ?? [];
    }

    // Convert a JsonElement tree into native C# types.
    public static object? ConvertElement(JsonElement el)
    {
        return el.ValueKind switch
        {
            JsonValueKind.Object => el.EnumerateObject()
                .ToDictionary(p => p.Name, p => ConvertElement(p.Value)),
            JsonValueKind.Array  => el.EnumerateArray()
                .Select(ConvertElement)
                .ToList<object?>(),
            JsonValueKind.String => el.GetString(),
            JsonValueKind.Number => el.TryGetInt64(out long l) ? (object?)l : el.GetDouble(),
            JsonValueKind.True   => (object?)true,
            JsonValueKind.False  => (object?)false,
            JsonValueKind.Null   => null,
            _                    => null,
        };
    }

    // Run a test-set spec through a subject function; fail on mismatch.
    public static void RunSet(
        object? testSpec,
        Func<object?, object?> subject,
        Dictionary<string, bool>? flags = null)
    {
        flags ??= [];
        bool allowNull = flags.TryGetValue("null", out bool n) && n;

        var spec = testSpec as Dictionary<string, object?>;
        if (spec == null) return;

        var set = spec.TryGetValue("set", out object? sv) ? sv as List<object?> : null;
        if (set == null) return;

        for (int i = 0; i < set.Count; i++)
        {
            var entry = set[i] as Dictionary<string, object?>;
            if (entry == null) continue;

            // Skip entries that have no "out".
            if (!entry.ContainsKey("out")) continue;

            object? input = entry.TryGetValue("in", out object? inv) ? inv : null;
            object? expected = entry["out"];

            // Skip null-valued inputs when null flag is false.
            if (!allowNull)
            {
                if (input == null) continue;
                if (expected == null) continue;
                if (input is Dictionary<string, object?> inMap &&
                    inMap.Values.Any(v => v == null)) continue;
            }

            // Apply NULLMARK substitutions.
            input    = FixJson(input, allowNull);
            expected = FixJson(expected, allowNull);

            object? result;
            try   { result = subject(input); }
            catch (Exception ex)
            {
                Assert.Fail($"Entry #{i}: threw exception: {ex.Message}\n  input={StructUtils.Stringify(input)}");
                return;
            }

            result = FixJson(result, allowNull);

            bool ok = DeepEqual(expected, result);
            if (!ok)
            {
                Assert.Fail(
                    $"Entry #{i}: expected {StructUtils.Stringify(expected)} " +
                    $"but got {StructUtils.Stringify(result)}\n" +
                    $"  input={StructUtils.Stringify(input)}");
            }
        }
    }

    // Apply NULLMARK / UNDEFMARK substitutions.
    public static object? FixJson(object? val, bool allowNull)
    {
        if (val is string s)
        {
            if (s == NULLMARK)  return allowNull ? null : null;
            if (s == UNDEFMARK) return null;
            return val;
        }
        if (val is Dictionary<string, object?> map)
        {
            var result = new Dictionary<string, object?>();
            foreach (var kv in map)
                result[kv.Key] = FixJson(kv.Value, allowNull);
            return result;
        }
        if (val is List<object?> list)
            return list.Select(v => FixJson(v, allowNull)).ToList<object?>();
        return val;
    }

    // Deep structural equality (numbers are compared by value, ignoring int/long/double).
    public static bool DeepEqual(object? a, object? b)
    {
        if (a == null && b == null) return true;
        if (a == null || b == null) return false;

        // Numeric equivalence across int/long/double.
        if (IsNumeric(a) && IsNumeric(b))
            return ToDouble(a) == ToDouble(b);

        if (a is bool ab && b is bool bb) return ab == bb;
        if (a is string sa && b is string sb) return sa == sb;

        if (a is Dictionary<string, object?> am && b is Dictionary<string, object?> bm)
        {
            if (am.Count != bm.Count) return false;
            foreach (var kv in am)
            {
                if (!bm.TryGetValue(kv.Key, out object? bv)) return false;
                if (!DeepEqual(kv.Value, bv)) return false;
            }
            return true;
        }

        // Handle any IList (List<object?>, List<string>, List<List<object?>>, etc.)
        if (a is System.Collections.IList al && b is System.Collections.IList bl)
        {
            if (al.Count != bl.Count) return false;
            for (int i = 0; i < al.Count; i++)
                if (!DeepEqual(al[i], bl[i])) return false;
            return true;
        }

        return a.Equals(b);
    }

    private static bool IsNumeric(object? v) =>
        v is int or long or double or float or short or byte;

    public static bool IsNumericValue(object? v) => IsNumeric(v);

    private static double ToDouble(object? v) => v switch
    {
        int    i => i,
        long   l => l,
        double d => d,
        float  f => f,
        _        => 0,
    };

    public static double ToDoubleVal(object? v) => ToDouble(v);

    // Run a test-set where entries may have an "err" field (expected exception message)
    // instead of (or in addition to) an "out" field.
    // - Entries with "err": subject is called without errs; expects InvalidOperationException.
    // - Entries with only "out": subject is called; result is compared to "out".
    public static void RunSetFull(
        object? testSpec,
        Func<Dictionary<string, object?>?, object?> subject,
        Dictionary<string, bool>? flags = null)
    {
        flags ??= [];
        bool allowNull = flags.TryGetValue("null", out bool n) && n;

        var spec = testSpec as Dictionary<string, object?>;
        if (spec == null) return;

        var set = spec.TryGetValue("set", out object? sv) ? sv as List<object?> : null;
        if (set == null) return;

        for (int i = 0; i < set.Count; i++)
        {
            var entry = set[i] as Dictionary<string, object?>;
            if (entry == null) continue;

            bool hasOut = entry.ContainsKey("out");
            bool hasErr = entry.ContainsKey("err");
            if (!hasOut && !hasErr) continue;

            object? rawInput = entry.TryGetValue("in", out object? inv) ? inv : null;
            if (!allowNull && rawInput == null && !hasErr) continue;
            rawInput = FixJson(rawInput, allowNull);
            var input = rawInput as Dictionary<string, object?>;

            if (hasErr)
            {
                string expectedErr = entry["err"]?.ToString() ?? "";
                try
                {
                    var r = subject(input);
                    Assert.Fail(
                        $"Entry #{i}: expected error but no exception thrown " +
                        $"(result={StructUtils.Stringify(r)})");
                }
                catch (Exception ex) when (ex is not Xunit.Sdk.XunitException)
                {
                    string msg = ex.Message;
                    bool ok = msg.Contains(expectedErr) || expectedErr.Length == 0;
                    if (!ok)
                        Assert.Fail(
                            $"Entry #{i}: expected error containing '{expectedErr}' " +
                            $"but got '{msg}'");
                }
            }
            else
            {
                object? expected = FixJson(entry["out"], allowNull);
                object? result;
                try { result = subject(input); }
                catch (Exception ex)
                {
                    Assert.Fail($"Entry #{i}: unexpected exception: {ex.Message}");
                    return;
                }
                result = FixJson(result, allowNull);
                if (!DeepEqual(expected, result))
                    Assert.Fail(
                        $"Entry #{i}: expected {StructUtils.Stringify(expected)} " +
                        $"but got {StructUtils.Stringify(result)}");
            }
        }
    }
}
