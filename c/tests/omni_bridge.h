/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

/*
 * Voxgig Struct — the bridge to voxgig/omni, the shared test runner.
 *
 * The corpus runner is not in this repository. omni is consumed as a local
 * checkout, resolved by the Makefile ($OMNI_HOME first, then sibling paths,
 * taking the first directory that carries spec/fib.json) and compiled in with
 * the tests. Only the tests use it: `make build` compiles src/ alone and the
 * shipped library has no reference to omni (register 4.13).
 *
 * This is the C counterpart of python/tests/omni.py, php/tests/omni.php,
 * lua/test/omni.lua, csharp/tests/Omni.cs, java/src/test/Omni.java,
 * rust/corpus/tests/omni.rs and perl/t/OmniBridge.pm.
 *
 * ---------------------------------------------------------------------------
 * Two value types, one shape
 * ---------------------------------------------------------------------------
 *
 * omni has `omni_json` (pool-allocated, freed in one go) and this port has
 * `voxgig_value` (reference-counted). They model the same JSON, and both draw
 * the same three-way distinction — absent, null, and a value — so nothing has
 * to be guessed:
 *
 *     omni            this port
 *     ----            ---------
 *     OMNI_ABSENT     VAL_UNDEF
 *     OMNI_NULL       VAL_NULL
 *     OMNI_BOOL/...   VAL_BOOL/...
 *
 * The one difference is numbers: `omni_json` carries a single `double`, while
 * this port separates integers from decimals — `typify(1)` is T_INTEGER and
 * `typify(1.5)` is T_DECIMAL, and `minor/typify` asserts both. So an integral
 * double becomes an int, which is exactly what this port's own JSON parser
 * does with a literal that has no `.` or exponent (src/value_io.c). The corpus
 * contains no decimal literal with an integral value, so nothing is lost.
 *
 * ---------------------------------------------------------------------------
 * Mutated arguments
 * ---------------------------------------------------------------------------
 *
 * `tostruct` allocates, so the subject does NOT receive omni's own container
 * and an in-place rewrite would be invisible to the runner. `minor/setpath`
 * asserts the store AFTER such a rewrite in eight of its nine entries, and
 * `merge/integrity` in all six, through `match.args`.
 *
 * So the wrapper writes the argument back: omni hands the subject the raw
 * `omni_json **` of its argument list, and storing a converted value at
 * `args[0]` is what `omni_checkresult` then matches against. go and csharp do
 * the same; java gets it for free because its two models share containers.
 */

#ifndef VOXGIG_STRUCT_OMNI_BRIDGE_H
#define VOXGIG_STRUCT_OMNI_BRIDGE_H

#include "omni.h"
#include "voxgig_struct.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The largest double that is exactly an integer. Beyond it, "is this a whole
 * number?" stops being a question about the value and starts being one about
 * the representation. */
#define BRIDGE_INTMAX 9007199254740992.0

/* omni's model -> this port's. The caller owns one reference. */
static voxgig_value* bridge_tostruct(const omni_json* val) {
  if (NULL == val || omni_isabsent(val))
    return voxgig_new_undef();

  switch (val->type) {
  case OMNI_NULL:
    return voxgig_new_null();

  case OMNI_BOOL:
    return voxgig_new_bool(0 != val->boolval);

  case OMNI_NUM: {
    double num = val->numval;
    if (isfinite(num) && floor(num) == num && fabs(num) < BRIDGE_INTMAX)
      return voxgig_new_int((int64_t)num);
    return voxgig_new_double(num);
  }

  case OMNI_STR:
    return voxgig_new_string(val->strval ? val->strval : "");

  case OMNI_LIST: {
    voxgig_value* out = voxgig_new_list();
    for (size_t i = 0; i < val->listlen; i++)
      voxgig_list_push(voxgig_as_list(out), bridge_tostruct(val->list[i]));
    return out;
  }

  case OMNI_MAP: {
    voxgig_value* out = voxgig_new_map();
    for (size_t i = 0; i < val->maplen; i++)
      voxgig_map_set(voxgig_as_map(out), val->keys[i], bridge_tostruct(val->vals[i]));
    return out;
  }

  default:
    return voxgig_new_undef();
  }
}

/* This port's model -> omni's, allocated from `pool`.
 *
 * A function or a sentinel has no JSON form. Both can reach here - `merge`
 * carries a function value through, and `$SKIP` survives a transform - and
 * omni only ever stringifies them, so they become their own names rather than
 * silently collapsing to null. */
static omni_json* bridge_toomni(omni_pool* pool, const voxgig_value* val) {
  if (NULL == val || voxgig_is_undef(val))
    return omni_absent(pool);

  if (voxgig_is_null(val))
    return omni_null(pool);

  if (voxgig_is_bool(val))
    return omni_bool(pool, voxgig_as_bool(val) ? 1 : 0);

  if (voxgig_is_int(val))
    return omni_num(pool, (double)voxgig_as_int(val));

  if (voxgig_is_double(val))
    return omni_num(pool, voxgig_as_double(val));

  if (voxgig_is_string(val)) {
    const char* text = voxgig_as_string(val);
    return omni_str(pool, text ? text : "");
  }

  if (voxgig_is_list(val)) {
    omni_json* out = omni_list(pool);
    voxgig_list* list = voxgig_as_list(val);
    for (size_t i = 0; i < list->len; i++)
      omni_list_push(out, bridge_toomni(pool, list->items[i]));
    return out;
  }

  if (voxgig_is_map(val)) {
    omni_json* out = omni_map(pool);
    voxgig_map* map = voxgig_as_map(val);
    for (size_t i = 0; i < map->len; i++)
      omni_map_set(out, map->entries[i].key, bridge_toomni(pool, map->entries[i].value));
    return out;
  }

  if (voxgig_is_func(val))
    return omni_str(pool, "[Function]");

  if (voxgig_is_skip(val))
    return omni_str(pool, "`$SKIP`");

  if (voxgig_is_delete(val))
    return omni_str(pool, "`$DELETE`");

  return omni_absent(pool);
}

/* A subject in this port's shape: one argument in, one value out. On failure
 * it sets *err to a message; a heap message is freed by the wrapper. */
typedef voxgig_value* (*bridge_subject_fn)(voxgig_value* in, char** err, void* ud);

typedef struct bridge_subject {
  omni_subject base;
  bridge_subject_fn fn;
  void* ud;
  omni_pool* pool;
} bridge_subject;

static omni_result bridge_call(omni_subject* self, omni_json** args, size_t nargs) {
  /* `base` is the first member, so a pointer to it is a pointer to the
   * wrapper. That is what lets the wrapper be a plain local in the caller. */
  bridge_subject* wrap = (bridge_subject*)self;
  omni_result result = {NULL, NULL};

  /* An entry carrying no `in` at all is called with one ABSENT argument, not
   * null - `typify()` is 1073741824 where `typify(null)` is 4194432. */
  voxgig_value* in = bridge_tostruct(0 < nargs ? args[0] : NULL);

  char* err = NULL;
  voxgig_value* got = wrap->fn(in, &err, wrap->ud);

  if (NULL != err) {
    result.err = omni_pool_strdup(wrap->pool, err);
    free(err);
  } else {
    result.val = bridge_toomni(wrap->pool, got);
  }

  /* Write the argument back, so an in-place rewrite is visible to `match`.
   * Only a node can be rewritten in place, and the `client` pointer omni
   * attached to a contextified argument has to survive the swap. */
  if (0 < nargs && voxgig_is_node(in)) {
    omni_json* back = bridge_toomni(wrap->pool, in);
    back->client = args[0]->client;
    args[0] = back;
  }

  voxgig_release(got);
  voxgig_release(in);

  return result;
}

static bridge_subject bridge_wrap(omni_pool* pool, bridge_subject_fn fn, void* ud) {
  bridge_subject wrap;
  wrap.base.call = bridge_call;
  wrap.base.data = NULL;
  wrap.fn = fn;
  wrap.ud = ud;
  wrap.pool = pool;
  return wrap;
}

#endif /* VOXGIG_STRUCT_OMNI_BRIDGE_H */
