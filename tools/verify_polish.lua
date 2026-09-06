-- Verify the SNES-native background polish on the HiROM build:
--   * BG2 contains the generated parallax art/map and is independently scrolled
--   * both original saw CHR frames reach the live BG1 tile slot
--   * the level remains in gameplay while these states change
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local BG = dofile(OUT .. "bg_level_expect.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
local LEVEL = tonumber(os.getenv("LEVEL") or "0")
local TOTAL = tonumber(os.getenv("FRAMES") or "600")
menu.start(LEVEL)

local W = emu.memType.snesWorkRam
local V = emu.memType.snesVideoRam
local frames, samples = 0, {}
local saw_seen = {}
local bg_phase_seen = {}
local bg_phase_checks, bg_phase_mismatch, bg_phase_changes = 0, 0, 0
local last_bg_phase

local function rd(addr, n)
  local v = 0
  for i = 0, (n or 1) - 1 do
    v = v + emu.read(addr + i, W, false) * (256 ^ i)
  end
  return v
end

local function slurp(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
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

-- Keep the run alive and moving so both layer scroll and saw phase change.
emu.addEventCallback(function()
  if menu.done() then emu.setInput({ a = true }, 0) end
end, emu.eventType.inputPolled)

emu.addMemoryCallback(function()
  emu.write(A.cube_data,
            emu.read(A.cube_data, W, false) & 0xFE, W)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

emu.addEventCallback(function()
  frames = frames + 1
  if not menu.done() then return end
  local bg_chr = emu.getState()["ppu.layers[0].chrAddress"]
  bg_phase_seen[bg_chr] = true
  if menu.frame() > 30 then
    bg_phase_checks = bg_phase_checks + 1
    -- shim_scroll_apply changes the visible BG tile base and saw phase
    -- atomically in vblank. parallax_scroll_x is next-frame game state and can
    -- legitimately advance after that vblank but before this callback.
    local visible_phase = rd(A.shim_saw_bank) == 15 and 0x1000 or 0
    if bg_chr ~= visible_phase then
      bg_phase_mismatch = bg_phase_mismatch + 1
    end
    if last_bg_phase and bg_chr ~= last_bg_phase then
      bg_phase_changes = bg_phase_changes + 1
    end
    last_bg_phase = bg_chr
  end
  local gf = menu.frame()
  if gf % 30 == 0 then
    local st = emu.getState()
    local b1 = st["ppu.layers[0].hscroll"]
    local b2 = st["ppu.layers[1].hscroll"]
    samples[#samples + 1] = { b1, b2 }
    saw_seen[rd(A.shim_saw_bank)] = true
  end
  if gf < TOTAL then return end

  local st = emu.getState()
  local par_tiles_wrong = match_vram(0x5000 * 2, slurp(OUT .. "parallax.tiles.bin"))
  local par_map_wrong = match_vram(0x4000 * 2, slurp(OUT .. "parallax.map.bin"))
  local bank = rd(A.shim_saw_bank)
  local saw_file = bank == 15 and "saw1.bin" or "saw0.bin"
  local saw_word = bank == 15 and 0x1600 or 0x0600
  local saw_wrong = match_vram(saw_word * 2, slurp(OUT .. saw_file))
  local bg_set = BG.tileset[LEVEL + 1]
  local bg_even_wrong =
    match_vram(0, slurp(OUT .. "bgchr" .. bg_set .. ".bin"))
  local bg_odd_wrong =
    match_vram(0x1000 * 2, slurp(OUT .. "bgchr_alt" .. bg_set .. ".bin"))
  local both_bg_phases = bg_phase_seen[0] and bg_phase_seen[0x1000]
  local independent = false
  for _, s in ipairs(samples) do
    if s[1] ~= s[2] then independent = true end
  end
  local both_saws = saw_seen[14] and saw_seen[15]
  local layer_ok = st["ppu.layers[1].tilemapAddress"] == 0x4000
                and st["ppu.layers[1].chrAddress"] == 0x5000
                and st["ppu.layers[1].doubleWidth"] == true
                and st["ppu.layers[1].doubleHeight"] == true
  local game_ok = rd(A.gameState) == 2 and rd(A.scroll_x, 2) > 100
  local zero_holes, transparent_holes = 0, 0
  local first_col = (st["ppu.layers[0].hscroll"] >> 3) & 63
  for x = 0, 31 do
    for y = 0, 63 do
      local tile = bg1_word((first_col + x) & 63, y) & 0x03FF
      if tile == 0 then zero_holes = zero_holes + 1 end
      if tile == 0x100 then transparent_holes = transparent_holes + 1 end
    end
  end
  local blank_wrong = match_vram(0x1000, string.rep(string.char(0), 16))
  local blank_alt_wrong = match_vram(0x3000, string.rep(string.char(0), 16))
  local bg2_palette_wrong = 0
  for color = 0, 15 do
    local bg1 = emu.read(color * 2, emu.memType.snesCgRam, false)
              + emu.read(color * 2 + 1, emu.memType.snesCgRam, false) * 256
    local bg2 = emu.read((32 + color) * 2, emu.memType.snesCgRam, false)
              + emu.read((32 + color) * 2 + 1, emu.memType.snesCgRam, false) * 256
    if bg1 ~= bg2 then bg2_palette_wrong = bg2_palette_wrong + 1 end
  end

  local rows = {
    string.format("BG2 map=$%04X chr=$%04X wide=%s tall=%s",
      st["ppu.layers[1].tilemapAddress"],
      st["ppu.layers[1].chrAddress"],
      tostring(st["ppu.layers[1].doubleWidth"]),
      tostring(st["ppu.layers[1].doubleHeight"])),
    string.format("parallax VRAM: tiles wrong=%d map wrong=%d independent scroll=%s",
      par_tiles_wrong, par_map_wrong, tostring(independent)),
    string.format("saws: frame14=%s frame15=%s live bank=%d wrong=%d",
      tostring(saw_seen[14] or false), tostring(saw_seen[15] or false),
      bank, saw_wrong),
    string.format("BG1 phase sets: even wrong=%d odd wrong=%d both selected=%s",
      bg_even_wrong, bg_odd_wrong, tostring(both_bg_phases)),
    string.format("BG1 phase cadence: changes=%d mismatches=%d/%d",
      bg_phase_changes, bg_phase_mismatch, bg_phase_checks),
    string.format("gameplay: state=%d scroll=%d", rd(A.gameState), rd(A.scroll_x, 2)),
    string.format("BG1 parallax holes: tile0=%d transparent=$100:%d blanks wrong=%d/%d",
      zero_holes, transparent_holes, blank_wrong, blank_alt_wrong),
    string.format("BG2 palette mirror wrong=%d", bg2_palette_wrong),
  }
  local cgram, raw = {}, {}
  for color = 0, 15 do
    cgram[#cgram + 1] = string.format("%04X",
      emu.read(color * 2, emu.memType.snesCgRam, false)
      + emu.read(color * 2 + 1, emu.memType.snesCgRam, false) * 256)
    raw[#raw + 1] = string.format(
      "%02X", emu.read(A.PAL_BUF_RAW + color, W, false))
  end
  rows[#rows + 1] = "CGRAM " .. table.concat(cgram, " ")
  rows[#rows + 1] = "RAW   " .. table.concat(raw, " ")
  local ok = layer_ok and par_tiles_wrong == 0 and par_map_wrong == 0
          and independent and both_saws and saw_wrong == 0 and game_ok
          and bg_even_wrong == 0 and bg_odd_wrong == 0 and both_bg_phases
          and bg_phase_checks > 100 and bg_phase_changes > 50
          and bg_phase_mismatch == 0
          and zero_holes == 0 and transparent_holes > 0
          and blank_wrong == 0 and blank_alt_wrong == 0
          and bg2_palette_wrong == 0
  rows[#rows + 1] = ok and "RESULT: PARALLAX AND ROTATING SAWS OK"
                          or "RESULT FAIL"
  local f = assert(io.open(OUT .. "polish_verify.txt", "w"))
  f:write(table.concat(rows, "\n") .. "\n")
  f:close()
  local shot_ok, png = pcall(emu.takeScreenshot)
  if shot_ok and png and #png > 0 then
    f = assert(io.open(OUT .. "polish.png", "wb"))
    f:write(png); f:close()
  end
  emu.stop(ok and 0 or 1)
end, emu.eventType.startFrame)
