/* The S-CPU <-> SA-1 mailbox.
 *
 * I-RAM is the only memory both processors reach cheaply - the SA-1 cannot see
 * $7E/$7F WRAM at all, and the S-CPU reaches BW-RAM only through an 8KB window -
 * so everything the two have to agree on lives here, in the 2KB at $0000-$07FF.
 * The direct page takes the first 256 bytes, so the mailbox starts at $0100.
 *
 * A FIXED ADDRESS, not a linker-placed section, on purpose: the S-CPU's half is
 * assembly (src/sa1_boot.s) and addresses these bytes numerically, and the Lua
 * verifiers read them the same way. A symbol that moved when something was
 * added would silently desynchronise the three.
 *
 * WHY THERE IS A SEQUENCE NUMBER RATHER THAN A FLAG.
 *
 * The port has no frame pacing on the SA-1 at all. ppu_wait_nmi() polls HVBJOY,
 * which for the SA-1 is open bus; open bus varies, so both of its wait loops
 * fall straight through and the game free-runs. So this is not a lock being
 * added to an existing rhythm - it IS the rhythm, and it has to be one that
 * cannot lose a frame or run ahead:
 *
 *   the SA-1 finishes a frame, increments `sa1_seq`, and spins until `scpu_seq`
 *   matches. The S-CPU, once per vblank, pushes whatever the buffers hold and
 *   copies `sa1_seq` into `scpu_seq`.
 *
 * A single "ready" flag would work only if the S-CPU always saw it; a counter
 * survives the S-CPU missing a vblank, because the SA-1 waits for equality
 * rather than for an edge. Both are single-byte writes, which the 65816 makes
 * atomic, so no other interlock is needed.
 */

#ifndef SHIM_SA1_H
#define SHIM_SA1_H

#include <stdint.h>

/*
 * THE TWO PROCESSORS SEE I-RAM AT DIFFERENT ADDRESSES, and this file is
 * compiled once for both. The SA-1 has I-RAM at $0000-$07FF (and again at
 * $3000-$37FF); the S-CPU has it ONLY at $3000-$37FF.
 *
 * So the mailbox has two names for one place. Using the wrong one does not
 * fault - from the S-CPU, $0100 is WRAM, a perfectly valid address holding
 * something else entirely - so the failure is silent and looks like the other
 * processor never wrote anything.
 *
 * SHIM_MB    for code that runs on the SA-1: the game, pad_poll, ppu_wait_nmi.
 * SHIM_MB_S  for code that runs on the S-CPU: shim_scpu_flush and nothing else.
 */
#define SHIM_MAILBOX   0x000100     /* as the SA-1 sees it */
#define SHIM_MAILBOX_S 0x003100     /* as the S-CPU sees it */

typedef struct {
    volatile uint8_t sa1_seq;   /* SA-1 -> S-CPU: a frame is ready to push */
    volatile uint8_t scpu_seq;  /* S-CPU -> SA-1: pushed it; carry on */

    /* The pads, read by the S-CPU because the SA-1 cannot reach $4218. The
     * game reads them every frame through neslib's pad functions, so without
     * this the player cannot be controlled at all. */
    volatile uint16_t pad[2];

    /* INIDISP and TM, shadowed. The game turns the screen on and off from its
     * own logic - ppu_on_bg, ppu_off, ppu_mask, the brightness fade - and every
     * one of those is a PPU register write that does nothing on the SA-1. The
     * S-CPU applies these two at the top of every flush, so the game keeps
     * control of the screen without knowing which processor it is on. */
    volatile uint8_t inidisp;
    volatile uint8_t tm;

    /* A request channel, for whole routines that only the S-CPU can run.
     *
     * Some of the port's PPU work is not a per-frame buffer flush but a one-off
     * burst - bringing the PPU up, swapping the level tileset for the menu font
     * and back - done with direct VRAM and CGRAM writes from the game's own
     * control flow. None of it has any effect on the SA-1. Rather than
     * restructure each into a queue, the SA-1 names the routine and waits.
     *
     * The SA-1 writes `req` and spins until `ack` equals it; the S-CPU runs the
     * routine inside its vblank and echoes. `ack` starts equal to `req` (both
     * zero) so an unasked request is never pending.
     *
     * The first version of this was a boot_req/boot_ack pair tested with
     * `!boot_ack`, which failed because I-RAM IS NOT ZEROED AT POWER-ON: it
     * came up as $86, the test read false, and the PPU was never initialised
     * while every other part of the port worked. src/sa1_boot.s clears the
     * mailbox now, and equality is used rather than truthiness. */
    volatile uint8_t req;
    volatile uint8_t ack;
} shim_mailbox_t;

/* Request opcodes. 0 is "nothing asked", so the cleared mailbox is idle. */
#define SHIM_REQ_VIDEO_INIT 1   /* bring the PPU up; needs BSS already zeroed */
#define SHIM_REQ_MENU_ENTER 2   /* menu font, palette, scroll, tilemap clear */
#define SHIM_REQ_MENU_DRAW  3   /* the static labels and the first row transfer */
#define SHIM_REQ_MENU_EXIT  4   /* level tileset back, and all of it at once */
#define SHIM_REQ_VRAM_FLUSH 5   /* the VRAM and column queues, right now */
#define SHIM_REQ_CHR_NOW    6   /* the whole CHR queue, unbudgeted */
#define SHIM_REQ_SPC_BOOT   7   /* upload the SPC700 driver; $2140 is S-CPU only */
#define SHIM_REQ_SPC_PREPARE 8  /* load one song's BRR kit while forced blank */
#define SHIM_REQ_END_ENTER  9   /* upload/draw the native completion screen */
#define SHIM_REQ_END_LEAVE 10   /* restore the selected level's BG tiles */
#define SHIM_REQ_MENU_PAL  11   /* exact Famidash menu CGRAM */
#define SHIM_REQ_MENU_P0L  12   /* page 0, first 1 KB */
#define SHIM_REQ_MENU_P0H  13   /* page 0, second 1 KB */
#define SHIM_REQ_MENU_P1L  14   /* page 1, first 1 KB */
#define SHIM_REQ_MENU_P1H  15   /* page 1, second 1 KB */
#define SHIM_REQ_MENU_FACE 16   /* normal/demon difficulty CHR bank */

#define SHIM_MB   ((shim_mailbox_t *)SHIM_MAILBOX)
#define SHIM_MB_S ((shim_mailbox_t *)SHIM_MAILBOX_S)


#ifdef SHIM_SA1
/*
 * The S-CPU's side of the split, declared here so both translation units see a
 * prototype. Without one the compiler assumes a NEAR call, and with
 * --code-model large that is a jsr to a function that is not in the caller's
 * bank - which does not fail at link time and jumps somewhere arbitrary.
 */
void shim_scpu_frame(void);      /* the whole per-frame job */
void shim_scpu_screen(void);     /* INIDISP and TM, from the shadow */
void shim_scpu_flush(void);      /* scroll, CGRAM, VRAM, OAM, CHR */
void shim_scpu_vram_flush(void); /* the VRAM and column queues */
void shim_scpu_chr_now(void);    /* the CHR queue, unbudgeted */

/*
 * Ask the S-CPU for a routine only it can run, and wait until it has.
 *
 * The game calls the flush entry points directly - flush_vram_update2 after
 * building the first screen, flush_chr_now after a bank switch - and expects
 * the queue to be empty when they return. Run on the SA-1 they emptied it
 * without moving a byte, so the level's whole first screen was discarded and
 * the background never appeared. They become requests instead, which keeps
 * both halves of that contract.
 */
static void shim_request(uint8_t op)
{
    SHIM_MB->req = op;
    while (SHIM_MB->ack != op)
        ;
}
#endif

#endif
