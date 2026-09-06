;; The full game's linker rules for an SA-1 cartridge.
;;
;; This is src/snes-HiROM.scm with the RAM re-homed and the boot block moved,
;; and deliberately nothing else: M2.25 established by probing the chip that
;; `$C0-$DF` is a linear 2MB HiROM window at the Super MMC's reset values.
;; The S-CPU boot also maps ROM megabytes 2 and 3 into `$E0-$FF`, because the
;; complete level set plus original music is now larger than 2MB.  All banks
;; remain linearly addressed and there is no run-time bank switching.
;; tools/gen_linkcfg.py --sa1 appends the generated data banks to this head, the
;; same ones it appends to the HiROM head.
;;
;; TWO THINGS MOVE.
;;
;; 1. THE RAM. The SA-1 cannot see $7E/$7F WRAM at all, so all ~38KB of it is
;;    re-homed onto the cartridge:
;;
;;      direct page  -> I-RAM $0000-$00FF. Direct page must be in bank 0, and
;;                      I-RAM is both the fastest memory there and the only one
;;                      that exists at that address.
;;      the mailbox  -> I-RAM $0100-$07FF. The shadow buffers the S-CPU has to
;;                      reach - OAM, palette, the VRAM queues. I-RAM is the only
;;                      memory BOTH processors address cheaply, which is what
;;                      makes it the mailbox and why no bulk data goes here.
;;      stack, near  -> BW-RAM through its $6000-$7FFF window. `near` addressing
;;                      and the stack both require bank 0; the window is the
;;                      only bank-0 memory big enough. The HiROM build fits this
;;                      in 4KB of an 8KB LoRAM, so 8KB is the same headroom.
;;      far, huge    -> BW-RAM linear at $40:2000 up. The HiROM build uses ~34KB
;;                      of a 64KB HiRAM; 56KB here is the same headroom.
;;
;;    The window and the linear view are the SAME physical BW-RAM. With CBMAP=0
;;    the window shows BW-RAM $0000-$1FFF, so the linear region starts at $2000 -
;;    otherwise `near` and `far` data would silently alias, which is a fault that
;;    would look like random corruption rather than like a mapping error.
;;
;; 2. THE BOOT BLOCK. An SA-1 cartridge is LoROM-shaped in banks $00-$3F: bank
;;    $00:$8000-$FFFF is ROM offset $0000-$7FFF, so the header lands at offset
;;    $7FC0 and the reset vector at $7FFC, where the HiROM build puts them at
;;    $FFC0/$FFFC. Since offset $0000-$7FFF is also $C0:0000-$7FFF, the scatter
;;    targets below just move from the top half of bank $C0 to the bottom half,
;;    and the same bytes are then reachable through both views - which is what
;;    lets the SA-1, whose program bank starts at 0, reach code assembled for
;;    $C0.
(define memories
        '((memory DirectPage
                (address (#x0 . #xff))
                (type RAM)
                (section registers ztiny tiny))

        ;; The S-CPU <-> SA-1 mailbox. Hand-placed: the S-CPU's vblank handler
        ;; and the Lua verifiers address it numerically, so it has to sit still
        ;; across builds in a way an allocated address would not.  Nothing is
        ;; linker-allocated here today, but reserve through $06FF so future
        ;; mailbox buffers cannot collide with the sequencer direct page.
        (memory IRamShared
                (address (#x100 . #x6ff))
                (type RAM)
                (section iram))

        ;; Original FamiStudio engine state.  The SA-1 runs the 6502-compatible
        ;; sequencer with D=$0700; the S-CPU sees these same I-RAM bytes through
        ;; its $3700 mirror and forwards the output image to the SPC700.
        (memory FamiAudioRAM
                (address (#x700 . #x7ff))
                (type RAM)
                (section fsaudioram))

        (memory NearRAM
                (address (#x6000 . #x7fff))
                (type RAM)
                (qualifier near)
                (section stack cstack data znear near))

        (memory FarRAM
                (address (#x402000 . #x40ffff))
                (type RAM)
                (qualifier far)
                (section heap zfar far huge))

        ;; Bank-0-addressed code, stored in the first half of $C0. sa1code is
        ;; the S-CPU's boot and the SA-1's entry stub (src/sa1_boot.s): both have
        ;; to be reachable at $00:xxxx, the boot because that is where the reset
        ;; vector points and the stub because CRV is a 16-bit vector with the
        ;; program bank starting at 0.
        (memory LoROM
                (address (#x8000 . #xffaf))
                (type ROM)
                (qualifier near)
                (scatter-to LoROM-store)
                (section sa1code code compactcode cdata cnear switch itiny idata inear data_init_table))

        (memory HeaderExtended
                (address (#xffb0 . #xffbf))
                (type ROM)
                (qualifier near)
                (section snesheaderextended)
                (scatter-to HeaderExt-store))

        (memory HeaderBasic
                (address (#xffc0 . #xffdf))
                (type ROM)
                (qualifier near)
                (section snesheader)
                (scatter-to Header-store))

        (memory Vector
                (address (#xffe0 . #xffff))
                (type ROM)
                (qualifier near)
                (scatter-to Vector-store)
                (section (reset #xfffc)))

        ;; The stores sit in the BOTTOM half of $C0 - offset $0000-$7FFF - which
        ;; is the same ROM the SA-1 map exposes as bank $00:$8000-$FFFF.
        (memory HiROM-c0
                (address (#xc00000 . #xc0ffff))
                (type ROM)
                (qualifier far)
                (section farcode cdata cnear cfar chuge switch ifar ihuge (LoROM-store #xc00000) (HeaderExt-store #xc07fb0) (Header-store #xc07fc0) (Vector-store #xc07fe0)))

        (memory HiROM
                (address (#xc10000 . #xc2ffff))
                (type ROM)
                (qualifier far)
                (section farcode cdata cnear cfar chuge switch ifar ihuge))

        ;; Switchable sprite CHR
