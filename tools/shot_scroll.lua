-- Headless multi-frame capture for the scrolling ROM (Mesen2 --testrunner).
--
-- Captures several frames spread across the level and records the ROM's own
-- scroll_x / cols_done alongside each, so the comparison is self-calibrating
-- rather than depending on predicting NMI timing.
--
-- Zero page (from out/scroll.map): scroll_x $0000, cols_done $0002.

local OUT = "C:/famidash-snes-port/out/"
local SHOT_FRAMES = {60, 240, 600, 1200, 2400, 3600}

local frames = 0
local idx = 1
local manifest = {}

local function note(msg)
  local f = io.open(OUT .. "mesen_status.txt", "a")
  if f then f:write(msg .. "\n") f:close() end
end

local function read16(addr)
  return emu.read(addr, emu.memType.snesWorkRam)
       + emu.read(addr + 1, emu.memType.snesWorkRam) * 256
end

local function finish()
  local m = io.open(OUT .. "scroll_manifest.txt", "w")
  m:write(table.concat(manifest, "\n") .. "\n")
  m:close()
  note("done, " .. #manifest .. " captures")
  emu.stop(0)
end

local function onFrame()
  frames = frames + 1
  if idx > #SHOT_FRAMES then return end
  if frames ~= SHOT_FRAMES[idx] then return end

  local ok, png = pcall(emu.takeScreenshot)
  if not ok or not png or #png == 0 then
    note("screenshot FAILED at frame " .. frames)
    emu.stop(1)
    return
  end

  local name = string.format("scroll_%d.png", idx)
  local f = io.open(OUT .. name, "wb")
  f:write(png)
  f:close()

  local sx, cd = read16(0x0000), read16(0x0002)
  manifest[#manifest + 1] = string.format("%s %d %d %d", name, frames, sx, cd)
  note(string.format("frame %d: scroll_x=%d cols_done=%d", frames, sx, cd))

  idx = idx + 1
  if idx > #SHOT_FRAMES then finish() end
end

note("--- scroll run start ---")
emu.addEventCallback(onFrame, emu.eventType.startFrame)
