/*
 * shim_core.c - SNES implementations of the hardware API the gameplay core needs.
 *
 * These are the eight symbols the linker reports as undefined when main()
 * drives cube_movement() + x_movement(). Semantics are ported from the NES
 * originals (LIB/asm/nesdash.s, LIB/asm/nesdoug.s) rather than reinvented,
 * because the gameplay depends on their exact behaviour - in particular the
 * 240-pixel "room" wrap, which the collision map is indexed by.
 */

#include <stdint.h>
#include "shim_sa1.h"
#include "arr_macros.h"
#include "neslib.h"
#include "nesdoug.h"
#include "mapper.h"
#include "nesdash.h"

/*
 * Game globals. famidash.h *defines* these rather than declaring them (it is
 * written for a unity build), so it cannot be included from a second
 * translation unit. Declared extern here instead; types match famidash.h.
 */
extern uint8_t currplayer_mini;      /* famidash.h:113 */
extern uint8_t currplayer_gravity;   /* famidash.h:118 */
extern uint8_t currplayer_table_idx; /* famidash.h:127 */
extern uint8_t collision;            /* famidash.h:133 */
extern uint8_t temp_x;               /* famidash.h:151 */
extern uint8_t temp_y;               /* famidash.h:152 */
extern uint8_t temp_room;            /* famidash.h:153 */

/* --- globals the game expects ------------------------------------------- */
struct pad joypad2;                 /* joypad2 precedes joypad1, as on NES */
struct pad joypad1;
struct pad *controllingplayer = &joypad1;

uint8_t framerate = 1;              /* 1 = 60Hz; SNES NTSC matches the NES */
uint16_t min_scroll_y;

/*
 * The cc65 register file, as seen by the game. See shim/include/nesdash.h for
 * why __A__ and __AX__ have to overlap, and arr_macros.h for what keeps
 * shim_last_index ("the Y register") in step with the array macros.
 */
union shim_regs shim_reg;
uint8_t shim_last_index;

/* --- SNES registers ----------------------------------------------------- */
#define HVBJOY   (*(volatile uint8_t *)0x4212)
#define JOY1L    (*(volatile uint8_t *)0x4218)
#define JOY1H    (*(volatile uint8_t *)0x4219)
#define JOY2L    (*(volatile uint8_t *)0x421A)
#define JOY2H    (*(volatile uint8_t *)0x421B)

/*
 * SNES auto-joypad layout:
 *   high byte  B Y Select Start Up Down Left Right
 *   low byte   A X L R - - - -
 *
 * Famidash uses the NES 8-button set. Directions, Start and Select map
 * straight across. For the face buttons the SNES bottom button (B) is the
 * natural jump, so NES A accepts SNES B or A, and NES B accepts SNES Y or X.
 */
static uint8_t snes_to_nes_pad(uint8_t hi, uint8_t lo)
{
    uint8_t r = 0;
    if (hi & 0x01) r |= PAD_RIGHT;
    if (hi & 0x02) r |= PAD_LEFT;
    if (hi & 0x04) r |= PAD_DOWN;
    if (hi & 0x08) r |= PAD_UP;
    if (hi & 0x10) r |= PAD_START;
    if (hi & 0x20) r |= PAD_SELECT;
    if ((hi & 0x80) || (lo & 0x80)) r |= PAD_A;     /* SNES B or A */
    if ((hi & 0x40) || (lo & 0x40)) r |= PAD_B;     /* SNES Y or X */
    return r;
}

static void pad_update(struct pad *p, uint8_t hi, uint8_t lo)
{
    uint8_t now = snes_to_nes_pad(hi, lo);
    uint8_t was = p->hold;
    p->hold = now;
    p->press = (uint8_t)(now & ~was);
    p->release = (uint8_t)(was & ~now);
}

uint8_t pad_poll(uint8_t pad)
{
#ifdef SHIM_SA1
    /*
     * The SA-1 cannot reach $4218 - the pads, like everything else in
     * $4200-$43FF, are the S-CPU's. It latches both ports into the mailbox once
     * per vblank (scpu_frame in src/sa1_boot.s) and this reads them back, so the
     * edge detection below still happens exactly where the game expects it.
     *
     * No HVBJOY spin here: the S-CPU already waited for the auto-joypad read to
     * finish before storing, and HVBJOY reads as open bus on this side anyway,
     * so the wait would either do nothing or never end.
     */
    uint16_t v = SHIM_MB->pad[pad ? 1 : 0];
    if (pad) {
        pad_update(&joypad2, (uint8_t)(v >> 8), (uint8_t)v);
        return joypad2.hold;
    }
    pad_update(&joypad1, (uint8_t)(v >> 8), (uint8_t)v);
    return joypad1.hold;
#else
    /* Auto-joypad read latches during vblank; bit 0 of HVBJOY is set while
       it is still in progress. */
    while (HVBJOY & 0x01)
        ;
    if (pad) {
        pad_update(&joypad2, JOY2H, JOY2L);
        return joypad2.hold;
    }
    pad_update(&joypad1, JOY1H, JOY1L);
    return joypad1.hold;
#endif
}

/* --- scroll ------------------------------------------------------------- */
/*
 * Ported from __add_scroll_y in LIB/asm/nesdoug.s. The low byte is a pixel
 * offset inside a 240-pixel room and the high byte is the room number, so the
 * wrap is at 0xF0, not 0x100. Both the carry path and the >= 0xF0 path add 16,
 * because on 6502 the carry was already set in each case.
 *
 * This 240 wrap is NOT a NES PPU artifact that the SNES removes - the
 * collision map is addressed in these units, so it stays.
 */
uint16_t add_scroll_y(uint8_t add, uint16_t scroll)
{
    /* 16-bit throughout: `(uint8_t)sum >= 0xF0` narrows to a SIGNED 8-bit
       compare against -16 (docs/HANDOFF.md trap 56), which is how the same
       shape broke sub_scroll_y and stopped the camera scrolling up. */
    uint16_t hi = (uint16_t)((scroll >> 8) & 0xFF);
    uint16_t sum = (uint16_t)(scroll & 0xFF) + add;
    uint16_t lo;

    if (sum > 0xFF || (sum & 0xFF) >= 0xF0) {
        lo = (uint16_t)((sum + 16) & 0xFF);
        hi = (uint16_t)((hi + 1) & 0xFF);
    } else {
        lo = (uint16_t)(sum & 0xFF);
    }
    return (uint16_t)((hi << 8) | lo);
}

/* --- physics table index ------------------------------------------------ */
/*
 * Ported from _update_currplayer_table_idx in LIB/asm/nesdash.s:
 *   idx = (framerate << 2) | (mini << 1) | (gravity >> 7)
 * Note it uses only bit 7 of currplayer_gravity, not the whole byte.
 */
void update_currplayer_table_idx(void)
{
    currplayer_table_idx = (uint8_t)(((framerate & 1) << 2)
                                     | ((currplayer_mini & 1) << 1)
                                     | ((currplayer_gravity & 0x80) >> 7));
}

/* --- background collision ---------------------------------------------- */
/*
 * Collision map: 4 pages of 256 bytes, one 16x15-tile page per 240px room.
 * On the NES this lived in cartridge PRG-RAM at $6000-$63FF; here it is just
 * WRAM. Ported from _bg_collision_sub in LIB/asm/nesdash.s.
 */
uint8_t collMap[4][256];

extern const uint8_t metatiles_coll[];

char bg_collision_sub(void)
{
    uint8_t index, tile;

    if (temp_y >= 0xF0) {
        collision = 0;
        return 0;
    }
    index = (uint8_t)((temp_x >> 4) | (temp_y & 0xF0));
    tile = collMap[temp_room & 3][index];
    collision = metatiles_coll[tile];
    return (char)collision;
}

/* --- banking ------------------------------------------------------------ */
/* No mapper on SNES; 65816 long addressing reaches the whole ROM. */
void mmc3_set_prg_bank_1(uint8_t bank) { (void)bank; }
