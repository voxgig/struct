--- The shared test runner comes from voxgig/omni, consumed as a local
--- checkout - omni is deliberately not published to LuaRocks (yet). The
--- checkout is resolved the same way voxgig/sekreto's ports resolve it:
--- $OMNI_HOME first, then sibling paths, taking the first directory that
--- carries spec/fib.json. Set OMNI_HOME if yours lives elsewhere.
---
--- Only the tests depend on omni. The library never does, and
--- struct.rockspec gains no dependency - this is a plain `require` off
--- package.path.
---
--- This is the Lua counterpart of python/tests/omni.py, ruby/omni.rb,
--- php/tests/omni.php and javascript/test/omni.js. The API it exposes is
--- omni's struct compat shim, so the test files call `makeRunner` and
--- `nullModifier` exactly as they did when that code lived in
--- `test/runner.lua`.
---
--- The swap also drops two rocks the in-situ runner needed and omni does
--- not: `dkjson` (omni carries its own JSON) and `lfs` (omni opens the spec
--- path directly rather than joining it to `lfs.currentdir()`).

local function exists(path)
  local fh = io.open(path, 'r')
  if nil == fh then
    return false
  end
  fh:close()
  return true
end

local function omnihome()
  local candidates = {}

  local env = os.getenv('OMNI_HOME')
  if nil ~= env and '' ~= env then
    candidates[#candidates + 1] = env
  end

  candidates[#candidates + 1] = '../../omni'
  candidates[#candidates + 1] = '../../../omni'
  candidates[#candidates + 1] = '/workspace/omni'
  candidates[#candidates + 1] = '/home/user/omni'

  for _, candidate in ipairs(candidates) do
    if exists(candidate .. '/spec/fib.json') then
      return candidate
    end
  end

  error('struct: voxgig/omni checkout not found - set OMNI_HOME')
end

local home = omnihome()

-- ONE path, and APPENDED. `lua/?.lua` is all omni needs: its `src/` modules
-- resolve their own siblings relative to themselves, so `src.util` finds
-- `src.json` without `src/` being on the path.
--
-- That matters more than it looks. omni ships `src/regex.lua` and so does
-- struct/lua; with omni's `src/` prepended, struct.lua's own
-- `require('regex')` fallback silently loaded OMNI's regex, and every
-- `re_test`/`re_find`/`re_replace`/`re_escape` in the port went nil.
-- Appending, and adding only the one directory, keeps the port's own
-- modules winning.

package.path = package.path .. ';' .. home .. '/lua/?.lua'

return require('compat.struct')
