-- Bot trainers: the roster, their parties, and how they wander.
--
-- Pure logic -- no love.*, no socket, no engine module -- so all of it is
-- exercised headless by tests/br_test.lua.  The host owns bot movement and
-- relays it like its own; everything else about a bot is DERIVED from the
-- match seed and the bot's id, so every client computes the same name and
-- the same party without a byte of it crossing the wire.  That matters
-- because whoever walks into a bot fights it locally: if two clients
-- disagreed about its team, they would disagree about who won.
--
-- Ids start at ID_BASE, far above anything the relay hands a real
-- connection (room ids count up from 1 and a room holds at most 16), so a
-- bot can share the players table with humans and be told apart by id alone.

local Spawn = require("mods.battle_royale.lib.spawn")

local Bots = {}

Bots.ID_BASE = 1000
Bots.MAX = 8

-- Names fit the 7-character Gen 1 box and read like trainers, not robots.
local NAMES = {
  "JOEY", "MIKEY", "CALVIN", "LASS", "TIANA", "DUDLEY", "SETH", "PIA",
  "RUDY", "NOLAN", "IVY", "MAX", "REN", "KIM", "TOBY", "VIC",
}

-- A shallow common-Kanto pool: every one of these is a real Red species and
-- a fair fight for a level 5 starter.
local SPECIES = {
  "RATTATA", "PIDGEY", "SPEAROW", "ZUBAT", "MANKEY", "EKANS", "SANDSHREW",
  "MEOWTH", "CATERPIE", "WEEDLE", "NIDORAN_M", "NIDORAN_F",
}

local DIRS = { "up", "down", "left", "right" }
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

Bots.DELTA = DELTA

function Bots.isBot(id)
  return type(id) == "number" and id >= Bots.ID_BASE
end

function Bots.idFor(index) return Bots.ID_BASE + index end

-- One deterministic stream per bot, so name/party/wander never depend on
-- call order or on which machine is asking.
function Bots.rng(seed, id)
  return Spawn.rng((tonumber(seed) or 1) + (tonumber(id) or 0) * 7919)
end

function Bots.name(seed, id)
  local rng = Bots.rng(seed, id)
  local base = NAMES[rng(1, #NAMES)]
  -- a suffix keeps two bots that rolled the same name distinguishable
  -- without pushing past the name box
  local n = id - Bots.ID_BASE
  if n > 0 and n <= 9 and #base <= 6 then return base .. tostring(n) end
  return base
end

-- The bot's team as a trainer partyDef ({species, level} rows) -- exactly
-- the shape BattleState.newTrainer's `trainer.party` hook expects, so the
-- engine builds the mons and we never touch Pokemon.new ourselves.
--
-- `species` is filtered against the live data so a pool entry this build
-- does not have degrades to RATTATA instead of asserting mid-battle.
function Bots.party(seed, id, data)
  local rng = Bots.rng(seed, id)
  local pool = {}
  for _, s in ipairs(SPECIES) do
    if not data or not data.pokemon or data.pokemon[s] then pool[#pool + 1] = s end
  end
  if #pool == 0 then pool = { "RATTATA" } end
  -- ONE mon at the starting level, because that is what a player has when
  -- they drop.  Two mons made a bot the favourite in every opening fight,
  -- so the first trainer you met usually ended your match before you could
  -- catch anything -- the opposite of a battle royale's build-a-team arc.
  -- When level scaling lands (DESIGN D12) bots grow on the same clock.
  return { { species = pool[rng(1, #pool)], level = 5 } }
end

-- Where a bot tries to step next.  Returns a direction, or nil to stand
-- still this beat.  canWalk(mapId, x, y) is supplied by the caller so this
-- stays free of the engine.
--
-- Bots keep their heading until it stops working, which reads as walking
-- somewhere rather than twitching in place.
function Bots.wander(bot, rng, canWalk)
  if rng() < 0.2 then return nil end -- a pause, so they are not machines

  local function ok(dir)
    local d = DELTA[dir]
    return d and canWalk(bot.map, bot.x + d[1], bot.y + d[2])
  end

  if bot.facing and ok(bot.facing) and rng() < 0.7 then return bot.facing end

  -- try the others in a rotated order so no direction is systematically
  -- preferred across the roster
  local start = rng(1, #DIRS)
  for i = 0, #DIRS - 1 do
    local dir = DIRS[(start + i - 1) % #DIRS + 1]
    if ok(dir) then return dir end
  end
  return nil
end

return Bots
