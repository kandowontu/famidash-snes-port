; ---------------------------------------------------------------------------
; Famidash SNES port - M1 step 1: display-only ROM.
;
; DMAs the M0-converted assets into VRAM/CGRAM and shows one static screen of
; Stereo Madness in BG mode 0. No input, no logic - this exists to prove the
; converted binaries are correct on real SNES hardware, turning M0's software
; render into an actual SNES frame.
;
; Build:  make   (see Makefile)
; ---------------------------------------------------------------------------

.p816
.smart -

; --- PPU / CPU registers ---------------------------------------------------
INIDISP     = $2100      ; screen brightness + forced blank
OBSEL       = $2101      ; object size / base
BGMODE      = $2105      ; BG mode + tile size
BG1SC       = $2107      ; BG1 tilemap base + screen size
BG12NBA     = $210B      ; BG1/BG2 character base
BG1HOFS     = $210D      ; BG1 horizontal scroll (write twice)
BG1VOFS     = $210E      ; BG1 vertical scroll   (write twice)
VMAIN       = $2115      ; VRAM address increment mode
VMADDL      = $2116      ; VRAM word address
VMDATAL     = $2118      ; VRAM data port
CGADD       = $2121      ; CGRAM word address
CGDATA      = $2122      ; CGRAM data port
TM          = $212C      ; main screen layer enable
TS          = $212D      ; sub screen layer enable
NMITIMEN    = $4200      ; NMI / IRQ / auto-joypad enable
MDMAEN      = $420B      ; general DMA enable
MEMSEL      = $420D      ; FastROM select

DMAP0       = $4300      ; DMA0 control
BBAD0       = $4301      ; DMA0 destination register
A1T0L       = $4302      ; DMA0 source address
A1B0        = $4304      ; DMA0 source bank
DAS0L       = $4305      ; DMA0 transfer size

; --- VRAM layout (word addresses) ------------------------------------------
; Tiles occupy $0000-$07FF (256 tiles x 8 words), tilemap sits at $1000.
VRAM_TILES  = $0000
VRAM_BG1MAP = $1000

; ---------------------------------------------------------------------------
.segment "CODE"

.proc reset
        sei
        clc
        xce                     ; -> native 65816 mode
        rep #$38                ; 16-bit A/X/Y, decimal off
        .a16
        .i16
        ldx #$1FFF
        txs                     ; stack at $1FFF
        lda #$0000
        tcd                     ; direct page = $0000

        sep #$20                ; 8-bit A
        .a8

        lda #$8F
        sta INIDISP             ; forced blank while we set up
        stz NMITIMEN
        stz MEMSEL              ; SlowROM - keeps timing simple

        jsr init_ppu
        jsr load_cgram
        jsr load_tiles
        jsr load_tilemap

        ; BG1: tilemap base $1000 (word) in 1K-word units -> $1000>>10 = 4,
        ; shifted left 2; screen size 00 = 32x32.
        lda #(($1000 >> 10) << 2)
        sta BG1SC
        ; BG1 character base $0000 in 4K-word units -> 0.
        stz BG12NBA

        stz BGMODE               ; mode 0: four 2bpp layers, 8x8 tiles

        ; Scroll to origin. Both registers are write-twice.
        stz BG1HOFS
        stz BG1HOFS
        lda #$FF                 ; -1: SNES BG scrolls down one line by default
        sta BG1VOFS
        lda #$FF
        sta BG1VOFS

        lda #$01
        sta TM                   ; main screen: BG1 only
        stz TS

        lda #$0F
        sta INIDISP              ; blank off, full brightness

forever:
        wai
        bra forever
.endproc

; ---------------------------------------------------------------------------
; Put the PPU into a known state. Mode 0 with a single BG still needs the
; other layers explicitly disabled or their power-on garbage can show.
; ---------------------------------------------------------------------------
.proc init_ppu
        .a8
        .i16
        ; Zero $2101-$2133 so no layer inherits power-on garbage. Registers
        ; that matter (BGMODE, BG1SC, BG12NBA, TM, VMAIN) are set afterwards.
        ldx #$2101
zero_loop:
        stz $0000,x
        inx
        cpx #$2134
        bne zero_loop

        lda #$80
        sta VMAIN                ; increment by 1 word after high-byte write
        rts
.endproc

; ---------------------------------------------------------------------------
; CGRAM <- 32 bytes (16 colours: 4 palettes x 4, Mode 0 BG1 block)
; ---------------------------------------------------------------------------
.proc load_cgram
        .a8
        .i16
        stz CGADD
        lda #$00                 ; 1 byte -> 1 register (CGDATA)
        sta DMAP0
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
; VRAM <- 4096 bytes of SNES 2bpp tile data
; ---------------------------------------------------------------------------
.proc load_tiles
        .a8
        .i16
        ldx #VRAM_TILES
        stx VMADDL
        lda #$01                 ; 2 bytes -> 2 registers ($2118/$2119)
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
; VRAM <- 2048 bytes of BG1 tilemap (32x32 16-bit entries)
; ---------------------------------------------------------------------------
.proc load_tilemap
        .a8
        .i16
        ldx #VRAM_BG1MAP
        stx VMADDL
        lda #$01
        sta DMAP0
        lda #<VMDATAL
        sta BBAD0
        ldx #.loword(map_data)
        stx A1T0L
        lda #^map_data
        sta A1B0
        ldx #map_size
        stx DAS0L
        lda #$01
        sta MDMAEN
        rts
.endproc

; ---------------------------------------------------------------------------
.proc nmi_handler
        rti
.endproc

.proc irq_handler
        rti
.endproc

; ---------------------------------------------------------------------------
; Converted assets, straight from tools/snes_m0.py
; ---------------------------------------------------------------------------
.segment "RODATA"

cgram_data:  .incbin "../out/bg1.cgram.bin"
cgram_end:
cgram_size   = cgram_end - cgram_data

tile_data:   .incbin "../out/bg1.tiles.bin"
tile_end:
tile_size    = tile_end - tile_data

map_data:    .incbin "../out/bg1.tilemap.bin"
map_end:
map_size     = map_end - map_data

; ---------------------------------------------------------------------------
; Cartridge header ($FFB0-$FFDF)
; ---------------------------------------------------------------------------
.segment "SNESHDR"

        .byte "  "                      ; $FFB0 maker code
        .byte "    "                    ; $FFB2 game code
        .byte $00,$00,$00,$00,$00,$00,$00   ; $FFB6 fixed / expansion
        .byte $00                       ; $FFBD expansion RAM size
        .byte $00                       ; $FFBE special version
        .byte $00                       ; $FFBF cartridge sub-type

        ; $FFC0: title, exactly 21 bytes, space padded
        .byte "FAMIDASH SNES M1     "
        .byte $20                       ; $FFD5 map mode: LoROM, SlowROM
        .byte $00                       ; $FFD6 chipset: ROM only
        .byte $05                       ; $FFD7 ROM size: 1<<5 KB = 32KB
        .byte $00                       ; $FFD8 RAM size: none
        .byte $01                       ; $FFD9 country: NTSC
        .byte $33                       ; $FFDA developer id
        .byte $00                       ; $FFDB version
        .word $0000                     ; $FFDC checksum complement
        .word $0000                     ; $FFDE checksum (patched post-build)

; ---------------------------------------------------------------------------
; Vectors ($FFE0-$FFFF)
; ---------------------------------------------------------------------------
.segment "VECTORS"

        ; Native mode
        .word $0000                     ; $FFE0 reserved
        .word $0000                     ; $FFE2 reserved
        .word $0000                     ; $FFE4 COP
        .word $0000                     ; $FFE6 BRK
        .word $0000                     ; $FFE8 ABORT
        .word nmi_handler               ; $FFEA NMI
        .word $0000                     ; $FFEC reserved
        .word irq_handler               ; $FFEE IRQ

        ; Emulation mode
        .word $0000                     ; $FFF0 reserved
        .word $0000                     ; $FFF2 reserved
        .word $0000                     ; $FFF4 COP
        .word $0000                     ; $FFF6 reserved
        .word $0000                     ; $FFF8 ABORT
        .word $0000                     ; $FFFA NMI
        .word reset                     ; $FFFC RESET (entry point)
        .word irq_handler               ; $FFFE IRQ/BRK
