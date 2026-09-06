-- INSTRUCTIONS per sprite_collide call, bucketed by active sprite slots.
--
-- The companion to the scanline version. Scanlines say the port is 1.4x the NES
-- fixed and 3x marginal; they do not say whether that is because the port
-- EXECUTES MORE INSTRUCTIONS (code generation) or because its instructions are
-- SLOWER (24-bit addressing into bank $7E rather than the NES's absolute and
-- zero-page modes). Those want completely different fixes, so measure which.
--
-- Bucketed by active slots because sprite_collide's cost is mostly marginal:
-- comparing a busy SNES level with whatever level the NES happened to be on
-- produced a confident ratio that meant nothing (docs/HANDOFF.md trap 106).
--
--   LEVEL=8 "C:/mesen2/Mesen.exe" --testrunner out/famidash-snes-full.sfc \
--           tools/profile_collide.lua
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local R = dofile(OUT .. "instr_ranges.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)

local WR = emu.memType.snesWorkRam
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
  emu.write(A.cube_data, emu.read(A.cube_data, WR) & 0xFE, WR)
  emu.write(A.cube_data + 1, emu.read(A.cube_data + 1, WR) & 0xFE, WR)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local lo, hi
for _, r in ipairs(R) do
  if r.name == "sprite_collide" then lo, hi = r.lo, r.hi end
end
if not lo then
  print("sprite_collide not in out/instr_ranges.lua - regenerate it")
  emu.stop(1)
  return
end

local cur, buckets, n = 0, {}, 0
-- One callback over the whole range counts instructions; a second on the entry
-- address alone resets the counter, so `cur` is per CALL.
emu.addMemoryCallback(function() cur = cur + 1 end, emu.callbackType.exec, lo, hi)
emu.addMemoryCallback(function() cur = 0 end, emu.callbackType.exec, lo, lo)

-- check_spr_objects is the next routine in the frame, so it is where the count
-- for the call that just finished is complete.
emu.addMemoryCallback(function()
  if n < 300 or cur == 0 then cur = 0; return end
  local act = 0
  for i = 0, 15 do
    if emu.read(A.activesprites_active + i, WR, false) ~= 0 then act = act + 1 end
  end
  local b = buckets[act] or { n = 0, total = 0 }
  b.n = b.n + 1; b.total = b.total + cur
  buckets[act] = b
  cur = 0
end, emu.callbackType.exec, A.code.check_spr_objects, A.code.check_spr_objects)

emu.addEventCallback(function()
  if not menu.done() then return end
  n = n + 1
  if n < 2000 then return end
  local keys = {}
  for k in pairs(buckets) do keys[#keys + 1] = k end
  table.sort(keys)
  print("SNES sprite_collide, INSTRUCTIONS per call, by active sprite slots:")
  local first, last
  for _, k in ipairs(keys) do
    local b = buckets[k]
    if b.n > 20 then
      print(string.format("  %2d active: %5d calls, mean %.0f instructions",
                          k, b.n, b.total / b.n))
      first = first or { k, b.total / b.n }
      last = { k, b.total / b.n }
    end
  end
  if first and last and last[1] > first[1] then
    print(string.format("  marginal: %.1f instructions per active sprite",
                        (last[2] - first[2]) / (last[1] - first[1])))
  end
  emu.stop(0)
end, emu.eventType.startFrame)
