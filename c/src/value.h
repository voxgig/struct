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

#define VOXGIG_T_ANY ((int)((1u << 31) - 1))
#define VOXGIG_T_NOVAL (1 << 30)
#define VOXGIG_T_BOOLEAN (1 << 29)
#define VOXGIG_T_DECIMAL (1 << 28)
#define VOXGIG_T_INTEGER (1 << 27)
#define VOXGIG_T_NUMBER (1 << 26)
#define VOXGIG_T_STRING (1 << 25)
#define VOXGIG_T_FUNCTION (1 << 24)
#define VOXGIG_T_SYMBOL (1 << 23)
#define VOXGIG_T_NULL (1 << 22)
#define VOXGIG_T_LIST (1 << 14)
#define VOXGIG_T_MAP (1 << 13)
#define VOXGIG_T_INSTANCE (1 << 12)
#define VOXGIG_T_SCALAR (1 << 7)
#define VOXGIG_T_NODE (1 << 6)

/* Inject mode bitfield. */
#define VOXGIG_M_KEYPRE 1
#define VOXGIG_M_KEYPOST 2
#define VOXGIG_M_VAL 4

#define VOXGIG_MAXDEPTH 32

/* ===========================================================================
 * Forward declarations / tags
 * ===========================================================================*/

typedef struct voxgig_value voxgig_value;
typedef struct voxgig_list voxgig_list;
typedef struct voxgig_map voxgig_map;
typedef struct voxgig_injection voxgig_injection;
typedef struct voxgig_sentinel voxgig_sentinel;

/* Injector / Modify function pointer types. */
typedef voxgig_value* (*voxgig_injector_fn)(voxgig_injection* inj, voxgig_value* val,
                                            const char* ref, voxgig_value* store, void* ud);

typedef void (*voxgig_modify_fn)(voxgig_value* val, voxgig_value* key, voxgig_value* parent,
                                 voxgig_injection* inj, voxgig_value* store, void* ud);

/* Walk callback (key may be VAL_UNDEF at root). path is a string-array Value. */
typedef voxgig_value* (*voxgig_walkapply_fn)(voxgig_value* key, voxgig_value* val,
                                             voxgig_value* parent, voxgig_value* path, void* ud);

/* Filter predicate: receives an [key, val] pair Value. */
typedef bool (*voxgig_itemcheck_fn)(voxgig_value* pair, void* ud);

/* Boxed function value — variant alternative. */
typedef struct voxgig_func {
  enum { VOXGIG_FUNC_INJECTOR, VOXGIG_FUNC_MODIFY } kind;
  union {
    voxgig_injector_fn inj;
    voxgig_modify_fn mod;
  } fn;
  void* ud; /* opaque caller-supplied closure pointer */
} voxgig_func;

/* Sentinel: pointer-identity marker. */
struct voxgig_sentinel {
  const char* name; /* "SKIP" or "DELETE" */
};

/* ===========================================================================
 * Value
 * ===========================================================================*/

typedef enum {
  VOXGIG_VAL_UNDEF = 0,
  VOXGIG_VAL_NULL,
  VOXGIG_VAL_BOOL,
  VOXGIG_VAL_INT,
  VOXGIG_VAL_DOUBLE,
  VOXGIG_VAL_STRING,
  VOXGIG_VAL_LIST,
  VOXGIG_VAL_MAP,
  VOXGIG_VAL_FUNC,
  VOXGIG_VAL_SENTINEL
} voxgig_kind;

struct voxgig_value {
  voxgig_kind kind;
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
    voxgig_list* lst; /* refcounted (own ref) */
    voxgig_map* map;  /* refcounted (own ref) */
    voxgig_func fn;
    const voxgig_sentinel* sentinel;
  } as;
};

/* ===========================================================================
 * List
 * ===========================================================================*/

struct voxgig_list {
  size_t refcount;
  size_t len;
  size_t cap;
  voxgig_value** items; /* each item owns a ref */
};

/* ===========================================================================
 * Map (ordered, vector-of-entries + hashtable index)
 * ===========================================================================*/

typedef struct voxgig_map_entry {
  char* key;           /* owned */
  size_t klen;         /* length excl. NUL */
  voxgig_value* value; /* owns a ref */
} voxgig_map_entry;

struct voxgig_map {
  size_t refcount;
  size_t len;
  size_t cap;
  voxgig_map_entry* entries;
  /* Open-addressing hash index of slot indices into entries[]. */
  size_t ihash_cap;    /* power of 2, 0 means empty */
  size_t* ihash_slots; /* values are (index+1); 0 means empty */
};

/* ===========================================================================
 * Constructors / refcount
 * ===========================================================================*/

voxgig_value* voxgig_new_undef(void);
voxgig_value* voxgig_new_null(void);
voxgig_value* voxgig_new_bool(bool b);
voxgig_value* voxgig_new_int(int64_t v);
voxgig_value* voxgig_new_double(double v);
voxgig_value* voxgig_new_string(const char* s);             /* copies */
voxgig_value* voxgig_new_string_n(const char* s, size_t n); /* copies n bytes */
voxgig_value* voxgig_new_string_take(char* s, size_t n);    /* takes ownership */
voxgig_value* voxgig_new_list(void);
voxgig_value* voxgig_new_map(void);
voxgig_value* voxgig_new_injector(voxgig_injector_fn fn, void* ud);
voxgig_value* voxgig_new_modify(voxgig_modify_fn fn, void* ud);
voxgig_value* voxgig_new_sentinel(const voxgig_sentinel* s);

voxgig_value* voxgig_retain(voxgig_value* v);
void voxgig_release(voxgig_value* v);
voxgig_value* voxgig_clone(voxgig_value* v);

/* ===========================================================================
 * Type predicates
 * ===========================================================================*/

bool voxgig_is_undef(const voxgig_value* v);
bool voxgig_is_null(const voxgig_value* v);
bool voxgig_is_bool(const voxgig_value* v);
bool voxgig_is_int(const voxgig_value* v);
bool voxgig_is_double(const voxgig_value* v);
bool voxgig_is_number(const voxgig_value* v);
bool voxgig_is_string(const voxgig_value* v);
bool voxgig_is_list(const voxgig_value* v);
bool voxgig_is_map(const voxgig_value* v);
bool voxgig_is_node(const voxgig_value* v);
bool voxgig_is_func(const voxgig_value* v);
bool voxgig_is_injector(const voxgig_value* v);
bool voxgig_is_modify(const voxgig_value* v);
bool voxgig_is_sentinel(const voxgig_value* v);

/* ===========================================================================
 * Accessors (return raw underlying values; assume kind matches)
 * ===========================================================================*/

bool voxgig_as_bool(const voxgig_value* v);
int64_t voxgig_as_int(const voxgig_value* v);
double voxgig_as_double(const voxgig_value* v);
const char* voxgig_as_string(const voxgig_value* v);
size_t voxgig_string_len(const voxgig_value* v);
voxgig_list* voxgig_as_list(const voxgig_value* v);
voxgig_map* voxgig_as_map(const voxgig_value* v);
const voxgig_sentinel* voxgig_as_sentinel(const voxgig_value* v);

/* ===========================================================================
 * Sentinel singletons
 * ===========================================================================*/

const voxgig_sentinel* voxgig_skip_sentinel(void);
const voxgig_sentinel* voxgig_delete_sentinel(void);
bool voxgig_is_skip(const voxgig_value* v);
bool voxgig_is_delete(const voxgig_value* v);
voxgig_value* voxgig_new_skip(void);
voxgig_value* voxgig_new_delete(void);

/* ===========================================================================
 * List operations
 * ===========================================================================*/

size_t voxgig_list_len(const voxgig_list* l);
voxgig_value* voxgig_list_get(const voxgig_list* l, size_t i);   /* borrowed ref */
void voxgig_list_push(voxgig_list* l, voxgig_value* v);          /* takes ownership of one ref */
void voxgig_list_set(voxgig_list* l, size_t i, voxgig_value* v); /* takes ownership */
void voxgig_list_erase(voxgig_list* l, size_t i);
void voxgig_list_insert(voxgig_list* l, size_t i, voxgig_value* v); /* takes ownership */
void voxgig_list_clear(voxgig_list* l);
void voxgig_list_reserve(voxgig_list* l, size_t cap);

/* ===========================================================================
 * Map operations
 * ===========================================================================*/

size_t voxgig_map_len(const voxgig_map* m);
const char* voxgig_map_key_at(const voxgig_map* m, size_t i);
voxgig_value* voxgig_map_val_at(const voxgig_map* m, size_t i);     /* borrowed */
voxgig_value* voxgig_map_get(const voxgig_map* m, const char* key); /* borrowed; NULL if missing */
voxgig_value* voxgig_map_get_n(const voxgig_map* m, const char* key, size_t n);
bool voxgig_map_has(const voxgig_map* m, const char* key);
void voxgig_map_set(voxgig_map* m, const char* key, voxgig_value* v); /* takes ownership */
void voxgig_map_set_n(voxgig_map* m, const char* key, size_t n, voxgig_value* v);
bool voxgig_map_erase(voxgig_map* m, const char* key);
void voxgig_map_clear(voxgig_map* m);

/* ===========================================================================
 * Equality / numeric helpers
 * ===========================================================================*/

bool voxgig_equals(const voxgig_value* a, const voxgig_value* b);

/* ===========================================================================
 * String pool (used for short literal-keyed Values)
 * ===========================================================================*/

/* No global pool; we always allocate strings owned per-value for simplicity. */

#ifdef __cplusplus
}
#endif

#endif /* VOXGIG_STRUCT_VALUE_H */
