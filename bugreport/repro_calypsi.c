/* Reproducer TU for the Calypsi 5.18 merge-point defect.
 *
 * This is probe/probe4.c with gamemode_cube.h taken from bugreport/gamemodes/
 * rather than overlay/, so the three miscompiled constructs are present. That
 * copy is the overlay file with only the workarounds reverted - the game's own
 * gamemode_cube.h cannot be used directly here because it is cc65 source and
 * does not compile under Calypsi at all.
 *
 * collision.h still comes from the overlay, because the original uses computed
 * goto - a separate unsupported feature (docs/HANDOFF.md trap 11) that would
 * stop the compile before reaching this bug.
 *
 *   sh bugreport/make_repro.sh
 *
 * Then look at the generated assembly for common_gravity_routine, cube_eject
 * and cube_movement, or run tools/scan_stackslots.py over it.
 */
#include "BUILD_FLAGS.h"
#include <stdint.h>
#include <stddef.h>
#include "arr_macros.h"
#include "neslib.h"
#include "nesdoug.h"
#include "mapper.h"
#include "nesdash.h"
#include "defines/space_defines.h"
#include "defines/physics_defines.h"
#include "defines/physics_table_defines.cmp.h"
#include "objdefines.h"
#include "famidash.h"
#include "METATILES/metatiles.h"
#include "functions/collision.h"
#include "functions/x_movement.h"
#include "gamemodes/gamemode_ufo.h"
#include "gamemodes/gamemode_ball.h"
#include "gamemodes/gamemode_cube.h"
#include "gamemodes/gamemode_ship.h"
#include "gamemodes/gamemode_spider.h"
#include "gamemodes/gamemode_wave.h"
