#!/bin/sh
# Build the Calypsi merge-point reproducer and show that it is miscompiled.
# Run from the repo root: sh bugreport/make_repro.sh
set -e
CALYPSI=${CALYPSI:-/c/toolchains/calypsi/calypsi-65816-5.18}
ROOT=${ROOT:-C:/famidash}
CF="--code-model large --data-model large -O 1"
INC="-I bugreport -I overlay -I shim/include -I $ROOT/SAUCE -I $ROOT/LIB/headers -I $ROOT -I $ROOT/LEVELS/include/lvlset_A"

# cc65816 -E writes to stdout and exits nonzero even on success, so it is not
# allowed to abort the script.
$CALYPSI/bin/cc65816.exe $CF -E bugreport/repro_calypsi.c $INC > bugreport/repro_calypsi.i 2>/dev/null || true
$CALYPSI/bin/cc65816.exe $CF -c bugreport/repro_calypsi.c -o out/repro.o \
  --assembly-source bugreport/repro_calypsi.s $INC 2>/dev/null

echo
echo "Suspect stack-slot reads (each is a lost value):"
python tools/scan_stackslots.py bugreport/repro_calypsi.s || true
echo
echo "Preprocessed TU for reporting upstream: bugreport/repro_calypsi.i"
