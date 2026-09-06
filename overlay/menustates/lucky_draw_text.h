/*
 * Lucky_Draw_Text_Stuff, lifted out of SAUCE/menustates/credits.c.
 *
 * level_loading.h calls this at the end of every level load, but only
 * `#ifdef level_luckydraw` - which lvlset_A does not define and lvlset_HUGE
 * does. Moving to the 168-level set therefore turned it into an undefined
 * symbol, and the rest of credits.c (the credits roll, the menu states) is not
 * ported and should not be dragged in for one function.
 *
 * It is the trigger counter the lucky draw level shows over the level: a count
 * of triggers survived, and the best so far, written straight into the
 * nametable with the LEVEL tileset. Those tiles are not letters - the game has
 * no alphabet (docs/HANDOFF.md trap 86) - so this draws the same tile indices
 * the NES does, which look like text there for the same reason "ATTEMPT" does.
 *
 * Verbatim apart from the two strings, which were file-scope in credits.c.
 */
#ifdef level_luckydraw

static const unsigned char ld_triggerstext[] = "TRIGGERS SURVIVED";
static const unsigned char ld_toptriggerstext[] = "TOP TRIGGERS SURVIVED";

void Lucky_Draw_Text_Stuff(void)
{
    if (level == level_luckydraw
        && (triggers_hit[0] || triggers_hit[1] || triggers_hit[2])) {
        multi_vram_buffer_horz((const char *)ld_triggerstext,
                               sizeof(ld_triggerstext) - 1, NTADR_C(1, 6));
        one_vram_buffer(0xF5 + triggers_hit[2], NTADR_C(20, 6));
        one_vram_buffer(0xF5 + triggers_hit[1], NTADR_C(21, 6));
        one_vram_buffer(0xF5 + triggers_hit[0], NTADR_C(22, 6));
        one_vram_buffer(0xD0, NTADR_C(23, 6));
        one_vram_buffer(0xF5 + 8, NTADR_C(24, 6));
        one_vram_buffer(0xF5 + 0, NTADR_C(25, 6));
        one_vram_buffer(0xF5 + 0, NTADR_C(26, 6));

        if (triggers > top_triggers) top_triggers = triggers;

        multi_vram_buffer_horz((const char *)ld_toptriggerstext,
                               sizeof(ld_toptriggerstext) - 1, NTADR_C(1, 8));

        hexToDec(top_triggers);

        if (hexToDecOutputBuffer[2])
            one_vram_buffer(0xF5 + hexToDecOutputBuffer[2], NTADR_C(23, 8));

        if (hexToDecOutputBuffer[2] | hexToDecOutputBuffer[1])
            one_vram_buffer(0xF5 + hexToDecOutputBuffer[1], NTADR_C(24, 8));

        one_vram_buffer(0xF5 + hexToDecOutputBuffer[0], NTADR_C(25, 8));

        one_vram_buffer(0xD0, NTADR_C(26, 8));
        one_vram_buffer(0xF5 + 8, NTADR_C(27, 8));
        one_vram_buffer(0xF5 + 0, NTADR_C(28, 8));
        one_vram_buffer(0xF5 + 0, NTADR_C(29, 8));

        triggers = 0;
        triggers_hit[0] = 0;
        triggers_hit[1] = 0;
        triggers_hit[2] = 0;
    }
}

#endif
