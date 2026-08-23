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
5. The host can add **BOTS** (the row steps 0, 1, 2, 3, 5, 8, 12, 16, 20,
   25, 30 and wraps) to fill the match out.
6. The host sees the roster fill in and picks **START MATCH**. Everyone
   drops into Kanto at once.

You can run a match entirely on your own: host, set some bots, start.

You start with **all eight badges and all five HMs**, because a match is
twenty minutes and Kanto is gated for a campaign. The badges are what Gen 1
checks before a field move will run at all, and they open the Route 22 gate
and Victory Road. The HMs are still items you have to *teach* to something
compatible — so catch a water type and you can Surf, catch a Machop and you
can move boulders. Where you travel is still what team you can build; the
gyms are just no longer in the way.

Meanwhile the **fog** closes in. See below.

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

**The fog** (`lib/fog.lua`) is what turns this from a deathmatch into a
battle royale: a ring that tightens on a shared clock until everyone left is
in the same few squares.

Drawing it took one decision worth knowing about. Kanto here is not a single
canvas the way Hoenn was in the sibling project — it is 222 separate maps
stitched by warps, with no global coordinate space to put a circle in. But
the game already ships Kanto's real geography: `field.townMap.locations`
gives **every** map a cell on the 16×16 Town Map grid, interiors included (a
building sits on its town's square). So the ring is a circle in *Town Map
space*, and a map is safe when its square falls inside it. The fog therefore
follows the Kanto you know — it closes on a named place, the routes around
it go first, and hiding in a building doesn't help because the building is
on the same square as the town.

Outside the ring, every Pokémon in your party loses **a tenth of its maximum
HP every four seconds** — about forty seconds from full to fainted. It is a
fraction rather than Gen 1's flat 1-HP-per-4-steps because a flat point does
not survive level scaling: it would kill a Lv5 starter in a minute and take
twenty patient minutes against a Lv100 team, which is exactly backwards. The
fog has to bite hardest when the ring is smallest. A **Poison-type lead is
immune**: the fog is its element
(DESIGN D11), and it gives an unloved type a real reason to be on your team.
Losing your last Pokémon to the fog eliminates you exactly like a whiteout.

The host owns the clock and announces each shrink; nobody derives it from
their own wall clock, which would drift. Bots caught outside walk out of it
off-screen — real pathing across Kanto's warp graph is a much bigger
feature, and relocating them keeps the match converging instead of quietly
wiping the roster on the first shrink.

`FOG SECONDS` (a mod option, default 120) is how long each ring lasts, so a
default match runs about ten minutes and a quick one can be far shorter.

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

**How many bots?** Up to **30**, verified live end-to-end. Kanto has 34
outdoor maps, so thirty bots each get a route or town of their own and the
drop stays spread out. The limit above that is the wire rather than the
world: the host relays one step per bot per beat, about 1.4 messages a
second each, against the relay's 120-a-second flood guard — thirty sits near
40/s with comfortable room for everyone's own movement and a battle in
flight, while sixty would be at three quarters of the cap before a fight
starts. Going much past thirty wants area-of-interest relaying (only
broadcast a bot when somebody is on its map), which is DESIGN D6 and would
make the count nearly free.

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

**Here (v0):** rooms + lobby over a relay with name entry, bots (up to 30,
so a match is playable solo), random Kanto drop, the shared loadout plus all
badges and HMs, real-time presence, forced face-to-face battles, the
shrinking fog on a shared clock with Poison immunity, party-as-health
elimination from any whiteout, victor-takes-the-bag loot, a save-slot guard
(matches can't overwrite a real save), last-trainer-standing. Route/gym
trainers stay live as PvE.

**Next, in rough order** (from the design in the sibling
`pokemon-battle-royale` project's `docs/DESIGN.md`): the rest of the loot
spill — the fallen team as 1-HP catchables (D8), level-scaling + evolution
on the same clock the fog uses (D12), six-tile "eyeline" initiation instead
of one (change `Engage.inFront`), bots that fight each other rather than
only the player, and drawing the ring on the Town Map item so you can see
where to run.

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
