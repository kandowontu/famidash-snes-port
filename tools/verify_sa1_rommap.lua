-- Report the SA-1's view of a 2MB ROM, read off the chip rather than assumed.
--
-- src/sa1_rommap.c probes a list of addresses and stores what it found. Each
-- 32KB block of the image is stamped with its own index at +$4000 (see
-- tools/pack_lorom.py --stamp), so a reply names the part of the ROM that
-- answered. A reply without the $B0 tag is not a block at all - it is open bus
-- or an unmapped hole, and that distinction is the point of the tag.
--
--   "C:/mesen2/Mesen.exe" --testrunner out/famidash-sa1-rommap.sfc tools/verify_sa1_rommap.lua

local OUT = "C:/famidash-snes-port/out/"

local PROBES = {
  0x00C000, 0x08C000, 0x10C000, 0x18C000,
  0x20C000, 0x28C000, 0x30C000, 0x38C000,
  0x80C000, 0x88C000, 0x90C000, 0x98C000,
  0xA0C000, 0xA8C000, 0xB0C000, 0xB8C000,
  0xC04000, 0xC0C000, 0xC44000, 0xC84000, 0xCC4000,
  0xD04000, 0xD44000, 0xD84000, 0xDC4000,
  0xE04000, 0xE84000, 0xF04000, 0xF84000,
}

local frames = 0
local function iram(off)
  return emu.read(0x300 + off, emu.memType.sa1InternalRam, false)
end

emu.addEventCallback(function()
  frames = frames + 1
  if iram(6) ~= 0xC5 and frames < 30 then return end

  local log = {}
  if iram(6) ~= 0xC5 then
    log[#log + 1] = "RESULT FAIL - the probe never finished"
  else
    log[#log + 1] = "SA-1 address    ROM block   file offset"
    local mapped = 0
    for i, addr in ipairs(PROBES) do
      local lo, hi = iram(8 + (i - 1) * 2), iram(9 + (i - 1) * 2)
      local line
      if (hi & 0xF0) == 0xB0 then
        local blk = ((hi & 0x0F) << 8) | lo
        mapped = mapped + 1
        -- The stamp sits at +$4000 inside its block, and the probe read the
        -- stamp, so the address probed corresponds to that file offset.
        line = string.format("$%06X        %4d        $%06X",
                             addr, blk, blk * 0x8000 + 0x4000)
      else
        line = string.format("$%06X        --  unmapped (read %02X %02X)",
                             addr, lo, hi)
      end
      log[#log + 1] = line
    end
    log[#log + 1] = ""
    log[#log + 1] = string.format("RESULT %d of %d probed addresses map to ROM",
                                  mapped, #PROBES)
  end

  local f = io.open(OUT .. "sa1_rommap.txt", "w")
  f:write(table.concat(log, "\n") .. "\n")
  f:close()
  emu.stop(0)
end, emu.eventType.endFrame)
