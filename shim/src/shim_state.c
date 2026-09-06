/*
 * shim_state.c - the globals that live in the NES library rather than in the
 * game, so famidash.h declares them extern and something else has to define
 * them. On the NES that "something else" is LIB/asm; here it is this file.
 *
 * These carry no SNES-specific behaviour on their own - they are storage. The
 * code that gives them meaning is in shim_ppu.c and shim_engine.c.
 */

#include <stdint.h>
#include "arr_macros.h"
#include "neslib.h"
#include "nesdoug.h"
#include "mapper.h"
#include "nesdash.h"
#include "defines/space_defines.h"
#include "mouse.h"

/* --- cc65 scratch ------------------------------------------------------- */
/*
 * The game uses these as named temporaries across statements, the way it uses
 * tmp1..tmp9. On the NES they were zero page; here they are ordinary globals.
 */
uint16_t cc65_ptr1;
uint16_t cc65_ptr2;
uint8_t cc65_tmp1;
uint8_t cc65_tmp2;

/* --- palette ------------------------------------------------------------ */
/*
 * PAL_BUF_RAW holds NES palette indices exactly as the game writes them;
 * PAL_BUF holds the 15-bit BGR words actually sent to CGRAM. Keeping the split
 * is what lets all 72 pal_col() call sites stay unchanged (see nesdash.h).
 */
uint8_t PAL_UPDATE;
uint8_t PAL_BUF_RAW[32];
uint16_t PAL_BUF[32];

/* --- VRAM update buffer ------------------------------------------------- */
/* Set while a frame's VRAM writes are pending; see shim_ppu.c. */
volatile unsigned char VRAM_UPDATE;

/* --- scroll ------------------------------------------------------------- */
/*
 * seam_scroll_y and old_draw_scroll_y are part of the NES two-nametable seam
 * bookkeeping. They stay because the collision map is addressed in the same
 * 240-pixel room units (docs/HANDOFF.md trap 23), not because the SNES needs a
 * seam.
 */
uint16_t seam_scroll_y;
uint16_t old_draw_scroll_y;
uint8_t parallax_scroll_column;
uint8_t parallax_scroll_column_start;

/* --- frame / timing ----------------------------------------------------- */
unsigned char drawing_frame;

/*
 * 0 = NTSC. The SNES reports region in $213F bit 4, but this build targets
 * 60Hz, and framerate=1 is the 60Hz physics table set (see M1_4_LINKED_ROM.md).
 */
uint8_t trueFramerate;

/* --- misc --------------------------------------------------------------- */
volatile uint8_t hexToDecOutputBuffer[5];

/* --- input -------------------------------------------------------------- */
/*
 * The SNES mouse exists and speaks a different protocol from the Famicom one,
 * but nothing reads this yet: pad_poll() in shim_core.c leaves `connected`
 * clear, so every `mouse.status_computed & MOUSE_CONNECTED` test fails and the
 * game falls back to the joypad. That is the behaviour we want for now.
 */
Mouse mouse;

/* --- audio -------------------------------------------------------------- */
/*
 * Both ROMs get these symbols from generated famistudio_ram.s.  The linker
 * places that section at S-CPU WRAM $1E00 for HiROM and shared SA-1 I-RAM
 * $0700 for the accelerator build, so practice-mode memcpy and the sequencer
 * operate on the exact same 172 bytes on either CPU.
 */
