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
reaches a box: the engine asks the new `catch.party_full` hook (RFC 0018,
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

### BR-27 · Watch the fight itself — DONE (2026-09-05)

**Resolved 2026-09-05:** a replay, not a stream. The watched client records
its battle -- the seed it rolls on (`BattleState.rng` is swapped for a
Park-Miller stream at `battle.started`), both parties packed with
`Protocol.packMon` as they stood at turn one, and every committed choice
(`resolveTurn` / `resolveSwitch` / `tryRun` / `throwBall` / `itemUsed` /
`sayChoice` wrapped on the instance, replacement picks off
`battle.battler_switched`) -- and unicasts the frames (`bmir`) to whoever
has peeked at it inside the last three peeks. The spectator's client runs
a BattleState of the same kind from those frames, with the engine's menus
replaced by waits for the frame that says what was chosen and the
spectator's input replaced by a stand-in that only turns pages. A duel
rides the lockstep messages themselves into `LinkBattle.newSpectator`, the
engine's tournament observer. A late watcher gets the whole log and
fast-forwards. Every action frame carries both actives' HP and the replica
snaps to it, so drift heals at the next turn. Not a protocol bump: a peer
without it leaves its spectators with the mark over its head. Proved by
`mirror_replay.lua` (one client) and the `spectate` PvP scenario (two,
over the relay). No engine change: `LinkBattle.newSpectator`,
`BattleState.makeBattler` / `trainerSprite` and `Protocol.packMon` were
already there.

Known limits: a move learned mid-fight is not learned on the replica and a
nickname prompt after a catch is skipped. (The replica runs against a
proxy game whose save names the watched trainer, so "<PLAYER> used
<ITEM>!" and "is out of usable POKéMON!" read their name, not the
spectator's.)

### BR-28 · Two bots fight for real — DONE (2026-09-05)

**Resolved 2026-09-05:** `Bots.resolveFight` (power ratio, one roll) is
the fallback only. `tickBotFights` now opens `BR:startBotDuel`: bot A's
team is built through `BattleState.newTrainer` against a proxy game
(`Mirror.proxyGame` -- a save that names A and holds A's party, a private
stack, the stand-in input), then the real fight is `newTrainer` for B with
A's party on the player side. `Mirror.simulate` ticks it once per host
frame at a person's pace with sound and music silenced, A picking moves
through `TrainerAI.chooseMove` aimed the other way (its own dice: the
battle's stream is what the replica follows, and the replica is TOLD A's
choice), replacements through the engine's own PartyMenu closure, SHIFT
declined, `finish` overridden (nothing to pop, nobody to pay). Recorded
with `Mirror.record` for subjects {A, B}; a spectator's peek at a bot goes
to the host (`peek.id`) and frames come back tagged `as` the bot; a host
watching its own bot is fed "local". `finishBotDuel` writes each of the
winner's mons' hpFrac from the fight, then the old path (eliminateBot,
quaff, botrec). Both bots are `inDuel` -- no roaming, no fog, marked
`battle` so nobody can jump them -- and a fight over 150 s is called on
HP left. Proved by `bot_duel_smoke.lua` (14 runs while chasing one drift).

The drift, for the record: a replica whose trainer had NO AI layers rolled
a die where the layered host did not (`TrainerAI.chooseMove` returns a
lone minimum without rolling), because the wire dropped the vanilla
layers, which are NUMBERS (1, 2, 3 -> LAYER_n). Action frames now carry
the roll count and the replica logs a mismatch; `Mirror.DEBUG` adds the
roll-by-roll trace on both ends.

Open: a host handover mid-duel loses the fight (the new host sees two
bots with a stale `battle` mark until they next move).

Open too: in the user's second 30-bot match (2026-09-05, log read), the
replica's out-of-step recovery fired five times in 25 duels -- the fight
lost a mon while the replica's was still standing -- with roll counts AND
both actives' HP matching at the start of every turn. So the difference
is inside a turn and not in the dice: stat stages, status, PP or a bench
mon are the candidates. Every action frame now carries a per-turn state
signature (`Mirror.signature`: both actives' species/HP/status/stages/PP
and both benches) and the replica logs `mirror: turn N, the state differs
before <k>` with both strings when they disagree. Three driver runs since
showed none; the next long spectated match will name the field.

### BR-13 · See the spectated player's party and items — DONE (POK-18)

**Resolved 2026-08-24:** pull, not push. A spectator unicasts `peek` to
the trainer they watch (on each hop, then every 3 s) and gets `state`
back -- party rows `{ sp, lv, hp, mhp, st, mv }` plus the bag and money
(wire PROTOCOL 6). Only two clients pay for it at a time, so sizing and
rate stop being a relay concern. `lib/peek.lua` builds the summary
(nothing that rebuilds the record: no DVs, no EXP) and the rows; a bot's
state is derived from the seed like its team (`Peek.botParty`) with
BOT_LOOT as its bag. While out, the START menu's POKeMON and ITEM rows
open "<name>'s TEAM" (a row per Pokemon: name, level, HP/max, status;
choose one for its moves) and "<name>'s BAG" as ListMenus -- read-only by
construction. No engine change.

Needs new wire messages: only position, facing and status are broadcast today.
Sizing and rate need a decision before this is safe on the relay.

---

## P4 — quality of life

### BR-29 · The last two bots should loot, heal and hunt each other — DONE

**Resolved 2026-09-05** (with BR-30, one change): `Bots.wantsHeal` now
counts a LEAD at or under `Bots.LEAD_LOW` (0.35) whatever the team
averages, and it means "hurt", not "stand down" -- `BR:botStandsDown`
decides that, and only when a nurse on THIS map can still serve, the bag
has no potion, and more than `Bots.ALL_IN` (3) are alive. At three or
fewer the stalk runs every beat with no wobble, healed or not. A spill
within `Bots.LOOT_FIRST` (6) cells outranks the walk to the Centre
(`Bots.chooseGoal`). A hurt bot with an empty bag and no Centre here
ranks its seams by "has an unfogged Centre" first (`roamBot`), so the
Centre one town over is a walk now. Pinned by the `endgame` leg of
`tests/drivers/bot_legs_smoke.lua` (two bots with a lead at 0.3 on
ROUTE_1 meet instead of pacing) and `br_test`.

**Seen 2026-09-05 (the user, spectating a match to its end):** two bots left,
same city, "idly walking back and forth". One had two POKéMON and stood a
few cells from two dropped POKéMON and a bag; it picked up none of it. The
other had five. Neither went looking for the other. A player at two-left
loots what is at their feet, heals, reads the map and closes in.

**More from the same run, read off the spectator's START menu:** neither
bot has a fainted mon; each has its FIRST slot badly hurt and the rest
healthy; neither carries a potion. They are on the route between CELADON
and SAFFRON with the ring closing on SAFFRON. So the permanent-wantsHeal
theory below does not apply to them -- the opposite does: with one hurt mon
in two, the record averages ABOVE the half-team line, `wantsHeal` is false,
and no Centre trip is ever considered, even with a town a route away on
either side. And a route under the ring's fog turns the same-map stalk OFF
by design (`preyHere` requires `not fogOver(map)`, so prey cannot bait a
bot into the fog), leaving only the seam errand toward the eye -- if that
seam is not being reached, two bots pace the route until the fog decides
it. First thing to read from a log: whether their map was fogged, and what
`stepBotErrand` was walking them to.

What exists already, and where it likely stalls:

- **Same-map hunting** (`tickBotRoam`, main.lua ~3358): prey is only
  considered when `not Bots.wantsHeal(record)`. `wantsHeal` is true for
  ANY fainted mon (`hpFrac <= 0`) and a potion cannot revive one, so a bot
  with a dead slot and no reachable Centre is "hurt" for the rest of the
  match and never hunts. It also has a `p.rng() < 0.2` wobble per beat.
- **The Centre** (`pickBotGoal`): `heal` is offered only while the town's
  Centre is not under fog. Once the fog has the town, the bot sips a potion
  per goal pick instead -- which never clears a faint, see above.
- **Loot** (`Bots.chooseGoal`): `heal` outranks `item`, so a "hurt" bot on
  a map with a live Centre walks to the door before it walks to the bag --
  and after healing, the seam clock may take it out of town before it
  circles back. When the Centre is fogged, items should be next; if the bot
  stood by the loot without taking it, check `spills:cellsOn(map, full)`
  (the second argument drops mons when the record is at cap) and whether a
  dwell/`FIGHT_COOLDOWN` (12 s) or the breather was holding it.
- **Cross-map hunting** (POK-95, `huntDistOf`) only ranks SEAMS by the
  nearest live trainer's map; on the same map it does nothing, and the
  roam clock at <= 3 alive is still 8 s of ambling between goal picks.

What "like a player" would mean here, in order:

1. At <= 3 alive (or once the ring is small), a bot on the same map as
   another trainer walks AT them -- `huntFor` set every beat, no wobble,
   healing or not (a wounded player at two-left still fights; it is that
   or the fog).
2. Loot at your feet first: an `item` within a few cells outranks `heal`.
3. `wantsHeal` is the wrong shape at both ends: a fainted slot with no
   Centre in reach should stop counting once the bot has nothing to do
   about it, and a LEAD at a sliver of HP should count even when the rest
   of the team averages it out -- a player heals the mon that fights, not
   the mean.
4. The Centre stays worth a walk if it is one town over and the ring
   allows it; today `heal` is only ever the door on THIS map.

Evidence to gather first: a spectator's run with the deep log on, reading
the two bots' goal picks (`debugFightProbe` shows `goal`, `hunting`,
`dwell`, `sinceFight`) at the moment they are seen ambling.

### BR-30 · A bot plays the way a player plays — the decision list — DONE

**Resolved 2026-09-05**, the rows this build covers: the fog first (as
before); loot at your feet before the nurse; the Centre when the lead is
at a sliver or the team is half gone, on this map or one town over when
the bag is empty; a potion the moment a trainer comes into view (one sip
a beat while the stalk closes, `tickBots`) rather than standing down; a
trainer on your map hunted regardless of wounds unless a nurse here is
the better move; and everything a player would do at three left. The
picker is still `Bots.chooseGoal` plus the gates in `tickBots`, now
reading the same team state (`wantsHeal`, `hasPotion`, `botStandsDown`)
rather than one flag.

**The rest of the table, 2026-09-05 (second pass):** coverage -- a full
team swaps for a catch or a ball that brings a type it lacks, letting a
member go whose every type somebody else carries (`Bots.coverageSwap`;
a grass catch releases it, a looted ball drops it where the bot stands).
HMs -- FLY and CUT are read as team capability the way SURF was
(`Bots.canFly`, `Bots.canCut`), and SURF/FLY are taught into the fight's
movesets (`BR:teachBotMoves`, which duels now reach too). FLY --
`BR:botFly` on the roam clock: to the nearest Centre town when wrecked
with an empty bag and no nurse here, to the unfogged town nearest the
eye when the fog has this map, or to the eye's town when it is
`Bots.FLY_FAR` out and nothing is being hunted on foot; the landing is
the engine's own `field.flyWarps` cell. No bird animation over the
ghost: the wire carries none. CUT -- a cut tree (`Spawn.cuttable`, the
engine's tryCut test) is a path cell for a team with the move
(`botCross`), so the hunt, an errand and a seam walk go through it;
other screens see the ghost walk through the tree, which is the same
abstraction as the unwatched fight. Pinned by the `fly` leg of
`bot_legs_smoke.lua` and `br_test`.

**The user's own flow, 2026-09-05, written while spectating.** This is the
spec the bot goal picker should be measured against, in priority order.
The right-hand notes say what a bot does TODAY (`Bots.chooseGoal`,
`pickBotGoal`, `tickBotRoam`, `huntDistOf`).

| a player... | a bot today |
| -- | -- |
| If I'm not at the centre of the ring, I'm trying to get there. | Seams are ranked toward the eye (`Bots.homeward`, POK-42); on-map errands are grass/loot/stroll, not "toward the eye". |
| If I'm not at a full party, I'm trying to pick up or catch POKéMON. | Yes: loot on the map is an errand, grass dwells roll a catch, the team builds to six (POK-158). |
| If I don't have full type coverage, I swap POKéMON out for better coverage. | **Missing.** A bot keeps what it catches; no coverage read of the team. |
| If there is a bag on the ground, I'm likely going to pick up its contents. | Bags are an errand (`spills:cellsOn`), but heal outranks them, and a bot never takes a bag while it is "hurt" on a map with a Centre. |
| If one of mine needs healing and I see a trainer, I heal up with a potion. | Half of it: `quaff` runs at a goal pick when no Centre serves, not when prey appears. A hurt bot stands DOWN from prey instead. |
| If I see a trainer and my party is at full health, I battle them. | Yes on the same unfogged map (the stalk, POK-153), with a 20 % per-beat wobble. |
| If I see a trainer and my party is not at full health, I heal and then battle. | **Missing.** Hurt means no stalk at all (`wantsHeal` gate). |
| If I see a trainer, I'm hurt and I cannot heal, I run to a town with a Centre. | Half: the Centre errand exists only for THIS map's Centre while unfogged; nothing walks a bot a route over to one. |
| If one of mine has fainted and I have no REVIVE, I go to a Centre. | Same-map Centre only, as above. |
| If one of mine can learn an HM, I teach it. | Partly: SURF is read as a team capability (POK-158 M4); no CUT/FLY, nothing taught deliberately. |
| If one of mine can learn a TM, I teach it. | Partly: a looted TM is taught (`Bots.tmMove`, POK-62). |
| If I'm in the fog, I get out as fast as I can. | Yes: the fog outranks every errand (`kind = "seam", why = "ring"`). |
| If I have FLY, I use it to reach the ring's centre. | **Missing.** Bots walk. |
| If I have SURF and it brings me closer to the centre or out of the fog, I use it. | Partly: the hunt path may cross water with SURF on the team; the seam ranking does not. |
| If I have CUT and it brings me closer or out of the fog, I use it. | **Missing.** |

And the two rules over all of it: **build the team on the way to the
centre**, and **fight what you see unless the odds are bad, in which case
heal first**; with fewer than four left and a good team, **hunt them down
even if that means leaving the centre** (today: seams rank toward the
nearest trainer at six or fewer alive, but only seams, and never while
hurt or fogged -- see BR-29).

The shape this wants is a single ordered decision list per goal pick with
the team's state as input (hurt lead? faint? potions? coverage? HMs?),
rather than the errand picker plus separate gates it is today. BR-29 is
the first two rows of the endgame column and should be fixed inside this,
not beside it.

### BR-32 · A bot crosses a seam by walking through it, not by appearing — DONE

**Resolved 2026-09-05:** the roam clock still ranks the exit
(`Bots.homeward`), but `roamBot` now turns it into a `seam` goal: the
nearest reachable edge cell whose crossing lands on the neighbour
(`Bots.seamCells`, one BFS via `Bots.pathToAny`), walked by the errand
machinery like any other goal under the long clock
(`Bots.LONG_GOAL_SECONDS`). On arrival `BR:walkSeam` lands the bot on the
engine's own landing cell (`Bots.seamLanding`: `destX = curX - offset*2`,
unclamped -- an off-strip landing is a bump, as Spawn.escapableSets
already held) and broadcasts the place; every client's ghost sync
despawns it at the edge and spawns it just across, and tickWatch carries
the spectator over. When the ranked exit's seam is unreachable the next
exit is tried; a bot that can reach none holds. The one seam no bot can
walk is ROUTE_22's fenced north edge, which is the gate building's job.
Pinned by the `seam` leg of `bot_legs_smoke.lua` and the Kanto seam sweep
in `br_test`. FLY as the one legitimate teleport is still BR-30's.

**Seen 2026-09-05 (the user, spectating):** bots "fly" between maps --
they vanish and are standing somewhere else, with no FLY animation and no
walk. That is `roamBot` (main.lua, `p.map, p.x, p.y = dest, c.x, c.y`): a
roam beat picks the next map by seam ranking and then drops the bot on a
RANDOM walkable cell of it, despawning the ghost here and placing it
there. Fine when nobody was looking; a camera glued to the bot (POK-30)
sees a teleport. A player leaves a map through its edge or a door and
arrives at the matching cell on the other side. So: the seam ranking picks
the EXIT as it does now, the bot walks to that exit cell (the hunt path
machinery, `Bots.path`), and the crossing lands it on the exit's connected
cell on the far map -- the same warp the player takes -- so a spectator
following it walks off one map and onto the next. A real FLY, when a bot
has the move and the town is far (BR-30), would then be the one legitimate
teleport, and could show the player's own fly-out animation over the ghost.

### BR-33 · A surfing bot looks like it is walking on water — DONE

**Resolved 2026-09-05:** (1) `Ghosts:_dress` swaps the ghost NPC's sheet
for `field.playerSprites.surf` (SEEL, what `Player:pose` draws) while the
cell under it is `Spawn.swimmable`, and back ashore; nothing on the wire.
(2) seam landings prefer dry cells (`seamGoalFor`), stroll and grass
targets were land already, and spills already wash ashore (`spillBot`).
A hunt or a wander may still pause a beat on water, which is passing
through. Pinned by the `surf` leg of `bot_legs_smoke.lua`.

**Seen 2026-09-05 (the user, spectating, screenshot):** NED standing on the
sea beside the CINNABAR lab door, drawn with his walk sheet, feet on the
waves. A bot whose team knows SURF may cross water on purpose (POK-158 M4:
`botCross` accepts `Spawn.swimmable` cells once `Bots.canSurf` says yes),
and the hunt path and errands use it -- so the position is legitimate; the
PICTURE is not. A player on water sits on the surf sprite. The ghost layer
(`lib/ghosts.lua`) knows nothing about water: it draws the walk sheet the
bot advertised, whatever the cell under it.

Two parts:

1. **Draw it.** When a ghost's cell is `swimmable`, draw the engine's surf
   sprite under it the way the player's own surfing is drawn (the trainer
   sits on the mount, the walk sheet is not used). The wire needs nothing
   new: every client has the map and can ask `Spawn.swimmable` for the
   cell.
2. **Do not stop there.** A surfing player is passing through; a bot whose
   errand or dwell ENDS on a water cell (a random landing cell from a seam
   crossing -- BR-32 -- or a stroll target) will stand on the sea, which is
   the frame in the screenshot. Roam landings, stroll targets and dwells
   should be land cells (`Spawn.walkable`), with water allowed only as
   path, never as destination.

Related: a bot eliminated while on water spills where it stood.
`Spills.placeAround` searches outward for walkable cells and falls back to
the centre cell when none are near, so a team can hit the sea. It should
walk the search to the nearest shore instead.

### BR-34 · Two bots fight from where they noticed each other, not face to face — DONE

**Resolved 2026-09-05:** `tickBotFights` no longer opens the duel on
NOTICE. `BR:botSighting` finds who saw whom -- down the facing,
`Bots.SIGHT` cells, stopped by the map's own walkability
(`Engage.target`), or within NOTICE with a clear line between
(`Bots.clearBetween`, never through a fence) -- and
`BR:startBotApproach` puts a `spot` mark (drawn as the `!`) over the
seer and freezes the one seen. `BR:tickBotApproaches` walks the seer at
`Bots.WALKUP_SECONDS` along a BFS path to any cell orthogonally adjacent,
turns both to face (`BR:faceBot`, on the wire), and only then
`BR:openBotDuel`. Either may be jumped or fogged until then; a walled-off
or over-long approach (`Bots.APPROACH_STEPS`) is called off under the
fight cooldown. Pinned by the `walkup` leg of `bot_legs_smoke.lua`.

**Seen 2026-09-05 (the user, spectating, screenshot):** NED and another
bot both wearing the fighting mark, four or five cells apart with a fence
between them, standing still. That is how a bot duel opens: `tickBotFights`
starts one the beat two bots are within `Bots.NOTICE` (3 cells, Chebyshev,
walls ignored), and `inDuel` freezes both where they stood. The fight
itself is real (BR-28); the approach is missing. When a bot engages the
PLAYER it has one: the `!` flash, then `walkUpThen` brings it adjacent
before the screen opens (POK-85). A duel should be the same scene from
the outside: the two notice each other along an eyeline (`Engage.sightLine`
with the map's `blocked`, the rule players are engaged by -- not through a
fence), one or both walk up until adjacent and facing, the marks go up,
and only THEN does `startBotDuel` open the fight. Until they are adjacent
they are still walking bots and either may be jumped or fogged. Not the
pacing bug: those two were not mid-replay, they were standing.
A second sighting the same session: two bots three cells apart on a
DIAGONAL, both marked, neither facing the other. Chebyshev distance is
what NOTICE measures, so a diagonal counts; a walk-up should end
orthogonally adjacent and facing, the only way two trainers ever meet
in Kanto.

And the mirror image, same session: one bot FOLLOWED another across a
town, in plain sight, and the fight only opened when the one in front
stopped at the Centre door and the follower caught up to three cells.
Two trainers who can see each other are already in the encounter: the
eyeline is the trigger, and the one seen STOPS -- the way the engine
freezes a player the moment a trainer's `!` goes up -- while the other
walks over. NOTICE at three cells is what makes a chase at equal speed
last until somebody pauses, which is what the user watched.

### BR-35 · A bot goes INTO the Centre — DONE

**Resolved 2026-09-05, option (2):** the visit is three legs of the errand
walker. `heal` is the doorstep and one real step up onto the door tile;
`BR:enterCentre` puts the bot on the mat inside (`Bots.warpIn`) with
`p.came` remembering the town and door; `counter` is the cell before the
nurse (`Bots.counterCell`), where the four seconds and `botHeal` happen;
`exit` is the cell above the mat and one step down onto it;
`BR:leaveCentre` resolves the mat like the engine's `Warp.resolve`
(`Bots.warpOut`, LAST_MAP -> the door it came in by) and lands it on the
door facing down. The ring is asked about the town while it is inside
(`BR:botOutdoor`, used by the fog, the goal picker and the stand-down).
Every Centre in Kanto is pinned walkable in, at and out by `br_test`; the
`centre` leg of `bot_legs_smoke.lua` watches VIRIDIAN's from the camera,
which follows the bot inside.

**Asked 2026-09-05 (the user, spectating):** "do bots not go all the way
into a POKéMON CENTER to heal?" They do not. `botHeal` (POK-158 M2) is
reached by walking to the cell in front of the door and waiting the dwell
out there; the team is healed on the doorstep and the interior trip was
abstracted, as the bot fight was. Nobody was following a bot when that
was decided. Now somebody is, and a trainer healing on the pavement with
a mark over their head is the seam showing.

Two sizes of fix:

1. **Enter and vanish (cheap, reads right from outside).** On reaching
   the door step, the bot steps onto the door tile and its ghost is
   despawned for the length of the dwell -- a player walking into a
   Centre disappears exactly like that -- then respawns on the step
   facing down and walks off healed. The wire already carries a
   despawn/place pair. A spectator's camera stays on the step; it is
   what a friend waiting outside sees.
2. **Actually go in (the full thing).** The Centre interior is a map like
   any other: the bot warps through the door the way a player does
   (BR-32's seam walk, doors included), walks to the counter, dwells,
   walks back out. The ghost layer and the spectator camera already
   follow a trainer across maps (tickWatch warps beside them), so the
   spectator would follow them in and stand in the Centre while they
   heal. Needs the interior's walkable cells and the door warp pair;
   nothing new on the wire.

**Decision (the user, 2026-09-05): (2).** A bot goes in like a real player
would; that is the expectation. (1) is not a stepping stone -- build the
door warp with BR-32 and walk the interior. The spectator follows them in.

### BR-31 · TAKE ALL on a dropped bag — DONE

**Resolved 2026-09-05:** `BR:lootRows` puts a TAKE ALL row at the top of
every non-empty bag; `BR:lootTakeAll` takes each stack the pack has room
for and the money in one press, one `Wire.took` per kind so the room's
copies follow, and says one "Took ... !" line per kind (a stack that does
not fit stays on the ground and the box says so). Pinned by case 3 of
`tests/drivers/loot_bag_smoke.lua`.

Looting a bag is one row at a time through the loot list. A player who
wants the lot -- and at two-left, that is everyone -- presses A a dozen
times. A TAKE ALL row at the top of the list (`BR:openBag`, `lootRows`)
that takes every stack the party and bag have room for, in one press,
with one "REF took ..." line per kind. Asked for by the user 2026-09-05.


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

**Re-based 2026-08-27 (POK-144):** there is no PLAY AGAIN row and no
`BR:playAgain()` any more. Every client arms an ending the moment the match
ends and takes it itself (`BR:armEnding` -> the tick -> `BR:endMatch`), so
the room is back in the lobby without anyone pressing anything -- and the
lobby's own start row reads PLAY AGAIN when there is a result to run back
from. `endMatch` does the host's half (broadcast `again`, unlock the room)
and does NOT re-arm the quick-play countdown: a countdown nobody armed
would drop a host who won, read the result and walked away into a fresh
match thirty seconds later. The `again` message is still on the wire, as
the recovery for a client that never saw `winner`.

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

### BR-20 · D8 — loose item and money pickups — DONE (POK-25)

**Resolved 2026-08-24:** one BAG per fallen trainer, on the cell they fell
on, the team's balls around it — position is the tell, and it has its own
sprite: `assets/bag.png`, a 16x16 sheet drawn in the item ball's four
shades (Gen 1 has no bag), registered with `mod.content.sprites:register`
exactly like SPRITE_POKE_BALL (`frames = 1, walker = false`); the POKeDEX
prop stands in if the registry refuses. The `spill` message carries the
bag (`{ key, x, y, items, money, name }`, wire PROTOCOL 5) and `loot` --
the unicast that put the loser's bag straight in the victor's pocket -- is
gone: a PvP loss, a whiteout, the fog and a bot all go through the same
`Spills.build(..., bag)`. Badges and HMs stay out of the bag (they are the
drop's grant). Opening one pages the contents ("RED's BAG: POTION x3 ...
¥500 / Take it?"); YES claims it for everyone (`took`) and the contents
land in ours. Bots: BOT_LOOT becomes their bag, and a player-beaten bot
now spills its team too (`spillBot`, shared with the host's
`eliminateBot`) -- the winner finds it on the ground beside them.

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
