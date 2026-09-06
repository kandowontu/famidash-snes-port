"""The NES's five voices as looped BRR samples for the SNES S-DSP.

WHY THIS IS THE RIGHT SHAPE FOR THE PORT

The music is FamiStudio data written for the 2A03, and the musicians' workflow
is that data. So the plan is not to re-score anything: run FamiStudio's own
sequencer, take the 2A03 register values it produces each frame, and play them
on the S-DSP instead of the APU. That needs the APU's *waveforms* as samples,
which is what this makes.

Three of the four 2A03 voices are single-cycle waveforms and loop exactly:

    pulse       a square wave at four duty cycles. One cycle is 16 samples,
                which is exactly one BRR block.
    triangle    a 32-step 4-bit staircase - two BRR blocks.
    noise       long mode uses the S-DSP hardware generator. NES short mode is
                a distinct 93-step metallic sequence, so it is a looped BRR
                sample (16 repeats make its length BRR-block aligned).

DPCM is the fourth and is deliberately out of this file: those are recorded
samples, not synthesised waveforms, and they carry a size problem this does not
- see the note at the bottom.

WHY FILTER 0, ALWAYS

A BRR block header picks one of four filters; 1-3 predict from the previous two
decoded samples, which is what makes BRR efficient on real audio. For a looped
single-cycle waveform they are exactly wrong: prediction carries state across
the loop point, so the first cycle after a loop decodes differently from the
one before it and the wave develops a DC drift and a click. Filter 0 has no
history - each nibble is just `value << shift` - so every loop is bit-identical
to the last. These waveforms are 16 samples long; there is nothing to gain by
compressing them and a working loop to lose.

    python tools/gen_brr.py --outdir out
"""

import argparse
import struct
from pathlib import Path

# A BRR block is 9 bytes: one header, then 8 bytes holding 16 signed nibbles.
BRR_BLOCK = 9
SAMPLES_PER_BLOCK = 16


def encode_brr(samples, loop=True):
    """Encode 16-bit signed samples as filter-0 BRR blocks.

    The length must be a multiple of 16: BRR has no partial blocks, and a loop
    point can only be placed on a block boundary, which is the whole reason the
    waveforms below are sized to 16 and 32 rather than to the NES's own step
    counts.
    """
    if len(samples) % SAMPLES_PER_BLOCK:
        raise ValueError("BRR needs a multiple of %d samples, got %d"
                         % (SAMPLES_PER_BLOCK, len(samples)))

    out = bytearray()
    nblocks = len(samples) // SAMPLES_PER_BLOCK
    for b in range(nblocks):
        block = samples[b * SAMPLES_PER_BLOCK:(b + 1) * SAMPLES_PER_BLOCK]

        # Smallest shift that keeps every sample inside a signed nibble, so the
        # quantisation error is as small as this block allows.
        #
        # Tested against the ACTUAL range, -8..7, not against the absolute peak
        # versus 7. Nibbles are signed and asymmetric: a block whose lowest
        # sample is exactly -8 fits, but an |v| <= 7 test rejects it and bumps
        # the shift, halving the resolution of the whole block. That cost the
        # triangle 12.5% of its amplitude - on the one waveform whose staircase
        # levels ARE the instrument.
        shift = 0
        while shift < 12 and any((v >> shift) < -8 or (v >> shift) > 7
                                 for v in block):
            shift += 1

        header = (shift << 4) | (0 << 2)        # filter 0
        if b == nblocks - 1:
            header |= 0x01                      # end of sample
            if loop:
                header |= 0x02                  # ...and loop back
        out.append(header)

        for i in range(0, SAMPLES_PER_BLOCK, 2):
            n = []
            for v in (block[i], block[i + 1]):
                q = v >> shift if shift else v
                q = max(-8, min(7, q))
                n.append(q & 0x0F)
            out.append((n[0] << 4) | n[1])
    return bytes(out)


def decode_brr(data):
    """Decode filter-0 BRR back to samples, for the round-trip check."""
    out = []
    for off in range(0, len(data), BRR_BLOCK):
        header = data[off]
        shift = header >> 4
        for byte in data[off + 1:off + BRR_BLOCK]:
            for nib in (byte >> 4, byte & 0x0F):
                v = nib - 16 if nib >= 8 else nib      # sign-extend 4 bits
                out.append(v << shift)
    return out


def pulse(duty_eighths, amplitude=7 << 12):
    """One cycle of a 2A03 pulse wave, 16 samples.

    The NES duty cycles are eighths, and 16 samples divides by 8 exactly, so
    each eighth is two samples and every duty is represented without rounding.

    FULL SCALE, and it has to be. A BRR nibble is -8..7 and the shift can be at
    most 12, so 7 << 12 is as loud as this format goes; the headroom for four
    voices summing belongs in the DSP's per-voice VOL, where gen_spc_image.py
    puts it. Encoding these quiet and turning the volume up instead throws away
    the bits it looks like it is saving - the same amplitude arrives with a
    sixteenth of the resolution.
    """
    high = duty_eighths * 2
    return [amplitude if i < high else -amplitude for i in range(16)]


def triangle(scale=1 << 12):
    """One cycle of the 2A03 triangle: 32 steps, 4 bits, up then down.

    Kept at the NES's own 32 steps rather than smoothed to a real triangle -
    the staircase is audible and is part of the instrument.

    The levels are the 4-bit DAC's own, centred to -8..7 and scaled by a power
    of two. That matters: BRR nibbles are signed 4-bit, so this lands on them
    exactly and the round trip is lossless. Scaling by 15ths instead - to
    "use the full range" - put the levels between nibbles and threw away 13% of
    the amplitude to quantisation, on the one waveform where the staircase is
    the instrument.
    """
    steps = list(range(16)) + list(range(15, -1, -1))
    return [(s - 8) * scale for s in steps]


def noise_short_cycle(amplitude=7 << 12):
    """One complete 93-step NES short-mode noise cycle."""
    shift = 1
    values = []
    seen = set()
    while shift not in seen:
        seen.add(shift)
        values.append(amplitude if (shift & 1) == 0 else -amplitude)
        feedback = (shift & 1) ^ ((shift >> 6) & 1)
        shift = (shift >> 1) | (feedback << 14)
    if len(values) != 93:
        raise ValueError(f"short-noise LFSR period is {len(values)}, want 93")
    return values


def noise_short(amplitude=7 << 12):
    """The NES noise channel's 93-step short-mode LFSR sequence.

    BRR blocks hold 16 samples while 93 is prime to 16. Repeating the exact
    period sixteen times gives a 1488-sample loop whose endpoint is both an
    LFSR boundary and a BRR boundary.
    """
    values = noise_short_cycle(amplitude)
    return values * 16


def noise_short_alias(period, sample_count, amplitude=7 << 12):
    """Pre-alias high NES short-noise rates into a 32 kHz BRR loop.

    The S-DSP pitch register tops out at 4x unity. NES periods 4..32 need
    rates above that limit, so sampling the exact LFSR cycle at its final
    output rate preserves the intended metallic timbre instead of playing a
    clamped, heavily transposed version.
    """
    source = noise_short_cycle(amplitude)
    step = 1789773.0 / period / 32000.0
    return [source[int(i * step) % len(source)] for i in range(sample_count)]


WAVES = [
    ("pulse_12", lambda: pulse(1), "2A03 pulse, duty 12.5%"),
    ("pulse_25", lambda: pulse(2), "2A03 pulse, duty 25%"),
    ("pulse_50", lambda: pulse(4), "2A03 pulse, duty 50%"),
    ("pulse_75", lambda: pulse(6), "2A03 pulse, duty 75% (duty 25% inverted)"),
    ("triangle", triangle,          "2A03 triangle, 32 steps"),
    ("noise_short", noise_short,    "2A03 noise, 93-step short mode"),
    ("noise_short_0", lambda: noise_short_alias(4, 80),
     "2A03 short noise period 4, pre-aliased to 32 kHz"),
    ("noise_short_1", lambda: noise_short_alias(8, 80),
     "2A03 short noise period 8, pre-aliased to 32 kHz"),
    ("noise_short_2", lambda: noise_short_alias(16, 80),
     "2A03 short noise period 16, pre-aliased to 32 kHz"),
    ("noise_short_3", lambda: noise_short_alias(32, 160),
     "2A03 short noise period 32, pre-aliased to 32 kHz"),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default="out")
    args = argparse.Namespace(**vars(ap.parse_args()))
    outdir = Path(args.outdir) / "brr"
    outdir.mkdir(parents=True, exist_ok=True)

    total = 0
    print("    name        samples  BRR bytes  worst error  ")
    for name, make, note in WAVES:
        pcm = make()
        brr = encode_brr(pcm, loop=True)
        back = decode_brr(brr)

        # The round trip is the check that matters: filter 0 is exact up to the
        # shift, so a large error here means the shift search is wrong rather
        # than that BRR is lossy.
        worst = max(abs(a - b) for a, b in zip(pcm, back))
        rel = 100.0 * worst / max(abs(v) for v in pcm)

        (outdir / (name + ".brr")).write_bytes(brr)
        total += len(brr)
        print("    %-10s  %7d  %9d  %5.1f%%       %s"
              % (name, len(pcm), len(brr), rel, note))

    print("    %d bytes of waveform in ARAM (of 65536 total)" % total)
    print("    long noise: S-DSP hardware; short noise: exact looped BRR")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
