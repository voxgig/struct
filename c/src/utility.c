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
static voxgig_regex* R_INTEGER_KEY_re(void) {
  static voxgig_regex* re = NULL;
  if (!re)
    re = voxgig_re_compile("^[-0-9]+$");
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
  bool ok = voxgig_re_test_re(R_INTEGER_KEY_re(), z);
  free(tmp);
  return ok;
}

/* ===========================================================================
 * String vector
 * ===========================================================================*/

void voxgig_strvec_init(voxgig_strvec* v) {
  v->len = 0;
  v->cap = 0;
  v->data = NULL;
}

void voxgig_strvec_free(voxgig_strvec* v) {
  if (!v)
    return;
  for (size_t i = 0; i < v->len; i++)
    free(v->data[i]);
  free(v->data);
  v->data = NULL;
  v->len = 0;
  v->cap = 0;
}

void voxgig_strvec_clear(voxgig_strvec* v) {
  for (size_t i = 0; i < v->len; i++)
    free(v->data[i]);
  v->len = 0;
}

static void strvec_reserve(voxgig_strvec* v, size_t need) {
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

void voxgig_strvec_push(voxgig_strvec* v, const char* s) {
  voxgig_strvec_push_n(v, s, s ? strlen(s) : 0);
}

void voxgig_strvec_push_n(voxgig_strvec* v, const char* s, size_t n) {
  strvec_reserve(v, v->len + 1);
  v->data[v->len++] = xstrndup_s(s ? s : "", n);
}

void voxgig_strvec_resize(voxgig_strvec* v, size_t n) {
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

void voxgig_strvec_set(voxgig_strvec* v, size_t i, const char* s) {
  if (i >= v->len)
    voxgig_strvec_resize(v, i + 1);
  free(v->data[i]);
  v->data[i] = xstrdup_s(s ? s : "");
}

void voxgig_strvec_copy(voxgig_strvec* dst, const voxgig_strvec* src) {
  voxgig_strvec_clear(dst);
  for (size_t i = 0; i < src->len; i++)
    voxgig_strvec_push(dst, src->data[i]);
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

const char* voxgig_typename(int t) {
  int idx = clz32((uint32_t)t);
  if (idx < 0 || idx >= 26)
    return "any";
  const char* s = TYPENAME_TABLE[idx];
  return (s && *s) ? s : "any";
}

/* ===========================================================================
 * typify
 * ===========================================================================*/

int voxgig_typify(const voxgig_value* v) {
  if (!v || voxgig_is_undef(v))
    return VOXGIG_T_NOVAL;
  if (voxgig_is_null(v))
    return VOXGIG_T_SCALAR | VOXGIG_T_NULL;
  if (voxgig_is_bool(v))
    return VOXGIG_T_SCALAR | VOXGIG_T_BOOLEAN;
  if (voxgig_is_int(v))
    return VOXGIG_T_SCALAR | VOXGIG_T_NUMBER | VOXGIG_T_INTEGER;
  if (voxgig_is_double(v)) {
    double d = voxgig_as_double(v);
    if (isnan(d))
      return VOXGIG_T_NOVAL;
    return VOXGIG_T_SCALAR | VOXGIG_T_NUMBER | VOXGIG_T_DECIMAL;
  }
  if (voxgig_is_string(v))
    return VOXGIG_T_SCALAR | VOXGIG_T_STRING;
  if (voxgig_is_list(v))
    return VOXGIG_T_NODE | VOXGIG_T_LIST;
  if (voxgig_is_map(v))
    return VOXGIG_T_NODE | VOXGIG_T_MAP;
  if (voxgig_is_func(v))
    return VOXGIG_T_SCALAR | VOXGIG_T_FUNCTION;
  if (voxgig_is_sentinel(v))
    return VOXGIG_T_NODE | VOXGIG_T_MAP;
  return VOXGIG_T_ANY;
}

/* ===========================================================================
 * Predicates (voxgig_*)
 * ===========================================================================*/

bool voxgig_isnode(const voxgig_value* v) {
  return voxgig_is_node(v);
}
bool voxgig_ismap(const voxgig_value* v) {
  return voxgig_is_map(v);
}
bool voxgig_islist(const voxgig_value* v) {
  return voxgig_is_list(v);
}

bool voxgig_iskey(const voxgig_value* v) {
  if (voxgig_is_string(v))
    return voxgig_string_len(v) > 0;
  return voxgig_is_int(v) || voxgig_is_double(v);
}

bool voxgig_isempty(const voxgig_value* v) {
  if (!v || voxgig_is_undef(v) || voxgig_is_null(v))
    return true;
  if (voxgig_is_string(v))
    return voxgig_string_len(v) == 0;
  if (voxgig_is_list(v))
    return voxgig_list_len(voxgig_as_list(v)) == 0;
  if (voxgig_is_map(v))
    return voxgig_map_len(voxgig_as_map(v)) == 0;
  return false;
}

bool voxgig_isfunc(const voxgig_value* v) {
  return voxgig_is_func(v);
}

/* ===========================================================================
 * getdef
 * ===========================================================================*/

voxgig_value* voxgig_getdef(voxgig_value* val, voxgig_value* alt) {
  if (!val || voxgig_is_undef(val))
    return alt ? voxgig_retain(alt) : voxgig_new_undef();
  return voxgig_retain(val);
}

/* ===========================================================================
 * size
 * ===========================================================================*/

int64_t voxgig_size(const voxgig_value* v) {
  if (!v)
    return 0;
  if (voxgig_is_list(v))
    return (int64_t)voxgig_list_len(voxgig_as_list(v));
  if (voxgig_is_map(v))
    return (int64_t)voxgig_map_len(voxgig_as_map(v));
  if (voxgig_is_string(v))
    return (int64_t)voxgig_string_len(v);
  if (voxgig_is_int(v))
    return (int64_t)floor((double)voxgig_as_int(v));
  if (voxgig_is_double(v))
    return (int64_t)floor(voxgig_as_double(v));
  if (voxgig_is_bool(v))
    return voxgig_as_bool(v) ? 1 : 0;
  return 0;
}

/* ===========================================================================
 * slice
 * ===========================================================================*/

voxgig_value* voxgig_slice(voxgig_value* v, voxgig_value* start, voxgig_value* end, bool mutate) {
  if (voxgig_is_number(v)) {
    int64_t s =
        (voxgig_is_int(start) || voxgig_is_double(start)) ? voxgig_as_int(start) : INT64_MIN / 2;
    int64_t e = (voxgig_is_int(end) || voxgig_is_double(end)) ? voxgig_as_int(end) : INT64_MAX / 2;
    e -= 1;
    int64_t val = voxgig_as_int(v);
    if (val < s)
      val = s;
    if (val > e)
      val = e;
    return voxgig_new_int(val);
  }

  int64_t vlen = voxgig_size(v);
  bool has_start = (start != NULL && !voxgig_is_undef(start));
  bool has_end = (end != NULL && !voxgig_is_undef(end));

  int64_t s = has_start ? voxgig_as_int(start) : -1;
  int64_t e = has_end ? voxgig_as_int(end) : -1;

  if (has_end && !has_start) {
    s = 0;
    has_start = true;
  }

  if (!has_start) {
    /* No start: return as-is (deep clone for safety since canonical returns input). */
    if (voxgig_is_string(v))
      return voxgig_new_string_n(voxgig_as_string(v), voxgig_string_len(v));
    if (voxgig_is_list(v))
      return voxgig_clone(v);
    return voxgig_retain(v);
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
    if (voxgig_is_list(v)) {
      voxgig_list* src = voxgig_as_list(v);
      if (mutate) {
        for (int64_t i = 0, j = s; j < e; i++, j++) {
          voxgig_value* old = src->items[i];
          src->items[i] = voxgig_retain(src->items[j]);
          voxgig_release(old);
        }
        for (int64_t i = (int64_t)src->len - 1; i >= e - s; i--) {
          voxgig_release(src->items[i]);
        }
        src->len = (size_t)(e - s);
        return voxgig_retain(v);
      }
      voxgig_value* out = voxgig_new_list();
      for (int64_t i = s; i < e; i++) {
        voxgig_list_push(voxgig_as_list(out), voxgig_clone(voxgig_list_get(src, (size_t)i)));
      }
      return out;
    }
    if (voxgig_is_string(v)) {
      return voxgig_new_string_n(voxgig_as_string(v) + s, (size_t)(e - s));
    }
  } else {
    if (voxgig_is_list(v)) {
      if (mutate) {
        voxgig_list_clear(voxgig_as_list(v));
        return voxgig_retain(v);
      }
      return voxgig_new_list();
    }
    if (voxgig_is_string(v)) {
      return voxgig_new_string("");
    }
  }
  return voxgig_retain(v);
}

/* ===========================================================================
 * strkey
 * ===========================================================================*/

char* voxgig_strkey(voxgig_value* key) {
  if (!key || voxgig_is_undef(key))
    return xstrdup_s("");
  int t = voxgig_typify(key);
  if (t & VOXGIG_T_STRING)
    return xstrdup_s(voxgig_as_string(key));
  if (t & VOXGIG_T_BOOLEAN)
    return xstrdup_s("");
  if (t & VOXGIG_T_NUMBER) {
    if (voxgig_is_int(key)) {
      return intstr(voxgig_as_int(key));
    }
    double d = voxgig_as_double(key);
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

voxgig_strvec voxgig_keysof(voxgig_value* val) {
  voxgig_strvec out;
  voxgig_strvec_init(&out);
  if (!voxgig_is_node(val))
    return out;
  if (voxgig_is_map(val)) {
    voxgig_map* m = voxgig_as_map(val);
    for (size_t i = 0; i < m->len; i++) {
      voxgig_strvec_push_n(&out, m->entries[i].key, m->entries[i].klen);
    }
    if (out.len > 1)
      qsort(out.data, out.len, sizeof(char*), qsort_str_cmp);
  } else {
    voxgig_list* l = voxgig_as_list(val);
    for (size_t i = 0; i < l->len; i++) {
      char* s = intstr((int64_t)i);
      voxgig_strvec_push(&out, s);
      free(s);
    }
  }
  return out;
}

/* ===========================================================================
 * getelem / getprop / haskey
 * ===========================================================================*/

voxgig_value* voxgig_getelem(voxgig_value* val, voxgig_value* key, voxgig_value* alt) {
  if (!val || voxgig_is_undef(val) || !key || voxgig_is_undef(key)) {
    return alt ? voxgig_retain(alt) : voxgig_new_undef();
  }
  if (voxgig_is_list(val)) {
    voxgig_list* l = voxgig_as_list(val);
    int64_t nk = 0;
    bool ok = false;
    if (voxgig_is_int(key)) {
      nk = voxgig_as_int(key);
      ok = true;
    } else if (voxgig_is_double(key)) {
      nk = (int64_t)voxgig_as_double(key);
      ok = true;
    } else if (voxgig_is_string(key)) {
      ok = match_integer_key(voxgig_as_string(key), voxgig_string_len(key)) &&
           parse_intstr(voxgig_as_string(key), voxgig_string_len(key), &nk);
    }
    if (!ok) {
      if (alt && voxgig_is_injector(alt)) {
        return alt->as.fn.fn.inj(NULL, alt, "", NULL, alt->as.fn.ud);
      }
      return alt ? voxgig_retain(alt) : voxgig_new_undef();
    }
    if (nk < 0)
      nk = (int64_t)l->len + nk;
    if (nk < 0 || nk >= (int64_t)l->len) {
      if (alt && voxgig_is_injector(alt)) {
        return alt->as.fn.fn.inj(NULL, alt, "", NULL, alt->as.fn.ud);
      }
      return alt ? voxgig_retain(alt) : voxgig_new_undef();
    }
    voxgig_value* v = voxgig_list_get(l, (size_t)nk);
    /* Group A: null at a slot counts as "no value" — same rule as getprop.
       Canonical TS getelem returns alt when the slot is null/absent. */
    if (v && !voxgig_is_undef(v) && !voxgig_is_null(v))
      return voxgig_retain(v);
    if (alt && voxgig_is_injector(alt)) {
      return alt->as.fn.fn.inj(NULL, alt, "", NULL, alt->as.fn.ud);
    }
    return alt ? voxgig_retain(alt) : voxgig_new_undef();
  }
  if (alt && voxgig_is_injector(alt)) {
    return alt->as.fn.fn.inj(NULL, alt, "", NULL, alt->as.fn.ud);
  }
  return alt ? voxgig_retain(alt) : voxgig_new_undef();
}

voxgig_value* voxgig_getprop(voxgig_value* val, voxgig_value* key, voxgig_value* alt) {
  if (!val || voxgig_is_undef(val) || !key || voxgig_is_undef(key)) {
    return alt ? voxgig_retain(alt) : voxgig_new_undef();
  }
  if (voxgig_is_map(val)) {
    char* k = voxgig_strkey(key);
    voxgig_value* v = voxgig_map_get(voxgig_as_map(val), k);
    free(k);
    /* Group A: JSON null at the key is treated as "no value" — same rule as
       absent. Returns alt. Mirrors the canonical TS post-spec semantics. */
    if (v && !voxgig_is_undef(v) && !voxgig_is_null(v))
      return voxgig_retain(v);
    return alt ? voxgig_retain(alt) : voxgig_new_undef();
  }
  if (voxgig_is_list(val)) {
    voxgig_list* l = voxgig_as_list(val);
    int64_t nk = 0;
    if (voxgig_is_int(key)) {
      nk = voxgig_as_int(key);
    } else if (voxgig_is_double(key)) {
      nk = (int64_t)voxgig_as_double(key);
    } else if (voxgig_is_string(key)) {
      if (!match_integer_key(voxgig_as_string(key), voxgig_string_len(key)) ||
          !parse_intstr(voxgig_as_string(key), voxgig_string_len(key), &nk)) {
        return alt ? voxgig_retain(alt) : voxgig_new_undef();
      }
    } else {
      return alt ? voxgig_retain(alt) : voxgig_new_undef();
    }
    if (nk < 0 || nk >= (int64_t)l->len) {
      return alt ? voxgig_retain(alt) : voxgig_new_undef();
    }
    voxgig_value* v = voxgig_list_get(l, (size_t)nk);
    /* Group A: null at the slot also returns alt. */
    if (v && !voxgig_is_undef(v) && !voxgig_is_null(v))
      return voxgig_retain(v);
    return alt ? voxgig_retain(alt) : voxgig_new_undef();
  }
  return alt ? voxgig_retain(alt) : voxgig_new_undef();
}

bool voxgig_haskey(voxgig_value* val, voxgig_value* key) {
  voxgig_value* v = voxgig_getprop(val, key, NULL);
  /* Group A: null counts as "no value", same rule as getprop. */
  bool out = v && !voxgig_is_undef(v) && !voxgig_is_null(v);
  voxgig_release(v);
  return out;
}

/* Internal literal lookup. See header. */
voxgig_value* voxgig_lookup(voxgig_value* val, voxgig_value* key) {
  if (!val || voxgig_is_undef(val) || !key || voxgig_is_undef(key))
    return NULL;
  if (voxgig_is_map(val)) {
    char* k = voxgig_strkey(key);
    voxgig_value* v = voxgig_map_get(voxgig_as_map(val), k);
    free(k);
    return v;
  }
  if (voxgig_is_list(val)) {
    int64_t nk = 0;
    if (voxgig_is_int(key))
      nk = voxgig_as_int(key);
    else if (voxgig_is_double(key))
      nk = (int64_t)voxgig_as_double(key);
    else if (voxgig_is_string(key)) {
      if (!parse_intstr(voxgig_as_string(key), voxgig_string_len(key), &nk))
        return NULL;
    } else
      return NULL;
    voxgig_list* l = voxgig_as_list(val);
    if (nk < 0 || nk >= (int64_t)l->len)
      return NULL;
    return voxgig_list_get(l, (size_t)nk);
  }
  return NULL;
}

/* ===========================================================================
 * items_v: returns list of [key, value] tuples
 * ===========================================================================*/

voxgig_value* voxgig_items_v(voxgig_value* val) {
  voxgig_value* out = voxgig_new_list();
  if (!voxgig_is_node(val))
    return out;
  voxgig_strvec keys = voxgig_keysof(val);
  for (size_t i = 0; i < keys.len; i++) {
    voxgig_value* pair = voxgig_new_list();
    voxgig_list_push(voxgig_as_list(pair), voxgig_new_string(keys.data[i]));
    voxgig_value* keyv = voxgig_new_string(keys.data[i]);
    voxgig_value* v = voxgig_getprop(val, keyv, NULL);
    voxgig_release(keyv);
    voxgig_list_push(voxgig_as_list(pair), v);
    voxgig_list_push(voxgig_as_list(out), pair);
  }
  voxgig_strvec_free(&keys);
  return out;
}

/* ===========================================================================
 * setprop / delprop
 * ===========================================================================*/

voxgig_value* voxgig_setprop(voxgig_value* parent, voxgig_value* key, voxgig_value* val) {
  if (!parent || !voxgig_iskey(key))
    return parent;
  if (voxgig_is_map(parent)) {
    char* k = voxgig_strkey(key);
    if (val && voxgig_is_undef(val)) {
      voxgig_map_erase(voxgig_as_map(parent), k);
    } else {
      voxgig_map_set(voxgig_as_map(parent), k, val ? voxgig_retain(val) : voxgig_new_undef());
    }
    free(k);
  } else if (voxgig_is_list(parent)) {
    int64_t ki = 0;
    if (voxgig_is_int(key))
      ki = voxgig_as_int(key);
    else if (voxgig_is_double(key))
      ki = (int64_t)floor(voxgig_as_double(key));
    else if (voxgig_is_string(key)) {
      if (!parse_intstr(voxgig_as_string(key), voxgig_string_len(key), &ki))
        return parent;
    } else {
      return parent;
    }
    voxgig_list* l = voxgig_as_list(parent);
    if (ki >= 0) {
      int64_t cap = (int64_t)l->len + 1;
      if (ki > cap - 1)
        ki = cap - 1;
      if (ki < cap) {
        voxgig_list_set(l, (size_t)ki, val ? voxgig_retain(val) : voxgig_new_undef());
      }
    } else {
      voxgig_list_insert(l, 0, val ? voxgig_retain(val) : voxgig_new_undef());
    }
  }
  return parent;
}

voxgig_value* voxgig_delprop(voxgig_value* parent, voxgig_value* key) {
  if (!parent || !voxgig_iskey(key))
    return parent;
  if (voxgig_is_map(parent)) {
    char* k = voxgig_strkey(key);
    voxgig_map_erase(voxgig_as_map(parent), k);
    free(k);
  } else if (voxgig_is_list(parent)) {
    int64_t ki = 0;
    if (voxgig_is_int(key))
      ki = voxgig_as_int(key);
    else if (voxgig_is_double(key))
      ki = (int64_t)floor(voxgig_as_double(key));
    else if (voxgig_is_string(key)) {
      if (!parse_intstr(voxgig_as_string(key), voxgig_string_len(key), &ki))
        return parent;
    } else {
      return parent;
    }
    voxgig_list* l = voxgig_as_list(parent);
    if (ki >= 0 && ki < (int64_t)l->len) {
      voxgig_list_erase(l, (size_t)ki);
    }
  }
  return parent;
}

/* ===========================================================================
 * flatten / filter
 * ===========================================================================*/

static void flatten_into(voxgig_value* out, voxgig_value* list, int depth) {
  if (!voxgig_is_list(list)) {
    voxgig_list_push(voxgig_as_list(out), voxgig_retain(list));
    return;
  }
  if (depth <= 0) {
    /* Append all items as-is (one level of flattening already exhausted). */
    voxgig_list* src = voxgig_as_list(list);
    for (size_t i = 0; i < src->len; i++) {
      voxgig_list_push(voxgig_as_list(out), voxgig_retain(src->items[i]));
    }
    return;
  }
  voxgig_list* src = voxgig_as_list(list);
  for (size_t i = 0; i < src->len; i++) {
    voxgig_value* it = src->items[i];
    if (voxgig_is_list(it)) {
      flatten_into(out, it, depth - 1);
    } else {
      voxgig_list_push(voxgig_as_list(out), voxgig_retain(it));
    }
  }
}

voxgig_value* voxgig_flatten(voxgig_value* list, voxgig_value* depth) {
  if (!voxgig_is_list(list))
    return voxgig_retain(list);
  int d = 1;
  if (depth && !voxgig_is_undef(depth)) {
    if (voxgig_is_int(depth))
      d = (int)voxgig_as_int(depth);
    else if (voxgig_is_double(depth))
      d = (int)voxgig_as_double(depth);
  }
  voxgig_value* out = voxgig_new_list();
  voxgig_list* src = voxgig_as_list(list);
  for (size_t i = 0; i < src->len; i++) {
    voxgig_value* it = src->items[i];
    if (voxgig_is_list(it) && d > 0) {
      flatten_into(out, it, d - 1);
    } else {
      voxgig_list_push(voxgig_as_list(out), voxgig_retain(it));
    }
  }
  return out;
}

voxgig_value* voxgig_filter(voxgig_value* val, voxgig_itemcheck_fn check, void* ud) {
  voxgig_value* all = voxgig_items_v(val);
  voxgig_value* out = voxgig_new_list();
  voxgig_list* l = voxgig_as_list(all);
  for (size_t i = 0; i < l->len; i++) {
    voxgig_value* pair = l->items[i];
    if (check(pair, ud)) {
      voxgig_value* v = voxgig_list_get(voxgig_as_list(pair), 1);
      voxgig_list_push(voxgig_as_list(out), voxgig_retain(v));
    }
  }
  voxgig_release(all);
  return out;
}

/* ===========================================================================
 * escre / escurl / replace
 * ===========================================================================*/

char* voxgig_escre(voxgig_value* v) {
  const char* s = "";
  if (voxgig_is_string(v))
    s = voxgig_as_string(v);
  /* Equivalent to canonical TS: replace /[.*+?^${}()|[\]\\]/g with "\\$&".
     voxgig_re_escape implements the same character set. */
  return voxgig_re_escape(s);
}

char* voxgig_escurl(voxgig_value* v) {
  const char* s = "";
  if (voxgig_is_string(v))
    s = voxgig_as_string(v);
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

char* voxgig_replace_str(const char* s, const char* from, const char* to) {
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
static void stringify_inner(voxgig_value* v, char** buf, size_t* len, size_t* cap, bool top);

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

static void stringify_inner(voxgig_value* v, char** buf, size_t* len, size_t* cap, bool top) {
  if (!v || voxgig_is_undef(v)) {
    if (top)
      sb_append_str(buf, len, cap, "");
    else
      sb_append_str(buf, len, cap, "null");
    return;
  }
  if (voxgig_is_null(v)) {
    sb_append_str(buf, len, cap, "null");
    return;
  }
  if (voxgig_is_bool(v)) {
    sb_append_str(buf, len, cap, voxgig_as_bool(v) ? "true" : "false");
    return;
  }
  if (voxgig_is_int(v)) {
    char tmp[32];
    snprintf(tmp, sizeof(tmp), "%lld", (long long)voxgig_as_int(v));
    sb_append_str(buf, len, cap, tmp);
    return;
  }
  if (voxgig_is_double(v)) {
    char* s = doublestr(voxgig_as_double(v));
    sb_append_str(buf, len, cap, s);
    free(s);
    return;
  }
  if (voxgig_is_string(v)) {
    /* In TS stringify, JSON.stringify then remove all quotes. */
    sb_append(buf, len, cap, "\"", 1);
    escape_json_str(voxgig_as_string(v), voxgig_string_len(v), buf, len, cap);
    sb_append(buf, len, cap, "\"", 1);
    return;
  }
  if (voxgig_is_list(v)) {
    sb_append_str(buf, len, cap, "[");
    voxgig_list* l = voxgig_as_list(v);
    for (size_t i = 0; i < l->len; i++) {
      if (i > 0)
        sb_append_str(buf, len, cap, ",");
      stringify_inner(l->items[i], buf, len, cap, false);
    }
    sb_append_str(buf, len, cap, "]");
    return;
  }
  if (voxgig_is_map(v)) {
    sb_append_str(buf, len, cap, "{");
    voxgig_map* m = voxgig_as_map(v);
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
  if (voxgig_is_sentinel(v)) {
    char tmp[48];
    snprintf(tmp, sizeof(tmp), "{\"`$%s`\":true}", voxgig_as_sentinel(v)->name);
    sb_append_str(buf, len, cap, tmp);
    return;
  }
  if (voxgig_is_func(v)) {
    sb_append_str(buf, len, cap, "null");
    return;
  }
  sb_append_str(buf, len, cap, "null");
}

char* voxgig_stringify(voxgig_value* val, int maxlen) {
  if (!val || voxgig_is_undef(val))
    return xstrdup_s("");
  char* buf = NULL;
  size_t len = 0, cap = 0;

  if (voxgig_is_string(val)) {
    sb_append(&buf, &len, &cap, voxgig_as_string(val), voxgig_string_len(val));
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
static void jsonify_inner(voxgig_value* v, char** buf, size_t* len, size_t* cap, int indent,
                          int depth) {
  if (!v || voxgig_is_undef(v) || voxgig_is_null(v)) {
    sb_append_str(buf, len, cap, "null");
    return;
  }
  if (voxgig_is_bool(v)) {
    sb_append_str(buf, len, cap, voxgig_as_bool(v) ? "true" : "false");
    return;
  }
  if (voxgig_is_int(v)) {
    char tmp[32];
    snprintf(tmp, sizeof(tmp), "%lld", (long long)voxgig_as_int(v));
    sb_append_str(buf, len, cap, tmp);
    return;
  }
  if (voxgig_is_double(v)) {
    char* s = doublestr(voxgig_as_double(v));
    sb_append_str(buf, len, cap, s);
    free(s);
    return;
  }
  if (voxgig_is_string(v)) {
    sb_append(buf, len, cap, "\"", 1);
    escape_json_str(voxgig_as_string(v), voxgig_string_len(v), buf, len, cap);
    sb_append(buf, len, cap, "\"", 1);
    return;
  }
  if (voxgig_is_list(v)) {
    voxgig_list* l = voxgig_as_list(v);
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
  if (voxgig_is_map(v)) {
    voxgig_map* m = voxgig_as_map(v);
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

char* voxgig_jsonify(voxgig_value* val, voxgig_value* flags) {
  if (!val || voxgig_is_undef(val) || voxgig_is_null(val))
    return xstrdup_s("null");
  int indent = 2;
  int offset = 0;
  if (flags && voxgig_is_map(flags)) {
    voxgig_value* iv = voxgig_map_get(voxgig_as_map(flags), "indent");
    if (voxgig_is_int(iv))
      indent = (int)voxgig_as_int(iv);
    else if (voxgig_is_double(iv))
      indent = (int)voxgig_as_double(iv);
    voxgig_value* ov = voxgig_map_get(voxgig_as_map(flags), "offset");
    if (voxgig_is_int(ov))
      offset = (int)voxgig_as_int(ov);
    else if (voxgig_is_double(ov))
      offset = (int)voxgig_as_double(ov);
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

char* voxgig_pad(voxgig_value* str, voxgig_value* padding, voxgig_value* padchar) {
  char* s;
  if (voxgig_is_string(str))
    s = xstrdup_s(voxgig_as_string(str));
  else
    s = voxgig_stringify(str, -1);
  int p = 44;
  if (padding && !voxgig_is_undef(padding)) {
    if (voxgig_is_int(padding))
      p = (int)voxgig_as_int(padding);
    else if (voxgig_is_double(padding))
      p = (int)voxgig_as_double(padding);
  }
  char pc = ' ';
  if (voxgig_is_string(padchar) && voxgig_string_len(padchar) > 0)
    pc = voxgig_as_string(padchar)[0];
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

char* voxgig_pathify(voxgig_value* val, int startin, int endin) {
  /* Determine path: list, string, or number. */
  voxgig_value* path = NULL;
  bool path_owned = false;
  if (voxgig_is_list(val)) {
    path = val;
  } else if (voxgig_is_string(val)) {
    path = voxgig_new_list();
    path_owned = true;
    voxgig_list_push(voxgig_as_list(path), voxgig_retain(val));
  } else if (voxgig_is_number(val)) {
    path = voxgig_new_list();
    path_owned = true;
    voxgig_list_push(voxgig_as_list(path), voxgig_retain(val));
  }

  int start = startin < 0 ? 0 : startin;
  int end = endin < 0 ? 0 : endin;

  char* out = NULL;
  if (path && voxgig_is_list(path)) {
    voxgig_list* l = voxgig_as_list(path);
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
        voxgig_value* p = voxgig_list_get(l, (size_t)i);
        if (!voxgig_iskey(p))
          continue;
        char* part;
        if (voxgig_is_number(p)) {
          int64_t n;
          if (voxgig_is_int(p))
            n = voxgig_as_int(p);
          else
            n = (int64_t)floor(voxgig_as_double(p));
          part = intstr(n);
        } else {
          /* Remove dots from string. */
          const char* ps = voxgig_as_string(p);
          size_t pn = voxgig_string_len(p);
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
    if (voxgig_is_undef(val))
      s = xstrdup_s("");
    else {
      char* tmp = voxgig_stringify(val, 47);
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
    voxgig_release(path);
  return out;
}

/* ===========================================================================
 * join
 * ===========================================================================*/

char* voxgig_join_v(voxgig_value* arr, voxgig_value* sep, voxgig_value* url) {
  const char* sepstr = ",";
  if (voxgig_is_string(sep))
    sepstr = voxgig_as_string(sep);
  bool url_mode = voxgig_is_bool(url) && voxgig_as_bool(url);
  size_t seplen = strlen(sepstr);

  if (!voxgig_is_list(arr))
    return xstrdup_s("");
  voxgig_list* l = voxgig_as_list(arr);
  /* Collect string entries (filter out non-string and empty). */
  size_t* keepi = (size_t*)malloc(sizeof(size_t) * (l->len + 1));
  size_t nkeep = 0;
  for (size_t i = 0; i < l->len; i++) {
    if (voxgig_is_string(l->items[i]) && voxgig_string_len(l->items[i]) > 0) {
      keepi[nkeep++] = i;
    }
  }
  /* Now process each. */
  char* result = NULL;
  size_t rlen = 0, rcap = 0;
  bool first = true;
  for (size_t k = 0; k < nkeep; k++) {
    size_t i = keepi[k];
    const char* sin = voxgig_as_string(l->items[i]);
    size_t inlen = voxgig_string_len(l->items[i]);
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

voxgig_value* voxgig_jm_va(int n, voxgig_value** kv) {
  voxgig_value* o = voxgig_new_map();
  for (int i = 0; i < n; i += 2) {
    voxgig_value* k = (i < n) ? kv[i] : NULL;
    voxgig_value* v = (i + 1 < n) ? kv[i + 1] : NULL;
    char buf[32];
    char* key;
    if (voxgig_is_string(k)) {
      key = xstrdup_s(voxgig_as_string(k));
    } else if (k) {
      key = voxgig_stringify(k, -1);
    } else {
      snprintf(buf, sizeof(buf), "$KEY%d", i);
      key = xstrdup_s(buf);
    }
    voxgig_map_set(voxgig_as_map(o), key, v ? voxgig_retain(v) : voxgig_new_null());
    free(key);
  }
  return o;
}

voxgig_value* voxgig_jt_va(int n, voxgig_value** v) {
  voxgig_value* a = voxgig_new_list();
  for (int i = 0; i < n; i++) {
    voxgig_list_push(voxgig_as_list(a), v[i] ? voxgig_retain(v[i]) : voxgig_new_null());
  }
  return a;
}

/* ===========================================================================
 * walk
 * ===========================================================================*/

typedef struct walk_state {
  voxgig_walkapply_fn before;
  voxgig_walkapply_fn after;
  int maxdepth;
  void* ud;
} walk_state;

/* path_stack: a voxgig_value list of strings; reused/mutated for child calls (per-depth pool). */

static voxgig_value* walk_rec(walk_state* st, voxgig_value* val, voxgig_value* key,
                              voxgig_value* parent, voxgig_value* path) {
  int depth = (int)voxgig_list_len(voxgig_as_list(path));
  voxgig_value* out = val ? voxgig_retain(val) : voxgig_new_undef();
  if (st->before) {
    voxgig_value* nval = st->before(key, out, parent, path, st->ud);
    /* Callback returns a new owned ref; release the prior one unconditionally. */
    voxgig_release(out);
    out = nval;
  }

  int maxd = st->maxdepth;
  if (maxd == 0 || (maxd > 0 && maxd <= depth)) {
    return out;
  }

  if (voxgig_is_node(out)) {
    /* Build child key list (sorted as keysof returns). */
    voxgig_strvec keys = voxgig_keysof(out);
    /* Path push placeholder. */
    voxgig_list_push(voxgig_as_list(path), voxgig_new_string(""));
    for (size_t i = 0; i < keys.len; i++) {
      /* Set path[depth] = key. */
      voxgig_release(voxgig_list_get(voxgig_as_list(path), (size_t)depth));
      voxgig_as_list(path)->items[depth] = voxgig_new_string(keys.data[i]);

      voxgig_value* ckey;
      if (voxgig_is_list(out)) {
        ckey = voxgig_new_int((int64_t)i);
      } else {
        ckey = voxgig_new_string(keys.data[i]);
      }
      voxgig_value* ckeyv = voxgig_new_string(keys.data[i]);
      voxgig_value* cp = voxgig_lookup(out, ckeyv);
      voxgig_value* child = cp ? voxgig_retain(cp) : voxgig_new_undef();
      voxgig_release(ckeyv);

      voxgig_value* nchild = walk_rec(st, child, ckey, out, path);
      voxgig_release(child);
      voxgig_setprop(out, ckey, nchild);
      voxgig_release(nchild);
      voxgig_release(ckey);
    }
    /* Path pop. */
    voxgig_release(voxgig_list_get(voxgig_as_list(path), (size_t)depth));
    voxgig_as_list(path)->len--;
    voxgig_strvec_free(&keys);
  }

  if (st->after) {
    voxgig_value* nval = st->after(key, out, parent, path, st->ud);
    voxgig_release(out);
    out = nval;
  }
  return out;
}

voxgig_value* voxgig_walk(voxgig_value* val, voxgig_walkapply_fn before, voxgig_walkapply_fn after,
                          int maxdepth, void* ud) {
  walk_state st;
  st.before = before;
  st.after = after;
  st.maxdepth = (maxdepth >= 0 || maxdepth == INT_MAX) ? maxdepth : VOXGIG_MAXDEPTH;
  if (maxdepth < 0 && maxdepth != INT_MAX)
    st.maxdepth = VOXGIG_MAXDEPTH;
  st.ud = ud;
  voxgig_value* path = voxgig_new_list();
  voxgig_value* undef = voxgig_new_undef();
  voxgig_value* out = walk_rec(&st, val, undef, NULL, path);
  voxgig_release(undef);
  voxgig_release(path);
  return out;
}

/* ===========================================================================
 * merge
 * ===========================================================================*/

typedef struct merge_state {
  voxgig_value* cur_stack; /* list */
  voxgig_value* dst_stack; /* list */
  int maxdepth;
} merge_state;

static voxgig_value* merge_before(voxgig_value* key, voxgig_value* val, voxgig_value* parent,
                                  voxgig_value* path, void* ud) {
  (void)parent;
  merge_state* st = (merge_state*)ud;
  int pI = (int)voxgig_list_len(voxgig_as_list(path));

  if (st->maxdepth <= pI) {
    /* setprop(cur[pI-1], key, val) */
    voxgig_value* target = voxgig_list_get(voxgig_as_list(st->cur_stack), pI - 1);
    if (target)
      voxgig_setprop(target, key, val);
    return val ? voxgig_retain(val) : voxgig_new_undef();
  }

  if (!voxgig_is_node(val)) {
    /* cur[pI] = val */
    voxgig_list_set(voxgig_as_list(st->cur_stack), (size_t)pI,
                    val ? voxgig_retain(val) : voxgig_new_undef());
    return val ? voxgig_retain(val) : voxgig_new_undef();
  }

  /* dst[pI] = pI>0 ? getprop(dst[pI-1], key) : dst[pI]; */
  voxgig_value* tval = NULL;
  if (pI > 0) {
    voxgig_value* dp = voxgig_list_get(voxgig_as_list(st->dst_stack), (size_t)(pI - 1));
    tval = dp ? voxgig_getprop(dp, key, NULL) : voxgig_new_undef();
  } else {
    tval = voxgig_retain(voxgig_list_get(voxgig_as_list(st->dst_stack), (size_t)pI));
  }
  /* dst[pI] = tval */
  voxgig_list_set(voxgig_as_list(st->dst_stack), (size_t)pI, voxgig_retain(tval));

  int tvt = voxgig_typify(tval);
  int valt = voxgig_typify(val);

  if (voxgig_is_undef(tval)) {
    /* Destination empty; create node unless override is instance. */
    if (!(VOXGIG_T_INSTANCE & valt)) {
      voxgig_value* nc = voxgig_is_list(val) ? voxgig_new_list() : voxgig_new_map();
      voxgig_list_set(voxgig_as_list(st->cur_stack), (size_t)pI, nc);
    }
    voxgig_release(tval);
    return val ? voxgig_retain(val) : voxgig_new_undef();
  }
  if (tvt == valt) {
    voxgig_list_set(voxgig_as_list(st->cur_stack), (size_t)pI, voxgig_retain(tval));
    voxgig_release(tval);
    return val ? voxgig_retain(val) : voxgig_new_undef();
  }
  /* Override wins. */
  voxgig_list_set(voxgig_as_list(st->cur_stack), (size_t)pI, voxgig_retain(val));
  voxgig_release(tval);
  /* Don't descend; set val to undef. */
  return voxgig_new_undef();
}

static voxgig_value* merge_after(voxgig_value* key, voxgig_value* val, voxgig_value* parent,
                                 voxgig_value* path, void* ud) {
  (void)val;
  (void)parent;
  merge_state* st = (merge_state*)ud;
  int cI = (int)voxgig_list_len(voxgig_as_list(path));
  voxgig_value* target = voxgig_list_get(voxgig_as_list(st->cur_stack), (size_t)(cI - 1));
  voxgig_value* value = voxgig_list_get(voxgig_as_list(st->cur_stack), (size_t)cI);
  if (target)
    voxgig_setprop(target, key, value);
  return val ? voxgig_retain(val) : voxgig_new_undef();
}

voxgig_value* voxgig_merge(voxgig_value* val, int maxdepth) {
  /* slice(maxdepth ?? MAXDEPTH, 0) — TS numeric slice clamps below 0. */
  int md = maxdepth;
  if (md < 0)
    md = 0;
  if (md > VOXGIG_MAXDEPTH)
    md = VOXGIG_MAXDEPTH;

  if (!voxgig_is_list(val))
    return val ? voxgig_retain(val) : voxgig_new_undef();
  voxgig_list* l = voxgig_as_list(val);
  size_t n = l->len;
  if (n == 0)
    return voxgig_new_undef();
  if (n == 1)
    return voxgig_retain(l->items[0]);

  voxgig_value* out = voxgig_list_get(l, 0);
  out = out ? voxgig_retain(out) : voxgig_new_map();

  for (size_t oI = 1; oI < n; oI++) {
    voxgig_value* obj = l->items[oI];
    if (!voxgig_is_node(obj)) {
      voxgig_release(out);
      out = obj ? voxgig_retain(obj) : voxgig_new_undef();
    } else {
      merge_state st;
      st.cur_stack = voxgig_new_list();
      st.dst_stack = voxgig_new_list();
      voxgig_list_push(voxgig_as_list(st.cur_stack), voxgig_retain(out));
      voxgig_list_push(voxgig_as_list(st.dst_stack), voxgig_retain(out));
      st.maxdepth = md;

      voxgig_value* walked = voxgig_walk(obj, merge_before, merge_after, md, &st);
      /* out = walk(obj, before, after, maxdepth) — TS reassigns. The walk
         callbacks update cur[0]; we use cur[0] as the new out. */
      voxgig_value* newcur = voxgig_list_get(voxgig_as_list(st.cur_stack), 0);
      if (newcur) {
        voxgig_release(out);
        out = voxgig_retain(newcur);
      }
      voxgig_release(walked);
      voxgig_release(st.cur_stack);
      voxgig_release(st.dst_stack);
    }
  }

  if (md == 0) {
    voxgig_value* last = voxgig_list_get(l, n - 1);
    voxgig_release(out);
    if (voxgig_is_list(last))
      out = voxgig_new_list();
    else if (voxgig_is_map(last))
      out = voxgig_new_map();
    else
      out = last ? voxgig_retain(last) : voxgig_new_undef();
  }
  return out;
}

/* ===========================================================================
 * setpath / getpath
 * ===========================================================================*/

voxgig_value* voxgig_setpath(voxgig_value* store, voxgig_value* path, voxgig_value* val,
                             voxgig_injection* injdef) {
  int pt = voxgig_typify(path);
  voxgig_value* parts = NULL;
  bool parts_owned = false;
  if (pt & VOXGIG_T_LIST) {
    parts = path;
  } else if (pt & VOXGIG_T_STRING) {
    parts = voxgig_new_list();
    parts_owned = true;
    const char* s = voxgig_as_string(path);
    size_t n = voxgig_string_len(path);
    size_t i = 0;
    while (i <= n) {
      size_t j = i;
      while (j < n && s[j] != '.')
        j++;
      voxgig_list_push(voxgig_as_list(parts), voxgig_new_string_n(s + i, j - i));
      i = j + 1;
      if (j == n)
        break;
    }
  } else if (pt & VOXGIG_T_NUMBER) {
    parts = voxgig_new_list();
    parts_owned = true;
    voxgig_list_push(voxgig_as_list(parts), voxgig_retain(path));
  } else {
    return NULL;
  }

  voxgig_value* base_v = NULL;
  if (injdef && injdef->base) {
    base_v = voxgig_map_get(voxgig_as_map(store), injdef->base);
  }
  voxgig_value* parent = base_v ? base_v : store;

  size_t nparts = voxgig_list_len(voxgig_as_list(parts));
  for (size_t pI = 0; pI + 1 < nparts; pI++) {
    voxgig_value* partKey = voxgig_list_get(voxgig_as_list(parts), pI);
    voxgig_value* nextParent = voxgig_getprop(parent, partKey, NULL);
    if (!voxgig_is_node(nextParent)) {
      voxgig_release(nextParent);
      voxgig_value* nextKey = voxgig_list_get(voxgig_as_list(parts), pI + 1);
      int nkt = voxgig_typify(nextKey);
      nextParent = (nkt & VOXGIG_T_NUMBER) ? voxgig_new_list() : voxgig_new_map();
      voxgig_setprop(parent, partKey, nextParent);
      /* nextParent ref ownership: voxgig_setprop retains, so we need to release our own. */
      voxgig_value* held = nextParent;
      nextParent = voxgig_getprop(parent, partKey, NULL);
      voxgig_release(held);
    }
    parent = nextParent;
    /* Release temporary borrowed ref carefully. nextParent was returned with
       a new ref via voxgig_getprop, so it's owned now; we'll leak refcount unless
       balanced. Reduce by 1 via release at end of loop. */
    /* For simplicity, treat parent as borrowed; release at end. */
  }

  voxgig_value* lastKey = nparts > 0 ? voxgig_list_get(voxgig_as_list(parts), nparts - 1) : NULL;
  if (val && voxgig_is_delete(val)) {
    voxgig_delprop(parent, lastKey);
  } else {
    voxgig_setprop(parent, lastKey, val);
  }

  if (parts_owned)
    voxgig_release(parts);
  return parent;
}

/* getpath: see TS reference, lines 1082–1188. */
voxgig_value* voxgig_getpath(voxgig_value* store, voxgig_value* path, voxgig_injection* injdef) {
  /* Parse path into string list. */
  voxgig_strvec parts;
  voxgig_strvec_init(&parts);
  bool path_ok = false;
  if (voxgig_is_list(path)) {
    voxgig_list* l = voxgig_as_list(path);
    for (size_t i = 0; i < l->len; i++) {
      char* sk = voxgig_strkey(l->items[i]);
      voxgig_strvec_push(&parts, sk);
      free(sk);
    }
    path_ok = true;
  } else if (voxgig_is_string(path)) {
    const char* s = voxgig_as_string(path);
    size_t n = voxgig_string_len(path);
    size_t i = 0;
    while (i <= n) {
      size_t j = i;
      while (j < n && s[j] != '.')
        j++;
      voxgig_strvec_push_n(&parts, s + i, j - i);
      i = j + 1;
      if (j == n)
        break;
    }
    path_ok = true;
  } else if (voxgig_is_number(path)) {
    char* sk = voxgig_strkey(path);
    voxgig_strvec_push(&parts, sk);
    free(sk);
    path_ok = true;
  }
  if (!path_ok)
    return voxgig_new_undef();

  voxgig_value* val = store ? voxgig_retain(store) : voxgig_new_undef();
  voxgig_value* base_v = NULL;
  if (injdef && injdef->base) {
    voxgig_value* keyv = voxgig_new_string(injdef->base);
    base_v = voxgig_getprop(store, keyv, NULL);
    voxgig_release(keyv);
  }
  voxgig_value* src = base_v && !voxgig_is_undef(base_v)
                          ? base_v
                          : (store ? voxgig_retain(store) : voxgig_new_undef());
  if (!base_v || voxgig_is_undef(base_v)) {
    voxgig_release(base_v);
  }
  size_t numparts = parts.len;
  voxgig_value* dparent =
      injdef ? (injdef->dparent ? voxgig_retain(injdef->dparent) : voxgig_new_undef())
             : voxgig_new_undef();
  bool emptypath = false;
  if (!path || voxgig_is_undef(path) || !store || (numparts == 1 && parts.data[0][0] == '\0')) {
    emptypath = true;
  }

  if (emptypath) {
    voxgig_release(val);
    val = voxgig_retain(src);
  } else if (numparts > 0) {
    /* Check for $ACTIONs. */
    if (numparts == 1) {
      voxgig_value* k = voxgig_new_string(parts.data[0]);
      voxgig_value* tv = voxgig_getprop(store, k, NULL);
      voxgig_release(k);
      voxgig_release(val);
      val = tv;
    }
    if (!voxgig_is_func(val)) {
      voxgig_release(val);
      val = voxgig_retain(src);

      /* Meta path regex: ^([^$]+)\$([=~])(.+)$ */
      if (injdef && injdef->meta && numparts > 0) {
        const char* p0 = parts.data[0];
        const char* dol = strchr(p0, '$');
        if (dol && dol != p0) {
          char sep = dol[1];
          if (sep == '=' || sep == '~') {
            char* lhs = xstrndup_s(p0, dol - p0);
            char* rhs = xstrdup_s(dol + 2);
            voxgig_value* k = voxgig_new_string(lhs);
            voxgig_value* tv = voxgig_getprop(injdef->meta, k, NULL);
            voxgig_release(k);
            voxgig_release(val);
            val = tv;
            voxgig_strvec_set(&parts, 0, rhs);
            free(lhs);
            free(rhs);
          }
        }
      }

      for (size_t pI = 0; !voxgig_is_undef(val) && pI < numparts; pI++) {
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
            voxgig_value* ipath = voxgig_new_string(inner);
            free(inner);
            voxgig_value* iv = voxgig_getpath(src, ipath, NULL);
            voxgig_release(ipath);
            free(part);
            part = voxgig_stringify(iv, -1);
            voxgig_release(iv);
          }
        } else if (injdef && strncmp(part, "$REF:", 5) == 0) {
          size_t pl = strlen(part);
          if (pl > 5 && part[pl - 1] == '$') {
            char* inner = xstrndup_s(part + 5, pl - 6);
            voxgig_value* spec_key = voxgig_new_string("$SPEC");
            voxgig_value* spec = voxgig_getprop(store, spec_key, NULL);
            voxgig_release(spec_key);
            voxgig_value* ipath = voxgig_new_string(inner);
            free(inner);
            voxgig_value* iv = voxgig_getpath(spec, ipath, NULL);
            voxgig_release(spec);
            voxgig_release(ipath);
            free(part);
            part = voxgig_stringify(iv, -1);
            voxgig_release(iv);
          }
        } else if (injdef && strncmp(part, "$META:", 6) == 0) {
          size_t pl = strlen(part);
          if (pl > 6 && part[pl - 1] == '$') {
            char* inner = xstrndup_s(part + 6, pl - 7);
            voxgig_value* ipath = voxgig_new_string(inner);
            free(inner);
            voxgig_value* iv = voxgig_getpath(injdef->meta, ipath, NULL);
            voxgig_release(ipath);
            free(part);
            part = voxgig_stringify(iv, -1);
            voxgig_release(iv);
          }
        }

        /* $$ escapes $ */
        char* unescaped = voxgig_replace_str(part, "$$", "$");
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
              voxgig_release(val);
              val = dparent ? voxgig_retain(dparent) : voxgig_new_undef();
            } else {
              /* fullpath = flatten([slice(dpath, -ascends), parts.slice(pI+1)])
               * NOTE: TS slice with negative start clamps via end = vlen+start, so
               * slice(arr, -ascends) keeps the FIRST (vlen-ascends) elements. */
              voxgig_value* fp = voxgig_new_list();
              int dpathlen = (int)(injdef ? injdef->dpath.len : 0);
              int dend = dpathlen - ascends;
              if (dend < 0)
                dend = 0;
              for (int di = 0; di < dend; di++) {
                voxgig_list_push(voxgig_as_list(fp), voxgig_new_string(injdef->dpath.data[di]));
              }
              for (size_t pj = pI + 1; pj < numparts; pj++) {
                voxgig_list_push(voxgig_as_list(fp), voxgig_new_string(parts.data[pj]));
              }
              if (ascends <= dpathlen) {
                voxgig_release(val);
                val = voxgig_getpath(store, fp, NULL);
              } else {
                voxgig_release(val);
                val = voxgig_new_undef();
              }
              voxgig_release(fp);
              free(part);
              break;
            }
          } else {
            voxgig_release(val);
            val = dparent ? voxgig_retain(dparent) : voxgig_new_undef();
          }
        } else {
          voxgig_value* k = voxgig_new_string(part);
          voxgig_value* nv = voxgig_lookup(val, k);
          voxgig_release(k);
          voxgig_value* tv = nv ? voxgig_retain(nv) : voxgig_new_undef();
          voxgig_release(val);
          val = tv;
        }
        free(part);
      }
    }
  }

  voxgig_release(dparent);
  voxgig_release(src);
  voxgig_strvec_free(&parts);

  /* Handler from injdef. */
  if (injdef && injdef->handler_val && voxgig_is_func(injdef->handler_val)) {
    char* ref = voxgig_pathify(path, 0, 0);
    voxgig_value* tv =
        injdef->handler_val->as.fn.fn.inj(injdef, val, ref, store, injdef->handler_val->as.fn.ud);
    free(ref);
    voxgig_release(val);
    val = tv;
  }

  return val ? val : voxgig_new_undef();
}
