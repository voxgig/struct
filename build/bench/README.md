# Performance benchmark harness

Cross-language micro-benchmarks for the core `voxgig/struct` operations. Every
port builds the **same** in-memory workload and times each operation
**in-process** — process startup and compilation are excluded — using the same
method as `typescript/test/walk-bench.test.ts` (build once, warm up, run N
times, report the median).

## Run it

```
make bench                       # every port that has a bench target
make bench-go                    # one port
python3 tools/bench.py go rust   # a subset, directly
BENCH_RUNS=11 make bench         # override the workload
```

Outputs (git-ignored):

- `build/bench/results.json` — raw measurements from every port.
- `build/bench/REPORT.md` — rendered Markdown comparison (ranking per op, ms matrix).
- `build/bench/report.html` — self-contained visual report (log-scale bars per
  operation + a heatmap matrix; rendered by `tools/bench_report_html.py`).

## Workload (identical across ports)

Controlled by environment variables so no port needs to parse a config file —
the driver sets them and `make` passes them through. Each bench hard-codes the
same defaults for standalone runs.

| var | meaning | default |
|-----|---------|--------:|
| `BENCH_WIDTH` | tree fan-out | `5` |
| `BENCH_DEPTH` | tree depth | `6` |
| `BENCH_WARMUP` | untimed warm-up runs | `3` |
| `BENCH_RUNS` | timed runs per op | `21` |
| `BENCH_GETPATH_ITERS` | getpath lookups per timed run | `2000` |

The workload is a **balanced tree of maps**: each non-leaf map has `WIDTH`
children keyed `k0..k{WIDTH-1}`; leaves are integers. `width=5, depth=6` →
19 531 nodes. Operations timed:

| op | what runs (one timed run) | unit_count |
|----|---------------------------|-----------|
| `clone` | deep-copy the whole tree | node count |
| `walk` | full walk; callback reads `path.length` into a sink | node count |
| `merge` | `merge([a, b])` of two same-shape trees (a mutated in place) | node count |
| `stringify` | serialise the whole tree | node count |
| `getpath` | `GETPATH_ITERS` lookups of a fixed leaf path | iterations |

## Output contract

Each bench prints **exactly one line of JSON** to stdout (other output — build
logs, warnings — must go to stderr; the driver takes the last stdout line
starting with `{`):

```json
{
  "lang": "typescript",
  "runtime": "node v22.22.2",
  "nodes": 19531,
  "params": {"width":5,"depth":6,"warmup":3,"runs":21,"getpath_iters":2000},
  "ops": [
    {"op":"clone","runs":21,"unit_count":19531,"min_ms":1.2,"median_ms":1.4,"mean_ms":1.5},
    {"op":"walk","runs":21,"unit_count":19531,"min_ms":0.8,"median_ms":0.9,"mean_ms":0.9},
    {"op":"merge","runs":21,"unit_count":19531,"min_ms":2.0,"median_ms":2.2,"mean_ms":2.3},
    {"op":"stringify","runs":21,"unit_count":19531,"min_ms":3.0,"median_ms":3.1,"mean_ms":3.2},
    {"op":"getpath","runs":21,"unit_count":2000,"min_ms":4.0,"median_ms":4.2,"mean_ms":4.3}
  ]
}
```

Times are milliseconds. `unit_count` is the number of work units in one run
(node count, or lookup count for `getpath`) so the report can normalise to
ns/unit.

## Adding a port

1. Write `<lang>/bench/…` that reads the five env vars (falling back to the
   defaults above), builds the tree, times the five ops with a **monotonic**
   high-resolution clock, and prints the JSON contract line.
2. Add a `bench` target to `<lang>/Makefile` that builds + runs it, emitting
   only the JSON on stdout (send compiler output to stderr).
3. Add the port to `DEFAULT_LANGS` in `tools/bench.py`.

All 22 ports are wired: typescript, javascript, python, ruby, php, go, rust,
java, c, cpp, perl, haskell, lua, dart, csharp, clojure, ocaml, elixir, zig,
swift, kotlin, scala.

A few ports' bench targets use a standalone compiler rather than the port's
usual build tool, so the harness runs without network access, and expose an
override:

- **kotlin** — `kotlinc` + `java` (not Gradle). `KOTLIN_STDLIB` is the runtime
  jar (defaults to a standard kotlinc `lib/`).
- **scala** — `scalac` + `java` (not scala-cli). `SCALA_RUNTIME` is the run
  classpath (scala3 + scala2 stdlib jars).
- **clojure** — `clojure.main` with `src:bench` on the classpath.
- **ocaml** — native `ocamlopt`; **cpp** — `g++ -O2`; **zig** —
  `zig build perfbench -Doptimize=ReleaseFast`; **swift** — `swift run -c release`.
