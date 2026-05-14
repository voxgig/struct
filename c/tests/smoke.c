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
  vs_value* m = vs_new_map();
  CHECK(vs_isnode(m), "ismap node");
  CHECK(vs_ismap(m), "is map");
  CHECK(!vs_islist(m), "not list");
  vs_release(m);

  vs_value* l = vs_new_list();
  CHECK(vs_isnode(l), "list node");
  CHECK(vs_islist(l), "is list");
  vs_release(l);

  vs_value* s = vs_new_string("hello");
  CHECK(!vs_isnode(s), "string not node");
  CHECK(vs_iskey(s), "is key");
  vs_release(s);

  /* getprop. */
  vs_value* obj = vs_new_map();
  vs_map_set(vs_as_map(obj), "a", vs_new_int(42));
  vs_value* keyv = vs_new_string("a");
  vs_value* v = vs_getprop(obj, keyv, NULL);
  CHECK(vs_is_int(v) && vs_as_int(v) == 42, "getprop int");
  vs_release(v);
  vs_release(keyv);
  vs_release(obj);

  /* getpath simple. */
  vs_value* store = vs_parse_json("{\"a\":{\"b\":{\"c\":99}}}", 0);
  vs_value* p = vs_new_string("a.b.c");
  vs_value* gv = vs_getpath(store, p, NULL);
  CHECK(vs_is_int(gv) && vs_as_int(gv) == 99, "getpath nested");
  vs_release(p);
  vs_release(gv);
  vs_release(store);

  /* typify. */
  vs_value* nv = vs_new_null();
  CHECK(vs_typify(nv) == (VS_T_SCALAR | VS_T_NULL), "typify null");
  vs_release(nv);

  /* size. */
  vs_value* str = vs_new_string("abc");
  CHECK(vs_size(str) == 3, "size string");
  vs_release(str);

  /* stringify. */
  vs_value* obj2 = vs_new_map();
  vs_map_set(vs_as_map(obj2), "a", vs_new_int(1));
  char* sout = vs_stringify(obj2, -1);
  CHECK(strcmp(sout, "{a:1}") == 0, "stringify {a:1}");
  free(sout);
  vs_release(obj2);

  /* merge. */
  vs_value* ml = vs_new_list();
  vs_value* o1 = vs_parse_json("{\"a\":1,\"b\":2}", 0);
  vs_value* o2 = vs_parse_json("{\"b\":3,\"c\":4}", 0);
  vs_list_push(vs_as_list(ml), o1);
  vs_list_push(vs_as_list(ml), o2);
  vs_value* mr = vs_merge(ml, VS_MAXDEPTH);
  char* mjs = vs_jsonify(mr, NULL);
  /* Expect a=1,b=3,c=4. */
  CHECK(mjs && strstr(mjs, "\"a\": 1") != NULL, "merge a");
  free(mjs);
  vs_release(mr);
  vs_release(ml);

  printf("smoke: %d/%d passed\n", passed, total);
  return passed == total ? 0 : 1;
}
