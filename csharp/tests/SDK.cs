/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

// The test SDK: what the corpus's `client` entries resolve to, and the handle
// the shared runner reaches the library through.
//
// This port had none. The `primary.check` group - the one that exercises
// client resolution, `DEF.client` options and `contextify` - was therefore
// never run here, while javascript, python, ruby, go, php and lua all run it.
// It is two entries, but they are the only two that prove the client path
// works at all.
//
// The shape mirrors the other ports' SDKs (php/tests/SDK.php,
// lua/test/sdk.lua): an object with `Utility()`, whose bag carries the
// library, a `Contextify` hook and a `Check` subject, plus `Tester(opts)` to
// mint a configured instance for a `DEF.client` entry.

namespace Voxgig.Struct.Tests;


/// <summary>What `SDK.Utility()` returns: the library plus the test hooks.</summary>
public sealed class UtilityBag
{
    /// <summary>
    /// The library itself, as a <see cref="System.Type"/> rather than an
    /// instance, because every entry point on it is static. The runner reads
    /// members off whatever this returns, so a Type gives it the statics -
    /// `NONE` among them, which is how absence crosses the boundary.
    /// </summary>
    public Type Struct => typeof(StructUtils);

    /// <summary>Resolve references in client options against the runner store.</summary>
    public Func<object?, object?, object?> Inject { get; init; } =
        (options, store) => StructUtils.Inject(options, store);

    /// <summary>Wrap a context map. This port adds nothing; the hook must exist.</summary>
    public Func<object?, object?> Contextify { get; init; } = ctxmap => ctxmap;

    /// <summary>The `check` subject the corpus names.</summary>
    public required Func<object?, object?> Check { get; init; }
}


/// <summary>The test SDK a runner is built with.</summary>
public sealed class SDK
{
    private readonly Dictionary<string, object?> _opts;
    private readonly UtilityBag _utility;

    public SDK(Dictionary<string, object?>? opts = null)
    {
        _opts = opts ?? [];

        _utility = new UtilityBag
        {
            Check = ctx =>
            {
                // `foo` comes from the client's own options, `bar` from the
                // entry's ctx - so the two corpus entries differ only by which
                // client resolved them.
                string foo = _opts.TryGetValue("foo", out object? f) && null != f
                    ? StructUtils.Stringify(f)
                    : "";

                string bar = "0";
                if (ctx is IDictionary<string, object?> ctxmap &&
                    ctxmap.TryGetValue("meta", out object? meta) &&
                    meta is IDictionary<string, object?> metamap &&
                    metamap.TryGetValue("bar", out object? b) && null != b)
                {
                    bar = StructUtils.Stringify(b);
                }

                return new Dictionary<string, object?> { ["zed"] = "ZED" + foo + "_" + bar };
            },
        };
    }

    /// <summary>A test SDK instance.</summary>
    public static SDK Test(Dictionary<string, object?>? opts = null) => new(opts);

    /// <summary>A sub-client for a `DEF.client` entry's options.</summary>
    public SDK Tester(Dictionary<string, object?>? opts = null) => new(opts ?? _opts);

    /// <summary>The library and the test hooks.</summary>
    public UtilityBag Utility() => _utility;
}
