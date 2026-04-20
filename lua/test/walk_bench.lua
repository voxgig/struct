-- Benchmark for walk() on wide and deep trees.
-- Not run by default. To enable:
--   WALK_BENCH=1 lua test/walk_bench.lua
--
-- Measures the overhead of the walk() traversal itself by supplying a
-- minimal callback that only reads `#path`. Gated on the WALK_BENCH
-- environment variable.

package.path = package.path .. ";./src/?.lua;./test/?.lua"

local BENCH = os.getenv("WALK_BENCH") == "1"
if not BENCH then
  print("[walk-bench] skipped (set WALK_BENCH=1 to enable)")
  return
end

local struct = require("struct")
local walk = struct.walk

-- Build a balanced tree of maps with given width and depth.
local function buildTree(width, depth)
  if 0 == depth then
    return 0
  end
  local out = {}
  setmetatable(out, { __jsontype = "object" })
  for i = 0, width - 1 do
    out["k" .. i] = buildTree(width, depth - 1)
  end
  return out
end


local function countNodes(val)
  if type(val) ~= "table" then
    return 1
  end
  local n = 1
  for _, v in pairs(val) do
    n = n + countNodes(v)
  end
  return n
end


local function measure(label, tree, runs)
  local sink = 0
  local cb = function(_k, v, _p, path)
    sink = sink + #path
    return v
  end

  -- Warm-up.
  for _ = 1, 2 do
    walk(tree, cb)
  end

  local times = {}
  for _ = 1, runs do
    local t0 = os.clock()
    walk(tree, cb)
    local t1 = os.clock()
    table.insert(times, (t1 - t0) * 1000.0)
  end
  table.sort(times)
  local median = times[math.floor(#times / 2) + 1]
  local min = times[1]
  local max = times[#times]
  local sum = 0
  for _, t in ipairs(times) do sum = sum + t end
  local mean = sum / #times

  local nodes = countNodes(tree)
  local nsPerNode = (median * 1e6) / nodes

  print(string.format(
    "[walk-bench] %s: nodes=%d runs=%d min=%.2fms median=%.2fms mean=%.2fms max=%.2fms ns/node=%.1f sink=%d",
    label, nodes, runs, min, median, mean, max, nsPerNode, sink
  ))
end


-- ~299k nodes: width=8, depth=6.
local wideDeep = buildTree(8, 6)
measure("wide+deep (w=8,d=6)", wideDeep, 7)
wideDeep = nil
collectgarbage("collect")

-- ~1M nodes, shallow.
local wide = buildTree(1000, 2)
measure("wide (w=1000,d=2)", wide, 7)
wide = nil
collectgarbage("collect")

-- ~2M nodes, deep. Lua's MAXDEPTH in walk is 32, so w=2,d=20 is safe.
local deep = buildTree(2, 20)
measure("deep (w=2,d=20)", deep, 5)
deep = nil
collectgarbage("collect")
