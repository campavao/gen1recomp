-- The CO-OP screen, reached from the start menu.
--
-- Deliberately thin: it starts and stops sessions and reports what the
-- session already knows.  Everything that happens once you are connected
-- happens in the overworld, not in here, so this screen is never the place
-- you sit and wait -- pick HOST, close the menu, keep walking.

local Entry = require("mods.coop.lib.entry")

local Menu = {}

-- Seed for the address entry: this machine's own LAN address is almost
-- always the friend's address give or take the last octet.  Net.lanIP picks
-- the outbound interface without sending a packet; nil off a network.
local function lanGuess()
  local ok, Net = pcall(require, "src.link.Net")
  if not ok or not Net or not Net.lanIP then return nil end
  local okip, ip = pcall(Net.lanIP)
  return okip and ip or nil
end

local function say(mod, text)
  -- The script runner owns the dialogue box, so status lands in a real
  -- Gen 1 text box instead of a bespoke overlay.  Refused while another
  -- script is running, which is correct: never interrupt a cutscene to
  -- announce a connection.
  mod.world:queueScript({ { "show_text", text } })
end

Menu.say = say

function Menu.build(mod, coop)
  return {
    new = function(game)
      local items = {}
      local session = coop.session

      -- Menu pops itself before onSelect runs (src/ui/Menu.lua), so nothing
      -- below closes anything by hand, and onSelect takes no arguments.
      if coop:isConnected() then
        local peer = session.peer or {}
        local ping = session.rtt
          and (" %dMS"):format(math.floor(session.rtt * 1000)) or ""
        items[#items + 1] = {
          label = ("WITH %s%s"):format(peer.name or "PLAYER", ping),
          keepOpen = true,        -- a status row, not an action
          onSelect = function() end,
        }
        items[#items + 1] = {
          label = "DISCONNECT",
          onSelect = function() coop:stop("You left the game.") end,
        }
      elseif coop:isPending() then
        local invite = session and session:invitation()
        items[#items + 1] = {
          label = invite and ("CODE %s"):format(invite) or "CONNECTING...",
          keepOpen = true,
          onSelect = function() end,
        }
        items[#items + 1] = {
          label = "CANCEL",
          onSelect = function() coop:stop() end,
        }
      else
        items[#items + 1] = {
          label = "HOST ONLINE",
          onSelect = function()
            local ok, err = coop:host(true)
            if not ok then say(mod, err or "Couldn't host.") end
          end,
        }
        items[#items + 1] = {
          label = "HOST ON LAN",
          onSelect = function()
            local ok, err = coop:host(false)
            if not ok then say(mod, err or "Couldn't host.") end
          end,
        }
        -- Entry, not NamingScreen: the Gen 1 naming grid has no digits, so
        -- neither a room code (Crockford-32) nor an address can be typed
        -- there at all.  See mods/coop/lib/entry.lua.
        items[#items + 1] = {
          label = "JOIN BY CODE",
          onSelect = function()
            game.stack:push(Entry.new(game, {
              title = "ENTER CODE",
              shape = Entry.CODE,
              onDone = function(code)
                if not code or code == "" then return end
                local ok, err = coop:join(code, true)
                if not ok then say(mod, err or "Couldn't join.") end
              end,
            }))
          end,
        }
        items[#items + 1] = {
          label = "JOIN BY IP",
          onSelect = function()
            game.stack:push(Entry.new(game, {
              title = "HOST ADDRESS",
              shape = Entry.ADDRESS,
              -- prefilled with this machine's LAN address, so joining a
              -- friend on the same network is usually a last-octet scrub
              default = mod.save:get("lastAddress") or lanGuess(),
              onDone = function(addr)
                if not addr or addr == "" then return end
                mod.save:set("lastAddress", addr)
                local ok, err = coop:join(addr, false)
                if not ok then say(mod, err or "Couldn't join.") end
              end,
            }))
          end,
        }
        -- Two copies on one PC (the usual way to try co-op before roping in
        -- a friend): the host binds 7777 and the joiner is a plain ENet
        -- client on an ephemeral port, so nothing collides.
        items[#items + 1] = {
          label = "JOIN THIS PC",
          onSelect = function()
            local ok, err = coop:join("127.0.0.1", false)
            if not ok then say(mod, err or "Couldn't join.") end
          end,
        }
      end

      return mod.ui.Menu.new(game, items, { startCloses = true })
    end,
  }
end

return Menu
