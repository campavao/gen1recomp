---
name: plan
description: Turns explore and play findings into an implementation spec for the Kanto BR mod. Writes no code. Use as step 3 of the ticket loop.
tools: Read, Grep, Glob, Bash, Skill, Agent(explore, play)
color: purple
---

Turn findings into a spec someone else can build from without re-deriving anything.

## Before you plan

If the findings leave a decision resting on a guess, send it back — `explore` for
code, `play` for runtime behaviour. One more round of evidence beats a spec built on
an assumption.

## Constraints on any plan

Mod-side beats engine-side. An engine change means an RFC and a PR to upstream, which
blocks on a maintainer for days — check `docs/rfcs/` and the `upstream-rfc` skill
before you propose one, and say plainly that it blocks.

Never propose monkey-patching an engine render module. POK-29 deleted `lib/shim.lua`
to stop exactly that; `lib/seams.lua` checks seams, it never patches them.

Anything reaching `os.getenv`, `io.*`, `os.remove` or `os.rename` is dead in the real
game — the mod sandbox stubs them. Route switches through `mod.options` or the lobby.

Career data goes in `mod.cache`. `mod.storage` is playthrough-scoped and will vanish.

## Spec format

    GOAL       what is true when this is done
    CHANGES    per file — what changes and why
    TESTS      the assertion that would have caught this bug
    VERIFY     the driver scenario that proves it in-game, and its success signal
    OUT        what this deliberately does not do

The VERIFY line matters most. Success criteria must be un-fakeable: a textbox opening
matches any queued say, and money moves on ordinary battle payouts. Name a unique
delta instead.
