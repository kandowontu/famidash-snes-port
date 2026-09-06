#!/bin/sh
# Build the SA-1 probe ROM.
#
# Deliberately separate from build_game.sh. The SA-1 work changes the cartridge
# header, the ROM shape and the memory map all at once, and the port is in a
# verified-good state that should stay buildable while this is figured out.
set -e
CALYPSI=${CALYPSI:-/c/toolchains/calypsi/calypsi-65816-5.18}
mkdir -p out

$CALYPSI/bin/as65816.exe --core 65816 -o out/sa1_header.o src/sa1_header.s

$CALYPSI/bin/as65816.exe --core 65816 -o out/sa1_probe.o  src/sa1_probe.s
$CALYPSI/bin/ln65816.exe --rom-code --output-format raw --raw-multiple-memories \
  --root-symbol sa1_header --root-symbol sa1_header_ext \
  --list-file out/sa1.map \
  -o out/sa1.bin src/snes-SA1.scm out/sa1_probe.o out/sa1_header.o

# The four ROM memories are contiguous ($8000-$FFFF), so the linker merges them
# into one raw - which is already the whole cartridge image for a LoROM-shaped
# map, once it is padded out and the checksum fixed.
python tools/pack_lorom.py --input out/sa1.raw --output out/famidash-sa1.sfc --size 0x8000

# The benchmark shares the header and the linker rules; only the code differs.
$CALYPSI/bin/as65816.exe --core 65816 -o out/sa1_bench.o src/sa1_bench.s
$CALYPSI/bin/ln65816.exe --rom-code --output-format raw --raw-multiple-memories \
  --root-symbol sa1_header --root-symbol sa1_header_ext \
  --list-file out/sa1_bench.map \
  -o out/sa1_bench.bin src/snes-SA1.scm out/sa1_bench.o out/sa1_header.o
python tools/pack_lorom.py --input out/sa1_bench.raw --output out/famidash-sa1-bench.sfc --size 0x8000

# The same image again as a plain LoROM FastROM cartridge with no SA-1 in it.
# Only run A can execute there - which is the point: it is the only way to time
# the S-CPU against the 3.58MHz clock the port actually ships on. The SA-1 map
# mode has no FastROM bit, so timing run A on the SA-1 cartridge measures it at
# 2.68MHz and flatters every SA-1 ratio by a quarter.
python tools/pack_lorom.py --input out/sa1_bench.raw --output out/famidash-sa1-base.sfc   --size 0x8000 --mapmode 0x30 --chipset 0x00

# ---- C on the SA-1 --------------------------------------------------------
# The same compiler settings as the port (build_game.sh): -O 1 for the reason
# recorded in docs/M2_24_WHY_2X.md section 4, and the large models because the
# game's pointers have to reach BW-RAM at $40:0000.
CF="--code-model large --data-model large -O 1"
$CALYPSI/bin/cc65816.exe $CF -c src/sa1_ccheck.c -o out/sa1_ccheck.o
$CALYPSI/bin/as65816.exe --core 65816 -o out/sa1_boot.o src/sa1_boot.s
$CALYPSI/bin/ln65816.exe --rom-code --output-format raw --raw-multiple-memories \
  --root-symbol sa1_header --root-symbol sa1_header_ext \
  --list-file out/sa1_c.map \
  -o out/sa1_c.bin src/snes-SA1-c.scm out/sa1_ccheck.o out/sa1_boot.o out/sa1_header.o
python tools/pack_lorom.py --input out/sa1_c.raw --output out/famidash-sa1-c.sfc --size 0x8000

# ---- the SA-1's view of a 2MB ROM ------------------------------------------
# A 2MB image whose padding is stamped block by block, so the probe can name
# which part of the ROM answered each address. The header must declare 2MB or an
# emulator that trusts the field will truncate the image and the far blocks read
# back as nothing.
$CALYPSI/bin/cc65816.exe $CF -c src/sa1_rommap.c -o out/sa1_rommap.o
$CALYPSI/bin/ln65816.exe --rom-code --output-format raw --raw-multiple-memories \
  --root-symbol sa1_header --root-symbol sa1_header_ext \
  --list-file out/sa1_rommap.map \
  -o out/sa1_rommap.bin src/snes-SA1-c.scm out/sa1_rommap.o out/sa1_boot.o out/sa1_header.o
python tools/pack_lorom.py --input out/sa1_rommap.raw --output out/famidash-sa1-rommap.sfc \
  --size 0x200000 --stamp --romsize 0x0B
