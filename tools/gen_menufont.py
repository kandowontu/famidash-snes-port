#!/usr/bin/env python3
"""Emit a small ASCII font as SNES 2bpp CHR, for the level select.

THE GAME HAS NO ALPHABET. The level tileset spells "ATTEMPT" as "PQQRSTQ" -
those are level tiles that happen to look like letters - and menus.chr is not an
ASCII font either: `one_vram_buffer('g', ...)` in the menu code is placing tile
$67, which is a piece of menu artwork, not the letter g. The real menus draw
pre-rendered screens with vram_unrle. LETTERBANK, despite the name, is
SawbladesNone.chr.

So the level select brings its own 5x7 font, indexed BY CHARACTER CODE, which
keeps the menu's drawing code to "write the string into the tilemap".

    python tools/gen_menufont.py [--outdir out]
"""
import argparse
from pathlib import Path

# 5x7 glyphs, one string per row, '#' = ink. Only what a level list needs:
# the alphabet, digits, and a cursor.
GLYPHS = {
    'A': (".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"),
    'B': ("####.", "#...#", "####.", "#...#", "#...#", "#...#", "####."),
    'C': (".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."),
    'D': ("####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."),
    'E': ("#####", "#....", "####.", "#....", "#....", "#....", "#####"),
    'F': ("#####", "#....", "####.", "#....", "#....", "#....", "#...."),
    'G': (".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."),
    'H': ("#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"),
    'I': ("#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"),
    'J': ("..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."),
    'K': ("#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"),
    'L': ("#....", "#....", "#....", "#....", "#....", "#....", "#####"),
    'M': ("#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"),
    'N': ("#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"),
    'O': (".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
    'P': ("####.", "#...#", "#...#", "####.", "#....", "#....", "#...."),
    'Q': (".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"),
    'R': ("####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"),
    'S': (".####", "#....", "#....", ".###.", "....#", "....#", "####."),
    'T': ("#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."),
    'U': ("#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
    'V': ("#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."),
    'W': ("#...#", "#...#", "#...#", "#...#", "#.#.#", "##.##", "#...#"),
    'X': ("#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"),
    'Y': ("#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."),
    'Z': ("#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"),
    '0': (".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."),
    '1': ("..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."),
    '2': (".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"),
    '3': ("####.", "....#", "....#", ".###.", "....#", "....#", "####."),
    '4': ("...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."),
    '5': ("#####", "#....", "####.", "....#", "....#", "#...#", ".###."),
    '6': ("..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."),
    '7': ("#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."),
    '8': (".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."),
    '9': (".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."),
    '>': (".....", ".#...", "..#..", "...#.", "..#..", ".#...", "....."),
    '-': (".....", ".....", ".....", "#####", ".....", ".....", "....."),
    '.': (".....", ".....", ".....", ".....", ".....", ".....", "..#.."),
    ':': (".....", "..#..", "..#..", ".....", "..#..", "..#..", "....."),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default=str(Path(__file__).resolve().parent.parent / "out"))
    args = ap.parse_args()

    # 256 tiles of SNES 2bpp, indexed by character code. Colour 1 is the ink;
    # plane 1 stays zero, so the menu palette only has to define two entries.
    chr_data = bytearray(256 * 16)
    for ch, rows in GLYPHS.items():
        base = ord(ch) * 16
        for y, row in enumerate(rows):
            bits = 0
            for x, c in enumerate(row):
                if c == '#':
                    bits |= 0x80 >> x
            # SNES 2bpp is row-interleaved: plane 0 byte, then plane 1 byte.
            chr_data[base + y * 2] = bits
            chr_data[base + y * 2 + 1] = 0

    out = Path(args.outdir) / "menu.tiles.bin"
    out.write_bytes(bytes(chr_data))
    print(f"    menu.tiles.bin (4096B, {len(GLYPHS)} glyphs, indexed by character)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
