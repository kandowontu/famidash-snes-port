/* Original Famidash level-complete state, backed by the converted NES art. */
CODE_BANK_PUSH(LVLDONE_BANK)

void set_completion_data();

void state_lvldone()
{
	uint8_t current_state = 0;
	uint8_t coin_timer = 0;
	uint16_t velocity = 0;
	uint16_t position = 0xF000;

	nmi_fs_updates_on();
	famistudio_music_stop();
	crossPRGBankJump0(set_completion_data);

	oam_clear();
	snes_end_screen_enter();
	sfx_play(sfx_level_complete, 0);
	joypad1.press = 0;
	ppu_on_bg();

	while (1) {
		oam_clear();
		ppu_wait_nmi();

		switch (current_state) {
		case 0:
			velocity += 0x40;
			position -= velocity;
			set_scroll_y(high_byte(position));
			if (high_byte(position) < 10) {
				current_state = 1;
				velocity = (uint16_t)((velocity & 0x00FF) | 0xFA00);
			}
			break;
		case 1:
			velocity += 0x40;
			position -= velocity;
			set_scroll_y(high_byte(position));
			if (high_byte(position) < 5
			    && !(high_byte(velocity) & 0x80)) {
				current_state = 2;
				velocity = (uint16_t)((velocity & 0x00FF) | 0xFD00);
			}
			break;
		case 2:
			velocity += 0x40;
			position -= velocity;
			set_scroll_y(high_byte(position));
			if (high_byte(position) < 3
			    && !(high_byte(velocity) & 0x80)) {
				set_scroll_y(0);
				current_state = 3;
			}
			break;
		case 3:
			current_state = 4;
			coin_timer = 1;
			break;
		case 4:
		case 5:
		case 6: {
			uint8_t coin_number = (uint8_t)(current_state - 4);
			uint8_t coin_mask = (uint8_t)(1 << coin_number);
			if (coins & coin_mask) {
				snes_end_screen_reveal_coin(coin_number);
				if (coin_timer == 1) {
					sfx_play(sfx_coin, 0);
					coin_timer = 50;
				}
			}
			coin_timer--;
			if (coin_timer == 0 || coin_timer == 30) {
				current_state++;
				coin_timer = 1;
			}
			break;
		}
		case 7:
			if (joypad1.press & (PAD_LEFT | PAD_RIGHT)) {
				menuselection ^= 1;
				snes_end_screen_set_selector(menuselection);
			}
			if (joypad1.press & (PAD_A | PAD_START)) {
				if (menuselection) {
					sfx_play(sfx_exit_level, 0);
					snes_end_screen_leave();
					gameState = STATE_LEVELSELECT;
					menuselection = 0;
					menuMusicCurrentlyPlaying = 0;
					nmi_fs_updates_off();
					return;
				}
				sfx_play(sfx_start_level, 0);
				snes_end_screen_leave();
				coins = 0;
				gameState = STATE_GAME;
				nmi_fs_updates_off();
				return;
			}
			break;
		}
	}
}

CODE_BANK_POP()
