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

### BR-13 · See the spectated player's party and items

Needs new wire messages: only position, facing and status are broadcast today.
Sizing and rate need a decision before this is safe on the relay.

---

## P4 — quality of life

### BR-14 · Free move management out of battle

Replace the move-tutor ceremony: from the party summary, swap any of a
Pokémon's moves for any move it can learn, including HMs, at any time outside
battle. (Carried over from the original battle royale design.)

### BR-15 · "Play again" after a match ends

Today the room locks at start and the only way to a second match is everyone
leaving and the host re-hosting.

---

## P5 — bigger design ideas

### BR-16 · Safari opening phase

Everyone starts together in the Safari Zone with a time limit to catch what
they can, seeing each other immediately, unable to battle. When the timer
ends, everyone is spread across Kanto and the Safari is closed for the rest of
the match. Solves the cold open (you meet people in minute one) and the
build-a-team arc at the same time.

### BR-17 · Choose where you drop

Pick a town rather than being scattered at random; the exact tile within it is
still random so a popular town does not stack everyone on one cell. Pairs
naturally with BR-16 as the thing you do when the Safari timer ends.

### BR-18 · Spawn softlocks

A drop can strand you behind water with a Rattata. BR-17 mostly solves it;
until then, consider filtering spawn cells to ones with a land route out.

---

## Carried over from `docs/DESIGN.md`, never built

### BR-19 · D9 — fleeing a PvP battle is free

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
