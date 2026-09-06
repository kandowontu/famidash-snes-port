-- Same-frame VRAM dump + screenshot, for isolating streaming bugs from
-- rendering bugs. Rendering the dumped tilemap through the software PPU and
-- comparing to the screenshot tests the PPU; comparing the dumped tilemap to
-- the expected columns tests the streamer.
--
-- Tilemap: VRAM word $6000 -> byte offset $C000, 64x64 entries = 8192 bytes.

local OUT = "C:/famidash-snes-port/out/"
local AT_FRAME = 240
do  -- out/dump_frame.txt overrides, since os.getenv is not available here
  local f = io.open(OUT .. "dump_frame.txt", "r")
  if f then
    AT_FRAME = tonumber(f:read("*l")) or AT_FRAME
    f:close()
  end
end

local frames = 0

local function onFrame()
  frames = frames + 1
  if frames ~= AT_FRAME then return end

  local png = emu.takeScreenshot()
  local p = io.open(OUT .. "dump_shot.png", "wb")
  p:write(png)
  p:close()

  local f = io.open(OUT .. "vram_tilemap.bin", "wb")
  local bytes = {}
  for i = 0, 4095 do
    bytes[#bytes + 1] = string.char(emu.read(0x2000 + i, emu.memType.snesVideoRam))
  end
  f:write(table.concat(bytes))
  f:close()

  local function rd16(a)
    return emu.read(a, emu.memType.snesWorkRam)
         + emu.read(a + 1, emu.memType.snesWorkRam) * 256
  end

  -- Read the PPU's actual scroll rather than inferring it from RAM: the NMI
  -- writes BG1HOFS before advancing scroll_x, so the two differ by a frame.
  -- Mesen flattens the layer array into literal keys named "layers[0]".
  local hofs, vofs = -1, -1
  local ok, st = pcall(emu.getState)
  if ok and st and st.ppu then
    local l = st.ppu["layers[0]"] or (st.ppu.layers and st.ppu.layers[0])
    if l then
      hofs = l.hscroll or -1
      vofs = l.vscroll or -1
    end
  end

  local s = io.open(OUT .. "vram_state.txt", "w")
  s:write(string.format("frame %d\nscroll_x %d\ncols_done %d\nbg1hofs %d\nbg1vofs %d\n",
    frames, rd16(0), rd16(2), hofs, vofs))
  s:close()

  emu.stop(0)
end

emu.addEventCallback(onFrame, emu.eventType.startFrame)
