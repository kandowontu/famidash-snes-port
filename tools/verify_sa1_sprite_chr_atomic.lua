-- Verify the two resident decoration banks and the per-frame OBJ name-table
-- selection on the SA-1 ROM.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local B = emu.memType.snesSaveRam
local V = emu.memType.snesVideoRam
local O = emu.memType.snesSpriteRam
local TEST_LEVEL = tonumber(os.getenv("LEVEL")) or 0
local FORCE_DISCO = tonumber(os.getenv("FORCE_DISCO")) or 0
local VRAM_BANK1 = 0x7000
local VRAM_CACHE = 0x5000
local BYTES = 4096

local function slurp(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*all")
  file:close()
  return data
end

local function rd(addr, width)
  local value = 0
  for i = 0, (width or 1) - 1 do
    value = value + emu.read(addr + i, B, false) * (256 ^ i)
  end
  return value
end

local frames, menu_frames, gameplay = 0, 0, 0
local entered, press = false, false
local base, even, odd, differing
local complete_even, complete_odd = 0, 0
local mixed_frames, flips, last_bank = 0, 0, nil
local visible_phase_mismatches = 0
local phase_matrix = {0, 0, 0, 0}
local first_mixed, first_phase_mismatch, second_phase_mismatch
local ready, observed = false, 0
local flush_pending, flush_bank = false, nil

emu.addEventCallback(function()
  if press or entered then emu.setInput({a = true}, 0) end
end, emu.eventType.inputPolled)

-- Capture the decoration selection which this complete producer frame is
-- actually publishing. On a missed SA-1 deadline the S-CPU intentionally
-- repeats the previous display and does not call this routine.
emu.addMemoryCallback(function()
  if not entered then return end
  flush_bank = rd(A.shim_chr_bank1)
  flush_pending = true
end, emu.callbackType.exec, A.code.shim_scpu_flush, A.code.shim_scpu_flush)

local function classify()
  local is_even, is_odd = true, true
  for i = 1, BYTES do
    if emu.read(VRAM_BANK1 + i - 1, V, false) ~= even:byte(i) then
      is_even = false
    end
    if emu.read(VRAM_CACHE + i - 1, V, false) ~= odd:byte(i) then
      is_odd = false
    end
  end
  return is_even, is_odd
end

local function displayed_phase_mismatches(bank)
  local expected_name = bank == base and 1 or 0
  local refs, bad = 0, 0
  for i = 0, 127 do
    local y = emu.read(i * 4 + 1, O, false)
    local tile = emu.read(i * 4 + 2, O, false)
    local attr = emu.read(i * 4 + 3, O, false)
    -- NES CHR bank 1 is tile-byte $80-$FF. Player/bank-0 tiles are below it.
    if y < 225 and tile >= 0x80 then
      refs = refs + 1
      if (attr & 1) ~= expected_name then bad = bad + 1 end
    end
  end
  return refs, bad
end

local function finish()
  local drops = rd(A.shim_chr_drops, 2)
  local ok = entered and observed > 300 and mixed_frames == 0
             and complete_even > 0 and complete_odd > 0
             and flips >= 20 and flips <= 40
             and visible_phase_mismatches == 0 and drops == 0
  local rows = {
    string.format("level=%d deco pair=%d/%d gameplay=%d",
                  TEST_LEVEL, base or -1, base and base + 2 or -1, gameplay),
    string.format("observed=%d resident tables base/alt=%d/%d corrupt=%d",
                  observed, complete_even, complete_odd, mixed_frames),
    string.format("published-phase flips=%d OAM-name mismatches=%d CHR drops=%d",
                  flips, visible_phase_mismatches, drops),
    string.format("resident matrix base-select base/alt=%d/%d cache-select base/alt=%d/%d",
                  phase_matrix[1], phase_matrix[2],
                  phase_matrix[3], phase_matrix[4]),
    first_mixed and ("first mixed frame: " .. first_mixed)
                or "first mixed frame: none",
    first_phase_mismatch
      and ("first phase mismatch: " .. first_phase_mismatch)
       or "first phase mismatch: none",
    second_phase_mismatch
      and ("second phase mismatch: " .. second_phase_mismatch)
       or "second phase mismatch: none",
    ok and "RESULT: SA-1 RESIDENT SPRITE PHASE SWITCHING IS ATOMIC"
       or "RESULT: FAIL - CORRUPT OR STALLED SA-1 SPRITE PHASE",
  }
  local file = assert(io.open(OUT .. "sa1_sprite_chr_atomic.txt", "w"))
  file:write(table.concat(rows, "\n") .. "\n")
  file:close()
  emu.stop(ok and 0 or 1)
end

emu.addEventCallback(function()
  frames = frames + 1
  if not entered then
    if rd(A.shim_menu_active) ~= 0 then
      menu_frames = menu_frames + 1
      emu.write(A.menu_sel, TEST_LEVEL, B)
      press = menu_frames >= 30 and menu_frames <= 45
    else
      press = false
      if menu_frames > 0 and rd(A.gameState) == 2
         and rd(A.level) == TEST_LEVEL then
        entered = true
      end
    end
    if frames >= 1200 and not entered then finish() end
    return
  end

  gameplay = gameplay + 1
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, B)
  if FORCE_DISCO ~= 0 then
    emu.write(A.discomode, 0x10, B)
    emu.write(A.discorefreshrate, 0x03, B)
    -- Keep the stress window in one continuous level run. A death/reset
    -- restarts kandoframecnt at zero and legitimately leaves the base phase
    -- selected throughout the fade, which is not an animation stall.
    emu.write(A.DEBUG_MODE, 1, B)
    emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, B)
  end
  if gameplay >= 30 and not differing then
    local candidate = rd(A.current_deco_type)
    if candidate ~= 28 and candidate ~= 32 and candidate ~= 36 then
      if gameplay >= 600 then
        first_mixed = string.format(
          "current_deco_type never initialized (last=%d)", candidate)
        finish()
      end
      return
    end
    base = candidate
    even = slurp(OUT .. string.format("sprchr%d.bin", base))
    odd = slurp(OUT .. string.format("sprchr%d.bin", base + 2))
    if not even or not odd then
      first_mixed = string.format(
        "missing generated pair for current_deco_type=%d", base)
      finish()
      return
    end
    differing = {}
    for i = 1, BYTES do
      if even:byte(i) ~= odd:byte(i) then
        differing[#differing + 1] = i
      end
    end
  end
  -- Level entry sets gameState before state_game has completed its fade-in and
  -- first forced-blank CHR load. Do not treat that initialization boundary as
  -- a steady-state animation frame; the user-visible alternation begins after
  -- the player starts moving.
  if differing and gameplay < 100 then flush_pending = false end
  if differing and flush_pending then
    local bank = flush_bank
    local is_even, is_odd = classify()
    if not ready then
      if (bank == base or bank == base + 2)
         and (is_even or is_odd) then
        ready = true
        -- The first sample has no preceding selection to compare against.
        last_bank = nil
      end
      if not ready then
        if gameplay >= 600 then finish() end
        return
      end
    end
    observed = observed + 1
    if last_bank and bank ~= last_bank then flips = flips + 1 end
    if is_even then complete_even = complete_even + 1 end
    if is_odd then complete_odd = complete_odd + 1 end
    if not is_even or not is_odd then
      mixed_frames = mixed_frames + 1
      if not first_mixed then
        first_mixed = string.format(
          "gameplay=%d selected=%d pending=%d",
          gameplay, bank, rd(A.shim_chr_pending))
      end
    end
    -- `bank` was sampled at the S-CPU flush which produced this displayed
    -- frame. Bank-1 sprite tile bytes keep bit 7; attribute name bit 8 chooses
    -- the base table for the base phase and the low cached table for the alt.
    -- The selector changes at the top of the loop immediately before ppu_wait;
    -- OAM being published there was built after the PREVIOUS wait, with the
    -- preceding selector. The name bit embedded in OAM is therefore expected
    -- to follow last_bank, not the already-selected phase for the next draw.
    local refs, bad = 0, 0
    if last_bank then refs, bad = displayed_phase_mismatches(last_bank) end
    if refs > 0 and bad > 0 then
      visible_phase_mismatches = visible_phase_mismatches + 1
      local detail = string.format(
          "gameplay=%d next=%d displayed-from=%d pending=%d bank0=%d mode=%d refs=%d bad=%d",
          gameplay, bank, last_bank, rd(A.shim_chr_pending),
          rd(A.shim_chr_bank0), rd(A.gamemode), refs, bad)
      if not first_phase_mismatch then first_phase_mismatch = detail
      elseif not second_phase_mismatch then second_phase_mismatch = detail end
    end
    if bank == base then
      if is_even then phase_matrix[1] = phase_matrix[1] + 1 end
      if is_odd then phase_matrix[2] = phase_matrix[2] + 1 end
    elseif bank == base + 2 then
      if is_even then phase_matrix[3] = phase_matrix[3] + 1 end
      if is_odd then phase_matrix[4] = phase_matrix[4] + 1 end
    end
    last_bank = bank
    flush_pending = false
  end

  if gameplay >= 600 then finish() end
end, emu.eventType.endFrame)
