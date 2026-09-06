# M2.16 — All 46 levels, a level select, and FastROM

**Goal.** Make the port testable on more than one level: put the whole level set in
the ROM, decode it at runtime, and put a menu in front of it. Then get the frame
rate back, because runtime decode cost most of what M2.15 had won.

**Result.** All 46 levels are in the ROM and every one of them loads, decodes and
streams. The level select draws its own font, lists all 46, and scrolls. The game
holds 60Hz — 99.8-100.0% of frames, worst 300-frame window 99.3% — while decoding
the level at runtime, which the 100% it replaced was not doing: that figure came
from a level whose columns had been precomputed offline into 230KB of ROM.

---

## 1. Every level, decoded at runtime

M2.12 shipped one level, as a precomputed stream of tilemap columns: 230KB of ROM
for stereomadness alone. Forty-six of those do not fit in any cartridge worth
building. The whole set as the game's own compressed data is 197,822 bytes of LZ
plus 87,751 bytes of sprite objects — under 300KB for everything — so the decoder
moved into the game.

`tools/gen_levels.py` emits one `.incbin` per level into section `lvldata`, plus
`out/level_table.c` with the per-level pointers and the 13-byte headers, and
`out/metatile_words.c` with the 256×4 tilemap words. `src/snes-HiROM.scm` declares
the level banks one per 64KB bank so no level's stream straddles one — a level is
read through a single far pointer, and DMA does not carry into the bank byte
(trap 37).

The runtime side is three stages in `shim/src/shim_engine.c`:

| stage | what it does |
| --- | --- |
| `lz_decompress` | inflates the level's `aart_lz` stream into `level_rle[20480]`, once, at level load |
| `decode_metatile_column` | walks the vertical RLE to produce one metatile column |
| `build_tile_column` | expands metatiles to tilemap words for one of the two tile columns |

`init_rld` caches the inflated level, so re-entering a level after a death does
not re-inflate it.

### 1.1 The decompressor was wrong on every level, and the tests said fine

The first version of this shipped with **all 46 levels subtly corrupt**, and it
took a bug report ("just tried lostinthewoods and got this") to find out. Two
independent failures, one in the port and one in how it was checked.

**The port.** Calypsi 5.18 compiles a cast to `uint8_t` used as an *array index*
as a SIGN extension:

```
    lz_ring[(uint8_t)(idx + n)]   ->   eor ##128 / and ##255 / sec / sbc ##128 / tax
                                       lda long:lz_ring,x
```

so ring index 159 read `lz_ring - 97`. Reading a plain `uint8_t` variable is
fine — `and ##255` — it is the cast in the subscript that goes wrong. Every LZ
copy whose source stayed below ring index 128 was correct, and on both levels
examined **the very first copy to read index ≥ 128 was the first wrong byte**.
The stream then resynced on the next literal, so a level decoded perfectly for a
few hundred bytes, produced six bytes of whatever was in front of the array, and
carried on — drawing a wall of one metatile where there should have been sky.
Trap 94; `tools/scan_signext_index.py` now runs in the build and its header
carries a reproducer.

**The checking.** `verify_render.lua` was byte-exact and had been for four
milestones — but its oracle was the *precomputed ROM stream*, which only ever
existed for stereomadness. The other 45 levels were covered by
`verify_level_boot.lua`, which asked whether the tilemap was non-empty. Forty-six
levels passed a test that could not fail. Trap 95.

### 1.2 What is verified now

`tools/gen_level_columns.py --all` generates a per-level oracle — both the
inflated RLE and the tilemap columns — by going back to the `.lz` file and
`metatiles.inc`, independently of the shim (trap 61). `verify_level_boot.lua`
then checks, **for every level**:

* `level_rle` holds exactly what the level's `.lz` inflates to, byte for byte;
* the streamed tilemap columns match the oracle, word for word;
* the game reaches `STATE_GAME`, columns keep streaming, the tilemap is not
  empty, and the player is on screen.

All 46 pass. `verify_render.lua` takes `LEVEL` too and reports which rows of a
wrong column differ and to what, which is what turned "column 48 is wrong" into
"column 48 is one metatile repeated where sky was expected".

---

## 2. Getting the frame rate back

Runtime decode cost 5.7 points: 100% → 94.3%, with a worst 300-frame window of
82.7%. Two changes and a third unrelated one took it back to ~100%.

### 2.1 Split the work evenly, not just in half

`draw_screen` streams one tile column per game frame, and a metatile column is two
tile columns — so its work is naturally spread over two frames. It was not spread
evenly. The first attempt put decode and both column builds on the even frame and
the collision write on the odd one:

```
even frame  decode + build both columns + queue    63 scanlines
odd  frame  write collision column + queue         35 scanlines
```

63 scanlines is 24% of a frame on top of the ~200 everything else needs, and the
even frame was the one that dropped. Building **one** tile column per frame is a
few instructions more work overall and much less peak:

```
even frame  decode + build left  + queue           ~50 scanlines
odd  frame  build right + collision + queue        ~50 scanlines
```

`tools/profile_drawscreen.lua` reports the distribution rather than an average,
which is the only useful shape for this: 34% of calls stream a column at all, and
what decides whether a frame drops is how big that burst is, not the mean.

### 2.2 Expand RLE runs with a walking pointer

`decode_metatile_column` called `rle_next()` once per metatile — up to 57 calls
for one column, 33 scanlines. A level column is mostly runs (solid ground, solid
sky), so the run is now expanded in place with a walking pointer and `rle_next()`
handles only the case where the cursor is not already inside a run. Same trick as
`write_collision_column` (trap 76) and `build_tile_column`.

### 2.3 FastROM — the one that mattered most

`MEMSEL` was 0 and the header's map mode byte was `0x21`: SlowROM, 2.68MHz. Every
byte of this port — code, level streams, sprite CHR — is at banks `$C0`–`$C9`,
which is exactly the `$80`–`$FF` range FastROM speeds up. Setting the header to
`0x31` and `MEMSEL` to 1 took the port from 96.5% to ~99% on its own, and the rest
of the way once the run started from a consistent point.

Both halves are required and neither is any use alone; hardware ignores `MEMSEL`
if the header does not declare fast, and declaring fast does nothing until
`MEMSEL` is written. Both ROM images share `shim/src/snes_header.s`, so the small
probe ROM sets `MEMSEL` too rather than running slow under a header that claims
otherwise.

| | overall | worst 300-frame window |
| --- | --- | --- |
| precomputed columns (M2.15) | 100% | — |
| runtime decode, uneven split | 94.3% | 82.7% |
| + even split, faster RLE | 96.5% | 94.0% |
| + FastROM | **99.8-100.0%** | **99.3%** |

The spread in the last row is real and not noise to be averaged away: the figure
depends on which stretch of the level the scripted run happens to cover, and the
harness's entry into gameplay moved when `menu_skip.lua` started poking the
selection instead of walking to it. Compare rows only when they were measured the
same way — trap 83.

---

## 3. The level select

### 3.1 The game has no alphabet

This took a while to establish and is worth writing down, because every obvious
lead is wrong:

- The level tileset has no letters. "ATTEMPT" is spelled `PQQRSTQ` — level tiles
  that happen to look like letters.
- `GRAPHICS/Menus/menus.chr` is **not** an ASCII font. The menu code calling
  `one_vram_buffer('g', NTADR_A(...))` looks like proof that it is; it is placing
  tile `$67`, which is a piece of menu artwork. Rendering tiles `$41`–`$5A` shows
  graphics fragments, not A–Z.
- `LETTERBANK` is `SawbladesNone.chr`. Despite the name, it is used only as
  `current_saw_set = LETTERBANK` in `level_luckydraw`.
- The real menus draw pre-rendered screens with `vram_unrle`. There is no font
  because nothing ever needed one.

So `tools/gen_menufont.py` generates a 5×7 one — 40 glyphs, A–Z, 0–9 and four
symbols — as 2bpp CHR **indexed by character code**. That keeps `menu_putc` to
"write the byte", makes `$20` a real blank, and needs only two CGRAM entries since
the font writes bitplane 0 only.

### 3.2 The menu

`level_select()` in `shim/src/snes_main_full.c`. 22 rows visible, scrolls to cover
all 46, cursor marked with `>` rather than recoloured so the menu does not depend
on whatever the last level left in CGRAM. It uploads its font, draws, and puts the
level tileset back before handing over. Everything is written in forced blank, so
none of it touches the vblank queue.

`tools/verify_menu.lua` reads the **tilemap** back and decodes it as text — the
font is indexed by character code, so a tile index is its ASCII value — and checks
it against `out/menu_expect.txt`, which `gen_levels.py` writes from the level set.
It also walks to the last level, so the scroll is covered and not just the first
screen.

---

## 4. Harness lessons

Seven of this milestone's bugs were in the test harness, not in the port, and each
one reported a clean pass or a plausible failure while measuring the wrong thing.
Two of them - a byte-exact check that existed for one level out of forty-six, and
a per-level check that only asked whether anything was drawn - are why section 1.1
happened at all.
They are traps 89–93 and 95–97 in [HANDOFF.md](HANDOFF.md): a stale report read as
a pass, a poked gamemode drawing correctly off screen, static functions missing
from the symbol table so the profilers hooked nothing, a hand-written
`addrs_full.lua` gone stale, emulator input needing a duty cycle rather than a
tap, a byte-exact check that covered one level, a 64-column window where only 63
slots are readable, and a menu poke that could land before the menu existed and
silently test level 0 instead.

The one worth repeating here: **a verifier that fails to start leaves the previous
run's `out/*.txt` in place.** Every `verify_*.lua` writes its verdict to a file and
prints little, so `tail out/gamemode_sprites.txt` after a run that never happened
reports the previous run's pass. `tools/verify_all.sh` deletes each report before
its run and treats a missing one as a failure.

---

## 5. Where things stand

```
sh tools/build_game.sh      # asset gen -> C -> link -> HiROM image -> layout check
sh tools/verify_all.sh      # every verifier, one line each
```

```
rom layout               RESULT: ROM LAYOUT OK
verify_render            RESULT: LEVEL RENDERED
verify_sprite_chr        RESULT: SPRITE CHR CORRECT, AND BANK SWITCHING WORKS
verify_gamemode_sprites  RESULT: EVERY GAMEMODE DRAWS ITS OWN SPRITES
verify_cube_spin         RESULT: SPIN RATE MATCHES THE PHYSICS TABLE
verify_framerate         RESULT: HOLDS 60Hz
verify_level_boot        RESULT: ALL 46 LEVELS LOAD AND STREAM
verify_menu              RESULT: MENU OK (44 names verified)
ALL VERIFIERS PASSED
```

`verify_level_boot` is 46 emulator runs and each one now compares the whole
inflated level and 63 tilemap columns against the oracle, so this is the check
that actually says the port is correct rather than that it is running.

`out/famidash-snes-full.sfc` is 589,824 bytes, HiROM banks `$C0`–`$C8`.

Still open, unchanged from M2.15: 16×16 OBJ mode, the four 1KB CHR registers
(background tilesets), parallax as a scroll register, vertical row streaming, and
audio.
