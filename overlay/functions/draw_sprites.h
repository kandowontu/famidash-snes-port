CODE_BANK_PUSH(SPRITE_RENDER_BANK)

void reset_level();
void minus15y();
void minus15x();
void plus15y();
void plus15x();
void trail_loop();
/*
	Draws the first player sprite
	Implemented in asm
*/
void __fastcall__ drawplayerone();
void __fastcall__ drawplayertwo();

void draw_sprites(){
	// dual = 1;
	// twoplayer = 1;
	
	// draw player
	if (!invisible) {
		if (dual) {
			if (kandoframecnt & 1 && !player_invis) { crossPRGBankJump0(drawplayertwo); crossPRGBankJump0(drawplayerone); }
			else if (!player_invis) { crossPRGBankJump0(drawplayerone); crossPRGBankJump0(drawplayertwo); }
		}
		else if (!player_invis) crossPRGBankJump0(drawplayerone);
	}

	// the level sprites

	//	for (index = 0; index < max_loaded_sprites; ++index){		//no flicker
	if (invisblocks) return;

	if (practice_point_count) {
		tmp3 = practice_player_1_y_hi[curr_practice_point];
		if (practice_sprite_x_pos > 10) { 
			practice_sprite_x_pos -= 3;
			oam_meta_spr(practice_sprite_x_pos, tmp3 - 1, Practice_Sprites[0]);
		}
		// else if (practice_sprite_x_pos < 10) {}
	}



	// The flickering motherfucker, by jrowe
	shuffle_offset = (shuffle_offset + 11) & 0x0F;
	// the level sprites
	count = 0;
	do {
		// and every sprite add another number thats also coprime with 16 AND 11
		shuffle_offset = (shuffle_offset + 9) & 0x0F;	// !!! If max_loaded_sprites changes change this
		index = shuffle_offset;
		
		if ((int8_t)(idx8_load(activesprites_type, index)) < 0) continue;
		if (!activesprites_active[index]) continue; 

		temp_x = activesprites_realx[index];
		if (temp_x > 0xf0) continue;
		if (temp_x == 0) temp_x = 1;

		temp_y = activesprites_realy[index];
		if (temp_y > 0xf0) continue;

		#define animation_frame_count tmp1
		#define animation_frame tmp2
		#define spr_type tmp3
		#define needs_reload tmp4
		#define animation_data_ptr tmpptr2

		// SNES port: replaces `#define animation_ptr tmpptr1`. The original
		// held the animation table in a zero-page byte pointer and stepped
		// through it three bytes at a time; that stride is a cc65 struct
		// layout, not a fact about the data, so the port keeps the real type.
		const struct SpriteFrame *anim_frames;


		if (nullscapes_active) {
			if (activesprites_type[index] == YELLOW_ORB ||
			activesprites_type[index] == RED_ORB ||
			activesprites_type[index] == BLACK_ORB ||
			activesprites_type[index] == BLUE_ORB_MULTI ||
			activesprites_type[index] == PINK_ORB ||
			activesprites_type[index] == GREEN_ORB ||
			activesprites_type[index] == GREEN_ORB_MULTI ||
			activesprites_type[index] == BLUE_ORB) {

				switch (nullscapes_orb_type) {
					case 0:	
							activesprites_type[index] = RED_ORB;
							break;
					case 1:	
							activesprites_type[index] = BLUE_ORB_MULTI;
							break;
					case 2:	
							activesprites_type[index] = YELLOW_ORB;
							break;
					case 3:	
							activesprites_type[index] = BLACK_ORB;
							break;
					case 4:	
							activesprites_type[index] = GREEN_ORB_MULTI;
							break;
					case 5:	
							activesprites_type[index] = PINK_ORB;
							break;
				};
				activesprites_activated[index] = 0;
			}
		}						
		


		needs_reload = 0;
		spr_type = activesprites_type[index];
		// SNES port: this is a `const struct SpriteFrame *`, and it has to be
		// treated as one - see the block below for what went wrong when it was
		// walked as raw bytes.
		anim_frames = (const struct SpriteFrame *)animation_frame_list[spr_type & 0x7F];
		// If this sprite has animations, then this pointer will not be null
		if (anim_frames) {
			// Reduce the frame counter by one to see if we need to move to the next frame
			// If this frame has expired, then move to the next animation frame
			animation_frame_count = idx8_dec(activesprites_anim_frame_count, index);
			if ((int8_t)animation_frame_count < 0) {

				if ((activesprites_type[index] == SKULL_ORB && activesprites_animated[index] == 1) || activesprites_type[index] != SKULL_ORB) {
					animation_frame = idx8_inc(activesprites_anim_frame, index);
				}

				else if (activesprites_type[index] == SKULL_ORB && activesprites_animated[index] == 2) { if (activesprites_anim_frame[index]) { animation_frame = idx8_dec(activesprites_anim_frame, index); } else { animation_frame = activesprites_anim_frame[index]; } }

				else { animation_frame = activesprites_anim_frame[index]; }

				// if the animation frame is past the length, wrap it around back to zero
				if (animation_frame >= animation_frame_length[spr_type]) {
				
					if (activesprites_type[index] != SKULL_ORB) {
						activesprites_anim_frame[index] = 0;
						animation_frame = 0;
					} else {
						idx8_dec(activesprites_anim_frame, index);
						animation_frame--;
					}
				}
				// and then set the animation_frame_count to be reloaded
				needs_reload = 1;
			} else {
					animation_frame = activesprites_anim_frame[index];
			}
			
			// Now load the data for this frame of animation.
			//
			// SNES port: INDEX THE STRUCT, do not walk it as bytes.
			//
			// The original is
			//     __AX__ = animation_frame * 3;   animation_ptr += __AX__;
			//     low_byte(dst) = animation_ptr[1];
			//     high_byte(dst) = animation_ptr[2];
			// because on cc65 `struct SpriteFrame { uint8_t frame_count;
			// const uint8_t *ptr; }` is exactly three bytes with the pointer at
			// offset 1 - the NES address space is 16-bit.
			//
			// Here a pointer is FOUR bytes and the struct is padded, so a stride
			// of 3 and an offset of 1 read neither the frame count nor the
			// pointer. The result was a garbage 24-bit address handed to
			// oam_meta_spr, which walks (dx, dy, tile, attr) quadruplets until
			// it reads dx == $80: with no terminator where one was expected it
			// ran until it happened to find an $80 byte. Measured on the coin
			// (type $07): 7161 sprites out of ONE call, filling OAM with garbage
			// tiles and taking fifty video frames to return. That is both the
			// "missingno" look and the worst of the lag.
			//
			// Written as a struct access it is correct on either compiler, and
			// the bank byte the 16-bit form had to reconstruct by hand comes out
			// of the table for free.
			animation_data_ptr = (unsigned char *)anim_frames[animation_frame].ptr;

			if (needs_reload) {
				activesprites_anim_frame_count[index] =
					(int8_t)anim_frames[animation_frame].frame_count;
			}

			// And load the pointer for this animation
		} else {
			animation_data_ptr = (unsigned char*)Metasprites[spr_type & 0x7F];
		}
		if (!disco_sprites) oam_meta_spr(temp_x, temp_y, animation_data_ptr);
		else oam_meta_spr_disco(temp_x, temp_y, animation_data_ptr);
		
	} while (++count < max_loaded_sprites);
	if (!dual) {
	if (kandoframecnt & 1) {
		
		tmp2 = sizeof(trail_sprites_visible) - 1;
		do {
			// SNES port: the pha/pla was cc65 register juggling around the two
			// indexed accesses. It is a one-element shift of the trail history.
			idx8_store(trail_sprites_visible, tmp2,
			           idx8_load(trail_sprites_visible, tmp2 - 1));
		} while (--tmp2 != 0);

		trail_sprites_visible[0] = (trails == 1 || orbactive);
	}
	if (viseffects) {
		if ((trails == 1) || (trails != 2 && forced_trails != 2 && !invisible)) {
			trail_loop();
		}
		else if ((forced_trails == 2 || trails == 2) && !(kandoframecnt & 1)) {
			skipProcessingCubeRotationLogic++;
			tmp6 = currplayer_vel_x << 1;
			
			tmpA = player_x[0];
			tmpB = player_y[0];

			high_byte(player_x[0]) -= high_byte(tmp6);
			high_byte(player_y[0]) = player_old_posy[0];

			crossPRGBankJump0(drawplayerone);
			
			high_byte(player_x[0]) -= high_byte(tmp6);
			high_byte(player_y[0]) = player_old_posy[1];

			crossPRGBankJump0(drawplayerone);

			high_byte(player_x[0]) -= high_byte(tmp6);
			high_byte(player_y[0]) = player_old_posy[2];

			if (gamemode == GAMEMODE_CUBE) {
				tmp9 = currplayer_mini;
				currplayer_mini = 1;
			}

			crossPRGBankJump0(drawplayerone);
			
			if (gamemode == GAMEMODE_CUBE) {
				currplayer_mini = tmp9;
			}
			
			player_x[0] = tmpA;
			player_y[0] = tmpB;
			skipProcessingCubeRotationLogic--;		
		}
	}
	}
#undef spr_type
}

void trail_loop() {
	if (kandoframecnt & 1) {
		tmp6 = currplayer_vel_x << 1;
		tmp1 = 1;
		tmp5 = currplayer_x - tmp6;
		do {
			if (trail_sprites_visible[tmp1]) {	
				oam_spr(
					high_byte(tmp5) + Trail_Circ_X,
					player_old_posy[tmp1] + Trail_Circ_Y,
					Trail_Circ_CHR, Trail_Circ_Attr);
			}
			
			tmp5 = tmp5 - tmp6;
			tmp1++;
		} while (tmp1 < 8);
	} else {
		tmp1 = 7;
		// the following 2 lines of code are equal to tmp5 -= (tmp6 * 7)
		tmp5 = currplayer_vel_x << 4;
		tmp5 = (currplayer_vel_x << 1) + currplayer_x - tmp5;
		do {
			if (trail_sprites_visible[tmp1]) {
				oam_spr(
					high_byte(tmp5) + Trail_Circ_X,
					player_old_posy[tmp1] + Trail_Circ_Y,
					Trail_Circ_CHR, Trail_Circ_Attr);
			}
			
			tmp5 = tmp5 + tmp6;
			tmp1--;
		} while (tmp1 > 0);
	}	
}

void put_progress_bar_sprite() {
	oam_meta_spr(tmp1, tmp2, (Number_Sprites+22)[tmp3 & 0x7F]);	// = Number_Sprites[22+tmp3]
}

void put_number() {
	oam_meta_spr(tmp1, tmp2, Number_Sprites[(high_byte(tmp6) + tmp3) & 0x7F]);
}

void minus15y() {
	high_byte(player_y[0]) -= 15;
}

void minus15x() {
	high_byte(player_x[0]) -= 15;
}

void plus15y() {
	high_byte(player_y[0]) += 15;
}

void plus15x() {
	high_byte(player_x[0]) += 15;
}






CODE_BANK_POP()
