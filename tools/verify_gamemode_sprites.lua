-- Does each gamemode draw its OWN sprite table?
--
-- Until M2.13 drawplayerone only had the cube arm, so every gamemode drew a
-- cube - the ship portal changed the physics and nothing else. Reaching the
-- ship portal from a scripted run is unreliable (it depends on the exact jump
-- trajectory), so this pokes `gamemode` directly and checks what comes out of
-- OAM: this is a test of the dispatch, which is the part that was missing.
--
-- Expected tile numbers come from tools/gamemode_expect.lua, generated from
-- SAUCE/defines/sprites.h - an independent oracle, not the shim's own formula
-- (docs/HANDOFF.md trap 61).
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local EXPECT = dofile(OUT .. "gamemode_expect.lua")

-- Settle for a few frames after poking so the frame counters advance normally.
local SETTLE = 12
local order = {}
for gm in pairs(EXPECT) do order[#order + 1] = gm end
table.sort(order)

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
  -- Pin the player mid-screen, HERE - after the physics has run and before
  -- drawplayerone draws. Poking `gamemode` hands control to an arm that was
  -- never entered properly, and the wave and the spider fly straight off the
  -- top or bottom; drawplayerone then hides the sprites at Y=255 and the test
  -- reads it as "this gamemode draws nothing". It did draw, correctly, off
  -- screen. Pinning once per frame instead is not enough: the physics moves it
  -- again before the draw. player_y is the screen row << 8.
  emu.write(A.player_y, 0x00, emu.memType.snesWorkRam)
  emu.write(A.player_y + 1, 0x60, emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frames, idx, rows, bad = 0, 1, {}, 0
local phase2 = nil
local START = 600

emu.addEventCallback(function()
  -- Gameplay only. main() now opens the level select first, so a script that
  -- counts from reset measures the menu - which reads as a game with nothing in
  -- it rather than as an error. See tools/menu_skip.lua.
  if not menu.done() then return end
  frames = frames + 1
  if frames < START then return end
  local gm = order[idx]
  if not gm then return end
  emu.write(A.gamemode, gm, emu.memType.snesWorkRam)

  if (frames - START) % SETTLE ~= SETTLE - 1 then return end

  -- The player is drawn first, so its entries are at the bottom of OAM.
  local seen, xs, attrs = {}, {}, {}
  for s = 0, 3 do
    if emu.read(s * 4 + 1, emu.memType.snesSpriteRam) < 225 then
      local a = emu.read(s * 4 + 3, emu.memType.snesSpriteRam)
      seen[#seen + 1] = emu.read(s * 4 + 2, emu.memType.snesSpriteRam) + (a % 2) * 256
      xs[#xs + 1] = emu.read(s * 4, emu.memType.snesSpriteRam)
      attrs[#attrs + 1] = a
    end
  end
  local tiles = {}
  for i, t in ipairs(seen) do tiles[i] = t end
  table.sort(tiles)

  -- A gamemode may legitimately be on any frame of its animation, so the check
  -- is "these tiles belong to this gamemode's table", not "this exact frame".
  local ok = #seen > 0
  for _, t in ipairs(tiles) do
    if not EXPECT[gm].tiles[t] then ok = false end
  end

  -- A flip must MIRROR THE OFFSETS, not just set the attribute bits.
  --
  -- oam_meta_spr_flipped originally only XORed the flip into each sprite's
  -- attribute, so every 8x16 sprite was mirrored about its own centre and left
  -- where it was: a 16x16 metasprite came out as four quadrants turned inside
  -- out. Positions alone cannot catch that - the sprites are still at the same
  -- two x values - but the ORDER can. Mirroring dx means the sprite emitted
  -- first is the one that was rightmost in the source data.
  local note = ""
  if #xs > 1 then
    local hflip = (attrs[1] & 0x40) ~= 0
    local descending = xs[1] > xs[#xs]
    if hflip ~= descending and xs[1] ~= xs[#xs] then
      ok = false
      note = "  <-- H FLIP DID NOT MIRROR THE OFFSETS"
    end
  end

  if not ok then bad = bad + 1 end
  rows[#rows + 1] = string.format("gamemode %2d %-9s tiles %-20s x %-12s attr %02X  %s%s",
    gm, EXPECT[gm].name, table.concat(tiles, ","), table.concat(xs, ","),
    attrs[1] or 0, ok and "ok" or "<-- WRONG", note)

  idx = idx + 1
  if not order[idx] then
    -- Phase two. The cube's H-flipped frames are steps 12-23 of its rotation,
    -- and which step it is on when sampled is luck - so with a slow spin the
    -- mirrored position path can go untested. It is separate code (a different
    -- bias, and a subtract rather than an add), so force it.
    phase2 = frames + 8
  end
end, emu.eventType.startFrame)

-- Hold the cube on an H-flipped rotation step and confirm the sprites come out
-- mirrored: first entry to the RIGHT of the last, and 16 pixels apart.
emu.addMemoryCallback(function()
  if phase2 == nil or frames < phase2 - 6 then return end
  emu.write(A.gamemode, 0, emu.memType.snesWorkRam)
  emu.write(A.cube_rotate, 0, emu.memType.snesWorkRam)
  emu.write(A.cube_rotate + 1, 19, emu.memType.snesWorkRam)   -- H_FLIP|5
end, emu.callbackType.exec, A.code.drawplayerone, A.code.drawplayerone)

emu.addEventCallback(function()
  if phase2 == nil or frames < phase2 then return end
  local xs, attrs = {}, {}
  for s = 0, 3 do
    if emu.read(s * 4 + 1, emu.memType.snesSpriteRam) < 225 then
      xs[#xs + 1] = emu.read(s * 4, emu.memType.snesSpriteRam)
      attrs[#attrs + 1] = emu.read(s * 4 + 3, emu.memType.snesSpriteRam)
    end
  end
  local hflip = #attrs > 0 and (attrs[1] & 0x40) ~= 0
  local mirrored = #xs > 1 and xs[1] > xs[#xs]
  local width = #xs > 1 and math.abs(xs[1] - xs[#xs]) or 0
  local ok2 = hflip and mirrored and width == 8
  if not ok2 then bad = bad + 1 end
  rows[#rows + 1] = ""
  rows[#rows + 1] = string.format(
    "forced H-flip: x %s attr %02X  %s", table.concat(xs, ","), attrs[1] or 0,
    ok2 and "mirrored, halves 8px apart - ok"
         or "<-- H FLIP DID NOT MIRROR THE OFFSETS")
  rows[#rows + 1] = ""
  rows[#rows + 1] = bad == 0 and "RESULT: EVERY GAMEMODE DRAWS ITS OWN SPRITES"
                              or string.format("RESULT: FAIL - %d wrong", bad)
  local f = io.open(OUT .. "gamemode_sprites.txt", "w")
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  emu.stop(bad == 0 and 0 or 1)
end, emu.eventType.startFrame)
