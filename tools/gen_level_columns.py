#!/usr/bin/env python3
"""The tilemap column records ANY level should produce, computed offline.

`gen_columns.py` builds this for one level, as ROM data. This builds it for a
level chosen by index, as a test oracle - `out/level_expect_<n>.bin`, 64 tilemap
words per tile column, which is exactly what `verify_render.lua` compares VRAM
against.

The distinction matters. Until this existed, the byte-exact render check only
ever ran on stereomadness, and `verify_level_boot.lua` - the only thing covering
the other 45 - asks whether a level DREW SOMETHING, not whether it drew the right
thing. A level whose decode desynced halfway down every column passes that
happily.

This is an independent decode: it goes back to the level's `.lz` file and
`metatiles.inc` and repeats what the runtime is supposed to do, rather than
sharing code with it (docs/HANDOFF.md trap 61).

    python tools/gen_level_columns.py --level 37 [--root C:/famidash]
"""
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import snes_m0 as m                                     # noqa: E402
import gen_levels as g                                  # noqa: E402

COL_WORDS = 64                  # tile rows per record - shim_engine.c
GROUND_ROWS = 3


def level_records(root: Path, lvlset: str, index: int):
    """Level identity plus clipped records and their decoded source columns."""
    lvldir = root / "LEVELS/include" / lvlset / "EXPORTS/level"
    order = g.parse_level_order(root, lvlset)
    headers = g.parse_all_headers(root, lvlset, order)
    kept = [n for n in order
            if (lvldir / f"{n}.lz.bin").exists() and n in headers]
    if index >= len(kept):
        sys.exit(f"level {index} out of range ({len(kept)} levels)")
    name = kept[index]
    height = headers[name][HEIGHT_FIELD]

    rle = bytes(m.lz_decompress((lvldir / f"{name}.lz.bin").read_bytes()))
    columns, _ = m.rle_decode(rle, height)
    columns = m.append_ground(columns, m.parse_ground_rle(root))
    metatiles = m.parse_metatiles(root / "METATILES" / "metatiles.inc")

    # The record shows the BOTTOM COL_WORDS tile rows of the grid, so a level
    # taller than 32 metatile rows is clipped at the top - shim_engine.c's
    # level_tile_start, and the reason vertical row streaming is still open.
    grid_rows = (height + GROUND_ROWS) * 2
    tile_start = max(0, grid_rows - COL_WORDS)
    skip = tile_start // 2

    records = []
    for mt_col in columns:
        rows = mt_col[skip:skip + (COL_WORDS // 2)]
        left, right = [], []
        for mt_index in rows:
            mt = metatiles[mt_index] if mt_index < len(metatiles) else metatiles[0]
            pal = mt["pal"]
            left += [m.tilemap_word(mt["tl"], pal), m.tilemap_word(mt["bl"], pal)]
            right += [m.tilemap_word(mt["tr"], pal), m.tilemap_word(mt["br"], pal)]
        left += [0] * (COL_WORDS - len(left))
        right += [0] * (COL_WORDS - len(right))
        records.append(left)
        records.append(right)
    return name, height, records, columns, metatiles


def world_records(columns, metatiles):
    """120-world-row tile columns used to verify vertical map streaming."""
    records = []
    for mt_col in columns:
        padded = [0] * (60 - len(mt_col)) + list(mt_col)
        left, right = [], []
        for mt_index in padded:
            mt = metatiles[mt_index] if mt_index < len(metatiles) else metatiles[0]
            pal = mt["pal"]
            left += [m.tilemap_word(mt["tl"], pal), m.tilemap_word(mt["bl"], pal)]
            right += [m.tilemap_word(mt["tr"], pal), m.tilemap_word(mt["br"], pal)]
        records.append(left)
        records.append(right)
    return records


HEIGHT_FIELD = g.HEADER_FIELDS.index("height")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="C:/famidash")
    ap.add_argument("--lvlset", default="lvlset_A")
    ap.add_argument("--outdir", default=str(ROOT / "out"))
    ap.add_argument("--level", type=int, default=0)
    ap.add_argument("--all", action="store_true",
                    help="every level, plus the inflated RLE each should hold")
    ap.add_argument("--world", action="store_true",
                    help="also emit the full 120-row vertical-stream oracle")
    args = ap.parse_args()

    root, outdir = Path(args.root), Path(args.outdir)
    if not args.all:
        emit(root, args.lvlset, outdir, args.level, verbose=True,
             world=args.world)
        return 0

    n = count_levels(root, args.lvlset)
    total = 0
    for i in range(n):
        total += emit(root, args.lvlset, outdir, i, verbose=False)
    print(f"    level_expect_*.bin + rle_expect_*.bin: {n} levels, "
          f"{total // 1024}KB of oracle")
    return 0


def emit(root: Path, lvlset: str, outdir: Path, index: int, verbose: bool,
         world: bool = False):
    name, height, records, columns, metatiles = level_records(
        root, lvlset, index)
    blob = bytearray()
    for rec in records:
        for w in rec:
            blob += bytes((w & 0xFF, w >> 8))
    (outdir / f"level_expect_{index}.bin").write_bytes(bytes(blob))

    world_blob = bytearray()
    if world:
        for rec in world_records(columns, metatiles):
            for w in rec:
                world_blob += bytes((w & 0xFF, w >> 8))
        (outdir / f"level_world_expect_{index}.bin").write_bytes(world_blob)

    # The inflated RLE the runtime should hold in level_rle. This is the check
    # that would have caught the sign-extended ring index (trap 94): the
    # decompressor was wrong from the first copy that read ring index >= 128,
    # and nothing compared its output to anything.
    lz = (root / "LEVELS/include" / lvlset / "EXPORTS/level"
          / f"{name}.lz.bin").read_bytes()
    rle = bytes(m.lz_decompress(lz))
    (outdir / f"rle_expect_{index}.bin").write_bytes(rle)

    if verbose:
        print(f"    level_expect_{index}.bin: {name} (height {height}), "
              f"{len(records)} tile columns, {len(blob)} bytes; "
              f"rle_expect_{index}.bin: {len(rle)} bytes")
        if world:
            print(f"    level_world_expect_{index}.bin: "
                  f"{len(world_blob)} bytes, 120 world tile rows per column")
    return len(blob) + len(rle)


def count_levels(root: Path, lvlset: str) -> int:
    lvldir = root / "LEVELS/include" / lvlset / "EXPORTS/level"
    order = g.parse_level_order(root, lvlset)
    headers = g.parse_all_headers(root, lvlset, order)
    return sum(1 for n in order
               if (lvldir / f"{n}.lz.bin").exists() and n in headers)


if __name__ == "__main__":
    raise SystemExit(main())
