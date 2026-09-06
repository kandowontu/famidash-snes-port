-- Does Calypsi-compiled C run on the SA-1 with its data in BW-RAM?
--
-- src/sa1_ccheck.c computes four checksums whose values are known ahead of
-- time and leaves them in the shared I-RAM block. Each one covers a different
-- thing the port depends on and that the new memory map could break silently:
--
--   BW-RAM zero-init globals  the bulk of the port's 34KB of state
--   BW-RAM initialised globals  cstartup's copy from the ROM image
--   ROM constants               how every level and table is read
--   and the fact that any of it ran at all, which needs a working stack -
--   the SA-1's is in the BW-RAM window, and BW-RAM comes up write-protected
--
-- Checksums, not flags: an untouched BW-RAM array reads back as a constant, so
-- a "did it run" flag would pass on a map that never wrote anything.
--
--   "C:/mesen2/Mesen.exe" --testrunner out/famidash-sa1-c.sfc tools/verify_sa1_c.lua

local OUT = "C:/famidash-snes-port/out/"

-- SHARED in the C, minus I-RAM's $0000 base: $000300 -> offset 0x300.
local BASE = 0x300

-- name, offset, expected. The expected values are arithmetic, computed by hand
-- from the source, not recorded from a previous run - a captured value would
-- happily lock in whatever the first broken map produced.
local CHECKS = {
  { "BW-RAM zeroed globals   ", 0, 2, (3 * (511 * 512 // 2)) % 65536 }, -- 0xFD00
  { "BW-RAM initialised data ", 2, 2, 11+22+33+44+55+66+77+88 },        -- 396
  { "ROM constants           ", 4, 2, 100+200+300+400+500+600+700+800 },-- 3600
  { "finished                ", 6, 1, 0xC5 },
}

local frames = 0

local function iram(off, n)
  local v = 0
  for i = n - 1, 0, -1 do
    v = v * 256 + emu.read(BASE + off + i, emu.memType.sa1InternalRam, false)
  end
  return v
end

emu.addEventCallback(function()
  frames = frames + 1
  -- The whole program is a few hundred thousand cycles; 30 frames is far more
  -- than it needs and short enough that a hang is obvious.
  if iram(6, 1) ~= 0xC5 and frames < 30 then return end

  local log, ok = {}, true
  for _, c in ipairs(CHECKS) do
    local got = iram(c[2], c[3])
    local good = got == c[4]
    ok = ok and good
    log[#log + 1] = string.format("%s got %04X  want %04X  %s",
                                  c[1], got, c[4], good and "ok" or "MISMATCH")
  end
  log[#log + 1] = ""
  log[#log + 1] = "RESULT " .. (ok
    and "OK - Calypsi C runs on the SA-1 with its data in BW-RAM"
    or  "FAIL - see the mismatches above")

  local f = io.open(OUT .. "sa1_c.txt", "w")
  f:write(table.concat(log, "\n") .. "\n")
  f:close()
  emu.stop(ok and 0 or 1)
end, emu.eventType.endFrame)
