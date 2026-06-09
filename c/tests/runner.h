/* Voxgig Struct corpus runner — C port.
 * Mirrors cpp/tests/runner.hpp.
 */

#ifndef VOXGIG_STRUCT_RUNNER_H
#define VOXGIG_STRUCT_RUNNER_H

#include "voxgig_struct.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Subject: function from input value to output value.
 * On error, the subject may set *err to an error message (caller-owned char*).
 */
typedef voxgig_value* (*runner_subject_fn)(voxgig_value* in, char** err, void* ud);

typedef struct runner_result {
  char* name;
  int passed;
  int total;
  /* Failure messages (owned). */
  size_t fail_len;
  size_t fail_cap;
  char** failures;
} runner_result;

static inline void runner_result_init(runner_result* r, const char* name) {
  r->name = strdup(name);
  r->passed = 0;
  r->total = 0;
  r->fail_len = 0;
  r->fail_cap = 0;
  r->failures = NULL;
}

static inline void runner_result_free(runner_result* r) {
  free(r->name);
  for (size_t i = 0; i < r->fail_len; i++)
    free(r->failures[i]);
  free(r->failures);
}

static inline void runner_push_failure(runner_result* r, const char* msg) {
  if (r->fail_len + 1 > r->fail_cap) {
    size_t nc = r->fail_cap == 0 ? 8 : r->fail_cap * 2;
    r->failures = (char**)realloc(r->failures, nc * sizeof(char*));
    r->fail_cap = nc;
  }
  r->failures[r->fail_len++] = strdup(msg);
}

/* Normalize: turn integer-valued doubles into ints; sort map keys; sentinels and
 * undef → null for stable comparison. */
static voxgig_value* normalize(const voxgig_value* v) {
  if (!v || voxgig_is_undef(v) || voxgig_is_null(v))
    return voxgig_new_null();
  if (voxgig_is_double(v)) {
    double d = voxgig_as_double(v);
    if (isfinite(d) && floor(d) == d)
      return voxgig_new_int((int64_t)d);
    return voxgig_new_double(d);
  }
  if (voxgig_is_list(v)) {
    voxgig_value* out = voxgig_new_list();
    voxgig_list* l = voxgig_as_list(v);
    for (size_t i = 0; i < l->len; i++) {
      voxgig_list_push(voxgig_as_list(out), normalize(l->items[i]));
    }
    return out;
  }
  if (voxgig_is_map(v)) {
    /* Sort by key (alphabetical). */
    voxgig_map* m = voxgig_as_map(v);
    size_t n = m->len;
    size_t* idx = (size_t*)malloc(n * sizeof(size_t) + 1);
    for (size_t i = 0; i < n; i++)
      idx[i] = i;
    for (size_t i = 1; i < n; i++) {
      size_t j = i;
      while (j > 0 && strcmp(m->entries[idx[j - 1]].key, m->entries[idx[j]].key) > 0) {
        size_t t = idx[j - 1];
        idx[j - 1] = idx[j];
        idx[j] = t;
        j--;
      }
    }
    voxgig_value* out = voxgig_new_map();
    for (size_t i = 0; i < n; i++) {
      voxgig_map_set(voxgig_as_map(out), m->entries[idx[i]].key,
                     normalize(m->entries[idx[i]].value));
    }
    free(idx);
    return out;
  }
  return voxgig_clone((voxgig_value*)v);
}

static bool deep_equal(const voxgig_value* a, const voxgig_value* b) {
  voxgig_value* na = normalize(a);
  voxgig_value* nb = normalize(b);
  bool eq = voxgig_equals(na, nb);
  voxgig_release(na);
  voxgig_release(nb);
  return eq;
}

static char* brief(const voxgig_value* v) {
  if (!v || voxgig_is_undef(v))
    return strdup("__UNDEF__");
  char* s = voxgig_jsonify((voxgig_value*)v, NULL);
  if (!s)
    return strdup("?");
  size_t n = strlen(s);
  if (n > 200) {
    s[197] = '\0';
    char* tmp = (char*)malloc(202);
    snprintf(tmp, 202, "%s...", s);
    free(s);
    return tmp;
  }
  return s;
}

__attribute__((unused)) static void str_lower(char* s) {
  for (; *s; s++)
    *s = (char)tolower((unsigned char)*s);
}

/* Deep-copy `v`, replacing every JSON null with the marker string "__NULL__".
 * Mirrors what the TS / JS / Py / Go / Lua runners do under their null flag —
 * the corpus uses null in source to mean "JSON null" but every runner
 * substitutes a string marker so comparisons can be done in JSON-poor
 * languages. */
__attribute__((unused)) static voxgig_value* null_substitute(voxgig_value* v) {
  if (!v || voxgig_is_undef(v))
    return voxgig_new_undef();
  if (voxgig_is_null(v))
    return voxgig_new_string("__NULL__");
  if (voxgig_is_list(v)) {
    voxgig_value* out = voxgig_new_list();
    voxgig_list* l = voxgig_as_list(v);
    for (size_t i = 0; i < l->len; i++)
      voxgig_list_push(voxgig_as_list(out), null_substitute(l->items[i]));
    return out;
  }
  if (voxgig_is_map(v)) {
    voxgig_value* out = voxgig_new_map();
    voxgig_map* m = voxgig_as_map(v);
    for (size_t i = 0; i < m->len; i++)
      voxgig_map_set(voxgig_as_map(out), m->entries[i].key, null_substitute(m->entries[i].value));
    return out;
  }
  return voxgig_clone(v);
}

static void run_subject(runner_result* res, voxgig_value* testspec, bool null_flag,
                        runner_subject_fn subj, void* ud) {
  voxgig_value* setk = voxgig_new_string("set");
  voxgig_value* set = voxgig_getprop(testspec, setk, NULL);
  voxgig_release(setk);
  if (!voxgig_is_list(set)) {
    voxgig_release(set);
    return;
  }
  voxgig_list* sl = voxgig_as_list(set);
  for (size_t i = 0; i < sl->len; i++) {
    voxgig_value* eo = sl->items[i];
    if (!voxgig_is_map(eo))
      continue;
    /* Use voxgig_map_get directly: voxgig_haskey treats null at a key as "no value"
       (Group A rule), but the runner needs literal presence to preserve
       test inputs like { in: null } where null IS the value to pass. */
    voxgig_value* in_raw_ptr = voxgig_map_get(voxgig_as_map(eo), "in");
    bool has_in = (in_raw_ptr != NULL);
    voxgig_value* in_raw = in_raw_ptr ? voxgig_retain(in_raw_ptr) : voxgig_new_undef();
    voxgig_value* in = has_in ? voxgig_clone(in_raw) : voxgig_new_undef();
    voxgig_value* out_raw_ptr = voxgig_map_get(voxgig_as_map(eo), "out");
    bool has_out = (out_raw_ptr != NULL);
    voxgig_value* expected = NULL;
    if (has_out)
      expected = voxgig_retain(out_raw_ptr);
    else if (null_flag)
      expected = voxgig_new_null();
    else
      expected = voxgig_new_undef();
    voxgig_value* err_ptr = voxgig_map_get(voxgig_as_map(eo), "err");
    voxgig_value* err_v = err_ptr ? voxgig_retain(err_ptr) : voxgig_new_undef();

    res->total++;
    char* err_msg = NULL;
    voxgig_value* got = subj(in, &err_msg, ud);

    if (!voxgig_is_undef(err_v)) {
      /* Test expects an error. Check if err_msg was set. */
      bool match = false;
      if (err_msg) {
        if (voxgig_is_bool(err_v) && voxgig_as_bool(err_v)) {
          match = true;
        } else if (voxgig_is_string(err_v)) {
          const char* es = voxgig_as_string(err_v);
          if (!es || !*es)
            match = true;
          else if (strstr(err_msg, es))
            match = true;
          else {
            /* Case-insensitive substring. */
            char* lm = strdup(err_msg);
            char* le = strdup(es);
            str_lower(lm);
            str_lower(le);
            if (strstr(lm, le))
              match = true;
            free(lm);
            free(le);
          }
        }
      }
      if (match) {
        res->passed++;
      } else {
        char* gs = brief(got);
        char* es = brief(err_v);
        char buf[2048];
        snprintf(buf, sizeof(buf), "[%zu] err mode (expected '%s' got err='%s' val=%s)", i, es,
                 err_msg ? err_msg : "(no err)", gs);
        runner_push_failure(res, buf);
        free(gs);
        free(es);
      }
      free(err_msg);
      voxgig_release(got);
      voxgig_release(err_v);
      voxgig_release(in);
      voxgig_release(in_raw);
      voxgig_release(expected);
      continue;
    }

    if (err_msg) {
      char* gs = brief(got);
      char* ins = brief(in_raw);
      char buf[2048];
      snprintf(buf, sizeof(buf), "[%zu] in=%s threw='%s' got=%s", i, ins, err_msg, gs);
      runner_push_failure(res, buf);
      free(gs);
      free(ins);
    } else if (deep_equal(got, expected)) {
      res->passed++;
    } else {
      char* gs = brief(got);
      char* es = brief(expected);
      char* ins = brief(in_raw);
      char buf[2048];
      snprintf(buf, sizeof(buf), "[%zu] in=%s expected=%s got=%s", i, ins, es, gs);
      runner_push_failure(res, buf);
      free(gs);
      free(es);
      free(ins);
    }
    free(err_msg);
    voxgig_release(got);
    voxgig_release(err_v);
    voxgig_release(in);
    voxgig_release(in_raw);
    voxgig_release(expected);
  }
  voxgig_release(set);
}

#endif
