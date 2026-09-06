-- Is there an SA-1 in this cartridge, did it start, and do both CPUs see I-RAM?
--
-- The probe ROM (src/sa1_probe.s) has the S-CPU set the SA-1's reset vector,
-- release it from reset, and then increment its own counter forever. The SA-1
-- writes $5A $A1 at I-RAM+0 and increments a counter of its own. So:
--
--   magic wrong   -> the SA-1 never ran, or ran somewhere other than intended
--   sa1 counter stuck, scpu counter moving -> the SA-1 is halted or absent
--   both stuck    -> the ROM did not boot at all; suspect the header
--
-- I-RAM is read through emu.memType.sa1InternalRam, NOT by reading $3000 on the
-- S-CPU bus: Mesen's debug reader does not route the SA-1's mappings for
-- snesMemory, so $3000 there comes back as open-bus garbage even while both
-- processors are using it correctly. That the memory type exists at all is
-- itself part of the result - it means the emulator put an SA-1 in the slot on
-- the strength of the header.
--
--   "C:/mesen2/Mesen.exe" --testrunner out/famidash-sa1.sfc tools/verify_sa1.lua

local OUT = "C:/famidash-snes-port/out/"
local log = {}
local function say(s) log[#log + 1] = s end

local function iram(off)
  return emu.read(off, emu.memType.sa1InternalRam, false)
end

local frames = 0
local first = nil

emu.addEventCallback(function()
  frames = frames + 1

  -- One early sample and one late one. The difference is what shows motion;
  -- a single sample cannot tell a running CPU from a stopped one.
  if frames == 2 then
    first = { sa1 = iram(2), scpu = iram(4) }
    return
  end
  if frames < 30 then return end

  local magic = iram(0) * 256 + iram(1)
  local sa1   = iram(2)
  local scpu  = iram(4)

  say(string.format("frames=%d magic=%04X sa1_ctr=%02X->%02X scpu_ctr=%02X->%02X",
                    frames, magic, first.sa1, sa1, first.scpu, scpu))

  -- The counters are 8-bit and free-running, so "moved" is inequality, not
  -- greater-than: over 28 frames at 10.7MHz they wrap many times.
  local booted  = scpu ~= first.scpu
  local sa1_ran = magic == 0x5AA1
  local sa1_alive = sa1 ~= first.sa1

  say("s-cpu running:   " .. tostring(booted))
  say("sa-1 magic:      " .. tostring(sa1_ran))
  say("sa-1 counting:   " .. tostring(sa1_alive))

  local ok = booted and sa1_ran and sa1_alive
  say("RESULT " .. (ok and "OK - SA-1 boots and shares I-RAM with the S-CPU"
                       or "FAIL - see the three lines above"))

  local f = io.open(OUT .. "sa1_probe.txt", "w")
  f:write(table.concat(log, "\n") .. "\n")
  f:close()
  emu.stop(ok and 0 or 1)
end, emu.eventType.endFrame)
