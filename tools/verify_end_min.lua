-- Minimal completion-state smoke test. It deliberately avoids execution and
-- I/O-port callbacks so the debugger cannot perturb the SPC handshake.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(0)

local W = emu.memType.snesWorkRam
local frames, game_frames, end_frames = 0, 0, 0

emu.addEventCallback(function()
  if end_frames >= 45 and end_frames < 50 then
    emu.setInput({ a = true }, 0)
  else
    emu.setInput({}, 0)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frames = frames + 1
  if not menu.done() then return end
  game_frames = game_frames + 1

  if game_frames == 180 then
    emu.write(A.gameState, 3, W)
  end
  if emu.read(A.gameState, W, false) == 3 then
    end_frames = end_frames + 1
  end

  if end_frames >= 45 and emu.read(A.gameState, W, false) == 2 then
    local f = assert(io.open(OUT .. "end_min_verify.txt", "w"))
    f:write(string.format(
      "RESULT: END MIN OK frames=%d end=%d state=%d\n",
      frames, end_frames, emu.read(A.gameState, W, false)))
    f:close()
    emu.stop(0)
  elseif frames >= 900 then
    local f = assert(io.open(OUT .. "end_min_verify.txt", "w"))
    f:write(string.format(
      "RESULT FAIL frames=%d end=%d state=%d\n",
      frames, end_frames, emu.read(A.gameState, W, false)))
    f:close()
    emu.stop(1)
  end
end, emu.eventType.startFrame)
