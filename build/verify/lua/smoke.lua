-- Universal struct smoke: getpath({ db = { host = "localhost" } }, "db.host").
-- Runs against the freshly-installed published rock (see verify-lua); the
-- public module is the namespaced voxgig.struct.
local struct = require("voxgig.struct")

local got = struct.getpath({ db = { host = "localhost" } }, "db.host")

if got == "localhost" then
  print("OK lua: getpath(db.host) = localhost")
  os.exit(0)
end

print("FAIL lua: getpath(db.host) = " .. tostring(got) .. " (want localhost)")
os.exit(1)
