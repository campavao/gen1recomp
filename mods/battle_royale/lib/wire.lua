-- The battle-royale room vocabulary: constructors and a validating decoder.
--
-- Pure logic -- no love.*, no socket, no engine module -- so the protocol is
-- exercised headless by tests/br_test.lua.  Everything that touches the
-- network lives in relay.lua; everything that touches the overworld lives
-- in ghosts.lua and main.lua.
--
-- These are the `m` payloads inside the relay's {type="recv", from=, m=}
-- envelope (see relay/server.js).  Field names are short because a step
-- goes out roughly four times a second per player to every other player.
--
--   {t="place", map=, x=, y=, f=, st=, sprite=}   where I am + my status
--   {t="step",  d=, x=, y=, map=}                 a step just committed
--   {t="face",  f=, map=}                         a turn in place
--   {t="start", seed=, spawns={{id=,map=,x=,y=}}} host: the match begins
--   {t="challenge", n=}                           I am facing you: fight
--   {t="accept", n=} / {t="decline", n=, why=}    the reply
--   {t="bt", m={...}}                             one link-battle message
--   {t="out"}                                     I have been eliminated
--   {t="winner", id=}                             host: the match is over
--
-- Statuses: "lobby" (not in the world yet), "alive", "battle" (locked in
-- a fight -- do not engage), "out" (eliminated, spectating on foot).
--
-- A peer that speaks a different PROTOCOL is refused at `place` rather than
-- half-understood.

local Wire = {}

Wire.PROTOCOL = 1

Wire.DIRS = { up = true, down = true, left = true, right = true }
Wire.STATUS = { lobby = true, alive = true, battle = true, out = true }

local MAX_NAME = 7     -- the Gen 1 player name box
local MAX_ID = 64
local MAX_CELL = 1000
local MAX_PLAYERS = 32

local function isCell(v)
  return type(v) == "number" and v == math.floor(v)
     and v >= -MAX_CELL and v <= MAX_CELL
end

local function isMapId(v)
  return type(v) == "string" and v ~= "" and #v <= MAX_ID
end

local function isId(v)
  return type(v) == "number" and v == math.floor(v) and v >= 1 and v <= 1e6
end

-- Trim to the name box's width and drop anything the font cannot draw, so a
-- peer cannot inject control characters into our text boxes.
function Wire.cleanName(name)
  if type(name) ~= "string" then return "PLAYER" end
  local out = name:gsub("[^%w%p ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  out = out:sub(1, MAX_NAME):gsub("%s+$", "")  -- capping can re-expose a space
  if out == "" then return "PLAYER" end
  return out
end

-- ------- constructors

function Wire.place(map, x, y, facing, status, sprite)
  return { t = "place", v = Wire.PROTOCOL, map = map, x = x, y = y, f = facing,
           st = status, sprite = sprite }
end

function Wire.step(dir, x, y, map)
  return { t = "step", d = dir, x = x, y = y, map = map }
end

function Wire.face(facing, map)
  return { t = "face", f = facing, map = map }
end

-- spawns: array of { id=, map=, x=, y= }, one per player in the match
function Wire.start(seed, spawns)
  return { t = "start", seed = seed, spawns = spawns }
end

function Wire.challenge(nonce) return { t = "challenge", n = nonce } end
function Wire.accept(nonce) return { t = "accept", n = nonce } end
function Wire.decline(nonce, why) return { t = "decline", n = nonce, why = why } end
function Wire.battle(inner) return { t = "bt", m = inner } end
function Wire.out() return { t = "out" } end
function Wire.winner(id) return { t = "winner", id = id } end

-- ------- decoding
--
-- Returns a normalized message, or nil + a reason.  The caller drops what
-- does not validate instead of trusting the shape: the relay forwards
-- whatever the other end sent, and "the other end" is a stranger's build.

local decoders = {}

decoders.place = function(m)
  if m.v ~= Wire.PROTOCOL then
    return nil, ("protocol %s, expected %d"):format(tostring(m.v), Wire.PROTOCOL)
  end
  if m.map ~= nil and not isMapId(m.map) then return nil, "bad map" end
  if m.map ~= nil and not (isCell(m.x) and isCell(m.y)) then return nil, "bad cell" end
  if m.f ~= nil and not Wire.DIRS[m.f] then return nil, "bad facing" end
  if not Wire.STATUS[m.st] then return nil, "bad status" end
  return { t = "place", map = m.map, x = m.x, y = m.y, facing = m.f or "down",
           status = m.st,
           sprite = type(m.sprite) == "string" and #m.sprite <= MAX_ID
                    and m.sprite or nil }
end

decoders.step = function(m)
  if not Wire.DIRS[m.d] then return nil, "bad dir" end
  if not (isCell(m.x) and isCell(m.y)) then return nil, "bad cell" end
  if m.map ~= nil and not isMapId(m.map) then return nil, "bad map" end
  return { t = "step", dir = m.d, x = m.x, y = m.y, map = m.map }
end

decoders.face = function(m)
  if not Wire.DIRS[m.f] then return nil, "bad facing" end
  if m.map ~= nil and not isMapId(m.map) then return nil, "bad map" end
  return { t = "face", facing = m.f, map = m.map }
end

decoders.start = function(m)
  if type(m.seed) ~= "number" then return nil, "bad seed" end
  if type(m.spawns) ~= "table" then return nil, "bad spawns" end
  local spawns = {}
  for i, s in ipairs(m.spawns) do
    if i > MAX_PLAYERS then break end
    if type(s) ~= "table" or not isId(s.id) or not isMapId(s.map)
       or not (isCell(s.x) and isCell(s.y)) then
      return nil, "bad spawn"
    end
    spawns[#spawns + 1] = { id = s.id, map = s.map, x = s.x, y = s.y }
  end
  if #spawns == 0 then return nil, "no spawns" end
  return { t = "start", seed = math.floor(m.seed), spawns = spawns }
end

local function nonce(m)
  if type(m.n) ~= "number" then return nil end
  return math.floor(m.n)
end

decoders.challenge = function(m)
  local n = nonce(m)
  if not n then return nil, "bad nonce" end
  return { t = "challenge", nonce = n }
end

decoders.accept = function(m)
  local n = nonce(m)
  if not n then return nil, "bad nonce" end
  return { t = "accept", nonce = n }
end

decoders.decline = function(m)
  local n = nonce(m)
  if not n then return nil, "bad nonce" end
  return { t = "decline", nonce = n,
           why = type(m.why) == "string" and m.why:sub(1, MAX_ID) or nil }
end

decoders.bt = function(m)
  -- the inner message is LinkBattle's; Session/Wire.sanitize validates it
  -- on the way into the battle, so here it only has to be a table
  if type(m.m) ~= "table" then return nil, "bad battle payload" end
  return { t = "bt", inner = m.m }
end

decoders.out = function() return { t = "out" } end

decoders.winner = function(m)
  if m.id ~= nil and not isId(m.id) then return nil, "bad id" end
  return { t = "winner", id = m.id }
end

function Wire.decode(m)
  if type(m) ~= "table" then return nil, "not a table" end
  local decoder = decoders[m.t]
  if not decoder then return nil, "unknown type: " .. tostring(m.t) end
  return decoder(m)
end

return Wire
