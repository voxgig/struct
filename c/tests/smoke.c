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

  printf("smoke: %d/%d passed\n", passed, total);
  return passed == total ? 0 : 1;
}
