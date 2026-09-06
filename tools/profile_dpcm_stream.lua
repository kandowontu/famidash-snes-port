-- Prove sampled-instrument traffic is bounded per video frame.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local LAYOUT = dofile(OUT .. "famistudio_layout.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
local level = tonumber(os.getenv("LEVEL")) or 1
local stop_at = tonumber(os.getenv("FRAMES")) or 1800
menu.start(level)

local video_frames, game_frames = 0, 0
local frame_data, max_data, max_at = 0, 0, 0
local commands = {}
local injected = false
local inject_miss = os.getenv("INJECT_MISS") == "1"

emu.addEventCallback(function()
  if menu.done() then emu.setInput({ a = true }, 0) end
end, emu.eventType.inputPolled)

emu.addMemoryCallback(function()
  emu.write(A.cube_data,
    emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
    emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

emu.addMemoryCallback(function()
  game_frames = game_frames + 1
end, emu.callbackType.exec, A.code.everything_else, A.code.everything_else)

emu.addMemoryCallback(function(_, value)
  if not menu.done() or value < 0xF7 or value > 0xFD then return end
  commands[value] = (commands[value] or 0) + 1
  if value == 0xFC or value == 0xF7 then frame_data = frame_data + 1 end
end, emu.callbackType.write, 0x002141, 0x002141)

-- Song 36's generated hot set intentionally excludes global BRR sample 27.
-- Inject that real table shape immediately before the flush to exercise the
-- exceptional-track fallback independently of where the song uses it.
emu.addMemoryCallback(function()
  if not inject_miss or injected or video_frames < 300 then return end
  local W = emu.memType.snesWorkRam
  local shadow = LAYOUT.dp + LAYOUT.apu_shadow_offset
  emu.write(LAYOUT.dp + LAYOUT.dpcm_bank_offset, 7, W)
  emu.write(shadow + 0x10, 0x0F, W)
  emu.write(shadow + 0x11, 0x40, W)
  emu.write(shadow + 0x12, 0x38, W)
  emu.write(shadow + 0x13, 0xE7, W)
  emu.write(shadow + 0x15, 0x1F, W)
  local seq = LAYOUT.dp + LAYOUT.dpcm_seq_offset
  emu.write(seq, (emu.read(seq, W, false) + 1) & 0xFF, W)
  injected = true
end, emu.callbackType.exec, A.code.spc_frame_flush, A.code.spc_frame_flush)

emu.addEventCallback(function()
  if not menu.done() then return end
  video_frames = video_frames + 1
  if frame_data > max_data then
    max_data, max_at = frame_data, video_frames
  end
  frame_data = 0
  if video_frames < stop_at then return end

  local rows = {
    string.format("level %d: %d video frames, %d game frames (%.1f%%)",
      level, video_frames, game_frames, 100 * game_frames / video_frames),
    string.format(
      "commands: data1=%d size=%d stop=%d play=%d start=%d data2=%d begin=%d",
      commands[0xF7] or 0, commands[0xF8] or 0, commands[0xF9] or 0,
      commands[0xFA] or 0, commands[0xFB] or 0, commands[0xFC] or 0,
      commands[0xFD] or 0),
    string.format("maximum fallback data commands in one video frame: %d (frame %d)",
      max_data, max_at),
    string.format("forced non-resident instrument: %s", tostring(injected)),
    max_data <= 192
      and "RESULT: DPCM STREAM IS BOUNDED"
       or "RESULT: DPCM STREAM EXCEEDED ITS FRAME BUDGET",
  }
  local f = io.open(OUT .. "dpcm_stream_profile.txt", "w")
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  emu.stop(max_data <= 192 and 0 or 1)
end, emu.eventType.startFrame)
