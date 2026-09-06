/*
 * shim_ppu.c - the NES video API, on SNES hardware.
 *
 * These are the neslib/nesdoug entry points the game calls to touch the PPU.
 * Signatures are unchanged; what happens underneath is not. The three mappings
 * that matter, and that everything else follows from:
 *
 *  1. NAMETABLE -> TILEMAP. The NES has two horizontal nametables at $2000 and
 *     $2400. BG1 here is a 64x64 map at VRAM word $6000. Its four 32x32 screen
 *     blocks preserve the NES address mapping horizontally and provide the
 *     complete vertical level window.
 *
 *  2. NO ATTRIBUTE TABLE. $23C0-$23FF and $27C0-$27FF are per-32x32-pixel
 *     palette bytes on the NES; on SNES the palette is in each tilemap word.
 *     Writes there are dropped, deliberately and loudly (see ppu_to_vram_word).
 *     get_at_addr() is absent from the shim for the same reason.
 *
 *  3. PALETTE. The game speaks NES palette indices. nes_to_cgram[] converts
 *     them to 15-bit BGR, and is generated from the asset pipeline's own table
 *     so the two cannot drift (tools/gen_palette.py).
 *
 * VRAM cannot be written while the screen is on, so everything that would have
 * gone straight to PPU_DATA is queued and flushed in vblank, which is what the
 * game's own vram buffer already expected.
 */

#include <stdint.h>
#include "shim_sa1.h"

/*
 * Screen control goes through the mailbox on the SA-1 and straight to the
 * registers otherwise. The game calls ppu_on_bg/ppu_off/ppu_mask from its own
 * logic, on whichever processor runs the game - so the write has to be
 * indirected at the point of use rather than the caller having to know.
 */
#ifdef SHIM_SA1
#define SHIM_INIDISP (SHIM_MB->inidisp)
#define SHIM_TM      (SHIM_MB->tm)
#else
#define SHIM_INIDISP INIDISP
#define SHIM_TM      TM
#endif
#include "arr_macros.h"
#include "neslib.h"
#include "nesdoug.h"
#include "mapper.h"
#include "nesdash.h"
#include "shim_spc.h"

/* --- SNES registers ----------------------------------------------------- */
#define REG(a) (*(volatile uint8_t *)(a))
#define INIDISP  REG(0x2100)
#define OBSEL    REG(0x2101)
#define OAMADDL  REG(0x2102)
#define OAMADDH  REG(0x2103)
#define OAMDATA  REG(0x2104)
#define BGMODE   REG(0x2105)
#define BG1SC    REG(0x2107)
#define BG12NBA  REG(0x210B)
#define BG1HOFS  REG(0x210D)
#define BG1VOFS  REG(0x210E)
#define VMAIN    REG(0x2115)
#define VMADDL   REG(0x2116)
#define VMADDH   REG(0x2117)
#define VMDATAL  REG(0x2118)
#define VMDATAH  REG(0x2119)
#define CGADD    REG(0x2121)
#define CGDATA   REG(0x2122)
#define TM       REG(0x212C)
#define STAT78   REG(0x213F)
#define HVBJOY   REG(0x4212)

/* DMA channel 0 */
#define DMAP0    REG(0x4300)
#define BBAD0    REG(0x4301)
#define A1T0L    REG(0x4302)
#define A1T0H    REG(0x4303)
#define A1B0     REG(0x4304)
#define DAS0L    REG(0x4305)
#define DAS0H    REG(0x4306)
#define MDMAEN   REG(0x420B)

/*
 * A pointer is 4 bytes here (24-bit address in the low 3), but the game's
 * uintptr_t is only 16 bits, so a pointer cannot be turned into a full address
 * by casting - see docs/HANDOFF.md trap 28. DMA needs the bank byte, hence the
 * union.
 */
union ptr_bits { const void *p; uint32_t v; };

static void dma_to_ppu(uint8_t bbad, const void *src, uint16_t len, uint8_t mode)
{
    union ptr_bits u;
    u.p = src;
    DMAP0 = mode;
    BBAD0 = bbad;
    A1T0L = (uint8_t)u.v;
    A1T0H = (uint8_t)(u.v >> 8);
    A1B0  = (uint8_t)(u.v >> 16);
    DAS0L = (uint8_t)len;
    DAS0H = (uint8_t)(len >> 8);
    MDMAEN = 0x01;
}

#define VRAM_BG1MAP 0x6000              /* word address, 64x64 map = 4096 words */

/* --- state shared with the rest of the shim ----------------------------- */
extern uint8_t PAL_UPDATE;
extern uint8_t PAL_BUF_RAW[32];
extern uint16_t PAL_BUF[32];
extern volatile unsigned char VRAM_UPDATE;
extern unsigned char drawing_frame;
extern const uint16_t nes_to_cgram[64];

uint8_t shim_screen_on;                 /* mirrors TM; ppu_off/on track it */
static uint8_t brightness = 0x0F;

/* ======================================================================== */
/* Palette                                                                  */
/* ======================================================================== */
/*
 * Gameplay uses Mode 1 so BG1 and BG2 are 4bpp. BG1 NES palettes 0-3 occupy
 * SNES palettes 0-3; parallax owns palette 4. NES background pixel 0 is an
 * opaque universal backdrop, while SNES pixel 0 is transparent, so converted
 * BG1 art uses index 4 for that colour. The game's PAL_BUF remains in its
 * original four-colour NES layout.
 */
void pal_col(uint8_t index, uint8_t color)
{
    index &= 0x1F;
    PAL_BUF_RAW[index] = color;
    PAL_BUF[index] = nes_to_cgram[color & 0x3F];
    ++PAL_UPDATE;
}

void pal_bg(const void *data)
{
    const uint8_t *p = (const uint8_t *)data;
    uint8_t i;
    for (i = 0; i < 16; i++)
        pal_col(i, p[i]);
}

void pal_spr(const void *data)
{
    const uint8_t *p = (const uint8_t *)data;
    uint8_t i;
    for (i = 0; i < 16; i++)
        pal_col(16 + i, p[i]);
}

void pal_all(const void *data)
{
    const uint8_t *p = (const uint8_t *)data;
    uint8_t i;
    for (i = 0; i < 32; i++)
        pal_col(i, p[i]);
}

void pal_clear(void)
{
    uint8_t i;
    for (i = 0; i < 32; i++)
        pal_col(i, 0x0F);               /* NES $0F is black */
}

/*
 * The NES faded by walking palette entries toward black through the colour
 * table. The SNES has a real master brightness register, so this is INIDISP.
 * 0 = black, 4 = normal; the game never asks for brighter than normal.
 */
void pal_bright(uint8_t bright)
{
    brightness = (bright >= 4) ? 0x0F : (uint8_t)(bright * 4);
    SHIM_INIDISP = (uint8_t)(shim_screen_on ? brightness : (0x80 | brightness));
}

void pal_fade_to(uint8_t from, uint8_t to)
{
    (void)from;
    pal_bright(to);
}

/*
 * Exact palBrightTable lookup from the NES neslib.
 *
 * This is not ordinary "subtract one brightness row" arithmetic. The NES
 * macro indexes 64 entries starting at palBrightTableN, so the colour's high
 * nibble advances through four consecutive 16-byte tables. In particular,
 * oneShadeDarker($02) is $0F (black), not $02. Returning $02 made Ground to
 * Space's first $02 colour trigger set both the backdrop and its dither ink to
 * the same blue, collapsing every striped sky tile into a solid field.
 */
uint8_t colBrightness(uint8_t color, uint8_t brightness_row)
{
    uint8_t hue = (uint8_t)(color & 0x0F);
    uint8_t table = (uint8_t)(brightness_row + ((color & 0x3F) >> 4));

    if (table <= 3)
        return 0x0F;
    if (table == 4)
        return hue;
    if (table == 5)
        return (uint8_t)(0x10 | hue);
    if (table == 6)
        return hue ? (uint8_t)(0x20 | hue) : 0x10;
    if (table == 7)
        return (uint8_t)(0x30 | hue);
    return 0x30;
}

/*
 * DMA, like every other bulk transfer here (docs/HANDOFF.md trap 36).
 *
 * Written as a C loop this was the single most expensive thing in the frame:
 * 32 colours is 64 writes to CGDATA plus the address changes, and it measured
 * at 27 of vblank's 37 scanlines - EVERY frame, because the game sets
 * PAL_UPDATE every frame. It pushed the rest of the flush past the end of
 * vblank, where VRAM writes are silently dropped (trap 35).
 *
 * Five transfers rather than one because of the sprite palette layout below;
 * each source run is contiguous in PAL_BUF, which is what DMA needs.
 */
static void cgram_flush(void)
{
    static uint16_t bg_cgram[80];
    uint8_t p;

    /*
     * Build five complete 4bpp palettes and DMA them as one run. A normal BG1
     * tile retains NES indices 1-3 and maps NES 0 to SNES 4; only tile $FE
     * contains real zeroes and reveals BG2. Palette 4 belongs to parallax.
     */
    for (p = 0; p < 4; p++) {
        uint16_t *dst = &bg_cgram[(uint16_t)p * 16];
        dst[0] = PAL_BUF[0];
        dst[1] = PAL_BUF[(uint16_t)p * 4 + 1];
        dst[2] = PAL_BUF[(uint16_t)p * 4 + 2];
        dst[3] = PAL_BUF[(uint16_t)p * 4 + 3];
        dst[4] = PAL_BUF[0];
    }
    bg_cgram[64] = PAL_BUF[0];
    bg_cgram[65] = PAL_BUF[1];

    CGADD = 0;
    /*
     * Preserve a deliberate all-black transition: on NES, black backdrop +
     * black darker ink hides the pattern completely. Only repair a future
     * non-black conversion collision in the parallax-owned entry.
     */
    if (PAL_BUF[0] != 0 && PAL_BUF[1] == PAL_BUF[0]) {
        bg_cgram[65] = 0;
    }
    dma_to_ppu(0x22, bg_cgram, 160, 0x00);          /* BG palettes 0-4 */

    /*
     * Sprites: the NES has four 4-colour palettes, the SNES eight 16-colour
     * ones. A converted sprite tile keeps pixel values 0-3, so NES palette p
     * maps onto the FIRST FOUR entries of SNES OBJ palette p - i.e. CGRAM
     * 128 + p*16 + c, with the other 12 entries of each unused. That is what
     * lets one tile be drawn under any of the four palettes, exactly as on the
     * NES, without four copies of the art.
     *
     * Four runs of four colours, so four transfers - the destination jumps 16
     * CGRAM entries between them while the source is consecutive.
     */
    for (p = 0; p < 4; p++) {
        CGADD = (uint8_t)(128 + p * 16);
        dma_to_ppu(0x22, &PAL_BUF[16 + p * 4], 8, 0x00);
    }
    PAL_UPDATE = 0;
}

/* ======================================================================== */
/* OAM                                                                      */
/* ======================================================================== */
/*
 * A shadow OAM, flushed in vblank. 128 sprites: a 512-byte low table
 * (X, Y, tile, attr) plus a 32-byte high table of 2 bits each - X bit 9 and the
 * size bit. Clearing only the low table leaves power-on garbage in the high one
 * and scatters coloured blocks over the screen (docs/HANDOFF.md trap 19).
 */
/*
 * One buffer, not two arrays: OAM is a single 544-byte region and the flush is
 * one DMA, so the low and high tables have to be genuinely contiguous. Two
 * separate arrays that happen to be laid out next to each other would work
 * until the linker decided otherwise.
 */
#define OAM_SPRITES 128
#define OAM_LO_SIZE (OAM_SPRITES * 4)
#define OAM_HI_SIZE (OAM_SPRITES / 4)
/* Not static: shim/src/oam_spr.s writes this table and the cursor directly. */
uint8_t oam_buf[OAM_LO_SIZE + OAM_HI_SIZE];
#define oam_lo (oam_buf)
#define oam_hi (oam_buf + OAM_LO_SIZE)

/*
 * Byte cursor into oam_lo. It MUST be 16-bit: oam_lo is 512 bytes, so a uint8_t
 * cannot even address half the table, and the bound it was being tested against
 * -- (uint8_t)(sizeof(oam_lo) - 4) -- truncated 540 to 28, which capped the
 * whole game at EIGHT hardware sprites. Two NES sprites. The generated code was
 * `lda ##28 / cmp long:sprid / bcc return`, and the player alone uses four.
 */
uint16_t sprid;                         /* not static: oam_spr.s advances it */
static uint16_t oam_hiwater;            /* highest cursor since the last flush */
static uint8_t obj_name_base;           /* bank_spr(): 0 or 1 */

/* NES OAM is 64 sprites of 4 bytes; each becomes two SNES sprites here, so an
   index in the game's units is twice as far into this table. Nothing in SAUCE/
   actually calls these, but the signatures are part of the API. */
void oam_set(uint8_t index) { sprid = (uint16_t)index * 2; }
uint8_t oam_get(void) { return (uint8_t)(sprid / 2); }
void bank_spr(uint8_t n) { obj_name_base = (uint8_t)(n & 1); }

/*
 * Hiding all 128 sprites here cost 28 scanlines a frame - over 10% of the frame
 * spent writing 240 into entries that were about to be overwritten anyway. Only
 * the entries used LAST frame and not reused this one actually need hiding, so
 * the cursor resets here and oam_flush() hides the tail from sprid up to the
 * high-water mark. Same result on screen, a twentieth of the work.
 *
 * The high table is not touched either: oam_put never sets X bit 9 (NES X is
 * 8-bit) or the size bit, so once video_init has zeroed it, it stays zero.
 */
void oam_clear(void)
{
    sprid = 0;
}

/*
 * The one full clear, from the boot path. oam_clear() no longer does this, so
 * without it the shadow buffer's power-on state is what gets DMA'd: 128 sprites
 * at Y = 0 naming tile 0. Also zeroes the 32-byte high table, which nothing
 * else writes - oam_put never sets X bit 9 (NES X is 8 bits) or the size bit,
 * so zeroing it once is enough. Leaving it is trap 19: the garbage shows up as
 * coloured blocks scattered over the screen.
 */
void oam_init(void)
{
    uint16_t i;

    for (i = 0; i < OAM_LO_SIZE; i += 4) {
        oam_lo[i + 0] = 0;
        oam_lo[i + 1] = 240;            /* below the 224-line display */
        oam_lo[i + 2] = 0;
        oam_lo[i + 3] = 0;
    }
    for (i = 0; i < OAM_HI_SIZE; i++)
        oam_hi[i] = 0;
    sprid = 0;
    oam_hiwater = 0;
}

/* The game clears just the player's own sprites without disturbing the rest.
   16 NES sprites is 32 SNES ones - clearing 16 left half of a two-player
   player 1 on screen. */
void oam_clear_player(void)
{
    uint8_t i;
    for (i = 0; i < 32; i++)
        oam_lo[i * 4 + 1] = 240;
}

void oam_clear_two_players(void)
{
    uint8_t i;
    for (i = 0; i < 64; i++)
        oam_lo[i * 4 + 1] = 240;
}

/*
 * The game runs the NES in 8x16 sprite mode (PPU_CTRL bit 5, set in crt0.s), and
 * the SNES has no 8x16 OBJ size - the sizes come in pairs like 8x8/16x16. So
 * ONE NES sprite becomes TWO SNES 8x8 sprites, stacked.
 *
 * In 8x16 mode the NES tile byte means something different too: bit 0 selects
 * the pattern table and the rest is the tile pair, so the halves are
 * (chrnum & 0xFE) and that + 1. Pattern table 1 is mapped to SNES OBJ tiles
 * 256+, which OBSEL's name-select puts $1000 words above the OBJ base.
 */
/*
 * oam_spr() itself is in shim/src/oam_spr.s - the one hand-written routine in
 * the shim.
 *
 * The header there says why, and carries the NES-to-SNES attribute and 8x16
 * tile mapping that used to be documented here: it is the innermost loop of the
 * port, it cost 4.2 scanlines a call in C, and a busy frame makes twenty of
 * those calls out of a 262-scanline budget.
 *
 * It writes oam_buf and sprid directly, which is why both are non-static.
 */

/*
 * Metasprite format, from __oam_meta_spr in LIB/asm/neslib.s: a stream of
 * (x offset, y offset, tile, attribute) quadruplets terminated by an x offset
 * of $80. Offsets are signed. A sprite whose position overflows out of the
 * 256-pixel space is dropped rather than wrapped, which is what the original's
 * carry tests are doing.
 */
/*
 * The walk is bounded. Nothing in the game's own data needs it - every
 * metasprite there is a handful of sprites - but an unbounded walk over a bad
 * pointer is not a graceful failure: it emits sprites until it happens to read
 * an $80 byte. One did, and it cost 7161 sprites and fifty video frames in a
 * single call (draw_sprites.h, the animation-frame struct). The cause is fixed;
 * this makes the next one a glitch instead of a hang. NES OAM holds 64 sprites,
 * so anything past that could not have been drawn on the original either.
 */
#define META_SPR_MAX 64

/*
 * x and y are held as 16-bit locals and the quadruplet is read by index rather
 * than through four `*p++`. Both are for code generation, not clarity: as
 * uint8_t they were re-masked with `and ##255` at every use, and each `*p++`
 * became its own load / stack store / pointer increment with a sep/rep pair
 * around it.
 */
/*
 * The walk itself is shim_meta_run() in shim/src/oam_spr.s, and its header
 * documents the offset mirroring and the drop rules it implements.
 *
 * It measured at roughly 3 scanlines per sprite in C - about half of
 * draw_sprites, and the reason a screen with a portal on it (9 sprites in one
 * metasprite, the largest object in the game) dropped frames. The work is four
 * byte reads and two adds; the cost was Calypsi's handling of 8-bit values in
 * 16-bit registers, which is not fixable from C.
 *
 * ARGUMENTS GO THROUGH THESE GLOBALS, NOT THROUGH THE CALLING CONVENTION.
 * oam_spr.s can rely on Calypsi's convention because its arguments are all
 * scalars in A and on the stack. A pointer argument is different: it arrives in
 * the compiler's direct-page pseudo-registers (`_Dp`), which are its own
 * scratch and not something to build an interface on. The C wrappers below cost
 * a few dozen cycles per metasprite - not per sprite - and remove that
 * dependency entirely.
 *
 * These are uint16_t rather than uint8_t on purpose: the assembly reads them
 * with 16-bit loads, and a byte-sized global would drag in whatever the linker
 * happened to place next to it.
 */
const uint8_t *shim_meta_ptr;
uint16_t shim_meta_x, shim_meta_y, shim_meta_disco, shim_meta_flip;
void shim_meta_run(void);                       /* oam_spr.s */

void oam_meta_spr(uint8_t x, uint8_t y, const void *data)
{
    shim_meta_ptr = (const uint8_t *)data;
    shim_meta_x = x;
    shim_meta_y = y;
    shim_meta_disco = 0;
    shim_meta_flip = 0;
    shim_meta_run();
}

/* Same, but the palette cycles per frame - the game's "disco" effect. */
void oam_meta_spr_disco(uint8_t x, uint8_t y, const void *data)
{
    shim_meta_ptr = (const uint8_t *)data;
    shim_meta_x = x;
    shim_meta_y = y;
    shim_meta_disco = 1;
    shim_meta_flip = 0;
    shim_meta_run();
}

void oam_meta_spr_flipped(uint8_t flip, uint8_t x, uint8_t y, const void *data)
{
    shim_meta_ptr = (const uint8_t *)data;
    shim_meta_x = x;
    shim_meta_y = y;
    shim_meta_disco = 0;
    shim_meta_flip = flip;
    shim_meta_run();
}

/*
 * 544 bytes, so this has to be DMA too: a C loop over it takes several times
 * the whole vblank and the sprites at the end of the table never arrive.
 * oam_lo and oam_hi are declared adjacent so one transfer covers both.
 */
static void oam_flush(void)
{
    uint16_t i;

    /*
     * Hide whatever last frame drew and this frame did not reach. This is the
     * work oam_clear() used to do for all 128 sprites up front; doing it here
     * means only the entries that actually went stale are touched.
     */
    for (i = sprid; i < oam_hiwater; i += 4)
        oam_lo[i + 1] = 240;            /* Y below the 224-line display */
    oam_hiwater = sprid;

    OAMADDL = 0;
    OAMADDH = 0;
    dma_to_ppu(0x04, oam_buf, sizeof(oam_buf), 0x00);
}

/* ======================================================================== */
/* VRAM                                                                     */
/* ======================================================================== */
/*
 * PPU address -> BG1 tilemap word. Returns 0xFFFF for the attribute tables,
 * which have no SNES equivalent: the palette is a field of each tilemap word,
 * chosen per metatile from metatiles_attr (docs/HANDOFF.md trap 24).
 */
static uint16_t ppu_to_vram_word(uint16_t ppu)
{
    uint16_t off = (uint16_t)(ppu & 0x03FF);
    if (off >= 0x03C0)
        return 0xFFFF;                  /* attribute table - no equivalent */
    return (uint16_t)(VRAM_BG1MAP + ((ppu & 0x0400) ? 0x0400 : 0) + off);
}

static uint16_t vram_ptr;               /* current vram_adr(), word address */

void vram_adr(uint16_t adr)
{
    vram_ptr = ppu_to_vram_word(adr);
    if (vram_ptr == 0xFFFF)
        return;
    VMAIN = 0x80;                       /* +1 word, step on the high byte */
    VMADDL = (uint8_t)vram_ptr;
    VMADDH = (uint8_t)(vram_ptr >> 8);
}

/*
 * A tilemap word is tile | palette<<10 | priority<<13 | flips. The game hands
 * us a bare NES tile number, so the palette has to come from somewhere: the
 * asset pipeline bakes it per metatile, and direct vram_put() is only used for
 * text and menu screens, which are all palette 0.
 */
void vram_put(uint8_t val)
{
    if (vram_ptr == 0xFFFF)
        return;
    VMDATAL = val;
    VMDATAH = 0;
    vram_ptr++;
}

void vram_fill(uint8_t n, uint16_t len)
{
    uint16_t i;
    if (vram_ptr == 0xFFFF)
        return;
    for (i = 0; i < len; i++) {
        VMDATAL = n;
        VMDATAH = 0;
    }
    vram_ptr = (uint16_t)(vram_ptr + len);
}

void vram_write(const void *src, uint16_t size)
{
    const uint8_t *p = (const uint8_t *)src;
    uint16_t i;
    for (i = 0; i < size; i++)
        vram_put(p[i]);
}

void vram_read(void *dst, uint16_t size)
{
    /* Nothing in the gameplay path reads VRAM back. */
    (void)dst; (void)size;
}

void vram_inc(uint8_t n)
{
    /* NES: +1 or +32 per write. The SNES equivalent is VMAIN's step field. */
    VMAIN = (uint8_t)(n ? 0x81 : 0x80);
}

/*
 * RLE nametable decoder, from _vram_unrle in LIB/asm/neslib.s. The first byte
 * is the run tag; after that a byte that is not the tag is literal, and the tag
 * introduces a count of repeats of the previous byte. A count of zero ends it.
 */
void vram_unrle(const void *data)
{
    const uint8_t *p = (const uint8_t *)data;
    uint8_t tag = *p++;
    uint8_t last = 0;

    for (;;) {
        uint8_t b = *p++;
        if (b != tag) {
            vram_put(b);
            last = b;
        } else {
            uint8_t count = *p++;
            if (count == 0)
                return;
            while (count--)
                vram_put(last);
        }
    }
}

/* ======================================================================== */
/* VRAM update buffer                                                       */
/* ======================================================================== */
/*
 * The NES could only touch VRAM during vblank, so nesdoug queued writes and
 * flushed them in NMI. The SNES has the same restriction, so the queue stays -
 * but entries are (word address, word value) rather than the NES's packed
 * address/length/data stream, because there is no run-length form to preserve.
 */
#define VRAM_QUEUE 128
static uint16_t vq_addr[VRAM_QUEUE];
static uint16_t vq_data[VRAM_QUEUE];
static uint8_t vq_len;
static uint8_t vq_enabled;

void set_vram_buffer(void) { vq_enabled = 1; }

void clear_vram_buffer(void) { vq_len = 0; }

static void vq_push(uint16_t word_addr, uint16_t value)
{
    if (word_addr == 0xFFFF || vq_len >= VRAM_QUEUE)
        return;
    vq_addr[vq_len] = word_addr;
    vq_data[vq_len] = value;
    vq_len++;
    VRAM_UPDATE = 1;
}

void one_vram_buffer(uint8_t data, uint16_t ppu_address)
{
    vq_push(ppu_to_vram_word(ppu_address), data);
}

void multi_vram_buffer_horz(const void *data, uint8_t len, uint16_t ppu_address)
{
    const uint8_t *p = (const uint8_t *)data;
    uint16_t base = ppu_to_vram_word(ppu_address);
    uint8_t i;
    if (base == 0xFFFF)
        return;
    for (i = 0; i < len; i++)
        vq_push((uint16_t)(base + i), p[i]);
}

void multi_vram_buffer_vert(const void *data, uint8_t len, uint16_t ppu_address)
{
    const uint8_t *p = (const uint8_t *)data;
    uint16_t base = ppu_to_vram_word(ppu_address);
    uint8_t i;
    if (base == 0xFFFF)
        return;
    for (i = 0; i < len; i++)
        vq_push((uint16_t)(base + i * 32), p[i]);
}

void one_vram_buffer_horz_repeat(uint8_t data, uint8_t len, uint16_t ppu_address)
{
    uint16_t base = ppu_to_vram_word(ppu_address);
    uint8_t i;
    if (base == 0xFFFF)
        return;
    for (i = 0; i < len; i++)
        vq_push((uint16_t)(base + i), data);
}

void one_vram_buffer_vert_repeat(uint8_t data, uint8_t len, uint16_t ppu_address)
{
    uint16_t base = ppu_to_vram_word(ppu_address);
    uint8_t i;
    if (base == 0xFFFF)
        return;
    for (i = 0; i < len; i++)
        vq_push((uint16_t)(base + i * 32), data);
}

/*
 * A whole tilemap column, for the level renderer. This bypasses the (addr,
 * value) queue because a column is 32 consecutive-by-32 words and the SNES can
 * write it with one address set-up and VMAIN stepping by 32 - the reason the
 * column records are shaped the way they are.
 *
 * Columns are held in their own small queue and flushed with the rest in
 * vblank, so the caller does not have to know when vblank is.
 */
#define COL_QUEUE 64
static uint16_t cq_slot[COL_QUEUE];
static const uint8_t *cq_src[COL_QUEUE];
static uint8_t cq_len;

/*
 * A vertically scrolling level can be 60 metatile rows (120 tile rows) tall,
 * while the largest SNES tilemap is 64 tile rows.  shim_engine therefore uses
 * the map as a vertical ring and replaces the row entering the viewport.
 *
 * Copy the prepared row into this queue.  The engine's scratch row is reused
 * immediately, and on SA-1 the S-CPU consumes the queue only after the SA-1
 * reaches the next frame handshake.
 */
#define ROW_QUEUE 32
static uint8_t rq_slot[ROW_QUEUE];
static uint16_t rq_data[ROW_QUEUE][64];
static uint8_t rq_len;

/* Non-static so a trace can tell "dropped" apart from "wrote the wrong thing" -
   the two look identical in a VRAM diff. */
uint16_t shim_col_drops;
uint16_t shim_row_drops;

void queue_vram_column(uint16_t slot, const uint8_t *rec)
{
    if (cq_len >= COL_QUEUE) {
        shim_col_drops++;
        return;                         /* behind - drop, the camera will retry */
    }
    cq_slot[cq_len] = slot;
    cq_src[cq_len] = rec;
    cq_len++;
    VRAM_UPDATE = 1;
}

uint8_t queue_vram_row(uint8_t slot, const uint16_t *rec)
{
    uint16_t *dst;
    uint8_t i;

    if (rq_len >= ROW_QUEUE) {
        shim_row_drops++;
        return 0;
    }
    rq_slot[rq_len] = (uint8_t)(slot & 0x3F);
    dst = rq_data[rq_len];
    for (i = 0; i < 64; i++)
        *dst++ = *rec++;
    rq_len++;
    VRAM_UPDATE = 1;
    return 1;
}

void clear_vram_row_queue(void) { rq_len = 0; }

/*
 * One logical 64-word row occupies two 32-word SNES screen blocks.  Flush rows
 * before columns: set_scroll_y() prepares an entering row before draw_screen()
 * decodes the newest far-ahead column, so that newer column must win at their
 * intersection.
 */
static void row_flush(void)
{
    uint8_t i;

    if (!rq_len)
        return;
    VMAIN = 0x80;                       /* +1 word, step on the high byte */
    for (i = 0; i < rq_len; i++) {
        uint8_t row = rq_slot[i];
        uint16_t base = (uint16_t)(VRAM_BG1MAP
                                   + ((row & 0x1F) << 5)
                                   + ((row & 0x20) ? 0x800 : 0));

        VMADDL = (uint8_t)base;
        VMADDH = (uint8_t)(base >> 8);
        dma_to_ppu(0x18, rq_data[i], 64, 0x01);          /* columns 0-31 */

        base = (uint16_t)(base + 0x400);
        VMADDL = (uint8_t)base;
        VMADDH = (uint8_t)(base >> 8);
        dma_to_ppu(0x18, rq_data[i] + 32, 64, 0x01);     /* columns 32-63 */
    }
    rq_len = 0;
}

/*
 * DMA, not a C loop. A column is 64 bytes and vblank is roughly 3400 CPU
 * cycles; writing it a byte at a time from C overruns vblank and the tail of
 * every column is simply lost - which looks exactly like "the renderer wrote
 * the wrong data". DMA moves 64 bytes in a few hundred master cycles.
 *
 * This is why the column records are bank-aligned (tools/gen_columns.py): DMA
 * increments the A-bus address within a bank and does not carry into the bank
 * byte, so a record that straddled a bank would wrap to the start of its own
 * bank halfway through.
 */
static void column_flush(void)
{
    uint8_t i;
    if (!cq_len)
        return;
    VMAIN = 0x81;                       /* +32 words, step on the high byte */
    for (i = 0; i < cq_len; i++) {
        /*
         * A 64x64 map is FOUR 32x32 screens, laid out SC0 SC1 SC2 SC3 at +0,
         * +$400, +$800, +$C00 words. A column is 64 tiles tall, so it spans two
         * screens vertically and needs two transfers: rows 0-31 into SC0/SC1
         * and rows 32-63 into SC2/SC3, $800 words apart.
         */
        uint16_t base = (uint16_t)(VRAM_BG1MAP + (cq_slot[i] & 0x1F)
                                   + ((cq_slot[i] & 0x20) ? 0x400 : 0));
        VMADDL = (uint8_t)base;
        VMADDH = (uint8_t)(base >> 8);
        dma_to_ppu(0x18, cq_src[i], 64, 0x01);          /* rows 0-31  */

        base = (uint16_t)(base + 0x800);
        VMADDL = (uint8_t)base;
        VMADDH = (uint8_t)(base >> 8);
        dma_to_ppu(0x18, cq_src[i] + 64, 64, 0x01);     /* rows 32-63 */
    }
    cq_len = 0;
}

/*
 * VRAM is only writable in forced blank or vblank; writes during active display
 * are dropped by the hardware, silently. The NES had the same restriction, which
 * is why nesdoug queues writes at all - but its flush ran from NMI, and the game
 * calls this one from wherever it likes.
 *
 * So: flush now if forced blank is on (level init, before the screen comes up),
 * otherwise leave everything queued for ppu_wait_nmi() to push in vblank. The
 * caller cannot tell the difference; a flush that silently did nothing is what
 * made the first streaming level render come out half-wrong.
 */
static void vram_flush_now(void)
{
    uint8_t i;

    row_flush();
    column_flush();
    VMAIN = 0x80;
    for (i = 0; i < vq_len; i++) {
        VMADDL = (uint8_t)vq_addr[i];
        VMADDH = (uint8_t)(vq_addr[i] >> 8);
        VMDATAL = (uint8_t)vq_data[i];
        VMDATAH = (uint8_t)(vq_data[i] >> 8);
    }
    vq_len = 0;
    VRAM_UPDATE = 0;
}

/* The real work, for the S-CPU to call through the request dispatcher. */
void shim_scpu_vram_flush(void) { vram_flush_now(); }

void flush_vram_update2(void)
{
    if (shim_screen_on)
        return;                 /* deferred; ppu_wait_nmi pushes it in vblank */
#ifdef SHIM_SA1
    /* Not vram_flush_now() here: on the SA-1 it would empty the queue without
       moving anything, which is how the level's first screen was being thrown
       away. The S-CPU does the transfer and this waits for it. */
    shim_request(SHIM_REQ_VRAM_FLUSH);
#else
    vram_flush_now();
#endif
}

/* ======================================================================== */
/* CHR bank uploads                                                         */
/* ======================================================================== */
/*
 * A mapper CHR bank switch, on hardware that has no CHR ROM: the tiles have to
 * be moved into VRAM. shim_misc.c's mmc3_set_*_chr_bank_* call this when the
 * requested bank actually changes; the transfer happens in vblank.
 *
 * Full 4KB banks are chunked because one would consume most of vblank. Runtime
 * player switches use a generated-bank delta no larger than this frame's
 * budget. Decoration animation keeps both phases resident and queues nothing.
 */
#define CHR_QUEUE 4
#define CHR_BUDGET 2048                 /* bytes per vblank */

static struct {
    const uint8_t *src;
    uint16_t dest;                      /* VRAM word address */
    uint16_t left;                      /* bytes still to send */
} chr_q[CHR_QUEUE];
static uint8_t chr_q_len;

/* Non-static: a dropped upload and a wrong upload look identical on screen. */
uint16_t shim_chr_drops;

/*
 * How many uploads are still in flight. A bank is 4KB and the budget is 2KB a
 * frame, so a switch lands over two frames and VRAM legitimately disagrees with
 * the selected bank in between. A check that does not know this reports a
 * half-arrived upload as corruption (docs/HANDOFF.md trap 55 is the same shape:
 * rld_column counts queued columns, not written ones).
 */
uint8_t shim_chr_pending;

void queue_chr_upload(uint16_t dest_word, const uint8_t *src, uint16_t bytes)
{
    uint8_t i;

    /* Replacing a pending upload to the same place is not a drop - it is the
       game changing its mind before the first one was sent. */
    for (i = 0; i < chr_q_len; i++) {
        if (chr_q[i].dest == dest_word) {
            chr_q[i].src = src;
            chr_q[i].left = bytes;
            VRAM_UPDATE = 1;
            return;
        }
    }
    if (chr_q_len >= CHR_QUEUE) {
        shim_chr_drops++;
        return;
    }
    chr_q[chr_q_len].src = src;
    chr_q[chr_q_len].dest = dest_word;
    chr_q[chr_q_len].left = bytes;
    chr_q_len++;
    shim_chr_pending = chr_q_len;
    VRAM_UPDATE = 1;
}

static void chr_flush(uint16_t budget)
{
    uint16_t n;
    uint8_t head = 0;

    /*
     * Consume through the array and compact once. This also keeps forced-blank
     * multi-upload drains linear.
     */
    while (head < chr_q_len && budget) {
        n = chr_q[head].left < budget ? chr_q[head].left : budget;
        VMAIN = 0x80;                   /* +1 word, step on the high byte */
        VMADDL = (uint8_t)chr_q[head].dest;
        VMADDH = (uint8_t)(chr_q[head].dest >> 8);
        dma_to_ppu(0x18, chr_q[head].src, n, 0x01);

        chr_q[head].src += n;
        chr_q[head].dest =
            (uint16_t)(chr_q[head].dest + (n >> 1));   /* words */
        chr_q[head].left = (uint16_t)(chr_q[head].left - n);
        budget = (uint16_t)(budget - n);

        if (chr_q[head].left == 0)
            head++;
    }

    if (head) {
        uint8_t i;
        for (i = head; i < chr_q_len; i++)
            chr_q[i - head] = chr_q[i];
        chr_q_len = (uint8_t)(chr_q_len - head);
        shim_chr_pending = chr_q_len;
    }
}

/* At level init the screen is in forced blank, so there is no budget to keep
   to and the whole thing can go at once - which is what makes the first frame
   correct rather than two-thirds uploaded. */
/* The real work, for the S-CPU to call through the request dispatcher. */
void shim_scpu_chr_now(void) { chr_flush(0xFFFF); }

void flush_chr_now(void)
{
#ifdef SHIM_SA1
    shim_request(SHIM_REQ_CHR_NOW);
#else
    chr_flush(0xFFFF);
#endif
}

/* ======================================================================== */
/* The level's own background art and colours                               */
/* ======================================================================== */
/*
 * On the NES the BG pattern table is four switchable 1KB CHR banks, chosen per
 * level from the header's spike set and block set (_set_tile_banks in
 * LIB/asm/neslib.s). The SNES has no CHR ROM, so the bank switch is a transfer
 * - and unlike the SPRITE banks (docs/M2_14_CHR_BANKING.md), which change
 * several times a second, these change only at level load, so the whole 4KB can
 * go through the same queue at once.
 *
 * tools/gen_bgchr.py collapses the level set to the ten combinations it
 * actually uses and lvl_bg_tileset[] indexes them.
 */
extern const uint8_t *const bg_tileset_ptr[];
extern const uint8_t *const bg_tileset_alt_ptr[];

#define VRAM_BG_TILES      0x0000       /* BG1 phase-0 char base, in words */
#define VRAM_BG_TILES_ALT  0x1000       /* BG1 phase-1 char base */

static uint8_t bg_tileset_loaded = 0xFF;

void set_bg_tileset(uint8_t which)
{
    if (which == bg_tileset_loaded)
        return;
    bg_tileset_loaded = which;
    queue_chr_upload(VRAM_BG_TILES, bg_tileset_ptr[which], 8192);
    queue_chr_upload(VRAM_BG_TILES_ALT, bg_tileset_alt_ptr[which], 8192);
    /* 8KB is four vblanks at the normal budget, so without this the level's
       first frames show half the PREVIOUS level's tiles - the boundary lands
       exactly at byte 2048. Level init runs in forced blank, where there is no
       budget to respect. */
    if (!shim_screen_on)
        flush_chr_now();
}

/* The level select draws with its own font in the same VRAM, so on the way back
   the tileset has to be sent again even though it has not changed. */
void bg_tileset_reload(void)
{
    BGMODE = 1;                        /* gameplay: BG1/BG2 are 4bpp */
    if (bg_tileset_loaded != 0xFF) {
        queue_chr_upload(VRAM_BG_TILES, bg_tileset_ptr[bg_tileset_loaded], 8192);
        queue_chr_upload(VRAM_BG_TILES_ALT,
                         bg_tileset_alt_ptr[bg_tileset_loaded], 8192);
        if (!shim_screen_on)
            flush_chr_now();
    }
}

#ifdef SHIM_SA1
/*
 * S-CPU request handlers must not call bg_tileset_reload(): forced blank makes
 * that routine call flush_chr_now(), whose SA-1 build sends another mailbox
 * request. From the S-CPU that request targets the wrong $0100 alias and waits
 * forever, leaving END_LEAVE at req/ack 10/9. Queue and drain locally instead.
 */
void shim_scpu_bg_tileset_reload(void)
{
    BGMODE = 1;                        /* also handles the first menu exit */
    if (bg_tileset_loaded != 0xFF) {
        queue_chr_upload(VRAM_BG_TILES, bg_tileset_ptr[bg_tileset_loaded], 8192);
        queue_chr_upload(VRAM_BG_TILES_ALT,
                         bg_tileset_alt_ptr[bg_tileset_loaded], 8192);
        chr_flush(0xFFFF);
    }
}
#endif

/*
 * The level header's two colours, placed exactly where nesdash.s puts them.
 *
 * PAL_BUF+0  the universal backdrop      = bg_color
 * PAL_BUF+1, +9, +13                     = bg_color one brightness step darker
 * PAL_BUF+6  the ground                  = ground_color
 * PAL_BUF+5                              = ground_color one step darker
 *
 * The darkening is palBrightTable3 in LIB/asm/neslib.s, which
 * tools/gen_palette.py copies out rather than reimplementing - it is not
 * arithmetic, $30 maps to $10 rather than to $20.
 */
extern const uint8_t nes_darken[64];

void set_level_colors(uint8_t bg_color, uint8_t ground_color)
{
    uint8_t bg = (uint8_t)(bg_color & 0x3F);
    uint8_t gr = (uint8_t)(ground_color & 0x3F);

    pal_col(0, bg);
    pal_col(1, nes_darken[bg]);
    pal_col(9, nes_darken[bg]);
    pal_col(13, nes_darken[bg]);
    pal_col(6, gr);
    pal_col(5, nes_darken[gr]);
}

/* ======================================================================== */
/* Screen control                                                           */
/* ======================================================================== */
void ppu_off(void)
{
    shim_screen_on = 0;
    SHIM_INIDISP = (uint8_t)(0x80 | brightness);        /* forced blank */
}

static void screen_on(uint8_t layers)
{
    shim_screen_on = 1;
    SHIM_TM = layers;
    SHIM_INIDISP = brightness;
}

extern uint8_t no_parallax;

void ppu_on_all(void)
{
    /* BG2 carries the original parallax pattern behind transparent BG1 sky. */
    screen_on((uint8_t)(no_parallax ? 0x11 : 0x13));  /* BG1 + [BG2] + OBJ */
}
void ppu_on_bg(void)  { screen_on(0x01); }
void ppu_on_spr(void) { screen_on(0x10); }

/*
 * The NES mask register also selected the left-8-pixel clipping and the
 * greyscale bit. The SNES has neither in the same place, and the game only ever
 * uses this to enable both layers.
 */
void ppu_mask(uint8_t mask)
{
    if (mask & 0x18)
        ppu_on_all();
    else
        ppu_off();
}

/* $213F bit 4: 1 = PAL. neslib's convention is 0 = PAL, so invert. */
uint8_t ppu_system(void) { return (uint8_t)((STAT78 & 0x10) ? 0 : 1); }

/*
 * Wait for vblank and push everything that has to move in it. There is no NMI
 * handler - snes-HiROM.scm only defines the reset vector, and enabling NMI
 * without one crashes into garbage (docs/HANDOFF.md trap 18) - so this polls.
 */
void ppu_wait_nmi(void)
{
    /*
     * neslib's real NMI calls FamiStudio whenever auto_fs_updates is non-zero.
     * Death/restart animations rely on that because their inner loops do not
     * call music_update themselves. Do it before waiting so the resulting APU
     * image is ready for this frame's SPC transfer without spending vblank.
     * On SA-1 this also keeps the sequencer on the SA-1; the S-CPU cannot run
     * its shared-I-RAM state.
     */
    if (auto_fs_updates)
        music_update();

#ifdef SHIM_SA1
    /*
     * On the SA-1 this is the whole frame boundary. HVBJOY is a PPU register
     * the SA-1 cannot read - it comes back as open bus, and open bus varies, so
     * the polling below does not block and the game free-runs with no pacing at
     * all. The handshake supplies the pacing instead: publish a sequence
     * number, then wait for the S-CPU to echo it back, which it does once per
     * vblank after pushing the buffers.
     *
     * Everything the non-SA-1 path does after the poll - scroll, CGRAM, VRAM,
     * OAM, CHR, pads - is the S-CPU's work now, because every one of them
     * touches registers in $2100-$43FF. See scpu_frame in src/sa1_boot.s.
     */
    uint8_t seq = (uint8_t)(SHIM_MB->sa1_seq + 1);
    SHIM_MB->sa1_seq = seq;
    while (SHIM_MB->scpu_seq != seq)
        ;

    /*
     * The S-CPU can read BW-RAM and DMA from it, but its writes to this SA-1
     * data window are protected.  Menu dirty flags therefore have to be
     * acknowledged here, on the SA-1, after the S-CPU has consumed them.
     * Otherwise a one-page change becomes two permanent page DMAs every frame
     * and the second transfer falls outside vblank.
     */
    fami_sa1_frame_ack();

    /*
     * The pads, AFTER the wait, exactly as the non-SA-1 path does them - and
     * for the same reason it does: neslib's NMI handler polled both ports every
     * frame, so every pad_poll() call in SAUCE/ is commented out and this is
     * the only place the game ever reads a button.
     *
     * Leaving these out of the SA-1 branch is what made the port look dead in
     * game. The level select worked, because it calls pad_poll() itself, so
     * menus responded and gameplay did not - the player could never jump, died
     * on the first obstacle, restarted, and did it again forever.
     *
     * The S-CPU has already latched both ports into the mailbox by now; this
     * only converts them and does the edge detection.
     */
    pad_poll(0);
    pad_poll(1);
#else
    while (HVBJOY & 0x80)
        ;
    while (!(HVBJOY & 0x80))
        ;
    /*
     * The scroll registers first, and in vblank, because the SNES applies them
     * the moment they are written. The game sets the scroll from the middle of
     * its frame; doing it there tears the picture along whatever scanline the
     * write lands on. See shim_scroll_apply() in shim_misc.c.
     */
    shim_scroll_apply();
    if (PAL_UPDATE)
        cgram_flush();
    vram_flush_now();           /* in vblank: write unconditionally */
    oam_flush();
    /* Last, and budgeted: a CHR bank is 4KB and would eat vblank whole. The
       column, OAM and palette transfers above have deadlines; this one only
       has to finish eventually. */
    chr_flush(CHR_BUDGET);

    /*
     * Read the pads HERE, because that is where the NES reads them: neslib's
     * NMI handler polls both ports every frame (LIB/asm/neslib.s), which is why
     * every pad_poll() call in SAUCE/ is commented out. There is no NMI handler
     * in this port, so without this the game never sees a button and the player
     * cannot be controlled at all.
     *
     * After the DMAs, not before: the SNES auto-joypad read takes about three
     * scanlines from the start of vblank, and pad_poll() spins until it
     * finishes. Polling first would burn the vblank budget the transfers need.
     */
    pad_poll(0);
    pad_poll(1);

    /*
     * The frame's audio, LAST. It is a handful of port handshakes with no
     * deadline of its own - the SPC700 plays continuously and only wants the
     * new register image before the next frame - whereas everything above it
     * has to be inside vblank or the hardware drops it (trap 35). Putting it
     * ahead of the transfers would spend their budget on work that does not
     * need it.
     *
     * On the SA-1 build this call is NOT here: it lives in shim_scpu_flush,
     * because $2140-$2143 are S-CPU-only and this branch runs on the SA-1.
     */
    spc_frame_flush();
#endif

    drawing_frame++;
}

#ifdef SHIM_SA1
/*
 * Everything ppu_wait_nmi used to do after the vblank poll, called by the
 * S-CPU once per frame from scpu_frame in src/sa1_boot.s.
 *
 * This is the SAME code the HiROM ROM runs, not a reimplementation, and that is
 * deliberate: these five routines are the ones every existing verifier covers,
 * and a hand-written assembly copy would be a second thing to keep correct
 * while looking identical from the outside.
 *
 * It works because the S-CPU can read BW-RAM linearly at $40:xxxx - measured,
 * not assumed - so `oam_buf`, `PAL_BUF`, the VRAM queues, the column sources
 * and the CHR descriptors are all reachable exactly where the SA-1 left them,
 * with no relocation into I-RAM and no window juggling.
 *
 * The two processors never run this concurrently with anything that touches the
 * same state: the SA-1 is blocked in ppu_wait_nmi's spin for the whole of it,
 * and that spin reads one volatile byte of I-RAM and nothing else. They do not
 * even share the compiler's scratch - src/sa1_boot.s gives the S-CPU its own
 * direct page and stack.
 */
/* The game's ppu_on/ppu_off/brightness landed in the mailbox; this is where
   they reach the hardware. Separate from the flush because it has to happen
   BEFORE any bulk transfer - see shim_scpu_frame. */
void shim_scpu_screen(void)
{
    INIDISP = SHIM_MB_S->inidisp;
    TM = SHIM_MB_S->tm;
}

void shim_scpu_flush(void)
{
    shim_scroll_apply();
    if (PAL_UPDATE)
        cgram_flush();
    vram_flush_now();
    oam_flush();
    /*
     * The budget exists to protect vblank, and in forced blank there is no
     * vblank to protect - the whole frame is writable. flush_chr_now() used to
     * do this at level init, but it runs on the SA-1, where it moves nothing,
     * so without this a level's CHR arrived 2KB a frame over several frames and
     * the first frames drew from tiles that were not there yet.
     */
    chr_flush((SHIM_MB_S->inidisp & 0x80) ? 0xFFFF : CHR_BUDGET);

    /*
     * Snapshot the shared audio producer state while the SA-1 is still blocked.
     * src/sa1_boot.s acknowledges the video frame next, then performs the
     * S-CPU-only SPC port handshakes from this stable copy. Audio I/O does not
     * require vblank and no longer delays the SA-1's next game frame.
     */
    spc_frame_latch();
}
#endif

/* Debug aids with no SNES equivalent; the game only calls them under a flag. */
void gray_line(void) { }
void color_emphasis(uint8_t color) { (void)color; }
