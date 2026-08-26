-- POK-105 scenario "spectate", host side: host the room with bots, start
-- the match, then eliminate ourselves on purpose and watch the guest.
--
-- The assertion is that a spectator is SHOWN the fight the trainer they
-- watch is in -- both actives, their levels and their HP -- rather than
-- sitting on an empty map while somebody else's battle happens off screen.
--
-- The host is the one that goes out because it owns the bots, so the guest
-- can be handed one to fight without either side having to find the other.
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
  E.setName("HOSTA")
  E.setBots(2)          -- one for the guest to fight, one to keep the match alive
  E.setSafari(0)
  E.setFog(600)
  E.host()

  local code = nil
  for _ = 1, 600 do
    U.wait(10)
    code = E.code()
    if code then break end
  end
  if not code then
    return C.fail("hosting never produced a code: " .. tostring(E.lastError()))
  end
  L.put(DIR, "code.txt", tostring(code))

  local both = false
  for _ = 1, 1800 do
    U.wait(10)
    if E.memberCount() >= 2 then both = true break end
  end
  if not both then return C.fail("the guest never joined") end
  E.start()

  if not L.waitPhase(C, "match", 240) then
    return C.fail("never reached the match")
  end
  for _ = 1, 8 do U.tap(game, "a") U.wait(20) end
  U.wait(30)

  -- Out on purpose: a spectator is what this scenario is about, and going
  -- out is the only way to become one.
  E.debugOut("spectate scenario")
  if not L.mashUntil(C, function() return E.status() == "out" end, 600) then
    return C.fail("debugOut did not put this side out (" .. tostring(E.status()) .. ")")
  end
  U.log("PVP host: out, and spectating")

  -- Find the guest and watch THEM, not a bot.  By ID, not by name: a bot is
  -- dealt a real trainer name from the seed (POK-89), so "does it look like
  -- a bot" is unanswerable from the name -- the first run of this settled
  -- on bot 1002 and then wondered why nobody was watching the guest.  Bots
  -- own the ids at and above Bots.ID_BASE, and E.bots() enumerates exactly
  -- those, so anybody NOT in that list is a person.
  local isBot = {}
  for _, b in ipairs(E.bots() or {}) do isBot[b.id] = true end
  local guestId = nil
  for _, p in ipairs(E.players() or {}) do
    if not isBot[p.id] then guestId = p.id end
  end
  if not guestId then
    return C.fail("could not tell the guest apart from the bots")
  end
  U.log("PVP host: the guest is " .. tostring(guestId))

  local watched = nil
  for _ = 1, 40 do
    watched = E.watching()
    if watched == guestId then break end
    E.hop(1)
    U.wait(20)
  end
  if watched ~= guestId then
    return C.fail(("never settled on the guest: watching %s, wanted %s")
                  :format(tostring(watched), tostring(guestId)))
  end
  L.put(DIR, "watching.txt", tostring(watched))
  U.log("PVP host: watching " .. tostring(watched))

  -- The peek heartbeat is the subscription, so give it a beat to register
  -- on the far side before asking for a fight to be staged.
  U.wait(240)
  L.put(DIR, "ready.txt", "1")

  if not L.waitFor(DIR, "fighting.txt", 3600) then
    return C.fail("the guest never reported a fight")
  end

  -- ...and here is the whole ticket: are we shown it?
  local view = nil
  for _ = 1, 900 do
    view = E.watchedBattle()
    if view and view.me and view.foe then break end
    U.wait(10)
  end
  if not (view and view.me and view.foe) then
    return C.fail("no battle view ever arrived for the watched trainer")
  end
  if view.id ~= watched then
    return C.fail(("the view is about %s, not the trainer being watched %s")
                  :format(tostring(view.id), tostring(watched)))
  end
  U.log(("PVP host: shown %s L%d %d/%d vs %s L%d %d/%d%s")
        :format(tostring(view.me.sp), view.me.lv or 0, view.me.hp or 0,
                view.me.mhp or 0, tostring(view.foe.sp), view.foe.lv or 0,
                view.foe.hp or 0, view.foe.mhp or 0,
                view.who and (" (" .. view.who .. ")") or ""))
  if not (view.me.mhp > 0 and view.foe.mhp > 0) then
    return C.fail("a view arrived with no maximum HP to draw a bar from")
  end

  -- It must also be LIVE, not one stale frame: the fight moves, so the
  -- numbers must move with it.
  local first = view.me.hp .. "/" .. view.foe.hp .. "/" .. tostring(view.me.sp)
              .. "/" .. tostring(view.foe.sp)
  local moved = false
  for _ = 1, 1200 do
    local v = E.watchedBattle()
    if v and v.me and v.foe then
      local now = v.me.hp .. "/" .. v.foe.hp .. "/" .. tostring(v.me.sp)
                .. "/" .. tostring(v.foe.sp)
      if now ~= first then moved = true break end
    end
    U.wait(10)
  end
  if not moved then
    return C.fail("the view never changed -- a still frame, not a fight")
  end
  U.log("PVP host: and it follows the fight as it resolves")

  -- The panel is drawn through render.hud, whose throws are swallowed by
  -- the hook chain -- so the only proof it renders is a frame with it on.
  -- The overworld must be on top or the overlay's own guard skips it
  -- (POK-78's lesson), so mash B to a quiet map first.
  local SHOTS = os.getenv("BR_SHOTS")
  if SHOTS then
    for _ = 1, 60 do
      if game.stack:top() == C.ow() then break end
      U.tap(game, "b")
      U.wait(12)
    end
    if game.stack:top() == C.ow() then
      U.shot(game, SHOTS .. "/spectate_panel.png")
      U.log("PVP host: panel shot taken")
    else
      U.log("PVP host: could not reach a quiet map for the shot")
    end
  end

  local err = E.tickError and E.tickError()
  if err then return C.fail("tick error: " .. tostring(err)) end

  L.put(DIR, "seen.txt", "1")
  U.log("PVP OK host: spectating followed the guest into their battle")
  love.event.quit(0)
  U.wait(10)
end
