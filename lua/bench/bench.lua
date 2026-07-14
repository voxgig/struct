-- Performance bench for the Lua port. Emits one JSON line per
-- build/bench/README.md; diagnostics go to stderr. Run from the lua/ dir.
package.path = package.path .. ";./src/?.lua"
local struct = require("struct")

local function envi(k, d)
  local v = os.getenv(k)
  if v and v:match("^%d+$") then return tonumber(v) end
  return d
end

local W = envi("BENCH_WIDTH", 5)
local D = envi("BENCH_DEPTH", 6)
local WARM = envi("BENCH_WARMUP", 3)
local RUNS = envi("BENCH_RUNS", 21)
local GP = envi("BENCH_GETPATH_ITERS", 2000)

local function build(w, d, leaf)
  if d == 0 then return leaf end
  local o = setmetatable({}, { __jsontype = "object" })
  for i = 0, w - 1 do o["k" .. i] = build(w, d - 1, leaf) end
  return o
end

local function nodecount(w, d)
  local n, p = 0, 1
  for _ = 0, d do n = n + p; p = p * w end
  return n
end

local sink = 0

local function measure(warm, runs, f)
  for _ = 1, warm do f() end
  local t = {}
  for _ = 1, runs do
    local a = os.clock()
    f()
    t[#t + 1] = (os.clock() - a) * 1000
  end
  table.sort(t)
  local s = 0
  for _, x in ipairs(t) do s = s + x end
  return t[1], t[math.floor(#t / 2) + 1], s / #t
end

local tree = build(W, D, 0)
local nodes = nodecount(W, D)
local treeA = build(W, D, 1)
local treeB = build(W, D, 2)
local mlist = setmetatable({ treeA, treeB }, { __jsontype = "array" })
local segs = {}
for i = 1, D do segs[i] = "k0" end
local path = table.concat(segs, ".")
local cb = function(_k, v, _p, pth) sink = sink + #pth; return v end

local specs = {
  { "clone", nodes, function() struct.clone(tree); sink = sink + 1 end },
  { "walk", nodes, function() struct.walk(tree, cb) end },
  { "merge", nodes, function() struct.merge(mlist); sink = sink + 1 end },
  { "stringify", nodes, function() sink = sink + #struct.stringify(tree) end },
  { "getpath", GP, function()
    local a = 0
    for _ = 1, GP do if struct.getpath(tree, path) == 0 then a = a + 1 end end
    sink = sink + a
  end },
}

local parts = {}
for _, sp in ipairs(specs) do
  local mn, md, mean = measure(WARM, RUNS, sp[3])
  parts[#parts + 1] = string.format(
    '{"op":"%s","runs":%d,"unit_count":%d,"min_ms":%.6g,"median_ms":%.6g,"mean_ms":%.6g}',
    sp[1], RUNS, sp[2], mn, md, mean)
end

io.stderr:write("lua: sink=" .. sink .. "\n")
io.write(string.format(
  '{"lang":"lua","runtime":"%s","nodes":%d,"params":{"width":%d,"depth":%d,"warmup":%d,"runs":%d,"getpath_iters":%d},"ops":[%s]}\n',
  _VERSION:lower():gsub(" ", " "), nodes, W, D, WARM, RUNS, GP, table.concat(parts, ",")))
