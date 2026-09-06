# M1 progress

M1 is the go/no-go gate: shim core (palette, vram buffer, OAM, scroll, input), cube mode,
one level, playable, silent.

## Step 1 — display-only ROM — **done**

A real 32KB LoROM SNES ROM that DMAs the M0-converted assets into VRAM/CGRAM and displays
one static screen of Stereo Madness in BG mode 0.

**No new toolchain was needed.** The scope doc assumed a 65816 C compiler (Calypsi) was the
first blocker. It isn't — for a display-only ROM there's no C to compile, and the game repo
already ships `BIN/ca65.exe`, which assembles 65816 via `--cpu 65816`, plus `BIN/ld65.exe`
to link it. A hand-written LoROM linker config was all that was missing.

Calypsi (or equivalent) is still required for M1 proper, since that's where `SAUCE/` starts
compiling. But it is *not* a prerequisite for getting pixels on screen.

### Verification

The software SNES PPU in `snes_m0.py` and Mesen2's SNES emulation were both pointed at the
same `out/bg1.*.bin` binaries:

```
software PPU : (256, 224)
mesen2 SNES  : (256, 224)

EXACT MATCH - 57344 / 57344 pixels identical
```

Non-degenerate: 4 distinct colours at 50.9% / 46.5% / 1.8% / 0.8%, identical in both. Mesen2's
15-bit→RGB expansion also agrees with the converter's `(v<<3)|(v>>2)`.

This closes the loop on M0. The converters are correct, the software PPU is correct (now
validated against real emulation, not just eyeballed), and the ROM displays exactly what the
pipeline predicted.

### What was built

```
src/main.s          65816: SNES init, three DMAs (CGRAM, tiles, tilemap), mode 0, BG1 on
src/lorom.cfg       ld65 config - 32KB LoROM, cartridge header at $FFB0, vectors at $FFE0
tools/build_rom.py  ca65 -> ld65 -> checksum patch
tools/shot.lua      Mesen2 --testrunner headless screenshot
tools/compare_rom.py software PPU vs Mesen2 pixel diff
```

VRAM layout: tiles at word `$0000` (256 tiles, 2bpp, 4KB), BG1 tilemap at word `$1000`
(32×32 entries, 2KB). `BG1VOFS` is set to −1 so tilemap row 0 lands on screen line 0.

### Build

```bash
python tools/snes_m0.py --root C:\famidash --outdir out --col-start 140 --columns 16
python tools/build_rom.py --root C:\famidash
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes.sfc tools\shot.lua
python tools/compare_rom.py
```

### Two bugs worth remembering

Both were caught before first run and are easy to repeat:

1. **The SNES vector table is not laid out the way it's usually written down.** Native NMI is
   at `$FFEA` and native IRQ at `$FFEE`; emulation RESET is `$FFFC`. An intuitive
   "reserved, COP, BRK, ABORT, NMI…" ordering from `$FFE0` is shifted one word and boots into
   garbage.
2. **`.sizeof()` does not work on `.incbin` labels** in ca65 — a plain label carries no size
   attribute. Use an explicit end label and subtract.

## Step 2 — column streaming + hardware scroll — **done**

A 256KB LoROM that scrolls through the whole of Stereo Madness, streaming one tilemap column
at a time into a 64×32 BG1 map while driving `BG1HOFS`. This is the SNES replacement for
`draw_screen` / `unrle_next_column`.

**The column write really is one DMA.** `VMAIN` can auto-increment the VRAM address by 32
words, which is exactly one tilemap row stride, so a 32-entry column is a single 64-byte
transfer rather than a per-tile write loop. This was the concrete claim in §4.3 of the scope
doc and it holds.

### ROM layout

```
bank $00        code, tiles, CGRAM, header, vectors
banks $01-$04   1796 tile columns x 64 bytes, bank-aligned
banks $05-$07   padding to 256KB
```

Columns are padded to whole banks because SNES DMA increments the A-bus address *within* a
bank and does not carry into the bank byte — a record straddling a bank boundary would read
garbage. Column *n* lives at bank `$01 + n/512`, offset `$8000 + (n%512)*64`, and goes to map
slot `n & 63`.

### Verification

`tools/verify_scroll.py` runs Mesen2 headless once per sample frame, dumps VRAM, and checks
every visible tilemap slot against the level data:

```
  frame    60  scroll_x=   240  col=   30  cols_done=   63  1024 words checked  OK
  frame   600  scroll_x=  2400  col=  300  cols_done=  333  1024 words checked  OK
  frame  1800  scroll_x=  7200  col=  900  cols_done=  933  1024 words checked  OK
  frame  2400  scroll_x=  9600  col= 1200  cols_done= 1233  1024 words checked  OK
  frame  3600  scroll_x= 14096  col= 1762  cols_done= 1796  1024 words checked  OK

11264/11264 tilemap words correct across 11 frames
```

Scroll advances at exactly 4px/frame and clamps at the level end
(`14096/8 + 34 = 1796` columns).

### Why VRAM and not screenshots

Step 1 verified rendering by pixel-diffing a Mesen capture. That does **not** work for a
moving image here: Mesen's `--testrunner` `takeScreenshot()` is not frame-deterministic. Two
runs stopped at the same frame return different images depending on what else the Lua script
did — adding an `emu.getState()` call changed the captured frame, and a script taking six
screenshots produced a different "frame 600" than one taking a single screenshot.

This cost real time before it was identified, so: **do not pixel-diff captures of a moving
scene under `--testrunner`.** VRAM contents are deterministic and are a stricter test anyway,
since they cover the rows below the 224-line display too. The rendering path itself is
already proven pixel-exact by the static ROM (`tools/compare_rom.py`).

### Two more bugs worth remembering

1. **Zero-page aliasing between a loop and its callee.** `stream_columns` kept its target
   column count in `tmp`; `write_column` used `tmp` as scratch. Depending on which map screen
   a column landed in, the loop either stopped after one column or ran away writing up to
   1024 columns in a single NMI — pushing DMA into active display and corrupting VRAM. The
   fix is separate variables plus a hard per-vblank budget (`VBLANK_COL_BUDGET`), so a logic
   error can never again run DMA past vblank.
2. **Verifying more than the ROM promised.** The first sweep flagged ~30 wrong words, all in
   column `== cols_done` — the write-ahead column that legitimately is not streamed yet and
   is not on screen. The check now counts only genuinely visible columns
   (32, plus one when the scroll is not tile-aligned).

## Next

Step 3 is the toolchain decision — Calypsi or equivalent — at which point `SAUCE/` starts
compiling and the shim thesis gets its real test. Everything so far has been assembly only.

Still not wired: the ground layer (`load_ground`, `grounddata.h`) and vertical scrolling.
Both belong with the M1 renderer.
