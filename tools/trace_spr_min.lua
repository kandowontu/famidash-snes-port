-- Does any loaded sprite EVER get within 256px of scroll_x?
--
-- Sampling a few frames cannot answer that. This walks all 16 slots every
-- frame and keeps the smallest non-negative dx seen, plus a histogram of how
-- many slots were active. If the minimum never drops below 256, sprites are
-- being retired before they reach the screen and the fault is in the x origin,
-- not in the cull.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local SLOTS, STOP_AT = 16, 2000

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

local frames, min_dx, hist, best = 0, 0x7FFFFFFF, {}, nil
local function onFrame()
  frames = frames + 1
  local sx = wram(A.scroll_x, 2)
  local active, fmin = 0, 0x7FFFFFFF
  for i = 0, SLOTS - 1 do
    local ty = wram(A.activesprites_type + i)
    if ty ~= 0xFF then
      local spx = wram(A.activesprites_x_lo + i) + wram(A.activesprites_x_hi + i) * 256
      local dx = spx - sx
      if dx >= 0 and dx < fmin then fmin = dx end
    end
    active = active + wram(A.activesprites_active + i)
  end
  hist[active] = (hist[active] or 0) + 1
  if fmin < min_dx then min_dx = fmin; best = {frames, sx} end

  if frames >= STOP_AT then
    local rows = {
      string.format("%d frames, scroll_x reached %d", frames, sx),
      string.format("smallest non-negative dx over the whole run: %d (frame %d, scroll_x %d)",
                    min_dx, best[1], best[2]),
      "active-slot count histogram:",
    }
    for n = 0, SLOTS do
      if hist[n] then
        rows[#rows + 1] = string.format("  %2d active: %5d frames", n, hist[n])
      end
    end
    local f = io.open(OUT .. "spr_min.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.startFrame)
