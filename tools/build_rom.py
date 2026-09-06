#!/usr/bin/env python3
"""
Build the SNES ROM: assemble, link, then patch the cartridge checksum.

Uses ca65/ld65 from the game repo's BIN/ directory - ca65 assembles 65816 with
--cpu 65816, so no extra toolchain is needed for a display-only ROM.

Usage:  python tools/build_rom.py [--root C:\\famidash] [--out out/famidash-snes.sfc]
"""

import argparse
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJ = HERE.parent


def run(cmd, **kw):
    print('  $', ' '.join(str(c) for c in cmd))
    res = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if res.stdout.strip():
        print(res.stdout.rstrip())
    if res.stderr.strip():
        print(res.stderr.rstrip(), file=sys.stderr)
    if res.returncode != 0:
        raise SystemExit(f"!! command failed ({res.returncode})")
    return res


def patch_checksum(path: Path, header_off=0x7FDC):
    """Fill in the SNES header checksum / complement at $FFDC-$FFDF.

    The checksum is the 16-bit sum of every byte with the checksum field itself
    read as zero; the complement is its XOR with $FFFF.  For a 32KB LoROM the
    header sits at file offset $7FB0, so the checksum field is $7FDC.
    """
    data = bytearray(path.read_bytes())
    data[header_off:header_off + 4] = b'\x00\x00\x00\x00'
    total = sum(data) & 0xFFFF
    complement = total ^ 0xFFFF
    data[header_off + 0] = complement & 0xFF
    data[header_off + 1] = complement >> 8
    data[header_off + 2] = total & 0xFF
    data[header_off + 3] = total >> 8
    path.write_bytes(data)
    return total, complement


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=r'C:\famidash',
                    help='game repo, for BIN/ca65.exe and BIN/ld65.exe')
    ap.add_argument('--target', default='main', choices=('main', 'scroll'),
                    help='main = static display ROM, scroll = column streaming')
    ap.add_argument('--out', default=None)
    args = ap.parse_args()

    TARGETS = {
        'main':   ('main.s',   'lorom.cfg',    0x7FDC, 0x05,
                   ('bg1.tiles.bin', 'bg1.tilemap.bin', 'bg1.cgram.bin')),
        'scroll': ('scroll.s', 'lorom256.cfg', 0x7FDC, 0x08,
                   ('bg1.tiles.bin', 'bg1.cgram.bin', 'level_info.inc',
                    'level.cols.0.bin', 'level.cols.1.bin',
                    'level.cols.2.bin', 'level.cols.3.bin')),
    }
    src_name, cfg_name, csum_off, _romsize, needs = TARGETS[args.target]
    if args.out is None:
        args.out = f'out/famidash-snes-{args.target}.sfc'

    bindir = Path(args.root) / 'BIN'
    ca65 = bindir / 'ca65.exe'
    ld65 = bindir / 'ld65.exe'
    for tool in (ca65, ld65):
        if not tool.exists():
            print(f"!! missing {tool}")
            return 1

    src = PROJ / 'src' / src_name
    cfg = PROJ / 'src' / cfg_name
    obj = PROJ / 'out' / f'{args.target}.o'
    rom = PROJ / args.out
    rom.parent.mkdir(parents=True, exist_ok=True)

    for need in needs:
        if not (PROJ / 'out' / need).exists():
            print(f"!! missing out/{need} - run tools/snes_m0.py first")
            return 1

    print("[1] assemble")
    run([ca65, '--cpu', '65816', '-o', obj, '-l', str(obj.with_suffix('.lst')),
         str(src)], cwd=src.parent)

    print("[2] link")
    run([ld65, '-C', str(cfg), '-o', str(rom), '-m', str(obj.with_suffix('.map')),
         str(obj)])

    print("[3] checksum")
    total, comp = patch_checksum(rom, csum_off)
    size = rom.stat().st_size
    print(f"    sum=${total:04X} complement=${comp:04X}")

    print(f"\n    {rom.relative_to(PROJ)}  {size} bytes ({size // 1024}KB LoROM)")
    return 0


if __name__ == '__main__':
    sys.exit(main())
