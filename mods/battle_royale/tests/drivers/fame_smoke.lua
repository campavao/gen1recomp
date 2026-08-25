-- POK-82 smoke: the Hall of Fame is the END of the run.
--
-- Host a solo room, start, declare the win (mod.exports.debugWin -- a match
-- cannot be played down to one survivor in a driver's lifetime), sit through
-- the Champion's parade, then check the two things the ticket is about:
--   1. the champion is no longer standing in the finished match world, and
--   2. the room survived, so PLAY AGAIN can still run it back.
--
-- One client, no relay server: a solo room is a LocalRoom, so this needs
-- only LOVE and an imported ROM.  Run from a gen1recomp checkout root:
--
--   POKEPORT_GAME=red POKEPORT_IMPORT_ROM=<rom.gb> \
--   POKEPORT_IDENTITY=br-fame-smoke POKEPORT_SPEED=3 \
--   POKEPORT_DRIVER=mods/battle_royale/tests/drivers/fame_smoke.lua \
--   <path to>/lovec . > fame.log 2>&1
--
-- Exit 0 with a `FAME OK` line passes; any `PVP FAIL` line fails (the
-- failure channel comes from pvplib, shared with the two-client pair).
-- Set BR_SHOTS=<dir> to also drop screenshots of the parade and of the
-- screen the champion lands on.

local U = require("tests.drivers.util")
local L = require("mods.battle_royale.tests.drivers.pvp.pvplib")

return function(game)
  local C = L.ctx(game)
  local SHOTS = os.getenv("BR_SHOTS")
  local function shot(name)
    if SHOTS then U.shot(game, SHOTS .. "/" .. name .. ".png") end
  end

  U.newGame(game)
  local E = C.E()
  if not E then return C.fail("no battle_royale exports") end
  E.setName("CHAMP")
  E.setSafari(0)            -- skip the Safari opening: the old RATTATA drop
  E.setFog(600)             -- the fog must not end this before we do
  if not E.hostSolo() then return C.fail("hostSolo refused") end
  E.setBots(1)              -- AFTER hostSolo: it forces its own count on zero,
                            -- and one bot keeps checkWinner from firing at once

  -- hosting is asynchronous even on a LocalRoom: startMatch wants isHost(),
  -- which only becomes true once the room_hosted reply lands in a tick
  local hosted = false
  for _ = 1, 300 do
    U.wait(10)
    if (E.memberCount() or 0) >= 1 then hosted = true break end
  end
  if not hosted then
    return C.fail("the solo room never came up: " .. tostring(E.lastError()))
  end
  U.log("FAME: solo room up, " .. tostring(E.memberCount()) .. " in it")
  E.start()

  -- mash, not wait: the drop opens a town picker that wants an A
  if not L.mashUntil(C, function() return E.phase() == "match" end, 400) then
    return C.fail("never reached the match (phase " .. tostring(E.phase()) .. ")")
  end
  for _ = 1, 8 do U.tap(game, "a") U.wait(20) end
  U.wait(30)
  local ow = game.overworld
  U.log(("FAME: in the match on %s, %s alive"):format(
    tostring(C.map()), tostring(E.aliveCount())))
  shot("in-match")

  E.debugWin()
  if not L.mashUntil(C, function() return E.phase() == "over" end, 600) then
    return C.fail("the declared win never took")
  end
  U.log("FAME: phase over; waiting on the parade")

  -- Spotting the parade: `.pages` alone is NOT enough -- a Gen 1 text box
  -- has text pages too, and the win banner is on screen first.  showPage is
  -- Fame's own method, so it comes off Fame's metatable and nothing else's.
  local function fame()
    local top = game.stack:top()
    if type(top) ~= "table" then return nil end
    if top.pages == nil or top.showPage == nil then return nil end
    return top
  end
  -- tap A, then poll finely, so a page that turns itself is not missed
  local function beat()
    U.tap(game, "a")
    for _ = 1, 12 do
      if fame() then return true end
      U.wait(2)
    end
    return fame() ~= nil
  end

  local seen
  for _ = 1, 300 do
    if beat() then seen = fame() break end
  end
  if not seen then
    return C.fail("the Hall of Fame never opened (top " .. tostring(game.stack:top()) .. ")")
  end
  U.log("FAME: parade open, " .. tostring(#seen.pages) .. " pages")
  shot("fame")

  local gone = false
  for _ = 1, 300 do
    U.tap(game, "a")
    U.wait(10)
    if not fame() then gone = true break end
  end
  if not gone then return C.fail("the parade never closed") end
  U.wait(120)
  shot("after")

  -- 1. off the finished world
  local top = game.stack:top()
  if top == ow then return C.fail("still standing in the match world") end
  if game.overworld and top == game.overworld then
    return C.fail("still on an overworld after the parade")
  end
  -- 2. the room is still theirs
  local members = E.memberCount() or 0
  if members < 1 then return C.fail("the room went away with the match") end

  U.log(("FAME OK: off the overworld, %d in the room, phase %s")
        :format(members, tostring(E.phase())))
  love.event.quit(0)
  U.wait(10)
end
