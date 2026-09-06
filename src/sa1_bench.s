;;; sa1_bench.s - how much faster is the SA-1, really?
;;;
;;; The clock says 10.74MHz against the S-CPU's 3.58, so 3x. That number is not
;;; the one the port gets, and the reason is the memory map: the SA-1 has NO
;;; access to $7E/$7F WRAM. The game's 34KB of state cannot stay where it is; it
;;; has to move to BW-RAM on the cartridge, which is slower than both WRAM and
;;; the SA-1's own 2KB of I-RAM. So the honest question is not "how fast is the
;;; SA-1" but "how fast is the SA-1 with its data where the data will have to
;;; be", and that is what this measures.
;;;
;;; Three runs of one identical, branch-free instruction stream:
;;;
;;;   A  S-CPU, arrays in WRAM $7E      - what ships today
;;;   B  SA-1,  arrays in I-RAM         - the 2KB best case
;;;   C  SA-1,  arrays in BW-RAM $40    - where 34KB of game state must live
;;;   D  SA-1,  arrays in BW-RAM, and the CODE copied into I-RAM first
;;;
;;; D exists because C came out far below the 3x the clock ratio promises, and
;;; there are two candidate reasons - slow data in BW-RAM, or slow instruction
;;; fetch from ROM. C against D separates them: same instructions, same
;;; operands, the only difference is where the opcodes are fetched from. The
;;; body is branch-relative and uses only absolute operands, so it is position
;;; independent and can simply be copied.
;;;
;;; They run one at a time, never overlapping, because both processors share the
;;; ROM bus and a concurrent run would measure contention instead of speed. The
;;; S-CPU finishes A, releases the SA-1, and stops.
;;;
;;; The stream is modelled on what Calypsi actually emits for sprite_collide -
;;; see docs/M2_24_WHY_2X.md: `long:` accesses, accumulator width churn, and
;;; register moves around a little real arithmetic. It is branch-free inside the
;;; unrolled body so all three runs execute exactly the same instructions, and
;;; the only variable is where the operands live.
;;;
;;; tools/verify_sa1_bench.lua reads the phase markers and reports elapsed
;;; frames and cycle counts for each run.

                .rtmodel version, "1"
                .rtmodel core, "65816"

CCNT            .equ 0x2200
CRV             .equ 0x2203
SIWP            .equ 0x2229     ; S-CPU I-RAM write permission
CIWP            .equ 0x222A     ; SA-1 I-RAM write permission
CBWE            .equ 0x2227     ; SA-1 BW-RAM write enable, bit 7
BWPA            .equ 0x2228     ; BW-RAM write-protected area size
CBMAP           .equ 0x2225     ; SA-1 BW-RAM bank for the $6000 window

;;; Phase markers. One byte PER RUN, not
;;; one counter stepped through the runs: the Lua samples at frame boundaries,
;;; and a single counter's "B finished" and "C started" are written by
;;; consecutive instructions, so the intervening value is never observable and
;;; run B measures as never having happened.
;;; Run A's marker lives in WRAM, not I-RAM, so the identical benchmark can also
;;; be built as a plain FastROM cartridge with no SA-1 in it - which is the only
;;; way to time run A against the clock the port actually ships on. I-RAM does
;;; not exist on that cartridge.
PH_A            .equ 0x7E0300
PH_B            .equ 0x3011
PH_C            .equ 0x3012
PH_D            .equ 0x3013

;;; Where run D's copy of the body is assembled to run. The SA-1's stack is
;;; moved down to $03FF to make room for it.
DCODE           .equ 0x000400

;;; 8 STEPs per outer iteration amortises the loop overhead to under 2%; the
;;; count is then chosen so each run lands around a second, which keeps the
;;; frame-granularity timing error near 1%.
OUTER           .equ 6000

;;; ---- the workload -------------------------------------------------------
;;; One step: two `long:` read-modify-writes, one width switch pair, two
;;; register moves, and the arithmetic between them. X stays inside 0..255 so
;;; every access lands in the 256-byte array it names.
STEP            .macro arr1, arr2
                lda     long:\arr1,x
                clc
                adc     #0x03
                sta     long:\arr1,x
                rep     #0x20
                txa
                clc
                adc     ##0x0001
                and     ##0x00FF
                tax
                sep     #0x20
                lda     long:\arr2,x
                eor     #0x40
                sta     long:\arr2,x
                .endm

;;; The loop around it. Written out per run rather than wrapped in another
;;; macro: the labels have to be unique, and three visible copies are easier to
;;; check against each other than one macro with a name-mangling scheme.
                .section sa1code, text, root
                .public bench_reset

;;; ---- the S-CPU: run A, then hand over --------------------------------------
bench_reset:
                sei
                clc
                xce
                rep     #0x30
                ldx     ##0x1FFF
                txs

                ;; Run the S-CPU body from bank $80. FastROM applies ONLY to
                ;; banks $80-$FF - MEMSEL does nothing for code in bank $00 -
                ;; and the shipping port's code lives at $C0, so run A has to be
                ;; up here or it is timed at 2.68MHz against a port that runs at
                ;; 3.58 and every SA-1 ratio comes out a quarter too high.
                jmp     long:scpu_body+0x800000

scpu_body:
                sep     #0x20
                lda     #0x8F
                sta     0x2100          ; screen off; nothing here draws
                lda     #0xFF
                sta     SIWP            ; I-RAM is write-protected at reset

                ;; FastROM. The shipping port runs the S-CPU at 3.58MHz, so run
                ;; A has to as well or the comparison flatters the SA-1 by the
                ;; ratio of the two S-CPU clocks. On the SA-1 map mode there is
                ;; no header bit for it - MEMSEL is the whole switch.
                lda     #0x01
                sta     0x420D          ; MEMSEL

                lda     #0x01
                sta     long:PH_A       ; run A is under way

                rep     #0x30
                ldx     ##0
                ldy     ##OUTER
                sep     #0x20
loopA:          STEP 0x7E0000, 0x7E0100
                STEP 0x7E0000, 0x7E0100
                STEP 0x7E0000, 0x7E0100
                STEP 0x7E0000, 0x7E0100
                STEP 0x7E0000, 0x7E0100
                STEP 0x7E0000, 0x7E0100
                STEP 0x7E0000, 0x7E0100
                STEP 0x7E0000, 0x7E0100
                dey
                beq     doneA
                brl     loopA
doneA:

                lda     #0x02
                sta     long:PH_A       ; run A finished

                ;; Hand over. Reset vector first, then release - in the other
                ;; order the SA-1 starts on whatever CRV happened to hold.
                rep     #0x20
                lda     ##bench_sa1
                sta     CRV
                sep     #0x20
                lda     #0x00
                sta     CCNT

                ;; Stop, rather than spin. A `bra *` loop keeps fetching from
                ;; the ROM the SA-1 is about to be measured against, and that
                ;; contention is exactly what this is trying not to measure.
                stp

;;; ---- the SA-1: run B in I-RAM, then run C in BW-RAM ------------------------
bench_sa1:
                sei
                clc
                xce
                rep     #0x30
                ldx     ##0x03FF        ; run D's code occupies $0400-$07FF
                txs

                sep     #0x20
                lda     #0xFF
                sta     CIWP            ; the SA-1's own I-RAM permission
                lda     #0x80
                sta     CBWE            ; bit 7: the SA-1 may write BW-RAM
                lda     #0x00
                sta     BWPA            ; no protected area within it
                sta     CBMAP

                lda     #0x01
                sta     PH_B            ; run B under way

                rep     #0x30
                ldx     ##0
                ldy     ##OUTER
                sep     #0x20
loopB:          STEP 0x003100, 0x003200
                STEP 0x003100, 0x003200
                STEP 0x003100, 0x003200
                STEP 0x003100, 0x003200
                STEP 0x003100, 0x003200
                STEP 0x003100, 0x003200
                STEP 0x003100, 0x003200
                STEP 0x003100, 0x003200
                dey
                beq     doneB
                brl     loopB
doneB:

                sep     #0x20
                lda     #0x02
                sta     PH_B            ; run B finished
                lda     #0x01
                sta     PH_C            ; run C under way

                rep     #0x30
                ldx     ##0
                ldy     ##OUTER
                sep     #0x20
loopC:          STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                dey
                beq     doneC
                brl     loopC
doneC:

                sep     #0x20
                lda     #0x02
                sta     PH_C            ; run C finished

                ;; ---- run D: the same body, fetched from I-RAM --------------
                rep     #0x30
                ldx     ##0
copyD:          lda     long:dcode_begin,x
                sta     long:DCODE,x
                inx
                inx
                cpx     ##dcode_end-dcode_begin+2
                bcc     copyD

                sep     #0x20
                lda     #0x01
                sta     PH_D            ; run D under way

                rep     #0x30
                ldx     ##0
                ldy     ##OUTER
                sep     #0x20
                jsl     DCODE

                sep     #0x20
                lda     #0x02
                sta     PH_D            ; run D finished - everything done
bench_end:      bra     bench_end

;;; ---- run D's body, assembled here and executed from I-RAM ------------------
;;; Byte-for-byte the same instructions as loopC. Every branch is relative and
;;; every operand absolute, so it runs correctly at either address; only the
;;; instruction fetches change.
dcode_begin:
loopD:          STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                STEP 0x400000, 0x400100
                dey
                beq     doneD
                brl     loopD
doneD:          rtl
dcode_end:

;;; The S-CPU's reset vector. `root` because the CPU reaches it through the
;;; vector table, which the linker cannot see.
                .section reset, root
                .word   bench_reset
