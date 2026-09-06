"""Generate the BRR working set used by each packed FamiStudio song.

The exported files all contain the complete 61-entry DPCM note table, so that
table cannot tell us what a song actually plays.  The fifth channel can: this
script walks the assembled FamiStudio bytecode with the same reference, loop,
repeat and opcode rules as famistudio_advance_channel, then maps its sample
notes back to the generated BRR blobs made by gen_dpcm_brr.py, including
one-shot variants selected by their initial delta-counter value.

Almost every song's complete working set fits in ARAM.  For an exceptional
song that does not, a small knapsack chooses the samples covering the most
hits while reserving one maximum-sized slot for the bounded runtime streamer.
"""

import argparse
import re
from collections import Counter
from pathlib import Path


DPCM_ARAM_BASE = 0x2000
DPCM_ARAM_BYTES = 0x10000 - DPCM_ARAM_BASE

SONG_RE = re.compile(
    r"\{(\d+), 0x([0-9a-fA-F]+), (\d+), (\d+)\}")
SAMPLE_META_RE = re.compile(
    r"\{(\d+), 0x([0-9a-fA-F]{2}), 0x([0-9a-fA-F]{2}), "
    r"0x([0-9a-fA-F]{2}), (\d), 0x([0-9a-fA-F]{4}), "
    r"0x([0-9a-fA-F]{4})\}")


def _word(data, at):
    return data[at] | (data[at + 1] << 8)


def _song_rows(meta):
    return [
        (int(bank), int(address, 16), int(local), int(source))
        for bank, address, local, source in SONG_RE.findall(meta)
    ]


def _sample_rows(meta):
    rows = []
    for bank, start, length, initial, loop, offset, size in (
            SAMPLE_META_RE.findall(meta)):
        rows.append({
            "key": (int(bank), int(start, 16), int(length, 16),
                    int(initial, 16), int(loop)),
            "offset": int(offset, 16),
            "size": int(size, 16),
        })
    return rows


def _walk_dpcm_events(data, song_base, local_song):
    """Return ``(table index, initial override)`` for one complete song.

    FamiStudio's $52 opcode can arm a one-shot DMC delta-counter value.  The
    next sample starts from that value instead of the initial value stored in
    the five-byte DPCM note table, then the override clears.  That changes the
    decoded waveform whenever the 2A03's 7-bit counter saturates, so it cannot
    be approximated by reusing the default BRR blob.

    An opcode value with bit 7 set writes $4011 immediately and does not arm
    the next sample.  Those writes only move the currently playing DAC level;
    a later normal sample trigger writes its own table initial value.
    """
    channel = _word(data, song_base + 5 + local_song * 14 + 8)
    pointer = channel
    repeat = 0
    ref_rows = 0
    ref_return = 0
    dmc_counter = None
    seen = set()
    events = []

    for _row in range(200000):
        # A stale return pointer is irrelevant when no reference is active.
        state = (pointer, repeat, ref_rows,
                 ref_return if ref_rows else 0, dmc_counter)
        if state in seen:
            return events
        seen.add(state)

        count_reference_row = True
        if repeat:
            repeat -= 1
        else:
            for _guard in range(10000):
                opcode = data[pointer]
                pointer = (pointer + 1) & 0xFFFF

                if opcode < 0x40:
                    if opcode:
                        events.append((opcode, dmc_counter))
                        dmc_counter = None
                    break

                if opcode < 0x70:
                    if opcode == 0x40:       # extended note
                        note = data[pointer]
                        pointer = (pointer + 1) & 0xFFFF
                        if note >= 12:
                            events.append((note - 12, dmc_counter))
                            dmc_counter = None
                        break
                    if opcode == 0x41:       # counted reference
                        ref_rows = data[pointer]
                        destination = _word(data, pointer + 1)
                        ref_return = (pointer + 3) & 0xFFFF
                        pointer = destination
                        continue
                    if opcode == 0x42:       # loop
                        pointer = _word(data, pointer)
                        continue
                    if opcode == 0x43:       # no attack
                        continue
                    if opcode == 0x44:       # end song
                        return events
                    if opcode == 0x45:       # release note
                        break
                    if opcode == 0x47:       # delayed note
                        pointer = (pointer + 1) & 0xFFFF
                        # The driver jumps directly to @flush_y, deliberately
                        # not consuming a row from a counted reference.
                        count_reference_row = False
                        break
                    if opcode == 0x48:       # delayed cut
                        pointer = (pointer + 1) & 0xFFFF
                        continue
                    if opcode == 0x52:       # one-shot/immediate DMC counter
                        value = data[pointer]
                        pointer = (pointer + 1) & 0xFFFF
                        if not value & 0x80:
                            dmc_counter = value & 0x7f
                        continue

                    parameter_bytes = {
                        0x46: 1,             # FamiTracker speed
                        0x49: 2, 0x4A: 0,    # vibrato override / clear
                        0x4B: 2, 0x4C: 0, 0x4D: 0,  # arpeggio
                        0x4E: 1,             # fine pitch
                        0x4F: 1,             # duty
                        0x50: 3,             # slide (ends this row)
                        0x51: 2,             # volume slide
                        0x53: 0,             # phase reset
                        0x54: 1,             # extended instrument
                    }.get(opcode)
                    if parameter_bytes is None:
                        raise ValueError(
                            f"unsupported DPCM opcode ${opcode:02X} "
                            f"at ${pointer - 1:04X}")
                    if opcode == 0x50:
                        target = data[(pointer + 2) & 0xFFFF]
                        if target >= 12:
                            events.append((target - 12, dmc_counter))
                            dmc_counter = None
                        pointer = (pointer + 3) & 0xFFFF
                        break
                    pointer = (pointer + parameter_bytes) & 0xFFFF
                    continue

                if opcode < 0x80:            # volume track
                    continue

                value = opcode & 0x7F
                if value & 1:                # empty-note run
                    repeat = value >> 1
                    break
                # Even values are instrument changes and do not end the row.
            else:
                raise ValueError("DPCM bytecode did not end a row")

        if count_reference_row and ref_rows:
            ref_rows -= 1
            if not ref_rows:
                pointer = ref_return

    raise ValueError("DPCM bytecode did not loop or end")


def _walk_dpcm(data, song_base, local_song):
    """Compatibility helper returning only DPCM note-table indices."""
    return [table_index for table_index, _ in
            _walk_dpcm_events(data, song_base, local_song)]


def _select_hot_samples(sample_ids, events, sizes, capacity):
    """0/1 knapsack: maximize covered note triggers within `capacity`."""
    counts = Counter(events)
    scale = 9                         # every BRR blob is whole 9-byte blocks
    cap = capacity // scale
    dp = [-1] * (cap + 1)
    masks = [0] * (cap + 1)
    dp[0] = 0

    for bit, sample_id in enumerate(sample_ids):
        weight = (sizes[sample_id] + scale - 1) // scale
        value = counts[sample_id]
        for used in range(cap, weight - 1, -1):
            if dp[used - weight] < 0:
                continue
            candidate = dp[used - weight] + value
            if candidate > dp[used]:
                dp[used] = candidate
                masks[used] = masks[used - weight] | (1 << bit)

    best = max(range(cap + 1), key=lambda used: (dp[used], used))
    mask = masks[best]
    return {
        sample_id for bit, sample_id in enumerate(sample_ids)
        if mask & (1 << bit)
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default="out")
    args = ap.parse_args()
    out = Path(args.outdir)

    songs = _song_rows((out / "famistudio_meta.c").read_text())
    samples = _sample_rows((out / "famistudio_dpcm_meta.c").read_text())
    if not songs or not samples:
        raise SystemExit("gen_song_dpcm: missing generated music/DPCM metadata")

    banks = {
        bank: (out / f"famistudio_bank{bank}.bin").read_bytes()
        for bank in {song[0] for song in songs}
    }
    by_key = {sample["key"]: i for i, sample in enumerate(samples)}
    sizes = [sample["size"] for sample in samples]
    max_sample = max(sizes)

    kits = []
    flat_samples = []
    oversize = 0
    for song_id, (bank, address, local, _source) in enumerate(songs):
        data = banks[bank]
        table = _word(data, address + 3)
        table_events = _walk_dpcm_events(data, address, local)
        sample_events = []
        for table_index, initial_override in table_events:
            row = (table + table_index * 5) & 0xFFFF
            start, length, freq, initial, dpcm_bank = data[row:row + 5]
            if initial_override is not None:
                initial = initial_override
            key = (dpcm_bank, start, length, initial & 0x7F,
                   (freq >> 6) & 1)
            if key not in by_key:
                raise SystemExit(
                    f"gen_song_dpcm: song {song_id} table index "
                    f"{table_index} has unknown sample {key}")
            sample_events.append(by_key[key])

        used = sorted(set(sample_events))
        total = sum(sizes[i] for i in used)
        dynamic = 0xFF
        if total > DPCM_ARAM_BYTES:
            oversize += 1
            resident_capacity = DPCM_ARAM_BYTES - max_sample
            selected = _select_hot_samples(
                used, sample_events, sizes, resident_capacity)
            # Start with the first non-resident instrument already in the
            # reserved slot. Its first note remains sample-accurate; later
            # replacements use the bounded streamer.
            dynamic = next(i for i in sample_events if i not in selected)
            used = sorted(selected)
            packed = sum(sizes[i] for i in used) + sizes[dynamic]
            if packed > DPCM_ARAM_BYTES:
                raise SystemExit(
                    f"gen_song_dpcm: song {song_id} kit overflow ({packed})")

        kits.append((len(flat_samples), len(used), dynamic))
        flat_samples.extend(used)

    header = """/* Generated by tools/gen_song_dpcm.py - do not edit. */
#ifndef FAMISTUDIO_SONG_DPCM_H
#define FAMISTUDIO_SONG_DPCM_H
#include <stdint.h>
typedef struct {
    uint16_t offset;
    uint8_t count;
    uint8_t dynamic_first;
} FamiStudioDpcmKit;
extern const FamiStudioDpcmKit famistudio_dpcm_kits[];
extern const uint8_t famistudio_dpcm_kit_samples[];
extern const uint8_t famistudio_dpcm_kit_count;
#endif
"""
    (out / "famistudio_song_dpcm.h").write_text(header)
    kit_rows = "\n".join(
        f"    {{{offset}, {count}, {dynamic}}},"
        for offset, count, dynamic in kits)
    sample_rows = []
    for at in range(0, len(flat_samples), 24):
        sample_rows.append(
            "    " + ", ".join(str(v) for v in flat_samples[at:at + 24])
            + ",")
    source = f"""/* Generated by tools/gen_song_dpcm.py - do not edit. */
#include "famistudio_song_dpcm.h"
const FamiStudioDpcmKit famistudio_dpcm_kits[] = {{
{kit_rows}
}};
const uint8_t famistudio_dpcm_kit_samples[] = {{
{chr(10).join(sample_rows)}
}};
const uint8_t famistudio_dpcm_kit_count = {len(kits)};
"""
    (out / "famistudio_song_dpcm.c").write_text(source)
    print(
        f"    DPCM residency: {len(kits) - oversize}/{len(kits)} complete "
        f"song kits fit ARAM; {oversize} use a bounded fallback slot")


if __name__ == "__main__":
    main()
