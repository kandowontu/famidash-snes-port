# M2.12 — the level sprites

Coins, orbs, pads, portals and decorations draw, with their own art, at 60Hz.

Before this: the level sprite engine existed but the objects on screen were
garbage tiles and the game ran at roughly half speed wherever they appeared.
Four separate faults, and only one of them was in the sprite engine.

---

## Result

| | before | after |
|---|---|---|
| speed, gameplay overall | 84–86% of 60Hz | **97.4%** |
| speed, sprite-dense stretch | 22–58% | 88–100% |
| largest metasprite emitted in one call | **7161 sprites** | 2 |
| hardware sprites the shim could write | **8** | 128 |
| OBJ tiles uploaded | 64 of 256 | 256 of 256, byte-verified |
| active sprite slots, typical frame | 0 (1802 frames of 2000) | 4–20 |

```bash
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_sprite_chr.lua
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_framerate.lua
cat out/sprite_chr_verify.txt out/framerate.txt
```

`verify_framerate.lua` still reports `DROPPING FRAMES`: it asks for 98% overall
and 90% in every 300-frame window, and the worst window is 88.3%. That is
deliberate — the bar is where "no visible lag" is, not where the current build
lands. See [what is left](#what-is-left).

---

## The four faults

### 1. Nothing was uploading the sprite art — the "missingno"

Only `bankicon00.chr` reached VRAM: 1KB, 64 tiles, OBJ tiles 256–319. Every
level object names a tile above that, so it drew whatever VRAM happened to hold.

The layout, which had to be read out of `crt0.s` rather than guessed. Every
sprite tile byte in `SAUCE/defines/sprites.h` is **odd** — bit 0 set — so every
sprite is in NES pattern table 1, `$1000-$1FFF`. MMC3 is in **CHR mode B**
(`initialize_mapper` sets `MMC3_REG_SEL_CHR_MODE_B`), so A12 is inverted and
that 4KB is the two 2KB registers, which `GAMECHR` pairs up as four 1KB files:

```
$1000  bankicon00.chr    the player icon     -> OBJ tiles 256-319
$1400  bankportals.chr   portals             -> OBJ tiles 320-383
$1800  bankmain.chr      orbs, pads, coins   -> OBJ tiles 384-447
$1C00  bankblank.chr     decorations         -> OBJ tiles 448-511
```

All four now convert to 4bpp and upload as one 8KB block at VRAM word `$3000`.
`verify_sprite_chr.lua` compares VRAM against `out/spr.tiles.bin` byte for byte
— 8192/8192 — because a screenshot cannot tell wrong art from unwritten VRAM.

The game bank-switches the icon and the decoration half per frame
(`state_game.h` alternates `current_deco_type` and `+2` every frame). This
takes one static set. Per-level icons and the decoration animation need the
switch, and there is room: OBJ tiles 0–255 are unused, since NES pattern table 0
holds background CHR and no sprite ever indexes it.

### 2. `viseffects` was 0, so the game deleted its own decorations

Measured before touching anything: **0 active sprite slots in 1802 frames of
2000.** The engine was loading the stream correctly and something was retiring
every object the frame it came on screen.

`sprite_collide`, in `sprite_loading.h`:

```c
case DECO:
    if (twoplayer || !viseffects) activesprites_type[index] = 0xFF;
    continue;
```

This port boots straight into `STATE_GAME`, so `setdefaultoptions()` — which
also pokes SRAM and the MMC3 IRQ table — never runs, and every option keeps its
BSS zero. That is not a neutral default. Most of Stereo Madness's sprite stream
is decorations.

`snes_main_full.c` now sets the options `setdefaultoptions()` sets to something
other than zero: `viseffects`, `auto_practicepoints`, and `icon_colors[0..2]`
(which is what `color1`/`color2`/`color3` are `#define`d to).

### 3. A cc65 struct layout, walked as bytes — the runaway metasprite

The expensive one, and the reason "extreme lag" and "missingno" were the same
bug in one of its two symptoms.

Animated sprites index a table of

```c
struct SpriteFrame { uint8_t frame_count; const uint8_t *ptr; };
```

On cc65 that is **three bytes** with the pointer at offset 1, because the NES
address space is 16-bit — so `draw_sprites.h` steps `frame * 3` and reads
`[1]` and `[2]`. Here a pointer is **four bytes** and the struct is padded, so a
stride of 3 and an offset of 1 read neither field.

The result was a garbage 24-bit address handed to `oam_meta_spr`, which walks
`(dx, dy, tile, attr)` quadruplets until it reads `dx == $80`. With no
terminator where one was expected it ran until it happened to find an `$80`
byte. On the coin, type `$07`: **7161 sprites out of one call**, filling OAM
with garbage tiles and taking fifty video frames to return.

`overlay/functions/draw_sprites.h` now indexes the struct, which is correct
under either compiler and gets the bank byte for free:

```c
animation_data_ptr = (unsigned char *)anim_frames[animation_frame].ptr;
```

This is a **new shape of trap 28**, and the more dangerous one. The known form
is a raw byte table holding 16-bit addresses. This was a real C `struct` whose
*size and field offsets* differ between the two targets — the compiler builds
correct accesses if you let it, and only hand-computed strides go wrong. Anything
in `SAUCE/` that computes a struct offset arithmetically is suspect.

`meta_spr` now also bounds its walk at 64 sprites, which is NES OAM's capacity —
past that it could not have been drawn on the original either. The cause is
fixed; the bound makes the next one a glitch rather than a hang.

### 4. The shim could only ever write eight hardware sprites

```c
if (sprid > (uint8_t)(sizeof(oam_lo) - 4))
    return;
```

`oam_lo` is `#define oam_lo (oam_buf)`, so `sizeof` is 544, and `(uint8_t)540`
is **28**. The generated code was `lda ##28 / cmp long:sprid / bcc`. Eight SNES
sprites — four of which the player uses. `sprid` was a `uint8_t` byte index into
a 512-byte table as well, so even the intent could not have worked.

`sprid` is 16-bit now. Nothing in `SAUCE/` calls `oam_set`/`oam_get`, but they
keep NES units (64 sprites of 4 bytes) and convert, since one NES sprite is two
SNES ones here.

---

## Where the frame went

Measured with `tools/profile_gameplay.lua`, which hooks the entry of every
per-frame function and logs the scanline. One NTSC frame is 262 scanlines and
vblank is 225–261.

| | before | after | |
|---|---|---|---|
| vblank flush | 38 | 20 | overran vblank; VRAM writes past it are dropped (trap 35) |
| `music_update` | 5 | 5 | |
| `sprite_collide` | 45–107 | 63–107 | game code; grew because sprites now exist |
| `check_spr_objects` | 31 | 25 | |
| `oam_clear` | **28** | **0** | |
| `draw_screen`, streaming frames | **98** | **37** | |
| `draw_sprites` | 140 | 88–107 | |
| `trail_loop` | — | 12–19 | new: `viseffects` enables it |

### `cgram_flush` was 27 of vblank's 37 scanlines

Every frame, because the game sets `PAL_UPDATE` every frame. 32 colours written
a byte at a time to `CGDATA`. It pushed the column and OAM transfers past the end
of vblank, where VRAM writes are silently dropped.

Now five DMAs: one for the 16 background colours, then one per sprite palette,
because NES palette *p* maps onto the first four entries of OBJ palette *p* and
the destination jumps 16 CGRAM entries between runs while the source is
contiguous. 27 scanlines → 8.

This is trap 36 again — *a C loop cannot fill vblank's budget* — in the one place
it had not been applied.

### `oam_clear` was hiding 128 sprites that were about to be overwritten

It now only resets the cursor. `oam_flush` hides the entries used last frame and
not reused this one — usually a handful. Same result on screen.

That needs a real full clear somewhere, so `oam_init()` does it once from the
boot path. Without it the shadow buffer's power-on state is what gets DMA'd:
128 sprites at Y=0 naming tile 0.

### `draw_screen` cost 98 scanlines on the frames it streamed a column

Two causes, both address arithmetic:

- `collMap[p][(r << 4) | slot] = src[p * COLL_ROWS + r]` compiles to a multiply,
  two shifts and two long-indexed accesses **per byte**, ~350 cycles each for 63
  bytes. Both walks are exactly linear, so they are two walking pointers now.
- `level_column_banks[rld_column / level_columns_per_bank]` and its `%` are two
  16-bit **software divisions** per column — the divisor is an extern, so nothing
  folds them. The cursor only moves forward one column at a time, so the offset
  and part index are carried alongside it and the division happens once per level
  restart instead. `rld_off` is `uint16_t` on purpose: a bank part is exactly
  65536 bytes, so the offset wrapping to 0 *is* the carry into the next part.

### `oam_spr` is now assembly

It is the innermost loop of the port: a busy frame reaches it about twenty times,
and it measured at **4.2 scanlines a call** — 76 of `draw_sprites`' 127, out of
262. Restructuring the C got it to 3.2 and no further.

The cost was never the work, which is eight byte stores. It is the shape Calypsi
has to generate: every 8-bit value handled in 16-bit registers with `sep`/`rep`
either side, every operand re-fetched from a stack slot, and the OAM index
recomputed for each store. `shim/src/oam_spr.s` is about 90 cycles against about
950, and its header documents the calling convention it implements — taken from
the compiler's own output for the same function, not from a manual:

> first argument in A, the rest pushed by the caller as 16-bit words right to
> left, `jsl` so 1,s..3,s is the return address, caller pops.

**It was verified, not assumed.** `tools/verify_oam.lua` checksums the whole OAM
table at fixed **game** frames — not video frames, since the change is that
frames take a different amount of time — over a forced run with identical input.
The assembly version is byte-identical to the C version at every sample, and
stayed identical through the `meta_spr` rewrite that followed.

---

## What is left

The remaining drops are ~20 scanlines of overrun on the densest frames, and they
are now dominated by **game code, not the shim**:

```
frame 1642: 530 scanlines  <-- DROPPED A FRAME
  music_update 5 | sprite_collide 107 | check_spr_objects 31 | oam_clear 0
  | draw_screen 3 | draw_sprites 88 | trail_loop 13 | ppu_wait_nmi 283
```

`sprite_collide` at 63–107 scanlines is the single largest item in the frame, and
`draw_sprites`' per-slot animation logic is most of what is left in `draw_sprites`
now that `oam_spr` is cheap. Both are ports of `SAUCE/`, and `overlay/` carries
ports and compiler workarounds — not rewrites — so the next move there needs a
decision, not just an edit.

The cheaper remaining lever is `meta_spr`, which is still C at roughly 3 scanlines
per sprite and is shim code. `oam_spr.s` is the worked example and
`verify_oam.lua` is the harness that makes such a change checkable.

Also still open, and unchanged by this work:

- **One static CHR set.** Per-level icons and the decoration animation need the
  bank switch the NES does per frame. OBJ tiles 0–255 are free for it.
- `bank_spr()` is recorded and ignored; nothing in the gameplay path uses it.
- `drawplayertwo` is still empty, and the non-cube gamemodes fall back to the
  cube arm.
