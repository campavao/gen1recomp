-- Standalone: luajit mods/battle_royale/tests/br_test.lua
--
-- Covers the pieces that can be tested without a display or a ROM: the wire
-- vocabulary, the engage rule, the drop picker (against a synthetic map
-- fixture so no import is needed), and lib/relay.lua driven over the
-- in-memory hub in fake_relay.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path

local passed, failed = 0, 0
local function ok(cond, label)
  if cond then passed = passed + 1
  else failed = failed + 1; io.write("  FAIL: ", label, "\n") end
end
local function eq(got, want, label)
  if got ~= want then
    failed = failed + 1
    io.write(("  FAIL: %s (got %s, want %s)\n"):format(label, tostring(got), tostring(want)))
  else passed = passed + 1 end
end

local Wire = require("mods.battle_royale.lib.wire")
local Engage = require("mods.battle_royale.lib.engage")
local Relay = require("mods.battle_royale.lib.relay")
local Hub = require("mods.battle_royale.tests.fake_relay")

-- ------- wire

do
  local m = Wire.decode(Wire.place("PALLET_TOWN", 5, 6, "down", "alive", "SPRITE_RED"))
  ok(m ~= nil, "place round-trips")
  eq(m and m.status, "alive", "place carries status")
  eq(m and m.sprite, "SPRITE_RED", "place carries sprite")

  ok(Wire.decode({ t = "place", v = 999, map = "X", x = 1, y = 1, f = "up", st = "alive" }) == nil,
     "wrong protocol is refused")
  ok(Wire.decode({ t = "place", v = Wire.PROTOCOL, st = "bogus" }) == nil,
     "bad status is refused")

  local s = Wire.decode(Wire.step("up", 4, 5, "ROUTE_1"))
  eq(s and s.dir, "up", "step carries dir")
  eq(s and s.x, 4, "step carries x")

  local st = Wire.decode(Wire.start(12345, { { id = 1, map = "ROUTE_1", x = 2, y = 3 },
                                             { id = 2, map = "PALLET_TOWN", x = 4, y = 5 } }))
  ok(st ~= nil, "start round-trips")
  eq(st and #st.spawns, 2, "start carries both spawns")
  ok(Wire.decode({ t = "start", seed = 1, spawns = {} }) == nil, "empty start is refused")

  eq(Wire.decode(Wire.challenge(7)).nonce, 7, "challenge nonce")
  eq(Wire.decode(Wire.accept(7)).nonce, 7, "accept nonce")
  eq(Wire.decode(Wire.winner(3)).id, 3, "winner id")

  local lt = Wire.decode(Wire.loot({ { id = "POKE_BALL", n = 6 },
                                     { id = "POTION", n = 1 } }, 3000))
  ok(lt ~= nil, "loot round-trips")
  eq(lt and #lt.items, 2, "loot carries both stacks")
  eq(lt and lt.items[1].n, 6, "loot carries the count")
  eq(lt and lt.money, 3000, "loot carries money")
  ok(Wire.decode({ t = "loot", items = "x" }) == nil, "malformed loot refused")
  ok(Wire.decode({ t = "loot", items = { { id = "", n = 1 } } }) == nil,
     "empty item id refused")
  eq(Wire.decode({ t = "loot", items = {}, money = -5 }).money, 0,
     "negative money clamps to zero")
  eq(Wire.decode({ t = "loot", items = { { id = "X", n = 500 } } }).items[1].n, 99,
     "oversized stack clamps")
  eq(Wire.cleanName("  ab\1cdef ghi "), "abcdef", "name cleaned + capped to 7")
  eq(Wire.cleanName(nil), "PLAYER", "name falls back")
end

-- ------- engage

do
  -- me at (5,5) facing right; target on (6,5)
  local me = { id = 2, map = "R", x = 5, y = 5, facing = "right", moving = false, status = "alive" }
  local a = { id = 5, map = "R", x = 6, y = 5, facing = "left", moving = false, status = "alive" }
  eq(Engage.target(me, { a }), 5, "faces adjacent alive trainer -> target")

  a.status = "out"
  ok(Engage.target(me, { a }) == nil, "eliminated player is not a target")
  a.status = "alive"; a.moving = true
  ok(Engage.target(me, { a }) == nil, "moving player is not a target")
  a.moving = false; a.map = "OTHER"
  ok(Engage.target(me, { a }) == nil, "player on another map is not a target")
  a.map = "R"; me.facing = "left"
  ok(Engage.target(me, { a }) == nil, "not facing them -> no target")

  eq(Engage.isHost(2, 5), true, "lower id hosts")
  eq(Engage.isHost(5, 2), false, "higher id does not host")

  -- lowest id wins when two candidates are somehow on the same cell
  me.facing = "right"
  local b = { id = 3, map = "R", x = 6, y = 5, facing = "left", moving = false, status = "alive" }
  eq(Engage.target(me, { a, b }), 3, "ties break to the lower id")

  eq(Engage.answer({ status = "alive" }, 5, nil), "accept", "idle player accepts")
  eq(Engage.answer({ status = "battle" }, 5, nil), "busy", "in-battle player is busy")
  eq(Engage.answer({ status = "alive" }, 5, { to = 9 }), "busy",
     "player pending with someone else is busy")
  eq(Engage.answer({ status = "alive" }, 5, { to = 5 }), "accept",
     "a challenge from the one we are challenging is accepted")
end

-- ------- spawn (against the real imported data when it is present)
-- Spawn leans on src.world.Map's real tileset semantics, so a faithful
-- synthetic fixture would have to reproduce the whole tileset format.  We
-- test it against the generated Kanto data instead, and skip cleanly when
-- no ROM has been imported (CI, a fresh checkout) so the suite still passes.

do
  local okData, maps = pcall(dofile, "data/generated/maps.lua")
  local okTs, tilesets = pcall(dofile, "data/generated/tilesets.lua")
  local okMap = pcall(require, "src.world.Map")
  if not (okData and okTs and okMap and type(maps) == "table") then
    io.write("  (skipping spawn: no imported data / Map unavailable headless)\n")
  else
    local Spawn = require("mods.battle_royale.lib.spawn")
    local outdoor = Spawn.outdoorMaps(maps)
    ok(#outdoor > 0, "found outdoor Kanto maps (" .. #outdoor .. ")")

    local drops, err = Spawn.pick(maps, tilesets, 8, Spawn.rng(42))
    ok(drops ~= nil, "picks 8 drops (" .. tostring(err) .. ")")
    if drops then
      eq(#drops, 8, "one drop per player")
      local seen, unique, allOutdoor = {}, true, true
      for _, d in ipairs(drops) do
        local key = d.map .. ":" .. d.x .. ":" .. d.y
        if seen[key] then unique = false end
        seen[key] = true
        if not maps[d.map] then allOutdoor = false end
      end
      ok(unique, "no two players share a cell")
      ok(allOutdoor, "every drop is on a real map")
      -- determinism: same seed -> same first drop
      local again = Spawn.pick(maps, tilesets, 8, Spawn.rng(42))
      eq(again and again[1].map, drops[1].map, "same seed reproduces the drop map")
      eq(again and again[1].x, drops[1].x, "same seed reproduces the drop cell")
    end
  end
end

-- ------- relay round-trip over the in-memory hub

do
  local hub = Hub.new()
  local host = Relay.new({ transport = hub:connect() })
  local guest = Relay.new({ transport = hub:connect() })

  local hostJoined, guestJoined = false, false
  local hostRoster, guestRoster = nil, nil
  local hostInbox, guestInbox = {}, {}
  host:on("joined", function() hostJoined = true end)
  host:on("roster", function(m) hostRoster = m end)
  host:on("message", function(from, m) hostInbox[#hostInbox + 1] = { from = from, m = m } end)
  guest:on("joined", function() guestJoined = true end)
  guest:on("roster", function(m) guestRoster = m end)
  guest:on("message", function(from, m) guestInbox[#guestInbox + 1] = { from = from, m = m } end)

  host:host("RED")
  host:update()
  ok(hostJoined, "host reaches the lobby")
  eq(host.code, "ROOM01", "host gets a code")
  ok(host:isHost(), "host is the host")

  guest:join("ROOM01", "BLUE")
  guest:update()
  host:update()
  ok(guestJoined, "guest reaches the lobby")
  ok(not guest:isHost(), "guest is not the host")
  eq(guestRoster and #guestRoster, 2, "guest sees both members")
  eq(hostRoster and #hostRoster, 2, "host sees both members")
  eq(guest.hostId, host.id, "guest knows who the host is")

  -- broadcast a place from the host; the guest receives it
  host:broadcast(Wire.place("ROUTE_1", 3, 4, "down", "alive", "SPRITE_RED"))
  guest:update()
  eq(#guestInbox, 1, "guest received the broadcast")
  local decoded = Wire.decode(guestInbox[1].m)
  eq(decoded and decoded.map, "ROUTE_1", "the broadcast decodes")
  eq(guestInbox[1].from, host.id, "and is attributed to the host")

  -- unicast a challenge from guest to host
  guest:send(host.id, Wire.challenge(1))
  host:update()
  eq(#hostInbox, 1, "host received the unicast")
  eq(Wire.decode(hostInbox[1].m).nonce, 1, "the challenge decodes")

  -- guest leaving closes their side and updates the host roster
  guest:leave()
  host:update()
  eq(hostRoster and #hostRoster, 1, "host roster shrinks when the guest leaves")
end

io.write(("\nbattle royale: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
