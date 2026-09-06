-- A checksum of OAM per GAME frame, for comparing two builds of the sprite
-- writer.
--
-- Keyed on the number of ppu_wait_nmi calls, not on video frames: the whole
-- point of the change under test is that frames take a different amount of
-- time, so a video-frame index would compare two different moments in the run
-- and disagree for the wrong reason.
--
-- The run is forced (A held, death disabled) so both builds see identical
-- input. Same game frame, same game state, same sprites - so the same OAM
-- bytes, whatever wrote them.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
-- Gameplay, not the level select. main() opens the menu first now, and a
-- script that does not get past it measures a menu - or, worse, writes no
-- report at all and leaves the PREVIOUS run's file to be read as this one's
-- (docs/HANDOFF.md trap 89).
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local SAMPLE_AT = { 100, 200, 400, 600, 800, 1000, 1200 }

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
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local gameframe, idx, rows = 0, 1, {}

emu.addMemoryCallback(function()
  gameframe = gameframe + 1
  if idx > #SAMPLE_AT or gameframe ~= SAMPLE_AT[idx] then return end
  idx = idx + 1

  -- OAM has not been flushed for this frame yet at ppu_wait_nmi entry, so this
  -- is the shadow buffer's state as the drawing code left it last frame.
  local sum, live, tiles = 0, 0, {}
  for s = 0, 127 do
    local x = emu.read(s * 4 + 0, emu.memType.snesSpriteRam)
    local y = emu.read(s * 4 + 1, emu.memType.snesSpriteRam)
    local t = emu.read(s * 4 + 2, emu.memType.snesSpriteRam)
    local a = emu.read(s * 4 + 3, emu.memType.snesSpriteRam)
    -- Order-sensitive rolling sum: two builds that write the same bytes in a
    -- different order are NOT equivalent here, and should not be.
    sum = (sum * 31 + x * 7 + y * 5 + t * 3 + a) % 0xFFFFFFF
    if y < 225 then
      live = live + 1
      tiles[#tiles + 1] = t + (a % 2) * 256
    end
  end
  rows[#rows + 1] = string.format("gameframe %5d  live=%-4d oam_sum=%08X  first tiles: %s",
    gameframe, live, sum, table.concat(tiles, ",", 1, math.min(#tiles, 12)))

  if idx > #SAMPLE_AT then
    local f = io.open(OUT .. "oam_verify.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end, emu.callbackType.exec, A.code.ppu_wait_nmi, A.code.ppu_wait_nmi)
