#!/usr/bin/env python3
"""
Pixel-diff the software SNES PPU against real SNES emulation.

Renders out/bg1.*.bin - the exact binaries the ROM DMAs - through the software
PPU in snes_m0.py, then compares against a Mesen2 capture of the ROM running.
An exact match means the M0 converters, the software PPU, and the ROM all agree.

Usage:  python tools/compare_rom.py
"""

import sys
from pathlib import Path

from PIL import Image, ImageChops

sys.path.insert(0, str(Path(__file__).resolve().parent))
import snes_m0 as m                                    # noqa: E402

PROJ = Path(__file__).resolve().parent.parent
OUT = PROJ / 'out'


def main() -> int:
    tiles = (OUT / 'bg1.tiles.bin').read_bytes()
    tmap = (OUT / 'bg1.tilemap.bin').read_bytes()
    cgb = (OUT / 'bg1.cgram.bin').read_bytes()
    shot_path = OUT / 'mesen_shot.png'

    if not shot_path.exists():
        print("!! no out/mesen_shot.png - run the Mesen testrunner first")
        return 1

    cgram = [int.from_bytes(cgb[i:i + 2], 'little') for i in range(0, len(cgb), 2)]

    # Rebuild the 32x32 BG1 screen from the tilemap bytes the ROM uses.
    grid = [[int.from_bytes(tmap[(y * 32 + x) * 2:(y * 32 + x) * 2 + 2], 'little')
             for x in range(32)] for y in range(32)]

    # The ROM sets BG1VOFS = -1, which puts tilemap row 0 on screen line 0.
    ours = m.render_bg(grid, tiles, cgram, scroll_x=0, scroll_y=0,
                       width=256, height=224).convert('RGB')
    ours.save(OUT / 'software_ppu_256x224.png')

    theirs = Image.open(shot_path).convert('RGB')
    print(f"software PPU : {ours.size}")
    print(f"mesen2 SNES  : {theirs.size}")

    if ours.size != theirs.size:
        print("!! size mismatch, cannot compare")
        return 1

    diff = ImageChops.difference(ours, theirs)
    bbox = diff.getbbox()
    total = ours.width * ours.height
    pixels = (diff.get_flattened_data() if hasattr(diff, 'get_flattened_data')
              else diff.getdata())
    bad = sum(1 for px in pixels if px != (0, 0, 0))

    if bbox is None:
        print(f"\nEXACT MATCH - {total} / {total} pixels identical")
        return 0

    print(f"\n{total - bad} / {total} pixels identical "
          f"({(total - bad) * 100 / total:.2f}%)")
    print(f"differing region: {bbox}")

    # Amplify the diff so any mismatch is visible.
    diff.point(lambda v: min(255, v * 8)).save(OUT / 'diff.png')
    print("wrote out/diff.png (8x amplified)")
    return 0 if bad == 0 else 2


if __name__ == '__main__':
    sys.exit(main())
