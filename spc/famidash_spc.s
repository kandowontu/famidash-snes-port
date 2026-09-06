; ======================================================================
; The Famidash SNES audio driver - SPC700 side.
;
; WHAT THIS IS NOT: a music sequencer. The music is FamiStudio data written
; for the 2A03 and the musicians' workflow is that data, so the sequencer
; stays FamiStudio's own. What this is, is the 2A03 itself: it takes the
; eleven APU register bytes FamiStudio produces every frame and plays them
; on the S-DSP.
;
; THE SEAM IS ALREADY IN FAMISTUDIO. With FAMISTUDIO_CFG_SFX_SUPPORT on -
; which this game has on - famistudio_ca65.s does not write $4000 at all
; while it works. It fills an eleven-byte `famistudio_output_buf` and copies
; that to the APU in one block at the end (the FAMISTUDIO_ALIAS_* equates,
; famistudio_ca65.s:1280). So the port does not have to intercept scattered
; register writes: it replaces that final copy, and the eleven bytes are the
; whole interface between the two machines.
;
;   0  PL1_VOL     DDLC VVVV   duty in bits 6-7, volume in bits 0-3
;   1  PL1_LO      period low
;   2  PL1_HI      period high, bits 0-2
;   3  PL2_VOL     4  PL2_LO   5  PL2_HI
;   6  TRI_LINEAR  $80 | volume - the triangle has no volume, so this is
;                  really "plays or not": bits 0-6 zero means silent
;   7  TRI_LO      8  TRI_HI
;   9  NOISE_VOL   $F0 | volume
;  10  NOISE_LO    mode in bit 7, (15 - period index) in bits 0-3... NO:
;                  FamiStudio writes the period INDEX in bits 0-3 already
;                  complemented against $0F, which is what the 2A03 expects,
;                  so bits 0-3 index the noise period table directly.
;
; HOW EACH VOICE IS PLAYED
;
;   pulse 1, 2  DSP voices 0 and 1, one of four looping single-cycle BRR
;               squares chosen by the duty bits.
;   triangle    DSP voice 2, the 32-step staircase, looping.
;   noise       DSP voice 3. Long mode uses NON hardware noise; ordinary short
;               mode uses source 5's exact 93-step loop, while the four rates
;               above the DSP pitch ceiling use pre-aliased sources 6..9.
;   DPCM        DSP voice 4, sample-by-sample BRR converted from the original
;               .dmc banks. A generated per-song kit is resident before play;
;               identical hits are retriggered by a sequence byte outside the
;               eleven-byte tone image.
;
; NO KEY-ON PER ORDINARY NOTE. Every waveform is a looping
; sample and every voice is keyed on ONCE at init with its volume at zero.
; The 2A03 has no note-on either: a channel is audible when its volume field
; is non-zero and silent when it is not, and pitch changes take effect
; immediately without restarting the waveform. Keying on per note would
; restart the phase and click on every vibrato step. There are two deliberate
; exceptions: the S-DSP latches SRCN at key-on, so pulse duty-envelope and
; short-noise source changes must re-key their voice, and FamiStudio's explicit
; $53 phase-reset effect must be preserved. The S-CPU combines those edges into
; CMD_TONE_KEYON.
;
; Assembled by tools/spcasm.py; the image is built by tools/gen_spc_image.py,
; which also generates the three lookup tables at the bottom of this file.
; ======================================================================

; ---- SPC700 hardware, all in the direct page ----
CONTROL  = $F1
DSPADDR  = $F2
DSPDATA  = $F3
CPUIO0   = $F4          ; command/sequence, and the ack back to the S-CPU
CPUIO1   = $F5          ; index
CPUIO2   = $F6          ; value at index
CPUIO3   = $F7          ; value at index+1

; ---- S-DSP register numbers ----
DSP_VOL_L  = $00        ; +$10 per voice
DSP_VOL_R  = $01
DSP_P_L    = $02
DSP_P_H    = $03
DSP_SRCN   = $04
DSP_ADSR1  = $05
DSP_GAIN   = $07
DSP_MVOL_L = $0C
DSP_MVOL_R = $1C
DSP_EVOL_L = $2C
DSP_EVOL_R = $3C
DSP_KON    = $4C
DSP_KOF    = $5C
DSP_FLG    = $6C
DSP_EFB    = $0D
DSP_PMON   = $2D
DSP_NON    = $3D
DSP_EON    = $4D
DSP_DIR    = $5D
DSP_EDL    = $7D

; ---- protocol ----
CMD_COMMIT  = $FF       ; apply the frame buffer to the DSP
CMD_SILENCE = $FE       ; every voice to zero volume
CMD_DPCM_BEGIN = $FD    ; payload is absolute fallback upload address
CMD_DPCM_DATA  = $FC    ; append the two payload bytes
CMD_DPCM_START = $FB    ; payload is absolute BRR start address
CMD_DPCM_PLAY  = $FA    ; payload 0 is the original $4010 frequency byte
CMD_DPCM_STOP  = $F9
CMD_DPCM_SIZE  = $F8    ; enter 3-byte bulk mode for this many BRR bytes
CMD_DPCM_DATA1 = $F7    ; append one byte (bounded per-frame fallback tail)
CMD_TONE_KEYON = $F6    ; pulse/noise source change / explicit reset mask
READY0      = $BB       ; what the S-CPU waits to see in ports 0 and 1 once
READY1      = $A5       ; the driver has finished initialising the DSP
DPCM_BASE   = $2000

; ---- mixing levels ----
;
; The waveforms are full-scale BRR, so the headroom lives here rather than in
; the sample data - a quiet sample and a loud volume would throw away bits.
; VOLTAB (generated below) tops out well short of $7F for the same reason the
; 2A03's own mixer is not linear: four voices at once must not clip the DSP's
; 16-bit accumulator.
MVOL   = $60
TRIVOL = $2A            ; the triangle has no volume control on the 2A03
DPCMVOL = $26

; ---- direct page variables ----
seq      = $00          ; the last sequence byte acknowledged
tmp      = $01          ; the DSP volume being computed
srcn     = $02
ptr      = $04          ; word, into the pitch table
pitbase  = $06          ; word, = PITCHTAB
period   = $08          ; word
pitchlo  = $0A
pitchhi  = $0B
chbase   = $0C          ; index of this channel's first byte in fb
vbase    = $0D          ; this channel's DSP voice register base
dpcmptr  = $0E          ; word, next byte of the resident DPCM bank
fb       = $10          ; the twelve-byte frame buffer (eleven used)
dpcmleft = $1C          ; word, non-zero only during synchronous bulk loading

            .org $0200

; ======================================================================
; Entry. The IPL jumps here once the image is in ARAM.
; ======================================================================
start:
            clrp                        ; direct page $00xx
            mov   x, #$ff
            mov   sp, x

            ; Silence the DSP before touching anything else: ARAM comes up
            ; with whatever the last program left in it and a voice keyed on
            ; over garbage is a full-volume screech at power-on.
            mov   x, #DSP_FLG
            mov   a, #$60               ; MUTE, and echo writes disabled
            call  !dsp_write
            mov   x, #DSP_KOF
            mov   a, #$ff
            call  !dsp_write

            ; Clear the frame buffer, so a commit before the first frame
            ; arrives produces silence rather than whatever was in RAM.
            mov   x, #12
            mov   a, #0
clear_fb:
            dec   x
            mov   fb+x, a
            bne   clear_fb
            mov   dpcmleft+0, a
            mov   dpcmleft+1, a

            ; pitbase is a direct-page word because ADDW has no immediate
            ; form - the pitch lookup adds it to the doubled period.
            mov   pitbase+0, #<PITCHTAB
            mov   pitbase+1, #>PITCHTAB

            ; ---- global DSP setup ----
            mov   x, #DSP_DIR
            mov   a, #>DIRTAB
            call  !dsp_write
            mov   x, #DSP_MVOL_L
            mov   a, #MVOL
            call  !dsp_write
            mov   x, #DSP_MVOL_R
            mov   a, #MVOL
            call  !dsp_write
            ; No echo: EVOL and EDL zero, EON zero, and FLG keeps echo writes
            ; disabled throughout. An echo buffer would have to be allocated
            ; in ARAM and there is a DPCM bank to fit there first.
            mov   x, #DSP_EVOL_L
            mov   a, #0
            call  !dsp_write
            mov   x, #DSP_EVOL_R
            mov   a, #0
            call  !dsp_write
            mov   x, #DSP_EDL
            mov   a, #0
            call  !dsp_write
            mov   x, #DSP_EFB
            mov   a, #0
            call  !dsp_write
            mov   x, #DSP_EON
            mov   a, #0
            call  !dsp_write
            mov   x, #DSP_PMON
            mov   a, #0
            call  !dsp_write
            ; Voice 3 is the noise channel: the DSP substitutes its own LFSR
            ; for that voice's sample, which is why the noise needs no BRR.
            mov   x, #DSP_NON
            mov   a, #%00001000
            call  !dsp_write

            ; ---- per-voice setup ----
            ; ADSR off and GAIN at direct maximum, so the envelope is a
            ; constant 127 and VOL_L/VOL_R alone decide loudness. That is the
            ; 2A03's model, and it is what lets a note change volume without
            ; a key-on.
            mov   y, #0                 ; voice number, and its source number
            mov   vbase, #$00
voice_init:
            mov   x, vbase
            call  !voice_defaults
            mov   a, vbase
            clrc
            adc   a, #$10
            mov   vbase, a
            inc   y
            cmp   y, #5
            bne   voice_init

            ; ---- key on, once, for the whole run ----
            ;
            ; KON AND KOF ARE LEVEL-TRIGGERED, NOT EDGE-TRIGGERED. The DSP
            ; samples both every output sample and acts on whatever bits are
            ; set, so a bit left standing does not mean "this happened once", it
            ; means "keep doing this". Both of those bit here:
            ;
            ;   the KOF $FF written above to silence power-on garbage keeps
            ;   every voice keyed off forever if it is not released, and the
            ;   voices then hold an envelope of zero no matter what VOL says -
            ;   which looks exactly like the volume translation being broken;
            ;
            ;   and KON left set re-keys the voice every sample, so the envelope
            ;   never gets past its five-sample key-on delay and the result is
            ;   the same silence from the other direction.
            ;
            ; So: release KOF, pulse KON, and hold it long enough for the DSP to
            ; see it before clearing it again.
            mov   x, #DSP_KOF
            mov   a, #0
            call  !dsp_write
            mov   x, #DSP_KON
            mov   a, #%00001111         ; voice 4 (DPCM) has nothing to play yet
            call  !dsp_write

            ; An output sample is 32 SPC cycles; this is about 1000, so the DSP
            ; cannot miss the pulse however the two clocks happen to line up.
            mov   y, #0
kon_hold:
            dec   y
            bne   kon_hold

            mov   x, #DSP_KON
            mov   a, #0
            call  !dsp_write

            ; Unmute. Noise rate 0 until the first commit sets it.
            mov   x, #DSP_FLG
            mov   a, #$20
            call  !dsp_write

            ; THE BASELINE IS WHAT THE S-CPU LAST WROTE, not a constant.
            ;
            ; Port 0 is two registers, not one: reading CPUIO0 gives what the
            ; S-CPU wrote, writing it is only seen by the S-CPU. So seeding
            ; `seq` from the READY byte written below would compare our own
            ; output against the S-CPU's input and could match by accident -
            ; the IPL's last write to port 0 is a byte counter and can be any
            ; value. Reading it is exact: whatever is there now is what the
            ; boot loader left, and the first frame transaction differs from it
            ; because the S-CPU counts on from that same value.
            mov   a, CPUIO0
            mov   seq, a

            ; Tell the S-CPU the driver is alive. Everything above has to have
            ; happened first: the S-CPU starts sending frames the instant it
            ; sees this. Two ports, because port 0 alone is a byte the IPL
            ; could plausibly have left there on its own.
            mov   a, #READY1
            mov   CPUIO1, a
            mov   a, #READY0
            mov   CPUIO0, a

; ======================================================================
; The main loop: wait for the sequence byte to change, take the payload,
; acknowledge.
;
; The S-CPU writes the two data ports BEFORE the sequence port, so by the
; time the change is visible here the payload is already there. The ack is
; the same byte written back, which is what the S-CPU spins on - a counter
; of our own would drift the first time a frame was dropped.
; ======================================================================
main:
            mov   a, CPUIO0
            cmp   a, seq
            beq   main
            mov   seq, a

            ; During a prepared song-kit upload all three payload ports are
            ; BRR bytes. This raises each acknowledged transaction from two
            ; bytes to three. The mode ends by itself at the exact byte count,
            ; so arbitrary sample data can contain every command value.
            mov   a, dpcmleft+0
            bne   jump_dpcm_bulk
            mov   a, dpcmleft+1
            bne   jump_dpcm_bulk

            mov   a, CPUIO1
            cmp   a, #CMD_COMMIT
            beq   do_commit
            cmp   a, #CMD_SILENCE
            beq   do_silence
            cmp   a, #CMD_DPCM_BEGIN
            beq   jump_dpcm_begin
            cmp   a, #CMD_DPCM_DATA
            beq   jump_dpcm_data
            cmp   a, #CMD_DPCM_START
            beq   jump_dpcm_start
            cmp   a, #CMD_DPCM_PLAY
            beq   jump_dpcm_play
            cmp   a, #CMD_DPCM_STOP
            beq   jump_dpcm_stop
            cmp   a, #CMD_DPCM_SIZE
            beq   jump_dpcm_size
            cmp   a, #CMD_DPCM_DATA1
            beq   jump_dpcm_data1
            cmp   a, #CMD_TONE_KEYON
            beq   jump_tone_keyon
            bra   ordinary_data

jump_dpcm_begin:
            jmp   !do_dpcm_begin
jump_dpcm_data:
            jmp   !do_dpcm_data
jump_dpcm_start:
            jmp   !do_dpcm_start
jump_dpcm_play:
            jmp   !do_dpcm_play
jump_dpcm_stop:
            jmp   !do_dpcm_stop
jump_dpcm_size:
            jmp   !do_dpcm_size
jump_dpcm_data1:
            jmp   !do_dpcm_data1
jump_tone_keyon:
            jmp   !do_tone_keyon
jump_dpcm_bulk:
            jmp   !do_dpcm_bulk

            ; Otherwise it is an index into the frame buffer, and the two
            ; data ports carry that byte and the one after it.
ordinary_data:
            mov   x, a
            mov   a, CPUIO2
            mov   fb+x, a
            inc   x
            mov   a, CPUIO3
            mov   fb+x, a
            jmp   !ack

do_silence:
            mov   x, #12
            mov   a, #0
silence_loop:
            dec   x
            mov   fb+x, a
            bne   silence_loop
            ; and fall through: an all-zero buffer commits to silence

do_commit:
            call  !apply
            jmp   !ack

; ----------------------------------------------------------------------
; Resident DPCM BRR kits, bounded fallback upload, and trigger commands.
; ----------------------------------------------------------------------
do_dpcm_begin:
            mov   a, CPUIO2
            mov   dpcmptr+0, a
            mov   a, CPUIO3
            mov   dpcmptr+1, a
            jmp   !ack

do_dpcm_size:
            mov   a, CPUIO2
            mov   dpcmleft+0, a
            mov   a, CPUIO3
            mov   dpcmleft+1, a
            jmp   !ack

do_dpcm_bulk:
            mov   y, #0
            mov   a, CPUIO1
            mov   [dpcmptr]+y, a
            incw  dpcmptr
            decw  dpcmleft
            mov   a, dpcmleft+0
            bne   dpcm_bulk_second
            mov   a, dpcmleft+1
            beq   dpcm_bulk_done
dpcm_bulk_second:
            mov   a, CPUIO2
            mov   [dpcmptr]+y, a
            incw  dpcmptr
            decw  dpcmleft
            mov   a, dpcmleft+0
            bne   dpcm_bulk_third
            mov   a, dpcmleft+1
            beq   dpcm_bulk_done
dpcm_bulk_third:
            mov   a, CPUIO3
            mov   [dpcmptr]+y, a
            incw  dpcmptr
            decw  dpcmleft
dpcm_bulk_done:
            jmp   !ack

do_dpcm_data:
            mov   y, #0
            mov   a, CPUIO2
            mov   [dpcmptr]+y, a
            inc   y
            mov   a, CPUIO3
            mov   [dpcmptr]+y, a
            incw  dpcmptr
            incw  dpcmptr
            jmp   !ack

do_dpcm_data1:
            mov   y, #0
            mov   a, CPUIO2
            mov   [dpcmptr]+y, a
            incw  dpcmptr
            jmp   !ack

do_dpcm_start:
            ; Source 10's directory entry. Every converted DPCM loop returns to
            ; its own start, while a one-shot ignores the loop address.
            mov   a, CPUIO2
            mov   !DIRTAB+40, a
            mov   !DIRTAB+42, a
            mov   a, CPUIO3
            mov   !DIRTAB+41, a
            mov   !DIRTAB+43, a
            jmp   !ack

do_dpcm_play:
            ; Original $4010 low nibble -> exact NTSC DPCM rate.
            mov   a, CPUIO2
            and   a, #$0f
            asl   a
            mov   x, a
            mov   a, !DPCMPITCH+x
            mov   pitchlo, a
            inc   x
            mov   a, !DPCMPITCH+x
            mov   pitchhi, a

            mov   x, #$40
            mov   DSPADDR, x
            mov   a, #DPCMVOL
            mov   DSPDATA, a
            inc   x
            mov   DSPADDR, x
            mov   DSPDATA, a
            inc   x
            mov   DSPADDR, x
            mov   a, pitchlo
            mov   DSPDATA, a
            inc   x
            mov   DSPADDR, x
            mov   a, pitchhi
            mov   DSPDATA, a
            inc   x
            mov   DSPADDR, x
            mov   a, #10
            mov   DSPDATA, a

            ; Stop the previous hit, then pulse key-on. Both registers are
            ; level-triggered and must be cleared again.
            mov   x, #DSP_KOF
            mov   a, #$10
            call  !dsp_write
            mov   y, #0
dpcm_kof_hold:
            dec   y
            bne   dpcm_kof_hold
            mov   x, #DSP_KOF
            mov   a, #0
            call  !dsp_write
            mov   x, #DSP_KON
            mov   a, #$10
            call  !dsp_write
            mov   y, #0
dpcm_kon_hold:
            dec   y
            bne   dpcm_kon_hold
            mov   x, #DSP_KON
            mov   a, #0
            call  !dsp_write
            jmp   !ack

do_dpcm_stop:
            mov   x, #$40
            mov   DSPADDR, x
            mov   a, #0
            mov   DSPDATA, a
            inc   x
            mov   DSPADDR, x
            mov   DSPDATA, a
            mov   x, #DSP_KOF
            mov   a, #$10
            call  !dsp_write
            mov   y, #0
dpcm_stop_hold:
            dec   y
            bne   dpcm_stop_hold
            mov   x, #DSP_KOF
            mov   a, #0
            call  !dsp_write
            jmp   !ack

; Re-latch the current SRCN and reset phase for requested pulse/noise voices.
; KON is a level input, so hold it across several DSP samples and clear it.
do_tone_keyon:
            mov   x, #DSP_KON
            mov   a, CPUIO2
            and   a, #%00001011
            call  !dsp_write
            mov   y, #0
tone_kon_hold:
            dec   y
            bne   tone_kon_hold
            mov   x, #DSP_KON
            mov   a, #0
            call  !dsp_write
            jmp   !ack
ack:
            mov   a, seq
            mov   CPUIO0, a
            jmp   !main

; ======================================================================
; DSP register write.  X = register number, A = value.
; ======================================================================
dsp_write:
            mov   DSPADDR, x
            mov   DSPDATA, a
            ret

; ----------------------------------------------------------------------
; Per-voice constants, for the voice whose register base is in X.
; ----------------------------------------------------------------------
voice_defaults:
            mov   DSPADDR, x
            mov   a, #0
            mov   DSPDATA, a            ; VOL_L
            inc   x
            mov   DSPADDR, x
            mov   DSPDATA, a            ; VOL_R
            inc   x
            mov   DSPADDR, x
            mov   DSPDATA, a            ; P_L
            inc   x
            mov   DSPADDR, x
            mov   DSPDATA, a            ; P_H
            inc   x
            mov   DSPADDR, x
            mov   a, y                  ; SRCN: voice N starts on source N,
            mov   DSPDATA, a            ; which puts the triangle on voice 2
            inc   x
            mov   DSPADDR, x
            mov   a, #0
            mov   DSPDATA, a            ; ADSR1 = 0 -> GAIN mode
            inc   x
            inc   x
            mov   DSPADDR, x
            mov   a, #$7f
            mov   DSPDATA, a            ; GAIN: direct, maximum
            ret

; ======================================================================
; Apply the frame buffer.
; ======================================================================
apply:
            mov   chbase, #0
            mov   vbase, #$00
            call  !upd_pulse
            mov   chbase, #3
            mov   vbase, #$10
            call  !upd_pulse
            call  !upd_tri
            call  !upd_noise
            ret

; ----------------------------------------------------------------------
; A pulse channel.  chbase = first fb byte, vbase = DSP voice base.
; ----------------------------------------------------------------------
upd_pulse:
            ; volume: the low nibble of the volume byte, through the table
            mov   x, chbase
            mov   a, fb+x
            and   a, #$0f
            mov   x, a
            mov   a, !VOLTAB+x
            mov   tmp, a

            ; duty: bits 6-7 of the same byte. XCN puts them at bits 2-3.
            mov   x, chbase
            mov   a, fb+x
            xcn   a
            lsr   a
            lsr   a
            and   a, #$03
            mov   srcn, a

            ; period, eleven bits across the next two bytes
            mov   x, chbase
            inc   x
            mov   a, fb+x
            mov   period+0, a
            inc   x
            mov   a, fb+x
            and   a, #$07
            mov   period+1, a

            ; The 2A03 mutes a pulse whose period is below 8 - it is above
            ; the audible range and the hardware's own sweep unit silences
            ; it. Without this the pitch table's clamp would turn a muted
            ; channel into a very loud one at the top of the DSP's range.
            mov   a, period+1
            bne   pulse_audible
            mov   a, period+0
            cmp   a, #8
            bcs   pulse_audible
            mov   tmp, #0
pulse_audible:
            call  !lookup_pitch
            call  !write_voice
            ret

; ----------------------------------------------------------------------
; The triangle. One voice, no volume control: bits 0-6 of TRI_LINEAR are
; FamiStudio's "plays or not".
; ----------------------------------------------------------------------
upd_tri:
            mov   vbase, #$20
            mov   srcn, #4
            mov   a, fb+6
            and   a, #$7f
            beq   tri_silent
            mov   tmp, #TRIVOL
            bra   tri_period
tri_silent:
            mov   tmp, #0
tri_period:
            mov   a, fb+7
            mov   period+0, a
            mov   a, fb+8
            and   a, #$07
            mov   period+1, a
            ; The 2A03 mutes the triangle below period 2, and for the same
            ; reason as the pulses: at that period it is inaudible and only
            ; produces a click on the DAC.
            mov   a, period+1
            bne   tri_audible
            mov   a, period+0
            cmp   a, #2
            bcs   tri_audible
            mov   tmp, #0
tri_audible:
            call  !lookup_pitch
            call  !write_voice
            ret

; ----------------------------------------------------------------------
; The noise. Long mode uses the DSP generator. Short-mode periods 4..32 use
; sources 6..9, pre-aliased at their final 32 kHz rate because they exceed the
; DSP pitch limit; the other periods use source 5's exact 93-step NES loop.
; ----------------------------------------------------------------------
upd_noise:
            mov   a, fb+9
            and   a, #$0f
            mov   x, a
            mov   a, !VOLTAB+x
            mov   tmp, a

            mov   a, fb+10
            bmi   noise_short

            mov   x, #DSP_NON
            mov   a, #%00001000
            call  !dsp_write
            mov   x, #$30               ; voice 3, VOL_L
            mov   DSPADDR, x
            mov   a, tmp
            mov   DSPDATA, a
            mov   x, #$31
            mov   DSPADDR, x
            mov   a, tmp
            mov   DSPDATA, a
            bra   noise_rate

noise_short:
            mov   x, #DSP_NON
            mov   a, #0
            call  !dsp_write
            mov   a, fb+10
            and   a, #$0f
            cmp   a, #4
            bcs   noise_short_regular
            clrc
            adc   a, #6
            mov   srcn, a
            mov   pitchlo, #$00
            mov   pitchhi, #$10
            bra   noise_short_write

noise_short_regular:
            asl   a
            mov   x, a
            mov   a, !NOISEPITCH+x
            mov   pitchlo, a
            inc   x
            mov   a, !NOISEPITCH+x
            mov   pitchhi, a
            mov   srcn, #5

noise_short_write:
            mov   vbase, #$30
            call  !write_voice

            ; The 2A03's sixteen noise periods onto the DSP's thirty-two
            ; noise rates, nearest match; see gen_spc_image.py for the
            ; derivation. Bit 5 keeps echo writes disabled.
noise_rate:
            mov   a, fb+10
            and   a, #$0f
            mov   x, a
            mov   a, !NOISETAB+x
            or    a, #$20
            mov   x, #DSP_FLG
            mov   DSPADDR, x
            mov   DSPDATA, a
            ret

; ----------------------------------------------------------------------
; period -> DSP pitch, through the table.
;
; A table and not a division: the DSP pitch is 229091/(period+1) and the
; SPC700's only divide is 16/8. Doing it in software would be a couple of
; hundred cycles every time a note moved, several times a frame, on a
; processor that has 17000 cycles to spend between frames.
; ----------------------------------------------------------------------
lookup_pitch:
            ; The SPC700 has no 16-bit shift - ASL/ROL are 8-bit and there is
            ; no ROL Y - so the doubling is an add of the value to itself.
            ; ADDW ignores the incoming carry, which is what makes two of them
            ; in a row safe.
            movw  ya, period
            addw  ya, period            ; YA = period * 2
            addw  ya, pitbase
            movw  ptr, ya
            mov   y, #0
            mov   a, [ptr]+y
            mov   pitchlo, a
            inc   y
            mov   a, [ptr]+y
            mov   pitchhi, a
            ret

; ----------------------------------------------------------------------
; Push tmp/pitch/srcn into the voice whose register base is vbase.
; ----------------------------------------------------------------------
write_voice:
            mov   x, vbase
            mov   DSPADDR, x
            mov   a, tmp
            mov   DSPDATA, a            ; VOL_L
            inc   x
            mov   DSPADDR, x
            mov   a, tmp
            mov   DSPDATA, a            ; VOL_R
            inc   x
            mov   DSPADDR, x
            mov   a, pitchlo
            mov   DSPDATA, a
            inc   x
            mov   DSPADDR, x
            mov   a, pitchhi
            mov   DSPDATA, a
            inc   x
            mov   DSPADDR, x
            mov   a, srcn
            mov   DSPDATA, a
            ret

; ======================================================================
; Generated data. tools/gen_spc_image.py writes these three files; the
; derivations and the arithmetic are documented there rather than here so
; there is exactly one copy of each.
; ======================================================================
            .align 16
VOLTAB:
            .incbin "voltab.bin"        ; 16 bytes: 2A03 volume -> DSP volume
NOISETAB:
            .incbin "noisetab.bin"      ; 16 bytes: 2A03 period -> DSP rate
DPCMPITCH:
            .incbin "dpcmpitch.bin"     ; 16 DPCM rates -> DSP pitch
NOISEPITCH:
            .incbin "noisepitch.bin"    ; sampled short-noise rates

            .align 256
DIRTAB:
            .incbin "dirtab.bin"        ; the BRR sample directory
SAMPLES:
            .incbin "samples.bin"       ; the five looping waveforms

            .align 2
PITCHTAB:
            .incbin "pitchtab.bin"      ; 2048 periods -> DSP pitch, 2 bytes
