# Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
#
# Voxgig Struct — Elixir port.
#
# A faithful port of the canonical TypeScript implementation
# (typescript/src/StructUtility.ts). The canonical algorithm mutates nodes in
# place and relies on reference-stable nodes (shared references seen by walk /
# merge / inject). The BEAM has no mutable, reference-stable native collection,
# so this port emulates a small mutable heap with ETS (an OTP-stdlib facility,
# like the JVM heap the Clojure port uses or Rust's Rc<RefCell>): a node is a
# tagged reference `{:vmap, id}` / `{:vlist, id}` whose contents live in the
# heap table and are replaced on mutation; the reference is stable, so all
# holders observe updates.
#
# Like the Python / Clojure / Dart ports, Elixir has a single `nil`, so the
# canonical `undefined` and JSON `null` are both `nil`; the Group A/B rules
# recover the distinction, and a NOARG sentinel marks "no argument supplied".
#
# Zero third-party runtime dependencies (ETS and :re/Regex are OTP stdlib).

defmodule Voxgig.Struct do
  @moduledoc "Faithful Elixir port of voxgig/struct. See AGENTS.md."

  # ---------------------------------------------------------------------------
  # Mutable heap (ETS)
  # ---------------------------------------------------------------------------

  @heap :vox_struct_heap

  defp ensure_heap do
    case :ets.whereis(@heap) do
      :undefined ->
        try do
          :ets.new(@heap, [:set, :public, :named_table])
        rescue
          ArgumentError -> :ok
        end

        :ok

      _ ->
        :ok
    end
  end

  defp alloc(contents) do
    ensure_heap()
    id = :erlang.unique_integer([:positive, :monotonic])
    :ets.insert(@heap, {id, contents})
    id
  end

  defp hget(id) do
    case :ets.lookup(@heap, id) do
      [{_, c}] -> c
      _ -> nil
    end
  end

  defp hset(id, contents), do: :ets.insert(@heap, {id, contents})

  defp vmap_new(pairs), do: {:vmap, alloc(pairs)}
  defp vlist_new(items), do: {:vlist, alloc(items)}
  defp empty_map, do: vmap_new([])
  defp empty_list, do: vlist_new([])

  defp map_pairs({:vmap, id}), do: hget(id)
  defp map_set_pairs({:vmap, id}, pairs), do: hset(id, pairs)
  defp list_items({:vlist, id}), do: hget(id)
  defp list_set_items({:vlist, id}, items), do: hset(id, items)

  # Injection cell
  defp vinj_new(fields), do: {:vinj, alloc(fields)}
  defp ig({:vinj, id}, k), do: Map.get(hget(id), k)

  defp is_({:vinj, id}, k, v) do
    hset(id, Map.put(hget(id), k, v))
    v
  end

  defp isinj({:vinj, _}), do: true
  defp isinj(_), do: false

  # ---------------------------------------------------------------------------
  # Sentinels / constants
  # ---------------------------------------------------------------------------

  @noarg :vox_noarg
  def noarg, do: @noarg

  @skip :vox_skip
  @delete :vox_delete
  def skip, do: @skip
  def delete, do: @delete
  def is_skip(v), do: v == @skip
  def is_delete(v), do: v == @delete

  @m_keypre "key:pre"
  @m_keypost "key:post"
  @m_val "val"
  def m_keypre, do: 1
  def m_keypost, do: 2
  def m_val, do: 4

  defp mode_to_num(@m_keypre), do: 1
  defp mode_to_num(@m_keypost), do: 2
  defp mode_to_num(@m_val), do: 4
  defp mode_to_num(_), do: 0

  @s_dkey "$KEY"
  @s_banno "`$ANNO`"
  @s_dtop "$TOP"
  @s_derrs "$ERRS"
  @s_dspec "$SPEC"
  @s_bexact "`$EXACT`"
  @s_bval "`$VAL`"
  @s_bkey "`$KEY`"
  @s_bopen "`$OPEN`"
  @s_mt ""
  @s_bt "`"
  @s_ds "$"
  @s_cn ":"
  @s_key "KEY"
  @s_viz ": "

  @t_any 0x7FFFFFFF
  @t_noval 0x40000000
  @t_boolean 0x20000000
  @t_decimal 0x10000000
  @t_integer 0x08000000
  @t_number 0x04000000
  @t_string 0x02000000
  @t_function 0x01000000
  @t_null 0x00400000
  @t_list 0x00004000
  @t_map 0x00002000
  @t_instance 0x00001000
  @t_scalar 0x00000080
  @t_node 0x00000040

  def t_any, do: @t_any
  def t_noval, do: @t_noval
  def t_boolean, do: @t_boolean
  def t_decimal, do: @t_decimal
  def t_integer, do: @t_integer
  def t_number, do: @t_number
  def t_string, do: @t_string
  def t_function, do: @t_function
  def t_null, do: @t_null
  def t_list, do: @t_list
  def t_map, do: @t_map
  def t_instance, do: @t_instance
  def t_scalar, do: @t_scalar
  def t_node, do: @t_node

  @typename {
    "any", "nil", "boolean", "decimal", "integer", "number", "string", "function",
    "symbol", "null", "", "", "", "", "", "", "", "list", "map", "instance",
    "", "", "", "", "scalar", "node"
  }

  @maxdepth 32

  @r_inject_full ~r/^`(\$[A-Z]+|[^`]*)[0-9]*`$/
  @r_inject_part ~r/`([^`]*)`/
  @r_meta_path ~r/^([^$]+)\$([=~])(.+)$/
  @r_transform_name ~r/`\$([A-Z]+)`/
  @r_intkey ~r/^-?[0-9]+$/

  # ---------------------------------------------------------------------------
  # Low-level helpers
  # ---------------------------------------------------------------------------

  defp is_intish(n) when is_integer(n), do: true
  defp is_intish(n) when is_float(n), do: n == Float.floor(n)
  defp is_intish(_), do: false

  defp num_to_string(n) when is_integer(n), do: Integer.to_string(n)

  defp num_to_string(n) when is_float(n) do
    cond do
      n == Float.floor(n) and abs(n) < 1.0e16 -> Integer.to_string(trunc(n))
      true -> shortest_float(n)
    end
  end

  defp shortest_float(n) do
    s = :erlang.float_to_binary(n, [:short])
    s
  end

  defp js_string(nil), do: "null"
  defp js_string(true), do: "true"
  defp js_string(false), do: "false"
  defp js_string(v) when is_number(v), do: num_to_string(v)
  defp js_string(v) when is_binary(v), do: v
  defp js_string(v) when is_function(v), do: "function"
  defp js_string(@skip), do: "skip"
  defp js_string(@delete), do: "delete"

  defp js_string({:vlist, _} = v) do
    list_items(v)
    |> Enum.map(fn x -> if x == nil, do: "", else: js_string(x) end)
    |> Enum.join(",")
  end

  defp js_string({:vmap, _}), do: "[object Object]"
  defp js_string(v), do: inspect(v)

  defp mapkey(k) when is_binary(k), do: k
  defp mapkey(k) when is_number(k), do: num_to_string(k)
  defp mapkey(k), do: js_string(k)

  defp to_int(k) when is_boolean(k), do: nil
  defp to_int(k) when is_integer(k), do: k
  defp to_int(k) when is_float(k), do: trunc(Float.floor(k))

  defp to_int(k) when is_binary(k) do
    case Integer.parse(String.trim(k)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp to_int(_), do: nil

  defp clz32(n0) do
    n = Bitwise.band(n0, 0xFFFFFFFF)

    if n == 0 do
      32
    else
      clz_loop(n, 0)
    end
  end

  defp clz_loop(n, r) do
    if Bitwise.band(n, 0x80000000) != 0 do
      r
    else
      clz_loop(Bitwise.band(Bitwise.bsl(n, 1), 0xFFFFFFFF), r + 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Minor utilities
  # ---------------------------------------------------------------------------

  def isnode({:vmap, _}), do: true
  def isnode({:vlist, _}), do: true
  def isnode(_), do: false

  def ismap({:vmap, _}), do: true
  def ismap(_), do: false

  def islist({:vlist, _}), do: true
  def islist(_), do: false

  def isfunc(v), do: is_function(v)

  def iskey(k) when is_binary(k), do: k != ""
  def iskey(k) when is_boolean(k), do: false
  def iskey(k) when is_number(k), do: true
  def iskey(_), do: false

  def isempty(v \\ nil) do
    cond do
      v == nil -> true
      v == "" -> true
      islist(v) -> list_items(v) == []
      ismap(v) -> map_pairs(v) == []
      true -> false
    end
  end

  def getdef(v, alt), do: if(v == nil, do: alt, else: v)

  def typify(value \\ @noarg) do
    cond do
      value == @noarg -> @t_noval
      value == nil -> Bitwise.bor(@t_scalar, @t_null)
      is_boolean(value) -> Bitwise.bor(@t_scalar, @t_boolean)
      is_integer(value) -> Bitwise.bor(Bitwise.bor(@t_scalar, @t_number), @t_integer)
      is_float(value) -> typify_float(value)
      is_binary(value) -> Bitwise.bor(@t_scalar, @t_string)
      is_function(value) -> Bitwise.bor(@t_scalar, @t_function)
      islist(value) -> Bitwise.bor(@t_node, @t_list)
      ismap(value) -> Bitwise.bor(@t_node, @t_map)
      true -> Bitwise.bor(@t_node, @t_instance)
    end
  end

  defp typify_float(value) do
    cond do
      value != value -> @t_noval
      value == Float.floor(value) -> Bitwise.bor(Bitwise.bor(@t_scalar, @t_number), @t_integer)
      true -> Bitwise.bor(Bitwise.bor(@t_scalar, @t_number), @t_decimal)
    end
  end

  def typename(t \\ 0) do
    i = clz32(t)
    if i >= 0 and i < tuple_size(@typename), do: elem(@typename, i), else: elem(@typename, 0)
  end

  def size(v \\ nil) do
    cond do
      islist(v) -> length(list_items(v))
      ismap(v) -> length(map_pairs(v))
      is_binary(v) -> String.length(v)
      is_boolean(v) -> if v, do: 1, else: 0
      is_number(v) -> trunc(Float.floor(v / 1))
      true -> 0
    end
  end

  def strkey(key \\ nil) do
    cond do
      key == nil -> @s_mt
      is_binary(key) -> key
      is_boolean(key) -> @s_mt
      is_number(key) -> if(is_intish(key), do: num_to_string(key), else: num_to_string(Float.floor(key)))
      true -> @s_mt
    end
  end

  def keysof(v \\ nil) do
    cond do
      ismap(v) -> map_pairs(v) |> Enum.map(&elem(&1, 0)) |> Enum.sort()
      islist(v) -> n = length(list_items(v)); if(n == 0, do: [], else: Enum.map(0..(n - 1), &Integer.to_string/1))
      true -> []
    end
  end

  defp omap_get(pairs, k) do
    case List.keyfind(pairs, k, 0) do
      {_, v} -> {:ok, v}
      nil -> :error
    end
  end

  defp omap_put(pairs, k, v) do
    if List.keymember?(pairs, k, 0) do
      Enum.map(pairs, fn {kk, vv} -> if kk == k, do: {k, v}, else: {kk, vv} end)
    else
      pairs ++ [{k, v}]
    end
  end

  defp omap_del(pairs, k), do: Enum.reject(pairs, fn {kk, _} -> kk == k end)

  def getprop(val, key, alt \\ nil) do
    if val == nil or key == nil do
      alt
    else
      out =
        cond do
          ismap(val) ->
            case omap_get(map_pairs(val), mapkey(key)) do
              {:ok, v} -> v
              :error -> nil
            end

          islist(val) ->
            ki = to_int(key)
            items = if ki == nil, do: [], else: list_items(val)
            if ki != nil and ki >= 0 and ki < length(items), do: Enum.at(items, ki), else: nil

          true ->
            nil
        end

      if out == nil, do: alt, else: out
    end
  end

  defp lookup_(val, key) do
    cond do
      val == nil or key == nil ->
        nil

      ismap(val) ->
        case omap_get(map_pairs(val), mapkey(key)) do
          {:ok, v} -> v
          :error -> nil
        end

      islist(val) ->
        ki = to_int(key)
        items = if ki == nil, do: [], else: list_items(val)
        if ki != nil and ki >= 0 and ki < length(items), do: Enum.at(items, ki), else: nil

      true ->
        nil
    end
  end

  def haskey(val \\ nil, key \\ nil), do: getprop(val, key) != nil

  def getelem(val, key, alt \\ nil) do
    if val == nil or key == nil do
      alt
    else
      out =
        if islist(val) do
          ks = cond do; is_binary(key) -> key; is_number(key) -> num_to_string(key); true -> "" end

          if Regex.match?(@r_intkey, ks) do
            items = list_items(val)
            len = length(items)
            nk0 = String.to_integer(ks)
            nk = if nk0 < 0, do: len + nk0, else: nk0
            if nk >= 0 and nk < len, do: Enum.at(items, nk), else: nil
          else
            nil
          end
        else
          nil
        end

      if out == nil do
        if isfunc(alt), do: alt.(), else: alt
      else
        out
      end
    end
  end

  defp getprop_raw(v, k) do
    cond do
      ismap(v) ->
        case omap_get(map_pairs(v), k) do
          {:ok, x} -> x
          :error -> nil
        end

      islist(v) ->
        i = String.to_integer(k)
        items = list_items(v)
        if i >= 0 and i < length(items), do: Enum.at(items, i), else: nil

      true ->
        nil
    end
  end

  defp items_pairs(v) do
    if not isnode(v), do: [], else: Enum.map(keysof(v), fn k -> {k, getprop_raw(v, k)} end)
  end

  def items(v \\ nil) do
    vlist_new(Enum.map(items_pairs(v), fn {k, x} -> vlist_new([k, x]) end))
  end

  defp items_v(v, f), do: vlist_new(Enum.map(items_pairs(v), f))

  def flatten(l, depth \\ 1) do
    if not islist(l) do
      l
    else
      out =
        Enum.reduce(list_items(l), [], fn item, acc ->
          if islist(item) and depth > 0 do
            acc ++ list_items(flatten(item, depth - 1))
          else
            acc ++ [item]
          end
        end)

      vlist_new(out)
    end
  end

  def filter(val, check) do
    out = Enum.reduce(items_pairs(val), [], fn {k, x}, acc -> if check.({k, x}), do: acc ++ [x], else: acc end)
    vlist_new(out)
  end

  def setprop(parent, key, val) do
    cond do
      not iskey(key) ->
        parent

      ismap(parent) ->
        map_set_pairs(parent, omap_put(map_pairs(parent), mapkey(key), val))
        parent

      islist(parent) ->
        case to_int(key) do
          nil ->
            parent

          ki ->
            items = list_items(parent)
            len = length(items)

            new =
              cond do
                ki >= 0 ->
                  ki2 = if ki > len, do: len, else: ki
                  if ki2 >= len, do: items ++ [val], else: List.replace_at(items, ki2, val)

                true ->
                  [val | items]
              end

            list_set_items(parent, new)
            parent
        end

      true ->
        parent
    end
  end

  def delprop(parent, key) do
    cond do
      not iskey(key) ->
        parent

      ismap(parent) ->
        map_set_pairs(parent, omap_del(map_pairs(parent), mapkey(key)))
        parent

      islist(parent) ->
        case to_int(key) do
          nil ->
            parent

          ki ->
            items = list_items(parent)
            if ki >= 0 and ki < length(items), do: list_set_items(parent, List.delete_at(items, ki))
            parent
        end

      true ->
        parent
    end
  end

  def clone(v \\ nil) do
    cond do
      ismap(v) -> vmap_new(Enum.map(map_pairs(v), fn {k, x} -> {k, clone(x)} end))
      islist(v) -> vlist_new(Enum.map(list_items(v), &clone/1))
      true -> v
    end
  end

  def slice(val, start \\ nil, stop \\ nil, mutate \\ false) do
    cond do
      is_number(val) and not is_boolean(val) ->
        lo = if is_number(start), do: start, else: nil
        hi = if is_number(stop), do: stop - 1, else: nil

        cond do
          hi != nil and val > hi -> hi
          lo != nil and val < lo -> lo
          true -> val
        end

      islist(val) or is_binary(val) ->
        slice_seq(val, start, stop, mutate)

      true ->
        val
    end
  end

  defp slice_seq(val, start, stop, mutate) do
    vlen = size(val)
    start = if start == nil and stop != nil, do: 0, else: start

    if start == nil do
      val
    else
      s0 = trunc(start)

      {s, e} =
        cond do
          s0 < 0 ->
            e = vlen + s0
            {0, if(e < 0, do: 0, else: e)}

          stop != nil ->
            e0 = trunc(stop)

            cond do
              e0 < 0 -> ee = vlen + e0; {s0, if(ee < 0, do: 0, else: ee)}
              vlen < e0 -> {s0, vlen}
              true -> {s0, e0}
            end

          true ->
            {s0, vlen}
        end

      s = if vlen < s, do: vlen, else: s

      if s > -1 and s <= e and e <= vlen do
        cond do
          islist(val) ->
            sub = Enum.slice(list_items(val), s, e - s)
            if mutate, do: (list_set_items(val, sub); val), else: vlist_new(sub)

          true ->
            binary_part(val, s, e - s)
        end
      else
        cond do
          islist(val) -> if mutate, do: (list_set_items(val, []); val), else: empty_list()
          true -> @s_mt
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Regex helpers (uniform re_* API over :re/Regex)
  # ---------------------------------------------------------------------------

  defp rx(p) do
    cond do
      is_struct(p, Regex) -> p
      is_binary(p) -> Regex.compile!(p)
      true -> Regex.compile!(js_string(p))
    end
  end

  def re_compile(p, _flags \\ nil), do: rx(p)
  def re_test(p, input), do: Regex.match?(rx(p), if(is_binary(input), do: input, else: js_string(input)))

  def re_find(p, input) do
    case Regex.run(rx(p), if(is_binary(input), do: input, else: js_string(input))) do
      nil -> nil
      groups -> vlist_new(Enum.map(groups, fn g -> g || "" end))
    end
  end

  def re_find_all(p, input) do
    matches = Regex.scan(rx(p), if(is_binary(input), do: input, else: js_string(input)))
    vlist_new(Enum.map(matches, fn groups -> vlist_new(Enum.map(groups, fn g -> g || "" end)) end))
  end

  def re_replace(_p, input, _repl), do: input
  def re_escape(s), do: escre(s)

  def escre(s \\ nil) do
    str = cond do; is_binary(s) -> s; s == nil -> @s_mt; true -> js_string(s) end

    str
    |> String.to_charlist()
    |> Enum.map(fn c ->
      ch = <<c::utf8>>
      if String.contains?(".*+?^${}()|[]\\", ch), do: "\\" <> ch, else: ch
    end)
    |> Enum.join("")
  end

  @url_unreserved "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"

  def escurl(s \\ nil) do
    str = cond do; is_binary(s) -> s; s == nil -> @s_mt; true -> js_string(s) end

    :binary.bin_to_list(str)
    |> Enum.map(fn b ->
      ch = <<b>>
      if String.contains?(@url_unreserved, ch) do
        ch
      else
        "%" <> String.upcase(String.pad_leading(Integer.to_string(b, 16), 2, "0"))
      end
    end)
    |> Enum.join("")
  end

  # ---------------------------------------------------------------------------
  # JSON-ish serialization / stringify / jsonify
  # ---------------------------------------------------------------------------

  defp esc_json(s) do
    inner =
      s
      |> String.to_charlist()
      |> Enum.map(fn c ->
        case c do
          ?" -> "\\\""
          ?\\ -> "\\\\"
          ?\n -> "\\n"
          ?\r -> "\\r"
          ?\t -> "\\t"
          c when c < 32 -> "\\u" <> String.pad_leading(Integer.to_string(c, 16), 4, "0")
          c -> <<c::utf8>>
        end
      end)
      |> Enum.join("")

    "\"" <> inner <> "\""
  end

  defp json_encode(v, sort \\ false, indent \\ nil), do: json_enc(v, sort, indent, 0)

  defp json_enc(v, sort, indent, level) do
    cond do
      v == nil -> "null"
      v == true -> "true"
      v == false -> "false"
      is_number(v) -> num_to_string(v)
      is_binary(v) -> esc_json(v)
      is_function(v) -> "null"
      v == @skip or v == @delete -> "null"
      islist(v) -> json_list(list_items(v), sort, indent, level)
      ismap(v) -> json_map(map_pairs(v), sort, indent, level)
      true -> esc_json(js_string(v))
    end
  end

  defp json_list([], _sort, _indent, _level), do: "[]"

  defp json_list(items, sort, nil, level) do
    "[" <> Enum.map_join(items, ",", fn x -> json_enc(x, sort, nil, level + 1) end) <> "]"
  end

  defp json_list(items, sort, indent, level) do
    pad = String.duplicate(" ", indent * (level + 1))
    cpad = String.duplicate(" ", indent * level)
    body = Enum.map_join(items, ",\n", fn x -> pad <> json_enc(x, sort, indent, level + 1) end)
    "[\n" <> body <> "\n" <> cpad <> "]"
  end

  defp json_map(pairs, sort, indent, level) do
    ks = Enum.map(pairs, &elem(&1, 0))
    ks = if sort, do: Enum.sort(ks), else: ks

    cond do
      ks == [] ->
        "{}"

      indent == nil ->
        "{" <>
          Enum.map_join(ks, ",", fn k ->
            {_, v} = List.keyfind(pairs, k, 0)
            esc_json(k) <> ":" <> json_enc(v, sort, nil, level + 1)
          end) <> "}"

      true ->
        pad = String.duplicate(" ", indent * (level + 1))
        cpad = String.duplicate(" ", indent * level)

        body =
          Enum.map_join(ks, ",\n", fn k ->
            {_, v} = List.keyfind(pairs, k, 0)
            pad <> esc_json(k) <> ": " <> json_enc(v, sort, indent, level + 1)
          end)

        "{\n" <> body <> "\n" <> cpad <> "}"
    end
  end

  defp has_cycle(v), do: has_cycle(v, MapSet.new())

  defp has_cycle({:vmap, id} = v, seen) do
    if MapSet.member?(seen, id), do: true, else: Enum.any?(map_pairs(v), fn {_, x} -> has_cycle(x, MapSet.put(seen, id)) end)
  end

  defp has_cycle({:vlist, id} = v, seen) do
    if MapSet.member?(seen, id), do: true, else: Enum.any?(list_items(v), fn x -> has_cycle(x, MapSet.put(seen, id)) end)
  end

  defp has_cycle(_, _), do: false

  def stringify(v \\ @noarg, maxlen \\ nil, pretty \\ nil) do
    pr = pretty == true

    cond do
      v == @noarg ->
        if pr, do: "<>", else: @s_mt

      true ->
        valstr =
          cond do
            is_binary(v) -> v
            has_cycle(v) -> "__STRINGIFY_FAILED__"
            true -> String.replace(json_encode(v, true), "\"", "")
          end

        valstr =
          if is_number(maxlen) and maxlen > -1 do
            m = trunc(maxlen)

            if m < String.length(valstr) do
              String.slice(valstr, 0, max(0, m - 3)) <> "..."
            else
              valstr
            end
          else
            valstr
          end

        if pr, do: stringify_pretty(valstr), else: valstr
    end
  end

  defp stringify_pretty(valstr) do
    colors = [81, 118, 213, 39, 208, 201, 45, 190, 129, 51, 160, 121, 226, 33, 207, 69]
    c = Enum.map(colors, fn n -> "\e[38;5;" <> Integer.to_string(n) <> "m" end) |> List.to_tuple()
    r = "\e[0m"
    clen = tuple_size(c)

    {_, _, t} =
      String.to_charlist(valstr)
      |> Enum.reduce({0, elem(c, 0), elem(c, 0)}, fn ch, {d, o, t} ->
        chs = <<ch::utf8>>

        cond do
          ch == ?{ or ch == ?[ ->
            d2 = d + 1
            o2 = elem(c, rem(d2, clen))
            {d2, o2, t <> o2 <> chs}

          ch == ?} or ch == ?] ->
            t2 = t <> o <> chs
            d2 = d - 1
            o2 = elem(c, rem(rem(d2, clen) + clen, clen))
            {d2, o2, t2}

          true ->
            {d, o, t <> o <> chs}
        end
      end)

    t <> r
  end

  def jsonify(v \\ nil, flags \\ nil) do
    if v == nil do
      "null"
    else
      indent = getprop(flags, "indent", 2)
      ind = if is_number(indent), do: trunc(indent), else: 2
      str = if ind > 0, do: json_encode(v, false, ind), else: json_encode(v)
      offset = getprop(flags, "offset", 0)
      off = if is_number(offset), do: trunc(offset), else: 0

      if off > 0 do
        lines = String.split(str, "\n")

        case lines do
          [_ | rest] -> "{\n" <> Enum.map_join(rest, "\n", fn l -> String.duplicate(" ", off) <> l end)
          [] -> str
        end
      else
        str
      end
    end
  end

  def pad(s \\ nil, padding \\ nil, padchar \\ nil) do
    str = cond do; is_binary(s) -> s; s == nil -> "null"; true -> stringify(s) end
    p = if is_number(padding), do: trunc(padding), else: 44
    pc = if is_binary(padchar), do: String.slice(padchar <> " ", 0, 1), else: " "

    if p > -1 do
      n = p - String.length(str)
      if n > 0, do: str <> String.duplicate(pc, n), else: str
    else
      n = -p - String.length(str)
      if n > 0, do: String.duplicate(pc, n) <> str, else: str
    end
  end

  # ---------------------------------------------------------------------------
  # join / pathify / replace
  # ---------------------------------------------------------------------------

  def join(arr, sep \\ nil, url \\ nil) do
    if not islist(arr) do
      @s_mt
    else
      sepdef = cond do; sep == nil -> ","; is_binary(sep) -> sep; true -> js_string(sep) end
      single = String.length(sepdef) == 1
      sc = if single, do: sepdef, else: " "
      is_url = url == true
      items = list_items(arr)
      sarr = length(items)

      out =
        items
        |> Enum.with_index()
        |> Enum.reduce([], fn {s0, idx}, acc ->
          if is_binary(s0) and s0 != @s_mt do
            s =
              if single do
                cond do
                  is_url and idx == 0 ->
                    strip_trailing(s0, sc)

                  true ->
                    x = if idx > 0, do: strip_leading(s0, sc), else: s0
                    x = if idx < sarr - 1 or not is_url, do: strip_trailing(x, sc), else: x
                    collapse(x, sc)
                end
              else
                s0
              end

            if s != @s_mt, do: acc ++ [s], else: acc
          else
            acc
          end
        end)

      Enum.join(out, sepdef)
    end
  end

  defp strip_trailing(s, sc) do
    if String.ends_with?(s, sc) and s != "", do: strip_trailing(String.slice(s, 0, String.length(s) - 1), sc), else: s
  end

  defp strip_leading(s, sc) do
    if String.starts_with?(s, sc) and s != "", do: strip_leading(String.slice(s, 1, String.length(s) - 1), sc), else: s
  end

  defp collapse(s, sc) do
    chars = String.graphemes(s)
    collapse_loop(chars, sc, [])
  end

  defp collapse_loop([], _sc, acc), do: Enum.join(Enum.reverse(acc), "")

  defp collapse_loop([ch | rest], sc, acc) do
    if ch != sc do
      collapse_loop(rest, sc, [ch | acc])
    else
      {run, rest2} = take_run(rest, sc, [ch])
      before_non = acc != [] and hd(acc) != sc
      after_non = rest2 != []

      if before_non and after_non do
        collapse_loop(rest2, sc, [sc | acc])
      else
        collapse_loop(rest2, sc, Enum.reverse(run) ++ acc)
      end
    end
  end

  defp take_run([ch | rest], sc, acc) when ch == sc, do: take_run(rest, sc, [ch | acc])
  defp take_run(rest, _sc, acc), do: {Enum.reverse(acc), rest}

  def joinurl(arr), do: join(arr, "/", true)

  def replace(s, from, to) do
    ts = typify(s)

    rs =
      cond do
        Bitwise.band(@t_string, ts) == 0 -> stringify(s)
        Bitwise.band(Bitwise.bor(@t_noval, @t_null), ts) > 0 -> @s_mt
        true -> stringify(s)
      end

    to_s = if is_binary(to), do: to, else: js_string(to)

    cond do
      is_binary(from) and from != "" -> String.replace(rs, from, to_s)
      is_struct(from, Regex) -> Regex.replace(from, rs, to_s)
      true -> rs
    end
  end

  def pathify(v \\ @noarg, startin \\ nil, endin \\ nil) do
    absent = v == @noarg
    val = if absent, do: nil, else: v

    path =
      cond do
        islist(val) -> list_items(val)
        iskey(val) -> [val]
        true -> nil
      end

    start = if is_number(startin), do: if(startin > -1, do: trunc(startin), else: 0), else: 0
    endn = if is_number(endin), do: if(endin > -1, do: trunc(endin), else: 0), else: 0

    pathstr =
      if path != nil and start >= 0 do
        len = length(path)
        e = max(0, len - endn)
        s = if start > len, do: len, else: start
        sub = if s <= e, do: Enum.slice(path, s, e - s), else: []

        if sub == [] do
          "<root>"
        else
          sub
          |> Enum.filter(&iskey/1)
          |> Enum.map(fn p ->
            cond do
              is_integer(p) -> num_to_string(p)
              is_float(p) -> num_to_string(Float.floor(p))
              true -> String.replace(js_string(p), ".", @s_mt)
            end
          end)
          |> Enum.join(".")
        end
      else
        nil
      end

    if pathstr == nil do
      "<unknown-path" <> (if absent, do: @s_mt, else: @s_cn <> stringify(val, 47)) <> ">"
    else
      pathstr
    end
  end

  # ---------------------------------------------------------------------------
  # walk / merge
  # ---------------------------------------------------------------------------

  def walk(val, opts \\ []) do
    before = Keyword.get(opts, :before)
    aft = Keyword.get(opts, :after)
    maxdepth = Keyword.get(opts, :maxdepth)
    key = Keyword.get(opts, :key)
    parent = Keyword.get(opts, :parent)
    path = Keyword.get(opts, :path)
    path = if path == nil, do: empty_list(), else: path
    depth = size(path)
    out = if before == nil, do: val, else: before.(key, val, parent, path)
    md = if is_number(maxdepth) and maxdepth >= 0, do: trunc(maxdepth), else: @maxdepth

    if md == 0 or (md > 0 and md <= depth) do
      out
    else
      if isnode(out) do
        prefix = list_items(path)

        Enum.each(items_pairs(out), fn {ckey, child} ->
          childpath = vlist_new(prefix ++ [ckey])

          result =
            walk(child, before: before, after: aft, maxdepth: md, key: ckey, parent: out, path: childpath)

          setprop(out, ckey, result)
        end)
      end

      if aft == nil, do: out, else: aft.(key, out, parent, path)
    end
  end

  defp grow(a, n) do
    if size(a) <= n do
      setprop(a, size(a), nil)
      grow(a, n)
    end
  end

  def merge(objs, maxdepth \\ nil) do
    md = if is_number(maxdepth), do: if(maxdepth < 0, do: 0, else: trunc(maxdepth)), else: @maxdepth

    if not islist(objs) do
      objs
    else
      items = list_items(objs)
      lenlist = length(items)

      cond do
        lenlist == 0 ->
          nil

        lenlist == 1 ->
          Enum.at(items, 0)

        true ->
          out0 = getprop(objs, 0, empty_map())
          out = merge_loop(objs, lenlist, md, out0)

          if md == 0 do
            o = getprop(objs, lenlist - 1)
            cond do; islist(o) -> empty_list(); ismap(o) -> empty_map(); true -> o end
          else
            out
          end
      end
    end
  end

  defp merge_loop(_objs, _lenlist, _md, out, oi \\ 1)

  defp merge_loop(objs, lenlist, md, out, oi) do
    if oi >= lenlist do
      out
    else
      obj = getprop(objs, oi)

      out2 =
        if not isnode(obj) do
          obj
        else
          cur = vlist_new([out])
          dst = vlist_new([out])

          before = fn key, val, _parent, path ->
            pi = size(path)

            cond do
              md <= pi ->
                grow(cur, pi)
                setprop(cur, pi, val)
                if pi > 0, do: setprop(getelem(cur, pi - 1), key, val)
                nil

              not isnode(val) ->
                grow(cur, pi)
                setprop(cur, pi, val)
                val

              true ->
                grow(dst, pi)
                grow(cur, pi)
                dnew = if pi > 0, do: getprop(getelem(dst, pi - 1), key), else: getelem(dst, pi)
                setprop(dst, pi, dnew)
                tval = getelem(dst, pi)

                cond do
                  tval == nil ->
                    setprop(cur, pi, if(islist(val), do: empty_list(), else: empty_map()))
                    val

                  (islist(val) and islist(tval)) or (ismap(val) and ismap(tval)) ->
                    setprop(cur, pi, tval)
                    val

                  true ->
                    setprop(cur, pi, val)
                    nil
                end
            end
          end

          aft = fn key, vv, _parent, path ->
            ci = size(path)

            if ci < 1 do
              if size(cur) > 0, do: getelem(cur, 0), else: vv
            else
              target = if ci - 1 < size(cur), do: getelem(cur, ci - 1), else: nil
              value = if ci < size(cur), do: getelem(cur, ci), else: nil
              setprop(target, key, value)
              value
            end
          end

          walk(obj, before: before, after: aft)
        end

      merge_loop(objs, lenlist, md, out2, oi + 1)
    end
  end

  # ---------------------------------------------------------------------------
  # getpath / setpath
  # ---------------------------------------------------------------------------

  defp idef(injdef, field) do
    cond do
      isinj(injdef) ->
        case field do
          "base" -> ig(injdef, :base)
          "dparent" -> ig(injdef, :dparent)
          "meta" -> ig(injdef, :meta)
          "key" -> ig(injdef, :key)
          "dpath" -> ig(injdef, :dpath)
          "handler" -> ig(injdef, :handler)
        end

      injdef == nil ->
        nil

      true ->
        getprop(injdef, field)
    end
  end

  defp dummy_inj, do: new_inj(nil, vmap_new([{@s_dtop, nil}]))

  def getpath(store, path, injdef \\ nil) do
    parts =
      cond do
        islist(path) -> list_items(path)
        is_binary(path) -> String.split(path, ".")
        is_number(path) and not is_boolean(path) -> [strkey(path)]
        true -> nil
      end

    if parts == nil do
      nil
    else
      has_inj = injdef != nil
      base = idef(injdef, "base")
      dparent = idef(injdef, "dparent")
      inj_meta = idef(injdef, "meta")
      inj_key = idef(injdef, "key")
      dpath = idef(injdef, "dpath")
      src = if iskey(base), do: getprop(store, base, store), else: store
      numparts = length(parts)

      val =
        cond do
          path == nil or store == nil or (numparts == 1 and Enum.at(parts, 0) == @s_mt) or numparts == 0 ->
            src

          true ->
            val0 = if numparts == 1, do: getprop(store, Enum.at(parts, 0)), else: store

            if isfunc(val0) do
              val0
            else
              {val1, parts1} =
                case if(is_binary(Enum.at(parts, 0)), do: Regex.run(@r_meta_path, Enum.at(parts, 0)), else: nil) do
                  [_, g1, _, g3] when inj_meta != nil and has_inj ->
                    {getprop(inj_meta, g1), List.replace_at(parts, 0, g3)}

                  _ ->
                    {src, parts}
                end

              getpath_loop(store, parts1, 0, val1, has_inj, inj_key, inj_meta, src, dparent, dpath)
            end
        end

      handler = idef(injdef, "handler")

      if has_inj and isfunc(handler) do
        ref = pathify(path)
        if isinj(injdef), do: handler.(injdef, val, ref, store), else: handler.(dummy_inj(), val, ref, store)
      else
        val
      end
    end
  end

  defp count_ascends(parts, pi, acc) do
    if pi + 1 < length(parts) and Enum.at(parts, pi + 1) == @s_mt do
      count_ascends(parts, pi + 1, acc + 1)
    else
      {acc, pi}
    end
  end

  defp getpath_loop(store, parts, pi, val, has_inj, inj_key, inj_meta, src, dparent, dpath) do
    numparts = length(parts)

    if val == nil or pi >= numparts do
      val
    else
      raw = Enum.at(parts, pi)

      part0 =
        cond do
          has_inj and raw == @s_dkey -> if inj_key != nil, do: inj_key, else: raw
          is_binary(raw) and String.starts_with?(raw, "$GET:") -> stringify(getpath(src, slice(raw, 5, -1)))
          is_binary(raw) and String.starts_with?(raw, "$REF:") -> stringify(getpath(getprop(store, @s_dspec), slice(raw, 5, -1)))
          has_inj and is_binary(raw) and String.starts_with?(raw, "$META:") -> stringify(getpath(inj_meta, slice(raw, 6, -1)))
          true -> raw
        end

      part = if is_binary(part0), do: String.replace(part0, "$$", "$"), else: strkey(part0)

      if part == @s_mt do
        {ascends, pi2} = count_ascends(parts, pi, 0)

        if has_inj and ascends > 0 do
          ascends2 = if pi2 == numparts - 1, do: ascends - 1, else: ascends

          if ascends2 == 0 do
            getpath_loop(store, parts, pi2 + 1, dparent, has_inj, inj_key, inj_meta, src, dparent, dpath)
          else
            tail = Enum.drop(parts, pi2 + 1)
            fullpath = flatten(vlist_new([slice(dpath, -ascends2), vlist_new(tail)]))
            if ascends2 <= size(dpath), do: getpath(store, fullpath), else: nil
          end
        else
          getpath_loop(store, parts, pi2 + 1, dparent, has_inj, inj_key, inj_meta, src, dparent, dpath)
        end
      else
        getpath_loop(store, parts, pi + 1, getprop(val, part), has_inj, inj_key, inj_meta, src, dparent, dpath)
      end
    end
  end

  def setpath(store, path, val, injdef \\ nil) do
    ptype = typify(path)

    parts =
      cond do
        Bitwise.band(@t_list, ptype) > 0 -> vlist_new(list_items(path))
        Bitwise.band(@t_string, ptype) > 0 -> vlist_new(String.split(path, "."))
        Bitwise.band(@t_number, ptype) > 0 -> vlist_new([path])
        true -> nil
      end

    if parts == nil do
      nil
    else
      base = if injdef != nil, do: idef(injdef, "base"), else: nil
      numparts = size(parts)
      parent0 = if iskey(base), do: getprop(store, base, store), else: store
      parent = setpath_walk(parts, numparts, parent0, 0)

      if is_delete(val) do
        delprop(parent, getelem(parts, -1))
      else
        setprop(parent, getelem(parts, -1), val)
      end

      parent
    end
  end

  defp setpath_walk(parts, numparts, parent, pi) do
    if pi >= numparts - 1 do
      parent
    else
      pkey = getelem(parts, pi)
      np0 = getprop(parent, pkey)

      np =
        if not isnode(np0) do
          nextpart = getelem(parts, pi + 1)
          nn = if Bitwise.band(@t_number, typify(nextpart)) > 0, do: empty_list(), else: empty_map()
          setprop(parent, pkey, nn)
          nn
        else
          np0
        end

      setpath_walk(parts, numparts, np, pi + 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Injection
  # ---------------------------------------------------------------------------

  defp new_inj(val, parent) do
    vinj_new(%{
      mode: @m_val,
      full: false,
      keyi: 0,
      keys: vlist_new([@s_dtop]),
      key: @s_dtop,
      ival: val,
      parent: parent,
      path: vlist_new([@s_dtop]),
      nodes: vlist_new([parent]),
      handler: &inject_handler/4,
      errs: empty_list(),
      meta: empty_map(),
      dparent: nil,
      dpath: vlist_new([@s_dtop]),
      base: @s_dtop,
      modify: nil,
      prior: nil,
      extra: nil,
      root: nil
    })
  end

  defp inj_descend(inj) do
    meta = ig(inj, :meta)

    if ismap(meta) do
      d = case getprop(meta, "__d") do; n when is_number(n) -> n; _ -> 0 end
      setprop(meta, "__d", d + 1)
    end

    parentkey = getelem(ig(inj, :path), -2)

    cond do
      ig(inj, :dparent) == nil ->
        if size(ig(inj, :dpath)) > 1 do
          is_(inj, :dpath, vlist_new(list_items(ig(inj, :dpath)) ++ [parentkey]))
        end

      parentkey != nil ->
        is_(inj, :dparent, getprop(ig(inj, :dparent), parentkey))
        lastpart = getelem(ig(inj, :dpath), -1)

        if lastpart == "$:" <> js_string(parentkey) do
          is_(inj, :dpath, slice(ig(inj, :dpath), -1))
        else
          is_(inj, :dpath, vlist_new(list_items(ig(inj, :dpath)) ++ [parentkey]))
        end

      true ->
        :ok
    end

    ig(inj, :dparent)
  end

  defp inj_child(inj, keyi, keys) do
    key = strkey(getelem(keys, keyi))
    val = ig(inj, :ival)

    vinj_new(%{
      mode: ig(inj, :mode),
      full: ig(inj, :full),
      keyi: keyi,
      keys: keys,
      key: key,
      ival: getprop(val, key),
      parent: val,
      path: vlist_new(list_items(ig(inj, :path)) ++ [key]),
      nodes: vlist_new(list_items(ig(inj, :nodes)) ++ [val]),
      handler: ig(inj, :handler),
      errs: ig(inj, :errs),
      meta: ig(inj, :meta),
      base: ig(inj, :base),
      modify: ig(inj, :modify),
      prior: inj,
      dpath: vlist_new(list_items(ig(inj, :dpath))),
      dparent: ig(inj, :dparent),
      extra: ig(inj, :extra),
      root: ig(inj, :root)
    })
  end

  defp inj_setval(inj, val, ancestor \\ 1) do
    {target, key} =
      if ancestor < 2 do
        {ig(inj, :parent), ig(inj, :key)}
      else
        {getelem(ig(inj, :nodes), -ancestor), getelem(ig(inj, :path), -ancestor)}
      end

    if val == nil, do: delprop(target, key), else: setprop(target, key, val)
  end

  # ---------------------------------------------------------------------------
  # inject
  # ---------------------------------------------------------------------------

  def inject(val, store, injdef \\ nil) do
    inj =
      if isinj(injdef) do
        injdef
      else
        parent = vmap_new([{@s_dtop, val}])
        i = new_inj(val, parent)
        is_(i, :dparent, store)
        is_(i, :errs, getprop(store, @s_derrs, empty_list()))
        if ismap(ig(i, :meta)), do: setprop(ig(i, :meta), "__d", 0)
        is_(i, :root, parent)

        if injdef != nil do
          if getprop(injdef, "modify") != nil, do: is_(i, :modify, getprop(injdef, "modify"))
          if getprop(injdef, "extra") != nil, do: is_(i, :extra, getprop(injdef, "extra"))
          if getprop(injdef, "meta") != nil, do: is_(i, :meta, getprop(injdef, "meta"))
          if getprop(injdef, "handler") != nil, do: is_(i, :handler, getprop(injdef, "handler"))
        end

        i
      end

    inj_descend(inj)

    rv =
      cond do
        isnode(val) ->
          nodekeys =
            if ismap(val) do
              ks = Enum.map(map_pairs(val), &elem(&1, 0))
              normal = ks |> Enum.filter(fn k -> not String.contains?(k, @s_ds) end) |> Enum.sort()
              trans = ks |> Enum.filter(fn k -> String.contains?(k, @s_ds) end) |> Enum.sort()
              normal ++ trans
            else
              n = length(list_items(val))
              if n == 0, do: [], else: Enum.map(0..(n - 1), &Integer.to_string/1)
            end

          inject_loop(inj, val, store, nodekeys, 0)
          val

        is_binary(val) ->
          is_(inj, :mode, @m_val)
          nv = injectstr(val, store, inj)
          if not is_skip(nv), do: inj_setval(inj, nv)
          nv

        true ->
          val
      end

    if ig(inj, :modify) != nil and not is_skip(rv) do
      mkey = ig(inj, :key)
      mparent = ig(inj, :parent)
      mval = getprop(mparent, mkey)
      ig(inj, :modify).(mval, mkey, mparent, inj)
    end

    is_(inj, :ival, rv)

    cond do
      ig(inj, :prior) == nil and ig(inj, :root) != nil and haskey(ig(inj, :root), @s_dtop) ->
        getprop(ig(inj, :root), @s_dtop)

      ig(inj, :key) == @s_dtop and ig(inj, :parent) != nil and haskey(ig(inj, :parent), @s_dtop) ->
        getprop(ig(inj, :parent), @s_dtop)

      true ->
        rv
    end
  end

  defp inject_loop(inj, val, store, nodekeys, nki) do
    if nki >= length(nodekeys) do
      :ok
    else
      childinj = inj_child(inj, nki, vlist_new(nodekeys))
      nodekey = ig(childinj, :key)
      is_(childinj, :mode, @m_keypre)
      prekey = injectstr(js_string(nodekey), store, childinj)
      nk1 = Enum.map(list_items(ig(childinj, :keys)), &js_string/1)

      nk2 =
        if prekey != nil do
          is_(childinj, :ival, getprop(val, prekey))
          is_(childinj, :mode, @m_val)
          inject(ig(childinj, :ival), store, childinj)
          _ = Enum.map(list_items(ig(childinj, :keys)), &js_string/1)
          is_(childinj, :mode, @m_keypost)
          injectstr(js_string(nodekey), store, childinj)
          Enum.map(list_items(ig(childinj, :keys)), &js_string/1)
        else
          nk1
        end

      inject_loop(inj, val, store, nk2, ig(childinj, :keyi) + 1)
    end
  end

  defp inject_handler(inj, val, ref, store) do
    iscmd = isfunc(val) and (ref == nil or (is_binary(ref) and String.starts_with?(ref, @s_ds)))

    cond do
      iscmd ->
        val.(inj, val, ref, store)

      ig(inj, :mode) == @m_val and ig(inj, :full) ->
        inj_setval(inj, val)
        val

      true ->
        val
    end
  end

  defp injectstr(val, store, inj) do
    if val == @s_mt do
      @s_mt
    else
      case Regex.run(@r_inject_full, val) do
        [_, pathref0] ->
          if inj != nil, do: is_(inj, :full, true)

          pathref =
            if String.length(pathref0) > 3,
              do: pathref0 |> String.replace("$BT", @s_bt) |> String.replace("$DS", @s_ds),
              else: pathref0

          getpath(store, pathref, inj)

        _ ->
          out =
            Regex.replace(@r_inject_part, val, fn _whole, ref0 ->
              ref =
                if String.length(ref0) > 3,
                  do: ref0 |> String.replace("$BT", @s_bt) |> String.replace("$DS", @s_ds),
                  else: ref0

              if inj != nil, do: is_(inj, :full, false)
              found = getpath(store, ref, inj)

              cond do
                found == nil -> @s_mt
                is_binary(found) -> if found == "__NULL__", do: "null", else: found
                isfunc(found) -> @s_mt
                true -> try do; json_encode(found); rescue _ -> stringify(found) end
              end
            end)

          if inj != nil and isfunc(ig(inj, :handler)) do
            is_(inj, :full, true)
            ig(inj, :handler).(inj, out, val, store)
          else
            out
          end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # transform commands
  # ---------------------------------------------------------------------------

  defp transform_delete(inj, _v, _r, _s) do
    delprop(ig(inj, :parent), ig(inj, :key))
    nil
  end

  defp transform_copy(inj, _v, _r, _s) do
    if ig(inj, :mode) == @m_keypre or ig(inj, :mode) == @m_keypost do
      ig(inj, :key)
    else
      out = lookup_(ig(inj, :dparent), ig(inj, :key))
      inj_setval(inj, out)
      out
    end
  end

  defp transform_key(inj, _v, _r, _s) do
    if ig(inj, :mode) != @m_val do
      nil
    else
      keyspec = lookup_(ig(inj, :parent), @s_bkey)

      if keyspec != nil do
        delprop(ig(inj, :parent), @s_bkey)
        getprop(ig(inj, :dparent), keyspec)
      else
        anno = lookup_(ig(inj, :parent), @s_banno)
        fromanno = lookup_(anno, @s_key)
        if fromanno != nil, do: fromanno, else: getelem(ig(inj, :path), -2)
      end
    end
  end

  defp transform_anno(inj, _v, _r, _s) do
    delprop(ig(inj, :parent), @s_banno)
    nil
  end

  defp transform_merge(inj, _v, _r, _s) do
    cond do
      ig(inj, :mode) == @m_keypre ->
        ig(inj, :key)

      ig(inj, :mode) == @m_keypost ->
        args0 = getprop(ig(inj, :parent), ig(inj, :key))
        args = if islist(args0), do: args0, else: vlist_new([args0])
        inj_setval(inj, nil)
        mergelist = flatten(vlist_new([vlist_new([ig(inj, :parent)]), args, vlist_new([clone(ig(inj, :parent))])]))
        merge(mergelist)
        ig(inj, :key)

      true ->
        nil
    end
  end

  defp transform_each(inj, _v, _r, store) do
    if islist(ig(inj, :keys)), do: slice(ig(inj, :keys), 0, 1, true)

    if ig(inj, :mode) != @m_val do
      nil
    else
      parent = ig(inj, :parent)
      srcpath = if size(parent) > 1, do: getelem(parent, 1), else: nil
      child_tm = if size(parent) > 2, do: clone(getelem(parent, 2)), else: nil
      srcstore = getprop(store, ig(inj, :base), store)
      src = getpath(srcstore, srcpath, inj)
      tkey = getelem(ig(inj, :path), -2)
      nodes = ig(inj, :nodes)
      target = (fn -> t = getelem(nodes, -2); if t == nil, do: getelem(nodes, -1), else: t end).()
      rval = vlist_new([])

      if isnode(src) do
        tval_items =
          cond do
            islist(src) ->
              Enum.map(list_items(src), fn _ -> clone(child_tm) end)

            ismap(src) ->
              Enum.map(map_pairs(src), fn {k, _} ->
                cc = clone(child_tm)
                if ismap(cc), do: setprop(cc, @s_banno, vmap_new([{@s_key, k}]))
                cc
              end)

            true ->
              []
          end

        tval = vlist_new(tval_items)

        tcurrent =
          cond do
            ismap(src) -> vlist_new(Enum.map(map_pairs(src), &elem(&1, 1)))
            islist(src) -> vlist_new(list_items(src))
            true -> src
          end

        if tval_items != [] do
          path = ig(inj, :path)
          ckey = getelem(path, -2)
          plist = list_items(path)
          tpath = if plist == [], do: vlist_new([]), else: vlist_new(Enum.take(plist, length(plist) - 1))
          dpath0 = [@s_dtop]

          dpath0 =
            if is_binary(srcpath) and srcpath != @s_mt do
              dpath0 ++ (String.split(srcpath, ".") |> Enum.filter(&(&1 != @s_mt)))
            else
              dpath0
            end

          dpath0 = if ckey != nil, do: dpath0 ++ ["$:" <> js_string(ckey)], else: dpath0
          tcur = vmap_new([{js_string(ckey), tcurrent}])

          {tcur, dpath0} =
            if size(tpath) > 1 do
              pkey = getelem(path, -3, @s_dtop)
              {vmap_new([{js_string(pkey), tcur}]), dpath0 ++ ["$:" <> js_string(pkey)]}
            else
              {tcur, dpath0}
            end

          tinj = inj_child(inj, 0, if(ckey != nil, do: vlist_new([ckey]), else: vlist_new([])))
          is_(tinj, :path, tpath)
          nlist = list_items(nodes)
          is_(tinj, :nodes, if(nlist == [], do: vlist_new([]), else: vlist_new(Enum.take(nlist, length(nlist) - 1))))
          is_(tinj, :parent, if(size(ig(tinj, :nodes)) > 0, do: getelem(ig(tinj, :nodes), -1), else: nil))
          if ckey != nil and ig(tinj, :parent) != nil, do: setprop(ig(tinj, :parent), ckey, tval)
          is_(tinj, :ival, tval)
          is_(tinj, :dpath, vlist_new(dpath0))
          is_(tinj, :dparent, tcur)
          inject(tval, store, tinj)
          rval = ig(tinj, :ival)
          setprop(target, tkey, rval)
          if islist(rval) and size(rval) > 0, do: getelem(rval, 0), else: nil
        else
          setprop(target, tkey, rval)
          if islist(rval) and size(rval) > 0, do: getelem(rval, 0), else: nil
        end
      else
        setprop(target, tkey, rval)
        nil
      end
    end
  end

  defp transform_pack(inj, _v, _r, store) do
    cond do
      ig(inj, :mode) != @m_keypre or not is_binary(ig(inj, :key)) ->
        nil

      true ->
        parent = ig(inj, :parent)
        path = ig(inj, :path)
        nodes = ig(inj, :nodes)
        args_val = getprop(parent, ig(inj, :key))

        if not islist(args_val) or size(args_val) < 2 do
          nil
        else
          srcpath = getelem(args_val, 0)
          origchildspec = getelem(args_val, 1)
          tkey = getelem(path, -2)
          pathsize = size(path)
          target = (fn -> t = getelem(nodes, pathsize - 2); if t == nil, do: getelem(nodes, pathsize - 1), else: t end).()
          srcstore = getprop(store, ig(inj, :base), store)
          src0 = getpath(srcstore, srcpath, inj)

          src =
            if not islist(src0) do
              if ismap(src0) do
                vlist_new(
                  Enum.map(items_pairs(src0), fn {k, node} ->
                    setprop(node, @s_banno, vmap_new([{@s_key, k}]))
                    node
                  end)
                )
              else
                nil
              end
            else
              src0
            end

          if src == nil do
            nil
          else
            keypath = getprop(origchildspec, @s_bkey)
            childspec = delprop(origchildspec, @s_bkey)
            child = getprop(childspec, @s_bval, childspec)
            tval = empty_map()

            Enum.each(items_pairs(src), fn {srckey, srcnode} ->
              k =
                cond do
                  keypath == nil -> srckey
                  is_binary(keypath) and String.starts_with?(keypath, @s_bt) -> inject(keypath, merge(vlist_new([empty_map(), store, vmap_new([{@s_dtop, srcnode}])]), 1))
                  true -> getpath(srcnode, keypath, inj)
                end

              tchild = clone(child)
              setprop(tval, k, tchild)
              anno = getprop(srcnode, @s_banno)
              if anno == nil, do: delprop(tchild, @s_banno), else: setprop(tchild, @s_banno, anno)
            end)

            rval =
              if not isempty(tval) do
                tsrc = empty_map()

                list_items(src)
                |> Enum.with_index()
                |> Enum.each(fn {node, i} ->
                  kn =
                    cond do
                      keypath == nil -> i
                      is_binary(keypath) and String.starts_with?(keypath, @s_bt) -> inject(keypath, merge(vlist_new([empty_map(), store, vmap_new([{@s_dtop, node}])]), 1))
                      true -> getpath(node, keypath, inj)
                    end

                  setprop(tsrc, kn, node)
                end)

                tpath = slice(ig(inj, :path), -1)
                ckey = getelem(ig(inj, :path), -2)
                dpath = flatten(vlist_new([@s_dtop, vlist_new(String.split(srcpath, ".")), "$:" <> js_string(ckey)]))

                tcur =
                  if size(tpath) > 1 do
                    pkey = getelem(ig(inj, :path), -3, @s_dtop)
                    setprop(dpath, size(dpath), "$:" <> js_string(pkey))
                    vmap_new([{js_string(pkey), vmap_new([{js_string(ckey), tsrc}])}])
                  else
                    vmap_new([{js_string(ckey), tsrc}])
                  end

                tinj = inj_child(inj, 0, vlist_new([ckey]))
                is_(tinj, :path, tpath)
                is_(tinj, :nodes, slice(ig(inj, :nodes), -1))
                is_(tinj, :parent, getelem(ig(tinj, :nodes), -1))
                is_(tinj, :ival, tval)
                is_(tinj, :dpath, dpath)
                is_(tinj, :dparent, tcur)
                inject(tval, store, tinj)
                ig(tinj, :ival)
              else
                empty_map()
              end

            setprop(target, tkey, rval)
            nil
          end
        end
    end
  end

  defp transform_ref(inj, val, _r, store) do
    if ig(inj, :mode) != @m_val do
      nil
    else
      nodes = ig(inj, :nodes)
      refpath = lookup_(ig(inj, :parent), 1)
      is_(inj, :keyi, size(ig(inj, :keys)))
      spec_func = getprop(store, @s_dspec)

      if not isfunc(spec_func) do
        nil
      else
        spec = spec_func.(inj, nil, "", store)
        refv = getpath(spec, refpath)
        flag = vlist_new([false])

        if isnode(refv) do
          walk(refv, after: fn _k, v2, _p, _path ->
            if v2 == "`$REF`", do: setprop(flag, 0, true)
            v2
          end)
        end

        has_sub = getelem(flag, 0) == true
        tref = clone(refv)
        cpath = slice(ig(inj, :path), 0, size(ig(inj, :path)) - 3)
        tpath = slice(ig(inj, :path), 0, size(ig(inj, :path)) - 1)
        tcur = getpath(store, cpath)
        tval = getpath(store, tpath)

        rval =
          if refv != nil and (not has_sub or tval != nil) do
            cs = inj_child(inj, 0, vlist_new([getelem(tpath, -1)]))
            is_(cs, :path, tpath)
            is_(cs, :nodes, slice(ig(inj, :nodes), 0, size(ig(inj, :nodes)) - 1))
            is_(cs, :parent, getelem(nodes, -2))
            is_(cs, :ival, tref)
            is_(cs, :dparent, tcur)
            inject(tref, store, cs)
            ig(cs, :ival)
          else
            nil
          end

        inj_setval(inj, rval, 2)

        if islist(ig(inj, :parent)) and ig(inj, :prior) != nil do
          is_(ig(inj, :prior), :keyi, ig(ig(inj, :prior), :keyi) - 1)
        end

        val
      end
    end
  end

  defp formatter_tbl do
    %{
      "identity" => fn _k, v -> v end,
      "upper" => fn _k, v -> if isnode(v), do: v, else: String.upcase(js_string(v)) end,
      "lower" => fn _k, v -> if isnode(v), do: v, else: String.downcase(js_string(v)) end,
      "string" => fn _k, v -> if isnode(v), do: v, else: js_string(v) end,
      "number" => fn _k, v ->
        if isnode(v) do
          v
        else
          n = parse_num(js_string(v))
          if is_intish(n), do: trunc(n), else: n
        end
      end,
      "integer" => fn _k, v -> if isnode(v), do: v, else: trunc(parse_num(js_string(v))) end,
      "concat" => fn k, v ->
        if k == nil and islist(v) do
          join(items_v(v, fn {_, x} -> if isnode(x), do: @s_mt, else: js_string(x) end), @s_mt)
        else
          v
        end
      end
    }
  end

  defp parse_num(s) do
    case Float.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end

  def check_placement(modes, ijname, parent_types, inj) do
    modenum = mode_to_num(ig(inj, :mode))

    cond do
      Bitwise.band(modes, modenum) == 0 ->
        allowed = Enum.filter([1, 2, 4], fn m -> Bitwise.band(modes, m) != 0 end)
        placements = allowed |> Enum.map(fn m -> if m == 4, do: "value", else: "key" end) |> Enum.join(",")
        cur = if modenum == 4, do: "value", else: "key"
        push_err(inj, "$" <> ijname <> ": invalid placement as " <> cur <> ", expected: " <> placements <> ".")
        false

      not isempty(parent_types) ->
        ptype = typify(ig(inj, :parent))

        if Bitwise.band(parent_types, ptype) == 0 do
          push_err(inj, "$" <> ijname <> ": invalid placement in parent " <> typename(ptype) <> ", expected: " <> typename(parent_types) <> ".")
          false
        else
          true
        end

      true ->
        true
    end
  end

  def injector_args(arg_types, args) do
    numargs = length(arg_types)
    found = injector_args_loop(arg_types, args, 0, numargs, List.duplicate(nil, 1 + numargs))
    vlist_new(found)
  end

  defp injector_args_loop(arg_types, args, argi, numargs, found) do
    if argi >= numargs do
      found
    else
      arg = getelem(args, argi)
      arg_type = typify(arg)
      at = Enum.at(arg_types, argi)

      if Bitwise.band(at, arg_type) == 0 do
        List.replace_at(found, 0, "invalid argument: " <> stringify(arg, 22) <> " (" <> typename(arg_type) <> " at position " <> Integer.to_string(1 + argi) <> ") is not of type: " <> typename(at) <> ".")
      else
        injector_args_loop(arg_types, args, argi + 1, numargs, List.replace_at(found, 1 + argi, arg))
      end
    end
  end

  def inject_child(child, store, inj) do
    cinj =
      if ig(inj, :prior) != nil do
        prior = ig(inj, :prior)

        if ig(prior, :prior) != nil do
          c = inj_child(ig(prior, :prior), ig(prior, :keyi), ig(prior, :keys))
          is_(c, :ival, child)
          setprop(ig(c, :parent), ig(prior, :key), child)
          c
        else
          c = inj_child(prior, ig(inj, :keyi), ig(inj, :keys))
          is_(c, :ival, child)
          setprop(ig(c, :parent), ig(inj, :key), child)
          c
        end
      else
        inj
      end

    inject(child, store, cinj)
    cinj
  end

  defp transform_format(inj, _v, _r, store) do
    slice(ig(inj, :keys), 0, 1, true)

    if ig(inj, :mode) != @m_val do
      nil
    else
      name = lookup_(ig(inj, :parent), 1)
      child = lookup_(ig(inj, :parent), 2)
      tkey = getelem(ig(inj, :path), -2)
      target = (fn -> t = getelem(ig(inj, :nodes), -2); if t == nil, do: getelem(ig(inj, :nodes), -1), else: t end).()
      cinj = inject_child(child, store, inj)
      resolved = ig(cinj, :ival)

      formatter =
        if Bitwise.band(@t_function, typify(name)) > 0 do
          fn k, v -> name.(dummy_inj(), v, js_string(k), nil) end
        else
          Map.get(formatter_tbl(), js_string(name))
        end

      if formatter == nil do
        push_err(inj, "$FORMAT: unknown format: " <> js_string(name) <> ".")
        nil
      else
        out = walk(resolved, after: fn k, v, _p, _path -> formatter.(k, v) end)
        setprop(target, tkey, out)
        out
      end
    end
  end

  defp transform_apply(inj, _v, _r, store) do
    if not check_placement(4, "APPLY", @t_list, inj) do
      nil
    else
      res = injector_args([@t_function, @t_any], slice(ig(inj, :parent), 1))
      err = getelem(res, 0)
      apply_fn = getelem(res, 1)
      child = if size(res) > 2, do: getelem(res, 2), else: nil

      if err != nil do
        push_err(inj, "$APPLY: " <> js_string(err))
        nil
      else
        tkey = getelem(ig(inj, :path), -2)
        target = (fn -> t = getelem(ig(inj, :nodes), -2); if t == nil, do: getelem(ig(inj, :nodes), -1), else: t end).()
        cinj = inject_child(child, store, inj)
        resolved = ig(cinj, :ival)
        out = apply_fn.(resolved, store, cinj)
        setprop(target, tkey, out)
        out
      end
    end
  end

  def transform(data, spec0, injdef \\ nil) do
    origspec = spec0
    spec = clone(spec0)
    extra = if injdef != nil, do: getprop(injdef, "extra"), else: nil
    collect = injdef != nil and getprop(injdef, "errs") != nil
    errs = if collect, do: getprop(injdef, "errs"), else: empty_list()
    extra_transforms = empty_map()
    extra_data = empty_map()

    if extra != nil do
      Enum.each(items_pairs(extra), fn {k, v} ->
        if String.starts_with?(k, @s_ds), do: setprop(extra_transforms, k, v), else: setprop(extra_data, k, v)
      end)
    end

    data_clone = merge(vlist_new([if(isempty(extra_data), do: nil, else: clone(extra_data)), clone(data)]))
    store = empty_map()
    setprop(store, @s_dtop, data_clone)
    setprop(store, @s_dspec, fn _i, _v, _r, _s -> origspec end)
    setprop(store, "$BT", fn _i, _v, _r, _s -> @s_bt end)
    setprop(store, "$DS", fn _i, _v, _r, _s -> @s_ds end)
    setprop(store, "$WHEN", fn _i, _v, _r, _s -> "1970-01-01T00:00:00.000Z" end)
    setprop(store, "$DELETE", &transform_delete/4)
    setprop(store, "$COPY", &transform_copy/4)
    setprop(store, "$KEY", &transform_key/4)
    setprop(store, "$ANNO", &transform_anno/4)
    setprop(store, "$MERGE", &transform_merge/4)
    setprop(store, "$EACH", &transform_each/4)
    setprop(store, "$PACK", &transform_pack/4)
    setprop(store, "$REF", &transform_ref/4)
    setprop(store, "$FORMAT", &transform_format/4)
    setprop(store, "$APPLY", &transform_apply/4)
    Enum.each(items_pairs(extra_transforms), fn {k, v} -> setprop(store, k, v) end)
    setprop(store, @s_derrs, errs)

    idef = empty_map()
    if ismap(injdef), do: Enum.each(items_pairs(injdef), fn {k, v} -> setprop(idef, k, v) end)
    setprop(idef, "errs", errs)
    out = inject(spec, store, idef)
    if size(errs) > 0 and not collect, do: raise(Voxgig.Struct.Error, message: join(errs, " | "))
    out
  end

  # ---------------------------------------------------------------------------
  # validate
  # ---------------------------------------------------------------------------

  defp push_err(inj, msg), do: setprop(ig(inj, :errs), size(ig(inj, :errs)), msg)

  defp invalid_type_msg(path, needtype, vt, v, _whence) do
    vs = if v == nil, do: "no value", else: stringify(v)

    "Expected " <>
      (if size(path) > 1, do: "field " <> pathify(path, 1) <> " to be ", else: "") <>
      needtype <>
      ", but found " <>
      (if v != nil, do: typename(vt) <> @s_viz, else: "") <>
      vs <> "."
  end

  defp validate_string(inj, _v, _r, _s) do
    out = lookup_(ig(inj, :dparent), ig(inj, :key))
    t = typify(out)

    cond do
      Bitwise.band(@t_string, t) == 0 -> push_err(inj, invalid_type_msg(ig(inj, :path), "string", t, out, "V1010")); nil
      out == @s_mt -> push_err(inj, "Empty string at " <> pathify(ig(inj, :path), 1)); nil
      true -> out
    end
  end

  defp validate_type(inj, _v, ref, _s) do
    tname = if is_binary(ref) and String.length(ref) > 1, do: String.downcase(String.slice(ref, 1, String.length(ref) - 1)), else: "any"
    idx = type_index(tname)
    typev0 = if idx >= 0, do: Bitwise.bsl(1, 31 - idx), else: 0
    typev = if tname == "nil", do: Bitwise.bor(typev0, @t_null), else: typev0
    out = lookup_(ig(inj, :dparent), ig(inj, :key))
    t = typify(out)

    if Bitwise.band(t, typev) == 0 do
      push_err(inj, invalid_type_msg(ig(inj, :path), tname, t, out, "V1001"))
      nil
    else
      out
    end
  end

  defp type_index(tname) do
    Enum.find_index(Tuple.to_list(@typename), fn x -> x == tname end) || -1
  end

  defp validate_any(inj, _v, _r, _s), do: lookup_(ig(inj, :dparent), ig(inj, :key))

  defp validate_child(inj, _v, _r, _s) do
    parent = ig(inj, :parent)
    key = ig(inj, :key)
    path = ig(inj, :path)
    keys = ig(inj, :keys)

    cond do
      ig(inj, :mode) == @m_keypre ->
        childtm = getprop(parent, key)
        pkey = getelem(path, -2)
        tval = getprop(ig(inj, :dparent), pkey)

        cond do
          tval == nil ->
            Enum.each(keysof(empty_map()), fn ckey -> setprop(parent, ckey, clone(childtm)); setprop(keys, size(keys), ckey) end)
            delprop(parent, key)
            nil

          not ismap(tval) ->
            push_err(inj, invalid_type_msg(slice(path, 0, size(path) - 1), "object", typify(tval), tval, "V0220"))
            nil

          true ->
            Enum.each(keysof(tval), fn ckey -> setprop(parent, ckey, clone(childtm)); setprop(keys, size(keys), ckey) end)
            delprop(parent, key)
            nil
        end

      ig(inj, :mode) == @m_val ->
        childtm = getprop(parent, 1)

        cond do
          not islist(parent) ->
            push_err(inj, "Invalid $CHILD as value")
            nil

          ig(inj, :dparent) == nil ->
            list_set_items(parent, [])
            nil

          not islist(ig(inj, :dparent)) ->
            push_err(inj, invalid_type_msg(slice(path, 0, size(path) - 1), "list", typify(ig(inj, :dparent)), ig(inj, :dparent), "V0230"))
            is_(inj, :keyi, size(parent))
            ig(inj, :dparent)

          true ->
            Enum.each(items_pairs(ig(inj, :dparent)), fn {k, _} -> setprop(parent, k, clone(childtm)) end)
            n = size(ig(inj, :dparent))
            list_set_items(parent, Enum.take(list_items(parent), n))
            is_(inj, :keyi, 0)
            getprop(ig(inj, :dparent), 0)
        end

      true ->
        nil
    end
  end

  defp validate_one(inj, _v, _r, store) do
    if ig(inj, :mode) != @m_val do
      nil
    else
      parent = ig(inj, :parent)

      if not islist(parent) or ig(inj, :keyi) != 0 do
        push_err(inj, "The $ONE validator at field " <> pathify(ig(inj, :path), 1, 1) <> " must be the first element of an array.")
        nil
      else
        is_(inj, :keyi, size(ig(inj, :keys)))
        inj_setval(inj, ig(inj, :dparent), 2)
        is_(inj, :path, slice(ig(inj, :path), 0, size(ig(inj, :path)) - 1))
        is_(inj, :key, getelem(ig(inj, :path), -1))
        tvals = slice(parent, 1)

        if size(tvals) == 0 do
          push_err(inj, "The $ONE validator at field " <> pathify(ig(inj, :path), 1, 1) <> " must have at least one argument.")
          nil
        else
          matched = validate_one_loop(inj, store, list_items(tvals), false)

          if not matched do
            valdesc = Enum.map_join(list_items(tvals), ", ", &stringify/1)
            valdesc = Regex.replace(@r_transform_name, valdesc, fn _w, g1 -> String.downcase(g1) end)
            push_err(inj, invalid_type_msg(ig(inj, :path), (if size(tvals) > 1, do: "one of ", else: "") <> valdesc, typify(ig(inj, :dparent)), ig(inj, :dparent), "V0210"))
          end

          nil
        end
      end
    end
  end

  defp validate_one_loop(_inj, _store, [], matched), do: matched

  defp validate_one_loop(inj, store, [tv | rest], matched) do
    if matched do
      true
    else
      terrs = empty_list()
      vstore = merge(vlist_new([empty_map(), store]), 1)
      setprop(vstore, @s_dtop, ig(inj, :dparent))
      idef = vmap_new([{"extra", vstore}, {"errs", terrs}, {"meta", ig(inj, :meta)}])
      vcurrent = validate(ig(inj, :dparent), tv, idef)
      inj_setval(inj, vcurrent, -2)
      if size(terrs) == 0, do: true, else: validate_one_loop(inj, store, rest, false)
    end
  end

  defp validate_exact(inj, _v, _r, _s) do
    if ig(inj, :mode) != @m_val do
      delprop(ig(inj, :parent), ig(inj, :key))
      nil
    else
      parent = ig(inj, :parent)

      if not islist(parent) or ig(inj, :keyi) != 0 do
        push_err(inj, "The $EXACT validator at field " <> pathify(ig(inj, :path), 1, 1) <> " must be the first element of an array.")
        nil
      else
        is_(inj, :keyi, size(ig(inj, :keys)))
        inj_setval(inj, ig(inj, :dparent), 2)
        is_(inj, :path, slice(ig(inj, :path), 0, size(ig(inj, :path)) - 1))
        is_(inj, :key, getelem(ig(inj, :path), -1))
        tvals = slice(parent, 1)

        if size(tvals) == 0 do
          push_err(inj, "The $EXACT validator at field " <> pathify(ig(inj, :path), 1, 1) <> " must have at least one argument.")
          nil
        else
          matched = Enum.any?(list_items(tvals), fn tv -> veq(tv, ig(inj, :dparent)) end)

          if not matched do
            valdesc = Enum.map_join(list_items(tvals), ", ", &stringify/1)
            valdesc = Regex.replace(@r_transform_name, valdesc, fn _w, g1 -> String.downcase(g1) end)
            push_err(inj, invalid_type_msg(ig(inj, :path), (if size(ig(inj, :path)) > 1, do: "", else: "value ") <> "exactly equal to " <> (if size(tvals) == 1, do: "", else: "one of ") <> valdesc, typify(ig(inj, :dparent)), ig(inj, :dparent), "V0110"))
          end

          nil
        end
      end
    end
  end

  def veq(a, b) do
    cond do
      a == nil and b == nil -> true
      is_boolean(a) or is_boolean(b) -> a == b
      is_number(a) and is_number(b) -> a == b
      is_binary(a) and is_binary(b) -> a == b
      islist(a) and islist(b) -> ia = list_items(a); ib = list_items(b); length(ia) == length(ib) and Enum.all?(Enum.zip(ia, ib), fn {x, y} -> veq(x, y) end)
      ismap(a) and ismap(b) -> veq_map(a, b)
      true -> a == b
    end
  end

  defp veq_map(a, b) do
    pa = map_pairs(a)
    pb = map_pairs(b)
    length(pa) == length(pb) and Enum.all?(pa, fn {k, v} -> case omap_get(pb, k) do; {:ok, w} -> veq(v, w); :error -> false end end)
  end

  defp validation(pval, key, parent, inj) do
    if is_skip(pval) do
      :ok
    else
      exact = getprop(ig(inj, :meta), @s_bexact, false)
      cval = getprop(ig(inj, :dparent), key)
      exact_b = exact == true

      if not exact_b and cval == nil do
        :ok
      else
        ptype = typify(pval)

        if Bitwise.band(@t_string, ptype) > 0 and String.contains?(js_string(pval), @s_ds) do
          :ok
        else
          ctype = typify(cval)

          cond do
            ptype != ctype and pval != nil ->
              push_err(inj, invalid_type_msg(ig(inj, :path), typename(ptype), ctype, cval, "V0010"))

            ismap(cval) ->
              if not ismap(pval) do
                push_err(inj, invalid_type_msg(ig(inj, :path), typename(ptype), ctype, cval, "V0020"))
              else
                ckeys = keysof(cval)
                pkeys = keysof(pval)

                if pkeys != [] and getprop(pval, @s_bopen) != true do
                  badkeys = Enum.filter(ckeys, fn ck -> lookup_(pval, ck) == nil end)
                  if badkeys != [], do: push_err(inj, "Unexpected keys at field " <> pathify(ig(inj, :path), 1) <> @s_viz <> Enum.join(badkeys, ", "))
                else
                  merge(vlist_new([pval, cval]))
                  if isnode(pval), do: delprop(pval, @s_bopen)
                end
              end

            islist(cval) ->
              if not islist(pval), do: push_err(inj, invalid_type_msg(ig(inj, :path), typename(ptype), ctype, cval, "V0030"))

            exact_b ->
              if not veq(cval, pval) do
                pathmsg = if size(ig(inj, :path)) > 1, do: "at field " <> pathify(ig(inj, :path), 1) <> ": ", else: ""
                push_err(inj, "Value " <> pathmsg <> js_string(cval) <> " should equal " <> js_string(pval) <> ".")
              end

            true ->
              setprop(parent, key, cval)
          end

          :ok
        end
      end
    end
  end

  defp validate_handler(inj, val, ref, store) do
    m = if is_binary(ref), do: Regex.run(@r_meta_path, ref), else: nil

    case m do
      [_, _, g2, _] ->
        if g2 == "=", do: inj_setval(inj, vlist_new([@s_bexact, val])), else: inj_setval(inj, val)
        is_(inj, :keyi, -1)
        @skip

      _ ->
        inject_handler(inj, val, ref, store)
    end
  end

  def validate(data, spec, injdef \\ nil) do
    extra = getprop(injdef, "extra")
    collect = injdef != nil and getprop(injdef, "errs") != nil
    errs = if collect, do: getprop(injdef, "errs"), else: empty_list()
    base = empty_map()
    Enum.each(["$DELETE", "$COPY", "$KEY", "$META", "$MERGE", "$EACH", "$PACK"], fn k -> setprop(base, k, nil) end)
    setprop(base, "$STRING", &validate_string/4)
    Enum.each(["$NUMBER", "$INTEGER", "$DECIMAL", "$BOOLEAN", "$NULL", "$NIL", "$MAP", "$LIST", "$FUNCTION", "$INSTANCE"], fn k -> setprop(base, k, &validate_type/4) end)
    setprop(base, "$ANY", &validate_any/4)
    setprop(base, "$CHILD", &validate_child/4)
    setprop(base, "$ONE", &validate_one/4)
    setprop(base, "$EXACT", &validate_exact/4)
    store = merge(vlist_new([base, if(extra == nil, do: empty_map(), else: extra), vmap_new([{@s_derrs, errs}])]), 1)
    meta = getprop(injdef, "meta", empty_map())
    setprop(meta, @s_bexact, getprop(meta, @s_bexact, false))
    idef = vmap_new([{"meta", meta}, {"extra", store}, {"modify", &validation/4}, {"handler", &validate_handler/4}, {"errs", errs}])
    out = transform(data, spec, idef)
    if size(errs) > 0 and not collect, do: raise(Voxgig.Struct.Error, message: join(errs, " | "))
    out
  end

  # ---------------------------------------------------------------------------
  # select
  # ---------------------------------------------------------------------------

  defp select_and(inj, _v, _r, store) do
    if ig(inj, :mode) == @m_keypre do
      terms = getprop(ig(inj, :parent), ig(inj, :key))
      ppath = slice(ig(inj, :path), -1)
      point = getpath(store, ppath)
      vstore = merge(vlist_new([empty_map(), store]), 1)
      setprop(vstore, @s_dtop, point)

      Enum.each(items_pairs(terms), fn {_, term} ->
        terrs = empty_list()
        validate(point, term, vmap_new([{"extra", vstore}, {"errs", terrs}, {"meta", ig(inj, :meta)}]))
        if size(terrs) != 0, do: push_err(inj, "AND:" <> pathify(ppath) <> "⨯" <> stringify(point) <> " fail:" <> stringify(terms))
      end)

      gkey = getelem(ig(inj, :path), -2)
      gp = getelem(ig(inj, :nodes), -2)
      setprop(gp, gkey, point)
    end

    nil
  end

  defp select_or(inj, _v, _r, store) do
    if ig(inj, :mode) == @m_keypre do
      terms = getprop(ig(inj, :parent), ig(inj, :key))
      ppath = slice(ig(inj, :path), -1)
      point = getpath(store, ppath)
      vstore = merge(vlist_new([empty_map(), store]), 1)
      setprop(vstore, @s_dtop, point)
      done = select_or_loop(inj, store, vstore, ppath, point, items_pairs(terms))
      if not done, do: push_err(inj, "OR:" <> pathify(ppath) <> "⨯" <> stringify(point) <> " fail:" <> stringify(terms))
    end

    nil
  end

  defp select_or_loop(_inj, _store, _vstore, _ppath, _point, []), do: false

  defp select_or_loop(inj, store, vstore, ppath, point, [{_, term} | rest]) do
    terrs = empty_list()
    validate(point, term, vmap_new([{"extra", vstore}, {"errs", terrs}, {"meta", ig(inj, :meta)}]))

    if size(terrs) == 0 do
      gkey = getelem(ig(inj, :path), -2)
      gp = getelem(ig(inj, :nodes), -2)
      setprop(gp, gkey, point)
      true
    else
      select_or_loop(inj, store, vstore, ppath, point, rest)
    end
  end

  defp select_not(inj, _v, _r, store) do
    if ig(inj, :mode) == @m_keypre do
      term = getprop(ig(inj, :parent), ig(inj, :key))
      ppath = slice(ig(inj, :path), -1)
      point = getpath(store, ppath)
      vstore = merge(vlist_new([empty_map(), store]), 1)
      setprop(vstore, @s_dtop, point)
      terrs = empty_list()
      validate(point, term, vmap_new([{"extra", vstore}, {"errs", terrs}, {"meta", ig(inj, :meta)}]))
      if size(terrs) == 0, do: push_err(inj, "NOT:" <> pathify(ppath) <> "⨯" <> stringify(point) <> " fail:" <> stringify(term))
      gkey = getelem(ig(inj, :path), -2)
      gp = getelem(ig(inj, :nodes), -2)
      setprop(gp, gkey, point)
    end

    nil
  end

  defp num_cmp(a, b, op) do
    if is_number(a) and is_number(b) do
      case op do
        :gt -> a > b
        :lt -> a < b
        :gte -> a >= b
        :lte -> a <= b
      end
    else
      false
    end
  end

  defp select_cmp(inj, _v, ref, store) do
    if ig(inj, :mode) == @m_keypre do
      term = getprop(ig(inj, :parent), ig(inj, :key))
      gkey = getelem(ig(inj, :path), -2)
      ppath = slice(ig(inj, :path), -1)
      point = getpath(store, ppath)

      pass =
        cond do
          ref == "$GT" -> num_cmp(point, term, :gt)
          ref == "$LT" -> num_cmp(point, term, :lt)
          ref == "$GTE" -> num_cmp(point, term, :gte)
          ref == "$LTE" -> num_cmp(point, term, :lte)
          ref == "$LIKE" -> is_binary(term) and Regex.match?(Regex.compile!(term), stringify(point))
          true -> false
        end

      if pass do
        gp = getelem(ig(inj, :nodes), -2)
        setprop(gp, gkey, point)
      else
        push_err(inj, "CMP: " <> pathify(ppath) <> "⨯" <> stringify(point) <> " fail:" <> js_string(ref) <> " " <> stringify(term))
      end
    end

    nil
  end

  def select(children0, query) do
    if not isnode(children0) do
      empty_list()
    else
      children =
        if ismap(children0) do
          vlist_new(Enum.map(items_pairs(children0), fn {k, n} -> setprop(n, @s_dkey, k); n end))
        else
          vlist_new(
            list_items(children0)
            |> Enum.with_index()
            |> Enum.map(fn {n, i} -> if ismap(n), do: (setprop(n, @s_dkey, i); n), else: n end)
          )
        end

      results = empty_list()
      extra = empty_map()
      setprop(extra, "$AND", &select_and/4)
      setprop(extra, "$OR", &select_or/4)
      setprop(extra, "$NOT", &select_not/4)
      setprop(extra, "$GT", &select_cmp/4)
      setprop(extra, "$LT", &select_cmp/4)
      setprop(extra, "$GTE", &select_cmp/4)
      setprop(extra, "$LTE", &select_cmp/4)
      setprop(extra, "$LIKE", &select_cmp/4)
      q = clone(query)

      walk(q, after: fn _k, v, _p, _path ->
        if ismap(v), do: setprop(v, @s_bopen, getprop(v, @s_bopen, true))
        v
      end)

      Enum.each(list_items(children), fn child ->
        errs = empty_list()
        meta = empty_map()
        setprop(meta, @s_bexact, true)
        idef = vmap_new([{"errs", errs}, {"meta", meta}, {"extra", extra}])
        validate(child, clone(q), idef)
        if size(errs) == 0, do: setprop(results, size(results), child)
      end)

      results
    end
  end

  # ---------------------------------------------------------------------------
  # builders
  # ---------------------------------------------------------------------------

  def jm(kv) do
    m = empty_map()
    n = length(kv)
    jm_loop(m, kv, n, 0)
    m
  end

  defp jm_loop(m, kv, n, i) do
    if i >= n do
      m
    else
      k0 = Enum.at(kv, i)
      k = cond do; k0 == nil -> "null"; is_binary(k0) -> k0; true -> stringify(k0) end
      setprop(m, k, if(i + 1 < n, do: Enum.at(kv, i + 1), else: nil))
      jm_loop(m, kv, n, i + 2)
    end
  end

  def jt(v), do: vlist_new(v)

  def tn(t), do: typename(t)
end

defmodule Voxgig.Struct.Error do
  defexception message: "struct error"
end
