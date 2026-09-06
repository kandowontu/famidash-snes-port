#!/usr/bin/env python3
"""Build the ARAM image the SNES uploads to the SPC700 at boot.

Three lookup tables, a BRR sample directory, the waveforms, and the driver
assembled around them. The arithmetic for each table lives here, in one place,
rather than as constants in the driver source - a magic number in SPC700
assembly is a number nobody can check.

    python tools/gen_spc_image.py --outdir out

Writes:
    out/spc/*.bin        the pieces, for .incbin
    out/spc_driver.bin   the finished ARAM image
    out/spc_image.s      the same image as a 65816 .incbin, for the ROM
    out/spc_image.lua    what a verifier needs to know about it
"""

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ARAM_LOAD = 0x0200          # where the image goes, and where the IPL jumps

# ---------------------------------------------------------------------------
# The pitch table.
#
# The DSP plays a sample at 32000 * PITCH / 4096 Hz. A pulse waveform here is
# 16 samples per cycle and the triangle is 32, and the 2A03's own periods are
#
#     pulse    f = 1789773 / (16 * (period + 1))
#     triangle f = 1789773 / (32 * (period + 1))
#
# so for the pulse:  PITCH = 4096 * 16 * f / 32000 = 229091 / (period + 1)
# and for the triangle the two factors of 32 cancel to exactly the same thing.
# ONE table serves both, which is the reason the waveforms were sized 16 and 32
# rather than to some rounder number.
# ---------------------------------------------------------------------------
CPU_HZ = 1789773.0
DSP_HZ = 32000.0
PITCH_UNITY = 4096
PITCH_MAX = 0x3FFF          # the DSP's pitch field is 14 bits
DPCM_ARAM = 0x2000          # per-song BRR residency arena


def pitch_table():
    out = bytearray()
    clamped = 0
    for period in range(2048):
        pitch = round(PITCH_UNITY * 16 * CPU_HZ / (16 * (period + 1)) / DSP_HZ)
        if pitch > PITCH_MAX:
            # Only reachable below period 14, and the 2A03 mutes the pulse
            # below period 8 and the triangle below 2. The clamp is here so a
            # period in the gap produces the highest note the DSP has rather
            # than a wrapped pitch field, which would be an audible screech
            # instead of an inaudible one.
            pitch = PITCH_MAX
            clamped += 1
        out += pitch.to_bytes(2, "little")
    return bytes(out), clamped


# NTSC 2A03 DPCM timer periods, one decoded DAC step per input bit.
DPCM_PERIODS = [428, 380, 340, 320, 286, 254, 226, 214,
                190, 160, 142, 128, 106, 84, 72, 54]


def dpcm_pitch_table():
    out = bytearray()
    for period in DPCM_PERIODS:
        rate = CPU_HZ / period
        pitch = min(PITCH_MAX, round(PITCH_UNITY * rate / DSP_HZ))
        out += pitch.to_bytes(2, "little")
    return bytes(out)


# ---------------------------------------------------------------------------
# The volume table.
#
# The 2A03's four-bit volume onto the DSP's signed eight-bit VOL. The top is
# well short of $7F on purpose: the DSP sums the voices into a 16-bit
# accumulator and clips, and the waveforms are full-scale BRR, so four voices
# at maximum have to stay inside it.
#
#     4 voices * 32768 * VOL_MAX/128 <= 32767   ->   VOL_MAX <= 32
#
# 30 leaves a little margin for the triangle, which is louder than a pulse of
# the same nominal level because its waveform is a full-amplitude staircase
# rather than a square that spends half its cycle at one rail.
# ---------------------------------------------------------------------------
VOL_MAX = 30


def volume_table():
    # Linear in the 2A03's own units. The 2A03's mixer is not linear in them
    # either, but its non-linearity is a property of the DAC and the other
    # channels' levels, not of the volume field, and approximating it here
    # would be guessing.
    return bytes(round(v * VOL_MAX / 15) for v in range(16))


# ---------------------------------------------------------------------------
# The noise table.
#
# The 2A03's sixteen noise periods, in CPU cycles, and the DSP's thirty-two
# noise rates in Hz. Nearest match by frequency.
#
# The top eight 2A03 periods are all far above the DSP's fastest rate (32kHz),
# so they collapse onto rate 31 - they are above the audible range on the NES
# too, where they read as a hiss rather than as pitch, so the collapse costs
# less than it looks like it should.
# ---------------------------------------------------------------------------
NES_NOISE_PERIODS = [4, 8, 16, 32, 64, 96, 128, 160,
                     202, 254, 380, 508, 762, 1016, 2034, 4068]
DSP_NOISE_RATES = [0, 16, 21, 25, 31, 42, 50, 63, 83, 100, 125, 167, 200, 250,
                   333, 400, 500, 667, 800, 1000, 1300, 1600, 2000, 2700, 3200,
                   4000, 5300, 6400, 8000, 10700, 16000, 32000]


def noise_table():
    out = bytearray()
    detail = []
    for p in NES_NOISE_PERIODS:
        want = CPU_HZ / p
        best = min(range(1, 32), key=lambda i: abs(DSP_NOISE_RATES[i] - want))
        out.append(best)
        detail.append((p, want, best, DSP_NOISE_RATES[best]))
    return bytes(out), detail


def noise_pitch_table():
    """Pitch for one sampled LFSR step per original noise timer clock."""
    out = bytearray()
    for period in NES_NOISE_PERIODS:
        pitch = round(PITCH_UNITY * (CPU_HZ / period) / DSP_HZ)
        out += min(PITCH_MAX, pitch).to_bytes(2, "little")
    return bytes(out)


# ---------------------------------------------------------------------------
# The BRR sample directory.
#
# Four bytes a source: start address then loop address, both little-endian.
# Every waveform here loops over its whole length, so the two are equal - a
# single-cycle wave has no attack to skip past.
# ---------------------------------------------------------------------------
SAMPLE_ORDER = [
    "pulse_12", "pulse_25", "pulse_50", "pulse_75", "triangle",
    "noise_short", "noise_short_0", "noise_short_1", "noise_short_2",
    "noise_short_3",
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default=str(ROOT / "out"))
    args = ap.parse_args()

    outdir = Path(args.outdir)
    spcdir = outdir / "spc"
    spcdir.mkdir(parents=True, exist_ok=True)
    brrdir = outdir / "brr"

    missing = [n for n in SAMPLE_ORDER if not (brrdir / (n + ".brr")).exists()]
    if missing:
        sys.exit("gen_spc_image: run tools/gen_brr.py first - missing %s"
                 % ", ".join(missing))

    pit, clamped = pitch_table()
    (spcdir / "pitchtab.bin").write_bytes(pit)
    (spcdir / "dpcmpitch.bin").write_bytes(dpcm_pitch_table())
    (spcdir / "voltab.bin").write_bytes(volume_table())
    noise, noise_detail = noise_table()
    (spcdir / "noisetab.bin").write_bytes(noise)
    (spcdir / "noisepitch.bin").write_bytes(noise_pitch_table())

    # The directory has to be built before the driver is assembled, and it
    # holds the sample ADDRESSES, which are not known until the driver has been
    # assembled. Two passes: assemble with a placeholder directory to find
    # where SAMPLES lands, then rebuild the directory and assemble again.
    #
    # A fixed-size placeholder is what makes this terminate - the directory is
    # always 4 bytes a source, so the second pass cannot move anything.
    blobs = [(brrdir / (n + ".brr")).read_bytes() for n in SAMPLE_ORDER]
    samples = b"".join(blobs)
    (spcdir / "samples.bin").write_bytes(samples)

    src = ROOT / "spc" / "famidash_spc.s"
    image = None
    sample_at = None
    for attempt in range(2):
        dirtab = bytearray()
        off = 0
        for blob in blobs:
            addr = (sample_at or 0) + off
            dirtab += addr.to_bytes(2, "little") * 2
            off += len(blob)
        dirtab += bytes(256 - len(dirtab))
        (spcdir / "dirtab.bin").write_bytes(bytes(dirtab))

        r = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "spcasm.py"), str(src),
             "-o", str(outdir / "spc_driver.bin"),
             "--base", hex(ARAM_LOAD),
             "--incdir", str(spcdir),
             "--listing", str(outdir / "spc_driver.lst"),
             "--symbols", str(outdir / "spc_driver.sym")],
            capture_output=True, text=True)
        if r.returncode:
            sys.exit(r.stdout + r.stderr)
        image = (outdir / "spc_driver.bin").read_bytes()
        syms = dict(line.split("=") for line in
                    (outdir / "spc_driver.sym").read_text().split()
                    if "=" in line)
        new_at = int(syms["SAMPLES"])
        if new_at == sample_at:
            break
        sample_at = new_at
    else:
        sys.exit("gen_spc_image: the sample address did not settle")
    if ARAM_LOAD + len(image) > DPCM_ARAM:
        sys.exit("gen_spc_image: driver/tables overlap dynamic DPCM ARAM "
                 f"at ${DPCM_ARAM:04X}")

    # The whole image, as one .incbin for the 65816 side. It is uploaded as a
    # single contiguous block, so there is nothing here to keep in step with
    # the linker beyond its length.
    #
    # `cfar,rodata` is the section Calypsi itself puts const far data in, and
    # src/snes-HiROM.scm already routes it into the code banks - so this needs
    # no memory of its own. It is read a byte at a time by the IPL upload loop
    # rather than DMA'd, so unlike the CHR and level banks it has no
    # bank-straddling constraint to satisfy (traps 37, 39).
    (outdir / "spc_image.s").write_text(
        "; Generated by tools/gen_spc_image.py - do not edit.\n"
        "; The SPC700 driver image, uploaded verbatim to ARAM at $%04X.\n"
        "\n"
        "        .section cfar,rodata,root\n"
        "        .public spc_image_data\n"
        "spc_image_data:\n"
        '        .incbin "%s"\n'
        % (ARAM_LOAD, (outdir / "spc_driver.bin").as_posix()))

    # THE POINTER IS BUILT IN C, not taken in assembly.
    #
    # A pointer here is 24 bits and a plain `extern const uint8_t x[]` reference
    # from C emits a SIXTEEN-bit relocation, which the linker rejects for
    # anything above bank 0 - that is the visible half of trap 28. A C pointer
    # variable initialised from the symbol makes the compiler build the full
    # 24-bit address itself, which is the same thing bgchr_meta.c does for the
    # tilesets and level_table.c for the levels.
    (outdir / "spc_image_meta.c").write_text(
        "/* Generated by tools/gen_spc_image.py - do not edit. */\n"
        "#include <stdint.h>\n"
        "\n"
        "extern const uint8_t spc_image_data[];\n"
        "\n"
        "const uint8_t *const spc_image = spc_image_data;\n"
        "const uint16_t spc_image_len = %d;\n" % len(image))

    entry = int(syms["start"])
    (outdir / "spc_image.lua").write_text(
        "-- generated by tools/gen_spc_image.py\n"
        "return {\n"
        "  load = 0x%04X, entry = 0x%04X, size = %d,\n"
        "  dirtab = 0x%04X, samples = 0x%04X, pitchtab = 0x%04X,\n"
        "  voltab = 0x%04X, noisetab = 0x%04X,\n"
        "  dpcm_base = 0x%04X, dpcmpitch = 0x%04X,\n"
        "  vol_max = %d,\n"
        "  ready0 = 0x%02X, ready1 = 0x%02X,\n"
        "}\n"
        % (ARAM_LOAD, entry, len(image), int(syms["DIRTAB"]),
           int(syms["SAMPLES"]), int(syms["PITCHTAB"]), int(syms["VOLTAB"]),
           int(syms["NOISETAB"]), DPCM_ARAM, int(syms["DPCMPITCH"]), VOL_MAX,
           int(syms["READY0"]), int(syms["READY1"])))

    code = int(syms["VOLTAB"]) - ARAM_LOAD
    print("    spc driver: %d bytes of code, %d of tables, %d of BRR"
          % (code, len(image) - code - len(samples), len(samples)))
    print("    ARAM $%04X-$%04X, entry $%04X, %d bytes free above it"
          % (ARAM_LOAD, ARAM_LOAD + len(image) - 1, entry,
             0xFFC0 - (ARAM_LOAD + len(image))))
    print("    pitch table: %d of 2048 periods clamped to the DSP's maximum"
          % clamped)
    print("    DPCM resident bank starts at ARAM $%04X" % DPCM_ARAM)
    print("    noise: " + ", ".join("%d->%d(%dHz)" % (p, i, r)
                                    for p, _, i, r in noise_detail[8:]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
