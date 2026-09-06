# M0 results — asset pipeline

**Status: complete and validated.**

M0's goal was to prove the asset pipeline — that NES level data, tiles and palettes can be
converted to SNES-native form correctly — *before* committing to a 65816 toolchain. It does
not produce a ROM.

Everything here is reproduced by `tools/snes_m0.py`.

## What it does

```
stereomadness.lz.bin
  ├─ 1. aart_lz decompress          -> RLE stream
  ├─ 2. vertical RLE decode         -> metatile columns (column-major)
  ├─ 3. NES CHR -> SNES 2bpp        -> .vram.bin
  ├─ 4. NES palette -> CGRAM 15-bit -> .cgram.bin
  ├─ 5. metatiles -> tilemap words  -> .tilemap.bin
  └─ 6. software SNES PPU (Mode 0)  -> .png
```

Stage 6 is a software SNES PPU. It reads back the *converted* binaries — real 16-bit
tilemap words, real 2bpp SNES tile data, real 15-bit CGRAM — so the PNG is evidence about
the converted data, not about the NES originals.

## Verification

| Check | Result |
|---|---|
| LZ decoder vs the game's own `aart_lz.compress()` | **454 / 454 level files byte-exact** |
| — files using the `0x7F` bank-continuation escape | 64, all pass |
| NES CHR → SNES 2bpp → NES CHR | lossless |
| CHR bank number → ROM offset, vs `Famidash - Huge Man.nes` | **PASS**, all 9 tilesets |
| Parallax CHR layout vs ROM | **PASS**, 144 banks, all distinct |
| Rendered colours vs CGRAM contents | exactly the 5 entries in use, 0 spurious |

Total level data exercised: **4,343,808 bytes** decoded from 2,599,775 compressed.

The ROM cross-check is built into the tool (`--rom`), so it stays reproducible as the game
repo changes rather than being a one-off.

## Findings that changed the plan

**1. The tile→palette lookup shortcut is dead.** The scope doc's first instinct was a global
`tile index → palette` table, which would have left all 210 `one_vram_buffer` call sites
untouched. Measured against `METATILES/metatiles.inc`: **47 of 235 background tiles (20%) are
used under more than one palette.** `BLOCK` and `FAKE_BLOCK` are both `$20,$21,$30,$31` at
PAL_0 vs PAL_1; tile `$00` appears under three palettes.

The working approach — driving palette from `metatiles_attr`, which `metatiles.s` already
exports per metatile — is implemented in `build_tilemap()` and **confirmed correct**: the
render is right with no tile duplication and no art changes.

**2. The pre-shifted-CHR tax is bigger than the parallax alone.** Verified against the ROM:
144 distinct 1KB parallax banks (144KB), *plus* every tileset in `GRAPHICS/Level Tiles/`
being 2KB holding two 1-pixel-offset phases of the same art. Tile `$00` is a `10101010`
dither — the sky texture — and the second phase shifts it one pixel. `_set_tile_banks`
selects with `parallax_scroll_x & 1`.

Both collapse to a hardware scroll register on SNES.

**3. Bank 2 is contended.** `neslib.s` gives tiles `$80-$BF` to *either* parallax *or*
slopes depending on `no_parallax`, so a level currently can't have both. On SNES it can.

## Known gap

**The ground is not drawn.** It's a separate stream (`load_ground`, `grounddata.h`,
`groundlist.h`), not part of the level metatile data — which is why palette 1 (ground) is
unused in the render. This belongs with M1's renderer, not the asset pipeline.

## Usage

```bash
python tools/snes_m0.py --root C:\famidash --level stereomadness
python tools/snes_m0.py --root C:\famidash --level stereomadness \
    --col-start 140 --columns 16 --scale 3
```

Options: `--lvlset`, `--height`, `--spikes`, `--blocks`, `--bg-color`, `--ground-color`,
`--col-start`, `--columns`, `--scale`, `--rom`, `--outdir`.

Requires Pillow. Reads the game repo read-only.

## Next: M1

M1 is the real go/no-go gate — shim core (palette, vram buffer, OAM, scroll, input), cube
mode, one level, playable, silent. First blocker is a 65816 toolchain: `BIN/ca65.exe` in the
game repo *can* assemble 65816 via `--cpu 65816`, but there is no SNES linker config and no C
compiler. See §2 of the scope doc — recommendation is Calypsi.
