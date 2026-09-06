-- Does the SECOND player draw?
--
-- drawplayertwo() was an empty stub for every milestone up to this one, so the
-- dual sections of the level set ran player two's whole physics pass and drew
-- nothing. This is the check that it draws, that it draws PLAYER TWO'S art at
-- PLAYER TWO'S position, and that the two players alternate for OAM priority.
--
-- WHY PALETTE AND NOT TILES. Player two's tables (CUBE2, SHIP2, ...) name the
-- SAME OBJ tiles as player one's under a DIFFERENT NES PALETTE - Cube_0 is tile
-- $0B palette 3, Cube2_0 is tile $0B palette 1. Counting OAM entries would pass
-- on a drawplayertwo that drew player one twice, and comparing tile numbers
-- would too. The palette is the only field that tells the two tables apart, and
-- tools/gen_gamemode_expect.py asserts the two sets are disjoint when it emits
-- the oracle - if a future sprite edit made them overlap it says so there rather
-- than letting this go quietly green.
--
-- Reaching a dual portal from a scripted run is not practical (they are deep in
-- the levels that have them), so `dual` is forced, exactly as
-- verify_gamemode_sprites.lua forces `gamemode`. That tests the dispatch and the
-- draw, which is the part that was missing.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local E1 = dofile(OUT .. "gamemode_expect.lua")
local E2 = dofile(OUT .. "gamemode_expect_p2.lua")

local W = emu.memType.snesWorkRam
local OAM = emu.memType.snesSpriteRam
local function r8(a) return emu.read(a, W, false) end
local function w8(a, v) emu.write(a, v, W) end

-- Where each player is pinned. Far enough apart that a ±16 window round each
-- cannot catch the other's sprites, and both comfortably on screen.
local P1X, P1Y = 0x40, 0x60
local P2X, P2Y = 0x80, 0x98
local GM = 0                            -- cube: both players' simplest arm

local START, EVERY, SAMPLES = 240, 5, 24
local frames, taken, bad, rows = 0, 0, 0, {}
local first_call = nil                  -- which of the two ran first this pass
local order_count = { [1] = 0, [2] = 0 }
local done = false

-- Gameplay input only AFTER the menu: A is also "select this level", so holding
-- it from frame 1 races the level select (docs/HANDOFF.md trap 114).
emu.addEventCallback(function()
  if not menu.done() then return end
  emu.setInput({ a = true }, 0)
end, emu.eventType.inputPolled)

-- Force dual and pin both players HERE - after the physics has run and before
-- draw_sprites reads any of it. Pinning once per frame somewhere else is not
-- enough: the physics moves the players again before the draw, and an unpinned
-- player two accelerates off screen within a few frames, at which point
-- drawplayer hides its sprites at Y=255 and this would read as "player two drew
-- nothing" (trap 90).
emu.addMemoryCallback(function()
  w8(A.dual, 1)
  w8(A.invisible, 0)
  w8(A.player_invis, 0)
  w8(A.gamemode, GM)
  w8(A.retro_mode, 0)
  -- Bit 0 of cube_data is "dead"; clear it for both so a spike does not end the
  -- run halfway through the sample window.
  w8(A.cube_data, r8(A.cube_data) & 0xFE)
  w8(A.cube_data + 1, r8(A.cube_data + 1) & 0xFE)
  w8(A.player_x, 0);     w8(A.player_x + 1, P1X)
  w8(A.player_x + 2, 0); w8(A.player_x + 3, P2X)
  w8(A.player_y, 0);     w8(A.player_y + 1, P1Y)
  w8(A.player_y + 2, 0); w8(A.player_y + 3, P2Y)
  w8(A.player_mini, 0);    w8(A.player_mini + 1, 0)
  w8(A.player_gravity, 0); w8(A.player_gravity + 1, 0)
  first_call = nil
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

-- WHICH PLAYER DREW FIRST, observed rather than derived.
--
-- The obvious version of this read `kandoframecnt & 1` at the pin hook above
-- and asserted the order followed it. It reported two wrong samples out of 24 -
-- not because the order was wrong but because the counter is not read at the
-- same point in the frame that draw_sprites reads it, so on a frame that lags
-- the two disagree. Hooking the two functions themselves cannot drift.
local function saw(who)
  if first_call == nil then
    first_call = who
    order_count[who] = order_count[who] + 1
  end
end
emu.addMemoryCallback(function() saw(1) end, emu.callbackType.exec,
                      A.code.drawplayerone, A.code.drawplayerone)
emu.addMemoryCallback(function() saw(2) end, emu.callbackType.exec,
                      A.code.drawplayertwo, A.code.drawplayertwo)

local function near(v, want) return math.abs(v - want) <= 16 end

local function finish()
  if done then return end
  done = true
  -- draw_sprites alternates the two calls on kandoframecnt's low bit so that
  -- neither player permanently wins OAM priority - without it one player would
  -- always be the one dropped at the 32-sprites-per-scanline limit. The check is
  -- that both orders happen and neither dominates; an exact frame-by-frame
  -- alternation is not the property, because a lagging frame legitimately
  -- repeats one.
  local n1, n2 = order_count[1], order_count[2]
  local total = n1 + n2
  rows[#rows + 1] = ""
  if n1 > 0 and n2 > 0 and n1 * 4 >= total and n2 * 4 >= total then
    rows[#rows + 1] = string.format(
      "draw order alternates: player one first on %d passes, player two first on %d",
      n1, n2)
  else
    bad = bad + 1
    rows[#rows + 1] = string.format(
      "<-- DRAW ORDER DID NOT ALTERNATE (p1 first %d, p2 first %d) - "
      .. "one player always has OAM priority", n1, n2)
  end
  rows[#rows + 1] = ""
  rows[#rows + 1] = bad == 0
    and string.format("RESULT: BOTH PLAYERS DRAW (%d samples)", taken)
    or  string.format("RESULT: FAIL - %d of %d samples wrong", bad, taken)
  local f = io.open(OUT .. "dual_verify.txt", "w")
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  emu.stop(bad == 0 and 0 or 1)
end

emu.addEventCallback(function()
  if done or not menu.done() then return end
  frames = frames + 1
  if frames < START then return end
  if (frames - START) % EVERY ~= 0 then return end

  -- The players are drawn FIRST, so their entries are the lowest OAM slots:
  -- two metasprites, two NES 8x16 sprites each, two SNES 8x8 halves each = 8.
  local ent = {}
  for s = 0, 7 do
    local y = emu.read(s * 4 + 1, OAM)
    local a = emu.read(s * 4 + 3, OAM)
    ent[#ent + 1] = {
      x = emu.read(s * 4, OAM), y = y,
      tile = emu.read(s * 4 + 2, OAM) + (a % 2) * 256,
      pal = (a >> 1) & 3,
      vis = y < 225,
    }
  end

  -- Classify by POSITION, then check the palette is the right table's. Doing it
  -- the other way round would let a player-one metasprite drawn at player two's
  -- position pass as player two.
  local n1, n2, other, ok = 0, 0, 0, true
  local pal1, pal2 = -1, -1
  local first = 0
  for _, e in ipairs(ent) do
    if not e.vis then
      ok = false
    elseif near(e.x, P1X + 8) and near(e.y, P1Y) then
      n1 = n1 + 1
      pal1 = e.pal
      if not E1[GM].pals[e.pal] or not E1[GM].tiles[e.tile] then ok = false end
      if first == 0 then first = 1 end
    elseif near(e.x, P2X + 8) and near(e.y, P2Y) then
      n2 = n2 + 1
      pal2 = e.pal
      if not E2[GM].pals[e.pal] or not E2[GM].tiles[e.tile] then ok = false end
      if first == 0 then first = 2 end
    else
      other = other + 1
      ok = false
    end
  end
  if n1 ~= 4 or n2 ~= 4 then ok = false end
  if not ok then bad = bad + 1 end

  taken = taken + 1
  rows[#rows + 1] = string.format(
    "frame %5d  p1 %d entries pal %d   p2 %d entries pal %d   stray %d  " ..
    "first in OAM: p%d  %s",
    frames, n1, pal1, n2, pal2, other, first, ok and "ok" or "<-- WRONG")

  if taken >= SAMPLES then finish() end
end, emu.eventType.startFrame)
