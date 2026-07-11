# Performance bench for the Python port. Emits one JSON line per
# build/bench/README.md; diagnostics go to stderr.
import json
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from voxgig_struct.voxgig_struct import clone, walk, merge, getpath, stringify


def envi(k, d):
    try:
        return int(os.environ[k])
    except (KeyError, ValueError):
        return d


W = envi("BENCH_WIDTH", 5)
D = envi("BENCH_DEPTH", 6)
WARM = envi("BENCH_WARMUP", 3)
RUNS = envi("BENCH_RUNS", 21)
GP = envi("BENCH_GETPATH_ITERS", 50000)


def build(w, d, leaf):
    if d == 0:
        return leaf
    return {"k" + str(i): build(w, d - 1, leaf) for i in range(w)}


def nodecount(w, d):
    n, p = 0, 1
    for _ in range(d + 1):
        n += p
        p *= w
    return n


sink = [0]


def measure(fn):
    for _ in range(WARM):
        fn()
    t = []
    for _ in range(RUNS):
        a = time.perf_counter_ns()
        fn()
        b = time.perf_counter_ns()
        t.append((b - a) / 1e6)
    t.sort()
    return {"min_ms": t[0], "median_ms": t[len(t) // 2],
            "mean_ms": sum(t) / len(t)}


tree = build(W, D, 0)
nodes = nodecount(W, D)
treeA = build(W, D, 1)
treeB = build(W, D, 2)
path = ".".join(["k0"] * D)


def cb(key, val, parent, p):
    sink[0] += len(p)
    return val


def op_getpath():
    s = 0
    for _ in range(GP):
        s += 1 if getpath(tree, path) == 0 else 0
    sink[0] += s


specs = [
    ("clone", nodes, lambda: sink.__setitem__(0, sink[0] + (1 if clone(tree) else 0))),
    ("walk", nodes, lambda: walk(tree, cb)),
    ("merge", nodes, lambda: sink.__setitem__(0, sink[0] + (1 if merge([treeA, treeB]) else 0))),
    ("stringify", nodes, lambda: sink.__setitem__(0, sink[0] + len(stringify(tree)))),
    ("getpath", GP, op_getpath),
]
ops = [dict(op=o, runs=RUNS, unit_count=uc, **measure(fn)) for o, uc, fn in specs]

sys.stderr.write("python: sink=%d\n" % sink[0])
print(json.dumps({
    "lang": "python",
    "runtime": "python " + sys.version.split()[0],
    "nodes": nodes,
    "params": {"width": W, "depth": D, "warmup": WARM, "runs": RUNS,
               "getpath_iters": GP},
    "ops": ops,
}))
