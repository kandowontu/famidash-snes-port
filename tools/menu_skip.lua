-- Get past the level select, so a verifier can go on measuring the game.
--
-- Every verify_*.lua used to boot straight into gameplay. Now main() opens
-- level_select() first, and a script that just waits N frames and reads the
-- world measures a menu instead - silently, because the menu is a perfectly
-- valid screen. That is what this exists to prevent.
--
--   local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
--   menu.start(0)                       -- or menu.start(tonumber(os.getenv"LEVEL"))
--
-- `menu.done()` reports whether the game has been entered yet, for scripts that
-- want to count frames from the start of gameplay rather than from reset.
--
-- Input is a DUTY CYCLE, not a tap: the shim derives a press edge, so a button
-- held across consecutive polls moves once; inputPolled fires more than once per
-- pad_poll; and a menu redraw is 1024 tilemap writes in forced blank, so an
-- iteration outlives its frame. Anything narrower than several frames drops
-- presses. See the header of tools/verify_menu.lua.

local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")

local M = {}
local STATE_GAME = 0x02

local want, entered, n, confirms = nil, false, 0, 0

local function sel() return emu.read(A.menu_sel, emu.memType.snesWorkRam, false) end
local function state() return emu.read(A.gameState, emu.memType.snesWorkRam, false) end

-- Is level_select() actually on screen yet?
--
-- A frame count is not proof of this and guessing cost two rounds of one flaky
-- level in 46. inputPolled fires on the hardware auto-joypad read every frame,
-- including while the C runtime is still clearing BSS and video_init is running
-- - so a poke of menu_sel can land before the menu exists, be wiped by the BSS
-- clear, and leave START going in against a selection of 0.
--
-- menu_draw() writes the title at tilemap (8,1), and the font is indexed by
-- character code, so that cell reading 'F' means the menu has been drawn. Any
-- poke after that is one the menu will actually use.
-- Is level_select() actually running?
--
-- A FLAG the menu sets, not a guess from the screen. This looked for the
-- title's 'F' in the tilemap, and at boot - before the menu has drawn - that
-- byte can already be $46: the poke then landed before level_select() existed,
-- was lost, and START went in against a selection of 0. Every scripted run
-- played level 0 and reported a perfectly plausible frame rate for it, which is
-- exactly the failure the post-entry assertion below exists to catch.
local function menu_is_up()
  return emu.read(A.shim_menu_active, emu.memType.snesWorkRam, false) ~= 0
end

-- Start the given level (0 = the first). Call once, at the top of the script.
function M.start(level)
  want = level or 0
  emu.addEventCallback(function() n = n + 1 end, emu.eventType.startFrame)
  emu.addEventCallback(function()
    -- The GAME's state is the signal that the menu is behind us, not a flag of
    -- our own. Setting a flag when we first press START looked like it worked
    -- and was wrong: the first polls happen during video_init, before the menu
    -- loop is even running, so the one press went nowhere and every verifier
    -- then measured a menu it thought it had left.
    if entered then return end
    if state() == STATE_GAME then
      entered, M.entered_at = true, n
      -- Say so loudly if the wrong level started. Silently measuring level 0
      -- while believing it is level 9 is the worst outcome available here.
      local got = emu.read(A.level, emu.memType.snesWorkRam, false)
      if got ~= want then
        print(string.format("menu_skip: HARNESS ERROR - asked for level %d, "
                            .. "the game started level %d", want, got))
      end
      return
    end
    if not menu_is_up() then return end
    if (math.floor(n / 8) % 2) ~= 0 then return end     -- release half
    -- POKE the selection rather than walking to it. Pressing DOWN 45 times at
    -- eight frames a press costs 720 frames before the level even loads, and
    -- what a verifier wants from this file is to be in the level - navigating
    -- the menu is verify_menu.lua's job, and duplicating it here only makes
    -- every other script slower and able to fail for a reason it is not
    -- testing.
    if sel() ~= want then
      emu.write(A.menu_sel, want, emu.memType.snesWorkRam)
      confirms = 0
      return                            -- let the menu redraw before START
    end
    -- Confirm the selection on two separate polls before committing to it, so
    -- a value that is about to be overwritten cannot be the one START acts on.
    confirms = confirms + 1
    if confirms < 2 then return end
    emu.setInput({ start = true }, 0)
  end, emu.eventType.inputPolled)
end

-- Frames since gameplay began, or 0 while still in the menu.
function M.frame() return entered and (n - M.entered_at) or 0 end

function M.done() return entered end

return M
