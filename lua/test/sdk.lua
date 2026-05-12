local StructUtility = require("src.struct").StructUtility

-- Define the SDK "class"
local SDK = {}
SDK.__index = SDK

-- Constructor
function SDK:new(opts)
  local _opts
  local _utility

  local instance = {}
  setmetatable(instance, self)

  _opts = opts or {}
  _utility = {
    struct = StructUtility:new(),
    contextify = function(ctxmap)
      return ctxmap
    end,
    check = function(ctx)
      return {
        zed = "ZED"
          .. (_opts == nil and "" or (_opts.foo == nil and "" or _opts.foo))
          .. "_"
          .. (ctx.meta and ctx.meta.bar or "0"),
      }
    end,
  }

  function instance:tester(opts)
    return SDK:new(opts or _opts)
  end

  function instance:utility()
    return _utility
  end

  return instance
end

function SDK:test(opts)
  local sdkInstance = SDK:new(opts)
  return sdkInstance
end

return {
  SDK = SDK,
}
