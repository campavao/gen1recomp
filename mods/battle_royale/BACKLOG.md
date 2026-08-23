# Kanto Battle Royale — backlog

Ticket-shaped, so it can be pasted into Linear as-is. Ordered by priority
within each group. `[dx]` marks something already diagnosed, with the finding
recorded so whoever picks it up does not repeat the search.

---

## P0 — a match can fail to end

### BR-1 · The ring never closes, so a match can run forever `[dx]`

**Seen:** four survivors at Lv100, ring at its last phase, match not ending.

**Cause:** `lib/fog.lua` — `Fog.PHASES = { 15, 9, 7, 5, 3, 1.5 }` and
`Fog.radius()` clamps to the last entry. After phase 6 the ring is static at
radius 1.5 forever. Anyone standing inside it is safe indefinitely, and
nothing else forces a confrontation.

**Fix:** a final phase that closes to nothing (everything is fog), or an
explicit sudden-death after the last shrink. The level ladder has the same
number of rungs, so both clocks stop together — worth deciding whether levels
keep climbing too.

**Done when:** a match with survivors who refuse to fight still ends.

### BR-2 · A Poison lead is absolutely fog-proof, which removes the ring `[dx]`

**Seen:** "The fog does not harm your POKeMON." around Fuchsia; no damage ever.

**Cause:** working as written — `Fog.immune()` returns true for any Poison-type
lead and `tickFog` then returns before doing damage. DESIGN D11 wanted Poison
to be at home in the fog, but *total* immunity means a Poison lead ignores the
ring for the whole match. Kanto is full of Zubat/Nidoran/Koffing/Grimer, so
this is the common case, not a corner.

**Fix:** make it resistance rather than immunity — half damage, or immune for
the first N ticks only, or immune outside the final ring but not inside it.

**Done when:** a Poison lead is a real advantage in the fog and still loses to
it eventually.

### BR-3 · No indication you are standing in the fog

**Seen:** one text box on entry and nothing after; easy to miss, and easy to
read as "the fog is broken".

**Want:** the poison-walk feel — the screen flash/shake Gen 1 uses for
overworld poison on each tick, plus a persistent on-screen marker while you
are outside the ring. Pairs with BR-12's alive counter.

---

## P1 — rules that are wrong today

### BR-4 · Wild Pokémon keep their vanilla levels

Trainer parties now ride the match rung (`trainer.party` hook). Wild
encounters do not — the Safari hands out Lv22+ against a Lv5 drop. The
`encounter.roll` / `encounter.species` hooks are already wrapped for the
spectator guard, so the level rewrite goes in the same place.

**Done when:** every battle in a match — trainer, wild, Safari, bot — is at
the current rung.

### BR-5 · Battles should be SET style

No "switch Pokémon?" prompt when the opponent's mon faints. It is free
information and a free swap, and it makes party-as-health softer than intended.

### BR-6 · Disable speed-up / slow-down during a match

The bumpers change game speed. In a match with a shared clock and other
players that is straightforwardly cheating.

### BR-7 · Remove LINK from the start menu during a match

The engine's own link play has no business being reachable mid-match.

### BR-8 · Skip the nickname prompt on catch

Always keep the species name. It is friction in a mode where you may catch a
dozen Pokémon under fog pressure.

---

## P2 — elimination and loot

### BR-9 · Eliminated players' ghosts stay on the map

They are non-interactive but still drawn, so the world fills up with corpses.
Decide: despawn them, or keep them as visibly-dead markers (greyed, or a
gravestone sprite).

### BR-10 · Loot balls appear inconsistently

Sometimes a beaten player drops a ball, sometimes not. Suspect the spill
broadcast or the placement search failing silently on a crowded/edge cell —
`Spills.placeAround` gives up if it finds no walkable ring cell.

### BR-11 · Opening a loot ball starts a battle

Expected: pick the Pokémon up as a gift. Today it initiates a catch battle at
1 HP, which is a strange ceremony for something already beaten. (The battle
was how the design made it *catchable* — but a straight gift is what a player
expects, and is faster under fog pressure.)

---

## P3 — spectating

### BR-12 · Spectator hopping + alive indicator `[next up]`

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
