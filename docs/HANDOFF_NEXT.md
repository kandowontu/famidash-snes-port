# Start here

The state of the port as of the end of the SA-1 session, and the three jobs
queued behind it. Read `docs/HANDOFF.md` for the trap list - it now runs to 125,
and 117-125 are all from this session.

---

## 1. What exists

**Two ROMs, both built from the same object files.**

```sh
sh tools/build_game.sh          # out/famidash-snes-full.sfc   HiROM, 1.9MB
SA1=1 sh tools/build_game.sh    # ...and out/famidash-sa1-full.sfc, SA-1
```

The HiROM ROM is the reference build and has been correct for a long time. The
SA-1 ROM is new: same 168 levels, same ROM banks, but the game runs on the SA-1
with all ~38KB of state in BW-RAM, and it **plays** - menu, input, level load,
60Hz, correct geometry and colours.

**Verification.**

```sh
sh tools/verify_all.sh          # the HiROM port, including all 168 levels
sh tools/verify_sa1_all.sh      # the six SA-1 checks
```

Everything passes at the time of writing.

**Why the SA-1 exists at all**, in one line: the port executes about twice the
NES's instructions for the same work (`docs/M2_24_WHY_2X.md`), and measurement
put the SA-1 at 1.73x with code in ROM and 2.92x with code in I-RAM
(`docs/M2_25_SA1.md`). 1.73x clears every level that was dropping frames.

## 2. The one thing to internalise about the SA-1 build

**The SA-1 cannot touch the PPU, the DMA controller, the pads, the APU, or
`$7E/$7F` WRAM.** Everything else is fair game. So the split is:

* the **SA-1** runs the game - all of it, out of ROM, with state in BW-RAM;
* the **S-CPU** owns every register in `$2100-$21FF` and `$4200-$43FF`, and runs
  the shim's own C flush code once per vblank;
* they talk through a **mailbox in I-RAM** (`shim/src/shim_sa1.h`), with a
  sequence number for frame pacing and a request channel for one-off bursts.

Three defects this session were the same shape - **something the game calls
directly that only the S-CPU can do**. Each one looked like missing art or a
dead ROM rather than a misplaced call. When adding anything, the question to ask
first is "which processor runs this, and can it?"

The seam is `ppu_wait_nmi()` in `shim/src/shim_ppu.c`. The SA-1 audio build also
compiles `shim_spc.c` with `SHIM_SA1`, so its S-CPU half reads the sequencer
image through the shared I-RAM mirror.

## 3. Next, in order

### a. Duals - the second player does not draw

`drawplayertwo()` in `shim/src/shim_engine.c` is an empty stub. The comment that
used to sit there said player 2's state was never set up; **that was wrong** and
has been corrected in place. The state exists (`state_game.h` sets `player_y[1]`
at spawn and writes both coordinates back every frame) and the call site exists
(`draw_sprites.h` calls it, alternating draw order with `drawplayerone` so
neither player permanently wins OAM priority).

The only missing thing is the body. It is not a copy-paste job: `drawplayerone`
is written against index 0 throughout - 18 subscripts across `player_x/y`,
`player_mini`, `player_gravity`, `player_vel_y`, `cube_data`, `cube_rotate`,
`slope_type`, `slope_frames` - and the `player_frame_*` helpers take no player
argument and read `cube_rotate[0]` and `cube_data[0]` directly.

**Thread a player index through that path; do not duplicate it.** Duplicating
doubles the register-clobber hazard documented at length inside `drawplayerone`,
which cost a session once already.

### b. The SPC700 music driver

**HiROM and SA-1 music now play.** The settled design includes DPCM:

* `tools/gen_famistudio.py` assembles the original 7,655-line 6502 FamiStudio
  sequencer for the 65816 rather than translating it by hand. Its 239-byte
  state lives at `$1E00` on HiROM or shared SA-1 I-RAM `$0700`; all 132 active
  songs plus the original SFX pack into six mirrored 64KB banks;
* `tools/gen_brr.py` makes the four pulse duties, triangle and exact 93-step
  short noise. Those source waveforms round-trip bit-exactly; long noise uses
  the S-DSP noise generator;
* `tools/gen_dpcm_brr.py` parses the real initial delta counter and loop bit for
  all 47 generated DPCM waveforms (including 8 initial-counter variants), and
  `tools/gen_song_dpcm.py` derives the exact per-song sample working sets.
  Complete kits fit for 129 of 132 songs and are
  loaded during forced blank; the two oversized songs use a hot kit plus one
  fallback slot streamed at at most 32 bytes per game frame. Voice 4 can
  therefore play resident hits at the original DPCM rate without a gameplay
  upload spike;
* `shim/src/shim_spc.c` uploads the ARAM program through the IPL and transports
  the eleven-byte APU image once per frame. On SA-1, the producer is in shared
  I-RAM and this transport stays on the S-CPU;
* the level generator resolves the real `song_*` constants. This fixed the
  all-levels-song-zero bug;
* the relocated 65816 direct page needs special handling for the pitch macro:
  the 6502 has no zero-page,Y form for its state-array reads, so the first port
  encoded them as absolute,Y and fetched pitch offsets from music ROM. That
  turned a correct timer such as `$02CE` into `$A1C8` and made every track sound
  wildly transposed. `gen_famistudio.py` now switches that macro to DP,X while
  preserving the note index. A reference song matches the NES for 160
  consecutive APU-image transitions, and both HiROM and SA-1 verifiers reject
  any timer high byte outside the 2A03's valid `$00-$07` range;
* `tools/verify_spc.lua`, `tools/verify_music.lua` and
  `tools/verify_sa1_music.lua` cover the translator and both complete producer
  paths. The music verifiers accept `EXPECT_NO_DPCM_UPLOAD=1` to require that
  sampled note hits use only resident ARAM.

Still remaining:

* the two SSDPCM voice clips used outside FamiStudio are still separate;
* literal analog-output 1:1 still needs recorded NES/SNES comparison and gain
  tuning. BRR DPCM is lossy (worst sample 6.5%), and the S-DSP mixer and
  long-noise rate set are not the NES analog circuit.

## 4. How to not waste a session

The port has a **known-good HiROM build**. When a measurement on the SA-1 build
looks wrong, run the same measurement against the HiROM ROM before believing it.
Two of this session's three "bugs" were measurement errors that survived several
rounds of investigation and were ended by a single side-by-side screenshot.

Specifically, and all of these bit this session: never difference a wrapping
byte counter, never start a sampling window at power-on, inject input from
`inputPolled` and not `endFrame`, and do not expect Mesen's exec-range callbacks
to fire for the SA-1. Trap 125.
