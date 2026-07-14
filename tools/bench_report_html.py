#!/usr/bin/env python3
"""Render build/bench/results.json into a self-contained HTML report.

    python3 tools/bench_report_html.py [results.json] [out.html]

Defaults: build/bench/results.json -> build/bench/report.html. The page embeds
the data and renders per-operation log-scale bar charts + a heatmap matrix with
inline SVG/CSS/JS (no external assets), theme-aware.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build/bench/results.json")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "build/bench/report.html")

with open(SRC) as f:
    data = json.load(f)

blob = json.dumps(data, separators=(",", ":"))

HTML = """<title>voxgig/struct — port performance</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root{
    --bg:#e9edf2; --surface:#ffffff; --surface-2:#f4f7fb; --ink:#0f1720;
    --muted:#5a6b7b; --faint:#8496a6; --line:#d8e0e9; --line-2:#e7edf3;
    --accent:#0d8b9c; --accent-soft:#d7eef1;
    --good:#1f9769; --warn:#c1571f; --crit:#cc3a52; --crit-soft:#f7dde2;
    --grid:#eef2f6;
  }
  @media (prefers-color-scheme: dark){
    :root{
      --bg:#0c1117; --surface:#141b23; --surface-2:#1a222c; --ink:#e7eef5;
      --muted:#8ea2b4; --faint:#607283; --line:#26313d; --line-2:#1f2833;
      --accent:#2bb9cb; --accent-soft:#123037; --good:#38c08a; --warn:#df8140;
      --crit:#e8637a; --crit-soft:#3a1e26; --grid:#1b242e;
    }
  }
  :root[data-theme="light"]{
    --bg:#e9edf2; --surface:#ffffff; --surface-2:#f4f7fb; --ink:#0f1720;
    --muted:#5a6b7b; --faint:#8496a6; --line:#d8e0e9; --line-2:#e7edf3;
    --accent:#0d8b9c; --accent-soft:#d7eef1; --good:#1f9769; --warn:#c1571f;
    --crit:#cc3a52; --crit-soft:#f7dde2; --grid:#eef2f6;
  }
  :root[data-theme="dark"]{
    --bg:#0c1117; --surface:#141b23; --surface-2:#1a222c; --ink:#e7eef5;
    --muted:#8ea2b4; --faint:#607283; --line:#26313d; --line-2:#1f2833;
    --accent:#2bb9cb; --accent-soft:#123037; --good:#38c08a; --warn:#df8140;
    --crit:#e8637a; --crit-soft:#3a1e26; --grid:#1b242e;
  }
  *{box-sizing:border-box}
  html{-webkit-text-size-adjust:100%}
  body{
    margin:0; background:var(--bg); color:var(--ink);
    font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
    line-height:1.5; -webkit-font-smoothing:antialiased;
  }
  .mono{font-family:ui-monospace,"SF Mono",Menlo,Consolas,monospace;
    font-variant-numeric:tabular-nums}
  .wrap{max-width:1060px; margin:0 auto; padding:clamp(20px,4vw,52px)}
  header.top{margin-bottom:36px}
  .eyebrow{font-family:ui-monospace,monospace; font-size:12px; letter-spacing:.14em;
    text-transform:uppercase; color:var(--accent); font-weight:600; margin:0 0 10px}
  h1{font-size:clamp(28px,5vw,44px); line-height:1.05; letter-spacing:-.02em;
    margin:0 0 14px; text-wrap:balance; font-weight:680}
  .lede{color:var(--muted); max-width:64ch; font-size:16px; margin:0}
  .lede code{font-family:ui-monospace,monospace; font-size:.9em;
    background:var(--surface-2); padding:1px 5px; border-radius:4px}
  .facts{display:flex; flex-wrap:wrap; gap:10px; margin:26px 0 0}
  .fact{background:var(--surface); border:1px solid var(--line); border-radius:10px;
    padding:12px 16px; min-width:104px}
  .fact .n{font-family:ui-monospace,monospace; font-size:21px; font-weight:640;
    letter-spacing:-.01em; display:block}
  .fact .l{font-size:11.5px; color:var(--faint); text-transform:uppercase;
    letter-spacing:.07em; margin-top:2px}
  h2{font-size:13px; font-family:ui-monospace,monospace; text-transform:uppercase;
    letter-spacing:.12em; color:var(--muted); font-weight:600;
    margin:44px 0 4px; display:flex; align-items:baseline; gap:10px}
  h2 .sub{font-family:system-ui,sans-serif; text-transform:none; letter-spacing:0;
    color:var(--faint); font-size:12.5px; font-weight:400}
  .grid{display:grid; grid-template-columns:repeat(auto-fit,minmax(330px,1fr));
    gap:16px; margin-top:16px}
  .panel{background:var(--surface); border:1px solid var(--line); border-radius:14px;
    padding:18px 18px 14px}
  .panel h3{margin:0; font-size:15px; font-weight:640; letter-spacing:-.01em;
    display:flex; align-items:baseline; justify-content:space-between; gap:8px}
  .panel h3 .unit{font-family:ui-monospace,monospace; font-size:11px;
    color:var(--faint); font-weight:400; text-transform:uppercase; letter-spacing:.06em}
  .chart{margin-top:12px; display:flex; flex-direction:column; gap:6px}
  .row{display:grid; grid-template-columns:74px 1fr; align-items:center;
    gap:10px; cursor:default}
  .row .name{font-family:ui-monospace,monospace; font-size:12px; color:var(--muted);
    text-align:right; white-space:nowrap; overflow:hidden; text-overflow:ellipsis}
  .row.lead .name{color:var(--ink); font-weight:600}
  .bartrack{height:22px; display:flex; align-items:center}
  .bar{height:22px; border-radius:0 5px 5px 0; background:var(--accent);
    flex:0 0 auto; min-width:3px; transition:filter .12s}
  .row.crit .bar{background:var(--crit)}
  .row:hover .bar{filter:brightness(1.08)}
  .val{flex:0 0 auto; font-family:ui-monospace,monospace; font-size:11.5px;
    color:var(--ink); padding-left:8px; white-space:nowrap}
  .tag{display:inline-block; font-family:ui-monospace,monospace; font-size:10px;
    padding:1px 6px; border-radius:999px; margin-left:6px; vertical-align:1px;
    border:1px solid transparent; letter-spacing:.03em}
  .tag.fast{color:var(--good); background:color-mix(in srgb,var(--good) 12%,transparent);
    border-color:color-mix(in srgb,var(--good) 30%,transparent)}
  .tag.slow{color:var(--crit); background:var(--crit-soft);
    border-color:color-mix(in srgb,var(--crit) 34%,transparent)}
  .axisnote{font-family:ui-monospace,monospace; font-size:10.5px; color:var(--faint);
    margin-top:10px; text-align:right}
  /* heatmap */
  .matrix{margin-top:16px; overflow-x:auto; background:var(--surface);
    border:1px solid var(--line); border-radius:14px; padding:6px}
  table{border-collapse:collapse; width:100%; font-size:13px}
  th,td{padding:9px 12px; text-align:right; white-space:nowrap}
  thead th{font-family:ui-monospace,monospace; font-size:11px; text-transform:uppercase;
    letter-spacing:.06em; color:var(--muted); font-weight:600; border-bottom:1px solid var(--line)}
  tbody th{text-align:left; font-family:ui-monospace,monospace; font-weight:600;
    color:var(--ink)}
  tbody td{font-family:ui-monospace,monospace; color:var(--ink);
    border-radius:6px; position:relative}
  tbody tr+tr th,tbody tr+tr td{border-top:1px solid var(--line-2)}
  .cell{display:block; border-radius:6px; padding:5px 8px; margin:1px}
  footer{margin-top:44px; padding-top:18px; border-top:1px solid var(--line);
    color:var(--faint); font-size:12.5px}
  footer .runtimes{display:flex; flex-wrap:wrap; gap:6px 14px; margin:10px 0 16px;
    font-family:ui-monospace,monospace; font-size:11.5px}
  footer .runtimes span{color:var(--muted)}
  a{color:var(--accent)}
</style>

<div class="wrap">
  <header class="top">
    <p class="eyebrow">voxgig/struct · performance</p>
    <h1>Core operations across language ports</h1>
    <p class="lede">Each port builds an identical in-memory tree and times the
      five core operations <em>in-process</em> — startup and compilation
      excluded — following the method of <code>walk-bench</code>: warm up, run
      21 times, take the median. Lower is faster.</p>
    <div class="facts" id="facts"></div>
  </header>

  <h2>By operation <span class="sub">ports ranked fastest → slowest · median ms · log scale</span></h2>
  <div class="grid" id="ops"></div>

  <h2>Median matrix <span class="sub">every port × operation · shaded relative to the fastest port in each column</span></h2>
  <div class="matrix"><table id="matrix"></table></div>

  <footer>
    <div class="runtimes" id="runtimes"></div>
    <div id="method"></div>
  </footer>
</div>

<script id="data" type="application/json">__BLOB__</script>
<script>
(function(){
  const DATA = JSON.parse(document.getElementById('data').textContent);
  const R = DATA.results, P = DATA.params;
  const OPS = ["clone","walk","merge","stringify","getpath"];
  const OP_UNIT = {clone:"ns/node",walk:"ns/node",merge:"ns/node",stringify:"ns/node",getpath:"ns/lookup"};
  const nodes = R.length ? R[0].nodes : 0;
  const fmt = (x)=> x<1 ? x.toFixed(3) : x<10 ? x.toFixed(2) : x<1000 ? x.toFixed(1) : Math.round(x).toLocaleString();
  const opOf = (r,op)=> r.ops.find(o=>o.op===op);

  // facts
  const facts = [
    [R.length, "ports"], [OPS.length, "operations"],
    [nodes.toLocaleString(), "tree nodes"], [P.BENCH_RUNS, "timed runs"],
  ];
  document.getElementById('facts').innerHTML = facts.map(
    ([n,l])=>`<div class="fact"><span class="n mono">${n}</span><span class="l">${l}</span></div>`).join('');

  // per-op bar panels (log scale)
  const grid = document.getElementById('ops');
  OPS.forEach(op=>{
    const rows = R.map(r=>{const o=opOf(r,op); return o?{lang:r.lang,med:o.median_ms,uc:o.unit_count}:null})
                  .filter(Boolean).sort((a,b)=>a.med-b.med);
    const fast = rows[0].med, slow = rows[rows.length-1].med;
    const lmin = Math.log10(fast*0.85), lmax = Math.log10(slow*1.15);
    const span = Math.max(lmax-lmin, 1e-6);
    const bars = rows.map((r,i)=>{
      const w = 4 + 62*(Math.log10(r.med)-lmin)/span;
      const rel = r.med/fast;
      const nsu = r.med*1e6/r.uc;
      const cls = rel>=100 ? ' crit' : (i===0?' lead':'');
      const tag = i===0 ? '<span class="tag fast">fastest</span>'
                 : rel>=100 ? `<span class="tag slow" title="${Math.round(rel).toLocaleString()}× the fastest port">${Math.round(rel).toLocaleString()}×</span>` : '';
      return `<div class="row${cls}" title="${r.lang} · ${op}: ${fmt(r.med)} ms  (${nsu.toFixed(0)} ${OP_UNIT[op].split('/')[0]}/${OP_UNIT[op].split('/')[1]}, ${rel.toFixed(1)}× fastest)">
        <div class="name">${r.lang}</div>
        <div class="bartrack"><div class="bar" style="width:${w}%"></div>
          <span class="val">${fmt(r.med)}${tag}</span></div></div>`;
    }).join('');
    grid.insertAdjacentHTML('beforeend',
      `<div class="panel"><h3>${op}<span class="unit">${OP_UNIT[op]}</span></h3>
        <div class="chart">${bars}</div>
        <div class="axisnote">${fmt(fast)}–${fmt(slow)} ms · log axis</div></div>`);
  });

  // heatmap matrix
  const cols = OPS;
  const fastByOp = {};
  cols.forEach(op=>{ fastByOp[op]=Math.min(...R.map(r=>{const o=opOf(r,op);return o?o.median_ms:Infinity})); });
  const langsSorted = [...R].sort((a,b)=>a.lang.localeCompare(b.lang));
  let html = `<thead><tr><th>port</th>${cols.map(c=>`<th>${c}</th>`).join('')}</tr></thead><tbody>`;
  langsSorted.forEach(r=>{
    html += `<tr><th>${r.lang}</th>` + cols.map(op=>{
      const o=opOf(r,op); if(!o) return '<td>—</td>';
      const rel = o.median_ms/fastByOp[op];
      // sequential accent intensity by log(rel), capped
      const t = Math.min(Math.log10(rel)/3, 1);              // 0 (fastest) .. 1 (>=1000x)
      const bg = `color-mix(in srgb, var(--accent) ${Math.round(6+t*74)}%, transparent)`;
      const ink = t>0.55 ? '#fff' : 'var(--ink)';
      return `<td><span class="cell" style="background:${bg};color:${ink}" title="${rel.toFixed(1)}× fastest">${fmt(o.median_ms)}</span></td>`;
    }).join('') + '</tr>';
  });
  html += '</tbody>';
  document.getElementById('matrix').innerHTML = html;

  // runtimes + method
  document.getElementById('runtimes').innerHTML =
    [...R].sort((a,b)=>a.lang.localeCompare(b.lang))
      .map(r=>`<span>${r.lang} · ${r.runtime}</span>`).join('');
  document.getElementById('method').innerHTML =
    `Workload: balanced map tree width ${P.BENCH_WIDTH} × depth ${P.BENCH_DEPTH}
     (${nodes.toLocaleString()} nodes), ${P.BENCH_WARMUP} warm-up + ${P.BENCH_RUNS} timed
     runs per op, ${Number(P.BENCH_GETPATH_ITERS).toLocaleString()} getpath lookups/run.
     Wall-clock medians on one machine — read them relative, not absolute.
     Regenerate with <code style="font-family:ui-monospace,monospace">make bench</code>.`;
})();
</script>
"""

out_html = HTML.replace("__BLOB__", blob)
with open(OUT, "w") as f:
    f.write(out_html)
print("wrote", OUT, "(%d bytes)" % len(out_html))
