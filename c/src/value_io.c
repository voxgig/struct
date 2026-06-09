/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
 *
 * JSON I/O — pure C, no third-party dependency. Replaces an earlier
 * cJSON-backed implementation so the C port has no link-time deps.
 */

#include "value_io.h"
#include "voxgig_struct.h"

#include <ctype.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ===========================================================================
 * Parser — recursive descent over a UTF-8 byte buffer.
 *
 * Accepts:
 *   - null / true / false
 *   - numbers (integer or decimal/exponent — split between voxgig_int and voxgig_double)
 *   - strings, with the standard JSON escapes including \uXXXX (UTF-16
 *     surrogate pairs are decoded to UTF-8 bytes)
 *   - arrays and objects, with arbitrary whitespace between tokens
 *
 * Anything malformed → returns voxgig_new_undef() and leaves the cursor where it
 * stopped. Mirrors cJSON's "best-effort, never throw" behaviour.
 * ===========================================================================*/

typedef struct {
  const char* src;
  size_t len;
  size_t pos;
} jp;

static void jp_skip_ws(jp* p) {
  while (p->pos < p->len) {
    char c = p->src[p->pos];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      p->pos++;
    } else {
      break;
    }
  }
}

static int jp_peek(jp* p) {
  return p->pos < p->len ? (unsigned char)p->src[p->pos] : -1;
}

static bool jp_match(jp* p, const char* lit) {
  size_t n = strlen(lit);
  if (p->pos + n > p->len)
    return false;
  if (memcmp(p->src + p->pos, lit, n) != 0)
    return false;
  p->pos += n;
  return true;
}

static int jp_hex(int c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return 10 + c - 'a';
  if (c >= 'A' && c <= 'F')
    return 10 + c - 'A';
  return -1;
}

static void sb_putc(char** buf, size_t* len, size_t* cap, char c) {
  if (*len + 2 > *cap) {
    size_t nc = *cap == 0 ? 32 : *cap * 2;
    char* nb = (char*)realloc(*buf, nc);
    if (!nb)
      abort();
    *buf = nb;
    *cap = nc;
  }
  (*buf)[(*len)++] = c;
  (*buf)[*len] = '\0';
}

static void sb_put_codepoint(char** buf, size_t* len, size_t* cap, uint32_t cp) {
  if (cp < 0x80) {
    sb_putc(buf, len, cap, (char)cp);
  } else if (cp < 0x800) {
    sb_putc(buf, len, cap, (char)(0xC0 | (cp >> 6)));
    sb_putc(buf, len, cap, (char)(0x80 | (cp & 0x3F)));
  } else if (cp < 0x10000) {
    sb_putc(buf, len, cap, (char)(0xE0 | (cp >> 12)));
    sb_putc(buf, len, cap, (char)(0x80 | ((cp >> 6) & 0x3F)));
    sb_putc(buf, len, cap, (char)(0x80 | (cp & 0x3F)));
  } else {
    sb_putc(buf, len, cap, (char)(0xF0 | (cp >> 18)));
    sb_putc(buf, len, cap, (char)(0x80 | ((cp >> 12) & 0x3F)));
    sb_putc(buf, len, cap, (char)(0x80 | ((cp >> 6) & 0x3F)));
    sb_putc(buf, len, cap, (char)(0x80 | (cp & 0x3F)));
  }
}

static char* jp_string(jp* p) {
  if (jp_peek(p) != '"')
    return NULL;
  p->pos++; /* eat opening " */
  char* buf = NULL;
  size_t len = 0, cap = 0;
  while (p->pos < p->len) {
    char c = p->src[p->pos++];
    if (c == '"') {
      if (!buf)
        sb_putc(&buf, &len, &cap, '\0'), len = 0;
      return buf ? buf : strdup("");
    }
    if (c == '\\') {
      if (p->pos >= p->len)
        break;
      char e = p->src[p->pos++];
      switch (e) {
      case '"':
        sb_putc(&buf, &len, &cap, '"');
        break;
      case '\\':
        sb_putc(&buf, &len, &cap, '\\');
        break;
      case '/':
        sb_putc(&buf, &len, &cap, '/');
        break;
      case 'b':
        sb_putc(&buf, &len, &cap, '\b');
        break;
      case 'f':
        sb_putc(&buf, &len, &cap, '\f');
        break;
      case 'n':
        sb_putc(&buf, &len, &cap, '\n');
        break;
      case 'r':
        sb_putc(&buf, &len, &cap, '\r');
        break;
      case 't':
        sb_putc(&buf, &len, &cap, '\t');
        break;
      case 'u': {
        if (p->pos + 4 > p->len)
          goto bad;
        int h1 = jp_hex((unsigned char)p->src[p->pos]);
        int h2 = jp_hex((unsigned char)p->src[p->pos + 1]);
        int h3 = jp_hex((unsigned char)p->src[p->pos + 2]);
        int h4 = jp_hex((unsigned char)p->src[p->pos + 3]);
        if (h1 < 0 || h2 < 0 || h3 < 0 || h4 < 0)
          goto bad;
        uint32_t cp = (uint32_t)((h1 << 12) | (h2 << 8) | (h3 << 4) | h4);
        p->pos += 4;
        if (cp >= 0xD800 && cp <= 0xDBFF) {
          /* High surrogate — expect low surrogate. */
          if (p->pos + 6 <= p->len && p->src[p->pos] == '\\' && p->src[p->pos + 1] == 'u') {
            int g1 = jp_hex((unsigned char)p->src[p->pos + 2]);
            int g2 = jp_hex((unsigned char)p->src[p->pos + 3]);
            int g3 = jp_hex((unsigned char)p->src[p->pos + 4]);
            int g4 = jp_hex((unsigned char)p->src[p->pos + 5]);
            if (g1 >= 0 && g2 >= 0 && g3 >= 0 && g4 >= 0) {
              uint32_t lo = (uint32_t)((g1 << 12) | (g2 << 8) | (g3 << 4) | g4);
              if (lo >= 0xDC00 && lo <= 0xDFFF) {
                p->pos += 6;
                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
              }
            }
          }
        }
        sb_put_codepoint(&buf, &len, &cap, cp);
        break;
      }
      default:
        sb_putc(&buf, &len, &cap, e);
        break;
      }
    } else {
      sb_putc(&buf, &len, &cap, c);
    }
  }
bad:
  free(buf);
  return NULL;
}

static voxgig_value* jp_value(jp* p); /* fwd */

static voxgig_value* jp_number(jp* p) {
  size_t start = p->pos;
  if (jp_peek(p) == '-')
    p->pos++;
  bool has_dot = false, has_exp = false;
  while (p->pos < p->len) {
    char c = p->src[p->pos];
    if (c >= '0' && c <= '9') {
      p->pos++;
    } else if (c == '.' && !has_dot && !has_exp) {
      has_dot = true;
      p->pos++;
    } else if ((c == 'e' || c == 'E') && !has_exp) {
      has_exp = true;
      p->pos++;
      if (p->pos < p->len && (p->src[p->pos] == '+' || p->src[p->pos] == '-'))
        p->pos++;
    } else {
      break;
    }
  }
  if (p->pos == start)
    return voxgig_new_undef();
  size_t n = p->pos - start;
  char tmp[64];
  if (n >= sizeof(tmp))
    n = sizeof(tmp) - 1;
  memcpy(tmp, p->src + start, n);
  tmp[n] = '\0';
  if (!has_dot && !has_exp) {
    long long ll = strtoll(tmp, NULL, 10);
    return voxgig_new_int((int64_t)ll);
  }
  double d = strtod(tmp, NULL);
  return voxgig_new_double(d);
}

static voxgig_value* jp_array(jp* p) {
  if (jp_peek(p) != '[')
    return voxgig_new_undef();
  p->pos++;
  voxgig_value* lv = voxgig_new_list();
  jp_skip_ws(p);
  if (jp_peek(p) == ']') {
    p->pos++;
    return lv;
  }
  for (;;) {
    jp_skip_ws(p);
    voxgig_value* item = jp_value(p);
    voxgig_list_push(voxgig_as_list(lv), item);
    jp_skip_ws(p);
    int c = jp_peek(p);
    if (c == ',') {
      p->pos++;
      continue;
    }
    if (c == ']') {
      p->pos++;
      break;
    }
    /* Malformed — return what we have. */
    break;
  }
  return lv;
}

static voxgig_value* jp_object(jp* p) {
  if (jp_peek(p) != '{')
    return voxgig_new_undef();
  p->pos++;
  voxgig_value* mv = voxgig_new_map();
  jp_skip_ws(p);
  if (jp_peek(p) == '}') {
    p->pos++;
    return mv;
  }
  for (;;) {
    jp_skip_ws(p);
    char* key = jp_string(p);
    if (!key) {
      break;
    }
    jp_skip_ws(p);
    if (jp_peek(p) != ':') {
      free(key);
      break;
    }
    p->pos++;
    jp_skip_ws(p);
    voxgig_value* val = jp_value(p);
    voxgig_map_set(voxgig_as_map(mv), key, val);
    free(key);
    jp_skip_ws(p);
    int c = jp_peek(p);
    if (c == ',') {
      p->pos++;
      continue;
    }
    if (c == '}') {
      p->pos++;
      break;
    }
    break;
  }
  return mv;
}

static voxgig_value* jp_value(jp* p) {
  jp_skip_ws(p);
  int c = jp_peek(p);
  if (c < 0)
    return voxgig_new_undef();
  if (c == 'n' && jp_match(p, "null"))
    return voxgig_new_null();
  if (c == 't' && jp_match(p, "true"))
    return voxgig_new_bool(true);
  if (c == 'f' && jp_match(p, "false"))
    return voxgig_new_bool(false);
  if (c == '"') {
    char* s = jp_string(p);
    voxgig_value* v = voxgig_new_string(s ? s : "");
    free(s);
    return v;
  }
  if (c == '-' || (c >= '0' && c <= '9'))
    return jp_number(p);
  if (c == '[')
    return jp_array(p);
  if (c == '{')
    return jp_object(p);
  /* Unrecognised — advance to avoid infinite loop. */
  p->pos++;
  return voxgig_new_undef();
}

voxgig_value* voxgig_parse_json(const char* text, size_t len) {
  if (!text)
    return voxgig_new_undef();
  if (len == 0)
    len = strlen(text);
  jp p = {.src = text, .len = len, .pos = 0};
  return jp_value(&p);
}

voxgig_value* voxgig_parse_json_file(const char* path) {
  FILE* f = fopen(path, "rb");
  if (!f)
    return voxgig_new_undef();
  fseek(f, 0, SEEK_END);
  long sz = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (sz < 0) {
    fclose(f);
    return voxgig_new_undef();
  }
  char* buf = (char*)malloc((size_t)sz + 1);
  if (!buf) {
    fclose(f);
    return voxgig_new_undef();
  }
  size_t rd = fread(buf, 1, (size_t)sz, f);
  buf[rd] = '\0';
  fclose(f);
  voxgig_value* v = voxgig_parse_json(buf, rd);
  free(buf);
  return v;
}

/* Serializer: defer to the library's voxgig_jsonify (compact form). */
char* voxgig_to_json(const voxgig_value* v) {
  voxgig_value* flags = voxgig_new_map();
  voxgig_map_set(voxgig_as_map(flags), "indent", voxgig_new_int(0));
  char* s = voxgig_jsonify((voxgig_value*)v, flags);
  voxgig_release(flags);
  return s;
}
