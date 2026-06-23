-- Test Provider (prototype) — Lua (5.3/5.4) port of the canonical ts/provider.ts.
--
-- Reads the shared corpus (build/test/test.json) and hands test code clean,
-- normalized cases. It is NOT a test runner: it never calls the subject and
-- never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
--
-- DEPENDENCY-FREE: no dkjson, no lfs, no LuaRocks deps. The JSON parser below
-- is a self-contained pure-Lua recursive-descent parser; files are read with
-- io.open.
--
-- Data model note (the crux of the port):
--   Lua tables cannot preserve insertion order for string keys, and cannot
--   store nil as a value. JSON ordering matters here (functions()/groups()
--   enumerate keys in corpus order) and JSON null must stay distinct from
--   "key absent". So we represent parsed JSON as:
--     * OBJECT -> { __obj = true, keys = {ordered key list}, map = {k = v} }
--     * ARRAY  -> { __arr = true, items = {1-based value list} }
--     * null   -> the unique sentinel table JSON_NULL
--     * string/number/boolean -> native Lua values
--   Key PRESENCE is tested via the object's map (a key can be present with a
--   JSON_NULL value), never via truthiness.

local M = {}

local NULLMARK = "__NULL__" -- Value is JSON null
local UNDEFMARK = "__UNDEF__" -- Value is not present (thus undefined)
local EXISTSMARK = "__EXISTS__" -- Value exists (not undefined)

-- Unique sentinel for JSON null (distinguishes from absent and from the
-- literal string "null").
local JSON_NULL = setmetatable({}, {
  __tostring = function()
    return "null"
  end,
})

-- Unique sentinel meaning "no value at this path" (mirrors TS undefined /
-- Python _MISSING). Distinct from JSON_NULL.
local MISSING = setmetatable({}, {
  __tostring = function()
    return "<missing>"
  end,
})

M.NULLMARK = NULLMARK
M.UNDEFMARK = UNDEFMARK
M.EXISTSMARK = EXISTSMARK
M.JSON_NULL = JSON_NULL
M.MISSING = MISSING

----------------------------------------------------------
-- Object / array helpers (our ordered-object representation)
----------------------------------------------------------

local function is_obj(v)
  return type(v) == "table" and v.__obj == true
end

local function is_arr(v)
  return type(v) == "table" and v.__arr == true
end

-- Is `v` a "node" (object or array), i.e. a recursable container?
local function is_node(v)
  return is_obj(v) or is_arr(v)
end

local function new_obj()
  return { __obj = true, keys = {}, map = {} }
end

local function new_arr()
  return { __arr = true, items = {} }
end

-- Does an object have `key` present (even if its value is JSON_NULL)?
local function obj_has(o, key)
  if not is_obj(o) then
    return false
  end
  -- map cannot store nil values, but JSON null is stored as JSON_NULL, so a
  -- present key always has a non-nil map entry. Still, guard via keys list to
  -- be unambiguous.
  for _, k in ipairs(o.keys) do
    if k == key then
      return true
    end
  end
  return false
end

-- Get an object's value for `key`; returns MISSING if the key is absent.
local function obj_get(o, key)
  if is_obj(o) and obj_has(o, key) then
    return o.map[key]
  end
  return MISSING
end

-- Set an object's key/value, appending the key if new (preserving order).
local function obj_set(o, key, value)
  if not obj_has(o, key) then
    table.insert(o.keys, key)
  end
  o.map[key] = value
end

M.is_obj = is_obj
M.is_arr = is_arr
M.is_node = is_node
M.obj_has = obj_has
M.obj_get = obj_get

----------------------------------------------------------
-- Pure-Lua recursive-descent JSON parser
----------------------------------------------------------
-- Handles: objects (order preserved), arrays, strings (with \uXXXX, surrogate
-- pairs, and standard escapes), numbers (negative, fractional, exponents),
-- true/false/null, and surrounding whitespace.

local json_parse_value -- forward decl

-- Parse error helper.
local function jerror(str, pos, msg)
  -- Compute a 1-based line/col for a friendlier message.
  local line, col = 1, 1
  for i = 1, pos - 1 do
    if str:sub(i, i) == "\n" then
      line = line + 1
      col = 1
    else
      col = col + 1
    end
  end
  error(string.format("JSON parse error at line %d col %d (byte %d): %s", line, col, pos, msg), 0)
end

local function is_ws(c)
  return c == " " or c == "\t" or c == "\n" or c == "\r"
end

-- Skip whitespace, returning the next significant position.
local function skip_ws(str, pos)
  local len = #str
  while pos <= len and is_ws(str:sub(pos, pos)) do
    pos = pos + 1
  end
  return pos
end

-- Encode a Unicode code point as UTF-8 (pure Lua; no utf8 library reliance,
-- though Lua 5.3+ has utf8.char — we implement directly for clarity/safety).
local function utf8_encode(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(
      0xC0 + math.floor(cp / 0x40),
      0x80 + (cp % 0x40)
    )
  elseif cp < 0x10000 then
    return string.char(
      0xE0 + math.floor(cp / 0x1000),
      0x80 + (math.floor(cp / 0x40) % 0x40),
      0x80 + (cp % 0x40)
    )
  else
    return string.char(
      0xF0 + math.floor(cp / 0x40000),
      0x80 + (math.floor(cp / 0x1000) % 0x40),
      0x80 + (math.floor(cp / 0x40) % 0x40),
      0x80 + (cp % 0x40)
    )
  end
end

local ESCAPES = {
  ['"'] = '"',
  ["\\"] = "\\",
  ["/"] = "/",
  ["b"] = "\b",
  ["f"] = "\f",
  ["n"] = "\n",
  ["r"] = "\r",
  ["t"] = "\t",
}

local function parse_hex4(str, pos)
  local hex = str:sub(pos, pos + 3)
  if #hex < 4 or not hex:match("^%x%x%x%x$") then
    jerror(str, pos, "invalid \\u escape (expected 4 hex digits)")
  end
  return tonumber(hex, 16), pos + 4
end

-- Parse a JSON string starting at the opening quote.
-- Returns (string, next_pos).
local function parse_string(str, pos)
  -- str:sub(pos,pos) == '"'
  pos = pos + 1
  local parts = {}
  local len = #str
  while pos <= len do
    local c = str:sub(pos, pos)
    if c == '"' then
      return table.concat(parts), pos + 1
    elseif c == "\\" then
      pos = pos + 1
      local e = str:sub(pos, pos)
      if e == "u" then
        local cp
        cp, pos = parse_hex4(str, pos + 1)
        -- Handle UTF-16 surrogate pairs.
        if cp >= 0xD800 and cp <= 0xDBFF then
          if str:sub(pos, pos + 1) == "\\u" then
            local lo
            lo, pos = parse_hex4(str, pos + 2)
            if lo >= 0xDC00 and lo <= 0xDFFF then
              cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
            else
              -- Unpaired high surrogate followed by a non-low \u escape;
              -- emit the replacement char then continue with `lo` as its own.
              parts[#parts + 1] = utf8_encode(0xFFFD)
              cp = lo
            end
          else
            -- Lone high surrogate.
            cp = 0xFFFD
          end
        elseif cp >= 0xDC00 and cp <= 0xDFFF then
          -- Lone low surrogate.
          cp = 0xFFFD
        end
        parts[#parts + 1] = utf8_encode(cp)
      else
        local mapped = ESCAPES[e]
        if mapped == nil then
          jerror(str, pos, "invalid escape \\" .. e)
        end
        parts[#parts + 1] = mapped
        pos = pos + 1
      end
    elseif c == "\n" or c == "\r" then
      jerror(str, pos, "unescaped control character in string")
    else
      parts[#parts + 1] = c
      pos = pos + 1
    end
  end
  jerror(str, pos, "unterminated string")
end

-- Parse a JSON number starting at `pos`. Returns (number, next_pos).
-- Grammar: -?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?
local function parse_number(str, pos)
  local start = pos
  local len = #str
  local c = str:sub(pos, pos)

  if c == "-" then
    pos = pos + 1
    c = str:sub(pos, pos)
  end

  -- Integer part.
  if c == "0" then
    pos = pos + 1
  elseif c:match("%d") then
    while pos <= len and str:sub(pos, pos):match("%d") do
      pos = pos + 1
    end
  else
    jerror(str, pos, "invalid number (expected digit)")
  end

  -- Fraction.
  if str:sub(pos, pos) == "." then
    pos = pos + 1
    if not str:sub(pos, pos):match("%d") then
      jerror(str, pos, "invalid number (expected digit after '.')")
    end
    while pos <= len and str:sub(pos, pos):match("%d") do
      pos = pos + 1
    end
  end

  -- Exponent.
  local ec = str:sub(pos, pos)
  if ec == "e" or ec == "E" then
    pos = pos + 1
    local sign = str:sub(pos, pos)
    if sign == "+" or sign == "-" then
      pos = pos + 1
    end
    if not str:sub(pos, pos):match("%d") then
      jerror(str, pos, "invalid number (expected digit in exponent)")
    end
    while pos <= len and str:sub(pos, pos):match("%d") do
      pos = pos + 1
    end
  end

  local numstr = str:sub(start, pos - 1)
  local n = tonumber(numstr)
  if n == nil then
    jerror(str, start, "invalid number: " .. numstr)
  end
  return n, pos
end

local function parse_array(str, pos)
  -- str:sub(pos,pos) == '['
  pos = pos + 1
  local arr = new_arr()
  pos = skip_ws(str, pos)
  if str:sub(pos, pos) == "]" then
    return arr, pos + 1
  end
  while true do
    local val
    val, pos = json_parse_value(str, pos)
    arr.items[#arr.items + 1] = val
    pos = skip_ws(str, pos)
    local c = str:sub(pos, pos)
    if c == "," then
      pos = skip_ws(str, pos + 1)
    elseif c == "]" then
      return arr, pos + 1
    else
      jerror(str, pos, "expected ',' or ']' in array")
    end
  end
end

local function parse_object(str, pos)
  -- str:sub(pos,pos) == '{'
  pos = pos + 1
  local obj = new_obj()
  pos = skip_ws(str, pos)
  if str:sub(pos, pos) == "}" then
    return obj, pos + 1
  end
  while true do
    pos = skip_ws(str, pos)
    if str:sub(pos, pos) ~= '"' then
      jerror(str, pos, "expected string key in object")
    end
    local key
    key, pos = parse_string(str, pos)
    pos = skip_ws(str, pos)
    if str:sub(pos, pos) ~= ":" then
      jerror(str, pos, "expected ':' after object key")
    end
    pos = skip_ws(str, pos + 1)
    local val
    val, pos = json_parse_value(str, pos)
    -- Preserve insertion order; later duplicate keys overwrite the value but
    -- keep their original position (mirrors JSON.parse semantics closely
    -- enough for the corpus, which has no duplicate keys).
    obj_set(obj, key, val)
    pos = skip_ws(str, pos)
    local c = str:sub(pos, pos)
    if c == "," then
      pos = pos + 1
    elseif c == "}" then
      return obj, pos + 1
    else
      jerror(str, pos, "expected ',' or '}' in object")
    end
  end
end

json_parse_value = function(str, pos)
  pos = skip_ws(str, pos)
  local c = str:sub(pos, pos)
  if c == "" then
    jerror(str, pos, "unexpected end of input")
  elseif c == "{" then
    return parse_object(str, pos)
  elseif c == "[" then
    return parse_array(str, pos)
  elseif c == '"' then
    return parse_string(str, pos)
  elseif c == "t" then
    if str:sub(pos, pos + 3) == "true" then
      return true, pos + 4
    end
    jerror(str, pos, "invalid literal (expected 'true')")
  elseif c == "f" then
    if str:sub(pos, pos + 4) == "false" then
      return false, pos + 5
    end
    jerror(str, pos, "invalid literal (expected 'false')")
  elseif c == "n" then
    if str:sub(pos, pos + 3) == "null" then
      return JSON_NULL, pos + 4
    end
    jerror(str, pos, "invalid literal (expected 'null')")
  elseif c == "-" or c:match("%d") then
    return parse_number(str, pos)
  else
    jerror(str, pos, "unexpected character '" .. c .. "'")
  end
end

-- Public: parse a JSON document string into our representation.
local function json_decode(str)
  local val, pos = json_parse_value(str, 1)
  pos = skip_ws(str, pos)
  if pos <= #str then
    jerror(str, pos, "trailing characters after JSON value")
  end
  return val
end

M.json_decode = json_decode

----------------------------------------------------------
-- Compact JSON serialization (for stringify)
----------------------------------------------------------

local json_encode -- forward decl

local function encode_string(s)
  local out = { '"' }
  for i = 1, #s do
    local c = s:sub(i, i)
    local b = c:byte()
    if c == '"' then
      out[#out + 1] = '\\"'
    elseif c == "\\" then
      out[#out + 1] = "\\\\"
    elseif c == "\n" then
      out[#out + 1] = "\\n"
    elseif c == "\r" then
      out[#out + 1] = "\\r"
    elseif c == "\t" then
      out[#out + 1] = "\\t"
    elseif c == "\b" then
      out[#out + 1] = "\\b"
    elseif c == "\f" then
      out[#out + 1] = "\\f"
    elseif b < 0x20 then
      out[#out + 1] = string.format("\\u%04x", b)
    else
      out[#out + 1] = c
    end
  end
  out[#out + 1] = '"'
  return table.concat(out)
end

-- Format a number like JSON would (integers without trailing ".0").
local function encode_number(n)
  if n ~= n then
    return "null" -- NaN -> null (JSON has no NaN)
  end
  if n == math.huge or n == -math.huge then
    return "null"
  end
  if math.type then
    if math.type(n) == "integer" then
      return string.format("%d", n)
    end
  elseif n == math.floor(n) and math.abs(n) < 1e15 then
    return string.format("%d", n)
  end
  -- Float: use %.17g then strip, but %.14g is closer to JS for most corpus
  -- values. Prefer integer-looking floats to print without a fraction.
  if n == math.floor(n) and math.abs(n) < 1e15 then
    return string.format("%d", math.floor(n))
  end
  return string.format("%.17g", n)
end

json_encode = function(v)
  if v == JSON_NULL or v == nil then
    return "null"
  elseif v == MISSING then
    return "null"
  elseif type(v) == "boolean" then
    return v and "true" or "false"
  elseif type(v) == "number" then
    return encode_number(v)
  elseif type(v) == "string" then
    return encode_string(v)
  elseif is_arr(v) then
    local parts = {}
    for i = 1, #v.items do
      parts[i] = json_encode(v.items[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
  elseif is_obj(v) then
    local parts = {}
    for _, k in ipairs(v.keys) do
      parts[#parts + 1] = encode_string(k) .. ":" .. json_encode(v.map[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  else
    -- Fallback for unexpected native tables/functions.
    return "null"
  end
end

M.json_encode = json_encode

----------------------------------------------------------
-- File IO
----------------------------------------------------------

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    error("Cannot open file: " .. path, 0)
  end
  local content = file:read("*a")
  file:close()
  return content
end

-- Directory of THIS script (provider.lua), used to resolve the default corpus
-- path relative to the source location rather than the cwd.
local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  local dir = src:match("^(.*)[/\\][^/\\]*$")
  return dir or "."
end

-- Default corpus path: build/test/test.json relative to the repo root
-- (test/proto/lua -> ../../../build/test/test.json).
local function default_test_file()
  return script_dir() .. "/../../../build/test/test.json"
end

M.default_test_file = default_test_file

----------------------------------------------------------
-- Normalization helpers
----------------------------------------------------------

-- A group bag is an object with a `set` array.
local function is_group_bag(v)
  if not is_obj(v) then
    return false
  end
  return is_arr(obj_get(v, "set"))
end

-- A function node has at least one child group bag (excluding `name`).
local function has_groups(v)
  if not is_obj(v) then
    return false
  end
  for _, k in ipairs(v.keys) do
    if k ~= "name" and is_group_bag(v.map[k]) then
      return true
    end
  end
  return false
end

-- A raw scalar -> "value present?" Uses obj_has so JSON_NULL counts present.
local function raw_has(raw, key)
  return obj_has(raw, key)
end

local function raw_get(raw, key)
  return obj_get(raw, key)
end

-- Convert MISSING -> nil for fields where absence should read as nil.
local function or_nil(v)
  if v == MISSING then
    return nil
  end
  return v
end

local function resolve_input(raw)
  if raw_has(raw, "ctx") then
    return { kind = "ctx", ctx = or_nil(raw_get(raw, "ctx")) }
  end
  if raw_has(raw, "args") then
    return { kind = "args", args = or_nil(raw_get(raw, "args")) }
  end
  -- kind == in. Key absent => native null (JSON_NULL sentinel, matching the
  -- runner's "absent in => null" treatment while staying distinct from a
  -- present JSON null, which is also JSON_NULL here).
  if raw_has(raw, "in") then
    return { kind = "in", ["in"] = raw_get(raw, "in") }
  end
  return { kind = "in", ["in"] = JSON_NULL }
end

local function parse_err(err)
  if err == true then
    return { any = true, text = nil, regex = false }
  end
  if type(err) == "string" then
    local inner = err:match("^/(.+)/$")
    if inner then
      return { any = false, text = inner, regex = true }
    end
    return { any = false, text = err, regex = false }
  end
  -- Non-true, non-string err spec: treat as "any error".
  return { any = true, text = nil, regex = false }
end

local function resolve_expect(raw)
  local match_part = nil
  if raw_has(raw, "match") then
    match_part = raw_get(raw, "match")
  end
  if raw_has(raw, "err") then
    return { kind = "error", error = parse_err(raw_get(raw, "err")), match = match_part }
  end
  -- KEY PRESENCE: "out" present even if its value is JSON_NULL => VALUE.
  if raw_has(raw, "out") then
    return { kind = "value", value = raw_get(raw, "out"), match = match_part }
  end
  if raw_has(raw, "match") then
    return { kind = "match", match = raw_get(raw, "match") }
  end
  return { kind = "absent" }
end

-- Coerce a raw value to a string id/client (only strings expected in corpus).
local function as_string(v)
  if v == nil or v == MISSING or v == JSON_NULL then
    return nil
  end
  if type(v) == "string" then
    return v
  end
  if type(v) == "number" or type(v) == "boolean" then
    return tostring(v)
  end
  return nil
end

local function normalize(fn, group, index, raw)
  local id_v = raw_has(raw, "id") and raw_get(raw, "id") or nil
  local client_v = raw_has(raw, "client") and raw_get(raw, "client") or nil
  local doc_v = raw_has(raw, "doc") and raw_get(raw, "doc") or nil
  return {
    ["function"] = fn,
    group = group,
    index = index,
    id = as_string(id_v),
    doc = (doc_v == true),
    client = as_string(client_v),
    input = resolve_input(raw),
    expect = resolve_expect(raw),
    raw = raw,
  }
end

----------------------------------------------------------
-- TestProvider
----------------------------------------------------------

local Provider = {}
Provider.__index = Provider

-- Resolve the root that holds the function nodes (spec.struct or spec).
local function root_node(spec)
  if is_obj(spec) then
    local s = obj_get(spec, "struct")
    if is_obj(s) then
      return s
    end
  end
  return spec
end

function Provider:raw()
  return self.spec
end

function Provider:_fn_node(fn)
  local node = MISSING
  if is_obj(self.spec) then
    local s = obj_get(self.spec, "struct")
    if is_obj(s) and obj_has(s, fn) then
      node = obj_get(s, fn)
    elseif obj_has(self.spec, fn) then
      node = obj_get(self.spec, fn)
    end
  end
  if node == MISSING or node == nil or node == JSON_NULL then
    error("Unknown function: " .. tostring(fn), 0)
  end
  return node
end

function Provider:functions()
  local root = root_node(self.spec)
  local out = {}
  if is_obj(root) then
    for _, k in ipairs(root.keys) do
      local v = root.map[k]
      if is_group_bag(v) or has_groups(v) then
        out[#out + 1] = k
      end
    end
  end
  return out
end

function Provider:groups(fn)
  local node = self:_fn_node(fn)
  local out = {}
  if is_obj(node) then
    for _, k in ipairs(node.keys) do
      if k ~= "name" and is_group_bag(node.map[k]) then
        out[#out + 1] = k
      end
    end
  end
  return out
end

function Provider:entries(fn, group)
  local node = self:_fn_node(fn)
  local groups
  if group ~= nil then
    groups = { group }
  else
    groups = self:groups(fn)
  end
  local out = {}
  for _, g in ipairs(groups) do
    local bag = obj_get(node, g)
    if is_group_bag(bag) then
      local set = obj_get(bag, "set")
      local items = set.items
      for i = 1, #items do
        -- index is 0-based to match the canonical ports (TS/Python use 0-based
        -- position within the group's set[]).
        out[#out + 1] = normalize(fn, g, i - 1, items[i])
      end
    end
  end
  return out
end

-- M.load(path): parse test.json and return a provider.
function M.load(testfile)
  local file = testfile or default_test_file()
  local spec = json_decode(read_file(file))
  return setmetatable({ spec = spec }, Provider)
end

-- Backwards-friendly alias matching the documented API surface.
M.TestProvider = { load = M.load }

----------------------------------------------------------
-- Pure comparison helpers
----------------------------------------------------------

-- stringify(x) = x if a Lua string, else compact JSON serialization.
local function stringify(x)
  if type(x) == "string" then
    return x
  end
  return json_encode(x)
end
M.stringify = stringify

-- Normalize NULLMARK / JSON_NULL / nil / MISSING to a single canonical null
-- token so lenient equality collapses absent ≡ null ≡ __NULL__.
local NULL_CANON = setmetatable({}, { __tostring = function() return "<null>" end })

local function norm_null(x)
  if x == NULLMARK or x == nil or x == JSON_NULL or x == MISSING then
    return NULL_CANON
  end
  if is_arr(x) then
    local r = new_arr()
    for i = 1, #x.items do
      r.items[i] = norm_null(x.items[i])
    end
    return r
  end
  if is_obj(x) then
    local r = new_obj()
    for _, k in ipairs(x.keys) do
      obj_set(r, k, norm_null(x.map[k]))
    end
    return r
  end
  return x
end

-- Strict variant: only __NULL__ collapses to null; JSON null stays distinct
-- from absent. JSON_NULL -> NULL_CANON too (a present JSON null IS null), but
-- MISSING (absent) stays MISSING.
local function norm_mark(x)
  if x == NULLMARK then
    return NULL_CANON
  end
  if x == JSON_NULL then
    return NULL_CANON
  end
  if is_arr(x) then
    local r = new_arr()
    for i = 1, #x.items do
      r.items[i] = norm_mark(x.items[i])
    end
    return r
  end
  if is_obj(x) then
    local r = new_obj()
    for _, k in ipairs(x.keys) do
      obj_set(r, k, norm_mark(x.map[k]))
    end
    return r
  end
  return x
end

-- Deep structural equality over our representation. Arrays compare by length +
-- element; objects compare by same key set + per-key value. Scalars use ==.
local function deep_eq(a, b)
  if a == b then
    return true
  end
  if is_arr(a) and is_arr(b) then
    if #a.items ~= #b.items then
      return false
    end
    for i = 1, #a.items do
      if not deep_eq(a.items[i], b.items[i]) then
        return false
      end
    end
    return true
  end
  if is_obj(a) and is_obj(b) then
    if #a.keys ~= #b.keys then
      return false
    end
    for _, k in ipairs(a.keys) do
      if not obj_has(b, k) then
        return false
      end
      if not deep_eq(a.map[k], b.map[k]) then
        return false
      end
    end
    return true
  end
  -- One is a container and the other isn't (or scalars unequal).
  return false
end

-- matchval(check, base): scalar primitive per PROVIDER.md §5.
-- check == base; else if check is a string: "/re/" => regex test against
-- stringify(base); otherwise stringify(base) lowercased CONTAINS check
-- lowercased (plain substring). Lua has no native regex, so "/re/" uses Lua
-- patterns. PROTOTYPE: regex simplified — Lua patterns are not JS RegExp.
local function regex_test(pattern, subject)
  -- PROTOTYPE: regex simplified. Lua's string.find with a Lua pattern is the
  -- closest dependency-free approximation to JS new RegExp(re).test(subject).
  -- It will diverge for JS-specific constructs (alternation |, \d, anchors,
  -- quantifiers like {n}, etc.). The corpus exercises only one `match`/regex
  -- error case, kept simple here.
  local ok, found = pcall(function()
    return subject:find(pattern) ~= nil
  end)
  if not ok then
    return false
  end
  return found
end

local function matchval(check, base)
  if check == base then
    return true
  end
  if type(check) == "string" then
    local basestr = stringify(base)
    local inner = check:match("^/(.+)/$")
    if inner then
      return regex_test(inner, basestr)
    end
    -- contains-case: case-insensitive plain substring.
    return basestr:lower():find(check:lower(), 1, true) ~= nil
  end
  if type(check) == "function" then
    return true
  end
  return false
end
M.matchval = matchval

-- equal: lenient deep-equal (absent ≡ null ≡ __NULL__).
local function equal(expected, actual)
  return deep_eq(norm_null(expected), norm_null(actual))
end
M.equal = equal

-- equal_strict: undefined/absent ≠ null; only __NULL__ and JSON null collapse.
local function equal_strict(expected, actual)
  return deep_eq(norm_mark(expected), norm_mark(actual))
end
M.equal_strict = equal_strict

-- error_matches(check, message): any => true; regex => pattern test; else
-- case-insensitive plain substring.
local function error_matches(check, message)
  if check.any then
    return true
  end
  if check.text == nil then
    return false
  end
  if check.regex then
    return regex_test(check.text, message)
  end
  return message:lower():find(check.text:lower(), 1, true) ~= nil
end
M.error_matches = error_matches

-- getpath over our representation. Returns MISSING when the path runs off the
-- end (mirrors TS undefined / Python _MISSING).
local function getpath(store, path)
  local cur = store
  for _, key in ipairs(path) do
    if cur == nil or cur == MISSING or cur == JSON_NULL then
      return MISSING
    end
    if is_arr(cur) then
      local idx = tonumber(key)
      if idx == nil then
        return MISSING
      end
      -- path indices are 0-based strings; our items are 1-based.
      cur = cur.items[idx + 1]
      if cur == nil then
        return MISSING
      end
    elseif is_obj(cur) then
      if obj_has(cur, key) then
        cur = cur.map[key]
      else
        return MISSING
      end
    else
      return MISSING
    end
  end
  return cur
end
M.getpath = getpath

-- Walk every leaf (non-node) of `node`, invoking fn(value, path) with a
-- string-path list. Mirrors the TS walkLeaves.
local function walk_leaves(node, path, fn)
  if is_arr(node) then
    for i = 1, #node.items do
      local p = {}
      for _, x in ipairs(path) do
        p[#p + 1] = x
      end
      p[#p + 1] = tostring(i - 1) -- 0-based index string
      walk_leaves(node.items[i], p, fn)
    end
  elseif is_obj(node) then
    for _, k in ipairs(node.keys) do
      local p = {}
      for _, x in ipairs(path) do
        p[#p + 1] = x
      end
      p[#p + 1] = k
      walk_leaves(node.map[k], p, fn)
    end
  else
    fn(node, path)
  end
end

-- struct_match(check, base) -> { ok, path?, expected?, actual? }
-- Partial structural match: every leaf of `check` must match `base` at its
-- path. First failure returns its path + the two values.
local function struct_match(check, base)
  local result = { ok = true }
  walk_leaves(check, {}, function(val, path)
    if not result.ok then
      return
    end
    local baseval = getpath(base, path)

    -- Direct equality (covers scalars, and JSON_NULL == JSON_NULL).
    if baseval ~= MISSING and baseval == val then
      return
    end

    -- Explicit undefined expected: require absent.
    if val == UNDEFMARK and baseval == MISSING then
      return
    end

    -- Explicit exists expected: require present (and not null).
    if val == EXISTSMARK and baseval ~= MISSING and baseval ~= JSON_NULL then
      return
    end

    local compare_base = baseval
    if compare_base == MISSING then
      compare_base = nil
    end
    if not matchval(val, compare_base) then
      result = {
        ok = false,
        path = path,
        expected = val,
        actual = compare_base,
      }
    end
  end)
  return result
end
M.struct_match = struct_match

return M
