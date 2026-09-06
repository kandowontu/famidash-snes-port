-- Headless screenshot for Mesen2 --testrunner.
-- Runs the ROM for a couple of seconds, captures the frame, exits.
-- emu.log does not reach stdout under --testrunner, so status goes to a file.

local OUT = "C:/famidash-snes-port/out/"
local WAIT_FRAMES = 120

local frames = 0

local function note(msg)
  local f = io.open(OUT .. "mesen_status.txt", "a")
  if f then f:write(msg .. "\n") f:close() end
end

local function onFrame()
  frames = frames + 1
  if frames == WAIT_FRAMES then
    local ok, png = pcall(emu.takeScreenshot)
    if ok and png and #png > 0 then
      local f = io.open(OUT .. "mesen_shot.png", "wb")
      f:write(png)
      f:close()
      note("captured frame " .. frames .. ", png bytes = " .. #png)
    else
      note("screenshot FAILED: " .. tostring(png))
    end
    emu.stop(0)
  end
end

note("--- run start ---")
emu.addEventCallback(onFrame, emu.eventType.startFrame)
