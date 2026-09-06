-- Capture the port's FamiStudio APU image once per gameplay frame.
local OUT_DIR = "C:/famidash-snes-port/out/"
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
local LAYOUT = dofile(OUT_DIR .. "famistudio_layout.lua")
local A = dofile(OUT_DIR .. "addrs_full.lua")
local TEST_LEVEL = tonumber(os.getenv("LEVEL")) or 0
local OUT = OUT_DIR .. string.format("snes_music_trace_%03d.txt", TEST_LEVEL)
local W = emu.memType.snesWorkRam
local FS_BUF = LAYOUT.dp + LAYOUT.output_offset
local frames, gameframes = 0, 0
local rows = {}
local previous

menu.start(TEST_LEVEL)

local function rd(address)
  return emu.read(address, W, false)
end

local function apu_image()
  local bytes = {}
  for i = 0, 10 do
    bytes[#bytes + 1] = string.format("%02X", rd(FS_BUF + i))
  end
  return table.concat(bytes, " ")
end

local function finish(code)
  local file = assert(io.open(OUT, "w"))
  file:write(table.concat(rows, "\n"), "\n")
  file:close()
  emu.stop(code)
end

emu.addEventCallback(function()
  frames = frames + 1
  if not menu.done() then
    if frames >= 1200 then finish(1) end
    return
  end
  gameframes = gameframes + 1
  local current = apu_image()
  if current ~= previous or gameframes <= 10 or gameframes % 60 == 0 then
    rows[#rows + 1] = string.format(
      "%04d state=%02X level=%02X song=%02X apu=%s",
      gameframes, rd(A.gameState), rd(A.level), rd(A.song), current)
    previous = current
  end
  if gameframes >= 600 then finish(0) end
end, emu.eventType.startFrame)
