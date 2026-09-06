/* collision.h as its own translation unit - the ICE is cumulative, so
   splitting the unity build may dodge it (and the port wants the split anyway). */
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
