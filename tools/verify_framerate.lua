-- Does the game hold 60Hz?
--
-- Counts game frames (everything_else runs exactly once per iteration of
-- state_game's loop) against video frames. 100% means every game frame fit in
-- its 262 scanlines; anything less is frames that overran and cost a second
-- one.
--
-- The run is forced so the measurement is repeatable and reaches the parts of
-- the level that actually have sprites in them: A is held, and bit 0 of
-- cube_data - the death flag - is cleared at the top of the draw phase. Without
-- both, the cube dies on the first spike at scroll_x ~185, ~600px before the
-- first sprite object, and the trace measures an empty screen.
--
-- Level loading is excluded: reset_level draws 256 columns in a tight loop
-- before the first frame, which is a one-off, not gameplay lag.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
-- FRAMES shortens the run for sweeping all 46 levels; the default is the full
-- window every earlier milestone was measured over, so numbers stay comparable
-- (docs/HANDOFF.md trap 83).
local WARMUP = 180
local STOP_AT = tonumber(os.getenv("FRAMES") or "") or 3000
local BUCKET = 300

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
  emu.write(A.cube_data + 1, emu.read(A.cube_data + 1, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local gameframes = 0
emu.addMemoryCallback(function() gameframes = gameframes + 1 end,
                      emu.callbackType.exec, A.code.everything_else,
                      A.code.everything_else)

local frames, base_gf, rows = 0, nil, {}
local bucket_gf, worst, worst_at = 0, 999, 0
local peak, peak_at, bucket_peak = 0, 0, 0

emu.addEventCallback(function()
  -- Gameplay only. main() now opens the level select first, so a script that
  -- counts from reset measures the menu - which reads as a game with nothing in
  -- it rather than as an error. See tools/menu_skip.lua.
  if not menu.done() then return end
  frames = frames + 1
  if frames < WARMUP then return end
  if frames == WARMUP then base_gf, bucket_gf = gameframes, gameframes; return end

  -- Sprite load every frame, not just at the bucket boundary: the point of the
  -- check is that a BUSY frame still fits, and sampling once per 300 frames
  -- almost never lands on one.
  local live = 0
  for s = 0, 127 do
    if emu.read(s * 4 + 1, emu.memType.snesSpriteRam) < 225 then live = live + 1 end
  end
  if live > bucket_peak then bucket_peak = live end
  if live > peak then peak, peak_at = live, frames end

  if (frames - WARMUP) % BUCKET == 0 then
    local pct = 100 * (gameframes - bucket_gf) / BUCKET
    rows[#rows + 1] = string.format("  frames %5d-%-5d  %5.1f%%   peak OAM=%d",
      frames - BUCKET, frames, pct, bucket_peak)
    bucket_peak = 0
    if pct < worst then worst, worst_at = pct, frames end
    bucket_gf = gameframes
  end

  if frames >= STOP_AT then
    local total = 100 * (gameframes - base_gf) / (frames - WARMUP)
    table.insert(rows, 1, string.format(
      "%d video frames of gameplay, %d game frames -> %.1f%% of 60Hz",
      frames - WARMUP, gameframes - base_gf, total))
    table.insert(rows, 2, string.format("worst %d-frame window: %.1f%% (at frame %d)",
      BUCKET, worst, worst_at))
    table.insert(rows, 3, string.format(
      "busiest frame: %d OAM entries live (frame %d) = %d NES sprites",
      peak, peak_at, peak // 2))
    table.insert(rows, 4, "")
    -- 98% is one dropped frame every ~50: visible on a graph, not to a player.
    local ok = total >= 98.0 and worst >= 90.0
    rows[#rows + 1] = ""
    rows[#rows + 1] = ok and "RESULT: HOLDS 60Hz" or "RESULT: DROPPING FRAMES"
    local f = io.open(OUT .. "framerate.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(ok and 0 or 1)
  end
end, emu.eventType.startFrame)
