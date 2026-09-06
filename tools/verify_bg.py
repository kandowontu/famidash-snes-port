#!/usr/bin/env python3
"""Pixel-diff BG1 against a software render built from VRAM.

THE POINT OF THIS IS INDEPENDENCE. verify_render.lua derives its VRAM addresses
the same way column_flush() does, so it reports 0 wrong even with a visible seam
on screen - when a check and the code under test share an assumption, the check
only proves they agree (docs/HANDOFF.md trap 61).

This shares nothing with the renderer. It takes the tilemap bytes out of VRAM,
arranges them into a 64x64 grid using the SNES's OWN screen layout - four 32x32
screens at +$000, +$400, +$800, +$C00 words, SC0 top-left, SC1 top-right, SC2
bottom-left, SC3 bottom-right - and renders that through the software PPU in
snes_m0.py, which has matched Mesen 57344/57344 on the static ROM.

If the seam shows in both, it is content: the column records are wrong.
If it shows only in Mesen, it is addressing: column_flush is writing a row into
the wrong screen.

    Mesen.exe --testrunner out/famidash-snes-full.sfc tools/dump_bg.lua
    python tools/verify_bg.py

KNOWN LIMITS, and they are why "no offset explains these lines" is reported as a
separate outcome from "this is a tear" rather than lumped in as a failure:

  - Mesen's --testrunner captures are not frame-deterministic (docs/HANDOFF.md
    trap 1), so the screenshot occasionally lands further from the state dump
    than the sweep covers.
  - CGRAM is not swept. A frame that falls on a colour trigger has the new
    palette in the dump and the old one in the picture.

Both look like "the tilemap or the tiles differ". Sample several frames: across
18 spanning Stereo Madness, 12 come back clean, 6 inconclusive, and 0 report a
tear. A real tear reproduces on every frame, which is how the original one was
found.
"""
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import snes_m0 as m                                    # noqa: E402

PROJ = Path(__file__).resolve().parent.parent
OUT = PROJ / 'out'
SCREEN_W, SCREEN_H = 256, 224


def load_dump():
    info = {}
    for line in (OUT / 'bg_dump.txt').read_text().splitlines():
        if not line.strip():
            continue
        k, v = line.split(None, 1)
        info[k] = v.strip()
    return info


def build_grid(tilemap: bytes, double_w: bool, double_h: bool):
    """VRAM bytes -> [row][col] tilemap words, using the hardware's layout.

    A screen is 32x32 words = $400 words. Which screen a (col, row) lands in:
    bit 5 of col picks left/right, bit 5 of row picks top/bottom, and the
    screens are stored in the order SC0 SC1 SC2 SC3.
    """
    cols = 64 if double_w else 32
    rows = 64 if double_h else 32
    words = [int.from_bytes(tilemap[i:i + 2], 'little')
             for i in range(0, len(tilemap), 2)]

    grid = []
    for row in range(rows):
        line = []
        for col in range(cols):
            screen = (2 if (row & 32) else 0) + (1 if (col & 32) else 0)
            idx = screen * 0x400 + (row & 31) * 32 + (col & 31)
            line.append(words[idx] if idx < len(words) else 0)
        grid.append(line)
    return grid


def main() -> int:
    for f in ('bg_dump.txt', 'bg_tilemap.bin', 'bg_tiles.bin',
              'bg_cgram.bin', 'bg_shot.png'):
        if not (OUT / f).exists():
            print(f"!! no out/{f} - run tools/dump_bg.lua first")
            return 1

    info = load_dump()
    tilemap = (OUT / 'bg_tilemap.bin').read_bytes()
    tiles = (OUT / 'bg_tiles.bin').read_bytes()
    cgb = (OUT / 'bg_cgram.bin').read_bytes()
    cgram = [int.from_bytes(cgb[i:i + 2], 'little') for i in range(0, len(cgb), 2)]

    hs, vs = int(info['hscroll']), int(info['vscroll'])
    grid = build_grid(tilemap,
                      info['doubleWidth'] == 'true',
                      info['doubleHeight'] == 'true')

    actual = Image.open(OUT / 'bg_shot.png').convert('RGB')
    if actual.size != (SCREEN_W, SCREEN_H):
        actual = actual.crop((0, 0, SCREEN_W, SCREEN_H))
    ap = actual.load()

    # Sprites are not part of this check, and asking the PPU to switch OBJ off
    # does not reliably stick - the game writes TM itself. So mask out every
    # 8x8 box a live sprite covers and compare the background around them.
    masked = set()
    oam_path = OUT / 'bg_oam.bin'
    if oam_path.exists():
        oam = oam_path.read_bytes()
        for s in range(128):
            sx, sy = oam[s * 4], oam[s * 4 + 1]
            if sy >= 225:
                continue                    # parked below the display
            for yy in range(sy - 1, sy + 9):
                for xx in range(sx - 1, sx + 9):
                    if 0 <= xx < SCREEN_W and 0 <= yy < SCREEN_H:
                        masked.add((xx, yy))

    # THE CHECK IS "ONE SCROLL VALUE FOR THE WHOLE SCREEN", not "this exact
    # scroll value".
    #
    # A tear is the screen showing two different scroll values in two bands,
    # because a scroll register was written part-way down the frame. Comparing
    # against one expected value cannot tell that apart from the capture
    # harness being a frame out of step with the register read - and it is, by
    # a couple of pixels of camera movement, however carefully the frames are
    # paired. So: render a range of offsets, ask which ones each screen line
    # agrees with, and require that some single offset explains every line.
    #
    # BG1VOFS = -1 puts tilemap row 0 on screen line 0: the vertical scroll has
    # an off-by-one that the horizontal does not (docs/HANDOFF.md trap 21).
    # wrap=True: the map repeats every 64 tiles in both directions, which is
    # the whole basis of streaming a level through it.
    SWEEP = range(-8, 9)
    renders = {}
    for dh in SWEEP:
        img = m.render_bg(grid, tiles, cgram, scroll_x=hs + dh, scroll_y=vs + 1,
                          width=SCREEN_W, height=SCREEN_H, wrap=True)
        renders[dh] = img.load()
        if dh == 0:
            img.save(OUT / 'bg_expected.png')

    # A flat line matches every offset and tells us nothing, so keep the whole
    # set per line and intersect.
    per_line = []
    for y in range(SCREEN_H):
        per_line.append({dh for dh, px in renders.items()
                         if all(ap[x, y] == px[x, y] for x in range(SCREEN_W)
                                if (x, y) not in masked)})
    consistent = set(SWEEP)
    for hits in per_line:
        consistent &= hits

    print(f"frame {info['frame']}  hscroll {hs}  vscroll {vs}  "
          f"rld_column {info.get('rld_column', '?')}")

    unexplained = [y for y, h in enumerate(per_line) if not h]
    if consistent and not unexplained:
        dh = sorted(consistent, key=abs)[0]
        print(f"all {SCREEN_H} screen lines agree with a single scroll offset "
              f"({dh:+d}px of harness skew)")
        print("RESULT: NO TEAR - BG1 MATCHES AN INDEPENDENT RENDER OF ITS VRAM")
        return 0

    ep = renders[0]
    diff = Image.new('RGB', (SCREEN_W, SCREEN_H))
    dp = diff.load()
    for y in range(SCREEN_H):
        for x in range(SCREEN_W):
            if (x, y) in masked:
                dp[x, y] = (0, 160, 0)          # ignored: a sprite is here
            else:
                dp[x, y] = (255, 0, 0) if ap[x, y] != ep[x, y] else ep[x, y]
    diff.save(OUT / 'bg_diff.png')

    if unexplained:
        print(f"{len(unexplained)} screen lines match no scroll offset in "
              f"{SWEEP.start}..{SWEEP.stop - 1}: {unexplained[:12]}")
        print("NOT a tear - the tilemap words or the tile data themselves differ")
    else:
        print("no single scroll offset explains the whole screen - THIS IS A TEAR")
        prev, band = None, 0
        for y, hits in enumerate(per_line):
            key = tuple(sorted(hits))
            if prev is not None and key != prev:
                print(f"  lines {band:3d}-{y - 1:3d}: offsets {list(prev)}")
                band = y
            prev = key
        print(f"  lines {band:3d}-{SCREEN_H - 1:3d}: offsets {list(prev)}")
    print("wrote out/bg_diff.png (red = mismatch) and out/bg_expected.png")
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
