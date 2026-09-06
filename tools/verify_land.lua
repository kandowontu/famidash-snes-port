-- Verify the cube falls, comes to rest, and jumps.
--
-- Trap #2 in docs/HANDOFF.md: two matching samples of a periodic system prove
-- nothing. So this does not sample - it checks every frame in a wide window and
-- reports the min/max seen, which a repeating fall cycle cannot pass.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs.lua")

local REST_FROM, REST_TO = 60, 400   -- must be at rest for this whole window
local JUMP_AT, JUMP_HOLD = 420, 6    -- press A here
local LAST = 700

local frames = 0
local rest = { ymin = 0xFFFF, ymax = 0, vmin = 0x7FFF, vmax = -0x8000 }
local jump = { ymin = 0xFFFF, ymax = 0, vmin = 0x7FFF, vmax = -0x8000, landed = nil }
local restY

local function rd(a) return emu.read(a, emu.memType.snesWorkRam) end
local function rd16(a) return rd(a) + rd(a + 1) * 256 end
local function s16(a)
  local v = rd16(a)
  return v >= 0x8000 and v - 0x10000 or v
end

local function track(t, y, v)
  if y < t.ymin then t.ymin = y end
  if y > t.ymax then t.ymax = y end
  if v < t.vmin then t.vmin = v end
  if v > t.vmax then t.vmax = v end
end

local function onFrame()
  frames = frames + 1
  local y, v = rd16(A.currplayer_y), s16(A.currplayer_vel_y)

  if frames >= REST_FROM and frames <= REST_TO then
    track(rest, y, v)
    restY = y
  elseif frames > JUMP_AT and frames <= LAST then
    track(jump, y, v)
    if jump.landed == nil and frames > JUMP_AT + JUMP_HOLD + 4 and v == 0 then
      jump.landed = { frame = frames, y = y }
    end
  end

  if frames == LAST then
    local ok = true
    local out = {}
    local function say(s) out[#out + 1] = s end

    say(string.format("rest window  frames %d-%d", REST_FROM, REST_TO))
    say(string.format("  y   min=%04X max=%04X", rest.ymin, rest.ymax))
    say(string.format("  vel min=%d max=%d", rest.vmin, rest.vmax))
    if rest.ymin ~= rest.ymax then
      ok = false; say("  FAIL: y moved while it should have been at rest")
    end
    if rest.vmin ~= 0 or rest.vmax ~= 0 then
      ok = false; say("  FAIL: vel_y nonzero while it should have been at rest")
    end

    say(string.format("jump  A held frames %d-%d", JUMP_AT, JUMP_AT + JUMP_HOLD - 1))
    say(string.format("  y   min=%04X max=%04X  (rest y was %04X)", jump.ymin, jump.ymax, restY or 0))
    say(string.format("  vel min=%d max=%d", jump.vmin, jump.vmax))
    if jump.vmin >= 0 then
      ok = false; say("  FAIL: no upward velocity - the jump never fired")
    end
    if restY and jump.ymin >= restY then
      ok = false; say("  FAIL: player never rose above its resting height")
    end
    if jump.landed then
      say(string.format("  landed again at frame %d, y=%04X", jump.landed.frame, jump.landed.y))
      if restY and jump.landed.y ~= restY then
        ok = false; say("  FAIL: landed at a different height than it started")
      end
    else
      ok = false; say("  FAIL: never came back to rest after the jump")
    end

    say(ok and "RESULT: PASS" or "RESULT: FAIL")
    local f = io.open(OUT .. "land_verify.txt", "w")
    f:write(table.concat(out, "\n") .. "\n")
    f:close()
    emu.stop(ok and 0 or 1)
  end
end
-- setInput only takes effect from inside an inputPolled callback, and its
-- argument order is (table, port) - the opposite way round from getInput(port).
-- Passing the port first fails with "table expected, got number", which the
-- testrunner swallows, so the run looks like the button simply did nothing.
-- SNES B is the bottom face button, which shim_core.c maps to NES PAD_A (jump).
local function onInput()
  if frames >= JUMP_AT and frames < JUMP_AT + JUMP_HOLD then
    emu.setInput({ b = true }, 0)
  end
end

emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.startFrame)
