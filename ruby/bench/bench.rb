# Performance bench for the Ruby port. Emits one JSON line per
# build/bench/README.md; diagnostics go to stderr.
require 'json'
require_relative '../voxgig_struct'

def envi(k, d)
  v = ENV[k]
  (v && v =~ /\A\d+\z/) ? v.to_i : d
end

W = envi('BENCH_WIDTH', 5)
D = envi('BENCH_DEPTH', 6)
WARM = envi('BENCH_WARMUP', 3)
RUNS = envi('BENCH_RUNS', 21)
GP = envi('BENCH_GETPATH_ITERS', 2000)

def build(w, d, leaf)
  return leaf if d == 0
  h = {}
  (0...w).each { |i| h["k#{i}"] = build(w, d - 1, leaf) }
  h
end

def nodecount(w, d)
  n = 0; p = 1
  (0..d).each { n += p; p *= w }
  n
end

$sink = 0

def measure(warm, runs)
  warm.times { yield }
  t = []
  runs.times do
    a = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    yield
    b = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    t << (b - a) / 1e6
  end
  t.sort!
  { min_ms: t[0], median_ms: t[t.length / 2], mean_ms: t.sum / t.length }
end

tree = build(W, D, 0)
nodes = nodecount(W, D)
treeA = build(W, D, 1)
treeB = build(W, D, 2)
path = (['k0'] * D).join('.')
cb = lambda { |_key, val, _parent, p| $sink += p.length; val }

ops = []
ops << { op: 'clone', runs: RUNS, unit_count: nodes }.merge(
  measure(WARM, RUNS) { $sink += VoxgigStruct.clone(tree) ? 1 : 0 })
ops << { op: 'walk', runs: RUNS, unit_count: nodes }.merge(
  measure(WARM, RUNS) { VoxgigStruct.walk(tree, cb) })
ops << { op: 'merge', runs: RUNS, unit_count: nodes }.merge(
  measure(WARM, RUNS) { $sink += VoxgigStruct.merge([treeA, treeB]) ? 1 : 0 })
ops << { op: 'stringify', runs: RUNS, unit_count: nodes }.merge(
  measure(WARM, RUNS) { $sink += VoxgigStruct.stringify(tree).length })
ops << { op: 'getpath', runs: RUNS, unit_count: GP }.merge(
  measure(WARM, RUNS) do
    s = 0
    GP.times { s += VoxgigStruct.getpath(tree, path) == 0 ? 1 : 0 }
    $sink += s
  end)

STDERR.puts "ruby: sink=#{$sink}"
puts JSON.generate({
  lang: 'ruby',
  runtime: "ruby #{RUBY_VERSION}",
  nodes: nodes,
  params: { width: W, depth: D, warmup: WARM, runs: RUNS, getpath_iters: GP },
  ops: ops,
})
