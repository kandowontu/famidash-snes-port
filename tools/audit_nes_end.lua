-- Capture the original Huge Man completion animation as a visual/timing oracle.
local OUT = "C:/famidash-snes-port/out/"
local M = emu.memType.nesMemory
local GAME_STATE = 0x049C
local LEVEL = 0x047F
local COINS = 0x0465
local JUMPS = 0x045E
local ATTEMPTS = 0x05B1
local PRACTICE_COUNT = 0x720E

local frame = 0
local entered = false
local done_frames = 0
local press_frames = 0
local gameplay_frames = 0

local function shot(name)
  local ok, png = pcall(emu.takeScreenshot)
  if ok and png then
    local f = assert(io.open(OUT .. name, "wb"))
    f:write(png)
    f:close()
  end
end

emu.addEventCallback(function()
  emu.setInput(press_frames > 0 and { a = true, start = true } or {}, 0)
  if press_frames > 0 then press_frames = press_frames - 1 end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frame = frame + 1
  local state = emu.read(GAME_STATE, M, false)
  -- Dismiss save safety/credits, choose Main Levels, then start Stereo Madness.
  if not entered and frame % 45 == 10 and (state == 0 or state == 1 or state == 5 or state == 6) then
    press_frames = 3
  end
  if not entered and state == 2 then
    gameplay_frames = gameplay_frames + 1
  end
  if not entered and gameplay_frames >= 30 then
    emu.write(LEVEL, 0, M)
    emu.write(COINS, 7, M)
    emu.write(JUMPS, 42, M)
    emu.write(JUMPS + 1, 0, M)
    emu.write(PRACTICE_COUNT, 0, M)
    for i = 0, 6 do emu.write(ATTEMPTS + i, 0, M) end
    emu.write(ATTEMPTS, 7, M)
    emu.write(ATTEMPTS + 1, 2, M)
    emu.write(GAME_STATE, 3, M)
    entered = true
  end
  if entered then
    done_frames = done_frames + 1
    if done_frames == 1 or done_frames % 10 == 0 then
      shot(string.format("nes_end_%03d.png", done_frames))
    end
    if done_frames >= 240 then emu.stop(0) end
  end
end, emu.eventType.endFrame)
