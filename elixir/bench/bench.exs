# Performance bench for the Elixir port. Emits one JSON line per
# build/bench/README.md; diagnostics go to stderr. Nodes are heap references
# built via S.jm (map, from a flat k,v list) and S.jt (list).
Code.require_file("../lib/voxgig_struct.ex", __DIR__)
alias Voxgig.Struct, as: S

envi = fn k, d ->
  case System.get_env(k) do
    nil -> d
    v -> case Integer.parse(v) do
      {n, ""} -> n
      _ -> d
    end
  end
end

w = envi.("BENCH_WIDTH", 5)
d = envi.("BENCH_DEPTH", 6)
warm = envi.("BENCH_WARMUP", 3)
runs = envi.("BENCH_RUNS", 21)
gp = envi.("BENCH_GETPATH_ITERS", 2000)

build = fn build, w, d, leaf ->
  if d == 0 do
    leaf
  else
    kv = Enum.flat_map(0..(w - 1), fn i -> ["k#{i}", build.(build, w, d - 1, leaf)] end)
    S.jm(kv)
  end
end

nodecount = fn w, d ->
  Enum.reduce(0..d, {0, 1}, fn _, {n, p} -> {n + p, p * w} end) |> elem(0)
end

bump = fn n -> Process.put(:sink, (Process.get(:sink) || 0) + n) end

measure = fn warm, runs, f ->
  Enum.each(1..warm, fn _ -> f.() end)
  ts =
    Enum.map(1..runs, fn _ ->
      a = System.monotonic_time(:nanosecond)
      f.()
      (System.monotonic_time(:nanosecond) - a) / 1.0e6
    end)
    |> Enum.sort()

  n = length(ts)
  {Enum.at(ts, 0), Enum.at(ts, div(n, 2)), Enum.sum(ts) / n}
end

tree = build.(build, w, d, 0)
nodes = nodecount.(w, d)
treea = build.(build, w, d, 1)
treeb = build.(build, w, d, 2)
mlist = S.jt([treea, treeb])
path = Enum.map_join(1..d, ".", fn _ -> "k0" end)
cb = fn _key, val, _parent, p -> bump.(S.size(p)); val end

specs = [
  {"clone", nodes, fn -> S.clone(tree); bump.(1) end},
  {"walk", nodes, fn -> S.walk(tree, before: cb) end},
  {"merge", nodes, fn -> S.merge(mlist); bump.(1) end},
  {"stringify", nodes, fn -> bump.(String.length(S.stringify(tree))) end},
  {"getpath", gp, fn -> Enum.each(1..gp, fn _ -> S.getpath(tree, path) end); bump.(gp) end}
]

ops =
  Enum.map(specs, fn {op, uc, f} ->
    {mn, md, mean} = measure.(warm, runs, f)
    ~s({"op":"#{op}","runs":#{runs},"unit_count":#{uc},"min_ms":#{mn},"median_ms":#{md},"mean_ms":#{mean}})
  end)

IO.puts(:stderr, "elixir: sink=#{Process.get(:sink) || 0}")

IO.puts(
  ~s({"lang":"elixir","runtime":"elixir #{System.version()}","nodes":#{nodes},) <>
    ~s("params":{"width":#{w},"depth":#{d},"warmup":#{warm},"runs":#{runs},"getpath_iters":#{gp}},) <>
    ~s("ops":[#{Enum.join(ops, ",")}]})
)
