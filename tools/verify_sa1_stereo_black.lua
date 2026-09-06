-- Verify Stereo Madness's intentional all-black parallax transition on SA-1.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local B = emu.memType.snesSaveRam
local C = emu.memType.snesCgRam
local LEVEL = 0

local function rd(addr)
  return emu.read(addr, B, false)
end

local function rd16(addr)
  return rd(addr) + rd(addr + 1) * 256
end

local function wr16(addr, value)
  emu.write(addr, value & 0xFF, B)
  emu.write(addr + 1, (value >> 8) & 0xFF, B)
end

local function wr32(addr, value)
  wr16(addr, value & 0xFFFF)
  wr16(addr + 2, (value >> 16) & 0xFFFF)
end

local function cgword(index)
  return emu.read(index * 2, C, false)
       + emu.read(index * 2 + 1, C, false) * 256
end

local entered = false
local menu_frames = 0
local game_frames = 0
local press = false
local max_scroll = 0
local last_raw_bg = -1
local palette_trace = {}
local black_seen_at
local WARP_SCROLL = 4200
local MAP_TARGET = (WARP_SCROLL >> 3) + 40

emu.addEventCallback(function()
  emu.setInput((press or entered) and { a = true } or {}, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not entered then
    if rd(A.shim_menu_active) ~= 0 then
      menu_frames = menu_frames + 1
      emu.write(A.menu_sel, LEVEL, B)
      press = menu_frames >= 30 and menu_frames <= 45
    else
      press = false
      if menu_frames > 0 and rd(A.gameState) == 2
          and rd(A.level) == LEVEL then
        entered = true
      end
    end
    return
  end

  game_frames = game_frames + 1
  -- The black $8F color object is at world x=4336. Put the player at its real
  -- screen position; check_spr_objects still walks the original stream and
  -- sprite_collide still performs the actual color change.
  if game_frames >= 60 then
    wr32(A.scroll_x, WARP_SCROLL)
    wr16(A.currplayer_x, 0x8000)
    wr16(A.player_x, 0x8000)
    wr16(A.player_x + 2, 0x8000)
  end
  -- Reach it without a death resetting the sprite stream.
  emu.write(A.DEBUG_MODE, 3, B)
  emu.write(A.invincible_counter, 0xFF, B)
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, B)
  emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, B)
  wr16(A.currplayer_y, 0xB000)
  wr16(A.player_y, 0xB000)
  wr16(A.player_y + 2, 0xB000)
  wr16(A.currplayer_vel_y, 0)
  wr16(A.player_vel_y, 0)
  wr16(A.player_vel_y + 2, 0)

  local raw_bg = rd(A.PAL_BUF_RAW)
  local raw_ink = rd(A.PAL_BUF_RAW + 1)
  local backdrop = cgword(0)
  local bg2_ink = cgword(65)
  local scroll = rd16(A.scroll_x)
  max_scroll = math.max(max_scroll, scroll)
  if raw_bg ~= last_raw_bg then
    palette_trace[#palette_trace + 1] = string.format(
      "%d:%d:%02X/%02X", game_frames, scroll, raw_bg, raw_ink)
    last_raw_bg = raw_bg
  end
  if raw_bg == 0x0F and raw_ink == 0x0F
      and backdrop == 0 and bg2_ink == 0 then
    black_seen_at = black_seen_at or game_frames
  end

  -- A camera warp makes draw_screen stream forward from the level start. Wait
  -- until every column needed by this viewport is resident before capturing.
  if black_seen_at and rd16(A.rld_column) >= MAP_TARGET
      and game_frames >= black_seen_at + 10 then
    local result = table.concat({
      string.format("level=Stereo Madness frame=%d scroll=%d",
        game_frames, scroll),
      string.format("raw palette backdrop/ink=%02X/%02X", raw_bg, raw_ink),
      string.format("CGRAM backdrop/BG2 ink=%04X/%04X",
        backdrop, bg2_ink),
      "RESULT: SA-1 STEREO BLACK TRANSITION OK",
      "palette trace: " .. table.concat(palette_trace, " | "),
    }, "\n") .. "\n"
    local f = assert(io.open(OUT .. "sa1_stereo_black_verify.txt", "w"))
    f:write(result)
    f:close()
    local shot_ok, png = pcall(emu.takeScreenshot)
    if shot_ok and png and #png > 0 then
      f = assert(io.open(OUT .. "sa1_stereo_black.png", "wb"))
      f:write(png)
      f:close()
    end
    print(result)
    emu.stop(0)
    return
  end

  if game_frames >= 1200 then
    local f = assert(io.open(OUT .. "sa1_stereo_black_verify.txt", "w"))
    f:write(string.format(
      "timeout raw=%02X/%02X CGRAM=%04X/%04X max scroll=%d\n"
      .. "palette trace: %s\n"
      .. "RESULT: SA-1 STEREO BLACK TRANSITION FAIL\n",
      raw_bg, raw_ink, backdrop, bg2_ink, max_scroll,
      table.concat(palette_trace, " | ")))
    f:close()
    emu.stop(1)
  end
end, emu.eventType.startFrame)
