-- The forced-battle rule, as pure functions over plain tables.
--
-- Walk up to another trainer so that you are facing them on the next cell
-- and the battle starts -- no A press, no consent, the way a trainer's line
-- of sight works.  Either side facing the other is enough, so backing into
-- someone counts too.  A one-tile "eyeline"; the six-tile version is a
-- later change to `inFront` alone.
--
-- Two players can notice each other on the same tick and both challenge.
-- That is fine: a challenge from the player you are already challenging is
-- read as an acceptance, and the lower id is always the battle host (the
-- side that deals the shared RNG seed), so both machines start the same
-- battle the same way round no matter who spoke first.

local Engage = {}

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- The cell in front of a player table { x=, y=, facing= }.
function Engage.inFront(p)
  local d = DELTA[p.facing]
  if not d then return nil end
  return p.x + d[1], p.y + d[2]
end

local function canFight(p)
  return p ~= nil and p.status == "alive" and not p.moving and not p.busy
end

-- me:     { id=, map=, x=, y=, facing=, moving=, status=, busy= }
-- others: array of { id=, map=, x=, y=, facing=, moving=, status=, busy= }
-- Returns the id of the player to challenge, or nil.
function Engage.target(me, others)
  if not canFight(me) then return nil end
  local fx, fy = Engage.inFront(me)
  if not fx then return nil end
  local best
  for _, o in ipairs(others or {}) do
    if o.map == me.map and o.x == fx and o.y == fy and canFight(o) then
      if not best or o.id < best then best = o.id end
    end
  end
  return best
end

-- Whichever of the two ids is lower hosts the lockstep battle.
function Engage.isHost(myId, theirId)
  return myId < theirId
end

-- What to do with an incoming challenge.
--   "accept"  -> answer and start (also when it crosses our own challenge
--                to the same player)
--   "busy"    -> decline: we are fighting, pending with someone else, or
--                not able to fight
function Engage.answer(me, fromId, pending)
  if me.status ~= "alive" or me.inBattle then return "busy" end
  if pending and pending.to ~= fromId then return "busy" end
  return "accept"
end

return Engage
