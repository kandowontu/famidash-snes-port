/*
 * shim_engine.c - the level and sprite engine entry points that are 6502 in
 * LIB/asm/nesdash.s on the NES.
 *
 * READ THIS BEFORE TRUSTING A RUNNING ROM.
 *
 * This file is in two halves. The first half is ported: the behaviour is the
 * NES behaviour, expressed in C. The second half is NOT implemented - the
 * functions exist, are safe to call, and do nothing, so that the game links and
 * the parts that ARE finished can be exercised. They are marked individually
 * and listed in docs/M1_6_LINKED_GAME.md.
 *
 * A ROM built with the second half unimplemented links, boots and runs the game
 * loop, but does not draw a level or a player. Do not read "it links" as "it
 * works".
 */

#include <stdint.h>
#include "arr_macros.h"
#include "neslib.h"
#include "nesdoug.h"
#include "mapper.h"
#include "nesdash.h"

/*
 * famidash.h *defines* its globals and so cannot be included from a second
 * translation unit (docs/HANDOFF.md trap 22). Mirrored here instead; the
 * gamemode numbering is famidash.h:29-40 and the movement jump table in
 * nesdash.s is indexed by it directly, so the values must not drift.
 */
#define GAMEMODE_CUBE     0x00
#define GAMEMODE_SHIP     0x01
#define GAMEMODE_BALL     0x02
#define GAMEMODE_UFO      0x03
#define GAMEMODE_ROBOT    0x04
#define GAMEMODE_SPIDER   0x05
#define GAMEMODE_WAVE     0x06
#define GAMEMODE_NINJA    0x08
#define GAMEMODE_POGO     0x09
#define GAMEMODE_SNAKE    0x0A
#define GAMEMODE_FOOTBALL 0x0B

/* --- game globals (famidash.h defines these; declared extern here) ------- */
extern uint8_t gamemode;
extern uint8_t retro_mode;
extern uint8_t attemptCounter[7];
extern uint8_t level;
extern uint32_t scroll_x;
extern uint8_t auto_fs_updates;
extern volatile uint8_t hexToDecOutputBuffer[5];

void load_ground(uint8_t ground_num);
void cube_movement(void);
void ship_movement(void);
void ball_movement(void);
void ufo_movement(void);
void spider_movement(void);
void wave_movement(void);

/* nesdash.h declares nmi_fs_updates_on/off in terms of this. */
uint8_t auto_fs_updates;

/* ======================================================================== */
/* Ported                                                                   */
/* ======================================================================== */

/*
 * From _movement in nesdash.s. A jump table indexed by gamemode, with one
 * special case: in retro mode the ship plays as a UFO. Gamemodes at or beyond
 * the table size do nothing, which is what the `CPX #gamemode_count / BCS end`
 * guard does.
 *
 * The table order is the game's own, and several gamemodes deliberately share
 * a movement routine (robot and ninja are cube; pogo and snake are ball/wave).
 */
void movement(void)
{
    if (retro_mode && gamemode == GAMEMODE_SHIP) {
        ufo_movement();
        return;
    }
    switch (gamemode) {
    case GAMEMODE_CUBE:                 cube_movement();   break;  /* 0 */
    case GAMEMODE_SHIP:                 ship_movement();   break;  /* 1 */
    case GAMEMODE_BALL:                 ball_movement();   break;  /* 2 */
    case GAMEMODE_UFO:                  ufo_movement();    break;  /* 3 */
    case GAMEMODE_ROBOT:                cube_movement();   break;  /* 4 */
    case GAMEMODE_SPIDER:               spider_movement(); break;  /* 5 */
    case GAMEMODE_WAVE:                 wave_movement();   break;  /* 6 */
    case 7:                             ball_movement();   break;
    case GAMEMODE_NINJA:                cube_movement();   break;  /* 8 */
    case GAMEMODE_POGO:                 ball_movement();   break;  /* 9 */
    case GAMEMODE_SNAKE:                wave_movement();   break;  /* 10 */
    case GAMEMODE_FOOTBALL:             cube_movement();   break;  /* 11 */
    default:                            break;             /* out of range */
    }
}

/*
 * From _increment_attempt_count in nesdash.s: a 7-digit decimal counter, one
 * digit per byte, carrying at 10. The top digit deliberately does not carry -
 * the original notes that a check "can be added tho".
 */
void increment_attempt_count(void)
{
    uint8_t i;
    for (i = 0; i < 6; i++) {
        if (++attemptCounter[i] != 10)
            return;
        attemptCounter[i] = 0;
    }
    attemptCounter[6]++;
}

/*
 * From _update_level_completeness in nesdash.s: how far through the level the
 * camera has travelled, as a percentage, stored per level.
 *
 * The original is a 24-bit divide written as a shift-subtract loop because the
 * 6502 has no divide. Here it is a divide. scroll_x is a 32-bit pixel count and
 * level_lengths_* is the same quantity for the whole level.
 */
extern const uint8_t level_lengths_lo[];
extern const uint8_t level_lengths_md[];
extern uint8_t level_completeness_normal[];
extern uint8_t invisible_level_completeness_normal[];
extern uint8_t invisblocks;

void update_level_completeness(void)
{
    uint32_t len = (uint32_t)level_lengths_lo[level]
                 | ((uint32_t)level_lengths_md[level] << 8);
    uint32_t pct;

    if (len == 0)
        return;
    pct = (scroll_x >> 4) * 100 / len;
    if (pct > 100)
        pct = 100;

    if (!invisblocks) {
        if ((uint8_t)pct > level_completeness_normal[level])
            level_completeness_normal[level] = (uint8_t)pct;
    } else {
        if ((uint8_t)pct > invisible_level_completeness_normal[level])
            invisible_level_completeness_normal[level] = (uint8_t)pct;
    }
}

/*
 * Draw the attempt counter as text. The NES version queued the digits into the
 * vram buffer with leading zeros suppressed; so does this.
 */
void display_attempt_counter(uint8_t zeroChr, uint16_t ppu_address)
{
    uint8_t digits[7];
    int8_t i;
    uint8_t started = 0, n = 0;

    for (i = 6; i >= 0; i--) {
        uint8_t d = attemptCounter[i];
        if (d || started || i == 0) {
            started = 1;
            digits[n++] = (uint8_t)(zeroChr + d);
        }
    }
    multi_vram_buffer_horz(digits, n, ppu_address);
}

/*
 * Text padded to a fixed width with spaces, so a shorter string overwrites
 * whatever a longer one left behind. Space is character 0 in the game's
 * charmap.
 */
void draw_padded_text(const void *data, uint8_t len, uint8_t total_len,
                      uint16_t ppu_address)
{
    const uint8_t *p = (const uint8_t *)data;
    uint8_t i;
    multi_vram_buffer_horz(p, len, ppu_address);
    for (i = len; i < total_len; i++)
        one_vram_buffer(0, (uint16_t)(ppu_address + i));
}

void printDecimal(uint16_t value, uint8_t digits, uint8_t zeroChr,
                  uint8_t spaceChr, uint16_t ppu_address)
{
    uint8_t out[5];
    uint8_t i, started = 0;
    hexToDec(value);
    for (i = 0; i < 5; i++) {
        uint8_t d = hexToDecOutputBuffer[i];
        if (d) started = 1;
        out[i] = (uint8_t)(started || i == 4 ? zeroChr + d : spaceChr);
    }
    multi_vram_buffer_horz(out + (5 - digits), digits, ppu_address);
}

/* A VS System / debug hook with no SNES meaning. */
void gameboy_check(void) { }

/* ======================================================================== */
/* Level rendering - IMPLEMENTED, single-level path                         */
/* ======================================================================== */
/*
 * draw_screen() streams one tilemap column per call, from the column records
 * tools/snes_m0.py precomputes. This is NOT a translation of the 355-line 6502
 * original: that spread a single column across three frames because that is all
 * an NES vblank affords, and one of those frames was attribute-table work that
 * has no SNES equivalent. src/scroll.s already proved this shape, and the
 * cadence below mirrors it.
 *
 * Contract, from the call sites in functions/level_loading.h:
 *   - returns non-zero if it queued anything, and the caller then flushes;
 *   - it is called in a tight loop at level init (scroll_x advancing each
 *     iteration) to fill the screen before it is switched on, and once per
 *     frame afterwards.
 *
 * The 64x32 BG1 map is two 32x32 screens back to back, so column slot n lands
 * at (n & 31) + (n & 32 ? 0x400 : 0) words from the map base. The map wraps
 * every 64 columns, which is what lets the level stream past it indefinitely.
 *
 * SCOPE: the whole level is precomputed, which costs 128KB of ROM for one
 * level. That does not generalise to 46 levels, let alone 454 level files.
 * See docs/M2_LEVEL_RENDER.md.
 */
#define COLS_AHEAD  34          /* columns kept ahead of the left screen edge */
#define COL_BYTES   128         /* one record = 64 tilemap words = one column */
#define COL_WORDS   64

/*
 * The collision map, refilled from the same stream as the camera moves.
 *
 * bg_collision_sub() reads collMap[room & 3][(x >> 4) | (y & 0xF0)] and temp_x
 * is a byte, so `x >> 4` is the metatile column modulo 16: the window is 16
 * metatile columns = 256 pixels = exactly one screen, and metatile column c
 * always lands in slot c & 15. That is the NES design, and it is what lets a
 * whole level stream through a 1KB map.
 *
 * Only page 0 is filled, matching the static window tools/snes_m0.py bakes: the
 * level is 27 metatiles tall and the collision rows are the bottom 15 - the
 * playfield.
 */
extern uint16_t min_scroll_y;
extern uint8_t collMap[4][256];

#define COLL_PAGES 4
#define COLL_ROWS  15           /* one 240-pixel room */
#define COLL_REC   (COLL_PAGES * COLL_ROWS)
#define GROUND_ROWS 3           /* the ground strip, the last rows of page 3 */
#define GROUND_COLS 16          /* the collision window is 16 metatiles wide */

/*
 * The ground strip: 3 rows x 16 metatile columns, filled by load_ground() and
 * copied into the bottom of collision page 3 as each column streams.
 *
 * This is the FLOOR. It is not in the level data - the opening run-up of Stereo
 * Madness has no collision at all until metatile column 17 - so with this
 * unfilled there is genuinely nothing to stand on.
 */
static uint8_t ground_strip[GROUND_ROWS * GROUND_COLS];













/* ======================================================================== */
/* Level decoding - every level, at run time                                */
/* ======================================================================== */
/*
 * This replaces the precomputed column stream. That stream cost 230KB of ROM
 * for ONE level - 1796 tile columns of 128 bytes - which is why the port sat on
 * Stereo Madness. The whole 46-level set is 198KB of LZ, so decoding at run
 * time is both smaller and general, which is what the NES did all along.
 *
 * The SNES makes it much easier than the NES had it, though, and the design is
 * not a translation of the 6502: the largest level decompresses to 19.7KB and
 * there is 128KB of WRAM, so the WHOLE level is decompressed once at load
 * instead of being streamed through a window. Only the RLE layer stays
 * incremental, because a decoded metatile grid would not fit.
 *
 * Three stages, and the formats are the game's own (tools/snes_m0.py has the
 * same two decoders in Python, which is what verifies this one):
 *
 *   .lz   -> LZ, a 256-byte ring and three opcodes      -> the RLE stream
 *   RLE   -> vertical, column-major, `height` per column -> metatile ids
 *   id    -> four SNES tilemap words, from metatile_words
 */

extern const uint8_t *const level_lz_ptr[];
extern const uint8_t *const level_spr_ptr[];
extern const uint8_t level_count;
extern const uint16_t metatile_words[256 * 4];

/* The game's own level index; `current_level` reads better where the
   decoder uses it and is the same variable. */
extern uint8_t level;
extern uint8_t song;
#define current_level level

extern const uint8_t lvl_song[];
extern const uint8_t lvl_gamemode_speed[];
extern const uint8_t lvl_spawn_y_hi[];
extern const uint8_t lvl_spawn_scroll_y_lo[];
extern const uint8_t lvl_platformer_parallax[];
extern const uint8_t lvl_fallspeed_deco[];
extern const uint8_t lvl_spike_block[];
extern const uint8_t lvl_bg_color[];
extern const uint8_t lvl_ground_color[];
extern const uint8_t lvl_height[];
extern const uint8_t lvl_bg_tileset[];          /* tools/gen_bgchr.py */
extern const uint8_t *const bg_tileset_ptr[];
void set_bg_tileset(uint8_t which);
void set_level_colors(uint8_t bg_color, uint8_t ground_color);

/*
 * The decompressed RLE stream. 20KB covers the largest level in the set
 * (extraordinaryexcitement, 19712 bytes); tools/gen_levels.py prints the figure
 * and the decompressor refuses to overrun this.
 */
#define LEVEL_RLE_MAX 20480
static uint8_t level_rle[LEVEL_RLE_MAX];
static uint16_t level_rle_len;

/* Non-static: a trace needs to tell "the level did not decompress" apart from
   "the level decompressed and the renderer did nothing with it". */
uint16_t shim_lz_len;
uint8_t shim_lz_overrun;
/* Which level is currently inflated into level_rle; 0xFF = none. */
static uint8_t level_loaded = 0xFF;

/*
 * LZ, the inverse of aart_lz.compress().
 *
 *   $FF             end
 *   $80, b          literal b
 *   L, idx, b       copy L bytes from ring[idx..], then literal b
 *
 * The ring is 256 bytes, zero-initialised, and the copy source is the
 * PRE-WRITE ring state - compress() matches before appending - so the copy has
 * to be snapshotted before the writes. find_subarray() never wraps, so the copy
 * does not either.
 */
#define LZ_END      0xFF
#define LZ_LITERAL  0x80

static uint8_t lz_ring[256];

static void lz_decompress(const uint8_t *src)
{
    uint16_t out = 0;
    uint16_t base, rd;
    uint8_t w = 0;
    uint16_t i;

    for (i = 0; i < 256; i++)
        lz_ring[i] = 0;
    shim_lz_overrun = 0;

    for (;;) {
        uint8_t len = *src++;
        uint8_t idx, b, n;

        if (len == LZ_END)
            break;
        if (len == LZ_LITERAL) {
            b = *src++;
            if (out >= LEVEL_RLE_MAX) { shim_lz_overrun = 1; break; }
            level_rle[out++] = b;
            lz_ring[w++] = b;
            continue;
        }
        idx = *src++;
        b = *src++;
        rd = idx;
        if ((uint16_t)(out + len) > LEVEL_RLE_MAX) { shim_lz_overrun = 1; break; }
        base = out;
        /*
         * `rd` is a uint16_t, NOT `lz_ring[(uint8_t)(idx + n)]`.
         *
         * Calypsi 5.18 SIGN-EXTENDS a cast-to-uint8_t used directly as an array
         * index: it emits `eor #128 / and #255 / sec / sbc #128` and puts the
         * result in X, so index 159 reads lz_ring MINUS 97. Reading a plain
         * uint8_t variable is zero-extended correctly (`and #255`) - it is the
         * cast in the subscript that goes wrong. See docs/HANDOFF.md trap 94.
         *
         * The failure is entirely silent and data-dependent: every copy whose
         * source stays below ring index 128 is correct, so the level decodes
         * perfectly for a few hundred bytes and then a handful of bytes come
         * back as whatever was in memory in front of the array.
         *
         * Snapshot semantics: the ring is read from its pre-write state,
         * because compress() matches before appending.
         */
        for (n = 0; n < len; n++) {
            level_rle[out++] = lz_ring[rd];
            rd = (uint16_t)((rd + 1) & 0xFF);
        }
        /*
         * The ring append reads back what was just written to level_rle, NOT
         * the ring.
         *
         * Reading the ring here is the same aliasing bug one line up, and it is
         * not hypothetical: the write cursor w can land inside [idx, idx+len),
         * and then the later iterations read bytes this very loop has already
         * replaced. It corrupts a handful of bytes and the stream then resyncs
         * on the next literal, so the level looks almost right - a wall of one
         * metatile where there should be sky - rather than obviously broken.
         * level_rle[base..] is the pre-write snapshot, already materialised.
         */
        for (n = 0; n < len; n++)
            lz_ring[w++] = level_rle[base + n];
        if (out >= LEVEL_RLE_MAX) { shim_lz_overrun = 1; break; }
        level_rle[out++] = b;
        lz_ring[w++] = b;
    }
    level_rle_len = out;
    shim_lz_len = out;
}

/*
 * The RLE layer, read one metatile at a time.
 *
 *   b >= $80   ->  a single metatile (b & $7F)
 *   b <  $80   ->  a run of (b + 1) copies of the next byte
 *
 * Incremental, unlike the LZ: a decoded metatile grid would be up to 170KB.
 * A run can span a column boundary, so the run counter is part of the cursor.
 */
static uint16_t rle_pos;
static uint8_t rle_run;                 /* metatiles left in the current run */
static uint8_t rle_run_value;

static void rle_rewind(void)
{
    rle_pos = 0;
    rle_run = 0;
}

static uint8_t rle_next(void)
{
    uint8_t b;

    if (rle_run) {
        rle_run--;
        return rle_run_value;
    }
    if (rle_pos >= level_rle_len)
        return 0;                       /* past the end - empty sky */
    b = level_rle[rle_pos++];
    if (b & 0x80)
        return (uint8_t)(b & 0x7F);
    if (rle_pos >= level_rle_len)
        return 0;
    rle_run_value = level_rle[rle_pos++];
    rle_run = b;                        /* b + 1 copies: this one plus b more */
    return rle_run_value;
}

/*
 * One metatile column: the level's own rows, then the 3 ground rows.
 *
 * GROUND_ROWS come from ground_strip rather than the level data - the floor is
 * not in the level (trap 43) - and repeat every 16 columns, which is the width
 * of the collision window.
 */
#define MT_COL_MAX 60                   /* the collision window, 57 + 3 ground */
uint8_t mt_col[MT_COL_MAX];             /* public for cache_col.s */
static uint8_t mt_rows;                 /* height + GROUND_ROWS */
static uint16_t mt_col_index;           /* which metatile column mt_col holds */

/*
 * The SNES tilemap is 64 tiles high but the NES collision world is 120 tiles
 * high.  Keep the most recent 32 metatile columns (64 tile columns, exactly
 * the horizontal tilemap ring) so a row entering the vertical viewport can be
 * reconstructed without rewinding the level's column-major RLE stream.
 *
 * Cached columns stay compact, like mt_col: level rows followed by ground.
 * The world-row lookup subtracts the top padding. Copying 30 words is much
 * cheaper on 65816 than writing 60 individual bytes every other frame.
 */
#define MT_CACHE_COLS 32
uint8_t mt_cache[MT_CACHE_COLS][MT_COL_MAX]; /* public for cache_col.s */
static uint16_t mt_cache_tag[MT_CACHE_COLS];
static uint8_t vertical_level;
void shim_cache_mt_column(uint16_t mc);

static void decode_metatile_column(uint16_t mc)
{
    uint8_t h = lvl_height[current_level];
    uint8_t *dst = mt_col;
    const uint8_t *gs = &ground_strip[mc & 15];
    uint8_t left = h;
    uint8_t r;

    /*
     * The run is expanded HERE, not one metatile at a time through rle_next().
     *
     * A level column is mostly runs - solid ground, solid sky - so the loop
     * `for (r = 0; r < h; r++) mt_col[r] = rle_next();` spent its time on the
     * call and on re-indexing mt_col rather than on decoding: 33 scanlines for
     * 57 metatiles. Copying a run with a walking pointer is the same trick that
     * fixed write_collision_column and build_tile_columns.
     *
     * rle_next() is still the authority on the format; this only shortcuts the
     * case where the cursor is already inside a run.
     */
    while (left) {
        uint8_t run = rle_run;
        if (run) {
            uint8_t v = rle_run_value;
            if (run > left)
                run = left;
            rle_run -= run;
            left -= run;
            do { *dst++ = v; } while (--run);
        } else {
            *dst++ = rle_next();
            left--;
        }
    }
    for (r = 0; r < GROUND_ROWS; r++) {
        *dst++ = *gs;
        gs += GROUND_COLS;
    }
    mt_rows = (uint8_t)(h + GROUND_ROWS);
    mt_col_index = mc;

    if (vertical_level) {
        shim_cache_mt_column(mc);
        mt_cache_tag[mc & (MT_CACHE_COLS - 1)] = mc;
    }
}

/*
 * Written as two walking pointers rather than the obvious index arithmetic.
 *
 * `collMap[p][(r << 4) | slot] = src[p * COLL_ROWS + r]` reads clearly and
 * compiles to a multiply, two shifts and two long-indexed accesses PER BYTE -
 * about 350 cycles each for 63 bytes. Measured, that put draw_screen at 98
 * scanlines on the frames it streams a column, which is 37% of a frame on top
 * of the ~200 scanlines everything else needs: the frame overran and cost a
 * whole extra one. It was the entire lag frame.
 *
 * Both walks are exactly linear - the destination steps by 16 down a column and
 * carries into the next page every 15 rows, and the source is consecutive - so
 * a pointer that steps is the same computation with the address arithmetic done
 * once instead of 63 times.
 */
static void write_collision_column(void)
{
    /*
     * The collision map is the 60-row window and the level is BOTTOM-aligned in
     * it, with the last GROUND_ROWS reserved for the floor (trap 42) - so the
     * decoded column starts `pad` rows down and everything above is empty.
     *
     * Two loops, not one with a test per row. The destination steps by 16 down
     * a column and skips the 16th row of each 256-byte page; that walk is the
     * same either way, but choosing between "empty" and "copy" on every one of
     * the 60 rows was not free.
     */
    uint8_t *dst = &collMap[0][mt_col_index & 15];
    uint16_t pad = (uint16_t)(COLL_PAGES * COLL_ROWS - mt_rows);
    const uint8_t *src = mt_col;
    uint16_t n, page_left = COLL_ROWS;

    for (n = 0; n < pad; n++) {
        *dst = 0;
        dst += 16;
        if (!--page_left) { dst += 16; page_left = COLL_ROWS; }
    }
    for (n = pad; n < COLL_PAGES * COLL_ROWS; n++) {
        *dst = *src++;
        dst += 16;
        if (!--page_left) { dst += 16; page_left = COLL_ROWS; }
    }
}


/* ======================================================================== */
/* Level rendering                                                          */
/* ======================================================================== */

/* Not static: the trace scripts read it from the linker map, and knowing how
   far the renderer has streamed is the first question when nothing appears. */
uint16_t rld_column;            /* next TILE column to write */

/* How many tile columns the level has, and where its top sits in the tilemap.
   Both derive from the decoded level, so both are computed at load. */
uint16_t level_columns_count;
uint16_t level_coll_column_count;
uint16_t level_scroll_origin;
static uint16_t level_tile_start;       /* first grid tile row the record shows */
static uint8_t level_map_origin_tile;   /* world row represented by map row 0 */

/*
 * Physical BG1 rows form a ring around the initial clipped window.  Each entry
 * records which of the 120 world tile rows currently occupies that physical
 * slot.  A tall level replaces one row when it enters the viewport; newly
 * streamed horizontal columns consult the same table, so the row/column
 * intersection is always built from the same world coordinate.
 */
static uint8_t map_world_row[COL_WORDS];
static uint8_t vertical_visible_first;
static uint8_t vertical_visible_last;
static uint8_t vertical_stream_ready;
static uint8_t vertical_ring_active;

/* See drawplayerone: these must NOT be locals. */
static uint8_t player_draw_px, player_draw_off;

/* Cursor into the level's sprite-object stream; see check_spr_objects. */
static uint16_t sprite_cursor;
static uint8_t sprite_stream_done;

void queue_vram_column(uint16_t slot, const uint8_t *rec);   /* shim_ppu.c */
uint8_t queue_vram_row(uint8_t slot, const uint16_t *rec);
void clear_vram_row_queue(void);

/*
 * Column records are BUILT now, not pointed at, so they need to live somewhere
 * until the DMA runs in vblank. A ring, because queue_vram_column only stores
 * the pointer. Gameplay has depth 1. Level init batches the first 34 columns so
 * SA-1 needs one S-CPU request instead of one request/vblank per column; the
 * ring therefore matches the 64-entry VRAM column queue.
 */
#define COL_RING 64
static uint16_t col_ring[COL_RING][COL_WORDS];
static uint8_t col_ring_next;
static uint8_t col_pair;                /* the ring slot holding this pair */

/*
 * A death restarts the SAME level at the SAME first 34 tile columns. Building
 * those columns costs about ten visible frames even in forced blank; on SA-1
 * the old per-column S-CPU handshakes cost much more. Cache the prepared words,
 * collision window and RLE cursor from the first entry, then replay them.
 */
#define RESTART_COLS 34
static uint16_t restart_cols[RESTART_COLS][COL_WORDS];
static uint8_t restart_collmap[COLL_PAGES][256];
static uint16_t restart_rle_pos;
static uint8_t restart_rle_run;
static uint8_t restart_rle_run_value;
static uint8_t restart_cache_level;
static uint8_t restart_cache_valid;
static uint8_t restart_replay;

extern uint8_t practice_point_count;
extern uint8_t no_parallax;

static void restart_cache_snapshot(void)
{
    uint8_t *dst = &restart_collmap[0][0];
    uint8_t *src = &collMap[0][0];
    uint16_t i;

    for (i = 0; i < COLL_PAGES * 256; i++)
        *dst++ = *src++;
    restart_rle_pos = rle_pos;
    restart_rle_run = rle_run;
    restart_rle_run_value = rle_run_value;
    restart_cache_level = current_level;
    restart_cache_valid = 1;
}

static void restart_cache_restore(void)
{
    uint8_t *dst = &collMap[0][0];
    uint8_t *src = &restart_collmap[0][0];
    uint16_t i;

    for (i = 0; i < COLL_PAGES * 256; i++)
        *dst++ = *src++;
    rle_pos = restart_rle_pos;
    rle_run = restart_rle_run;
    rle_run_value = restart_rle_run_value;
}

/*
 * Tile $FE is a dedicated transparent SNES-only tile. NES draw_screen
 * replaced tile $00 with the parallax pattern; BG2 now carries that pattern,
 * so BG1's corresponding cells must be holes. Levels that disable parallax
 * keep the original tile $00, matching the NES @nopar path.
 */
#define BG_TRANSPARENT_TILE 0x00FE
/*
 * Build ONE tile column of a metatile column - `half` 0 is the left, 1 the
 * right.
 *
 * map_world_row is the authority now. Initially it describes the same bottom
 * 64 rows the old clipped renderer emitted, byte for byte. As the camera rises,
 * individual physical rows are reassigned to the world rows entering from
 * above. Consulting the table here is essential: a new horizontal column must
 * agree with rows already replaced by the vertical streamer.
 */
static void build_tile_column(uint8_t slot, uint8_t half)
{
    uint16_t *dst = col_ring[slot + half];
    uint16_t skip = (uint16_t)(level_tile_start >> 1);
    uint16_t nrows = (uint16_t)(mt_rows - skip);
    const uint8_t *src = &mt_col[skip];
    uint16_t r;

    if (nrows > (COL_WORDS >> 1))
        nrows = COL_WORDS >> 1;
    for (r = 0; r < nrows; r++) {
        const uint16_t *w =
            &metatile_words[((uint16_t)(*src++) << 2) + half];
        uint16_t top = w[0];
        uint16_t bottom = w[2];
        if (!no_parallax) {
            if (!(top & 0x03FF))
                top = (uint16_t)((top & 0xFC00) | BG_TRANSPARENT_TILE);
            if (!(bottom & 0x03FF))
                bottom = (uint16_t)((bottom & 0xFC00) | BG_TRANSPARENT_TILE);
        }
        *dst++ = top;
        *dst++ = bottom;
    }
    for (r = (uint16_t)(nrows << 1); r < COL_WORDS; r++)
        *dst++ = (uint16_t)(no_parallax ? 0 : BG_TRANSPARENT_TILE);
}

static void build_tile_column_ring(uint8_t slot, uint8_t half)
{
    uint16_t *dst = col_ring[slot + half];
    const uint8_t *cache = mt_cache[mt_col_index & (MT_CACHE_COLS - 1)];
    uint16_t blank = (uint16_t)(no_parallax ? 0 : BG_TRANSPARENT_TILE);
    uint16_t r;

    /*
     * Only the 28/29 visible world rows must be correct in a newly arriving
     * horizontal column. Rows entering later are rebuilt across all 64 columns
     * by stream_world_tile_row.
     */
    for (r = 0; r < COL_WORDS; r++)
        *dst++ = blank;
    dst = col_ring[slot + half];
    for (r = vertical_visible_first; r <= vertical_visible_last; r++) {
        uint8_t world_tile = (uint8_t)r;
        uint8_t world_mt = (uint8_t)(world_tile >> 1);
        uint8_t pad = (uint8_t)(MT_COL_MAX - mt_rows);
        uint8_t physical_row =
            (uint8_t)((world_tile - level_map_origin_tile)
                      & (COL_WORDS - 1));
        uint16_t word = 0;
        if (world_mt >= pad) {
            uint8_t mt = cache[world_mt - pad];
            const uint16_t *w =
                &metatile_words[((uint16_t)mt << 2) + half];
            word = w[(world_tile & 1) ? 2 : 0];
        }
        if (!no_parallax && !(word & 0x03FF))
            word = (uint16_t)((word & 0xFC00) | BG_TRANSPARENT_TILE);
        dst[physical_row] = word;
    }
}

static uint16_t vertical_row_buf[COL_WORDS];

/* Put one 120-row-world tile row into its congruent physical row in BG1. */
static void stream_world_tile_row(uint8_t world_tile)
{
    uint8_t physical_row =
        (uint8_t)((world_tile - level_map_origin_tile) & (COL_WORDS - 1));
    uint8_t mt_row;
    uint8_t pad;
    uint8_t slot;
    uint16_t *dst;

    if (world_tile >= MT_COL_MAX * 2)
        return;
    if (map_world_row[physical_row] == world_tile
        && !vertical_ring_active)
        return;
    if (map_world_row[physical_row] != world_tile)
        vertical_ring_active = 1;

    mt_row = (uint8_t)(world_tile >> 1);
    pad = (uint8_t)(MT_COL_MAX - mt_rows);
    dst = vertical_row_buf;
    for (slot = 0; slot < MT_CACHE_COLS; slot++) {
        uint16_t left = 0;
        uint16_t right = 0;

        if (mt_cache_tag[slot] != 0xFFFF && mt_row >= pad) {
            uint8_t mt = mt_cache[slot][mt_row - pad];
            const uint16_t *w =
                &metatile_words[(uint16_t)mt << 2];
            uint8_t bottom = (uint8_t)((world_tile & 1) ? 2 : 0);
            left = w[bottom];
            right = w[bottom + 1];
        }
        if (!no_parallax) {
            if (!(left & 0x03FF))
                left = (uint16_t)((left & 0xFC00) | BG_TRANSPARENT_TILE);
            if (!(right & 0x03FF))
                right = (uint16_t)((right & 0xFC00) | BG_TRANSPARENT_TILE);
        }
        *dst++ = left;
        *dst++ = right;
    }

    /* queue_vram_row copies the scratch row before returning. */
    if (queue_vram_row(physical_row, vertical_row_buf))
        map_world_row[physical_row] = world_tile;
}

/*
 * Maintain the 64-row map as a vertical ring around the 28-row viewport.
 * Normal camera motion introduces at most one row at an edge. A practice-point
 * jump can move by rooms at once, so resynchronise the whole visible band; it
 * is still at most 29 rows and happens while the screen is blank.
 */
void shim_vertical_stream(uint16_t linear_y)
{
    uint8_t first;
    uint8_t last;
    uint16_t row;
    uint8_t large_jump;

    /* Short levels already fit in the 64-row BG map. Keep their frame-critical
       scroll path byte-for-byte simple; the ring only exists for clipped maps. */
    if (!vertical_stream_ready || !vertical_level)
        return;

    first = (uint8_t)(linear_y >> 3);
    last = (uint8_t)((linear_y + 223) >> 3);
    large_jump = (uint8_t)(
        first + 2 < vertical_visible_first
        || first > vertical_visible_first + 2);

    if (large_jump) {
        for (row = first; row <= last; row++)
            stream_world_tile_row((uint8_t)row);
    } else {
        for (row = first; row < vertical_visible_first; row++)
            stream_world_tile_row((uint8_t)row);
        for (row = (uint16_t)vertical_visible_last + 1; row <= last; row++)
            stream_world_tile_row((uint8_t)row);
    }

    vertical_visible_first = first;
    vertical_visible_last = last;
}

uint8_t draw_screen(void)
{
    uint16_t target;

    if (rld_column >= level_columns_count)
        return 0;                       /* whole level streamed */

    /*
     * scroll_x is a 32-bit pixel count; >>3 is the leftmost visible tile
     * column. It starts negative (level_loading.h sets it to -256 so the first
     * screen draws into the left half of the map), and the shift of a negative
     * value would run away, so the comparison is done in the unsigned space the
     * game already keeps it in.
     */
    target = (uint16_t)((scroll_x >> 3) + COLS_AHEAD);
    if (rld_column >= target)
        return 0;                       /* far enough ahead already */

    if (restart_replay && rld_column < RESTART_COLS) {
        queue_vram_column((uint16_t)(rld_column & 0x3F),
                          (const uint8_t *)restart_cols[rld_column]);
        rld_column++;
        if (rld_column == RESTART_COLS)
            restart_cache_restore();
        return 1;
    }

    /*
     * The work is split across the metatile column's two frames rather than
     * done all at once - and split EVENLY, which took two goes.
     *
     * Doing all of it on the even frame cost 63 scanlines there and 0 on the
     * odd one, and the even frame overran. Moving only the collision write to
     * the odd frame left 63 and 35. Building one tile column per frame as well
     * puts decode + half the build against half the build + collision, which is
     * about 48 and 50 - the same total work, and no frame carrying a burst that
     * does not fit.
     *
     * DO NOT try to spread it over more frames than this. The obvious next step
     * - decouple preparation from streaming, do one unit of work per call
     * whether or not a column is due - was built and measured and changed
     * nothing (91.6% against 91.7% on the heaviest level). The premise is
     * false: at these level speeds the camera needs a new tile column on about
     * 90% of frames, so there are no spare calls to spread into. What is left
     * on those levels is the game's own sprite code, not this. See
     * docs/M2_17_TILESETS.md.
     *
     * Both halves are built from mt_col, which decode_metatile_column filled on
     * the even frame and nothing touches until the next one.
     *
     * The collision column arriving a frame later is safe: draw_screen keeps
     * COLS_AHEAD (34) tile columns in front of the camera, so the player is
     * seventeen metatiles away from anything being written.
     */
    if (!(rld_column & 1)) {
        decode_metatile_column((uint16_t)(rld_column >> 1));
        col_pair = col_ring_next;
        col_ring_next = (uint8_t)((col_ring_next + 2) & (COL_RING - 1));
        if (vertical_ring_active)
            build_tile_column_ring(col_pair, 0);
        else
            build_tile_column(col_pair, 0);
    } else {
        if (vertical_ring_active)
            build_tile_column_ring(col_pair, 1);
        else
            build_tile_column(col_pair, 1);
        write_collision_column();
    }

    {
        uint16_t *built = col_ring[col_pair + (rld_column & 1)];

        queue_vram_column((uint16_t)(rld_column & 0x3F),
                          (const uint8_t *)built);
        if (!restart_replay && !practice_point_count
            && rld_column < RESTART_COLS) {
            uint16_t *saved = restart_cols[rld_column];
            uint16_t i;
            for (i = 0; i < COL_WORDS; i++)
                *saved++ = *built++;
        }
    }

    rld_column++;
    if (!restart_replay && !practice_point_count
        && rld_column == RESTART_COLS)
        restart_cache_snapshot();
    return 1;
}

/*
 * Reset the column stream, and apply the level header.
 *
 * On the NES the header is the 13 bytes in front of the level's LZ stream, read
 * at level load (nesdash.s, around the level_list pointer fetch). This port
 * consumes the .lz file directly, which is the RLE stream ONLY - so nothing was
 * reading the header and every field it carries stayed 0. The visible effect
 * was spawn_y_pos = 0: the player started at the top of the level, fell three
 * rooms to the ground, and the level reset.
 *
 * tools/gen_assets.py parses the header out of all_level_data.s into
 * out/level_header.c. Note spawn_scroll_y_pos's high byte is not in the header
 * at all - nesdash.s hardcodes $02 with the comment "no levels need this
 * setting, at least yet" - so it is hardcoded here too, for the same reason.
 */
extern uint16_t spawn_y_pos;
extern uint16_t spawn_scroll_y_pos;
extern uint8_t speed;
extern uint8_t force_platformer;
extern uint8_t max_fallspeed_7;
extern uint8_t current_deco_type;
extern uint8_t current_spike_set;
extern uint8_t current_block_set;

/*
 * Count the level's metatile columns by walking the RLE once.
 *
 * The count is not in the header and cannot be had from the compressed size, so
 * it is measured: total metatiles / height. One pass over at most 20KB, once per
 * level load - cheaper than carrying a 46-entry table that could drift from the
 * data it describes.
 */
static uint16_t count_metatile_columns(uint8_t height)
{
    uint32_t tiles = 0;
    uint16_t pos = 0;

    while (pos < level_rle_len) {
        uint8_t b = level_rle[pos++];
        if (b & 0x80) {
            tiles++;
            continue;
        }
        if (pos >= level_rle_len)
            break;
        pos++;                          /* the run's value byte */
        tiles += (uint32_t)b + 1;
    }
    return height ? (uint16_t)(tiles / height) : 0;
}

void init_rld(void)
{
    uint8_t lv = current_level;
    uint8_t h;
    uint8_t r;
    uint16_t grid_rows;
    uint16_t spawn_linear;

    /* A reset can follow a frame that prepared a vertical row for the old
       camera. Do not let that stale row flush over the freshly built screen. */
    clear_vram_row_queue();
    vertical_stream_ready = 0;
    vertical_ring_active = 0;

    /*
     * Decompress the WHOLE level. The NES could not - it had 2KB of RAM and
     * streamed the RLE through a window - but the largest level here is 19.7KB
     * decompressed against 128KB of WRAM, so the awkward half of the NES design
     * simply does not need porting. Only the RLE layer stays incremental,
     * because a decoded metatile grid would be up to 170KB.
     */
    /*
     * Only decompress when the LEVEL changes. init_rld runs from reset_level,
     * so it is on the death path too - and re-inflating up to 20KB every time
     * the player dies is work nothing asked for.
     */
    if (lv != level_loaded) {
        restart_cache_valid = 0;
        lz_decompress(level_lz_ptr[lv]);
        level_loaded = lv;
        level_coll_column_count = count_metatile_columns(lvl_height[lv]);
        level_columns_count = (uint16_t)(level_coll_column_count << 1);
        for (r = 0; r < MT_CACHE_COLS; r++)
            mt_cache_tag[r] = 0xFFFF;
    }
    rle_rewind();
    rld_column = 0;
    col_ring_next = 0;
    restart_replay = (uint8_t)(restart_cache_valid
                               && restart_cache_level == lv
                               && !practice_point_count);

    h = lvl_height[lv];

    /*
     * Where the level sits in the tilemap. The grid is (height + ground) rows
     * of metatiles = twice that in tiles, and the 64-row record shows its
     * BOTTOM 64 tile rows - so a level taller than 32 metatile rows is clipped
     * at the top until vertical row streaming exists.
     *
     * level_scroll_origin is the pixel offset from the collision window's
     * origin to the top of what the tilemap shows, which set_scroll_y()
     * subtracts. The level is bottom-aligned in the 60-row window, so its own
     * top edge is (60 - GROUND_ROWS - height) rows down, and the record may
     * start further down still.
     */
    grid_rows = (uint16_t)((h + GROUND_ROWS) << 1);
    level_tile_start = (grid_rows > COL_WORDS)
                     ? (uint16_t)(grid_rows - COL_WORDS) : 0;
    vertical_level = (uint8_t)(level_tile_start != 0);
    level_scroll_origin =
        (uint16_t)((uint16_t)(COLL_PAGES * COLL_ROWS - GROUND_ROWS - h) * 16
                   + level_tile_start * 8);
    level_map_origin_tile = (uint8_t)(level_scroll_origin >> 3);
    for (r = 0; r < COL_WORDS; r++)
        map_world_row[r] = (uint8_t)(level_map_origin_tile + r);

    spawn_y_pos = (uint16_t)((uint16_t)lvl_spawn_y_hi[lv] << 8);
    spawn_scroll_y_pos = (uint16_t)(0x0200 | lvl_spawn_scroll_y_lo[lv]);
    spawn_linear = (uint16_t)(2 * 240 + lvl_spawn_scroll_y_lo[lv]);
    vertical_visible_first = (uint8_t)(spawn_linear >> 3);
    vertical_visible_last = (uint8_t)((spawn_linear + 223) >> 3);
    vertical_stream_ready = 1;

    /* The NES loader consumes this byte directly from the 13-byte level
       header.  The SNES tables used to omit it and left `song` at BSS zero,
       making every one of the 168 levels start track zero. */
    song = lvl_song[lv];
    gamemode = (uint8_t)(lvl_gamemode_speed[lv] & 0x0F);
    speed = (uint8_t)(lvl_gamemode_speed[lv] >> 4);

    /* Bit 0 is the parallax-disable flag, the rest is force_platformer. */
    force_platformer = (uint8_t)(lvl_platformer_parallax[lv] & 1);
    no_parallax = (uint8_t)(lvl_platformer_parallax[lv] >> 1);

    /*
     * Bit 7 is the max-fall-speed flag, the rest is the DECORATION CHR BANK.
     *
     * This field went unread until the sprite CHR became switchable, and zero is
     * not a harmless default for it: state_game asks for
     * mmc3_set_2kb_chr_bank_1(current_deco_type) every other frame, so with 0 the
     * game requested CHR bank 0 - which is a background tileset, not sprite art.
     */
    max_fallspeed_7 = (uint8_t)(lvl_fallspeed_deco[lv] >> 7);
    current_deco_type = (uint8_t)(lvl_fallspeed_deco[lv] & 0x7F);

    /* High nibble the spike set, low nibble the block set - both 1KB CHR bank
       numbers for the BACKGROUND. The game reads these for other decisions too;
       set_bg_tileset below is what puts the art in VRAM. */
    current_spike_set = (uint8_t)(lvl_spike_block[lv] >> 4);
    current_block_set = (uint8_t)(lvl_spike_block[lv] & 0x0F);

    /*
     * The level's own BG art and its own two colours.
     *
     * Neither was applied before: the ROM carried stereomadness's tileset alone
     * and the palette baked with its colours, so 36 of the 46 levels drew the
     * right shapes from the wrong tiles. tools/gen_bgchr.py collapses the set to
     * the ten combinations actually used and lvl_bg_tileset indexes them.
     */
    set_bg_tileset(lvl_bg_tileset[lv]);
    set_level_colors(lvl_bg_color[lv], lvl_ground_color[lv]);

    /*
     * How far up the camera may travel. This is the TRUE top of the level, not
     * the top of the 64-row tilemap snapshot.
     *
     * The old clamp used level_scroll_origin, which also contains
     * level_tile_start*8. Theory of Everything is 57 metatiles tall, so that
     * deliberately stopped its camera 448px below the NES ceiling to hide the
     * clipped rows. The tilemap is now a vertical ring; underflow relative to
     * level_scroll_origin is the intended SNES wrap and rows are replaced as
     * they enter.
     */
    {
        uint16_t top =
            (uint16_t)(COLL_PAGES * COLL_ROWS - GROUND_ROWS - h) * 16;
        min_scroll_y = (uint16_t)(((top / 240) << 8) | (top % 240));
    }

    load_ground(0);
}

/*
 * Skip forward N columns without drawing, to restart from a practice point.
 * With a precomputed stream this is just moving the cursor; the original had to
 * actually run the RLE decoder to get there.
 */
void dummy_unrle_columns(uint16_t columns)
{
    uint16_t c;

    if (columns > level_columns_count)
        columns = level_columns_count;
    /*
     * With a precomputed stream this was a cursor move. With a real decoder it
     * has to decode its way there, exactly as the original did - the RLE has no
     * random access, and a run can span a column boundary.
     */
    rle_rewind();
    for (c = 0; c < (uint16_t)(columns >> 1); c++)
        decode_metatile_column(c);
    rld_column = columns;
}

/*
 * Decode the ground strip. From _load_ground in nesdash.s.
 *
 * RLE, filling exactly 48 bytes (3 rows x 16 columns):
 *   b & 0x80  -> one metatile, (b & 0x7F)
 *   otherwise -> b is a run count, the next byte is the value, repeated b+1
 *                times
 * The original notes the worst case is 96 bytes of input for 48 of output, so
 * it never checks for overflow; the bound here is the output, same as there.
 *
 * `ground` is a real C pointer table (`const unsigned char * const ground[]`),
 * so it is not affected by the 16-bit-pointer problem in docs/HANDOFF.md trap
 * 28 - the compiler builds these pointers itself.
 */
extern const unsigned char *const ground[];

void load_ground(uint8_t ground_num)
{
    const uint8_t *p = (const uint8_t *)ground[ground_num];
    uint8_t out = 0;

    while (out < sizeof(ground_strip)) {
        uint8_t b = *p++;
        if (b & 0x80) {
            ground_strip[out++] = (uint8_t)(b & 0x7F);
        } else {
            uint8_t value = *p++;
            uint8_t n = (uint8_t)(b + 1);
            while (n-- && out < sizeof(ground_strip))
                ground_strip[out++] = value;
        }
    }
}

/*
 * Reset the active-sprite table. From _init_sprites in nesdash.s, whose first
 * act is to fill activesprites_type with $FF - "clear sprites to load them".
 *
 * This matters more than it looks: draw_sprites.h walks all max_loaded_sprites
 * entries every frame, so an uninitialised table draws phantom objects from
 * whatever was in RAM. The symptom is a stray 16x16 sprite pinned at x=0 that
 * looks exactly like a second player.
 *
 * The rest of the original - walking the level's sprite data to load the
 * objects that start on screen - is NOT done here. It needs the level's sprite
 * stream, which this port does not decode yet; see check_spr_objects below.
 */
#define MAX_LOADED_SPRITES 16

extern uint8_t activesprites_type[MAX_LOADED_SPRITES];
extern uint8_t activesprites_active[MAX_LOADED_SPRITES];
extern uint8_t activesprites_activated[MAX_LOADED_SPRITES];
extern uint8_t activesprites_animated[MAX_LOADED_SPRITES];
extern uint8_t activesprites_anim_frame[MAX_LOADED_SPRITES];

void init_sprites(void)
{
    uint8_t i;

    sprite_cursor = 0;
    sprite_stream_done = 0;
    for (i = 0; i < MAX_LOADED_SPRITES; i++) {
        activesprites_type[i] = 0xFF;       /* $FF = empty slot */
        activesprites_active[i] = 0;
        activesprites_activated[i] = 0;
        activesprites_animated[i] = 0;
        activesprites_anim_frame[i] = 0;
    }
}

/* ======================================================================== */
/* Level sprite objects - coins, orbs, pads, portals                        */
/* ======================================================================== */
/*
 * From load_next_sprite and check_spr_objects in nesdash.s.
 *
 * The level's sprite stream is 5 bytes per object - x_lo, x_hi, y_lo, y_hi,
 * id - terminated by 0xFF in the first byte, walked with a cursor. 16 slots are
 * live at once; as one scrolls off the left its slot is refilled from the
 * stream. Because the stream is in x order and the camera only moves right, one
 * cursor is enough.
 *
 * The port reads the stream from ROM (tools/gen_assets.py emits it) rather than
 * through the NES's sprite_data pointer + bank, which this build does not set up.
 */
/* The level's sprite-object stream, from the concatenated blob. */
#define level_sprite_data (level_spr_ptr[current_level])

extern uint8_t activesprites_x_lo[MAX_LOADED_SPRITES];
extern uint8_t activesprites_x_hi[MAX_LOADED_SPRITES];
extern uint8_t activesprites_y_lo[MAX_LOADED_SPRITES];
extern uint8_t activesprites_y_hi[MAX_LOADED_SPRITES];
extern uint8_t activesprites_realx[MAX_LOADED_SPRITES];
extern uint8_t activesprites_realy[MAX_LOADED_SPRITES];
extern uint8_t animating;
extern uint16_t scroll_y;

uint16_t calculate_linear_scroll_y(uint16_t nonlinearScroll);

/* Coins animate off-screen, so they are exempt from the vertical cull. */
static uint8_t is_coin(uint8_t type)
{
    return (uint8_t)(type == 0x07 || type == 0x1A || type == 0x1B);
}

static void load_next_sprite(uint8_t slot)
{
    const uint8_t *p;

    if (sprite_stream_done)
        return;
    p = &level_sprite_data[sprite_cursor];
    if (p[0] == 0xFF) {                 /* end of stream */
        sprite_stream_done = 1;
        return;
    }
    activesprites_x_lo[slot] = p[0];
    activesprites_realx[slot] = p[0];
    activesprites_x_hi[slot] = p[1];
    activesprites_y_lo[slot] = p[2];
    activesprites_realy[slot] = p[2];
    activesprites_y_hi[slot] = p[3];
    activesprites_type[slot] = p[4];
    activesprites_activated[slot] = 0;
    activesprites_animated[slot] = 0;
    sprite_cursor = (uint16_t)(sprite_cursor + 5);
}

void check_spr_objects(void)
{
    /*
     * 16-bit locals throughout - this is exactly the position arithmetic that
     * trap 56 keeps breaking (see sub_scroll_y and drawplayerone).
     */
    uint16_t realScrollY = calculate_linear_scroll_y(scroll_y);
    uint16_t sx = (uint16_t)(scroll_x & 0xFFFF);
    uint16_t i = MAX_LOADED_SPRITES;

    /*
     * The counter is uint16_t, and counting down with `while (i--)` rather than
     * `for (int8_t i = 15; i >= 0; i--)`. With a signed char index Calypsi
     * sign-extends it - `lda 10,s / eor ##128 / and ##255 / sec / sbc ##128 /
     * tax` - separately before EVERY array access, eight times per slot, 128
     * times per frame. As a plain 16-bit value the index is already in the form
     * the indexed addressing modes want.
     */
    while (i--) {
        uint8_t type = activesprites_type[i];
        uint16_t spx = (uint16_t)(activesprites_x_lo[i]
                                  | ((uint16_t)activesprites_x_hi[i] << 8));
        uint16_t spy;
        uint16_t dx, dy;

        /* Retired, or scrolled off the left: refill the slot from the stream. */
        if (type == 0xFF || (int16_t)(spx - sx) < 0) {
            if (is_coin(type))
                animating = 0;
            load_next_sprite((uint8_t)i);
            activesprites_active[i] = 0;
            continue;
        }

        dx = (uint16_t)(spx - sx);
        if (dx > 0xFF) {                /* still off to the right */
            activesprites_active[i] = 0;
            continue;
        }

        /*
         * The Y position is read HERE, not with the X above: this runs for all
         * 16 slots every frame and most of them fail the X test, so reading
         * y_lo and y_hi up front is two long-indexed loads and their index
         * setup thrown away per slot.
         */
        spy = (uint16_t)(activesprites_y_lo[i]
                         | ((uint16_t)activesprites_y_hi[i] << 8));

        /* The original subtracts one extra here - `clc` before `sbc` - to sit
           the objects a pixel higher. Keep it. */
        dy = (uint16_t)(spy - realScrollY - 1);
        activesprites_realy[i] = (uint8_t)dy;

        if (dy > 0xFF && !(animating && is_coin(type))) {
            activesprites_active[i] = 0;
            continue;
        }

        activesprites_realx[i] = (uint8_t)dx;
        activesprites_active[i] = 1;
    }
}

/* ======================================================================== */
/* The player sprite                                                        */
/* ======================================================================== */
/*
 * From _drawplayerone in nesdash.s.
 *
 * The original picks a sprite table out of sprite_table_table_lo/hi, indexed by
 * mini*12 + gamemode (+24 in retro mode), then runs a per-gamemode arm to work
 * out which frame of that table to draw and which flips to apply. This is that,
 * as a table plus a switch.
 *
 * Until M2.13 only the cube arm existed and every other gamemode fell back to
 * it - which is why the ship portal changed the physics but the player stayed a
 * cube.
 *
 * Metasprites[] and the per-gamemode sprite tables are real C pointer arrays
 * (`const unsigned char * const []`), so Calypsi builds proper 24-bit pointers
 * for them and docs/HANDOFF.md trap 28 does NOT apply here. That trap is only
 * about raw byte tables holding 16-bit addresses.
 */
extern const unsigned char *const CUBE[];
extern const unsigned char *const SHIP[];
extern const unsigned char *const BALL[];
extern const unsigned char *const UFO[];
extern const unsigned char *const ROBOT[];
extern const unsigned char *const SPIDER[];
extern const unsigned char *const WAVE[];
extern const unsigned char *const SWING[];
extern const unsigned char *const POGO[];
extern const unsigned char *const SNAKE[];
extern const unsigned char *const MINI_CUBE[];
extern const unsigned char *const MINI_SHIP[];
extern const unsigned char *const MINI_BALL[];
extern const unsigned char *const MINI_UFO[];
extern const unsigned char *const MINI_ROBOT[];
extern const unsigned char *const MINI_SPIDER[];
extern const unsigned char *const MINI_WAVE[];
extern const unsigned char *const MINI_SWING[];
extern const unsigned char *const MINI_POGO[];
extern const unsigned char *const MINI_SNAKE[];
extern const unsigned char *const ROBOT_ALT[];
extern const unsigned char *const SPIDER_ALT[];
extern const unsigned char *const MINI_BALL_ALT[];
extern const unsigned char *const MINI_ROBOT_ALT[];
extern const unsigned char *const MINI_SPIDER_ALT[];
extern const unsigned char *const MINI_SWING_ALT[];
/* The jump frames. On the NES these are read by indexing PAST the end of the
   walk table - ROBOT_JUMP[x] is spelled ROBOT[x + 20] - which only works
   because cc65 lays the two arrays out adjacently. Nothing guarantees that
   here, so they are named and indexed properly; see player_frame_robot(). */
extern const unsigned char *const MINI_ROBOT_JUMP[];
extern const unsigned char *const MINI_ROBOT_JUMP_ALT[];

/*
 * Player two's own art. Every gamemode has a second recoloured set, and
 * _drawplayertwo in nesdash.s selects from its own copy of
 * sprite_table_table_lo/hi holding these rather than player one's.
 *
 * FOUR of the retro-mini entries are NOT the "2" variants - MINI_BALL_ALT,
 * MINI_ROBOT_ALT, MINI_SPIDER_ALT and MINI_SWING_ALT are player one's arrays,
 * used verbatim in player two's table. There is no MINI_*_ALT2 in sprites.h to
 * use instead, so this is the original's own table and not a transcription
 * slip; the tables below reproduce it.
 */
extern const unsigned char *const CUBE2[];
extern const unsigned char *const SHIP2[];
extern const unsigned char *const BALL2[];
extern const unsigned char *const UFO2[];
extern const unsigned char *const ROBOT2[];
extern const unsigned char *const SPIDER2[];
extern const unsigned char *const WAVE2[];
extern const unsigned char *const SWING2[];
extern const unsigned char *const POGO2[];
extern const unsigned char *const SNAKE2[];
extern const unsigned char *const MINI_CUBE2[];
extern const unsigned char *const MINI_SHIP2[];
extern const unsigned char *const MINI_BALL2[];
extern const unsigned char *const MINI_UFO2[];
extern const unsigned char *const MINI_ROBOT2[];
extern const unsigned char *const MINI_SPIDER2[];
extern const unsigned char *const MINI_WAVE2[];
extern const unsigned char *const MINI_SWING2[];
extern const unsigned char *const MINI_POGO2[];
extern const unsigned char *const MINI_SNAKE2[];
extern const unsigned char *const ROBOT_ALT2[];
extern const unsigned char *const SPIDER_ALT2[];
extern const unsigned char *const MINI_ROBOT_JUMP2[];

extern uint8_t cube_data[2];
extern uint8_t slope_frames[2];
extern uint8_t slope_type[2];
extern uint8_t player_gravity[2];
extern uint8_t player_mini[2];
extern uint16_t player_x[2];
extern uint16_t player_y[2];
extern uint16_t cube_rotate[2];
extern int16_t player_vel_y[2];
extern int16_t player_vel_x[2];
extern uint8_t spiderframe[2];
extern uint8_t robotframe[2];
extern uint8_t robotjumpframe[2];
extern uint8_t ballframe;
extern uint8_t chargepower[2];
extern uint8_t orbed[2];
extern uint8_t was_on_slope_counter[2];
extern uint8_t retro_mode;
extern uint8_t options;
extern uint8_t skipProcessingCubeRotationLogic;

#define GM_CUBE 0
#define GM_SHIP 1
#define GM_BALL 2
#define GM_UFO 3
#define GM_ROBOT 4
#define GM_SPIDER 5
#define GM_WAVE 6
#define GM_SWING 7
#define GM_NINJA 8
#define GM_POGO 9
#define GM_SNAKE 10
#define GM_FOOTBALL 11
#define GAMEMODE_COUNT 12

#define OPT_PLATFORMER 0x04

/*
 * sprite_table_table_lo/hi in nesdash.s, as one array of pointers-to-tables.
 * Four rows of 12 per player: normal, mini, retro-normal, retro-mini. Ninja and
 * football share the cube's art, and swing shares the ship's frame logic but has
 * its own table.
 *
 * Player one's four rows come first, then player two's - _drawplayertwo keeps
 * its own copy of the table and the two are NOT the same shape. Besides the "2"
 * art, player two's retro row sends the ninja to the cube where player one's
 * sends it to ROBOT_ALT; that is the table half of the dispatch difference in
 * drawplayer(), where only player one routes a retro ninja through the robot.
 *
 * Flat rather than [2][48] so the row base is one 16-bit value.
 */
#define PLAYER_TABLE_ROWS (4 * GAMEMODE_COUNT)
static const unsigned char *const *const player_tables[2 * PLAYER_TABLE_ROWS] = {
    /* ---- player one ---------------------------------------------------- */
    /* Cub   Shp   Bal   UFO   RBT    SPI     Wav   Sng    Nja   Pgo   Snk    Ftb */
    CUBE, SHIP, BALL, UFO, ROBOT, SPIDER, WAVE, SWING, CUBE, POGO, SNAKE, CUBE,
    MINI_CUBE, MINI_SHIP, MINI_BALL, MINI_UFO, MINI_ROBOT, MINI_SPIDER,
    MINI_WAVE, MINI_SWING, MINI_CUBE, MINI_POGO, MINI_SNAKE, MINI_CUBE,
    /* retro */
    CUBE, SHIP, BALL, UFO, ROBOT_ALT, SPIDER_ALT, WAVE, SWING, ROBOT_ALT,
    POGO, SNAKE, CUBE,
    MINI_CUBE, MINI_SHIP, MINI_BALL_ALT, MINI_UFO, MINI_ROBOT_ALT,
    MINI_SPIDER_ALT, MINI_WAVE, MINI_SWING_ALT, MINI_ROBOT_ALT, MINI_POGO,
    MINI_SNAKE, MINI_CUBE,
    /* ---- player two ---------------------------------------------------- */
    CUBE2, SHIP2, BALL2, UFO2, ROBOT2, SPIDER2, WAVE2, SWING2, CUBE2, POGO2,
    SNAKE2, CUBE2,
    MINI_CUBE2, MINI_SHIP2, MINI_BALL2, MINI_UFO2, MINI_ROBOT2, MINI_SPIDER2,
    MINI_WAVE2, MINI_SWING2, MINI_CUBE2, MINI_POGO2, MINI_SNAKE2, MINI_CUBE2,
    /* retro */
    CUBE2, SHIP2, BALL2, UFO2, ROBOT_ALT2, SPIDER_ALT2, WAVE2, SWING2, CUBE2,
    POGO2, SNAKE2, CUBE2,
    MINI_CUBE2, MINI_SHIP2, MINI_BALL_ALT, MINI_UFO2, MINI_ROBOT_ALT,
    MINI_SPIDER_ALT, MINI_WAVE2, MINI_SWING_ALT, MINI_CUBE2, MINI_POGO2,
    MINI_SNAKE2, MINI_CUBE2,
};

/*
 * Rotation step -> sprite index plus flip bits. Bits 6-7 are the flip flags,
 * bits 0-2 the index; the cube has 7 drawn frames and the other 17 of its 24
 * steps are those seven mirrored.
 *
 * THREE tables, laid out end to end exactly as nesdash.s has them, because the
 * original INDEXES PAST THE END of the first one. The slope adjustment below
 * can push the index past 23, and `LDA drawcube_sprite_table, X` then reads on
 * into drawcube_sprite_way. Splitting them into three C arrays would change
 * what those reads return, so they stay one array (docs/HANDOFF.md trap 70 -
 * the same shape as the robot's jump frames).
 *
 *   0..23   drawcube_sprite_table   the normal icon
 *  24..47   drawcube_sprite_way     icon 2 mirrors the other way
 *  48..71   drawcube_sprite_none    icons $0F, $12, $16 do not mirror at all
 */
#define NOFLIP 0x00
#define H_FLIP 0x40
#define V_FLIP 0x80
#define HVFLIP 0xC0
#define CUBE_TABLE_NORMAL 0
#define CUBE_TABLE_WAY   24
#define CUBE_TABLE_NONE  48
static const uint8_t cube_frame_table[72] = {
    /* drawcube_sprite_table */
    NOFLIP|0, NOFLIP|1, NOFLIP|2, NOFLIP|3, NOFLIP|4, NOFLIP|5,
    NOFLIP|6, V_FLIP|5, V_FLIP|4, V_FLIP|3, V_FLIP|2, V_FLIP|1,
    HVFLIP|0, HVFLIP|1, HVFLIP|2, HVFLIP|3, HVFLIP|4, HVFLIP|5,
    HVFLIP|6, H_FLIP|5, H_FLIP|4, H_FLIP|3, H_FLIP|2, H_FLIP|1,
    /* drawcube_sprite_way */
    NOFLIP|0, NOFLIP|1, NOFLIP|2, NOFLIP|3, NOFLIP|4, NOFLIP|5,
    NOFLIP|6, H_FLIP|5, H_FLIP|4, H_FLIP|3, H_FLIP|2, H_FLIP|1,
    H_FLIP|0, HVFLIP|1, HVFLIP|2, HVFLIP|3, HVFLIP|4, HVFLIP|5,
    V_FLIP|6, V_FLIP|5, V_FLIP|4, V_FLIP|3, V_FLIP|2, V_FLIP|1,
    /* drawcube_sprite_none */
    NOFLIP|0, NOFLIP|1, NOFLIP|2, NOFLIP|3, NOFLIP|4, NOFLIP|5,
    NOFLIP|6, NOFLIP|1, NOFLIP|2, NOFLIP|3, NOFLIP|4, NOFLIP|5,
    NOFLIP|6, NOFLIP|1, NOFLIP|2, NOFLIP|3, NOFLIP|4, NOFLIP|5,
    NOFLIP|6, NOFLIP|1, NOFLIP|2, NOFLIP|3, NOFLIP|4, NOFLIP|5,
};

/*
 * Snap the rotation to the nearest sixth of a turn when the player is grounded.
 * Twelve entries, indexed by (step >= 12 ? step - 12 : step) - the original
 * writes it out twice so the routine does not need the conditional, but the
 * effect is that index, and the thirteenth byte wraps a full turn back to zero.
 */
static const int8_t cube_rounding_table[13] = {
    0, -1, -2, 3, 2, 1, 0, -1, -2, 3, 2, 1,
    /*
     * THIRTEENTH ENTRY, and it is reachable - an earlier version of this table
     * stopped at twelve on the belief that it was not.
     *
     * Rounding up from step 21, 22 or 23 gives 24: a whole turn, which is the
     * same orientation as 0 but is not stored as 0. On the NEXT grounded frame
     * that step indexes here, at 24 - 12 = 12, and -24 is what brings it back
     * to zero. Without the entry the index runs one past the array, the step
     * becomes whatever byte follows it, and the cube settles at an arbitrary
     * angle instead of flat - which is only visible when it happens to land in
     * the top quarter of the wheel.
     */
    -24
};

/*
 * Extra rotation for a cube sitting on a slope, from rounding_slope_table,
 * indexed by slope_type - 1. This one is added to the DRAWN index only: the
 * original stores the rounded rotation first and adds this afterwards, so it
 * never accumulates.
 */
static const uint8_t cube_slope_rounding[15] = {
    /*  45v   22v   66v   45^   22^   66^   none        */
    0x09, 0x08, 0x09, 0x00, 0x03, 0x04, 0x08, 0x00,
    0x09, 0x16, 0x1A, 0x00, 0x03, 0x1A, 0x17,   /* upside down */
};

/*
 * How fast the cube spins in the air. THIS IS A FRACTION, and getting that
 * wrong is why the cube span about two and a half times too fast: cube_rotate
 * is 16-bit fixed point, its LOW byte accumulating CUBE_GRAVITY every frame and
 * its high byte - the 0..23 step actually drawn - advancing only when it
 * carries.
 * Stepping the high byte directly turns a ~57-frame revolution into a 24-frame
 * one.
 *
 * The low bytes of the CUBE_GRAVITY table, indexed by framerate * 4 as
 * nesdash.s does. At framerate 1 that is 107, so a step every 256/107 = 2.4
 * frames and a full turn in about a second.
 */
extern uint8_t framerate;
extern const uint8_t CUBE_GRAVITY_lo[];

/* Which flip pattern the icon wants; gameState 1 is STATE_MENU. */
extern uint8_t gameState;
extern uint8_t icon;
extern uint8_t titleicon;

/*
 * Where the sprite's origin sits relative to the player, per gamemode. Two
 * rows of 12: normal size then mini, exactly as drawplayer_center_offsets in
 * nesdash.s. Indexing this with anything other than mini*12 + gamemode puts the
 * player half a tile out.
 */
static const uint8_t center_offsets[24] = {
    /* Cub Shp Bal UFO RBT SPI Wav Sng Nja Pgo Snk Ftb */
        8,  8,  8,  8,  4,  4,  8,  8,  8,  8,  8,  8,   /* normal */
        4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,   /* mini   */
};

/* ---- the per-gamemode frame arms, from the drawplayer switches ---------- */

/*
 * WHICH PLAYER IS BEING DRAWN, and it is a file-scope variable on purpose.
 *
 * Everything below reads it instead of taking a parameter. The long comment in
 * drawplayer() explains why: an argument that has to survive a switch and a
 * dozen merges is exactly what Calypsi 5.18 loses, and it would be lost in the
 * same silent way player_draw_px was - a plausible sprite drawn from the wrong
 * player's state, with the build scanning clean.
 *
 * uint16_t, not uint8_t: a byte used as an array subscript can compile to a
 * SIGN extension (trap 94), and a 16-bit index cannot.
 */
static uint16_t player_draw_p;

/*
 * Set by the robot arm when the frame comes from a separate jump table rather
 * than from the gamemode's own. File-scope for the same reason as above, and so
 * the arms need no out-parameter.
 */
static const unsigned char *const *player_draw_jump;

/*
 * Ship and swing. The tilt is the vertical velocity mapped onto the 8 frames:
 * `cube_rotate = 0x0400 - vel_y`, clamped to 0..0x07FF, and the frame is its
 * high byte - mirrored when gravity is inverted.
 *
 * 16-bit throughout, and the clamp compares the whole word rather than its high
 * byte: this is exactly the shape of trap 56, and getting it wrong points the
 * ship at a frame index far outside the 8-entry table.
 */
static uint8_t player_frame_ship(uint8_t is_wave)
{
    uint16_t p = player_draw_p;
    uint16_t rot = (uint16_t)(0x0400 - (uint16_t)player_vel_y[p]);
    uint8_t hi = (uint8_t)(rot >> 8);
    uint8_t idx;

    /*
     * The ship and the wave clamp the OPPOSITE way, and that is not a typo
     * here - it is in nesdash.s. The two arms are otherwise the same code, the
     * same comment sits above both, and the only difference is one branch:
     *
     *     ship:   CMP #$80 / BCS :+      high >= $80 -> 0x0000, else 0x07FF
     *     wave:   CMP #$80 / BCC :+      high >= $80 -> 0x07FF, else 0x0000
     *
     * The ship's is the continuous one; the wave's snaps to the other extreme.
     * One of them is presumably a bug in the original, but the port's job is to
     * match, so both are reproduced. This function drew BOTH with the ship's
     * rule, so the wave and the snake showed the wrong extreme frame whenever
     * they saturated - and they saturate constantly.
     *
     * Reachable in both gravity directions: the velocity clamp puts `hi` at
     * exactly $08 at maximum rise and $FF at maximum fall.
     */
    if (hi >= 0x08) {
        if (is_wave)
            rot = (hi >= 0x80) ? 0x07FF : 0x0000;
        else
            rot = (hi >= 0x80) ? 0x0000 : 0x07FF;
    }
    cube_rotate[p] = rot;
    idx = (uint8_t)(rot >> 8);

    /*
     * The wave arm has one extra step the ship does not: above speed x3 the
     * sprite would come out mirrored, so a non-mini wave flips back.
     *
     * The speed read is player ONE's in both routines - _drawplayertwo reads
     * `_player_vel_x+1`, the high byte of player_vel_x[0], not player two's.
     * Both players move at the level's speed, so it makes no difference; it is
     * indexed [0] here to match rather than "corrected".
     */
    if (is_wave && !player_mini[p]
        && (uint16_t)((uint16_t)player_vel_x[0] >> 8) >= 0x04)
        idx = (uint8_t)(7 - idx);

    if (player_gravity[p])
        idx = (uint8_t)(7 - idx);
    return (uint8_t)(idx & 7);
}

static uint8_t player_frame_wave(void)
{
    return player_frame_ship(1);
}

/*
 * Ball. In platformer mode a stationary ball stops rolling; otherwise the frame
 * counter advances every frame and wraps at 8.
 *
 * PLAYER TWO'S ARM ONLY READS THE COUNTER. It does not advance it and does not
 * reset it, and it tests `options & platformer` without the force_platformer
 * half - all three straight out of _drawplayertwo, which is a cut-down copy.
 * There is one ballframe for both players, so a second increment here would
 * spin the ball at twice its rate whenever dual is on.
 */
static uint8_t player_frame_ball(void)
{
    uint8_t frame;
    uint8_t stopped = 0;

    if (player_draw_p) {
        if ((options & OPT_PLATFORMER) && player_vel_x[0] == 0)
            stopped = 1;
        if (stopped)
            return 0;
        return ballframe;
    }

    if (((options & OPT_PLATFORMER) || force_platformer) && player_vel_x[0] == 0) {
        ballframe = 0;
        return 0;
    }
    frame = ballframe;
    ballframe = (uint8_t)((ballframe + 1) & 7);
    return frame;
}

/* UFO: three frames - level, rising, falling. */
static uint8_t player_frame_ufo(void)
{
    int16_t vy = player_vel_y[player_draw_p];

    if (vy == 0)
        return 0;
    return (uint8_t)(vy < 0 ? 2 : 1);
}

/*
 * Pogo: two frames, the second while a jump is in progress - and the jump
 * counter is DECREMENTED here, which is what ends the animation. Leaving the
 * decrement out (as this did) leaves a pogo that has jumped once stuck on its
 * second frame for as long as nothing else clears the counter.
 */
static uint8_t player_frame_pogo(void)
{
    uint16_t p = player_draw_p;

    if (robotjumpframe[p] == 0)
        return 0;
    robotjumpframe[p] = (uint8_t)(robotjumpframe[p] - 1);
    return 1;
}

/*
 * Robot. Walking, unless airborne - and `was_on_slope_counter` suppresses the
 * jump frame so running over a slope does not flicker into it.
 *
 * The walk cycle is 20 frames normally and 15 in retro mode; a stationary robot
 * in platformer mode resets to frame 0.
 *
 * ROBOT and ROBOT_ALT (and their "2" variants) carry their five jump frames at
 * index 20, which is what `LDA #21 / ADC _robotjumpframe` reaches - so the
 * airborne frame is 20 + jump, NOT the bare jump index. Returning the bare index
 * drew ROBOT[0..4], the standing walk frame, for every airborne non-mini robot.
 * MINI_ROBOT* is 20 entries with no jump frames appended - on the NES the read
 * ran off the end into an array cc65 happened to place next to it - so the mini
 * arm names the jump table instead.
 */
static uint8_t player_frame_robot(void)
{
    uint16_t p = player_draw_p;
    uint8_t frame;
    uint8_t jump;
    uint8_t limit;

    if (!was_on_slope_counter[p] && player_vel_y[p] != 0) {
        /*
         * robotjumpframe is read at index 0 for BOTH players: _drawplayertwo's
         * @jump is `ADC _robotjumpframe`, not `+1`. Same for the walk counter
         * below. Copy-paste in the original, harmless in effect (the two robots
         * animate in step) and reproduced rather than fixed.
         */
        jump = robotjumpframe[0];
        if (jump > 4)
            jump = 4;
        if (player_mini[p]) {
            if (p) {
                /*
                 * Player two's retro-mini row is MINI_ROBOT_ALT - player ONE's
                 * array, see player_tables - so its jump frames are the ALT set
                 * too. Only the non-retro row is the "2" art.
                 */
                if (retro_mode) player_draw_jump = MINI_ROBOT_JUMP_ALT;
                else            player_draw_jump = MINI_ROBOT_JUMP2;
            } else {
                if (retro_mode) player_draw_jump = MINI_ROBOT_JUMP_ALT;
                else            player_draw_jump = MINI_ROBOT_JUMP;
            }
            return jump;
        }
        return (uint8_t)(20 + jump);
    }

    /*
     * Player two's arm has neither the retro branch nor force_platformer: it is
     * `options & platformer` and a 20-frame cycle, full stop. It also tests
     * player two's own X velocity where player one's tests its own.
     */
    if (p) {
        if ((options & OPT_PLATFORMER) && player_vel_x[1] == 0) {
            robotframe[0] = 0;
            return 0;
        }
        limit = 20;
    } else {
        if (!retro_mode && ((options & OPT_PLATFORMER) || force_platformer)
            && player_vel_x[0] == 0) {
            robotframe[0] = 0;
            return 0;
        }
        limit = retro_mode ? 15 : 20;
    }

    frame = robotframe[0];
    robotframe[0] = (uint8_t)(frame + 1);
    if (robotframe[0] >= limit)
        robotframe[0] = 0;
    return frame;
}

/*
 * Spider. 16-frame walk cycle; airborne uses the jump frame at index 16.
 *
 * EVERY spider table is 20 entries - SPIDER, SPIDER_ALT, MINI_SPIDER,
 * MINI_SPIDER_ALT and the "2" variants alike - so 16..19 is in range in all of
 * them and there is no separate jump table to name. The mini arm used to
 * substitute MINI_SPIDER_JUMP, which is right for the plain mini spider and
 * draws the wrong frame in retro mode, where the table is MINI_SPIDER_ALT.
 */
static uint8_t player_frame_spider(void)
{
    uint16_t p = player_draw_p;
    uint8_t frame;

    if (player_vel_y[p] != 0)
        return (uint8_t)(16 + (robotjumpframe[0] & 3));

    /* Both arms test player one's X velocity - `LDA _player_vel_x` in both. */
    if (p) {
        if ((options & OPT_PLATFORMER) && player_vel_x[0] == 0) {
            /* and _drawplayertwo resets index 0's counter, not its own */
            spiderframe[0] = 0;
            return 0;
        }
        frame = spiderframe[1];
        spiderframe[1] = (uint8_t)((frame + 1) & 0x0F);
        return frame;
    }

    if (((options & OPT_PLATFORMER) || force_platformer) && player_vel_x[0] == 0) {
        spiderframe[0] = 0;
        return 0;
    }
    frame = spiderframe[0];
    spiderframe[0] = (uint8_t)((frame + 1) & 0x0F);
    return frame;
}

/*
 * Football's charge meter picks the rotation directly while the player is
 * grounded: the harder the charge, the further back the cube is wound. The two
 * routines use DIFFERENT thresholds - player two's are roughly half player
 * one's - so this is a row per player, not a shared table.
 */
static const uint8_t football_charge[2][5] = {
    { 10, 20, 30, 38, 50 },
    {  5, 15, 25, 30, 46 },
};
static const uint8_t football_step[5] = { 23, 22, 21, 20, 20 };

/*
 * Cube. Returns the raw entry from cube_frame_table: flip flags in bits 6-7 and
 * the frame index in bits 0-2, which is how the original packs it. The caller
 * splits them, and unlike every other gamemode the cube REPLACES the gravity
 * flip rather than adding to it.
 */
static uint8_t player_frame_cube(void)
{
    uint16_t p = player_draw_p;
    uint16_t rot = cube_rotate[p];
    uint16_t step = (uint16_t)(rot >> 8);       /* the 0..23 step being drawn */
    uint16_t drawn = step;
    uint16_t table;
    uint8_t  do_round = 0;      /* nesdash.s' @round  - snap to a sixth */
    uint8_t  do_spin  = 0;      /* nesdash.s' @no_round -> @normalstuff */

    /*
     * The label order in nesdash.s, and it matters: the slope test comes FIRST,
     * so a football player on a slope is rounded before the charge arm runs.
     */
    if (cube_data[p] & 0x80) {
        do_round = 1;
    } else if (p == 0 && skipProcessingCubeRotationLogic) {
        /* Drawing a trail copy - do not spin. Player two has no trails: the
           equivalent two lines are commented out in _drawplayertwo. */
        do_round = 0;
    } else if (gamemode == GM_FOOTBALL && player_vel_y[p] == 0) {
        /* The football arm zeroes the rotation and then re-enters @no_round. */
        cube_rotate[p] = 0;
        step = 0;
        drawn = 0;
        do_round = 1;
    } else if (player_vel_y[p] == 0) {
        do_round = 1;
    } else {
        do_spin = 1;
    }

    if (do_round) {
        /*
         * Grounded: snap to the nearest sixth of a turn, and clear the
         * fraction. Written (step >= 12 ? step - 12 : step) rather than a
         * clamp - the original doubles the table so it needs no conditional at
         * all, and clamping at 12 instead sticks the top half of the wheel on
         * one entry.
         */
        uint16_t i = step;
        if (step >= 12)
            i = (uint16_t)(step - 12);
        step = (uint16_t)((step + cube_rounding_table[i]) & 0xFF);
        cube_rotate[p] = (uint16_t)(step << 8);

        /*
         * A cube on a slope is drawn turned further, but the STORED rotation
         * stays the rounded one - the original adds this after the store, so it
         * cannot accumulate frame over frame.
         */
        drawn = step;
        if (cube_data[p] & 0x80) {
            uint16_t st = slope_type[p];
            if (st >= 1 && st <= 15)
                drawn = (uint16_t)((drawn + cube_slope_rounding[st - 1]) & 0xFF);
        }

        /* @round ends with `if (gamemode == 11) jmp @no_round`. */
        if (gamemode == GM_FOOTBALL)
            do_spin = 1;
    }

    if (do_spin && gamemode == GM_FOOTBALL) {
        uint8_t handled = 0;

        if (player_vel_y[p] == 0) {
            uint8_t cp = chargepower[p];
            if (orbed[p]) {
                drawn = 6;
                handled = 1;
            } else if (cp != 0) {
                uint16_t k = 0;
                drawn = 6;
                while (k < 5) {
                    if (cp < football_charge[p][k]) {
                        drawn = football_step[k];
                        break;
                    }
                    ++k;
                }
                handled = 1;
            }
        }
        if (handled) {
            cube_rotate[p] = (uint16_t)(drawn << 8);
            do_spin = 0;
        }
        /* Charge 0 and not orbed falls through to the ordinary spin, from 0. */
    }

    if (do_spin) {
        /*
         * Airborne. THE ROTATION IS 16-BIT FIXED POINT: the low byte is a
         * fraction that accumulates CUBE_GRAVITY, and the drawn step advances
         * only when it carries. Adding 1 to the high byte instead is a full
         * step every frame, which is the cube spinning ~2.4x too fast.
         */
        uint16_t g = CUBE_GRAVITY_lo[(framerate << 2) & 7];

        rot = cube_rotate[p];           /* the football arm may have zeroed it */
        if (player_gravity[p]) {
            rot = (uint16_t)(rot - g);
            /* Borrowed out of step 0: the original DECs and tests for negative. */
            if ((uint16_t)(rot >> 8) >= 24)
                rot = (uint16_t)((23 << 8) | (uint8_t)rot);
        } else {
            rot = (uint16_t)(rot + g);
            if ((uint16_t)(rot >> 8) >= 24)
                rot = (uint16_t)((uint8_t)rot);         /* wrap 24 -> 0 */
        }
        cube_rotate[p] = rot;
        drawn = (uint16_t)(rot >> 8);
    }

    /*
     * Which of the three flip patterns. Most icons mirror one way, icon 2
     * mirrors the other, and three icons are drawn with no mirroring at all.
     * gameState 1 is STATE_MENU, which uses its own icon - and only player
     * one's arm looks at it; _drawplayertwo always reads `_icon`.
     */
    {
        uint8_t ic;
        ic = icon;
        if (p == 0) {
            if (gameState == 1)
                ic = titleicon;
        }
        if (ic == 0x0F || ic == 0x12 || ic == 0x16)
            table = CUBE_TABLE_NONE;
        else if (ic == 2)
            table = CUBE_TABLE_WAY;
        else
            table = CUBE_TABLE_NORMAL;
    }

    /* The slope adjustment can push this past 23, and the original lets it read
       on into the next table - which is why they are one array here. */
    if (table + drawn >= 72)
        drawn = (uint16_t)(drawn % 24);
    return cube_frame_table[table + drawn];
}

/*
 * _drawplayerone and _drawplayertwo, as one routine indexed by player_draw_p.
 *
 * The two originals are the same shape and are NOT the same code: player two's
 * is a cut-down copy that has drifted. Every place they differ is marked
 * `player two:` below or in the arm it belongs to, and there are eight -
 * the art tables, the retro ninja dispatch, the snake dispatch, the trail
 * check, the menu icon, the ball counter, the robot's retro branch and the
 * football thresholds. Threading an index through one routine is what the
 * handoff asked for; duplicating it would have meant maintaining both.
 */
static void drawplayer(void)
{
    uint16_t p = player_draw_p;
    uint8_t x, y, frame, flip, table_idx, mode;

    player_draw_jump = 0;

    /* Bit 7 of cube_data records "on a slope"; the rounding uses it. */
    if (slope_frames[p] | slope_type[p])
        cube_data[p] |= 0x80;
    else
        cube_data[p] &= 0x7F;

    y = (uint8_t)((player_y[p] >> 8) - 1);      /* oam_meta_spr wants y - 1 */

    /*
     * The original's guard is "temp_x == 0 or > 0xFC", written as
     * (temp_x - 1) > 0xFB so it is one comparison. It stops a player who has
     * wrapped off the edge being drawn at the wrong side.
     */
    /*
     * NO TERNARIES, NO REGISTER-ALLOCATED LOCALS, AND THE GUARD FIRST.
     *
     * This cost a long session. The obvious form -
     *
     *     uint8_t px = player_x[p] >> 8;
     *     uint8_t off_idx = (mini ? 12 : 0) + (gamemode < 12 ? gamemode : 0);
     *     ...use px...
     *
     * - reads px correctly (instrumented: 80) and then loses it. Evaluating the
     * two ternaries clobbers the register holding px, so by the time the edge
     * guard runs px is 0, the guard fires, and the player is drawn at x = 8
     * instead of 88. That is trap 8 in its register-clobber variant, which
     * scan_stackslots.py cannot see - the build scanned clean throughout.
     *
     * The fix is the same one gamemode_cube.h uses: keep the value in a
     * file-scope temporary the compiler cannot hold in a register across a
     * merge, spell the ternaries out as statements, and apply the guard while
     * the value is still fresh. It is also why player_draw_p is file-scope.
     */
    player_draw_px = (uint8_t)(player_x[p] >> 8);
    {
        /*
         * COMPARE IN 16 BITS. Written the obvious way -
         *     if ((uint8_t)(px - 1) >= 0xFC) px = 1;
         * - Calypsi narrows to an 8-bit SIGNED compare (`sec / sbc #-4` then
         * `bmi`), so 0xFC becomes -4, "79 >= -4" is true, and the guard fires
         * for every ordinary position. The player then draws at x = 8 instead
         * of 88. Widening the operand keeps the comparison unsigned.
         *
         * The condition itself is the original's: px == 0, or px has wrapped
         * past the right edge. The replacement is ONE, not zero: the original
         * decrements before the test and adds the 1 back with the `SEC` in
         * front of the offset add, so a clamped position is 1 + offset.
         */
        uint16_t pxw = player_draw_px;
        if (pxw == 0 || pxw >= 0xFD)
            player_draw_px = 1;
    }

    player_draw_off = gamemode;
    if (player_draw_off >= 12)
        player_draw_off = 0;
    if (player_mini[p])
        player_draw_off = (uint8_t)(player_draw_off + 12);
    player_draw_off = center_offsets[player_draw_off];

    x = (uint8_t)(player_draw_px + player_draw_off);

    /*
     * Gravity flips the sprite vertically for every gamemode EXCEPT the cube,
     * whose arm overwrites the flip byte from its own rotation table rather
     * than OR-ing into it (nesdash.s: `STA xargs+0`, not `ORA`).
     */
    flip = NOFLIP;
    if (player_gravity[p])
        flip = V_FLIP;

    /* Which table, and which frame of it. */
    table_idx = gamemode;
    if (table_idx >= GAMEMODE_COUNT)
        table_idx = GM_CUBE;
    mode = table_idx;
    if (player_mini[p])
        table_idx = (uint8_t)(table_idx + GAMEMODE_COUNT);
    if (retro_mode)
        table_idx = (uint8_t)(table_idx + 2 * GAMEMODE_COUNT);

    if (p) {
        /*
         * player two: SNAKE goes to the POGO arm. `dex / jeq pogo` where
         * _drawplayerone has `jeq wave`. It is almost certainly a slip in the
         * original - the snake is a wave-shaped gamemode - but it is what the
         * NES draws, and a dual snake section would look different if this were
         * "fixed" here and nowhere else.
         */
        if (mode == GM_SNAKE)
            mode = GM_POGO;
    } else {
        /* player one only: retro mode routes the ninja through the robot arm.
           _drawplayertwo has no such prologue - its ninja stays a cube. */
        if (retro_mode && mode == GM_NINJA)
            mode = GM_ROBOT;
    }

    switch (mode) {
    case GM_SHIP:
    case GM_SWING:
        frame = player_frame_ship(0);
        break;
    case GM_WAVE:
    case GM_SNAKE:
        frame = player_frame_wave();
        break;
    case GM_BALL:
        frame = player_frame_ball();
        break;
    case GM_UFO:
        frame = player_frame_ufo();
        break;
    case GM_POGO:
        frame = player_frame_pogo();
        break;
    case GM_ROBOT:
        frame = player_frame_robot();
        break;
    case GM_SPIDER:
        frame = player_frame_spider();
        break;
    default:
        /* Cube, and the gamemodes that share its art: ninja and football. */
        frame = player_frame_cube();
        flip = (uint8_t)(frame & 0xC0);
        frame &= 0x07;
        break;
    }

    /*
     * nesdash.s' `fin`, which every arm passes through: a grounded ninja is
     * stood upright, and the stored rotation is forced to match. It runs after
     * the frame index has been chosen, so it changes the NEXT frame rather than
     * this one - which is why it can sit here rather than inside the cube arm.
     */
    if (gamemode == GM_NINJA && player_vel_y[p] == 0) {
        if (player_gravity[p])
            cube_rotate[p] = 0x0C00;
        else
            cube_rotate[p] = 0x0000;
    }

    /*
     * The walk tables and the mini robot's jump table are separate arrays here.
     * On the NES the jump frame is reached by running off the end of the walk
     * table (`MINI_ROBOT_JUMP[x]` is written `MINI_ROBOT[x + 21]`), which is
     * only well defined because cc65 happens to lay them out adjacently.
     * ROBOT and SPIDER and their variants really do carry their jump frames, so
     * those index in range and the arms return the in-table index.
     */
    if (player_draw_jump)
        oam_meta_spr_flipped(flip, x, y, player_draw_jump[frame]);
    else
        oam_meta_spr_flipped(flip, x, y,
                             player_tables[p * PLAYER_TABLE_ROWS + table_idx][frame]);
}

void drawplayerone(void)
{
    player_draw_p = 0;
    drawplayer();
}

/*
 * Second player, for the dual gamemode.
 *
 * State and call site were both already in place - state_game.h runs player
 * two's whole physics pass under `if (dual)` and writes player_x[1]/player_y[1]
 * back every frame, and draw_sprites.h calls this, alternating the draw order
 * with drawplayerone so neither player permanently wins OAM priority. Only the
 * drawing was missing.
 */
void drawplayertwo(void)
{
    player_draw_p = 1;
    drawplayer();
}
