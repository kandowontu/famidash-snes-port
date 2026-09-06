# M4 — SPC700 music, HiROM and SA-1 paths

Both full ROMs play Famidash's original FamiStudio music through the SNES audio
hardware.

## What is implemented

`tools/gen_famistudio.py` assembles the upstream 6502 FamiStudio engine for the
65816. This preserves the sequencer, instrument/envelope logic, tempo, vibrato,
slides, SFX mixing, exported song format, and `.fms` workflow instead of cloning
those semantics in new code.

The compatibility island contains 3,416 bytes of sequencer code, 2,305 bytes of
original SFX, and all 132 active songs in six 64KB ROM banks at `$DD-$E2`. Its
239-byte state is a dedicated direct page at `$1E00` on HiROM or shared SA-1
I-RAM at `$0700`.

Every song bank mirrors the sequencer's constant tables and SFX at identical
low addresses. DBR can therefore select song data while the engine's original
16-bit addresses remain valid.

The level generator resolves each header's `song_*` define and emits
`lvl_song[]`; `init_rld()` copies that entry to the sequencer's `song` variable.
Treating those symbolic values as zero was the reason every level previously
played the same track.

The sequencer writes FamiStudio's native eleven-byte 2A03 register image.
`shim/src/shim_spc.c` sends changed pairs and an atomic commit over
`$2140-$2143`. `spc/famidash_spc.s` maps:

* the two pulses to exact looping single-cycle BRRs;
* triangle to its exact looping 32-step BRR;
* long noise to S-DSP hardware noise;
* the NES's 93-step short-noise mode to an exact looping BRR;
* DPCM to voice 4.

`tools/gen_dpcm_brr.py` parses each exported instrument's initial `$4011`
delta-counter value and loop bit, then converts all 39 original instruments
across twelve source banks. Voice 4 plays them at the original sixteen NTSC
DPCM rates. `tools/gen_song_dpcm.py` derives each song's actual sample working
set; 129 of 132 complete kits fit in ARAM and load while the screen is forced
blank. The two oversized songs preload their hot samples and stream a rare
uncached sample into one fallback slot at no more than 32 bytes per game frame.
Resident instrument changes do no BRR upload during gameplay.

On SA-1, the original sequencer runs natively against shared I-RAM. The S-CPU
reads the same register image through the `$3700` mirror and alone touches the
audio ports. ROM megabytes 2 and 3 are mapped through EXB/FXB so the six music
banks and twelve packed DPCM ROM banks are reachable.

## Verification

* `tools/verify_spc.lua` checks the IPL upload and exact pulse duty, pitch,
  volume, mute threshold, triangle, long noise and sampled short noise.
* `tools/verify_music.lua` checks the selected level's song ID and ROM bank and
  runs the real producer through ARAM to live DSP voices. Set
  `REQUIRE_DPCM=1` with a sample-using level for a required voice-4 check, and
  `EXPECT_NO_DPCM_UPLOAD=1` to require resident-only gameplay hits.
* `tools/verify_sa1_music.lua` checks the complete split path: SA-1 I-RAM
  producer, S-CPU transport, SPC ARAM and live DSP voices. Its default level 1
  check includes DPCM.
* `tools/verify_rom_layout.py` checks all six music banks and all twelve DPCM
  BRR blobs in both finished ROM layouts.

## Fidelity boundary

Pulse, triangle and short-noise source waveforms round-trip bit-exactly through
BRR. DPCM is necessarily lossy BRR; the worst sample has 6.5% peak round-trip
error and the others are generally lower. Long noise uses the nearest S-DSP
hardware-noise rate, and the S-DSP mixer/interpolator is not the NES's nonlinear
analog mixer.

The musical data, sequencer, envelopes, duties, pitch effects and sample
identities are preserved, but literal analog-output “1:1” should wait for
recorded NES/SNES comparison and final gain tuning.
