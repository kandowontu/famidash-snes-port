-- Diagnose the split audio boot/request path on the complete SA-1 ROM.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local IRAM = emu.memType.sa1InternalRam
local BWRAM = emu.memType.snesSaveRam
local ARAM = emu.memType.spcRam
local frames = 0
local menu_frames = 0
local press = false
local stop_at = tonumber(os.getenv("FRAMES")) or 1200
local test_level = tonumber(os.getenv("LEVEL")) or 1

emu.addEventCallback(function()
  if press then emu.setInput({ a = true }, 0) end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frames = frames + 1
  if emu.read(A.shim_menu_active, BWRAM, false) ~= 0 then
    menu_frames = menu_frames + 1
    emu.write(A.menu_sel, test_level, BWRAM)
    press = menu_frames >= 12 and menu_frames <= 20
  else
    press = false
  end
  if frames < stop_at then return end
  local st = emu.getState()
  local rows = {
    string.format("frames=%d cpu.pc=$%06X sa1.pc=$%06X spc.pc=$%04X",
      frames, st["cpu.pc"] or 0, st["cart.coprocessor.cpu.pc"] or 0,
      st["spc.pc"] or 0),
    string.format("mailbox seq=%02X/%02X screen=%02X/%02X req=%02X ack=%02X",
      emu.read(0x100, IRAM, false), emu.read(0x101, IRAM, false),
      emu.read(0x106, IRAM, false), emu.read(0x107, IRAM, false),
      emu.read(0x108, IRAM, false), emu.read(0x109, IRAM, false)),
    string.format("spc_alive=%02X requested=%02X prepared=%02X aramseq=%02X",
      emu.read(A.spc_alive, BWRAM, false),
      emu.read(A.spc_requested_song, BWRAM, false),
      emu.read(A.spc_prepared_song, BWRAM, false),
      emu.read(0, ARAM, false)),
    string.format("gameState=%02X level=%02X menu_active=%02X",
      emu.read(A.gameState, BWRAM, false), emu.read(A.level, BWRAM, false),
      emu.read(A.shim_menu_active, BWRAM, false)),
  }
  local f = io.open(OUT .. "sa1_audio_boot_probe.txt", "w")
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  emu.stop(0)
end, emu.eventType.endFrame)
