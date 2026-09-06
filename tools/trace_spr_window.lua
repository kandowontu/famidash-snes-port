-- Per-frame view of the slot window as the camera crosses a group of objects.
-- Shows scroll_x, the nearest loaded sprite ahead of it, the nearest behind it,
-- and how many slots check_spr_objects marked active - so "the object was
-- retired before it reached the screen" is visible as an event, not inferred.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local SLOTS = 16
local FIRST, LAST = 700, 820

local function wram(addr, n)
  local v = 0
  for i = 0, (n or 1) - 1 do
    v = v + emu.read(addr + i, emu.memType.snesWorkRam) * (256 ^ i)
  end
  return v
end

emu.addEventCallback(function() emu.setInput({ a = true }, 0) end,
                     emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frames, rows = 0, {}
local function onFrame()
  frames = frames + 1
  if frames < FIRST or frames > LAST then
    if frames == LAST + 1 then
      local f = io.open(OUT .. "spr_window.txt", "w")
      f:write(table.concat(rows, "\n") .. "\n"); f:close()
      emu.stop(0)
    end
    return
  end

  local sx = wram(A.scroll_x, 2)
  local ahead, behind, active = 0x7FFFFFFF, -0x7FFFFFFF, 0
  for i = 0, SLOTS - 1 do
    if wram(A.activesprites_type + i) ~= 0xFF then
      local spx = wram(A.activesprites_x_lo + i) + wram(A.activesprites_x_hi + i) * 256
      local dx = spx - sx
      if dx >= 0 then if dx < ahead then ahead = dx end
      else if dx > behind then behind = dx end end
    end
    active = active + wram(A.activesprites_active + i)
  end
  rows[#rows + 1] = string.format("f%-5d scroll_x=%-6d nearest ahead=%-6s nearest behind=%-7s active=%d",
    frames, sx, ahead == 0x7FFFFFFF and "-" or ahead,
    behind == -0x7FFFFFFF and "-" or behind, active)
end
emu.addEventCallback(onFrame, emu.eventType.startFrame)
