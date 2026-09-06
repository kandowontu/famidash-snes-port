#!/bin/sh
# What does the shim still owe the gameplay code?
#
# Links the full-gameplay TU against a main() that reaches the real entry points
# (probe/link_full.c), so the linker cannot tree-shake the game away, and prints
# the undefined symbols. That list IS the remaining SNES hardware surface.
#
#   sh tools/undef_surface.sh
set -e
CALYPSI=${CALYPSI:-/c/toolchains/calypsi/calypsi-65816-5.18}
ROOT=${ROOT:-C:/famidash}
CF="--code-model large --data-model large -O 1"
INC="-I overlay -I shim/include -I $ROOT/SAUCE -I $ROOT/LIB/headers -I $ROOT"
INC="$INC -I $ROOT/LEVELS/include/lvlset_A -I $ROOT/MUSIC/EXPORTS/lvlset_A"

mkdir -p out
python tools/gen_palette.py >/dev/null
$CALYPSI/bin/cc65816.exe $CF -c probe/probe_full.c -o out/probe_full.o $INC 2>/dev/null
$CALYPSI/bin/cc65816.exe $CF -c probe/link_full.c  -o out/link_full.o  $INC 2>/dev/null
for f in shim_core shim_state shim_ppu shim_misc shim_engine; do
  $CALYPSI/bin/cc65816.exe $CF -c shim/src/$f.c -o out/$f.o $INC 2>/dev/null
done
$CALYPSI/bin/cc65816.exe $CF -c out/nes_palette.c -o out/nes_palette.o 2>/dev/null
$CALYPSI/bin/cc65816.exe $CF -c out/level_lengths.c -o out/level_lengths.o 2>/dev/null
$CALYPSI/bin/cc65816.exe $CF -c out/level_collcols.c -o out/level_collcols.o
$CALYPSI/bin/cc65816.exe $CF -c out/level_sprites.c -o out/level_sprites.o 2>/dev/null
$CALYPSI/bin/cc65816.exe $CF -c out/level_header.c -o out/level_header.o 2>/dev/null
python tools/gen_columns.py --outdir out >/dev/null
$CALYPSI/bin/cc65816.exe $CF -c out/level_columns_meta.c -o out/level_columns_meta.o 2>/dev/null
$CALYPSI/bin/as65816.exe --core 65816 -o out/level_columns.o out/level_columns.s 2>/dev/null
# oam_spr is hand-written 65816, not C - without it in the link every caller of
# it shows up as the shim owing the game a symbol it actually provides.
$CALYPSI/bin/as65816.exe --core 65816 -o out/oam_spr.o shim/src/oam_spr.s
# The switchable sprite CHR: mmc3_set_2kb_chr_bank_* resolve against these.
python tools/gen_sprchr.py --root "$ROOT" --outdir out >/dev/null
$CALYPSI/bin/as65816.exe --core 65816 -o out/spr_chr.o out/spr_chr.s
$CALYPSI/bin/cc65816.exe $CF -c out/spr_chr_meta.c -o out/spr_chr_meta.o

$CALYPSI/bin/ln65816.exe --rom-code --output-format raw --raw-multiple-memories \
  --root-symbol snes_header --root-symbol snes_header_ext \
  -o out/undef_probe.bin src/snes-HiROM.scm \
  out/link_full.o out/probe_full.o out/shim_core.o out/shim_state.o \
  out/shim_ppu.o out/shim_misc.o out/shim_engine.o out/nes_palette.o \
  out/level_lengths.o out/level_collcols.o out/level_sprites.o out/level_header.o out/level_columns.o out/level_columns_meta.o \
  out/oam_spr.o out/spr_chr.o out/spr_chr_meta.o \
  out/metatiles_coll.o \
  out/assets.o out/snes_header.o 2>&1 \
  | grep -oE "undefined symbol '[^']*'" \
  | sed "s/undefined symbol '//;s/'//" | sort -u > out/undef.txt || true

echo "$(wc -l < out/undef.txt) symbols still undefined"
echo
cat out/undef.txt
