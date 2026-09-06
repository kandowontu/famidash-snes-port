/*
 * neslib.h - SNES shim.
 *
 * Same names and semantics as LIB/headers/neslib.h so SAUCE/ compiles
 * unchanged; the implementation is SNES hardware. See docs/SNES_PORT_SCOPE.md
 * section 4 for the per-function mapping.
 *
 * The cc65 pseudo-register calling convention (__fastcall__, __A__/__AX__/
 * __EAX__, storeBytesToSreg) does not survive to 65816, so what were macros
 * packing arguments into registers are plain prototypes here. Call sites are
 * unaffected - the argument lists are identical.
 */

#ifndef NESLIB_H
#define NESLIB_H

#include <stdint.h>

/* --- palette ------------------------------------------------------------ */
void pal_all(const void *data);          /* 32 bytes  */
void pal_bg(const void *data);           /* 16 bytes  */
void pal_spr(const void *data);          /* 16 bytes  */
void pal_clear(void);
void pal_bright(uint8_t bright);         /* 0 black, 4 normal, 8 white */

/* --- screen control ----------------------------------------------------- */
void ppu_wait_nmi(void);
void ppu_off(void);
void ppu_on_all(void);
void ppu_on_bg(void);
void ppu_on_spr(void);
void ppu_mask(uint8_t mask);
uint8_t ppu_system(void);                /* 0 = PAL (SNES $213F bit 4) */

/* --- sprites ------------------------------------------------------------ */
/* Not a neslib function: the one-time full clear of the shadow OAM. oam_clear()
   only resets the write cursor now, so the boot path has to call this. */
void oam_init(void);
void oam_clear(void);
void oam_clear_player(void);
void oam_clear_two_players(void);
void oam_spr(uint8_t x, uint8_t y, uint8_t chrnum, uint8_t attr);
void oam_meta_spr(uint8_t x, uint8_t y, const void *data);
void oam_meta_spr_disco(uint8_t x, uint8_t y, const void *data);
void oam_set(uint8_t index);
uint8_t oam_get(void);
void bank_spr(uint8_t n);

/* --- input -------------------------------------------------------------- */
uint8_t pad_poll(uint8_t pad);

/* --- scroll ------------------------------------------------------------- */
void scroll(uint16_t x, uint16_t y);
void split(uint16_t x);
/* Not a neslib function: set_scroll_x/y only latch the values, because writing
   BG1HOFS mid-frame tears the picture. ppu_wait_nmi applies them in vblank,
   which is where the NES's NMI handler wrote $2005. */
void shim_scroll_apply(void);

/* --- rng ---------------------------------------------------------------- */
uint8_t newrand(void);
void set_rand(uint16_t seed);

/* --- VRAM --------------------------------------------------------------- */
void vram_fill(uint8_t n, uint16_t len);
void vram_inc(uint8_t n);
void vram_read(void *dst, uint16_t size);
void vram_write(const void *src, uint16_t size);
void vram_unrle(const void *data);

void memcpy(void *dst, const void *src, uint16_t len);
void memfill(void *dst, uint8_t val, uint16_t len);
void delay(uint8_t frames);

/* --- controller state --------------------------------------------------- */
struct pad {
    union {
        unsigned char hold;
        struct {
            unsigned char right : 1;
            unsigned char left : 1;
            unsigned char down : 1;
            unsigned char up : 1;
            unsigned char start : 1;
            unsigned char select : 1;
            unsigned char b : 1;
            unsigned char a : 1;
        };
    };
    union {
        unsigned char press;
        struct {
            unsigned char press_right : 1;
            unsigned char press_left : 1;
            unsigned char press_down : 1;
            unsigned char press_up : 1;
            unsigned char press_start : 1;
            unsigned char press_select : 1;
            unsigned char press_b : 1;
            unsigned char press_a : 1;
        };
    };
    union {
        unsigned char release;
        struct {
            unsigned char release_right : 1;
            unsigned char release_left : 1;
            unsigned char release_down : 1;
            unsigned char release_up : 1;
            unsigned char release_start : 1;
            unsigned char release_select : 1;
            unsigned char release_b : 1;
            unsigned char release_a : 1;
        };
    };
};

extern struct pad joypad1;
extern struct pad joypad2;
extern struct pad *controllingplayer;

/* SNES pads carry 12 buttons; the 8 the game uses keep their NES names. */
#define PAD_A       0x80
#define PAD_B       0x40
#define PAD_SELECT  0x20
#define PAD_START   0x10
#define PAD_UP      0x08
#define PAD_DOWN    0x04
#define PAD_LEFT    0x02
#define PAD_RIGHT   0x01

/* OAM attribute bits, remapped to SNES layout inside the shim. */
#define OAM_FLIP_V  0x80
#define OAM_FLIP_H  0x40
#define OAM_BEHIND  0x20

#define MAX(x1, x2) ((x1) < (x2) ? (x2) : (x1))
#define MIN(x1, x2) ((x1) < (x2) ? (x1) : (x2))

#define MASK_SPR      0x10
#define MASK_BG       0x08
#define MASK_EDGE_SPR 0x04   /* no SNES equivalent; ignored by the shim */
#define MASK_EDGE_BG  0x02   /* no SNES equivalent; ignored by the shim */

/* Nametable constants are kept so existing address arithmetic still compiles.
   The shim translates $2000-based addresses to SNES tilemap word addresses. */
#define NAMETABLE_A 0x2000
#define NAMETABLE_B 0x2400
#define NAMETABLE_C 0x2800
#define NAMETABLE_D 0x2c00

#ifndef TRUE
#define TRUE  1
#define FALSE 0
#endif

#define NT_UPD_HORZ 0x40
#define NT_UPD_VERT 0x80
#define NT_UPD_EOF  0xff

#define VRAM_OFF(x, y) (((y) << 5) | (x))
#define NTADR_A(x, y)  (NAMETABLE_A | VRAM_OFF(x, y))
#define NTADR_B(x, y)  (NAMETABLE_B | VRAM_OFF(x, y))
#define NTADR_C(x, y)  (NAMETABLE_C | VRAM_OFF(x, y))
#define NTADR_D(x, y)  (NAMETABLE_D | VRAM_OFF(x, y))

#endif /* NESLIB_H */
