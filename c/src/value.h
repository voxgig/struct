/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

/*
 * Voxgig Struct — Value type (C port).
 *
 * In-memory JSON-shaped data plus a small set of runtime extras the canonical
 * TypeScript port needs: callable values (Injector/Modify), sentinel markers
 * (SKIP/DELETE), and an explicit "undefined" distinct from JSON null.
 *
 * Design summary (mirrors cpp/src/value.hpp):
 *   - Tagged union with reference-counted List/Map containers so list/map
 *     mutation propagates to every Value that references the same container
 *     (TS reference-stability).
 *   - Insertion-ordered Map (keys are an array, plus a hashtable for lookup),
 *     because the inject machinery's $-suffix key partition depends on order.
 *   - VAL_UNDEF (distinct from VAL_NULL) represents "absent" / undefined.
 *   - Sentinel pointers (SKIP / DELETE) compare by identity and survive clone.
 */

#ifndef VOXGIG_STRUCT_VALUE_H
#define VOXGIG_STRUCT_VALUE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ===========================================================================
 * Type bit-flags. Mirrors TS lines 110–127.
 * ===========================================================================*/

#define VS_T_ANY ((int)((1u << 31) - 1))
#define VS_T_NOVAL (1 << 30)
#define VS_T_BOOLEAN (1 << 29)
#define VS_T_DECIMAL (1 << 28)
#define VS_T_INTEGER (1 << 27)
#define VS_T_NUMBER (1 << 26)
#define VS_T_STRING (1 << 25)
#define VS_T_FUNCTION (1 << 24)
#define VS_T_SYMBOL (1 << 23)
#define VS_T_NULL (1 << 22)
#define VS_T_LIST (1 << 14)
#define VS_T_MAP (1 << 13)
#define VS_T_INSTANCE (1 << 12)
#define VS_T_SCALAR (1 << 7)
#define VS_T_NODE (1 << 6)

/* Inject mode bitfield. */
#define VS_M_KEYPRE 1
#define VS_M_KEYPOST 2
#define VS_M_VAL 4

#define VS_MAXDEPTH 32

/* ===========================================================================
 * Forward declarations / tags
 * ===========================================================================*/

typedef struct vs_value vs_value;
typedef struct vs_list vs_list;
typedef struct vs_map vs_map;
typedef struct vs_injection vs_injection;
typedef struct vs_sentinel vs_sentinel;

/* Injector / Modify function pointer types. */
typedef vs_value* (*vs_injector_fn)(vs_injection* inj, vs_value* val, const char* ref,
                                    vs_value* store, void* ud);

typedef void (*vs_modify_fn)(vs_value* val, vs_value* key, vs_value* parent, vs_injection* inj,
                             vs_value* store, void* ud);

/* Walk callback (key may be VAL_UNDEF at root). path is a string-array Value. */
typedef vs_value* (*vs_walkapply_fn)(vs_value* key, vs_value* val, vs_value* parent, vs_value* path,
                                     void* ud);

/* Filter predicate: receives an [key, val] pair Value. */
typedef bool (*vs_itemcheck_fn)(vs_value* pair, void* ud);

/* Boxed function value — variant alternative. */
typedef struct vs_func {
  enum { VS_FUNC_INJECTOR, VS_FUNC_MODIFY } kind;
  union {
    vs_injector_fn inj;
    vs_modify_fn mod;
  } fn;
  void* ud; /* opaque caller-supplied closure pointer */
} vs_func;

/* Sentinel: pointer-identity marker. */
struct vs_sentinel {
  const char* name; /* "SKIP" or "DELETE" */
};

/* ===========================================================================
 * Value
 * ===========================================================================*/

typedef enum {
  VS_VAL_UNDEF = 0,
  VS_VAL_NULL,
  VS_VAL_BOOL,
  VS_VAL_INT,
  VS_VAL_DOUBLE,
  VS_VAL_STRING,
  VS_VAL_LIST,
  VS_VAL_MAP,
  VS_VAL_FUNC,
  VS_VAL_SENTINEL
} vs_kind;

struct vs_value {
  vs_kind kind;
  /* Refcount for the value structure itself (the outer container). */
  size_t refcount;
  union {
    bool b;
    int64_t i;
    double d;
    struct {
      char* data;
      size_t len;
    } s;
    vs_list* lst; /* refcounted (own ref) */
    vs_map* map;  /* refcounted (own ref) */
    vs_func fn;
    const vs_sentinel* sentinel;
  } as;
};

/* ===========================================================================
 * List
 * ===========================================================================*/

struct vs_list {
  size_t refcount;
  size_t len;
  size_t cap;
  vs_value** items; /* each item owns a ref */
};

/* ===========================================================================
 * Map (ordered, vector-of-entries + hashtable index)
 * ===========================================================================*/

typedef struct vs_map_entry {
  char* key;       /* owned */
  size_t klen;     /* length excl. NUL */
  vs_value* value; /* owns a ref */
} vs_map_entry;

struct vs_map {
  size_t refcount;
  size_t len;
  size_t cap;
  vs_map_entry* entries;
  /* Open-addressing hash index of slot indices into entries[]. */
  size_t ihash_cap;    /* power of 2, 0 means empty */
  size_t* ihash_slots; /* values are (index+1); 0 means empty */
};

/* ===========================================================================
 * Constructors / refcount
 * ===========================================================================*/

vs_value* vs_new_undef(void);
vs_value* vs_new_null(void);
vs_value* vs_new_bool(bool b);
vs_value* vs_new_int(int64_t v);
vs_value* vs_new_double(double v);
vs_value* vs_new_string(const char* s);             /* copies */
vs_value* vs_new_string_n(const char* s, size_t n); /* copies n bytes */
vs_value* vs_new_string_take(char* s, size_t n);    /* takes ownership */
vs_value* vs_new_list(void);
vs_value* vs_new_map(void);
vs_value* vs_new_injector(vs_injector_fn fn, void* ud);
vs_value* vs_new_modify(vs_modify_fn fn, void* ud);
vs_value* vs_new_sentinel(const vs_sentinel* s);

vs_value* vs_retain(vs_value* v);
void vs_release(vs_value* v);
vs_value* vs_clone(vs_value* v);

/* ===========================================================================
 * Type predicates
 * ===========================================================================*/

bool vs_is_undef(const vs_value* v);
bool vs_is_null(const vs_value* v);
bool vs_is_bool(const vs_value* v);
bool vs_is_int(const vs_value* v);
bool vs_is_double(const vs_value* v);
bool vs_is_number(const vs_value* v);
bool vs_is_string(const vs_value* v);
bool vs_is_list(const vs_value* v);
bool vs_is_map(const vs_value* v);
bool vs_is_node(const vs_value* v);
bool vs_is_func(const vs_value* v);
bool vs_is_injector(const vs_value* v);
bool vs_is_modify(const vs_value* v);
bool vs_is_sentinel(const vs_value* v);

/* ===========================================================================
 * Accessors (return raw underlying values; assume kind matches)
 * ===========================================================================*/

bool vs_as_bool(const vs_value* v);
int64_t vs_as_int(const vs_value* v);
double vs_as_double(const vs_value* v);
const char* vs_as_string(const vs_value* v);
size_t vs_string_len(const vs_value* v);
vs_list* vs_as_list(const vs_value* v);
vs_map* vs_as_map(const vs_value* v);
const vs_sentinel* vs_as_sentinel(const vs_value* v);

/* ===========================================================================
 * Sentinel singletons
 * ===========================================================================*/

const vs_sentinel* vs_skip_sentinel(void);
const vs_sentinel* vs_delete_sentinel(void);
bool vs_is_skip(const vs_value* v);
bool vs_is_delete(const vs_value* v);
vs_value* vs_new_skip(void);
vs_value* vs_new_delete(void);

/* ===========================================================================
 * List operations
 * ===========================================================================*/

size_t vs_list_len(const vs_list* l);
vs_value* vs_list_get(const vs_list* l, size_t i);   /* borrowed ref */
void vs_list_push(vs_list* l, vs_value* v);          /* takes ownership of one ref */
void vs_list_set(vs_list* l, size_t i, vs_value* v); /* takes ownership */
void vs_list_erase(vs_list* l, size_t i);
void vs_list_insert(vs_list* l, size_t i, vs_value* v); /* takes ownership */
void vs_list_clear(vs_list* l);
void vs_list_reserve(vs_list* l, size_t cap);

/* ===========================================================================
 * Map operations
 * ===========================================================================*/

size_t vs_map_len(const vs_map* m);
const char* vs_map_key_at(const vs_map* m, size_t i);
vs_value* vs_map_val_at(const vs_map* m, size_t i);     /* borrowed */
vs_value* vs_map_get(const vs_map* m, const char* key); /* borrowed; NULL if missing */
vs_value* vs_map_get_n(const vs_map* m, const char* key, size_t n);
bool vs_map_has(const vs_map* m, const char* key);
void vs_map_set(vs_map* m, const char* key, vs_value* v); /* takes ownership */
void vs_map_set_n(vs_map* m, const char* key, size_t n, vs_value* v);
bool vs_map_erase(vs_map* m, const char* key);
void vs_map_clear(vs_map* m);

/* ===========================================================================
 * Equality / numeric helpers
 * ===========================================================================*/

bool vs_equals(const vs_value* a, const vs_value* b);

/* ===========================================================================
 * String pool (used for short literal-keyed Values)
 * ===========================================================================*/

/* No global pool; we always allocate strings owned per-value for simplicity. */

#ifdef __cplusplus
}
#endif

#endif /* VOXGIG_STRUCT_VALUE_H */
