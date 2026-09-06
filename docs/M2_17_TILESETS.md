# M2.17 — Per-level tilesets and colours, and where the frame rate actually goes

Three problems were reported after M2.16: massive slowdowns on `dorabaebasic4`,
"ship flight seems to have bad values", and "the right tilesets are not loading".
They turned out to be three different things — one real and fixed, one not a bug,
and one real, now measured properly and not fixed.

---

## 1. The tilesets — real, fixed

**Only one BG tileset was ever in the ROM.** `snes_m0.py` builds `bg1.tiles.bin`
for a single level, and that was uploaded once at boot and never changed. Ten of
the 46 levels happen to use stereomadness's combination; **the other 36 drew the
right shapes from the wrong art.**

On the NES the BG pattern table is four switchable 1KB CHR banks, chosen per
level (`_set_tile_banks` in `LIB/asm/neslib.s`):

| bank | tiles | contents |
| --- | --- | --- |
| 0 | `$00-$3F` | `current_spike_set` — level header, high nibble |
| 1 | `$40-$7F` | `current_block_set` — level header, low nibble |
| 2 | `$80-$BF` | parallax, or a SLOPE set chosen by the block set when the level disables parallax |
| 3 | `$C0-$FF` | `current_saw_set` — `SAWBLADESA` for every level in this set |

`tools/gen_bgchr.py` enumerates the combinations the level set actually uses —
**ten**, 40KB — converts each to SNES 2bpp, and emits `lvl_bg_tileset[]`. The
SNES has no CHR ROM so the bank switch is a transfer, but unlike the sprite banks
([M2_14](M2_14_CHR_BANKING.md)) these change only at level load, so the whole 4KB
goes at once. `set_bg_tileset()` queues it and flushes immediately when the
screen is in forced blank — without that the level's first two frames show half
the previous level's tiles, and the seam lands exactly at byte 2048, the vblank
CHR budget.

Cross-check worth keeping: generated tileset 0 is **byte-identical** to the
`bg1.tiles.bin` the old single-level path produced.

### 1.1 The level's own two colours

The same fault, one level down: `lvl_bg_color` and `lvl_ground_color` were parsed
into the ROM and then never read. The level header's colours go where `nesdash.s`
puts them —

```
PAL_BUF+0        the universal backdrop = bg_color
PAL_BUF+1,+9,+13 bg_color one brightness step darker
PAL_BUF+6        the ground = ground_color
PAL_BUF+5        ground_color one step darker
```

— and the darkening is a lookup, not arithmetic: `palBrightTable3` maps `$30` to
`$10`, not to `$20`. `tools/gen_palette.py` copies that table out of
`LIB/asm/neslib.s` rather than reimplementing it.

### 1.2 What it took to check this correctly

The obvious check — read CGRAM at the end of the test window — **fails, and the
failure is the game working properly.** Famidash changes the background colour
mid-level from `COLR` objects in the level's own sprite stream
(`sprite_loading.h`), so what is in CGRAM at any given frame depends on how many
colour triggers the camera has passed, and how long the level took to load. Two
different wrong answers came out of that before it was clear the check was wrong
rather than the port.

So the two are checked at different, deterministic moments:

* the **tileset** as soon as the level has loaded — `rld_column > 0`, the level
  select's palette gone, **and `shim_chr_pending == 0`**, because a 4KB upload is
  two vblanks and sampling in between reads half of it;
* the **colours** from an exec hook on `load_ground()`, the last call `init_rld`
  makes, re-read on every call — the first call happens during boot before any
  level is chosen, and latching there recorded the default palette for all 46.

Both are in `verify_level_boot.lua`, for every level. All 46 pass.

---

## 2. The ship — not a bug

Measured rather than argued. Forcing ship mode and sampling per GAME frame (not
per video frame — a dropped frame reads as a stalled velocity and then a double
step, which looks exactly like bad physics):

* gravity is `-42` per frame holding, `+34` released, against
  `SHIP_GRAVITY_BASE[4] = 0x2A = 42` and `SHIP_GRAVITY[4] = 0x22 = 34`;
* the velocity clamps at exactly `-1091` and `+873`, which are `-0x0443` and
  `+0x0369` from `gamemode_ship.h`;
* `currplayer_table_idx` is 4 = `framerate<<2 | mini<<1 | gravity`, correct;
* the three-way `tmpgravity` select compiles correctly — all three arms converge
  on one store, not the merge-point defect (trap 8).

The ship's tiles come from the sprite CHR banks, which were already verified, so
what was seen was most likely the wrong BG tileset behind it (section 1) or the
frame drops (section 3).

---

## 3. The slowdown — real, measured, not fixed

`dorabaebasic4` is level 29. It is not special: **19 of 46 levels run below 95%
of 60Hz**, the worst around 73%. Level 0 — the only level the frame-rate check
had ever run on — holds 100%.

```
sh tools/sweep_framerate.sh
```

Where a dropped frame goes, on the worst level (`electromanadventures`), in
scanlines of a 262-line frame:

```
music_update  4 | sprite_collide 70 | check_spr_objects 23 | draw_screen 58
              | draw_sprites 111                                    = 266
```

**The sprite code is the problem, not the level renderer.** Two independent
confirmations:

* the correlation between level height — which is what `draw_screen` costs scale
  with — and frame rate is **+0.01**. The slowest levels are mostly height 27,
  the same as stereomadness at 100%;
* levels 22–25 are platformer levels where the camera does not auto-scroll, so
  `draw_screen` streams almost nothing. They run at 100%.

### 3.1 Two optimisations built, measured, and reverted

Both are recorded because the reasoning that motivated them is wrong in an
instructive way, and someone will otherwise try them again.

**Decouple preparation from streaming.** `draw_screen` did all its work on the
frames that stream a column and returned immediately on the rest, so the obvious
move was a state machine doing one unit of work per call — decode, build left,
build right + collision — whether or not a column was due. Built, verified
byte-exact, measured: **91.6% against 91.7%**. The premise is false. At these
level speeds the camera needs a new tile column on about **90%** of frames, so
there are no spare calls to spread into.

**Split `metatile_words` into four planes of 256.** One interleaved table of
1024 costs a shift and an add per metatile to build the index; four planes make
the metatile byte the index directly. Measured: **90.3% against 91.6% — slower.**
Four far base pointers cost more than the shift they save.

Neither is in the tree. Trap 84: an optimisation that does not move the number is
not an optimisation.

### 3.2 What would actually move it

`draw_sprites` at ~111 scanlines and `sprite_collide` at ~70 are the two largest
items, and both are the game's own sprite code walking NES-shaped metasprites.
The structural fix is the one [M2_15](M2_15_SPRITE_BUDGET.md) already identified:
**16×16 OBJ mode**, which halves the OAM entries and the per-sprite work. That is
milestone-sized and is the next thing to do.

---

## 4. Verification

`verify_level_boot.lua` now checks, for every level: the inflated RLE byte for
byte, the streamed tilemap columns word for word, **the BG tileset in VRAM byte
for byte, and the six CGRAM entries the header's colours set** — plus that the
level reaches `STATE_GAME`, keeps streaming, and leaves the player on screen.

```
rom layout               RESULT: ROM LAYOUT OK
verify_render            RESULT: LEVEL RENDERED
verify_sprite_chr        RESULT: SPRITE CHR CORRECT, AND BANK SWITCHING WORKS
verify_gamemode_sprites  RESULT: EVERY GAMEMODE DRAWS ITS OWN SPRITES
verify_cube_spin         RESULT: SPIN RATE MATCHES THE PHYSICS TABLE
verify_framerate         RESULT: HOLDS 60Hz            (level 0)
verify_level_boot        RESULT: ALL 46 LEVELS LOAD AND STREAM
framerate sweep          RESULT: 19 of 46 levels below 95% of 60Hz
verify_menu              RESULT: MENU OK (44 names verified)
```

`out/famidash-snes-full.sfc` is 720,896 bytes, HiROM banks `$C0`–`$CA`.
