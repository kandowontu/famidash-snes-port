-- Screenshot the full ROM once the level has streamed in.
-- Not a verification (docs/HANDOFF.md trap 1: captures are not
-- frame-deterministic) - just a picture to look at. verify_render.lua is the
-- actual check. emu.takeScreenshot returns the PNG bytes.
local OUT = "C:/famidash-snes-port/out/"
local AT = tonumber(os.getenv("SHOT_FRAME") or "") or 140
local n = 0
local function onFrame()
  n = n + 1
  if n ~= AT then return end
  local ok, png = pcall(emu.takeScreenshot)
  if ok and png and #png > 0 then
    local f = io.open(OUT .. "full_shot.png", "wb"); f:write(png); f:close()
  end
  emu.stop(0)
end
emu.addEventCallback(onFrame, emu.eventType.startFrame)
