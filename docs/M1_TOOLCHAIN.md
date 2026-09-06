# M1 step 3 — C toolchain and the shim

## Result

**The Famidash gameplay core compiles to 65816 machine code.** Collision, X movement, and all
six gamemodes, built against the shim headers:

```
-O 0  ->  103,518 byte object    0 errors, 0 ICEs
-O 1  ->   95,413 byte object
-O 2  ->   98,342 byte object
```

8,641 lines of 65816 assembly, using long addressing and reading the split lo/hi physics
tables that the ported `lohi_arr16_load` produces:

```asm
cube_movement:
            lda     long:currplayer_table_idx
            and     ##255
            tax
            lda     long:CUBE_MAX_FALLSPEED_lo,x
            ...
            sta     long:tmpfallspeed
```

The shim thesis holds. Getting here needed one real porting change beyond the shim — see
"Computed goto" below.

Codegen quality at `-O 1` is mediocre (the `lda long:x / and ##255 / tax` sequence repeats
rather than being reused, a consequence of integer promotion on `uint8_t`). That is a tuning
problem for later, not a blocker.

## Toolchain

Calypsi 5.18 for 65816, from the vendor's official repo
(`github.com/hth313/Calypsi-tool-chains`, release 5.18, linked from calypsi.cc).
`calypsi-65816-5.18.zip`, 137.9 MB, extracted to `C:\toolchains\calypsi` — a zip, so nothing
is executed on install. No license key was needed.

```
cc65816.exe   ISO C compiler      as65816.exe   assembler
ln65816.exe   linker              nlib.exe      librarian
db65816.exe   debugger
```

Note the argument syntax differs from cc65: optimisation is `-O 2`, not `-O2`, and an
unrecognised option makes the compiler exit with a *usage* message rather than an error — see
the correction note at the bottom of this file.

## What the shim covers

`shim/include/` reimplements the NES hardware API with identical signatures so `SAUCE/`
compiles unchanged:

| Header | Notes |
|---|---|
| `arr_macros.h` | The 6502 hand-optimised indexing rewritten as portable C. Only 7 of ~38 macros are actually used by the game (`idx8_store` 85 sites, `idx8_load` 50, `lohi_arr16_decl` 17, `idx8_inc` 12, `idx8_dec` 7, `ind16BE_load_NOC` 4, `idx16_load_hi_NOC` 3); the rest are unreferenced and were not carried over. Data layout is preserved exactly — 16-bit arrays stay little-endian pairs, `lohi_*` keeps the split byte planes, and `ind16BE_*` really is big-endian. |
| `neslib.h` | Palette, PPU state, OAM, input, VRAM, scroll. |
| `nesdoug.h` | VRAM buffer, scroll helpers. **`get_at_addr()` is deliberately omitted** so any surviving attribute-table use is a compile error rather than a silent garbage write. |
| `nesdash.h` | Where most of the cc65 dialect lived. `crossPRGBankJump*` → a plain call, `CODE_BANK_PUSH` → linker placement, `GET_BANK` → linker bank byte, `do_if_*` → ordinary C conditionals. Redefining these is what keeps ~180 call sites untouched. |
| `mapper.h` | No mapper. PRG banking gone, CHR banking → VRAM residency, scanline IRQ → HDMA. |

`famidash.h` — the game's entire global state, ~15KB — compiled clean on the first attempt
with no changes at all.

## Source changes actually needed

Far smaller than the raw grep counts suggested. Held in `overlay/`, which shadows `SAUCE/`
on the include path, so **the game repo is not modified**:

**`gamemodes/gamemode_cube.h` — 2 sites.** Both are the same cc65 register-pressure
workaround, and the comment above each already states the intent:

```c
// robotjumptime[currplayer] = ROBOT_JUMP_TIME[framerate]
__A__ = ROBOT_JUMP_TIME[framerate], __asm__("pha");
idx8_store(robotjumptime, currplayer, (__asm__("pla"), __A__));
```

becomes exactly what the comment says:

```c
idx8_store(robotjumptime, currplayer, ROBOT_JUMP_TIME[framerate]);
```

**`gamemodes/gamemode_spider.h` — forward declarations.** `spider_up_wait()` and
`spider_down_wait()` are called above their definitions. C99 rejects the implicit
declaration; cc65 only warned. The fix matches the convention `gamemode_cube.h` already uses.

**`functions/collision.h` — computed goto → switch.** See the next section.

That is the entire diff for the gameplay core: three files, all in `overlay/`.

## Computed goto — the one real porting change

`collision.h` dispatches its slope-collision handler through a **GCC computed goto**:

```c
static const void * const jumpTable[] = {
    &&col_default, ..., &&col_slope_RD45, &&col_slope_LD45, ...
};
...
goto *jumpTable[collision];
```

Address-of-label and `goto *expr` are a GNU extension, not standard C. Calypsi's clang-based
front end accepts them, but the 65816 backend cannot lower them and raises an internal
compiler error. Minimal reproducer, three lines:

```c
int c; int f(void){ void *p = &&a; goto *p; a: return 1; }
```

`overlay/functions/collision.h` replaces the dispatch with a `switch` that jumps to the same
labels in the same table order — 20 cases plus `default: goto col_default`. Every label body
is unchanged, the case values are the original array indices, and a generated check confirms
all 21 target labels are still present. Plain `goto` is standard C and compiles fine; only
the *computed* form is the problem.

This is worth carrying upstream regardless of the SNES port: the extension makes the NES
codebase dependent on GCC/clang-family compilers.

## The ICE investigation, and a wrong turn worth recording

Before the computed goto was identified, the ICE was characterised as follows — all of this
is still accurate and is why it took a while to find:

- **Deterministic** — 8/8 identical runs.
- **All 12 valid memory-model combinations** (code ∈ small/compact/large × data ∈
  small/medium/large/huge).
- **All optimisation levels**, and `--no-cross-call`, `--no-interprocedural-cross-jump`,
  `--no-inline`, and every `--force-switch` strategy.
- **Splitting the translation unit did not help** — `collision.h` alone still ICEd.
- **No single function triggered it**, which is what made it look cumulative.

That last point was misleading. Delta-debugging the *preprocessed* source reduced it to 38
lines, and the reduction pointed at a function-local array with an empty initializer:

```c
void f(void){ int jt[] = {}; }     /* also ICEs - but a different bug */
```

That is a genuine second Calypsi bug, but it was **an artifact of the reduction, not the
blocker**: the delta debugger had emptied the jump table's initializer, deleting the `&&label`
entries that were the actual cause. Checking the reduced result against the real source is
what caught it. Two separate ICE-triggering constructs, and the reducer found the wrong one
first.

Both are captured in `bugreport/` and both are worth reporting upstream.


## Byproduct: a real bug in the NES game

The stricter compiler found a live defect in `SAUCE/functions/collision.h:59`:

```c
case COL_FLOOR_CEIL:
    if (gamemode == gamemode == GAMEMODE_WAVE || gamemode == GAMEMODE_SNAKE) return 0;
```

This parses as `((gamemode == gamemode) == GAMEMODE_WAVE) || ...` — that is, `1 == 6` — so
the wave half is **always false and dead**. `GAMEMODE_WAVE` is `0x06`, `GAMEMODE_SNAKE` is
`0x0A`. Wave mode never gets the floor/ceiling early-out that snake mode gets. cc65 never
warned about this.

**Fixed upstream in the game repo** during this work. Note the fix changes wave-mode
collision behaviour, so it is worth re-checking level timings on the NES build.

## Correction

An earlier run of the memory-model matrix appeared to show `--code-model medium` compiling
cleanly. That was wrong: `medium` is not a valid code model, so the compiler exited with a
usage message, and the check — which counted `error:` lines — read the absence of errors as
success. The matrix now verifies that an object file was actually produced. There is no
memory-model that avoids the ICE.
