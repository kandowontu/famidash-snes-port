-- Verify the vertical tilemap ring on Theory of Everything (level 11).
--
-- The level is 57 metatiles tall. Its true camera top is world y=0, but the
-- original SNES renderer kept only the bottom 64 tile rows and clamped at
-- y=448. This harness moves the camera from y=719 to y=0, then compares every
-- visible tile against an independently decoded 120-row oracle.
local OUT = "C:/famidash-snes-port/out/"
local SA1 = os.getenv("SA1") == "1"
local A = dofile(OUT .. (SA1 and "addrs_sa1.lua" or "addrs_full.lua"))
local menu = not SA1
  and dofile("C:/famidash-snes-port/tools/menu_skip.lua") or nil
local LEVEL = 11
local MAP_BASE = 0x6000
local WORLD_ROWS = 120
local W = SA1 and emu.memType.snesSaveRam or emu.memType.snesWorkRam
local V = emu.memType.snesVideoRam
if not SA1 then menu.start(LEVEL) end

local function slurp(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read("*a")
  f:close()
  return data
end

local oracle = slurp(OUT .. "level_world_expect_11.bin")

local function rd(addr)
  return emu.read(addr, W, false)
end

local function rd16(addr)
  return rd(addr) + rd(addr + 1) * 256
end

local function wr16(addr, value)
  emu.write(addr, value & 0xFF, W)
  emu.write(addr + 1, (value >> 8) & 0xFF, W)
end

local function packed_scroll(linear)
  return ((linear // 240) << 8) | (linear % 240)
end

local function map_word(tile_col, physical_row)
  local slot = tile_col & 63
  local addr = MAP_BASE
             + (slot & 31) + ((slot & 32) ~= 0 and 0x400 or 0)
             + (physical_row & 31) * 32
             + ((physical_row & 32) ~= 0 and 0x800 or 0)
  return emu.read(addr * 2, V, false)
       + emu.read(addr * 2 + 1, V, false) * 256
end

local desired = 719
local forcing = false
local direction = "up"
local reached_top_at
local reached_bottom_at
local top_checked = false
local top_wrong, top_mapping_wrong, top_first_wrong
local video_frames = 0
local game_frames = 0
local force_video_start
local force_game_start
-- SA-1 state is driven at video-frame boundaries, while the game can complete
-- fewer gameplay ticks than video frames. Give it time to consume the final
-- forced camera position before sampling VRAM.
local settle_frames = SA1 and 90 or 10
local sa1_entered = false
local sa1_menu_frames = 0
local sa1_game_frames = 0
local sa1_press = false

local function game_done()
  return SA1 and sa1_entered or menu.done()
end

local function gameplay_frame()
  return SA1 and sa1_game_frames or menu.frame()
end

emu.addEventCallback(function()
  if SA1 then
    emu.setInput(sa1_press and { a = true } or {}, 0)
  elseif menu.done() then
    emu.setInput({}, 0)
  end
end, emu.eventType.inputPolled)

-- Keep collision/sprites from turning this camera-renderer test into an
-- automated playthrough test.
if not SA1 then
  emu.addMemoryCallback(function()
    emu.write(A.cube_data, rd(A.cube_data) & 0xFE, W)
    emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, W)
  end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

  emu.addMemoryCallback(function()
    game_frames = game_frames + 1
  end, emu.callbackType.exec, A.code.everything_else, A.code.everything_else)
end

-- process_y_scroll is immediately before set_scroll_y. Put the camera at the
-- requested packed 240-pixel-room coordinate and keep the player inside the
-- dead zone so the original routine leaves it there.
local function force_camera()
  if not forcing then return end
  if direction == "up" then
    desired = math.max(0, desired - 4)
  else
    desired = math.min(719, desired + 4)
  end
  local packed = packed_scroll(desired)
  wr16(A.scroll_y, packed)
  wr16(A.target_scroll_y, packed)
  emu.write(A.scroll_y_subpx, 0, W)
  wr16(A.currplayer_y, 0x7000)
  wr16(A.player_y, 0x7000)
  wr16(A.player_y + 2, 0x7000)
end

if not SA1 then
  emu.addMemoryCallback(force_camera, emu.callbackType.exec,
    A.code.process_y_scroll, A.code.process_y_scroll)
end

local function check_world_rows(row_first, row_last)
  local origin_tile = rd16(A.level_scroll_origin) >> 3
  local newest = rd16(A.rld_column) - 2
  local first_col = math.max(0, newest - 62)
  local wrong, first_wrong = 0, nil
  local mapping_wrong = 0

  for world_row = row_first, row_last do
    local physical_row = (world_row - origin_tile) & 63
    if rd(A.map_world_row + physical_row) ~= world_row then
      mapping_wrong = mapping_wrong + 1
    end
    for col = first_col, newest do
      local offset = (col * WORLD_ROWS + world_row) * 2
      if offset + 2 <= #oracle then
        local want = oracle:byte(offset + 1) + oracle:byte(offset + 2) * 256
        if (want & 0x03FF) == 0 then
          want = (want & 0xFC00) | 0x00FE
        end
        local got = map_word(col, physical_row)
        if got ~= want then
          wrong = wrong + 1
          first_wrong = first_wrong or string.format(
            "column %d world row %d got %04X expected %04X",
            col, world_row, got, want)
        end
      end
    end
  end
  return wrong, mapping_wrong, first_wrong
end

emu.addEventCallback(function()
  -- SA-1 gameplay state lives in BW-RAM and Mesen does not expose execution
  -- callbacks from the SA-1 CPU. Drive its menu and camera at frame boundaries.
  if SA1 and not sa1_entered then
    if rd(A.shim_menu_active) ~= 0 then
      sa1_menu_frames = sa1_menu_frames + 1
      emu.write(A.menu_sel, LEVEL, W)
      sa1_press = sa1_menu_frames >= 12 and sa1_menu_frames <= 20
    else
      sa1_press = false
      if sa1_menu_frames > 0 and rd(A.gameState) == 2
          and rd(A.level) == LEVEL then
        sa1_entered = true
      end
    end
    return
  end
  if not game_done() then return end
  video_frames = video_frames + 1
  if SA1 then
    sa1_game_frames = sa1_game_frames + 1
    game_frames = game_frames + 1
    emu.write(A.cube_data, rd(A.cube_data) & 0xFE, W)
    emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, W)
  end

  if not forcing and gameplay_frame() > 60 then
    forcing = true
    force_video_start = video_frames
    force_game_start = game_frames
  end
  if SA1 then force_camera() end

  if forcing and desired == 0 and not reached_top_at then
    reached_top_at = video_frames
  end

  if reached_top_at and not top_checked
      and video_frames >= reached_top_at + settle_frames then
    top_wrong, top_mapping_wrong, top_first_wrong =
      check_world_rows(0, 27)
    local stem = SA1 and "sa1_tall_level" or "tall_level"
    local shot_ok, png = pcall(emu.takeScreenshot)
    if shot_ok then
      local image = assert(io.open(OUT .. stem .. ".png", "wb"))
      image:write(png)
      image:close()
    end
    top_checked = true
    direction = "down"
    return
  end
  if top_checked and desired == 719 and not reached_bottom_at then
    reached_bottom_at = video_frames
  end
  if not reached_bottom_at
      or video_frames < reached_bottom_at + settle_frames then return end

  -- At y=719 the viewport covers world tile rows 89-117.
  local bottom_wrong, bottom_mapping_wrong, bottom_first_wrong =
    check_world_rows(89, 117)
  do
    local shot_ok, png = pcall(emu.takeScreenshot)
    if shot_ok then
      local stem = SA1 and "sa1_tall_level_bottom.png"
                             or "tall_level_bottom.png"
      local image = assert(io.open(OUT .. stem, "wb"))
      image:write(png)
      image:close()
    end
  end
  local origin_tile = rd16(A.level_scroll_origin) >> 3
  local min_scroll = rd16(A.min_scroll_y)
  local live_scroll = rd16(A.scroll_y)
  local drops = rd16(A.shim_row_drops)
  local elapsed_video = video_frames - force_video_start
  local elapsed_game = game_frames - force_game_start
  local rate = 100 * elapsed_game / elapsed_video
  local ok = min_scroll == 0 and live_scroll == 0x02EF
          and top_mapping_wrong == 0 and top_wrong == 0
          and bottom_mapping_wrong == 0 and bottom_wrong == 0
          and drops == 0

  local rows = {
    string.format("build=%s level=11 height=57", SA1 and "SA-1" or "HiROM"),
    string.format("camera min=%04X live=%04X origin=%dpx",
                  min_scroll, live_scroll, origin_tile * 8),
    string.format("top rows 0-27: mapping wrong=%d tile words wrong=%d",
                  top_mapping_wrong, top_wrong),
    string.format("bottom rows 89-117 after return: mapping wrong=%d "
                  .. "tile words wrong=%d",
                  bottom_mapping_wrong, bottom_wrong),
    string.format("vertical row drops=%d forced-scroll rate=%.1f%% (%d/%d)",
                  drops, rate, elapsed_game, elapsed_video),
    (top_first_wrong or bottom_first_wrong)
      and ("first mismatch: " .. (top_first_wrong or bottom_first_wrong))
      or "both visible bands match the 120-row oracle",
    ok and "RESULT: TALL LEVEL CEILING OK" or
           "RESULT: TALL LEVEL CEILING FAIL",
  }
  local result = table.concat(rows, "\n") .. "\n"
  local stem = SA1 and "sa1_tall_level" or "tall_level"
  local f = assert(io.open(OUT .. stem .. "_verify.txt", "w"))
  f:write(result)
  f:close()
  print(result)
  emu.stop(ok and 0 or 1)
end, emu.eventType.startFrame)
