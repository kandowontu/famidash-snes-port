;; Linker rules for C running on the SA-1.
;;
;; The interesting part is the RAM, because the SA-1 cannot see $7E/$7F WRAM at
;; all. Everything the port keeps in WRAM today has to be re-homed, and the SA-1
;; offers three places with quite different properties:
;;
;;   I-RAM      2KB, $0000-$07FF. The only memory the S-CPU can also reach
;;              cheaply, so it is where the two processors talk. Also where the
;;              direct page goes - direct page must be in bank 0, and I-RAM is
;;              the fastest thing there.
;;   BW-RAM     cartridge RAM. The SA-1 sees it linearly at $40:0000 and ALSO
;;              through an 8KB window at $00:6000-$7FFF. The window is in bank
;;              0, which is what `near` addressing and the stack require, so the
;;              window holds the stack and near data and the linear view holds
;;              the bulk.
;;   ROM        code and constants, as before.
;;
;; M2.25 measured BW-RAM and I-RAM as exactly equal for data, so putting 34KB of
;; game state on the cartridge costs nothing. What is NOT free is instruction
;; fetch from ROM - which is why I-RAM is reserved for shared buffers and,
;; later, hot code, and deliberately not spent on data.
;;
;; The window and the linear view are the SAME physical BW-RAM. With CBMAP=0 the
;; window shows BW-RAM $0000-$1FFF, so the linear region below starts at $2000 -
;; otherwise near data and far data would silently alias.
(define memories
        '((memory DirectPage
                (address (#x0 . #xff))
                (type RAM)
                (section registers ztiny tiny))

        ;; The S-CPU <-> SA-1 mailbox. Hand-placed rather than left to the
        ;; allocator: the Lua verifiers and the S-CPU's assembly both address it
        ;; numerically, so it has to sit still.
        (memory IRamShared
                (address (#x100 . #x6ff))
                (type RAM)
                (section iram))

        (memory FamiAudioRAM
                (address (#x700 . #x7ff))
                (type RAM)
                (section fsaudioram))

        ;; BW-RAM through the $6000 window: bank 0, so `near` and the stack work.
        (memory NearRAM
                (address (#x6000 . #x7fff))
                (type RAM)
                (qualifier near)
                (section stack cstack data znear near))

        ;; BW-RAM linear, starting past the 8KB the window covers.
        (memory FarRAM
                (address (#x402000 . #x40ffff))
                (type RAM)
                (qualifier far)
                (section heap zfar far huge))

        (memory ROM
                (address (#x8000 . #xffaf))
                (type ROM)
                (qualifier near)
                (section sa1code code farcode compactcode cdata cnear cfar chuge switch
                         itiny idata inear ifar ihuge data_init_table))

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
        (base-address _NearBaseAddress NearRAM 0)
    ))
