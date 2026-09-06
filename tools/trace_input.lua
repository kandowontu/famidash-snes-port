-- Does injected input reach the game? Traces the SNES auto-joypad registers,
-- the shim's decoded pad struct, and the game's jump counter.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs.lua")

local PRESS_FROM, PRESS_TO = 100, 112
local LAST = 130
local frames, rows = 0, {}

local function rd(a) return emu.read(a, emu.memType.snesWorkRam) end
local function reg(a) return emu.read(a, emu.memType.snesMemory) end

local function onInput()
  if frames >= PRESS_FROM and frames <= PRESS_TO then
    emu.setInput(0, { b = true, a = true, up = true })
  end
end

local function onFrame()
  frames = frames + 1
  if frames < PRESS_FROM - 3 or frames > LAST then return end
  local gi = emu.getInput(0)
  rows[#rows + 1] = string.format(
    "%4d  lua_b=%-5s lua_a=%-5s  JOY1H=%02X JOY1L=%02X  hold=%02X press=%02X  jumps=%d vel=%d",
    frames, tostring(gi and gi.b), tostring(gi and gi.a),
    reg(0x4219), reg(0x4218),
    rd(A.joypad1), rd(A.joypad1 + 1),
    rd(A.jumps), rd(A.currplayer_vel_y) + rd(A.currplayer_vel_y + 1) * 256)
  if frames == LAST then
    local f = io.open(OUT .. "input_trace.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n")
    f:close()
    emu.stop(0)
  end
end

emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.startFrame)
