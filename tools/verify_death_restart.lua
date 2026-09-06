-- Force a late death after level objects are live, then verify:
--   music stop + death SFX are advanced by the auto-update path,
--   OAM does not retain the frozen gameplay objects,
--   the forced-blank restart redraw is batched and returns promptly.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local L = dofile(OUT .. "famistudio_layout.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(0)

local W = emu.memType.snesWorkRam
local DSP = emu.memType.spcDspRegisters
local frames, death_at, reset_at, visible_at = 0
local deaths, resets, stops, sfx_calls = 0, 0, 0, 0
local forced, injected = false, false
local auto_frames, audible_frames, image_changes = 0, 0, 0
local max_live_after_first, death_frames = 0, 0
local last_image

local function rd(addr, n)
  local v = 0
  for i = 0, (n or 1) - 1 do
    v = v + emu.read(addr + i, W, false) * (256 ^ i)
  end
  return v
end

local function apu_image()
  local t = {}
  for i = 0, 10 do
    t[#t + 1] = string.char(emu.read(L.dp + L.output_offset + i, W, false))
  end
  return table.concat(t)
end

emu.addMemoryCallback(function()
  deaths = deaths + 1
  death_at = frames
end, emu.callbackType.exec, A.code.death_animation, A.code.death_animation)

emu.addMemoryCallback(function()
  resets = resets + 1
  if death_at then reset_at = frames end
end, emu.callbackType.exec, A.code.reset_level, A.code.reset_level)

emu.addMemoryCallback(function() stops = stops + 1 end,
  emu.callbackType.exec, A.code.famistudio_music_stop,
  A.code.famistudio_music_stop)
emu.addMemoryCallback(function() sfx_calls = sfx_calls + 1 end,
  emu.callbackType.exec, A.code.sfx_play, A.code.sfx_play)

emu.addEventCallback(function()
  if not menu.done() then return end
  -- Drive normally until sprite objects have reached the screen.
  emu.setInput({ a = true }, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frames = frames + 1
  if not menu.done() then return end

  if not injected and rd(A.scroll_x, 2) > 850 then
    emu.write(A.cube_data, rd(A.cube_data) | 1, W)
    injected = true
  end

  if death_at and not reset_at then
    death_frames = death_frames + 1
    if rd(A.auto_fs_updates) ~= 0 then auto_frames = auto_frames + 1 end

    local image = apu_image()
    if last_image and image ~= last_image then image_changes = image_changes + 1 end
    last_image = image

    local audible = false
    for voice = 0, 3 do
      if emu.read(voice * 0x10, DSP, false) ~= 0 then audible = true end
    end
    if audible then audible_frames = audible_frames + 1 end

    if death_frames > 1 then
      local live = 0
      for s = 0, 127 do
        if emu.read(s * 4 + 1, emu.memType.snesSpriteRam, false) < 225 then
          live = live + 1
        end
      end
      if live > max_live_after_first then max_live_after_first = live end
    end
  end

  if reset_at and not visible_at then
    local st = emu.getState()
    if not st["ppu.forcedBlank"] then visible_at = frames end
  end

  if not visible_at or frames < visible_at + 60 then
    if frames < 2400 then return end
  end

  local reset_gap = visible_at and (visible_at - reset_at) or 999
  local restarted = rd(A.gameState) == 2 and rd(A.scroll_x, 2) < 500
  local ok = deaths == 1 and resets >= 2 and stops >= 1 and sfx_calls >= 1
          and auto_frames >= 20 and audible_frames > 0 and image_changes > 0
          -- Four frames is the measured cached same-level reset, including
          -- state reinitialisation and the complete 34-column forced-blank DMA.
          -- The uncached path was ten frames.
          and max_live_after_first <= 16 and reset_gap <= 4 and restarted
  local rows = {
    string.format("death=%d reset calls=%d stop=%d sfx=%d",
      deaths, resets, stops, sfx_calls),
    string.format("death frames=%d auto-update=%d audible=%d APU changes=%d",
      death_frames, auto_frames, audible_frames, image_changes),
    string.format("max live OAM after first death frame=%d", max_live_after_first),
    string.format("restart forced-blank gap=%d frames state=%d scroll=%d",
      reset_gap, rd(A.gameState), rd(A.scroll_x, 2)),
    ok and "RESULT: DEATH AUDIO, OAM CLEAR, AND RESTART OK" or "RESULT FAIL",
  }
  local f = assert(io.open(OUT .. "death_restart_verify.txt", "w"))
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  emu.stop(ok and 0 or 1)
end, emu.eventType.startFrame)
