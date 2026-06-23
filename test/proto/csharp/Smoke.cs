// Smoke test for the C# test-provider port. Loads the default corpus and prints
// summary numbers to verify parity with the canonical TS reference.
//
// Expected canonical output:
//   functions: minor, getpath, inject, merge, transform, walk, validate, select, sentinels
//   total entries: 1325 ; expect kinds: value=1181, absent=84, match=1, error=59 ; input kinds: in=1325
//   getpath/basic[0]: id=getpath/basic#deep, doc=true, input.kind=in, expect.kind=value, expect.value=42

namespace Voxgig.Struct.Proto;

public static class Smoke
{
    private static string ExpectName(ExpectKind k) => k switch
    {
        ExpectKind.Value => "value",
        ExpectKind.Error => "error",
        ExpectKind.Match => "match",
        ExpectKind.Absent => "absent",
        _ => "?",
    };

    private static string InputName(InputKind k) => k switch
    {
        InputKind.In => "in",
        InputKind.Args => "args",
        InputKind.Ctx => "ctx",
        _ => "?",
    };

    public static void Main()
    {
        TestProvider provider = TestProvider.Load();

        List<string> fns = provider.Functions();
        Console.WriteLine("functions: " + string.Join(", ", fns));

        int total = 0;
        var expectKinds = new Dictionary<string, int>
        {
            ["value"] = 0, ["absent"] = 0, ["match"] = 0, ["error"] = 0,
        };
        var inputKinds = new Dictionary<string, int>
        {
            ["in"] = 0, ["args"] = 0, ["ctx"] = 0,
        };

        foreach (string fn in fns)
        {
            foreach (Entry e in provider.Entries(fn))
            {
                total++;
                expectKinds[ExpectName(e.Expect.Kind)]++;
                inputKinds[InputName(e.Input.Kind)]++;
            }
        }

        Console.WriteLine(
            $"total entries: {total} ; " +
            $"expect kinds: value={expectKinds["value"]}, absent={expectKinds["absent"]}, " +
            $"match={expectKinds["match"]}, error={expectKinds["error"]} ; " +
            $"input kinds: in={inputKinds["in"]}");

        List<Entry> gp = provider.Entries("getpath", "basic");
        if (gp.Count > 0)
        {
            Entry e = gp[0];
            string id = e.Id ?? "<nil>";
            string val = TestProvider.Stringify(e.Expect.Value);
            Console.WriteLine(
                $"getpath/basic[0]: id={id}, doc={(e.Doc ? "true" : "false")}, " +
                $"input.kind={InputName(e.Input.Kind)}, expect.kind={ExpectName(e.Expect.Kind)}, " +
                $"expect.value={val}");
        }
    }
}
