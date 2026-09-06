;;; Cartridge header for the SA-1 probe.
;;;
;;; Three fields decide whether an emulator or a flashcart puts an SA-1 in the
;;; cartridge at all, and all three have to agree:
;;;
;;;   map mode  $23   SA-1. Not $20 (LoROM) or $21 (HiROM), even though the
;;;                   address layout is LoROM-shaped.
;;;   chipset   $34   ROM + SA-1 + RAM. $35 adds a battery.
;;;   RAM size  $06   BW-RAM, as 1<<N KB - 64KB. This is the cartridge RAM
;;;                   the SA-1 uses INSTEAD of $7E/$7F WRAM, which it cannot
;;;                   see, so a declaration of 0 leaves it with nowhere to put
;;;                   the game's 34KB of state.
;;;
;;; The reset vector is the S-CPU's, as always. The SA-1's comes from CRV
;;; ($2203), written by the S-CPU before it releases reset - see sa1_probe.s.

                .rtmodel version, "1"
                .rtmodel core, "65816"

                .section snesheaderextended
                .public  sa1_header_ext
sa1_header_ext:
                .byte   "  "                    ; maker code
                .byte   "    "                  ; game code
                .byte   0,0,0,0,0,0,0           ; fixed / expansion
                .byte   0                       ; expansion RAM size
                .byte   0                       ; special version
                .byte   0                       ; cartridge sub-type

                .section snesheader
                .public  sa1_header
sa1_header:
                .byte   "FAMIDASH SA1 PROBE   "  ; title, exactly 21 bytes
                .byte   0x23                    ; map mode: SA-1
                .byte   0x34                    ; chipset: ROM + SA-1 + RAM
                .byte   0x05                    ; ROM size: 1<<5 KB = 32KB
                ;; 64KB: the full game needs 8KB for the $6000 window block
                ;; (stack and near data) plus 34KB of far data, and BW-RAM is
                ;; the ONLY place either can go. Declaring 32KB would mirror the
                ;; top half over the bottom and corrupt state silently.
                .byte   0x06                    ; RAM size: 1<<6 KB = 64KB BW-RAM
                .byte   0x01                    ; country: NTSC
                .byte   0x33                    ; developer id
                .byte   0x00                    ; version
                .word   0x0000                  ; checksum complement
                .word   0x0000                  ; checksum (patched post-build)
