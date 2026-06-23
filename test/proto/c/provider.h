/* Test Provider (prototype) — C11 port of the canonical ts/provider.ts.
 *
 * Reads the shared corpus (build/test/test.json) and hands test code clean,
 * normalized cases. It is NOT a test runner: it never calls the subject and
 * never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
 *
 * DEPENDENCY-FREE and self-contained: this prototype ships its own minimal
 * JSON parser and does NOT depend on the voxgig_struct C library. Only the C
 * standard library (plus POSIX <regex.h> for regex helpers, standard on Linux).
 *
 * Single self-contained header-with-impl: define PROVIDER_IMPL in exactly one
 * translation unit before including this header to pull in the implementation.
 *
 * Memory: this is a prototype. Parsed values and entries are arena-ish and
 * intentionally leak rather than free; the contract is "crashing is not
 * acceptable, leaking is".
 *
 * Corpus-path convention: provider_load(NULL) resolves to the relative path
 * "build/test/test.json", which works when the process is run from the repo
 * root. An absolute (or any explicit) path may be passed instead and is used
 * verbatim.
 */

#ifndef PROVIDER_H
#define PROVIDER_H

#include <stdbool.h>
#include <stddef.h>

/* ─── JSON value model ─────────────────────────────────────────────────────
 * Tagged union. Objects preserve key INSERTION ORDER: keys and values are
 * stored in parallel arrays in parse order. */

typedef enum {
  JV_NULL = 0,
  JV_BOOL,
  JV_NUM,
  JV_STR,
  JV_ARR,
  JV_OBJ
} jv_type;

typedef struct jvalue jvalue;

struct jvalue {
  jv_type type;
  union {
    bool b;     /* JV_BOOL */
    double n;   /* JV_NUM  */
    char* s;    /* JV_STR  (NUL-terminated, owned) */
    struct {    /* JV_ARR  */
      jvalue** items;
      size_t len;
      size_t cap;
    } arr;
    struct {    /* JV_OBJ  — parallel arrays, insertion order */
      char** keys;
      jvalue** vals;
      size_t len;
      size_t cap;
    } obj;
  } as;
};

/* Parse a NUL-terminated JSON string. Returns NULL on parse error. */
jvalue* jv_parse(const char* text);
/* Parse a whole file. Returns NULL on read or parse error. */
jvalue* jv_parse_file(const char* path);

/* Object key lookup honouring insertion order. Returns NULL if absent. */
jvalue* jv_obj_get(const jvalue* o, const char* key);
/* Key-presence test (distinct from "value is null"). */
bool jv_obj_has(const jvalue* o, const char* key);

/* Compact JSON serialization (owned, malloc'd). */
char* jv_stringify(const jvalue* v);

/* ─── Provider data model ──────────────────────────────────────────────────*/

typedef enum { IN_IN = 0, IN_ARGS, IN_CTX } input_kind;
typedef enum { EX_VALUE = 0, EX_ERROR, EX_MATCH, EX_ABSENT } expect_kind;

typedef struct {
  input_kind kind;
  jvalue* in;    /* kind==IN_IN   — single arg; native null if "in" absent */
  jvalue* args;  /* kind==IN_ARGS — positional vector (JV_ARR) */
  jvalue* ctx;   /* kind==IN_CTX  — context map (JV_OBJ) */
} Input;

typedef struct {
  bool any;
  char* text;   /* may be NULL */
  bool regex;
} ErrorCheck;

typedef struct {
  expect_kind kind;
  jvalue* value;       /* kind==VALUE — may be JV_NULL literal */
  ErrorCheck error;    /* kind==ERROR */
  jvalue* match;       /* kind==MATCH, or co-existing match block (else NULL) */
} Expect;

typedef struct {
  const char* function;
  const char* group;
  int index;
  char* id;       /* may be NULL */
  bool doc;
  char* client;   /* may be NULL */
  Input input;
  Expect expect;
  jvalue* raw;    /* the original entry map, untouched */
} Entry;

typedef struct Provider Provider;

/* Load the corpus. If path is NULL, resolves to "build/test/test.json"
 * (relative to cwd — run from the repo root). Returns NULL on failure. */
Provider* provider_load(const char* path);

/* The parsed test.json (escape hatch). */
jvalue* provider_raw(Provider* p);

/* Ordered list of function names. *out_len receives the count. Owned by p. */
const char** provider_functions(Provider* p, size_t* out_len);
/* Ordered group names for fn. *out_len receives the count. Owned (leaked). */
const char** provider_groups(Provider* p, const char* fn, size_t* out_len);
/* Normalized entries for fn (all groups) or one group (group != NULL).
 * *out_len receives the count. Returns a malloc'd array (leaked). */
Entry* provider_entries(Provider* p, const char* fn, const char* group, size_t* out_len);

/* ─── Pure comparison helpers (PROVIDER.md §5) ─────────────────────────────*/

typedef struct {
  bool ok;
  char** path;       /* failure path components (NULL on ok) */
  size_t path_len;
  jvalue* expected;  /* NULL on ok */
  jvalue* actual;    /* NULL on ok */
} MatchResult;

/* stringify(x): the string itself if x is JV_STR, else compact JSON. Owned. */
char* provider_stringify(const jvalue* x);

bool matchval(const jvalue* check, const jvalue* base);
bool equal(const jvalue* expected, const jvalue* actual);
bool equal_strict(const jvalue* expected, const jvalue* actual);
MatchResult struct_match(const jvalue* check, const jvalue* base);
bool error_matches(const ErrorCheck* check, const char* message);

#endif /* PROVIDER_H */

/* ════════════════════════════════════════════════════════════════════════ */
#ifdef PROVIDER_IMPL

#include <ctype.h>
#include <regex.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NULLMARK "__NULL__"
#define UNDEFMARK "__UNDEF__"
#define EXISTSMARK "__EXISTS__"

/* ─── small allocation helpers ─────────────────────────────────────────────*/

static void* xmalloc(size_t n) {
  void* p = malloc(n ? n : 1);
  if (!p) {
    fprintf(stderr, "provider: out of memory\n");
    abort();
  }
  return p;
}

static void* xrealloc(void* p, size_t n) {
  void* q = realloc(p, n ? n : 1);
  if (!q) {
    fprintf(stderr, "provider: out of memory\n");
    abort();
  }
  return q;
}

static char* xstrdup(const char* s) {
  size_t n = strlen(s) + 1;
  char* d = (char*)xmalloc(n);
  memcpy(d, s, n);
  return d;
}

/* ─── jvalue constructors ──────────────────────────────────────────────────*/

static jvalue* jv_new(jv_type t) {
  jvalue* v = (jvalue*)xmalloc(sizeof(jvalue));
  memset(v, 0, sizeof(*v));
  v->type = t;
  return v;
}

static jvalue* jv_null(void) { return jv_new(JV_NULL); }

static jvalue* jv_bool(bool b) {
  jvalue* v = jv_new(JV_BOOL);
  v->as.b = b;
  return v;
}

static jvalue* jv_num(double n) {
  jvalue* v = jv_new(JV_NUM);
  v->as.n = n;
  return v;
}

static jvalue* jv_str_owned(char* s) {
  jvalue* v = jv_new(JV_STR);
  v->as.s = s;
  return v;
}

static void jv_arr_push(jvalue* a, jvalue* item) {
  if (a->as.arr.len + 1 > a->as.arr.cap) {
    size_t nc = a->as.arr.cap ? a->as.arr.cap * 2 : 8;
    a->as.arr.items = (jvalue**)xrealloc(a->as.arr.items, nc * sizeof(jvalue*));
    a->as.arr.cap = nc;
  }
  a->as.arr.items[a->as.arr.len++] = item;
}

static void jv_obj_put(jvalue* o, char* key /*owned*/, jvalue* val) {
  if (o->as.obj.len + 1 > o->as.obj.cap) {
    size_t nc = o->as.obj.cap ? o->as.obj.cap * 2 : 8;
    o->as.obj.keys = (char**)xrealloc(o->as.obj.keys, nc * sizeof(char*));
    o->as.obj.vals = (jvalue**)xrealloc(o->as.obj.vals, nc * sizeof(jvalue*));
    o->as.obj.cap = nc;
  }
  o->as.obj.keys[o->as.obj.len] = key;
  o->as.obj.vals[o->as.obj.len] = val;
  o->as.obj.len++;
}

jvalue* jv_obj_get(const jvalue* o, const char* key) {
  if (!o || o->type != JV_OBJ) {
    return NULL;
  }
  for (size_t i = 0; i < o->as.obj.len; i++) {
    if (strcmp(o->as.obj.keys[i], key) == 0) {
      return o->as.obj.vals[i];
    }
  }
  return NULL;
}

bool jv_obj_has(const jvalue* o, const char* key) {
  if (!o || o->type != JV_OBJ) {
    return false;
  }
  for (size_t i = 0; i < o->as.obj.len; i++) {
    if (strcmp(o->as.obj.keys[i], key) == 0) {
      return true;
    }
  }
  return false;
}

/* ─── recursive-descent JSON parser ────────────────────────────────────────*/

typedef struct {
  const char* p;
  const char* end;
  bool err;
} jparser;

static void jp_skip_ws(jparser* jp) {
  while (jp->p < jp->end) {
    char c = *jp->p;
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      jp->p++;
    } else {
      break;
    }
  }
}

static jvalue* jp_value(jparser* jp);

/* Append a code point to a growing UTF-8 buffer. */
static void utf8_append(char** buf, size_t* len, size_t* cap, unsigned cp) {
  char tmp[4];
  size_t n;
  if (cp < 0x80) {
    tmp[0] = (char)cp;
    n = 1;
  } else if (cp < 0x800) {
    tmp[0] = (char)(0xC0 | (cp >> 6));
    tmp[1] = (char)(0x80 | (cp & 0x3F));
    n = 2;
  } else if (cp < 0x10000) {
    tmp[0] = (char)(0xE0 | (cp >> 12));
    tmp[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
    tmp[2] = (char)(0x80 | (cp & 0x3F));
    n = 3;
  } else {
    tmp[0] = (char)(0xF0 | (cp >> 18));
    tmp[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
    tmp[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
    tmp[3] = (char)(0x80 | (cp & 0x3F));
    n = 4;
  }
  if (*len + n > *cap) {
    size_t nc = *cap ? *cap * 2 : 16;
    while (nc < *len + n) {
      nc *= 2;
    }
    *buf = (char*)xrealloc(*buf, nc);
    *cap = nc;
  }
  memcpy(*buf + *len, tmp, n);
  *len += n;
}

static int hex4(const char* p) {
  int v = 0;
  for (int i = 0; i < 4; i++) {
    char c = p[i];
    int d;
    if (c >= '0' && c <= '9') {
      d = c - '0';
    } else if (c >= 'a' && c <= 'f') {
      d = c - 'a' + 10;
    } else if (c >= 'A' && c <= 'F') {
      d = c - 'A' + 10;
    } else {
      return -1;
    }
    v = (v << 4) | d;
  }
  return v;
}

/* Parse a string literal; jp->p must point at the opening quote. */
static char* jp_string_raw(jparser* jp) {
  if (jp->p >= jp->end || *jp->p != '"') {
    jp->err = true;
    return NULL;
  }
  jp->p++; /* opening quote */
  char* buf = NULL;
  size_t len = 0, cap = 0;
  while (jp->p < jp->end) {
    unsigned char c = (unsigned char)*jp->p;
    if (c == '"') {
      jp->p++;
      /* ensure NUL-terminated */
      if (len + 1 > cap) {
        cap = cap ? cap + 1 : 1;
        buf = (char*)xrealloc(buf, cap);
      }
      buf[len] = '\0';
      return buf ? buf : xstrdup("");
    }
    if (c == '\\') {
      jp->p++;
      if (jp->p >= jp->end) {
        jp->err = true;
        return buf;
      }
      char e = *jp->p;
      switch (e) {
        case '"': utf8_append(&buf, &len, &cap, '"'); jp->p++; break;
        case '\\': utf8_append(&buf, &len, &cap, '\\'); jp->p++; break;
        case '/': utf8_append(&buf, &len, &cap, '/'); jp->p++; break;
        case 'b': utf8_append(&buf, &len, &cap, '\b'); jp->p++; break;
        case 'f': utf8_append(&buf, &len, &cap, '\f'); jp->p++; break;
        case 'n': utf8_append(&buf, &len, &cap, '\n'); jp->p++; break;
        case 'r': utf8_append(&buf, &len, &cap, '\r'); jp->p++; break;
        case 't': utf8_append(&buf, &len, &cap, '\t'); jp->p++; break;
        case 'u': {
          jp->p++; /* past 'u' */
          if (jp->p + 4 > jp->end) {
            jp->err = true;
            return buf;
          }
          int cp = hex4(jp->p);
          if (cp < 0) {
            jp->err = true;
            return buf;
          }
          jp->p += 4;
          unsigned u = (unsigned)cp;
          /* surrogate pair */
          if (u >= 0xD800 && u <= 0xDBFF && jp->p + 6 <= jp->end &&
              jp->p[0] == '\\' && jp->p[1] == 'u') {
            int lo = hex4(jp->p + 2);
            if (lo >= 0xDC00 && lo <= 0xDFFF) {
              u = 0x10000 + ((u - 0xD800) << 10) + ((unsigned)lo - 0xDC00);
              jp->p += 6;
            }
          }
          utf8_append(&buf, &len, &cap, u);
          break;
        }
        default:
          jp->err = true;
          return buf;
      }
    } else {
      utf8_append(&buf, &len, &cap, c);
      jp->p++;
    }
  }
  jp->err = true;
  return buf;
}

static jvalue* jp_number(jparser* jp) {
  const char* start = jp->p;
  if (jp->p < jp->end && *jp->p == '-') {
    jp->p++;
  }
  while (jp->p < jp->end && isdigit((unsigned char)*jp->p)) {
    jp->p++;
  }
  if (jp->p < jp->end && *jp->p == '.') {
    jp->p++;
    while (jp->p < jp->end && isdigit((unsigned char)*jp->p)) {
      jp->p++;
    }
  }
  if (jp->p < jp->end && (*jp->p == 'e' || *jp->p == 'E')) {
    jp->p++;
    if (jp->p < jp->end && (*jp->p == '+' || *jp->p == '-')) {
      jp->p++;
    }
    while (jp->p < jp->end && isdigit((unsigned char)*jp->p)) {
      jp->p++;
    }
  }
  size_t n = (size_t)(jp->p - start);
  char* tmp = (char*)xmalloc(n + 1);
  memcpy(tmp, start, n);
  tmp[n] = '\0';
  double d = strtod(tmp, NULL);
  free(tmp);
  return jv_num(d);
}

static bool jp_lit(jparser* jp, const char* word) {
  size_t n = strlen(word);
  if ((size_t)(jp->end - jp->p) < n || strncmp(jp->p, word, n) != 0) {
    return false;
  }
  jp->p += n;
  return true;
}

static jvalue* jp_array(jparser* jp) {
  jp->p++; /* '[' */
  jvalue* a = jv_new(JV_ARR);
  jp_skip_ws(jp);
  if (jp->p < jp->end && *jp->p == ']') {
    jp->p++;
    return a;
  }
  for (;;) {
    jp_skip_ws(jp);
    jvalue* item = jp_value(jp);
    if (jp->err) {
      return a;
    }
    jv_arr_push(a, item);
    jp_skip_ws(jp);
    if (jp->p >= jp->end) {
      jp->err = true;
      return a;
    }
    if (*jp->p == ',') {
      jp->p++;
      continue;
    }
    if (*jp->p == ']') {
      jp->p++;
      return a;
    }
    jp->err = true;
    return a;
  }
}

static jvalue* jp_object(jparser* jp) {
  jp->p++; /* '{' */
  jvalue* o = jv_new(JV_OBJ);
  jp_skip_ws(jp);
  if (jp->p < jp->end && *jp->p == '}') {
    jp->p++;
    return o;
  }
  for (;;) {
    jp_skip_ws(jp);
    if (jp->p >= jp->end || *jp->p != '"') {
      jp->err = true;
      return o;
    }
    char* key = jp_string_raw(jp);
    if (jp->err) {
      return o;
    }
    jp_skip_ws(jp);
    if (jp->p >= jp->end || *jp->p != ':') {
      jp->err = true;
      return o;
    }
    jp->p++; /* ':' */
    jp_skip_ws(jp);
    jvalue* val = jp_value(jp);
    if (jp->err) {
      return o;
    }
    jv_obj_put(o, key, val);
    jp_skip_ws(jp);
    if (jp->p >= jp->end) {
      jp->err = true;
      return o;
    }
    if (*jp->p == ',') {
      jp->p++;
      continue;
    }
    if (*jp->p == '}') {
      jp->p++;
      return o;
    }
    jp->err = true;
    return o;
  }
}

static jvalue* jp_value(jparser* jp) {
  jp_skip_ws(jp);
  if (jp->p >= jp->end) {
    jp->err = true;
    return jv_null();
  }
  char c = *jp->p;
  switch (c) {
    case '{': return jp_object(jp);
    case '[': return jp_array(jp);
    case '"': {
      char* s = jp_string_raw(jp);
      if (jp->err) {
        return jv_null();
      }
      return jv_str_owned(s);
    }
    case 't':
      if (jp_lit(jp, "true")) {
        return jv_bool(true);
      }
      jp->err = true;
      return jv_null();
    case 'f':
      if (jp_lit(jp, "false")) {
        return jv_bool(false);
      }
      jp->err = true;
      return jv_null();
    case 'n':
      if (jp_lit(jp, "null")) {
        return jv_null();
      }
      jp->err = true;
      return jv_null();
    default:
      if (c == '-' || isdigit((unsigned char)c)) {
        return jp_number(jp);
      }
      jp->err = true;
      return jv_null();
  }
}

jvalue* jv_parse(const char* text) {
  jparser jp;
  jp.p = text;
  jp.end = text + strlen(text);
  jp.err = false;
  jvalue* v = jp_value(&jp);
  if (jp.err) {
    return NULL;
  }
  jp_skip_ws(&jp);
  /* trailing junk is tolerated leniently for prototype robustness */
  return v;
}

jvalue* jv_parse_file(const char* path) {
  FILE* f = fopen(path, "rb");
  if (!f) {
    return NULL;
  }
  if (fseek(f, 0, SEEK_END) != 0) {
    fclose(f);
    return NULL;
  }
  long sz = ftell(f);
  if (sz < 0) {
    fclose(f);
    return NULL;
  }
  rewind(f);
  char* buf = (char*)xmalloc((size_t)sz + 1);
  size_t rd = fread(buf, 1, (size_t)sz, f);
  fclose(f);
  buf[rd] = '\0';
  jvalue* v = jv_parse(buf);
  free(buf);
  return v;
}

/* ─── compact JSON serialization ───────────────────────────────────────────*/

typedef struct {
  char* buf;
  size_t len;
  size_t cap;
} sbuf;

static void sb_putc(sbuf* sb, char c) {
  if (sb->len + 1 > sb->cap) {
    size_t nc = sb->cap ? sb->cap * 2 : 32;
    sb->buf = (char*)xrealloc(sb->buf, nc);
    sb->cap = nc;
  }
  sb->buf[sb->len++] = c;
}

static void sb_puts(sbuf* sb, const char* s) {
  for (; *s; s++) {
    sb_putc(sb, *s);
  }
}

static void sb_json_str(sbuf* sb, const char* s) {
  sb_putc(sb, '"');
  for (const unsigned char* p = (const unsigned char*)s; *p; p++) {
    unsigned char c = *p;
    switch (c) {
      case '"': sb_puts(sb, "\\\""); break;
      case '\\': sb_puts(sb, "\\\\"); break;
      case '\b': sb_puts(sb, "\\b"); break;
      case '\f': sb_puts(sb, "\\f"); break;
      case '\n': sb_puts(sb, "\\n"); break;
      case '\r': sb_puts(sb, "\\r"); break;
      case '\t': sb_puts(sb, "\\t"); break;
      default:
        if (c < 0x20) {
          char tmp[8];
          snprintf(tmp, sizeof(tmp), "\\u%04x", c);
          sb_puts(sb, tmp);
        } else {
          sb_putc(sb, (char)c);
        }
    }
  }
  sb_putc(sb, '"');
}

/* Render a number the way JS JSON.stringify would for these corpus values:
 * integers without a decimal point, otherwise %g-ish. */
static void sb_json_num(sbuf* sb, double n) {
  char tmp[64];
  if (n == (double)(long long)n && n >= -9.007199254740992e15 &&
      n <= 9.007199254740992e15) {
    snprintf(tmp, sizeof(tmp), "%lld", (long long)n);
  } else {
    snprintf(tmp, sizeof(tmp), "%.17g", n);
  }
  sb_puts(sb, tmp);
}

static void sb_json(sbuf* sb, const jvalue* v) {
  if (!v) {
    sb_puts(sb, "null");
    return;
  }
  switch (v->type) {
    case JV_NULL: sb_puts(sb, "null"); break;
    case JV_BOOL: sb_puts(sb, v->as.b ? "true" : "false"); break;
    case JV_NUM: sb_json_num(sb, v->as.n); break;
    case JV_STR: sb_json_str(sb, v->as.s); break;
    case JV_ARR:
      sb_putc(sb, '[');
      for (size_t i = 0; i < v->as.arr.len; i++) {
        if (i) {
          sb_putc(sb, ',');
        }
        sb_json(sb, v->as.arr.items[i]);
      }
      sb_putc(sb, ']');
      break;
    case JV_OBJ:
      sb_putc(sb, '{');
      for (size_t i = 0; i < v->as.obj.len; i++) {
        if (i) {
          sb_putc(sb, ',');
        }
        sb_json_str(sb, v->as.obj.keys[i]);
        sb_putc(sb, ':');
        sb_json(sb, v->as.obj.vals[i]);
      }
      sb_putc(sb, '}');
      break;
  }
}

char* jv_stringify(const jvalue* v) {
  sbuf sb = {0};
  sb_json(&sb, v);
  sb_putc(&sb, '\0');
  return sb.buf;
}

/* ─── Provider ─────────────────────────────────────────────────────────────*/

struct Provider {
  jvalue* spec;
};

/* The root holding functions: spec.struct if present, else spec. */
static jvalue* prov_root(Provider* p) {
  jvalue* root = jv_obj_get(p->spec, "struct");
  return root ? root : p->spec;
}

static bool is_group_bag(const jvalue* v) {
  if (!v || v->type != JV_OBJ) {
    return false;
  }
  jvalue* set = jv_obj_get(v, "set");
  return set && set->type == JV_ARR;
}

static bool has_groups(const jvalue* v) {
  if (!v || v->type != JV_OBJ) {
    return false;
  }
  for (size_t i = 0; i < v->as.obj.len; i++) {
    if (strcmp(v->as.obj.keys[i], "name") != 0 && is_group_bag(v->as.obj.vals[i])) {
      return true;
    }
  }
  return false;
}

static jvalue* fn_node(Provider* p, const char* fn) {
  jvalue* root = jv_obj_get(p->spec, "struct");
  jvalue* node = NULL;
  if (root) {
    node = jv_obj_get(root, fn);
  }
  if (!node) {
    node = jv_obj_get(p->spec, fn);
  }
  return node;
}

Provider* provider_load(const char* path) {
  const char* file = path ? path : "build/test/test.json";
  jvalue* spec = jv_parse_file(file);
  if (!spec) {
    return NULL;
  }
  Provider* p = (Provider*)xmalloc(sizeof(Provider));
  p->spec = spec;
  return p;
}

jvalue* provider_raw(Provider* p) { return p->spec; }

const char** provider_functions(Provider* p, size_t* out_len) {
  jvalue* root = prov_root(p);
  const char** out = (const char**)xmalloc(root->as.obj.len * sizeof(char*));
  size_t n = 0;
  for (size_t i = 0; i < root->as.obj.len; i++) {
    jvalue* v = root->as.obj.vals[i];
    if (is_group_bag(v) || has_groups(v)) {
      out[n++] = root->as.obj.keys[i];
    }
  }
  *out_len = n;
  return out;
}

const char** provider_groups(Provider* p, const char* fn, size_t* out_len) {
  jvalue* node = fn_node(p, fn);
  if (!node || node->type != JV_OBJ) {
    *out_len = 0;
    return NULL;
  }
  const char** out = (const char**)xmalloc(node->as.obj.len * sizeof(char*));
  size_t n = 0;
  for (size_t i = 0; i < node->as.obj.len; i++) {
    if (strcmp(node->as.obj.keys[i], "name") != 0 && is_group_bag(node->as.obj.vals[i])) {
      out[n++] = node->as.obj.keys[i];
    }
  }
  *out_len = n;
  return out;
}

static ErrorCheck parse_err(const jvalue* err) {
  ErrorCheck ec = {true, NULL, false};
  if (err && err->type == JV_BOOL && err->as.b) {
    ec.any = true;
    ec.text = NULL;
    ec.regex = false;
    return ec;
  }
  if (err && err->type == JV_STR) {
    const char* s = err->as.s;
    size_t len = strlen(s);
    /* /re/  matches ^/(.+)/$ */
    if (len >= 3 && s[0] == '/' && s[len - 1] == '/') {
      ec.any = false;
      ec.regex = true;
      size_t inner = len - 2;
      char* t = (char*)xmalloc(inner + 1);
      memcpy(t, s + 1, inner);
      t[inner] = '\0';
      ec.text = t;
      return ec;
    }
    ec.any = false;
    ec.regex = false;
    ec.text = xstrdup(s);
    return ec;
  }
  /* non-true, non-string err spec: treat as "any error" */
  ec.any = true;
  ec.text = NULL;
  ec.regex = false;
  return ec;
}

static Input resolve_input(const jvalue* raw) {
  Input in;
  memset(&in, 0, sizeof(in));
  if (jv_obj_has(raw, "ctx")) {
    in.kind = IN_CTX;
    in.ctx = jv_obj_get(raw, "ctx");
    return in;
  }
  if (jv_obj_has(raw, "args")) {
    in.kind = IN_ARGS;
    in.args = jv_obj_get(raw, "args");
    return in;
  }
  in.kind = IN_IN;
  in.in = jv_obj_has(raw, "in") ? jv_obj_get(raw, "in") : jv_null();
  return in;
}

static Expect resolve_expect(const jvalue* raw) {
  Expect ex;
  memset(&ex, 0, sizeof(ex));
  jvalue* match_part = jv_obj_has(raw, "match") ? jv_obj_get(raw, "match") : NULL;
  if (jv_obj_has(raw, "err")) {
    ex.kind = EX_ERROR;
    ex.error = parse_err(jv_obj_get(raw, "err"));
    ex.match = match_part;
    return ex;
  }
  if (jv_obj_has(raw, "out")) {
    ex.kind = EX_VALUE;
    ex.value = jv_obj_get(raw, "out");
    ex.match = match_part;
    return ex;
  }
  if (jv_obj_has(raw, "match")) {
    ex.kind = EX_MATCH;
    ex.match = jv_obj_get(raw, "match");
    return ex;
  }
  ex.kind = EX_ABSENT;
  return ex;
}

static const char* group_client(Provider* p, const char* fn, const char* group);

static Entry normalize_entry(Provider* p, const char* fn, const char* group, int index,
                             jvalue* raw) {
  Entry e;
  memset(&e, 0, sizeof(e));
  e.function = fn;
  e.group = group;
  e.index = index;
  jvalue* idv = jv_obj_get(raw, "id");
  e.id = (idv && idv->type == JV_STR) ? xstrdup(idv->as.s)
       : (idv && idv->type != JV_NULL) ? jv_stringify(idv)
       : NULL;
  jvalue* docv = jv_obj_get(raw, "doc");
  e.doc = (docv && docv->type == JV_BOOL && docv->as.b);
  jvalue* clientv = jv_obj_get(raw, "client");
  e.client = (clientv && clientv->type == JV_STR) ? xstrdup(clientv->as.s)
           : (clientv && clientv->type != JV_NULL) ? jv_stringify(clientv)
           : NULL;
  /* If the entry itself names no client, fall back to the group's DEF.client. */
  if (!e.client) {
    const char* gc = group_client(p, fn, group);
    if (gc) {
      e.client = xstrdup(gc);
    }
  }
  e.input = resolve_input(raw);
  e.expect = resolve_expect(raw);
  e.raw = raw;
  return e;
}

/* The named client from the group's DEF.client (or NULL). */
static const char* group_client(Provider* p, const char* fn, const char* group) {
  jvalue* node = fn_node(p, fn);
  if (!node) {
    return NULL;
  }
  jvalue* bag = jv_obj_get(node, group);
  if (!bag || bag->type != JV_OBJ) {
    return NULL;
  }
  jvalue* def = jv_obj_get(bag, "DEF");
  if (!def || def->type != JV_OBJ) {
    return NULL;
  }
  jvalue* client = jv_obj_get(def, "client");
  if (client && client->type == JV_STR) {
    return client->as.s;
  }
  return NULL;
}

Entry* provider_entries(Provider* p, const char* fn, const char* group, size_t* out_len) {
  jvalue* node = fn_node(p, fn);
  if (!node || node->type != JV_OBJ) {
    *out_len = 0;
    return NULL;
  }
  size_t ng = 0;
  const char** groups;
  if (group) {
    static const char* one[1];
    one[0] = group;
    groups = one;
    ng = 1;
  } else {
    groups = provider_groups(p, fn, &ng);
  }
  Entry* out = NULL;
  size_t len = 0, cap = 0;
  for (size_t gi = 0; gi < ng; gi++) {
    jvalue* bag = jv_obj_get(node, groups[gi]);
    if (!is_group_bag(bag)) {
      continue;
    }
    jvalue* set = jv_obj_get(bag, "set");
    for (size_t i = 0; i < set->as.arr.len; i++) {
      if (len + 1 > cap) {
        cap = cap ? cap * 2 : 16;
        out = (Entry*)xrealloc(out, cap * sizeof(Entry));
      }
      out[len++] = normalize_entry(p, fn, groups[gi], (int)i, set->as.arr.items[i]);
    }
  }
  *out_len = len;
  return out;
}

/* ─── pure comparison helpers ──────────────────────────────────────────────*/

char* provider_stringify(const jvalue* x) {
  if (x && x->type == JV_STR) {
    return xstrdup(x->as.s);
  }
  return jv_stringify(x);
}

static bool jv_shallow_eq(const jvalue* a, const jvalue* b) {
  /* identity-ish equality for scalars (mirrors === for primitives) */
  if (a == b) {
    return true;
  }
  if (!a || !b) {
    return false;
  }
  if (a->type != b->type) {
    return false;
  }
  switch (a->type) {
    case JV_NULL: return true;
    case JV_BOOL: return a->as.b == b->as.b;
    case JV_NUM: return a->as.n == b->as.n;
    case JV_STR: return strcmp(a->as.s, b->as.s) == 0;
    default: return false; /* arrays/objects are never === */
  }
}

/* normNull / normMark: produce a normalized copy. We don't materialize a copy;
 * instead deep_eq carries a flag for how to treat the NULLMARK string and
 * (lenient only) treat null/missing uniformly. Simpler: implement equality
 * with normalization inline. */

static bool is_nullmark(const jvalue* v) {
  return v && v->type == JV_STR && strcmp(v->as.s, NULLMARK) == 0;
}

/* lenient: NULLMARK and null collapse to the same nullish.
 * strict: only NULLMARK -> null; (undefined != null, but our model has no
 * "undefined" — absent keys already became jv_null in resolve_input, and the
 * corpus expectation values come straight from JSON, so strict simply does not
 * collapse a real null against a NULLMARK string differently from lenient here;
 * the meaningful distinction strict draws is that it does NOT treat a missing
 * key as null. In this value model both are represented, so strict == lenient
 * for materialized values except we keep the NULLMARK normalization.) */

static bool deep_eq(const jvalue* a, const jvalue* b, bool lenient) {
  /* Normalize NULLMARK->null (both modes) and, in lenient mode, null/absent. */
  bool an = is_nullmark(a) || (lenient && (!a || (a && a->type == JV_NULL)));
  bool bn = is_nullmark(b) || (lenient && (!b || (b && b->type == JV_NULL)));
  if (an || bn) {
    /* In strict mode a JV_NULL is itself; treat as null only via NULLMARK. */
    if (lenient) {
      return an == bn;
    }
    /* strict: NULLMARK normalizes to null; compare normalized nullness */
    bool a_null = is_nullmark(a) || (a && a->type == JV_NULL);
    bool b_null = is_nullmark(b) || (b && b->type == JV_NULL);
    if (a_null || b_null) {
      return a_null == b_null;
    }
  }
  if (!a || !b) {
    return a == b;
  }
  if (a->type != b->type) {
    return false;
  }
  switch (a->type) {
    case JV_NULL: return true;
    case JV_BOOL: return a->as.b == b->as.b;
    case JV_NUM: return a->as.n == b->as.n;
    case JV_STR: return strcmp(a->as.s, b->as.s) == 0;
    case JV_ARR: {
      if (a->as.arr.len != b->as.arr.len) {
        return false;
      }
      for (size_t i = 0; i < a->as.arr.len; i++) {
        if (!deep_eq(a->as.arr.items[i], b->as.arr.items[i], lenient)) {
          return false;
        }
      }
      return true;
    }
    case JV_OBJ: {
      if (a->as.obj.len != b->as.obj.len) {
        return false;
      }
      for (size_t i = 0; i < a->as.obj.len; i++) {
        jvalue* bv = jv_obj_get(b, a->as.obj.keys[i]);
        if (!jv_obj_has(b, a->as.obj.keys[i])) {
          return false;
        }
        if (!deep_eq(a->as.obj.vals[i], bv, lenient)) {
          return false;
        }
      }
      return true;
    }
  }
  return false;
}

bool equal(const jvalue* expected, const jvalue* actual) {
  return deep_eq(expected, actual, true);
}

bool equal_strict(const jvalue* expected, const jvalue* actual) {
  return deep_eq(expected, actual, false);
}

bool matchval(const jvalue* check, const jvalue* base) {
  if (jv_shallow_eq(check, base)) {
    return true;
  }
  if (check && check->type == JV_STR) {
    char* basestr = provider_stringify(base);
    const char* cs = check->as.s;
    size_t clen = strlen(cs);
    bool result;
    if (clen >= 3 && cs[0] == '/' && cs[clen - 1] == '/') {
      /* /re/ */
      size_t inner = clen - 2;
      char* re = (char*)xmalloc(inner + 1);
      memcpy(re, cs + 1, inner);
      re[inner] = '\0';
      regex_t rx;
      if (regcomp(&rx, re, REG_EXTENDED) == 0) {
        result = (regexec(&rx, basestr, 0, NULL, 0) == 0);
        regfree(&rx);
      } else {
        result = false;
      }
      free(re);
    } else {
      /* case-insensitive substring */
      char* lb = xstrdup(basestr);
      char* lc = xstrdup(cs);
      for (char* q = lb; *q; q++) {
        *q = (char)tolower((unsigned char)*q);
      }
      for (char* q = lc; *q; q++) {
        *q = (char)tolower((unsigned char)*q);
      }
      result = (strstr(lb, lc) != NULL);
      free(lb);
      free(lc);
    }
    free(basestr);
    return result;
  }
  /* check is a function -> true; we have no function values, so false. */
  return false;
}

bool error_matches(const ErrorCheck* check, const char* message) {
  if (check->any) {
    return true;
  }
  if (!check->text) {
    return false;
  }
  if (!message) {
    message = "";
  }
  if (check->regex) {
    regex_t rx;
    if (regcomp(&rx, check->text, REG_EXTENDED) != 0) {
      return false;
    }
    bool m = (regexec(&rx, message, 0, NULL, 0) == 0);
    regfree(&rx);
    return m;
  }
  char* lm = xstrdup(message);
  char* lt = xstrdup(check->text);
  for (char* q = lm; *q; q++) {
    *q = (char)tolower((unsigned char)*q);
  }
  for (char* q = lt; *q; q++) {
    *q = (char)tolower((unsigned char)*q);
  }
  bool m = (strstr(lm, lt) != NULL);
  free(lm);
  free(lt);
  return m;
}

/* getpath over the jvalue model; returns NULL if absent. */
static jvalue* jv_getpath(jvalue* store, char** path, size_t plen) {
  jvalue* cur = store;
  for (size_t i = 0; i < plen; i++) {
    if (!cur) {
      return NULL;
    }
    if (cur->type == JV_ARR) {
      char* endp = NULL;
      long idx = strtol(path[i], &endp, 10);
      if (endp == path[i] || idx < 0 || (size_t)idx >= cur->as.arr.len) {
        return NULL;
      }
      cur = cur->as.arr.items[idx];
    } else if (cur->type == JV_OBJ) {
      cur = jv_obj_get(cur, path[i]);
    } else {
      return NULL;
    }
  }
  return cur;
}

static bool jv_is_node(const jvalue* v) {
  return v && (v->type == JV_OBJ || v->type == JV_ARR);
}

typedef struct {
  bool ok;
  char** path;
  size_t path_len;
  jvalue* expected;
  jvalue* actual;
} sm_state;

static void walk_leaves(jvalue* node, char** path, size_t plen, jvalue* base, sm_state* st);

static void sm_check_leaf(jvalue* val, char** path, size_t plen, jvalue* base, sm_state* st) {
  if (!st->ok) {
    return;
  }
  jvalue* baseval = jv_getpath(base, path, plen);
  if (jv_shallow_eq(val, baseval)) {
    return;
  }
  if (val && val->type == JV_STR && strcmp(val->as.s, UNDEFMARK) == 0 && baseval == NULL) {
    return;
  }
  if (val && val->type == JV_STR && strcmp(val->as.s, EXISTSMARK) == 0 && baseval &&
      baseval->type != JV_NULL) {
    return;
  }
  if (!matchval(val, baseval)) {
    st->ok = false;
    /* copy the path */
    char** pc = (char**)xmalloc((plen ? plen : 1) * sizeof(char*));
    for (size_t i = 0; i < plen; i++) {
      pc[i] = xstrdup(path[i]);
    }
    st->path = pc;
    st->path_len = plen;
    st->expected = val;
    st->actual = baseval;
  }
}

static void walk_leaves(jvalue* node, char** path, size_t plen, jvalue* base, sm_state* st) {
  if (!st->ok) {
    return;
  }
  if (node && node->type == JV_ARR) {
    for (size_t i = 0; i < node->as.arr.len; i++) {
      char idxbuf[32];
      snprintf(idxbuf, sizeof(idxbuf), "%zu", i);
      char** np = (char**)xmalloc((plen + 1) * sizeof(char*));
      for (size_t k = 0; k < plen; k++) {
        np[k] = path[k];
      }
      np[plen] = idxbuf;
      walk_leaves(node->as.arr.items[i], np, plen + 1, base, st);
      free(np);
    }
  } else if (jv_is_node(node)) {
    for (size_t i = 0; i < node->as.obj.len; i++) {
      char** np = (char**)xmalloc((plen + 1) * sizeof(char*));
      for (size_t k = 0; k < plen; k++) {
        np[k] = path[k];
      }
      np[plen] = node->as.obj.keys[i];
      walk_leaves(node->as.obj.vals[i], np, plen + 1, base, st);
      free(np);
    }
  } else {
    sm_check_leaf(node, path, plen, base, st);
  }
}

MatchResult struct_match(const jvalue* check, const jvalue* base) {
  sm_state st;
  memset(&st, 0, sizeof(st));
  st.ok = true;
  walk_leaves((jvalue*)check, NULL, 0, (jvalue*)base, &st);
  MatchResult r;
  r.ok = st.ok;
  r.path = st.path;
  r.path_len = st.path_len;
  r.expected = st.expected;
  r.actual = st.actual;
  return r;
}

#endif /* PROVIDER_IMPL */
