-- What a spectator is shown of somebody else's fight (POK-105).
--
-- Push, not pull -- the opposite of the party peek next door (POK-18), and
-- for a reason. A party changes when somebody catches something, so asking
-- every three seconds is fine; a fight changes on a beat you have to be
-- there for, and a spectator polling it would watch a slideshow of a
-- battle that had already moved on.
--
-- WHY A SUMMARY AND NOT THE LOCKSTEP. It is tempting to think a spectator
-- could just listen to the PvP battle traffic, but there is none to listen
-- to for most fights: a bot, a wild encounter and one of Kanto's own
-- trainers are resolved ENTIRELY on the one client, from the match seed,
-- with nothing crossing the wire at all (BR:startBotBattle). Only a duel
-- has a wire protocol, it is a two-party lockstep carried by unicast
-- (lib/channel.lua), and a third party replaying it would have to run a
-- phantom LinkBattle that could only ever drift out of step. So the view
-- is derived from whatever the watched client can SEE of its own battle,
-- which is the one thing every kind of fight has in common.
--
-- It is also small. A frame is around 180 bytes against the ~780 the party
-- peek already spends every three seconds, so even a frame per visible
-- change costs less than the stream running beside it -- which is what
-- lets this be pushed at all (see POK-114 for what a burst costs).
--
-- Pure: plain tables in, plain tables out, so br_test covers the whole of
-- it without a battle, a ROM, or a running match.

local BView = {}

-- One side of a fight, as a watcher needs it.
--
-- shownHP, not mon.hp, when it is there: it is the value the HP BAR is
-- displaying, which drains behind the real number so the bar lands with
-- the message that explains it. Sending the real HP would drop the
-- watcher's bar a beat before "it's super effective!" arrives.
local function side(battler)
  local mon = battler and battler.mon
  if not (mon and mon.species) then return nil end
  local maxHp = (mon.stats and mon.stats.hp) or mon.maxHp or mon.hp or 1
  local hp = battler.shownHP or mon.hp or 0
  local nick = mon.nickname
  return {
    sp = mon.species,
    -- only when it says something the species does not; a match skips the
    -- nickname prompt (POK-12), so this is almost always absent
    nm = (type(nick) == "string" and nick ~= "" and nick ~= mon.species)
         and nick or nil,
    lv = math.max(1, math.floor(tonumber(mon.level) or 1)),
    hp = math.max(0, math.floor(tonumber(hp) or 0)),
    mhp = math.max(1, math.floor(tonumber(maxHp) or 1)),
    st = mon.status,
  }
end

BView.side = side

-- Build a view from a live BattleState. Reads display fields only and
-- never touches the turn loop, so it is safe to call from the mod's tick
-- the way the fog already reads battle.player.mon.hp.
--
-- `who` is what to call the opponent (a bot's name, a duelist's name, or
-- nil for a wild encounter); `msg` is the last line the battle put up.
function BView.of(battle, who, msg)
  if type(battle) ~= "table" then return nil end
  local me, foe = side(battle.player), side(battle.enemy)
  if not (me and foe) then return nil end
  return {
    me = me, foe = foe,
    who = (type(who) == "string" and who ~= "") and who or nil,
    msg = (type(msg) == "string" and msg ~= "") and msg or nil,
  }
end

local function sameSide(a, b)
  if a == nil or b == nil then return a == b end
  return a.sp == b.sp and a.nm == b.nm and a.lv == b.lv
     and a.hp == b.hp and a.mhp == b.mhp and a.st == b.st
end

-- Has anything a spectator would SEE changed? This is the whole rate
-- limit: a battle spends most of its frames animating something already
-- sent, and a frame per tick would be the flood POK-114 was about.
function BView.changed(a, b)
  if a == nil or b == nil then return a ~= b end
  return not (sameSide(a.me, b.me) and sameSide(a.foe, b.foe)
              and a.who == b.who and a.msg == b.msg)
end

-- How full a bar is, 0..1. Nil-safe because a view can arrive for a
-- species this build does not know.
function BView.fraction(s)
  if type(s) ~= "table" then return 0 end
  local mhp = tonumber(s.mhp) or 0
  if mhp <= 0 then return 0 end
  local f = (tonumber(s.hp) or 0) / mhp
  if f < 0 then return 0 end
  if f > 1 then return 1 end
  return f
end

-- The name to print for one side: the nickname if there is one, else the
-- species' own name from data, else the raw id -- so a species this build
-- has never heard of still draws a row instead of a blank.
function BView.nameOf(data, s)
  if type(s) ~= "table" then return "?" end
  if s.nm then return s.nm end
  local pokemon = type(data) == "table" and data.pokemon
  local def = type(pokemon) == "table" and pokemon[s.sp]
  local name = type(def) == "table" and def.name
  return (type(name) == "string" and name ~= "") and name or tostring(s.sp or "?")
end

return BView
