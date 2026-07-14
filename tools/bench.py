#!/usr/bin/env python3
"""Cross-language performance benchmark driver for voxgig/struct.

Runs each port's `make bench` target, which builds a fixed in-memory workload
and times the core operations (clone, walk, merge, getpath, stringify) entirely
in-process (startup/compile excluded). Each bench prints ONE line of JSON to
stdout following the shared contract in build/bench/README.md. This driver
collects those lines, writes build/bench/results.json, and renders a Markdown
report (build/bench/REPORT.md).

The workload is identical across ports and controlled by environment variables
(so no port needs a JSON parser to read it):

  BENCH_WIDTH         tree fan-out            (default 5)
  BENCH_DEPTH         tree depth              (default 6)
  BENCH_WARMUP        untimed warm-up runs    (default 3)
  BENCH_RUNS          timed runs per op       (default 21)
  BENCH_GETPATH_ITERS getpath lookups per run (default 2000)

Usage:
  python3 tools/bench.py                 # all default (verified) ports
  python3 tools/bench.py go rust python  # only these ports
  BENCH_RUNS=11 python3 tools/bench.py   # override workload
"""

import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Every port has a bench runner + `bench` Makefile target following the
# build/bench/README.md contract.
DEFAULT_LANGS = [
    "typescript", "javascript", "python", "ruby", "php",
    "go", "rust", "java", "c", "cpp", "perl", "haskell",
    "lua", "dart", "csharp", "clojure", "ocaml", "elixir",
    "zig", "swift", "kotlin", "scala",
]

DEFAULTS = {
    "BENCH_WIDTH": "5",
    "BENCH_DEPTH": "6",
    "BENCH_WARMUP": "3",
    "BENCH_RUNS": "21",
    # 2000 keeps the fastest ports well above clock noise while still letting
    # slow-getpath ports (e.g. ruby, whose getpath is O(store-size)) finish
    # within the per-port timeout. Push higher via BENCH_GETPATH_ITERS for a
    # finer signal on the fast ports; ns/lookup stays comparable either way.
    "BENCH_GETPATH_ITERS": "2000",
}

# Per-op unit label used when normalising to ns/unit in the report.
OP_UNIT = {
    "clone": "node", "walk": "node", "merge": "node",
    "stringify": "node", "getpath": "lookup",
}
OP_ORDER = ["clone", "walk", "merge", "stringify", "getpath"]

# Bench builds can compile from scratch, so allow generous time per port.
TIMEOUT_S = int(os.environ.get("BENCH_TIMEOUT", "1200"))


def run_lang(lang, env):
    """Build + run one port's bench; return (result_dict | None, error_str)."""
    d = os.path.join(ROOT, lang)
    if not os.path.isdir(d):
        return None, "no such port directory"
    t0 = time.time()
    try:
        p = subprocess.run(
            ["make", "-s", "-C", d, "bench"],
            env=env, capture_output=True, text=True, timeout=TIMEOUT_S,
        )
    except subprocess.TimeoutExpired:
        return None, f"timed out after {TIMEOUT_S}s"
    except FileNotFoundError as e:
        return None, str(e)
    wall = time.time() - t0
    # The JSON contract line is the last stdout line beginning with '{'.
    line = next((ln for ln in reversed(p.stdout.splitlines())
                 if ln.strip().startswith("{")), None)
    if line is None:
        tail = (p.stderr.strip() or p.stdout.strip() or "no output")
        return None, f"no JSON line (rc={p.returncode}): {tail[-400:]}"
    try:
        res = json.loads(line)
    except json.JSONDecodeError as e:
        return None, f"bad JSON: {e}: {line[:200]}"
    res["_build_wall_s"] = round(wall, 1)
    return res, ""


def collect(langs, env):
    results, errors = [], {}
    for lang in langs:
        sys.stderr.write(f"  bench {lang} ... ")
        sys.stderr.flush()
        res, err = run_lang(lang, env)
        if res is None:
            errors[lang] = err
            sys.stderr.write(f"SKIP ({err.splitlines()[0][:60]})\n")
        else:
            results.append(res)
            meds = {o["op"]: o["median_ms"] for o in res.get("ops", [])}
            sys.stderr.write(
                "ok  " + "  ".join(f"{k}={meds[k]:.2f}ms" for k in OP_ORDER
                                   if k in meds) + "\n")
    return results, errors


def fmt_ms(x):
    return f"{x:.3f}" if x < 1 else (f"{x:.2f}" if x < 100 else f"{x:.1f}")


def ns_per_unit(median_ms, unit_count):
    return median_ms * 1e6 / unit_count if unit_count else float("nan")


def render_report(results, errors, params, langs):
    lines = []
    A = lines.append
    A("# voxgig/struct — cross-port performance report\n")
    A("Core operations timed **in-process** (startup and compilation excluded), "
      "following the same method as `typescript/test/walk-bench.test.ts`: a fixed "
      "workload is built once, warmed up, then each operation is run "
      f"`{params['BENCH_RUNS']}` times and the **median** reported.\n")

    nodes = results[0]["nodes"] if results else "?"
    A("## Workload\n")
    A(f"- Balanced map tree: width **{params['BENCH_WIDTH']}**, depth "
      f"**{params['BENCH_DEPTH']}** → **{nodes:,}** nodes"
      if isinstance(nodes, int) else f"- tree nodes: {nodes}")
    A(f"- Warm-up runs: {params['BENCH_WARMUP']}  ·  timed runs: "
      f"{params['BENCH_RUNS']}  ·  getpath lookups/run: "
      f"{int(params['BENCH_GETPATH_ITERS']):,}")
    A(f"- Ports benchmarked: **{len(results)}** of {len(langs)} requested\n")

    # Per-operation ranking tables (median ms, ns/unit, relative to fastest).
    A("## Results by operation\n")
    A("Lower is better. `rel` = median relative to the fastest port for that "
      "operation. `ns/unit` normalises by work done (per node, or per lookup "
      "for getpath).\n")
    for op in OP_ORDER:
        rows = []
        for r in results:
            o = next((x for x in r.get("ops", []) if x["op"] == op), None)
            if o:
                rows.append((r["lang"], o["median_ms"], o["min_ms"],
                             o.get("unit_count", r["nodes"])))
        if not rows:
            continue
        rows.sort(key=lambda t: t[1])
        fastest = rows[0][1]
        unit = OP_UNIT.get(op, "unit")
        A(f"### {op}\n")
        A(f"| # | port | median (ms) | min (ms) | ns/{unit} | rel |")
        A("|--:|------|------------:|---------:|---------:|----:|")
        for i, (lang, med, mn, uc) in enumerate(rows, 1):
            rel = med / fastest if fastest else float("nan")
            A(f"| {i} | {lang} | {fmt_ms(med)} | {fmt_ms(mn)} | "
              f"{ns_per_unit(med, uc):.1f} | {rel:.1f}× |")
        A("")

    # Median-ms matrix (ports × ops) for an at-a-glance overview.
    A("## Median (ms) matrix\n")
    A("| port | " + " | ".join(OP_ORDER) + " |")
    A("|------|" + "|".join(["--:"] * len(OP_ORDER)) + "|")
    for r in sorted(results, key=lambda r: r["lang"]):
        cells = []
        for op in OP_ORDER:
            o = next((x for x in r.get("ops", []) if x["op"] == op), None)
            cells.append(fmt_ms(o["median_ms"]) if o else "—")
        A(f"| {r['lang']} | " + " | ".join(cells) + " |")
    A("")

    A("## Runtimes\n")
    A("| port | runtime | build+run (s) |")
    A("|------|---------|--------------:|")
    for r in sorted(results, key=lambda r: r["lang"]):
        A(f"| {r['lang']} | {r.get('runtime', '?')} | "
          f"{r.get('_build_wall_s', '?')} |")
    A("")

    if errors:
        A("## Not benchmarked\n")
        for lang, err in errors.items():
            A(f"- **{lang}**: {err.splitlines()[0][:120]}")
        A("")

    A("---\n")
    A("_Numbers are wall-clock medians on the machine that ran the harness; use "
      "them for relative comparison, not as absolute guarantees. Regenerate with "
      "`make bench` (all ports) or `python3 tools/bench.py <ports…>`._")
    return "\n".join(lines) + "\n"


def main(argv):
    langs = argv or DEFAULT_LANGS
    env = dict(os.environ)
    for k, v in DEFAULTS.items():
        env.setdefault(k, v)
    params = {k: env[k] for k in DEFAULTS}

    sys.stderr.write(f"workload: {params}\n")
    results, errors = collect(langs, env)

    outdir = os.path.join(ROOT, "build", "bench")
    os.makedirs(outdir, exist_ok=True)
    payload = {"params": params, "results": results, "errors": errors}
    with open(os.path.join(outdir, "results.json"), "w") as f:
        json.dump(payload, f, indent=2)
    report = render_report(results, errors, params, langs)
    with open(os.path.join(outdir, "REPORT.md"), "w") as f:
        f.write(report)

    # Also render the self-contained HTML report (best-effort).
    html_out = os.path.join(outdir, "report.html")
    try:
        subprocess.run(
            [sys.executable, os.path.join(ROOT, "tools", "bench_report_html.py"),
             os.path.join(outdir, "results.json"), html_out],
            check=True, capture_output=True, text=True,
        )
    except (subprocess.CalledProcessError, OSError) as e:
        sys.stderr.write(f"(html report skipped: {e})\n")
        html_out = None

    outs = "results.json, REPORT.md" + (", report.html" if html_out else "")
    sys.stderr.write(f"\nwrote {outdir}/{{{outs}}}\n")
    if not results:
        sys.stderr.write("no ports produced results\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
