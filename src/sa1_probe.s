;;; sa1_probe.s - does the SA-1 start, and can both CPUs see the same memory?
;;;
;;; Everything about moving this port onto the SA-1 depends on three things that
;;; have to be established before anything else is worth writing:
;;;
;;;   1. the cartridge header and memory map are right, so the ROM boots at all;
;;;   2. the S-CPU can release the SA-1 from reset and it starts executing where
;;;      it was told to;
;;;   3. the two CPUs can pass data through I-RAM, which is the only memory both
;;;      can touch cheaply - the SA-1 CANNOT see $7E/$7F WRAM at all, and that
;;;      single fact is what makes this a port rather than a recompile.
;;;
;;; So: the S-CPU sets the SA-1's reset vector, releases it, and then does
;;; nothing. The SA-1 writes a magic number into I-RAM and increments a counter
;;; forever. tools/verify_sa1.lua reads both back. If the counter moves, all
;;; three hold.
;;;
;;; SA-1 register map, the parts used here:
;;;   $2200 CCNT  S-CPU -> SA-1 control. bit 5 RESB holds the SA-1 in reset and
;;;               is SET at power-on; bit 6 RDYB stalls it; bit 4 NMI, bit 7 IRQ.
;;;   $2203 CRV   the SA-1's 16-bit reset vector. Program bank starts at 0.
;;;   $2220-$2223 the Super MMC bank registers; after reset they already map ROM
;;;               banks 0-3, which is all this needs.
;;;
;;; I-RAM is 2KB, at $3000-$37FF for the S-CPU and $0000-$07FF for the SA-1.
;;; $3000 is written here because both see it there.

                .rtmodel version, "1"
                .rtmodel core, "65816"

CCNT            .equ 0x2200
CRV             .equ 0x2203
SCNT            .equ 0x2209
SIWP            .equ 0x2229     ; S-CPU I-RAM write permission, 1 bit per 256B
CIWP            .equ 0x222A     ; SA-1 I-RAM write permission, same shape
IRAM            .equ 0x3000

                .section sa1code, text, root
                .public sa1_reset

;;; ---- the S-CPU -----------------------------------------------------------
sa1_reset:
                sei
                clc
                xce                     ; native mode
                rep     #0x30           ; 16-bit A and index
                ldx     ##0x1FFF
                txs

                ;; Blank the screen. Nothing here draws, and a PPU left in its
                ;; power-on state makes a failed boot look like a hung one.
                sep     #0x20
                lda     #0x8F
                sta     0x2100

                ;; I-RAM is write-protected at reset - SIWP and CIWP both come
                ;; up as 0, which permits no writes at all, from EITHER CPU. A
                ;; store to I-RAM before this is silently dropped: no fault, no
                ;; side effect, the value simply does not land. Each bit opens
                ;; one 256-byte block, so $FF opens all 2KB.
                lda     #0xFF
                sta     SIWP

                ;; The SA-1's reset vector, THEN release it. In the other order
                ;; it starts executing whatever CRV happened to contain.
                rep     #0x20
                lda     ##sa1_main
                sta     CRV
                sep     #0x20
                lda     #0x00
                sta     CCNT            ; clear RESB: the SA-1 runs

                ;; A counter of our own, so the test can tell "the S-CPU hung"
                ;; from "the SA-1 never started".
scpu_loop:      inc     IRAM+4
                bra     scpu_loop

;;; ---- the SA-1 ------------------------------------------------------------
;;; Reached because CRV points here. The SA-1 starts with program bank 0, and
;;; bank $00:$8000-$FFFF is ROM, so this label resolves for both processors.
sa1_main:
                sei
                clc
                xce
                rep     #0x30
                ldx     ##0x07FF        ; the SA-1's stack lives in I-RAM
                txs

                sep     #0x20
                lda     #0xFF
                sta     CIWP            ; the SA-1's own I-RAM write permission

                lda     #0x5A
                sta     IRAM+0
                lda     #0xA1
                sta     IRAM+1          ; "SA1", so a zeroed I-RAM cannot pass

sa1_loop:       inc     IRAM+2
                bra     sa1_loop

;;; The S-CPU's reset vector. The main port gets this from Calypsi's cstartup;
;;; this probe has no C runtime, so it supplies its own.
;;; `root` because nothing references it - the CPU jumps here through the vector
;;; table, which the linker cannot see, so without it the section is discarded
;;; and the ROM boots to whatever $FFFC happened to hold.
                .section reset, root
                .word   sa1_reset
