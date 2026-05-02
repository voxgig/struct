// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
//
// Voxgig Struct — JSON I/O bridge.
//
// Converts between our runtime Value type and nlohmann::json for parsing
// and serialisation. nlohmann is used only at the JSON-text boundary; the
// runtime container is Value.

#ifndef VOXGIG_STRUCT_VALUE_IO_HPP
#define VOXGIG_STRUCT_VALUE_IO_HPP

#include <fstream>
#include <sstream>
#include <string>

#include <nlohmann/json.hpp>

#include "value.hpp"

namespace voxgig {
namespace structlib {

// ---- nlohmann::json -> Value ----

inline Value from_njson(const nlohmann::json& j) {
  if (j.is_null())            return Value(nullptr);
  if (j.is_boolean())         return Value(j.get<bool>());
  if (j.is_number_integer())  return Value(j.get<int64_t>());
  if (j.is_number_unsigned()) return Value(static_cast<int64_t>(j.get<uint64_t>()));
  if (j.is_number_float())    return Value(j.get<double>());
  if (j.is_string())          return Value(j.get<std::string>());
  if (j.is_array()) {
    auto out = std::make_shared<List>();
    out->reserve(j.size());
    for (const auto& el : j) out->push_back(from_njson(el));
    return Value(std::move(out));
  }
  if (j.is_object()) {
    auto out = std::shared_ptr<Map>(new Map());
    for (auto it = j.begin(); it != j.end(); ++it) {
      out->set(it.key(), from_njson(it.value()));
    }
    return Value(std::move(out));
  }
  return Value();  // undefined fallback
}

// ---- Value -> nlohmann::json (for serialisation; drops functions) ----

inline nlohmann::json to_njson(const Value& v) {
  if (v.is_undef())    return nullptr;  // serialise undefined as null
  if (v.is_null())     return nullptr;
  if (v.is_bool())     return v.as_bool();
  if (v.is_int())      return v.as_int();
  if (v.is_double())   return v.as_double();
  if (v.is_string())   return v.as_string();
  if (v.is_list()) {
    nlohmann::json out = nlohmann::json::array();
    for (const auto& e : *v.as_list()) out.push_back(to_njson(e));
    return out;
  }
  if (v.is_map()) {
    nlohmann::json out = nlohmann::json::object();
    for (const auto& [k, e] : *v.as_map()) out[k] = to_njson(e);
    return out;
  }
  if (v.is_sentinel()) {
    nlohmann::json out = nlohmann::json::object();
    out[std::string("`$") + v.as_sentinel()->name + "`"] = true;
    return out;
  }
  // function / unknown -> null
  return nullptr;
}

// ---- JSON text I/O ----

inline Value parse_json(const std::string& text) {
  return from_njson(nlohmann::json::parse(text));
}

inline Value parse_json_file(const std::string& path) {
  std::ifstream f(path);
  if (!f) throw std::runtime_error("Cannot open " + path);
  std::stringstream ss;
  ss << f.rdbuf();
  return parse_json(ss.str());
}

inline std::string dump_json(const Value& v, int indent = -1) {
  return to_njson(v).dump(indent);
}

}  // namespace structlib
}  // namespace voxgig

#endif  // VOXGIG_STRUCT_VALUE_IO_HPP
