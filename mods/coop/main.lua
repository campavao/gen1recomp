-- Kanto Co-op: two trainers walking the same Kanto.
--
-- Shape of the thing:
--   lib/wire.lua     the message vocabulary (pure, headless-testable)
--   lib/session.lua  one connection, over src/link/Net.lua
--   lib/ghosts.lua   the peer as a real overworld NPC
--   lib/menu.lua     the CO-OP start-menu screen
--   this file        the wiring, and the local -> wire direction
--
-- Two directions to keep straight.  Outbound: the local player's steps and
-- turns become messages, driven off the movement.speed hook (which fires
-- exactly when a step commits) and a per-tick facing check.  Inbound: the
-- session's callbacks feed lib/ghosts, which drives a runtime NPC.
--
-- Everything runs on the engine's 60 Hz fixed step via the input.step hook,
-- so there is no thread and no lock anywhere in here.

local Session = require("mods.coop.lib.session")
local Ghosts = require("mods.coop.lib.ghosts")
local Wire = require("mods.coop.lib.wire")
local CoopMenu = require("mods.coop.lib.menu")

local SCREEN = "CoopMenu"
local OFFER_SCREEN = "CoopOffer"

-- Full position resync cadence.  Steps and turns already keep the ghost
-- honest; this is insurance against a message the transport dropped on a
-- lossy channel, and against the peer moving in a way we do not model
-- (a Fly, a Dig, a scripted escort).
local RESYNC_TICKS = 300  -- 5 seconds at 60 Hz

return function(mod)
  mod.options:define({
    { key = "solid", label = "SOLID PEER", type = "toggle", default = true },
    { key = "announce", label = "ANNOUNCE JOIN", type = "toggle", default = true },
  })

  local Coop = {
    session = nil,
    ghosts = Ghosts.new(mod, mod.options:get("solid")),
    game = nil,
    sentFacing = nil,
    sentMap = nil,
    resync = 0,
    pendingInvite = nil,   -- a kind we offered and are waiting on
  }

  local function say(text) CoopMenu.say(mod, text) end

  -- ------- what we tell the other end about ourselves

  local function identity()
    local game = Coop.game
    local here = mod.world:current() or {}
    local save = game and game.save
    local player = save and save.player
    local field = game and game.data and game.data.field
    return {
      name = Wire.cleanName(player and player.name or "PLAYER"),
      sprite = field and field.playerSprites and field.playerSprites.walk,
      map = here.mapId, x = here.x, y = here.y, facing = here.facing,
    }
  end

  local function sendPlace()
    if not Coop:isConnected() then return end
    local me = identity()
    if not me.map then return end
    Coop.session:send(Wire.place(me.map, me.x, me.y, me.facing))
    Coop.sentMap, Coop.sentFacing = me.map, me.facing
  end

  -- ------- session lifecycle

  function Coop:isConnected()
    return self.session ~= nil and self.session:isConnected()
  end

  function Coop:isPending()
    local s = self.session
    return s ~= nil and (s.status == "hosting" or s.status == "joining")
  end

  local function wireHandlers(session)
    session:on("hello", function(peer)
      if mod.options:get("announce") then
        say(("%s joined your\ngame!"):format(peer.name or "PLAYER"))
      end
      -- tell them exactly where we are the moment they exist to us
      sendPlace()
    end)

    session:on("step", function(msg)
      Coop.ghosts:pushStep(msg.dir)
    end)

    session:on("face", function(msg)
      Coop.ghosts:face(msg.facing)
    end)

    session:on("place", function()
      local here = mod.world:current()
      Coop.ghosts:place(Coop.game, here and here.mapId, session.peer)
    end)

    session:on("invite", function(kind)
      Coop:receiveInvite(kind)
    end)

    session:on("reply", function(kind, ok)
      if not Coop.pendingInvite then return end
      Coop.pendingInvite = nil
      if ok then
        Coop:handoff(kind, true)
      else
        say("...They said no.")
      end
    end)

    session:on("gone", function(reason)
      Coop.ghosts:despawn()
      Coop.session = nil
      Coop.pendingInvite = nil
      if reason then say(reason) end
    end)
  end

  function Coop:host(online)
    self:stop()
    local session = Session.new({ identity = identity, log = mod.log })
    wireHandlers(session)
    local ok, err = session:host(online)
    if not ok then return false, err end
    self.session = session
    return true
  end

  function Coop:join(target, online)
    self:stop()
    local session = Session.new({ identity = identity, log = mod.log })
    wireHandlers(session)
    local ok, err = session:join(target, online)
    if not ok then return false, err end
    self.session = session
    return true
  end

  function Coop:stop(message)
    self.ghosts:despawn()
    if self.session then self.session:leave() end
    self.session = nil
    self.pendingInvite = nil
    if message then say(message) end
  end

  -- ------- battle / trade
  --
  -- The invite travels on the co-op wire; the battle itself does not.  Once
  -- both sides agree we hand the live, already-paired socket to LinkState
  -- (LinkState.newFromSession), which owns every link mode the game has --
  -- reimplementing a lockstep battle here would be a second, worse copy.
  --
  -- The socket goes with it: LinkState:exitWith closes the net when the
  -- battle or trade ends, so co-op ends too and you reconnect to keep
  -- walking together.  Sharing one socket between two state machines is the
  -- alternative and it is not worth the desync surface.

  function Coop:sendInvite(kind)
    if not self:isConnected() then return end
    self.pendingInvite = kind
    self.session:send(Wire.invite(kind))
    say("Waiting for the\nother player...")
  end

  function Coop:receiveInvite(kind)
    local session = self.session
    if not session then return end
    local name = (session.peer and session.peer.name) or "PLAYER"
    local game = self.game
    if not game then return end
    -- ListMenu rather than Menu: it takes a title, and the title is the
    -- whole point here -- "who is asking, and for what".
    game.stack:push(mod.ui.ListMenu.new(game,
      ("%s WANTS TO %s"):format(name, kind:upper()),
      { { label = "OK", value = true }, { label = "NO", value = false } },
      {
        onChoose = function(item, menu)
          menu:close()
          session:send(Wire.reply(kind, item.value))
          if item.value then Coop:handoff(kind, false) end
        end,
        onCancel = function()
          session:send(Wire.reply(kind, false))
        end,
      }))
  end

  -- isHost decides which side deals the shared battle RNG seed.  The player
  -- who opened the co-op session is the host, which both ends already agree
  -- on: the inviter is whoever pressed A, so we pass it explicitly.
  function Coop:handoff(kind, isHost)
    local session, game = self.session, self.game
    if not (session and game and session.net) then return end
    local net = session.net
    -- drop our claim on the socket before LinkState takes over, so the
    -- co-op pump stops touching a transport it no longer owns
    session.net = nil
    session.status = "closed"
    self.session = nil
    self.ghosts:despawn()
    local LinkState = require("src.link.LinkState")
    game.stack:push(LinkState.newFromSession(game, net, kind, isHost))
  end

  -- ------- outbound: local movement -> wire
  --
  -- movement.speed fires inside Player:tryMove at the moment a step commits,
  -- after targetX/targetY are set and before the walk animates.  That makes
  -- it the earliest honest point to tell the peer "I am stepping there",
  -- and it costs the peer no extra latency waiting for the step to land.

  mod.hooks:wrap("movement.speed", function(next, frames, ctx)
    local player = ctx and ctx.player
    if player and player.targetX and Coop:isConnected() then
      local here = mod.world:current()
      local map = here and here.mapId
      Coop.session:send(Wire.step(player.facing, player.targetX, player.targetY, map))
      Coop.sentFacing, Coop.sentMap = player.facing, map
    end
    return next(frames, ctx)
  end)

  -- ------- the tick

  mod.hooks:wrap("input.step", function(next, game, dt)
    Coop.game = game
    local session = Coop.session
    if session then
      session:update(dt)

      if session:isConnected() then
        local here = mod.world:current()
        if here then
          -- a turn in place never reaches movement.speed
          if here.facing ~= Coop.sentFacing then
            Coop.sentFacing = here.facing
            session:send(Wire.face(here.facing, here.mapId))
          end
          -- changing map is a hard cut for the peer's ghost
          if here.mapId ~= Coop.sentMap then
            sendPlace()
          end
          Coop.resync = Coop.resync + 1
          if Coop.resync >= RESYNC_TICKS then
            Coop.resync = 0
            sendPlace()
          end
          Coop.ghosts:sync(game, here.mapId, session.peer)
        end
      end
    end
    return next(game, dt)
  end)

  -- Leaving a map takes our copy of the peer with it: the ghost is a runtime
  -- object on the map we are leaving, and OverworldState rebuilds its NPC
  -- list on arrival.  sync() re-places it on the next tick if the peer is
  -- on the new map too.
  -- toggling SOLID PEER takes effect on the live body, not just the next one
  mod.events:on("mod.options_changed", function()
    Coop.ghosts.solid = mod.options:get("solid") ~= false
    local handle = Coop.ghosts:handle()
    if handle then handle:setPassable(not Coop.ghosts.solid) end
  end)

  mod.events:on("map.entered", function()
    Coop.ghosts:despawn()
    if Coop:isConnected() then sendPlace() end
  end)

  -- ------- talking to the other player
  --
  -- Our ghost is a runtime object with no TEXT_* id, so the vanilla talk
  -- path has nothing to say for it.  world.talk lets us answer instead --
  -- not calling next() is what claims the A press.

  mod.hooks:wrap("world.talk", function(next, ow, npc)
    if not Coop.ghosts:owns(npc) then return next(ow, npc) end
    local game = Coop.game
    if not (game and Coop:isConnected()) then return end
    npc:facePlayer(ow.player)
    local name = (Coop.session.peer and Coop.session.peer.name) or "PLAYER"
    game.stack:push(mod.ui.ListMenu.new(game, name, {
      { label = "BATTLE", value = "battle" },
      { label = "TRADE", value = "trade" },
      { label = "NOTHING", value = nil },
    }, {
      onChoose = function(item, menu)
        menu:close()
        if item.value then Coop:sendInvite(item.value) end
      end,
    }))
  end)

  -- ------- reaching it from START

  mod.content.screens:register(SCREEN, CoopMenu.build(mod, Coop))

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    local label = Coop:isConnected() and "CO-OP*" or "CO-OP"
    return mod.ui.insertBefore(out, "OPTION", {
      label = label,
      onSelect = function() mod.ui.push(game, SCREEN) end,
    })
  end)

  -- Other mods can ask whether co-op is live and who is on the other end,
  -- which is the supported way to depend on this without poking at locals.
  mod.exports.isConnected = function() return Coop:isConnected() end
  mod.exports.peer = function()
    local s = Coop.session
    if not (s and s.peer) then return nil end
    return { name = s.peer.name, map = s.peer.map,
             x = s.peer.x, y = s.peer.y, rtt = s.rtt }
  end
end
