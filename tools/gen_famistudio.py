#!/usr/bin/env python3
"""Build Famidash's original FamiStudio sequencer for the 65816.

The FamiStudio engine is 6502 assembly, but the 65816 executes that instruction
set natively.  This generator keeps the engine and the exported song data
unchanged where it matters, and supplies a small compatibility environment:

* all engine RAM and scratch live in one relocatable 256-byte direct page;
* NES APU writes land in a direct-page shadow instead of SNES I/O;
* native-mode wrappers set 8-bit A/X, D and DBR before entering the engine;
* every music ROM bank mirrors the engine/constants and SFX at the same
  addresses, while the original song blobs are packed behind that prefix.

The mirrored prefix is important.  The original engine uses 16-bit absolute
addresses for its own lookup tables and 16-bit indirect addresses for song
data.  On a 65816 both use DBR.  Mirroring the constants in every data bank lets
DBR select a song bank without translating thousands of assembly operands.

Outputs are consumed by tools/build_game.sh and tools/gen_linkcfg.py:

    out/famistudio_driver.bin       raw 6502-compatible engine
    out/famistudio_bank*.bin        complete 64KB music banks
    out/famistudio_banks.s          Calypsi .incbin wrapper
    out/famistudio_ram.s            fixed direct-page storage and public names
    out/famistudio_layout.h         direct-page offsets shared with C
    out/famistudio_meta.[ch]        global-song -> bank/address/local metadata
    out/famistudio_layout.py        build-time layout constants

This first integration intentionally leaves DPCM BRR streaming to the existing
follow-up task.  The APU shadow already exposes every DPCM register and bank
callback, so no sequencer work has to be revisited when streaming is connected.
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
BANK_SIZE = 0x10000
FS_DP_BASE = 0x1E00
FS_SA1_DP_BASE = 0x0700
EXPECTED_STATE_SIZE = 172
EXPECTED_OUTPUT_SIZE = 11


def run(cmd: list[object]) -> None:
    pretty = " ".join(str(x) for x in cmd)
    proc = subprocess.run([str(x) for x in cmd], text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if proc.returncode:
        sys.stderr.write(proc.stdout)
        raise SystemExit(f"gen_famistudio: command failed: {pretty}")


def parse_labels(path: Path) -> dict[str, int]:
    """Read ld65 -Ln output (``al 001234 .symbol``)."""
    labels: dict[str, int] = {}
    for line in path.read_text().splitlines():
        m = re.match(r"\w+\s+([0-9A-Fa-f]+)\s+\.?(\S+)", line)
        if m:
            labels[m.group(2)] = int(m.group(1), 16)
    return labels


def linker_cfg(path: Path, origin: int = 0, segment: str = "FSDRV",
               zp: bool = False) -> None:
    if zp:
        text = f"""MEMORY {{
    DP:  start = $0000, size = $0100, type = rw;
    ROM: start = ${origin:04x}, size = ${BANK_SIZE - origin:04x},
         type = ro, file = %O;
}}
SEGMENTS {{
    FSDP: load = DP,  type = zp;
    {segment}: load = ROM, type = ro, start = ${origin:04x};
}}
"""
    else:
        text = f"""MEMORY {{
    ROM: start = ${origin:04x}, size = ${BANK_SIZE - origin:04x},
         type = ro, file = %O;
}}
SEGMENTS {{
    {segment}: load = ROM, type = ro, start = ${origin:04x};
}}
SYMBOLS {{
    FAMISTUDIO_DPCM_PTR: type = weak, value = $00;
}}
"""
    path.write_text(text)


def patch_driver(source: str) -> str:
    # Put both persistent state and the seven temporary bytes in one relocatable
    # direct page.  The opening declaration gives the segment its zeropage
    # attribute before the source first switches to its RAM segment.
    source = source.replace(
        ".define FAMISTUDIO_CA65_ZP_SEGMENT   ZEROPAGE",
        ".define FAMISTUDIO_CA65_ZP_SEGMENT   FSDP")
    source = source.replace(
        ".define FAMISTUDIO_CA65_RAM_SEGMENT  BSS",
        ".define FAMISTUDIO_CA65_RAM_SEGMENT  FSDP")
    source = source.replace(
        ".define FAMISTUDIO_CA65_CODE_SEGMENT SND_DRV",
        ".define FAMISTUDIO_CA65_CODE_SEGMENT FSDRV")

    # The SNES build is 60Hz.  Keeping only NTSC removes an irrelevant branch
    # without changing the exported data format.
    source = source.replace("FAMISTUDIO_CFG_PAL_SUPPORT   = 1",
                            "FAMISTUDIO_CFG_PAL_SUPPORT   = 0")
    # Famidash's fork reads the game's `framerate` byte and switches the MMC3
    # bank around SFX.  This build is fixed 60Hz and mirrors SFX in every DBR
    # bank, so neither external dependency belongs in the compatibility island.
    source = source.replace("    lda framerate", "    lda #1")
    source = source.replace("    ldx framerate", "    ldx #1")
    source = source.replace(
        "    LDA #<.bank(sounds)\n    JSR mmc3_tmp_prg_bank_1\n", "")

    # 65816 JMP (abs) always fetches its pointer from bank 0 at the literal
    # 16-bit address; unlike ordinary direct-page operands it does not add D.
    # FamiStudio has exactly one such dispatch, through a pointer in its ZP
    # scratch.  Synthesize the same jump with RTS so the relocated DP is used.
    old_dispatch = "    jmp (@opcode_jmp_ptr)"
    new_dispatch = """    lda @opcode_jmp_ptr+0
    bne :+
    dec @opcode_jmp_ptr+1
:
    dec @opcode_jmp_ptr+0
    lda @opcode_jmp_ptr+1
    pha
    lda @opcode_jmp_ptr+0
    pha
    rts"""
    if source.count(old_dispatch) != 1:
        raise SystemExit("gen_famistudio: opcode dispatch shape changed")
    source = source.replace(old_dispatch, new_dispatch)

    # The 6502 has no zero-page,Y form for LDA/ADC, so ca65 encodes the pitch
    # macro's state-array reads as absolute,Y.  That is harmless on an NES
    # because zero page is physically $0000, but on the 65816 compatibility
    # island our direct page is relocated: absolute,Y uses DBR and was reading
    # bytes from the mirrored music ROM instead.  The resulting bogus signed
    # pitch (commonly $9EFA) was added to every otherwise-correct note.
    #
    # Temporarily put the pitch-envelope index in X so these state reads use
    # direct-page,X encodings, then restore the note index before consulting
    # the ROM note table.  This applies equally to the S-CPU and SA-1 wrappers
    # because both set D to their own audio direct page.
    pitch_macro_start = source.index(
        ".macro famistudio_get_note_pitch_macro")
    pitch_macro_end = source.index(".endmacro", pitch_macro_start)
    pitch_macro = source[pitch_macro_start:pitch_macro_end]
    pitch_alias = "    @tmp_ror = famistudio_r0\n"
    if pitch_macro.count(pitch_alias) != 1:
        raise SystemExit("gen_famistudio: pitch macro aliases changed")
    pitch_macro = pitch_macro.replace(
        pitch_alias,
        pitch_alias
        + "\n"
        + "    phx                 ; preserve note-table index\n"
        + "    tyx                 ; X = relocated-DP pitch-envelope index\n",
        1)
    state_y_operands = (
        "famistudio_pitch_env_fine_value+pitch_env_offset, y",
        "famistudio_pitch_env_value_lo+pitch_env_offset, y",
        "famistudio_pitch_env_value_hi+pitch_env_offset, y",
        "famistudio_slide_step+pitch_env_offset, y",
        "famistudio_slide_pitch_lo+pitch_env_offset, y",
        "famistudio_slide_pitch_hi+pitch_env_offset, y",
    )
    replaced = 0
    for operand in state_y_operands:
        count = pitch_macro.count(operand)
        pitch_macro = pitch_macro.replace(operand, operand[:-1] + "x")
        replaced += count
    if replaced != 11:
        raise SystemExit(
            f"gen_famistudio: patched {replaced} pitch DP,Y reads, want 11")
    note_table_marker = "    ; Finally, add note pitch.\n"
    if pitch_macro.count(note_table_marker) != 1:
        raise SystemExit("gen_famistudio: pitch note-table marker changed")
    pitch_macro = pitch_macro.replace(
        note_table_marker,
        "    plx                 ; restore note-table index\n\n"
        + note_table_marker,
        1)
    source = (source[:pitch_macro_start] + pitch_macro
              + source[pitch_macro_end:])

    # Predeclare FSDP as zeropage.  A later `.segment "FSDP"` retains this
    # attribute, so ordinary state operands get direct-page encodings too.
    source = '.setcpu "65816"\n.segment "FSDP": zeropage\n' + source

    marker = ";======================================================================================================================\n; CODE\n"
    if marker not in source:
        raise SystemExit("gen_famistudio: cannot find the driver CODE marker")
    shadow = r"""
; SNES compatibility state, still in the same relocatable direct page.
.export fs_apu_shadow, fs_dpcm_bank, fs_dpcm_seq, fs_phase_reset
.export fs_data_bank, fs_data_ptr_lo, fs_data_ptr_hi, fs_call_arg, fs_call_arg2
.export fs_dp_end
fs_apu_shadow: .res $18       ; shadows NES $4000-$4017
fs_dpcm_bank:  .res 1         ; value passed to the mapper callback
fs_dpcm_seq:   .res 1         ; changes on each DPCM start/stop event
fs_phase_reset:.res 1         ; pulse phase-reset mask produced this frame
fs_data_bank:  .res 1         ; DBR selected by the native wrappers
fs_data_ptr_lo:.res 1
fs_data_ptr_hi:.res 1
fs_call_arg:   .res 1
fs_call_arg2:  .res 1
fs_dp_end:

"""
    source = source.replace(marker, shadow + marker, 1)

    # The NES phase-reset effect is an APU write edge, not part of the eleven
    # steady-state register values. Preserve the two 2A03 pulse bits before
    # FamiStudio clears them so the S-CPU/SPC bridge can re-key only those
    # voices. Without this, sync leads and phase-reset percussion have the
    # right pitch/envelope but the wrong waveform alignment.
    phase_old = """    lda famistudio_phase_reset

    ; TODO : What about SFX here? A phase reset here will reset the SFX? Or will it?"""
    phase_new = """    lda famistudio_phase_reset
    and #$03
    sta fs_phase_reset
    lda famistudio_phase_reset

    ; TODO : What about SFX here? A phase reset here will reset the SFX? Or will it?"""
    if source.count(phase_old) != 1:
        raise SystemExit("gen_famistudio: phase-reset routine shape changed")
    source = source.replace(phase_old, phase_new, 1)

    # A frame with no $53 opcode must not repeat the previous frame's reset.
    update_old = """famistudio_update:

    @pitch_env_type = famistudio_r0"""
    update_new = """famistudio_update:

    stz fs_phase_reset

    @pitch_env_type = famistudio_r0"""
    if source.count(update_old) != 1:
        raise SystemExit("gen_famistudio: update entry shape changed")
    source = source.replace(update_old, update_new, 1)

    # No NES register address may survive into a SNES ROM.  Keeping the
    # register-number spacing makes the shadow easy to inspect and later gives
    # the DPCM streamer the exact $4010-$4015 transaction FamiStudio produced.
    apu_defs = re.compile(
        r"^(FAMISTUDIO_APU_[A-Z0-9_]+)\s*=\s*\$40([0-1][0-9a-fA-F])\s*$",
        re.MULTILINE)

    def remap(m: re.Match[str]) -> str:
        address = int("40" + m.group(2), 16)
        if not 0x4000 <= address <= 0x4017:
            raise SystemExit(f"gen_famistudio: unexpected APU address ${address:04x}")
        return f"{m.group(1):28s} = fs_apu_shadow + ${address - 0x4000:02x}"

    source, count = apu_defs.subn(remap, source)
    if count != 20:
        raise SystemExit(f"gen_famistudio: remapped {count} APU constants, want 20")

    # The final $4010-$4015 shadow describes a DPCM sample, but $4015 itself
    # stays at "enabled" after a trigger.  A sequence byte preserves the event
    # edge so the S-CPU/SPC bridge retriggers repeated drum hits with identical
    # register values.  Stop is captured too, so changing songs cannot leave a
    # long BRR voice ringing.
    start_old = """    lda #%00011111 ; Start DMC
    sta FAMISTUDIO_APU_SND_CHN"""
    start_new = start_old + "\n    inc fs_dpcm_seq"
    if source.count(start_old) != 1:
        raise SystemExit("gen_famistudio: DPCM start shape changed")
    source = source.replace(start_old, start_new, 1)
    stop_old = """famistudio_sample_stop:

    lda #%00001111
    sta FAMISTUDIO_APU_SND_CHN
    rts"""
    stop_new = """famistudio_sample_stop:

    lda #%00001111
    sta FAMISTUDIO_APU_SND_CHN
    inc fs_dpcm_seq
    rts"""
    if source.count(stop_old) != 1:
        raise SystemExit("gen_famistudio: DPCM stop shape changed")
    source = source.replace(stop_old, stop_new, 1)

    # Resolve the NES mapper callback locally and append no-argument native ABI
    # wrappers.  Calypsi enters with 16-bit A/X; the original driver requires
    # 8-bit registers, its direct page at $1E00, and the selected song bank in
    # DBR.  All caller state is restored before RTL.
    source += rf"""

; SNES DPCM bank callback.  Streaming consumes this byte together with the
; $4010-$4015 shadow after famistudio_update returns.
famistudio_dpcm_bank_callback:
    sta fs_dpcm_bank
    rts

.macro fs_native_enter
    php
    phb
    phd
    phx
    phy
    pha
    rep #$30
    .a16
    .i16
    lda #${FS_DP_BASE:04x}
    tcd
    sep #$30
    .a8
    .i8
    lda fs_data_bank
    pha
    plb
.endmacro

.macro fs_sa1_native_enter
    php
    phb
    phd
    phx
    phy
    pha
    rep #$30
    .a16
    .i16
    lda #${FS_SA1_DP_BASE:04x}
    tcd
    sep #$30
    .a8
    .i8
    lda fs_data_bank
    pha
    plb
.endmacro

.macro fs_native_leave
    rep #$30
    .a16
    .i16
    pla
    ply
    plx
    pld
    plb
    plp
    rtl
.endmacro

.export fs_native_init, fs_native_music_play, fs_native_music_pause
.export fs_native_music_stop, fs_native_update
.export fs_native_sfx_init, fs_native_sfx_play, fs_native_sfx_clear
.export fs_native_sfx_sample_play
.export fs_sa1_native_init, fs_sa1_native_music_play
.export fs_sa1_native_music_pause, fs_sa1_native_music_stop
.export fs_sa1_native_update, fs_sa1_native_sfx_init
.export fs_sa1_native_sfx_play, fs_sa1_native_sfx_clear
.export fs_sa1_native_sfx_sample_play

fs_native_init:
    fs_native_enter
    ldx fs_data_ptr_lo
    ldy fs_data_ptr_hi
    lda #1                         ; NTSC / 60Hz
    jsr famistudio_init
    fs_native_leave

fs_native_music_play:
    fs_native_enter
    lda fs_call_arg
    jsr famistudio_music_play
    fs_native_leave

fs_native_music_pause:
    fs_native_enter
    lda fs_call_arg
    jsr famistudio_music_pause
    fs_native_leave

fs_native_music_stop:
    fs_native_enter
    jsr famistudio_music_stop
    fs_native_leave

fs_native_update:
    fs_native_enter
    jsr famistudio_update
    fs_native_leave

fs_native_sfx_init:
    fs_native_enter
    ldx fs_data_ptr_lo
    ldy fs_data_ptr_hi
    jsr famistudio_sfx_init
    fs_native_leave

fs_native_sfx_play:
    fs_native_enter
    lda fs_call_arg
    ldx fs_call_arg2
    jsr famistudio_sfx_play
    fs_native_leave

fs_native_sfx_clear:
    fs_native_enter
    ldx fs_call_arg
    jsr famistudio_sfx_clear_channel
    fs_native_leave

fs_native_sfx_sample_play:
    fs_native_enter
    lda fs_call_arg
    jsr famistudio_sfx_sample_play
    fs_native_leave

; The SA-1 executes the same 6502 engine natively.  Its private direct page is
; I-RAM $0700 instead of S-CPU WRAM $1E00; the bytes are simultaneously visible
; to the S-CPU at $3700, which lets the existing vblank-side SPC transport read
; the register image without a copy or another command channel.
fs_sa1_native_init:
    fs_sa1_native_enter
    ldx fs_data_ptr_lo
    ldy fs_data_ptr_hi
    lda #1
    jsr famistudio_init
    fs_native_leave

fs_sa1_native_music_play:
    fs_sa1_native_enter
    lda fs_call_arg
    jsr famistudio_music_play
    fs_native_leave

fs_sa1_native_music_pause:
    fs_sa1_native_enter
    lda fs_call_arg
    jsr famistudio_music_pause
    fs_native_leave

fs_sa1_native_music_stop:
    fs_sa1_native_enter
    jsr famistudio_music_stop
    fs_native_leave

fs_sa1_native_update:
    fs_sa1_native_enter
    jsr famistudio_update
    fs_native_leave

fs_sa1_native_sfx_init:
    fs_sa1_native_enter
    ldx fs_data_ptr_lo
    ldy fs_data_ptr_hi
    jsr famistudio_sfx_init
    fs_native_leave

fs_sa1_native_sfx_play:
    fs_sa1_native_enter
    lda fs_call_arg
    ldx fs_call_arg2
    jsr famistudio_sfx_play
    fs_native_leave

fs_sa1_native_sfx_clear:
    fs_sa1_native_enter
    ldx fs_call_arg
    jsr famistudio_sfx_clear_channel
    fs_native_leave

fs_sa1_native_sfx_sample_play:
    fs_sa1_native_enter
    lda fs_call_arg
    jsr famistudio_sfx_sample_play
    fs_native_leave
"""
    return source


def assemble_driver(root: Path, out: Path) -> tuple[bytes, dict[str, int]]:
    ca65 = root / "BIN" / "ca65.exe"
    ld65 = root / "BIN" / "ld65.exe"
    src = root / "LIB" / "asm" / "famistudio_ca65.s"
    for tool in (ca65, ld65, src):
        if not tool.exists():
            raise SystemExit(f"gen_famistudio: missing {tool}")

    patched = out / "famistudio_snes.s"
    patched.write_text(patch_driver(src.read_text()))
    cfg = out / "famistudio_driver.cfg"
    obj = out / "famistudio_driver.o"
    raw = out / "famistudio_driver.bin"
    labels = out / "famistudio_driver.lbl"
    linker_cfg(cfg, zp=True)
    run([ca65, "--cpu", "65816", "-I", src.parent,
         "--bin-include-dir", src.parent, "-o", obj, "-l",
         out / "famistudio_driver.lst", patched])
    run([ld65, "-C", cfg, "-o", raw, "-Ln", labels, obj])
    syms = parse_labels(labels)

    required = (
        "_famistudio_state", "_famistudio_output_buf",
        "_famistudio_song_speed", "fs_dp_end", "fs_apu_shadow",
        "fs_dpcm_bank", "fs_dpcm_seq", "fs_phase_reset",
        "fs_data_bank", "fs_data_ptr_lo",
        "fs_data_ptr_hi", "fs_call_arg", "fs_call_arg2",
        "fs_native_init", "fs_native_music_play", "fs_native_music_pause",
        "fs_native_music_stop", "fs_native_update", "fs_native_sfx_init",
        "fs_native_sfx_play", "fs_native_sfx_clear",
        "fs_native_sfx_sample_play",
        "fs_sa1_native_init", "fs_sa1_native_music_play",
        "fs_sa1_native_music_pause", "fs_sa1_native_music_stop",
        "fs_sa1_native_update", "fs_sa1_native_sfx_init",
        "fs_sa1_native_sfx_play", "fs_sa1_native_sfx_clear",
        "fs_sa1_native_sfx_sample_play",
    )
    missing = [name for name in required if name not in syms]
    if missing:
        raise SystemExit("gen_famistudio: missing driver symbols: "
                         + ", ".join(missing))
    state_size = syms["_famistudio_output_buf"] - syms["_famistudio_state"]
    if state_size != EXPECTED_STATE_SIZE:
        raise SystemExit(f"gen_famistudio: FamiStudio state is {state_size} "
                         f"bytes, game ABI says {EXPECTED_STATE_SIZE}")
    if syms["fs_dp_end"] > 0x100:
        raise SystemExit(f"gen_famistudio: direct page needs "
                         f"{syms['fs_dp_end']} bytes")
    return raw.read_bytes(), syms


def assemble_blob(ca65: Path, ld65: Path, src: Path, out: Path,
                  stem: str, origin: int) -> bytes:
    cfg = out / f"{stem}.cfg"
    obj = out / f"{stem}.o"
    raw = out / f"{stem}.bin"
    # Generated exports do not name a segment and therefore use ca65's CODE
    # segment.  Assemble the file directly; an absolute Windows path inside an
    # `.include` string is not accepted by this ca65 build.
    linker_cfg(cfg, origin=origin, segment="CODE")
    run([ca65, "-o", obj, src])
    run([ld65, "-C", cfg, "-o", raw, obj])
    return raw.read_bytes()


def song_count(path: Path) -> int:
    text = path.read_text()
    m = re.search(r"^music_data_[^:]+:\s*\n\s*\.byte\s+([^\s,;]+)",
                  text, re.MULTILINE)
    if not m:
        raise SystemExit(f"gen_famistudio: cannot read song count from {path}")
    return int(m.group(1).replace("$", "0x"), 0)


def active_music_file_count(exports: Path) -> int:
    """Number of data files selected by the level set's generated bank table."""
    text = (exports / "musicPlayRoutines.s").read_text()
    m = re.search(r"music_counts:\s*\n\s*\.byte\s+([^;]+)", text)
    if not m:
        raise SystemExit("gen_famistudio: cannot parse musicPlayRoutines.s")
    values = [x.strip() for x in m.group(1).split(",")]
    # The original mapper loop uses $FF as a sentinel for the last data file;
    # it still represents one real file, so the entry count is the file count.
    return len(values)


def emit_ram_assembly(out: Path, syms: dict[str, int]) -> None:
    # Labels exported to C.  Private regions are represented only by padding.
    points = {
        syms["_famistudio_state"]: "famistudio_state",
        syms["_famistudio_song_speed"]: "famistudio_song_speed",
        syms["_famistudio_output_buf"]: "famistudio_output_buf",
        syms["fs_apu_shadow"]: "famistudio_apu_shadow",
        syms["fs_dpcm_bank"]: "famistudio_dpcm_bank",
        syms["fs_dpcm_seq"]: "famistudio_dpcm_seq",
        syms["fs_phase_reset"]: "famistudio_phase_reset_mask",
        syms["fs_data_bank"]: "famistudio_data_bank",
        syms["fs_data_ptr_lo"]: "famistudio_data_ptr_lo",
        syms["fs_data_ptr_hi"]: "famistudio_data_ptr_hi",
        syms["fs_call_arg"]: "famistudio_call_arg",
        syms["fs_call_arg2"]: "famistudio_call_arg2",
    }
    lines = [
        "; Generated by tools/gen_famistudio.py - do not edit.",
        "        .rtmodel version, \"1\"",
        "        .rtmodel codeModel, \"large\"",
        "        .rtmodel dataModel, \"large\"",
        "        .rtmodel core, \"65816\"",
        "        .rtmodel huge, \"0\"",
        "",
        "        .section fsaudioram,bss",
    ]
    cursor = 0
    for offset, name in sorted(points.items()):
        if offset < cursor:
            raise SystemExit(f"gen_famistudio: overlapping RAM label {name}")
        if offset > cursor:
            lines.append(f"        .space {offset - cursor}")
        lines += [f"        .public {name}", f"{name}:"]
        cursor = offset
    end = syms["fs_dp_end"]
    if end > cursor:
        lines.append(f"        .space {end - cursor}")
    lines.append("")
    (out / "famistudio_ram.s").write_text("\n".join(lines))


def emit_bank_assembly(out: Path, bank_count: int,
                       wrapper_offsets: dict[str, int]) -> None:
    # Split bank 0 at wrapper entry points so the Calypsi linker gets real
    # symbols at their raw-binary offsets.  Other banks are data-only mirrors.
    exports = {
        "fs_native_init": "famistudio_native_init",
        "fs_native_music_play": "famistudio_native_music_play",
        "fs_native_music_pause": "famistudio_native_music_pause",
        "fs_native_music_stop": "famistudio_native_music_stop",
        "fs_native_update": "famistudio_native_update",
        "fs_native_sfx_init": "famistudio_native_sfx_init",
        "fs_native_sfx_play": "famistudio_native_sfx_play",
        "fs_native_sfx_clear": "famistudio_native_sfx_clear",
        "fs_native_sfx_sample_play": "famistudio_native_sfx_sample_play",
        "fs_sa1_native_init": "famistudio_sa1_native_init",
        "fs_sa1_native_music_play": "famistudio_sa1_native_music_play",
        "fs_sa1_native_music_pause": "famistudio_sa1_native_music_pause",
        "fs_sa1_native_music_stop": "famistudio_sa1_native_music_stop",
        "fs_sa1_native_update": "famistudio_sa1_native_update",
        "fs_sa1_native_sfx_init": "famistudio_sa1_native_sfx_init",
        "fs_sa1_native_sfx_play": "famistudio_sa1_native_sfx_play",
        "fs_sa1_native_sfx_clear": "famistudio_sa1_native_sfx_clear",
        "fs_sa1_native_sfx_sample_play": "famistudio_sa1_native_sfx_sample_play",
    }
    ordered = sorted((wrapper_offsets[k], v) for k, v in exports.items())
    bank0 = (out / "famistudio_bank0.bin").read_bytes()
    lines = [
        "; Generated by tools/gen_famistudio.py - do not edit.",
        "        .rtmodel version, \"1\"",
        "        .rtmodel codeModel, \"large\"",
        "        .rtmodel dataModel, \"large\"",
        "        .rtmodel core, \"65816\"",
        "        .rtmodel huge, \"0\"",
        "",
        "        .section fsmusic0,rodata,root",
    ]
    cursor = 0
    for index, (offset, public) in enumerate(ordered):
        chunk = out / f"famistudio_bank0_chunk{index}.bin"
        chunk.write_bytes(bank0[cursor:offset])
        lines.append(f'        .incbin "out/{chunk.name}"')
        lines.append(f"        .public {public}")
        lines.append(f"{public}:")
        cursor = offset
    tail = out / f"famistudio_bank0_chunk{len(ordered)}.bin"
    tail.write_bytes(bank0[cursor:])
    lines.append(f'        .incbin "out/{tail.name}"')
    for i in range(1, bank_count):
        lines.append(f"        .section fsmusic{i},rodata,root")
        lines.append(f'        .incbin "out/famistudio_bank{i}.bin"')
    lines.append("")
    (out / "famistudio_banks.s").write_text("\n".join(lines))


def emit_metadata(out: Path, songs: list[tuple[int, int, int, int]],
                  sfx_origin: int, bank_count: int,
                  syms: dict[str, int]) -> None:
    # (ROM-bank index, address, local song, source file)
    header = """/* Generated by tools/gen_famistudio.py - do not edit. */
#ifndef FAMISTUDIO_META_H
#define FAMISTUDIO_META_H
#include <stdint.h>
typedef struct {
    uint8_t bank;
    uint16_t address;
    uint8_t local_song;
    uint8_t source;
} FamiStudioSong;
extern const FamiStudioSong famistudio_songs[];
extern const uint8_t famistudio_song_count;
extern const uint16_t famistudio_sfx_address;
#endif
"""
    (out / "famistudio_meta.h").write_text(header)
    rows = "\n".join(
        f"    {{{bank}, 0x{addr:04x}, {local}, {source}}},"
        for bank, addr, local, source in songs)
    c = f"""/* Generated by tools/gen_famistudio.py - do not edit. */
#include "famistudio_meta.h"
const FamiStudioSong famistudio_songs[] = {{
{rows}
}};
const uint8_t famistudio_song_count = {len(songs)};
const uint16_t famistudio_sfx_address = 0x{sfx_origin:04x};
"""
    (out / "famistudio_meta.c").write_text(c)
    lua_rows = "\n".join(
        f"    {{ bank={bank}, address=0x{addr:04x}, "
        f"local_song={local}, source={source} }},"
        for bank, addr, local, source in songs)
    (out / "famistudio_meta.lua").write_text(
        "-- Generated by tools/gen_famistudio.py - do not edit.\n"
        "return {\n"
        f"  sfx_address=0x{sfx_origin:04x},\n"
        "  songs={\n"
        f"{lua_rows}\n"
        "  }\n"
        "}\n")
    layout = f"""# Generated by tools/gen_famistudio.py - do not edit.
FS_BANK_COUNT = {bank_count}
FS_DP_BASE = 0x{FS_DP_BASE:04x}
FS_SA1_DP_BASE = 0x{FS_SA1_DP_BASE:04x}
FS_STATE_SIZE = {EXPECTED_STATE_SIZE}
FS_OUTPUT_SIZE = {EXPECTED_OUTPUT_SIZE}
FS_OUTPUT_OFFSET = 0x{syms["_famistudio_output_buf"]:02x}
"""
    (out / "famistudio_layout.py").write_text(layout)
    c_layout = f"""/* Generated by tools/gen_famistudio.py - do not edit. */
#ifndef FAMISTUDIO_LAYOUT_H
#define FAMISTUDIO_LAYOUT_H
#define FAMISTUDIO_DP_BASE 0x{FS_DP_BASE:04x}u
#define FAMISTUDIO_SA1_DP_BASE 0x{FS_SA1_DP_BASE:04x}u
#define FAMISTUDIO_OUTPUT_OFFSET 0x{syms["_famistudio_output_buf"]:02x}u
#define FAMISTUDIO_APU_SHADOW_OFFSET 0x{syms["fs_apu_shadow"]:02x}u
#define FAMISTUDIO_DPCM_BANK_OFFSET 0x{syms["fs_dpcm_bank"]:02x}u
#define FAMISTUDIO_DPCM_SEQ_OFFSET 0x{syms["fs_dpcm_seq"]:02x}u
#define FAMISTUDIO_PHASE_RESET_OFFSET 0x{syms["fs_phase_reset"]:02x}u
#define FAMISTUDIO_OUTPUT_SIZE {EXPECTED_OUTPUT_SIZE}u
/* The S-CPU sees SA-1 I-RAM $0000-$07ff at its bank-zero $3000 mirror. */
#define FAMISTUDIO_SA1_OUTPUT_SCPU \\
    (0x3000u + FAMISTUDIO_SA1_DP_BASE + FAMISTUDIO_OUTPUT_OFFSET)
#endif
"""
    (out / "famistudio_layout.h").write_text(c_layout)
    (out / "famistudio_layout.lua").write_text(
        "-- Generated by tools/gen_famistudio.py - do not edit.\n"
        "return {\n"
        f"  dp=0x{FS_DP_BASE:04x}, sa1_dp=0x{FS_SA1_DP_BASE:04x},\n"
        f"  output_offset=0x{syms['_famistudio_output_buf']:02x},\n"
        f"  apu_shadow_offset=0x{syms['fs_apu_shadow']:02x},\n"
        f"  dpcm_bank_offset=0x{syms['fs_dpcm_bank']:02x},\n"
        f"  dpcm_seq_offset=0x{syms['fs_dpcm_seq']:02x},\n"
        f"  phase_reset_offset=0x{syms['fs_phase_reset']:02x},\n"
        f"  data_bank_offset=0x{syms['fs_data_bank']:02x},\n"
        f"  size=0x{syms['fs_dp_end']:02x}\n"
        "}\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=r"C:\famidash")
    ap.add_argument("--lvlset", default="lvlset_HUGE")
    ap.add_argument("--outdir", default=str(ROOT / "out"))
    args = ap.parse_args()
    root = Path(args.root)
    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)
    exports = root / "MUSIC" / "EXPORTS" / args.lvlset
    ca65, ld65 = root / "BIN" / "ca65.exe", root / "BIN" / "ld65.exe"

    driver, syms = assemble_driver(root, out)

    # SFX is identical in every selected music bank, just like the driver's
    # absolute lookup tables.
    sfx_origin = (len(driver) + 0xFF) & ~0xFF
    sfx = assemble_blob(ca65, ld65, exports / "sfx.s", out,
                        "famistudio_sfx", sfx_origin)
    song_floor = (sfx_origin + len(sfx) + 0xFF) & ~0xFF
    if song_floor >= BANK_SIZE:
        raise SystemExit("gen_famistudio: driver + SFX do not fit a bank")
    prefix = bytearray(song_floor)
    prefix[:len(driver)] = driver
    prefix[sfx_origin:sfx_origin + len(sfx)] = sfx

    files = sorted(
        (p for p in exports.glob("music_[0-9]*.s")
         if re.fullmatch(r"music_\d+", p.stem)),
        key=lambda p: int(p.stem.split("_")[1]))
    files = files[:active_music_file_count(exports)]
    # Compile once at zero to get exact sizes before packing.
    sized: list[tuple[Path, int, int]] = []
    for p in files:
        idx = int(p.stem.split("_")[1])
        raw = assemble_blob(ca65, ld65, p, out,
                            f"famistudio_size_{idx}", 0)
        sized.append((p, song_count(p), len(raw)))

    banks: list[bytearray] = [bytearray(prefix)]
    placements: list[tuple[int, int, int, int]] = []
    cursor = song_floor
    global_song = 0
    for p, count, size in sized:
        if cursor + size > BANK_SIZE:
            banks[-1].extend(b"\0" * (BANK_SIZE - len(banks[-1])))
            banks.append(bytearray(prefix))
            cursor = song_floor
        file_idx = int(p.stem.split("_")[1])
        raw = assemble_blob(ca65, ld65, p, out,
                            f"famistudio_music_{file_idx}", cursor)
        if len(raw) != size:
            raise SystemExit(f"gen_famistudio: origin changed size of {p.name}")
        if len(banks[-1]) < cursor:
            banks[-1].extend(b"\0" * (cursor - len(banks[-1])))
        banks[-1].extend(raw)
        for local in range(count):
            placements.append((len(banks) - 1, cursor, local, file_idx))
            global_song += 1
        cursor += size

    if len(placements) > 255:
        raise SystemExit("gen_famistudio: song count no longer fits uint8_t")
    for i, bank in enumerate(banks):
        bank.extend(b"\0" * (BANK_SIZE - len(bank)))
        (out / f"famistudio_bank{i}.bin").write_bytes(bank)

    emit_ram_assembly(out, syms)
    emit_bank_assembly(out, len(banks), syms)
    emit_metadata(out, placements, sfx_origin, len(banks), syms)

    print(f"    FamiStudio: {len(driver)}-byte sequencer, {len(sfx)}-byte "
          f"SFX, {len(placements)} songs in {len(banks)} x 64KB banks")
    print(f"    direct page: ${FS_DP_BASE:04X}-${FS_DP_BASE + syms['fs_dp_end'] - 1:04X} "
          f"({syms['fs_dp_end']} bytes), song data starts at ${song_floor:04X}")
    print(f"    SA-1 I-RAM: ${FS_SA1_DP_BASE:04X}-"
          f"${FS_SA1_DP_BASE + syms['fs_dp_end'] - 1:04X}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
