/* Link probe: a main() that reaches the real gameplay entry points, so the
 * linker cannot tree-shake the game away and the undefined-symbol list is the
 * true hardware surface still owed by the shim.
 *
 * This is NOT the game loop - it exists only to make the reachability graph
 * honest. shim/src/snes_main.c stays the real entry point.
 */
#include <stdint.h>

void state_game(void);
void state_lvldone(void);
void unrle_first_screen(void);
void reset_level(void);
void init_sprites(void);
void sprite_collide(void);
void draw_sprites(void);
void process_x_scroll(void);
void process_y_scroll(void);
void store_practice_state(void);
void load_practice_state(void);

int main(void)
{
    unrle_first_screen();
    reset_level();
    init_sprites();
    state_game();
    state_lvldone();
    sprite_collide();
    draw_sprites();
    process_x_scroll();
    process_y_scroll();
    store_practice_state();
    load_practice_state();
    return 0;
}
