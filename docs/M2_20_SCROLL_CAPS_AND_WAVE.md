# M2.20-M2.21 — the ball stops bouncing, and the wave starts moving

> Resuming work? [HANDOFF.md](HANDOFF.md) has the current state and next task.

Two defects, found from one report ("the ball bounces on the floor"). Neither was in
the ball.

## Result

```
verify_ball              RESULT: BALL RESTS ON THE FLOOR
verify_ship              RESULT: SHIP PHYSICS MATCHES THE TABLES
```

with, for the first time, the wave's tilt clamp actually covered:

```
wave tilt: 1958 frames correct (771 at the clamp)
wave vel_y is +/-CUBE_SPEED (doubled when mini) or 0 on all 1958 frames, 1711 of them moving
```

## 1. The scroll caps were half a port

`cap_scroll_y_at_top` and `cap_scroll_y_at_bottom` are declared in `LIB/headers/nesdash.h`
as *"caps the Y scroll at min_scroll_y"* and nothing else, and the shim implemented exactly
that. The 6502 bodies in `LIB/asm/nesdash.s` do three things:

| | |
|---|---|
| clamp | `scroll_y = min_scroll_y` / `0x2EF` |
| **compensate** | move `currplayer_y` and `player_y[1]` by the scroll that was discarded |
| **reset** | `scroll_y_subpx = 0` |

The compensation exists because `process_y_scroll` moves the camera and the players
*together*. When the camera is pinned at a limit, the players' half of that movement has to
be taken back — otherwise it survives while the scroll it was compensating for does not.

Without it the player drifted about **2px a frame**, for as long as the camera stayed at a
limit.

### Why the ball, and not the cube

`process_y_scroll` has two arms. The cube's arm only moves the player when the player is
outside a dead zone, so a pinned camera does nothing. The ship/ball/wave arm — the one
driven by `target_scroll_y` — moves the player *every frame*, unconditionally. So the ball
sitting on flat ground took 2px a frame upward, the floor eject pulled it back down, and the
two fought in a ~14-frame cycle over about 7 pixels. It reads as bad ball physics. The ball
code is correct and unmodified.

`target_scroll_y` is written **only** by `reset_level` and by a gamemode portal, which is
also a trap for the harness: forcing a gamemode without going through a portal leaves it
stale, which reproduces the drift for the wrong reason.

### What is still not exact, deliberately

The bottom cap now conserves the camera position exactly. The **top** cap does not, and that
is the original's arithmetic. Two things in the upward path each disagree by one sub-pixel
step and only cancel if *both* are changed:

- `functions/scroll.h`'s ship/ball arm increments the pixel count on carry **set** after a
  subtract — i.e. when there was *no* borrow (`do_if_carry`, which `nesdash.h` defines as
  `do_if_c_set`). The cube's upward arm uses `do_if_borrow`.
- `_cap_scroll_y_at_top` subtracts `scroll_y_subpx` from the player where conserving the
  camera would add it.

Together they leave ~0.2px a frame. Ported as written; `tools/verify_ball.lua` bounds it
rather than asserting it away.

## 2. The wave's velocity was a constant +1

Chasing the wave's tilt through `verify_ship` — which had been reporting *"NEVER CLAMPED …
this run does not cover it"* for several milestones — turned up a second Calypsi
miscompilation, in `SAUCE/gamemodes/gamemode_wave.h`:

```c
currplayer_vel_y = !currplayer_mini ?
    (currplayer_gravity ? -currplayer_vel_x : currplayer_vel_x) :
    (currplayer_gravity ? -(currplayer_vel_x << 1) : (currplayer_vel_x << 1));
```

Four arms, each leaving its result in A, each branching to one shared store — and the store
is preceded by a spurious `tya`:

```
`?L3664`:   tya
            sta     long:currplayer_vel_y
```

So every arm's value was discarded and whatever was in Y was stored. Measured:
`currplayer_vel_y` was **+1 on every frame**. The wave gamemode did not move vertically at
all.

This is the same family as trap 8, but `tools/scan_stackslots.py` cannot see it — nothing
reads an unwritten slot. `tools/scan_merge_tya.py` is the check for this variant and runs in
`build_game.sh`. It found exactly the two known sites (`probe_full.s` and `game_core.s`,
both from this one header) and nothing else across eight generated files.

The discriminator against the many innocent `tya`/`txa` sites is an **unconditional `bra` to
the label**. When Calypsi gets the same shape right it puts the store behind a second label
and the other arm branches *past* the transfer:

```
`?L251`:    txa
`?L850`:    sta     3,s        <- `bra ?L850`, past the txa. Correct.
```

Fixed the way `common_gravity_routine` was: written long-hand in
`overlay/gamemodes/gamemode_wave.h`, every arm storing to `currplayer_vel_y` itself.

**And the verifier had been telling us.** The wave's tilt could not reach the clamp because
the velocity it is computed from was stuck at +1 — far too small for `0x400 - vel_y` to
leave its unclamped range. An uncovered branch is a question about the port, not a
shortcoming of the test.

## 3. Harness lessons

- **`emu.getState()` returns a FLAT table with dotted keys** — `s["cpu.pc"]`, not
  `s.cpu.pc`. The nested form raises, and **an error inside a memory callback kills that
  callback silently**, so the trace produces no rows and reads as "nothing writes this
  address". Three traces were thrown away to that. `tools/probe_memcb.lua` establishes which
  callback forms fire before a trace depends on them.
- **Mesen resolves `--testrunner` paths relative to its own directory.** A relative path
  exits 1 with no output and leaves the previous run's report to be read as this one's.
- The Bash tool's sandbox cannot launch `Mesen.exe` at all (exit 127, silent). Run
  verifiers from PowerShell.

## Files

| | |
|---|---|
| `shim/src/shim_misc.c` | the two caps, ported in full |
| `overlay/gamemodes/gamemode_wave.h` | the ternary, long-hand |
| `tools/scan_merge_tya.py` | the new scanner, wired into `build_game.sh` |
| `tools/verify_ball.lua` | the ball regression check, in `verify_all.sh` |
| `tools/verify_ship.lua` | mini-wave phases + a direct wave-velocity check |
| `tools/trace_ball*.lua`, `tools/trace_wave.lua`, `tools/probe_memcb.lua` | the traces that found them |
