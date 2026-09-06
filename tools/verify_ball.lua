-- Does the ball rest on the floor, with the camera pinned at a scroll cap?
--
-- The ball is the gamemode that exposed cap_scroll_y_at_top/bottom. Its camera
-- runs through process_y_scroll's target_scroll_y arm, which moves the player
-- EVERY frame and lets the cap take the matching scroll back. Port the cap as a
-- bare clamp - as this port originally did - and the player keeps the movement
-- while the camera does not, so it drifts ~2px a frame; the floor eject fights
-- the drift and the ball visibly bounces over ~7 pixels.
--
-- THREE ways this could pass for the wrong reason, all guarded against:
--
--  1. The cap never firing. A ball dropped on flat ground with target_scroll_y
--     already equal to scroll_y rests whether or not the compensation exists.
--     So target_scroll_y is driven far past the limit ON PURPOSE, and the run
--     FAILS if the cap did not actually engage (scroll_y must stay pinned).
--  2. Only testing one cap. Bottom and top are separate routines and only the
--     bottom one is reached by dropping the ball; the top one is a phase here.
--  3. The terrain moving underneath. The ball travels, so "it never settles"
--     and "it ran onto a slope" look identical. currplayer_x and scroll_x are
--     frozen, so the column below the ball does not change.
--
--   "C:/mesen2/Mesen.exe" --testrunner <abs rom> <abs tools/verify_ball.lua>
-- Mesen resolves a testrunner path relative to its OWN directory - pass both
-- absolutely (docs/HANDOFF.md).
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)

local WR = emu.memType.snesWorkRam
local START = 240              -- level loaded, cube has landed
local SETTLE = 40              -- frames to let the drop finish before judging
local PHASE = 140

-- Driving target_scroll_y past a limit pins the camera against a cap and keeps
-- it there, so the compensation runs on every single frame of the phase.
--
-- The top phase also raises min_scroll_y to wherever the camera already is.
-- Without that, target = 0 makes the camera genuinely scroll up - which drags
-- the ball off its floor and into a real fall, and measures the fall rather
-- than the cap. Pinning the limit at the current position keeps the same floor
-- under the ball while still driving the target past it every frame.
local PHASES = {
  { name = "floor, camera pinned at the BOTTOM cap", target = 0xB000,
    max_px = 2, max_vel = 256 },
  -- The top cap does NOT come out exact, and that is the original's arithmetic,
  -- not a shortfall of the port. Two things in the upward path disagree by one
  -- sub-pixel step and only cancel if BOTH are changed:
  --   * scroll.h's ship/ball arm increments the pixel count on carry SET after
  --     a subtract - i.e. when there was NO borrow (its own `do_if_carry`,
  --     which nesdash.h defines as do_if_c_set). The cube's upward arm uses
  --     do_if_borrow. The asymmetry is in the game.
  --   * _cap_scroll_y_at_top subtracts scroll_y_subpx from the player, where
  --     conserving the camera position would add it.
  -- Together they leave ~0.2px a frame, against 0.28px of ball gravity, so the
  -- ball hops a little instead of sitting still. Ported as written; the bound
  -- here is set to catch a REGRESSION (the un-compensated cap drifted 2px a
  -- frame and bounced over 7px), not to assert the original is exact.
  { name = "floor, camera pinned at the TOP cap",    target = 0x0000,
    pin_min = true, max_px = 4, max_vel = 700 },
}

local function rd(a) return emu.read(a, WR, false) end
local function u16(a) return rd(a) + 256 * rd(a + 1) end
local function u32(a) return u16(a) + 65536 * u16(a + 2) end
local function s16(a)
  local v = u16(a); if v >= 0x8000 then v = v - 0x10000 end; return v
end
local function wr16(a, v)
  emu.write(a, v & 0xFF, WR); emu.write(a + 1, (v >> 8) & 0xFF, WR)
end

local frame, rows = 0, {}
local froze_x, froze_scroll
local st = {}                  -- per-phase measurements

-- Keep the player alive; a death reloads the level and the gamemode with it.
emu.addMemoryCallback(function()
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, WR)
  emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, WR)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

emu.addEventCallback(function()
  if not menu.done() then return end
  frame = frame + 1
  if frame < START then return end

  local i = math.floor((frame - START) / PHASE) + 1
  local p = PHASES[i]
  if not p then return end

  emu.write(A.gamemode, 0x02, WR)                       -- BALL
  if not froze_x then
    froze_x, froze_scroll = u16(A.currplayer_x), u32(A.scroll_x)
  end
  wr16(A.currplayer_x, froze_x)
  wr16(A.scroll_x, froze_scroll & 0xFFFF)
  wr16(A.scroll_x + 2, (froze_scroll >> 16) & 0xFFFF)
  if p.pin_min then wr16(A.min_scroll_y, u16(A.scroll_y)) end
  wr16(A.target_scroll_y, p.target)

  local s = st[i]
  if not s then
    s = { n = 0, lo = 0xFFFF, hi = 0, vel_hi = -32768, rest = 0,
          sy_lo = 0xFFFF, sy_hi = 0 }
    st[i] = s
  end

  -- Settle first: the ball has to finish the drop it is already in.
  if ((frame - START) % PHASE) < SETTLE then return end

  local y   = u16(A.currplayer_y)
  local vel = s16(A.currplayer_vel_y)
  local sy  = u16(A.scroll_y)
  s.n = s.n + 1
  if y < s.lo then s.lo = y end
  if y > s.hi then s.hi = y end
  if vel > s.vel_hi then s.vel_hi = vel end
  if vel == 0 then s.rest = s.rest + 1 end
  if sy < s.sy_lo then s.sy_lo = sy end
  if sy > s.sy_hi then s.sy_hi = sy end
  s.target, s.min = p.target, u16(A.min_scroll_y)

  if frame >= START + PHASE * #PHASES - 1 then
    local ok = true
    local function say(f, ...) rows[#rows + 1] = string.format(f, ...) end
    for k, ph in ipairs(PHASES) do
      local m = st[k]
      say("%s", ph.name)
      if not m or m.n == 0 then
        ok = false; say("  FAIL - phase never ran"); goto continue
      end
      say("  %d frames   y %04X..%04X (%d px)   peak vel %+d   vel==0 on %d",
          m.n, m.lo, m.hi, (m.hi - m.lo) // 256, m.vel_hi, m.rest)
      say("  scroll_y %04X..%04X   target %04X   min_scroll_y %04X",
          m.sy_lo, m.sy_hi, m.target, m.min)

      -- The cap must have been engaged, or this measures nothing.
      if m.sy_lo ~= m.sy_hi then
        ok = false
        say("  FAIL - scroll_y moved, so the camera was not pinned and the "
            .. "cap did not run every frame")
      end
      -- A resting ball jitters by the eject, one metatile-aligned pixel.
      if (m.hi - m.lo) > (ph.max_px * 256 + 255) then
        ok = false
        say("  FAIL - ball travels %d px (limit %d); it is bouncing, not "
            .. "resting", (m.hi - m.lo) // 256, ph.max_px)
      end
      -- The velocity is the sharper signal, because a bounce shows up there
      -- long before the position leaves a 2px band: free fall to the bottom
      -- of a 7px bounce reaches BALL_MAX_FALLSPEED (994), whereas a ball the
      -- floor is catching every frame never gets past one frame of gravity.
      --
      -- NOT "vel == 0 on every frame": the eject zeroes it and the next
      -- frame's gravity puts it straight back, and a once-a-frame sample
      -- lands on either side of that depending on where the game's logic
      -- frame sits relative to the emulator's. Peak velocity does not have
      -- that ambiguity.
      if m.vel_hi > ph.max_vel then
        ok = false
        say("  FAIL - peak velocity %+d exceeds %d; the ball is in free fall "
            .. "between hits, i.e. bouncing", m.vel_hi, ph.max_vel)
      end
      if m.rest == 0 then
        ok = false
        say("  FAIL - velocity never reached 0; the floor eject is not running")
      end
      ::continue::
    end
    say(ok and "RESULT: BALL RESTS ON THE FLOOR" or "RESULT: FAIL")
    local f = io.open(OUT .. "ball_physics.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(ok and 0 or 1)
  end
end, emu.eventType.startFrame)
