# Benchmark for walk() on wide and deep trees.
# Not run by default. To enable:
#   WALK_BENCH=1 python -m unittest tests.test_walk_bench
# Or via make target:
#   make bench
#
# Sizes are configurable with env vars to keep runs tractable on slow
# Python backends. Defaults mirror the TypeScript reference benchmark.
#   WALK_BENCH_WD_WIDTH / WALK_BENCH_WD_DEPTH   (wide+deep, default 8 / 6)
#   WALK_BENCH_VW_WIDTH / WALK_BENCH_VW_DEPTH   (very-wide, default 1000 / 2)
#   WALK_BENCH_VD_WIDTH / WALK_BENCH_VD_DEPTH   (very-deep, default 2 / 20)
#   WALK_BENCH_RUNS_WD / WALK_BENCH_RUNS_VW / WALK_BENCH_RUNS_VD
#   WALK_BENCH_WARMUP  (default 2; set to 0 for very large scenarios)

import os
import time
import unittest

from voxgig_struct.voxgig_struct import walk


BENCH = '1' == os.environ.get('WALK_BENCH', '')


def buildTree(width, depth):
    """Build a balanced tree of maps with given width and depth.
    Total nodes: (width^(depth+1) - 1) / (width - 1).
    """
    if 0 == depth:
        return 0
    out = {}
    for i in range(width):
        out['k' + str(i)] = buildTree(width, depth - 1)
    return out


def countNodes(val):
    if not isinstance(val, (dict, list)):
        return 1
    n = 1
    if isinstance(val, dict):
        for k in val.keys():
            n += countNodes(val[k])
    else:
        for v in val:
            n += countNodes(v)
    return n


def measure(label, tree, runs, warmup=None):
    # Touch path to simulate a minimal consumer. Using len(path) keeps the
    # work O(1) so we measure walk overhead rather than callback overhead.
    sink = [0]

    def cb(_k, v, _p, path):
        sink[0] += len(path)
        return v

    if warmup is None:
        warmup = int(os.environ.get('WALK_BENCH_WARMUP', '2'))
    for _ in range(warmup):
        walk(tree, cb)

    times_ms = []
    for _ in range(runs):
        t0 = time.perf_counter_ns()
        walk(tree, cb)
        t1 = time.perf_counter_ns()
        times_ms.append((t1 - t0) / 1e6)
    times_ms.sort()
    median = times_ms[len(times_ms) // 2]
    tmin = times_ms[0]
    tmax = times_ms[-1]
    mean = sum(times_ms) / len(times_ms)

    nodes = countNodes(tree)
    ns_per_node = (median * 1e6) / nodes

    print(
        f"[walk-bench] {label}: nodes={nodes} runs={runs} "
        f"min={tmin:.2f}ms median={median:.2f}ms "
        f"mean={mean:.2f}ms max={tmax:.2f}ms "
        f"ns/node={ns_per_node:.1f} sink={sink[0]}"
    )


def _env_int(name, default):
    try:
        return int(os.environ.get(name, str(default)))
    except (TypeError, ValueError):
        return default


@unittest.skipUnless(BENCH, "WALK_BENCH=1 not set")
class TestWalkBench(unittest.TestCase):

    def test_walk_bench_a_wide_and_deep(self):
        w = _env_int('WALK_BENCH_WD_WIDTH', 8)
        d = _env_int('WALK_BENCH_WD_DEPTH', 6)
        runs = _env_int('WALK_BENCH_RUNS_WD', 7)
        # Default w=8, d=6 -> ~299k nodes.
        wideDeep = buildTree(w, d)
        measure(f'wide+deep (w={w},d={d})', wideDeep, runs)

    def test_walk_bench_b_very_wide(self):
        w = _env_int('WALK_BENCH_VW_WIDTH', 1000)
        d = _env_int('WALK_BENCH_VW_DEPTH', 2)
        runs = _env_int('WALK_BENCH_RUNS_VW', 7)
        # Default w=1000, d=2 -> ~1,001,001 nodes, shallow.
        wide = buildTree(w, d)
        measure(f'wide (w={w},d={d})', wide, runs)

    def test_walk_bench_c_very_deep(self):
        w = _env_int('WALK_BENCH_VD_WIDTH', 2)
        d = _env_int('WALK_BENCH_VD_DEPTH', 20)
        runs = _env_int('WALK_BENCH_RUNS_VD', 5)
        # MAXDEPTH in walk is 32. Default w=2, d=20 -> 2,097,151 nodes.
        deep = buildTree(w, d)
        measure(f'deep (w={w},d={d})', deep, runs)


if __name__ == '__main__':
    unittest.main()
