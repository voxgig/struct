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

inline const std::string& NULLMARK() {
  static const std::string s = "__NULL__";
  return s;
}
inline const std::string& UNDEFMARK() {
  static const std::string s = "__UNDEF__";
  return s;
}
inline const std::string& EXISTSMARK() {
  static const std::string s = "__EXISTS__";
  return s;
}

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

// fix_json: bridge JSON null to the cross-port "__NULL__" string marker, the
// same transform the canonical runner (typescript/test/runner.ts:fixJSON)
// applies to every test input, every result, and every expected `out` when the
// null flag is set. This is what lets the corpus encode "value is JSON null"
// (distinct from "value is absent") without the test harness having to special
// case it: every observed null becomes the literal string "__NULL__", and the
// subjects that care (inject.string) swap it back via null_modifier(). A node's
// own identity is preserved; only null *values* are rewritten.
inline Value fix_json(const Value& v, bool null_flag) {
  if (v.is_undef())
    return v;
  if (v.is_null())
    return null_flag ? Value(NULLMARK()) : v;
  if (v.is_list()) {
    auto out = std::make_shared<List>();
    for (const auto& e : *v.as_list())
      out->push_back(fix_json(e, null_flag));
    return Value(out);
  }
  if (v.is_map()) {
    auto out = std::shared_ptr<Map>(new Map());
    for (const auto& [k, e] : *v.as_map())
      out->set(k, fix_json(e, null_flag));
    return Value(out);
  }
  return v;
}

// collapse_absent: treat NOVAL (absent) as JSON null for comparison. The
// canonical TS runner roundtrips both the result and the expected `out` through
// JSON.stringify, which erases the null/undef distinction at the value level
// (swift CorpusTests.canon does the same via normaliseAbsent). Applying this to
// BOTH sides — together with fix_json — lets a port that correctly returns
// "absent" for a missing getprop/getelem/getpath match a corpus entry that
// records the result as null. The stored-null vs absent distinction that the
// sentinels groups exercise is preserved earlier, on the *input*, via fix_json.
inline Value collapse_absent(const Value& v) {
  if (v.is_undef())
    return Value(nullptr);
  if (v.is_list()) {
    auto out = std::make_shared<List>();
    for (const auto& e : *v.as_list())
      out->push_back(collapse_absent(e));
    return Value(out);
  }
  if (v.is_map()) {
    auto out = std::shared_ptr<Map>(new Map());
    for (const auto& [k, e] : *v.as_map())
      out->set(k, collapse_absent(e));
    return Value(out);
  }
  return v;
}

// null_modifier: the inject `modify` callback used by the inject.string subject.
// Mirrors typescript/test/runner.ts:nullModifier — a slot whose injected value
// is exactly "__NULL__" becomes JSON null; a string that merely *contains*
// "__NULL__" has the marker rewritten to the literal text "null".
inline void null_modifier(const Value& val, const Value& key, const Value& parent, Injection&,
                          const Value&) {
  if (!val.is_string())
    return;
  const std::string& s = val.as_string();
  if (s == NULLMARK()) {
    setprop(parent, key, Value(nullptr));
    return;
  }
  if (s.find(NULLMARK()) != std::string::npos) {
    std::string out = s;
    std::string::size_type pos = 0;
    while ((pos = out.find(NULLMARK(), pos)) != std::string::npos) {
      out.replace(pos, NULLMARK().size(), "null");
      pos += 4;
    }
    setprop(parent, key, Value(out));
  }
}

// Normalise for comparison: integer-valued doubles -> int64. Map key order and
// null/undef are NOT collapsed here — null is carried as the "__NULL__" marker
// (see fix_json) and key order must match canonical insertion order, so the
// comparison stays faithful instead of masking those distinctions.
inline Value normalize(const Value& v) {
  if (v.is_double()) {
    double d = v.as_double();
    if (std::isfinite(d) && std::floor(d) == d)
      return Value(static_cast<int64_t>(d));
    return v;
  }
  if (v.is_list()) {
    auto out = std::make_shared<List>();
    for (const auto& e : *v.as_list())
      out->push_back(normalize(e));
    return Value(out);
  }
  if (v.is_map()) {
    auto out = std::shared_ptr<Map>(new Map());
    for (const auto& [k, e] : *v.as_map())
      out->set(k, normalize(e));
    return Value(out);
  }
  return v;
}

// Order-insensitive deep equality. JSON objects are unordered, so two maps with
// the same entries in a different key order are equal (swift CorpusTests.canon
// compares via stringify with sorted keys for the same reason). Lists stay
// order-sensitive. Scalars fall back to Value::operator== after normalize().
inline bool deep_equal(const Value& a0, const Value& b0) {
  Value a = normalize(a0);
  Value b = normalize(b0);
  if (a.is_map() && b.is_map()) {
    auto am = a.as_map();
    auto bm = b.as_map();
    if (am->size() != bm->size())
      return false;
    for (const auto& [k, av] : *am) {
      const Value* bv = bm->find(k);
      if (bv == nullptr || !deep_equal(av, *bv))
        return false;
    }
    return true;
  }
  if (a.is_list() && b.is_list()) {
    auto al = a.as_list();
    auto bl = b.as_list();
    if (al->size() != bl->size())
      return false;
    for (size_t i = 0; i < al->size(); i++)
      if (!deep_equal((*al)[i], (*bl)[i]))
        return false;
    return true;
  }
  return a == b;
}

inline std::string brief(const Value& v) {
  std::string s;
  if (v.is_undef())
    return UNDEFMARK();
  // Use the library's in-tree jsonify (compact form, no third-party dep).
  s = jsonify(v, 0);
  if (s.size() > 200)
    s = s.substr(0, 197) + "...";
  return s;
}

inline Result runsetflags(const std::string& full_name, const Value& testspec, bool null_flag,
                          const Subject& subject) {
  Result res;
  res.name = full_name;
  Value set_v = getprop(testspec, Value("set"));
  if (!set_v.is_list())
    return res;
  auto set = set_v.as_list();
  for (size_t i = 0; i < set->size(); i++) {
    const Value& eo = (*set)[i];
    if (!eo.is_map())
      continue;
    // Extract in/out/err with the null-preserving lookup_v rather than Group A
    // getprop/haskey: a test entry whose `in` (or `out`) is literally JSON null
    // (e.g. the sentinels groups) must keep that null, not be read as absent.
    Value in_raw = lookup_v(eo, Value("in"));
    bool has_in = !in_raw.is_undef();
    // Bridge JSON null -> "__NULL__" on the input the same way the canonical
    // runner does, so subjects observe the marker (and inject.string can swap
    // it back through null_modifier).
    Value in = has_in ? fix_json(clone(in_raw), null_flag) : Value::undef();
    Value out_raw = lookup_v(eo, Value("out"));
    bool has_out = !out_raw.is_undef();
    // resolveEntry: an absent expected `out` collapses to null, then both sides
    // run through collapse_absent + fix_json so an absent result matches it.
    Value expected = fix_json(collapse_absent(has_out ? out_raw : Value::undef()), null_flag);
    Value err_raw = lookup_v(eo, Value("err"));
    Value err_v = err_raw.is_undef() ? Value::undef() : err_raw;

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
        if (err_v.is_bool() && err_v.as_bool())
          match = true;
        else if (err_v.is_string()) {
          std::string es = err_v.as_string();
          if (es.empty())
            match = true;
          else if (thrown_msg.find(es) != std::string::npos)
            match = true;
          else {
            std::string lo_msg = thrown_msg;
            std::string lo_es = es;
            for (auto& c : lo_msg)
              c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
            for (auto& c : lo_es)
              c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
            if (lo_msg.find(lo_es) != std::string::npos)
              match = true;
          }
        }
        if (match)
          res.passed++;
        else {
          std::ostringstream oss;
          oss << "[" << i << "] err mismatch: expected '" << brief(err_v) << "' got '" << thrown_msg
              << "'";
          res.failures.push_back(oss.str());
        }
      } else {
        std::ostringstream oss;
        oss << "[" << i << "] expected err='" << brief(err_v) << "' but call returned "
            << brief(got);
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

    Value got_c = fix_json(collapse_absent(got), null_flag);
    if (deep_equal(got_c, expected)) {
      res.passed++;
    } else {
      std::ostringstream oss;
      oss << "[" << i << "] in=" << brief(in_raw) << " expected=" << brief(expected)
          << " got=" << brief(got_c);
      res.failures.push_back(oss.str());
    }
  }
  return res;
}

inline Result runset(const std::string& full_name, const Value& testspec, const Subject& subject) {
  return runsetflags(full_name, testspec, true, subject);
}

} // namespace runner
} // namespace structlib
} // namespace voxgig

#endif // VOXGIG_STRUCT_RUNNER_HPP
