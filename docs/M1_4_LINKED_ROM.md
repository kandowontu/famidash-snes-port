# M1.4 — shim implementation, linked ROM, and working physics

> Resuming work? [HANDOFF.md](HANDOFF.md) has the current state and next task.

## Result

**There is a bootable SNES ROM that renders a real Famidash level and runs the
real Famidash physics correctly.** `out/famidash-snes-game.sfc`, 64KB HiROM.
The cube falls, lands, rests, and jumps, with velocities that match the game's
own physics tables exactly.

| | |
|---|---|
| Compiles | gameplay core + shim, 65816, 0 errors |
| Links | Calypsi `ln65816` with the shipped `snes-HiROM.scm` rules |
| Boots | Mesen2 runs it; valid header, reset vector, checksum |
| Renders | real Stereo Madness tilemap, correct palette, player sprite |
| Physics runs | `cube_movement()` executes every frame |
| Collision detects | `bg_collision_sub()` returns `COL_ALL` against real level data |
| Collision responds | `cube_eject()` zeroes `vel_y` and snaps the player to the surface |
| **Lands and stays landed** | 341 consecutive frames with `y` and `vel_y` both exactly constant |
| **Jumps** | B rises 34.3px and lands back at exactly the same height |
| Collision table | byte-identical to the shipping NES ROM's `metatiles_coll` |

Verify with:

```bash
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-game.sfc tools\verify_land.lua
```

Exit status is the result; the report is written to `out/land_verify.txt`.

## The physics is right, not just stable

Every number checks out against `SAUCE/defines/physics_table_defines.cmp.h` at
`currplayer_table_idx = 4` (framerate 1, no mini, gravity down):

| Quantity | Table | Measured |
|---|---|---|
| gravity per frame | `CUBE_GRAVITY[4]` = `0x006B` = 107 | `vel_y` steps by exactly +107 |
| terminal velocity | `CUBE_MAX_FALLSPEED[4]` = `0x0600` = 1536 | oscillates 1498 / 1605, i.e. ±107 around 1536 |
| jump velocity | `JUMP_VEL[4]` = `0xFA70` = −1424 | peak `vel_y` = −1424 |
| jump apex | Σ(1424 − 107k) ≈ 8763 (8.8 fixed) = 34.2px | 34.3px |

That the fallspeed "clamp" is really a ±gravity oscillation around the limit is
the game's own algorithm (`if (vel > fallspeed) accel = -accel`), not an
artifact of the port.

`framerate = 1` is correct for 60Hz, contrary to first appearances: index 4's
1536×60 equals index 0's 1843×50, so indices 0–3 are the 50Hz set.

## What the bug actually was

Not gameplay logic, and not the shim — **the compiler**.

`currplayer_vel_y` was stepping by a constant `-0x3900` per frame instead of by
`tmpgravity`. Calypsi 5.18 miscompiled `common_gravity_routine()`: the join
point after `switch (gravity_mod)` read `tmpaccel` with `lda 1,s`, from a stack
slot that nothing in the function ever writes, while the value was live in Y.
The slot held whatever the caller left on the stack — stable frame to frame,
which is why it looked like plausible-but-wrong physics rather than a crash.

Two more instances of the same defect were then found in the same file:

- `cube_eject()` — `currplayer_vel_y = currplayer_gravity ? 0xffff : 0` had both
  ternary arms discarded by `lda 1,s` at the join. **On a live landing path.**
- `cube_movement()` — the football charge clamp stored to `1,s` on one arm, left
  the value in A on the other, and read `3,s` at the join.

All three are worked around in `overlay/gamemodes/gamemode_cube.h` by writing
each merge out long-hand, so every branch does its own store and no value has to
survive the join. Full write-up and reproducer: [../bugreport/README.md](../bugreport/README.md).

`Generic.width/height` were a genuine second bug, fixed earlier: the collision
probes offset from `Generic.y` by `Generic.height` to find the player's feet,
and on the NES those come from `sprite_loading.h`, which is not in this build.
With height 0 every probe tested the wrong row. Necessary, but not sufficient —
the miscompilation was underneath it.

## Tooling added, because none of this was findable by inspection

| | |
|---|---|
| `tools/scan_stackslots.py` | detects the miscompilation in generated assembly; **runs as part of `build_game.sh`** |
| `tools/gen_addrs.py` | emits `out/addrs.lua` from the linker map |
| `tools/trace_fall.lua` | per-frame physics trace |
| `tools/verify_land.lua` | pass/fail check of falling, resting and jumping |
| `bugreport/make_repro.sh` | builds a translation unit that reproduces the defect |

Two build-script fixes were needed to make any of this trustworthy:

- **`build_game.sh` never regenerated `out/game.map`.** The map on disk was from
  an older manual link, so every hardcoded trace address was silently wrong.
  Adding `--list-file out/game.map` and generating `out/addrs.lua` from it means
  trace scripts can no longer drift. This cost a full debugging cycle on its own.
- `--assembly-source` is kept on the three hand-written units so the scan can run.

## The eight symbols the gameplay core actually needed

Linking `main()` + `cube_movement()` + `x_movement()` reported exactly eight
undefined symbols. That is the real size of the hardware surface for the physics
core:

```
add_scroll_y   bg_collision_sub   controllingplayer   framerate
min_scroll_y   mmc3_set_prg_bank_1   pad_poll   update_currplayer_table_idx
```

All are in `shim/src/shim_core.c`, ported from the NES originals rather than
reinvented:

- **`add_scroll_y`** — from `__add_scroll_y` in nesdoug.s. The low byte wraps at
  `0xF0`, not `0x100`, because it is a pixel offset inside a 240-pixel room. This
  wrap is **not** a NES PPU artifact that the SNES removes — the collision map is
  addressed in these units, so it stays.
- **`update_currplayer_table_idx`** — `idx = (framerate << 2) | (mini << 1) | (gravity >> 7)`.
  Note it uses only bit 7 of `currplayer_gravity`.
- **`bg_collision_sub`** — 4 pages of 256 bytes, one 240px room each;
  `index = (x >> 4) | (y & 0xF0)`, `page = room & 3`. Entries are metatile ids,
  mapped through `metatiles_coll`.
- **`pad_poll`** — SNES auto-joypad read. Directions/Start/Select map straight
  across; NES A accepts SNES B or A (bottom button is the natural jump), NES B
  accepts Y or X.

`famidash.h` *defines* its globals rather than declaring them — it is written for
a unity build — so it cannot be included from a second translation unit. The shim
declares what it needs `extern` instead.

## Build

```bash
python tools/snes_m0.py --root C:\famidash --outdir out --col-start 140 --columns 16
sh tools/build_game.sh
```

`tools/pack_hirom.py` pads the linker's raw output to a whole bank and patches
the SNES checksum.

## Still not wired

`x_movement()` is deliberately not called yet. It drives the constant rightward
run, and the collision map here is a fixed 16-metatile window, so the player
would immediately leave mapped ground. Horizontal travel needs the camera plus
collision-map streaming — that is M1.5.

## Three SNES bugs worth remembering

1. **Enabling NMI without a handler.** `snes-HiROM.scm` defines only the *reset*
   vector; NMI and IRQ point at whatever happens to sit in `$FFE0-$FFFB`. Setting
   `NMITIMEN = 0x81` crashed into garbage — the symptom was a black screen with
   `screenBrightness = 0` and `cpu.pc = 2`. Auto-joypad read does not need NMI,
   so the loop polls the vblank flag in `$4212` instead.
2. **Clearing only half of OAM.** OAM is 544 bytes: a 512-byte low table plus a
   32-byte high table holding X bit 9 and the size bit per sprite. Clearing just
   the low table left the high table full of power-on garbage, which showed up as
   coloured blobs scattered over the sky.
3. **Linker tree-shaking dropped the cartridge header.** Nothing references the
   header sections, so they were shaken out and the title read as zeros. Fixed
   with `.public` anchors plus `--root-symbol`.

## Toolchain notes

- Calypsi's linker needs a `.scm` memory description passed as an input file, and
  ships `linker-rules/snes-HiROM.scm` ready to use.
- `--output-format raw` writes the image to `<output>.raw` alongside the ELF at `-o`.
- Valid optimisation levels are `-O 0/1/2` — there is no `-O 3`.
- An unrecognised option makes both the compiler and linker exit with a *usage*
  message rather than an error, which is easy to misread as success when scripting.
