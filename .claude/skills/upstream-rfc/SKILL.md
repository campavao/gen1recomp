---
name: upstream-rfc
description: Land an engine change upstream in bryanthaboi/gen1recomp as an RFC and PR. Use when a fix needs an engine hook the mod cannot reach, or when working in a g1rfc* worktree.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Engine changes go upstream

Prefer a mod-side fix. An upstream PR blocks on a maintainer for days, and the mod's
`manifest.json` `game_version` floor cannot rise until the change is in a release.

## Prove the mod cannot do it first

Enumerate every hook the engine actually fires:

    grep -rhoE 'Runtime\.call\("[a-z_.0-9]+"' src/

Not `ModRuntime.call` — that covers only the dozen in `Game.lua`. There are ~70.

If none fits, the remaining mod-only routes are painting over pixels from `render.hud`
or monkey-patching a render module. The second is what POK-29 deleted `lib/shim.lua`
to stop. That is the argument for an engine change — state it that way in the RFC.

## Worktree

    git worktree add ../g1rfc<NN> -b rfc-<NNNN>-<slug> origin/dev

Branch off `origin/dev`, never off `battle-royale` — the mod must not travel with it.
Launch Claude there with `--add-dir ../gen1recomp-multiplayer` to keep these skills.

Upstream wants **rebase, never a backwards merge** on a PR branch. On conflict, rebase
onto `origin/dev` and force-push the single commit.

## A new hook needs three artifacts

`tests/engine/gate_meta_coverage.lua` fails without all of them:

1. a modkit case under `tests/modkit/cases/` naming the hook
2. docs in `docs/modding.md`
3. an RFC in `docs/rfcs/`

The hook catalog (`tests/modkit/catalog.lua`) is auto-scanned from source — nothing to
register. Check `docs/rfcs/` for the next free number; upstream has skipped and
duplicated numbers before.

Put the one definition of the new behaviour in a single module and call it from every
site, rather than repeating the condition. RFC 0019 added `src/ui/LevelDisplay.lua`
for exactly this.

## Baseline

`run_engine` is **327/331 on stock `origin/dev`** — `audio_device_reset`,
`hostshell_curl_env` and two `love.quit`/audio-handler suites fail with no change at
all. `git stash` and re-measure before blaming your branch. `run_modkit` is 33/33
clean.

## After it merges

A merged PR is not a shipped hook. Confirm it reached a release:

    git merge-base --is-ancestor <mergeCommit> v0.2.<N>

Then bump the mod's `game_version` floor and write the mod-side wrap.
