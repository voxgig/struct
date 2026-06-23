/* Smoke test for the C test provider port. Prints summary stats that must
 * match the canonical TS output documented in PROVIDER.md.
 *
 * Build & run (from the repo root so the relative corpus path resolves):
 *   gcc -std=c11 -O2 test/proto/c/smoke.c -o /tmp/c_smoke -lm
 *   ./...  (run from /home/user/struct)
 *
 * An explicit corpus path may be passed as argv[1].
 */

#define PROVIDER_IMPL
#include "provider.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char* input_kind_name(input_kind k) {
  switch (k) {
    case IN_IN: return "in";
    case IN_ARGS: return "args";
    case IN_CTX: return "ctx";
  }
  return "?";
}

static const char* expect_kind_name(expect_kind k) {
  switch (k) {
    case EX_VALUE: return "value";
    case EX_ERROR: return "error";
    case EX_MATCH: return "match";
    case EX_ABSENT: return "absent";
  }
  return "?";
}

int main(int argc, char** argv) {
  const char* path = argc > 1 ? argv[1] : NULL;
  Provider* prov = provider_load(path);
  if (!prov) {
    fprintf(stderr, "failed to load corpus (%s)\n",
            path ? path : "build/test/test.json");
    return 1;
  }

  size_t nfns = 0;
  const char** fns = provider_functions(prov, &nfns);
  printf("functions: ");
  for (size_t i = 0; i < nfns; i++) {
    printf("%s%s", i ? ", " : "", fns[i]);
  }
  printf("\n");

  int total = 0;
  /* expect kinds in fixed order: value, error, match, absent */
  int ev = 0, ee = 0, em = 0, ea = 0;
  /* input kinds: in, args, ctx */
  int ii = 0, ia = 0, ic = 0;

  for (size_t f = 0; f < nfns; f++) {
    size_t ne = 0;
    Entry* entries = provider_entries(prov, fns[f], NULL, &ne);
    for (size_t e = 0; e < ne; e++) {
      total++;
      switch (entries[e].expect.kind) {
        case EX_VALUE: ev++; break;
        case EX_ERROR: ee++; break;
        case EX_MATCH: em++; break;
        case EX_ABSENT: ea++; break;
      }
      switch (entries[e].input.kind) {
        case IN_IN: ii++; break;
        case IN_ARGS: ia++; break;
        case IN_CTX: ic++; break;
      }
    }
  }

  printf("total entries: %d ; ", total);
  printf("expect kinds: value=%d, absent=%d, match=%d, error=%d ; ", ev, ea, em, ee);
  printf("input kinds: in=%d", ii);
  if (ia) {
    printf(", args=%d", ia);
  }
  if (ic) {
    printf(", ctx=%d", ic);
  }
  printf("\n");

  size_t ne = 0;
  Entry* gp = provider_entries(prov, "getpath", "basic", &ne);
  if (ne > 0) {
    Entry* e = &gp[0];
    char* val = e->expect.value ? jv_stringify(e->expect.value) : NULL;
    const char* valstr = val ? val : "(none)";
    printf("getpath/basic[0]: id=%s, doc=%s, input.kind=%s, expect.kind=%s, expect.value=%s\n",
           e->id ? e->id : "(null)",
           e->doc ? "true" : "false",
           input_kind_name(e->input.kind),
           expect_kind_name(e->expect.kind),
           valstr);
    free(val);
  }

  return 0;
}
