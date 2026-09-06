#!/bin/sh
# Frame rate on EVERY level, not just stereomadness.
#
# verify_framerate.lua ran on level 0 alone, and level 0 is the lightest level in
# the set: it holds 60Hz while 21 of the other 45 do not. That is the same hole
# the byte-exact render check had (docs/HANDOFF.md trap 95) - a real check that
# only ever covered one case.
#
# A shorter window than the full run, because this is 46 emulator runs. The
# numbers are therefore NOT comparable with the per-milestone figures, which are
# measured over the full 3000 frames (trap 83); use verify_framerate.lua for
# those.
#
#   sh tools/sweep_framerate.sh [threshold]
set -e
ROM=${ROM:-out/famidash-snes-full.sfc}
MESEN=${MESEN:-C:/mesen2/Mesen.exe}
FRAMES=${FRAMES:-1200}
MIN=${1:-95}

levels=$(grep -c '' out/menu_expect.txt)
slow=0
L=0
echo "level                     %60Hz  worst-300"
while [ "$L" -lt "$levels" ]; do
  rm -f out/framerate.txt
  LEVEL=$L FRAMES=$FRAMES "$MESEN" --testrunner "$ROM" tools/verify_framerate.lua \
    >/dev/null 2>&1 || true
  if [ ! -f out/framerate.txt ]; then
    echo "  level $L DID NOT RUN"; slow=$((slow + 1)); L=$((L + 1)); continue
  fi
  name=$(sed -n "$((L + 1))p" out/menu_expect.txt)
  pct=$(sed -n '1p' out/framerate.txt | sed 's/.*-> //; s/% of 60Hz//')
  wst=$(sed -n '2p' out/framerate.txt | sed 's/.*window: //; s/%.*//')
  mark=""
  case "$(echo "$pct" | cut -d. -f1)" in
    ''|*[!0-9]*) mark="  ??" ;;
    *) [ "$(echo "$pct" | cut -d. -f1)" -lt "$MIN" ] && { mark="  <-- SLOW"; slow=$((slow + 1)); } ;;
  esac
  printf "%2d %-22s %6s %10s%s\n" "$L" "$name" "$pct" "$wst" "$mark"
  L=$((L + 1))
done

echo
if [ "$slow" -eq 0 ]; then
  echo "RESULT: EVERY LEVEL HOLDS 60Hz"
else
  echo "RESULT: $slow of $levels levels below ${MIN}% of 60Hz"
fi
exit 0
