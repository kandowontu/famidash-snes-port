-- What does the ball do when it is standing on the floor?
--
-- Reported symptom: it bounces instead of rolling. This does not try to judge;
-- it prints the per-frame state so the shape of the motion is visible.
--
--   "C:/mesen2/Mesen.exe" --testrunner out/famidash-snes-full.sfc tools/trace_ball.lua
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)

local WR = emu.memType.snesWorkRam
local START = 220
local LAST  = START + 90

local function rd(a) return emu.read(a, WR, false) end
local function u16(a) return rd(a) + 256 * rd(a + 1) end
local function s16(a)
  local v = u16(a)
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end

local frame, rows = 0, {}

-- Keep the player alive; a death resets the level and the gamemode with it.
emu.addMemoryCallback(function()
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, WR)
  emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, WR)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

-- ball_eject reads Generic.y / eject_D; capture them where they are live.
local pre_vel, pre_y, ej_hit = nil, nil, 0
emu.addMemoryCallback(function()
  pre_vel, pre_y = s16(A.currplayer_vel_y), u16(A.currplayer_y)
end, emu.callbackType.exec, A.code.ball_eject, A.code.ball_eject)

emu.addEventCallback(function()
  if not menu.done() then return end
  frame = frame + 1
  if frame < START then return end
  emu.write(A.gamemode, 0x02, WR)          -- BALL
  if frame < START + 2 then return end
  if frame > LAST then return end

  rows[#rows + 1] = string.format(
    "f%4d  y=%04X vel=%+6d   at ball_eject: y=%04X vel=%+6d  eject_D=%02X "
    .. "eject_U=%02X  Gy=%02X grav=%02X hbl=%02X",
    frame, u16(A.currplayer_y), s16(A.currplayer_vel_y),
    pre_y or 0, pre_vel or 0, rd(A.eject_D), rd(A.eject_U),
    rd(A.Generic + 1), rd(A.currplayer_gravity), rd(A.hblocked))

  if frame == LAST then
    local f = io.open(OUT .. "ball_trace.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
