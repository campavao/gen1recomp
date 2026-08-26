-- POK-105 scenario "spectate", guest side: join, and once the host says it
-- is watching, pick a fight with one of the host's bots and stay in it.
--
-- This side asserts the SENDING half -- that a watcher is registered and
-- that a fight is actually pushed to them -- while the host asserts the
-- receiving half. Neither alone would prove the round trip.
local U = require("tests.drivers.util")
local L = require("mods.battle_royale.tests.drivers.pvp.pvplib")

return function(game)
  local C = L.ctx(game)
  local DIR = os.getenv("BR_PVP_DIR")
  if not DIR then return C.fail("no BR_PVP_DIR") end

  U.newGame(game)
  local E = C.E()
  if not E then return C.fail("no battle_royale exports") end
  E.setRelay(os.getenv("BR_PVP_RELAY") or "127.0.0.1:7790")
  E.setName("GUESTB")

  local code = L.waitFor(DIR, "code.txt", 3600)
  if not code then return C.fail("no room code ever appeared") end
  code = code:gsub("%s", "")
  local joined = false
  for _ = 1, 10 do
    E.join(code)
    for _ = 1, 120 do
      U.wait(10)
      if E.memberCount() >= 2 then joined = true break end
    end
    if joined then break end
  end
  if not joined then
    return C.fail("could not join " .. code .. ": " .. tostring(E.lastError()))
  end

  if not L.waitPhase(C, "match", 360) then
    return C.fail("never reached the match")
  end
  for _ = 1, 8 do U.tap(game, "a") U.wait(20) end
  U.wait(30)

  -- Something that can survive a few turns, so the fight lasts long enough
  -- for the host to see it move.
  L.armParty(C, "MEWTWO", 100, "PSYCHIC_M")

  if not L.waitFor(DIR, "ready.txt", 3600) then
    return C.fail("the host never said it was watching")
  end

  -- The watcher list is the peek heartbeat, so by now the host should be
  -- on it. This is the sending half of the ticket.
  local watchers = nil
  for _ = 1, 400 do
    watchers = E.watchers() or {}
    if #watchers > 0 then break end
    U.wait(10)
  end
  if not (watchers and #watchers > 0) then
    return C.fail("nobody registered as watching this side")
  end
  U.log("PVP guest: " .. #watchers .. " watcher(s) registered")

  -- Pick a fight with one of the host's bots by standing it in our face:
  -- the engage sight-line has no consent step, which is normally a hazard
  -- and here is exactly the tool (see the duel scenario's probe, which has
  -- to work around the same thing).
  local botId = nil
  for _, b in ipairs(E.bots() or {}) do
    if b.status == "alive" then botId = b.id break end
  end
  if not botId then return C.fail("no living bot to pick a fight with") end

  local fought = false
  for _ = 1, 60 do
    E.debugPlaceBot(botId, C.map(), C.x(), C.y() + 1)
    U.wait(20)
    U.tap(game, "a")
    U.wait(20)
    if E.status() == "battle" or E.busy() == "battle" then fought = true break end
  end
  if not fought then
    fought = L.mashUntil(C, function() return E.busy() == "battle" end, 900)
  end
  if not fought then return C.fail("never got into a fight with the bot") end
  U.log("PVP guest: in a fight; holding it for the watcher")
  L.put(DIR, "fighting.txt", "1")

  -- Stay in it, and let it actually resolve turns -- the host asserts the
  -- view MOVES, which needs a fight that is doing something.
  for _ = 1, 260 do
    if L.get(DIR, "seen.txt") then break end
    U.tap(game, "a")
    U.wait(15)
  end

  if not L.waitFor(DIR, "seen.txt", 1200) then
    return C.fail("the host never reported seeing the fight")
  end

  local err = E.tickError and E.tickError()
  if err then return C.fail("tick error: " .. tostring(err)) end

  U.log("PVP OK guest: fight staged and pushed to the watcher")
  love.event.quit(0)
  U.wait(10)
end
