# M2.14 — the cube's spin rate, and switchable sprite CHR

Two things that were both "the port reads a field the NES reads and does
something else with it".

| | before | after |
|---|---|---|
| cube revolution | 24 frames | **57.7** (physics table says 57.4) |
| gamemodes drawing their own ART | 5 of 12 | **12 of 12** |
| decoration animation | never moved | switches every frame |
| speed | 98.9% of 60Hz | **99.1%** |

```bash
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_cube_spin.lua
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_sprite_chr.lua
python tools/verify_rom_layout.py
```

---

## 1. `cube_rotate` is fixed point, and the low byte is the fraction

The airborne cube advanced one of its 24 drawn steps **every frame**. It should
advance one every ~2.4.

`cube_rotate` is 16-bit: the high byte is the step actually drawn, and the low
byte is a fraction. Each airborne frame `nesdash.s` adds `CUBE_GRAVITY` to the
LOW byte and lets the carry move the step:

```
LDA _cube_rotate            ; the fraction
CLC
ADC _CUBE_GRAVITY_lo,Y      ; Y = framerate * 4
STA _cube_rotate
BCC @fin                    ; no carry -> the drawn step does not move
    LDX _cube_rotate+1
    INX
    CPX #24 / BCC :+ / LDX #00      ; wrap
```

At `framerate = 1` the step is `CUBE_GRAVITY_lo[4]` = 107, so a drawn step every
256/107 = 2.39 frames and a full turn in 57.4 — about a second, which is what
Geometry Dash looks like. Stepping the high byte directly is a turn every 24
frames.

`verify_cube_spin.lua` measures it over real jumps rather than asserting the
table: 106.5 units per airborne frame against the 107 the table gives, 57.7
frames per turn against 57.4.

Two smaller faults in the same routine, both found by reading the original
beside the port:

- **The grounded snap indexed the rounding table with a clamp.** The original
  writes the 6-entry pattern out twice so it can index `step` directly for
  0..11 and `step - 12` for 12..23; clamping at 12 instead sticks the whole top
  half of the wheel on one entry.
- **A cube on a slope is drawn turned further** (`rounding_slope_table`, indexed
  by `slope_type`), and that adjustment applies to the DRAWN index only — the
  original stores the rounded rotation first and adds afterwards, so it cannot
  accumulate. That was missing entirely.

The icon also picks between three flip patterns (`drawcube_sprite_table`,
`_way`, `_none`); ported, and the three are one 72-entry array because the slope
adjustment can push the index past 23 and the original lets it read on into the
next table — the same NES-layout dependency as the robot's jump frames.

## 2. A mapper CHR bank switch is a DMA

`mmc3_set_2kb_chr_bank_0/1` were no-ops. They are the two registers that cover
NES pattern table 1 — where **every sprite in the game lives** — so:

- `set_player_banks()` asked for the ball's, robot's, spider's, wave's, swing's,
  snake's and pogo's art and got whatever was uploaded at boot. Those seven
  gamemodes drew the right tile *numbers* against the wrong *art*.
- the decoration bank alternates every frame (`current_deco_type` and `+2`);
  only their 1600-byte differing tile region is transferred
  and never moved.

MMC3 is in CHR mode B, so A12 is inverted and the two 2KB registers map to:

```
2KB bank 0 -> NES $1000-$17FF -> OBJ tiles 256-383   icon / gamemode art
2KB bank 1 -> NES $1800-$1FFF -> OBJ tiles 384-511   main sprites + decorations
```

`tools/gen_sprchr.py` reproduces `crt0.s`'s GAMECHR layout, extracts the 2KB
banks gameplay can reach, and widens each to 4bpp — 4KB per bank, 14 banks,
56KB. Emitted as `.incbin`s rather than C arrays for the same reason the column
stream is: 56KB of initialisers is slow to compile and produces the same bytes.
Cross-checked on generation: banks 40 and 28 reproduce the old static upload
byte for byte.

### It has to be chunked

4KB of DMA is about 24 scanlines. Vblank is 37 and the column, OAM and palette
transfers already want twenty of them, so sending a bank whole would overrun
into active display where VRAM writes are silently dropped — and the tail of the
bank would simply be missing. So there is a queue with a 2KB-per-vblank budget
and a switch lands over two frames. The game switches the decoration bank every
16 frames; arriving a frame late is not visible.

That makes "VRAM disagrees with the selected bank" a legitimate transient, which
is why `shim_chr_pending` exists and `verify_sprite_chr.lua` waits for the queue
to drain before comparing. Reporting a half-arrived upload as corruption is the
same mistake as counting the write-ahead column.

### The level header field that fed it was never parsed

`current_deco_type` comes from the header byte written as `(1 << 7) | _DECO1`,
and `gen_assets.py` gave up on any expression it could not evaluate — so it was
0, and the game asked for CHR bank 0, which is a background tileset. The parser
now resolves `_NAME` against `space_defines.h` (`DECO1` is 28). Same fix gets
`current_spike_set` and `current_block_set` out of `(_SPIKESA << 4) | _BLOCKSA`.

**Zero is not a neutral default for a level-header field** any more than it is
for a game option. This is the third time that has bitten: `spawn_y_pos`,
`viseffects`, now the deco bank.

### ROM layout, and a guard for it

The banks live at `$C3`, one bank of their own, because DMA increments the A-bus
address within a bank and does not carry into the bank byte — a 4KB block that
straddled a ROM bank would wrap to the start of its own bank part way through
the transfer. 4KB divides 64KB, so laying them end to end from `$C30000` makes
that impossible.

Adding them also **changed which memories the linker emits separately**: bank
`$C3` bridged the gap between the code and the column stream at `$C4`, so
`--raw-multiple-memories` folded the columns back into the main image and
`LevelColumns0.raw` stopped existing. The build had been splicing that file in
unconditionally and now failed outright — which was lucky, because the failure
mode trap 38 warns about is the silent one.

`tools/verify_rom_layout.py` replaces the assumption: it checks the finished
`.sfc` actually contains the column stream and every sprite CHR bank, and that
no CHR bank straddles a ROM bank. `pack_hirom.py` skips a `--part` whose file
the linker did not emit, and says so.

## What is still owed

- **The four 1KB CHR registers** are the background tilesets, still no-ops. Only
  correct while one tileset is loaded, which is the case for this level; a level
  that switches spike or block sets mid-level needs them to DMA BG tiles.
- **Parallax is deliberately not this.** `reset_level.h` calls
  `mmc3_set_1kb_chr_bank_2(parallax_scroll_x + PARALLAX_CHR)` every frame, and
  the 144 pre-shifted banks exist only because the NES cannot scroll a layer
  independently. On SNES that is one BG layer and a scroll register; uploading a
  bank a frame would be 12 scanlines of DMA to reproduce something the hardware
  does for free.
- **Thirteen icon banks and the nine contest icons are not carried** — they need
  the customise menu, which is not ported, so `icon` cannot change. Pass
  `--icons N` to `gen_sprchr.py` to include more; `shim_chr_unknown` counts
  requests for a bank the build does not have, and it is 0 in gameplay.
- **16x16 OBJ mode** is still the structural next step for the sprite budget —
  see [M2_13_PLAYER_AND_TEAR.md](M2_13_PLAYER_AND_TEAR.md).
