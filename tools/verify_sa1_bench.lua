-- Time the three benchmark runs in src/sa1_bench.s and report the ratios.
--
-- Each run writes a phase marker to I-RAM on entry and exit; this samples the
-- markers every frame and records the frame number at each transition. Elapsed
-- FRAMES is the unit that matters, because frames are wall-clock and cycles are
-- not comparable between two processors on different clocks. The cycle counts
-- are reported alongside anyway, because their ratio to frames is the effective
-- clock rate of each run - which is how a memory-access penalty shows itself.
--
--   "C:/mesen2/Mesen.exe" --testrunner out/famidash-sa1-bench.sfc tools/verify_sa1_bench.lua

local OUT = "C:/famidash-snes-port/out/"
-- Run A's marker is in WRAM so the same script works on the no-SA-1 baseline
-- cartridge, where I-RAM does not exist.
local RUNS = {
  { name = "A  S-CPU / WRAM $7E        ", ph = 0x10, wram = 0x0300, cpu = "scpu" },
  { name = "B  SA-1  / I-RAM           ", ph = 0x11, cpu = "sa1" },
  { name = "C  SA-1  / BW-RAM          ", ph = 0x12, cpu = "sa1" },
  { name = "D  SA-1  / BW-RAM, code IRAM", ph = 0x13, cpu = "sa1" },
}

local frames = 0
local mark = {}          -- mark[phase byte][value] = {frame, cycles}
local prev = { [0x10] = -1, [0x11] = -1, [0x12] = -1, [0x13] = -1 }

local function marker(ph)
  if ph == 0x10 then
    return emu.read(0x0300, emu.memType.snesWorkRam, false)
  end
  return emu.read(ph, emu.memType.sa1InternalRam, false)
end

local function cycles(which)
  local st = emu.getState()
  if which == "sa1" then return st["cart.coprocessor.cpu.cycleCount"] end
  return st["cpu.cycleCount"]
end

local function report()
  local log = {}
  local function say(s) log[#log + 1] = s end
  say("run                          frames     cycles   eff. MHz   vs run A")

  local base = nil
  for _, r in ipairs(RUNS) do
    local a = mark[r.ph] and mark[r.ph][1]
    local b = mark[r.ph] and mark[r.ph][2]
    if not (a and b) then
      say(string.format("%s  DID NOT COMPLETE", r.name))
    else
      local df = b.frame - a.frame
      local dc = b.cycles - a.cycles
      -- 60.0988 fields a second on NTSC; close enough that the third digit of
      -- the derived clock is meaningful and the fourth is not.
      local mhz = dc / (df / 60.0988) / 1e6
      base = base or df
      say(string.format("%s  %6d  %9d      %5.2f     %5.2fx",
                        r.name, df, dc, mhz, base / df))
    end
  end

  -- The one line the architecture decision rests on.
  local a = mark[0x10] and mark[0x10][2] and mark[0x10][1]
  local c = mark[0x12] and mark[0x12][2] and mark[0x12][1]
  local d = mark[0x13] and mark[0x13][2] and mark[0x13][1]
  if a and c and d then
    local fa = mark[0x10][2].frame - a.frame
    say("")
    say(string.format("RESULT SA-1 %.2fx with code in ROM, %.2fx with code in I-RAM"
                      .. " (data in BW-RAM either way)",
                      fa / (mark[0x12][2].frame - c.frame),
                      fa / (mark[0x13][2].frame - d.frame)))
  else
    say("")
    say("RESULT FAIL - a run did not finish; see the table above")
  end

  local f = io.open(OUT .. "sa1_bench.txt", "w")
  f:write(table.concat(log, "\n") .. "\n")
  f:close()
end

emu.addEventCallback(function()
  frames = frames + 1
  for ph, _ in pairs(prev) do
    local v = marker(ph)
    if v ~= prev[ph] then
      mark[ph] = mark[ph] or {}
      -- First sighting wins. A marker is written once, but the frame sampler
      -- can only see it on the next frame boundary, so re-recording a repeat
      -- would move the timestamp.
      if not mark[ph][v] then
        mark[ph][v] = { frame = frames,
                        cycles = cycles(ph == 0x10 and "scpu" or "sa1") }
      end
      prev[ph] = v
    end
  end

  -- Done when the SA-1 reaches phase 4, or give up rather than hang.
  if (mark[0x13] and mark[0x13][2]) or frames > 2400 then
    report()
    emu.stop(0)
  end
end, emu.eventType.endFrame)
