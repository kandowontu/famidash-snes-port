#!/usr/bin/env python3
"""Pad the linker's raw output to a whole bank and patch the SNES checksum.

With `--raw-multiple-memories` the linker does NOT produce one image: it writes
each non-contiguous memory to its own `<MemoryName>.raw` alongside the main
output. A memory placed away from the code - the level column stream at bank
$C4, for instance - therefore never appears in the ROM unless it is spliced back
in here. Symptom if you forget: everything links, the map looks right, and the
ROM is simply the size of the code.

HiROM maps bank $C0 to file offset 0, so a bank's file offset is
(bank - 0xC0) << 16.

    python tools/pack_hirom.py --input out/rom.raw --output out/game.sfc \\
        --part out/LevelColumns0.raw@0xC4
"""
import argparse
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument('--input', default='out/rom.raw')
ap.add_argument('--output', default='out/famidash-snes-game.sfc')
ap.add_argument('--title', default=None,
                help='overwrite the 21-byte cartridge title')
ap.add_argument('--header-at', type=lambda v: int(v, 0), default=0xFFB0,
                help='file offset of the extended header. HiROM puts it at '
                     '$FFB0; an SA-1 cartridge is LoROM-shaped and puts it at '
                     '$7FB0, which is also where its reset vector lives')
ap.add_argument('--part', action='append', default=[],
                help='FILE@BANK - splice a separately emitted memory in at '
                     'the file offset for that HiROM bank')
args = ap.parse_args()

raw = bytearray(Path(args.input).read_bytes())

# Which bytes the main image and the parts spliced so far actually own.
written = bytearray(len(raw))
for i, _ in enumerate(raw):
    written[i] = 1

# BIGGEST FIRST, AND FILL-ONLY.
#
# `--raw-multiple-memories` does not emit one raw per memory. It merges
# contiguous ROM memories, so a single `SpriteCHR.raw` can hold everything from
# bank $C3 upwards - AND it can ALSO emit a `BGCHR.raw` for a memory inside that
# span, holding only part of it. Splicing every part in the order given then
# overwrites 60KB of correct BG tilesets with a truncated 40KB copy, and five
# levels' worth of tiles vanish from a ROM that links, packs and passes a layout
# check written before this could happen.
#
# So: the largest raw for a region wins, and a later part may only fill bytes
# nothing has claimed. tools/verify_rom_layout.py checks the result rather than
# trusting it.
parts = []
for spec in args.part:
    path, _, bank = spec.rpartition('@')
    if not path:
        raise SystemExit(f"--part needs FILE@BANK, got {spec!r}")
    offset = (int(bank, 0) - 0xC0) << 16
    if offset < 0:
        raise SystemExit(f"{spec}: bank must be >= $C0 for HiROM")
    if not Path(path).exists():
        # Not an error: whether a memory gets its own file depends on what the
        # .scm places between it and the main image.
        print(f"    ({Path(path).name} not emitted separately - "
              f"the linker kept it in the main image)")
        continue
    parts.append((Path(path).stat().st_size, offset, Path(path)))

for size, offset, path in sorted(parts, key=lambda t: -t[0]):
    data = path.read_bytes()
    end = offset + len(data)
    if len(raw) < end:
        raw += bytes(end - len(raw))
        written += bytes(end - len(written))
    filled = 0
    for i, byte in enumerate(data):
        if not written[offset + i]:
            raw[offset + i] = byte
            written[offset + i] = 1
            filled += 1
    if filled == len(data):
        print(f"    {path.name}: {filled} bytes at bank "
              f"${(offset >> 16) + 0xC0:02X}")
    elif filled:
        print(f"    {path.name}: {filled} of {len(data)} bytes at bank "
              f"${(offset >> 16) + 0xC0:02X} (the rest was already covered)")
    else:
        print(f"    {path.name}: already covered by a larger raw")

raw += bytes((-len(raw)) % 65536)
H = args.header_at        # HiROM: $FFB0, bank $C0 being file offset 0.
                          # SA-1: $7FB0, because banks $00-$3F are LoROM-shaped
                          # and the console reads the header through that view.

if args.title:
    raw[H + 0x10:H + 0x25] = args.title.ljust(21)[:21].encode('latin1')

# ROM size is log2(KB): 64KB -> 6, 128KB -> 7, and so on.
size_kb = len(raw) // 1024
raw[H + 0x27] = max(6, (size_kb - 1).bit_length())

raw[H + 0x2C:H + 0x30] = b'\x00' * 4
total = sum(raw) & 0xFFFF
comp = total ^ 0xFFFF
raw[H + 0x2C], raw[H + 0x2D] = comp & 0xFF, comp >> 8
raw[H + 0x2E], raw[H + 0x2F] = total & 0xFF, total >> 8

out = Path(args.output)
out.write_bytes(raw)
print(f"{out}  {len(raw)} bytes  "
      f"title={raw[H+0x10:H+0x25].decode('latin1').strip()!r}  "
      f"checksum=${total:04X}  "
      f"reset=${raw[H + 0x4C] | (raw[H + 0x4D] << 8):04X}")
