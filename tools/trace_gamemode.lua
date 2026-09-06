-- Where does the gamemode change, and what does the player draw there?
--
-- Stereo Madness has a ship section. drawplayerone picks its sprite table from
-- gamemode, so "the ship portal fires but the player stays a cube" is visible
-- as gamemode changing while the OBJ tile numbers stay in the cube's range.
--
-- The icon bank is OBJ tiles 256-319, so cube frames live there; SHIP's tile
-- bytes index the same bank, so the check is the tile NUMBERS against what the
-- metasprite tables say, not the range.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local STOP_AT = 3000

emu.addEventCallback(function() emu.setInput({ a = true }, 0) end,
                     emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
  emu.write(A.cube_data + 1, emu.read(A.cube_data + 1, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frames, rows, prev = 0, {}, nil
emu.addEventCallback(function()
  frames = frames + 1
  local gm = emu.read(A.gamemode, emu.memType.snesWorkRam)
  local tiles = {}
  for s = 0, 3 do
    tiles[#tiles + 1] = emu.read(s * 4 + 2, emu.memType.snesSpriteRam)
                      + (emu.read(s * 4 + 3, emu.memType.snesSpriteRam) % 2) * 256
  end
  if gm ~= prev then
    rows[#rows + 1] = string.format(
      "frame %5d  gamemode %d -> %d   scroll_x=%d   player OBJ tiles %s",
      frames, prev or -1, gm,
      emu.read(A.scroll_x, emu.memType.snesWorkRam)
        + emu.read(A.scroll_x + 1, emu.memType.snesWorkRam) * 256,
      table.concat(tiles, ","))
    prev = gm
  end
  if frames >= STOP_AT then
    -- Also record the tiles a little after the switch, once the new mode has
    -- had frames to settle.
    rows[#rows + 1] = string.format("at frame %d: gamemode %d, player OBJ tiles %s",
      frames, gm, table.concat(tiles, ","))
    local f = io.open(OUT .. "gamemode_trace.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
