#!/usr/bin/env bash
# Launch the game under a driver without stealing the desk.
#
# Two things go wrong every time a driver is launched by hand, and both land
# on whoever is sitting at the machine rather than on the run:
#
#   * a 1024x768 window lands on top of what they were doing,
#   * it opens the real audio device, so Pallet Town's theme arrives at
#     whatever volume the speakers were already at.
#
# Neither is a property of the driver, so neither belongs in the driver:
#
#   * conf.lua opens no window at all for a POKEPORT_DRIVER run.  The GL
#     context and the backbuffer are still there, so captureScreenshot still
#     captures -- verified, byte-identical to a visible run.  That is NOT true
#     of a minimized window, whose rendering the OS may stop, which is why
#     love.window.minimize() is the wrong reach.
#   * SDL_AUDIODRIVER=dummy means no output device is ever opened.  love.audio
#     calls all still succeed, so a driver that hooks the audio layer
#     (tests/drivers/trainer_fanfare_bug764_test.lua) still sees its calls.
#   * SDL_WINDOW_NO_ACTIVATION_WHEN_SHOWN=1 stays on as the belt to that
#     brace: with WATCH=1, or anywhere the window is shown after all, it still
#     must not steal focus.
#
# WATCH=1 shows the window, for when the point is to see the run happen.
#
# Usage:
#   tools/drive.sh <driver> [identity]     run a driver: no window, no sound
#   WATCH=1 tools/drive.sh <driver>        ... but show the window
#   tools/drive.sh --play [identity]       hand the game to the user: focus
#                                          and sound ON, no driver
#
# <driver> is a path, or a bare name resolved against the BR driver dir and
# then the engine one, so `tools/drive.sh bot_smoke` works.
#
# Env knobs: WATCH, LOVEC, ROM, SPEED, SHOTS, LOGDIR, GAME, RELAY_PORT.
set -u

LOVEC="${LOVEC:-/c/Program Files/LOVE/lovec.exe}"
ROM="${ROM:-C:/Users/cam95/Documents/roms/pokemon-red-us.gb}"
GAME="${GAME:-red}"
SPEED="${SPEED:-3}"
LOGDIR="${LOGDIR:-${TMPDIR:-/tmp}/g1r-drive}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1

if [ "${1:-}" = "--play" ]; then
  # The one launch that SHOULD take focus and make noise: they asked for it.
  exec env POKEPORT_GAME="$GAME" POKEPORT_IMPORT_ROM="$ROM" \
    ${2:+POKEPORT_IDENTITY="$2"} "$LOVEC" .
fi

driver="${1:?usage: tools/drive.sh <driver|--play> [identity]}"
if [ ! -f "$driver" ]; then
  for dir in mods/battle_royale/tests/drivers tests/drivers; do
    if [ -f "$dir/$driver.lua" ]; then driver="$dir/$driver.lua"; break; fi
    if [ -f "$dir/$driver" ]; then driver="$dir/$driver"; break; fi
  done
fi
[ -f "$driver" ] || { echo "drive: no such driver: $1" >&2; exit 2; }

name="$(basename "$driver" .lua)"
identity="${2:-drv-$name}"
mkdir -p "$LOGDIR"
log="$LOGDIR/$name.log"

# U.shot writes with a plain io.open and only warns; the directory has to
# exist before the run or every screenshot silently writes nothing.
shots="${SHOTS:-}"
[ -n "$shots" ] && mkdir -p "$shots"

start=$(date +%s)
env SDL_WINDOW_NO_ACTIVATION_WHEN_SHOWN=1 SDL_AUDIODRIVER=dummy \
  POKEPORT_GAME="$GAME" POKEPORT_IMPORT_ROM="$ROM" \
  POKEPORT_IDENTITY="$identity" POKEPORT_SPEED="$SPEED" \
  POKEPORT_DRIVER="$driver" \
  ${WATCH:+POKEPORT_DRIVER_WINDOW=1} \
  ${shots:+BR_SHOTS="$shots"} ${RELAY_PORT:+BR_RELAY_PORT="$RELAY_PORT"} \
  "$LOVEC" . > "$log" 2>&1
code=$?

echo "drive: $name exit=$code in $(( $(date +%s) - start ))s  log=$log"
grep -E "^\[driver\]|driver error" "$log" | tail -25
exit $code
