/*
 * gameplay_helpers.h - five functions that gameplay needs but that live in
 * SAUCE/menustates/bgmtest.c on the NES.
 *
 * bgmtest.c is a copy of the game loop used by the music test, and it happens
 * to be where these ended up; state_game.h and state_lvldone.h call them. The
 * SNES port is not building the menus yet, so they are extracted here rather
 * than dragging in a menu state. They are otherwise unchanged, except for
 * decrement_was_on_slope, noted below.
 *
 * If the menus are ported later, these must be deleted from here, not
 * duplicated - two definitions will not link.
 */

/*
 * SNES port: the original computed a physics table index with inline asm -
 *
 *      __A__ = (currplayer_slope_type & SLOPE_UPSIDEDOWN) + (256 - SLOPE_UPSIDEDOWN);
 *      __A__ = currplayer_table_idx & ~TBLIDX_GRAV;
 *      __asm__ ("adc #0 \n tay");
 *
 * The first line exists only for its carry: it sets C when the slope is upside
 * down. The `adc #0` then folds that carry into the table index, so the gravity
 * bit is replaced by the upside-down bit. `get_Y` afterwards reads that index.
 *
 * This is one of the three get_Y sites the shim cannot cover, because Y is set
 * by hand rather than by an array macro (docs/HANDOFF.md trap 29).
 */
void decrement_was_on_slope() {
	if (currplayer_was_on_slope_counter) {
		currplayer_was_on_slope_counter--;

		if (!currplayer_was_on_slope_counter) {
			if (gamemode == GAMEMODE_CUBE || gamemode == GAMEMODE_BALL) {
				uint8_t slope_tbl_idx = (uint8_t)
					((currplayer_table_idx & ~TBLIDX_GRAV)
					 + ((currplayer_slope_type & SLOPE_UPSIDEDOWN) ? 1 : 0));

				switch (gamemode) {
					case GAMEMODE_BALL:
						switch (currplayer_slope_type) {
							case SLOPE_22DEG_UP:
							case SLOPE_22DEG_UP_UD:
								currplayer_vel_y += EXIT_SLOPE_BALL_22(slope_tbl_idx);
								break;
							case SLOPE_66DEG_UP:
							case SLOPE_66DEG_UP_UD:
								currplayer_vel_y += EXIT_SLOPE_BALL_66(slope_tbl_idx);
						}
						break;
					case GAMEMODE_CUBE:
						switch (currplayer_slope_type) {
							case SLOPE_22DEG_UP:
							case SLOPE_22DEG_UP_UD:
								currplayer_vel_y += EXIT_SLOPE_CUBE_22(slope_tbl_idx);
								break;
						}
						break;
				}
			}
			currplayer_slope_type = 0;
		}
	} else {
		currplayer_last_slope_type = 0;
		currplayer_slope_type = 0;
	}
}

void check_practice_point_deletion() {
	if (practicebuffer || (practice_point_count > 1 && (joypad1.press_select || (mouse.left && mouse.right_press)) && !(joypad1.hold & (PAD_UP | PAD_DOWN)))) {
				curr_practice_point--;
				practicebuffer = 0;
				if (latest_practice_point) latest_practice_point--;
				if (curr_practice_point >= practice_point_count)
					curr_practice_point = practice_point_count - 1;
	}
}

void end_level_debug() {
				END_LEVEL_TIMER = 0;
				kandokidshack4 = 0;
				oam_clear();
				gameState = STATE_LVLDONE;
				famistudio_music_stop();
}

void set_completion_data() {
	if (!DEBUG_MODE && !kandokidshack && !kandokidshack3 && !kandokidshack4) {
		if (!practice_point_count) {
			if (!invisblocks) {
				LEVELCOMPLETE[level] = 1;
				if (coins & COIN_1) coin1_obtained[level] = 1;
				if (coins & COIN_2) coin2_obtained[level] = 1;
				if (coins & COIN_3) coin3_obtained[level] = 1;
				level_completeness_normal[level] = 100;
			}
			else {
				invisible_LEVELCOMPLETE[level] = 1;
				if (coins & COIN_1) invisible_coin1_obtained[level] = 1;
				if (coins & COIN_2) invisible_coin2_obtained[level] = 1;
				if (coins & COIN_3) invisible_coin3_obtained[level] = 1;
				invisible_level_completeness_normal[level] = 100;
			}
		} else {
			if (!invisblocks) level_completeness_practice[level] = 100;
			else invisible_level_completeness_practice[level] = 100;
		}
	}
}

void set_lvldone_palette() {
	// The CHR bank calls are no-ops on SNES - there is no CHR ROM, tiles live
	// in VRAM. Kept so the call sites match the NES build.
	mmc3_set_1kb_chr_bank_0(LEVELCOMPLETEBANK);
	mmc3_set_1kb_chr_bank_1(PRACTICECOMPLETEBANK);
	mmc3_set_1kb_chr_bank_2(LEVELCOMPLETEBANK+2);
	mmc3_set_1kb_chr_bank_3(LEVELCOMPLETEBANK+3);
	mmc3_set_2kb_chr_bank_1(MOUSEBANK);

	// Set palettes back to natural colors since we aren't fading back in
	pal_bright(4);
	pal_bg(paletteMenu);
	pal_col(0x0A,0x2A);
	pal_col(0x0B,0x21);
	pal_set_update();
	pal_spr(paletteDefaultSP);
}
