-- Why is activesprites_active almost always 0?
--
-- Recomputes check_spr_objects' own two tests from WRAM, per slot, so the
-- answer is "the X test rejected it" or "the Y test rejected it" rather than a
-- guess. Same cheats as trace_sprites_deep.lua: death off, A held.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
-- Gameplay, not the level select. main() opens the menu first now, and a
-- script that does not get past it measures a menu - or, worse, writes no
-- report at all and leaves the PREVIOUS run's file to be read as this one's
-- (docs/HANDOFF.md trap 89).
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local SLOTS = 16
local SAMPLE_AT = { 300, 900, 1500 }

local function wram(addr, n)
  local v = 0
  for i = 0, (n or 1) - 1 do
    v = v + emu.read(addr + i, emu.memType.snesWorkRam) * (256 ^ i)
  end
  return v
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
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frames, idx, rows = 0, 1, {}
local function onFrame()
  frames = frames + 1
  if idx > #SAMPLE_AT or frames ~= SAMPLE_AT[idx] then return end
  idx = idx + 1

  local sx = wram(A.scroll_x, 2)
  local sy = wram(A.scroll_y, 2)
  local realScrollY = (sy >> 8) * 240 + (sy & 0xFF)

  rows[#rows + 1] = string.format(
    "frame %d  scroll_x=%d  scroll_y=$%04X -> realScrollY=%d  animating=%d",
    frames, sx, sy, realScrollY, wram(A.animating))
  for i = 0, SLOTS - 1 do
    local ty = wram(A.activesprites_type + i)
    local spx = wram(A.activesprites_x_lo + i) + wram(A.activesprites_x_hi + i) * 256
    local spy = wram(A.activesprites_y_lo + i) + wram(A.activesprites_y_hi + i) * 256
    local dx = (spx - sx) & 0xFFFF
    local dy = (spy - realScrollY - 1) & 0xFFFF
    local why = "ON"
    if ty == 0xFF then why = "empty"
    elseif dx >= 0x8000 then why = "behind"
    elseif dx > 0xFF then why = "right"
    elseif dy > 0xFF then why = "Y-cull" end
    rows[#rows + 1] = string.format(
      "  slot %2d type %02X  spx=%-6d spy=%-6d dx=%-6d dy=%-6d active=%d  %s",
      i, ty, spx, spy, dx > 0x7FFF and dx - 0x10000 or dx,
      dy > 0x7FFF and dy - 0x10000 or dy, wram(A.activesprites_active + i), why)
  end

  if idx > #SAMPLE_AT then
    local f = io.open(OUT .. "spr_cull.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.startFrame)
