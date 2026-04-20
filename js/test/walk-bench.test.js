// Benchmark for walk() on a wide and deep tree.
// Not run by default. To enable:
//   WALK_BENCH=1 npm run walk-bench
// Or directly:
//   WALK_BENCH=1 node --test test/walk-bench.test.js

const { test, describe } = require('node:test')

const { walk } = require('../src/struct')


const BENCH = '1' === process.env.WALK_BENCH


// Build a balanced tree of maps with given width and depth.
// Total nodes: (width^(depth+1) - 1) / (width - 1).
function buildTree(width, depth) {
  if (0 === depth) {
    return 0
  }
  const out = {}
  for (let i = 0; i < width; i++) {
    out['k' + i] = buildTree(width, depth - 1)
  }
  return out
}


function countNodes(val) {
  if (null == val || 'object' !== typeof val) {
    return 1
  }
  let n = 1
  for (const k of Object.keys(val)) {
    n += countNodes(val[k])
  }
  return n
}


function measure(label, tree, runs) {
  // Touch path to simulate a minimal consumer. Using path.length keeps the
  // work O(1) so we measure walk overhead rather than callback overhead.
  let sink = 0
  const cb = (_k, v, _p, path) => {
    sink += path.length
    return v
  }

  // Warm-up.
  for (let i = 0; i < 2; i++) {
    walk(tree, cb)
  }

  const times = []
  for (let r = 0; r < runs; r++) {
    const t0 = process.hrtime.bigint()
    walk(tree, cb)
    const t1 = process.hrtime.bigint()
    times.push(Number(t1 - t0) / 1e6)
  }
  times.sort((a, b) => a - b)
  const median = times[Math.floor(times.length / 2)]
  const min = times[0]
  const max = times[times.length - 1]
  const mean = times.reduce((a, b) => a + b, 0) / times.length

  const nodes = countNodes(tree)
  const nsPerNode = (median * 1e6) / nodes

  console.log(
    `[walk-bench] ${label}: nodes=${nodes} runs=${runs} ` +
    `min=${min.toFixed(2)}ms median=${median.toFixed(2)}ms ` +
    `mean=${mean.toFixed(2)}ms max=${max.toFixed(2)}ms ` +
    `ns/node=${nsPerNode.toFixed(1)} sink=${sink}`
  )
}


describe('walk-bench', () => {

  test('walk-bench-wide-and-deep', { skip: !BENCH }, () => {
    // ~299k nodes: width=8, depth=6.
    const wideDeep = buildTree(8, 6)
    measure('wide+deep (w=8,d=6)', wideDeep, 7)
  })

  test('walk-bench-very-wide', { skip: !BENCH }, () => {
    // width=1000, depth=2 -> 1,001,001. ~1M nodes, shallow.
    const wide = buildTree(1000, 2)
    measure('wide (w=1000,d=2)', wide, 7)
  })

  test('walk-bench-very-deep', { skip: !BENCH }, () => {
    // MAXDEPTH in walk is 32, so cap depth at 24. Width 2 keeps node count sane.
    // width=2, depth=20 -> (2^21 - 1) = 2,097,151 nodes.
    const deep = buildTree(2, 20)
    measure('deep (w=2,d=20)', deep, 5)
  })

})
