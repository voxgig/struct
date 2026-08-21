/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

// The client path: `DEF.client`, client-scoped options, and `contextify`.
//
// This port had no such test. Every other migrated port runs this group
// (javascript/test/client.test.js, php/tests/ClientTest.php,
// lua/test/client_test.lua and the rest), and it is the only thing that
// exercises subject resolution through the SDK rather than through a lambda
// the test file supplies - so nothing here had ever checked that a corpus
// `client` key resolves, or that a `DEF.client` entry's options reach the
// subject.
//
// Two entries, and they differ only by which client answers: the default one
// with no options gives "ZED_BAR0", and client "a" - carrying `{foo: 1}` -
// gives "ZED1_BAR1".

using Voxgig.Struct;
using Voxgig.Omni;
using Xunit;

namespace Voxgig.Struct.Tests;


public class ClientTests
{
    [Fact]
    public void ClientCheckBasic()
    {
        var pack = Omni.MakeRunner(SDK.Test())("check", null);
        var spec = pack.Spec as Dictionary<string, object?> ?? [];

        // No subject: the runner resolves it by name off the SDK, which is the
        // whole point of the group.
        pack.RunSetNamed(spec["basic"], Omni.Nulls);
    }
}
