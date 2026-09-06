-- Why is the level not streaming? Watch the renderer's cursor and the camera.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local SAMPLE = {2,5,10,20,30,60,90,120,180,240,300,400,500,600}
local frames, idx, rows = 0, 1, {}
local function rd(a) return emu.read(a, emu.memType.snesWorkRam) end
local function rd16(a) return rd(a) + rd(a+1)*256 end
local function rd32(a) return rd16(a) + rd16(a+2)*65536 end
local function onFrame()
  frames = frames + 1
  if idx > #SAMPLE or frames ~= SAMPLE[idx] then return end
  idx = idx + 1
  rows[#rows+1] = string.format("frame %4d  rld_column=%5d  scroll_x=%10d  scroll_y=%04X  gameState=%02X  drawing_frame=%3d",
    frames, rd16(A.rld_column), rd32(A.scroll_x), rd16(A.scroll_y), rd(A.gameState), rd(A.drawing_frame))
  if idx > #SAMPLE then
    local f=io.open(OUT.."render_trace.txt","w"); f:write(table.concat(rows,"\n").."\n"); f:close()
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.startFrame)
