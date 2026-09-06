-- Per-frame trace of the first N frames of play.
-- Symbol addresses come from out/addrs.lua, regenerated from the linker map by
-- tools/gen_addrs.py on every build. Never hardcode them: adding or removing a
-- single variable reshuffles the whole 'zfar' section.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs.lua")

local NFRAMES = tonumber(os.getenv("TRACE_FRAMES")) or 48
local frames, rows = 0, {}
local function rd(a) return emu.read(a, emu.memType.snesWorkRam) end
local function rd16(a) return rd(a) + rd(a + 1) * 256 end
local function s16(a)
  local v = rd16(a)
  return v >= 0x8000 and v - 0x10000 or v
end

local function onFrame()
  frames = frames + 1
  if frames > NFRAMES then return end
  rows[#rows + 1] = string.format(
    "%3d  %04X %6d  %04X %04X  %3d %3d  %3d  %02X %02X %02X  %3d %3d %3d  %d %d %d",
    frames,
    rd16(A.currplayer_y), s16(A.currplayer_vel_y),
    rd16(A.tmpgravity), rd16(A.tmpfallspeed),
    rd(A.eject_D), rd(A.eject_U), rd(A.collision),
    rd(A.temp_room), rd(A.temp_y), rd(A.temp_x),
    rd(A.Generic + 0), rd(A.Generic + 1), rd(A.Generic + 3),
    rd(A.currplayer_table_idx), rd(A.currplayer_gravity), rd(A.framerate))
  if frames == NFRAMES then
    local f = io.open(OUT .. "fall_trace.txt", "w")
    f:write("frm  ply_y  vel_y  tmpgr tmpfl  ejD ejU  col  rm ty tx  Gx  Gy  Gh  idx gr fr\n")
    f:write(table.concat(rows, "\n") .. "\n")
    f:close()
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.startFrame)
