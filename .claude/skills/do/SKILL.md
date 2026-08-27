---
name: do
description: Run a ticket through the full agent pipeline — explore, plan, build, verify, quality, then a PR. Use only when the user invokes it by name; ordinary tickets are faster done directly.
allowed-tools: Read, Grep, Glob, Bash, Skill, Agent, SendMessage
---

# Running a ticket through the team

You are the orchestrator for this ticket and nothing else. Do not read source to
diagnose, write patches, or run suites — the agents do that. Spawn them, relay what
they found, say where things stand.

This is the expensive path. A pipeline run costs minutes and six figures of tokens, so
it earns its keep on work that is genuinely wide — a bug touching several subsystems, a
feature needing a real spec, anything where one context cannot hold the material. For a
tight bug with a known neighbourhood, close the skill and do it yourself; that is the
default the project's CLAUDE.md sets, and it is usually right.

## The loop

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

Step 6 caps at 3 rounds. On the third round with feedback still open, stop and hand it
to the user rather than looping again.

Run 1–8 unattended. Surface progress only at step 8, at the 3-round cap, or when an
agent is genuinely blocked.

## Briefing an agent

A weak brief is what makes this path slow. Each agent starts with nothing but what you
write, so carry the findings forward yourself:

- State what is already established, with `file:line`, and say **do not re-derive it**.
  Two agents rediscovering the same fact is the main way a run wastes an hour.
- Name the specific files or symbols to start from. "Investigate the freeze" costs far
  more than "start at `main.lua:4111` and trace `toggleObject`".
- Say what would settle an open question, so the agent knows when to stop.
- Give the constraints that change the answer: which build is running, what is committed
  versus dirty, whether an engine change is affordable.

When you learn something mid-run that changes the search, `SendMessage` the running
agent rather than letting it finish on a stale premise.

## Model tiers

The agents carry their own. `verify` and `play` are pinned to `sonnet` — they drive a
driver and read what came back, which is not frontier work. `explore`, `plan`, `build`
and `quality` inherit, because finding a root cause, writing a spec, implementing it and
reviewing it are the steps where a weaker model costs more than it saves.

Anything you spawn outside those six — a log grep, a file sweep — takes `model: "haiku"`
and `effort: "low"`. Do not pass a model override to the six; their definitions already
say what they need.

## Concurrency

Check `git status` before step 4. If another session has uncommitted changes in files
the spec touches, tell `build` explicitly which paths are off limits and split the work
so it creates new files rather than editing held ones. A collision here costs someone
else's work, which is worse than a slow ticket.

## Reporting

One line per agent result. The user does not want the transcript — they want to know
whether it is moving, what broke, and what needs them. Keep the project's voice rules.

Do not state an agent's conclusion as fact until you have checked the part that matters:
run the suite yourself, or read the one file the finding rests on. Agents are confidently
wrong often enough that relaying a wrong cause costs more than the check.
