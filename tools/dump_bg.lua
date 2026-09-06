-- Dump everything needed to re-render BG1 independently, plus the real frame.
--
-- The two halves are taken one frame apart ON PURPOSE, because that is what
-- makes them describe the SAME frame:
--
--   startFrame N   : VRAM and the scroll registers hold what is about to draw
--                    frame N - the game's writes for frame N happen in the
--                    vblank that follows it. takeScreenshot here returns
--                    frame N-1.
--   startFrame N+1 : takeScreenshot returns frame N.
--
-- Reading both at startFrame N compares frame N-1's picture against frame N's
-- state, which is off by exactly one frame of camera movement - and on a
-- scrolling scene that looks like a rendering bug that is not there.
--
-- OBJ is switched off for the captured frame so the diff is about the
-- background only - sprites are verified separately.
--
--   DUMP_FRAME=1500 Mesen.exe --testrunner rom.sfc tools/dump_bg.lua
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local AT = tonumber(os.getenv("DUMP_FRAME") or "") or 1500

emu.addEventCallback(function() emu.setInput({ a = true }, 0) end,
                     emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
  emu.write(A.cube_data + 1, emu.read(A.cube_data + 1, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frames = 0
emu.addEventCallback(function()
  frames = frames + 1

  -- Ask for OBJ off so the diff is about BG1 alone. The game writes TM itself
  -- (ppu_on_all), so this does not always stick - which is why the OAM is
  -- dumped as well and verify_bg.py masks the sprite boxes out regardless.
  if frames >= AT - 2 then
    emu.write(0x212C, 0x01, emu.memType.snesMemory)
  end
  -- The frame after the dump: this screenshot is the frame the state below drew.
  if frames == AT + 1 then
    local ok2, png2 = pcall(emu.takeScreenshot)
    if ok2 and png2 and #png2 > 0 then
      local g = io.open(OUT .. "bg_shot.png", "wb"); g:write(png2); g:close()
    end
    emu.stop(0)
    return
  end
  if frames ~= AT then return end

  local st = emu.getState()
  local function bytes(addr, len, memtype)
    local t = {}
    for i = 0, len - 1 do t[#t + 1] = string.char(emu.read(addr + i, memtype)) end
    return table.concat(t)
  end

  -- BG1 tilemap: 64x64 words = 4096 words = 8KB, at the layer's own base.
  local map_word = st["ppu.layers[0].tilemapAddress"]
  local chr_word = st["ppu.layers[0].chrAddress"]
  local f = io.open(OUT .. "bg_tilemap.bin", "wb")
  f:write(bytes(map_word * 2, 8192, emu.memType.snesVideoRam)); f:close()
  f = io.open(OUT .. "bg_tiles.bin", "wb")
  f:write(bytes(chr_word * 2, 4096, emu.memType.snesVideoRam)); f:close()
  f = io.open(OUT .. "bg_cgram.bin", "wb")
  f:write(bytes(0, 32, emu.memType.snesCgRam)); f:close()
  -- The low OAM table, so the comparison can ignore anything a sprite covers.
  f = io.open(OUT .. "bg_oam.bin", "wb")
  f:write(bytes(0, 512, emu.memType.snesSpriteRam)); f:close()

  f = io.open(OUT .. "bg_dump.txt", "w")
  f:write(string.format(
    "frame %d\nhscroll %d\nvscroll %d\ntilemap_word %d\nchr_word %d\n"
    .. "doubleWidth %s\ndoubleHeight %s\nbgmode %d\nrld_column %d\n",
    frames, st["ppu.layers[0].hscroll"], st["ppu.layers[0].vscroll"],
    map_word, chr_word,
    tostring(st["ppu.layers[0].doubleWidth"]),
    tostring(st["ppu.layers[0].doubleHeight"]),
    st["ppu.bgMode"],
    emu.read(A.rld_column, emu.memType.snesWorkRam)
      + emu.read(A.rld_column + 1, emu.memType.snesWorkRam) * 256))
  f:close()
end, emu.eventType.startFrame)
