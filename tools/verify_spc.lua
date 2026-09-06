-- The audio path, end to end: ROM -> IPL -> ARAM -> driver -> S-DSP.
--
-- Four things, in order, because each one only means something if the one
-- before it held:
--
--   1. the driver image reached ARAM byte for byte;
--   2. the driver ran and set up the DSP's global state;
--   3. an APU register image pushed through the port handshake arrives;
--   4. the DSP voices hold the pitch, volume and source that image implies.
--
-- (4) is the one that matters and (1)-(3) are what stop a failure in it being
-- misread. A wrong pitch with a corrupt upload is not a translation bug.
--
-- The real sequencer now writes famistudio_output_buf every frame. This script
-- replaces that image at the entry to spc_frame_flush, after the sequencer has
-- run and immediately before transport reads it. That isolates the translator
-- while tools/verify_music.lua tests the real end-to-end producer.
--
-- The expected pitch is recomputed here from the 2A03 and DSP clock rates
-- rather than read out of the table the driver uses. That is the point: a
-- verifier that reads the same table cannot catch a wrong table (trap 61).
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local IMG = dofile(OUT .. "spc_image.lua")
local LAYOUT = dofile(OUT .. "famistudio_layout.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)

local W = emu.memType.snesWorkRam
local ARAM = emu.memType.spcRam
local DSP = emu.memType.spcDspRegisters
local FS_BUF = LAYOUT.dp + LAYOUT.output_offset

local rows, bad = {}, 0
local function say(s) rows[#rows + 1] = s end
local function fail(s) bad = bad + 1; say("  <-- " .. s) end

-- ---- the expected DSP pitch, from first principles -----------------------
-- The DSP plays a sample at 32000 * PITCH / 4096 Hz; a pulse waveform is 16
-- samples per cycle and the 2A03 pulse frequency is 1789773/(16*(P+1)). The
-- triangle's two factors of 32 cancel to the same expression.
local function want_pitch(period)
  local p = math.floor(4096 * 1789773 / (32000 * (period + 1)) + 0.5)
  if p > 0x3FFF then p = 0x3FFF end
  return p
end

-- The volume table's own arithmetic, from gen_spc_image.py.
local function want_vol(v)
  return math.floor(v * IMG.vol_max / 15 + 0.5)
end

local NOISE_PERIODS = { 4, 8, 16, 32, 64, 96, 128, 160,
                        202, 254, 380, 508, 762, 1016, 2034, 4068 }
local function want_noise_pitch(index)
  local p = math.floor(4096 * (1789773 / NOISE_PERIODS[index + 1])
                       / 32000 + 0.5)
  return math.min(0x3FFF, p)
end

local function dsp(reg) return emu.read(reg, DSP) end
local function dsp16(reg) return dsp(reg) + dsp(reg + 1) * 256 end

-- ---- driving the buffer --------------------------------------------------
-- Each case is a full eleven-byte APU image and what it should produce.
-- Volume bytes carry FamiStudio's own constant bits: duty<<6 | $30 | volume on
-- the pulses, $80 | plays on the triangle, $F0 | volume on the noise.
local CASES = {
  { name = "pulse1 duty 2, vol 12, period 200",
    buf = { 0x30 | (2 << 6) | 12, 200 % 256, 0, 0x30, 0, 0,
            0x80, 0, 0, 0xF0, 0 },
    check = function()
      if dsp(0x00) ~= want_vol(12) then fail(string.format(
        "voice 0 VOL_L %d, want %d", dsp(0x00), want_vol(12))) end
      if dsp16(0x02) ~= want_pitch(200) then fail(string.format(
        "voice 0 pitch $%04X, want $%04X", dsp16(0x02), want_pitch(200))) end
      if dsp(0x04) ~= 2 then fail("voice 0 SRCN " .. dsp(0x04) .. ", want 2") end
    end },
  { name = "pulse2 duty 0, vol 15, period 1000; pulse1 silent",
    buf = { 0x30, 0, 0, 0x30 | 15, 1000 % 256, math.floor(1000 / 256),
            0x80, 0, 0, 0xF0, 0 },
    check = function()
      if dsp(0x00) ~= 0 then fail("voice 0 should be silent, VOL_L " .. dsp(0x00)) end
      if dsp(0x10) ~= want_vol(15) then fail(string.format(
        "voice 1 VOL_L %d, want %d", dsp(0x10), want_vol(15))) end
      if dsp16(0x12) ~= want_pitch(1000) then fail(string.format(
        "voice 1 pitch $%04X, want $%04X", dsp16(0x12), want_pitch(1000))) end
      if dsp(0x14) ~= 0 then fail("voice 1 SRCN " .. dsp(0x14) .. ", want 0") end
    end },
  { name = "triangle on, period 400",
    buf = { 0x30, 0, 0, 0x30, 0, 0,
            0x80 | 15, 400 % 256, math.floor(400 / 256), 0xF0, 0 },
    check = function()
      if dsp(0x20) == 0 then fail("voice 2 silent with the triangle playing") end
      if dsp16(0x22) ~= want_pitch(400) then fail(string.format(
        "voice 2 pitch $%04X, want $%04X", dsp16(0x22), want_pitch(400))) end
      if dsp(0x24) ~= 4 then fail("voice 2 SRCN " .. dsp(0x24) .. ", want 4") end
    end },
  { name = "triangle off - TRI_LINEAR $80 with no volume bits",
    buf = { 0x30, 0, 0, 0x30, 0, 0, 0x80, 400 % 256, 1, 0xF0, 0 },
    check = function()
      if dsp(0x20) ~= 0 then fail("voice 2 VOL_L " .. dsp(0x20)
                                  .. " with the triangle cut") end
    end },
  { name = "noise vol 10, period index 12",
    buf = { 0x30, 0, 0, 0x30, 0, 0, 0x80, 0, 0, 0xF0 | 10, 12 },
    check = function()
      if dsp(0x30) ~= want_vol(10) then fail(string.format(
        "voice 3 VOL_L %d, want %d", dsp(0x30), want_vol(10))) end
      -- The 2A03's period 12 is 762 CPU cycles = 2349Hz; the nearest DSP noise
      -- rate is 2000Hz, which is entry 22. Bit 5 keeps echo writes disabled.
      if dsp(0x6C) ~= (0x20 | 22) then fail(string.format(
        "FLG $%02X, want $%02X", dsp(0x6C), 0x20 | 22)) end
    end },
  { name = "short noise vol 9, period index 12 - sampled 93-step LFSR",
    buf = { 0x30, 0, 0, 0x30, 0, 0, 0x80, 0, 0, 0xF0 | 9, 0x80 | 12 },
    check = function()
      if dsp(0x30) ~= want_vol(9) then fail(string.format(
        "voice 3 VOL_L %d, want %d", dsp(0x30), want_vol(9))) end
      if dsp(0x3D) ~= 0 then fail(string.format(
        "NON $%02X, want short-noise BRR rather than hardware noise",
        dsp(0x3D))) end
      if dsp(0x34) ~= 5 then fail(
        "voice 3 SRCN " .. dsp(0x34) .. ", want short-noise source 5") end
      if dsp16(0x32) ~= want_noise_pitch(12) then fail(string.format(
        "voice 3 pitch $%04X, want $%04X",
        dsp16(0x32), want_noise_pitch(12))) end
    end },
  { name = "pulse1 period 4 - below the 2A03's mute threshold",
    buf = { 0x30 | 15, 4, 0, 0x30, 0, 0, 0x80, 0, 0, 0xF0, 0 },
    check = function()
      if dsp(0x00) ~= 0 then fail("voice 0 VOL_L " .. dsp(0x00)
                                  .. " at period 4; the 2A03 mutes below 8") end
    end },
}

-- Replace the sequencer's frame at the exact consumer boundary. A startFrame
-- injection is too early: music_update legitimately overwrites it before the
-- vblank flush and every case then appears silent.
local case = 0
emu.addMemoryCallback(function()
  if case == 0 or not CASES[case] then return end
  for i, v in ipairs(CASES[case].buf) do
    emu.write(FS_BUF + i - 1, v, W)
  end
end, emu.callbackType.exec, A.code.spc_frame_flush, A.code.spc_frame_flush)

local frames, phase, settle = 0, 0, 0
-- WAIT FOR THE DATA TO ARRIVE, DO NOT COUNT FRAMES.
--
-- A fixed settling window was wrong twice here, in both directions: six frames
-- read the DSP before the first commit had even been sent and reported the
-- driver's init values as the answer to every case, and sixteen fixed only the
-- last four cases. The number is not a constant - spc_frame_flush runs from
-- ppu_wait_nmi, and the level select does not call ppu_wait_nmi at all, so the
-- first push happens somewhere inside the level load and how long THAT takes
-- depends on the level.
--
-- The driver's own frame buffer at ARAM $0010 is the positive signal: when it
-- matches the case's eleven bytes, the transport has delivered them and the
-- commit that follows is one transaction behind. This is the same lesson as
-- trap 97 - prove the state you need, do not wait a while and assume it.
local FB = 0x0010
local SETTLE = 3                -- frames after arrival, for the commit and apply
local done = false

local function delivered(buf)
  for i, v in ipairs(buf) do
    if emu.read(FB + i - 1, ARAM) ~= v then return false end
  end
  return true
end

local function finish()
  if done then return end
  done = true
  say("")
  say(bad == 0 and "RESULT: THE SPC700 DRIVER PLAYS THE APU REGISTER IMAGE"
                or string.format("RESULT: FAIL - %d problem(s)", bad))
  local f = io.open(OUT .. "spc_verify.txt", "w")
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  emu.stop(bad == 0 and 0 or 1)
end

emu.addEventCallback(function()
  if done then return end
  frames = frames + 1

  if phase == 0 then
    -- WAIT FOR THE GAME TO BE UP FIRST, and not for spc_alive alone.
    --
    -- startFrame fires from reset, and spc_alive lives in BSS that cstartup has
    -- not cleared yet at that point - so on the very first frame it reads as
    -- whatever WRAM powered up holding (45, as it happens) and every check
    -- below ran against an SPC700 still sitting in its IPL ROM. That is trap 97
    -- with a different variable: a harness has to prove the game is ready
    -- rather than infer it from a value that has not been written yet.
    -- menu.done() is a positive signal - the game reached STATE_GAME - and
    -- spc_boot runs long before that.
    if not menu.done() then return end

    if emu.read(A.spc_alive, W, false) == 0 then
      say("spc_alive is zero after the game started - the IPL upload did not "
          .. "complete, or the SPC700 never answered")
      bad = bad + 1
      finish()
      return
    end

    -- 1. ARAM against the image in the ROM, byte for byte. This is the check
    --    that a later wrong note is not simply a corrupt upload.
    local img = io.open(OUT .. "spc_driver.bin", "rb")
    local want = img:read("*all")
    img:close()
    local wrong, first = 0, nil
    for i = 1, #want do
      if emu.read(IMG.load + i - 1, ARAM) ~= want:byte(i) then
        wrong = wrong + 1
        first = first or (IMG.load + i - 1)
      end
    end
    say(string.format("ARAM $%04X..$%04X: %d bytes, %d wrong%s",
                      IMG.load, IMG.load + #want - 1, #want, wrong,
                      first and string.format(" (first at $%04X)", first) or ""))
    if wrong ~= 0 then fail("the driver image did not reach ARAM intact") end

    -- 2. The globals the driver sets up once. DIR is the page holding the
    --    sample directory; without it every voice plays whatever ARAM byte the
    --    stale directory happened to point at.
    say(string.format("DSP  DIR $%02X (want $%02X)  MVOL_L %d  NON $%02X  FLG $%02X",
                      dsp(0x5D), IMG.dirtab >> 8, dsp(0x0C), dsp(0x3D), dsp(0x6C)))
    if dsp(0x5D) ~= (IMG.dirtab >> 8) then fail("DIR does not point at the directory") end
    if dsp(0x3D) ~= 0x08 then fail("NON should have voice 3 on noise") end
    if (dsp(0x6C) & 0x40) ~= 0 then fail("FLG still has the mute bit set") end
    if (dsp(0x6C) & 0x20) == 0 then fail("FLG should keep echo writes disabled") end
    if dsp(0x0C) == 0 then fail("master volume is zero") end

    -- 3. The voices were keyed on at init and are running. A voice that was
    --    never keyed on reads back an envelope of zero forever, which would
    --    make every volume check below pass for the wrong reason.
    local st = emu.getState()
    for v = 0, 3 do
      local env = st[string.format("spc.dsp.voices[%d].envVolume", v)]
      if env == nil or env == 0 then
        fail(string.format("voice %d envelope %s - it was never keyed on",
                           v, tostring(env)))
      end
    end
    say("voices 0-3 keyed on with a running envelope")

    phase, case, settle = 1, 1, 0
    say("")
    return
  end

  -- 4. One case at a time. Do not start the settling window until the driver's
  --    own ARAM buffer proves that this exact case crossed the transport.
  if not delivered(CASES[case].buf) then
    settle = 0
    return
  end
  settle = settle + 1
  if settle < SETTLE then return end
  settle = 0

  local before = bad
  say(string.format("%-52s", CASES[case].name))
  CASES[case].check()
  if bad == before then rows[#rows] = rows[#rows] .. "  ok" end

  case = case + 1
  if not CASES[case] then finish() end
end, emu.eventType.startFrame)
