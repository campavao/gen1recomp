-- The other trainer, as something Kanto can actually contain.
--
-- A remote player is a runtime object (mod.world:spawnNpc) that we drive
-- ourselves.  Making it a real NPC rather than a sprite we blit is what buys
-- the whole feature for free: the tile renderer already sorts it against the
-- map, Collision already treats it as solid so you cannot walk through your
-- friend, and OverworldState:interact already finds it when you press A.
--
-- What we do NOT use is Handle:scriptMove.  That queues onto
-- OverworldState.scriptMoves, which the overworld reads as "a cutscene is
-- running" and uses to gate handleInput -- so every step the other player
-- took would freeze your controls for 16 frames.  Handle:stepNow drives the
-- same per-tile state without the queue.  See src/world/WorldAPI.lua.
--
-- Replay, not simulation: the peer already decided (and collision-checked)
-- each step on their own machine.  We repeat it verbatim and let the cell
-- coordinates in the message correct any drift.

local Ghosts = {}
Ghosts.__index = Ghosts

-- How many un-replayed steps we will walk out before giving up and snapping.
-- Each step costs 16 frames; letting a backlog drain at walking pace would
-- put the ghost visibly behind where the peer says it is, so past this we
-- teleport to the truth instead of politely queueing.
local MAX_BACKLOG = 3

local FACING_TO_RANGE = { down = "DOWN", up = "UP", left = "LEFT", right = "RIGHT" }
local DEFAULT_SPRITE = "SPRITE_RED"

-- solid: false lets the local player walk through the peer.  Worth having
-- as a choice rather than a constant -- a peer standing in a doorway with
-- solid on can wall you into a building until they move.
function Ghosts.new(mod, solid)
  return setmetatable({
    mod = mod,
    npcId = nil,      -- id returned by spawnNpc, nil when not spawned
    mapId = nil,      -- map the ghost is currently spawned on
    queue = {},       -- directions waiting to be walked
    solid = solid ~= false,
    name = "PLAYER",
    sprite = DEFAULT_SPRITE,
  }, Ghosts)
end

-- The sprite sheet the peer advertised, if this build actually has it.
-- A peer with a sprite mod we do not have must not crash NPC.new (which
-- asserts on an unknown sheet), so an unrecognised id falls back.
function Ghosts:resolveSprite(game, wanted)
  local sprites = game and game.data and game.data.sprites
  if not sprites then return DEFAULT_SPRITE end
  if wanted and sprites[wanted] then return wanted end
  local field = game.data.field
  local walk = field and field.playerSprites and field.playerSprites.walk
  if walk and sprites[walk] then return walk end
  if sprites[DEFAULT_SPRITE] then return DEFAULT_SPRITE end
  return next(sprites)
end

function Ghosts:handle()
  if not self.npcId or not self.mapId then return nil end
  return (self.mod.world:npc(self.mapId, self.npcId))
end

-- Is this the NPC we spawned?  The world.talk hook asks before deciding
-- whether the A press is ours to answer.
function Ghosts:owns(npc)
  return self.npcId ~= nil and npc ~= nil and npc.id == self.npcId
end

function Ghosts:isSpawned() return self.npcId ~= nil end

-- ------- lifecycle

function Ghosts:spawn(game, mapId, x, y, facing, peerSprite)
  self:despawn()
  local sprite = self:resolveSprite(game, peerSprite)
  local id, err = self.mod.world:spawnNpc(mapId, {
    name = "COOP_PEER",
    sprite = sprite,
    x = x, y = y,
    movement = "STAY",                                  -- never wanders
    range = FACING_TO_RANGE[facing] or "DOWN",
  })
  if not id then
    self.mod.log:warn("couldn't place the other player: %s", tostring(err))
    return false
  end
  self.npcId, self.mapId, self.sprite = id, mapId, sprite
  self.queue = {}
  local handle = self:handle()
  if handle then handle:setPassable(not self.solid) end
  return true
end

function Ghosts:despawn()
  if not self.npcId then return end
  -- Runtime objects live in the shared map def until removed, so a missed
  -- despawn would leave a frozen double of the other player standing in the
  -- world for the rest of the session.
  local ok, err = self.mod.world:removeNpc(self.npcId)
  if not ok and err then self.mod.log:warn("couldn't remove ghost: %s", tostring(err)) end
  self.npcId, self.mapId = nil, nil
  self.queue = {}
end

-- ------- driving
--
-- Reconcile "where the peer says they are" against "where the ghost is".
-- Called every tick: it owns spawning on arrival, despawning on departure,
-- and draining the step queue at walking pace.

function Ghosts:sync(game, myMapId, peer)
  if not peer or not myMapId then self:despawn() return end

  -- different map (or no map yet) -> no ghost here
  if peer.map ~= myMapId then self:despawn() return end

  if not self.npcId or self.mapId ~= myMapId then
    self:spawn(game, myMapId, peer.x, peer.y, peer.facing, peer.sprite)
    return
  end

  local handle = self:handle()
  if not handle then
    -- The map reloaded under us (a warp, a block swap) and took the pooled
    -- NPC with it; forget the stale id and let the next tick respawn.
    self.npcId, self.mapId = nil, nil
    return
  end

  if handle:isMoving() then return end

  if #self.queue > MAX_BACKLOG then
    -- too far behind to walk it off: snap to the truth
    self.queue = {}
    handle:placeAt(peer.x, peer.y, peer.facing)
    return
  end

  local dir = table.remove(self.queue, 1)
  if dir then
    handle:stepNow(dir)
    return
  end

  -- Idle: nothing queued, so correct any residual disagreement quietly.
  local cx, cy = handle:position()
  if cx ~= peer.x or cy ~= peer.y then
    handle:placeAt(peer.x, peer.y, peer.facing)
  else
    handle:face(peer.facing)
  end
end

-- A step the peer committed.  Queued rather than applied now: the ghost may
-- still be walking off the previous one, and steps must not overlap.
function Ghosts:pushStep(dir)
  self.queue[#self.queue + 1] = dir
end

function Ghosts:face(facing)
  local handle = self:handle()
  if handle and not handle:isMoving() then handle:face(facing) end
end

-- A warp, a Fly, a resync: no walk animation, just be there.
function Ghosts:place(game, myMapId, peer)
  self.queue = {}
  if peer.map ~= myMapId then self:despawn() return end
  local handle = self:handle()
  if handle then
    handle:placeAt(peer.x, peer.y, peer.facing)
  else
    self:spawn(game, myMapId, peer.x, peer.y, peer.facing, peer.sprite)
  end
end

return Ghosts
