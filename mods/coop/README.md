# Kanto Co-op

Two trainers, one Kanto. Connect to a friend, see them walking the same
maps you are, and walk up and press A to battle or trade.

Each player keeps their own camera, their own party and their own save.
You see the other player in the world as a real overworld character — they
are solid, they animate, and they are standing where they say they are.

## Using it

Both players need this mod enabled and the same game version.

1. `START` → `CO-OP`
2. One player picks **HOST ONLINE** and reads out the six-character room
   code (or **HOST ON LAN** and reads out the address).
3. The other picks **JOIN BY CODE** (or **JOIN BY IP**) and enters it.

The menu closes and you keep playing — co-op runs in the background. Reopen
`CO-OP` any time to see who you are connected to, the round-trip time, and
`DISCONNECT`. The start-menu row reads `CO-OP*` while a session is live.

Walk up to the other player, face them, and press `A` to offer a **BATTLE**
or a **TRADE**.

### Options

| Option | Default | Effect |
| --- | --- | --- |
| `SOLID PEER` | on | the other player blocks your movement |
| `ANNOUNCE JOIN` | on | a text box when they connect |

## How it works

**Transport.** The engine already ships one: `src/link/Net.lua` gives both
a direct ENet/UDP backend and a relay backend with room codes that works
through NAT, behind a single `host/join/send/poll` API. Co-op uses it
as-is, which is why `network` is the one permission this mod declares.

**Movement.** Kanto movement is a grid: one tile per step, sixteen frames
at one pixel per frame. That means co-op does not have to stream positions
— it sends one small message per step (about four a second) and the other
machine replays the same deterministic step. The cell coordinates ride
along in every message, so drift corrects itself rather than accumulating.

**The other player.** They are a runtime object (`mod.world:spawnNpc`), not
a sprite drawn over the world. That way the tile renderer sorts them
correctly, collision treats them as solid, and `A` finds them — all of it
the engine's own code rather than a reimplementation.

**Battles and trades.** The invite travels on the co-op wire; the battle
does not. Once both sides agree, the live socket is handed to `LinkState`,
which already owns every link mode the game has. Reimplementing a lockstep
battle here would be a second, worse copy of it.

## Engine additions

This mod needed three small, generic additions rather than a fork:

| Where | What | Why |
| --- | --- | --- |
| `src/world/WorldAPI.lua` | `Handle:stepNow / canStep / placeAt / isMoving` | `scriptMove` queues onto `OverworldState.scriptMoves`, which the overworld reads as "a cutscene is running" and uses to gate `handleInput`. Driving a networked actor that way would freeze your controls for 16 frames every time your friend took a step. |
| `src/world/OverworldController.lua` | `world.talk` hook around the NPC talk path | A runtime object a mod spawned has no `TEXT_*` id, so the vanilla path has nothing to say for it. A mod that owns the object claims the `A` press by not calling `next()`. |
| `src/link/LinkState.lua` | `LinkState.newFromSession` + the `adopted` stage | Lets a link session adopt a transport that is *already* paired and skip the connect UI. The mod-compatibility handshake still runs exactly as it would on the LAN or ONLINE path. |

All three are useful beyond co-op — any mod with a self-driven actor wants
the first two.

## Known limits

- **A battle or a trade ends the co-op session.** Ownership of the socket
  transfers to `LinkState`, and `LinkState:exitWith` closes it when the
  battle unwinds. Reconnect to keep walking together. Sharing one socket
  between two state machines is the alternative and it is not worth the
  desync surface.
- **Two players, not more.** The wire and the ghost driver both assume a
  single peer. The message vocabulary would carry a player id fine; the
  session and the ghost table are what would need to grow.
- **The world is not shared.** Doors, event flags, items and NPC state are
  each player's own. You see each other move; you do not see each other's
  progress. That is the next milestone, and it is a much bigger one — it
  needs a conflict-resolution story for two players triggering one event.
- **No prediction or interpolation buffer.** The ghost replays steps as
  they arrive, so on a bad connection it walks in bursts rather than
  smoothly. It never ends up in the wrong place — the resync sees to that.

## Tests

```sh
luajit mods/coop/tests/coop_test.lua       # wire, a live two-ended session, the ghost driver
luajit mods/coop/tests/coop_load_test.lua  # loads through the real headless loader
```

Neither needs an imported ROM: the first runs the session over
`Net.loopbackPair()` and the ghost driver against a stub world, and the
second uses the modkit fixture dataset.
