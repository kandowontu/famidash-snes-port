-- Verify the original two-nametable left/right level-select transition.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local B = emu.memType.snesSaveRam
local input = {}
local title_frames, level_frames = 0, 0

local function rd(a)
  return emu.read(a, B, false)
end

emu.addEventCallback(function()
  emu.setInput(input, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if rd(A.fami_screen) == 1 then
    title_frames = title_frames + 1
    input = (title_frames >= 60 and title_frames <= 80) and { a = true } or {}
  elseif rd(A.fami_screen) == 2 then
    level_frames = level_frames + 1
    input = (level_frames >= 45 and level_frames <= 58)
      and { right = true } or {}
    if level_frames == 75 then
      local state = emu.getState()
      local scroll = state["ppu.layers[0].hscroll"] or -1
      local png = emu.takeScreenshot()
      local image = assert(io.open(OUT .. "sa1_famidash_level_slide.png", "wb"))
      image:write(png)
      image:close()
      local ok = rd(A.level) == 1 and scroll == 256
      local f = assert(io.open(OUT .. "sa1_famidash_level_slide.txt", "w"))
      f:write(string.format("level=%d hscroll=%d\nRESULT: %s\n",
        rd(A.level), scroll, ok and "SA-1 LEVEL SLIDE OK" or "FAIL"))
      f:close()
      emu.stop(ok and 0 or 1)
    end
  end
end, emu.eventType.startFrame)
