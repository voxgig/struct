// Smoke test for the C++ test-provider port.
//
// Loads build/test/test.json (resolved relative to CWD; run from repo root),
// prints the functions list, total entries, expect-kind counts, input-kind
// counts, and the first getpath/basic entry.
//
//   g++ -std=c++17 -O2 test/proto/cpp/smoke.cpp -o /tmp/cpp_smoke
//   (cd /home/user/struct && /tmp/cpp_smoke)

#include <iostream>
#include <string>

#include "provider.hpp"

using namespace voxgig::testproto;

static std::string expectKindName(ExpectKind k) {
  switch (k) {
    case ExpectKind::VALUE:
      return "value";
    case ExpectKind::ERROR:
      return "error";
    case ExpectKind::MATCH:
      return "match";
    case ExpectKind::ABSENT:
      return "absent";
  }
  return "?";
}

static std::string inputKindName(InputKind k) {
  switch (k) {
    case InputKind::IN:
      return "in";
    case InputKind::ARGS:
      return "args";
    case InputKind::CTX:
      return "ctx";
  }
  return "?";
}

int main(int argc, char** argv) {
  std::string path = (argc > 1) ? argv[1] : "";
  TestProvider provider = TestProvider::load(path);

  // functions list
  std::vector<std::string> fns = provider.functions();
  std::cout << "functions: ";
  for (size_t i = 0; i < fns.size(); i++) {
    if (i) std::cout << ", ";
    std::cout << fns[i];
  }
  std::cout << "\n";

  // tally over all entries
  size_t total = 0;
  size_t valueN = 0, absentN = 0, matchN = 0, errorN = 0;
  size_t inN = 0, argsN = 0, ctxN = 0;
  for (const auto& fn : fns) {
    for (const auto& e : provider.entries(fn)) {
      total++;
      switch (e.expect.kind) {
        case ExpectKind::VALUE:
          valueN++;
          break;
        case ExpectKind::ABSENT:
          absentN++;
          break;
        case ExpectKind::MATCH:
          matchN++;
          break;
        case ExpectKind::ERROR:
          errorN++;
          break;
      }
      switch (e.input.kind) {
        case InputKind::IN:
          inN++;
          break;
        case InputKind::ARGS:
          argsN++;
          break;
        case InputKind::CTX:
          ctxN++;
          break;
      }
    }
  }

  std::cout << "total entries: " << total << " ; expect kinds: value=" << valueN
            << ", absent=" << absentN << ", match=" << matchN << ", error=" << errorN
            << " ; input kinds: in=" << inN;
  if (argsN) std::cout << ", args=" << argsN;
  if (ctxN) std::cout << ", ctx=" << ctxN;
  std::cout << "\n";

  // getpath/basic[0]
  std::vector<Entry> gp = provider.entries("getpath", std::optional<std::string>("basic"));
  if (!gp.empty()) {
    const Entry& e = gp[0];
    std::cout << "getpath/basic[0]: id=" << (e.id ? *e.id : std::string("null"))
              << ", doc=" << (e.doc ? "true" : "false")
              << ", input.kind=" << inputKindName(e.input.kind)
              << ", expect.kind=" << expectKindName(e.expect.kind) << ", expect.value=";
    if (e.expect.value.has_value())
      std::cout << jsonify(*e.expect.value);
    else
      std::cout << "(none)";
    std::cout << "\n";
  }

  return 0;
}
