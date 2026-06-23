# Smoke test for the Elixir test provider port. Prints summary stats that must
# match the canonical TS output documented in PROVIDER.md / the task brief.
#
# Run (when Elixir is available):  elixir smoke.exs
# This file deliberately uses NO JSON dependency (provider.ex ships its own).

Code.require_file("provider.ex", __DIR__)

defmodule Smoke do
  alias Voxgig.Proto.Provider, as: P

  def main do
    prov = P.load()

    fns = P.functions(prov)
    IO.puts("functions: " <> Enum.join(fns, ", "))

    {total, expect_kinds, input_kinds} =
      Enum.reduce(fns, {0, %{}, %{}}, fn fn_name, {total, ek, ik} ->
        Enum.reduce(P.entries(prov, fn_name), {total, ek, ik}, fn entry, {t, e, i} ->
          ekind = entry.expect.kind
          ikind = entry.input.kind
          {t + 1, Map.update(e, ekind, 1, &(&1 + 1)), Map.update(i, ikind, 1, &(&1 + 1))}
        end)
      end)

    IO.puts("total entries: #{total}")
    IO.puts("expect kinds: " <> kindstr(expect_kinds))
    IO.puts("input kinds: " <> kindstr(input_kinds))

    e = hd(P.entries(prov, "getpath", "basic"))

    IO.puts(
      "getpath/basic[0]: " <>
        "id=#{e.id}, doc=#{e.doc}, " <>
        "input.kind=#{e.input.kind}, " <>
        "expect.kind=#{e.expect.kind}, expect.value=#{fmt(e.expect.value)}"
    )

    # --- helper sanity checks ------------------------------------------------
    IO.puts("equal(:null, nil) lenient: #{P.equal(:null, nil)}")

    IO.puts(
      "equal_strict distinguishes nil vs __NULL__-collapse: " <>
        "#{P.equal_strict(nil, "__NULL__")} / #{P.equal_strict(:null, "__NULL__")}"
    )

    IO.puts(
      "error_matches substring case-insensitive: " <>
        "#{P.error_matches(%{any: false, text: "Foo", regex: false}, "a foobar error")}"
    )

    a = P.Obj.new([{"a", P.Obj.new([{"b", 2}])}])
    b = P.Obj.new([{"a", P.Obj.new([{"b", 3}])}])
    IO.puts("struct_match failure: #{inspect(P.struct_match(a, b))}")
  end

  # Stable "k=v, k=v" rendering with keys sorted for deterministic output.
  defp kindstr(map) do
    map
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join(", ")
  end

  defp fmt(:null), do: "null"
  defp fmt(v) when is_binary(v), do: v
  defp fmt(v), do: P.stringify(v)
end

Smoke.main()
