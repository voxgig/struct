# Benchmark for walk() on a wide and deep tree.
# Not run by default. To enable:
#   WALK_BENCH=1 ruby walk_bench.rb
#
# Mirrors ts/test/walk-bench.test.ts.

require_relative 'voxgig_struct'

BENCH = ENV['WALK_BENCH'] == '1'

# Build a balanced tree of maps with given width and depth.
# Total nodes: (width^(depth+1) - 1) / (width - 1).
def build_tree(width, depth)
  return 0 if depth == 0
  out = {}
  width.times do |i|
    out["k#{i}"] = build_tree(width, depth - 1)
  end
  out
end

def count_nodes(val)
  if val.is_a?(Hash)
    n = 1
    val.each_value { |v| n += count_nodes(v) }
    n
  elsif val.is_a?(Array)
    n = 1
    val.each { |v| n += count_nodes(v) }
    n
  else
    1
  end
end

def measure(label, tree, runs)
  # Touch path to simulate a minimal consumer. Using path.length keeps the
  # work O(1) so we measure walk overhead rather than callback overhead.
  sink = 0
  cb = lambda do |_k, v, _p, path|
    sink += path.length
    v
  end

  # Warm-up.
  2.times { VoxgigStruct.walk(tree, cb) }

  times = []
  runs.times do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    VoxgigStruct.walk(tree, cb)
    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    times << (t1 - t0) / 1_000_000.0  # ms
  end

  times.sort!
  median = times[times.length / 2]
  min = times[0]
  max = times[-1]
  mean = times.inject(0.0) { |a, b| a + b } / times.length

  nodes = count_nodes(tree)
  ns_per_node = (median * 1_000_000.0) / nodes

  printf(
    "[walk-bench] %s: nodes=%d runs=%d min=%.2fms median=%.2fms mean=%.2fms max=%.2fms ns/node=%.1f sink=%d\n",
    label, nodes, runs, min, median, mean, max, ns_per_node, sink
  )
  $stdout.flush
end

if BENCH
  # ~299k nodes: width=8, depth=6.
  wide_deep = build_tree(8, 6)
  measure('wide+deep (w=8,d=6)', wide_deep, 7)

  # width=1000, depth=2 -> 1,001,001 nodes, shallow.
  wide = build_tree(1000, 2)
  measure('wide (w=1000,d=2)', wide, 7)

  # width=2, depth=20 -> 2,097,151 nodes. MAXDEPTH is 32 by default.
  deep = build_tree(2, 20)
  measure('deep (w=2,d=20)', deep, 5)
else
  puts "walk_bench skipped (set WALK_BENCH=1 to run)"
end
