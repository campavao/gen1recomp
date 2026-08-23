-- The co-op wire protocol: message constructors and a validating decoder.
--
-- Pure logic -- no love.*, no socket, no engine module -- so the whole
-- protocol is exercised headless by tests/coop_test.lua.  Everything that
-- touches the network lives in session.lua; everything that touches the
-- overworld lives in ghosts.lua.
--
-- Messages ride src/link/Net.lua, which JSON-encodes a plain table onto
-- ENet's reliable-ordered channel (or the relay's newline-delimited TCP).
-- Field names are short because a step message goes out roughly four times
-- a second per player and the relay is someone else's bandwidth.
--
--   {t="hello", v=1, name=, sprite=, map=, x=, y=, f=}  identity + placement
--   {t="step",  d=, x=, y=, map=}                       a step just committed
--   {t="face",  f=, map=}                               a turn in place
--   {t="place", map=, x=, y=, f=}                       authoritative resync
--   {t="invite", kind="battle"|"trade"}                 interaction request
--   {t="reply",  kind=, ok=}                            accept / decline
--   {t="ping", s=} / {t="pong", s=}                     keepalive + RTT
--   {t="bye", why=}                                     clean disconnect
--
-- A peer that speaks a different PROTOCOL is refused at hello rather than
-- half-understood: a co-op session where one side silently drops `step` is
-- worse than one that never starts.

local Wire = {}

Wire.PROTOCOL = 1

-- The four grid directions, as the engine spells them (Collision.DELTA).
Wire.DIRS = { up = true, down = true, left = true, right = true }

-- Bounds that make a malformed or hostile packet cheap to reject.  Map ids
-- are engine constants (PALLET_TOWN, ROUTE_1); cells are walk-grid indices
-- and no Gen 1 map is anywhere near 1000 cells on a side.
local MAX_NAME = 10
local MAX_ID = 64
local MAX_CELL = 1000

local function isCell(v)
  return type(v) == "number" and v == math.floor(v)
     and v >= -MAX_CELL and v <= MAX_CELL
end

local function isMapId(v)
  return type(v) == "string" and v ~= "" and #v <= MAX_ID
end

-- Trim to the name box's width and drop anything the font cannot draw, so a
-- peer cannot inject control characters into our text boxes.
function Wire.cleanName(name)
  if type(name) ~= "string" then return "PLAYER" end
  local out = name:gsub("[^%w%p ]", ""):sub(1, MAX_NAME)
  if out == "" then return "PLAYER" end
  return out
end

-- ------- constructors

function Wire.hello(me)
  return { t = "hello", v = Wire.PROTOCOL, name = me.name, sprite = me.sprite,
           map = me.map, x = me.x, y = me.y, f = me.facing }
end

-- dir is the direction stepped; x,y the destination cell.  Both travel so
-- the receiver can animate the walk AND correct drift in the same message.
function Wire.step(dir, x, y, map)
  return { t = "step", d = dir, x = x, y = y, map = map }
end

function Wire.face(facing, map)
  return { t = "face", f = facing, map = map }
end

function Wire.place(map, x, y, facing)
  return { t = "place", map = map, x = x, y = y, f = facing }
end

function Wire.invite(kind) return { t = "invite", kind = kind } end
function Wire.reply(kind, ok) return { t = "reply", kind = kind, ok = ok and true or false } end
function Wire.ping(seq) return { t = "ping", s = seq } end
function Wire.pong(seq) return { t = "pong", s = seq } end
function Wire.bye(why) return { t = "bye", why = why } end

-- ------- decoding
--
-- Returns a normalized message, or nil + a reason.  The session drops what
-- does not validate instead of trusting the shape: Net hands us whatever
-- the other end sent, and "the other end" is a stranger's build.

local decoders = {}

decoders.hello = function(m)
  if m.v ~= Wire.PROTOCOL then
    return nil, ("protocol %s, expected %d"):format(tostring(m.v), Wire.PROTOCOL)
  end
  if not isMapId(m.map) then return nil, "bad map" end
  if not (isCell(m.x) and isCell(m.y)) then return nil, "bad cell" end
  if not Wire.DIRS[m.f] then return nil, "bad facing" end
  return { t = "hello", v = m.v, name = Wire.cleanName(m.name),
           sprite = type(m.sprite) == "string" and #m.sprite <= MAX_ID
                    and m.sprite or nil,
           map = m.map, x = m.x, y = m.y, facing = m.f }
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

decoders.place = function(m)
  if not isMapId(m.map) then return nil, "bad map" end
  if not (isCell(m.x) and isCell(m.y)) then return nil, "bad cell" end
  if not Wire.DIRS[m.f] then return nil, "bad facing" end
  return { t = "place", map = m.map, x = m.x, y = m.y, facing = m.f }
end

local KINDS = { battle = true, trade = true }

decoders.invite = function(m)
  if not KINDS[m.kind] then return nil, "bad kind" end
  return { t = "invite", kind = m.kind }
end

decoders.reply = function(m)
  if not KINDS[m.kind] then return nil, "bad kind" end
  return { t = "reply", kind = m.kind, ok = m.ok and true or false }
end

decoders.ping = function(m)
  if type(m.s) ~= "number" then return nil, "bad seq" end
  return { t = "ping", seq = m.s }
end

decoders.pong = function(m)
  if type(m.s) ~= "number" then return nil, "bad seq" end
  return { t = "pong", seq = m.s }
end

decoders.bye = function(m)
  return { t = "bye", why = type(m.why) == "string" and m.why:sub(1, MAX_ID) or nil }
end

function Wire.decode(m)
  if type(m) ~= "table" then return nil, "not a table" end
  local decoder = decoders[m.t]
  if not decoder then return nil, "unknown type: " .. tostring(m.t) end
  return decoder(m)
end

return Wire
