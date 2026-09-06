/* Calypsi 65816 5.18 codegen bug: a `register` local that is live across a
 * switch whose default path is an empty `break` is read back from an
 * uninitialised stack slot instead of from the register holding it.
 *
 *   cc65816 --code-model large --data-model large -O 1 -c regvar_switch.c \
 *           -o regvar_switch.o --assembly-source regvar_switch.s
 *
 * In the emitted code `a` is kept in Y (`tay` after the negate, `tya` at the
 * head of each non-empty case). The join point after the switch emits
 *      lda 1,s
 *      clc
 *      adc long:accum
 * but nothing ever stores Y into 1,s, so `accum` accumulates whatever the
 * caller happened to leave in Y. Reproduces at -O 1 and -O 2.
 */
#include <stdint.h>

int16_t accum;
int16_t base;
uint8_t mode;
uint8_t flip;

void step(void)
{
    register int16_t a;

    a = base;
    if (flip)
        a = -a;
    switch (mode) {
        case 0: break;
        case 1: a /= 3; break;
        case 2: a /= 2; break;
        case 3: a = (a / 3 * 2); break;
        case 4: a *= 2; break;
    }
    accum += a;
}
