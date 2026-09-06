/*
 * snes_main_full.c - entry point for the full-game ROM.
 *
 * This drives the game's own STATE_GAME loop rather than the hand-rolled
 * physics loop in snes_main.c, and it plays: the level streams, the player and
 * the level's objects draw, and the pad works. snes_main.c is kept as the
 * minimal physics ROM.
 *
 * See docs/M2_LEVEL_RENDER.md, docs/M2_12_LEVEL_SPRITES.md and
 * docs/M2_13_PLAYER_AND_TEAR.md for what is and is not done.
 */

#include <stdint.h>
#include "shim_sa1.h"
#include "arr_macros.h"
#include "neslib.h"
#include "nesdoug.h"
#include "mapper.h"
#include "nesdash.h"
#include "shim_spc.h"
#include "musicDefines.h"
#include "sfxDefines.h"

#define REG(a) (*(volatile uint8_t *)(a))
#define INIDISP  REG(0x2100)
#define OBSEL    REG(0x2101)
#define BG1SC    REG(0x2107)
#define BG2SC    REG(0x2108)
#define BG12NBA  REG(0x210B)
#define BGMODE   REG(0x2105)
#define SETINI   REG(0x2133)
#define NMITIMEN REG(0x4200)
#define MEMSEL   REG(0x420D)

#define VMAIN    REG(0x2115)
#define VMADDL   REG(0x2116)
#define VMADDH   REG(0x2117)
#define VMDATAL  REG(0x2118)
#define VMDATAH  REG(0x2119)
#define CGADD    REG(0x2121)
#define CGDATA   REG(0x2122)
#define BG1HOFS  REG(0x210D)
#define BG1VOFS  REG(0x210E)
#define BG2HOFS  REG(0x210F)
#define BG2VOFS  REG(0x2110)
#define HVBJOY   REG(0x4212)

#define VRAM_TILES  0x0000
#define VRAM_BG1MAP 0x6000
#define VRAM_OBJ    0x2000
#define VRAM_BG2MAP 0x4000
#define VRAM_BG2TILES 0x5000

/* Converted by tools/snes_m0.py; SNES 2bpp, one tileset. */
extern const uint8_t bg1_tiles[];       /* 4096 bytes, SNES 2bpp */
extern const uint8_t spr_tiles[];       /* 8192 bytes, SNES 4bpp: 256 tiles */
extern const uint8_t menu_tiles[];      /* 4096 bytes, the ASCII-indexed font */
extern const uint8_t parallax_tiles[];  /* 2048 bytes, Mode 1 4bpp BG2 art */
extern const uint8_t parallax_map[];    /* top 4096 bytes of 64x64 motif */
extern const uint8_t parallax_map_bottom[]; /* bottom 4096 bytes */
extern const uint8_t famidash_menu_bg_tiles[];
extern const uint8_t famidash_menu_cursor_tiles[];
extern const uint8_t famidash_menu_demon_tiles[];
extern const uint8_t famidash_end_bg_tiles[];
extern const uint8_t famidash_practice_bg_tiles[];
extern const uint8_t famidash_title_map[];
extern const uint8_t famidash_levelselect_map[];
extern const uint8_t famidash_end_map[];
extern const uint8_t famidash_practice_map[];
extern const uint8_t famidash_level_lines[];
extern const uint8_t famidash_difficulty[];
extern const uint8_t famidash_stars[];
extern const uint8_t famidash_menu_colors[];
extern const uint16_t nes_to_cgram[64];
/* Declared because an implicit one is assumed NEAR, and with --code-model large
   that is a jsr to a function in another bank - no link error, wrong target. */
void bg_tileset_reload(void);
void flush_chr_now(void);
void shim_scpu_chr_now(void);
void shim_scpu_bg_tileset_reload(void);

/* tools/gen_levels.py: every level of the set, and its name for the menu. */
extern const uint8_t level_count;
extern const uint8_t level_names[];     /* LEVEL_NAME_W chars each, uppercase */
extern const uint8_t lvl_song[];
#define LEVEL_NAME_W 23

/* Game state lives in probe_full.c's translation unit. This entry point resets
   the fresh-level player state before preloading its CHR in forced blank. */
extern uint8_t gamemode;
extern uint8_t currplayer_mini;
extern uint8_t iconbank;
extern uint8_t icon;
extern uint8_t retro_mode;
#ifndef GAMEMODE_CUBE
#define GAMEMODE_CUBE 0
#endif

#define DMAP0    REG(0x4300)
#define BBAD0    REG(0x4301)
#define A1T0L    REG(0x4302)
#define A1T0H    REG(0x4303)
#define A1B0     REG(0x4304)
#define DAS0L    REG(0x4305)
#define DAS0H    REG(0x4306)
#define MDMAEN   REG(0x420B)

/*
 * A pointer is 4 bytes here (24-bit address in the low 3) and the game's
 * uintptr_t is 16, so a pointer cannot be cast to an address - see
 * docs/HANDOFF.md trap 28. DMA needs the bank byte, hence the union.
 */
union menu_ptr { const void *p; uint32_t v; };

/* Tilemap words to VRAM, in one transfer. VMADD must already be set. */
static void dma_vram(const void *src, uint16_t bytes)
{
    union menu_ptr u;
    u.p = src;
    DMAP0 = 0x01;                       /* 2 registers, write once: L then H */
    BBAD0 = 0x18;                       /* VMDATAL */
    A1T0L = (uint8_t)u.v;
    A1T0H = (uint8_t)(u.v >> 8);
    A1B0  = (uint8_t)(u.v >> 16);
    DAS0L = (uint8_t)bytes;
    DAS0H = (uint8_t)(bytes >> 8);
    MDMAEN = 0x01;
}

static void vram_upload(uint16_t word_addr, const uint8_t *src, uint16_t len)
{
    uint16_t i;
    VMAIN = 0x80;                       /* +1 word, step on the high byte */
    VMADDL = (uint8_t)word_addr;
    VMADDH = (uint8_t)(word_addr >> 8);
    for (i = 0; i < len; i += 2) {
        VMDATAL = src[i];
        VMDATAH = src[i + 1];
    }
}

/* Game state the loop needs. famidash.h defines rather than declares these. */
extern uint8_t gameState;
extern uint8_t level;
extern uint8_t framerate;
extern uint8_t forceNoFadeOut;
extern uint8_t menuMusicCurrentlyPlaying;
extern uint8_t use_auto_chrswitch;
extern uint8_t attemptCounter[7];
extern uint16_t jumps;
extern uint8_t coins;
extern uint8_t shim_native_screen_active;
extern uint8_t practice_point_count;
extern uint8_t menuselection;
extern uint8_t normalorcommlevels;
extern uint8_t invisblocks;
extern uint8_t no_parallax;
extern uint8_t LEVELCOMPLETE[];
extern uint8_t invisible_LEVELCOMPLETE[];
extern uint8_t level_completeness_normal[];
extern uint8_t invisible_level_completeness_normal[];
extern uint8_t coin1_obtained[];
extern uint8_t coin2_obtained[];
extern uint8_t coin3_obtained[];
extern uint8_t invisible_coin1_obtained[];
extern uint8_t invisible_coin2_obtained[];
extern uint8_t invisible_coin3_obtained[];
extern const unsigned char * const Number_Sprites[];

/*
 * The options famidash.c's setdefaultoptions() sets to something other than 0.
 *
 * This port boots straight into STATE_GAME, so setdefaultoptions() - which also
 * pokes SRAM and the MMC3 IRQ table - never runs and every option stays at its
 * BSS zero. That is not a neutral default: `viseffects` gates the DECO arm of
 * sprite_collide, which retires every decoration sprite the frame it comes on
 * screen (`if (twoplayer || !viseffects) activesprites_type[index] = 0xFF;`).
 * Most of Stereo Madness's sprite stream is decorations, so with viseffects = 0
 * the level looks empty however well the sprite engine works - measured, 0
 * active slots in 1802 of 2000 frames.
 */
extern uint8_t viseffects;
extern uint8_t auto_practicepoints;
/* famidash.h line 219: color1/2/3 are #defines for icon_colors[0..2]. */
extern uint8_t icon_colors[3];
extern uint8_t current_deco_type;
extern const uint8_t lvl_fallspeed_deco[];

static void default_options(void)
{
    viseffects = 1;
    auto_practicepoints = 1;
    icon_colors[0] = 0x2A;              /* color1 */
    icon_colors[1] = 0x2C;              /* color2 */
    icon_colors[2] = 0x0F;              /* color3 */
}

void state_game(void);
void state_lvldone(void);

#define STATE_GAME    0x02
#define STATE_LVLDONE 0x03

/*
 * On the SA-1 this runs on the S-CPU, called from scpu_boot before the SA-1 is
 * released - so it is not static there. Every line of it is PPU work: forced
 * blank, the $2101-$2133 clear, both VRAM uploads, the BG and OBJ base
 * registers. None of it would have any effect from the SA-1 side, which is
 * why the screen stayed dark with correct data behind it.
 */
#ifdef SHIM_SA1
void video_init(void)
#else
static void video_init(void)
#endif
{
    uint16_t i;

    INIDISP = 0x8F;                     /* forced blank */
    NMITIMEN = 0;
    /* FastROM. Banks $80-$FF go from 2.68MHz to 3.58MHz, and every byte of
       this port - code, level streams, sprite CHR - lives at $C0-$C9. The
       header's map mode byte has to agree (snes_header.s, 0x31 not 0x21);
       hardware ignores one without the other. */
    MEMSEL = 1;
    for (i = 0x2101; i < 0x2134; i++)
        REG((uint16_t)i) = 0;

    vram_upload(VRAM_TILES, bg1_tiles, 4096);
    /*
     * Sprite tiles go to OBJ tile 256, not 0: EVERY sprite tile byte in the
     * game indexes NES pattern table 1 (tile byte bit 0 set), and oam_spr maps
     * that to SNES OBJ tiles 256+. With OBSEL name-select 0 those sit $1000
     * words above the OBJ base, so $2000 + $1000 = $3000.
     *
     * All 256 tiles of that pattern table, not just the icon bank: the level
     * objects live in the portals/main/deco 1KB banks further up, and uploading
     * only the icon left every coin, orb and portal naming VRAM that had never
     * been written - which is exactly what they looked like on screen.
     */
    vram_upload(VRAM_OBJ + 0x1000, spr_tiles, 8192);
    vram_upload(VRAM_BG2TILES, parallax_tiles, 2048);
    vram_upload(VRAM_BG2MAP, parallax_map, 4096);
    vram_upload(VRAM_BG2MAP + 0x0800, parallax_map_bottom, 4096);

    /* screen size 11 = 64x64: 512px tall, so a level up to 29 metatile rows
       (29 + 3 ground = 32) needs no vertical row streaming at all. */
    BG1SC = (uint8_t)(((VRAM_BG1MAP >> 10) << 2) | 0x03);
    /* BG2 is 64x64. Besides the horizontal parallax period, the extra map
       height prevents VOFS 238 from wrapping the nine-row motif inside the
       visible top of the screen (the former 64x32 map wrapped at 256px). */
    BG2SC = (uint8_t)(((VRAM_BG2MAP >> 10) << 2) | 0x03);
    BG12NBA = (uint8_t)((VRAM_BG2TILES >> 8) & 0xF0);
    /* base $2000 in 8K-word units; name-select 0 puts table 1 at +$1000. */
    OBSEL = (uint8_t)(VRAM_OBJ >> 13);
    BGMODE = 0;

    /*
     * The full clear, not oam_clear(): that one only resets the cursor now, and
     * the tail-hiding it was replaced with cannot reach entries no frame has
     * ever drawn. Without this the shadow buffer's power-on state is DMA'd
     * straight to OAM.
     */
    oam_init();
    /*
     * Leave the screen in forced blank. reset_level() does ppu_off() ... draw
     * the first screen ... ppu_on_all(), and the level renderer relies on that
     * window: VRAM is only writable in forced blank or vblank, so turning the
     * screen on here would make every write in the init loop vanish.
     */
    ppu_off();
    NMITIMEN = 0x01;                    /* auto-joypad read; no NMI handler */
}

/* ======================================================================== */
/* A level select                                                           */
/* ======================================================================== */
/*
 * Basic on purpose: enough to reach any of the 46 levels and check it renders,
 * not a port of menustates/levelselection.c - that wants the mouse, the save
 * file, the difficulty faces and a lot of menu CHR.
 *
 * It draws with its OWN tileset, generated by tools/gen_menufont.py, because
 * THE GAME HAS NO ALPHABET ANYWHERE: the level tileset spells "ATTEMPT" as
 * "PQQRSTQ" - level tiles that happen to look like letters - and menus.chr is
 * artwork, not a font. So the menu uploads its font, draws, and puts the level
 * tileset back before handing over to the game.
 *
 * Everything here writes VRAM in forced blank, so none of it needs the vblank
 * queue.
 */
#define MENU_ROWS   22                  /* level rows visible at once */
#define MENU_TOP    3
#define MENU_LEFT   6
#define MENU_COLS   32

/*
 * The font is generated by tools/gen_menufont.py and indexed by CHARACTER CODE,
 * so a space really is $20 and drawing a string is just writing its bytes.
 *
 * It exists because THE GAME HAS NO ALPHABET: the level tileset spells
 * "ATTEMPT" as "PQQRSTQ" - level tiles that happen to look like letters - and
 * menus.chr is not an ASCII font either. `one_vram_buffer('g', ...)` in the
 * menu code places tile $67, which is a piece of menu artwork; the real menus
 * draw pre-rendered screens with vram_unrle.
 */
#define MENU_BLANK ' '

/*
 * VOLATILE because the test harness pokes them.
 *
 * tools/menu_skip.lua writes menu_sel to jump straight to a level instead of
 * walking 167 rows. At -O 1 that worked by accident; at -O 2 the compiler keeps
 * the value in a register across the menu loop and the poke is invisible, so
 * every scripted run played level 0 - and reported a perfectly plausible frame
 * rate for it. The menu itself was never broken: verify_menu.lua, which presses
 * buttons, passed throughout.
 */
static volatile uint16_t menu_sel;      /* which level is highlighted */
static volatile uint16_t menu_top;      /* first level shown */

/*
 * Non-zero exactly while level_select() is running its loop.
 *
 * For the test harness, which pokes menu_sel to jump to a level. It used to
 * decide the menu was up by looking for the title's 'F' in the tilemap - and at
 * boot, before the menu has drawn, that byte can already be $46, so the poke
 * landed before level_select() existed, was lost, and START went in against a
 * selection of 0. Every scripted run then played level 0 and reported a
 * perfectly plausible frame rate for it.
 */
volatile uint8_t shim_menu_active;

/*
 * The visible rows, shadowed in WRAM and sent as ONE DMA in vblank.
 *
 * The menu used to redraw straight into VRAM under forced blank, which is a
 * black frame on every keypress - a visible blink, and unusable once the list
 * is long enough to want holding the button down. Writing 704 tilemap words one
 * at a time does not fit in vblank; a DMA of the same 1408 bytes is about a
 * fifth of it, so the whole visible block can go every frame it changes with
 * the screen still on.
 */
static uint16_t menu_rows[MENU_ROWS + 1][MENU_COLS];  /* +1: sentinel row */
static uint8_t menu_dirty;

static void menu_putc(uint16_t col, uint16_t row, uint8_t ch, uint8_t pal)
{
    /* The 64x64 map is four 32x32 screens; the menu only uses the first. */
    uint16_t addr = (uint16_t)(VRAM_BG1MAP + (row & 31) * 32 + (col & 31));
    VMAIN = 0x80;
    VMADDL = (uint8_t)addr;
    VMADDH = (uint8_t)(addr >> 8);
    VMDATAL = ch;
    VMDATAH = (uint8_t)((pal & 7) << 2);        /* tilemap word: pppcc cccccccc */
}

static void menu_puts(uint16_t col, uint16_t row, const char *s, uint8_t pal)
{
    while (*s)
        menu_putc(col++, row, (uint8_t)*s++, pal);
}

/*
 * Fill the shadow with the visible window.
 *
 * POINTER WALKS WITH SENTINELS, not indexed loops. Written the obvious way -
 * `menu_rows[row][col] = level_names[lv * LEVEL_NAME_W + col]` - this cost a
 * multiply and a two-dimensional index per CHARACTER, and Calypsi keeps the
 * loop counters in stack slots, so every one of the 1200 stores carried several
 * stack accesses with it. Measured: about one rebuild every eight frames, which
 * capped the scroll at one row per eight frames however fast the auto-repeat
 * asked for. Same shape as the fix in trap 76.
 */
static void menu_build(void)
{
    uint16_t *row = &menu_rows[0][0];
    uint16_t *end = &menu_rows[MENU_ROWS][0];
    const uint8_t *nm = &level_names[(uint16_t)menu_top * LEVEL_NAME_W];
    uint16_t lv = menu_top;

    while (row != end) {
        uint16_t *d = row;
        uint16_t *stop = row + MENU_COLS;

        while (d != stop)
            *d++ = MENU_BLANK;

        if (lv < level_count) {
            const uint8_t *nend = nm + LEVEL_NAME_W;
            /* The selected row is marked rather than recoloured: one palette
               keeps the menu independent of whatever the level left in CGRAM. */
            if (lv == menu_sel)
                row[MENU_LEFT - 2] = (uint16_t)'>';
            d = row + MENU_LEFT;
            while (nm != nend)
                *d++ = (uint16_t)(*nm++);
        }
        row = stop;
        lv++;
    }
    menu_dirty = 1;
}

/* One DMA, in vblank, with the screen on. */
static void menu_flush(void)
{
    uint16_t addr = (uint16_t)(VRAM_BG1MAP + MENU_TOP * 32);
    if (!menu_dirty)
        return;
    VMAIN = 0x80;
    VMADDL = (uint8_t)addr;
    VMADDH = (uint8_t)(addr >> 8);
    dma_vram(menu_rows, MENU_ROWS * MENU_COLS * 2);
    menu_dirty = 0;
}

static void menu_clear_static(void)
{
    uint16_t r, c;
    for (r = 0; r < 32; r++)
        for (c = 0; c < 32; c++)
            menu_putc(c, r, MENU_BLANK, 0);
}

/* A readable palette of its own: the level's colours are whatever the last
   level left behind, and the font is drawn in colour 1. */
static void menu_palette(void)
{
    uint16_t i;
    CGADD = 0;
    for (i = 0; i < 4; i++) {
        /* The font only writes bitplane 0, so colour 1 is the glyph and 0 the
           backdrop; 2 and 3 never appear. */
        static const uint16_t c[4] = { 0x2000, 0x7FFF, 0x0000, 0x0000 };
        CGDATA = (uint8_t)c[i];
        CGDATA = (uint8_t)(c[i] >> 8);
    }
}

/* ======================================================================== */
/* Native level-complete screen                                             */
/* ======================================================================== */
static void famidash_end_enter_ppu(void);
static void famidash_end_leave_ppu(void);
static void famidash_end_prepare(void);
#ifdef SHIM_SA1
static void fami_sa1_enter_ack(void);
#endif
/*
 * The NES screen names four CHR banks that were never resident on SNES, so its
 * nametable decoded successfully into tile numbers whose art was still the
 * level tileset. This screen deliberately uses the port's ASCII-indexed menu
 * font: readable on both mappings and independent of mapper state.
 */
static void end_put_centered(uint16_t row, const char *s)
{
    uint16_t len = 0;
    const char *p = s;
    while (*p++) len++;
    menu_puts((uint16_t)((32 - len) >> 1), row, s, 0);
}

static void end_put_u16(uint16_t col, uint16_t row, uint16_t value)
{
    uint8_t digits[5];
    uint8_t i, started = 0;

    for (i = 5; i != 0; i--) {
        digits[i - 1] = (uint8_t)(value % 10);
        value /= 10;
    }
    for (i = 0; i < 5; i++) {
        if (digits[i] || started || i == 4) {
            started = 1;
            menu_putc(col++, row, (uint8_t)('0' + digits[i]), 0);
        }
    }
}

static void end_put_attempts(uint16_t col, uint16_t row)
{
    int8_t i;
    uint8_t started = 0;

    for (i = 6; i >= 0; i--) {
        uint8_t d = attemptCounter[i];
        if (d || started || i == 0) {
            started = 1;
            menu_putc(col++, row, (uint8_t)('0' + d), 0);
        }
    }
}

static void end_screen_enter_ppu(void)
{
    const uint8_t *name = &level_names[(uint16_t)level * LEVEL_NAME_W];
    uint8_t got_coins = 0;
    uint8_t i;

    BGMODE = 0;                         /* native font is Mode 0 2bpp */
    vram_upload(VRAM_TILES, menu_tiles, 4096);
    BG12NBA = (uint8_t)((VRAM_BG2TILES >> 8) & 0xF0);
    menu_palette();
    BG1HOFS = 0; BG1HOFS = 0;
    /*
     * Reset both writes of the shared BG scroll latch. Reusing the menu's
     * power-on $3FF convention here inherited the level's last low latch bits;
     * measured result was VOFS=238, which put every completion label below the
     * visible screen even though its tilemap and font were both correct.
     */
    BG1VOFS = 0; BG1VOFS = 0;
    menu_clear_static();

    end_put_centered(4, "LEVEL COMPLETE");
    for (i = 0; i < LEVEL_NAME_W; i++)
        menu_putc((uint16_t)(4 + i), 7, name[i], 0);

    end_put_centered(11, "ATTEMPTS");
    end_put_attempts(13, 12);
    end_put_centered(15, "JUMPS");
    end_put_u16(13, 16, jumps);

    if (coins & 1) got_coins++;
    if (coins & 2) got_coins++;
    if (coins & 4) got_coins++;
    menu_puts(11, 19, "COINS", 0);
    menu_putc(17, 19, (uint8_t)('0' + got_coins), 0);
    menu_puts(19, 19, "/ 3", 0);

    end_put_centered(23, "A  RESTART");
    end_put_centered(25, "B  LEVEL SELECT");

    /* A transition must never inherit hardware sprites from gameplay. */
    oam_init();
}

static void end_screen_leave_ppu(void)
{
#ifdef SHIM_SA1
    shim_scpu_bg_tileset_reload();
#else
    bg_tileset_reload();
    shim_scpu_chr_now();
#endif
}

void snes_end_screen_enter(void)
{
    shim_native_screen_active = 1;
    ppu_off();
    famidash_end_prepare();
#ifdef SHIM_SA1
    shim_request(SHIM_REQ_END_ENTER);
    fami_sa1_enter_ack();
#else
    famidash_end_enter_ppu();
#endif
}

void snes_end_screen_leave(void)
{
    ppu_off();
    shim_native_screen_active = 0;
#ifdef SHIM_SA1
    shim_request(SHIM_REQ_END_LEAVE);
#else
    famidash_end_leave_ppu();
#endif
}

/*
 * Auto-repeat, so the list can be held rather than tapped.
 *
 * 168 levels is 167 presses to reach the end, which is not a menu. A press
 * moves once, then after DELAY frames the movement repeats every REPEAT frames,
 * and after FAST_AFTER repeats it goes to one row per frame.
 */
#define MENU_DELAY      18              /* frames before the repeat starts */
#define MENU_REPEAT      3              /* frames between repeats */
#define MENU_FAST_AFTER  6              /* repeats before the step grows */
#define MENU_FAST_STEP   5              /* rows per move once fast */

/*
 * Move the selection, and redraw as little as possible.
 *
 * A full rebuild of the window is about four frames, so doing one per row is
 * what caps the scroll - and it is unnecessary for the common move, where the
 * window does not scroll at all and the only change is which row carries the
 * marker. Two stores instead of twelve hundred.
 *
 * When the window DOES scroll there is no way round the rebuild, so the fast
 * tier takes several rows at a time instead: the cost is per rebuild, not per
 * row, and 168 levels is not a list to walk one row per four frames.
 */
static void menu_move(int16_t step)
{
    uint16_t old_sel = menu_sel;
    uint16_t old_top = menu_top;
    int16_t s = (int16_t)menu_sel + step;

    /* Wrap at both ends: from the top, up goes to the bottom. */
    while (s < 0)
        s += level_count;
    while (s >= (int16_t)level_count)
        s -= level_count;
    menu_sel = (uint16_t)s;

    if (menu_sel < menu_top)
        menu_top = menu_sel;
    if (menu_sel >= (uint16_t)(menu_top + MENU_ROWS))
        menu_top = (uint16_t)(menu_sel - MENU_ROWS + 1);

    if (menu_top == old_top) {
        /* The window did not move: just move the marker. */
        menu_rows[old_sel - menu_top][MENU_LEFT - 2] = MENU_BLANK;
        menu_rows[menu_sel - menu_top][MENU_LEFT - 2] = (uint16_t)'>';
        menu_dirty = 1;
        return;
    }
    menu_build();
}

/*
 * The menu's PPU burst: its own font over the level tileset, its own palette,
 * its own scroll, and a cleared tilemap. All direct VRAM and CGRAM writes, so
 * on the SA-1 the S-CPU runs this through the request channel.
 */
static void menu_enter_ppu(void)
{
    BGMODE = 0;                         /* native font is Mode 0 2bpp */
    vram_upload(VRAM_TILES, menu_tiles, 4096);
    BG12NBA = (uint8_t)((VRAM_BG2TILES >> 8) & 0xF0);
    menu_palette();
    /* BG1 only: the player and the level objects have nothing to do here. */
    BG1HOFS = 0; BG1HOFS = 0;
    BG1VOFS = 0xFF; BG1VOFS = 0xFF;     /* -1 puts tilemap row 0 on line 0 */
    menu_clear_static();
}

static void level_select(void)
{
    uint16_t held = 0;                  /* frames the direction has been held */
    uint16_t repeats = 0;

    ppu_off();
#ifdef SHIM_SA1
    /* ppu_off only reached the shadow; the S-CPU applies it at the top of the
       next flush, and menu_enter_ppu runs in that same forced blank. */
    shim_request(SHIM_REQ_MENU_ENTER);
#else
    menu_enter_ppu();
#endif
    menu_build();
#ifdef SHIM_SA1
    /*
     * The static labels and the first row transfer are both PPU work, so they
     * go with the rest of the menu's setup rather than happening here.
     *
     * menu_flush in particular MUST NOT be called from this side: it is guarded
     * by `menu_dirty`, and calling it on the SA-1 cleared the flag while its
     * DMA moved nothing, so the S-CPU's copy always found the menu clean and
     * the level list never appeared. The rest of the menu - backdrop, palette,
     * cleared tilemap - drew correctly, which made it look like a font problem.
     */
    shim_request(SHIM_REQ_MENU_DRAW);
#else
    menu_puts(8, 1, "FAMIDASH  SNES", 0);
    menu_puts(2, MENU_TOP + MENU_ROWS + 1, "UP DOWN  A TO PLAY", 0);
    menu_flush();                       /* still in forced blank: free */
#endif
    ppu_on_bg();
    shim_menu_active = 1;

    for (;;) {
        uint8_t pressed, hold;
        int8_t dir = 0;

        /* No NMI handler, so wait for vblank the same way ppu_wait_nmi does.
           pad_poll AFTER it: the auto-joypad read takes about three scanlines
           from the start of vblank and pad_poll spins until it finishes. */
#ifdef SHIM_SA1
        /* level_select has its own copy of the frame boundary, so it needs the
           same handshake ppu_wait_nmi got: HVBJOY is open bus on the SA-1 and
           these two polls fall straight through, which left the menu spinning
           at full speed on input it could never read.
           menu_flush is a DMA and has moved to the S-CPU, which calls it from
           shim_scpu_frame inside this wait.

           NO pad_poll here: ppu_wait_nmi already does it on this path, and
           polling twice destroys the press edge - the second call sees the
           button already held, so `press` comes back zero and A never
           registers. That locked the menu completely. */
        ppu_wait_nmi();
#else
        while (HVBJOY & 0x80) ;
        while (!(HVBJOY & 0x80)) ;
        /* The DMA goes FIRST, while the vblank is still long: pad_poll spins
           for the auto-joypad read and would eat the window. */
        menu_flush();
        pad_poll(0);
#endif
        pressed = joypad1.press;        /* the shim already does the edge */
        hold = joypad1.hold;

        if (pressed & (PAD_A | PAD_START | PAD_B))
            break;

        if (hold & PAD_DOWN)      dir = 1;
        else if (hold & PAD_UP)   dir = -1;

        if (dir == 0) {
            held = 0;
            repeats = 0;
        } else if (pressed & (PAD_UP | PAD_DOWN)) {
            menu_move(dir);             /* the initial press */
            held = 0;
            repeats = 0;
        } else {
            held++;
            if (held >= (repeats ? MENU_REPEAT : MENU_DELAY)) {
                held = 0;
                repeats++;
                menu_move((int16_t)dir
                          * (repeats > MENU_FAST_AFTER ? MENU_FAST_STEP : 1));
            }
        }
    }

    /* Hand the level tileset back before the game touches the screen. The
       menu drew with its own font in the same VRAM, so this has to be sent
       again even when the level has not changed - init_rld would skip it. */
    shim_menu_active = 0;
    ppu_off();
    level = (uint8_t)menu_sel;
#ifdef SHIM_SA1
    shim_request(SHIM_REQ_MENU_EXIT);
#else
    bg_tileset_reload();
    flush_chr_now();
#endif
}

/* ======================================================================== */
/* Original Famidash title, level-select, and completion screens             */
/* ======================================================================== */

#define FAMI_SCREEN_TITLE  1
#define FAMI_SCREEN_LEVEL  2
#define FAMI_SCREEN_END    3
#define FAMI_OFFICIAL      28
#define FAMI_LEVELS        168
#define FAMI_SAVE_STRIDE   255
#define FAMI_BLANK_TILE    0xFE

/*
 * The generated maps are the original NES nametables with their attribute
 * bytes expanded into SNES tilemap words.  Keep both horizontal pages in
 * shared WRAM: the level selector really slides between two complete screens,
 * just as Famidash does with nametables A and B.
 */
/* SA-1 BW-RAM is already occupied by the decompressed level and sprite state.
 * The two menu nametables fit exactly in the otherwise-free $7000-$7FFF near
 * WRAM window, and both processors can see it. */
#ifdef SHIM_SA1
/* Keep a far-qualified C object even though the linker places it in near WRAM.
 * A __near pointer is stored relative to _NearBaseAddress; converting that
 * relative value to the 24-bit DMA source silently produced $00:0000 instead
 * of $00:6000.  The explicit section gets the placement without changing the
 * pointer representation. */
static uint16_t fami_pages[2][1024] __attribute__((section("znear")));
#else
static uint16_t fami_pages[2][1024];
#endif
static volatile uint8_t fami_dirty_pages;
static volatile uint8_t fami_palette_dirty;
static volatile uint8_t fami_screen;
static volatile uint8_t fami_level_number;
static volatile uint8_t fami_title_color;
static volatile uint8_t fami_demon_face;
static volatile uint8_t fami_face_dirty;
static volatile uint8_t fami_face_uploaded;
static volatile uint8_t fami_page_phase;
static uint8_t fami_menu_song;
static uint8_t fami_menu_song_chosen;

#ifdef SHIM_SA1
/*
 * BW-RAM writes made by the S-CPU are protected in this mapping.  It can read
 * the menu buffers and DMA them to VRAM, but only the SA-1 can retire the
 * producer flags.  ppu_wait_nmi calls this after the S-CPU echoes the frame.
 */
void fami_sa1_frame_ack(void)
{
    uint8_t dirty = fami_dirty_pages;

    fami_palette_dirty = 0;
    if (dirty) {
        /*
         * One 1 KB half-page was consumed this frame. Keep the page dirty for
         * the second half, then retire it after the following frame.
         */
        if (fami_page_phase == 0) {
            fami_page_phase = 1;
        } else {
            fami_page_phase = 0;
            fami_dirty_pages = 0;
        }
    } else if (fami_face_dirty) {
        fami_face_uploaded = fami_demon_face;
        fami_face_dirty = 0;
    }
}

/* Whole-screen entry uploaded both pages and the resident face under forced
   blank, so there is nothing left for the next frame to repeat. */
static void fami_sa1_enter_ack(void)
{
    fami_dirty_pages = 0;
    fami_palette_dirty = 0;
    fami_face_dirty = 0;
    fami_page_phase = 0;
    fami_face_uploaded =
        (uint8_t)(fami_screen == FAMI_SCREEN_LEVEL && fami_demon_face);
}

/*
 * Publish menu work before vblank instead of waiting until the SA-1 finishes a
 * gameplay-style frame. The S-CPU then catches the request at the start of
 * vblank, giving each 1 KB half-page its full transfer window.
 */
static void fami_sa1_drain(void)
{
    while (fami_dirty_pages || fami_palette_dirty || fami_face_dirty) {
        if (fami_palette_dirty) {
            shim_request(SHIM_REQ_MENU_PAL);
            fami_palette_dirty = 0;
        } else if (fami_dirty_pages) {
            uint8_t page = (uint8_t)((fami_dirty_pages & 1) ? 0 : 1);
            uint8_t op = (uint8_t)(SHIM_REQ_MENU_P0L
                + page * 2 + fami_page_phase);
            shim_request(op);
            if (fami_page_phase == 0) {
                fami_page_phase = 1;
            } else {
                fami_page_phase = 0;
                fami_dirty_pages = 0;
            }
        } else {
            shim_request(SHIM_REQ_MENU_FACE);
            fami_face_uploaded = fami_demon_face;
            fami_face_dirty = 0;
        }
    }
}
#endif

static const uint8_t fami_palette_title[16] = {
    0x11,0x0F,0x14,0x37, 0x11,0x0F,0x2A,0x3A,
    0x11,0x0F,0x27,0x30, 0x11,0x0F,0x11,0x30
};
static const uint8_t fami_palette_level[16] = {
    0x11,0x0F,0x11,0x30, 0x11,0x0F,0x2A,0x3A,
    0x11,0x0F,0x27,0x30, 0x11,0x0F,0x11,0x30
};
static const uint8_t fami_palette_end[16] = {
    0x17,0x0F,0x10,0x30, 0x11,0x0F,0x2A,0x3A,
    0x17,0x0F,0x17,0x27, 0x17,0x0F,0x11,0x21
};
static const uint8_t fami_palette_obj[16] = {
    0x00,0x0F,0x2A,0x21, 0x00,0x0F,0x24,0x28,
    0x00,0x0F,0x16,0x30, 0x00,0x0F,0x2A,0x2C
};
static const uint8_t fami_level_obj[16] = {
    0x11,0x0F,0x2A,0x30, 0x11,0x0F,0x11,0x30,
    0x11,0x0F,0x11,0x30, 0x11,0x0F,0x30,0x30
};
static const uint8_t fami_diff_a[7] =
    { 0x21,0x2A,0x28,0x16,0x24,0x16,0x28 };
static const uint8_t fami_diff_b[7] =
    { 0x06,0x30,0x30,0x30,0x06,0x30,0x21 };
static const uint8_t fami_diff_c[7] =
    { 0x13,0x14,0x16,0x16,0x06,0x06,0x03 };

static void fami_copy_map(uint8_t page, const uint8_t *src)
{
    uint16_t i;
    uint16_t *dst = fami_pages[page];
    for (i = 0; i != 1024; i++) {
        dst[i] = (uint16_t)src[i * 2]
               | ((uint16_t)src[i * 2 + 1] << 8);
    }
}

static void fami_tile(uint8_t page, uint8_t x, uint8_t y, uint8_t tile)
{
    uint16_t *word = &fami_pages[page][(uint16_t)y * 32 + x];
    *word = (uint16_t)((*word & 0xFF00) | tile);
}

static void fami_cgram_word(uint8_t index, uint16_t color)
{
    CGADD = index;
    CGDATA = (uint8_t)color;
    CGDATA = (uint8_t)(color >> 8);
}

static void fami_bg_palette(const uint8_t *palette)
{
    uint8_t i;
    for (i = 0; i != 16; i++)
        fami_cgram_word(i, nes_to_cgram[palette[i] & 0x3F]);
}

static void fami_obj_palette(const uint8_t *palette)
{
    uint8_t p, c;
    for (p = 0; p != 4; p++) {
        for (c = 0; c != 4; c++) {
            fami_cgram_word(
                (uint8_t)(128 + p * 16 + c),
                nes_to_cgram[palette[p * 4 + c] & 0x3F]);
        }
    }
}

static void fami_apply_palette(void)
{
    uint8_t color;
    uint8_t diff;

    if (fami_screen == FAMI_SCREEN_TITLE) {
        fami_bg_palette(fami_palette_title);
        fami_obj_palette(fami_palette_obj);
        color = fami_title_color;
        fami_cgram_word(0, nes_to_cgram[color & 0x3F]);
        fami_cgram_word(129, nes_to_cgram[color & 0x3F]);
        return;
    }

    if (fami_screen == FAMI_SCREEN_LEVEL) {
        fami_bg_palette(fami_palette_level);
        fami_obj_palette(fami_level_obj);
        color = famidash_menu_colors[fami_level_number % 9];
        fami_cgram_word(0, nes_to_cgram[color]);
        fami_cgram_word(14, nes_to_cgram[color]);
        fami_cgram_word(128, nes_to_cgram[color]);
        fami_cgram_word(178, nes_to_cgram[color]);

        diff = famidash_difficulty[fami_level_number];
        if (fami_demon_face) {
            fami_cgram_word(10, nes_to_cgram[fami_diff_c[diff]]);
            fami_cgram_word(11, nes_to_cgram[0x30]);
        } else {
            fami_cgram_word(10, nes_to_cgram[fami_diff_a[diff]]);
            fami_cgram_word(11, nes_to_cgram[fami_diff_b[diff]]);
        }
        return;
    }

    fami_bg_palette(fami_palette_end);
    fami_obj_palette(fami_palette_obj);
}

static void fami_upload_page(uint8_t page)
{
    uint16_t addr = (uint16_t)(VRAM_BG1MAP + (uint16_t)page * 0x0400);
    VMAIN = 0x80;
    VMADDL = (uint8_t)addr;
    VMADDH = (uint8_t)(addr >> 8);
    dma_vram(fami_pages[page], 2048);
}

#ifdef SHIM_SA1
static void fami_upload_page_half(uint8_t page, uint8_t half)
{
    uint16_t addr = (uint16_t)(VRAM_BG1MAP
        + (uint16_t)page * 0x0400 + (uint16_t)half * 0x0200);
    const uint16_t *src =
        &fami_pages[page][(uint16_t)half * 0x0200];

    VMAIN = 0x80;
    VMADDL = (uint8_t)addr;
    VMADDH = (uint8_t)(addr >> 8);
    dma_vram(src, 1024);
}
#endif

static void fami_clear_vram_page(uint16_t addr)
{
    uint16_t i;
    VMAIN = 0x80;
    VMADDL = (uint8_t)addr;
    VMADDH = (uint8_t)(addr >> 8);
    for (i = 0; i != 1024; i++) {
        VMDATAL = FAMI_BLANK_TILE;
        VMDATAH = 0;
    }
}

static void fami_upload_face_tiles(void)
{
    const uint8_t *src;
    if (fami_demon_face)
        src = famidash_menu_demon_tiles;
    else
        src = famidash_menu_bg_tiles + 2048;
    VMAIN = 0x80;
    VMADDL = 0x00;
    VMADDH = 0x04;                      /* BG tile $80 */
    dma_vram(src, 1024);
}

static void fami_flush(void)
{
    uint8_t dirty = fami_dirty_pages;

    if (fami_palette_dirty) {
        fami_apply_palette();
        fami_palette_dirty = 0;
    }
#ifdef SHIM_SA1
    /* The S-CPU may begin a flush late in vblank. A full 2 KB card plus OAM
       and CGRAM is not guaranteed to fit, so transfer one half per frame. */
    if (dirty & 1)
        fami_upload_page_half(0, fami_page_phase);
    else if (dirty & 2)
        fami_upload_page_half(1, fami_page_phase);
#else
    if (dirty & 1)
        fami_upload_page(0);
    if (dirty & 2)
        fami_upload_page(1);
    fami_dirty_pages = 0;
#endif

    /*
     * A level card is a 2 KB DMA.  The old path also uploaded the entire
     * 1 KB difficulty CHR bank on every move, even when the face had not
     * changed.  Together with OAM/CGRAM that exceeds one SNES vblank, so the
     * card DMA was dropped and every other selector page stayed blank.
     *
     * Face CHR only changes at the normal/demon boundary.  Even there, defer
     * it until the frame after the card DMA; the page is still almost entirely
     * off-screen during the first frame of the easing animation.
     */
    if (!dirty && fami_face_dirty) {
        fami_upload_face_tiles();
        fami_face_uploaded = fami_demon_face;
        fami_face_dirty = 0;
    }
}

static void fami_enter_ppu(void)
{
    BGMODE = 0;
    SETINI = 0x04;                      /* NES menus use all 240 visible lines */
    BG1SC = (uint8_t)(((VRAM_BG1MAP >> 10) << 2) | 0x03);
    BG12NBA = (uint8_t)((VRAM_BG2TILES >> 8) & 0xF0);
    OBSEL = (uint8_t)(VRAM_OBJ >> 13);

    vram_upload(VRAM_TILES, famidash_menu_bg_tiles, 4096);
    vram_upload(VRAM_OBJ + 0x1800, famidash_menu_cursor_tiles, 4096);
    fami_face_uploaded = 0;
    if (fami_screen == FAMI_SCREEN_LEVEL && fami_demon_face) {
        fami_upload_face_tiles();
        fami_face_uploaded = 1;
    }
    fami_face_dirty = 0;

    fami_apply_palette();
    fami_upload_page(0);
    fami_upload_page(1);

    fami_clear_vram_page(VRAM_BG1MAP + 0x0800);
    fami_clear_vram_page(VRAM_BG1MAP + 0x0C00);

    fami_dirty_pages = 0;
    fami_palette_dirty = 0;
    fami_page_phase = 0;
    oam_init();
}

static void fami_leave_ppu(void)
{
    SETINI = 0;
#ifdef SHIM_SA1
    shim_scpu_bg_tileset_reload();
#else
    bg_tileset_reload();
    shim_scpu_chr_now();
#endif
}

static void fami_title_build(uint8_t selection)
{
    static const uint8_t cursor_x[7] = { 15,21,9,15,21,27,9 };
    static const uint8_t cursor_y[7] = { 11,11,17,17,17,1,11 };
    uint8_t page, i;

    for (page = 0; page != 2; page++) {
        fami_copy_map(page, famidash_title_map);
        /* Huge Man exposes Fun Settings from the start. */
        fami_tile(page, 27, 2, 0x1B);
        fami_tile(page, 28, 2, 0x1C);
        fami_tile(page, 27, 3, 0x1D);
        fami_tile(page, 28, 3, 0x1E);
        for (i = 0; i != 7; i++) {
            if (i == 5) {
                fami_tile(page, 26, 2, FAMI_BLANK_TILE);
                fami_tile(page, 26, 3, FAMI_BLANK_TILE);
            } else {
                fami_tile(page, cursor_x[i], cursor_y[i], FAMI_BLANK_TILE);
                fami_tile(page, (uint8_t)(cursor_x[i] + 1), cursor_y[i],
                          FAMI_BLANK_TILE);
            }
        }
        if (selection == 5) {
            fami_tile(page, 26, 2, 0x6F);
            fami_tile(page, 26, 3, 0x7F);
        } else {
            fami_tile(page, cursor_x[selection], cursor_y[selection], 0x5E);
            fami_tile(page, (uint8_t)(cursor_x[selection] + 1),
                      cursor_y[selection], 0x5F);
        }
    }
    /* Title never scrolls to page 1; only the visible page needs cursor edits. */
    fami_dirty_pages = 1;
}

/*
 * Returns 0 for the official selector and 1 for community.  The other five
 * original buttons remain navigable and give the original invalid SFX until
 * their own screens are ported; importantly they never launch the wrong level.
 */
static uint8_t fami_title_screen(void)
{
    uint8_t frame = 0;
    uint8_t player_x = 0;

    if (menuselection > 6)
        menuselection = 0;
    ppu_off();
    set_scroll_x(0);
    set_scroll_y(0);
    fami_title_build(menuselection);
    fami_screen = FAMI_SCREEN_TITLE;
    fami_title_color = 0x11;
    fami_palette_dirty = 1;

    /* The title character uses the player's real selected cube graphics. */
    gamemode = GAMEMODE_CUBE;
    currplayer_mini = 0;
    iconbank = (uint8_t)((icon << 1) + 40);
    mmc3_set_2kb_chr_bank_0(retro_mode ? 18 : iconbank);
#ifdef SHIM_SA1
    shim_request(SHIM_REQ_MENU_ENTER);
    fami_sa1_enter_ack();
    shim_request(SHIM_REQ_CHR_NOW);
#else
    fami_enter_ppu();
    flush_chr_now();
#endif

    no_parallax = 1;
    shim_menu_active = 1;
    ppu_on_all();

    if (!menuMusicCurrentlyPlaying) {
        if (!fami_menu_song_chosen) {
            uint8_t random = newrand();
            if (random == 0)
                fami_menu_song = song_menu_theme_e_side;
            else if (random < 63)
                fami_menu_song = song_menu_theme;
            else if (random < 126)
                fami_menu_song = song_menu_theme_human_capturing_mix;
            else if (random < 189)
                fami_menu_song = song_menu_theme_b_sides;
            else
                fami_menu_song = song_emeht_unem;
            fami_menu_song_chosen = 1;
        }
        music_play(fami_menu_song);
        menuMusicCurrentlyPlaying = 1;
    }

    joypad1.press = 0;
    for (;;) {
        oam_clear();
        oam_spr(player_x, 160, 0x01, 0x20);
        oam_spr((uint8_t)(player_x + 8), 160, 0x03, 0x20);
        player_x++;
        ppu_wait_nmi();

        frame++;
        if (!(frame & 0x7F)) {
            fami_title_color++;
            if (fami_title_color > 0x1C)
                fami_title_color = 0x11;
            fami_palette_dirty = 1;
        }

        if (joypad1.press & PAD_RIGHT) {
            if (menuselection == 6)
                menuselection = 0;
            else
                menuselection++;
            fami_title_build(menuselection);
#ifdef SHIM_SA1
            fami_sa1_drain();
#endif
        }
        if (joypad1.press & PAD_LEFT) {
            if (menuselection == 0)
                menuselection = 6;
            else
                menuselection--;
            fami_title_build(menuselection);
#ifdef SHIM_SA1
            fami_sa1_drain();
#endif
        }

        if (joypad1.press & PAD_SELECT)
            sfx_play(sfx_invalid, 0);

        if (joypad1.press & (PAD_A | PAD_START)) {
            if (menuselection == 0 || menuselection == 1)
                break;
            sfx_play(sfx_invalid, 0);
        }
    }

    oam_clear();
    ppu_wait_nmi();
    normalorcommlevels = (uint8_t)(menuselection == 1);
    if (normalorcommlevels)
        level = FAMI_OFFICIAL;
    else
        level = 0;
    return normalorcommlevels;
}

static uint8_t fami_saved_value(uint8_t *normal, uint8_t *invisible)
{
    if (invisblocks)
        return invisible[level];
    return normal[level];
}

static void fami_progress_map(uint8_t page, uint8_t row, uint8_t percent)
{
    uint8_t x;
    uint8_t full = (uint8_t)(percent / 5);
    if (full > 19)
        full = 19;

    fami_tile(page, 6, row, percent >= 5 ? 0x8C : 0x7C);
    for (x = 1; x != 19; x++)
        fami_tile(page, (uint8_t)(6 + x), row,
                  x <= full ? 0x6B : 0x02);
    fami_tile(page, 25, row, percent >= 100 ? 0x8D : 0x7D);
}

static void fami_level_build(uint8_t page)
{
    const uint8_t *lines;
    uint8_t diff, stars, flags, normal, practice, i;

    fami_copy_map(page, famidash_levelselect_map);
    lines = &famidash_level_lines[(uint16_t)level * 34];
    for (i = 0; i != 17; i++) {
        fami_tile(page, (uint8_t)(8 + i), 10, lines[i]);
        fami_tile(page, (uint8_t)(8 + i), 11, lines[17 + i]);
    }

    if (fami_saved_value(LEVELCOMPLETE, invisible_LEVELCOMPLETE)) {
        fami_tile(page, 7, 9, 0x4E);
        fami_tile(page, 8, 9, 0x4F);
    } else {
        fami_tile(page, 7, 9, FAMI_BLANK_TILE);
        fami_tile(page, 8, 9, FAMI_BLANK_TILE);
    }

    diff = famidash_difficulty[level];
    fami_tile(page, 7, 10, (uint8_t)(0x90 + diff * 2));
    fami_tile(page, 8, 10, (uint8_t)(0x91 + diff * 2));
    fami_tile(page, 7, 11, (uint8_t)(0xA0 + diff * 2));
    fami_tile(page, 8, 11, (uint8_t)(0xA1 + diff * 2));

    stars = famidash_stars[level];
    if (stars >= 10) {
        fami_tile(page, 22, 9, (uint8_t)(0xB0 + stars / 10));
        fami_tile(page, 23, 9, (uint8_t)(0xB0 + stars % 10));
    } else {
        fami_tile(page, 22, 9, FAMI_BLANK_TILE);
        fami_tile(page, 23, 9, (uint8_t)(0xB0 + stars));
    }

    if (invisblocks) {
        flags = (uint8_t)(invisible_coin1_obtained[level]
              | (invisible_coin2_obtained[level] << 1)
              | (invisible_coin3_obtained[level] << 2));
    } else {
        flags = (uint8_t)(coin1_obtained[level]
              | (coin2_obtained[level] << 1)
              | (coin3_obtained[level] << 2));
    }
    for (i = 0; i != 3; i++)
        fami_tile(page, (uint8_t)(22 + i), 12,
                  flags & (1 << i) ? 0x8F : 0x0F);

    if (invisblocks) {
        normal = invisible_level_completeness_normal[level];
        practice = invisible_level_completeness_normal[
            FAMI_SAVE_STRIDE + level];
    } else {
        normal = level_completeness_normal[level];
        practice = level_completeness_normal[FAMI_SAVE_STRIDE + level];
    }
    fami_progress_map(page, 16, normal);
    fami_progress_map(page, 19, practice);

    fami_demon_face =
        (uint8_t)(famidash_stars[level] == 10 && level > 25);
    if (fami_demon_face != fami_face_uploaded)
        fami_face_dirty = 1;
    fami_level_number = level;
    fami_palette_dirty = 1;
    fami_dirty_pages |= (uint8_t)(1 << page);
}

static void fami_decimal_sprites(uint8_t x, uint8_t y, uint8_t value)
{
    if (value >= 100) {
        oam_meta_spr(x, y, Number_Sprites[value / 100]);
        x = (uint8_t)(x + 8);
    }
    if (value >= 10) {
        oam_meta_spr(x, y, Number_Sprites[(value / 10) % 10]);
        x = (uint8_t)(x + 8);
    }
    oam_meta_spr(x, y, Number_Sprites[value % 10]);
    oam_meta_spr((uint8_t)(x + 8), y, Number_Sprites[10]);
}

static void fami_progress_sprites(uint8_t y, uint8_t value)
{
    uint16_t marker;
    fami_decimal_sprites(112, y, value);
    oam_meta_spr(40, (uint8_t)(y + 1), Number_Sprites[22]);
    oam_meta_spr(41, (uint8_t)(y + 1), Number_Sprites[25]);
    oam_meta_spr(206, (uint8_t)(y + 1), Number_Sprites[26]);
    marker = (uint16_t)(41 + ((uint16_t)value * 8) / 5);
    if (marker > 201)
        marker = 201;
    oam_meta_spr((uint8_t)marker, (uint8_t)(y + 1),
                 Number_Sprites[y == 127 ? 23 : 24]);
}

static void fami_level_sprites(void)
{
    uint8_t normal, practice;
    if (invisblocks) {
        normal = invisible_level_completeness_normal[level];
        practice = invisible_level_completeness_normal[
            FAMI_SAVE_STRIDE + level];
    } else {
        normal = level_completeness_normal[level];
        practice = level_completeness_normal[FAMI_SAVE_STRIDE + level];
    }
    fami_progress_sprites(127, normal);
    fami_progress_sprites(151, practice);
}

static void fami_level_slide(uint8_t old_page, uint8_t direction)
{
    uint8_t amount = 0xFF;
    uint16_t scroll;

    while (amount) {
        oam_clear();
        fami_level_sprites();
        if (direction) {
            scroll = (uint16_t)(old_page * 256 + (255 - amount));
        } else {
            scroll = (uint16_t)(((old_page ^ 1) * 256) + amount);
        }
        set_scroll_x(scroll & 0x01FF);
        ppu_wait_nmi();
        amount = (uint8_t)(amount - ((amount >> 2) + 1));
    }
    set_scroll_x((uint16_t)((level & 1) * 256));
}

static void fami_level_preload(void)
{
#ifdef SHIM_SA1
    /*
     * Hold the current card still for the two vblanks needed to preload the
     * off-screen card. The easing animation then reveals only complete data.
     */
    fami_sa1_drain();
#endif
}

/* 0 returns to the title; 1 starts the selected level. */
static uint8_t fami_level_select(uint8_t community)
{
    uint8_t page;
    uint8_t hold_timer = 0;

    normalorcommlevels = community;
    if (community) {
        if (level < FAMI_OFFICIAL || level >= FAMI_LEVELS)
            level = FAMI_OFFICIAL;
    } else {
        if (level >= FAMI_OFFICIAL)
            level = 0;
    }

    ppu_off();
    set_scroll_y(0);
    page = (uint8_t)(level & 1);
    fami_copy_map((uint8_t)(page ^ 1), famidash_levelselect_map);
    fami_level_build(page);
    fami_screen = FAMI_SCREEN_LEVEL;
#ifdef SHIM_SA1
    shim_request(SHIM_REQ_MENU_ENTER);
    fami_sa1_enter_ack();
#else
    fami_enter_ppu();
#endif
    set_scroll_x((uint16_t)(page * 256));
    no_parallax = 1;
    shim_menu_active = 1;
    ppu_on_all();
    joypad1.press = 0;

    for (;;) {
        uint8_t move = 0;
        uint8_t direction = 0;
        oam_clear();
        fami_level_sprites();
        ppu_wait_nmi();

        if (joypad1.press & (PAD_A | PAD_START)) {
            uint8_t wait = 0;
            sfx_play(sfx_start_level, 0);
            famistudio_music_stop();
            do {
                oam_clear();
                fami_level_sprites();
                ppu_wait_nmi();
                wait++;
            } while (wait != 30);
            menuMusicCurrentlyPlaying = 0;
            shim_menu_active = 0;
            ppu_off();
#ifdef SHIM_SA1
            shim_request(SHIM_REQ_MENU_EXIT);
#else
            fami_leave_ppu();
#endif
            return 1;
        }

        if (joypad1.press & PAD_B) {
            shim_menu_active = 0;
            return 0;
        }

        if (joypad1.press & (PAD_LEFT | PAD_RIGHT))
            hold_timer = 0;
        if ((joypad1.press & PAD_RIGHT)
            || ((joypad1.hold & PAD_RIGHT) && hold_timer >= 15)) {
            move = 1;
            direction = 1;
        }
        if ((joypad1.press & PAD_LEFT)
            || ((joypad1.hold & PAD_LEFT) && hold_timer >= 15)) {
            move = 1;
            direction = 0;
        }

        if (move) {
            uint8_t old_page = (uint8_t)(level & 1);
            hold_timer = 0;
            if (direction) {
                level++;
                if (!community && level >= FAMI_OFFICIAL)
                    level = 0;
                if (community && level >= FAMI_LEVELS)
                    level = FAMI_OFFICIAL;
            } else {
                if (!community) {
                    if (level == 0)
                        level = FAMI_OFFICIAL - 1;
                    else
                        level--;
                } else {
                    if (level <= FAMI_OFFICIAL)
                        level = FAMI_LEVELS - 1;
                    else
                        level--;
                }
            }
            fami_level_build((uint8_t)(level & 1));
            fami_level_preload();
            fami_level_slide(old_page, direction);
        }

        if (hold_timer < 15)
            hold_timer++;
    }
}

static void fami_end_number(uint8_t x, uint8_t y, uint16_t value)
{
    uint16_t divisor = 10000;
    uint8_t started = 0;
    uint8_t digit;
    while (divisor) {
        digit = (uint8_t)(value / divisor);
        value = (uint16_t)(value % divisor);
        if (digit || started || divisor == 1) {
            fami_tile(0, x, y, (uint8_t)(0xD0 + digit));
            x++;
            started = 1;
        }
        divisor = (uint16_t)(divisor / 10);
    }
}

static void fami_end_attempts(void)
{
    int8_t i;
    uint8_t x = 20;
    uint8_t started = 0;
    for (i = 6; i >= 0; i--) {
        uint8_t digit = attemptCounter[i];
        if (digit || started || i == 0) {
            fami_tile(0, x, 13, (uint8_t)(0xD0 + digit));
            x++;
            started = 1;
        }
    }
}

static void famidash_end_prepare(void)
{
    fami_copy_map(0, practice_point_count
        ? famidash_practice_map : famidash_end_map);
    fami_copy_map(1, practice_point_count
        ? famidash_practice_map : famidash_end_map);
    fami_end_attempts();
    fami_end_number(18, 15, jumps);
    menuselection = 1;
    fami_tile(0, 8, 23, FAMI_BLANK_TILE);
    fami_tile(0, 9, 23, FAMI_BLANK_TILE);
    fami_tile(0, 22, 23, 0x94);
    fami_tile(0, 23, 23, 0x95);
    fami_screen = FAMI_SCREEN_END;
    fami_dirty_pages = 3;
    fami_palette_dirty = 1;
    set_scroll_x(0);
    set_scroll_y(0x00E8);
}

void snes_end_screen_set_selector(uint8_t selection)
{
    menuselection = (uint8_t)(selection & 1);
    if (menuselection) {
        fami_tile(0, 8, 23, FAMI_BLANK_TILE);
        fami_tile(0, 9, 23, FAMI_BLANK_TILE);
        fami_tile(0, 22, 23, 0x94);
        fami_tile(0, 23, 23, 0x95);
    } else {
        fami_tile(0, 8, 23, 0x94);
        fami_tile(0, 9, 23, 0x95);
        fami_tile(0, 22, 23, FAMI_BLANK_TILE);
        fami_tile(0, 23, 23, FAMI_BLANK_TILE);
    }
    fami_dirty_pages |= 1;
#ifdef SHIM_SA1
    fami_sa1_drain();
#endif
}

void snes_end_screen_reveal_coin(uint8_t coin)
{
    uint8_t x = (uint8_t)(11 + coin * 4);
    fami_tile(0, x, 18, 0x90);
    fami_tile(0, (uint8_t)(x + 1), 18, 0x91);
    fami_tile(0, x, 19, 0xA0);
    fami_tile(0, (uint8_t)(x + 1), 19, 0xA1);
    fami_dirty_pages |= 1;
#ifdef SHIM_SA1
    fami_sa1_drain();
#endif
}

static void famidash_end_enter_ppu(void)
{
    BGMODE = 0;
    SETINI = 0x04;
    BG1SC = (uint8_t)(((VRAM_BG1MAP >> 10) << 2) | 0x03);
    BG12NBA = (uint8_t)((VRAM_BG2TILES >> 8) & 0xF0);
    if (practice_point_count)
        vram_upload(VRAM_TILES, famidash_practice_bg_tiles, 4096);
    else
        vram_upload(VRAM_TILES, famidash_end_bg_tiles, 4096);
    fami_apply_palette();
    fami_upload_page(0);
    fami_upload_page(1);

    fami_clear_vram_page(VRAM_BG1MAP + 0x0800);
    fami_clear_vram_page(VRAM_BG1MAP + 0x0C00);
    fami_dirty_pages = 0;
    fami_palette_dirty = 0;
    oam_init();
}

static void famidash_end_leave_ppu(void)
{
    fami_leave_ppu();
}

#ifdef SHIM_SA1
/*
 * The S-CPU's whole per-frame job, called from scpu_frame in src/sa1_boot.s.
 * Lives here rather than in shim_ppu.c because menu_flush is static to this
 * file, and the menu's transfer has to happen in the same vblank as the rest.
 */
void shim_scpu_frame(void)
{
    uint8_t fami_done = 0;
    /*
     * The screen state FIRST, before anything bulk.
     *
     * The requests below are not vblank-sized: menu_enter_ppu writes 4096 bytes
     * of font through VMDATA in a C loop, which is many times a vblank. The
     * game knows that and calls ppu_off() before asking - but ppu_off only
     * reaches the shadow, so unless it is applied here, first, the burst runs
     * with the screen still on, overruns vblank, and the hardware drops the
     * tail silently. That looked like a menu drawn in an invisible font: the
     * tilemap and the palette were right and the glyphs were never uploaded.
     */
    shim_scpu_screen();

    uint8_t req = SHIM_MB_S->req;
    if (req != SHIM_MB_S->ack) {
        switch (req) {
        case SHIM_REQ_VIDEO_INIT: video_init();      break;
        case SHIM_REQ_MENU_ENTER: fami_enter_ppu();  break;
        case SHIM_REQ_MENU_DRAW:
            fami_flush();
            fami_done = 1;
            break;
        /* shim_scpu_chr_now, NOT flush_chr_now: on this side flush_chr_now is
           a request, and the S-CPU asking itself would never be answered. */
        case SHIM_REQ_MENU_EXIT:  fami_leave_ppu(); break;
        case SHIM_REQ_VRAM_FLUSH: shim_scpu_vram_flush(); break;
        case SHIM_REQ_CHR_NOW:    shim_scpu_chr_now();    break;
        case SHIM_REQ_SPC_BOOT:   spc_boot();             break;
        case SHIM_REQ_SPC_PREPARE:
            spc_prepare_song(spc_requested_song);
            break;
        case SHIM_REQ_END_ENTER: famidash_end_enter_ppu(); break;
        case SHIM_REQ_END_LEAVE: famidash_end_leave_ppu(); break;
        case SHIM_REQ_MENU_PAL:
            fami_apply_palette();
            fami_done = 1;
            break;
        case SHIM_REQ_MENU_P0L:
            fami_upload_page_half(0, 0);
            fami_done = 1;
            break;
        case SHIM_REQ_MENU_P0H:
            fami_upload_page_half(0, 1);
            fami_done = 1;
            break;
        case SHIM_REQ_MENU_P1L:
            fami_upload_page_half(1, 0);
            fami_done = 1;
            break;
        case SHIM_REQ_MENU_P1H:
            fami_upload_page_half(1, 1);
            fami_done = 1;
            break;
        case SHIM_REQ_MENU_FACE:
            fami_upload_face_tiles();
            fami_done = 1;
            break;
        }
        SHIM_MB_S->ack = req;
    }
    /* BEFORE shim_scpu_flush, not after. The menu's transfer has a deadline -
       VRAM writes past the end of vblank are dropped silently (trap 35) - and
       shim_scpu_flush ends with the CHR upload, which by design has no deadline
       at all. Running the budgeted transfer first pushed the menu past the end
       of vblank, and the level select drew nothing but uninitialised VRAM.

       Unconditional: menu_flush already guards on its own `menu_dirty`, which
       only the level select sets and which is false throughout gameplay. */
    if (!fami_done)
        fami_flush();
    menu_flush();
    shim_scpu_flush();
}
#endif

int main(void)
{
    uint8_t community = 0;
    uint8_t show_title = 1;
#ifdef SHIM_SA1
    /* Ask the S-CPU to bring the PPU up, now that cstartup has zeroed BSS, and
       wait until it has - the first frame assumes video_init already ran. */
    shim_request(SHIM_REQ_VIDEO_INIT);
#else
    video_init();
#endif

    /*
     * The audio driver, before anything else runs a frame. Uploading it is a
     * few thousand port handshakes and does not want to be competing with a
     * frame's work; it also has to be resident before the first
     * spc_frame_flush from the vblank path, which starts on the very next
     * frame.
     *
     * $2140-$2143 are S-CPU-only like every other register in $2100-$43FF, and
     * main() is SA-1 code on that build - so it goes through the request
     * channel there rather than being called directly. This is the fourth
     * instance of the defect shape that cost most of the SA-1 session
     * (docs/HANDOFF.md trap 119): something the game calls directly that only
     * the S-CPU can do, failing silently as missing output rather than as an
     * error.
     *
     * If the SPC does not answer, spc_boot gives up and the game runs silent
     * rather than hanging - see SPC_TIMEOUT.
     */
#ifdef SHIM_SA1
    shim_request(SHIM_REQ_SPC_BOOT);
#else
    spc_boot();
#endif

    default_options();
    framerate = 1;                      /* 60Hz physics table set */

    for (;;) {
        if (show_title)
            community = fami_title_screen();
        if (!fami_level_select(community)) {
            show_title = 1;
            continue;
        }
        show_title = 0;

        /* The selector deliberately returns in forced blank. Put the selected
           track's complete BRR working set in ARAM now, so no instrument note
           can turn into a synchronous multi-kilobyte gameplay upload. */
        music_prepare(lvl_song[level]);
        /*
         * Every fresh level starts as a full-size cube. Load that player bank
         * while the menu has left us in forced blank; otherwise state_game's
         * first set_player_banks() happens after reset_level has turned the
         * screen on, and its 4KB first-use upload blocks the 1.6KB decoration
         * phase for two visible frames.
         */
        gamemode = GAMEMODE_CUBE;
        currplayer_mini = 0;
        iconbank = (uint8_t)((icon << 1) + 40);
        mmc3_set_2kb_chr_bank_0(retro_mode ? 18 : iconbank);
        /*
         * Preload both decoration phases while the menu has left the screen in
         * forced blank. The sibling phase lives in otherwise unused OBJ tiles,
         * so state_game's every-frame bank toggle never spends vblank on CHR.
         */
        current_deco_type =
            (uint8_t)(lvl_fallspeed_deco[level] & 0x7F);
        mmc3_set_2kb_chr_bank_1(current_deco_type);
        gameState = STATE_GAME;

        while (gameState == STATE_GAME || gameState == STATE_LVLDONE) {
            forceNoFadeOut = 0;
            switch (gameState) {
            case STATE_GAME:
                state_game();
                use_auto_chrswitch = 0;
                if (gameState == STATE_LVLDONE)
                    forceNoFadeOut = 1;
                break;
            case STATE_LVLDONE:
                state_lvldone();
                break;
            }
        }
    }
}
