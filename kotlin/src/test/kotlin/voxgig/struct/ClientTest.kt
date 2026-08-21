package voxgig.struct

import voxgig.omni.Flags
import voxgig.omni.Json
import voxgig.omni.Provider
import voxgig.omni.stringify
import kotlin.test.Test

/**
 * The client path: `DEF.client`, client-scoped options, and `contextify`.
 *
 * This port had no such test. Every migrated port runs this group
 * (javascript/test/client.test.js, php/tests/ClientTest.php,
 * lua/test/client_test.lua, csharp/tests/ClientTest.cs,
 * java/src/test/ClientTest.java, perl/t/client.t, c/tests/client_test.c,
 * cpp/tests/client_test.cpp), and it is the only thing that exercises subject
 * resolution through a PROVIDER rather than through a callback the test file
 * hands over - so nothing here had ever checked that a corpus `client` key
 * resolves, or that a `DEF.client` entry's options reach the subject.
 *
 * Two entries, differing only in which client answers: the default one with no
 * options gives "ZED_BAR0", and client "a" - carrying `{foo: 1}` - gives
 * "ZED1_BAR1".
 *
 * The subject here talks to omni DIRECTLY, in omni's own value type: the
 * runner resolves it by name off the provider, so there is no `in` to convert
 * and no result for the bridge to convert back.
 */
class ClientTest {
    /**
     * The SDK's `check` subject. `options` is what a `DEF.client` entry
     * carried, `args[0]` is the entry's own context.
     */
    private fun check(
        options: Json,
        args: List<Json>,
    ): Json {
        val foo = options.get("foo")
        val foos = if (foo.isabsent) "" else stringify(foo)

        var bars = "0"
        if (args.isNotEmpty()) {
            val bar = args[0].get("meta").get("bar")
            if (!bar.isnone) {
                bars = stringify(bar)
            }
        }

        return Json.map("zed" to Json.str("ZED" + foos + "_" + bars))
    }

    /** A provider carrying one client's options. */
    private fun provider(options: Json): Provider =
        Provider(
            subject = { name ->
                if ("check" == name) {
                    { args: List<Json> -> check(options, args) }
                } else {
                    null
                }
            },
            // A DEF.client entry becomes another provider, carrying its options.
            client = { copts -> provider(copts) },
            // This port adds nothing to a context; the hook must exist so omni
            // installs `client` on it.
            contextify = { value -> value },
        )

    @Test
    fun clientCheckBasic() {
        val run = Omni.Run.of("check", provider(Json.map()))
        // No subject: the runner resolves it by name off the provider, which
        // is the whole point of the group.
        run.runsetnamed(run.group("basic"), Flags(name = "check.basic"))
    }
}
