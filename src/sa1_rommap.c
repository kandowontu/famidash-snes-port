/* Where does the SA-1 see ROM, when there is 2MB of it?
 *
 * The port is a 1.9MB HiROM image in banks $C0-$DC. An SA-1 cartridge does not
 * map ROM that way: there is a bank controller (the "Super MMC", registers
 * $2220-$2223) between the processors and the ROM, and each of its four
 * registers points a region of the address space at a 1MB slice. Which region,
 * and how the $C0-$FF area behaves, decides the entire ROM layout - where the
 * levels go, where the CHR goes, and whether a level can be read through one
 * pointer the way it is today.
 *
 * Rather than trust a memory of the documentation, this reads it off the chip.
 * tools/pack_lorom.py --stamp writes each 32KB block's own index at +$4000
 * inside it, so reading one address and getting back "block 37" says exactly
 * which part of the ROM answered. Every candidate address is probed from the
 * SA-1 and from nowhere else, because it is the SA-1's view that is in
 * question.
 *
 * The Super MMC registers are left at their reset values on purpose. That is
 * the state a cartridge powers up in, and if the whole 2MB is reachable
 * without touching them, the port never has to bank-switch at all.
 */

#include <stdint.h>

#define SHARED ((volatile uint8_t *)0x000300)

/* $8000 in the LoROM-shaped banks, and both halves of the HiROM-shaped ones.
 * The stamp lives at +$4000 in each 32KB block, so a LoROM bank is probed at
 * $C000 and a HiROM bank at $4000 and $C000. */
static const uint32_t probes[] = {
  /* LoROM-shaped, the region CXB and DXB control */
  0x00C000, 0x08C000, 0x10C000, 0x18C000,
  0x20C000, 0x28C000, 0x30C000, 0x38C000,
  /* ...and its $80-$BF mirror, the region EXB and FXB control */
  0x80C000, 0x88C000, 0x90C000, 0x98C000,
  0xA0C000, 0xA8C000, 0xB0C000, 0xB8C000,
  /* HiROM-shaped: the part that would have to hold 1.9MB in one piece */
  0xC04000, 0xC0C000, 0xC44000, 0xC84000, 0xCC4000,
  0xD04000, 0xD44000, 0xD84000, 0xDC4000,
  0xE04000, 0xE84000, 0xF04000, 0xF84000,
};

#define NPROBES (sizeof(probes) / sizeof(probes[0]))

int main(void)
{
  uint16_t i;

  for (i = 0; i < NPROBES; i++) {
    const uint8_t *p = (const uint8_t *)probes[i];
    /* Two bytes: the block index and a $B0 tag. Without the tag an unmapped
     * address reading as open bus could be mistaken for a real block. */
    SHARED[8 + i * 2] = p[0];
    SHARED[9 + i * 2] = p[1];
  }

  SHARED[6] = 0xC5;
  for (;;) { }
}
