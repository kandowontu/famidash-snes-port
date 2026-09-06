-- Why does the wave's tilt never reach the clamp?
--
-- verify_ship models cube_rotate as 0x400 - player_vel_y[0] with a clamp above
-- 0x07FF, and the wave and the ship clamp it in opposite directions - so the
-- one case where they differ is only covered if |vel_y| gets past 0x400.
-- wave_movement sets vel_y to +/-currplayer_vel_x (doubled when mini), which
-- should be plenty, and the measured range says otherwise. This prints the
-- inputs that decide it.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)

local WR = emu.memType.snesWorkRam
local START = 240
local LAST = START + 40

local function rd(a) return emu.read(a, WR, false) end
local function u16(a) return rd(a) + 256 * rd(a + 1) end
local function s16(a)
  local v = u16(a); if v >= 0x8000 then v = v - 0x10000 end; return v
end

local frame, rows = 0, {}

emu.addMemoryCallback(function()
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, WR)
  emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, WR)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

emu.addEventCallback(function()
  if not menu.done() then return end
  frame = frame + 1
  if frame < START then return end
  emu.write(A.gamemode, 0x06, WR)          -- WAVE
  emu.write(A.currplayer_mini, 1, WR)

  rows[#rows + 1] = string.format(
    "f%4d vel_y=%+6d vel_x=%+6d speed=%d mini=%d dashing=%02X "
    .. "sframes=%02X onslope=%02X dbl=%02X rot=%04X cp=%d dash=%02X,%02X tmp1=%02X",
    frame, s16(A.currplayer_vel_y), s16(A.currplayer_vel_x), rd(A.speed),
    rd(A.currplayer_mini), rd(A.dashing), rd(A.currplayer_slope_frames),
    rd(A.currplayer_was_on_slope_counter), rd(A.dblocked),
    u16(A.cube_rotate), rd(A.currplayer), rd(A.dashing), rd(A.dashing + 1),
    rd(A.tmp1))

  if frame >= LAST then
    local f = io.open(OUT .. "wave_trace.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
