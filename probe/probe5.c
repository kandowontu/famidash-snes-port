/* M1.4 probe: drive the real cube physics from main() so the linker reports
   everything the shim must actually provide. */
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
#include "gamemodes/gamemode_cube.h"

int main(void) {
    for (;;) {
        pad_poll(0);
        cube_movement();
        x_movement();
    }
}
