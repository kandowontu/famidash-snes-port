-- Who is calling oam_spr hundreds of times in one game frame?
--
-- Reads the JSL return address off the stack at oam_spr's entry and attributes
-- it to the nearest preceding code symbol. The flood shows up as one caller
-- with an enormous count.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
-- Gameplay, not the level select. main() opens the menu first now, and a
-- script that does not get past it measures a menu - or, worse, writes no
-- report at all and leaves the PREVIOUS run's file to be read as this one's
-- (docs/HANDOFF.md trap 89).
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local FIRST, LAST = 2600, 2700

local syms = {}
for name, addr in pairs(A.code) do syms[#syms + 1] = { addr = addr, name = name } end
table.sort(syms, function(a, b) return a.addr < b.addr end)
local function whose(pc)
  local best, off = "?", 0
  for _, s in ipairs(syms) do
    if s.addr <= pc then best, off = s.name, pc - s.addr else break end
  end
  return string.format("%s+%d", best, off)
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

local frames, callers, err = 0, {}, nil
emu.addMemoryCallback(function()
  if frames < FIRST or frames > LAST then return end
  -- --testrunner swallows errors raised inside a callback, so the script just
  -- looks like it did nothing (docs/HANDOFF.md trap 32). Catch them instead.
  local ok, e = pcall(function()
    -- JSL pushed PB:PCH:PCL, so 1,s..3,s is the return address, low byte first.
    local s = emu.getState()["cpu.sp"]   -- "cpu.s" is nil; the key is cpu.sp
    local ret = emu.read(s + 1, emu.memType.snesMemory)
              + emu.read(s + 2, emu.memType.snesMemory) * 0x100
              + emu.read(s + 3, emu.memType.snesMemory) * 0x10000
    local who = string.format("%06X  %s", ret - 4, whose(ret - 4))
    callers[who] = (callers[who] or 0) + 1
  end)
  if not ok then err = e end
end, emu.callbackType.exec, A.code.oam_spr, A.code.oam_spr)

emu.addEventCallback(function()
  frames = frames + 1
  if frames == LAST + 1 then
    local list = {}
    for k, v in pairs(callers) do list[#list + 1] = { k, v } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local rows = { string.format("oam_spr callers over video frames %d-%d:", FIRST, LAST) }
    if err then rows[#rows + 1] = "  callback error: " .. tostring(err) end
    for _, e in ipairs(list) do
      rows[#rows + 1] = string.format("  %-40s %6d", e[1], e[2])
    end
    local f = io.open(OUT .. "oam_callers.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
