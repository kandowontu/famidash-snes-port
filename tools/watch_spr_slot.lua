-- Who retires a sprite one frame after it comes on screen?
--
-- The slot window trace showed a sprite reaching dx=254 (on screen) and being
-- replaced on the very next frame. check_spr_objects only refills a slot whose
-- sprite is BEHIND the camera, so something else is writing the table. This
-- puts a write watch on activesprites_type and logs the PC of every writer.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local FIRST, LAST = 780, 830

-- PC -> nearest preceding code symbol, so the log names a function.
local syms = {}
for name, addr in pairs(A.code) do syms[#syms + 1] = { addr = addr, name = name } end
table.sort(syms, function(a, b) return a.addr < b.addr end)
local function whose(pc)
  local best = "?"
  for _, s in ipairs(syms) do
    if s.addr <= pc then best = string.format("%s+%d", s.name, pc - s.addr) else break end
  end
  return best
end

emu.addEventCallback(function() emu.setInput({ a = true }, 0) end,
                     emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frames, rows = 0, {}
local writers = {}

emu.addMemoryCallback(function(address, value)
  if frames < FIRST or frames > LAST then return end
  local slot = address - (0x7E0000 + A.activesprites_type)
  local pc = emu.getState()["cpu.pc"] + emu.getState()["cpu.k"] * 0x10000
  local who = whose(pc)
  writers[who] = (writers[who] or 0) + 1
  if #rows < 200 then
    rows[#rows + 1] = string.format("f%-5d type[%2d] <- %02X   by %s", frames, slot, value, who)
  end
end, emu.callbackType.write, 0x7E0000 + A.activesprites_type,
     0x7E0000 + A.activesprites_type + 15, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  frames = frames + 1
  if frames == LAST + 1 then
    rows[#rows + 1] = ""
    rows[#rows + 1] = "writers:"
    for k, v in pairs(writers) do rows[#rows + 1] = string.format("  %-30s %d", k, v) end
    local f = io.open(OUT .. "spr_writers.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
