-- Capture Ground to Space from the SA-1 port and report its level palette.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local B = emu.memType.snesSaveRam
local C = emu.memType.snesCgRam
local TARGET = 52
local title_polls = 0
local selector_polls = 0
local selector_seen = false
local game_frames = 0
local total = 0
local rows = {}
local trigger_seen = false
local failures = {}

local function rd(a)
  return emu.read(a, B, false)
end

local function cgword(i)
  return emu.read(i * 2, C, false)
       | (emu.read(i * 2 + 1, C, false) << 8)
end

emu.addEventCallback(function()
  local screen = rd(A.fami_screen)
  local press = false
  if screen == 1 and not selector_seen then
    title_polls = title_polls + 1
    emu.write(A.menuselection, 1, B)
    local phase = title_polls % 60
    press = phase >= 15 and phase <= 45
  elseif rd(A.shim_menu_active) ~= 0 then
    selector_seen = true
    selector_polls = selector_polls + 1
    emu.write(A.normalorcommlevels, 1, B)
    emu.write(A.level, TARGET, B)
    local phase = selector_polls % 60
    press = phase >= 15 and phase <= 45
  end
  emu.setInput(press and { a = true } or {}, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  total = total + 1
  local playing = selector_seen and rd(A.shim_menu_active) == 0
                  and rd(A.gameState) == 2 and rd(A.level) == TARGET
  if not playing then
    if total == 2400 then
      local f = assert(io.open(OUT .. "ground_to_space_sa1.txt", "w"))
      f:write(string.format("timeout state=%d level=%d menu=%d\nRESULT: FAIL\n",
                            rd(A.gameState), rd(A.level),
                            rd(A.shim_menu_active)))
      f:close()
      emu.stop(1)
    end
    return
  end

  game_frames = game_frames + 1
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, B)
  emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, B)
  if cgword(0) == 0x6404 then
    trigger_seen = true
    if cgword(1) ~= 0 or cgword(4) ~= 0x6404 then
      failures[#failures + 1] = string.format(
        "frame %d collapsed: backdrop=%04X ink=%04X opaque=%04X",
        game_frames, cgword(0), cgword(1), cgword(4))
    end
  end
  if game_frames % 60 == 0 then
    local ok, png = pcall(emu.takeScreenshot)
    if ok and png then
      local image = assert(io.open(
        OUT .. string.format("ground_to_space_sa1_%03d.png", game_frames),
        "wb"))
      image:write(png)
      image:close()
    end
    local state = emu.getState()
    rows[#rows + 1] = string.format(
      "frame=%d scroll_x=%d phase=%d cgram=%04X,%04X,%04X "
      .. "tile0=%02X,%02X alt0=%02X,%02X bgbase=%s",
      game_frames, rd(A.scroll_x) | (rd(A.scroll_x + 1) << 8),
      rd(A.parallax_scroll_x) & 1, cgword(0), cgword(1), cgword(4),
      emu.read(0, emu.memType.snesVideoRam, false),
      emu.read(16, emu.memType.snesVideoRam, false),
      emu.read(0x2000, emu.memType.snesVideoRam, false),
      emu.read(0x2010, emu.memType.snesVideoRam, false),
      tostring(state["ppu.layers[0].tilemapAddress"]))
  end
  if game_frames == 600 then
    local pass = trigger_seen and #failures == 0
    local f = assert(io.open(OUT .. "ground_to_space_sa1.txt", "w"))
    f:write(string.format(
      "state=%d level=%d no_parallax=%d trigger_seen=%s failures=%d\n%s\n%s"
      .. "RESULT: %s\n",
      rd(A.gameState), rd(A.level), rd(A.no_parallax),
      tostring(trigger_seen), #failures, table.concat(rows, "\n"),
      failures[1] and ("first failure: " .. failures[1] .. "\n") or "",
      pass and "SA-1 GROUND TO SPACE MATCHES NES" or "FAIL"))
    f:close()
    emu.stop(pass and 0 or 1)
  end
end, emu.eventType.startFrame)
