// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
//
// The client path: `DEF.client`, client-scoped options, and `contextify`.
//
// This port had no such test. Every migrated port runs this group
// (javascript/test/client.test.js, php/tests/ClientTest.php,
// lua/test/client_test.lua, csharp/tests/ClientTest.cs,
// java/src/test/ClientTest.java, perl/t/client.t, c/tests/client_test.c), and
// it is the only thing that exercises subject resolution through a PROVIDER
// rather than through a callback the test file hands over — so nothing here
// had ever checked that a corpus `client` key resolves, or that a `DEF.client`
// entry's options reach the subject.
//
// Two entries, differing only in which client answers: the default one with no
// options gives "ZED_BAR0", and client "a" — carrying `{foo: 1}` — gives
// "ZED1_BAR1".
//
// The subject here talks to omni DIRECTLY, in omni's own value type: the
// runner resolves it by name off the provider, so there is no `in` to convert
// and no result for the bridge to convert back.

#include <cstdio>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "omni.hpp"

namespace {

std::shared_ptr<omni::Provider> makeprovider(const omni::Json& options);

// The SDK's `check` subject. `options` is what a `DEF.client` entry carried,
// `args[0]` is the entry's own context.
omni::Json check(const omni::Json& options, const std::vector<omni::Json>& args) {
  const omni::Json foo = options.get("foo");
  const std::string foos = foo.isabsent() ? "" : omni::stringify(foo);

  std::string bars = "0";
  if (!args.empty()) {
    const omni::Json bar = args[0].get("meta").get("bar");
    if (!bar.isnone()) {
      bars = omni::stringify(bar);
    }
  }

  omni::Json out = omni::Json::map();
  out.set("zed", omni::Json::str("ZED" + foos + "_" + bars));
  return out;
}

// A provider carrying one client's options.
std::shared_ptr<omni::Provider> makeprovider(const omni::Json& options) {
  auto provider = std::make_shared<omni::Provider>();

  provider->subject = [options](const std::string& name) -> omni::Subject {
    if ("check" != name) {
      return nullptr;
    }
    return [options](const std::vector<omni::Json>& args) { return check(options, args); };
  };

  // A DEF.client entry becomes another provider, carrying its options.
  provider->client = [](const omni::Json& copts) { return makeprovider(copts); };

  // This port adds nothing to a context; the hook must exist so omni installs
  // `client` on it.
  provider->contextify = [](const omni::Json& val) { return val; };

  return provider;
}

} // namespace

int main() {
  try {
    omni::Runner runner =
        omni::makeRunner("../build/test/test.json", makeprovider(omni::Json::map()));
    omni::RunPack pack = runner.runner("check");

    omni::Flags flags;
    flags.name = "check.basic";

    // No subject: the runner resolves it by name off the provider, which is
    // the whole point of the group.
    pack.runsetflags(pack.spec.get("basic"), flags);

    std::printf("\n===== struct client =====\n  ok   check.basic\n=========================\n\n");
  } catch (const std::exception& err) {
    std::printf("\n===== struct client =====\n  FAIL check.basic\n       %s\n"
                "=========================\n\n",
                err.what());
    return 1;
  }

  return 0;
}
