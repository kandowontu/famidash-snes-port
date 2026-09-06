-- Enter STATE_LVLDONE from live gameplay, verify the native completion screen,
-- then press A and verify a clean same-level restart with BG art restored.
--
-- This intentionally uses only frame/input callbacks. Execution callbacks
-- around the SPC transport perturb Mesen's S-CPU/SPC scheduling enough to
-- create a debugger-only handshake stall during the forced-blank transition.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(0)

local W = emu.memType.snesWorkRam
local V = emu.memType.snesVideoRam
local O = emu.memType.snesSpriteRam
local FS_OUTPUT = 0x1EAC

local frames, game_frames, end_frames = 0, 0, 0
local forced, entered, pressed, restart_at = false, false, false, nil
local title_ok, screenshot_ok = false, false
local max_oam, audible_frames = 0, 0
local output_images = {}
local capture_tm, capture_brightness = 0, 0
local capture_vscroll, capture_font_wrong = 0, -1
local capture_cgram1 = 0

local function rd(addr, n)
  local v = 0
  for i = 0, (n or 1) - 1 do
    v = v + emu.read(addr + i, W, false) * (256 ^ i)
  end
  return v
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

local function match_bg_prefix()
  local f = assert(io.open(OUT .. "bgchr0.bin", "rb"))
  local s = f:read(3072)
  f:close()
  local wrong = 0
  for i = 1, #s do
    if emu.read(i - 1, V, false) ~= s:byte(i) then
      wrong = wrong + 1
    end
  end
  return wrong
end

local function output_signature()
  local bytes = {}
  for i = 0, 10 do
    bytes[#bytes + 1] = string.format(
      "%02X", emu.read(FS_OUTPUT + i, W, false))
  end
  return table.concat(bytes)
end

local function capture()
  local st = emu.getState()
  capture_tm = st["ppu.mainScreenLayers"] or 0
  capture_brightness = st["ppu.screenBrightness"] or 0
  capture_vscroll = st["ppu.layers[0].vscroll"] or 0
  capture_cgram1 = emu.read(2, emu.memType.snesCgRam, false)
                 + emu.read(3, emu.memType.snesCgRam, false) * 256

  local font = assert(io.open(OUT .. "menu.tiles.bin", "rb"))
  local bytes = font:read("*a")
  font:close()
  capture_font_wrong = 0
  for i = 1, #bytes do
    if emu.read(i - 1, V, false) ~= bytes:byte(i) then
      capture_font_wrong = capture_font_wrong + 1
    end
  end

  local ok, png = pcall(emu.takeScreenshot)
  if not ok or not png or #png == 0 then return false end
  local f = assert(io.open(OUT .. "end_screen.png", "wb"))
  f:write(png)
  f:close()
  return true
end

local function live_oam_count()
  local live = 0
  for s = 0, 127 do
    if emu.read(s * 4 + 1, O, false) < 225 then live = live + 1 end
  end
  return live
end

local function count_keys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

emu.addEventCallback(function()
  if entered and end_frames >= 45 and end_frames < 50 then
    emu.setInput({ a = true }, 0)
    pressed = true
  else
    emu.setInput({}, 0)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frames = frames + 1
  if not menu.done() then return end
  game_frames = game_frames + 1

  if not forced and game_frames >= 180 then
    emu.write(A.gameState, 3, W)
    forced = true
  end

  local state = rd(A.gameState)
  if state == 3 then
    entered = true
    end_frames = end_frames + 1
    title_ok = title_ok or title_matches()
    output_images[output_signature()] = true

    -- The C transition spans several emulated frames while forced blank is
    -- active. Judge hardware OAM only once the completed screen has settled;
    -- earlier counts are the invisible final gameplay frame awaiting oam_init.
    if end_frames >= 15 then
      local live = live_oam_count()
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
  elseif entered and pressed and state == 2 and not restart_at then
    restart_at = frames
  end

  if not restart_at or frames < restart_at + 45 then
    if frames < 1200 then return end
  end

  local bg_wrong = match_bg_prefix()
  local image_count = count_keys(output_images)
  local ok = entered and title_ok and screenshot_ok and max_oam == 0
          and restart_at ~= nil and state == 2 and bg_wrong == 0
          and image_count >= 2 and audible_frames >= 1
          and rd(A.spc_alive) == 1
  local rows = {
    string.format("entered=%s end frames=%d title=%s screenshot=%s",
      tostring(entered), end_frames, tostring(title_ok),
      tostring(screenshot_ok)),
    string.format("max OAM=%d restart=%s restored BG prefix wrong=%d",
      max_oam, tostring(restart_at ~= nil), bg_wrong),
    string.format("completion audio images=%d audible frames=%d SPC alive=%d",
      image_count, audible_frames, rd(A.spc_alive)),
    string.format(
      "capture TM=$%02X brightness=%d vscroll=%d CGRAM1=$%04X font wrong=%d",
      capture_tm, capture_brightness, capture_vscroll, capture_cgram1,
      capture_font_wrong),
    string.format("state=%d scroll=%d", state, rd(A.scroll_x, 2)),
    ok and "RESULT: END SCREEN AND SAME-LEVEL RESTART OK" or "RESULT FAIL",
  }
  local f = assert(io.open(OUT .. "end_screen_verify.txt", "w"))
  f:write(table.concat(rows, "\n") .. "\n")
  f:close()
  emu.stop(ok and 0 or 1)
end, emu.eventType.startFrame)
