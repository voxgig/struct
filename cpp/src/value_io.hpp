// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
//
// Voxgig Struct — JSON I/O bridge.
//
// Hand-written recursive-descent JSON parser (no third-party deps).
// Runtime container is Value; this file converts to/from JSON text.

#ifndef VOXGIG_STRUCT_VALUE_IO_HPP
#define VOXGIG_STRUCT_VALUE_IO_HPP

#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>

#include "value.hpp"
#include "voxgig_struct.hpp" // jsonify() for the serializer side

namespace voxgig {
namespace structlib {

// ===========================================================================
// Parser — same algorithm as c/src/value_io.c jp_*. Accepts the standard
// JSON grammar including \\uXXXX escapes and surrogate pairs. On any
// malformed input returns Value::undef() (no exceptions thrown).
// ===========================================================================

namespace _jp {

struct State {
  const std::string& src;
  size_t pos = 0;
};

inline void skip_ws(State& p) {
  while (p.pos < p.src.size()) {
    char c = p.src[p.pos];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
      p.pos++;
    else
      break;
  }
}

inline int peek(const State& p) {
  return p.pos < p.src.size() ? static_cast<unsigned char>(p.src[p.pos]) : -1;
}

inline bool match(State& p, const char* lit) {
  size_t n = std::strlen(lit);
  if (p.pos + n > p.src.size())
    return false;
  if (p.src.compare(p.pos, n, lit) != 0)
    return false;
  p.pos += n;
  return true;
}

inline int hex(int c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return 10 + c - 'a';
  if (c >= 'A' && c <= 'F')
    return 10 + c - 'A';
  return -1;
}

inline void put_codepoint(std::string& dst, uint32_t cp) {
  if (cp < 0x80) {
    dst.push_back(static_cast<char>(cp));
  } else if (cp < 0x800) {
    dst.push_back(static_cast<char>(0xC0 | (cp >> 6)));
    dst.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  } else if (cp < 0x10000) {
    dst.push_back(static_cast<char>(0xE0 | (cp >> 12)));
    dst.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
    dst.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  } else {
    dst.push_back(static_cast<char>(0xF0 | (cp >> 18)));
    dst.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
    dst.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
    dst.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  }
}

inline bool parse_string(State& p, std::string& out) {
  if (peek(p) != '"')
    return false;
  p.pos++;
  while (p.pos < p.src.size()) {
    char c = p.src[p.pos++];
    if (c == '"')
      return true;
    if (c == '\\') {
      if (p.pos >= p.src.size())
        return false;
      char e = p.src[p.pos++];
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
        if (p.pos + 4 > p.src.size())
          return false;
        int h1 = hex(static_cast<unsigned char>(p.src[p.pos]));
        int h2 = hex(static_cast<unsigned char>(p.src[p.pos + 1]));
        int h3 = hex(static_cast<unsigned char>(p.src[p.pos + 2]));
        int h4 = hex(static_cast<unsigned char>(p.src[p.pos + 3]));
        if (h1 < 0 || h2 < 0 || h3 < 0 || h4 < 0)
          return false;
        uint32_t cp = static_cast<uint32_t>((h1 << 12) | (h2 << 8) | (h3 << 4) | h4);
        p.pos += 4;
        if (cp >= 0xD800 && cp <= 0xDBFF && p.pos + 6 <= p.src.size() && p.src[p.pos] == '\\' &&
            p.src[p.pos + 1] == 'u') {
          int g1 = hex(static_cast<unsigned char>(p.src[p.pos + 2]));
          int g2 = hex(static_cast<unsigned char>(p.src[p.pos + 3]));
          int g3 = hex(static_cast<unsigned char>(p.src[p.pos + 4]));
          int g4 = hex(static_cast<unsigned char>(p.src[p.pos + 5]));
          if (g1 >= 0 && g2 >= 0 && g3 >= 0 && g4 >= 0) {
            uint32_t lo = static_cast<uint32_t>((g1 << 12) | (g2 << 8) | (g3 << 4) | g4);
            if (lo >= 0xDC00 && lo <= 0xDFFF) {
              p.pos += 6;
              cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
            }
          }
        }
        put_codepoint(out, cp);
        break;
      }
      default:
        out.push_back(e);
        break;
      }
    } else {
      out.push_back(c);
    }
  }
  return false;
}

inline Value parse_value(State& p);

inline Value parse_number(State& p) {
  size_t start = p.pos;
  if (peek(p) == '-')
    p.pos++;
  bool has_dot = false, has_exp = false;
  while (p.pos < p.src.size()) {
    char c = p.src[p.pos];
    if (c >= '0' && c <= '9') {
      p.pos++;
    } else if (c == '.' && !has_dot && !has_exp) {
      has_dot = true;
      p.pos++;
    } else if ((c == 'e' || c == 'E') && !has_exp) {
      has_exp = true;
      p.pos++;
      if (p.pos < p.src.size() && (p.src[p.pos] == '+' || p.src[p.pos] == '-'))
        p.pos++;
    } else {
      break;
    }
  }
  if (p.pos == start)
    return Value();
  std::string tok = p.src.substr(start, p.pos - start);
  if (!has_dot && !has_exp) {
    return Value(static_cast<int64_t>(std::strtoll(tok.c_str(), nullptr, 10)));
  }
  return Value(std::strtod(tok.c_str(), nullptr));
}

inline Value parse_array(State& p) {
  if (peek(p) != '[')
    return Value();
  p.pos++;
  auto out = std::make_shared<List>();
  skip_ws(p);
  if (peek(p) == ']') {
    p.pos++;
    return Value(std::move(out));
  }
  while (true) {
    skip_ws(p);
    out->push_back(parse_value(p));
    skip_ws(p);
    int c = peek(p);
    if (c == ',') {
      p.pos++;
      continue;
    }
    if (c == ']') {
      p.pos++;
      break;
    }
    break;
  }
  return Value(std::move(out));
}

inline Value parse_object(State& p) {
  if (peek(p) != '{')
    return Value();
  p.pos++;
  auto out = std::shared_ptr<Map>(new Map());
  skip_ws(p);
  if (peek(p) == '}') {
    p.pos++;
    return Value(std::move(out));
  }
  while (true) {
    skip_ws(p);
    std::string key;
    if (!parse_string(p, key))
      break;
    skip_ws(p);
    if (peek(p) != ':')
      break;
    p.pos++;
    skip_ws(p);
    Value val = parse_value(p);
    out->set(key, val);
    skip_ws(p);
    int c = peek(p);
    if (c == ',') {
      p.pos++;
      continue;
    }
    if (c == '}') {
      p.pos++;
      break;
    }
    break;
  }
  return Value(std::move(out));
}

inline Value parse_value(State& p) {
  skip_ws(p);
  int c = peek(p);
  if (c < 0)
    return Value();
  if (c == 'n' && match(p, "null"))
    return Value(nullptr);
  if (c == 't' && match(p, "true"))
    return Value(true);
  if (c == 'f' && match(p, "false"))
    return Value(false);
  if (c == '"') {
    std::string s;
    parse_string(p, s);
    return Value(std::move(s));
  }
  if (c == '-' || (c >= '0' && c <= '9'))
    return parse_number(p);
  if (c == '[')
    return parse_array(p);
  if (c == '{')
    return parse_object(p);
  p.pos++;
  return Value();
}

} // namespace _jp

// ---- JSON text I/O ----

inline Value parse_json(const std::string& text) {
  _jp::State p{text, 0};
  return _jp::parse_value(p);
}

inline Value parse_json_file(const std::string& path) {
  std::ifstream f(path);
  if (!f)
    throw std::runtime_error("Cannot open " + path);
  std::stringstream ss;
  ss << f.rdbuf();
  return parse_json(ss.str());
}

inline std::string dump_json(const Value& v, int indent = -1) {
  return jsonify(v, indent < 0 ? 0 : indent);
}

} // namespace structlib
} // namespace voxgig

#endif // VOXGIG_STRUCT_VALUE_IO_HPP
