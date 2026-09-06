/*
 * nesdash.h - SNES shim. Mirrors LIB/headers/nesdash.h.
 *
 * The original is where most of the cc65 dialect lives: pseudo-register
 * argument packing, inline-6502 flag tricks (do_if_*), MMC3 bank plumbing and
 * the crossPRGBankJump family. Almost all of it either becomes a plain call or
 * disappears entirely on 65816:
 *
 *   crossPRGBankJump*  ->  a normal call (JSL); 24-bit addressing sees all ROM
 *   CODE_BANK_PUSH     ->  linker section placement
 *   GET_BANK           ->  bank byte from the linker
 *   do_if_*            ->  ordinary C conditionals
 *
 * Redefining them here is what keeps ~180 call sites in SAUCE/ untouched.
 */

#ifndef NESDASH_H
#define NESDASH_H

#include <stdint.h>
#include "arr_macros.h"

/* --- sprites ------------------------------------------------------------ */
void oam_meta_spr_flipped(uint8_t flip, uint8_t x, uint8_t y, const void *data);

/* --- VRAM buffer helpers ------------------------------------------------ */
void one_vram_buffer_horz_repeat(uint8_t data, uint8_t len, uint16_t ppu_address);
void one_vram_buffer_vert_repeat(uint8_t data, uint8_t len, uint16_t ppu_address);
void draw_padded_text(const void *data, uint8_t len, uint8_t total_len,
                      uint16_t ppu_address);
void printDecimal(uint16_t value, uint8_t digits, uint8_t zeroChr,
                  uint8_t spaceChr, uint16_t ppu_address);

/* --- audio -------------------------------------------------------------- */
void music_play(uint8_t song);
void music_prepare(uint8_t song);
void snes_end_screen_enter(void);
void snes_end_screen_leave(void);
void snes_end_screen_set_selector(uint8_t selection);
void snes_end_screen_reveal_coin(uint8_t coin);
#ifdef SHIM_SA1
/* The S-CPU can read the SA-1's BW-RAM menu flags but cannot acknowledge them
   there. Called by the SA-1 after each completed frame transfer. */
void fami_sa1_frame_ack(void);
#endif
void sfx_play(uint8_t sfx_index, uint8_t channel);
void music_update(void);
void playPCM(uint8_t sample);
void famistudio_sfx_clear_channel(uint8_t channel);
void famistudio_music_stop(void);
void famistudio_music_pause(uint8_t pause);

/* Native SNES completion screen. These wrappers route PPU work to the S-CPU
   on SA-1 and run directly on HiROM. */
void snes_end_screen_enter(void);
void snes_end_screen_leave(void);

/* --- scroll ------------------------------------------------------------- */
/*
 * On the NES this converts between the 240px nametable wrap and linear pixels.
 * SNES tilemaps wrap at 256, so the conversion is the identity and the whole
 * seam-handling class of bug goes away. Kept as a function so call sites and
 * the NES build stay identical.
 */
uint16_t calculate_linear_scroll_y(uint16_t nonlinearScroll);
void cap_scroll_y_at_top(void);
void cap_scroll_y_at_bottom(void);

/* --- misc --------------------------------------------------------------- */
uint16_t hexToDec(uint16_t input);
void update_level_completeness(void);
void increment_attempt_count(void);
void display_attempt_counter(uint8_t zeroChr, uint16_t ppu_address);
void update_currplayer_table_idx(void);

/* --- palette ------------------------------------------------------------ */
/*
 * PAL_BUF_RAW holds NES palette indices exactly as before; PAL_BUF holds the
 * converted 15-bit BGR words that get DMAd to CGRAM. Keeping this split is
 * what lets the 72 pal_col() call sites stay unchanged.
 */
extern uint8_t PAL_UPDATE;
extern uint8_t PAL_BUF_RAW[32];
extern uint16_t PAL_BUF[32];

void pal_col(uint8_t index, uint8_t color);
#define pal_set_update() (++PAL_UPDATE)

extern uint8_t auto_fs_updates;
#define nmi_fs_updates_on()  (++auto_fs_updates)
#define nmi_fs_updates_off() (auto_fs_updates = 0)
#define pal_fade_out()       (pal_fade_to(4, 0))
#define pal_fade_in()        (pal_fade_to(0, 4))

uint8_t colBrightness(uint8_t color, uint8_t brightness);
#define oneShadeDarker(color) colBrightness(color, 3)

/* --- VRAM direct access ------------------------------------------------- */
void vram_adr(uint16_t adr);
void vram_put(uint8_t val);

/* --- banking ------------------------------------------------------------ */
/*
 * No mapper. 65816 long addressing reaches the whole ROM, and the linker
 * decides placement, so these collapse to nothing or to a direct call.
 */
#define GET_BANK(sym) (0)

#define CODE_BANK_PUSH(bank)
#define CODE_BANK_POP()
#define CODE_BANK(bank)

#define crossPRGBankJump0(sym)        (sym())
#define crossPRGBankJump8(sym, args)  (sym(args))
#define crossPRGBankJump16(sym, args) (sym(args))

/* --- 6502 flag tricks, now ordinary C ----------------------------------- */
#define do_if_equal(cond, func)     do { if (cond) func } while (0)
#define do_if_not_equal(cond, func) do { if (!(cond)) func } while (0)
#define do_if_zero(cond, func)      do { if ((cond) == 0) func } while (0)
#define do_if_not_zero(cond, func)  do { if ((cond) != 0) func } while (0)

#define do_if_in_range(val, min, max, func) \
    do { if ((uint8_t)(val) >= (min) && (uint8_t)(val) <= (max)) func } while (0)
#define do_if_not_in_range(val, min, max, func) \
    do { if ((uint8_t)(val) < (min) || (uint8_t)(val) > (max)) func } while (0)

#define swapbyte(a, b) do { uint8_t swaptmp_ = (a); (a) = (b); (b) = swaptmp_; } while (0)

/* Split a 16-bit value into two byte destinations, evaluating it once. */
#define storeWordSeparately(w, low, high)   \
    do {                                    \
        uint16_t sws_ = (uint16_t)(w);      \
        (low) = (uint8_t)sws_;              \
        (high) = (uint8_t)(sws_ >> 8);      \
    } while (0)

#define sec_adc(a, b) ((uint8_t)((a) + (b) + 1))
#define clc_sbc(a, b) ((uint8_t)((a) - (b) - 1))

/* The original is a hand-rolled 4-byte carry chain because cc65 has no usable
   32-bit increment. Calypsi does. */
#define uint32_inc(v) (++(v))

/*
 * Dispatch through a table of function pointers. The original loaded the entry
 * into A:X and used cc65's `callax`; here it is an ordinary indirect call.
 *
 * NOTE this is only usable where the table really holds function pointers.
 * functions/sprite_loading.h used it with a table of *label* addresses, which
 * is a computed goto in disguise - that one is rewritten as a switch in
 * overlay/functions/sprite_loading.h (docs/HANDOFF.md trap 11).
 */
#define jumpInTableWithOffset(tbl, val, off) ((tbl)[(uint8_t)(val) - (off)]())

/* --- cc65 pseudo-registers ---------------------------------------------- */
/*
 * cc65 exposes the 6502 registers as lvalues, and the game uses them to move a
 * value between two statements without naming a variable. `__AX__` is the
 * 16-bit A:X pair with A as the low byte, so writing `__A__` must change the
 * low half of `__AX__` and leave the high half alone - hence the union rather
 * than two independent variables. 65816 is little-endian, so the layout is the
 * same as cc65's.
 *
 * `__asm__` is deliberately NOT defined. Roughly twenty sites in SAUCE/ are
 * hand-written 6502 that no shim can translate; leaving the macro undefined
 * makes each of them a compile error until it is ported into overlay/, rather
 * than something that quietly assembles into the wrong thing. Same reasoning as
 * get_at_addr() (docs/HANDOFF.md trap 25).
 */
union shim_regs {
    uint16_t ax;
    struct { uint8_t a, x; } b;
};
extern union shim_regs shim_reg;

#define __A__  (shim_reg.b.a)
#define __AX__ (shim_reg.ax)

/* The Y register, tracked by the array macros in arr_macros.h. */
#define get_Y (shim_last_index)

/*
 * Statement form, matching the original: the result is delivered in __AX__.
 *   signExtend8to16(idx8_load(sprite_x_offset, tmp4));
 *   cc65_ptr2 = __AX__ + activesprites_realx[index];
 */
#define signExtend8to16(value) \
    ((void)(__AX__ = (uint16_t)(int16_t)(int8_t)(value)))
#define signExtend8to16inline(value) ((uint16_t)(int16_t)(int8_t)(value))

extern uint8_t shiftBy4table[16];
#define shlNibble4(nibble)  ((uint8_t)((nibble) << 4))
#define shlNibble12(nibble) ((uint16_t)((nibble) << 12))

/* Famicom microphone: no SNES equivalent, always reads as not-pressed. */
#define fc_mic_poll() (0)

#endif /* NESDASH_H */
