-- Which metasprite is enormous?
--
-- meta_spr() walks a stream of (dx, dy, tile, attr) quadruplets until it reads
-- an x offset of $80. A pointer into the wrong place has no terminator where
-- one is expected, so it walks until it happens to find an $80 byte - thousands
-- of sprites, all garbage. That is both the "missingno" look and a frame that
-- takes 50 video frames to finish.
--
-- This counts oam_spr calls between consecutive oam_meta_spr calls and reports
-- the worst, with the sprite type (draw_sprites' `spr_type` is tmp3) and slot
-- that produced it.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
-- Gameplay, not the level select. main() opens the menu first now, and a
-- script that does not get past it measures a menu - or, worse, writes no
-- report at all and leaves the PREVIOUS run's file to be read as this one's
-- (docs/HANDOFF.md trap 89).
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local STOP_AT = 3000

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

local sprites, cur, worst = 0, nil, {}
local function close_current()
  if cur and sprites > 0 then
    local k = string.format("type %02X", cur.type)
    local w = worst[k]
    if not w or sprites > w.n then
      worst[k] = { n = sprites, slot = cur.slot, frame = cur.frame }
    end
  end
end

for _, name in ipairs({ "oam_meta_spr", "oam_meta_spr_disco", "oam_meta_spr_flipped" }) do
  emu.addMemoryCallback(function()
    close_current()
    sprites = 0
    cur = { type = emu.read(A.tmp3, emu.memType.snesWorkRam),
            slot = emu.read(A.index, emu.memType.snesWorkRam),
            frame = 0 }
  end, emu.callbackType.exec, A.code[name], A.code[name])
end
emu.addMemoryCallback(function() sprites = sprites + 1 end,
                      emu.callbackType.exec, A.code.oam_spr, A.code.oam_spr)

local frames = 0
emu.addEventCallback(function()
  frames = frames + 1
  if cur then cur.frame = frames end
  if frames >= STOP_AT then
    close_current()
    local list = {}
    for k, v in pairs(worst) do list[#list + 1] = { k, v } end
    table.sort(list, function(a, b) return a[2].n > b[2].n end)
    local rows = { "largest metasprite seen per sprite type "
                   .. "(sprites emitted in one oam_meta_spr call):" }
    for _, e in ipairs(list) do
      rows[#rows + 1] = string.format("  %-10s %7d sprites   slot %2d, around frame %d%s",
        e[1], e[2].n, e[2].slot, e[2].frame,
        e[2].n > 64 and "   <-- RUNAWAY" or "")
    end
    local f = io.open(OUT .. "metaspr.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
