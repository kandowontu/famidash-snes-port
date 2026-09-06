/*
 * nesdoug.h - SNES shim. Mirrors LIB/headers/nesdoug.h.
 *
 * The VRAM buffer keeps the original byte-stream format and API; only the
 * vblank-time consumer changes, writing 16-bit tilemap words to $2118/$2119
 * (or DMAing them) instead of bytes to $2007. See scope doc section 4.3.
 */

#ifndef NESDOUG_H
#define NESDOUG_H

#include <stdint.h>

void set_vram_buffer(void);
void clear_vram_buffer(void);
void flush_vram_update2(void);

void one_vram_buffer(uint8_t data, uint16_t ppu_address);
void multi_vram_buffer_horz(const void *data, uint8_t len, uint16_t ppu_address);
void multi_vram_buffer_vert(const void *data, uint8_t len, uint16_t ppu_address);

uint8_t get_frame_count(void);
uint8_t check_collision(void);

void pal_fade_to(uint8_t from, uint8_t to);

void set_scroll_x(uint16_t x);
void set_scroll_y(uint16_t y);
uint16_t add_scroll_y(uint8_t add, uint16_t scroll);
uint16_t sub_scroll_y(uint8_t sub, uint16_t scroll);
uint16_t sub_scroll_y_ext(uint16_t sub, uint16_t scroll);

uint16_t get_ppu_addr(uint8_t nt, uint8_t x, uint8_t y);

/*
 * get_at_addr() is intentionally absent.
 *
 * The SNES has no attribute table - palette lives in the tilemap entry - so
 * every attribute-address computation is dead code. Leaving the declaration
 * out turns any surviving use into a compile error rather than a silent
 * garbage VRAM write. See scope doc section 3 and section 7 item 1.
 */

void xy_split(uint16_t x, uint16_t y);
void gray_line(void);
void seed_rng(void);

/*
 * color_emphasis() has no SNES hardware equivalent. The tint is applied when
 * PAL_BUF_RAW is converted to CGRAM, so these keep their values and meaning.
 */
void color_emphasis(uint8_t color);

#define COL_EMP_GREYDARK   0xe1
#define COL_EMP_GREYPURPLE 0xA1
#define COL_EMP_GREYCYAN   0xC1
#define COL_EMP_GREYYELLOW 0x61
#define COL_EMP_GREYBLUE   0x81
#define COL_EMP_GREYGREEN  0x41
#define COL_EMP_GREYRED    0x21
#define COL_EMP_PURPLE     0xA0
#define COL_EMP_CYAN       0xC0
#define COL_EMP_YELLOW     0x60
#define COL_EMP_BLUE       0x80
#define COL_EMP_GREEN      0x40
#define COL_EMP_RED        0x20
#define COL_EMP_NORMAL     0x00
#define COL_EMP_DARK       0xe0
#define COL_EMP_GREY       0x01

#define POKE(addr, val) (*(volatile uint8_t *)(addr) = (val))
#define PEEK(addr)      (*(volatile uint8_t *)(addr))

#endif /* NESDOUG_H */
