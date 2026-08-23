# Kanto Battle Royale

Last trainer standing. Everyone drops onto a random spot in Kanto with a
level 5 RATTATA, six Poké Balls and a Potion. You see the other trainers
walking the same world you are; walk into one face-to-face and the battle
starts on its own — no menu, no consent, like a trainer's line of sight.
Your party is your health, so when your last Pokémon faints you're out. The
match ends when one trainer is left.

This is the first, deliberately-minimal milestone: plain Kanto, no fog, no
level scaling, no loot spill yet. See "What's here / what's next" below.

## Playing it

Everyone needs this mod enabled and the same game version. Play runs over a
small relay server (see [`relay/`](relay/)) so it works over the internet,
through NAT, with no port-forwarding.

1. `START` → `ROYALE`
2. `NAME` to pick the trainer name everyone else sees (7 letters, the
   Gen 1 naming grid). `SERVER...` once, to point at your relay as
   `host:port` (default is `127.0.0.1:7790` for a relay on your own
   machine). Both are remembered.
3. One player picks **HOST GAME** and reads out the six-character room code.
4. Everyone else picks **JOIN BY CODE** and enters it.
5. The host can add **BOTS** (0–8, the row cycles) to fill the match out.
6. The host sees the roster fill in and picks **START MATCH**. Everyone
   drops into Kanto at once.

You can run a match entirely on your own: host, set some bots, start.

Walk into another trainer — be on the tile facing them — and the battle
begins. Win, lose or run; a lost battle only ends your match if it was your
last Pokémon. **Knock someone out and you take their bag and their money**
(the first slice of the loot spill). Reopen `ROYALE` any time to see how
many trainers are left, or to leave.

A match plays in a throwaway world: **SAVE is disabled from the drop until
you return to the title** and start or continue a real game, so a match can
never overwrite your actual playthrough.

The start-menu row reads `ROYALE.` while you're in a lobby and `ROYALE*`
once a match is live.

## Running the relay

```sh
node mods/battle_royale/relay/server.js   # :7790 (PORT or BR_RELAY_PORT to change)
```

Run it from the repo root, not from inside `relay/`. A process whose working
directory sits inside `mods/battle_royale/` holds a Windows directory handle,
and the headless loader's directory probe (`tests/fs_io.lua` uses
`os.rename(path, path)` there) then reports the mod folder as missing — so
`br_load_test` fails with a confusing "manifest id: nil" while the game
itself loads the mod perfectly well.

Zero dependencies — any machine with Node 18+ and a reachable port is a
server. On a LAN, one player runs it and everyone points `SERVER...` at that
machine's address. For internet play, run it on a small VPS (or a free
tier) and use its public `host:port`.

## How it works

**Transport.** The engine already ships a newline-JSON TCP client in
`src/link/Net.lua` (its relay backend). This mod speaks a tiny **room
protocol** on top of it — host/join by code, then unicast and broadcast
between members — implemented in `relay/server.js` and spoken by
`lib/relay.lua`. `network` is the one permission the mod declares, exactly
so it can reach `src.link`.

**Movement.** Kanto movement is a grid: one tile per step. So presence is
one small message per step (about four a second), and each other machine
replays the same deterministic step. Cell coordinates ride along in every
message, so drift corrects itself.

**The other players.** Each is a runtime object (`mod.world:spawnNpc`), not
a sprite drawn over the world — so the tile renderer sorts them, collision
treats them as solid, and `A` finds them, all the engine's own code.
Eliminated players stay visible but walk-through.

**Forced battles.** Walking into someone face-to-face fires a
challenge/accept over the room; the lower room id hosts the lockstep. The
battle itself rides a **channel** (`lib/channel.lua`) tunnelled through the
room and handed to `LinkState` (`LinkState.newFromSession`), which owns
every link mode the game already has. Reimplementing a lockstep battle here
would be a second, worse copy of it. Because the channel is separate from
the room socket, a battle no longer ends your session — the old co-op
limitation is gone.

**Party as health.** A whiteout is elimination, however it happened — a bot,
a route trainer, a wild Pokémon — which the mod picks up from the engine's
`world.blacked_out`. PvP is the exception that needs its own path: link
battles follow cable rules and never touch your real party, so the mod reads
the lockstep party copy off `link.battle_ended` and copies the damage back
itself. The host is the authority on who's left and declares the winner.

**The drop.** The host picks every spawn once (`lib/spawn.lua`: a random
walkable, non-water cell on a random outdoor Kanto map, dealt round-robin so
players spread out and never share a cell) and sends the list. Nobody else
has to agree on the algorithm, only on the answer.

**Bots** (`lib/bots.lua`) fill a match out and make it playable solo. They
take spawns from the same list as everyone else, and the host walks them —
relaying each step tagged `as = <bot id>`, so every client renders them
through the same ghost driver a human gets. Only the host's `as` is
honoured, so nobody can puppet another trainer.

Everything *about* a bot — its name, its team — is derived from the match
seed and its id rather than sent, so every client computes the same answer.
That matters because a bot has no client to run a lockstep battle with:
whoever walks into one fights it **locally**, as an ordinary trainer battle
whose party comes from `Bots.party` through the engine's own `trainer.party`
hook. If two clients disagreed about the team, they would disagree about who
won. The winner tells the room (`botout`); the host recounts the survivors.

A bot drops with one Pokémon at the starting level, the same as a player —
two made the bot the favourite in every opening fight, which ended most
matches before anyone could build a team.

Bot steps are paced in **real seconds**, not ticks. A bot's step is ambience
that happens to be network traffic, and tying its rate to the host's logic
clock means a fast-forwarding player floods the relay off its own connection.

## Engine additions

Like the co-op mod, this needs a few small, generic engine seams rather than
a fork. They live outside `mods/` and are documented in the repo's engine
diff:

| Where | What | Why |
| --- | --- | --- |
| `src/world/WorldAPI.lua` | `Handle:stepNow / canStep / placeAt / isMoving / setPassable` | drive a networked actor without the scripted-move queue freezing your controls |
| `src/world/OverworldController.lua` | the `world.talk` hook around the NPC talk path | a runtime object has no `TEXT_*` id, so the mod claims the `A` press |
| `src/link/LinkState.lua` | `LinkState.newFromSession` + the `adopted` stage, and the `link.battle_ended` event | adopt an already-paired transport and skip the connect UI; report the battle's outcome + party so a mode above it can react |
| `src/core/Game.lua` | `Game:startNewGame(opts)` (with `intro=false`) | start a fresh game straight into the world, so a match can drop you in without Oak's speech |

All four are generic — any mod with a self-driven actor, an adopted link
transport, or its own new-game flow wants them.

## What's here / what's next

**Here (v0):** rooms + lobby over a relay with name entry, bots (0–8, so a
match is playable solo), random Kanto drop, the shared loadout, real-time
presence, forced face-to-face battles, party-as-health elimination from any
whiteout, victor-takes-the-bag loot, a save-slot guard (matches can't
overwrite a real save), last-trainer-standing. Route/gym trainers stay live
as PvE.

**Next, in rough order** (from the design in the sibling
`pokemon-battle-royale` project's `docs/DESIGN.md`): the rest of the loot
spill — the fallen team as 1-HP catchables (D8), a shrinking-ring / fog
killer on a shared clock (D11), level-scaling + evolution on that clock
(D12), bots to fill a match, and six-tile "eyeline" initiation instead of
one (change `Engage.inFront`).

## Tests

```sh
luajit mods/battle_royale/tests/br_test.lua        # wire, engage, spawn, a live relay round-trip
luajit mods/battle_royale/tests/br_load_test.lua   # loads through the real headless loader
cd mods/battle_royale/relay && node --test && cd -  # the relay server over real sockets
```

Run the Lua tests with no shell or server parked inside `mods/battle_royale/`
(see the relay note above) — `cd -` in that last line is deliberate.

The Lua tests need no imported ROM (the relay round-trip runs over an
in-memory hub; the spawn test uses the imported Kanto data when present and
skips cleanly when it isn't). `relay.test.js` drives `server.js` over real
loopback sockets.
