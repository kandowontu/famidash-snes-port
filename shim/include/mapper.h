/*
 * mapper.h - SNES shim. Mirrors LIB/headers/mapper.h.
 *
 * There is no mapper on SNES.
 *
 *   PRG banking   -> gone; 65816 long addressing reaches all 8MB
 *   CHR banking   -> VRAM residency management; the shim DMAs tiles in during
 *                    vblank instead of swapping an 8KB aperture
 *   scanline IRQ  -> HDMA
 *
 * The IRQ table was a little bytecode interpreted by the MMC3 IRQ handler.
 * Every opcode maps onto HDMA, which is both a better fit and free of CPU
 * cost, so set_irq_ptr()/write_irq_table()/edit_irq_table() keep their
 * signatures and the shim translates the table into HDMA tables.
 * See scope doc section 4.8.
 */

#ifndef MAPPER_H
#define MAPPER_H

#include <stdint.h>

/* PRG banking: no-ops. Kept so call sites compile unchanged. */
void mmc3_set_prg_bank_0(uint8_t bank);
void mmc3_set_prg_bank_1(uint8_t bank);

/* CHR banking: requests for a tileset to be resident in VRAM. */
void mmc3_set_2kb_chr_bank_0(uint8_t bank);
void mmc3_set_2kb_chr_bank_1(uint8_t bank);
void mmc3_set_1kb_chr_bank_0(uint8_t bank);
void mmc3_set_1kb_chr_bank_1(uint8_t bank);
void mmc3_set_1kb_chr_bank_2(uint8_t bank);
void mmc3_set_1kb_chr_bank_3(uint8_t bank);
void mmc3_set_8kb_chr(uint8_t bank);

/* --- raster effects ----------------------------------------------------- */
extern uint8_t irqTable[32];
extern uint8_t irqTableIdx;

void mmc3_disable_irq(void);
void set_irq_ptr(const uint8_t *address);
void write_irq_table(const uint8_t *data);
void edit_irq_table(uint8_t byte, uint8_t offset);

/* HDMA has no equivalent race, so this is always "safe to edit". */
uint8_t is_irq_done(void);

#define irqtable_ppuctrl   0xf0
#define irqtable_ppustatus 0xf1
#define irqtable_hscroll   0xf5
#define irqtable_ppuaddr   0xf6
#define irqtable_chr0      0xf7
#define irqtable_chr1      0xf8
#define irqtable_chr2      0xf9
#define irqtable_chr3      0xfa
#define irqtable_chr4      0xfb
#define irqtable_chr5      0xfc
#define irqtable_wait      0xfd
#define irqtable_timedwait 0xfe
#define irqtable_end       0xff

#endif /* MAPPER_H */
