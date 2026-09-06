-- Sample the player sprite (OAM sprite 0) across frames to show that the
-- ported Famidash physics is actually running: gravity, then a landing.

local OUT = "C:/famidash-snes-port/out/"
local SAMPLES = {1, 2, 3, 4, 6, 8, 10, 15, 20, 30, 60, 120, 240, 300}

local frames = 0
local idx = 1
local rows = {}

local function onFrame()
  frames = frames + 1
  if idx > #SAMPLES or frames ~= SAMPLES[idx] then return end

  -- OAM low table: sprite 0 is X, Y, tile, attr
  local x = emu.read(0, emu.memType.snesSpriteRam)
  local y = emu.read(1, emu.memType.snesSpriteRam)
  rows[#rows + 1] = string.format("%5d %5d %5d", frames, x, y)

  idx = idx + 1
  if idx > #SAMPLES then
    local f = io.open(OUT .. "player_trace.txt", "w")
    f:write("frame sprX sprY\n" .. table.concat(rows, "\n") .. "\n")
    f:close()
    emu.stop(0)
  end
end

emu.addEventCallback(onFrame, emu.eventType.startFrame)
