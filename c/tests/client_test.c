/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

/*
 * The client path: `DEF.client`, client-scoped options, and `contextify`.
 *
 * This port had no such test. Every migrated port runs this group
 * (javascript/test/client.test.js, php/tests/ClientTest.php,
 * lua/test/client_test.lua, csharp/tests/ClientTest.cs,
 * java/src/test/ClientTest.java, perl/t/client.t), and it is the only thing
 * that exercises subject resolution through a PROVIDER rather than through a
 * callback the test file hands over - so nothing here had ever checked that a
 * corpus `client` key resolves, or that a `DEF.client` entry's options reach
 * the subject.
 *
 * Two entries, differing only in which client answers: the default one with no
 * options gives "ZED_BAR0", and client "a" - carrying `{foo: 1}` - gives
 * "ZED1_BAR1".
 *
 * The subject here talks to omni DIRECTLY, in omni's own value type: the
 * runner resolves it by name off the provider, so there is no `in` to convert
 * and no result for the bridge to convert back.
 */

#include "omni.h"

#include <stdio.h>
#include <string.h>

/* A provider carrying one client's options, plus the subject it hands out. */
typedef struct client_provider {
  omni_provider base;
  omni_subject subject;
  omni_pool* pool;
  omni_json* options;
} client_provider;

static client_provider* provider_new(omni_pool* pool, omni_json* options);

/* The SDK's `check` subject. The options are the ones a `DEF.client` entry
 * carried; the context is the entry's own `ctx`. */
static omni_result check_call(omni_subject* self, omni_json** args, size_t nargs) {
  client_provider* prov = (client_provider*)self->data;
  omni_result result = {NULL, NULL};

  omni_json* foo = omni_map_get(prov->options, "foo");
  const char* foos = omni_isabsent(foo) ? "" : omni_stringify(prov->pool, foo);

  const char* bars = "0";
  if (0 < nargs) {
    omni_json* bar = omni_map_get(omni_map_get(args[0], "meta"), "bar");
    if (!omni_isnone(bar))
      bars = omni_stringify(prov->pool, bar);
  }

  char zed[256];
  snprintf(zed, sizeof(zed), "ZED%s_%s", foos, bars);

  omni_json* out = omni_map(prov->pool);
  omni_map_set(out, "zed", omni_str(prov->pool, zed));
  result.val = out;
  return result;
}

static omni_subject* provider_subject(omni_provider* self, const char* name) {
  client_provider* prov = (client_provider*)self;
  if (0 != strcmp(name, "check"))
    return NULL;
  return &prov->subject;
}

/* A DEF.client entry becomes another provider, carrying its options. */
static omni_provider* provider_client(omni_provider* self, omni_json* options) {
  client_provider* prov = (client_provider*)self;
  return (omni_provider*)provider_new(prov->pool, options);
}

/* This port adds nothing to a context; the hook must exist so omni installs
 * `client` on it. */
static omni_json* provider_contextify(omni_provider* self, omni_json* val) {
  (void)self;
  return val;
}

static client_provider* provider_new(omni_pool* pool, omni_json* options) {
  client_provider* prov = (client_provider*)omni_pool_alloc(pool, sizeof(client_provider));
  prov->base.subject = provider_subject;
  prov->base.client = provider_client;
  prov->base.contextify = provider_contextify;
  prov->base.data = NULL;
  prov->subject.call = check_call;
  prov->subject.data = prov;
  prov->pool = pool;
  prov->options = options ? options : omni_map(pool);
  return prov;
}

int main(void) {
  char* err = NULL;
  omni_pool* pool = omni_pool_new();

  client_provider* provider = provider_new(pool, omni_map(pool));

  omni_runner* runner =
      omni_make_runner(pool, "../build/test/test.json", NULL, (omni_provider*)provider, &err);
  if (NULL == runner) {
    fprintf(stderr, "struct: %s\n", err ? err : "cannot load the corpus");
    return 1;
  }

  omni_runpack* pack = omni_runner_run(runner, "check", NULL, &err);
  if (NULL == pack) {
    fprintf(stderr, "struct: %s\n", err ? err : "cannot resolve the check spec");
    return 1;
  }

  omni_flags flags = omni_flags_default();
  flags.name = "check.basic";

  /* No subject: the runner resolves it by name off the provider, which is the
   * whole point of the group. */
  int rc = omni_runsetflags(pack, omni_map_get(omni_spec(pack), "basic"), flags, NULL, &err);

  if (0 == rc) {
    printf("\n===== struct client =====\n  ok   check.basic\n=========================\n\n");
  } else {
    printf(
        "\n===== struct client =====\n  FAIL check.basic\n       %s\n=========================\n\n",
        err ? err : "(no message)");
  }

  omni_pool_free(pool);
  return 0 == rc ? 0 : 1;
}
