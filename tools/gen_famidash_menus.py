#!/usr/bin/env python3
"""Convert the original Famidash menu screens and CHR for the SNES port.

The source screens are NES nametables compressed with neslib's tag RLE.  This
keeps the art pixel-identical: only the CHR byte layout and attribute table are
translated to SNES Mode 0.
"""
import argparse
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import snes_m0


def c_arrays(path: Path, name: str):
    text = path.read_text(errors="replace")
    pat = (r"const\s+unsigned\s+char\s+" + re.escape(name)
           + r"\s*\[\s*\d*\s*\]\s*=\s*\{(.*?)\};")
    out = []
    for body in re.findall(pat, text, re.S):
        out.append(bytes(int(x, 16) for x in re.findall(r"0x([0-9A-Fa-f]+)", body)))
    if not out:
        raise RuntimeError(f"{path}: no {name} arrays")
    return out


def neslib_rle(data: bytes):
    tag = data[0]
    out = bytearray()
    p = 1
    while p < len(data):
        b = data[p]
        p += 1
        if b != tag:
            out.append(b)
            continue
        count = data[p]
        p += 1
        if count == 0:
            break
        out.extend([out[-1]] * count)
    if len(out) != 1024:
        raise RuntimeError(f"RLE expanded to {len(out)}, expected 1024")
    return out


def snes_map(nametable: bytes):
    """NES 960-byte tilemap + 64-byte attributes -> 32x32 SNES map words."""
    out = bytearray(2048)
    for y in range(32):
        for x in range(32):
            tile = nametable[y * 32 + x] if y < 30 else 0
            if y < 30:
                attr = nametable[960 + (y // 4) * 8 + (x // 4)]
                shift = ((y & 2) << 1) | (x & 2)
                pal = (attr >> shift) & 3
            else:
                pal = 0
            word = tile | (pal << 10)
            i = (y * 32 + x) * 2
            out[i] = word & 0xFF
            out[i + 1] = word >> 8
    return out


def parse_menu_lines(root: Path, count=168):
    """Exact two-line names used by refreshmenuHUGE.c, already padded to 17."""
    h = (root / "LEVELS/include/lvlset_HUGE/menutext.h").read_text(
        errors="replace")
    strings = {
        int(i, 16): s
        for i, s in re.findall(
            r'const\s+char\s+levelText([0-9A-Fa-f]+)\s*\[\s*\d+\s*\]\s*=\s*"([^"]*)"',
            h)
    }
    asm = (root / "LEVELS/include/lvlset_HUGE/menutext.s").read_text(
        errors="replace")

    def table(label, next_label):
        m = re.search(r"^" + label + r":\s*$([\s\S]*?)^" + next_label + r":\s*$",
                      asm, re.M)
        if not m:
            raise RuntimeError(f"menutext.s: {label} not found")
        vals = []
        for line in m.group(1).splitlines():
            bm = re.match(r"\s*\.byte\s+(.*)", line)
            if not bm:
                continue
            token = bm.group(1).strip()
            tm = re.search(r"_levelText([0-9A-Fa-f]+)", token)
            vals.append(strings[int(tm.group(1), 16)] if tm else "")
            if len(vals) == count:
                break
        if len(vals) != count:
            raise RuntimeError(f"{label}: got {len(vals)} entries")
        return vals

    upper = table("_levelTextsUpper_lo", "_levelTextsUpper_hi")
    lower = table("_levelTextsLower_lo", "_levelTextsLower_hi")

    def menu_tile(ch):
        if ch == " ":
            return 0xFE
        if ch == "^":
            return 0x8F
        if ch == "_":
            return 0x0F
        if "0" <= ch <= "9":
            return 0xB0 + ord(ch) - ord("0")
        if "A" <= ch <= "U":
            return 0xBB + ord(ch) - ord("A")
        if "V" <= ch <= "Z":
            return 0xDB + ord(ch) - ord("V")
        raise RuntimeError(f"unmapped menu character {ch!r}")

    data = bytearray()
    for a, b in zip(upper, lower):
        for line in (a, b):
            # _draw_padded_text centers within 17 tiles: floor(padding/2) on
            # the left and ceil(padding/2) on the right.
            data.extend(menu_tile(ch) for ch in line[:17].center(17))
    return data


def parse_level_menu_metadata(root: Path, count=168):
    """Difficulty/star tables used by the Huge Man level-select screen."""
    text = (root / "LEVELS/include/lvlset_HUGE/levellist.h").read_text(
        errors="replace")
    difficulty_names = {
        "EASY": 0, "NORMAL": 1, "HARD": 2, "HARDER": 3,
        "INSANE": 4, "DEMON": 5, "AUTO": 6,
        "EASYDEMON": 0, "MEDIUMDEMON": 1, "HARDDEMON": 2,
        "INSANEDEMON": 3, "EXTREMEDEMON": 4,
        "IMPOSSIBLEDEMON": 5, "GRANDPADEMON": 6,
    }

    def array_body(name):
        match = re.search(
            r"const\s+uint8_t\s+" + re.escape(name)
            + r"\s*\[\s*\]\s*=\s*\{(.*?)\};", text, re.S)
        if not match:
            raise RuntimeError(f"levellist.h: {name} not found")
        return match.group(1)

    difficulties = bytearray()
    for line in array_body("difficulty_list").splitlines():
        token = line.split("//", 1)[0].strip().rstrip(",").strip()
        if token:
            difficulties.append(difficulty_names[token])

    stars = bytearray()
    for value in re.findall(r"\b(\d+)\s*,", array_body("stars_list")):
        stars.append(int(value))

    colors_text = (
        root / "LEVELS/include/lvlset_HUGE/const_levellist.h"
    ).read_text(errors="replace")
    colors_match = re.search(
        r"colors_list\s*\[\s*\]\s*=\s*\{(.*?)\};", colors_text, re.S)
    if not colors_match:
        raise RuntimeError("const_levellist.h: colors_list not found")
    colors = bytearray(
        int(value, 16)
        for value in re.findall(r"0x([0-9A-Fa-f]+)", colors_match.group(1)))

    if len(difficulties) != count or len(stars) != count or len(colors) != 9:
        raise RuntimeError(
            "menu metadata size mismatch: "
            f"difficulty={len(difficulties)}, stars={len(stars)}, "
            f"colors={len(colors)}")
    return difficulties, stars, colors


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="C:/famidash")
    ap.add_argument("--outdir", default=str(HERE.parent / "out"))
    args = ap.parse_args()
    root = Path(args.root)
    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)

    gfx = root / "GRAPHICS/Menus"
    (out / "famidash_menu_bg.tiles.bin").write_bytes(
        snes_m0.nes_chr_to_snes_2bpp((gfx / "menus.chr").read_bytes()))
    (out / "famidash_menu_cursor.tiles.bin").write_bytes(
        snes_m0.nes_chr_to_snes_4bpp((gfx / "cursors.chr").read_bytes()))
    (out / "famidash_menu_demon.tiles.bin").write_bytes(
        snes_m0.nes_chr_to_snes_2bpp((gfx / "HUGE-demon.chr").read_bytes()))
    (out / "famidash_end_bg.tiles.bin").write_bytes(
        snes_m0.nes_chr_to_snes_2bpp((gfx / "levelcomplete.chr").read_bytes()))

    practice = bytearray((gfx / "levelcomplete.chr").read_bytes())
    practice[1024:2048] = (gfx / "practicecomplete.chr").read_bytes()
    (out / "famidash_practice_bg.tiles.bin").write_bytes(
        snes_m0.nes_chr_to_snes_2bpp(practice))

    nt03 = root / "SAUCE/defines/nametable/menunametable_XCD03.c"
    nt06 = root / "SAUCE/defines/nametable/menunametable_XCD06.c"
    # index 1 is the non-VS level select; index 0 of the HUGE main-menu branch.
    screens = {
        "famidash_levelselect.map.bin":
            c_arrays(nt03, "level_select_screen")[1],
        "famidash_title.map.bin":
            c_arrays(nt03, "game_start_screen")[0],
        "famidash_end.map.bin":
            c_arrays(nt06, "leveldone")[0],
        "famidash_practice.map.bin":
            c_arrays(nt06, "practicedone")[0],
    }
    for name, packed in screens.items():
        (out / name).write_bytes(snes_map(neslib_rle(packed)))

    lines = parse_menu_lines(root)
    (out / "famidash_level_lines.bin").write_bytes(lines)
    difficulties, stars, colors = parse_level_menu_metadata(root)
    (out / "famidash_difficulty.bin").write_bytes(difficulties)
    (out / "famidash_stars.bin").write_bytes(stars)
    (out / "famidash_menu_colors.bin").write_bytes(colors)
    print("    Famidash menus (original title, level select, completion; "
          "CHR, maps, exact 2-line level labels)")


if __name__ == "__main__":
    raise SystemExit(main())
