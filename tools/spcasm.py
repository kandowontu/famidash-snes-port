#!/usr/bin/env python3
"""A two-pass SPC700 assembler.

The toolchain has nothing that targets the SPC700 - Calypsi is 65816 only and
ca65 has no SPC700 CPU - so the audio driver would otherwise have to be a table
of hand-encoded bytes. That is not a readable driver and not a maintainable one.

WHAT IT REFUSES TO DO. Every mnemonic/addressing-mode pair is looked up in an
explicit table and an unrecognised combination is a hard error. There is no
"assume absolute", no silent widening of a direct-page operand, and no default
for a missing operand form. The reason is the shape of this project's worst
bugs: a tool that quietly produces plausible output is how a whole milestone
shipped subtly wrong (docs/HANDOFF.md traps 9, 17, 94). If this file cannot
encode something, it says so and stops.

SYNTAX

    ; comment                      and # is NOT a comment - it is immediate mode
    NAME = $1234                   equate
    label:                         label
    .org $0300                     set the assembly address
    .byte $01, 2, label            emit bytes
    .word $1234, label             emit little-endian words
    .space 16                      emit N zero bytes
    .incbin "file"                 emit a file verbatim
    .align 256                     pad to a multiple of N

    mov a, #$12                    immediate
    mov a, $12                     direct page       - bare, no prefix
    mov a, $12+x                   direct page + X
    mov a, !$1234                  absolute          - the ! is REQUIRED
    mov a, !$1234+x                absolute + X
    mov a, (x)   (x)+   (y)        indirect
    mov a, [$12+x]                 dp indexed indirect
    mov a, [$12]+y                 dp indirect indexed
    set1 $12.3                     bit of a dp byte
    and1 c, !$1234.5               bit of an absolute byte
    and1 c, /!$1234.5              ...complemented

Direct page vs absolute is NOT inferred from the value. `$12` is always direct
page and `!$12` is always absolute, exactly as every SPC700 assembler spells it
- an address that happens to be small is not a reason to change the instruction
that reads it, and the driver relies on that (the DSP is reached through the
direct-page registers at $F2/$F3).

    python tools/spcasm.py driver.s -o out/driver.bin --listing out/driver.lst
    python tools/spcasm.py --selftest
"""

import argparse
import re
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# The opcode table.
#
# Keyed by (MNEMONIC, operand-form-tuple). The forms are the canonical strings
# produced by parse_operand() below; "imm", "dp", "abs" and "rel" also say how
# many bytes of operand follow and in what order.
#
# Operand BYTE ORDER is not always the source order: `mov dp,dp` stores the
# SOURCE first, and `mov dp,#imm` stores the IMMEDIATE first. The third element
# of each entry lists the operands in the order they are emitted, by index into
# the source form tuple.
# --------------------------------------------------------------------------
OPS = {}


def op(mnemonic, forms, opcode, order=None):
    key = (mnemonic, tuple(forms))
    if key in OPS:
        raise AssertionError("duplicate table entry %r" % (key,))
    if order is None:
        order = tuple(range(len(forms)))
    OPS[key] = (opcode, order)


# ---- MOV ------------------------------------------------------------------
op("MOV", ["A", "imm"],      0xE8)
op("MOV", ["A", "dp"],       0xE4)
op("MOV", ["A", "dp+X"],     0xF4)
op("MOV", ["A", "abs"],      0xE5)
op("MOV", ["A", "abs+X"],    0xF5)
op("MOV", ["A", "abs+Y"],    0xF6)
op("MOV", ["A", "(X)"],      0xE6)
op("MOV", ["A", "(X)+"],     0xBF)
op("MOV", ["A", "[dp+X]"],   0xE7)
op("MOV", ["A", "[dp]+Y"],   0xF7)
op("MOV", ["X", "imm"],      0xCD)
op("MOV", ["X", "dp"],       0xF8)
op("MOV", ["X", "dp+Y"],     0xF9)
op("MOV", ["X", "abs"],      0xE9)
op("MOV", ["Y", "imm"],      0x8D)
op("MOV", ["Y", "dp"],       0xEB)
op("MOV", ["Y", "dp+X"],     0xFB)
op("MOV", ["Y", "abs"],      0xEC)
op("MOV", ["dp", "A"],       0xC4)
op("MOV", ["dp+X", "A"],     0xD4)
op("MOV", ["abs", "A"],      0xC5)
op("MOV", ["abs+X", "A"],    0xD5)
op("MOV", ["abs+Y", "A"],    0xD6)
op("MOV", ["(X)", "A"],      0xC6)
op("MOV", ["(X)+", "A"],     0xAF)
op("MOV", ["[dp+X]", "A"],   0xC7)
op("MOV", ["[dp]+Y", "A"],   0xD7)
op("MOV", ["dp", "X"],       0xD8)
op("MOV", ["dp+Y", "X"],     0xD9)
op("MOV", ["abs", "X"],      0xC9)
op("MOV", ["dp", "Y"],       0xCB)
op("MOV", ["dp+X", "Y"],     0xDB)
op("MOV", ["abs", "Y"],      0xCC)
# dest,source in the source text; the ENCODING stores source first.
op("MOV", ["dp", "dp"],      0xFA, order=(1, 0))
# dest,#imm in the source text; the ENCODING stores the immediate first.
op("MOV", ["dp", "imm"],     0x8F, order=(1, 0))
op("MOV", ["A", "X"],        0x7D)
op("MOV", ["A", "Y"],        0xDD)
op("MOV", ["X", "A"],        0x5D)
op("MOV", ["Y", "A"],        0xFD)
op("MOV", ["X", "SP"],       0x9D)
op("MOV", ["SP", "X"],       0xBD)
op("MOVW", ["YA", "dp"],     0xBA)
op("MOVW", ["dp", "YA"],     0xDA)

# ---- the eight ALU ops, which share one addressing-mode layout -------------
for name, base in (("OR", 0x00), ("AND", 0x20), ("EOR", 0x40),
                   ("CMP", 0x60), ("ADC", 0x80), ("SBC", 0xA0)):
    op(name, ["A", "imm"],    base + 0x08)
    op(name, ["A", "dp"],     base + 0x04)
    op(name, ["A", "dp+X"],   base + 0x14)
    op(name, ["A", "abs"],    base + 0x05)
    op(name, ["A", "abs+X"],  base + 0x15)
    op(name, ["A", "abs+Y"],  base + 0x16)
    op(name, ["A", "(X)"],    base + 0x06)
    op(name, ["A", "[dp+X]"], base + 0x07)
    op(name, ["A", "[dp]+Y"], base + 0x17)
    op(name, ["(X)", "(Y)"],  base + 0x19)
    op(name, ["dp", "dp"],    base + 0x09, order=(1, 0))
    op(name, ["dp", "imm"],   base + 0x18, order=(1, 0))

op("CMP", ["X", "imm"],  0xC8)
op("CMP", ["X", "dp"],   0x3E)
op("CMP", ["X", "abs"],  0x1E)
op("CMP", ["Y", "imm"],  0xAD)
op("CMP", ["Y", "dp"],   0x7E)
op("CMP", ["Y", "abs"],  0x5E)

# ---- read/modify/write ----------------------------------------------------
for name, (a, d, dx, ab) in {
        "INC": (0xBC, 0xAB, 0xBB, 0xAC),
        "DEC": (0x9C, 0x8B, 0x9B, 0x8C),
        "ASL": (0x1C, 0x0B, 0x1B, 0x0C),
        "LSR": (0x5C, 0x4B, 0x5B, 0x4C),
        "ROL": (0x3C, 0x2B, 0x3B, 0x2C),
        "ROR": (0x7C, 0x6B, 0x7B, 0x6C)}.items():
    op(name, ["A"],     a)
    op(name, ["dp"],    d)
    op(name, ["dp+X"],  dx)
    op(name, ["abs"],   ab)
op("INC", ["X"], 0x3D)
op("INC", ["Y"], 0xFC)
op("DEC", ["X"], 0x1D)
op("DEC", ["Y"], 0xDC)
op("XCN", ["A"], 0x9F)

op("ADDW", ["YA", "dp"], 0x7A)
op("SUBW", ["YA", "dp"], 0x9A)
op("CMPW", ["YA", "dp"], 0x5A)
op("INCW", ["dp"],       0x3A)
op("DECW", ["dp"],       0x1A)
op("MUL",  ["YA"],       0xCF)
op("DIV",  ["YA", "X"],  0x9E)
op("DAA",  ["A"],        0xDF)
op("DAS",  ["A"],        0xBE)

# ---- branches -------------------------------------------------------------
for name, code in (("BRA", 0x2F), ("BEQ", 0xF0), ("BNE", 0xD0), ("BCS", 0xB0),
                   ("BCC", 0x90), ("BVS", 0x70), ("BVC", 0x50), ("BMI", 0x30),
                   ("BPL", 0x10)):
    op(name, ["rel"], code)
for b in range(8):
    op("BBS%d" % b, ["dp", "rel"], 0x03 + b * 0x20)
    op("BBC%d" % b, ["dp", "rel"], 0x13 + b * 0x20)
op("CBNE", ["dp", "rel"],   0x2E)
op("CBNE", ["dp+X", "rel"], 0xDE)
op("DBNZ", ["dp", "rel"],   0x6E)
op("DBNZ", ["Y", "rel"],    0xFE)

op("JMP",  ["abs"],       0x5F)
op("JMP",  ["[abs+X]"],   0x1F)
op("CALL", ["abs"],       0x3F)
op("RET",  [],            0x6F)
op("RETI", [],            0x7F)
op("BRK",  [],            0x0F)

# ---- stack ----------------------------------------------------------------
op("PUSH", ["A"], 0x2D)
op("PUSH", ["X"], 0x4D)
op("PUSH", ["Y"], 0x6D)
op("PUSH", ["PSW"], 0x0D)
op("POP", ["A"], 0xAE)
op("POP", ["X"], 0xCE)
op("POP", ["Y"], 0xEE)
op("POP", ["PSW"], 0x8E)

# ---- bits and flags -------------------------------------------------------
for b in range(8):
    op("SET1", ["dp.%d" % b], 0x02 + b * 0x20)
    op("CLR1", ["dp.%d" % b], 0x12 + b * 0x20)
op("TSET1", ["abs"], 0x0E)
op("TCLR1", ["abs"], 0x4E)
op("AND1", ["C", "membit"],  0x4A)
op("AND1", ["C", "/membit"], 0x6A)
op("OR1",  ["C", "membit"],  0x0A)
op("OR1",  ["C", "/membit"], 0x2A)
op("EOR1", ["C", "membit"],  0x8A)
op("NOT1", ["membit"],       0xEA)
op("MOV1", ["C", "membit"],  0xAA)
op("MOV1", ["membit", "C"],  0xCA)
for name, code in (("CLRC", 0x60), ("SETC", 0x80), ("NOTC", 0xED),
                   ("CLRV", 0xE0), ("CLRP", 0x20), ("SETP", 0x40),
                   ("EI", 0xA0), ("DI", 0xC0), ("NOP", 0x00),
                   ("SLEEP", 0xEF), ("STOP", 0xFF)):
    op(name, [], code)


# Which forms carry an operand byte, and how wide.
WIDTH = {"imm": 1, "dp": 1, "dp+X": 1, "dp+Y": 1, "[dp+X]": 1, "[dp]+Y": 1,
         "abs": 2, "abs+X": 2, "abs+Y": 2, "[abs+X]": 2, "rel": 1,
         "membit": 2, "/membit": 2}
for _b in range(8):
    WIDTH["dp.%d" % _b] = 1


# Mnemonics whose LAST operand is a relative branch target.
RELATIVE_LAST = ({"BRA", "BEQ", "BNE", "BCS", "BCC", "BVS", "BVC", "BMI",
                  "BPL", "CBNE", "DBNZ"}
                 | {"BBS%d" % b for b in range(8)}
                 | {"BBC%d" % b for b in range(8)})


class AsmError(Exception):
    pass


def parse_operand(text):
    """-> (form, expression-or-None). Raises on anything not understood."""
    t = text.strip()
    up = t.upper()
    if up in ("A", "X", "Y", "YA", "SP", "PSW", "C"):
        return up, None
    if t.startswith("#"):
        return "imm", t[1:]

    m = re.fullmatch(r"\((?i:x)\)\+", t)
    if m:
        return "(X)+", None
    m = re.fullmatch(r"\((?i:[xy])\)", t)
    if m:
        return "(%s)" % t[1].upper(), None

    m = re.fullmatch(r"\[(.+)\+\s*(?i:x)\]", t)
    if m:
        inner = m.group(1).strip()
        if inner.startswith("!"):
            return "[abs+X]", inner[1:]
        return "[dp+X]", inner
    m = re.fullmatch(r"\[(.+)\]\+\s*(?i:y)", t)
    if m:
        return "[dp]+Y", m.group(1).strip()

    comp = False
    if t.startswith("/"):
        comp, t = True, t[1:].strip()

    # A bit selector binds tighter than anything else here: `!$1234.5`.
    m = re.fullmatch(r"(.+)\.(\d)", t)
    if m and not m.group(1).strip().endswith("+"):
        addr, bit = m.group(1).strip(), int(m.group(2))
        if addr.startswith("!"):
            return ("/membit" if comp else "membit"), (addr[1:], bit)
        if comp:
            raise AsmError("a complemented bit needs an absolute address: %s" % text)
        return "dp.%d" % bit, addr
    if comp:
        raise AsmError("'/' is only valid on an absolute bit: %s" % text)

    m = re.fullmatch(r"(.+?)\s*\+\s*(?i:([xy]))", t)
    if m:
        addr, idx = m.group(1).strip(), m.group(2).upper()
        if addr.startswith("!"):
            return "abs+%s" % idx, addr[1:]
        return "dp+%s" % idx, addr

    if t.startswith("!"):
        return "abs", t[1:]
    return "dp", t


def tokenize_operands(text):
    """Split on commas that are not inside brackets or parentheses."""
    out, depth, cur = [], 0, ""
    for ch in text:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return [o for o in out if o.strip()]


def strip_comment(line):
    """Drop a ';' comment, but not one inside a string literal."""
    out, in_str = "", False
    for ch in line:
        if ch == '"':
            in_str = not in_str
        if ch == ";" and not in_str:
            break
        out += ch
    return out


class Assembler:
    def __init__(self, base=0x0200, incdir="."):
        self.base = base
        self.incdir = Path(incdir)
        self.symbols = {}
        self.listing = []

    # ---- expressions ------------------------------------------------------
    def evaluate(self, expr, strict):
        """$hex / %bin / decimal / symbols / + - * / ( ) << >> & | ^.

        A leading `<` or `>` takes the low or high byte, as every 6502-family
        assembler spells it. It is stripped here rather than parsed as an
        operator because `<<` and `>>` mean shifts everywhere else in the same
        expression grammar.
        """
        expr = expr.strip()
        half = None
        if expr[:1] in ("<", ">") and expr[:2] not in ("<<", ">>"):
            half, expr = expr[0], expr[1:]

        e = re.sub(r"\$([0-9A-Fa-f]+)", lambda m: str(int(m.group(1), 16)), expr)
        e = re.sub(r"%([01]+)", lambda m: str(int(m.group(1), 2)), e)

        def sub(m):
            name = m.group(0)
            if name in self.symbols:
                return str(self.symbols[name])
            if strict:
                raise AsmError("undefined symbol '%s'" % name)
            return "0"                      # pass 1: any value of the right size
        e = re.sub(r"[A-Za-z_.][A-Za-z0-9_.]*", sub, e)
        if not re.fullmatch(r"[-+*/()<>&|^ 0-9]*", e):
            raise AsmError("cannot evaluate %r" % expr)
        try:
            v = int(eval(e, {"__builtins__": {}}, {}))       # noqa: S307
        except Exception as exc:
            raise AsmError("cannot evaluate %r: %s" % (expr, exc))
        if half == "<":
            return v & 0xFF
        if half == ">":
            return (v >> 8) & 0xFF
        return v

    # ---- one pass ---------------------------------------------------------
    def assemble(self, text, strict):
        pc = self.base
        out = bytearray()

        def emit(*bs):
            nonlocal pc
            out.extend(bs)
            pc += len(bs)

        for lineno, raw in enumerate(text.split("\n"), 1):
            line = strip_comment(raw).strip()
            if not line:
                continue
            try:
                # label: / NAME = value
                m = re.match(r"^([A-Za-z_.][A-Za-z0-9_.]*)\s*:\s*(.*)$", line)
                if m:
                    name, line = m.group(1), m.group(2).strip()
                    if not strict:
                        if name in self.symbols and self.symbols[name] != pc:
                            pass            # pass 1 refines it; pass 2 must agree
                        self.symbols[name] = pc
                    elif self.symbols.get(name) != pc:
                        raise AsmError("label '%s' moved between passes" % name)
                    if not line:
                        continue
                m = re.fullmatch(r"([A-Za-z_.][A-Za-z0-9_.]*)\s*=\s*(.+)", line)
                if m:
                    self.symbols[m.group(1)] = self.evaluate(m.group(2), strict)
                    continue

                parts = line.split(None, 1)
                mnem = parts[0].upper()
                rest = parts[1] if len(parts) > 1 else ""

                # ---- directives ----
                if mnem == ".ORG":
                    want = self.evaluate(rest, strict)
                    if want < pc:
                        raise AsmError(".org $%04X goes backwards from $%04X"
                                       % (want, pc))
                    emit(*([0] * (want - pc)))
                    continue
                if mnem == ".ALIGN":
                    n = self.evaluate(rest, strict)
                    while pc % n:
                        emit(0)
                    continue
                if mnem == ".SPACE":
                    emit(*([0] * self.evaluate(rest, strict)))
                    continue
                if mnem == ".BYTE":
                    for e in tokenize_operands(rest):
                        emit(self.evaluate(e, strict) & 0xFF)
                    continue
                if mnem == ".WORD":
                    for e in tokenize_operands(rest):
                        v = self.evaluate(e, strict) & 0xFFFF
                        emit(v & 0xFF, v >> 8)
                    continue
                if mnem == ".INCBIN":
                    path = self.incdir / rest.strip().strip('"')
                    if not path.exists():
                        raise AsmError("%s not found" % path)
                    emit(*path.read_bytes())
                    continue
                if mnem.startswith("."):
                    raise AsmError("unknown directive %s" % mnem)

                # ---- instructions ----
                forms, exprs = [], []
                for tok in tokenize_operands(rest):
                    f, e = parse_operand(tok)
                    forms.append(f)
                    exprs.append(e)

                # A branch target is a plain label, which parses as a direct
                # page address like any other bare expression. Nothing in the
                # operand text distinguishes the two - it is the MNEMONIC that
                # decides - so the last operand of a branch is retyped here.
                if mnem in RELATIVE_LAST and forms:
                    if forms[-1] not in ("dp", "abs"):
                        raise AsmError("%s wants a label, got %s"
                                       % (mnem, forms[-1]))
                    forms[-1] = "rel"

                key = (mnem, tuple(forms))
                if key not in OPS:
                    raise AsmError("no SPC700 encoding for %s %s"
                                   % (mnem, ", ".join(forms)))
                opcode, order = OPS[key]
                start = pc
                emit(opcode)
                for i in order:
                    form, expr = forms[i], exprs[i]
                    w = WIDTH.get(form)
                    if w is None:
                        continue
                    if form in ("membit", "/membit"):
                        addr = self.evaluate(expr[0], strict) & 0x1FFF
                        v = addr | (expr[1] << 13)
                        emit(v & 0xFF, v >> 8)
                    elif form == "rel":
                        target = self.evaluate(expr, strict)
                        # The displacement is from the byte AFTER the operand,
                        # which for BBS/CBNE/DBNZ is not the byte after the
                        # opcode - getting that wrong lands one byte off and
                        # only on the multi-operand branches.
                        delta = target - (pc + 1)
                        if strict and not -128 <= delta <= 127:
                            raise AsmError("branch out of range: %+d to $%04X"
                                           % (delta, target))
                        emit(delta & 0xFF)
                    elif w == 1:
                        v = self.evaluate(expr, strict)
                        if strict and form != "imm" and not 0 <= v <= 0xFF:
                            raise AsmError("$%04X is not a direct-page address "
                                           "(use ! for absolute)" % v)
                        emit(v & 0xFF)
                    else:
                        v = self.evaluate(expr, strict) & 0xFFFF
                        emit(v & 0xFF, v >> 8)
                if strict:
                    self.listing.append("%04X  %-14s %s"
                                        % (start,
                                           " ".join("%02X" % b for b in
                                                    out[start - self.base:pc - self.base]),
                                           line))
            except AsmError as exc:
                raise AsmError("line %d: %s\n    %s" % (lineno, exc, raw.strip()))
        return bytes(out)

    def run(self, text):
        self.assemble(text, strict=False)
        self.listing = []
        return self.assemble(text, strict=True)


SELFTEST = [
    # (source, expected bytes). Encodings that the driver actually relies on,
    # including every one where the operand order or the branch base is not the
    # obvious thing.
    ("mov a, #$12",           "E8 12"),
    ("mov a, $12",            "E4 12"),
    ("mov a, !$1234",         "E5 34 12"),
    ("mov a, !$1234+x",       "F5 34 12"),
    ("mov $f2, #$4c",         "8F 4C F2"),      # immediate FIRST
    ("mov $10, $20",          "FA 20 10"),      # source FIRST
    ("mov $f3, a",            "C4 F3"),
    ("movw ya, $10",          "BA 10"),
    ("movw $10, ya",          "DA 10"),
    ("mov a, [$10]+y",        "F7 10"),
    ("mov a, (x)+",           "BF"),
    ("cmp a, #$08",           "68 08"),
    ("adc a, $30",            "84 30"),
    ("and a, #$0f",           "28 0F"),
    ("eor a, #$ff",           "48 FF"),
    ("or a, $05",             "04 05"),
    ("asl a",                 "1C"),
    ("lsr $10",               "4B 10"),
    ("inc x",                 "3D"),
    ("mul ya",                "CF"),
    ("div ya, x",             "9E"),
    ("set1 $10.3",            "62 10"),
    ("clr1 $10.7",            "F2 10"),
    ("call !$0400",           "3F 00 04"),
    ("ret",                   "6F"),
    ("here: bra here",        "2F FE"),
    ("here: dbnz $10, here",  "6E 10 FD"),      # base is AFTER both operands
    ("here: cbne $10, here",  "2E 10 FD"),
    ("here: bbs2 $10, here",  "43 10 FD"),
    ("nop",                   "00"),
]


def selftest():
    bad = 0
    for src, want in SELFTEST:
        want_b = bytes(int(x, 16) for x in want.split())
        try:
            got = Assembler(base=0x0200).run(src)
        except AsmError as exc:
            print("FAIL  %-24s %s" % (src, exc))
            bad += 1
            continue
        if got != want_b:
            print("FAIL  %-24s want %s  got %s"
                  % (src, want, " ".join("%02X" % b for b in got)))
            bad += 1
    print("spcasm selftest: %d/%d encodings correct" % (len(SELFTEST) - bad,
                                                        len(SELFTEST)))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source", nargs="?")
    ap.add_argument("-o", "--output")
    ap.add_argument("--base", default="0x0200")
    ap.add_argument("--incdir", help="where .incbin looks; defaults to the "
                                     "source file's own directory")
    ap.add_argument("--listing")
    ap.add_argument("--symbols", help="write NAME=addr lines here")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if not args.source or not args.output:
        ap.error("need a source file and -o")

    src = Path(args.source)
    asm = Assembler(base=int(args.base, 0), incdir=args.incdir or src.parent)
    try:
        image = asm.run(src.read_text())
    except AsmError as exc:
        sys.exit("%s: %s" % (src, exc))

    Path(args.output).write_bytes(image)
    if args.listing:
        Path(args.listing).write_text("\n".join(asm.listing) + "\n")
    if args.symbols:
        Path(args.symbols).write_text(
            "".join("%s=%d\n" % (k, v) for k, v in sorted(asm.symbols.items())))
    print("    %s: %d bytes at $%04X-$%04X"
          % (Path(args.output).name, len(image), asm.base,
             asm.base + len(image) - 1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
