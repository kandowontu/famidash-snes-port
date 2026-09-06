-- Verify the native completion screen and same-level restart on the SA-1
-- mapping. Gameplay state lives in BW-RAM, the FamiStudio producer in I-RAM,
-- and PPU/OAM state is shared with the S-CPU.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local L = dofile(OUT .. "famistudio_layout.lua")

local B = emu.memType.snesSaveRam
local I = emu.memType.sa1InternalRam
local V = emu.memType.snesVideoRam
local O = emu.memType.snesSpriteRam
local FS_OUTPUT = L.sa1_dp + L.output_offset

local frames, menu_frames, game_frames, end_frames = 0, 0, 0, 0
local entered_game, forced, entered_end, pressed = false, false, false, false
local press_menu, restart_at = false, nil
local title_ok, screenshot_ok = false, false
local max_oam, audible_frames = 0, 0
local output_images = {}
local input_trace = {}

local function rd(addr, width)
  local value = 0
  for i = 0, (width or 1) - 1 do
    value = value + emu.read(addr + i, B, false) * (256 ^ i)
  end
  return value
end

local function title_matches()
  local text = "LEVEL COMPLETE"
  local base = (0x6000 + 4 * 32 + 9) * 2
  for i = 1, #text do
    if emu.read(base + (i - 1) * 2, V, false) ~= text:byte(i) then
      return false
    end
  end
  return true
end

local function output_signature()
  local bytes = {}
  for i = 0, 10 do
    bytes[#bytes + 1] = string.format(
      "%02X", emu.read(FS_OUTPUT + i, I, false))
  end
  return table.concat(bytes)
end

local function count_keys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function match_bg_prefix()
  local f = assert(io.open(OUT .. "bgchr0.bin", "rb"))
  local data = f:read(3072)
  f:close()
  local wrong = 0
  for i = 1, #data do
    if emu.read(i - 1, V, false) ~= data:byte(i) then wrong = wrong + 1 end
  end
  return wrong
end

local function capture()
  local ok, png = pcall(emu.takeScreenshot)
  if not ok or not png or #png == 0 then return false end
  local f = assert(io.open(OUT .. "sa1_end_screen.png", "wb"))
  f:write(png)
  f:close()
  return true
end

emu.addEventCallback(function()
  if press_menu
     or (entered_game and not entered_end)
     or (entered_end and end_frames >= 45 and end_frames < 50) then
    emu.setInput({ a = true }, 0)
    if entered_end and end_frames >= 45 then pressed = true end
  else
    emu.setInput({}, 0)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frames = frames + 1
  if not entered_game then
    if rd(A.shim_menu_active) ~= 0 then
      menu_frames = menu_frames + 1
      emu.write(A.menu_sel, 0, B)
      press_menu = menu_frames >= 30 and menu_frames <= 45
    else
      press_menu = false
      if menu_frames > 0 and rd(A.gameState) == 2 and rd(A.level) == 0 then
        entered_game = true
      end
    end
  elseif not entered_end then
    game_frames = game_frames + 1
    emu.write(A.cube_data, rd(A.cube_data) & 0xFE, B)
    if not forced and game_frames >= 180 then
      emu.write(A.gameState, 3, B)
      forced = true
    end
    if rd(A.gameState) == 3 then entered_end = true end
  end

  local state = rd(A.gameState)
  if entered_end and state == 3 then
    end_frames = end_frames + 1
    if end_frames >= 35 and end_frames <= 65 then
      local mailbox_pad = emu.read(0x102, I, false)
                        + emu.read(0x103, I, false) * 256
      input_trace[#input_trace + 1] = string.format(
        "%d:mb=%04X hold=%02X press=%02X native=%d req=%d/%d",
        end_frames, mailbox_pad, rd(A.joypad1), rd(A.joypad1 + 1),
        rd(A.shim_native_screen_active),
        emu.read(0x108, I, false), emu.read(0x109, I, false))
    end
    title_ok = title_ok or title_matches()
    output_images[output_signature()] = true

    if end_frames >= 15 then
      local live = 0
      for sprite = 0, 127 do
        if emu.read(sprite * 4 + 1, O, false) < 225 then live = live + 1 end
      end
      if live > max_oam then max_oam = live end
    end

    local st = emu.getState()
    local audible = false
    for voice = 0, 4 do
      if (st[string.format("spc.dsp.voices[%d].envVolume", voice)] or 0) > 0 then
        audible = true
      end
    end
    if audible then audible_frames = audible_frames + 1 end
    if end_frames == 20 then screenshot_ok = capture() end
  elseif entered_end and pressed and state == 2 and not restart_at then
    restart_at = frames
  end

  if not entered_game and frames >= 1400 then
    local f = assert(io.open(OUT .. "sa1_end_screen_verify.txt", "w"))
    f:write("RESULT FAIL - never entered SA-1 gameplay\n")
    f:close()
    emu.stop(1)
    return
  end
  if not restart_at or frames < restart_at + 45 then
    if frames < 1800 then return end
  end

  local st = emu.getState()
  local bg_wrong = match_bg_prefix()
  local images = count_keys(output_images)
  local ok = entered_end and title_ok and screenshot_ok and max_oam == 0
          and restart_at ~= nil and state == 2 and bg_wrong == 0
          and images >= 2 and audible_frames >= 1 and rd(A.spc_alive) == 1
          and rd(A.shim_native_screen_active) == 0
  local rows = {
    string.format("entered=%s end frames=%d title=%s screenshot=%s",
      tostring(entered_end), end_frames, tostring(title_ok),
      tostring(screenshot_ok)),
    string.format("max OAM=%d restart=%s restored BG prefix wrong=%d",
      max_oam, tostring(restart_at ~= nil), bg_wrong),
    string.format("completion audio images=%d audible frames=%d SPC alive=%d",
      images, audible_frames, rd(A.spc_alive)),
    string.format("state=%d scroll=%d native screen=%d vscroll=%d",
      state, rd(A.scroll_x, 2), rd(A.shim_native_screen_active),
      st["ppu.layers[0].vscroll"] or -1),
    "input trace: " .. table.concat(input_trace, " | "),
    ok and "RESULT: SA-1 END SCREEN AND RESTART OK" or "RESULT FAIL",
  }
  local f = assert(io.open(OUT .. "sa1_end_screen_verify.txt", "w"))
  f:write(table.concat(rows, "\n") .. "\n")
  f:close()
  emu.stop(ok and 0 or 1)
end, emu.eventType.startFrame)
