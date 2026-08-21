/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

package voxgig.struct;

// The client path: `DEF.client`, client-scoped options, and `contextify`.
//
// This port had no such test. Every migrated port runs this group
// (javascript/test/client.test.js, php/tests/ClientTest.php,
// lua/test/client_test.lua, csharp/tests/ClientTest.cs), and it is the only
// thing that exercises subject resolution through a PROVIDER rather than
// through a lambda the test file hands over - so nothing here had ever checked
// that a corpus `client` key resolves, or that a `DEF.client` entry's options
// reach the subject.
//
// Two entries, and they differ only by which client answers: the default one
// with no options gives "ZED_BAR0", and client "a" - carrying `{foo: 1}` -
// gives "ZED1_BAR1".

import com.voxgig.omni.Runner;

import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.Map;

class ClientTest {

  /**
   * The SDK's `check` subject. `opts` is what a `DEF.client` entry carried,
   * `ctx` is the entry's own context.
   */
  @SuppressWarnings("unchecked")
  private static Object check(Object opts, Object ctx) {
    Object foo = opts instanceof Map ? ((Map<String, Object>) opts).get("foo") : null;
    String foos = null == foo ? "" : Struct.stringify(foo);

    String bars = "0";
    if (ctx instanceof Map) {
      Object meta = ((Map<String, Object>) ctx).get("meta");
      if (meta instanceof Map) {
        Object bar = ((Map<String, Object>) meta).get("bar");
        if (null != bar) {
          bars = Struct.stringify(bar);
        }
      }
    }

    Map<String, Object> out = new LinkedHashMap<>();
    out.put("zed", "ZED" + foos + "_" + bars);
    return out;
  }

  /** A provider carrying one client's options. */
  private static Runner.Provider provider(Object options) {
    Runner.Provider provider = new Runner.Provider();

    provider.subject =
        name -> "check".equals(name) ? (Runner.Subject) args -> check(options, 0 < args.length ? args[0] : null) : null;

    // A DEF.client entry becomes another provider, carrying its options.
    provider.client = ClientTest::provider;

    // This port adds nothing to a context; the hook must exist so omni
    // installs `client` on it.
    provider.contextify = val -> val;

    return provider;
  }

  @Test
  @SuppressWarnings("unchecked")
  void clientCheckBasic() {
    Omni.Run run = Omni.Run.of("check", provider(new LinkedHashMap<String, Object>()));
    // No subject: the runner resolves it by name off the provider, which is
    // the whole point of the group.
    run.runsetnamed(((Map<String, Object>) run.spec).get("basic"), null);
  }
}
