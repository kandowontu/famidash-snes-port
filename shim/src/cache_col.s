;;; Cache one decoded 60-byte metatile column for vertical row streaming.
;;;
;;; Calypsi's large-data-model pointer loop costs hundreds of instructions:
;;; every 16-bit copy reloads two far pointers, advances them in memory and
;;; spills the loop state. This fixed-size copy is the hot half of draw_screen
;;; on every tall level, so express the actual operation directly.
;;;
;;; Calling convention:
;;;   void shim_cache_mt_column(uint16_t metatile_column)
;;;   A = first argument, 16-bit A/X/Y; X and Y are caller-owned.
;;;
;;; X becomes (column & 31) * 60. Both symbols are long-address relocations, so
;;; the same object works when HiROM links them into WRAM and SA-1 links them
;;; into BW-RAM.

                .rtmodel version, "1"
                .rtmodel codeModel, "large"
                .rtmodel dataModel, "large"
                .rtmodel core, "65816"
                .rtmodel huge, "0"

                .extern mt_col
                .extern mt_cache

                .section farcode, text
                .public shim_cache_mt_column
shim_cache_mt_column:
                phx
                pha
                and     ##0x001F
                asl     a
                asl     a               ; column * 4
                sta     1,s
                asl     a
                asl     a
                asl     a
                asl     a               ; column * 64
                sec
                sbc     1,s              ; column * 60
                tax

copy_word       .macro offset
                lda     long:mt_col+\offset
                sta     long:mt_cache+\offset,x
                .endm

                copy_word 0
                copy_word 2
                copy_word 4
                copy_word 6
                copy_word 8
                copy_word 10
                copy_word 12
                copy_word 14
                copy_word 16
                copy_word 18
                copy_word 20
                copy_word 22
                copy_word 24
                copy_word 26
                copy_word 28
                copy_word 30
                copy_word 32
                copy_word 34
                copy_word 36
                copy_word 38
                copy_word 40
                copy_word 42
                copy_word 44
                copy_word 46
                copy_word 48
                copy_word 50
                copy_word 52
                copy_word 54
                copy_word 56
                copy_word 58

                pla
                plx
                rtl
