-- Drive the player far enough into the level that the level sprites actually
-- come on screen, then measure what the sprite engine costs.
--
-- Without this the run is useless as a sprite test: the cube dies on the first
-- spike at scroll_x ~185, and the first object in the stream is at x = 800.
--
-- Two cheats, both deliberate and both only in this script:
--   * bit 0 of cube_data is the death flag; clearing it at the top of the draw
--     phase (oam_clear, which runs just before state_game's death check) keeps
--     the run going through spikes.
--   * A is held, so the cube jumps whenever it is grounded.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
-- Gameplay, not the level select. main() opens the menu first now, and a
-- script that does not get past it measures a menu - or, worse, writes no
-- report at all and leaves the PREVIOUS run's file to be read as this one's
-- (docs/HANDOFF.md trap 89).
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local SLOTS = 16
local SAMPLE_EVERY = 120
local STOP_AT = 1800

local function wram(addr, n)
  local v = 0
  for i = 0, (n or 1) - 1 do
    v = v + emu.read(addr + i, emu.memType.snesWorkRam) * (256 ^ i)
  end
  return v
end

-- emu.setInput takes (table, port) - the opposite order from emu.getInput(port)
-- - and only takes effect from inputPolled (docs/HANDOFF.md trap 6).
emu.addEventCallback(function()
  emu.setInput({ a = true }, 0)
end, emu.eventType.inputPolled)

emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
  emu.write(A.cube_data + 1, emu.read(A.cube_data + 1, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

-- Game frames per video frame: everything_else runs exactly once per game frame.
local gameframes = 0
emu.addMemoryCallback(function() gameframes = gameframes + 1 end,
                      emu.callbackType.exec, A.code.everything_else,
                      A.code.everything_else)

local frames, rows = 0, {}
local last_gf, last_vf = 0, 0

local function onFrame()
  frames = frames + 1
  if frames % SAMPLE_EVERY ~= 0 then return end

  local live, tiles, maxy = 0, {}, 0
  for s = 0, 127 do
    local y = emu.read(s * 4 + 1, emu.memType.snesSpriteRam)
    if y < 225 then
      live = live + 1
      local t = emu.read(s * 4 + 2, emu.memType.snesSpriteRam)
      local at = emu.read(s * 4 + 3, emu.memType.snesSpriteRam)
      local tile = t + (at % 2) * 256
      tiles[tile] = (tiles[tile] or 0) + 1
    end
  end
  local tlist = {}
  for t, n in pairs(tiles) do tlist[#tlist + 1] = string.format("%d x%d", t, n) end
  table.sort(tlist, function(a, b)
    return tonumber(a:match("^%d+")) < tonumber(b:match("^%d+")) end)

  local act = {}
  for i = 0, SLOTS - 1 do
    act[#act + 1] = string.format("%02X/%d@%d",
      wram(A.activesprites_type + i), wram(A.activesprites_active + i),
      wram(A.activesprites_realx + i))
  end

  local gf, vf = gameframes - last_gf, frames - last_vf
  last_gf, last_vf = gameframes, frames
  rows[#rows + 1] = string.format(
    "frame %5d  scroll_x=%-6d rld=%-5d OAM live=%-4d  %d game frames / %d video (%.0f%% speed)",
    frames, wram(A.scroll_x, 3), wram(A.rld_column, 2), live, gf, vf, 100 * gf / vf)
  rows[#rows + 1] = "    slots: " .. table.concat(act, " ")
  rows[#rows + 1] = "    OBJ tiles: " .. table.concat(tlist, ", ")

  if frames >= STOP_AT then
    local f = io.open(OUT .. "sprite_deep.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.startFrame)
