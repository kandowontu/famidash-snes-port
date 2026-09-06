# M2 — the level renders

> Resuming work? [HANDOFF.md](HANDOFF.md) has the current state and next task.

## Result

**`out/famidash-snes-full.sfc` streams and renders the real level, driven by the
game's own code.** `draw_screen()` is implemented; the tilemap is verified
byte-exact against the level data, 8160 words checked, zero wrong.

```bash
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_render.lua
cat out/render_verify.txt
```

```
frame  400  rld_column=   82   resident 18-81   correct 63, HUD-overlaid 25, wrong 0
8160 tilemap words checked, 0 columns wrong, 26 differing only in the game's own HUD row
RESULT: LEVEL RENDERED
```

`verify_render` reads the renderer's own cursor (`rld_column`) and checks each of
the 64 resident map slots against the precomputed record it should hold. It does
**not** try to infer which column is where: the level opens on empty sky, so
column 0 matches dozens of others and the search locks onto the wrong one — the
first version of this check "passed" partly by accident.

Columns marked *HUD-overlaid* differ only in tilemap row 15, where the game draws
its own `ATTEMPT n` text (`level_loading.h`, `NTADR_C(6,15)` and `NTADR_C(20,15)`),
exactly as it does on the NES. That is the game, not the renderer, and the check
says so rather than quietly tolerating a mismatch.

## What is on screen, and what is not

The tilemap is correct, but the picture is still mostly sky. Two reasons, both
expected and both still stubbed:

- **`load_ground` does nothing**, so the bottom rows of the playfield are empty.
  This is also why palette 1 has been unused in every render since M0 — and, as
  the collision section below shows, it is the *floor*, not decoration.
- **The level header is never read**, so `spawn_y_pos` is 0 and the player starts
  at the top of the level rather than at its spawn point.

So: the renderer is done, the level is not yet playable. Do not read the
screenshot as a failure of `draw_screen` — `verify_render` is the check that
matters, and it is exact.

## Three bugs, in order of how long they cost

### 1. VRAM writes during active display are silently dropped

`flush_vram_update2()` wrote VRAM the moment it was called, but the SNES only
accepts VRAM writes in forced blank or vblank; outside those the write simply
does not happen. The NES had the same restriction — that is the entire reason
nesdoug has a VRAM buffer — but its flush ran from NMI, and the game calls this
one from wherever it likes.

Now `flush_vram_update2()` writes only in forced blank and otherwise leaves
everything queued for `ppu_wait_nmi()` to push in vblank. `ppu_wait_nmi` calls an
internal `vram_flush_now()` instead, because it already knows it is in vblank.

`snes_main_full.c` also had to stop turning the screen on at boot: `reset_level()`
does `ppu_off()` … draw the first screen … `ppu_on_all()`, and the renderer
depends on that window.

### 2. A C loop cannot fill vblank's budget — this needs DMA

With the flush timing fixed, columns written during level init were right and
every column written during gameplay was wrong. Writing 64 bytes a byte at a time
from C overruns vblank, and the tail of each column is lost — which looks
identical to "the renderer computed the wrong data".

Both big transfers are DMA now:

| | |
|---|---|
| tilemap column | 64 bytes → `VMDATAL/H`, mode 1, `VMAIN` stepping +32 words |
| OAM | 544 bytes → `OAMDATA`, mode 0 |

This is why the column records are bank-aligned (`tools/gen_columns.py`): **DMA
increments the A-bus address within a bank and does not carry into the bank
byte**, so a record straddling a bank would wrap to the start of its own bank
halfway through.

OAM had to become a single 544-byte buffer for the same reason — it was two
arrays that happened to sit next to each other, which is not something C
guarantees and one relink would have broken.

### 3. `--raw-multiple-memories` writes extra files you have to collect

Giving the column stream its own memory means the linker writes it to
`out/LevelColumns0.raw`, *not* into the main image. Everything links, the map
looks right, and the ROM is simply the size of the code. `pack_hirom.py` takes
`--part FILE@BANK` and splices it back in; HiROM maps bank `$C0` to file offset 0,
so a bank's offset is `(bank - 0xC0) << 16`.

## How the renderer works

One tilemap column per call, from records `tools/snes_m0.py` precomputes — **not**
a translation of the 355-line 6502 original, which spread one column across three
frames because that is all an NES vblank affords, and spent one of those frames on
attribute-table work that has no SNES equivalent. `src/scroll.s` already proved
this shape and the cadence mirrors it: keep `COLS_AHEAD` (34) columns ahead of the
leftmost visible column, `scroll_x >> 3`.

The 64×32 BG1 map is two 32×32 screens back to back, so column *n* lands at
`(n & 31) + (n & 32 ? 0x400 : 0)` words from the base and the map wraps every 64
columns, which is what lets the level stream past it indefinitely.

Layout: the stream is split into 64KB bank-sized parts, because the linker
allocates ROM in bank chunks and a single 128KB section cannot be placed at all.
`src/snes-HiROM.scm` provides four such banks (`$C4-$C7`); `gen_columns.py` errors
if a level needs more.

## The scaling decision, deliberately not made yet

Precomputing this level costs **128KB of ROM for one level**, taking the full ROM
from 128KB to 384KB. This level set has 46 levels and there are 454 level files
across all sets, so this does not generalise: the full game needs the RLE and
metatile decode to happen at run time, from the compressed data, as the NES does.

This is the single-level path, chosen because single-level gameplay is the current
scope. Choosing between "precompute per level set" and "port the decoder" is still
open, and should be a decision rather than a default.

## Collision-map streaming is done — and it revealed why the player falls

`draw_screen()` now refills the collision map as it streams, from a per-column
slice `tools/snes_m0.py` emits alongside the tilemap columns
(`level_collcols.bin`, 898 columns x 60 metatiles = 4 rooms each).

The window is 16 metatile columns = 256 pixels = exactly one screen, because
`bg_collision_sub()` reads `collMap[room & 3][(x >> 4) | (y & 0xF0)]` and
`temp_x` is a byte - so metatile column *c* always lands in slot `c & 15`. That
is the NES design, and it is what lets a whole level stream through a 1KB map.

Record row `p*15 + r` is world metatile row `p*15 + r`: the rooms are the level
sliced into 15-row bands from the top. An earlier version anchored the rows to
the *bottom* of the level (copying what the static window in `emit_collision_map`
does), which put the floor 12 rows away from where `add_scroll_y()` says it is.

**The player still falls, and now we know why.** Measuring the emitted stream:

```
898 columns, 6694 non-zero collision bytes, first column with any collision: 17
```

The first 17 metatile columns of Stereo Madness have **no collision data at all**,
and the level data is not missing anything - *the floor is not in it*. Famidash
draws the ground as a separate strip via `load_ground`, which is still stubbed.
So there is genuinely nothing to stand on, and the player falls through the
run-up exactly as it should given an absent floor.

This is why `load_ground` is the next task and not the sprite engine: it is the
floor, not decoration, and it is also why palette 1 has been unused since M0.

A second thing the trace showed: `spawn_y_pos` and `spawn_scroll_y_pos` are both
**0**. They come from the level *header*, which nothing reads - the port
precomputes geometry and never decodes level data at run time. The player
therefore starts at y=0 rather than at the level's spawn point. That needs
solving too, and it is the first place the precompute-vs-runtime-decode decision
starts to bite.

## The ground layer — implemented, and the player now reaches the floor

`load_ground()` is ported from `_load_ground` in nesdash.s. It RLE-decodes a
48-byte strip — **3 rows x 16 metatile columns** — which `draw_screen()` then
copies into the bottom three rows of collision page 3 as each column streams,
exactly as `writeToCollisionMap` does per column on the NES.

Getting the row layout right mattered more than the decoder. The collision
window is 60 rows (4 pages x 15) and the level is **bottom-aligned** in it, with
the last 3 rows reserved for the ground:

```
buffer rows  0..29   unused for a 27-row level
buffer rows 30..56   level metatile rows 0..26   -> pages 2 and 3
buffer rows 57..59   the ground strip            -> page 3, rows 12..14
```

`writeToCollisionMap` shows this directly: its guards (`cpy #<-(15+15+12)` and
friends) skip whole pages for a short level, and `write_ground` fills
`columnBuffer[57..59]`. An earlier version here wrote level row *n* to page
*n/15* — top-aligned — which put the whole playfield two pages above where
`add_scroll_y()` looks for it.

Measured in the running ROM: collision page 3 holds exactly **48 non-zero
bytes** once the first 16 columns have streamed, and the probe starts returning
hits (`collision = 4`) as the player descends into room 3, at which point its Y
stops changing. The floor exists and the player meets it.

## The level header — the player now spawns and stands

`init_rld()` applies the 13-byte level header that precedes the LZ stream in
`all_level_data.s`. Nothing was reading it, because this port consumes the `.lz`
file directly and that file is the RLE stream **only**. Every field it carries
stayed 0, and the visible effect was `spawn_y_pos = 0`: the player started at the
top of the level, fell three rooms to the ground, and the level reset.

`tools/gen_assets.py` parses it into `out/level_header.c`:

```
stereomadness: spawn_y=0xB000, spawn_scroll_y=0x02EF, height=27
```

`spawn_scroll_y_pos`'s high byte is not in the header at all — `nesdash.s`
hardcodes `$02` with the comment *"no levels need this setting, at least yet"* —
so the shim hardcodes it too, for the same reason and with the same note.

**Measured result:** the player spawns at `0xB000` and holds `0xB200` for 600
consecutive frames. It is standing on the ground, not falling, and the level no
longer resets on a timer. It then runs forward under `x_movement()` and dies on
the first spike — which, with no input and no jump, is correct.

## Known gap: the ground has collision but no tiles

`load_ground()` fills the *collision* map. It does not draw the ground's
*tiles*, so the floor is solid but invisible. On the NES `write_ground` also
feeds `columnBuffer`, which drives the tile rendering; here the tilemap columns
are precomputed from level data, and **the level data does not contain the
ground**. The precomputed column stream needs the ground strip composited into
its bottom rows — a change in `tools/snes_m0.py`, not in the shim.

## Vertical scrolling: the tilemap cannot hold a whole level

**Measured across all 46 levels in the set** (`gen_assets.parse_level_header`, header
byte 12):

```
distinct heights: 27, 32, 35, 36, 40, 47, 48, 51, 57 metatile rows
max: 57  (watertemple, theoryofeverything, thechallenge, dorabaebasic4)
```

57 + 3 ground rows = **60**, which is exactly the collision window (4 pages x 15).
That is the design constraint, not a coincidence.

| | |
|---|---|
| tallest level, 60 metatile rows | 120 tile rows | 960 px |
| SNES maximum tilemap, 64x64 | 64 tile rows | 512 px |

**So the tilemap cannot hold a whole level vertically, and vertical row streaming is
required.** The NES seam exists for exactly this reason. A 64x64 map is worth having
anyway - it doubles the vertical window from 256px to 512px and so makes row streaming
rare rather than constant - but it does not remove the need for it.

Sizing, for whoever picks this up:

- 64x64 costs 8KB of VRAM (4096 entries x 2 bytes), at words `$1000-$1FFF`. Tiles are at
  `$0000-$0FFF` and OBJ at `$2000`, so it fits the current layout with no rearrangement.
- A column record becomes 64 tile rows = 128 bytes, written as **two** DMAs: 64x64 is four
  32x32 screens, so rows 0-31 land in SC0/SC1 and rows 32-63 in SC2/SC3, `$800` words apart.
- Levels up to 29 metatile rows (29 + 3 = 32 -> 512px) fit entirely and need no vertical
  streaming at all. **Stereo Madness, at 27, is one of them** - so a 64x64 map alone would
  finish the current single-level target, with row streaming still owed for the other 45.
- The vertical origin needs an offset. The level is bottom-aligned in the 60-row collision
  window, so for a height-*h* level it starts at metatile row `60 - 3 - h`, i.e. pixel
  `(57 - h) * 16`. `set_scroll_y()` currently subtracts only the 1-pixel `BG1VOFS` fudge
  (trap 21); it will need that origin subtracted too.

This is why the ground tiles were not simply composited into the precomputed columns: doing
that correctly means settling the vertical windowing first, and the answer is different for
a 27-row level than for a 57-row one.

## 64x64 map, ground tiles, vertical origin — done

The tilemap is now **64x64**: 512px tall instead of 256, 8KB at words `$1000-$1FFF`,
which fits the existing layout unchanged (tiles `$0000-$0FFF`, OBJ `$2000`).

Three consequences, all handled:

- **A column record is 64 tile rows = 128 bytes, written as TWO DMAs.** 64x64 is
  four 32x32 screens at +0, +`$400`, +`$800`, +`$C00` words, so rows 0-31 go to
  SC0/SC1 and rows 32-63 to SC2/SC3, `$800` words apart.
- **The ground is composited into the column records.** It is not in the level
  data, so `tools/snes_m0.py` decodes the same RLE strip `load_ground()` does and
  appends its 3 metatile rows below the level before building the tilemap.
- **`set_scroll_y()` subtracts a vertical origin.** The scroll value is in
  collision space, whose origin is the top of the 60-row window; the level is
  bottom-aligned in it, so the tilemap's row 0 sits `level_scroll_origin` pixels
  lower - 480px for a 27-row level. `gen_columns.py` emits the constant, so it
  tracks the level rather than being hardcoded.

Verified: **14592 tilemap words checked, 0 wrong.** The screenshot shows flat
ground, a horizon and a spike standing on it.

### Two column streams, on purpose

`tools/snes_m0.py` now emits both:

| | | |
|---|---|---|
| `level.cols.*` | 32 rows, 64x32 | the assembly scroll ROM (`src/scroll.s`) |
| `level.cols64.*` | 64 rows, 64x64, ground composited | the C game ROM |

Only one ends up in any given ROM. Changing the shared format in place broke
`verify_scroll` (3830/7168) without breaking anything the game ROM checks — the
assembly ROM is a verified baseline and it should not rot silently when the game
ROM's format moves.

### Levels taller than 29 metatile rows still need row streaming

512px covers 29 metatile rows plus the 3 ground rows. Stereo Madness at 27 fits
entirely. The other 45 levels in the set run up to 57 rows (960px) and will show
only their bottom 64 tile rows until vertical row streaming exists.

## The player sprite — drawn, but with no tiles loaded yet

`drawplayerone()` is ported from `_drawplayerone` in nesdash.s: the CUBE arm,
which is the default there and is shared by robot, ninja and football. The other
gamemodes fall back to it rather than drawing nothing — wrong-looking beats
invisible while they are ported one at a time.

It carries the real behaviour: the "on a slope" bit in `cube_data`, the
`(temp_x - 1) > 0xFB` edge guard, the per-gamemode centre offsets, and the
rotation logic — snap to the nearest quarter turn when grounded, spin in the
direction of gravity when airborne. The cube has 7 drawn frames and the other 17
of its 24 rotation steps are those seven mirrored, which is what
`drawcube_sprite_table` encodes (flip flags in bits 6-7, index in bits 0-2).

### Sprite CHR: three separate NES/SNES mismatches

Getting the cube to actually appear needed all three of these, and none of them
is a copy:

**1. NES sprites are 2bpp; SNES OBJ is always 4bpp.** There is no 2bpp sprite
mode. `nes_chr_to_snes_4bpp()` interleaves the rows as usual for planes 0/1 and
appends 16 bytes of zero for planes 2/3 - 16 bytes per tile in, 32 out. Pixel
values stay 0-3, which matters for the next point.

**2. The game runs the NES in 8x16 sprite mode** (`PPU_CTRL` bit 5, set in
crt0.s), and the SNES has no 8x16 OBJ size - sizes come in pairs like 8x8/16x16.
So **one NES sprite becomes two SNES 8x8 sprites, stacked**. In 8x16 mode the
NES tile byte also means something different: bit 0 selects the pattern table and
the rest is the tile *pair*, so the halves are `chrnum & 0xFE` and that + 1. A
vertical flip swaps which half goes on top.

**3. Four 4-colour palettes vs eight 16-colour ones.** Because the converted
tiles keep values 0-3, NES sprite palette *p* maps onto the **first four
entries** of SNES OBJ palette *p* - CGRAM `128 + p*16 + c`, with the other 12
entries of each unused. That is what lets one tile be drawn under any of the four
palettes, as on the NES, instead of keeping four recoloured copies of the art.

Pattern table 1 (which the cube's metasprites index) maps to SNES OBJ tiles 256+,
which OBSEL's name-select puts `$1000` words above the OBJ base - so the icon
bank uploads to word `$3000`.

Also unresolved: `trap 28 does not apply to the sprite tables`. `Metasprites[]`
and the per-gamemode tables are real C pointer arrays
(`const unsigned char * const []`), so Calypsi builds proper 24-bit pointers for
them. The trap is only about raw byte tables holding 16-bit addresses, like the
`animation_ptr` case already fixed in `draw_sprites.h`.

## The player position bug — an 8-bit comparison compiled as signed

The cube drew 80px too far left. The read was fine; the guard was not.

```c
if ((uint8_t)(px - 1) >= 0xFC)   /* px == 0, or wrapped off the right edge */
    px = 0;
```

compiles to:

```
sec
sbc  #-4        <- 0xFC narrowed to SIGNED -4
bmi  ...
```

so the test became "79 >= -4", which is true for every ordinary position: the guard fired
every frame, `px` became 0, and the sprite landed at `0 + centre_offset` = 8 instead of 88.
In C the operand promotes to `int` and the comparison is against 252.

**This is not trap 8**, and `scan_stackslots.py` cannot see it - the build scanned clean the
whole time. Widening the operand keeps it unsigned:

```c
uint16_t pxw = player_draw_px;
if (pxw == 0 || pxw >= 0xFD)
    player_draw_px = 0;
```

which compiles to `and ##255 / cmp ##253 / bcc` - correct.

Worth recording how it was found, because two plausible theories were wrong first: the fix
came from instrumenting **every hop** of the call chain in one run
(`drawplayerone -> oam_meta_spr_flipped -> meta_spr -> oam_spr -> oam_put`) and seeing the
value arrive already wrong at the first hop. Guessing at trap 8 twice cost more than that
one measurement did.

## Input — the pads are polled in vblank, not by the game

On the NES, neslib's **NMI handler** polls both controller ports every frame
(`LIB/asm/neslib.s`), which is why every `pad_poll()` call in `SAUCE/` is
commented out. This port has no NMI handler, so nothing polled and `joypad1`
stayed zero forever: the game read a button state of 0 every frame and the
player could not be controlled, with nothing visibly broken to point at.

The poll now sits at the end of `ppu_wait_nmi()`, which is this port's stand-in
for the NMI. **After** the DMAs, not before: the SNES auto-joypad read takes
about three scanlines from the start of vblank and `pad_poll()` spins until it
completes, so polling first would burn the vblank budget the CGRAM/VRAM/OAM
transfers need.

`tools/verify_input.lua` checks both halves, because either alone can pass for
the wrong reason - that the decoded pad state reaches the game
(`joypad1.hold` = `0x80` = `PAD_A`), and that the player actually leaves the
ground while the button is held:

```
resting y = B200
joypad1.hold peak = 80   (PAD_A = 0x80)
player rose 34 px
RESULT: PASS
```

**34px is the cross-check worth noticing**: it matches the 34.3px apex measured
independently on the physics ROM back in M1.4, from `JUMP_VEL[4]` and
`CUBE_GRAVITY[4]`. The same physics is running, now driven by a real button.

## The camera would not scroll up — trap 56 again, in the scroll arithmetic

Reported from play: the player rises, the screen stays put, and they die on the
ceiling.

Instrumenting `process_y_scroll()` term by term showed the guard was **fine** -
all three conditions true, the upward branch entered - and yet `scroll_y` never
changed. The loss was one level down:

```
sub_scroll_y(0x1E, 0x02EF)  ->  0xFFD1        (should be 0x02D1)
```

`sub_scroll_y` had `uint8_t` locals, so `lo >= sub` with `lo = 0xEF` and
`sub = 0x1E` compiled as an 8-bit **signed** compare: "-17 >= 30" is false, it
took the borrow path, and returned nonsense. The `lo >= 0xF0` test had the same
problem (`0xF0` becomes -16).

Both `sub_scroll_y` and `add_scroll_y` are now `uint16_t` throughout, which keeps
the comparisons unsigned. Measured after the fix, forcing the player high:

```
f318 scroll_y=02EF    f330 scroll_y=02B0    f336 scroll_y=0200    f342 scroll_y=0200
```

The camera follows and stops at `min_scroll_y` - the top of the level.

**`min_scroll_y` was a second, independent bug found on the way**: it was 0,
because nothing set it. That lets the camera rise above the level, and here that
is worse than on the NES because `set_scroll_y()` subtracts
`level_scroll_origin` - past the top, the subtraction underflows and `BG1VOFS`
wraps to the bottom of the tilemap. `init_rld()` now derives it from the level
geometry (`0x0200` for a 27-row level).

### This is the second user-visible bug from trap 56

The first was the player drawn 80px too far left. **Assume it.** Any `uint8_t`
compared against a constant >= `$80`, or against a value that can exceed 127, is
suspect, and `scan_stackslots.py` cannot see any of it. Position and scroll
arithmetic in the shim is now written with `uint16_t` locals as a matter of
policy.

### How it was found, which is the reusable part

Term-by-term instrumentation, not inspection. The guard *looked* wrong and was
not; the function that looked fine was returning garbage. Recording each
condition and each intermediate into a traceable global and reading them in one
run took minutes, after inspection had already cost far longer on the player-X
bug.

## Still stubbed

```
load_ground          the ground strip - why palette 1 is unused
init_sprites         reset the active-sprite table
check_spr_objects    stream sprite objects in and out with the camera
drawplayerone/two    the player metasprite
```

Plus collision-map streaming, which is not one of the NES entry points — the NES
built the collision map inside `draw_screen`'s third frame. On SNES it needs to
happen alongside the column write, and it is what stands between this and a
playable level.
