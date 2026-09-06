-- Does the full ROM respond to the controller?
--
-- The NES polls both pads inside neslib's NMI handler, so every pad_poll() call
-- in SAUCE/ is commented out. This port has no NMI, so the poll lives in
-- ppu_wait_nmi(); without it the game never sees a button.
--
-- Checks two things, because either alone can pass for the wrong reason:
--   1. the decoded pad state reaches the game (joypad1.hold)
--   2. the player actually leaves the ground while the button is held
--
-- setInput takes (table, port) - the opposite order from getInput(port) - and
-- only takes effect from an inputPolled callback (docs/HANDOFF.md trap 6).
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
-- Gameplay, not the level select. main() opens the menu first now, and a
-- script that does not get past it measures a menu - or, worse, writes no
-- report at all and leaves the PREVIOUS run's file to be read as this one's
-- (docs/HANDOFF.md trap 89).
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)

local SETTLE_TO = 260          -- let the level load and the player land
local PRESS_FROM, PRESS_TO = 280, 300
local LAST = 400

local frames, rows = 0, {}
local ground_y, min_y, max_hold = nil, 0xFFFF, 0
local rose = false

local function rd(a) return emu.read(a, emu.memType.snesWorkRam) end
local function rd16(a) return rd(a) + rd(a + 1) * 256 end

local function onInput()
  if frames >= PRESS_FROM and frames <= PRESS_TO then
    emu.setInput({ b = true }, 0)      -- SNES B -> NES A (jump)
  end
end

local function onFrame()
  frames = frames + 1
  local y = rd16(A.player_y)
  local hold = rd(A.joypad1)

  if frames == SETTLE_TO then ground_y = y end
  if frames > SETTLE_TO then
    if hold > max_hold then max_hold = hold end
    if y < min_y then min_y = y end
    if ground_y and y < ground_y then rose = true end
  end

  if frames == LAST then
    local ok = true
    local function say(s) rows[#rows + 1] = s end
    say(string.format("resting y = %04X", ground_y or 0))
    say(string.format("joypad1.hold peak = %02X   (PAD_A = 0x80)", max_hold))
    say(string.format("highest y reached = %04X", min_y))

    if (max_hold & 0x80) == 0 then
      ok = false; say("FAIL: PAD_A never reached the game - input is not being polled")
    end
    if not rose then
      ok = false; say("FAIL: player never rose above its resting height")
    else
      say(string.format("player rose %d px", (ground_y - min_y) // 256))
    end
    say(ok and "RESULT: PASS" or "RESULT: FAIL")
    local f = io.open(OUT .. "input_verify.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(ok and 0 or 1)
  end
end

emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.startFrame)
