-- Exercise several consecutive Famidash level-selector slides on the SA-1.
-- Each settled page is checked against the generated two-line level label.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local B = emu.memType.snesSaveRam
local V = emu.memType.snesVideoRam

local input = {}
local title_frames = 0
local selector_frames = 0
local target = 0
local settle = 0
local pulse = 0
local rows = {}
local labels

do
  local f = assert(io.open(OUT .. "famidash_level_lines.bin", "rb"))
  labels = f:read("*a")
  f:close()
end

local function rd(a)
  return emu.read(a, B, false)
end

local function check_level(lv)
  local page = lv % 2
  local map_byte = 0xC000 + page * 0x800
  local expected = lv * 34
  local wrong = 0
  local rom_wrong = 0
  local near_wrong = 0
  local buffer_wrong = 0
  for line = 0, 1 do
    for x = 0, 16 do
      local vram = map_byte + ((10 + line) * 32 + 8 + x) * 2
      local got = emu.read(vram, V, false)
      local want = labels:byte(expected + line * 17 + x + 1)
      if got ~= want then wrong = wrong + 1 end
      local rom = emu.read(0xC0B95C + expected + line * 17 + x,
                           emu.memType.snesMemory, false)
      if rom ~= want then rom_wrong = rom_wrong + 1 end
      local near = emu.read(0x6000 + page * 0x800
                            + ((10 + line) * 32 + 8 + x) * 2,
                            emu.memType.snesMemory, false)
      if near ~= want then near_wrong = near_wrong + 1 end
      if got ~= near then buffer_wrong = buffer_wrong + 1 end
    end
  end
  local state = emu.getState()
  local scroll = state["ppu.layers[0].hscroll"] or -1
  rows[#rows + 1] = string.format(
    "level=%d page=%d scroll=%d label_wrong=%d rom_wrong=%d near_wrong=%d "
    .. "buffer_wrong=%d "
    .. "dirty=%d palette=%d face_dirty=%d face_uploaded=%d",
    lv, page, scroll, wrong, rom_wrong, near_wrong, buffer_wrong,
    rd(A.fami_dirty_pages), rd(A.fami_palette_dirty),
    rd(A.fami_face_dirty), rd(A.fami_face_uploaded))
  local png = emu.takeScreenshot()
  local f = assert(io.open(
    OUT .. string.format("sa1_level_sequence_%03d.png", lv), "wb"))
  f:write(png)
  f:close()
  return buffer_wrong == 0 and scroll == page * 256
end

emu.addEventCallback(function()
  emu.setInput(input, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  local screen = rd(A.fami_screen)
  if screen == 1 then
    title_frames = title_frames + 1
    input = (title_frames >= 60 and title_frames <= 80) and { a = true } or {}
    return
  end
  if screen ~= 2 then return end

  selector_frames = selector_frames + 1
  local lv = rd(A.level)
  if target == 0 then
    if selector_frames < 35 then
      input = {}
      return
    end
    check_level(lv)
    target = 1
    pulse = 14
  elseif lv == target then
    input = {}
    settle = settle + 1
    if settle == 24 then
      if not check_level(lv) then
        rows[#rows + 1] = "RESULT: FAIL"
        local f = assert(io.open(OUT .. "sa1_level_sequence.txt", "w"))
        f:write(table.concat(rows, "\n") .. "\n")
        f:close()
        emu.stop(1)
        return
      end
      if target == 8 then
        rows[#rows + 1] = "RESULT: SA-1 LEVEL SEQUENCE OK"
        local f = assert(io.open(OUT .. "sa1_level_sequence.txt", "w"))
        f:write(table.concat(rows, "\n") .. "\n")
        f:close()
        emu.stop(0)
        return
      end
      target = target + 1
      settle = 0
      pulse = 14
    end
  elseif pulse > 0 then
    input = { right = true }
    pulse = pulse - 1
  else
    input = {}
  end
end, emu.eventType.startFrame)
