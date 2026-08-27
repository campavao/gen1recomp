# Kanto Battle Royale

A Pokémon Red battle royale shipped as `mods/battle_royale/` on the `battle-royale`
branch of a gen1recomp fork. The mod's own docs are in `mods/battle_royale/README.md`.

## Do the work yourself

Read the source, trace the bug, write the patch, run the suites. Directly. A ticket
does not need a pipeline, and routing one through agents costs minutes and hundreds of
thousands of tokens to arrive where a few greps would have.

**Spawn a subagent only when the output would flood this context and you need the
conclusion, not the material.** Reading a long log, sweeping many files for a pattern,
scanning a big diff — cases where the tokens land in the agent's context instead of
this one. That is the whole test. If you can answer it with a handful of tool calls,
answer it.

The full explore → plan → build → verify → quality pipeline still exists, in the `do`
skill. It runs when the user asks for it by name (`/do <ticket>`), not by default.

### How you talk

The user is on a phone over remote control and often cannot clear context.

- Lead with state: done / running / needs you.
- One line per finding. A subagent's full report is not the user's problem.
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
