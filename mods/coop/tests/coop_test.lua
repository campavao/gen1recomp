-- Standalone: luajit mods/coop/tests/coop_test.lua
--
-- Covers the three pieces that can be tested without a display or a ROM:
-- the wire vocabulary, a real two-ended session over Net.loopbackPair, and
-- the ghost driver against a stub world.  The engine-side additions
-- (Handle:stepNow, world.talk) are exercised through that stub too.
package.path = "./?.lua;./?/init.lua;" .. package.path

local passed, failed = 0, 0

local function ok(cond, label)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("  FAIL: ", label, "\n")
  end
end

local function eq(got, want, label)
  if got ~= want then
    failed = failed + 1
    io.write(("  FAIL: %s (got %s, want %s)\n"):format(
      label, tostring(got), tostring(want)))
  else
    passed = passed + 1
  end
end

local Wire = require("mods.coop.lib.wire")
local Session = require("mods.coop.lib.session")
local Ghosts = require("mods.coop.lib.ghosts")

-- ------- wire

do
  local m = Wire.decode(Wire.hello({ name = "RED", sprite = "SPRITE_RED",
    map = "PALLET_TOWN", x = 5, y = 6, facing = "down" }))
  ok(m ~= nil, "hello round-trips")
  eq(m and m.name, "RED", "hello carries the name")
  eq(m and m.map, "PALLET_TOWN", "hello carries the map")
  eq(m and m.facing, "down", "hello carries the facing")

  local step = Wire.decode(Wire.step("up", 5, 5, "ROUTE_1"))
  eq(step and step.dir, "up", "step carries the direction")
  eq(step and step.x, 5, "step carries the destination cell")

  -- rejections: a peer is a stranger's build, not a trusted caller
  ok(Wire.decode({ t = "step", d = "sideways", x = 1, y = 1 }) == nil,
     "a bogus direction is refused")
  ok(Wire.decode({ t = "step", d = "up", x = 1e9, y = 1 }) == nil,
     "an out-of-range cell is refused")
  ok(Wire.decode({ t = "place", map = "", x = 1, y = 1, f = "up" }) == nil,
     "an empty map id is refused")
  ok(Wire.decode({ t = "hello", v = 999, map = "X", x = 1, y = 1, f = "up" }) == nil,
     "a mismatched protocol is refused")
  ok(Wire.decode({ t = "nonsense" }) == nil, "an unknown type is refused")
  ok(Wire.decode("not a table") == nil, "a non-table is refused")

  eq(Wire.cleanName("\1\2BAD\3"), "BAD", "control characters are stripped")
  eq(Wire.cleanName(""), "PLAYER", "an empty name falls back")
  eq(#Wire.cleanName(("X"):rep(50)), 10, "an over-long name is trimmed")
end

-- ------- code/address entry
--
-- The Gen 1 naming grid has no digits, so a room code (Crockford-32) and a
-- dotted IP both need the scrub widget instead.  These guard that the
-- generalization stayed backward compatible for LinkState's own use.

do
  local CodeEntry = require("src.link.CodeEntry")

  local code = CodeEntry.new()
  eq(code.length, 6, "default length is the room-code shape")
  eq(#CodeEntry.text(code), 6, "default text is six characters")
  ok(CodeEntry.CHARSET:find("2", 1, true) ~= nil, "charset carries digits")
  ok(CodeEntry.CHARSET:find("0", 1, true) == nil, "no 0/O ambiguity")

  -- scrubbing wraps in both directions
  local first = CodeEntry.text(code):sub(1, 1)
  CodeEntry.down(code)
  eq(CodeEntry.text(code):sub(1, 1), CodeEntry.CHARSET:sub(-1),
     "down from slot 1 wraps to the last character")
  CodeEntry.up(code)
  eq(CodeEntry.text(code):sub(1, 1), first, "up returns to where it started")

  -- cursor clamps rather than wrapping
  CodeEntry.left(code)
  eq(code.pos, 1, "left clamps at the first slot")
  for _ = 1, 20 do CodeEntry.right(code) end
  eq(code.pos, 6, "right clamps at the last slot")

  -- the address shape, and seeding from text
  local addr = CodeEntry.fromText("192.168.1.40", { charset = "0123456789. ", length = 15 })
  eq(CodeEntry.text(addr):gsub("%s+$", ""), "192.168.1.40", "an address round-trips")
  local seeded = CodeEntry.fromText("A!B", { charset = "0123456789. ", length = 15 })
  eq(CodeEntry.charAt(seeded, 1), " ", "a character outside the charset blanks out")
  -- a charset with no blank (the room code) has nowhere to put one
  local noBlank = CodeEntry.fromText("@@", { charset = "AB", length = 2 })
  eq(CodeEntry.text(noBlank), "AA", "a blankless charset falls back to slot 1")

  -- two widgets of different shapes must not read each other's alphabet
  local a = CodeEntry.new()
  local b = CodeEntry.new({ charset = "01", length = 2 })
  CodeEntry.up(b)
  eq(CodeEntry.text(b), "10", "the narrow widget scrubs its own charset")
  eq(#CodeEntry.text(a), 6, "the room-code widget is unaffected")
end

-- ------- session, both ends live

do
  local Net = require("src.link.Net")
  local a, b = Net.loopbackPair()

  local function ident(name, x)
    return function()
      return { name = name, sprite = "SPRITE_RED",
               map = "PALLET_TOWN", x = x, y = 6, facing = "down" }
    end
  end

  local host = Session.new({ transport = a, identity = ident("RED", 5) })
  local guest = Session.new({ transport = b, identity = ident("BLUE", 9) })
  host.status, guest.status = "hosting", "joining"

  local seen = {}
  host:on("hello", function(p) seen.hello = p.name end)
  host:on("step", function(m) seen.step = m.dir end)
  host:on("face", function(m) seen.face = m.facing end)
  host:on("place", function() seen.place = true end)
  host:on("invite", function(kind) seen.invite = kind end)

  -- a few pumps: pairing, then the hello both ends send on their first
  -- paired frame, then whatever the test sends after
  for _ = 1, 4 do host:update(1 / 60); guest:update(1 / 60) end

  eq(seen.hello, "BLUE", "the host learns the guest's name")
  ok(host:isConnected(), "the host reaches connected")
  ok(guest:isConnected(), "the guest reaches connected")
  eq(host.peer and host.peer.x, 9, "the peer's position arrives with hello")

  guest:send(Wire.step("up", 9, 5, "PALLET_TOWN"))
  guest:send(Wire.face("left", "PALLET_TOWN"))
  guest:send(Wire.place("ROUTE_1", 2, 3, "right"))
  guest:send(Wire.invite("battle"))
  for _ = 1, 3 do host:update(1 / 60); guest:update(1 / 60) end

  eq(seen.step, "up", "a step reaches the other end")
  eq(seen.face, "left", "a turn reaches the other end")
  ok(seen.place, "a resync reaches the other end")
  eq(seen.invite, "battle", "an invite reaches the other end")
  eq(host.peer.map, "ROUTE_1", "place moves the tracked peer to the new map")
  eq(host.peer.x, 2, "place updates the tracked cell")

  -- a peer that says nothing is eventually declared gone
  local gone = false
  host:on("gone", function() gone = true end)
  host.lastHeard = -1e9
  host:update(1 / 60)
  ok(gone, "silence past the timeout closes the session")
end

-- ------- ghosts, against a stub world
--
-- The stub answers the same WorldAPI surface the mod uses, including the
-- Handle methods added for this feature, so the driver's spawn/despawn and
-- queue-draining logic is checked without a renderer.

do
  local world = { spawned = {}, nextId = 0 }
  local function makeHandle(rec)
    return {
      isMoving = function() return rec.moving end,
      position = function() return rec.x, rec.y end,
      face = function(_, dir) rec.facing = dir end,
      stepNow = function(_, dir) rec.moving = true; rec.steps[#rec.steps + 1] = dir end,
      placeAt = function(_, x, y, f) rec.x, rec.y, rec.facing = x, y, f; rec.moving = false end,
      setPassable = function(_, v) rec.passable = v end,
    }
  end
  function world:spawnNpc(mapId, def)
    self.nextId = self.nextId + 1
    local id = mapId .. "_obj_" .. self.nextId
    self.spawned[id] = { x = def.x, y = def.y, facing = "down",
                         moving = false, steps = {}, map = mapId,
                         sprite = def.sprite }
    return id
  end
  function world:removeNpc(id)
    if not self.spawned[id] then return nil, "no such object" end
    self.spawned[id] = nil
    return true
  end
  function world:npc(mapId, id)
    local rec = self.spawned[id]
    if not rec or rec.map ~= mapId then return nil end
    return makeHandle(rec)
  end

  local warned = {}
  local mod = { world = world,
                log = { warn = function(_, f, ...) warned[#warned + 1] = f end } }
  local game = { data = { sprites = { SPRITE_RED = {} },
                          field = { playerSprites = { walk = "SPRITE_RED" } } } }

  local g = Ghosts.new(mod)
  local peer = { map = "PALLET_TOWN", x = 4, y = 7, facing = "down",
                 sprite = "SPRITE_RED" }

  g:sync(game, "PALLET_TOWN", peer)
  ok(g:isSpawned(), "a peer on our map gets a body")
  local id = g.npcId
  eq(world.spawned[id].x, 4, "spawned at the peer's cell")
  eq(world.spawned[id].passable, false, "a solid peer blocks by default")

  -- the non-solid variant lets you walk through your friend
  local loose = Ghosts.new(mod, false)
  loose:sync(game, "PALLET_TOWN", peer)
  eq(world.spawned[loose.npcId].passable, true, "SOLID PEER off makes it passable")
  loose:despawn()

  -- a peer that walks away from our map takes its body with it
  peer.map = "ROUTE_1"
  g:sync(game, "PALLET_TOWN", peer)
  ok(not g:isSpawned(), "a peer on another map has no body here")
  eq(next(world.spawned), nil, "the runtime object is actually removed")

  -- back again, then walk
  peer.map = "PALLET_TOWN"
  g:sync(game, "PALLET_TOWN", peer)
  id = g.npcId
  ok(g:isSpawned(), "the body comes back when the peer does")

  g:pushStep("up")
  peer.y = 6
  g:sync(game, "PALLET_TOWN", peer)
  eq(world.spawned[id].steps[1], "up", "a queued step is walked")

  -- while a step animates, nothing else starts
  g:pushStep("up")
  g:sync(game, "PALLET_TOWN", peer)
  eq(#world.spawned[id].steps, 1, "a step in flight is not interrupted")

  -- a backlog past MAX_BACKLOG snaps instead of walking it off
  world.spawned[id].moving = false
  for _ = 1, 6 do g:pushStep("up") end
  peer.x, peer.y = 4, 1
  g:sync(game, "PALLET_TOWN", peer)
  eq(world.spawned[id].y, 1, "too far behind snaps to the truth")
  eq(#g.queue, 0, "snapping clears the backlog")

  -- an unknown sprite must not reach NPC.new, which asserts on one
  eq(g:resolveSprite(game, "SPRITE_FROM_A_MOD_WE_LACK"), "SPRITE_RED",
     "an unknown peer sprite falls back")
  eq(g:resolveSprite(game, "SPRITE_RED"), "SPRITE_RED", "a known sprite is kept")

  g:despawn()
  eq(next(world.spawned), nil, "despawn leaves nothing behind")
end

io.write(("\ncoop: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
