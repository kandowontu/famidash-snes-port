-- SA-1-only regression for pulse and noise instruments whose timbre depends
-- on a source change or FamiStudio's explicit phase-reset effect.
--
-- The S-DSP latches SRCN at key-on. Merely writing a new pulse/noise source
-- number while a voice runs leaves the old waveform audible, so this watches
-- both the bridge's tone-key command and the final DSP source selection.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local LAYOUT = dofile(OUT .. "famistudio_layout.lua")
local IMG = dofile(OUT .. "spc_image.lua")

local IRAM = emu.memType.sa1InternalRam
local BWRAM = emu.memType.snesSaveRam
local ARAM = emu.memType.spcRam
local DSP = emu.memType.spcDspRegisters
local FS_BUF = LAYOUT.sa1_dp + LAYOUT.output_offset
local FS_RESET = LAYOUT.sa1_dp + LAYOUT.phase_reset_offset
local TEST_LEVEL = tonumber(os.getenv("LEVEL")) or 0

local n, menu_frames, entered, gameframes = 0, 0, false, 0
local press = false
local rows, bad = {}, 0
local tone_commands = 0
local active_case = 0
local reset_once = 0
local settled = 0
local baseline_commands = 0

local function say(value) rows[#rows + 1] = value end
local function fail(value)
  bad = bad + 1
  say("  FAIL: " .. value)
end
local function dsp(reg) return emu.read(reg, DSP, false) end

local CASES = {
  {
    name = "establish pulse duty 0",
    buf = {0x3C, 200, 0, 0x30, 0, 0, 0x80, 0, 0, 0xF0, 0},
    src0 = 0,
  },
  {
    name = "pulse 1 duty envelope 0 -> 2",
    buf = {0xBC, 200, 0, 0x30, 0, 0, 0x80, 0, 0, 0xF0, 0},
    src0 = 2, command_delta = 1,
  },
  {
    name = "pitch-only update does not restart pulse",
    buf = {0xBC, 210, 0, 0x30, 0, 0, 0x80, 0, 0, 0xF0, 0},
    src0 = 2, command_delta = 0,
  },
  {
    name = "FamiStudio explicit pulse 1 phase reset",
    buf = {0xBC, 210, 0, 0x30, 0, 0, 0x80, 0, 0, 0xF0, 0},
    reset = 1, src0 = 2, command_delta = 1,
  },
  {
    name = "pulse 2 duty envelope 0 -> 3",
    buf = {0xBC, 210, 0, 0xF9, 180, 0, 0x80, 0, 0, 0xF0, 0},
    src0 = 2, src1 = 3, command_delta = 1,
  },
  {
    name = "establish hardware long noise",
    buf = {0xBC, 210, 0, 0xF9, 180, 0, 0x80, 0, 0, 0xFA, 0},
    non = 0x08, command_delta = 0,
  },
  {
    name = "long -> short noise period 0",
    buf = {0xBC, 210, 0, 0xF9, 180, 0, 0x80, 0, 0, 0xFA, 0x80},
    src3 = 6, non = 0, pitch3 = 0x1000, command_delta = 1,
  },
  {
    name = "short noise alias period 0 -> 1",
    buf = {0xBC, 210, 0, 0xF9, 180, 0, 0x80, 0, 0, 0xFA, 0x81},
    src3 = 7, non = 0, pitch3 = 0x1000, command_delta = 1,
  },
  {
    name = "short noise alias -> regular period 8",
    buf = {0xBC, 210, 0, 0xF9, 180, 0, 0x80, 0, 0, 0xFA, 0x88},
    src3 = 5, non = 0, command_delta = 1,
  },
  {
    name = "regular short-noise pitch-only update",
    buf = {0xBC, 210, 0, 0xF9, 180, 0, 0x80, 0, 0, 0xFA, 0x89},
    src3 = 5, non = 0, command_delta = 0,
  },
}

emu.addEventCallback(function()
  if press then emu.setInput({a = true}, 0) end
end, emu.eventType.inputPolled)

-- Count the dedicated S-CPU -> SPC command. The exact key pulse lives on the
-- SPC side; observing this together with SRCN proves both halves agree.
emu.addMemoryCallback(function(_, value)
  if entered and value == 0xF6 then tone_commands = tone_commands + 1 end
end, emu.callbackType.write, 0x002141, 0x002141)

-- Replace the live producer image at the consumer boundary, after the SA-1
-- sequencer has finished this frame and before the S-CPU transports it.
emu.addMemoryCallback(function()
  local case = CASES[active_case]
  if not case then return end
  for i, value in ipairs(case.buf) do
    emu.write(FS_BUF + i - 1, value, IRAM)
  end
  if reset_once ~= 0 then
    emu.write(FS_RESET, reset_once, IRAM)
    reset_once = 0
  else
    emu.write(FS_RESET, 0, IRAM)
  end
end, emu.callbackType.exec,
    A.code.spc_frame_flush, A.code.spc_frame_flush)

local function finish()
  local image = assert(io.open(OUT .. "spc_driver.bin", "rb"))
  local wanted = image:read("*all")
  image:close()
  local wrong = 0
  for i = 1, #wanted do
    if emu.read(IMG.load + i - 1, ARAM, false) ~= wanted:byte(i) then
      wrong = wrong + 1
    end
  end
  say(string.format("SPC image upload: %d bytes, %d wrong", #wanted, wrong))
  if wrong ~= 0 then fail("generated instrument sources did not reach ARAM") end
  say("")
  say(string.format("tone key commands observed=%d", tone_commands))
  say(bad == 0
    and "RESULT: SA-1 PULSE/NOISE SOURCE TRANSITIONS AND PHASE RESET OK"
     or string.format("RESULT: FAIL - %d SA-1 instrument problem(s)", bad))
  local file = assert(io.open(OUT .. "sa1_instruments.txt", "w"))
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
    if n >= 1200 and not entered then
      fail("level never started")
      finish()
    end
    return
  end

  gameframes = gameframes + 1
  if gameframes == 30 then
    active_case = 1
    reset_once = CASES[1].reset or 0
    settled = 0
  end
  if active_case == 0 then return end

  settled = settled + 1
  if settled < 8 then return end
  local case = CASES[active_case]
  if case.src0 ~= nil and dsp(0x04) ~= case.src0 then
    fail(string.format("%s: voice 0 SRCN=%d, want %d",
                       case.name, dsp(0x04), case.src0))
  end
  if case.src1 ~= nil and dsp(0x14) ~= case.src1 then
    fail(string.format("%s: voice 1 SRCN=%d, want %d",
                       case.name, dsp(0x14), case.src1))
  end
  if case.src3 ~= nil and dsp(0x34) ~= case.src3 then
    fail(string.format("%s: voice 3 SRCN=%d, want %d",
                       case.name, dsp(0x34), case.src3))
  end
  if case.non ~= nil and dsp(0x3D) ~= case.non then
    fail(string.format("%s: NON=$%02X, want $%02X",
                       case.name, dsp(0x3D), case.non))
  end
  if case.pitch3 ~= nil
     and (dsp(0x32) | (dsp(0x33) << 8)) ~= case.pitch3 then
    fail(string.format("%s: voice 3 pitch=$%04X, want $%04X",
                       case.name, dsp(0x32) | (dsp(0x33) << 8),
                       case.pitch3))
  end
  if active_case > 1 then
    local got = tone_commands - baseline_commands
    local want = case.command_delta or 0
    if got ~= want then
      fail(string.format("%s: %d tone-key command(s), want %d",
                         case.name, got, want))
    end
  end
  say(string.format("%-46s src=%d/%d/%d NON=$%02X commands=%d",
                    case.name, dsp(0x04), dsp(0x14), dsp(0x34), dsp(0x3D),
                    tone_commands - baseline_commands))
  baseline_commands = tone_commands
  active_case = active_case + 1
  if not CASES[active_case] then
    finish()
    return
  end
  reset_once = CASES[active_case].reset or 0
  settled = 0
end, emu.eventType.endFrame)
