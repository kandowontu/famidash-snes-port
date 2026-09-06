-- How many INSTRUCTIONS each routine executes per game frame.
--
-- The scanline timeline (tools/profile_worst.lua) says which routine the frame
-- is lost in; it does not say why that routine is expensive. An exec callback
-- registered over a routine's whole address range fires once per instruction
-- executed inside it, so this counts them - including the library helpers the
-- compiler calls, which is where the answer turned out to be.
--
-- Comparable with the NES: both machines run 262-line frames at 60Hz, so a
-- routine's share of the frame is directly comparable even though the CPUs are
-- not. tools/profile_nes.lua measures the same routine on the NES ROM.
--
-- Ranges come from out/instr_ranges.lua, generated from the linker map, so they
-- cannot go stale against a rebuild (docs/HANDOFF.md trap 5).
--
--   LEVEL=8 "C:/mesen2/Mesen.exe" --testrunner out/famidash-snes-full.sfc \
--           tools/profile_instr.lua
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local RANGES = dofile(OUT .. "instr_ranges.lua")

local WR = emu.memType.snesWorkRam
local START = tonumber(os.getenv("START") or "") or 400
local STOP = tonumber(os.getenv("STOP") or "") or 1400

-- Hold A and keep the player alive: a run that dies profiles the death.
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

local frame, counting = 0, false
local count = {}
for _, r in ipairs(RANGES) do
  count[r.name] = 0
  emu.addMemoryCallback(function()
    if counting then count[r.name] = count[r.name] + 1 end
  end, emu.callbackType.exec, r.lo, r.hi)
end

-- Game frames, not video frames: a dropped frame would otherwise deflate the
-- per-frame figure exactly where the interesting levels are worst.
local gframes = 0
emu.addMemoryCallback(function()
  if counting then gframes = gframes + 1 end
end, emu.callbackType.exec, A.code.ppu_wait_nmi, A.code.ppu_wait_nmi)

emu.addEventCallback(function()
  if not menu.done() then return end
  frame = frame + 1
  if frame == START then counting = true end
  if frame < STOP then return end
  counting = false

  local rows = { string.format("instructions per GAME frame over %d video frames "
                               .. "(%d game frames)", STOP - START, gframes) }
  local names = {}
  for _, r in ipairs(RANGES) do names[#names + 1] = r.name end
  table.sort(names, function(a, b) return count[a] > count[b] end)
  local total = 0
  for _, n in ipairs(names) do total = total + count[n] end
  for _, n in ipairs(names) do
    if count[n] > 0 then
      rows[#rows + 1] = string.format("  %-24s %8.0f  (%4.1f%% of the measured)",
                                      n, count[n] / math.max(gframes, 1),
                                      100 * count[n] / math.max(total, 1))
    end
  end
  local f = io.open(OUT .. "instr_profile.txt", "w")
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  print(table.concat(rows, "\n"))
  emu.stop(0)
end, emu.eventType.startFrame)
