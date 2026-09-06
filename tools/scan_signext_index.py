#!/usr/bin/env python3
"""Catch Calypsi sign-extending an unsigned byte used as an array index.

Calypsi 5.18 compiles `arr[(uint8_t)(i + n)]` by sign-extending the byte into X:

        eor     ##128
        and     ##255
        sec
        sbc     ##128       ; <- byte -> SIGNED word
        tax
        lda     long:arr,x

So index 159 reads `arr - 97`. Reading a plain `uint8_t` VARIABLE is fine
(`and ##255`); it is the cast in the subscript that goes wrong.

This is worth a build-time scan rather than a code review rule because of how it
fails. Every access below 128 is correct, so the code works - for a while, on
some inputs. In the level decompressor it corrupted a handful of bytes of every
one of 46 levels, the stream resynced on the next literal, and the levels drew
almost right: a wall of one metatile where there should have been sky. Nothing
crashed and nothing was obviously wrong. See docs/HANDOFF.md trap 94.

A genuinely signed index is legal C and would trip this too, so a hit is "look at
this", not "this is a bug" - but the port has none, and the fix is always the
same: keep the index in a uint16_t and mask it.

    python tools/scan_signext_index.py out/shim_engine.s ...
"""
import re
import sys
from pathlib import Path

# The sign-extend idiom, then the transfer to an index register, then a long
# indexed access. Comment lines (the compiler interleaves the C source) are
# skipped so the sequence is matched on instructions alone.
SEXT = ["eor ##128", "and ##255", "sec", "sbc ##128"]
XFER = ("tax", "tay")
INDEXED = re.compile(r"(lda|sta|ldx|stx|ldy|sty)\s+long:(\w+),\s*[xy]")


def scan(path: Path):
    lines = []
    for n, raw in enumerate(path.read_text(errors="replace").splitlines(), 1):
        text = raw.split(";")[0].strip()
        text = re.sub(r"^`?\??\w+`?:", "", text).strip()   # drop a label prefix
        if text:
            lines.append((n, re.sub(r"\s+", " ", text)))

    hits = []
    for i in range(len(lines) - len(SEXT) - 1):
        if [lines[i + k][1] for k in range(len(SEXT))] != SEXT:
            continue
        j = i + len(SEXT)
        if lines[j][1] not in XFER:
            continue
        m = INDEXED.match(lines[j + 1][1])
        if m:
            hits.append((lines[j + 1][0], m.group(2)))
    return hits


def main(argv):
    if len(argv) < 2:
        sys.exit("usage: scan_signext_index.py <file.s> ...")
    total = 0
    for name in argv[1:]:
        path = Path(name)
        if not path.exists():
            sys.exit(f"{path} not found")
        for line, sym in scan(path):
            print(f"{path}:{line}: index into {sym!r} is SIGN-EXTENDED - "
                  f"a value >= 128 reads before the array")
            total += 1
    if total:
        print(f"scan_signext_index: {total} sign-extended indexed access(es). "
              f"Keep the index in a uint16_t and mask it (& 0xFF).")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
