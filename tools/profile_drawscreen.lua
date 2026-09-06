-- How long does draw_screen take, and how often?
--
-- The level decoder is the one part of the frame whose cost is not roughly
-- constant: it does nothing on the frames the camera has not moved a whole tile,
-- and a burst on the ones it has. An average is therefore useless - what decides
-- whether a frame drops is the size of the burst - so this reports the
-- distribution, and how much of the total frame budget the worst ones take.
--
-- draw_screen and build/decode are static and get inlined into it, so the only
-- thing that can be hooked is draw_screen itself and the call that follows it
-- (draw_sprites). The gap between them IS draw_screen.
--
--   "C:/mesen2/Mesen.exe" --testrunner out/famidash-snes-full.sfc tools/profile_drawscreen.lua
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)

local STOP_AT = 3000

-- Hold A and keep the player alive, the same way profile_gameplay.lua does: a
-- run that dies profiles the death animation.
-- Gameplay input only AFTER the menu. A is also "select this level", so a
-- script that holds it from frame 1 races the level select - and whichever wins
-- depends on when the menu happens to appear, which a compiler flag can move.
-- That is how every scripted run silently played level 0 (docs/HANDOFF.md
-- trap 114).
emu.addEventCallback(function()
  if not menu.done() then return end
  emu.setInput({ a = true }, 0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
  emu.write(A.cube_data + 1, emu.read(A.cube_data + 1, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frame, enter, hist, calls, busy, worst = 0, nil, {}, 0, 0, 0

emu.addMemoryCallback(function()
  enter = emu.getState()["ppu.scanline"]
end, emu.callbackType.exec, A.code.draw_screen, A.code.draw_screen)

emu.addMemoryCallback(function()
  if not enter then return end
  local d = emu.getState()["ppu.scanline"] - enter
  enter = nil
  if d < 0 then d = d + 262 end               -- wrapped into the next field
  calls = calls + 1
  if d > 2 then
    busy = busy + 1
    if d > worst then worst = d end
    local b = math.floor(d / 10) * 10
    hist[b] = (hist[b] or 0) + 1
  end
end, emu.callbackType.exec, A.code.draw_sprites, A.code.draw_sprites)

emu.addEventCallback(function()
  frame = frame + 1
  if frame < STOP_AT then return end
  local rows = {
    string.format("%d draw_screen calls, %d of them streamed a column (%.0f%%)",
                  calls, busy, 100 * busy / math.max(calls, 1)),
    string.format("worst single call: %d scanlines (%.0f%% of a 262-line frame)",
                  worst, 100 * worst / 262),
    "",
    "scanlines per streaming call:",
  }
  local keys = {}
  for k in pairs(hist) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    rows[#rows + 1] = string.format("  %3d-%3d  %5d  %s", k, k + 9, hist[k],
                                    string.rep("#", math.floor(hist[k] / 8)))
  end
  local f = io.open(OUT .. "drawscreen_profile.txt", "w")
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  print(table.concat(rows, "\n"))
  emu.stop(0)
end, emu.eventType.startFrame)
