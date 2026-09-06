/*
 * arr_macros.h - SNES/65816 port of LIB/headers/arr_macros.h
 *
 * The originals are hand-written 6502 in cc65 inline asm: they exist purely to
 * beat cc65's code generator at indexed array access. None of that survives to
 * 65816, and none of it needs to - every one of them has an exact portable-C
 * equivalent, and a real optimising compiler generates the indexed access
 * itself.
 *
 * Semantics and, critically, *data layout* are preserved exactly:
 *   - 16-bit arrays are little-endian pairs, i.e. a plain uint16_t[]
 *   - lohi_arr*_decl keeps the split byte-plane layout (still a good fit for
 *     65816 8-bit indexed addressing, and famidash.h depends on the names)
 *   - ind16BE_* really is big-endian; that is not a typo in the original
 *
 * Only the macros the game actually uses are ported. Counts measured over
 * SAUCE/: idx8_store 85, idx8_load 50, lohi_arr16_decl 17, idx8_inc 12,
 * idx8_dec 7, ind16BE_load_NOC 4, idx16_load_hi_NOC 3, lohi_arr32_load_to 1.
 * The remainder of the original file is unreferenced and is deliberately not
 * carried over - see docs/M1_PROGRESS.md.
 */

#ifndef ARR_MACROS_H
#define ARR_MACROS_H

#include <stdint.h>

/* --- width clamps ------------------------------------------------------- */
#define byte(x) (((x) & 0xFF))
#define word(x) (((x) & 0xFFFF))

#define LSB(x)  ((byte(x)))
#define MSB(x)  ((byte((x) >> 8)))
#define SB3(x)  ((byte((x##L) >> 16)))
#define SB4(x)  ((byte((x##L) >> 24)))

#define LSW(x)  ((word(x)))
#define MSW(x)  ((word((x##L) >> 16)))

/* --- arithmetic that deliberately does not carry ------------------------ */
#define addNOC_b(a, b) byte(byte(a) + (b))
#define addNOC_w(a, b) word(word(a) + (b))
#define addloNOC(a, b) (addNOC_b(a, b)) | ((a) & 0xFF00)

#define subNOC_b(a, b) byte(byte(a) - (b))
#define subNOC_w(a, b) word(word(a) - (b))
#define subloNOC(a, b) (subNOC_b(a, b)) | ((a) & 0xFF00)

/* --- the "Y register" --------------------------------------------------- */
/*
 * cc65 leaves the index of an indexed access in Y, and the game exploits that:
 * `get_Y` (nesdash.h) re-reads it so a run of stores against the same index
 * does not reload it. 92 of the ~100 uses are one such run in
 * functions/practice_state.h.
 *
 * There is no equivalent register discipline on 65816 under Calypsi, so the
 * index is recorded here instead and `get_Y` reads it back. Every macro that
 * indexes an array goes through shim_idx(), which is what keeps `get_Y`
 * meaning "the index the previous array access used".
 *
 * This does NOT cover the handful of sites that set Y with inline asm rather
 * than with an array macro (menustates/bgmtest*.c compute a table index with
 * `adc #0 \n tay`). Those need porting individually; the shim cannot see them.
 *
 * shim_idx() is a function, not a macro, on purpose. As a macro the assignment
 * landed inside an array subscript, so an expression touching two arrays -
 * `a[shim_idx(i)] = b[shim_idx(j)]` in draw_sprites.h, or `arr(get_Y)` where
 * get_Y is itself shim_last_index - modified and read the same object with no
 * sequence point between: undefined behaviour, and 60 -Wunsequenced warnings
 * loud enough to bury real ones. Function calls are indeterminately sequenced
 * rather than unsequenced, which removes the UB.
 *
 * Where one expression indexes twice, which index is left behind is still
 * unspecified - so do not write `get_Y` immediately after such a line.
 */
extern uint8_t shim_last_index;

static uint8_t shim_idx(uint8_t i)
{
    shim_last_index = i;
    return i;
}

/* --- byte arrays -------------------------------------------------------- */
#define idx8_load(arr, idx)        ((arr)[shim_idx(idx)])
#define idx8_store(arr, idx, val)  ((arr)[shim_idx(idx)] = (uint8_t)(val))
#define idx8_inc(arr, idx)         (++(arr)[shim_idx(idx)])
#define idx8_dec(arr, idx)         (--(arr)[shim_idx(idx)])

/* --- 16-bit arrays, stored little-endian -------------------------------- */
#define idx16_load_lo(arr, idx)     (((const uint8_t *)(arr))[(idx) << 1])
#define idx16_load_hi(arr, idx)     (((const uint8_t *)(arr))[((idx) << 1) + 1])

/* The _NOC variants only promised idx <= 127; that constraint was a 6502
   addressing limit and is irrelevant here, so they alias the general form. */
#define idx16_load_lo_NOC(arr, idx) idx16_load_lo(arr, idx)
#define idx16_load_hi_NOC(arr, idx) idx16_load_hi(arr, idx)

/* --- split byte-plane arrays -------------------------------------------- */
#define lohi_arr16_decl(name, size) \
    uint8_t name##_lo[size];        \
    uint8_t name##_hi[size]

#define lohi_arr32_decl(name, size) \
    uint8_t name##_lo[size];        \
    uint8_t name##_md[size];        \
    uint8_t name##_hi[size];        \
    uint8_t name##_ex[size]

#define lohi_arr16_load(arr, idx) \
    ((uint16_t)(arr##_lo[shim_idx(idx)]) | ((uint16_t)(arr##_hi[shim_last_index]) << 8))

#define lohi_arr16_store(arr, idx, value)                  \
    (arr##_lo[shim_idx(idx)] = (uint8_t)(value),           \
     arr##_hi[shim_last_index] = (uint8_t)((value) >> 8))

#define lohi_arr32_load(arr, idx)                                   \
    ((uint32_t)(arr##_lo[shim_idx(idx)])                            \
     | ((uint32_t)(arr##_md[shim_last_index]) << 8)                 \
     | ((uint32_t)(arr##_hi[shim_last_index]) << 16)                \
     | ((uint32_t)(arr##_ex[shim_last_index]) << 24))

#define lohi_arr32_load_to(arr, idx, target) \
    ((target) = lohi_arr32_load(arr, idx))

/* The original splits `value` into two words to dodge cc65's 32-bit codegen;
   here that distinction does not exist, so it is the plain store. */
#define lohi_arr32_store_from(arr, idx, value) lohi_arr32_store(arr, idx, value)

#define lohi_arr32_store(arr, idx, value)                       \
    (arr##_lo[shim_idx(idx)] = (uint8_t)(value),                \
     arr##_md[shim_last_index] = (uint8_t)((value) >> 8),       \
     arr##_hi[shim_last_index] = (uint8_t)((value) >> 16),      \
     arr##_ex[shim_last_index] = (uint8_t)((value) >> 24))

/* --- indirect loads through a pointer ----------------------------------- */
#define ind16_load_NOC(ptr, idx)                                     \
    ((uint16_t)(((const uint8_t *)(ptr))[(idx) << 1])                \
     | ((uint16_t)(((const uint8_t *)(ptr))[((idx) << 1) + 1]) << 8))

/* Big-endian on purpose: the original loads the high byte first. */
#define ind16BE_load_NOC(ptr, idx)                                          \
    (((uint16_t)(((const uint8_t *)(ptr))[(idx) << 1]) << 8)                \
     | (uint16_t)(((const uint8_t *)(ptr))[((idx) << 1) + 1]))

/* --- byte views of a wider value ---------------------------------------- */
#define low_byte(a)    (*((uint8_t *)&(a)))
#define high_byte(a)   (*((uint8_t *)&(a) + 1))
#define third_byte(a)  (*((uint8_t *)&(a) + 2))
#define fourth_byte(a) (*((uint8_t *)&(a) + 3))

#define low_word(a)    (*((uint16_t *)&(a)))
#define high_word(a)   (*((uint16_t *)&(a) + 1))

#endif /* ARR_MACROS_H */
