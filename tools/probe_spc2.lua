-- Which side of the port handshake is stuck?
--
-- Built on the same shape as tools/probe_exec.lua, which is known to fire its
-- callbacks. An earlier version of this file reported zero hits on EVERY exec
-- callback including ppu_wait_nmi, which cannot be true of a running game - so
-- the numbers it produced about the SPC were worthless too. That is trap 66/104
-- again: a broken harness reads as a broken program.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(0)

local W = emu.memType.snesWorkRam
local ARAM = emu.memType.spcRam
local n = 0
local hits = {}
local names = { "ppu_wait_nmi", "spc_frame_flush", "spc_send" }
for _, nm in ipairs(names) do
  hits[nm] = 0
  emu.addMemoryCallback(function() hits[nm] = hits[nm] + 1 end,
                        emu.callbackType.exec, A.code[nm], A.code[nm])
end

emu.addEventCallback(function()
  if not menu.done() then return end
  for i, v in ipairs({ 0x30 | (2 << 6) | 12, 200, 0, 0x30, 0, 0,
                       0x80, 0, 0, 0xF0, 0 }) do
    emu.write(A.famistudio_output_buf + i - 1, v, W)
  end
end, emu.eventType.startFrame)

emu.addEventCallback(function()
  if not menu.done() then return end
  n = n + 1
  if n < 120 then return end

  local function hex(base, len, mt)
    local t = {}
    for i = 0, len - 1 do t[#t + 1] = string.format("%02X", emu.read(base + i, mt)) end
    return table.concat(t, " ")
  end

  local rows = {}
  for _, nm in ipairs(names) do
    rows[#rows + 1] = string.format("%-16s hits %d", nm, hits[nm])
  end
  rows[#rows + 1] = "spc_alive        = " .. emu.read(A.spc_alive, W, false)
  rows[#rows + 1] = "spc_seq (S-CPU)  = " .. emu.read(A.spc_seq, W, false)
  rows[#rows + 1] = "spc_primed       = " .. emu.read(A.spc_primed, W, false)
  rows[#rows + 1] = "ARAM $00 seq     = " .. hex(0x00, 1, ARAM)
  rows[#rows + 1] = "ARAM $10 fb      = " .. hex(0x10, 12, ARAM)
  local D = emu.memType.spcDspRegisters
  for v = 0, 3 do
    rows[#rows + 1] = string.format(
      "voice %d  VOL %3d %3d  PITCH $%02X%02X  SRCN %d  ADSR1 $%02X GAIN $%02X",
      v, emu.read(v*16+0, D), emu.read(v*16+1, D),
      emu.read(v*16+3, D), emu.read(v*16+2, D),
      emu.read(v*16+4, D), emu.read(v*16+5, D), emu.read(v*16+7, D))
  end
  rows[#rows + 1] = string.format("KON $%02X  KOF $%02X  FLG $%02X  DIR $%02X",
                                  emu.read(0x4C, D), emu.read(0x5C, D),
                                  emu.read(0x6C, D), emu.read(0x5D, D))
  local st2 = emu.getState()
  local e = {}
  for v = 0, 3 do e[#e+1] = tostring(st2[string.format("spc.dsp.voices[%d].envVolume", v)]) end
  rows[#rows + 1] = "envVolume        = " .. table.concat(e, " ")
  rows[#rows + 1] = "SPC pc           = " ..
                    string.format("$%04X", emu.getState()["spc.pc"])

  local f = io.open(OUT .. "spc_probe2.txt", "w")
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  emu.stop(0)
end, emu.eventType.startFrame)
