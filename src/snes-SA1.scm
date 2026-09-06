;; Linker rules for the SA-1 probe.
;;
;; SA-1 cartridges use the LoROM-shaped map - 32KB per bank at $8000-$FFFF, with
;; the header at $7FC0 in the image - not the HiROM layout the main port uses.
;; That is worth knowing before the game moves across: the ROM layout changes
;; too, not just the CPU.
;;
;; This is a 32KB image: everything, both processors' code, in bank $00.
(define memories
        '((memory DirectPage
                (address (#x0 . #xff))
                (type RAM)
                (section registers ztiny tiny))

        ;; I-RAM: the 2KB both processors can see. $3000-$37FF for the S-CPU,
        ;; $0000-$07FF for the SA-1. The only cheap shared memory there is - the
        ;; SA-1 has no access to $7E/$7F WRAM at all.
        (memory IRAM
                (address (#x3000 . #x37ff))
                (type RAM)
                (section iram))

        (memory ROM
                (address (#x8000 . #xffaf))
                (type ROM)
                (qualifier near)
                (section sa1code code cdata cnear switch itiny idata inear))

        (memory HeaderExtended
                (address (#xffb0 . #xffbf))
                (type ROM)
                (qualifier near)
                (section snesheaderextended))

        (memory HeaderBasic
                (address (#xffc0 . #xffdf))
                (type ROM)
                (qualifier near)
                (section snesheader))

        (memory Vector
                (address (#xffe0 . #xffff))
                (type ROM)
                (qualifier near)
                (section (reset #xfffc)))

        (base-address _DirectPageStart DirectPage 0)
    ))
