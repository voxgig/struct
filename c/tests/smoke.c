/* Voxgig Struct C port — smoke test. */

#include "voxgig_struct.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int passed = 0;
static int total = 0;

#define CHECK(cond, msg)                                                                           \
  do {                                                                                             \
    total++;                                                                                       \
    if (cond) {                                                                                    \
      passed++;                                                                                    \
    } else {                                                                                       \
      fprintf(stderr, "FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__);                              \
    }                                                                                              \
  } while (0)

/* Values the condense checks hold until release_held. */
static voxgig_value* HELD[256];
static size_t NHELD = 0;

static voxgig_value* hold(voxgig_value* v) {
  if (NHELD < sizeof(HELD) / sizeof(HELD[0]))
    HELD[NHELD++] = v;
  return v;
}

static void release_held(void) {
  while (0 < NHELD)
    voxgig_release(HELD[--NHELD]);
}

static voxgig_value* J(const char* text) {
  return hold(voxgig_parse_json(text, 0));
}

static voxgig_value* S(const char* text) {
  return hold(voxgig_new_string(text));
}

static voxgig_value* C(const char* text) {
  return hold(voxgig_condense(J(text)));
}

static bool same_json(voxgig_value* a, voxgig_value* b) {
  char* aj = voxgig_to_json(a);
  char* bj = voxgig_to_json(b);
  bool same = aj && bj && 0 == strcmp(aj, bj);
  free(aj);
  free(bj);
  return same;
}

static bool is_str(voxgig_value* v, const char* text) {
  return voxgig_is_string(v) && 0 == strcmp(voxgig_as_string(v), text);
}

/* What the corpus cannot express: identity, sharing and the immutability contract. */
static void condense_checks(void) {
  const char* src = "{\"b\":{\"m\":\"GET\"},\"a\":{\"m\":\"GET\"},\"l\":[1,\"x\",true]}";
  CHECK(same_json(C(src), C(src)), "condense is deterministic");
  CHECK(same_json(C(src), C("{\"l\":[1,\"x\",true],\"a\":{\"m\":\"GET\"},\"b\":{\"m\":\"GET\"}}")),
        "condense ignores insertion order");

  voxgig_value* nodek = S("node");
  int64_t one =
      voxgig_size(hold(voxgig_getprop(C("{\"x\":{\"m\":\"GET\",\"p\":\"/1\"}}"), nodek, NULL)));
  int64_t two = voxgig_size(hold(voxgig_getprop(
      C("{\"x\":{\"m\":\"GET\",\"p\":\"/1\"},\"y\":{\"m\":\"GET\",\"p\":\"/1\"}}"), nodek, NULL)));
  int64_t three = voxgig_size(hold(voxgig_getprop(
      C("{\"x\":{\"m\":\"GET\"},\"y\":{\"m\":\"PUT\"},\"z\":{\"m\":\"POST\"}}"), nodek, NULL)));
  CHECK(two == one, "condense: an identical subtree adds no node");
  CHECK(three > two, "condense: distinct subtrees add nodes");

  voxgig_value* rt = J("{\"a\":{\"b\":[1,\"x\",true,null,{}]},\"c\":\"z\"}");
  CHECK(voxgig_equals(hold(voxgig_expand(hold(voxgig_condense(rt)))), rt),
        "condense round-trips by value");

  voxgig_value* deep = J("{\"entity\":{\"p\":{\"op\":{\"list\":{\"method\":\"GET\"}}}}}");
  voxgig_value* cdeep = hold(voxgig_condense(deep));
  voxgig_value* listpath = J("[\"entity\",\"p\",\"op\",\"list\"]");
  CHECK(voxgig_equals(hold(voxgig_getpath(cdeep, listpath, NULL)),
                      hold(voxgig_getpath(deep, listpath, NULL))),
        "condense: getpath is transparent");
  CHECK(
      is_str(hold(voxgig_getpath(cdeep, J("[\"entity\",\"p\",\"op\",\"list\",\"method\"]"), NULL)),
             "GET"),
      "condense: getpath reaches a leaf");
  CHECK(voxgig_is_undef(hold(voxgig_getpath(cdeep, J("[\"entity\",\"nope\"]"), NULL))),
        "condense: getpath misses");

  voxgig_cview v = voxgig_condenseview(
      C("{\"entity\":{\"a\":{\"v\":1},\"b\":{\"v\":2}},\"other\":9}"), NULL, NULL);
  voxgig_strvec keys = voxgig_cview_keys(&v, S("entity"));
  CHECK(2 == keys.len && 0 == strcmp(keys.data[0], "a") && 0 == strcmp(keys.data[1], "b"),
        "view keys");
  voxgig_strvec_free(&keys);
  voxgig_cview ve = voxgig_cview_at(&v, S("entity"));
  voxgig_cview vb = voxgig_cview_at(&ve, S("b"));
  voxgig_value* vbv = hold(voxgig_cview_get(&vb, S("v")));
  CHECK(voxgig_is_int(vbv) && 2 == voxgig_as_int(vbv), "view at, at, get");
  CHECK(voxgig_cview_has(&v, S("entity.a")), "view has");
  CHECK(!voxgig_cview_has(&v, S("entity.zz")), "view has not");
  CHECK(2 == voxgig_cview_size(&v), "view size");
  voxgig_cview vz = voxgig_cview_at(&v, S("entity.zz"));
  keys = voxgig_cview_keys(&vz, NULL);
  CHECK(!voxgig_cview_exists(&vz) && 0 == voxgig_cview_size(&vz) && 0 == keys.len &&
            voxgig_is_undef(hold(voxgig_cview_value(&vz))) &&
            voxgig_is_undef(hold(voxgig_cview_ref(&vz))),
        "view at a miss");
  voxgig_strvec_free(&keys);
  voxgig_cview_free(&vz);
  voxgig_cview_free(&vb);
  voxgig_cview_free(&ve);
  voxgig_cview_free(&v);

  voxgig_cview vs =
      voxgig_condenseview(C("{\"a\":{\"m\":\"GET\"},\"b\":{\"m\":\"GET\"}}"), NULL, NULL);
  voxgig_value* x = hold(voxgig_cview_get(&vs, S("a")));
  voxgig_value* y = hold(voxgig_cview_get(&vs, S("b")));
  CHECK(voxgig_equals(x, y) && x != y, "view get copies a shared node");
  voxgig_setprop(x, S("m"), S("MUTATED"));
  CHECK(is_str(hold(voxgig_cview_get(&vs, S("b.m"))), "GET"), "view get is independent");
  voxgig_cview ra = voxgig_cview_at(&vs, S("a"));
  voxgig_cview rb = voxgig_cview_at(&vs, S("a"));
  CHECK(hold(voxgig_cview_ref(&ra)) == hold(voxgig_cview_ref(&rb)), "view ref shares");
  voxgig_cview_free(&rb);
  voxgig_cview_free(&ra);
  voxgig_cview_free(&vs);

  voxgig_value* pv = J("{\"x\":\"__proto__\"}");
  CHECK(voxgig_equals(hold(voxgig_expand(hold(voxgig_condense(pv)))), pv),
        "condense: a __proto__ value round-trips");
  char* pk = voxgig_to_json(hold(voxgig_expand(C("{\"__proto__\":1}"))));
  CHECK(pk && 0 == strcmp(pk, "{\"__proto__\":1}"), "condense: a __proto__ key round-trips");
  free(pk);

  /* Canonical reads a stored null as absent; this port's plain getpath returns the null. */
  CHECK(voxgig_is_undef(hold(voxgig_getpath(C("{\"a\":null}"), S("a"), NULL))),
        "condense: getpath reads a stored null as absent");
  voxgig_injection binj;
  memset(&binj, 0, sizeof binj);
  binj.base = "base";
  voxgig_value* bstore = J("{\"base\":{\"x\":1}}");
  voxgig_value* bgot = hold(voxgig_getpath(hold(voxgig_condense(bstore)), S("x"), &binj));
  CHECK(voxgig_is_int(bgot) && 1 == voxgig_as_int(bgot) &&
            voxgig_equals(bgot, hold(voxgig_getpath(bstore, S("x"), &binj))),
        "condense: getpath honours a base");

  /* Unary + would accept these; a plain list read does not, so condensing must not change
     which value a path selects. */
  voxgig_value* pl = J("{\"l\":[10,20]}");
  voxgig_value* cl = hold(voxgig_condense(pl));
  const char* listkeys[] = {"01", "1e0", " 1", "+1", "1.0", "-0"};
  for (size_t i = 0; i < sizeof(listkeys) / sizeof(listkeys[0]); i++) {
    voxgig_value* lp = hold(voxgig_new_list());
    voxgig_list_push(voxgig_as_list(lp), voxgig_new_string("l"));
    voxgig_list_push(voxgig_as_list(lp), voxgig_new_string(listkeys[i]));
    CHECK(voxgig_equals(hold(voxgig_getpath(cl, lp, NULL)), hold(voxgig_getpath(pl, lp, NULL))),
          listkeys[i]);
  }
  voxgig_value* l1 = hold(voxgig_getpath(cl, J("[\"l\",\"1\"]"), NULL));
  CHECK(voxgig_is_int(l1) && 20 == voxgig_as_int(l1), "condense: list key 1");

  voxgig_value* sym = hold(
      voxgig_getprop(C("{\"a\":\"\xF0\x90\x80\x80\",\"b\":\"\xEF\xBF\xBF\"}"), S("sym"), NULL));
  CHECK(4 == voxgig_size(sym) && is_str(voxgig_list_get(voxgig_as_list(sym), 2), "\xEF\xBF\xBF") &&
            is_str(voxgig_list_get(voxgig_as_list(sym), 3), "\xF0\x90\x80\x80"),
        "condense: symbols sort by code point");

  voxgig_value* astral = C("{\"\xEF\xBC\xA1\":1,\"\xF0\x9F\x98\x80\":2}");
  voxgig_value* emoji = S("\xF0\x9F\x98\x80");
  voxgig_value* got2 = hold(voxgig_getpath(astral, hold(voxgig_jt_va(1, &emoji)), NULL));
  voxgig_value* fw = S("\xEF\xBC\xA1");
  voxgig_value* got1 = hold(voxgig_getpath(astral, hold(voxgig_jt_va(1, &fw)), NULL));
  voxgig_cview va = voxgig_condenseview(astral, NULL, NULL);
  voxgig_value* got3 = hold(voxgig_cview_get(&va, emoji));
  CHECK(voxgig_is_int(got2) && 2 == voxgig_as_int(got2) && voxgig_is_int(got1) &&
            1 == voxgig_as_int(got1) && voxgig_is_int(got3) && 2 == voxgig_as_int(got3),
        "condense: astral keys resolve");
  voxgig_cview_free(&va);

  voxgig_value* cond = C("{\"a\":1}");
  voxgig_value* two_v = hold(voxgig_new_int(2));
  char* before = voxgig_to_json(cond);
  CHECK(cond == voxgig_delprop(cond, NULL) && cond == voxgig_setprop(cond, NULL, two_v),
        "condense: an invalid key stays a no-op");
  voxgig_injection inj;
  memset(&inj, 0, sizeof inj);
  inj.errs = hold(voxgig_new_list());
  CHECK(NULL == voxgig_setpath(cond, S("a"), two_v, &inj) && 1 == voxgig_size(inj.errs) &&
            strstr(voxgig_as_string(voxgig_list_get(voxgig_as_list(inj.errs), 0)), "immutable"),
        "condense: setpath refuses, and says why");
  CHECK(NULL == voxgig_setprop(cond, S("a"), two_v), "condense: setprop refuses");
  CHECK(NULL == voxgig_delprop(cond, S("sym")), "condense: delprop refuses");
  char* after = voxgig_to_json(cond);
  CHECK(before && after && 0 == strcmp(before, after), "condense: the store is unchanged");
  free(before);
  free(after);
  voxgig_value* e = hold(voxgig_expand(cond));
  voxgig_setpath(e, S("a"), two_v, NULL);
  voxgig_value* ea = hold(voxgig_getprop(e, S("a"), NULL));
  CHECK(voxgig_is_int(ea) && 2 == voxgig_as_int(ea), "condense: the expanded copy is mutable");

  CHECK(NHELD < sizeof(HELD) / sizeof(HELD[0]), "condense checks hold every value");
  release_held();
}

/* The errors validate collects for data against spec, held. */
static voxgig_value* verrs(voxgig_value* data, voxgig_value* spec) {
  voxgig_injection inj;
  memset(&inj, 0, sizeof inj);
  inj.errs = hold(voxgig_new_list());
  hold(voxgig_validate(data, spec, &inj));
  return inj.errs;
}

/* What the corpus cannot express: the number of $CHILD errors, and a decimal $NOF count,
   which the corpus compiler writes as an integer. */
static void validate_checks(void) {
  const char* child[][2] = {
      {"{\"x\":1}", "{\"x\":{\"`$CHILD`\":\"`$NUMBER`\"}}"},
      {"{\"x\":1}", "{\"x\":[\"`$CHILD`\",\"`$NUMBER`\"]}"},
      {"1", "{\"`$CHILD`\":\"`$NUMBER`\"}"},
      {"1", "[\"`$CHILD`\",\"`$NUMBER`\"]"},
  };
  for (size_t i = 0; i < sizeof(child) / sizeof(child[0]); i++)
    CHECK(1 == voxgig_size(verrs(J(child[i][0]), J(child[i][1]))), child[i][1]);

  voxgig_value* nof2 = J("[\"`$NOF`\",2.0,\"`$STRING`\",\"`$STRING`\"]");
  CHECK(voxgig_is_double(voxgig_list_get(voxgig_as_list(nof2), 1)) &&
            0 == voxgig_size(verrs(J("\"x\""), nof2)),
        "nof: a 2.0 count admits");
  voxgig_value* nof2miss = verrs(J("\"x\""), J("[\"`$NOF`\",2.0,\"`$STRING`\",\"`$NUMBER`\"]"));
  CHECK(1 == voxgig_size(nof2miss) &&
            is_str(voxgig_list_get(voxgig_as_list(nof2miss), 0),
                   "Expected exactly 2 of string, number, but found string: x."),
        "nof: a 2.0 count is exactly 2");
  CHECK(0 == voxgig_size(
                 verrs(J("\"x\""),
                       J("[\"`$NOF`\",{\"min\":1.0,\"max\":2.0},\"`$STRING`\",\"`$NUMBER`\"]"))),
        "nof: a decimal min and max");
  release_held();
}

int main(void) {
  /* Type predicates. */
  voxgig_value* m = voxgig_new_map();
  CHECK(voxgig_isnode(m), "ismap node");
  CHECK(voxgig_ismap(m), "is map");
  CHECK(!voxgig_islist(m), "not list");
  voxgig_release(m);

  voxgig_value* l = voxgig_new_list();
  CHECK(voxgig_isnode(l), "list node");
  CHECK(voxgig_islist(l), "is list");
  voxgig_release(l);

  voxgig_value* s = voxgig_new_string("hello");
  CHECK(!voxgig_isnode(s), "string not node");
  CHECK(voxgig_iskey(s), "is key");
  voxgig_release(s);

  /* getprop. */
  voxgig_value* obj = voxgig_new_map();
  voxgig_map_set(voxgig_as_map(obj), "a", voxgig_new_int(42));
  voxgig_value* keyv = voxgig_new_string("a");
  voxgig_value* v = voxgig_getprop(obj, keyv, NULL);
  CHECK(voxgig_is_int(v) && voxgig_as_int(v) == 42, "getprop int");
  voxgig_release(v);
  voxgig_release(keyv);
  voxgig_release(obj);

  /* getpath simple. */
  voxgig_value* store = voxgig_parse_json("{\"a\":{\"b\":{\"c\":99}}}", 0);
  voxgig_value* p = voxgig_new_string("a.b.c");
  voxgig_value* gv = voxgig_getpath(store, p, NULL);
  CHECK(voxgig_is_int(gv) && voxgig_as_int(gv) == 99, "getpath nested");
  voxgig_release(p);
  voxgig_release(gv);
  voxgig_release(store);

  /* typify. */
  voxgig_value* nv = voxgig_new_null();
  CHECK(voxgig_typify(nv) == (VOXGIG_T_SCALAR | VOXGIG_T_NULL), "typify null");
  voxgig_release(nv);

  /* size. */
  voxgig_value* str = voxgig_new_string("abc");
  CHECK(voxgig_size(str) == 3, "size string");
  voxgig_release(str);

  /* stringify. */
  voxgig_value* obj2 = voxgig_new_map();
  voxgig_map_set(voxgig_as_map(obj2), "a", voxgig_new_int(1));
  char* sout = voxgig_stringify(obj2, -1);
  CHECK(strcmp(sout, "{a:1}") == 0, "stringify {a:1}");
  free(sout);
  voxgig_release(obj2);

  /* merge. */
  voxgig_value* ml = voxgig_new_list();
  voxgig_value* o1 = voxgig_parse_json("{\"a\":1,\"b\":2}", 0);
  voxgig_value* o2 = voxgig_parse_json("{\"b\":3,\"c\":4}", 0);
  voxgig_list_push(voxgig_as_list(ml), o1);
  voxgig_list_push(voxgig_as_list(ml), o2);
  voxgig_value* mr = voxgig_merge(ml, VOXGIG_MAXDEPTH);
  char* mjs = voxgig_jsonify(mr, NULL);
  /* Expect a=1,b=3,c=4. */
  CHECK(mjs && strstr(mjs, "\"a\": 1") != NULL, "merge a");
  free(mjs);
  voxgig_release(mr);
  voxgig_release(ml);

  /* parse_json: malformed input, or anything after the value, gives undef. */
  const char* bad_json[] = {"{\"id\": \"x01\", \"title\": ",
                            "[1, 2] trailing",
                            "{} {}",
                            "[1, 2",
                            "[1 2]",
                            "[1,]",
                            "{\"a\" 1}",
                            "{\"a\": 1,}",
                            "{1: 2}",
                            "nul",
                            "01",
                            "1.",
                            "-",
                            "1e+",
                            "\"open",
                            "\"a\\x\"",
                            "\"tab\there\""};
  for (size_t i = 0; i < sizeof(bad_json) / sizeof(bad_json[0]); i++) {
    voxgig_value* bv = voxgig_parse_json(bad_json[i], 0);
    CHECK(voxgig_is_undef(bv), bad_json[i]);
    voxgig_release(bv);
  }
  voxgig_value* gj = voxgig_parse_json(" {\"a\": [0, -2.5e3, true, null, \"\\u00e9\"]}\n", 0);
  char* gjs = voxgig_jsonify(gj, NULL);
  CHECK(gjs && strstr(gjs, "-2500") && strstr(gjs, "\xc3\xa9"), "parse_json whole document");
  free(gjs);
  voxgig_release(gj);

  /* setpath reads its base as getprop(store, base, store). */
  const char* base_rows[][4] = {
      {"[[]]", "0", "[0,\"a\"]", "[[{\"a\":1}]]"},
      {"{\"x\":null}", "x", "[0]", "{\"x\":null,\"0\":1}"},
      {"{\"x\":[]}", "x", "[0,\"a\"]", "{\"x\":[{\"a\":1}]}"},
  };
  for (size_t i = 0; i < sizeof(base_rows) / sizeof(base_rows[0]); i++) {
    voxgig_value* bstore = voxgig_parse_json(base_rows[i][0], 0);
    voxgig_value* bpath = voxgig_parse_json(base_rows[i][2], 0);
    voxgig_value* bval = voxgig_new_int(1);
    voxgig_injection binj;
    memset(&binj, 0, sizeof binj);
    binj.base = (char*)base_rows[i][1];
    voxgig_setpath(bstore, bpath, bval, &binj);
    char* bout = voxgig_to_json(bstore);
    CHECK(bout && 0 == strcmp(bout, base_rows[i][3]), base_rows[i][3]);
    if (bout && 0 != strcmp(bout, base_rows[i][3]))
      fprintf(stderr, "  got: %s\n", bout);
    free(bout);
    voxgig_release(bval);
    voxgig_release(bpath);
    voxgig_release(bstore);
  }

  condense_checks();
  validate_checks();

  printf("smoke: %d/%d passed\n", passed, total);
  return passed == total ? 0 : 1;
}
