#!/usr/bin/env python3
"""
Famidash SNES port - M0 asset pipeline.

Converts NES-side assets to SNES-native form and renders the result with a
software SNES PPU (Mode 0, 2bpp) so the pipeline can be validated without an
emulator or a 65816 toolchain.

Stages:
    1. aart_lz decompress      (level data outer layer)
    2. vertical RLE decode     (level data inner layer -> metatile columns)
    3. NES CHR  -> SNES 2bpp   (byte interleave)
    4. NES palette -> CGRAM    (15-bit BGR)
    5. metatiles -> SNES tilemap words (vhopppcc cccccccc)
    6. software SNES PPU -> PNG

Usage:  python snes_m0.py [--root C:/famidash] [--level stereomadness]
"""

import argparse
import re
import sys
from pathlib import Path

from PIL import Image

# --------------------------------------------------------------------------
# 1. aart_lz  (mirror of LEVELS/aart_lz.py compress())
# --------------------------------------------------------------------------

LZ_LITERAL = 0x80
LZ_END = 0xFF


def lz_decompress(data: bytes) -> bytearray:
    """Inverse of aart_lz.compress().

    Stream ops:
        0xFF                -> end
        0x80, b             -> literal b
        L, idx, b           -> copy L bytes from ring[idx:idx+L], then literal b

    The ring is 256 bytes, zero-initialised, and the copy source is always the
    *pre-write* ring state (compress() matches before appending), so reads are
    snapshotted before writes.  find_subarray() never wraps, so neither do we.
    """
    out = bytearray()
    ring = bytearray(256)
    w = 0
    p = 0

    def push(byte: int) -> None:
        nonlocal w
        ring[w] = byte
        w = (w + 1) & 0xFF

    while p < len(data):
        length = data[p]
        p += 1
        if length == LZ_END:
            break
        if length == LZ_LITERAL:
            b = data[p]
            p += 1
            out.append(b)
            push(b)
            continue
        idx = data[p]
        b = data[p + 1]
        p += 2
        copied = bytes(ring[idx:idx + length])   # snapshot before writing
        out.extend(copied)
        for v in copied:
            push(v)
        out.append(b)
        push(b)

    return out


# --------------------------------------------------------------------------
# 2. vertical RLE  (mirror of export_levels.vertical_rle_with_single_tile())
# --------------------------------------------------------------------------

META_SEQ = 0x7F


def rle_decode(data: bytes, height: int):
    """Decode the vertical RLE stream into column-major metatile indices.

    Ops:
        b >= 0x80    -> single metatile (b & 0x7F)
        b <  0x80    -> run of (b + 1) copies of the following byte

    A run byte of 0x7F carrying tile 0x7F is the bank-continuation escape
    emitted by split_rle_data_into_compressed_banks(); one pointer byte
    follows and the stream ends there.
    """
    tiles = []
    p = 0
    continued_in = None

    while p < len(data):
        b = data[p]
        p += 1
        if b & 0x80:
            tiles.append(b & 0x7F)
            continue
        if p >= len(data):
            break
        tile = data[p]
        p += 1
        if b == META_SEQ and tile == META_SEQ:
            continued_in = data[p] if p < len(data) else None
            break
        tiles.extend([tile] * (b + 1))

    columns = [tiles[i:i + height] for i in range(0, len(tiles), height)]
    if columns and len(columns[-1]) < height:
        columns.pop()
    return columns, continued_in


# --------------------------------------------------------------------------
# 3. NES CHR -> SNES 2bpp
# --------------------------------------------------------------------------

def nes_chr_to_snes_2bpp(chr_data: bytes) -> bytearray:
    """NES 2bpp (8 bytes plane0, then 8 bytes plane1) -> SNES 2bpp (row-interleaved).

    Both are 16 bytes/tile, so this is a pure permutation.
    """
    if len(chr_data) % 16:
        raise ValueError(f"CHR data not a multiple of 16 bytes: {len(chr_data)}")
    out = bytearray(len(chr_data))
    for base in range(0, len(chr_data), 16):
        for row in range(8):
            out[base + row * 2] = chr_data[base + row]
            out[base + row * 2 + 1] = chr_data[base + 8 + row]
    return out


def nes_chr_to_snes_4bpp(chr_data: bytes) -> bytearray:
    """NES 2bpp -> SNES 4bpp, for sprites.

    SNES OBJ is ALWAYS 4bpp; there is no 2bpp sprite mode. So unlike the
    background - where the conversion is a pure byte interleave - sprite tiles
    have to be widened: rows interleaved as usual for planes 0/1, then 16 bytes
    of zero for planes 2/3. Pixel values stay 0-3, which is what lets one
    4-colour NES sprite palette map onto the first four entries of an SNES OBJ
    palette.

    16 bytes/tile in, 32 out.
    """
    if len(chr_data) % 16:
        raise ValueError(f"CHR data not a multiple of 16 bytes: {len(chr_data)}")
    out = bytearray()
    for base in range(0, len(chr_data), 16):
        for row in range(8):
            out.append(chr_data[base + row])          # plane 0
            out.append(chr_data[base + 8 + row])      # plane 1
        out += bytes(16)                              # planes 2 and 3
    return out


def nes_chr_to_snes_4bpp_opaque(chr_data: bytes, blank_tile=None) -> bytearray:
    """NES BG 2bpp -> SNES BG 4bpp with NES colour 0 made opaque.

    NES background pixel 0 is the universal backdrop colour. SNES background
    pixel 0 is transparent, so widening the art unchanged lets a lower
    parallax layer leak through blocks and spikes. Values 1-3 retain their
    numbers and NES value 0 becomes SNES value 4 (plane 2 only). ``blank_tile``
    is left as all-zero SNES pixels for the intentional BG1 parallax hole.
    """
    if len(chr_data) % 16:
        raise ValueError(f"CHR data not a multiple of 16 bytes: {len(chr_data)}")
    out = bytearray()
    for tile, base in enumerate(range(0, len(chr_data), 16)):
        if tile == blank_tile:
            out += bytes(32)
            continue
        for row in range(8):
            out.append(chr_data[base + row])
            out.append(chr_data[base + 8 + row])
        for row in range(8):
            p0 = chr_data[base + row]
            p1 = chr_data[base + 8 + row]
            out.append((~(p0 | p1)) & 0xFF)
            out.append(0)
    return out


def snes_4bpp_to_nes_chr(snes: bytes) -> bytearray:
    """Recover the original NES planes from a widened SNES 4bpp stream."""
    if len(snes) % 32:
        raise ValueError(f"4bpp data not a multiple of 32 bytes: {len(snes)}")
    out = bytearray(len(snes) // 2)
    for src in range(0, len(snes), 32):
        dst = (src // 32) * 16
        for row in range(8):
            out[dst + row] = snes[src + row * 2]
            out[dst + 8 + row] = snes[src + row * 2 + 1]
    return out


def obj_pair_layout(tiles_4bpp: bytes) -> bytearray:
    """Reorder 8x8 OBJ tiles so an NES 8x16 sprite stands VERTICALLY.

    NOT USED - kept because it works and the reasoning behind retiring it is
    worth more than the code. See docs/M2_23_OBJ16.md: 16x16 OBJ mode reduces
    OAM ENTRIES, which is a PPU per-scanline resource, and barely touches CPU
    time, because the sprite walker's cost is per METASPRITE ENTRY - both halves
    of a merged pair still have to be read, positioned and culled. Measured, a
    perfect implementation saves about 3% of the walker while the re-layout
    itself costs more than that.

    The SNES has no 8x16 OBJ size, so each NES sprite is two 8x8 entries - and
    the SNES OBJ tile grid is 16 wide, where a 16x16 sprite takes N, N+1, N+16
    and N+17. For two adjacent NES 8x16 sprites to become ONE 16x16 OBJ, each
    sprite's two tiles have to be stacked and consecutive sprites side by side.

    Linear order gives the opposite: sprite k's halves land at N and N+1, side by
    side, so a 16x16 covering them would be 8 pixels of the wrong sprite.

    Sprite k (NES tiles 2k and 2k+1) therefore goes to

        top    N = 32 * (k >> 4) + (k & 15)
        bottom N + 16

    which fills the grid in row PAIRS: sixteen sprites across, then the next
    sixteen two rows down. Applied per 128-tile bank; the banks land at OBJ tile
    256 and 384, both multiples of 16, so the rule holds for the absolute tile
    numbers too.
    """
    n = len(tiles_4bpp) // 32
    if n % 32:
        raise ValueError(f"{n} tiles is not a whole number of 16-sprite rows")
    out = bytearray(len(tiles_4bpp))
    for k in range(n // 2):
        dst_top = 32 * (k >> 4) + (k & 15)
        for half in (0, 1):
            src = (2 * k + half) * 32
            dst = (dst_top + 16 * half) * 32
            out[dst:dst + 32] = tiles_4bpp[src:src + 32]
    return out


def snes_2bpp_to_nes_chr(snes: bytes) -> bytearray:
    """Inverse of the above - used to prove the conversion is lossless."""
    out = bytearray(len(snes))
    for base in range(0, len(snes), 16):
        for row in range(8):
            out[base + row] = snes[base + row * 2]
            out[base + 8 + row] = snes[base + row * 2 + 1]
    return out


def decode_snes_2bpp_tile(tile: bytes):
    """-> 8x8 list of rows of 2-bit pixel values."""
    rows = []
    for row in range(8):
        p0 = tile[row * 2]
        p1 = tile[row * 2 + 1]
        rows.append([((p0 >> (7 - x)) & 1) | (((p1 >> (7 - x)) & 1) << 1)
                     for x in range(8)])
    return rows


# --------------------------------------------------------------------------
# 4. NES palette -> SNES CGRAM (15-bit BGR)
# --------------------------------------------------------------------------

# 2C02 NES palette, 64 entries, RGB888.
NES_PALETTE_RGB = [
    (0x62, 0x62, 0x62), (0x00, 0x1F, 0xB2), (0x24, 0x04, 0xC8), (0x52, 0x00, 0xB2),
    (0x73, 0x00, 0x76), (0x80, 0x00, 0x24), (0x73, 0x0B, 0x00), (0x52, 0x28, 0x00),
    (0x24, 0x44, 0x00), (0x00, 0x57, 0x00), (0x00, 0x5C, 0x00), (0x00, 0x53, 0x24),
    (0x00, 0x3C, 0x76), (0x00, 0x00, 0x00), (0x00, 0x00, 0x00), (0x00, 0x00, 0x00),
    (0xAB, 0xAB, 0xAB), (0x0D, 0x57, 0xFF), (0x4B, 0x30, 0xFF), (0x8A, 0x13, 0xFF),
    (0xBC, 0x08, 0xD6), (0xD2, 0x12, 0x69), (0xC7, 0x2E, 0x00), (0x9D, 0x54, 0x00),
    (0x60, 0x7B, 0x00), (0x20, 0x98, 0x00), (0x00, 0xA3, 0x00), (0x00, 0x99, 0x42),
    (0x00, 0x7D, 0xB4), (0x00, 0x00, 0x00), (0x00, 0x00, 0x00), (0x00, 0x00, 0x00),
    (0xFF, 0xFF, 0xFF), (0x53, 0xAE, 0xFF), (0x90, 0x85, 0xFF), (0xD3, 0x65, 0xFF),
    (0xFF, 0x57, 0xFF), (0xFF, 0x5D, 0xCF), (0xFF, 0x77, 0x57), (0xFA, 0x9E, 0x00),
    (0xBD, 0xC7, 0x00), (0x7A, 0xE7, 0x00), (0x43, 0xF6, 0x11), (0x26, 0xEF, 0x7E),
    (0x2C, 0xD5, 0xF6), (0x4E, 0x4E, 0x4E), (0x00, 0x00, 0x00), (0x00, 0x00, 0x00),
    (0xFF, 0xFF, 0xFF), (0xB6, 0xE1, 0xFF), (0xCE, 0xD1, 0xFF), (0xE9, 0xC3, 0xFF),
    (0xFF, 0xBC, 0xFF), (0xFF, 0xBD, 0xF4), (0xFF, 0xC6, 0xC3), (0xFF, 0xD5, 0x9A),
    (0xE9, 0xE6, 0x81), (0xCE, 0xF4, 0x81), (0xB6, 0xFB, 0x9A), (0xA9, 0xFA, 0xC3),
    (0xA9, 0xF0, 0xF4), (0xB8, 0xB8, 0xB8), (0x00, 0x00, 0x00), (0x00, 0x00, 0x00),
]


def nes_color_to_cgram(nes_index: int) -> int:
    """NES palette index -> SNES CGRAM word (0bbbbbgg gggrrrrr)."""
    r, g, b = NES_PALETTE_RGB[nes_index & 0x3F]
    return (r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10)


def cgram_to_rgb(word: int):
    """CGRAM word -> RGB888, matching how the SNES actually displays it."""
    r = word & 0x1F
    g = (word >> 5) & 0x1F
    b = (word >> 10) & 0x1F
    return ((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2))


def build_cgram(nes_palette_16, bg_color=None, ground_color=None):
    """NES 16-byte BG palette -> 32-byte CGRAM block (8 palettes x 4 colors, Mode 0).

    The level header overrides the universal background colour and the ground
    palette's colour 0, matching what reset_level does on hardware.
    """
    pal = list(nes_palette_16)
    if bg_color is not None:
        for p in range(4):
            pal[p * 4] = bg_color
    if ground_color is not None:
        pal[1 * 4 + 0] = ground_color
    return [nes_color_to_cgram(c) for c in pal]


# --------------------------------------------------------------------------
# 5. metatiles -> SNES tilemap
# --------------------------------------------------------------------------

METATILE_RE = re.compile(
    r'^\s*Metatile\s+"([^"]+)"\s*,\s*(.+?)\s*$', re.IGNORECASE)


def _num(tok: str) -> int:
    """Parse ca65 ($xx, %bin) and C (0x..) integer literals."""
    tok = tok.strip()
    if tok.startswith('$'):
        return int(tok[1:], 16)
    if tok.startswith('%'):
        return int(tok[1:], 2)
    if tok.lower().startswith('0x'):
        return int(tok, 16)
    if tok.lower().startswith('0b'):
        return int(tok, 2)
    if re.fullmatch(r'\d+', tok):
        return int(tok)
    return 0            # symbolic PAL_n / COL_n handled by caller


def parse_metatiles(path: Path):
    """-> list of dicts: tl, tr, bl, br, pal, name."""
    out = []
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        m = METATILE_RE.match(line)
        if not m:
            continue
        name = m.group(1)
        fields = [f.strip() for f in m.group(2).split(',')]
        if len(fields) < 5:
            continue
        pal_tok = fields[4]
        pal = int(pal_tok[4:]) if pal_tok.startswith('PAL_') else _num(pal_tok)
        # Field 5 is the collision class (COL_*), resolved from METATILES/metatiles.h.
        coll_tok = fields[5].strip() if len(fields) > 5 else '0'
        out.append({
            'name': name,
            'tl': _num(fields[0]), 'tr': _num(fields[1]),
            'bl': _num(fields[2]), 'br': _num(fields[3]),
            'coll': coll_tok,
            'pal': pal & 7,
        })
    return out


def emit_metatiles_coll(metatiles, metatiles_h: Path) -> bytes:
    """Build the metatile -> collision-class table.

    `bg_collision_sub` indexes this with a metatile id to get the collision
    class, so it has to match the NES build exactly. COL_* names are resolved
    from METATILES/metatiles.h.
    """
    consts = {}
    for line in metatiles_h.read_text(encoding='utf-8', errors='replace').splitlines():
        m = re.match(r'\s*#define\s+(COL_\w+)\s+(\S+)', line)
        if m:
            consts[m.group(1)] = _num(m.group(2))

    out = bytearray()
    for mt in metatiles:
        tok = mt['coll']
        out.append(consts.get(tok, _num(tok)) & 0xFF)
    return bytes(out)


def emit_collision_map(columns, col_start=0, pages=4, row_start=0):
    """Build the collision map bg_collision_sub() reads.

    Layout is dictated by the NES original: `pages` pages of 256 bytes, each
    one 240px-tall "room" of 16x15 metatiles.
        index = (x >> 4) | (y & 0xF0)   -> (col & 15) | (row_in_room << 4)
        page  = room & 3
    Entries are metatile ids; bg_collision_sub maps them through
    metatiles_coll to a collision class.
    """
    ROWS_PER_ROOM = 15
    out = bytearray(pages * 256)
    height = len(columns[0]) if columns else 0

    for page in range(pages):
        for row in range(ROWS_PER_ROOM):
            world_row = row_start + page * ROWS_PER_ROOM + row
            if world_row >= height:
                continue
            for x in range(16):
                c = col_start + x
                if c >= len(columns):
                    continue
                out[page * 256 + ((row << 4) | x)] = columns[c][world_row] & 0xFF
    return bytes(out)


GROUND_ROWS = 3          # metatile rows of ground, appended below the level
GROUND_COLS = 16         # the ground pattern repeats every 16 metatile columns


def parse_ground_rle(root, name="ground0", lvlset="lvlset_A"):
    """Decode a ground strip from grounddata.h -> GROUND_ROWS x GROUND_COLS ids.

    Same RLE as _load_ground in nesdash.s:
        b & 0x80  -> one metatile, (b & 0x7F)
        otherwise -> b is a run count, the next byte repeats b+1 times
    Exactly 48 bytes are produced; the original relies on that rather than
    checking bounds, and so does this.
    """
    import re
    path = root / "LEVELS/include" / lvlset / "grounddata.h"
    text = path.read_text(errors="replace")
    m = re.search(r"^const unsigned char %s\[\]\s*=\s*\{(.*?)\};" % re.escape(name),
                  text, re.S | re.M)
    if not m:
        raise SystemExit(f"grounddata.h: no array {name}")
    data = [int(v, 0) for v in re.findall(r"0x[0-9A-Fa-f]+", m.group(1))]

    out, i = [], 0
    while len(out) < GROUND_ROWS * GROUND_COLS:
        b = data[i]; i += 1
        if b & 0x80:
            out.append(b & 0x7F)
        else:
            value = data[i]; i += 1
            out.extend([value] * (b + 1))
    return out[:GROUND_ROWS * GROUND_COLS]


def append_ground(columns, ground):
    """Extend every metatile column with the ground rows below the level.

    The ground is NOT in the level data - it is a separate strip - so the
    rendered columns have to have it composited in, exactly as the collision
    map does at run time. The pattern repeats every GROUND_COLS columns.
    """
    return [list(col) + [ground[r * GROUND_COLS + (c % GROUND_COLS)]
                         for r in range(GROUND_ROWS)]
            for c, col in enumerate(columns)]


def emit_collision_columns(columns, pages=4, rows_per_room=15, ground_rows=3):
    """Per-metatile-column slices of the collision map, for streaming.

    emit_collision_map() bakes a fixed 16-column window; this emits every column
    so the runtime can refill the window as the camera moves. One record is
    `rows` metatile ids, top to bottom, for the same world rows the static
    window uses.

    bg_collision_sub() indexes collMap[room & 3][(x >> 4) | (y & 0xF0)], and
    temp_x is a byte, so `x >> 4` is the metatile column modulo 16: the window is
    16 metatile columns = 256 pixels = exactly one screen, and column c always
    lands in slot c & 15.
    """
    out = bytearray()
    height = len(columns[0]) if columns else 0
    total = pages * rows_per_room
    # The level is BOTTOM-ALIGNED in the window, with the last `ground_rows`
    # reserved for the ground strip, which is not in the level data at all.
    # writeToCollisionMap in nesdash.s does the same: for a 27-row level the
    # rows land at buffer rows 30..56 and the ground fills 57..59, so the level
    # occupies collision pages 2 and 3 - not 0 and 1.
    top = total - ground_rows - height
    for col in columns:
        for row in range(total):
            src = row - top
            out.append(col[src] & 0xFF if 0 <= src < height else 0)
    return bytes(out)


def tilemap_word(tile: int, palette: int, priority=0, hflip=0, vflip=0) -> int:
    """SNES tilemap entry:  vhopppcc cccccccc"""
    return ((tile & 0x3FF)
            | ((palette & 7) << 10)
            | ((priority & 1) << 13)
            | ((hflip & 1) << 14)
            | ((vflip & 1) << 15))


def build_tilemap(columns, metatiles):
    """Metatile columns -> SNES tilemap words.

    Returns a 2D list [tile_row][tile_col].  Each metatile is 2x2 tiles, and
    the palette comes from the metatile's own attribute byte - which is what
    makes this correct despite 47 of 235 tiles being reused across palettes.
    """
    if not columns:
        return []
    height_mt = len(columns[0])
    rows = height_mt * 2
    cols = len(columns) * 2
    grid = [[0] * cols for _ in range(rows)]

    for cx, column in enumerate(columns):
        for cy, mt_index in enumerate(column):
            mt = metatiles[mt_index] if mt_index < len(metatiles) else metatiles[0]
            pal = mt['pal']
            x, y = cx * 2, cy * 2
            grid[y][x] = tilemap_word(mt['tl'], pal)
            grid[y][x + 1] = tilemap_word(mt['tr'], pal)
            grid[y + 1][x] = tilemap_word(mt['bl'], pal)
            grid[y + 1][x + 1] = tilemap_word(mt['br'], pal)
    return grid


# --------------------------------------------------------------------------
# 6. software SNES PPU (Mode 0, 2bpp, single BG)
# --------------------------------------------------------------------------

def render_bg(grid, tile_data: bytes, cgram, scroll_x=0, scroll_y=0,
              width=None, height=None, wrap=False):
    """Render a BG layer exactly as SNES Mode 0 would, from real tilemap words.

    tile_data is SNES-format 2bpp.  cgram is a list of 15-bit words.  Colour 0
    of every palette is transparent and shows the backdrop (CGRAM 0).

    `wrap` makes the map repeat, which is what the hardware actually does - a
    scrolling level relies on it, and without it anything past the edge of the
    grid comes out as backdrop. It defaults off because the static-ROM
    comparison (tools/compare_rom.py) is pixel-exact against the clipping
    behaviour at scroll_y = -1, and that check is a fixed point worth keeping.
    """
    rows, cols = len(grid), len(grid[0]) if grid else 0
    width = width if width is not None else cols * 8
    height = height if height is not None else rows * 8

    img = Image.new('RGB', (width, height), cgram_to_rgb(cgram[0]))
    px = img.load()

    tile_cache = {}

    for sy in range(height):
        ty = ((sy + scroll_y) // 8)
        if wrap:
            ty %= rows
        elif not (0 <= ty < rows):
            continue
        fy = (sy + scroll_y) % 8
        row = grid[ty]
        for sx in range(width):
            tx = ((sx + scroll_x) // 8)
            if wrap:
                tx %= cols
            elif not (0 <= tx < cols):
                continue
            word = row[tx]
            tile_idx = word & 0x3FF
            pal = (word >> 10) & 7
            hflip = (word >> 14) & 1
            vflip = (word >> 15) & 1

            if tile_idx not in tile_cache:
                off = tile_idx * 16
                chunk = tile_data[off:off + 16]
                if len(chunk) < 16:
                    chunk = chunk + bytes(16 - len(chunk))
                tile_cache[tile_idx] = decode_snes_2bpp_tile(chunk)
            tile = tile_cache[tile_idx]

            fx = (sx + scroll_x) % 8
            val = tile[7 - fy if vflip else fy][7 - fx if hflip else fx]
            if val == 0:
                continue                       # transparent -> backdrop
            px[sx, sy] = cgram_to_rgb(cgram[pal * 4 + val])

    return img


# --------------------------------------------------------------------------
# driver
# --------------------------------------------------------------------------

# From SAUCE/defines/space_defines.h - 1KB CHR bank numbers.
CHR_BANKS = {
    'SPIKESA': 0, 'SPIKESB': 2, 'SPIKESC': 4,
    'BLOCKSA': 6, 'BLOCKSB': 8, 'BLOCKSC': 10, 'BLOCKSD': 12,
    'SAWBLADESA': 14, 'SLOPESA': 16,
}
CHR_FILES = {
    0: 'SpikesA.chr', 2: 'SpikesB.chr', 4: 'SpikesC.chr',
    6: 'BlocksA.chr', 8: 'BlocksB.chr', 10: 'BlocksC.chr', 12: 'BlocksD.chr',
    14: 'SawbladesA.chr', 16: 'slopesA.chr',
}

# SAUCE/defines/palette/palettes_PRG.c :: paletteDefault
PALETTE_DEFAULT = [
    0x11, 0x01, 0x0F, 0x30,     # 0 level tiles
    0x00, 0x01, 0x11, 0x30,     # 1 ground
    0x00, 0x01, 0x0F, 0x2A,     # 2 decorations
    0x11, 0x01, 0x0F, 0x0F,     # 3 text
]


def load_bg_pattern_table(root: Path, spike_set: int, block_set: int,
                          bank2_file: str, saw_set: int) -> bytearray:
    """Assemble the 4KB BG pattern table from four 1KB CHR banks.

    Mirrors _set_tile_banks in LIB/asm/neslib.s:
        bank0 tiles $00-$3F = spike set
        bank1 tiles $40-$7F = block set
        bank2 tiles $80-$BF = parallax (or slopes when parallax is disabled)
        bank3 tiles $C0-$FF = saw set
    """
    tiles_dir = root / 'GRAPHICS' / 'Level Tiles'

    def bank1k(bank_no: int) -> bytes:
        fname = CHR_FILES[bank_no & ~1]
        data = (tiles_dir / fname).read_bytes()
        half = (bank_no & 1) * 1024
        return data[half:half + 1024]

    out = bytearray()
    out += bank1k(spike_set)
    out += bank1k(block_set)
    if bank2_file:
        out += (root / bank2_file).read_bytes()[:1024]
    else:
        out += bank1k(CHR_BANKS['SLOPESA'])
    out += bank1k(saw_set)
    return out


def emit_snes_bg1_tilemap(grid, col_start_tiles=0, row_start=None,
                          width=32, height=32):
    """Crop the tile grid to a real SNES BG1 tilemap screen (32x32 entries, 2KB).

    Entries are row-major little-endian words; anything outside the level
    becomes 0 (metatile 0 / EMPTY).
    """
    rows = len(grid)
    cols = len(grid[0]) if grid else 0
    if row_start is None:                       # bottom-align on the playfield
        row_start = max(0, rows - height)

    out = bytearray()
    for y in range(height):
        gy = row_start + y
        for x in range(width):
            gx = col_start_tiles + x
            inside = 0 <= gy < rows and 0 <= gx < cols
            word = grid[gy][gx] if inside else 0
            out += word.to_bytes(2, 'little')
    return out, row_start


STREAM_ROWS = 64         # one column record; 64x64 BG1 map


def emit_column_stream(grid, row_start, rows=STREAM_ROWS, cols_per_bank=256):
    """Emit every tile column of the level as fixed-size, bank-aligned records.

    One record is `rows` tilemap words (64 bytes at rows=32), which is exactly
    one VRAM column write: set VMAIN to +32 words and a single DMA fills it.

    Records are padded out to whole 32KB LoROM banks so a column never straddles
    a bank boundary - SNES DMA increments the A-bus address within a bank and
    does not carry into the bank byte.

    Returns (blob, n_columns, n_banks).
    """
    total_rows = len(grid)
    total_cols = len(grid[0]) if grid else 0
    rec = rows * 2
    bank_bytes = cols_per_bank * rec

    blob = bytearray()
    for c in range(total_cols):
        for y in range(rows):
            gy = row_start + y
            word = grid[gy][c] if 0 <= gy < total_rows else 0
            blob += word.to_bytes(2, 'little')

    n_banks = (len(blob) + bank_bytes - 1) // bank_bytes
    blob += bytes(n_banks * bank_bytes - len(blob))
    return blob, total_cols, n_banks


def verify_chr_banks_against_rom(root: Path, rom_name: str) -> bool:
    """Prove the bank-number -> 1KB-ROM-offset assumption against a built ROM.

    space_defines.h gives CHR bank numbers in 1KB units; this confirms bank N
    really is CHR ROM offset N*1024, which is what load_bg_pattern_table relies on.
    """
    rom_path = root / rom_name
    if not rom_path.exists():
        print(f"    (no {rom_name}, skipping ROM cross-check)")
        return True

    rom = rom_path.read_bytes()
    h = rom[:16]
    prg, chrn = h[4], h[5]
    if (h[7] >> 2) & 3 == 2:                      # NES 2.0
        prg |= (h[9] & 0x0F) << 8
        chrn |= (h[9] >> 4) << 8
    chr_base = 16 + prg * 16384

    def bank(n: int) -> bytes:
        return rom[chr_base + n * 1024: chr_base + (n + 1) * 1024]

    tiles_dir = root / 'GRAPHICS' / 'Level Tiles'
    ok = True
    stale = []
    for bank_no, fname in sorted(CHR_FILES.items()):
        src = (tiles_dir / fname).read_bytes()
        for half in range(len(src) // 1024):
            if bank(bank_no + half) != src[half * 1024:(half + 1) * 1024]:
                # The .chr files are the source of truth; a mismatch means the
                # reference ROM predates an art change, not that the bank
                # numbering is wrong.
                newer = (tiles_dir / fname).stat().st_mtime > rom_path.stat().st_mtime
                stale.append(f"{fname} half {half}"
                             + (" (art newer than ROM)" if newer else ""))
                ok = ok and newer

    par = (root / 'GRAPHICS' / 'parallax.chr').read_bytes()
    n_par = len(par) // 1024
    par_base = 0x1C000 // 1024                    # GAMECHR size, from the .cfg
    par_ok = all(bank(par_base + i) == par[i * 1024:(i + 1) * 1024]
                 for i in range(n_par))
    distinct = len({par[i * 1024:(i + 1) * 1024] for i in range(n_par)})
    n_ok = len(CHR_FILES) - len({s.split(' half')[0] for s in stale})
    print(f"    CHR bank mapping vs {rom_name}: {'PASS' if ok else 'FAIL'} "
          f"({n_ok}/{len(CHR_FILES)} tilesets match)")
    for s in stale:
        print(f"      stale in reference ROM: {s}")
    print(f"    parallax: {n_par} banks ({len(par) // 1024}KB), {distinct} distinct, "
          f"ROM match: {'PASS' if par_ok else 'FAIL'}")
    return ok and par_ok


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=r'C:\famidash')
    ap.add_argument('--level', default='stereomadness')
    ap.add_argument('--lvlset', default='lvlset_A')
    ap.add_argument('--height', type=int, default=27)
    ap.add_argument('--spikes', default='SPIKESA')
    ap.add_argument('--blocks', default='BLOCKSA')
    ap.add_argument('--bg-color', type=lambda s: int(s, 0), default=0x12)
    ap.add_argument('--ground-color', type=lambda s: int(s, 0), default=0x02)
    ap.add_argument('--columns', type=int, default=64)
    ap.add_argument('--col-start', type=int, default=0)
    ap.add_argument('--row-start', type=int, default=None,
                    help='top tile row of the 32x32 BG1 screen (default: '
                         'bottom-aligned on the playfield)')
    ap.add_argument('--scale', type=int, default=1)
    ap.add_argument('--rom', default='Famidash - Huge Man.nes',
                    help='built NES ROM used to cross-check CHR bank mapping')
    ap.add_argument('--outdir', default='.')
    args = ap.parse_args()

    root = Path(args.root)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    print(f"=== Famidash SNES M0 :: {args.level} ===\n")

    # -- stage 1: LZ ------------------------------------------------------
    lz_path = (root / 'LEVELS' / 'include' / args.lvlset / 'EXPORTS' / 'level'
               / f'{args.level}.lz.bin')
    if not lz_path.exists():
        cands = sorted((lz_path.parent).glob(f'{args.level}.lz*.bin'))
        if not cands:
            print(f"!! no level data found for {args.level} in {lz_path.parent}")
            return 1
        lz_path = cands[0]
    lz_data = lz_path.read_bytes()
    rle_data = lz_decompress(lz_data)
    print(f"[1] LZ      {lz_path.name}: {len(lz_data)} -> {len(rle_data)} bytes "
          f"({100 - len(lz_data) / len(rle_data) * 100:.1f}% saved)")

    # validate against the project's own compressor
    sys.path.insert(0, str(root / 'LEVELS'))
    try:
        import aart_lz
        recompressed = aart_lz.compress(bytearray(rle_data))
        ok = bytes(recompressed) == lz_data
        print(f"    round-trip vs aart_lz.compress(): "
              f"{'PASS' if ok else 'FAIL'} "
              f"({len(recompressed)} vs {len(lz_data)} bytes)")
        if not ok:
            return 1
    except ImportError:
        print("    (aart_lz not importable, skipping round-trip check)")

    # -- stage 2: RLE -----------------------------------------------------
    columns, continued = rle_decode(rle_data, args.height)
    print(f"[2] RLE     {len(columns)} columns x {args.height} metatiles"
          + (f", continues in chunk {continued}" if continued is not None else ""))

    # -- stage 3: CHR -----------------------------------------------------
    nes_chr = load_bg_pattern_table(
        root,
        CHR_BANKS[args.spikes], CHR_BANKS[args.blocks],
        'GRAPHICS/parallax.chr', CHR_BANKS['SAWBLADESA'])
    snes_chr = nes_chr_to_snes_2bpp(nes_chr)
    lossless = snes_2bpp_to_nes_chr(snes_chr) == nes_chr
    print(f"[3] CHR     {len(nes_chr)} bytes -> SNES 2bpp, "
          f"{len(nes_chr) // 16} tiles; "
          f"round-trip: {'PASS' if lossless else 'FAIL'}")
    if not lossless:
        return 1
    if not verify_chr_banks_against_rom(root, args.rom):
        return 1

    # -- stage 4: palette -------------------------------------------------
    cgram = build_cgram(PALETTE_DEFAULT, args.bg_color, args.ground_color)
    print(f"[4] CGRAM   16 NES colours -> 15-bit BGR; "
          f"backdrop ${args.bg_color:02X} -> {cgram_to_rgb(cgram[0])}")

    # -- stage 5: tilemap -------------------------------------------------
    metatiles = parse_metatiles(root / 'METATILES' / 'metatiles.inc')
    view = columns[args.col_start:args.col_start + args.columns]
    grid = build_tilemap(view, metatiles)
    used_pals = sorted({(w >> 10) & 7 for row in grid for w in row})
    print(f"[5] tilemap {len(metatiles)} metatiles parsed; "
          f"{len(grid[0])}x{len(grid)} tiles; palettes used: {used_pals}")

    tilemap_bin = bytearray()
    for row in grid:
        for w in row:
            tilemap_bin += w.to_bytes(2, 'little')

    # -- stage 6: render --------------------------------------------------
    def save(img, suffix):
        if args.scale > 1:
            img = img.resize((img.width * args.scale, img.height * args.scale),
                             Image.NEAREST)
        path = outdir / f'{args.level}{suffix}.png'
        img.save(path)
        return path, img

    overview_path, overview = save(
        render_bg(grid, snes_chr, cgram), '_overview')

    # A real 256x224 SNES screen, framed on the playfield at the level's foot.
    screen_h = args.height * 16
    screen_path, screen = save(
        render_bg(grid, snes_chr, cgram,
                  scroll_x=0, scroll_y=max(0, screen_h - 224),
                  width=256, height=224), '_screen')

    print(f"[6] render  {overview_path.name} ({overview.width}x{overview.height})")
    print(f"            {screen_path.name} ({screen.width}x{screen.height})")

    # -- emit SNES-ready binaries ----------------------------------------
    (outdir / f'{args.level}.vram.bin').write_bytes(snes_chr)
    (outdir / f'{args.level}.tilemap.bin').write_bytes(tilemap_bin)
    cg = bytearray()
    for w in cgram:
        cg += w.to_bytes(2, 'little')
    (outdir / f'{args.level}.cgram.bin').write_bytes(cg)
    print(f"\n    wrote {args.level}.vram.bin ({len(snes_chr)}B), "
          f"{args.level}.tilemap.bin ({len(tilemap_bin)}B), "
          f"{args.level}.cgram.bin ({len(cg)}B)")

    # Fixed-layout binaries for the ROM build: exactly one 32x32 BG1 screen.
    bg1, row_start = emit_snes_bg1_tilemap(grid, row_start=args.row_start)
    (outdir / 'bg1.tilemap.bin').write_bytes(bg1)
    (outdir / 'bg1.tiles.bin').write_bytes(snes_chr)
    (outdir / 'bg1.cgram.bin').write_bytes(cg)
    print(f"    ROM build set: bg1.tilemap.bin ({len(bg1)}B, 32x32 @ tile row "
          f"{row_start}), bg1.tiles.bin ({len(snes_chr)}B), "
          f"bg1.cgram.bin ({len(cg)}B)")

    # Two column streams, because there are two consumers with different maps:
    #
    #   level.cols.*    32 rows, 64x32 map - the assembly scroll ROM
    #                   (src/scroll.s), a verified baseline that verify_scroll.py
    #                   checks. Level data only, no ground.
    #   level.cols64.*  64 rows, 64x64 map - the C game ROM, with the ground
    #                   composited in.
    #
    # Only one ends up in any given ROM, so the duplication costs nothing but
    # build time, and it keeps the baseline from silently rotting when the game
    # ROM's format moves.
    plain_grid = build_tilemap(columns, metatiles)
    s32, n32, b32 = emit_column_stream(plain_grid, row_start, rows=32,
                                       cols_per_bank=512)
    bb32 = len(s32) // b32
    for i in range(b32):
        (outdir / f'level.cols.{i}.bin').write_bytes(s32[i * bb32:(i + 1) * bb32])
    (outdir / 'level.columns.meta').write_text(
        f"columns {n32}\nbanks {b32}\nbank_bytes {bb32}\nrow_start {row_start}\n")

    # The ground is composited into the 64-row stream: it is not in the level
    # data, so without this the floor has collision (load_ground fills that at
    # run time) but no tiles - solid and invisible.
    ground = parse_ground_rle(root)
    full_grid = build_tilemap(append_ground(columns, ground), metatiles)
    # 64 tile rows, bottom-aligned: a 64x64 BG1 map is 512px tall, which covers
    # any level up to 29 metatile rows (29 + 3 ground = 32 -> 512px). Taller
    # levels need vertical row streaming and will show only their bottom 64 rows
    # until that exists - see docs/M2_LEVEL_RENDER.md.
    stream_row_start = max(0, len(full_grid) - STREAM_ROWS)
    stream, n_cols, n_banks = emit_column_stream(full_grid, stream_row_start,
                                                 rows=STREAM_ROWS)
    bank_bytes = len(stream) // n_banks
    for i in range(n_banks):
        (outdir / f'level.cols64.{i}.bin').write_bytes(
            stream[i * bank_bytes:(i + 1) * bank_bytes])
    (outdir / 'level.columns64.meta').write_text(
        f"columns {n_cols}\nbanks {n_banks}\nbank_bytes {bank_bytes}\n"
        f"row_start {stream_row_start}\nstream_rows {STREAM_ROWS}\n"
        f"level_height {args.height}\n")
    # Start the map at the playfield so the floor lands in page 0.
    cmap = emit_collision_map(columns, args.col_start, row_start=args.height - 15)
    (outdir / 'level_collmap.bin').write_bytes(cmap)
    print(f"    level_collmap.bin ({len(cmap)}B, 4 rooms x 16x15 metatiles "
          f"from column {args.col_start})")

    # The same data per column, so draw_screen can refill the window as it goes.
    ccols = emit_collision_columns(columns)
    (outdir / 'level_collcols.bin').write_bytes(ccols)
    print(f"    level_collcols.bin ({len(ccols)}B, {len(columns)} columns "
          f"x 60 metatiles = 4 rooms)")

    # Sprite tiles: the WHOLE of NES pattern table 1.
    #
    # Every sprite tile byte in SAUCE/defines/sprites.h is odd, i.e. bit 0 set,
    # i.e. pattern table 1 - $1000-$1FFF. MMC3 is in CHR mode B (crt0.s sets
    # MMC3_REG_SEL_CHR_MODE_B), so A12 is inverted and that 4KB is the two 2KB
    # registers: 2KB bank 0 at $1000 and 2KB bank 1 at $1800. In crt0.s's
    # GAMECHR those pair up as four 1KB files:
    #
    #   $1000 bankicon00.chr    the player icon      -> OBJ tiles 256-319
    #   $1400 bankportals.chr   portals              -> OBJ tiles 320-383
    #   $1800 bankmain.chr      orbs, pads, coins    -> OBJ tiles 384-447
    #   $1C00 bankblank.chr     decorations          -> OBJ tiles 448-511
    #
    # Uploading only the icon bank is why every level object drew garbage: its
    # tile number named VRAM that had never been written. The game bank-switches
    # the icon and the deco half per frame; this takes one static set, which is
    # the level-1 configuration.
    SPRITE_BANKS = [
        ('GRAPHICS/Icons/bankicon00.chr',          'icon'),
        ('GRAPHICS/Level Sprites/bankportals.chr', 'portals'),
        ('GRAPHICS/Level Sprites/bankmain.chr',    'main'),
        ('GRAPHICS/Level Sprites/bankblank.chr',   'deco'),
    ]
    spr = bytearray()
    for rel, what in SPRITE_BANKS:
        data = (root / rel).read_bytes()
        if len(data) != 1024:
            raise SystemExit(f"{rel}: expected a 1KB CHR bank, got {len(data)}")
        spr += nes_chr_to_snes_4bpp(data)
    (outdir / 'spr.tiles.bin').write_bytes(spr)
    print(f"    spr.tiles.bin ({len(spr)}B, {len(spr) // 32} tiles, "
          f"NES pattern table 1: {', '.join(w for _, w in SPRITE_BANKS)})")

    coll = emit_metatiles_coll(metatiles, root / 'METATILES' / 'metatiles.h')
    (outdir / 'metatiles_coll.bin').write_bytes(coll)
    print(f"    metatiles_coll.bin ({len(coll)} entries, "
          f"{len(set(coll))} distinct collision classes)")

    (outdir / 'level_info.inc').write_text(
        "; generated by tools/snes_m0.py - do not edit\n"
        f"LEVEL_COLS   = {n_cols}\n"
        f"COL_BANKS    = {n_banks}\n"
        f"COLS_PER_BANK = {bank_bytes // (32 * 2)}\n"
        f"TILE_ROWS    = 32\n")
    print(f"    column stream: level.cols64.0..{n_banks - 1}.bin "
          f"({len(stream):,}B total) - {n_cols} tile columns, "
          f"{n_banks} x {bank_bytes // 1024}KB banks")
    return 0


if __name__ == '__main__':
    sys.exit(main())
