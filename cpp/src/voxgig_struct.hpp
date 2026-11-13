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
#include <cstdio>
#include <cstdlib>
#include <iomanip>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "value.hpp"

namespace voxgig {
namespace structlib {

// ===========================================================================
// String / regex constants
// ===========================================================================

inline const std::string& S_MT() {
  static const std::string s = "";
  return s;
}
inline const std::string& S_DT() {
  static const std::string s = ".";
  return s;
}
inline const std::string& S_DTOP() {
  static const std::string s = "$TOP";
  return s;
}
inline const std::string& S_DSPEC() {
  static const std::string s = "$SPEC";
  return s;
}
inline const std::string& S_DKEY() {
  static const std::string s = "$KEY";
  return s;
}
inline const std::string& S_DERRS() {
  static const std::string s = "$ERRS";
  return s;
}
inline const std::string& S_BKEY() {
  static const std::string s = "`$KEY`";
  return s;
}
inline const std::string& S_BANNO() {
  static const std::string s = "`$ANNO`";
  return s;
}
inline const std::string& S_BVAL() {
  static const std::string s = "`$VAL`";
  return s;
}
inline const std::string& S_BEXACT() {
  static const std::string s = "`$EXACT`";
  return s;
}
inline const std::string& S_BOPEN() {
  static const std::string s = "`$OPEN`";
  return s;
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

inline bool isnode(const Value& v) {
  return v.is_node() || v.is_sentinel();
}
inline bool ismap(const Value& v) {
  return v.is_map() || v.is_sentinel();
}
inline bool islist(const Value& v) {
  return v.is_list();
}

inline bool iskey(const Value& v) {
  if (v.is_string())
    return !v.as_string().empty();
  if (v.is_int())
    return true;
  if (v.is_double())
    return true;
  return false;
}

inline bool isempty(const Value& v) {
  if (v.is_undef() || v.is_null())
    return true;
  if (v.is_string())
    return v.as_string().empty();
  if (v.is_list())
    return v.as_list()->empty();
  if (v.is_map())
    return v.as_map()->empty();
  return false;
}

inline bool isfunc(const Value& v) {
  return v.is_func();
}

inline Value getdef(const Value& v, const Value& alt) {
  if (v.is_undef())
    return alt;
  return v;
}

inline int64_t size(const Value& v) {
  return size_of(v);
}

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
inline Value lookup_v(const Value& val, const Value& key);
inline Value setprop(Value parent, const Value& key, const Value& val);
inline Value delprop(Value parent, const Value& key);
inline std::vector<std::string> keysof(const Value& v);
inline bool haskey(const Value& v, const Value& key);
inline std::vector<Value> items(const Value& v);
inline std::string stringify(const Value& v, int maxlen = -1);
inline std::string pathify(const Value& v, int startin = 0, int endin = 0);
inline Value slice(const Value& v, const Value& start = Value::undef(),
                   const Value& end = Value::undef());
inline Value walk_v(
    const Value& val,
    std::function<Value(const Value&, const Value&, const Value&, const std::vector<std::string>&)>
        before,
    std::function<Value(const Value&, const Value&, const Value&, const std::vector<std::string>&)>
        after,
    int maxdepth = MAXDEPTH);
inline Value merge_v(const Value& list, int maxdepth = MAXDEPTH);
inline Value getpath_v(const Value& store, const Value& path, Injection* inj = nullptr);
inline Value setpath_v(const Value& store, const Value& path, const Value& val);
inline Value inject(const Value& val, const Value& store, Injection* injdef = nullptr);
inline Value transform(const Value& data, const Value& spec, const Value& options = Value::undef());
inline Value validate(const Value& data, const Value& spec, const Value& options = Value::undef());
inline std::vector<Value> select(const Value& children, const Value& query);
inline bool iscondensed(const Value& val = Value::undef());

inline const std::string& S_IMMUTABLE() {
  static const std::string s =
      "struct: condensed structures are immutable - expand() first, then modify the copy";
  return s;
}

// ===========================================================================
// strkey / getprop / setprop / delprop / getelem
// ===========================================================================

inline std::string strkey(const Value& key) {
  if (key.is_undef())
    return S_MT();
  if (key.is_string())
    return key.as_string();
  if (key.is_bool())
    return S_MT();
  if (key.is_int())
    return std::to_string(key.as_int());
  if (key.is_double()) {
    double d = key.as_double();
    if (std::floor(d) == d)
      return std::to_string(static_cast<int64_t>(d));
    return std::to_string(static_cast<int64_t>(std::floor(d)));
  }
  return S_MT();
}

namespace detail {

// A list key this far from zero is past any list: a write appends or prepends, a read misses.
constexpr int64_t LISTKEY_HUGE = 1000000000000000000;

// ^(0|-?[1-9][0-9]*)$, the form String(n) gives an integer n, as that integer. So "01",
// "+1", " 1", "1.0" and "-0" are not list keys.
inline bool canon_listindex(const std::string& key, int64_t& index) {
  size_t j = !key.empty() && '-' == key[0] ? 1 : 0;
  if (j == key.size() || ('0' == key[j] && 1 < key.size()))
    return false;
  int64_t i = 0;
  for (; j < key.size(); j++) {
    if (key[j] < '0' || '9' < key[j])
      return false;
    i = i < LISTKEY_HUGE / 10 ? i * 10 + (key[j] - '0') : LISTKEY_HUGE;
  }
  index = '-' == key[0] ? -i : i;
  return true;
}

// The canonical _listkey: an integral number, or a string canon_listindex accepts.
inline bool list_key(const Value& key, int64_t& index) {
  if (key.is_int()) {
    index = key.as_int();
    return true;
  }
  if (key.is_double()) {
    double d = key.as_double();
    if (!std::isfinite(d) || std::floor(d) != d)
      return false;
    if (std::fabs(d) < static_cast<double>(LISTKEY_HUGE))
      index = static_cast<int64_t>(d);
    else
      index = 0 < d ? LISTKEY_HUGE : -LISTKEY_HUGE;
    return true;
  }
  return key.is_string() && canon_listindex(key.as_string(), index);
}

// The element a list read selects, else -1. Only getelem counts a negative key from the end.
inline int64_t list_readindex(const Value& key) {
  int64_t i = -1;
  return list_key(key, i) && 0 <= i ? i : -1;
}

// A map reads a string or number key; any other key names no member.
inline bool map_readkey(const Value& key) {
  return key.is_string() || key.is_number();
}

} // namespace detail

inline Value getprop(const Value& val, const Value& key, const Value& alt) {
  if (val.is_undef() || key.is_undef())
    return alt;
  if (val.is_map()) {
    auto m = val.as_map();
    if (!m || !detail::map_readkey(key))
      return alt;
    std::string sk = strkey(key);
    Value* found = m->find(sk);
    if (!found)
      return alt;
    // Group A: a stored JSON null counts as "no value" (canonical `null == out`
    // is true for both undefined and null), so the alt is substituted.
    if (found->is_undef() || found->is_null())
      return alt;
    return *found;
  }
  if (val.is_list()) {
    auto l = val.as_list();
    if (!l)
      return alt;
    int64_t idx = detail::list_readindex(key);
    if (idx < 0 || idx >= static_cast<int64_t>(l->size()))
      return alt;
    Value v = (*l)[static_cast<size_t>(idx)];
    // Group A: a stored JSON null counts as "no value" — substitute the alt.
    if (v.is_undef() || v.is_null())
      return alt;
    return v;
  }
  return alt;
}

inline Value getelem(const Value& val, const Value& key, const Value& alt) {
  Value out = Value::undef();
  if (val.is_undef() || key.is_undef()) {
    if (alt.is_func() && alt.is_injector())
      return alt;
    return alt;
  }
  if (val.is_list()) {
    auto l = val.as_list();
    int64_t size = static_cast<int64_t>(l->size());
    int64_t nkey = -1;
    if (detail::list_key(key, nkey) && nkey < 0)
      nkey += size;
    if (nkey < 0 || nkey >= size)
      return alt;
    out = (*l)[static_cast<size_t>(nkey)];
  }
  // Group A: a stored JSON null at the slot counts as "no value" (canonical
  // `null == out` is true for both undefined and null) — substitute the alt.
  if (out.is_undef() || out.is_null())
    return alt;
  return out;
}

// Internal Group B lookup: read the raw stored value at a slot, preserving a
// stored JSON null. Mirrors canonical `_lookup` (StructUtility.ts). The public
// getprop / getelem / haskey treat a stored null as absent (Group A); the
// validate / transform / inject internals that need the literal value (e.g. to
// validate against $NULL or echo a null back through an injector) use this.
inline Value lookup_v(const Value& val, const Value& key) {
  if (val.is_undef() || key.is_undef())
    return Value::undef();
  if (val.is_list()) {
    auto l = val.as_list();
    if (!l)
      return Value::undef();
    int64_t idx = detail::list_readindex(key);
    if (idx < 0 || idx >= static_cast<int64_t>(l->size()))
      return Value::undef();
    Value v = (*l)[static_cast<size_t>(idx)];
    return v.is_undef() ? Value::undef() : v;
  }
  if (val.is_map()) {
    auto m = val.as_map();
    if (!m || !detail::map_readkey(key))
      return Value::undef();
    std::string sk = strkey(key);
    if (sk.empty())
      return Value::undef();
    Value* found = m->find(sk);
    if (!found)
      return Value::undef();
    return *found;
  }
  return Value::undef();
}

inline Value setprop(Value parent, const Value& key, const Value& val) {
  if (!iskey(key))
    return parent;
  if (iscondensed(parent))
    throw std::runtime_error(S_IMMUTABLE());
  if (parent.is_map()) {
    auto m = parent.as_map();
    std::string sk = strkey(key);
    m->set(sk, val);
    return parent;
  }
  if (parent.is_list()) {
    auto l = parent.as_list();
    int64_t idx = 0;
    if (!detail::list_key(key, idx))
      return parent;

    if (idx >= 0) {
      if (idx >= static_cast<int64_t>(l->size())) {
        l->push_back(val);
      } else {
        (*l)[static_cast<size_t>(idx)] = val;
      }
    } else {
      l->insert(l->begin(), val);
    }
    return parent;
  }
  return parent;
}

inline Value delprop(Value parent, const Value& key) {
  if (!iskey(key))
    return parent;
  if (iscondensed(parent))
    throw std::runtime_error(S_IMMUTABLE());
  if (parent.is_map()) {
    parent.as_map()->erase(strkey(key));
    return parent;
  }
  if (parent.is_list()) {
    auto l = parent.as_list();
    int64_t idx = -1;
    if (detail::list_key(key, idx) && 0 <= idx && idx < static_cast<int64_t>(l->size()))
      l->erase(l->begin() + idx);
    return parent;
  }
  return parent;
}

// ===========================================================================
// keysof / haskey / items
// ===========================================================================

inline std::vector<std::string> keysof(const Value& v) {
  std::vector<std::string> out;
  if (!v.is_node())
    return out;
  if (v.is_map()) {
    for (const auto& [k, _] : *v.as_map())
      out.push_back(k);
    // Matches TS canonical Object.keys(val).sort() — keysof returns
    // alphabetically sorted keys regardless of insertion order.
    std::sort(out.begin(), out.end());
  } else {
    auto l = v.as_list();
    out.reserve(l->size());
    for (size_t i = 0; i < l->size(); i++)
      out.push_back(std::to_string(i));
  }
  return out;
}

inline bool haskey(const Value& v, const Value& key) {
  // Canonical: `null != getprop(val, key)`. A present-but-null key is false
  // (getprop already substitutes its undef default for a stored null).
  Value r = getprop(v, key);
  return !r.is_undef() && !r.is_null();
}

// items returns list of [key, value] pairs as Value-list-of-Value-lists.
inline Value items_v(const Value& v) {
  auto out = std::make_shared<List>();
  if (!v.is_node())
    return Value(out);
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
  if (!v.is_node())
    return out;
  for (const auto& key : keysof(v)) {
    auto pair = std::make_shared<List>();
    pair->push_back(Value(key));
    // Canonical reads val[k]: a stored null is a value here (Group B).
    pair->push_back(lookup_v(v, Value(key)));
    out.push_back(Value(std::move(pair)));
  }
  return out;
}

// ===========================================================================
// flatten / filter
// ===========================================================================

inline Value flatten(const Value& list, int depth = 1) {
  if (!list.is_list())
    return list;
  auto out = std::make_shared<List>();
  std::function<void(const std::shared_ptr<List>&, int)> rec = [&](const std::shared_ptr<List>& src,
                                                                   int d) {
    for (const auto& e : *src) {
      if (d > 0 && e.is_list())
        rec(e.as_list(), d - 1);
      else
        out->push_back(e);
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
    if (start_v.is_number())
      lo = start_v.as_int();
    if (end_v.is_number())
      hi = end_v.as_int() - 1;
    if (n < lo)
      n = lo;
    if (n > hi)
      n = hi;
    if (val.is_int())
      return Value(static_cast<int64_t>(n));
    return Value(n);
  }

  int vlen = static_cast<int>(size(val));
  bool has_start = !start_v.is_undef();
  bool has_end = !end_v.is_undef();
  int start = has_start ? static_cast<int>(start_v.as_int()) : 0;
  int end = has_end ? static_cast<int>(end_v.as_int()) : vlen;

  if (has_end && !has_start) {
    start = 0;
    has_start = true; // proceed into slice block even if only end was given
  }

  if (has_start) {
    if (start < 0) {
      end = vlen + start;
      if (end < 0)
        end = 0;
      start = 0;
    } else if (has_end) {
      if (end < 0) {
        end = vlen + end;
        if (end < 0)
          end = 0;
      } else if (vlen < end) {
        end = vlen;
      }
    } else {
      end = vlen;
    }
    if (vlen < start)
      start = vlen;

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
      if (val.is_list())
        return Value(std::make_shared<List>());
      if (val.is_string())
        return Value(std::string(""));
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
inline std::string pad(const Value& v, const Value& padding_v,
                       const Value& padchar_v = Value::undef()) {
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

// ----------------------------------------------------------------------------
// Regex utility — uniform re_* API (see /REGEX_API.md). C++'s <regex>
// (ECMAScript dialect by default) is a strict superset of RE2.
// ----------------------------------------------------------------------------

inline std::regex re_compile(const std::string& pattern) {
  return std::regex(pattern);
}

inline bool re_test(const std::string& pattern, const std::string& input) {
  return std::regex_search(input, std::regex(pattern));
}

inline bool re_test(const std::regex& re, const std::string& input) {
  return std::regex_search(input, re);
}

inline std::vector<std::string> re_find(const std::string& pattern, const std::string& input) {
  std::smatch m;
  if (!std::regex_search(input, m, std::regex(pattern)))
    return {};
  std::vector<std::string> out;
  for (size_t i = 0; i < m.size(); i++)
    out.push_back(m[i].str());
  return out;
}

inline std::vector<std::vector<std::string>> re_find_all(const std::string& pattern,
                                                         const std::string& input) {
  std::vector<std::vector<std::string>> out;
  std::regex rx(pattern);
  auto begin = std::sregex_iterator(input.begin(), input.end(), rx);
  auto end = std::sregex_iterator();
  for (auto it = begin; it != end; ++it) {
    std::vector<std::string> row;
    for (size_t i = 0; i < it->size(); i++)
      row.push_back((*it)[i].str());
    out.push_back(std::move(row));
  }
  return out;
}

inline std::string re_replace(const std::string& pattern, const std::string& input,
                              const std::string& replacement) {
  return std::regex_replace(input, std::regex(pattern), replacement);
}

inline std::string re_escape(const std::string& s) {
  return std::regex_replace(s, R_ESCAPE_REGEXP(), "\\$&");
}

inline std::string escurl(const Value& v) {
  if (v.is_undef())
    return "";
  std::string s = v.is_string() ? v.as_string() : stringify(v);
  std::ostringstream out;
  out.fill('0');
  out << std::hex;
  for (unsigned char c : s) {
    // The set encodeURIComponent keeps.
    if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~' || c == '!' || c == '*' ||
        c == '\'' || c == '(' || c == ')') {
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
  if (v.is_undef() || v.is_null())
    return "null";
  if (v.is_bool())
    return v.as_bool() ? "true" : "false";
  if (v.is_int())
    return std::to_string(v.as_int());
  if (v.is_double()) {
    double d = v.as_double();
    if (std::isfinite(d) && std::floor(d) == d) {
      return std::to_string(static_cast<int64_t>(d));
    }
    std::ostringstream oss;
    oss << d;
    return oss.str();
  }
  if (v.is_string())
    return v.as_string();
  return stringify(v);
}

inline std::string join(const Value& arr, const std::string& sep = ",", bool url = false) {
  if (!arr.is_list())
    return "";
  // Filter to non-empty strings.
  std::vector<std::string> parts;
  auto src = arr.as_list();
  for (size_t i = 0; i < src->size(); i++) {
    const Value& v = (*src)[i];
    if (!v.is_string() || v.as_string().empty())
      continue;
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
        if (i > 0)
          s = std::regex_replace(s, std::regex("^" + sepre + "+"), "");
        if (i < sarr - 1 || !url) {
          s = std::regex_replace(s, std::regex(sepre + "+$"), "");
        }
        s = std::regex_replace(s, std::regex("([^" + sepre + "])" + sepre + "+([^" + sepre + "])"),
                               std::string("$1") + sep + "$2");
      }
    }
    if (!s.empty())
      cleaned.push_back(s);
  }
  std::string out;
  for (size_t i = 0; i < cleaned.size(); i++) {
    if (i > 0)
      out += sep;
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

// Pure-C++ JSON emitter — mirrors c/src/utility.c::jsonify_inner. Map keys
// are emitted in INSERTION order (matching TS canonical's JSON.stringify
// behaviour), not alphabetically. Used by jsonify / stringify / partial
// inject so the library proper does not depend on nlohmann::json for
// output (nlohmann is still used by the test harness for corpus loading).
inline void _json_escape(const std::string& s, std::string& out) {
  for (char c : s) {
    switch (c) {
    case '"':
      out += "\\\"";
      break;
    case '\\':
      out += "\\\\";
      break;
    case '\b':
      out += "\\b";
      break;
    case '\f':
      out += "\\f";
      break;
    case '\n':
      out += "\\n";
      break;
    case '\r':
      out += "\\r";
      break;
    case '\t':
      out += "\\t";
      break;
    default:
      if (static_cast<unsigned char>(c) < 0x20) {
        char buf[8];
        std::snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned char>(c));
        out += buf;
      } else {
        out += c;
      }
    }
  }
}

inline void _jsonify_inner(const Value& v, std::string& out, int indent, int depth,
                           bool sort_keys = false) {
  if (v.is_undef() || v.is_null()) {
    out += "null";
    return;
  }
  if (v.is_bool()) {
    out += v.as_bool() ? "true" : "false";
    return;
  }
  if (v.is_int()) {
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%lld", static_cast<long long>(v.as_int()));
    out += buf;
    return;
  }
  if (v.is_double()) {
    double d = v.as_double();
    if (!std::isfinite(d)) {
      out += "null";
      return;
    }
    char buf[48];
    if (std::floor(d) == d && std::abs(d) < 1e15) {
      std::snprintf(buf, sizeof(buf), "%lld", static_cast<long long>(d));
    } else {
      // Use %g (shortest round-trip-ish form) — matches C's doublestr and
      // closely tracks JS JSON.stringify for typical fractional values.
      std::snprintf(buf, sizeof(buf), "%g", d);
    }
    out += buf;
    return;
  }
  if (v.is_string()) {
    out += '"';
    _json_escape(v.as_string(), out);
    out += '"';
    return;
  }
  if (v.is_list()) {
    const auto& l = *v.as_list();
    if (l.empty()) {
      out += "[]";
      return;
    }
    out += '[';
    bool first = true;
    for (const auto& e : l) {
      if (!first)
        out += ',';
      first = false;
      if (indent > 0) {
        out += '\n';
        out.append(static_cast<size_t>((depth + 1) * indent), ' ');
      }
      _jsonify_inner(e, out, indent, depth + 1, sort_keys);
    }
    if (indent > 0) {
      out += '\n';
      out.append(static_cast<size_t>(depth * indent), ' ');
    }
    out += ']';
    return;
  }
  if (v.is_map()) {
    const auto& m = *v.as_map();
    if (m.empty()) {
      out += "{}";
      return;
    }
    out += '{';

    // Optionally walk in sorted key order (stringify behaviour, matching
    // TS canonical's stringify replacer). jsonify keeps insertion order.
    std::vector<std::string> order;
    order.reserve(m.size());
    for (const auto& [k, _e] : m)
      order.push_back(k);
    if (sort_keys)
      std::sort(order.begin(), order.end());

    bool first = true;
    for (const auto& k : order) {
      const Value* ep = m.find(k);
      if (!ep)
        continue;
      const auto& e = *ep;
      if (!first)
        out += ',';
      first = false;
      if (indent > 0) {
        out += '\n';
        out.append(static_cast<size_t>((depth + 1) * indent), ' ');
      }
      out += '"';
      _json_escape(k, out);
      out += indent > 0 ? "\": " : "\":";
      _jsonify_inner(e, out, indent, depth + 1, sort_keys);
    }
    if (indent > 0) {
      out += '\n';
      out.append(static_cast<size_t>(depth * indent), ' ');
    }
    out += '}';
    return;
  }
  // function / sentinel / unknown -> null
  out += "null";
}

inline std::string jsonify(const Value& v, int indent = 2) {
  if (v.is_undef() || v.is_null())
    return "null";
  std::string out;
  _jsonify_inner(v, out, indent, 0);
  return out;
}

inline std::string jsonify(const Value& v, const Value& flags) {
  int indent = 2;
  int offset = 0;
  if (flags.is_map()) {
    Value iv = getprop(flags, Value("indent"));
    Value ov = getprop(flags, Value("offset"));
    if (iv.is_int())
      indent = static_cast<int>(iv.as_int());
    if (ov.is_int())
      offset = static_cast<int>(ov.as_int());
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
      if (first) {
        padded += line;
        first = false;
      } else
        padded += "\n" + pad_str + line;
      if (nl == std::string::npos)
        break;
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
  if (v.is_undef())
    return "";
  if (v.is_string()) {
    valstr = v.as_string();
  } else {
    // Use the in-tree printer (no third-party dep) with compact output
    // AND sorted keys (matches TS canonical's stringify replacer); then
    // strip double-quotes (TS regex /"/g).
    std::string raw;
    _jsonify_inner(v, raw, 0, 0, true);
    valstr.reserve(raw.size());
    for (char c : raw)
      if (c != '"')
        valstr.push_back(c);
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
        if (e.is_int())
          parts.push_back(std::to_string(e.as_int()));
        else if (e.is_double())
          parts.push_back(std::to_string(static_cast<int64_t>(std::floor(e.as_double()))));
        else {
          std::string s = e.as_string();
          // Strip dots — TS regex /\./g.
          std::string filtered;
          for (char c : s)
            if (c != '.')
              filtered += c;
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
  int end = std::max(0, endin);
  if (valid) {
    int total = static_cast<int>(parts.size());
    int new_end = total - end;
    if (new_end < start)
      new_end = start;
    if (new_end > total)
      new_end = total;
    std::vector<std::string> sliced(parts.begin() + std::min(start, total),
                                    parts.begin() + new_end);
    if (sliced.empty())
      return "<root>";
    std::string out;
    for (size_t i = 0; i < sliced.size(); i++) {
      if (i > 0)
        out += ".";
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
    if (k.empty())
      k = "$KEY" + std::to_string(i);
    ++it;
    i++;
    Value v = (it != kv.end()) ? *it : Value(nullptr);
    if (it != kv.end()) {
      ++it;
      i++;
    }
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

using WalkApply = std::function<Value(const Value& key, const Value& val, const Value& parent,
                                      const std::vector<std::string>& path)>;

namespace detail {

inline Value walk_descend(Value val, const WalkApply& before, const WalkApply& after, int maxdepth,
                          const Value& key, const Value& parent, std::vector<std::string>& path) {
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
  if (after)
    out = after(key, out, parent, path);
  return out;
}

} // namespace detail

inline Value walk_v(const Value& val, WalkApply before, WalkApply after, int maxdepth) {
  std::vector<std::string> path;
  return detail::walk_descend(val, before, after, maxdepth, Value::undef(), Value::undef(), path);
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
  if (!list.is_list())
    return list;
  auto src = list.as_list();
  if (src->empty())
    return Value(nullptr);
  if (src->size() == 1)
    return (*src)[0];

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

    WalkApply before = [&](const Value& key, const Value& val, const Value& parent,
                           const std::vector<std::string>& path) -> Value {
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
        if (dst[pI].is_undef())
          dst[pI] = Value::undef();
      }
      Value tval = dst[pI];
      if (typify(val) == typify(tval)) {
        cur[pI] = tval;
      } else if ((typify(val) & T_instance) == 0) {
        // Otherwise the override wins: a plain node is copied, taking
        // nothing from the destination, so no later merge writes into it.
        cur[pI] = val.is_list() ? Value(std::make_shared<List>())
                                : Value(std::shared_ptr<Map>(new Map()));
        dst[pI] = Value::undef();
      } else {
        // A class instance is kept as is, so there is nothing to descend.
        cur[pI] = val;
        return Value::undef();
      }
      return val;
    };

    WalkApply after = [&](const Value& key, const Value& val_unused, const Value& parent,
                          const std::vector<std::string>& path) -> Value {
      int cI = static_cast<int>(path.size());
      if (key.is_undef() || cI <= 0) {
        return cur[0];
      }
      cur[cI - 1] = setprop(cur[cI - 1], key, cur[cI]);
      // walk writes this back into the override, so it is the override's
      // own child, leaving the override unchanged.
      return lookup_v(parent, key);
    };

    walk_v(obj, before, after, md);
    out = cur[0];
  }

  if (md == 0) {
    Value last = src->back();
    if (last.is_list())
      out = Value(std::make_shared<List>());
    else if (last.is_map())
      out = Value(std::shared_ptr<Map>(new Map()));
    else
      out = last;
  }
  return out;
}

// ===========================================================================
// pathParts — a string path's parts, shared by getpath / setpath
// ===========================================================================

namespace detail {
inline std::vector<std::string> path_parts(const std::string& s) {
  std::vector<std::string> out;
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
} // namespace detail

// ===========================================================================
// setpath
// ===========================================================================

inline Value setpath_v(const Value& store, const Value& path, const Value& val) {
  if (iscondensed(store))
    throw std::runtime_error(S_IMMUTABLE());

  // The parts stay as given: setprop decides what a number or string key names.
  std::vector<Value> parts;
  if (path.is_string()) {
    for (const auto& part : detail::path_parts(path.as_string()))
      parts.emplace_back(part);
  } else if (path.is_list()) {
    parts.assign(path.as_list()->begin(), path.as_list()->end());
  } else if (path.is_number()) {
    parts.push_back(path);
  } else {
    return Value::undef();
  }
  if (parts.empty())
    return Value::undef();

  // A number next part makes a list; string paths only create maps.
  Value parent = store;
  for (size_t i = 0; i + 1 < parts.size(); i++) {
    Value next = getprop(parent, parts[i]);
    if (!isnode(next)) {
      next = 0 != (T_number & typify(parts[i + 1])) ? Value(std::make_shared<List>())
                                                    : Value(std::shared_ptr<Map>(new Map()));
      setprop(parent, parts[i], next);
    }
    parent = next;
  }
  if (is_delete(val)) {
    delprop(parent, parts.back());
  } else {
    setprop(parent, parts.back(), val);
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
  std::shared_ptr<std::vector<std::string>> keys; // shared with prior
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

  Injection(const Value& val_in, const Value& parent_in) : val(val_in), parent(parent_in) {
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
      if (dv && dv->is_int())
        d = dv->as_int();
      m->set("__d", Value(d + 1));
    }
    if (path.size() < 2)
      return dparent;
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
        if (!dpath.empty())
          dpath.pop_back();
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
    cinj->keys = keys_in; // shared reference
    cinj->key = ck;
    cinj->path = path; // copy
    cinj->path.push_back(ck);
    cinj->nodes = std::make_shared<std::vector<Value>>(*nodes);
    cinj->nodes->push_back(val);
    cinj->mode = mode;
    cinj->handler = handler;
    cinj->modify = modify;
    cinj->base = base;
    cinj->meta = meta; // shared reference
    cinj->errs = errs; // shared reference
    cinj->prior = this;
    cinj->dpath = dpath; // copy
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
      if (idx_n < 0 || idx_p < 0)
        return Value::undef();
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
// condense / expand / iscondensed / condenseview
// ===========================================================================

namespace detail {

constexpr int64_t CONDENSE_VERSION = 1;

constexpr int64_t CONDENSE_MAP = 0;
constexpr int64_t CONDENSE_LIST = 1;
constexpr int64_t CONDENSE_STR = 2;
constexpr int64_t CONDENSE_NUM = 3;
constexpr int64_t CONDENSE_TRUE = 4;
constexpr int64_t CONDENSE_FALSE = 5;
constexpr int64_t CONDENSE_NULL = 6;

inline const std::string& S_condense() {
  static const std::string s = "$condense";
  return s;
}
inline const std::string& S_condsym() {
  static const std::string s = "sym";
  return s;
}
inline const std::string& S_condnode() {
  static const std::string s = "node";
  return s;
}
inline const std::string& S_condroot() {
  static const std::string s = "root";
  return s;
}

// The integer a number holds: false for anything else, a fraction included.
inline bool cond_int(const Value& v, int64_t& out) {
  if (v.is_int()) {
    out = v.as_int();
    return true;
  }
  if (v.is_double()) {
    double d = v.as_double();
    if (std::floor(d) == d && -0x1p63 <= d && d < 0x1p63) {
      out = static_cast<int64_t>(d);
      return true;
    }
  }
  return false;
}

// An index read from the format, or -1 when the value cannot be one.
inline int64_t cond_idx(const Value& v) {
  int64_t i = -1;
  return cond_int(v, i) ? i : -1;
}

inline const List* cond_list(const Value& v) {
  const auto* l = std::get_if<std::shared_ptr<List>>(&v.storage);
  return l ? l->get() : nullptr;
}

inline const Value* cond_field(const Value& cond, const std::string& name) {
  const auto* m = std::get_if<std::shared_ptr<Map>>(&cond.storage);
  return m && *m ? (*m)->find(name) : nullptr;
}

inline const List* cond_fieldlist(const Value& cond, const std::string& name) {
  const Value* f = cond_field(cond, name);
  return f ? cond_list(*f) : nullptr;
}

inline int64_t cond_root(const Value& cond) {
  const Value* root = cond_field(cond, S_condroot());
  return root ? cond_idx(*root) : -1;
}

// Node idx's encoding; nullptr when it is absent or null.
inline const Value* cond_enc(const Value& cond, int64_t idx) {
  const List* node = cond_fieldlist(cond, S_condnode());
  if (!node || idx < 0 || static_cast<uint64_t>(idx) >= node->size())
    return nullptr;
  const Value& enc = (*node)[static_cast<size_t>(idx)];
  return enc.is_undef() || enc.is_null() ? nullptr : &enc;
}

inline int64_t cond_kind(const List* el) {
  return el && !el->empty() ? cond_idx((*el)[0]) : -1;
}

// sym[id]; nullptr when id does not index sym.
inline const Value* cond_sym(const Value& cond, const Value& id) {
  const List* sym = cond_fieldlist(cond, S_condsym());
  int64_t i = cond_idx(id);
  return sym && 0 <= i && static_cast<uint64_t>(i) < sym->size() ? &(*sym)[static_cast<size_t>(i)]
                                                                 : nullptr;
}

inline std::string cond_numstr(double d) {
  char buf[40];
  if (std::isnan(d))
    return "NaN";
  if (std::isinf(d))
    return d < 0 ? "-Infinity" : "Infinity";
  if (std::floor(d) == d && std::fabs(d) < 1e21) {
    std::snprintf(buf, sizeof buf, "%.0f", 0 == d ? 0.0 : d);
    return buf;
  }
  for (int p = 1; p <= 17; p++) {
    std::snprintf(buf, sizeof buf, "%.*g", p, d);
    if (std::strtod(buf, nullptr) == d)
      break;
  }
  return buf;
}

// JS `'' + v`.
inline std::string cond_str(const Value& v) {
  if (v.is_string())
    return v.as_string();
  if (v.is_int())
    return std::to_string(v.as_int());
  if (v.is_double())
    return cond_numstr(v.as_double());
  if (v.is_bool())
    return v.as_bool() ? "true" : "false";
  if (v.is_null())
    return "null";
  if (v.is_undef())
    return "undefined";
  if (const List* l = cond_list(v)) {
    std::string out;
    for (size_t i = 0; i < l->size(); i++) {
      if (0 < i)
        out += ",";
      if (!(*l)[i].is_undef() && !(*l)[i].is_null())
        out += cond_str((*l)[i]);
    }
    return out;
  }
  return "[object Object]";
}

// sym[id] as a map key: its string form when it is not a string.
inline std::string cond_keyname(const Value& cond, const Value& id) {
  const Value* s = cond_sym(cond, id);
  return s ? cond_str(*s) : "undefined";
}

// Code-point order: in UTF-8, std::string's unsigned byte order.
inline int64_t cond_symid(const Value& cond, const std::string& key) {
  const List* sym = cond_fieldlist(cond, S_condsym());
  if (!sym)
    return -1;
  int64_t lo = 0;
  int64_t hi = static_cast<int64_t>(sym->size()) - 1;
  while (lo <= hi) {
    int64_t mid = (lo + hi) / 2;
    const Value& s = (*sym)[static_cast<size_t>(mid)];
    int c = (s.is_string() ? s.as_string() : S_MT()).compare(key);
    if (0 == c)
      return mid;
    if (0 > c)
      lo = mid + 1;
    else
      hi = mid - 1;
  }
  return -1;
}

// The node index of key inside node idx, or -1. Touches only this node.
inline int64_t cond_child(const Value& cond, int64_t idx, const std::string& key) {
  const Value* enc = cond_enc(cond, idx);
  const List* el = enc ? cond_list(*enc) : nullptr;
  int64_t kind = cond_kind(el);

  if (CONDENSE_MAP == kind) {
    int64_t symid = cond_symid(cond, key);
    int64_t lo = 0;
    int64_t hi = (static_cast<int64_t>(el->size()) - 1) / 2 - 1;
    while (0 <= symid && lo <= hi) {
      int64_t mid = (lo + hi) / 2;
      int64_t k = cond_idx((*el)[static_cast<size_t>(1 + mid * 2)]);
      if (k == symid)
        return cond_idx((*el)[static_cast<size_t>(2 + mid * 2)]);
      if (k < symid)
        lo = mid + 1;
      else
        hi = mid - 1;
    }
    return -1;
  }

  if (CONDENSE_LIST == kind) {
    int64_t i = -1;
    return canon_listindex(key, i) && 0 <= i && i < static_cast<int64_t>(el->size()) - 1
               ? cond_idx((*el)[static_cast<size_t>(1 + i)])
               : -1;
  }

  return -1;
}

// Walk a path from node idx: the node index reached, or -1.
inline int64_t cond_resolve(const Value& cond, int64_t idx, const Value& path) {
  int64_t at = idx;

  if (const List* parts = cond_list(path)) {
    for (const Value& part : *parts) {
      if (0 > at || (!part.is_string() && !part.is_number()))
        return -1;
      if (!part.is_string() || !part.as_string().empty())
        at = cond_child(cond, at, cond_str(part));
    }
  } else if (path.is_string()) {
    const std::string& s = path.as_string();
    size_t from = 0;
    for (size_t j = 0; !s.empty() && j <= s.size(); j++) {
      if (j < s.size() && '.' != s[j])
        continue;
      if (0 > at)
        return -1;
      if (from < j)
        at = cond_child(cond, at, s.substr(from, j - from));
      from = j + 1;
    }
  } else if (!path.is_undef() && !path.is_null()) {
    if (0 > at)
      return -1;
    at = cond_child(cond, at, cond_str(path));
  }

  return at;
}

// A fresh, independent tree for node idx; undefined when there is no such node.
inline Value cond_rebuild(const Value& cond, int64_t idx) {
  const Value* enc = cond_enc(cond, idx);
  if (!enc)
    return Value::undef();
  const List* el = cond_list(*enc);
  int64_t kind = cond_kind(el);

  if (CONDENSE_MAP == kind) {
    auto out = std::shared_ptr<Map>(new Map());
    for (size_t j = 1; j < el->size(); j += 2) {
      Value child = cond_rebuild(cond, j + 1 < el->size() ? cond_idx((*el)[j + 1]) : -1);
      std::string key = cond_keyname(cond, (*el)[j]);
      // As setprop does for an absent value, the key goes.
      if (child.is_undef())
        out->erase(key);
      else
        out->set(key, std::move(child));
    }
    return Value(out);
  }

  if (CONDENSE_LIST == kind) {
    auto out = std::make_shared<List>();
    out->reserve(el->size() - 1);
    for (size_t j = 1; j < el->size(); j++)
      out->push_back(cond_rebuild(cond, cond_idx((*el)[j])));
    return Value(out);
  }

  if (CONDENSE_STR == kind) {
    const Value* s = 1 < el->size() ? cond_sym(cond, (*el)[1]) : nullptr;
    return s ? clone(*s) : Value::undef();
  }

  if (CONDENSE_NUM == kind)
    return 1 < el->size() ? clone((*el)[1]) : Value::undef();

  if (CONDENSE_TRUE == kind || CONDENSE_FALSE == kind)
    return Value(CONDENSE_TRUE == kind);

  return Value(nullptr);
}

inline std::vector<std::string> cond_keys(const Value& cond, int64_t idx) {
  std::vector<std::string> out;
  const Value* enc = cond_enc(cond, idx);
  const List* el = enc ? cond_list(*enc) : nullptr;
  int64_t kind = cond_kind(el);

  if (CONDENSE_MAP == kind) {
    for (size_t j = 1; j < el->size(); j += 2)
      out.push_back(cond_keyname(cond, (*el)[j]));
  } else if (CONDENSE_LIST == kind) {
    for (size_t j = 1; j < el->size(); j++)
      out.push_back(std::to_string(j - 1));
  }

  return out;
}

// Equal numbers spell the same, so an integer and a decimal of one value share a node.
inline std::string cond_numkey(const Value& v) {
  int64_t i = 0;
  if (cond_int(v, i))
    return std::to_string(i);
  char buf[40];
  std::snprintf(buf, sizeof buf, "%.17g", v.as_double());
  return buf;
}

class Condenser {
public:
  // Pass one: every distinct map key and string value, sorted.
  explicit Condenser(const Value& val) {
    collect(val);
    std::sort(syms_.begin(), syms_.end(),
              [](const std::string* a, const std::string* b) { return *a < *b; });
    syms_.erase(std::unique(syms_.begin(), syms_.end(),
                            [](const std::string* a, const std::string* b) { return *a == *b; }),
                syms_.end());
  }

  Value condense(const Value& val) {
    int64_t root = build(val);

    auto sym = std::make_shared<List>();
    sym->reserve(syms_.size());
    for (const std::string* s : syms_)
      sym->push_back(Value(*s));

    auto out = std::shared_ptr<Map>(new Map());
    out->set(S_condense(), Value(CONDENSE_VERSION));
    out->set(S_condsym(), Value(sym));
    out->set(S_condnode(), Value(node_));
    out->set(S_condroot(), Value(root));
    return Value(out);
  }

private:
  std::vector<const std::string*> syms_;
  std::shared_ptr<List> node_ = std::make_shared<List>();
  std::unordered_map<std::string, int64_t> seen_;

  void collect(const Value& n) {
    if (n.is_map()) {
      for (const auto& [k, v] : *n.as_map()) {
        syms_.push_back(&k);
        collect(v);
      }
    } else if (const List* l = cond_list(n)) {
      for (const Value& c : *l)
        collect(c);
    } else if (n.is_string()) {
      syms_.push_back(&n.as_string());
    }
  }

  int64_t symid(const std::string& s) const {
    auto it = std::lower_bound(syms_.begin(), syms_.end(), &s,
                               [](const std::string* a, const std::string* b) { return *a < *b; });
    return it != syms_.end() && **it == s ? it - syms_.begin() : -1;
  }

  // Post-order, so identical subtrees are already interned when a parent names them.
  int64_t build(const Value& n) {
    auto enc = std::make_shared<List>();

    if (n.is_map()) {
      std::vector<std::pair<int64_t, const Value*>> pairs;
      for (const auto& [k, v] : *n.as_map())
        pairs.emplace_back(symid(k), &v);
      std::sort(pairs.begin(), pairs.end(),
                [](const auto& a, const auto& b) { return a.first < b.first; });
      enc->push_back(Value(CONDENSE_MAP));
      for (const auto& [id, v] : pairs) {
        enc->push_back(Value(id));
        enc->push_back(Value(build(*v)));
      }
    } else if (const List* l = cond_list(n)) {
      enc->push_back(Value(CONDENSE_LIST));
      for (const Value& c : *l)
        enc->push_back(Value(build(c)));
    } else if (n.is_string()) {
      enc->push_back(Value(CONDENSE_STR));
      enc->push_back(Value(symid(n.as_string())));
    } else if (n.is_number()) {
      enc->push_back(Value(CONDENSE_NUM));
      enc->push_back(n);
    } else if (n.is_bool()) {
      enc->push_back(Value(n.as_bool() ? CONDENSE_TRUE : CONDENSE_FALSE));
    } else {
      enc->push_back(Value(CONDENSE_NULL));
    }

    return intern(enc);
  }

  // An encoding equal to one already built reuses that node.
  int64_t intern(const std::shared_ptr<List>& enc) {
    std::string key;
    for (size_t i = 0; i < enc->size(); i++) {
      if (0 < i)
        key += ",";
      key += cond_numkey((*enc)[i]);
    }
    auto hit = seen_.find(key);
    if (hit != seen_.end())
      return hit->second;
    int64_t idx = static_cast<int64_t>(node_->size());
    node_->push_back(Value(enc));
    seen_.emplace(std::move(key), idx);
    return idx;
  }
};

} // namespace detail

inline bool iscondensed(const Value& val) {
  int64_t version = -1;
  const Value* ver = detail::cond_field(val, detail::S_condense());
  const Value* root = detail::cond_field(val, detail::S_condroot());
  return ver && detail::cond_int(*ver, version) && detail::CONDENSE_VERSION == version &&
         detail::cond_fieldlist(val, detail::S_condsym()) &&
         detail::cond_fieldlist(val, detail::S_condnode()) && root && root->is_number();
}

// Pure: the same input gives the same bytes, on every port.
inline Value condense(const Value& val) {
  return detail::Condenser(val).condense(val);
}

// A value that is not condensed comes back as itself.
inline Value expand(const Value& cond) {
  if (!iscondensed(cond))
    return cond;
  return detail::cond_rebuild(cond, detail::cond_root(cond));
}

// A cursor into a condensed structure. Views made by at() share the memo, so ref()
// hands every one of them the same node.
class CondenseView {
public:
  CondenseView(Value cond, int64_t start, std::shared_ptr<Map> memo)
      : cond_(std::move(cond)), start_(start), memo_(std::move(memo)) {}

  Value get(const Value& path = Value::undef()) const {
    return detail::cond_rebuild(cond_, detail::cond_resolve(cond_, start_, path));
  }

  std::vector<std::string> keys(const Value& path = Value::undef()) const {
    return detail::cond_keys(cond_, detail::cond_resolve(cond_, start_, path));
  }

  bool has(const Value& path = Value::undef()) const {
    return 0 <= detail::cond_resolve(cond_, start_, path);
  }

  CondenseView at(const Value& path = Value::undef()) const {
    return CondenseView(cond_, detail::cond_resolve(cond_, start_, path), memo_);
  }

  Value value() const { return detail::cond_rebuild(cond_, start_); }

  int64_t size() const {
    const Value* enc = detail::cond_enc(cond_, start_);
    const List* el = enc ? detail::cond_list(*enc) : nullptr;
    int64_t kind = detail::cond_kind(el);
    if (detail::CONDENSE_MAP == kind)
      return (static_cast<int64_t>(el->size()) - 1) / 2;
    if (detail::CONDENSE_LIST == kind)
      return static_cast<int64_t>(el->size()) - 1;
    return 0;
  }

  bool exists() const { return 0 <= start_; }

  // Shared, unlike get() and value(): mutating the result changes every reader of the node.
  Value ref() const {
    std::string k = std::to_string(start_);
    if (const Value* hit = memo_->find(k))
      return *hit;
    Value out = detail::cond_rebuild(cond_, start_);
    if (!out.is_undef())
      memo_->set(k, out);
    return out;
  }

private:
  Value cond_;
  int64_t start_;
  std::shared_ptr<Map> memo_;
};

inline CondenseView condenseview(const Value& cond, const Value& idx = Value::undef(),
                                 const Value& memo = Value::undef()) {
  int64_t start = idx.is_undef() || idx.is_null()
                      ? (iscondensed(cond) ? detail::cond_root(cond) : -1)
                      : detail::cond_idx(idx);
  return CondenseView(cond, start, memo.is_map() ? memo.as_map() : std::shared_ptr<Map>(new Map()));
}

// ===========================================================================
// getpath
// ===========================================================================

namespace detail {

inline Value getpath_inner(const Value& store, const Value& path, std::vector<std::string>& parts,
                           Injection* inj);

} // namespace detail

inline Value getpath_v(const Value& store, const Value& path, Injection* inj) {
  std::vector<std::string> parts;
  if (path.is_string()) {
    parts = detail::path_parts(path.as_string());
  } else if (path.is_list()) {
    // A number part reads as its string form; any other part makes the whole path miss.
    for (const Value& part : *path.as_list()) {
      if (part.is_string())
        parts.push_back(part.as_string());
      else if (part.is_number())
        parts.push_back(detail::cond_str(part));
      else
        return Value::undef();
    }
  } else if (path.is_number()) {
    parts.push_back(detail::cond_str(path));
  } else {
    return Value::undef();
  }

  // A base changes what the path resolves against, so honour it on the expansion.
  if (iscondensed(store)) {
    if (!inj || inj->base.empty()) {
      Value found =
          detail::cond_rebuild(store, detail::cond_resolve(store, detail::cond_root(store), path));
      // Group A, as a plain getpath reads it: a stored null is absent.
      return found.is_null() ? Value::undef() : found;
    }
    return getpath_v(expand(store), path, inj);
  }

  Value val = detail::getpath_inner(store, path, parts, inj);
  if (inj && inj->handler) {
    std::string ref = path.is_undef() ? "" : pathify(path);
    val = inj->handler(*inj, val, ref, store);
  }
  return val;
}

namespace detail {

inline Value getpath_inner(const Value& store, const Value& path, std::vector<std::string>& parts,
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

      // $$ -> $ (skip the std::regex for the common no-"$$" segment)
      if (part.find("$$") != std::string::npos) {
        part = std::regex_replace(part, R_DOUBLE_DOLLAR(), "$");
      }

      if (part.empty()) {
        int ascends = 0;
        while (1 + pI < numparts && parts[1 + pI].empty()) {
          ascends++;
          pI++;
        }
        if (inj && ascends > 0) {
          if (pI == numparts - 1)
            ascends--;
          if (ascends == 0) {
            val = dparent;
          } else if (dpath) {
            int dlen = static_cast<int>(dpath->size());
            int cut = dlen - ascends;
            if (cut < 0)
              cut = 0;
            std::vector<std::string> fullpath(dpath->begin(), dpath->begin() + cut);
            for (int j = pI + 1; j < numparts; j++) {
              fullpath.push_back(parts[j]);
            }
            if (ascends <= dlen) {
              auto fp = std::make_shared<List>();
              for (auto& p : fullpath)
                fp->push_back(Value(p));
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

} // namespace detail

// ===========================================================================
// _invalidTypeMsg / _injectstr / _injecthandler
// ===========================================================================

inline std::string invalid_type_msg(const std::vector<std::string>& path,
                                    const std::string& need_type, int vt, const Value& v,
                                    const std::string& whence = "") {
  (void) whence;
  std::string vs = (v.is_undef() || v.is_null()) ? "no value" : stringify(v);
  std::string out = "Expected ";
  if (path.size() > 1) {
    auto pl = std::make_shared<List>();
    for (auto& p : path)
      pl->push_back(Value(p));
    out += "field " + pathify(Value(pl), 1, 0) + " to be ";
  }
  out += need_type + ", but found ";
  if (!v.is_undef() && !v.is_null()) {
    out += typename_str(vt) + ": ";
  }
  out += vs + ".";
  return out;
}

inline std::string invalid_type_msg(const Value& path_v, const std::string& need_type, int vt,
                                    const Value& v, const std::string& whence = "") {
  std::vector<std::string> p;
  if (path_v.is_list()) {
    for (const auto& e : *path_v.as_list())
      p.push_back(strkey(e));
  } else if (path_v.is_string()) {
    p.push_back(path_v.as_string());
  }
  return invalid_type_msg(p, need_type, vt, v, whence);
}

// MODENAME / PLACEMENT helpers.
inline std::string modename(int mode) {
  switch (mode) {
  case M_VAL:
    return "val";
  case M_KEYPRE:
    return "key:pre";
  case M_KEYPOST:
    return "key:post";
  default:
    return "";
  }
}
inline std::string placement(int mode) {
  switch (mode) {
  case M_VAL:
    return "value";
  case M_KEYPRE:
  case M_KEYPOST:
    return "key";
  default:
    return "";
  }
}

// _injecthandler: forward declared, defined below after Injection helpers.
inline Value injecthandler(Injection& inj, const Value& val, const std::string& ref,
                           const Value& store);

inline Value injectstr(const std::string& val, const Value& store, Injection* inj) {
  if (val.empty())
    return Value(std::string(""));

  std::smatch m;
  if (std::regex_match(val, m, R_INJECTION_FULL())) {
    if (inj)
      inj->full = true;
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
    if (inj)
      inj->full = false;
    Value found = getpath_v(store, Value(ref), inj);
    if (found.is_undef()) {
      // append nothing
    } else if (found.is_null()) {
      out += "null";
    } else if (found.is_string()) {
      out += found.as_string();
    } else {
      // Compact JSON for non-string injection — no third-party dep.
      _jsonify_inner(found, out, 0, 0);
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

inline Value injecthandler(Injection& inj, const Value& val, const std::string& ref,
                           const Value& store) {
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

inline bool checkPlacement(int modes, const std::string& ijname, int parent_types, Injection& inj) {
  if ((modes & inj.mode) == 0) {
    std::string allowed;
    int first = 1;
    for (int m : {M_KEYPRE, M_KEYPOST, M_VAL}) {
      if (modes & m) {
        if (!first)
          allowed += ",";
        allowed += placement(m);
        first = 0;
      }
    }
    inj.errs->push_back(Value("$" + ijname + ": invalid placement as " + placement(inj.mode) +
                              ", expected: " + allowed + "."));
    return false;
  }
  if (parent_types != 0) {
    int ptype = typify(inj.parent);
    if ((parent_types & ptype) == 0) {
      inj.errs->push_back(Value("$" + ijname + ": invalid placement in parent " +
                                typename_str(ptype) + ", expected: " + typename_str(parent_types) +
                                "."));
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
      out[0] = Value("invalid argument: " + stringify(arg, 22) + " (" + typename_str(argType) +
                     " at position " + std::to_string(1 + i) +
                     ") is not of type: " + typename_str(arg_types[i]) + ".");
      return out;
    }
    out[i + 1] = arg;
  }
  return out;
}

// Forward decl: inject is defined below.
inline std::unique_ptr<Injection> injectChild_helper(const Value& child, const Value& store,
                                                     Injection& inj);

inline Injection& injectChild(const Value& child, const Value& store,
                              Injection& inj); // signature only; inline below

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
      (void) sl;
    }
    inj_owner->meta->set("__d", Value(int64_t(0)));

    if (injdef) {
      if (injdef->modify)
        inj_owner->modify = injdef->modify;
      if (!injdef->extra.is_undef())
        inj_owner->extra = injdef->extra;
      if (injdef->meta)
        inj_owner->meta = injdef->meta;
      if (injdef->handler)
        inj_owner->handler = injdef->handler;
      if (!injdef->base.empty())
        inj_owner->base = injdef->base;
      if (!injdef->dparent.is_undef())
        inj_owner->dparent = injdef->dparent;
      if (injdef->errs && !injdef->errs->empty())
        inj_owner->errs = injdef->errs;
      // Always honor an external errs list pointer if one is supplied.
      if (injdef->errs)
        inj_owner->errs = injdef->errs;
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
        if (k.find('$') == std::string::npos)
          nodekeys->push_back(k);
      }
      for (const auto& k : node_keys_vec) {
        if (k.find('$') != std::string::npos)
          nodekeys->push_back(k);
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
  return lookup_v(inj->parent, Value(S_DTOP()));
}

// injectChild definition (after inject is declared).
inline Injection& injectChild(const Value& child, const Value& store, Injection& inj) {
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

inline Value DELETE_FN(Injection& inj, const Value& val, const std::string& ref,
                       const Value& store) {
  inj.setval(Value::undef());
  return Value::undef();
}

inline Value COPY_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  if (!checkPlacement(M_VAL, "COPY", T_any, inj))
    return Value::undef();
  Value out = lookup_v(inj.dparent, Value(inj.key));
  inj.setval(out);
  return out;
}

inline Value KEY_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  if (inj.mode != M_VAL)
    return Value::undef();
  Value keyspec = lookup_v(inj.parent, Value(S_BKEY()));
  if (!keyspec.is_undef()) {
    delprop(inj.parent, Value(S_BKEY()));
    return getprop(inj.dparent, keyspec);
  }
  Value anno = lookup_v(inj.parent, Value(S_BANNO()));
  Value alt = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
  // Canonical: `_lookup(anno, S_KEY) ?? getelem(path, -2)` — null/undef -> alt.
  Value k = lookup_v(anno, Value("KEY"));
  if (k.is_undef() || k.is_null())
    return alt;
  return k;
}

inline Value ANNO_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  delprop(inj.parent, Value(S_BANNO()));
  return Value::undef();
}

inline Value MERGE_FN(Injection& inj, const Value& val, const std::string& ref,
                      const Value& store) {
  if (inj.mode == M_KEYPRE)
    return Value(inj.key);
  if (inj.mode != M_KEYPOST)
    return Value::undef();

  Value args = getprop(inj.parent, Value(inj.key));
  auto arg_list = std::make_shared<List>();
  if (args.is_list()) {
    for (const auto& e : *args.as_list())
      arg_list->push_back(e);
  } else {
    arg_list->push_back(args);
  }
  inj.setval(Value::undef());

  auto merge_args = std::make_shared<List>();
  merge_args->push_back(inj.parent);
  for (const auto& a : *arg_list)
    merge_args->push_back(a);
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
          for (const auto& e : *x.as_list())
            out->push_back(rec(e));
          return Value(out);
        }
        if (x.is_map()) {
          auto out = std::shared_ptr<Map>(new Map());
          for (const auto& [k, e] : *x.as_map())
            out->set(k, rec(e));
          return Value(out);
        }
        return f(x);
      };
      return rec(v);
    };
    F["identity"] = [](const Value& v) { return v; };
    F["upper"] = [deep_apply](const Value& v) {
      return deep_apply(v, [](const Value& x) -> Value {
        if (isnode(x))
          return x;
        std::string s = js_string(x);
        for (auto& c : s)
          c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        return Value(s);
      });
    };
    F["lower"] = [deep_apply](const Value& v) {
      return deep_apply(v, [](const Value& x) -> Value {
        if (isnode(x))
          return x;
        std::string s = js_string(x);
        for (auto& c : s)
          c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        return Value(s);
      });
    };
    F["string"] = [deep_apply](const Value& v) {
      return deep_apply(v, [](const Value& x) -> Value {
        if (isnode(x))
          return x;
        return Value(js_string(x));
      });
    };
    F["number"] = [deep_apply](const Value& v) {
      return deep_apply(v, [](const Value& x) -> Value {
        if (isnode(x))
          return x;
        if (x.is_number())
          return x;
        try {
          double d = std::stod(js_string(x));
          if (std::isnan(d))
            return Value(int64_t(0));
          if (std::floor(d) == d)
            return Value(static_cast<int64_t>(d));
          return Value(d);
        } catch (...) {
          return Value(int64_t(0));
        }
      });
    };
    F["integer"] = [deep_apply](const Value& v) {
      return deep_apply(v, [](const Value& x) -> Value {
        if (isnode(x))
          return x;
        try {
          return Value(static_cast<int64_t>(std::stod(js_string(x))));
        } catch (...) {
          return Value(int64_t(0));
        }
      });
    };
    F["concat"] = [](const Value& v) -> Value {
      if (!v.is_list())
        return v;
      std::string out;
      for (const auto& e : *v.as_list()) {
        if (!isnode(e))
          out += js_string(e);
      }
      return Value(out);
    };
  }
  return F;
}

inline Value FORMAT_FN(Injection& inj, const Value& val, const std::string& ref,
                       const Value& store) {
  // Truncate keys to single element.
  if (inj.keys && inj.keys->size() > 1) {
    inj.keys->resize(1);
  }
  if (inj.mode != M_VAL)
    return Value::undef();

  Value name = lookup_v(inj.parent, Value(int64_t(1)));
  Value child = lookup_v(inj.parent, Value(int64_t(2)));

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

inline Value APPLY_FN(Injection& inj, const Value& val, const std::string& ref,
                      const Value& store) {
  if (!checkPlacement(M_VAL, "APPLY", T_list, inj))
    return Value::undef();
  std::vector<Value> args;
  if (inj.parent.is_list()) {
    auto pl = inj.parent.as_list();
    for (size_t i = 1; i < pl->size(); i++)
      args.push_back((*pl)[i]);
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

inline Value EACH_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  if (!checkPlacement(M_VAL, "EACH", T_list, inj))
    return Value::undef();
  if (inj.keys && inj.keys->size() > 1) {
    inj.keys->resize(1);
  }
  std::vector<Value> args;
  if (inj.parent.is_list()) {
    auto pl = inj.parent.as_list();
    for (size_t i = 1; i < pl->size(); i++)
      args.push_back((*pl)[i]);
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
    for (size_t i = 0; i < sl->size(); i++)
      tval->push_back(clone(child));
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
      for (const auto& e : *src.as_list())
        tcur_list->push_back(e);
      tcur = Value(tcur_list);
    } else if (src.is_map()) {
      auto tcur_list = std::make_shared<List>();
      for (const auto& [_, e] : *src.as_map())
        tcur_list->push_back(e);
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
        if (dot == std::string::npos) {
          dpath.push_back(srcpath.substr(pos));
          break;
        }
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
    tinj->nodes = std::make_shared<std::vector<Value>>(inj.nodes->begin(), inj.nodes->end() - 1);
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

inline Value PACK_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  if (!checkPlacement(M_KEYPRE, "PACK", T_map, inj))
    return Value::undef();

  Value args = getprop(inj.parent, Value(inj.key));
  std::vector<Value> arg_list;
  if (args.is_list()) {
    for (const auto& e : *args.as_list())
      arg_list.push_back(e);
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
    for (const auto& e : *src.as_list())
      srcList.push_back(e);
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
    } else if (keypath.is_string() && !keypath.as_string().empty() &&
               keypath.as_string()[0] == '`') {
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
      } else if (keypath.is_string() && !keypath.as_string().empty() &&
                 keypath.as_string()[0] == '`') {
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
        if (dot == std::string::npos) {
          dpath.push_back(srcpath.substr(pos));
          break;
        }
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
    tinj->nodes = std::make_shared<std::vector<Value>>(inj.nodes->begin(), inj.nodes->end() - 1);
    tinj->parent = tinj->nodes->empty() ? Value::undef() : tinj->nodes->back();
    tinj->val = Value(tval);
    tinj->dpath = dpath;
    tinj->dparent = tcur_out;

    inject(Value(tval), store, tinj);
    if (tinj->val.is_map())
      rval = tinj->val;
  }

  setprop(target, tkey, rval);
  return Value::undef();
}

inline Value REF_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  if (inj.mode != M_VAL)
    return Value::undef();
  Value refpath = lookup_v(inj.parent, Value(int64_t(1)));
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
  for (auto& p : dpath_slice)
    fp->push_back(Value(p));
  refInj.dparent = getpath_v(spec, Value(fp));
  refInj.handler = injecthandler;
  Value refResolved = getpath_v(spec, refpath, &refInj);

  Value tref = clone(refResolved);
  bool hasSubRef = false;
  if (isnode(tref)) {
    walk_v(
        tref,
        [&](const Value&, const Value& v, const Value&, const std::vector<std::string>&) -> Value {
          if (v.is_string() && v.as_string() == "`$REF`")
            hasSubRef = true;
          return v;
        });
  }

  // A recursive reference stops where the data does.
  auto tpath_list = std::make_shared<List>();
  for (size_t i = 0; i + 1 < inj.path.size(); i++)
    tpath_list->push_back(Value(inj.path[i]));
  Value tval = getpath_v(store, Value(tpath_list));
  Value rval = (!hasSubRef || !tval.is_undef()) ? tref : Value::undef();

  // The enclosing loop injects the referenced spec in this list's place, so
  // neither this pass nor this element leaves a value for modify to check.
  Value grandparent = inj.setval(rval, 2);

  if (Injection* prior = inj.prior) {
    prior->modify = nullptr;
    if (grandparent.is_list() || !rval.is_undef()) {
      prior->keyI--;
    }
  }
  return SKIP();
}

} // namespace transforms

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
    for (const auto& e : *errsRaw.as_list())
      errs->push_back(e);
  } else {
    errs = std::make_shared<std::vector<Value>>();
  }

  // Split extra into commands ($-keyed) and data.
  auto extraTransforms = std::shared_ptr<Map>(new Map());
  auto extraData = std::shared_ptr<Map>(new Map());
  if (extra.is_map()) {
    for (const auto& [k, v] : *extra.as_map()) {
      if (!k.empty() && k[0] == '$')
        extraTransforms->set(k, v);
      else
        extraData->set(k, v);
    }
  }

  auto dataMergeList = std::make_shared<List>();
  if (!extraData->empty())
    dataMergeList->push_back(Value(extraData));
  dataMergeList->push_back(clone(data));
  Value dataClone = merge_v(Value(dataMergeList));

  auto baseStore = std::shared_ptr<Map>(new Map());
  baseStore->set(S_DTOP(), dataClone);
  // $SPEC as Injector that returns origspec.
  Injector spec_supplier = [origspec](Injection&, const Value&, const std::string&,
                                      const Value&) -> Value { return origspec; };
  baseStore->set(S_DSPEC(), Value(spec_supplier));
  // $BT, $DS, $WHEN as Injectors (called via _injecthandler when matched).
  baseStore->set("$BT", Value(Injector([](Injection&, const Value&, const std::string&,
                                          const Value&) -> Value { return Value("`"); })));
  baseStore->set("$DS", Value(Injector([](Injection&, const Value&, const std::string&,
                                          const Value&) -> Value { return Value("$"); })));
  baseStore->set("$WHEN", Value(Injector([](Injection&, const Value&, const std::string&,
                                            const Value&) -> Value {
                   // ISO timestamp.
                   auto t = std::time(nullptr);
                   auto* tm = std::gmtime(&t);
                   char buf[40];
                   std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%S.000Z", tm);
                   return Value(std::string(buf));
                 })));
  baseStore->set("$DELETE", Value(Injector(transforms::DELETE_FN)));
  baseStore->set("$COPY", Value(Injector(transforms::COPY_FN)));
  baseStore->set("$KEY", Value(Injector(transforms::KEY_FN)));
  baseStore->set("$ANNO", Value(Injector(transforms::ANNO_FN)));
  baseStore->set("$MERGE", Value(Injector(transforms::MERGE_FN)));
  baseStore->set("$EACH", Value(Injector(transforms::EACH_FN)));
  baseStore->set("$PACK", Value(Injector(transforms::PACK_FN)));
  baseStore->set("$REF", Value(Injector(transforms::REF_FN)));
  baseStore->set("$FORMAT", Value(Injector(transforms::FORMAT_FN)));
  baseStore->set("$APPLY", Value(Injector(transforms::APPLY_FN)));

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
  if (modifyRaw.is_modify())
    injdef.modify = modifyRaw.as_modify();
  if (handlerRaw.is_injector())
    injdef.handler = handlerRaw.as_injector();
  if (metaRaw.is_map())
    injdef.meta = metaRaw.as_map();
  injdef.errs = errs;

  Value out = inject(workspec, store, &injdef);

  // Sync $ERRS list back to errs.
  for (const auto& e : *errsListPtr)
    errs->push_back(e);

  if (!errs->empty() && !collect) {
    std::string msg;
    for (size_t i = 0; i < errs->size(); i++) {
      if (i > 0)
        msg += " | ";
      msg += stringify((*errs)[i]);
    }
    throw std::runtime_error(msg);
  }
  // Update options.errs if the caller passed a list (back-compat).
  if (collect && errsRaw.is_list()) {
    auto rawList = errsRaw.as_list();
    rawList->clear();
    for (const auto& e : *errs)
      rawList->push_back(e);
  }
  return out;
}

// ===========================================================================
// Validate injectors
// ===========================================================================

namespace validators {

inline Value STRING_FN(Injection& inj, const Value& val, const std::string& ref,
                       const Value& store) {
  Value out = lookup_v(inj.dparent, Value(inj.key));
  int t = typify(out);
  if ((T_string & t) == 0) {
    inj.errs->push_back(Value(invalid_type_msg(inj.path, "string", t, out, "V1010")));
    return Value::undef();
  }
  if (out.as_string().empty()) {
    auto pl = std::make_shared<List>();
    for (auto& p : inj.path)
      pl->push_back(Value(p));
    inj.errs->push_back(Value("Empty string at " + pathify(Value(pl), 1, 0)));
    return Value::undef();
  }
  return out;
}

inline Value TYPE_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  std::string tname = ref.size() >= 2 ? ref.substr(1) : "";
  for (auto& c : tname)
    c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  int idx = -1;
  for (int i = 0; i < 26; i++) {
    if (typename_table(i) == tname) {
      idx = i;
      break;
    }
  }
  if (idx < 0)
    return Value::undef();
  // $NIL is absent or null.
  int typev = (1 << (31 - idx)) | (tname == "nil" ? T_null : 0);
  Value out = lookup_v(inj.dparent, Value(inj.key));
  int t = typify(out);
  if ((t & typev) == 0) {
    inj.errs->push_back(Value(invalid_type_msg(inj.path, tname, t, out, "V1001")));
    return Value::undef();
  }
  return out;
}

inline Value ANY_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  return lookup_v(inj.dparent, Value(inj.key));
}

inline Value CHILD_FN(Injection& inj, const Value& val, const std::string& ref,
                      const Value& store) {
  if (inj.mode == M_KEYPRE) {
    Value childtm = getprop(inj.parent, Value(inj.key));
    Value pkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
    Value tval = getprop(inj.dparent, pkey);

    if (tval.is_undef() || tval.is_null()) {
      tval = Value(std::shared_ptr<Map>(new Map()));
    } else if (!ismap(tval)) {
      // _validation reports the mismatch, once.
      return Value::undef();
    }
    auto ckeys = keysof(tval);
    for (const auto& ck : ckeys) {
      setprop(inj.parent, Value(ck), clone(childtm));
      if (inj.keys)
        inj.keys->push_back(ck);
    }
    inj.setval(Value::undef());
    return Value::undef();
  }
  if (inj.mode == M_VAL) {
    if (!inj.parent.is_list()) {
      inj.errs->push_back(Value("Invalid $CHILD as value"));
      return Value::undef();
    }
    Value childtm = lookup_v(inj.parent, Value(int64_t(1)));
    if (inj.dparent.is_undef() || inj.dparent.is_null()) {
      inj.parent.as_list()->clear();
      return Value::undef();
    }
    if (!inj.dparent.is_list()) {
      inj.keyI = static_cast<int>(size(inj.parent));
      return inj.dparent;
    }
    auto dpl = inj.dparent.as_list();
    auto pl = inj.parent.as_list();
    for (size_t i = 0; i < dpl->size(); i++) {
      setprop(inj.parent, Value(static_cast<int64_t>(i)), clone(childtm));
    }
    while (pl->size() > dpl->size())
      pl->pop_back();

    // NOTE: modifying inj! This extends the child value loop in inject
    // to cover every cloned child.
    if (inj.keys) {
      for (size_t ckeyI = inj.keys->size(); ckeyI < pl->size(); ckeyI++) {
        inj.keys->push_back(strkey(Value(static_cast<int64_t>(ckeyI))));
      }
    }

    // Restart the child value loop at the first element (the loop
    // increments keyI on resume) so that the first element is also
    // validated against the child template.
    inj.keyI = -1;

    // SKIP leaves the cloned child template in place at the first
    // element so the resumed loop can validate it.
    return SKIP();
  }
  return Value::undef();
}

// Lowers every `$NAME` marker in the joined description, nested ones included.
inline std::string describe_alternatives(const std::vector<Value>& tvals) {
  std::string joined;
  for (size_t i = 0; i < tvals.size(); i++) {
    if (i > 0)
      joined += ", ";
    joined += stringify(tvals[i]);
  }
  std::string out;
  auto begin = std::sregex_iterator(joined.begin(), joined.end(), R_TRANSFORM_NAME());
  size_t last = 0;
  for (auto it = begin; it != std::sregex_iterator(); ++it) {
    const std::smatch& m = *it;
    out.append(joined, last, static_cast<size_t>(m.position(0)) - last);
    std::string lower = m[1].str();
    for (auto& c : lower)
      c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    out += lower;
    last = static_cast<size_t>(m.position(0) + m.length(0));
  }
  out.append(joined, last, std::string::npos);
  return out;
}

inline Value pathlist(const std::vector<std::string>& path) {
  auto pl = std::make_shared<List>();
  for (const auto& p : path)
    pl->push_back(Value(p));
  return Value(pl);
}

// The data value at a list directive's slot. The directive's own dparent was
// read with getprop, which reports a stored null as absent.
inline Value slotval(const Injection& inj) {
  return inj.prior ? lookup_v(inj.prior->dparent, Value(inj.prior->key)) : inj.dparent;
}

// JSON equality: numbers by value, lists in order, maps by key in any order.
inline bool deepequal(const Value& a, const Value& b) {
  if (a == b)
    return true;

  int atype = typify(a);
  if (atype != typify(b) || 0 == ((T_list | T_map) & atype))
    return false;

  auto akeys = keysof(a);
  auto bkeys = keysof(b);
  if (akeys.size() != bkeys.size())
    return false;

  for (size_t kI = 0; kI < akeys.size(); kI++) {
    const std::string& k = akeys[kI];
    if (k != bkeys[kI] || !deepequal(lookup_v(a, Value(k)), lookup_v(b, Value(k))))
      return false;
  }

  return true;
}

// Every member val has is in out, unchanged. A member only out has is a
// default the spec supplied, and is ignored.
inline bool keeps(const Value& val, const Value& out) {
  if (val.is_undef())
    return true;

  if (0 == ((T_list | T_map) & typify(val)) || val.is_list() != out.is_list() || !isnode(out))
    return deepequal(val, out);

  for (const auto& k : keysof(val)) {
    if (!keeps(lookup_v(val, Value(k)), lookup_v(out, Value(k))))
      return false;
  }

  return true;
}

// A spec admits a value when validating the value against it finds no error
// and gives back the value as it is.
inline bool admits(const Value& val, const Value& spec, Injection& inj, const Value& store) {
  auto vstore = std::shared_ptr<Map>(new Map());
  if (store.is_map()) {
    for (const auto& [k, v] : *store.as_map())
      vstore->set(k, v);
  }
  vstore->set(S_DTOP(), val);

  auto terrs = std::make_shared<List>();
  auto opts = std::shared_ptr<Map>(new Map());
  opts->set("extra", Value(vstore));
  opts->set("errs", Value(terrs));
  if (inj.meta)
    opts->set("meta", Value(inj.meta));

  Value out = validate(val, spec, Value(opts));

  return terrs->empty() && keeps(val, out);
}

// The bounds of a $NOF count, and the words for it. False when the count is
// invalid. Without a max, the bound is the number of specs.
inline bool nofcount(const Value& count, int64_t numtvals, int64_t& lo, int64_t& hi,
                     std::string& desc) {
  // A decimal with an integral value counts, as JavaScript does not tell 2.0 from 2.
  auto isnat = [](const Value& n, int64_t& nat) {
    double d = n.as_double();
    if (n.is_int())
      nat = n.as_int();
    else if (n.is_double() && 0 <= d && d < static_cast<double>(INT64_MAX) && std::floor(d) == d)
      nat = static_cast<int64_t>(d);
    else
      return false;
    return 0 <= nat;
  };

  if (isnat(count, lo)) {
    hi = lo;
    desc = 0 == lo ? "none" : "exactly " + std::to_string(lo);
    return true;
  }

  Value min = lookup_v(count, Value("min"));
  Value max = lookup_v(count, Value("max"));

  lo = 0;
  hi = numtvals;
  bool valid = count.is_map() && 0 < count.as_map()->size() &&
               count.as_map()->size() ==
                   static_cast<size_t>(min.is_undef() ? 0 : 1) + (max.is_undef() ? 0 : 1) &&
               (min.is_undef() || isnat(min, lo)) && (max.is_undef() || isnat(max, hi)) &&
               (min.is_undef() || max.is_undef() || lo <= hi);

  if (!valid)
    return false;

  if (max.is_undef())
    desc = "at least " + std::to_string(lo);
  else if (0 == hi)
    desc = "none";
  else if (min.is_undef())
    desc = "at most " + std::to_string(hi);
  else if (lo == hi)
    desc = "exactly " + std::to_string(lo);
  else
    desc = std::to_string(lo) + " to " + std::to_string(hi);

  return true;
}

inline Value EXACT_FN(Injection& inj, const Value& val, const std::string& ref,
                      const Value& store) {
  if (inj.mode == M_VAL) {
    if (!inj.parent.is_list() || inj.keyI != 0) {
      inj.errs->push_back(Value("The $EXACT validator at field " +
                                pathify(pathlist(inj.path), 1, 1) +
                                " must be the first element of an array."));
      return Value::undef();
    }

    Value cval = slotval(inj);

    inj.keyI = static_cast<int>(inj.keys ? inj.keys->size() : 0);

    // Replace [$EXACT, ...] with the data value; SKIP keeps inject off the detached list.
    inj.setval(cval, 2);

    if (!inj.path.empty())
      inj.path.pop_back();

    std::vector<Value> tvals;
    if (inj.parent.is_list()) {
      auto pl = inj.parent.as_list();
      for (size_t i = 1; i < pl->size(); i++)
        tvals.push_back((*pl)[i]);
    }
    if (tvals.empty()) {
      inj.errs->push_back(Value("The $EXACT validator at field " +
                                pathify(pathlist(inj.path), 1, 1) +
                                " must have at least one argument."));
      return SKIP();
    }

    for (const auto& tval : tvals) {
      if (deepequal(tval, cval))
        return SKIP();
    }

    std::string valdesc = describe_alternatives(tvals);
    inj.errs->push_back(Value(invalid_type_msg(inj.path,
                                               std::string(inj.path.size() > 1 ? "" : "value ") +
                                                   "exactly equal to " +
                                                   (tvals.size() == 1 ? "" : "one of ") + valdesc,
                                               typify(cval), cval, "V0110")));
    return SKIP();
  } else {
    delprop(inj.parent, Value(inj.key));
    return Value::undef();
  }
}

// The counting list directives. Without a count, every spec has to admit.
inline Value validatecount(Injection& inj, const Value& store, const std::string& name,
                           bool counted) {
  if (inj.mode != M_VAL)
    return Value::undef();

  if (!inj.parent.is_list() || inj.keyI != 0) {
    inj.errs->push_back(Value("The " + name + " validator at field " +
                              pathify(pathlist(inj.path), 1, 1) +
                              " must be the first element of an array."));
    return Value::undef();
  }

  Value cval = slotval(inj);

  inj.keyI = static_cast<int>(inj.keys ? inj.keys->size() : 0);

  // Replace the directive's list with the data value. Each return is SKIP, so
  // that inject leaves the detached list alone and validates nothing in it.
  inj.setval(cval, 2);

  if (!inj.path.empty())
    inj.path.pop_back();

  auto pl = inj.parent.as_list();
  size_t first = counted ? 2 : 1;
  Value count = counted ? lookup_v(inj.parent, Value(int64_t(1))) : Value::undef();
  std::vector<Value> tvals;
  for (size_t i = first; i < pl->size(); i++)
    tvals.push_back((*pl)[i]);
  int64_t numtvals = static_cast<int64_t>(tvals.size());
  std::string field = "The " + name + " validator at field " + pathify(pathlist(inj.path), 1);

  if (0 == numtvals) {
    inj.errs->push_back(Value(field + (counted ? " must have a count and" : " must have") +
                              " at least one argument."));
    return SKIP();
  }

  int64_t lo = numtvals;
  int64_t hi = numtvals;
  std::string countdesc = "all";
  if (counted && !nofcount(count, numtvals, lo, hi, countdesc)) {
    inj.errs->push_back(Value(field + " has an invalid count: " + stringify(count) + "."));
    return SKIP();
  }

  int64_t admitted = 0;
  for (int64_t tI = 0; tI < numtvals; tI++) {
    int64_t left = numtvals - tI;

    // Stop once the specs left cannot change the verdict.
    if (hi < admitted || admitted + left < lo || (lo <= admitted && admitted + left <= hi))
      break;

    if (admits(cval, tvals[static_cast<size_t>(tI)], inj, store))
      admitted++;
  }

  if (admitted < lo || hi < admitted) {
    inj.errs->push_back(Value(invalid_type_msg(
        inj.path, countdesc + " of " + describe_alternatives(tvals), typify(cval), cval, "V0310")));
  }

  return SKIP();
}

// Count the specs that admit the value: ['`$NOF`', count, spec, ...], where
// count is an integer, or a map holding min, max or both.
inline Value NOF_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  return validatecount(inj, store, "$NOF", true);
}

// Every spec admits the value: ['`$ALL`', spec, ...].
inline Value ALL_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  return validatecount(inj, store, "$ALL", false);
}

// The bounds of a $LEN bound, with -1 for no maximum, and the words for it.
// False when the bound is invalid.
inline bool lenbound(const Value& bound, int64_t& lo, int64_t& hi, std::string& desc) {
  std::string countdesc;
  if (!nofcount(bound, -1, lo, hi, countdesc))
    return false;

  desc = "of length " + (lo == hi   ? std::to_string(lo)
                         : -1 == hi ? "at least " + std::to_string(lo)
                         : 0 == lo  ? "at most " + std::to_string(hi)
                                    : std::to_string(lo) + " to " + std::to_string(hi));
  return true;
}

// The words for a $RANGE bound. False when the bound is invalid.
inline bool rangedesc(const Value& bound, std::string& desc) {
  if (!bound.is_map())
    return false;

  Value min = lookup_v(bound, Value("min"));
  Value max = lookup_v(bound, Value("max"));
  Value gt = lookup_v(bound, Value("gt"));
  Value lt = lookup_v(bound, Value("lt"));
  Value lower = min.is_undef() ? gt : min;
  Value upper = max.is_undef() ? lt : max;
  auto isnum = [](const Value& n) { return n.is_undef() || 0 != (T_number & typify(n)); };

  size_t given = 0;
  for (const Value* n : {&min, &max, &gt, &lt})
    given += n->is_undef() ? 0 : 1;

  size_t numkeys = bound.as_map()->size();
  bool valid = 0 < numkeys && numkeys == given && (min.is_undef() || gt.is_undef()) &&
               (max.is_undef() || lt.is_undef()) && isnum(min) && isnum(max) && isnum(gt) &&
               isnum(lt) &&
               (lower.is_undef() || upper.is_undef() || lower.as_double() <= upper.as_double());

  if (!valid)
    return false;

  std::string lowdesc = !min.is_undef()  ? "at least " + stringify(min)
                        : !gt.is_undef() ? "greater than " + stringify(gt)
                                         : "";
  std::string updesc = !max.is_undef()  ? "at most " + stringify(max)
                       : !lt.is_undef() ? "less than " + stringify(lt)
                                        : "";
  desc = lowdesc + (lowdesc.empty() || updesc.empty() ? "" : " and ") + updesc;
  return true;
}

// A number within a valid $RANGE bound, compared as doubles, as JavaScript does.
inline bool inrange(const Value& bound, const Value& val) {
  Value min = lookup_v(bound, Value("min"));
  Value max = lookup_v(bound, Value("max"));
  Value gt = lookup_v(bound, Value("gt"));
  Value lt = lookup_v(bound, Value("lt"));
  double v = val.as_double();

  return (min.is_undef() || min.as_double() <= v) && (max.is_undef() || v <= max.as_double()) &&
         (gt.is_undef() || gt.as_double() < v) && (lt.is_undef() || v < lt.as_double());
}

// A string's length in code points: its UTF-8 bytes that do not continue a character.
inline int64_t codepoints(const std::string& s) {
  int64_t n = 0;
  for (unsigned char b : s)
    n += 0x80 == (b & 0xC0) ? 0 : 1;
  return n;
}

// A $LIKE pattern compiled by std::regex, through re_compile, which throws on a
// bad pattern. False unless it compiles.
inline bool likere(const Value& pattern, std::regex& like) {
  if (!pattern.is_string())
    return false;
  try {
    like = re_compile(pattern.as_string());
    return true;
  } catch (const std::regex_error&) {
    return false;
  }
}

// The bounding list directives: a bound or pattern, then at most one spec that also admits.
inline Value validatebound(Injection& inj, const Value& store, const std::string& name) {
  if (inj.mode != M_VAL)
    return Value::undef();

  if (!inj.parent.is_list() || inj.keyI != 0) {
    inj.errs->push_back(Value("The " + name + " validator at field " +
                              pathify(pathlist(inj.path), 1, 1) +
                              " must be the first element of an array."));
    return Value::undef();
  }

  Value cval = slotval(inj);

  inj.keyI = static_cast<int>(inj.keys ? inj.keys->size() : 0);

  // As for the counting directives: SKIP keeps inject off the detached list.
  inj.setval(cval, 2);

  if (!inj.path.empty())
    inj.path.pop_back();

  std::string field = "The " + name + " validator at field " + pathify(pathlist(inj.path), 1);
  int64_t nargs = size(inj.parent) - 1;
  bool islen = "$LEN" == name;
  bool islike = "$LIKE" == name;
  std::string argname = islike ? "pattern" : "bound";

  if (nargs < 1 || 2 < nargs) {
    inj.errs->push_back(Value(field + " must have a " + argname + " and at most one spec."));
    return SKIP();
  }

  Value bound = lookup_v(inj.parent, Value(int64_t(1)));
  std::regex like;
  int64_t lo = 0;
  int64_t hi = 0;
  std::string desc;

  bool valid = islen    ? lenbound(bound, lo, hi, desc)
               : islike ? likere(bound, like)
                        : rangedesc(bound, desc);

  if (!valid) {
    inj.errs->push_back(
        Value(field + " has an invalid " + argname + ": " + stringify(bound) + "."));
    return SKIP();
  }

  if (islike)
    desc = "like /" + bound.as_string() + "/";

  int ctype = typify(cval);

  if (2 == nargs) {
    Value spec = lookup_v(inj.parent, Value(int64_t(2)));
    if (!admits(cval, spec, inj, store)) {
      inj.errs->push_back(
          Value(invalid_type_msg(inj.path, describe_alternatives({spec}), ctype, cval, "V0410")));
      return SKIP();
    }
  }

  if (0 == ((islen ? T_string | T_list | T_map : islike ? T_string : T_number) & ctype)) {
    std::string needtype = islen ? "string, list or map" : islike ? "string" : "number";
    inj.errs->push_back(Value(invalid_type_msg(inj.path, needtype, ctype, cval, "V0420")));
    return SKIP();
  }

  int64_t len = islen ? (cval.is_string() ? codepoints(cval.as_string()) : size(cval)) : 0;
  bool inbound = islen    ? lo <= len && (-1 == hi || len <= hi)
                 : islike ? re_test(like, cval.as_string())
                          : inrange(bound, cval);

  if (!inbound) {
    std::string needtype = std::string(inj.path.size() > 1 ? "" : "value ") + desc;
    inj.errs->push_back(Value(invalid_type_msg(inj.path, needtype, ctype, cval, "V0430")));
  }

  return SKIP();
}

// The value's length is within a bound: ['`$LEN`', bound, spec?], where the
// bound is as for a $NOF count. A string's length is in code points.
inline Value LEN_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  return validatebound(inj, store, "$LEN");
}

// The value is a number within a bound: ['`$RANGE`', bound, spec?], where the
// bound holds min or gt, max or lt, or one of each.
inline Value RANGE_FN(Injection& inj, const Value& val, const std::string& ref,
                      const Value& store) {
  return validatebound(inj, store, "$RANGE");
}

inline Value LIKE_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  return validatebound(inj, store, "$LIKE");
}

// Names a validate spec may use besides its checkers: transform's that it keeps, and $OPEN.
inline const std::vector<std::string>& VALIDATE_NAMES() {
  static const std::vector<std::string> names = {"$TOP",  "$SPEC", "$BT",     "$DS",    "$WHEN",
                                                 "$ANNO", "$REF",  "$FORMAT", "$APPLY", "$OPEN"};
  return names;
}

inline const std::regex& R_CHECKER_NAME() {
  static const std::regex r("^\\$[A-Z]+$");
  return r;
}

inline std::string upper(std::string s) {
  for (auto& c : s)
    c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
  return s;
}

// The name a whole-string reference gives, when it is a checker name in any
// case. Empty when there is none.
inline std::string refname(const Value& val) {
  if (!val.is_string())
    return "";
  std::smatch m;
  const std::string& s = val.as_string();
  if (!std::regex_match(s, m, R_INJECTION_FULL()))
    return "";
  std::string name = m[1].str();
  return std::regex_match(upper(name), R_CHECKER_NAME()) ? name : "";
}

inline bool knownname(const std::string& n, const Value& store) {
  const auto& names = VALIDATE_NAMES();
  if (std::find(names.begin(), names.end(), n) != names.end())
    return true;
  Value found = lookup_v(store, Value(n));
  return !found.is_undef() && !found.is_null();
}

// Unknown: undefined and upper case, or a defined name in another case. Null disables a name.
inline bool unknownname(const std::string& name, const Value& store) {
  std::string uname = upper(name);
  return !knownname(name, store) && (uname == name || knownname(uname, store));
}

// Report each checker the spec names that validate lacks; $EXACT's arguments are literals.
inline void checknames(const Value& spec, const Value& store, std::vector<std::string>& path,
                       std::vector<Value>& errs) {
  std::string name = refname(spec);
  if (!name.empty()) {
    if (unknownname(name, store))
      errs.push_back(
          Value("Unknown validator " + name + " at field " + pathify(pathlist(path)) + "."));
    return;
  }

  if (spec.is_list() && !spec.as_list()->empty() && "$EXACT" == refname((*spec.as_list())[0]))
    return;

  for (const auto& key : keysof(spec)) {
    if (spec.is_map())
      checknames(Value(key), store, path, errs);
    path.push_back(key);
    checknames(lookup_v(spec, Value(key)), store, path, errs);
    path.pop_back();
  }
}

} // namespace validators

// ===========================================================================
// _validation Modify
// ===========================================================================

inline void _validation(const Value& pval, const Value& key, const Value& parent, Injection& inj,
                        const Value& store) {
  if (is_skip(pval))
    return;
  bool exact = false;
  if (inj.meta) {
    Value* e = inj.meta->find(S_BEXACT());
    if (e && e->is_bool())
      exact = e->as_bool();
  }
  Value cval = getprop(inj.dparent, key);
  if (!exact && (cval.is_undef() || cval.is_null()))
    return;

  int ptype = typify(pval);
  if ((T_string & ptype) && pval.is_string() && pval.as_string().find('$') != std::string::npos) {
    return;
  }
  int ctype = typify(cval);
  if (ptype != ctype && !pval.is_undef()) {
    inj.errs->push_back(
        Value(invalid_type_msg(inj.path, typename_str(ptype), ctype, cval, "V0010")));
    return;
  }

  if (ismap(cval)) {
    if (!ismap(pval)) {
      inj.errs->push_back(
          Value(invalid_type_msg(inj.path, typename_str(ptype), ctype, cval, "V0020")));
      return;
    }
    auto ckeys = keysof(cval);
    auto pkeys = keysof(pval);
    Value open_v = getprop(pval, Value(S_BOPEN()));
    bool is_open = open_v.is_bool() && open_v.as_bool();
    if (!pkeys.empty() && !is_open) {
      std::vector<std::string> badkeys;
      for (auto& ck : ckeys) {
        // Canonical uses `NONE === _lookup(pval, ckey)`: the shape's literal
        // presence, so a key whose validator stored null still counts as
        // declared (Group A haskey would miss a null-valued slot).
        if (lookup_v(pval, Value(ck)).is_undef())
          badkeys.push_back(ck);
      }
      if (!badkeys.empty()) {
        auto pl = std::make_shared<List>();
        for (auto& p : inj.path)
          pl->push_back(Value(p));
        std::string joined;
        for (size_t i = 0; i < badkeys.size(); i++) {
          if (i > 0)
            joined += ", ";
          joined += badkeys[i];
        }
        inj.errs->push_back(
            Value("Unexpected keys at field " + pathify(Value(pl), 1, 0) + ": " + joined));
      }
    } else {
      auto args_l = std::make_shared<List>();
      args_l->push_back(pval);
      args_l->push_back(cval);
      merge_v(Value(args_l));
      if (isnode(pval))
        delprop(pval, Value(S_BOPEN()));
    }
  } else if (islist(cval)) {
    if (!islist(pval)) {
      inj.errs->push_back(
          Value(invalid_type_msg(inj.path, typename_str(ptype), ctype, cval, "V0030")));
    }
  } else if (exact) {
    if (cval != pval) {
      auto pl = std::make_shared<List>();
      for (auto& p : inj.path)
        pl->push_back(Value(p));
      std::string pathmsg =
          inj.path.size() > 1 ? "at field " + pathify(Value(pl), 1, 0) + ": " : "";
      inj.errs->push_back(
          Value("Value " + pathmsg + js_string(cval) + " should equal " + js_string(pval) + "."));
    }
  } else {
    setprop(parent, key, cval);
  }
}

inline Value _validatehandler(Injection& inj, const Value& val, const std::string& ref,
                              const Value& store) {
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
  Value errsRaw = options.is_map() ? getprop(options, Value("errs")) : Value::undef();
  Value metaRaw = options.is_map() ? getprop(options, Value("meta")) : Value::undef();

  bool collect = errsRaw.is_list();
  std::shared_ptr<std::vector<Value>> errs = std::make_shared<std::vector<Value>>();
  if (collect) {
    for (const auto& e : *errsRaw.as_list())
      errs->push_back(e);
  }

  auto baseStore = std::shared_ptr<Map>(new Map());
  baseStore->set("$DELETE", Value(nullptr));
  baseStore->set("$COPY", Value(nullptr));
  baseStore->set("$KEY", Value(nullptr));
  baseStore->set("$META", Value(nullptr));
  baseStore->set("$MERGE", Value(nullptr));
  baseStore->set("$EACH", Value(nullptr));
  baseStore->set("$PACK", Value(nullptr));

  baseStore->set("$STRING", Value(Injector(validators::STRING_FN)));
  baseStore->set("$NUMBER", Value(Injector(validators::TYPE_FN)));
  baseStore->set("$INTEGER", Value(Injector(validators::TYPE_FN)));
  baseStore->set("$DECIMAL", Value(Injector(validators::TYPE_FN)));
  baseStore->set("$BOOLEAN", Value(Injector(validators::TYPE_FN)));
  baseStore->set("$NULL", Value(Injector(validators::TYPE_FN)));
  baseStore->set("$NIL", Value(Injector(validators::TYPE_FN)));
  baseStore->set("$MAP", Value(Injector(validators::TYPE_FN)));
  baseStore->set("$LIST", Value(Injector(validators::TYPE_FN)));
  baseStore->set("$FUNCTION", Value(Injector(validators::TYPE_FN)));
  baseStore->set("$INSTANCE", Value(Injector(validators::TYPE_FN)));
  baseStore->set("$ANY", Value(Injector(validators::ANY_FN)));
  baseStore->set("$CHILD", Value(Injector(validators::CHILD_FN)));
  baseStore->set("$EXACT", Value(Injector(validators::EXACT_FN)));
  baseStore->set("$NOF", Value(Injector(validators::NOF_FN)));
  baseStore->set("$ALL", Value(Injector(validators::ALL_FN)));
  baseStore->set("$LEN", Value(Injector(validators::LEN_FN)));
  baseStore->set("$RANGE", Value(Injector(validators::RANGE_FN)));
  baseStore->set("$LIKE", Value(Injector(validators::LIKE_FN)));

  auto mergeList = std::make_shared<List>();
  mergeList->push_back(Value(baseStore));
  if (extraRaw.is_map())
    mergeList->push_back(extraRaw);
  auto errsListPtr = std::make_shared<List>();
  auto errsHolder = std::shared_ptr<Map>(new Map());
  errsHolder->set(S_DERRS(), Value(errsListPtr));
  mergeList->push_back(Value(errsHolder));
  Value store = merge_v(Value(mergeList), 1);

  std::shared_ptr<Map> meta;
  if (metaRaw.is_map()) {
    meta = std::shared_ptr<Map>(new Map());
    for (const auto& [k, v] : *metaRaw.as_map())
      meta->set(k, v);
  } else {
    meta = std::shared_ptr<Map>(new Map());
  }
  if (!meta->find(S_BEXACT()))
    meta->set(S_BEXACT(), Value(false));

  // A spec that names an unknown checker validates nothing.
  size_t numerrs = errs->size();
  std::vector<std::string> namepath;
  validators::checknames(spec, store, namepath, *errs);

  Value out;
  if (numerrs < errs->size()) {
    out = clone(data);
  } else {
    auto opts = std::shared_ptr<Map>(new Map());
    opts->set("meta", Value(meta));
    opts->set("extra", store);
    opts->set("modify", Value(Modify(_validation)));
    opts->set("handler", Value(Injector(_validatehandler)));
    auto opt_errs_list = std::make_shared<List>();
    for (const auto& e : *errs)
      opt_errs_list->push_back(e);
    opts->set("errs", Value(opt_errs_list));

    out = transform(data, spec, Value(opts));

    // Sync opt_errs_list back to errs.
    errs->clear();
    for (const auto& e : *opt_errs_list)
      errs->push_back(e);
  }

  if (!errs->empty() && !collect) {
    std::string msg;
    for (size_t i = 0; i < errs->size(); i++) {
      if (i > 0)
        msg += " | ";
      msg += stringify((*errs)[i]);
    }
    throw std::runtime_error(msg);
  }
  if (collect && errsRaw.is_list()) {
    auto rl = errsRaw.as_list();
    rl->clear();
    for (const auto& e : *errs)
      rl->push_back(e);
  }
  return out;
}

// ===========================================================================
// Select injectors + select()
// ===========================================================================

namespace selectors {

inline std::shared_ptr<Map> recOpts(const Value& store, const Value& point,
                                    std::shared_ptr<Map> meta, std::shared_ptr<List> errs_list) {
  auto vstore = std::shared_ptr<Map>(new Map());
  if (store.is_map()) {
    for (const auto& [k, v] : *store.as_map())
      vstore->set(k, v);
  }
  vstore->set(S_DTOP(), point);
  auto opts = std::shared_ptr<Map>(new Map());
  opts->set("errs", Value(errs_list));
  opts->set("meta", Value(meta));
  opts->set("extra", Value(vstore));
  return opts;
}

inline Value AND_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  if (inj.mode != M_KEYPRE)
    return Value::undef();
  Value terms = lookup_v(inj.parent, Value(inj.key));
  if (!terms.is_list())
    return Value::undef();

  auto ppath = std::make_shared<List>();
  for (size_t i = 0; i + 1 < inj.path.size(); i++)
    ppath->push_back(Value(inj.path[i]));
  Value point = getpath_v(store, Value(ppath));

  for (const auto& term : *terms.as_list()) {
    auto terrs = std::make_shared<List>();
    auto opts = recOpts(store, point, inj.meta, terrs);
    try {
      validate(point, term, Value(opts));
    } catch (const std::exception& e) {
      terrs->push_back(Value(std::string(e.what())));
    }
    if (!terrs->empty()) {
      inj.errs->push_back(Value("AND:" + pathify(Value(ppath)) + ": " + stringify(point) +
                                " fail:" + stringify(terms)));
    }
  }
  Value gkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
  Value gp;
  if (inj.nodes && inj.nodes->size() >= 2)
    gp = (*inj.nodes)[inj.nodes->size() - 2];
  setprop(gp, gkey, point);
  return Value::undef();
}

inline Value OR_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  if (inj.mode != M_KEYPRE)
    return Value::undef();
  Value terms = lookup_v(inj.parent, Value(inj.key));
  if (!terms.is_list())
    return Value::undef();

  auto ppath = std::make_shared<List>();
  for (size_t i = 0; i + 1 < inj.path.size(); i++)
    ppath->push_back(Value(inj.path[i]));
  Value point = getpath_v(store, Value(ppath));

  for (const auto& term : *terms.as_list()) {
    auto terrs = std::make_shared<List>();
    auto opts = recOpts(store, point, inj.meta, terrs);
    try {
      validate(point, term, Value(opts));
    } catch (const std::exception& e) {
      terrs->push_back(Value(std::string(e.what())));
    }
    if (terrs->empty()) {
      Value gkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
      Value gp;
      if (inj.nodes && inj.nodes->size() >= 2)
        gp = (*inj.nodes)[inj.nodes->size() - 2];
      setprop(gp, gkey, point);
      return Value::undef();
    }
  }
  inj.errs->push_back(
      Value("OR:" + pathify(Value(ppath)) + ": " + stringify(point) + " fail:" + stringify(terms)));
  return Value::undef();
}

inline Value NOT_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  if (inj.mode != M_KEYPRE)
    return Value::undef();
  Value term = lookup_v(inj.parent, Value(inj.key));
  auto ppath = std::make_shared<List>();
  for (size_t i = 0; i + 1 < inj.path.size(); i++)
    ppath->push_back(Value(inj.path[i]));
  Value point = getpath_v(store, Value(ppath));
  auto terrs = std::make_shared<List>();
  auto opts = recOpts(store, point, inj.meta, terrs);
  try {
    validate(point, term, Value(opts));
  } catch (const std::exception& e) {
    terrs->push_back(Value(std::string(e.what())));
  }
  if (terrs->empty()) {
    inj.errs->push_back(Value("NOT:" + pathify(Value(ppath)) + ": " + stringify(point) +
                              " fail:" + stringify(term)));
  }
  Value gkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
  Value gp;
  if (inj.nodes && inj.nodes->size() >= 2)
    gp = (*inj.nodes)[inj.nodes->size() - 2];
  setprop(gp, gkey, point);
  return Value::undef();
}

inline Value CMP_FN(Injection& inj, const Value& val, const std::string& ref, const Value& store) {
  // The list form of $LIKE is validate's checker; the key form is this operator.
  if (M_VAL == inj.mode && "$LIKE" == ref)
    return validators::LIKE_FN(inj, val, ref, store);

  if (inj.mode != M_KEYPRE)
    return Value::undef();
  Value term = lookup_v(inj.parent, Value(inj.key));
  Value gkey = inj.path.size() >= 2 ? Value(inj.path[inj.path.size() - 2]) : Value::undef();
  auto ppath = std::make_shared<List>();
  for (size_t i = 0; i + 1 < inj.path.size(); i++)
    ppath->push_back(Value(inj.path[i]));
  Value point = getpath_v(store, Value(ppath));
  bool pass = false;
  if (point.is_number() && term.is_number()) {
    double a = point.as_double();
    double b = term.as_double();
    if (ref == "$GT")
      pass = a > b;
    else if (ref == "$LT")
      pass = a < b;
    else if (ref == "$GTE")
      pass = a >= b;
    else if (ref == "$LTE")
      pass = a <= b;
  } else if (ref == "$LIKE" && term.is_string()) {
    try {
      std::regex pat(term.as_string());
      pass = std::regex_search(stringify(point), pat);
    } catch (...) {
      pass = false;
    }
  }
  if (pass) {
    Value gp;
    if (inj.nodes && inj.nodes->size() >= 2)
      gp = (*inj.nodes)[inj.nodes->size() - 2];
    setprop(gp, gkey, point);
  } else {
    inj.errs->push_back(Value("CMP: " + pathify(Value(ppath)) + ": " + stringify(point) +
                              " fail:" + ref + " " + stringify(term)));
  }
  return Value::undef();
}

// Open every map in a select query, so a child may hold keys the query does
// not name, but leave a directive's literals as written: what $EXACT
// compares, and the count or bound of $NOF, $LEN and $RANGE.
inline void openquery(const Value& q) {
  if (ismap(q)) {
    Value cur = getprop(q, Value(S_BOPEN()));
    setprop(q, Value(S_BOPEN()), cur.is_undef() ? Value(true) : cur);
    for (const auto& entry : *q.as_map())
      openquery(entry.second);
  } else if (islist(q)) {
    auto l = q.as_list();
    std::string head = !l->empty() && (*l)[0].is_string() ? (*l)[0].as_string() : "";
    bool exact = S_BEXACT() == head;
    bool bounded = "`$NOF`" == head || "`$LEN`" == head || "`$RANGE`" == head;
    for (size_t i = 0; i < l->size(); i++) {
      if (0 == i || !(exact || (bounded && 1 == i)))
        openquery((*l)[i]);
    }
  }
}

} // namespace selectors

inline std::vector<Value> select(const Value& children, const Value& query) {
  if (!isnode(children))
    return {};

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
  extra->set("$OR", Value(Injector(selectors::OR_FN)));
  extra->set("$NOT", Value(Injector(selectors::NOT_FN)));
  extra->set("$GT", Value(Injector(selectors::CMP_FN)));
  extra->set("$LT", Value(Injector(selectors::CMP_FN)));
  extra->set("$GTE", Value(Injector(selectors::CMP_FN)));
  extra->set("$LTE", Value(Injector(selectors::CMP_FN)));
  extra->set("$LIKE", Value(Injector(selectors::CMP_FN)));

  Value q = clone(query);

  selectors::openquery(q);

  std::vector<Value> results;
  for (const auto& child : childList) {
    auto errs_list = std::make_shared<List>();
    auto opts = std::shared_ptr<Map>(new Map());
    opts->set("errs", Value(errs_list));
    opts->set("meta", Value(meta));
    opts->set("extra", Value(extra));
    try {
      validate(child, clone(q), Value(opts));
    } catch (const std::exception& e) {
      errs_list->push_back(Value(std::string(e.what())));
    }
    if (errs_list->empty())
      results.push_back(child);
  }
  return results;
}

} // namespace structlib
} // namespace voxgig

#endif // VOXGIG_STRUCT_HPP
