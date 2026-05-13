/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
 *
 * Voxgig Struct — public C API.
 *
 * C port of the canonical TypeScript implementation. The runtime value type
 * is vs_value (see value.h). The functions below mirror the canonical API,
 * lowercased with `vs_` prefix.
 *
 * Naming: `vs_<canonical>` (e.g. vs_getpath, vs_setprop, vs_walk). Optional
 * arguments in the TS API are exposed via NULL: pass NULL to indicate
 * "not provided".
 *
 * Memory model: All vs_value* arguments are borrowed (caller still owns
 * its reference). Returned vs_value* are owned by the caller — use
 * vs_release() to free.
 */

#ifndef VOXGIG_STRUCT_H
#define VOXGIG_STRUCT_H

#include "value.h"
#include "value_io.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ===========================================================================
 * Injection state
 * ===========================================================================*/

/* string vector — heap-owned, used for path arrays. */
typedef struct vs_strvec {
  size_t len;
  size_t cap;
  char** data;
} vs_strvec;

void vs_strvec_init(vs_strvec* v);
void vs_strvec_free(vs_strvec* v);
void vs_strvec_push(vs_strvec* v, const char* s);
void vs_strvec_push_n(vs_strvec* v, const char* s, size_t n);
void vs_strvec_clear(vs_strvec* v);
void vs_strvec_resize(vs_strvec* v, size_t n); /* fill with "" */
void vs_strvec_set(vs_strvec* v, size_t i, const char* s);
void vs_strvec_copy(vs_strvec* dst, const vs_strvec* src);

struct vs_injection {
  int mode;         /* M_KEYPRE / M_KEYPOST / M_VAL bitfield */
  bool full;        /* full-string injection */
  size_t keyI;      /* index of parent key in keys */
  bool keyI_neg;    /* true if keyI is logically -1 (validator hack) */
  vs_strvec keys;   /* parent keys */
  char* key;        /* current parent key (owned) */
  vs_value* val;    /* current child value (borrowed in canonical; owned in C state) */
  vs_value* parent; /* current parent (in transform specification, borrowed) */
  vs_strvec path;   /* path to current node */
  /* nodes stack: list of borrowed nodes (each entry is borrowed). */
  size_t nodes_len;
  size_t nodes_cap;
  vs_value** nodes;
  vs_value* handler_val; /* injector value (owned) */
  /* errs is a vs_value list (owned) */
  vs_value* errs;
  /* meta is a vs_value map (owned) */
  vs_value* meta;
  vs_value* dparent; /* borrowed */
  vs_strvec dpath;
  char* base;           /* owned, may be NULL */
  vs_value* modify_val; /* owned */
  vs_injection* prior;  /* not owned */
  vs_value* extra;      /* borrowed */
};

vs_injection* vs_inj_new(vs_value* val, vs_value* parent);
void vs_inj_free(vs_injection* inj);
void vs_inj_descend(vs_injection* inj);
vs_injection* vs_inj_child(vs_injection* parent, size_t keyI, const vs_strvec* keys);
vs_value* vs_inj_setval(vs_injection* inj, vs_value* val, int ancestor); /* val borrowed */

void vs_inj_nodes_push(vs_injection* inj, vs_value* n); /* borrowed */
void vs_inj_set_path(vs_injection* inj, const vs_strvec* path);
void vs_inj_set_dpath(vs_injection* inj, const vs_strvec* path);

/* ===========================================================================
 * Minor utilities
 * ===========================================================================*/

const char* vs_typename(int t);
vs_value* vs_getdef(vs_value* val, vs_value* alt);

bool vs_isnode(const vs_value* v);
bool vs_ismap(const vs_value* v);
bool vs_islist(const vs_value* v);
bool vs_iskey(const vs_value* v);
bool vs_isempty(const vs_value* v);
bool vs_isfunc(const vs_value* v);

int64_t vs_size(const vs_value* v);
vs_value* vs_slice(vs_value* v, vs_value* start, vs_value* end, bool mutate);
char* vs_pad(vs_value* str, vs_value* padding, vs_value* padchar);
int vs_typify(const vs_value* v);
vs_value* vs_getelem(vs_value* val, vs_value* key, vs_value* alt);
vs_value* vs_getprop(vs_value* val, vs_value* key, vs_value* alt);
char* vs_strkey(vs_value* key);
vs_strvec vs_keysof(vs_value* val);
bool vs_haskey(vs_value* val, vs_value* key);

/* Items as a List of [k,v] pairs (owned). */
vs_value* vs_items_v(vs_value* val);

vs_value* vs_flatten(vs_value* list, vs_value* depth);
vs_value* vs_filter(vs_value* val, vs_itemcheck_fn check, void* ud);

char* vs_escre(vs_value* v);
char* vs_escurl(vs_value* v);
char* vs_replace_str(const char* s, const char* from, const char* to);
char* vs_join_v(vs_value* arr, vs_value* sep, vs_value* url);
char* vs_jsonify(vs_value* val, vs_value* flags);
char* vs_stringify(vs_value* val, int maxlen);
char* vs_pathify(vs_value* val, int startin, int endin);

vs_value* vs_jm_va(int n, vs_value** kv);
vs_value* vs_jt_va(int n, vs_value** v);

vs_value* vs_delprop(vs_value* parent, vs_value* key); /* returns parent */
vs_value* vs_setprop(vs_value* parent, vs_value* key, vs_value* val);

/* ===========================================================================
 * Major utilities
 * ===========================================================================*/

vs_value* vs_walk(vs_value* val, vs_walkapply_fn before, vs_walkapply_fn after, int maxdepth,
                  void* ud);

vs_value* vs_merge(vs_value* val, int maxdepth);

vs_value* vs_setpath(vs_value* store, vs_value* path, vs_value* val, vs_injection* injdef);
vs_value* vs_getpath(vs_value* store, vs_value* path, vs_injection* injdef);

vs_value* vs_inject(vs_value* val, vs_value* store, vs_injection* injdef);

vs_value* vs_transform(vs_value* data, vs_value* spec, vs_injection* injdef);
vs_value* vs_validate(vs_value* data, vs_value* spec, vs_injection* injdef);

/* select returns a new List. */
vs_value* vs_select(vs_value* children, vs_value* query);

/* Injection helpers. */
bool vs_check_placement(int modes, const char* ijname, int parent_types, vs_injection* inj);
/* injectorArgs: returns a List; element 0 is the error (string or undef),
   elements 1..n are the args. Owned by caller. */
vs_value* vs_injector_args(const int* argTypes, size_t n, vs_value* args);
vs_injection* vs_inject_child(vs_value* child, vs_value* store, vs_injection* inj);

#ifdef __cplusplus
}
#endif

#endif
