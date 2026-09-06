#!/bin/sh
# Compile the full-gameplay probe TU and summarise what is still broken.
# This is the scope meter for "port the rest of the code".
#
#   sh tools/probe_full.sh            # summary
#   sh tools/probe_full.sh -v         # full compiler output
CALYPSI=${CALYPSI:-/c/toolchains/calypsi/calypsi-65816-5.18}
ROOT=${ROOT:-C:/famidash}
CF="--code-model large --data-model large -O 1"
INC="-I overlay -I shim/include -I $ROOT/SAUCE -I $ROOT/LIB/headers -I $ROOT"
INC="$INC -I $ROOT/LEVELS/include/lvlset_A -I $ROOT/MUSIC/EXPORTS/lvlset_A"

mkdir -p out
$CALYPSI/bin/cc65816.exe $CF -c probe/probe_full.c -o out/probe_full.o $INC \
  > out/probe_full.log 2>&1

if [ "$1" = "-v" ]; then
  cat out/probe_full.log
  exit 0
fi

echo "errors:   $(grep -c ' error: ' out/probe_full.log)"
echo "warnings: $(grep -c ' warning: ' out/probe_full.log)"
echo
echo "distinct error kinds:"
grep ' error: ' out/probe_full.log \
  | sed 's/.* error: //' \
  | sed "s/'[^']*'/'X'/g" \
  | sort | uniq -c | sort -rn | head -25
echo
echo "errors per file:"
grep ' error: ' out/probe_full.log \
  | sed 's/:[0-9]*:[0-9]*: error: .*//' \
  | sort | uniq -c | sort -rn | head -25
