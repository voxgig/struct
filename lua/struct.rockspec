package = "voxgig-struct"
version = "0.0-1"
source = {
   url = "git://github.com/voxgig/struct.git",
   dir = "struct/lua"
}
description = {
   summary = "Utility functions for JSON-like data structures",
   detailed = [[
      Utility functions to manipulate in-memory JSON-like data structures.
      Includes functions for walking, merging, transforming, and validating data.
   ]],
   license = "MIT"
}
-- The library proper has zero third-party dependencies — src/struct.lua
-- uses only the Lua standard library. The entries below are needed
-- ONLY by the test harness (busted/luassert for assertions, dkjson +
-- luafilesystem for corpus loading and file ops).
dependencies = {
   "lua >= 5.3",
   "busted >= 2.0.0",
   "luassert >= 1.8.0",
   "dkjson >= 2.5",
   "luafilesystem >= 1.8.0"
}
build = {
   type = "builtin",
   modules = {
      struct = "src/struct.lua"
   },
   copy_directories = {"test"}
}
