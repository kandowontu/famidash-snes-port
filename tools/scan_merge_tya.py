#!/usr/bin/env python3
"""Find the OTHER Calypsi merge-point defect: a value dropped by a spurious TYA/TXA.

tools/scan_stackslots.py catches the variant where the join reads a stack slot
nothing wrote.  This catches the variant where the join reads the WRONG REGISTER.

The shape, from gamemodes/gamemode_wave.h:

    currplayer_vel_y = a ? (b ? -vx : vx) : (b ? -(vx<<1) : (vx<<1));

compiles to four arms that each leave the result in A and then `bra` to one
shared store - and the store is preceded by `tya`, so every arm's value is
thrown away and whatever is in Y is stored instead:

    `?L3664`:   tya
                sta     long:currplayer_vel_y

Measured effect: the wave's vertical velocity was +1 on every frame, so the
gamemode did not work at all.  It compiles clean, the scanner for the other
variant does not see it, and the number it produces is stable, so nothing but a
trace or this check finds it.

WHAT IS NOT A BUG.  A `tya`/`txa` at a label is completely normal when Y or X is
the register-allocated variable - loop counters and clamped locals both look
like that.  The discriminator is an UNCONDITIONAL `bra` to the label: a block
that computed a value into A and jumped to the merge.  When Calypsi gets it
right it puts the store behind a SECOND label and the other arm branches there
instead:

    `?L251`:    txa
    `?L850`:    sta     3,s        <- `bra ?L850`, past the txa.  Correct.

so those sites have no `bra` to the txa label and are not reported.

    python tools/scan_merge_tya.py out/probe_full.s ...
"""
import re
import sys

LABEL = re.compile(r"^`(\?L\d+)`:\s*(.*)$")
BRA = re.compile(r"^\s*bra\s+`(\?L\d+)`")
INSTR = re.compile(r"^\s*([a-z]{3})\b")


def scan(path):
    with open(path, "rb") as f:
        lines = f.read().decode("utf-8", "replace").split("\n")

    # Which labels does an UNCONDITIONAL bra target?
    bra_targets = set()
    for line in lines:
        m = BRA.match(line)
        if m:
            bra_targets.add(m.group(1))

    bad = []
    for i, line in enumerate(lines):
        m = LABEL.match(line)
        if not m:
            continue
        name, rest = m.group(1), m.group(2).strip()
        if name not in bra_targets:
            continue
        # The first instruction at the label, whether it shares the line or not.
        j = i
        first = rest
        while not first:
            j += 1
            if j >= len(lines):
                break
            first = lines[j].strip()
        if not re.match(r"^(tya|txa)\b", first):
            continue
        # ...and the value it clobbers has to actually be stored, or there is
        # nothing to lose.
        k = j + 1 if not rest else i + 1
        nxt = ""
        while k < len(lines):
            nxt = lines[k].strip()
            if nxt and not nxt.startswith(";"):
                break
            k += 1
        if not re.match(r"^sta\b", nxt):
            continue
        bad.append((i + 1, name, first, nxt))
    return bad


def main(argv):
    total = 0
    for path in argv[1:]:
        for line_no, name, first, store in scan(path):
            total += 1
            print(f"{path}:{line_no}: `{name}` is branched to unconditionally and "
                  f"starts with `{first}` feeding `{store}` - the incoming arms' "
                  f"value in A is discarded")
    print(f"{total} suspect register merge(s)")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
