/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

#include "value.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ===========================================================================
 * Sentinel singletons
 * ===========================================================================*/

static const vs_sentinel SKIP_SENTINEL = {"SKIP"};
static const vs_sentinel DELETE_SENTINEL = {"DELETE"};

const vs_sentinel* vs_skip_sentinel(void) {
  return &SKIP_SENTINEL;
}

const vs_sentinel* vs_delete_sentinel(void) {
  return &DELETE_SENTINEL;
}

/* ===========================================================================
 * Allocators
 * ===========================================================================*/

static vs_value* alloc_value(vs_kind k) {
  vs_value* v = (vs_value*)calloc(1, sizeof(vs_value));
  if (!v) {
    fprintf(stderr, "voxgig-struct: out of memory\n");
    abort();
  }
  v->kind = k;
  v->refcount = 1;
  return v;
}

static char* xstrndup(const char* s, size_t n) {
  char* p = (char*)malloc(n + 1);
  if (!p) {
    fprintf(stderr, "voxgig-struct: out of memory\n");
    abort();
  }
  if (n)
    memcpy(p, s, n);
  p[n] = '\0';
  return p;
}

/* ===========================================================================
 * Constructors
 * ===========================================================================*/

vs_value* vs_new_undef(void) {
  return alloc_value(VS_VAL_UNDEF);
}

vs_value* vs_new_null(void) {
  return alloc_value(VS_VAL_NULL);
}

vs_value* vs_new_bool(bool b) {
  vs_value* v = alloc_value(VS_VAL_BOOL);
  v->as.b = b;
  return v;
}

vs_value* vs_new_int(int64_t i) {
  vs_value* v = alloc_value(VS_VAL_INT);
  v->as.i = i;
  return v;
}

vs_value* vs_new_double(double d) {
  vs_value* v = alloc_value(VS_VAL_DOUBLE);
  v->as.d = d;
  return v;
}

vs_value* vs_new_string(const char* s) {
  return vs_new_string_n(s, s ? strlen(s) : 0);
}

vs_value* vs_new_string_n(const char* s, size_t n) {
  vs_value* v = alloc_value(VS_VAL_STRING);
  v->as.s.data = xstrndup(s ? s : "", n);
  v->as.s.len = n;
  return v;
}

vs_value* vs_new_string_take(char* s, size_t n) {
  vs_value* v = alloc_value(VS_VAL_STRING);
  v->as.s.data = s;
  v->as.s.len = n;
  return v;
}

vs_value* vs_new_list(void) {
  vs_value* v = alloc_value(VS_VAL_LIST);
  vs_list* l = (vs_list*)calloc(1, sizeof(vs_list));
  if (!l)
    abort();
  l->refcount = 1;
  v->as.lst = l;
  return v;
}

vs_value* vs_new_map(void) {
  vs_value* v = alloc_value(VS_VAL_MAP);
  vs_map* m = (vs_map*)calloc(1, sizeof(vs_map));
  if (!m)
    abort();
  m->refcount = 1;
  v->as.map = m;
  return v;
}

vs_value* vs_new_injector(vs_injector_fn fn, void* ud) {
  vs_value* v = alloc_value(VS_VAL_FUNC);
  v->as.fn.kind = VS_FUNC_INJECTOR;
  v->as.fn.fn.inj = fn;
  v->as.fn.ud = ud;
  return v;
}

vs_value* vs_new_modify(vs_modify_fn fn, void* ud) {
  vs_value* v = alloc_value(VS_VAL_FUNC);
  v->as.fn.kind = VS_FUNC_MODIFY;
  v->as.fn.fn.mod = fn;
  v->as.fn.ud = ud;
  return v;
}

vs_value* vs_new_sentinel(const vs_sentinel* s) {
  vs_value* v = alloc_value(VS_VAL_SENTINEL);
  v->as.sentinel = s;
  return v;
}

vs_value* vs_new_skip(void) {
  return vs_new_sentinel(vs_skip_sentinel());
}

vs_value* vs_new_delete(void) {
  return vs_new_sentinel(vs_delete_sentinel());
}

/* ===========================================================================
 * Refcount + free
 * ===========================================================================*/

static void list_free(vs_list* l) {
  if (!l)
    return;
  if (--l->refcount > 0)
    return;
  for (size_t i = 0; i < l->len; i++) {
    vs_release(l->items[i]);
  }
  free(l->items);
  free(l);
}

static void map_free(vs_map* m) {
  if (!m)
    return;
  if (--m->refcount > 0)
    return;
  for (size_t i = 0; i < m->len; i++) {
    free(m->entries[i].key);
    vs_release(m->entries[i].value);
  }
  free(m->entries);
  free(m->ihash_slots);
  free(m);
}

vs_value* vs_retain(vs_value* v) {
  if (v)
    v->refcount++;
  return v;
}

void vs_release(vs_value* v) {
  if (!v)
    return;
  if (--v->refcount > 0)
    return;
  switch (v->kind) {
  case VS_VAL_STRING:
    free(v->as.s.data);
    break;
  case VS_VAL_LIST:
    list_free(v->as.lst);
    break;
  case VS_VAL_MAP:
    map_free(v->as.map);
    break;
  default:
    break;
  }
  free(v);
}

/* ===========================================================================
 * Deep clone (forks list/map containers; preserves sentinel identity)
 * ===========================================================================*/

vs_value* vs_clone(vs_value* v) {
  if (!v)
    return vs_new_undef();
  switch (v->kind) {
  case VS_VAL_UNDEF:
    return vs_new_undef();
  case VS_VAL_NULL:
    return vs_new_null();
  case VS_VAL_BOOL:
    return vs_new_bool(v->as.b);
  case VS_VAL_INT:
    return vs_new_int(v->as.i);
  case VS_VAL_DOUBLE:
    return vs_new_double(v->as.d);
  case VS_VAL_STRING:
    return vs_new_string_n(v->as.s.data, v->as.s.len);
  case VS_VAL_SENTINEL:
    return vs_new_sentinel(v->as.sentinel);
  case VS_VAL_FUNC: {
    vs_value* o = alloc_value(VS_VAL_FUNC);
    o->as.fn = v->as.fn;
    return o;
  }
  case VS_VAL_LIST: {
    vs_value* o = vs_new_list();
    vs_list* src = v->as.lst;
    vs_list_reserve(o->as.lst, src->len);
    for (size_t i = 0; i < src->len; i++) {
      vs_list_push(o->as.lst, vs_clone(src->items[i]));
    }
    return o;
  }
  case VS_VAL_MAP: {
    vs_value* o = vs_new_map();
    vs_map* src = v->as.map;
    for (size_t i = 0; i < src->len; i++) {
      vs_map_set_n(o->as.map, src->entries[i].key, src->entries[i].klen,
                   vs_clone(src->entries[i].value));
    }
    return o;
  }
  }
  return vs_new_undef();
}

/* ===========================================================================
 * Predicates / accessors
 * ===========================================================================*/

bool vs_is_undef(const vs_value* v) {
  return !v || v->kind == VS_VAL_UNDEF;
}
bool vs_is_null(const vs_value* v) {
  return v && v->kind == VS_VAL_NULL;
}
bool vs_is_bool(const vs_value* v) {
  return v && v->kind == VS_VAL_BOOL;
}
bool vs_is_int(const vs_value* v) {
  return v && v->kind == VS_VAL_INT;
}
bool vs_is_double(const vs_value* v) {
  return v && v->kind == VS_VAL_DOUBLE;
}
bool vs_is_number(const vs_value* v) {
  return vs_is_int(v) || vs_is_double(v);
}
bool vs_is_string(const vs_value* v) {
  return v && v->kind == VS_VAL_STRING;
}
bool vs_is_list(const vs_value* v) {
  return v && v->kind == VS_VAL_LIST;
}
bool vs_is_map(const vs_value* v) {
  return v && v->kind == VS_VAL_MAP;
}
bool vs_is_node(const vs_value* v) {
  return vs_is_list(v) || vs_is_map(v);
}
bool vs_is_func(const vs_value* v) {
  return v && v->kind == VS_VAL_FUNC;
}
bool vs_is_injector(const vs_value* v) {
  return vs_is_func(v) && v->as.fn.kind == VS_FUNC_INJECTOR;
}
bool vs_is_modify(const vs_value* v) {
  return vs_is_func(v) && v->as.fn.kind == VS_FUNC_MODIFY;
}
bool vs_is_sentinel(const vs_value* v) {
  return v && v->kind == VS_VAL_SENTINEL;
}
bool vs_is_skip(const vs_value* v) {
  return vs_is_sentinel(v) && v->as.sentinel == vs_skip_sentinel();
}
bool vs_is_delete(const vs_value* v) {
  return vs_is_sentinel(v) && v->as.sentinel == vs_delete_sentinel();
}

bool vs_as_bool(const vs_value* v) {
  return v ? v->as.b : false;
}
int64_t vs_as_int(const vs_value* v) {
  if (!v)
    return 0;
  if (v->kind == VS_VAL_INT)
    return v->as.i;
  if (v->kind == VS_VAL_DOUBLE)
    return (int64_t)v->as.d;
  return 0;
}
double vs_as_double(const vs_value* v) {
  if (!v)
    return 0.0;
  if (v->kind == VS_VAL_DOUBLE)
    return v->as.d;
  if (v->kind == VS_VAL_INT)
    return (double)v->as.i;
  return 0.0;
}
const char* vs_as_string(const vs_value* v) {
  return (v && v->kind == VS_VAL_STRING) ? v->as.s.data : "";
}
size_t vs_string_len(const vs_value* v) {
  return (v && v->kind == VS_VAL_STRING) ? v->as.s.len : 0;
}
vs_list* vs_as_list(const vs_value* v) {
  return (v && v->kind == VS_VAL_LIST) ? v->as.lst : NULL;
}
vs_map* vs_as_map(const vs_value* v) {
  return (v && v->kind == VS_VAL_MAP) ? v->as.map : NULL;
}
const vs_sentinel* vs_as_sentinel(const vs_value* v) {
  return (v && v->kind == VS_VAL_SENTINEL) ? v->as.sentinel : NULL;
}

/* ===========================================================================
 * List operations
 * ===========================================================================*/

size_t vs_list_len(const vs_list* l) {
  return l ? l->len : 0;
}

vs_value* vs_list_get(const vs_list* l, size_t i) {
  if (!l || i >= l->len)
    return NULL;
  return l->items[i];
}

void vs_list_reserve(vs_list* l, size_t cap) {
  if (!l || cap <= l->cap)
    return;
  size_t nc = l->cap == 0 ? 8 : l->cap;
  while (nc < cap)
    nc *= 2;
  vs_value** ni = (vs_value**)realloc(l->items, nc * sizeof(vs_value*));
  if (!ni)
    abort();
  l->items = ni;
  l->cap = nc;
}

void vs_list_push(vs_list* l, vs_value* v) {
  vs_list_reserve(l, l->len + 1);
  l->items[l->len++] = v ? v : vs_new_undef();
}

void vs_list_set(vs_list* l, size_t i, vs_value* v) {
  if (!l) {
    vs_release(v);
    return;
  }
  if (i >= l->len) {
    while (l->len < i) {
      vs_list_push(l, vs_new_undef());
    }
    vs_list_push(l, v);
    return;
  }
  vs_release(l->items[i]);
  l->items[i] = v ? v : vs_new_undef();
}

void vs_list_erase(vs_list* l, size_t i) {
  if (!l || i >= l->len)
    return;
  vs_release(l->items[i]);
  for (size_t j = i + 1; j < l->len; j++) {
    l->items[j - 1] = l->items[j];
  }
  l->len--;
}

void vs_list_insert(vs_list* l, size_t i, vs_value* v) {
  if (!l) {
    vs_release(v);
    return;
  }
  vs_list_reserve(l, l->len + 1);
  if (i > l->len)
    i = l->len;
  for (size_t j = l->len; j > i; j--) {
    l->items[j] = l->items[j - 1];
  }
  l->items[i] = v ? v : vs_new_undef();
  l->len++;
}

void vs_list_clear(vs_list* l) {
  if (!l)
    return;
  for (size_t i = 0; i < l->len; i++)
    vs_release(l->items[i]);
  l->len = 0;
}

/* ===========================================================================
 * Map operations
 * ===========================================================================*/

/* FNV-1a 64-bit hash. */
static uint64_t map_hash(const char* k, size_t n) {
  uint64_t h = 0xcbf29ce484222325ULL;
  for (size_t i = 0; i < n; i++) {
    h ^= (unsigned char)k[i];
    h *= 0x100000001b3ULL;
  }
  return h;
}

static void map_index_rebuild(vs_map* m, size_t new_cap) {
  size_t* slots = (size_t*)calloc(new_cap, sizeof(size_t));
  if (!slots)
    abort();
  for (size_t i = 0; i < m->len; i++) {
    uint64_t h = map_hash(m->entries[i].key, m->entries[i].klen);
    size_t mask = new_cap - 1;
    size_t s = (size_t)(h & mask);
    while (slots[s] != 0)
      s = (s + 1) & mask;
    slots[s] = i + 1;
  }
  free(m->ihash_slots);
  m->ihash_slots = slots;
  m->ihash_cap = new_cap;
}

static void map_index_ensure(vs_map* m) {
  size_t need = m->ihash_cap == 0 ? 16 : m->ihash_cap;
  while (need < m->len * 2)
    need *= 2;
  /* Always rebuild on insert: cheapest correct option. The hashtable holds
   * positional indices, so a single insert doesn't invalidate prior slots,
   * but the new entry must be added — rebuilding handles both. */
  map_index_rebuild(m, need);
}

size_t vs_map_len(const vs_map* m) {
  return m ? m->len : 0;
}

const char* vs_map_key_at(const vs_map* m, size_t i) {
  if (!m || i >= m->len)
    return NULL;
  return m->entries[i].key;
}

vs_value* vs_map_val_at(const vs_map* m, size_t i) {
  if (!m || i >= m->len)
    return NULL;
  return m->entries[i].value;
}

static size_t map_find_idx(const vs_map* m, const char* key, size_t n) {
  if (!m || m->ihash_cap == 0)
    return (size_t)-1;
  uint64_t h = map_hash(key, n);
  size_t mask = m->ihash_cap - 1;
  size_t s = (size_t)(h & mask);
  while (m->ihash_slots[s] != 0) {
    size_t idx = m->ihash_slots[s] - 1;
    if (m->entries[idx].klen == n && memcmp(m->entries[idx].key, key, n) == 0) {
      return idx;
    }
    s = (s + 1) & mask;
  }
  return (size_t)-1;
}

vs_value* vs_map_get(const vs_map* m, const char* key) {
  return vs_map_get_n(m, key, key ? strlen(key) : 0);
}

vs_value* vs_map_get_n(const vs_map* m, const char* key, size_t n) {
  size_t i = map_find_idx(m, key, n);
  if (i == (size_t)-1)
    return NULL;
  return m->entries[i].value;
}

bool vs_map_has(const vs_map* m, const char* key) {
  return vs_map_get(m, key) != NULL;
}

void vs_map_set(vs_map* m, const char* key, vs_value* v) {
  vs_map_set_n(m, key, key ? strlen(key) : 0, v);
}

void vs_map_set_n(vs_map* m, const char* key, size_t n, vs_value* v) {
  if (!m) {
    vs_release(v);
    return;
  }
  size_t idx = map_find_idx(m, key, n);
  if (idx != (size_t)-1) {
    vs_release(m->entries[idx].value);
    m->entries[idx].value = v ? v : vs_new_undef();
    return;
  }
  if (m->len + 1 > m->cap) {
    size_t nc = m->cap == 0 ? 8 : m->cap * 2;
    vs_map_entry* ne = (vs_map_entry*)realloc(m->entries, nc * sizeof(vs_map_entry));
    if (!ne)
      abort();
    m->entries = ne;
    m->cap = nc;
  }
  m->entries[m->len].key = xstrndup(key ? key : "", n);
  m->entries[m->len].klen = n;
  m->entries[m->len].value = v ? v : vs_new_undef();
  m->len++;
  map_index_ensure(m);
}

bool vs_map_erase(vs_map* m, const char* key) {
  if (!m)
    return false;
  size_t n = key ? strlen(key) : 0;
  size_t idx = map_find_idx(m, key, n);
  if (idx == (size_t)-1)
    return false;
  free(m->entries[idx].key);
  vs_release(m->entries[idx].value);
  for (size_t j = idx + 1; j < m->len; j++) {
    m->entries[j - 1] = m->entries[j];
  }
  m->len--;
  /* Rebuild the index because positional shifts invalidate slots. */
  map_index_rebuild(m, m->ihash_cap == 0 ? 16 : m->ihash_cap);
  return true;
}

void vs_map_clear(vs_map* m) {
  if (!m)
    return;
  for (size_t i = 0; i < m->len; i++) {
    free(m->entries[i].key);
    vs_release(m->entries[i].value);
  }
  m->len = 0;
  if (m->ihash_slots) {
    memset(m->ihash_slots, 0, m->ihash_cap * sizeof(size_t));
  }
}

/* ===========================================================================
 * Equality
 * ===========================================================================*/

bool vs_equals(const vs_value* a, const vs_value* b) {
  if (a == b)
    return true;
  if (!a || !b)
    return false;
  /* Sentinels: pointer identity. */
  if (vs_is_sentinel(a) || vs_is_sentinel(b)) {
    return vs_is_sentinel(a) && vs_is_sentinel(b) && a->as.sentinel == b->as.sentinel;
  }
  /* Cross-type number equality. */
  if (vs_is_number(a) && vs_is_number(b)) {
    if (vs_is_int(a) && vs_is_int(b))
      return a->as.i == b->as.i;
    return vs_as_double(a) == vs_as_double(b);
  }
  if (a->kind != b->kind)
    return false;
  switch (a->kind) {
  case VS_VAL_UNDEF:
  case VS_VAL_NULL:
    return true;
  case VS_VAL_BOOL:
    return a->as.b == b->as.b;
  case VS_VAL_STRING:
    return a->as.s.len == b->as.s.len && memcmp(a->as.s.data, b->as.s.data, a->as.s.len) == 0;
  case VS_VAL_LIST: {
    vs_list* la = a->as.lst;
    vs_list* lb = b->as.lst;
    if (la == lb)
      return true;
    if (la->len != lb->len)
      return false;
    for (size_t i = 0; i < la->len; i++) {
      if (!vs_equals(la->items[i], lb->items[i]))
        return false;
    }
    return true;
  }
  case VS_VAL_MAP: {
    vs_map* ma = a->as.map;
    vs_map* mb = b->as.map;
    if (ma == mb)
      return true;
    if (ma->len != mb->len)
      return false;
    for (size_t i = 0; i < ma->len; i++) {
      vs_value* bv = vs_map_get_n(mb, ma->entries[i].key, ma->entries[i].klen);
      if (!bv)
        return false;
      if (!vs_equals(ma->entries[i].value, bv))
        return false;
    }
    return true;
  }
  case VS_VAL_FUNC:
    return false;
  default:
    return false;
  }
}
