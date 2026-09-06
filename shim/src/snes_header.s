;;; SNES cartridge header for Calypsi-linked builds.
;;;
;;; The snes-HiROM.scm linker rules place these sections at $C0FFB0 and
;;; $C0FFC0 and scatter them to $FFB0/$FFC0. Calypsi's cstartup supplies the
;;; reset vector itself, so only the header lives here.

                .rtmodel version, "1"
                .rtmodel core, "*"

                .section snesheaderextended
                .public  snes_header_ext
snes_header_ext:
                .byte   "  "                    ; maker code
                .byte   "    "                  ; game code
                .byte   0,0,0,0,0,0,0           ; fixed / expansion
                .byte   0                       ; expansion RAM size
                .byte   0                       ; special version
                .byte   0                       ; cartridge sub-type

                .section snesheader
                .public  snes_header
snes_header:
                .byte   "FAMIDASH SNES M1.4   "  ; title, exactly 21 bytes
                ; HiROM, FastROM. The 65816 runs banks $80-$FF at 3.58MHz
                ; instead of 2.68 when MEMSEL says so, and ALL the code and the
                ; level data are at $C0-$C9 - so this is a third off every
                ; instruction fetch and every ROM read in the game. It is only
                ; half the switch: video_init writes MEMSEL too.
                .byte   0x31                    ; map mode: HiROM, FastROM
                .byte   0x00                    ; chipset: ROM only
                ; ROM size, as 1<<N KB. 0x0B = 2MB, which is what the 168-level
                ; set needs; the field is a declaration, not a limit, but an
                ; emulator or flash cart that trusts it will truncate the image.
                .byte   0x0B                    ; ROM size: 1<<11 KB = 2MB
                .byte   0x00                    ; RAM size: none
                .byte   0x01                    ; country: NTSC
                .byte   0x33                    ; developer id
                .byte   0x00                    ; version
                .word   0x0000                  ; checksum complement
                .word   0x0000                  ; checksum (patched post-build)
