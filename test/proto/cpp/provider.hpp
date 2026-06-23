// Test Provider (prototype) — C++17 port.
//
// Reads the shared corpus (build/test/test.json) and hands test code clean,
// normalized cases. It is NOT a test runner: it never calls the subject and
// never asserts. See ../PROVIDER.md for the model and ../ts/provider.ts for
// the canonical reference this is ported from.
//
// Self-contained and dependency-free: includes its own minimal JSON parser and
// does NOT depend on the cpp port's value.hpp. Standard library only.

#ifndef VOXGIG_TEST_PROVIDER_HPP
#define VOXGIG_TEST_PROVIDER_HPP

#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <memory>
#include <optional>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace voxgig {
namespace testproto {

// ─── JSON value type ───────────────────────────────────────────────────────
// Order-preserving object: vector<pair<string,Value>> (NOT std::map) so that
// functions()/groups() keep corpus order.

class Value;
using Array = std::vector<Value>;
using Object = std::vector<std::pair<std::string, Value>>;

enum class Type { Null, Bool, Number, String, Array, Object };

class Value {
 public:
  Type type = Type::Null;
  bool b = false;
  double num = 0.0;
  std::string str;
  std::shared_ptr<Array> arr;
  std::shared_ptr<Object> obj;

  Value() : type(Type::Null) {}
  static Value null() { return Value(); }
  static Value boolean(bool v) {
    Value x;
    x.type = Type::Bool;
    x.b = v;
    return x;
  }
  static Value number(double v) {
    Value x;
    x.type = Type::Number;
    x.num = v;
    return x;
  }
  static Value string(std::string v) {
    Value x;
    x.type = Type::String;
    x.str = std::move(v);
    return x;
  }
  static Value array() {
    Value x;
    x.type = Type::Array;
    x.arr = std::make_shared<Array>();
    return x;
  }
  static Value object() {
    Value x;
    x.type = Type::Object;
    x.obj = std::make_shared<Object>();
    return x;
  }

  bool is_null() const { return type == Type::Null; }
  bool is_bool() const { return type == Type::Bool; }
  bool is_number() const { return type == Type::Number; }
  bool is_string() const { return type == Type::String; }
  bool is_array() const { return type == Type::Array; }
  bool is_object() const { return type == Type::Object; }

  // Object helpers (order-preserving).
  bool has(const std::string& key) const {
    if (!is_object()) return false;
    for (const auto& kv : *obj)
      if (kv.first == key) return true;
    return false;
  }
  // Returns nullptr if absent.
  const Value* find(const std::string& key) const {
    if (!is_object()) return nullptr;
    for (const auto& kv : *obj)
      if (kv.first == key) return &kv.second;
    return nullptr;
  }
  void set(const std::string& key, Value v) {
    if (!is_object()) {
      type = Type::Object;
      obj = std::make_shared<Object>();
    }
    for (auto& kv : *obj) {
      if (kv.first == key) {
        kv.second = std::move(v);
        return;
      }
    }
    obj->emplace_back(key, std::move(v));
  }
  void push(Value v) {
    if (!is_array()) {
      type = Type::Array;
      arr = std::make_shared<Array>();
    }
    arr->push_back(std::move(v));
  }
};

// ─── compact JSON serialization ────────────────────────────────────────────

inline void jsonEscape(const std::string& s, std::string& out) {
  out.push_back('"');
  for (unsigned char c : s) {
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
        if (c < 0x20) {
          static const char* hex = "0123456789abcdef";
          out += "\\u00";
          out.push_back(hex[(c >> 4) & 0xF]);
          out.push_back(hex[c & 0xF]);
        } else {
          out.push_back(static_cast<char>(c));
        }
    }
  }
  out.push_back('"');
}

inline std::string numToString(double d) {
  // Integer-valued doubles render without a decimal point (matches JSON.stringify
  // for whole numbers), else a round-trippable representation.
  if (d == static_cast<int64_t>(d) && d >= -9.007199254740992e15 &&
      d <= 9.007199254740992e15) {
    std::ostringstream oss;
    oss << static_cast<int64_t>(d);
    return oss.str();
  }
  std::ostringstream oss;
  oss.precision(17);
  oss << d;
  return oss.str();
}

inline void jsonify(const Value& v, std::string& out) {
  switch (v.type) {
    case Type::Null:
      out += "null";
      break;
    case Type::Bool:
      out += v.b ? "true" : "false";
      break;
    case Type::Number:
      out += numToString(v.num);
      break;
    case Type::String:
      jsonEscape(v.str, out);
      break;
    case Type::Array: {
      out.push_back('[');
      bool first = true;
      for (const auto& e : *v.arr) {
        if (!first) out.push_back(',');
        first = false;
        jsonify(e, out);
      }
      out.push_back(']');
      break;
    }
    case Type::Object: {
      out.push_back('{');
      bool first = true;
      for (const auto& kv : *v.obj) {
        if (!first) out.push_back(',');
        first = false;
        jsonEscape(kv.first, out);
        out.push_back(':');
        jsonify(kv.second, out);
      }
      out.push_back('}');
      break;
    }
  }
}

inline std::string jsonify(const Value& v) {
  std::string out;
  jsonify(v, out);
  return out;
}

// ─── recursive-descent JSON parser ─────────────────────────────────────────

class JsonParser {
 public:
  explicit JsonParser(const std::string& s) : s_(s), n_(s.size()) {}

  Value parse() {
    skipWs();
    Value v = parseValue();
    skipWs();
    if (i_ != n_) fail("trailing characters");
    return v;
  }

 private:
  const std::string& s_;
  size_t i_ = 0;
  size_t n_;

  [[noreturn]] void fail(const std::string& msg) {
    std::ostringstream oss;
    oss << "JSON parse error at offset " << i_ << ": " << msg;
    throw std::runtime_error(oss.str());
  }

  char peek() { return i_ < n_ ? s_[i_] : '\0'; }
  char get() { return i_ < n_ ? s_[i_++] : '\0'; }

  void skipWs() {
    while (i_ < n_) {
      char c = s_[i_];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
        i_++;
      else
        break;
    }
  }

  Value parseValue() {
    skipWs();
    char c = peek();
    switch (c) {
      case '{':
        return parseObject();
      case '[':
        return parseArray();
      case '"':
        return Value::string(parseString());
      case 't':
      case 'f':
        return parseBool();
      case 'n':
        return parseNull();
      default:
        if (c == '-' || (c >= '0' && c <= '9')) return parseNumber();
        fail("unexpected character");
    }
  }

  Value parseObject() {
    get();  // {
    Value v = Value::object();
    skipWs();
    if (peek() == '}') {
      get();
      return v;
    }
    while (true) {
      skipWs();
      if (peek() != '"') fail("expected string key");
      std::string key = parseString();
      skipWs();
      if (get() != ':') fail("expected ':'");
      Value val = parseValue();
      v.obj->emplace_back(std::move(key), std::move(val));
      skipWs();
      char c = get();
      if (c == ',') continue;
      if (c == '}') break;
      fail("expected ',' or '}'");
    }
    return v;
  }

  Value parseArray() {
    get();  // [
    Value v = Value::array();
    skipWs();
    if (peek() == ']') {
      get();
      return v;
    }
    while (true) {
      Value el = parseValue();
      v.arr->push_back(std::move(el));
      skipWs();
      char c = get();
      if (c == ',') continue;
      if (c == ']') break;
      fail("expected ',' or ']'");
    }
    return v;
  }

  void appendUtf8(uint32_t cp, std::string& out) {
    if (cp <= 0x7F) {
      out.push_back(static_cast<char>(cp));
    } else if (cp <= 0x7FF) {
      out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp <= 0xFFFF) {
      out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
      out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else {
      out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
      out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
  }

  uint32_t parseHex4() {
    uint32_t v = 0;
    for (int k = 0; k < 4; k++) {
      char c = get();
      v <<= 4;
      if (c >= '0' && c <= '9')
        v |= static_cast<uint32_t>(c - '0');
      else if (c >= 'a' && c <= 'f')
        v |= static_cast<uint32_t>(c - 'a' + 10);
      else if (c >= 'A' && c <= 'F')
        v |= static_cast<uint32_t>(c - 'A' + 10);
      else
        fail("invalid \\u escape");
    }
    return v;
  }

  std::string parseString() {
    get();  // opening "
    std::string out;
    while (true) {
      if (i_ >= n_) fail("unterminated string");
      char c = get();
      if (c == '"') break;
      if (c == '\\') {
        char e = get();
        switch (e) {
          case '"':
            out.push_back('"');
            break;
          case '\\':
            out.push_back('\\');
            break;
          case '/':
            out.push_back('/');
            break;
          case 'b':
            out.push_back('\b');
            break;
          case 'f':
            out.push_back('\f');
            break;
          case 'n':
            out.push_back('\n');
            break;
          case 'r':
            out.push_back('\r');
            break;
          case 't':
            out.push_back('\t');
            break;
          case 'u': {
            uint32_t cp = parseHex4();
            if (cp >= 0xD800 && cp <= 0xDBFF) {
              // high surrogate; expect a low surrogate next
              if (peek() == '\\') {
                get();
                if (get() != 'u') fail("expected low surrogate");
                uint32_t lo = parseHex4();
                if (lo >= 0xDC00 && lo <= 0xDFFF) {
                  cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                } else {
                  // unpaired; emit both as-is
                  appendUtf8(cp, out);
                  cp = lo;
                }
              }
            }
            appendUtf8(cp, out);
            break;
          }
          default:
            fail("invalid escape");
        }
      } else {
        out.push_back(c);
      }
    }
    return out;
  }

  Value parseNumber() {
    size_t start = i_;
    if (peek() == '-') get();
    while (i_ < n_ && s_[i_] >= '0' && s_[i_] <= '9') i_++;
    if (peek() == '.') {
      get();
      while (i_ < n_ && s_[i_] >= '0' && s_[i_] <= '9') i_++;
    }
    if (peek() == 'e' || peek() == 'E') {
      get();
      if (peek() == '+' || peek() == '-') get();
      while (i_ < n_ && s_[i_] >= '0' && s_[i_] <= '9') i_++;
    }
    std::string tok = s_.substr(start, i_ - start);
    return Value::number(std::stod(tok));
  }

  Value parseBool() {
    if (s_.compare(i_, 4, "true") == 0) {
      i_ += 4;
      return Value::boolean(true);
    }
    if (s_.compare(i_, 5, "false") == 0) {
      i_ += 5;
      return Value::boolean(false);
    }
    fail("invalid literal");
  }

  Value parseNull() {
    if (s_.compare(i_, 4, "null") == 0) {
      i_ += 4;
      return Value::null();
    }
    fail("invalid literal");
  }
};

inline Value parseJson(const std::string& text) {
  JsonParser p(text);
  return p.parse();
}

// ─── normalized model ──────────────────────────────────────────────────────

enum class InputKind { IN, ARGS, CTX };
enum class ExpectKind { VALUE, ERROR, MATCH, ABSENT };

struct Input {
  InputKind kind = InputKind::IN;
  Value in;    // kind==IN
  Value args;  // kind==ARGS
  Value ctx;   // kind==CTX
};

struct ErrorCheck {
  bool any = false;
  std::optional<std::string> text;
  bool regex = false;
};

struct Expect {
  ExpectKind kind = ExpectKind::ABSENT;
  std::optional<Value> value;
  std::optional<ErrorCheck> error;
  std::optional<Value> match;
};

struct Entry {
  std::string function;
  std::string group;
  size_t index = 0;
  std::optional<std::string> id;
  bool doc = false;
  std::optional<std::string> client;
  Input input;
  Expect expect;
  Value raw;
};

struct MatchResult {
  bool ok = true;
  std::vector<std::string> path;
  std::optional<Value> expected;
  std::optional<Value> actual;
};

// ─── markers ───────────────────────────────────────────────────────────────

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

// ─── group / function detection ────────────────────────────────────────────

// A group bag is a map with a `set` array.
inline bool isGroupBag(const Value& v) {
  if (!v.is_object()) return false;
  const Value* set = v.find("set");
  return set != nullptr && set->is_array();
}

// A function node has at least one child group bag (excluding "name").
inline bool hasGroups(const Value& v) {
  if (!v.is_object()) return false;
  for (const auto& kv : *v.obj) {
    if (kv.first != "name" && isGroupBag(kv.second)) return true;
  }
  return false;
}

// ─── stringify (for match helpers) ─────────────────────────────────────────

inline std::string stringify(const Value& x) {
  if (x.is_string()) return x.str;
  return jsonify(x);
}

// ─── null normalization (equal / equalStrict) ──────────────────────────────

// normNull: __NULL__ -> null and recurse. (Absent maps to null at the source;
// here all explicit values are present, so we only collapse the marker.)
inline Value normNull(const Value& x) {
  if (x.is_string() && x.str == NULLMARK()) return Value::null();
  if (x.is_array()) {
    Value out = Value::array();
    for (const auto& e : *x.arr) out.arr->push_back(normNull(e));
    return out;
  }
  if (x.is_object()) {
    Value out = Value::object();
    for (const auto& kv : *x.obj) out.obj->emplace_back(kv.first, normNull(kv.second));
    return out;
  }
  return x;
}

inline Value normMark(const Value& x) { return normNull(x); }

inline bool scalarEq(const Value& a, const Value& b) {
  if (a.type != b.type) return false;
  switch (a.type) {
    case Type::Null:
      return true;
    case Type::Bool:
      return a.b == b.b;
    case Type::Number:
      return a.num == b.num;
    case Type::String:
      return a.str == b.str;
    default:
      return false;
  }
}

inline bool deepEq(const Value& a, const Value& b) {
  if (a.is_array() && b.is_array()) {
    if (a.arr->size() != b.arr->size()) return false;
    for (size_t i = 0; i < a.arr->size(); i++)
      if (!deepEq((*a.arr)[i], (*b.arr)[i])) return false;
    return true;
  }
  if (a.is_object() && b.is_object()) {
    if (a.obj->size() != b.obj->size()) return false;
    // Mirrors JS deepEq: same number of keys, every key in `a` present in `b`
    // with deep-equal value (key order not required).
    for (const auto& kv : *a.obj) {
      const Value* bv = b.find(kv.first);
      if (bv == nullptr || !deepEq(kv.second, *bv)) return false;
    }
    return true;
  }
  return scalarEq(a, b);
}

// ─── pure comparison helpers ───────────────────────────────────────────────

inline bool matchval(const Value& check, const Value& base) {
  if (scalarEq(check, base)) return true;
  // Deep equality for compound values (=== in JS is identity, but a string
  // check against a compound base never matches by identity; preserve the
  // string-special-casing below for strings).
  if (check.is_string()) {
    std::string basestr = stringify(base);
    const std::string& c = check.str;
    if (c.size() >= 2 && c.front() == '/' && c.back() == '/') {
      std::string re = c.substr(1, c.size() - 2);
      try {
        std::regex rx(re);
        return std::regex_search(basestr, rx);
      } catch (const std::regex_error&) {
        return false;
      }
    }
    std::string lo_base = basestr, lo_c = c;
    for (auto& ch : lo_base) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    for (auto& ch : lo_c) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    return lo_base.find(lo_c) != std::string::npos;
  }
  // No function type in this value model; otherwise would return true.
  return false;
}

inline bool equal(const Value& expected, const Value& actual) {
  return deepEq(normNull(expected), normNull(actual));
}

inline bool equalStrict(const Value& expected, const Value& actual) {
  return deepEq(normMark(expected), normMark(actual));
}

inline bool errorMatches(const ErrorCheck& check, const std::string& message) {
  if (check.any) return true;
  if (!check.text.has_value()) return false;
  if (check.regex) {
    try {
      std::regex rx(*check.text);
      return std::regex_search(message, rx);
    } catch (const std::regex_error&) {
      return false;
    }
  }
  std::string lo_msg = message, lo_t = *check.text;
  for (auto& c : lo_msg) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  for (auto& c : lo_t) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return lo_msg.find(lo_t) != std::string::npos;
}

// getpath used by structMatch: returns nullptr for an absent (undefined) slot.
inline const Value* getpathp(const Value* store, const std::vector<std::string>& path) {
  const Value* cur = store;
  for (const auto& key : path) {
    if (cur == nullptr || cur->is_null()) return nullptr;
    if (cur->is_array()) {
      // numeric index
      char* end = nullptr;
      long idx = std::strtol(key.c_str(), &end, 10);
      if (end == key.c_str() || *end != '\0' || idx < 0 ||
          static_cast<size_t>(idx) >= cur->arr->size()) {
        cur = nullptr;
      } else {
        cur = &(*cur->arr)[static_cast<size_t>(idx)];
      }
    } else if (cur->is_object()) {
      cur = cur->find(key);
    } else {
      cur = nullptr;
    }
  }
  return cur;
}

inline bool isNodeV(const Value& v) { return v.is_array() || v.is_object(); }

// walkLeaves: visit every scalar leaf of `node` with its path.
template <typename Fn>
inline void walkLeaves(const Value& node, std::vector<std::string>& path, Fn&& fn) {
  if (node.is_array()) {
    for (size_t i = 0; i < node.arr->size(); i++) {
      path.push_back(std::to_string(i));
      walkLeaves((*node.arr)[i], path, fn);
      path.pop_back();
    }
  } else if (node.is_object()) {
    for (const auto& kv : *node.obj) {
      path.push_back(kv.first);
      walkLeaves(kv.second, path, fn);
      path.pop_back();
    }
  } else {
    fn(node, path);
  }
}

inline MatchResult structMatch(const Value& check, const Value& base) {
  MatchResult result;
  result.ok = true;
  std::vector<std::string> path;
  walkLeaves(check, path, [&](const Value& val, const std::vector<std::string>& p) {
    if (!result.ok) return;
    const Value* basevalp = getpathp(&base, p);
    Value baseval = basevalp ? *basevalp : Value::null();
    bool absent = (basevalp == nullptr);
    if (!absent && scalarEq(val, baseval)) return;
    if (val.is_string() && val.str == UNDEFMARK() && absent) return;
    if (val.is_string() && val.str == EXISTSMARK() && !absent && !baseval.is_null()) return;
    if (!matchval(val, baseval)) {
      result.ok = false;
      result.path = p;
      result.expected = val;
      result.actual = basevalp ? std::optional<Value>(*basevalp) : std::nullopt;
    }
  });
  return result;
}

// ─── normalization (raw -> Entry) ──────────────────────────────────────────

inline Input resolveInput(const Value& raw) {
  Input in;
  if (raw.has("ctx")) {
    in.kind = InputKind::CTX;
    in.ctx = *raw.find("ctx");
    return in;
  }
  if (raw.has("args")) {
    in.kind = InputKind::ARGS;
    in.args = *raw.find("args");
    return in;
  }
  in.kind = InputKind::IN;
  const Value* p = raw.find("in");
  in.in = p ? *p : Value::null();
  return in;
}

inline ErrorCheck parseErr(const Value& err) {
  ErrorCheck ec;
  if (err.is_bool() && err.b) {
    ec.any = true;
    return ec;
  }
  if (err.is_string()) {
    const std::string& s = err.str;
    if (s.size() >= 2 && s.front() == '/' && s.back() == '/') {
      ec.any = false;
      ec.text = s.substr(1, s.size() - 2);
      ec.regex = true;
      return ec;
    }
    ec.any = false;
    ec.text = s;
    ec.regex = false;
    return ec;
  }
  // Non-true, non-string err spec: treat as "any error".
  ec.any = true;
  return ec;
}

inline Expect resolveExpect(const Value& raw) {
  Expect e;
  std::optional<Value> matchPart;
  if (raw.has("match")) matchPart = *raw.find("match");

  if (raw.has("err")) {
    e.kind = ExpectKind::ERROR;
    e.error = parseErr(*raw.find("err"));
    e.match = matchPart;
    return e;
  }
  if (raw.has("out")) {
    e.kind = ExpectKind::VALUE;
    e.value = *raw.find("out");
    e.match = matchPart;
    return e;
  }
  if (raw.has("match")) {
    e.kind = ExpectKind::MATCH;
    e.match = *raw.find("match");
    return e;
  }
  e.kind = ExpectKind::ABSENT;
  return e;
}

inline Entry normalize(const std::string& fn, const std::string& group, size_t index,
                       const Value& raw) {
  Entry e;
  e.function = fn;
  e.group = group;
  e.index = index;
  const Value* idp = raw.find("id");
  if (idp != nullptr && !idp->is_null()) {
    e.id = idp->is_string() ? idp->str : stringify(*idp);
  }
  const Value* docp = raw.find("doc");
  e.doc = (docp != nullptr && docp->is_bool() && docp->b);
  const Value* clientp = raw.find("client");
  if (clientp != nullptr && !clientp->is_null()) {
    e.client = clientp->is_string() ? clientp->str : stringify(*clientp);
  }
  e.input = resolveInput(raw);
  e.expect = resolveExpect(raw);
  e.raw = raw;
  return e;
}

// ─── default corpus path resolution ────────────────────────────────────────

// Convention: when no explicit path is given, resolve "build/test/test.json"
// relative to the current working directory (the repo root). The smoke harness
// is run from the repo root, matching the existing cpp runner which reads
// "../build/test/test.json" from its own build dir. Tests may pass an explicit
// path.
inline std::string defaultTestFile() { return "build/test/test.json"; }

// ─── TestProvider ──────────────────────────────────────────────────────────

class TestProvider {
 public:
  Value spec;

  TestProvider() = default;
  explicit TestProvider(Value s) : spec(std::move(s)) {}

  static TestProvider load(const std::string& path = "") {
    std::string file = path.empty() ? defaultTestFile() : path;
    std::ifstream f(file, std::ios::binary);
    if (!f) throw std::runtime_error("cannot open corpus: " + file);
    std::ostringstream ss;
    ss << f.rdbuf();
    return TestProvider(parseJson(ss.str()));
  }

  const Value& raw() const { return spec; }

  std::vector<std::string> functions() const {
    const Value& root = rootNode();
    std::vector<std::string> out;
    if (!root.is_object()) return out;
    for (const auto& kv : *root.obj) {
      if (isGroupBag(kv.second) || hasGroups(kv.second)) out.push_back(kv.first);
    }
    return out;
  }

  std::vector<std::string> groups(const std::string& fn) const {
    const Value& node = fnNode(fn);
    std::vector<std::string> out;
    if (!node.is_object()) return out;
    for (const auto& kv : *node.obj) {
      if (kv.first != "name" && isGroupBag(kv.second)) out.push_back(kv.first);
    }
    return out;
  }

  std::vector<Entry> entries(const std::string& fn,
                             const std::optional<std::string>& group = std::nullopt) const {
    const Value& node = fnNode(fn);
    std::vector<std::string> gs;
    if (group.has_value())
      gs.push_back(*group);
    else
      gs = groups(fn);

    std::vector<Entry> out;
    for (const auto& g : gs) {
      const Value* bag = node.find(g);
      if (bag == nullptr || !isGroupBag(*bag)) continue;
      const Value* set = bag->find("set");
      if (set == nullptr || !set->is_array()) continue;
      for (size_t i = 0; i < set->arr->size(); i++) {
        out.push_back(normalize(fn, g, i, (*set->arr)[i]));
      }
    }
    return out;
  }

 private:
  const Value& rootNode() const {
    const Value* s = spec.find("struct");
    return (s != nullptr) ? *s : spec;
  }

  const Value& fnNode(const std::string& fn) const {
    const Value* s = spec.find("struct");
    if (s != nullptr) {
      const Value* node = s->find(fn);
      if (node != nullptr) return *node;
    }
    const Value* node = spec.find(fn);
    if (node != nullptr) return *node;
    throw std::runtime_error("Unknown function: " + fn);
  }
};

}  // namespace testproto
}  // namespace voxgig

#endif  // VOXGIG_TEST_PROVIDER_HPP
