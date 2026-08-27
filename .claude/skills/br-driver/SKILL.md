---
name: br-driver
description: Run Kanto BR in the real game with a scripted driver — launch commands, the driver contract, screenshot and staging recipes, and the two-client PvP harness. Use when verifying a fix in-game, playtesting a match, or gathering runtime evidence.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Driving the game

A driver is a Lua coroutine stepped once per frame. It is the only way an agent can
observe the running game: there is no live log tail, because `Logger.lua` is `print`
with no file sink and stdout is block-buffered until the process exits. Drivers exit
on their own, so their logs capture. An interactive session's log does not appear
until the window closes.

## Launch

    POKEPORT_GAME=red \
    POKEPORT_IMPORT_ROM="C:/Users/cam95/Documents/roms/pokemon-red-us.gb" \
    POKEPORT_IDENTITY=br-<name> POKEPORT_SPEED=3 \
    POKEPORT_DRIVER=mods/battle_royale/tests/drivers/<driver>.lua \
    "/c/Program Files/LOVE/lovec.exe" . > <scratchpad>/run.log 2>&1

From the repo root. A fresh identity imports the ROM on first run (~1 min); budget
2–3 min per scenario after that.

To hand the game to the user instead, drop the driver and identity — the default
`pokemon-love2d` identity already has `red/` imported and holds their career and
skins. Tell them the log arrives when they close the window, and that `lovec`'s own
console shows it live.

## Driver contract

`return function(game)`, stepped as a coroutine. Helpers in `tests/drivers/util.lua`:
`U.wait/tap/hold/shot/log/teleport`. Reach the mod at
`game.mods.exports.battle_royale` — `setSafari`, `setFog`, `setBots`, `hostSolo`,
`start`, `phase`, `status`, `safariLeft`, `buzz`, `ring`, `aliveCount`,
`debugPhase`, `debugWin`, `debugSpill`, `spillState`. End with `love.event.quit(code)`.

`hostSolo()` is async even on a LocalRoom — poll `memberCount()` before `start()`, or
it silently no-ops.

`debugPhase(off|lobby|safari|drop|match|over)` sets a phase with no match under it.
It is the only way to drive a phase-dependent rule headlessly.

## Staging that works

**Walking.** Waypoints are whack-a-mole. Use the one-step BFS in `pvplib.lua`
(`stepToward`/`goTo`): BFS from the goal over `Spawn.walkable`, one cell per call,
repath every call. Add a stuck detector — if a hold moved nothing, tap A, because
post-battle dialogs eat walk input.

Mid-match, walking is unreliable (dialog churn, and a Cycling Road drop slides you
every step). When the walk is not what's under test: `L.flyTo(C, town)` with a
busy-retry loop, then `U.teleport(game, map, x, y)`.

**Fighting.** `Pokemon.movesAtLevel` keeps the *last* four learnset moves, so a
Lv100 MEWTWO has zero damaging moves and a mash-A driver can never win. Overwrite:
`mon.moves = { { id = "PSYCHIC_M", pp = 99 } }`. Move ids are pret names — `PSYCHIC_M`,
not `PSYCHIC`, which warns and stalls at move resolution forever.

**A stationary NPC.** An adjacent bot always becomes a fight — Engage sight-line is
6 cells by row, 4 by column, no consent. Use a vanilla map object (filter `ow().npcs`
by sprite, exclude `E.spills()` cells) and banish every bot to CINNABAR_ISLAND 10,10
first. Off-map bots cannot engage and their ghosts despawn.

**Clocks.** `U.wait` counts sim frames but the fog ring advances on wall time
(`love.timer.getTime`), so at `POKEPORT_SPEED=3` every fog wait is 3× too short.
Stage wins by fighting under a long fog (`setFog(300)`), not by waiting for the ring.

**Solo runs.** Killing the only bot makes you the winner — phase goes `over` and the
presence block stops, so nothing spills. Use ≥2 bots, or `debugSpill(dx, dy)`.

## Screenshots

`BR_SHOTS` must be an **absolute** path and the directory must exist before launch —
`U.shot` calls `os.execute('mkdir -p ...')`, a bash-ism that fails under LOVE on
Windows, and then `io.open` silently writes nothing.

A mod overlay drawn through `render.hud` is guarded by `top == ow`, so it is invisible
in any shot taken while a say box is up — and the fog phase keeps one on screen. Mash
B until `game.stack:top() == game.overworld`, then shoot, and assert `top == ow` so a
covered frame fails loudly.

## Two-client PvP

    python mods/battle_royale/tests/drivers/pvp/run_pvp.py [duel|stall|freeze] [workdir]

Boots `relay/server.js` on `127.0.0.1:7790`, launches two LOVE instances that
coordinate through handshake files in `BR_PVP_DIR`, and watches both logs: any
`PVP FAIL` fails, both `PVP OK` pass. 5–8 min. Env: `LOVEC`, `POKEPORT_IMPORT_ROM`,
`BR_RELAY_PORT`, `BR_PVP_TIMEOUT`.

- **duel** — guest walks into the host's eyeline at Pewter (16,18), lockstep fight to
  a KO, loser's spill on the winner's client, PLAY AGAIN to lobby.
- **stall** — host silent at the move menu; the clock forfeits at ~42s.
- **freeze** — host silent from the battle intro; watchdog plus clock end it at ~69s.

A LOVE process killed by the harness eats its buffered stdout — a log can be 0 bytes
after minutes of play. `pvplib.ctx` mirrors every `U.log` into a flushed
`<role>.plog`; read that. Only trust stdout from a client that exited cleanly.

The engine turn clock ticks only in `s.phase == "menu"`. The move *list* is a
different phase, so a driver that taps A one frame too many disarms the clock.

**This checkout cannot link-battle a packed build.** `Version.lua` pins `0.0.0-dev`
and the handshake refuses `engine_skew`. Local two-client runs work because both
sides are dev; a real playtest against a released build needs a packed build on both
sides.
