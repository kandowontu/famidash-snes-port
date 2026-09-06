/* Calypsi 65816 5.18 - a value computed on both arms of a `?:` is discarded at
 * the join, which reloads it from a stack slot nothing in the function wrote.
 *
 *   cc65816 --code-model large --data-model large -O 1 \
 *           -c merge_point_value_lost.c -o merge_point_value_lost.o \
 *           --assembly-source merge_point_value_lost.s
 *
 * `eject()` below is a cut-down of cube_eject() from Famidash
 * (github.com/tfdsoft/famidash), reached while porting the game to SNES. The
 * emitted code for
 *
 *      vel_y = grav ? 0xffff : 0;
 *
 * is
 *
 *      `?L1220`:   sep     #32
 *                  lda     long:grav
 *                  rep     #32
 *                  bne     `?L1224`
 *                  lda     ##0
 *                  bra     `?L1225`
 *      `?L1224`:   lda     ##-1
 *      `?L1225`:   lda     1,s              <-- both arms discarded
 *                  sta     long:vel_y
 *
 * Nothing in the function ever stores to 1,s; it holds whatever the caller
 * left on the stack. The code is otherwise valid, so this compiles and links
 * clean and produces a stable, plausible, wrong value at run time.
 *
 * Two more instances of the same defect in the same program:
 *
 *   cube_movement()   tmp3 = (chargepower[p] > 45 ? 45 : chargepower[p]);
 *                     one arm stored to 1,s, the other left the value in A,
 *                     and the join read 3,s - a third slot again.
 *
 *   common_gravity_routine()
 *                     a `register int16_t` was allocated to Y; each case of a
 *                     following switch read it with `tya`, and the join after
 *                     the switch did `lda 1,s`. The symptom was a physics
 *                     accumulator stepping by a constant garbage -0x3900 per
 *                     frame instead of by gravity, so the player never landed.
 *
 * Writing the merge out long-hand, so every branch does its own store and no
 * value has to survive the join, generates correct code. That is the
 * workaround used in the port.
 */
#include <stdint.h>

uint16_t vel_y;
uint16_t y;
uint8_t grav;
uint8_t eject_D, eject_U;
uint8_t orbactive;
uint8_t player;
uint8_t hblocked[2], fblocked[2];

extern uint8_t coll_D(void);
extern uint8_t coll_U(void);
extern void update_idx(void);

#define low_byte(a)  (*((uint8_t *)&(a)))
#define high_byte(a) (*((uint8_t *)&(a) + 1))

void eject(void)
{
    if (!grav || (grav && (hblocked[player] | fblocked[player]))) {
        if (coll_D()) {
            high_byte(y) -= eject_D;
            low_byte(y) = 0;
            if (!hblocked[player]) {
                vel_y = 0;
            } else {
                vel_y = grav ? 0xffff : 0;      /* <-- miscompiled */
            }
            orbactive = 0;
            if (fblocked[player]) {
                grav = 0;
                update_idx();
            }
        }
    }
    if (grav || (!grav && (hblocked[player] | fblocked[player]))) {
        if (coll_U()) {
            high_byte(y) -= eject_U;
            low_byte(y) = 0;
            if (!hblocked[player]) {
                vel_y = 0;
            } else {
                vel_y = !grav ? 1 : 0;          /* <-- miscompiled */
            }
            orbactive = 0;
            if (fblocked[player]) {
                grav = 0x80;
                update_idx();
            }
        }
    }
}
