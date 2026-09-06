-- Temporary visual reference capture for the original NES build.
local OUT = "C:/famidash-snes-port/out/"
local frame = 0

emu.addEventCallback(function()
  local phase = frame % 90
  if phase >= 10 and phase < 16 then
    emu.setInput({ a = true, start = true }, 0)
  else
    emu.setInput({}, 0)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frame = frame + 1
  if frame % 120 == 0 then
    local ok, png = pcall(emu.takeScreenshot)
    if ok and png then
      local f = assert(io.open(
        OUT .. string.format("nes_reference_%04d.png", frame), "wb"))
      f:write(png)
      f:close()
    end
  end
  if frame >= 1800 then emu.stop(0) end
end, emu.eventType.startFrame)
