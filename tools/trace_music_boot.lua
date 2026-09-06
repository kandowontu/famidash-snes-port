-- Trace the first real FamiStudio calls even if the CPU wedges before another
-- video frame.  This is intentionally append-and-flush at each entry.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(0)
local W = emu.memType.snesWorkRam
local f = io.open(OUT .. "music_boot_trace.txt", "w")
f:write("trace loaded\n")
f:flush()

local function rd(a) return emu.read(a, W, false) end
local function log(tag)
  local s = emu.getState()
  f:write(string.format(
    "%-18s pc=%02X:%04X a=%s x=%s y=%s s=%s d=%s db=%s "
      .. "src=%02X bank=%02X ptr=%02X%02X arg=%02X/%02X speed=%02X\n",
    tag, s["cpu.k"], s["cpu.pc"], tostring(s["cpu.a"]),
    tostring(s["cpu.x"]), tostring(s["cpu.y"]), tostring(s["cpu.sp"]),
    tostring(s["cpu.d"]), tostring(s["cpu.db"]),
    rd(0x1EE8), rd(0x1EE9), rd(0x1EEB), rd(0x1EEA),
    rd(0x1EEC), rd(0x1EED), rd(0x1EAB)))
  f:flush()
end

local points = {
  {"C music_play", A.code.music_play},
  {"native init", 0xDD0B00},
  {"6502 init", 0xDD0000},
  {"native sfx init", 0xDD0BA0},
  {"6502 sfx init", 0xDD0816},
  {"native play", 0xDD0B24},
  {"6502 play", 0xDD00BA},
  {"native update", 0xDD0B82},
  {"6502 update", 0xDD01D1},
}
for _, p in ipairs(points) do
  emu.addMemoryCallback(function() log(p[1]) end,
                        emu.callbackType.exec, p[2], p[2])
end

local frames = 0
emu.addEventCallback(function()
  frames = frames + 1
  if frames % 30 == 0 then log("frame " .. frames) end
  if frames == 1200 then f:close(); emu.stop(0) end
end, emu.eventType.startFrame)
