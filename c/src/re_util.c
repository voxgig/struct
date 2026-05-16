/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
 *
 * Voxgig Struct — regex utility wrappers (re_*). Thin layer over the
 * vendored RE2-subset engine in regex.c so internal call sites read the same
 * as the canonical TS.
 */

#include "regex.h"
#include "voxgig_struct.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

static char* rdup(const char* s) {
  if (!s)
    s = "";
  size_t n = strlen(s);
  char* o = (char*)malloc(n + 1);
  if (!o)
    abort();
  memcpy(o, s, n + 1);
  return o;
}

vs_regex* vs_re_compile(const char* pattern) {
  return vs_regex_compile(pattern, NULL);
}

bool vs_re_test(const char* pattern, const char* input) {
  vs_regex* re = vs_regex_compile(pattern, NULL);
  if (!re)
    return false;
  bool out = vs_regex_test(re, input, input ? strlen(input) : 0);
  vs_regex_free(re);
  return out;
}

bool vs_re_test_re(const vs_regex* re, const char* input) {
  return re ? vs_regex_test(re, input ? input : "", input ? strlen(input) : 0) : false;
}

vs_strvec vs_re_find_re(const vs_regex* re, const char* input) {
  vs_strvec out;
  vs_strvec_init(&out);
  if (!re || !input)
    return out;
  int ngroups = vs_regex_ngroups(re);
  int* caps = (int*)malloc(sizeof(int) * (size_t)(ngroups * 2));
  for (int i = 0; i < ngroups * 2; i++)
    caps[i] = -1;
  if (vs_regex_find(re, input, strlen(input), caps, ngroups)) {
    for (int g = 0; g < ngroups; g++) {
      int s = caps[2 * g], e = caps[2 * g + 1];
      if (s < 0 || e < s) {
        vs_strvec_push(&out, "");
      } else {
        vs_strvec_push_n(&out, input + s, (size_t)(e - s));
      }
    }
  }
  free(caps);
  return out;
}

vs_strvec vs_re_find(const char* pattern, const char* input) {
  vs_regex* re = vs_regex_compile(pattern, NULL);
  vs_strvec out = vs_re_find_re(re, input);
  vs_regex_free(re);
  return out;
}

void vs_strvec_vec_init(vs_strvec_vec* v) {
  v->len = 0;
  v->cap = 0;
  v->data = NULL;
}

void vs_strvec_vec_free(vs_strvec_vec* v) {
  if (!v)
    return;
  for (size_t i = 0; i < v->len; i++) {
    vs_strvec_free(&v->data[i]);
  }
  free(v->data);
  v->data = NULL;
  v->len = v->cap = 0;
}

static void vs_strvec_vec_push(vs_strvec_vec* v, vs_strvec row) {
  if (v->len == v->cap) {
    size_t nc = v->cap == 0 ? 4 : v->cap * 2;
    v->data = (vs_strvec*)realloc(v->data, nc * sizeof(vs_strvec));
    if (!v->data)
      abort();
    v->cap = nc;
  }
  v->data[v->len++] = row;
}

vs_strvec_vec vs_re_find_all_re(const vs_regex* re, const char* input) {
  vs_strvec_vec out;
  vs_strvec_vec_init(&out);
  if (!re || !input)
    return out;
  size_t ilen = strlen(input);
  /* Grow the caps buffer until vs_regex_find_all stops filling it. */
  int max_matches = 64;
  int per_row = 2 * VS_REGEX_MAX_GROUPS;
  int* caps = NULL;
  int count = 0;
  for (;;) {
    caps = (int*)realloc(caps, (size_t)(max_matches * per_row) * sizeof(int));
    if (!caps)
      abort();
    count = vs_regex_find_all(re, input, ilen, caps, max_matches);
    if (count < max_matches)
      break;
    max_matches *= 2;
  }
  int ngroups = vs_regex_ngroups(re);
  for (int m = 0; m < count; m++) {
    int* row_caps = caps + m * per_row;
    vs_strvec row;
    vs_strvec_init(&row);
    for (int g = 0; g < ngroups; g++) {
      int s = row_caps[2 * g], e = row_caps[2 * g + 1];
      if (s < 0 || e < s) {
        vs_strvec_push(&row, "");
      } else {
        vs_strvec_push_n(&row, input + s, (size_t)(e - s));
      }
    }
    vs_strvec_vec_push(&out, row);
  }
  free(caps);
  return out;
}

vs_strvec_vec vs_re_find_all(const char* pattern, const char* input) {
  vs_regex* re = vs_regex_compile(pattern, NULL);
  vs_strvec_vec out = vs_re_find_all_re(re, input);
  vs_regex_free(re);
  return out;
}

char* vs_re_replace_re(const vs_regex* re, const char* input, const char* replacement) {
  if (!re)
    return rdup(input);
  return vs_regex_replace(re, input ? input : "", input ? strlen(input) : 0,
                          replacement ? replacement : "");
}

char* vs_re_replace(const char* pattern, const char* input, const char* replacement) {
  vs_regex* re = vs_regex_compile(pattern, NULL);
  char* out = vs_re_replace_re(re, input, replacement);
  vs_regex_free(re);
  return out;
}

/* Adapter to bridge the engine's int*-based callback to a strvec-based one. */
struct cb_ctx {
  char* (*user_cb)(const vs_strvec* caps, void* ud);
  void* user_ud;
};

static char* cb_adapter(const int* caps, int ncaps, const char* input, void* ud) {
  struct cb_ctx* ctx = (struct cb_ctx*)ud;
  vs_strvec sv;
  vs_strvec_init(&sv);
  for (int g = 0; g < ncaps; g++) {
    int s = caps[2 * g], e = caps[2 * g + 1];
    if (s < 0 || e < s) {
      vs_strvec_push(&sv, "");
    } else {
      vs_strvec_push_n(&sv, input + s, (size_t)(e - s));
    }
  }
  char* out = ctx->user_cb(&sv, ctx->user_ud);
  vs_strvec_free(&sv);
  return out;
}

char* vs_re_replace_cb(const vs_regex* re, const char* input,
                       char* (*cb)(const vs_strvec* caps, void* ud), void* ud) {
  if (!re || !input)
    return rdup(input);
  struct cb_ctx ctx = {cb, ud};
  return vs_regex_replace_cb_fn(re, input, strlen(input), cb_adapter, &ctx);
}

char* vs_re_escape(const char* literal) {
  if (!literal)
    literal = "";
  /* Same set as canonical R_ESCAPE_REGEXP: [.*+?^${}()|\[\]\\] */
  size_t n = strlen(literal);
  char* o = (char*)malloc(n * 2 + 1);
  if (!o)
    abort();
  size_t j = 0;
  for (size_t i = 0; i < n; i++) {
    char c = literal[i];
    if (c == '.' || c == '*' || c == '+' || c == '?' || c == '^' || c == '$' || c == '{' ||
        c == '}' || c == '(' || c == ')' || c == '|' || c == '[' || c == ']' || c == '\\') {
      o[j++] = '\\';
    }
    o[j++] = c;
  }
  o[j] = '\0';
  return o;
}
