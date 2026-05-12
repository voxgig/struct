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
