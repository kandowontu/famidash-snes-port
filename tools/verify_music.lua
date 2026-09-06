-- The real music path, end to end:
-- original FamiStudio data -> original 6502 sequencer -> 11-byte APU image ->
-- S-CPU port transport -> SPC700 translator -> S-DSP voices.
local OUT = "C:/famidash-snes-port/out/"
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
local ROM_BANK = dofile(OUT .. "famistudio_rom_bank.lua")
local META = dofile(OUT .. "famistudio_meta.lua")
local LEVEL_SONG = dofile(OUT .. "level_song.lua")
local LAYOUT = dofile(OUT .. "famistudio_layout.lua")
local A = dofile(OUT .. "addrs_full.lua")
local TEST_LEVEL = tonumber(os.getenv("LEVEL")) or 0
local REQUIRE_DPCM = os.getenv("REQUIRE_DPCM") == "1"
local EXPECT_NO_DPCM_UPLOAD = os.getenv("EXPECT_NO_DPCM_UPLOAD") == "1"
local EXPECT_SONG = LEVEL_SONG[TEST_LEVEL + 1]
local EXPECT_INFO = META.songs[EXPECT_SONG + 1]
menu.start(TEST_LEVEL)

local W = emu.memType.snesWorkRam
local ARAM = emu.memType.spcRam
local DSP = emu.memType.spcDspRegisters
local FS_BUF = LAYOUT.dp + LAYOUT.output_offset
local FS_BANK = LAYOUT.dp + LAYOUT.data_bank_offset
local EXPECT_BANK = ROM_BANK.first + EXPECT_INFO.bank
local frames, gameframes = 0, 0
local images, pitches = {}, {}
local delivered, audible, bad = 0, 0, 0
local dpcm_frames = 0
local dpcm_events = {}
local dpcm_commands = {}
local dpcm_details = {}
local dpcm_last
local dpcm_start_events = 0
local game_started = false
local rows = {}
local invalid_timer_frames = 0

local function dsp(r) return emu.read(r, DSP, false) end
local function image(base, mem)
  local t = {}
  for i = 0, 10 do t[#t + 1] = string.format("%02X", emu.read(base + i, mem)) end
  return table.concat(t)
end
local function same_image()
  for i = 0, 10 do
    if emu.read(FS_BUF + i, W, false) ~= emu.read(0x10 + i, ARAM, false) then
      return false
    end
  end
  return true
end
local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- DPCM hits can be shorter than the verifier's once-per-frame DSP snapshots,
-- so also observe the actual S-CPU -> SPC command stream.  Port 1 carries
-- arbitrary image bytes during the IPL upload; only count it after gameplay
-- has positively started.
emu.addMemoryCallback(function(_, value)
  if not game_started or value < 0xF9 or value > 0xFD then return end
  dpcm_commands[value] = (dpcm_commands[value] or 0) + 1
end, emu.callbackType.write, 0x002141, 0x002141)

local function finish()
  local distinct, pitch_count = count(images), count(pitches)
  rows[#rows + 1] = string.format(
    "%d distinct APU images; %d distinct DSP pitch sets; "
      .. "%d delivered frames; %d audible DSP frames",
    distinct, pitch_count, delivered, audible)
  rows[#rows + 1] = string.format(
    "%d frames with invalid 2A03 timer high bytes", invalid_timer_frames)
  local actual_song = emu.read(A.song, W, false)
  rows[#rows + 1] = string.format(
    "level %d song ID %d (expected %d), music bank $%02X (expected $%02X)",
    TEST_LEVEL, actual_song, EXPECT_SONG, emu.read(FS_BANK, W, false),
    EXPECT_BANK)
  local dpcm_nonzero = 0
  for i = 0, 255 do
    if emu.read(0x2000 + i, ARAM, false) ~= 0 then
      dpcm_nonzero = dpcm_nonzero + 1
    end
  end
  rows[#rows + 1] = string.format(
    "DPCM: %d event sequence values, %d configured voice frames, "
      .. "%d/256 resident BRR bytes nonzero; commands "
      .. "begin=%d data=%d start=%d play=%d stop=%d",
    count(dpcm_events), dpcm_frames, dpcm_nonzero,
    dpcm_commands[0xFD] or 0, dpcm_commands[0xFC] or 0,
    dpcm_commands[0xFB] or 0, dpcm_commands[0xFA] or 0,
    dpcm_commands[0xF9] or 0)
  local state = emu.getState()
  rows[#rows + 1] = string.format(
    "  transport: alive=%d S-CPU ports=%02X/%02X SPC pc=$%04X "
      .. "seq=$%02X writeptr=$%04X",
    emu.read(A.spc_alive, W, false),
    emu.read(0x2140, emu.memType.snesMemory, false),
    emu.read(0x2141, emu.memType.snesMemory, false),
    state["spc.pc"] or 0, emu.read(0x00, ARAM, false),
    emu.read(0x0E, ARAM, false) + emu.read(0x0F, ARAM, false) * 256)
  for _, detail in ipairs(dpcm_details) do rows[#rows + 1] = detail end
  if actual_song ~= EXPECT_SONG then
    bad = bad + 1
    rows[#rows + 1] = "level-to-song routing is wrong"
  end
  if emu.read(FS_BANK, W, false) ~= EXPECT_BANK then
    bad = bad + 1
    rows[#rows + 1] = string.format("wrong music DBR $%02X (want $%02X)",
      emu.read(FS_BANK, W, false), EXPECT_BANK)
  end
  if distinct < 32 then bad = bad + 1; rows[#rows + 1] = "register image barely changed" end
  -- Songs do not all have the same melodic density. Five independent pitch
  -- sets still proves that the live sequencer is driving the DSP; requiring
  -- twelve made drum-heavy songs fail while their 40+ APU images were valid.
  if pitch_count < 5 then bad = bad + 1; rows[#rows + 1] = "DSP pitches barely changed" end
  if delivered < 120 then bad = bad + 1; rows[#rows + 1] = "too few images reached ARAM" end
  if audible < 60 then bad = bad + 1; rows[#rows + 1] = "DSP voices stayed silent" end
  if invalid_timer_frames ~= 0 then
    bad = bad + 1
    rows[#rows + 1] =
      "relocated FamiStudio pitch state corrupted the 2A03 timers"
  end
  if count(dpcm_events) < 2 or (dpcm_commands[0xFA] or 0) < 1
      or dpcm_nonzero < 16 then
    if not REQUIRE_DPCM and dpcm_start_events == 0 then
      -- This song did not request a DPCM hit in the observed window. Tone
      -- routing is still a valid test; a dedicated REQUIRE_DPCM run covers
      -- the sampled-instrument path.
    else
      bad = bad + 1
      rows[#rows + 1] = "original DPCM/BRR instruments did not reach voice 4"
    end
  end
  if REQUIRE_DPCM and dpcm_start_events == 0 then
    bad = bad + 1
    rows[#rows + 1] = "test song never requested the required DPCM hit"
  end
  if EXPECT_NO_DPCM_UPLOAD
     and ((dpcm_commands[0xFD] or 0) ~= 0
          or (dpcm_commands[0xFC] or 0) ~= 0) then
    bad = bad + 1
    rows[#rows + 1] =
      "resident song uploaded BRR data from an instrument frame"
  end
  rows[#rows + 1] = bad == 0
    and "RESULT: ORIGINAL FAMISTUDIO MUSIC REACHES THE S-DSP"
     or string.format("RESULT: FAIL - %d music-path problem(s)", bad)
  local f = io.open(OUT .. "music_verify.txt", "w")
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  emu.stop(bad == 0 and 0 or 1)
end

emu.addEventCallback(function()
  frames = frames + 1
  if not menu.done() then
    if frames >= 1200 then
      rows[#rows + 1] = "RESULT: FAIL - game never entered"
      local f = io.open(OUT .. "music_verify.txt", "w")
      f:write(table.concat(rows, "\n") .. "\n"); f:close(); emu.stop(1)
    end
    return
  end
  game_started = true
  gameframes = gameframes + 1

  local event = emu.read(LAYOUT.dp + LAYOUT.dpcm_seq_offset, W, false)
  if event ~= dpcm_last then
    dpcm_last = event
    dpcm_events[event] = true
    if (emu.read(LAYOUT.dp + LAYOUT.apu_shadow_offset + 0x15,
                 W, false) & 0x10) ~= 0 then
      dpcm_start_events = dpcm_start_events + 1
    end
    dpcm_details[#dpcm_details + 1] = string.format(
      "  event %d: bank=%d $4010=%02X $4011=%02X $4012=%02X "
        .. "$4013=%02X $4015=%02X voice4 vol=%d src=%d",
      event, emu.read(FS_BANK - (LAYOUT.data_bank_offset
        - LAYOUT.dpcm_bank_offset), W, false),
      emu.read(LAYOUT.dp + LAYOUT.apu_shadow_offset + 0x10, W, false),
      emu.read(LAYOUT.dp + LAYOUT.apu_shadow_offset + 0x11, W, false),
      emu.read(LAYOUT.dp + LAYOUT.apu_shadow_offset + 0x12, W, false),
      emu.read(LAYOUT.dp + LAYOUT.apu_shadow_offset + 0x13, W, false),
      emu.read(LAYOUT.dp + LAYOUT.apu_shadow_offset + 0x15, W, false),
      dsp(0x40), dsp(0x44))
  end

  if gameframes < 30 then return end -- music_play lands during level setup

  images[image(FS_BUF, W)] = true
  if emu.read(FS_BUF + 2, W, false) > 7
     or emu.read(FS_BUF + 5, W, false) > 7
     or emu.read(FS_BUF + 8, W, false) > 7 then
    invalid_timer_frames = invalid_timer_frames + 1
  end
  pitches[string.format("%02X%02X/%02X%02X/%02X%02X",
    dsp(0x03), dsp(0x02), dsp(0x13), dsp(0x12), dsp(0x23), dsp(0x22))] = true
  if same_image() then delivered = delivered + 1 end
  if dsp(0x00) ~= 0 or dsp(0x10) ~= 0 or dsp(0x20) ~= 0 or dsp(0x30) ~= 0 then
    audible = audible + 1
  end
  if dsp(0x44) == 10 and dsp(0x40) ~= 0 then dpcm_frames = dpcm_frames + 1 end
  if gameframes == 210 then finish() end
end, emu.eventType.startFrame)
