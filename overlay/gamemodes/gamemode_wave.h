
CODE_BANK_PUSH(MOVEMENT_BANK)

void wave_eject();
void wave_movement(){

#define collided tmp4

	tmp1 = dashing[currplayer];

	switch (tmp1) {
	
		case 0:
			/* SNES port: written long-hand. Calypsi 5.18 compiled the nested
			   ternary as four arms that each leave the value in A and branch to
			   ONE shared store - and the store is preceded by a spurious `tya`,
			   so every arm's result was thrown away and whatever happened to be
			   in Y was stored instead. Measured: currplayer_vel_y was +1 on
			   every frame, so the wave did not move vertically at all.

			   This is the same miscompilation as the one in
			   gamemodes/gamemode_cube.h's common_gravity_routine; see
			   docs/HANDOFF.md. Each arm stores to currplayer_vel_y itself so
			   there is no value to lose at a merge. Do not fold it back into a
			   ternary without re-reading the generated code. */
			if (!currplayer_mini) {
				if (currplayer_gravity) currplayer_vel_y = -currplayer_vel_x;
				else                    currplayer_vel_y = currplayer_vel_x;
			} else {
				if (currplayer_gravity) currplayer_vel_y = -(currplayer_vel_x << 1);
				else                    currplayer_vel_y = (currplayer_vel_x << 1);
			}

			if (controllingplayer->hold & (PAD_A | PAD_UP) && gamemode != GAMEMODE_SNAKE) currplayer_vel_y = -currplayer_vel_y;
			
			else if (controllingplayer->hold & (PAD_A | PAD_UP)) {
				collided = DASH_GRAVITY_ORB;
				crossPRGBankJump0(sprite_gamemode_controller_check);
			}

			if (!currplayer_slope_frames && !currplayer_was_on_slope_counter) {
				currplayer_y += currplayer_vel_y;
			} else {
				currplayer_vel_y = 0;
			}
			break;
		case 1: currplayer_vel_y = 1; break;
		case 2: currplayer_vel_y = -currplayer_vel_x; currplayer_y += currplayer_vel_y; break;
		case 3: currplayer_vel_y = currplayer_vel_x; currplayer_y += currplayer_vel_y; break;
		case 4: currplayer_vel_y = currplayer_vel_x; currplayer_y -= currplayer_vel_y; break;
		case 5: currplayer_vel_y = currplayer_vel_x; currplayer_y += currplayer_vel_y; break;

	};
	Generic.x = high_byte(currplayer_x) + 4;
	
	// this literally offsets the collision down 2 pixel for the vel reset to happen every frame instead of each other frame
	Generic.y = high_byte(currplayer_y) + (currplayer_mini ? 0 : 4);
	
	

	wave_eject();
	


	Generic.x = high_byte(currplayer_x);
	Generic.y = high_byte(currplayer_y);

//	if (currplayer_vel_y != 0 && !slope_type){
//		if(controllingplayer->press & (PAD_A | PAD_UP)) {
//			idx8_store(cube_data, currplayer, cube_data[currplayer] | 0x02);
//		}
//	}
	
}	



void wave_eject() {
	if(high_byte(currplayer_vel_y) & 0x80){
		if (bg_coll_U()) {
			if(dblocked[currplayer]){ // check collision above
				high_byte(currplayer_y) = high_byte(currplayer_y) - eject_U;
				currplayer_vel_y = 0;
				idx8_store(cube_data, currplayer, cube_data[currplayer] & 1);			
			} else {
				idx8_store(cube_data, currplayer, cube_data[currplayer] | 1);		
			}
		}
	}
	else{
		if(bg_coll_D()){ // check collision below
			if (dblocked[currplayer]) {
				high_byte(currplayer_y) = high_byte(currplayer_y) - eject_D;
				currplayer_vel_y = 0;
				idx8_store(cube_data, currplayer, cube_data[currplayer] & 1);		    
			} else {
				idx8_store(cube_data, currplayer, cube_data[currplayer] | 1);		
			}
		}
	}
}


CODE_BANK_POP()
