-- Capture Ground to Space from the original Huge Man NES ROM as the visual
-- and palette oracle for the SA-1 port.
local OUT = "C:/famidash-snes-port/out/"
local M = emu.memType.nesMemory
local GAME_STATE = 0x049C
local LEVEL = 0x047F
local MENU_SELECTION = 0x0482
local NORMAL_OR_COMM = 0x049E
local NO_PARALLAX = 0x05AC
local SCROLL_X = 0x04A6
local PAL_BUF = 0x01A0
local CUBE_DATA = 0x007B
local TARGET = 52

local total = 0
local game_frames = 0
local rows = {}

local function rd(a)
  return emu.read(a, M, false)
end

emu.addEventCallback(function()
  local state = rd(GAME_STATE)
  local phase = total % 60
  local press = phase >= 15 and phase <= 45
  if state == 6 then
    emu.write(NORMAL_OR_COMM, 1, M)
    emu.write(LEVEL, TARGET, M)
  elseif state ~= 2 then
    emu.write(MENU_SELECTION, 1, M)
  end
  emu.setInput(press and { a = true, start = true } or {}, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  total = total + 1
  if rd(GAME_STATE) ~= 2 or rd(LEVEL) ~= TARGET then
    if total == 3600 then
      local f = assert(io.open(OUT .. "ground_to_space_nes.txt", "w"))
      f:write(string.format("timeout state=%d level=%d\nRESULT: FAIL\n",
                            rd(GAME_STATE), rd(LEVEL)))
      f:close()
      emu.stop(1)
    end
    return
  end

  game_frames = game_frames + 1
  emu.write(CUBE_DATA, rd(CUBE_DATA) & 0xFE, M)
  if game_frames % 60 == 0 then
    local ok, png = pcall(emu.takeScreenshot)
    if ok and png then
      local image = assert(io.open(
        OUT .. string.format("ground_to_space_nes_%03d.png", game_frames),
        "wb"))
      image:write(png)
      image:close()
    end
    rows[#rows + 1] = string.format(
      "frame=%d scroll_x=%d palette=%02X,%02X,%02X",
      game_frames, rd(SCROLL_X) | (rd(SCROLL_X + 1) << 8),
      rd(PAL_BUF), rd(PAL_BUF + 1), rd(PAL_BUF + 4))
  end
  if game_frames == 600 then
    local f = assert(io.open(OUT .. "ground_to_space_nes.txt", "w"))
    f:write(string.format(
      "state=%d level=%d no_parallax=%d\n%s\n"
      .. "RESULT: NES GROUND TO SPACE CAPTURED\n",
      rd(GAME_STATE), rd(LEVEL), rd(NO_PARALLAX),
      table.concat(rows, "\n")))
    f:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
