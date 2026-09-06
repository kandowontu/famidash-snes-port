-- Do exec callbacks fire for these addresses at all? A control for probe_spc2.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(0)
local n, hits = 0, { }
local names = { "ppu_wait_nmi", "spc_frame_flush", "oam_clear", "drawplayerone" }
for _, nm in ipairs(names) do
  hits[nm] = 0
  emu.addMemoryCallback(function() hits[nm] = hits[nm] + 1 end,
                        emu.callbackType.exec, A.code[nm], A.code[nm])
end
emu.addEventCallback(function()
  if not menu.done() then return end
  n = n + 1
  if n < 120 then return end
  local t = {}
  for _, nm in ipairs(names) do
    t[#t + 1] = string.format("%-18s %s  hits %d", nm,
                              string.format("$%06X", A.code[nm]), hits[nm])
  end
  local f = io.open(OUT .. "exec_probe.txt", "w")
  f:write(table.concat(t, "\n") .. "\n"); f:close()
  emu.stop(0)
end, emu.eventType.startFrame)
