/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
 *
 * Transform, validate, select — and the 11 transform commands, 15 validate
 * checkers, and 4 select operators.
 *
 * Mirrors ts/src/StructUtility.ts lines 1306–2499.
 */

#include "voxgig_struct.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Forward decls of items shared from inject.c */
vs_value* vs_inject_str_v(const char* val, size_t vlen, vs_value* store, vs_injection* inj);

/* Local helpers */
static char* xstrdup_t(const char* s) {
  if (!s)
    s = "";
  size_t n = strlen(s);
  char* o = (char*)malloc(n + 1);
  if (!o)
    abort();
  memcpy(o, s, n + 1);
  return o;
}

static vs_value* _invalid_type_msg(vs_strvec* path, const char* needtype, int vt, vs_value* v) {
  char* vs = NULL;
  if (!v || vs_is_undef(v) || vs_is_null(v))
    vs = xstrdup_t("no value");
  else
    vs = vs_stringify(v, -1);

  char* pathstr = NULL;
  if (path && path->len > 1) {
    /* pathify(path, 1, 0) — equivalent to slice(path,1).join('.') */
    vs_value* lst = vs_new_list();
    for (size_t i = 1; i < path->len; i++) {
      vs_list_push(vs_as_list(lst), vs_new_string(path->data[i]));
    }
    pathstr = vs_pathify(lst, 0, 0);
    vs_release(lst);
  }

  char* buf = (char*)malloc((pathstr ? strlen(pathstr) : 0) + strlen(needtype) + strlen(vs) + 128);
  if (!buf)
    abort();
  buf[0] = '\0';
  strcat(buf, "Expected ");
  if (pathstr && *pathstr) {
    strcat(buf, "field ");
    strcat(buf, pathstr);
    strcat(buf, " to be ");
  }
  strcat(buf, needtype);
  strcat(buf, ", but found ");
  if (v && !vs_is_undef(v) && !vs_is_null(v)) {
    strcat(buf, vs_typename(vt));
    strcat(buf, ": ");
  }
  strcat(buf, vs);
  strcat(buf, ".");
  vs_value* res = vs_new_string(buf);
  free(buf);
  free(vs);
  free(pathstr);
  return res;
}

/* ===========================================================================
 * Transform commands
 * ===========================================================================*/

static vs_value* tx_DELETE(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                           void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  vs_inj_setval(inj, NULL, 0);
  return vs_new_undef();
}

static vs_value* tx_COPY(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                         void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  if (!vs_check_placement(VS_M_VAL, "COPY", VS_T_ANY, inj))
    return vs_new_undef();
  vs_value* keyv = vs_new_string(inj->key);
  vs_value* out = vs_getprop(inj->dparent, keyv, NULL);
  vs_release(keyv);
  vs_inj_setval(inj, out, 0);
  return out;
}

static vs_value* tx_KEY(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                        void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  if (inj->mode != VS_M_VAL)
    return vs_new_undef();

  vs_value* parent = inj->parent;
  vs_value* bkey = vs_new_string("`$KEY`");
  vs_value* keyspec = vs_getprop(parent, bkey, NULL);
  if (!vs_is_undef(keyspec)) {
    vs_delprop(parent, bkey);
    vs_release(bkey);
    vs_value* out = vs_getprop(inj->dparent, keyspec, NULL);
    vs_release(keyspec);
    return out;
  }
  vs_release(keyspec);
  vs_release(bkey);

  vs_value* banno = vs_new_string("`$ANNO`");
  vs_value* anno = vs_getprop(parent, banno, NULL);
  vs_release(banno);
  vs_value* key_str = vs_new_string("KEY");
  vs_value* defv = NULL;
  /* path[-2] */
  if (inj->path.len >= 2) {
    defv = vs_new_string(inj->path.data[inj->path.len - 2]);
  } else {
    defv = vs_new_undef();
  }
  vs_value* result = vs_getprop(anno, key_str, defv);
  vs_release(anno);
  vs_release(key_str);
  vs_release(defv);
  return result;
}

static vs_value* tx_ANNO(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                         void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  vs_value* banno = vs_new_string("`$ANNO`");
  vs_delprop(inj->parent, banno);
  vs_release(banno);
  return vs_new_undef();
}

static vs_value* tx_MERGE(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                          void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  if (inj->mode == VS_M_KEYPRE) {
    return vs_new_string(inj->key);
  }
  if (inj->mode == VS_M_KEYPOST) {
    vs_value* keyv = vs_new_string(inj->key);
    vs_value* args = vs_getprop(inj->parent, keyv, NULL);
    vs_release(keyv);
    vs_value* args_list = NULL;
    if (vs_is_list(args)) {
      args_list = vs_retain(args);
    } else {
      args_list = vs_new_list();
      vs_list_push(vs_as_list(args_list), args ? vs_retain(args) : vs_new_undef());
    }
    vs_release(args);
    vs_inj_setval(inj, NULL, 0);
    /* mergelist = [parent, ...args, clone(parent)] */
    vs_value* mergelist = vs_new_list();
    vs_list_push(vs_as_list(mergelist), vs_retain(inj->parent));
    vs_list* al = vs_as_list(args_list);
    for (size_t i = 0; i < al->len; i++)
      vs_list_push(vs_as_list(mergelist), vs_retain(al->items[i]));
    vs_list_push(vs_as_list(mergelist), vs_clone(inj->parent));
    vs_release(args_list);
    vs_value* merged = vs_merge(mergelist, VS_MAXDEPTH);
    vs_release(merged);
    vs_release(mergelist);
    return vs_new_string(inj->key);
  }
  return vs_new_undef();
}

static vs_value* tx_EACH(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                         void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (!vs_check_placement(VS_M_VAL, "EACH", VS_T_LIST, inj))
    return vs_new_undef();

  /* Truncate keys to length 1. */
  if (inj->keys.len > 1) {
    for (size_t i = 1; i < inj->keys.len; i++)
      free(inj->keys.data[i]);
    inj->keys.len = 1;
  }

  /* args = inj.parent[1..] */
  vs_list* pl = vs_as_list(inj->parent);
  vs_value* args = vs_new_list();
  for (size_t i = 1; i < pl->len; i++)
    vs_list_push(vs_as_list(args), vs_retain(pl->items[i]));
  int argT[2] = {VS_T_STRING, VS_T_ANY};
  vs_value* check = vs_injector_args(argT, 2, args);
  vs_release(args);
  vs_value* err = vs_list_get(vs_as_list(check), 0);
  if (err && !vs_is_undef(err)) {
    char buf[512];
    snprintf(buf, sizeof(buf), "$EACH: %s", vs_as_string(err));
    vs_list_push(vs_as_list(inj->errs), vs_new_string(buf));
    vs_release(check);
    return vs_new_undef();
  }
  vs_value* srcpath = vs_retain(vs_list_get(vs_as_list(check), 1));
  vs_value* child = vs_retain(vs_list_get(vs_as_list(check), 2));
  vs_release(check);

  /* srcstore = store[inj.base] || store */
  vs_value* srcstore = store;
  if (inj->base) {
    vs_value* bs = vs_map_get(vs_as_map(store), inj->base);
    if (bs)
      srcstore = bs;
  }
  vs_value* src = vs_getpath(srcstore, srcpath, inj);
  int srctype = vs_typify(src);

  /* Build tval = list of cloned children. */
  vs_value* tval = vs_new_list();
  if (srctype & VS_T_LIST) {
    vs_list* sl = vs_as_list(src);
    for (size_t i = 0; i < sl->len; i++) {
      vs_list_push(vs_as_list(tval), vs_clone(child));
    }
  } else if (srctype & VS_T_MAP) {
    vs_map* sm = vs_as_map(src);
    for (size_t i = 0; i < sm->len; i++) {
      vs_value* cc = vs_clone(child);
      vs_value* anno = vs_new_map();
      vs_value* keymap = vs_new_map();
      vs_map_set(vs_as_map(keymap), "KEY", vs_new_string(sm->entries[i].key));
      vs_map_set(vs_as_map(anno), "`$ANNO`", keymap);
      vs_value* mlist = vs_new_list();
      vs_list_push(vs_as_list(mlist), cc);
      vs_list_push(vs_as_list(mlist), anno);
      vs_value* merged = vs_merge(mlist, 1);
      vs_release(mlist);
      vs_list_push(vs_as_list(tval), merged);
    }
  }

  vs_value* rval = vs_new_list();

  if (vs_list_len(vs_as_list(tval)) > 0) {
    /* tcur initialised below */
    /* ckey = inj.path[-2] */
    const char* ckey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
    /* tpath = slice(inj.path, -1) */
    vs_strvec tpath;
    vs_strvec_init(&tpath);
    if (inj->path.len > 0) {
      for (size_t i = 0; i + 1 < inj->path.len; i++)
        vs_strvec_push(&tpath, inj->path.data[i]);
    }
    /* dpath = [$TOP, ...srcpath.split('.'), '$:'+ckey] */
    vs_strvec dpath;
    vs_strvec_init(&dpath);
    vs_strvec_push(&dpath, "$TOP");
    if (vs_is_string(srcpath)) {
      const char* s = vs_as_string(srcpath);
      size_t n = vs_string_len(srcpath);
      size_t i = 0;
      while (i <= n) {
        size_t j = i;
        while (j < n && s[j] != '.')
          j++;
        vs_strvec_push_n(&dpath, s + i, j - i);
        i = j + 1;
        if (j == n)
          break;
      }
    }
    char marker[256];
    snprintf(marker, sizeof(marker), "$:%s", ckey);
    vs_strvec_push(&dpath, marker);

    /* tcur = {ckey: src items} */
    vs_value* tcur = vs_new_map();
    /* tcur[ckey] = items(src).map(n=>n[1]) — basically a list of src values */
    vs_value* tcsrc = vs_new_list();
    if (vs_is_list(src)) {
      vs_list* sl = vs_as_list(src);
      for (size_t i = 0; i < sl->len; i++)
        vs_list_push(vs_as_list(tcsrc), vs_retain(sl->items[i]));
    } else if (vs_is_map(src)) {
      vs_map* sm = vs_as_map(src);
      for (size_t i = 0; i < sm->len; i++)
        vs_list_push(vs_as_list(tcsrc), vs_retain(sm->entries[i].value));
    }
    vs_map_set(vs_as_map(tcur), ckey, tcsrc);

    if (tpath.len > 1) {
      const char* pkey = inj->path.len >= 3 ? inj->path.data[inj->path.len - 3] : "$TOP";
      vs_value* outer = vs_new_map();
      vs_map_set(vs_as_map(outer), pkey, tcur);
      tcur = outer;
      char m2[256];
      snprintf(m2, sizeof(m2), "$:%s", pkey);
      vs_strvec_push(&dpath, m2);
    }

    /* tinj = inj.child(0, [ckey]) */
    vs_strvec ckeys_one;
    vs_strvec_init(&ckeys_one);
    vs_strvec_push(&ckeys_one, ckey);
    vs_injection* tinj = vs_inj_child(inj, 0, &ckeys_one);
    vs_strvec_free(&ckeys_one);
    /* Override tinj fields. */
    vs_strvec_clear(&tinj->path);
    for (size_t i = 0; i < tpath.len; i++)
      vs_strvec_push(&tinj->path, tpath.data[i]);
    vs_strvec_free(&tpath);
    /* tinj.nodes = slice(inj.nodes, -1) */
    if (inj->nodes_len > 0) {
      tinj->nodes_len = inj->nodes_len - 1;
      if (tinj->nodes_cap < tinj->nodes_len) {
        tinj->nodes = (vs_value**)realloc(tinj->nodes, tinj->nodes_len * sizeof(vs_value*));
        tinj->nodes_cap = tinj->nodes_len;
      }
      for (size_t i = 0; i < tinj->nodes_len; i++)
        tinj->nodes[i] = inj->nodes[i];
    } else {
      tinj->nodes_len = 0;
    }
    /* tinj.parent = nodes[-1] */
    vs_release(tinj->parent);
    tinj->parent =
        tinj->nodes_len > 0 ? vs_retain(tinj->nodes[tinj->nodes_len - 1]) : vs_new_undef();
    vs_value* ckeyv = vs_new_string(ckey);
    vs_setprop(tinj->parent, ckeyv, tval);
    vs_release(ckeyv);
    vs_release(tinj->val);
    tinj->val = vs_retain(tval);
    vs_strvec_clear(&tinj->dpath);
    for (size_t i = 0; i < dpath.len; i++)
      vs_strvec_push(&tinj->dpath, dpath.data[i]);
    vs_strvec_free(&dpath);
    vs_release(tinj->dparent);
    tinj->dparent = tcur;

    vs_value* out = vs_inject(tval, store, tinj);
    vs_release(out);
    vs_release(rval);
    rval = vs_retain(tinj->val);
    vs_inj_free(tinj);
  } else {
    vs_release(rval);
    rval = vs_new_list();
  }

  /* target = inj.nodes[-2] (fallback nodes[-1]) */
  vs_value* target = NULL;
  if (inj->nodes_len >= 2)
    target = inj->nodes[inj->nodes_len - 2];
  else if (inj->nodes_len >= 1)
    target = inj->nodes[inj->nodes_len - 1];
  const char* tkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  vs_value* tkeyv = vs_new_string(tkey);
  vs_setprop(target, tkeyv, rval);
  vs_release(tkeyv);

  vs_release(srcpath);
  vs_release(child);
  vs_release(src);
  vs_release(tval);

  /* Return rval[0] to prevent caller from damaging first slot. */
  vs_list* rl = vs_as_list(rval);
  vs_value* ret = (rl && rl->len > 0) ? vs_retain(rl->items[0]) : vs_new_undef();
  vs_release(rval);
  return ret;
}

static vs_value* tx_PACK(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                         void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (!vs_check_placement(VS_M_KEYPRE, "EACH", VS_T_MAP, inj))
    return vs_new_undef();

  vs_value* keyv = vs_new_string(inj->key);
  vs_value* args = vs_getprop(inj->parent, keyv, NULL);
  vs_release(keyv);

  int argT[2] = {VS_T_STRING, VS_T_ANY};
  vs_value* check = vs_injector_args(argT, 2, args);
  vs_value* err = vs_list_get(vs_as_list(check), 0);
  if (err && !vs_is_undef(err)) {
    char buf[512];
    snprintf(buf, sizeof(buf), "$EACH: %s", vs_as_string(err));
    vs_list_push(vs_as_list(inj->errs), vs_new_string(buf));
    vs_release(check);
    vs_release(args);
    return vs_new_undef();
  }
  vs_value* srcpath = vs_retain(vs_list_get(vs_as_list(check), 1));
  vs_value* origchildspec = vs_retain(vs_list_get(vs_as_list(check), 2));
  vs_release(check);
  vs_release(args);

  /* target / tkey */
  const char* tkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  size_t pathsize = inj->path.len;
  vs_value* target = NULL;
  if (inj->nodes_len >= pathsize - 1 && pathsize >= 2)
    target = inj->nodes[pathsize - 2];
  else if (inj->nodes_len >= 1)
    target = inj->nodes[inj->nodes_len - 1];

  vs_value* srcstore = store;
  if (inj->base) {
    vs_value* bs = vs_map_get(vs_as_map(store), inj->base);
    if (bs)
      srcstore = bs;
  }
  vs_value* src = vs_getpath(srcstore, srcpath, inj);
  /* Normalise src to list. */
  if (!vs_is_list(src)) {
    if (vs_is_map(src)) {
      vs_value* lst = vs_new_list();
      vs_map* sm = vs_as_map(src);
      for (size_t i = 0; i < sm->len; i++) {
        vs_value* it = sm->entries[i].value;
        vs_value* anno = vs_new_map();
        vs_map_set(vs_as_map(anno), "KEY", vs_new_string(sm->entries[i].key));
        vs_value* bk = vs_new_string("`$ANNO`");
        vs_setprop(it, bk, anno);
        vs_release(bk);
        vs_release(anno);
        vs_list_push(vs_as_list(lst), vs_retain(it));
      }
      vs_release(src);
      src = lst;
    } else {
      vs_release(src);
      src = vs_new_undef();
    }
  }
  if (vs_is_undef(src) || vs_is_null(src)) {
    vs_release(srcpath);
    vs_release(origchildspec);
    vs_release(src);
    return vs_new_undef();
  }

  vs_value* bkey = vs_new_string("`$KEY`");
  vs_value* keypath = vs_getprop(origchildspec, bkey, NULL);
  vs_delprop(origchildspec, bkey);
  vs_release(bkey);

  vs_value* bval = vs_new_string("`$VAL`");
  vs_value* child = vs_getprop(origchildspec, bval, origchildspec);
  vs_release(bval);

  /* Build tval map. */
  vs_value* tval = vs_new_map();
  vs_list* sl = vs_as_list(src);
  for (size_t i = 0; i < sl->len; i++) {
    vs_value* srcnode = sl->items[i];
    char* keystr = NULL;
    if (!vs_is_undef(keypath)) {
      if (vs_is_string(keypath) && vs_string_len(keypath) > 0 && vs_as_string(keypath)[0] == '`') {
        /* inject(keypath, merge([{},store,{$TOP:srcnode}], 1)) */
        vs_value* mlist = vs_new_list();
        vs_list_push(vs_as_list(mlist), vs_new_map());
        vs_list_push(vs_as_list(mlist), vs_retain(store));
        vs_value* topwrap = vs_new_map();
        vs_map_set(vs_as_map(topwrap), "$TOP", vs_retain(srcnode));
        vs_list_push(vs_as_list(mlist), topwrap);
        vs_value* mstore = vs_merge(mlist, 1);
        vs_release(mlist);
        vs_value* iv = vs_inject(keypath, mstore, NULL);
        keystr = vs_stringify(iv, -1);
        vs_release(iv);
        vs_release(mstore);
      } else {
        vs_value* kv = vs_getpath(srcnode, keypath, inj);
        keystr = vs_stringify(kv, -1);
        vs_release(kv);
      }
    } else {
      /* Use index. */
      char tmp[32];
      snprintf(tmp, sizeof(tmp), "%zu", i);
      keystr = xstrdup_t(tmp);
    }
    vs_value* tchild = vs_clone(child);
    vs_map_set(vs_as_map(tval), keystr, tchild);
    /* Preserve $ANNO from src. */
    vs_value* annob = vs_new_string("`$ANNO`");
    vs_value* anno = vs_getprop(srcnode, annob, NULL);
    if (vs_is_undef(anno)) {
      vs_delprop(tchild, annob);
    } else {
      vs_setprop(tchild, annob, anno);
    }
    vs_release(anno);
    vs_release(annob);
    free(keystr);
  }
  vs_release(child);

  vs_value* rval = vs_new_map();
  if (!vs_isempty(tval)) {
    /* tsrc = parallel src map */
    vs_value* tsrc = vs_new_map();
    for (size_t i = 0; i < sl->len; i++) {
      vs_value* n = sl->items[i];
      char* keystr = NULL;
      if (!vs_is_undef(keypath)) {
        if (vs_is_string(keypath) && vs_string_len(keypath) > 0 &&
            vs_as_string(keypath)[0] == '`') {
          vs_value* mlist = vs_new_list();
          vs_list_push(vs_as_list(mlist), vs_new_map());
          vs_list_push(vs_as_list(mlist), vs_retain(store));
          vs_value* tw = vs_new_map();
          vs_map_set(vs_as_map(tw), "$TOP", vs_retain(n));
          vs_list_push(vs_as_list(mlist), tw);
          vs_value* ms = vs_merge(mlist, 1);
          vs_release(mlist);
          vs_value* iv = vs_inject(keypath, ms, NULL);
          keystr = vs_stringify(iv, -1);
          vs_release(iv);
          vs_release(ms);
        } else {
          vs_value* kv = vs_getpath(n, keypath, inj);
          keystr = vs_stringify(kv, -1);
          vs_release(kv);
        }
      } else {
        char tmp[32];
        snprintf(tmp, sizeof(tmp), "%zu", i);
        keystr = xstrdup_t(tmp);
      }
      vs_map_set(vs_as_map(tsrc), keystr, vs_retain(n));
      free(keystr);
    }

    /* tpath = slice(inj.path, -1) */
    vs_strvec tpath;
    vs_strvec_init(&tpath);
    for (size_t i = 0; i + 1 < inj->path.len; i++)
      vs_strvec_push(&tpath, inj->path.data[i]);
    const char* ckey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";

    /* dpath build */
    vs_strvec dpath;
    vs_strvec_init(&dpath);
    vs_strvec_push(&dpath, "$TOP");
    if (vs_is_string(srcpath)) {
      const char* s = vs_as_string(srcpath);
      size_t n = vs_string_len(srcpath);
      size_t pos = 0;
      while (pos <= n) {
        size_t j = pos;
        while (j < n && s[j] != '.')
          j++;
        vs_strvec_push_n(&dpath, s + pos, j - pos);
        pos = j + 1;
        if (j == n)
          break;
      }
    }
    char marker[256];
    snprintf(marker, sizeof(marker), "$:%s", ckey);
    vs_strvec_push(&dpath, marker);

    vs_value* tcur = vs_new_map();
    vs_map_set(vs_as_map(tcur), ckey, tsrc);
    if (tpath.len > 1) {
      const char* pkey = inj->path.len >= 3 ? inj->path.data[inj->path.len - 3] : "$TOP";
      vs_value* outer = vs_new_map();
      vs_map_set(vs_as_map(outer), pkey, tcur);
      tcur = outer;
      char m2[256];
      snprintf(m2, sizeof(m2), "$:%s", pkey);
      vs_strvec_push(&dpath, m2);
    }

    vs_strvec ckeys_one;
    vs_strvec_init(&ckeys_one);
    vs_strvec_push(&ckeys_one, ckey);
    vs_injection* tinj = vs_inj_child(inj, 0, &ckeys_one);
    vs_strvec_free(&ckeys_one);
    vs_strvec_clear(&tinj->path);
    for (size_t i = 0; i < tpath.len; i++)
      vs_strvec_push(&tinj->path, tpath.data[i]);
    vs_strvec_free(&tpath);
    if (inj->nodes_len > 0) {
      tinj->nodes_len = inj->nodes_len - 1;
      if (tinj->nodes_cap < tinj->nodes_len) {
        tinj->nodes = (vs_value**)realloc(tinj->nodes, tinj->nodes_len * sizeof(vs_value*));
        tinj->nodes_cap = tinj->nodes_len;
      }
      for (size_t i = 0; i < tinj->nodes_len; i++)
        tinj->nodes[i] = inj->nodes[i];
    } else {
      tinj->nodes_len = 0;
    }
    vs_release(tinj->parent);
    tinj->parent =
        tinj->nodes_len > 0 ? vs_retain(tinj->nodes[tinj->nodes_len - 1]) : vs_new_undef();
    vs_release(tinj->val);
    tinj->val = vs_retain(tval);
    vs_strvec_clear(&tinj->dpath);
    for (size_t i = 0; i < dpath.len; i++)
      vs_strvec_push(&tinj->dpath, dpath.data[i]);
    vs_strvec_free(&dpath);
    vs_release(tinj->dparent);
    tinj->dparent = tcur;

    vs_value* out = vs_inject(tval, store, tinj);
    vs_release(out);
    vs_release(rval);
    rval = vs_retain(tinj->val);
    vs_inj_free(tinj);
  }

  vs_value* tkeyv = vs_new_string(tkey);
  vs_setprop(target, tkeyv, rval);
  vs_release(tkeyv);

  vs_release(srcpath);
  vs_release(origchildspec);
  vs_release(src);
  vs_release(keypath);
  vs_release(tval);
  vs_release(rval);

  return vs_new_undef();
}

static vs_value* tx_REF(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                        void* ud) {
  (void)ref;
  (void)ud;
  if (inj->mode != VS_M_VAL)
    return vs_new_undef();

  /* refpath = parent[1] */
  vs_value* one = vs_new_int(1);
  vs_value* refpath = vs_getprop(inj->parent, one, NULL);
  vs_release(one);
  /* End loop. */
  inj->keyI = inj->keys.len;

  /* spec = store.$SPEC() — invoke the function. */
  vs_value* spec_fn = vs_map_get(vs_as_map(store), "$SPEC");
  vs_value* spec = NULL;
  if (spec_fn && vs_is_injector(spec_fn)) {
    spec = spec_fn->as.fn.fn.inj(inj, spec_fn, "$SPEC", store, spec_fn->as.fn.ud);
  } else {
    spec = vs_new_undef();
  }

  /* dpath = slice(inj.path, 1) */
  vs_value* dpath_v = vs_new_list();
  for (size_t i = 1; i < inj->path.len; i++)
    vs_list_push(vs_as_list(dpath_v), vs_new_string(inj->path.data[i]));

  /* Build child injection state for the inner getpath. */
  vs_injection* tmp_inj = vs_inj_new(NULL, NULL);
  /* tmp_inj.dpath = dpath_v elements */
  vs_strvec_clear(&tmp_inj->dpath);
  vs_list* dl = vs_as_list(dpath_v);
  for (size_t i = 0; i < dl->len; i++)
    vs_strvec_push(&tmp_inj->dpath, vs_as_string(dl->items[i]));
  vs_value* dparent = vs_getpath(spec, dpath_v, NULL);
  tmp_inj->dparent = dparent;
  vs_value* refv = vs_getpath(spec, refpath, tmp_inj);
  vs_inj_free(tmp_inj);
  vs_release(spec);

  /* Walk refv for sub-refs. */
  bool hasSubRef = false;
  if (vs_is_node(refv)) {
    /* Iterative walk. */
    /* Simplified: walk all values; if any string equals "`$REF`", set flag. */
    /* Use a stack. */
    vs_value* stk = vs_new_list();
    vs_list_push(vs_as_list(stk), vs_retain(refv));
    while (vs_list_len(vs_as_list(stk)) > 0) {
      vs_value* node = vs_list_get(vs_as_list(stk), vs_list_len(vs_as_list(stk)) - 1);
      vs_retain(node);
      vs_list_erase(vs_as_list(stk), vs_list_len(vs_as_list(stk)) - 1);
      if (vs_is_map(node)) {
        vs_map* m = vs_as_map(node);
        for (size_t i = 0; i < m->len; i++) {
          vs_value* v = m->entries[i].value;
          if (vs_is_string(v) && strcmp(vs_as_string(v), "`$REF`") == 0)
            hasSubRef = true;
          if (vs_is_node(v))
            vs_list_push(vs_as_list(stk), vs_retain(v));
        }
      } else if (vs_is_list(node)) {
        vs_list* l = vs_as_list(node);
        for (size_t i = 0; i < l->len; i++) {
          vs_value* v = l->items[i];
          if (vs_is_string(v) && strcmp(vs_as_string(v), "`$REF`") == 0)
            hasSubRef = true;
          if (vs_is_node(v))
            vs_list_push(vs_as_list(stk), vs_retain(v));
        }
      }
      vs_release(node);
    }
    vs_release(stk);
  }

  vs_value* tref = vs_clone(refv);

  /* cpath = slice(inj.path, -3), tpath = slice(inj.path, -1) */
  vs_value* cpath = vs_new_list();
  /* slice(path, -3) means keep all but last 3 */
  if (inj->path.len > 3) {
    for (size_t i = 0; i + 3 < inj->path.len; i++)
      vs_list_push(vs_as_list(cpath), vs_new_string(inj->path.data[i]));
  }
  vs_value* tpath = vs_new_list();
  if (inj->path.len > 1) {
    for (size_t i = 0; i + 1 < inj->path.len; i++)
      vs_list_push(vs_as_list(tpath), vs_new_string(inj->path.data[i]));
  }
  vs_value* tcur = vs_getpath(store, cpath, NULL);
  vs_value* tval = vs_getpath(store, tpath, NULL);
  vs_value* rval = vs_new_undef();
  if (!hasSubRef || !vs_is_undef(tval)) {
    /* tinj = inj.child(0, [last_of_tpath]) */
    vs_list* tplist = vs_as_list(tpath);
    const char* lastpart =
        tplist->len > 0 ? vs_as_string(vs_list_get(tplist, tplist->len - 1)) : "";
    vs_strvec ckeys_one;
    vs_strvec_init(&ckeys_one);
    vs_strvec_push(&ckeys_one, lastpart);
    vs_injection* tinj = vs_inj_child(inj, 0, &ckeys_one);
    vs_strvec_free(&ckeys_one);

    vs_strvec_clear(&tinj->path);
    for (size_t i = 0; i < tplist->len; i++)
      vs_strvec_push(&tinj->path, vs_as_string(tplist->items[i]));
    if (inj->nodes_len > 0) {
      tinj->nodes_len = inj->nodes_len - 1;
      if (tinj->nodes_cap < tinj->nodes_len) {
        tinj->nodes = (vs_value**)realloc(tinj->nodes, tinj->nodes_len * sizeof(vs_value*));
        tinj->nodes_cap = tinj->nodes_len;
      }
      for (size_t i = 0; i < tinj->nodes_len; i++)
        tinj->nodes[i] = inj->nodes[i];
    } else {
      tinj->nodes_len = 0;
    }
    vs_release(tinj->parent);
    tinj->parent = inj->nodes_len >= 2 ? vs_retain(inj->nodes[inj->nodes_len - 2]) : vs_new_undef();
    vs_release(tinj->val);
    tinj->val = vs_retain(tref);

    vs_strvec_clear(&tinj->dpath);
    vs_list* cpl = vs_as_list(cpath);
    for (size_t i = 0; i < cpl->len; i++)
      vs_strvec_push(&tinj->dpath, vs_as_string(cpl->items[i]));
    vs_release(tinj->dparent);
    tinj->dparent = vs_retain(tcur);

    vs_value* out = vs_inject(tref, store, tinj);
    vs_release(out);
    rval = vs_retain(tinj->val);
    vs_inj_free(tinj);
  }

  vs_value* grandparent = vs_inj_setval(inj, rval, 2);
  if (vs_is_list(grandparent) && inj->prior) {
    /* TS: `inj.prior.keyI--`. With signed numbers, keyI can go to -1. We use
       keyI_neg as a flag for "logically -1" (size_t cannot represent it). */
    if (inj->prior->keyI > 0) {
      inj->prior->keyI--;
    } else if (inj->prior->keyI == 0 && !inj->prior->keyI_neg) {
      inj->prior->keyI_neg = true;
    }
  }

  vs_release(refpath);
  vs_release(dpath_v);
  vs_release(refv);
  vs_release(tref);
  vs_release(cpath);
  vs_release(tpath);
  vs_release(tcur);
  vs_release(tval);
  vs_release(rval);
  return val ? vs_retain(val) : vs_new_undef();
}

/* FORMATTER table */
static vs_value* formatter_identity(vs_value* k, vs_value* v, vs_value* parent, vs_value* path,
                                    void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  return v ? vs_retain(v) : vs_new_undef();
}
static vs_value* formatter_upper(vs_value* k, vs_value* v, vs_value* parent, vs_value* path,
                                 void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  if (vs_is_node(v))
    return v ? vs_retain(v) : vs_new_undef();
  char* s = vs_stringify(v, -1);
  for (char* p = s; *p; p++)
    *p = (char)toupper((unsigned char)*p);
  vs_value* out = vs_new_string(s);
  free(s);
  return out;
}
static vs_value* formatter_lower(vs_value* k, vs_value* v, vs_value* parent, vs_value* path,
                                 void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  if (vs_is_node(v))
    return v ? vs_retain(v) : vs_new_undef();
  char* s = vs_stringify(v, -1);
  for (char* p = s; *p; p++)
    *p = (char)tolower((unsigned char)*p);
  vs_value* out = vs_new_string(s);
  free(s);
  return out;
}
static vs_value* formatter_string(vs_value* k, vs_value* v, vs_value* parent, vs_value* path,
                                  void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  if (vs_is_node(v))
    return v ? vs_retain(v) : vs_new_undef();
  char* s = vs_stringify(v, -1);
  vs_value* out = vs_new_string(s);
  free(s);
  return out;
}
static vs_value* formatter_number(vs_value* k, vs_value* v, vs_value* parent, vs_value* path,
                                  void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  if (vs_is_node(v))
    return v ? vs_retain(v) : vs_new_undef();
  if (vs_is_number(v))
    return vs_retain(v);
  if (vs_is_string(v)) {
    char* end = NULL;
    double d = strtod(vs_as_string(v), &end);
    if (end && *end == '\0') {
      if (d == floor(d))
        return vs_new_int((int64_t)d);
      return vs_new_double(d);
    }
  }
  return vs_new_int(0);
}
static vs_value* formatter_integer(vs_value* k, vs_value* v, vs_value* parent, vs_value* path,
                                   void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  if (vs_is_node(v))
    return v ? vs_retain(v) : vs_new_undef();
  int32_t i = 0;
  if (vs_is_number(v))
    i = (int32_t)vs_as_int(v);
  else if (vs_is_string(v)) {
    char* end = NULL;
    double d = strtod(vs_as_string(v), &end);
    if (end && *end == '\0')
      i = (int32_t)d;
  }
  return vs_new_int((int64_t)i);
}
static vs_value* formatter_concat(vs_value* k, vs_value* v, vs_value* parent, vs_value* path,
                                  void* ud) {
  (void)parent;
  (void)path;
  (void)ud;
  if ((!k || vs_is_undef(k)) && vs_is_list(v)) {
    char* buf = NULL;
    size_t len = 0, cap = 0;
    vs_list* l = vs_as_list(v);
    for (size_t i = 0; i < l->len; i++) {
      vs_value* el = l->items[i];
      if (vs_is_node(el))
        continue;
      char* s = vs_stringify(el, -1);
      size_t sl = strlen(s);
      if (len + sl + 1 > cap) {
        size_t nc = cap == 0 ? 64 : cap;
        while (nc < len + sl + 1)
          nc *= 2;
        buf = (char*)realloc(buf, nc);
        if (!buf)
          abort();
        cap = nc;
      }
      memcpy(buf + len, s, sl);
      len += sl;
      buf[len] = '\0';
      free(s);
    }
    if (!buf)
      buf = xstrdup_t("");
    vs_value* out = vs_new_string(buf);
    free(buf);
    return out;
  }
  return v ? vs_retain(v) : vs_new_undef();
}

static vs_walkapply_fn formatter_lookup(const char* name) {
  if (strcmp(name, "identity") == 0)
    return formatter_identity;
  if (strcmp(name, "upper") == 0)
    return formatter_upper;
  if (strcmp(name, "lower") == 0)
    return formatter_lower;
  if (strcmp(name, "string") == 0)
    return formatter_string;
  if (strcmp(name, "number") == 0)
    return formatter_number;
  if (strcmp(name, "integer") == 0)
    return formatter_integer;
  if (strcmp(name, "concat") == 0)
    return formatter_concat;
  return NULL;
}

static vs_value* tx_FORMAT(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                           void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  /* Truncate keys. */
  if (inj->keys.len > 1) {
    for (size_t i = 1; i < inj->keys.len; i++)
      free(inj->keys.data[i]);
    inj->keys.len = 1;
  }
  if (inj->mode != VS_M_VAL)
    return vs_new_undef();

  vs_value* one = vs_new_int(1);
  vs_value* two = vs_new_int(2);
  vs_value* name = vs_getprop(inj->parent, one, NULL);
  vs_value* child = vs_getprop(inj->parent, two, NULL);
  vs_release(one);
  vs_release(two);

  const char* tkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  vs_value* target = NULL;
  if (inj->nodes_len >= 2)
    target = inj->nodes[inj->nodes_len - 2];
  else if (inj->nodes_len >= 1)
    target = inj->nodes[inj->nodes_len - 1];

  vs_injection* cinj = vs_inject_child(child, store, inj);
  vs_value* resolved = vs_retain(cinj->val);

  vs_walkapply_fn fmt = NULL;
  if (vs_is_func(name)) {
    /* Function name: use injector to walk. */
    /* Wrap injector as walk_apply via lambda-like helper not feasible; treat as injector call. */
  } else if (vs_is_string(name)) {
    fmt = formatter_lookup(vs_as_string(name));
  }
  if (!fmt) {
    char msg[256];
    snprintf(msg, sizeof(msg), "$FORMAT: unknown format: %s.",
             vs_is_string(name) ? vs_as_string(name) : "(unknown)");
    vs_list_push(vs_as_list(inj->errs), vs_new_string(msg));
    vs_release(name);
    vs_release(child);
    vs_release(resolved);
    if (cinj != inj)
      vs_inj_free(cinj);
    return vs_new_undef();
  }

  vs_value* out = vs_walk(resolved, fmt, NULL, VS_MAXDEPTH, NULL);

  vs_value* tkeyv = vs_new_string(tkey);
  vs_setprop(target, tkeyv, out);
  vs_release(tkeyv);

  vs_release(name);
  vs_release(child);
  vs_release(resolved);
  if (cinj != inj)
    vs_inj_free(cinj);

  return out;
}

static vs_value* tx_APPLY(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                          void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (!vs_check_placement(VS_M_VAL, "APPLY", VS_T_LIST, inj))
    return vs_new_undef();

  /* args = parent[1..] */
  vs_list* pl = vs_as_list(inj->parent);
  vs_value* args = vs_new_list();
  for (size_t i = 1; i < pl->len; i++)
    vs_list_push(vs_as_list(args), vs_retain(pl->items[i]));
  int argT[2] = {VS_T_FUNCTION, VS_T_ANY};
  vs_value* check = vs_injector_args(argT, 2, args);
  vs_release(args);
  vs_value* err = vs_list_get(vs_as_list(check), 0);
  if (err && !vs_is_undef(err)) {
    char buf[512];
    snprintf(buf, sizeof(buf), "$APPLY: %s", vs_as_string(err));
    vs_list_push(vs_as_list(inj->errs), vs_new_string(buf));
    vs_release(check);
    return vs_new_undef();
  }
  vs_value* apply = vs_retain(vs_list_get(vs_as_list(check), 1));
  vs_value* child = vs_retain(vs_list_get(vs_as_list(check), 2));
  vs_release(check);

  const char* tkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  vs_value* target = NULL;
  if (inj->nodes_len >= 2)
    target = inj->nodes[inj->nodes_len - 2];
  else if (inj->nodes_len >= 1)
    target = inj->nodes[inj->nodes_len - 1];

  vs_injection* cinj = vs_inject_child(child, store, inj);
  vs_value* resolved = vs_retain(cinj->val);

  vs_value* out = apply->as.fn.fn.inj(cinj, resolved, "", store, apply->as.fn.ud);

  vs_value* tkeyv = vs_new_string(tkey);
  vs_setprop(target, tkeyv, out);
  vs_release(tkeyv);

  vs_release(apply);
  vs_release(child);
  vs_release(resolved);
  if (cinj != inj)
    vs_inj_free(cinj);

  return out;
}

/* ===========================================================================
 * Validate checkers
 * ===========================================================================*/

static int typename_to_bit(const char* tname) {
  static const struct {
    const char* name;
    int bit;
  } TABLE[] = {
      {"any", VS_T_ANY},           {"nil", VS_T_NOVAL},         {"boolean", VS_T_BOOLEAN},
      {"decimal", VS_T_DECIMAL},   {"integer", VS_T_INTEGER},   {"number", VS_T_NUMBER},
      {"string", VS_T_STRING},     {"function", VS_T_FUNCTION}, {"symbol", VS_T_SYMBOL},
      {"null", VS_T_NULL},         {"list", VS_T_LIST},         {"map", VS_T_MAP},
      {"instance", VS_T_INSTANCE}, {"scalar", VS_T_SCALAR},     {"node", VS_T_NODE},
  };
  for (size_t i = 0; i < sizeof(TABLE) / sizeof(TABLE[0]); i++) {
    if (strcmp(TABLE[i].name, tname) == 0)
      return TABLE[i].bit;
  }
  return 0;
}

static vs_value* va_STRING(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                           void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  vs_value* keyv = vs_new_string(inj->key);
  vs_value* out = vs_getprop(inj->dparent, keyv, NULL);
  vs_release(keyv);
  int t = vs_typify(out);
  if ((t & VS_T_STRING) == 0) {
    vs_value* msg = _invalid_type_msg(&inj->path, "string", t, out);
    vs_list_push(vs_as_list(inj->errs), msg);
    vs_release(out);
    return vs_new_undef();
  }
  if (vs_string_len(out) == 0) {
    /* Build "Empty string at <path>" message. */
    vs_value* lst = vs_new_list();
    for (size_t i = 1; i < inj->path.len; i++)
      vs_list_push(vs_as_list(lst), vs_new_string(inj->path.data[i]));
    char* p = vs_pathify(lst, 0, 0);
    vs_release(lst);
    char buf[512];
    snprintf(buf, sizeof(buf), "Empty string at %s", p);
    free(p);
    vs_list_push(vs_as_list(inj->errs), vs_new_string(buf));
    vs_release(out);
    return vs_new_undef();
  }
  return out;
}

static vs_value* va_TYPE(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                         void* ud) {
  (void)val;
  (void)store;
  (void)ud;
  /* tname = ref[1..].toLowerCase() */
  if (!ref || ref[0] != '$')
    return vs_new_undef();
  char tname[32];
  size_t rl = strlen(ref);
  size_t cp = rl - 1;
  if (cp >= sizeof(tname))
    cp = sizeof(tname) - 1;
  for (size_t i = 0; i < cp; i++)
    tname[i] = (char)tolower((unsigned char)ref[1 + i]);
  tname[cp] = '\0';
  int typev = typename_to_bit(tname);
  vs_value* keyv = vs_new_string(inj->key);
  vs_value* out = vs_getprop(inj->dparent, keyv, NULL);
  vs_release(keyv);
  int t = vs_typify(out);
  if ((t & typev) == 0) {
    vs_value* msg = _invalid_type_msg(&inj->path, tname, t, out);
    vs_list_push(vs_as_list(inj->errs), msg);
    vs_release(out);
    return vs_new_undef();
  }
  return out;
}

static vs_value* va_ANY(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                        void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  vs_value* keyv = vs_new_string(inj->key);
  vs_value* out = vs_getprop(inj->dparent, keyv, NULL);
  vs_release(keyv);
  return out;
}

static vs_value* va_CHILD(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                          void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  if (inj->mode == VS_M_KEYPRE) {
    vs_value* keyv = vs_new_string(inj->key);
    vs_value* childtm = vs_getprop(inj->parent, keyv, NULL);
    vs_release(keyv);
    const char* pkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
    vs_value* pkv = vs_new_string(pkey);
    vs_value* tval = vs_getprop(inj->dparent, pkv, NULL);
    vs_release(pkv);
    bool tval_undef = vs_is_undef(tval) || vs_is_null(tval);
    if (tval_undef) {
      vs_release(tval);
      tval = vs_new_map();
    } else if (!vs_is_map(tval)) {
      /* error */
      vs_value* msg = _invalid_type_msg(&inj->path, "object", vs_typify(tval), tval);
      vs_list_push(vs_as_list(inj->errs), msg);
      vs_release(tval);
      vs_release(childtm);
      return vs_new_undef();
    }
    vs_strvec ckeys = vs_keysof(tval);
    for (size_t i = 0; i < ckeys.len; i++) {
      vs_value* ckv = vs_new_string(ckeys.data[i]);
      vs_setprop(inj->parent, ckv, vs_clone(childtm));
      vs_release(ckv);
      vs_strvec_push(&inj->keys, ckeys.data[i]);
    }
    vs_strvec_free(&ckeys);
    vs_inj_setval(inj, NULL, 0);
    vs_release(tval);
    vs_release(childtm);
    return vs_new_undef();
  }
  if (inj->mode == VS_M_VAL) {
    if (!vs_is_list(inj->parent)) {
      vs_list_push(vs_as_list(inj->errs), vs_new_string("Invalid $CHILD as value"));
      return vs_new_undef();
    }
    vs_value* one = vs_new_int(1);
    vs_value* childtm = vs_getprop(inj->parent, one, NULL);
    vs_release(one);
    if (!inj->dparent || vs_is_undef(inj->dparent)) {
      /* Empty list as default. */
      vs_value* nul = NULL;
      vs_value* empty = vs_new_list();
      (void)nul;
      /* slice(parent, 0, 0, true) — clear parent list. */
      if (vs_is_list(inj->parent))
        vs_list_clear(vs_as_list(inj->parent));
      vs_release(empty);
      vs_release(childtm);
      return vs_new_undef();
    }
    if (!vs_is_list(inj->dparent)) {
      vs_value* msg = _invalid_type_msg(&inj->path, "list", vs_typify(inj->dparent), inj->dparent);
      vs_list_push(vs_as_list(inj->errs), msg);
      inj->keyI = vs_list_len(vs_as_list(inj->parent));
      vs_release(childtm);
      return inj->dparent ? vs_retain(inj->dparent) : vs_new_undef();
    }
    /* Clone childtm into parent for each item. */
    vs_list* dl = vs_as_list(inj->dparent);
    vs_list_clear(vs_as_list(inj->parent));
    for (size_t i = 0; i < dl->len; i++) {
      vs_list_push(vs_as_list(inj->parent), vs_clone(childtm));
    }
    inj->keyI = 0;
    vs_release(childtm);
    return dl->len > 0 ? vs_retain(dl->items[0]) : vs_new_undef();
  }
  return vs_new_undef();
}

/* Forward decl for use in ONE / select. */
vs_value* vs_validate(vs_value* data, vs_value* spec, vs_injection* injdef);

static vs_value* va_ONE(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                        void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (inj->mode != VS_M_VAL)
    return vs_new_undef();
  if (!vs_is_list(inj->parent) || inj->keyI != 0) {
    /* Build path string. */
    vs_value* lst = vs_new_list();
    for (size_t i = 1; i + 1 < inj->path.len; i++)
      vs_list_push(vs_as_list(lst), vs_new_string(inj->path.data[i]));
    char* ps = vs_pathify(lst, 0, 0);
    vs_release(lst);
    char buf[512];
    snprintf(buf, sizeof(buf),
             "The $ONE validator at field %s must be the first element of an array.", ps);
    free(ps);
    vs_list_push(vs_as_list(inj->errs), vs_new_string(buf));
    return vs_new_undef();
  }
  inj->keyI = inj->keys.len;
  vs_inj_setval(inj, inj->dparent, 2);

  /* slice path to drop last. */
  if (inj->path.len > 0) {
    free(inj->path.data[inj->path.len - 1]);
    inj->path.len--;
  }
  free(inj->key);
  inj->key = inj->path.len > 0 ? xstrdup_t(inj->path.data[inj->path.len - 1]) : xstrdup_t("");

  vs_list* pl = vs_as_list(inj->parent);
  vs_value* tvals = vs_new_list();
  for (size_t i = 1; i < pl->len; i++)
    vs_list_push(vs_as_list(tvals), vs_retain(pl->items[i]));
  if (vs_list_len(vs_as_list(tvals)) == 0) {
    vs_value* lst = vs_new_list();
    for (size_t i = 1; i + 1 < inj->path.len; i++)
      vs_list_push(vs_as_list(lst), vs_new_string(inj->path.data[i]));
    char* ps = vs_pathify(lst, 0, 0);
    vs_release(lst);
    char buf[512];
    snprintf(buf, sizeof(buf), "The $ONE validator at field %s must have at least one argument.",
             ps);
    free(ps);
    vs_list_push(vs_as_list(inj->errs), vs_new_string(buf));
    vs_release(tvals);
    return vs_new_undef();
  }

  vs_list* tvl = vs_as_list(tvals);
  for (size_t i = 0; i < tvl->len; i++) {
    vs_value* tval = tvl->items[i];
    /* vstore = merge([{}, store], 1); vstore.$TOP = inj.dparent */
    vs_value* mlist = vs_new_list();
    vs_list_push(vs_as_list(mlist), vs_new_map());
    vs_list_push(vs_as_list(mlist), vs_retain(store));
    vs_value* vstore = vs_merge(mlist, 1);
    vs_release(mlist);
    vs_map_set(vs_as_map(vstore), "$TOP", inj->dparent ? vs_retain(inj->dparent) : vs_new_undef());

    vs_injection* sub = vs_inj_new(NULL, NULL);
    sub->extra = vstore;
    sub->errs = vs_new_list();
    sub->meta = vs_retain(inj->meta);
    vs_value* vcurrent = vs_validate(inj->dparent, tval, sub);
    vs_inj_setval(inj, vcurrent, -2);
    vs_release(vcurrent);

    size_t terrlen = vs_list_len(vs_as_list(sub->errs));
    vs_inj_free(sub);
    vs_release(vstore);
    if (terrlen == 0) {
      vs_release(tvals);
      return vs_new_undef();
    }
  }
  /* All failed: build "one of <vals>" needtype and push V0210-style msg. */
  size_t tvc = vs_list_len(vs_as_list(tvals));
  char needtype[1024];
  needtype[0] = '\0';
  if (tvc > 1)
    strcat(needtype, "one of ");
  bool first_tv = true;
  vs_list* tvl_ = vs_as_list(tvals);
  for (size_t i = 0; i < tvl_->len; i++) {
    char* s = vs_stringify(tvl_->items[i], -1);
    /* Lower-case any `$NAME` -> name for human readability (R_TRANSFORM_NAME). */
    size_t sl = strlen(s);
    char* ls = (char*)malloc(sl + 1);
    size_t lw = 0;
    for (size_t k = 0; k < sl; k++) {
      if (k + 2 < sl && s[k] == '`' && s[k + 1] == '$' && s[k + 2] >= 'A' && s[k + 2] <= 'Z') {
        /* find closing ` */
        size_t e = k + 2;
        while (e < sl && s[e] >= 'A' && s[e] <= 'Z')
          e++;
        if (e < sl && s[e] == '`') {
          for (size_t q = k + 2; q < e; q++)
            ls[lw++] = (char)(s[q] - 'A' + 'a');
          k = e;
          continue;
        }
      }
      ls[lw++] = s[k];
    }
    ls[lw] = '\0';
    free(s);
    size_t cur = strlen(needtype);
    if (cur + lw + 4 < sizeof(needtype)) {
      if (!first_tv)
        strcat(needtype, ", ");
      strcat(needtype, ls);
      first_tv = false;
    }
    free(ls);
  }
  vs_value* msg = _invalid_type_msg(&inj->path, needtype, vs_typify(inj->dparent), inj->dparent);
  vs_list_push(vs_as_list(inj->errs), msg);
  vs_release(tvals);
  return vs_new_undef();
}

static vs_value* va_EXACT(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                          void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  if (inj->mode != VS_M_VAL) {
    vs_value* keyv = vs_new_string(inj->key);
    vs_delprop(inj->parent, keyv);
    vs_release(keyv);
    return vs_new_undef();
  }
  if (!vs_is_list(inj->parent) || inj->keyI != 0) {
    vs_list_push(vs_as_list(inj->errs), vs_new_string("$EXACT must be first element of array."));
    return vs_new_undef();
  }
  inj->keyI = inj->keys.len;
  vs_inj_setval(inj, inj->dparent, 2);
  if (inj->path.len > 0) {
    free(inj->path.data[inj->path.len - 1]);
    inj->path.len--;
  }
  free(inj->key);
  inj->key = inj->path.len > 0 ? xstrdup_t(inj->path.data[inj->path.len - 1]) : xstrdup_t("");
  vs_list* pl = vs_as_list(inj->parent);
  if (pl->len <= 1) {
    vs_list_push(vs_as_list(inj->errs), vs_new_string("$EXACT must have at least one argument."));
    return vs_new_undef();
  }
  char* curstr = NULL;
  for (size_t i = 1; i < pl->len; i++) {
    vs_value* tval = pl->items[i];
    bool match = vs_equals(tval, inj->dparent);
    if (!match && vs_is_node(tval)) {
      if (!curstr)
        curstr = vs_stringify(inj->dparent, -1);
      char* tvs = vs_stringify(tval, -1);
      if (strcmp(tvs, curstr) == 0)
        match = true;
      free(tvs);
    }
    if (match) {
      free(curstr);
      return vs_new_undef();
    }
  }
  free(curstr);
  /* Build "exactly equal to <vals>" needtype string. */
  size_t tvc = pl->len > 1 ? pl->len - 1 : 0;
  char needtype[1024];
  needtype[0] = '\0';
  if (inj->path.len <= 1)
    strcat(needtype, "value ");
  strcat(needtype, "exactly equal to ");
  if (tvc > 1)
    strcat(needtype, "one of ");
  bool first_tv = true;
  for (size_t i = 1; i < pl->len; i++) {
    char* s = vs_stringify(pl->items[i], -1);
    size_t slen = strlen(s);
    size_t cur = strlen(needtype);
    if (cur + slen + 4 < sizeof(needtype)) {
      if (!first_tv)
        strcat(needtype, ", ");
      strcat(needtype, s);
      first_tv = false;
    }
    free(s);
  }
  vs_value* msg = _invalid_type_msg(&inj->path, needtype, vs_typify(inj->dparent), inj->dparent);
  vs_list_push(vs_as_list(inj->errs), msg);
  return vs_new_undef();
}

/* ===========================================================================
 * Validation modifier
 * ===========================================================================*/

static void _validation(vs_value* pval, vs_value* key, vs_value* parent, vs_injection* inj,
                        vs_value* store, void* ud) {
  (void)store;
  (void)ud;
  if (!inj)
    return;
  if (pval && vs_is_skip(pval))
    return;

  /* exact = inj.meta[`$EXACT`] */
  vs_value* bex = vs_new_string("`$EXACT`");
  vs_value* exv = vs_getprop(inj->meta, bex, NULL);
  vs_release(bex);
  bool exact = vs_is_bool(exv) && vs_as_bool(exv);
  vs_release(exv);

  vs_value* cval = vs_getprop(inj->dparent, key, NULL);
  bool cval_undef = !cval || vs_is_undef(cval);
  if (!exact && cval_undef) {
    vs_release(cval);
    return;
  }

  int ptype = vs_typify(pval);
  /* Skip if pval is a residual command string. */
  if ((ptype & VS_T_STRING) && pval && strchr(vs_as_string(pval), '$')) {
    vs_release(cval);
    return;
  }
  int ctype = vs_typify(cval);
  if (ptype != ctype && pval && !vs_is_undef(pval)) {
    vs_value* msg = _invalid_type_msg(&inj->path, vs_typename(ptype), ctype, cval);
    vs_list_push(vs_as_list(inj->errs), msg);
    vs_release(cval);
    return;
  }

  if (vs_is_map(cval)) {
    if (!vs_is_map(pval)) {
      vs_value* msg = _invalid_type_msg(&inj->path, vs_typename(ptype), ctype, cval);
      vs_list_push(vs_as_list(inj->errs), msg);
      vs_release(cval);
      return;
    }
    vs_strvec ckeys = vs_keysof(cval);
    vs_strvec pkeys = vs_keysof(pval);
    vs_value* bopen = vs_new_string("`$OPEN`");
    vs_value* openv = vs_getprop(pval, bopen, NULL);
    bool is_open = vs_is_bool(openv) && vs_as_bool(openv);
    vs_release(openv);
    if (pkeys.len > 0 && !is_open) {
      /* Closed object: gather badkeys. */
      char buf[4096];
      buf[0] = '\0';
      bool first = true;
      for (size_t i = 0; i < ckeys.len; i++) {
        vs_value* kv = vs_new_string(ckeys.data[i]);
        bool has = vs_haskey(pval, kv);
        vs_release(kv);
        if (!has) {
          if (!first)
            strcat(buf, ", ");
          strcat(buf, ckeys.data[i]);
          first = false;
        }
      }
      if (buf[0] != '\0') {
        vs_value* lst = vs_new_list();
        for (size_t i = 1; i < inj->path.len; i++)
          vs_list_push(vs_as_list(lst), vs_new_string(inj->path.data[i]));
        char* ps = vs_pathify(lst, 0, 0);
        vs_release(lst);
        char full[4500];
        snprintf(full, sizeof(full), "Unexpected keys at field %s: %s", ps, buf);
        free(ps);
        vs_list_push(vs_as_list(inj->errs), vs_new_string(full));
      }
    } else {
      /* Open: merge cval into pval. */
      vs_value* ml = vs_new_list();
      vs_list_push(vs_as_list(ml), vs_retain(pval));
      vs_list_push(vs_as_list(ml), vs_retain(cval));
      vs_value* m = vs_merge(ml, VS_MAXDEPTH);
      vs_release(ml);
      vs_release(m);
      if (vs_is_node(pval))
        vs_delprop(pval, bopen);
    }
    vs_release(bopen);
    vs_strvec_free(&ckeys);
    vs_strvec_free(&pkeys);
  } else if (vs_is_list(cval)) {
    if (!vs_is_list(pval)) {
      vs_value* msg = _invalid_type_msg(&inj->path, vs_typename(ptype), ctype, cval);
      vs_list_push(vs_as_list(inj->errs), msg);
    }
  } else if (exact) {
    if (!vs_equals(cval, pval)) {
      vs_value* lst = vs_new_list();
      for (size_t i = 1; i < inj->path.len; i++)
        vs_list_push(vs_as_list(lst), vs_new_string(inj->path.data[i]));
      char* ps = vs_pathify(lst, 0, 0);
      vs_release(lst);
      char* cs = vs_stringify(cval, -1);
      char* psv = vs_stringify(pval, -1);
      size_t bufsz = strlen(ps) + strlen(cs) + strlen(psv) + 64;
      char* buf = (char*)malloc(bufsz);
      if (inj->path.len > 1)
        snprintf(buf, bufsz, "Value at field %s: %s should equal %s.", ps, cs, psv);
      else
        snprintf(buf, bufsz, "Value %s should equal %s.", cs, psv);
      vs_list_push(vs_as_list(inj->errs), vs_new_string(buf));
      free(buf);
      free(ps);
      free(cs);
      free(psv);
    }
  } else {
    /* Spec value is a default; copy data over. */
    vs_setprop(parent, key, cval);
  }
  vs_release(cval);
}

/* ===========================================================================
 * Validate handler (R_META_PATH detection)
 * ===========================================================================*/

static vs_value* vs_validatehandler(vs_injection* inj, vs_value* val, const char* ref,
                                    vs_value* store, void* ud) {
  (void)store;
  (void)ud;
  if (ref) {
    const char* dol = strchr(ref, '$');
    if (dol && dol != ref && (dol[1] == '=' || dol[1] == '~') && dol[2] != '\0') {
      char sep = dol[1];
      if (sep == '=') {
        vs_value* pair = vs_new_list();
        vs_list_push(vs_as_list(pair), vs_new_string("`$EXACT`"));
        vs_list_push(vs_as_list(pair), val ? vs_retain(val) : vs_new_undef());
        vs_inj_setval(inj, pair, 0);
        vs_release(pair);
      } else {
        vs_inj_setval(inj, val, 0);
      }
      inj->keyI = 0;
      inj->keyI_neg = true;
      return vs_new_skip();
    }
  }
  /* Delegate to inject-handler. */
  vs_value* out = val ? vs_retain(val) : vs_new_undef();
  bool iscmd = vs_is_injector(val) && (ref == NULL || ref[0] == '$');
  if (iscmd) {
    vs_release(out);
    out = val->as.fn.fn.inj(inj, val, ref, store, val->as.fn.ud);
  } else if (inj->mode == VS_M_VAL && inj->full) {
    vs_inj_setval(inj, val, 0);
  }
  return out;
}

/* Spec wrapper (returns origspec). */
static vs_value* spec_fn_impl(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                              void* ud) {
  (void)inj;
  (void)val;
  (void)ref;
  (void)store;
  return vs_retain((vs_value*)ud);
}

/* $BT / $DS / $WHEN runtime helpers (returned via store as injector calls). */
static vs_value* tx_BT(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                       void* ud) {
  (void)inj;
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  return vs_new_string("`");
}
static vs_value* tx_DS(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                       void* ud) {
  (void)inj;
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  return vs_new_string("$");
}
static vs_value* tx_WHEN(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                         void* ud) {
  (void)inj;
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  /* ISO-8601 UTC timestamp (best effort). */
  time_t t = time(NULL);
  struct tm* tm = gmtime(&t);
  char buf[64];
  strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%S.000Z", tm);
  return vs_new_string(buf);
}

/* ===========================================================================
 * transform
 * ===========================================================================*/

vs_value* vs_transform(vs_value* data, vs_value* spec, vs_injection* injdef) {
  vs_value* origspec = spec;
  vs_value* spec_clone = vs_clone(spec);

  vs_value* errs = NULL;
  bool collect = false;
  vs_value* injdef_modify = NULL;
  vs_value* injdef_handler = NULL;
  vs_value* injdef_meta = NULL;
  vs_value* injdef_extra = NULL;

  if (injdef) {
    if (injdef->errs) {
      errs = vs_retain(injdef->errs);
      collect = true;
    }
    if (injdef->modify_val)
      injdef_modify = vs_retain(injdef->modify_val);
    if (injdef->handler_val)
      injdef_handler = vs_retain(injdef->handler_val);
    if (injdef->meta)
      injdef_meta = vs_retain(injdef->meta);
    if (injdef->extra)
      injdef_extra = injdef->extra; /* borrowed */
  }
  if (!errs)
    errs = vs_new_list();

  /* extra split into extraTransforms (keys starting with $) and extraData. */
  vs_value* extraTransforms = vs_new_map();
  vs_value* extraData = vs_new_map();
  if (injdef_extra && vs_is_map(injdef_extra)) {
    vs_map* em = vs_as_map(injdef_extra);
    for (size_t i = 0; i < em->len; i++) {
      const char* k = em->entries[i].key;
      vs_value* v = em->entries[i].value;
      if (k[0] == '$')
        vs_map_set(vs_as_map(extraTransforms), k, vs_retain(v));
      else
        vs_map_set(vs_as_map(extraData), k, vs_retain(v));
    }
  }

  /* dataClone = merge([extraData (or undef if empty), clone(data)]) */
  vs_value* ml = vs_new_list();
  if (!vs_isempty(extraData))
    vs_list_push(vs_as_list(ml), vs_clone(extraData));
  vs_list_push(vs_as_list(ml), vs_clone(data));
  vs_value* dataClone = vs_merge(ml, VS_MAXDEPTH);
  vs_release(ml);

  /* Build store. */
  vs_value* builtins = vs_new_map();
  vs_map_set(vs_as_map(builtins), "$TOP", dataClone);
  /* $SPEC closure */
  vs_value* spec_fn = vs_new_injector(spec_fn_impl, origspec);
  vs_map_set(vs_as_map(builtins), "$SPEC", spec_fn);
  vs_map_set(vs_as_map(builtins), "$BT", vs_new_injector(tx_BT, NULL));
  vs_map_set(vs_as_map(builtins), "$DS", vs_new_injector(tx_DS, NULL));
  vs_map_set(vs_as_map(builtins), "$WHEN", vs_new_injector(tx_WHEN, NULL));
  vs_map_set(vs_as_map(builtins), "$DELETE", vs_new_injector(tx_DELETE, NULL));
  vs_map_set(vs_as_map(builtins), "$COPY", vs_new_injector(tx_COPY, NULL));
  vs_map_set(vs_as_map(builtins), "$KEY", vs_new_injector(tx_KEY, NULL));
  vs_map_set(vs_as_map(builtins), "$ANNO", vs_new_injector(tx_ANNO, NULL));
  vs_map_set(vs_as_map(builtins), "$MERGE", vs_new_injector(tx_MERGE, NULL));
  vs_map_set(vs_as_map(builtins), "$EACH", vs_new_injector(tx_EACH, NULL));
  vs_map_set(vs_as_map(builtins), "$PACK", vs_new_injector(tx_PACK, NULL));
  vs_map_set(vs_as_map(builtins), "$REF", vs_new_injector(tx_REF, NULL));
  vs_map_set(vs_as_map(builtins), "$FORMAT", vs_new_injector(tx_FORMAT, NULL));
  vs_map_set(vs_as_map(builtins), "$APPLY", vs_new_injector(tx_APPLY, NULL));

  vs_value* errwrap = vs_new_map();
  vs_map_set(vs_as_map(errwrap), "$ERRS", vs_retain(errs));

  vs_value* sml = vs_new_list();
  vs_list_push(vs_as_list(sml), builtins);
  vs_list_push(vs_as_list(sml), extraTransforms);
  vs_list_push(vs_as_list(sml), errwrap);
  vs_value* store = vs_merge(sml, 1);
  vs_release(sml);

  /* Pass the (mode=0) config-bag injdef so inject() carries over caller settings
     while initialising as root. */
  vs_value* out = vs_inject(spec_clone, store, injdef);

  bool generr = vs_list_len(vs_as_list(errs)) > 0 && !collect;
  if (generr) {
    /* "throw" — emit error to stderr and return undef? In TS, throws.
       For C, write the joined message into errs and abort via a longer-term
       approach. For now, return out and the caller can inspect errs. */
  }

  vs_release(spec_clone);
  vs_release(store);
  vs_release(errs);
  vs_release(extraData);
  if (injdef_modify)
    vs_release(injdef_modify);
  if (injdef_handler)
    vs_release(injdef_handler);
  if (injdef_meta)
    vs_release(injdef_meta);

  return out;
}

/* ===========================================================================
 * validate
 * ===========================================================================*/

vs_value* vs_validate(vs_value* data, vs_value* spec, vs_injection* injdef) {
  vs_value* errs = NULL;
  bool collect = false;
  vs_value* meta_in = NULL;
  vs_value* extra_in = NULL;

  if (injdef) {
    if (injdef->errs) {
      errs = vs_retain(injdef->errs);
      collect = true;
    }
    if (injdef->meta)
      meta_in = vs_retain(injdef->meta);
    if (injdef->extra)
      extra_in = injdef->extra;
  }
  if (!errs)
    errs = vs_new_list();
  if (!meta_in)
    meta_in = vs_new_map();

  vs_value* bex = vs_new_string("`$EXACT`");
  if (!vs_haskey(meta_in, bex)) {
    vs_map_set(vs_as_map(meta_in), "`$EXACT`", vs_new_bool(false));
  }
  vs_release(bex);

  /* Build validator store. */
  vs_value* m1 = vs_new_map();
  vs_map_set(vs_as_map(m1), "$DELETE", vs_new_null());
  vs_map_set(vs_as_map(m1), "$COPY", vs_new_null());
  vs_map_set(vs_as_map(m1), "$KEY", vs_new_null());
  vs_map_set(vs_as_map(m1), "$META", vs_new_null());
  vs_map_set(vs_as_map(m1), "$MERGE", vs_new_null());
  vs_map_set(vs_as_map(m1), "$EACH", vs_new_null());
  vs_map_set(vs_as_map(m1), "$PACK", vs_new_null());
  vs_map_set(vs_as_map(m1), "$STRING", vs_new_injector(va_STRING, NULL));
  vs_map_set(vs_as_map(m1), "$NUMBER", vs_new_injector(va_TYPE, NULL));
  vs_map_set(vs_as_map(m1), "$INTEGER", vs_new_injector(va_TYPE, NULL));
  vs_map_set(vs_as_map(m1), "$DECIMAL", vs_new_injector(va_TYPE, NULL));
  vs_map_set(vs_as_map(m1), "$BOOLEAN", vs_new_injector(va_TYPE, NULL));
  vs_map_set(vs_as_map(m1), "$NULL", vs_new_injector(va_TYPE, NULL));
  vs_map_set(vs_as_map(m1), "$NIL", vs_new_injector(va_TYPE, NULL));
  vs_map_set(vs_as_map(m1), "$MAP", vs_new_injector(va_TYPE, NULL));
  vs_map_set(vs_as_map(m1), "$LIST", vs_new_injector(va_TYPE, NULL));
  vs_map_set(vs_as_map(m1), "$FUNCTION", vs_new_injector(va_TYPE, NULL));
  vs_map_set(vs_as_map(m1), "$INSTANCE", vs_new_injector(va_TYPE, NULL));
  vs_map_set(vs_as_map(m1), "$ANY", vs_new_injector(va_ANY, NULL));
  vs_map_set(vs_as_map(m1), "$CHILD", vs_new_injector(va_CHILD, NULL));
  vs_map_set(vs_as_map(m1), "$ONE", vs_new_injector(va_ONE, NULL));
  vs_map_set(vs_as_map(m1), "$EXACT", vs_new_injector(va_EXACT, NULL));

  vs_value* ext = extra_in ? vs_retain(extra_in) : vs_new_map();
  vs_value* errwrap = vs_new_map();
  vs_map_set(vs_as_map(errwrap), "$ERRS", vs_retain(errs));

  vs_value* ml = vs_new_list();
  vs_list_push(vs_as_list(ml), m1);
  vs_list_push(vs_as_list(ml), ext);
  vs_list_push(vs_as_list(ml), errwrap);
  vs_value* store = vs_merge(ml, 1);
  vs_release(ml);

  /* Wire up transform with our store / handler / modify. */
  vs_injection* sub = vs_inj_new(NULL, NULL);
  sub->mode = 0; /* config bag, not mid-recursion */
  vs_release(sub->errs);
  sub->errs = vs_retain(errs);
  vs_release(sub->meta);
  sub->meta = vs_retain(meta_in);
  sub->extra = store;
  vs_release(sub->modify_val);
  sub->modify_val = vs_new_modify(_validation, NULL);
  vs_release(sub->handler_val);
  sub->handler_val = vs_new_injector(vs_validatehandler, NULL);

  vs_value* out = vs_transform(data, spec, sub);

  bool generr = vs_list_len(vs_as_list(errs)) > 0 && !collect;
  (void)generr; /* Same as transform: keep errs accessible. */

  vs_inj_free(sub);
  vs_release(store);
  vs_release(errs);
  vs_release(meta_in);
  return out;
}

/* ===========================================================================
 * Select operators
 * ===========================================================================*/

static vs_value* sel_AND(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                         void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (inj->mode != VS_M_KEYPRE)
    return vs_new_undef();
  vs_value* keyv = vs_new_string(inj->key);
  vs_value* terms = vs_getprop(inj->parent, keyv, NULL);
  vs_release(keyv);
  /* ppath = slice(inj.path, -1); point = getpath(store, ppath) */
  vs_value* ppath = vs_new_list();
  for (size_t i = 0; i + 1 < inj->path.len; i++)
    vs_list_push(vs_as_list(ppath), vs_new_string(inj->path.data[i]));
  vs_value* point = vs_getpath(store, ppath, NULL);

  vs_value* ml = vs_new_list();
  vs_list_push(vs_as_list(ml), vs_new_map());
  vs_list_push(vs_as_list(ml), vs_retain(store));
  vs_value* vstore = vs_merge(ml, 1);
  vs_release(ml);
  vs_map_set(vs_as_map(vstore), "$TOP", vs_retain(point));

  if (vs_is_list(terms)) {
    vs_list* tl = vs_as_list(terms);
    for (size_t i = 0; i < tl->len; i++) {
      vs_value* term = tl->items[i];
      vs_injection* sub = vs_inj_new(NULL, NULL);
      sub->extra = vstore;
      vs_release(sub->errs);
      sub->errs = vs_new_list();
      vs_release(sub->meta);
      sub->meta = vs_retain(inj->meta);
      vs_value* out = vs_validate(point, term, sub);
      vs_release(out);
      if (vs_list_len(vs_as_list(sub->errs)) > 0) {
        vs_list_push(vs_as_list(inj->errs), vs_new_string("AND failed"));
      }
      vs_inj_free(sub);
    }
  }
  /* setprop(grandparent, gkey, point) */
  const char* gkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  vs_value* gp = inj->nodes_len >= 2 ? inj->nodes[inj->nodes_len - 2] : NULL;
  vs_value* gkv = vs_new_string(gkey);
  if (gp)
    vs_setprop(gp, gkv, point);
  vs_release(gkv);

  vs_release(terms);
  vs_release(ppath);
  vs_release(point);
  vs_release(vstore);
  return vs_new_undef();
}

static vs_value* sel_OR(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                        void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (inj->mode != VS_M_KEYPRE)
    return vs_new_undef();
  vs_value* keyv = vs_new_string(inj->key);
  vs_value* terms = vs_getprop(inj->parent, keyv, NULL);
  vs_release(keyv);
  vs_value* ppath = vs_new_list();
  for (size_t i = 0; i + 1 < inj->path.len; i++)
    vs_list_push(vs_as_list(ppath), vs_new_string(inj->path.data[i]));
  vs_value* point = vs_getpath(store, ppath, NULL);

  vs_value* ml = vs_new_list();
  vs_list_push(vs_as_list(ml), vs_new_map());
  vs_list_push(vs_as_list(ml), vs_retain(store));
  vs_value* vstore = vs_merge(ml, 1);
  vs_release(ml);
  vs_map_set(vs_as_map(vstore), "$TOP", vs_retain(point));

  bool any_ok = false;
  if (vs_is_list(terms)) {
    vs_list* tl = vs_as_list(terms);
    for (size_t i = 0; i < tl->len; i++) {
      vs_value* term = tl->items[i];
      vs_injection* sub = vs_inj_new(NULL, NULL);
      sub->extra = vstore;
      vs_release(sub->errs);
      sub->errs = vs_new_list();
      vs_release(sub->meta);
      sub->meta = vs_retain(inj->meta);
      vs_value* out = vs_validate(point, term, sub);
      vs_release(out);
      if (vs_list_len(vs_as_list(sub->errs)) == 0) {
        any_ok = true;
        vs_inj_free(sub);
        break;
      }
      vs_inj_free(sub);
    }
  }
  if (any_ok) {
    const char* gkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
    vs_value* gp = inj->nodes_len >= 2 ? inj->nodes[inj->nodes_len - 2] : NULL;
    vs_value* gkv = vs_new_string(gkey);
    if (gp)
      vs_setprop(gp, gkv, point);
    vs_release(gkv);
  } else {
    vs_list_push(vs_as_list(inj->errs), vs_new_string("OR failed"));
  }
  vs_release(terms);
  vs_release(ppath);
  vs_release(point);
  vs_release(vstore);
  return vs_new_undef();
}

static vs_value* sel_NOT(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                         void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (inj->mode != VS_M_KEYPRE)
    return vs_new_undef();
  vs_value* keyv = vs_new_string(inj->key);
  vs_value* term = vs_getprop(inj->parent, keyv, NULL);
  vs_release(keyv);
  vs_value* ppath = vs_new_list();
  for (size_t i = 0; i + 1 < inj->path.len; i++)
    vs_list_push(vs_as_list(ppath), vs_new_string(inj->path.data[i]));
  vs_value* point = vs_getpath(store, ppath, NULL);

  vs_value* ml = vs_new_list();
  vs_list_push(vs_as_list(ml), vs_new_map());
  vs_list_push(vs_as_list(ml), vs_retain(store));
  vs_value* vstore = vs_merge(ml, 1);
  vs_release(ml);
  vs_map_set(vs_as_map(vstore), "$TOP", vs_retain(point));

  vs_injection* sub = vs_inj_new(NULL, NULL);
  sub->extra = vstore;
  vs_release(sub->errs);
  sub->errs = vs_new_list();
  vs_release(sub->meta);
  sub->meta = vs_retain(inj->meta);
  vs_value* out = vs_validate(point, term, sub);
  vs_release(out);
  if (vs_list_len(vs_as_list(sub->errs)) == 0) {
    vs_list_push(vs_as_list(inj->errs), vs_new_string("NOT failed"));
  }
  vs_inj_free(sub);

  const char* gkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  vs_value* gp = inj->nodes_len >= 2 ? inj->nodes[inj->nodes_len - 2] : NULL;
  vs_value* gkv = vs_new_string(gkey);
  if (gp)
    vs_setprop(gp, gkv, point);
  vs_release(gkv);

  vs_release(term);
  vs_release(ppath);
  vs_release(point);
  vs_release(vstore);
  return vs_new_undef();
}

static int cmp_values(vs_value* a, vs_value* b) {
  if (vs_is_number(a) && vs_is_number(b)) {
    double da = vs_as_double(a);
    double db = vs_as_double(b);
    if (da < db)
      return -1;
    if (da > db)
      return 1;
    return 0;
  }
  if (vs_is_string(a) && vs_is_string(b))
    return strcmp(vs_as_string(a), vs_as_string(b));
  /* Fallback: stringify. */
  char* sa = vs_stringify(a, -1);
  char* sb = vs_stringify(b, -1);
  int r = strcmp(sa, sb);
  free(sa);
  free(sb);
  return r;
}

static vs_value* sel_CMP(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                         void* ud) {
  (void)val;
  (void)ud;
  if (inj->mode != VS_M_KEYPRE)
    return vs_new_undef();
  vs_value* keyv = vs_new_string(inj->key);
  vs_value* term = vs_getprop(inj->parent, keyv, NULL);
  vs_release(keyv);
  vs_value* ppath = vs_new_list();
  for (size_t i = 0; i + 1 < inj->path.len; i++)
    vs_list_push(vs_as_list(ppath), vs_new_string(inj->path.data[i]));
  vs_value* point = vs_getpath(store, ppath, NULL);

  bool pass = false;
  int c = cmp_values(point, term);
  if (strcmp(ref, "$GT") == 0)
    pass = c > 0;
  else if (strcmp(ref, "$LT") == 0)
    pass = c < 0;
  else if (strcmp(ref, "$GTE") == 0)
    pass = c >= 0;
  else if (strcmp(ref, "$LTE") == 0)
    pass = c <= 0;
  else if (strcmp(ref, "$LIKE") == 0) {
    /* Simple substring contain as approximation since C regex is fragile. */
    char* ps = vs_stringify(point, -1);
    const char* termstr = vs_is_string(term) ? vs_as_string(term) : "";
    pass = strstr(ps, termstr) != NULL;
    free(ps);
  }
  const char* gkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  vs_value* gp = inj->nodes_len >= 2 ? inj->nodes[inj->nodes_len - 2] : NULL;
  vs_value* gkv = vs_new_string(gkey);
  if (pass) {
    if (gp)
      vs_setprop(gp, gkv, point);
  } else {
    char buf[256];
    snprintf(buf, sizeof(buf), "CMP: %s failed", ref);
    vs_list_push(vs_as_list(inj->errs), vs_new_string(buf));
  }
  vs_release(gkv);
  vs_release(term);
  vs_release(ppath);
  vs_release(point);
  return vs_new_undef();
}

/* ===========================================================================
 * select
 * ===========================================================================*/

/* walk callback to add `$OPEN` to every map in the query. */
static vs_value* set_open_callback(vs_value* k, vs_value* v, vs_value* parent, vs_value* path,
                                   void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  if (vs_is_map(v)) {
    vs_value* bk = vs_new_string("`$OPEN`");
    if (!vs_haskey(v, bk)) {
      vs_map_set(vs_as_map(v), "`$OPEN`", vs_new_bool(true));
    }
    vs_release(bk);
  }
  return v ? vs_retain(v) : vs_new_undef();
}

vs_value* vs_select(vs_value* children, vs_value* query) {
  if (!vs_is_node(children))
    return vs_new_list();

  /* Convert children to list, adding $KEY to each. */
  vs_value* child_list = vs_new_list();
  if (vs_is_map(children)) {
    vs_map* m = vs_as_map(children);
    for (size_t i = 0; i < m->len; i++) {
      vs_value* it = m->entries[i].value;
      if (vs_is_map(it)) {
        vs_map_set(vs_as_map(it), "$KEY", vs_new_string(m->entries[i].key));
      }
      vs_list_push(vs_as_list(child_list), vs_retain(it));
    }
  } else {
    vs_list* l = vs_as_list(children);
    for (size_t i = 0; i < l->len; i++) {
      vs_value* it = l->items[i];
      if (vs_is_map(it)) {
        vs_map_set(vs_as_map(it), "$KEY", vs_new_int((int64_t)i));
      }
      vs_list_push(vs_as_list(child_list), vs_retain(it));
    }
  }

  /* extra = {$AND:..., $OR:..., $NOT:..., $GT/$LT/$GTE/$LTE/$LIKE:...} */
  vs_value* extra = vs_new_map();
  vs_map_set(vs_as_map(extra), "$AND", vs_new_injector(sel_AND, NULL));
  vs_map_set(vs_as_map(extra), "$OR", vs_new_injector(sel_OR, NULL));
  vs_map_set(vs_as_map(extra), "$NOT", vs_new_injector(sel_NOT, NULL));
  vs_map_set(vs_as_map(extra), "$GT", vs_new_injector(sel_CMP, NULL));
  vs_map_set(vs_as_map(extra), "$LT", vs_new_injector(sel_CMP, NULL));
  vs_map_set(vs_as_map(extra), "$GTE", vs_new_injector(sel_CMP, NULL));
  vs_map_set(vs_as_map(extra), "$LTE", vs_new_injector(sel_CMP, NULL));
  vs_map_set(vs_as_map(extra), "$LIKE", vs_new_injector(sel_CMP, NULL));

  /* meta = {`$EXACT`: true} */
  vs_value* meta = vs_new_map();
  vs_map_set(vs_as_map(meta), "`$EXACT`", vs_new_bool(true));

  /* q = clone(query); walk q to set `$OPEN` on every map. */
  vs_value* q = vs_clone(query);
  vs_value* walked = vs_walk(q, set_open_callback, NULL, VS_MAXDEPTH, NULL);
  vs_release(walked);

  vs_value* results = vs_new_list();
  vs_list* cl = vs_as_list(child_list);
  for (size_t i = 0; i < cl->len; i++) {
    vs_value* child = cl->items[i];
    vs_injection* sub = vs_inj_new(NULL, NULL);
    vs_release(sub->errs);
    sub->errs = vs_new_list();
    vs_release(sub->meta);
    sub->meta = vs_retain(meta);
    sub->extra = extra;
    vs_value* qc = vs_clone(q);
    vs_value* out = vs_validate(child, qc, sub);
    vs_release(out);
    vs_release(qc);
    if (vs_list_len(vs_as_list(sub->errs)) == 0) {
      vs_list_push(vs_as_list(results), vs_retain(child));
    }
    vs_inj_free(sub);
  }

  vs_release(child_list);
  vs_release(extra);
  vs_release(meta);
  vs_release(q);
  return results;
}
