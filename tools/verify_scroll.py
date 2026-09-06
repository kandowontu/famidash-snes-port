#!/usr/bin/env python3
"""
Authoritative verification for the column-streaming ROM.

Runs Mesen2 headless once per sample frame, dumps VRAM, and checks that every
visible tilemap slot holds exactly the level column it should - all 32 rows,
including the rows below the 224-line display.

Why VRAM and not screenshots: Mesen's --testrunner takeScreenshot() is not
frame-deterministic here. Two runs stopped at the same frame return different
images depending on what else the Lua script did, so pixel-diffing a *moving*
image against ground truth is unreliable. VRAM contents are deterministic and
are a stricter test anyway - they cover off-screen rows too.

The static (non-scrolling) ROM is still verified pixel-exact by
tools/compare_rom.py; that is what validates the rendering path.

Usage:  python tools/verify_scroll.py [--root C:\\famidash] [--frames 120,600,...]
"""

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import snes_m0 as m                                    # noqa: E402

PROJ = Path(__file__).resolve().parent.parent
OUT = PROJ / 'out'
TILE_ROWS = 32


def visible_col_count(scroll_x: int) -> int:
    """Columns actually on screen: 32, plus a partial one when not tile-aligned.

    Columns beyond this are write-ahead slack and are legitimately not yet
    streamed - checking them would flag the streamer for work it has not been
    asked to do yet.
    """
    return 32 + (1 if scroll_x % 8 else 0)


def run_mesen(mesen: Path, rom: Path, frame: int) -> dict:
    (OUT / 'dump_frame.txt').write_text(f"{frame}\n")
    subprocess.run([str(mesen), '--testrunner', str(rom),
                    str(PROJ / 'tools' / 'dump_vram.lua')],
                   capture_output=True)
    return dict(line.split(maxsplit=1) for line in
                (OUT / 'vram_state.txt').read_text().splitlines() if line.strip())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=r'C:\famidash')
    ap.add_argument('--mesen', default=r'C:\mesen2\Mesen.exe')
    ap.add_argument('--rom', default='out/famidash-snes-scroll.sfc')
    ap.add_argument('--level', default='stereomadness')
    ap.add_argument('--lvlset', default='lvlset_A')
    ap.add_argument('--height', type=int, default=27)
    ap.add_argument('--frames', default='120,600,1200,1800,2400,3000,3600')
    args = ap.parse_args()

    root = Path(args.root)
    mesen = Path(args.mesen)
    rom = PROJ / args.rom
    if not mesen.exists():
        print(f"!! Mesen not found at {mesen}")
        return 1

    lz = (root / 'LEVELS' / 'include' / args.lvlset / 'EXPORTS' / 'level'
          / f'{args.level}.lz.bin').read_bytes()
    columns, _ = m.rle_decode(m.lz_decompress(lz), args.height)
    grid = m.build_tilemap(columns, m.parse_metatiles(root / 'METATILES' / 'metatiles.inc'))
    meta = dict(line.split(maxsplit=1) for line in
                (OUT / 'level.columns.meta').read_text().splitlines() if line.strip())
    row_start = int(meta['row_start'])
    n_cols = len(grid[0])

    print(f"level: {len(columns)} metatile columns -> {n_cols} tile columns, "
          f"window at tile row {row_start}\n")

    total_checked = total_bad = 0
    frames = [int(f) for f in args.frames.split(',')]

    for frame in frames:
        st = run_mesen(mesen, rom, frame)
        scroll_x, cols_done = int(st['scroll_x']), int(st['cols_done'])
        vram = (OUT / 'vram_tilemap.bin').read_bytes()

        def vword(slot, row):
            i = ((slot & 32) << 5) + (slot & 31) + row * TILE_ROWS
            return int.from_bytes(vram[i * 2:i * 2 + 2], 'little')

        left = scroll_x // 8
        bad = []
        checked = 0
        for k in range(visible_col_count(scroll_x)):
            col = left + k
            if col >= n_cols:
                break
            for r in range(TILE_ROWS):
                gr = row_start + r
                want = grid[gr][col] if gr < len(grid) else 0
                checked += 1
                if vword(col & 63, r) != want:
                    bad.append((col, r, want, vword(col & 63, r)))
        total_checked += checked
        total_bad += len(bad)

        status = 'OK' if not bad else f'{len(bad)} WRONG'
        print(f"  frame {frame:5d}  scroll_x={scroll_x:6d}  col={left:5d}  "
              f"cols_done={cols_done:5d}  {checked:4d} words checked  {status}")
        for col, r, want, got in bad[:3]:
            print(f"      col {col} row {r}: want {want:04X} got {got:04X}")

    print(f"\n{total_checked - total_bad}/{total_checked} tilemap words correct "
          f"across {len(frames)} frames")
    return 0 if total_bad == 0 else 2


if __name__ == '__main__':
    sys.exit(main())
