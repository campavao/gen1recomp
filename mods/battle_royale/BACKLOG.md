# Kanto Battle Royale — backlog

**These are now Linear issues** — POK-5 to POK-28, in the
[Kanto Battle Royale](https://linear.app/pokemon-battle-royale/project/kanto-battle-royale-8f9066b10315)
project. Linear is the source of truth from here; this file is kept as the
long-form version, since the diagnoses in it are longer than a ticket wants to
be and were expensive to find.

`[dx]` marks something already diagnosed, with the finding recorded so whoever
picks it up does not repeat the search.

---

## P0 — a match can fail to end

### BR-1 · The ring never closes, so a match can run forever — DONE (POK-5) `[dx]`

**Resolved 2026-08-23:** `Fog.PHASES` continues past the 1.5-square arena to
`0` (the centre's own square) and then `Fog.EVERYWHERE` (-1, nothing is
safe). `Fog.isSafe` returns false for a negative radius before any other
check, so an unplaced map is not a loophole either. The wire decoder used to
refuse `r < 0`, which would have silently dropped the final ring on every
guest — it now accepts -1. The town map shades everything and drops the
eye box; the announcement reads "The fog covers all of KANTO!".

**Seen:** four survivors at Lv100, ring at its last phase, match not ending.

**Cause:** `lib/fog.lua` — `Fog.PHASES = { 15, 9, 7, 5, 3, 1.5 }` and
`Fog.radius()` clamps to the last entry. After phase 6 the ring is static at
radius 1.5 forever. Anyone standing inside it is safe indefinitely, and
nothing else forces a confrontation.

**Decided:** the fog never clamps. Past phase 6 it keeps shrinking until it
covers the whole map, and the endgame becomes who survives longest inside it
— expected to be rarer than players simply finishing each other off. Remove
the clamp in `Fog.radius` and let `Fog.PHASES` continue to 0.

**Watch out:** this collides with BR-2. If the whole map is fog and a Poison
lead is immune, whoever holds a Poison lead wins by standing still, and the
stalemate comes back in a worse form. One of the two has to give — either
immunity becomes resistance, or the final all-fog phase ignores immunity.

**Done when:** a match with survivors who refuse to fight still ends.

### BR-2 · Poison fog immunity — DONE (removed), revisit as POK-6 `[dx]`

**Seen:** "The fog does not harm your POKeMON." around Fuchsia; no damage ever.

**Cause:** working as written — `Fog.immune()` returns true for any Poison-type
lead and `tickFog` then returns before doing damage. DESIGN D11 wanted Poison
to be at home in the fog, but *total* immunity means a Poison lead ignores the
ring for the whole match. Kanto is full of Zubat/Nidoran/Koffing/Grimer, so
this is the common case, not a corner.

**Resolved 2026-08-23:** immunity removed for players and bots (`99812bc0`).
`Fog.immune` stays in lib/fog.lua, unused and documented as parked. POK-6 is
now the revisit ticket, to be taken alongside POK-28.

**Status:** Poison is the ONLY lead-type ability that exists today — there is
no wider system, just this one check. Adding more is parked deliberately to
keep the first version simple.

**Still needs a decision, because BR-1 forces it:** once the fog covers the
whole map, an immune lead wins by doing nothing. Make it resistance (half
damage) or have the all-fog phase bite through immunity.

### BR-3 · No indication you are standing in the fog — DONE (POK-7)

**Resolved 2026-08-23:** each fog tick sets the overworld's own
`poisonFlash` and plays the `Poisoned` SFX (so it looks exactly like
walking poisoned), and a `FOG!` box pulses top-left while `wasInFog`.

**Seen:** one text box on entry and nothing after; easy to miss, and easy to
read as "the fog is broken".

**Want:** the poison-walk feel — the screen flash/shake Gen 1 uses for
overworld poison on each tick, plus a persistent on-screen marker while you
are outside the ring. Pairs with BR-12's alive counter.

---

## P1 — rules that are wrong today

> BR-4 to BR-8 all DONE 2026-08-23 (POK-8/9/10/11/12). Three were plain hook
> wraps (`encounter.species` + `encounter.fishing`, `core.logic_speed`,
> `ui.start_menu.items` + `removeLabel`). Two had no seam: the engine read
> `save.options.battleStyle` inline and the nickname prompt was inline in the
> catch flow. Writing the option would have leaked SET into the player's real
> options the first time the speed hotkey called `writeOptions`, so they got
> two small generic hooks instead — `battle.style` and `catch.nickname`
> (RFC 0015, `src/battle/BattleState.lua`), shimmed on stock engines. Known
> gap: the touch skin's hold-to-fast-forward sets `speedOverride`, which the
> engine checks *before* the hook on purpose; not reachable from a mod.

### BR-4 · Wild Pokémon keep their vanilla levels — DONE

Trainer parties now ride the match rung (`trainer.party` hook). Wild
encounters do not — the Safari hands out Lv22+ against a Lv5 drop. The
`encounter.roll` / `encounter.species` hooks are already wrapped for the
spectator guard, so the level rewrite goes in the same place.

**Done when:** every battle in a match — trainer, wild, Safari, bot — is at
the current rung.

### BR-5 · Battles should be SET style — DONE

No "switch Pokémon?" prompt when the opponent's mon faints. It is free
information and a free swap, and it makes party-as-health softer than intended.

### BR-6 · Disable speed-up / slow-down during a match — DONE

The bumpers change game speed. In a match with a shared clock and other
players that is straightforwardly cheating.

### BR-7 · Remove LINK from the start menu during a match — DONE

The engine's own link play has no business being reachable mid-match.

### BR-8 · Skip the nickname prompt on catch — DONE

Always keep the species name. It is friction in a mode where you may catch a
dozen Pokémon under fog pressure.

---

## P2 — elimination and loot

> Fixed already, not a ticket: the spectator return warp used to fight the
> engine's whiteout warp for fifteen seconds, which showed up as a flashing
> POKeMON CENTER and the player spinning on the spot. It now waits to be moved
> and moves back exactly once.

### BR-9 · A defeated trainer's sprite should disappear, leaving only the balls — DONE (POK-13)

**Resolved 2026-08-23:** ghosts of players and bots despawn on `status ==
"out"` (`Ghosts:sync` filters and despawns; `eliminateBot` already did it
host-side); Kanto's own trainers are toggled off via the engine's
`objectToggles` on every client (`npcout` on the wire). The spectator still
sees their own local sprite — it is their camera avatar, and nobody else
sees it.

**Decided:** when anything is beaten — an eliminated player, a bot, or one of
Kanto's own NPC trainers — the sprite goes away entirely and all that is left
on the ground is its Poke Balls. Walking into an area and seeing balls with no
trainer is how you read that somebody else got there first.

Today eliminated players stay drawn (non-interactive) and NPC trainers stay
put exactly as in vanilla.

### BR-9b · Kanto's own NPC trainers should drop their Pokémon too — DONE (POK-14)

**Resolved 2026-08-23:** `world.trainer_engaged` stashes the map object;
a `battle.ended` win spills `enemyParty` (at the rung, as fought) where the
trainer stood, broadcasts `npcout` + the spill, and toggles the object off
everywhere. Spill keys are `npc:<map>:<obj>:<i>`, so a double-beat race
cannot duplicate loot. Scope note: this covers `engageTrainer` trainers
(sight and talk); script-driven fights (gym leaders, the rival) are POK-26's
territory. Wire PROTOCOL bumped to 2.

Not just players and bots. Beating a route trainer leaves its team on the
ground the same way, which makes the world readable — you can tell at a glance
which routes have already been picked over, and it gives PvE a reason to
exist beyond levels.

### BR-10 · Loot balls appear inconsistently — DONE (POK-16)

**Diagnosed 2026-08-23:** the first suspect was right. `Spills.placeAround`
gave up silently when the outward ring search found fewer walkable cells
than Pokémon (map edges, water, walls) and `Spills.build` dropped the
shortfall — "sometimes a ball, sometimes not". The other suspects were
clean: the spill handler is unconditional, and `Spills:sync` already logs.
Fixed: the shortfall now stacks on the faller's own cell, which is walkable
by definition and free now that the corpse despawns (BR-9). Every fallen
Pokémon lands somewhere, always.

Sometimes a beaten player drops a ball, sometimes not. Suspect the spill
broadcast or the placement search failing silently on a crowded/edge cell —
`Spills.placeAround` gives up if it finds no walkable ring cell.

### BR-11 · A loot ball should be a gift, not a second battle — DONE (POK-15)

**Resolved 2026-08-23:** `openSpill` pushes the take-or-leave TextBox
instead of a 1-HP catch battle. The claim (`Wire.took`) is broadcast only
on YES, so NO and a full party leave the ball; a claim that lands while
the box is open answers YES with "It's gone". The Pokémon joins at 1 HP,
OT-stamped, dex-marked. Live-verified: YES added the fallen mon, NO left
the ball on the ground.

**Decided:** the hard part was the battle you already won; fighting a 1 HP
opponent afterwards to earn it again is ceremony. Opening a ball shows the
prompt Oak's lab uses for the starters —

> This contains a NIDORINO. Do you want it?

— with take-or-leave. No battle, no catch roll.

Leave means the ball stays on the ground for someone else.

### BR-24 · A full party means dropping one (the Fortnite rule) — DONE (POK-34)

**Resolved 2026-08-23:** at 6/6 a catch or a loot-ball take opens the party
screen as a picker (`PartyMenu` `pickOnly`): A releases that member, B keeps
the team you have — a cancelled catch is released, a passed-over ball stays
on the ground. The released Pokémon spills as a ball at your feet — the same
`Spills`/`Wire.spill` path as an elimination, under its own `<id>:drop:<n>`
key namespace — so trading up leaves a trace anyone can claim. Nothing ever
reaches a box: the engine asks the new `catch.party_full` hook (RFC 0016,
`BattleState:partyFullDestination`) before `Boxes.deposit`; on a stock
engine the shim wraps `deposit` itself, at the cost of the vanilla "But
every BOX is full!" line showing before the picker. The battle picker rides
the engine's own UI queue (the dex page stays ahead of it); the spill waits
until the battle unwinds and the overworld is back on top, because the ball
lands where you stand.

---

## P3 — spectating

### BR-12 · Spectator hopping + alive indicator — DONE (POK-17)

**Resolved 2026-08-23:** `N LEFT` box top-right during a match. While out,
LEFT/RIGHT are taken off the engine's press queue in `input.step` (before
`Input:step` promotes them) and hop to a free cell beside the next living
trainer; `tickWatch` re-warps when they change map or get > 5 cells away,
at most every 2 s; `movement.collision` refuses the spectator's own steps.
The watched name is shown top-left.

**Found on the way — a real P0:** `roamBot` reset a bot's `fogTicks` on
every map change, and bots roam every 25 s against a 40 s kill, so a bot
that kept walking could never die in the fog. That alone could keep a match
from ending. Fixed; the ticks now persist like a player's lost HP.

LEFT/RIGHT cycles between living trainers while you are out; an on-screen
counter shows how many are left. No bumpers exist — the engine has only
`up/down/left/right/a/b/start/select` — and a spectator has no other use for
left/right.

### BR-26 · Spectator: a camera, not a body — DONE (POK-30)

**Resolved 2026-08-23:** no engine change. While out, the tick asserts the
engine's own `ow.playerHidden` (the flag the fly/warp fades use, cleared by
the engine on every arrival, so it is re-set each frame) and
`ow.player.passable = true` (`Collision.occupied` lets NPCs and ghosts
through). The view is the engine's camera follow plus a `cameraPan`
offset — the pan_camera script's mechanism, a plain `{ ox, oy }` with no
ramp — pointing from the invisible body to the watched trainer's ghost,
recomputed every tick off the ghost NPC's pixel position (`Ghosts:npcOf`),
so it walks when they walk; while the ghost is not yet placed the wire's
cell stands in. A different map is the one case that still warps
(`tickWatch`, cross-map only, no more "five cells away" re-warps). `hop`
no longer warps directly — it just changes `watching` and lets the tick
catch up, which is what makes hopping survive a menu round-trip (a warp
attempted under a menu used to fail silently). The first living trainer
is picked automatically on elimination. A spectator's A press no longer
turns a ghost to face an invisible body.

### BR-13 · See the spectated player's party and items

Needs new wire messages: only position, facing and status are broadcast today.
Sizing and rate need a decision before this is safe on the relay.

---

## P4 — quality of life

### BR-27 · One lobby screen, not a menu round-trip — DONE (POK-32)

**Resolved 2026-08-23:** `lib/menu.lua` is now a Menu whose rows are
rebuilt from BR every frame (`Menu.items(mod, BR, game)` is a pure
function of state; `Menu.view` names the face: menu / connecting / lobby /
match). The rows that start a room — QUICK PLAY, SOLO VS BOTS, HOST GAME,
JOIN BY CODE — keep the screen open, so the same screen becomes the lobby
on the next frame; the box re-sizes to its rows the way `Menu.new` sized
it at birth; the cursor resets only when the face changes. START MATCH,
LEAVE and LEAVE MATCH close it. NAME and SERVER... stay on the first face
(a name is sent when you join, an address only matters before you
connect). The match face gained the Safari clock. Same pattern the
engine's StartMenu uses to overlay its Safari counter (override the
instance's method, call the base).

### BR-14 · Free move management out of battle — DONE (POK-19)

**Resolved 2026-08-24:** `lib/moves.lua` + a `ui.party.submenu` wrap. The
engine's party submenu already accepts hook-injected rows with an
`onSelect(mon, game)` callback, so in a round (and out of battle) a MOVES
row sits above STATS. `Moves.learnable(data, mon)` is the species'
`level1Moves` + `learnset` at any level + `tmhm` (already move ids, HMs
included), minus what it knows, each once; `Moves.teach` fills a free slot
or replaces a chosen one at full PP. UI: a ListMenu "LEARN WHICH?" (the
`right` column says L<n>/TM/HM), then "FORGET WHICH?" only when all four
slots are taken, then a text box. No MoveLearnMenu ceremony and no HM
lock — the mode says any move, any time. Pre-evolution learnsets are not
included (a RAICHU only lists RAICHU's); worth adding if it bites.

Replace the move-tutor ceremony: from the party summary, swap any of a
Pokémon's moves for any move it can learn, including HMs, at any time outside
battle. (Carried over from the original battle royale design.)

### BR-15 · "Play again" after a match ends — DONE (POK-20)

**Resolved 2026-08-24:** the host's match report gains PLAY AGAIN once the
match is over (`Menu.items`, host only). `BR:playAgain()` broadcasts a new
`again` message (wire PROTOCOL 4), unlocks the room (`relay:lock(false)`
-- the relay's `lock_room` always took a boolean; the solo room ignores
it) and runs `onAgain` locally; guests run it on the message. `onAgain`
clears everything one match owns (`BR:resetMatch()`, split out of
`reset()` so the room -- relay, code, roster, BOTS/FILL/OPEN -- survives),
leaves the finished world the way `teardown` does (pop to the title) and
pushes the lobby screen on top, so the roster and START MATCH are right
there. An open room re-arms its quick-play countdown. The next START MATCH
rolls a new seed and spawns like the first.

Today the room locks at start and the only way to a second match is everyone
leaving and the host re-hosting.

---

## P5 — bigger design ideas

### BR-16 · Safari opening phase — DONE (POK-21)

**Resolved 2026-08-23:** `BR.phase` gained `safari` and `drop`. The host
deals everyone a distinct cell of `SAFARI_ZONE_CENTER` (`Spawn.pickIn`) and
`start` carries the round's length (`SAFARI SECONDS`, default 120; wire
PROTOCOL 3). The loadout hook writes an EMPTY party and the gate's own
`save.safari = { balls = 30, steps = 502 }`, so the engine's Safari — the
BALL/BAIT/ROCK/RUN battles, the steps/500 counter, the PA game-over —
runs unmodified. Three things had to come from outside: the host's clock
(`safari` beats every 5 s, 0 = buzzer), the centre's two gate warps
refused via `movement.collision`, and a **stand-in lead** lent for one
encounter while the party is empty, because `BattleState.newWild` marks a
battle with no healthy party dead ("skipping") — it never draws the lead
in a Safari battle, so nobody sees it; it leaves on `battle.ended`. At the
buzzer: caught nothing → `eliminate()` (its guard now spans the round);
otherwise the vanilla `ow:safariGameOver()` (PA jingle, "Time's up!",
walk to the gate), then the picker (BR-17). Nobody fights until the drop:
`tryEngage`, the ghost-talk path and inbound challenges all wait for
`phase == "match"`; bots stop hunting in the Safari. The gate's Fuchsia
door is refused for the rest of the match. Decided during implementation:
no starter (the Safari IS the team), the vanilla step and ball limits stay
as the real game's second and third ways out, the fog clock starts at the
host's landing, and the fog's eye is NOT shown in the picker (v1).

Everyone starts together in the Safari Zone with a time limit to catch what
they can, seeing each other immediately, unable to battle. When the timer
ends, everyone is spread across Kanto and the Safari is closed for the rest of
the match. Solves the cold open (you meet people in minute one) and the
build-a-team arc at the same time.

### BR-17 · Choose where you drop — DONE (POK-22)

**Resolved 2026-08-23:** the Safari's exit screen. At the gate a `ListMenu`
("DROP WHERE?") lists the fly towns in Town Map order; B closes it and the
tick reopens it, because there is no staying at the gate. The choice lands
on a random walkable cell of that town (`Spawn.pickIn`, one cell) via
`mod.world:warpTo(..., { arrive = "fly" })`, `lastHeal` moves with it, and
`phase` becomes `match` on the choice. Bots get a town from their own rng
stream at the buzzer and are placed host-side.

Pick a town rather than being scattered at random; the exact tile within it is
still random so a popular town does not stack everyone on one cell. Pairs
naturally with BR-16 as the thing you do when the Safari timer ends.

### BR-18 · Spawn softlocks

A drop can strand you behind water with a Rattata. BR-17 mostly solves it;
until then, consider filtering spawn cells to ones with a land route out.

---

## Carried over from `docs/DESIGN.md`, never built

### BR-19 · D9 — fleeing a PvP battle is free — DONE (POK-24)

**Resolved 2026-08-24:** `lib/flee.lua`. A lockstep battle ends as a draw
the moment either side submits a `run` action and the engine's escape
roll (`battle.run`) never runs for it — `LinkBattle` submits straight from
its own `tryRun`. That `tryRun` is an instance field, so the mod wraps it
on `battle.started` for `kind == "link"` and only the RUNNER's machine
decides whether a run is submitted at all — deterministic by construction,
no engine change, works on stock. The roll: one in four at equal speed,
half at twice the pursuer's speed, capped at five in eight, +8% per retry
in the battle (never certain), halved per earlier escape from the same
pursuer (`fledFrom[opponent]`, kept per match). A failed attempt says
"Can't escape!" and hands the menu back — the turn is fought, not lost as
in Gen 1, because the lockstep needs an action from us and a pass would
need a seam. A POKé DOLL is spent for a guaranteed bail. After a flee the
pair gets a 4 s grace (both `tryEngage` and inbound challenges skip each
other) and the runner a 30 s lockout from initiating on that pursuer.
NOT done from D9: Teleport/Roar as escape moves (engine turn logic) and
Repel shrinking the eyeline others see you at (needs a wire flag).
Verified headlessly on the real lockstep (a loopback host/guest pair with
the guest's RUN wrapped: a failed roll leaves the battle running and the
host sees nothing; a passing roll ends it as a draw on both sides).


RUN ends a link battle as a draw with no consequence. Damage carries, but
nobody can ever be cornered, which blunts the forced-eyeline premise. D9 wants
a re-engage cooldown, escalating pursuit, and escape items.

### BR-20 · D8 — loose item and money pickups

The victor takes the bag directly. D8 wants items and money on the ground as
pickups, like the team already is.

### BR-21 · D14 — gyms as contested bosses

Gyms are plain PvE. D14 wants first-to-beat claims the prize and the gym
closes for the match.

### BR-22 · D18/D20 — type-based overworld abilities

### BR-23 · Badges boost stats in PvE but not PvP

All eight badges are granted at the drop, and Gen 1 badge boosts apply in
bot/wild/trainer battles but not in link battles (cable rules zero them). It
is symmetric between players so it is not unfair, but PvE is measurably softer
than PvP. Worth a decision rather than an accident.
