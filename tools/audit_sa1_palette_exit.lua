-- Verify that leaving the native selector restores the selected level's
-- palette and retires all menu-owned transfer flags on the SA-1 build.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local B = emu.memType.snesSaveRam
local input = {}
local title_polls = 0
local selector_polls = 0
local selector_seen = false
local game_frames = 0
local total_frames = 0

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

local function write_report(ok, reason)
  local f = assert(io.open(OUT .. "sa1_palette_exit.txt", "w"))
  f:write("reason=" .. reason .. "\n")
  f:write(string.format(
    "screen=%d state=%d game_frames=%d dirty=%d palette_dirty=%d\n",
    rd(A.fami_screen), rd(A.gameState), game_frames,
    rd(A.fami_dirty_pages), rd(A.fami_palette_dirty)))
  f:write("RESULT: " .. (ok and "SA-1 GAME PALETTE RESTORED" or "FAIL") .. "\n")
  f:close()
  emu.stop(ok and 0 or 1)
end

emu.addEventCallback(function()
  local screen = rd(A.fami_screen)
  if screen == 1 then
    title_polls = title_polls + 1
    input = (title_polls >= 45 and title_polls <= 80) and { a = true } or {}
  elseif screen == 2 then
    selector_seen = true
    selector_polls = selector_polls + 1
    input = (selector_polls >= 45 and selector_polls <= 80) and { a = true } or {}
  else
    input = {}
  end
  emu.setInput(input, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  total_frames = total_frames + 1
  local playing = selector_seen and rd(A.gameState) == 2
                  and rd(A.shim_menu_active) == 0
  if playing then
    game_frames = game_frames + 1
  end
  if game_frames == 60 then
    local palette_ok = true
    for p = 0, 3 do
      if cgword(p * 16 + 4) ~= rd16(A.PAL_BUF) then
        palette_ok = false
      end
      for color = 1, 3 do
        if cgword(p * 16 + color)
           ~= rd16(A.PAL_BUF + (p * 4 + color) * 2) then
          palette_ok = false
        end
      end
    end
    local flags_ok = rd(A.fami_dirty_pages) == 0
                     and rd(A.fami_palette_dirty) == 0
    local shot_ok, png = pcall(emu.takeScreenshot)
    if shot_ok and png then
      local f = assert(io.open(OUT .. "sa1_game_palette_exit.png", "wb"))
      f:write(png)
      f:close()
    end
    write_report(palette_ok and flags_ok,
                 string.format("palette=%s flags=%s",
                               tostring(palette_ok), tostring(flags_ok)))
  elseif total_frames == 1800 then
    write_report(false, "timeout before 60 gameplay frames")
  end
end, emu.eventType.startFrame)
