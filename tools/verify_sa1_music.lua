-- Original FamiStudio music on the split SA-1 build:
--   SA-1 sequencer -> shared I-RAM -> S-CPU -> SPC700 -> S-DSP.
--
-- This deliberately reads the producer from SA-1 I-RAM and the consumer from
-- SPC ARAM.  An audible DSP voice alone could be stale state; matching changing
-- images on opposite sides of the processor boundary proves the whole path.

local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local BANKS = dofile(OUT .. "famistudio_rom_bank.lua")
local META = dofile(OUT .. "famistudio_meta.lua")
local LEVEL_SONG = dofile(OUT .. "level_song.lua")
local LAYOUT = dofile(OUT .. "famistudio_layout.lua")

local IRAM = emu.memType.sa1InternalRam
local BWRAM = emu.memType.snesSaveRam
local ARAM = emu.memType.spcRam
local DSP = emu.memType.spcDspRegisters
local FS_BUF = LAYOUT.sa1_dp + LAYOUT.output_offset
local FS_BANK = LAYOUT.sa1_dp + LAYOUT.data_bank_offset
local FS_DPCM_SEQ = LAYOUT.sa1_dp + LAYOUT.dpcm_seq_offset
local TEST_LEVEL = tonumber(os.getenv("LEVEL")) or 1
local REQUIRE_DPCM = os.getenv("REQUIRE_DPCM") == "1"
local EXPECT_NO_DPCM_UPLOAD = os.getenv("EXPECT_NO_DPCM_UPLOAD") == "1"
local EXPECT_SONG = LEVEL_SONG[TEST_LEVEL + 1]
local EXPECT_INFO = META.songs[EXPECT_SONG + 1]
local EXPECT_BANK = BANKS.first + EXPECT_INFO.bank

local n, press = 0, false
local menu_frames, entered, gameframes = 0, false, 0
local images, pitches = {}, {}
local delivered, audible = 0, 0
local dpcm_frames, dpcm_events = 0, {}
local dpcm_commands = {}
local invalid_timer_frames = 0

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function image(base, mem)
  local t = {}
  for i = 0, 10 do
    t[#t + 1] = string.format("%02X", emu.read(base + i, mem, false))
  end
  return table.concat(t)
end

local function same_image()
  for i = 0, 10 do
    if emu.read(FS_BUF + i, IRAM, false)
       ~= emu.read(0x10 + i, ARAM, false) then
      return false
    end
  end
  return true
end

local function dsp(r)
  return emu.read(r, DSP, false)
end

-- The SA-1 menu receives pads through the S-CPU mailbox.  Use a broad pulse;
-- the game derives the press edge after the mailbox handoff. Poke menu_sel
-- only after shim_menu_active proves the menu exists, just as menu_skip.lua
-- does for the HiROM build.
emu.addEventCallback(function()
  if press then emu.setInput({ a = true }, 0) end
end, emu.eventType.inputPolled)

emu.addMemoryCallback(function(_, value)
  if not entered or value < 0xF9 or value > 0xFD then return end
  dpcm_commands[value] = (dpcm_commands[value] or 0) + 1
end, emu.callbackType.write, 0x002141, 0x002141)

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
  else
    press = false
    gameframes = gameframes + 1
  end

  if entered and gameframes >= 30 then
    images[image(FS_BUF, IRAM)] = true
    if emu.read(FS_BUF + 2, IRAM, false) > 7
       or emu.read(FS_BUF + 5, IRAM, false) > 7
       or emu.read(FS_BUF + 8, IRAM, false) > 7 then
      invalid_timer_frames = invalid_timer_frames + 1
    end
    pitches[string.format("%02X%02X/%02X%02X/%02X%02X",
      dsp(0x03), dsp(0x02), dsp(0x13), dsp(0x12), dsp(0x23), dsp(0x22))] = true
    if same_image() then delivered = delivered + 1 end
    if dsp(0x00) ~= 0 or dsp(0x10) ~= 0
       or dsp(0x20) ~= 0 or dsp(0x30) ~= 0 then
      audible = audible + 1
    end
    dpcm_events[emu.read(FS_DPCM_SEQ, IRAM, false)] = true
    if dsp(0x44) == 10 and dsp(0x40) ~= 0 then
      dpcm_frames = dpcm_frames + 1
    end
  end

  if not entered and n >= 1200 then
    local f = io.open(OUT .. "sa1_music.txt", "w")
    f:write(string.format(
      "menu_active=%d menu_sel=%d gameState=%d level=%d\n"
        .. "RESULT FAIL - SA-1 music verifier never entered level %d\n",
      emu.read(A.shim_menu_active, BWRAM, false),
      emu.read(A.menu_sel, BWRAM, false),
      emu.read(A.gameState, BWRAM, false),
      emu.read(A.level, BWRAM, false), TEST_LEVEL))
    f:close()
    emu.stop(1)
    return
  end
  if gameframes < 360 then return end

  local rows, bad = {}, 0
  local function say(s) rows[#rows + 1] = s end
  local actual_song = emu.read(A.song, BWRAM, false)
  local actual_bank = emu.read(FS_BANK, IRAM, false)
  local distinct, pitch_count = count(images), count(pitches)

  say(string.format("level %d song ID: %d (expected %d)",
                    TEST_LEVEL, actual_song, EXPECT_SONG))
  say(string.format("music data bank: $%02X (expected $%02X)",
                    actual_bank, EXPECT_BANK))
  say(string.format("%d distinct APU images; %d distinct DSP pitch sets",
                    distinct, pitch_count))
  say(string.format("%d delivered frames; %d audible DSP frames",
                    delivered, audible))
  say(string.format("%d frames with invalid 2A03 timer high bytes",
                    invalid_timer_frames))
  local dpcm_nonzero = 0
  for i = 0, 255 do
    if emu.read(0x2000 + i, ARAM, false) ~= 0 then
      dpcm_nonzero = dpcm_nonzero + 1
    end
  end
  say(string.format("DPCM: %d event values, %d voice frames, "
                    .. "%d/256 resident BRR bytes nonzero; commands "
                    .. "begin=%d data=%d start=%d play=%d stop=%d",
                    count(dpcm_events), dpcm_frames, dpcm_nonzero,
                    dpcm_commands[0xFD] or 0, dpcm_commands[0xFC] or 0,
                    dpcm_commands[0xFB] or 0, dpcm_commands[0xFA] or 0,
                    dpcm_commands[0xF9] or 0))

  if actual_song ~= EXPECT_SONG then bad = bad + 1 end
  if actual_bank ~= EXPECT_BANK then bad = bad + 1 end
  if distinct < 24 then bad = bad + 1 end
  if pitch_count < 5 then bad = bad + 1 end
  if delivered < 100 then bad = bad + 1 end
  if audible < 60 then bad = bad + 1 end
  if invalid_timer_frames ~= 0 then bad = bad + 1 end
  if count(dpcm_events) < 2 or (dpcm_commands[0xFA] or 0) < 1
     or dpcm_frames < 1 or dpcm_nonzero < 16 then
    -- A tone-only song is valid; require the sampled path only when this song
    -- actually requested it, or when the caller selected the dedicated check.
    if REQUIRE_DPCM or (dpcm_commands[0xFA] or 0) > 0 then
      bad = bad + 1
    end
  end
  if EXPECT_NO_DPCM_UPLOAD
     and ((dpcm_commands[0xFD] or 0) ~= 0
          or (dpcm_commands[0xFC] or 0) ~= 0) then
    bad = bad + 1
    say("resident song uploaded BRR data from an instrument frame")
  end

  say("")
  say(bad == 0
    and "RESULT OK - SA-1 FAMISTUDIO MUSIC REACHES THE S-DSP"
     or string.format("RESULT FAIL - %d SA-1 music-path problem(s)", bad))
  local f = io.open(OUT .. "sa1_music.txt", "w")
  f:write(table.concat(rows, "\n") .. "\n")
  f:close()
  emu.stop(bad == 0 and 0 or 1)
end, emu.eventType.endFrame)
