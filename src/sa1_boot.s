;;; sa1_boot.s - the S-CPU half of an SA-1 cartridge, and the SA-1's entry stub.
;;;
;;; Two processors, one link. The division is fixed by hardware: the SA-1 cannot
;;; touch the PPU, the DMA controller or the pads, so everything that talks to
;;; $2100-$21FF and $4200-$43FF stays on the S-CPU no matter how the rest is
;;; arranged. Everything else can move.
;;;
;;; HOW THE TWO ENTRY POINTS ARE ARRANGED.
;;;
;;; Calypsi's cstartup declares `__program_root_section` - the word at $FFFC -
;;; and `__program_start` as `.pubweak`. So a strong definition here takes the
;;; reset vector for the S-CPU, while cstartup's `__program_start` stays exactly
;;; where it is and becomes the SA-1's entry instead. The C runtime is then set
;;; up by the processor that is going to use it, which is the SA-1, and none of
;;; it had to be rewritten.
;;;
;;; WHY THERE IS A STUB IN FRONT OF IT.
;;;
;;; cstartup sets the stack pointer and immediately `call`s __low_level_init,
;;; which pushes. The SA-1's stack lives in the BW-RAM window, and BOTH I-RAM
;;; and BW-RAM come up write-protected - so those pushes would be dropped on the
;;; floor and the first `rts` would return into nothing. The permissions have to
;;; be open before cstartup runs a single instruction, and __low_level_init is
;;; already too late. Hence sa1_entry.

                .rtmodel version, "1"
                .rtmodel core, "65816"

CCNT            .equ 0x2200     ; S-CPU -> SA-1 control; bit 5 RESB
CRV             .equ 0x2203     ; the SA-1's reset vector
SIWP            .equ 0x2229     ; S-CPU I-RAM write permission, 1 bit per 256B
CIWP            .equ 0x222A     ; SA-1 I-RAM write permission
SBWE            .equ 0x2226     ; S-CPU BW-RAM write enable, bit 7
CBWE            .equ 0x2227     ; SA-1 BW-RAM write enable, bit 7
BWPA            .equ 0x2228     ; BW-RAM write-protected area size
SBMAP           .equ 0x2224     ; which 8KB of BW-RAM the S-CPU's window shows
CBMAP           .equ 0x2225     ; ...and the SA-1's
EXB             .equ 0x2222     ; ROM megabyte mapped into $E0-$EF/$80-$9F
FXB             .equ 0x2223     ; ROM megabyte mapped into $F0-$FF/$A0-$BF

HVBJOY          .equ 0x4212     ; bit 7 vblank, bit 0 auto-joypad busy
NMITIMEN        .equ 0x4200     ; bit 0 arms the auto-joypad read
JOY1L           .equ 0x4218
JOY2L           .equ 0x421A

;;; The mailbox. Must match shim/src/shim_sa1.h - the C half addresses it as a
;;; struct and this half by number.
;;;
;;; THE TWO PROCESSORS SEE I-RAM AT DIFFERENT ADDRESSES. The SA-1 has it at
;;; $0000-$07FF (and again at $3000-$37FF); the S-CPU has it ONLY at
;;; $3000-$37FF. So the C side's $0100 is $3100 here, and using the same number
;;; on both sides does not fault - it silently reads WRAM $0100 instead, which
;;; is a perfectly valid address holding something else entirely.
MB_BASE         .equ 0x3000     ; the S-CPU's window onto I-RAM $0000
MB_SA1_SEQ      .equ MB_BASE+0x0100
MB_SCPU_SEQ     .equ MB_BASE+0x0101
MB_PAD0         .equ MB_BASE+0x0102
MB_PAD1         .equ MB_BASE+0x0104
MB_REQ          .equ MB_BASE+0x0108
MB_ACK          .equ MB_BASE+0x0109

                .extern __program_start
                .extern shim_scpu_frame
                .extern spc_frame_flush

;;; The S-CPU's own C environment. It runs the shim's flush routines - the same
;;; C the HiROM ROM runs - so it needs a direct page and a stack, and sharing
;;; either with the SA-1 would corrupt whichever one was mid-call.
;;;
;;; Both live in WRAM, which is the S-CPU's alone: the SA-1 cannot see $7E/$7F
;;; at all, so nothing there can collide with it and none of the scarce 2KB of
;;; I-RAM is spent on it.
;;;
;;; The first attempt put the stack in I-RAM at $37FF. It grew down into the
;;; mailbox and overwrote boot_ack, which is the kind of fault that looks like
;;; the other processor misbehaving rather than like a stack overflow.
SCPU_DP         .equ 0x0200     ; WRAM; also what the compiler's dp: resolves to
SCPU_STACK      .equ 0x1FFF     ; WRAM, growing down - nothing else is there

;;; ---- the S-CPU's reset vector ---------------------------------------------
;;; Strong, so it wins over cstartup's weak definition.
                .section reset, root
                .public __program_root_section
__program_root_section:
                .word   scpu_boot

;;; ---- the S-CPU ------------------------------------------------------------
                .section sa1code, text, root
                .public scpu_boot

scpu_boot:
                sei
                clc
                xce                     ; native mode
                rep     #0x30
                ldx     ##0x1FFF
                txs

                ;; Run through the physical bank-$C0 mirror of this LoROM boot
                ;; block.  The old code used bank $80 for FastROM, but $80 is
                ;; controlled by EXB; mapping the ROM's third megabyte there
                ;; for music would replace the code under the S-CPU's feet.
                ;; $C0 is FastROM too and remains mapped to megabyte zero.
                jmp     long:scpu_body+0xBF8000
scpu_body:
                sep     #0x20
                lda     #0x01
                sta     0x420D          ; MEMSEL: 3.58MHz, which an SA-1
                                        ; cartridge does still grant the S-CPU
                ;; The full ROM is padded/declared as 4MB. Reset maps only its
                ;; first 2MB and mirrors those at $E0-$FF; the final three
                ;; FamiStudio banks live at $E0-$E2, so expose megabytes 2/3.
                lda     #0x02
                sta     EXB
                lda     #0x03
                sta     FXB
                lda     #0x8F
                sta     0x2100          ; screen off until something draws

                ;; The S-CPU's own access to the shared memories. Both come up
                ;; fully protected; each bit of SIWP opens one 256-byte block of
                ;; I-RAM, and bit 7 of SBWE opens BW-RAM.
                lda     #0xFF
                sta     SIWP
                lda     #0x80
                sta     SBWE
                lda     #0x00
                sta     SBMAP           ; the S-CPU's window: BW-RAM block 0

                ;; Arm the automatic joypad read. NMI itself stays off - there
                ;; is no handler - but bit 0 is what makes the controller
                ;; latched into $4218 every frame without the CPU doing it.
                lda     #0x01
                sta     NMITIMEN

                ;; Zero the S-CPU's direct page. The compiler keeps its scratch
                ;; there - _Vfp among it, which cstartup clears - and this is
                ;; the S-CPU's own page, so nothing else will do it.
                rep     #0x30
                ldx     ##0x00FE
scpu_dpclr:     stz     SCPU_DP,x
                dex
                dex
                bpl     scpu_dpclr

                ;; The C environment, set once: direct page, stack, and a data
                ;; bank of 0 because `near` data lives in the BW-RAM window at
                ;; $6000, which is bank 0.
                lda     ##SCPU_STACK
                tcs
                lda     ##SCPU_DP
                tcd
                lda     ##0
                pha
                plb
                plb

                ;; Clear the mailbox. I-RAM IS NOT ZEROED AT POWER-ON, and
                ;; nothing else clears it - the SA-1's cstartup zeroes BSS in
                ;; BW-RAM, not this. Left as it came up, `boot_ack` held $86,
                ;; which made shim_scpu_frame's `!boot_ack` false, so video_init
                ;; never ran and the screen showed uninitialised VRAM while
                ;; every other part of the port worked perfectly.
                rep     #0x30
                ldx     ##0x003E
scpu_mbclr:     stz     MB_BASE+0x0100,x
                dex
                dex
                bpl     scpu_mbclr

                ;; The screen-control shadow starts at forced blank, so the
                ;; first flush does not switch the screen on before the game
                ;; asks. video_init runs on the first frame, from the frame
                ;; loop, once the SA-1's cstartup has zeroed BSS.
                sep     #0x20
                lda     #0x8F
                sta     MB_BASE+0x0106  ; mailbox .inidisp
                stz     MB_BASE+0x0107  ; mailbox .tm
                rep     #0x30

                ;; Start the SA-1 on the C runtime, through the stub that opens
                ;; ITS permissions. Vector first, release second.
                rep     #0x20
                lda     ##sa1_entry
                sta     CRV
                sep     #0x20
                lda     #0x00
                sta     CCNT            ; clear RESB

;;; ---- the S-CPU's frame loop ------------------------------------------------
;;; Once per vblank: push whatever the SA-1 has left in the mailbox, then echo
;;; its sequence number so it can start the next frame.
;;;
;;; The echo is the pacing. The SA-1 has none of its own - see the comment in
;;; shim/src/shim_sa1.h - so until this loop runs the game free-runs and no
;;; frame ever completes.
scpu_frame:
                ;; Wait for the START of vblank, not merely for vblank to be
                ;; true. Entering while it is already half over would leave the
                ;; transfers short of the time they need, and on a frame the
                ;; SA-1 finished early this loop would otherwise run twice.
                ;; long: throughout this loop. It runs either side of a `jsl`
                ;; into compiled C, which is free to leave the data bank
                ;; wherever it liked, and an absolute access would then land in
                ;; the wrong bank - silently, because every bank has something
                ;; readable at these addresses.
                sep     #0x20
                lda     #0x01
                sta     long:NMITIMEN   ; arm the auto-joypad read, every frame:
                                        ; video_init clears it and the order in
                                        ; which the two processors get there is
                                        ; not worth depending on
scpu_wait_lo:   lda     long:HVBJOY
                and     #0x80
                bne     scpu_wait_lo    ; still in the previous vblank
scpu_wait_hi:   lda     long:HVBJOY
                and     #0x80
                beq     scpu_wait_hi    ; now wait for it to begin

                ;; Only touch shared producer buffers when the SA-1 has
                ;; explicitly finished a frame or is blocked on a request.
                ;;
                ;; The old loop flushed unconditionally every vblank. If the
                ;; SA-1 was still between oam_clear() and draw_sprites() (most
                ;; often on palette-heavy frames), the S-CPU DMA'd that partial
                ;; shadow OAM and left sprites missing or stuck for one display
                ;; frame. A repeated sequence with no request means no complete
                ;; producer state is ready, so retain the last complete PPU
                ;; state and try again at the next vblank. Requests count as
                ;; ready work because shim_request() leaves the SA-1 spinning
                ;; without touching the shared buffers.
                lda     long:MB_SA1_SEQ
                cmp     long:MB_SCPU_SEQ
                bne     scpu_have_work
                lda     long:MB_REQ
                cmp     long:MB_ACK
                bne     scpu_have_work

                ;; A repeated display frame still needs a completed auto-joy
                ;; read. Besides keeping the mailbox's input current, this is
                ;; what an emulator uses to distinguish an intentionally held
                ;; video frame from a game that missed input polling entirely.
                ;; Do not acknowledge a sequence here: the SA-1 is still
                ;; producing it and its shared PPU buffers remain untouched.
scpu_idle_joy:  lda     long:HVBJOY
                and     #0x01
                bne     scpu_idle_joy
                rep     #0x20
                lda     long:JOY1L
                sta     long:MB_PAD0
                lda     long:JOY2L
                sta     long:MB_PAD1

                ;; The auto-joy read itself takes about three scanlines. A
                ;; dense SA-1 frame can finish just after that wait, while
                ;; enough vblank remains for this ROM's now-CHR-free normal
                ;; flush. Give it a short, strictly bounded grace window before
                ;; holding the prior complete frame. 64 mailbox polls are
                ;; about eight scanlines on the S-CPU; this still leaves over
                ;; twenty scanlines for OAM, CGRAM, CHR and the other queues.
                sep     #0x20
                ldx     ##64
scpu_late_wait:
                lda     long:MB_SA1_SEQ
                cmp     long:MB_SCPU_SEQ
                bne     scpu_have_work
                lda     long:MB_REQ
                cmp     long:MB_ACK
                bne     scpu_have_work
                dex
                bne     scpu_late_wait
scpu_frame_relay:
                bra     scpu_frame

                ;; Push the frame. This is the shim's own code - the deferred
                ;; video_init on the first frame, then screen control, scroll,
                ;; CGRAM, the VRAM and column queues, OAM, a budgeted slice of
                ;; any pending CHR bank, and the level select's transfer -
                ;; reading the SA-1's buffers where they sit in BW-RAM.
scpu_have_work: jsl     shim_scpu_frame

                ;; Re-establish the register widths. The assembler tracks
                ;; sep/rep statically and cannot see through a jsl, so it keeps
                ;; assembling 8-bit immediates below - while the compiled C is
                ;; free to return with a 16-bit accumulator. When it does, the
                ;; CPU takes two bytes for the `and #0x01` operand, eats the
                ;; next opcode, and the loop desynchronises.
                ;;
                ;; This is why the menu ran at 60Hz and gameplay crawled: the
                ;; two take different paths through the flush and left different
                ;; widths behind.
                sep     #0x20
                rep     #0x10

                ;; The pads, for the SA-1 to read: it cannot reach $4218 itself,
                ;; so without this the game never sees a button. Auto-joypad
                ;; read is armed by NMITIMEN and takes about three scanlines from
                ;; the start of vblank, so HVBJOY bit 0 has to be clear first.
scpu_joy_busy:  lda     long:HVBJOY
                and     #0x01
                bne     scpu_joy_busy
                rep     #0x20
                lda     long:JOY1L
                sta     long:MB_PAD0
                lda     long:JOY2L
                sta     long:MB_PAD1

                ;; Echo the sequence number. This is what releases the SA-1 from
                ;; its spin in ppu_wait_nmi, so it goes LAST - everything above
                ;; has to be done with the buffers before the SA-1 may touch
                ;; them again.
                sep     #0x20
                lda     long:MB_SA1_SEQ
                sta     long:MB_SCPU_SEQ

                ;; Audio uses the snapshot shim_scpu_flush made before this
                ;; acknowledgement. Its SPC700 port handshakes need the S-CPU
                ;; but not vblank, so overlap them with the SA-1's next frame
                ;; instead of keeping the producer serialized behind them.
                jsl     spc_frame_flush
                sep     #0x20
                rep     #0x10
                bra     scpu_frame_relay

;;; ---- the SA-1's entry stub -------------------------------------------------
;;; Reached from CRV. Opens the SA-1's side of both shared memories, then hands
;;; over to the C runtime, which from this point behaves exactly as it does in
;;; the main port.
                .public sa1_entry
sa1_entry:
                sei
                clc
                xce
                sep     #0x20

                lda     #0xFF
                sta     CIWP            ; all 2KB of I-RAM writable
                lda     #0x80
                sta     CBWE            ; BW-RAM writable - the stack is in it
                lda     #0x00
                sta     BWPA            ; no protected sub-area
                sta     CBMAP           ; the SA-1's window: BW-RAM block 0,
                                        ; which is what snes-SA1-c.scm assumes
                                        ; when it starts far RAM at $402000

                jmp     long:__program_start
