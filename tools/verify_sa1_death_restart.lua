-- SA-1 death/restart counterpart to verify_death_restart.lua. Mesen does not
-- expose SA-1 execution callbacks, so phase changes are identified from the
-- shared game state, forced blank, OAM, I-RAM FamiStudio output and S-DSP.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local L = dofile(OUT .. "famistudio_layout.lua")

local B = emu.memType.snesSaveRam
local I = emu.memType.sa1InternalRam
local O = emu.memType.snesSpriteRam
local DSP = emu.memType.spcDspRegisters
local FS_OUTPUT = L.sa1_dp + L.output_offset

local frames, menu_frames, game_frames = 0, 0, 0
local entered, menu_press, injected = false, false, false
local death_at, reset_at, visible_at
local death_frames, auto_frames = 0, 0
local audible_frames, image_changes = 0, 0
local max_live_after_first = 0
local last_image
local injected_at
local phase_trace = {}

local function rd(addr, width)
  local value = 0
  for i = 0, (width or 1) - 1 do
    value = value + emu.read(addr + i, B, false) * (256 ^ i)
  end
  return value
end

local function apu_image()
  local bytes = {}
  for i = 0, 10 do
    bytes[#bytes + 1] = string.char(emu.read(FS_OUTPUT + i, I, false))
  end
  return table.concat(bytes)
end

emu.addEventCallback(function()
  if menu_press or entered then
    emu.setInput({ a = true }, 0)
  else
    emu.setInput({}, 0)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frames = frames + 1
  if not entered then
    if rd(A.shim_menu_active) ~= 0 then
      menu_frames = menu_frames + 1
      emu.write(A.menu_sel, 0, B)
      menu_press = menu_frames >= 30 and menu_frames <= 45
    else
      menu_press = false
      if menu_frames > 0 and rd(A.gameState) == 2 and rd(A.level) == 0 then
        entered = true
      end
    end
  else
    game_frames = game_frames + 1
  end

  if entered and not injected then
    -- Keep the scripted run alive until decorations and hazards occupy OAM.
    emu.write(A.cube_data, rd(A.cube_data) & 0xFE, B)
    local sx = rd(A.scroll_x, 2)
    -- During reset scroll_x briefly contains a wrapped negative value. Wait
    -- for established gameplay so that is not mistaken for a late-level run.
    if game_frames > 300 and sx > 850 and sx < 10000 then
      emu.write(A.cube_data, rd(A.cube_data) | 1, B)
      injected = true
      injected_at = frames
    end
  end

  if injected_at and frames <= injected_at + 45 then
    local phase = string.format("%d:a%d/f%d/s%d",
      frames - injected_at, rd(A.auto_fs_updates),
      emu.getState()["ppu.forcedBlank"] and 1 or 0, rd(A.scroll_x, 2))
    phase_trace[#phase_trace + 1] = phase
  end

  if injected and not death_at and rd(A.auto_fs_updates) ~= 0 then
    death_at = frames
  end

  local st = emu.getState()
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
      for sprite = 0, 127 do
        if emu.read(sprite * 4 + 1, O, false) < 225 then live = live + 1 end
      end
      if live > max_live_after_first then max_live_after_first = live end
    end

    -- On SA-1 the forced-blank shadow can be applied and restored between two
    -- Mesen startFrame callbacks. The same reset is also unambiguously marked
    -- by the completed 30-frame auto-update window and scroll returning to 0.
    if st["ppu.forcedBlank"]
       or (death_frames >= 20 and rd(A.auto_fs_updates) == 0
           and rd(A.scroll_x, 2) < 200) then
      reset_at = frames
    end
  elseif reset_at and not visible_at and not st["ppu.forcedBlank"] then
    visible_at = frames
  end

  if not visible_at or frames < visible_at + 60 then
    if frames < 2600 then return end
  end

  local reset_gap = visible_at and (visible_at - reset_at) or 999
  local restarted = rd(A.gameState) == 2 and rd(A.scroll_x, 2) < 500
  local ok = injected and death_at ~= nil and reset_at ~= nil
          and death_frames >= 20 and auto_frames >= 20
          and audible_frames > 0 and image_changes > 0
          and max_live_after_first <= 16 and reset_gap <= 4 and restarted
          and rd(A.auto_fs_updates) == 0 and rd(A.spc_alive) == 1
  local rows = {
    string.format("injected=%s death=%s reset=%s visible=%s",
      tostring(injected), tostring(death_at ~= nil),
      tostring(reset_at ~= nil), tostring(visible_at ~= nil)),
    string.format("death frames=%d auto-update=%d audible=%d APU changes=%d",
      death_frames, auto_frames, audible_frames, image_changes),
    string.format("max live OAM after first death frame=%d", max_live_after_first),
    string.format("restart forced-blank gap=%d frames state=%d scroll=%d SPC=%d",
      reset_gap, rd(A.gameState), rd(A.scroll_x, 2), rd(A.spc_alive)),
    "phase trace: " .. table.concat(phase_trace, " | "),
    ok and "RESULT: SA-1 DEATH AUDIO, OAM CLEAR, AND RESTART OK"
       or "RESULT FAIL",
  }
  local f = assert(io.open(OUT .. "sa1_death_restart_verify.txt", "w"))
  f:write(table.concat(rows, "\n") .. "\n")
  f:close()
  emu.stop(ok and 0 or 1)
end, emu.eventType.startFrame)
