# Famidash → SNES: shim layer scope

Scoping doc. Maps every NES hardware-facing function in `LIB/` to a SNES implementation,
flags the ones with no clean equivalent, and stages the work.

Measurements in this doc were taken from the current `main` tree of the game repo.
Claims tagged **[ROM-verified]** were later confirmed byte-exact against a built
`Famidash - Huge Man.nes` by `tools/snes_m0.py` — see [M0_RESULTS.md](M0_RESULTS.md).

---

## 1. Strategy: shim, not rewrite

The thesis is that `SAUCE/` (the game) is separable from `LIB/` (the hardware), and that
`LIB/` can be reimplemented on SNES **keeping the same function signatures**, so the game
code compiles against either backend.

What that buys: one tree, one set of levels, one set of gameplay logic, two backends.
The alternative — a from-scratch SNES rewrite — forks the project permanently and doubles
every future level/feature.

```
SAUCE/            shared, ~17k lines           ← unchanged (mostly)
LEVELS/           shared, 35MB                 ← unchanged, exporter retargeted
METATILES/        shared                       ← unchanged
LIB/nes/          existing neslib/nesdoug/nesdash/mapper/famistudio
LIB/snes/         NEW: same API, SNES guts
```

### How well does the seam hold?

Measured across `SAUCE/`:

| Construct | Count | Portability |
|---|---|---|
| `crossPRGBankJump*` | 100 | **Free** — becomes `JSL`; redefine the macro once |
| `__A__` | 88 | Macro-mediated in most cases; some hand sites |
| `CODE_BANK*` | 53 | **Free** — becomes linker section placement |
| `__asm__` | 39 | **Genuine rewrites** — 6502 asm inline in C |
| `GET_BANK` | 26 | **Free** — compiler/linker provides |
| `do_if_*` | 21 | **Genuine rewrites** — 6502 flag hacks |
| `zpsym` | 20 | Direct page on 65816; concept survives |
| `__AX__` / `__fastcall__` | 19 | cc65 calling convention, needs new ABI |
| `POKE(0x2xxx)` | 2 | Trivial |

**18 of 67 files** touch cc65-specific constructs. The bulk of the count is in macros that
get redefined once rather than edited per site. The real hand-work is ~60 sites
(`__asm__` + `do_if_*`).

That's the good news. The bad news is in §7.

---

## 2. Toolchain

cc65 has no 65816 target, and neither does llvm-mos — so the Famidash 2.0 branch doesn't
help here either.

| Option | Verdict |
|---|---|
| **Calypsi C (65816)** | **Recommended.** Modern C99/C11, good codegen, real optimizer, handles a codebase this size. Free for non-commercial. |
| PVSnesLib (tcc-65816) | Popular, batteries included, but tcc-65816 is old and fragile. This codebase leans hard on compiler behavior; expect to fight it. |
| ca65/ld65 (65816 mode) | ca65 *does* assemble 65816 — useful for porting the `.s` files in-toolchain, but you'd be mixing ABIs with whatever C compiler you pick. |
| WLA-DX | Fine assembler, no C story. |

The `__fastcall__` / `__A__` / `__EAX__` argument-passing convention is cc65-only and does
not survive. Every shim entry point needs a new prototype under the new compiler's ABI.
This is mechanical but touches every signature in the four headers.

---

## 3. The central design problem: 8-bit tile writes → 16-bit tilemap entries

This is the thing that decides whether the shim thesis works, so it goes first.

**NES:** nametable byte = tile index. Palette lives separately in the attribute table,
one palette per 16×16 px area.

**SNES:** tilemap entry is 16 bits — `vhopppcc cccccccc` — 10 bits tile, 3 bits palette,
1 priority, 1 H-flip, 1 V-flip. **Palette is per tile entry. There is no attribute table.**

So every `one_vram_buffer(tile, addr)` (210 call sites) must become a 16-bit write, and the
shim has to know the palette at write time.

### The shortcut that does NOT work

Baking a `tile index → palette` lookup table would let all 210 sites stay untouched. I
checked whether the art allows it:

```
metatiles defined:            256
distinct bg tiles used:       235
tiles used with >1 palette:    47   ← 20%
```

e.g. `BLOCK` and `FAKE_BLOCK` are both `$20,$21,$30,$31` — same tiles, PAL_0 vs PAL_1.
`$00` alone appears under PAL_0, PAL_2 and PAL_3. So a global lookup is out.

### What actually works

Split the write paths, because they have different palette knowledge:

**Path A — level rendering** (`draw_screen`, `unrle_next_column`, `load_ground`, the
metatile system). This path already has the palette: `metatiles.s` exports
`_metatiles_attr`, a per-metatile palette byte, right alongside `_metatiles_top_left` etc.
The SNES renderer reads it and emits correct 16-bit entries. **No ambiguity, no tile
duplication, no art changes.**

**Path B — text/HUD/menus** (`draw_padded_text`, `printDecimal`, `display_attempt_counter`,
and the menu `.c` files writing charmap tiles). These write bare tile indices, but always
with a known palette for the context. Add a `shim_set_palette(n)` global that the shim ORs
into entries; set it when switching menu/HUD context. A handful of sites, not 210.

**Consequence:** all writes targeting attribute-table addresses (`$23C0-$23FF` and friends)
become **no-ops and must be deleted**. `get_at_addr()` becomes dead code. This audit is a
required work item, not optional — leaving them in means garbage tilemap writes.

---

## 4. Function-by-function mapping

### 4.1 Palette — `pal_*`

`nesdash.h` already routes palette through `PAL_BUF_RAW[32]` (NES indices) and `PAL_BUF[32]`
(brightness-mapped), flushed when `PAL_UPDATE` is set. Keep that exact structure; change
what `PAL_BUF` holds.

| NES | SNES | Notes |
|---|---|---|
| `pal_col(i, c)` ×72 | `PAL_BUF_RAW[i]=c; PAL_BUF16[i]=nes2snes[c]` | Macro rewritten once, **72 sites unchanged** |
| `pal_all/bg/spr` ×26 | CGRAM DMA | Sprite palettes live at CGRAM 128+ |
| `pal_set_update()` ×20 | flag → CGRAM DMA in vblank | Direct |
| `pal_clear()` | fill black | Direct |
| `pal_bright(0..4)` ×5 | **INIDISP `$2100`** brightness 0-15 | Free in hardware, and 16 steps vs 9 — smoother |
| `pal_bright(5..8)` (toward white) | color math: `CGADSUB $2131` + `COLDATA $2132` | **No direct equivalent**, see §7 |
| `pal_fade_in/out` ×17 | drives INIDISP over frames | Direct |
| `colBrightness` / `oneShadeDarker` | keep NES table, apply pre-conversion | Direct |
| `color_emphasis()` / `gameboy_check()` | **no hardware equivalent** | Apply tint during RAW→CGRAM conversion; see §7 |

One-time asset: a 64-entry NES-index → 15-bit BGR table.

### 4.2 PPU state

| NES | SNES |
|---|---|
| `ppu_off()` ×11 | `INIDISP = $80` (forced blank) |
| `ppu_on_all()` ×26 | `INIDISP = brightness`, `TM $212C = BG1\|BG2\|BG3\|OBJ` |
| `ppu_on_bg/spr()` | `TM` bits |
| `ppu_mask(m)` ×1 | `TM`/`TS`; the `MASK_EDGE_*` bits have no SNES analogue — drop them |
| `ppu_wait_nmi()` ×25 | wait on NMI flag / `RDNMI $4210` |
| `ppu_system()` | `$213F` bit 4 (PAL/NTSC) |

### 4.3 VRAM buffer system — the biggest surface (~300 sites)

Keep the buffer **format and API identical**. Only the NMI-time consumer changes: instead
of streaming bytes to `$2007`, it writes words to `$2118/$2119` (or DMAs).

| NES | SNES | Notes |
|---|---|---|
| `one_vram_buffer` ×210 | word write, palette per §3 | Format unchanged |
| `one_vram_buffer_horz_repeat` ×59 | **fixed-source DMA** | One DMA per run — faster than NES |
| `multi_vram_buffer_horz` ×30 | DMA, `VMAIN` +1 word | |
| `multi_vram_buffer_vert` | DMA, `VMAIN` +32 words | `VMAIN $2115` has a native +32 mode = exactly one tilemap row stride. Column writes become **a single DMA.** |
| `vram_adr` / `vram_put` ×24 | `$2116` / `$2118` | Already macros in `nesdash.h` |
| `vram_unrle` ×23 | decode → WRAM staging → one DMA | Rewrite of `lz.s`; can't stream to VRAM byte-wise efficiently |
| `vram_fill` ×3 | fixed-source DMA | |
| `vram_write` / `vram_read` | DMA | VRAM reads need the prefetch dummy-read quirk |
| `get_ppu_addr(nt,x,y)` | tilemap word address | Direct |
| `get_at_addr(nt,x,y)` | **DELETE — obsolete** | See §3 |
| `set_/clear_vram_buffer`, `flush_vram_update2` | direct | |

### 4.4 OAM / sprites

SNES OAM: 128 sprites, 4-byte low table + 2-bit high table (X bit 9, size select). Keep a
544-byte shadow in WRAM, DMA to `$2104` each vblank.

| NES | SNES | Notes |
|---|---|---|
| `oam_spr(x,y,tile,attr)` ×39 | bit-remap attr | NES `pp?vhb` → SNES `vhoopppN`. Pure remap in shim. |
| `oam_clear()` ×35 | fill shadow with Y=224 | |
| `oam_meta_spr` / `_flipped` / `_disco` | same, over shadow | |
| `bank_spr(n)` ×1 | `OBSEL $2101` sprite tile base | |
| `oam_set/get`, `oam_clear_player` | direct | |

**Wins:** 64→128 sprites, 8→32 per scanline. Any flicker/cycling logic becomes dead weight
(`load_next_sprite`, `check_spr_objects` in `nesdash.s` — leave them working initially,
simplify later).

**Cost:** SNES OBJ is *always* 4bpp. NES 2bpp sprite art converts with upper planes zeroed —
2× VRAM per sprite tile, but it means sprites can later use 16 colors for free.

### 4.5 Scroll

| NES | SNES | Notes |
|---|---|---|
| `set_scroll_x` ×16 | `BG1HOFS $210D` (write twice) | |
| `set_scroll_y` ×15 | `BG1VOFS $210E` | |
| `calculate_linear_scroll_y` | **becomes identity** | See below |
| `cap_scroll_y_at_top/bottom`, `seam_scroll_y`, `min_scroll_y` | mostly obsolete | |
| `split(x)` / `xy_split(x,y)` | **HDMA to `$210D`/`$210E`** | See below |

**`calculate_linear_scroll_y` disappears.** It exists because NES nametables are 30 tiles
(240px) tall, so vertical scroll wraps at 240, not 256 — hence the "nonlinear" conversion and
all the seam handling. SNES tilemaps are 32×32 tiles and wrap at 256 naturally (or use
64×64). That whole class of bug goes away.

**`split()` gets strictly better.** The NES version needs a sprite-0 hit and — per neslib's
own comment — *burns every CPU cycle between the call and the split point*. HDMA costs
~18 master cycles per channel per scanline and zero CPU involvement. This frees real frame
time.

### 4.6 Parallax — the single biggest win

Current implementation, `reset_level.h:184`:

```c
if (!no_parallax) mmc3_set_1kb_chr_bank_2(parallax_scroll_x + GET_BANK(PARALLAX_CHR));
```

and in `CONFIG/mmc3-huge.cfg:283`:

```
PARALLAXCHR: start = $0000, size = $24000, ... bank = $70;
```

`$24000` = **147,456 bytes — 144KB of pre-shifted CHR**, one 1KB bank per horizontal
sub-position, because the NES can't scroll a background layer independently.

**[ROM-verified]** All 144 banks are present at 1KB-bank index 112 and all 144 are
*distinct* — it really is 144 pre-shifted phases, not padding.

On SNES the parallax is **BG2 with its own `BG2HOFS` register.**

- 144KB of ROM → ~1-2KB of tiles
- `parallax_scroll_column`, `increase_parallax_scroll_column`, the 3-tile stagger scheme,
  the per-frame CHR bank write → **one register write per frame**
- The parallax gains free sub-pixel-smooth scrolling it doesn't currently have

### The same trick runs at tileset level too

`_set_tile_banks` in `LIB/asm/neslib.s` offsets the spike/block/saw banks by
`parallax_scroll_x & 1`, and `space_defines.h` spaces the tileset constants by 2
(`SPIKESA 0, SPIKESB 2, …`). Each `.chr` in `GRAPHICS/Level Tiles/` is 2KB holding **two
1-pixel-offset phases** of the same art — tile `$00` is a `10101010` dither (the sky
texture), and the second phase shifts it by one pixel. **[ROM-verified]** for all 9
tilesets.

So the background dither costs 2× CHR on top of the parallax's 144KB. On SNES both
collapse into a scroll register, and the tileset halves merge back into one copy.

A knock-on: because bank 2 holds *either* parallax *or* slopes (`neslib.s` picks between
them on `no_parallax`), levels currently cannot have both. On SNES they can — separate BG
layer, no aperture contention.

### 4.7 Banking → addressing + VRAM residency

| NES | SNES |
|---|---|
| `mmc3_set_prg_bank_0/1` | **Gone.** 65816 long addressing sees all 8MB. |
| `crossPRGBankJump*` ×100 | Plain `JSL`. Redefine macro; sites unchanged. |
| `CODE_BANK_PUSH` ×53 | Linker section placement. |
| `GET_BANK(sym)` ×26 | Compiler-provided bank byte. |
| `mmc3_set_*_chr_bank` | **Replaced by VRAM residency management.** |

CHR bankswitching is the conceptual shift. Instead of swapping 1KB/2KB windows into an 8KB
aperture, you decide what lives in 64KB VRAM and DMA changes during vblank:

- Gamemode/icon swaps (`state_game.h:300-304`) fire at portals — a discrete event. Check
  residency, DMA if absent.
- Deco animation (`state_game.h:151-152`) swaps its two phases every frame; the
  SNES port transfers only the 1600-byte region that differs between them
  each frame, against a ~6KB/vblank budget. Comfortable.

ExHiROM caps at 8MB; Huge Man's 2.3MB fits with room.

### 4.8 IRQ table → HDMA

`mapper.h` defines a little bytecode the MMC3 scanline IRQ handler interprets:

```
irqtable_ppuctrl $f0   ppustatus $f1   hscroll $f5   ppuaddr $f6
irqtable_chr0..5 $f7-$fc                wait $fd   timedwait $fe   end $ff
```

Every one of these maps onto HDMA, which is a better fit than the NES mechanism:

| Opcode | SNES |
|---|---|
| `hscroll` | HDMA → `BG1HOFS $210D` (word mode matches the write-twice register) |
| `ppuaddr` | HDMA → `BG1SC $2107` (tilemap base) |
| `ppuctrl` | HDMA → `BG12NBA $210B` (character base) / `$2107` |
| `chr0`–`chr5` | Usually **unnecessary** (everything resident); else HDMA → `$210B` |
| `wait` / `timedwait` | **Native** — HDMA line counts encode this |
| `end` | Native — table terminator |

`mapper.s`'s 376 lines plus the IRQ interpreter collapse into an HDMA table builder, and the
per-scanline CPU cost drops to zero.

API preservation: `set_irq_ptr` / `write_irq_table` / `edit_irq_table` keep their signatures;
the shim translates the table into HDMA tables. `is_irq_done()` can return "done"
unconditionally — HDMA has no such race.

### 4.9 Input

| NES | SNES |
|---|---|
| `pad_poll(pad)` | auto-joypad read `$4218/$4219` |
| `struct pad` (hold/press/release bitfields) | **unchanged** — only the fill changes |
| `PAD_*` constants | remap bit order; 12 buttons available, 8 needed |
| `__VS_SYSTEM` select/start swap | **drop this variant entirely** |
| `mouse.h` | **SNES Mouse is real hardware** — menu mouse support survives, retargeted |

### 4.10 Misc — ports as-is

`get_frame_count`, `seed_rng`, `newrand`, `set_rand`, `check_collision`, `delay`, `hexToDec`,
`printDecimal`, `draw_padded_text`, `display_attempt_counter`, `update_level_completeness`,
`increment_attempt_count` — pure logic or vram-buffer producers. They follow the shim with no
changes of their own.

`memcpy`/`memfill` → keep, or use WRAM DMA (`$2180`) for large moves.
`gray_line()` (debug) → drop or reimplement via mid-frame `COLDATA`.
`playPCM` → **strict upgrade**: currently *hangs the game* until the sample finishes; on
SPC700 it's fire-and-forget.

---

## 5. Asset pipeline

**Tile format.** NES 2bpp CHR is 8 bytes plane 0 then 8 bytes plane 1. SNES 2bpp is
row-interleaved: `p0row0, p1row0, p0row1, p1row1, …`. **NES → SNES 2bpp is a pure byte
interleave** — a ~20-line converter. SNES 4bpp = that same 16 bytes, then planes 2/3
interleaved in the next 16.

**Recommended first target: Mode 0.** Four 2bpp BG layers, each with its own palettes. This
matches NES bit depth *exactly*, so the first milestone can be pixel-faithful with zero art
changes:

- BG1 = level
- BG2 = parallax
- BG3 = HUD
- BG4 = spare

Then move to **Mode 1** (BG1/BG2 4bpp, BG3 2bpp) when the art gets upgraded to 16 colors.

**VRAM budget, Mode 0** (64KB total):

| Item | Size |
|---|---|
| BG1 tilemap 64×32 | 4KB |
| BG2 tilemap 32×32 | 2KB |
| BG3 tilemap 32×32 | 2KB |
| Level tiles (1024 @ 2bpp) | 16KB |
| Parallax tiles | 1KB |
| Font | 4KB |
| Sprite tiles (256 @ 4bpp) | 8KB |
| **Total** | **~37KB** |

Comfortable headroom. Note the **1024-tile ceiling per BG** (10-bit index) — larger than any
single NES CHR bank, but smaller than the game's total tile pool, so tilesets still stream
per *level* rather than per *scanline*.

**Vblank DMA budget:** NTSC vblank ≈ 38 lines ≈ **~6.3KB**. Per frame: column update 64B,
CGRAM 512B worst case, OAM 544B, deco 2KB every 16th frame. Fits. Level loads use forced
blank for full-frame DMA (~44KB).

**Levels.** The 35MB in `LEVELS/` and the Python exporters (`export_levels.py`, `aart_lz.py`)
keep their format; retarget the emitter. Level data is not the problem.

---

## 6. Audio — the separate project

`famistudio_ca65.s` is 7,655 lines of 2A03 driver. SNES audio is a physically separate
SPC700 CPU with 64KB private ARAM and a BRR sample-based DSP. FamiStudio has no SNES export.

**Recommended: an SPC700 driver that synthesizes NES APU voices, consuming existing
FamiStudio data.** This preserves all 37MB of music *and* the authoring pipeline your
musicians already use — no re-authoring, no forked music workflow for future songs.

| NES channel | SPC700 voice |
|---|---|
| Pulse 1, 2 | 16-sample looped BRR squares, 4 duty variants, pitch via `VxPITCH` |
| Triangle | 32-sample BRR loop — reproduces the 4-bit quantization *exactly* |
| Noise | Hardware noise (`NON`, 32 rates). NES "short mode" (93-step LFSR) needs a sampled BRR loop to be faithful |
| DPCM | BRR directly — **native, and higher quality than the original** |
| — | 3 voices left over for SFX |

Sequencer placement: port FamiStudio's song interpreter to SPC700 and upload song data to
ARAM. Budget: driver ~4KB + samples ~2-8KB leaves ~50KB for song data; upload per song at
level start. Note most of that 7,655 lines is APU-register code and conditional assembly for
expansion chips you don't use — the sequencer core is more like 1,500-2,000 lines.

**Fallback if that's too much:** run the sequencer on the 65816 and push register writes
through the `$2140-$2143` mailbox each frame. Much less work, meaningfully less elegant,
bandwidth-tight but workable.

**Bonus:** the SPC700 runs at 1.024MHz *regardless of region*, so the PAL/NTSC pitch split
vanishes — `LIB/asm/NoteTables/famistudio_note_table_pal_*` become unnecessary. Only tempo
differs.

This is the **highest-risk item in the project** and the one I'd prototype earliest, ideally
in parallel with M1 rather than after it.

---

## 7. No clean equivalent — the honest list

1. **Attribute-table writes and `get_at_addr()`.** Obsolete on SNES. Requires an audit-and-
   delete pass; leaving them in produces garbage tilemap writes. See §3.
2. **Tiles reused across palettes (47 of 235, 20%).** Kills the zero-effort lookup shortcut.
   Solved by the metatile-attr path, but it's *why* the level renderer must be rewritten
   rather than shimmed.
3. **Color emphasis / `gameboy_check()`** — 9 tint modes with no SNES hardware analogue.
   Reimplement as a tint applied during RAW→CGRAM conversion (cheap; `gameboy_mode` changes
   rarely).
4. **`pal_bright()` values 5-8** (fade toward white). INIDISP only goes normal→black.
   Fading to white needs color math with a fixed white via `CGADSUB`/`COLDATA`. Two-path
   implementation.
5. **Cycle-counted raster effects.** `timedwait` implies NES-CPU-cycle-exact timing. HDMA is
   scanline-locked so most of this is *easier*, but anything genuinely cycle-counted must be
   re-derived rather than translated.
6. **cc65 calling convention.** `__fastcall__`/`__A__`/`__EAX__` don't survive; every shim
   prototype is rewritten. Mechanical, but it's all four headers.
7. **The ~60 hand-written 6502 sites** (`__asm__` ×39, `do_if_*` ×21). `do_if_*` is pure
   6502-flag hacking with no portable form. These are real rewrites.
8. **DMC DMA glitch workarounds** in neslib — irrelevant on SNES, delete.
9. **`__VS_SYSTEM` builds** — drop.

---

## 8. Staged plan

| # | Milestone | Proves |
|---|---|---|
| ~~**M0**~~ | ~~One static screen rendered from **real level data**~~ **DONE** — see [M0_RESULTS.md](M0_RESULTS.md) | Tile converter, palette converter, level decoders, tilemap builder |
| **M1** | Shim core: palette + vram buffer + OAM + scroll + input. Cube mode, one level, playable, **silent** | **Go/no-go gate on the whole thesis** |
| **M2** | Column streaming + HDMA; parallax on BG2; IRQ-table→HDMA translation | Full scrolling at speed |
| **M3** | All gamemodes + menus | Mostly free if M1 is right — menu `.c` files are pure vram-buffer users |
| **M4** | SPC700 driver + FamiStudio data converter | *Start prototyping during M1* |
| **M5** | All level sets, all icons, VRAM residency manager | Content breadth |

**M1 is the honest decision point.** If the shim holds — if `SAUCE/` compiles against
`LIB/snes/` with only the §7 items hand-fixed — then M2/M3 are mostly mechanical breadth and
the port is a matter of grinding. If it doesn't hold, you've learned that for the cost of one
milestone instead of the cost of the project.

---

## 9. Recommendation

Do M0 and M1 before committing to anything else, and prototype the SPC700 driver alongside
M1 rather than deferring it to M4 — it's the item most likely to change the overall verdict.

Be clear-eyed about maintenance: this is a second platform against a tree that currently
ships seven NES variants from one build. The shim architecture is what keeps that from
becoming two projects — it is worth paying for properly rather than working around.
