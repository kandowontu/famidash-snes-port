-- What does Mesen expose about the SPC700 and the S-DSP?
--
-- Written before anything depended on it, for the same reason
-- tools/probe_memcb.lua exists: Mesen's Lua names are not the ones you would
-- guess, a wrong one is nil rather than an error, and the arithmetic that
-- follows raises inside the callback where --testrunner swallows it (traps 32,
-- 66, 104). This prints what is actually there.
local OUT = "C:/famidash-snes-port/out/"
local rows = {}

local function note(s) rows[#rows + 1] = s end

note("-- emu.memType entries --")
local names = {}
for k, v in pairs(emu.memType) do names[#names + 1] = string.format("%s=%s", k, tostring(v)) end
table.sort(names)
note(table.concat(names, "  "))

note("")
note("-- emu.cpuType entries --")
names = {}
for k, v in pairs(emu.cpuType) do names[#names + 1] = string.format("%s=%s", k, tostring(v)) end
table.sort(names)
note(table.concat(names, "  "))

emu.addEventCallback(function()
  -- Reading each candidate memory type once, guarded, so a bad one is a
  -- reported message rather than a dead callback.
  note("")
  note("-- reads at frame 60 --")
  for _, n in ipairs({ "spcRam", "spcRom", "spcMemory", "spcDebug", "dspAudioRam" }) do
    local mt = emu.memType[n]
    if mt == nil then
      note(string.format("%-12s  no such memType", n))
    else
      local ok, v = pcall(emu.read, 0, mt, false)
      note(string.format("%-12s  = %s  read[0] -> %s", n, tostring(mt),
                         ok and string.format("$%02X", v) or ("ERROR " .. tostring(v))))
    end
  end

  local ok, st = pcall(emu.getState)
  if ok then
    local keys = {}
    for k in pairs(st) do
      if k:match("^spc") or k:match("^dsp") then keys[#keys + 1] = k end
    end
    table.sort(keys)
    note("")
    note("-- emu.getState() keys matching spc/dsp --")
    note(#keys > 0 and table.concat(keys, "  ") or "(none)")
  else
    note("emu.getState() failed: " .. tostring(st))
  end

  local f = io.open(OUT .. "spc_probe.txt", "w")
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  emu.stop(0)
end, emu.eventType.startFrame)
