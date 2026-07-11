// Performance bench for the C++ port. Emits one JSON line per
// build/bench/README.md; diagnostics go to stderr. Header-only library.
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "voxgig_struct.hpp"

using namespace voxgig::structlib;

static long g_sink = 0;

static int envi(const char* k, int d) {
  const char* v = getenv(k);
  if (!v || !*v) return d;
  char* e;
  long n = strtol(v, &e, 10);
  return *e == 0 ? (int)n : d;
}

static Value buildTree(int w, int d, int leaf) {
  if (d == 0) return Value((int64_t)leaf);
  Value m = jm({});
  for (int i = 0; i < w; i++) setprop(m, Value("k" + std::to_string(i)), buildTree(w, d - 1, leaf));
  return m;
}

static long nodecount(int w, int d) {
  long n = 0, p = 1;
  for (int i = 0; i <= d; i++) { n += p; p *= w; }
  return n;
}

static double now_ms() {
  return std::chrono::duration<double, std::milli>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

struct Stats { double mn, md, mean; };

template <class F>
static Stats measure(int warm, int runs, F f) {
  for (int i = 0; i < warm; i++) f();
  std::vector<double> t(runs);
  for (int r = 0; r < runs; r++) {
    double a = now_ms();
    f();
    t[r] = now_ms() - a;
  }
  std::sort(t.begin(), t.end());
  double s = 0;
  for (double x : t) s += x;
  return {t[0], t[runs / 2], s / runs};
}

int main() {
  int W = envi("BENCH_WIDTH", 5), D = envi("BENCH_DEPTH", 6),
      WARM = envi("BENCH_WARMUP", 3), RUNS = envi("BENCH_RUNS", 21),
      GP = envi("BENCH_GETPATH_ITERS", 2000);

  Value tree = buildTree(W, D, 0);
  long nodes = nodecount(W, D);
  Value mlist = jt({buildTree(W, D, 1), buildTree(W, D, 2)});
  std::string ps;
  for (int i = 0; i < D; i++) { if (i) ps += "."; ps += "k0"; }
  Value path(ps);
  WalkApply cb = [&](const Value&, const Value& v, const Value&,
                     const std::vector<std::string>& pth) -> Value {
    g_sink += (long)pth.size();
    return v;
  };

  const char* names[] = {"clone", "walk", "merge", "stringify", "getpath"};
  long ucs[] = {nodes, nodes, nodes, nodes, GP};
  Stats st[5];
  st[0] = measure(WARM, RUNS, [&]() { clone(tree); g_sink++; });
  st[1] = measure(WARM, RUNS, [&]() { walk_v(tree, cb); });
  st[2] = measure(WARM, RUNS, [&]() { merge_v(mlist); g_sink++; });
  st[3] = measure(WARM, RUNS, [&]() { g_sink += (long)stringify(tree).size(); });
  st[4] = measure(WARM, RUNS, [&]() {
    long a = 0;
    for (int i = 0; i < GP; i++) { Value r = getpath_v(tree, path); (void)r; a++; }
    g_sink += a;
  });

  fprintf(stderr, "cpp: sink=%ld\n", g_sink);
  printf("{\"lang\":\"cpp\",\"runtime\":\"g++ %d.%d.%d\",\"nodes\":%ld,"
         "\"params\":{\"width\":%d,\"depth\":%d,\"warmup\":%d,\"runs\":%d,\"getpath_iters\":%d},"
         "\"ops\":[",
         __GNUC__, __GNUC_MINOR__, __GNUC_PATCHLEVEL__, nodes, W, D, WARM, RUNS, GP);
  for (int i = 0; i < 5; i++) {
    if (i) printf(",");
    printf("{\"op\":\"%s\",\"runs\":%d,\"unit_count\":%ld,\"min_ms\":%g,\"median_ms\":%g,\"mean_ms\":%g}",
           names[i], RUNS, ucs[i], st[i].mn, st[i].md, st[i].mean);
  }
  printf("]}\n");
  return 0;
}
