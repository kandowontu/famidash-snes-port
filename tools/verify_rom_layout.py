#!/usr/bin/env python3
"""Is the bulk data actually IN the packed ROM, at an address DMA can reach?

This is the guard for docs/HANDOFF.md trap 38. `--raw-multiple-memories` writes
a memory to its own `.raw` file only when it is not contiguous with the main
image, and whether it is contiguous depends on what else the linker placed in
between - so whether pack_hirom.py needs to splice a given memory back in is not
a fixed property of the build. Everything links either way, the map looks right
either way, and the difference is a ROM with a hole in it.

So rather than assume, check the finished image:

  * the level column stream is present and matches out/level_columns*.bin;
  * every sprite CHR bank is present and matches out/sprchr*.bin;
  * every generated 64KB FamiStudio bank is present at its assigned DBR bank;
  * every converted DPCM source bank is present and contained in one ROM bank;
  * no sprite CHR bank straddles a 64KB ROM bank, because DMA increments the
    A-bus address within a bank and does not carry into the bank byte (trap 37)
    - a block that straddled would wrap to the start of its own bank part way
    through the transfer.

    python tools/verify_rom_layout.py [--rom out/famidash-snes-full.sfc]
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom", default=str(ROOT / "out" / "famidash-snes-full.sfc"))
    ap.add_argument("--outdir", default=str(ROOT / "out"))
    args = ap.parse_args()

    rom = Path(args.rom).read_bytes()
    outdir = Path(args.outdir)
    bad = 0

    print(f"{Path(args.rom).name}: {len(rom)} bytes "
          f"(HiROM banks $C0-${0xC0 + len(rom) // 65536 - 1:02X})")

    # --- every level's compressed data --------------------------------------
    parts = sorted(outdir.glob("level_lz_*.bin"))
    if not parts:
        print("!! no out/level_lz_*.bin - run tools/gen_levels.py first")
        return 1
    missing, straddle_lvl = [], []
    for p in parts:
        data = p.read_bytes()
        at = rom.find(data)
        if at < 0:
            missing.append(p.stem)
            continue
        # A level is read through one pointer, so it must not cross a bank -
        # whether a far pointer increment carries into the bank byte is not
        # something to rely on.
        if (at >> 16) != ((at + len(data) - 1) >> 16):
            straddle_lvl.append(f"{p.stem} at 0x{at:06X}")
    if missing:
        print(f"  {len(missing)} level streams NOT IN THE ROM: {missing[:6]}")
        bad += len(missing)
    if straddle_lvl:
        print(f"  {len(straddle_lvl)} levels straddle a ROM bank: {straddle_lvl[:4]}")
        bad += len(straddle_lvl)
    if not missing and not straddle_lvl:
        print(f"  {len(parts)} level streams present, none straddling a bank")

    # The level headers name songs symbolically. This table used to contain
    # 168 zeroes because the generator only resolved graphics defines, which
    # made every level play the same track even though all 132 songs were in
    # ROM. Check the final linked bytes, not only the generated Lua oracle.
    song_lua = outdir / "level_song.lua"
    map_name = ("game_sa1.map" if "sa1" in Path(args.rom).name.lower()
                else "game_full.map")
    map_path = outdir / map_name
    if song_lua.exists() and map_path.exists():
        expected = [int(x) for x in re.findall(
            r"\b\d+\b", song_lua.read_text().split("{", 1)[1])]
        sym = re.search(r"^\s*lvl_song\s*=\s*([0-9A-Fa-f]{6})\s*$",
                        map_path.read_text(), re.MULTILINE)
        if not sym:
            print(f"!! cannot find lvl_song in {map_name}")
            bad += 1
        else:
            address = int(sym.group(1), 16)
            at = ((address >> 16) - 0xC0) * 0x10000 + (address & 0xFFFF)
            actual = list(rom[at:at + len(expected)])
            if actual != expected:
                print("  level song table is missing/wrong in the ROM")
                bad += 1
            else:
                print(f"  {len(expected)} level song IDs match "
                      f"({len(set(expected))} distinct songs)")
    else:
        print("!! no level song oracle or linker map")
        bad += 1

    sprs = sorted(outdir.glob("level_spr_*.bin"))
    miss_s = [p.stem for p in sprs if rom.find(p.read_bytes()) < 0]
    if miss_s:
        print(f"  {len(miss_s)} sprite streams NOT IN THE ROM: {miss_s[:6]}")
        bad += len(miss_s)
    else:
        print(f"  {len(sprs)} sprite streams present")

    # --- the BG tilesets -----------------------------------------------------
    # Added after five of fifteen went missing from a ROM that linked, packed
    # and passed every other check: the linker emitted BOTH a merged raw holding
    # all of them and a truncated per-memory raw holding two thirds, and the
    # packer spliced the truncated one over the good data.
    bgs = (sorted(outdir.glob("bgchr[0-9]*.bin"),
                  key=lambda q: int(q.stem[5:]))
           + sorted(outdir.glob("bgchr_alt*.bin"),
                    key=lambda q: int(q.stem[9:])))
    if bgs:
        miss_bg, straddle_bg = [], []
        for p in bgs:
            data = p.read_bytes()
            at = rom.find(data)
            if at < 0:
                miss_bg.append(p.stem)
            elif (at >> 16) != ((at + len(data) - 1) >> 16):
                straddle_bg.append(f"{p.stem} at 0x{at:06X}")
        if miss_bg:
            print(f"  {len(miss_bg)} BG tilesets NOT IN THE ROM: {miss_bg[:8]}")
            bad += len(miss_bg)
        if straddle_bg:
            print(f"  {len(straddle_bg)} BG tilesets straddle a ROM bank: "
                  f"{straddle_bg[:4]}")
            bad += len(straddle_bg)
        if not miss_bg and not straddle_bg:
            print(f"  {len(bgs)} BG tilesets present, none straddling a bank")

    # --- the switchable sprite CHR ------------------------------------------
    banks = sorted(outdir.glob("sprchr*.bin"),
                   key=lambda q: int(q.stem[6:]))
    if not banks:
        print("!! no out/sprchr*.bin - run tools/gen_sprchr.py first")
        return 1
    straddling = []
    for p in banks:
        data = p.read_bytes()
        at = rom.find(data)
        if at < 0:
            print(f"  {p.name}: NOT IN THE ROM")
            bad += 1
            continue
        if (at >> 16) != ((at + len(data) - 1) >> 16):
            straddling.append(f"{p.name} at 0x{at:06X}")
    if straddling:
        print("  sprite CHR banks that STRADDLE a ROM bank (DMA would wrap):")
        for s in straddling:
            print(f"    {s}")
        bad += len(straddling)
    else:
        first = rom.find(banks[0].read_bytes())
        print(f"  {len(banks)} sprite CHR banks present, none straddling a bank "
              f"(first at 0x{first:06X})")

    # --- original FamiStudio sequencer/song banks ---------------------------
    music = sorted(outdir.glob("famistudio_bank[0-9].bin"),
                   key=lambda q: int(q.stem.replace("famistudio_bank", "")))
    bank_header = outdir / "famistudio_rom_bank.h"
    if not music or not bank_header.exists():
        print("!! no generated FamiStudio banks/map - run gen_famistudio.py "
              "and gen_linkcfg.py first")
        bad += 1
    else:
        m = re.search(r"FAMISTUDIO_FIRST_BANK\s+0x([0-9A-Fa-f]+)",
                      bank_header.read_text())
        if not m:
            print("!! cannot parse FAMISTUDIO_FIRST_BANK")
            bad += 1
        else:
            first_bank = int(m.group(1), 16)
            wrong = []
            for i, p in enumerate(music):
                at = (first_bank - 0xC0 + i) << 16
                data = p.read_bytes()
                if len(data) != 0x10000 or rom[at:at + 0x10000] != data:
                    wrong.append(p.name)
            if wrong:
                print(f"  {len(wrong)} FamiStudio banks missing/wrong: "
                      f"{wrong[:6]}")
                bad += len(wrong)
            else:
                print(f"  {len(music)} FamiStudio banks match at "
                      f"${first_bank:02X}-${first_bank + len(music) - 1:02X}")

    # --- original DPCM instruments, sample-by-sample BRR -------------------
    dpcm = sorted((outdir / "brr").glob("dpcm_bank*.brr"),
                  key=lambda q: int(q.stem.replace("dpcm_bank", "")))
    missing_dpcm, straddle_dpcm = [], []
    for p in dpcm:
        data = p.read_bytes()
        at = rom.find(data)
        if at < 0:
            missing_dpcm.append(p.name)
        elif (at >> 16) != ((at + len(data) - 1) >> 16):
            straddle_dpcm.append(f"{p.name} at 0x{at:06X}")
    if not dpcm:
        print("!! no converted DPCM BRR banks - run gen_dpcm_brr.py")
        bad += 1
    elif missing_dpcm or straddle_dpcm:
        if missing_dpcm:
            print(f"  {len(missing_dpcm)} DPCM BRR banks missing: "
                  f"{missing_dpcm[:6]}")
            bad += len(missing_dpcm)
        if straddle_dpcm:
            print(f"  {len(straddle_dpcm)} DPCM BRR banks straddle ROM: "
                  f"{straddle_dpcm[:4]}")
            bad += len(straddle_dpcm)
    else:
        print(f"  {len(dpcm)} DPCM BRR source banks present, none straddling")

    print("RESULT: ROM LAYOUT OK" if bad == 0
          else f"RESULT: FAIL - {bad} problem(s)")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
