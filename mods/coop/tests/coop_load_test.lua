-- Standalone: luajit mods/coop/tests/coop_load_test.lua
--
-- Loads the mod through the REAL headless loader against the fixture
-- dataset (no ROM import needed) and asserts it reaches "loaded" with no
-- errors.  That covers what coop_test.lua cannot: the manifest validates,
-- the entry chunk runs, the sub-modules resolve, and every hook name and
-- registry it touches actually exists.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local run = T.sdk.loadMod("mods/coop")

T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
T.eq(run.mod and run.mod.state, "loaded", "reached the loaded state")
T.eq(run.mod and run.mod.manifest.id, "coop", "manifest id")

-- the network permission is what lets a mod reach src.link legitimately;
-- without it the dev tripwire warns on every session we open
T.check(run.mod and run.mod.manifest.permissionSet.network,
  "declares the network permission")

-- the exports other mods are told to depend on
local exports = run.loader.exports.coop
T.check(type(exports.isConnected) == "function", "exports isConnected")
T.check(type(exports.peer) == "function", "exports peer")
T.eq(exports.isConnected(), false, "reports disconnected before any session")
T.eq(exports.peer(), nil, "reports no peer before any session")

run.release()
T.finish("coop_load")
