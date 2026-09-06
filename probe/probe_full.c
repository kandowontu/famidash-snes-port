/* The whole gameplay half of SAUCE/, compiled for 65816.
 *
 * Mirrors SAUCE/include.h's ordering for everything except the menus and the
 * sound driver. Overlay path comes first so ported files shadow the originals.
 *
 * This is the scope probe: what does not compile here is what still needs
 * porting. It is not linked into the ROM until it builds clean.
 */
#include "BUILD_FLAGS.h"
#include <stdint.h>
#include <stddef.h>
#include "nonstdint.h"
#include "arr_macros.h"

#include "neslib.h"
#include "nesdoug.h"
#include "mapper.h"
#include "nesdash.h"
#include "famistudio_cc65.h"
#include "musicDefines.h"
#include "sfxDefines.h"

#include "level_defines.h"
#include "defines/space_defines.h"
#include "defines/physics_defines.h"
#include "defines/physics_table_defines.cmp.h"

#include "mouse.h"
#include "grounddata.h"
#include "groundlist.h"
#include "objdefines.h"
#include "defines/difficulty.h"
#include "levellist.h"
#include "const_levellist.h"
#include "defines/dialogbox.h"

#include "famidash.h"

/* Data-only files. palettes_PRG.c is where include.h puts it; the level-done
 * nametables live on the menu side, but state_lvldone.h needs them and they are
 * self-contained arrays, so they come in here rather than dragging in the whole
 * menu system. */
#include "defines/palette/palettes_PRG.c"
#include "defines/nametable/menunametable_XCD06.c"

#include "METATILES/metatiles.h"
#include "defines/sprites.h"
#include "functions/sprite_loading.h"
#include "functions/practice_state.h"
#include "functions/draw_sprites.h"
/* level_loading.h calls Lucky_Draw_Text_Stuff when the level set defines
   level_luckydraw, which lvlset_HUGE does. It lives in credits.c, which is not
   ported - see the header of this file. */
#include "menustates/lucky_draw_text.h"
#include "functions/level_loading.h"
#include "functions/scroll.h"
#include "functions/collision.h"
#include "functions/reset_level.h"
/* Extracted from menustates/bgmtest.c - gameplay calls them but they live
 * on the menu side upstream. See the file header. */
#include "functions/gameplay_helpers.h"

#include "functions/x_movement.h"

#include "gamemodes/gamemode_ufo.h"
#include "gamemodes/gamemode_ball.h"
#include "gamemodes/gamemode_cube.h"
#include "gamemodes/gamemode_ship.h"
#include "gamemodes/gamemode_spider.h"
#include "gamemodes/gamemode_wave.h"

#include "gamestates/state_game.h"
#include "gamestates/state_lvldone.h"
#include "gamestates/state_savefile_validate.h"
