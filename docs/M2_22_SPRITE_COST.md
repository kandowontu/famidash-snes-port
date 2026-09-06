# M2.22 — Why the port lags where the NES does not, and the whole level set

Three things: find the lag the NES does not have, put every level in the ROM, and
make the level select usable with 168 of them.

---

## 1. The lag, measured against the NES

The port dropped frames on sprite-heavy levels — `cycles` ran at 80% of 60Hz —
and the NES does not. Every previous attempt at this guessed at the renderer and
was wrong (M2.17 §3.1 records two optimisations built, measured and reverted; traps 106-109).
This time the NES was measured directly, because it is available: Mesen runs it,
and `Famidash - Huge Man.dbg` gives the addresses.

### 1.1 The comparison has to be at the same load

The first NES/SNES comparison was useless: instructions per frame in the same
routines, but the NES run was wherever some blind button presses landed and the
SNES run was `cycles`. Different sprite counts, so the ratio meant nothing.

The comparison that works is **cost per call, bucketed by the number of active
sprite slots**. Both machines run 262-line frames at 60Hz, so a routine's cost in
scanlines is directly comparable even though the CPUs are not.

`sprite_collide`, scanlines per call:

| active slots | NES | SNES port |
| --- | --- | --- |
| 0 | 36.0 | 51.3 |
| 3 | 38.2 | 49.5 |
| 5 | 38.9 | 56.8 |
| 7 | 44.0 | 78.2 |
| 12 | — | 88.4 |

Two things fall out. The **fixed** cost is about 1.4x the NES's, which is what a
port compiled for a different CPU by a different compiler is expected to be. The
**marginal** cost per active sprite is about 3x — ~3.1 scanlines against ~1.1 —
and that is the part that makes a sprite-heavy level fall over while the NES
holds.

### 1.2 Where the marginal cost went

`tools/profile_instr.lua` counts instructions executed per game frame per
routine, by registering an exec callback over each routine's whole address range.
On `cycles`:

```
shim_meta_run     1533  (24.8%)
draw_sprites      1290  (20.8%)
check_spr_objects 1199  (19.4%)
sprite_collide     695  (11.2%)
_ValueSwitch16     683  (11.0%)   <-- a compiler library routine
```

`_ValueSwitch16` is Calypsi's helper for a sparse `switch`. `sprite_collide`
switches on the sprite's height code, which has five cases — `0`, `$FC`, `$FD`,
`$FE`, `$FF` — and **the common case is that a sprite has a real height and
matches none of them**, so the helper searched the whole table and failed, for
every active sprite, every frame. That is precisely a per-active-sprite cost,
which is precisely what the NES comparison said was wrong.

cc65 does not do this, which is why the NES build does not pay it.

### 1.3 The fix

The switch is now an if-chain in `overlay/functions/sprite_loading.h`, ordered so
the common path is rejected by one comparison — the four special codes are
`$FC`–`$FF`, so `tmp2 == 0 || tmp2 >= OUTL` covers all of them:

| | before | after |
| --- | --- | --- |
| `_ValueSwitch16` | 683 instr/frame | 173 |
| `sprite_collide` | 695 | 737 |
| **that path, total** | **1378** | **910** (−34%) |
| `cycles` | 80.4% of 60Hz | **86.9%** |

The bodies are spliced out of the original switch by the edit rather than
retyped, so they cannot drift from it.

### 1.4 What is left

The remaining gap is structural, and the numbers say where:

* `shim_meta_run` at 1533 instructions/frame is the OAM writer. Measured
  properly: **5.7 calls/frame, 276 instructions per call, ~26 OAM entries per
  frame — about 60 instructions per entry.** That is the number to attack, and
  it is in a file this port owns.

### 1.5 16x16 OBJ mode is worth ~20%, not 50% — measured

This was claimed as "halves the entries" for several milestones. It is wrong, and
the arithmetic is simple once stated: an NES 8x16 sprite is **8 pixels wide**, so
a 16x16 OBJ cannot stand in for one. It can only replace **two NES sprites side
by side**, and only when they share a row and their attributes match.

Counting the OAM entries actually drawn rather than the metasprite tables:

| | `cycles` | `lostinthewoods` |
| --- | --- | --- |
| OAM entries per frame | 26.3 | 24.1 |
| side-by-side pairs | 5.9 | 4.7 |
| ...with consecutive tiles | 4.7 | 4.6 |
| entries after 16x16 | 21.6 (**−18%**) | 19.5 (**−19%**) |

**This section's conclusion did not survive being built.** 16x16 mode removes the
OAM entries it says it does, and that is worth about 3% of the walker, because
OAM entries are a PPU per-scanline resource and the walker's cost is per
metasprite ENTRY - see [M2_23_OBJ16.md](M2_23_OBJ16.md). The rest of this section
is left as written because the reasoning about VRAM and the OBJ name space is
still correct and still the answer to "why not just combine four 8x8s".

And on the question of building a 16x16 out of any four 8x8 tiles: **VRAM bytes
are not the constraint.** Two things are.

* The OBJ **name** space is 512 tiles whatever the VRAM size, and a 16x16 sprite
  does not take four arbitrary tiles - it takes `N`, `N+1`, `N+16`, `N+17` in the
  16-wide OBJ tile grid. So "combine as needed" is a layout problem, not a
  capacity one. The port uses OBJ tiles 256-511 (two 4KB CHR banks), leaving 256
  names free: room for 64 such blocks.
* It is not worth the machinery. Allowing arbitrary combinations - duplicating
  tiles so any pair can be merged - only moves the saving from 18% to 23% on
  `cycles` and from 19% to 20% on `lostinthewoods`, because nearly every pair
  that CAN merge is already two consecutive tiles. A CHR re-layout that puts each
  NES 8x16 pair vertically (`N`, `N+16`) and consecutive sprites horizontally
  gets that for free, with no duplication and nothing to compose at run time.
* `draw_sprites` and `check_spr_objects` are ordinary C loops whose cost is
  dominated by 24-bit `long:` accesses to WRAM — the same variables the NES had
  in **zero page**. Moving the hot ones to the SNES direct page (or the `near`
  data model) is the other structural lever, and it means shadowing `famidash.h`.

---

## 2. Every level from the huge ROM

`lvlset_HUGE` is a strict superset of `lvlset_A`: all 46 of A's levels plus 122
more, **168 in total**, 962KB of LZ and 414KB of sprite streams. The build takes
`LVLSET` (default `lvlset_HUGE`) and threads it through every generator, so the
level set is one variable rather than a path repeated in five tools.

Two things had to stop being hand-written:

* **The linker script.** Six level banks was right for 46 levels and not for
  168. `tools/gen_linkcfg.py` emits the full ROM's `.scm` with as many banks as
  the data needs, bin-packing the per-level sections the way the linker will —
  divided, not simulated, would under-count, because a level that does not fit in
  what is left of a bank goes to the next and leaves the space empty. 24 level
  banks, 1 BG CHR, 1 sprite CHR: `$C0`–`$DC`, a 1.9MB ROM.
* **`Lucky_Draw_Text_Stuff`.** `level_loading.h` calls it `#ifdef
  level_luckydraw`, which only the HUGE set defines. It lives in `credits.c`,
  which is not ported, so it is lifted verbatim into
  `overlay/menustates/lucky_draw_text.h` rather than dragging the credits roll in.

### 2.1 Five tilesets that were not in the ROM

Worth its own note, because it passed everything. With more data the linker
started emitting **both** a merged `SpriteCHR.raw` covering bank `$C3` upwards —
holding all 15 BG tilesets correctly — **and** a separate `BGCHR.raw` holding
only 10 of them. `pack_hirom.py` spliced every part in the order given, so the
truncated copy landed on top of the good one and five tilesets disappeared.

The ROM linked, packed, and passed `verify_rom_layout.py` — which checked level
streams and sprite CHR but had never been extended to BG CHR. Levels rendered
with the wrong tileset, and only `verify_level_boot.lua`'s per-level tileset
comparison caught it.

Both halves are fixed: `pack_hirom.py` splices **largest raw first and fill-only**,
so a partial raw can only fill bytes nothing has claimed, and
`verify_rom_layout.py` now checks the BG tilesets too. Trap 38's warning was
right and its guard was incomplete.

---

## 3. The level select

168 levels is a different menu from 46.

**No blink.** The menu redrew straight into VRAM under forced blank, which is a
black frame on every keypress. It now keeps the visible rows in a WRAM shadow and
sends them as **one DMA in vblank** with the screen on: 704 tilemap words is about
a fifth of a vblank, where writing them one at a time does not fit. Measured, zero
forced-blank frames while the menu is up.

**Hold to scroll.** A press moves one row; holding repeats after 18 frames, and
once up to speed takes five rows a step. The step, not the interval, is what
makes it fast: a full rebuild of the window is about four frames whatever it
contains, so the cost is per rebuild.

Two things had to be fixed to get there:

* `menu_build` written the obvious way — `menu_rows[row][col] = level_names[lv *
  LEVEL_NAME_W + col]` — cost a multiply and a two-dimensional index per
  character, and Calypsi keeps loop counters in stack slots. Eight frames per
  rebuild. Pointer walks with sentinels, the same shape as trap 76, cut it to
  about four.
* The common move does not scroll the window at all, only the marker, so that
  case now writes **two** words instead of twelve hundred.

Measured end to end: **0.88 rows per frame**, so 168 levels take about three
seconds to walk.

**Wrap.** Up from the top goes to the bottom and back.

---

## 4. Where things stand

```
sh tools/build_game.sh       # LVLSET=lvlset_HUGE by default
sh tools/verify_all.sh
sh tools/sweep_framerate.sh  # every level, not just level 0
```

`out/famidash-snes-full.sfc` is 1,900,544 bytes, HiROM banks `$C0`–`$DC`, 168
levels.

Frame rate across the whole set (`tools/sweep_framerate.sh`, 1200-frame window
per level, so NOT comparable with the full-run figures elsewhere - trap 83):

| | levels |
| --- | --- |
| 99%+ of 60Hz | 51 |
| 95-99% | 45 |
| below 95% | 72 |

Mean 94.1%, median 96.1%. The worst are `XMASCHALLENGE` at 64.7% and a cluster
of the later HUGE levels around 77-80% - all of them sprite-heavy, which is
consistent with section 1: what is left is the per-sprite cost, and the fix for
it is 16x16 OBJ mode.

New tools:

| | |
| --- | --- |
| `tools/profile_instr.lua` | instructions per game frame per routine, from exec callbacks over each routine's address range |
| `tools/gen_linkcfg.py` | the full ROM's linker script, with as many data banks as the level set needs |
| `tools/gen_physics_expect.py` | the physics tables as a Lua oracle, parsed from the game's own header |
