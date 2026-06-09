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

static const voxgig_sentinel SKIP_SENTINEL = {"SKIP"};
static const voxgig_sentinel DELETE_SENTINEL = {"DELETE"};

const voxgig_sentinel* voxgig_skip_sentinel(void) {
  return &SKIP_SENTINEL;
}

const voxgig_sentinel* voxgig_delete_sentinel(void) {
  return &DELETE_SENTINEL;
}

/* ===========================================================================
 * Allocators
 * ===========================================================================*/

static voxgig_value* alloc_value(voxgig_kind k) {
  voxgig_value* v = (voxgig_value*)calloc(1, sizeof(voxgig_value));
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

voxgig_value* voxgig_new_undef(void) {
  return alloc_value(VOXGIG_VAL_UNDEF);
}

voxgig_value* voxgig_new_null(void) {
  return alloc_value(VOXGIG_VAL_NULL);
}

voxgig_value* voxgig_new_bool(bool b) {
  voxgig_value* v = alloc_value(VOXGIG_VAL_BOOL);
  v->as.b = b;
  return v;
}

voxgig_value* voxgig_new_int(int64_t i) {
  voxgig_value* v = alloc_value(VOXGIG_VAL_INT);
  v->as.i = i;
  return v;
}

voxgig_value* voxgig_new_double(double d) {
  voxgig_value* v = alloc_value(VOXGIG_VAL_DOUBLE);
  v->as.d = d;
  return v;
}

voxgig_value* voxgig_new_string(const char* s) {
  return voxgig_new_string_n(s, s ? strlen(s) : 0);
}

voxgig_value* voxgig_new_string_n(const char* s, size_t n) {
  voxgig_value* v = alloc_value(VOXGIG_VAL_STRING);
  v->as.s.data = xstrndup(s ? s : "", n);
  v->as.s.len = n;
  return v;
}

voxgig_value* voxgig_new_string_take(char* s, size_t n) {
  voxgig_value* v = alloc_value(VOXGIG_VAL_STRING);
  v->as.s.data = s;
  v->as.s.len = n;
  return v;
}

voxgig_value* voxgig_new_list(void) {
  voxgig_value* v = alloc_value(VOXGIG_VAL_LIST);
  voxgig_list* l = (voxgig_list*)calloc(1, sizeof(voxgig_list));
  if (!l)
    abort();
  l->refcount = 1;
  v->as.lst = l;
  return v;
}

voxgig_value* voxgig_new_map(void) {
  voxgig_value* v = alloc_value(VOXGIG_VAL_MAP);
  voxgig_map* m = (voxgig_map*)calloc(1, sizeof(voxgig_map));
  if (!m)
    abort();
  m->refcount = 1;
  v->as.map = m;
  return v;
}

voxgig_value* voxgig_new_injector(voxgig_injector_fn fn, void* ud) {
  voxgig_value* v = alloc_value(VOXGIG_VAL_FUNC);
  v->as.fn.kind = VOXGIG_FUNC_INJECTOR;
  v->as.fn.fn.inj = fn;
  v->as.fn.ud = ud;
  return v;
}

voxgig_value* voxgig_new_modify(voxgig_modify_fn fn, void* ud) {
  voxgig_value* v = alloc_value(VOXGIG_VAL_FUNC);
  v->as.fn.kind = VOXGIG_FUNC_MODIFY;
  v->as.fn.fn.mod = fn;
  v->as.fn.ud = ud;
  return v;
}

voxgig_value* voxgig_new_sentinel(const voxgig_sentinel* s) {
  voxgig_value* v = alloc_value(VOXGIG_VAL_SENTINEL);
  v->as.sentinel = s;
  return v;
}

voxgig_value* voxgig_new_skip(void) {
  return voxgig_new_sentinel(voxgig_skip_sentinel());
}

voxgig_value* voxgig_new_delete(void) {
  return voxgig_new_sentinel(voxgig_delete_sentinel());
}

/* ===========================================================================
 * Refcount + free
 * ===========================================================================*/

static void list_free(voxgig_list* l) {
  if (!l)
    return;
  if (--l->refcount > 0)
    return;
  for (size_t i = 0; i < l->len; i++) {
    voxgig_release(l->items[i]);
  }
  free(l->items);
  free(l);
}

static void map_free(voxgig_map* m) {
  if (!m)
    return;
  if (--m->refcount > 0)
    return;
  for (size_t i = 0; i < m->len; i++) {
    free(m->entries[i].key);
    voxgig_release(m->entries[i].value);
  }
  free(m->entries);
  free(m->ihash_slots);
  free(m);
}

voxgig_value* voxgig_retain(voxgig_value* v) {
  if (v)
    v->refcount++;
  return v;
}

void voxgig_release(voxgig_value* v) {
  if (!v)
    return;
  if (--v->refcount > 0)
    return;
  switch (v->kind) {
  case VOXGIG_VAL_STRING:
    free(v->as.s.data);
    break;
  case VOXGIG_VAL_LIST:
    list_free(v->as.lst);
    break;
  case VOXGIG_VAL_MAP:
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

voxgig_value* voxgig_clone(voxgig_value* v) {
  if (!v)
    return voxgig_new_undef();
  switch (v->kind) {
  case VOXGIG_VAL_UNDEF:
    return voxgig_new_undef();
  case VOXGIG_VAL_NULL:
    return voxgig_new_null();
  case VOXGIG_VAL_BOOL:
    return voxgig_new_bool(v->as.b);
  case VOXGIG_VAL_INT:
    return voxgig_new_int(v->as.i);
  case VOXGIG_VAL_DOUBLE:
    return voxgig_new_double(v->as.d);
  case VOXGIG_VAL_STRING:
    return voxgig_new_string_n(v->as.s.data, v->as.s.len);
  case VOXGIG_VAL_SENTINEL:
    return voxgig_new_sentinel(v->as.sentinel);
  case VOXGIG_VAL_FUNC: {
    voxgig_value* o = alloc_value(VOXGIG_VAL_FUNC);
    o->as.fn = v->as.fn;
    return o;
  }
  case VOXGIG_VAL_LIST: {
    voxgig_value* o = voxgig_new_list();
    voxgig_list* src = v->as.lst;
    voxgig_list_reserve(o->as.lst, src->len);
    for (size_t i = 0; i < src->len; i++) {
      voxgig_list_push(o->as.lst, voxgig_clone(src->items[i]));
    }
    return o;
  }
  case VOXGIG_VAL_MAP: {
    voxgig_value* o = voxgig_new_map();
    voxgig_map* src = v->as.map;
    for (size_t i = 0; i < src->len; i++) {
      voxgig_map_set_n(o->as.map, src->entries[i].key, src->entries[i].klen,
                       voxgig_clone(src->entries[i].value));
    }
    return o;
  }
  }
  return voxgig_new_undef();
}

/* ===========================================================================
 * Predicates / accessors
 * ===========================================================================*/

bool voxgig_is_undef(const voxgig_value* v) {
  return !v || v->kind == VOXGIG_VAL_UNDEF;
}
bool voxgig_is_null(const voxgig_value* v) {
  return v && v->kind == VOXGIG_VAL_NULL;
}
bool voxgig_is_bool(const voxgig_value* v) {
  return v && v->kind == VOXGIG_VAL_BOOL;
}
bool voxgig_is_int(const voxgig_value* v) {
  return v && v->kind == VOXGIG_VAL_INT;
}
bool voxgig_is_double(const voxgig_value* v) {
  return v && v->kind == VOXGIG_VAL_DOUBLE;
}
bool voxgig_is_number(const voxgig_value* v) {
  return voxgig_is_int(v) || voxgig_is_double(v);
}
bool voxgig_is_string(const voxgig_value* v) {
  return v && v->kind == VOXGIG_VAL_STRING;
}
bool voxgig_is_list(const voxgig_value* v) {
  return v && v->kind == VOXGIG_VAL_LIST;
}
bool voxgig_is_map(const voxgig_value* v) {
  return v && v->kind == VOXGIG_VAL_MAP;
}
bool voxgig_is_node(const voxgig_value* v) {
  return voxgig_is_list(v) || voxgig_is_map(v);
}
bool voxgig_is_func(const voxgig_value* v) {
  return v && v->kind == VOXGIG_VAL_FUNC;
}
bool voxgig_is_injector(const voxgig_value* v) {
  return voxgig_is_func(v) && v->as.fn.kind == VOXGIG_FUNC_INJECTOR;
}
bool voxgig_is_modify(const voxgig_value* v) {
  return voxgig_is_func(v) && v->as.fn.kind == VOXGIG_FUNC_MODIFY;
}
bool voxgig_is_sentinel(const voxgig_value* v) {
  return v && v->kind == VOXGIG_VAL_SENTINEL;
}
bool voxgig_is_skip(const voxgig_value* v) {
  return voxgig_is_sentinel(v) && v->as.sentinel == voxgig_skip_sentinel();
}
bool voxgig_is_delete(const voxgig_value* v) {
  return voxgig_is_sentinel(v) && v->as.sentinel == voxgig_delete_sentinel();
}

bool voxgig_as_bool(const voxgig_value* v) {
  return v ? v->as.b : false;
}
int64_t voxgig_as_int(const voxgig_value* v) {
  if (!v)
    return 0;
  if (v->kind == VOXGIG_VAL_INT)
    return v->as.i;
  if (v->kind == VOXGIG_VAL_DOUBLE)
    return (int64_t)v->as.d;
  return 0;
}
double voxgig_as_double(const voxgig_value* v) {
  if (!v)
    return 0.0;
  if (v->kind == VOXGIG_VAL_DOUBLE)
    return v->as.d;
  if (v->kind == VOXGIG_VAL_INT)
    return (double)v->as.i;
  return 0.0;
}
const char* voxgig_as_string(const voxgig_value* v) {
  return (v && v->kind == VOXGIG_VAL_STRING) ? v->as.s.data : "";
}
size_t voxgig_string_len(const voxgig_value* v) {
  return (v && v->kind == VOXGIG_VAL_STRING) ? v->as.s.len : 0;
}
voxgig_list* voxgig_as_list(const voxgig_value* v) {
  return (v && v->kind == VOXGIG_VAL_LIST) ? v->as.lst : NULL;
}
voxgig_map* voxgig_as_map(const voxgig_value* v) {
  return (v && v->kind == VOXGIG_VAL_MAP) ? v->as.map : NULL;
}
const voxgig_sentinel* voxgig_as_sentinel(const voxgig_value* v) {
  return (v && v->kind == VOXGIG_VAL_SENTINEL) ? v->as.sentinel : NULL;
}

/* ===========================================================================
 * List operations
 * ===========================================================================*/

size_t voxgig_list_len(const voxgig_list* l) {
  return l ? l->len : 0;
}

voxgig_value* voxgig_list_get(const voxgig_list* l, size_t i) {
  if (!l || i >= l->len)
    return NULL;
  return l->items[i];
}

void voxgig_list_reserve(voxgig_list* l, size_t cap) {
  if (!l || cap <= l->cap)
    return;
  size_t nc = l->cap == 0 ? 8 : l->cap;
  while (nc < cap)
    nc *= 2;
  voxgig_value** ni = (voxgig_value**)realloc(l->items, nc * sizeof(voxgig_value*));
  if (!ni)
    abort();
  l->items = ni;
  l->cap = nc;
}

void voxgig_list_push(voxgig_list* l, voxgig_value* v) {
  voxgig_list_reserve(l, l->len + 1);
  l->items[l->len++] = v ? v : voxgig_new_undef();
}

void voxgig_list_set(voxgig_list* l, size_t i, voxgig_value* v) {
  if (!l) {
    voxgig_release(v);
    return;
  }
  if (i >= l->len) {
    while (l->len < i) {
      voxgig_list_push(l, voxgig_new_undef());
    }
    voxgig_list_push(l, v);
    return;
  }
  voxgig_release(l->items[i]);
  l->items[i] = v ? v : voxgig_new_undef();
}

void voxgig_list_erase(voxgig_list* l, size_t i) {
  if (!l || i >= l->len)
    return;
  voxgig_release(l->items[i]);
  for (size_t j = i + 1; j < l->len; j++) {
    l->items[j - 1] = l->items[j];
  }
  l->len--;
}

void voxgig_list_insert(voxgig_list* l, size_t i, voxgig_value* v) {
  if (!l) {
    voxgig_release(v);
    return;
  }
  voxgig_list_reserve(l, l->len + 1);
  if (i > l->len)
    i = l->len;
  for (size_t j = l->len; j > i; j--) {
    l->items[j] = l->items[j - 1];
  }
  l->items[i] = v ? v : voxgig_new_undef();
  l->len++;
}

void voxgig_list_clear(voxgig_list* l) {
  if (!l)
    return;
  for (size_t i = 0; i < l->len; i++)
    voxgig_release(l->items[i]);
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

static void map_index_rebuild(voxgig_map* m, size_t new_cap) {
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

static void map_index_ensure(voxgig_map* m) {
  size_t need = m->ihash_cap == 0 ? 16 : m->ihash_cap;
  while (need < m->len * 2)
    need *= 2;
  /* Always rebuild on insert: cheapest correct option. The hashtable holds
   * positional indices, so a single insert doesn't invalidate prior slots,
   * but the new entry must be added — rebuilding handles both. */
  map_index_rebuild(m, need);
}

size_t voxgig_map_len(const voxgig_map* m) {
  return m ? m->len : 0;
}

const char* voxgig_map_key_at(const voxgig_map* m, size_t i) {
  if (!m || i >= m->len)
    return NULL;
  return m->entries[i].key;
}

voxgig_value* voxgig_map_val_at(const voxgig_map* m, size_t i) {
  if (!m || i >= m->len)
    return NULL;
  return m->entries[i].value;
}

static size_t map_find_idx(const voxgig_map* m, const char* key, size_t n) {
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

voxgig_value* voxgig_map_get(const voxgig_map* m, const char* key) {
  return voxgig_map_get_n(m, key, key ? strlen(key) : 0);
}

voxgig_value* voxgig_map_get_n(const voxgig_map* m, const char* key, size_t n) {
  size_t i = map_find_idx(m, key, n);
  if (i == (size_t)-1)
    return NULL;
  return m->entries[i].value;
}

bool voxgig_map_has(const voxgig_map* m, const char* key) {
  return voxgig_map_get(m, key) != NULL;
}

void voxgig_map_set(voxgig_map* m, const char* key, voxgig_value* v) {
  voxgig_map_set_n(m, key, key ? strlen(key) : 0, v);
}

void voxgig_map_set_n(voxgig_map* m, const char* key, size_t n, voxgig_value* v) {
  if (!m) {
    voxgig_release(v);
    return;
  }
  size_t idx = map_find_idx(m, key, n);
  if (idx != (size_t)-1) {
    voxgig_release(m->entries[idx].value);
    m->entries[idx].value = v ? v : voxgig_new_undef();
    return;
  }
  if (m->len + 1 > m->cap) {
    size_t nc = m->cap == 0 ? 8 : m->cap * 2;
    voxgig_map_entry* ne = (voxgig_map_entry*)realloc(m->entries, nc * sizeof(voxgig_map_entry));
    if (!ne)
      abort();
    m->entries = ne;
    m->cap = nc;
  }
  m->entries[m->len].key = xstrndup(key ? key : "", n);
  m->entries[m->len].klen = n;
  m->entries[m->len].value = v ? v : voxgig_new_undef();
  m->len++;
  map_index_ensure(m);
}

bool voxgig_map_erase(voxgig_map* m, const char* key) {
  if (!m)
    return false;
  size_t n = key ? strlen(key) : 0;
  size_t idx = map_find_idx(m, key, n);
  if (idx == (size_t)-1)
    return false;
  free(m->entries[idx].key);
  voxgig_release(m->entries[idx].value);
  for (size_t j = idx + 1; j < m->len; j++) {
    m->entries[j - 1] = m->entries[j];
  }
  m->len--;
  /* Rebuild the index because positional shifts invalidate slots. */
  map_index_rebuild(m, m->ihash_cap == 0 ? 16 : m->ihash_cap);
  return true;
}

void voxgig_map_clear(voxgig_map* m) {
  if (!m)
    return;
  for (size_t i = 0; i < m->len; i++) {
    free(m->entries[i].key);
    voxgig_release(m->entries[i].value);
  }
  m->len = 0;
  if (m->ihash_slots) {
    memset(m->ihash_slots, 0, m->ihash_cap * sizeof(size_t));
  }
}

/* ===========================================================================
 * Equality
 * ===========================================================================*/

bool voxgig_equals(const voxgig_value* a, const voxgig_value* b) {
  if (a == b)
    return true;
  if (!a || !b)
    return false;
  /* Sentinels: pointer identity. */
  if (voxgig_is_sentinel(a) || voxgig_is_sentinel(b)) {
    return voxgig_is_sentinel(a) && voxgig_is_sentinel(b) && a->as.sentinel == b->as.sentinel;
  }
  /* Cross-type number equality. */
  if (voxgig_is_number(a) && voxgig_is_number(b)) {
    if (voxgig_is_int(a) && voxgig_is_int(b))
      return a->as.i == b->as.i;
    return voxgig_as_double(a) == voxgig_as_double(b);
  }
  if (a->kind != b->kind)
    return false;
  switch (a->kind) {
  case VOXGIG_VAL_UNDEF:
  case VOXGIG_VAL_NULL:
    return true;
  case VOXGIG_VAL_BOOL:
    return a->as.b == b->as.b;
  case VOXGIG_VAL_STRING:
    return a->as.s.len == b->as.s.len && memcmp(a->as.s.data, b->as.s.data, a->as.s.len) == 0;
  case VOXGIG_VAL_LIST: {
    voxgig_list* la = a->as.lst;
    voxgig_list* lb = b->as.lst;
    if (la == lb)
      return true;
    if (la->len != lb->len)
      return false;
    for (size_t i = 0; i < la->len; i++) {
      if (!voxgig_equals(la->items[i], lb->items[i]))
        return false;
    }
    return true;
  }
  case VOXGIG_VAL_MAP: {
    voxgig_map* ma = a->as.map;
    voxgig_map* mb = b->as.map;
    if (ma == mb)
      return true;
    if (ma->len != mb->len)
      return false;
    for (size_t i = 0; i < ma->len; i++) {
      voxgig_value* bv = voxgig_map_get_n(mb, ma->entries[i].key, ma->entries[i].klen);
      if (!bv)
        return false;
      if (!voxgig_equals(ma->entries[i].value, bv))
        return false;
    }
    return true;
  }
  case VOXGIG_VAL_FUNC:
    return false;
  default:
    return false;
  }
}
