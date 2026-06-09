/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
 *
 * Voxgig Struct — public C API.
 *
 * C port of the canonical TypeScript implementation. The runtime value type
 * is voxgig_value (see value.h). The functions below mirror the canonical API,
 * lowercased with `voxgig_` prefix.
 *
 * Naming: `voxgig_<canonical>` (e.g. voxgig_getpath, voxgig_setprop, voxgig_walk). Optional
 * arguments in the TS API are exposed via NULL: pass NULL to indicate
 * "not provided".
 *
 * Memory model: All voxgig_value* arguments are borrowed (caller still owns
 * its reference). Returned voxgig_value* are owned by the caller — use
 * voxgig_release() to free.
 */

#ifndef VOXGIG_STRUCT_H
#define VOXGIG_STRUCT_H

#include "regex.h"
#include "value.h"
#include "value_io.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ===========================================================================
 * Injection state
 * ===========================================================================*/

/* string vector — heap-owned, used for path arrays. */
typedef struct voxgig_strvec {
  size_t len;
  size_t cap;
  char** data;
} voxgig_strvec;

void voxgig_strvec_init(voxgig_strvec* v);
void voxgig_strvec_free(voxgig_strvec* v);
void voxgig_strvec_push(voxgig_strvec* v, const char* s);
void voxgig_strvec_push_n(voxgig_strvec* v, const char* s, size_t n);
void voxgig_strvec_clear(voxgig_strvec* v);
void voxgig_strvec_resize(voxgig_strvec* v, size_t n); /* fill with "" */
void voxgig_strvec_set(voxgig_strvec* v, size_t i, const char* s);
void voxgig_strvec_copy(voxgig_strvec* dst, const voxgig_strvec* src);

/* ===========================================================================
 * Regex utility — uniform re_* names (mirror of REGEX_API.md). Wraps the
 * vendored RE2-subset engine in src/regex.c.
 *
 * voxgig_re_compile returns a voxgig_regex* that must be released with voxgig_regex_free.
 * The other helpers accept either a voxgig_regex* (already-compiled) or a pattern
 * string (compiled on the fly and freed before returning).
 * ===========================================================================*/

voxgig_regex* voxgig_re_compile(const char* pattern);
bool voxgig_re_test(const char* pattern, const char* input);
bool voxgig_re_test_re(const voxgig_regex* re, const char* input);

/* Returns a newly-allocated list of strings: [whole, capture1, ...]. Caller
 * voxgig_strvec_free()s. If no match, returns a voxgig_strvec with len==0. */
voxgig_strvec voxgig_re_find(const char* pattern, const char* input);
voxgig_strvec voxgig_re_find_re(const voxgig_regex* re, const char* input);

/* List-of-lists of strings — one voxgig_strvec per match (each row is
 * [whole, capture1, ...]). Caller must voxgig_strvec_vec_free() to release. */
typedef struct voxgig_strvec_vec {
  size_t len;
  size_t cap;
  voxgig_strvec* data;
} voxgig_strvec_vec;

void voxgig_strvec_vec_init(voxgig_strvec_vec* v);
void voxgig_strvec_vec_free(voxgig_strvec_vec* v);

voxgig_strvec_vec voxgig_re_find_all(const char* pattern, const char* input);
voxgig_strvec_vec voxgig_re_find_all_re(const voxgig_regex* re, const char* input);

/* Returns malloc'd string. */
char* voxgig_re_replace(const char* pattern, const char* input, const char* replacement);
char* voxgig_re_replace_re(const voxgig_regex* re, const char* input, const char* replacement);
char* voxgig_re_replace_cb(const voxgig_regex* re, const char* input,
                           char* (*cb)(const voxgig_strvec* caps, void* ud), void* ud);

/* Alias of voxgig_escre. */
char* voxgig_re_escape(const char* literal);

struct voxgig_injection {
  int mode;             /* M_KEYPRE / M_KEYPOST / M_VAL bitfield */
  bool full;            /* full-string injection */
  size_t keyI;          /* index of parent key in keys */
  bool keyI_neg;        /* true if keyI is logically -1 (validator hack) */
  voxgig_strvec keys;   /* parent keys */
  char* key;            /* current parent key (owned) */
  voxgig_value* val;    /* current child value (borrowed in canonical; owned in C state) */
  voxgig_value* parent; /* current parent (in transform specification, borrowed) */
  voxgig_strvec path;   /* path to current node */
  /* nodes stack: list of borrowed nodes (each entry is borrowed). */
  size_t nodes_len;
  size_t nodes_cap;
  voxgig_value** nodes;
  voxgig_value* handler_val; /* injector value (owned) */
  /* errs is a voxgig_value list (owned) */
  voxgig_value* errs;
  /* meta is a voxgig_value map (owned) */
  voxgig_value* meta;
  voxgig_value* dparent; /* borrowed */
  voxgig_strvec dpath;
  char* base;               /* owned, may be NULL */
  voxgig_value* modify_val; /* owned */
  voxgig_injection* prior;  /* not owned */
  voxgig_value* extra;      /* borrowed */
};

voxgig_injection* voxgig_inj_new(voxgig_value* val, voxgig_value* parent);
void voxgig_inj_free(voxgig_injection* inj);
void voxgig_inj_descend(voxgig_injection* inj);
voxgig_injection* voxgig_inj_child(voxgig_injection* parent, size_t keyI,
                                   const voxgig_strvec* keys);
voxgig_value* voxgig_inj_setval(voxgig_injection* inj, voxgig_value* val,
                                int ancestor); /* val borrowed */

void voxgig_inj_nodes_push(voxgig_injection* inj, voxgig_value* n); /* borrowed */
void voxgig_inj_set_path(voxgig_injection* inj, const voxgig_strvec* path);
void voxgig_inj_set_dpath(voxgig_injection* inj, const voxgig_strvec* path);

/* ===========================================================================
 * Minor utilities
 * ===========================================================================*/

const char* voxgig_typename(int t);
voxgig_value* voxgig_getdef(voxgig_value* val, voxgig_value* alt);

bool voxgig_isnode(const voxgig_value* v);
bool voxgig_ismap(const voxgig_value* v);
bool voxgig_islist(const voxgig_value* v);
bool voxgig_iskey(const voxgig_value* v);
bool voxgig_isempty(const voxgig_value* v);
bool voxgig_isfunc(const voxgig_value* v);

int64_t voxgig_size(const voxgig_value* v);
voxgig_value* voxgig_slice(voxgig_value* v, voxgig_value* start, voxgig_value* end, bool mutate);
char* voxgig_pad(voxgig_value* str, voxgig_value* padding, voxgig_value* padchar);
int voxgig_typify(const voxgig_value* v);
voxgig_value* voxgig_getelem(voxgig_value* val, voxgig_value* key, voxgig_value* alt);
voxgig_value* voxgig_getprop(voxgig_value* val, voxgig_value* key, voxgig_value* alt);

/* Internal: literal lookup that preserves stored JSON null. Group B callers
 * (validate / transform commands / builders / inject internals) use this
 * when they need to inspect the raw stored value at a slot regardless of
 * whether it is null. The public voxgig_getprop / voxgig_getelem / voxgig_haskey APIs
 * treat null as absent (Group A) per /UNDEF_SPEC.md.
 *
 * Returned reference is borrowed from the container (NOT retained). Caller
 * must voxgig_retain() if it needs to outlive the parent container. */
voxgig_value* voxgig_lookup(voxgig_value* val, voxgig_value* key);
char* voxgig_strkey(voxgig_value* key);
voxgig_strvec voxgig_keysof(voxgig_value* val);
bool voxgig_haskey(voxgig_value* val, voxgig_value* key);

/* Items as a List of [k,v] pairs (owned). */
voxgig_value* voxgig_items_v(voxgig_value* val);

voxgig_value* voxgig_flatten(voxgig_value* list, voxgig_value* depth);
voxgig_value* voxgig_filter(voxgig_value* val, voxgig_itemcheck_fn check, void* ud);

char* voxgig_escre(voxgig_value* v);
char* voxgig_escurl(voxgig_value* v);
char* voxgig_replace_str(const char* s, const char* from, const char* to);
char* voxgig_join_v(voxgig_value* arr, voxgig_value* sep, voxgig_value* url);
char* voxgig_jsonify(voxgig_value* val, voxgig_value* flags);
char* voxgig_stringify(voxgig_value* val, int maxlen);
char* voxgig_pathify(voxgig_value* val, int startin, int endin);

voxgig_value* voxgig_jm_va(int n, voxgig_value** kv);
voxgig_value* voxgig_jt_va(int n, voxgig_value** v);

voxgig_value* voxgig_delprop(voxgig_value* parent, voxgig_value* key); /* returns parent */
voxgig_value* voxgig_setprop(voxgig_value* parent, voxgig_value* key, voxgig_value* val);

/* ===========================================================================
 * Major utilities
 * ===========================================================================*/

voxgig_value* voxgig_walk(voxgig_value* val, voxgig_walkapply_fn before, voxgig_walkapply_fn after,
                          int maxdepth, void* ud);

voxgig_value* voxgig_merge(voxgig_value* val, int maxdepth);

voxgig_value* voxgig_setpath(voxgig_value* store, voxgig_value* path, voxgig_value* val,
                             voxgig_injection* injdef);
voxgig_value* voxgig_getpath(voxgig_value* store, voxgig_value* path, voxgig_injection* injdef);

voxgig_value* voxgig_inject(voxgig_value* val, voxgig_value* store, voxgig_injection* injdef);

voxgig_value* voxgig_transform(voxgig_value* data, voxgig_value* spec, voxgig_injection* injdef);
voxgig_value* voxgig_validate(voxgig_value* data, voxgig_value* spec, voxgig_injection* injdef);

/* select returns a new List. */
voxgig_value* voxgig_select(voxgig_value* children, voxgig_value* query);

/* Injection helpers. */
bool voxgig_check_placement(int modes, const char* ijname, int parent_types, voxgig_injection* inj);
/* injectorArgs: returns a List; element 0 is the error (string or undef),
   elements 1..n are the args. Owned by caller. */
voxgig_value* voxgig_injector_args(const int* argTypes, size_t n, voxgig_value* args);
voxgig_injection* voxgig_inject_child(voxgig_value* child, voxgig_value* store,
                                      voxgig_injection* inj);

#ifdef __cplusplus
}
#endif

#endif
