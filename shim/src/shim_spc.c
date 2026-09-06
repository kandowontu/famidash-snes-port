/*
 * The audio driver's S-CPU half: get the SPC700 program into ARAM, then feed
 * it one APU register image a frame.
 *
 * WHERE THE SEAM IS. FamiStudio's driver, with FAMISTUDIO_CFG_SFX_SUPPORT on -
 * which this game has on - does not write $4000 while it works. It fills an
 * eleven-byte `famistudio_output_buf` and copies that block to the APU once, at
 * the end of famistudio_update (famistudio_ca65.s:1280 for the aliases,
 * :4435 for the copy). So the port replaces one block copy, not a scattered
 * set of register writes, and those eleven bytes are the entire interface
 * between the sequencer and the sound hardware.
 *
 * THE PRODUCER NOW EXISTS. tools/gen_famistudio.py builds the original 6502
 * sequencer as a 65816 compatibility island and packs all 132 exported songs.
 * tools/verify_music.lua checks that its changing register image arrives here,
 * crosses ARAM byte-for-byte and drives audible S-DSP voices; verify_spc.lua
 * independently injects exact register cases to test the translation below.
 *
 * WHY THE TRANSPORT RUNS ON THE S-CPU. $2140-$2143 are S-CPU-only, like every
 * other register in $2100-$43FF (docs/M2_25_SA1.md). On HiROM the flush is
 * called from ppu_wait_nmi; on SA-1 it is called from shim_scpu_flush once a
 * frame.  The sequencer itself does run on the SA-1 and writes shared I-RAM
 * $0700; this S-CPU half reads the same bytes at the hardware's $3700 mirror.
 */

#include <stdint.h>
#include "famistudio_layout.h"
#include "famistudio_dpcm_meta.h"
#include "famistudio_song_dpcm.h"

#define REG(a) (*(volatile uint8_t *)(a))
#define APUIO0 REG(0x2140)
#define APUIO1 REG(0x2141)
#define APUIO2 REG(0x2142)
#define APUIO3 REG(0x2143)

/*
 * The driver image, verbatim, from tools/gen_spc_image.py.
 *
 * A POINTER VARIABLE, not an `extern const uint8_t spc_image[]`. A pointer is
 * 24 bits here and a direct reference to an assembly symbol compiles to a
 * 16-bit relocation, which the linker rejects for anything above bank 0 - the
 * same shape as trap 28. out/spc_image_meta.c builds the pointer in C so the
 * compiler emits the whole address.
 */
extern const uint8_t *const spc_image;
extern const uint16_t spc_image_len;

#define ARAM_LOAD   0x0200      /* must match gen_spc_image.py */
#define CMD_COMMIT  0xFF
#define CMD_SILENCE 0xFE
#define CMD_DPCM_BEGIN 0xFD
#define CMD_DPCM_DATA  0xFC
#define CMD_DPCM_START 0xFB
#define CMD_DPCM_PLAY  0xFA
#define CMD_DPCM_STOP  0xF9
#define CMD_DPCM_SIZE  0xF8
#define CMD_DPCM_DATA1 0xF7
#define CMD_TONE_KEYON 0xF6
#define READY0      0xBB
#define READY1      0xA5
#define DPCM_ARAM   0x2000
#define DPCM_ARAM_END 0x10000UL
#define DPCM_SAMPLE_SLOTS 64
#define DPCM_STREAM_BYTES_PER_FRAME 32

/*
 * NOTHING HERE SPINS FOREVER.
 *
 * Every wait on the SPC700 is bounded and every one of them can give up. A
 * cartridge with a dead or missing APU is a thing that happens on hardware and
 * on some emulators, and the failure this guards against is not silence - it is
 * a game that hangs at boot with a black screen, which looks exactly like the
 * ROM being broken. If a wait times out, spc_alive goes to zero and every entry
 * point below turns into a no-op for the rest of the run.
 *
 * The bound is in loop iterations rather than in time on purpose: this runs
 * before the frame counter exists and there is no clock to read yet.
 */
#define SPC_TIMEOUT 20000

uint8_t spc_alive;              /* 0 until the driver answers; 0 again if it stops */

/*
 * The APU register image, in FamiStudio's own output-buffer order. The array
 * ALREADY EXISTS - shim_state.c defines it, because the game's own
 * practice-state code saves and restores it (famidash.h:307,
 * practice_famistudio_registers) - so this is the game's buffer and not a
 * parallel one. See the header of spc/famidash_spc.s for what each byte means.
 */
#ifdef SHIM_SA1
#define FS_OUTPUT_BUF \
    ((volatile uint8_t *)FAMISTUDIO_SA1_OUTPUT_SCPU)
#define FS_SHARED_BYTE(offset) \
    (*(volatile uint8_t *)(0x3000u + FAMISTUDIO_SA1_DP_BASE + (offset)))
#define FS_APU_SHADOW \
    ((volatile uint8_t *)(0x3000u + FAMISTUDIO_SA1_DP_BASE \
                          + FAMISTUDIO_APU_SHADOW_OFFSET))
#define FS_DPCM_BANK FS_SHARED_BYTE(FAMISTUDIO_DPCM_BANK_OFFSET)
#define FS_DPCM_SEQ  FS_SHARED_BYTE(FAMISTUDIO_DPCM_SEQ_OFFSET)
#define FS_PHASE_RESET FS_SHARED_BYTE(FAMISTUDIO_PHASE_RESET_OFFSET)
#else
extern uint8_t famistudio_output_buf[];
extern uint8_t famistudio_apu_shadow[];
extern uint8_t famistudio_dpcm_bank;
extern uint8_t famistudio_dpcm_seq;
extern uint8_t famistudio_phase_reset_mask;
#define FS_OUTPUT_BUF famistudio_output_buf
#define FS_APU_SHADOW famistudio_apu_shadow
#define FS_DPCM_BANK famistudio_dpcm_bank
#define FS_DPCM_SEQ famistudio_dpcm_seq
#define FS_PHASE_RESET famistudio_phase_reset_mask
#endif

/* What was sent last frame, so an unchanged frame costs nothing. */
static uint8_t spc_sent[12];
static uint8_t spc_seq;         /* the sequence byte, echoed back as the ack */
static uint8_t spc_primed;      /* has a full image been sent at least once? */
static uint8_t spc_dpcm_seen;   /* last FamiStudio DPCM event sequence */
static uint16_t spc_dpcm_address[DPCM_SAMPLE_SLOTS];
static uint8_t spc_prepared_song;
static uint8_t spc_dynamic_sample;
static uint16_t spc_dynamic_address;
static uint16_t spc_dynamic_capacity;
static const uint8_t *spc_stream_ptr;
static uint16_t spc_stream_left;
static uint8_t spc_stream_sample;
static uint8_t spc_stream_freq;
static uint8_t spc_stream_play;
static uint8_t spc_stream_active;
/* Kept out of spc_frame_flush's stack frame: Calypsi 5.18 miscompiles the
   larger frame at -O1 (caught by scan_stackslots.py). The audio path is
   single-threaded, so persistent scratch is safe here. */
static uint8_t spc_tone_keyon;
static uint8_t spc_old_noise;
static uint8_t spc_new_noise;
/*
 * The SA-1 may begin producing the next frame while the S-CPU talks to the
 * SPC700. Keep that overlap race-free by latching the complete, tiny producer
 * image before the sequence acknowledgement.
 */
static uint8_t spc_frame_image[11];
static uint8_t spc_frame_phase_reset;
static uint8_t spc_frame_dpcm_seq;
static uint8_t spc_frame_dpcm_bank;
static uint8_t spc_frame_apu_10;
static uint8_t spc_frame_apu_11;
static uint8_t spc_frame_apu_12;
static uint8_t spc_frame_apu_13;
static uint8_t spc_frame_apu_15;

/* SA-1 writes this shared BWRAM byte before asking the S-CPU to prepare ARAM. */
volatile uint8_t spc_requested_song;

/*
 * One transaction: two payload bytes at an index, then the sequence byte, then
 * wait for the driver to echo the sequence byte back.
 *
 * THE ORDER OF THE THREE WRITES IS THE PROTOCOL. The driver waits on port 0
 * and reads ports 1-3 only after it changes, so the payload has to be in place
 * first. Writing port 0 first would let the driver read a half-updated payload
 * on a frame where it happened to be looking.
 */
static uint8_t spc_send(uint8_t index, uint8_t v0, uint8_t v1)
{
    uint16_t spin;

    APUIO1 = index;
    APUIO2 = v0;
    APUIO3 = v1;
    spc_seq++;
    APUIO0 = spc_seq;

    for (spin = 0; spin < SPC_TIMEOUT; spin++) {
        if (APUIO0 == spc_seq)
            return 1;
    }
    spc_alive = 0;
    return 0;
}

static const FamiStudioDpcmSample *spc_find_dpcm(uint8_t bank,
                                                 uint8_t start,
                                                 uint8_t length,
                                                 uint8_t initial,
                                                 uint8_t loop,
                                                 uint8_t *sample_index)
{
    uint8_t i;
    const FamiStudioDpcmSample *fallback = 0;
    uint8_t fallback_index = 0;
    for (i = 0; i < famistudio_dpcm_sample_count; i++) {
        const FamiStudioDpcmSample *s = &famistudio_dpcm_samples[i];
        if (s->bank == bank && s->start == start && s->length == length
            && s->loop == loop) {
            if (s->initial == initial) {
                *sample_index = i;
                return s;
            }
            fallback = s;
            fallback_index = i;
        }
    }
    /* FamiStudio's delta-counter effect may override the table's initial DAC
       value. The waveform remains the right original sample; using its normal
       initial value is preferable to dropping the hit entirely. */
    if (fallback)
        *sample_index = fallback_index;
    return fallback;
}

/*
 * Load one complete resident sample. Prepared song kits use a counted bulk
 * mode: after the address and exact byte count, all three payload ports carry
 * BRR. This is still synchronous, but it runs while level_select has already
 * forced the screen blank, never from an instrument's note-trigger frame.
 */
static uint8_t spc_load_dpcm_at(const FamiStudioDpcmSample *sample,
                                uint16_t address)
{
    const uint8_t *p;
    uint16_t left;

    if (sample->bank >= famistudio_dpcm_bank_count)
        return 0;
    p = famistudio_dpcm_brr_banks[sample->bank] + sample->brr_offset;
    left = sample->brr_size;
    if (!spc_send(CMD_DPCM_BEGIN, (uint8_t)address,
                  (uint8_t)(address >> 8)))
        return 0;
    if (!spc_send(CMD_DPCM_SIZE, (uint8_t)left, (uint8_t)(left >> 8)))
        return 0;
    while (left >= 3) {
        uint8_t a = *p++;
        uint8_t b = *p++;
        uint8_t c = *p++;
        if (!spc_send(a, b, c))
            return 0;
        left -= 3;
    }
    if (left == 2) {
        uint8_t a = *p++;
        uint8_t b = *p;
        if (!spc_send(a, b, 0))
            return 0;
    } else if (left && !spc_send(*p, 0, 0)) {
        return 0;
    }
    return 1;
}

/*
 * Place the generated working set for a song in ARAM. 129/132 songs fit in
 * full; the two exceptions reserve the tail for one streamed replacement.
 */
void spc_prepare_song(uint8_t song)
{
    const FamiStudioDpcmKit *kit;
    uint32_t next;
    uint8_t i;

    if (!spc_alive || song >= famistudio_dpcm_kit_count)
        return;
    if (spc_prepared_song == song)
        return;

    kit = &famistudio_dpcm_kits[song];
    spc_send(CMD_DPCM_STOP, 0, 0);
    spc_stream_left = 0;
    spc_stream_play = 0;
    spc_stream_active = 0;
    spc_dynamic_sample = 0xff;
    spc_dynamic_address = 0;
    spc_dynamic_capacity = 0;
    for (i = 0; i < DPCM_SAMPLE_SLOTS; i++)
        spc_dpcm_address[i] = 0;

    next = DPCM_ARAM;
    for (i = 0; i < kit->count; i++) {
        uint8_t sample_index =
            famistudio_dpcm_kit_samples[kit->offset + i];
        const FamiStudioDpcmSample *sample;
        if (sample_index >= famistudio_dpcm_sample_count)
            return;
        sample = &famistudio_dpcm_samples[sample_index];
        if (next + sample->brr_size > DPCM_ARAM_END)
            return;
        if (!spc_load_dpcm_at(sample, (uint16_t)next))
            return;
        spc_dpcm_address[sample_index] = (uint16_t)next;
        next += sample->brr_size;
    }

    /* The generator only sets dynamic_first on an oversized song and has
       already reserved enough space for the largest BRR instrument. */
    if (kit->dynamic_first != 0xff) {
        uint8_t sample_index = kit->dynamic_first;
        const FamiStudioDpcmSample *sample;
        spc_dynamic_address = (uint16_t)next;
        spc_dynamic_capacity = (uint16_t)(DPCM_ARAM_END - next);
        if (sample_index >= famistudio_dpcm_sample_count)
            return;
        sample = &famistudio_dpcm_samples[sample_index];
        if (sample->brr_size > spc_dynamic_capacity)
            return;
        if (!spc_load_dpcm_at(sample, spc_dynamic_address))
            return;
        spc_dpcm_address[sample_index] = spc_dynamic_address;
        spc_dynamic_sample = sample_index;
    }

    spc_dpcm_seen = FS_DPCM_SEQ;
    spc_prepared_song = song;
}

static uint8_t spc_dpcm_play(uint16_t address, uint8_t freq)
{
    if (!spc_send(CMD_DPCM_START, (uint8_t)address,
                  (uint8_t)(address >> 8)))
        return 0;
    return spc_send(CMD_DPCM_PLAY, freq, 0);
}

/*
 * An oversized song can miss its generated hot set. Start a replacement in
 * the reserved tail, then copy only a fixed amount per frame. The note may be
 * late in those two exceptional tracks, but gameplay can never inherit an
 * unbounded multi-kilobyte upload from the audio path again.
 */
static uint8_t spc_dpcm_stream_begin(uint8_t sample_index,
                                     const FamiStudioDpcmSample *sample,
                                     uint8_t freq)
{
    if (!spc_dynamic_address || sample->brr_size > spc_dynamic_capacity)
        return 0;
    if (spc_dynamic_sample != 0xff)
        spc_dpcm_address[spc_dynamic_sample] = 0;
    spc_dynamic_sample = 0xff;
    spc_send(CMD_DPCM_STOP, 0, 0);
    if (!spc_send(CMD_DPCM_BEGIN, (uint8_t)spc_dynamic_address,
                  (uint8_t)(spc_dynamic_address >> 8)))
        return 0;
    spc_stream_ptr =
        famistudio_dpcm_brr_banks[sample->bank] + sample->brr_offset;
    spc_stream_left = sample->brr_size;
    spc_stream_sample = sample_index;
    spc_stream_freq = freq;
    spc_stream_play = 1;
    spc_stream_active = 1;
    return 1;
}

static void spc_dpcm_stream_step(void)
{
    uint16_t budget = DPCM_STREAM_BYTES_PER_FRAME;

    if (!spc_stream_active)
        return;
    while (spc_stream_left && budget) {
        if (spc_stream_left == 1) {
            if (!spc_send(CMD_DPCM_DATA1, *spc_stream_ptr++, 0))
                return;
            spc_stream_left = 0;
            budget--;
        } else {
            uint8_t a = *spc_stream_ptr++;
            uint8_t b = *spc_stream_ptr++;
            if (!spc_send(CMD_DPCM_DATA, a, b))
                return;
            spc_stream_left -= 2;
            budget -= 2;
        }
    }

    if (!spc_stream_left) {
        spc_dynamic_sample = spc_stream_sample;
        spc_dpcm_address[spc_stream_sample] = spc_dynamic_address;
        if (spc_stream_play)
            spc_dpcm_play(spc_dynamic_address, spc_stream_freq);
        spc_stream_play = 0;
        spc_stream_active = 0;
    }
}

static void spc_dpcm_flush(void)
{
    const FamiStudioDpcmSample *sample;
    uint8_t event = spc_frame_dpcm_seq;
    uint8_t bank, freq, loop, sample_index;
    uint16_t address;

    if (event == spc_dpcm_seen)
        return;
    spc_dpcm_seen = event;

    /* $4015 bit 4 is the final start/stop state for this event. */
    if (!(spc_frame_apu_15 & 0x10)) {
        spc_stream_play = 0;
        spc_send(CMD_DPCM_STOP, 0, 0);
        return;
    }

    bank = spc_frame_dpcm_bank;
    freq = spc_frame_apu_10;
    loop = (uint8_t)((freq >> 6) & 1);
    sample = spc_find_dpcm(bank, spc_frame_apu_12,
                          spc_frame_apu_13,
                          (uint8_t)(spc_frame_apu_11 & 0x7f), loop,
                          &sample_index);
    if (!sample) {
        spc_send(CMD_DPCM_STOP, 0, 0);
        return;
    }

    address = spc_dpcm_address[sample_index];
    if (!address) {
        if (spc_stream_active && spc_stream_sample == sample_index) {
            spc_stream_freq = freq;
            spc_stream_play = 1;
            return;
        }
        spc_dpcm_stream_begin(sample_index, sample, freq);
        return;
    }
    spc_stream_play = 0;
    spc_dpcm_play(address, freq);
}

/*
 * The IPL boot loader, from the SNES side.
 *
 * The sequence is the SPC700 IPL ROM's own and is not negotiable; what is worth
 * writing down is the two places it is easy to get wrong. The byte counter in
 * port 0 starts at ZERO for the first byte of a block and simply wraps, and the
 * transfer is ended by writing a ZERO to port 1 with the entry address in ports
 * 2-3 and the counter ADVANCED BY TWO rather than one. A counter that repeats a
 * value the IPL has already acknowledged deadlocks both machines.
 */
static uint8_t spc_upload(void)
{
    const uint8_t *p = spc_image;
    uint16_t len = spc_image_len;
    uint16_t spin;
    uint8_t count;

    /* The IPL announces itself with $BBAA in ports 0 and 1. */
    for (spin = 0; spin < SPC_TIMEOUT; spin++) {
        if (APUIO0 == 0xAA && APUIO1 == 0xBB)
            break;
    }
    if (spin >= SPC_TIMEOUT)
        return 0;

    APUIO1 = 0x01;                      /* non-zero: this is a transfer */
    APUIO2 = (uint8_t)(ARAM_LOAD & 0xFF);
    APUIO3 = (uint8_t)(ARAM_LOAD >> 8);
    APUIO0 = 0xCC;
    for (spin = 0; spin < SPC_TIMEOUT; spin++) {
        if (APUIO0 == 0xCC)
            break;
    }
    if (spin >= SPC_TIMEOUT)
        return 0;

    count = 0;
    while (len--) {
        APUIO1 = *p++;
        APUIO0 = count;
        for (spin = 0; spin < SPC_TIMEOUT; spin++) {
            if (APUIO0 == count)
                break;
        }
        if (spin >= SPC_TIMEOUT)
            return 0;
        count++;
    }

    /* Finish: zero in port 1, the entry point in 2-3, counter + 2. */
    count = (uint8_t)(count + 2);
    APUIO1 = 0x00;
    APUIO2 = (uint8_t)(ARAM_LOAD & 0xFF);
    APUIO3 = (uint8_t)(ARAM_LOAD >> 8);
    APUIO0 = count;

    /*
     * THE DRIVER'S SEQUENCE BASELINE IS THIS BYTE.
     *
     * Port 0 is two registers, one per direction: the driver cannot see what it
     * writes and this side cannot see what it wrote. The driver seeds its
     * comparison by READING port 0, which holds exactly the value written on
     * the line above, so counting on from here is what makes the first frame
     * transaction differ from the boot loader's last write. Starting the
     * sequence at zero would work until the day the image length made the final
     * count zero too, and then hang.
     */
    spc_seq = count;

    for (spin = 0; spin < SPC_TIMEOUT; spin++) {
        if (APUIO0 == READY0 && APUIO1 == READY1)
            return 1;
    }
    return 0;
}

/*
 * Upload the driver and wait for it to come up. Called once, from main(),
 * before the level select - the transfer is a few thousand handshakes and does
 * not want to be competing with a frame.
 */
void spc_boot(void)
{
    uint8_t i;

    spc_alive = 0;
    spc_primed = 0;
    spc_seq = 0;
    spc_prepared_song = 0xff;
    spc_requested_song = 0xff;
    spc_dynamic_sample = 0xff;
    spc_dynamic_address = 0;
    spc_dynamic_capacity = 0;
    spc_stream_left = 0;
    spc_stream_play = 0;
    spc_stream_active = 0;
    spc_dpcm_seen = FS_DPCM_SEQ;
    for (i = 0; i < 11; i++)
        FS_OUTPUT_BUF[i] = 0;
    for (i = 0; i < 12; i++)
        spc_sent[i] = 0;
    for (i = 0; i < DPCM_SAMPLE_SLOTS; i++)
        spc_dpcm_address[i] = 0;

    if (spc_upload())
        spc_alive = 1;
}

/*
 * One frame of audio. Six index transactions and a commit, and only for the
 * pairs that changed - a frame in which nothing moves costs one transaction.
 *
 * The commit is separate from the data so a frame is never half-applied: the
 * driver copies into its buffer as the pairs arrive and only recomputes the
 * DSP when the commit lands. Without it a slow frame could be heard as a note
 * playing at the previous note's pitch.
 */
void spc_frame_latch(void)
{
    uint8_t i;

    for (i = 0; i < 11; i++)
        spc_frame_image[i] = FS_OUTPUT_BUF[i];
    spc_frame_phase_reset = FS_PHASE_RESET;
    spc_frame_dpcm_seq = FS_DPCM_SEQ;
    spc_frame_dpcm_bank = FS_DPCM_BANK;
    spc_frame_apu_10 = FS_APU_SHADOW[0x10];
    spc_frame_apu_11 = FS_APU_SHADOW[0x11];
    spc_frame_apu_12 = FS_APU_SHADOW[0x12];
    spc_frame_apu_13 = FS_APU_SHADOW[0x13];
    spc_frame_apu_15 = FS_APU_SHADOW[0x15];
}

void spc_frame_flush(void)
{
    uint8_t i;
    uint8_t changed = 0;

#ifndef SHIM_SA1
    /* The single-CPU build does not split latch and transport. */
    spc_frame_latch();
#endif
    if (!spc_alive)
        return;
    spc_tone_keyon = (uint8_t)(spc_frame_phase_reset & 0x03);

    /*
     * SRCN is latched by the S-DSP at key-on. Duty-envelope changes and
     * changes between the separately sampled high-rate noise sources need a
     * pulse even though ordinary pitch and volume updates do not. Explicit
     * $53 phase-reset effects use the same command.
     */
    if (!spc_primed) {
        /* The driver keyed on before receiving its first register image. */
        spc_tone_keyon |= 0x0b;
    } else {
        if ((spc_sent[0] ^ spc_frame_image[0]) & 0xc0)
            spc_tone_keyon |= 0x01;
        if ((spc_sent[3] ^ spc_frame_image[3]) & 0xc0)
            spc_tone_keyon |= 0x02;

        spc_old_noise = spc_sent[10];
        spc_new_noise = spc_frame_image[10];
        if ((spc_new_noise & 0x80)
            && (!(spc_old_noise & 0x80)
                || (((spc_old_noise & 0x0f) < 4
                       ? (spc_old_noise & 0x0f) + 6 : 5)
                    != ((spc_new_noise & 0x0f) < 4
                         ? (spc_new_noise & 0x0f) + 6 : 5))))
            spc_tone_keyon |= 0x08;
    }

    for (i = 0; i < 12; i += 2) {
        uint8_t v0 = (i < 11) ? spc_frame_image[i] : 0;
        uint8_t v1 =
            (uint8_t)((i + 1 < 11) ? spc_frame_image[i + 1] : 0);

        if (spc_primed && spc_sent[i] == v0 && spc_sent[i + 1] == v1)
            continue;
        if (!spc_send(i, v0, v1))
            return;
        spc_sent[i] = v0;
        spc_sent[i + 1] = v1;
        changed = 1;
    }

    if (!changed && spc_primed)
        spc_dpcm_flush();
    else if (spc_send(CMD_COMMIT, 0, 0)) {
        spc_primed = 1;
        spc_dpcm_flush();
    }
    if (spc_tone_keyon)
        spc_send(CMD_TONE_KEYON, spc_tone_keyon, 0);
    spc_dpcm_stream_step();
}

/* Every voice to zero volume, without waiting for a frame to say so. */
void spc_silence(void)
{
    uint8_t i;

    if (!spc_alive)
        return;
    if (spc_send(CMD_SILENCE, 0, 0)) {
        spc_send(CMD_DPCM_STOP, 0, 0);
        for (i = 0; i < 12; i++)
            spc_sent[i] = 0;
        spc_primed = 1;
    }
}
