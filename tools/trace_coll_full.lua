-- Where does the collision chain break in the full ROM?
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local SAMPLE = {30,45,60,90,120,180,300,450,600}
local frames, idx, rows = 0, 1, {}
local function rd(a) return emu.read(a, emu.memType.snesWorkRam) end
local function rd16(a) return rd(a) + rd(a+1)*256 end
local function onFrame()
  frames = frames + 1
  if idx > #SAMPLE or frames ~= SAMPLE[idx] then return end
  idx = idx + 1
  -- how much of the collision window is non-zero?
  local nz = {}
  for pg = 0, 3 do
    local c = 0
    for i = 0, 255 do if rd(A.collMap + pg*256 + i) ~= 0 then c = c + 1 end end
    nz[pg] = c
  end
  rows[#rows+1] = string.format(
    "f%4d ply_y=%04X cur_y=%04X sy=%04X coll=%3d temp_y=%02X room=%02X  collMap nonzero p0=%3d p1=%3d p2=%3d p3=%3d",
    frames, rd16(A.player_y), rd16(A.currplayer_y), rd16(A.scroll_y),
    rd(A.collision), rd(A.temp_y), rd(A.temp_room),
    nz[0], nz[1], nz[2], nz[3])
  if idx > #SAMPLE then
    local f=io.open(OUT.."coll_full.txt","w"); f:write(table.concat(rows,"\n").."\n"); f:close()
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.startFrame)
