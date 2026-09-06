#!/bin/sh
# Run every SA-1 milestone check and report one line each.
#
# Same shape as tools/verify_all.sh, and for the same reason: a script that
# fails to start leaves the previous run's out/*.txt in place, so the report is
# deleted before each run and a missing one counts as a failure.
set -e
MESEN=${MESEN:-C:/mesen2/Mesen.exe}

CASES="famidash-sa1:verify_sa1:sa1_probe
famidash-sa1-bench:verify_sa1_bench:sa1_bench
famidash-sa1-c:verify_sa1_c:sa1_c
famidash-sa1-rommap:verify_sa1_rommap:sa1_rommap
famidash-sa1-full:verify_sa1_game:sa1_game
famidash-sa1-full:verify_sa1_play:sa1_play
famidash-sa1-full:verify_sa1_music:sa1_music
famidash-sa1-full:verify_sa1_oam_lifecycle:sa1_oam_lifecycle
famidash-sa1-full:verify_sa1_sprite_chr_atomic:sa1_sprite_chr_atomic"

fail=0
for c in $CASES; do
  rom=out/${c%%:*}.sfc
  rest=${c#*:}
  script=${rest%%:*}
  report=out/${rest#*:}.txt
  printf '%-22s ' "$script"
  rm -f "$report"
  "$MESEN" --testrunner "$rom" "tools/$script.lua" >/dev/null 2>&1 || true
  if [ -f "$report" ]; then
    grep -h '^RESULT' "$report" | tail -1
    grep -q '^RESULT.*FAIL' "$report" && fail=1 || true
  else
    echo "DID NOT RUN - $report was not written"; fail=1
  fi
done
[ "$fail" -eq 0 ] && echo "all SA-1 checks OK" || echo "SA-1 CHECKS FAILED"
exit $fail
