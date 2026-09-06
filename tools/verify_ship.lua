-- Does the ship pick the right gravity, and does the velocity follow it?
--
-- ship_movement chooses between FOUR tables, on two booleans:
--
--                 not falling              falling
--   holding       SHIP_GRAVITY_BASE        SHIP_GRAVITY_HOLD_FALL
--   released      SHIP_GRAVITY_AFTER_HOLD  SHIP_GRAVITY
--
-- then flips the sign when `(gravity != 0) XOR holding`, and common_gravity_routine
-- adds the result to currplayer_vel_y, which gamemode_ship.h then clamps.
--
-- THREE ways to get a false pass here, all of which happened:
--
--  1. Only exercising two of the four cases. Holding from rest and releasing
--     once already falling are the two a scripted run reaches by accident; the
--     other two need the button to change while the ship is still travelling the
--     other way. The input below is a duty cycle tuned to cross both boundaries.
--  2. Only exercising one table index. currplayer_table_idx is
--     framerate<<2 | mini<<1 | gravity, and a normal run never leaves index 4.
--     Mini and flipped gravity are forced here.
--  3. Checking the CONSTANT and not the VELOCITY. tmpgravity being right says
--     nothing about whether it was applied, or clamped at the right bound.
--
-- Expected values come from tools/gen_physics_expect.py, parsed out of the
-- game's own header rather than recomputed here (docs/HANDOFF.md trap 61).
--
--   "C:/mesen2/Mesen.exe" --testrunner out/famidash-snes-full.sfc tools/verify_ship.lua
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local T = dofile(OUT .. "physics_expect.lua")

local WR = emu.memType.snesWorkRam
local START = 200                       -- let the level finish loading
local PHASE = 500                       -- frames per (mini, gravity) combination

-- gamemode_ship.h, the clamp after common_gravity_routine.
local CLAMP = {
  [0] = { lo = -0x0443, hi = 0x0369 },  -- normal gravity
  [1] = { lo = -0x0369, hi = 0x0443 },  -- flipped
}

-- gamemode 1 is the ship, 6 the wave. Both go through player_frame_ship, and
-- they clamp the tilt the OPPOSITE way in nesdash.s - so both are driven here.
local PHASES = {
  { mini = 0, grav = 0x00, mode = 1, name = "ship" },
  { mini = 1, grav = 0x00, mode = 1, name = "ship mini" },
  { mini = 0, grav = 0x80, mode = 1, name = "ship flipped" },
  { mini = 1, grav = 0x80, mode = 1, name = "ship mini+flipped" },
  { mini = 0, grav = 0x00, mode = 6, name = "wave" },
  { mini = 0, grav = 0x80, mode = 6, name = "wave flipped" },
  -- MINI wave, both directions. Without these the wave's tilt never reaches the
  -- clamp and this check silently did not cover the one case where the ship and
  -- the wave behave DIFFERENTLY - the run said so, in as many words, for
  -- several milestones.
  --
  -- It needs mini rather than a poke of player_vel_y: wave_movement sets
  -- currplayer_vel_y to +/-currplayer_vel_x, doubled when mini. At speed 0 that
  -- is 0x352 full size - inside 0x0400, so cube_rotate = 0x400 - vel never
  -- leaves 0x0000..0x07FF - and 0x6A4 mini, which overshoots in BOTH directions
  -- and exercises both arms of the clamp.
  { mini = 1, grav = 0x00, mode = 6, name = "wave mini" },
  { mini = 1, grav = 0x80, mode = 6, name = "wave mini+flipped" },
}
local STOP = START + PHASE * #PHASES

local function rd(a) return emu.read(a, WR, false) end
local function s16(a)
  local v = rd(a) + 256 * rd(a + 1)
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end

-- Keep the player alive; a death resets the level and the gamemode with it.
emu.addMemoryCallback(function()
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, WR)
  emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, WR)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frame, holding, phase = 0, false, 0
local phase_frame = 0   -- frames since the current (mini, gravity, mode) began

emu.addEventCallback(function()
  if holding then emu.setInput({ a = true }, 0) end
end, emu.eventType.inputPolled)

-- case[idx][slot] = { n, wrong, got, want }, slot 1..4 as in the table above
local case, vel_bad, vel_first = {}, 0, nil
local clamp_seen, clamp_bad, clamp_first = {}, 0, nil
local CASE_NAME = { "BASE (hold, rising)", "HOLD_FALL (hold, falling)",
                    "AFTER_HOLD (released, rising)", "GRAVITY (released, falling)" }

local pending                            -- state captured before the add

emu.addEventCallback(function()
  if not menu.done() then return end
  frame = frame + 1
  if frame < START then return end
  phase = math.floor((frame - START) / PHASE) + 1
  local p = PHASES[phase]
  if not p then return end

  emu.write(A.gamemode, p.mode, WR)
  emu.write(A.currplayer_mini, p.mini, WR)
  emu.write(A.currplayer_gravity, p.grav, WR)
  -- currplayer_table_idx is only recomputed by cube_movement and at level load,
  -- so in ship mode it has to be maintained here to match what was forced.
  emu.write(A.currplayer_table_idx,
            (rd(A.framerate) & 1) * 4 + p.mini * 2 + (p.grav ~= 0 and 1 or 0), WR)

  -- 45 frames each way. Long enough to reverse the direction of travel, so the
  -- button change lands while the ship is still moving the other way and the
  -- two mid-flight cases happen - AND long enough to saturate: at 42 per frame
  -- the clamp at 1091 takes 26 frames, so a shorter cycle never reaches the
  -- bound and silently leaves the terminal velocity untested.
  phase_frame = (frame - START) % PHASE
  holding = (math.floor((frame - START) / 45) % 2) == 0
end, emu.eventType.startFrame)

-- common_gravity_routine runs immediately after ship_movement has chosen
-- tmpgravity, with tmp1 (falling) and tmp2 (holding) still set - the one place
-- where the decision and its inputs are all readable at once.
emu.addMemoryCallback(function()
  if rd(A.gamemode) ~= 1 or frame < START + 4 then return end   -- ship only
  -- Skip the first frames of a phase. The harness forces mini/gravity and the
  -- matching currplayer_table_idx from a startFrame callback, and on the frame
  -- a phase changes ship_movement can already have chosen tmpgravity from the
  -- PREVIOUS index - so the oracle and the game disagree about which row of the
  -- table was in force. One sample in 204, entirely the harness's own doing.
  if phase_frame < 4 then return end
  local hold = rd(A.tmp2) ~= 0
  local fall = rd(A.tmp1) ~= 0
  local idx = rd(A.currplayer_table_idx)
  local grav = s16(A.tmpgravity)

  local tbl, slot
  if hold and not fall then tbl, slot = T.SHIP_GRAVITY_BASE, 1
  elseif hold then          tbl, slot = T.SHIP_GRAVITY_HOLD_FALL, 2
  elseif not fall then      tbl, slot = T.SHIP_GRAVITY_AFTER_HOLD, 3
  else                      tbl, slot = T.SHIP_GRAVITY, 4 end

  local want = tbl[idx + 1]
  if ((rd(A.currplayer_gravity) ~= 0) ~= hold) then want = -want end

  case[idx] = case[idx] or {}
  local c = case[idx][slot] or { n = 0, wrong = 0 }
  case[idx][slot] = c
  c.n = c.n + 1
  c.got, c.want = grav, want
  if grav ~= want then c.wrong = c.wrong + 1 end

  -- Carry the state forward so the velocity AFTER the add can be checked.
  -- dashing takes a completely different path through common_gravity_routine;
  -- it never happens in this scripted flight, but assert it rather than assume.
  if rd(A.dashing) ~= 0 then return end
  pending = { vel = s16(A.currplayer_vel_y), grav = grav,
              g = rd(A.currplayer_gravity) ~= 0 and 1 or 0, idx = idx,
              fall = s16(A.tmpfallspeed), gm = rd(A.gravity_mod) }
end, emu.callbackType.exec, A.code.common_gravity_routine, A.code.common_gravity_routine)

-- ufo_ship_eject is the next call in ship_movement, after the add AND after the
-- clamp - so the velocity read here is the finished one for this frame.
emu.addMemoryCallback(function()
  if not pending then return end
  local vel = s16(A.currplayer_vel_y)
  local cl = CLAMP[pending.g]

  -- common_gravity_routine flips the sign AGAIN, against tmpfallspeed, and then
  -- scales by gravity_mod. Leaving those out of the oracle produced a
  -- confident-looking failure that was the check being wrong, not the port.
  -- Written out rather than as `a and b or c`: that form evaluated to
  -- `b or c` for the normal-gravity case and produced a confident failure that
  -- was the oracle, not the port.
  local accel = pending.grav
  local flip
  if pending.g == 0 then flip = pending.vel > pending.fall
  else                   flip = pending.vel < pending.fall end
  if flip then accel = -accel end
  local gm = pending.gm
  local function trunc(x) return x < 0 and math.ceil(x) or math.floor(x) end
  if gm == 1 then accel = trunc(accel / 3)
  elseif gm == 2 then accel = trunc(accel / 2)
  elseif gm == 3 then accel = trunc(trunc(accel / 3) * 2)
  elseif gm == 4 then accel = accel * 2 end

  local want = pending.vel + accel
  if want < cl.lo then want = cl.lo end
  if want > cl.hi then want = cl.hi end
  if vel ~= want then
    vel_bad = vel_bad + 1
    vel_first = vel_first or string.format(
      "idx %d: vel %+d, gravity %+d, accel %+d -> %+d, expected %+d",
      pending.idx, pending.vel, pending.grav, accel, vel, want)
  end
  if vel == cl.lo or vel == cl.hi then clamp_seen[pending.g] = true end
  pending = nil
end, emu.callbackType.exec, A.code.ufo_ship_eject, A.code.ufo_ship_eject)

-- The tilt, checked against an independent model of the two clamps in
-- nesdash.s. cube_rotate is what player_frame_ship writes and the frame index is
-- its high byte, so this pins the whole path including the copy of
-- currplayer_vel_y back into player_vel_y[0] that the draw reads.
local tilt, copy_bad, copy_first = {}, 0, nil
local wave_vel_bad, wave_vel_first = 0, nil
local wave_vel_ok, wave_vel_moving = 0, 0
local vx_bad, vx_first = 0, nil
local hi_max, hi_min = 0, 255
emu.addMemoryCallback(function()
  local mode = rd(A.gamemode)
  -- Settle after a phase change as well as after the start. The gamemode is
  -- poked at startFrame but the game's logic frame straddles that boundary, so
  -- on the first frame of a phase this callback can see the NEW gamemode
  -- alongside a velocity the PREVIOUS one produced. It showed up as exactly one
  -- wave frame carrying a ship velocity - a harness artifact reported as a port
  -- defect, which is the failure mode this whole file is written against.
  if (mode ~= 1 and mode ~= 6) or frame < START + 4 or phase_frame < 4 then
    return
  end
  local vy = s16(A.player_vel_y)
  local rot = (0x0400 - vy) & 0xFFFF
  local hi = rot >> 8
  if hi >= 0x08 then
    if mode == 6 then rot = (hi >= 0x80) and 0x07FF or 0x0000
    else              rot = (hi >= 0x80) and 0x0000 or 0x07FF end
  end
  -- player_vel_y[0] is a COPY of currplayer_vel_y, made when the physics writes
  -- the working state back. Modelling the tilt from the same variable the draw
  -- reads would pass happily if that copy never happened and both sides were
  -- stale, so compare them.
  local cvy = s16(A.currplayer_vel_y)
  if vy ~= cvy then
    copy_bad = copy_bad + 1
    copy_first = copy_first or string.format(
      "player_vel_y[0] is %+d but currplayer_vel_y is %+d", vy, cvy)
  end

  -- Horizontal speed, the last part of "flight" the vertical checks do not
  -- touch: x_movement sets currplayer_vel_x from CUBE_SPEED[framerate][speed]
  -- every frame, for every gamemode.
  local vx = s16(A.currplayer_vel_x)
  local want_vx = T.CUBE_SPEED[rd(A.framerate) & 1][rd(A.speed) + 1]
  if want_vx and vx ~= want_vx then
    vx_bad = vx_bad + 1
    vx_first = vx_first or string.format("speed %d gave vel_x %d, expected %d",
                                         rd(A.speed), vx, want_vx)
  end

  -- The WAVE's own velocity rule, which the tilt check alone does not pin down.
  -- wave_movement sets currplayer_vel_y to +/-currplayer_vel_x, doubled when
  -- mini; the sign follows gravity and flips while A is held, and both the slope
  -- branch and wave_eject can zero it. So the invariant that holds on every
  -- frame regardless of those is the MAGNITUDE: |vel_y| is either the speed or
  -- zero, never anything else.
  --
  -- Worth checking on its own because it was wrong in exactly the way the tilt
  -- check could not see: Calypsi dropped the value at the merge of the four
  -- ternary arms and stored Y instead, so vel_y was a constant +1 - small enough
  -- that cube_rotate never left its unclamped range and every tilt frame
  -- "passed" (docs/HANDOFF.md traps 105-106).
  if mode == 6 then
    local mag = math.abs(vx) * (rd(A.currplayer_mini) ~= 0 and 2 or 1)
    if math.abs(cvy) ~= mag and cvy ~= 0 then
      wave_vel_bad = wave_vel_bad + 1
      wave_vel_first = wave_vel_first or string.format(
        "wave vel_y %+d, expected +/-%d (vel_x %d, mini %d) or 0",
        cvy, mag, vx, rd(A.currplayer_mini))
    else
      wave_vel_ok = wave_vel_ok + 1
      if cvy ~= 0 then wave_vel_moving = wave_vel_moving + 1 end
    end
  end

  local got = rd(A.cube_rotate) + 256 * rd(A.cube_rotate + 1)
  local key = (mode == 6) and "wave" or "ship"
  tilt[key] = tilt[key] or { n = 0, wrong = 0, clamped = 0, hi_lo = 255, hi_hi = 0 }
  local t = tilt[key]
  if hi > t.hi_hi then t.hi_hi = hi end
  if hi < t.hi_lo then t.hi_lo = hi end
  t.n = t.n + 1
  if hi >= 0x08 then t.clamped = t.clamped + 1 end
  if got ~= rot then
    t.wrong = t.wrong + 1
    t.first = t.first or string.format("vel_y %+d gave cube_rotate %04X, expected %04X",
                                       vy, got, rot)
  end
end, emu.callbackType.exec, A.code.trail_loop, A.code.trail_loop)

emu.addEventCallback(function()
  if frame < STOP or not menu.done() then return end
  local rows, bad = {}, 0
  for pi, p in ipairs(PHASES) do
    local idx = (1 & 1) * 4 + p.mini * 2 + (p.grav ~= 0 and 1 or 0)
    rows[#rows + 1] = string.format("%s (currplayer_table_idx %d)", p.name, idx)
    for slot = 1, 4 do
      local c = case[idx] and case[idx][slot]
      if not c then
        rows[#rows + 1] = string.format("  %-30s NEVER REACHED", CASE_NAME[slot])
        bad = bad + 1
      else
        if c.wrong > 0 then bad = bad + 1 end
        rows[#rows + 1] = string.format(
          "  %-30s %4d samples, gravity %+5d, expected %+5d  %s",
          CASE_NAME[slot], c.n, c.got, c.want,
          c.wrong == 0 and "ok"
            or string.format("<-- WRONG on %d of %d", c.wrong, c.n))
      end
    end
  end
  rows[#rows + 1] = ""
  if vel_bad > 0 then
    rows[#rows + 1] = string.format("velocity: %d frames did not follow gravity+clamp; %s",
                                    vel_bad, vel_first)
    bad = bad + 1
  else
    rows[#rows + 1] = "velocity: follows gravity and clamps on every frame"
  end
  for _, key in ipairs({ "ship", "wave" }) do
    local t = tilt[key]
    if not t or t.clamped == 0 then
      rows[#rows + 1] = string.format(
        "%s tilt: %d frames correct, but NEVER CLAMPED (cube_rotate high byte "
        .. "stayed in $%02X..$%02X) - the case where the ship and the wave "
        .. "differ was not reached, so this run does not cover it",
        key, t and t.n or 0, t and t.hi_lo or 0, t and t.hi_hi or 0)
    elseif t.wrong > 0 then
      rows[#rows + 1] = string.format("%s tilt: %d of %d frames wrong; %s",
                                      key, t.wrong, t.n, t.first)
      bad = bad + 1
    else
      rows[#rows + 1] = string.format("%s tilt: %d frames correct (%d at the clamp)",
                                      key, t.n, t.clamped)
    end
  end
  if vx_bad > 0 then
    rows[#rows + 1] = string.format("horizontal speed wrong on %d frames; %s",
                                    vx_bad, vx_first)
    bad = bad + 1
  else
    rows[#rows + 1] = "horizontal speed matches CUBE_SPEED[framerate][speed]"
  end
  if wave_vel_bad > 0 then
    rows[#rows + 1] = string.format("wave vel_y wrong on %d frames; %s",
                                    wave_vel_bad, wave_vel_first)
    bad = bad + 1
  elseif wave_vel_moving == 0 then
    -- All zero would satisfy the magnitude test and mean the wave never moved.
    rows[#rows + 1] = string.format(
      "wave vel_y: %d frames checked but NEVER NON-ZERO - the wave did not move",
      wave_vel_ok)
    bad = bad + 1
  else
    rows[#rows + 1] = string.format(
      "wave vel_y is +/-CUBE_SPEED (doubled when mini) or 0 on all %d frames, "
      .. "%d of them moving", wave_vel_ok, wave_vel_moving)
  end
  if copy_bad > 0 then
    rows[#rows + 1] = string.format("player_vel_y[0] does not track currplayer_vel_y "
                                    .. "on %d frames; %s", copy_bad, copy_first)
    bad = bad + 1
  else
    rows[#rows + 1] = "player_vel_y[0] tracks currplayer_vel_y on every drawn frame"
  end
  if not (clamp_seen[0] and clamp_seen[1]) then
    rows[#rows + 1] = "clamp: NOT REACHED in both gravity directions - "
                      .. "the bounds were never exercised"
    bad = bad + 1
  else
    rows[#rows + 1] = "clamp: reached in both gravity directions"
  end

  local text = table.concat(rows, "\n") .. "\n"
      .. (bad == 0 and "RESULT: SHIP PHYSICS MATCHES THE TABLES\n"
                    or string.format("RESULT: FAIL - %d problem(s)\n", bad))
  local f = io.open(OUT .. "ship_physics.txt", "w"); f:write(text); f:close()
  print(text)
  emu.stop(bad == 0 and 0 or 1)
end, emu.eventType.startFrame)
