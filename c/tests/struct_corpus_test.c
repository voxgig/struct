/* Voxgig Struct corpus driver — C port. Mirrors cpp/tests/struct_corpus_test.cpp. */

#include "runner.h"
#include "voxgig_struct.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static vs_value* CORPUS = NULL;

static vs_value* get_spec(const char* category, const char* name) {
  if (!CORPUS) {
    CORPUS = vs_parse_json_file("../build/test/test.json");
  }
  vs_value* sk = vs_new_string("struct");
  vs_value* sv = vs_getprop(CORPUS, sk, NULL);
  vs_release(sk);
  vs_value* ck = vs_new_string(category);
  vs_value* cat = vs_getprop(sv, ck, NULL);
  vs_release(ck);
  vs_release(sv);
  vs_value* nk = vs_new_string(name);
  vs_value* spec = vs_getprop(cat, nk, NULL);
  vs_release(nk);
  vs_release(cat);
  return spec;
}

/* Scoreboard. */
typedef struct slot {
  char* key;
  runner_result r;
} slot;

static slot* SB = NULL;
static size_t SB_LEN = 0;
static size_t SB_CAP = 0;

static void sb_add(const char* key, runner_result r) {
  if (SB_LEN + 1 > SB_CAP) {
    size_t nc = SB_CAP == 0 ? 64 : SB_CAP * 2;
    SB = (slot*)realloc(SB, nc * sizeof(slot));
    SB_CAP = nc;
  }
  SB[SB_LEN].key = strdup(key);
  SB[SB_LEN].r = r;
  SB_LEN++;
}

static void run(const char* cat, const char* name, bool null_flag, runner_subject_fn s, void* ud) {
  char full[256];
  snprintf(full, sizeof(full), "%s.%s", cat, name);
  vs_value* spec = get_spec(cat, name);
  runner_result r;
  runner_result_init(&r, full);
  run_subject(&r, spec, null_flag, s, ud);
  vs_release(spec);
  sb_add(full, r);
}

/* Helpers. */
/* Raw map lookup for runner field extraction. Unlike vs_getprop (Group A,
 * which treats null at a key as "no value"), this returns the literal stored
 * value — including null — so tests for Group B functions like stringify and
 * pad receive their corpus input verbatim. */
static vs_value* getp(vs_value* in, const char* key) {
  if (!vs_is_map(in))
    return vs_new_undef();
  vs_value* v = vs_map_get(vs_as_map(in), key);
  return v ? vs_retain(v) : vs_new_undef();
}

/* Subject implementations. */
static vs_value* subj_isnode(vs_value* in, char** err, void* ud) {
  (void)ud;
  return vs_new_bool(vs_isnode(in));
}
static vs_value* subj_ismap(vs_value* in, char** err, void* ud) {
  (void)ud;
  return vs_new_bool(vs_ismap(in));
}
static vs_value* subj_islist(vs_value* in, char** err, void* ud) {
  (void)ud;
  return vs_new_bool(vs_islist(in));
}
static vs_value* subj_iskey(vs_value* in, char** err, void* ud) {
  (void)ud;
  return vs_new_bool(vs_iskey(in));
}
static vs_value* subj_isempty(vs_value* in, char** err, void* ud) {
  (void)ud;
  return vs_new_bool(vs_isempty(in));
}
static vs_value* subj_isfunc(vs_value* in, char** err, void* ud) {
  (void)ud;
  return vs_new_bool(vs_isfunc(in));
}
static vs_value* subj_typify(vs_value* in, char** err, void* ud) {
  (void)ud;
  return vs_new_int(vs_typify(in));
}
static vs_value* subj_typename(vs_value* in, char** err, void* ud) {
  (void)ud;
  if (vs_is_int(in))
    return vs_new_string(vs_typename((int)vs_as_int(in)));
  return vs_new_string(vs_typename(vs_typify(in)));
}
static vs_value* subj_clone(vs_value* in, char** err, void* ud) {
  (void)ud;
  return vs_clone(in);
}
static vs_value* subj_size(vs_value* in, char** err, void* ud) {
  (void)ud;
  return vs_new_int(vs_size(in));
}
static vs_value* subj_strkey(vs_value* in, char** err, void* ud) {
  (void)ud;
  char* s = vs_strkey(in);
  vs_value* v = vs_new_string(s);
  free(s);
  return v;
}
static vs_value* subj_keysof(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_strvec ks = vs_keysof(in);
  vs_value* out = vs_new_list();
  for (size_t i = 0; i < ks.len; i++)
    vs_list_push(vs_as_list(out), vs_new_string(ks.data[i]));
  vs_strvec_free(&ks);
  return out;
}
static vs_value* subj_items(vs_value* in, char** err, void* ud) {
  (void)ud;
  return vs_items_v(in);
}
static vs_value* subj_haskey(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* src = getp(in, "src");
  vs_value* key = getp(in, "key");
  bool r = vs_haskey(src, key);
  vs_release(src);
  vs_release(key);
  return vs_new_bool(r);
}
static vs_value* subj_getprop(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* val = getp(in, "val");
  vs_value* key = getp(in, "key");
  vs_value* altk = vs_new_string("alt");
  vs_value* alt = vs_haskey(in, altk) ? vs_getprop(in, altk, NULL) : NULL;
  vs_release(altk);
  vs_value* r = vs_getprop(val, key, alt);
  vs_release(val);
  vs_release(key);
  vs_release(alt);
  return r;
}
static vs_value* subj_getelem(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* val = getp(in, "val");
  vs_value* key = getp(in, "key");
  vs_value* altk = vs_new_string("alt");
  vs_value* alt = vs_haskey(in, altk) ? vs_getprop(in, altk, NULL) : NULL;
  vs_release(altk);
  vs_value* r = vs_getelem(val, key, alt);
  vs_release(val);
  vs_release(key);
  vs_release(alt);
  return r;
}
static vs_value* subj_setprop(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* parent = getp(in, "parent");
  if (!parent || vs_is_undef(parent)) {
    vs_release(parent);
    parent = vs_new_null();
  }
  vs_value* key = getp(in, "key");
  vs_value* val = getp(in, "val");
  vs_value* r = vs_setprop(parent, key, val);
  vs_value* ret = r ? vs_retain(r) : vs_new_undef();
  vs_release(parent);
  vs_release(key);
  vs_release(val);
  return ret;
}
static vs_value* subj_delprop(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* parent = getp(in, "parent");
  if (!parent || vs_is_undef(parent)) {
    vs_release(parent);
    parent = vs_new_null();
  }
  vs_value* key = getp(in, "key");
  vs_value* r = vs_delprop(parent, key);
  vs_value* ret = r ? vs_retain(r) : vs_new_undef();
  vs_release(parent);
  vs_release(key);
  return ret;
}
static vs_value* subj_stringify(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* val = getp(in, "val");
  vs_value* max = getp(in, "max");
  int m = -1;
  if (vs_is_int(max))
    m = (int)vs_as_int(max);
  char* s = vs_stringify(val, m);
  vs_value* r = vs_new_string(s);
  free(s);
  vs_release(val);
  vs_release(max);
  return r;
}
static vs_value* subj_jsonify(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* val = getp(in, "val");
  vs_value* flags = getp(in, "flags");
  char* s = vs_jsonify(val, flags);
  vs_value* r = vs_new_string(s);
  free(s);
  vs_release(val);
  vs_release(flags);
  return r;
}
static vs_value* subj_pathify(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* path = getp(in, "path");
  vs_value* from = getp(in, "from");
  vs_value* to = getp(in, "to");
  int f = vs_is_int(from) ? (int)vs_as_int(from) : 0;
  int t = vs_is_int(to) ? (int)vs_as_int(to) : 0;
  char* s = vs_pathify(path, f, t);
  vs_value* r = vs_new_string(s);
  free(s);
  vs_release(path);
  vs_release(from);
  vs_release(to);
  return r;
}
static vs_value* subj_escre(vs_value* in, char** err, void* ud) {
  (void)ud;
  char* s = vs_escre(in);
  vs_value* r = vs_new_string(s);
  free(s);
  return r;
}
static vs_value* subj_escurl(vs_value* in, char** err, void* ud) {
  (void)ud;
  char* s = vs_escurl(in);
  vs_value* r = vs_new_string(s);
  free(s);
  return r;
}
static vs_value* subj_join(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* val = getp(in, "val");
  vs_value* sep = getp(in, "sep");
  vs_value* url = getp(in, "url");
  char* s = vs_join_v(val, sep, url);
  vs_value* r = vs_new_string(s);
  free(s);
  vs_release(val);
  vs_release(sep);
  vs_release(url);
  return r;
}
static vs_value* subj_flatten(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* val = getp(in, "val");
  vs_value* depth = getp(in, "depth");
  vs_value* r = vs_flatten(val, depth);
  vs_release(val);
  vs_release(depth);
  return r;
}

static bool gt3(vs_value* pair, void* ud) {
  (void)ud;
  vs_value* one = vs_new_int(1);
  vs_value* v = vs_getprop(pair, one, NULL);
  vs_release(one);
  bool ok = vs_is_number(v) && vs_as_double(v) > 3;
  vs_release(v);
  return ok;
}
static bool lt3(vs_value* pair, void* ud) {
  (void)ud;
  vs_value* one = vs_new_int(1);
  vs_value* v = vs_getprop(pair, one, NULL);
  vs_release(one);
  bool ok = vs_is_number(v) && vs_as_double(v) < 3;
  vs_release(v);
  return ok;
}
static vs_value* subj_filter(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* val = getp(in, "val");
  vs_value* checkk = vs_new_string("check");
  vs_value* check = vs_getprop(in, checkk, NULL);
  vs_release(checkk);
  vs_itemcheck_fn pred = lt3;
  if (vs_is_string(check) && strcmp(vs_as_string(check), "gt3") == 0)
    pred = gt3;
  vs_value* r = vs_filter(val, pred, NULL);
  vs_release(val);
  vs_release(check);
  return r;
}
static vs_value* subj_slice(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* val = getp(in, "val");
  vs_value* start = getp(in, "start");
  vs_value* end = getp(in, "end");
  vs_value* r = vs_slice(val, start, end, false);
  vs_release(val);
  vs_release(start);
  vs_release(end);
  return r;
}
static vs_value* subj_pad(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* val = getp(in, "val");
  vs_value* pd = getp(in, "pad");
  vs_value* ch = getp(in, "char");
  char* s = vs_pad(val, pd, ch);
  vs_value* r = vs_new_string(s);
  free(s);
  vs_release(val);
  vs_release(pd);
  vs_release(ch);
  return r;
}
static vs_value* subj_setpath(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* store = getp(in, "store");
  vs_value* path = getp(in, "path");
  vs_value* val = getp(in, "val");
  vs_value* r = vs_setpath(store, path, val, NULL);
  vs_value* ret = r ? vs_retain(r) : vs_new_undef();
  vs_release(store);
  vs_release(path);
  vs_release(val);
  return ret;
}

/* walk depth subject: builds a parallel deep tree, controlled by maxdepth. */
typedef struct walk_depth_state {
  vs_value* top;
  vs_value* cur;
} walk_depth_state;

static vs_value* walk_depth_cb(vs_value* key, vs_value* val, vs_value* parent, vs_value* path,
                               void* ud) {
  (void)parent;
  (void)path;
  walk_depth_state* st = (walk_depth_state*)ud;
  if (!key || vs_is_undef(key) || vs_isnode(val)) {
    vs_value* child = vs_is_list(val) ? vs_new_list() : vs_new_map();
    if (!key || vs_is_undef(key)) {
      vs_release(st->top);
      st->top = child;
      st->cur = child;
    } else {
      vs_setprop(st->cur, key, child);
      st->cur = child;
    }
  } else {
    vs_setprop(st->cur, key, val);
  }
  return vs_retain(val);
}
static vs_value* subj_walk_depth(vs_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  vs_value* src = getp(in, "src");
  vs_value* mdv = getp(in, "maxdepth");
  int md = vs_is_int(mdv) ? (int)vs_as_int(mdv) : VS_MAXDEPTH;
  walk_depth_state st = {NULL, NULL};
  vs_value* w = vs_walk(src, walk_depth_cb, NULL, md, &st);
  vs_release(w);
  vs_release(src);
  vs_release(mdv);
  vs_value* out = st.top ? st.top : vs_new_map();
  return out;
}

/* getpath relative. */
static vs_value* subj_getpath_relative(vs_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  vs_value* store = getp(in, "store");
  vs_value* path = getp(in, "path");
  vs_injection* inj = vs_inj_new(NULL, NULL);
  inj->mode = 0;
  /* Apply dparent / dpath / base from input if present. */
  vs_value* dparent = getp(in, "dparent");
  if (dparent && !vs_is_undef(dparent)) {
    vs_release(inj->dparent);
    inj->dparent = dparent;
  } else {
    vs_release(dparent);
  }
  vs_value* dpath = getp(in, "dpath");
  if (vs_is_list(dpath)) {
    vs_strvec_clear(&inj->dpath);
    vs_list* l = vs_as_list(dpath);
    for (size_t i = 0; i < l->len; i++) {
      char* s = vs_strkey(l->items[i]);
      vs_strvec_push(&inj->dpath, s);
      free(s);
    }
  } else if (vs_is_string(dpath)) {
    vs_strvec_clear(&inj->dpath);
    const char* s = vs_as_string(dpath);
    size_t n = vs_string_len(dpath);
    size_t i = 0;
    while (i <= n) {
      size_t j = i;
      while (j < n && s[j] != '.')
        j++;
      vs_strvec_push_n(&inj->dpath, s + i, j - i);
      i = j + 1;
      if (j == n)
        break;
    }
  }
  vs_release(dpath);
  vs_value* base = getp(in, "base");
  if (vs_is_string(base)) {
    free(inj->base);
    inj->base = strdup(vs_as_string(base));
  }
  vs_release(base);
  vs_value* r = vs_getpath(store, path, inj);
  vs_inj_free(inj);
  vs_release(store);
  vs_release(path);
  return r;
}

/* Inject basic. */
static vs_value* subj_inject_basic(vs_value* in, char** err, void* ud) {
  (void)err;
  (void)ud;
  return vs_inject(in, in, NULL);
}

/* Walk subjects. */
static vs_value* walk_basic_cb(vs_value* key, vs_value* val, vs_value* parent, vs_value* path,
                               void* ud) {
  (void)key;
  (void)parent;
  (void)ud;
  if (vs_is_string(val)) {
    char* buf = NULL;
    size_t len = 0, cap = 0;
    const char* s = vs_as_string(val);
    size_t sl = vs_string_len(val);
    /* val + "~" + path.join(".") */
    cap = sl + 16;
    buf = (char*)malloc(cap);
    memcpy(buf, s, sl);
    len = sl;
    buf[len++] = '~';
    vs_list* pl = vs_as_list(path);
    for (size_t i = 0; i < pl->len; i++) {
      if (i > 0) {
        if (len + 1 >= cap) {
          cap *= 2;
          buf = (char*)realloc(buf, cap);
        }
        buf[len++] = '.';
      }
      const char* ps = vs_as_string(pl->items[i]);
      size_t psl = vs_string_len(pl->items[i]);
      if (len + psl + 1 >= cap) {
        while (cap < len + psl + 1)
          cap *= 2;
        buf = (char*)realloc(buf, cap);
      }
      memcpy(buf + len, ps, psl);
      len += psl;
    }
    buf[len] = '\0';
    vs_value* r = vs_new_string(buf);
    free(buf);
    return r;
  }
  return vs_retain(val);
}
static vs_value* subj_walk_basic(vs_value* in, char** err, void* ud) {
  (void)ud;
  return vs_walk(in, walk_basic_cb, NULL, VS_MAXDEPTH, NULL);
}

/* Merge subjects. */
static vs_value* subj_merge(vs_value* in, char** err, void* ud) {
  (void)ud;
  return vs_merge(in, VS_MAXDEPTH);
}
static vs_value* subj_merge_depth(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* val = getp(in, "val");
  vs_value* depth = getp(in, "depth");
  int d = vs_is_int(depth) ? (int)vs_as_int(depth) : VS_MAXDEPTH;
  vs_value* r = vs_merge(val, d);
  vs_release(val);
  vs_release(depth);
  return r;
}

/* getpath subjects. */
static vs_value* subj_getpath_basic(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* store = getp(in, "store");
  vs_value* path = getp(in, "path");
  vs_value* r = vs_getpath(store, path, NULL);
  vs_release(store);
  vs_release(path);
  return r;
}

/* inject subjects. */
static vs_value* subj_inject(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* val = getp(in, "val");
  vs_value* store = getp(in, "store");
  vs_value* r = vs_inject(val, store, NULL);
  vs_release(val);
  vs_release(store);
  return r;
}

/* transform subjects. */
static vs_value* subj_transform(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* data = getp(in, "data");
  vs_value* spec = getp(in, "spec");
  vs_value* r = vs_transform(data, spec, NULL);
  vs_release(data);
  vs_release(spec);
  return r;
}

/* Helper to collect errs from a validate/transform call. */
static char* join_errs(vs_value* errs) {
  if (!vs_is_list(errs))
    return NULL;
  vs_list* l = vs_as_list(errs);
  if (l->len == 0)
    return NULL;
  size_t cap = 256, len = 0;
  char* buf = malloc(cap);
  buf[0] = '\0';
  for (size_t i = 0; i < l->len; i++) {
    if (!vs_is_string(l->items[i]))
      continue;
    const char* s = vs_as_string(l->items[i]);
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
static vs_value* subj_validate(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* data = getp(in, "data");
  vs_value* spec = getp(in, "spec");
  /* Build a config bag with errs to collect. */
  vs_injection* sub = vs_inj_new(NULL, NULL);
  sub->mode = 0;
  vs_release(sub->errs);
  sub->errs = vs_new_list();
  vs_value* r = vs_validate(data, spec, sub);
  /* If errs collected, set err. */
  if (vs_list_len(vs_as_list(sub->errs)) > 0) {
    *err = join_errs(sub->errs);
  }
  vs_inj_free(sub);
  vs_release(data);
  vs_release(spec);
  return r;
}

/* select subjects. */
static vs_value* subj_select(vs_value* in, char** err, void* ud) {
  (void)ud;
  vs_value* obj = getp(in, "obj");
  vs_value* query = getp(in, "query");
  vs_value* r = vs_select(obj, query);
  vs_release(obj);
  vs_release(query);
  return r;
}

/* Category to file map (for scoreboard grouping). */
static const char* category_to_file(const char* cat) {
  if (strcmp(cat, "minor") == 0)
    return "minor.jsonic";
  if (strcmp(cat, "walk") == 0)
    return "walk.jsonic";
  if (strcmp(cat, "merge") == 0)
    return "merge.jsonic";
  if (strcmp(cat, "getpath") == 0)
    return "getpath.jsonic";
  if (strcmp(cat, "inject") == 0)
    return "inject.jsonic";
  if (strcmp(cat, "transform") == 0)
    return "transform.jsonic";
  if (strcmp(cat, "validate") == 0)
    return "validate.jsonic";
  if (strcmp(cat, "select") == 0)
    return "select.jsonic";
  return cat;
}

int main(void) {
  /* minor */
  run("minor", "isnode", true, subj_isnode, NULL);
  run("minor", "ismap", true, subj_ismap, NULL);
  run("minor", "islist", true, subj_islist, NULL);
  run("minor", "iskey", false, subj_iskey, NULL);
  run("minor", "strkey", false, subj_strkey, NULL);
  run("minor", "isempty", false, subj_isempty, NULL);
  run("minor", "isfunc", true, subj_isfunc, NULL);
  run("minor", "typify", true, subj_typify, NULL);
  run("minor", "typename", true, subj_typename, NULL);
  run("minor", "clone", false, subj_clone, NULL);
  run("minor", "size", true, subj_size, NULL);
  run("minor", "keysof", true, subj_keysof, NULL);
  run("minor", "items", true, subj_items, NULL);
  run("minor", "haskey", true, subj_haskey, NULL);
  run("minor", "getprop", true, subj_getprop, NULL);
  run("minor", "getelem", true, subj_getelem, NULL);
  run("minor", "setprop", true, subj_setprop, NULL);
  run("minor", "delprop", true, subj_delprop, NULL);
  run("minor", "stringify", true, subj_stringify, NULL);
  run("minor", "jsonify", true, subj_jsonify, NULL);
  run("minor", "pathify", true, subj_pathify, NULL);
  run("minor", "escre", true, subj_escre, NULL);
  run("minor", "escurl", true, subj_escurl, NULL);
  run("minor", "join", true, subj_join, NULL);
  run("minor", "flatten", true, subj_flatten, NULL);
  run("minor", "filter", true, subj_filter, NULL);
  run("minor", "slice", true, subj_slice, NULL);
  run("minor", "pad", true, subj_pad, NULL);
  run("minor", "setpath", false, subj_setpath, NULL);

  /* walk */
  run("walk", "basic", true, subj_walk_basic, NULL);
  run("walk", "depth", false, subj_walk_depth, NULL);

  /* merge */
  run("merge", "basic", true, subj_merge, NULL);
  run("merge", "cases", true, subj_merge, NULL);
  run("merge", "array", true, subj_merge, NULL);
  run("merge", "integrity", true, subj_merge, NULL);
  run("merge", "depth", true, subj_merge_depth, NULL);

  /* getpath */
  run("getpath", "basic", true, subj_getpath_basic, NULL);
  run("getpath", "relative", true, subj_getpath_relative, NULL);

  /* inject */
  run("inject", "basic", true, subj_inject_basic, NULL);
  run("inject", "string", true, subj_inject, NULL);
  run("inject", "deep", true, subj_inject, NULL);

  /* transform */
  run("transform", "paths", true, subj_transform, NULL);
  run("transform", "cmds", true, subj_transform, NULL);
  run("transform", "each", true, subj_transform, NULL);
  run("transform", "pack", true, subj_transform, NULL);
  run("transform", "ref", true, subj_transform, NULL);

  /* validate */
  run("validate", "basic", true, subj_validate, NULL);
  run("validate", "invalid", true, subj_validate, NULL);
  run("validate", "child", true, subj_validate, NULL);
  run("validate", "one", true, subj_validate, NULL);
  run("validate", "exact", true, subj_validate, NULL);

  /* select */
  run("select", "basic", true, subj_select, NULL);
  run("select", "operators", true, subj_select, NULL);
  run("select", "edge", true, subj_select, NULL);
  run("select", "alts", true, subj_select, NULL);

  /* Aggregate scoreboard. */
  int totalP = 0, totalT = 0;
  /* Group by file. */
  printf("\n========= STRUCT CORPUS SCOREBOARD =========\n");
  /* Per-test print, sorted-ish (insertion order is fine). */
  for (size_t i = 0; i < SB_LEN; i++) {
    printf("  %-30s %d / %d\n", SB[i].r.name, SB[i].r.passed, SB[i].r.total);
    totalP += SB[i].r.passed;
    totalT += SB[i].r.total;
  }
  printf("  %-30s %d / %d\n", "TOTAL", totalP, totalT);
  printf("============================================\n");

  /* If CORPUS_VERBOSE, dump failures. */
  const char* vrb = getenv("CORPUS_VERBOSE");
  if (vrb && strcmp(vrb, "0") != 0) {
    for (size_t i = 0; i < SB_LEN; i++) {
      if (SB[i].r.fail_len == 0)
        continue;
      fprintf(stderr, "\n--- %s (%d/%d) ---\n", SB[i].r.name, SB[i].r.passed, SB[i].r.total);
      int shown = 0;
      for (size_t j = 0; j < SB[i].r.fail_len; j++) {
        fprintf(stderr, "  %s\n", SB[i].r.failures[j]);
        if (++shown >= 5) {
          fprintf(stderr, "  ... %zu more\n", SB[i].r.fail_len - shown);
          break;
        }
      }
    }
  }

  /* Write target/corpus-scoreboard.json */
  FILE* f = fopen("corpus-scoreboard.json", "w");
  if (f) {
    fprintf(f, "{\n  \"files\": {\n");
    /* Group. */
    /* For simplicity, just dump per-test. */
    bool first = true;
    for (size_t i = 0; i < SB_LEN; i++) {
      const char* dot = strchr(SB[i].r.name, '.');
      const char* cat = SB[i].r.name;
      char catbuf[64];
      if (dot) {
        size_t cl = dot - cat;
        if (cl >= sizeof(catbuf))
          cl = sizeof(catbuf) - 1;
        memcpy(catbuf, cat, cl);
        catbuf[cl] = '\0';
        cat = catbuf;
      }
      if (!first)
        fprintf(f, ",\n");
      first = false;
      fprintf(f, "    \"%s\": {\"passed\": %d, \"total\": %d}", category_to_file(cat),
              SB[i].r.passed, SB[i].r.total);
    }
    fprintf(f, "\n  },\n  \"total\": {\"passed\": %d, \"total\": %d}\n}\n", totalP, totalT);
    fclose(f);
  }

  for (size_t i = 0; i < SB_LEN; i++) {
    runner_result_free(&SB[i].r);
    free(SB[i].key);
  }
  free(SB);
  vs_release(CORPUS);
  return 0;
}
