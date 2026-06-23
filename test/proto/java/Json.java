// Minimal dependency-free JSON parser and serializer for the Java test provider.
//
// Parses into java.lang.Object trees:
//   - objects -> java.util.LinkedHashMap<String,Object>  (PRESERVES key order)
//   - arrays  -> java.util.ArrayList<Object>
//   - strings -> String
//   - numbers -> Double
//   - true/false -> Boolean
//   - null -> null
//
// JDK standard library only. No Gson, no Jackson, no third-party libs.

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class Json {

  private Json() {}

  // ─── parsing ───────────────────────────────────────────────────────────────

  public static Object parse(String text) {
    Parser p = new Parser(text);
    p.skipWs();
    Object v = p.parseValue();
    p.skipWs();
    if (!p.atEnd()) {
      throw new JsonException("Trailing content at position " + p.pos);
    }
    return v;
  }

  public static class JsonException extends RuntimeException {
    public JsonException(String msg) {
      super(msg);
    }
  }

  private static final class Parser {
    final String s;
    int pos;

    Parser(String s) {
      this.s = s;
    }

    boolean atEnd() {
      return pos >= s.length();
    }

    void skipWs() {
      while (pos < s.length()) {
        char c = s.charAt(pos);
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
          pos++;
        } else {
          break;
        }
      }
    }

    char peek() {
      if (pos >= s.length()) {
        throw new JsonException("Unexpected end of input");
      }
      return s.charAt(pos);
    }

    Object parseValue() {
      skipWs();
      char c = peek();
      switch (c) {
        case '{':
          return parseObject();
        case '[':
          return parseArray();
        case '"':
          return parseString();
        case 't':
        case 'f':
          return parseBool();
        case 'n':
          return parseNull();
        default:
          if (c == '-' || (c >= '0' && c <= '9')) {
            return parseNumber();
          }
          throw new JsonException("Unexpected char '" + c + "' at position " + pos);
      }
    }

    Map<String, Object> parseObject() {
      Map<String, Object> m = new LinkedHashMap<>();
      pos++; // consume '{'
      skipWs();
      if (peek() == '}') {
        pos++;
        return m;
      }
      while (true) {
        skipWs();
        if (peek() != '"') {
          throw new JsonException("Expected string key at position " + pos);
        }
        String key = parseString();
        skipWs();
        if (peek() != ':') {
          throw new JsonException("Expected ':' at position " + pos);
        }
        pos++; // consume ':'
        Object val = parseValue();
        m.put(key, val);
        skipWs();
        char c = peek();
        if (c == ',') {
          pos++;
          continue;
        }
        if (c == '}') {
          pos++;
          break;
        }
        throw new JsonException("Expected ',' or '}' at position " + pos);
      }
      return m;
    }

    List<Object> parseArray() {
      List<Object> list = new ArrayList<>();
      pos++; // consume '['
      skipWs();
      if (peek() == ']') {
        pos++;
        return list;
      }
      while (true) {
        Object val = parseValue();
        list.add(val);
        skipWs();
        char c = peek();
        if (c == ',') {
          pos++;
          continue;
        }
        if (c == ']') {
          pos++;
          break;
        }
        throw new JsonException("Expected ',' or ']' at position " + pos);
      }
      return list;
    }

    String parseString() {
      pos++; // consume opening '"'
      StringBuilder sb = new StringBuilder();
      while (true) {
        if (pos >= s.length()) {
          throw new JsonException("Unterminated string");
        }
        char c = s.charAt(pos++);
        if (c == '"') {
          break;
        }
        if (c == '\\') {
          if (pos >= s.length()) {
            throw new JsonException("Unterminated escape");
          }
          char e = s.charAt(pos++);
          switch (e) {
            case '"':
              sb.append('"');
              break;
            case '\\':
              sb.append('\\');
              break;
            case '/':
              sb.append('/');
              break;
            case 'b':
              sb.append('\b');
              break;
            case 'f':
              sb.append('\f');
              break;
            case 'n':
              sb.append('\n');
              break;
            case 'r':
              sb.append('\r');
              break;
            case 't':
              sb.append('\t');
              break;
            case 'u':
              if (pos + 4 > s.length()) {
                throw new JsonException("Invalid \\u escape");
              }
              String hex = s.substring(pos, pos + 4);
              pos += 4;
              try {
                sb.append((char) Integer.parseInt(hex, 16));
              } catch (NumberFormatException nfe) {
                throw new JsonException("Invalid \\u escape: " + hex);
              }
              break;
            default:
              throw new JsonException("Invalid escape '\\" + e + "'");
          }
        } else {
          sb.append(c);
        }
      }
      return sb.toString();
    }

    Boolean parseBool() {
      if (s.startsWith("true", pos)) {
        pos += 4;
        return Boolean.TRUE;
      }
      if (s.startsWith("false", pos)) {
        pos += 5;
        return Boolean.FALSE;
      }
      throw new JsonException("Invalid literal at position " + pos);
    }

    Object parseNull() {
      if (s.startsWith("null", pos)) {
        pos += 4;
        return null;
      }
      throw new JsonException("Invalid literal at position " + pos);
    }

    Double parseNumber() {
      int start = pos;
      if (peek() == '-') {
        pos++;
      }
      while (pos < s.length() && Character.isDigit(s.charAt(pos))) {
        pos++;
      }
      if (pos < s.length() && s.charAt(pos) == '.') {
        pos++;
        while (pos < s.length() && Character.isDigit(s.charAt(pos))) {
          pos++;
        }
      }
      if (pos < s.length() && (s.charAt(pos) == 'e' || s.charAt(pos) == 'E')) {
        pos++;
        if (pos < s.length() && (s.charAt(pos) == '+' || s.charAt(pos) == '-')) {
          pos++;
        }
        while (pos < s.length() && Character.isDigit(s.charAt(pos))) {
          pos++;
        }
      }
      String num = s.substring(start, pos);
      try {
        return Double.parseDouble(num);
      } catch (NumberFormatException nfe) {
        throw new JsonException("Invalid number '" + num + "'");
      }
    }
  }

  // ─── serialization ───────────────────────────────────────────────────────────

  // Compact JSON serialization. Whole-number Doubles render without a trailing
  // ".0" (so 42.0 -> "42"), matching the canonical stringify expectations.
  public static String stringify(Object v) {
    StringBuilder sb = new StringBuilder();
    write(v, sb);
    return sb.toString();
  }

  @SuppressWarnings("unchecked")
  private static void write(Object v, StringBuilder sb) {
    if (v == null) {
      sb.append("null");
    } else if (v instanceof String) {
      writeString((String) v, sb);
    } else if (v instanceof Double) {
      writeNumber((Double) v, sb);
    } else if (v instanceof Number) {
      // Other numeric types (Long, Integer, etc.) — render plainly.
      writeNumber(((Number) v).doubleValue(), sb);
    } else if (v instanceof Boolean) {
      sb.append(((Boolean) v) ? "true" : "false");
    } else if (v instanceof Map) {
      sb.append('{');
      boolean first = true;
      for (Map.Entry<?, ?> e : ((Map<?, ?>) v).entrySet()) {
        if (!first) {
          sb.append(',');
        }
        first = false;
        writeString(String.valueOf(e.getKey()), sb);
        sb.append(':');
        write(e.getValue(), sb);
      }
      sb.append('}');
    } else if (v instanceof List) {
      sb.append('[');
      boolean first = true;
      for (Object x : (List<Object>) v) {
        if (!first) {
          sb.append(',');
        }
        first = false;
        write(x, sb);
      }
      sb.append(']');
    } else {
      writeString(String.valueOf(v), sb);
    }
  }

  private static void writeNumber(double d, StringBuilder sb) {
    if (Double.isFinite(d) && Math.floor(d) == d && Math.abs(d) < 1e15) {
      sb.append(Long.toString((long) d));
    } else {
      sb.append(Double.toString(d));
    }
  }

  private static void writeString(String s, StringBuilder sb) {
    sb.append('"');
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      switch (c) {
        case '"':
          sb.append("\\\"");
          break;
        case '\\':
          sb.append("\\\\");
          break;
        case '\b':
          sb.append("\\b");
          break;
        case '\f':
          sb.append("\\f");
          break;
        case '\n':
          sb.append("\\n");
          break;
        case '\r':
          sb.append("\\r");
          break;
        case '\t':
          sb.append("\\t");
          break;
        default:
          if (c < 0x20) {
            sb.append(String.format("\\u%04x", (int) c));
          } else {
            sb.append(c);
          }
      }
    }
    sb.append('"');
  }
}
