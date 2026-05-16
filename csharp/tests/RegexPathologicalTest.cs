/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

// RUN: cd csharp/tests && dotnet test --filter "DisplayName~RegexPathological"
//
// Discovery test: pathological regex inputs run against the port's Re* API.
// Goal is to surface failures across ports, not to assert behaviour.
// Panel is the same in every port (see REGEX.md).

using System;
using System.Diagnostics;
using System.Text.Json;
using static Voxgig.Struct.StructUtils;
using Xunit;

namespace Voxgig.Tests;

public class RegexPathologicalTest
{
    private static void Record(string label, Func<object?> fn)
    {
        var sw = Stopwatch.StartNew();
        string outcome;
        try
        {
            var r = fn();
            outcome = "OK | " + JsonSerializer.Serialize(r);
        }
        catch (Exception e)
        {
            outcome = "ERR | " + e.GetType().Name + ": " + e.Message;
        }
        sw.Stop();
        var ms = sw.Elapsed.TotalMilliseconds;
        Console.WriteLine($"[regex-discovery] {label} | {ms:F2}ms | {outcome}");
    }

    [Fact]
    public void Panel()
    {
        var a22 = new string('a', 22);
        var nest40 = new string('(', 40) + "a" + new string(')', 40);

        Record("P1_redos_nested_plus",      () => ReTest("^(a+)+$", a22 + "!"));
        Record("P2_redos_alt_overlap",      () => ReTest("^(a|aa)+$", a22 + "!"));
        Record("P3_empty_repeat_replace",   () => ReReplace("a*", "abc", "X"));
        Record("P4_unicode_replace_dot",    () => ReReplace("\\.", "café.au.lait", "/"));
        Record("P5_unicode_find_codepoint", () => ReFind("é", "café au lait"));
        Record("P6_deep_nesting_compile",   () => ReTest(nest40, "a"));
        Record("P7_big_bounded_quantifier", () => ReTest("^a{0,10000}b$", new string('a', 10) + "b"));
        Record("P8_invalid_pattern",        () => ReCompile("[abc"));
        Record("P9_backref_re2_forbidden",  () => ReTest("^(a+)\\1$", "aaaa"));
        Record("P10_find_all_zero_width",   () => ReFindAll("a*", "bbb"));
    }
}
