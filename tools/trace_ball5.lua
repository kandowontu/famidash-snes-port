-- Where does the ball's floor eject put it, and why is that not the floor?
--
-- With x frozen (see trace_ball4) the ball falls ~2.5px, gets ejected, and
-- falls again - a 14-frame bounce instead of the every-frame rest the source
-- comments describe. This records the numbers the eject is computed FROM:
-- Generic.y/height, the world temp_y the check landed on, and tmp8/eject_D.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)

local WR = emu.memType.snesWorkRam
local START = 240
local LAST  = START + 34

local function rd(a) return emu.read(a, WR, false) end
local function u16(a) return rd(a) + 256 * rd(a + 1) end
local function u32(a) return u16(a) + 65536 * u16(a + 2) end
local function s16(a)
  local v = u16(a); if v >= 0x8000 then v = v - 0x10000 end; return v
end
local function wr16(a, v)
  emu.write(a, v & 0xFF, WR); emu.write(a + 1, (v >> 8) & 0xFF, WR)
end

local frame, rows, armed = 0, {}, false
local froze_x, froze_scroll

emu.addMemoryCallback(function()
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, WR)
  emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, WR)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

emu.addMemoryCallback(function()
  if not armed then return end
  rows[#rows + 1] = string.format(
    "    bg_coll_D  y=%04X Gy=%02X Gh=%02X Gw=%02X mini=%d",
    u16(A.currplayer_y), rd(A.Generic + 1), rd(A.Generic + 3), rd(A.Generic + 2),
    rd(A.currplayer_mini))
end, emu.callbackType.exec, A.code.bg_coll_D, A.code.bg_coll_D)

-- bg_coll_return_D is the ONLY writer of eject_D, so its exit state is what the
-- eject actually uses. Entry is close enough: tmp8 is set by the checks it
-- calls, so read it on the way back out via the next thing that runs - here,
-- simply sample after the frame as well.
emu.addMemoryCallback(function()
  if not armed then return end
  rows[#rows + 1] = string.format(
    "    return_D   temp_y=%04X room=%02X tmp8=%02X eject_D=%02X",
    u16(A.temp_y), rd(A.temp_room), rd(A.tmp8), rd(A.eject_D))
end, emu.callbackType.exec, A.code.bg_coll_return_D, A.code.bg_coll_return_D)

emu.addEventCallback(function()
  if not menu.done() then return end
  frame = frame + 1
  if frame < START then return end
  emu.write(A.gamemode, 0x02, WR)
  if not froze_x then
    froze_x, froze_scroll = u16(A.currplayer_x), u32(A.scroll_x)
  end
  wr16(A.currplayer_x, froze_x)
  wr16(A.scroll_x, froze_scroll & 0xFFFF)
  wr16(A.scroll_x + 2, (froze_scroll >> 16) & 0xFFFF)
  armed = true

  rows[#rows + 1] = string.format(
    "f%4d y=%04X vel=%+6d ejD=%02X scroll_y=%04X",
    frame, u16(A.currplayer_y), s16(A.currplayer_vel_y), rd(A.eject_D),
    u16(A.scroll_y))

  if frame >= LAST then
    local f = io.open(OUT .. "ball_trace5.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
