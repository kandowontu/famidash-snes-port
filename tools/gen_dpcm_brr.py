"""The NES's DPCM instruments, converted sample-by-sample to BRR.

This is the other half of the sample set. tools/gen_brr.py makes the four pulse
duties and the triangle - synthesised waveforms, 54 bytes, filter 0 because they
loop. These are recorded samples, and they need a real encoder.

WHY THE NATIVE RATE IS KEPT

A .dmc plays back at one of sixteen fixed NES rates, the highest being about
33.1kHz. The S-DSP resamples every voice through a 14-bit pitch register, and
33143 / 32000 * 0x1000 is about $1092 - well inside its 4x range. So the samples
go across at their own rate and the DSP does the rate conversion in hardware,
which is both exact and free. Resampling them here would throw away detail to
save nothing.

WHY IT STILL FITS

BRR is 9 bytes per 16 samples, against DPCM's 1 bit per sample: 4.5x larger. The
whole lvlset_HUGE set is 88896 bytes of .dmc, which would be ~390KB - six times
the SPC700's entire 64KB of ARAM. The ROM retains all 39 definitions, while
tools/gen_song_dpcm.py computes the samples each song actually uses. Complete
per-song kits fit in ARAM for 129 of 132 songs and are loaded while the screen is
forced blank. The two oversized songs use a hot resident kit plus one bounded
fallback slot. No sample is synchronously uploaded on a normal note hit.

Samples are encoded separately, not by decoding an entire 8KB bank as one
stream.  Every DPCM table entry supplies its own initial delta-counter value and
the S-DSP resets its BRR predictor on key-on; treating a bank as one continuous
sample gets both of those boundaries wrong and audibly corrupts every hit after
the first.

    python tools/gen_dpcm_brr.py --lvlset lvlset_HUGE --outdir out
"""

import argparse
import re
from pathlib import Path

from gen_song_dpcm import _song_rows, _walk_dpcm_events

BRR_BLOCK = 9
SAMPLES_PER_BLOCK = 16
NES_DPCM_RATE = 33143.94        # the fastest of the sixteen rates, $4010 = $F
DSP_RATE = 32000.0

SAMPLE_RE = re.compile(
    r"\.byte\s+\$([0-9a-fA-F]{2})\+\.lobyte"
    r"\(FAMISTUDIO_DPCM_PTR\),"
    r"\$([0-9a-fA-F]{2}),\$([0-9a-fA-F]{2}),"
    r"\$([0-9a-fA-F]{2}),\$([0-9a-fA-F]{2})")


def decode_dpcm(data, initial=64):
    """A .dmc back to PCM, by the 2A03's own rule.

    The delta counter is 7-bit and moves by two, and - the part that matters -
    it SATURATES rather than wrapping: it will not step past 127 or below 0.
    Letting it wrap instead turns a loud passage into a burst of noise, which
    is the classic way this conversion goes wrong.
    """
    counter = initial
    out = []
    for byte in data:
        for bit in range(8):                # LSB first
            if byte & (1 << bit):
                if counter <= 125:
                    counter += 2
            else:
                if counter >= 2:
                    counter -= 2
            # 0..127 centred, then scaled to fill signed 16-bit.
            out.append((counter - 64) * 512)
    return out


def _predict(f, p1, p2):
    """The S-DSP's four filters, exactly as the hardware computes them.

    Python's >> on a negative int floors, which is what an arithmetic shift
    right does, so these translate directly.
    """
    if f == 0:
        return 0
    if f == 1:
        return p1 + ((-p1) >> 4)
    if f == 2:
        return (p1 * 2) + ((-p1 * 3) >> 5) - p2 + (p2 >> 4)
    return (p1 * 2) + ((-p1 * 13) >> 6) - p2 + ((p2 * 3) >> 4)


def _clamp16(v):
    return max(-32768, min(32767, v))


def encode_brr(samples, loop_block=None):
    """Encode PCM as BRR, choosing the best filter and shift for each block.

    Brute force over all four filters and all thirteen shifts, scored on squared
    error against the original. That is affordable here and it matters: filters
    1-3 predict from the previous two DECODED samples, so the encoder has to
    carry the decoder's state and pick with that state in mind. Choosing per
    block on real audio is most of what makes BRR sound acceptable at all.

    The first block is forced to filter 0. Filters 1-3 would predict from
    samples that do not exist yet, and on a sample that is retriggered every
    time a drum hits, that start-up error is audible on every single hit.
    """
    if len(samples) % SAMPLES_PER_BLOCK:
        samples = samples + [0] * (SAMPLES_PER_BLOCK - len(samples) % SAMPLES_PER_BLOCK)

    out = bytearray()
    nblocks = len(samples) // SAMPLES_PER_BLOCK
    p1 = p2 = 0

    for b in range(nblocks):
        block = samples[b * SAMPLES_PER_BLOCK:(b + 1) * SAMPLES_PER_BLOCK]
        best = None
        filters = (0,) if b == 0 else (0, 1, 2, 3)

        for f in filters:
            for shift in range(13):
                e1, e2 = p1, p2
                err = 0
                nibbles = []
                for target in block:
                    pred = _predict(f, e1, e2)
                    delta = target - pred
                    # Round to nearest rather than truncating: truncation biases
                    # every sample the same way and the bias accumulates through
                    # the predictor as a DC drift.
                    half = 1 << (shift - 1) if shift else 0
                    q = (delta + half) >> shift if shift else delta
                    q = max(-8, min(7, q))
                    dec = _clamp16(pred + (q << shift))
                    err += (target - dec) ** 2
                    nibbles.append(q & 0x0F)
                    e2, e1 = e1, dec
                if best is None or err < best[0]:
                    best = (err, f, shift, nibbles, e1, e2)

        _, f, shift, nibbles, p1, p2 = best
        header = (shift << 4) | (f << 2)
        if b == nblocks - 1:
            header |= 0x01
            if loop_block is not None:
                header |= 0x02
        out.append(header)
        for i in range(0, SAMPLES_PER_BLOCK, 2):
            out.append((nibbles[i] << 4) | nibbles[i + 1])
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="C:/famidash")
    ap.add_argument("--lvlset", default="lvlset_HUGE")
    ap.add_argument("--outdir", default="out")
    ap.add_argument("--only", type=int, default=None,
                    help="convert one bank, for a quick look (no metadata)")
    args = ap.parse_args()

    src = Path(args.root) / "MUSIC" / "EXPORTS" / args.lvlset
    banks = sorted(src.glob("music_bank*.dmc"),
                   key=lambda p: int(p.stem.replace("music_bank", "")))
    if not banks:
        raise SystemExit("no .dmc banks in %s" % src)

    outroot = Path(args.outdir)
    outdir = outroot / "brr"
    outdir.mkdir(parents=True, exist_ok=True)

    # (start register, length register, initial delta, loop flag), grouped by
    # the DPCM bank callback value.  Pitch is intentionally not part of the
    # identity: the DSP resampler plays one BRR at all sixteen original rates.
    records = {}
    music_files = sorted(
        src.glob("music_[0-9]*.s"),
        key=lambda p: int(p.stem.split("_")[1]))
    for path in music_files:
        for line in path.read_text(errors="replace").splitlines():
            if "FAMISTUDIO_DPCM_PTR" not in line or ".byte" not in line:
                continue
            m = SAMPLE_RE.search(line)
            if not m:
                raise SystemExit("cannot parse DPCM table row: " + line)
            start, length, freq, initial, bank = (
                int(x, 16) for x in m.groups())
            records.setdefault(bank, set()).add(
                (start, length, initial & 0x7f, 1 if freq & 0x40 else 0))

    # Add the non-default initial-counter variants that the actual songs use.
    # The source DPCM tables only contain each note's default value; opcode
    # $52 can replace it for the next hit.  Decode the already assembled song
    # streams so those audible variants become first-class BRR samples too.
    meta_path = outroot / "famistudio_meta.c"
    if not meta_path.exists():
        raise SystemExit("gen_dpcm_brr: run gen_famistudio.py first")
    songs = _song_rows(meta_path.read_text())
    song_banks = {
        bank: (outroot / f"famistudio_bank{bank}.bin").read_bytes()
        for bank in {song[0] for song in songs}
    }
    override_uses = set()
    for song_bank, song_base, local_song, _source in songs:
        data = song_banks[song_bank]
        table = data[song_base + 3] | (data[song_base + 4] << 8)
        for table_index, initial_override in _walk_dpcm_events(
                data, song_base, local_song):
            if initial_override is None:
                continue
            row = (table + table_index * 5) & 0xffff
            start, length, freq, _initial, dpcm_bank = data[row:row + 5]
            key = (start, length, initial_override & 0x7f,
                   1 if freq & 0x40 else 0)
            records.setdefault(dpcm_bank, set()).add(key)
            override_uses.add((dpcm_bank,) + key)

    print("    bank  definitions    .dmc      packed BRR   worst error")
    entries = []
    sizes = []
    worst_overall = 0.0
    for p in banks:
        bank = int(p.stem.replace("music_bank", ""))
        if args.only is not None and bank != args.only:
            continue
        dmc = p.read_bytes()
        packed = bytearray()
        bank_worst = 0.0
        defs = sorted(records.get(bank, ()))
        for start, length, initial, loop in defs:
            byte_at = start * 64
            byte_count = length * 16 + 1
            sample = dmc[byte_at:byte_at + byte_count]
            if len(sample) != byte_count:
                # Exported banks omit trailing alignment bytes that are never
                # named by another sample. The NES still reads through the
                # declared $4013 length into the bank's zero-filled padding.
                if byte_at + byte_count > 8192:
                    raise SystemExit(
                        f"bank {bank} sample ${start:02x}/${length:02x} "
                        "runs past the 8KB DPCM window")
                sample += bytes(byte_count - len(sample))
            pcm = decode_dpcm(sample, initial)
            brr = encode_brr(pcm, loop_block=0 if loop else None)
            err = _round_trip_error(brr, pcm)
            bank_worst = max(bank_worst, err)
            entries.append(
                (bank, start, length, initial, loop, len(packed), len(brr)))
            packed += brr

        worst_overall = max(worst_overall, bank_worst)
        sizes.append(len(packed))
        (outdir / f"dpcm_bank{bank}.brr").write_bytes(packed)
        print(f"    {bank:4d}  {len(defs):11d}  {len(dmc):7d}  "
              f"{len(packed):14d}      {bank_worst:4.1f}%")

    if args.only is not None:
        return 0

    # One root section per resident bank. The linker first-fits these sections
    # into generated 64KB ROM memories; C pointers retain their final banks.
    asm = [
        "; Generated by tools/gen_dpcm_brr.py - do not edit.",
        "        .rtmodel version, \"1\"",
        "        .rtmodel codeModel, \"large\"",
        "        .rtmodel dataModel, \"large\"",
        "        .rtmodel core, \"65816\"",
        "        .rtmodel huge, \"0\"",
        "",
    ]
    for bank, _ in enumerate(sizes):
        asm += [
            "        .section fsdpcm,rodata,root",
            f"        .public famistudio_dpcm_brr_bank{bank}",
            f"famistudio_dpcm_brr_bank{bank}:",
            f'        .incbin "out/brr/dpcm_bank{bank}.brr"',
            "",
        ]
    (outroot / "famistudio_dpcm_banks.s").write_text("\n".join(asm))

    header = """/* Generated by tools/gen_dpcm_brr.py - do not edit. */
#ifndef FAMISTUDIO_DPCM_META_H
#define FAMISTUDIO_DPCM_META_H
#include <stdint.h>
typedef struct {
    uint8_t bank, start, length, initial, loop;
    uint16_t brr_offset, brr_size;
} FamiStudioDpcmSample;
extern const uint8_t *const famistudio_dpcm_brr_banks[];
extern const uint16_t famistudio_dpcm_brr_sizes[];
extern const FamiStudioDpcmSample famistudio_dpcm_samples[];
extern const uint8_t famistudio_dpcm_bank_count;
extern const uint8_t famistudio_dpcm_sample_count;
#endif
"""
    (outroot / "famistudio_dpcm_meta.h").write_text(header)
    externs = "\n".join(
        f"extern const uint8_t famistudio_dpcm_brr_bank{i}[];"
        for i in range(len(sizes)))
    ptrs = ", ".join(
        f"famistudio_dpcm_brr_bank{i}" for i in range(len(sizes)))
    size_rows = ", ".join(str(n) for n in sizes)
    sample_rows = "\n".join(
        f"    {{{bank}, 0x{start:02x}, 0x{length:02x}, 0x{initial:02x}, "
        f"{loop}, 0x{offset:04x}, 0x{size:04x}}},"
        for bank, start, length, initial, loop, offset, size in entries)
    meta = f"""/* Generated by tools/gen_dpcm_brr.py - do not edit. */
#include "famistudio_dpcm_meta.h"
{externs}
const uint8_t *const famistudio_dpcm_brr_banks[] = {{ {ptrs} }};
const uint16_t famistudio_dpcm_brr_sizes[] = {{ {size_rows} }};
const FamiStudioDpcmSample famistudio_dpcm_samples[] = {{
{sample_rows}
}};
const uint8_t famistudio_dpcm_bank_count = {len(sizes)};
const uint8_t famistudio_dpcm_sample_count = {len(entries)};
"""
    (outroot / "famistudio_dpcm_meta.c").write_text(meta)
    (outroot / "famistudio_dpcm_layout.py").write_text(
        "# Generated by tools/gen_dpcm_brr.py - do not edit.\n"
        f"DPCM_BANK_SIZES = {sizes!r}\n"
        f"DPCM_SAMPLE_COUNT = {len(entries)}\n")

    print("    largest packed BRR source bank: %d bytes" % max(sizes))
    print("    %d unique DPCM waveforms (%d counter-override variants); "
          "worst round-trip error: %.1f%%"
          % (len(entries), len(override_uses), worst_overall))
    return 0


def _round_trip_error(brr, pcm):
    p1 = p2 = 0
    worst = 0
    peak = max(abs(v) for v in pcm) or 1
    i = 0
    for off in range(0, len(brr), BRR_BLOCK):
        header = brr[off]
        shift, f = header >> 4, (header >> 2) & 3
        for byte in brr[off + 1:off + BRR_BLOCK]:
            for nib in (byte >> 4, byte & 0x0F):
                q = nib - 16 if nib >= 8 else nib
                dec = _clamp16(_predict(f, p1, p2) + (q << shift))
                if i < len(pcm):
                    worst = max(worst, abs(pcm[i] - dec))
                p2, p1 = p1, dec
                i += 1
    return 100.0 * worst / peak


if __name__ == "__main__":
    raise SystemExit(main())
