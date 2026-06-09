/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
 *
 * Injection state machine + inject() + transform/validate/select machinery.
 * Mirrors lines 1190–2500 of ts/src/StructUtility.ts.
 */

#include "voxgig_struct.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Forward declarations of internal helpers from this file. */
static voxgig_value* _injecthandler(voxgig_injection* inj, voxgig_value* val, const char* ref,
                                    voxgig_value* store, void* ud);

/* Static helpers (copied from utility.c style; avoid duplicates by re-defining locally) */
static char* xstrdup_s2(const char* s) {
  if (!s)
    s = "";
  size_t n = strlen(s);
  char* o = (char*)malloc(n + 1);
  if (!o)
    abort();
  memcpy(o, s, n + 1);
  return o;
}

static char* xstrndup_s2(const char* s, size_t n) {
  char* o = (char*)malloc(n + 1);
  if (!o)
    abort();
  if (n)
    memcpy(o, s, n);
  o[n] = '\0';
  return o;
}

/* ===========================================================================
 * Injection state — constructors / destructors / methods
 * ===========================================================================*/

voxgig_injection* voxgig_inj_new(voxgig_value* val, voxgig_value* parent) {
  voxgig_injection* inj = (voxgig_injection*)calloc(1, sizeof(voxgig_injection));
  if (!inj)
    abort();
  inj->val = val ? voxgig_retain(val) : voxgig_new_undef();
  inj->parent = parent ? voxgig_retain(parent) : voxgig_new_undef();
  inj->errs = voxgig_new_list();
  inj->dparent = NULL;
  voxgig_strvec_init(&inj->dpath);
  voxgig_strvec_push(&inj->dpath, "$TOP");
  inj->mode = VOXGIG_M_VAL;
  inj->full = false;
  inj->keyI = 0;
  inj->keyI_neg = false;
  voxgig_strvec_init(&inj->keys);
  voxgig_strvec_push(&inj->keys, "$TOP");
  inj->key = xstrdup_s2("$TOP");
  voxgig_strvec_init(&inj->path);
  voxgig_strvec_push(&inj->path, "$TOP");
  /* nodes stack: borrowed references. */
  inj->nodes_len = 0;
  inj->nodes_cap = 0;
  inj->nodes = NULL;
  voxgig_inj_nodes_push(inj, parent);
  inj->handler_val = voxgig_new_injector(_injecthandler, NULL);
  inj->base = xstrdup_s2("$TOP");
  inj->meta = voxgig_new_map();
  inj->modify_val = NULL;
  inj->prior = NULL;
  inj->extra = NULL;
  return inj;
}

void voxgig_inj_free(voxgig_injection* inj) {
  if (!inj)
    return;
  voxgig_release(inj->val);
  voxgig_release(inj->parent);
  voxgig_strvec_free(&inj->keys);
  free(inj->key);
  voxgig_strvec_free(&inj->path);
  free(inj->nodes);
  voxgig_release(inj->handler_val);
  voxgig_release(inj->errs);
  voxgig_release(inj->meta);
  voxgig_strvec_free(&inj->dpath);
  free(inj->base);
  voxgig_release(inj->modify_val);
  free(inj);
}

void voxgig_inj_nodes_push(voxgig_injection* inj, voxgig_value* n) {
  if (inj->nodes_len + 1 > inj->nodes_cap) {
    size_t nc = inj->nodes_cap == 0 ? 8 : inj->nodes_cap * 2;
    voxgig_value** nn = (voxgig_value**)realloc(inj->nodes, nc * sizeof(voxgig_value*));
    if (!nn)
      abort();
    inj->nodes = nn;
    inj->nodes_cap = nc;
  }
  inj->nodes[inj->nodes_len++] = n;
}

void voxgig_inj_set_path(voxgig_injection* inj, const voxgig_strvec* path) {
  voxgig_strvec_copy(&inj->path, path);
}

void voxgig_inj_set_dpath(voxgig_injection* inj, const voxgig_strvec* path) {
  voxgig_strvec_copy(&inj->dpath, path);
}

void voxgig_inj_descend(voxgig_injection* inj) {
  /* meta.__d++ */
  voxgig_value* d = voxgig_map_get(voxgig_as_map(inj->meta), "__d");
  int64_t dv = (d && voxgig_is_int(d)) ? voxgig_as_int(d) : 0;
  voxgig_map_set(voxgig_as_map(inj->meta), "__d", voxgig_new_int(dv + 1));

  /* parentkey = path[path.length-2] */
  const char* parentkey = NULL;
  if (inj->path.len >= 2)
    parentkey = inj->path.data[inj->path.len - 2];

  if (!inj->dparent || voxgig_is_undef(inj->dparent)) {
    if (inj->dpath.len > 1 && parentkey) {
      voxgig_strvec_push(&inj->dpath, parentkey);
    }
  } else {
    if (parentkey) {
      voxgig_value* k = voxgig_new_string(parentkey);
      voxgig_value* lp = voxgig_lookup(inj->dparent, k);
      voxgig_value* nd = lp ? voxgig_retain(lp) : voxgig_new_undef();
      voxgig_release(k);
      voxgig_release(inj->dparent);
      inj->dparent = nd;
      /* Check dpath last segment. */
      char marker[256];
      snprintf(marker, sizeof(marker), "$:%s", parentkey);
      const char* lastpart = inj->dpath.len ? inj->dpath.data[inj->dpath.len - 1] : "";
      if (strcmp(lastpart, marker) == 0) {
        /* slice(dpath, -1) — drop last element. */
        if (inj->dpath.len > 0) {
          free(inj->dpath.data[inj->dpath.len - 1]);
          inj->dpath.len--;
        }
      } else {
        voxgig_strvec_push(&inj->dpath, parentkey);
      }
    }
  }
}

voxgig_injection* voxgig_inj_child(voxgig_injection* parent, size_t keyI,
                                   const voxgig_strvec* keys) {
  /* key = strkey(keys[keyI]) */
  const char* keystr = (keyI < keys->len) ? keys->data[keyI] : "";
  voxgig_value* keyv = voxgig_new_string(keystr);
  voxgig_value* vp = voxgig_lookup(parent->val, keyv);
  voxgig_value* val = vp ? voxgig_retain(vp) : voxgig_new_undef();
  voxgig_release(keyv);

  voxgig_injection* cinj = (voxgig_injection*)calloc(1, sizeof(voxgig_injection));
  if (!cinj)
    abort();
  cinj->val = val;
  cinj->parent = voxgig_retain(parent->val);
  cinj->errs = voxgig_retain(parent->errs);
  cinj->dparent = parent->dparent ? voxgig_retain(parent->dparent) : voxgig_new_undef();
  voxgig_strvec_init(&cinj->dpath);
  voxgig_strvec_copy(&cinj->dpath, &parent->dpath);
  cinj->mode = parent->mode;
  cinj->full = false;
  cinj->keyI = keyI;
  cinj->keyI_neg = false;
  voxgig_strvec_init(&cinj->keys);
  voxgig_strvec_copy(&cinj->keys, keys);
  cinj->key = xstrdup_s2(keystr);
  voxgig_strvec_init(&cinj->path);
  voxgig_strvec_copy(&cinj->path, &parent->path);
  voxgig_strvec_push(&cinj->path, keystr);
  cinj->nodes_len = 0;
  cinj->nodes_cap = 0;
  cinj->nodes = NULL;
  for (size_t i = 0; i < parent->nodes_len; i++)
    voxgig_inj_nodes_push(cinj, parent->nodes[i]);
  voxgig_inj_nodes_push(cinj, parent->val);
  cinj->handler_val = parent->handler_val ? voxgig_retain(parent->handler_val) : NULL;
  cinj->base = parent->base ? xstrdup_s2(parent->base) : NULL;
  cinj->meta = parent->meta ? voxgig_retain(parent->meta) : voxgig_new_map();
  cinj->modify_val = parent->modify_val ? voxgig_retain(parent->modify_val) : NULL;
  cinj->prior = parent;
  cinj->extra = parent->extra;
  return cinj;
}

voxgig_value* voxgig_inj_setval(voxgig_injection* inj, voxgig_value* val, int ancestor) {
  voxgig_value* target = NULL;
  const char* tkey = NULL;
  if (ancestor < 2) {
    target = inj->parent;
    tkey = inj->key;
  } else {
    /* nodes[-ancestor], path[-ancestor] */
    if (inj->nodes_len < (size_t)ancestor)
      return NULL;
    target = inj->nodes[inj->nodes_len - ancestor];
    if (inj->path.len < (size_t)ancestor)
      return NULL;
    tkey = inj->path.data[inj->path.len - ancestor];
  }
  voxgig_value* keyv = voxgig_new_string(tkey ? tkey : "");
  if (!val || voxgig_is_undef(val)) {
    voxgig_delprop(target, keyv);
  } else {
    voxgig_setprop(target, keyv, val);
  }
  voxgig_release(keyv);
  return target;
}

/* ===========================================================================
 * checkPlacement
 * ===========================================================================*/

bool voxgig_check_placement(int modes, const char* ijname, int parent_types,
                            voxgig_injection* inj) {
  if ((modes & inj->mode) == 0) {
    const char* placement = (inj->mode == VOXGIG_M_VAL) ? "value" : "key";
    /* Build expected list. */
    char expected[64] = "";
    bool first = true;
    if (modes & VOXGIG_M_KEYPRE) {
      if (!first)
        strcat(expected, ",");
      strcat(expected, "key");
      first = false;
    }
    if (modes & VOXGIG_M_KEYPOST) {
      if (!first)
        strcat(expected, ",");
      strcat(expected, "key");
      first = false;
    }
    if (modes & VOXGIG_M_VAL) {
      if (!first)
        strcat(expected, ",");
      strcat(expected, "value");
      first = false;
    }
    char msg[256];
    snprintf(msg, sizeof(msg), "$%s: invalid placement as %s, expected: %s.", ijname, placement,
             expected);
    voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string(msg));
    return false;
  }
  if (parent_types != 0 && parent_types != VOXGIG_T_ANY) {
    int pt = voxgig_typify(inj->parent);
    if ((parent_types & pt) == 0) {
      char msg[256];
      snprintf(msg, sizeof(msg), "$%s: invalid placement in parent %s, expected: %s.", ijname,
               voxgig_typename(pt), voxgig_typename(parent_types));
      voxgig_list_push(voxgig_as_list(inj->errs), voxgig_new_string(msg));
      return false;
    }
  }
  return true;
}

/* ===========================================================================
 * injectorArgs
 * ===========================================================================*/

voxgig_value* voxgig_injector_args(const int* argTypes, size_t n, voxgig_value* args) {
  voxgig_value* found = voxgig_new_list();
  voxgig_list_push(voxgig_as_list(found), voxgig_new_undef()); /* err slot */
  for (size_t i = 0; i < n; i++) {
    voxgig_value* arg = NULL;
    if (voxgig_is_list(args)) {
      arg = voxgig_list_get(voxgig_as_list(args), i);
    }
    int argt = voxgig_typify(arg);
    if ((argTypes[i] & argt) == 0) {
      char* arepr = voxgig_stringify(arg, 22);
      char msg[512];
      snprintf(msg, sizeof(msg), "invalid argument: %s (%s at position %zu) is not of type: %s.",
               arepr, voxgig_typename(argt), 1 + i, voxgig_typename(argTypes[i]));
      free(arepr);
      voxgig_list_set(voxgig_as_list(found), 0, voxgig_new_string(msg));
      return found;
    }
    voxgig_list_push(voxgig_as_list(found), arg ? voxgig_retain(arg) : voxgig_new_undef());
  }
  return found;
}

/* ===========================================================================
 * injectChild
 * ===========================================================================*/

voxgig_injection* voxgig_inject_child(voxgig_value* child, voxgig_value* store,
                                      voxgig_injection* inj) {
  voxgig_injection* cinj = inj;

  /* Replace ['$FORMAT', ...] in parent with child. */
  if (inj->prior) {
    if (inj->prior->prior) {
      cinj = voxgig_inj_child(inj->prior->prior, inj->prior->keyI, &inj->prior->keys);
      voxgig_release(cinj->val);
      cinj->val = child ? voxgig_retain(child) : voxgig_new_undef();
      voxgig_value* keyv = voxgig_new_string(inj->prior->key);
      voxgig_setprop(cinj->parent, keyv, child);
      voxgig_release(keyv);
    } else {
      cinj = voxgig_inj_child(inj->prior, inj->keyI, &inj->keys);
      voxgig_release(cinj->val);
      cinj->val = child ? voxgig_retain(child) : voxgig_new_undef();
      voxgig_value* keyv = voxgig_new_string(inj->key);
      voxgig_setprop(cinj->parent, keyv, child);
      voxgig_release(keyv);
    }
  }

  voxgig_inject(child, store, cinj);
  return cinj;
}

/* ===========================================================================
 * _injectstr
 * ===========================================================================*/

/* R_INJECTION_FULL: ^`(\$[A-Z]+|[^`]*)[0-9]*`$
 * Goes through the vendored regex engine so the call site reads the same as
 * the canonical TS. The captured group is returned via out_pathref. */
static voxgig_regex* R_INJECTION_FULL_re(void) {
  static voxgig_regex* re = NULL;
  if (!re)
    re = voxgig_re_compile("^`(\\$[A-Z]+|[^`]*)[0-9]*`$");
  return re;
}
static bool match_injection_full(const char* val, size_t vlen, char** out_pathref) {
  char buf[256];
  char* tmp = NULL;
  const char* z;
  if (vlen < sizeof(buf)) {
    memcpy(buf, val, vlen);
    buf[vlen] = '\0';
    z = buf;
  } else {
    tmp = (char*)malloc(vlen + 1);
    memcpy(tmp, val, vlen);
    tmp[vlen] = '\0';
    z = tmp;
  }
  voxgig_strvec caps = voxgig_re_find_re(R_INJECTION_FULL_re(), z);
  bool ok = (caps.len >= 2);
  if (ok) {
    *out_pathref = xstrndup_s2(caps.data[1], strlen(caps.data[1]));
  }
  voxgig_strvec_free(&caps);
  free(tmp);
  return ok;
}

/* Apply $BT and $DS escapes. */
static char* apply_escapes(const char* s) {
  char* a = voxgig_replace_str(s, "$BT", "`");
  char* b = voxgig_replace_str(a, "$DS", "$");
  free(a);
  return b;
}

/* _injectstr: returns the new string value (allocated) if it's a partial-style
 * pure-string replacement, OR returns NULL and sets *outv (owned) to the
 * resolved value for full-string injections.
 *
 * If the input is a full injection (entire string is `…`), the result is a
 * value (any type) — we set outv and return NULL.
 *
 * If the input is partial, we return a malloc'd string and outv is NULL.
 *
 * The handler is invoked appropriately.
 */
voxgig_value* voxgig_inject_str_v(const char* val, size_t vlen, voxgig_value* store,
                                  voxgig_injection* inj) {
  if (!val || vlen == 0)
    return voxgig_new_string("");
  char* pathref = NULL;
  if (match_injection_full(val, vlen, &pathref)) {
    if (inj)
      inj->full = true;
    char* eff = pathref;
    char* unescaped = NULL;
    if (strlen(eff) > 3) {
      unescaped = apply_escapes(eff);
      eff = unescaped;
    }
    voxgig_value* p = voxgig_new_string(eff);
    voxgig_value* out = voxgig_getpath(store, p, inj);
    voxgig_release(p);
    free(pathref);
    free(unescaped);
    return out;
  }
  /* Partial injection: find `…` segments and substitute. */
  char* buf = NULL;
  size_t blen = 0, bcap = 0;
  size_t i = 0;
  while (i < vlen) {
    if (val[i] == '`') {
      size_t j = i + 1;
      while (j < vlen && val[j] != '`')
        j++;
      if (j < vlen) {
        /* Extract ref. */
        size_t rlen = j - i - 1;
        char* ref = xstrndup_s2(val + i + 1, rlen);
        char* eff = ref;
        char* unescaped = NULL;
        if (rlen > 3) {
          unescaped = apply_escapes(ref);
          eff = unescaped;
        }
        if (inj)
          inj->full = false;
        voxgig_value* p = voxgig_new_string(eff);
        voxgig_value* found = voxgig_getpath(store, p, inj);
        voxgig_release(p);
        free(unescaped);
        free(ref);
        char* sub;
        if (!found || voxgig_is_undef(found))
          sub = xstrdup_s2("");
        else if (voxgig_is_string(found))
          sub = xstrdup_s2(voxgig_as_string(found));
        else {
          /* JSON.stringify without indent — compact. */
          voxgig_value* flags = voxgig_new_map();
          voxgig_map_set(voxgig_as_map(flags), "indent", voxgig_new_int(0));
          sub = voxgig_jsonify(found, flags);
          voxgig_release(flags);
        }
        size_t slen = strlen(sub);
        if (blen + slen + 1 > bcap) {
          size_t nc = bcap == 0 ? 64 : bcap;
          while (nc < blen + slen + 1)
            nc *= 2;
          buf = (char*)realloc(buf, nc);
          if (!buf)
            abort();
          bcap = nc;
        }
        memcpy(buf + blen, sub, slen);
        blen += slen;
        buf[blen] = '\0';
        free(sub);
        voxgig_release(found);
        i = j + 1;
      } else {
        /* No closing backtick; append literally. */
        if (blen + 1 >= bcap) {
          size_t nc = bcap == 0 ? 64 : bcap * 2;
          buf = (char*)realloc(buf, nc);
          if (!buf)
            abort();
          bcap = nc;
        }
        buf[blen++] = val[i];
        buf[blen] = '\0';
        i++;
      }
    } else {
      if (blen + 1 >= bcap) {
        size_t nc = bcap == 0 ? 64 : bcap * 2;
        buf = (char*)realloc(buf, nc);
        if (!buf)
          abort();
        bcap = nc;
      }
      buf[blen++] = val[i];
      buf[blen] = '\0';
      i++;
    }
  }
  if (!buf)
    buf = xstrdup_s2("");
  /* After replacement, run handler with full=true. */
  voxgig_value* outv = voxgig_new_string(buf);
  free(buf);
  if (inj && inj->handler_val && voxgig_is_func(inj->handler_val)) {
    inj->full = true;
    char* origref = xstrndup_s2(val, vlen);
    voxgig_value* nv =
        inj->handler_val->as.fn.fn.inj(inj, outv, origref, store, inj->handler_val->as.fn.ud);
    free(origref);
    voxgig_release(outv);
    outv = nv;
  }
  return outv;
}

/* ===========================================================================
 * _injecthandler / _validatehandler
 * ===========================================================================*/

static voxgig_value* _injecthandler(voxgig_injection* inj, voxgig_value* val, const char* ref,
                                    voxgig_value* store, void* ud) {
  (void)ud;
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

voxgig_value* voxgig_validatehandler_internal(voxgig_injection* inj, voxgig_value* val,
                                              const char* ref, voxgig_value* store, void* ud);

voxgig_value* voxgig_validatehandler_internal(voxgig_injection* inj, voxgig_value* val,
                                              const char* ref, voxgig_value* store, void* ud) {
  /* Match R_META_PATH: ^([^$]+)\$([=~])(.+)$ */
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
      inj->keyI_neg = true;
      inj->keyI = 0;
      return voxgig_new_skip();
    }
  }
  return _injecthandler(inj, val, ref, store, ud);
}

/* ===========================================================================
 * Main inject() loop
 * ===========================================================================*/

voxgig_value* voxgig_inject(voxgig_value* val, voxgig_value* store, voxgig_injection* injdef) {
  voxgig_injection* inj = injdef;
  /* Root if no injdef, or injdef.mode==0 (config bag). */
  bool root = (injdef == NULL) || (injdef->mode == 0);
  voxgig_injection* allocated_inj = NULL;

  if (root) {
    voxgig_value* holder = voxgig_new_map();
    voxgig_map_set(voxgig_as_map(holder), "$TOP", val ? voxgig_retain(val) : voxgig_new_undef());
    inj = voxgig_inj_new(val, holder);
    voxgig_release(holder);
    allocated_inj = inj;
    inj->dparent = store ? voxgig_retain(store) : voxgig_new_undef();
    /* errs = store.$ERRS or [] */
    voxgig_value* serr = voxgig_map_get(voxgig_as_map(store), "$ERRS");
    if (serr) {
      voxgig_release(inj->errs);
      inj->errs = voxgig_retain(serr);
    }
    /* meta.__d = 0 */
    voxgig_map_set(voxgig_as_map(inj->meta), "__d", voxgig_new_int(0));
    /* Carry over modify/handler/meta/extra/errs from caller config. */
    if (injdef) {
      if (injdef->modify_val) {
        voxgig_release(inj->modify_val);
        inj->modify_val = voxgig_retain(injdef->modify_val);
      }
      if (injdef->handler_val) {
        voxgig_release(inj->handler_val);
        inj->handler_val = voxgig_retain(injdef->handler_val);
      }
      if (injdef->meta) {
        voxgig_release(inj->meta);
        inj->meta = voxgig_retain(injdef->meta);
      }
      if (injdef->errs && voxgig_is_list(injdef->errs)) {
        voxgig_release(inj->errs);
        inj->errs = voxgig_retain(injdef->errs);
      }
      if (injdef->extra) {
        inj->extra = injdef->extra;
      }
    }
  }

  voxgig_inj_descend(inj);

  if (voxgig_is_node(val)) {
    /* Get keys; if map, partition non-$ then $. */
    voxgig_strvec nodekeys = voxgig_keysof(val);
    if (voxgig_is_map(val)) {
      voxgig_strvec part1;
      voxgig_strvec part2;
      voxgig_strvec_init(&part1);
      voxgig_strvec_init(&part2);
      for (size_t i = 0; i < nodekeys.len; i++) {
        const char* k = nodekeys.data[i];
        if (strchr(k, '$'))
          voxgig_strvec_push(&part2, k);
        else
          voxgig_strvec_push(&part1, k);
      }
      voxgig_strvec_clear(&nodekeys);
      for (size_t i = 0; i < part1.len; i++)
        voxgig_strvec_push(&nodekeys, part1.data[i]);
      for (size_t i = 0; i < part2.len; i++)
        voxgig_strvec_push(&nodekeys, part2.data[i]);
      voxgig_strvec_free(&part1);
      voxgig_strvec_free(&part2);
    }

    for (size_t nkI = 0; nkI < nodekeys.len; nkI++) {
      voxgig_injection* childinj = voxgig_inj_child(inj, nkI, &nodekeys);
      /* Copy the key — nodekeys may be cleared and rewritten below. */
      char* nodekey = xstrndup_s2(nodekeys.data[nkI], strlen(nodekeys.data[nkI]));
      childinj->mode = VOXGIG_M_KEYPRE;

      /* prekey = _injectstr(nodekey, store, childinj) */
      voxgig_value* prekey = voxgig_inject_str_v(nodekey, strlen(nodekey), store, childinj);

      /* Re-read keyI / keys */
      nkI = childinj->keyI_neg ? (size_t)-1 : childinj->keyI;
      voxgig_strvec_clear(&nodekeys);
      for (size_t i = 0; i < childinj->keys.len; i++)
        voxgig_strvec_push(&nodekeys, childinj->keys.data[i]);

      bool prekey_valid = prekey && !voxgig_is_undef(prekey);
      if (prekey_valid) {
        char* pks = voxgig_strkey(prekey);
        voxgig_value* pkv = voxgig_new_string(pks);
        voxgig_release(childinj->val);
        childinj->val = voxgig_getprop(val, pkv, NULL);
        voxgig_release(pkv);
        free(pks);
        childinj->mode = VOXGIG_M_VAL;

        voxgig_inject(childinj->val, store, childinj);

        nkI = childinj->keyI_neg ? (size_t)-1 : childinj->keyI;
        voxgig_strvec_clear(&nodekeys);
        for (size_t i = 0; i < childinj->keys.len; i++)
          voxgig_strvec_push(&nodekeys, childinj->keys.data[i]);

        childinj->mode = VOXGIG_M_KEYPOST;
        voxgig_value* postv = voxgig_inject_str_v(nodekey, strlen(nodekey), store, childinj);
        voxgig_release(postv);

        nkI = childinj->keyI_neg ? (size_t)-1 : childinj->keyI;
        voxgig_strvec_clear(&nodekeys);
        for (size_t i = 0; i < childinj->keys.len; i++)
          voxgig_strvec_push(&nodekeys, childinj->keys.data[i]);
      }

      free(nodekey);
      voxgig_release(prekey);
      voxgig_inj_free(childinj);
    }
    voxgig_strvec_free(&nodekeys);
  } else if (voxgig_is_string(val)) {
    inj->mode = VOXGIG_M_VAL;
    voxgig_value* nv =
        voxgig_inject_str_v(voxgig_as_string(val), voxgig_string_len(val), store, inj);
    if (!voxgig_is_skip(nv)) {
      voxgig_inj_setval(inj, nv, 0);
    }
    /* Replace inj->val and val (which is borrowed). voxgig_retain so caller's
       reference is independent from inj->val's. */
    voxgig_release(inj->val);
    inj->val = nv;
    val = nv; /* borrowed alias; do not release again below */
  }

  /* Modify callback. */
  if (inj->modify_val && voxgig_is_modify(inj->modify_val) && !voxgig_is_skip(val)) {
    voxgig_value* keyv = voxgig_new_string(inj->key);
    voxgig_value* mvp = voxgig_lookup(inj->parent, keyv);
    voxgig_value* mval = mvp ? voxgig_retain(mvp) : voxgig_new_undef();
    inj->modify_val->as.fn.fn.mod(mval, keyv, inj->parent, inj, store, inj->modify_val->as.fn.ud);
    voxgig_release(mval);
    voxgig_release(keyv);
  }

  /* inj->val is already updated for string case; for node case we leave it
     unchanged (it pointed at val from the start). */
  voxgig_value* out = voxgig_map_get(voxgig_as_map(inj->parent), "$TOP");
  voxgig_value* result = out ? voxgig_retain(out) : voxgig_new_undef();
  if (allocated_inj) {
    voxgig_inj_free(allocated_inj);
  }
  return result;
}
