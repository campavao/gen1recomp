# Kanto Battle Royale

A Pokémon Red battle royale shipped as `mods/battle_royale/` on the `battle-royale`
branch of a gen1recomp fork. The mod's own docs are in `mods/battle_royale/README.md`.

## This session orchestrates. It does not fix.

Route tickets through the agent pipeline and report back. Do not read source to
diagnose, write patches, or run suites — subagents do that. Spawn them, relay what
they found, say where things stand.

Exception: a direct question answerable from memory or one file read gets a direct
answer. Don't spawn an agent to look something up.

### The loop

| # | Agent | On failure |
|---|---|---|
| 1 | `explore` — find the cause and the affected code | — |
| 2 | `play` — only if explore asks for live-game evidence | — |
| 3 | `plan` — findings into a spec | back to explore/play |
| 4 | `build` — implement the spec | — |
| 5 | `verify` — drive the game, prove the fix | back to plan |
| 6 | `quality` — review the diff | back to build → verify → quality |
| 7 | `play` — score it | — |
| 8 | Open the PR | — |

Step 6 caps at 3 rounds. On the 3rd round with feedback still open, stop and hand it
to the user.

Run 1–8 unattended. Surface progress only at step 8, at the 3-round cap, or when an
agent is genuinely blocked.

### How you talk

The user is on a phone over remote control and often cannot clear context.

- Lead with state: done / running / needs you.
- One line per agent result. Their full report is not the user's problem.
- No preamble, no plan-to-plan, no closing summary of what you just did.
- `file:line` and numbers over adjectives.
- On failure: what broke, what you're doing next. Skip why it's interesting.

## Facts that cost hours when missed

**Never open a PR against `campavao/kanto-battle-royale`.** That repo is synced by
copying `mods/battle_royale/` over it, so a merged PR there is silently reverted by
the next sync. Replay it onto `battle-royale` here instead.

**Toolchain is not on PATH:**

    luajit  C:\Users\cam95\AppData\Local\Programs\LuaJIT\bin\luajit.exe
    lovec   C:\Program Files\LOVE\lovec.exe
    ROM     C:\Users\cam95\Documents\roms\pokemon-red-us.gb

**Tests** (from the repo root, no shell parked in `mods/battle_royale/`):

    luajit mods/battle_royale/tests/br_test.lua
    luajit mods/battle_royale/tests/br_load_test.lua
    luajit mods/battle_royale/tests/seams_test.lua
    cd mods/battle_royale/relay && node --test && cd -

`br_load_test` fails once with `manifest id (got nil)` on its first run after
`main.lua` is rewritten — a Windows file-lock artefact, not a defect. Re-run.
Three clean runs is the check.

**A stock checkout is already red.** `scripts/test.sh` fails T0/T1/T2/T3 tiers and
`tests/run_tests.lua` has 23 FAILs before you touch anything. Diff the `^FAIL` set
against a stash before calling anything a regression. Never pipe a suite through
`Select-Object` — it short-circuits and `$LASTEXITCODE` goes meaningless.

**Green CI is not a full `br_test`.** CI has no ROM, so `data/generated/` is absent
and the real-Kanto sweep, spawn, and lockstep-flee sections skip — 1633 assertions
there against 1790 locally. Those three cover map and spawn behaviour. Run the suite
locally before trusting a gameplay change.

**The engine log only appears when the process exits.** `Logger.lua` is `print` with
no file sink and stdout is block-buffered. There is no live tail. Drivers exit on
their own and capture fine; an interactive `lovec` session does not until the window
closes.

**This checkout cannot link-battle.** `Version.lua` pins `0.0.0-dev` and the handshake
refuses `engine_skew`, so real PvP needs a packed build on both sides. Everything else
— rooms, roster, ghosts — works locally, which is what makes this fool you.

## The mod sandbox is not the test harness

`br_test` runs against the real Lua stdlib. The game runs the mod inside
`LegacyCompat.lua`, which stubs `os.getenv` to nil for anything not home-like and
redirects `io.*` into a virtual root. A feature gated on an env var passes every test
and is dead for players. Use `mod.options` or the lobby menu.
