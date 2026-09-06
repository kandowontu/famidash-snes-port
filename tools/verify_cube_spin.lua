-- How fast does the cube actually spin in the air?
--
-- cube_rotate is 16-bit fixed point: the low byte accumulates CUBE_GRAVITY each
-- airborne frame and the high byte - the 0..23 step drawn - advances only when
-- that carries. Stepping the high byte directly instead spins the cube a full
-- turn in 24 frames rather than ~57, which is what "the player spins too fast"
-- was.
--
-- At framerate 1 the step is CUBE_GRAVITY_lo[4] = 107, so:
--     frames per drawn step   = 256 / 107 = 2.393
--     frames per full turn    = 24 * 2.393 = 57.4
--
-- Measured over a real jump, not asserted from the table: this samples
-- cube_rotate while the player is off the ground and checks the rate against
-- what the physics table says it should be.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local STOP_AT = 1200
local GRAVITY = 107          -- CUBE_GRAVITY_lo[framerate * 4], framerate = 1
local EXPECT_PER_TURN = 24 * 256 / GRAVITY
local TOLERANCE = 0.10       -- 10%: a jump is not an exact number of frames

-- Gameplay input only AFTER the menu. A is also "select this level", so a
-- script that holds it from frame 1 races the level select - and whichever wins
-- depends on when the menu happens to appear, which a compiler flag can move.
-- That is how every scripted run silently played level 0 (docs/HANDOFF.md
-- trap 114).
emu.addEventCallback(function()
  if not menu.done() then return end
  emu.setInput({ a = true }, 0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local function wram16(a)
  return emu.read(a, emu.memType.snesWorkRam)
       + emu.read(a + 1, emu.memType.snesWorkRam) * 256
end

local frames = 0
local prev_rot, airborne_frames, total_units = nil, 0, 0
local step_changes = 0
local rows = {}

emu.addEventCallback(function()
  -- Gameplay only. main() now opens the level select first, so a script that
  -- counts from reset measures the menu - which reads as a game with nothing in
  -- it rather than as an error. See tools/menu_skip.lua.
  if not menu.done() then return end
  frames = frames + 1
  local vy = wram16(A.player_vel_y)
  local rot = wram16(A.cube_rotate)
  -- Airborne is vel_y ~= 0; treat the signed 16-bit value as such.
  local moving = (vy ~= 0)

  if moving and prev_rot then
    -- Unsigned distance travelled around the 24*256 wheel, shortest way.
    local d = (rot - prev_rot) % (24 * 256)
    if d > 12 * 256 then d = d - 24 * 256 end
    if math.abs(d) < 4 * 256 then          -- ignore the snap when landing
      total_units = total_units + math.abs(d)
      airborne_frames = airborne_frames + 1
      if (rot >> 8) ~= (prev_rot >> 8) then step_changes = step_changes + 1 end
    end
  end
  prev_rot = rot

  if frames >= STOP_AT then
    local per_frame = airborne_frames > 0 and (total_units / airborne_frames) or 0
    local per_turn = per_frame > 0 and (24 * 256 / per_frame) or 0
    local frames_per_step = step_changes > 0 and (airborne_frames / step_changes) or 0
    rows[#rows + 1] = string.format(
      "%d airborne frames sampled, %d drawn-step changes", airborne_frames, step_changes)
    rows[#rows + 1] = string.format(
      "measured %.1f rotation units/frame  (CUBE_GRAVITY_lo[4] = %d)", per_frame, GRAVITY)
    rows[#rows + 1] = string.format(
      "measured %.1f frames per full turn  (expected %.1f)", per_turn, EXPECT_PER_TURN)
    rows[#rows + 1] = string.format(
      "measured %.2f frames per drawn step (expected %.2f)",
      frames_per_step, 256 / GRAVITY)
    local ok = airborne_frames > 30
              and math.abs(per_frame - GRAVITY) <= GRAVITY * TOLERANCE
    rows[#rows + 1] = ""
    rows[#rows + 1] = ok and "RESULT: SPIN RATE MATCHES THE PHYSICS TABLE"
                          or "RESULT: FAIL - the cube is not spinning at CUBE_GRAVITY"
    local f = io.open(OUT .. "cube_spin.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(ok and 0 or 1)
  end
end, emu.eventType.startFrame)
