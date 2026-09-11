-- A placeholder map for testing Kanto BR in isolation.
--
-- BR_ARENA is a 12x10-block room (24x20 cells) on the imported OVERWORLD
-- tileset: a tree ring around an empty floor, one signpost, one stationary
-- NPC, and a warp home to Pallet.  Nothing in it is randomised, so a driver
-- that wants a bot at a known distance, a spill on a known cell, or a fight
-- with a known NPC can stage it here instead of fighting real Kanto for a
-- flat spot.
--
-- `outdoor = false` is the important key.  The tileset is still OVERWORLD
-- (so the art needs no new sheet), but Map.isOutdoor reads the explicit
-- flag first, which keeps the arena out of Spawn.outdoorMaps -- otherwise
-- every real match would be able to drop players here.
--
-- This mod lives only in a dev checkout.  mods/battle_royale is what the
-- release sync copies, so nothing here can reach a player.

local ARENA = "BR_ARENA"
local W, H = 12, 10          -- blocks; cells are 2x that, so 24x20
local FLOOR, TREE = 11, 67   -- plain grass, and the OVERWORLD tree

return function(mod)
  local blocks = {}
  for by = 0, H - 1 do
    for bx = 0, W - 1 do
      local edge = bx == 0 or bx == W - 1 or by == 0 or by == H - 1
      blocks[by * W + bx + 1] = edge and TREE or FLOOR
    end
  end

  mod.content.text:register("_BrArenaSign", "BR SANDBOX")
  mod.content.text:register("_BrArenaDummy", "I DO NOT MOVE.")
  mod.content.text:register("_BrArenaNurse", "I HEAL.")

  mod.content.maps:register(ARENA, {
    id = ARENA,
    label = "BrArena",
    index = 1000,
    tileset = "OVERWORLD",
    -- keeps the arena out of the drop pool and off the town map
    outdoor = false,
    width = W, height = H,
    blocks = blocks,
    borderBlock = TREE,
    -- bottom-centre, on the tree ring, so walking south leaves the arena
    warps = { { x = 12, y = 19, destMap = "PALLET_TOWN", destWarp = 1 } },
    objects = {
      { index = 1, name = "BRARENA_DUMMY", sprite = "SPRITE_FISHER",
        movement = "STAY", range = "NONE", x = 16, y = 10,
        text = "TEXT_BRARENA_DUMMY" },
      -- A nurse with no counter: the `nurse` flag on her text entry is
      -- all the engine (OverworldController, "marts / nurses / PCs via
      -- TX_SCRIPT markers") and the mod (its world.talk wrap) read, so
      -- the Centre's flow can be driven here without a Centre.
      { index = 2, name = "BRARENA_NURSE", sprite = "SPRITE_NURSE",
        movement = "STAY", range = "NONE", x = 8, y = 6,
        text = "TEXT_BRARENA_NURSE" },
    },
    signs = { { index = 1, x = 12, y = 4, text = "TEXT_BRARENA_SIGN" } },
  })

  mod.content.text_pointers:patch("BrArena", {
    TEXT_BRARENA_SIGN = { text = "_BrArenaSign" },
    TEXT_BRARENA_DUMMY = { text = "_BrArenaDummy" },
    TEXT_BRARENA_NURSE = { text = "_BrArenaNurse", nurse = true },
  })

  mod.log:info("BR_ARENA registered (" .. (W * 2) .. "x" .. (H * 2) .. " cells)")
end
