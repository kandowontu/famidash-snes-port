# 1 "probe/tu_collision.c"
# 1 "<built-in>" 1
# 1 "<built-in>" 3
# 263 "<built-in>" 3
# 1 "<command line>" 1
# 1 "<built-in>" 2
# 1 "probe/tu_collision.c" 2


# 1 "C:/famidash\\BUILD_FLAGS.h" 1
# 4 "probe/tu_collision.c" 2
# 1 "C:/famidash/LIB/headers\\stdint.h" 1
# 48 "C:/famidash/LIB/headers\\stdint.h"
typedef signed char int8_t;
typedef int int16_t;
typedef long int32_t;
typedef unsigned char uint8_t;
typedef unsigned uint16_t;
typedef unsigned long uint32_t;
# 66 "C:/famidash/LIB/headers\\stdint.h"
typedef signed char int_least8_t;
typedef int int_least16_t;
typedef long int_least32_t;
typedef unsigned char uint_least8_t;
typedef unsigned uint_least16_t;
typedef unsigned long uint_least32_t;
# 84 "C:/famidash/LIB/headers\\stdint.h"
typedef signed char int_fast8_t;
typedef int int_fast16_t;
typedef long int_fast32_t;
typedef unsigned char uint_fast8_t;
typedef unsigned uint_fast16_t;
typedef unsigned long uint_fast32_t;
# 102 "C:/famidash/LIB/headers\\stdint.h"
typedef int intptr_t;
typedef unsigned uintptr_t;






typedef long intmax_t;
typedef unsigned long uintmax_t;
# 5 "probe/tu_collision.c" 2
# 1 "C:/famidash/LIB/headers\\stddef.h" 1
# 44 "C:/famidash/LIB/headers\\stddef.h"
typedef int ptrdiff_t;



typedef char wchar_t;



typedef unsigned size_t;
# 6 "probe/tu_collision.c" 2
# 1 "shim/include\\arr_macros.h" 1
# 7 "probe/tu_collision.c" 2
# 1 "shim/include\\neslib.h" 1
# 20 "shim/include\\neslib.h"
void pal_all(const void *data);
void pal_bg(const void *data);
void pal_spr(const void *data);
void pal_clear(void);
void pal_bright(uint8_t bright);


void ppu_wait_nmi(void);
void ppu_off(void);
void ppu_on_all(void);
void ppu_on_bg(void);
void ppu_on_spr(void);
void ppu_mask(uint8_t mask);
uint8_t ppu_system(void);


void oam_clear(void);
void oam_clear_player(void);
void oam_clear_two_players(void);
void oam_spr(uint8_t x, uint8_t y, uint8_t chrnum, uint8_t attr);
void oam_meta_spr(uint8_t x, uint8_t y, const void *data);
void oam_meta_spr_disco(uint8_t x, uint8_t y, const void *data);
void oam_set(uint8_t index);
uint8_t oam_get(void);
void bank_spr(uint8_t n);


uint8_t pad_poll(uint8_t pad);


void scroll(uint16_t x, uint16_t y);
void split(uint16_t x);


uint8_t newrand(void);
void set_rand(uint16_t seed);


void vram_fill(uint8_t n, uint16_t len);
void vram_inc(uint8_t n);
void vram_read(void *dst, uint16_t size);
void vram_write(const void *src, uint16_t size);
void vram_unrle(const void *data);

void memcpy(void *dst, const void *src, uint16_t len);
void memfill(void *dst, uint8_t val, uint16_t len);
void delay(uint8_t frames);


struct pad {
    union {
        unsigned char hold;
        struct {
            unsigned char right : 1;
            unsigned char left : 1;
            unsigned char down : 1;
            unsigned char up : 1;
            unsigned char start : 1;
            unsigned char select : 1;
            unsigned char b : 1;
            unsigned char a : 1;
        };
    };
    union {
        unsigned char press;
        struct {
            unsigned char press_right : 1;
            unsigned char press_left : 1;
            unsigned char press_down : 1;
            unsigned char press_up : 1;
            unsigned char press_start : 1;
            unsigned char press_select : 1;
            unsigned char press_b : 1;
            unsigned char press_a : 1;
        };
    };
    union {
        unsigned char release;
        struct {
            unsigned char release_right : 1;
            unsigned char release_left : 1;
            unsigned char release_down : 1;
            unsigned char release_up : 1;
            unsigned char release_start : 1;
            unsigned char release_select : 1;
            unsigned char release_b : 1;
            unsigned char release_a : 1;
        };
    };
};

extern struct pad joypad1;
extern struct pad joypad2;
extern struct pad *controllingplayer;
# 8 "probe/tu_collision.c" 2
# 1 "shim/include\\nesdoug.h" 1
# 14 "shim/include\\nesdoug.h"
void set_vram_buffer(void);
void clear_vram_buffer(void);
void flush_vram_update2(void);

void one_vram_buffer(uint8_t data, uint16_t ppu_address);
void multi_vram_buffer_horz(const void *data, uint8_t len, uint16_t ppu_address);
void multi_vram_buffer_vert(const void *data, uint8_t len, uint16_t ppu_address);

uint8_t get_frame_count(void);
uint8_t check_collision(void);

void pal_fade_to(uint8_t from, uint8_t to);

void set_scroll_x(uint16_t x);
void set_scroll_y(uint16_t y);
uint16_t add_scroll_y(uint8_t add, uint16_t scroll);
uint16_t sub_scroll_y(uint8_t sub, uint16_t scroll);
uint16_t sub_scroll_y_ext(uint16_t sub, uint16_t scroll);

uint16_t get_ppu_addr(uint8_t nt, uint8_t x, uint8_t y);
# 44 "shim/include\\nesdoug.h"
void xy_split(uint16_t x, uint16_t y);
void gray_line(void);
void seed_rng(void);





void color_emphasis(uint8_t color);
# 9 "probe/tu_collision.c" 2
# 1 "shim/include\\mapper.h" 1
# 24 "shim/include\\mapper.h"
void mmc3_set_prg_bank_0(uint8_t bank);
void mmc3_set_prg_bank_1(uint8_t bank);


void mmc3_set_2kb_chr_bank_0(uint8_t bank);
void mmc3_set_2kb_chr_bank_1(uint8_t bank);
void mmc3_set_1kb_chr_bank_0(uint8_t bank);
void mmc3_set_1kb_chr_bank_1(uint8_t bank);
void mmc3_set_1kb_chr_bank_2(uint8_t bank);
void mmc3_set_1kb_chr_bank_3(uint8_t bank);
void mmc3_set_8kb_chr(uint8_t bank);


extern uint8_t irqTable[32];
extern uint8_t irqTableIdx;

void mmc3_disable_irq(void);
void set_irq_ptr(const uint8_t *address);
void write_irq_table(const uint8_t *data);
void edit_irq_table(uint8_t byte, uint8_t offset);


uint8_t is_irq_done(void);
# 10 "probe/tu_collision.c" 2
# 1 "shim/include\\nesdash.h" 1
# 24 "shim/include\\nesdash.h"
void oam_meta_spr_flipped(uint8_t flip, uint8_t x, uint8_t y, const void *data);


void one_vram_buffer_horz_repeat(uint8_t data, uint8_t len, uint16_t ppu_address);
void one_vram_buffer_vert_repeat(uint8_t data, uint8_t len, uint16_t ppu_address);
void draw_padded_text(const void *data, uint8_t len, uint8_t total_len,
                      uint16_t ppu_address);
void printDecimal(uint16_t value, uint8_t digits, uint8_t zeroChr,
                  uint8_t spaceChr, uint16_t ppu_address);


void music_play(uint8_t song);
void sfx_play(uint8_t sfx_index, uint8_t channel);
void music_update(void);
void playPCM(uint8_t sample);
void famistudio_sfx_clear_channel(uint8_t channel);
# 48 "shim/include\\nesdash.h"
uint16_t calculate_linear_scroll_y(uint16_t nonlinearScroll);
void cap_scroll_y_at_top(void);
void cap_scroll_y_at_bottom(void);


uint16_t hexToDec(uint16_t input);
void update_level_completeness(void);
void increment_attempt_count(void);
void display_attempt_counter(uint8_t zeroChr, uint16_t ppu_address);
void update_currplayer_table_idx(void);







extern uint8_t PAL_UPDATE;
extern uint8_t PAL_BUF_RAW[32];
extern uint16_t PAL_BUF[32];

void pal_col(uint8_t index, uint8_t color);


extern uint8_t auto_fs_updates;





uint8_t colBrightness(uint8_t color, uint8_t brightness);



void vram_adr(uint16_t adr);
void vram_put(uint8_t val);
# 126 "shim/include\\nesdash.h"
extern uint8_t shiftBy4table[16];
# 11 "probe/tu_collision.c" 2
# 1 "C:/famidash/SAUCE\\defines/space_defines.h" 1
# 12 "probe/tu_collision.c" 2
# 1 "C:/famidash/SAUCE\\defines/physics_defines.h" 1
# 13 "probe/tu_collision.c" 2
# 1 "C:/famidash/SAUCE\\defines/physics_table_defines.cmp.h" 1





const uint8_t CUBE_WIDTH[] = {0x0F, 0x08};



const uint8_t CUBE_HEIGHT[] = {0x0F, 0x07};
# 21 "C:/famidash/SAUCE\\defines/physics_table_defines.cmp.h"
const uint16_t CUBE_SPEED_50[] = {0x5203, 0xAE02, 0x2104, 0xFE04, 0x2406, 0xB701};
const uint16_t CUBE_SPEED_60[] = {0xC402, 0x3B02, 0x7103, 0x2904, 0x1E05, 0x6E01};


const uint16_t * const CUBE_SPEED[] = {CUBE_SPEED_50, CUBE_SPEED_60};


#pragma rodata-name("XCD_BANK_06")



const uint16_t sprite_gamemode_adjust_heights_50_mg[] = {0x53F9, 0xD3FA, 0x20FB, 0x93FB, 0x53F9, 0xE6FA, 0x0000, 0xA6FB, 0xB3F6, 0x80FB, 0x13FA, 0x2DFC, 0x93F5, 0x00FA, 0x0000, 0xD3FA, 0x6DFB, 0x9AFD, 0x2DFC, 0x73FD, 0xD3FA, 0x06FC, 0x0000, 0xA0FC, 0xEDF9, 0x13FD, 0xF3FB, 0x3AFD, 0xA0F9, 0x06FC, 0x0000, 0xF3FB, 0x3AF7, 0x06F9, 0xA0F9, 0xEDF9, 0x3AF7, 0x00FA, 0x0000, 0x3AFA, 0x53F9, 0x53F9, 0x06F9, 0x53F9, 0x53F9, 0x53F9, 0x0000, 0x06F9, 0x7A0B, 0x7A0B, 0x530B, 0x7A0B, 0x7A0B, 0x7A0B, 0x0000, 0x530B, 0xB3F9, 0xB3F9, 0xAAFA, 0x60FA, 0x13F7, 0x60FA, 0x0000, 0xAAFA, 0x13F4, 0xA6F8, 0x93F8, 0x33FB, 0xA0F3, 0x20F8, 0x0000, 0x5AF8};
const uint16_t sprite_gamemode_adjust_heights_50_mG[] = {0xAD06, 0x2D05, 0xE004, 0x6D04, 0xAD06, 0x1A05, 0x0000, 0x5A04, 0x4D09, 0x8004, 0xED05, 0xD303, 0x6D0A, 0x0006, 0x0000, 0x2D05, 0x9304, 0x6602, 0xD303, 0x8D02, 0x2D05, 0xFA03, 0x0000, 0x6003, 0x1306, 0xED02, 0x0D04, 0xC602, 0x6006, 0xFA03, 0x0000, 0x0D04, 0xC608, 0xFA06, 0x6006, 0x1306, 0xC608, 0x0006, 0x0000, 0xC605, 0xAD06, 0xAD06, 0xFA06, 0xAD06, 0xAD06, 0xAD06, 0x0000, 0xFA06, 0x86F4, 0x86F4, 0xADF4, 0x86F4, 0x86F4, 0x86F4, 0x0000, 0xADF4, 0x4D06, 0x4D06, 0x5605, 0xA005, 0xED08, 0xA005, 0x0000, 0x5605, 0xED0B, 0x5A07, 0x6D07, 0xCD04, 0x600C, 0xE007, 0x0000, 0xA607};
const uint16_t sprite_gamemode_adjust_heights_50_Mg[] = {0x3AFA, 0x73FA, 0xD3FA, 0x6DFB, 0xADFA, 0x06FC, 0x0000, 0xDAFC, 0x33F8, 0xFAFA, 0x3AFA, 0xA6FB, 0x60F7, 0x33FB, 0x0000, 0x1AFC, 0x06FC, 0xC0FD, 0x06FC, 0xFAFD, 0xE0FB, 0x60FD, 0x0000, 0xADFD, 0x46FB, 0xC0FD, 0xBAFB, 0x6DFE, 0x06FC, 0x06FC, 0x0000, 0x73FD, 0x6DF8, 0x46F8, 0x00FA, 0xA0F9, 0x6DF8, 0xADFA, 0x0000, 0x06FC, 0x53F9, 0x53F9, 0x8DF9, 0x53F9, 0x53F9, 0x53F9, 0x0000, 0x8DF9, 0x7A0B, 0x7A0B, 0x530B, 0x7A0B, 0x7A0B, 0x7A0B, 0x0000, 0x530B, 0xB3F9, 0xB3F9, 0xAAFA, 0x60FA, 0x13F7, 0x60FA, 0x0000, 0xAAFA, 0x2DF6, 0xE6F7, 0x2DF9, 0xA0F9, 0x6DF5, 0xA0F9, 0x0000, 0xA6FB};
const uint16_t sprite_gamemode_adjust_heights_50_MG[] = {0xC605, 0x8D05, 0x2D05, 0x9304, 0x5305, 0xFA03, 0x0000, 0x2603, 0xCD07, 0x0605, 0xC605, 0x5A04, 0xA008, 0xCD04, 0x0000, 0xE603, 0xFA03, 0x4002, 0xFA03, 0x0602, 0x2004, 0xA002, 0x0000, 0x5302, 0xBA04, 0x4002, 0x4604, 0x9301, 0xFA03, 0xFA03, 0x0000, 0x8D02, 0x9307, 0xBA07, 0x0006, 0x6006, 0x9307, 0x5305, 0x0000, 0xFA03, 0xAD06, 0xAD06, 0x7306, 0xAD06, 0xAD06, 0xAD06, 0x0000, 0x7306, 0x86F4, 0x86F4, 0xADF4, 0x86F4, 0x86F4, 0x86F4, 0x0000, 0xADF4, 0x4D06, 0x4D06, 0x5605, 0xA005, 0xED08, 0xA005, 0x0000, 0x5605, 0xD309, 0x1A08, 0xD306, 0x6006, 0x930A, 0x6006, 0x0000, 0x5A04};
const uint16_t sprite_gamemode_adjust_heights_60_mg[] = {0x70FA, 0xB0FB, 0xF0FB, 0x50FC, 0x70FA, 0xC0FB, 0x0000, 0x60FC, 0x40F8, 0x40FC, 0x10FB, 0xD0FC, 0x50F7, 0x00FB, 0x0000, 0xB0FB, 0x30FC, 0x00FE, 0xD0FC, 0xE0FD, 0xB0FB, 0xB0FC, 0x0000, 0x30FD, 0xF0FA, 0x90FD, 0xA0FC, 0xB0FD, 0xB0FA, 0xB0FC, 0x0000, 0xA0FC, 0xB0F8, 0x30FA, 0xB0FA, 0xF0FA, 0xB0F8, 0x00FB, 0x0000, 0x30FB, 0x70FA, 0x70FA, 0x30FA, 0x70FA, 0x70FA, 0x70FA, 0x0000, 0x30FA, 0x9009, 0x9009, 0x7009, 0x9009, 0x9009, 0x9009, 0x0000, 0x7009, 0xC0FA, 0xC0FA, 0x8EFB, 0x50FB, 0x90F8, 0x50FB, 0x0000, 0x8EFB, 0x10F6, 0xE0F9, 0xD0F9, 0x00FC, 0xB0F5, 0x70F9, 0x0000, 0xA0F9};
const uint16_t sprite_gamemode_adjust_heights_60_mG[] = {0x9005, 0x5004, 0x1004, 0xB003, 0x9005, 0x4004, 0x0000, 0xA003, 0xC007, 0xC003, 0xF004, 0x3003, 0xB008, 0x0005, 0x0000, 0x5004, 0xD003, 0x0002, 0x3003, 0x2002, 0x5004, 0x5003, 0x0000, 0xD002, 0x1005, 0x7002, 0x6003, 0x5002, 0x5005, 0x5003, 0x0000, 0x6003, 0x5007, 0xD005, 0x5005, 0x1005, 0x5007, 0x0005, 0x0000, 0xD004, 0x9005, 0x9005, 0xD005, 0x9005, 0x9005, 0x9005, 0x0000, 0xD005, 0x70F6, 0x70F6, 0x90F6, 0x70F6, 0x70F6, 0x70F6, 0x0000, 0x90F6, 0x4005, 0x4005, 0x7204, 0xB004, 0x7007, 0xB004, 0x0000, 0x7204, 0xF009, 0x2006, 0x3006, 0x0004, 0x500A, 0x9006, 0x0000, 0x6006};
const uint16_t sprite_gamemode_adjust_heights_60_Mg[] = {0x30FB, 0x60FB, 0xB0FB, 0x30FC, 0x90FB, 0xB0FC, 0x0000, 0x60FD, 0x80F9, 0xD0FB, 0x30FB, 0x60FC, 0xD0F8, 0x00FC, 0x0000, 0xC0FC, 0xB0FC, 0x20FE, 0xB0FC, 0x50FE, 0x90FC, 0xD0FD, 0x0000, 0x10FE, 0x10FC, 0x20FE, 0x70FC, 0xB0FE, 0xB0FC, 0xB0FC, 0x0000, 0xE0FD, 0xB0F9, 0x90F9, 0x00FB, 0xB0FA, 0xB0F9, 0x90FB, 0x0000, 0xB0FC, 0x70FA, 0x70FA, 0xA0FA, 0x70FA, 0x70FA, 0x70FA, 0x0000, 0xA0FA, 0x9009, 0x9009, 0x7009, 0x9009, 0x9009, 0x9009, 0x0000, 0x7009, 0xC0FA, 0xC0FA, 0x8EFB, 0x50FB, 0x90F8, 0x50FB, 0x0000, 0x8EFB, 0xD0F7, 0x40F9, 0x50FA, 0xB0FA, 0x30F7, 0xB0FA, 0x0000, 0x60FC};
const uint16_t sprite_gamemode_adjust_heights_60_MG[] = {0xD004, 0xA004, 0x5004, 0xD003, 0x7004, 0x5003, 0x0000, 0xA002, 0x8006, 0x3004, 0xD004, 0xA003, 0x3007, 0x0004, 0x0000, 0x4003, 0x5003, 0xE001, 0x5003, 0xB001, 0x7003, 0x3002, 0x0000, 0xF001, 0xF003, 0xE001, 0x9003, 0x5001, 0x5003, 0x5003, 0x0000, 0x2002, 0x5006, 0x7006, 0x0005, 0x5005, 0x5006, 0x7004, 0x0000, 0x5003, 0x9005, 0x9005, 0x6005, 0x9005, 0x9005, 0x9005, 0x0000, 0x6005, 0x70F6, 0x70F6, 0x90F6, 0x70F6, 0x70F6, 0x70F6, 0x0000, 0x90F6, 0x4005, 0x4005, 0x7204, 0xB004, 0x7007, 0xB004, 0x0000, 0x7204, 0x3008, 0xC006, 0xB005, 0x5005, 0xD008, 0x5005, 0x0000, 0xA003};

const uint16_t * const sprite_gamemode_adjust_heights[] = {sprite_gamemode_adjust_heights_50_mg, sprite_gamemode_adjust_heights_50_mG, sprite_gamemode_adjust_heights_50_Mg, sprite_gamemode_adjust_heights_50_MG, sprite_gamemode_adjust_heights_60_mg, sprite_gamemode_adjust_heights_60_mG, sprite_gamemode_adjust_heights_60_Mg, sprite_gamemode_adjust_heights_60_MG};


#pragma rodata-name("XCD_BANK_00")

const uint8_t PAD_HEIGHT_BLUE_lo[] = {0x5A, 0xA6, 0x5A, 0xA6, 0xA0, 0x60, 0xA0, 0x60};
const uint8_t PAD_HEIGHT_BLUE_hi[] = {0x04, 0xFB, 0x04, 0xFB, 0x03, 0xFC, 0x03, 0xFC};


const uint8_t ORB_BALL_HEIGHT_BLUE_lo[] = {0xF3, 0x0D, 0xF3, 0x0D, 0xA0, 0x60, 0xA0, 0x60};
const uint8_t ORB_BALL_HEIGHT_BLUE_hi[] = {0x01, 0xFE, 0x01, 0xFE, 0x01, 0xFE, 0x01, 0xFE};



const uint8_t POS_DUAL_CAP_CHECK_lo[] = {0xC6, 0x50};
# 65 "C:/famidash/SAUCE\\defines/physics_table_defines.cmp.h"
const uint8_t NEG_DUAL_CAP_CHECK_lo[] = {0x3A, 0xB0};








#pragma rodata-name(MOVEMENT_BANK)

const uint8_t JUMP_VEL_lo[] = {0x53, 0xAD, 0x3A, 0xC6, 0x70, 0x90, 0x30, 0xD0};
const uint8_t JUMP_VEL_hi[] = {0xF9, 0x06, 0xFA, 0x05, 0xFA, 0x05, 0xFB, 0x04};


const uint8_t BALL_SWITCH_VEL_lo[] = {0x66, 0x9A, 0x5A, 0xA6, 0x00, 0x00, 0x20, 0xE0};
const uint8_t BALL_SWITCH_VEL_hi[] = {0x02, 0xFD, 0x01, 0xFE, 0x02, 0xFE, 0x01, 0xFE};


const uint8_t UFO_JUMP_VEL_lo[] = {0x2D, 0xD3, 0xA0, 0x60, 0xD0, 0x30, 0x30, 0xD0};
const uint8_t UFO_JUMP_VEL_hi[] = {0xFC, 0x03, 0xFC, 0x03, 0xFC, 0x03, 0xFD, 0x02};


const uint8_t ROBOT_JUMP_VEL_lo[] = {0xC6, 0x3A, 0xC6, 0x3A, 0x50, 0xB0, 0x50, 0xB0};
const uint8_t ROBOT_JUMP_VEL_hi[] = {0xFC, 0x03, 0xFC, 0x03, 0xFD, 0x02, 0xFD, 0x02};



const uint8_t ROBOT_JUMP_TIME[] = {0x10, 0x13};


const uint8_t CUBE_MAX_FALLSPEED_lo[] = {0x33, 0xCD, 0x33, 0xCD, 0x00, 0x00, 0x00, 0x00};
const uint8_t CUBE_MAX_FALLSPEED_hi[] = {0x07, 0xF8, 0x07, 0xF8, 0x06, 0xFA, 0x06, 0xFA};


const uint8_t SHIP_MAX_FALLSPEED_lo[] = {0x69, 0x97, 0x03, 0xFD, 0xD7, 0x29, 0x57, 0xA9};
const uint8_t SHIP_MAX_FALLSPEED_hi[] = {0x03, 0xFC, 0x04, 0xFB, 0x02, 0xFD, 0x03, 0xFC};


const uint8_t SHIP_MAX_FALLSPEED_HOLD_lo[] = {0x43, 0xBD, 0x03, 0xFD, 0x8D, 0x73, 0x2D, 0xD3};
const uint8_t SHIP_MAX_FALLSPEED_HOLD_hi[] = {0x04, 0xFB, 0x05, 0xFA, 0x03, 0xFC, 0x04, 0xFB};


const uint8_t BALL_MAX_FALLSPEED_lo[] = {0x33, 0xCD, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
const uint8_t BALL_MAX_FALLSPEED_hi[] = {0x07, 0xF8, 0x06, 0xFA, 0x06, 0xFA, 0x05, 0xFB};


const uint8_t UFO_MAX_FALLSPEED_lo[] = {0xC0, 0x40, 0xFA, 0x06, 0x20, 0xE0, 0x50, 0xB0};
const uint8_t UFO_MAX_FALLSPEED_hi[] = {0x03, 0xFC, 0x03, 0xFC, 0x03, 0xFC, 0x03, 0xFC};


const uint8_t SPIDER_MAX_FALLSPEED_lo[] = {0x33, 0xCD, 0x33, 0xCD, 0x00, 0x00, 0x00, 0x00};
const uint8_t SPIDER_MAX_FALLSPEED_hi[] = {0x07, 0xF8, 0x07, 0xF8, 0x06, 0xFA, 0x06, 0xFA};


const uint8_t SWING_MAX_FALLSPEED_lo[] = {0x9A, 0x66, 0xFC, 0x04, 0x00, 0x00, 0x52, 0xAE};
const uint8_t SWING_MAX_FALLSPEED_hi[] = {0x03, 0xFC, 0x03, 0xFC, 0x03, 0xFD, 0x03, 0xFC};


#pragma rodata-name(SCROLL_BANK)


const uint8_t SHIP_SCROLL_SPEED_lo[] = {0x66, 0x00};








#pragma rodata-name(MOVEMENT_BANK)


const uint8_t SHIP_GRAVITY_BASE_lo[] = {0x3C, 0xC4, 0x47, 0xB9, 0x2A, 0xD6, 0x31, 0xCF};
const uint8_t SHIP_GRAVITY_BASE_hi[] = {0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF};


const uint8_t SHIP_GRAVITY_lo[] = {0x30, 0xD0, 0x39, 0xC7, 0x22, 0xDE, 0x27, 0xD9};
const uint8_t SHIP_GRAVITY_hi[] = {0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF};


const uint8_t SHIP_GRAVITY_AFTER_HOLD_lo[] = {0x49, 0xB7, 0x55, 0xAB, 0x32, 0xCE, 0x3B, 0xC5};
const uint8_t SHIP_GRAVITY_AFTER_HOLD_hi[] = {0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF};


const uint8_t SHIP_GRAVITY_HOLD_FALL_lo[] = {0x4C, 0xB4, 0x59, 0xA7, 0x34, 0xCC, 0x3E, 0xC2};
const uint8_t SHIP_GRAVITY_HOLD_FALL_hi[] = {0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF};


const uint8_t BALL_GRAVITY_lo[] = {0x66, 0x9A, 0x7D, 0x83, 0x47, 0xB9, 0x57, 0xA9};
const uint8_t BALL_GRAVITY_hi[] = {0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF};


const uint8_t UFO_GRAVITY_lo[] = {0x48, 0xB8, 0x48, 0xB8, 0x32, 0xCE, 0x32, 0xCE};
const uint8_t UFO_GRAVITY_hi[] = {0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF};


const uint8_t SPIDER_GRAVITY_lo[] = {0x6C, 0x94, 0x6C, 0x94, 0x4B, 0xB5, 0x4B, 0xB5};
const uint8_t SPIDER_GRAVITY_hi[] = {0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF};


const uint8_t SWING_GRAVITY_lo[] = {0x48, 0xB8, 0x51, 0xAF, 0x32, 0xCE, 0x38, 0xC8};
const uint8_t SWING_GRAVITY_hi[] = {0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF};


#pragma rodata-name("RODATA")

const uint8_t CUBE_GRAVITY_lo[] = {0x9A, 0x66, 0xA0, 0x60, 0x6B, 0x95, 0x6F, 0x91};
const uint8_t CUBE_GRAVITY_hi[] = {0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF};


const uint8_t MAKE_CUBE_JUMP_HIGHER_lo[] = {0x66, 0x9A, 0x66, 0x9A, 0x80, 0x80, 0x80, 0x80};
const uint8_t MAKE_CUBE_JUMP_HIGHER_hi[] = {0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00};


const uint8_t EXIT_SLOPE_BALL_22_lo[] = {0xA0, 0x60, 0xA0, 0x60, 0xB0, 0x50, 0xB0, 0x50};
const uint8_t EXIT_SLOPE_BALL_22_hi[] = {0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00};


const uint8_t EXIT_SLOPE_BALL_66_lo[] = {0x93, 0x6D, 0x93, 0x6D, 0x50, 0xB0, 0x50, 0xB0};
const uint8_t EXIT_SLOPE_BALL_66_hi[] = {0x01, 0xFE, 0x01, 0xFE, 0x01, 0xFE, 0x01, 0xFE};


const uint8_t EXIT_SLOPE_CUBE_22_lo[] = {0xCD, 0x33, 0xCD, 0x33, 0x00, 0x00, 0x00, 0x00};
const uint8_t EXIT_SLOPE_CUBE_22_hi[] = {0xFE, 0x01, 0xFE, 0x01, 0xFF, 0x01, 0xFF, 0x01};


const uint8_t DASH_END_VEL_RESET_lo[] = {0x33, 0xCD, 0x33, 0xCD, 0x00, 0x00, 0x00, 0x00};
const uint8_t DASH_END_VEL_RESET_hi[] = {0x01, 0xFE, 0x01, 0xFE, 0x01, 0xFF, 0x01, 0xFF};
# 14 "probe/tu_collision.c" 2
# 1 "C:/famidash/LEVELS/include/lvlset_A\\objdefines.h" 1
# 15 "probe/tu_collision.c" 2
# 1 "C:/famidash/SAUCE\\famidash.h" 1
# 56 "C:/famidash/SAUCE\\famidash.h"
#pragma bss-name("ZEROPAGE")

uint8_t tmp1;
uint8_t tmp2;
uint8_t tmp3;
uint8_t tmp4;
uint16_t tmp5;
uint16_t tmp6;
uint8_t tmp7;
uint8_t tmp8;
uint8_t tmp9;
uint16_t tmpA;
uint16_t tmpB;
int16_t tmpfallspeed;
int16_t tmpgravity;
uint8_t iconbank1;
uint8_t iconbank2;
uint8_t iconbank3;
uint8_t* tmpptr1;
uint8_t* tmpptr2;
uint32_t tmplong;
uint8_t selectedbgm;
uint8_t selectedsfx;
int8_t tmpi8;

#pragma zpsym("tmpptr1")
#pragma zpsym("tmpptr2")



extern uint8_t cc65_tmp1;
extern uint8_t cc65_tmp2;
extern uint8_t cc65_tmp3;
extern uint8_t cc65_tmp4;
extern uint16_t cc65_ptr1;
extern uint16_t cc65_ptr2;
extern uint16_t cc65_ptr3;
extern uint16_t cc65_ptr4;

extern void * cc65_sp;
extern uint16_t cc65_sreg;

#pragma zpsym("cc65_tmp1")
#pragma zpsym("cc65_tmp2")
#pragma zpsym("cc65_tmp3")
#pragma zpsym("cc65_tmp4")
#pragma zpsym("cc65_ptr1")
#pragma zpsym("cc65_ptr2")
#pragma zpsym("cc65_ptr3")
#pragma zpsym("cc65_ptr4")

#pragma zpsym("cc65_sp")
#pragma zpsym("cc65_sreg")

extern volatile unsigned char VRAM_UPDATE;
#pragma zpsym ("VRAM_UPDATE")

uint8_t currplayer_mini;
uint16_t currplayer_x;
uint16_t currplayer_y;
int16_t currplayer_vel_x;
int16_t currplayer_vel_y;
uint8_t currplayer_gravity;
uint8_t currplayer_x_small;
uint8_t currplayer_y_small;
int8_t currplayer_vel_y_small;
int8_t currplayer_slope_frames;
uint8_t currplayer_was_on_slope_counter;
uint8_t currplayer_slope_type;
uint8_t currplayer_last_slope_type;
uint8_t currplayer_direction;
uint8_t currplayer_table_idx;

uint8_t gamemode;
uint8_t cube_data[2];
uint16_t cube_rotate[2];

uint8_t collision;
uint8_t collision_L;
uint8_t collision_R;
uint8_t collision_U;
uint8_t collision_D;

uint16_t old_x;
uint16_t old_y;

uint8_t eject_L;
uint8_t eject_R;
uint8_t eject_D;
uint8_t eject_U;

uintptr_t address;
uint8_t x;
uint8_t y;
uint8_t index;
uint8_t temp_x;
uint8_t temp_y;
uint8_t temp_room;
uint8_t dual;
int8_t slope_frames[2];

uint8_t slope_type[2];
uint8_t was_on_slope_counter[2];
uint8_t * sprite_data;
uint8_t * level_data;

#pragma zpsym("sprite_data")
#pragma zpsym("level_data")

extern uint8_t framerate;
extern uint8_t cpuRegion;
extern uint8_t fullRegion;

#pragma zpsym ("framerate")
#pragma zpsym ("cpuRegion")
#pragma zpsym ("fullRegion")


#pragma bss-name("SRAM")
uint8_t SRAM_VALIDATE[4];

uint8_t coin1_obtained[0xFF];
uint8_t coin2_obtained[0xFF];
uint8_t coin3_obtained[0xFF];

uint8_t LEVELCOMPLETE[0xFF];
uint8_t level_completeness_normal[0xFF*2];


uint8_t invisible_coin1_obtained[0xFF];
uint8_t invisible_coin2_obtained[0xFF];
uint8_t invisible_coin3_obtained[0xFF];

uint8_t invisible_LEVELCOMPLETE[0xFF];
uint8_t invisible_level_completeness_normal[0xFF*2];




uint8_t invisible;
uint8_t twoplayer;







uint8_t options;
# 214 "C:/famidash/SAUCE\\famidash.h"
uint8_t practice_music_sync;

uint8_t icon;
uint8_t icon_colors[3];





uint8_t cursedmusic;
uint8_t discomode;
uint8_t trails;
uint8_t viseffects;
uint8_t retro_mode;
uint8_t palette_cycle_mode;
uint8_t gameboy_mode;
uint8_t invisblocks;
uint8_t cam_seesaw;
uint8_t forced_credits;
extern uint8_t extceil;
uint8_t drawBarFlag;
uint8_t exitPortalTimer;
uint8_t menu_music;

uint8_t auto_practicepoints;







uint8_t practice_point_count;
uint8_t curr_practice_point;
uint8_t latest_practice_point;


uint8_t practice_player_1_x_lo[8]; uint8_t practice_player_1_x_hi[8];
uint8_t practice_player_1_vel_x_lo[8]; uint8_t practice_player_1_vel_x_hi[8];
uint8_t practice_player_1_y_lo[8]; uint8_t practice_player_1_y_hi[8];
uint8_t practice_player_1_vel_y_lo[8]; uint8_t practice_player_1_vel_y_hi[8];
uint8_t practice_cube_1_rotate_lo[8]; uint8_t practice_cube_1_rotate_hi[8];

uint8_t practice_player_2_x_lo[8]; uint8_t practice_player_2_x_hi[8];
uint8_t practice_player_2_vel_x_lo[8]; uint8_t practice_player_2_vel_x_hi[8];
uint8_t practice_player_2_y_lo[8]; uint8_t practice_player_2_y_hi[8];
uint8_t practice_player_2_vel_y_lo[8]; uint8_t practice_player_2_vel_y_hi[8];
uint8_t practice_cube_2_rotate_lo[8]; uint8_t practice_cube_2_rotate_hi[8];

uint8_t practice_player_1_gravity[8];
uint8_t practice_player_2_gravity[8];
uint8_t practice_player_1_mini[8];
uint8_t practice_player_2_mini[8];
uint8_t practice_player_1_was_on_slope_counter[8];
uint8_t practice_player_2_was_on_slope_counter[8];
int8_t practice_player_1_slope_frames[8];
int8_t practice_player_2_slope_frames[8];
int8_t practice_player_1_slope_type[8];
int8_t practice_player_2_slope_type[8];
int8_t practice_player_1_last_slope_type[8];
int8_t practice_player_2_last_slope_type[8];

uint8_t practice_scroll_x_lo[8]; uint8_t practice_scroll_x_md[8]; uint8_t practice_scroll_x_hi[8]; uint8_t practice_scroll_x_ex[8];
uint8_t practice_scroll_y_lo[8]; uint8_t practice_scroll_y_hi[8];
uint8_t practice_scroll_y_subpx[8];
uint8_t practice_min_scroll_y_lo[8]; uint8_t practice_min_scroll_y_hi[8];
uint8_t practice_seam_scroll_y_lo[8]; uint8_t practice_seam_scroll_y_hi[8];
uint8_t practice_old_draw_scroll_y_lo[8]; uint8_t practice_old_draw_scroll_y_hi[8];
uint8_t practice_target_scroll_y_lo[8]; uint8_t practice_target_scroll_y_hi[8];

uint8_t practice_nocamlockforced[8];
uint8_t practice_disco_sprites[8];
uint8_t practice_slowmode[8];
uint8_t practice_forced_trails[8];
uint8_t practice_gravity_mod[8];
uint8_t practice_player_gamemode[8];
uint8_t practice_dual[8];
uint8_t practice_speed[8];
uint8_t practice_parallax_scroll_x[8];
uint8_t practice_outline_color[8];
uint8_t practice_g_color_type[8];
uint8_t practice_bg_color_type[8];


uint8_t practice_orbactive[8];
uint8_t practice_nullscapes_active[8];
uint8_t practice_nullscapes_orb_type[8];
uint8_t practice_kandoframecnt[8];

uint8_t practice_song[8];
uint8_t practice_player_invis[8];

uint8_t practice_famistudio_state[172 * 8];
uint8_t practice_famistudio_registers[11 * 8];
# 318 "C:/famidash/SAUCE\\famidash.h"
#pragma bss-name("BSS")

extern uint8_t trueFramerate;
extern uint8_t trueCpuRegion;
extern uint8_t trueFullRegion;

uint8_t last_gameState;

uint16_t player_x[2];
uint16_t player_y[2];
int16_t player_vel_x[2];
int16_t player_vel_y[2];
uint8_t player_gravity[2];
uint8_t player_mini[2];
uint8_t orbhitonthisframe[2];
uint8_t chargepower[2];


uint8_t practice_sprite_x_pos;

uint8_t kandokidshack;
uint8_t kandokidshack2;
uint8_t kandokidshack3;
uint8_t kandokidshack4;
uint8_t menuthemechosen;
uint8_t menutheme;
# 354 "C:/famidash/SAUCE\\famidash.h"
uint16_t exittimer;
uint16_t jumps;
uint8_t orbed[2];
uint8_t speed;
uint8_t shuffle_offset;
uint8_t count;
uint8_t coins;
uint8_t currplayer;
uint8_t menuMusicCurrentlyPlaying;
uint8_t ball_switched[2];
uint8_t processXMovement;


uint8_t kandoframecnt;



uint8_t spiderframe[2];
uint8_t robotframe[2];
uint8_t ballframe;
uint8_t robotjumpframe[2];
uint8_t robotjumptime[2];
uint8_t hblocked[2];
uint8_t jblocked[2];
uint8_t fblocked[2];
uint8_t ninjajumps[2];
uint8_t slowmode;
uint8_t use_auto_chrswitch;
uint8_t level;
uint8_t level_data_bank;
uint8_t sprite_data_bank;
uint8_t menuselection;
uint8_t settingvalue;
uint8_t mouseframe;
uint8_t hold_timer;
uint8_t titlemode;
uint8_t titlecolor1;
uint8_t titlecolor2;
uint8_t titlecolor3;
uint8_t titleicon;
uint8_t kandodebugmode;

uint8_t all_levels_complete;
uint16_t triggers;
uint16_t top_triggers;

uint8_t current_deco_type;
uint8_t current_spike_set;
uint8_t current_block_set;
uint8_t current_saw_set;

uint8_t nocamlock;
uint8_t nocamlockforced;
uint8_t nestopia;

uint8_t nullscapes_orb_type;
uint8_t nullscapes_active;

uint8_t last_slope_type[2];

uint8_t gameState;

uint8_t teleport_output;

uint8_t normalorcommlevels;
uint8_t mouse_timer;
uint8_t prev_mouse_x;
uint8_t prev_mouse_y;




uint8_t level_resetting_flag;
uint8_t timewarp_done;

extern uint8_t parallax_scroll_column;
extern uint8_t parallax_scroll_column_start;
uint8_t parallax_scroll_x;
uint8_t invincible_counter;
uint32_t scroll_x;
uint16_t scroll_y;
uint8_t scroll_y_subpx;
uint16_t old_trail_scroll_y;
uint16_t target_scroll_y;

uint8_t song;
uint8_t songplaying;
uint8_t tempsong;
uint8_t temptemp6;
uint8_t make_cube_jump_higher;
uint8_t fartmode;

uint8_t animating;
uint8_t coin1_timer;
uint8_t coin2_timer;
uint8_t coin3_timer;
uint16_t coin1_speed;
uint16_t coin2_speed;
uint16_t coin3_speed;

uint16_t spawn_y_pos;
uint16_t spawn_scroll_y_pos;
uint8_t max_fallspeed_7;






uint8_t orbactive;
uint8_t trail_sprites_visible[9];

uint8_t ufo_orbed[2];
uint8_t black_orbed[2];

uint8_t dashing[2];

uint8_t wrap_mode;
uint8_t minicoins;


uint16_t auto_practicepoint_timer;


uint8_t cheated;


uint8_t activesprites_x_lo[16]; uint8_t activesprites_x_hi[16];
uint8_t activesprites_y_lo[16]; uint8_t activesprites_y_hi[16];
uint8_t activesprites_type[16];
uint8_t activesprites_anim_frame[16];
int8_t activesprites_anim_frame_count[16];

uint8_t activesprites_realx[16];
uint8_t activesprites_realy[16];
uint8_t activesprites_active[16];
uint8_t activesprites_activated[16];
uint8_t activesprites_animated[16];



uint8_t DEBUG_MODE;
uint8_t lastgcolortype;
uint8_t lastbgcolortype;
uint8_t iconbank;
uint8_t dblocked[2];


uint8_t player_old_posy[9];
uint8_t discorefreshrate;
uint8_t discoframe;
uint8_t no_parallax;
uint8_t force_platformer;
uint8_t outline_color;
uint8_t forced_trails;
uint8_t skipProcessingCubeRotationLogic;

uint8_t attemptCounter[7];
uint8_t triggers_hit[3];
uint8_t pauseStatus;

uint8_t forceNoFadeOut;
# 536 "C:/famidash/SAUCE\\famidash.h"
uint16_t target_x_scroll_stop;
uint16_t curr_x_scroll_stop;
uint8_t disco_sprites;
uint8_t gravity_mod;


uint8_t practicebuffer;
uint8_t tempplat;

unsigned char END_LEVEL_TIMER;





uint8_t donotresetrng;

uint8_t player_invis;

extern uint8_t famistudio_song_speed;

extern uint16_t min_scroll_y;
extern uint16_t seam_scroll_y;

extern volatile uint8_t hexToDecOutputBuffer[5];
# 580 "C:/famidash/SAUCE\\famidash.h"
struct Base {
 uint8_t x;
 uint8_t y;
 uint8_t width;
 uint8_t height;
};

struct Base Generic;
struct Base Generic2;
# 16 "probe/tu_collision.c" 2
# 1 "C:/famidash\\METATILES/metatiles.h" 1
# 67 "C:/famidash\\METATILES/metatiles.h"
extern const unsigned char metatiles_top1[];
extern const unsigned char metatiles_top2[];
extern const unsigned char metatiles_bot1[];
extern const unsigned char metatiles_bot2[];
extern const unsigned char metatiles_attr[];
extern const unsigned char is_solid[];
# 17 "probe/tu_collision.c" 2
# 1 "C:/famidash/SAUCE\\functions/collision.h" 1
# 37 "C:/famidash/SAUCE\\functions/collision.h"
char bg_collision_sub();
void commonly_used_store();
void commonly_stored_routine_2();
void commonly_used_death_check();
void tmp20f();






char bg_coll_sides() {
 switch (collision) {
  case 0x07:
   return 1;
  case 0x06:
   if ((uint8_t)(temp_y & 0x08) && !force_platformer) return 1;
   break;
  case 0x05:
   if (!(uint8_t)(temp_y & 0x08) && !force_platformer) return 1;
   break;
  case 0x09:
   if (gamemode == 0x06 || gamemode == 0x0A) return 0;

 };
 return 0;
}

#pragma warn (unreachable-code, push, off)
char col_death_bottom_routine() {
 if ((uint8_t)(temp_y & 0x0f) > 0x0a) {

  do { if ((uint8_t)((uint8_t)(temp_x & 0x0f)) >= (0x05) && (uint8_t)((uint8_t)(temp_x & 0x0f)) <= (0x08-1)) { cube_data[currplayer] = 1; return 1; } } while (0);



 }
 return 0;
}

char col_death_top_routine() {
 if ((uint8_t)(temp_y & 0x0f) < 0x06) {

  do { if ((uint8_t)((uint8_t)(temp_x & 0x0f)) >= (0x05) && (uint8_t)((uint8_t)(temp_x & 0x0f)) <= (0x08-1)) { cube_data[currplayer] = 1; return 1; } } while (0);



 }
 return 0;
}

char col_death_right_routine() {
 if ((uint8_t)(temp_x & 0x0f) >= 0x0a) {
  do { if ((uint8_t)((uint8_t)(temp_y & 0x0f)) >= (0x06) && (uint8_t)((uint8_t)(temp_y & 0x0f)) <= (0x09-1)) { cube_data[currplayer] = 1; return 1; } } while (0);



 }
 return 0;
}

char col_death_left_routine() {
 if ((uint8_t)(temp_x & 0x0f) < 0x06) {
  do { if ((uint8_t)((uint8_t)(temp_y & 0x0f)) >= (0x06) && (uint8_t)((uint8_t)(temp_y & 0x0f)) <= (0x09-1)) { cube_data[currplayer] = 1; return 1; } } while (0);



 }
 return 0;
}






char bg_coll_spikes() {

 switch (collision) {
  case 0x02:
   return col_death_left_routine();

  case 0x01:
   return col_death_right_routine();

  case 0x03:
   return col_death_top_routine();

  case 0x3d:
  case 0x3b:
  case 0x04:
   return col_death_bottom_routine();

  case 0x36:
   tmp2 = col_death_left_routine();
   return (((((col_death_bottom_routine()) & 0xFF)))) | tmp2;

  case 0x35:
   tmp2 = col_death_right_routine();
   return (((((col_death_bottom_routine()) & 0xFF)))) | tmp2;

  case 0x34:
   tmp2 = col_death_left_routine();
   return (((((col_death_top_routine()) & 0xFF)))) | tmp2;

  case 0x33:
   tmp2 = col_death_right_routine();
   return (((((col_death_top_routine()) & 0xFF)))) | tmp2;

  case 0x08:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   if (tmp2 >= 0x04 && tmp2 < 0x0c) {
    do { if ((uint8_t)((uint8_t)(temp_x & 0x0f)) >= (0x04) && (uint8_t)((uint8_t)(temp_x & 0x0f)) <= (0x09-1)) {goto bg_coll_spikes_break;} } while (0);
   }
   return 0;
  case 0x2b:
  case 0x2d:
   if (!(uint8_t)(temp_y & 0x08)) {
    do { if ((uint8_t)((uint8_t)(temp_x & 0x0f)) >= (0x02) && (uint8_t)((uint8_t)(temp_x & 0x0f)) <= (0x06-1)) {goto bg_coll_spikes_break;} } while (0);
   }
   return 0;
  case 0x2c:
  case 0x2e:
   if (!(uint8_t)(temp_y & 0x08)) {
    do { if ((uint8_t)((uint8_t)(temp_x & 0x0f)) >= (0x0a) && (uint8_t)((uint8_t)(temp_x & 0x0f)) <= (0x0d-1)) {goto bg_coll_spikes_break;} } while (0);
   }
   return 0;
  case 0x3c:
   if (!(uint8_t)(temp_y & 0x08)) {
    do { if ((uint8_t)((uint8_t)(temp_x & 0x0f)) >= (0x07) && (uint8_t)((uint8_t)(temp_x & 0x0f)) <= (0x0b-1)) {goto bg_coll_spikes_break;} } while (0);
   }
   return 0;
  case 0x2f:
   if (!(uint8_t)(temp_y & 0x08)) {
    do { if ((uint8_t)((uint8_t)(temp_x & 0x07)) >= (0x02) && (uint8_t)((uint8_t)(temp_x & 0x07)) <= (0x06-1)) {goto bg_coll_spikes_break;} } while (0);
   }
   return 0;
  case 0x30:
   if (!(uint8_t)(temp_y & 0x08)) {
    do { if ((uint8_t)((uint8_t)(temp_x & 0x0f)) >= (0x02) && (uint8_t)((uint8_t)(temp_x & 0x0f)) <= (0x06-1)) {goto bg_coll_spikes_break;} } while (0);
   }
   return 0;
  case 0x31:
   if (!(uint8_t)(temp_y & 0x08)) {
    do { if ((uint8_t)((uint8_t)(temp_x & 0x0f)) >= (0x0a) && (uint8_t)((uint8_t)(temp_x & 0x0f)) <= (0x0d-1)) {goto bg_coll_spikes_break;} } while (0);
   }
   return 0;
  case 0x32:
   if (!(uint8_t)(temp_y & 0x08)) {
    do { if ((uint8_t)((uint8_t)(temp_x & 0x07)) >= (0x02) && (uint8_t)((uint8_t)(temp_x & 0x07)) <= (0x06-1)) {goto bg_coll_spikes_break;} } while (0);
   }
   return 0;
  case 0x28:
   if ((uint8_t)(temp_y & 0x08)) {
    do { if ((uint8_t)((uint8_t)(temp_x & 0x0f)) >= (0x02) && (uint8_t)((uint8_t)(temp_x & 0x0f)) <= (0x06-1)) {goto bg_coll_spikes_break;} } while (0);
   }
   return 0;
  case 0x29:
   if ((uint8_t)(temp_y & 0x08)) {
    do { if ((uint8_t)((uint8_t)(temp_x & 0x0f)) >= (0x0a) && (uint8_t)((uint8_t)(temp_x & 0x0f)) <= (0x0d-1)) {goto bg_coll_spikes_break;} } while (0);
   }
   return 0;
  case 0x2a:
   if ((uint8_t)(temp_y & 0x08)) {
    do { if ((uint8_t)((uint8_t)(temp_x & 0x07)) >= (0x02) && (uint8_t)((uint8_t)(temp_x & 0x07)) <= (0x06-1)) {goto bg_coll_spikes_break;} } while (0);
   }
   return 0;
  default: return 0;
 }

 bg_coll_spikes_break:
 cube_data[currplayer] = 1;
 return 1;
}

#pragma warn(unreachable-code, pop)





void bg_coll_floor_spikes() {
 if (currplayer_vel_y) {
  currplayer_direction = (*((uint8_t *)&(currplayer_vel_y) + 1)) & 0x80;
 }


 temp_x = Generic.x + (*((uint16_t *)&(scroll_x))) + 3;

 commonly_used_store();

 bg_collision_sub();

 if (collision) {
  if (bg_coll_spikes()) return;
 }

 temp_x += Generic.width - 6;

 bg_collision_sub();

 if (collision) {
  if (bg_coll_spikes()) return;
 }


 temp_x = Generic.x + (*((uint16_t *)&(scroll_x))) + 3;

 commonly_stored_routine_2();

 bg_collision_sub();

 if (collision) {
  if (bg_coll_spikes()) return;
 }

 temp_x += Generic.width - 6;

 bg_collision_sub();

 if (collision) {
  if (bg_coll_spikes()) return;
 }
}





char bg_coll_top_bottom_slabs() {
 switch (collision) {
  case 0x06:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp8 = tmp2 & 0x07;

   if (tmp8 != tmp2) {
    return 1;
   }
   break;
  case 0x05:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp8 = tmp2 & 0x07;

   if (tmp8 == tmp2) {
    return 1;
   }
   break;
  };
 return 0;
}


char bg_coll_mini_blocks() {
 if (collision != 0x09 && (*((uint8_t *)&(currplayer_x) + 1)) < 0x10) return 0;
 switch (collision) {
  case 0x20:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp8 = tmp2 & 0x07;
   if (tmp2 < 0x08 && ((uint8_t)(temp_x & 0x0f) < 0x08)) {
    return 1;
   }
   break;
  case 0x21:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp8 = tmp2 & 0x07;
   if (tmp2 < 0x08 && ((uint8_t)(temp_x & 0x0f) >= 0x08)) {
    return 1;
   }
   break;
  case 0x22:
  case 0x2b:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp8 = tmp2 & 0x07;
   if (tmp2 >= 0x08 && ((uint8_t)(temp_x & 0x0f) < 0x08)) {
    return 1;
   }
   break;
  case 0x23:
  case 0x2c:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp8 = tmp2 & 0x07;
   if (tmp2 >= 0x08 && ((uint8_t)(temp_x & 0x0f) >= 0x08)) {
    return 1;
   }
   break;
  case 0x2d:
  case 0x2e:
  case 0x3c:
  case 0x2f:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp8 = tmp2 & 0x07;

   if (tmp8 != tmp2) {
    return 1;
   }
   break;

  case 0x3d:
  case 0x3b:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp8 = tmp2 & 0x07;

   if (tmp8 == tmp2) {
    return 1;
   }
   break;
  case 0x24:
   tmp8 = (uint8_t)(temp_y & 0x0f) & 0x0f;
   if ((uint8_t)(temp_x & 0x0f) < 0x08) {
    return 1;
   }
   break;
  case 0x25:
   tmp8 = (uint8_t)(temp_y & 0x0f) & 0x0f;
   if ((uint8_t)(temp_x & 0x0f) >= 0x08) {
    return 1;
   }
   break;
  case 0x26:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp8 = tmp2 & 0x07;
   if ((uint8_t)(temp_x & 0x0f) < 0x08) {
    if (tmp2 < 0x08) return 1;
   } else {
    if (tmp2 >= 0x08) return 1;
   }
   break;
  case 0x27:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp8 = tmp2 & 0x07;
   if ((uint8_t)(temp_x & 0x0f) < 0x08) {
    if (tmp2 >= 0x08) return 1;
   } else {
    if (tmp2 < 0x08) return 1;
   }
   break;
  case 0x39:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp4 = (uint8_t)(temp_x & 0x0f);
   tmp8 = tmp2 & 0x07;

   if (tmp2 >= 0x08 && tmp4 < 0x08) {
    break;
   }
   return 1;

  case 0x3a:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp4 = (uint8_t)(temp_x & 0x0f);
   tmp8 = tmp2 & 0x07;

   if (tmp2 >= 0x08 && tmp4 >= 0x08) {
    break;
   }
   return 1;

  case 0x37:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp4 = (uint8_t)(temp_x & 0x0f);
   tmp8 = tmp2 & 0x07;

   if (tmp2 < 0x08 && tmp4 < 0x08) {
    break;
   }
   return 1;

  case 0x38:
   tmp2 = (uint8_t)(temp_y & 0x0f);
   tmp4 = (uint8_t)(temp_x & 0x0f);
   tmp8 = tmp2 & 0x07;

   if (tmp2 < 0x08 && tmp4 >= 0x08) {
    break;
   }
   return 1;
 }

 return 0;
}

char bg_coll_slope();






char bg_side_coll_common() {
 tmp1 = Generic.y + (currplayer_mini ? ((((0x10 - Generic.height) & 0xFF)) >> 1) : 0) + (Generic.height >> 1);

 if (currplayer_mini && (gamemode == 0x00 || gamemode == 0x04 || gamemode == 0x08)) {
  tmp1 += (currplayer_gravity ? 3 : -2);
 }

 if (currplayer_was_on_slope_counter | currplayer_slope_frames) {
  return 0;
 }

 do { uint16_t sws_ = (uint16_t)(add_scroll_y(tmp1, scroll_y)); (temp_y) = (uint8_t)sws_; (temp_room) = (uint8_t)(sws_ >> 8); } while (0);

 bg_collision_sub();
 if (collision) {
  if (gamemode == 0x06 || gamemode == 0x0A) {
   if (bg_coll_slope()) {
    if (!dblocked[currplayer]) {
     ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] | 1));
    }
   }
  } else {
   if (!currplayer_was_on_slope_counter && bg_coll_slope()) {
    (*((uint8_t *)&(currplayer_y) + 1)) += (currplayer_slope_type & 0b1000 ? 2 : -2);
   }
  }

  if (bg_coll_spikes()) return 0;

  return bg_coll_sides() || bg_coll_mini_blocks() || bg_coll_top_bottom_slabs();
 }

 return 0;
}





char bg_coll_R() {

 temp_x = Generic.x + (*((uint16_t *)&(scroll_x))) + Generic.width + ((options & 0x04 || force_platformer) ? 3 : 0);
 return bg_side_coll_common();
}





char bg_coll_L() {

 temp_x = Generic.x + (*((uint16_t *)&(scroll_x))) - ((options & 0x04 || force_platformer) ? 3 : 0);
 return bg_side_coll_common();
}
# 486 "C:/famidash/SAUCE\\functions/collision.h"
char bg_coll_U_D_checks() {
 switch (collision) {
  case 0x1f:
   return 1;
  case 0x07:
   if ((*((uint8_t *)&(currplayer_x) + 1)) < 0x10) return 0;
   else return 1;
  case 0x03:
   col_death_top_routine();
   break;
  case 0x04:
   col_death_bottom_routine();
   break;
  case 0x09:
   dblocked[currplayer] = 1;
   return 1;
 }

 return 0;
}

void clear_slope_vars() {
 currplayer_was_on_slope_counter = 0;
 currplayer_slope_frames = 0;
 currplayer_slope_type = 0;
 currplayer_last_slope_type = 0;
}

char a_check_lookup[] = {
 1, 0, 0, 1, 1, 0, 0, 1
};






char bg_coll_slope() {

 static const void * const jumpTable[] = {
  &&col_default, &&col_default, &&col_default, &&col_default,
  &&col_default, &&col_default, &&col_default, &&col_default,
  &&col_default, &&col_default, &&col_default,

  &&col_slope_RD45, &&col_slope_LD45,
  &&col_slope_RD22_RIGHT, &&col_slope_LD22_RIGHT,
  &&col_slope_RD22_LEFT, &&col_slope_LD22_LEFT,
  &&col_slope_RD66_TOP, &&col_slope_LD66_TOP,
  &&col_slope_RD66_BOT, &&col_slope_LD66_BOT,
  &&col_slope_RU45, &&col_slope_LU45,
  &&col_slope_RU22_LEFT, &&col_slope_RU22_RIGHT,
  &&col_slope_LU22_LEFT, &&col_slope_LU22_RIGHT,
  &&col_slope_RU66_TOP, &&col_slope_LU66_TOP,
  &&col_slope_RU66_BOT, &&col_slope_LU66_BOT
 };

 tmp8 = (temp_y) & 0x0f;

 do { if ((uint8_t)(collision) < (0x0b) || (uint8_t)(collision) > (0x1e)) {return 0;} } while (0);
 goto *jumpTable[collision];

 col_default:
  return 0;



 col_slope_LU45:
  if ((gamemode == 0x06 || gamemode == 0x0A) && !currplayer_mini) {
   return 0;
  }
  else {
   tmp7 = (temp_x & 0x0f);
   tmp4 = (temp_y & 0x0f) ^ 0x0f;
  }
  currplayer_slope_type = (0b01 | 0b1000);
  goto col_end;

 col_slope_LD45:
  tmp7 = (temp_x & 0x0f);
  tmp4 = (temp_y & 0x0f);

  currplayer_slope_type = (0b01);
  goto col_end;

 col_slope_RU45:
  tmp7 = (temp_x & 0x0f) ^ 0x0f;
  tmp4 = (temp_y & 0x0f) ^ 0x0f;

  currplayer_slope_type = (0b01 | 0b0100 | 0b1000);
  goto col_end;

 col_slope_RD45:
  tmp7 = (temp_x & 0x0f) ^ 0x0f;
  tmp4 = temp_y & 0x0f;

  currplayer_slope_type = (0b01 | 0b0100);
  goto col_end;



 col_slope_RU22_RIGHT:
  tmp7 = ((temp_x >> 1) & 0x07) ^ 0x0f;
  tmp4 = (temp_y & 0x0f) ^ 0x0f;

  currplayer_slope_type = (0b10 | 0b0100 | 0b1000);
  goto col_end;

 col_slope_RU22_LEFT:
  tmp7 = (((temp_x >> 1) | 0x8) & 0x0f) ^ 0x0f;
  tmp4 = (temp_y & 0x0f) ^ 0x0f;

  currplayer_slope_type = (0b10 | 0b0100 | 0b1000);
  goto col_end;

 col_slope_RD22_RIGHT:
  tmp7 = ((temp_x >> 1) & 0x07) ^ 0x0f;
  tmp4 = (temp_y & 0x0f);

  currplayer_slope_type = (0b10 | 0b0100);
  goto col_end;

 col_slope_RD22_LEFT:
  tmp7 = (((temp_x >> 1) | 0x8) & 0x0f) ^ 0x0f;
  tmp4 = (temp_y & 0x0f);

  currplayer_slope_type = (0b10 | 0b0100);
  goto col_end;

 col_slope_LU22_RIGHT:
  tmp7 = ((temp_x >> 1) & 0x07);
  tmp4 = (temp_y & 0x0f) ^ 0x0f;

  currplayer_slope_type = (0b10 | 0b1000);
  goto col_end;

 col_slope_LU22_LEFT:
  tmp7 = (((temp_x >> 1) | 0x8) & 0x0f);
  tmp4 = (temp_y & 0x0f) ^ 0x0f;

  currplayer_slope_type = (0b10 | 0b1000);
  goto col_end;

 col_slope_LD22_RIGHT:
  tmp7 = ((temp_x >> 1) & 0x07);
  tmp4 = (temp_y & 0x0f);

  currplayer_slope_type = (0b10);
  goto col_end;

 col_slope_LD22_LEFT:
  tmp7 = (((temp_x >> 1) | 0x8) & 0x0f);
  tmp4 = (temp_y & 0x0f);

  currplayer_slope_type = (0b10);
  goto col_end;



 col_slope_RD66_TOP:
  if ((uint8_t)(temp_x & 0x0f) < 0x08) return 0;
  tmp7 = (((temp_x & 0x07) << 1) & 0x0f) ^ 0x0f;
  tmp4 = ((temp_y) & 0x0f);

  currplayer_slope_type = (0b11 | 0b0100);
  goto col_end;

 col_slope_RD66_BOT:
  if ((uint8_t)(temp_x & 0x0f) >= 0x08) return 1;
  tmp7 = (((temp_x & 0x0f) << 1) & 0x0f) ^ 0x0f;
  tmp4 = ((temp_y) & 0x0f);

  currplayer_slope_type = (0b11 | 0b0100);
  goto col_end;

 col_slope_LD66_TOP:
  if ((uint8_t)(temp_x & 0x0f) >= 0x08) return 0;
  tmp7 = (((temp_x & 0x07) << 1) & 0x0f);
  tmp4 = ((temp_y) & 0x0f);

  currplayer_slope_type = (0b11);
  goto col_end;

 col_slope_LD66_BOT:
  if ((uint8_t)(temp_x & 0x0f) < 0x08) return 1;
  tmp7 = (((temp_x & 0x0f) << 1) & 0x0f);
  tmp4 = ((temp_y) & 0x0f);

  currplayer_slope_type = (0b11);
  goto col_end;

 col_slope_RU66_TOP:
  if ((uint8_t)(temp_x & 0x0f) < 0x08) return 0;
  tmp7 = (((temp_x & 0x07) << 1) & 0x0f) ^ 0x0f;
  tmp4 = ((temp_y) & 0x0f) ^ 0x0f;

  currplayer_slope_type = (0b11 | 0b0100 | 0b1000);
  goto col_end;

 col_slope_RU66_BOT:
  if ((uint8_t)(temp_x & 0x0f) >= 0x08) return 1;
  tmp7 = (((temp_x & 0x0f) << 1) & 0x0f) ^ 0x0f;
  tmp4 = ((temp_y) & 0x0f) ^ 0x0f;

  currplayer_slope_type = (0b11 | 0b0100 | 0b1000);
  goto col_end;

 col_slope_LU66_TOP:
  if ((gamemode == 0x06 || gamemode == 0x0A) && currplayer_mini) {
   return 0;
  }

  if ((uint8_t)(temp_x & 0x0f) >= 0x08) return 0;
  tmp7 = (((temp_x & 0x07) << 1) & 0x0f);
  tmp4 = ((temp_y) & 0x0f) ^ 0x0f;

  currplayer_slope_type = (0b11 | 0b1000);
  goto col_end;

 col_slope_LU66_BOT:
  if ((gamemode == 0x06 || gamemode == 0x0A) && currplayer_mini) {
   return 0;
  }
  if ((uint8_t)(temp_x & 0x0f) < 0x08) return 1;
  tmp7 = (((temp_x & 0x0f) << 1) & 0x0f);
  tmp4 = ((temp_y) & 0x0f) ^ 0x0f;

  currplayer_slope_type = (0b11 | 0b1000);

 col_end:
 if ((uint8_t)(tmp4) >= tmp7) {
   tmp8 = tmp4 - tmp7;

   if (gamemode == 0x00 || gamemode == 0x04 || gamemode == 0x08) {
    if (controllingplayer->hold & (0x80 | 0x08)) {
     make_cube_jump_higher = 1;

    } else {
     currplayer_slope_frames = 1;
     currplayer_was_on_slope_counter = 3;
    }
   } else {
    tmp4 = 0;
    if (currplayer_slope_type & 0b0100) {
     tmp4 |= 0b100;
    }
    if (currplayer_slope_type & 0b1000) {
     tmp4 |= 0b010;
    }
    if (currplayer_gravity) {
     tmp4 |= 0b001;
    }

    if (a_check_lookup[tmp4]) {
     if (controllingplayer->hold & (0x80 | 0x08)) {
      tmp8 = 4;
     }
    } else {
     if (!(controllingplayer->hold & (0x80 | 0x08))) {
      tmp8 = 4;
     }
    }

    currplayer_slope_frames = 1;
    currplayer_was_on_slope_counter = 3;
   }

   return 1;
 } else if (!currplayer_was_on_slope_counter) {
   currplayer_slope_type = 0;
   tmp8 = 0;
 }

 return 0;
}







char bg_coll_return_D () {
 tmp1 = bg_coll_U_D_checks() || bg_coll_mini_blocks() || bg_coll_top_bottom_slabs();
 eject_D = tmp8;
 return tmp1;
}







char bg_coll_return_U () {
 tmp3 = bg_coll_U_D_checks();
 tmp1 = bg_coll_mini_blocks() || bg_coll_top_bottom_slabs();
 eject_U = (tmp3 ? 0xf0 : 0xf8) | tmp8;
 return tmp1 | tmp3;
}







char bg_coll_return_slope_D () {
 tmp1 = bg_coll_slope();

 if (!tmp2) {

  if (currplayer_slope_type & 0b0100) {
   currplayer_slope_type = currplayer_last_slope_type;
   return 0;
  }
 } else {

  if (!(currplayer_slope_type & 0b0100)) {
   currplayer_slope_type = currplayer_last_slope_type;
   return 0;
  }
 }
 if (tmp1) {
  if ((currplayer_last_slope_type & 0b0100) && !(currplayer_slope_type & 0b0100)) {
   if (currplayer_last_slope_type != 0 && currplayer_slope_type != 0) {
    currplayer_slope_type = currplayer_last_slope_type;
    tmp8 = (*((uint8_t *)&(currplayer_vel_x) + 1));
   }
  }
  if (currplayer_slope_type != 0) currplayer_last_slope_type = currplayer_slope_type;
  eject_D = tmp8;
 }
 return tmp1;
}







char bg_coll_return_slope_U () {
 tmp1 = bg_coll_slope();

 if (!tmp2) {

  if (currplayer_slope_type & 0b0100) {
   currplayer_slope_type = currplayer_last_slope_type;
   return 0;
  }
 } else {

  if (!(currplayer_slope_type & 0b0100)) {
   currplayer_slope_type = currplayer_last_slope_type;
   return 0;
  }
 }

 if (tmp1) {
  if ((currplayer_last_slope_type & 0b0100) && !(currplayer_slope_type & 0b0100)) {
   if (currplayer_last_slope_type != 0 && currplayer_slope_type != 0) {
    currplayer_slope_type = currplayer_last_slope_type;
    tmp8 = (*((uint8_t *)&(currplayer_vel_x) + 1));
   }
  }
  if (currplayer_slope_type != 0) currplayer_last_slope_type = currplayer_slope_type;
  eject_U = -tmp8;
 }
 return tmp1;
}
# 886 "C:/famidash/SAUCE\\functions/collision.h"
char bg_coll_U() {



 if ((*((uint8_t *)&(currplayer_x) + 1)) >= 0x10) {
  do { uint16_t sws_ = (uint16_t)(add_scroll_y( Generic.y + ((((0x10 - Generic.height) & 0xFF)) >> 1) + (currplayer_mini ? 1 : 2) + (gamemode == 0x01 ? 1 : 0), scroll_y )); (temp_y) = (uint8_t)sws_; (temp_room) = (uint8_t)(sws_ >> 8); } while (0);




  temp_x = Generic.x + (*((uint16_t *)&(scroll_x)));

  tmp2 = 0;
  (*((uint8_t *)&(tmp3))) = 0;
  do {
   bg_collision_sub();

   if (collision) {

    tmp3 = (((((bg_coll_return_slope_U()) & 0xFF)))) | tmp3;
   }

   temp_x += Generic.width;
  } while (++tmp2 < 2);
  if ((*((uint8_t *)&(tmp3)))) return 1;
 }

 if ((*((uint8_t *)&(currplayer_vel_y) + 1)) & 0x80) {
  temp_x = Generic.x + (*((uint16_t *)&(scroll_x))) + (gamemode == 0x06 || gamemode == 0x0A ? 4 : 0);

  do { uint16_t sws_ = (uint16_t)(add_scroll_y( Generic.y + ((currplayer_mini ? (((0x10 - Generic.height) & 0xFF)) >> 1 : 0) + (gamemode == 0x06 || gamemode == 0x0A ? 0 : 1)), scroll_y )); (temp_y) = (uint8_t)sws_; (temp_room) = (uint8_t)(sws_ >> 8); } while (0);





  tmp8 = (temp_y) & 0x0f;

  bg_collision_sub(); if (collision) { if (bg_coll_return_U()) { ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] & 0b1111110)); return 1; } }

  temp_x += Generic.width >> 1;

  bg_collision_sub(); if (collision) { if (bg_coll_return_U()) { ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] & 0b1111110)); return 1; } }

  temp_x = Generic.x + (*((uint16_t *)&(scroll_x))) + (Generic.width);

  bg_collision_sub(); if (collision) { if (bg_coll_return_U()) { ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] & 0b1111110)); return 1; } }
 }
 return 0;

}







char bg_coll_D() {


 if ((*((uint8_t *)&(currplayer_x) + 1)) >= 0x10) {
  do { uint16_t sws_ = (uint16_t)(add_scroll_y( Generic.y + Generic.height - 2 + (currplayer_mini ? (((0x10 - Generic.height) & 0xFF)) >> 1 : 0), scroll_y )); (temp_y) = (uint8_t)sws_; (temp_room) = (uint8_t)(sws_ >> 8); } while (0);



  temp_x = Generic.x + (*((uint16_t *)&(scroll_x)));

  tmp2 = 0;
  (*((uint8_t *)&(tmp3))) = 0;
  do {
   bg_collision_sub();

   if (collision) {

    tmp3 = (((((bg_coll_return_slope_D()) & 0xFF)))) | tmp3;
   }
   temp_x += Generic.width;
  } while (++tmp2 < 2);
  if ((*((uint8_t *)&(tmp3)))) return 1;
 }

 if (!((*((uint8_t *)&(currplayer_vel_y) + 1)) & 0x80)) {

  temp_x = Generic.x + (*((uint16_t *)&(scroll_x))) + (gamemode == 0x06 || gamemode == 0x0A ? 4 : 0);

  do { uint16_t sws_ = (uint16_t)(add_scroll_y( Generic.y + Generic.height + (currplayer_mini ? (((0x10 - Generic.height) & 0xFF)) >> 1 : 0), scroll_y )); (temp_y) = (uint8_t)sws_; (temp_room) = (uint8_t)(sws_ >> 8); } while (0);





  tmp8 = (temp_y) & 0x0f;

  bg_collision_sub(); if (collision) { if (bg_coll_return_D()) { ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] & 0b1111110)); return 1; } }

  temp_x += Generic.width >> 1;

  bg_collision_sub(); if (collision) { if (bg_coll_return_D()) { ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] & 0b1111110)); return 1; } }

  temp_x = Generic.x + (*((uint16_t *)&(scroll_x))) + (Generic.width);

  bg_collision_sub(); if (collision) { if (bg_coll_return_D()) { ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] & 0b1111110)); return 1; } }
 }

 return 0;
}




char bg_coll_U_spider() {
 temp_x = tmp7;
 do { uint16_t sws_ = (uint16_t)(add_scroll_y( Generic.y + (currplayer_mini ? (((0x10 - Generic.height) & 0xFF)) >> 1 : 0), scroll_y )); (temp_y) = (uint8_t)sws_; (temp_room) = (uint8_t)(sws_ >> 8); } while (0);





 tmp8 = (temp_y) & 0x0f;

 bg_collision_sub(); if (collision) { if (bg_coll_return_U()) { ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] & 0b1111110)); return 1; } }

 temp_x = tmp9;

 bg_collision_sub(); if (collision) { if (bg_coll_return_U()) { ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] & 0b1111110)); return 1; } }

 return 0;
}

char bg_coll_D_spider() {
 temp_x = tmp7;
 do { uint16_t sws_ = (uint16_t)(add_scroll_y( Generic.y + Generic.height + (currplayer_mini ? (((0x10 - Generic.height) & 0xFF)) >> 1 : 0), scroll_y )); (temp_y) = (uint8_t)sws_; (temp_room) = (uint8_t)(sws_ >> 8); } while (0);





 tmp8 = (temp_y) & 0x0f;

 bg_collision_sub(); if (collision) { if (bg_coll_return_D()) { ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] & 0b1111110)); return 1; } }

 temp_x = tmp9;

 bg_collision_sub(); if (collision) { if (bg_coll_return_D()) { ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] & 0b1111110)); return 1; } }

 return 0;
}
# 1042 "C:/famidash/SAUCE\\functions/collision.h"
void bg_coll_death() {




 temp_x = Generic.x + (*((uint16_t *)&(scroll_x))) + (Generic.width >> 1)-1;

 do { uint16_t sws_ = (uint16_t)(add_scroll_y( Generic.y + (Generic.height >> 1) + (currplayer_mini ? (((0x10 - Generic.height) & 0xFF)) >> 1 : 0), scroll_y )); (temp_y) = (uint8_t)sws_; (temp_room) = (uint8_t)(sws_ >> 8); } while (0);





 bg_collision_sub();

 if (collision) {
  if (!dblocked[currplayer] || gamemode != 0x06) {
   if (!force_platformer) {
    if (bg_coll_U_D_checks() || bg_coll_mini_blocks() || bg_coll_top_bottom_slabs() || bg_coll_spikes() || bg_coll_slope()) {
     ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] | 1));
    }
   }
   else {
    if (bg_coll_U_D_checks() || bg_coll_mini_blocks() || bg_coll_spikes() || bg_coll_slope()) {
     ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] | 1));
    }
   }
  }
  else {
   if (bg_coll_mini_blocks() || bg_coll_top_bottom_slabs() || bg_coll_spikes() || bg_coll_slope()) {
    ((cube_data)[(uint8_t)(currplayer)] = (uint8_t)(cube_data[currplayer] | 1));
   }
  }
 }




}

void commonly_used_store() {
  do { uint16_t sws_ = (uint16_t)(add_scroll_y( Generic.y + (currplayer_mini ? ((((0x10 - Generic.height) & 0xFF)) >> 1) : 0) + Generic.height - 2, scroll_y )); (temp_y) = (uint8_t)sws_; (temp_room) = (uint8_t)(sws_ >> 8); } while (0);



}
void commonly_stored_routine_2() {
 do { uint16_t sws_ = (uint16_t)(add_scroll_y( Generic.y + (currplayer_mini ? ((((0x10 - Generic.height) & 0xFF)) >> 1) : 2), scroll_y )); (temp_y) = (uint8_t)sws_; (temp_room) = (uint8_t)(sws_ >> 8); } while (0);




}

void commonly_used_death_check() {
 do { if ((uint8_t)((uint8_t)(temp_x & 0x0f)) >= (0x04) && (uint8_t)((uint8_t)(temp_x & 0x0f)) <= (0x08)) { cube_data[currplayer] = 1; } } while (0);


}
# 18 "probe/tu_collision.c" 2

