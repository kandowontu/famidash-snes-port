-- Capture the original NES driver's FamiStudio APU image once per video frame.
-- The addresses come from Mesen's Famidash - Huge Man debugger symbols.
local OUT = "C:/famidash-snes-port/out/nes_music_trace.txt"
local RAM = emu.memType.nesInternalRam
local FS_BUF = 0x0420
local SONG = 0x04B1
local GAME_STATE = 0x049C
local LEVEL = 0x047F
local CURRENT_SONG_BANK = 0x036D
local frames = 0
local rows = {}
local previous

local function rd(address)
  return emu.read(address, RAM, false)
end

local function apu_image()
  local bytes = {}
  for i = 0, 10 do
    bytes[#bytes + 1] = string.format("%02X", rd(FS_BUF + i))
  end
  return table.concat(bytes, " ")
end

local function finish()
  local file = assert(io.open(OUT, "w"))
  file:write(table.concat(rows, "\n"), "\n")
  file:close()
  emu.stop(0)
end

emu.addEventCallback(function()
  frames = frames + 1
  local current = apu_image()
  if current ~= previous or frames <= 10 or frames % 60 == 0 then
    rows[#rows + 1] = string.format(
      "%04d state=%02X level=%02X song=%02X bank=%02X apu=%s",
      frames, rd(GAME_STATE), rd(LEVEL), rd(SONG), rd(CURRENT_SONG_BANK),
      current)
    previous = current
  end
  if frames >= 600 then finish() end
end, emu.eventType.startFrame)
