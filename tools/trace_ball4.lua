-- Does the ball come to rest on flat ground?
--
-- The earlier traces let the ball keep travelling, so the terrain under it
-- changed every frame and "it never rests" could equally have been "it is
-- running over slopes". This FREEZES the horizontal state - currplayer_x and
-- scroll_x are restored at the top of every frame - so the ball sits over one
-- column of the level and the vertical motion is the only thing moving.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)

local WR = emu.memType.snesWorkRam
local START = tonumber(os.getenv("BALLSTART")) or 240
local LAST  = START + 60

local function rd(a) return emu.read(a, WR, false) end
local function u16(a) return rd(a) + 256 * rd(a + 1) end
local function u32(a) return u16(a) + 65536 * u16(a + 2) end
local function s16(a)
  local v = u16(a); if v >= 0x8000 then v = v - 0x10000 end; return v
end
local function wr16(a, v)
  emu.write(a, v & 0xFF, WR); emu.write(a + 1, (v >> 8) & 0xFF, WR)
end

local frame, rows = 0, {}
local froze_x, froze_scroll

emu.addMemoryCallback(function()
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, WR)
  emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, WR)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

emu.addEventCallback(function()
  if not menu.done() then return end
  frame = frame + 1
  if frame < START then return end
  emu.write(A.gamemode, 0x02, WR)                       -- BALL

  if not froze_x then
    froze_x, froze_scroll = u16(A.currplayer_x), u32(A.scroll_x)
  end
  -- The ball uses the TARGET-driven camera (process_y_scroll's else arm), and
  -- target_scroll_y is only ever set by reset_level and by a gamemode portal.
  -- Forcing the gamemode without a portal leaves it at the spawn value, so the
  -- camera code drags the player 2px a frame forever - an artifact of the
  -- harness, not the game. Keep them equal so the fall is the only motion.
  -- PINTARGET=1 removes the harness artifact for a clean physics reading; the
  -- default leaves target_scroll_y where the game put it, which is what
  -- exercises cap_scroll_y_at_top/bottom.
  if os.getenv("PINTARGET") then wr16(A.target_scroll_y, u16(A.scroll_y)) end
  wr16(A.currplayer_x, froze_x)
  wr16(A.scroll_x, froze_scroll & 0xFFFF)
  wr16(A.scroll_x + 2, (froze_scroll >> 16) & 0xFFFF)

  rows[#rows + 1] = string.format(
    "f%4d y=%04X vel=%+6d  ejD=%02X ejU=%02X slope=%02X onslope=%02X "
    .. "sframes=%02X dbl=%02X tgt=%04X sy=%04X",
    frame, u16(A.currplayer_y), s16(A.currplayer_vel_y),
    rd(A.eject_D), rd(A.eject_U), rd(A.currplayer_slope_type),
    rd(A.currplayer_was_on_slope_counter), rd(A.currplayer_slope_frames),
    rd(A.dblocked), u16(A.target_scroll_y), u16(A.scroll_y))

  if frame >= LAST then
    local f = io.open(OUT .. "ball_trace4.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
