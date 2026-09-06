;;; oam_spr - one NES 8x16 sprite into two SNES 8x8 OAM entries.
;;;
;;; WHY THIS IS ASSEMBLY, when the rest of the shim is C.
;;;
;;; This is the innermost loop of the whole port. A busy frame of Stereo Madness
;;; reaches it about twenty times, and the C version measured at 4.2 scanlines a
;;; call - 76 of draw_sprites' 127, on a frame that only has 262 to spend. That
;;; was the "extreme lag": every sprite-dense stretch of a level dropped the game
;;; to half speed.
;;;
;;; The cost was not the work, which is eight byte stores. It was the shape
;;; Calypsi has to generate for it: every 8-bit value handled in 16-bit registers
;;; with `sep`/`rep` either side, every operand fetched again from a stack slot,
;;; and the OAM index recomputed for each store. Nothing about that is fixable
;;; from C. Written directly it is about 90 cycles instead of about 950.
;;;
;;; CALLING CONVENTION (Calypsi 65816, --code-model large --data-model large).
;;; Taken from the compiler's own output for this function, not from a manual:
;;;
;;;   void oam_spr(uint8_t x, uint8_t y, uint8_t chrnum, uint8_t attr)
;;;
;;;   entry:  jsl, so 1,s..3,s is the return address
;;;           A holds the FIRST argument, 16-bit A and index registers
;;;           the rest are pushed by the caller as 16-bit words, right to left:
;;;             4,s = y   6,s = chrnum   8,s = attr
;;;   exit:   caller pops the three pushed words; A is the return value
;;;
;;; X and Y are saved and restored here rather than assumed scratch, and every
;;; access is `long:` so nothing depends on the data bank register. The direct
;;; page is not touched at all: `_Dp` is the compiler's scratch and is only
;;; live within an expression, but there is no reason to rely on that.

                .rtmodel version, "1"
                .rtmodel codeModel, "large"
                .rtmodel dataModel, "large"
                .rtmodel core, "65816"
                .rtmodel huge, "0"

                .extern oam_buf         ; the shadow OAM, shim_ppu.c
                .extern sprid           ; byte cursor into its low table
                .extern shim_deco_cached_phase

                .section farcode, text
                .public oam_spr
oam_spr:
                phy                     ; caller's Y
                phx                     ; caller's X
                pha                     ; slot A: 3,s = x, 4,s = snes attribute
                pha                     ; slot B: 1,s = top tile, 2,s = bottom
;;; Arguments have moved up by the 8 bytes just pushed:
;;;   ret 9,s..11,s   y 12,s   chrnum 14,s   attr 16,s
;;; oam_buf is 512 bytes of low table followed by 32 of high table. Two entries
;;; need eight bytes, so the last usable cursor is 512 - 8 = 504 = $1F8, and
;;; anything above that is dropped rather than wrapped - as the C version did.
                lda     long:sprid      ; LDX has no absolute-long mode
                tax
                cpx     ##0x01F9
                bcc     oam_spr_room
                ;; A relay, because the tile mapping below pushed oam_spr_done
                ;; past a branch's reach. It sits after an unconditional branch
                ;; so nothing can fall into it - docs/HANDOFF.md trap 73.
                jmp     .word0 oam_spr_done
oam_spr_room:

                sep     #0x20           ; 8-bit accumulator, index stays 16-bit

;;; ---- attribute --------------------------------------------------------
;;; NES: bits 0-1 palette, bit 5 behind-background, bit 6 flip X, bit 7 flip Y.
;;; SNES: bit 0 name bit 8, bits 1-3 palette, bits 4-5 priority, 6-7 the flips.
;;; Sprite palettes start at CGRAM 128, which is OBJ palette 0, so the NES
;;; palette number maps straight through. Priority 2 is the normal layer and
;;; "behind background" becomes priority 0 - one xor, no branch.
                lda     16,s            ; attr
                and     #0x03
                asl     a               ; palette -> bits 1-2
                sta     4,s
                lda     16,s
                eor     #0x20
                and     #0x20           ; priority
                ora     4,s
                sta     4,s
                lda     16,s
                and     #0xC0           ; flips pass straight through
                ora     4,s
                sta     4,s
;;; Bank-1 tiles have chrnum bit 7 set. The cached decoration phase keeps their
;;; low tile byte unchanged and selects the otherwise-unused OBJ name table by
;;; clearing SNES name bit 8. Bank-0/player tiles retain the normal name bit.
                lda     long:shim_deco_cached_phase
                beq     oam_spr_normal_name
                lda     14,s
                bmi     oam_spr_name_done
oam_spr_normal_name:
                lda     14,s            ; chrnum
                and     #0x01           ; pattern table -> OBJ name bit 8
                ora     4,s
                sta     4,s             ; the finished attribute byte
oam_spr_name_done:

;;; ---- the two tile numbers ---------------------------------------------
;;; The game runs the NES in 8x16 sprite mode, where bit 0 of the tile byte
;;; selects the pattern table and the rest is the tile PAIR - so the halves are
;;; (chrnum & $FE) and that + 1. A vertical flip swaps which one is on top.
;;; Both halves share the attribute byte, including its name bit: the pair
;;; number is even, so +1 cannot carry out of the low byte.
                lda     16,s
                and     #0x80
                beq     oam_spr_noflip
                lda     14,s
                and     #0xFE
                sta     2,s             ; flipped: n is the bottom half
                inc     a
                sta     1,s             ; and n+1 the top
                bra     oam_spr_tiles
oam_spr_noflip:
                lda     14,s
                and     #0xFE
                sta     1,s
                inc     a
                sta     2,s
oam_spr_tiles:

;;; ---- write both entries -----------------------------------------------
;;; X is the byte cursor into the low table. Long indexed addressing only takes
;;; X, which is why the cursor lives there and the operands live on the stack.
                lda     3,s             ; x, the same for both halves
                sta     long:oam_buf,x
                sta     long:oam_buf+4,x
                lda     12,s            ; y
                inc     a               ; NES OAM stores y-1: the PPU draws
                sta     long:oam_buf+1,x        ; sprites one line down
                clc
                adc     #8              ; the bottom half, eight lines lower
                sta     long:oam_buf+5,x
                lda     1,s
                sta     long:oam_buf+2,x
                lda     2,s
                sta     long:oam_buf+6,x
                lda     4,s
                sta     long:oam_buf+3,x
                sta     long:oam_buf+7,x

                rep     #0x20           ; 16-bit accumulator again
                txa
                clc
                adc     ##8
                sta     long:sprid

oam_spr_done:
                rep     #0x20           ; the full path never left 16-bit, but
                                        ; both paths must leave in the same mode
                pla                     ; slot B
                pla                     ; slot A
                plx
                ply
                rtl

;;; ---------------------------------------------------------------------------
;;; shim_meta_run - walk a metasprite and write its sprites into the shadow OAM.
;;;
;;; This is the hot loop of the port. Measured with tools/profile_sprite_split.lua,
;;; the shim's half of drawing sprites (this plus oam_spr) was 1505 instructions a
;;; frame against 737 for draw_sprites' own per-slot logic - two thirds of the
;;; cost was here, not in the game code.
;;;
;;; Three things make it fast, and all three are about doing work ONCE PER
;;; METASPRITE instead of once per sprite:
;;;
;;; 1. THE POSITION IS A SINGLE ADD. Sign-extending an 8-bit offset and adding it
;;;    to the origin is, written out, a mask, a compare, a branch and an add per
;;;    axis. But sign extension of a zero-extended byte v is (v ^ $80) - $80, so
;;;    px = x + sext(dx) folds to (dx ^ $80) + (x - $80): xor the byte, add a bias
;;;    computed once. The flipped forms fold the same way -
;;;      H:  px = x - dx - 8  =  (x + $78) - (dx ^ $80)
;;;      V:  py = y - dy      =  (y + $80) - (dy ^ $80)
;;;    - so a flip only changes which bias and whether it adds or subtracts.
;;;
;;; 2. THE OAM WRITE IS INLINE. It used to `jsl oam_spr`, which under this ABI
;;;    means pushing three stack words and popping them again per sprite. oam_spr
;;;    stays for the game's own callers (trail_loop, put_number, the mouse
;;;    cursor); this is the same eight stores without the call.
;;;
;;; 3. THE FLIP IS HOISTED. It was re-read from a global and tested twice per
;;;    sprite. It is constant for the whole metasprite, so it is now two DP
;;;    values: mflip16 (flip << 8, so BIT in 16-bit mode puts H in V and V in N)
;;;    and mflipb (flip & $C0, to xor into each attribute byte).
;;;
;;; ARGUMENTS COME THROUGH GLOBALS, not the calling convention. This takes a
;;; POINTER, and Calypsi passes pointer arguments in its direct-page
;;; pseudo-registers (`_Dp`) - compiler scratch, not an interface to build on.
;;; The C wrappers in shim_ppu.c fill these in, once per metasprite.
;;;
;;;   shim_meta_ptr    the metasprite data (24-bit)
;;;   shim_meta_x/y    where to put it
;;;   shim_meta_disco  cycle the palette per frame
;;;   shim_meta_flip   bits 6/7: mirror the whole metasprite
;;;
;;; FORMAT. (dx, dy, tile, attr) quadruplets terminated by dx = $80. Offsets are
;;; signed. A sprite whose position leaves the 256-pixel space is dropped rather
;;; than wrapped, which is what the original's carry tests do.
;;;
;;; A FLIP MIRRORS THE OFFSETS, not just the attribute bits. Flipping only the
;;; attribute mirrors each 8x16 sprite about its own centre and leaves it where
;;; it was, so a 16x16 metasprite comes out as four quadrants each turned inside
;;; out - which is exactly what the rotating cube looked like on screen. The -8
;;; in the H form is the sprite's own width; there is deliberately no -16 on the
;;; vertical, because 8x16 mode already accounts for the height.
;;;
;;; The walk is bounded at 64 sprites, NES OAM's capacity. Nothing in the game's
;;; own data needs the bound, but an unbounded walk over a bad pointer emits
;;; sprites until it happens to read an $80 byte - one did, and it cost 7161
;;; sprites and fifty video frames in a single call.
;;;
;;; The loop-backs are absolute jumps, not relative branches: the body outgrew
;;; the +/-127 a branch reaches. `jmp .word0 label` is the form that works - this
;;; assembler has no `jml`, and `jmp long:` assembles a 16-bit operand the linker
;;; then rejects. Earlier this used chained relay branches, and putting one in a
;;; fall-through path sent every sprite back to the top before it was drawn, with
;;; OAM coming out empty and no error anywhere.

                .extern shim_meta_ptr
                .extern shim_meta_x
                .extern shim_meta_y
                .extern shim_meta_disco
                .extern shim_meta_flip
                .extern drawing_frame

;;; Direct page, because [dp],y is the only addressing mode that reads through a
;;; 24-bit pointer, and metasprite data lives in ROM banks $C0-$C2. `ztiny` is
;;; the section src/snes-HiROM.scm already routes into the DirectPage memory, so
;;; this needs no linker change.
                .section ztiny, bss
mp:             .space  4               ; the walking pointer
mdx:            .space  2               ; the quadruplet, xored ready for the bias
mdy:            .space  2
mbx:            .space  2               ; x bias, sign already chosen by the flip
mby:            .space  2               ; y bias
mflip16:        .space  2               ; flip << 8, for BIT in 16-bit mode
mflipb:         .space  2               ; flip & $C0, to xor into the attribute
mpx:            .space  2               ; this sprite's screen position
mpy:            .space  2
mtile:          .space  2
mattr:          .space  2               ; the NES attribute, flip applied
mattr2:         .space  2               ; the SNES attribute being built
mtmp:           .space  2
mcount:         .space  2               ; sprites left before the bound
mdeco:          .space  2               ; resident decoration cache selected

                .section farcode, text
                .public shim_meta_run
shim_meta_run:
                phx
                phy
                rep     #0x30           ; 16-bit A and index unless a byte read
                lda     long:shim_meta_ptr
                sta     dp:.tiny mp
                lda     long:shim_meta_ptr+2
                sta     dp:.tiny (mp+2)
                lda     long:shim_deco_cached_phase
                and     ##0x00FF
                sta     dp:.tiny mdeco
;;; If OAM is already full there is nothing this call can achieve - every
;;; sprite would be computed and then dropped at the write. Bail before the
;;; per-sprite work rather than after it: this is exactly the case a
;;; sprite-dense frame runs into, and it is where the time was going.
                lda     long:sprid
                cmp     ##0x01F9
                bcc     meta_room
                ply                     ; X and Y are already pushed - restore
                plx                     ; them, or the caller returns to junk
                rtl
meta_room:
                lda     ##64
                sta     dp:.tiny mcount
                stz     dp:.tiny mdx            ; only the low byte is written in
                stz     dp:.tiny mdy            ; the loop, so zero the high ones
                stz     dp:.tiny mtile          ; once and let the 16-bit reads
                stz     dp:.tiny mattr          ; zero-extend for free

;;; ---- per-metasprite: the flip, and the two position biases --------------
                lda     long:shim_meta_flip
                and     ##0x00C0
                sta     dp:.tiny mflipb
                xba                     ; << 8 so BIT puts H in V and V in N
                and     ##0xFF00
                sta     dp:.tiny mflip16

                bit     dp:.tiny mflip16
                bvc     meta_bx_plain
                lda     long:shim_meta_x        ; H: px = (x + $78) - (dx ^ $80)
                clc
                adc     ##0x0078
                bra     meta_bx_done
meta_bx_plain:  lda     long:shim_meta_x        ;    px = (dx ^ $80) + (x - $80)
                sec
                sbc     ##0x0080
meta_bx_done:   sta     dp:.tiny mbx

                bit     dp:.tiny mflip16
                bpl     meta_by_plain
                lda     long:shim_meta_y        ; V: py = (y + $80) - (dy ^ $80)
                clc
                adc     ##0x0080
                bra     meta_by_done
meta_by_plain:  lda     long:shim_meta_y        ;    py = (dy ^ $80) + (y - $80)
                sec
                sbc     ##0x0080
meta_by_done:   sta     dp:.tiny mby

                bra     meta_loop

;;; The exit sits before the loop so its branches reach it.
meta_done:      rep     #0x30
                ply
                plx
                rtl
meta_loop:      dec     dp:.tiny mcount
                bmi     meta_done               ; the 64-sprite bound

;;; ---- read the quadruplet, and ADVANCE FIRST -----------------------------
;;; The pointer moves on before the off-screen checks below, because those
;;; branch back to the top of the loop: advancing afterwards means a dropped
;;; sprite re-reads the same quadruplet forever. The four reads cost the same
;;; either way - a dropped sprite is rare.
                sep     #0x20
                ldy     ##0
                lda     [.tiny mp],y            ; dx
                cmp     #0x80
                beq     meta_done               ; end of stream
                eor     #0x80                   ; ready for the bias add
                sta     dp:.tiny mdx
                ldy     ##1
                lda     [.tiny mp],y            ; dy
                eor     #0x80
                sta     dp:.tiny mdy
                ldy     ##2
                lda     [.tiny mp],y            ; chrnum
                sta     dp:.tiny mtile
                ldy     ##3
                lda     [.tiny mp],y            ; attr
                eor     dp:.tiny mflipb         ; the metasprite's own flip
                sta     dp:.tiny mattr
                rep     #0x20
                lda     dp:.tiny mp
                clc
                adc     ##4
                sta     dp:.tiny mp

;;; ---- x ------------------------------------------------------------------
                lda     dp:.tiny mdx
                bit     dp:.tiny mflip16
                bvc     meta_x_plain
                sta     dp:.tiny mtmp
                lda     dp:.tiny mbx
                sec
                sbc     dp:.tiny mtmp
                bra     meta_x_done
meta_x_plain:   clc
                adc     dp:.tiny mbx
meta_x_done:    sta     dp:.tiny mpx
                cmp     ##0x0100
                bcc     meta_x_ok               ; off the edge - drop, not wrap
                jmp     .word0 meta_loop
meta_x_ok:

;;; ---- y ------------------------------------------------------------------
                lda     dp:.tiny mdy
                bit     dp:.tiny mflip16
                bpl     meta_y_plain
                sta     dp:.tiny mtmp
                lda     dp:.tiny mby
                sec
                sbc     dp:.tiny mtmp
                bra     meta_y_done
meta_y_plain:   clc
                adc     dp:.tiny mby
meta_y_done:    sta     dp:.tiny mpy
                cmp     ##0x0100
                bcc     meta_y_ok
                jmp     .word0 meta_loop
meta_y_ok:

                sep     #0x20
;;; ---- the attribute ------------------------------------------------------
;;; NES: bits 0-1 palette, bit 5 behind-background, bit 6 flip X, bit 7 flip Y.
;;; SNES: bit 0 name bit 8, bits 1-3 palette, bits 4-5 priority, 6-7 the flips.
;;; Sprite palettes start at CGRAM 128, which is OBJ palette 0, so the NES
;;; palette number maps straight through, and "behind background" becomes
;;; priority 0 with one xor. The metasprite's own flip is xored in first: it
;;; only touches bits 6-7, which pass through the conversion unchanged.
                lda     dp:.tiny mattr
                and     #0x03
                asl     a                       ; palette -> bits 1-2
                sta     dp:.tiny mattr2
                lda     dp:.tiny mattr
                eor     #0x20
                and     #0x20                   ; priority
                ora     dp:.tiny mattr2
                sta     dp:.tiny mattr2
                lda     dp:.tiny mattr
                and     #0xC0                   ; the flips
                ora     dp:.tiny mattr2
                sta     dp:.tiny mattr2

;;; The disco effect replaces the palette bits with the frame counter.
                lda     long:shim_meta_disco
                beq     meta_nodisco
                lda     dp:.tiny mattr2
                and     #0xF9                   ; clear palette bits 1-2
                sta     dp:.tiny mattr2
                lda     long:drawing_frame
                and     #0x03
                asl     a
                ora     dp:.tiny mattr2
                sta     dp:.tiny mattr2
meta_nodisco:

;;; ---- the tile pair ------------------------------------------------------
;;; The game runs the NES in 8x16 sprite mode, where bit 0 of the tile byte
;;; selects the pattern table and the rest is the tile PAIR - so the halves are
;;; (chrnum & $FE) and that + 1, and pattern table 1 is OBJ tiles 256+, which is
;;; attribute bit 0. A vertical flip swaps which half is on top. Both halves
;;; share the attribute, including that name bit: the pair number is even, so +1
;;; cannot carry out of the low byte.
;;; The full sibling decoration bank is resident in OBJ tiles 128..255. Its
;;; chrnum low byte is identical; bank-1 sprites (bit 7 set) select it by
;;; leaving SNES name bit 8 clear. Player/bank-0 sprites keep the normal bit.
                lda     dp:.tiny mdeco
                beq     meta_normal_name
                lda     dp:.tiny mtile
                bmi     meta_name_done
meta_normal_name:
                lda     dp:.tiny mtile
                and     #0x01                   ; pattern table -> name bit 8
                ora     dp:.tiny mattr2
                sta     dp:.tiny mattr2
meta_name_done:

                lda     dp:.tiny mattr
                and     #0x80
                beq     meta_noflip
                lda     dp:.tiny mtile
                and     #0xFE
                sta     dp:.tiny mtmp           ; flipped: n is the bottom half
                inc     a
                sta     dp:.tiny mtile          ; and n+1 the top
                bra     meta_tiles
meta_noflip:    lda     dp:.tiny mtile
                and     #0xFE
                sta     dp:.tiny mtile
                inc     a
                sta     dp:.tiny mtmp
meta_tiles:

;;; ---- write the two OAM entries -----------------------------------------
;;; Two SNES 8x8 sprites stacked, because the SNES has no 8x16 OBJ size. X is
;;; the byte cursor into the low table; long indexed addressing only takes X,
;;; which is why the cursor lives there.
;;; oam_buf is 512 bytes of low table plus 32 of high table, so the last usable
;;; cursor is 512 - 8 = $1F8; past that, drop rather than wrap.
                rep     #0x20
                lda     long:sprid
                tax
                cpx     ##0x01F9
                bcs     meta_advance            ; out of sprites

                sep     #0x20
                lda     dp:.tiny mpx
                sta     long:oam_buf,x
                sta     long:oam_buf+4,x
                lda     dp:.tiny mpy
                inc     a                       ; NES OAM stores y-1: the PPU
                sta     long:oam_buf+1,x        ; draws sprites one line down
                clc
                adc     #8                      ; the bottom half
                sta     long:oam_buf+5,x
                lda     dp:.tiny mtile
                sta     long:oam_buf+2,x
                lda     dp:.tiny mtmp
                sta     long:oam_buf+6,x
                lda     dp:.tiny mattr2
                sta     long:oam_buf+3,x
                sta     long:oam_buf+7,x
                rep     #0x20
                txa
                clc
                adc     ##8
                sta     long:sprid

meta_advance:   jmp     .word0 meta_loop
