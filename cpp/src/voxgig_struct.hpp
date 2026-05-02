// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
//
// Voxgig Struct — main API.
//
// Header-only port of the canonical TypeScript implementation. Everything
// public lives in namespace voxgig::structlib. Mirrors the Java port at
// java/src/Struct.java which itself mirrors ts/src/StructUtility.ts.

#ifndef VOXGIG_STRUCT_HPP
#define VOXGIG_STRUCT_HPP

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "value.hpp"
#include "value_io.hpp"

namespace voxgig {
namespace structlib {

// ===========================================================================
// String / regex constants
// ===========================================================================

inline const std::string& S_MT()    { static const std::string s = "";       return s; }
inline const std::string& S_DT()    { static const std::string s = ".";      return s; }
inline const std::string& S_DTOP()  { static const std::string s = "$TOP";   return s; }
inline const std::string& S_DSPEC() { static const std::string s = "$SPEC";  return s; }
inline const std::string& S_DKEY()  { static const std::string s = "$KEY";   return s; }
inline const std::string& S_DERRS() { static const std::string s = "$ERRS";  return s; }
inline const std::string& S_BKEY()  { static const std::string s = "`$KEY`"; return s; }
inline const std::string& S_BANNO() { static const std::string s = "`$ANNO`"; return s; }
inline const std::string& S_BVAL()  { static const std::string s = "`$VAL`"; return s; }
inline const std::string& S_BEXACT(){ static const std::string s = "`$EXACT`"; return s; }
inline const std::string& S_BOPEN() { static const std::string s = "`$OPEN`"; return s; }

inline const std::regex& R_INTEGER_KEY() {
  static const std::regex r("^[-0-9]+$");
  return r;
}
inline const std::regex& R_META_PATH() {
  static const std::regex r("^([^$]+)\\$([=~])(.+)$");
  return r;
}
inline const std::regex& R_INJECTION_FULL() {
  static const std::regex r("^`(\\$[A-Z]+|[^`]*)[0-9]*`$");
  return r;
}
inline const std::regex& R_INJECTION_PARTIAL() {
  static const std::regex r("`([^`]+)`");
  return r;
}
inline const std::regex& R_DOUBLE_DOLLAR() {
  static const std::regex r("\\$\\$");
  return r;
}
inline const std::regex& R_TRANSFORM_NAME() {
  static const std::regex r("`\\$([A-Z]+)`");
  return r;
}
inline const std::regex& R_BT_ESCAPE() {
  static const std::regex r("\\$BT");
  return r;
}
inline const std::regex& R_DS_ESCAPE() {
  static const std::regex r("\\$DS");
  return r;
}
inline const std::regex& R_ESCAPE_REGEXP() {
  static const std::regex r(R"([.*+?^${}()|\[\]\\])");
  return r;
}

// ===========================================================================
// Predicates (most also exposed via Value methods)
// ===========================================================================

inline bool isnode(const Value& v) { return v.is_node() || v.is_sentinel(); }
inline bool ismap(const Value& v)  { return v.is_map() || v.is_sentinel(); }
inline bool islist(const Value& v) { return v.is_list(); }

inline bool iskey(const Value& v) {
  if (v.is_string()) return !v.as_string().empty();
  if (v.is_int())    return true;
  if (v.is_double()) return true;
  return false;
}

inline bool isempty(const Value& v) {
  if (v.is_undef() || v.is_null()) return true;
  if (v.is_string()) return v.as_string().empty();
  if (v.is_list())   return v.as_list()->empty();
  if (v.is_map())    return v.as_map()->empty();
  return false;
}

inline bool isfunc(const Value& v) { return v.is_func(); }

inline Value getdef(const Value& v, const Value& alt) {
  if (v.is_undef()) return alt;
  return v;
}

inline int64_t size(const Value& v) { return size_of(v); }

// ===========================================================================
// Type helpers re-exported (defined in value.hpp)
// ===========================================================================
//   typify(const Value&)       -> int
//   typename_str(int)          -> std::string
//   typename_str(const Value&) -> std::string

// ===========================================================================
// Forward declarations
// ===========================================================================

class Injection;

inline std::string strkey(const Value& key);
inline Value getprop(const Value& val, const Value& key, const Value& alt = Value::undef());
inline Value getelem(const Value& val, const Value& key, const Value& alt = Value::undef());
inline Value setprop(Value parent, const Value& key, const Value& val);
inline Value delprop(Value parent, const Value& key);
inline std::vector<std::string> keysof(const Value& v);
inline bool haskey(const Value& v, const Value& key);
inline std::vector<Value> items(const Value& v);
inline std::string stringify(const Value& v, int maxlen = -1);
inline std::string pathify(const Value& v, int startin = 0, int endin = 0);
inline Value slice(const Value& v, const Value& start = Value::undef(), const Value& end = Value::undef());
inline Value walk_v(const Value& val,
                     std::function<Value(const Value&, const Value&, const Value&, const std::vector<std::string>&)> before,
                     std::function<Value(const Value&, const Value&, const Value&, const std::vector<std::string>&)> after,
                     int maxdepth = MAXDEPTH);
inline Value merge_v(const Value& list, int maxdepth = MAXDEPTH);
inline Value getpath_v(const Value& store, const Value& path, Injection* inj = nullptr);
inline Value setpath_v(const Value& store, const Value& path, const Value& val);
inline Value inject(const Value& val, const Value& store, Injection* injdef = nullptr);
inline Value transform(const Value& data, const Value& spec, const Value& options = Value::undef());
inline Value validate(const Value& data, const Value& spec, const Value& options = Value::undef());
inline std::vector<Value> select(const Value& children, const Value& query);

// ===========================================================================
// strkey / getprop / setprop / delprop / getelem
// ===========================================================================

inline std::string strkey(const Value& key) {
  if (key.is_undef()) return S_MT();
  if (key.is_string()) return key.as_string();
  if (key.is_bool())   return S_MT();
  if (key.is_int())    return std::to_string(key.as_int());
  if (key.is_double()) {
    double d = key.as_double();
    if (std::floor(d) == d) return std::to_string(static_cast<int64_t>(d));
    return std::to_string(static_cast<int64_t>(std::floor(d)));
  }
  return S_MT();
}

inline Value getprop(const Value& val, const Value& key, const Value& alt) {
  if (val.is_undef() || key.is_undef()) return alt;
  if (val.is_map()) {
    auto m = val.as_map();
    if (!m) return alt;
    std::string sk = strkey(key);
    Value* found = m->find(sk);
    if (!found) return alt;
    if (found->is_undef()) return alt;
    return *found;
  }
  if (val.is_list()) {
    auto l = val.as_list();
    if (!l) return alt;
    int idx;
    if (key.is_int()) {
      idx = static_cast<int>(key.as_int());
    } else if (key.is_string()) {
      // Match TS: only accept strings that match /^[-0-9]+$/ entirely.
      if (!std::regex_match(key.as_string(), R_INTEGER_KEY())) return alt;
      try { idx = std::stoi(key.as_string()); }
      catch (...) { return alt; }
    } else if (key.is_double()) {
      idx = static_cast<int>(key.as_double());
    } else {
      return alt;
    }
    if (idx < 0 || idx >= static_cast<int>(l->size())) return alt;
    Value v = (*l)[idx];
    if (v.is_undef()) return alt;
    return v;
  }
  return alt;
}

// Match TS regex /^[-0-9]+$/ check.
inline bool is_integer_key_string(const Value& key) {
  if (key.is_int() || key.is_double()) return true;
  if (key.is_string()) {
    return std::regex_match(key.as_string(), R_INTEGER_KEY());
  }
  return false;
}

inline Value getelem(const Value& val, const Value& key, const Value& alt) {
  Value out = Value::undef();
  if (val.is_undef() || key.is_undef()) {
    if (alt.is_func() && alt.is_injector()) return alt;
    return alt;
  }
  if (val.is_list()) {
    auto l = val.as_list();
    int nkey;
    if (key.is_int()) {
      nkey = static_cast<int>(key.as_int());
    } else if (key.is_string()) {
      if (!is_integer_key_string(key)) return alt;
      try { nkey = std::stoi(key.as_string()); }
      catch (...) { return alt; }
    } else if (key.is_double()) {
      nkey = static_cast<int>(key.as_double());
    } else {
      return alt;
    }
    if (nkey < 0) nkey = static_cast<int>(l->size()) + nkey;
    if (nkey < 0 || nkey >= static_cast<int>(l->size())) return alt;
    out = (*l)[nkey];
  }
  if (out.is_undef()) return alt;
  return out;
}

inline Value setprop(Value parent, const Value& key, const Value& val) {
  if (!iskey(key)) return parent;
  if (parent.is_map()) {
    auto m = parent.as_map();
    std::string sk = strkey(key);
    m->set(sk, val);
    return parent;
  }
  if (parent.is_list()) {
    auto l = parent.as_list();
    int idx;
    if (key.is_int()) idx = static_cast<int>(key.as_int());
    else if (key.is_string()) {
      try { idx = std::stoi(key.as_string()); } catch (...) { return parent; }
    } else if (key.is_double()) idx = static_cast<int>(key.as_double());
    else return parent;

    if (idx >= 0) {
      if (idx >= static_cast<int>(l->size())) {
        l->push_back(val);
      } else {
        (*l)[idx] = val;
      }
    } else {
      l->insert(l->begin(), val);
    }
    return parent;
  }
  return parent;
}

inline Value delprop(Value parent, const Value& key) {
  if (!iskey(key)) return parent;
  if (parent.is_map()) {
    parent.as_map()->erase(strkey(key));
    return parent;
  }
  if (parent.is_list()) {
    auto l = parent.as_list();
    int idx;
    if (key.is_int()) idx = static_cast<int>(key.as_int());
    else if (key.is_string()) {
      try { idx = std::stoi(key.as_string()); } catch (...) { return parent; }
    } else if (key.is_double()) idx = static_cast<int>(key.as_double());
    else return parent;
    if (idx >= 0 && idx < static_cast<int>(l->size())) {
      l->erase(l->begin() + idx);
    }
    return parent;
  }
  return parent;
}

// ===========================================================================
// keysof / haskey / items
// ===========================================================================

inline std::vector<std::string> keysof(const Value& v) {
  std::vector<std::string> out;
  if (!v.is_node()) return out;
  if (v.is_map()) {
    for (const auto& [k, _] : *v.as_map()) out.push_back(k);
  } else {
    auto l = v.as_list();
    out.reserve(l->size());
    for (size_t i = 0; i < l->size(); i++) out.push_back(std::to_string(i));
  }
  return out;
}

inline bool haskey(const Value& v, const Value& key) {
  return !getprop(v, key).is_undef();
}

// items returns list of [key, value] pairs as Value-list-of-Value-lists.
inline Value items_v(const Value& v) {
  auto out = std::make_shared<List>();
  if (!v.is_node()) return Value(out);
  for (const auto& key : keysof(v)) {
    auto pair = std::make_shared<List>();
    pair->push_back(Value(key));
    pair->push_back(getprop(v, Value(key)));
    out->push_back(Value(std::move(pair)));
  }
  return Value(out);
}

inline std::vector<Value> items(const Value& v) {
  std::vector<Value> out;
  if (!v.is_node()) return out;
  for (const auto& key : keysof(v)) {
    auto pair = std::make_shared<List>();
    pair->push_back(Value(key));
    pair->push_back(getprop(v, Value(key)));
    out.push_back(Value(std::move(pair)));
  }
  return out;
}

// ===========================================================================
// flatten / filter
// ===========================================================================

inline Value flatten(const Value& list, int depth = 1) {
  if (!list.is_list()) return list;
  auto out = std::make_shared<List>();
  std::function<void(const std::shared_ptr<List>&, int)> rec =
      [&](const std::shared_ptr<List>& src, int d) {
        for (const auto& e : *src) {
          if (d > 0 && e.is_list()) rec(e.as_list(), d - 1);
          else out->push_back(e);
        }
      };
  rec(list.as_list(), depth);
  return Value(std::move(out));
}

using ItemCheck = std::function<bool(const Value& pair)>;

inline Value filter(const Value& v, const ItemCheck& check) {
  auto out = std::make_shared<List>();
  for (const auto& pair : items(v)) {
    if (check(pair)) {
      out->push_back(getprop(pair, Value(static_cast<int64_t>(1))));
    }
  }
  return Value(std::move(out));
}

// ===========================================================================
// slice / pad
// ===========================================================================
//
// slice mirrors TS lines 314–383. Negative indices count from end. For
// numbers, performs min/max bounding (start inclusive, end exclusive).

inline Value slice(const Value& val, const Value& start_v, const Value& end_v) {
  // Number case: bound between start and end-1.
  if (val.is_number()) {
    double n = val.as_double();
    int64_t lo = std::numeric_limits<int64_t>::min();
    int64_t hi = std::numeric_limits<int64_t>::max();
    if (start_v.is_number()) lo = start_v.as_int();
    if (end_v.is_number())   hi = end_v.as_int() - 1;
    if (n < lo) n = lo;
    if (n > hi) n = hi;
    if (val.is_int()) return Value(static_cast<int64_t>(n));
    return Value(n);
  }

  int vlen = static_cast<int>(size(val));
  bool has_start = !start_v.is_undef();
  bool has_end   = !end_v.is_undef();
  int start = has_start ? static_cast<int>(start_v.as_int()) : 0;
  int end   = has_end   ? static_cast<int>(end_v.as_int())   : vlen;

  if (has_end && !has_start) {
    start = 0;
    has_start = true;  // proceed into slice block even if only end was given
  }

  if (has_start) {
    if (start < 0) {
      end = vlen + start;
      if (end < 0) end = 0;
      start = 0;
    } else if (has_end) {
      if (end < 0) {
        end = vlen + end;
        if (end < 0) end = 0;
      } else if (vlen < end) {
        end = vlen;
      }
    } else {
      end = vlen;
    }
    if (vlen < start) start = vlen;

    if (start >= 0 && start <= end && end <= vlen) {
      if (val.is_list()) {
        auto src = val.as_list();
        auto out = std::make_shared<List>(src->begin() + start, src->begin() + end);
        return Value(std::move(out));
      }
      if (val.is_string()) {
        return Value(val.as_string().substr(start, end - start));
      }
    } else {
      if (val.is_list())   return Value(std::make_shared<List>());
      if (val.is_string()) return Value(std::string(""));
    }
  }
  return val;
}

inline std::string pad(const Value& v, int padding = 44, const std::string& padchar = " ") {
  std::string s = v.is_string() ? v.as_string() : stringify(v);
  std::string pc = padchar.empty() ? std::string(" ") : padchar.substr(0, 1);
  if (padding >= 0) {
    if (static_cast<int>(s.size()) < padding) {
      s.append(padding - s.size(), pc[0]);
    }
    return s;
  }
  int need = -padding - static_cast<int>(s.size());
  if (need > 0) {
    return std::string(need, pc[0]) + s;
  }
  return s;
}

// Convenience overload: pad with default args using Value parameters.
inline std::string pad(const Value& v, const Value& padding_v, const Value& padchar_v = Value::undef()) {
  int p = padding_v.is_number() ? static_cast<int>(padding_v.as_int()) : 44;
  std::string pc = padchar_v.is_string() ? padchar_v.as_string() : " ";
  return pad(v, p, pc);
}

// ===========================================================================
// escre / escurl / replace / join
// ===========================================================================

inline std::string escre(const Value& v) {
  std::string s = v.is_string() ? v.as_string() : (v.is_undef() ? "" : stringify(v));
  return std::regex_replace(s, R_ESCAPE_REGEXP(), "\\$&");
}

inline std::string escurl(const Value& v) {
  if (v.is_undef()) return "";
  std::string s = v.is_string() ? v.as_string() : stringify(v);
  std::ostringstream out;
  out.fill('0');
  out << std::hex;
  for (unsigned char c : s) {
    if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
      out << c;
    } else {
      out << '%' << std::uppercase << std::setw(2) << static_cast<int>(c);
      out << std::nouppercase;
    }
  }
  return out.str();
}

// JS-style scalar -> string: integer-valued doubles render without ".0".
inline std::string js_string(const Value& v) {
  if (v.is_undef() || v.is_null()) return "null";
  if (v.is_bool())   return v.as_bool() ? "true" : "false";
  if (v.is_int())    return std::to_string(v.as_int());
  if (v.is_double()) {
    double d = v.as_double();
    if (std::isfinite(d) && std::floor(d) == d) {
      return std::to_string(static_cast<int64_t>(d));
    }
    std::ostringstream oss;
    oss << d;
    return oss.str();
  }
  if (v.is_string()) return v.as_string();
  return stringify(v);
}

inline std::string join(const Value& arr, const std::string& sep = ",", bool url = false) {
  if (!arr.is_list()) return "";
  // Filter to non-empty strings.
  std::vector<std::string> parts;
  auto src = arr.as_list();
  for (size_t i = 0; i < src->size(); i++) {
    const Value& v = (*src)[i];
    if (!v.is_string() || v.as_string().empty()) continue;
    parts.push_back(v.as_string());
  }
  size_t sarr = parts.size();
  std::string sepre = sep.size() == 1 ? std::regex_replace(sep, R_ESCAPE_REGEXP(), "\\$&") : "";

  std::vector<std::string> cleaned;
  for (size_t i = 0; i < parts.size(); i++) {
    std::string s = parts[i];
    if (!sepre.empty()) {
      if (url && i == 0) {
        s = std::regex_replace(s, std::regex(sepre + "+$"), "");
      } else {
        if (i > 0) s = std::regex_replace(s, std::regex("^" + sepre + "+"), "");
        if (i < sarr - 1 || !url) {
          s = std::regex_replace(s, std::regex(sepre + "+$"), "");
        }
        s = std::regex_replace(s, std::regex("([^" + sepre + "])" + sepre + "+([^" + sepre + "])"),
                               std::string("$1") + sep + "$2");
      }
    }
    if (!s.empty()) cleaned.push_back(s);
  }
  std::string out;
  for (size_t i = 0; i < cleaned.size(); i++) {
    if (i > 0) out += sep;
    out += cleaned[i];
  }
  return out;
}

inline std::string join(const Value& arr, const Value& sep_v, const Value& url_v = Value::undef()) {
  std::string sep = sep_v.is_string() ? sep_v.as_string() : ",";
  bool url = url_v.is_bool() ? url_v.as_bool() : false;
  return join(arr, sep, url);
}

// ===========================================================================
// jsonify / stringify / pathify
// ===========================================================================

inline std::string jsonify(const Value& v, int indent = 2) {
  if (v.is_undef()) return "null";
  try {
    return to_njson(v).dump(indent < 0 ? -1 : indent);
  } catch (...) {
    return "__JSONIFY_FAILED__";
  }
}

inline std::string jsonify(const Value& v, const Value& flags) {
  int indent = 2;
  int offset = 0;
  if (flags.is_map()) {
    Value iv = getprop(flags, Value("indent"));
    Value ov = getprop(flags, Value("offset"));
    if (iv.is_int()) indent = static_cast<int>(iv.as_int());
    if (ov.is_int()) offset = static_cast<int>(ov.as_int());
  }
  std::string out = jsonify(v, indent);
  if (offset > 0 && out.find('\n') != std::string::npos) {
    std::string pad_str(offset, ' ');
    std::string padded;
    bool first = true;
    size_t pos = 0;
    while (pos < out.size()) {
      size_t nl = out.find('\n', pos);
      std::string line = (nl == std::string::npos) ? out.substr(pos) : out.substr(pos, nl - pos);
      if (first) { padded += line; first = false; }
      else padded += "\n" + pad_str + line;
      if (nl == std::string::npos) break;
      pos = nl + 1;
    }
    out = padded;
  }
  return out;
}

// stringify renders a Value in a JSON-ish form, but with no quotes around
// strings (mirrors TS stringify which strips quotes for human friendliness).
inline std::string stringify(const Value& v, int maxlen) {
  std::string valstr;
  if (v.is_undef()) return "";
  if (v.is_string()) {
    valstr = v.as_string();
  } else {
    try {
      // Use to_njson to dump with sorted keys for stable output, then strip
      // quotes from the result. Mirrors TS's stringify.
      nlohmann::json j = to_njson(v);
      valstr = j.dump();
      // Strip double-quotes (TS regex /"/g).
      std::string out;
      out.reserve(valstr.size());
      for (char c : valstr) if (c != '"') out.push_back(c);
      valstr = out;
    } catch (...) {
      valstr = "__STRINGIFY_FAILED__";
    }
  }
  if (maxlen > 0 && static_cast<int>(valstr.size()) > maxlen) {
    if (maxlen >= 3) {
      return valstr.substr(0, maxlen - 3) + "...";
    }
    return valstr.substr(0, maxlen);
  }
  return valstr;
}

inline std::string pathify(const Value& v, int startin, int endin) {
  std::vector<std::string> parts;
  bool valid = false;
  if (v.is_list()) {
    valid = true;
    for (const auto& e : *v.as_list()) {
      if (iskey(e)) {
        if (e.is_int()) parts.push_back(std::to_string(e.as_int()));
        else if (e.is_double()) parts.push_back(std::to_string(static_cast<int64_t>(std::floor(e.as_double()))));
        else {
          std::string s = e.as_string();
          // Strip dots — TS regex /\./g.
          std::string filtered;
          for (char c : s) if (c != '.') filtered += c;
          parts.push_back(filtered);
        }
      }
    }
  } else if (v.is_string()) {
    valid = true;
    parts.push_back(v.as_string());
  } else if (v.is_number()) {
    valid = true;
    parts.push_back(v.is_int() ? std::to_string(v.as_int())
                                : std::to_string(static_cast<int64_t>(std::floor(v.as_double()))));
  }

  int start = std::max(0, startin);
  int end   = std::max(0, endin);
  if (valid) {
    int total = static_cast<int>(parts.size());
    int new_end = total - end;
    if (new_end < start) new_end = start;
    if (new_end > total) new_end = total;
    std::vector<std::string> sliced(parts.begin() + std::min(start, total),
                                    parts.begin() + new_end);
    if (sliced.empty()) return "<root>";
    std::string out;
    for (size_t i = 0; i < sliced.size(); i++) {
      if (i > 0) out += ".";
      out += sliced[i];
    }
    return out;
  }
  std::string s = "<unknown-path";
  if (!v.is_undef()) {
    s += ":" + stringify(v, 47);
  }
  s += ">";
  return s;
}

// ===========================================================================
// jm / jt builders
// ===========================================================================

inline Value jm(std::initializer_list<Value> kv) {
  auto m = std::shared_ptr<Map>(new Map());
  auto it = kv.begin();
  size_t i = 0;
  while (it != kv.end()) {
    std::string k = it->is_string() ? it->as_string() : stringify(*it);
    if (k.empty()) k = "$KEY" + std::to_string(i);
    ++it; i++;
    Value v = (it != kv.end()) ? *it : Value(nullptr);
    if (it != kv.end()) { ++it; i++; }
    m->set(k, v);
  }
  return Value(std::move(m));
}

inline Value jt(std::initializer_list<Value> v) {
  auto l = std::make_shared<List>(v.begin(), v.end());
  return Value(std::move(l));
}

// ===========================================================================
// walk
// ===========================================================================
//
// Depth-first walk, applying optional `before` (on descend) and `after`
// (on ascend) callbacks. Mirrors TS walk lines 915–975.

using WalkApply = std::function<Value(
    const Value& key,
    const Value& val,
    const Value& parent,
    const std::vector<std::string>& path)>;

namespace detail {

inline Value walk_descend(
    Value val,
    const WalkApply& before,
    const WalkApply& after,
    int maxdepth,
    const Value& key,
    const Value& parent,
    std::vector<std::string>& path) {
  Value out = before ? before(key, val, parent, path) : val;
  int depth = static_cast<int>(path.size());
  if (maxdepth == 0 || (maxdepth > 0 && maxdepth <= depth)) {
    // Match TS walk: do NOT fire `after` on the maxdepth early-return.
    return out;
  }
  if (isnode(out)) {
    auto entries = items(out);
    for (auto& pair : entries) {
      auto pl = pair.as_list();
      Value ckey = (*pl)[0];
      Value child = (*pl)[1];
      path.push_back(strkey(ckey));
      Value newchild = walk_descend(child, before, after, maxdepth, ckey, out, path);
      out = setprop(out, ckey, newchild);
      path.pop_back();
    }
  }
  if (after) out = after(key, out, parent, path);
  return out;
}

}  // namespace detail

inline Value walk_v(const Value& val, WalkApply before, WalkApply after, int maxdepth) {
  std::vector<std::string> path;
  return detail::walk_descend(val, before, after, maxdepth,
                              Value::undef(), Value::undef(), path);
}

inline Value walk_v(const Value& val, WalkApply before) {
  return walk_v(val, before, nullptr, MAXDEPTH);
}

// ===========================================================================
// merge
// ===========================================================================
//
// Deep merge a list of values; later values win, nodes override scalars,
// node kinds (list vs map) do not merge. The first element is modified.
// Mirrors TS lines 982–1098.

inline Value merge_v(const Value& list, int maxdepth) {
  int md = std::max(0, std::min(maxdepth, MAXDEPTH));
  if (!list.is_list()) return list;
  auto src = list.as_list();
  if (src->empty()) return Value(nullptr);
  if (src->size() == 1) return (*src)[0];

  Value out = (*src)[0];
  if (out.is_undef()) {
    out = Value(std::shared_ptr<Map>(new Map()));
  }

  for (size_t oI = 1; oI < src->size(); oI++) {
    Value obj = (*src)[oI];
    if (!isnode(obj)) {
      out = obj;
      continue;
    }
    // Scratch arrays of cur/dst per depth (TS uses pI to index).
    std::vector<Value> cur(MAXDEPTH + 2, Value::undef());
    std::vector<Value> dst(MAXDEPTH + 2, Value::undef());
    cur[0] = out;
    dst[0] = out;

    WalkApply before = [&](const Value& key, const Value& val,
                           const Value& parent, const std::vector<std::string>& path) -> Value {
      int pI = static_cast<int>(path.size());
      if (md <= pI) {
        if (!key.is_undef()) {
          cur[pI - 1] = setprop(cur[pI - 1], key, val);
        }
        return val;
      }
      if (!isnode(val)) {
        cur[pI] = val;
        return val;
      }
      // Descending into a node.
      if (pI > 0 && !key.is_undef()) {
        dst[pI] = getprop(dst[pI - 1], key);
        if (dst[pI].is_undef()) dst[pI] = Value::undef();
      }
      Value tval = dst[pI];
      if (tval.is_undef() && (typify(val) & T_instance) == 0) {
        cur[pI] = val.is_list() ? Value(std::make_shared<List>())
                                 : Value(std::shared_ptr<Map>(new Map()));
      } else if (typify(val) == typify(tval)) {
        cur[pI] = tval;
      } else {
        cur[pI] = val;
        return Value::undef();  // skip descent
      }
      return val;
    };

    WalkApply after = [&](const Value& key, const Value& val_unused,
                          const Value& parent, const std::vector<std::string>& path) -> Value {
      int cI = static_cast<int>(path.size());
      if (key.is_undef() || cI <= 0) {
        return cur[0];
      }
      Value value = cur[cI];
      cur[cI - 1] = setprop(cur[cI - 1], key, value);
      return value;
    };

    walk_v(obj, before, after, md);
    out = cur[0];
  }

  if (md == 0) {
    Value last = src->back();
    if (last.is_list())     out = Value(std::make_shared<List>());
    else if (last.is_map()) out = Value(std::shared_ptr<Map>(new Map()));
    else                    out = last;
  }
  return out;
}

// ===========================================================================
// pathParts — shared helper for getpath / setpath
// ===========================================================================

namespace detail {
inline std::vector<std::string> path_parts(const Value& path) {
  std::vector<std::string> out;
  if (path.is_string()) {
    const std::string& s = path.as_string();
    if (s.empty()) {
      out.push_back("");
      return out;
    }
    size_t pos = 0;
    while (pos <= s.size()) {
      size_t dot = s.find('.', pos);
      if (dot == std::string::npos) {
        out.push_back(s.substr(pos));
        break;
      }
      out.push_back(s.substr(pos, dot - pos));
      pos = dot + 1;
    }
    return out;
  }
  if (path.is_list()) {
    auto l = path.as_list();
    for (const auto& e : *l) {
      if (e.is_string()) out.push_back(e.as_string());
      else if (e.is_number()) out.push_back(strkey(e));
      else out.push_back(strkey(e));
    }
    return out;
  }
  if (path.is_number()) {
    out.push_back(strkey(path));
    return out;
  }
  return {};
}
}  // namespace detail

// ===========================================================================
// setpath
// ===========================================================================

inline Value setpath_v(const Value& store, const Value& path, const Value& val) {
  std::vector<std::string> parts;
  bool path_is_list = path.is_list();
  if (path.is_undef() || path.is_null()) return Value::undef();
  if (path.is_string()) parts = detail::path_parts(path);
  else if (path.is_list()) parts = detail::path_parts(path);
  else if (path.is_number()) parts.push_back(strkey(path));
  else return Value::undef();
  if (parts.empty()) return Value::undef();

  // String paths only create maps (TS: "Use a string list to create list parts").
  // For list paths, decide list-vs-map by whether the next part is integer.
  Value parent = store;
  for (size_t i = 0; i + 1 < parts.size(); i++) {
    Value next = getprop(parent, Value(parts[i]));
    if (!isnode(next)) {
      bool make_list = false;
      if (path_is_list) {
        // Check the original list for whether parts[i+1] came from a number.
        Value el = getprop(path, Value(static_cast<int64_t>(i + 1)));
        if (el.is_number()) make_list = true;
      }
      next = make_list ? Value(std::make_shared<List>())
                       : Value(std::shared_ptr<Map>(new Map()));
      setprop(parent, Value(parts[i]), next);
    }
    parent = next;
  }
  Value last_key(parts.back());
  if (is_delete(val)) {
    delprop(parent, last_key);
  } else {
    setprop(parent, last_key, val);
  }
  return parent;
}

// ===========================================================================
// Injection
// ===========================================================================

class Injection {
 public:
  int mode = M_VAL;
  bool full = false;
  int keyI = 0;
  std::shared_ptr<std::vector<std::string>> keys;  // shared with prior
  std::string key;
  Value val;
  Value parent;
  std::vector<std::string> path;
  std::shared_ptr<std::vector<Value>> nodes;
  Injector handler;
  std::shared_ptr<std::vector<Value>> errs;
  std::shared_ptr<Map> meta;
  Value dparent;
  std::vector<std::string> dpath;
  std::string base;
  Modify modify;
  Injection* prior = nullptr;
  Value extra;

  Injection(const Value& val_in, const Value& parent_in)
      : val(val_in), parent(parent_in) {
    keys = std::make_shared<std::vector<std::string>>();
    keys->push_back(S_DTOP());
    key = S_DTOP();
    path.push_back(S_DTOP());
    nodes = std::make_shared<std::vector<Value>>();
    nodes->push_back(parent_in);
    dparent = Value::undef();
    dpath.push_back(S_DTOP());
    errs = std::make_shared<std::vector<Value>>();
    meta = std::shared_ptr<Map>(new Map());
    base = S_DTOP();
  }

  Value descend() {
    int64_t d = 0;
    if (auto* m = meta.get()) {
      Value* dv = m->find("__d");
      if (dv && dv->is_int()) d = dv->as_int();
      m->set("__d", Value(d + 1));
    }
    if (path.size() < 2) return dparent;
    const std::string& parentkey = path[path.size() - 2];

    if (dparent.is_undef()) {
      if (dpath.size() > 1) {
        dpath.push_back(parentkey);
      }
    } else {
      dparent = getprop(dparent, Value(parentkey));
      std::string lastpart = dpath.empty() ? "" : dpath.back();
      std::string marker = "$:" + parentkey;
      if (marker == lastpart) {
        if (!dpath.empty()) dpath.pop_back();
      } else {
        dpath.push_back(parentkey);
      }
    }
    return dparent;
  }

  std::unique_ptr<Injection> child(int keyI_in,
                                    const std::shared_ptr<std::vector<std::string>>& keys_in) {
    std::string ck = strkey(Value((*keys_in)[keyI_in]));
    Value child_val = getprop(val, Value(ck));
    auto cinj = std::unique_ptr<Injection>(new Injection(child_val, val));
    cinj->keyI = keyI_in;
    cinj->keys = keys_in;       // shared reference
    cinj->key = ck;
    cinj->path = path;          // copy
    cinj->path.push_back(ck);
    cinj->nodes = std::make_shared<std::vector<Value>>(*nodes);
    cinj->nodes->push_back(val);
    cinj->mode = mode;
    cinj->handler = handler;
    cinj->modify = modify;
    cinj->base = base;
    cinj->meta = meta;          // shared reference
    cinj->errs = errs;          // shared reference
    cinj->prior = this;
    cinj->dpath = dpath;        // copy
    cinj->dparent = dparent;
    return cinj;
  }

  Value setval(const Value& v) { return setval(v, 0); }

  Value setval(const Value& v, int ancestor) {
    Value pp;
    if (ancestor < 2) {
      if (v.is_undef()) {
        pp = delprop(parent, Value(key));
        parent = pp;
      } else {
        pp = setprop(parent, Value(key), v);
      }
    } else {
      // Use nodes[-ancestor] and path[-ancestor]
      int idx_n = static_cast<int>(nodes->size()) - ancestor;
      int idx_p = static_cast<int>(path.size()) - ancestor;
      if (idx_n < 0 || idx_p < 0) return Value::undef();
      Value aval = (*nodes)[idx_n];
      Value akey(path[idx_p]);
      if (v.is_undef()) {
        pp = delprop(aval, akey);
      } else {
        pp = setprop(aval, akey, v);
      }
    }
    return pp;
  }
};

// ===========================================================================
// getpath
// ===========================================================================

namespace detail {

inline Value getpath_inner(
    const Value& store, const Value& path,
    std::vector<std::string>& parts,
    Injection* inj);

}  // namespace detail

inline Value getpath_v(const Value& store, const Value& path, Injection* inj) {
  std::vector<std::string> parts;
  bool valid_path = false;
  if (path.is_string())      { parts = detail::path_parts(path); valid_path = true; }
  else if (path.is_list())   { parts = detail::path_parts(path); valid_path = true; }
  else if (path.is_number()) { parts.push_back(strkey(path));    valid_path = true; }
  // Note: undef / null / bool / map paths are invalid (matches TS lines 1147-1153).
  if (!valid_path) return Value::undef();
  Value val = detail::getpath_inner(store, path, parts, inj);
  if (inj && inj->handler) {
    std::string ref = path.is_undef() ? "" : pathify(path);
    val = inj->handler(*inj, val, ref, store);
  }
  return val;
}

namespace detail {

inline Value getpath_inner(
    const Value& store, const Value& path,
    std::vector<std::string>& parts,
    Injection* inj) {
  if (path.is_undef() || path.is_null()) {
    return store;
  }

  Value base_v = inj ? Value(inj->base) : Value::undef();
  Value src = getprop(store, base_v, store);
  Value dparent = inj ? inj->dparent : Value::undef();
  std::vector<std::string>* dpath = inj ? &inj->dpath : nullptr;

  int numparts = static_cast<int>(parts.size());
  Value val = store;

  if (numparts == 0 || (numparts == 1 && parts[0].empty())) {
    return src;
  }

  // Function shortcut: if only one part and it directly resolves to a function
  // in store, return it.
  if (numparts == 1) {
    val = getprop(store, Value(parts[0]));
  }

  if (!isfunc(val)) {
    val = src;

    // Meta path syntax `<root>$=value` / `<root>$~spec`.
    {
      std::smatch m;
      if (inj && inj->meta && std::regex_match(parts[0], m, R_META_PATH())) {
        val = getprop(Value(inj->meta), Value(m[1].str()));
        parts[0] = m[3].str();
      }
    }

    for (int pI = 0; !val.is_undef() && !val.is_null() && pI < numparts; pI++) {
      std::string part = parts[pI];

      if (inj && part == S_DKEY()) {
        part = inj->key;
      } else if (inj && part.size() > 5 && part.substr(0, 5) == "$GET:") {
        std::string subpath = part.substr(5, part.size() - 6);
        Value res = getpath_v(src, Value(subpath));
        part = stringify(res);
      } else if (inj && part.size() > 5 && part.substr(0, 5) == "$REF:") {
        std::string subpath = part.substr(5, part.size() - 6);
        Value spec = getprop(store, Value(S_DSPEC()));
        if (spec.is_injector()) {
          // Supplier-like: call the injector with a synthetic Injection.
          // (TS uses () => origspec; emulated here as Injector taking an inj.)
          Injection synth(Value::undef(), Value::undef());
          spec = spec.as_injector()(synth, Value::undef(), "$SPEC", store);
        }
        if (!spec.is_undef()) {
          Value res = getpath_v(spec, Value(subpath));
          part = stringify(res);
        }
      } else if (inj && part.size() > 6 && part.substr(0, 6) == "$META:") {
        std::string subpath = part.substr(6, part.size() - 7);
        Value res = getpath_v(Value(inj->meta), Value(subpath));
        part = stringify(res);
      }

      // $$ -> $
      part = std::regex_replace(part, R_DOUBLE_DOLLAR(), "$");

      if (part.empty()) {
        int ascends = 0;
        while (1 + pI < numparts && parts[1 + pI].empty()) {
          ascends++;
          pI++;
        }
        if (inj && ascends > 0) {
          if (pI == numparts - 1) ascends--;
          if (ascends == 0) {
            val = dparent;
          } else if (dpath) {
            int dlen = static_cast<int>(dpath->size());
            int cut = dlen - ascends;
            if (cut < 0) cut = 0;
            std::vector<std::string> fullpath(dpath->begin(),
                                              dpath->begin() + cut);
            for (int j = pI + 1; j < numparts; j++) {
              fullpath.push_back(parts[j]);
            }
            if (ascends <= dlen) {
              auto fp = std::make_shared<List>();
              for (auto& p : fullpath) fp->push_back(Value(p));
              val = getpath_v(store, Value(std::move(fp)));
            } else {
              val = Value::undef();
            }
            break;
          }
        } else {
          val = dparent;
        }
      } else {
        val = getprop(val, Value(part));
      }
    }
  }
  return val;
}

}  // namespace detail

// ===========================================================================
// _invalidTypeMsg / _injectstr / _injecthandler
// ===========================================================================

inline std::string invalid_type_msg(const std::vector<std::string>& path,
                                     const std::string& need_type,
                                     int vt, const Value& v,
                                     const std::string& whence = "") {
  (void)whence;
  std::string vs = (v.is_undef() || v.is_null()) ? "no value" : stringify(v);
  std::string out = "Expected ";
  if (path.size() > 1) {
    auto pl = std::make_shared<List>();
    for (auto& p : path) pl->push_back(Value(p));
    out += "field " + pathify(Value(pl), 1, 0) + " to be ";
  }
  out += need_type + ", but found ";
  if (!v.is_undef() && !v.is_null()) {
    out += typename_str(vt) + ": ";
  }
  out += vs + ".";
  return out;
}

inline std::string invalid_type_msg(const Value& path_v,
                                     const std::string& need_type,
                                     int vt, const Value& v,
                                     const std::string& whence = "") {
  std::vector<std::string> p;
  if (path_v.is_list()) {
    for (const auto& e : *path_v.as_list()) p.push_back(strkey(e));
  } else if (path_v.is_string()) {
    p.push_back(path_v.as_string());
  }
  return invalid_type_msg(p, need_type, vt, v, whence);
}

// MODENAME / PLACEMENT helpers.
inline std::string modename(int mode) {
  switch (mode) {
    case M_VAL: return "val";
    case M_KEYPRE: return "key:pre";
    case M_KEYPOST: return "key:post";
    default: return "";
  }
}
inline std::string placement(int mode) {
  switch (mode) {
    case M_VAL: return "value";
    case M_KEYPRE:
    case M_KEYPOST: return "key";
    default: return "";
  }
}

// _injecthandler: forward declared, defined below after Injection helpers.
inline Value injecthandler(Injection& inj, const Value& val,
                            const std::string& ref, const Value& store);

inline Value injectstr(const std::string& val, const Value& store, Injection* inj) {
  if (val.empty()) return Value(std::string(""));

  std::smatch m;
  if (std::regex_match(val, m, R_INJECTION_FULL())) {
    if (inj) inj->full = true;
    std::string pathref = m[1].str();
    if (pathref.size() > 3) {
      pathref = std::regex_replace(pathref, R_BT_ESCAPE(), "`");
      pathref = std::regex_replace(pathref, R_DS_ESCAPE(), "$");
    }
    return getpath_v(store, Value(pathref), inj);
  }

  // Partial replacement.
  auto begin = std::sregex_iterator(val.begin(), val.end(), R_INJECTION_PARTIAL());
  auto end = std::sregex_iterator();
  std::string out;
  size_t cursor = 0;
  for (auto it = begin; it != end; ++it) {
    auto pos = static_cast<size_t>(it->position(0));
    out.append(val, cursor, pos - cursor);
    std::string ref = (*it)[1].str();
    if (ref.size() > 3) {
      ref = std::regex_replace(ref, R_BT_ESCAPE(), "`");
      ref = std::regex_replace(ref, R_DS_ESCAPE(), "$");
    }
    if (inj) inj->full = false;
    Value found = getpath_v(store, Value(ref), inj);
    if (found.is_undef()) {
      // append nothing
    } else if (found.is_null()) {
      out += "null";
    } else if (found.is_string()) {
      out += found.as_string();
    } else {
      try { out += to_njson(found).dump(); } catch (...) { out += stringify(found); }
    }
    cursor = pos + it->length(0);
  }
  out.append(val, cursor, val.size() - cursor);

  Value out_val(out);
  if (inj && inj->handler) {
    inj->full = true;
    out_val = inj->handler(*inj, out_val, val, store);
  }
  return out_val;
}

inline Value injecthandler(Injection& inj, const Value& val,
                            const std::string& ref, const Value& store) {
  Value out = val;
  bool iscmd = isfunc(val) && (ref.empty() || ref[0] == '$');
  if (iscmd) {
    if (val.is_injector()) {
      out = val.as_injector()(inj, val, ref, store);
    }
  } else if (inj.mode == M_VAL && inj.full) {
    inj.setval(val);
  }
  return out;
}

// ===========================================================================
// checkPlacement / injectorArgs / injectChild
// ===========================================================================

inline bool checkPlacement(int modes, const std::string& ijname,
                           int parent_types, Injection& inj) {
  if ((modes & inj.mode) == 0) {
    std::string allowed;
    int first = 1;
    for (int m : {M_KEYPRE, M_KEYPOST, M_VAL}) {
      if (modes & m) {
        if (!first) allowed += ",";
        allowed += placement(m);
        first = 0;
      }
    }
    inj.errs->push_back(Value("$" + ijname + ": invalid placement as " +
                               placement(inj.mode) + ", expected: " + allowed + "."));
    return false;
  }
  if (parent_types != 0) {
    int ptype = typify(inj.parent);
    if ((parent_types & ptype) == 0) {
      inj.errs->push_back(Value(
          "$" + ijname + ": invalid placement in parent " +
          typename_str(ptype) + ", expected: " + typename_str(parent_types) + "."));
      return false;
    }
  }
  return true;
}

// Returns a vector of size argTypes.size() + 1.
// [0] is error message (empty string if ok), [1..] are args.
inline std::vector<Value> injectorArgs(const std::vector<int>& arg_types,
                                       const std::vector<Value>& args) {
  std::vector<Value> out(arg_types.size() + 1);
  out[0] = Value::undef();
  for (size_t i = 0; i < arg_types.size(); i++) {
    Value arg = i < args.size() ? args[i] : Value::undef();
    int argType = typify(arg);
    if ((arg_types[i] & argType) == 0) {
      out[0] = Value("invalid argument: " + stringify(arg, 22) +
                     " (" + typename_str(argType) + " at position " +
                     std::to_string(1 + i) + ") is not of type: " +
                     typename_str(arg_types[i]) + ".");
      return out;
    }
    out[i + 1] = arg;
  }
  return out;
}

// Forward decl: inject is defined below.
inline std::unique_ptr<Injection> injectChild_helper(
    const Value& child, const Value& store, Injection& inj);

inline Injection& injectChild(const Value& child, const Value& store,
                               Injection& inj);  // signature only; inline below

// ===========================================================================
// inject
// ===========================================================================

inline Value inject(const Value& val, const Value& store, Injection* injdef) {
  std::unique_ptr<Injection> inj_owner;
  Injection* inj = nullptr;
  bool isInitial = (injdef == nullptr || injdef->prior == nullptr);

  if (isInitial) {
    auto wrap = std::shared_ptr<Map>(new Map());
    wrap->set(S_DTOP(), val);
    inj_owner.reset(new Injection(val, Value(wrap)));
    inj_owner->dparent = store;
    Value errs_v = getprop(store, Value(S_DERRS()));
    if (errs_v.is_list()) {
      // Replace shared errs with the store's list (by transferring pointers).
      // We can't directly assign vector<Value>; convert.
      // Store list-of-values share semantics: keep using inj's errs; but we
      // need the same list as the store's $ERRS so the test runner sees them.
      // Quickly: inj->errs = a fresh vec, then push references via the
      // `Value(list)` storage. For simplicity, swap our shared_ptr for the
      // List behind store.$ERRS. We store via shared_ptr<vector<Value>>,
      // not shared_ptr<List>; bridge by reusing the underlying vector.
      // Simplest: mirror — use the store's list directly when possible.
      auto sl = errs_v.as_list();
      // Replace inj_owner->errs with a fresh vec backed by sl's elements;
      // append back to sl when an error is added. To keep semantics simple,
      // the errs list is kept as an alias: every push to inj_owner->errs is
      // also pushed to sl. We achieve this by sharing via a wrapper:
      // assign inj_owner->errs to a new vec that mirrors sl. For now,
      // use sl's vector as the source of truth.
      //
      // Simpler approach: don't share; copy on initial setup, push back at
      // end. The corpus tests pass errs externally via the options map, so
      // this is wired in transform()/validate() instead.
      (void)sl;
    }
    inj_owner->meta->set("__d", Value(int64_t(0)));

    if (injdef) {
      if (injdef->modify) inj_owner->modify = injdef->modify;
      if (!injdef->extra.is_undef()) inj_owner->extra = injdef->extra;
      if (injdef->meta) inj_owner->meta = injdef->meta;
      if (injdef->handler) inj_owner->handler = injdef->handler;
      if (!injdef->base.empty()) inj_owner->base = injdef->base;
      if (!injdef->dparent.is_undef()) inj_owner->dparent = injdef->dparent;
      if (injdef->errs && !injdef->errs->empty()) inj_owner->errs = injdef->errs;
      // Always honor an external errs list pointer if one is supplied.
      if (injdef->errs) inj_owner->errs = injdef->errs;
    }
    if (!inj_owner->handler) {
      inj_owner->handler = injecthandler;
    }
    // Top-level wrapper participates in nodes stack.
    inj_owner->nodes->clear();
    inj_owner->nodes->push_back(Value(wrap));
    inj = inj_owner.get();
  } else {
    inj = injdef;
  }

  inj->descend();

  Value cur = val;

  if (isnode(cur) && !cur.is_sentinel()) {
    auto node_keys_vec = keysof(cur);
    auto nodekeys = std::make_shared<std::vector<std::string>>();

    if (cur.is_map()) {
      // $-suffix ordering: non-$ first, then $.
      for (const auto& k : node_keys_vec) {
        if (k.find('$') == std::string::npos) nodekeys->push_back(k);
      }
      for (const auto& k : node_keys_vec) {
        if (k.find('$') != std::string::npos) nodekeys->push_back(k);
      }
    } else {
      *nodekeys = node_keys_vec;
    }

    inj->val = cur;

    for (size_t nkI = 0; nkI < nodekeys->size(); nkI++) {
      auto cinj_owner = inj->child(static_cast<int>(nkI), nodekeys);
      Injection* cinj = cinj_owner.get();
      std::string nodekey = cinj->key;
      cinj->mode = M_KEYPRE;

      Value prekey = injectstr(nodekey, store, cinj);
      nkI = cinj->keyI;
      nodekeys = cinj->keys;

      if (!prekey.is_undef()) {
        cinj->val = getprop(cur, prekey);
        cinj->mode = M_VAL;
        inject(cinj->val, store, cinj);

        nkI = cinj->keyI;
        nodekeys = cinj->keys;

        cinj->mode = M_KEYPOST;
        injectstr(nodekey, store, cinj);

        nkI = cinj->keyI;
        nodekeys = cinj->keys;
      }
    }
  } else if (cur.is_string()) {
    inj->mode = M_VAL;
    Value newVal = injectstr(cur.as_string(), store, inj);
    if (!is_skip(newVal)) {
      inj->setval(newVal);
    }
    cur = newVal;
  }

  if (inj->modify && !is_skip(cur)) {
    Value mkey(inj->key);
    Value mparent = inj->parent;
    Value mval = getprop(mparent, mkey);
    inj->modify(mval, mkey, mparent, *inj, store);
  }

  inj->val = cur;
  return getprop(inj->parent, Value(S_DTOP()));
}

// injectChild definition (after inject is declared).
inline Injection& injectChild(const Value& child, const Value& store,
                               Injection& inj) {
  static thread_local std::unique_ptr<Injection> hold;
  Injection* cinj = &inj;
  std::unique_ptr<Injection> owner;
  if (inj.prior) {
    if (inj.prior->prior) {
      owner = inj.prior->prior->child(inj.prior->keyI, inj.prior->keys);
      owner->val = child;
      setprop(owner->parent, Value(inj.prior->key), child);
    } else {
      owner = inj.prior->child(inj.keyI, inj.keys);
      owner->val = child;
      setprop(owner->parent, Value(inj.key), child);
    }
    cinj = owner.get();
  }
  inject(child, store, cinj);
  if (owner) {
    hold = std::move(owner);
  }
  return *cinj;
}

// ===========================================================================
// Transform injectors
// ===========================================================================

namespace transforms {

inline Value DELETE_FN(Injection& inj, const Value& val,
                        const std::string& ref, const Value& store) {
  inj.setval(Value::undef());
  return Value::undef();
}

inline Value COPY_FN(Injection& inj, const Value& val,
                      const std::string& ref, const Value& store) {
  if (!checkPlacement(M_VAL, "COPY", T_any, inj)) return Value::undef();
  Value out = getprop(inj.dparent, Value(inj.key));
  inj.setval(out);
  return out;
}

inline Value KEY_FN(Injection& inj, const Value& val,
                     const std::string& ref, const Value& store) {
  if (inj.mode != M_VAL) return Value::undef();
  Value keyspec = getprop(inj.parent, Value(S_BKEY()));
  if (!keyspec.is_undef()) {
    delprop(inj.parent, Value(S_BKEY()));
    return getprop(inj.dparent, keyspec);
  }
  Value anno = getprop(inj.parent, Value(S_BANNO()));
  Value alt = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
  return getprop(anno, Value("KEY"), alt);
}

inline Value ANNO_FN(Injection& inj, const Value& val,
                      const std::string& ref, const Value& store) {
  delprop(inj.parent, Value(S_BANNO()));
  return Value::undef();
}

inline Value MERGE_FN(Injection& inj, const Value& val,
                       const std::string& ref, const Value& store) {
  if (inj.mode == M_KEYPRE) return Value(inj.key);
  if (inj.mode != M_KEYPOST) return Value::undef();

  Value args = getprop(inj.parent, Value(inj.key));
  auto arg_list = std::make_shared<List>();
  if (args.is_list()) {
    for (const auto& e : *args.as_list()) arg_list->push_back(e);
  } else {
    arg_list->push_back(args);
  }
  inj.setval(Value::undef());

  auto merge_args = std::make_shared<List>();
  merge_args->push_back(inj.parent);
  for (const auto& a : *arg_list) merge_args->push_back(a);
  merge_args->push_back(clone(inj.parent));
  merge_v(Value(merge_args));
  return Value(inj.key);
}

// FORMATTER map (named formatters for $FORMAT).
inline std::unordered_map<std::string, std::function<Value(const Value&)>>& formatters() {
  static std::unordered_map<std::string, std::function<Value(const Value&)>> F;
  if (F.empty()) {
    auto deep_apply = [](const Value& v, std::function<Value(const Value&)> f) -> Value {
      std::function<Value(const Value&)> rec = [&](const Value& x) -> Value {
        if (x.is_list()) {
          auto out = std::make_shared<List>();
          for (const auto& e : *x.as_list()) out->push_back(rec(e));
          return Value(out);
        }
        if (x.is_map()) {
          auto out = std::shared_ptr<Map>(new Map());
          for (const auto& [k, e] : *x.as_map()) out->set(k, rec(e));
          return Value(out);
        }
        return f(x);
      };
      return rec(v);
    };
    F["identity"] = [](const Value& v) { return v; };
    F["upper"] = [deep_apply](const Value& v) {
      return deep_apply(v, [](const Value& x) -> Value {
        if (isnode(x)) return x;
        std::string s = js_string(x);
        for (auto& c : s) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        return Value(s);
      });
    };
    F["lower"] = [deep_apply](const Value& v) {
      return deep_apply(v, [](const Value& x) -> Value {
        if (isnode(x)) return x;
        std::string s = js_string(x);
        for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        return Value(s);
      });
    };
    F["string"] = [deep_apply](const Value& v) {
      return deep_apply(v, [](const Value& x) -> Value {
        if (isnode(x)) return x;
        return Value(js_string(x));
      });
    };
    F["number"] = [deep_apply](const Value& v) {
      return deep_apply(v, [](const Value& x) -> Value {
        if (isnode(x)) return x;
        if (x.is_number()) return x;
        try {
          double d = std::stod(js_string(x));
          if (std::isnan(d)) return Value(int64_t(0));
          if (std::floor(d) == d) return Value(static_cast<int64_t>(d));
          return Value(d);
        } catch (...) { return Value(int64_t(0)); }
      });
    };
    F["integer"] = [deep_apply](const Value& v) {
      return deep_apply(v, [](const Value& x) -> Value {
        if (isnode(x)) return x;
        try { return Value(static_cast<int64_t>(std::stod(js_string(x)))); }
        catch (...) { return Value(int64_t(0)); }
      });
    };
    F["concat"] = [](const Value& v) -> Value {
      if (!v.is_list()) return v;
      std::string out;
      for (const auto& e : *v.as_list()) {
        if (!isnode(e)) out += js_string(e);
      }
      return Value(out);
    };
  }
  return F;
}

inline Value FORMAT_FN(Injection& inj, const Value& val,
                        const std::string& ref, const Value& store) {
  // Truncate keys to single element.
  if (inj.keys && inj.keys->size() > 1) {
    inj.keys->resize(1);
  }
  if (inj.mode != M_VAL) return Value::undef();

  Value name = getprop(inj.parent, Value(int64_t(1)));
  Value child = getprop(inj.parent, Value(int64_t(2)));

  Value tkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
  Value target;
  if (inj.nodes && inj.nodes->size() >= 2) {
    target = (*inj.nodes)[inj.nodes->size() - 2];
  } else if (inj.nodes && !inj.nodes->empty()) {
    target = inj.nodes->back();
  }

  Injection& cinj = injectChild(child, store, inj);
  Value resolved = cinj.val;

  auto& F = formatters();
  std::string fname = name.is_string() ? name.as_string() : "";
  auto it = F.find(fname);
  if (it == F.end()) {
    inj.errs->push_back(Value("$FORMAT: unknown format: " + fname + "."));
    return Value::undef();
  }
  Value out = it->second(resolved);
  setprop(target, tkey, out);
  return out;
}

inline Value APPLY_FN(Injection& inj, const Value& val,
                       const std::string& ref, const Value& store) {
  if (!checkPlacement(M_VAL, "APPLY", T_list, inj)) return Value::undef();
  std::vector<Value> args;
  if (inj.parent.is_list()) {
    auto pl = inj.parent.as_list();
    for (size_t i = 1; i < pl->size(); i++) args.push_back((*pl)[i]);
  }
  auto checked = injectorArgs({T_function, T_any}, args);
  if (!checked[0].is_undef()) {
    inj.errs->push_back(Value("$APPLY: " + checked[0].as_string()));
    return Value::undef();
  }
  Value apply = checked[1];
  Value child = checked[2];

  Value tkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
  Value target;
  if (inj.nodes && inj.nodes->size() >= 2) {
    target = (*inj.nodes)[inj.nodes->size() - 2];
  } else if (inj.nodes && !inj.nodes->empty()) {
    target = inj.nodes->back();
  }

  Injection& cinj = injectChild(child, store, inj);
  Value resolved = cinj.val;

  Value out;
  if (apply.is_injector()) {
    out = apply.as_injector()(inj, resolved, ref, store);
  } else {
    out = Value::undef();
  }
  setprop(target, tkey, out);
  return out;
}

inline Value EACH_FN(Injection& inj, const Value& val,
                      const std::string& ref, const Value& store) {
  if (!checkPlacement(M_VAL, "EACH", T_list, inj)) return Value::undef();
  if (inj.keys && inj.keys->size() > 1) {
    inj.keys->resize(1);
  }
  std::vector<Value> args;
  if (inj.parent.is_list()) {
    auto pl = inj.parent.as_list();
    for (size_t i = 1; i < pl->size(); i++) args.push_back((*pl)[i]);
  }
  auto checked = injectorArgs({T_string, T_any}, args);
  if (!checked[0].is_undef()) {
    inj.errs->push_back(Value("$EACH: " + checked[0].as_string()));
    return Value::undef();
  }
  std::string srcpath = checked[1].as_string();
  Value child = checked[2];

  Value srcstore = getprop(store, Value(inj.base), store);
  Value src = getpath_v(srcstore, Value(srcpath), &inj);
  int srctype = typify(src);

  Value tkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
  Value target;
  if (inj.nodes && inj.nodes->size() >= 2) {
    target = (*inj.nodes)[inj.nodes->size() - 2];
  } else if (inj.nodes && !inj.nodes->empty()) {
    target = inj.nodes->back();
  }

  auto tval = std::make_shared<List>();
  if ((T_list & srctype) && src.is_list()) {
    auto sl = src.as_list();
    for (size_t i = 0; i < sl->size(); i++) tval->push_back(clone(child));
  } else if ((T_map & srctype) && src.is_map()) {
    auto sm = src.as_map();
    for (const auto& [k, v] : *sm) {
      Value cl = clone(child);
      auto anno = std::shared_ptr<Map>(new Map());
      auto keymap = std::shared_ptr<Map>(new Map());
      keymap->set("KEY", Value(k));
      anno->set(S_BANNO(), Value(keymap));
      auto args_l = std::make_shared<List>();
      args_l->push_back(cl);
      args_l->push_back(Value(anno));
      Value merged = merge_v(Value(args_l), 1);
      tval->push_back(merged);
    }
  }

  Value rval(std::make_shared<List>());

  if (!tval->empty()) {
    Value tcur;
    if (src.is_list()) {
      auto tcur_list = std::make_shared<List>();
      for (const auto& e : *src.as_list()) tcur_list->push_back(e);
      tcur = Value(tcur_list);
    } else if (src.is_map()) {
      auto tcur_list = std::make_shared<List>();
      for (const auto& [_, e] : *src.as_map()) tcur_list->push_back(e);
      tcur = Value(tcur_list);
    }

    std::string ckey = inj.path.size() >= 2 ? inj.path[inj.path.size() - 2] : "";

    std::vector<std::string> tpath(inj.path.begin(), inj.path.end() - 1);
    std::vector<std::string> dpath;
    dpath.push_back(S_DTOP());
    if (!srcpath.empty()) {
      // split srcpath on '.'
      size_t pos = 0;
      while (pos <= srcpath.size()) {
        size_t dot = srcpath.find('.', pos);
        if (dot == std::string::npos) { dpath.push_back(srcpath.substr(pos)); break; }
        dpath.push_back(srcpath.substr(pos, dot - pos));
        pos = dot + 1;
      }
    }
    dpath.push_back("$:" + ckey);

    auto tcur_map = std::shared_ptr<Map>(new Map());
    tcur_map->set(ckey, tcur);
    Value tcur_out(tcur_map);
    if (tpath.size() > 1) {
      std::string pkey = inj.path.size() >= 3 ? inj.path[inj.path.size() - 3] : S_DTOP();
      auto wrap = std::shared_ptr<Map>(new Map());
      wrap->set(pkey, tcur_out);
      tcur_out = Value(wrap);
      dpath.push_back("$:" + pkey);
    }

    auto single_keys = std::make_shared<std::vector<std::string>>();
    single_keys->push_back(ckey);
    auto tinj_owner = inj.child(0, single_keys);
    Injection* tinj = tinj_owner.get();
    tinj->path = tpath;
    tinj->nodes = std::make_shared<std::vector<Value>>(
        inj.nodes->begin(), inj.nodes->end() - 1);
    tinj->parent = tinj->nodes->empty() ? Value::undef() : tinj->nodes->back();
    setprop(tinj->parent, Value(ckey), Value(tval));
    tinj->val = Value(tval);
    tinj->dpath = dpath;
    tinj->dparent = tcur_out;

    inject(Value(tval), store, tinj);
    rval = tinj->val;
  }

  setprop(target, tkey, rval);
  if (rval.is_list() && !rval.as_list()->empty()) {
    return (*rval.as_list())[0];
  }
  return Value::undef();
}

inline Value PACK_FN(Injection& inj, const Value& val,
                      const std::string& ref, const Value& store) {
  if (!checkPlacement(M_KEYPRE, "PACK", T_map, inj)) return Value::undef();

  Value args = getprop(inj.parent, Value(inj.key));
  std::vector<Value> arg_list;
  if (args.is_list()) {
    for (const auto& e : *args.as_list()) arg_list.push_back(e);
  }
  auto checked = injectorArgs({T_string, T_any}, arg_list);
  if (!checked[0].is_undef()) {
    inj.errs->push_back(Value("$PACK: " + checked[0].as_string()));
    return Value::undef();
  }
  std::string srcpath = checked[1].as_string();
  Value origchildspec = checked[2];

  Value tkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
  int pathsize = static_cast<int>(inj.path.size());
  Value target;
  if (inj.nodes && static_cast<int>(inj.nodes->size()) >= pathsize) {
    target = (*inj.nodes)[pathsize - 2];
  }
  if (target.is_undef() && inj.nodes && !inj.nodes->empty()) {
    target = inj.nodes->back();
  }

  Value srcstore = getprop(store, Value(inj.base), store);
  Value src = getpath_v(srcstore, Value(srcpath), &inj);

  std::vector<Value> srcList;
  if (src.is_list()) {
    for (const auto& e : *src.as_list()) srcList.push_back(e);
  } else if (src.is_map()) {
    for (const auto& [k, e] : *src.as_map()) {
      if (isnode(e)) {
        auto annoMap = std::shared_ptr<Map>(new Map());
        annoMap->set("KEY", Value(k));
        setprop(e, Value(S_BANNO()), Value(annoMap));
        srcList.push_back(e);
      }
    }
  } else {
    return Value::undef();
  }

  // Extract `$KEY` and `$VAL` from origchildspec.
  Value keypath = Value::undef();
  Value child = origchildspec;
  if (origchildspec.is_map()) {
    keypath = getprop(origchildspec, Value(S_BKEY()));
    delprop(origchildspec, Value(S_BKEY()));
    Value vspec = getprop(origchildspec, Value(S_BVAL()));
    child = vspec.is_undef() ? origchildspec : vspec;
  }

  auto tval = std::shared_ptr<Map>(new Map());

  for (size_t i = 0; i < srcList.size(); i++) {
    const Value& item = srcList[i];
    std::string outKey;
    if (keypath.is_undef()) {
      Value dk = getprop(item, Value(S_DKEY()));
      outKey = dk.is_undef() ? std::to_string(i) : strkey(dk);
    } else if (keypath.is_string() && !keypath.as_string().empty() && keypath.as_string()[0] == '`') {
      // Inject keypath against {$TOP: srcnode} merged into store.
      auto mergeList = std::make_shared<List>();
      mergeList->push_back(Value(std::shared_ptr<Map>(new Map())));
      mergeList->push_back(store);
      auto topMap = std::shared_ptr<Map>(new Map());
      topMap->set(S_DTOP(), item);
      mergeList->push_back(Value(topMap));
      Value merged = merge_v(Value(mergeList), 1);
      Value injected = inject(keypath, merged);
      outKey = injected.is_string() ? injected.as_string() : stringify(injected);
    } else {
      Value kv = getpath_v(item, keypath, &inj);
      outKey = kv.is_string() ? kv.as_string() : strkey(kv);
    }

    Value tchild = clone(child);
    tval->set(outKey, tchild);
    Value anno = getprop(item, Value(S_BANNO()));
    if (anno.is_undef()) {
      delprop(tchild, Value(S_BANNO()));
    } else {
      setprop(tchild, Value(S_BANNO()), anno);
    }
  }

  Value rval(std::shared_ptr<Map>(new Map()));

  if (!tval->empty()) {
    auto tsrc = std::shared_ptr<Map>(new Map());
    for (size_t i = 0; i < srcList.size(); i++) {
      const Value& item = srcList[i];
      std::string kn;
      if (keypath.is_undef()) {
        kn = std::to_string(i);
      } else if (keypath.is_string() && !keypath.as_string().empty() && keypath.as_string()[0] == '`') {
        auto mergeList = std::make_shared<List>();
        mergeList->push_back(Value(std::shared_ptr<Map>(new Map())));
        mergeList->push_back(store);
        auto topMap = std::shared_ptr<Map>(new Map());
        topMap->set(S_DTOP(), item);
        mergeList->push_back(Value(topMap));
        Value merged = merge_v(Value(mergeList), 1);
        Value injected = inject(keypath, merged);
        kn = injected.is_string() ? injected.as_string() : stringify(injected);
      } else {
        Value kv = getpath_v(item, keypath, &inj);
        kn = kv.is_string() ? kv.as_string() : strkey(kv);
      }
      tsrc->set(kn, item);
    }

    std::vector<std::string> tpath(inj.path.begin(), inj.path.end() - 1);
    std::string ckey = inj.path.size() >= 2 ? inj.path[inj.path.size() - 2] : "";

    std::vector<std::string> dpath;
    dpath.push_back(S_DTOP());
    if (!srcpath.empty()) {
      size_t pos = 0;
      while (pos <= srcpath.size()) {
        size_t dot = srcpath.find('.', pos);
        if (dot == std::string::npos) { dpath.push_back(srcpath.substr(pos)); break; }
        dpath.push_back(srcpath.substr(pos, dot - pos));
        pos = dot + 1;
      }
    }
    dpath.push_back("$:" + ckey);

    auto tcur = std::shared_ptr<Map>(new Map());
    tcur->set(ckey, Value(tsrc));
    Value tcur_out(tcur);
    if (tpath.size() > 1) {
      std::string pkey = inj.path.size() >= 3 ? inj.path[inj.path.size() - 3] : S_DTOP();
      auto wrap = std::shared_ptr<Map>(new Map());
      wrap->set(pkey, tcur_out);
      tcur_out = Value(wrap);
      dpath.push_back("$:" + pkey);
    }

    auto single_keys = std::make_shared<std::vector<std::string>>();
    single_keys->push_back(ckey);
    auto tinj_owner = inj.child(0, single_keys);
    Injection* tinj = tinj_owner.get();
    tinj->path = tpath;
    tinj->nodes = std::make_shared<std::vector<Value>>(
        inj.nodes->begin(), inj.nodes->end() - 1);
    tinj->parent = tinj->nodes->empty() ? Value::undef() : tinj->nodes->back();
    tinj->val = Value(tval);
    tinj->dpath = dpath;
    tinj->dparent = tcur_out;

    inject(Value(tval), store, tinj);
    if (tinj->val.is_map()) rval = tinj->val;
  }

  setprop(target, tkey, rval);
  return Value::undef();
}

inline Value REF_FN(Injection& inj, const Value& val,
                     const std::string& ref, const Value& store) {
  if (inj.mode != M_VAL) return Value::undef();
  Value refpath = getprop(inj.parent, Value(int64_t(1)));
  inj.keyI = static_cast<int>(inj.keys ? inj.keys->size() : 0);

  Value spec_holder = getprop(store, Value(S_DSPEC()));
  Value spec = spec_holder;
  if (spec_holder.is_injector()) {
    Injection synth(Value::undef(), Value::undef());
    spec = spec_holder.as_injector()(synth, Value::undef(), "$SPEC", store);
  }

  std::vector<std::string> dpath_slice(inj.path.begin() + 1, inj.path.end());
  Injection refInj(Value::undef(), Value::undef());
  refInj.dpath = dpath_slice;
  auto fp = std::make_shared<List>();
  for (auto& p : dpath_slice) fp->push_back(Value(p));
  refInj.dparent = getpath_v(spec, Value(fp));
  refInj.handler = injecthandler;
  Value refResolved = getpath_v(spec, refpath, &refInj);

  Value tref = clone(refResolved);
  bool hasSubRef = false;
  if (isnode(tref)) {
    walk_v(tref, [&](const Value&, const Value& v, const Value&,
                      const std::vector<std::string>&) -> Value {
      if (v.is_string() && v.as_string() == "`$REF`") hasSubRef = true;
      return v;
    });
  }

  std::vector<std::string> cpath_v;
  if (inj.path.size() >= 3) {
    cpath_v = std::vector<std::string>(inj.path.begin(),
                                        inj.path.begin() + (inj.path.size() - 3));
  }
  std::vector<std::string> tpath_v;
  if (!inj.path.empty()) {
    tpath_v = std::vector<std::string>(inj.path.begin(), inj.path.end() - 1);
  }
  auto cpath_list = std::make_shared<List>();
  for (auto& p : cpath_v) cpath_list->push_back(Value(p));
  auto tpath_list = std::make_shared<List>();
  for (auto& p : tpath_v) tpath_list->push_back(Value(p));

  Value tval_at = getpath_v(store, Value(tpath_list));
  Value rval = Value::undef();

  if (!hasSubRef || !tval_at.is_undef()) {
    std::string lastkey = tpath_v.empty() ? "" : tpath_v.back();
    auto single_keys = std::make_shared<std::vector<std::string>>();
    single_keys->push_back(lastkey);
    auto tinj_owner = inj.child(0, single_keys);
    Injection* tinj = tinj_owner.get();
    tinj->path = tpath_v;
    if (inj.nodes && inj.nodes->size() >= 1) {
      tinj->nodes = std::make_shared<std::vector<Value>>(
          inj.nodes->begin(), inj.nodes->end() - 1);
    }
    if (inj.nodes && inj.nodes->size() >= 2) {
      tinj->parent = (*inj.nodes)[inj.nodes->size() - 2];
    }
    tinj->val = tref;
    tinj->dpath = cpath_v;
    tinj->dparent = getpath_v(store, Value(cpath_list));

    inject(tref, store, tinj);
    rval = tinj->val;
  }

  Value grandparent = inj.setval(rval, 2);
  if (grandparent.is_list() && inj.prior) {
    inj.prior->keyI--;
  }
  return val;
}

}  // namespace transforms

// ===========================================================================
// transform()
// ===========================================================================

inline Value transform(const Value& data, const Value& spec, const Value& options) {
  Value origspec = spec;
  Value workspec = clone(origspec);

  Value extra = options.is_map() ? getprop(options, Value("extra")) : Value::undef();
  Value modifyRaw = options.is_map() ? getprop(options, Value("modify")) : Value::undef();
  Value handlerRaw = options.is_map() ? getprop(options, Value("handler")) : Value::undef();
  Value metaRaw = options.is_map() ? getprop(options, Value("meta")) : Value::undef();
  Value errsRaw = options.is_map() ? getprop(options, Value("errs")) : Value::undef();

  bool collect = errsRaw.is_list();
  std::shared_ptr<std::vector<Value>> errs;
  if (collect) {
    errs = std::make_shared<std::vector<Value>>();
    for (const auto& e : *errsRaw.as_list()) errs->push_back(e);
  } else {
    errs = std::make_shared<std::vector<Value>>();
  }

  // Split extra into commands ($-keyed) and data.
  auto extraTransforms = std::shared_ptr<Map>(new Map());
  auto extraData = std::shared_ptr<Map>(new Map());
  if (extra.is_map()) {
    for (const auto& [k, v] : *extra.as_map()) {
      if (!k.empty() && k[0] == '$') extraTransforms->set(k, v);
      else extraData->set(k, v);
    }
  }

  auto dataMergeList = std::make_shared<List>();
  if (!extraData->empty()) dataMergeList->push_back(Value(extraData));
  dataMergeList->push_back(clone(data));
  Value dataClone = merge_v(Value(dataMergeList));

  auto baseStore = std::shared_ptr<Map>(new Map());
  baseStore->set(S_DTOP(), dataClone);
  // $SPEC as Injector that returns origspec.
  Injector spec_supplier = [origspec](Injection&, const Value&, const std::string&, const Value&) -> Value {
    return origspec;
  };
  baseStore->set(S_DSPEC(), Value(spec_supplier));
  // $BT, $DS, $WHEN as Injectors (called via _injecthandler when matched).
  baseStore->set("$BT", Value(Injector([](Injection&, const Value&, const std::string&, const Value&) -> Value {
    return Value("`");
  })));
  baseStore->set("$DS", Value(Injector([](Injection&, const Value&, const std::string&, const Value&) -> Value {
    return Value("$");
  })));
  baseStore->set("$WHEN", Value(Injector([](Injection&, const Value&, const std::string&, const Value&) -> Value {
    // ISO timestamp.
    auto t = std::time(nullptr);
    auto* tm = std::gmtime(&t);
    char buf[40];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%S.000Z", tm);
    return Value(std::string(buf));
  })));
  baseStore->set("$DELETE", Value(Injector(transforms::DELETE_FN)));
  baseStore->set("$COPY",   Value(Injector(transforms::COPY_FN)));
  baseStore->set("$KEY",    Value(Injector(transforms::KEY_FN)));
  baseStore->set("$ANNO",   Value(Injector(transforms::ANNO_FN)));
  baseStore->set("$MERGE",  Value(Injector(transforms::MERGE_FN)));
  baseStore->set("$EACH",   Value(Injector(transforms::EACH_FN)));
  baseStore->set("$PACK",   Value(Injector(transforms::PACK_FN)));
  baseStore->set("$REF",    Value(Injector(transforms::REF_FN)));
  baseStore->set("$FORMAT", Value(Injector(transforms::FORMAT_FN)));
  baseStore->set("$APPLY",  Value(Injector(transforms::APPLY_FN)));

  auto storeMergeList = std::make_shared<List>();
  storeMergeList->push_back(Value(baseStore));
  if (!extraTransforms->empty()) {
    storeMergeList->push_back(Value(extraTransforms));
  }
  // $ERRS holder list.
  auto errsListPtr = std::make_shared<List>();
  // Note: errs is std::vector<Value>; convert below as needed.
  auto errsHolder = std::shared_ptr<Map>(new Map());
  errsHolder->set(S_DERRS(), Value(errsListPtr));
  storeMergeList->push_back(Value(errsHolder));
  Value store = merge_v(Value(storeMergeList), 1);

  Injection injdef(workspec, Value::undef());
  injdef.prior = nullptr;
  if (modifyRaw.is_modify()) injdef.modify = modifyRaw.as_modify();
  if (handlerRaw.is_injector()) injdef.handler = handlerRaw.as_injector();
  if (metaRaw.is_map()) injdef.meta = metaRaw.as_map();
  injdef.errs = errs;

  Value out = inject(workspec, store, &injdef);

  // Sync $ERRS list back to errs.
  for (const auto& e : *errsListPtr) errs->push_back(e);

  if (!errs->empty() && !collect) {
    std::string msg;
    for (size_t i = 0; i < errs->size(); i++) {
      if (i > 0) msg += " | ";
      msg += stringify((*errs)[i]);
    }
    throw std::runtime_error(msg);
  }
  // Update options.errs if the caller passed a list (back-compat).
  if (collect && errsRaw.is_list()) {
    auto rawList = errsRaw.as_list();
    rawList->clear();
    for (const auto& e : *errs) rawList->push_back(e);
  }
  return out;
}

// ===========================================================================
// Validate injectors
// ===========================================================================

namespace validators {

inline Value STRING_FN(Injection& inj, const Value& val,
                        const std::string& ref, const Value& store) {
  Value out = getprop(inj.dparent, Value(inj.key));
  int t = typify(out);
  if ((T_string & t) == 0) {
    inj.errs->push_back(Value(invalid_type_msg(inj.path, "string", t, out, "V1010")));
    return Value::undef();
  }
  if (out.as_string().empty()) {
    auto pl = std::make_shared<List>();
    for (auto& p : inj.path) pl->push_back(Value(p));
    inj.errs->push_back(Value("Empty string at " + pathify(Value(pl), 1, 0)));
    return Value::undef();
  }
  return out;
}

inline Value TYPE_FN(Injection& inj, const Value& val,
                      const std::string& ref, const Value& store) {
  std::string tname = ref.size() >= 2 ? ref.substr(1) : "";
  for (auto& c : tname) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  int idx = -1;
  for (int i = 0; i < 26; i++) {
    if (typename_table(i) == tname) { idx = i; break; }
  }
  if (idx < 0) return Value::undef();
  int typev = 1 << (31 - idx);
  Value out = getprop(inj.dparent, Value(inj.key));
  int t = typify(out);
  if ((t & typev) == 0) {
    inj.errs->push_back(Value(invalid_type_msg(inj.path, tname, t, out, "V1001")));
    return Value::undef();
  }
  return out;
}

inline Value ANY_FN(Injection& inj, const Value& val,
                     const std::string& ref, const Value& store) {
  return getprop(inj.dparent, Value(inj.key));
}

inline Value CHILD_FN(Injection& inj, const Value& val,
                      const std::string& ref, const Value& store) {
  if (inj.mode == M_KEYPRE) {
    Value childtm = getprop(inj.parent, Value(inj.key));
    Value pkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
    Value tval = getprop(inj.dparent, pkey);

    if (tval.is_undef() || tval.is_null()) {
      tval = Value(std::shared_ptr<Map>(new Map()));
    } else if (!ismap(tval)) {
      auto pl = std::make_shared<List>();
      for (size_t i = 0; i + 1 < inj.path.size(); i++) pl->push_back(Value(inj.path[i]));
      inj.errs->push_back(Value(invalid_type_msg(Value(pl), "object", typify(tval), tval, "V0220")));
      return Value::undef();
    }
    auto ckeys = keysof(tval);
    for (const auto& ck : ckeys) {
      setprop(inj.parent, Value(ck), clone(childtm));
      if (inj.keys) inj.keys->push_back(ck);
    }
    inj.setval(Value::undef());
    return Value::undef();
  }
  if (inj.mode == M_VAL) {
    if (!inj.parent.is_list()) {
      inj.errs->push_back(Value("Invalid $CHILD as value"));
      return Value::undef();
    }
    Value childtm = getprop(inj.parent, Value(int64_t(1)));
    if (inj.dparent.is_undef() || inj.dparent.is_null()) {
      inj.parent.as_list()->clear();
      return Value::undef();
    }
    if (!inj.dparent.is_list()) {
      auto pl = std::make_shared<List>();
      for (size_t i = 0; i + 1 < inj.path.size(); i++) pl->push_back(Value(inj.path[i]));
      inj.errs->push_back(Value(invalid_type_msg(Value(pl), "list", typify(inj.dparent), inj.dparent, "V0230")));
      inj.keyI = static_cast<int>(size(inj.parent));
      return inj.dparent;
    }
    auto dpl = inj.dparent.as_list();
    auto pl = inj.parent.as_list();
    for (size_t i = 0; i < dpl->size(); i++) {
      setprop(inj.parent, Value(static_cast<int64_t>(i)), clone(childtm));
    }
    while (pl->size() > dpl->size()) pl->pop_back();
    inj.keyI = 0;
    return getprop(inj.dparent, Value(int64_t(0)));
  }
  return Value::undef();
}

inline Value ONE_FN(Injection& inj, const Value& val,
                     const std::string& ref, const Value& store) {
  if (inj.mode != M_VAL) return Value::undef();
  if (!inj.parent.is_list() || inj.keyI != 0) {
    auto pl = std::make_shared<List>();
    for (auto& p : inj.path) pl->push_back(Value(p));
    inj.errs->push_back(Value("The $ONE validator at field " + pathify(Value(pl), 1, 1) +
                              " must be the first element of an array."));
    return Value::undef();
  }
  inj.keyI = static_cast<int>(inj.keys ? inj.keys->size() : 0);
  inj.setval(inj.dparent, 2);
  if (!inj.path.empty()) inj.path.pop_back();
  inj.key = inj.path.empty() ? "" : inj.path.back();

  std::vector<Value> tvals;
  if (inj.parent.is_list()) {
    auto pl = inj.parent.as_list();
    for (size_t i = 1; i < pl->size(); i++) tvals.push_back((*pl)[i]);
  }
  if (tvals.empty()) {
    auto pl = std::make_shared<List>();
    for (auto& p : inj.path) pl->push_back(Value(p));
    inj.errs->push_back(Value("The $ONE validator at field " + pathify(Value(pl), 1, 1) +
                              " must have at least one argument."));
    return Value::undef();
  }
  for (const auto& tval : tvals) {
    auto terrs = std::make_shared<std::vector<Value>>();
    auto vstore = std::shared_ptr<Map>(new Map());
    if (store.is_map()) {
      for (const auto& [k, v] : *store.as_map()) vstore->set(k, v);
    }
    vstore->set(S_DTOP(), inj.dparent);
    auto opts = std::shared_ptr<Map>(new Map());
    auto terrs_list = std::make_shared<List>();
    opts->set("extra", Value(vstore));
    opts->set("errs", Value(terrs_list));
    if (inj.meta) opts->set("meta", Value(inj.meta));
    Value vcurrent;
    try {
      vcurrent = validate(inj.dparent, tval, Value(opts));
    } catch (const std::exception& e) {
      terrs_list->push_back(Value(std::string(e.what())));
      vcurrent = inj.dparent;
    }
    inj.setval(vcurrent, -2);
    if (terrs_list->empty()) return Value::undef();
  }
  // No match.
  std::string valdesc;
  for (size_t i = 0; i < tvals.size(); i++) {
    if (i > 0) valdesc += ", ";
    if (tvals[i].is_string()) {
      std::smatch m;
      const std::string& s = tvals[i].as_string();
      if (std::regex_match(s, m, R_TRANSFORM_NAME())) {
        std::string lower = m[1].str();
        for (auto& c : lower) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        valdesc += lower;
        continue;
      }
    }
    valdesc += stringify(tvals[i]);
  }
  inj.errs->push_back(Value(invalid_type_msg(
      inj.path, (tvals.size() > 1 ? "one of " : "") + valdesc,
      typify(inj.dparent), inj.dparent, "V0210")));
  return Value::undef();
}

inline Value EXACT_FN(Injection& inj, const Value& val,
                       const std::string& ref, const Value& store) {
  if (inj.mode == M_VAL) {
    if (!inj.parent.is_list() || inj.keyI != 0) {
      auto pl = std::make_shared<List>();
      for (auto& p : inj.path) pl->push_back(Value(p));
      inj.errs->push_back(Value("The $EXACT validator at field " + pathify(Value(pl), 1, 1) +
                                " must be the first element of an array."));
      return Value::undef();
    }
    inj.keyI = static_cast<int>(inj.keys ? inj.keys->size() : 0);
    inj.setval(inj.dparent, 2);
    if (!inj.path.empty()) inj.path.pop_back();
    inj.key = inj.path.empty() ? "" : inj.path.back();

    std::vector<Value> tvals;
    if (inj.parent.is_list()) {
      auto pl = inj.parent.as_list();
      for (size_t i = 1; i < pl->size(); i++) tvals.push_back((*pl)[i]);
    }
    if (tvals.empty()) {
      auto pl = std::make_shared<List>();
      for (auto& p : inj.path) pl->push_back(Value(p));
      inj.errs->push_back(Value("The $EXACT validator at field " + pathify(Value(pl), 1, 1) +
                                " must have at least one argument."));
      return Value::undef();
    }
    std::string currentstr;
    bool currentstr_set = false;
    for (const auto& tval : tvals) {
      bool exactmatch = (tval == inj.dparent);
      if (!exactmatch && isnode(tval)) {
        if (!currentstr_set) { currentstr = stringify(inj.dparent); currentstr_set = true; }
        std::string ts = stringify(tval);
        exactmatch = (ts == currentstr);
      }
      if (exactmatch) return Value::undef();
    }
    std::string valdesc;
    for (size_t i = 0; i < tvals.size(); i++) {
      if (i > 0) valdesc += ", ";
      if (tvals[i].is_string()) {
        std::smatch m;
        const std::string& s = tvals[i].as_string();
        if (std::regex_match(s, m, R_TRANSFORM_NAME())) {
          std::string lower = m[1].str();
          for (auto& c : lower) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
          valdesc += lower;
          continue;
        }
      }
      valdesc += stringify(tvals[i]);
    }
    inj.errs->push_back(Value(invalid_type_msg(
        inj.path,
        std::string(inj.path.size() > 1 ? "" : "value ") +
            "exactly equal to " + (tvals.size() == 1 ? "" : "one of ") + valdesc,
        typify(inj.dparent), inj.dparent, "V0110")));
    return Value::undef();
  } else {
    delprop(inj.parent, Value(inj.key));
    return Value::undef();
  }
}

}  // namespace validators

// ===========================================================================
// _validation Modify
// ===========================================================================

inline void _validation(const Value& pval, const Value& key, const Value& parent,
                         Injection& inj, const Value& store) {
  if (is_skip(pval)) return;
  bool exact = false;
  if (inj.meta) {
    Value* e = inj.meta->find(S_BEXACT());
    if (e && e->is_bool()) exact = e->as_bool();
  }
  Value cval = getprop(inj.dparent, key);
  if (!exact && (cval.is_undef() || cval.is_null())) return;

  int ptype = typify(pval);
  if ((T_string & ptype) && pval.is_string() && pval.as_string().find('$') != std::string::npos) {
    return;
  }
  int ctype = typify(cval);
  if (ptype != ctype && !pval.is_undef()) {
    inj.errs->push_back(Value(invalid_type_msg(inj.path, typename_str(ptype), ctype, cval, "V0010")));
    return;
  }

  if (ismap(cval)) {
    if (!ismap(pval)) {
      inj.errs->push_back(Value(invalid_type_msg(inj.path, typename_str(ptype), ctype, cval, "V0020")));
      return;
    }
    auto ckeys = keysof(cval);
    auto pkeys = keysof(pval);
    Value open_v = getprop(pval, Value(S_BOPEN()));
    bool is_open = open_v.is_bool() && open_v.as_bool();
    if (!pkeys.empty() && !is_open) {
      std::vector<std::string> badkeys;
      for (auto& ck : ckeys) {
        if (!haskey(pval, Value(ck))) badkeys.push_back(ck);
      }
      if (!badkeys.empty()) {
        auto pl = std::make_shared<List>();
        for (auto& p : inj.path) pl->push_back(Value(p));
        std::string joined;
        for (size_t i = 0; i < badkeys.size(); i++) {
          if (i > 0) joined += ", ";
          joined += badkeys[i];
        }
        inj.errs->push_back(Value("Unexpected keys at field " + pathify(Value(pl), 1, 0) + ": " + joined));
      }
    } else {
      auto args_l = std::make_shared<List>();
      args_l->push_back(pval);
      args_l->push_back(cval);
      merge_v(Value(args_l));
      if (isnode(pval)) delprop(pval, Value(S_BOPEN()));
    }
  } else if (islist(cval)) {
    if (!islist(pval)) {
      inj.errs->push_back(Value(invalid_type_msg(inj.path, typename_str(ptype), ctype, cval, "V0030")));
    }
  } else if (exact) {
    if (cval != pval) {
      auto pl = std::make_shared<List>();
      for (auto& p : inj.path) pl->push_back(Value(p));
      std::string pathmsg = inj.path.size() > 1 ? "at field " + pathify(Value(pl), 1, 0) + ": " : "";
      inj.errs->push_back(Value("Value " + pathmsg + js_string(cval) +
                                " should equal " + js_string(pval) + "."));
    }
  } else {
    setprop(parent, key, cval);
  }
}

inline Value _validatehandler(Injection& inj, const Value& val,
                              const std::string& ref, const Value& store) {
  if (!ref.empty()) {
    std::smatch m;
    if (std::regex_match(ref, m, R_META_PATH())) {
      std::string op = m[2].str();
      if (op == "=") {
        auto wrap = std::make_shared<List>();
        wrap->push_back(Value(S_BEXACT()));
        wrap->push_back(val);
        inj.setval(Value(wrap));
      } else {
        inj.setval(val);
      }
      inj.keyI = -1;
      return SKIP();
    }
  }
  return injecthandler(inj, val, ref, store);
}

// ===========================================================================
// validate()
// ===========================================================================

inline Value validate(const Value& data, const Value& spec, const Value& options) {
  Value extraRaw = options.is_map() ? getprop(options, Value("extra")) : Value::undef();
  Value errsRaw  = options.is_map() ? getprop(options, Value("errs"))  : Value::undef();
  Value metaRaw  = options.is_map() ? getprop(options, Value("meta"))  : Value::undef();

  bool collect = errsRaw.is_list();
  std::shared_ptr<std::vector<Value>> errs = std::make_shared<std::vector<Value>>();
  if (collect) {
    for (const auto& e : *errsRaw.as_list()) errs->push_back(e);
  }

  auto baseStore = std::shared_ptr<Map>(new Map());
  baseStore->set("$DELETE", Value(nullptr));
  baseStore->set("$COPY",   Value(nullptr));
  baseStore->set("$KEY",    Value(nullptr));
  baseStore->set("$META",   Value(nullptr));
  baseStore->set("$MERGE",  Value(nullptr));
  baseStore->set("$EACH",   Value(nullptr));
  baseStore->set("$PACK",   Value(nullptr));

  baseStore->set("$STRING",   Value(Injector(validators::STRING_FN)));
  baseStore->set("$NUMBER",   Value(Injector(validators::TYPE_FN)));
  baseStore->set("$INTEGER",  Value(Injector(validators::TYPE_FN)));
  baseStore->set("$DECIMAL",  Value(Injector(validators::TYPE_FN)));
  baseStore->set("$BOOLEAN",  Value(Injector(validators::TYPE_FN)));
  baseStore->set("$NULL",     Value(Injector(validators::TYPE_FN)));
  baseStore->set("$NIL",      Value(Injector(validators::TYPE_FN)));
  baseStore->set("$MAP",      Value(Injector(validators::TYPE_FN)));
  baseStore->set("$LIST",     Value(Injector(validators::TYPE_FN)));
  baseStore->set("$FUNCTION", Value(Injector(validators::TYPE_FN)));
  baseStore->set("$INSTANCE", Value(Injector(validators::TYPE_FN)));
  baseStore->set("$ANY",      Value(Injector(validators::ANY_FN)));
  baseStore->set("$CHILD",    Value(Injector(validators::CHILD_FN)));
  baseStore->set("$ONE",      Value(Injector(validators::ONE_FN)));
  baseStore->set("$EXACT",    Value(Injector(validators::EXACT_FN)));

  auto mergeList = std::make_shared<List>();
  mergeList->push_back(Value(baseStore));
  if (extraRaw.is_map()) mergeList->push_back(extraRaw);
  auto errsListPtr = std::make_shared<List>();
  auto errsHolder = std::shared_ptr<Map>(new Map());
  errsHolder->set(S_DERRS(), Value(errsListPtr));
  mergeList->push_back(Value(errsHolder));
  Value store = merge_v(Value(mergeList), 1);

  std::shared_ptr<Map> meta;
  if (metaRaw.is_map()) {
    meta = std::shared_ptr<Map>(new Map());
    for (const auto& [k, v] : *metaRaw.as_map()) meta->set(k, v);
  } else {
    meta = std::shared_ptr<Map>(new Map());
  }
  if (!meta->find(S_BEXACT())) meta->set(S_BEXACT(), Value(false));

  auto opts = std::shared_ptr<Map>(new Map());
  opts->set("meta", Value(meta));
  opts->set("extra", store);
  opts->set("modify", Value(Modify(_validation)));
  opts->set("handler", Value(Injector(_validatehandler)));
  auto opt_errs_list = std::make_shared<List>();
  for (const auto& e : *errs) opt_errs_list->push_back(e);
  opts->set("errs", Value(opt_errs_list));

  Value out = transform(data, spec, Value(opts));

  // Sync opt_errs_list back to errs.
  errs->clear();
  for (const auto& e : *opt_errs_list) errs->push_back(e);

  if (!errs->empty() && !collect) {
    std::string msg;
    for (size_t i = 0; i < errs->size(); i++) {
      if (i > 0) msg += " | ";
      msg += stringify((*errs)[i]);
    }
    throw std::runtime_error(msg);
  }
  if (collect && errsRaw.is_list()) {
    auto rl = errsRaw.as_list();
    rl->clear();
    for (const auto& e : *errs) rl->push_back(e);
  }
  return out;
}

// ===========================================================================
// Select injectors + select()
// ===========================================================================

namespace selectors {

inline std::shared_ptr<Map> recOpts(const Value& store, const Value& point,
                                     std::shared_ptr<Map> meta,
                                     std::shared_ptr<List> errs_list) {
  auto vstore = std::shared_ptr<Map>(new Map());
  if (store.is_map()) {
    for (const auto& [k, v] : *store.as_map()) vstore->set(k, v);
  }
  vstore->set(S_DTOP(), point);
  auto opts = std::shared_ptr<Map>(new Map());
  opts->set("errs", Value(errs_list));
  opts->set("meta", Value(meta));
  opts->set("extra", Value(vstore));
  return opts;
}

inline Value AND_FN(Injection& inj, const Value& val,
                     const std::string& ref, const Value& store) {
  if (inj.mode != M_KEYPRE) return Value::undef();
  Value terms = getprop(inj.parent, Value(inj.key));
  if (!terms.is_list()) return Value::undef();

  auto ppath = std::make_shared<List>();
  for (size_t i = 0; i + 1 < inj.path.size(); i++) ppath->push_back(Value(inj.path[i]));
  Value point = getpath_v(store, Value(ppath));

  for (const auto& term : *terms.as_list()) {
    auto terrs = std::make_shared<List>();
    auto opts = recOpts(store, point, inj.meta, terrs);
    try { validate(point, term, Value(opts)); }
    catch (const std::exception& e) { terrs->push_back(Value(std::string(e.what()))); }
    if (!terrs->empty()) {
      inj.errs->push_back(Value("AND:" + pathify(Value(ppath)) + ": " +
                                stringify(point) + " fail:" + stringify(terms)));
    }
  }
  Value gkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
  Value gp;
  if (inj.nodes && inj.nodes->size() >= 2) gp = (*inj.nodes)[inj.nodes->size() - 2];
  setprop(gp, gkey, point);
  return Value::undef();
}

inline Value OR_FN(Injection& inj, const Value& val,
                    const std::string& ref, const Value& store) {
  if (inj.mode != M_KEYPRE) return Value::undef();
  Value terms = getprop(inj.parent, Value(inj.key));
  if (!terms.is_list()) return Value::undef();

  auto ppath = std::make_shared<List>();
  for (size_t i = 0; i + 1 < inj.path.size(); i++) ppath->push_back(Value(inj.path[i]));
  Value point = getpath_v(store, Value(ppath));

  for (const auto& term : *terms.as_list()) {
    auto terrs = std::make_shared<List>();
    auto opts = recOpts(store, point, inj.meta, terrs);
    try { validate(point, term, Value(opts)); }
    catch (const std::exception& e) { terrs->push_back(Value(std::string(e.what()))); }
    if (terrs->empty()) {
      Value gkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
      Value gp;
      if (inj.nodes && inj.nodes->size() >= 2) gp = (*inj.nodes)[inj.nodes->size() - 2];
      setprop(gp, gkey, point);
      return Value::undef();
    }
  }
  inj.errs->push_back(Value("OR:" + pathify(Value(ppath)) + ": " +
                            stringify(point) + " fail:" + stringify(terms)));
  return Value::undef();
}

inline Value NOT_FN(Injection& inj, const Value& val,
                     const std::string& ref, const Value& store) {
  if (inj.mode != M_KEYPRE) return Value::undef();
  Value term = getprop(inj.parent, Value(inj.key));
  auto ppath = std::make_shared<List>();
  for (size_t i = 0; i + 1 < inj.path.size(); i++) ppath->push_back(Value(inj.path[i]));
  Value point = getpath_v(store, Value(ppath));
  auto terrs = std::make_shared<List>();
  auto opts = recOpts(store, point, inj.meta, terrs);
  try { validate(point, term, Value(opts)); }
  catch (const std::exception& e) { terrs->push_back(Value(std::string(e.what()))); }
  if (terrs->empty()) {
    inj.errs->push_back(Value("NOT:" + pathify(Value(ppath)) + ": " +
                              stringify(point) + " fail:" + stringify(term)));
  }
  Value gkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
  Value gp;
  if (inj.nodes && inj.nodes->size() >= 2) gp = (*inj.nodes)[inj.nodes->size() - 2];
  setprop(gp, gkey, point);
  return Value::undef();
}

inline Value CMP_FN(Injection& inj, const Value& val,
                     const std::string& ref, const Value& store) {
  if (inj.mode != M_KEYPRE) return Value::undef();
  Value term = getprop(inj.parent, Value(inj.key));
  Value gkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
  auto ppath = std::make_shared<List>();
  for (size_t i = 0; i + 1 < inj.path.size(); i++) ppath->push_back(Value(inj.path[i]));
  Value point = getpath_v(store, Value(ppath));
  bool pass = false;
  if (point.is_number() && term.is_number()) {
    double a = point.as_double();
    double b = term.as_double();
    if (ref == "$GT") pass = a > b;
    else if (ref == "$LT") pass = a < b;
    else if (ref == "$GTE") pass = a >= b;
    else if (ref == "$LTE") pass = a <= b;
  } else if (ref == "$LIKE" && term.is_string()) {
    try {
      std::regex pat(term.as_string());
      pass = std::regex_search(stringify(point), pat);
    } catch (...) { pass = false; }
  }
  if (pass) {
    Value gp;
    if (inj.nodes && inj.nodes->size() >= 2) gp = (*inj.nodes)[inj.nodes->size() - 2];
    setprop(gp, gkey, point);
  } else {
    inj.errs->push_back(Value("CMP: " + pathify(Value(ppath)) + ": " +
                              stringify(point) + " fail:" + ref + " " + stringify(term)));
  }
  return Value::undef();
}

}  // namespace selectors

inline std::vector<Value> select(const Value& children, const Value& query) {
  if (!isnode(children)) return {};

  std::vector<Value> childList;
  if (ismap(children)) {
    for (const auto& [k, v] : *children.as_map()) {
      if (isnode(v)) {
        setprop(v, Value(S_DKEY()), Value(k));
      }
      childList.push_back(v);
    }
  } else {
    auto cl = children.as_list();
    for (size_t i = 0; i < cl->size(); i++) {
      const Value& node = (*cl)[i];
      if (isnode(node)) {
        setprop(node, Value(S_DKEY()), Value(static_cast<int64_t>(i)));
      }
      childList.push_back(node);
    }
  }

  auto meta = std::shared_ptr<Map>(new Map());
  meta->set(S_BEXACT(), Value(true));

  auto extra = std::shared_ptr<Map>(new Map());
  extra->set("$AND", Value(Injector(selectors::AND_FN)));
  extra->set("$OR",  Value(Injector(selectors::OR_FN)));
  extra->set("$NOT", Value(Injector(selectors::NOT_FN)));
  extra->set("$GT",  Value(Injector(selectors::CMP_FN)));
  extra->set("$LT",  Value(Injector(selectors::CMP_FN)));
  extra->set("$GTE", Value(Injector(selectors::CMP_FN)));
  extra->set("$LTE", Value(Injector(selectors::CMP_FN)));
  extra->set("$LIKE",Value(Injector(selectors::CMP_FN)));

  Value q = clone(query);
  walk_v(q, [](const Value&, const Value& v, const Value&,
                const std::vector<std::string>&) -> Value {
    if (ismap(v)) {
      Value cur = getprop(v, Value(S_BOPEN()));
      setprop(v, Value(S_BOPEN()), cur.is_undef() ? Value(true) : cur);
    }
    return v;
  });

  std::vector<Value> results;
  for (const auto& child : childList) {
    auto errs_list = std::make_shared<List>();
    auto opts = std::shared_ptr<Map>(new Map());
    opts->set("errs", Value(errs_list));
    opts->set("meta", Value(meta));
    opts->set("extra", Value(extra));
    try { validate(child, clone(q), Value(opts)); }
    catch (const std::exception& e) { errs_list->push_back(Value(std::string(e.what()))); }
    if (errs_list->empty()) results.push_back(child);
  }
  return results;
}

}  // namespace structlib
}  // namespace voxgig

#endif  // VOXGIG_STRUCT_HPP
