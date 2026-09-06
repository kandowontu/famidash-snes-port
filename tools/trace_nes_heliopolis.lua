-- Original-NES visual reference for the Heliopolis palette-flash section.
local OUT = "C:/famidash-snes-port/out/"
local M = emu.memType.nesMemory
local LEVEL = 165
local frame, gameplay = 0, 0
local started = false
local rows = {}

local GAME_STATE = 0x049C
local LEVEL_ID = 0x047F
local DEBUG_MODE = 0x059B
local INVINCIBLE = 0x04A5
local SCROLL_X = 0x04A6

emu.addEventCallback(function()
  if started then
    emu.setInput({ a = true }, 0)
  else
    local phase = frame % 90
    emu.setInput((phase >= 10 and phase < 16)
      and { a = true, start = true } or {}, 0)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frame = frame + 1
  if frame % 60 == 0 then
    rows[#rows + 1] = string.format("frame=%d state=%02X level=%d started=%s",
      frame, emu.read(GAME_STATE, M, false), emu.read(LEVEL_ID, M, false),
      tostring(started))
  end
  if not started and emu.read(GAME_STATE, M, false) == 1 then
    emu.write(LEVEL_ID, LEVEL, M)
    emu.write(GAME_STATE, 2, M)
    started = true
  end
  if started and emu.read(GAME_STATE, M, false) == 2 then
    gameplay = gameplay + 1
    emu.write(DEBUG_MODE, 1, M)
    emu.write(INVINCIBLE, 0xFF, M)
    if gameplay % 60 == 0 then
      local ok, png = pcall(emu.takeScreenshot)
      if ok and png then
        local f = assert(io.open(OUT .. string.format(
          "nes_heliopolis_F%04d_X%05d.png", gameplay,
          emu.read16(SCROLL_X, M, false)), "wb"))
        f:write(png)
        f:close()
      end
    end
  end
  if gameplay >= 900 or frame >= 1800 then
    local f = assert(io.open(OUT .. "nes_heliopolis_trace.txt", "w"))
    f:write(table.concat(rows, "\n") .. "\n")
    f:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)
