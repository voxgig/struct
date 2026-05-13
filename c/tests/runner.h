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
typedef vs_value* (*runner_subject_fn)(vs_value* in, char** err, void* ud);

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
static vs_value* normalize(const vs_value* v) {
  if (!v || vs_is_undef(v) || vs_is_null(v))
    return vs_new_null();
  if (vs_is_double(v)) {
    double d = vs_as_double(v);
    if (isfinite(d) && floor(d) == d)
      return vs_new_int((int64_t)d);
    return vs_new_double(d);
  }
  if (vs_is_list(v)) {
    vs_value* out = vs_new_list();
    vs_list* l = vs_as_list(v);
    for (size_t i = 0; i < l->len; i++) {
      vs_list_push(vs_as_list(out), normalize(l->items[i]));
    }
    return out;
  }
  if (vs_is_map(v)) {
    /* Sort by key (alphabetical). */
    vs_map* m = vs_as_map(v);
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
    vs_value* out = vs_new_map();
    for (size_t i = 0; i < n; i++) {
      vs_map_set(vs_as_map(out), m->entries[idx[i]].key, normalize(m->entries[idx[i]].value));
    }
    free(idx);
    return out;
  }
  return vs_clone((vs_value*)v);
}

static bool deep_equal(const vs_value* a, const vs_value* b) {
  vs_value* na = normalize(a);
  vs_value* nb = normalize(b);
  bool eq = vs_equals(na, nb);
  vs_release(na);
  vs_release(nb);
  return eq;
}

static char* brief(const vs_value* v) {
  if (!v || vs_is_undef(v))
    return strdup("__UNDEF__");
  char* s = vs_jsonify((vs_value*)v, NULL);
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
static vs_value* null_substitute(vs_value* v) {
  if (!v || vs_is_undef(v))
    return vs_new_undef();
  if (vs_is_null(v))
    return vs_new_string("__NULL__");
  if (vs_is_list(v)) {
    vs_value* out = vs_new_list();
    vs_list* l = vs_as_list(v);
    for (size_t i = 0; i < l->len; i++)
      vs_list_push(vs_as_list(out), null_substitute(l->items[i]));
    return out;
  }
  if (vs_is_map(v)) {
    vs_value* out = vs_new_map();
    vs_map* m = vs_as_map(v);
    for (size_t i = 0; i < m->len; i++)
      vs_map_set(vs_as_map(out), m->entries[i].key, null_substitute(m->entries[i].value));
    return out;
  }
  return vs_clone(v);
}

static void run_subject(runner_result* res, vs_value* testspec, bool null_flag,
                        runner_subject_fn subj, void* ud) {
  vs_value* setk = vs_new_string("set");
  vs_value* set = vs_getprop(testspec, setk, NULL);
  vs_release(setk);
  if (!vs_is_list(set)) {
    vs_release(set);
    return;
  }
  vs_list* sl = vs_as_list(set);
  for (size_t i = 0; i < sl->len; i++) {
    vs_value* eo = sl->items[i];
    if (!vs_is_map(eo))
      continue;
    vs_value* ink = vs_new_string("in");
    bool has_in = vs_haskey(eo, ink);
    vs_value* in_raw = vs_getprop(eo, ink, NULL);
    vs_release(ink);
    vs_value* in = has_in ? vs_clone(in_raw) : vs_new_undef();
    vs_value* outk = vs_new_string("out");
    bool has_out = vs_haskey(eo, outk);
    vs_value* expected = NULL;
    if (has_out)
      expected = vs_getprop(eo, outk, NULL);
    else if (null_flag)
      expected = vs_new_null();
    else
      expected = vs_new_undef();
    vs_release(outk);
    vs_value* errk = vs_new_string("err");
    vs_value* err_v = vs_haskey(eo, errk) ? vs_getprop(eo, errk, NULL) : vs_new_undef();
    vs_release(errk);

    res->total++;
    char* err_msg = NULL;
    vs_value* got = subj(in, &err_msg, ud);

    if (!vs_is_undef(err_v)) {
      /* Test expects an error. Check if err_msg was set. */
      bool match = false;
      if (err_msg) {
        if (vs_is_bool(err_v) && vs_as_bool(err_v)) {
          match = true;
        } else if (vs_is_string(err_v)) {
          const char* es = vs_as_string(err_v);
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
      vs_release(got);
      vs_release(err_v);
      vs_release(in);
      vs_release(in_raw);
      vs_release(expected);
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
    vs_release(got);
    vs_release(err_v);
    vs_release(in);
    vs_release(in_raw);
    vs_release(expected);
  }
  vs_release(set);
}

#endif
