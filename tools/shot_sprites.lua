-- Screenshot the full ROM somewhere the level actually has objects in it.
--
-- Not a verification (docs/HANDOFF.md trap 1: captures are not
-- frame-deterministic) - just a picture to look at. Holds A and disables death
-- so the run reaches the sprite-dense part of the level; the first object in
-- the stream is at x = 800 and the cube dies on a spike at scroll_x ~185
-- without the cheat.
--
--   SHOT_FRAME=900 Mesen.exe --testrunner rom.sfc tools/shot_sprites.lua
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
-- Gameplay, not the level select. main() opens the menu first now, and a
-- script that does not get past it measures a menu - or, worse, writes no
-- report at all and leaves the PREVIOUS run's file to be read as this one's
-- (docs/HANDOFF.md trap 89).
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local AT = tonumber(os.getenv("SHOT_FRAME") or "") or 800
-- Optional: force a gamemode, so a mode the scripted run never reaches (the
-- ship portal depends on the exact jump trajectory) can still be looked at.
local FORCE_GM = tonumber(os.getenv("SHOT_GAMEMODE") or "")
if FORCE_GM then
  emu.addEventCallback(function()
    emu.write(A.gamemode, FORCE_GM, emu.memType.snesWorkRam)
  end, emu.eventType.startFrame)
  -- Forcing the gamemode also forces its physics, and the player sinks off the
  -- bottom within a few frames - so it has to be parked somewhere visible too.
  -- At drawplayerone's entry, which is where the value is read: poking it at
  -- startFrame is overwritten by the physics first (trap 58's cousin).
  emu.addMemoryCallback(function()
    emu.write(A.player_y + 1, 100, emu.memType.snesWorkRam)
  end, emu.callbackType.exec, A.code.drawplayerone, A.code.drawplayerone)
end

-- Gameplay input only AFTER the menu. A is also "select this level", so a
-- script that holds it from frame 1 races the level select - and whichever wins
-- depends on when the menu happens to appear, which a compiler flag can move.
-- That is how every scripted run silently played level 0 (docs/HANDOFF.md
-- trap 114).
emu.addEventCallback(function()
  if not menu.done() then return end
  emu.setInput({ a = true }, 0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
  emu.write(A.cube_data + 1, emu.read(A.cube_data + 1, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local n = 0
emu.addEventCallback(function()
  n = n + 1
  if n ~= AT then return end
  local ok, png = pcall(emu.takeScreenshot)
  if ok and png and #png > 0 then
    local f = io.open(OUT .. string.format("sprites_%d.png", AT), "wb")
    f:write(png); f:close()
  end
  -- Where to look: the player's OAM entries are written first, so entry 0 is
  -- the top-left of the metasprite. Saves hunting for it in the image.
  local rows = {}
  for s = 0, 15 do
    local y = emu.read(s * 4 + 1, emu.memType.snesSpriteRam)
    if y < 225 then
      rows[#rows + 1] = string.format("oam[%d] x=%d y=%d tile=%d attr=%02X",
        s, emu.read(s * 4, emu.memType.snesSpriteRam), y,
        emu.read(s * 4 + 2, emu.memType.snesSpriteRam)
          + (emu.read(s * 4 + 3, emu.memType.snesSpriteRam) % 2) * 256,
        emu.read(s * 4 + 3, emu.memType.snesSpriteRam))
    end
  end
  rows[#rows + 1] = string.format("gamemode=%d player_x=%d player_y=%d",
    emu.read(A.gamemode, emu.memType.snesWorkRam),
    emu.read(A.player_x + 1, emu.memType.snesWorkRam),
    emu.read(A.player_y + 1, emu.memType.snesWorkRam))
  local f = io.open(OUT .. string.format("sprites_%d.txt", AT), "w")
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  emu.stop(0)
end, emu.eventType.startFrame)
