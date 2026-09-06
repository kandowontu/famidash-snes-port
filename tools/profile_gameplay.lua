-- Frame timeline during REAL gameplay, not during the death animation.
--
-- profile_frame.lua's first window landed inside reset_level's own
-- ppu_wait_nmi loop, where almost nothing runs - which reads as a comfortably
-- fast frame and is meaningless. This keeps the player alive (cube_data bit 0
-- is the death flag) and holds A, then logs the timeline once the run is well
-- into the level.
--
-- Read it as: ppu_wait_nmi returns at about scanline 225 (vblank start). Every
-- later mark in the same video frame is that many scanlines into the game
-- frame. A game frame that does not reach ppu_wait_nmi before scanline 262 has
-- overrun and costs a whole extra video frame.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(0)

local WATCH = {
  "ppu_wait_nmi", "music_update", "everything_else", "sprite_collide",
  "check_spr_objects", "oam_clear", "draw_screen", "draw_sprites",
  "drawplayerone", "oam_meta_spr", "oam_spr", "trail_loop", "put_number",
  -- The runtime level decoder, split out: it replaced a precomputed column
  -- stream and cost 5 points of frame rate, so where the time goes matters.
  "decode_metatile_column", "build_tile_columns", "write_collision_column",
  "queue_vram_column", "rle_next",
}
-- Window chosen from trace_sprites_deep.lua: this is where the run gets its
-- heaviest sprite load, and a light frame profiles nothing interesting.
local FIRST = tonumber(os.getenv("FIRST") or "") or 1450
local LAST = FIRST + 12
local STOP_AT = LAST + 40

-- Gameplay input only AFTER the menu. A is also "select this level", so a
-- script that holds it from frame 1 races the level select - and whichever wins
-- depends on when the menu happens to appear, which a compiler flag can move.
-- That is how every scripted run silently played level 0 (docs/HANDOFF.md
-- trap 114).
emu.addEventCallback(function()
  if not menu.done() then return end
  emu.setInput({ a = true }, 0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
  emu.write(A.cube_data + 1, emu.read(A.cube_data + 1, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frame, marks, counts = 0, {}, {}
for _, name in ipairs(WATCH) do
  local addr = A.code[name]
  if addr then
    emu.addMemoryCallback(function()
      counts[name] = (counts[name] or 0) + 1
      if frame >= FIRST and frame <= LAST then
        -- Flat table with dotted keys (docs/HANDOFF.md trap 32).
        marks[#marks + 1] = string.format("  f%-5d sl%-4d %s",
          frame, emu.getState()["ppu.scanline"], name)
      end
    end, emu.callbackType.exec, addr, addr)
  end
end

local rows = {}
local function onFrame()
  frame = frame + 1
  if frame == LAST + 1 then
    rows[#rows + 1] = "timeline (vblank 225-261; a frame that passes 262 has overrun)"
    for _, m in ipairs(marks) do rows[#rows + 1] = m end
  end
  if frame >= STOP_AT then
    rows[#rows + 1] = ""
    rows[#rows + 1] = string.format("call counts over %d video frames:", frame)
    local names = {}
    for n in pairs(counts) do names[#names + 1] = n end
    table.sort(names, function(a, b) return counts[a] > counts[b] end)
    for _, n in ipairs(names) do
      rows[#rows + 1] = string.format("  %-20s %6d   (%.2f per video frame)",
        n, counts[n], counts[n] / frame)
    end
    local f = io.open(OUT .. "gameplay_profile.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.startFrame)
