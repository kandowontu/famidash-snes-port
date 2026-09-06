/* Does Calypsi-compiled C run on the SA-1, with its data in BW-RAM?
 *
 * Everything measured so far was hand-written assembly. The port is 34KB of C
 * globals and a compiler runtime, so before any of it moves, four things have
 * to work on the SA-1 with the memory map in src/snes-SA1-c.scm:
 *
 *   1. the stack, which lives in the BW-RAM window - if BW-RAM writes were
 *      still protected the first call would return into nothing;
 *   2. zero-initialised globals in BW-RAM (`far`), which is where the bulk of
 *      the port's state has to go;
 *   3. INITIALISED globals, which cstartup copies from a ROM image at boot -
 *      the port has many, and this is the step that would fail silently if the
 *      data_init_table were not reachable in the new map;
 *   4. constants read from ROM, which is how every level and table is read.
 *
 * Each answer is a checksum with a value known ahead of time, written to the
 * shared I-RAM block for tools/verify_sa1_c.lua to read. Checksums rather than
 * flags because a flag only proves the code ran, not that it computed anything:
 * an unwritten BW-RAM array reads back as a constant and would still let a
 * "did it run" test pass.
 */

#include <stdint.h>

/* The mailbox. I-RAM is the only memory both processors reach cheaply, and it
 * is addressed numerically from the S-CPU's assembly and from Lua, so it is a
 * fixed address rather than a linker-placed symbol. */
#define SHARED ((volatile uint8_t *)0x000300)

/* (2) zero-initialised: lands in BW-RAM. 1KB, enough that a partial or aliased
 * mapping shows up as a wrong sum rather than working by luck. */
static uint16_t bss_arr[512];

/* (3) initialised: the values live in ROM and cstartup copies them down. */
static uint16_t init_arr[8] = { 11, 22, 33, 44, 55, 66, 77, 88 };

/* (4) const: stays in ROM and is read in place. */
static const uint16_t rom_tab[8] = { 100, 200, 300, 400, 500, 600, 700, 800 };

/* Deliberately not static and not inlined away: a real call, so the return
 * address has to survive a push and a pull through BW-RAM. */
uint16_t sum_of(const uint16_t *p, uint16_t n)
{
  uint16_t s = 0;
  while (n--) s += *p++;
  return s;
}

int main(void)
{
  uint16_t i;

  for (i = 0; i < 512; i++) bss_arr[i] = i * 3;
  /* 3 * (511*512/2) = 392448, low 16 bits = 0x5D80 */
  SHARED[0] = (uint8_t)sum_of(bss_arr, 512);
  SHARED[1] = (uint8_t)(sum_of(bss_arr, 512) >> 8);

  SHARED[2] = (uint8_t)sum_of(init_arr, 8);           /* 396 -> 0x8C */
  SHARED[3] = (uint8_t)(sum_of(init_arr, 8) >> 8);    /* 0x01 */

  SHARED[4] = (uint8_t)sum_of(rom_tab, 8);            /* 3600 -> 0x10 */
  SHARED[5] = (uint8_t)(sum_of(rom_tab, 8) >> 8);     /* 0x0E */

  SHARED[6] = 0xC5;                                   /* all four finished */

  for (;;) { }
}
