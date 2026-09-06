/* Probe: compile the real Famidash gameplay core for 65816 against the shim. */
#include <stdint.h>
#include <stddef.h>

#include "arr_macros.h"
#include "neslib.h"
#include "nesdoug.h"
#include "mapper.h"
#include "nesdash.h"

#include "defines/space_defines.h"
#include "defines/physics_defines.h"
#include "famidash.h"
