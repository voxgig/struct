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
voxgig_value* voxgig_inject_str_v(const char* val, size_t vlen, voxgig_value* store,
                                  voxgig_injection* inj);

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

static voxgig_value* _invalid_type_msg(voxgig_strvec* path, const char* needtype, int vt,
                                       voxgig_value* v) {
  char* vs = NULL;
  if (!v || voxgig_is_undef(v) || voxgig_is_null(v))
    vs = xstrdup_t("no value");
  else
    vs = voxgig_stringify(v, -1);

  char* pathstr = NULL;
  if (path && path->len > 1) {
    /* pathify(path, 1, 0) — equivalent to slice(path,1).join('.') */
    voxgig_value* lst = voxgig_new_list();
    for (size_t i = 1; i < path->len; i++) {
      voxgig_list_push(voxgig_as_list(lst), voxgig_new_string(path->data[i]));
    }
    pathstr = voxgig_pathify(lst, 0, 0);
    voxgig_release(lst);
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
  if (v && !voxgig_is_undef(v) && !voxgig_is_null(v)) {
    strcat(buf, voxgig_typename(vt));
    strcat(buf, ": ");
  }
  strcat(buf, vs);
  strcat(buf, ".");
  voxgig_value* res = voxgig_new_string(buf);
  free(buf);
  free(vs);
  free(pathstr);
  return res;
}

/* ===========================================================================
 * Transform commands
 * ===========================================================================*/

static voxgig_value* tx_DELETE(voxgig_injection* inj, voxgig_value* val, const char* ref,
                               voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  voxgig_inj_setval(inj, NULL, 0);
  return voxgig_new_undef();
}

static voxgig_value* tx_COPY(voxgig_injection* inj, voxgig_value* val, const char* ref,
                             voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  if (!voxgig_check_placement(VOXGIG_M_VAL, "COPY", VOXGIG_T_ANY, inj))
    return voxgig_new_undef();
  voxgig_value* keyv = voxgig_new_string(inj->key);
  voxgig_value* tmp = voxgig_lookup(inj->dparent, keyv);
  voxgig_value* out = tmp ? voxgig_retain(tmp) : voxgig_new_undef();
  voxgig_release(keyv);
  voxgig_inj_setval(inj, out, 0);
  return out;
}

static voxgig_value* tx_KEY(voxgig_injection* inj, voxgig_value* val, const char* ref,
                            voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  if (inj->mode != VOXGIG_M_VAL)
    return voxgig_new_undef();

  voxgig_value* parent = inj->parent;
  voxgig_value* bkey = voxgig_new_string("`$KEY`");
  voxgig_value* keyspec = voxgig_getprop(parent, bkey, NULL);
  if (!voxgig_is_undef(keyspec)) {
    voxgig_delprop(parent, bkey);
    voxgig_release(bkey);
    voxgig_value* out = voxgig_getprop(inj->dparent, keyspec, NULL);
    voxgig_release(keyspec);
    return out;
  }
  voxgig_release(keyspec);
  voxgig_release(bkey);

  voxgig_value* banno = voxgig_new_string("`$ANNO`");
  voxgig_value* anno = voxgig_getprop(parent, banno, NULL);
  voxgig_release(banno);
  voxgig_value* key_str = voxgig_new_string("KEY");
  voxgig_value* defv = NULL;
  /* path[-2] */
  if (inj->path.len >= 2) {
    defv = voxgig_new_string(inj->path.data[inj->path.len - 2]);
  } else {
    defv = voxgig_new_undef();
  }
  voxgig_value* result = voxgig_getprop(anno, key_str, defv);
  voxgig_release(anno);
  voxgig_release(key_str);
  voxgig_release(defv);
  return result;
}

static voxgig_value* tx_ANNO(voxgig_injection* inj, voxgig_value* val, const char* ref,
                             voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  voxgig_value* banno = voxgig_new_string("`$ANNO`");
  voxgig_delprop(inj->parent, banno);
  voxgig_release(banno);
  return voxgig_new_undef();
}

static voxgig_value* tx_MERGE(voxgig_injection* inj, voxgig_value* val, const char* ref,
                              voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  if (inj->mode == VOXGIG_M_KEYPRE) {
    return voxgig_new_string(inj->key);
  }
  if (inj->mode == VOXGIG_M_KEYPOST) {
    voxgig_value* keyv = voxgig_new_string(inj->key);
    voxgig_value* args = voxgig_getprop(inj->parent, keyv, NULL);
    voxgig_release(keyv);
    voxgig_value* args_list = NULL;
    if (voxgig_is_list(args)) {
      args_list = voxgig_retain(args);
    } else {
      args_list = voxgig_new_list();
      voxgig_list_push(voxgig_as_list(args_list), args ? voxgig_retain(args) : voxgig_new_undef());
    }
    voxgig_release(args);
    voxgig_inj_setval(inj, NULL, 0);
    /* mergelist = [parent, ...args, clone(parent)] */
    voxgig_value* mergelist = voxgig_new_list();
    voxgig_list_push(voxgig_as_list(mergelist), voxgig_retain(inj->parent));
    voxgig_list* al = voxgig_as_list(args_list);
    for (size_t i = 0; i < al->len; i++)
      voxgig_list_push(voxgig_as_list(mergelist), voxgig_retain(al->items[i]));
    voxgig_list_push(voxgig_as_list(mergelist), voxgig_clone(inj->parent));
    voxgig_release(args_list);
    voxgig_value* merged = voxgig_merge(mergelist, VOXGIG_MAXDEPTH);
    voxgig_release(merged);
    voxgig_release(mergelist);
    return voxgig_new_string(inj->key);
  }
  return voxgig_new_undef();
}

static voxgig_value* tx_EACH(voxgig_injection* inj, voxgig_value* val, const char* ref,
                             voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (!voxgig_check_placement(VOXGIG_M_VAL, "EACH", VOXGIG_T_LIST, inj))
    return voxgig_new_undef();

  /* Truncate keys to length 1. */
  if (inj->keys.len > 1) {
    for (size_t i = 1; i < inj->keys.len; i++)
      free(inj->keys.data[i]);
    inj->keys.len = 1;
  }

  /* args = inj.parent[1..] */
  voxgig_list* pl = voxgig_as_list(inj->parent);
  voxgig_value* args = voxgig_new_list();
  for (size_t i = 1; i < pl->len; i++)
    voxgig_list_push(voxgig_as_list(args), voxgig_retain(pl->items[i]));
  int argT[2] = {VOXGIG_T_STRING, VOXGIG_T_ANY};
  voxgig_value* check = voxgig_injector_args(argT, 2, args);
  voxgig_release(args);
  voxgig_value* err = voxgig_list_get(voxgig_as_list(check), 0);
  if (err && !voxgig_is_undef(err)) {
    char buf[512];
    snprintf(buf, sizeof(buf), "$EACH: %s", voxgig_as_string(err));
    voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string(buf));
    voxgig_release(check);
    return voxgig_new_undef();
  }
  voxgig_value* srcpath = voxgig_retain(voxgig_list_get(voxgig_as_list(check), 1));
  voxgig_value* child = voxgig_retain(voxgig_list_get(voxgig_as_list(check), 2));
  voxgig_release(check);

  /* srcstore = store[inj.base] || store */
  voxgig_value* srcstore = store;
  if (inj->base) {
    voxgig_value* bs = voxgig_map_get(voxgig_as_map(store), inj->base);
    if (bs)
      srcstore = bs;
  }
  voxgig_value* src = voxgig_getpath(srcstore, srcpath, inj);
  int srctype = voxgig_typify(src);

  /* Build tval = list of cloned children. */
  voxgig_value* tval = voxgig_new_list();
  if (srctype & VOXGIG_T_LIST) {
    voxgig_list* sl = voxgig_as_list(src);
    for (size_t i = 0; i < sl->len; i++) {
      voxgig_list_push(voxgig_as_list(tval), voxgig_clone(child));
    }
  } else if (srctype & VOXGIG_T_MAP) {
    voxgig_map* sm = voxgig_as_map(src);
    for (size_t i = 0; i < sm->len; i++) {
      voxgig_value* cc = voxgig_clone(child);
      voxgig_value* anno = voxgig_new_map();
      voxgig_value* keymap = voxgig_new_map();
      voxgig_map_set(voxgig_as_map(keymap), "KEY", voxgig_new_string(sm->entries[i].key));
      voxgig_map_set(voxgig_as_map(anno), "`$ANNO`", keymap);
      voxgig_value* mlist = voxgig_new_list();
      voxgig_list_push(voxgig_as_list(mlist), cc);
      voxgig_list_push(voxgig_as_list(mlist), anno);
      voxgig_value* merged = voxgig_merge(mlist, 1);
      voxgig_release(mlist);
      voxgig_list_push(voxgig_as_list(tval), merged);
    }
  }

  voxgig_value* rval = voxgig_new_list();

  if (voxgig_list_len(voxgig_as_list(tval)) > 0) {
    /* tcur initialised below */
    /* ckey = inj.path[-2] */
    const char* ckey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
    /* tpath = slice(inj.path, -1) */
    voxgig_strvec tpath;
    voxgig_strvec_init(&tpath);
    if (inj->path.len > 0) {
      for (size_t i = 0; i + 1 < inj->path.len; i++)
        voxgig_strvec_push(&tpath, inj->path.data[i]);
    }
    /* dpath = [$TOP, ...srcpath.split('.'), '$:'+ckey] */
    voxgig_strvec dpath;
    voxgig_strvec_init(&dpath);
    voxgig_strvec_push(&dpath, "$TOP");
    if (voxgig_is_string(srcpath)) {
      const char* s = voxgig_as_string(srcpath);
      size_t n = voxgig_string_len(srcpath);
      size_t i = 0;
      while (i <= n) {
        size_t j = i;
        while (j < n && s[j] != '.')
          j++;
        voxgig_strvec_push_n(&dpath, s + i, j - i);
        i = j + 1;
        if (j == n)
          break;
      }
    }
    char marker[256];
    snprintf(marker, sizeof(marker), "$:%s", ckey);
    voxgig_strvec_push(&dpath, marker);

    /* tcur = {ckey: src items} */
    voxgig_value* tcur = voxgig_new_map();
    /* tcur[ckey] = items(src).map(n=>n[1]) — basically a list of src values */
    voxgig_value* tcsrc = voxgig_new_list();
    if (voxgig_is_list(src)) {
      voxgig_list* sl = voxgig_as_list(src);
      for (size_t i = 0; i < sl->len; i++)
        voxgig_list_push(voxgig_as_list(tcsrc), voxgig_retain(sl->items[i]));
    } else if (voxgig_is_map(src)) {
      voxgig_map* sm = voxgig_as_map(src);
      for (size_t i = 0; i < sm->len; i++)
        voxgig_list_push(voxgig_as_list(tcsrc), voxgig_retain(sm->entries[i].value));
    }
    voxgig_map_set(voxgig_as_map(tcur), ckey, tcsrc);

    if (tpath.len > 1) {
      const char* pkey = inj->path.len >= 3 ? inj->path.data[inj->path.len - 3] : "$TOP";
      voxgig_value* outer = voxgig_new_map();
      voxgig_map_set(voxgig_as_map(outer), pkey, tcur);
      tcur = outer;
      char m2[256];
      snprintf(m2, sizeof(m2), "$:%s", pkey);
      voxgig_strvec_push(&dpath, m2);
    }

    /* tinj = inj.child(0, [ckey]) */
    voxgig_strvec ckeys_one;
    voxgig_strvec_init(&ckeys_one);
    voxgig_strvec_push(&ckeys_one, ckey);
    voxgig_injection* tinj = voxgig_inj_child(inj, 0, &ckeys_one);
    voxgig_strvec_free(&ckeys_one);
    /* Override tinj fields. */
    voxgig_strvec_clear(&tinj->path);
    for (size_t i = 0; i < tpath.len; i++)
      voxgig_strvec_push(&tinj->path, tpath.data[i]);
    voxgig_strvec_free(&tpath);
    /* tinj.nodes = slice(inj.nodes, -1) */
    if (inj->nodes_len > 0) {
      tinj->nodes_len = inj->nodes_len - 1;
      if (tinj->nodes_cap < tinj->nodes_len) {
        tinj->nodes = (voxgig_value**)realloc(tinj->nodes, tinj->nodes_len * sizeof(voxgig_value*));
        tinj->nodes_cap = tinj->nodes_len;
      }
      for (size_t i = 0; i < tinj->nodes_len; i++)
        tinj->nodes[i] = inj->nodes[i];
    } else {
      tinj->nodes_len = 0;
    }
    /* tinj.parent = nodes[-1] */
    voxgig_release(tinj->parent);
    tinj->parent =
        tinj->nodes_len > 0 ? voxgig_retain(tinj->nodes[tinj->nodes_len - 1]) : voxgig_new_undef();
    voxgig_value* ckeyv = voxgig_new_string(ckey);
    voxgig_setprop(tinj->parent, ckeyv, tval);
    voxgig_release(ckeyv);
    voxgig_release(tinj->val);
    tinj->val = voxgig_retain(tval);
    voxgig_strvec_clear(&tinj->dpath);
    for (size_t i = 0; i < dpath.len; i++)
      voxgig_strvec_push(&tinj->dpath, dpath.data[i]);
    voxgig_strvec_free(&dpath);
    voxgig_release(tinj->dparent);
    tinj->dparent = tcur;

    voxgig_value* out = voxgig_inject(tval, store, tinj);
    voxgig_release(out);
    voxgig_release(rval);
    rval = voxgig_retain(tinj->val);
    voxgig_inj_free(tinj);
  } else {
    voxgig_release(rval);
    rval = voxgig_new_list();
  }

  /* target = inj.nodes[-2] (fallback nodes[-1]) */
  voxgig_value* target = NULL;
  if (inj->nodes_len >= 2)
    target = inj->nodes[inj->nodes_len - 2];
  else if (inj->nodes_len >= 1)
    target = inj->nodes[inj->nodes_len - 1];
  const char* tkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  voxgig_value* tkeyv = voxgig_new_string(tkey);
  voxgig_setprop(target, tkeyv, rval);
  voxgig_release(tkeyv);

  voxgig_release(srcpath);
  voxgig_release(child);
  voxgig_release(src);
  voxgig_release(tval);

  /* Return rval[0] to prevent caller from damaging first slot. */
  voxgig_list* rl = voxgig_as_list(rval);
  voxgig_value* ret = (rl && rl->len > 0) ? voxgig_retain(rl->items[0]) : voxgig_new_undef();
  voxgig_release(rval);
  return ret;
}

static voxgig_value* tx_PACK(voxgig_injection* inj, voxgig_value* val, const char* ref,
                             voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (!voxgig_check_placement(VOXGIG_M_KEYPRE, "EACH", VOXGIG_T_MAP, inj))
    return voxgig_new_undef();

  voxgig_value* keyv = voxgig_new_string(inj->key);
  voxgig_value* args = voxgig_getprop(inj->parent, keyv, NULL);
  voxgig_release(keyv);

  int argT[2] = {VOXGIG_T_STRING, VOXGIG_T_ANY};
  voxgig_value* check = voxgig_injector_args(argT, 2, args);
  voxgig_value* err = voxgig_list_get(voxgig_as_list(check), 0);
  if (err && !voxgig_is_undef(err)) {
    char buf[512];
    snprintf(buf, sizeof(buf), "$EACH: %s", voxgig_as_string(err));
    voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string(buf));
    voxgig_release(check);
    voxgig_release(args);
    return voxgig_new_undef();
  }
  voxgig_value* srcpath = voxgig_retain(voxgig_list_get(voxgig_as_list(check), 1));
  voxgig_value* origchildspec = voxgig_retain(voxgig_list_get(voxgig_as_list(check), 2));
  voxgig_release(check);
  voxgig_release(args);

  /* target / tkey */
  const char* tkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  size_t pathsize = inj->path.len;
  voxgig_value* target = NULL;
  if (inj->nodes_len >= pathsize - 1 && pathsize >= 2)
    target = inj->nodes[pathsize - 2];
  else if (inj->nodes_len >= 1)
    target = inj->nodes[inj->nodes_len - 1];

  voxgig_value* srcstore = store;
  if (inj->base) {
    voxgig_value* bs = voxgig_map_get(voxgig_as_map(store), inj->base);
    if (bs)
      srcstore = bs;
  }
  voxgig_value* src = voxgig_getpath(srcstore, srcpath, inj);
  /* Normalise src to list. */
  if (!voxgig_is_list(src)) {
    if (voxgig_is_map(src)) {
      voxgig_value* lst = voxgig_new_list();
      voxgig_map* sm = voxgig_as_map(src);
      for (size_t i = 0; i < sm->len; i++) {
        voxgig_value* it = sm->entries[i].value;
        voxgig_value* anno = voxgig_new_map();
        voxgig_map_set(voxgig_as_map(anno), "KEY", voxgig_new_string(sm->entries[i].key));
        voxgig_value* bk = voxgig_new_string("`$ANNO`");
        voxgig_setprop(it, bk, anno);
        voxgig_release(bk);
        voxgig_release(anno);
        voxgig_list_push(voxgig_as_list(lst), voxgig_retain(it));
      }
      voxgig_release(src);
      src = lst;
    } else {
      voxgig_release(src);
      src = voxgig_new_undef();
    }
  }
  if (voxgig_is_undef(src) || voxgig_is_null(src)) {
    voxgig_release(srcpath);
    voxgig_release(origchildspec);
    voxgig_release(src);
    return voxgig_new_undef();
  }

  voxgig_value* bkey = voxgig_new_string("`$KEY`");
  voxgig_value* keypath = voxgig_getprop(origchildspec, bkey, NULL);
  voxgig_delprop(origchildspec, bkey);
  voxgig_release(bkey);

  voxgig_value* bval = voxgig_new_string("`$VAL`");
  voxgig_value* child = voxgig_getprop(origchildspec, bval, origchildspec);
  voxgig_release(bval);

  /* Build tval map. */
  voxgig_value* tval = voxgig_new_map();
  voxgig_list* sl = voxgig_as_list(src);
  for (size_t i = 0; i < sl->len; i++) {
    voxgig_value* srcnode = sl->items[i];
    char* keystr = NULL;
    if (!voxgig_is_undef(keypath)) {
      if (voxgig_is_string(keypath) && voxgig_string_len(keypath) > 0 &&
          voxgig_as_string(keypath)[0] == '`') {
        /* inject(keypath, merge([{},store,{$TOP:srcnode}], 1)) */
        voxgig_value* mlist = voxgig_new_list();
        voxgig_list_push(voxgig_as_list(mlist), voxgig_new_map());
        voxgig_list_push(voxgig_as_list(mlist), voxgig_retain(store));
        voxgig_value* topwrap = voxgig_new_map();
        voxgig_map_set(voxgig_as_map(topwrap), "$TOP", voxgig_retain(srcnode));
        voxgig_list_push(voxgig_as_list(mlist), topwrap);
        voxgig_value* mstore = voxgig_merge(mlist, 1);
        voxgig_release(mlist);
        voxgig_value* iv = voxgig_inject(keypath, mstore, NULL);
        keystr = voxgig_stringify(iv, -1);
        voxgig_release(iv);
        voxgig_release(mstore);
      } else {
        voxgig_value* kv = voxgig_getpath(srcnode, keypath, inj);
        keystr = voxgig_stringify(kv, -1);
        voxgig_release(kv);
      }
    } else {
      /* Use index. */
      char tmp[32];
      snprintf(tmp, sizeof(tmp), "%zu", i);
      keystr = xstrdup_t(tmp);
    }
    voxgig_value* tchild = voxgig_clone(child);
    voxgig_map_set(voxgig_as_map(tval), keystr, tchild);
    /* Preserve $ANNO from src. */
    voxgig_value* annob = voxgig_new_string("`$ANNO`");
    voxgig_value* anno = voxgig_getprop(srcnode, annob, NULL);
    if (voxgig_is_undef(anno)) {
      voxgig_delprop(tchild, annob);
    } else {
      voxgig_setprop(tchild, annob, anno);
    }
    voxgig_release(anno);
    voxgig_release(annob);
    free(keystr);
  }
  voxgig_release(child);

  voxgig_value* rval = voxgig_new_map();
  if (!voxgig_isempty(tval)) {
    /* tsrc = parallel src map */
    voxgig_value* tsrc = voxgig_new_map();
    for (size_t i = 0; i < sl->len; i++) {
      voxgig_value* n = sl->items[i];
      char* keystr = NULL;
      if (!voxgig_is_undef(keypath)) {
        if (voxgig_is_string(keypath) && voxgig_string_len(keypath) > 0 &&
            voxgig_as_string(keypath)[0] == '`') {
          voxgig_value* mlist = voxgig_new_list();
          voxgig_list_push(voxgig_as_list(mlist), voxgig_new_map());
          voxgig_list_push(voxgig_as_list(mlist), voxgig_retain(store));
          voxgig_value* tw = voxgig_new_map();
          voxgig_map_set(voxgig_as_map(tw), "$TOP", voxgig_retain(n));
          voxgig_list_push(voxgig_as_list(mlist), tw);
          voxgig_value* ms = voxgig_merge(mlist, 1);
          voxgig_release(mlist);
          voxgig_value* iv = voxgig_inject(keypath, ms, NULL);
          keystr = voxgig_stringify(iv, -1);
          voxgig_release(iv);
          voxgig_release(ms);
        } else {
          voxgig_value* kv = voxgig_getpath(n, keypath, inj);
          keystr = voxgig_stringify(kv, -1);
          voxgig_release(kv);
        }
      } else {
        char tmp[32];
        snprintf(tmp, sizeof(tmp), "%zu", i);
        keystr = xstrdup_t(tmp);
      }
      voxgig_map_set(voxgig_as_map(tsrc), keystr, voxgig_retain(n));
      free(keystr);
    }

    /* tpath = slice(inj.path, -1) */
    voxgig_strvec tpath;
    voxgig_strvec_init(&tpath);
    for (size_t i = 0; i + 1 < inj->path.len; i++)
      voxgig_strvec_push(&tpath, inj->path.data[i]);
    const char* ckey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";

    /* dpath build */
    voxgig_strvec dpath;
    voxgig_strvec_init(&dpath);
    voxgig_strvec_push(&dpath, "$TOP");
    if (voxgig_is_string(srcpath)) {
      const char* s = voxgig_as_string(srcpath);
      size_t n = voxgig_string_len(srcpath);
      size_t pos = 0;
      while (pos <= n) {
        size_t j = pos;
        while (j < n && s[j] != '.')
          j++;
        voxgig_strvec_push_n(&dpath, s + pos, j - pos);
        pos = j + 1;
        if (j == n)
          break;
      }
    }
    char marker[256];
    snprintf(marker, sizeof(marker), "$:%s", ckey);
    voxgig_strvec_push(&dpath, marker);

    voxgig_value* tcur = voxgig_new_map();
    voxgig_map_set(voxgig_as_map(tcur), ckey, tsrc);
    if (tpath.len > 1) {
      const char* pkey = inj->path.len >= 3 ? inj->path.data[inj->path.len - 3] : "$TOP";
      voxgig_value* outer = voxgig_new_map();
      voxgig_map_set(voxgig_as_map(outer), pkey, tcur);
      tcur = outer;
      char m2[256];
      snprintf(m2, sizeof(m2), "$:%s", pkey);
      voxgig_strvec_push(&dpath, m2);
    }

    voxgig_strvec ckeys_one;
    voxgig_strvec_init(&ckeys_one);
    voxgig_strvec_push(&ckeys_one, ckey);
    voxgig_injection* tinj = voxgig_inj_child(inj, 0, &ckeys_one);
    voxgig_strvec_free(&ckeys_one);
    voxgig_strvec_clear(&tinj->path);
    for (size_t i = 0; i < tpath.len; i++)
      voxgig_strvec_push(&tinj->path, tpath.data[i]);
    voxgig_strvec_free(&tpath);
    if (inj->nodes_len > 0) {
      tinj->nodes_len = inj->nodes_len - 1;
      if (tinj->nodes_cap < tinj->nodes_len) {
        tinj->nodes = (voxgig_value**)realloc(tinj->nodes, tinj->nodes_len * sizeof(voxgig_value*));
        tinj->nodes_cap = tinj->nodes_len;
      }
      for (size_t i = 0; i < tinj->nodes_len; i++)
        tinj->nodes[i] = inj->nodes[i];
    } else {
      tinj->nodes_len = 0;
    }
    voxgig_release(tinj->parent);
    tinj->parent =
        tinj->nodes_len > 0 ? voxgig_retain(tinj->nodes[tinj->nodes_len - 1]) : voxgig_new_undef();
    voxgig_release(tinj->val);
    tinj->val = voxgig_retain(tval);
    voxgig_strvec_clear(&tinj->dpath);
    for (size_t i = 0; i < dpath.len; i++)
      voxgig_strvec_push(&tinj->dpath, dpath.data[i]);
    voxgig_strvec_free(&dpath);
    voxgig_release(tinj->dparent);
    tinj->dparent = tcur;

    voxgig_value* out = voxgig_inject(tval, store, tinj);
    voxgig_release(out);
    voxgig_release(rval);
    rval = voxgig_retain(tinj->val);
    voxgig_inj_free(tinj);
  }

  voxgig_value* tkeyv = voxgig_new_string(tkey);
  voxgig_setprop(target, tkeyv, rval);
  voxgig_release(tkeyv);

  voxgig_release(srcpath);
  voxgig_release(origchildspec);
  voxgig_release(src);
  voxgig_release(keypath);
  voxgig_release(tval);
  voxgig_release(rval);

  return voxgig_new_undef();
}

static voxgig_value* tx_REF(voxgig_injection* inj, voxgig_value* val, const char* ref,
                            voxgig_value* store, void* ud) {
  (void)ref;
  (void)ud;
  if (inj->mode != VOXGIG_M_VAL)
    return voxgig_new_undef();

  /* refpath = parent[1] */
  voxgig_value* one = voxgig_new_int(1);
  voxgig_value* refpath = voxgig_getprop(inj->parent, one, NULL);
  voxgig_release(one);
  /* End loop. */
  inj->keyI = inj->keys.len;

  /* spec = store.$SPEC() — invoke the function. */
  voxgig_value* spec_fn = voxgig_map_get(voxgig_as_map(store), "$SPEC");
  voxgig_value* spec = NULL;
  if (spec_fn && voxgig_is_injector(spec_fn)) {
    spec = spec_fn->as.fn.fn.inj(inj, spec_fn, "$SPEC", store, spec_fn->as.fn.ud);
  } else {
    spec = voxgig_new_undef();
  }

  /* dpath = slice(inj.path, 1) */
  voxgig_value* dpath_v = voxgig_new_list();
  for (size_t i = 1; i < inj->path.len; i++)
    voxgig_list_push(voxgig_as_list(dpath_v), voxgig_new_string(inj->path.data[i]));

  /* Build child injection state for the inner getpath. */
  voxgig_injection* tmp_inj = voxgig_inj_new(NULL, NULL);
  /* tmp_inj.dpath = dpath_v elements */
  voxgig_strvec_clear(&tmp_inj->dpath);
  voxgig_list* dl = voxgig_as_list(dpath_v);
  for (size_t i = 0; i < dl->len; i++)
    voxgig_strvec_push(&tmp_inj->dpath, voxgig_as_string(dl->items[i]));
  voxgig_value* dparent = voxgig_getpath(spec, dpath_v, NULL);
  tmp_inj->dparent = dparent;
  voxgig_value* refv = voxgig_getpath(spec, refpath, tmp_inj);
  voxgig_inj_free(tmp_inj);
  voxgig_release(spec);

  /* Walk refv for sub-refs. */
  bool hasSubRef = false;
  if (voxgig_is_node(refv)) {
    /* Iterative walk. */
    /* Simplified: walk all values; if any string equals "`$REF`", set flag. */
    /* Use a stack. */
    voxgig_value* stk = voxgig_new_list();
    voxgig_list_push(voxgig_as_list(stk), voxgig_retain(refv));
    while (voxgig_list_len(voxgig_as_list(stk)) > 0) {
      voxgig_value* node =
          voxgig_list_get(voxgig_as_list(stk), voxgig_list_len(voxgig_as_list(stk)) - 1);
      voxgig_retain(node);
      voxgig_list_erase(voxgig_as_list(stk), voxgig_list_len(voxgig_as_list(stk)) - 1);
      if (voxgig_is_map(node)) {
        voxgig_map* m = voxgig_as_map(node);
        for (size_t i = 0; i < m->len; i++) {
          voxgig_value* v = m->entries[i].value;
          if (voxgig_is_string(v) && strcmp(voxgig_as_string(v), "`$REF`") == 0)
            hasSubRef = true;
          if (voxgig_is_node(v))
            voxgig_list_push(voxgig_as_list(stk), voxgig_retain(v));
        }
      } else if (voxgig_is_list(node)) {
        voxgig_list* l = voxgig_as_list(node);
        for (size_t i = 0; i < l->len; i++) {
          voxgig_value* v = l->items[i];
          if (voxgig_is_string(v) && strcmp(voxgig_as_string(v), "`$REF`") == 0)
            hasSubRef = true;
          if (voxgig_is_node(v))
            voxgig_list_push(voxgig_as_list(stk), voxgig_retain(v));
        }
      }
      voxgig_release(node);
    }
    voxgig_release(stk);
  }

  voxgig_value* tref = voxgig_clone(refv);

  /* cpath = slice(inj.path, -3), tpath = slice(inj.path, -1) */
  voxgig_value* cpath = voxgig_new_list();
  /* slice(path, -3) means keep all but last 3 */
  if (inj->path.len > 3) {
    for (size_t i = 0; i + 3 < inj->path.len; i++)
      voxgig_list_push(voxgig_as_list(cpath), voxgig_new_string(inj->path.data[i]));
  }
  voxgig_value* tpath = voxgig_new_list();
  if (inj->path.len > 1) {
    for (size_t i = 0; i + 1 < inj->path.len; i++)
      voxgig_list_push(voxgig_as_list(tpath), voxgig_new_string(inj->path.data[i]));
  }
  voxgig_value* tcur = voxgig_getpath(store, cpath, NULL);
  voxgig_value* tval = voxgig_getpath(store, tpath, NULL);
  voxgig_value* rval = voxgig_new_undef();
  if (!hasSubRef || !voxgig_is_undef(tval)) {
    /* tinj = inj.child(0, [last_of_tpath]) */
    voxgig_list* tplist = voxgig_as_list(tpath);
    const char* lastpart =
        tplist->len > 0 ? voxgig_as_string(voxgig_list_get(tplist, tplist->len - 1)) : "";
    voxgig_strvec ckeys_one;
    voxgig_strvec_init(&ckeys_one);
    voxgig_strvec_push(&ckeys_one, lastpart);
    voxgig_injection* tinj = voxgig_inj_child(inj, 0, &ckeys_one);
    voxgig_strvec_free(&ckeys_one);

    voxgig_strvec_clear(&tinj->path);
    for (size_t i = 0; i < tplist->len; i++)
      voxgig_strvec_push(&tinj->path, voxgig_as_string(tplist->items[i]));
    if (inj->nodes_len > 0) {
      tinj->nodes_len = inj->nodes_len - 1;
      if (tinj->nodes_cap < tinj->nodes_len) {
        tinj->nodes = (voxgig_value**)realloc(tinj->nodes, tinj->nodes_len * sizeof(voxgig_value*));
        tinj->nodes_cap = tinj->nodes_len;
      }
      for (size_t i = 0; i < tinj->nodes_len; i++)
        tinj->nodes[i] = inj->nodes[i];
    } else {
      tinj->nodes_len = 0;
    }
    voxgig_release(tinj->parent);
    tinj->parent =
        inj->nodes_len >= 2 ? voxgig_retain(inj->nodes[inj->nodes_len - 2]) : voxgig_new_undef();
    voxgig_release(tinj->val);
    tinj->val = voxgig_retain(tref);

    voxgig_strvec_clear(&tinj->dpath);
    voxgig_list* cpl = voxgig_as_list(cpath);
    for (size_t i = 0; i < cpl->len; i++)
      voxgig_strvec_push(&tinj->dpath, voxgig_as_string(cpl->items[i]));
    voxgig_release(tinj->dparent);
    tinj->dparent = voxgig_retain(tcur);

    voxgig_value* out = voxgig_inject(tref, store, tinj);
    voxgig_release(out);
    rval = voxgig_retain(tinj->val);
    voxgig_inj_free(tinj);
  }

  voxgig_value* grandparent = voxgig_inj_setval(inj, rval, 2);
  if (voxgig_is_list(grandparent) && inj->prior) {
    /* TS: `inj.prior.keyI--`. With signed numbers, keyI can go to -1. We use
       keyI_neg as a flag for "logically -1" (size_t cannot represent it). */
    if (inj->prior->keyI > 0) {
      inj->prior->keyI--;
    } else if (inj->prior->keyI == 0 && !inj->prior->keyI_neg) {
      inj->prior->keyI_neg = true;
    }
  }

  voxgig_release(refpath);
  voxgig_release(dpath_v);
  voxgig_release(refv);
  voxgig_release(tref);
  voxgig_release(cpath);
  voxgig_release(tpath);
  voxgig_release(tcur);
  voxgig_release(tval);
  voxgig_release(rval);
  return val ? voxgig_retain(val) : voxgig_new_undef();
}

/* FORMATTER table */
static voxgig_value* formatter_identity(voxgig_value* k, voxgig_value* v, voxgig_value* parent,
                                        voxgig_value* path, void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  return v ? voxgig_retain(v) : voxgig_new_undef();
}
static voxgig_value* formatter_upper(voxgig_value* k, voxgig_value* v, voxgig_value* parent,
                                     voxgig_value* path, void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  if (voxgig_is_node(v))
    return v ? voxgig_retain(v) : voxgig_new_undef();
  char* s = voxgig_stringify(v, -1);
  for (char* p = s; *p; p++)
    *p = (char)toupper((unsigned char)*p);
  voxgig_value* out = voxgig_new_string(s);
  free(s);
  return out;
}
static voxgig_value* formatter_lower(voxgig_value* k, voxgig_value* v, voxgig_value* parent,
                                     voxgig_value* path, void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  if (voxgig_is_node(v))
    return v ? voxgig_retain(v) : voxgig_new_undef();
  char* s = voxgig_stringify(v, -1);
  for (char* p = s; *p; p++)
    *p = (char)tolower((unsigned char)*p);
  voxgig_value* out = voxgig_new_string(s);
  free(s);
  return out;
}
static voxgig_value* formatter_string(voxgig_value* k, voxgig_value* v, voxgig_value* parent,
                                      voxgig_value* path, void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  if (voxgig_is_node(v))
    return v ? voxgig_retain(v) : voxgig_new_undef();
  char* s = voxgig_stringify(v, -1);
  voxgig_value* out = voxgig_new_string(s);
  free(s);
  return out;
}
static voxgig_value* formatter_number(voxgig_value* k, voxgig_value* v, voxgig_value* parent,
                                      voxgig_value* path, void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  if (voxgig_is_node(v))
    return v ? voxgig_retain(v) : voxgig_new_undef();
  if (voxgig_is_number(v))
    return voxgig_retain(v);
  if (voxgig_is_string(v)) {
    char* end = NULL;
    double d = strtod(voxgig_as_string(v), &end);
    if (end && *end == '\0') {
      if (d == floor(d))
        return voxgig_new_int((int64_t)d);
      return voxgig_new_double(d);
    }
  }
  return voxgig_new_int(0);
}
static voxgig_value* formatter_integer(voxgig_value* k, voxgig_value* v, voxgig_value* parent,
                                       voxgig_value* path, void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  if (voxgig_is_node(v))
    return v ? voxgig_retain(v) : voxgig_new_undef();
  int32_t i = 0;
  if (voxgig_is_number(v))
    i = (int32_t)voxgig_as_int(v);
  else if (voxgig_is_string(v)) {
    char* end = NULL;
    double d = strtod(voxgig_as_string(v), &end);
    if (end && *end == '\0')
      i = (int32_t)d;
  }
  return voxgig_new_int((int64_t)i);
}
static voxgig_value* formatter_concat(voxgig_value* k, voxgig_value* v, voxgig_value* parent,
                                      voxgig_value* path, void* ud) {
  (void)parent;
  (void)path;
  (void)ud;
  if ((!k || voxgig_is_undef(k)) && voxgig_is_list(v)) {
    char* buf = NULL;
    size_t len = 0, cap = 0;
    voxgig_list* l = voxgig_as_list(v);
    for (size_t i = 0; i < l->len; i++) {
      voxgig_value* el = l->items[i];
      if (voxgig_is_node(el))
        continue;
      char* s = voxgig_stringify(el, -1);
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
    voxgig_value* out = voxgig_new_string(buf);
    free(buf);
    return out;
  }
  return v ? voxgig_retain(v) : voxgig_new_undef();
}

static voxgig_walkapply_fn formatter_lookup(const char* name) {
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

static voxgig_value* tx_FORMAT(voxgig_injection* inj, voxgig_value* val, const char* ref,
                               voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  /* Truncate keys. */
  if (inj->keys.len > 1) {
    for (size_t i = 1; i < inj->keys.len; i++)
      free(inj->keys.data[i]);
    inj->keys.len = 1;
  }
  if (inj->mode != VOXGIG_M_VAL)
    return voxgig_new_undef();

  voxgig_value* one = voxgig_new_int(1);
  voxgig_value* two = voxgig_new_int(2);
  voxgig_value* name = voxgig_getprop(inj->parent, one, NULL);
  voxgig_value* child = voxgig_getprop(inj->parent, two, NULL);
  voxgig_release(one);
  voxgig_release(two);

  const char* tkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  voxgig_value* target = NULL;
  if (inj->nodes_len >= 2)
    target = inj->nodes[inj->nodes_len - 2];
  else if (inj->nodes_len >= 1)
    target = inj->nodes[inj->nodes_len - 1];

  voxgig_injection* cinj = voxgig_inject_child(child, store, inj);
  voxgig_value* resolved = voxgig_retain(cinj->val);

  voxgig_walkapply_fn fmt = NULL;
  if (voxgig_is_func(name)) {
    /* Function name: use injector to walk. */
    /* Wrap injector as walk_apply via lambda-like helper not feasible; treat as injector call. */
  } else if (voxgig_is_string(name)) {
    fmt = formatter_lookup(voxgig_as_string(name));
  }
  if (!fmt) {
    char msg[256];
    snprintf(msg, sizeof(msg), "$FORMAT: unknown format: %s.",
             voxgig_is_string(name) ? voxgig_as_string(name) : "(unknown)");
    voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string(msg));
    voxgig_release(name);
    voxgig_release(child);
    voxgig_release(resolved);
    if (cinj != inj)
      voxgig_inj_free(cinj);
    return voxgig_new_undef();
  }

  voxgig_value* out = voxgig_walk(resolved, fmt, NULL, VOXGIG_MAXDEPTH, NULL);

  voxgig_value* tkeyv = voxgig_new_string(tkey);
  voxgig_setprop(target, tkeyv, out);
  voxgig_release(tkeyv);

  voxgig_release(name);
  voxgig_release(child);
  voxgig_release(resolved);
  if (cinj != inj)
    voxgig_inj_free(cinj);

  return out;
}

static voxgig_value* tx_APPLY(voxgig_injection* inj, voxgig_value* val, const char* ref,
                              voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (!voxgig_check_placement(VOXGIG_M_VAL, "APPLY", VOXGIG_T_LIST, inj))
    return voxgig_new_undef();

  /* args = parent[1..] */
  voxgig_list* pl = voxgig_as_list(inj->parent);
  voxgig_value* args = voxgig_new_list();
  for (size_t i = 1; i < pl->len; i++)
    voxgig_list_push(voxgig_as_list(args), voxgig_retain(pl->items[i]));
  int argT[2] = {VOXGIG_T_FUNCTION, VOXGIG_T_ANY};
  voxgig_value* check = voxgig_injector_args(argT, 2, args);
  voxgig_release(args);
  voxgig_value* err = voxgig_list_get(voxgig_as_list(check), 0);
  if (err && !voxgig_is_undef(err)) {
    char buf[512];
    snprintf(buf, sizeof(buf), "$APPLY: %s", voxgig_as_string(err));
    voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string(buf));
    voxgig_release(check);
    return voxgig_new_undef();
  }
  voxgig_value* apply = voxgig_retain(voxgig_list_get(voxgig_as_list(check), 1));
  voxgig_value* child = voxgig_retain(voxgig_list_get(voxgig_as_list(check), 2));
  voxgig_release(check);

  const char* tkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  voxgig_value* target = NULL;
  if (inj->nodes_len >= 2)
    target = inj->nodes[inj->nodes_len - 2];
  else if (inj->nodes_len >= 1)
    target = inj->nodes[inj->nodes_len - 1];

  voxgig_injection* cinj = voxgig_inject_child(child, store, inj);
  voxgig_value* resolved = voxgig_retain(cinj->val);

  voxgig_value* out = apply->as.fn.fn.inj(cinj, resolved, "", store, apply->as.fn.ud);

  voxgig_value* tkeyv = voxgig_new_string(tkey);
  voxgig_setprop(target, tkeyv, out);
  voxgig_release(tkeyv);

  voxgig_release(apply);
  voxgig_release(child);
  voxgig_release(resolved);
  if (cinj != inj)
    voxgig_inj_free(cinj);

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
      {"any", VOXGIG_T_ANY},           {"nil", VOXGIG_T_NOVAL},
      {"boolean", VOXGIG_T_BOOLEAN},   {"decimal", VOXGIG_T_DECIMAL},
      {"integer", VOXGIG_T_INTEGER},   {"number", VOXGIG_T_NUMBER},
      {"string", VOXGIG_T_STRING},     {"function", VOXGIG_T_FUNCTION},
      {"symbol", VOXGIG_T_SYMBOL},     {"null", VOXGIG_T_NULL},
      {"list", VOXGIG_T_LIST},         {"map", VOXGIG_T_MAP},
      {"instance", VOXGIG_T_INSTANCE}, {"scalar", VOXGIG_T_SCALAR},
      {"node", VOXGIG_T_NODE},
  };
  for (size_t i = 0; i < sizeof(TABLE) / sizeof(TABLE[0]); i++) {
    if (strcmp(TABLE[i].name, tname) == 0)
      return TABLE[i].bit;
  }
  return 0;
}

static voxgig_value* va_STRING(voxgig_injection* inj, voxgig_value* val, const char* ref,
                               voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  voxgig_value* keyv = voxgig_new_string(inj->key);
  voxgig_value* tmp = voxgig_lookup(inj->dparent, keyv);
  voxgig_value* out = tmp ? voxgig_retain(tmp) : voxgig_new_undef();
  voxgig_release(keyv);
  int t = voxgig_typify(out);
  if ((t & VOXGIG_T_STRING) == 0) {
    voxgig_value* msg = _invalid_type_msg(&inj->path, "string", t, out);
    voxgig_list_push(voxgig_as_list(inj->errs), msg);
    voxgig_release(out);
    return voxgig_new_undef();
  }
  if (voxgig_string_len(out) == 0) {
    /* Build "Empty string at <path>" message. */
    voxgig_value* lst = voxgig_new_list();
    for (size_t i = 1; i < inj->path.len; i++)
      voxgig_list_push(voxgig_as_list(lst), voxgig_new_string(inj->path.data[i]));
    char* p = voxgig_pathify(lst, 0, 0);
    voxgig_release(lst);
    char buf[512];
    snprintf(buf, sizeof(buf), "Empty string at %s", p);
    free(p);
    voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string(buf));
    voxgig_release(out);
    return voxgig_new_undef();
  }
  return out;
}

static voxgig_value* va_TYPE(voxgig_injection* inj, voxgig_value* val, const char* ref,
                             voxgig_value* store, void* ud) {
  (void)val;
  (void)store;
  (void)ud;
  /* tname = ref[1..].toLowerCase() */
  if (!ref || ref[0] != '$')
    return voxgig_new_undef();
  char tname[32];
  size_t rl = strlen(ref);
  size_t cp = rl - 1;
  if (cp >= sizeof(tname))
    cp = sizeof(tname) - 1;
  for (size_t i = 0; i < cp; i++)
    tname[i] = (char)tolower((unsigned char)ref[1 + i]);
  tname[cp] = '\0';
  int typev = typename_to_bit(tname);
  voxgig_value* keyv = voxgig_new_string(inj->key);
  voxgig_value* tmp = voxgig_lookup(inj->dparent, keyv);
  voxgig_value* out = tmp ? voxgig_retain(tmp) : voxgig_new_undef();
  voxgig_release(keyv);
  int t = voxgig_typify(out);
  if ((t & typev) == 0) {
    voxgig_value* msg = _invalid_type_msg(&inj->path, tname, t, out);
    voxgig_list_push(voxgig_as_list(inj->errs), msg);
    voxgig_release(out);
    return voxgig_new_undef();
  }
  return out;
}

static voxgig_value* va_ANY(voxgig_injection* inj, voxgig_value* val, const char* ref,
                            voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  voxgig_value* keyv = voxgig_new_string(inj->key);
  voxgig_value* tmp = voxgig_lookup(inj->dparent, keyv);
  voxgig_value* out = tmp ? voxgig_retain(tmp) : voxgig_new_undef();
  voxgig_release(keyv);
  return out;
}

static voxgig_value* va_CHILD(voxgig_injection* inj, voxgig_value* val, const char* ref,
                              voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  if (inj->mode == VOXGIG_M_KEYPRE) {
    voxgig_value* keyv = voxgig_new_string(inj->key);
    voxgig_value* childtm = voxgig_getprop(inj->parent, keyv, NULL);
    voxgig_release(keyv);
    const char* pkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
    voxgig_value* pkv = voxgig_new_string(pkey);
    voxgig_value* tval = voxgig_getprop(inj->dparent, pkv, NULL);
    voxgig_release(pkv);
    bool tval_undef = voxgig_is_undef(tval) || voxgig_is_null(tval);
    if (tval_undef) {
      voxgig_release(tval);
      tval = voxgig_new_map();
    } else if (!voxgig_is_map(tval)) {
      /* error */
      voxgig_value* msg = _invalid_type_msg(&inj->path, "object", voxgig_typify(tval), tval);
      voxgig_list_push(voxgig_as_list(inj->errs), msg);
      voxgig_release(tval);
      voxgig_release(childtm);
      return voxgig_new_undef();
    }
    voxgig_strvec ckeys = voxgig_keysof(tval);
    for (size_t i = 0; i < ckeys.len; i++) {
      voxgig_value* ckv = voxgig_new_string(ckeys.data[i]);
      voxgig_setprop(inj->parent, ckv, voxgig_clone(childtm));
      voxgig_release(ckv);
      voxgig_strvec_push(&inj->keys, ckeys.data[i]);
    }
    voxgig_strvec_free(&ckeys);
    voxgig_inj_setval(inj, NULL, 0);
    voxgig_release(tval);
    voxgig_release(childtm);
    return voxgig_new_undef();
  }
  if (inj->mode == VOXGIG_M_VAL) {
    if (!voxgig_is_list(inj->parent)) {
      voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string("Invalid $CHILD as value"));
      return voxgig_new_undef();
    }
    voxgig_value* one = voxgig_new_int(1);
    voxgig_value* childtm = voxgig_getprop(inj->parent, one, NULL);
    voxgig_release(one);
    if (!inj->dparent || voxgig_is_undef(inj->dparent)) {
      /* Empty list as default. */
      voxgig_value* nul = NULL;
      voxgig_value* empty = voxgig_new_list();
      (void)nul;
      /* slice(parent, 0, 0, true) — clear parent list. */
      if (voxgig_is_list(inj->parent))
        voxgig_list_clear(voxgig_as_list(inj->parent));
      voxgig_release(empty);
      voxgig_release(childtm);
      return voxgig_new_undef();
    }
    if (!voxgig_is_list(inj->dparent)) {
      voxgig_value* msg =
          _invalid_type_msg(&inj->path, "list", voxgig_typify(inj->dparent), inj->dparent);
      voxgig_list_push(voxgig_as_list(inj->errs), msg);
      inj->keyI = voxgig_list_len(voxgig_as_list(inj->parent));
      voxgig_release(childtm);
      return inj->dparent ? voxgig_retain(inj->dparent) : voxgig_new_undef();
    }
    /* Clone childtm into parent for each item. */
    voxgig_list* dl = voxgig_as_list(inj->dparent);
    voxgig_list_clear(voxgig_as_list(inj->parent));
    for (size_t i = 0; i < dl->len; i++) {
      voxgig_list_push(voxgig_as_list(inj->parent), voxgig_clone(childtm));
    }
    inj->keyI = 0;
    voxgig_release(childtm);
    return dl->len > 0 ? voxgig_retain(dl->items[0]) : voxgig_new_undef();
  }
  return voxgig_new_undef();
}

/* Forward decl for use in ONE / select. */
voxgig_value* voxgig_validate(voxgig_value* data, voxgig_value* spec, voxgig_injection* injdef);

static voxgig_value* va_ONE(voxgig_injection* inj, voxgig_value* val, const char* ref,
                            voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (inj->mode != VOXGIG_M_VAL)
    return voxgig_new_undef();
  if (!voxgig_is_list(inj->parent) || inj->keyI != 0) {
    /* Build path string. */
    voxgig_value* lst = voxgig_new_list();
    for (size_t i = 1; i + 1 < inj->path.len; i++)
      voxgig_list_push(voxgig_as_list(lst), voxgig_new_string(inj->path.data[i]));
    char* ps = voxgig_pathify(lst, 0, 0);
    voxgig_release(lst);
    char buf[512];
    snprintf(buf, sizeof(buf),
             "The $ONE validator at field %s must be the first element of an array.", ps);
    free(ps);
    voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string(buf));
    return voxgig_new_undef();
  }
  inj->keyI = inj->keys.len;
  voxgig_inj_setval(inj, inj->dparent, 2);

  /* slice path to drop last. */
  if (inj->path.len > 0) {
    free(inj->path.data[inj->path.len - 1]);
    inj->path.len--;
  }
  free(inj->key);
  inj->key = inj->path.len > 0 ? xstrdup_t(inj->path.data[inj->path.len - 1]) : xstrdup_t("");

  voxgig_list* pl = voxgig_as_list(inj->parent);
  voxgig_value* tvals = voxgig_new_list();
  for (size_t i = 1; i < pl->len; i++)
    voxgig_list_push(voxgig_as_list(tvals), voxgig_retain(pl->items[i]));
  if (voxgig_list_len(voxgig_as_list(tvals)) == 0) {
    voxgig_value* lst = voxgig_new_list();
    for (size_t i = 1; i + 1 < inj->path.len; i++)
      voxgig_list_push(voxgig_as_list(lst), voxgig_new_string(inj->path.data[i]));
    char* ps = voxgig_pathify(lst, 0, 0);
    voxgig_release(lst);
    char buf[512];
    snprintf(buf, sizeof(buf), "The $ONE validator at field %s must have at least one argument.",
             ps);
    free(ps);
    voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string(buf));
    voxgig_release(tvals);
    return voxgig_new_undef();
  }

  voxgig_list* tvl = voxgig_as_list(tvals);
  for (size_t i = 0; i < tvl->len; i++) {
    voxgig_value* tval = tvl->items[i];
    /* vstore = merge([{}, store], 1); vstore.$TOP = inj.dparent */
    voxgig_value* mlist = voxgig_new_list();
    voxgig_list_push(voxgig_as_list(mlist), voxgig_new_map());
    voxgig_list_push(voxgig_as_list(mlist), voxgig_retain(store));
    voxgig_value* vstore = voxgig_merge(mlist, 1);
    voxgig_release(mlist);
    voxgig_map_set(voxgig_as_map(vstore), "$TOP",
                   inj->dparent ? voxgig_retain(inj->dparent) : voxgig_new_undef());

    voxgig_injection* sub = voxgig_inj_new(NULL, NULL);
    sub->extra = vstore;
    sub->errs = voxgig_new_list();
    sub->meta = voxgig_retain(inj->meta);
    voxgig_value* vcurrent = voxgig_validate(inj->dparent, tval, sub);
    voxgig_inj_setval(inj, vcurrent, -2);
    voxgig_release(vcurrent);

    size_t terrlen = voxgig_list_len(voxgig_as_list(sub->errs));
    voxgig_inj_free(sub);
    voxgig_release(vstore);
    if (terrlen == 0) {
      voxgig_release(tvals);
      return voxgig_new_undef();
    }
  }
  /* All failed: build "one of <vals>" needtype and push V0210-style msg. */
  size_t tvc = voxgig_list_len(voxgig_as_list(tvals));
  char needtype[1024];
  needtype[0] = '\0';
  if (tvc > 1)
    strcat(needtype, "one of ");
  bool first_tv = true;
  voxgig_list* tvl_ = voxgig_as_list(tvals);
  for (size_t i = 0; i < tvl_->len; i++) {
    char* s = voxgig_stringify(tvl_->items[i], -1);
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
  voxgig_value* msg =
      _invalid_type_msg(&inj->path, needtype, voxgig_typify(inj->dparent), inj->dparent);
  voxgig_list_push(voxgig_as_list(inj->errs), msg);
  voxgig_release(tvals);
  return voxgig_new_undef();
}

static voxgig_value* va_EXACT(voxgig_injection* inj, voxgig_value* val, const char* ref,
                              voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  if (inj->mode != VOXGIG_M_VAL) {
    voxgig_value* keyv = voxgig_new_string(inj->key);
    voxgig_delprop(inj->parent, keyv);
    voxgig_release(keyv);
    return voxgig_new_undef();
  }
  if (!voxgig_is_list(inj->parent) || inj->keyI != 0) {
    voxgig_list_push(voxgig_as_list(inj->errs),
                     voxgig_new_string("$EXACT must be first element of array."));
    return voxgig_new_undef();
  }
  inj->keyI = inj->keys.len;
  voxgig_inj_setval(inj, inj->dparent, 2);
  if (inj->path.len > 0) {
    free(inj->path.data[inj->path.len - 1]);
    inj->path.len--;
  }
  free(inj->key);
  inj->key = inj->path.len > 0 ? xstrdup_t(inj->path.data[inj->path.len - 1]) : xstrdup_t("");
  voxgig_list* pl = voxgig_as_list(inj->parent);
  if (pl->len <= 1) {
    voxgig_list_push(voxgig_as_list(inj->errs),
                     voxgig_new_string("$EXACT must have at least one argument."));
    return voxgig_new_undef();
  }
  char* curstr = NULL;
  for (size_t i = 1; i < pl->len; i++) {
    voxgig_value* tval = pl->items[i];
    bool match = voxgig_equals(tval, inj->dparent);
    if (!match && voxgig_is_node(tval)) {
      if (!curstr)
        curstr = voxgig_stringify(inj->dparent, -1);
      char* tvs = voxgig_stringify(tval, -1);
      if (strcmp(tvs, curstr) == 0)
        match = true;
      free(tvs);
    }
    if (match) {
      free(curstr);
      return voxgig_new_undef();
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
    char* s = voxgig_stringify(pl->items[i], -1);
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
  voxgig_value* msg =
      _invalid_type_msg(&inj->path, needtype, voxgig_typify(inj->dparent), inj->dparent);
  voxgig_list_push(voxgig_as_list(inj->errs), msg);
  return voxgig_new_undef();
}

/* ===========================================================================
 * Validation modifier
 * ===========================================================================*/

static void _validation(voxgig_value* pval, voxgig_value* key, voxgig_value* parent,
                        voxgig_injection* inj, voxgig_value* store, void* ud) {
  (void)store;
  (void)ud;
  if (!inj)
    return;
  if (pval && voxgig_is_skip(pval))
    return;

  /* exact = inj.meta[`$EXACT`] */
  voxgig_value* bex = voxgig_new_string("`$EXACT`");
  voxgig_value* exv = voxgig_getprop(inj->meta, bex, NULL);
  voxgig_release(bex);
  bool exact = voxgig_is_bool(exv) && voxgig_as_bool(exv);
  voxgig_release(exv);

  voxgig_value* cp = voxgig_lookup(inj->dparent, key);
  voxgig_value* cval = cp ? voxgig_retain(cp) : voxgig_new_undef();
  bool cval_undef = !cval || voxgig_is_undef(cval);
  if (!exact && cval_undef) {
    voxgig_release(cval);
    return;
  }

  int ptype = voxgig_typify(pval);
  /* Skip if pval is a residual command string. */
  if ((ptype & VOXGIG_T_STRING) && pval && strchr(voxgig_as_string(pval), '$')) {
    voxgig_release(cval);
    return;
  }
  int ctype = voxgig_typify(cval);
  if (ptype != ctype && pval && !voxgig_is_undef(pval)) {
    voxgig_value* msg = _invalid_type_msg(&inj->path, voxgig_typename(ptype), ctype, cval);
    voxgig_list_push(voxgig_as_list(inj->errs), msg);
    voxgig_release(cval);
    return;
  }

  if (voxgig_is_map(cval)) {
    if (!voxgig_is_map(pval)) {
      voxgig_value* msg = _invalid_type_msg(&inj->path, voxgig_typename(ptype), ctype, cval);
      voxgig_list_push(voxgig_as_list(inj->errs), msg);
      voxgig_release(cval);
      return;
    }
    voxgig_strvec ckeys = voxgig_keysof(cval);
    voxgig_strvec pkeys = voxgig_keysof(pval);
    voxgig_value* bopen = voxgig_new_string("`$OPEN`");
    voxgig_value* openv = voxgig_getprop(pval, bopen, NULL);
    bool is_open = voxgig_is_bool(openv) && voxgig_as_bool(openv);
    voxgig_release(openv);
    if (pkeys.len > 0 && !is_open) {
      /* Closed object: gather badkeys. */
      char buf[4096];
      buf[0] = '\0';
      bool first = true;
      for (size_t i = 0; i < ckeys.len; i++) {
        voxgig_value* kv = voxgig_new_string(ckeys.data[i]);
        /* Literal presence: _validation needs to know if the SHAPE declares
           this key, regardless of whether validator stored null in the slot.
           Group A's haskey would miss null-valued slots. */
        bool has = voxgig_lookup(pval, kv) != NULL;
        voxgig_release(kv);
        if (!has) {
          if (!first)
            strcat(buf, ", ");
          strcat(buf, ckeys.data[i]);
          first = false;
        }
      }
      if (buf[0] != '\0') {
        voxgig_value* lst = voxgig_new_list();
        for (size_t i = 1; i < inj->path.len; i++)
          voxgig_list_push(voxgig_as_list(lst), voxgig_new_string(inj->path.data[i]));
        char* ps = voxgig_pathify(lst, 0, 0);
        voxgig_release(lst);
        char full[4500];
        snprintf(full, sizeof(full), "Unexpected keys at field %s: %s", ps, buf);
        free(ps);
        voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string(full));
      }
    } else {
      /* Open: merge cval into pval. */
      voxgig_value* ml = voxgig_new_list();
      voxgig_list_push(voxgig_as_list(ml), voxgig_retain(pval));
      voxgig_list_push(voxgig_as_list(ml), voxgig_retain(cval));
      voxgig_value* m = voxgig_merge(ml, VOXGIG_MAXDEPTH);
      voxgig_release(ml);
      voxgig_release(m);
      if (voxgig_is_node(pval))
        voxgig_delprop(pval, bopen);
    }
    voxgig_release(bopen);
    voxgig_strvec_free(&ckeys);
    voxgig_strvec_free(&pkeys);
  } else if (voxgig_is_list(cval)) {
    if (!voxgig_is_list(pval)) {
      voxgig_value* msg = _invalid_type_msg(&inj->path, voxgig_typename(ptype), ctype, cval);
      voxgig_list_push(voxgig_as_list(inj->errs), msg);
    }
  } else if (exact) {
    if (!voxgig_equals(cval, pval)) {
      voxgig_value* lst = voxgig_new_list();
      for (size_t i = 1; i < inj->path.len; i++)
        voxgig_list_push(voxgig_as_list(lst), voxgig_new_string(inj->path.data[i]));
      char* ps = voxgig_pathify(lst, 0, 0);
      voxgig_release(lst);
      char* cs = voxgig_stringify(cval, -1);
      char* psv = voxgig_stringify(pval, -1);
      size_t bufsz = strlen(ps) + strlen(cs) + strlen(psv) + 64;
      char* buf = (char*)malloc(bufsz);
      if (inj->path.len > 1)
        snprintf(buf, bufsz, "Value at field %s: %s should equal %s.", ps, cs, psv);
      else
        snprintf(buf, bufsz, "Value %s should equal %s.", cs, psv);
      voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string(buf));
      free(buf);
      free(ps);
      free(cs);
      free(psv);
    }
  } else {
    /* Spec value is a default; copy data over. */
    voxgig_setprop(parent, key, cval);
  }
  voxgig_release(cval);
}

/* ===========================================================================
 * Validate handler (R_META_PATH detection)
 * ===========================================================================*/

static voxgig_value* voxgig_validatehandler(voxgig_injection* inj, voxgig_value* val,
                                            const char* ref, voxgig_value* store, void* ud) {
  (void)store;
  (void)ud;
  if (ref) {
    const char* dol = strchr(ref, '$');
    if (dol && dol != ref && (dol[1] == '=' || dol[1] == '~') && dol[2] != '\0') {
      char sep = dol[1];
      if (sep == '=') {
        voxgig_value* pair = voxgig_new_list();
        voxgig_list_push(voxgig_as_list(pair), voxgig_new_string("`$EXACT`"));
        voxgig_list_push(voxgig_as_list(pair), val ? voxgig_retain(val) : voxgig_new_undef());
        voxgig_inj_setval(inj, pair, 0);
        voxgig_release(pair);
      } else {
        voxgig_inj_setval(inj, val, 0);
      }
      inj->keyI = 0;
      inj->keyI_neg = true;
      return voxgig_new_skip();
    }
  }
  /* Delegate to inject-handler. */
  voxgig_value* out = val ? voxgig_retain(val) : voxgig_new_undef();
  bool iscmd = voxgig_is_injector(val) && (ref == NULL || ref[0] == '$');
  if (iscmd) {
    voxgig_release(out);
    out = val->as.fn.fn.inj(inj, val, ref, store, val->as.fn.ud);
  } else if (inj->mode == VOXGIG_M_VAL && inj->full) {
    voxgig_inj_setval(inj, val, 0);
  }
  return out;
}

/* Spec wrapper (returns origspec). */
static voxgig_value* spec_fn_impl(voxgig_injection* inj, voxgig_value* val, const char* ref,
                                  voxgig_value* store, void* ud) {
  (void)inj;
  (void)val;
  (void)ref;
  (void)store;
  return voxgig_retain((voxgig_value*)ud);
}

/* $BT / $DS / $WHEN runtime helpers (returned via store as injector calls). */
static voxgig_value* tx_BT(voxgig_injection* inj, voxgig_value* val, const char* ref,
                           voxgig_value* store, void* ud) {
  (void)inj;
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  return voxgig_new_string("`");
}
static voxgig_value* tx_DS(voxgig_injection* inj, voxgig_value* val, const char* ref,
                           voxgig_value* store, void* ud) {
  (void)inj;
  (void)val;
  (void)ref;
  (void)store;
  (void)ud;
  return voxgig_new_string("$");
}
static voxgig_value* tx_WHEN(voxgig_injection* inj, voxgig_value* val, const char* ref,
                             voxgig_value* store, void* ud) {
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
  return voxgig_new_string(buf);
}

/* ===========================================================================
 * transform
 * ===========================================================================*/

voxgig_value* voxgig_transform(voxgig_value* data, voxgig_value* spec, voxgig_injection* injdef) {
  voxgig_value* origspec = spec;
  voxgig_value* spec_clone = voxgig_clone(spec);

  voxgig_value* errs = NULL;
  bool collect = false;
  voxgig_value* injdef_modify = NULL;
  voxgig_value* injdef_handler = NULL;
  voxgig_value* injdef_meta = NULL;
  voxgig_value* injdef_extra = NULL;

  if (injdef) {
    if (injdef->errs) {
      errs = voxgig_retain(injdef->errs);
      collect = true;
    }
    if (injdef->modify_val)
      injdef_modify = voxgig_retain(injdef->modify_val);
    if (injdef->handler_val)
      injdef_handler = voxgig_retain(injdef->handler_val);
    if (injdef->meta)
      injdef_meta = voxgig_retain(injdef->meta);
    if (injdef->extra)
      injdef_extra = injdef->extra; /* borrowed */
  }
  if (!errs)
    errs = voxgig_new_list();

  /* extra split into extraTransforms (keys starting with $) and extraData. */
  voxgig_value* extraTransforms = voxgig_new_map();
  voxgig_value* extraData = voxgig_new_map();
  if (injdef_extra && voxgig_is_map(injdef_extra)) {
    voxgig_map* em = voxgig_as_map(injdef_extra);
    for (size_t i = 0; i < em->len; i++) {
      const char* k = em->entries[i].key;
      voxgig_value* v = em->entries[i].value;
      if (k[0] == '$')
        voxgig_map_set(voxgig_as_map(extraTransforms), k, voxgig_retain(v));
      else
        voxgig_map_set(voxgig_as_map(extraData), k, voxgig_retain(v));
    }
  }

  /* dataClone = merge([extraData (or undef if empty), clone(data)]) */
  voxgig_value* ml = voxgig_new_list();
  if (!voxgig_isempty(extraData))
    voxgig_list_push(voxgig_as_list(ml), voxgig_clone(extraData));
  voxgig_list_push(voxgig_as_list(ml), voxgig_clone(data));
  voxgig_value* dataClone = voxgig_merge(ml, VOXGIG_MAXDEPTH);
  voxgig_release(ml);

  /* Build store. */
  voxgig_value* builtins = voxgig_new_map();
  voxgig_map_set(voxgig_as_map(builtins), "$TOP", dataClone);
  /* $SPEC closure */
  voxgig_value* spec_fn = voxgig_new_injector(spec_fn_impl, origspec);
  voxgig_map_set(voxgig_as_map(builtins), "$SPEC", spec_fn);
  voxgig_map_set(voxgig_as_map(builtins), "$BT", voxgig_new_injector(tx_BT, NULL));
  voxgig_map_set(voxgig_as_map(builtins), "$DS", voxgig_new_injector(tx_DS, NULL));
  voxgig_map_set(voxgig_as_map(builtins), "$WHEN", voxgig_new_injector(tx_WHEN, NULL));
  voxgig_map_set(voxgig_as_map(builtins), "$DELETE", voxgig_new_injector(tx_DELETE, NULL));
  voxgig_map_set(voxgig_as_map(builtins), "$COPY", voxgig_new_injector(tx_COPY, NULL));
  voxgig_map_set(voxgig_as_map(builtins), "$KEY", voxgig_new_injector(tx_KEY, NULL));
  voxgig_map_set(voxgig_as_map(builtins), "$ANNO", voxgig_new_injector(tx_ANNO, NULL));
  voxgig_map_set(voxgig_as_map(builtins), "$MERGE", voxgig_new_injector(tx_MERGE, NULL));
  voxgig_map_set(voxgig_as_map(builtins), "$EACH", voxgig_new_injector(tx_EACH, NULL));
  voxgig_map_set(voxgig_as_map(builtins), "$PACK", voxgig_new_injector(tx_PACK, NULL));
  voxgig_map_set(voxgig_as_map(builtins), "$REF", voxgig_new_injector(tx_REF, NULL));
  voxgig_map_set(voxgig_as_map(builtins), "$FORMAT", voxgig_new_injector(tx_FORMAT, NULL));
  voxgig_map_set(voxgig_as_map(builtins), "$APPLY", voxgig_new_injector(tx_APPLY, NULL));

  voxgig_value* errwrap = voxgig_new_map();
  voxgig_map_set(voxgig_as_map(errwrap), "$ERRS", voxgig_retain(errs));

  voxgig_value* sml = voxgig_new_list();
  voxgig_list_push(voxgig_as_list(sml), builtins);
  voxgig_list_push(voxgig_as_list(sml), extraTransforms);
  voxgig_list_push(voxgig_as_list(sml), errwrap);
  voxgig_value* store = voxgig_merge(sml, 1);
  voxgig_release(sml);

  /* Pass the (mode=0) config-bag injdef so inject() carries over caller settings
     while initialising as root. */
  voxgig_value* out = voxgig_inject(spec_clone, store, injdef);

  bool generr = voxgig_list_len(voxgig_as_list(errs)) > 0 && !collect;
  if (generr) {
    /* "throw" — emit error to stderr and return undef? In TS, throws.
       For C, write the joined message into errs and abort via a longer-term
       approach. For now, return out and the caller can inspect errs. */
  }

  voxgig_release(spec_clone);
  voxgig_release(store);
  voxgig_release(errs);
  voxgig_release(extraData);
  if (injdef_modify)
    voxgig_release(injdef_modify);
  if (injdef_handler)
    voxgig_release(injdef_handler);
  if (injdef_meta)
    voxgig_release(injdef_meta);

  return out;
}

/* ===========================================================================
 * validate
 * ===========================================================================*/

voxgig_value* voxgig_validate(voxgig_value* data, voxgig_value* spec, voxgig_injection* injdef) {
  voxgig_value* errs = NULL;
  bool collect = false;
  voxgig_value* meta_in = NULL;
  voxgig_value* extra_in = NULL;

  if (injdef) {
    if (injdef->errs) {
      errs = voxgig_retain(injdef->errs);
      collect = true;
    }
    if (injdef->meta)
      meta_in = voxgig_retain(injdef->meta);
    if (injdef->extra)
      extra_in = injdef->extra;
  }
  if (!errs)
    errs = voxgig_new_list();
  if (!meta_in)
    meta_in = voxgig_new_map();

  voxgig_value* bex = voxgig_new_string("`$EXACT`");
  if (!voxgig_haskey(meta_in, bex)) {
    voxgig_map_set(voxgig_as_map(meta_in), "`$EXACT`", voxgig_new_bool(false));
  }
  voxgig_release(bex);

  /* Build validator store. */
  voxgig_value* m1 = voxgig_new_map();
  voxgig_map_set(voxgig_as_map(m1), "$DELETE", voxgig_new_null());
  voxgig_map_set(voxgig_as_map(m1), "$COPY", voxgig_new_null());
  voxgig_map_set(voxgig_as_map(m1), "$KEY", voxgig_new_null());
  voxgig_map_set(voxgig_as_map(m1), "$META", voxgig_new_null());
  voxgig_map_set(voxgig_as_map(m1), "$MERGE", voxgig_new_null());
  voxgig_map_set(voxgig_as_map(m1), "$EACH", voxgig_new_null());
  voxgig_map_set(voxgig_as_map(m1), "$PACK", voxgig_new_null());
  voxgig_map_set(voxgig_as_map(m1), "$STRING", voxgig_new_injector(va_STRING, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$NUMBER", voxgig_new_injector(va_TYPE, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$INTEGER", voxgig_new_injector(va_TYPE, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$DECIMAL", voxgig_new_injector(va_TYPE, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$BOOLEAN", voxgig_new_injector(va_TYPE, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$NULL", voxgig_new_injector(va_TYPE, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$NIL", voxgig_new_injector(va_TYPE, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$MAP", voxgig_new_injector(va_TYPE, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$LIST", voxgig_new_injector(va_TYPE, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$FUNCTION", voxgig_new_injector(va_TYPE, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$INSTANCE", voxgig_new_injector(va_TYPE, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$ANY", voxgig_new_injector(va_ANY, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$CHILD", voxgig_new_injector(va_CHILD, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$ONE", voxgig_new_injector(va_ONE, NULL));
  voxgig_map_set(voxgig_as_map(m1), "$EXACT", voxgig_new_injector(va_EXACT, NULL));

  voxgig_value* ext = extra_in ? voxgig_retain(extra_in) : voxgig_new_map();
  voxgig_value* errwrap = voxgig_new_map();
  voxgig_map_set(voxgig_as_map(errwrap), "$ERRS", voxgig_retain(errs));

  voxgig_value* ml = voxgig_new_list();
  voxgig_list_push(voxgig_as_list(ml), m1);
  voxgig_list_push(voxgig_as_list(ml), ext);
  voxgig_list_push(voxgig_as_list(ml), errwrap);
  voxgig_value* store = voxgig_merge(ml, 1);
  voxgig_release(ml);

  /* Wire up transform with our store / handler / modify. */
  voxgig_injection* sub = voxgig_inj_new(NULL, NULL);
  sub->mode = 0; /* config bag, not mid-recursion */
  voxgig_release(sub->errs);
  sub->errs = voxgig_retain(errs);
  voxgig_release(sub->meta);
  sub->meta = voxgig_retain(meta_in);
  sub->extra = store;
  voxgig_release(sub->modify_val);
  sub->modify_val = voxgig_new_modify(_validation, NULL);
  voxgig_release(sub->handler_val);
  sub->handler_val = voxgig_new_injector(voxgig_validatehandler, NULL);

  voxgig_value* out = voxgig_transform(data, spec, sub);

  bool generr = voxgig_list_len(voxgig_as_list(errs)) > 0 && !collect;
  (void)generr; /* Same as transform: keep errs accessible. */

  voxgig_inj_free(sub);
  voxgig_release(store);
  voxgig_release(errs);
  voxgig_release(meta_in);
  return out;
}

/* ===========================================================================
 * Select operators
 * ===========================================================================*/

static voxgig_value* sel_AND(voxgig_injection* inj, voxgig_value* val, const char* ref,
                             voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (inj->mode != VOXGIG_M_KEYPRE)
    return voxgig_new_undef();
  voxgig_value* keyv = voxgig_new_string(inj->key);
  voxgig_value* terms = voxgig_getprop(inj->parent, keyv, NULL);
  voxgig_release(keyv);
  /* ppath = slice(inj.path, -1); point = getpath(store, ppath) */
  voxgig_value* ppath = voxgig_new_list();
  for (size_t i = 0; i + 1 < inj->path.len; i++)
    voxgig_list_push(voxgig_as_list(ppath), voxgig_new_string(inj->path.data[i]));
  voxgig_value* point = voxgig_getpath(store, ppath, NULL);

  voxgig_value* ml = voxgig_new_list();
  voxgig_list_push(voxgig_as_list(ml), voxgig_new_map());
  voxgig_list_push(voxgig_as_list(ml), voxgig_retain(store));
  voxgig_value* vstore = voxgig_merge(ml, 1);
  voxgig_release(ml);
  voxgig_map_set(voxgig_as_map(vstore), "$TOP", voxgig_retain(point));

  if (voxgig_is_list(terms)) {
    voxgig_list* tl = voxgig_as_list(terms);
    for (size_t i = 0; i < tl->len; i++) {
      voxgig_value* term = tl->items[i];
      voxgig_injection* sub = voxgig_inj_new(NULL, NULL);
      sub->extra = vstore;
      voxgig_release(sub->errs);
      sub->errs = voxgig_new_list();
      voxgig_release(sub->meta);
      sub->meta = voxgig_retain(inj->meta);
      voxgig_value* out = voxgig_validate(point, term, sub);
      voxgig_release(out);
      if (voxgig_list_len(voxgig_as_list(sub->errs)) > 0) {
        voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string("AND failed"));
      }
      voxgig_inj_free(sub);
    }
  }
  /* setprop(grandparent, gkey, point) */
  const char* gkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  voxgig_value* gp = inj->nodes_len >= 2 ? inj->nodes[inj->nodes_len - 2] : NULL;
  voxgig_value* gkv = voxgig_new_string(gkey);
  if (gp)
    voxgig_setprop(gp, gkv, point);
  voxgig_release(gkv);

  voxgig_release(terms);
  voxgig_release(ppath);
  voxgig_release(point);
  voxgig_release(vstore);
  return voxgig_new_undef();
}

static voxgig_value* sel_OR(voxgig_injection* inj, voxgig_value* val, const char* ref,
                            voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (inj->mode != VOXGIG_M_KEYPRE)
    return voxgig_new_undef();
  voxgig_value* keyv = voxgig_new_string(inj->key);
  voxgig_value* terms = voxgig_getprop(inj->parent, keyv, NULL);
  voxgig_release(keyv);
  voxgig_value* ppath = voxgig_new_list();
  for (size_t i = 0; i + 1 < inj->path.len; i++)
    voxgig_list_push(voxgig_as_list(ppath), voxgig_new_string(inj->path.data[i]));
  voxgig_value* point = voxgig_getpath(store, ppath, NULL);

  voxgig_value* ml = voxgig_new_list();
  voxgig_list_push(voxgig_as_list(ml), voxgig_new_map());
  voxgig_list_push(voxgig_as_list(ml), voxgig_retain(store));
  voxgig_value* vstore = voxgig_merge(ml, 1);
  voxgig_release(ml);
  voxgig_map_set(voxgig_as_map(vstore), "$TOP", voxgig_retain(point));

  bool any_ok = false;
  if (voxgig_is_list(terms)) {
    voxgig_list* tl = voxgig_as_list(terms);
    for (size_t i = 0; i < tl->len; i++) {
      voxgig_value* term = tl->items[i];
      voxgig_injection* sub = voxgig_inj_new(NULL, NULL);
      sub->extra = vstore;
      voxgig_release(sub->errs);
      sub->errs = voxgig_new_list();
      voxgig_release(sub->meta);
      sub->meta = voxgig_retain(inj->meta);
      voxgig_value* out = voxgig_validate(point, term, sub);
      voxgig_release(out);
      if (voxgig_list_len(voxgig_as_list(sub->errs)) == 0) {
        any_ok = true;
        voxgig_inj_free(sub);
        break;
      }
      voxgig_inj_free(sub);
    }
  }
  if (any_ok) {
    const char* gkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
    voxgig_value* gp = inj->nodes_len >= 2 ? inj->nodes[inj->nodes_len - 2] : NULL;
    voxgig_value* gkv = voxgig_new_string(gkey);
    if (gp)
      voxgig_setprop(gp, gkv, point);
    voxgig_release(gkv);
  } else {
    voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string("OR failed"));
  }
  voxgig_release(terms);
  voxgig_release(ppath);
  voxgig_release(point);
  voxgig_release(vstore);
  return voxgig_new_undef();
}

static voxgig_value* sel_NOT(voxgig_injection* inj, voxgig_value* val, const char* ref,
                             voxgig_value* store, void* ud) {
  (void)val;
  (void)ref;
  (void)ud;
  if (inj->mode != VOXGIG_M_KEYPRE)
    return voxgig_new_undef();
  voxgig_value* keyv = voxgig_new_string(inj->key);
  voxgig_value* term = voxgig_getprop(inj->parent, keyv, NULL);
  voxgig_release(keyv);
  voxgig_value* ppath = voxgig_new_list();
  for (size_t i = 0; i + 1 < inj->path.len; i++)
    voxgig_list_push(voxgig_as_list(ppath), voxgig_new_string(inj->path.data[i]));
  voxgig_value* point = voxgig_getpath(store, ppath, NULL);

  voxgig_value* ml = voxgig_new_list();
  voxgig_list_push(voxgig_as_list(ml), voxgig_new_map());
  voxgig_list_push(voxgig_as_list(ml), voxgig_retain(store));
  voxgig_value* vstore = voxgig_merge(ml, 1);
  voxgig_release(ml);
  voxgig_map_set(voxgig_as_map(vstore), "$TOP", voxgig_retain(point));

  voxgig_injection* sub = voxgig_inj_new(NULL, NULL);
  sub->extra = vstore;
  voxgig_release(sub->errs);
  sub->errs = voxgig_new_list();
  voxgig_release(sub->meta);
  sub->meta = voxgig_retain(inj->meta);
  voxgig_value* out = voxgig_validate(point, term, sub);
  voxgig_release(out);
  if (voxgig_list_len(voxgig_as_list(sub->errs)) == 0) {
    voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string("NOT failed"));
  }
  voxgig_inj_free(sub);

  const char* gkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  voxgig_value* gp = inj->nodes_len >= 2 ? inj->nodes[inj->nodes_len - 2] : NULL;
  voxgig_value* gkv = voxgig_new_string(gkey);
  if (gp)
    voxgig_setprop(gp, gkv, point);
  voxgig_release(gkv);

  voxgig_release(term);
  voxgig_release(ppath);
  voxgig_release(point);
  voxgig_release(vstore);
  return voxgig_new_undef();
}

static int cmp_values(voxgig_value* a, voxgig_value* b) {
  if (voxgig_is_number(a) && voxgig_is_number(b)) {
    double da = voxgig_as_double(a);
    double db = voxgig_as_double(b);
    if (da < db)
      return -1;
    if (da > db)
      return 1;
    return 0;
  }
  if (voxgig_is_string(a) && voxgig_is_string(b))
    return strcmp(voxgig_as_string(a), voxgig_as_string(b));
  /* Fallback: stringify. */
  char* sa = voxgig_stringify(a, -1);
  char* sb = voxgig_stringify(b, -1);
  int r = strcmp(sa, sb);
  free(sa);
  free(sb);
  return r;
}

static voxgig_value* sel_CMP(voxgig_injection* inj, voxgig_value* val, const char* ref,
                             voxgig_value* store, void* ud) {
  (void)val;
  (void)ud;
  if (inj->mode != VOXGIG_M_KEYPRE)
    return voxgig_new_undef();
  voxgig_value* keyv = voxgig_new_string(inj->key);
  voxgig_value* term = voxgig_getprop(inj->parent, keyv, NULL);
  voxgig_release(keyv);
  voxgig_value* ppath = voxgig_new_list();
  for (size_t i = 0; i + 1 < inj->path.len; i++)
    voxgig_list_push(voxgig_as_list(ppath), voxgig_new_string(inj->path.data[i]));
  voxgig_value* point = voxgig_getpath(store, ppath, NULL);

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
    char* ps = voxgig_stringify(point, -1);
    const char* termstr = voxgig_is_string(term) ? voxgig_as_string(term) : "";
    pass = voxgig_re_test(termstr, ps);
    free(ps);
  }
  const char* gkey = inj->path.len >= 2 ? inj->path.data[inj->path.len - 2] : "";
  voxgig_value* gp = inj->nodes_len >= 2 ? inj->nodes[inj->nodes_len - 2] : NULL;
  voxgig_value* gkv = voxgig_new_string(gkey);
  if (pass) {
    if (gp)
      voxgig_setprop(gp, gkv, point);
  } else {
    char buf[256];
    snprintf(buf, sizeof(buf), "CMP: %s failed", ref);
    voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string(buf));
  }
  voxgig_release(gkv);
  voxgig_release(term);
  voxgig_release(ppath);
  voxgig_release(point);
  return voxgig_new_undef();
}

/* ===========================================================================
 * select
 * ===========================================================================*/

/* walk callback to add `$OPEN` to every map in the query. */
static voxgig_value* set_open_callback(voxgig_value* k, voxgig_value* v, voxgig_value* parent,
                                       voxgig_value* path, void* ud) {
  (void)k;
  (void)parent;
  (void)path;
  (void)ud;
  if (voxgig_is_map(v)) {
    voxgig_value* bk = voxgig_new_string("`$OPEN`");
    if (!voxgig_haskey(v, bk)) {
      voxgig_map_set(voxgig_as_map(v), "`$OPEN`", voxgig_new_bool(true));
    }
    voxgig_release(bk);
  }
  return v ? voxgig_retain(v) : voxgig_new_undef();
}

voxgig_value* voxgig_select(voxgig_value* children, voxgig_value* query) {
  if (!voxgig_is_node(children))
    return voxgig_new_list();

  /* Convert children to list, adding $KEY to each. */
  voxgig_value* child_list = voxgig_new_list();
  if (voxgig_is_map(children)) {
    voxgig_map* m = voxgig_as_map(children);
    for (size_t i = 0; i < m->len; i++) {
      voxgig_value* it = m->entries[i].value;
      if (voxgig_is_map(it)) {
        voxgig_map_set(voxgig_as_map(it), "$KEY", voxgig_new_string(m->entries[i].key));
      }
      voxgig_list_push(voxgig_as_list(child_list), voxgig_retain(it));
    }
  } else {
    voxgig_list* l = voxgig_as_list(children);
    for (size_t i = 0; i < l->len; i++) {
      voxgig_value* it = l->items[i];
      if (voxgig_is_map(it)) {
        voxgig_map_set(voxgig_as_map(it), "$KEY", voxgig_new_int((int64_t)i));
      }
      voxgig_list_push(voxgig_as_list(child_list), voxgig_retain(it));
    }
  }

  /* extra = {$AND:..., $OR:..., $NOT:..., $GT/$LT/$GTE/$LTE/$LIKE:...} */
  voxgig_value* extra = voxgig_new_map();
  voxgig_map_set(voxgig_as_map(extra), "$AND", voxgig_new_injector(sel_AND, NULL));
  voxgig_map_set(voxgig_as_map(extra), "$OR", voxgig_new_injector(sel_OR, NULL));
  voxgig_map_set(voxgig_as_map(extra), "$NOT", voxgig_new_injector(sel_NOT, NULL));
  voxgig_map_set(voxgig_as_map(extra), "$GT", voxgig_new_injector(sel_CMP, NULL));
  voxgig_map_set(voxgig_as_map(extra), "$LT", voxgig_new_injector(sel_CMP, NULL));
  voxgig_map_set(voxgig_as_map(extra), "$GTE", voxgig_new_injector(sel_CMP, NULL));
  voxgig_map_set(voxgig_as_map(extra), "$LTE", voxgig_new_injector(sel_CMP, NULL));
  voxgig_map_set(voxgig_as_map(extra), "$LIKE", voxgig_new_injector(sel_CMP, NULL));

  /* meta = {`$EXACT`: true} */
  voxgig_value* meta = voxgig_new_map();
  voxgig_map_set(voxgig_as_map(meta), "`$EXACT`", voxgig_new_bool(true));

  /* q = clone(query); walk q to set `$OPEN` on every map. */
  voxgig_value* q = voxgig_clone(query);
  voxgig_value* walked = voxgig_walk(q, set_open_callback, NULL, VOXGIG_MAXDEPTH, NULL);
  voxgig_release(walked);

  voxgig_value* results = voxgig_new_list();
  voxgig_list* cl = voxgig_as_list(child_list);
  for (size_t i = 0; i < cl->len; i++) {
    voxgig_value* child = cl->items[i];
    voxgig_injection* sub = voxgig_inj_new(NULL, NULL);
    voxgig_release(sub->errs);
    sub->errs = voxgig_new_list();
    voxgig_release(sub->meta);
    sub->meta = voxgig_retain(meta);
    sub->extra = extra;
    voxgig_value* qc = voxgig_clone(q);
    voxgig_value* out = voxgig_validate(child, qc, sub);
    voxgig_release(out);
    voxgig_release(qc);
    if (voxgig_list_len(voxgig_as_list(sub->errs)) == 0) {
      voxgig_list_push(voxgig_as_list(results), voxgig_retain(child));
    }
    voxgig_inj_free(sub);
  }

  voxgig_release(child_list);
  voxgig_release(extra);
  voxgig_release(meta);
  voxgig_release(q);
  return results;
}
