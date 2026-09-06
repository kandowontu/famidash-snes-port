#pragma data-name(push, "XCD_BANK_00")
#pragma rodata-name(push, "XCD_BANK_00")
#pragma code-name(push, "XCD_BANK_00")

extern void load_next_sprite(uint8_t slot);
extern void check_spr_objects();
void init_sprites();

void dual_cap_check();
void spider_up_wait();
void spider_down_wait();
extern char bg_coll_U();
extern char bg_coll_D();
void 	clearrobotjumpframes();
void settrailstuff();

const unsigned char OUTLINES[]={
		0x30,
		0x11,
		0x12,
		0x13,
		0x14,
		0x15,
		0x16,
		0x27,
		0x28,
		0x29,
		0x2A,
		0x2B,
		0x2C,
		0x21,
		0x17,
		0x0F
};

#define PORTAL_TO_TOP_DIFF 0x3A

#define OUTL    0xFC
#define COLR    0xFD
#define DECO    0xFE
#ifdef FLAG_KANDO_FUN_STUFF
#define	KNDO	0xFF
#else
#define KNDO	0x00
#endif
#define SPBH    0xFF

uint8_t sprite_heights[]={
	0x34,	0x34,	0x34,	0x34,	0x34,	0x12,	0x12,	SPBH,	// 00 - 07
	0x28,	0x28,	0x03,	0x12,	0x03,	0x03,	0x03,	SPBH,	// 08 - 0F
	0x0e,	0x0e,	0x0e,	0x0e,	0x24,	0x24,	0x24,	0x34,	// 10 - 17
	0x34,	0x34,	SPBH,	SPBH,	SPBH,	SPBH,	SPBH,	0x12,	// 18 - 1F
	0x24,	0x24,	0x34,	0x34,	0x34,	0x03,	0x03,	0x12,	// 20 - 27
	0x12,	0x12,	DECO,	DECO,	DECO,	DECO,	DECO,	DECO,	// 28 - 2F
	DECO,	DECO,	DECO,	DECO,	DECO,	DECO,	DECO,	DECO,	// 30 - 37
	DECO,	DECO,	DECO,	DECO,	DECO,	DECO,	DECO,	DECO,	// 38 - 3F
	DECO,	DECO,	DECO,	DECO,	0x12,	0x12,	0x12,	0x28,	// 40 - 47
	0x28,	DECO,	DECO,	0x34,	0x12,	0x12,	0x30,	SPBH,	// 48 - 4F
	0x12,	0x12,	0x03,	0x03,	0x12,	0x12,	0x03,	0x03,	// 50 - 57
	0x34,	0x10,	SPBH,	0x12,	0x12,	0x12,	0x12,	0x34,	// 58 - 5F
	0x34,	0x34,	0x34,	0x34,	0x34,	0x02,	0x10,	SPBH,	// 60 - 67
	0x10,	SPBH,	0x34,	0x34,	0x34,	0x20,	0x08,	SPBH,	// 68 - 6F
	SPBH,	SPBH,	SPBH,	SPBH,	SPBH,	0x10,	SPBH,	0x10,	// 70 - 77
	SPBH,	0x12,	0x12,	0x12,	0x12,	SPBH,	SPBH,	SPBH,	// 78 - 7F
	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	// 80 - 87
	COLR,	COLR,	COLR,	COLR,	COLR,	0x00,	SPBH,	COLR,	// 88 - 8F
	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	// 90 - 97
	COLR,	COLR,	COLR,	COLR,	COLR,	0x00,	SPBH,	COLR,	// 98 - 9F
	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	// A0 - A7
	COLR,	COLR,	COLR,	COLR,	COLR,	0x00,	COLR,	OUTL,	// A8 - AF
	OUTL,	OUTL,	OUTL,	OUTL,	OUTL,	OUTL,	OUTL,	OUTL,	// B0 - B7
	OUTL,	OUTL,	OUTL,	OUTL,	OUTL,	OUTL,	OUTL,	OUTL,	// B8 - BF
	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	// C0 - C7
	COLR,	COLR,	COLR,	COLR,	COLR,	0x00,	0x00,	COLR,	// C8 - CF
	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	// D0 - D7
	COLR,	COLR,	COLR,	COLR,	COLR,	SPBH,	SPBH,	KNDO,	// D8 - DF
	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	COLR,	// E0 - E7
	COLR,	COLR,	COLR,	COLR,	COLR,	SPBH,	KNDO,	KNDO,	// E8 - EF
	SPBH,	SPBH,	SPBH,	SPBH,	SPBH,	SPBH,	0x10,	0x10,	// F0 - F7
	0x10,	0x10,	0x1F,	0x10,	0x10,	0x03,	0x03,	0x00,	// F8 - FF
};

uint8_t sprite_widths[]={
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// 00 - 07
	0x0e,	0x0e,	0x0F,	0x10,	0x0F,	0x0F,	0x0F,	0x10,	// 08 - 0F
	0x28,	0x28,	0x28,	0x28,	0x10,	0x10,	0x10,	0x10,	// 10 - 17
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// 18 - 1F
	0x10,	0x10,	0x10,	0x10,	0x10,	0x0F,	0x0F,	0x10,	// 20 - 27
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// 28 - 2F
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// 30 - 37
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// 38 - 3F
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x0e,	// 40 - 47
	0x0e,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// 48 - 4F
	0x10,	0x10,	0x0F,	0x0F,	0x10,	0x10,	0x0F,	0x0F,	// 50 - 57
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// 58 - 5F
	0x10,	0x10,	0x10,	0x10,	0x10,	0x0E,	0x30,	0x30,	// 60 - 67
	0x30,	0x30,	0x10,	0x10,	0x10,	0x10,	0x08,	0x10,	// 68 - 6F
	0x10,	0x10,	0x10,	0x10,	0x10,	0x30,	0x30,	0x30,	// 70 - 77
	0x30,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// 78 - 7F
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// 80 - 87
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// 88 - 8F
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// 90 - 97
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// 98 - 9F
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// A0 - A7
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// A8 - AF
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// B0 - B7
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// B8 - BF
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// C0 - C7
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// C8 - CF
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// D0 - D7
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// D8 - DF
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// E0 - E7
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// E8 - EF
	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	0x10,	// F0 - F7
	0x10,	0x08,	0x1B,	0x10,	0x10,	0x0E,	0x0E,	0x10,	// F8 - FF
};

// Offset goes for x to the rigth and for y down, for moving it in the other direction, put a negative value (0x80-0xff) 

int8_t sprite_x_offset[]={
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 00 - 07
	0x01,	0x01,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 08 - 0F
	0x04,	0x04,	0x04,	0x04,	0x00,	0x00,	0x00,	0x00,	// 10 - 17
	0x08,	0x08,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 18 - 1F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 20 - 27
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 28 - 2F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 30 - 37
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 38 - 3F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x01,	// 40 - 47
	0x01,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 48 - 4F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 50 - 57
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 58 - 5F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 60 - 67
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x04,	0x00,	// 68 - 6F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 70 - 77
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 78 - 7F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 80 - 87
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 88 - 8F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 90 - 97
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 98 - 9F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// A0 - A7
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// A8 - AF
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// B0 - B7
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// B8 - BF
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// C0 - C7
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// C8 - CF
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// D0 - D7
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// D8 - DF
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// E0 - E7
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// E8 - EF
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// F0 - F7
	0x00,	0x08,	-0x07,	0x00,	0x00,	0x00,	0x00,	0x00,	// F8 - FF
};

int8_t sprite_y_offset[]={
	-0x02,	-0x02,	-0x02,	-0x02,	-0x02,	-0x01,	-0x01,	0x00,	// 00 - 07
	0x04,	0x04,	0x05,	-0x01,	0x00,	0x05,	0x00,	0x00,	// 08 - 0F
	0x01,	0x01,	0x01,	0x01,	-0x02,	-0x02,	-0x02,	-0x02,	// 10 - 17
	-0x02,	-0x02,	0x00,	0x00,	0x00,	0x00,	0x00,	-0x01,	// 18 - 1F
	-0x02,	-0x02,	-0x02,	-0x02,	-0x02,	0x05,	0x00,	-0x01,	// 20 - 27
	-0x01,	-0x01,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 28 - 2F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 30 - 37
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 38 - 3F
	0x00,	0x00,	0x00,	0x00,	-0x01,	-0x01,	-0x01,	0x04,	// 40 - 47
	0x04,	0x00,	0x00,	-0x02,	0x00,	-0x01,	-0x01,	0x00,	// 48 - 4F
	-0x01,	-0x01,	0x05,	0x00,	-0x01,	-0x01,	0x05,	0x00,	// 50 - 57
	-0x02,	0x00,	0x00,	-0x01,	-0x01,	-0x01,	-0x01,	-0x02,	// 58 - 5F
	-0x02,	-0x02,	-0x02,	-0x02,	-0x02,	0x00,	0x00,	0x00,	// 60 - 67
	0x00,	0x00,	-0x02,	-0x02,	-0x02,	0x00,	0x04,	0x00,	// 68 - 6F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 70 - 77
	0x00,	-0x01,	-0x01,	-0x01,	-0x01,	0x00,	0x00,	0x00,	// 78 - 7F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 80 - 87
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 88 - 8F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 90 - 97
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// 98 - 9F
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// A0 - A7
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// A8 - AF
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// B0 - B7
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// B8 - BF
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// C0 - C7
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// C8 - CF
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// D0 - D7
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// D8 - DF
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// E0 - E7
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// E8 - EF
	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	// F0 - F7
	0x00,	0x00,	-0x07,	0x00,	0x00,	0x05,	0x02,	0x00,	// F8 - FF
};

void animate_coin_1();

void animate_coin_2();

void animate_coin_3();

void clear_slope_stuff() {
	currplayer_was_on_slope_counter = 0;
	currplayer_slope_frames = 0;
	currplayer_slope_type = 0;
	currplayer_last_slope_type = 0;
}



char sprite_load_special_behavior(){

	#define killSprite_return0 activesprites_type[index] = 0xFF; return 0

	#define type tmp4

	switch(type) {
		#ifdef FLAG_KANDO_FUN_STUFF	
			case DEATH_CHANCE:
				// if ((newrand() & 63) == (newrand() & 63)), paraphrased
				// attempts to use less tmp variables result in c stack operations
				cc65_tmp1 = newrand();
				cc65_tmp2 = newrand();
				cc65_tmp2 = (cc65_tmp2 ^ cc65_tmp1) & 63;
				if (cc65_tmp2 == 0) {
					idx8_store(cube_data, currplayer, cube_data[currplayer] | 1);
				}
				triggers_hit[0]++;
				if (triggers_hit[0] == 10) { triggers_hit[0] = 0; triggers_hit[1]++; }
				if (triggers_hit[1] == 10) { triggers_hit[1] = 0; triggers_hit[2]++; }
				triggers++;
				killSprite_return0;
			case MASK_SPRITES_ON:
				disco_sprites = 1;
				killSprite_return0;
			case MASK_SPRITES_OFF:
				disco_sprites = 0;
				killSprite_return0;
			case PLAYER_INVIS_ON:
				player_invis = 1;
				killSprite_return0;
			case PLAYER_INVIS_OFF:
				player_invis = 0;
				killSprite_return0;
			case WRAP_MODE_ON:
				wrap_mode = 1;
				killSprite_return0;
			case WRAP_MODE_OFF:
				wrap_mode = 0;
				killSprite_return0;
			case GRAVITY_13_PORTAL_INVIS:
				gravity_mod = 1;
				killSprite_return0;
			case GRAVITY_12_PORTAL_INVIS:
				gravity_mod = 2;
				killSprite_return0;
			case GRAVITY_23_PORTAL_INVIS:
				gravity_mod = 3;
				killSprite_return0;
			case GRAVITY_2X_PORTAL_INVIS:
				gravity_mod = 4;
				killSprite_return0;
			case GRAVITY_1X_PORTAL_INVIS:
				gravity_mod = 0;
				killSprite_return0;
			case NULLSCAPES_ORB:
				nullscapes_active++;
				if (nullscapes_active == 3) nullscapes_active = 0;
				killSprite_return0;
		#endif
		case FORCED_FREECAM_ON:
			nocamlockforced = 1;
			killSprite_return0;
		case FORCED_FREECAM_OFF:
			nocamlockforced = 0;
			killSprite_return0;
		case X_SCROLL_SETTING:
			if (!cam_seesaw) {
				target_x_scroll_stop = (activesprites_realy[index] & 0xF0) << 8;
				killSprite_return0;
			}
			return 0;

		case SLOWMODE_ON:
			if (!level_resetting_flag) slowmode = 1;
			else if (level_resetting_flag && !timewarp_done) { slowmode = 1; timewarp_done = 1; }
			killSprite_return0;
		case SLOWMODE_OFF:
			if (!level_resetting_flag) slowmode = 0;
			else if (level_resetting_flag && !timewarp_done) { slowmode = 0; timewarp_done = 1; }
			killSprite_return0;

		case FORCED_TRAILS_ON:
			forced_trails = 1;
			killSprite_return0;
		case FORCED_TRAILS_OFF:
		case PLAYER_TRAILS_OFF:
			forced_trails = 0;
			killSprite_return0;
		case PLAYER_TRAILS_ON:
			forced_trails = 2;
			killSprite_return0;

		case TELEPORT_SQUARE_EXIT:
			teleport_output = activesprites_realy[index];
			return 0x0f;

		case INVIS_TELEPORT_PORTAL_DOWNWARDS_EXIT:
		case INVIS_TELEPORT_PORTAL_UPWARDS_EXIT:	
		case TELEPORT_PORTAL_DOWNWARDS_EXIT:
		case TELEPORT_PORTAL_UPWARDS_EXIT:		
			teleport_output = activesprites_realy[index] + 0x10;
			return 0x10;

		case TELEPORT_PORTAL_EXIT:
			teleport_output = activesprites_realy[index] + 0x10;
			return 0x30;

		case COIN1:
			if (!invisblocks) {
				if (coin1_obtained[level]) {
					activesprites_type[index] = COINGOTTEN1;
				}
			}
			else {
				if (invisible_coin1_obtained[level]) {
					activesprites_type[index] = COINGOTTEN1;
				}
			}
		case COINGOTTEN1:
			if (coin1_timer) {
				animate_coin_1();
			}      
			return 0x10;

		case COIN2:
			if (!invisblocks) {
				if (coin2_obtained[level]) {
					activesprites_type[index] = COINGOTTEN2;
				}
			}
			else {
				if (invisible_coin2_obtained[level]) {
					activesprites_type[index] = COINGOTTEN2;
				}
			}
		case COINGOTTEN2:
			if (coin2_timer) {
				animate_coin_2();
			}
			return 0x10;

		case COIN3:
			if (!invisblocks) {
				if (coin3_obtained[level]) {
					activesprites_type[index] = COINGOTTEN3;
				}
			}
			else {
				if (invisible_coin3_obtained[level]) {
					activesprites_type[index] = COINGOTTEN3;
				}
			}
		case COINGOTTEN3:
			#ifdef level_fingerdash
				if (level == level_fingerdash && minicoins != 10) {
					activesprites_type[index] = 0xFF;
					return 0x10;
				}
			#endif
			if (coin3_timer) {
				animate_coin_3();
			}
			return 0x10; 

		case LEVEL_END_TRIGGER:
			gameState = STATE_LVLDONE; kandokidshack4 = 0;
			
	}
	return 0;

	#undef type

//	#undef killSprite_return0
}

void animate_coin_1() {    
    idx8_store(activesprites_y_lo, index, activesprites_y_lo[index] - high_byte(coin1_speed));
    coin1_speed -= 0x0040;
    coin1_timer++;

    if (coin1_timer == 40) {
        activesprites_type[index] = 0xFF;
        animating = 0;
    }	 
}


void animate_coin_2() {
    idx8_store(activesprites_y_lo, index, activesprites_y_lo[index] - high_byte(coin2_speed));
    coin2_speed -= 0x0040;
    coin2_timer++;

    if (coin2_timer == 40) {
        activesprites_type[index] = 0xFF;
        animating = 0;
    }	 
}


void animate_coin_3() {
    idx8_store(activesprites_y_lo, index, activesprites_y_lo[index] - high_byte(coin3_speed));
    coin3_speed -= 0x0040;
    coin3_timer++;

    if (coin3_timer == 40) {
        activesprites_type[index] = 0xFF;
        animating = 0;
    }	 
}

void common_dash_orb_routine() {
//	if (gamemode == GAMEMODE_UFO) {
//		if (currplayer_vel_y != 0) invert_gravity(currplayer_gravity);		;why was this here??
//	}
//	else 
	invert_gravity(currplayer_gravity);
	update_currplayer_table_idx();
}

#define yellow_orb  0x00 << 3
#define yellow_pad  0x01 << 3
#define pink_orb    0x02 << 3
#define pink_pad    0x03 << 3
#define red_orb     0x04 << 3
#define ylw_bigger  0x05 << 3
#define black_orb   0x06 << 3
#define ylw_smaller 0x07 << 3
#define red_pad     0x08 << 3

#define table_offset tmp3
#define collided tmp4

#pragma data-name(push, "XCD_BANK_06")
#pragma rodata-name(push, "XCD_BANK_06")
#pragma code-name(push, "XCD_BANK_06")

// Load the player velocity from the height table
static uint16_t _sprite_gamemode_y_adjust() {
	return ind16BE_load_NOC(sprite_gamemode_adjust_heights(currplayer_table_idx), ((retro_mode && gamemode == GAMEMODE_ROBOT) || gamemode == GAMEMODE_NINJA) ? table_offset : gamemode | table_offset);
}

#pragma code-name(pop)
#pragma rodata-name(pop)
#pragma data-name(pop)

static uint16_t sprite_gamemode_y_adjust() {	// A trampoline of sorts
	if (gamemode == GAMEMODE_POGO) {
		gamemode = GAMEMODE_SWING;
		tmpA = crossPRGBankJump0(_sprite_gamemode_y_adjust);
		gamemode = GAMEMODE_POGO;
		return tmpA;
	}
	if (gamemode == GAMEMODE_SNAKE) {
		gamemode = GAMEMODE_WAVE;
		tmpA = crossPRGBankJump0(_sprite_gamemode_y_adjust);
		gamemode = GAMEMODE_SNAKE;
		return tmpA;
	}
	if (gamemode == GAMEMODE_FOOTBALL) {
		gamemode = GAMEMODE_CUBE;
		tmpA = crossPRGBankJump0(_sprite_gamemode_y_adjust);
		gamemode = GAMEMODE_FOOTBALL;
		return tmpA;
	}
	return crossPRGBankJump0(_sprite_gamemode_y_adjust);
}

void gamemode_stuff() {
		clearrobotjumpframes();		
		if (!dual || twoplayer) target_scroll_y = (lohi_arr16_load(activesprites_y, index) - PORTAL_TO_TOP_DIFF);		
}		

void pad_stuff() {
		clear_slope_stuff();
		settrailstuff();
		currplayer_vel_y = sprite_gamemode_y_adjust();
		orbhitonthisframe[currplayer] = 1;
}	

static void sprite_gamemode_main() {
	if (controllingplayer->hold & (PAD_A | PAD_UP)) {
		if (gamemode == BALL_MODE) ball_switched[currplayer] = 1;
		if ((cube_data[currplayer] & 2) || controllingplayer->press & (PAD_A | PAD_UP)) {
			if (gamemode == GAMEMODE_SPIDER && collided == BLACK_ORB) black_orbed[currplayer] = 1;
			if (gamemode == ROBOT_MODE) orbed[currplayer] = 1;
			idx8_store(cube_data, currplayer, cube_data[currplayer] & 1);
			settrailstuff();
			clear_slope_stuff();

			switch (collided) {
			case BLUE_ORB_MULTI:
			case BLUE_ORB:
				if (!activesprites_activated[index]) {
					invert_gravity(currplayer_gravity); invert_gravity(player_gravity[0]); invert_gravity(player_gravity[1]);
					update_currplayer_table_idx();
					dual_cap_check();
					if (gamemode != BALL_MODE) {
						currplayer_vel_y = PAD_HEIGHT_BLUE(currplayer_table_idx);
					} else {
						currplayer_vel_y = ORB_BALL_HEIGHT_BLUE(currplayer_table_idx);
					}
				}
				break;
			case GREEN_ORB_MULTI:
			case GREEN_ORB:
				if (!activesprites_activated[index]) {
					invert_gravity(currplayer_gravity); invert_gravity(player_gravity[0]); invert_gravity(player_gravity[1]);
					update_currplayer_table_idx();
					dual_cap_check();
					currplayer_vel_y = sprite_gamemode_y_adjust();
				}
				break;
			case DASH_GRAVITY_ORB:
				if (!dashing[currplayer]) { 
					common_dash_orb_routine();
				}
				//intentional leak
			case DASH_ORB:
				currplayer_vel_y = 0;
				dashing[currplayer] = 1;
				break;
			case DASH_GRAVITY_ORB_45DEG_UP:
				if (!dashing[currplayer]) {
					common_dash_orb_routine();
				}				
				//intentional leak
			case DASH_ORB_45DEG_UP:
				currplayer_vel_y = -currplayer_vel_x;
				dashing[currplayer] = 2;
				break;
			case DASH_GRAVITY_ORB_45DEG_DOWN:
				if (!dashing[currplayer]) {
					common_dash_orb_routine();
				}				
				//intentional leak
			case DASH_ORB_45DEG_DOWN:
				currplayer_vel_y = currplayer_vel_x;
				dashing[currplayer] = 3;
				break;
			case DASH_GRAVITY_ORB_UPWARDS:
				if (!dashing[currplayer]) {
					common_dash_orb_routine();
				}			
				//intentional leak
			case DASH_ORB_UPWARDS:
				currplayer_vel_y = currplayer_vel_x * 4;
				//currplayer_vel_x = 0;
				dashing[currplayer] = 4;
				break;
			case DASH_GRAVITY_ORB_DOWNWARDS:
				if (!dashing[currplayer]) {
					common_dash_orb_routine();
				}			
				//intentional leak
			case DASH_ORB_DOWNWARDS:
				currplayer_vel_y = -currplayer_vel_x * 4;
				//currplayer_vel_x = 0;
				dashing[currplayer] = 5;
				break;
			default:
				currplayer_vel_y = sprite_gamemode_y_adjust();
				//break;
			};
	if (
		activesprites_type[index] != BLUE_ORB_MULTI &&
		activesprites_type[index] != GREEN_ORB_MULTI
	) 
		idx8_inc(activesprites_activated, index);		
		orbhitonthisframe[currplayer] = 1;
		}
	}
}

static void sprite_gamemode_controller_check() {
	if (controllingplayer->press & (PAD_A | PAD_UP)) {	
		idx8_store(cube_data, currplayer, cube_data[currplayer] & 0x01);
		settrailstuff();
		switch (collided) {
		case BLUE_ORB_MULTI:
		case BLUE_ORB:
			if (!activesprites_activated[index]) {
				invert_gravity(currplayer_gravity); invert_gravity(player_gravity[0]); invert_gravity(player_gravity[1]);
				update_currplayer_table_idx();
				dual_cap_check();
				// INTENTIONALLY do this after changing gravity
				if (gamemode != BALL_MODE) {
					currplayer_vel_y = PAD_HEIGHT_BLUE(currplayer_table_idx);
				} else {
					currplayer_vel_y = ORB_BALL_HEIGHT_BLUE(currplayer_table_idx);
				}
			}
			break;
		case GREEN_ORB_MULTI:
		case GREEN_ORB:
			if (!activesprites_activated[index]) {
			invert_gravity(currplayer_gravity); invert_gravity(player_gravity[0]); invert_gravity(player_gravity[1]);
			update_currplayer_table_idx();
			dual_cap_check();
		//	if (currplayer_gravity && currplayer_vel_y < 0x670) currplayer_vel_y = 0x670;
		//	else if (!currplayer_gravity && currplayer_vel_y > -0x670) currplayer_vel_y = -0x670;
			currplayer_vel_y = sprite_gamemode_y_adjust();	
			}			
			break;
		case DASH_GRAVITY_ORB:
			if (!dashing[currplayer]) {
				common_dash_orb_routine();
			}
			//intentional leak
		case DASH_ORB:
			currplayer_vel_y = 0;
			dashing[currplayer] = 1;
			break;
		case DASH_GRAVITY_ORB_45DEG_UP:
			if (!dashing[currplayer]) {
				common_dash_orb_routine();
			}
			//intentional leak
		case DASH_ORB_45DEG_UP:
			currplayer_vel_y = -currplayer_vel_x;
			dashing[currplayer] = 2;
			break;	
		case DASH_GRAVITY_ORB_45DEG_DOWN:
			if (!dashing[currplayer]) {
				common_dash_orb_routine();
			}
			//intentional leak
		case DASH_ORB_45DEG_DOWN:
			currplayer_vel_y = currplayer_vel_x;
			dashing[currplayer] = 3;
			break;		
		case DASH_GRAVITY_ORB_UPWARDS:
			if (!dashing[currplayer]) {
				common_dash_orb_routine();
			}
			//intentional leak
		case DASH_ORB_UPWARDS:
			currplayer_vel_y = currplayer_vel_x;
			currplayer_vel_x = 0;
			dashing[currplayer] = 4;
			break;	
		case DASH_GRAVITY_ORB_DOWNWARDS:
			if (!dashing[currplayer]) {
				common_dash_orb_routine();
			}
			//intentional leak
		case DASH_ORB_DOWNWARDS:
			currplayer_vel_y = -currplayer_vel_x;
			currplayer_vel_x = 0;
			dashing[currplayer] = 5;
			break;
		default:
			currplayer_vel_y = sprite_gamemode_y_adjust();
			//break;
		};
	if (
		activesprites_type[index] != BLUE_ORB_MULTI &&
		activesprites_type[index] != GREEN_ORB_MULTI
	) 
		idx8_inc(activesprites_activated, index);
	}
}



void sprite_collide_lookup() {

	if (activesprites_activated[index] && !dual && !(options & platformer) && !force_platformer)
		return;
	
	// SNES port: this was a computed goto through two tables of label
	// addresses; Calypsi's 65816 backend does not support `goto *expr`
	// (docs/HANDOFF.md trap 11). It is a switch now, but every spcl_* label is
	// kept so the `goto spcl_*` jumps between arms still resolve and the
	// fallthrough between adjacent arms is unchanged. Case labels were
	// generated from the original tables by tools/port_collide_lookup.py.
	switch (collided) {

	default:
	case 0x0F: case 0x2A: case 0x2B: case 0x2C: case 0x2D: case 0x2E: case 0x2F: case 0x30:
	case 0x31: case 0x32: case 0x33: case 0x34: case 0x35: case 0x36: case 0x37: case 0x38:
	case 0x39: case 0x3A: case 0x3B: case 0x3C: case 0x3D: case 0x3E: case 0x3F: case 0x40:
	case 0x41: case 0x42: case 0x43: case 0x49: case 0x4A: case 0x4F: case 0x5A: case 0x67:
	case 0x69: case 0x6F: case 0x70: case 0x71: case 0x72: case 0x73: case 0x74: case 0x76:
	case 0x78: case 0x7E: case 0x80: case 0x81: case 0x82: case 0x83: case 0x84: case 0x85:
	case 0x86: case 0x87: case 0x88: case 0x89: case 0x8A: case 0x8B: case 0x8C: case 0x8D:
	case 0x8E: case 0x8F: case 0x90: case 0x91: case 0x92: case 0x93: case 0x94: case 0x95:
	case 0x96: case 0x97: case 0x98: case 0x99: case 0x9A: case 0x9B: case 0x9C: case 0x9D:
	case 0x9E: case 0x9F: case 0xA0: case 0xA1: case 0xA2: case 0xA3: case 0xA4: case 0xA5:
	case 0xA6: case 0xA7: case 0xA8: case 0xA9: case 0xAA: case 0xAB: case 0xAC: case 0xAD:
	case 0xAE: case 0xAF: case 0xB0: case 0xB1: case 0xB2: case 0xB3: case 0xB4: case 0xB5:
	case 0xB6: case 0xB7: case 0xB8: case 0xB9: case 0xBA: case 0xBB: case 0xBC: case 0xBD:
	case 0xBE: case 0xBF: case 0xC0: case 0xC1: case 0xC2: case 0xC3: case 0xC4: case 0xC5:
	case 0xC6: case 0xC7: case 0xC8: case 0xC9: case 0xCA: case 0xCB: case 0xCC: case 0xCD:
	case 0xCE: case 0xCF: case 0xD0: case 0xD1: case 0xD2: case 0xD3: case 0xD4: case 0xD5:
	case 0xD6: case 0xD7: case 0xD8: case 0xD9: case 0xDA: case 0xDB: case 0xDC: case 0xDD:
	case 0xDE: case 0xDF: case 0xE0: case 0xE1: case 0xE2: case 0xE3: case 0xE4: case 0xE5:
	case 0xE6: case 0xE7: case 0xE8: case 0xE9: case 0xEA: case 0xEB: case 0xEC: case 0xEE:
	case 0xEF: case 0xF0: case 0xF1: case 0xF2: case 0xF3: case 0xF4: case 0xF5:
	spcl_default:
		return;

	// Gamemode portals
	
	case 0x79:
	spcl_skl_orb:
		activesprites_animated[index] = 1;
		if ((gamemode == GAMEMODE_CUBE || gamemode == GAMEMODE_POGO ||gamemode == GAMEMODE_BALL || gamemode == GAMEMODE_ROBOT || gamemode == GAMEMODE_NINJA || gamemode == GAMEMODE_SPIDER || gamemode >= GAMEMODE_SWING) && cube_data[currplayer] & 0x02) {
			if (controllingplayer->hold & (PAD_A | PAD_UP)) {
				idx8_store(cube_data,currplayer,cube_data[currplayer] | 0x01);
				activesprites_animated[index] = 0;
			}
		} else {
			if (controllingplayer->press & (PAD_A | PAD_UP)) {	
				idx8_store(cube_data,currplayer,cube_data[currplayer] | 0x01);
				activesprites_animated[index] = 0;
			}
		}
		return;
	
	case 0x7A:
	spcl_wht_orb:
		if ((gamemode == GAMEMODE_CUBE || gamemode == GAMEMODE_POGO || gamemode == GAMEMODE_BALL || gamemode == GAMEMODE_ROBOT || gamemode == GAMEMODE_NINJA || gamemode == GAMEMODE_SPIDER || gamemode >= GAMEMODE_SWING) && cube_data[currplayer] & 0x02) {
			if (controllingplayer->hold & (PAD_A | PAD_UP)) {
				currplayer_vel_y = 0;
				idx8_store(cube_data,currplayer,cube_data[currplayer] & 0x01);
				activesprites_activated[index] = 1;
			}
		} else {
			if (controllingplayer->press & (PAD_A | PAD_UP)) {	
				currplayer_vel_y = 0;
				idx8_store(cube_data,currplayer,cube_data[currplayer] & 0x01);
				activesprites_activated[index] = 1;
			}
		}

		return;
	
	case 0x00:
	spcl_cube:
		orbactive = 0;
		robotjumpframe[0] = 0;
		robotjumpframe[1] = 0;
		exitPortalTimer = 10;
		if (gamemode == GAMEMODE_WAVE || gamemode == GAMEMODE_SNAKE) currplayer_vel_y = 0;
		if (retro_mode) gamemode = GAMEMODE_ROBOT;
		else gamemode = GAMEMODE_CUBE;
		clearrobotjumpframes();
		return;
	
	case 0x01: case 0x03:
	spcl_shipufo:
		settrailstuff();
		// intentional leak
	case 0x02:
	spcl_ball:
		if (gamemode != collided) currplayer_vel_y /= 2;
		gamemode = collided;
		activesprites_activated[index] = 1;
		gamemode_stuff();
		return;

	case 0x04:
	spcl_robot:
		exitPortalTimer = 10;
		if (gamemode == GAMEMODE_WAVE || gamemode == GAMEMODE_SNAKE) currplayer_vel_y /= 2;
		gamemode = GAMEMODE_ROBOT;
		clearrobotjumpframes();
		return;

	case 0x17:
	spcl_spider:
		if (gamemode == GAMEMODE_WAVE || gamemode == GAMEMODE_SNAKE) currplayer_vel_y = 0;
		gamemode = GAMEMODE_SPIDER;
		gamemode_stuff();
		return;

	case 0x24:
	spcl_wave:
		settrailstuff();		
		gamemode = GAMEMODE_WAVE;
		gamemode_stuff();
		return;

	case 0x6B:
	spcl_snake:
		settrailstuff();		
		gamemode = GAMEMODE_SNAKE;
		gamemode_stuff();
		return;

	case 0x6C:
	spcl_footb:
		gamemode = GAMEMODE_FOOTBALL;
		gamemode_stuff();
		return;

	case 0x6A:
	spcl_pogo:
		settrailstuff();
		if (gamemode == GAMEMODE_WAVE || gamemode == GAMEMODE_SNAKE) currplayer_vel_y = 0;
		gamemode = GAMEMODE_POGO;
		gamemode_stuff();
		return;
		
	case 0x4B:
	spcl_swing:
		settrailstuff();
		if (gamemode == GAMEMODE_WAVE || gamemode == GAMEMODE_SNAKE) currplayer_vel_y = 0;
		gamemode = GAMEMODE_SWING;
		gamemode_stuff();
		return;

	case 0x58:
	spcl_ninja:
		#ifdef FLAG_KANDO_FUN_STUFF
			if (gamemode == GAMEMODE_WAVE || gamemode == GAMEMODE_SNAKE) currplayer_vel_y = 0;		
			gamemode = GAMEMODE_NINJA;
			clearrobotjumpframes();
		#endif
		return;

	case 0x64:
	spcl_rndmode:
		#ifdef FLAG_KANDO_FUN_STUFF
			if (gamemode == GAMEMODE_WAVE || gamemode == GAMEMODE_SNAKE) currplayer_vel_y = 0;		
			gamemode = newrand() & 7;
			idx8_inc(activesprites_activated, index);
			gamemode_stuff();
		#endif
		return;

	case 0x7D:
	spcl_suprrnd:
		#ifdef FLAG_KANDO_FUN_STUFF
			if (gamemode == GAMEMODE_WAVE || gamemode == GAMEMODE_SNAKE) currplayer_vel_y = 0;		
			do {
				gamemode = newrand() & 15;
			} while (gamemode > 0x0B);
			idx8_inc(activesprites_activated, index);
			gamemode_stuff();
		#endif
		return;

	case 0x6E:
	spcl_minicoi:
		minicoins++;
		activesprites_type[index] = 0xFF;
		return;

	// Non-Gamemode portals 
	// - Gravity portals
	case 0x08: case 0x10: case 0x11: case 0x47: case 0xFC:
	spcl_gvdn_pt:
		if (!currplayer_gravity) 
			return;
		currplayer_gravity = GRAVITY_DOWN;
		goto spcl_gvity_portal_common;
	
	case 0x09: case 0x12: case 0x13: case 0x48: case 0xFB:
	spcl_gvup_pt:
		if (currplayer_gravity)
			return;
		currplayer_gravity = GRAVITY_UP;
		// intentional leak
	spcl_gvity_portal_common:
		settrailstuff();
		currplayer_vel_y /= 2;
		robotjumptime[currplayer] = 0;
		idx8_inc(activesprites_activated, index);
		update_currplayer_table_idx();
		return;
	
	// - Speed portals
	case 0x14:
	spcl_spd_05: speed = 1; return;
	case 0x15:
	spcl_spd_10: speed = 0; return;
	case 0x16:
	spcl_spd_20: speed = 2; return;
	case 0x20:
	spcl_spd_30: speed = 3; return;
	case 0x21:
	spcl_spd_40: speed = 4; return;
	case 0x6D:
	spcl_spdslow: speed = 5; return;

	// - Gravity portals
	case 0x63:
	spcl_gv1x_pt:
		#ifdef FLAG_KANDO_FUN_STUFF
			gravity_mod = 0;
		#endif
		return;

	case 0x5F:
	spcl_gv13_pt:
		#ifdef FLAG_KANDO_FUN_STUFF
			gravity_mod = 1;
		#endif
		return;

	case 0x60:
	spcl_gv12_pt:
		#ifdef FLAG_KANDO_FUN_STUFF
			gravity_mod = 2;
		#endif
		return;

	case 0x61:
	spcl_gv23_pt:
		#ifdef FLAG_KANDO_FUN_STUFF
			gravity_mod = 3;
		#endif
		return;

	case 0x62:
	spcl_gv2x_pt:
		#ifdef FLAG_KANDO_FUN_STUFF
			gravity_mod = 4;
		#endif
		return;

	// - Size portals
	case 0x18:
	spcl_mini_pt:
		currplayer_mini = 1;
		player_mini[0] = 1;
		player_mini[1] = 1;
		update_currplayer_table_idx();
		return;

	case 0x19:
	spcl_grow_pt:
		currplayer_mini = 0;
		player_mini[0] = 0;
		player_mini[1] = 0;
		update_currplayer_table_idx();
		return;

	// - Kando size portals


	// - Doubling portals
	case 0x22:
	spcl_dual_pt:
		if (!activesprites_activated[index]) {
			dual = 1;
			target_scroll_y = (lohi_arr16_load(activesprites_y, index) - PORTAL_TO_TOP_DIFF);
			if (twoplayer) { player_gravity[1] = player_gravity[0] ^ 0xFF;  }
			else { 
				player_x[1] = player_x[0]; player_y[1] = currplayer_y;
				player_gravity[1] = currplayer_gravity ^ 0xFF;
				player_vel_y[1] = -currplayer_vel_y; player_mini[1] = player_mini[0];
			}
			// activesprites_type[index] = 0xFF;
			activesprites_activated[index] = 1;
		}
		return;
	
	case 0x23:
	spcl_sngl_pt:
		if (!activesprites_activated[index]) {
			if (!twoplayer) { dual = 0; player_y[0] = currplayer_y; player_gravity[0] = currplayer_gravity; player_vel_y[0] = currplayer_vel_y; }
			else { player_gravity[1] = player_gravity[0]; }
			activesprites_activated[index] = 1;

			// activesprites_type[index] = 0xFF;
			exitPortalTimer = 10;
		}
		return;
	
	// - Teleport portals (and square)
	case 0x59:
	spcl_tlpt_sq:
		if ((cube_data[currplayer] & 2) || (controllingplayer->press & (PAD_A | PAD_UP))) {
			currplayer_vel_y = 0;
			orbed[currplayer] = 1;
			idx8_store(cube_data, currplayer, cube_data[currplayer] & 1);
	case 0x4E: case 0x66: case 0x68: case 0x75: case 0x77: case 0xED:
	spcl_tlpt_pt:
			high_byte(currplayer_y) = teleport_output;
		}
		return;

	// Alphabet blocks
	case 0xF9:
	spcl_s_block:
		if (dashing[currplayer]){
			dashing[currplayer] = 0; orbed[currplayer] = 1; currplayer_vel_y = 0;
		}
		return;
	case 0xF8:
	spcl_h_block: hblocked[currplayer] = 1; return;
	case 0xF7:
	spcl_j_block: jblocked[currplayer] = 1; orbed[currplayer] = 1; return;
	case 0xFA:
	spcl_d_block: dblocked[currplayer] = 1; return;
	case 0xF6:
	spcl_f_block: fblocked[currplayer] = 1; return;

	// Coins
	case 0x07: case 0x1C:
	spcl_coin_1:
		if (practice_point_count) return;
		if (coin1_timer) return;
		coins |= COIN_1;
		coin1_timer = 1;
		coin1_speed = 0x0200;
		goto spcl_coin_common;

	case 0x1A: case 0x1D:
	spcl_coin_2:
		if (practice_point_count) return;
		if (coin2_timer) return;
		coins |= COIN_2;
		coin2_timer = 1;
		coin2_speed = 0x0200;
		goto spcl_coin_common;

	case 0x1B: case 0x1E:
	spcl_coin_3:
		if (practice_point_count) return;
		if (coin3_timer) return;
		coins |= COIN_3;
		coin3_timer = 1;
		coin3_speed = 0x0200;
		// intentional leak
	spcl_coin_common:
		sfx_play(sfx_coin, 0);
		animating = 1;
		return;
	

	// collided with a pad
	case 0x0A: case 0x0C:
	spcl_ylw_pad:
		table_offset = yellow_pad;
		pad_stuff();
		return;
	case 0x25: case 0x26:
	spcl_pinkpad:
		table_offset = pink_pad;
		pad_stuff();
		return;
	case 0x52: case 0x53:
	spcl_red_pad:
		table_offset = red_pad;
		pad_stuff();
		return;

	case 0x65:
	spcl_grn_pad:
		#ifdef FLAG_KANDO_FUN_STUFF
		invert_gravity(currplayer_gravity); invert_gravity(player_gravity[0]); invert_gravity(player_gravity[1]);
		update_currplayer_table_idx();
		table_offset = yellow_orb;
		pad_stuff();
		idx8_inc(activesprites_activated, index);
		#endif
		return;
	
	case 0x0D: case 0xFD:
	spcl_gvdn_pd:
		clear_slope_stuff();
		if (!currplayer_gravity) { 
			settrailstuff();
			currplayer_gravity = GRAVITY_UP;				//flip gravity
			update_currplayer_table_idx();
			currplayer_vel_y = PAD_HEIGHT_BLUE(currplayer_table_idx);
			orbhitonthisframe[currplayer] = 1;
		}
		idx8_inc(activesprites_activated, index);
		return;
	
	case 0x0E: case 0xFE:
	spcl_gvup_pd:
		clear_slope_stuff();
		if (currplayer_gravity) { 	
			settrailstuff();
			currplayer_gravity = GRAVITY_DOWN;				//flip gravity
			update_currplayer_table_idx();
			currplayer_vel_y = PAD_HEIGHT_BLUE(currplayer_table_idx);
			orbhitonthisframe[currplayer] = 1;
			//invincible_counter = 3;				
		}
		idx8_inc(activesprites_activated, index);	
		return;

	// Spider orbs and pads
	case 0x54:
	spcl_sporbup:
		if ((cube_data[currplayer] & 2) || (controllingplayer->press & (PAD_A | PAD_UP))) {
			idx8_store(cube_data, currplayer, cube_data[currplayer] & 1);
	case 0x56:
	spcl_sppadup:
			high_byte(currplayer_y) -= eject_D;
			currplayer_vel_y = 0;
			currplayer_gravity = GRAVITY_UP;
			update_currplayer_table_idx();
			crossPRGBankJump0(spider_up_wait);
			high_byte(currplayer_y) -= eject_U;
			currplayer_vel_y = 0;	
			orbed[currplayer] = 1;
			idx8_inc(activesprites_activated, index);
		}
		return;
	case 0x55:
	spcl_sporbdn:
		if ((cube_data[currplayer] & 2) || (controllingplayer->press & (PAD_A | PAD_UP))) {
			idx8_store(cube_data, currplayer, cube_data[currplayer] & 1);
	case 0x57:
	spcl_sppaddn:
			high_byte(currplayer_y) -= eject_U + 1;
			currplayer_vel_y = 0;
			currplayer_gravity = GRAVITY_DOWN;
			update_currplayer_table_idx();
			crossPRGBankJump0(spider_down_wait);
			high_byte(currplayer_y) -= eject_D;
			currplayer_vel_y = 0;
			orbed[currplayer] = 1;
			idx8_inc(activesprites_activated, index);
		}
		return;

	case 0x0B:
	spcl_ylw_orb:
		table_offset = yellow_orb;
		//intentional leak
		goto spcl_orb_cmn;
	case 0x27:
	spcl_grn_orb:
	#ifdef FLAG_KANDO_FUN_STUFF		
		table_offset = yellow_orb;
		goto spcl_orb_cmn;
	#else
		return;
	#endif

	case 0x1F:
	spcl_ylw_big:
		table_offset = ylw_bigger;
		goto spcl_orb_cmn;

	case 0x29:
	spcl_ylw_sml:
		table_offset = ylw_smaller;
		goto spcl_orb_cmn;

	case 0x06:
	spcl_pinkorb:
		table_offset = pink_orb;
		goto spcl_orb_cmn;

	case 0x44:
	spcl_blckorb:
		table_offset = black_orb;
		goto spcl_orb_cmn;

	case 0x28:
	spcl_red_orb:
		table_offset = red_orb;
		// intentional leak

	case 0x05: case 0x45: case 0x46: case 0x4C: case 0x4D: case 0x50: case 0x51: case 0x5B:
	case 0x5C: case 0x5D: case 0x5E: case 0x7B: case 0x7C:
	spcl_orb_cmn:
		ufo_orbed[currplayer] = 1;		
		if (gamemode == GAMEMODE_CUBE || gamemode == GAMEMODE_POGO || gamemode == GAMEMODE_BALL || gamemode == GAMEMODE_ROBOT || gamemode == GAMEMODE_NINJA || gamemode == GAMEMODE_SPIDER || gamemode >= GAMEMODE_SWING) {
			sprite_gamemode_main();
		} else {
			sprite_gamemode_controller_check();
		}
		update_currplayer_table_idx();
		return;
	}
}

#undef table_offset
#undef collided

void sprite_collide(){
	if (gamemode != GAMEMODE_WAVE) {
		Generic.width = CUBE_WIDTH[currplayer_mini];
		Generic.height = CUBE_HEIGHT[currplayer_mini]; 
	} else {
		Generic.width = WAVE_WIDTH;
		Generic.height = WAVE_HEIGHT;
	}

	Generic.x = high_byte(currplayer_x) + 1;
	Generic.y = high_byte(currplayer_y) + (byte(0x10 - Generic.height) >> 1);

	index = 0;

	do {
		tmp3 = activesprites_active[index];
		if (tmp3){
			tmp4 = activesprites_type[index];

			tmp2 = sprite_heights[tmp4];
			tmp9 = sprite_widths[tmp4];
			/*
 * An if-chain, NOT a switch. Calypsi compiles this five-case sparse switch
 * (0, $FC, $FD, $FE, $FF) into a call to the library helper _ValueSwitch16,
 * which walks a table of case values - and the common case here is that tmp2
 * is a real sprite height and matches NONE of them, so the helper searched the
 * whole table and failed for every active sprite, every frame. Measured, it was
 * 683 instructions per frame on `cycles`, as much as the whole of
 * sprite_collide's own code, and it is exactly the MARGINAL cost per active
 * sprite - which is why sprite-heavy levels fell over while the NES, whose
 * compiler did not do this, did not. See docs/M2_18_SPRITE_COST.md.
 *
 * The four special codes are $FC..$FF, so one comparison rejects them all.
 */
			if (tmp2 == 0 || tmp2 >= OUTL) {
				if (tmp2 == DECO) {
					if (twoplayer || !viseffects) activesprites_type[index] = 0xFF;
					continue;
				}
				if (tmp2 == COLR) {
					if (discomode) {
						activesprites_type[index] = 0xFF; continue;
					}
					tmp2 = (tmp4 & 0x3F);
					
					if (tmp2 == 0x20) tmp2 = 0x30;
					
					if (tmp4 == 0x9F) {
						pal_col(0, color1);
						pal_col(1, oneShadeDarker(color1)); 
						pal_col(9, oneShadeDarker(color1)); 
						lastbgcolortype = tmp4;
					}						
					
					else if (tmp4 == 0xAE) {
						pal_col(6, color2);
						pal_col(5, oneShadeDarker(color2)); 
						lastgcolortype = tmp4;
					}
					else if (tmp4 >= 0xC0 && !invisblocks){
						pal_col(6, tmp2);
						pal_col(5, oneShadeDarker(tmp2)); 
						lastgcolortype = tmp4;
					} else if (tmp4 < 0xC0) {
						pal_col(0, tmp2);
						pal_col(1, oneShadeDarker(tmp2)); 
						pal_col(9, oneShadeDarker(tmp2)); 
						pal_col(0x0D, oneShadeDarker(tmp2)); 
						lastbgcolortype = tmp4;
						if (invisblocks) {
							pal_col(6, tmp2);
							pal_col(5, oneShadeDarker(tmp2)); 
						}
					}
					pal_set_update();
					activesprites_type[index] = 0xFF;
					// intentional leak
					continue;       /* the switch fell through to `case 0:` */
				}
				if (tmp2 == OUTL) {

					if (tmp4 == 0xAF) outline_color = color1;
					else outline_color = idx8_load(OUTLINES, tmp4 & 0x0F);
					activesprites_type[index] = 0xFF;
					continue;
				}
				if (tmp2 != SPBH)
					continue;       /* tmp2 == 0 */
					if ((tmp2 = sprite_load_special_behavior()) == 0) continue;
			}
			Generic2.height = tmp2;	
			Generic2.width  = tmp9;

			signExtend8to16(idx8_load(sprite_x_offset, tmp4));
			cc65_ptr2 = __AX__ + activesprites_realx[index];
			if (high_byte(cc65_ptr2) != 0)
				Generic2.x = (high_byte(cc65_ptr2) >= 0x80 ? 0x00 : 0xFF);
			else
				Generic2.x = low_byte(cc65_ptr2);

			signExtend8to16(idx8_load(sprite_y_offset, tmp4));
			cc65_ptr2 = __AX__ + activesprites_realy[index];
			if (high_byte(cc65_ptr2) != 0)
				Generic2.y = (high_byte(cc65_ptr2) >= 0x80 ? 0x00 : 0xFF);
			else
				Generic2.y = low_byte(cc65_ptr2);
			
			if (check_collision()) {
				sprite_collide_lookup();
			}
			
			else if (activesprites_type[index] == SKULL_ORB && activesprites_animated[index] == 1) activesprites_animated[index] = 2;
		}
	} while (++index < max_loaded_sprites);
	if (gamemode != GAMEMODE_WAVE) {
		Generic.width = CUBE_WIDTH[currplayer_mini]; 
		Generic.height = CUBE_HEIGHT[currplayer_mini];
	} else {
		Generic.width = WAVE_WIDTH;
		Generic.height = WAVE_HEIGHT;
	}
}


void settrailstuff() {
	if (forced_trails != 2 && !orbactive) {
		orbactive = 1;
	}
}

void clearrobotjumpframes() {
	robotjumpframe[0] = 0;
	robotjumpframe[1] = 0;
}			

void dual_cap_check() {
	if (dual && !twoplayer) {
		// Load player_vel_y of the other player, divide by 2, store it back.
		// SNES port: the original left the halved value in AX and wrote it back
		// with inline asm, reusing the Y that cc65 had already set to
		// (other player) * 2 by the load. Written out it is an in-place halve
		// of the other player's slot.
		player_vel_y[(currplayer^1)&0x7F] = player_vel_y[(currplayer^1)&0x7F] / 2;
	}
}				

#pragma code-name(pop)
#pragma data-name(pop) 
#pragma rodata-name(pop)
