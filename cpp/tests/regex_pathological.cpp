// Discovery test: pathological regex inputs run against the port's re_* API.
// Goal is to surface failures across ports, not to assert behaviour.
// Panel is the same in every port (see REGEX.md).

#include "voxgig_struct.hpp"

#include <chrono>
#include <cstdio>
#include <functional>
#include <regex>
#include <sstream>
#include <string>

using namespace voxgig::structlib;

// Render outcomes as JSON-ish so output matches the other ports.
static std::string j_str(const std::string& s) {
  std::string out = "\"";
  for (char c : s) {
    if (c == '"' || c == '\\')
      out.push_back('\\'), out.push_back(c);
    else
      out.push_back(c);
  }
  out.push_back('"');
  return out;
}

template <typename F> static void record(const char* label, F fn) {
  auto t0 = std::chrono::steady_clock::now();
  std::string outcome;
  try {
    outcome = std::string("OK | ") + fn();
  } catch (const std::exception& e) {
    outcome = std::string("ERR | ") + typeid(e).name() + ": " + e.what();
  } catch (...) {
    outcome = "ERR | unknown exception";
  }
  double ms =
      std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  std::printf("[regex-discovery] %s | %.2fms | %s\n", label, ms, outcome.c_str());
}

static std::string as_bool(bool b) {
  return b ? "true" : "false";
}

static std::string as_vec(const std::vector<std::string>& v) {
  std::string s = "[";
  for (size_t i = 0; i < v.size(); i++) {
    if (i)
      s += ",";
    s += j_str(v[i]);
  }
  s += "]";
  return s;
}

static std::string as_vec2(const std::vector<std::vector<std::string>>& v) {
  std::string s = "[";
  for (size_t i = 0; i < v.size(); i++) {
    if (i)
      s += ",";
    s += as_vec(v[i]);
  }
  s += "]";
  return s;
}

int main() {
  std::string a22(22, 'a');
  std::string nest40 = std::string(40, '(') + "a" + std::string(40, ')');

  record("P1_redos_nested_plus", [&] { return as_bool(re_test("^(a+)+$", a22 + "!")); });
  record("P2_redos_alt_overlap", [&] { return as_bool(re_test("^(a|aa)+$", a22 + "!")); });
  record("P3_empty_repeat_replace", [&] { return j_str(re_replace("a*", "abc", "X")); });
  record("P4_unicode_replace_dot", [&] { return j_str(re_replace("\\.", "café.au.lait", "/")); });
  record("P5_unicode_find_codepoint", [&] { return as_vec(re_find("é", "café au lait")); });
  record("P6_deep_nesting_compile", [&] { return as_bool(re_test(nest40, "a")); });
  record("P7_big_bounded_quantifier",
         [&] { return as_bool(re_test("^a{0,10000}b$", std::string(10, 'a') + "b")); });
  record("P8_invalid_pattern", [&] {
    (void) re_compile("[abc");
    return std::string("\"compiled\"");
  });
  record("P9_backref_re2_forbidden", [&] { return as_bool(re_test("^(a+)\\1$", "aaaa")); });
  record("P10_find_all_zero_width", [&] { return as_vec2(re_find_all("a*", "bbb")); });

  return 0;
}
