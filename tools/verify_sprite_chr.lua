-- Is the sprite CHR in VRAM, and does a bank switch actually switch it?
--
-- The original "missingno" was OBJ tiles naming VRAM that had never been
-- written. That is fixed, but the art is now BANK SWITCHED: the SNES has no CHR
-- ROM, so mmc3_set_2kb_chr_bank_0/1 DMA converted tiles into OBJ VRAM, and
-- "the right tile numbers against the wrong art" is a failure a screenshot
-- cannot distinguish from correct.
--
-- So this reads which banks the shim currently has selected and compares OBJ
-- VRAM against those banks' converted data, byte for byte. It samples several
-- times, because the decoration bank alternates every frame and catching
-- the switch is the point.
--
-- OBJ base is VRAM word $2000 and name-select 0 puts the second 256-tile table
-- at +$1000 words, so NES pattern table 1 lands at word $3000 = byte $6000:
--   2KB bank 0 -> OBJ tiles 256-383 -> byte $6000, 4096 bytes
--   2KB bank 1 -> OBJ tiles 384-511 -> byte $7000, 4096 bytes
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local BANK0_BYTE, BANK1_BYTE = 0x6000, 0x7000
local BANK_BYTES = 4096
local SAMPLE_AT = { 200, 260, 320, 380, 600, 900 }

local cache = {}
local function bank_data(n)
  if cache[n] == nil then
    local f = io.open(OUT .. string.format("sprchr%d.bin", n), "rb")
    cache[n] = f and f:read("*a") or false
    if f then f:close() end
  end
  return cache[n]
end

-- Hold A and disable death so the run gets past the opening spike; the bank
-- switching is per-frame work either way.
-- Gameplay input only AFTER the menu. A is also "select this level", so a
-- script that holds it from frame 1 races the level select - and whichever wins
-- depends on when the menu happens to appear, which a compiler flag can move.
-- That is how every scripted run silently played level 0 (docs/HANDOFF.md
-- trap 114).
emu.addEventCallback(function()
  if not menu.done() then return end
  emu.setInput({ a = true }, 0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frames, idx, rows, bad = 0, 1, {}, 0
local seen = {}

local function check(label, vram_byte, bank)
  local want = bank_data(bank)
  if want == false then
    rows[#rows + 1] = string.format("  %s: bank %d - no out/sprchr%d.bin, not carried",
                                    label, bank, bank)
    return
  end
  local wrong, first = 0, nil
  for i = 1, BANK_BYTES do
    local got = emu.read(vram_byte + i - 1, emu.memType.snesVideoRam)
    if got ~= want:byte(i) then
      wrong = wrong + 1
      if not first then first = i - 1 end
    end
  end
  if wrong > 0 then bad = bad + 1 end
  seen[bank] = true
  rows[#rows + 1] = string.format("  %s: bank %-3d %s%s", label, bank,
    wrong == 0 and "matches" or string.format("%d/%d bytes WRONG", wrong, BANK_BYTES),
    first and string.format(" (first at byte %d)", first) or "")
end

emu.addEventCallback(function()
  -- Gameplay only. main() now opens the level select first, so a script that
  -- counts from reset measures the menu - which reads as a game with nothing in
  -- it rather than as an error. See tools/menu_skip.lua.
  if not menu.done() then return end
  frames = frames + 1
  if idx > #SAMPLE_AT or frames < SAMPLE_AT[idx] then return end
  -- A bank is 4KB and the budget is 2KB a frame, so a switch lands over two
  -- frames and VRAM legitimately disagrees with the selected bank in between.
  -- Wait for the queue to drain rather than reporting a half-arrived upload as
  -- corruption (docs/HANDOFF.md trap 55, same shape).
  if emu.read(A.shim_chr_pending, emu.memType.snesWorkRam) ~= 0 then return end
  idx = idx + 1

  local b0 = emu.read(A.shim_chr_bank0, emu.memType.snesWorkRam)
  local b1 = emu.read(A.shim_chr_bank1, emu.memType.snesWorkRam)
  rows[#rows + 1] = string.format("frame %d: OBJ bank0=%d bank1=%d", frames, b0, b1)
  check("tiles 256-383", BANK0_BYTE, b0)
  check("tiles 384-511", BANK1_BYTE, b1)

  if idx > #SAMPLE_AT then
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    local unknown = emu.read(A.shim_chr_unknown, emu.memType.snesWorkRam)
                  + emu.read(A.shim_chr_unknown + 1, emu.memType.snesWorkRam) * 256
    local drops = emu.read(A.shim_chr_drops, emu.memType.snesWorkRam)
                + emu.read(A.shim_chr_drops + 1, emu.memType.snesWorkRam) * 256
    rows[#rows + 1] = ""
    rows[#rows + 1] = string.format(
      "%d distinct banks seen in VRAM; %d requests for a bank not carried, %d uploads dropped",
      n, unknown, drops)
    -- More than one bank proves the switching works, not just the boot upload.
    local ok = bad == 0 and drops == 0 and n >= 2
    rows[#rows + 1] = ok and "RESULT: SPRITE CHR CORRECT, AND BANK SWITCHING WORKS"
                          or "RESULT: FAIL"
    local f = io.open(OUT .. "sprite_chr_verify.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(ok and 0 or 1)
  end
end, emu.eventType.startFrame)
