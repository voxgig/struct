// Performance bench for the JavaScript port (runs against src/struct.js).
// Emits one JSON line per build/bench/README.md.
// All diagnostics go to stderr so stdout carries only the JSON contract line.
'use strict'
runBench('javascript', require('../src/struct'), 'node ' + process.version)

// Shared node bench body — the typescript port uses an identical function,
// differing only in the require() path and the lang label above.
function runBench(lang, S, runtime) {
  const envi = (k, d) => {
    const v = parseInt(process.env[k], 10)
    return Number.isFinite(v) ? v : d
  }
  const W = envi('BENCH_WIDTH', 5)
  const D = envi('BENCH_DEPTH', 6)
  const WARM = envi('BENCH_WARMUP', 3)
  const RUNS = envi('BENCH_RUNS', 21)
  const GP = envi('BENCH_GETPATH_ITERS', 2000)

  const buildTree = (w, d, leaf) => {
    if (0 === d) return leaf
    const o = {}
    for (let i = 0; i < w; i++) o['k' + i] = buildTree(w, d - 1, leaf)
    return o
  }
  const count = (v) => {
    if (null === v || 'object' !== typeof v) return 1
    let n = 1
    for (const k of Object.keys(v)) n += count(v[k])
    return n
  }

  let sink = 0
  const now = () => process.hrtime.bigint()

  const measure = (fn) => {
    for (let i = 0; i < WARM; i++) fn()
    const t = []
    for (let r = 0; r < RUNS; r++) {
      const a = now()
      fn()
      const b = now()
      t.push(Number(b - a) / 1e6)
    }
    t.sort((x, y) => x - y)
    return {
      min_ms: t[0],
      median_ms: t[(t.length - 1) >> 1],
      mean_ms: t.reduce((x, y) => x + y, 0) / t.length,
    }
  }

  const tree = buildTree(W, D, 0)
  const nodes = count(tree)
  const treeA = buildTree(W, D, 1)
  const treeB = buildTree(W, D, 2)
  const path = new Array(D).fill('k0').join('.')
  const cb = (_k, v, _p, p) => {
    sink += p.length
    return v
  }

  const raw = [
    ['clone', nodes, () => { sink += S.clone(tree) ? 1 : 0 }],
    ['walk', nodes, () => { S.walk(tree, cb) }],
    ['merge', nodes, () => { sink += S.merge([treeA, treeB]) ? 1 : 0 }],
    ['stringify', nodes, () => { sink += S.stringify(tree).length }],
    ['getpath', GP, () => {
      let s = 0
      for (let i = 0; i < GP; i++) s += S.getpath(tree, path) | 0
      sink += s
    }],
  ]
  const ops = raw.map(([op, unit_count, fn]) =>
    Object.assign({ op, runs: RUNS, unit_count }, measure(fn)))

  process.stderr.write(lang + ': sink=' + sink + '\n')
  process.stdout.write(JSON.stringify({
    lang,
    runtime,
    nodes,
    params: { width: W, depth: D, warmup: WARM, runs: RUNS, getpath_iters: GP },
    ops,
  }) + '\n')
}

module.exports = { runBench }
