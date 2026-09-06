typedef signed char int8_t;
typedef unsigned char uint8_t;
struct pad {
    union {
        unsigned char hold;
        struct {
        };
        struct {
        };
    };
};
extern struct pad *controllingplayer;
uint8_t tmp4;
uint8_t tmp7;
uint8_t tmp8;
uint8_t currplayer_mini;
uint8_t currplayer_was_on_slope_counter;
uint8_t currplayer_slope_type;
uint8_t gamemode;
uint8_t make_cube_jump_higher;
char a_check_lookup[] = {
};
char bg_coll_slope() {
 static const void * const jumpTable[] = {
 };
  if ((gamemode == 0x06 || gamemode == 0x0A) && !currplayer_mini) {
  }
 if ((uint8_t)(tmp4) >= tmp7) {
   if (gamemode == 0x00 || gamemode == 0x04 || gamemode == 0x08) {
    if (controllingplayer->hold & (0x80 | 0x08)) {
    }
    if (a_check_lookup[tmp4]) {
     if (controllingplayer->hold & (0x80 | 0x08)) {
     }
    }
   }
 }