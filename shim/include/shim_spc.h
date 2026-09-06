/*
 * The SPC700 audio driver, from the S-CPU side. See shim/src/shim_spc.c.
 *
 * These prototypes are not optional. Under --code-model large a call to an
 * undeclared function is assumed NEAR, so the compiler emits a `jsr` to a
 * function that lives in another bank - and there is no link error, it simply
 * jumps somewhere arbitrary (docs/HANDOFF.md trap 122).
 */
#ifndef SHIM_SPC_H
#define SHIM_SPC_H

#include <stdint.h>

/* Upload the driver to ARAM and wait for it to answer. Call once, at boot. */
void spc_boot(void);

/* Load the sampled instruments used by one song while gameplay is stopped. */
void spc_prepare_song(uint8_t song);

/* Snapshot the SA-1's shared image before releasing its frame buffers. */
void spc_frame_latch(void);

/* Send the latched APU register image. Call once a frame, from the S-CPU. */
void spc_frame_flush(void);

/* Every voice to zero volume immediately. */
void spc_silence(void);

/* Zero until the driver has answered, and zero again if it ever stops. */
extern uint8_t spc_alive;

/* Shared SA-1 -> S-CPU argument for SHIM_REQ_SPC_PREPARE. */
extern volatile uint8_t spc_requested_song;

/*
 * The eleven APU register bytes for this frame, in FamiStudio's own
 * output-buffer order - this IS famistudio_output_buf, and the ported
 * sequencer writes it exactly where the 6502 one does.
 *
 *   0 PL1_VOL  1 PL1_LO  2 PL1_HI   3 PL2_VOL  4 PL2_LO  5 PL2_HI
 *   6 TRI_LINEAR  7 TRI_LO  8 TRI_HI   9 NOISE_VOL  10 NOISE_LO
 */
extern uint8_t famistudio_output_buf[];

#endif
