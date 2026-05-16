-- Discovery test: pathological regex inputs run against the port's re_* API.
-- Goal is to surface failures across ports, not to assert behaviour.
-- Panel is the same in every port (see REGEX.md).
--
-- RUN: lua test/regex_pathological.lua

package.path = "../src/?.lua;./src/?.lua;" .. (package.path or "")
local re = require("regex")

local function json_str(s)
  return '"' .. tostring(s):gsub('"', '\\"') .. '"'
end

local function json_table(t)
  local parts = {}
  for _, v in ipairs(t) do
    if type(v) == "table" then
      parts[#parts + 1] = json_table(v)
    elseif type(v) == "string" then
      parts[#parts + 1] = json_str(v)
    else
      parts[#parts + 1] = tostring(v)
    end
  end
  return "[" .. table.concat(parts, ",") .. "]"
end

local function render(r)
  local t = type(r)
  if t == "nil" then return "null"
  elseif t == "boolean" then return tostring(r)
  elseif t == "string" then return json_str(r)
  elseif t == "table" then return json_table(r)
  else return tostring(r) end
end

local function record(label, fn)
  local t0 = os.clock()
  local ok, r = pcall(fn)
  local ms = (os.clock() - t0) * 1000.0
  local outcome
  if ok then
    outcome = "OK | " .. render(r)
  else
    outcome = "ERR | " .. tostring(r)
  end
  io.write(string.format("[regex-discovery] %s | %.2fms | %s\n", label, ms, outcome))
end

local a22 = string.rep("a", 22)
local nest40 = string.rep("(", 40) .. "a" .. string.rep(")", 40)

record("P1_redos_nested_plus",      function() return re.re_test("^(a+)+$", a22 .. "!") end)
record("P2_redos_alt_overlap",      function() return re.re_test("^(a|aa)+$", a22 .. "!") end)
record("P3_empty_repeat_replace",   function() return re.re_replace("a*", "abc", "X") end)
record("P4_unicode_replace_dot",    function() return re.re_replace("\\.", "café.au.lait", "/") end)
record("P5_unicode_find_codepoint", function() return re.re_find("é", "café au lait") end)
record("P6_deep_nesting_compile",   function() return re.re_test(nest40, "a") end)
record("P7_big_bounded_quantifier", function() return re.re_test("^a{0,10000}b$", string.rep("a", 10) .. "b") end)
record("P8_invalid_pattern",        function() return re.re_compile("[abc") end)
record("P9_backref_re2_forbidden",  function() return re.re_test("^(a+)\\1$", "aaaa") end)
record("P10_find_all_zero_width",   function() return re.re_find_all("a*", "bbb") end)
