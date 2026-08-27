---
name: mod-release
description: Sync mods/battle_royale to the public kanto-battle-royale repo and cut a release. Use when shipping a version, bumping the manifest, or asked why players don't have a change yet.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Shipping a release

Ask before cutting one. It is outward-facing and the in-game updater is confirmed
working, so a release reaches real players the same hour.

## The sync is a copy, not a merge

`campavao/kanto-battle-royale` holds the mod folder's contents at its repo root. It
is not a submodule, subtree, or remote. Syncing means copying these out of
`mods/battle_royale/`:

    main.lua  manifest.json  lib/  tests/  relay/  assets/  COMPATIBILITY.md

Excluded: `BACKLOG.md` (deliberately unpublished) and `README.md` — the mod repo's
README is hand-written and player-facing, not the dev-facing one in this tree.

**A PR opened against the mod repo is the wrong target.** Merging it there gets
silently reverted by the next copy. Replay it onto `battle-royale` here; the mod repo
picks it up through the normal sync. Expect any such PR to be stale too — a cloud
session clones `main`, which is the *last release*, so its diff misses everything
added since. `git apply` will refuse it; `git merge` the PR ref in a scratch clone and
copy the merged files in.

Always check `git diff --cached --stat` before committing a sync. The copy produces
CR-only churn on untouched files; the staged list must name only what actually
changed.

## Cutting it

1. Bump `manifest.json`. Confirm it still carries
   `"github": "campavao/kanto-battle-royale"` — the launcher's *Check for updates*
   walks installed mods and skips any without that field. Eleven releases shipped
   un-offerable because it was missing.
2. **Never hand-roll the zip.** From the mod-repo clone: `python tools/pack.py`
   (`--check` to verify without writing). It is an allowlist, so a new repo-only
   directory has to be added deliberately rather than shipping by accident.
3. `gh release create vX.Y.Z --repo campavao/kanto-battle-royale --target main
   --title "vX.Y.Z — <clause>" --notes-file notes.md <zip>`
4. In the clone: `node tools/build-index.mjs` (needs `gh` on PATH; it refuses a
   manifest/tag mismatch), commit `site/data/index.json`, push.
5. Verify live: the feed reports the new version and the zip URL returns 200.

## Timing

Mod releases no longer restart the relay — Railway `watchPatterns` is `["relay/**"]`.
A **relay** deploy still kills every live match; run
`mods/battle_royale/relay/check-idle.sh` first and treat exit 2 as busy, not idle.

A **PROTOCOL bump** splits the player base — 0.35.0 cannot share a room with 0.34.x.
That is the thing worth timing against live players, not the deploy.

## Two rules the zip has to hold

Both were learned by failing the mod index's submission checklist, and
`tools/pack.py` enforces both — this section is why, not what to type.

**Files sit at the archive root, not under `battle_royale/`.** The engine takes
either: `LauncherMods.locateRoot` returns `""` for a root manifest and `"<dir>"`
for a single wrapping folder, and the install path is `mods/<manifest.id>` either
way (`LauncherMods.lua:1022`), so flattening cannot change where a mod lands. The
index's PR checklist asks for root, so root is what ships.

**`tests/` does not ship.** Nothing at runtime references it, it was 39% of the
download, and `modkit.py validate --strict` / `lint` fail MK301 on any
distributed file containing the literal `data/generated/` — which `br_test.lua`
does, in `pcall`'d `dofile` calls that skip when the cache is absent. No ROM
content is ever involved; the gate is a string match, and the file simply has no
business in a player's download. `pack.py` re-checks the same strings so a
release cannot reintroduce it.

Before submitting to the index, both of these must pass in the engine repo:

    python tools/modkit.py validate battle_royale --strict
    python tools/modkit.py lint battle_royale

## Release notes

Do not write a `CHANGELOG.md`. The GitHub release notes are the changelog:
hand-voiced, player-facing, opening with the compatibility line. Read the existing
ones before writing any doc that might duplicate them:

    gh api repos/campavao/kanto-battle-royale/releases -q '.[].body'
