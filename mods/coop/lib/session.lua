-- The co-op session: one connection, one peer, a message pump.
--
-- Owns a src/link/Net.lua transport and nothing else.  Net already gives us
-- both backends -- direct ENet over UDP, and the relay with a six-character
-- room code that works through NAT -- behind one API, so this module never
-- learns which is in play.  That is also why co-op can exist as a mod at
-- all: the wire is a solved problem here, and `network` is a declared
-- permission (see manifest.json) precisely for reaching src.link.
--
-- The session is deliberately transport-injectable: pass opts.transport and
-- it never requires Net at all, which is how tests/coop_test.lua drives two
-- live sessions against Net.loopbackPair() under plain luajit.
--
-- Threading model: none.  update() is called from the engine's 60 Hz fixed
-- step (the input.step hook), so every callback below runs on the game
-- thread and may touch the world directly.

local Wire = require("mods.coop.lib.wire")

local Session = {}
Session.__index = Session

-- Keepalive: a ping every PING_EVERY seconds, and a peer that has said
-- nothing at all for SILENT_FOR is treated as gone.  ENet notices a dropped
-- UDP peer on its own, but a wedged relay socket can stay "open" forever,
-- so the timeout is ours rather than the transport's.
local PING_EVERY = 2.0
local SILENT_FOR = 10.0

local function now()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  local ok, socket = pcall(require, "socket")
  if ok and socket and socket.gettime then return socket.gettime() end
  return os.clock()
end

-- opts.identity  -> function returning { name, sprite, map, x, y, facing }
-- opts.transport -> a preconstructed Net-alike (tests); otherwise made here
-- opts.log       -> mod.log
function Session.new(opts)
  opts = opts or {}
  local self = setmetatable({
    net = opts.transport,
    identity = opts.identity or function() return {} end,
    log = opts.log,
    status = "idle",       -- idle | hosting | joining | connected | closed
    peer = nil,            -- populated on hello
    error = nil,
    sentHello = false,
    lastHeard = 0,
    lastPing = 0,
    pingSeq = 0,
    rtt = nil,
    handlers = {},
  }, Session)
  return self
end

-- on("step", fn) etc.  One handler per event; the mod is the only caller
-- and a second registration is a bug worth surfacing loudly.
function Session:on(event, fn)
  assert(self.handlers[event] == nil, "duplicate co-op handler: " .. event)
  self.handlers[event] = fn
  return self
end

function Session:_fire(event, ...)
  local fn = self.handlers[event]
  if not fn then return end
  local ok, err = pcall(fn, ...)
  if not ok and self.log then
    self.log:warn("co-op handler %s failed: %s", event, tostring(err))
  end
end

local function newNet()
  local ok, Net = pcall(require, "src.link.Net")
  if not ok or not Net then return nil, "link transport unavailable" end
  if Net.available and not Net.available() then
    return nil, "co-op needs lua-enet\n(run the game with LOVE)"
  end
  return Net.new()
end

-- ------- opening a session
--
-- Both openers are fire-and-forget: they put the transport in motion and
-- return.  Pairing, hello exchange and failure all land in update().

function Session:host(online)
  local net, err = self.net, nil
  if not net then net, err = newNet() end
  if not net then self.error = err; self.status = "closed"; return false, err end
  self.net = net
  local ok
  if online then ok = net:hostOnline() else ok = net:host() end
  -- Net:host returns nothing on the ENet path and sets .error on failure
  if net.error then
    self.error = net.error; self.status = "closed"; return false, net.error
  end
  if online and ok == false then
    self.error = net.error or "couldn't reach the relay"
    self.status = "closed"
    return false, self.error
  end
  self.status = "hosting"
  self.lastHeard = now()
  return true
end

function Session:join(target, online)
  local net, err = self.net, nil
  if not net then net, err = newNet() end
  if not net then self.error = err; self.status = "closed"; return false, err end
  self.net = net
  if online then net:joinOnline(nil, target) else net:join(target) end
  if net.error then
    self.error = net.error; self.status = "closed"; return false, net.error
  end
  self.status = "joining"
  self.lastHeard = now()
  return true
end

-- The address or room code to read out to the other player, whichever
-- backend is running.  nil until the relay answers with a code.
function Session:invitation()
  local net = self.net
  if not net then return nil end
  return net.code or net.address
end

function Session:isConnected() return self.status == "connected" end

function Session:send(msg)
  if not self.net or self.net.closed then return false end
  self.net:send(msg)
  return true
end

-- ------- the pump

function Session:update(dt)
  local net = self.net
  if not net or self.status == "closed" or self.status == "idle" then return end

  local ok, err = pcall(net.update, net)
  if not ok then
    self:_close("transport error: " .. tostring(err))
    return
  end

  if net.error and not self.error then self.error = net.error end
  if net.closed then
    self:_close(self.error or "the other player disconnected")
    return
  end

  -- Pairing is the transport's word that a peer exists; hello is ours.
  -- Sending it exactly once, on the first paired frame, means both ends
  -- exchange identity without either needing to know who dialed whom.
  if net.paired and not self.sentHello then
    self.sentHello = true
    local me = self.identity() or {}
    self:send(Wire.hello({
      name = me.name, sprite = me.sprite,
      map = me.map, x = me.x, y = me.y, facing = me.facing,
    }))
  end

  local pollOk, msgs = pcall(net.poll, net)
  if not pollOk then
    self:_close("transport error: " .. tostring(msgs))
    return
  end
  for _, raw in ipairs(msgs or {}) do
    self:_receive(raw)
  end

  if self.status == "connected" then
    local t = now()
    if t - self.lastPing >= PING_EVERY then
      self.lastPing = t
      self.pingSeq = self.pingSeq + 1
      self.pingSentAt = t
      self:send(Wire.ping(self.pingSeq))
    end
    if t - self.lastHeard >= SILENT_FOR then
      self:_close("lost contact with\nthe other player")
    end
  end
end

function Session:_receive(raw)
  local msg, why = Wire.decode(raw)
  if not msg then
    if self.log then self.log:warn("co-op dropped a message: %s", tostring(why)) end
    -- A protocol mismatch is not a transient glitch: the peer is running a
    -- different co-op build and nothing it sends will parse.  Say so once
    -- and close, rather than sitting in a silent half-session.
    if raw and raw.t == "hello" then
      self:send(Wire.bye("protocol"))
      self:_close("that player is running\na different co-op version")
    end
    return
  end

  self.lastHeard = now()

  if msg.t == "hello" then
    self.peer = {
      name = msg.name, sprite = msg.sprite,
      map = msg.map, x = msg.x, y = msg.y, facing = msg.facing,
    }
    self.status = "connected"
    self:_fire("hello", self.peer)
  elseif msg.t == "step" then
    if self.peer then
      if msg.map then self.peer.map = msg.map end
      self.peer.x, self.peer.y, self.peer.facing = msg.x, msg.y, msg.dir
      self:_fire("step", msg)
    end
  elseif msg.t == "face" then
    if self.peer then
      self.peer.facing = msg.facing
      self:_fire("face", msg)
    end
  elseif msg.t == "place" then
    if self.peer then
      self.peer.map, self.peer.x, self.peer.y, self.peer.facing =
        msg.map, msg.x, msg.y, msg.facing
      self:_fire("place", msg)
    end
  elseif msg.t == "invite" then
    self:_fire("invite", msg.kind)
  elseif msg.t == "reply" then
    self:_fire("reply", msg.kind, msg.ok)
  elseif msg.t == "ping" then
    self:send(Wire.pong(msg.seq))
  elseif msg.t == "pong" then
    if msg.seq == self.pingSeq and self.pingSentAt then
      self.rtt = now() - self.pingSentAt
    end
  elseif msg.t == "bye" then
    self:_close(msg.why == "protocol"
      and "that player is running\na different co-op version"
      or "the other player left")
  end
end

function Session:_close(reason)
  if self.status == "closed" then return end
  self.status = "closed"
  self.error = self.error or reason
  self:_fire("gone", self.error)
end

-- Leaving on purpose: tell the peer first so their ghost vanishes cleanly
-- instead of waiting out SILENT_FOR.
function Session:leave()
  if self.net and not self.net.closed then
    pcall(function() self:send(Wire.bye("left")) end)
    pcall(self.net.update, self.net)   -- flush the relay's write buffer
    pcall(self.net.close, self.net)
  end
  self.status = "closed"
  self:_fire("gone", nil)
end

return Session
