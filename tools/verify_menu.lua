-- Does the level select actually SHOW the level list, and does it scroll?
--
-- A screenshot only proves something was drawn. This reads the BG1 tilemap back
-- and decodes it as text - the font is indexed by character code, so a tile
-- index IS its ASCII value - then checks the names against what the ROM's
-- level_names table says they should be.
--
-- It also holds DOWN long enough to walk past the bottom of the window, which is
-- the part a first-frame screenshot cannot show: with 46 levels and 22 rows the
-- list has to scroll, and menu_top is only recomputed on the frames where the
-- selection leaves the window.
--
--   "C:/mesen2/Mesen.exe" --testrunner out/famidash-snes-full.sfc tools/verify_menu.lua
--
-- Expected names come from out/menu_expect.txt (tools/gen_levels.py writes it),
-- so this does not hardcode a level set.

local OUT   = "C:/famidash-snes-port/out/"
local MAP   = 0x6000            -- VRAM_BG1MAP, in words
local TOP   = 3                 -- MENU_TOP
local LEFT  = 6                 -- MENU_LEFT
local ROWS  = 22                -- MENU_ROWS
local NAMEW = 23                -- LEVEL_NAME_W

local expect = {}
for line in io.lines(OUT .. "menu_expect.txt") do
  expect[#expect + 1] = line
end

-- Read one tilemap row back as a string. The tilemap word is pppcc cccccccc, so
-- the low byte is the character.
local function readrow(row, col, n)
  local s = {}
  for i = 0, n - 1 do
    local w = emu.read((MAP + (row % 32) * 32 + ((col + i) % 32)) * 2,
                       emu.memType.snesVideoRam, false)
    s[#s + 1] = string.char(w)
  end
  return table.concat(s)
end

local function window()
  local names = {}
  for r = 0, ROWS - 1 do
    local s = readrow(TOP + r, LEFT, NAMEW):gsub("%s+$", "")
    if s ~= "" then names[#names + 1] = s end
  end
  return names
end

local function cursor()
  for r = 0, ROWS - 1 do
    if readrow(TOP + r, LEFT - 2, 1) == ">" then return r end
  end
  return -1
end

local A = dofile(OUT .. "addrs_full.lua")
local function sel() return emu.read(A.menu_sel, emu.memType.snesWorkRam, false) end

local n, stage, bad, checked, settle = 0, 0, 0, 0, 0
local WRAP_UP = -2   -- sentinel: hold UP to test the wrap at the top

-- HOLD the direction, which is now the thing under test: the menu auto-repeats,
-- so a held button walks the list instead of moving once. It used to need a
-- duty cycle - hold 8 frames, release 8 - because only the press edge moved the
-- selection, and 167 taps is not a menu.
local want = -1
emu.addEventCallback(function()
  if want < 0 then return end
  if sel() >= want then return end
  -- HOLD while far away - the menu auto-repeats and takes several rows a step
  -- once it is up to speed, which is the thing under test. TAP for the last few
  -- rows: a held button would overshoot the target by up to a full fast step
  -- and then wrap round the bottom, and the walk would never terminate.
  if want - sel() > 12 then
    emu.setInput({ down = true }, 0)
  elseif (math.floor(n / 8) % 2) == 0 then
    emu.setInput({ down = true }, 0)
  end
end, emu.eventType.inputPolled)

local function check(label, top)
  local got = window()
  local cur = cursor()
  local shown = math.min(ROWS, #expect - top)
  if #got ~= shown then
    print(string.format("  %s: %d rows on screen, expected %d (cursor row %d)",
                        label, #got, shown, cur))
    for i = 1, #got do print("      " .. got[i]) end
    bad = bad + 1
    return
  end
  for i = 1, #got do
    checked = checked + 1
    if got[i] ~= expect[top + i] then
      print(string.format("  %s row %d: %q, expected %q",
                          label, i - 1, got[i], expect[top + i]))
      bad = bad + 1
    end
  end
  print(string.format("  %s: rows %d-%d correct, cursor on row %d (%s)",
                      label, top, top + #got - 1, cur, got[cur + 1] or "?"))
end

emu.addEventCallback(function()
  n = n + 1
  if stage == 0 and window()[1] == expect[1] and cursor() == 0 then
    -- Fresh menu: the window starts at the top and the cursor is on row 0.
    check("initial", 0)
    want = #expect - 1          -- walk to the last level
    stage = 1
  elseif stage == 0 and n > 600 then
    print("  gave up waiting for the initial menu")
    emu.stop(1)
  elseif stage == 1 and (n % 240) == 0 then
    print(string.format("  ... frame %d, selection %d/%d", n, sel(), want))
    if n > 6000 then print("  gave up waiting"); emu.stop(1) end
  elseif stage == 1 and sel() >= want then
    stage, settle = 2, n + 30   -- a redraw is 1024 tilemap writes in forced
                                -- blank and outlives the frame that started it;
                                -- reading the map immediately catches it half
                                -- written and looks like missing rows.
  elseif stage == 2 and n >= settle then
    -- The selection is on the last level, so the window has scrolled to show it
    -- as its bottom row.
    check("scrolled", #expect - ROWS)
    local png = emu.takeScreenshot()
    local f = io.open(OUT .. "menu_bottom.png", "wb"); f:write(png); f:close()
    print(bad == 0 and string.format("RESULT: MENU OK (%d names verified)", checked)
                    or string.format("RESULT: FAIL - %d problem(s)", bad))
    emu.stop(bad == 0 and 0 or 1)
  end
end, emu.eventType.startFrame)
