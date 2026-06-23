-- Smoke test for the Lua test provider port. Prints summary stats that must
-- match the canonical TS output documented in PROVIDER.md.
--
-- Run from this directory:  lua smoke.lua
-- (Resolves the corpus relative to provider.lua's source location.)

-- Make `require("provider")` work regardless of cwd by adding this script's
-- directory to package.path.
local function this_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)[/\\][^/\\]*$") or "."
end
package.path = this_dir() .. "/?.lua;" .. package.path

local P = require("provider")

local JSON_NULL = P.JSON_NULL

-- Render a value for human-readable display (used for expect.value etc.).
local function show(v)
  if v == nil then
    return "nil"
  elseif v == JSON_NULL then
    return "null"
  elseif v == P.MISSING then
    return "<missing>"
  elseif type(v) == "boolean" then
    return v and "true" or "false"
  elseif type(v) == "string" then
    return v
  elseif type(v) == "number" then
    return P.json_encode(v)
  else
    return P.json_encode(v)
  end
end

local function main()
  local prov = P.load()

  local fns = prov:functions()
  print("functions: " .. table.concat(fns, ", "))

  local total = 0
  local expect_kinds = {}
  local input_kinds = {}
  for _, fn in ipairs(fns) do
    for _, entry in ipairs(prov:entries(fn)) do
      total = total + 1
      local ek = entry.expect.kind
      local ik = entry.input.kind
      expect_kinds[ek] = (expect_kinds[ek] or 0) + 1
      input_kinds[ik] = (input_kinds[ik] or 0) + 1
    end
  end

  print("total entries: " .. total)

  -- Sort kind names for stable output.
  local function sorted_kinds(counts)
    local ks = {}
    for k in pairs(counts) do
      ks[#ks + 1] = k
    end
    table.sort(ks)
    local parts = {}
    for _, k in ipairs(ks) do
      parts[#parts + 1] = k .. "=" .. counts[k]
    end
    return table.concat(parts, ", ")
  end

  print("expect kinds: " .. sorted_kinds(expect_kinds))
  print("input kinds: " .. sorted_kinds(input_kinds))

  local e = prov:entries("getpath", "basic")[1]
  print(
    "getpath/basic[0]: "
      .. "id=" .. tostring(e.id)
      .. ", doc=" .. tostring(e.doc)
      .. ", input.kind=" .. e.input.kind
      .. ", expect.kind=" .. e.expect.kind
      .. ", expect.value=" .. show(e.expect.value)
  )

  -- ─── helper sanity checks ────────────────────────────────────────────────
  print("equal(JSON_NULL, nil) lenient: " .. tostring(P.equal(JSON_NULL, nil)))
  print(
    "equal_strict(JSON_NULL, MISSING) vs (JSON_NULL, 1): "
      .. tostring(P.equal_strict(JSON_NULL, P.MISSING))
      .. " / "
      .. tostring(P.equal_strict(JSON_NULL, 1))
  )
  print(
    "error_matches substring case-insensitive: "
      .. tostring(P.error_matches({ any = false, text = "Foo", regex = false }, "a foobar error"))
  )

  -- struct_match failure shape: build a small object {a:{b:2}} vs {a:{b:3}}.
  local function obj(pairs_list)
    local o = { __obj = true, keys = {}, map = {} }
    for _, kv in ipairs(pairs_list) do
      table.insert(o.keys, kv[1])
      o.map[kv[1]] = kv[2]
    end
    return o
  end
  local check = obj({ { "a", obj({ { "b", 2 } }) } })
  local base = obj({ { "a", obj({ { "b", 3 } }) } })
  local sm = P.struct_match(check, base)
  print(
    "struct_match failure: ok=" .. tostring(sm.ok)
      .. (sm.ok and "" or (", path=" .. table.concat(sm.path, ".")
        .. ", expected=" .. show(sm.expected)
        .. ", actual=" .. show(sm.actual)))
  )
end

main()
