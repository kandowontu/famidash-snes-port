# M1.5 — the whole gameplay half of SAUCE/ compiles for 65816

> Resuming work? [HANDOFF.md](HANDOFF.md) has the current state and next task.

## Result

**Every gameplay source file in the game now compiles for 65816, and the
generated code scans clean.** That is `functions/`, `gamemodes/` and
`gamestates/` — ~5,500 lines of game logic plus ~3,700 lines of sprite data —
in one translation unit, `probe/probe_full.c`.

```bash
sh tools/build_game.sh        # compiles and scans probe_full.c as a gate
sh tools/undef_surface.sh     # what the shim still owes it
```

It does **not** link yet. The shim covers the hardware the physics core needed;
the rest of the game reaches for another 80 symbols. That list is below, and
producing it is most of the value of this milestone: it is now a bounded,
enumerated job rather than an open question.

Audio is deliberately excluded — the scope for this pass is single-level
gameplay, so `musicDefines.h`/`sfxDefines.h` are included for their constants
but nothing implements the driver.

## What it took

| Problem | Where | Fix |
|---|---|---|
| `get_Y` — reads the Y register left by the previous indexed access | 101 sites, 92 in `practice_state.h` | array macros record the index; `get_Y` reads it back |
| `__A__` / `__AX__` — cc65 pseudo-registers used to carry a value between statements | 10 sites | a union in the shim, so writing `__A__` changes the low half of `__AX__` exactly as on cc65 |
| `__asm__` — hand-written 6502 | ~20 sites in 6 files | ported individually into `overlay/` |
| computed goto through 254 label addresses | `sprite_collide_lookup()` | rewritten as a `switch` by `tools/port_collide_lookup.py` |
| `register` local with its address taken | `level_loading.h` | `register` dropped |
| 6502 carry flag read by the *next* C statement | 4 sites in `scroll.h` | the same condition, tested explicitly |
| Calypsi merge-point miscompilation (trap 8) | `state_game.h` | one more ternary written long-hand |

### `__asm__` is deliberately not defined in the shim

Every one of those ~20 sites was hand-written 6502 that no shim can translate.
Leaving the macro undefined turns each into a compile error until it is ported,
rather than something that quietly assembles into the wrong thing. Same
reasoning as `get_at_addr()` (HANDOFF trap 25).

### The `switch` rewrite keeps its labels

`sprite_collide_lookup()` dispatches 254 collision types into 64 labels inside
one function, with `goto spcl_*` jumps between arms and deliberate fallthrough.
`tools/port_collide_lookup.py` deletes the tables and wraps the body in a
`switch`, but **keeps every `spcl_*:` label** and adds `case` labels alongside
them. Nothing moves, so the fallthrough and the `goto`s are unchanged. Rerunning
the script against a fresh copy of the file reproduces the port.

## Two defects found in the port itself

Worth recording because both were silent:

1. **`shim_idx()` had to become a function.** As a macro, the index assignment
   landed inside an array subscript, so `a[shim_idx(i)] = b[shim_idx(j)]`
   modified and read the same object with no sequence point — undefined
   behaviour, and 60 `-Wunsequenced` warnings loud enough to bury real ones.
2. **A pointer cast was dropping the bank byte.** `void *` is 4 bytes here, but
   the game's `uintptr_t` is 2, because the NES address space is 16-bit. Casting
   a 16-bit table entry straight to a pointer silently yields a bank-0 address.
   `draw_sprites.h` now writes the 16 bits into the low half of a pointer that
   already carries the right bank.

**Point 2 is a design item, not a one-off.** Any game table holding 16-bit
pointers (`Metasprites[]`, `animation_frame_list[]`, the level pointer tables)
has the same problem, and the compiler will not warn when the value is used as
an array index rather than cast. This needs a decision before the ROM runs:
either keep all pointed-to data in one bank and synthesise the bank byte, or
widen the tables.

## The remaining surface — 80 symbols

Regenerate with `sh tools/undef_surface.sh`. `probe/link_full.c` exists purely
so the linker cannot tree-shake the game away and give a falsely short list.

### 1. State the shim must own (17) — mechanical

```
PAL_UPDATE  VRAM_UPDATE  auto_fs_updates  cc65_ptr1  cc65_ptr2  cc65_tmp1
cc65_tmp2  drawing_frame  hexToDecOutputBuffer  mouse  old_draw_scroll_y
parallax_scroll_column  parallax_scroll_column_start  seam_scroll_y
trueFramerate  famistudio_song_speed  famistudio_state
```

### 2. neslib / nesdoug / nesdash on SNES (29) — the real shim work

```
calculate_linear_scroll_y  cap_scroll_y_at_bottom  cap_scroll_y_at_top
check_collision  colBrightness  color_emphasis  display_attempt_counter
draw_padded_text  flush_vram_update2  gray_line  hexToDec  memfill
multi_vram_buffer_horz  newrand  oam_clear  oam_clear_player
oam_clear_two_players  oam_meta_spr  oam_meta_spr_disco  oam_spr
one_vram_buffer  pal_bg  pal_col  pal_fade_to  pal_spr  ppu_off  ppu_on_all
ppu_wait_nmi  set_scroll_x  set_scroll_y  sub_scroll_y  sub_scroll_y_ext
vram_adr  vram_fill  vram_unrle
```

Mostly direct: OAM, CGRAM and VRAM writes. Two need design first — the VRAM
update buffer (`flush_vram_update2`, `one_vram_buffer`, `multi_vram_buffer_horz`)
because the SNES writes VRAM through different registers with different timing,
and the palette path, because `pal_col` takes NES palette indices that have to be
converted to 15-bit BGR (the split `PAL_BUF_RAW` / `PAL_BUF` in the shim header
is already designed for this).

### 3. Level and sprite engine, currently 6502 in `LIB/asm/nesdash.s` (13) — the bulk

```
draw_screen  init_rld  dummy_unrle_columns  load_ground  init_sprites
check_spr_objects  drawplayerone  drawplayertwo  movement
increment_attempt_count  update_level_completeness  set_completion_data
set_lvldone_palette
```

`draw_screen` (355 lines of 6502) is the level renderer and the one that matters:
it is the NES-nametable counterpart of the column streaming already proven in
`src/scroll.s`. `load_ground` is the still-unwired ground layer.

### 4. Out of scope for this pass (13)

Audio — `music_play`, `music_update`, `sfx_play`, `famistudio_*` — is M4.
`check_practice_point_deletion`, `decrement_was_on_slope`, `end_level_debug`,
`gameboy_check` live in `menustates/`, which is not being ported yet;
`decrement_was_on_slope` is needed by gameplay and contains one of the three
`get_Y` sites the shim cannot cover (it computes the index with `adc #0 \n tay`).

### 5. Mapper (3) — no-ops, then real work

```
mmc3_set_1kb_chr_bank_2  mmc3_set_2kb_chr_bank_0  mmc3_set_2kb_chr_bank_1
```

There is no CHR ROM on SNES; tiles live in VRAM. These become no-ops for now,
but tileset switching has to be solved for real — the game changes CHR banks
mid-level.

## Scanner changes

`tools/scan_stackslots.py` gained stack-depth tracking, because `N,s` is
relative to the *current* stack pointer and Calypsi pushes call arguments
mid-expression. Without it, `sta 3,s … pla … lda 1,s` — a correct read-back —
looked identical to the bug. It now tracks pushes and pulls (with their M/X
width), the `tsc/clc/adc ##N/tcs` bulk stack adjustment, and resets depth at
each label so the `pha`/`rts` jump-table idiom cannot make it drift.

Calibration, checked on every run:

- `bugreport/repro_calypsi.s` → exactly the 3 known miscompilations
- the shipping build → clean
- `probe_full.s` → clean (after the `state_game.h` fix above)
