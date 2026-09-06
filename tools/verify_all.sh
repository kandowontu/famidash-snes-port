#!/bin/sh
# Run every verifier against the full ROM and report one line each.
#
# The individual scripts write their detail to out/*.txt and print little or
# nothing, which is right for reading a single result and wrong for answering
# "is the port still correct". Running them by hand also went wrong in a
# specific way worth naming: a script that fails to start leaves the PREVIOUS
# run's out/*.txt in place, so `tail out/gamemode_sprites.txt` happily reported
# a pass for a run that never happened. This deletes each report before its run
# and treats a missing one as a failure.
set -e
ROM=${ROM:-out/famidash-snes-full.sfc}
MESEN=${MESEN:-C:/mesen2/Mesen.exe}

# script:report - the report is the file the script writes its verdict into.
CASES="verify_render:render_verify
verify_spc:spc_verify
verify_music:music_verify
verify_sprite_chr:sprite_chr_verify
verify_gamemode_sprites:gamemode_sprites
verify_cube_spin:cube_spin
verify_ship:ship_physics
verify_ball:ball_physics
verify_dual:dual_verify
verify_framerate:framerate"

fail=0

# The ROM layout check is Python and prints its own verdict.
printf '%-24s ' "rom layout"
python tools/verify_rom_layout.py --rom "$ROM" | tail -1 || fail=1

for c in $CASES; do
  script=${c%%:*}
  report=out/${c##*:}.txt
  printf '%-24s ' "$script"
  rm -f "$report"
  "$MESEN" --testrunner "$ROM" "tools/$script.lua" >/dev/null 2>&1 || true
  if [ -f "$report" ]; then
    grep -h '^RESULT' "$report" | tail -1 || { echo "no verdict in $report"; fail=1; }
    grep -q '^RESULT.*\(FAIL\|DROPPING\)' "$report" && fail=1 || true
  else
    echo "DID NOT RUN - $report was not written"
    fail=1
  fi
done

# Every level, not just stereomadness: 46 went in at once and each has its own
# height, LZ stream and sprite stream. One emulator run per level - poking the
# selection makes each one short.
printf '%-24s ' "verify_level_boot"
levels=$(grep -c '' out/menu_expect.txt)
lbad=0
L=0
while [ "$L" -lt "$levels" ]; do
  out=$(LEVEL=$L "$MESEN" --testrunner "$ROM" tools/verify_level_boot.lua 2>&1         | grep -E '^level' | tail -1)
  case "$out" in
    *OK*) ;;
    *) lbad=$((lbad + 1)); bad_lines="$bad_lines$out
" ;;
  esac
  L=$((L + 1))
done
if [ "$lbad" -eq 0 ]; then
  echo "RESULT: ALL $levels LEVELS LOAD AND STREAM"
else
  echo "RESULT: FAIL - $lbad of $levels levels"
  printf "%b" "$bad_lines"
  fail=1
fi

# Frame rate on EVERY level. Level 0 is the lightest in the set and holds 60Hz
# while 21 others do not, so checking it alone said nothing.
printf '%-24s ' "framerate sweep"
sh tools/sweep_framerate.sh | tail -1
grep -q . /dev/null || true

# verify_menu prints its verdict rather than writing a report.
printf '%-24s ' "verify_menu"
"$MESEN" --testrunner "$ROM" tools/verify_menu.lua 2>&1 \
  | grep -E '^RESULT' | tail -1 || { echo "no verdict"; fail=1; }

[ "$fail" -eq 0 ] && echo "ALL VERIFIERS PASSED" || echo "SOME VERIFIERS FAILED"
exit $fail
