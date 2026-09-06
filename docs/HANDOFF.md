# Handoff

> **New session? Read `docs/HANDOFF_NEXT.md` first.** It is the current state
> of the port and the queued work; this file is the trap list it refers to.


Read this first if you are picking this project up cold. It is written to be self-contained:
what exists, what is proven, what the next task is, and which traps have already cost time.

---

## 1. What this is

Porting [Famidash](https://github.com/tfdsoft/famidash) — a Geometry Dash demake for the NES
(cc65 / MMC3) — to the SNES.

**Strategy: shim, not rewrite.** Reimplement `LIB/` (neslib / nesdoug / nesdash / mapper) on
SNES hardware *keeping the same function signatures*, so `SAUCE/` (~17k lines of gameplay)
and all 35MB of level data compile against either backend. One tree, two backends.

The full design doc is [SNES_PORT_SCOPE.md](SNES_PORT_SCOPE.md). The thesis has held up so
far: the gameplay core compiles for 65816 with **three** ported files.

### Repo boundaries — important

- This repo is `C:\famidash-snes-port`. It holds **only** SNES-side work.
- The game repo is `C:\famidash`, referenced via `--root`, and is **read-only**. Nothing here
  writes to it.
- Ported game files live in `overlay/`, which shadows `SAUCE/` on the include path. That is
  how the game repo stays untouched.
- `C:\famidash` may be a stale checkout. Pass `--root` explicitly if the live one is
  elsewhere.

---

## 2. State

| Milestone | State |
|---|---|
| M0 — asset pipeline | done, validated ([M0_RESULTS.md](M0_RESULTS.md)) |
| M1.1 — display-only ROM | done, pixel-exact vs Mesen2 ([M1_PROGRESS.md](M1_PROGRESS.md)) |
| M1.2 — column streaming + scroll | done, 11264/11264 tilemap words verified |
| M1.3 — C toolchain + shim headers | done, gameplay core → 65816 object code ([M1_TOOLCHAIN.md](M1_TOOLCHAIN.md)) |
| M1.4 — shim impl + linked ROM | done — real physics, cube falls / lands / rests / jumps ([M1_4_LINKED_ROM.md](M1_4_LINKED_ROM.md)) |
| M1.5 — all gameplay code compiles | done — `functions/`, `gamemodes/`, `gamestates/` build clean for 65816 ([M1_5_FULL_PORT.md](M1_5_FULL_PORT.md)) |
| M1.6 — the game links and runs its loop | done — 0 undefined symbols; boots and runs `state_game()` ([M1_6_LINKED_GAME.md](M1_6_LINKED_GAME.md)) |
| M2.1 — level renders | done — tilemap byte-exact, 8160 words, 0 wrong ([M2_LEVEL_RENDER.md](M2_LEVEL_RENDER.md)) |
| M2.2 — collision streaming | done — window refills as the camera moves ([M2_LEVEL_RENDER.md](M2_LEVEL_RENDER.md)) |
| M2.3 — ground layer | done — floor reaches the collision map, player meets it ([M2_LEVEL_RENDER.md](M2_LEVEL_RENDER.md)) |
| M2.4 — level header | done — player spawns correctly and stands on the ground ([M2_LEVEL_RENDER.md](M2_LEVEL_RENDER.md)) |
| M2.5 — 64x64 map + ground tiles | done — 14592 tilemap words, 0 wrong; ground renders ([M2_LEVEL_RENDER.md](M2_LEVEL_RENDER.md)) |
| M2.6 — player sprite | done — cube arm of `drawplayerone` ported |
| M2.7 — sprite CHR | done — 2bpp→4bpp, 8×16→two 8×8, per-palette OBJ mapping |
| M2.8 — player position | done — an 8-bit compare was compiling as signed (trap 56) |
| M2.9 — controller input | done — pads polled in vblank; **the cube jumps on A/B/Up** |
| M2.10 — camera scrolls up | done — trap 56 again, in `sub_scroll_y` ([M2_LEVEL_RENDER.md](M2_LEVEL_RENDER.md)) |
| M2.11 — the screen seam | done — it was a scroll TEAR, not the tilemap: BG1HOFS written mid-frame ([M2_13_PLAYER_AND_TEAR.md](M2_13_PLAYER_AND_TEAR.md)) |
| M2.12 — level sprites | done — coins, orbs, pads, portals and decorations draw ([M2_12_LEVEL_SPRITES.md](M2_12_LEVEL_SPRITES.md)) |
| M2.13 — player sprite, all gamemodes, tear | done — cube reconstructs, every gamemode draws its own sprites, no tear ([M2_13_PLAYER_AND_TEAR.md](M2_13_PLAYER_AND_TEAR.md)) |
| M2.14 — spin rate + switchable sprite CHR | done — cube spins at CUBE_GRAVITY, all 12 gamemodes draw their own ART, 99.1% of 60Hz ([M2_14_CHR_BANKING.md](M2_14_CHR_BANKING.md)) |
| M2.15 — the sprite budget | done — **holds 60Hz**; worst 300-frame window 99.7% ([M2_15_SPRITE_BUDGET.md](M2_15_SPRITE_BUDGET.md)) |
| M2.16 — all 46 levels, level select, FastROM | done — every level loads and streams; every level byte-exact against an offline oracle; menu lists and starts all 46; **holds 60Hz** (99.8-100.0%, worst window 99.3%) ([M2_16_LEVELS_AND_MENU.md](M2_16_LEVELS_AND_MENU.md)) |
| M2.17 — per-level tilesets and colours | done — 36 of 46 levels were drawing the right shapes from the wrong art; frame rate measured on ALL levels ([M2_17_TILESETS.md](M2_17_TILESETS.md)) |
| M2.20 — the scroll caps, and the ball | done — `cap_scroll_y_at_top/bottom` were clamping scroll_y and nothing else; the originals also take the discarded scroll back out of the players. **The ball rests on the floor instead of bouncing** (traps 102-103, `tools/verify_ball.lua`) ([M2_20_SCROLL_CAPS_AND_WAVE.md](M2_20_SCROLL_CAPS_AND_WAVE.md)) |
| M2.21 — the wave moves | done — a second Calypsi merge defect made `currplayer_vel_y` a constant **+1** for the whole wave gamemode. `tools/scan_merge_tya.py` catches the shape and runs in the build; the wave's tilt clamp is now reachable and checked (traps 105-106) ([M2_20_SCROLL_CAPS_AND_WAVE.md](M2_20_SCROLL_CAPS_AND_WAVE.md)) |
| M2.22 — the whole level set, and the lag measured against the NES | done — all 168 levels of `lvlset_HUGE`; a Calypsi switch helper was the per-sprite cost the NES does not pay. 51 levels hold 99%+ of 60Hz, 72 are below 95% ([M2_22_SPRITE_COST.md](M2_22_SPRITE_COST.md)) |
| M2.23 — 16x16 OBJ mode | built, measured, **retired** — it works and removes 22% of OAM entries, and that is worth ~3% of the walker because OAM entries are a PPU resource, not CPU time ([M2_23_OBJ16.md](M2_23_OBJ16.md)) |
| M2.24 — why the port is 2x the NES | done — measured: the port executes **2x** the NES's instructions for the same work and **25% of them are `rep`/`sep` width switches**. The SNES is not the constraint ([M2_24_WHY_2X.md](M2_24_WHY_2X.md)) |
| M2.25 — hand-write the hot routines | **next** — `shim_meta_run`, `draw_sprites`, `check_spr_objects`, `sprite_collide` are 80% of the frame; in assembly the accumulator width is a choice rather than a consequence |
| M2.26 — `near`/direct-page data | the game's data is ~7KB once the three big shim buffers are `__far`, which fits bank 0 |
| M2.27 — `xmaschallenge` | 23.4% of 60Hz, not reloading, unrelated to the sprite work. The worst level in the set by a wide margin |
| M2.28 — vertical row streaming | the tilemap shows the bottom 64 tile rows, so a taller level's upper rows are never drawn |
| M3–M5 | not started |

Two ROMs:

```
out/famidash-snes-game.sfc    64KB   physics core     WORKS - falls, lands, jumps
out/famidash-snes-full.sfc   512KB   the whole game   PLAYABLE - runs, jumps, dies on spikes
```

**Stereo Madness is playable, with a controller.** The cube spawns where the header says,
stands on the ground, runs forward, rotates as it moves, **jumps when you press A/B/Up**, and
dies on the first spike. Level, ground, player and **the level's own sprites — coins, orbs,
pads, portals, decorations — all render**, at a measured **100.0% of 60Hz**, with no tear.

All twelve gamemodes draw their own sprite table AND their own art — the sprite CHR is
bank-switched, as on the NES. The cube spins at the rate its own physics table specifies.
The camera follows the player up and stops at the top of the level.

**Known gaps**, none of them a wrong picture:

- The sprite budget runs out at about **12 simultaneously active objects** (~29 NES sprites).
  Stereo Madness peaks at 19 and holds 60Hz throughout; a denser level would not. Measured
  with `tools/stress_sprites.lua` — see [M2_15_SPRITE_BUDGET.md](M2_15_SPRITE_BUDGET.md).
- The four 1KB CHR registers — background tilesets — are still no-ops. Correct only while one
  tileset is loaded, which is the case for this level.
- Parallax is deliberately not implemented as CHR banking; it wants one BG layer and a scroll
  register.
- Thirteen icon banks and the contest icons are not carried: they need the customise menu,
  which is not ported, so `icon` cannot change.

See [M2_13_PLAYER_AND_TEAR.md](M2_13_PLAYER_AND_TEAR.md),
[M2_14_CHR_BANKING.md](M2_14_CHR_BANKING.md) and
[M2_15_SPRITE_BUDGET.md](M2_15_SPRITE_BUDGET.md). Section 3.

Two more build from clean, from assembly only — they are the reference implementations the
C shim was written against:

```
out/famidash-snes-main.sfc     32KB LoROM   static level screen
out/famidash-snes-scroll.sfc  256KB LoROM   scrolls the whole level
```

### Verified facts

These are measured, not assumed. Do not re-derive them.

- **LZ + RLE level decoders**: 454/454 level files across every level set decode and
  round-trip byte-exact against the game's own `aart_lz.compress()`.
- **CHR conversion**: NES 2bpp → SNES 2bpp is a pure byte interleave; round-trips losslessly.
- **CHR bank numbering**: `space_defines.h` numbers are 1KB units; bank *N* is ROM offset
  *N*×1024. Verified against the built NES ROM for 8/9 tilesets (the 9th, `slopesA.chr`, is
  newer than the reference ROM — the ROM is stale, not the tool).
- **Parallax**: 144 *distinct* 1KB pre-shifted CHR banks = 144KB, ROM-verified. Collapses to
  one BG layer + a scroll register on SNES. The same pre-shift trick also doubles every
  tileset (`SpikesA.chr` is 2KB holding two 1-pixel phases of the sky dither).
- **`metatiles_coll`**: the generated 256-byte collision table is byte-identical to the one in
  the shipping NES ROM (found at file offset `0x1FDB74`).
- **Software SNES PPU** in `tools/snes_m0.py` matches Mesen2 exactly (57344/57344 pixels) for
  a static frame.
- **Cube physics matches the game's own tables.** At `currplayer_table_idx = 4`: `vel_y`
  steps by exactly `CUBE_GRAVITY[4]` = 107, oscillates ±107 around
  `CUBE_MAX_FALLSPEED[4]` = 1536, and a jump peaks at exactly `JUMP_VEL[4]` = −1424 for a
  34.3px apex. `framerate = 1` is the 60Hz set — index 4's 1536×60 equals index 0's 1843×50.

---

## 3. The immediate next task

**First, finish the `LIB/asm` audit that trap 102 opened.** `cap_scroll_y_at_top/bottom`
were implemented from their header comment rather than from their 6502 body, and quietly
left out half of what they do. Every other shim function ported from `LIB/asm/nesdash.s`
and `nesdoug.s` deserves the same read-the-assembly pass, especially anything that touches
`currplayer_y`, `player_y[]`, `scroll_y_subpx` or the physics tables. `add_scroll_y`,
`sub_scroll_y`, `sub_scroll_y_ext`, `calculate_linear_scroll_y` and
`update_currplayer_table_idx` have now been checked line by line against the originals and
match.

**The sprite path's next step is 16x16 OBJ mode.** Today one 16x16 metasprite is four SNES
8x8 sprites; in 16x16 mode it would be **one** — a quarter of the OAM entries, a quarter of
the `oam_spr` calls, and a quarter of the per-scanline sprite load. It needs the sprite CHR
repacked so each object's four tiles sit in the 2x2 arrangement the SNES expects (`n`, `n+1`,
`n+16`, `n+17`), which is a change to `nes_chr_to_snes_4bpp` plus a tile-number mapping, the
size bit in OAM's high table, and OBSEL's size field. `tools/verify_oam.lua` is the harness
that makes it checkable; `shim/src/oam_spr.s` is where it lands.

OBJ tiles 0-255 are free for it, because nothing indexes NES pattern table 0.

**Then M2.15 — vertical row streaming** for the 45 levels taller than 29 metatile rows.

**And the 1KB CHR registers** — the background tilesets — which are the same mechanism as the
sprite banking in [M2_14_CHR_BANKING.md](M2_14_CHR_BANKING.md) pointed at BG VRAM, and needed
by any level that switches spike or block sets partway through.

### The sprite budget, measured

The level holds 60Hz, but `tools/stress_sprites.lua` puts the cliff at about **12
simultaneously active objects** (~29 NES sprites) — Stereo Madness peaks at 19. At that load
a frame needs ~299 scanlines of the 262 it has: `sprite_collide` 95, `draw_sprites` 116
(roughly 47 shim / 69 game), `check_spr_objects` 25, the vblank flush ~20.

16x16 mode halves the shim's 47 and would push the cliff to nearer 20 objects. Past that the
cost is `sprite_collide` and `draw_sprites.h`'s per-slot loop, both ports of `SAUCE/` — and
`overlay/` carries ports and compiler workarounds rather than rewrites, so that is a decision
to take deliberately, not an edit. Full numbers and the tile mapping 16x16 needs are in
[M2_15_SPRITE_BUDGET.md](M2_15_SPRITE_BUDGET.md).

### Settled: trap 28 does NOT apply to the sprite tables — but struct LAYOUT does

`Metasprites[]` and the per-gamemode sprite tables are real C pointer arrays
(`const unsigned char * const []`), so Calypsi builds proper 24-bit pointers for them and
there is nothing to decide. The trap is only about **raw byte tables holding 16-bit
addresses**.

The dangerous relative of it, found in M2.12 and now trap 62, is **hand-computed struct
strides**. `animation_frame_list[]` points at `struct SpriteFrame { uint8_t; const uint8_t
*; }` — three bytes on cc65, padded and larger here — and `draw_sprites.h` stepped it by 3
and read the pointer at offset 1. Both are cc65 facts, not data facts. Fixed by indexing the
struct.

The original warning, still true for the narrow case:

**The game's tables hold 16-bit pointers** (trap 28). `void *` is 4 bytes under this memory
model but the game's `uintptr_t` is 2, because the NES address space is 16-bit. Casting a
table entry straight to a pointer silently produces a bank-0 address, and the compiler does
not warn when the entry is used as an index instead. `Metasprites[]` and the level pointer
tables have the same shape. Either keep all pointed-to data in one bank and synthesise the
bank byte, or widen the tables.

### Decide before scaling past one level

**Precomputed columns do not scale.** This level costs 128KB of ROM, taking the full ROM to
384KB. The level set has 46 levels and there are 454 level files across all sets, so the
full game needs the RLE/metatile decode at run time, as the NES does. Precomputing was
chosen because single-level gameplay is the current scope — see
[M2_LEVEL_RENDER.md](M2_LEVEL_RENDER.md). Choose deliberately rather than by default.

### Already ruled out — do not repeat

- **Room wrap.** Filling all four collision-map pages with the playfield, so the player could
  not wrap out of mapped ground, made no difference. Reverted; the emitter keeps the correct
  per-room mapping.
- **Hitbox alone.** Setting `Generic.width/height` was necessary but did not fix landing —
  the miscompilation below was underneath it.

### What the "player never lands" bug turned out to be

Worth reading before debugging anything else in this codebase: it was **the compiler**, not
the game logic or the shim. `currplayer_vel_y` stepped by a constant `-0x3900` per frame
because Calypsi dropped `tmpaccel` at a control-flow merge. Two more instances of the same
defect were then found nearby, one of them on a live landing path. See trap 8 below and
[bugreport/README.md](../bugreport/README.md).

---

## 4. Environment

| | |
|---|---|
| Game repo | `C:\famidash` (read-only, via `--root`) |
| Assembler/linker (asm ROMs) | `C:\famidash\BIN\ca65.exe`, `ld65.exe` — `--cpu 65816` |
| C toolchain | Calypsi 5.18, `C:\toolchains\calypsi\calypsi-65816-5.18` |
| Emulator | Mesen2, `C:\mesen2\Mesen.exe` (SNES + NES) |
| Python | 3.14 with Pillow |

Calypsi was downloaded as `calypsi-65816-5.18.zip` (137.9 MB) from
`github.com/hth313/Calypsi-tool-chains` release 5.18. No license key needed.

### Build

```bash
python tools/snes_m0.py --root C:\famidash --outdir out --col-start 140 --columns 16
python tools/build_rom.py --root C:\famidash --target main
python tools/build_rom.py --root C:\famidash --target scroll
sh tools/build_game.sh          # both C ROMs: the physics core and the full game
```

`build_game.sh` runs from an empty `out/` and regenerates everything it needs
(`gen_menufont.py`, `gen_assets.py`, `gen_palette.py`, `gen_levels.py`, `gen_sprchr.py`,
`gen_addrs.py`, `gen_gamemode_expect.py`) - but it consumes `snes_m0.py`'s `.bin` output, so
that line above is not optional. This is worth re-testing periodically by moving `out/`
aside: a generator that is missing from the build is invisible while the file it makes is
still lying around, and two of them were (`addrs_full.lua`, `gamemode_expect.lua`).

### Verify

```bash
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-main.sfc tools\shot.lua
sh tools/verify_all.sh                            # every check on the full game ROM
python tools/compare_rom.py                       # expect 57344/57344 exact
python tools/verify_scroll.py --root C:\famidash  # expect all tilemap words correct

# gameplay: falls, lands, rests, jumps. Exit status is the result.
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-game.sfc tools\verify_land.lua
cat out/land_verify.txt

# per-frame physics, when verify_land fails and you need to see why
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-game.sfc tools\trace_fall.lua
cat out/fall_trace.txt

# the full game: boots, streams the right columns, and responds to the pad
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_boot.lua
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_render.lua
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_input.lua
cat out/render_verify.txt out/input_verify.txt
sh tools/undef_surface.sh                         # expect 0 symbols

# sprites: the art is in VRAM, every gamemode draws its own, and it holds 60Hz
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_sprite_chr.lua
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_gamemode_sprites.lua
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_cube_spin.lua
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_framerate.lua
cat out/sprite_chr_verify.txt out/gamemode_sprites.txt out/cube_spin.txt out/framerate.txt

# the bulk data really is in the ROM (traps 37 and 38); build_game.sh runs this too
python tools/verify_rom_layout.py

# the background, against a render that shares nothing with the renderer
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\dump_bg.lua
python tools/verify_bg.py
```

`verify_gamemode_sprites.lua` needs `out/gamemode_expect.lua`:

```bash
python tools/gen_gamemode_expect.py
```

`verify_framerate.lua`'s bar is 98% overall / 90% in every 300-frame window — where "no
visible lag" is, not where the build happens to be. It passes at 98.9% / 93.3%; if a change
makes it fail, that is the check working.

`verify_bg.py` samples one frame, so run it at several. Across 18 spanning the level: 0
tears, 12 confirmed clean, 6 inconclusive. It reports "no offset explains these lines"
separately from "this is a tear" for exactly that reason — the inconclusive ones are trap 1
and CGRAM skew in the harness, both documented in the tool. **A real tear reproduces on
every frame**, which is how the original was found.

`verify_render.lua` needs `out/addrs_full.lua`. The full ROM has its own map, so it is not
built by default:

```bash
python tools/gen_addrs.py --map out/game_full.map --out out/addrs_full.lua
```

`build_game.sh` also runs `tools/scan_stackslots.py` over the generated assembly and fails
the build on a hit. That is the guard for trap 8; treat a hit as a miscompilation, not as a
scanner false positive, until you have read the surrounding assembly.

---

## 5. Traps

Every one of these cost real time. They are the main value of this document.

### Verification traps

1. **Mesen `--testrunner` screenshots are not frame-deterministic.** Two runs stopped at the
   same frame return different images depending on what else the Lua script did — adding an
   `emu.getState()` call changed the captured frame. **Never pixel-diff captures of a moving
   scene.** VRAM reads *are* deterministic and are a stricter test anyway. The static ROM is
   still pixel-verified because nothing moves.
2. **Two matching samples of a periodic system prove nothing.** "The player landed" was
   claimed off two identical trace rows that turned out to be the same phase of a repeating
   fall cycle. Widen the sample window before concluding.
3. **Delta debugging can manufacture a different bug.** Reducing the preprocessed source to
   find an ICE emptied a jump table's initializer and produced a minimal repro for an
   *unrelated* compiler bug, hiding the real cause (computed goto). Always check a reduced
   repro back against the real source.
4. **Verify only what the code promises.** A collision sweep flagged ~30 "wrong" words that
   were all the write-ahead column — not yet streamed, and not on screen.
5. **`out/game.map` was stale, and nothing regenerated it.** `build_game.sh` had no
   `--list-file`, so the map on disk was from an older manual link and every trace address
   read from it was silently wrong — producing a screenful of plausible garbage that looks
   exactly like a real bug. Fixed: the link now writes the map, and `tools/gen_addrs.py`
   turns it into `out/addrs.lua`, which the Lua scripts `dofile`. **Never hardcode a WRAM
   address in a trace script** — adding one variable reshuffles the whole `zfar` section.
6. **`emu.setInput` takes `(table, port)`** — the opposite order from `emu.getInput(port)`.
   Getting it wrong raises inside the callback, which `--testrunner` swallows, so the run
   looks like the button simply did nothing. It also only takes effect from inside an
   `inputPolled` callback, not `startFrame`.
7. **Python's `splitlines()` and text-mode reads do not agree with grep.** Calypsi's
   assembly listings contain bare CRs; universal-newline translation turns each into a line
   break. A scanner built that way reports line numbers that match nothing and, worse,
   computes the wrong function boundaries. Read bytes and split on `"\n"`.

### Calypsi traps

8. **Calypsi 5.18 silently drops a value at a control-flow merge.** A `?:` or a `switch`
   feeding one shared store can compile to a join that reads a stack slot *nothing in the
   function ever writes* — so the result is whatever the caller left on the stack: stable,
   plausible, and wrong. This is the single most expensive bug in this project so far. Three
   instances were found in `gamemode_cube.h` alone, one on a live landing path.
   **`tools/scan_stackslots.py` detects it and runs as part of `build_game.sh` — do not
   remove it.** Workaround: write the merge out long-hand so every branch does its own store.
   Details and reproducer: [../bugreport/README.md](../bugreport/README.md).
   *It does not reduce.* A standalone `out = flag ? hi : 0;` compiles correctly at every
   optimisation level, with or without a stack frame; only the full TU triggers it.
9. **An unrecognised option exits with a *usage* message, not an error.** A memory-model
   sweep appeared to show `--code-model medium` working; `medium` is not a valid code model,
   and the check was counting `error:` lines. **Always confirm the object file exists.**
   Valid: code ∈ `small|compact|large`, data ∈ `small|medium|large|huge`.
10. **Optimisation is `-O 2`, not `-O2`.** Levels are 0–2; there is no `-O 3`.
11. **Computed goto is not supported.** `&&label` / `goto *expr` ICEs the 65816 backend.
    `collision.h` used it; `overlay/functions/collision.h` rewrites it as a switch. Repro:
    `int c; int f(void){ void *p = &&a; goto *p; a: return 1; }`
12. **`int jt[] = {};`** (block-scope array, empty initializer) also ICEs — a separate bug.
13. **The linker needs a `.scm` memory description as an input file.** Calypsi ships
    `linker-rules/snes-HiROM.scm`; it is copied to `src/`.
14. **`--output-format raw` writes to `<output>.raw`**, alongside the ELF at `-o`.
15. **Tree-shaking drops the cartridge header** — nothing references it. Fixed with `.public`
    anchors plus `--root-symbol`.
16. **`cc65816 -E` writes to stdout and exits nonzero even on success.** Under `set -e` that
    aborts the script.
17. **`--assembly-source` behaves like `-S`: it SUPPRESSES the object file.** Combining it
    with `-c -o foo.o` exits 0, emits the `.s`, and silently writes no `.o` — so the link
    picks up whichever stale object was already there. This produced a ROM that passed its
    verification while not containing two of the fixes it was supposed to. `build_game.sh`
    now deletes all objects first, emits assembly in separate `-S` invocations, and asserts
    every object exists before linking. This is the same family as trap 9: **always confirm
    the object file exists.**

### SNES traps

18. **`snes-HiROM.scm` defines only the reset vector.** NMI and IRQ point at whatever sits in
    `$FFE0-$FFFB`. Enabling NMI without a handler crashes into garbage — symptom was a black
    screen with `screenBrightness = 0` and `cpu.pc = 2`. Auto-joypad read does not need NMI;
    the loop polls the vblank flag in `$4212`.
19. **OAM is 544 bytes, not 512.** The 32-byte high table holds X bit 9 and the size bit per
    sprite. Clearing only the low table leaves power-on garbage that shows up as coloured
    blobs scattered over the screen.
20. **The SNES vector table is not laid out the way it is usually written down.** Native NMI
    is `$FFEA`, native IRQ `$FFEE`, emulation RESET `$FFFC`. An intuitive ordering from
    `$FFE0` is shifted one word and boots into garbage.
21. **`BG1VOFS = -1`** puts tilemap row 0 on screen line 0. Vertical scroll has an
    off-by-one; horizontal does not.

### Codebase traps

22. **`famidash.h` *defines* its globals rather than declaring them** — it is written for a
    unity build, so it cannot be included from a second translation unit. `shim_core.c`
    declares what it needs `extern` (types are documented with source line numbers).
23. **The 240-pixel scroll wrap is not a NES artifact to remove.** `add_scroll_y` wraps the
    low byte at `0xF0` because it is a pixel offset inside a 240px "room", and the collision
    map is *addressed* in those units. It stays.
24. **20% of background tiles (47 of 235) are used under more than one palette.** A global
    tile→palette lookup does not work; palette must come from `metatiles_attr` per metatile.
25. **`get_at_addr()` is deliberately absent from the shim.** The SNES has no attribute
    table, so any surviving use should be a compile error, not a silent bad VRAM write.
26. **`sprite_loading.h` fills `Generic.width/height`.** Anything using the collision probes
    without it gets a zero-height hitbox and every probe tests the wrong row.
27. **`overlay/` files carry compiler workarounds, not just ports.** `gamemode_cube.h` has
    three long-hand rewrites that exist purely to dodge trap 8, and `state_game.h` a fourth.
    Do not "tidy" them back toward the original shape without re-reading the generated
    assembly.
28. **The game's tables hold 16-bit pointers, but a pointer here is 4 bytes.** The game's
    `uintptr_t` is 2 bytes because the NES address space is 16-bit. Casting a table entry
    straight to a pointer compiles with only a warning and silently yields a **bank-0**
    address — and there is no warning at all when the entry is used as an index. Write the
    16 bits into the low half of a pointer that already carries the right bank, as
    `overlay/functions/draw_sprites.h` does. Unresolved port-wide; see
    [M1_5_FULL_PORT.md](M1_5_FULL_PORT.md).
29. **`get_Y` is not a value — it is "the index the last array access used".** cc65 leaves it
    in Y; the shim records it in `shim_last_index` and every array macro maintains it. Three
    sites set Y with inline asm instead (`adc #0 \n tay` in `menustates/bgmtest*.c`) and the
    shim **cannot** see those — they need porting individually. Also: where one expression
    indexes twice, which index survives is unspecified, so never write `get_Y` straight after
    such a line.
30. **`shim_idx()` must stay a function, not a macro.** As a macro the assignment landed
    inside an array subscript, making `a[shim_idx(i)] = b[shim_idx(j)]` undefined behaviour
    and burying real warnings under 60 `-Wunsequenced` ones.
31. **`__asm__` is deliberately undefined in the shim**, like `get_at_addr()`. Every
    remaining site is hand-written 6502; a compile error is the point.
32. **`emu.getState()` returns a FLAT table with dotted keys** — `st["cpu.pc"]`, not
    `st.cpu.pc`. Indexing it the nested way raises inside the callback, `--testrunner`
    swallows the error, and the script looks like it simply did nothing.
33. **On HiROM, code legitimately runs at any 16-bit address in banks `$C0-$FF`.** A boot
    check that demands `pc >= $8000` reports a perfectly healthy ROM as wedged.
34. ~~**`shim_engine.c` still has three stubs.**~~ Obsolete as of M2.12: `init_sprites`,
    `check_spr_objects` and `drawplayerone` are implemented and the level's objects draw.
    `drawplayertwo` is still empty (nothing sets up player 2's state, so drawing it would put
    a stray cube on screen), and the non-cube gamemodes fall back to the cube arm.
35. **VRAM writes during active display are silently dropped.** Only forced blank and vblank
    accept them. `flush_vram_update2()` therefore writes only in forced blank and otherwise
    leaves everything queued for `ppu_wait_nmi()`. A flush that quietly did nothing is what
    made the first streaming level render come out half-wrong.
36. **A C loop cannot fill vblank's budget — big transfers must be DMA.** 64 bytes of tilemap
    column, or 544 bytes of OAM, written a byte at a time from C overrun vblank and the tail
    is lost. That looks *identical* to "the renderer computed the wrong data". Both are DMA.
37. **DMA does not carry into the bank byte.** It increments the A-bus address within a bank
    and wraps. Any block DMA'd in one go must not straddle a bank — which is why the column
    records are bank-aligned and OAM is one 544-byte buffer rather than two arrays that
    happen to sit next to each other.
38. **`--raw-multiple-memories` writes extra `.raw` files you have to collect.** A memory
    placed away from the code (the column stream at bank `$C4`) goes to its own
    `<MemoryName>.raw` and never reaches the ROM. Everything links, the map looks right, and
    the image is simply the size of the code. `pack_hirom.py --part FILE@BANK` splices it in.
39. **The linker allocates ROM in 64KB bank chunks.** A single section larger than a bank
    cannot be placed at all, whatever the memory's declared address range says.
40. **Do not infer which level column is in which map slot.** The level opens on empty sky, so
    column 0 matches dozens of others and a search locks onto the wrong one — the first
    version of `verify_render.lua` "passed" partly by accident. Read `rld_column`, the
    renderer's own cursor, from the map instead.
41. **The game draws its own `ATTEMPT n` overlay into tilemap row 15** (`level_loading.h`,
    `NTADR_C(6,15)` and `NTADR_C(20,15)`), exactly as on the NES. A tilemap check that does
    not know this reports the game's own HUD as a renderer bug.

42. **The collision window is 60 rows and the level is BOTTOM-aligned in it**, with the
    last 3 rows reserved for the ground strip. For a 27-row level the playfield lives in
    pages 2 and 3, not 0 and 1. Top-aligning it puts the floor two whole rooms from where
    `add_scroll_y()` looks — nothing warns, the player just falls through.
43. **The floor is not in the level data.** Famidash draws the ground as a separate RLE
    strip via `load_ground`; the opening run-up of Stereo Madness has no collision until
    metatile column 17. Do not conclude the level decode is broken from an empty collision
    map at the start of a level.

44. **The `.lz` level file is the RLE stream ONLY — the header is not in it.** The 13-byte
    header (spawn position, gamemode, level height, colours) lives in front of the `.incbin`
    in `all_level_data.s`. This port reads the `.lz` directly, so nothing was reading the
    header and every field it carries silently stayed 0. `tools/gen_assets.py` parses it now.
45. **`spawn_scroll_y_pos`'s high byte is not in the header.** `nesdash.s` hardcodes `$02`
    — *"no levels need this setting, at least yet"*. The shim hardcodes it for the same
    reason. Do not go looking for a header byte that does not exist.

46. **Levels are up to 57 metatile rows tall, not 27.** Stereo Madness is the shortest in
    the set; heights run 27, 32, 35, 36, 40, 47, 48, 51, 57. 57 + 3 ground rows = 60, which
    is exactly the collision window — that is the design constraint. Do not size anything
    vertical off Stereo Madness.
47. **The tilemap cannot hold a level vertically.** 60 metatile rows is 960px; the largest
    SNES tilemap (64x64) is 512px. Vertical row streaming is required, which is what the NES
    seam was for. A 64x64 map makes it rare, not unnecessary.

48. **A 64x64 tilemap is FOUR 32x32 screens**, at +0, +`$400`, +`$800`, +`$C00` words. A
    64-row column therefore needs two DMAs, not one - rows 0-31 into SC0/SC1 and rows 32-63
    into SC2/SC3.
49. **The scroll value is in collision space, not tilemap space.** The level is
    bottom-aligned in the 60-metatile-row window, so the tilemap's row 0 sits
    `level_scroll_origin` px below the collision origin - 480px for a 27-row level.
    `set_scroll_y()` must subtract it or the camera looks below the level and sees nothing.
50. **`src/scroll.s` and the C game ROM consume DIFFERENT column streams.** Changing the
    shared format in place broke `verify_scroll` (3830/7168) while every game-ROM check
    stayed green. `snes_m0.py` emits `level.cols.*` (32-row, for the assembly baseline) and
    `level.cols64.*` (64-row, ground composited, for the game) separately.

51. **NES sprites are 2bpp; SNES OBJ is always 4bpp.** Background tiles convert with a
    pure byte interleave, sprite tiles do not — they need a 4bpp form with the upper two
    bitplanes zeroed. `make_player_tile()` in `snes_main.c` is the worked example.
52. **Trap 28 does not apply to `Metasprites[]` or the sprite tables.** They are real C
    pointer arrays, so the compiler builds 24-bit pointers itself. The trap is only about
    raw byte tables holding 16-bit addresses.

53. **The game runs the NES in 8x16 sprite mode** (`PPU_CTRL` bit 5, crt0.s), and the SNES
    has no 8x16 OBJ size. One NES sprite becomes TWO stacked SNES 8x8 sprites, and the tile
    byte means something different too: bit 0 picks the pattern table, the rest is the tile
    *pair* (`chrnum & 0xFE` and +1). A vertical flip swaps which half is on top.
54. **Four NES sprite palettes map onto the first 4 entries of four SNES OBJ palettes** -
    CGRAM `128 + p*16 + c`. Converted tiles keep pixel values 0-3, so one tile can be drawn
    under any palette exactly as on the NES. The alternative - four recoloured copies of
    every sprite - is what you get if you map them densely instead.
55. **`rld_column` counts QUEUED columns, not written ones.** The DMA happens in the next
    vblank, so the newest column is legitimately still in flight and a VRAM check that
    includes it reports a renderer bug that is not there.

56. **Calypsi narrows an 8-bit comparison against a constant >= $80 to a SIGNED one.**
    `if ((uint8_t)(px - 1) >= 0xFC)` compiles to `sec / sbc #-4` then `bmi` - 0xFC becomes
    -4, so "79 >= -4" is true and the branch fires for every ordinary value. In C the operand
    promotes to int and the comparison is against 252; the generated code disagrees. This is
    a SEPARATE defect from trap 8 and `scan_stackslots.py` cannot see it - the build scanned
    clean while the player drew 80px off. **Widen the operand** (`uint16_t pxw = px;`) and the
    comparison stays unsigned: `and ##255 / cmp ##253 / bcc`.

57. **The NES polls the controllers inside neslib's NMI handler**, not from game code -
    which is why every `pad_poll()` call in `SAUCE/` is commented out. This port has no NMI
    handler, so the poll lives at the end of `ppu_wait_nmi()`. Without it `joypad1` stays
    zero forever and the player simply cannot be controlled, with nothing obviously broken to
    point at. Poll AFTER the DMAs: the SNES auto-joypad read takes ~3 scanlines from the
    start of vblank and `pad_poll()` spins until it finishes, so polling first burns the
    vblank budget the transfers need.

58. **`currplayer_*` are per-frame COPIES of `player_*[currplayer]`.** The game loads them
    at the top of the frame and stores back later, so poking `currplayer_y` from a Lua script
    to force a situation does nothing - it is overwritten before the code under test reads
    it. Poke `player_y[0]` instead.
59. **`min_scroll_y` must be set per level, and 0 is not a safe default.** It is how far up
    the camera may travel. Because `set_scroll_y()` subtracts `level_scroll_origin`, a camera
    that rises above the top of the level underflows the subtraction and `BG1VOFS` wraps to
    the bottom of the tilemap. `init_rld()` derives it from the level height.

60. **Trap 56 is not a one-off - assume it until proved otherwise.** It has now caused two
    separate user-visible bugs: the player drawn 80px left, and the camera refusing to scroll
    up (`sub_scroll_y` returning `0xFFD1` instead of `0x02D1`). Any `uint8_t` compared against
    a constant >= `$80`, or against another value that can exceed 127, is suspect. **Write
    scroll and position arithmetic with `uint16_t` locals throughout** - `add_scroll_y` and
    `sub_scroll_y` in the shim now do. `scan_stackslots.py` cannot see this defect.

61. **A verifier that mirrors the code's own formula cannot catch a wrong formula.**
    `verify_render.lua` derives its VRAM addresses the same way `column_flush()` does, so it
    reports 0 wrong even with a visible seam on screen. When a check and the code under test
    share an assumption, the check only proves they agree. `tools/snes_m0.py`'s software PPU
    is the independent oracle - it matched Mesen 57344/57344 on the static ROM.

62. **A cc65 struct is not this struct.** `struct SpriteFrame { uint8_t frame_count; const
    uint8_t *ptr; }` is THREE bytes with the pointer at offset 1 on cc65, because the NES
    address space is 16-bit. Here a pointer is 4 bytes and the struct is padded. `SAUCE/`
    walks such tables with hand-computed strides (`ptr += frame * 3`, then `ptr[1]`/`ptr[2]`),
    which read neither field. The result is a garbage 24-bit address, and if it is handed to
    something that scans for a terminator - `oam_meta_spr` walks until it reads `$80` - it
    runs until it happens to find one: **7161 sprites out of one call, fifty video frames.**
    This is a relative of trap 28 and worse, because the fix is not "add the bank byte", it
    is "index the struct and let the compiler compute the offsets". Suspect every arithmetic
    struct offset in the game's code.

63. **`setdefaultoptions()` never runs in this port, and zero is not a neutral default.**
    Booting straight into `STATE_GAME` skips it, so every game option keeps its BSS zero.
    `viseffects = 0` makes `sprite_collide`'s `DECO` arm delete every decoration sprite the
    frame it comes on screen - measured, 0 active slots in 1802 frames of 2000 - so the level
    looks empty no matter how well the sprite engine works. `snes_main_full.c` now sets the
    options that function sets to non-zero. Note `color1`/`color2`/`color3` are `#define`s
    for `icon_colors[0..2]`, so they cannot be declared `extern` under those names.

64. **`(uint8_t)(sizeof(x) - 4)` is not a bound, it is 28.** `oam_put`'s guard was
    `sprid > (uint8_t)(sizeof(oam_lo) - 4)`; `oam_lo` is a macro for a 544-byte buffer, so the
    cast truncated 540 to 28 and the whole game was capped at EIGHT hardware sprites. It
    compiles clean, and with only the player on screen it is invisible. Check the generated
    code for any bound that involves a cast: this one was `lda ##28`.

65. **A frame that ends inside vblank has not necessarily fit.** `ppu_wait_nmi` returns at
    scanline 225 and the game's next call is reached at scanline 1 of the *following* video
    frame - so a naive reading of the timeline says the frame took 29 scanlines. It took 262.
    Profile against a monotonic clock (`frames * 262 + scanline`), and be aware that a window
    picked at random may land inside `reset_level`'s own `ppu_wait_nmi` loop, where almost
    nothing runs and every frame looks comfortably fast. `tools/profile_worst.lua` times every
    game frame and prints only the slowest.

66. **Mesen's Lua names are not the ones you would guess.** `emu.memCallbackType` does not
    exist - it is `emu.callbackType`, with `.exec`, `.read`, `.write`. The stack pointer in
    `emu.getState()` is `cpu.sp`, not `cpu.s`. Both are nil rather than an error, so the
    arithmetic that follows raises inside the callback, `--testrunner` swallows it, and the
    script looks like it simply did nothing (trap 32). Wrap callback bodies in `pcall` and
    record the message.

67. **`LDX` has no absolute-long addressing mode.** `ldx long:sprid` is an assembler error,
    not a silent wrong read - but it is easy to write when the compiler's own output is full
    of `lda long:`. Use `lda long:` then `tax`. Only the accumulator has the long modes.

68. **A FLIP MIRRORS THE OFFSETS, not just the attribute bits.** Setting bit 6/7 in each
    sprite's attribute mirrors that 8x16 sprite about its OWN centre and leaves it where it
    was, so a 16x16 metasprite comes out as four quadrants each turned inside out - a square
    pulled apart into corners. `__oam_meta_spr_flipped` in nesdash.s also transforms the
    offsets, in 8 bits with the carry: `dx -> x - dx - 8` and `dy -> y - dy`. The `-8` is the
    sprite's own width; there is deliberately NO `-16` on the vertical, and the original has
    that adjustment written out and commented off because 8x16 mode already accounts for the
    height. Positions alone cannot test this - the sprites sit at the same two x values
    either way - but the ORDER can, and `verify_gamemode_sprites.lua` checks it.

69. **A tool that reconstructs sprites for comparison has to flip rows INSIDE the tile.** A
    vertical flip of an 8x16 sprite swaps which tile of the pair is on top *and* mirrors the
    rows within each tile. Doing only the swap produces two disjoint halves and looks exactly
    like a bug in the thing under test. That cost a detour while chasing trap 68.

70. **`SAUCE/` indexes past the end of arrays and relies on cc65's layout.**
    `ROBOT_JUMP[x]` is spelled `ROBOT[x + 20]`: it runs off the walk table and lands in the
    jump table because cc65 happens to place them adjacently. `ROBOT` and `SPIDER` do have
    their jump frames appended so those stay in range; `MINI_ROBOT` and `MINI_SPIDER` do not.
    Nothing guarantees adjacency here - name the second array and index it.

71. **A register written mid-frame tears the picture, and it is not a tilemap bug.** The
    SNES applies BG1HOFS the instant it is written, and the game calls `scroll()` from the
    middle of its frame. The result is a full-width horizontal band that moves up and down
    with how long the frame's work takes - it looks exactly like a tilemap addressing fault.
    **The tell is that the boundary sits on a SCREEN LINE, not on a tilemap row**: identical
    tilemap content renders correctly above it and wrongly below. The NES never had this
    because neslib's `scroll()` only stores and its NMI handler writes `$2005` in vblank;
    `set_scroll_x/y` now latch and `ppu_wait_nmi()` applies. Any other PPU register the game
    sets mid-frame has the same problem.

72. **When comparing a capture against emulator state, decide which frame each describes.**
    At `startFrame N`, VRAM and the registers hold what is about to draw frame N, while
    `takeScreenshot` returns frame N-1. Reading both there compares a picture against a state
    one frame newer - and on a scrolling scene that looks like a rendering bug. Worse, moving
    a write into vblank (trap 71) *changes* the skew, so a check pinned to one expected scroll
    value breaks when the bug is fixed. `verify_bg.py` therefore asks a skew-independent
    question: does SOME single scroll offset explain every screen line? A tear is exactly the
    failure of that.

73. **A branch relay must not sit where the code can fall into it.** This assembler has no
    `jml`, and `jmp long:label` assembles a 16-bit operand the linker then rejects (use
    `jmp .word0 label`, or short relays). Chaining relays is fine - but putting one in a
    fall-through path sent every sprite back to the top of the loop before it was drawn, and
    OAM came out empty with no error anywhere. Put relays immediately after an unconditional
    branch, or at the end where falling into them IS the loop-back.

74. **Calypsi passes POINTER arguments in its direct-page pseudo-registers** (`_Dp`,
    `_Dp+2`), not on the stack - verified across every call site of `oam_meta_spr`. That is
    compiler scratch and not something to build an assembly interface on, so
    `shim_meta_run()` takes its arguments through globals instead and the C wrappers fill
    them in. Scalar arguments are fine: first in A, the rest pushed right to left as 16-bit
    words (trap: that is what `oam_spr.s` relies on).

75. **A `ztiny` section reaches the direct page with no linker change.** `src/snes-HiROM.scm`
    already routes `registers ztiny tiny` into the DirectPage memory. Assembly that needs
    `[dp],y` - the only addressing mode that reads through a 24-bit pointer, which anything
    walking ROM data does - can declare its own scratch there.

76. **Constant offsets beat an inner loop, by a lot.** The collision-column copy went from 37
    scanlines to 14 purely by writing a page's 15 rows long-hand as `dst[0]`, `dst[16]`,
    `dst[32]`… instead of looping with a pointer add. Calypsi was spending more on the add
    and the loop test than on the copy. Worth trying before reaching for assembly.

77. **Zero is not a neutral default for a game option** - see trap 63, and now also
    `viseffects` enabling `trail_loop`, which costs 12-20 scanlines a frame. Turning an
    option on to fix a missing feature adds work that was not in any earlier measurement.

78. **`cube_rotate` is 16-bit FIXED POINT: the low byte is a fraction.** The airborne cube
    adds `CUBE_GRAVITY_lo[framerate * 4]` to the LOW byte each frame and the drawn 0..23 step
    advances only when that carries - 107 at 60Hz, so a step every 2.4 frames and a
    revolution in 57. Stepping the high byte directly spins it 2.4x too fast and looks like a
    physics problem rather than a rendering one. Assume any `_lo`/`_hi` pair in the game's
    state is fixed point until proved otherwise.

79. **`gen_assets.py` used to give up on any header expression it could not evaluate**, and
    the level headers are written in terms of `space_defines.h` constants -
    `(1 << 7) | _DECO1`, `(_SPIKESA << 4) | _BLOCKSA`. Silently yielding 0 made the game ask
    for CHR bank 0, which is a background tileset, not sprite art. The parser resolves `_NAME`
    against that header now. **Every header field that reads 0 is suspect** - this is the
    third one (spawn_y_pos, then viseffects, now the deco bank).

80. **A mapper CHR bank switch is a DMA, and 4KB of DMA does not fit in one vblank.** About
    24 scanlines of the 37, on top of the ~20 the column, OAM and palette transfers already
    want. Send it whole and the tail lands during active display where VRAM writes are
    dropped (trap 35) - the bank arrives with a hole in it. Budget it per frame and let a
    switch take two. That makes a half-arrived upload a legitimate state, so anything
    checking VRAM against the selected bank has to wait for the queue to drain (`shim_chr_pending`);
    otherwise it reports a transient as corruption, exactly like trap 55.

81. **Sign-extend-and-add folds into one add.** `x + sext(dx)` for a zero-extended byte is
    `(dx ^ $80) + (x - $80)`, so the bias is computed once per metasprite and the per-sprite
    work is an xor and an add - not a mask, compare, branch and add per axis. The mirrored
    forms fold too: `x - dx - 8` is `(x + $78) - (dx ^ $80)`, and `y - dy` is
    `(y + $80) - (dy ^ $80)`. This took the sprite walker's position maths from about
    24 instructions per sprite to about 6.

82. **Advance a stream pointer BEFORE the checks that skip an entry**, not after. The
    off-screen tests in the metasprite walker branch back to the top of the loop; with the
    advance at the bottom, a dropped sprite re-reads the same quadruplet forever. Reading the
    whole entry up front costs nothing - a dropped entry is rare - and makes the loop
    obviously terminating.

83. **Instruction counts from two runs at different frame rates are not comparable.** A
    profiler that hooks address ranges gives exact counts, but if the change under test alters
    the frame rate then at video frame N the two builds are at DIFFERENT POINTS IN THE LEVEL,
    with different content on screen. Compare scanline-accurate phase splits
    (`tools/profile_worst.lua`) or normalise against a known-unchanged item; do not read the
    raw per-frame counts as a before/after.

84. **An optimisation that does not move the number is not an optimisation.** The walker's
    "OAM is already full, return early" guard was added to cut work in sprite-dense frames and
    measured as making no difference - the peak is 58 OAM entries against a 63-sprite cap, so
    it almost never fires. It is kept as a bound on the worst case and described as one.
    Reporting it as a win would have been easy and wrong.

85. **WHICH memories get their own `.raw` file is not a fixed property of the build.**
    `--raw-multiple-memories` emits a memory separately only when it is NOT contiguous with
    the main image - so adding the sprite CHR at bank `$C3` bridged the gap to the column
    stream at `$C4` and `LevelColumns0.raw` stopped being produced. The build had been
    splicing it unconditionally and failed loudly, which was luck; the failure trap 38 warns
    about is the silent one. `pack_hirom.py` now skips a missing part and
    `tools/verify_rom_layout.py` confirms the data really is in the finished ROM - including
    that no CHR bank straddles a 64KB bank, which DMA cannot cross (trap 37).

86. **The game has NO alphabet, and every lead saying otherwise is wrong.** The level
    tileset spells "ATTEMPT" as `PQQRSTQ` - level tiles that look like letters.
    `menus.chr` is not an ASCII font either: `one_vram_buffer('g', NTADR_A(...))` in the
    menu code looks like proof that it is, and is placing tile `$67`, a piece of menu
    artwork. `LETTERBANK` is `SawbladesNone.chr`. The real menus draw pre-rendered screens
    with `vram_unrle`, so nothing ever needed a font. `tools/gen_menufont.py` generates
    one, indexed by character code so a tile index IS its ASCII value.

87. **FastROM is two switches and neither works alone.** `MEMSEL` ($420D bit 0) and the
    header's map mode byte ($FFD5: `0x31`, not `0x21`) must agree; hardware ignores one
    without the other, and there is no error either way - the ROM just runs at 2.68MHz.
    All of this port's code and data is at banks `$C0`-`$C9`, squarely in the `$80`-`$FF`
    range FastROM speeds up, and turning it on was worth 2.5 points of frame rate on its
    own. Check this before optimising anything.

88. **Splitting work across frames is not the same as balancing it.** `draw_screen`'s
    decode was moved off one frame and onto two, and the frame rate barely moved: the
    split was 63 scanlines against 35, and the 63 was still the frame that dropped. What
    matters is the PEAK, not that the work was divided. Building one tile column per frame
    instead of both on one is slightly more total work and much less peak. Profile the
    distribution, not the average - `tools/profile_drawscreen.lua`.

89. **A verifier that fails to start leaves the PREVIOUS run's report in place.** Every
    `verify_*.lua` writes its verdict to `out/*.txt` and prints little, so `tail
    out/gamemode_sprites.txt` after a run that never happened reports the last run's pass.
    This is how "EVERY GAMEMODE DRAWS ITS OWN SPRITES" was believed for an hour after the
    level select started blocking every script at boot. `tools/verify_all.sh` deletes each
    report before its run and treats a missing one as a failure.

90. **A test that pokes game state has to pin it where the DRAW can see it.** Forcing
    `gamemode` hands control to an arm that was never entered properly: the wave and the
    spider fly the player off screen within a few frames, `drawplayerone` hides its sprites
    at Y=255, and the harness reads that as "this gamemode draws nothing". The sprites were
    correct and off screen. Pinning `player_y` once per frame is not enough either - the
    physics moves it again before the draw, so the pin belongs on the pre-draw hook.

91. **The linker map writes static FUNCTIONS in a different shape from static VARIABLES.**
    A variable gets `name in section 'zfar'  placed at address 7e852d-7e852d`; a function
    wraps the address onto the NEXT line. `gen_addrs.py` handled only the one-line form, so
    it found every static variable and no static function - and the profiling scripts
    hooked nothing and reported a clean timeline. Neither map form appears in the
    `name = address` symbol table, which only lists globals.

92. **`out/addrs_full.lua` was written by hand once and then went stale**, which is worse
    than hardcoding an address: it still resolves, and points at whatever variable has since
    moved into that slot. `build_game.sh` now generates it from `out/game_full.map` on every
    build, alongside `addrs.lua` from the small ROM's map.

93. **Emulator input is a DUTY CYCLE, not a tap.** The shim derives a press edge, so a
    button held across consecutive polls moves a menu selection once; `inputPolled` fires
    more than once per `pad_poll`; and a menu iteration is not one frame long, because a
    redraw is 1024 tilemap writes in forced blank. Every scheme based on counting presses
    undercounted, and it looked like a menu bug. Hold for ~8 frames, release for ~8, and
    drive off the observed state - `tools/menu_skip.lua`.

94. **A cast to `uint8_t` used as an ARRAY INDEX is compiled as a SIGN extension.**
    `lz_ring[(uint8_t)(idx + n)]` becomes `eor ##128 / and ##255 / sec / sbc ##128 / tax`,
    so index 159 reads `lz_ring - 97`. Reading a plain `uint8_t` VARIABLE is fine
    (`and ##255`) - it is the cast inside the subscript that goes wrong. Keep the index in
    a `uint16_t` and mask it.

    This is the worst kind of failure: every access below 128 is correct, so it works
    until it does not. In the level decompressor it corrupted a handful of bytes of ALL 46
    levels; the stream resynced on the next literal, and each level drew *nearly* right - a
    wall of one metatile where there should have been sky. Nothing crashed, no check
    failed, and the port shipped a milestone with every level subtly wrong.
    `tools/scan_signext_index.py` runs in `build_game.sh` and there is a reproducer for it
    in its header. Same family as trap 56.

95. **"It drew something" is not a correctness test, and writing one that only covers a
    single case is how you find that out.** `verify_render.lua` was byte-exact but existed
    for stereomadness alone, because the oracle was the precomputed ROM stream and that
    was only ever generated for one level. The other 45 were covered by
    `verify_level_boot.lua`, which asked whether the tilemap was non-empty - and it passed
    on all 46 while trap 94 corrupted every one of them.
    `tools/gen_level_columns.py --all` now emits a per-level oracle (both the inflated RLE
    and the tilemap columns) and `verify_level_boot.lua` compares against it.

96. **Only 63 of the 64 tilemap slots can be checked, not 64.** Column `c` lives in slot
    `c % 64`, so column `rld-65` shares a slot with `rld-1`. A window of a full 64 columns
    includes one whose slot has already been reused by the newest write - and whether that
    write has reached VRAM depends on the vblank, so the oldest column reads as itself or
    as its successor depending on timing. The safe window is `rld-64 .. rld-2`.

97. **A harness that pokes game state must prove the game is READY for the poke.**
    `menu_skip.lua` wrote `menu_sel` and pressed START a few frames later. `inputPolled`
    fires on the hardware auto-joypad read every frame, including while the C runtime is
    still clearing BSS - so the poke could be wiped and START went in against a selection
    of 0, silently testing level 0 while believing it was testing level 9. It showed up as
    ONE flaky level out of 46, and moving the frame threshold just moved which one. The
    fix is a positive signal that the menu exists - its title is on screen - plus an
    assertion after entry that the level which started is the level that was asked for.

98. **The level's BG tileset and its two colours are per level, and neither was applied.**
    `snes_m0.py` builds ONE tileset, for the level named on its command line, and that was
    uploaded at boot and never changed - so 36 of the 46 levels drew the right shapes from
    the wrong art, and every one of them drew it in stereomadness's colours.
    `tools/gen_bgchr.py` emits the ten combinations the set actually uses; `set_bg_tileset`
    and `set_level_colors` apply them at level load.

99. **A 4KB CHR upload is TWO vblanks at the normal budget.** `set_bg_tileset` has to flush
    immediately when the screen is in forced blank, or the level's first frames show half
    the previous level's tiles - and the seam lands exactly at byte 2048, which is the
    budget, not a coincidence. A verifier sampling VRAM has to wait for
    `shim_chr_pending == 0` for the same reason.

100. **The background colour CHANGES during a level, and that is the game working.** `COLR`
    objects in the level's own sprite stream call `pal_col()` (`sprite_loading.h`), so
    reading CGRAM at an arbitrary frame and comparing it with the level header gives a
    different wrong answer depending on how far the camera got and how long the level took
    to load. The header colours are a STARTING state: check them from an exec hook on the
    last call `init_rld` makes, and re-read on every call - the first one happens during
    boot, before any level is chosen.

101. **`draw_screen` is not what makes the port drop frames.** It scales with level height,
    and the correlation between level height and frame rate across the 46 levels is +0.01.
    The slowest levels are height 27, the same as the one level that holds 60Hz; the
    platformer levels, where the camera does not scroll and the renderer streams almost
    nothing, hold 100%. It is `draw_sprites` (~111 scanlines) and `sprite_collide` (~70).
    Measure before optimising the renderer again - two attempts are recorded in
    [M2_17_TILESETS.md](M2_17_TILESETS.md), one that changed nothing and one that was
    slower.

102. **A LIB routine whose C prototype returns `void` can still write half the player
    state.** `cap_scroll_y_at_top` / `cap_scroll_y_at_bottom` are declared in
    `nesdash.h` as "caps the Y scroll at min_scroll_y" and nothing more, and the port
    implemented exactly that. The 6502 originals also move `currplayer_y` and
    `player_y[1]` back by the scroll they just discarded and clear `scroll_y_subpx` -
    because `process_y_scroll` moves the camera and the players together, and when the
    camera is pinned the players' half of that has to be taken back. Without it the
    player drifts about 2px a frame for as long as the camera stays at a limit.
    **Read the assembly, not the header comment**, for anything in `LIB/asm`.

103. **The bug looked like ball physics and was in the camera.** The ball bounced ~7px
    on flat ground. `gamemode_ball.h` and `common_gravity_routine` were both correct;
    what moved the player was `process_y_scroll`, via trap 102. The ball is simply the
    gamemode that shows it: its camera runs through the `target_scroll_y` arm, which
    moves the player every frame with no dead zone, whereas the cube's arm only moves
    the player when it is outside one. `target_scroll_y` is set **only** by
    `reset_level` and by a gamemode portal, so any harness that forces a gamemode
    without going through a portal leaves it stale - which reproduces the drift for the
    wrong reason. `tools/verify_ball.lua` drives it deliberately and asserts the cap
    engaged.

104. **`emu.getState()` returns a FLAT table with dotted keys.** It is `s["cpu.pc"]`,
    not `s.cpu.pc`. The nested form raises "attempt to index a nil value (field 'cpu')"
    - and **an error inside a memory callback kills that callback silently**, so the
    trace simply produces no rows and reads as "nothing ever writes this address".
    Three traces were thrown away to that. `tools/probe_memcb.lua` establishes which
    callback forms fire before a trace depends on them.

105. **Calypsi has a SECOND merge-point defect, and it drops a REGISTER, not a stack
    slot.** `gamemode_wave.h`'s

    ```c
    currplayer_vel_y = !mini ? (grav ? -vx : vx) : (grav ? -(vx<<1) : (vx<<1));
    ```

    compiled to four arms that each leave the value in A and `bra` to one shared
    store - and the store is preceded by a spurious `tya`, so every arm's result was
    discarded and whatever was in Y was stored. Measured: `currplayer_vel_y` was **+1
    on every frame**, so the wave did not move vertically at all. It is the same
    family as trap 8 but `tools/scan_stackslots.py` cannot see it, because nothing
    reads an unwritten slot. `tools/scan_merge_tya.py` does, and runs in the build.

    The discriminator against the many innocent `tya`/`txa` sites is an
    **unconditional `bra` to the label**: when Calypsi gets this right it puts the
    store behind a second label and the other arm branches *past* the transfer.

    Fixed the same way as `common_gravity_routine`: written long-hand in
    `overlay/gamemodes/gamemode_wave.h`, every arm storing to `currplayer_vel_y`
    itself.

106. **A verifier saying "this case was NOT covered" can be pointing at a bug.**
    `verify_ship` had reported, for several milestones, that the wave's tilt never
    reached the clamp - and it was right to. The wave's velocity was stuck at +1 by
    trap 105, so it could never get near the bound. Fixing the wave made the case
    reachable and it now checks 779 clamped frames. Treat an uncovered branch as an
    open question about the port, not as a shortcoming of the test.

107. **Mesen resolves `--testrunner` paths relative to its own directory, not the
    shell's.** A relative ROM or script path exits 1 with no output and no report - and
    leaves the previous run's `out/*.txt` in place to be read as this run's (trap 89).
    Pass both absolutely. Separately, the Bash tool's sandbox cannot launch
    `Mesen.exe` at all (exit 127, no output); run verifiers from PowerShell.

106. **MEASURE THE NES. It is right there.** Mesen runs the NES build and
    `Famidash - Huge Man.dbg` gives every routine's address, so "the NES does not lag here"
    can be turned into a number instead of a hypothesis. Two rounds of renderer optimisation
    were built and reverted before anyone did this (M2.17), and the answer was in a routine
    nobody had looked at.

    Compare at the SAME LOAD or the comparison is worthless: instructions per frame in the
    same routines, measured on two different levels with different sprite counts, produced a
    confident 3x that meant nothing. Cost per call bucketed by active sprite slots is
    comparable, because both machines run 262-line frames at 60Hz.

107. **A sparse `switch` compiles to a linear table search, and the cost lands on the case
    that MATCHES NOTHING.** `sprite_collide` switches on five values (`0`, `$FC`-`$FF`) and
    the common case - a sprite with a real height - matches none, so Calypsi's
    `_ValueSwitch16` walked the whole table and failed for every active sprite, every frame:
    683 instructions per frame, as much as the rest of the routine, and precisely the
    per-active-sprite cost that made sprite-heavy levels drop. An if-chain that rejects the
    common case in one comparison cut that path 34% and `cycles` from 80.4% to 86.9% of
    60Hz. cc65 does not do this, which is why the NES build does not pay it. Look for this
    in any hot switch.

108. **`--raw-multiple-memories` can emit BOTH a merged raw and a TRUNCATED per-memory one
    for a region inside it.** With 168 levels the linker produced a `SpriteCHR.raw` covering
    bank `$C3` upwards with all 15 BG tilesets in it, AND a `BGCHR.raw` holding only 10 -
    and `pack_hirom.py`, splicing parts in the order given, laid the truncated copy over the
    good data. Five tilesets vanished from a ROM that linked, packed and passed the layout
    check. Splice LARGEST FIRST and FILL-ONLY, so a partial raw can only fill bytes nothing
    has claimed. Trap 38's warning was right and its guard was incomplete: extend
    `verify_rom_layout.py` whenever a new kind of bulk data goes in the ROM.

109. **A menu that redraws under forced blank blinks, and a WRAM shadow plus one DMA does
    not.** 704 tilemap words is about a fifth of a vblank as a DMA and does not fit at all
    written one at a time. And build the shadow with POINTER WALKS: the obvious
    `rows[r][c] = names[lv * W + c]` costs a multiply and a 2D index per character with the
    counters in stack slots, which measured at eight frames per rebuild - the auto-repeat
    was fine, the redraw was the limit.

110. **A 16x16 OBJ cannot replace an NES 8x16 sprite - it is twice as wide.** It can only
    replace TWO NES sprites side by side, sharing a row and attributes. "16x16 mode halves
    the OAM entries" was repeated for several milestones and is wrong: measured on the
    entries actually drawn, it is **18-19%**. Count what the frame draws, not what the
    metasprite tables contain.

    And the VRAM is not the constraint on building one. The OBJ NAME space is 512 tiles
    whatever the VRAM size, and a 16x16 takes `N`, `N+1`, `N+16`, `N+17` in the 16-wide OBJ
    grid - four arbitrary tiles cannot be combined without placing them adjacently.
    Duplicating tiles to allow arbitrary pairs moves the saving from 18% to 23%, because
    nearly every mergeable pair is already two consecutive tiles: a CHR re-layout gets it
    for free.

111. **16x16 OBJ mode reduces OAM ENTRIES, and OAM entries are a PPU per-scanline resource,
    not CPU time.** It was called "the structural fix for the sprite budget" for three
    milestones. Built and measured: it removes 22% of the entries and makes the walker
    SLOWER, because the walker's cost is per METASPRITE ENTRY - both halves of a merged
    pair are still read, sign-extended, positioned and culled, and merging only removes the
    second entry's four-byte write. Ceiling is ~3% of the walker. It is the right fix for
    sprite DROPOUT at the 32-per-scanline limit, and the wrong one for frame rate.
    See [M2_23_OBJ16.md](M2_23_OBJ16.md); `snes_m0.obj_pair_layout()` is kept, unused.

112. **`profile_instr.lua` counts game frames with `ppu_wait_nmi`, which the LEVEL LOAD
    loop also calls.** It reported 88.7% for a level `verify_framerate.lua` measured at
    23.9%, which sent an investigation after a phantom regression. `everything_else` runs
    once per gameplay frame and is the right hook. Two counters that disagree by 4x are a
    reason to check what each one counts, not to pick the one you like.

113. **A quarter of the compiled hot loop is `rep`/`sep`, and it computes nothing.** The
    game's variables are `uint8_t` and the arithmetic around them is 16-bit, so Calypsi
    flips the accumulator width back and forth around almost every access - 130 of
    `sprite_collide`'s 519 instructions. The 6502 has no such concept, which is most of why
    the port executes 2x the NES's instructions for the same work at the same sprite load
    (216 -> 412 fixed, 21 -> 42 per active sprite). Measure instruction COUNTS on both
    machines before blaming the hardware: the SNES has twice the clock and is spending it
    on twice the instructions. See [M2_24_WHY_2X.md](M2_24_WHY_2X.md).

114. **A test script that holds A from frame 1 RACES the level select.** A is also "select
    this level". `menu_skip.lua` pokes `menu_sel` and presses START; every other script
    held A for gameplay from the first frame. Whichever won decided which level ran - and
    it flipped when a COMPILER FLAG moved the menu by a frame, so every scripted run
    silently played level 0 and reported a perfectly plausible frame rate for it. Gameplay
    input must be gated on `menu.done()`. The assertion that caught it ("asked for level 8,
    the game started level 0") was added two milestones earlier for exactly this and is the
    only reason it was not believed.

115. **Cross-call optimisation is a size optimisation and it is ON at `-O 2`.** It replaces
    repeated code with subroutine calls: `sprite_collide` shrinks from 519 static
    instructions to 373 AND gets slower, because the count does not include the
    subroutines. Measured, plain `-O 2` costs 11-18 points on the heavy levels;
    `-O 2 --speed --no-cross-call` gains 2-5. Static instruction counts cannot see this -
    measure the frame rate.

116. **`-O 2` miscompiles `gamemode_ship.h`.** The four-way `tmpgravity` branch followed by
    a conditional negation loses the negation on the HOLD_FALL path: `+62` where the table
    says `-62`, on 100% of samples. `tools/verify_ship.lua` catches it and the three
    `scan_*.py` scanners do not, so it is a FOURTH Calypsi defect shape. `-O 1` ships until
    it is worked around.

---

## 6. Layout

```
docs/                  design doc, per-milestone results, this handoff
src/main.s             65816: static display ROM        (ca65/ld65)
src/scroll.s           65816: column-streaming scroll   (ca65/ld65)
src/lorom.cfg          ld65 config, 32KB
src/lorom256.cfg       ld65 config, 256KB, banked column data
src/snes-HiROM.scm     Calypsi linker rules (copied from the toolchain)
shim/include/            SNES reimplementation of the NES hardware API (headers)
shim/src/shim_core.c     the 8 symbols the physics core needs
shim/src/shim_state.c    globals that live in LIB/asm on the NES
shim/src/shim_ppu.c      palette, OAM, VRAM, the vblank flush
shim/src/shim_misc.c     scroll maths, collision, RNG, banking, audio stubs
shim/src/shim_engine.c   level and sprite engine - column stream, collision, objects
shim/src/oam_spr.s       the sprite writer, hand-written 65816 - read its header first
shim/src/snes_main.c     entry point for the small physics ROM (works)
shim/src/snes_main_full.c entry point for the full game ROM (plays Stereo Madness)
shim/src/snes_header.s   SNES cartridge header
overlay/               ported SAUCE/ files; shadows the game repo
                       (also carries Calypsi workarounds — see trap 27)
                       defines/    physics tables, dialogbox
                       functions/  collision, sprite_loading, draw_sprites,
                                   level_loading, scroll, practice_state
                       gamemodes/  cube, spider
                       gamestates/ state_game, state_lvldone
probe/                 translation units for testing what compiles
bugreport/             Calypsi reproducers + README
tools/                 asset pipeline, ROM builders, Mesen Lua, verifiers
out/                   generated (gitignored)
```

Key tools added while fixing M1.4:

| | |
|---|---|
| `tools/scan_stackslots.py` | catches the trap-8 miscompilation; run by `build_game.sh` |
| `tools/gen_addrs.py` | `out/game.map` → `out/addrs.lua`; run by `build_game.sh` |
| `tools/gen_assets.py` | `out/*.bin` → `out/assets.c`, `out/metatiles_coll.c`; run by `build_game.sh` |
| `tools/verify_land.lua` | pass/fail: falls, lands, rests, jumps |
| `tools/trace_fall.lua` | per-frame physics trace |
| `tools/probe_full.sh` | compile the whole gameplay TU, summarise what is still broken |
| `tools/undef_surface.sh` | what the shim still owes the gameplay code — expect 0 |
| `tools/port_collide_lookup.py` | rewrites `sprite_collide_lookup()`'s computed goto as a switch |
| `tools/gen_palette.py` | NES index → CGRAM table, from the asset pipeline's own table |
| `tools/gen_columns.py` | precomputed tilemap column stream, one 64KB part per bank |
| `tools/verify_boot.lua` | the full ROM boots and keeps executing in ROM |
| `tools/verify_render.lua` | the streamed tilemap matches the level, exactly |
| `tools/verify_input.lua` | the pad reaches the game AND the player jumps |
| `tools/shot_full.lua` | a screenshot to look at — **not** a check (trap 1) |

Added while fixing M2.12. The profilers matter as much as the checks: every number in
[M2_12_LEVEL_SPRITES.md](M2_12_LEVEL_SPRITES.md) came out of one of them, and guessing at
this had already cost a session.

| | |
|---|---|
| `tools/verify_sprite_chr.lua` | OBJ VRAM vs `out/spr.tiles.bin`, byte for byte — expect 8192/8192 |
| `tools/verify_framerate.lua` | game frames vs video frames; the lag check |
| `tools/verify_oam.lua` | OAM checksum per GAME frame — the equivalence harness for changing the sprite writer |
| `tools/profile_gameplay.lua` | frame timeline: every per-frame function, and the scanline it is reached on |
| `tools/profile_worst.lua` | times every game frame, prints only the slowest with phase splits |
| `tools/profile_vblank.lua` | splits the vblank flush by the registers each stage writes |
| `tools/trace_metaspr.lua` | largest metasprite per sprite type — catches a runaway walk |
| `tools/trace_spr_cull.lua` | recomputes `check_spr_objects`' own two tests per slot |
| `tools/trace_oam_callers.lua` | attributes `oam_spr` calls to their caller via the stacked return address |
| `tools/shot_sprites.lua` | screenshot somewhere the level actually has objects — **not** a check |

Added while fixing M2.13:

| | |
|---|---|
| `tools/verify_bg.py` + `tools/dump_bg.lua` | **the independent BG oracle** — renders the tilemap out of VRAM through the software PPU and asks whether one scroll offset explains the whole screen. This is what found the tear; `verify_render.lua` structurally cannot (trap 61) |
| `tools/verify_gamemode_sprites.lua` | every gamemode draws its own sprite table, and a flip mirrors the offsets |
| `tools/gen_gamemode_expect.py` | `sprites.h` → which OBJ tiles each gamemode may name; the oracle the above checks against |
| `tools/profile_worst.lua` | times every game frame, prints only the slowest with phase splits |
| `tools/trace_gamemode.lua` | where the gamemode changes, and what the player draws there |

Added while fixing M2.14:

| | |
|---|---|
| `tools/gen_sprchr.py` | GAMECHR's 2KB sprite banks → 4bpp, one `.incbin` each; what a CHR bank switch DMAs |
| `tools/verify_cube_spin.lua` | the cube spins at CUBE_GRAVITY, measured over real jumps |
| `tools/verify_rom_layout.py` | the bulk data is really IN the packed ROM, and no CHR bank straddles a bank — the guard for traps 37 and 38 |

`verify_sprite_chr.lua` now checks the selected banks rather than one fixed image, so it
tests the switching and not just the boot upload.

Added while fixing M2.15:

| | |
|---|---|
| `tools/profile_sprite_split.lua` | instructions executed inside each function's address range — how much of drawing sprites is the SHIM and how much the GAME. It answered 67%, not the 50% that had been assumed |
| `tools/stress_sprites.lua` | forces N active-sprite slots on, so the frame budget can be read at a load the level never reaches. `STRESS_SLOTS` also works on `profile_sprite_split` and `profile_worst` |

`verify_framerate.lua` now reports the peak OAM load alongside the speed, and
`verify_gamemode_sprites.lua` forces an H-flipped cube frame so the mirrored position path is
tested rather than left to whichever rotation step the sample lands on.

Several of these force the run (hold A, clear `cube_data` bit 0 at the top of the draw phase)
so it reaches the sprite-dense part of the level. Without that the cube dies on a spike at
`scroll_x` ~185 and the first object in the stream is at x = 800, so the measurement is of an
empty screen. It is a deliberate cheat, and it can drive the game into states real play
cannot reach — a stuck cube inside geometry produced a 22%-speed window that was an artifact,
not a bug.

Probe translation units:

| | |
|---|---|
| `probe/probe4.c` | the physics core — this is what the **ROM** links |
| `probe/probe_full.c` | all gameplay; compiled + scanned as a gate, does not link yet |
| `probe/link_full.c` | a `main()` reaching the real entry points, so `undef_surface.sh` cannot be fooled by tree-shaking |

Added while fixing M2.16. `verify_all.sh` is the entry point - the individual scripts write
their verdict to `out/*.txt` and print little, and reading a stale one is trap 89.

| | |
|---|---|
| `tools/verify_all.sh` | every verifier, one line each; deletes each report before its run |
| `tools/gen_levels.py` | all 46 levels: LZ streams, sprite streams, headers, names, metatile words |
| `tools/gen_menufont.py` | the level select's 5x7 font - the game has no alphabet (trap 86) |
| `tools/gen_sprchr.py` | the 14 switchable 2KB sprite CHR banks, widened to 4bpp |
| `tools/verify_rom_layout.py` | every level, sprite stream and CHR bank is IN the packed ROM, and none straddles a bank |
| `tools/verify_level_boot.lua` | one level per run: loads, streams, draws, player on screen |
| `tools/verify_menu.lua` | decodes the level select out of the TILEMAP and scrolls to the end |
| `tools/menu_skip.lua` | the fixture every other verifier uses to get past the level select |
| `tools/profile_drawscreen.lua` | the decoder's cost DISTRIBUTION - an average is useless here (trap 88) |
| `tools/gen_level_columns.py` | the per-level oracle: what each level inflates to and the tilemap columns it should produce |
| `tools/scan_signext_index.py` | catches Calypsi sign-extending a `(uint8_t)` array index (trap 94); run by `build_game.sh` |
| `tools/gen_bgchr.py` | the per-level BG tilesets - the ten combinations the level set uses, plus the appearance oracle |
| `tools/sweep_framerate.sh` | frame rate on EVERY level; level 0 alone said nothing (trap 101) |
| `tools/profile_instr.lua` | instructions per game frame per routine - what the scanline timeline cannot tell you (trap 106) |
| `tools/profile_collide.lua` | instructions per call bucketed by sprite load, for the like-for-like NES comparison (trap 113) |
| `tools/gen_instr_ranges.py` | the profilers' PC ranges, from the map, so they cannot go stale |
| `tools/gen_linkcfg.py` | the full ROM's linker script, sized to the level set |
| `tools/gen_physics_expect.py` | the physics tables as a Lua oracle, from the game's own header |

`out/assets.c` and `out/metatiles_coll.c` previously had **no generator** — they existed only
in gitignored `out/`, so the game ROM could not be built from a clean tree at all. That is
what `gen_assets.py` fixes; the full sequence below now works from an empty `out/`.

**Variable addresses** (`Generic`, `eject_D`, `currplayer_vel_y`, …) **change on every
rebuild** — adding or removing a single variable reshuffles the whole `zfar` section. Trace
scripts must `dofile("out/addrs.lua")` rather than hardcoding them - or `out/addrs_full.lua`
for the full ROM, which has its own layout and is generated from `out/game_full.map`. `trace_phys.lua` and
`trace_coll.lua` had baked-in constants and were deleted rather than left as landmines;
`trace_fall.lua` covers both. See trap 5 for what happens when they drift.

---

## 7. Open items beyond M1

- **Audio (M4)** is in progress: the HiROM build now runs the original 6502
  FamiStudio sequencer and plays its
  pulse/triangle/noise register image through the SPC700 BRR/DSP driver. DPCM
  bank streaming and the SA-1 command/state-copy seam remain; see
  `docs/HANDOFF_NEXT.md`.
- **Sprite CHR banking is done** ([M2_14_CHR_BANKING.md](M2_14_CHR_BANKING.md)). The four 1KB
  registers — the background tilesets — are not, and neither is parallax, which wants a BG
  layer and a scroll register rather than a bank a frame. OBJ tiles 0–255 remain free, since
  no sprite indexes NES pattern table 0.
- **16x16 OBJ mode** is the structural fix for the sprite budget and the prerequisite worth
  doing first — see section 3.
- **The level select is a debug menu, not a port of `menustates/levelselection.c`.** That
  wants the mouse, the save file, the difficulty faces and a lot of menu CHR. What is there
  lists all 46 levels and starts them; see
  [M2_16_LEVELS_AND_MENU.md](M2_16_LEVELS_AND_MENU.md).
- **Three Calypsi bugs** are worth reporting upstream; reproducers and a write-up are in
  [bugreport/README.md](../bugreport/README.md). The merge-point one (trap 8) is the
  important one — it miscompiles ordinary C silently, so any code this port compiles could
  be affected, not just what has been exercised so far.
- **Computed goto in `collision.h`** ties the NES codebase to GCC/clang-family compilers.
  Worth raising with the Famidash team independently of this port.

117. **The two processors see I-RAM at different addresses.** The SA-1 has it at
     `$0000-$07FF` (and again at `$3000-$37FF`); the S-CPU has it ONLY at
     `$3000-$37FF`. Using one number on both sides does not fault - from the
     S-CPU, `$0100` is WRAM, a valid address holding something else - so the
     failure is silent and looks like the other processor never wrote anything.
     Hit twice: once in `sa1_boot.s`, once in C. `shim_sa1.h` now carries two
     names for the one place, `SHIM_MB` and `SHIM_MB_S`.

118. **I-RAM is not zeroed at power-on.** `boot_ack` came up as `$86`, so a
     `!boot_ack` test read false and `video_init` never ran - the screen showed
     uninitialised VRAM while every other part of the port worked. `scpu_boot`
     clears the mailbox, and the request channel compares for equality rather
     than truthiness.

119. **A flush called from the SA-1 empties the queue without moving a byte.**
     `menu_flush`, `flush_vram_update2` and `flush_chr_now` are called by the
     game itself and clear `menu_dirty` / `vq_len` / `cq_len` / the CHR queue as
     a side effect. On the SA-1 the transfers do nothing but the queues still
     drain, so the S-CPU always found nothing to send. This cost the level's
     first screen AND the menu's level list, and both looked like missing art
     rather than a lost queue. All three are requests to the S-CPU now.

120. **`ppu_off()` only reaches the shadow**, so the S-CPU must apply screen
     state BEFORE any bulk transfer. Otherwise a 4KB font upload runs with the
     screen on, overruns vblank, and the hardware drops the tail (trap 35). Same
     reason the budgeted CHR upload must come after deadline-bound transfers,
     not before.

121. **Register widths are unknown after a `jsl` into compiled C.** The
     assembler tracks `sep`/`rep` statically and cannot see through the call, so
     it keeps emitting 8-bit immediates while the C is free to return with a
     16-bit accumulator - the CPU then takes two bytes for the operand, eats the
     next opcode and the loop desynchronises. Re-establish widths after every
     call out to C.

122. **A missing prototype under `--code-model large` is a near call to a far
     function.** The compiler assumes NEAR, emits a `jsr` to a function in
     another bank, and there is no link error - it simply jumps somewhere
     arbitrary. Warnings about implicit declarations are not cosmetic here.

123. **Exactly one place per frame may poll the pads.** Every `pad_poll()` in
     `SAUCE/` is commented out because neslib's NMI handler did it; the port
     does it at the end of `ppu_wait_nmi`. Leaving those two calls out of the
     SA-1 branch meant gameplay saw no input at all - menus worked, because
     `level_select` polls for itself, so the game loaded levels and looked alive
     while the cube could not jump. Then adding a second poll broke the menu:
     `press` is `now & ~was`, so the second call sees the button already held
     and the edge is destroyed.

124. **`cube_rounding_table` needs thirteen entries, not twelve.** Landing at
     step 21, 22 or 23 rounds up to 24 - a full turn - and the next grounded
     frame indexes at `24 - 12 = 12`. The thirteenth entry, `-24`, is what folds
     it back to zero. With twelve the index runs off the array and the cube
     settles at an arbitrary angle, on 3 of 24 landings.

125. **Four measurement traps, each of which produced a confident wrong answer.**
     * Differencing a WRAPPING byte counter: `drawing_frame` advanced 530 times
       and read back as 18, reported as a 3% frame rate where the truth was 99%.
       Count transitions.
     * A sampling window that starts at power-on measures boot, not steady
       state - 28% where the truth was 76%.
     * `emu.setInput` must be called from `emu.eventType.inputPolled`. From
       `endFrame` it lands after the console has latched, and a working ROM looks
       like it ignores the controller.
     * Mesen's exec-range memory callbacks do not fire for `emu.cpuType.sa1`,
       and `emu.eventType.scanline` does not exist. Per-frame PC sampling from
       `endFrame` is what works.

     The cheapest defence against all four: the port has a known-good HiROM
     build. Run the same measurement against it. Two of these survived several
     rounds of investigation that a single side-by-side screenshot ended.

126. **65816 `JMP (abs)` does not relocate with D.** Ordinary direct-page
     operands in the original 6502 FamiStudio driver followed the compatibility
     island from `$0000` to `$1E00`, but its one opcode-dispatch `JMP (ptr)`
     still fetched the pointer from literal bank-0 `$00xx`. The CPU then ran
     song bytes forever at `$DD:31FF`. `tools/gen_famistudio.py` rewrites that
     single dispatch as a stack/`RTS` jump, which uses the relocated DP operands.
