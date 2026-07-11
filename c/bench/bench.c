/* Performance bench for the C port. Emits one JSON line per
 * build/bench/README.md; diagnostics go to stderr. Manual refcounting: every
 * value we create or receive from clone/merge/walk/getpath is released, and
 * stringify's char* is freed, so the timed loops don't leak. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "voxgig_struct.h"

static long g_sink = 0;

static int envi(const char *k, int d) {
  const char *v = getenv(k);
  if (!v || !*v) return d;
  char *e;
  long n = strtol(v, &e, 10);
  return (*e == 0) ? (int)n : d;
}

static voxgig_value *build(int w, int d, int leaf) {
  if (d == 0) return voxgig_new_int(leaf);
  voxgig_value *m = voxgig_new_map();
  char key[24];
  for (int i = 0; i < w; i++) {
    snprintf(key, sizeof key, "k%d", i);
    voxgig_map_set(voxgig_as_map(m), key, build(w, d - 1, leaf));
  }
  return m;
}

static long nodecount(int w, int d) {
  long n = 0, p = 1;
  for (int i = 0; i <= d; i++) { n += p; p *= w; }
  return n;
}

static double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}

static voxgig_value *walk_cb(voxgig_value *key, voxgig_value *val,
                             voxgig_value *parent, voxgig_value *path,
                             void *ud) {
  (void)key; (void)parent; (void)ud;
  if (path) g_sink += (long)voxgig_size(path);
  return voxgig_retain(val);
}

typedef struct { double min_ms, median_ms, mean_ms; } stats;

static int cmp_double(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b;
  return (x > y) - (x < y);
}

static stats finish(double *t, int n) {
  qsort(t, n, sizeof(double), cmp_double);
  double s = 0;
  for (int i = 0; i < n; i++) s += t[i];
  stats r = {t[0], t[n / 2], s / n};
  return r;
}

int main(void) {
  int W = envi("BENCH_WIDTH", 5), D = envi("BENCH_DEPTH", 6),
      WARM = envi("BENCH_WARMUP", 3), RUNS = envi("BENCH_RUNS", 21),
      GP = envi("BENCH_GETPATH_ITERS", 2000);

  voxgig_value *tree = build(W, D, 0);
  long nodes = nodecount(W, D);
  voxgig_value *treeA = build(W, D, 1);
  voxgig_value *treeB = build(W, D, 2);

  char *pbuf = malloc((size_t)D * 3 + 1);
  pbuf[0] = 0;
  for (int i = 0; i < D; i++) strcat(pbuf, i ? ".k0" : "k0");
  voxgig_value *pathv = voxgig_new_string(pbuf);

  double *T = malloc((size_t)RUNS * sizeof(double));
  stats sc, sw, sm, ss, sg;

#define MEASURE(OUT, BODY)                                        \
  do {                                                            \
    for (int i = 0; i < WARM; i++) { BODY }                       \
    for (int r = 0; r < RUNS; r++) {                              \
      double a = now_ms();                                        \
      BODY                                                        \
      T[r] = now_ms() - a;                                        \
    }                                                             \
    OUT = finish(T, RUNS);                                        \
  } while (0)

  MEASURE(sc, {
    voxgig_value *c = voxgig_clone(tree);
    g_sink += (c != NULL);
    voxgig_release(c);
  });
  MEASURE(sw, {
    voxgig_value *w = voxgig_walk(tree, walk_cb, NULL, VOXGIG_MAXDEPTH, NULL);
    voxgig_release(w);
  });
  MEASURE(sm, {
    voxgig_value *ml = voxgig_new_list();
    voxgig_list_push(voxgig_as_list(ml), voxgig_retain(treeA));
    voxgig_list_push(voxgig_as_list(ml), voxgig_retain(treeB));
    voxgig_value *mr = voxgig_merge(ml, VOXGIG_MAXDEPTH);
    g_sink += (mr != NULL);
    voxgig_release(mr);
    voxgig_release(ml);
  });
  MEASURE(ss, {
    char *s = voxgig_stringify(tree, -1);
    g_sink += s ? (long)strlen(s) : 0;
    free(s);
  });
  MEASURE(sg, {
    long s = 0;
    for (int i = 0; i < GP; i++) {
      voxgig_value *r = voxgig_getpath(tree, pathv, NULL);
      s += (r != NULL);
      voxgig_release(r);
    }
    g_sink += s;
  });
#undef MEASURE

  fprintf(stderr, "c: sink=%ld\n", g_sink);
  printf("{\"lang\":\"c\",\"runtime\":\"%s\",\"nodes\":%ld,"
         "\"params\":{\"width\":%d,\"depth\":%d,\"warmup\":%d,\"runs\":%d,"
         "\"getpath_iters\":%d},\"ops\":["
         "{\"op\":\"clone\",\"runs\":%d,\"unit_count\":%ld,\"min_ms\":%g,\"median_ms\":%g,\"mean_ms\":%g},"
         "{\"op\":\"walk\",\"runs\":%d,\"unit_count\":%ld,\"min_ms\":%g,\"median_ms\":%g,\"mean_ms\":%g},"
         "{\"op\":\"merge\",\"runs\":%d,\"unit_count\":%ld,\"min_ms\":%g,\"median_ms\":%g,\"mean_ms\":%g},"
         "{\"op\":\"stringify\",\"runs\":%d,\"unit_count\":%ld,\"min_ms\":%g,\"median_ms\":%g,\"mean_ms\":%g},"
         "{\"op\":\"getpath\",\"runs\":%d,\"unit_count\":%d,\"min_ms\":%g,\"median_ms\":%g,\"mean_ms\":%g}"
         "]}\n",
#ifdef __clang__
         "clang " __clang_version__,
#else
         "gcc " __VERSION__,
#endif
         nodes, W, D, WARM, RUNS, GP,
         RUNS, nodes, sc.min_ms, sc.median_ms, sc.mean_ms,
         RUNS, nodes, sw.min_ms, sw.median_ms, sw.mean_ms,
         RUNS, nodes, sm.min_ms, sm.median_ms, sm.mean_ms,
         RUNS, nodes, ss.min_ms, ss.median_ms, ss.mean_ms,
         RUNS, GP, sg.min_ms, sg.median_ms, sg.mean_ms);

  free(T);
  free(pbuf);
  voxgig_release(pathv);
  voxgig_release(tree);
  voxgig_release(treeA);
  voxgig_release(treeB);
  return 0;
}
