/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

// The shared test runner comes from voxgig/omni, consumed as a local checkout
// - omni is deliberately not published to NuGet (yet). The checkout is
// resolved the same way voxgig/sekreto's ports resolve it: $OMNI_HOME first,
// then sibling paths, taking the first directory that carries spec/fib.json.
// Set OMNI_HOME if yours lives elsewhere.
//
// C# differs from the other ports in WHERE that resolution happens. A
// `require`/`import` can be redirected at run time, so python, ruby, php and
// lua resolve the checkout in this file. A C# project reference is resolved at
// BUILD time, so the path lives in `VoxgigStructTest.csproj` and this file
// only names the API. The rule that matters is the same one: only the tests
// depend on omni. `VoxgigStruct.csproj` gains nothing, and
// `dotnet build VoxgigStruct.csproj` still succeeds with no omni checkout
// present at all - which is register 4.13, and is checked by the `library
// builds without omni` CI step rather than left to a reviewer.
//
// This is the C# counterpart of python/tests/omni.py, ruby/omni.rb,
// php/tests/omni.php, lua/test/omni.lua and javascript/test/omni.js.

using Voxgig.Omni;
using Compat = Voxgig.Omni.Compat.Struct;

namespace Voxgig.Struct.Tests;


/// <summary>omni's struct compat shim, under the names this port's tests use.</summary>
public static class Omni
{
    /// <summary>Value is JSON null.</summary>
    public const string NULLMARK = Compat.NULLMARK;

    /// <summary>Value is not present.</summary>
    public const string UNDEFMARK = Compat.UNDEFMARK;

    /// <summary>Value exists.</summary>
    public const string EXISTSMARK = Compat.EXISTSMARK;

    /// <summary>Every entry runs with nulls marked unless a group says otherwise.</summary>
    public static Flags Nulls => new();

    /// <summary>The groups that pass real nulls through to the subject.</summary>
    public static Flags NoNulls => Flags.NoNull();

    /// <summary>
    /// Walk up from the test binary to the corpus, as this port's own runner
    /// did. The build output sits several directories below the repository
    /// root, and the depth differs between `dotnet test` and a published
    /// binary, so it is searched for rather than computed.
    /// </summary>
    public static string CorpusPath()
    {
        string dir = AppContext.BaseDirectory;
        for (int up = 0; up < 10 && null != dir; up++)
        {
            string candidate = Path.Combine(dir, "build", "test", "test.json");
            if (File.Exists(candidate))
            {
                return candidate;
            }
            dir = Path.GetDirectoryName(dir)!;
        }

        throw new FileNotFoundException("struct: could not find build/test/test.json");
    }

    /// <summary>A runner over the shared corpus, backed by omni.</summary>
    public static Func<string, object?, Compat.StructRunPack> MakeRunner(object client)
    {
        return Compat.MakeRunner(CorpusPath(), client);
    }

    /// <summary>
    /// Structural equality for the hand-written assertions in the test files
    /// (the ones the corpus cannot express, such as walk's visit log).
    ///
    /// BOTH sides go through the shim's own boundary conversion first, so they
    /// are compared in exactly the model the runner compares in. Calling
    /// `Util.DeepEqual` directly would not do: it wants `IList&lt;object&gt;`,
    /// and this port's `KeysOf` hands back a `List&lt;string&gt;`.
    /// </summary>
    public static bool DeepEqual(object? expected, object? actual)
    {
        return Util.DeepEqual(
            Compat.ToOmni(expected, StructUtils.NONE),
            Compat.ToOmni(actual, StructUtils.NONE));
    }

    /// <summary>Is this a number, in any of C#'s numeric types?</summary>
    public static bool IsNum(object? val) => Util.IsNum(val);

    /// <summary>That number as a double.</summary>
    public static double ToNum(object? val) => Util.ToNum(val);

    /// <summary>
    /// The null modifier, in this port's `Modify` shape. Not a delegation:
    /// omni's returns a replacement value, struct's is an inject hook that
    /// mutates `parent[key]`.
    /// </summary>
    public static object? NullModifier(object? val, object? key, object? parent,
                                       object? inj, object? store)
    {
        return Compat.NullModifier(val, key, parent, inj, store);
    }
}
