-- Temporary/diagnostic trace for the real FamiStudio -> SPC path.
-- Kept as a useful failure report: it samples the public 11-byte register
-- image and the compatibility island's control/state bytes after level entry.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(0)
local W = emu.memType.snesWorkRam
local ARAM = emu.memType.spcRam
local FS_SPEED, FS_BUF, FS_BANK = 0x1EAB, 0x1EAC, 0x1EE9
local frames, entered, rows = 0, 0, {}
local seen = {}

local function hexbuf(base, n, mem)
  local t = {}
  for i = 0, n - 1 do
    t[#t + 1] = string.format("%02X", emu.read(base + i, mem))
  end
  return table.concat(t, " ")
end

emu.addEventCallback(function()
  frames = frames + 1
  if not menu.done() then
    if frames > 1200 then
      rows[#rows + 1] = "RESULT: FAIL - game never entered"
      local f = io.open(OUT .. "music_probe.txt", "w")
      f:write(table.concat(rows, "\n") .. "\n"); f:close(); emu.stop(1)
    end
    return
  end
  entered = entered + 1
  local buf = hexbuf(FS_BUF, 11, W)
  seen[buf] = true
  if entered <= 12 or entered % 30 == 0 then
    rows[#rows + 1] = string.format(
      "%4d speed=%02X bank=%02X buf=%s aram=%s",
      entered, emu.read(FS_SPEED, W), emu.read(FS_BANK, W), buf,
      hexbuf(0x10, 11, ARAM))
  end
  if entered == 180 then
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    rows[#rows + 1] = string.format("%d distinct register frames", count)
    rows[#rows + 1] = count > 8
      and "RESULT: REAL FAMISTUDIO OUTPUT IS ADVANCING"
       or "RESULT: FAIL - REGISTER IMAGE IS STATIC"
    local f = io.open(OUT .. "music_probe.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(count > 8 and 0 or 1)
  end
end, emu.eventType.startFrame)
