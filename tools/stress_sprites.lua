-- How much sprite load can the frame actually take?
--
-- Stereo Madness peaks at 38 OAM entries, and "it holds 60Hz there" says
-- nothing about a denser level. This forces every one of the 16 active-sprite
-- slots on, every frame, at positions spread across the screen - so
-- draw_sprites walks all of them and the metasprite walker does the maximum
-- work the engine can ask of it - and reports where the frame rate breaks.
--
-- The slots are filled with types taken from the level's own stream, so the
-- metasprites are real ones of realistic size rather than something invented.
--
--   STRESS_SLOTS=16 Mesen.exe --testrunner rom.sfc tools/stress_sprites.lua
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
-- Gameplay, not the level select. main() opens the menu first now, and a
-- script that does not get past it measures a menu - or, worse, writes no
-- report at all and leaves the PREVIOUS run's file to be read as this one's
-- (docs/HANDOFF.md trap 89).
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local SLOTS = tonumber(os.getenv("STRESS_SLOTS") or "") or 16
local WARMUP, STOP_AT = 400, 1600

-- Gameplay input only AFTER the menu. A is also "select this level", so a
-- script that holds it from frame 1 races the level select - and whichever wins
-- depends on when the menu happens to appear, which a compiler flag can move.
-- That is how every scripted run silently played level 0 (docs/HANDOFF.md
-- trap 114).
emu.addEventCallback(function()
  if not menu.done() then return end
  emu.setInput({ a = true }, 0)
end, emu.eventType.inputPolled)

-- Force the slots on at the top of the draw phase, after check_spr_objects has
-- had its say - otherwise it culls them straight back off.
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
  for i = 0, SLOTS - 1 do
    emu.write(A.activesprites_active + i, 1, emu.memType.snesWorkRam)
    -- Spread them out so nothing is dropped for leaving the 256-pixel space.
    emu.write(A.activesprites_realx + i, 16 + (i * 14) % 224, emu.memType.snesWorkRam)
    emu.write(A.activesprites_realy + i, 24 + (i * 11) % 160, emu.memType.snesWorkRam)
  end
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local gameframes = 0
emu.addMemoryCallback(function() gameframes = gameframes + 1 end,
                      emu.callbackType.exec, A.code.everything_else,
                      A.code.everything_else)

local frames, base_gf, peak = 0, nil, 0
emu.addEventCallback(function()
  frames = frames + 1
  if frames < WARMUP then return end
  if frames == WARMUP then base_gf = gameframes; return end

  local live = 0
  for s = 0, 127 do
    if emu.read(s * 4 + 1, emu.memType.snesSpriteRam) < 225 then live = live + 1 end
  end
  if live > peak then peak = live end

  if frames >= STOP_AT then
    local n = frames - WARMUP
    local pct = 100 * (gameframes - base_gf) / n
    local rows = {
      string.format("%d slots forced active, %d video frames", SLOTS, n),
      string.format("peak OAM entries live: %d (= %d NES sprites)", peak, peak // 2),
      string.format("%d game frames -> %.1f%% of 60Hz", gameframes - base_gf, pct),
    }
    local f = io.open(OUT .. "sprite_stress.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
