-- Kanto Battle Royale: last trainer standing.
--
-- Shape of the thing:
--   lib/wire.lua     the room message vocabulary (pure, headless-testable)
--   lib/relay.lua    the connection to relay/server.js (over src/link/Net.lua)
--   lib/spawn.lua    where everyone drops (pure)
--   lib/engage.lua   the forced-battle rule (pure)
--   lib/ghosts.lua   the other players as real overworld NPCs
--   lib/channel.lua  one battle's transport, tunnelled through the room
--   lib/menu.lua     the BATTLE ROYALE start-menu screen
--   this file        the wiring
--
-- The loop, once a match starts: everyone drops onto a random Kanto cell
-- with a level 5 RATTATA, six POKe BALLs and a POTION; you see each other
-- walk in real time; walk into someone face-to-face and the battle starts
-- with no prompt; your party is your health, so a whiteout puts you out;
-- last trainer standing wins.
--
-- Two directions to keep straight.  Outbound: local steps/turns become
-- room messages (off movement.speed and a per-tick facing check).  Inbound:
-- the relay's messages drive the ghosts and the engage/battle handoff.
--
-- Everything runs on the engine's 60 Hz fixed step (the input.step hook),
-- so there is no thread and no lock anywhere in here.

local Wire = require("mods.battle_royale.lib.wire")
local Relay = require("mods.battle_royale.lib.relay")
local Spawn = require("mods.battle_royale.lib.spawn")
local Engage = require("mods.battle_royale.lib.engage")
local Ghosts = require("mods.battle_royale.lib.ghosts")
local Channel = require("mods.battle_royale.lib.channel")
local BRMenu = require("mods.battle_royale.lib.menu")

local SCREEN = "BattleRoyaleMenu"
local DEFAULT_RELAY = "127.0.0.1:7790"

-- Full position resync cadence: steps and turns keep a ghost honest, this
-- is insurance against a dropped message and against a peer moving in a way
-- we do not model (a warp).  5 seconds at 60 Hz.
local RESYNC_TICKS = 300

-- The starting loadout, all in one place (docs/DESIGN.md D7).
local START_SPECIES = "RATTATA"
local START_LEVEL = 5
local START_ITEMS = { POKE_BALL = 6, POTION = 1 }
local START_MONEY = 3000

-- Story flags a fresh Kanto save normally earns in Pallet/Oak's lab.  Set
-- at match start so the intro scripts never fire and the towns are free to
-- walk, while every route/gym trainer stays live as PvE.
local STORY_FLAGS = {
  "EVENT_FOLLOWED_OAK_INTO_LAB", "EVENT_GOT_STARTER", "EVENT_GOT_POKEDEX",
  "EVENT_GOT_POKEBALLS_FROM_OAK", "EVENT_PALLET_AFTER_GETTING_POKEBALLS",
  "EVENT_GOT_OAKS_PARCEL", "EVENT_OAK_GOT_PARCEL",
}

return function(mod)
  mod.options:define({
    { key = "relay", label = "RELAY", type = "text", default = DEFAULT_RELAY },
  })

  local BR = {
    relay = nil,
    ghosts = Ghosts.new(mod),
    game = nil,
    phase = "off",        -- off | lobby | match | over
    status = "lobby",     -- my status: lobby | alive | battle | out
    players = {},         -- id -> { name, map, x, y, facing, sprite, status }
    myId = nil,
    sentFacing = nil,
    sentMap = nil,
    resync = 0,
    pending = nil,        -- an outstanding challenge { to, nonce, host }
    battle = nil,         -- active fight { channel, opponentId, isHost }
    nonceSeq = 0,
    arming = nil,         -- { map, x, y } while save.new_game reshapes the skeleton
    started = false,      -- have I dropped into the world yet this match
  }

  local function say(text) BRMenu.say(mod, text) end

  -- ------- relay address (a mod option, editable from the menu)

  function BR:relayAddress()
    return mod.options:get("relay") or DEFAULT_RELAY
  end

  function BR:setRelayAddress(addr)
    mod.save:set("relay", addr)   -- remembered per playthrough
    mod.options:define({          -- and live for this session
      { key = "relay", label = "RELAY", type = "text", default = addr },
    })
  end

  -- ------- identity + presence

  local function myName()
    local save = BR.game and BR.game.save
    return Wire.cleanName(save and save.player and save.player.name or "PLAYER")
  end

  local function mySprite()
    local field = BR.game and BR.game.data and BR.game.data.field
    return field and field.playerSprites and field.playerSprites.walk
  end

  local function here()
    return BR.game and mod.world:current()
  end

  local function broadcastPlace()
    if not (BR.relay and BR.relay:isOpen()) then return end
    local h = here()
    BR.relay:broadcast(Wire.place(h and h.mapId, h and h.x, h and h.y,
                                  h and h.facing, BR.status, mySprite()))
    if h then BR.sentMap, BR.sentFacing = h.mapId, h.facing end
  end

  -- ------- room lifecycle

  local function wireRelay(relay)
    relay:on("joined", function()
      BR.myId = relay.id
      BR.phase = "lobby"
    end)
    relay:on("roster", function(members)
      -- forget anyone who left; the host recounts survivors
      local present = {}
      for _, m in ipairs(members) do present[m.id] = true end
      for id in pairs(BR.players) do
        if not present[id] then
          -- if the one who left is who we are fighting, end the battle as a
          -- pulled cable rather than waiting on a move that never comes
          if BR.battle and BR.battle.opponentId == id then
            BR.battle.channel:peerGone()
          end
          BR.ghosts:despawn(id)
          BR.players[id] = nil
        end
      end
      if BR.phase == "match" then BR:checkWinner() end
    end)
    relay:on("message", function(fromId, m) BR:onMessage(fromId, m) end)
    relay:on("closed", function(reason)
      if reason then say(reason) end
      BR:reset()
    end)
  end

  function BR:host()
    self:reset()
    local relay = Relay.new({ address = self:relayAddress(), log = mod.log })
    wireRelay(relay)
    local ok, err = relay:host(myName())
    if not ok then return false, err end
    self.relay = relay
    return true
  end

  function BR:join(code)
    self:reset()
    local relay = Relay.new({ address = self:relayAddress(), log = mod.log })
    wireRelay(relay)
    local ok, err = relay:join(code, myName())
    if not ok then return false, err end
    self.relay = relay
    return true
  end

  -- Back to a clean slate without leaving the world (a closed relay, a
  -- cancelled lobby).  teardown() is the deliberate exit that also tells the
  -- relay goodbye.
  function BR:reset()
    self.ghosts:despawnAll()
    if self.battle then
      self.battle.channel:peerGone()
      self.battle = nil
    end
    self.relay = nil
    self.players = {}
    self.pending = nil
    self.phase = "off"
    self.status = "lobby"
    self.myId = nil
    self.started = false
  end

  function BR:teardown(message)
    if self.relay then self.relay:leave() end
    self:reset()
    if message then say(message) end
  end

  -- ------- starting a match
  --
  -- The host picks every drop point and sends them; nobody else has to agree
  -- on the algorithm, only on the answer.  Host and guests both apply the
  -- same `start` message through onStart.

  function BR:startMatch()
    local relay = self.relay
    if not (relay and relay:isHost()) then return end
    local ids = {}
    for _, m in ipairs(relay.members) do ids[#ids + 1] = m.id end
    table.sort(ids)
    local seed = love.math.random(1, 2 ^ 30)
    local rng = Spawn.rng(seed)
    local data = self.game.data
    local drops, err = Spawn.pick(data.maps, data.tilesets, #ids, rng)
    if not drops then
      say("Couldn't start:\n" .. tostring(err))
      return
    end
    local spawns = {}
    for i, id in ipairs(ids) do
      spawns[i] = { id = id, map = drops[i].map, x = drops[i].x, y = drops[i].y }
    end
    relay:lock(true)                       -- no late joiners mid-match
    relay:broadcast(Wire.start(seed, spawns))
    self:onStart({ seed = seed, spawns = spawns })
  end

  function BR:onStart(msg)
    -- find my drop
    local mine
    for _, s in ipairs(msg.spawns) do
      if s.id == self.myId then mine = s break end
    end
    if not mine then
      say("The match started\nwithout a spawn\nfor you.")
      return
    end
    -- seed the peers as alive-in-lobby until their first place message
    self.players = {}
    for _, s in ipairs(msg.spawns) do
      if s.id ~= self.myId then
        self.players[s.id] = { name = self.relay:nameOf(s.id), map = nil,
                               x = s.x, y = s.y, facing = "down",
                               status = "alive" }
      end
    end
    -- arm the loadout hook, then start a fresh game straight into the world
    self.arming = { map = mine.map, x = mine.x, y = mine.y }
    self.phase = "match"
    self.status = "alive"
    self.started = true
    self.game:startNewGame({ intro = false })
    self.arming = nil
    self.sentMap, self.sentFacing, self.resync = nil, nil, 0
    broadcastPlace()
  end

  -- the loadout, applied to the fresh skeleton (save.new_game).  Only when a
  -- match is arming; a normal New Game passes straight through.
  mod.hooks:wrap("save.new_game", function(next, save)
    save = next(save)
    if not BR.arming then return save end
    local Pokemon = require("src.pokemon.Pokemon")
    local Data = require("src.core.Data")
    save.party = { Pokemon.new(Data, START_SPECIES, START_LEVEL) }
    save.inventory = {}
    for id, n in pairs(START_ITEMS) do save.inventory[id] = n end
    save.bagOrder = nil            -- rebuilt from inventory on next open
    save.pcItems = {}
    save.money = START_MONEY
    save.flags = save.flags or {}
    for _, f in ipairs(STORY_FLAGS) do save.flags[f] = true end
    save.player.map = BR.arming.map
    save.player.x, save.player.y = BR.arming.x, BR.arming.y
    save.player.facing = "down"
    -- a whiteout should return here, not to a Pallet that never happened
    save.lastHeal = { map = BR.arming.map, x = BR.arming.x, y = BR.arming.y }
    save.lastOutdoor = { id = BR.arming.map, x = BR.arming.x, y = BR.arming.y }
    return save
  end)

  -- ------- inbound room messages

  function BR:onMessage(fromId, raw)
    local msg, why = Wire.decode(raw)
    if not msg then
      mod.log:warn("battle royale dropped a message: %s", tostring(why))
      return
    end
    local p = self.players[fromId]

    if msg.t == "place" then
      p = p or { name = self.relay:nameOf(fromId) }
      self.players[fromId] = p
      p.map, p.x, p.y, p.facing = msg.map, msg.x, msg.y, msg.facing
      p.sprite = msg.sprite or p.sprite
      p.status = msg.status
      if msg.status == "out" and self.phase == "match" then self:checkWinner() end

    elseif msg.t == "step" then
      if p then
        if msg.map then p.map = msg.map end
        p.x, p.y, p.facing = msg.x, msg.y, msg.dir
        self.ghosts:pushStep(fromId, msg.dir)
      end

    elseif msg.t == "face" then
      if p then
        p.facing = msg.facing
        self.ghosts:face(fromId, msg.facing)
      end

    elseif msg.t == "start" then
      -- only the host is a legitimate author; ignore a forged one
      if fromId == self.relay.hostId and not self.started then
        self:onStart(msg)
      end

    elseif msg.t == "challenge" then
      self:onChallenge(fromId, msg.nonce)

    elseif msg.t == "accept" then
      if self.pending and self.pending.to == fromId then
        local nonce = self.pending.nonce
        self.pending = nil
        self:beginBattle(fromId, Engage.isHost(self.myId, fromId), nonce)
      end

    elseif msg.t == "decline" then
      if self.pending and self.pending.to == fromId then
        self.pending = nil
        say("...They ran off.")
      end

    elseif msg.t == "bt" then
      if self.battle and self.battle.opponentId == fromId then
        self.battle.channel:push(msg.inner)
      end

    elseif msg.t == "out" then
      if p then p.status = "out" end
      if self.phase == "match" then self:checkWinner() end

    elseif msg.t == "winner" then
      if fromId == self.relay.hostId then self:onWinner(msg.id) end
    end
  end

  -- ------- forced battles
  --
  -- The challenge/accept exchange settles who fights whom; the battle itself
  -- rides a Channel handed to LinkState (LinkState.newFromSession), which
  -- owns every link mode the game has.  The lower room id hosts the lockstep
  -- so both machines start it the same way round.

  function BR:onChallenge(fromId, nonce)
    -- a challenge from the player we are already challenging is an accept
    if self.pending and self.pending.to == fromId then
      self.pending = nil
      self.relay:send(fromId, Wire.accept(nonce))
      self:beginBattle(fromId, Engage.isHost(self.myId, fromId), nonce)
      return
    end
    local decision = Engage.answer(
      { status = self.status, inBattle = self.battle ~= nil }, fromId, self.pending)
    if decision ~= "accept" then
      self.relay:send(fromId, Wire.decline(nonce, "busy"))
      return
    end
    self.relay:send(fromId, Wire.accept(nonce))
    self:beginBattle(fromId, Engage.isHost(self.myId, fromId), nonce)
  end

  function BR:tryEngage()
    if self.status ~= "alive" or self.battle or self.pending then return end
    local ow = mod.world:overworld()
    local player = ow and ow.player
    if not (player and ow.map) then return end
    if player.moving or player.inputLocked then return end
    local me = { id = self.myId, map = ow.map.id, x = player.cellX,
                 y = player.cellY, facing = player.facing,
                 moving = false, status = "alive", busy = false }
    local others = {}
    for id, p in pairs(self.players) do
      others[#others + 1] = { id = id, map = p.map, x = p.x, y = p.y,
                              facing = p.facing, moving = false,
                              status = p.status,
                              busy = p.status == "battle" }
    end
    local target = Engage.target(me, others)
    if target then
      self.nonceSeq = self.nonceSeq + 1
      self.pending = { to = target, nonce = self.nonceSeq,
                       host = Engage.isHost(self.myId, target) }
      self.relay:send(target, Wire.challenge(self.nonceSeq))
    end
  end

  function BR:beginBattle(opponentId, isHost, _nonce)
    if self.battle then return end
    local channel = Channel.new(self.relay, opponentId, {
      onClose = function() BR:onBattleClosed(opponentId) end,
    })
    self.battle = { channel = channel, opponentId = opponentId, isHost = isHost }
    self.status = "battle"
    self.pending = nil
    self.ghosts:despawnAll()             -- the world pauses under the battle
    broadcastPlace()                     -- tell everyone I am busy
    local LinkState = require("src.link.LinkState")
    self.game.stack:push(LinkState.newFromSession(self.game, channel,
                                                  "battle", isHost))
  end

  function BR:onBattleClosed(_opponentId)
    -- the channel closed (LinkState:exitWith); the result arrives separately
    -- on link.battle_ended, so here we only drop our handle
    if self.battle then self.battle = nil end
  end

  -- link.battle_ended carries the lockstep party copies, which took the
  -- damage the real save.party never does under cable rules.  Party is
  -- health here, so we copy the damage back and a wiped party is elimination.
  mod.events:on("link.battle_ended", function(ev)
    if not (BR.phase == "match" and BR.game) then return end
    local party = BR.game.save.party
    for i, mon in ipairs(party) do
      local after = ev.myParty and ev.myParty[i]
      if after and after.species == mon.species then
        mon.hp = math.max(0, math.min(mon.stats.hp, after.hp or mon.hp))
        mon.status = after.status
      end
    end
    if ev.result == "lose" then
      BR.status = "out"
      if BR.relay then BR.relay:broadcast(Wire.out()) end
      say("You whited out!\nYou are out of\nthe match.")
      BR:checkWinner()
    else
      BR.status = "alive"
    end
    broadcastPlace()
  end)

  -- ------- winner
  --
  -- The host is the authority: when one trainer is left un-eliminated it
  -- names them.  Everyone (host included) reacts to the winner message.

  function BR:aliveCount()
    local n = (self.status ~= "out") and 1 or 0
    for _, p in pairs(self.players) do
      if p.status ~= "out" then n = n + 1 end
    end
    return n
  end

  function BR:checkWinner()
    if not (self.relay and self.relay:isHost() and self.phase == "match") then return end
    -- survivors among everyone still in the room
    local survivors = {}
    if self.status ~= "out" then survivors[#survivors + 1] = self.myId end
    for id, p in pairs(self.players) do
      if p.status ~= "out" then survivors[#survivors + 1] = id end
    end
    if #survivors == 1 then
      self.relay:broadcast(Wire.winner(survivors[1]))
      self:onWinner(survivors[1])
    elseif #survivors == 0 then
      self.relay:broadcast(Wire.winner(nil))
      self:onWinner(nil)
    end
  end

  function BR:onWinner(id)
    if self.phase == "over" then return end
    self.phase = "over"
    self.ghosts:despawnAll()
    if id == self.myId then
      say("You are the last\ntrainer standing!\nYou win!")
    elseif id then
      say((self.relay:nameOf(id)) .. " wins\nthe match!")
    else
      say("The match is\nover.")
    end
  end

  -- ------- outbound: local movement -> wire
  --
  -- movement.speed fires inside Player:tryMove the moment a step commits,
  -- after targetX/targetY are set and before the walk animates -- the
  -- earliest honest point to tell everyone "I am stepping there".

  mod.hooks:wrap("movement.speed", function(next, frames, ctx)
    local player = ctx and ctx.player
    if player and player.targetX and BR.relay and BR.relay:isOpen()
       and BR.status ~= "battle" then
      local h = here()
      local map = h and h.mapId
      BR.relay:broadcast(Wire.step(player.facing, player.targetX,
                                   player.targetY, map))
      BR.sentFacing, BR.sentMap = player.facing, map
    end
    return next(frames, ctx)
  end)

  -- ------- the tick

  mod.hooks:wrap("input.step", function(next, game, dt)
    BR.game = game
    local relay = BR.relay
    if relay then
      relay:update()
      relay = BR.relay -- update() may have closed and reset it
    end

    if relay and relay:isOpen() and BR.phase == "match" then
      local h = here()
      if h then
        if BR.status ~= "battle" then
          if h.facing ~= BR.sentFacing then
            BR.sentFacing = h.facing
            relay:broadcast(Wire.face(h.facing, h.mapId))
          end
          if h.mapId ~= BR.sentMap then broadcastPlace() end
          BR.resync = BR.resync + 1
          if BR.resync >= RESYNC_TICKS then
            BR.resync = 0
            broadcastPlace()
          end
          BR.ghosts:sync(game, h.mapId, BR.players)
          BR:tryEngage()
        end
      end
    end
    return next(game, dt)
  end)

  -- Leaving a map takes our copy of every ghost with it: they are runtime
  -- objects on the map we left, and OverworldState rebuilds its NPC list on
  -- arrival.  sync() re-places them next tick.
  mod.events:on("map.entered", function()
    BR.ghosts:despawnAll()
    if BR.relay and BR.relay:isOpen() and BR.phase == "match" then broadcastPlace() end
  end)

  -- ------- talking to another trainer
  --
  -- A ghost is a runtime object with no TEXT_* id, so the vanilla talk path
  -- has nothing to say.  We answer instead -- but the battle is forced by
  -- walking into someone, so here A just names them (and, if we are already
  -- adjacent and facing, is a second way to start the fight).

  mod.hooks:wrap("world.talk", function(next, ow, npc)
    local id = BR.ghosts:ownerOf(npc)
    if not id then return next(ow, npc) end
    if not (BR.game and BR.relay and BR.relay:isOpen()) then return end
    npc:facePlayer(ow.player)
    -- talking counts as engaging if they are alive and we are
    if BR.status == "alive" and BR.players[id] and BR.players[id].status == "alive"
       and not BR.battle and not BR.pending then
      BR.nonceSeq = BR.nonceSeq + 1
      BR.pending = { to = id, nonce = BR.nonceSeq,
                     host = Engage.isHost(BR.myId, id) }
      BR.relay:send(id, Wire.challenge(BR.nonceSeq))
    end
  end)

  -- ------- reaching it from START

  mod.content.screens:register(SCREEN, BRMenu.build(mod, BR))

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    local label = (BR.phase == "match" or BR.phase == "over") and "ROYALE*"
      or (BR.relay and "ROYALE." or "ROYALE")
    return mod.ui.insertBefore(out, "OPTION", {
      label = label,
      onSelect = function() mod.ui.push(game, SCREEN) end,
    })
  end)

  -- Restore a remembered relay address on load.
  mod.events:on("save.created", function()
    local saved = mod.save:get("relay")
    if saved then BR:setRelayAddress(saved) end
  end)

  -- Other mods (and the tests) can ask what the match looks like.
  mod.exports.phase = function() return BR.phase end
  mod.exports.aliveCount = function() return BR:aliveCount() end
  mod.exports.status = function() return BR.status end

  -- The same verbs the menu speaks, exposed so a companion tool, another
  -- mod, or a POKEPORT_DRIVER script can run a match without simulating
  -- menu taps.  These are the menu's own code paths, nothing extra.
  mod.exports.host = function() return BR:host() end
  mod.exports.join = function(code) return BR:join(code) end
  mod.exports.start = function() return BR:startMatch() end
  mod.exports.leave = function() return BR:teardown() end
  mod.exports.setRelay = function(addr) return BR:setRelayAddress(addr) end
  mod.exports.code = function() return BR.relay and BR.relay.code end
  mod.exports.lastError = function() return BR.relay and BR.relay.error end
  mod.exports.memberCount = function()
    return BR.relay and #BR.relay.members or 0
  end
  mod.exports.players = function()
    local out = {}
    for id, p in pairs(BR.players) do
      out[#out + 1] = { id = id, name = p.name, map = p.map, x = p.x, y = p.y,
                        status = p.status }
    end
    return out
  end
end
