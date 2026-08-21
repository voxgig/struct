/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

/*
 * Voxgig Struct — the shared corpus, run on the shared runner.
 *
 * The in-situ runner (tests/runner.h) is gone. Every group is driven through
 * voxgig/omni, so this file only says WHICH subject answers each group and
 * with which flags — the entry loop, the comparison, the `err` and `match`
 * handling all live in the runner, identically for every port.
 *
 * Flags mirror canonical: typescript/test/utility/StructUtility.test.ts.
 */

#include "omni_bridge.h"
#include "voxgig_struct.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static omni_pool* POOL = NULL;
static omni_runpack* PACK = NULL;
static omni_json* SPEC = NULL;

static int GROUPS = 0;
static int FAILED = 0;

/* One named group of the resolved spec: `struct.<category>.<name>`. */
static omni_json* group_spec(const char* category, const char* name) {
  return omni_map_get(omni_map_get(SPEC, category), name);
}

/* Run one group. Each group is one assertion: omni stops at its first failing
 * entry and reports the index, the entry and both values. */
static void run(const char* category, const char* name, bool donull, bridge_subject_fn fn,
                void* ud) {
  bridge_subject wrap = bridge_wrap(POOL, fn, ud);
  omni_flags flags = donull ? omni_flags_default() : omni_flags_nonull();

  char label[128];
  snprintf(label, sizeof(label), "%s.%s", category, name);
  /* Pool-owned: the label outlives this frame inside a failure message. */
  flags.name = omni_pool_strdup(POOL, label);

  char* err = NULL;
  int rc = omni_runsetflags(PACK, group_spec(category, name), flags, &wrap.base, &err);

  GROUPS++;
  if (0 == rc) {
    printf("  ok   %s\n", label);
  } else {
    FAILED++;
    printf("  FAIL %s\n       %s\n", label, err ? err : "(no message)");
  }
}

/* `merge.basic`, `inject.basic` and `transform.basic` are single entries, not
 * sets, so the runner cannot drive them. Compared here, through omni's own
 * deepequal so the rule is the one every group uses. Takes one reference. */
static void single(const char* label, omni_json* entry, voxgig_value* got) {
  omni_json* want = omni_map_get(entry, "out");
  omni_json* have = bridge_toomni(POOL, got);

  GROUPS++;
  if (omni_deepequal(have, want)) {
    printf("  ok   %s\n", label);
  } else {
    FAILED++;
    printf("  FAIL %s\n       expected: %s\n       actual:   %s\n", label,
           omni_stringify(POOL, want), omni_stringify(POOL, have));
  }

  voxgig_release(got);
}

/* Helpers. */
/* Raw map lookup for runner field extraction. Unlike voxgig_getprop (Group A,
 * which treats null at a key as "no value"), this returns the literal stored
 * value — including null — so tests for Group B functions like stringify and
 * pad receive their corpus input verbatim. */
static voxgig_value* getp(voxgig_value* in, const char* key) {
  if (!voxgig_is_map(in))
    return voxgig_new_undef();
  voxgig_value* v = voxgig_map_get(voxgig_as_map(in), key);
  return v ? voxgig_retain(v) : voxgig_new_undef();
}

/* As getp, but answers NULL when the key is ABSENT rather than an undef
 * value - the difference between "the entry omitted `alt`" and "the entry set
 * `alt` to null", which the argument list has to preserve. */
static voxgig_value* getp_literal(voxgig_value* in, const char* key) {
  if (!voxgig_is_map(in))
    return NULL;
  voxgig_value* v = voxgig_map_get(voxgig_as_map(in), key);
  return v ? voxgig_retain(v) : NULL;
}

/* Under `null: true` the runner replaces every corpus null with this marker,
 * so it survives a JSON round trip in a language without one. */
static bool is_nullmark(const voxgig_value* v) {
  return voxgig_is_string(v) && 0 == strcmp(voxgig_as_string(v), OMNI_NULLMARK);
}

/* Canonical throws when an injector reports a problem; this port collects the
 * messages instead, and the subject raises them. Defined below. */
static char* join_errs(voxgig_value* errs);

/* Marks the one inject group that wants the NULLMARK modifier. A function
 * pointer is not convertible to void* in ISO C, so the flag is an object. */
static const int USE_NULLMODIFIER = 1;

/* Subject implementations. */
static voxgig_value* subj_isnode(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  return voxgig_new_bool(voxgig_isnode(in));
}
static voxgig_value* subj_ismap(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  return voxgig_new_bool(voxgig_ismap(in));
}
static voxgig_value* subj_islist(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  return voxgig_new_bool(voxgig_islist(in));
}
static voxgig_value* subj_iskey(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  return voxgig_new_bool(voxgig_iskey(in));
}
static voxgig_value* subj_isempty(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  return voxgig_new_bool(voxgig_isempty(in));
}
static voxgig_value* subj_isfunc(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  return voxgig_new_bool(voxgig_isfunc(in));
}
static voxgig_value* subj_typify(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  return voxgig_new_int(voxgig_typify(in));
}
static voxgig_value* subj_typename(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  if (voxgig_is_int(in))
    return voxgig_new_string(voxgig_typename((int)voxgig_as_int(in)));
  return voxgig_new_string(voxgig_typename(voxgig_typify(in)));
}
static voxgig_value* subj_clone(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  return voxgig_clone(in);
}
static voxgig_value* subj_size(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  return voxgig_new_int(voxgig_size(in));
}
static voxgig_value* subj_strkey(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  char* s = voxgig_strkey(in);
  voxgig_value* v = voxgig_new_string(s);
  free(s);
  return v;
}
static voxgig_value* subj_keysof(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_strvec ks = voxgig_keysof(in);
  voxgig_value* out = voxgig_new_list();
  for (size_t i = 0; i < ks.len; i++)
    voxgig_list_push(voxgig_as_list(out), voxgig_new_string(ks.data[i]));
  voxgig_strvec_free(&ks);
  return out;
}
static voxgig_value* subj_items(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  return voxgig_items_v(in);
}
static voxgig_value* subj_haskey(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* src = getp(in, "src");
  voxgig_value* key = getp(in, "key");
  bool r = voxgig_haskey(src, key);
  voxgig_release(src);
  voxgig_release(key);
  return voxgig_new_bool(r);
}
static voxgig_value* subj_getprop(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* val = getp(in, "val");
  voxgig_value* key = getp(in, "key");
  /* Canonical omits `alt` only when the KEY is missing
   * (`undefined === vin.alt`), so an explicit `alt: null` is passed through -
   * unlike getelem below, which omits a null alt too (`null == vin.alt`).
   * `voxgig_haskey` is the Group A rule and could not tell them apart.
   * `minor/getprop#51` is the entry that separates them. */
  voxgig_value* alt = getp_literal(in, "alt");
  voxgig_value* r = voxgig_getprop(val, key, alt);
  voxgig_release(val);
  voxgig_release(key);
  voxgig_release(alt);
  return r;
}
static voxgig_value* subj_getelem(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* val = getp(in, "val");
  voxgig_value* key = getp(in, "key");
  voxgig_value* altk = voxgig_new_string("alt");
  voxgig_value* alt = voxgig_haskey(in, altk) ? voxgig_getprop(in, altk, NULL) : NULL;
  voxgig_release(altk);
  voxgig_value* r = voxgig_getelem(val, key, alt);
  voxgig_release(val);
  voxgig_release(key);
  voxgig_release(alt);
  return r;
}
static voxgig_value* subj_setprop(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* parent = getp(in, "parent");
  if (!parent || voxgig_is_undef(parent)) {
    voxgig_release(parent);
    parent = voxgig_new_null();
  }
  voxgig_value* key = getp(in, "key");
  voxgig_value* val = getp(in, "val");
  voxgig_value* r = voxgig_setprop(parent, key, val);
  voxgig_value* ret = r ? voxgig_retain(r) : voxgig_new_undef();
  voxgig_release(parent);
  voxgig_release(key);
  voxgig_release(val);
  return ret;
}
static voxgig_value* subj_delprop(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* parent = getp(in, "parent");
  if (!parent || voxgig_is_undef(parent)) {
    voxgig_release(parent);
    parent = voxgig_new_null();
  }
  voxgig_value* key = getp(in, "key");
  voxgig_value* r = voxgig_delprop(parent, key);
  voxgig_value* ret = r ? voxgig_retain(r) : voxgig_new_undef();
  voxgig_release(parent);
  voxgig_release(key);
  return ret;
}
static voxgig_value* subj_stringify(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* val = getp(in, "val");
  voxgig_value* max = getp(in, "max");
  /* This group runs with `null: true`, so a corpus null arrives as the
   * NULLMARK string. Canonical hands `stringify` the word it would print. */
  if (is_nullmark(val)) {
    voxgig_release(val);
    val = voxgig_new_string("null");
  }
  int m = -1;
  if (voxgig_is_int(max))
    m = (int)voxgig_as_int(max);
  char* s = voxgig_stringify(val, m);
  voxgig_value* r = voxgig_new_string(s);
  free(s);
  voxgig_release(val);
  voxgig_release(max);
  return r;
}
static voxgig_value* subj_jsonify(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* val = getp(in, "val");
  voxgig_value* flags = getp(in, "flags");
  char* s = voxgig_jsonify(val, flags);
  voxgig_value* r = voxgig_new_string(s);
  free(s);
  voxgig_release(val);
  voxgig_release(flags);
  return r;
}
/* Replace every occurrence of `find` in `text`. Caller owns the result. */
static char* str_replace_all(const char* text, const char* find, const char* with) {
  size_t flen = strlen(find);
  size_t wlen = strlen(with);
  size_t cap = strlen(text) + 1;
  char* out = (char*)malloc(cap);
  size_t len = 0;

  for (const char* p = text; '\0' != *p;) {
    if (0 == strncmp(p, find, flen)) {
      cap += wlen;
      char* grown = (char*)realloc(out, cap);
      if (NULL == grown) {
        free(out);
        return NULL;
      }
      out = grown;
      memcpy(out + len, with, wlen);
      len += wlen;
      p += flen;
    } else {
      out[len++] = *p++;
    }
  }
  out[len] = '\0';
  return out;
}

/* This group runs with `null: true`, so an ABSENT path arrives as the NULLMARK
 * string and canonical puts the rendering back the way a real undefined would
 * read: the marker segment disappears, and a `>` terminator gains `:null`. */
static voxgig_value* subj_pathify(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* path = getp(in, "path");
  voxgig_value* from = getp(in, "from");
  voxgig_value* to = getp(in, "to");
  bool marked = is_nullmark(path);
  if (marked) {
    voxgig_release(path);
    path = voxgig_new_undef();
  }
  int f = voxgig_is_int(from) ? (int)voxgig_as_int(from) : 0;
  int t = voxgig_is_int(to) ? (int)voxgig_as_int(to) : 0;

  char* rendered = voxgig_pathify(path, f, t);
  char* stripped = str_replace_all(rendered, OMNI_NULLMARK ".", "");
  free(rendered);
  char* final = marked ? str_replace_all(stripped, ">", ":null>") : stripped;
  if (final != stripped)
    free(stripped);

  voxgig_value* r = voxgig_new_string(final);
  free(final);
  voxgig_release(path);
  voxgig_release(from);
  voxgig_release(to);
  return r;
}
static voxgig_value* subj_escre(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  char* s = voxgig_escre(in);
  voxgig_value* r = voxgig_new_string(s);
  free(s);
  return r;
}
static voxgig_value* subj_escurl(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  char* s = voxgig_escurl(in);
  voxgig_value* r = voxgig_new_string(s);
  free(s);
  return r;
}
static voxgig_value* subj_join(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* val = getp(in, "val");
  voxgig_value* sep = getp(in, "sep");
  voxgig_value* url = getp(in, "url");
  char* s = voxgig_join_v(val, sep, url);
  voxgig_value* r = voxgig_new_string(s);
  free(s);
  voxgig_release(val);
  voxgig_release(sep);
  voxgig_release(url);
  return r;
}
static voxgig_value* subj_flatten(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* val = getp(in, "val");
  voxgig_value* depth = getp(in, "depth");
  voxgig_value* r = voxgig_flatten(val, depth);
  voxgig_release(val);
  voxgig_release(depth);
  return r;
}

static bool gt3(voxgig_value* pair, void* ud) {
  (void)ud;
  voxgig_value* one = voxgig_new_int(1);
  voxgig_value* v = voxgig_getprop(pair, one, NULL);
  voxgig_release(one);
  bool ok = voxgig_is_number(v) && voxgig_as_double(v) > 3;
  voxgig_release(v);
  return ok;
}
static bool lt3(voxgig_value* pair, void* ud) {
  (void)ud;
  voxgig_value* one = voxgig_new_int(1);
  voxgig_value* v = voxgig_getprop(pair, one, NULL);
  voxgig_release(one);
  bool ok = voxgig_is_number(v) && voxgig_as_double(v) < 3;
  voxgig_release(v);
  return ok;
}
static voxgig_value* subj_filter(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* val = getp(in, "val");
  voxgig_value* checkk = voxgig_new_string("check");
  voxgig_value* check = voxgig_getprop(in, checkk, NULL);
  voxgig_release(checkk);
  voxgig_itemcheck_fn pred = lt3;
  if (voxgig_is_string(check) && strcmp(voxgig_as_string(check), "gt3") == 0)
    pred = gt3;
  voxgig_value* r = voxgig_filter(val, pred, NULL);
  voxgig_release(val);
  voxgig_release(check);
  return r;
}
static voxgig_value* subj_slice(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* val = getp(in, "val");
  voxgig_value* start = getp(in, "start");
  voxgig_value* end = getp(in, "end");
  voxgig_value* r = voxgig_slice(val, start, end, false);
  voxgig_release(val);
  voxgig_release(start);
  voxgig_release(end);
  return r;
}
static voxgig_value* subj_pad(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* val = getp(in, "val");
  voxgig_value* pd = getp(in, "pad");
  voxgig_value* ch = getp(in, "char");
  char* s = voxgig_pad(val, pd, ch);
  voxgig_value* r = voxgig_new_string(s);
  free(s);
  voxgig_release(val);
  voxgig_release(pd);
  voxgig_release(ch);
  return r;
}
static voxgig_value* subj_setpath(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* store = getp(in, "store");
  voxgig_value* path = getp(in, "path");
  voxgig_value* val = getp(in, "val");
  voxgig_value* r = voxgig_setpath(store, path, val, NULL);
  voxgig_value* ret = r ? voxgig_retain(r) : voxgig_new_undef();
  voxgig_release(store);
  voxgig_release(path);
  voxgig_release(val);
  return ret;
}

/* walk depth subject: builds a parallel deep tree, controlled by maxdepth. */
typedef struct walk_depth_state {
  voxgig_value* top;
  voxgig_value* cur;
} walk_depth_state;

static voxgig_value* walk_depth_cb(voxgig_value* key, voxgig_value* val, voxgig_value* parent,
                                   voxgig_value* path, void* ud) {
  (void)parent;
  (void)path;
  walk_depth_state* st = (walk_depth_state*)ud;
  if (!key || voxgig_is_undef(key) || voxgig_isnode(val)) {
    voxgig_value* child = voxgig_is_list(val) ? voxgig_new_list() : voxgig_new_map();
    if (!key || voxgig_is_undef(key)) {
      voxgig_release(st->top);
      st->top = child;
      st->cur = child;
    } else {
      voxgig_setprop(st->cur, key, child);
      st->cur = child;
    }
  } else {
    voxgig_setprop(st->cur, key, val);
  }
  return voxgig_retain(val);
}
static voxgig_value* subj_walk_depth(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  voxgig_value* src = getp(in, "src");
  voxgig_value* mdv = getp(in, "maxdepth");
  int md = voxgig_is_int(mdv) ? (int)voxgig_as_int(mdv) : VOXGIG_MAXDEPTH;
  walk_depth_state st = {NULL, NULL};
  voxgig_value* w = voxgig_walk(src, walk_depth_cb, NULL, md, &st);
  voxgig_release(w);
  voxgig_release(src);
  voxgig_release(mdv);
  voxgig_value* out = st.top ? st.top : voxgig_new_map();
  return out;
}

/* getpath relative. */
static voxgig_value* subj_getpath_relative(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  voxgig_value* store = getp(in, "store");
  voxgig_value* path = getp(in, "path");
  voxgig_injection* inj = voxgig_inj_new(NULL, NULL);
  inj->mode = 0;
  /* Apply dparent / dpath / base from input if present. */
  voxgig_value* dparent = getp(in, "dparent");
  if (dparent && !voxgig_is_undef(dparent)) {
    voxgig_release(inj->dparent);
    inj->dparent = dparent;
  } else {
    voxgig_release(dparent);
  }
  voxgig_value* dpath = getp(in, "dpath");
  if (voxgig_is_list(dpath)) {
    voxgig_strvec_clear(&inj->dpath);
    voxgig_list* l = voxgig_as_list(dpath);
    for (size_t i = 0; i < l->len; i++) {
      char* s = voxgig_strkey(l->items[i]);
      voxgig_strvec_push(&inj->dpath, s);
      free(s);
    }
  } else if (voxgig_is_string(dpath)) {
    voxgig_strvec_clear(&inj->dpath);
    const char* s = voxgig_as_string(dpath);
    size_t n = voxgig_string_len(dpath);
    size_t i = 0;
    while (i <= n) {
      size_t j = i;
      while (j < n && s[j] != '.')
        j++;
      voxgig_strvec_push_n(&inj->dpath, s + i, j - i);
      i = j + 1;
      if (j == n)
        break;
    }
  }
  voxgig_release(dpath);
  voxgig_value* base = getp(in, "base");
  if (voxgig_is_string(base)) {
    free(inj->base);
    inj->base = strdup(voxgig_as_string(base));
  }
  voxgig_release(base);
  voxgig_value* r = voxgig_getpath(store, path, inj);
  voxgig_inj_free(inj);
  voxgig_release(store);
  voxgig_release(path);
  return r;
}

/* getpath special: an `inj` map carries key/meta/dparent/dpath. Mirrors the
 * cpp port's getpath.special dispatch. */
static voxgig_value* subj_getpath_special(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  voxgig_value* store = getp(in, "store");
  voxgig_value* path = getp(in, "path");
  voxgig_value* injv = getp(in, "inj");
  if (!voxgig_is_map(injv)) {
    voxgig_value* r = voxgig_getpath(store, path, NULL);
    voxgig_release(store);
    voxgig_release(path);
    voxgig_release(injv);
    return r;
  }
  voxgig_injection* inj = voxgig_inj_new(NULL, NULL);
  inj->mode = 0;
  voxgig_value* k = getp(injv, "key");
  if (voxgig_is_string(k)) {
    free(inj->key);
    inj->key = strdup(voxgig_as_string(k));
  }
  voxgig_release(k);
  voxgig_value* m = getp(injv, "meta");
  if (voxgig_is_map(m)) {
    voxgig_release(inj->meta);
    inj->meta = voxgig_retain(m);
  }
  voxgig_release(m);
  voxgig_value* dparent = getp(injv, "dparent");
  if (dparent && !voxgig_is_undef(dparent)) {
    voxgig_release(inj->dparent);
    inj->dparent = dparent;
  } else {
    voxgig_release(dparent);
  }
  voxgig_value* dpath = getp(injv, "dpath");
  if (voxgig_is_list(dpath)) {
    voxgig_strvec_clear(&inj->dpath);
    voxgig_list* l = voxgig_as_list(dpath);
    for (size_t i = 0; i < l->len; i++) {
      char* s = voxgig_strkey(l->items[i]);
      voxgig_strvec_push(&inj->dpath, s);
      free(s);
    }
  }
  voxgig_release(dpath);
  voxgig_value* r = voxgig_getpath(store, path, inj);
  voxgig_inj_free(inj);
  voxgig_release(store);
  voxgig_release(path);
  voxgig_release(injv);
  return r;
}

/* getpath handler: store gets a $FOO injector returning "foo"; a custom handler
 * invokes the injector. Mirrors perl t/struct.t getpath.handler dispatch. */
static voxgig_value* foo_injector(voxgig_injection* inj, voxgig_value* val, const char* ref,
                                  voxgig_value* store, void* ud) {
  (void)inj;
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  return voxgig_new_string("foo");
}
static voxgig_value* handler_invoke(voxgig_injection* inj, voxgig_value* val, const char* ref,
                                    voxgig_value* store, void* ud) {
  (void)inj;
  (void)ref;
  (void)ud;
  /* Custom handler: invoke the injector value directly (perl: $val->()). */
  if (voxgig_is_injector(val))
    return val->as.fn.fn.inj(inj, val, ref, store, val->as.fn.ud);
  return val ? voxgig_retain(val) : voxgig_new_undef();
}
static voxgig_value* subj_getpath_handler(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  voxgig_value* store_in = getp(in, "store");
  voxgig_value* path = getp(in, "path");
  /* Build { '$TOP': store, '$FOO': <injector> }. */
  voxgig_value* store = voxgig_new_map();
  voxgig_map_set(voxgig_as_map(store), "$TOP",
                 store_in ? voxgig_retain(store_in) : voxgig_new_null());
  voxgig_map_set(voxgig_as_map(store), "$FOO", voxgig_new_injector(foo_injector, NULL));
  voxgig_injection* inj = voxgig_inj_new(NULL, NULL);
  inj->mode = 0;
  voxgig_release(inj->handler_val);
  inj->handler_val = voxgig_new_injector(handler_invoke, NULL);
  voxgig_value* r = voxgig_getpath(store, path, inj);
  voxgig_inj_free(inj);
  voxgig_release(store);
  voxgig_release(store_in);
  voxgig_release(path);
  return r;
}

/* Sentinels: getprop/getelem with val/key/alt. */
static voxgig_value* subj_sent_getprop(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  voxgig_value* val = getp(in, "val");
  voxgig_value* key = getp(in, "key");
  voxgig_value* altk = voxgig_new_string("alt");
  voxgig_value* alt =
      (voxgig_map_get(voxgig_as_map(in), "alt")) ? voxgig_getprop(in, altk, NULL) : NULL;
  voxgig_release(altk);
  voxgig_value* r = voxgig_getprop(val, key, alt);
  voxgig_release(val);
  voxgig_release(key);
  voxgig_release(alt);
  return r;
}
static voxgig_value* subj_sent_getelem(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  voxgig_value* val = getp(in, "val");
  voxgig_value* key = getp(in, "key");
  voxgig_value* altk = voxgig_new_string("alt");
  voxgig_value* alt =
      (voxgig_map_get(voxgig_as_map(in), "alt")) ? voxgig_getprop(in, altk, NULL) : NULL;
  voxgig_release(altk);
  voxgig_value* r = voxgig_getelem(val, key, alt);
  voxgig_release(val);
  voxgig_release(key);
  voxgig_release(alt);
  return r;
}
static voxgig_value* subj_sent_haskey(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  voxgig_value* val = getp(in, "val");
  voxgig_value* key = getp(in, "key");
  bool r = voxgig_haskey(val, key);
  voxgig_release(val);
  voxgig_release(key);
  return voxgig_new_bool(r);
}
static voxgig_value* subj_sent_isempty(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  return voxgig_new_bool(voxgig_isempty(in));
}
static voxgig_value* subj_sent_isnode(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  return voxgig_new_bool(voxgig_isnode(in));
}
static voxgig_value* subj_sent_stringify(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  char* s = voxgig_stringify(in, -1);
  voxgig_value* r = voxgig_new_string(s);
  free(s);
  return r;
}

/* Inject basic. */

/* Walk subjects. */
static voxgig_value* walk_basic_cb(voxgig_value* key, voxgig_value* val, voxgig_value* parent,
                                   voxgig_value* path, void* ud) {
  (void)key;
  (void)parent;
  (void)ud;
  if (voxgig_is_string(val)) {
    char* buf = NULL;
    size_t len = 0, cap = 0;
    const char* s = voxgig_as_string(val);
    size_t sl = voxgig_string_len(val);
    /* val + "~" + path.join(".") */
    cap = sl + 16;
    buf = (char*)malloc(cap);
    memcpy(buf, s, sl);
    len = sl;
    buf[len++] = '~';
    voxgig_list* pl = voxgig_as_list(path);
    for (size_t i = 0; i < pl->len; i++) {
      if (i > 0) {
        if (len + 1 >= cap) {
          cap *= 2;
          buf = (char*)realloc(buf, cap);
        }
        buf[len++] = '.';
      }
      const char* ps = voxgig_as_string(pl->items[i]);
      size_t psl = voxgig_string_len(pl->items[i]);
      if (len + psl + 1 >= cap) {
        while (cap < len + psl + 1)
          cap *= 2;
        buf = (char*)realloc(buf, cap);
      }
      memcpy(buf + len, ps, psl);
      len += psl;
    }
    buf[len] = '\0';
    voxgig_value* r = voxgig_new_string(buf);
    free(buf);
    return r;
  }
  return voxgig_retain(val);
}
static voxgig_value* subj_walk_basic(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  return voxgig_walk(in, walk_basic_cb, NULL, VOXGIG_MAXDEPTH, NULL);
}

/* Merge subjects. */
static voxgig_value* subj_merge(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  return voxgig_merge(in, VOXGIG_MAXDEPTH);
}
static voxgig_value* subj_merge_depth(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* val = getp(in, "val");
  voxgig_value* depth = getp(in, "depth");
  int d = voxgig_is_int(depth) ? (int)voxgig_as_int(depth) : VOXGIG_MAXDEPTH;
  voxgig_value* r = voxgig_merge(val, d);
  voxgig_release(val);
  voxgig_release(depth);
  return r;
}

/* getpath subjects. */
static voxgig_value* subj_getpath_basic(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* store = getp(in, "store");
  voxgig_value* path = getp(in, "path");
  voxgig_value* r = voxgig_getpath(store, path, NULL);
  voxgig_release(store);
  voxgig_release(path);
  return r;
}

/* inject subjects. */
/* The runner encodes "value is JSON null" as the NULLMARK string so it
 * survives a JSON round trip; a modifier puts a real null back as the
 * structure is built. `inject/string` needs it: entry 10 injects a stored null
 * INTO a string, and the marker has to read as the word `null` there. */
static void modify_nullmark(voxgig_value* val, voxgig_value* key, voxgig_value* parent,
                            voxgig_injection* inj, voxgig_value* store, void* ud) {
  (void)inj;
  (void)store;
  (void)ud;
  if (!voxgig_is_string(val) || NULL == key || !voxgig_is_node(parent))
    return;

  const char* text = voxgig_as_string(val);
  if (0 == strcmp(text, OMNI_NULLMARK)) {
    voxgig_setprop(parent, key, voxgig_new_null());
    return;
  }
  if (NULL == strstr(text, OMNI_NULLMARK))
    return;

  char* replaced = str_replace_all(text, OMNI_NULLMARK, "null");
  voxgig_setprop(parent, key, voxgig_new_string(replaced));
  free(replaced);
}

static voxgig_value* subj_inject(voxgig_value* in, char** err, void* ud) {
  (void)err;
  voxgig_value* val = getp(in, "val");
  voxgig_value* store = getp(in, "store");

  voxgig_injection* inj = NULL;
  if (NULL != ud) {
    inj = voxgig_inj_new(NULL, NULL);
    inj->mode = 0;
    voxgig_release(inj->modify_val);
    inj->modify_val = voxgig_new_modify(modify_nullmark, NULL);
  }

  voxgig_value* r = voxgig_inject(val, store, inj);

  if (NULL != inj)
    voxgig_inj_free(inj);
  voxgig_release(val);
  voxgig_release(store);
  return r;
}

/* transform subjects. */
/* Canonical `transform` THROWS when an injector reports a problem and no
 * `errs` list was supplied to collect into. C has no exceptions, so this port
 * says it the only way it can: give transform an errs list, and raise here
 * what canonical would have raised there. `subj_validate` below does the same,
 * for the same reason. Without it `transform/apply#0` and
 * `transform/format#11` - which assert exactly those messages - saw the
 * unresolved spec come back as an ordinary value. */
static voxgig_value* subj_transform(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* data = getp(in, "data");
  voxgig_value* spec = getp(in, "spec");

  voxgig_injection* inj = voxgig_inj_new(NULL, NULL);
  inj->mode = 0;
  voxgig_release(inj->errs);
  inj->errs = voxgig_new_list();

  voxgig_value* r = voxgig_transform(data, spec, inj);
  if (0 < voxgig_list_len(voxgig_as_list(inj->errs)))
    *err = join_errs(inj->errs);

  voxgig_inj_free(inj);
  voxgig_release(data);
  voxgig_release(spec);
  return r;
}

/* Helper to collect errs from a validate/transform call. */
static char* join_errs(voxgig_value* errs) {
  if (!voxgig_is_list(errs))
    return NULL;
  voxgig_list* l = voxgig_as_list(errs);
  if (l->len == 0)
    return NULL;
  size_t cap = 256, len = 0;
  char* buf = malloc(cap);
  buf[0] = '\0';
  for (size_t i = 0; i < l->len; i++) {
    if (!voxgig_is_string(l->items[i]))
      continue;
    const char* s = voxgig_as_string(l->items[i]);
    size_t sl = strlen(s);
    if (len + sl + 8 > cap) {
      while (len + sl + 8 > cap)
        cap *= 2;
      buf = realloc(buf, cap);
    }
    if (i > 0) {
      strcat(buf, " | ");
      len += 3;
    }
    strcat(buf, s);
    len += sl;
  }
  return buf;
}

/* validate subjects. */
static voxgig_value* subj_validate(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* data = getp(in, "data");
  voxgig_value* spec = getp(in, "spec");
  /* Build a config bag with errs to collect. */
  voxgig_injection* sub = voxgig_inj_new(NULL, NULL);
  sub->mode = 0;
  voxgig_release(sub->errs);
  sub->errs = voxgig_new_list();
  voxgig_value* r = voxgig_validate(data, spec, sub);
  /* If errs collected, set err. */
  if (voxgig_list_len(voxgig_as_list(sub->errs)) > 0) {
    *err = join_errs(sub->errs);
  }
  voxgig_inj_free(sub);
  voxgig_release(data);
  voxgig_release(spec);
  return r;
}

/* select subjects. */
static voxgig_value* subj_select(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* obj = getp(in, "obj");
  voxgig_value* query = getp(in, "query");
  voxgig_value* r = voxgig_select(obj, query);
  voxgig_release(obj);
  voxgig_release(query);
  return r;
}

/* ---- regex subjects (parity floor: Go stdlib regexp; REGEX_API.md) ---- */

static const char* rx_str(voxgig_value* v) {
  return voxgig_is_string(v) ? voxgig_as_string(v) : "";
}

static voxgig_value* subj_re_test(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  voxgig_value* pv = getp(in, "pattern");
  voxgig_value* iv = getp(in, "input");
  voxgig_regex* re = voxgig_regex_compile(rx_str(pv), NULL);
  bool r = re != NULL && voxgig_regex_test(re, rx_str(iv), strlen(rx_str(iv)));
  if (re != NULL)
    voxgig_regex_free(re);
  voxgig_release(pv);
  voxgig_release(iv);
  return voxgig_new_bool(r);
}

static voxgig_value* rx_groups_value(const char* input, const int* caps, int ngroups) {
  voxgig_value* row = voxgig_new_list();
  for (int g = 0; g < ngroups; g++) {
    int cs = caps[2 * g];
    int ce = caps[2 * g + 1];
    if (cs < 0 || ce < cs) {
      voxgig_list_push(voxgig_as_list(row), voxgig_new_string(""));
    } else {
      char* part = (char*)malloc((size_t)(ce - cs) + 1);
      memcpy(part, input + cs, (size_t)(ce - cs));
      part[ce - cs] = 0;
      voxgig_list_push(voxgig_as_list(row), voxgig_new_string(part));
      free(part);
    }
  }
  return row;
}

static voxgig_value* subj_re_find(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  voxgig_value* pv = getp(in, "pattern");
  voxgig_value* iv = getp(in, "input");
  const char* input = rx_str(iv);
  voxgig_value* out = NULL;
  voxgig_regex* re = voxgig_regex_compile(rx_str(pv), NULL);
  if (re != NULL) {
    int caps[2 * VOXGIG_REGEX_MAX_GROUPS];
    int ngroups = voxgig_regex_ngroups(re);
    if (voxgig_regex_find(re, input, strlen(input), caps, ngroups)) {
      out = rx_groups_value(input, caps, ngroups);
    }
    voxgig_regex_free(re);
  }
  if (out == NULL)
    out = voxgig_new_null();
  voxgig_release(pv);
  voxgig_release(iv);
  return out;
}

static voxgig_value* subj_re_find_all(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  voxgig_value* pv = getp(in, "pattern");
  voxgig_value* iv = getp(in, "input");
  const char* input = rx_str(iv);
  voxgig_value* out = voxgig_new_list();
  voxgig_regex* re = voxgig_regex_compile(rx_str(pv), NULL);
  if (re != NULL) {
    enum { MAXM = 64 };
    static int caps[MAXM * 2 * VOXGIG_REGEX_MAX_GROUPS];
    int ngroups = voxgig_regex_ngroups(re);
    int nm = voxgig_regex_find_all(re, input, strlen(input), caps, MAXM);
    for (int m = 0; m < nm; m++) {
      voxgig_list_push(voxgig_as_list(out),
                       rx_groups_value(input, caps + m * 2 * VOXGIG_REGEX_MAX_GROUPS, ngroups));
    }
    voxgig_regex_free(re);
  }
  voxgig_release(pv);
  voxgig_release(iv);
  return out;
}

static voxgig_value* subj_re_replace(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  voxgig_value* pv = getp(in, "pattern");
  voxgig_value* iv = getp(in, "input");
  voxgig_value* rv = getp(in, "replacement");
  const char* input = rx_str(iv);
  voxgig_value* out = NULL;
  voxgig_regex* re = voxgig_regex_compile(rx_str(pv), NULL);
  if (re != NULL) {
    char* rs = voxgig_regex_replace(re, input, strlen(input), rx_str(rv));
    if (rs != NULL) {
      out = voxgig_new_string(rs);
      free(rs);
    }
    voxgig_regex_free(re);
  }
  if (out == NULL)
    out = voxgig_new_string(input);
  voxgig_release(pv);
  voxgig_release(iv);
  voxgig_release(rv);
  return out;
}

static voxgig_value* subj_re_escape(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  voxgig_value* v = getp(in, "val");
  char* s = voxgig_escre(v);
  voxgig_value* r = voxgig_new_string(s);
  free(s);
  voxgig_release(v);
  return r;
}

/* ---- new subjects: the six groups the in-situ runner never wired ---- */

/* transform.modify: prefix every string the transform produces with '@'. */
static void modify_prefix(voxgig_value* val, voxgig_value* key, voxgig_value* parent,
                          voxgig_injection* inj, voxgig_value* store, void* ud) {
  (void)inj;
  (void)store;
  (void)ud;
  if (!voxgig_is_string(val) || NULL == key || NULL == parent)
    return;
  if (!voxgig_is_node(parent))
    return;

  const char* text = voxgig_as_string(val);
  size_t len = strlen(text ? text : "");
  char* prefixed = (char*)malloc(len + 2);
  prefixed[0] = '@';
  memcpy(prefixed + 1, text ? text : "", len);
  prefixed[len + 1] = '\0';
  voxgig_setprop(parent, key, voxgig_new_string_take(prefixed, len + 1));
}

static voxgig_value* subj_transform_modify(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  voxgig_value* data = getp(in, "data");
  voxgig_value* spec = getp(in, "spec");

  voxgig_injection* inj = voxgig_inj_new(NULL, NULL);
  inj->mode = 0;
  voxgig_release(inj->modify_val);
  inj->modify_val = voxgig_new_modify(modify_prefix, NULL);

  voxgig_value* r = voxgig_transform(data, spec, inj);

  voxgig_inj_free(inj);
  voxgig_release(data);
  voxgig_release(spec);
  return r;
}

/* validate.special: the entry carries its own injection config in `inj`. */
static voxgig_value* subj_validate_special(voxgig_value* in, char** err, void* ud) {
  (void)ud;
  voxgig_value* data = getp(in, "data");
  voxgig_value* spec = getp(in, "spec");

  voxgig_injection* inj = voxgig_inj_new(NULL, NULL);
  inj->mode = 0;
  voxgig_release(inj->errs);
  inj->errs = voxgig_new_list();

  /* `$=` and the other special checks read their operand out of `inj.meta`,
   * which the entry supplies. Ignoring it made every one of them compare
   * against nothing. */
  voxgig_value* injv = getp(in, "inj");
  voxgig_value* meta = getp(injv, "meta");
  if (voxgig_is_map(meta)) {
    voxgig_release(inj->meta);
    inj->meta = voxgig_retain(meta);
  }
  voxgig_release(meta);
  voxgig_release(injv);

  voxgig_value* r = voxgig_validate(data, spec, inj);
  if (0 < voxgig_list_len(voxgig_as_list(inj->errs)))
    *err = join_errs(inj->errs);

  voxgig_inj_free(inj);
  voxgig_release(data);
  voxgig_release(spec);
  return r;
}

/* walk.copy: rebuild the tree through `setprop`, one level per path step.
 * `cur[i]` is the node being built at depth i; canonical keeps the same
 * one-element-per-depth array. */
typedef struct walk_copy_state {
  voxgig_value* cur; /* list of nodes by depth */
} walk_copy_state;

static voxgig_value* walk_copy_cb(voxgig_value* key, voxgig_value* val, voxgig_value* parent,
                                  voxgig_value* path, void* ud) {
  (void)parent;
  walk_copy_state* st = (walk_copy_state*)ud;

  /* A walk callback returns a RETAINED reference - `voxgig_walk` hands its
   * result straight back to the caller, who releases it. */
  if (NULL == key || voxgig_is_undef(key)) {
    voxgig_release(st->cur);
    st->cur = voxgig_new_list();
    voxgig_list_push(voxgig_as_list(st->cur), voxgig_ismap(val)    ? voxgig_new_map()
                                              : voxgig_islist(val) ? voxgig_new_list()
                                                                   : voxgig_retain(val));
    return val ? voxgig_retain(val) : voxgig_new_undef();
  }

  size_t depth = (size_t)voxgig_size(path);
  voxgig_list* cur = voxgig_as_list(st->cur);

  voxgig_value* child = voxgig_retain(val);
  if (voxgig_isnode(val)) {
    child = voxgig_ismap(val) ? voxgig_new_map() : voxgig_new_list();
    while (voxgig_list_len(cur) <= depth)
      voxgig_list_push(cur, voxgig_new_undef());
    voxgig_list_set(cur, depth, voxgig_retain(child));
  }

  if (0 < depth)
    voxgig_setprop(voxgig_list_get(cur, depth - 1), key, voxgig_retain(child));

  voxgig_release(child);
  return val ? voxgig_retain(val) : voxgig_new_undef();
}

static voxgig_value* subj_walk_copy(voxgig_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  walk_copy_state st = {NULL};
  voxgig_value* walked = voxgig_walk(in, walk_copy_cb, NULL, VOXGIG_MAXDEPTH, &st);
  voxgig_release(walked);

  voxgig_value* out = NULL;
  if (NULL != st.cur && 0 < voxgig_list_len(voxgig_as_list(st.cur)))
    out = voxgig_retain(voxgig_list_get(voxgig_as_list(st.cur), 0));
  else
    out = voxgig_new_undef();

  voxgig_release(st.cur);
  return out;
}

int main(void) {
  char* err = NULL;

  POOL = omni_pool_new();

  omni_runner* runner = omni_make_runner(POOL, "../build/test/test.json", NULL, NULL, &err);
  if (NULL == runner) {
    fprintf(stderr, "struct: %s\n", err ? err : "cannot load the corpus");
    return 1;
  }

  PACK = omni_runner_run(runner, "struct", NULL, &err);
  if (NULL == PACK) {
    fprintf(stderr, "struct: %s\n", err ? err : "cannot resolve the struct spec");
    return 1;
  }
  SPEC = omni_spec(PACK);

  printf("\n===== struct corpus =====\n");

  /* minor */
  run("minor", "isnode", true, subj_isnode, NULL);
  run("minor", "ismap", true, subj_ismap, NULL);
  run("minor", "islist", true, subj_islist, NULL);
  run("minor", "iskey", false, subj_iskey, NULL);
  run("minor", "strkey", false, subj_strkey, NULL);
  run("minor", "isempty", false, subj_isempty, NULL);
  run("minor", "isfunc", true, subj_isfunc, NULL);
  run("minor", "typify", false, subj_typify, NULL);
  run("minor", "typename", true, subj_typename, NULL);
  run("minor", "clone", false, subj_clone, NULL);
  run("minor", "size", false, subj_size, NULL);
  run("minor", "keysof", true, subj_keysof, NULL);
  run("minor", "items", true, subj_items, NULL);
  run("minor", "haskey", false, subj_haskey, NULL);
  run("minor", "getprop", false, subj_getprop, NULL);
  run("minor", "getelem", false, subj_getelem, NULL);
  run("minor", "setprop", true, subj_setprop, NULL);
  run("minor", "delprop", true, subj_delprop, NULL);
  run("minor", "stringify", true, subj_stringify, NULL);
  run("minor", "jsonify", false, subj_jsonify, NULL);
  run("minor", "pathify", true, subj_pathify, NULL);
  run("minor", "escre", true, subj_escre, NULL);
  run("minor", "escurl", true, subj_escurl, NULL);
  run("minor", "join", false, subj_join, NULL);
  run("minor", "flatten", true, subj_flatten, NULL);
  run("minor", "filter", true, subj_filter, NULL);
  run("minor", "slice", false, subj_slice, NULL);
  run("minor", "pad", false, subj_pad, NULL);
  run("minor", "setpath", false, subj_setpath, NULL);

  /* walk */
  run("walk", "basic", true, subj_walk_basic, NULL);
  run("walk", "depth", false, subj_walk_depth, NULL);
  run("walk", "copy", true, subj_walk_copy, NULL);

  /* merge */
  {
    omni_json* entry = group_spec("merge", "basic");
    voxgig_value* in = bridge_tostruct(omni_map_get(entry, "in"));
    single("merge.basic", entry, voxgig_merge(in, VOXGIG_MAXDEPTH));
    voxgig_release(in);
  }
  run("merge", "cases", true, subj_merge, NULL);
  run("merge", "array", true, subj_merge, NULL);
  run("merge", "integrity", true, subj_merge, NULL);
  run("merge", "depth", true, subj_merge_depth, NULL);

  /* getpath */
  run("getpath", "basic", true, subj_getpath_basic, NULL);
  run("getpath", "relative", true, subj_getpath_relative, NULL);
  run("getpath", "special", true, subj_getpath_special, NULL);
  run("getpath", "handler", true, subj_getpath_handler, NULL);

  /* regex (parity floor: Go stdlib regexp - see design/REGEX_API.md) */
  run("regex", "test", true, subj_re_test, NULL);
  run("regex", "find", true, subj_re_find, NULL);
  run("regex", "find_all", true, subj_re_find_all, NULL);
  run("regex", "replace", true, subj_re_replace, NULL);
  run("regex", "escape", true, subj_re_escape, NULL);

  /* sentinels - null and absent unified on observation */
  run("sentinels", "getprop_unify", false, subj_sent_getprop, NULL);
  run("sentinels", "getelem_absent", false, subj_sent_getelem, NULL);
  run("sentinels", "haskey_unify", false, subj_sent_haskey, NULL);
  run("sentinels", "isempty_unify", false, subj_sent_isempty, NULL);
  run("sentinels", "isnode_unify", false, subj_sent_isnode, NULL);
  run("sentinels", "stringify_null", false, subj_sent_stringify, NULL);

  /* inject */
  {
    omni_json* entry = group_spec("inject", "basic");
    voxgig_value* in = bridge_tostruct(omni_map_get(entry, "in"));
    voxgig_value* val = getp(in, "val");
    voxgig_value* store = getp(in, "store");
    single("inject.basic", entry, voxgig_inject(val, store, NULL));
    voxgig_release(val);
    voxgig_release(store);
    voxgig_release(in);
  }
  run("inject", "string", true, subj_inject, (void*)&USE_NULLMODIFIER);
  run("inject", "deep", true, subj_inject, NULL);

  /* transform */
  {
    omni_json* entry = group_spec("transform", "basic");
    voxgig_value* in = bridge_tostruct(omni_map_get(entry, "in"));
    voxgig_value* data = getp(in, "data");
    voxgig_value* spec = getp(in, "spec");
    single("transform.basic", entry, voxgig_transform(data, spec, NULL));
    voxgig_release(data);
    voxgig_release(spec);
    voxgig_release(in);
  }
  run("transform", "paths", true, subj_transform, NULL);
  run("transform", "cmds", true, subj_transform, NULL);
  run("transform", "each", true, subj_transform, NULL);
  run("transform", "pack", true, subj_transform, NULL);
  run("transform", "ref", true, subj_transform, NULL);
  run("transform", "apply", true, subj_transform, NULL);
  run("transform", "format", false, subj_transform, NULL);
  run("transform", "modify", true, subj_transform_modify, NULL);

  /* validate */
  run("validate", "basic", false, subj_validate, NULL);
  run("validate", "invalid", false, subj_validate, NULL);
  run("validate", "child", true, subj_validate, NULL);
  run("validate", "one", true, subj_validate, NULL);
  run("validate", "exact", true, subj_validate, NULL);
  run("validate", "special", true, subj_validate_special, NULL);

  /* select */
  run("select", "basic", true, subj_select, NULL);
  run("select", "operators", true, subj_select, NULL);
  run("select", "edge", true, subj_select, NULL);
  run("select", "alts", true, subj_select, NULL);
  run("select", "nullkey", false, subj_select, NULL);

  /* condense / expand / iscondensed exist only in canonical TypeScript so far
   * - no port implements them, and check_parity.py already lists them as
   * pending. Named here so the gap is a visible TODO rather than three groups
   * nobody notices are missing. */
  printf("  skip condense.condense, condense.expand, condense.iscondensed (not ported)\n");

  printf("=========================\n%d groups, %d failed\n\n", GROUPS, FAILED);

  omni_pool_free(POOL);
  return 0 == FAILED ? 0 : 1;
}
