// prototype
#ifdef level_luckydraw
void Lucky_Draw_Text_Stuff();
#endif
void init_sprites();
#if !__VS_SYSTEM
	#include "defines/charmap/bg_charmap.h"
	const unsigned char attempttext[]="PQQRSTQ"; //ATTEMPT
#endif


//const unsigned char whartxt[]="wxyz";	// WHAR
void setdefaultoptions();
/* 
	Reset run-length decoder back to zero
	Implemented in asm
*/
void __fastcall__ init_rld(uint8_t level);

/* 
	This should explain itself
	Requires the correct PRG1 bank to be set
	Implemented in asm
*/
void __fastcall__ unrle_next_column();

/* 
	Scrolling to the right, draw metatiles as we go
	Returns 1 if it actually did anything
	Implemented in asm	
*/
char __fastcall__ draw_screen();

/*
	Load ground tiles into collision map
	Implemented in asm
*/
void __fastcall__ load_ground(uint8_t id);

/*
	Dummy unrle columns, way faster
	Implemented in asm
*/
void __fastcall__ dummy_unrle_columns(uint16_t columns);

void increase_parallax_scroll_column() {
	// The parallax is a 6 x 9 tile background, and when it repeats
	// horizontally, we offset the start of the next column by 3
	// to stagger the repeat
	parallax_scroll_column++;
	if (parallax_scroll_column >= 6) {
		parallax_scroll_column = 0;
		parallax_scroll_column_start += 3;
		if (parallax_scroll_column_start >= 9) {
			parallax_scroll_column_start = 0;
		}
	}
}

extern unsigned char drawing_frame;
void unrle_first_screen(){ // run-length decode the first screen of a level
	// register unsigned char i;
	#define i (*((uint8_t *)&ii))
	// SNES port: `register` dropped. cc65 keeps register locals in an
	// addressable zero-page pseudo-stack, so taking &ii is legal there;
	// Calypsi rejects it ("address of register variable requested"). The
	// keyword was only ever a hint, and `i` aliases the low byte of `ii`.
	uint16_t ii;
	mmc3_set_prg_bank_1(GET_BANK(increment_attempt_count));
	#if !__VS_SYSTEM
		increment_attempt_count();
	#else
		memfill(attemptCounter, 0, sizeof(attemptCounter));
		for (tmp2 = 0; tmp2 < coins_inserted; tmp2++) {
			increment_attempt_count();
		}
	#endif



	mmc3_set_prg_bank_1(level_data_bank);



	// If practice mode has set a scroll position to restart from
	// Then we dummy unrle, and adjust the parallax to match
	if (practice_point_count) {

		ii = lohi_arr32_load(practice_scroll_x, curr_practice_point) >> 4;
		dummy_unrle_columns(ii);

		// SNES port of the original's inline asm, which parked two constants in
		// Y and reused them:
		//   1. Y = -9. parallax_scroll_column starts there and counts up once
		//      per skipped column, snapping back to -9 whenever it reaches 0,
		//      so it cycles with period 9.
		//   2. Y = 3. Both counters then step by 3 until parallax_scroll_column
		//      goes non-negative - the trailing `bmi` tested the N flag left by
		//      the line above it, so this is a do/while on bit 7.
		#define PARALLAX_PHASE_RESET ((uint8_t)-(6 * (9 / 3) / 2))   /* -9 */
		parallax_scroll_column = PARALLAX_PHASE_RESET;
		while (ii != 0) {
			parallax_scroll_column++;
			if (parallax_scroll_column == 0) {
				parallax_scroll_column = PARALLAX_PHASE_RESET;
			}
			ii--;
		}
		parallax_scroll_column_start = -3;
		do {
			parallax_scroll_column_start += 3;
			parallax_scroll_column += 3;
		} while (parallax_scroll_column & 0x80);
		#undef PARALLAX_PHASE_RESET
		parallax_scroll_column <<= 1;

		crossPRGBankJump0(load_practice_state);	

		mmc3_set_prg_bank_1(GET_BANK(draw_screen));
		// Draw the nametable starting from where the scroll is set
		i = -16;
		do {
			draw_screen();
			i++;
			uint32_inc(scroll_x);
		} while (i != 0);
	} 
	else {
		// To get the draw screen R to start in the left nametable, scroll must be negative.
		low_word(scroll_x) = LSW(-256); high_word(scroll_x) = MSW(-256);
		parallax_scroll_x = 0;
		parallax_scroll_column = 0;
		parallax_scroll_column_start = 0;
		i = 0;
		mmc3_set_prg_bank_1(GET_BANK(draw_screen));
	}
	

	// Draw the nametable starting from where the scroll is set
    do {
		draw_screen();
		i++;
		uint32_inc(scroll_x);
	} while (i != 0);
	/*
	 * SNES port: send the prepared first screen as one batch. On SA-1 every
	 * forced-blank flush is a synchronous S-CPU request serviced at vblank;
	 * flushing every column turned a death restart into dozens of black frames.
	 * The column queue/ring both hold 64 entries and this pass produces 34.
	 */
	flush_vram_update2();

//	level_resetting_flag = 2;
//	if (!level_resetting_flag) timewarp_done = 0;   how was this a fix? this cant ever be false...

	init_sprites();
	
	set_scroll_x(scroll_x);
	set_scroll_y(scroll_y);
//	if (!practice_point_count) {
		#if !__VS_SYSTEM
			multi_vram_buffer_horz((const char*)attempttext,sizeof(attempttext)-1,NTADR_C(6, 15));
		#endif
	
			#ifdef level_luckydraw
			
			crossPRGBankJump0(Lucky_Draw_Text_Stuff);

			#endif
			
			mmc3_set_prg_bank_1(GET_BANK(_display_attempt_counter));
			display_attempt_counter(0xF5, NTADR_C(20, 15));
			
			
//	}
	
}
