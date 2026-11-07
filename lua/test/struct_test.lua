package.path = package.path .. ";./test/?.lua"

local assert = require("luassert")

local runnerModule = require("omni")
local makeRunner, nullModifier = runnerModule.makeRunner, runnerModule.nullModifier
-- Spec entries arrive in the runner's own value model, where a JSON null is a
-- sentinel rather than a Lua nil. The skip guards below have to compare
-- against it.
local JSON_NULL = runnerModule.JSON_NULL

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
-- Entries this port cannot express
----------------------------------------------------------

-- Lua has ONE `nil`. The corpus distinguishes JSON null from absent, and a
-- Lua table cannot hold a nil at all, so some entries have no representation
-- here. `NOVAL` (src/struct.lua) covers the ARGUMENT side -- `typify()`
-- against `typify(null)` -- but not the RESULT side: a function that returns
-- nothing and one that returns JSON null both return `nil`, and the runner
-- has to read it one way.
--
-- It reads it as ABSENT, which is the cheaper side by a wide margin: measured
-- entry by entry, reading it as null costs 43 entries (every missing-key and
-- out-of-range case in getprop and getelem, where canonical answers
-- undefined), reading it as absent costs the cases that return a genuine
-- null, dropped below. The alternative -- returning NOVAL from getprop - would
-- fix both sides but change what every existing caller of getprop sees, and
-- struct/go would have to move with it.
--
-- Rather than mark whole groups pending and lose the other ~150 entries in
-- them, the individual entries are dropped and named here.
--
-- Each drop is GUARDED. Corpus indexes are positional, so if the corpus gains
-- or reorders an entry the guard fires and says so, instead of quietly
-- skipping a different entry and reporting green.
local function dropentries(group, drops)
  assert.is_true(nil ~= group, "corpus group missing")
  local set = group.set
  assert.is_true(nil ~= set, "corpus group has no set")

  -- Descending, so each removal leaves the earlier indexes alone.
  for i = #drops, 1, -1 do
    local drop = drops[i]
    local entry = set[drop.at + 1]
    assert.is_true(
      nil ~= entry and drop.is(entry),
      "corpus moved under a skip: " .. drop.why .. " is no longer at index " .. drop.at
    )
    table.remove(set, drop.at + 1)
  end

  return group
end

-- Helpers the guards use. `dropentries` mutates the spec node in place, so a
-- group must be dropped from once; a second pass would find the entry gone
-- and the guard would say so.
local function isnull(val)
  return JSON_NULL == val
end
-- A numeric path part indexes a list from 0, as corpus paths do.
local function entryin(entry, path)
  local at = entry["in"]
  for part in path:gmatch("[^%.]+") do
    if type(at) ~= "table" then
      return nil
    end
    local index = math.tointeger(tonumber(part))
    if nil ~= index and nil ~= rawget(at, index + 1) then
      at = at[index + 1]
    else
      at = at[part]
    end
  end
  return at
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
  local condense = struct_util.condense
  local condenseview = struct_util.condenseview
  local expand = struct_util.expand
  local iscondensed = struct_util.iscondensed
  local delprop = struct_util.delprop
  local escre = struct_util.escre
  local escurl = struct_util.escurl
  local filter = struct_util.filter
  local flatten = struct_util.flatten
  local getelem = struct_util.getelem
  local getpath = struct_util.getpath
  local getprop = struct_util.getprop
  local re_test = struct_util.re_test
  local re_find = struct_util.re_find
  local re_find_all = struct_util.re_find_all
  local re_replace = struct_util.re_replace
  local re_escape = struct_util.re_escape

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

  local condenseSpec = spec.condense
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
  -- Condense Tests
  ----------------------------------------------------------

  test("condense-condense", function()
    runsetflags(
      dropentries(condenseSpec.condense, {
        -- The null list element arrives as the string "null", which condenses
        -- as a string.
        { at = 10, why = "condense of a null list element", is = function(entry)
          return "condense/list-mixed" == entry.id and isnull(entryin(entry, "3"))
        end },
      }),
      { null = false },
      condense
    )
  end)

  test("condense-expand", function()
    runsetflags(
      dropentries(condenseSpec.expand, {
        -- `expand` gives back the null root as nil, read as absent.
        { at = 3, why = "expand of a null root", is = function(entry)
          return "expand/scalar-null" == entry.id and isnull(entry.out)
        end },
      }),
      { null = false },
      expand
    )
  end)

  test("condense-iscondensed", function()
    runsetflags(condenseSpec.iscondensed, { null = false }, iscondensed)
  end)

  -- What the corpus shape cannot express: identity, sharing, laziness and the
  -- immutability contract.

  test("condense-deterministic", function()
    local function flat(val)
      return jsonify(condense(val), { indent = 0 })
    end
    local function get()
      return object({ m = "GET" })
    end
    local src = object({ b = get(), a = get(), l = array(1, "x", true) })
    assert.equal(flat(src), flat(src))
    -- Keys are stored by symbol id, so the order a table was built in does not
    -- change the bytes.
    local reordered = object()
    reordered.l = array(1, "x", true)
    reordered.a = get()
    reordered.b = get()
    assert.equal(flat(src), flat(reordered))
  end)

  test("condense-shares-identical-subtrees", function()
    local function op(m)
      return object({ m = m, p = "/1" })
    end
    local one = condense(object({ x = op("GET") }))
    local two = condense(object({ x = op("GET"), y = op("GET") }))
    assert.equal(#one.node, #two.node)
    local three = condense(object({ x = op("GET"), y = op("PUT"), z = op("POST") }))
    assert.is_true(#three.node > #two.node)
  end)

  test("condense-round-trips-by-value", function()
    local src = object({ a = object({ b = array(1, "x", true, "__NULL__", object()) }), c = "z" })
    assert.same(src, expand(condense(src)))
    -- NULLMARK is an ordinary string to condense, as a key and as a value.
    local marked = object({ __NULL__ = "__NULL__" })
    assert.same(marked, expand(condense(marked)))
    assert.equal("__NULL__", getpath(condense(marked), "__NULL__"))
  end)

  test("condense-getpath-is-transparent", function()
    local op = object({ list = object({ method = "GET" }) })
    local src = object({ entity = object({ p = object({ op = op }) }) })
    local c = condense(src)
    assert.same(
      getpath(src, array("entity", "p", "op", "list")),
      getpath(c, array("entity", "p", "op", "list"))
    )
    assert.equal("GET", getpath(c, array("entity", "p", "op", "list", "method")))
    assert.is_nil(getpath(c, array("entity", "nope")))
  end)

  test("condense-view-reads-without-materialising", function()
    local entity = object({ a = object({ v = 1 }), b = object({ v = 2 }) })
    local v = condenseview(condense(object({ entity = entity, other = 9 })))
    assert.same(array("a", "b"), v.keys("entity"))
    assert.equal(2, v.at("entity").at("b").get("v"))
    assert.is_true(v.has("entity.a"))
    assert.is_false(v.has("entity.zz"))
    assert.equal(2, v.size())
    assert.is_false(v.at("entity.zz").exists())
    assert.equal(0, v.at("entity.zz").size())
    assert.same(array("0", "1"), condenseview(condense(array(7, 8))).keys())
  end)

  test("condense-value-copies-and-ref-shares", function()
    local src = object({ a = object({ m = "GET" }), b = object({ m = "GET" }) })
    local v = condenseview(condense(src))
    -- a and b share one node, which get() must not make observable.
    local x = v.get("a")
    local y = v.get("b")
    assert.same(x, y)
    assert.is_false(x == y)
    x.m = "MUTATED"
    assert.equal("GET", v.get("b").m)
    -- ref() is the opt-in shared materialisation.
    assert.equal(v.at("a").ref(), v.at("a").ref())
  end)

  test("condense-preserves-proto-named-keys-and-values", function()
    local asvalue = object({ x = "__proto__" })
    assert.same(asvalue, expand(condense(asvalue)))
    local askey = object({ __proto__ = 1 })
    assert.equal('{"__proto__":1}', jsonify(expand(condense(askey)), { indent = 0 }))
  end)

  test("condense-getpath-matches-plain-on-null-and-options", function()
    -- A Lua table holds no null, so this structure is spelt condensed: {a: null}.
    local c = object({ ["$condense"] = 1, sym = array("a"), root = 1 })
    c.node = array(array(6), array(0, 0, 0))
    assert.is_true(iscondensed(c))
    assert.is_nil(getpath(c, "a"))
    -- A null list element materialises as NULLMARK, since a list cannot hold nil.
    local l = object({ ["$condense"] = 1, sym = array(), root = 1 })
    l.node = array(array(6), array(1, 0))
    assert.same(array("__NULL__"), expand(l))
    -- injdef.base must not be ignored by the condensed read.
    local store = object({ base = object({ x = 1 }) })
    local base = { base = "base" }
    assert.equal(getpath(store, "x", base), getpath(condense(store), "x", base))
    assert.equal(1, getpath(condense(store), "x", base))
  end)

  test("condense-list-keys-are-canonical-integers", function()
    local plain = object({ l = array(10, 20) })
    local c = condense(plain)
    for _, k in ipairs({ "01", "1e0", " 1", "+1", "1.0", "-0", "1\n" }) do
      assert.equal(getpath(plain, array("l", k)), getpath(c, array("l", k)), "list key " .. k)
    end
    assert.equal(20, getpath(c, array("l", "1")))
    assert.equal(20, getpath(c, array("l", 1)))
  end)

  test("condense-symbols-sort-by-code-point", function()
    local sym = condense(object({ a = "\u{10000}", b = "\u{FFFF}" })).sym
    local at = {}
    for i, s in ipairs(sym) do
      at[s] = i
    end
    assert.is_true(at["\u{FFFF}"] < at["\u{10000}"])
  end)

  test("condense-astral-keys-resolve", function()
    -- Code-unit order would put the astral key first; the stored pairs must not.
    local c = condense(object({ ["\u{FF21}"] = 1, ["\u{1F600}"] = 2 }))
    assert.equal(2, getpath(c, array("\u{1F600}")))
    assert.equal(1, getpath(c, array("\u{FF21}")))
    assert.equal(2, condenseview(c).get("\u{1F600}"))
  end)

  test("condense-numbers-intern-by-value", function()
    local node = condense(array(1, 1.0, 2)).node
    assert.equal("[[3,1],[3,2],[1,0,0,1]]", jsonify(node, { indent = 0 }))
  end)

  test("condense-invalid-key-mutations-stay-no-ops", function()
    -- An invalid key is ignored, so a call that cannot write does not raise.
    local c = condense(object({ a = 1 }))
    assert.equal(c, delprop(c, nil))
    assert.equal(c, setprop(c, nil, 1))
    -- A call that could write still raises.
    local ok, err = pcall(delprop, c, "sym")
    assert.is_false(ok)
    assert.truthy(string.find(err, "immutable", 1, true))
  end)

  test("condense-is-immutable", function()
    local function raises(fn, ...)
      local ok, err = pcall(fn, ...)
      return not ok and nil ~= string.find(tostring(err), "immutable", 1, true)
    end
    local c = condense(object({ a = 1 }))
    assert.is_true(raises(setpath, c, "a", 2))
    assert.is_true(raises(setprop, c, "a", 2))
    assert.is_true(raises(delprop, c, "sym"))
    -- The expanded copy is ordinary and mutable.
    local e = expand(c)
    setpath(e, "a", 2)
    assert.equal(2, e.a)
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
    runsetflags(
      dropentries(minorSpec.clone, {
        -- `clone(null)`, which must give back null. The port returns nil,
        -- read as absent. (`clone()` with NO argument - index 13, the
        -- residual struct/go still carries - passes.)
        { at = 6, why = "clone(null)", is = function(entry)
          return isnull(entry["in"]) and isnull(entry.out)
        end },
      }),
      {
        null = false,
      },
      clone
    )

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
    runset(minorSpec.escurl, escurl)
  end)

  test("minor-stringify", function()
    -- null = true so a JSON null `val` arrives as NULLMARK; stringify(NULLMARK)
    -- is "null" (canonical TS stringify(null) === "null"), while an absent val
    -- (nil) is "".
    runsetflags(minorSpec.stringify, {
      null = true,
    }, function(vin)
      return stringify(vin.val, vin.max)
    end)
  end)

  test("minor-pathify", function()
    -- null = true so a JSON null path arrives as NULLMARK. pathify treats
    -- NULLMARK as a scalar (not a key), so null path elements are dropped via
    -- iskey and a top-level null renders as <unknown-path:null>.
    runsetflags(minorSpec.pathify, {
      null = true,
    }, function(vin)
      return pathify(vin.path, vin.from)
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
    runsetflags(
      dropentries(minorSpec.getprop, {
        -- A null `alt`, which getprop must hand straight back. The port
        -- receives it as nil and returns nil, read as absent. The other 52
        -- entries - every missing-key case among them - pass.
        { at = 51, why = "getprop with a null alt", is = function(entry)
          return "x" == entryin(entry, "key") and isnull(entryin(entry, "alt"))
        end },
        { at = 52, why = "getprop with a null key and a null alt", is = function(entry)
          return isnull(entryin(entry, "key")) and isnull(entryin(entry, "alt"))
        end },
      }),
      {
        null = false,
      },
      function(vin)
        if vin.alt == nil then
          return getprop(vin.val, vin.key)
        else
          return getprop(vin.val, vin.key, vin.alt)
        end
      end
    )
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
    -- null = false so a JSON null `in` arrives as nil; typify(nil) is
    -- T_scalar|T_null (4194432), matching canonical TS typify(null). (The
    -- typify(undefined)==T_noval corpus entry has no `in` and is skipped, as
    -- Lua cannot distinguish absent from null at the value level.)
    runsetflags(minorSpec.typify, {
      null = false,
    }, typify)
  end)

  test("minor-getelem", function()
    runsetflags(
      minorSpec.getelem,
      {
        null = false,
      },
      function(vin)
        if vin.alt == nil then
          return getelem(vin.val, vin.key)
        else
          return getelem(vin.val, vin.key, vin.alt)
        end
      end
    )
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
    runsetflags(
      dropentries(validateSpec.basic, {
        -- `$NULL` against null data: validate returns the null, the port
        -- returns nil, read as absent.
        { at = 14, why = "$NULL validating null data", is = function(entry)
          return "`$NULL`" == entryin(entry, "spec") and isnull(entryin(entry, "data"))
        end },
        { at = 53, why = "$NULL validating null data, again", is = function(entry)
          return "`$NULL`" == entryin(entry, "spec") and isnull(entryin(entry, "data"))
        end },
        -- `{"a": null}` against `$ANY`, expecting `{"a": null}` back. Under
        -- `null = false` the runner passes a real null, and a Lua table
        -- cannot hold a nil - so the key is simply not there. Keeping a
        -- sentinel in the slot instead was measurably worse: the port's own
        -- `haskey({a: null}, "a") == false` and
        -- `getprop({a: null}, "a", "D") == "D"` are corpus entries too, and
        -- they need that key ABSENT.
        { at = 61, why = "a null value in a map under null = false", is = function(entry)
          return "`$ANY`" == entryin(entry, "spec.a") and isnull(entryin(entry, "data.a"))
        end },
      }),
      { null = false },
      function(vin)
        return validate(vin.data, vin.spec)
      end
    )
  end)

  test("validate-child", function()
    runset(validateSpec.child, function(vin)
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

  -- Under `null = false` a null map member arrives absent and cannot come back,
  -- a null list element arrives as the string "null" and comes back as one, and
  -- null data comes back as nil, read as absent. A null in a spec changes the
  -- same way. The entries that turn on such a null are dropped.

  test("validate-directive", function()
    runsetflags(
      dropentries(validateSpec.directive, {
        { at = 0, why = "a null map member validated by $NOF", is = function(entry)
          return isnull(entryin(entry, "data.a")) and "`$NULL`" == entryin(entry, "spec.a.3")
        end },
        { at = 1, why = "null data validated by $NOF", is = function(entry)
          return isnull(entryin(entry, "data")) and "`$NOF`" == entryin(entry, "spec.0")
        end },
        { at = 2, why = "a null list element validated by $NOF", is = function(entry)
          return isnull(entryin(entry, "data.0")) and "`$NOF`" == entryin(entry, "spec.1.0")
        end },
        { at = 3, why = "a null map member under $CHILD", is = function(entry)
          return isnull(entryin(entry, "data.a")) and "x" == entryin(entry, "data.b")
        end },
        { at = 5, why = "a null map member against $EXACT null", is = function(entry)
          return isnull(entryin(entry, "data.a")) and isnull(entryin(entry, "spec.a.1"))
        end },
        { at = 6, why = "null data against $EXACT null", is = function(entry)
          return isnull(entryin(entry, "data")) and isnull(entryin(entry, "spec.2"))
        end },
        { at = 7, why = "a null list element against $EXACT null", is = function(entry)
          return isnull(entryin(entry, "data.0")) and "`$EXACT`" == entryin(entry, "spec.1.0")
        end },
        { at = 10, why = "a null map member validated by $NIL", is = function(entry)
          return isnull(entryin(entry, "data.a")) and "`$NIL`" == entryin(entry, "spec.a")
        end },
        { at = 11, why = "null data validated by $NIL", is = function(entry)
          return isnull(entryin(entry, "data")) and "`$NIL`" == entryin(entry, "spec")
        end },
        { at = 12, why = "a null map member validated by $NOF with $NIL", is = function(entry)
          return isnull(entryin(entry, "data.a")) and "`$NIL`" == entryin(entry, "spec.a.3")
        end },
        { at = 24, why = "$EXACT of a map with a null member", is = function(entry)
          return "null" == entryin(entry, "data.x") and isnull(entryin(entry, "spec.1.x"))
        end },
        { at = 27, why = "$EXACT of a map with a null member, again", is = function(entry)
          return 1 == entryin(entry, "data.x") and isnull(entryin(entry, "spec.1.y"))
        end },
      }),
      { null = false },
      function(vin)
        return validate(vin.data, vin.spec)
      end
    )
  end)

  test("validate-nof", function()
    runsetflags(
      dropentries(validateSpec.nof, {
        -- The member arrives absent, which no spec of $NULL admits, so the
        -- count of none holds where canonical counts the null.
        { at = 24, why = "a null map member counted by $NOF", is = function(entry)
          return isnull(entryin(entry, "data.a")) and 0 == entryin(entry, "spec.a.1")
        end },
        { at = 25, why = "a null map member validated by $NOF", is = function(entry)
          return isnull(entryin(entry, "data.a")) and "`$NULL`" == entryin(entry, "spec.a.3")
        end },
        { at = 26, why = "a null list element validated by $NOF", is = function(entry)
          return isnull(entryin(entry, "data.0")) and "`$NOF`" == entryin(entry, "spec.1.0")
        end },
        { at = 31, why = "a null map member a default would replace", is = function(entry)
          return isnull(entryin(entry, "data.r")) and "`$NOF`" == entryin(entry, "spec.0")
        end },
      }),
      { null = false },
      function(vin)
        return validate(vin.data, vin.spec)
      end
    )
  end)

  test("validate-all", function()
    runsetflags(
      dropentries(validateSpec.all, {
        { at = 10, why = "a null map member validated by $ALL", is = function(entry)
          return isnull(entryin(entry, "data.a")) and "`$ALL`" == entryin(entry, "spec.a.0")
        end },
        { at = 13, why = "a null map member a default would replace", is = function(entry)
          return isnull(entryin(entry, "data.r")) and "`$ALL`" == entryin(entry, "spec.0")
        end },
      }),
      { null = false },
      function(vin)
        return validate(vin.data, vin.spec)
      end
    )
  end)

  test("validate-unknown", function()
    runsetflags(validateSpec.unknown, { null = false }, function(vin)
      return validate(vin.data, vin.spec)
    end)
  end)

  test("validate-unknown-edge", function()
    -- Only the unknown name is reported, and the data comes back as it is.
    local errs = array()
    local data = object({ a = "x" })
    local out =
      validate(data, object({ a = array("`$ONE`", "`$STRING`", "`$NIL`") }), { errs = errs })
    assert.same(array("Unknown validator $ONE at field a.0."), errs)
    assert.same(data, out)

    -- A checker supplied in extra is defined, in any case.
    local function even(inj)
      local n = getprop(inj.dparent, inj.key)
      if 0 ~= n % 2 then
        table.insert(inj.errs, "Odd at " .. pathify(inj.path, 1) .. ": " .. n)
      end
      return n
    end

    errs = array()
    out = validate(
      object({ n = 2 }),
      object({ n = "`$EVEN`" }),
      { extra = { ["$EVEN"] = even }, errs = errs }
    )
    assert.same({ n = 2 }, out)
    out = validate(
      object({ n = 3 }),
      object({ n = "`$even`" }),
      { extra = { ["$even"] = even }, errs = errs }
    )
    assert.same({ n = 3 }, out)
    assert.same(array("Odd at n: 3"), errs)

    -- A null in extra takes a checker away. A Lua table cannot hold nil, so
    -- the port spells that null false, as validate does for transform's commands.
    errs = array()
    validate("x", "`$STRING`", { extra = { ["$STRING"] = false }, errs = errs })
    assert.same(array("Unknown validator $STRING at field <root>."), errs)
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

  ----------------------------------------------------------
  -- Sentinel (JSON null) Tests
  ----------------------------------------------------------
  -- These pin the JSON-null unification rules. Lua has no value distinct from
  -- nil for JSON null, so the flag choice depends on where the null sits:
  --   * In a MAP value / scalar position, null = false renders it as nil
  --     (an absent map key), which getprop/haskey/isempty/isnode already
  --     unify the canonical way. This mirrors canonical TS (sentinels run
  --     with null:false there too).
  --   * In a LIST element, nil would create an array hole, so the harness
  --     carries the null as the NULLMARK ("__NULL__") sentinel under
  --     null = true; getelem treats NULLMARK as no-value.
  --   * stringify must distinguish JSON null ("null") from absent (""), which
  --     it can only see via the NULLMARK sentinel, so it runs with null = true.

  local sentinelsSpec = spec.sentinels
  local regexSpec = spec.regex

  -- regex (parity floor: Go stdlib regexp — see design/REGEX_API.md)
  test("regex-test", function()
    runset(regexSpec.test, function(vin)
      return re_test(vin.pattern, vin.input)
    end)
  end)

  test("regex-find", function()
    runset(regexSpec.find, function(vin)
      return re_find(vin.pattern, vin.input)
    end)
  end)

  test("regex-find_all", function()
    runset(regexSpec.find_all, function(vin)
      return re_find_all(vin.pattern, vin.input)
    end)
  end)

  test("regex-replace", function()
    runset(regexSpec.replace, function(vin)
      return re_replace(vin.pattern, vin.input, vin.replacement)
    end)
  end)

  test("regex-escape", function()
    runset(regexSpec.escape, function(vin)
      return re_escape(vin.val)
    end)
  end)

  test("sentinels-getprop_unify", function()
    runsetflags(sentinelsSpec.getprop_unify, { null = false }, function(vin)
      return getprop(vin.val, vin.key, vin.alt)
    end)
  end)

  test("sentinels-getelem_absent", function()
    runsetflags(sentinelsSpec.getelem_absent, { null = true }, function(vin)
      return getelem(vin.val, vin.key, vin.alt)
    end)
  end)

  test("sentinels-haskey_unify", function()
    runsetflags(sentinelsSpec.haskey_unify, { null = false }, function(vin)
      return haskey(vin.val, vin.key)
    end)
  end)

  test("sentinels-isempty_unify", function()
    runsetflags(sentinelsSpec.isempty_unify, { null = false }, isempty)
  end)

  test("sentinels-isnode_unify", function()
    runsetflags(sentinelsSpec.isnode_unify, { null = false }, isnode)
  end)

  test("sentinels-stringify_null", function()
    runsetflags(sentinelsSpec.stringify_null, { null = true }, stringify)
  end)
end)
