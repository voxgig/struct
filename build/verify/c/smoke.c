/* Smoke client for the PUBLISHED C port, built against the source vendored
 * from the git tag c/v<VERSION>. The Makefile compiles this together with
 * the vendored c/src C files (with -I on <topdir>/c/src). */

#include "voxgig_struct.h"

#include <stdio.h>
#include <string.h>

int main(void) {
  /* store = { db: { host: "localhost" } } */
  voxgig_value* store = voxgig_parse_json("{\"db\":{\"host\":\"localhost\"}}", 0);
  voxgig_value* path = voxgig_new_string("db.host");
  voxgig_value* got = voxgig_getpath(store, path, NULL);

  const char* s = voxgig_as_string(got);
  int ok = (s != NULL && strcmp(s, "localhost") == 0);

  if (ok) {
    printf("OK c: getpath(db.host) = localhost\n");
  } else {
    fprintf(stderr, "FAIL c: getpath(db.host) = %s (want localhost)\n",
            s ? s : "(non-string)");
  }

  voxgig_release(got);
  voxgig_release(path);
  voxgig_release(store);
  return ok ? 0 : 1;
}
