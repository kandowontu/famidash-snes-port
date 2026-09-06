#!/bin/sh
# Build the SNES game ROM: assets -> C -> scan -> link -> HiROM image.
set -e
CALYPSI=${CALYPSI:-/c/toolchains/calypsi/calypsi-65816-5.18}
ROOT=${ROOT:-C:/famidash}
# Which level set goes in the ROM. lvlset_HUGE is a strict superset of lvlset_A
# - all 46 of A's levels plus 122 more, 168 in total - so this is the whole game
# rather than the starter set.
LVLSET=${LVLSET:-lvlset_HUGE}
# -O 1. NOT -O 2, and the reason is measured, not assumed.
#
# Calypsi defaults to -O0 and to optimising for SPACE. Of the settings tried:
#   -O 1 (this)                    L8 86.8%  L12 85.9%  L9 79.1%
#   -O 2 --speed --no-cross-call   L8 89.2%  L12 91.0%  L9 82.3%  <- but see below
#   -O 2 (cross-call ON)           L8 75.7%  L12 68.2%            <- much worse
#
# Cross-call replaces repeated code with subroutine calls: smaller, and far
# slower. Worth knowing if -O 2 is ever revisited.
#
# -O 2 is +2 to +5 points AND MISCOMPILES the ship: the sign flip after
# gamemode_ship.h's HOLD_FALL branch is skipped, so holding while falling gives
# +62 where the table says -62, on 100% of samples. tools/verify_ship.lua
# catches it; the three scan_*.py scanners do not, so it is a fourth defect
# shape. Not worth shipping wrong physics for five points until that is worked
# around. See docs/M2_24_WHY_2X.md.
CF="--code-model large --data-model large -O 1"
INC="-I overlay -I shim/include -I out -I $ROOT/SAUCE -I $ROOT/LIB/headers -I $ROOT -I $ROOT/LEVELS/include/$LVLSET"
INC="$INC -I $ROOT/MUSIC/EXPORTS/$LVLSET"

OBJS="out/game_core.o out/shim_core.o out/snes_main.o out/metatiles_coll.o out/assets.o out/snes_header.o"

# Wrap snes_m0.py's .bin output as C arrays. out/ is gitignored, so these must be
# regenerated rather than assumed to be lying around from an earlier session.
# The level select's font - the game has no alphabet of its own.
python tools/gen_menufont.py --outdir out
python tools/gen_famidash_menus.py --root "$ROOT" --outdir out
python tools/gen_assets.py --outdir out --lvlset "$LVLSET"

# Nothing here is incremental: a stale object from a previous run links happily
# and produces a ROM that does not match the source. Start from nothing.
rm -f $OBJS out/game_core.s out/shim_core.s out/snes_main.s out/probe_full.o \
      out/probe_full.s out/rom.raw out/rom.bin

$CALYPSI/bin/cc65816.exe $CF -c probe/probe4.c        -o out/game_core.o      $INC
$CALYPSI/bin/cc65816.exe $CF -c shim/src/shim_core.c  -o out/shim_core.o      $INC
$CALYPSI/bin/cc65816.exe $CF -c shim/src/snes_main.c  -o out/snes_main.o      $INC
$CALYPSI/bin/cc65816.exe $CF -c out/metatiles_coll.c  -o out/metatiles_coll.o
$CALYPSI/bin/cc65816.exe $CF -c out/assets.c          -o out/assets.o
$CALYPSI/bin/as65816.exe --core 65816 -o out/snes_header.o shim/src/snes_header.s

# An unrecognised or misused option makes cc65816 exit 0 with a usage message and
# no object file (docs/HANDOFF.md trap 9). Confirm every object exists before the
# link, or a stale one gets picked up silently.
for o in $OBJS; do
  [ -f "$o" ] || { echo "build_game.sh: $o was not produced" >&2; exit 1; }
done

# Assembly for the scanner, in SEPARATE invocations: --assembly-source behaves
# like -S and SUPPRESSES the object file, so combining it with -c -o silently
# leaves the previous .o in place. That is how a verified ROM ended up not
# containing the fixes it was supposed to.
$CALYPSI/bin/cc65816.exe $CF -S probe/probe4.c        --assembly-source out/game_core.s $INC
$CALYPSI/bin/cc65816.exe $CF -S shim/src/shim_core.c  --assembly-source out/shim_core.s $INC
$CALYPSI/bin/cc65816.exe $CF -S shim/src/snes_main.c  --assembly-source out/snes_main.s $INC

# Calypsi 5.18 silently drops values across control-flow merges (a `?:` or a
# switch feeding one shared store). It compiles clean and produces a stable
# wrong number, so it has to be caught here rather than in a trace.
python tools/scan_stackslots.py out/game_core.s out/shim_core.s out/snes_main.s
# A cast-to-uint8_t used as an array index compiles to a SIGN extension, so any
# value >= 128 reads before the array. It corrupted every level's decompressed
# data and still drew a level that looked nearly right (trap 94).
python tools/scan_signext_index.py out/game_core.s out/shim_core.s out/snes_main.s
# The OTHER merge-point defect: the join reads the wrong REGISTER rather than an
# unwritten stack slot, so a `tya` throws away what every arm computed. It made
# the wave's vertical velocity a constant +1 - the gamemode simply did not work.
python tools/scan_merge_tya.py out/game_core.s out/shim_core.s out/snes_main.s

# --- the full game ------------------------------------------------------------
# The whole gameplay half of SAUCE/ compiles, links, and renders the level. The
# sprite engine is still stubbed, so there is no player on screen yet - see
# shim/src/shim_engine.c and docs/M2_LEVEL_RENDER.md.
python tools/gen_palette.py --root "$ROOT"
# Every level of the set, compressed, plus the tables the runtime decoder needs.
# This replaces the precomputed column stream: that cost 230KB of ROM for ONE
# level, and the whole 46-level set is 198KB of LZ.
python tools/gen_levels.py --root "$ROOT" --lvlset "$LVLSET" --outdir out
$CALYPSI/bin/as65816.exe --core 65816 -o out/level_lz.o out/level_lz.s
$CALYPSI/bin/as65816.exe --core 65816 -o out/level_spr.o out/level_spr.s
$CALYPSI/bin/cc65816.exe $CF -c out/level_table.c -o out/level_table.o
$CALYPSI/bin/cc65816.exe $CF -c out/metatile_words.c -o out/metatile_words.o
# The switchable sprite CHR banks. mmc3_set_2kb_chr_bank_0/1 DMA these into OBJ
# VRAM: on hardware with no CHR ROM a mapper bank switch is a transfer.
# The BG tilesets, one per (spike set, block set, parallax/slope) combination
# the level set actually uses. Only stereomadness's was in the ROM before, so
# 36 of the 46 levels drew the right shapes from the wrong art.
python tools/gen_bgchr.py --root "$ROOT" --lvlset "$LVLSET" --outdir out
$CALYPSI/bin/as65816.exe --core 65816 -o out/bg_chr.o out/bgchr.s
$CALYPSI/bin/cc65816.exe $CF -c out/bgchr_meta.c -o out/bgchr_meta.o
python tools/gen_sprchr.py --root "$ROOT" --outdir out
$CALYPSI/bin/as65816.exe --core 65816 -o out/spr_chr.o out/spr_chr.s
$CALYPSI/bin/cc65816.exe $CF -c out/spr_chr_meta.c -o out/spr_chr_meta.o
# The audio driver's ARAM image: the four pulse duties and the triangle as
# looping BRR, three lookup tables, and the SPC700 program that turns
# FamiStudio's eleven APU register bytes into S-DSP state. gen_spc_image.py
# assembles it with tools/spcasm.py - the toolchain has nothing that targets
# the SPC700, so the assembler is part of the port.
python tools/spcasm.py --selftest
python tools/gen_brr.py --outdir out
# Pack the original sequencer/song streams before DPCM conversion: the
# converter audits those streams for one-shot $4011 counter overrides and
# emits a distinct BRR waveform for every variant that is actually used.
python tools/gen_famistudio.py --root "$ROOT" --lvlset "$LVLSET" --outdir out
python tools/gen_dpcm_brr.py --root "$ROOT" --lvlset "$LVLSET" --outdir out
python tools/gen_spc_image.py --outdir out
$CALYPSI/bin/as65816.exe --core 65816 -o out/spc_image.o out/spc_image.s
$CALYPSI/bin/cc65816.exe $CF -c out/spc_image_meta.c -o out/spc_image_meta.o
$CALYPSI/bin/as65816.exe --core 65816 -o out/famistudio_dpcm_banks.o out/famistudio_dpcm_banks.s
$CALYPSI/bin/cc65816.exe $CF -c out/famistudio_dpcm_meta.c -o out/famistudio_dpcm_meta.o -I out
# The sequencer/song data was packed above so DPCM counter overrides could be
# included in the BRR inventory. Finish its per-song residency metadata here.
python tools/gen_song_dpcm.py --outdir out
python tools/audit_spc_instruments.py --root "$ROOT" --lvlset "$LVLSET" --outdir out
$CALYPSI/bin/as65816.exe --core 65816 -o out/famistudio_banks.o out/famistudio_banks.s
$CALYPSI/bin/as65816.exe --core 65816 -o out/famistudio_ram.o out/famistudio_ram.s
$CALYPSI/bin/cc65816.exe $CF -c out/famistudio_meta.c -o out/famistudio_meta.o -I out
$CALYPSI/bin/cc65816.exe $CF -c out/famistudio_song_dpcm.c -o out/famistudio_song_dpcm.o -I out
# The generated map assigns the absolute ROM bank used as DBR. It only depends
# on assets already generated above, so emit it before compiling shim_misc.c.
python tools/gen_linkcfg.py --outdir out
# metatiles_coll.o, assets.o and snes_header.o are shared with the small ROM and
# were already built above - they are linked into both and must NOT be deleted
# here, or the link picks up nothing.
FULL_ONLY="out/probe_full.o out/snes_main_full.o out/shim_state.o out/shim_ppu.o
           out/shim_misc.o out/shim_engine.o out/shim_spc.o out/nes_palette.o
           out/level_lengths.o out/oam_spr.o out/cache_col.o"
FULL_OBJS="$FULL_ONLY out/shim_core.o out/metatiles_coll.o out/assets.o
           out/level_lz.o out/level_spr.o out/level_table.o out/metatile_words.o
           out/snes_header.o out/spr_chr.o out/spr_chr_meta.o
           out/bg_chr.o out/bgchr_meta.o out/spc_image.o out/spc_image_meta.o
           out/famistudio_banks.o out/famistudio_ram.o out/famistudio_meta.o
           out/famistudio_song_dpcm.o"
FULL_OBJS="$FULL_OBJS out/famistudio_dpcm_banks.o out/famistudio_dpcm_meta.o"
rm -f $FULL_ONLY out/probe_full.s

$CALYPSI/bin/cc65816.exe $CF -c probe/probe_full.c         -o out/probe_full.o    $INC
$CALYPSI/bin/cc65816.exe $CF -c shim/src/snes_main_full.c  -o out/snes_main_full.o $INC
for f in shim_state shim_ppu shim_misc shim_engine shim_spc; do
  $CALYPSI/bin/cc65816.exe $CF -c shim/src/$f.c -o out/$f.o $INC
done
$CALYPSI/bin/cc65816.exe $CF -c out/nes_palette.c   -o out/nes_palette.o
$CALYPSI/bin/cc65816.exe $CF -c out/level_lengths.c -o out/level_lengths.o
$CALYPSI/bin/cc65816.exe $CF -c shim/src/shim_core.c -o out/shim_core.o $INC
# The sprite writer is hand-written 65816 - see the header in oam_spr.s for the
# measurement that justifies it and the calling convention it implements.
$CALYPSI/bin/as65816.exe --core 65816 -o out/oam_spr.o shim/src/oam_spr.s
$CALYPSI/bin/as65816.exe --core 65816 -o out/cache_col.o shim/src/cache_col.s
for o in $FULL_OBJS; do
  [ -f "$o" ] || { echo "build_game.sh: $o was not produced" >&2; exit 1; }
done

$CALYPSI/bin/cc65816.exe $CF -S probe/probe_full.c --assembly-source out/probe_full.s $INC
# Scan the shim too, not just the game code - these files are C and just as
# exposed to the merge-point defect. Leaving them out was a real gap.
for f in shim_state shim_ppu shim_misc shim_engine shim_spc; do
  $CALYPSI/bin/cc65816.exe $CF -S shim/src/$f.c --assembly-source out/$f.s $INC
done
python tools/scan_stackslots.py out/probe_full.s out/shim_state.s out/shim_ppu.s   out/shim_misc.s out/shim_engine.s out/shim_spc.s
python tools/scan_signext_index.py out/probe_full.s out/shim_state.s out/shim_ppu.s   out/shim_misc.s out/shim_engine.s out/shim_spc.s
python tools/scan_merge_tya.py out/probe_full.s out/shim_state.s out/shim_ppu.s   out/shim_misc.s out/shim_engine.s out/shim_spc.s

# The data banks are a function of the level set, so the full ROM's linker script
# is GENERATED - six banks was right for 46 levels and is not right for 168.
# gen_linkcfg.py already ran before shim_misc.c so its FAMISTUDIO_FIRST_BANK
# header could be compiled into the sequencer bridge.
$CALYPSI/bin/ln65816.exe --rom-code --output-format raw --raw-multiple-memories \
  --root-symbol snes_header --root-symbol snes_header_ext \
  --list-file out/game_full.map \
  -o out/rom_full.bin out/snes-HiROM-full.scm $FULL_OBJS
# --raw-multiple-memories writes each non-contiguous memory to its OWN raw file
# (docs/HANDOFF.md trap 38). WHICH memories get one is not fixed: the linker
# merges contiguous ROM memories, so the sprite CHR at $C3 and the six level-data
# banks above it come out as a single SpriteCHR.raw starting at $C3. pack_hirom
# skips a --part whose file is absent, and verify_rom_layout confirms what
# actually landed rather than trusting that it did.
python tools/pack_hirom.py --input out/rom_full.raw --output out/famidash-snes-full.sfc \
  --title "FAMIDASH SNES FULL" $(cat out/rom_parts.txt)
python tools/verify_rom_layout.py --rom out/famidash-snes-full.sfc

# shim_core.o was just rebuilt for the full link; the small ROM needs its own.
$CALYPSI/bin/cc65816.exe $CF -c shim/src/shim_core.c -o out/shim_core.o $INC

$CALYPSI/bin/ln65816.exe --rom-code --output-format raw --raw-multiple-memories \
  --root-symbol snes_header --root-symbol snes_header_ext \
  --list-file out/game.map \
  -o out/rom.bin src/snes-HiROM.scm $OBJS

python tools/pack_hirom.py
# WRAM symbol addresses move whenever a variable is added or removed, so the
# trace scripts read them from here rather than hardcoding. See tools/gen_addrs.py.
# BOTH maps: the full ROM has its own symbol layout, and out/addrs_full.lua was
# being written by hand once and then silently going stale - which is worse than
# hardcoding, because it still resolves and points at the wrong variable.
python tools/gen_addrs.py
python tools/gen_addrs.py --map out/game_full.map --out out/addrs_full.lua
# The gamemode oracle. It is derived from SAUCE/defines/sprites.h rather than
# from the shim, which is the point (trap 61) - and it had no generator in the
# build, so on a clean tree verify_gamemode_sprites.lua simply did not run.
python tools/gen_gamemode_expect.py --root "$ROOT" --outdir out
# The physics tables, parsed out of the game's own header for the ship check.
python tools/gen_physics_expect.py --root "$ROOT" --outdir out
# PC ranges for the profilers. Generated because they move on every build and a
# stale copy profiles whatever now sits at those addresses (traps 5, 92).
python tools/gen_instr_ranges.py
# The per-level oracle: what every level's .lz inflates to, and the tilemap
# columns it should produce. Independent of the shim, and per LEVEL - the
# byte-exact render check used to exist for stereomadness only, which is how a
# decompressor that corrupted a few bytes of all 46 levels shipped (trap 94).
python tools/gen_level_columns.py --root "$ROOT" --lvlset "$LVLSET" --outdir out --all

# ---- the SA-1 variant, opt-in with SA1=1 -----------------------------------
# The SAME object files, relinked against a memory map that puts the game's RAM
# on the cartridge instead of in $7E/$7F - which the SA-1 cannot see. The ROM
# banks are untouched: $C0-$DF is the reset-time linear 2MB HiROM window, and
# sa1_boot maps ROM megabytes 2/3 at $E0-$FF for the music banks above it.
#
# Not on by default. The main port is in a verified-good state and stays the
# thing that builds when you type `sh tools/build_game.sh`.
if [ -n "${SA1:-}" ]; then
  echo "--- SA-1 variant"
  $CALYPSI/bin/as65816.exe --core 65816 -o out/sa1_boot.o   src/sa1_boot.s
  $CALYPSI/bin/as65816.exe --core 65816 -o out/sa1_header.o src/sa1_header.s
  python tools/gen_linkcfg.py --outdir out --sa1
  # These translation units differ between the two ROMs because they touch
  # registers or direct-page state whose SA-1 and S-CPU views differ:
  #   shim_ppu.c        ppu_wait_nmi, the frame boundary, becomes a handshake
  #   shim_core.c       pad_poll reads the mailbox instead of $4218
  #   snes_main_full.c  level_select has its OWN copy of the frame boundary
  # Everything else is the same object file, which is why this link is cheap.
  #   shim_misc.c       calls wrappers that select I-RAM $0700 as D
  #   shim_spc.c        S-CPU reads that I-RAM through its $3700 mirror
  for f in shim_ppu shim_core snes_main_full shim_state shim_misc shim_spc; do
    $CALYPSI/bin/cc65816.exe $CF -D SHIM_SA1 -c shim/src/$f.c -o out/${f}_sa1.o $INC
  done

  # snes_header.o is the HiROM header and sa1_header.o is the SA-1 one; only the
  # second goes in, or two sections would claim the same address.
  SA1_OBJS=$(echo "$FULL_OBJS"     | sed -e 's#out/snes_header.o#out/sa1_header.o#'           -e 's#out/shim_ppu.o#out/shim_ppu_sa1.o#'           -e 's#out/shim_core.o#out/shim_core_sa1.o#'           -e 's#out/snes_main_full.o#out/snes_main_full_sa1.o#'           -e 's#out/shim_state.o#out/shim_state_sa1.o#'           -e 's#out/shim_misc.o#out/shim_misc_sa1.o#'           -e 's#out/shim_spc.o#out/shim_spc_sa1.o#')
  $CALYPSI/bin/ln65816.exe --rom-code --output-format raw --raw-multiple-memories \
    --root-symbol sa1_header --root-symbol sa1_header_ext \
    --list-file out/game_sa1.map \
    -o out/rom_sa1.bin out/snes-SA1-full.scm $SA1_OBJS out/sa1_boot.o
  # Same packer as the HiROM ROM - the parts and their bank offsets are
  # identical, because the ROM banks did not move. Only the header position
  # differs, because an SA-1 cartridge is LoROM-shaped.
  python tools/pack_hirom.py --input out/rom_sa1.raw --output out/famidash-sa1-full.sfc     --title "FAMIDASH SA1" --header-at 0x7FB0 $(cat out/rom_parts_sa1.txt)
  # The SA-1 ROM has its own symbol layout, and a stale addrs file does not fail
  # loudly - it resolves to the wrong function and the trace scripts report
  # confident nonsense.
  python tools/gen_addrs.py --map out/game_sa1.map --out out/addrs_sa1.lua
fi
