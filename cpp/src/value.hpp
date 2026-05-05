// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
//
// Voxgig Struct — Value type
//
// In-memory JSON-shaped data plus the small set of language-runtime extras
// the canonical TypeScript port needs: callable values (Injector/Modify),
// sentinel markers (SKIP/DELETE), and an explicit "undefined" distinct from
// JSON null.
//
// Design summary (see cpp/REFACTOR_PLAN.md for rationale):
//   - std::variant for tagged-union storage with compile-time exhaustiveness.
//   - shared_ptr<List>/shared_ptr<Map> so list/map mutation propagates to all
//     Value copies that reference the same container (TS reference-stability).
//   - Custom OrderedMap (vector + index) so map keys preserve insertion order.
//     Required by the inject machinery's $-suffix key partition.
//   - std::monostate for undefined; std::nullptr_t for JSON null. Distinct.
//   - const Sentinel* for SKIP/DELETE so == identity survives clone().
//
// This header is intentionally self-contained: it does not include nlohmann
// or any other JSON parser. JSON I/O lives in value_io.hpp.

#ifndef VOXGIG_STRUCT_VALUE_HPP
#define VOXGIG_STRUCT_VALUE_HPP

#include <cmath>
#include <cstdint>
#include <functional>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <variant>
#include <vector>

namespace voxgig {
namespace structlib {

// Forward declarations.
class Value;
class Injection;
class OrderedMap;

using List = std::vector<Value>;
using Map = OrderedMap;

// Injector: invoked for each `$NAME` reference (transform_*, validate_*,
// select_*). Mirrors TS `Injector`.
using Injector = std::function<Value(
    Injection& inj,
    const Value& val,
    const std::string& ref,
    const Value& store)>;

// Modify: optional value-mutation hook used by inject/transform/validate.
// Mirrors TS `Modify`.
using Modify = std::function<void(
    const Value& val,
    const Value& key,
    const Value& parent,
    Injection& inj,
    const Value& store)>;

// Sentinel: tagged marker compared by pointer identity. Two static instances
// (SKIP / DELETE) are exposed below.
struct Sentinel {
  const char* name;  // "SKIP" or "DELETE"
};

// Type bit-flags. Mirrors TS lines 110–127.
constexpr int T_any      = static_cast<int>((1u << 31) - 1);
constexpr int T_noval    = 1 << 30;  // undefined / absent
constexpr int T_boolean  = 1 << 29;
constexpr int T_decimal  = 1 << 28;
constexpr int T_integer  = 1 << 27;
constexpr int T_number   = 1 << 26;
constexpr int T_string   = 1 << 25;
constexpr int T_function = 1 << 24;
constexpr int T_symbol   = 1 << 23;
constexpr int T_null     = 1 << 22;
constexpr int T_list     = 1 << 14;
constexpr int T_map      = 1 << 13;
constexpr int T_instance = 1 << 12;
constexpr int T_scalar   = 1 << 7;
constexpr int T_node     = 1 << 6;

// Index → name for typify→typename. Order must match TS TYPENAME table.
inline const std::string& typename_table(int idx) {
  static const std::string TABLE[26] = {
      "any", "nil", "boolean", "decimal", "integer", "number", "string",
      "function", "symbol", "null",
      "", "", "",
      "", "", "", "",
      "list", "map", "instance",
      "", "", "", "",
      "scalar", "node",
  };
  static const std::string EMPTY = "";
  if (idx < 0 || idx >= 26) return EMPTY;
  return TABLE[idx];
}

// Inject mode bitfield.
constexpr int M_KEYPRE  = 1;
constexpr int M_KEYPOST = 2;
constexpr int M_VAL     = 4;

constexpr int MAXDEPTH = 32;

// ===========================================================================
// Value
// ===========================================================================

class Value {
 public:
  using Storage = std::variant<
      std::monostate,             // 0  - undefined / T_noval
      std::nullptr_t,             // 1  - JSON null
      bool,                       // 2  - boolean
      int64_t,                    // 3  - integer
      double,                     // 4  - decimal
      std::string,                // 5  - string
      std::shared_ptr<List>,      // 6  - list (reference-stable)
      std::shared_ptr<Map>,       // 7  - map  (reference-stable)
      Injector,                   // 8  - $-command handler
      Modify,                     // 9  - modify hook
      const Sentinel*             // 10 - SKIP / DELETE marker
      >;

  Storage storage;

  // ---- Constructors ----
  Value() : storage(std::monostate{}) {}
  Value(std::nullptr_t) : storage(nullptr) {}
  Value(bool b) : storage(b) {}
  Value(int v) : storage(static_cast<int64_t>(v)) {}
  Value(long v) : storage(static_cast<int64_t>(v)) {}
  Value(long long v) : storage(static_cast<int64_t>(v)) {}
  Value(unsigned v) : storage(static_cast<int64_t>(v)) {}
  Value(unsigned long v) : storage(static_cast<int64_t>(v)) {}
  Value(double v) : storage(v) {}
  Value(float v) : storage(static_cast<double>(v)) {}
  Value(const char* s) : storage(std::string(s)) {}
  Value(std::string s) : storage(std::move(s)) {}
  Value(std::shared_ptr<List> l) : storage(std::move(l)) {}
  Value(std::shared_ptr<Map> m) : storage(std::move(m)) {}
  Value(Injector f) : storage(std::move(f)) {}
  Value(Modify f) : storage(std::move(f)) {}
  Value(const Sentinel* s) : storage(s) {}

  // ---- Factory helpers ----
  static Value undef() { return Value(); }
  static Value list() { return Value(std::make_shared<List>()); }
  static Value list(std::initializer_list<Value> il) {
    auto p = std::make_shared<List>(il.begin(), il.end());
    return Value(std::move(p));
  }
  // Defined after OrderedMap is complete (below).
  static Value map();

  // ---- Type predicates ----
  bool is_undef() const { return std::holds_alternative<std::monostate>(storage); }
  bool is_null() const  { return std::holds_alternative<std::nullptr_t>(storage); }
  bool is_bool() const  { return std::holds_alternative<bool>(storage); }
  bool is_int() const   { return std::holds_alternative<int64_t>(storage); }
  bool is_double() const{ return std::holds_alternative<double>(storage); }
  bool is_number() const{ return is_int() || is_double(); }
  bool is_string() const{ return std::holds_alternative<std::string>(storage); }
  bool is_list() const  { return std::holds_alternative<std::shared_ptr<List>>(storage); }
  bool is_map() const   { return std::holds_alternative<std::shared_ptr<Map>>(storage); }
  bool is_node() const  { return is_list() || is_map(); }
  bool is_injector() const { return std::holds_alternative<Injector>(storage); }
  bool is_modify() const   { return std::holds_alternative<Modify>(storage); }
  bool is_func() const  { return is_injector() || is_modify(); }
  bool is_sentinel() const { return std::holds_alternative<const Sentinel*>(storage); }

  // ---- Accessors (assume the variant alternative is correct) ----
  bool as_bool() const { return std::get<bool>(storage); }
  int64_t as_int() const {
    if (is_int()) return std::get<int64_t>(storage);
    if (is_double()) return static_cast<int64_t>(std::get<double>(storage));
    return 0;
  }
  double as_double() const {
    if (is_double()) return std::get<double>(storage);
    if (is_int()) return static_cast<double>(std::get<int64_t>(storage));
    return 0.0;
  }
  const std::string& as_string() const { return std::get<std::string>(storage); }
  std::shared_ptr<List> as_list() const { return std::get<std::shared_ptr<List>>(storage); }
  std::shared_ptr<Map> as_map() const { return std::get<std::shared_ptr<Map>>(storage); }
  const Injector& as_injector() const { return std::get<Injector>(storage); }
  const Modify& as_modify() const { return std::get<Modify>(storage); }
  const Sentinel* as_sentinel() const { return std::get<const Sentinel*>(storage); }

  // ---- Identity-aware equality ----
  // For the sentinel alternative, compares by pointer identity (which is the
  // whole point of having sentinels). Other alternatives use value equality.
  // Lists / maps compare by structure (deep), not pointer.
  friend bool operator==(const Value& a, const Value& b);
  friend bool operator!=(const Value& a, const Value& b) { return !(a == b); }
};

// ===========================================================================
// Sentinel singletons
// ===========================================================================

inline const Sentinel& skip_inst() {
  static const Sentinel S{"SKIP"};
  return S;
}
inline const Sentinel& delete_inst() {
  static const Sentinel S{"DELETE"};
  return S;
}

inline Value SKIP() { return Value(&skip_inst()); }
inline Value DELETE_V() { return Value(&delete_inst()); }

inline bool is_skip(const Value& v) {
  return v.is_sentinel() && v.as_sentinel() == &skip_inst();
}
inline bool is_delete(const Value& v) {
  return v.is_sentinel() && v.as_sentinel() == &delete_inst();
}

// ===========================================================================
// OrderedMap
// ===========================================================================
//
// Insertion-ordered map. The TS canonical relies on object insertion order
// for the inject $-suffix-key partition (non-$ keys before $ keys), so the
// runtime map type must preserve insertion order regardless of platform
// hash randomisation.

class OrderedMap {
 public:
  using Entry = std::pair<std::string, Value>;
  using Entries = std::vector<Entry>;

  OrderedMap() = default;
  OrderedMap(const OrderedMap&) = default;
  OrderedMap(OrderedMap&&) = default;
  OrderedMap& operator=(const OrderedMap&) = default;
  OrderedMap& operator=(OrderedMap&&) = default;

  size_t size() const { return entries_.size(); }
  bool empty() const { return entries_.empty(); }

  bool contains(const std::string& key) const {
    return index_.find(key) != index_.end();
  }

  Value* find(const std::string& key) {
    auto it = index_.find(key);
    if (it == index_.end()) return nullptr;
    return &entries_[it->second].second;
  }
  const Value* find(const std::string& key) const {
    auto it = index_.find(key);
    if (it == index_.end()) return nullptr;
    return &entries_[it->second].second;
  }

  Value& operator[](const std::string& key) {
    auto it = index_.find(key);
    if (it != index_.end()) return entries_[it->second].second;
    index_.emplace(key, entries_.size());
    entries_.emplace_back(key, Value());
    return entries_.back().second;
  }

  void set(const std::string& key, Value v) {
    auto it = index_.find(key);
    if (it == index_.end()) {
      index_.emplace(key, entries_.size());
      entries_.emplace_back(key, std::move(v));
    } else {
      entries_[it->second].second = std::move(v);
    }
  }

  bool erase(const std::string& key) {
    auto it = index_.find(key);
    if (it == index_.end()) return false;
    size_t idx = it->second;
    entries_.erase(entries_.begin() + idx);
    rebuild_index_();
    return true;
  }

  void clear() {
    entries_.clear();
    index_.clear();
  }

  // Iteration is over the insertion-ordered entries.
  Entries::iterator begin() { return entries_.begin(); }
  Entries::iterator end()   { return entries_.end(); }
  Entries::const_iterator begin() const { return entries_.begin(); }
  Entries::const_iterator end()   const { return entries_.end(); }

  const Entries& entries() const { return entries_; }
  Entries& entries() { return entries_; }

  bool operator==(const OrderedMap& other) const {
    if (entries_.size() != other.entries_.size()) return false;
    // Order-sensitive equality. For test comparison we usually want
    // order-insensitive, but Value::operator== on shared_ptr<Map> calls this;
    // the test runner uses its own normalising deep_equal.
    for (size_t i = 0; i < entries_.size(); i++) {
      if (entries_[i].first != other.entries_[i].first) return false;
      if (entries_[i].second != other.entries_[i].second) return false;
    }
    return true;
  }
  bool operator!=(const OrderedMap& other) const { return !(*this == other); }

 private:
  Entries entries_;
  std::unordered_map<std::string, size_t> index_;

  void rebuild_index_() {
    index_.clear();
    index_.reserve(entries_.size());
    for (size_t i = 0; i < entries_.size(); i++) {
      index_.emplace(entries_[i].first, i);
    }
  }
};

// ===========================================================================
// Value::map factory (after OrderedMap is defined)
// ===========================================================================

inline Value Value::map() {
  return Value(std::shared_ptr<Map>(new Map()));
}

// ===========================================================================
// Equality (after OrderedMap is defined)
// ===========================================================================

inline bool operator==(const Value& a, const Value& b) {
  // Sentinel alternative: pointer identity only.
  if (a.is_sentinel() || b.is_sentinel()) {
    return a.is_sentinel() && b.is_sentinel()
        && a.as_sentinel() == b.as_sentinel();
  }
  // Number cross-type equality: integer-valued double == int.
  if (a.is_number() && b.is_number()) {
    if (a.is_int() && b.is_int()) {
      return a.as_int() == b.as_int();
    }
    return a.as_double() == b.as_double();
  }
  if (a.storage.index() != b.storage.index()) {
    return false;
  }
  // Lists / maps compare structurally (operator== on shared_ptr<...> Storage
  // alternative calls .equals on the contained list/map via std::variant's
  // generated operator==, which dereferences the shared_ptr).
  if (a.is_list()) {
    auto la = a.as_list();
    auto lb = b.as_list();
    if (la == lb) return true;  // same shared instance
    if (!la || !lb) return false;
    if (la->size() != lb->size()) return false;
    for (size_t i = 0; i < la->size(); i++) {
      if ((*la)[i] != (*lb)[i]) return false;
    }
    return true;
  }
  if (a.is_map()) {
    auto ma = a.as_map();
    auto mb = b.as_map();
    if (ma == mb) return true;
    if (!ma || !mb) return false;
    return *ma == *mb;
  }
  // Function alternatives: not meaningfully comparable; return false unless
  // both refer to the same target (std::function provides target_type).
  if (a.is_injector() || a.is_modify()) {
    return false;
  }
  // Scalars: variant value-equality.
  return a.storage == b.storage;
}

// ===========================================================================
// typify / typename
// ===========================================================================

inline int typify(const Value& v) {
  if (v.is_undef())    return T_noval;
  if (v.is_null())     return T_scalar | T_null;
  if (v.is_bool())     return T_scalar | T_boolean;
  if (v.is_int())      return T_scalar | T_number | T_integer;
  if (v.is_double()) {
    double d = v.as_double();
    if (std::isnan(d)) return T_noval;
    return T_scalar | T_number | T_decimal;
  }
  if (v.is_string())   return T_scalar | T_string;
  if (v.is_list())     return T_node | T_list;
  if (v.is_map())      return T_node | T_map;
  if (v.is_func())     return T_scalar | T_function;
  if (v.is_sentinel()) return T_node | T_map;  // SKIP/DELETE behave as maps
  return T_any;
}

// Highest set bit wins (smallest leading-zero count). Mirrors TS typename.
inline std::string typename_str(int t) {
  if (t == 0) return "any";
  // Equivalent to Math.clz32(t) on a 32-bit unsigned.
  uint32_t u = static_cast<uint32_t>(t);
  int idx = 0;
  while (idx < 32 && (u & (1u << (31 - idx))) == 0) idx++;
  if (idx >= 26) return "any";
  const std::string& s = typename_table(idx);
  return s.empty() ? "any" : s;
}

inline std::string typename_str(const Value& v) {
  return typename_str(typify(v));
}

// ===========================================================================
// Deep clone
// ===========================================================================
//
// Reference-stable mutation means a plain copy of `Value` shares its
// underlying List/Map. clone() forks them so the copy can be mutated
// independently. Sentinels short-circuit so identity survives.

inline Value clone(const Value& v);

inline std::shared_ptr<List> clone_list(const std::shared_ptr<List>& src) {
  if (!src) return nullptr;
  auto out = std::make_shared<List>();
  out->reserve(src->size());
  for (const auto& e : *src) out->push_back(clone(e));
  return out;
}

inline std::shared_ptr<Map> clone_map(const std::shared_ptr<Map>& src) {
  if (!src) return nullptr;
  auto out = std::shared_ptr<Map>(new Map());
  for (const auto& [k, v] : *src) out->set(k, clone(v));
  return out;
}

inline Value clone(const Value& v) {
  if (v.is_sentinel()) return v;          // preserve identity
  if (v.is_list())     return Value(clone_list(v.as_list()));
  if (v.is_map())      return Value(clone_map(v.as_map()));
  // Scalars / undefined / null / function: copy variant alternative.
  return v;
}

// ===========================================================================
// size / length helper
// ===========================================================================

inline int64_t size_of(const Value& v) {
  if (v.is_list())   return static_cast<int64_t>(v.as_list()->size());
  if (v.is_map())    return static_cast<int64_t>(v.as_map()->size());
  if (v.is_string()) return static_cast<int64_t>(v.as_string().size());
  if (v.is_int())    return static_cast<int64_t>(std::floor(static_cast<double>(v.as_int())));
  if (v.is_double()) return static_cast<int64_t>(std::floor(v.as_double()));
  if (v.is_bool())   return v.as_bool() ? 1 : 0;
  return 0;
}

}  // namespace structlib
}  // namespace voxgig

#endif  // VOXGIG_STRUCT_VALUE_HPP
