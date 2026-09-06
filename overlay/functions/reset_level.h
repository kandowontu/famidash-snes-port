/*
 * Keep the upstream reset routine, but replace its death animation with the
 * SNES-specific audio/OAM version below. Renaming before inclusion avoids
 * carrying a second copy of the large reset routine in this overlay.
 */
#define death_animation death_animation_upstream
#include "../../../famidash/SAUCE/functions/reset_level.h"
#undef death_animation

void death_animation()
{
	nmi_fs_updates_on();
	if (!practice_point_count || practice_music_sync)
		famistudio_music_stop();

	tmp1 = 30;
	if (!DEBUG_MODE) {
		if (cube_data[0] & 1)
			tmp2 = 0;
		else if (cube_data[1] & 1)
			tmp2 = 1;

		#if __VS_SYSTEM
		coins_inserted--;
		#endif

		update_level_completeness();
		sfx_play(sfx_death, 0);

		while (tmp1 != 0) {
			/*
			 * ppu_wait_nmi now honors auto_fs_updates, matching the NES NMI:
			 * the death SFX advances and the stopped song reaches the SPC.
			 */
			ppu_wait_nmi();
			crossPRGBankJump0(check_practice_point_deletion);

			/*
			 * Start a fresh OAM frame. The upstream code only hid the player
			 * slots and left sprid at the end of the gameplay frame, so every
			 * explosion frame appended after frozen level objects. That both
			 * left sprites stuck on screen and eventually filled all 128 slots.
			 */
			oam_clear();

			if (robotjumpframe[0] < 20) {
				if (retro_mode &&
				    !(gamemode == GAMEMODE_ROBOT ||
				      gamemode == GAMEMODE_NINJA ||
				      gamemode == GAMEMODE_UFO ||
				      gamemode == GAMEMODE_SHIP))
					mmc3_set_2kb_chr_bank_0(20);

				oam_meta_spr(
					idx16_load_hi_NOC(player_x, tmp2) - 2,
					idx16_load_hi_NOC(player_y, tmp2) - 2,
					(retro_mode &&
					 (gamemode == GAMEMODE_ROBOT ||
					  gamemode == GAMEMODE_NINJA ||
					  gamemode == GAMEMODE_UFO ||
					  gamemode == GAMEMODE_SHIP))
						? ExplodeR_Sprites[robotjumpframe[0] & 0x7F]
						: Explode_Sprites[robotjumpframe[0] & 0x7F]);
				++robotjumpframe[0];
			}

			if (practice_point_count > 1 &&
			    (((mouse.connected ? 0 : joypad2.press) | joypad1.press)
			     & PAD_SELECT)) {
				curr_practice_point--;
				if (curr_practice_point >= practice_point_count)
					curr_practice_point = practice_point_count - 1;
			}

			--tmp1;
		}
	}

	pal_fade_out();
	oam_clear();
	ppu_off();
	nmi_fs_updates_off();
}
