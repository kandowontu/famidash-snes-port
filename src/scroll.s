; ---------------------------------------------------------------------------
; Famidash SNES port - M1 step 2: column-streaming horizontal scroll.
;
; Scrolls through the whole of Stereo Madness, streaming one tilemap column at
; a time into a 64x32 BG1 map and driving BG1HOFS. This is the SNES replacement
; for draw_screen / unrle_next_column: because VMAIN can auto-increment by 32
; words, a whole column is one DMA rather than a per-tile write loop.
;
; Build:  python tools/build_rom.py --target scroll
; ---------------------------------------------------------------------------

.p816
.smart -

.include "../out/level_info.inc"

; --- registers -------------------------------------------------------------
INIDISP     = $2100
BGMODE      = $2105
BG1SC       = $2107
BG12NBA     = $210B
BG1HOFS     = $210D
BG1VOFS     = $210E
VMAIN       = $2115
VMADDL      = $2116
VMDATAL     = $2118
CGADD       = $2121
CGDATA      = $2122
TM          = $212C
TS          = $212D
NMITIMEN    = $4200
MDMAEN      = $420B
MEMSEL      = $420D

DMAP0       = $4300
BBAD0       = $4301
A1T0L       = $4302
A1B0        = $4304
DAS0L       = $4305

; --- layout ----------------------------------------------------------------
VRAM_TILES   = $0000            ; word address, 256 tiles x 8 words
VRAM_BG1MAP  = $1000            ; word address, 64x32 map = 2048 words

FIRST_COL_BANK = $01            ; column data starts at LoROM bank $01
COL_BYTES      = TILE_ROWS * 2  ; 64 bytes per column record

SCROLL_SPEED = 4                ; pixels per frame
VBLANK_COL_BUDGET = 4           ; max column DMAs per vblank (4 x 64B = 256B,
                                ;  well inside the ~6KB NTSC vblank budget)
COLS_AHEAD   = 34               ; columns kept ahead of the left screen edge
                                ; (32 visible + 2 slack; the 64-wide map means
                                ;  the slot being overwritten is 30 columns
                                ;  off-screen)

; ---------------------------------------------------------------------------
.segment "ZEROPAGE"

scroll_x:   .res 2
cols_done:  .res 2
target_col: .res 2          ; stream_columns only
wtmp:       .res 2          ; write_column only - must NOT alias target_col
budget:     .res 2          ; columns left to write this vblank

; ---------------------------------------------------------------------------
.segment "CODE"

.proc reset
        sei
        clc
        xce                     ; native mode
        rep #$38
        .a16
        .i16
        ldx #$1FFF
        txs
        lda #$0000
        tcd                     ; direct page = $0000

        sep #$20
        .a8
        lda #$8F
        sta INIDISP             ; forced blank
        stz NMITIMEN
        stz MEMSEL

        jsr init_ppu
        jsr load_cgram
        jsr load_tiles

        rep #$20
        .a16
        stz scroll_x
        stz cols_done
        lda #COLS_AHEAD + 1     ; forced blank: prime the whole visible map
        sta budget
        jsr stream_columns

        sep #$20
        .a8
        ; BG1 tilemap base $1000 (word) in 1K-word units, screen size 01 = 64x32
        lda #((VRAM_BG1MAP >> 10) << 2) | $01
        sta BG1SC
        stz BG12NBA             ; BG1 character base $0000
        stz BGMODE              ; mode 0

        stz BG1HOFS
        stz BG1HOFS
        lda #$FF                ; VOFS = -1 puts map row 0 on screen line 0
        sta BG1VOFS
        sta BG1VOFS

        lda #$01
        sta TM
        stz TS

        lda #$0F
        sta INIDISP             ; blank off
        lda #$80
        sta NMITIMEN            ; enable NMI

forever:
        wai
        bra forever
.endproc

; ---------------------------------------------------------------------------
.proc init_ppu
        .a8
        .i16
        ldx #$2101
zero_loop:
        stz $0000,x
        inx
        cpx #$2134
        bne zero_loop
        lda #$80
        sta VMAIN
        rts
.endproc

; ---------------------------------------------------------------------------
.proc load_cgram
        .a8
        .i16
        stz CGADD
        stz DMAP0               ; 1 byte -> 1 register
        lda #<CGDATA
        sta BBAD0
        ldx #.loword(cgram_data)
        stx A1T0L
        lda #^cgram_data
        sta A1B0
        ldx #cgram_size
        stx DAS0L
        lda #$01
        sta MDMAEN
        rts
.endproc

; ---------------------------------------------------------------------------
.proc load_tiles
        .a8
        .i16
        ldx #VRAM_TILES
        stx VMADDL
        lda #$80
        sta VMAIN               ; +1 word
        lda #$01                ; 2 bytes -> 2 registers
        sta DMAP0
        lda #<VMDATAL
        sta BBAD0
        ldx #.loword(tile_data)
        stx A1T0L
        lda #^tile_data
        sta A1B0
        ldx #tile_size
        stx DAS0L
        lda #$01
        sta MDMAEN
        rts
.endproc

; ---------------------------------------------------------------------------
; Write every column that should now be resident. Entered with 16-bit A/X/Y.
; ---------------------------------------------------------------------------
.proc stream_columns
        .a16
        .i16
        lda scroll_x
        lsr
        lsr
        lsr                     ; leftmost visible column
        clc
        adc #COLS_AHEAD
        sta target_col
loop:
        lda budget
        beq done                ; out of vblank budget
        lda cols_done
        cmp #LEVEL_COLS
        bcs done                ; whole level streamed
        cmp target_col
        bcs done
        jsr write_column
        inc cols_done
        dec budget
        bra loop
done:
        rts
.endproc

; ---------------------------------------------------------------------------
; DMA one column record into its BG1 map slot.
;
; A 64x32 map is stored as two 32x32 screens back to back, so slots 32-63 live
; $400 words after slots 0-31.
; ---------------------------------------------------------------------------
.proc write_column
        .a16
        .i16
        ; --- destination ---
        lda cols_done
        and #$003F              ; slot = n & 63
        tax
        and #$0020              ; second screen?
        .repeat 5
        asl a
        .endrep                 ; -> $0000 or $0400 words
        sta wtmp
        txa
        and #$001F
        clc
        adc wtmp
        clc
        adc #VRAM_BG1MAP
        sta VMADDL              ; 16-bit store fills $2116/$2117

        sep #$20
        .a8
        lda #$81                ; +32 words, increment on high-byte write
        sta VMAIN
        lda #$01                ; 2 bytes -> 2 registers
        sta DMAP0
        lda #<VMDATAL
        sta BBAD0
        rep #$20
        .a16

        ; --- source: bank $01 + n/COLS_PER_BANK, offset $8000 + (n%512)*64 ---
        lda cols_done
        and #(COLS_PER_BANK - 1)
        .repeat 6
        asl a
        .endrep
        clc
        adc #$8000
        sta A1T0L

        lda #COL_BYTES
        sta DAS0L

        sep #$20
        .a8
        lda cols_done+1         ; high byte of n
        lsr a                   ; n >> 9  (COLS_PER_BANK = 512)
        clc
        adc #FIRST_COL_BANK
        sta A1B0

        lda #$01
        sta MDMAEN
        rep #$20
        .a16
        rts
.endproc

; ---------------------------------------------------------------------------
.proc nmi_handler
        rep #$30
        .a16
        .i16
        pha
        phx
        phy
        phd
        phb
        lda #$0000
        tcd

        ; --- scroll register, two 8-bit writes ---
        sep #$20
        .a8
        lda scroll_x
        sta BG1HOFS
        lda scroll_x+1
        sta BG1HOFS
        rep #$20
        .a16

        ; Cap DMA per vblank. At 4px/frame only one column is ever due; the cap
        ; is a hard stop so a logic error can never run DMA into active display.
        lda #VBLANK_COL_BUDGET
        sta budget
        jsr stream_columns

        ; --- advance, but stop once the level runs out ---
        lda scroll_x
        lsr
        lsr
        lsr
        clc
        adc #COLS_AHEAD
        cmp #LEVEL_COLS
        bcs no_advance
        lda scroll_x
        clc
        adc #SCROLL_SPEED
        sta scroll_x
no_advance:

        plb
        pld
        ply
        plx
        pla
        rti
.endproc

.proc irq_handler
        rti
.endproc

; ---------------------------------------------------------------------------
.segment "RODATA"

cgram_data:  .incbin "../out/bg1.cgram.bin"
cgram_end:
cgram_size   = cgram_end - cgram_data

tile_data:   .incbin "../out/bg1.tiles.bin"
tile_end:
tile_size    = tile_end - tile_data

; ---------------------------------------------------------------------------
; Level column stream, one segment per LoROM bank.
; ---------------------------------------------------------------------------
.segment "COLBANK0"
        .incbin "../out/level.cols.0.bin"
.segment "COLBANK1"
        .incbin "../out/level.cols.1.bin"
.segment "COLBANK2"
        .incbin "../out/level.cols.2.bin"
.segment "COLBANK3"
        .incbin "../out/level.cols.3.bin"

; ---------------------------------------------------------------------------
.segment "SNESHDR"

        .byte "  "
        .byte "    "
        .byte $00,$00,$00,$00,$00,$00,$00
        .byte $00
        .byte $00
        .byte $00
        .byte "FAMIDASH SNES SCROLL "   ; 21 bytes
        .byte $20                       ; LoROM, SlowROM
        .byte $00                       ; ROM only
        .byte $08                       ; 1<<8 KB = 256KB
        .byte $00
        .byte $01                       ; NTSC
        .byte $33
        .byte $00
        .word $0000
        .word $0000

; ---------------------------------------------------------------------------
.segment "VECTORS"

        .word $0000                     ; $FFE0 reserved
        .word $0000                     ; $FFE2 reserved
        .word $0000                     ; $FFE4 COP
        .word $0000                     ; $FFE6 BRK
        .word $0000                     ; $FFE8 ABORT
        .word nmi_handler               ; $FFEA NMI
        .word $0000                     ; $FFEC reserved
        .word irq_handler               ; $FFEE IRQ

        .word $0000                     ; $FFF0 reserved
        .word $0000                     ; $FFF2 reserved
        .word $0000                     ; $FFF4 COP
        .word $0000                     ; $FFF6 reserved
        .word $0000                     ; $FFF8 ABORT
        .word $0000                     ; $FFFA NMI
        .word reset                     ; $FFFC RESET
        .word irq_handler               ; $FFFE IRQ/BRK
