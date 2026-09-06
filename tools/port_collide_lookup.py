#!/usr/bin/env python3
"""Rewrite sprite_collide_lookup()'s computed-goto dispatch as a switch.

Calypsi's 65816 backend ICEs on `&&label` / `goto *expr` (docs/HANDOFF.md trap
11). functions/sprite_loading.h dispatches sprite collision through two
256-entry tables of label addresses, into 64 labels inside one function - with
`goto spcl_*` jumps between those labels and deliberate fallthrough between
adjacent ones.

The transformation is deliberately the minimal one:

  - the two `static void * const` tables are deleted;
  - the `goto *table[collided]` dispatch becomes `switch (collided) {`;
  - each existing `spcl_foo:` label KEEPS its name and gains the `case` labels
    for every table index that pointed at it.

Keeping the labels is what makes this safe: the `goto spcl_*` jumps still
resolve, and because no body is moved, fallthrough between labels is preserved
exactly as the original had it. A C label and a case label may share a
statement, so `case 5: spcl_foo: ...` is valid.

Run against the overlay copy (idempotent - refuses if already ported):

    python tools/port_collide_lookup.py overlay/functions/sprite_loading.h
"""
import re
import sys
from pathlib import Path

TABLE_RE = re.compile(
    r"\tstatic void \* const (sprite_collide_jump_table_[01])\[\] = \{(.*?)\n\t\};\n",
    re.S)
LABEL_RE = re.compile(r"^\tspcl_([a-z0-9_]+):", re.M)

DISPATCH = """	// Instead of the giant ass switch : case that used to be here
	if (collided < 0x7F)
		goto *sprite_collide_jump_table_0[collided];
	else if (collided == 0x7F) return;
	else if (collided >= 0x80)
		jumpInTableWithOffset(sprite_collide_jump_table_1, collided, 0);

"""

DISPATCH_NEW = """	// SNES port: this was a computed goto through two tables of label
	// addresses; Calypsi's 65816 backend does not support `goto *expr`
	// (docs/HANDOFF.md trap 11). It is a switch now, but every spcl_* label is
	// kept so the `goto spcl_*` jumps between arms still resolve and the
	// fallthrough between adjacent arms is unchanged. Case labels were
	// generated from the original tables by tools/port_collide_lookup.py.
	switch (collided) {

"""


def parse_tables(text):
    """index -> label name, from the two jump tables."""
    mapping = {}
    for m in TABLE_RE.finditer(text):
        base = 0x00 if m.group(1).endswith("0") else 0x80
        body = re.sub(r"//[^\n]*", "", m.group(2))     # strip the range comments
        names = re.findall(r"&&(spcl_[a-z0-9_]+)", body)
        for i, name in enumerate(names):
            mapping[base + i] = name
    return mapping


def main():
    path = Path(sys.argv[1] if len(sys.argv) > 1
                else "overlay/functions/sprite_loading.h")
    text = path.read_text(encoding="utf-8", errors="surrogateescape")

    # `switch (collided)` already occurs twice elsewhere in the file; the marker
    # for "already ported" is the absence of the computed goto.
    if "goto *sprite_collide_jump_table_0" not in text:
        sys.exit(f"{path}: already ported")

    mapping = parse_tables(text)
    if not mapping:
        sys.exit(f"{path}: jump tables not found")

    labels = set(LABEL_RE.findall(text))
    missing = {n for n in mapping.values()} - {"spcl_" + l for l in labels}
    if missing:
        sys.exit(f"{path}: tables reference labels with no definition: {missing}")

    # index -> label, inverted
    by_label = {}
    for idx, name in sorted(mapping.items()):
        by_label.setdefault(name, []).append(idx)

    text, n = TABLE_RE.subn("", text)
    if n != 2:
        sys.exit(f"expected 2 jump tables, removed {n}")
    if text.count(DISPATCH) != 1:
        sys.exit("dispatch block not found verbatim")
    text = text.replace(DISPATCH, DISPATCH_NEW)

    def add_cases(m):
        name = "spcl_" + m.group(1)
        idxs = by_label.get(name)
        lines = []
        if name == "spcl_default":
            lines.append("\tdefault:")            # 0x7F, 0xFF and any gap
        if idxs:
            for i in range(0, len(idxs), 8):
                chunk = " ".join(f"case 0x{v:02X}:" for v in idxs[i:i + 8])
                lines.append("\t" + chunk)
        lines.append(m.group(0))
        return "\n".join(lines)

    text, nlab = LABEL_RE.subn(add_cases, text)

    # close the switch just before the function's final brace
    tail = "\t\tupdate_currplayer_table_idx();\n\t\treturn;\n}\n"
    if text.count(tail) != 1:
        sys.exit("function tail not found verbatim")
    text = text.replace(tail, "\t\tupdate_currplayer_table_idx();\n"
                              "\t\treturn;\n\t}\n}\n")

    path.write_text(text, encoding="utf-8", errors="surrogateescape")
    covered = len(mapping)
    print(f"{path}: {nlab} labels, {covered} table entries mapped to "
          f"{len(by_label)} distinct labels")
    uncovered = sorted(set(range(0x100)) - set(mapping))
    print(f"  indices with no table entry (handled by default): "
          f"{', '.join(hex(u) for u in uncovered)}")


if __name__ == "__main__":
    raise SystemExit(main())
