-- Visual/behavior smoke test for the original Famidash title, level selector,
-- and level-complete screens on the SA-1 build.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local B = emu.memType.snesSaveRam

local frame = 0
local screen_frames = 0
local last_screen = 0
local entered_game = false
local selector_seen = false
local forced_end = false
local end_frames = 0
local game_frames = 0
local palette_exit_ok = false
local input = {}
local captures = {}

local function rd(a)
  return emu.read(a, B, false)
end

local function rd16(a)
  return rd(a) | (rd(a + 1) << 8)
end

local function cgword(i)
  return emu.read(i * 2, emu.memType.snesCgRam, false)
       | (emu.read(i * 2 + 1, emu.memType.snesCgRam, false) << 8)
end

local function shot(name)
  local ok, png = pcall(emu.takeScreenshot)
  if not ok or not png then
    captures[#captures + 1] = name .. ":ERROR:" .. tostring(png)
    return false
  end
  local f = assert(io.open(OUT .. name, "wb"))
  f:write(png)
  f:close()
  captures[#captures + 1] = name
  return true
end

local function compare_file(path, base, memtype)
  local f = assert(io.open(OUT .. path, "rb"))
  local data = f:read("*a")
  f:close()
  local wrong = 0
  for i = 1, #data do
    if emu.read(base + i - 1, memtype, false) ~= data:byte(i) then
      wrong = wrong + 1
    end
  end
  return wrong, #data
end

emu.addEventCallback(function()
  if entered_game and rd(A.gameState) == 2 then
    game_frames = game_frames + 1
    if game_frames == 60 then
      local match = true
      for p = 0, 3 do
        if cgword(p * 16 + 4) ~= rd16(A.PAL_BUF) then match = false end
        for color = 1, 3 do
          if cgword(p * 16 + color)
             ~= rd16(A.PAL_BUF + (p * 4 + color) * 2) then
            match = false
          end
        end
      end
      palette_exit_ok = match
        and rd(A.fami_dirty_pages) == 0
        and rd(A.fami_palette_dirty) == 0
      shot("sa1_game_palette_exit.png")
    end
    if game_frames >= 120 and not forced_end then
      emu.write(A.coins, 7, B)
      emu.write(A.gameState, 3, B)
      forced_end = true
    end
  end
  emu.setInput(input, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frame = frame + 1
  local screen = rd(A.fami_screen)
  if screen == 2 then selector_seen = true end
  if screen ~= last_screen then
    last_screen = screen
    screen_frames = 0
    input = {}
  else
    screen_frames = screen_frames + 1
  end

  if selector_seen and rd(A.gameState) == 2
     and rd(A.shim_menu_active) == 0 and not entered_game then
    entered_game = true
    input = {}
  end

  if entered_game and rd(A.gameState) == 2 then
    input = {}
  elseif screen == 1 then
    if screen_frames == 90 then
      shot("sa1_famidash_title.png")
      local tw, tn = compare_file(
        "famidash_menu_bg.tiles.bin", 0, emu.memType.snesVideoRam)
      local mw, mn = compare_file(
        "famidash_title.map.bin", 0x6000 * 2,
        emu.memType.snesVideoRam)
      local f = assert(io.open(OUT .. "sa1_famidash_title_memory.txt", "w"))
      f:write(string.format("tiles wrong=%d/%d map wrong=%d/%d\n",
                            tw, tn, mw, mn))
      f:close()
    end
    input = (screen_frames >= 100 and screen_frames <= 125) and { a = true } or {}
  elseif screen == 2 and not entered_game then
    if screen_frames == 45 then shot("sa1_famidash_level_select.png") end
    if screen_frames >= 60 and screen_frames <= 85 then
      input = { a = true }
    else
      input = {}
    end
  elseif forced_end and rd(A.gameState) == 3 then
    end_frames = end_frames + 1
    input = {}
    if end_frames == 20 then shot("sa1_famidash_end_bounce.png") end
    if end_frames == 220 then
      shot("sa1_famidash_end_final.png")
      local f = assert(io.open(OUT .. "sa1_famidash_menus_audit.txt", "w"))
      f:write("captures=" .. table.concat(captures, ",") .. "\n")
      f:write(string.format(
        "title=%s level=%s game=%s game_frames=%d end=%s\n"
        .. "game_palette_restored=%s\n"
        .. "RESULT: %s\n",
        tostring(last_screen >= 1), tostring(entered_game),
        tostring(forced_end), game_frames, tostring(end_frames >= 220),
        tostring(palette_exit_ok),
        palette_exit_ok and "NATIVE MENU FLOW OK" or "FAIL")))
      f:write(string.format("SETINI=%02X\n",
        emu.read(0x2133, emu.memType.snesMemory, false)))
      local state = emu.getState()
      for key, value in pairs(state) do
        if key:lower():find("overscan") or key:lower():find("height") then
          f:write(tostring(key) .. "=" .. tostring(value) .. "\n")
        end
      end
      f:close()
      emu.stop(palette_exit_ok and 0 or 1)
    end
  end

  if frame > 4000 then
    local f = assert(io.open(OUT .. "sa1_famidash_menus_audit.txt", "w"))
    f:write(string.format(
      "timeout frame=%d screen=%d screen_frames=%d state=%d\nRESULT FAIL\n",
      frame, screen, screen_frames, rd(A.gameState)))
    f:close()
    emu.stop(1)
  end
end, emu.eventType.startFrame)
