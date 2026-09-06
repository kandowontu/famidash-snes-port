-- Inspect the exact note-table lookup performed by the 6502 compatibility
-- driver. This is a diagnostic for pitch corruption, not a pass/fail test.
local OUT_DIR = "C:/famidash-snes-port/out/"
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
local A = dofile(OUT_DIR .. "addrs_full.lua")
local W = emu.memType.snesWorkRam
local M = emu.memType.snesMemory
local TEST_LEVEL = tonumber(os.getenv("LEVEL")) or 24
local rows = {}
local hits = 0
local frames = 0

menu.start(TEST_LEVEL)

local function wr(address)
  return emu.read(address, W, false)
end

-- famistudio_get_note_pitch's first note-table load in the mirrored driver.
emu.addMemoryCallback(function()
  if not menu.done() or hits >= 80 then return end
  local state = emu.getState()
  local x = state["cpu.x"] & 0xFF
  local y = state["cpu.y"] & 0xFF
  local db = state["cpu.dbr"] & 0xFF
  local env_addr = wr(0x1E40 + y) + wr(0x1E43 + y) * 0x100
  local env_pos = wr(0x1E46 + y)
  hits = hits + 1
  rows[#rows + 1] = string.format(
    "%03d frame=%04d db=%02X x=%02X y=%02X table=%02X/%02X "
      .. "sum=%02X%02X pitch=%02X%02X fine=%02X slide=%02X:%02X%02X "
      .. "envptr=%04X+%02X bytes=%02X,%02X,%02X",
    hits, frames, db, x, y,
    emu.read(db * 0x10000 + 0x0921 + x, M, false),
    emu.read(db * 0x10000 + 0x0982 + x, M, false),
    wr(0x1ECF), wr(0x1ECE),
    wr(0x1E3A + y), wr(0x1E37 + y), wr(0x1E49 + y),
    wr(0x1E4C + y), wr(0x1E54 + y), wr(0x1E50 + y),
    env_addr, env_pos,
    emu.read(db * 0x10000 + env_addr, M, false),
    emu.read(db * 0x10000 + ((env_addr + env_pos) & 0xFFFF), M, false),
    emu.read(db * 0x10000 + ((env_addr + env_pos + 1) & 0xFFFF), M, false))
end, emu.callbackType.exec, 0xDD016C, 0xDD016C)

local function finish(code)
  local file = assert(io.open(OUT_DIR .. "famistudio_pitch_probe.txt", "w"))
  file:write(table.concat(rows, "\n"), "\n")
  file:close()
  emu.stop(code)
end

emu.addEventCallback(function()
  frames = frames + 1
  if hits >= 80 then finish(0) end
  if frames >= 1500 then finish(1) end
end, emu.eventType.startFrame)
