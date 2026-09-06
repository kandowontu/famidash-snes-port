# M2.15 — the sprite budget

Stereo Madness now holds **60Hz outright**. The interesting part is the
measurement that got it there, and the headroom number, which is the honest
answer to "how many sprites can it take".

| | before | after |
|---|---|---|
| overall | 99.1% of 60Hz | **100.0%** |
| worst 300-frame window | 93.7% | **99.7%** |
| shim's share of sprite drawing | 67% | 53% |
| stress: 8 objects forced active (24 NES sprites) | — | 93.1% |
| stress: 12 objects forced active (29 NES sprites) | — | 63.7% |

```bash
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\verify_framerate.lua
STRESS_SLOTS=12 "C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-full.sfc tools\stress_sprites.lua
```

---

## Measure first: the shim was two thirds of it

"Roughly half of `draw_sprites` is the shim" had been an estimate all along.
`tools/profile_sprite_split.lua` makes it a measurement — it hooks each
function's *address range* and counts instructions executed inside it, which
needs no timing assumptions and no guesses about which callees are hot:

```
shim_meta_run   832        oam_spr   673        draw_sprites (body)   737
-> the shim was 67% of the cost of drawing sprites, not 50%
```

That is worth stating plainly because it inverted the plan. The game's per-slot
animation logic in `draw_sprites.h` looked like the expensive part and is not;
optimising it would have been effort spent on a third of the problem, against
`overlay/` code that is supposed to stay a port rather than a rewrite.

## Three changes, all "once per metasprite instead of once per sprite"

### 1. The position is now a single add

Sign-extending an 8-bit offset and adding it to the origin is a mask, a compare,
a branch and an add per axis. But sign extension of a zero-extended byte `v` is
`(v ^ $80) - $80`, so

```
px = x + sext(dx)  =  (dx ^ $80) + (x - $80)
```

— xor the byte, add a bias computed once per metasprite. The mirrored forms fold
the same way:

```
H:  px = x - dx - 8  =  (x + $78) - (dx ^ $80)
V:  py = y - dy      =  (y + $80) - (dy ^ $80)
```

so a flip only chooses which bias and whether it adds or subtracts. Two dozen
instructions per sprite became about six.

### 2. The OAM write is inline

It used to `jsl oam_spr`, which under Calypsi's convention means pushing three
stack words and popping them again, per sprite. `oam_spr` stays for the game's
own callers — `trail_loop`, `put_number`, the mouse cursor — and the walker does
the same eight stores itself.

### 3. The flip is hoisted

It was read from a global and tested twice per sprite, and it is constant for the
whole metasprite. It is now two direct-page values: `mflip16` (flip << 8, so a
16-bit `BIT` puts H in V and V in N) and `mflipb` (flip & $C0, to xor into each
attribute byte).

### And one in C

`check_spr_objects` read `y_lo`/`y_hi` for every slot before testing X. It runs
for all 16 slots every frame and most fail the X test, so that was two
long-indexed loads and their index setup thrown away per slot. Deferring them
took the function from 28-29 scanlines to about 20.

## The restructure that nearly went wrong

The walker reads the quadruplet and advances the pointer **before** the
off-screen checks. That is not an optimisation — those checks branch back to the
top of the loop, and advancing afterwards means a dropped sprite re-reads the
same quadruplet forever. The four reads cost the same either way; a dropped
sprite is rare.

The loop-backs are absolute jumps now (`jmp .word0 label`) rather than the
chained relay branches the previous version used. The body outgrew the ±127 a
relative branch reaches, and the relay approach had already produced one silent
failure: a relay placed in a fall-through path sent every sprite back to the top
before it was drawn, and OAM came out empty with no error anywhere.

## Verified, not assumed

The rewrite could not be checked against the previous build's OAM checksums,
because the cube's spin rate changed in the same session and the cube is on a
different rotation step at any given game frame. So the check moved to
*invariants* that hold regardless:

- `verify_gamemode_sprites.lua` compares the exact x positions and tile sets for
  all twelve gamemodes against `sprites.h`. Every one matches the values recorded
  before the rewrite — including the 4-pixel centre offset that makes the robot
  and spider sit at 72,72,80,80 rather than 80,80,88,88.
- It now also **forces an H-flipped cube frame**. The mirrored path is separate
  code — a different bias, and a subtract rather than an add — and with the spin
  rate corrected the sampled frames may never land on one, so leaving it to
  chance left the riskiest new code untested. It asserts the halves come out
  mirrored and 8 pixels apart.

## The headroom, measured

`tools/stress_sprites.lua` forces N of the 16 active-sprite slots on every frame
at positions spread across the screen, so `draw_sprites` walks all of them and
the walker does the most work the engine can ask of it:

| objects forced active | peak OAM | NES sprites | speed |
|---|---|---|---|
| 4  | 50 | 25 | 98.0% |
| 8  | 48 | 24 | 93.1% |
| 12 | 58 | 29 | 63.7% |
| 16 | 58 | 29 | 50.0% |

Stereo Madness peaks at 38 OAM entries — 19 NES sprites — and holds 100%. The
cliff is around **12 simultaneously active objects**, and at that load a frame
needs about 299 scanlines against the 262 it has:

```
music_update 5 | sprite_collide 95 | check_spr_objects 25 | draw_screen 13
| draw_sprites 116 | trail_loop 25 | vblank flush ~20
```

`draw_sprites` at 116 splits roughly 47 shim / 69 game, and `sprite_collide` at
95 is entirely game code.

There is a guard in the walker that returns immediately when OAM is already
full, so an overloaded frame does not compute sprites it cannot write. It did
**not** move the stress numbers — the peak is 58 entries against a 63-sprite cap,
so it rarely fires. It is a bound on the worst case, not an optimisation, and is
described that way because measuring it and reporting it as a win would have
been easy and wrong.

## What would move the cliff

**16x16 OBJ mode**, still. One 16x16 metasprite is four SNES 8x8 sprites today
and would be one: a quarter of the OAM entries, a quarter of the writes, and a
quarter of the per-scanline sprite load. On the numbers above that halves the
shim's 47 scanlines and pushes the cliff from ~12 objects to nearer 20.

The tile mapping it needs, worked out but not implemented. A SNES 16x16 sprite
at base `t` covers OBJ tiles `t`, `t+1`, `t+16`, `t+17`. Placing NES tile pair
`k` (tiles `2k`, `2k+1`) at

```
A(k) = (k & 15) + (k >> 4) * 32      NES 2k -> A(k),  NES 2k+1 -> A(k) + 16
```

puts pairs `k` and `k+1` side by side, so a 16x16 sprite at `A(k)` covers exactly
top-left, top-right, bottom-left, bottom-right. 128 pairs map into 256 tiles —
eight rows of sixteen pairs, each using two tile rows. At run time the base is
`k = chrnum >> 1`, then `(k & 15) + ((k >> 4) << 5)`; the 8x8 fallback for
metasprites that are not clean pairs is `A(k)` and `A(k) + 16`.

That is a change to `gen_sprchr.py`'s conversion (a permutation), the OAM
writer, OBSEL's size field and the size bit in OAM's high table — and it moves
every tile number, so `verify_sprite_chr.lua`, `gen_gamemode_expect.py` and
`verify_gamemode_sprites.lua` all need to follow.

Beyond that the remaining cost is `sprite_collide` and `draw_sprites.h`'s
per-slot loop, both ports of `SAUCE/` — a decision about what `overlay/` is for,
not an edit.
