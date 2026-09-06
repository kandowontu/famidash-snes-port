#!/usr/bin/env python3
"""The BG tilesets the level set actually uses, one 8KB block per phase.

Only ONE tileset was ever in the ROM - stereomadness's - because `snes_m0.py`
builds `bg1.tiles.bin` for a single level. Ten of the 46 levels happen to use
that combination; the other 36 rendered with the wrong tiles, which is what the
levels looked like: the right shapes drawn from the wrong art.

On the NES the BG pattern table is four switchable 1KB banks (`_set_tile_banks`
in LIB/asm/neslib.s):

    bank0  tiles $00-$3F   current_spike_set   from the level header
    bank1  tiles $40-$7F   current_block_set   from the level header
    bank2  tiles $80-$BF   parallax, or the SLOPE set chosen by the block set
                           when the level disables parallax
    bank3  tiles $C0-$FF   current_saw_set     SAWBLADESA for every level here

The SNES has no CHR ROM, so a bank switch is a transfer. The static spike,
block and slope art changes at level load. Parallax is emitted separately for
BG2, where a hardware scroll replaces the NES's 144 pre-shifted banks. The two
saw banks are emitted separately as the original rotation frames.

The combinations are enumerated from the level headers rather than assumed: this
set needs ten, 40KB in total. Emits

    out/bgchr.s        one .incbin section per tileset, in section `bgchr`
    out/bgchr_meta.c   bg_tileset_ptr[] and lvl_bg_tileset[] (per level)
    out/bgchr<n>.bin   phase 0 blocks, for tools/verify_rom_layout.py
    out/bgchr_alt<n>.bin phase 1 blocks; the SNES switches BG1 char base
    out/parallax.*.bin BG2 tiles and the 64x64 staggered map
    out/saw*.bin       the two rotating-saw frames and the empty special set

    python tools/gen_bgchr.py --root C:/famidash --outdir out
"""
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import snes_m0 as m                                     # noqa: E402
import gen_levels as g                                  # noqa: E402

# Which slope bank _set_tile_banks picks, by block set. The routine tests
# BLOCKSD then BLOCKSB and falls through to SLOPESA, so BLOCKSA and BLOCKSC both
# land on SLOPESA.
SLOPE_FOR_BLOCK = {6: 'SLOPESA', 8: 'SLOPESB', 10: 'SLOPESA', 12: 'SLOPESD'}
SLOPE_BANK = {'SLOPESA': 16, 'SLOPESB': 88, 'SLOPESD': 90}
SLOPE_FILE = {16: 'slopesA.chr', 88: 'slopesB.chr', 90: 'slopesD.chr'}
SAWBLADESA = 14
PARALLAX = 'GRAPHICS/parallax.chr'
SAW_FILE = 'GRAPHICS/Level Tiles/SawbladesA.chr'
SAW_NONE_FILE = 'GRAPHICS/Level Tiles/SawbladesNone.chr'

# palBrightTable3, via the same parser gen_palette.py uses - the darkening is a
# lookup, not arithmetic.
from gen_palette import parse_darken                    # noqa: E402

HEIGHT = g.HEADER_FIELDS.index("height")
SPIKE_BLOCK = g.HEADER_FIELDS.index("spike_block")
PLAT_PARALLAX = g.HEADER_FIELDS.index("platformer_parallax")


def bank1k(root: Path, bank_no: int) -> bytes:
    """One 1KB CHR bank. Bank N is CHR ROM offset N*1024, and the .chr files are
    2KB each, so an odd bank is the second half of its file."""
    files = dict(m.CHR_FILES)
    files.update({k: v for k, v in SLOPE_FILE.items()})
    data = (root / 'GRAPHICS' / 'Level Tiles' / files[bank_no & ~1]).read_bytes()
    half = (bank_no & 1) * 1024
    return data[half:half + 1024]


def tileset_key(header):
    """(spike, block, bank2) for one level's header."""
    sb = header[SPIKE_BLOCK]
    spike, block = sb >> 4, sb & 0x0F
    no_parallax = header[PLAT_PARALLAX] >> 1
    bank2 = SLOPE_FOR_BLOCK.get(block, 'SLOPESA') if no_parallax else 'PARALLAX'
    return (spike, block, bank2)


def build(root: Path, key, phase: int):
    spike, block, bank2 = key
    out = bytearray()
    out += bank1k(root, spike + phase)
    out += bank1k(root, block + phase)
    if bank2 == 'PARALLAX':
        # These cells are transparent on BG1 in the SNES port, but preserve the
        # original first two shifted banks for any non-hole tile references.
        par = (root / PARALLAX).read_bytes()
        out += par[phase * 1024:(phase + 1) * 1024]
    else:
        out += bank1k(root, SLOPE_BANK[bank2] + phase)
    out += bank1k(root, SAWBLADESA + phase)
    return bytes(out)


# Relative tile numbers from nesdash.s's ParallaxBuffer. The NES substituted
# these into otherwise empty BG1 cells. On SNES those cells are transparent and
# this exact pattern lives behind them on BG2.
PARALLAX_COLS = (
    (0x00, 0x10, 0x20, 0x30, 0x06, 0x16, 0x26, 0x36, 0x0C),
    (0x01, 0x11, 0x21, 0x31, 0x07, 0x17, 0x27, 0x37, 0x0D),
    (0x02, 0x12, 0x22, 0x32, 0x08, 0x18, 0x28, 0x38, 0x0E),
    (0x03, 0x13, 0x23, 0x33, 0x09, 0x19, 0x29, 0x39, 0x1C),
    (0x04, 0x14, 0x24, 0x34, 0x0A, 0x1A, 0x2A, 0x3A, 0x1D),
    (0x05, 0x15, 0x25, 0x35, 0x0B, 0x1B, 0x2B, 0x3B, 0x1E),
)


def emit_layer_assets(root: Path, outdir: Path, asm):
    """Emit the art whose NES animation/banking becomes SNES-native state."""
    par_nes = (root / PARALLAX).read_bytes()[:1024]
    par_snes = m.nes_chr_to_snes_4bpp(par_nes)
    (outdir / "parallax.tiles.bin").write_bytes(par_snes)

    # BG2 is 64x64: four 32x32 screen blocks in SNES TL/TR/BL/BR order. A
    # 64x32 map wrapped vertically at 256px; Stereo Madness starts at VOFS 238,
    # so that wrap cut through the top 18 pixels of every frame and restarted
    # the nine-row motif at the wrong phase. The 512px map covers the complete
    # vertical camera window without an on-screen wrap.
    #
    # Horizontally the motif repeats after 18 columns (three six-column blocks,
    # shifted 3 rows each). BG2HOFS stays within that 144-pixel period, so the
    # visible 32 columns never reach the hardware wrap at column 64.
    words = []
    for screen_y in range(2):
        for screen_x in range(2):
            for local_y in range(32):
                y = screen_y * 32 + local_y
                for local_x in range(32):
                    x = screen_x * 32 + local_x
                    col = x % 6
                    phase = ((x // 6) * 3) % 9
                    # Mode 1 BG1/BG2 share the 4bpp palette space. BG1 uses
                    # NES palettes 0-3; reserve palette 4 for parallax.
                    words.append(PARALLAX_COLS[col][(y + phase) % 9] | 0x1000)
    par_map = bytearray()
    for word in words:
        par_map += int(word).to_bytes(2, "little")
    assert len(par_map) == 8192
    (outdir / "parallax.map.bin").write_bytes(par_map)
    # The map and widened 4bpp art total 16KB and are counted with BGCHR.
    (outdir / "parallax.map.top.bin").write_bytes(par_map[:4096])
    (outdir / "parallax.map.bottom.bin").write_bytes(par_map[4096:])

    saw = (root / SAW_FILE).read_bytes()
    assert len(saw) == 2048
    for frame in range(2):
        data = m.nes_chr_to_snes_4bpp_opaque(
            saw[frame * 1024:(frame + 1) * 1024], blank_tile=0x3E)
        (outdir / f"saw{frame}.bin").write_bytes(data)
    saw_none = m.nes_chr_to_snes_4bpp_opaque(
        (root / SAW_NONE_FILE).read_bytes()[:1024], blank_tile=0x3E)
    (outdir / "saw_none.bin").write_bytes(saw_none)

    # Keep shared BG graphics in the same section as the phase pairs. The link
    # generator includes these files in its bank count; SpriteCHR therefore
    # remains within its own 64KB bank.
    asm += [
        "        .section bgchr,text,root",
        "        .public parallax_tiles",
        "parallax_tiles:",
        '        .incbin "out/parallax.tiles.bin"',
        "",
        "        .public parallax_map",
        "parallax_map:",
        '        .incbin "out/parallax.map.top.bin"',
        "",
        "        .public saw_tiles_0",
        "saw_tiles_0:",
        '        .incbin "out/saw0.bin"',
        "",
        "        .public saw_tiles_1",
        "saw_tiles_1:",
        '        .incbin "out/saw1.bin"',
        "",
        "        .public saw_tiles_none",
        "saw_tiles_none:",
        '        .incbin "out/saw_none.bin"',
        "",
        "        .public parallax_map_bottom",
        "parallax_map_bottom:",
        '        .incbin "out/parallax.map.bottom.bin"',
        "",
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="C:/famidash")
    ap.add_argument("--lvlset", default="lvlset_A")
    ap.add_argument("--outdir", default=str(ROOT / "out"))
    args = ap.parse_args()
    root, outdir = Path(args.root), Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    # A smaller level set must not leave numbered tilesets from an earlier
    # build behind: gen_linkcfg deliberately inventories these files.
    for stale in outdir.glob("bgchr[0-9]*.bin"):
        stale.unlink()
    for stale in outdir.glob("bgchr_alt[0-9]*.bin"):
        stale.unlink()

    lvldir = root / "LEVELS/include" / args.lvlset / "EXPORTS/level"
    order = g.parse_level_order(root, args.lvlset)
    headers = g.parse_all_headers(root, args.lvlset, order)
    kept = [n for n in order
            if (lvldir / f"{n}.lz.bin").exists() and n in headers]

    keys, per_level = [], []
    for n in kept:
        k = tileset_key(headers[n])
        if k not in keys:
            keys.append(k)
        per_level.append(keys.index(k))

    asm = ["; Generated by tools/gen_bgchr.py - do not edit.",
           f"; {len(keys)} BG tileset pairs, 8KB per phase (Mode 1 4bpp).", ""]
    for i, k in enumerate(keys):
        for phase in range(2):
            nes = build(root, k, phase)
            assert len(nes) == 4096, (k, phase, len(nes))
            # Tile $FE is unused by every generated metatile and becomes the
            # one truly transparent BG1 tile. Every normal NES pixel 0 widens
            # to opaque SNES index 4 so BG2 cannot leak through solid art.
            snes = m.nes_chr_to_snes_4bpp_opaque(nes, blank_tile=0xFE)
            roundtrip = m.snes_4bpp_to_nes_chr(snes)
            keep_before = 0xFE * 16
            keep_after = 0xFF * 16
            if (roundtrip[:keep_before] != nes[:keep_before]
                    or roundtrip[keep_after:] != nes[keep_after:]):
                sys.exit(f"bgchr{i} phase {phase}: conversion is not lossless")
            stem = f"bgchr{i}" if phase == 0 else f"bgchr_alt{i}"
            symbol = f"bg_tiles_{i}" if phase == 0 else f"bg_tiles_alt_{i}"
            (outdir / f"{stem}.bin").write_bytes(bytes(snes))
            asm += ["        .section bgchr,text,root",
                    f"        .public {symbol}",
                    f"{symbol}:",
                    f'        .incbin "out/{stem}.bin"', ""]
    emit_layer_assets(root, outdir, asm)
    (outdir / "bgchr.s").write_text("\n".join(asm))

    c = ["/* Generated by tools/gen_bgchr.py - do not edit. */",
         "#include <stdint.h>", ""]
    for i in range(len(keys)):
        c.append(f"extern const uint8_t bg_tiles_{i}[];")
        c.append(f"extern const uint8_t bg_tiles_alt_{i}[];")
    c.append("")
    c.append(f"const uint8_t *const bg_tileset_ptr[{len(keys)}] = {{")
    c.append("    " + ", ".join(f"bg_tiles_{i}" for i in range(len(keys))))
    c.append("};")
    c.append("")
    c.append(f"const uint8_t *const bg_tileset_alt_ptr[{len(keys)}] = {{")
    c.append("    " + ", ".join(f"bg_tiles_alt_{i}" for i in range(len(keys))))
    c.append("};")
    c.append("")
    c.append(f"const uint8_t lvl_bg_tileset[{len(per_level)}] = {{")
    for i in range(0, len(per_level), 16):
        c.append("    " + ", ".join(str(v) for v in per_level[i:i + 16]) + ",")
    c.append("};")
    (outdir / "bgchr_meta.c").write_text("\n".join(c) + "\n")

    # The oracle for tools/verify_level_boot.lua: which tileset each level must
    # have in VRAM, and the six CGRAM entries the header's two colours set.
    # Emitted here because this file already knows the mapping - a check that
    # recomputed it from the same assumptions would not be a check.
    BG_I, GR_I = g.HEADER_FIELDS.index("bg_color"), g.HEADER_FIELDS.index("ground_color")
    darken = parse_darken(root)
    lua = ["-- Generated by tools/gen_bgchr.py - do not edit.",
           "return {", "  tileset = {"]
    lua.append("    " + ", ".join(str(v) for v in per_level))
    lua.append("  },")
    lua.append("  -- CGRAM word per palette index, per level (0-based level key).")
    lua.append("  pal = {")
    for i, n in enumerate(kept):
        bg = headers[n][BG_I] & 0x3F
        gr = headers[n][GR_I] & 0x3F
        ent = {0: bg, 1: darken[bg], 9: darken[bg], 13: darken[bg],
               6: gr, 5: darken[gr]}
        body = ", ".join(f"[{k}]=0x{m.nes_color_to_cgram(v):04X}"
                         for k, v in sorted(ent.items()))
        lua.append(f"    [{i}] = {{ {body} }},")
    lua.append("  },")
    lua.append("}")
    (outdir / "bg_level_expect.lua").write_text("\n".join(lua) + "\n")

    print(f"    bgchr.s ({len(keys)} tileset pairs, {len(keys) * 16}KB; "
          f"BG2 parallax) + bgchr_meta.c ({len(per_level)} levels) + "
          "bg_level_expect.lua")
    for i, k in enumerate(keys):
        used = sum(1 for v in per_level if v == i)
        print(f"      {i}: spikes={k[0]:<2} blocks={k[1]:<2} bank2={k[2]:<8} "
              f"{used} level(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
