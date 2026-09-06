#!/usr/bin/env python3
"""Emit the FULL ROM's linker script, with as many data banks as the set needs.

`src/snes-HiROM.scm` has the level banks written out by hand, six of them, which
was fine for one 46-level set and is not fine for a 168-level one. The number of
banks is a function of the data, so it is computed from the data:

  * the level LZ and sprite streams are emitted as one section PER LEVEL, so
    they are bin-packed into 64KB banks - and the packing has to be simulated,
    not divided, because a level that does not fit in the space left in a bank
    goes to the next one and leaves that space empty;
  * a level must not straddle a bank, because it is read through one far
    pointer and DMA does not carry into the bank byte (docs/HANDOFF.md traps 37
    and 39). Per-bank memories are what makes that impossible rather than
    unlikely.

Also emits out/rom_parts.txt - the `--part` arguments pack_hirom.py needs, one
per data memory. Which memories actually get their own `.raw` is not fixed
(trap 38), and pack_hirom skips a part whose file is absent, so listing them all
is correct either way.

    python tools/gen_linkcfg.py --outdir out
"""
import argparse
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BANK = 0x10000

CODE_BANKS = 3          # $C0-$C2: HiROM-c0 plus HiROM
FIRST_DATA_BANK = 0xC0 + CODE_BANKS


def first_fit_banks(sizes):
    """How many 64KB banks these sections need, packed the way the linker does.

    Descending first-fit is not what the linker does either, but it is a lower
    bound; sections are placed in order, so that is what is simulated.
    """
    banks = [0]
    for n in sizes:
        if n > BANK:
            sys.exit(f"a section of {n} bytes cannot fit in a 64KB bank")
        for i, used in enumerate(banks):
            if used + n <= BANK:
                banks[i] = used + n
                break
        else:
            banks.append(n)
    return len(banks)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default=str(ROOT / "out"))
    ap.add_argument("--sa1", action="store_true",
                    help="emit the SA-1 variant instead: same ROM banks, but "
                         "RAM re-homed to I-RAM and BW-RAM, because the SA-1 "
                         "cannot see $7E/$7F WRAM at all")
    ap.add_argument("--spare", type=int, default=2,
                    help="extra level banks, so a small data change need not "
                         "reshuffle the layout")
    args = ap.parse_args()
    outdir = Path(args.outdir)

    spr = sorted(outdir.glob("sprchr*.bin"))
    bg = (sorted(outdir.glob("bgchr[0-9]*.bin"))
          + sorted(outdir.glob("bgchr_alt*.bin")))
    lvl = ([p.stat().st_size for p in sorted(outdir.glob("level_lz_*.bin"))]
           + [p.stat().st_size for p in sorted(outdir.glob("level_spr_*.bin"))])
    if not spr or not bg or not lvl:
        sys.exit("run gen_levels.py, gen_bgchr.py and gen_sprchr.py first")

    spr_banks = math.ceil(sum(p.stat().st_size for p in spr) / BANK)
    bg_shared = [
        outdir / "parallax.tiles.bin",
        outdir / "parallax.map.top.bin",
        outdir / "parallax.map.bottom.bin",
        outdir / "saw0.bin",
        outdir / "saw1.bin",
        outdir / "saw_none.bin",
    ]
    if not all(p.exists() for p in bg_shared):
        sys.exit("run gen_bgchr.py before gen_linkcfg.py (shared BG assets missing)")
    bg_banks = math.ceil(
        (sum(p.stat().st_size for p in bg)
         + sum(p.stat().st_size for p in bg_shared)) / BANK)
    lvl_banks = first_fit_banks(lvl) + args.spare
    fs_layout = outdir / "famistudio_layout.py"
    if not fs_layout.exists():
        sys.exit("run gen_famistudio.py before gen_linkcfg.py")
    fs_vars = {}
    exec(fs_layout.read_text(), fs_vars)
    fs_banks = int(fs_vars["FS_BANK_COUNT"])
    dpcm_layout = outdir / "famistudio_dpcm_layout.py"
    if not dpcm_layout.exists():
        sys.exit("run gen_dpcm_brr.py before gen_linkcfg.py")
    dpcm_vars = {}
    exec(dpcm_layout.read_text(), dpcm_vars)
    dpcm_sizes = [int(n) for n in dpcm_vars["DPCM_BANK_SIZES"]]
    dpcm_banks = first_fit_banks(dpcm_sizes)

    out, parts = [], []
    bank = FIRST_DATA_BANK

    def memory(name, nbanks, section, note):
        nonlocal bank
        for i in range(nbanks):
            label = f"{name}{i}" if nbanks > 1 else name
            lo, hi = bank << 16, (bank << 16) | 0xFFFF
            out.append(f"        ;; {note if i == 0 else ''}".rstrip())
            out.append(f"        (memory {label}")
            out.append(f"                (address (#x{lo:06x} . #x{hi:06x}))")
            out.append("                (type ROM)")
            out.append("                (qualifier far)")
            out.append(f"                (section {section}))")
            parts.append(f"--part out/{label}.raw@0x{bank:02X}")
            bank += 1

    # The two heads differ only in where the RAM lives and where the boot block
    # is scattered to; the generated data banks below are identical, which is
    # the whole point of generating them from the data rather than the map.
    head_file = "snes-SA1-game.scm" if args.sa1 else "snes-HiROM.scm"
    head = (ROOT / "src" / head_file).read_text()
    # Everything up to the first data memory is identical for both ROMs.
    keep = head[:head.index("        ;; Switchable sprite CHR")]
    out.append(keep.rstrip("\n"))
    out.append("")
    out.append("        ;; GENERATED by tools/gen_linkcfg.py - do not edit.")
    out.append(f"        ;; {len(spr)} sprite CHR banks, {len(bg)} BG tilesets, "
               f"{len(lvl)} level sections.")
    out.append("")

    memory("SpriteCHR", spr_banks, "sprchr",
           "Switchable sprite CHR (tools/gen_sprchr.py). 4KB blocks, DMA'd into "
           "OBJ VRAM; 4KB divides a bank so none can straddle one.")
    memory("BGCHR", bg_banks, "bgchr",
           "The BG tilesets (tools/gen_bgchr.py), one per level-load.")
    memory("LevelData", lvl_banks, "lvldata",
           "Every level of the set, one section per stream, one memory per bank "
           "so no level can straddle a bank boundary.")

    # Every bank is a complete 64KB section with the 6502 engine/constants
    # mirrored at the same low addresses.  Calypsi will not split one section
    # across CPU banks, so each generated image has its own section and memory.
    fs_first_bank = bank
    for i in range(fs_banks):
        lo, hi = bank << 16, (bank << 16) | 0xFFFF
        out.append("        ;; Original FamiStudio sequencer, SFX and song "
                   "data." if i == 0 else "        ;;")
        out.append(f"        (memory FamiStudioMusic{i}")
        out.append(f"                (address (#x{lo:06x} . #x{hi:06x}))")
        out.append("                (type ROM)")
        out.append("                (qualifier far)")
        out.append(f"                (section fsmusic{i}))")
        parts.append(f"--part out/FamiStudioMusic{i}.raw@0x{bank:02X}")
        bank += 1

    memory("FamiStudioDPCM", dpcm_banks, "fsdpcm",
           "Original Famidash .dmc instruments converted sample-by-sample to "
           "BRR. The linker first-fits the twelve resident-bank sections.")

    (outdir / "famistudio_rom_bank.h").write_text(
        "/* Generated by tools/gen_linkcfg.py - do not edit. */\n"
        f"#define FAMISTUDIO_FIRST_BANK 0x{fs_first_bank:02X}\n"
        f"#define FAMISTUDIO_ROM_BANK_COUNT {fs_banks}\n")
    (outdir / "famistudio_rom_bank.lua").write_text(
        "-- Generated by tools/gen_linkcfg.py - do not edit.\n"
        f"return {{ first = 0x{fs_first_bank:02X}, count = {fs_banks} }}\n")

    out.append("")
    out.append("        (base-address _DirectPageStart DirectPage 0)")
    out.append("        (base-address _NearBaseAddress %s 0)"
               % ("NearRAM" if args.sa1 else "LoRAM"))
    out.append("    ))")
    name = "snes-SA1-full.scm" if args.sa1 else "snes-HiROM-full.scm"
    (outdir / name).write_text("\n".join(out) + "\n")
    # Separate parts lists: the two ROMs have the same data banks but are packed
    # by different packers, and one file overwritten by the other build would be
    # wrong in a way that only shows up as a corrupt ROM.
    parts_name = "rom_parts_sa1.txt" if args.sa1 else "rom_parts.txt"
    (outdir / parts_name).write_text(" ".join(parts) + "\n")

    total = bank - 0xC0
    print(f"    {name}: {spr_banks} sprite CHR + {bg_banks} BG CHR "
          f"+ {lvl_banks} level + {fs_banks} music + {dpcm_banks} DPCM "
          f"bank(s), "
          f"$C0-${bank - 1:02X} ({total * 64}KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
