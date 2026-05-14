-- Luacheck configuration for the Lua port.
-- https://luacheck.readthedocs.io/
std = "lua54+luajit"
max_line_length = 120

-- The busted test framework injects these globals into spec files.
files["test/"] = {
  std = "+busted",
}

exclude_files = {
  ".luarocks/",
  "lua_modules/",
}

-- Mirroring the canonical TypeScript source produces some unused arguments
-- (kept for signature parity); don't flag those.
unused_args = false

-- The library proper has a few API-surface stubs (`re_compile` / `re_find` /
-- `re_find_all` / `re_replace` / `re_escape` in src/struct.lua) and an
-- internal scratch variable (`start` in src/regex.lua's match loop). Allow
-- them since deleting would drop public surface or in-place state.
files["src/struct.lua"] = {
  ignore = { "211", "311" }, -- unused local / value assigned to local never used
}
files["src/regex.lua"] = {
  ignore = { "211", "231", "631" }, -- unused local / set-but-never-accessed / long line
}
