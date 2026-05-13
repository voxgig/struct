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
static vs_value* _injecthandler(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                                void* ud);

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

vs_injection* vs_inj_new(vs_value* val, vs_value* parent) {
  vs_injection* inj = (vs_injection*)calloc(1, sizeof(vs_injection));
  if (!inj)
    abort();
  inj->val = val ? vs_retain(val) : vs_new_undef();
  inj->parent = parent ? vs_retain(parent) : vs_new_undef();
  inj->errs = vs_new_list();
  inj->dparent = NULL;
  vs_strvec_init(&inj->dpath);
  vs_strvec_push(&inj->dpath, "$TOP");
  inj->mode = VS_M_VAL;
  inj->full = false;
  inj->keyI = 0;
  inj->keyI_neg = false;
  vs_strvec_init(&inj->keys);
  vs_strvec_push(&inj->keys, "$TOP");
  inj->key = xstrdup_s2("$TOP");
  vs_strvec_init(&inj->path);
  vs_strvec_push(&inj->path, "$TOP");
  /* nodes stack: borrowed references. */
  inj->nodes_len = 0;
  inj->nodes_cap = 0;
  inj->nodes = NULL;
  vs_inj_nodes_push(inj, parent);
  inj->handler_val = vs_new_injector(_injecthandler, NULL);
  inj->base = xstrdup_s2("$TOP");
  inj->meta = vs_new_map();
  inj->modify_val = NULL;
  inj->prior = NULL;
  inj->extra = NULL;
  return inj;
}

void vs_inj_free(vs_injection* inj) {
  if (!inj)
    return;
  vs_release(inj->val);
  vs_release(inj->parent);
  vs_strvec_free(&inj->keys);
  free(inj->key);
  vs_strvec_free(&inj->path);
  free(inj->nodes);
  vs_release(inj->handler_val);
  vs_release(inj->errs);
  vs_release(inj->meta);
  vs_strvec_free(&inj->dpath);
  free(inj->base);
  vs_release(inj->modify_val);
  free(inj);
}

void vs_inj_nodes_push(vs_injection* inj, vs_value* n) {
  if (inj->nodes_len + 1 > inj->nodes_cap) {
    size_t nc = inj->nodes_cap == 0 ? 8 : inj->nodes_cap * 2;
    vs_value** nn = (vs_value**)realloc(inj->nodes, nc * sizeof(vs_value*));
    if (!nn)
      abort();
    inj->nodes = nn;
    inj->nodes_cap = nc;
  }
  inj->nodes[inj->nodes_len++] = n;
}

void vs_inj_set_path(vs_injection* inj, const vs_strvec* path) {
  vs_strvec_copy(&inj->path, path);
}

void vs_inj_set_dpath(vs_injection* inj, const vs_strvec* path) {
  vs_strvec_copy(&inj->dpath, path);
}

void vs_inj_descend(vs_injection* inj) {
  /* meta.__d++ */
  vs_value* d = vs_map_get(vs_as_map(inj->meta), "__d");
  int64_t dv = (d && vs_is_int(d)) ? vs_as_int(d) : 0;
  vs_map_set(vs_as_map(inj->meta), "__d", vs_new_int(dv + 1));

  /* parentkey = path[path.length-2] */
  const char* parentkey = NULL;
  if (inj->path.len >= 2)
    parentkey = inj->path.data[inj->path.len - 2];

  if (!inj->dparent || vs_is_undef(inj->dparent)) {
    if (inj->dpath.len > 1 && parentkey) {
      vs_strvec_push(&inj->dpath, parentkey);
    }
  } else {
    if (parentkey) {
      vs_value* k = vs_new_string(parentkey);
      vs_value* nd = vs_getprop(inj->dparent, k, NULL);
      vs_release(k);
      vs_release(inj->dparent);
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
        vs_strvec_push(&inj->dpath, parentkey);
      }
    }
  }
}

vs_injection* vs_inj_child(vs_injection* parent, size_t keyI, const vs_strvec* keys) {
  /* key = strkey(keys[keyI]) */
  const char* keystr = (keyI < keys->len) ? keys->data[keyI] : "";
  vs_value* keyv = vs_new_string(keystr);
  vs_value* val = vs_getprop(parent->val, keyv, NULL);
  vs_release(keyv);

  vs_injection* cinj = (vs_injection*)calloc(1, sizeof(vs_injection));
  if (!cinj)
    abort();
  cinj->val = val;
  cinj->parent = vs_retain(parent->val);
  cinj->errs = vs_retain(parent->errs);
  cinj->dparent = parent->dparent ? vs_retain(parent->dparent) : vs_new_undef();
  vs_strvec_init(&cinj->dpath);
  vs_strvec_copy(&cinj->dpath, &parent->dpath);
  cinj->mode = parent->mode;
  cinj->full = false;
  cinj->keyI = keyI;
  cinj->keyI_neg = false;
  vs_strvec_init(&cinj->keys);
  vs_strvec_copy(&cinj->keys, keys);
  cinj->key = xstrdup_s2(keystr);
  vs_strvec_init(&cinj->path);
  vs_strvec_copy(&cinj->path, &parent->path);
  vs_strvec_push(&cinj->path, keystr);
  cinj->nodes_len = 0;
  cinj->nodes_cap = 0;
  cinj->nodes = NULL;
  for (size_t i = 0; i < parent->nodes_len; i++)
    vs_inj_nodes_push(cinj, parent->nodes[i]);
  vs_inj_nodes_push(cinj, parent->val);
  cinj->handler_val = parent->handler_val ? vs_retain(parent->handler_val) : NULL;
  cinj->base = parent->base ? xstrdup_s2(parent->base) : NULL;
  cinj->meta = parent->meta ? vs_retain(parent->meta) : vs_new_map();
  cinj->modify_val = parent->modify_val ? vs_retain(parent->modify_val) : NULL;
  cinj->prior = parent;
  cinj->extra = parent->extra;
  return cinj;
}

vs_value* vs_inj_setval(vs_injection* inj, vs_value* val, int ancestor) {
  vs_value* target = NULL;
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
  vs_value* keyv = vs_new_string(tkey ? tkey : "");
  if (!val || vs_is_undef(val)) {
    vs_delprop(target, keyv);
  } else {
    vs_setprop(target, keyv, val);
  }
  vs_release(keyv);
  return target;
}

/* ===========================================================================
 * checkPlacement
 * ===========================================================================*/

bool vs_check_placement(int modes, const char* ijname, int parent_types, vs_injection* inj) {
  if ((modes & inj->mode) == 0) {
    const char* placement = (inj->mode == VS_M_VAL) ? "value" : "key";
    /* Build expected list. */
    char expected[64] = "";
    bool first = true;
    if (modes & VS_M_KEYPRE) {
      if (!first)
        strcat(expected, ",");
      strcat(expected, "key");
      first = false;
    }
    if (modes & VS_M_KEYPOST) {
      if (!first)
        strcat(expected, ",");
      strcat(expected, "key");
      first = false;
    }
    if (modes & VS_M_VAL) {
      if (!first)
        strcat(expected, ",");
      strcat(expected, "value");
      first = false;
    }
    char msg[256];
    snprintf(msg, sizeof(msg), "$%s: invalid placement as %s, expected: %s.", ijname, placement,
             expected);
    vs_list_push(vs_as_list(inj->errs), vs_new_string(msg));
    return false;
  }
  if (parent_types != 0 && parent_types != VS_T_ANY) {
    int pt = vs_typify(inj->parent);
    if ((parent_types & pt) == 0) {
      char msg[256];
      snprintf(msg, sizeof(msg), "$%s: invalid placement in parent %s, expected: %s.", ijname,
               vs_typename(pt), vs_typename(parent_types));
      vs_list_push(vs_as_list(inj->errs), vs_new_string(msg));
      return false;
    }
  }
  return true;
}

/* ===========================================================================
 * injectorArgs
 * ===========================================================================*/

vs_value* vs_injector_args(const int* argTypes, size_t n, vs_value* args) {
  vs_value* found = vs_new_list();
  vs_list_push(vs_as_list(found), vs_new_undef()); /* err slot */
  for (size_t i = 0; i < n; i++) {
    vs_value* arg = NULL;
    if (vs_is_list(args)) {
      arg = vs_list_get(vs_as_list(args), i);
    }
    int argt = vs_typify(arg);
    if ((argTypes[i] & argt) == 0) {
      char* arepr = vs_stringify(arg, 22);
      char msg[512];
      snprintf(msg, sizeof(msg), "invalid argument: %s (%s at position %zu) is not of type: %s.",
               arepr, vs_typename(argt), 1 + i, vs_typename(argTypes[i]));
      free(arepr);
      vs_list_set(vs_as_list(found), 0, vs_new_string(msg));
      return found;
    }
    vs_list_push(vs_as_list(found), arg ? vs_retain(arg) : vs_new_undef());
  }
  return found;
}

/* ===========================================================================
 * injectChild
 * ===========================================================================*/

vs_injection* vs_inject_child(vs_value* child, vs_value* store, vs_injection* inj) {
  vs_injection* cinj = inj;

  /* Replace ['$FORMAT', ...] in parent with child. */
  if (inj->prior) {
    if (inj->prior->prior) {
      cinj = vs_inj_child(inj->prior->prior, inj->prior->keyI, &inj->prior->keys);
      vs_release(cinj->val);
      cinj->val = child ? vs_retain(child) : vs_new_undef();
      vs_value* keyv = vs_new_string(inj->prior->key);
      vs_setprop(cinj->parent, keyv, child);
      vs_release(keyv);
    } else {
      cinj = vs_inj_child(inj->prior, inj->keyI, &inj->keys);
      vs_release(cinj->val);
      cinj->val = child ? vs_retain(child) : vs_new_undef();
      vs_value* keyv = vs_new_string(inj->key);
      vs_setprop(cinj->parent, keyv, child);
      vs_release(keyv);
    }
  }

  vs_inject(child, store, cinj);
  return cinj;
}

/* ===========================================================================
 * _injectstr
 * ===========================================================================*/

/* R_INJECTION_FULL: ^`(\$[A-Z]+|[^`]*)[0-9]*`$
 * Returns true if val is a full single-injection string of length>=2.
 * On match, fills pathref (allocated). */
static bool match_injection_full(const char* val, size_t vlen, char** out_pathref) {
  if (vlen < 2 || val[0] != '`' || val[vlen - 1] != '`')
    return false;
  /* Inside content: val+1 .. vlen-2 */
  size_t ilen = vlen - 2;
  const char* in = val + 1;
  /* No backticks inside. */
  for (size_t i = 0; i < ilen; i++) {
    if (in[i] == '`')
      return false;
  }
  /* Two alternatives:
   *  (a) "$NAME" — $ + [A-Z]+
   *  (b) [^`]* — any non-backtick
   * Then optional [0-9]* at the end (these digits are NOT in the capture for $NAME case,
   * but for the [^`]* case they're part of the capture).
   */
  /* TS regex: ^`(\$[A-Z]+|[^`]*)[0-9]*`$ — the captured group is either $NAME (no digits)
   * or [^`]* greedy. The greedy `[^`]*` will eat trailing digits too. So the only case
   * where digits get stripped is when the captured part is $NAME (uppercase only). */
  /* Detect $NAME form. */
  if (ilen > 1 && in[0] == '$') {
    size_t j = 1;
    while (j < ilen && in[j] >= 'A' && in[j] <= 'Z')
      j++;
    /* Verify the rest is digits only. */
    size_t k = j;
    while (k < ilen && in[k] >= '0' && in[k] <= '9')
      k++;
    if (k == ilen && j > 1) {
      *out_pathref = xstrndup_s2(in, j); /* without trailing digits */
      return true;
    }
  }
  /* Fall through: full content is the pathref (greedy). */
  *out_pathref = xstrndup_s2(in, ilen);
  return true;
}

/* Apply $BT and $DS escapes. */
static char* apply_escapes(const char* s) {
  char* a = vs_replace_str(s, "$BT", "`");
  char* b = vs_replace_str(a, "$DS", "$");
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
vs_value* vs_inject_str_v(const char* val, size_t vlen, vs_value* store, vs_injection* inj) {
  if (!val || vlen == 0)
    return vs_new_string("");
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
    vs_value* p = vs_new_string(eff);
    vs_value* out = vs_getpath(store, p, inj);
    vs_release(p);
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
        vs_value* p = vs_new_string(eff);
        vs_value* found = vs_getpath(store, p, inj);
        vs_release(p);
        free(unescaped);
        free(ref);
        char* sub;
        if (!found || vs_is_undef(found))
          sub = xstrdup_s2("");
        else if (vs_is_string(found))
          sub = xstrdup_s2(vs_as_string(found));
        else {
          /* JSON.stringify without indent — compact. */
          vs_value* flags = vs_new_map();
          vs_map_set(vs_as_map(flags), "indent", vs_new_int(0));
          sub = vs_jsonify(found, flags);
          vs_release(flags);
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
        vs_release(found);
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
  vs_value* outv = vs_new_string(buf);
  free(buf);
  if (inj && inj->handler_val && vs_is_func(inj->handler_val)) {
    inj->full = true;
    char* origref = xstrndup_s2(val, vlen);
    vs_value* nv =
        inj->handler_val->as.fn.fn.inj(inj, outv, origref, store, inj->handler_val->as.fn.ud);
    free(origref);
    vs_release(outv);
    outv = nv;
  }
  return outv;
}

/* ===========================================================================
 * _injecthandler / _validatehandler
 * ===========================================================================*/

static vs_value* _injecthandler(vs_injection* inj, vs_value* val, const char* ref, vs_value* store,
                                void* ud) {
  (void)ud;
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

vs_value* vs_validatehandler_internal(vs_injection* inj, vs_value* val, const char* ref,
                                      vs_value* store, void* ud);

vs_value* vs_validatehandler_internal(vs_injection* inj, vs_value* val, const char* ref,
                                      vs_value* store, void* ud) {
  /* Match R_META_PATH: ^([^$]+)\$([=~])(.+)$ */
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
      inj->keyI_neg = true;
      inj->keyI = 0;
      return vs_new_skip();
    }
  }
  return _injecthandler(inj, val, ref, store, ud);
}

/* ===========================================================================
 * Main inject() loop
 * ===========================================================================*/

vs_value* vs_inject(vs_value* val, vs_value* store, vs_injection* injdef) {
  vs_injection* inj = injdef;
  /* Root if no injdef, or injdef.mode==0 (config bag). */
  bool root = (injdef == NULL) || (injdef->mode == 0);
  vs_injection* allocated_inj = NULL;

  if (root) {
    vs_value* holder = vs_new_map();
    vs_map_set(vs_as_map(holder), "$TOP", val ? vs_retain(val) : vs_new_undef());
    inj = vs_inj_new(val, holder);
    vs_release(holder);
    allocated_inj = inj;
    inj->dparent = store ? vs_retain(store) : vs_new_undef();
    /* errs = store.$ERRS or [] */
    vs_value* serr = vs_map_get(vs_as_map(store), "$ERRS");
    if (serr) {
      vs_release(inj->errs);
      inj->errs = vs_retain(serr);
    }
    /* meta.__d = 0 */
    vs_map_set(vs_as_map(inj->meta), "__d", vs_new_int(0));
    /* Carry over modify/handler/meta/extra/errs from caller config. */
    if (injdef) {
      if (injdef->modify_val) {
        vs_release(inj->modify_val);
        inj->modify_val = vs_retain(injdef->modify_val);
      }
      if (injdef->handler_val) {
        vs_release(inj->handler_val);
        inj->handler_val = vs_retain(injdef->handler_val);
      }
      if (injdef->meta) {
        vs_release(inj->meta);
        inj->meta = vs_retain(injdef->meta);
      }
      if (injdef->errs && vs_is_list(injdef->errs)) {
        vs_release(inj->errs);
        inj->errs = vs_retain(injdef->errs);
      }
      if (injdef->extra) {
        inj->extra = injdef->extra;
      }
    }
  }

  vs_inj_descend(inj);

  if (vs_is_node(val)) {
    /* Get keys; if map, partition non-$ then $. */
    vs_strvec nodekeys = vs_keysof(val);
    if (vs_is_map(val)) {
      vs_strvec part1;
      vs_strvec part2;
      vs_strvec_init(&part1);
      vs_strvec_init(&part2);
      for (size_t i = 0; i < nodekeys.len; i++) {
        const char* k = nodekeys.data[i];
        if (strchr(k, '$'))
          vs_strvec_push(&part2, k);
        else
          vs_strvec_push(&part1, k);
      }
      vs_strvec_clear(&nodekeys);
      for (size_t i = 0; i < part1.len; i++)
        vs_strvec_push(&nodekeys, part1.data[i]);
      for (size_t i = 0; i < part2.len; i++)
        vs_strvec_push(&nodekeys, part2.data[i]);
      vs_strvec_free(&part1);
      vs_strvec_free(&part2);
    }

    for (size_t nkI = 0; nkI < nodekeys.len; nkI++) {
      vs_injection* childinj = vs_inj_child(inj, nkI, &nodekeys);
      /* Copy the key — nodekeys may be cleared and rewritten below. */
      char* nodekey = xstrndup_s2(nodekeys.data[nkI], strlen(nodekeys.data[nkI]));
      childinj->mode = VS_M_KEYPRE;

      /* prekey = _injectstr(nodekey, store, childinj) */
      vs_value* prekey = vs_inject_str_v(nodekey, strlen(nodekey), store, childinj);

      /* Re-read keyI / keys */
      nkI = childinj->keyI_neg ? (size_t)-1 : childinj->keyI;
      vs_strvec_clear(&nodekeys);
      for (size_t i = 0; i < childinj->keys.len; i++)
        vs_strvec_push(&nodekeys, childinj->keys.data[i]);

      bool prekey_valid = prekey && !vs_is_undef(prekey);
      if (prekey_valid) {
        char* pks = vs_strkey(prekey);
        vs_value* pkv = vs_new_string(pks);
        vs_release(childinj->val);
        childinj->val = vs_getprop(val, pkv, NULL);
        vs_release(pkv);
        free(pks);
        childinj->mode = VS_M_VAL;

        vs_inject(childinj->val, store, childinj);

        nkI = childinj->keyI_neg ? (size_t)-1 : childinj->keyI;
        vs_strvec_clear(&nodekeys);
        for (size_t i = 0; i < childinj->keys.len; i++)
          vs_strvec_push(&nodekeys, childinj->keys.data[i]);

        childinj->mode = VS_M_KEYPOST;
        vs_value* postv = vs_inject_str_v(nodekey, strlen(nodekey), store, childinj);
        vs_release(postv);

        nkI = childinj->keyI_neg ? (size_t)-1 : childinj->keyI;
        vs_strvec_clear(&nodekeys);
        for (size_t i = 0; i < childinj->keys.len; i++)
          vs_strvec_push(&nodekeys, childinj->keys.data[i]);
      }

      free(nodekey);
      vs_release(prekey);
      vs_inj_free(childinj);
    }
    vs_strvec_free(&nodekeys);
  } else if (vs_is_string(val)) {
    inj->mode = VS_M_VAL;
    vs_value* nv = vs_inject_str_v(vs_as_string(val), vs_string_len(val), store, inj);
    if (!vs_is_skip(nv)) {
      vs_inj_setval(inj, nv, 0);
    }
    /* Replace inj->val and val (which is borrowed). vs_retain so caller's
       reference is independent from inj->val's. */
    vs_release(inj->val);
    inj->val = nv;
    val = nv; /* borrowed alias; do not release again below */
  }

  /* Modify callback. */
  if (inj->modify_val && vs_is_modify(inj->modify_val) && !vs_is_skip(val)) {
    vs_value* keyv = vs_new_string(inj->key);
    vs_value* mval = vs_getprop(inj->parent, keyv, NULL);
    inj->modify_val->as.fn.fn.mod(mval, keyv, inj->parent, inj, store, inj->modify_val->as.fn.ud);
    vs_release(mval);
    vs_release(keyv);
  }

  /* inj->val is already updated for string case; for node case we leave it
     unchanged (it pointed at val from the start). */
  vs_value* out = vs_map_get(vs_as_map(inj->parent), "$TOP");
  vs_value* result = out ? vs_retain(out) : vs_new_undef();
  if (allocated_inj) {
    vs_inj_free(allocated_inj);
  }
  return result;
}
