# M2.13 — the player sprite, every gamemode, and the seam

Four reported faults, four different causes, none of them where the previous
handoff predicted.

| reported | cause | |
|---|---|---|
| "the cube needs to be reconstructed" | a flip mirrored the attribute bits but not the metasprite's offsets | fixed |
| "ship mode is not changing to ship sprites" | `drawplayerone` had only the cube arm; no gamemode dispatch | fixed |
| "a seam about 1/4 of the way down the screen" | BG1HOFS written mid-frame — a scroll tear, not a tilemap fault | fixed |
| "heavy lag around sprite-heavy areas, especially ship transitions" | `meta_spr` and the collision-column copy | 96.6% → **98.9%** of 60Hz |

```bash
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_gamemode_sprites.lua
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_framerate.lua
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\dump_bg.lua
python tools/verify_bg.py
```

---

## 1. The cube: a flip has to mirror the offsets

`oam_meta_spr_flipped` XORed the flip bits into each sprite's attribute and left
the sprites where they were. That mirrors each 8x16 sprite about **its own**
centre, so a 16x16 metasprite came out as four quadrants each turned inside out
— the cube looked like a square pulled apart into corners with a cross-shaped
hole through it.

`__oam_meta_spr_flipped` in `nesdash.s` does the arithmetic in 8 bits with the
carry:

```
H:  EOR #$FF / ADC #($100-8) / SEC   then + x   ->   x - dx - 8
V:  EOR #$FF /                 SEC   then + y   ->   y - dy
```

The `-8` is the sprite's own width. There is deliberately **no** `-16` on the
vertical: the original has that adjustment written out and commented off,
because 8x16 mode already accounts for the height.

Reconstructing `Cube_3` from `bankicon00.chr` by hand — applying the pattern
table, the 8x16 tile pair, and both flips — was what settled it. A renderer that
swaps the tile pair without also mirroring the rows *inside* each tile produces
two disjoint halves and looks exactly like a bug in the thing under test; that
cost a detour.

`verify_gamemode_sprites.lua` now guards this. Positions alone cannot catch it —
the sprites are at the same two x values either way — but the **order** can:
mirroring `dx` means the sprite emitted first is the one that was rightmost in
the source data. The check asserts that the first OAM entry's x is greater than
the last's exactly when the H flip bit is set.

## 2. Every gamemode now draws its own sprites

`drawplayerone` implemented the cube arm and every other gamemode fell back to
it, so the ship portal changed the physics and nothing else.

`sprite_table_table_lo/hi` in `nesdash.s` is now a table of pointers-to-tables,
four rows of twelve — normal, mini, retro-normal, retro-mini — indexed by
`mini*12 + gamemode (+24 retro)`, with a per-gamemode arm for the frame index:

- **ship / swing** — the tilt is `0x0400 - vel_y` clamped to `0..0x07FF`, frame
  = its high byte, mirrored when gravity is inverted.
- **wave / snake** — the same, plus the "speed above x3 comes out mirrored" fix
  the original carries.
- **ball**, **ufo**, **pogo** — counters and velocity sign.
- **robot**, **spider** — walk cycles, with the jump frames handled below.

Gravity flips the sprite for every gamemode **except** the cube, whose arm
*overwrites* the flip byte from its own rotation table rather than OR-ing into
it (`STA xargs+0`, not `ORA`).

### The jump tables are read out of bounds on the NES

`ROBOT_JUMP[x]` is spelled `ROBOT[x + 20]` — the original indexes past the end
of the walk table and lands in the jump table because cc65 happens to lay the
two arrays out adjacently. `ROBOT` and `SPIDER` really do have their jump frames
appended so those stay in range; `MINI_ROBOT` and `MINI_SPIDER` do not, and
nothing guarantees the adjacency here. The port names the jump tables and
indexes them properly.

### Verified against sprites.h, not against the shim

`tools/gen_gamemode_expect.py` parses `SAUCE/defines/sprites.h` and works out
which OBJ tiles each gamemode's table can possibly name — resolving the
metasprites, the 8x16 tile pairs and the pattern-table bit itself.
`verify_gamemode_sprites.lua` pokes each gamemode in turn and checks what OAM
actually gets. All twelve pass.

Reaching the ship portal from a scripted run is not reliable — it depends on the
exact jump trajectory — so the check pokes `gamemode` directly. That tests the
dispatch, which is the part that was missing.

### Still only one CHR set

Ship and UFO share the icon bank with the cube (`set_player_banks`:
`iconbank3`), so they draw correctly today. Ball, robot and spider come from
`bankgamemodesA`, and wave, swing, snake and pogo from `bankgamemodesB` — the
NES bank-switches those in per gamemode and this port uploads one static set, so
those four draw the right *tile numbers* against the wrong *art*. OBJ tiles
0–255 are free for it: nothing indexes NES pattern table 0.

## 3. The seam was a scroll tear

The previous handoff's hypothesis was the 64x64 map's SC0/SC1 → SC2/SC3
boundary at tile row 32. It was not that, and `verify_render.lua` could never
have found it: that check derives its VRAM addresses the same way
`column_flush()` does, so the two agree whatever either does (trap 61).

`tools/verify_bg.py` is the independent oracle the handoff asked for. It takes
the tilemap **out of VRAM**, arranges it into a 64x64 grid using the SNES's own
screen layout, and renders it through the software PPU in `snes_m0.py` — the one
that matched Mesen 57344/57344 on the static ROM.

It found the band immediately, and the decisive detail was that its lower edge
sat on a **screen line**, not on a tilemap row: identical tilemap content
rendered correctly above line 42 and incorrectly below it. That is a register
changing part-way down the frame, not an addressing fault.

Sweeping the horizontal scroll confirmed it: the top of the screen matched
`hscroll - 2` and the bottom matched `hscroll`, switching at line 42. Exactly one
frame of camera movement.

The game calls `scroll()` from `do_the_scroll_thing`, in the middle of its
frame, and the SNES applies BG1HOFS the instant it is written. The NES never had
this problem — neslib's `scroll()` only stores into `SCROLL_X`/`SCROLL_Y` and
its NMI handler writes `$2005` at the top of vblank. `set_scroll_x/y` now latch,
and `ppu_wait_nmi()` applies, which is the same policy the VRAM queue already
had and for the same reason.

### The check is "one scroll value for the whole screen"

Not "this exact scroll value". However carefully the frames are paired, the
register read and the captured frame are a little out of step — and now
deliberately so, since the write moved into vblank. So `verify_bg.py` renders a
range of offsets, asks which ones each screen line agrees with, and requires
that **some single offset explains every line**. A tear is precisely the failure
of that, and the tool reports it separately from "no offset explains these
lines", which is the harness giving up rather than a fault in the ROM.

Across 18 sample frames spanning the level: **0 tears**, 12 confirmed clean, 6
inconclusive. The inconclusive ones are trap 1 — Mesen's `--testrunner`
captures are not frame-deterministic, so the screenshot occasionally lands a
frame away from the state dump by more than the sweep covers — plus CGRAM skew
when a frame falls on a colour trigger. Both are limits of the harness, not
results; the same 18 frames before the fix showed the two-band structure every
time, with the split measured at screen line 42 and the band above matching
`hscroll - 2` exactly.

## 4. The lag

| | before | after |
|---|---|---|
| overall | 96.6% of 60Hz | **98.9%** |
| worst 300-frame window | 86.0% | **93.3%** |

**`meta_spr` is now assembly** (`shim/src/oam_spr.s`), for the same reason
`oam_spr` already was: about 3 scanlines *per sprite* in C, roughly half of
`draw_sprites`. A portal is 9 sprites in one metasprite — the largest object in
the game — which is why the lag was worst around gamemode transitions.

Its arguments come through globals rather than the calling convention. That is
the interesting part: `oam_spr` can rely on Calypsi's convention because its
arguments are all scalars in A and on the stack, but `meta_spr` takes a
**pointer**, and Calypsi passes pointer arguments in its direct-page
pseudo-registers (`_Dp`) — compiler scratch, not an interface. The C wrappers
cost a few dozen cycles per metasprite instead of per sprite.

Its own scratch is in a `ztiny` section, which `src/snes-HiROM.scm` already
routes into the DirectPage memory — no linker change. It needs direct page at
all because `[dp],y` is the only addressing mode that reads through a 24-bit
pointer, and metasprite data is in ROM banks `$C0-$C2`.

**The collision-column copy went from 37 scanlines to 14**, in C. The 15 rows of
a page are written long-hand with constant offsets from one base pointer rather
than as an inner loop: Calypsi spent more on the pointer add and the loop test
than on the copy itself. That was the difference between the marginal frames
fitting and not.

### What is left

The remaining drops are `sprite_collide` at 63–101 scanlines of 262 — the
game's own object-collision pass, in `overlay/functions/sprite_loading.h` — plus
the per-slot animation logic in `draw_sprites.h`. Both are ports of `SAUCE/`,
and `overlay/` carries ports and compiler workarounds rather than rewrites, so
the next move there is a decision rather than an edit.

The structural answer, and the one worth taking before micro-optimising further,
is **16x16 OBJ mode**. Today one 16x16 metasprite is four SNES 8x8 sprites; in
16x16 mode it would be one — a quarter of the OAM entries, a quarter of the
`oam_spr` calls, and a quarter of the per-scanline sprite load. It needs the
sprite CHR repacked so each object's four tiles sit in the 2x2 arrangement the
SNES expects (`n`, `n+1`, `n+16`, `n+17`), which is a change to
`nes_chr_to_snes_4bpp` and a tile-number mapping, plus the size bit in OAM's
high table and OBSEL's size field. That is the "reconstruct the cube" work in
its larger sense, and it is the right next step for the sprite path.
