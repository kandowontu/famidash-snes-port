"""Pad a LoROM-shaped raw image to a power of two and fix its header checksum.

The main port's packer is pack_hirom.py and is HiROM-specific: it splices
separately-emitted memories in at HiROM bank offsets. SA-1 cartridges use the
LoROM-shaped map instead - 32KB banks at $8000-$FFFF, header at file offset
$7FC0 - so the SA-1 work needs its own, much smaller, packer.

Two jobs, both of which an emulator notices:

* pad to a power of two. The linker stops emitting at the last byte it placed,
  which is the reset vector at $FFFC, so a 32KB image arrives 2 bytes short and
  the header's declared size stops matching the file.
* the header checksum. Mesen's format detection scores candidate header
  locations, and a valid checksum/complement pair is part of that score - which
  matters here precisely because the SA-1 map mode is the thing under test.
"""

import argparse
import sys

HEADER_OFF = 0x7FC0  # LoROM: the header sits at the top of the first 32KB bank
CKSUM_OFF = HEADER_OFF + 0x1C  # complement, then checksum


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--size", type=lambda s: int(s, 0), default=0x8000)
    # The benchmark ships as two cartridges built from ONE object file: the SA-1
    # one, and a plain FastROM one used only to time the S-CPU run against the
    # clock the port really has. Overriding two header bytes is the entire
    # difference, and doing it here keeps the two from drifting apart the way a
    # duplicated header source would.
    ap.add_argument("--mapmode", type=lambda s: int(s, 0))
    ap.add_argument("--chipset", type=lambda s: int(s, 0))
    # Stamp each 32KB block of the padding with its own index, so a program can
    # read an address and say which part of the ROM answered. That is the only
    # way to establish the SA-1's ROM mapping without trusting documentation:
    # the chip has a bank controller in front of it and the port needs 2MB.
    #
    # The stamp goes at +$4000 within each block rather than at its start,
    # because the start of block 0 is the program itself.
    ap.add_argument("--stamp", action="store_true")
    ap.add_argument("--romsize", type=lambda s: int(s, 0),
                    help="header ROM size as 1<<N KB; an emulator that trusts "
                         "a stale value will truncate the image")
    args = ap.parse_args()

    data = bytearray(open(args.input, "rb").read())
    if len(data) > args.size:
        sys.exit("pack_lorom: image is %d bytes, larger than the %d requested"
                 % (len(data), args.size))
    data += b"\x00" * (args.size - len(data))

    if args.stamp:
        for blk in range(len(data) // 0x8000):
            at = blk * 0x8000 + 0x4000
            data[at + 0] = blk & 0xFF
            data[at + 1] = 0xB0 | (blk >> 8)   # a tag, so noise cannot pass

    if args.romsize is not None:
        data[HEADER_OFF + 0x17] = args.romsize
    if args.mapmode is not None:
        data[HEADER_OFF + 0x15] = args.mapmode
    if args.chipset is not None:
        data[HEADER_OFF + 0x16] = args.chipset

    # The pair is summed as if it read $FFFF/$0000, which is what makes the
    # result checkable without knowing it in advance.
    data[CKSUM_OFF:CKSUM_OFF + 4] = b"\xFF\xFF\x00\x00"
    total = sum(data) & 0xFFFF
    data[CKSUM_OFF + 0] = (total ^ 0xFFFF) & 0xFF
    data[CKSUM_OFF + 1] = ((total ^ 0xFFFF) >> 8) & 0xFF
    data[CKSUM_OFF + 2] = total & 0xFF
    data[CKSUM_OFF + 3] = (total >> 8) & 0xFF

    open(args.output, "wb").write(bytes(data))
    print("pack_lorom: %s, %d bytes, map mode 0x%02X chipset 0x%02X, checksum %04X"
          % (args.output, len(data), data[HEADER_OFF + 0x15],
             data[HEADER_OFF + 0x16], total))


if __name__ == "__main__":
    main()
