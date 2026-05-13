/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
 *
 * Minor utilities and helpers, plus walk/merge/getpath/setpath.
 * The inject / transform / validate / select machinery lives in inject.c.
 */

#include "voxgig_struct.h"

#include <ctype.h>
#include <limits.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ===========================================================================
 * Static helpers
 * ===========================================================================*/

static char* xstrdup_s(const char* s) {
  if (!s)
    s = "";
  size_t n = strlen(s);
  char* o = (char*)malloc(n + 1);
  if (!o)
    abort();
  memcpy(o, s, n + 1);
  return o;
}

static char* xstrndup_s(const char* s, size_t n) {
  char* o = (char*)malloc(n + 1);
  if (!o)
    abort();
  if (n)
    memcpy(o, s, n);
  o[n] = '\0';
  return o;
}

/* "intdup" — format int as string. Caller must free. */
static char* intstr(int64_t v) {
  char buf[32];
  snprintf(buf, sizeof(buf), "%lld", (long long)v);
  return xstrdup_s(buf);
}

/* doublestr: format double, removing trailing zeros. */
static char* doublestr(double v) {
  char buf[64];
  /* Use %g for compact representation. */
  if (isnan(v)) {
    return xstrdup_s("null");
  }
  if (isinf(v)) {
    return xstrdup_s(v < 0 ? "-Infinity" : "Infinity");
  }
  if (floor(v) == v && fabs(v) < 1e15) {
    snprintf(buf, sizeof(buf), "%lld", (long long)v);
  } else {
    snprintf(buf, sizeof(buf), "%g", v);
  }
  return xstrdup_s(buf);
}

/* parseInt-style: returns true if the string represents an integer (possibly
 * with leading sign). Outputs the integer in *out.
 */
static bool parse_intstr(const char* s, size_t n, int64_t* out) {
  if (!s || n == 0)
    return false;
  size_t i = 0;
  int sign = 1;
  if (s[0] == '-') {
    sign = -1;
    i = 1;
  } else if (s[0] == '+') {
    i = 1;
  }
  if (i >= n)
    return false;
  int64_t v = 0;
  for (; i < n; i++) {
    if (s[i] < '0' || s[i] > '9')
      return false;
    v = v * 10 + (s[i] - '0');
  }
  *out = sign * v;
  return true;
}

/* R_INTEGER_KEY: ^[-0-9]+$ — goes through the vendored regex engine so the
   call sites read the same as the canonical TS. */
static vs_regex* R_INTEGER_KEY_re(void) {
  static vs_regex* re = NULL;
  if (!re)
    re = vs_re_compile("^[-0-9]+$");
  return re;
}
static bool match_integer_key(const char* s, size_t n) {
  if (!s || n == 0)
    return false;
  char buf[64];
  char* tmp = NULL;
  const char* z;
  if (n < sizeof(buf)) {
    memcpy(buf, s, n);
    buf[n] = '\0';
    z = buf;
  } else {
    tmp = (char*)malloc(n + 1);
    memcpy(tmp, s, n);
    tmp[n] = '\0';
    z = tmp;
  }
  bool ok = vs_re_test_re(R_INTEGER_KEY_re(), z);
  free(tmp);
  return ok;
}

/* ===========================================================================
 * String vector
 * ===========================================================================*/

void vs_strvec_init(vs_strvec* v) {
  v->len = 0;
  v->cap = 0;
  v->data = NULL;
}

void vs_strvec_free(vs_strvec* v) {
  if (!v)
    return;
  for (size_t i = 0; i < v->len; i++)
    free(v->data[i]);
  free(v->data);
  v->data = NULL;
  v->len = 0;
  v->cap = 0;
}

void vs_strvec_clear(vs_strvec* v) {
  for (size_t i = 0; i < v->len; i++)
    free(v->data[i]);
  v->len = 0;
}

static void strvec_reserve(vs_strvec* v, size_t need) {
  if (v->cap >= need)
    return;
  size_t nc = v->cap == 0 ? 8 : v->cap;
  while (nc < need)
    nc *= 2;
  char** nd = (char**)realloc(v->data, nc * sizeof(char*));
  if (!nd)
    abort();
  v->data = nd;
  v->cap = nc;
}

void vs_strvec_push(vs_strvec* v, const char* s) {
  vs_strvec_push_n(v, s, s ? strlen(s) : 0);
}

void vs_strvec_push_n(vs_strvec* v, const char* s, size_t n) {
  strvec_reserve(v, v->len + 1);
  v->data[v->len++] = xstrndup_s(s ? s : "", n);
}

void vs_strvec_resize(vs_strvec* v, size_t n) {
  if (n < v->len) {
    for (size_t i = n; i < v->len; i++)
      free(v->data[i]);
    v->len = n;
    return;
  }
  if (n > v->len) {
    strvec_reserve(v, n);
    for (size_t i = v->len; i < n; i++)
      v->data[i] = xstrdup_s("");
    v->len = n;
  }
}

void vs_strvec_set(vs_strvec* v, size_t i, const char* s) {
  if (i >= v->len)
    vs_strvec_resize(v, i + 1);
  free(v->data[i]);
  v->data[i] = xstrdup_s(s ? s : "");
}

void vs_strvec_copy(vs_strvec* dst, const vs_strvec* src) {
  vs_strvec_clear(dst);
  for (size_t i = 0; i < src->len; i++)
    vs_strvec_push(dst, src->data[i]);
}

/* ===========================================================================
 * Type-name table (matches TS TYPENAME).
 * ===========================================================================*/

static const char* TYPENAME_TABLE[26] = {
    "any",  "nil",      "boolean", "decimal", "integer", "number", "string", "function", "symbol",
    "null", "",         "",        "",        "",        "",       "",       "",         "list",
    "map",  "instance", "",        "",        "",        "",       "scalar", "node",
};

static int clz32(uint32_t x) {
  if (x == 0)
    return 32;
  int n = 0;
  while ((x & 0x80000000u) == 0) {
    n++;
    x <<= 1;
  }
  return n;
}

const char* vs_typename(int t) {
  int idx = clz32((uint32_t)t);
  if (idx < 0 || idx >= 26)
    return "any";
  const char* s = TYPENAME_TABLE[idx];
  return (s && *s) ? s : "any";
}

/* ===========================================================================
 * typify
 * ===========================================================================*/

int vs_typify(const vs_value* v) {
  if (!v || vs_is_undef(v))
    return VS_T_NOVAL;
  if (vs_is_null(v))
    return VS_T_SCALAR | VS_T_NULL;
  if (vs_is_bool(v))
    return VS_T_SCALAR | VS_T_BOOLEAN;
  if (vs_is_int(v))
    return VS_T_SCALAR | VS_T_NUMBER | VS_T_INTEGER;
  if (vs_is_double(v)) {
    double d = vs_as_double(v);
    if (isnan(d))
      return VS_T_NOVAL;
    return VS_T_SCALAR | VS_T_NUMBER | VS_T_DECIMAL;
  }
  if (vs_is_string(v))
    return VS_T_SCALAR | VS_T_STRING;
  if (vs_is_list(v))
    return VS_T_NODE | VS_T_LIST;
  if (vs_is_map(v))
    return VS_T_NODE | VS_T_MAP;
  if (vs_is_func(v))
    return VS_T_SCALAR | VS_T_FUNCTION;
  if (vs_is_sentinel(v))
    return VS_T_NODE | VS_T_MAP;
  return VS_T_ANY;
}

/* ===========================================================================
 * Predicates (vs_*)
 * ===========================================================================*/

bool vs_isnode(const vs_value* v) {
  return vs_is_node(v);
}
bool vs_ismap(const vs_value* v) {
  return vs_is_map(v);
}
bool vs_islist(const vs_value* v) {
  return vs_is_list(v);
}

bool vs_iskey(const vs_value* v) {
  if (vs_is_string(v))
    return vs_string_len(v) > 0;
  return vs_is_int(v) || vs_is_double(v);
}

bool vs_isempty(const vs_value* v) {
  if (!v || vs_is_undef(v) || vs_is_null(v))
    return true;
  if (vs_is_string(v))
    return vs_string_len(v) == 0;
  if (vs_is_list(v))
    return vs_list_len(vs_as_list(v)) == 0;
  if (vs_is_map(v))
    return vs_map_len(vs_as_map(v)) == 0;
  return false;
}

bool vs_isfunc(const vs_value* v) {
  return vs_is_func(v);
}

/* ===========================================================================
 * getdef
 * ===========================================================================*/

vs_value* vs_getdef(vs_value* val, vs_value* alt) {
  if (!val || vs_is_undef(val))
    return alt ? vs_retain(alt) : vs_new_undef();
  return vs_retain(val);
}

/* ===========================================================================
 * size
 * ===========================================================================*/

int64_t vs_size(const vs_value* v) {
  if (!v)
    return 0;
  if (vs_is_list(v))
    return (int64_t)vs_list_len(vs_as_list(v));
  if (vs_is_map(v))
    return (int64_t)vs_map_len(vs_as_map(v));
  if (vs_is_string(v))
    return (int64_t)vs_string_len(v);
  if (vs_is_int(v))
    return (int64_t)floor((double)vs_as_int(v));
  if (vs_is_double(v))
    return (int64_t)floor(vs_as_double(v));
  if (vs_is_bool(v))
    return vs_as_bool(v) ? 1 : 0;
  return 0;
}

/* ===========================================================================
 * slice
 * ===========================================================================*/

vs_value* vs_slice(vs_value* v, vs_value* start, vs_value* end, bool mutate) {
  if (vs_is_number(v)) {
    int64_t s = (vs_is_int(start) || vs_is_double(start)) ? vs_as_int(start) : INT64_MIN / 2;
    int64_t e = (vs_is_int(end) || vs_is_double(end)) ? vs_as_int(end) : INT64_MAX / 2;
    e -= 1;
    int64_t val = vs_as_int(v);
    if (val < s)
      val = s;
    if (val > e)
      val = e;
    return vs_new_int(val);
  }

  int64_t vlen = vs_size(v);
  bool has_start = (start != NULL && !vs_is_undef(start));
  bool has_end = (end != NULL && !vs_is_undef(end));

  int64_t s = has_start ? vs_as_int(start) : -1;
  int64_t e = has_end ? vs_as_int(end) : -1;

  if (has_end && !has_start) {
    s = 0;
    has_start = true;
  }

  if (!has_start) {
    /* No start: return as-is (deep clone for safety since canonical returns input). */
    if (vs_is_string(v))
      return vs_new_string_n(vs_as_string(v), vs_string_len(v));
    if (vs_is_list(v))
      return vs_clone(v);
    return vs_retain(v);
  }

  if (s < 0) {
    e = vlen + s;
    if (e < 0)
      e = 0;
    s = 0;
  } else if (has_end) {
    if (e < 0) {
      e = vlen + e;
      if (e < 0)
        e = 0;
    } else if (vlen < e) {
      e = vlen;
    }
  } else {
    e = vlen;
  }

  if (vlen < s)
    s = vlen;

  if (s >= 0 && s <= e && e <= vlen) {
    if (vs_is_list(v)) {
      vs_list* src = vs_as_list(v);
      if (mutate) {
        for (int64_t i = 0, j = s; j < e; i++, j++) {
          vs_value* old = src->items[i];
          src->items[i] = vs_retain(src->items[j]);
          vs_release(old);
        }
        for (int64_t i = (int64_t)src->len - 1; i >= e - s; i--) {
          vs_release(src->items[i]);
        }
        src->len = (size_t)(e - s);
        return vs_retain(v);
      }
      vs_value* out = vs_new_list();
      for (int64_t i = s; i < e; i++) {
        vs_list_push(vs_as_list(out), vs_clone(vs_list_get(src, (size_t)i)));
      }
      return out;
    }
    if (vs_is_string(v)) {
      return vs_new_string_n(vs_as_string(v) + s, (size_t)(e - s));
    }
  } else {
    if (vs_is_list(v)) {
      if (mutate) {
        vs_list_clear(vs_as_list(v));
        return vs_retain(v);
      }
      return vs_new_list();
    }
    if (vs_is_string(v)) {
      return vs_new_string("");
    }
  }
  return vs_retain(v);
}

/* ===========================================================================
 * strkey
 * ===========================================================================*/

char* vs_strkey(vs_value* key) {
  if (!key || vs_is_undef(key))
    return xstrdup_s("");
  int t = vs_typify(key);
  if (t & VS_T_STRING)
    return xstrdup_s(vs_as_string(key));
  if (t & VS_T_BOOLEAN)
    return xstrdup_s("");
  if (t & VS_T_NUMBER) {
    if (vs_is_int(key)) {
      return intstr(vs_as_int(key));
    }
    double d = vs_as_double(key);
    if (d == floor(d))
      return intstr((int64_t)d);
    return intstr((int64_t)floor(d));
  }
  return xstrdup_s("");
}

/* ===========================================================================
 * keysof
 * ===========================================================================*/

static int qsort_str_cmp(const void* a, const void* b) {
  const char* sa = *(const char* const*)a;
  const char* sb = *(const char* const*)b;
  return strcmp(sa, sb);
}

vs_strvec vs_keysof(vs_value* val) {
  vs_strvec out;
  vs_strvec_init(&out);
  if (!vs_is_node(val))
    return out;
  if (vs_is_map(val)) {
    vs_map* m = vs_as_map(val);
    for (size_t i = 0; i < m->len; i++) {
      vs_strvec_push_n(&out, m->entries[i].key, m->entries[i].klen);
    }
    if (out.len > 1)
      qsort(out.data, out.len, sizeof(char*), qsort_str_cmp);
  } else {
    vs_list* l = vs_as_list(val);
    for (size_t i = 0; i < l->len; i++) {
      char* s = intstr((int64_t)i);
      vs_strvec_push(&out, s);
      free(s);
    }
  }
  return out;
}

/* ===========================================================================
 * getelem / getprop / haskey
 * ===========================================================================*/

vs_value* vs_getelem(vs_value* val, vs_value* key, vs_value* alt) {
  if (!val || vs_is_undef(val) || !key || vs_is_undef(key)) {
    return alt ? vs_retain(alt) : vs_new_undef();
  }
  if (vs_is_list(val)) {
    vs_list* l = vs_as_list(val);
    int64_t nk = 0;
    bool ok = false;
    if (vs_is_int(key)) {
      nk = vs_as_int(key);
      ok = true;
    } else if (vs_is_double(key)) {
      nk = (int64_t)vs_as_double(key);
      ok = true;
    } else if (vs_is_string(key)) {
      ok = match_integer_key(vs_as_string(key), vs_string_len(key)) &&
           parse_intstr(vs_as_string(key), vs_string_len(key), &nk);
    }
    if (!ok) {
      if (alt && vs_is_injector(alt)) {
        return alt->as.fn.fn.inj(NULL, alt, "", NULL, alt->as.fn.ud);
      }
      return alt ? vs_retain(alt) : vs_new_undef();
    }
    if (nk < 0)
      nk = (int64_t)l->len + nk;
    if (nk < 0 || nk >= (int64_t)l->len) {
      if (alt && vs_is_injector(alt)) {
        return alt->as.fn.fn.inj(NULL, alt, "", NULL, alt->as.fn.ud);
      }
      return alt ? vs_retain(alt) : vs_new_undef();
    }
    vs_value* v = vs_list_get(l, (size_t)nk);
    return v ? vs_retain(v) : (alt ? vs_retain(alt) : vs_new_undef());
  }
  if (alt && vs_is_injector(alt)) {
    return alt->as.fn.fn.inj(NULL, alt, "", NULL, alt->as.fn.ud);
  }
  return alt ? vs_retain(alt) : vs_new_undef();
}

vs_value* vs_getprop(vs_value* val, vs_value* key, vs_value* alt) {
  if (!val || vs_is_undef(val) || !key || vs_is_undef(key)) {
    return alt ? vs_retain(alt) : vs_new_undef();
  }
  if (vs_is_map(val)) {
    char* k = vs_strkey(key);
    vs_value* v = vs_map_get(vs_as_map(val), k);
    free(k);
    /* Group A: JSON null at the key is treated as "no value" — same rule as
       absent. Returns alt. Mirrors the canonical TS post-spec semantics. */
    if (v && !vs_is_undef(v) && !vs_is_null(v))
      return vs_retain(v);
    return alt ? vs_retain(alt) : vs_new_undef();
  }
  if (vs_is_list(val)) {
    vs_list* l = vs_as_list(val);
    int64_t nk = 0;
    if (vs_is_int(key)) {
      nk = vs_as_int(key);
    } else if (vs_is_double(key)) {
      nk = (int64_t)vs_as_double(key);
    } else if (vs_is_string(key)) {
      if (!match_integer_key(vs_as_string(key), vs_string_len(key)) ||
          !parse_intstr(vs_as_string(key), vs_string_len(key), &nk)) {
        return alt ? vs_retain(alt) : vs_new_undef();
      }
    } else {
      return alt ? vs_retain(alt) : vs_new_undef();
    }
    if (nk < 0 || nk >= (int64_t)l->len) {
      return alt ? vs_retain(alt) : vs_new_undef();
    }
    vs_value* v = vs_list_get(l, (size_t)nk);
    /* Group A: null at the slot also returns alt. */
    if (v && !vs_is_undef(v) && !vs_is_null(v))
      return vs_retain(v);
    return alt ? vs_retain(alt) : vs_new_undef();
  }
  return alt ? vs_retain(alt) : vs_new_undef();
}

bool vs_haskey(vs_value* val, vs_value* key) {
  vs_value* v = vs_getprop(val, key, NULL);
  /* Group A: null counts as "no value", same rule as getprop. */
  bool out = v && !vs_is_undef(v) && !vs_is_null(v);
  vs_release(v);
  return out;
}

/* Internal literal lookup. See header. */
vs_value* vs_lookup(vs_value* val, vs_value* key) {
  if (!val || vs_is_undef(val) || !key || vs_is_undef(key))
    return NULL;
  if (vs_is_map(val)) {
    char* k = vs_strkey(key);
    vs_value* v = vs_map_get(vs_as_map(val), k);
    free(k);
    return v;
  }
  if (vs_is_list(val)) {
    int64_t nk = 0;
    if (vs_is_int(key))
      nk = vs_as_int(key);
    else if (vs_is_double(key))
      nk = (int64_t)vs_as_double(key);
    else if (vs_is_string(key)) {
      if (!parse_intstr(vs_as_string(key), vs_string_len(key), &nk))
        return NULL;
    } else
      return NULL;
    vs_list* l = vs_as_list(val);
    if (nk < 0 || nk >= (int64_t)l->len)
      return NULL;
    return vs_list_get(l, (size_t)nk);
  }
  return NULL;
}

/* ===========================================================================
 * items_v: returns list of [key, value] tuples
 * ===========================================================================*/

vs_value* vs_items_v(vs_value* val) {
  vs_value* out = vs_new_list();
  if (!vs_is_node(val))
    return out;
  vs_strvec keys = vs_keysof(val);
  for (size_t i = 0; i < keys.len; i++) {
    vs_value* pair = vs_new_list();
    vs_list_push(vs_as_list(pair), vs_new_string(keys.data[i]));
    vs_value* keyv = vs_new_string(keys.data[i]);
    vs_value* v = vs_getprop(val, keyv, NULL);
    vs_release(keyv);
    vs_list_push(vs_as_list(pair), v);
    vs_list_push(vs_as_list(out), pair);
  }
  vs_strvec_free(&keys);
  return out;
}

/* ===========================================================================
 * setprop / delprop
 * ===========================================================================*/

vs_value* vs_setprop(vs_value* parent, vs_value* key, vs_value* val) {
  if (!parent || !vs_iskey(key))
    return parent;
  if (vs_is_map(parent)) {
    char* k = vs_strkey(key);
    if (val && vs_is_undef(val)) {
      vs_map_erase(vs_as_map(parent), k);
    } else {
      vs_map_set(vs_as_map(parent), k, val ? vs_retain(val) : vs_new_undef());
    }
    free(k);
  } else if (vs_is_list(parent)) {
    int64_t ki = 0;
    if (vs_is_int(key))
      ki = vs_as_int(key);
    else if (vs_is_double(key))
      ki = (int64_t)floor(vs_as_double(key));
    else if (vs_is_string(key)) {
      if (!parse_intstr(vs_as_string(key), vs_string_len(key), &ki))
        return parent;
    } else {
      return parent;
    }
    vs_list* l = vs_as_list(parent);
    if (ki >= 0) {
      int64_t cap = (int64_t)l->len + 1;
      if (ki > cap - 1)
        ki = cap - 1;
      if (ki < cap) {
        vs_list_set(l, (size_t)ki, val ? vs_retain(val) : vs_new_undef());
      }
    } else {
      vs_list_insert(l, 0, val ? vs_retain(val) : vs_new_undef());
    }
  }
  return parent;
}

vs_value* vs_delprop(vs_value* parent, vs_value* key) {
  if (!parent || !vs_iskey(key))
    return parent;
  if (vs_is_map(parent)) {
    char* k = vs_strkey(key);
    vs_map_erase(vs_as_map(parent), k);
    free(k);
  } else if (vs_is_list(parent)) {
    int64_t ki = 0;
    if (vs_is_int(key))
      ki = vs_as_int(key);
    else if (vs_is_double(key))
      ki = (int64_t)floor(vs_as_double(key));
    else if (vs_is_string(key)) {
      if (!parse_intstr(vs_as_string(key), vs_string_len(key), &ki))
        return parent;
    } else {
      return parent;
    }
    vs_list* l = vs_as_list(parent);
    if (ki >= 0 && ki < (int64_t)l->len) {
      vs_list_erase(l, (size_t)ki);
    }
  }
  return parent;
}

/* ===========================================================================
 * flatten / filter
 * ===========================================================================*/

static void flatten_into(vs_value* out, vs_value* list, int depth) {
  if (!vs_is_list(list)) {
    vs_list_push(vs_as_list(out), vs_retain(list));
    return;
  }
  if (depth <= 0) {
    /* Append all items as-is (one level of flattening already exhausted). */
    vs_list* src = vs_as_list(list);
    for (size_t i = 0; i < src->len; i++) {
      vs_list_push(vs_as_list(out), vs_retain(src->items[i]));
    }
    return;
  }
  vs_list* src = vs_as_list(list);
  for (size_t i = 0; i < src->len; i++) {
    vs_value* it = src->items[i];
    if (vs_is_list(it)) {
      flatten_into(out, it, depth - 1);
    } else {
      vs_list_push(vs_as_list(out), vs_retain(it));
    }
  }
}

vs_value* vs_flatten(vs_value* list, vs_value* depth) {
  if (!vs_is_list(list))
    return vs_retain(list);
  int d = 1;
  if (depth && !vs_is_undef(depth)) {
    if (vs_is_int(depth))
      d = (int)vs_as_int(depth);
    else if (vs_is_double(depth))
      d = (int)vs_as_double(depth);
  }
  vs_value* out = vs_new_list();
  vs_list* src = vs_as_list(list);
  for (size_t i = 0; i < src->len; i++) {
    vs_value* it = src->items[i];
    if (vs_is_list(it) && d > 0) {
      flatten_into(out, it, d - 1);
    } else {
      vs_list_push(vs_as_list(out), vs_retain(it));
    }
  }
  return out;
}

vs_value* vs_filter(vs_value* val, vs_itemcheck_fn check, void* ud) {
  vs_value* all = vs_items_v(val);
  vs_value* out = vs_new_list();
  vs_list* l = vs_as_list(all);
  for (size_t i = 0; i < l->len; i++) {
    vs_value* pair = l->items[i];
    if (check(pair, ud)) {
      vs_value* v = vs_list_get(vs_as_list(pair), 1);
      vs_list_push(vs_as_list(out), vs_retain(v));
    }
  }
  vs_release(all);
  return out;
}

/* ===========================================================================
 * escre / escurl / replace
 * ===========================================================================*/

char* vs_escre(vs_value* v) {
  const char* s = "";
  if (vs_is_string(v))
    s = vs_as_string(v);
  /* Equivalent to canonical TS: replace /[.*+?^${}()|[\]\\]/g with "\\$&".
     vs_re_escape implements the same character set. */
  return vs_re_escape(s);
}

char* vs_escurl(vs_value* v) {
  const char* s = "";
  if (vs_is_string(v))
    s = vs_as_string(v);
  size_t n = strlen(s);
  char* o = (char*)malloc(n * 3 + 1);
  if (!o)
    abort();
  size_t j = 0;
  static const char hex[] = "0123456789ABCDEF";
  for (size_t i = 0; i < n; i++) {
    unsigned char c = (unsigned char)s[i];
    /* RFC 3986 encodeURIComponent: unreserved chars: A-Z a-z 0-9 - _ . ~ ! * ' ( ) */
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' ||
        c == '_' || c == '.' || c == '~' || c == '!' || c == '*' || c == '\'' || c == '(' ||
        c == ')') {
      o[j++] = (char)c;
    } else {
      o[j++] = '%';
      o[j++] = hex[(c >> 4) & 0xF];
      o[j++] = hex[c & 0xF];
    }
  }
  o[j] = '\0';
  return o;
}

char* vs_replace_str(const char* s, const char* from, const char* to) {
  if (!s)
    s = "";
  if (!from || !*from)
    return xstrdup_s(s);
  if (!to)
    to = "";
  size_t sl = strlen(s);
  size_t fl = strlen(from);
  size_t tl = strlen(to);
  size_t cap = sl + 16;
  char* out = (char*)malloc(cap);
  if (!out)
    abort();
  size_t o = 0;
  for (size_t i = 0; i < sl;) {
    if (i + fl <= sl && memcmp(s + i, from, fl) == 0) {
      while (o + tl >= cap) {
        cap *= 2;
        out = (char*)realloc(out, cap);
        if (!out)
          abort();
      }
      memcpy(out + o, to, tl);
      o += tl;
      i += fl;
    } else {
      if (o + 1 >= cap) {
        cap *= 2;
        out = (char*)realloc(out, cap);
        if (!out)
          abort();
      }
      out[o++] = s[i++];
    }
  }
  if (o + 1 > cap) {
    cap = o + 1;
    out = (char*)realloc(out, cap);
    if (!out)
      abort();
  }
  out[o] = '\0';
  return out;
}

/* ===========================================================================
 * stringify / jsonify / pathify / pad
 * ===========================================================================*/

static void sb_append(char** buf, size_t* len, size_t* cap, const char* s, size_t n) {
  if (*len + n + 1 > *cap) {
    size_t nc = *cap == 0 ? 64 : *cap;
    while (nc < *len + n + 1)
      nc *= 2;
    char* nb = (char*)realloc(*buf, nc);
    if (!nb)
      abort();
    *buf = nb;
    *cap = nc;
  }
  memcpy(*buf + *len, s, n);
  *len += n;
  (*buf)[*len] = '\0';
}

static void sb_append_str(char** buf, size_t* len, size_t* cap, const char* s) {
  sb_append(buf, len, cap, s, strlen(s));
}

/* Sort keys for "stringify": canonical orders map keys by insertion (so stable). */
static void stringify_inner(vs_value* v, char** buf, size_t* len, size_t* cap, bool top);

static void escape_json_str(const char* s, size_t n, char** buf, size_t* len, size_t* cap) {
  for (size_t i = 0; i < n; i++) {
    unsigned char c = (unsigned char)s[i];
    if (c == '"' || c == '\\') {
      char esc[2] = {'\\', (char)c};
      sb_append(buf, len, cap, esc, 2);
    } else if (c == '\n') {
      sb_append(buf, len, cap, "\\n", 2);
    } else if (c == '\r') {
      sb_append(buf, len, cap, "\\r", 2);
    } else if (c == '\t') {
      sb_append(buf, len, cap, "\\t", 2);
    } else if (c == '\b') {
      sb_append(buf, len, cap, "\\b", 2);
    } else if (c == '\f') {
      sb_append(buf, len, cap, "\\f", 2);
    } else if (c < 0x20) {
      char tmp[8];
      snprintf(tmp, sizeof(tmp), "\\u%04x", c);
      sb_append_str(buf, len, cap, tmp);
    } else {
      sb_append(buf, len, cap, (const char*)&c, 1);
    }
  }
}

static void stringify_inner(vs_value* v, char** buf, size_t* len, size_t* cap, bool top) {
  if (!v || vs_is_undef(v)) {
    if (top)
      sb_append_str(buf, len, cap, "");
    else
      sb_append_str(buf, len, cap, "null");
    return;
  }
  if (vs_is_null(v)) {
    sb_append_str(buf, len, cap, "null");
    return;
  }
  if (vs_is_bool(v)) {
    sb_append_str(buf, len, cap, vs_as_bool(v) ? "true" : "false");
    return;
  }
  if (vs_is_int(v)) {
    char tmp[32];
    snprintf(tmp, sizeof(tmp), "%lld", (long long)vs_as_int(v));
    sb_append_str(buf, len, cap, tmp);
    return;
  }
  if (vs_is_double(v)) {
    char* s = doublestr(vs_as_double(v));
    sb_append_str(buf, len, cap, s);
    free(s);
    return;
  }
  if (vs_is_string(v)) {
    /* In TS stringify, JSON.stringify then remove all quotes. */
    sb_append(buf, len, cap, "\"", 1);
    escape_json_str(vs_as_string(v), vs_string_len(v), buf, len, cap);
    sb_append(buf, len, cap, "\"", 1);
    return;
  }
  if (vs_is_list(v)) {
    sb_append_str(buf, len, cap, "[");
    vs_list* l = vs_as_list(v);
    for (size_t i = 0; i < l->len; i++) {
      if (i > 0)
        sb_append_str(buf, len, cap, ",");
      stringify_inner(l->items[i], buf, len, cap, false);
    }
    sb_append_str(buf, len, cap, "]");
    return;
  }
  if (vs_is_map(v)) {
    sb_append_str(buf, len, cap, "{");
    vs_map* m = vs_as_map(v);
    /* In TS stringify, map keys are visited via items() which yields sorted keys. */
    /* Build sorted index. */
    size_t* idx = (size_t*)malloc(m->len * sizeof(size_t) + 1);
    if (!idx)
      abort();
    for (size_t i = 0; i < m->len; i++)
      idx[i] = i;
    /* Sort by key. */
    for (size_t i = 1; i < m->len; i++) {
      size_t j = i;
      while (j > 0 && strcmp(m->entries[idx[j - 1]].key, m->entries[idx[j]].key) > 0) {
        size_t t = idx[j - 1];
        idx[j - 1] = idx[j];
        idx[j] = t;
        j--;
      }
    }
    for (size_t i = 0; i < m->len; i++) {
      if (i > 0)
        sb_append_str(buf, len, cap, ",");
      sb_append(buf, len, cap, "\"", 1);
      escape_json_str(m->entries[idx[i]].key, m->entries[idx[i]].klen, buf, len, cap);
      sb_append_str(buf, len, cap, "\":");
      stringify_inner(m->entries[idx[i]].value, buf, len, cap, false);
    }
    free(idx);
    sb_append_str(buf, len, cap, "}");
    return;
  }
  if (vs_is_sentinel(v)) {
    char tmp[48];
    snprintf(tmp, sizeof(tmp), "{\"`$%s`\":true}", vs_as_sentinel(v)->name);
    sb_append_str(buf, len, cap, tmp);
    return;
  }
  if (vs_is_func(v)) {
    sb_append_str(buf, len, cap, "null");
    return;
  }
  sb_append_str(buf, len, cap, "null");
}

char* vs_stringify(vs_value* val, int maxlen) {
  if (!val || vs_is_undef(val))
    return xstrdup_s("");
  char* buf = NULL;
  size_t len = 0, cap = 0;

  if (vs_is_string(val)) {
    sb_append(&buf, &len, &cap, vs_as_string(val), vs_string_len(val));
  } else {
    stringify_inner(val, &buf, &len, &cap, true);
    /* Remove all double quotes. */
    size_t w = 0;
    for (size_t r = 0; r < len; r++) {
      if (buf[r] != '"')
        buf[w++] = buf[r];
    }
    buf[w] = '\0';
    len = w;
  }

  if (maxlen >= 0 && (int64_t)len > (int64_t)maxlen) {
    if (maxlen >= 3) {
      memcpy(buf + maxlen - 3, "...", 3);
      buf[maxlen] = '\0';
    } else {
      buf[maxlen] = '\0';
    }
  }
  if (!buf)
    buf = xstrdup_s("");
  return buf;
}

/* jsonify: emit standard JSON. */
static void jsonify_inner(vs_value* v, char** buf, size_t* len, size_t* cap, int indent,
                          int depth) {
  if (!v || vs_is_undef(v) || vs_is_null(v)) {
    sb_append_str(buf, len, cap, "null");
    return;
  }
  if (vs_is_bool(v)) {
    sb_append_str(buf, len, cap, vs_as_bool(v) ? "true" : "false");
    return;
  }
  if (vs_is_int(v)) {
    char tmp[32];
    snprintf(tmp, sizeof(tmp), "%lld", (long long)vs_as_int(v));
    sb_append_str(buf, len, cap, tmp);
    return;
  }
  if (vs_is_double(v)) {
    char* s = doublestr(vs_as_double(v));
    sb_append_str(buf, len, cap, s);
    free(s);
    return;
  }
  if (vs_is_string(v)) {
    sb_append(buf, len, cap, "\"", 1);
    escape_json_str(vs_as_string(v), vs_string_len(v), buf, len, cap);
    sb_append(buf, len, cap, "\"", 1);
    return;
  }
  if (vs_is_list(v)) {
    vs_list* l = vs_as_list(v);
    if (l->len == 0) {
      sb_append_str(buf, len, cap, "[]");
      return;
    }
    sb_append_str(buf, len, cap, "[");
    for (size_t i = 0; i < l->len; i++) {
      if (i > 0)
        sb_append_str(buf, len, cap, ",");
      if (indent > 0) {
        sb_append_str(buf, len, cap, "\n");
        for (int j = 0; j < (depth + 1) * indent; j++)
          sb_append_str(buf, len, cap, " ");
      }
      jsonify_inner(l->items[i], buf, len, cap, indent, depth + 1);
    }
    if (indent > 0) {
      sb_append_str(buf, len, cap, "\n");
      for (int j = 0; j < depth * indent; j++)
        sb_append_str(buf, len, cap, " ");
    }
    sb_append_str(buf, len, cap, "]");
    return;
  }
  if (vs_is_map(v)) {
    vs_map* m = vs_as_map(v);
    if (m->len == 0) {
      sb_append_str(buf, len, cap, "{}");
      return;
    }
    sb_append_str(buf, len, cap, "{");
    for (size_t i = 0; i < m->len; i++) {
      if (i > 0)
        sb_append_str(buf, len, cap, ",");
      if (indent > 0) {
        sb_append_str(buf, len, cap, "\n");
        for (int j = 0; j < (depth + 1) * indent; j++)
          sb_append_str(buf, len, cap, " ");
      }
      sb_append(buf, len, cap, "\"", 1);
      escape_json_str(m->entries[i].key, m->entries[i].klen, buf, len, cap);
      sb_append_str(buf, len, cap, indent > 0 ? "\": " : "\":");
      jsonify_inner(m->entries[i].value, buf, len, cap, indent, depth + 1);
    }
    if (indent > 0) {
      sb_append_str(buf, len, cap, "\n");
      for (int j = 0; j < depth * indent; j++)
        sb_append_str(buf, len, cap, " ");
    }
    sb_append_str(buf, len, cap, "}");
    return;
  }
  sb_append_str(buf, len, cap, "null");
}

char* vs_jsonify(vs_value* val, vs_value* flags) {
  if (!val || vs_is_undef(val) || vs_is_null(val))
    return xstrdup_s("null");
  int indent = 2;
  int offset = 0;
  if (flags && vs_is_map(flags)) {
    vs_value* iv = vs_map_get(vs_as_map(flags), "indent");
    if (vs_is_int(iv))
      indent = (int)vs_as_int(iv);
    else if (vs_is_double(iv))
      indent = (int)vs_as_double(iv);
    vs_value* ov = vs_map_get(vs_as_map(flags), "offset");
    if (vs_is_int(ov))
      offset = (int)vs_as_int(ov);
    else if (vs_is_double(ov))
      offset = (int)vs_as_double(ov);
  }
  char* buf = NULL;
  size_t len = 0, cap = 0;
  jsonify_inner(val, &buf, &len, &cap, indent, 0);
  if (offset > 0) {
    /* Re-indent: find first newline, prepend "{" + "\n" and pad subsequent lines by offset. */
    /* The first brace is on the same line as the assignment, so it's not offset. */
    char* nb = NULL;
    size_t nlen = 0, ncap = 0;
    sb_append_str(&nb, &nlen, &ncap, "{\n");
    bool first_line = true;
    size_t i = 0;
    while (i < len) {
      size_t lstart = i;
      while (i < len && buf[i] != '\n')
        i++;
      size_t llen = i - lstart;
      if (first_line) {
        /* Skip the first '{' line. */
        first_line = false;
      } else {
        /* Pad with offset spaces. */
        for (int j = 0; j < offset; j++)
          sb_append_str(&nb, &nlen, &ncap, " ");
        sb_append(&nb, &nlen, &ncap, buf + lstart, llen);
        sb_append_str(&nb, &nlen, &ncap, "\n");
      }
      if (i < len)
        i++;
    }
    free(buf);
    /* Strip trailing newline. */
    if (nlen > 0 && nb[nlen - 1] == '\n')
      nb[--nlen] = '\0';
    buf = nb;
  }
  if (!buf)
    return xstrdup_s("null");
  return buf;
}

char* vs_pad(vs_value* str, vs_value* padding, vs_value* padchar) {
  char* s;
  if (vs_is_string(str))
    s = xstrdup_s(vs_as_string(str));
  else
    s = vs_stringify(str, -1);
  int p = 44;
  if (padding && !vs_is_undef(padding)) {
    if (vs_is_int(padding))
      p = (int)vs_as_int(padding);
    else if (vs_is_double(padding))
      p = (int)vs_as_double(padding);
  }
  char pc = ' ';
  if (vs_is_string(padchar) && vs_string_len(padchar) > 0)
    pc = vs_as_string(padchar)[0];
  size_t slen = strlen(s);
  if (p < 0) {
    /* Left pad. */
    int width = -p;
    if (slen >= (size_t)width)
      return s;
    size_t pad = width - slen;
    char* o = (char*)malloc(width + 1);
    if (!o)
      abort();
    memset(o, pc, pad);
    memcpy(o + pad, s, slen);
    o[width] = '\0';
    free(s);
    return o;
  } else {
    /* Right pad. */
    if (slen >= (size_t)p)
      return s;
    char* o = (char*)realloc(s, p + 1);
    if (!o)
      abort();
    memset(o + slen, pc, p - slen);
    o[p] = '\0';
    return o;
  }
}

char* vs_pathify(vs_value* val, int startin, int endin) {
  /* Determine path: list, string, or number. */
  vs_value* path = NULL;
  bool path_owned = false;
  if (vs_is_list(val)) {
    path = val;
  } else if (vs_is_string(val)) {
    path = vs_new_list();
    path_owned = true;
    vs_list_push(vs_as_list(path), vs_retain(val));
  } else if (vs_is_number(val)) {
    path = vs_new_list();
    path_owned = true;
    vs_list_push(vs_as_list(path), vs_retain(val));
  }

  int start = startin < 0 ? 0 : startin;
  int end = endin < 0 ? 0 : endin;

  char* out = NULL;
  if (path && vs_is_list(path)) {
    vs_list* l = vs_as_list(path);
    int64_t plen = (int64_t)l->len;
    /* path = slice(path, start, path.length - end) */
    int64_t s = start;
    int64_t e = plen - end;
    if (s < 0)
      s = 0;
    if (e > plen)
      e = plen;
    if (e <= s) {
      out = xstrdup_s("<root>");
    } else {
      /* Build dotted joined string. */
      char* buf = NULL;
      size_t len = 0, cap = 0;
      bool first = true;
      for (int64_t i = s; i < e; i++) {
        vs_value* p = vs_list_get(l, (size_t)i);
        if (!vs_iskey(p))
          continue;
        char* part;
        if (vs_is_number(p)) {
          int64_t n;
          if (vs_is_int(p))
            n = vs_as_int(p);
          else
            n = (int64_t)floor(vs_as_double(p));
          part = intstr(n);
        } else {
          /* Remove dots from string. */
          const char* ps = vs_as_string(p);
          size_t pn = vs_string_len(p);
          char* tmp = (char*)malloc(pn + 1);
          if (!tmp)
            abort();
          size_t w = 0;
          for (size_t k = 0; k < pn; k++) {
            if (ps[k] != '.')
              tmp[w++] = ps[k];
          }
          tmp[w] = '\0';
          part = tmp;
        }
        if (!first)
          sb_append_str(&buf, &len, &cap, ".");
        sb_append_str(&buf, &len, &cap, part);
        first = false;
        free(part);
      }
      if (!buf)
        out = xstrdup_s("");
      else
        out = buf;
    }
  }

  if (!out) {
    char* s;
    if (vs_is_undef(val))
      s = xstrdup_s("");
    else {
      char* tmp = vs_stringify(val, 47);
      size_t ln = strlen(tmp) + 32;
      s = (char*)malloc(ln);
      snprintf(s, ln, ":%s", tmp);
      free(tmp);
    }
    char* full = (char*)malloc(strlen(s) + 32);
    snprintf(full, strlen(s) + 32, "<unknown-path%s>", s);
    free(s);
    out = full;
  }

  if (path_owned)
    vs_release(path);
  return out;
}

/* ===========================================================================
 * join
 * ===========================================================================*/

char* vs_join_v(vs_value* arr, vs_value* sep, vs_value* url) {
  const char* sepstr = ",";
  if (vs_is_string(sep))
    sepstr = vs_as_string(sep);
  bool url_mode = vs_is_bool(url) && vs_as_bool(url);
  size_t seplen = strlen(sepstr);

  if (!vs_is_list(arr))
    return xstrdup_s("");
  vs_list* l = vs_as_list(arr);
  /* Collect string entries (filter out non-string and empty). */
  size_t* keepi = (size_t*)malloc(sizeof(size_t) * (l->len + 1));
  size_t nkeep = 0;
  for (size_t i = 0; i < l->len; i++) {
    if (vs_is_string(l->items[i]) && vs_string_len(l->items[i]) > 0) {
      keepi[nkeep++] = i;
    }
  }
  /* Now process each. */
  char* result = NULL;
  size_t rlen = 0, rcap = 0;
  bool first = true;
  for (size_t k = 0; k < nkeep; k++) {
    size_t i = keepi[k];
    const char* sin = vs_as_string(l->items[i]);
    size_t inlen = vs_string_len(l->items[i]);
    char* s = xstrndup_s(sin, inlen);
    /* Apply sep-trimming rules. */
    if (seplen == 1) {
      char sc = sepstr[0];
      bool early_return = false;
      /* URL mode at index 0: strip trailing sep then EARLY-RETURN. */
      if (url_mode && i == 0) {
        size_t sl = strlen(s);
        while (sl > 0 && s[sl - 1] == sc)
          s[--sl] = '\0';
        early_return = true;
      } else {
        if (i > 0) {
          /* Strip leading sep. */
          size_t st = 0;
          size_t sl = strlen(s);
          while (st < sl && s[st] == sc)
            st++;
          if (st > 0) {
            memmove(s, s + st, sl - st + 1);
          }
        }
        if (i < l->len - 1 || !url_mode) {
          size_t sl = strlen(s);
          while (sl > 0 && s[sl - 1] == sc)
            s[--sl] = '\0';
        }
      }
      if (!early_return) {
        /* Collapse "X<sep>+Y" -> "X<sep>Y" — only the FIRST match per the TS
         * regex which is unanchored and not /g. */
        size_t sl = strlen(s);
        char* tmp = (char*)malloc(sl + 1);
        size_t w = 0;
        bool replaced = false;
        for (size_t p = 0; p < sl; p++) {
          if (!replaced && p > 0 && p < sl - 1 && s[p] == sc && s[p - 1] != sc) {
            size_t q = p + 1;
            while (q < sl && s[q] == sc)
              q++;
            if (q < sl && q > p + 1 && s[q] != sc) {
              tmp[w++] = sc;
              p = q - 1;
              replaced = true;
              continue;
            }
          }
          tmp[w++] = s[p];
        }
        tmp[w] = '\0';
        free(s);
        s = tmp;
      }
    }
    if (strlen(s) > 0) {
      if (!first)
        sb_append(&result, &rlen, &rcap, sepstr, seplen);
      sb_append_str(&result, &rlen, &rcap, s);
      first = false;
    }
    free(s);
  }
  free(keepi);
  if (!result)
    return xstrdup_s("");
  return result;
}

/* ===========================================================================
 * jm / jt builders
 * ===========================================================================*/

vs_value* vs_jm_va(int n, vs_value** kv) {
  vs_value* o = vs_new_map();
  for (int i = 0; i < n; i += 2) {
    vs_value* k = (i < n) ? kv[i] : NULL;
    vs_value* v = (i + 1 < n) ? kv[i + 1] : NULL;
    char buf[32];
    char* key;
    if (vs_is_string(k)) {
      key = xstrdup_s(vs_as_string(k));
    } else if (k) {
      key = vs_stringify(k, -1);
    } else {
      snprintf(buf, sizeof(buf), "$KEY%d", i);
      key = xstrdup_s(buf);
    }
    vs_map_set(vs_as_map(o), key, v ? vs_retain(v) : vs_new_null());
    free(key);
  }
  return o;
}

vs_value* vs_jt_va(int n, vs_value** v) {
  vs_value* a = vs_new_list();
  for (int i = 0; i < n; i++) {
    vs_list_push(vs_as_list(a), v[i] ? vs_retain(v[i]) : vs_new_null());
  }
  return a;
}

/* ===========================================================================
 * walk
 * ===========================================================================*/

typedef struct walk_state {
  vs_walkapply_fn before;
  vs_walkapply_fn after;
  int maxdepth;
  void* ud;
} walk_state;

/* path_stack: a vs_value list of strings; reused/mutated for child calls (per-depth pool). */

static vs_value* walk_rec(walk_state* st, vs_value* val, vs_value* key, vs_value* parent,
                          vs_value* path) {
  int depth = (int)vs_list_len(vs_as_list(path));
  vs_value* out = val ? vs_retain(val) : vs_new_undef();
  if (st->before) {
    vs_value* nval = st->before(key, out, parent, path, st->ud);
    /* Callback returns a new owned ref; release the prior one unconditionally. */
    vs_release(out);
    out = nval;
  }

  int maxd = st->maxdepth;
  if (maxd == 0 || (maxd > 0 && maxd <= depth)) {
    return out;
  }

  if (vs_is_node(out)) {
    /* Build child key list (sorted as keysof returns). */
    vs_strvec keys = vs_keysof(out);
    /* Path push placeholder. */
    vs_list_push(vs_as_list(path), vs_new_string(""));
    for (size_t i = 0; i < keys.len; i++) {
      /* Set path[depth] = key. */
      vs_release(vs_list_get(vs_as_list(path), (size_t)depth));
      vs_as_list(path)->items[depth] = vs_new_string(keys.data[i]);

      vs_value* ckey;
      if (vs_is_list(out)) {
        ckey = vs_new_int((int64_t)i);
      } else {
        ckey = vs_new_string(keys.data[i]);
      }
      vs_value* ckeyv = vs_new_string(keys.data[i]);
      vs_value* cp = vs_lookup(out, ckeyv);
      vs_value* child = cp ? vs_retain(cp) : vs_new_undef();
      vs_release(ckeyv);

      vs_value* nchild = walk_rec(st, child, ckey, out, path);
      vs_release(child);
      vs_setprop(out, ckey, nchild);
      vs_release(nchild);
      vs_release(ckey);
    }
    /* Path pop. */
    vs_release(vs_list_get(vs_as_list(path), (size_t)depth));
    vs_as_list(path)->len--;
    vs_strvec_free(&keys);
  }

  if (st->after) {
    vs_value* nval = st->after(key, out, parent, path, st->ud);
    vs_release(out);
    out = nval;
  }
  return out;
}

vs_value* vs_walk(vs_value* val, vs_walkapply_fn before, vs_walkapply_fn after, int maxdepth,
                  void* ud) {
  walk_state st;
  st.before = before;
  st.after = after;
  st.maxdepth = (maxdepth >= 0 || maxdepth == INT_MAX) ? maxdepth : VS_MAXDEPTH;
  if (maxdepth < 0 && maxdepth != INT_MAX)
    st.maxdepth = VS_MAXDEPTH;
  st.ud = ud;
  vs_value* path = vs_new_list();
  vs_value* undef = vs_new_undef();
  vs_value* out = walk_rec(&st, val, undef, NULL, path);
  vs_release(undef);
  vs_release(path);
  return out;
}

/* ===========================================================================
 * merge
 * ===========================================================================*/

typedef struct merge_state {
  vs_value* cur_stack; /* list */
  vs_value* dst_stack; /* list */
  int maxdepth;
} merge_state;

static vs_value* merge_before(vs_value* key, vs_value* val, vs_value* parent, vs_value* path,
                              void* ud) {
  (void)parent;
  merge_state* st = (merge_state*)ud;
  int pI = (int)vs_list_len(vs_as_list(path));

  if (st->maxdepth <= pI) {
    /* setprop(cur[pI-1], key, val) */
    vs_value* target = vs_list_get(vs_as_list(st->cur_stack), pI - 1);
    if (target)
      vs_setprop(target, key, val);
    return val ? vs_retain(val) : vs_new_undef();
  }

  if (!vs_is_node(val)) {
    /* cur[pI] = val */
    vs_list_set(vs_as_list(st->cur_stack), (size_t)pI, val ? vs_retain(val) : vs_new_undef());
    return val ? vs_retain(val) : vs_new_undef();
  }

  /* dst[pI] = pI>0 ? getprop(dst[pI-1], key) : dst[pI]; */
  vs_value* tval = NULL;
  if (pI > 0) {
    vs_value* dp = vs_list_get(vs_as_list(st->dst_stack), (size_t)(pI - 1));
    tval = dp ? vs_getprop(dp, key, NULL) : vs_new_undef();
  } else {
    tval = vs_retain(vs_list_get(vs_as_list(st->dst_stack), (size_t)pI));
  }
  /* dst[pI] = tval */
  vs_list_set(vs_as_list(st->dst_stack), (size_t)pI, vs_retain(tval));

  int tvt = vs_typify(tval);
  int valt = vs_typify(val);

  if (vs_is_undef(tval)) {
    /* Destination empty; create node unless override is instance. */
    if (!(VS_T_INSTANCE & valt)) {
      vs_value* nc = vs_is_list(val) ? vs_new_list() : vs_new_map();
      vs_list_set(vs_as_list(st->cur_stack), (size_t)pI, nc);
    }
    vs_release(tval);
    return val ? vs_retain(val) : vs_new_undef();
  }
  if (tvt == valt) {
    vs_list_set(vs_as_list(st->cur_stack), (size_t)pI, vs_retain(tval));
    vs_release(tval);
    return val ? vs_retain(val) : vs_new_undef();
  }
  /* Override wins. */
  vs_list_set(vs_as_list(st->cur_stack), (size_t)pI, vs_retain(val));
  vs_release(tval);
  /* Don't descend; set val to undef. */
  return vs_new_undef();
}

static vs_value* merge_after(vs_value* key, vs_value* val, vs_value* parent, vs_value* path,
                             void* ud) {
  (void)val;
  (void)parent;
  merge_state* st = (merge_state*)ud;
  int cI = (int)vs_list_len(vs_as_list(path));
  vs_value* target = vs_list_get(vs_as_list(st->cur_stack), (size_t)(cI - 1));
  vs_value* value = vs_list_get(vs_as_list(st->cur_stack), (size_t)cI);
  if (target)
    vs_setprop(target, key, value);
  return val ? vs_retain(val) : vs_new_undef();
}

vs_value* vs_merge(vs_value* val, int maxdepth) {
  /* slice(maxdepth ?? MAXDEPTH, 0) — TS numeric slice clamps below 0. */
  int md = maxdepth;
  if (md < 0)
    md = 0;
  if (md > VS_MAXDEPTH)
    md = VS_MAXDEPTH;

  if (!vs_is_list(val))
    return val ? vs_retain(val) : vs_new_undef();
  vs_list* l = vs_as_list(val);
  size_t n = l->len;
  if (n == 0)
    return vs_new_undef();
  if (n == 1)
    return vs_retain(l->items[0]);

  vs_value* out = vs_list_get(l, 0);
  out = out ? vs_retain(out) : vs_new_map();

  for (size_t oI = 1; oI < n; oI++) {
    vs_value* obj = l->items[oI];
    if (!vs_is_node(obj)) {
      vs_release(out);
      out = obj ? vs_retain(obj) : vs_new_undef();
    } else {
      merge_state st;
      st.cur_stack = vs_new_list();
      st.dst_stack = vs_new_list();
      vs_list_push(vs_as_list(st.cur_stack), vs_retain(out));
      vs_list_push(vs_as_list(st.dst_stack), vs_retain(out));
      st.maxdepth = md;

      vs_value* walked = vs_walk(obj, merge_before, merge_after, md, &st);
      /* out = walk(obj, before, after, maxdepth) — TS reassigns. The walk
         callbacks update cur[0]; we use cur[0] as the new out. */
      vs_value* newcur = vs_list_get(vs_as_list(st.cur_stack), 0);
      if (newcur) {
        vs_release(out);
        out = vs_retain(newcur);
      }
      vs_release(walked);
      vs_release(st.cur_stack);
      vs_release(st.dst_stack);
    }
  }

  if (md == 0) {
    vs_value* last = vs_list_get(l, n - 1);
    vs_release(out);
    if (vs_is_list(last))
      out = vs_new_list();
    else if (vs_is_map(last))
      out = vs_new_map();
    else
      out = last ? vs_retain(last) : vs_new_undef();
  }
  return out;
}

/* ===========================================================================
 * setpath / getpath
 * ===========================================================================*/

vs_value* vs_setpath(vs_value* store, vs_value* path, vs_value* val, vs_injection* injdef) {
  int pt = vs_typify(path);
  vs_value* parts = NULL;
  bool parts_owned = false;
  if (pt & VS_T_LIST) {
    parts = path;
  } else if (pt & VS_T_STRING) {
    parts = vs_new_list();
    parts_owned = true;
    const char* s = vs_as_string(path);
    size_t n = vs_string_len(path);
    size_t i = 0;
    while (i <= n) {
      size_t j = i;
      while (j < n && s[j] != '.')
        j++;
      vs_list_push(vs_as_list(parts), vs_new_string_n(s + i, j - i));
      i = j + 1;
      if (j == n)
        break;
    }
  } else if (pt & VS_T_NUMBER) {
    parts = vs_new_list();
    parts_owned = true;
    vs_list_push(vs_as_list(parts), vs_retain(path));
  } else {
    return NULL;
  }

  vs_value* base_v = NULL;
  if (injdef && injdef->base) {
    base_v = vs_map_get(vs_as_map(store), injdef->base);
  }
  vs_value* parent = base_v ? base_v : store;

  size_t nparts = vs_list_len(vs_as_list(parts));
  for (size_t pI = 0; pI + 1 < nparts; pI++) {
    vs_value* partKey = vs_list_get(vs_as_list(parts), pI);
    vs_value* nextParent = vs_getprop(parent, partKey, NULL);
    if (!vs_is_node(nextParent)) {
      vs_release(nextParent);
      vs_value* nextKey = vs_list_get(vs_as_list(parts), pI + 1);
      int nkt = vs_typify(nextKey);
      nextParent = (nkt & VS_T_NUMBER) ? vs_new_list() : vs_new_map();
      vs_setprop(parent, partKey, nextParent);
      /* nextParent ref ownership: vs_setprop retains, so we need to release our own. */
      vs_value* held = nextParent;
      nextParent = vs_getprop(parent, partKey, NULL);
      vs_release(held);
    }
    parent = nextParent;
    /* Release temporary borrowed ref carefully. nextParent was returned with
       a new ref via vs_getprop, so it's owned now; we'll leak refcount unless
       balanced. Reduce by 1 via release at end of loop. */
    /* For simplicity, treat parent as borrowed; release at end. */
  }

  vs_value* lastKey = nparts > 0 ? vs_list_get(vs_as_list(parts), nparts - 1) : NULL;
  if (val && vs_is_delete(val)) {
    vs_delprop(parent, lastKey);
  } else {
    vs_setprop(parent, lastKey, val);
  }

  if (parts_owned)
    vs_release(parts);
  return parent;
}

/* getpath: see TS reference, lines 1082–1188. */
vs_value* vs_getpath(vs_value* store, vs_value* path, vs_injection* injdef) {
  /* Parse path into string list. */
  vs_strvec parts;
  vs_strvec_init(&parts);
  bool path_ok = false;
  if (vs_is_list(path)) {
    vs_list* l = vs_as_list(path);
    for (size_t i = 0; i < l->len; i++) {
      char* sk = vs_strkey(l->items[i]);
      vs_strvec_push(&parts, sk);
      free(sk);
    }
    path_ok = true;
  } else if (vs_is_string(path)) {
    const char* s = vs_as_string(path);
    size_t n = vs_string_len(path);
    size_t i = 0;
    while (i <= n) {
      size_t j = i;
      while (j < n && s[j] != '.')
        j++;
      vs_strvec_push_n(&parts, s + i, j - i);
      i = j + 1;
      if (j == n)
        break;
    }
    path_ok = true;
  } else if (vs_is_number(path)) {
    char* sk = vs_strkey(path);
    vs_strvec_push(&parts, sk);
    free(sk);
    path_ok = true;
  }
  if (!path_ok)
    return vs_new_undef();

  vs_value* val = store ? vs_retain(store) : vs_new_undef();
  vs_value* base_v = NULL;
  if (injdef && injdef->base) {
    vs_value* keyv = vs_new_string(injdef->base);
    base_v = vs_getprop(store, keyv, NULL);
    vs_release(keyv);
  }
  vs_value* src =
      base_v && !vs_is_undef(base_v) ? base_v : (store ? vs_retain(store) : vs_new_undef());
  if (!base_v || vs_is_undef(base_v)) {
    vs_release(base_v);
  }
  size_t numparts = parts.len;
  vs_value* dparent =
      injdef ? (injdef->dparent ? vs_retain(injdef->dparent) : vs_new_undef()) : vs_new_undef();
  bool emptypath = false;
  if (!path || vs_is_undef(path) || !store || (numparts == 1 && parts.data[0][0] == '\0')) {
    emptypath = true;
  }

  if (emptypath) {
    vs_release(val);
    val = vs_retain(src);
  } else if (numparts > 0) {
    /* Check for $ACTIONs. */
    if (numparts == 1) {
      vs_value* k = vs_new_string(parts.data[0]);
      vs_value* tv = vs_getprop(store, k, NULL);
      vs_release(k);
      vs_release(val);
      val = tv;
    }
    if (!vs_is_func(val)) {
      vs_release(val);
      val = vs_retain(src);

      /* Meta path regex: ^([^$]+)\$([=~])(.+)$ */
      if (injdef && injdef->meta && numparts > 0) {
        const char* p0 = parts.data[0];
        const char* dol = strchr(p0, '$');
        if (dol && dol != p0) {
          char sep = dol[1];
          if (sep == '=' || sep == '~') {
            char* lhs = xstrndup_s(p0, dol - p0);
            char* rhs = xstrdup_s(dol + 2);
            vs_value* k = vs_new_string(lhs);
            vs_value* tv = vs_getprop(injdef->meta, k, NULL);
            vs_release(k);
            vs_release(val);
            val = tv;
            vs_strvec_set(&parts, 0, rhs);
            free(lhs);
            free(rhs);
          }
        }
      }

      for (size_t pI = 0; !vs_is_undef(val) && pI < numparts; pI++) {
        char* part = xstrdup_s(parts.data[pI]);

        if (injdef && strcmp(part, "$KEY") == 0) {
          if (injdef->key) {
            free(part);
            part = xstrdup_s(injdef->key);
          }
        } else if (injdef && strncmp(part, "$GET:", 5) == 0) {
          /* $GET:path$ - inner path is part[5..len-1] */
          size_t pl = strlen(part);
          if (pl > 5 && part[pl - 1] == '$') {
            char* inner = xstrndup_s(part + 5, pl - 6);
            vs_value* ipath = vs_new_string(inner);
            free(inner);
            vs_value* iv = vs_getpath(src, ipath, NULL);
            vs_release(ipath);
            free(part);
            part = vs_stringify(iv, -1);
            vs_release(iv);
          }
        } else if (injdef && strncmp(part, "$REF:", 5) == 0) {
          size_t pl = strlen(part);
          if (pl > 5 && part[pl - 1] == '$') {
            char* inner = xstrndup_s(part + 5, pl - 6);
            vs_value* spec_key = vs_new_string("$SPEC");
            vs_value* spec = vs_getprop(store, spec_key, NULL);
            vs_release(spec_key);
            vs_value* ipath = vs_new_string(inner);
            free(inner);
            vs_value* iv = vs_getpath(spec, ipath, NULL);
            vs_release(spec);
            vs_release(ipath);
            free(part);
            part = vs_stringify(iv, -1);
            vs_release(iv);
          }
        } else if (injdef && strncmp(part, "$META:", 6) == 0) {
          size_t pl = strlen(part);
          if (pl > 6 && part[pl - 1] == '$') {
            char* inner = xstrndup_s(part + 6, pl - 7);
            vs_value* ipath = vs_new_string(inner);
            free(inner);
            vs_value* iv = vs_getpath(injdef->meta, ipath, NULL);
            vs_release(ipath);
            free(part);
            part = vs_stringify(iv, -1);
            vs_release(iv);
          }
        }

        /* $$ escapes $ */
        char* unescaped = vs_replace_str(part, "$$", "$");
        free(part);
        part = unescaped;

        if (part[0] == '\0') {
          int ascends = 0;
          while (pI + 1 < numparts && parts.data[pI + 1][0] == '\0') {
            ascends++;
            pI++;
          }
          if (injdef && ascends > 0) {
            if (pI == numparts - 1)
              ascends--;
            if (ascends == 0) {
              vs_release(val);
              val = dparent ? vs_retain(dparent) : vs_new_undef();
            } else {
              /* fullpath = flatten([slice(dpath, -ascends), parts.slice(pI+1)])
               * NOTE: TS slice with negative start clamps via end = vlen+start, so
               * slice(arr, -ascends) keeps the FIRST (vlen-ascends) elements. */
              vs_value* fp = vs_new_list();
              int dpathlen = (int)(injdef ? injdef->dpath.len : 0);
              int dend = dpathlen - ascends;
              if (dend < 0)
                dend = 0;
              for (int di = 0; di < dend; di++) {
                vs_list_push(vs_as_list(fp), vs_new_string(injdef->dpath.data[di]));
              }
              for (size_t pj = pI + 1; pj < numparts; pj++) {
                vs_list_push(vs_as_list(fp), vs_new_string(parts.data[pj]));
              }
              if (ascends <= dpathlen) {
                vs_release(val);
                val = vs_getpath(store, fp, NULL);
              } else {
                vs_release(val);
                val = vs_new_undef();
              }
              vs_release(fp);
              free(part);
              break;
            }
          } else {
            vs_release(val);
            val = dparent ? vs_retain(dparent) : vs_new_undef();
          }
        } else {
          vs_value* k = vs_new_string(part);
          vs_value* nv = vs_lookup(val, k);
          vs_release(k);
          vs_value* tv = nv ? vs_retain(nv) : vs_new_undef();
          vs_release(val);
          val = tv;
        }
        free(part);
      }
    }
  }

  vs_release(dparent);
  vs_release(src);
  vs_strvec_free(&parts);

  /* Handler from injdef. */
  if (injdef && injdef->handler_val && vs_is_func(injdef->handler_val)) {
    char* ref = vs_pathify(path, 0, 0);
    vs_value* tv =
        injdef->handler_val->as.fn.fn.inj(injdef, val, ref, store, injdef->handler_val->as.fn.ud);
    free(ref);
    vs_release(val);
    val = tv;
  }

  return val ? val : vs_new_undef();
}
