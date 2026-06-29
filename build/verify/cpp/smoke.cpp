// Smoke client for the PUBLISHED C++ port (header-only), built against the
// source vendored from the git tag cpp/v<VERSION>. The Makefile compiles
// this with -I <topdir>/cpp/src.

#include <iostream>
#include <string>

#include "value_io.hpp" // pulls in value.hpp + voxgig_struct.hpp, plus parse_json

using namespace voxgig::structlib;

int main() {
  // store = { db: { host: "localhost" } }
  Value store = parse_json(R"({"db":{"host":"localhost"}})");
  Value got = getpath_v(store, Value("db.host"));

  if (got == Value("localhost")) {
    std::cout << "OK cpp: getpath(db.host) = localhost\n";
    return 0;
  }

  std::cerr << "FAIL cpp: getpath(db.host) = " << stringify(got)
            << " (want localhost)\n";
  return 1;
}
