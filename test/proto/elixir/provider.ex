# Test Provider (prototype) — Elixir port of the canonical ts/provider.ts.
#
# Reads the shared corpus (build/test/test.json) and hands test code clean,
# normalized cases. It is NOT a test runner: it never calls the subject and
# never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
#
# Zero runtime dependencies: ships its OWN minimal JSON parser in pure Elixir
# (no Jason/Poison, and no reliance on the OTP :json module being present),
# matching repo policy.
#
# JSON value representation (Elixir maps do NOT preserve key order, which the
# provider needs for functions()/groups()):
#   * objects -> %Voxgig.Proto.Provider.Obj{order: [keys...], map: %{k => v}}
#                (string keys; `order` records insertion order)
#   * arrays  -> Elixir list
#   * strings -> binary
#   * numbers -> integer | float
#   * boolean -> true | false
#   * null    -> the :null atom (distinct from nil/absent)

defmodule Voxgig.Proto.Provider do
  # --- ordered JSON object -------------------------------------------------
  defmodule Obj do
    @moduledoc "Ordered JSON object: preserves key insertion order."
    defstruct order: [], map: %{}

    def new(pairs) when is_list(pairs) do
      Enum.reduce(pairs, %Obj{}, fn {k, v}, acc -> put(acc, k, v) end)
    end

    def put(%Obj{order: order, map: map} = o, k, v) do
      if Map.has_key?(map, k) do
        %Obj{o | map: Map.put(map, k, v)}
      else
        %Obj{order: order ++ [k], map: Map.put(map, k, v)}
      end
    end

    def has?(%Obj{map: map}, k), do: Map.has_key?(map, k)
    def get(%Obj{map: map}, k, default \\ nil), do: Map.get(map, k, default)
    def keys(%Obj{order: order}), do: order
  end

  alias Voxgig.Proto.Provider.Obj

  @nullmark "__NULL__"
  @undefmark "__UNDEF__"
  @existsmark "__EXISTS__"

  # Sentinel distinguishing "key absent" from "value is :null" in getpath.
  @missing :__provider_missing__

  # ---------------------------------------------------------------------------
  # Public API surface (PROVIDER.md §6)
  # ---------------------------------------------------------------------------

  # Default corpus path: build/test/test.json relative to the repo root.
  # This file lives at test/proto/elixir/provider.ex, so the repo root is three
  # levels up.
  def default_test_file do
    here = Path.dirname(__ENV__.file)
    Path.join([here, "..", "..", "..", "build", "test", "test.json"])
  end

  @doc "Parse a corpus file into a provider (the parsed spec)."
  def load(testfile \\ nil) do
    file = testfile || default_test_file()
    file |> File.read!() |> parse_json()
  end

  @doc "The parsed test.json (escape hatch)."
  def raw(provider), do: provider

  @doc ~S(Function names: ["minor","getpath",...].)
  def functions(provider) do
    root = root_node(provider)

    Obj.keys(root)
    |> Enum.filter(fn k ->
      v = Obj.get(root, k)
      is_group_bag(v) or has_groups(v)
    end)
  end

  @doc ~S(Group names for a function: ["basic","relative",...].)
  def groups(provider, fn_name) do
    node = fn_node(provider, fn_name)

    Obj.keys(node)
    |> Enum.filter(fn k -> k != "name" and is_group_bag(Obj.get(node, k)) end)
  end

  @doc "Normalized entries for a function, optionally a single group."
  def entries(provider, fn_name, group \\ nil) do
    node = fn_node(provider, fn_name)
    group_names = if group != nil, do: [group], else: groups(provider, fn_name)

    Enum.flat_map(group_names, fn g ->
      bag = Obj.get(node, g)

      if is_group_bag(bag) do
        set = Obj.get(bag, "set")

        set
        |> Enum.with_index()
        |> Enum.map(fn {entry, i} -> normalize(fn_name, g, i, entry) end)
      else
        []
      end
    end)
  end

  # The struct bag when present, else the top-level object.
  defp root_node(provider) do
    case provider do
      %Obj{} = o ->
        case Obj.get(o, "struct") do
          %Obj{} = s -> s
          _ -> o
        end

      _ ->
        provider
    end
  end

  defp fn_node(provider, fn_name) do
    struct_root =
      case provider do
        %Obj{} = o -> Obj.get(o, "struct")
        _ -> nil
      end

    node =
      cond do
        match?(%Obj{}, struct_root) and Obj.has?(struct_root, fn_name) ->
          Obj.get(struct_root, fn_name)

        match?(%Obj{}, provider) and Obj.has?(provider, fn_name) ->
          Obj.get(provider, fn_name)

        true ->
          nil
      end

    if node == nil, do: raise("Unknown function: #{fn_name}")
    node
  end

  # A group bag is an object with a `set` list.
  defp is_group_bag(%Obj{} = v), do: is_list(Obj.get(v, "set"))
  defp is_group_bag(_), do: false

  # A function node has at least one child group bag.
  defp has_groups(%Obj{} = v) do
    Enum.any?(Obj.keys(v), fn k -> k != "name" and is_group_bag(Obj.get(v, k)) end)
  end

  defp has_groups(_), do: false

  # ---------------------------------------------------------------------------
  # Normalization (PROVIDER.md §2-4)
  # ---------------------------------------------------------------------------

  defp normalize(fn_name, group, index, raw) do
    %{
      function: fn_name,
      group: group,
      index: index,
      id: opt_string(raw, "id"),
      doc: obj_get(raw, "doc") == true,
      client: opt_string(raw, "client"),
      input: resolve_input(raw),
      expect: resolve_expect(raw),
      raw: raw
    }
  end

  # str(raw[key]) if present and not null/nil, else nil (mirrors `!= null` in TS).
  defp opt_string(raw, key) do
    v = obj_get(raw, key)
    if v == nil or v == :null, do: nil, else: stringify(v)
  end

  defp obj_has(%Obj{} = o, k), do: Obj.has?(o, k)
  defp obj_has(_, _), do: false

  defp obj_get(%Obj{} = o, k), do: Obj.get(o, k)
  defp obj_get(_, _), do: nil

  # §3 Input: precedence ctx > args > in. Absent "in" key => :null.
  defp resolve_input(raw) do
    cond do
      obj_has(raw, "ctx") -> %{kind: :ctx, ctx: obj_get(raw, "ctx")}
      obj_has(raw, "args") -> %{kind: :args, args: obj_get(raw, "args")}
      true -> %{kind: :in, in: if(obj_has(raw, "in"), do: obj_get(raw, "in"), else: :null)}
    end
  end

  defp parse_err(err) do
    cond do
      err == true ->
        %{any: true, text: nil, regex: false}

      is_binary(err) ->
        case Regex.run(~r{^/(.+)/$}, err) do
          [_, inner] -> %{any: false, text: inner, regex: true}
          nil -> %{any: false, text: err, regex: false}
        end

      true ->
        # Non-true, non-string err spec: treat as "any error".
        %{any: true, text: nil, regex: false}
    end
  end

  # §4 Expect: precedence err > out > match > absent. "out" present (even :null)
  # => :value, decided by KEY PRESENCE not truthiness. Attach match whenever a
  # "match" key exists.
  defp resolve_expect(raw) do
    match_part = if obj_has(raw, "match"), do: obj_get(raw, "match"), else: nil

    cond do
      obj_has(raw, "err") ->
        %{kind: :error, error: parse_err(obj_get(raw, "err")), match: match_part}

      obj_has(raw, "out") ->
        %{kind: :value, value: obj_get(raw, "out"), match: match_part}

      obj_has(raw, "match") ->
        %{kind: :match, match: obj_get(raw, "match")}

      true ->
        %{kind: :absent}
    end
  end

  # ---------------------------------------------------------------------------
  # Pure comparison helpers (PROVIDER.md §5)
  # ---------------------------------------------------------------------------

  # stringify(x) = x if it's already a string, else compact JSON.
  def stringify(x) when is_binary(x), do: x
  def stringify(x), do: encode_json(x)

  # Collapse __NULL__ / :null / nil to a single canonical null (:null) for
  # lenient (flags.null == true) deep equality.
  defp norm_null(@nullmark), do: :null
  defp norm_null(nil), do: :null
  defp norm_null(:null), do: :null
  defp norm_null(x) when is_list(x), do: Enum.map(x, &norm_null/1)

  defp norm_null(%Obj{} = o) do
    Obj.new(Enum.map(Obj.keys(o), fn k -> {k, norm_null(Obj.get(o, k))} end))
  end

  defp norm_null(x), do: x

  # Strict variant for {null: false} functions: only __NULL__ collapses to null;
  # an absent value (nil) stays distinct from JSON null (:null).
  defp norm_mark(@nullmark), do: :null
  defp norm_mark(x) when is_list(x), do: Enum.map(x, &norm_mark/1)

  defp norm_mark(%Obj{} = o) do
    Obj.new(Enum.map(Obj.keys(o), fn k -> {k, norm_mark(Obj.get(o, k))} end))
  end

  defp norm_mark(x), do: x

  @doc """
  Scalar primitive match (matchval): `check == base`; else if `check` is a
  string, "/re/" => regex test on stringify(base), otherwise case-insensitive
  substring; else if `check` is a function => true.
  """
  def matchval(check, base) do
    cond do
      check === base ->
        true

      is_binary(check) ->
        basestr = stringify(base)

        case Regex.run(~r{^/(.+)/$}, check) do
          [_, inner] ->
            Regex.match?(Regex.compile!(inner), basestr)

          nil ->
            String.contains?(String.downcase(basestr), String.downcase(check))
        end

      is_function(check) ->
        true

      true ->
        false
    end
  end

  @doc "Deep equality with null/absent collapsed (runner default null:true)."
  def equal(expected, actual) do
    deep_eq(norm_null(expected), norm_null(actual))
  end

  @doc "Deep equality where absent (nil) is distinct from null (runner null:false)."
  def equal_strict(expected, actual) do
    deep_eq(norm_mark(expected), norm_mark(actual))
  end

  defp deep_eq(a, b) do
    cond do
      # Guard against any accidental bool/number coercion; mirror JS ===.
      is_boolean(a) or is_boolean(b) ->
        a === b

      a === b ->
        true

      is_list(a) and is_list(b) ->
        length(a) == length(b) and
          a |> Enum.zip(b) |> Enum.all?(fn {x, y} -> deep_eq(x, y) end)

      match?(%Obj{}, a) and match?(%Obj{}, b) ->
        ak = Obj.keys(a)
        bk = Obj.keys(b)

        length(ak) == length(bk) and
          Enum.all?(ak, fn k -> Obj.has?(b, k) and deep_eq(Obj.get(a, k), Obj.get(b, k)) end)

      is_list(a) or is_list(b) ->
        false

      match?(%Obj{}, a) or match?(%Obj{}, b) ->
        false

      true ->
        a == b
    end
  end

  @doc "ErrorCheck vs a thrown message."
  def error_matches(%{any: true}, _message), do: true

  def error_matches(%{text: nil}, _message), do: false

  def error_matches(%{text: text, regex: regex}, message) do
    if regex do
      Regex.match?(Regex.compile!(text), message)
    else
      String.contains?(String.downcase(message), String.downcase(text))
    end
  end

  @doc """
  Partial structural match: every leaf of `check` must match `base` at its
  path. Returns %{ok: bool, path?, expected?, actual?}. First failure wins.
  """
  def struct_match(check, base) do
    walk_leaves(check, [], %{ok: true}, fn val, path, result ->
      if not result.ok do
        result
      else
        baseval = getpath(base, path)

        cond do
          baseval != @missing and deep_eq_leaf(baseval, val) ->
            result

          val == @undefmark and baseval == @missing ->
            result

          val == @existsmark and baseval != @missing and baseval != :null ->
            result

          true ->
            compare_base = if baseval == @missing, do: :null, else: baseval

            if matchval(val, compare_base) do
              result
            else
              %{ok: false, path: path, expected: val, actual: compare_base}
            end
        end
      end
    end)
  end

  # Leaf-level equality used inside struct_match (scalars; :null tolerant).
  defp deep_eq_leaf(a, b), do: a === b

  defp walk_leaves(node, path, acc, fun) when is_list(node) do
    node
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {v, i}, a ->
      walk_leaves(v, path ++ [Integer.to_string(i)], a, fun)
    end)
  end

  defp walk_leaves(%Obj{} = node, path, acc, fun) do
    Enum.reduce(Obj.keys(node), acc, fn k, a ->
      walk_leaves(Obj.get(node, k), path ++ [k], a, fun)
    end)
  end

  defp walk_leaves(leaf, path, acc, fun), do: fun.(leaf, path, acc)

  # getpath over the ordered representation; returns @missing when absent.
  defp getpath(store, path) do
    Enum.reduce_while(path, store, fn key, cur ->
      cond do
        cur == nil or cur == :null or cur == @missing ->
          {:halt, @missing}

        is_list(cur) ->
          idx = String.to_integer(key)

          if idx >= 0 and idx < length(cur) do
            {:cont, Enum.at(cur, idx)}
          else
            {:halt, @missing}
          end

        match?(%Obj{}, cur) ->
          if Obj.has?(cur, key), do: {:cont, Obj.get(cur, key)}, else: {:halt, @missing}

        true ->
          {:halt, @missing}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Minimal JSON encoder (compact) — for stringify / matchval.
  # ---------------------------------------------------------------------------

  defp encode_json(:null), do: "null"
  defp encode_json(nil), do: "null"
  defp encode_json(true), do: "true"
  defp encode_json(false), do: "false"
  defp encode_json(n) when is_integer(n), do: Integer.to_string(n)

  defp encode_json(n) when is_float(n) do
    # Render integral floats without a trailing ".0" to mirror JS JSON.stringify.
    if Float.round(n) == n and abs(n) < 1.0e16 do
      Integer.to_string(trunc(n))
    else
      Float.to_string(n)
    end
  end

  defp encode_json(s) when is_binary(s), do: encode_string(s)

  defp encode_json(l) when is_list(l) do
    "[" <> (l |> Enum.map(&encode_json/1) |> Enum.join(",")) <> "]"
  end

  defp encode_json(%Obj{} = o) do
    body =
      Obj.keys(o)
      |> Enum.map(fn k -> encode_string(k) <> ":" <> encode_json(Obj.get(o, k)) end)
      |> Enum.join(",")

    "{" <> body <> "}"
  end

  defp encode_json(f) when is_function(f), do: "null"

  defp encode_string(s) do
    inner =
      s
      |> String.to_charlist()
      |> Enum.map(&escape_char/1)
      |> IO.iodata_to_binary()

    "\"" <> inner <> "\""
  end

  defp escape_char(?"), do: "\\\""
  defp escape_char(?\\), do: "\\\\"
  defp escape_char(?\n), do: "\\n"
  defp escape_char(?\r), do: "\\r"
  defp escape_char(?\t), do: "\\t"
  defp escape_char(8), do: "\\b"
  defp escape_char(12), do: "\\f"
  defp escape_char(c) when c < 0x20, do: "\\u" <> pad4(Integer.to_string(c, 16))
  defp escape_char(c), do: <<c::utf8>>

  defp pad4(hex), do: String.pad_leading(String.downcase(hex), 4, "0")

  # ---------------------------------------------------------------------------
  # Minimal JSON parser (pure Elixir). Objects -> Obj, arrays -> list, strings
  # -> binary, numbers -> integer|float, booleans -> true|false, null -> :null.
  # ---------------------------------------------------------------------------

  defp parse_json(str) do
    {v, rest} = parse_value(str)

    case skip_ws(rest) do
      "" -> v
      _ -> v
    end
  end

  defp skip_ws(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r], do: skip_ws(rest)
  defp skip_ws(s), do: s

  defp parse_value(s) do
    s = skip_ws(s)

    case s do
      "{" <> rest -> parse_object(rest, [])
      "[" <> rest -> parse_array(rest, [])
      "\"" <> rest -> parse_string_raw(rest, [])
      "true" <> rest -> {true, rest}
      "false" <> rest -> {false, rest}
      "null" <> rest -> {:null, rest}
      _ -> parse_number(s)
    end
  end

  defp parse_object(s, acc) do
    s = skip_ws(s)

    case s do
      "}" <> rest ->
        {Obj.new(Enum.reverse(acc)), rest}

      _ ->
        "\"" <> s1 = s
        {key, s2} = parse_string_raw(s1, [])
        s3 = skip_ws(s2)
        ":" <> s4 = s3
        {val, s5} = parse_value(s4)
        s6 = skip_ws(s5)

        case s6 do
          "," <> r -> parse_object(r, [{key, val} | acc])
          "}" <> r -> parse_object("}" <> r, [{key, val} | acc])
        end
    end
  end

  defp parse_array(s, acc) do
    s = skip_ws(s)

    case s do
      "]" <> rest ->
        {Enum.reverse(acc), rest}

      _ ->
        {val, s1} = parse_value(s)
        s2 = skip_ws(s1)

        case s2 do
          "," <> r -> parse_array(r, [val | acc])
          "]" <> r -> parse_array("]" <> r, [val | acc])
        end
    end
  end

  defp parse_string_raw("\"" <> rest, acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), rest}

  defp parse_string_raw("\\" <> <<c, rest::binary>>, acc) do
    case c do
      ?" -> parse_string_raw(rest, ["\"" | acc])
      ?\\ -> parse_string_raw(rest, ["\\" | acc])
      ?/ -> parse_string_raw(rest, ["/" | acc])
      ?n -> parse_string_raw(rest, ["\n" | acc])
      ?r -> parse_string_raw(rest, ["\r" | acc])
      ?t -> parse_string_raw(rest, ["\t" | acc])
      ?b -> parse_string_raw(rest, [<<8>> | acc])
      ?f -> parse_string_raw(rest, [<<12>> | acc])
      ?u ->
        <<hex::binary-size(4), rest2::binary>> = rest
        code = String.to_integer(hex, 16)
        parse_string_raw(rest2, [<<code::utf8>> | acc])
    end
  end

  defp parse_string_raw(<<c::utf8, rest::binary>>, acc),
    do: parse_string_raw(rest, [<<c::utf8>> | acc])

  defp parse_number(s) do
    {numstr, rest} = take_number(s, [])
    n = IO.iodata_to_binary(Enum.reverse(numstr))

    val =
      if String.contains?(n, ".") or String.contains?(n, "e") or String.contains?(n, "E") do
        {f, ""} = Float.parse(n)
        f
      else
        String.to_integer(n)
      end

    {val, rest}
  end

  defp take_number(<<c, rest::binary>>, acc)
       when c in ?0..?9 or c in [?-, ?+, ?., ?e, ?E],
       do: take_number(rest, [<<c>> | acc])

  defp take_number(s, acc), do: {acc, s}
end
