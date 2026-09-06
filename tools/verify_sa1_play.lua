-- Does the SA-1 build actually PLAY - not just boot and pace frames?
--
-- verify_sa1_game covers the menu, and passed for a long time while gameplay
-- rendered nothing, so it is not evidence about the level at all. This drives
-- the ROM the way a player does: wait for the level select, press A, and then
-- check the things that can only be true if the whole split is working.
--
--   the frame rate in-level, counted as COUNTER TRANSITIONS. drawing_frame is a
--   byte; differencing it across 600 frames reported 3% where the truth was
--   99%, because 530 increments wrap to 18. Never difference it.
--   the BG1 tilemap is populated - the level's geometry reached VRAM through
--   the S-CPU's column DMAs;
--   CGRAM matches PAL_BUF - the level's own colours arrived, rather than the
--   menu palette it starts from;
--   scroll_x moves - the game is running, not painting one frame forever.
--
--   "C:/mesen2/Mesen.exe" --testrunner out/famidash-sa1-full.sfc tools/verify_sa1_play.lua

local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")

-- Input MUST be injected from inputPolled. From endFrame it lands after the
-- console has latched, and the ROM looks like it ignores the controller.
local n, press = 0, false
local title_polls, level_polls = 0, 0
local function rd8(a)  return emu.read(a, emu.memType.snesSaveRam, false) end
local function rd16(a) return rd8(a) | (rd8(a + 1) << 8) end
emu.addEventCallback(function()
  local screen = rd8(A.fami_screen)
  if screen == 1 then
    title_polls = title_polls + 1
    press = title_polls >= 30 and title_polls <= 36
  elseif screen == 2 and rd8(A.gameState) ~= 2 then
    level_polls = level_polls + 1
    press = level_polls >= 30 and level_polls <= 36
  else
    press = rd8(A.gameState) == 2
  end
  if press then
    emu.setInput({ a = true }, 0)
  else
    emu.setInput({}, 0)
  end
end, emu.eventType.inputPolled)

local adv, last = 0, -1
local scroll = {}
local game_frames = 0

local function cgword(i)
  return emu.read(i * 2, emu.memType.snesCgRam, false)
       | (emu.read(i * 2 + 1, emu.memType.snesCgRam, false) << 8)
end
local function palword(i) return rd16(A.PAL_BUF + i * 2) end

emu.addEventCallback(function()
  n = n + 1
  -- Select the level, then HOLD jump. Without input the cube cannot clear the
  -- first obstacle, dies, restarts, and does it forever - which is what "loads
  -- a level and sits there" looks like, and was the real bug: pad_poll was
  -- missing from ppu_wait_nmi's SA-1 branch, so gameplay saw no buttons at all
  -- while the menu, which polls for itself, worked fine.
  local d = rd8(A.drawing_frame)
  local playing = rd8(A.gameState) == 2 and rd8(A.shim_menu_active) == 0
  if playing then
    game_frames = game_frames + 1
    if game_frames > 30 and d ~= last then adv = adv + 1 end
  end
  last = d
  -- Sample often and keep the LARGEST forward step seen. The level auto-
  -- scrolls, dies and restarts from 0, so two samples far apart can land either
  -- side of a restart and show almost no movement - which is how an earlier
  -- version of this check passed on 547 -> 600 across 600 frames and called a
  -- barely-moving game "playing".
  if playing and game_frames > 30 and game_frames % 30 == 0 then
    local x = rd16(A.scroll_x)
    if scroll.prev and x > scroll.prev then
      local d = x - scroll.prev
      if d > (scroll.best or 0) then scroll.best = d end
    end
    scroll.prev = x
    scroll.max = math.max(scroll.max or 0, x)
  end

  if game_frames < 690 and n < 5000 then return end

  local log = {}
  local function say(s) log[#log + 1] = s end

  local tiles = 0
  for w = 0x6000, 0x6FFF do
    if emu.read(w * 2, emu.memType.snesVideoRam, false) ~= 0 then
      tiles = tiles + 1
    end
  end

  local pal_ok = true
  for p = 0, 3 do
    if cgword(p * 16 + 4) ~= palword(0) then pal_ok = false end
    for color = 1, 3 do
      if cgword(p * 16 + color) ~= palword(p * 4 + color) then
        pal_ok = false
      end
    end
  end
  local bg2_want = palword(1)
  if palword(0) ~= 0 and bg2_want == palword(0) then bg2_want = 0 end
  if cgword(65) ~= bg2_want then pal_ok = false end

  local in_level = rd8(A.shim_menu_active) == 0
  local measured = math.max(1, game_frames - 30)
  local rate = 100 * adv / measured
  -- The measured rate is ~83 units per 30 frames (~2.8/frame), so 50 is a
  -- comfortable floor that still fails a stalled game, and a peak past 1000
  -- means the level really ran rather than twitching at the start line.
  local moved = (scroll.best or 0) > 50 and (scroll.max or 0) > 1000

  say(string.format("left the menu:        %s", tostring(in_level)))
  say(string.format("frame rate in-level:  %d/%d (%.0f%% of 60Hz)",
                    adv, measured, rate))
  say(string.format("BG1 tilemap written:  %d/4096 tiles", tiles))
  say(string.format("CGRAM matches PAL_BUF: %s", tostring(pal_ok)))
  say(string.format("scroll_x advancing:   %s (best 30-frame step %d, peak %d)",
                    tostring(moved), scroll.best or 0, scroll.max or 0))

  local ok = in_level and game_frames >= 690 and rate > 90
          and tiles > 100 and pal_ok and moved
  say("")
  say("RESULT " .. (ok and "OK - the SA-1 build plays: level entered, 60Hz, "
                        .. "geometry and colours on screen, level scrolling"
                      or "FAIL - see the lines above"))

  local f = io.open(OUT .. "sa1_play.txt", "w")
  f:write(table.concat(log, "\n") .. "\n")
  f:close()
  emu.stop(ok and 0 or 1)
end, emu.eventType.endFrame)
