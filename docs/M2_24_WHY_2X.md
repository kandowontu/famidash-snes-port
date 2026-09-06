# M2.24 — The port executes twice the NES's instructions, and a quarter of them do nothing

The question was whether to reach for SA-1. The measurement says the SNES is not
the constraint: at the same sprite load the port executes **about twice** the
instructions the NES does for the same work, on a CPU with twice the clock — and
**25% of them are accumulator width switches that compute nothing**.

---

## 1. The comparison

`sprite_collide`, instructions per call, bucketed by active sprite slots so the
two machines are doing the same work (traps 102 and 106):

| | NES (cc65, 6502) | SNES port (Calypsi, 65816) | ratio |
| --- | --- | --- | --- |
| fixed cost, 0 active | 216 | 412 | **1.9x** |
| marginal, per active sprite | 21.0 | 42.3 | **2.0x** |

And the same routine in time, from the earlier scanline measurement:

| | NES | SNES port |
| --- | --- | --- |
| fixed, 0 active | 36.0 scanlines | 51.3 |
| marginal, per active sprite | ~1.1 | ~3.1 |

Both machines run 262-line frames at 60Hz, so scanlines compare directly. Put the
two together: **2x the instructions, and each instruction is slower on average
too** — the SNES's 2x clock is spent paying for the extra instructions rather
than getting ahead.

`tools/profile_collide.lua` is the SNES side; the NES side is the same shape
against `Famidash - Huge Man.nes` and `.dbg`.

## 2. What the extra instructions are

Static mix of `sprite_collide` as Calypsi compiles it:

| | share |
| --- | --- |
| `long:` 24-bit accesses | 28.3% |
| arithmetic, branches, everything that works | 28.1% |
| **`rep`/`sep` accumulator width switches** | **25.0%** |
| register moves | 15.4% |
| stack slots | 3.1% |

**130 of 519 instructions are `rep`/`sep`.** They exist because the game's
variables are `uint8_t` and the arithmetic around them is 16-bit, so the
compiler flips the accumulator width back and forth around almost every access.
The 6502 has no such concept, which is most of where the 2x comes from.

The 28% `long:` accesses are the second factor: bank `$7E` costs 4 bytes of
instruction and 32 master cycles where absolute in bank 0 would cost 3 and 26,
and direct page 2 and 20. The NES reaches the same arrays with absolute
addressing at 4 cycles.

## 3. So: SA-1, or fix the code?

SA-1 is a 10.74MHz 65816 — 3x the clock, and it would certainly clear the
budget. But it is the wrong first move here, for a reason the numbers make
plain: **the port is 2x off on instruction count against a CPU that is already
2x faster.** Adding a third CPU to run twice as many instructions as necessary
buys speed while leaving the cause in place, and it is not a small change:

* the SA-1 has its own memory map, its own vectors, and IRAM the S-CPU shares;
* game code has to run *on* the SA-1, with the S-CPU left doing DMA, OAM and
  the pads — so the shim's PPU layer and the game loop have to be split across
  two processors with a handshake between them;
* Calypsi has no SA-1 target, so the runtime is ours to build;
* it costs the port its "runs on a stock cartridge" property.

The software levers, in the order the measurements rank them:

1. **The `rep`/`sep` churn — 25% of instructions, doing no work.** The hot
   routines are already known (`shim_meta_run`, `draw_sprites`,
   `check_spr_objects`, `sprite_collide` are 80% of the frame). Hand-writing
   them in 65816, as `oam_spr.s` already is, removes the width switching
   entirely because the width becomes a choice rather than a consequence.
2. **`long:` → absolute or direct page.** The whole data set is 34KB, but 25KB
   of that is three shim buffers (`level_rle` 20KB, `col_ring` 2KB,
   `menu_rows` 1.4KB) that are walked by pointer and do not care. What is left
   is about 7KB — which fits bank 0, where `near` addressing works.
3. **Only then, SA-1**, if the frame still does not fit.

If (1) and (2) land what the measurement suggests, the sprite-heavy levels go
from ~80% of 60Hz to comfortably over 100% of the budget, on a stock cartridge.
SA-1 stays available and the reasoning for it would then be evidence rather
than a guess.

## 4. The compiler settings, measured

Calypsi defaults to `-O0` and to optimising for **space**, and the port had been
built `-O 1` with the default `--space` for its whole life. Measured over the
full run:

| | level 0 | `cycles` | level 12 | `xstep` |
| --- | --- | --- | --- | --- |
| `-O 1` (what ships) | 100.0% | 86.8% | 85.9% | 79.1% |
| `-O 2 --speed --no-cross-call` | 100.0% | **89.2%** | **91.0%** | **82.3%** |
| `-O 2`, cross-call ON | 97.9% | 75.7% | 68.2% | — |

Two things worth keeping:

* **Cross-call optimisation is a trap.** It replaces repeated code with
  subroutine calls - smaller, and 11-18 points slower on the heavy levels. It is
  on by default at `-O 2`. Static instruction counts hide this completely:
  `sprite_collide` shrinks from 519 instructions to 373 while getting slower,
  because the count does not include the subroutines it now calls.
* **`-O 2` miscompiles the ship.** `gamemode_ship.h` assigns `tmpgravity` in a
  four-way branch and then negates it conditionally; at `-O 2` the negation is
  skipped on the HOLD_FALL path, so holding while falling gives `+62` where the
  table says `-62`, on 100% of samples. `tools/verify_ship.lua` catches it. The
  three `scan_*.py` scanners do not - it is a fourth defect shape, and it is why
  `-O 1` still ships.

Five points is not worth wrong physics. But if the hot routines move to assembly
(lever 1 above), the C that remains is less exposed, and `-O 2 --speed
--no-cross-call` becomes worth revisiting with the ship branch restructured.
