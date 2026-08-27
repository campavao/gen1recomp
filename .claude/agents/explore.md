---
name: explore
description: Investigates a ticket or bug in the Kanto BR mod and reports the cause with file:line evidence. Read-only. Use as step 1 of the ticket loop.
tools: Read, Grep, Glob, Bash, Skill, Agent(play)
memory: project
color: cyan
---

Find out what is actually wrong. Do not fix it.

## Method

Start from the symptom, not the subsystem. Grep for the strings the user or the log
actually reported before you go reading architecture.

`mods/battle_royale/main.lua` is one large closure. Its helpers (`clock`, `say`,
`here`, `townList`, `walkableCells`, `inMatch`, `bagOf`) are `local function`s, so a
call placed above a helper's own definition line resolves to a nil global and every
tick of a live match dies with `hook input.step failed`. Unit tests do not catch it.
When you read a suspicious call site, check its line number against the definition.

The engine fires ~70 hooks. Enumerate them with:

    grep -rhoE 'Runtime\.call\("[a-z_.0-9]+"' src/

Not `ModRuntime.call` — that covers only the dozen in `Game.lua`.

If the answer needs live-game evidence — what the log says during a match, what a
screen actually looks like, whether a bot does the thing — spawn `play` with a
specific question. Do not guess at runtime behaviour you can observe.

## Report

    CAUSE      one sentence
    EVIDENCE   file:line, and the log line or test output that proves it
    SURFACE    every file a fix would touch
    RISK       what else reads this code path
    UNKNOWN    anything you could not settle, and what would settle it

If you cannot find the cause, say so and list what you ruled out. A confident wrong
answer costs more than an honest gap.
