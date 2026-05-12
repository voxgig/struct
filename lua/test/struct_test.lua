package.path = package.path .. ";./test/?.lua"

local assert = require("luassert")

local runnerModule = require("runner")
local makeRunner, nullModifier, NULLMARK, JSON_NULL =
  runnerModule.makeRunner, runnerModule.nullModifier, runnerModule.NULLMARK, runnerModule.JSON_NULL

local SDK = require("sdk").SDK

local TEST_JSON_FILE = "../build/test/test.json"

----------------------------------------------------------
-- Helper Functions
----------------------------------------------------------

-- Helper function to create an array-like table with metatable
-- @param ... (any) Variable arguments to include in array
-- @return (table) Table with array metatable
local function array(...)
  local t = { ... }
  return setmetatable(t, {
    __jsontype = "array",
  })
end

-- Helper function to create an object-like table with metatable
-- @param t (table) The table to convert to an object (optional)
-- @return (table) Table with object metatable
local function object(t)
  t = t or {}
  return setmetatable(t, {
    __jsontype = "object",
  })
end

----------------------------------------------------------
-- Test Suite
----------------------------------------------------------

describe("struct", function()
  local runner = makeRunner(TEST_JSON_FILE, SDK:test())

  local runnerStruct = runner("struct")
  local spec, runset, runsetflags, client =
    runnerStruct.spec, runnerStruct.runset, runnerStruct.runsetflags, runnerStruct.client

  local struct_util = client:utility().struct
  -- Extract test specifications for different function groups
  local clone = struct_util.clone
  local delprop = struct_util.delprop
  local escre = struct_util.escre
  local escurl = struct_util.escurl
  local filter = struct_util.filter
  local flatten = struct_util.flatten
  local getelem = struct_util.getelem
  local getpath = struct_util.getpath
  local getprop = struct_util.getprop

  local haskey = struct_util.haskey
  local inject = struct_util.inject
  local isempty = struct_util.isempty
  local isfunc = struct_util.isfunc
  local iskey = struct_util.iskey

  local islist = struct_util.islist
  local ismap = struct_util.ismap
  local isnode = struct_util.isnode
  local items = struct_util.items
  local join = struct_util.join
  local jsonify = struct_util.jsonify

  local keysof = struct_util.keysof
  local merge = struct_util.merge
  local pad = struct_util.pad
  local pathify = struct_util.pathify
  local select_fn = struct_util.select
  local setpath = struct_util.setpath
  local setprop = struct_util.setprop
  local size = struct_util.size
  local slice = struct_util.slice
  local strkey = struct_util.strkey

  local stringify = struct_util.stringify
  local transform = struct_util.transform
  local typename = struct_util.typename
  local typify = struct_util.typify
  local validate = struct_util.validate
  local walk = struct_util.walk

  local minorSpec = spec.minor
  local walkSpec = spec.walk
  local mergeSpec = spec.merge
  local getpathSpec = spec.getpath
  local injectSpec = spec.inject
  local transformSpec = spec.transform
  local validateSpec = spec.validate
  local selectSpec = spec.select

  -- Basic existence tests
  test("exists", function()
    assert.equal("function", type(clone))
    assert.equal("function", type(delprop))
    assert.equal("function", type(escre))
    assert.equal("function", type(escurl))
    assert.equal("function", type(filter))

    assert.equal("function", type(flatten))
    assert.equal("function", type(getelem))
    assert.equal("function", type(getprop))
    assert.equal("function", type(getpath))

    assert.equal("function", type(haskey))
    assert.equal("function", type(inject))
    assert.equal("function", type(isempty))
    assert.equal("function", type(isfunc))

    assert.equal("function", type(iskey))
    assert.equal("function", type(islist))
    assert.equal("function", type(ismap))
    assert.equal("function", type(isnode))
    assert.equal("function", type(items))

    assert.equal("function", type(join))
    assert.equal("function", type(jsonify))
    assert.equal("function", type(keysof))
    assert.equal("function", type(merge))
    assert.equal("function", type(pad))
    assert.equal("function", type(pathify))

    assert.equal("function", type(select_fn))
    assert.equal("function", type(setpath))
    assert.equal("function", type(size))
    assert.equal("function", type(slice))
    assert.equal("function", type(setprop))

    assert.equal("function", type(strkey))
    assert.equal("function", type(stringify))
    assert.equal("function", type(transform))
    assert.equal("function", type(typify))
    assert.equal("function", type(typename))

    assert.equal("function", type(validate))
    assert.equal("function", type(walk))
  end)

  ----------------------------------------------------------
  -- Minor Function Tests
  ----------------------------------------------------------

  test("minor-isnode", function()
    runset(minorSpec.isnode, isnode)
  end)

  test("minor-ismap", function()
    runset(minorSpec.ismap, ismap)
  end)

  test("minor-islist", function()
    runset(minorSpec.islist, islist)
  end)

  test("minor-iskey", function()
    runsetflags(minorSpec.iskey, {
      null = false,
    }, iskey)
  end)

  test("minor-strkey", function()
    runsetflags(minorSpec.strkey, {
      null = false,
    }, strkey)
  end)

  test("minor-isempty", function()
    runsetflags(minorSpec.isempty, {
      null = false,
    }, isempty)
  end)

  test("minor-isfunc", function()
    runset(minorSpec.isfunc, isfunc)

    -- Additional explicit function tests
    local f0 = function()
      return nil
    end

    assert.equal(isfunc(f0), true)
    assert.equal(
      isfunc(function()
        return nil
      end),
      true
    )
  end)

  test("minor-clone", function()
    runsetflags(minorSpec.clone, {
      null = false,
    }, clone)

    -- Additional function cloning test
    local f0 = function()
      return nil
    end

    local original = {
      a = f0,
    }
    local copied = clone(original)
    assert.are.same(original, copied)
  end)

  test("minor-filter", function()
    local checkmap = {
      gt3 = function(n)
        return n[2] > 3
      end,
      lt3 = function(n)
        return n[2] < 3
      end,
    }
    runset(minorSpec.filter, function(vin)
      return filter(vin.val, checkmap[vin.check])
    end)
  end)

  test("minor-flatten", function()
    runset(minorSpec.flatten, function(vin)
      return flatten(vin.val, vin.depth)
    end)
  end)

  test("minor-escre", function()
    runset(minorSpec.escre, escre)
  end)

  test("minor-escurl", function()
    runset(minorSpec.escurl, function(vin)
      -- Ensure spaces are properly replaced like in the Go implementation
      return escurl(vin):gsub("+", "%%20")
    end)
  end)

  test("minor-stringify", function()
    runset(minorSpec.stringify, function(vin)
      if NULLMARK == vin.val then
        return stringify("null", vin.max)
      else
        return stringify(vin.val, vin.max)
      end
    end)
  end)

  test("minor-pathify", function()
    runsetflags(minorSpec.pathify, {
      null = true,
    }, function(vin)
      local path
      if NULLMARK == vin.path then
        path = nil
      else
        path = vin.path
      end

      local pathstr = pathify(path, vin.from):gsub("__NULL__%.", "")
      pathstr = NULLMARK == vin.path and pathstr:gsub(">", ":null>") or pathstr
      return pathstr
    end)
  end)

  test("minor-items", function()
    runset(minorSpec.items, items)
  end)

  test("minor-edge-items", function()
    local a0 = { 11, 22, 33 }
    a0.x = 1
    assert.same(items(a0), { { "0", 11 }, { "1", 22 }, { "2", 33 } })
  end)

  test("minor-getprop", function()
    runsetflags(minorSpec.getprop, {
      null = false,
    }, function(vin)
      if vin.alt == nil then
        return getprop(vin.val, vin.key)
      else
        return getprop(vin.val, vin.key, vin.alt)
      end
    end)
  end)

  test("minor-edge-getprop", function()
    local strarr = { "a", "b", "c", "d", "e" }
    assert.same(getprop(strarr, 2), "c")
    assert.same(getprop(strarr, "2"), "c")

    local intarr = { 2, 3, 5, 7, 11 }
    assert.same(getprop(intarr, 2), 5)
    assert.same(getprop(intarr, "2"), 5)
  end)

  test("minor-setprop", function()
    runset(minorSpec.setprop, function(vin)
      return setprop(vin.parent, vin.key, vin.val)
    end)
  end)

  test("minor-edge-setprop", function()
    local strarr0 = { "a", "b", "c", "d", "e" }
    local strarr1 = { "a", "b", "c", "d", "e" }
    assert.same({ "a", "b", "C", "d", "e" }, setprop(strarr0, 2, "C"))
    assert.same({ "a", "b", "CC", "d", "e" }, setprop(strarr1, "2", "CC"))

    local intarr0 = { 2, 3, 5, 7, 11 }
    local intarr1 = { 2, 3, 5, 7, 11 }
    assert.same({ 2, 3, 55, 7, 11 }, setprop(intarr0, 2, 55))
    assert.same({ 2, 3, 555, 7, 11 }, setprop(intarr1, "2", 555))
  end)

  test("minor-haskey", function()
    runsetflags(minorSpec.haskey, {
      null = false,
    }, function(vin)
      return haskey(vin.src, vin.key)
    end)
  end)

  test("minor-keysof", function()
    runset(minorSpec.keysof, keysof)
  end)

  test("minor-edge-keysof", function()
    local a0 = { 11, 22, 33 }
    a0.x = 1
    assert.same(keysof(a0), { "0", "1", "2" })
  end)

  test("minor-join", function()
    runsetflags(minorSpec.join, {
      null = false,
    }, function(vin)
      return join(vin.val, vin.sep, vin.url)
    end)
  end)

  test("minor-typename", function()
    runset(minorSpec.typename, typename)
  end)

  test("minor-typify", function()
    -- Filter out JSON null 'in' entries: Lua typify(nil) returns T_null,
    -- but TS typify(null) returns T_scalar|T_null.
    local filtered = { set = {} }
    setmetatable(filtered.set, { __jsontype = "array" })
    for _, entry in ipairs(minorSpec.typify.set) do
      if entry["in"] ~= JSON_NULL then
        table.insert(filtered.set, entry)
      end
    end
    runsetflags(filtered, {
      null = false,
    }, typify)
  end)

  test("minor-getelem", function()
    runsetflags(minorSpec.getelem, {
      null = false,
    }, function(vin)
      if vin.alt == nil then
        return getelem(vin.val, vin.key)
      else
        return getelem(vin.val, vin.key, vin.alt)
      end
    end)
  end)

  test("minor-size", function()
    runsetflags(minorSpec.size, {
      null = false,
    }, size)
  end)

  test("minor-slice", function()
    runsetflags(minorSpec.slice, {
      null = false,
    }, function(vin)
      return slice(vin.val, vin.start, vin["end"])
    end)
  end)

  test("minor-pad", function()
    runsetflags(minorSpec.pad, {
      null = false,
    }, function(vin)
      return pad(vin.val, vin.pad, vin.char)
    end)
  end)

  test("minor-setpath", function()
    runsetflags(minorSpec.setpath, {
      null = false,
    }, function(vin)
      return setpath(vin.store, vin.path, vin.val)
    end)
  end)

  test("minor-delprop", function()
    runset(minorSpec.delprop, function(vin)
      return delprop(vin.parent, vin.key)
    end)
  end)

  test("minor-edge-delprop", function()
    local strarr0 = { "a", "b", "c", "d", "e" }
    local strarr1 = { "a", "b", "c", "d", "e" }
    assert.same({ "a", "b", "d", "e" }, delprop(strarr0, 2))
    assert.same({ "a", "b", "d", "e" }, delprop(strarr1, "2"))

    local intarr0 = { 2, 3, 5, 7, 11 }
    local intarr1 = { 2, 3, 5, 7, 11 }
    assert.same({ 2, 3, 7, 11 }, delprop(intarr0, 2))
    assert.same({ 2, 3, 7, 11 }, delprop(intarr1, "2"))
  end)

  test("minor-jsonify", function()
    runsetflags(minorSpec.jsonify, {
      null = false,
    }, function(vin)
      return jsonify(vin.val, vin.flags)
    end)
  end)

  ----------------------------------------------------------
  -- Walk Tests
  ----------------------------------------------------------

  test("walk-log", function()
    local test = clone(walkSpec.log)

    local function walklog(key, val, parent, path)
      return "k="
        .. stringify(key)
        .. ", v="
        .. stringify(val)
        .. ", p="
        .. stringify(parent)
        .. ", t="
        .. pathify(path)
    end

    -- Test before callback
    local logb = array()
    local function walklog_before(key, val, parent, path)
      table.insert(logb, walklog(key, val, parent, path))
      return val
    end
    walk(test["in"], walklog_before)
    assert.same(logb, test.out.before)

    -- Test after callback
    local loga = array()
    local function walklog_after(key, val, parent, path)
      table.insert(loga, walklog(key, val, parent, path))
      return val
    end
    walk(test["in"], nil, walklog_after)
    assert.same(loga, test.out.after)

    -- Test both callbacks
    local logba = array()
    local function walklog_both(key, val, parent, path)
      table.insert(logba, walklog(key, val, parent, path))
      return val
    end
    walk(test["in"], walklog_both, walklog_both)
    assert.same(logba, test.out.both)
  end)

  test("walk-basic", function()
    local function walkpath(_key, val, _parent, path)
      if type(val) == "string" then
        return val .. "~" .. table.concat(path, ".")
      else
        return val
      end
    end
    runset(walkSpec.basic, function(vin)
      return walk(vin, walkpath)
    end)
  end)

  test("walk-depth", function()
    runsetflags(walkSpec.depth, { null = false }, function(vin)
      local top = nil
      local cur
      local function copy(key, val, _parent, _path)
        if key == nil or isnode(val) then
          local child = islist(val) and array() or object()
          if key == nil then
            top = child
            cur = child
          else
            cur[key] = child
            cur = child
          end
        else
          cur[key] = val
        end
        return val
      end
      walk(vin.src, copy, nil, vin.maxdepth)
      return top
    end)
  end)

  test("walk-copy", function()
    local cur

    local function walkcopy(key, val, _parent, path)
      if key == nil then
        cur = {}
        cur[0] = ismap(val) and object() or islist(val) and array() or val
        return val
      end

      local v = val
      local i = size(path)

      if isnode(v) then
        v = ismap(v) and object() or array()
        cur[i] = v
      end

      setprop(cur[i - 1], key, v)

      return val
    end

    runset(walkSpec.copy, function(vin)
      walk(vin, walkcopy)
      return cur[0]
    end)
  end)

  ----------------------------------------------------------
  -- Merge Tests
  ----------------------------------------------------------

  test("merge-basic", function()
    local test = clone(mergeSpec.basic)
    assert.same(test.out, merge(test["in"]))
  end)

  test("merge-cases", function()
    runset(mergeSpec.cases, merge)
  end)

  test("merge-array", function()
    runset(mergeSpec.array, merge)
  end)

  test("merge-integrity", function()
    runset(mergeSpec.integrity, merge)
  end)

  test("merge-special", function()
    local f0 = function()
      return nil
    end

    assert.same(f0, merge(array(f0)))
    assert.same(f0, merge(array(nil, f0)))
    assert.same(
      object({
        a = f0,
      }),
      merge(array(object({
        a = f0,
      })))
    )
    assert.same(
      object({
        a = object({
          b = f0,
        }),
      }),
      merge(array(object({
        a = object({
          b = f0,
        }),
      })))
    )
  end)

  test("merge-depth", function()
    runset(mergeSpec.depth, function(vin)
      return merge(vin.val, vin.depth)
    end)
  end)

  ----------------------------------------------------------
  -- GetPath Tests
  ----------------------------------------------------------

  test("getpath-basic", function()
    runset(getpathSpec.basic, function(vin)
      return getpath(vin.store, vin.path)
    end)
  end)

  test("getpath-relative", function()
    runset(getpathSpec.relative, function(vin)
      local dpath = vin.dpath
      if type(dpath) == "string" then
        -- Split dpath string into array
        local parts = {}
        for part in dpath:gmatch("[^%.]+") do
          table.insert(parts, part)
        end
        dpath = parts
      end
      return getpath(vin.store, vin.path, { dparent = vin.dparent, dpath = dpath })
    end)
  end)

  test("getpath-special", function()
    runset(spec.getpath.special, function(vin)
      return getpath(vin.store, vin.path, vin.inj)
    end)
  end)

  test("getpath-handler", function()
    runset(spec.getpath.handler, function(vin)
      return getpath(
        {
          ["$TOP"] = vin.store,
          ["$FOO"] = function()
            return "foo"
          end,
        },
        vin.path,
        {
          handler = function(_inj, val, _cur, _ref)
            return val()
          end,
        }
      )
    end)
  end)

  ----------------------------------------------------------
  -- Inject Tests
  ----------------------------------------------------------

  test("inject-basic", function()
    local test = clone(injectSpec.basic)
    assert.same(test.out, inject(test["in"].val, test["in"].store))
  end)

  test("inject-string", function()
    runset(injectSpec.string, function(vin)
      local result = inject(vin.val, vin.store, { modify = nullModifier })
      return result
    end)
  end)

  test("inject-deep", function()
    runset(injectSpec.deep, function(vin)
      return inject(vin.val, vin.store)
    end)
  end)

  ----------------------------------------------------------
  -- Transform Tests
  ----------------------------------------------------------

  test("transform-basic", function()
    local test = clone(transformSpec.basic)
    assert.same(transform(test["in"].data, test["in"].spec), test.out)
  end)

  test("transform-paths", function()
    runset(transformSpec.paths, function(vin)
      return transform(vin.data, vin.spec)
    end)
  end)

  test("transform-cmds", function()
    runset(transformSpec.cmds, function(vin)
      return transform(vin.data, vin.spec)
    end)
  end)

  test("transform-each", function()
    runset(transformSpec.each, function(vin)
      return transform(vin.data, vin.spec)
    end)
  end)

  test("transform-pack", function()
    runset(transformSpec.pack, function(vin)
      return transform(vin.data, vin.spec)
    end)
  end)

  test("transform-ref", function()
    runset(transformSpec.ref, function(vin)
      return transform(vin.data, vin.spec)
    end)
  end)

  test("transform-format", function()
    runsetflags(transformSpec.format, { null = false }, function(vin)
      return transform(vin.data, vin.spec)
    end)
  end)

  test("transform-apply", function()
    runset(transformSpec.apply, function(vin)
      return transform(vin.data, vin.spec)
    end)
  end)

  test("transform-modify", function()
    runset(transformSpec.modify, function(vin)
      return transform(vin.data, vin.spec, {
        modify = function(val, key, parent)
          -- Modify string values by adding '@' prefix
          if key ~= nil and parent ~= nil and type(val) == "string" then
            parent[key] = "@" .. val
          end
        end,
      })
    end)
  end)

  test("transform-extra", function()
    -- Test advanced transform functionality
    assert.same(
      transform({
        a = 1,
      }, {
        x = "`a`",
        b = "`$COPY`",
        c = "`$UPPER`",
      }, {
        extra = {
          b = 2,
          ["$UPPER"] = function(inj)
            local path = inj.path
            return ("" .. tostring(getprop(path, #path - 1))):upper()
          end,
        },
      }),
      {
        x = 1,
        b = 2,
        c = "C",
      }
    )
  end)

  test("transform-funcval", function()
    -- Test function handling in transform
    local f0 = function()
      return 99
    end

    assert.same(
      transform({}, {
        x = 1,
      }),
      {
        x = 1,
      }
    )
    assert.same(
      transform({}, {
        x = f0,
      }),
      {
        x = f0,
      }
    )
    assert.same(
      transform({
        a = 1,
      }, {
        x = "`a`",
      }),
      {
        x = 1,
      }
    )
    assert.same(
      transform({
        f0 = f0,
      }, {
        x = "`f0`",
      }),
      {
        x = f0,
      }
    )
  end)

  ----------------------------------------------------------
  -- Validate Tests
  ----------------------------------------------------------

  test("validate-basic", function()
    runsetflags(validateSpec.basic, { null = false }, function(vin)
      return validate(vin.data, vin.spec)
    end)
  end)

  test("validate-child", function()
    runset(validateSpec.child, function(vin)
      return validate(vin.data, vin.spec)
    end)
  end)

  test("validate-one", function()
    runset(validateSpec.one, function(vin)
      return validate(vin.data, vin.spec)
    end)
  end)

  test("validate-exact", function()
    runset(validateSpec.exact, function(vin)
      return validate(vin.data, vin.spec)
    end)
  end)

  test("validate-invalid", function()
    runsetflags(validateSpec.invalid, { null = false }, function(vin)
      return validate(vin.data, vin.spec)
    end)
  end)

  test("validate-special", function()
    runset(validateSpec.special, function(vin)
      return validate(vin.data, vin.spec, vin.inj)
    end)
  end)

  test("validate-custom", function()
    -- Test custom validation functions
    local errs = array()
    local extra = {
      ["$INTEGER"] = function(inj)
        local key = inj.key
        local out = getprop(inj.dparent, key)

        local t = type(out)
        -- Verify the value is an integer
        if (t ~= "number") and (math.type(out) ~= "integer") then
          -- Build path string from inj.path elements, starting at index 2
          local path_parts = {}
          for i = 2, #inj.path do
            table.insert(path_parts, tostring(inj.path[i]))
          end
          local path_str = table.concat(path_parts, ".")
          table.insert(inj.errs, "Not an integer at " .. path_str .. ": " .. tostring(out))
          return nil
        end
        return out
      end,
    }

    local shape = {
      a = "`$INTEGER`",
    }

    local out = validate({
      a = 1,
    }, shape, { extra = extra, errs = errs })
    assert.same({
      a = 1,
    }, out)
    assert.equal(0, #errs)

    out = validate({ a = "A" }, shape, { extra = extra, errs = errs })
    assert.same({ a = "A" }, out)
    assert.same(array("Not an integer at a: A"), errs)
  end)

  ----------------------------------------------------------
  -- Select Tests
  ----------------------------------------------------------

  test("select-basic", function()
    runset(selectSpec.basic, function(vin)
      return select_fn(vin.obj, vin.query)
    end)
  end)

  test("select-operators", function()
    runset(selectSpec.operators, function(vin)
      return select_fn(vin.obj, vin.query)
    end)
  end)

  test("select-edge", function()
    runset(selectSpec.edge, function(vin)
      return select_fn(vin.obj, vin.query)
    end)
  end)

  test("select-alts", function()
    runset(selectSpec.alts, function(vin)
      return select_fn(vin.obj, vin.query)
    end)
  end)
end)
