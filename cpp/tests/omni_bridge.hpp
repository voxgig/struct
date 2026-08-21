// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
//
// Voxgig Struct — the bridge to voxgig/omni, the shared test runner.
//
// The corpus runner is not in this repository. omni is header-only and
// consumed as a local checkout, resolved by the Makefile ($OMNI_HOME first,
// then sibling paths, taking the first directory that carries spec/fib.json).
// Only the tests include it: `make build` compiles src/ alone and nothing in
// the shipped headers names omni (register 4.13).
//
// This is the C++ counterpart of c/tests/omni_bridge.h, python/tests/omni.py,
// csharp/tests/Omni.cs, java/src/test/Omni.java, rust/corpus/tests/omni.rs
// and perl/t/OmniBridge.pm.
//
// ---------------------------------------------------------------------------
// Two value types, one shape
// ---------------------------------------------------------------------------
//
// omni has `omni::Json` and this port has `Value`. They model the same JSON,
// and both draw the same three-way distinction - absent, null, and a value -
// so nothing has to be guessed:
//
//     omni                  this port
//     ----                  ---------
//     Json::Type::Absent    std::monostate (is_undef)
//     Json::Type::Null      std::nullptr_t (is_null)
//     Json::Type::Bool/...  bool / int64_t / double / std::string / ...
//
// The one difference is numbers: `omni::Json` carries a single `double`, while
// this port separates integers from decimals - `typify(1)` is T_integer and
// `typify(1.5)` is T_decimal, and `minor/typify` asserts both. So an integral
// double becomes an int64, which is what this port's own JSON reader does with
// a literal that has no `.` or exponent. The corpus contains no decimal
// literal with an integral value, so nothing is lost.
//
// ---------------------------------------------------------------------------
// Mutated arguments
// ---------------------------------------------------------------------------
//
// `tostruct` builds a new `Value`, so the subject does NOT receive omni's own
// container and an in-place rewrite would be invisible to the runner.
// `minor/setpath` asserts the store AFTER such a rewrite in eight of its nine
// entries, and `merge/integrity` in all six, through `match.args`.
//
// `omni::Json` is a value type, so there is nothing to share and no way to
// write through a `const std::vector<Json>&`. omni grew `runsetflags_args` for
// exactly this - a subject that may mutate its argument vector - and the
// wrapper below writes the converted argument back after the call. omni-rust
// has the same pair for the same reason; the dynamic ports share the object
// and need neither.

#ifndef VOXGIG_STRUCT_OMNI_BRIDGE_HPP
#define VOXGIG_STRUCT_OMNI_BRIDGE_HPP

#include <cmath>
#include <memory>
#include <string>
#include <vector>

#include "omni.hpp"
#include "value.hpp"
#include "voxgig_struct.hpp"

namespace bridge {

using voxgig::structlib::List;
using voxgig::structlib::Map;
using voxgig::structlib::Value;

// The subject in this port's shape: one argument in, one value out. A failure
// is a thrown exception, which omni catches and matches against `err`.
using Subject = std::function<Value(const Value&)>;

// The largest double that is exactly an integer. Beyond it, "is this a whole
// number?" stops being a question about the value and starts being one about
// the representation.
constexpr double INTMAX = 9007199254740992.0;

// omni's model -> this port's.
inline Value tostruct(const omni::Json& val) {
  switch (val.type) {
  case omni::Json::Type::Absent:
    return Value::undef();

  case omni::Json::Type::Null:
    return Value(nullptr);

  case omni::Json::Type::Bool:
    return Value(val.boolval);

  case omni::Json::Type::Num: {
    double num = val.numval;
    if (std::isfinite(num) && std::floor(num) == num && std::fabs(num) < INTMAX) {
      return Value(static_cast<int64_t>(num));
    }
    return Value(num);
  }

  case omni::Json::Type::Str:
    return Value(val.strval);

  case omni::Json::Type::List: {
    auto out = std::make_shared<List>();
    out->reserve(val.listval.size());
    for (const auto& entry : val.listval) {
      out->push_back(tostruct(entry));
    }
    return Value(out);
  }

  case omni::Json::Type::Map: {
    auto out = std::shared_ptr<Map>(new Map());
    for (const auto& entry : val.mapval) {
      out->set(entry.first, tostruct(entry.second));
    }
    return Value(out);
  }
  }

  return Value::undef();
}

// This port's model -> omni's.
//
// A function or a sentinel has no JSON form. Both can reach here - `merge`
// carries a function value through, and `$SKIP` survives a transform - and
// omni only ever stringifies them, so they become their own names rather than
// silently collapsing to null.
inline omni::Json toomni(const Value& val) {
  if (val.is_undef()) {
    return omni::Json::absent();
  }
  if (val.is_null()) {
    return omni::Json::null();
  }
  if (val.is_bool()) {
    return omni::Json::boolean(val.as_bool());
  }
  if (val.is_int()) {
    return omni::Json::num(static_cast<double>(val.as_int()));
  }
  if (val.is_double()) {
    return omni::Json::num(val.as_double());
  }
  if (val.is_string()) {
    return omni::Json::str(val.as_string());
  }
  if (val.is_list()) {
    omni::Json out = omni::Json::list();
    for (const auto& entry : *val.as_list()) {
      out.listval.push_back(toomni(entry));
    }
    return out;
  }
  if (val.is_map()) {
    omni::Json out = omni::Json::map();
    for (const auto& [key, entry] : *val.as_map()) {
      out.set(key, toomni(entry));
    }
    return out;
  }
  if (val.is_func()) {
    return omni::Json::str("[Function]");
  }
  if (val.is_sentinel()) {
    return omni::Json::str(std::string("`$") + val.as_sentinel()->name + "`");
  }
  return omni::Json::absent();
}

// Wrap a struct-shaped subject as one omni can call, writing the converted
// argument back so an in-place rewrite is visible to `match`.
inline omni::SubjectArgs wrap(const Subject& subject) {
  return [subject](std::vector<omni::Json>& args) -> omni::Json {
    // An entry carrying no `in` at all is called with one ABSENT argument, not
    // null - `typify()` is 1073741824 where `typify(null)` is 4194432.
    Value in = tostruct(args.empty() ? omni::Json::absent() : args[0]);
    Value got = subject(in);
    if (!args.empty()) {
      args[0] = toomni(in);
    }
    return toomni(got);
  };
}

} // namespace bridge

#endif // VOXGIG_STRUCT_OMNI_BRIDGE_HPP
