# famidash-snes-port

WORK DONE BY CLAUDE - THIS SUCKS REALLY BAD

Exploratory work on porting [Famidash](https://github.com/tfdsoft/famidash) — a Geometry Dash
demake for the NES (cc65 / MMC3) — to the SNES.

This repo holds **only** the SNES-side tooling and design docs. It reads the game repo
read-only and never writes to it. Point tools at it with `--root` (default `C:\famidash`).

> Note: `C:\famidash` may be a stale copy of the game repo. Pass `--root` explicitly if you
> keep the live checkout elsewhere.

**Picking this up cold? Start with [docs/HANDOFF.md](docs/HANDOFF.md).** Current state, the
exact next task, and the traps that have already cost time.

## Status

| Milestone | State |
|---|---|
| **M0** — asset pipeline | **done, validated** — [docs/M0_RESULTS.md](docs/M0_RESULTS.md) |
| **M1.1** — display-only SNES ROM | **done** — pixel-exact vs Mesen2, [docs/M1_PROGRESS.md](docs/M1_PROGRESS.md) |
| **M1.2** — column streaming + hardware scroll | **done** — 11264/11264 tilemap words verified |
| **M1.3** — C toolchain + shim headers | **done** — gameplay core compiles to 65816 object code, [docs/M1_TOOLCHAIN.md](docs/M1_TOOLCHAIN.md) |
| **M1.4** — shim implementation + linked ROM | **done** — real physics: falls, lands, rests, jumps — [docs/M1_4_LINKED_ROM.md](docs/M1_4_LINKED_ROM.md) |
| **M1** — shim core, cube mode, one level, playable | **done** — the whole gameplay half compiles, links and runs ([docs/M1_6_LINKED_GAME.md](docs/M1_6_LINKED_GAME.md)) |
| **M2** — level renders, streams and plays | **All 168 levels are playable** — level, ground, player, all 12 gamemodes, the level's coins/orbs/pads/portals, each level's own tileset and colours, and a level select. 27 of 46 hold 60Hz; the rest drop frames on heavy sprite loads (M2.18) ([M2_LEVEL_RENDER](docs/M2_LEVEL_RENDER.md), [M2_12](docs/M2_12_LEVEL_SPRITES.md), [M2_13](docs/M2_13_PLAYER_AND_TEAR.md), [M2_14](docs/M2_14_CHR_BANKING.md), [M2_15](docs/M2_15_SPRITE_BUDGET.md), [M2_16](docs/M2_16_LEVELS_AND_MENU.md), [M2_17](docs/M2_17_TILESETS.md), [M2_22](docs/M2_22_SPRITE_COST.md)) |
| M3 — all gamemodes + menus | not started |
| **M4 — SPC700 audio** | **HiROM and SA-1 music play** — all 132 original FamiStudio songs route per level; exact pulse/triangle/short-noise BRRs and all 39 original DPCM instruments feed the SPC700/DSP driver |
| M5 — content breadth | not started |

## The approach

Reimplement `LIB/` (neslib / nesdoug / nesdash / mapper) on SNES hardware **keeping the same
function signatures**, so the ~17k lines of game logic in `SAUCE/` and all 35MB of level data
compile against either backend. One tree, two backends — rather than a fork that doubles
every future level and feature.

Full function-by-function mapping, the items with no clean SNES equivalent, and the staged
plan: **[docs/SNES_PORT_SCOPE.md](docs/SNES_PORT_SCOPE.md)**.

## Layout

```
docs/SNES_PORT_SCOPE.md   design doc — API mapping, hard list, milestones
docs/M0_RESULTS.md        M0 findings and verification results
docs/M1_PROGRESS.md       M1 progress and build instructions
src/main.s                65816: static display ROM (32KB LoROM)
src/scroll.s              65816: column-streaming scroll ROM (256KB LoROM)
src/lorom.cfg             ld65 config, 32KB
src/lorom256.cfg          ld65 config, 256KB with banked column data
src/snes-HiROM.scm        Calypsi linker rules for the C build
shim/src/                 SNES implementations: pad, collision, scroll, video, main
shim/src/oam_spr.s        the sprite writer, hand-written 65816 (the port's hot loop)
tools/snes_m0.py          asset pipeline + software SNES PPU renderer
tools/build_rom.py        ca65 -> ld65 -> checksum patch (--target main|scroll)
tools/compare_rom.py      software PPU vs Mesen2 pixel diff (static ROM)
tools/verify_scroll.py    VRAM-vs-level-data sweep (scrolling ROM)
tools/*.lua               Mesen2 headless capture / VRAM / PPU-state dumps
shim/include/             SNES reimplementation of the NES hardware API
overlay/                  ported SAUCE/ files; shadows the game repo, never edits it
probe/                    translation units used to test what compiles
bugreport/                Calypsi ICE reproducer
out/                      generated ROMs, renders, binaries (gitignored)
```

## Quick start

```bash
python tools/snes_m0.py --root C:\famidash --outdir out --col-start 140 --columns 16
python tools/build_rom.py --root C:\famidash --target main
python tools/build_rom.py --root C:\famidash --target scroll
```

Produces `out/famidash-snes-main.sfc` (static screen) and
`out/famidash-snes-scroll.sfc` (scrolls the whole level). Requires Python 3, Pillow, and the
game repo's `BIN/ca65.exe` + `BIN/ld65.exe`.

To verify against emulation (needs Mesen2 at `C:\mesen2`):

```bash
"C:\mesen2\Mesen.exe" --testrunner out\famidash-snes-main.sfc tools\shot.lua && python tools/compare_rom.py
```

```bash
python tools/verify_scroll.py --root C:\famidash
```

Note: do not pixel-diff Mesen `--testrunner` captures of a *moving* scene — they are not
frame-deterministic. See docs/M1_PROGRESS.md.

## Toolchain

- **Assembly**: `ca65 --cpu 65816` + `ld65` from the game repo's `BIN/`. No install needed.
- **C**: Calypsi 5.18 for 65816 at `C:\toolchains\calypsi`. See
  [docs/M1_TOOLCHAIN.md](docs/M1_TOOLCHAIN.md) — note `-O 2`, not `-O2`.

The gameplay core — collision, X movement, all six gamemodes — compiles to 65816 object code
(~95KB at `-O 1`). Three files needed porting, all held in `overlay/` so the game repo is
never modified: two cc65 register-pressure workarounds, two missing forward declarations, and
one GCC computed-goto dispatch rewritten as a switch.
