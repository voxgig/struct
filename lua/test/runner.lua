local json = require("dkjson")
local lfs = require("lfs")
local luassert = require("luassert")

local NULLMARK = "__NULL__" -- Value is JSON null
local UNDEFMARK = "__UNDEF__" -- Value is not present (thus undefined)
local EXISTSMARK = "__EXISTS__" -- Value exists (not undefined)

-- Unique sentinel for JSON null (distinguishes from the literal string "null")
local JSON_NULL = setmetatable({}, {
  __tostring = function()
    return "null"
  end,
})

----------------------------------------------------------
-- Utility Functions
----------------------------------------------------------

-- Read file contents synchronously
-- @param path (string) The path to the file
-- @return (string) The contents of the file
local function readFileSync(path)
  local file = io.open(path, "r")
  if not file then
    error("Cannot open file: " .. path)
  end
  local content = file:read("*a")
  file:close()
  return content
end

-- Join path segments with forward slashes
-- @param ... (string) Path segments to join
-- @return (string) Joined path
local function join(...)
  return table.concat({ ... }, "/")
end

-- Assert failure with message
-- @param msg (string) Failure message
local function fail(msg)
  luassert(false, msg)
end

-- Deep equality check between two values
-- @param actual (any) The actual value
-- @param expected (any) The expected value
local function deepEqual(actual, expected)
  luassert.same(expected, actual)
end

----------------------------------------------------------
-- foward declarations
----------------------------------------------------------
local resolveSpec
local resolveClients
local resolveSubject
local resolveFlags
local resolveEntry
local resolveTestPack
local resolveArgs
local fixJSON
local checkResult
local handleError
local match
local matchval

-- Creates a runner function that can be used to run tests
-- @param testfile (string) The path to the test file
-- @param client (table) The client instance to use
-- @return (function) A runner function
local function makeRunner(testfile, client)
  -- Main test runner function
  -- @param name (string) The name of the test
  -- @param store (table) Store with configuration values
  -- @return (table) The runner pack with test functions
  local function runner(name, store)
    store = store or {}

    local utility = client:utility()
    local structUtils = utility.struct

    local spec = resolveSpec(name, testfile)
    local clients = resolveClients(client, spec, store, structUtils)
    local subject = resolveSubject(name, utility)

    -- Run test set with flags
    -- @param testspec (table) The test specification
    -- @param flags (table) Processing flags
    -- @param testsubject (function) Optional test subject override
    local function runsetflags(testspec, flags, testsubject)
      subject = testsubject or subject
      flags = resolveFlags(flags)

      -- Lua has no undefined value; skip entries where 'in' or 'out' is absent.
      -- Must check before fixJSON since fixJSON may convert JSON_NULL to nil.
      local rawset = testspec.set
      local filteredset = {}
      setmetatable(filteredset, getmetatable(rawset) or { __jsontype = "array" })
      for _, entry in ipairs(rawset) do
        if entry["in"] ~= nil or entry.args ~= nil or entry.ctx ~= nil then
          table.insert(filteredset, entry)
        end
      end
      testspec = { set = filteredset }

      local testspecmap = fixJSON(testspec, flags)

      local testset = testspecmap.set
      for _, entry in ipairs(testset) do
        local success, err = pcall(function()
          entry = resolveEntry(entry, flags)

          local testpack = resolveTestPack(name, entry, subject, client, clients)
          local args = resolveArgs(entry, testpack, utility, structUtils)

          local res = testpack.subject(table.unpack(args))
          res = fixJSON(res, flags)
          entry.res = res

          checkResult(entry, args, res, structUtils)
        end)

        if not success then
          handleError(entry, err, structUtils)
        end
      end
    end

    -- Run test set with default flags
    -- @param testspec (table) The test specification
    -- @param testsubject (function) Optional test subject override
    local function runset(testspec, testsubject)
      return runsetflags(testspec, {}, testsubject)
    end

    local runpack = {
      spec = spec,
      runset = runset,
      runsetflags = runsetflags,
      subject = subject,
      client = client,
    }

    return runpack
  end

  return runner
end

-- Resolve the test specification from a file
-- @param name (string) The name of the test specification
-- @param testfile (string) The path to the test file
-- @return (table) The resolved test specification
resolveSpec = function(name, testfile)
  local alltests = json.decode(readFileSync(join(lfs.currentdir(), testfile)), 1, JSON_NULL)
  local spec = (alltests.primary and alltests.primary[name]) or alltests[name] or alltests
  return spec
end

-- Resolve client instances based on specification
-- @param spec (table) The test specification
-- @param store (table) Store with configuration values
-- @param structUtils (table) Structure utility functions
-- @param baseClient (table) The base client instance
-- @return (table) Table of resolved client instances
resolveClients = function(client, spec, store, structUtils)
  local clients = {}

  if spec.DEF and spec.DEF.client then
    for cn in pairs(spec.DEF.client) do
      local cdef = spec.DEF.client[cn]
      local copts = cdef.test.options or {}
      if structUtils.ismap(store) and structUtils.inject then
        structUtils.inject(copts, store)
      end
      -- Use the tester method on the base client to create new test clients
      clients[cn] = client:tester(copts)
    end
  end
  return clients
end

-- Resolve the test subject function
-- @param name (string) The name of the subject to resolve
-- @param container (table) The container object (Utility)
-- @return (function) The resolved subject function
resolveSubject = function(name, container)
  local subject = container[name] or container.struct[name]
  return subject
end

-- Resolve test flags with defaults
-- @param flags (table) Input flags
-- @return (table) Resolved flags with defaults applied
resolveFlags = function(flags)
  if flags == nil then
    flags = {}
  end
  if flags.null == nil then
    flags.null = true
  else
    flags.null = not not flags.null -- Convert to boolean
  end
  return flags
end

-- Prepare a test entry with the given flags
-- @param entry (table) The test entry
-- @param flags (table) Processing flags
-- @return (table) The processed entry
resolveEntry = function(entry, flags)
  entry.out = (entry.out == nil and flags.null) and NULLMARK or entry.out
  return entry
end

-- Check the result of a test against expectations
-- @param entry (table) The test entry
-- @param args (table) The test arguments
-- @param res (any) The test result
-- @param structUtils (table) Structure utility functions
checkResult = function(entry, args, res, structUtils)
  local matched = false

  -- If expected error but none thrown, fail
  if entry.err then
    fail("Expected error did not occur: " .. structUtils.stringify(entry.err))
    return
  end

  -- If there's a match pattern, verify it first
  if entry.match then
    local result = {
      ["in"] = entry["in"],
      args = args,
      out = entry.res,
      ctx = entry.ctx,
    }
    match(entry.match, result, structUtils)
    matched = true
  end

  local out = entry.out

  -- If direct equality, we're done
  if out == res then
    return
  end

  -- If we matched and out is null or nil, we're done
  if matched and (out == NULLMARK or out == nil) then
    return
  end

  -- Otherwise, verify deep equality.
  -- Round-trip through JSON to normalize (matches TS behavior).
  if res ~= nil then
    local json_str = json.encode(res)
    local decoded = json.decode(json_str, 1, JSON_NULL)
    deepEqual(decoded, out)
  else
    deepEqual(res, out)
  end
end

-- Handle errors during test execution
-- @param entry (table) The test entry
-- @param err (any) The error that occurred
-- @param structUtils (table) Structure utility functions
handleError = function(entry, err, structUtils)
  entry.thrown = err

  local entry_err = entry.err
  local err_message = (type(err) == "table" and err.message) or tostring(err)

  if entry_err ~= nil then
    if entry_err == true or matchval(entry_err, err_message, structUtils) then
      if entry.match then
        -- Process the error with fixJSON before matching
        local processed_err = fixJSON(err, { null = true })
        match(entry.match, {
          ["in"] = entry["in"],
          out = entry.res,
          ctx = entry.ctx,
          err = processed_err,
        }, structUtils)
      end
      return
    end

    fail("ERROR MATCH: [" .. structUtils.stringify(entry_err) .. "] <=> [" .. err_message .. "]")
  else
    -- fail((err.stack or err_message) .. "\n\nENTRY: " .. inspect(entry))
    fail((err.stack or err_message))
  end
end

-- Prepare test arguments
-- @param entry (table) The test entry
-- @param testpack (table) The test pack with client and utility
-- @return (table) Array of arguments for the test
resolveArgs = function(entry, testpack, utility, structUtils)
  local args

  if entry.ctx then
    args = { entry.ctx }
  elseif entry.args then
    args = entry.args
  else
    args = { structUtils.clone(entry["in"]) }
  end

  if entry.ctx or entry.args then
    local first = args[1]
    if structUtils.ismap(first) then
      first = structUtils.clone(first)
      first = utility.contextify(first)
      args[1] = first
      entry.ctx = first

      first.client = testpack.client
      first.utility = testpack.utility
    end
  end

  return args
end

-- Resolve the test pack with client and subject
-- @param name (string) The name of the test
-- @param entry (table) The test entry
-- @param subject (function) The test subject function
-- @param client (table) The default client
-- @param clients (table) Table of available clients
-- @return (table) The resolved test pack
resolveTestPack = function(name, entry, subject, client, clients)
  local testpack = {
    name = name,
    client = client,
    subject = subject,
    utility = client:utility(),
  }

  if entry.client then
    testpack.client = clients[entry.client]
    testpack.utility = testpack.client:utility()
    testpack.subject = resolveSubject(name, testpack.utility)
  end

  return testpack
end

-- Match a check structure against a base structure
-- @param check (table) The check structure with patterns
-- @param base (table) The base structure to validate against
-- @param structUtils (table) Structure utility functions
match = function(check, base, structUtils)
  -- Clone the base to avoid modifying the original
  base = structUtils.clone(base)

  structUtils.walk(check, function(_key, val, _parent, path)
    if not structUtils.isnode(val) then
      local baseval = structUtils.getpath(base, path)

      -- Direct match check
      if baseval == val then
        return val
      end

      -- Explicit undefined expected
      if val == UNDEFMARK and baseval == nil then
        return val
      end

      -- Explicit defined expected
      if val == EXISTSMARK and baseval ~= nil then
        return val
      end

      if not matchval(val, baseval, structUtils) then
        fail(
          "MATCH: "
            .. table.concat(path, ".")
            .. ": ["
            .. structUtils.stringify(val)
            .. "] <=> ["
            .. structUtils.stringify(baseval)
            .. "]"
        )
      end
    end

    return val
  end)
end

-- Check if a test value matches a base value according to defined rules
-- @param check (any) The test pattern or value to check
-- @param base (any) The base value to check against
-- @param structUtils (table) Structure utility functions
-- @return (boolean) Whether the value matches
matchval = function(check, base, structUtils)
  local pass = check == base

  if not pass then
    if type(check) == "string" then
      local basestr = structUtils.stringify(base)

      -- Check if string starts and ends with '/' (RegExp in TypeScript)
      local rem = check:match("^/(.+)/$")
      if rem then
        -- Convert JS RegExp to Lua pattern when possible
        -- This is a simplification and might need adjustments for complex patterns
        local lua_pattern = rem
          :gsub("%%", "%%%%")
          :gsub("%.", "%%.")
          :gsub("%+", "%%+")
          :gsub("%-", "%%-")
          :gsub("%*", "%%*")
          :gsub("%?", "%%?")
          :gsub("%[", "%%[")
          :gsub("%]", "%%]")
          :gsub("%^", "%%^")
          :gsub("%$", "%%$")
          :gsub("%(", "%%(")
          :gsub("%)", "%%)")
        pass = basestr:match(lua_pattern) ~= nil
      else
        -- Convert both strings to lowercase and check if one contains the other
        pass = basestr:lower():find(structUtils.stringify(check):lower(), 1, true) ~= nil
      end
    elseif type(check) == "function" then
      pass = true
    end
  end

  return pass
end

-- Transform null values in JSON data according to flags.
-- dkjson decodes JSON null as the Lua string "null".
-- When flags.null is true, convert "null" to NULLMARK ("__NULL__").
-- When flags.null is false, convert "null" to nil (native Lua null).
-- @param val (any) The value to process
-- @param flags (table) Processing flags including null handling
-- @return (any) The processed value
fixJSON = function(val, flags)
  -- Handle JSON_NULL sentinel and Lua nil.
  if val == JSON_NULL or val == nil then
    if flags.null then
      return NULLMARK
    else
      return nil
    end
  end

  local function isarray(t)
    if type(t) ~= "table" then
      return false
    end
    if t == JSON_NULL then
      return false
    end
    local mt = getmetatable(t)
    if mt and mt.__jsontype == "array" then
      return true
    end
    local count = 0
    local max = 0
    for k in pairs(t) do
      if type(k) ~= "number" then
        return false
      end
      if k > max then
        max = k
      end
      count = count + 1
    end
    return count > 0 and max == count
  end

  -- In arrays, we need to preserve null as a value (not nil which creates holes).
  -- Use "null" string as a stand-in for JS null in arrays when flags.null=false.
  local function replacer(v, in_array)
    if v == JSON_NULL or v == nil then
      if flags.null then
        return NULLMARK
      elseif in_array then
        -- Preserve null in arrays as the string "null" to avoid nil holes.
        -- Matches JS behavior where String(null) === "null".
        return "null"
      else
        return nil
      end
    elseif type(v) == "table" and v ~= JSON_NULL then
      if isarray(v) then
        local result = {}
        local mt = getmetatable(v)
        if mt then
          setmetatable(result, mt)
        elseif #v > 0 then
          setmetatable(result, { __jsontype = "array" })
        end
        for i = 1, #v do
          local newval = replacer(v[i], true)
          if newval ~= nil then
            table.insert(result, newval)
          end
        end
        return result
      else
        -- For maps, process each value
        local result = {}
        for k, value in pairs(v) do
          local newval = replacer(value, false)
          if newval ~= nil then
            result[k] = newval
          end
        end
        local mt = getmetatable(v)
        if mt then
          setmetatable(result, mt)
        end
        return result
      end
    else
      return v
    end
  end

  return replacer(val)
end

-- Process null marker values
-- @param val (any) The value to check
-- @param key (any) The key in the parent
-- @param parent (table) The parent table
local function nullModifier(val, key, parent)
  if val == NULLMARK then
    parent[key] = nil -- In Lua, nil represents null
  elseif type(val) == "string" then
    parent[key] = val:gsub(NULLMARK, "null")
  end
end

-- Module exports
return {
  NULLMARK = NULLMARK,
  EXISTSMARK = EXISTSMARK,
  JSON_NULL = JSON_NULL,
  nullModifier = nullModifier,
  makeRunner = makeRunner,
}
