# M1.6 — the whole game links and runs its own loop

> Resuming work? [HANDOFF.md](HANDOFF.md) has the current state and next task.

## Result

**Zero undefined symbols.** The entire gameplay half of Famidash links against
the SNES shim, and the resulting ROM boots and runs the game's own `state_game()`
loop, frame after frame, waiting on vblank like a real game.

```
out/famidash-snes-game.sfc    64KB   physics core     WORKS - falls, lands, jumps
out/famidash-snes-full.sfc   128KB   the whole game   LINKS AND BOOTS - draws nothing
```

**Do not read "it links" as "it works."** The level and sprite engine is not
implemented. `famidash-snes-full.sfc` executes the real game loop with real
physics against real level data, but nothing is rendered, because the eight
routines that put pixels on screen are stubs. They are listed below and marked
individually in `shim/src/shim_engine.c`.

Verify:

```bash
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-game.sfc tools\verify_land.lua
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_boot.lua
sh tools/undef_surface.sh        # expect 0
```

`verify_boot` samples the CPU across 600 frames and confirms it is executing in
ROM and advancing. It lands inside `ppu_wait_nmi` every time — the loop really is
running a frame at a time, not spinning on a crash.

## 80 symbols, closed

| Group | Count | What happened |
|---|---|---|
| State the shim owns | 17 | `shim/src/shim_state.c` — storage, no behaviour |
| neslib / nesdoug / nesdash | 29 | `shim_ppu.c` + `shim_misc.c` — real SNES implementations |
| Level / sprite engine | 8 | `shim_engine.c` — **stubs**, see below |
| Ported from 6502 | 6 | `movement`, `increment_attempt_count`, `update_level_completeness`, `display_attempt_counter`, `draw_padded_text`, `printDecimal` |
| Extracted from `menustates/` | 5 | `overlay/functions/gameplay_helpers.h` |
| Mapper | 3 | no-ops — there is no CHR ROM on SNES |
| Audio | 9 | silent stubs; M4 |
| Level data | 3 | `level_lengths_*`, parsed out of the game's assembler table by `gen_assets.py` |

### What the video shim actually does

Three mappings carry everything else:

1. **Nametable → tilemap.** The NES's two horizontal nametables at `$2000`/`$2400`
   map onto a 64×32 BG1 map at VRAM word `$1000`, stored as two 32×32 screens
   back to back — the same layout `src/scroll.s` already streams into. A PPU
   address becomes a tilemap word by keeping bits 0–9 and using bit 10 to pick
   the screen.
2. **No attribute table.** `$23C0-$23FF` has no SNES equivalent; palette is a
   field of each tilemap word. Writes there are dropped deliberately, in one
   place (`ppu_to_vram_word` returns `0xFFFF`).
3. **Palette.** `pal_col()` takes NES indices and converts through
   `nes_to_cgram[]`, which `tools/gen_palette.py` generates **from the asset
   pipeline's own table** so the runtime and the baked level colours cannot
   drift apart — a divergence that would be very hard to see.

VRAM cannot be written with the screen on, so writes queue and flush in vblank,
which is what the game's own vram buffer already expected. `ppu_wait_nmi()` polls
`$4212` rather than taking an NMI, because `snes-HiROM.scm` defines only the
reset vector (HANDOFF trap 18).

## The eight stubs — this is M2

```
draw_screen          the level renderer
init_rld             reset the level-data RLE decoder
dummy_unrle_columns  skip forward N columns (practice-point restart)
load_ground          the ground strip - why palette 1 is still unused
init_sprites         reset the active-sprite table
check_spr_objects    stream sprite objects in and out as the camera moves
drawplayerone/two    the player metasprite
```

`draw_screen` is the one that matters and the one **not** to translate. On the
NES it is 355 lines of 6502 that spread a single column update across three
frames, because that is all the VRAM bandwidth an NES vblank has — and one of
those three frames is attribute-table work that does not exist here.

The SNES design is already proven in this repo and is a different shape:
`src/scroll.s` streams a whole tilemap column per frame into the 64×32 map, and
`tools/snes_m0.py` precomputes those columns offline (verified 11264/11264
tilemap words). Wiring that in is the next milestone.

**That precomputation does not scale, and the decision is deliberate.** One
level is 131KB of precomputed columns; the game has 46 levels in this set alone
and 454 level files across all sets. Precomputing suits bringing up a single
level — which is the current scope — but the full game needs the decode to
happen at runtime, from the compressed level data, as the NES does. Choosing
between "precompute per level set" and "port the RLE/metatile decoder" is an
open design question, not something to settle by accident.

## Still open from M1.5

**16-bit pointers in game tables.** `void *` is 4 bytes here; the game's
`uintptr_t` is 2, because the NES address space is 16-bit. One instance is fixed
in `overlay/functions/draw_sprites.h`; `Metasprites[]`, `animation_frame_list[]`
and the level pointer tables have the same shape, and there is no warning at all
when an entry is used as an index rather than cast. This has to be settled
before the sprite engine is written, because that is the code that dereferences
them. See HANDOFF trap 28.

## Things worth knowing

- **`emu.getState()` returns a flat table with dotted keys** (`st["cpu.pc"]`),
  not nested tables. Indexing it as `st.cpu.pc` fails inside the callback and
  `--testrunner` swallows the error, so the script looks like it just did
  nothing.
- **On HiROM, code legitimately runs at any 16-bit address in banks `$C0-$FF`.**
  A boot check that requires `pc >= $8000` reports a healthy ROM as wedged.
- **`pack_hirom.py` now takes `--input/--output/--title`** so both ROMs can be
  packed by it, and derives the ROM-size header byte from the actual length
  instead of assuming 64KB.
