(define memories
        '((memory DirectPage
                (address (#x0 . #xff))
                (type RAM)
                (section registers ztiny tiny))
        (memory LoRAM
                (address (#x100 . #x1dff))
                (type RAM)
                (qualifier near)
                (section stack data znear near))

        ;; A relocatable direct page for the original 6502 FamiStudio engine.
        ;; Native wrappers set D=$1E00 while the sequencer runs; keeping this
        ;; out of LoRAM prevents the C stack/near allocator from claiming it.
        (memory FamiAudioRAM
                (address (#x1e00 . #x1eff))
                (type RAM)
                (qualifier near)
                (section fsaudioram))
        (memory HiRAM
                (address (#x7e2000 . #x7fffff))
                (type RAM)
                (qualifier far)
                (section heap zfar far huge))

        (memory LoROM
                (address (#x8000 . #xffaf))
                (type ROM)
                (qualifier near)
                (scatter-to LoROM-store)
                (section code compactcode cdata cnear switch itiny idata inear data_init_table))

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

        (memory HiROM-c0
                (address (#xc00000 . #xc0ffff))
                (type ROM)
                (qualifier far)
                (section farcode cdata cnear cfar chuge switch ifar ihuge (LoROM-store #xc08000) (HeaderExt-store #xc0ffb0) (Header-store #xc0ffc0) (Vector-store #xc0ffe0)))

        (memory HiROM
                (address (#xc10000 . #xc2ffff))
                (type ROM)
                (qualifier far)
                (section farcode cdata cnear cfar chuge switch ifar ihuge))

        ;; Switchable sprite CHR (tools/gen_sprchr.py), one bank of its own.
        ;;
        ;; These are DMA'd into OBJ VRAM when the game switches a CHR bank, and
        ;; DMA increments the A-bus address WITHIN a bank without carrying into
        ;; the bank byte - so a 4KB block that straddled a ROM bank boundary
        ;; would wrap to the start of its own bank half way through. Fourteen
        ;; 4KB blocks is 56KB, they are emitted in order from offset 0, and 4KB
        ;; divides 64KB exactly, so none of them can straddle.
        (memory SpriteCHR
                (address (#xc30000 . #xc3ffff))
                (type ROM)
                (qualifier far)
                (section sprchr))

        ;; The BG tilesets (tools/gen_bgchr.py). Unlike the sprite banks these
        ;; change only at level load, so the whole 4KB goes up at once - but the
        ;; same 64KB-bank rule applies, and 4KB divides a bank exactly, so no
        ;; block can straddle one.
        (memory BGCHR
                (address (#xca0000 . #xcaffff))
                (type ROM)
                (qualifier far)
                (section bgchr))

        ;; Every level of the set, compressed (tools/gen_levels.py): the LZ
        ;; streams and the sprite-object streams, one section per level.
        ;;
        ;; Declared one memory PER BANK on purpose. The linker allocates ROM in
        ;; bank chunks and a single section cannot exceed a bank, so the data is
        ;; emitted per level rather than as one blob - and per-bank memories
        ;; also mean the linker cannot place a level across a bank boundary,
        ;; which keeps every level readable through one pointer.
        ;;
        ;; Six banks for ~286KB. gen_levels.py prints the totals; if a level set
        ;; outgrows this, add banks here.
        (memory LevelData0
                (address (#xc40000 . #xc4ffff))
                (type ROM)
                (qualifier far)
                (section lvldata))
        (memory LevelData1
                (address (#xc50000 . #xc5ffff))
                (type ROM)
                (qualifier far)
                (section lvldata))
        (memory LevelData2
                (address (#xc60000 . #xc6ffff))
                (type ROM)
                (qualifier far)
                (section lvldata))
        (memory LevelData3
                (address (#xc70000 . #xc7ffff))
                (type ROM)
                (qualifier far)
                (section lvldata))
        (memory LevelData4
                (address (#xc80000 . #xc8ffff))
                (type ROM)
                (qualifier far)
                (section lvldata))
        (memory LevelData5
                (address (#xc90000 . #xc9ffff))
                (type ROM)
                (qualifier far)
                (section lvldata))

        (base-address _DirectPageStart DirectPage 0)
        (base-address _NearBaseAddress LoRAM 0)
    ))
