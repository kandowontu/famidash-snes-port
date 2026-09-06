
CODE_BANK_PUSH(SCROLL_BANK)


#define player0_x currplayer_x
#define player1_x player_x[1]

#define player0_y currplayer_y
#define player1_y player_y[1]

void process_x_scroll() {
	switch (cam_seesaw) {
		case 1:
			if (curr_x_scroll_stop < 0xD000) target_x_scroll_stop = 0xD000;
			else cam_seesaw = 2;
			break;
		case 2:
			if (curr_x_scroll_stop > 0x1000) target_x_scroll_stop = 0x1000;
			else cam_seesaw = 1;
			break;
	}


	if (!kandodebugmode) {
		if (curr_x_scroll_stop < target_x_scroll_stop) curr_x_scroll_stop += 0x200;
		else if (curr_x_scroll_stop > target_x_scroll_stop) curr_x_scroll_stop -= 0x200;		
	} else {
		if (curr_x_scroll_stop < target_x_scroll_stop) curr_x_scroll_stop += 0x180;
		else if (curr_x_scroll_stop > target_x_scroll_stop) curr_x_scroll_stop -= 0x180;		
	}		

	if (player0_x > curr_x_scroll_stop){ // change x scroll
		tmp1 = MSB(player0_x - curr_x_scroll_stop);
		scroll_x += tmp1;
		parallax_scroll_x += tmp1 ? tmp1 - 1 : 0;
		if (parallax_scroll_x >= 144) {
			parallax_scroll_x -= 144;
		}
		high_byte(player0_x) = high_byte(player0_x) - tmp1;
		high_byte(player1_x) = high_byte(player1_x) - tmp1;
	} else if (player0_x < 0x0200){ // change x scroll
		tmp1 = MSB(player0_x + 0x0200);
		scroll_x = scroll_x - tmp1;
		if (tmp1) {
			if (tmp1 > parallax_scroll_x) {	// sorta yoda notation
				parallax_scroll_x += 144;
			}
			parallax_scroll_x -= tmp1 - 1;
		}
		
		high_byte(player0_x) = high_byte(player0_x) + tmp1;
		high_byte(player1_x) = high_byte(player1_x) + tmp1;
	}
}


void process_y_scroll() {
	if ((!dual || twoplayer) && (gamemode == GAMEMODE_CUBE || gamemode == GAMEMODE_ROBOT || gamemode == GAMEMODE_NINJA || gamemode == GAMEMODE_POGO || nocamlock || nocamlockforced)) {
			if (exitPortalTimer) exitPortalTimer--;
			if (player0_y < 0x4000 && 
				(scroll_y >= min_scroll_y && (scroll_y_subpx || scroll_y != min_scroll_y))
				){
				// change y scroll (upward)
				cc65_ptr1 = 0x4000 - player0_y;
				if (exitPortalTimer) {
					cc65_tmp1 = (11 - exitPortalTimer);
					if (MSB(cc65_ptr1) >= cc65_tmp1) cc65_ptr1 = (cc65_tmp1) << 8;
				}
				player0_y += cc65_ptr1;
				player1_y += cc65_ptr1;

				// SNES port: do_if_borrow tested the 6502 carry left by the line above.
				// Written as an explicit test of the same condition, evaluated before
				// scroll_y_subpx changes. Incrementing the high byte does not disturb
				// LSB(cc65_ptr1), so hoisting the test above the accumulate is exact.
				if (scroll_y_subpx < LSB(cc65_ptr1)) { ++high_byte(cc65_ptr1); }
				scroll_y_subpx -= LSB(cc65_ptr1);
				scroll_y = sub_scroll_y(MSB(cc65_ptr1), scroll_y);
			}
			cap_scroll_y_at_top();

			if (scroll_y < 0x2EF && high_byte(player0_y) >= MSB(0xA000)){
				// change y scroll (downward)
				cc65_ptr1 = player0_y - 0xA000;
				if (exitPortalTimer) {
					cc65_tmp1 = (11 - exitPortalTimer);
					if (MSB(cc65_ptr1) >= cc65_tmp1) cc65_ptr1 = (cc65_tmp1) << 8;
				}
				player0_y = player0_y - cc65_ptr1;
				player1_y = player1_y - cc65_ptr1;

				// SNES port: do_if_carry tested the 6502 carry left by the line above.
				// Written as an explicit test of the same condition, evaluated before
				// scroll_y_subpx changes. Incrementing the high byte does not disturb
				// LSB(cc65_ptr1), so hoisting the test above the accumulate is exact.
				if ((uint16_t)scroll_y_subpx + LSB(cc65_ptr1) > 0xFF) { ++high_byte(cc65_ptr1); }
				scroll_y_subpx += LSB(cc65_ptr1);
				scroll_y = add_scroll_y(MSB(cc65_ptr1), scroll_y);
			}
			cap_scroll_y_at_bottom();
	} else {			//ship stuff
		if (low_byte(target_scroll_y) >= 0xf0) {
			target_scroll_y += 0x10;
		}
		if (target_scroll_y > scroll_y) {
			cc65_ptr1 = SHIP_SCROLL_SPEED(framerate);
			
			player0_y = player0_y - cc65_ptr1;
			player1_y = player1_y - cc65_ptr1;

			// SNES port: do_if_carry tested the 6502 carry left by the line above.
			// Written as an explicit test of the same condition, evaluated before
			// scroll_y_subpx changes. Incrementing the high byte does not disturb
			// LSB(cc65_ptr1), so hoisting the test above the accumulate is exact.
			if ((uint16_t)scroll_y_subpx + LSB(cc65_ptr1) > 0xFF) { ++high_byte(cc65_ptr1); }
			scroll_y_subpx += LSB(cc65_ptr1);
			scroll_y = add_scroll_y(MSB(cc65_ptr1), scroll_y);
		}
		if (target_scroll_y < scroll_y) {
			cc65_ptr1 = SHIP_SCROLL_SPEED(framerate);
			
			player0_y = player0_y + cc65_ptr1;
			player1_y = player1_y + cc65_ptr1;

			// SNES port: do_if_carry tested the 6502 carry left by the line above.
			// NOTE this arm subtracts and then tests carry SET (= no borrow),
			// which is the opposite of the other subtract site above. That
			// asymmetry is in the original and is preserved here deliberately;
			// see docs/HANDOFF.md. Do not "fix" it as part of the port.
			if (scroll_y_subpx >= LSB(cc65_ptr1)) { ++high_byte(cc65_ptr1); }
			scroll_y_subpx -= LSB(cc65_ptr1);
			scroll_y = sub_scroll_y(MSB(cc65_ptr1), scroll_y);
		}
		cap_scroll_y_at_top();
		cap_scroll_y_at_bottom();
	}
}

void do_the_scroll_thing(){
	process_x_scroll();
	process_y_scroll();

    set_scroll_x(scroll_x);
    set_scroll_y(scroll_y);
}


CODE_BANK_POP()
