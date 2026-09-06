-- How much of the sprite cost is the SHIM and how much is the GAME?
--
-- draw_sprites is the biggest per-frame item after sprite_collide, and it is a
-- mix: SAUCE/'s per-slot animation logic, plus the shim's metasprite walker and
-- OAM writer. Optimising the wrong half is wasted work, and "roughly half" was
-- an estimate, not a measurement.
--
-- This counts INSTRUCTIONS EXECUTED inside each function's address range, by
-- hooking the range itself. That is exact and needs no timing assumptions - one
-- 65816 instruction is 4-8 cycles, so the counts are directly comparable. It is
-- far too slow to leave running, hence the tiny window.
--
-- Ranges come from the linker map via gen_addrs.py: a public symbol's range is
-- from it to the next public symbol, which is an upper bound but a tight one
-- for these.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
-- Gameplay, not the level select. main() opens the menu first now, and a
-- script that does not get past it measures a menu - or, worse, writes no
-- report at all and leaves the PREVIOUS run's file to be read as this one's
-- (docs/HANDOFF.md trap 89).
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local FIRST, LAST = 1600, 1610

-- name -> {start, next symbol's start}
local order = {}
for name, addr in pairs(A.code) do order[#order + 1] = { name = name, addr = addr } end
table.sort(order, function(a, b) return a.addr < b.addr end)
local function range(name)
  for i, e in ipairs(order) do
    if e.name == name then
      return e.addr, (order[i + 1] and order[i + 1].addr or e.addr + 0x400) - 1
    end
  end
end

-- sprite_collide's own range excludes its callees, and those are where its cost
-- actually is - so name them too, or the biggest item in a sprite-dense frame
-- is invisible.
local WATCH = { "draw_sprites", "shim_meta_run", "oam_spr", "sprite_collide",
                "sprite_collide_lookup", "sprite_load_special_behavior",
                "check_spr_objects", "trail_loop", "draw_screen",
                "x_movement_coll", "bg_coll_death" }

-- Gameplay input only AFTER the menu. A is also "select this level", so a
-- script that holds it from frame 1 races the level select - and whichever wins
-- depends on when the menu happens to appear, which a compiler flag can move.
-- That is how every scripted run silently played level 0 (docs/HANDOFF.md
-- trap 114).
emu.addEventCallback(function()
  if not menu.done() then return end
  emu.setInput({ a = true }, 0)
end, emu.eventType.inputPolled)
-- STRESS_SLOTS forces N active-sprite slots on, the same way
-- tools/stress_sprites.lua does, so the split can be measured under a load the
-- level itself never reaches.
local STRESS = tonumber(os.getenv("STRESS_SLOTS") or "") or 0
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
  emu.write(A.cube_data + 1, emu.read(A.cube_data + 1, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
  for i = 0, STRESS - 1 do
    emu.write(A.activesprites_active + i, 1, emu.memType.snesWorkRam)
    emu.write(A.activesprites_realx + i, 16 + (i * 14) % 224, emu.memType.snesWorkRam)
    emu.write(A.activesprites_realy + i, 24 + (i * 11) % 160, emu.memType.snesWorkRam)
  end
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frames, counts = 0, {}
for _, name in ipairs(WATCH) do
  local lo, hi = range(name)
  if lo then
    counts[name] = 0
    emu.addMemoryCallback(function()
      if frames >= FIRST and frames <= LAST then
        counts[name] = counts[name] + 1
      end
    end, emu.callbackType.exec, lo, hi)
  end
end

emu.addEventCallback(function()
  frames = frames + 1
  if frames ~= LAST + 1 then return end
  local n = LAST - FIRST + 1
  local rows = { string.format("instructions executed per frame, averaged over %d frames:", n) }
  local names = {}
  for k in pairs(counts) do names[#names + 1] = k end
  table.sort(names, function(a, b) return counts[a] > counts[b] end)
  for _, k in ipairs(names) do
    rows[#rows + 1] = string.format("  %-20s %8.0f", k, counts[k] / n)
  end
  -- draw_sprites' own range excludes the callees, so this is the game's half.
  local shim = (counts.shim_meta_run or 0) + (counts.oam_spr or 0)
  local game = counts.draw_sprites or 0
  rows[#rows + 1] = ""
  rows[#rows + 1] = string.format(
    "sprite drawing: shim (shim_meta_run + oam_spr) %.0f, game (draw_sprites body) %.0f"
    .. "  -> shim is %.0f%%",
    shim / n, game / n, 100 * shim / math.max(shim + game, 1))
  local f = io.open(OUT .. "sprite_split.txt", "w")
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  emu.stop(0)
end, emu.eventType.startFrame)
