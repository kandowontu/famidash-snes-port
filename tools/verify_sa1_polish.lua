-- SA-1 counterpart to verify_polish.lua. The SA-1 runs gameplay from BW-RAM
-- and Mesen does not expose its execution callbacks, so this drives the menu
-- through the S-CPU pad mailbox and verifies shared PPU/VRAM state by frame.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local BG = dofile(OUT .. "bg_level_expect.lua")
local LEVEL = tonumber(os.getenv("LEVEL")) or 0

local B = emu.memType.snesSaveRam
local V = emu.memType.snesVideoRam
local n, menu_frames, game_frames = 0, 0, 0
local entered, press = false, false
local samples, saw_seen = {}, {}
local bg_phase_seen = {}
local bg_phase_checks, bg_phase_mismatch, bg_phase_changes = 0, 0, 0
local last_bg_phase
local palette_pairs, raw_pairs = {}, {}
local palette_flips, last_palette = 0, nil
local early_pairs, early_flips, early_last = {}, 0, nil
local palette_tail = {}

local function rd(addr, width)
  local value = 0
  for i = 0, (width or 1) - 1 do
    value = value + emu.read(addr + i, B, false) * (256 ^ i)
  end
  return value
end

local function slurp(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read("*a")
  f:close()
  return data
end

local function match_vram(byte_addr, expected)
  local wrong = 0
  for i = 1, #expected do
    if emu.read(byte_addr + i - 1, V, false) ~= expected:byte(i) then
      wrong = wrong + 1
    end
  end
  return wrong
end

local function bg1_word(col, row)
  local word = 0x6000
             + ((col >> 5) & 1) * 0x400
             + ((row >> 5) & 1) * 0x800
             + (row & 31) * 32 + (col & 31)
  return emu.read(word * 2, V, false)
       + emu.read(word * 2 + 1, V, false) * 256
end

emu.addEventCallback(function()
  if press or entered then
    emu.setInput({ a = true }, 0)
  else
    emu.setInput({}, 0)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  n = n + 1
  if not entered then
    if rd(A.shim_menu_active) ~= 0 then
      menu_frames = menu_frames + 1
      emu.write(A.menu_sel, LEVEL, B)
      press = menu_frames >= 30 and menu_frames <= 45
    else
      press = false
      if menu_frames > 0 and rd(A.gameState) == 2 and rd(A.level) == LEVEL then
        entered = true
      end
    end
  else
    game_frames = game_frames + 1
    local bg_chr = emu.getState()["ppu.layers[0].chrAddress"]
    bg_phase_seen[bg_chr] = true
    if game_frames > 30 then
      bg_phase_checks = bg_phase_checks + 1
    -- Compare two pieces of state committed by the same vblank operation.
    -- parallax_scroll_x can already contain the following gameplay frame.
    local visible_phase = rd(A.shim_saw_bank) == 15 and 0x1000 or 0
    if bg_chr ~= visible_phase then
      bg_phase_mismatch = bg_phase_mismatch + 1
    end
      if last_bg_phase and bg_chr ~= last_bg_phase then
        bg_phase_changes = bg_phase_changes + 1
      end
      last_bg_phase = bg_chr
    end
    -- Keep the scripted run alive without relying on SA-1 exec callbacks.
    emu.write(A.cube_data, rd(A.cube_data) & 0xFE, B)
    do
      local words = {}
      for color = 0, 15 do
        words[#words + 1] = string.format("%04X",
          emu.read(color * 2, emu.memType.snesCgRam, false)
          + emu.read(color * 2 + 1, emu.memType.snesCgRam, false) * 256)
      end
      local palette = table.concat(words, "/")
      local raw = string.format("%02X/%02X",
        rd(A.PAL_BUF_RAW), rd(A.PAL_BUF_RAW + 1))
      palette_pairs[palette], raw_pairs[raw] = true, true
      if last_palette and palette ~= last_palette then palette_flips = palette_flips + 1 end
      last_palette = palette
      if game_frames <= 180 then
        early_pairs[palette] = true
        if early_last and palette ~= early_last then early_flips = early_flips + 1 end
        early_last = palette
      end
      palette_tail[#palette_tail + 1] = string.format(
        "%d:%s:%s", game_frames, palette, raw)
      if #palette_tail > 8 then table.remove(palette_tail, 1) end
    end
    if game_frames % 30 == 0 then
      local st = emu.getState()
      samples[#samples + 1] = {
        st["ppu.layers[0].hscroll"], st["ppu.layers[1].hscroll"]
      }
      saw_seen[rd(A.shim_saw_bank)] = true
    end
  end

  if not entered and n >= 1200 then
    local f = assert(io.open(OUT .. "sa1_polish_verify.txt", "w"))
    f:write("RESULT FAIL - never entered SA-1 gameplay\n")
    f:close()
    emu.stop(1)
    return
  end
  if game_frames < 600 then return end

  local st = emu.getState()
  local par_tiles_wrong =
    match_vram(0x5000 * 2, slurp(OUT .. "parallax.tiles.bin"))
  local par_map_wrong =
    match_vram(0x4000 * 2, slurp(OUT .. "parallax.map.bin"))
  local saw_bank = rd(A.shim_saw_bank)
  local saw_word = saw_bank == 15 and 0x1C00 or 0x0C00
  local saw_wrong = match_vram(
    saw_word * 2, slurp(OUT .. (saw_bank == 15 and "saw1.bin" or "saw0.bin")))
  local bg_set = BG.tileset[LEVEL + 1]
  local bg_even_wrong =
    match_vram(0, slurp(OUT .. "bgchr" .. bg_set .. ".bin"))
  local bg_odd_wrong =
    match_vram(0x1000 * 2, slurp(OUT .. "bgchr_alt" .. bg_set .. ".bin"))
  local both_bg_phases = bg_phase_seen[0] and bg_phase_seen[0x1000]
  local independent = false
  for _, sample in ipairs(samples) do
    if sample[1] ~= sample[2] then independent = true end
  end

  local layer_ok = st["ppu.layers[1].tilemapAddress"] == 0x4000
                and st["ppu.layers[1].chrAddress"] == 0x5000
                and st["ppu.layers[1].doubleWidth"] == true
                and st["ppu.layers[1].doubleHeight"] == true
  local zero_holes, transparent_holes = 0, 0
  local first_col = (st["ppu.layers[0].hscroll"] >> 3) & 63
  for x = 0, 31 do
    for y = 0, 63 do
      local tile = bg1_word((first_col + x) & 63, y) & 0x03FF
      if tile == 0 then zero_holes = zero_holes + 1 end
      if tile == 0xFE then transparent_holes = transparent_holes + 1 end
    end
  end
  local blank_wrong = match_vram(0x1FC0, string.rep(string.char(0), 32))
  local blank_alt_wrong = match_vram(0x3FC0, string.rep(string.char(0), 32))
  local bg2_palette_wrong = 0
  local bg2_contrast_repairs = 0
  local backdrop = emu.read(0, emu.memType.snesCgRam, false)
                 + emu.read(1, emu.memType.snesCgRam, false) * 256
  for p = 0, 3 do
    local opaque = emu.read((p * 16 + 4) * 2,
                            emu.memType.snesCgRam, false)
                 + emu.read((p * 16 + 4) * 2 + 1,
                            emu.memType.snesCgRam, false) * 256
    if opaque ~= backdrop then bg2_palette_wrong = bg2_palette_wrong + 1 end
    for color = 1, 3 do
      local got = emu.read((p * 16 + color) * 2,
                           emu.memType.snesCgRam, false)
                + emu.read((p * 16 + color) * 2 + 1,
                           emu.memType.snesCgRam, false) * 256
      if got ~= rd(A.PAL_BUF + (p * 4 + color) * 2, 2) then
        bg2_palette_wrong = bg2_palette_wrong + 1
      end
    end
  end
  local native_ink = rd(A.PAL_BUF + 2, 2)
  local want_ink = native_ink
  if backdrop ~= 0 and native_ink == backdrop then
    want_ink = 0
    bg2_contrast_repairs = 1
  end
  local bg2_ink = emu.read(65 * 2, emu.memType.snesCgRam, false)
                + emu.read(65 * 2 + 1, emu.memType.snesCgRam, false) * 256
  if bg2_ink ~= want_ink then bg2_palette_wrong = bg2_palette_wrong + 1 end
  local ok = layer_ok and par_tiles_wrong == 0 and par_map_wrong == 0
          and independent and saw_seen[14] and saw_seen[15]
          and saw_wrong == 0 and rd(A.gameState) == 2
          and rd(A.scroll_x, 2) > 100
          and bg_even_wrong == 0 and bg_odd_wrong == 0 and both_bg_phases
          and bg_phase_checks > 100 and bg_phase_changes > 50
          and bg_phase_mismatch == 0
          and zero_holes == 0 and transparent_holes > 0
          and blank_wrong == 0 and blank_alt_wrong == 0
          and bg2_palette_wrong == 0
  local rows = {
    string.format("BG2 map=$%04X chr=$%04X wide=%s tall=%s",
      st["ppu.layers[1].tilemapAddress"],
      st["ppu.layers[1].chrAddress"],
      tostring(st["ppu.layers[1].doubleWidth"]),
      tostring(st["ppu.layers[1].doubleHeight"])),
    string.format(
      "parallax VRAM: tiles wrong=%d map wrong=%d independent scroll=%s",
      par_tiles_wrong, par_map_wrong, tostring(independent)),
    string.format("saws: frame14=%s frame15=%s live bank=%d wrong=%d",
      tostring(saw_seen[14] or false), tostring(saw_seen[15] or false),
      saw_bank, saw_wrong),
    string.format("BG1 phase sets: even wrong=%d odd wrong=%d both selected=%s",
      bg_even_wrong, bg_odd_wrong, tostring(both_bg_phases)),
    string.format("BG1 phase cadence: changes=%d mismatches=%d/%d",
      bg_phase_changes, bg_phase_mismatch, bg_phase_checks),
    string.format("gameplay: state=%d scroll=%d frames=%d",
      rd(A.gameState), rd(A.scroll_x, 2), game_frames),
    string.format("BG1 parallax holes: tile0=%d transparent=$FE:%d blanks wrong=%d/%d",
      zero_holes, transparent_holes, blank_wrong, blank_alt_wrong),
    string.format("BG2 palette wrong=%d contrast repairs=%d",
      bg2_palette_wrong, bg2_contrast_repairs),
    string.format("first 180f palette pairs=%d flips=%d; all pairs=%d raw pairs=%d flips=%d",
      (function() local x=0 for _ in pairs(early_pairs) do x=x+1 end return x end)(),
      early_flips,
      (function() local x=0 for _ in pairs(palette_pairs) do x=x+1 end return x end)(),
      (function() local x=0 for _ in pairs(raw_pairs) do x=x+1 end return x end)(),
      palette_flips),
    ok and "RESULT: SA-1 PARALLAX AND ROTATING SAWS OK" or "RESULT FAIL",
  }
  rows[#rows + 1] = string.format(
    "Mode 1 palette mapping wrong=%d backdrop=%04X BG2=%04X/%04X",
    bg2_palette_wrong, backdrop, bg2_ink, want_ink)
  rows[#rows + 1] = "TAIL  " .. table.concat(palette_tail, " | ")
  local f = assert(io.open(OUT .. "sa1_polish_verify.txt", "w"))
  f:write(table.concat(rows, "\n") .. "\n")
  f:close()
  local shot_ok, png = pcall(emu.takeScreenshot)
  if shot_ok and png and #png > 0 then
    f = assert(io.open(OUT .. "sa1_polish.png", "wb"))
    f:write(png)
    f:close()
  end
  emu.stop(ok and 0 or 1)
end, emu.eventType.startFrame)
