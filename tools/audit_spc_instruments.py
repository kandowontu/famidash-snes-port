#!/usr/bin/env python3
"""Audit every sound source used by the SA-1 FamiStudio -> S-DSP port.

This is deliberately independent of the emulator smoke tests.  It inventories
the source project's named 2A03 instruments, checks the generated tone/noise
waveforms and lookup tables, decodes every DPCM BRR blob back to PCM, and
validates every song's resident sample kit.
"""

from __future__ import annotations

import argparse
import math
import re
from collections import defaultdict
from pathlib import Path

import gen_brr
import gen_dpcm_brr
import gen_song_dpcm
import gen_spc_image


ROOT = Path(__file__).resolve().parent.parent
SAMPLE_RE = re.compile(
    r"\{(\d+), 0x([0-9a-f]{2}), 0x([0-9a-f]{2}), 0x([0-9a-f]{2}), "
    r"(\d), 0x([0-9a-f]{4}), 0x([0-9a-f]{4})\}", re.I)
KIT_RE = re.compile(r"\{(\d+), (\d+), (\d+)\}")
INST_RE = re.compile(
    r'^INST2A03\s+(\d+)\s+.*?"([^"]*)"', re.MULTILINE)
DPCM_NAME_RE = re.compile(r'^DPCMDEF\s+\d+\s+\d+\s+"([^"]*)"',
                          re.MULTILINE)


def _decode_brr(data: bytes) -> list[int]:
    out = []
    p1 = p2 = 0
    for off in range(0, len(data), 9):
        header = data[off]
        shift, filt = header >> 4, (header >> 2) & 3
        for byte in data[off + 1:off + 9]:
            for nibble in (byte >> 4, byte & 15):
                q = nibble - 16 if nibble >= 8 else nibble
                value = gen_dpcm_brr._clamp16(
                    gen_dpcm_brr._predict(filt, p1, p2) + (q << shift))
                out.append(value)
                p2, p1 = p1, value
    return out


def _error(original: list[int], decoded: list[int]) -> tuple[float, float]:
    pairs = list(zip(original, decoded))
    peak = max((abs(v) for v in original), default=1) or 1
    worst = max((abs(a - b) for a, b in pairs), default=0)
    mse = sum((a - b) ** 2 for a, b in pairs) / max(1, len(pairs))
    return 100.0 * worst / peak, 100.0 * math.sqrt(mse) / peak


def _cents(actual: float, wanted: float) -> float:
    return 1200.0 * math.log2(actual / wanted)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=r"C:\famidash")
    ap.add_argument("--lvlset", default="lvlset_HUGE")
    ap.add_argument("--outdir", default=str(ROOT / "out"))
    args = ap.parse_args()
    source_root = Path(args.root)
    out = Path(args.outdir)
    rows = []
    failures = []

    tracker = (source_root / "MUSIC" / "INTERMEDIATES" /
               "music_master.txt").read_text(errors="replace")
    instruments = [(int(i), name or "(unnamed)")
                   for i, name in INST_RE.findall(tracker)]
    dpcm_names = DPCM_NAME_RE.findall(tracker)
    rows.append("SA-1 FAMISTUDIO / SPC700 INSTRUMENT AUDIT")
    rows.append(f"source instruments: {len(instruments)} named/macro "
                f"definitions; {len(dpcm_names)} original DPCM recordings")
    rows.append("  " + ", ".join(f"{i}:{name}" for i, name in instruments))

    # Synthesized BRR sources: compare the files with their defining 2A03
    # waveform, not with a second copy of generated output.
    rows.append("")
    rows.append("tone/noise BRR waveforms:")
    for name, make, _note in gen_brr.WAVES:
        original = make()
        encoded = (out / "brr" / f"{name}.brr").read_bytes()
        decoded = gen_brr.decode_brr(encoded)
        worst, rms = _error(original, decoded)
        rows.append(f"  {name:12s} {len(original):5d} samples, "
                    f"{len(encoded):4d} bytes, max {worst:5.2f}%, "
                    f"RMS {rms:5.2f}%")
        if worst:
            failures.append(f"{name} BRR waveform is not lossless")

    # Pitch tables are checked against the clock formulas, including the tiny
    # top-octave region the S-DSP's 4x pitch field cannot represent.
    pitch = (out / "spc" / "pitchtab.bin").read_bytes()
    tone_errors = []
    for period in range(14, 2048):
        value = pitch[period * 2] | (pitch[period * 2 + 1] << 8)
        actual = gen_spc_image.DSP_HZ * value / gen_spc_image.PITCH_UNITY
        wanted = gen_spc_image.CPU_HZ / (period + 1)
        tone_errors.append(abs(_cents(actual, wanted)))
    dpcm_pitch = (out / "spc" / "dpcmpitch.bin").read_bytes()
    dpcm_pitch_errors = []
    for i, period in enumerate(gen_spc_image.DPCM_PERIODS):
        value = dpcm_pitch[i * 2] | (dpcm_pitch[i * 2 + 1] << 8)
        actual = gen_spc_image.DSP_HZ * value / gen_spc_image.PITCH_UNITY
        wanted = gen_spc_image.CPU_HZ / period
        dpcm_pitch_errors.append(abs(_cents(actual, wanted)))
    rows.append("")
    rows.append("pitch:")
    rows.append(f"  pulse/triangle representable range: max error "
                f"{max(tone_errors):.3f} cents")
    rows.append(f"  DPCM 16-rate table: max error "
                f"{max(dpcm_pitch_errors):.3f} cents")
    rows.append("  hardware limit: pulse periods 8-13 exceed the S-DSP 4x "
                "pitch ceiling")
    rows.append("  short-noise indices 0-3: dedicated pre-aliased 32 kHz "
                "BRR sources (no pitch clamp)")
    # At the bottom of the tone table the 14-bit pitch field itself is coarse:
    # one LSB is several cents. Eight cents is the quantization ceiling; DPCM's
    # higher playback rates remain below one cent.
    if max(tone_errors) > 8.0 or max(dpcm_pitch_errors) > 1.0:
        failures.append("a pitch entry exceeds the S-DSP quantization ceiling")

    noise_table = (out / "spc" / "noisetab.bin").read_bytes()
    noise_errors = []
    rows.append("")
    rows.append("long-noise rate mapping (NES wanted -> S-DSP actual):")
    for index, period in enumerate(gen_spc_image.NES_NOISE_PERIODS):
        wanted = gen_spc_image.CPU_HZ / period
        actual = gen_spc_image.DSP_NOISE_RATES[noise_table[index]]
        error = 100.0 * abs(actual - wanted) / wanted
        noise_errors.append(error)
        rows.append(f"  {index:2d}: {wanted:9.1f} Hz -> {actual:5d} Hz "
                    f"({error:6.1f}% error)")
    rows.append("  note: long-noise indices 0-3 exceed the DSP noise clock; "
                "their output is already above Nyquist. Short mode uses the "
                "dedicated BRR sources audited above")

    # Every converted sample, including one-shot delta-counter variants.
    sample_meta = (out / "famistudio_dpcm_meta.c").read_text()
    samples = [tuple(int(v, 16 if i in (1, 2, 3, 5, 6) else 10)
                     for i, v in enumerate(match))
               for match in SAMPLE_RE.findall(sample_meta)]
    source_banks = {
        int(path.stem.replace("music_bank", "")): path.read_bytes()
        for path in (source_root / "MUSIC" / "EXPORTS" /
                     args.lvlset).glob("music_bank*.dmc")
    }
    packed_banks = {
        int(path.stem.replace("dpcm_bank", "")): path.read_bytes()
        for path in (out / "brr").glob("dpcm_bank*.brr")
    }
    quality = []
    identity_groups = defaultdict(set)
    for bank, start, length, initial, loop, offset, size in samples:
        byte_at = start * 64
        byte_count = length * 16 + 1
        raw = source_banks[bank][byte_at:byte_at + byte_count]
        raw += bytes(byte_count - len(raw))
        pcm = gen_dpcm_brr.decode_dpcm(raw, initial)
        brr = packed_banks[bank][offset:offset + size]
        worst, rms = _error(pcm, _decode_brr(brr))
        quality.append((worst, rms, bank, start, length, initial, loop, size))
        identity_groups[(bank, start, length, loop)].add(initial)
    variants = sum(len(values) - 1 for values in identity_groups.values())
    rows.append("")
    rows.append(f"DPCM/BRR: {len(samples)} decoded waveforms, including "
                f"{variants} one-shot delta-counter variants")
    rows.append(f"  looping={sum(s[4] for s in samples)}, "
                f"one-shot={sum(not s[4] for s in samples)}")
    rows.append("  ten highest conversion errors:")
    for worst, rms, bank, start, length, initial, loop, size in sorted(
            quality, reverse=True)[:10]:
        rows.append(f"    bank {bank:2d} ${start:02X}/${length:02X} "
                    f"init ${initial:02X} loop {loop}: {size:5d} bytes, "
                    f"max {worst:5.2f}%, RMS {rms:5.2f}%")
    if max(q[0] for q in quality) > 12.0:
        failures.append("a DPCM BRR conversion exceeds 12% peak error")

    songs = gen_song_dpcm._song_rows(
        (out / "famistudio_meta.c").read_text())
    kits = [tuple(map(int, values))
            for values in KIT_RE.findall(
                (out / "famistudio_song_dpcm.c").read_text())]
    dynamic = sum(item[2] != 255 for item in kits[:len(songs)])
    rows.append("")
    rows.append(f"song coverage: {len(songs)} sequencer songs, "
                f"{len(kits[:len(songs)])} generated BRR kits")
    rows.append(f"  {len(songs) - dynamic} fully resident; {dynamic} use the "
                "bounded fallback slot")
    if len(kits) < len(songs):
        failures.append("not every song has a DPCM residency kit")

    rows.append("")
    if failures:
        rows.extend("FAIL: " + failure for failure in failures)
        rows.append(f"RESULT: FAIL - {len(failures)} instrument audit issue(s)")
    else:
        rows.append("RESULT: PASS - ALL GENERATED SA-1 INSTRUMENT SOURCES AUDITED")
    report = "\n".join(rows) + "\n"
    (out / "instrument_audit.txt").write_text(report)
    print(report, end="")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
