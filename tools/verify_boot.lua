-- Does the ROM boot and keep executing real code?
--
-- Not a claim that it works - only that it is not wedged in garbage. The
-- classic failure here is a black screen with cpu.pc near 0 (docs/HANDOFF.md
-- trap 17: NMI enabled with no handler).
--
-- Note emu.getState() returns a FLAT table with dotted keys ("cpu.pc"), not
-- nested tables, and on HiROM code legitimately runs anywhere in banks $C0-$FF,
-- so a low 16-bit PC is not by itself a fault.
local OUT = "C:/famidash-snes-port/out/"
local SAMPLE_AT = { 30, 60, 120, 240, 400, 600 }
local frames, idx, rows, pcs = 0, 1, {}, {}

local function onFrame()
  frames = frames + 1
  if idx > #SAMPLE_AT or frames ~= SAMPLE_AT[idx] then return end
  local st = emu.getState()
  local pc, bank = st["cpu.pc"], st["cpu.k"]
  pcs[#pcs + 1] = bank * 0x10000 + pc
  rows[#rows + 1] = string.format(
    "frame %4d  pc=%02X:%04X  brightness=%2d  forcedBlank=%-5s  bgmode=%d  main=%02X",
    frames, bank, pc, st["ppu.screenBrightness"], tostring(st["ppu.forcedBlank"]),
    st["ppu.bgMode"], st["ppu.mainScreenLayers"])
  idx = idx + 1

  if idx > #SAMPLE_AT then
    local ok, moved = true, false
    for i = 2, #pcs do if pcs[i] ~= pcs[1] then moved = true end end
    for _, p in ipairs(pcs) do
      local b = p >> 16
      -- HiROM maps ROM into $C0-$FF (and mirrors at $80-$BF).
      if b < 0x80 then ok = false end
    end
    rows[#rows + 1] = moved and "pc advances between samples"
                            or "pc identical at every sample (tight loop or wedged)"
    rows[#rows + 1] = ok and "RESULT: BOOTS (executing in ROM)"
                          or "RESULT: WEDGED (pc left ROM)"
    local f = io.open(OUT .. "boot_verify.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n")
    f:close()
    emu.stop(ok and 0 or 1)
  end
end
emu.addEventCallback(onFrame, emu.eventType.startFrame)
