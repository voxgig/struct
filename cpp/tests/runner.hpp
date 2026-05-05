// Voxgig Struct corpus runner — C++ port.
// Mirrors java/src/test/Runner.java.

#ifndef VOXGIG_STRUCT_RUNNER_HPP
#define VOXGIG_STRUCT_RUNNER_HPP

#include <functional>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "value.hpp"
#include "value_io.hpp"
#include "voxgig_struct.hpp"

namespace voxgig {
namespace structlib {
namespace runner {

inline const std::string& NULLMARK()   { static const std::string s = "__NULL__";   return s; }
inline const std::string& UNDEFMARK()  { static const std::string s = "__UNDEF__";  return s; }
inline const std::string& EXISTSMARK() { static const std::string s = "__EXISTS__"; return s; }

using Subject = std::function<Value(const Value&)>;

struct Result {
  std::string name;
  int passed = 0;
  int total = 0;
  std::vector<std::string> failures;
};

inline Value& corpus() {
  static Value c = Value::undef();
  return c;
}

inline Value get_spec(const std::string& category, const std::string& name) {
  if (corpus().is_undef()) {
    corpus() = parse_json_file("../build/test/test.json");
  }
  Value struct_v = getprop(corpus(), Value("struct"));
  Value cat = getprop(struct_v, Value(category));
  return getprop(cat, Value(name));
}

// Normalise: integer-valued doubles -> int64; map keys sorted; sentinels and
// undefined collapse to null for stable comparison.
inline Value normalize(const Value& v) {
  if (v.is_undef() || v.is_null()) return Value(nullptr);
  if (v.is_double()) {
    double d = v.as_double();
    if (std::isfinite(d) && std::floor(d) == d) return Value(static_cast<int64_t>(d));
    return v;
  }
  if (v.is_list()) {
    auto out = std::make_shared<List>();
    for (const auto& e : *v.as_list()) out->push_back(normalize(e));
    return Value(out);
  }
  if (v.is_map()) {
    std::map<std::string, Value> sorted;
    for (const auto& [k, e] : *v.as_map()) sorted[k] = normalize(e);
    auto out = std::shared_ptr<Map>(new Map());
    for (const auto& [k, e] : sorted) out->set(k, e);
    return Value(out);
  }
  return v;
}

inline bool deep_equal(const Value& a, const Value& b) {
  return normalize(a) == normalize(b);
}

inline std::string brief(const Value& v) {
  std::string s;
  if (v.is_undef()) return UNDEFMARK();
  try { s = to_njson(v).dump(); }
  catch (...) { s = stringify(v); }
  if (s.size() > 200) s = s.substr(0, 197) + "...";
  return s;
}

inline Result runsetflags(const std::string& full_name, const Value& testspec,
                          bool null_flag, const Subject& subject) {
  Result res;
  res.name = full_name;
  Value set_v = getprop(testspec, Value("set"));
  if (!set_v.is_list()) return res;
  auto set = set_v.as_list();
  for (size_t i = 0; i < set->size(); i++) {
    const Value& eo = (*set)[i];
    if (!eo.is_map()) continue;
    bool has_in = haskey(eo, Value("in"));
    Value in_raw = getprop(eo, Value("in"));
    Value in = has_in ? clone(in_raw) : Value::undef();
    bool has_out = haskey(eo, Value("out"));
    Value expected = has_out ? getprop(eo, Value("out"))
                              : (null_flag ? Value(nullptr) : Value::undef());
    Value err_v = haskey(eo, Value("err")) ? getprop(eo, Value("err")) : Value::undef();

    res.total++;
    Value got;
    bool threw = false;
    std::string thrown_msg;
    try {
      got = subject(in);
    } catch (const std::exception& e) {
      threw = true;
      thrown_msg = e.what();
    }

    if (!err_v.is_undef()) {
      // err entry: either accept any thrown error, or substring match.
      if (threw) {
        bool match = false;
        if (err_v.is_bool() && err_v.as_bool()) match = true;
        else if (err_v.is_string()) {
          std::string es = err_v.as_string();
          if (es.empty()) match = true;
          else if (thrown_msg.find(es) != std::string::npos) match = true;
          else {
            std::string lo_msg = thrown_msg;
            std::string lo_es = es;
            for (auto& c : lo_msg) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
            for (auto& c : lo_es)  c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
            if (lo_msg.find(lo_es) != std::string::npos) match = true;
          }
        }
        if (match) res.passed++;
        else {
          std::ostringstream oss;
          oss << "[" << i << "] err mismatch: expected '" << brief(err_v)
              << "' got '" << thrown_msg << "'";
          res.failures.push_back(oss.str());
        }
      } else {
        std::ostringstream oss;
        oss << "[" << i << "] expected err='" << brief(err_v)
            << "' but call returned " << brief(got);
        res.failures.push_back(oss.str());
      }
      continue;
    }

    if (threw) {
      std::ostringstream oss;
      oss << "[" << i << "] in=" << brief(in_raw) << " threw=" << thrown_msg;
      res.failures.push_back(oss.str());
      continue;
    }

    if (deep_equal(got, expected)) {
      res.passed++;
    } else {
      std::ostringstream oss;
      oss << "[" << i << "] in=" << brief(in_raw)
          << " expected=" << brief(expected)
          << " got=" << brief(got);
      res.failures.push_back(oss.str());
    }
  }
  return res;
}

inline Result runset(const std::string& full_name, const Value& testspec,
                     const Subject& subject) {
  return runsetflags(full_name, testspec, true, subject);
}

}  // namespace runner
}  // namespace structlib
}  // namespace voxgig

#endif  // VOXGIG_STRUCT_RUNNER_HPP
