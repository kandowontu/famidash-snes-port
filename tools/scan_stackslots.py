#!/usr/bin/env python3
"""Scan Calypsi-generated 65816 assembly for reads of never-written stack slots.

This is the shape of the bug that broke common_gravity_routine(): a local kept
in a register across a control-flow merge, where the merge point reloads it
from a `N,s` slot that no path ever stores to. The value read is whatever the
caller happened to leave on the stack, so it is stable frame to frame and looks
like plausible-but-wrong physics rather than a crash.

Function arguments also live at positive stack offsets, so a bare "read without
write" is not on its own a bug. The heuristic here is deliberately narrow: only
flag a slot that (a) is read somewhere in the function, (b) is never written
anywhere in the function, and (c) lies within the frame the function's own
prologue pushed. Anything above that is an incoming argument and is ignored.

    python tools/scan_stackslots.py out/game_core.s
"""
import re
import sys
from pathlib import Path

LABEL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):")
STACK = re.compile(r"^\s*(lda|sta|ldx|stx|ldy|sty|adc|sbc|cmp|ora|and|eor)\s+(\d+),s\b")
PUSH = re.compile(r"^\s*(pha|phx|phy|php|phb|phd|phk)\b")
PULL = re.compile(r"^\s*(pla|plx|ply|plp|plb|pld)\b")
WIDTH = re.compile(r"^\s*(sep|rep)\s+#(\d+)\b")

# Calypsi reclaims a block of stack in one go with `tsc / clc / adc ##N / tcs`
# (and allocates with sbc). That moves every `N,s` in the rest of the block, so
# it has to be tracked just like a push or a pull.
TSC = re.compile(r"^\s*tsc\b")
TCS = re.compile(r"^\s*tcs\b")
ADDSUB = re.compile(r"^\s*(adc|sbc)\s+##?(\d+)\b")

# Calypsi puts an instruction on the same line as the label it follows, both for
# its own local labels (`?L1175`:   lda 1,s) and for function entry
# (cube_eject: phy). Matching only indented lines silently skips exactly the
# join points and prologues this scanner exists to look at, so strip any leading
# label before matching an instruction.
LABEL_PREFIX = re.compile(r"^(?:`[^`]*`|[A-Za-z_][A-Za-z0-9_]*):")


def code(line):
    return LABEL_PREFIX.sub("", line)


def scan(path):
    # Calypsi emits bare CRs inside the source-comment lines it interleaves with
    # the code. Reading in text mode would let universal-newline translation
    # turn each of those into a line break, so the reported line numbers - and,
    # worse, the function boundaries - would not match grep or an editor.
    # Decode the bytes and split on "\n" alone, exactly as grep does.
    lines = Path(path).read_bytes().decode("utf-8", "replace").split("\n")

    funcs = []          # (name, start, end)
    cur, start = None, 0
    for i, line in enumerate(lines):
        m = LABEL.match(line)
        if m and not m.group(1).startswith("?"):
            if cur:
                funcs.append((cur, start, i))
            cur, start = m.group(1), i
    if cur:
        funcs.append((cur, start, len(lines)))

    findings = []
    for name, a, b in funcs:
        body = lines[a:b]

        # Frame size: contiguous pushes at the top of the function, 2 bytes
        # each. The first push can share the entry label's line.
        frame, prologue_end = 0, 0
        for idx, line in enumerate(body):
            c = code(line).strip()
            if PUSH.match(code(line)):
                frame += 2
                prologue_end = idx + 1
            elif c and not c.startswith(";"):
                break
        if frame == 0:
            continue

        # `N,s` is relative to the CURRENT stack pointer, so a push or pull
        # between a store and a load renames the same byte. Calypsi pushes call
        # arguments mid-expression, which makes `sta 3,s ... pla ... lda 1,s` a
        # correct read-back rather than a bug. Track the depth and compare
        # canonical slots (depth + offset) instead of raw offsets.
        #
        # The depth is tracked per basic block and reset at every label. A
        # linear walk cannot follow control flow, and Calypsi's jump tables use
        # `pha` + `rts` - a push the walk sees and a matching pop it does not -
        # so depth would drift for the rest of the function and mis-name every
        # later slot. Resetting at labels bounds the drift to one block, which
        # is where the push/pull renaming this correction exists for happens.
        #
        # Push width depends on the M/X flags, hence the sep/rep tracking;
        # #$20 is M (A width), #$10 is X (index width).
        # Depth 0 is the post-prologue stack pointer: every `N,s` in the body is
        # relative to that, so the prologue's own pushes must not be counted.
        depth = 0
        a8 = x8 = False           # 16-bit A and X on entry
        reads, writes = {}, set()
        in_tsc, tsc_delta = False, 0
        for off, line in enumerate(body[prologue_end:], start=prologue_end):
            if LABEL_PREFIX.match(line):
                depth = 0
            c = code(line)

            if TSC.match(c):
                in_tsc, tsc_delta = True, 0
                continue
            if in_tsc:
                m = ADDSUB.match(c)
                if m:
                    n = int(m.group(2))
                    tsc_delta += n if m.group(1) == "adc" else -n
                    continue
                if TCS.match(c):
                    depth += tsc_delta
                    in_tsc = False
                    continue
                if c.strip() in ("clc", "sec"):
                    continue
                in_tsc = False       # not the idiom after all

            w = WIDTH.match(c)
            if w:
                bits = int(w.group(2))
                setting = w.group(1) == "sep"        # sep sets the flag = 8-bit
                if bits & 0x20:
                    a8 = setting
                if bits & 0x10:
                    x8 = setting
                continue

            m = STACK.match(c)
            if m:
                op, slot = m.group(1), depth + int(m.group(2))
                if op.startswith("st"):
                    writes.add(slot)
                    # A store also covers the NEXT slot. Byte-granular access
                    # to the halves of a 16-bit local is routine - store the
                    # word at N, then read N for the low byte and N+1 for the
                    # high - and counting only the named slot reports that as an
                    # unwritten read. Doing this unconditionally rather than
                    # from the tracked M/X width, because the width at a given
                    # instruction is only as good as a linear walk can make it.
                    #
                    # TRADE-OFF: this can no longer catch a defect that affects
                    # ONLY the high byte of a 16-bit local. Every real instance
                    # found so far (see bugreport/README.md) discards the whole
                    # value, so the reproducer still catches all three.
                    writes.add(slot + 1)
                else:
                    reads.setdefault(slot, a + off + 1)
                continue

            p = PUSH.match(c)
            if p:
                op = p.group(1)
                depth -= 1 if op in ("php", "phb", "phk") else \
                         (1 if (a8 if op == "pha" else x8) else 2) \
                         if op in ("pha", "phx", "phy") else 2
                continue

            p = PULL.match(c)
            if p:
                op = p.group(1)
                depth += 1 if op in ("plp", "plb") else \
                         (1 if (a8 if op == "pla" else x8) else 2) \
                         if op in ("pla", "plx", "ply") else 2
                continue

        for slot, lineno in sorted(reads.items()):
            # slots inside our own frame only; higher offsets are arguments
            if slot <= frame and slot not in writes:
                findings.append((name, slot, frame, lineno))

    return findings, len(funcs)


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: scan_stackslots.py <file.s> [...]")
    total = 0
    for path in sys.argv[1:]:
        findings, nfuncs = scan(path)
        print(f"{path}: {nfuncs} functions")
        for name, slot, frame, lineno in findings:
            print(f"  {path}:{lineno}: {name} reads {slot},s "
                  f"(frame {frame} bytes) but never writes it")
        total += len(findings)
    print(f"{total} suspect slot read(s)")
    return 1 if total else 0


if __name__ == "__main__":
    raise SystemExit(main())
