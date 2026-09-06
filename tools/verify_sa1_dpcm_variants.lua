-- Prove a non-default FamiStudio $4011 counter variant selects its own
-- resident BRR waveform on the SA-1 path.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local LAYOUT = dofile(OUT .. "famistudio_layout.lua")
local IMG = dofile(OUT .. "spc_image.lua")
local IRAM = emu.memType.sa1InternalRam
local BWRAM = emu.memType.snesSaveRam
local ARAM = emu.memType.spcRam
local DSP = emu.memType.spcDspRegisters

-- Level 33 routes song 87. Its generated kit starts with global sample 0:
-- bank 0, start $00, length $41, *override initial $00*, one-shot.
local TEST_LEVEL = 33
local DP = LAYOUT.sa1_dp
local SHADOW = DP + LAYOUT.apu_shadow_offset
local DPCM_BANK = DP + LAYOUT.dpcm_bank_offset
local DPCM_SEQ = DP + LAYOUT.dpcm_seq_offset
local n, menu_frames, gameframes = 0, 0, 0
local entered, press, inject = false, false, false
local start_commands, play_commands = 0, 0
local rows, bad = {}, 0

emu.addEventCallback(function()
  if press then emu.setInput({a = true}, 0) end
end, emu.eventType.inputPolled)

emu.addMemoryCallback(function(_, value)
  if not entered then return end
  if value == 0xFB then start_commands = start_commands + 1 end
  if value == 0xFA then play_commands = play_commands + 1 end
end, emu.callbackType.write, 0x002141, 0x002141)

emu.addMemoryCallback(function()
  if not inject then return end
  inject = false
  emu.write(DPCM_BANK, 0, IRAM)
  emu.write(SHADOW + 0x10, 0x0F, IRAM) -- fastest DPCM rate, no loop
  emu.write(SHADOW + 0x11, 0x00, IRAM) -- the non-default initial counter
  emu.write(SHADOW + 0x12, 0x00, IRAM)
  emu.write(SHADOW + 0x13, 0x41, IRAM)
  emu.write(SHADOW + 0x15, 0x1F, IRAM)
  emu.write(DPCM_SEQ, (emu.read(DPCM_SEQ, IRAM, false) + 1) & 0xFF,
            IRAM)
end, emu.callbackType.exec,
    A.code.spc_frame_flush, A.code.spc_frame_flush)

local function word(address)
  return emu.read(address, ARAM, false)
       | (emu.read(address + 1, ARAM, false) << 8)
end

local function finish()
  local address = word(IMG.dirtab + 40)
  rows[#rows + 1] = string.format(
    "commands start/play=%d/%d; voice4 src=%d vol=%d; directory=$%04X",
    start_commands, play_commands, emu.read(0x44, DSP, false),
    emu.read(0x40, DSP, false), address)
  if start_commands < 1 or play_commands < 1 then
    bad = bad + 1
    rows[#rows + 1] = "DPCM trigger did not cross the S-CPU/SPC transport"
  end
  if address ~= 0x2000 then
    bad = bad + 1
    rows[#rows + 1] = string.format(
      "selected BRR address $%04X, want sample-0 variant at $2000", address)
  end
  if emu.read(0x44, DSP, false) ~= 10 or emu.read(0x40, DSP, false) == 0 then
    bad = bad + 1
    rows[#rows + 1] = "DPCM voice 4 was not configured and audible"
  end
  rows[#rows + 1] = bad == 0
    and "RESULT: SA-1 DPCM COUNTER VARIANT OK"
     or string.format("RESULT: FAIL - %d DPCM variant problem(s)", bad)
  local file = assert(io.open(OUT .. "sa1_dpcm_variants.txt", "w"))
  file:write(table.concat(rows, "\n") .. "\n")
  file:close()
  emu.stop(bad == 0 and 0 or 1)
end

emu.addEventCallback(function()
  n = n + 1
  if not entered then
    if emu.read(A.shim_menu_active, BWRAM, false) ~= 0 then
      menu_frames = menu_frames + 1
      emu.write(A.menu_sel, TEST_LEVEL, BWRAM)
      press = menu_frames >= 30 and menu_frames <= 45
    else
      press = false
      if menu_frames > 0
         and emu.read(A.gameState, BWRAM, false) == 2
         and emu.read(A.level, BWRAM, false) == TEST_LEVEL then
        entered = true
      end
    end
    if n > 1200 and not entered then
      bad = bad + 1
      rows[#rows + 1] = "level never started"
      finish()
    end
    return
  end
  gameframes = gameframes + 1
  if gameframes == 45 then inject = true end
  if gameframes == 49 then finish() end
end, emu.eventType.endFrame)
