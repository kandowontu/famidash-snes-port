-- Exercise every NES background colour through the SA-1 CGRAM path.
--
-- The parallax uses backdrop transparency plus Mode 1 palette 4 colour 1. For
-- black-range NES colours the normal darker colour converts to the same SNES
-- RGB word; the SA-1 port must keep BG1 exact while giving BG2 visible ink.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local B = emu.memType.snesSaveRam
local C = emu.memType.snesCgRam
local LEVEL = 0

local function slurp(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read("*a")
  f:close()
  return data
end

local palette_source = slurp(OUT .. "nes_palette.c")
local words_text = assert(palette_source:match(
  "const uint16_t nes_to_cgram%[64%] = {%s*(.-)%s*};"))
local dark_text = assert(palette_source:match(
  "const uint8_t nes_darken%[64%] = {%s*(.-)%s*};"))
local cgram_words, darker = {}, {}
for hex in words_text:gmatch("0x(%x%x%x%x)") do
  cgram_words[#cgram_words + 1] = tonumber(hex, 16)
end
for hex in dark_text:gmatch("0x(%x%x)") do
  darker[#darker + 1] = tonumber(hex, 16)
end
assert(#cgram_words == 64 and #darker == 64)

local function rd(addr)
  return emu.read(addr, B, false)
end

local function wr16(addr, value)
  emu.write(addr, value & 0xFF, B)
  emu.write(addr + 1, (value >> 8) & 0xFF, B)
end

local function cgword(index)
  return emu.read(index * 2, C, false)
       + emu.read(index * 2 + 1, C, false) * 256
end

local entered = false
local menu_frames = 0
local game_frames = 0
local press = false
local color = 0
local settle = 0
local tested = 0
local black_collapses = 0
local contrast_repairs = 0
local failures = {}

emu.addEventCallback(function()
  -- Hold jump after entry so the palette sweep is not interrupted by the
  -- level's normal death/restart path reloading its header colours.
  emu.setInput((press or entered) and { a = true } or {}, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not entered then
    if rd(A.shim_menu_active) ~= 0 then
      menu_frames = menu_frames + 1
      emu.write(A.menu_sel, LEVEL, B)
      press = menu_frames >= 30 and menu_frames <= 45
    else
      press = false
      if menu_frames > 0 and rd(A.gameState) == 2
          and rd(A.level) == LEVEL then
        entered = true
      end
    end
    return
  end

  game_frames = game_frames + 1
  -- Do not let an automated palette test turn into a collision/restart test.
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, B)
  emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, B)
  if game_frames < 30 then return end

  if settle == 0 then
    if color >= 64 then
      local result = table.concat({
        string.format("SA-1 parallax palette colours tested=%d", tested),
        string.format("intentional black collapses preserved=%d",
          black_collapses),
        string.format("non-black collisions repaired=%d", contrast_repairs),
        string.format("failures=%d", #failures),
        failures[1] and ("first failure: " .. failures[1])
          or "BG1 remains exact; black hides BG2 and normal colours retain contrast",
        #failures == 0 and "RESULT: SA-1 PARALLAX EDGE COLOURS OK"
          or "RESULT: SA-1 PARALLAX EDGE COLOURS FAIL",
      }, "\n") .. "\n"
      local f = assert(io.open(OUT .. "sa1_parallax_edges_verify.txt", "w"))
      f:write(result)
      f:close()
      local shot_ok, png = pcall(emu.takeScreenshot)
      if shot_ok and png and #png > 0 then
        f = assert(io.open(OUT .. "sa1_parallax_edges.png", "wb"))
        f:write(png)
        f:close()
      end
      print(result)
      emu.stop(#failures == 0 and 0 or 1)
      return
    end

    local bg = cgram_words[color + 1]
    local ink = cgram_words[darker[color + 1] + 1]
    wr16(A.PAL_BUF, bg)
    wr16(A.PAL_BUF + 2, ink)
    emu.write(A.PAL_UPDATE, 1, B)
    settle = 3
    return
  end

  settle = settle - 1
  if settle ~= 0 then return end

  local bg = cgram_words[color + 1]
  local native_ink = cgram_words[darker[color + 1] + 1]
  local want_bg2 = native_ink
  if native_ink == bg then
    if bg == 0 then
      black_collapses = black_collapses + 1
    else
      contrast_repairs = contrast_repairs + 1
      want_bg2 = 0
    end
  end
  local got_backdrop = cgword(0)
  local got_bg1 = cgword(1)
  local got_opaque = cgword(4)
  local got_bg2 = cgword(65)
  local should_contrast = not (bg == 0 and native_ink == bg)
  if got_backdrop ~= bg or got_bg1 ~= native_ink or got_opaque ~= bg
      or got_bg2 ~= want_bg2
      or (should_contrast and got_bg2 == got_backdrop) then
    failures[#failures + 1] = string.format(
      "$%02X backdrop=%04X/%04X BG1=%04X/%04X opaque=%04X/%04X BG2=%04X/%04X",
      color, got_backdrop, bg, got_bg1, native_ink, got_opaque, bg,
      got_bg2, want_bg2)
  end
  tested = tested + 1
  color = color + 1
end, emu.eventType.startFrame)
