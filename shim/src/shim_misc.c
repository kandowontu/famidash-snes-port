/*
 * shim_misc.c - the rest of the NES library: scroll arithmetic, collision,
 * RNG, memory, banking, and the audio stubs.
 *
 * Everything here is ported from the 6502 originals in LIB/asm rather than
 * reinvented, because the gameplay depends on the exact behaviour - especially
 * the 240-pixel room wrap in the scroll helpers, which the collision map is
 * addressed by (docs/HANDOFF.md trap 23).
 */

#include <stdint.h>
#include "arr_macros.h"
#include "neslib.h"
#include "nesdoug.h"
#include "mapper.h"
#include "nesdash.h"
#include "shim_sa1.h"
#include "shim_spc.h"

#define REG(a) (*(volatile uint8_t *)(a))
#define BG1HOFS  REG(0x210D)
#define BG1VOFS  REG(0x210E)
#define BG2HOFS  REG(0x210F)
#define BG2VOFS  REG(0x2110)
#define BG12NBA  REG(0x210B)

struct Base { uint8_t x, y, width, height; };
extern struct Base Generic;
extern struct Base Generic2;

extern uint16_t seam_scroll_y;
extern uint16_t min_scroll_y;
extern unsigned char drawing_frame;
extern volatile uint8_t hexToDecOutputBuffer[5];

/* ======================================================================== */
/* Scroll                                                                   */
/* ======================================================================== */
/*
 * The counterpart of add_scroll_y in shim_core.c, from __sub_scroll_y in
 * nesdoug.s. The low byte is a pixel offset inside a 240-pixel room and the
 * high byte is the room number, so the borrow happens at 0xF0, not 0x00. An
 * out-of-range low byte is clamped to 0 first, exactly as the original does.
 */
uint16_t sub_scroll_y(uint8_t sub, uint16_t scroll)
{
    /*
     * EVERYTHING HERE IS uint16_t ON PURPOSE - see docs/HANDOFF.md trap 56.
     *
     * Written with uint8_t locals, Calypsi narrows `lo >= sub` to an 8-bit
     * SIGNED compare: with lo = 0xEF and sub = 0x1E that is "-17 >= 30", which
     * is false, so it takes the borrow path and returns 0xFFD1 instead of
     * 0x02D1. The camera then never scrolls up, and the player dies on the
     * ceiling. Same for the `>= 0xF0` test - 0xF0 becomes -16.
     *
     * Keeping the operands 16-bit keeps the comparisons unsigned.
     */
    uint16_t hi = (uint16_t)((scroll >> 8) & 0xFF);
    uint16_t lo = (uint16_t)(scroll & 0xFF);
    uint16_t s = sub;

    if (lo >= 0xF0)
        lo = 0;
    if (lo >= s)
        return (uint16_t)((hi << 8) | ((lo - s) & 0xFF));

    /* borrowed: step back a room and re-base into 0..239 */
    lo = (uint16_t)((lo - s - 16) & 0xFF);
    hi = (uint16_t)((hi - 1) & 0xFF);
    return (uint16_t)((hi << 8) | lo);
}

/* The 16-bit form: subtract a whole number of rooms plus a remainder. */
uint16_t sub_scroll_y_ext(uint16_t sub, uint16_t scroll)
{
    /* 16-bit throughout, same reason as sub_scroll_y (trap 56). */
    uint16_t out = sub_scroll_y((uint8_t)(sub & 0xFF), scroll);
    return (uint16_t)(out - (((sub >> 8) & 0xFF) << 8));
}

/*
 * Rooms are 240 pixels but the SNES tilemap wraps at 256, so a "room + offset"
 * position has to be flattened to a linear pixel count before it can drive a
 * scroll register. On the NES this needed the nametable seam; here it is only
 * arithmetic.
 */
uint16_t calculate_linear_scroll_y(uint16_t nonlinearScroll)
{
    return (uint16_t)((uint16_t)(nonlinearScroll >> 8) * 240
                      + (uint8_t)nonlinearScroll);
}

/*
 * THE SCROLL REGISTERS ARE LATCHED, NOT WRITTEN, HERE.
 *
 * The game calls scroll() from do_the_scroll_thing, which runs in the middle of
 * the frame - and the SNES applies BG1HOFS the instant it is written. Writing it
 * there tears the picture: the scanlines already drawn keep the previous
 * frame's scroll and everything below gets the new one, which is a full-width
 * horizontal seam that moves up and down the screen with how long the frame's
 * work takes. Measured at scanline 42 on a 224-line screen, i.e. a fifth of the
 * way down, with the band above shifted by exactly one frame of camera movement.
 *
 * The NES never had this problem: neslib's scroll() only stores into SCROLL_X /
 * SCROLL_Y and its NMI handler writes $2005 at the top of vblank. This port has
 * no NMI handler, so ppu_wait_nmi() applies them - same as the VRAM queue and
 * for the same reason.
 */
uint16_t shim_bg1_hofs;
uint16_t shim_bg1_vofs;
uint16_t shim_bg2_hofs;
/*
 * Native text screens still use ppu_wait_nmi for input, OAM and audio. Keep
 * that shared frame boundary from reapplying the last gameplay camera after
 * the screen has explicitly reset BG1 to (0,0).
 */
uint8_t shim_native_screen_active;

extern uint8_t parallax_scroll_x;
extern uint8_t current_saw_set;
extern volatile uint8_t shim_menu_active;
extern uint8_t shim_saw_bank;

extern uint8_t shim_screen_on;                  /* shim_ppu.c */

void shim_scroll_apply(void)
{
    uint8_t phase = (uint8_t)(parallax_scroll_x & 1);

    /*
     * The NES NMI switched spike, block, slope and saw CHR banks together on
     * this phase. Both complete 8KB sets are resident on SNES, so changing
     * BG1's character base is atomic and costs one register write rather than
     * a frame-late multi-kilobyte DMA. Native font screens always use base 0.
     */
    BG12NBA = (uint8_t)(0x50
                        | ((shim_native_screen_active || shim_menu_active)
                           ? 0 : phase));
    if (current_saw_set == 14)
        shim_saw_bank = (uint8_t)(14 + phase);
    else if (current_saw_set == 111)
        shim_saw_bank = 111;

    if (shim_native_screen_active) {
        BG1HOFS = 0; BG1HOFS = 0;
        BG1VOFS = 0; BG1VOFS = 0;
        BG2HOFS = 0; BG2HOFS = 0;
        BG2VOFS = 0; BG2VOFS = 0;
        return;
    }

    BG1HOFS = (uint8_t)shim_bg1_hofs;
    BG1HOFS = (uint8_t)(shim_bg1_hofs >> 8);
    BG1VOFS = (uint8_t)shim_bg1_vofs;
    BG1VOFS = (uint8_t)(shim_bg1_vofs >> 8);
    BG2HOFS = (uint8_t)shim_bg2_hofs;
    BG2HOFS = (uint8_t)(shim_bg2_hofs >> 8);
    /* On NES the parallax occupied empty BG1 cells, so it followed the same
       vertical room/camera scroll. Only the horizontal rate differs. */
    BG2VOFS = (uint8_t)shim_bg1_vofs;
    BG2VOFS = (uint8_t)(shim_bg1_vofs >> 8);
}

void set_scroll_x(uint16_t x)
{
    shim_bg1_hofs = x;
    /*
     * The NES kept the pattern in BG1 and shifted its CHR by
     * parallax_scroll_x. On an independent layer, the equivalent displacement
     * is camera minus CHR phase. Its exact 18-tile period is 144 pixels.
     */
    shim_bg2_hofs = (uint16_t)((x - parallax_scroll_x) % 144);

    /* In forced blank there is no raster to tear, and level init sets the
       scroll before the screen comes on - so apply it now rather than leave the
       first visible frame on a stale value. */
    if (!shim_screen_on)
        shim_scroll_apply();
}

/*
 * The scroll value is in collision space, whose origin is the top of the
 * 60-metatile-row window. The level is bottom-aligned in that window, so the
 * tilemap's initial row 0 sits level_scroll_origin pixels below it - 480px for
 * a 27-row level. Tall levels can scroll above that origin: the subtraction
 * then wraps in the 64-row SNES map while shim_vertical_stream replaces the
 * physical row entering the viewport.
 */
extern const uint16_t level_scroll_origin;
void shim_vertical_stream(uint16_t linear_y);

void set_scroll_y(uint16_t y)
{
    uint16_t linear_y = calculate_linear_scroll_y(y);

    /* -1 because BG1VOFS = -1 puts tilemap row 0 on screen line 0 - the
       vertical off-by-one is real and horizontal does not have it (trap 21). */
    shim_vertical_stream(linear_y);
    shim_bg1_vofs =
        (uint16_t)(linear_y - level_scroll_origin - 1);
    if (!shim_screen_on) {
        /* Practice-point loads can jump several rooms and prepare the whole
           visible band at once. Forced blank makes the larger DMA safe. */
        flush_vram_update2();
        shim_scroll_apply();
    }
}

void scroll(uint16_t x, uint16_t y) { set_scroll_x(x); set_scroll_y(y); }

/*
 * Raster splits are the one case that genuinely wants a mid-frame write, so
 * these apply immediately. Nothing in the gameplay path calls them; a real
 * split needs HDMA.
 */
void split(uint16_t x) { set_scroll_x(x); shim_scroll_apply(); }
void xy_split(uint16_t x, uint16_t y)
{
    set_scroll_x(x);
    set_scroll_y(y);
    shim_scroll_apply();
}

extern uint16_t scroll_y;
extern uint8_t scroll_y_subpx;
extern uint16_t currplayer_y;
extern uint16_t player_y[2];

/*
 * From _cap_scroll_y_at_top / _cap_scroll_y_at_bottom in LIB/asm/nesdash.s.
 *
 * THESE DO NOT JUST CLAMP scroll_y. process_y_scroll moves the players and the
 * camera together; when the camera is then pinned at a limit, the players'
 * half of that movement has to be taken back, or it survives while the scroll
 * it was compensating for does not. Both originals therefore
 *
 *   - work out how much scroll was discarded, as a LINEAR pixel count,
 *   - move currplayer_y and player_y[1] back by that much, and
 *   - clear scroll_y_subpx,
 *
 * and the port had only the clamp. The player then drifted ~2px a frame for as
 * long as the camera stayed pinned. It showed up as the ball bouncing on flat
 * ground: the ball is a gamemode whose camera runs through process_y_scroll's
 * target_scroll_y arm, which moves the player EVERY frame, so with the camera
 * pinned the floor eject and the drift fought each other in a ~14-frame cycle.
 * The cube never showed it because its arm only moves the player when the
 * player is outside the dead zone.
 *
 * Only the LOW byte of the linear difference is used, exactly as the original
 * does: "we can't do anything with the high byte of the diff anyway".
 *
 * player_y[0] gets its HIGH byte only. That is not an oversight here - the
 * original stores the low half to _player_y+1 as well (its own comment calls
 * it "apparently guaranteed to be 0") and is immediately overwritten by the
 * high half two instructions later, so the net effect is a high-byte write.
 *
 * The comparisons are the originals': a plain unsigned compare of the packed
 * room:offset value, not of the linearised one. All arithmetic is 16-bit on
 * purpose (docs/HANDOFF.md trap 56).
 */
void cap_scroll_y_at_top(void)
{
    uint16_t old, adj;

    if (scroll_y >= min_scroll_y)
        return;

    old = scroll_y;
    scroll_y = min_scroll_y;

    /* min_scroll_y - old, in room:offset arithmetic, linearised. */
    adj = calculate_linear_scroll_y(sub_scroll_y_ext(old, min_scroll_y));
    adj = (uint16_t)(((adj & 0xFF) << 8) | scroll_y_subpx);

    currplayer_y = (uint16_t)(currplayer_y - adj);
    player_y[0] = (uint16_t)((player_y[0] & 0x00FF) | (currplayer_y & 0xFF00));
    player_y[1] = (uint16_t)(player_y[1] - adj);
    scroll_y_subpx = 0;
}

/*
 * The bottom of the level. 0x2EF is the last room/offset pair the camera may
 * reach; the game tests against it directly in functions/scroll.h.
 *
 * The original's test is a 24-bit compare of scroll_y_subpx:scroll_y against
 * 0x02F000, which is scroll_y >= 0x02F0 - the sub-pixel byte cannot change the
 * result because the constant's own sub-pixel byte is zero.
 */
void cap_scroll_y_at_bottom(void)
{
    uint16_t old, adj;

    if (scroll_y < 0x02F0)
        return;

    old = scroll_y;
    scroll_y = 0x02EF;

    /* old - 0x2EF, in room:offset arithmetic, linearised. */
    adj = calculate_linear_scroll_y(sub_scroll_y_ext(0x02EF, old));
    adj = (uint16_t)(((adj & 0xFF) << 8) | scroll_y_subpx);

    currplayer_y = (uint16_t)(currplayer_y + adj);
    player_y[0] = (uint16_t)((player_y[0] & 0x00FF) | (currplayer_y & 0xFF00));
    player_y[1] = (uint16_t)(player_y[1] + adj);
    scroll_y_subpx = 0;
}

/* ======================================================================== */
/* Collision                                                                */
/* ======================================================================== */
/*
 * From _check_collision in nesdoug.s: an axis-aligned overlap test between
 * Generic and Generic2, in 8-bit arithmetic. The original's `bcs` guards mean
 * an edge that overflows past 255 counts as "no rejection on that side", so
 * they are written here as 16-bit sums compared against 0xFF.
 */
uint8_t check_collision(void)
{
    uint16_t r1 = (uint16_t)Generic.x + Generic.width;
    uint16_t r2 = (uint16_t)Generic2.x + Generic2.width;
    uint16_t b1 = (uint16_t)Generic.y + Generic.height;
    uint16_t b2 = (uint16_t)Generic2.y + Generic2.height;

    if (r1 <= 0xFF && r1 < Generic2.x) return 0;
    if (r2 <= 0xFF && r2 < Generic.x)  return 0;
    if (b1 <= 0xFF && b1 < Generic2.y) return 0;
    if (b2 <= 0xFF && b2 < Generic.y)  return 0;
    return 1;
}

/* ======================================================================== */
/* RNG                                                                      */
/* ======================================================================== */
/* neslib's 16-bit Galois LFSR, stepped 8 times per call. */
static uint16_t rand_seed = 0x8988;

void set_rand(uint16_t seed) { rand_seed = seed ? seed : 1; }

uint8_t newrand(void)
{
    uint8_t i;
    for (i = 0; i < 8; i++) {
        uint16_t bit = (uint16_t)(rand_seed & 1);
        rand_seed >>= 1;
        if (bit)
            rand_seed ^= 0xB400;
    }
    return (uint8_t)rand_seed;
}

/* On the NES this seeded from the frame counter at first input. */
void seed_rng(void) { set_rand((uint16_t)(drawing_frame | 0x0100)); }

uint8_t get_frame_count(void) { return drawing_frame; }

/* ======================================================================== */
/* Memory                                                                   */
/* ======================================================================== */
void memfill(void *dst, uint8_t val, uint16_t len)
{
    uint8_t *p = (uint8_t *)dst;
    uint16_t i;
    for (i = 0; i < len; i++)
        p[i] = val;
}

void memcpy(void *dst, const void *src, uint16_t len)
{
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    uint16_t i;
    for (i = 0; i < len; i++)
        d[i] = s[i];
}

void delay(uint8_t frames)
{
    while (frames--)
        ppu_wait_nmi();
}

/* ======================================================================== */
/* Number formatting                                                        */
/* ======================================================================== */
/*
 * Binary -> 5 decimal digits in hexToDecOutputBuffer, most significant first.
 * The game reads the buffer directly as well as using the return value.
 */
uint16_t hexToDec(uint16_t input)
{
    uint16_t v = input;
    int8_t i;
    for (i = 4; i >= 0; i--) {
        hexToDecOutputBuffer[i] = (uint8_t)(v % 10);
        v /= 10;
    }
    return input;
}

/* ======================================================================== */
/* Banking                                                                  */
/* ======================================================================== */
/*
 * There is no mapper. 65816 long addressing reaches all of ROM, and the linker
 * decides placement, so the PRG calls are nothing.
 *
 * The CHR calls are a different matter: the SNES has no CHR ROM, so a bank
 * switch has to become a transfer of converted tiles into VRAM.
 *
 * THE TWO SPRITE BANKS ARE IMPLEMENTED. MMC3 is in CHR mode B (crt0.s sets
 * MMC3_REG_SEL_CHR_MODE_B), so A12 is inverted and the two 2KB registers cover
 * NES pattern table 1 - which is where every sprite in the game lives:
 *
 *   2KB bank 0 -> NES $1000-$17FF -> OBJ tiles 256-383  (icon / gamemode art)
 *   2KB bank 1 -> NES $1800-$1FFF -> OBJ tiles 384-511  (main sprites + deco)
 *
 * Without this, `set_player_banks()` asked for the ball's or the robot's art and
 * got whatever was uploaded at boot, so seven gamemodes drew the right tile
 * NUMBERS against the wrong ART, and the decoration animation never moved.
 *
 * The static 1KB background banks are folded into a per-level tileset.
 * Parallax is BG2; the saw bank remains dynamic because its two consecutive
 * banks are the original rotation frames.
 */
void mmc3_set_prg_bank_0(uint8_t bank) { (void)bank; }

/* tools/gen_sprchr.py: the 2KB banks gameplay can ask for, widened to 4bpp. */
extern const uint8_t spr_chr_bank_count;
extern const uint8_t spr_chr_bank_num[];
extern const uint8_t *const spr_chr_bank_ptr[];

void queue_chr_upload(uint16_t dest_word, const uint8_t *src, uint16_t bytes);
void flush_chr_now(void);

/* OBJ tiles 256 and 384, in VRAM word addresses: the OBJ base is word $2000 and
   name-select 0 puts the second 256-tile table $1000 words above it. */
#define CHR_DEST_BANK0 0x3000
#define CHR_DEST_BANK1 0x3800
#define CHR_DEST_DECO_CACHE 0x2800
#define CHR_BANK_BYTES 4096

/* Not static: "the bank never changed" and "the upload was dropped" look the
   same on screen, and a trace needs to tell them apart. */
uint8_t shim_chr_bank0 = 0xFF;
uint8_t shim_chr_bank1 = 0xFF;
uint16_t shim_chr_unknown;              /* asked for a bank we do not carry */
uint8_t shim_deco_cached_phase;
static uint8_t shim_deco_base_bank = 0xFF;
static uint8_t shim_deco_cache_bank = 0xFF;

static uint8_t is_player_chr_bank(uint8_t bank)
{
    /*
     * Every bank selected for OBJ bank 0 keeps its live player art in tiles
     * 0..63. The remaining half is unrelated padding/data, so runtime changes
     * among all normal, mini, retro and special-mode banks need only the 2KB
     * player delta. Treating 18..26 as full 4KB switches delayed the paired
     * decoration phase and exposed the wrong animation tiles for two frames.
     */
    return (uint8_t)(bank == 18 || bank == 20 || bank == 22
                     || bank == 24 || bank == 26 || bank == 40
                     || bank == 92 || bank == 94);
}

static const uint8_t *find_sprite_chr_bank(uint8_t bank)
{
    uint8_t i;

    for (i = 0; i < spr_chr_bank_count; i++)
        if (spr_chr_bank_num[i] == bank)
            return spr_chr_bank_ptr[i];
    return 0;
}

static void set_sprite_chr_bank(uint8_t bank, uint16_t dest, uint8_t previous)
{
    uint8_t i;

    for (i = 0; i < spr_chr_bank_count; i++) {
        if (spr_chr_bank_num[i] == bank) {
            const uint8_t *src = spr_chr_bank_ptr[i];

            /*
             * Runtime player-bank changes only alter a compact region:
             *
             *   player banks 40/92/94: tiles 0..63 (2048 bytes)
             *
             * Both decoration phases are instead kept resident: the selected
             * base bank occupies OBJ tiles 384..511 and the full sibling bank
             * occupies the otherwise-unused OBJ tiles 128..255. oam_spr.s
             * selects between the two hardware name tables. The per-frame
             * MMC3 call becomes one byte of state, with no gameplay DMA.
             */
            if (shim_screen_on && dest == CHR_DEST_BANK0
                && is_player_chr_bank(previous)
                && is_player_chr_bank(bank)) {
                queue_chr_upload(dest, src, 2048);
            } else if (shim_screen_on && dest == CHR_DEST_BANK1
                       && (bank == shim_deco_base_bank
                           || bank == shim_deco_cache_bank)) {
                shim_deco_cached_phase =
                    (uint8_t)(bank == shim_deco_cache_bank);
            } else {
                queue_chr_upload(dest, src, CHR_BANK_BYTES);
                if (!shim_screen_on && dest == CHR_DEST_BANK1
                    && (bank == 28 || bank == 30 || bank == 32
                        || bank == 34 || bank == 36 || bank == 38)) {
                    uint8_t sibling = (uint8_t)(bank ^ 2);
                    const uint8_t *sibling_src =
                        find_sprite_chr_bank(sibling);
                    if (sibling_src) {
                        queue_chr_upload(CHR_DEST_DECO_CACHE, sibling_src,
                                         CHR_BANK_BYTES);
                        shim_deco_base_bank = bank;
                        shim_deco_cache_bank = sibling;
                        shim_deco_cached_phase = 0;
                    }
                } else if (dest == CHR_DEST_BANK1) {
                    shim_deco_base_bank = 0xFF;
                    shim_deco_cache_bank = 0xFF;
                    shim_deco_cached_phase = 0;
                }
            }
            /* In forced blank there is no vblank budget to respect, and level
               init switches banks before the screen comes on. */
            if (!shim_screen_on)
                flush_chr_now();
            return;
        }
    }
    /* A bank this build does not carry - the thirteen unreachable icons, the
       contest icons, the menu banks. Leave VRAM alone rather than upload
       something wrong, and count it. */
    shim_chr_unknown++;
}

void mmc3_set_2kb_chr_bank_0(uint8_t bank)
{
    uint8_t previous;

    if (bank == shim_chr_bank0)
        return;                         /* called every frame; only act on a change */
    previous = shim_chr_bank0;
    shim_chr_bank0 = bank;
    set_sprite_chr_bank(bank, CHR_DEST_BANK0, previous);
}

void mmc3_set_2kb_chr_bank_1(uint8_t bank)
{
    uint8_t previous;

    if (bank == shim_chr_bank1)
        return;
    previous = shim_chr_bank1;
    shim_chr_bank1 = bank;

    /*
     * This is the every-game-frame decoration toggle. Both banks are already
     * resident, so do not enter set_sprite_chr_bank(): its linear search over
     * the generated 14-bank pointer table was pure SA-1 work on every frame
     * and pushed dense Heliopolis frames past the display deadline.
     */
    if (shim_screen_on
        && (bank == shim_deco_base_bank || bank == shim_deco_cache_bank)) {
        shim_deco_cached_phase = (uint8_t)(bank == shim_deco_cache_bank);
        return;
    }
    set_sprite_chr_bank(bank, CHR_DEST_BANK1, previous);
}

/*
 * The 1KB registers are the BACKGROUND tilesets ($0000-$0FFF in CHR mode B).
 * Spike/block/slope art is part of the generated 4KB level set. Parallax is
 * BG2. Bank 3 remains live for the rotating saw frames.
 *
 * Tilesets: correct only while one tileset is loaded, which is the case for the
 * level being brought up. Levels that switch spike or block sets mid-level need
 * these to DMA BG tiles.
 *
 * Parallax is deliberately NOT a bank upload: reset_level.h calls
 * mmc3_set_1kb_chr_bank_2(parallax_scroll_x + PARALLAX_CHR) every frame, and the
 * 144 pre-shifted banks exist only because the NES cannot scroll a layer
 * independently. On SNES that is one BG layer and a scroll register - uploading
 * a bank a frame would be 12 scanlines of DMA to reproduce something the
 * hardware does for free. See docs/SNES_PORT_SCOPE.md.
 */
void mmc3_set_1kb_chr_bank_0(uint8_t bank) { (void)bank; }
void mmc3_set_1kb_chr_bank_1(uint8_t bank) { (void)bank; }
void mmc3_set_1kb_chr_bank_2(uint8_t bank)
{
    (void)bank;
    /* reset_level calls this after current_saw_set is selected. Initialise
       frame zero here even before the camera moves. */
    if (current_saw_set == 14)
        mmc3_set_1kb_chr_bank_3((uint8_t)(14 + (parallax_scroll_x & 1)));
    else if (current_saw_set == 111)
        mmc3_set_1kb_chr_bank_3(111);
}

extern const uint8_t saw_tiles_0[];
extern const uint8_t saw_tiles_1[];
extern const uint8_t saw_tiles_none[];

#define CHR_DEST_SAWS     0x0C00
#define CHR_DEST_SAWS_ALT 0x1C00
#define SAW_CHR_BYTES 2048

uint8_t shim_saw_bank = 0xFF;

void mmc3_set_1kb_chr_bank_3(uint8_t bank)
{
    if (bank == shim_saw_bank)
        return;
    if (bank != 14 && bank != 15 && bank != 111)
        return;

    shim_saw_bank = bank;
    /*
     * Banks 14/15 are already the saw quarter of the two resident BG1 phases.
     * The special no-saw bank is not part of a level header, so install it in
     * both bases when requested.
     */
    if (bank == 111) {
        queue_chr_upload(CHR_DEST_SAWS, saw_tiles_none, SAW_CHR_BYTES);
        queue_chr_upload(CHR_DEST_SAWS_ALT, saw_tiles_none, SAW_CHR_BYTES);
        if (!shim_screen_on)
            flush_chr_now();
    }
}
void mmc3_set_8kb_chr(uint8_t bank) { (void)bank; }

uint8_t irqTable[32];
uint8_t irqTableIdx;

void mmc3_disable_irq(void) { }
void set_irq_ptr(const uint8_t *address) { (void)address; }
void write_irq_table(const uint8_t *data) { (void)data; }
void edit_irq_table(uint8_t byte, uint8_t offset) { (void)byte; (void)offset; }
uint8_t is_irq_done(void) { return 1; }

/* ======================================================================== */
/* Audio                                                                    */
/* ======================================================================== */
/*
 * The active 65816 runs Famidash's original 6502 FamiStudio sequencer directly.
 * tools/gen_famistudio.py supplies no-argument native wrappers because they
 * must save the C ABI, set D/DBR and enter with 8-bit A/X.  Arguments travel
 * through bytes in the same dedicated direct page.  HiROM uses S-CPU WRAM
 * $1E00; SA-1 uses shared I-RAM $0700 and wrapper entry points that select it.
 */
#include "famistudio_meta.h"
#include "famistudio_rom_bank.h"

extern uint8_t options;
extern uint8_t famistudio_data_bank;
extern uint8_t famistudio_data_ptr_lo;
extern uint8_t famistudio_data_ptr_hi;
extern uint8_t famistudio_call_arg;
extern uint8_t famistudio_call_arg2;

extern void famistudio_native_init(void);
extern void famistudio_native_music_play(void);
extern void famistudio_native_music_pause(void);
extern void famistudio_native_music_stop(void);
extern void famistudio_native_update(void);
extern void famistudio_native_sfx_init(void);
extern void famistudio_native_sfx_play(void);
extern void famistudio_native_sfx_clear(void);
extern void famistudio_native_sfx_sample_play(void);

#ifdef SHIM_SA1
extern void famistudio_sa1_native_init(void);
extern void famistudio_sa1_native_music_play(void);
extern void famistudio_sa1_native_music_pause(void);
extern void famistudio_sa1_native_music_stop(void);
extern void famistudio_sa1_native_update(void);
extern void famistudio_sa1_native_sfx_init(void);
extern void famistudio_sa1_native_sfx_play(void);
extern void famistudio_sa1_native_sfx_clear(void);
extern void famistudio_sa1_native_sfx_sample_play(void);
#define FS_INIT             famistudio_sa1_native_init
#define FS_MUSIC_PLAY       famistudio_sa1_native_music_play
#define FS_MUSIC_PAUSE      famistudio_sa1_native_music_pause
#define FS_MUSIC_STOP       famistudio_sa1_native_music_stop
#define FS_UPDATE           famistudio_sa1_native_update
#define FS_SFX_INIT         famistudio_sa1_native_sfx_init
#define FS_SFX_PLAY         famistudio_sa1_native_sfx_play
#define FS_SFX_CLEAR        famistudio_sa1_native_sfx_clear
#else
#define FS_INIT             famistudio_native_init
#define FS_MUSIC_PLAY       famistudio_native_music_play
#define FS_MUSIC_PAUSE      famistudio_native_music_pause
#define FS_MUSIC_STOP       famistudio_native_music_stop
#define FS_UPDATE           famistudio_native_update
#define FS_SFX_INIT         famistudio_native_sfx_init
#define FS_SFX_PLAY         famistudio_native_sfx_play
#define FS_SFX_CLEAR        famistudio_native_sfx_clear
#endif

static uint8_t famistudio_source = 0xff;
static uint8_t famistudio_sfx_ready;
static uint8_t famistudio_prepared_song = 0xff;

static void famistudio_set_ptr(uint16_t address)
{
    famistudio_data_ptr_lo = (uint8_t)address;
    famistudio_data_ptr_hi = (uint8_t)(address >> 8);
}

void music_prepare(uint8_t song)
{
    if (song >= famistudio_song_count || song == famistudio_prepared_song)
        return;
#ifdef SHIM_SA1
    spc_requested_song = song;
    shim_request(SHIM_REQ_SPC_PREPARE);
#else
    spc_prepare_song(song);
#endif
    famistudio_prepared_song = song;
}

void music_play(uint8_t song)
{
    const FamiStudioSong *info;

    if ((options & 0x80) || song >= famistudio_song_count)
        return;
    music_prepare(song);
    info = &famistudio_songs[song];
    famistudio_data_bank = (uint8_t)(FAMISTUDIO_FIRST_BANK + info->bank);

    if (famistudio_source != info->source) {
        famistudio_set_ptr(info->address);
        FS_INIT();
        famistudio_source = info->source;
    }
    if (!famistudio_sfx_ready) {
        famistudio_set_ptr(famistudio_sfx_address);
        FS_SFX_INIT();
        famistudio_sfx_ready = 1;
    }

    famistudio_call_arg = info->local_song;
    FS_MUSIC_PLAY();
}

void music_update(void)
{
    if (famistudio_source != 0xff)
        FS_UPDATE();
}

void sfx_play(uint8_t sfx_index, uint8_t channel)
{
    if ((options & 0x40) || !famistudio_sfx_ready)
        return;
    famistudio_call_arg = sfx_index;
    famistudio_call_arg2 = channel;
    FS_SFX_PLAY();
}

/* SSDPCM voice clips are separate from FamiStudio DPCM and remain follow-up. */
void playPCM(uint8_t sample) { (void)sample; }

void famistudio_sfx_clear_channel(uint8_t channel)
{
    if (!famistudio_sfx_ready)
        return;
    famistudio_call_arg = channel;
    FS_SFX_CLEAR();
}

void famistudio_music_stop(void)
{
    if (famistudio_source != 0xff)
        FS_MUSIC_STOP();
}

void famistudio_music_pause(uint8_t pause)
{
    if (famistudio_source == 0xff)
        return;
    famistudio_call_arg = pause;
    FS_MUSIC_PAUSE();
}

void famistudio_update(void)
{
    music_update();
}
