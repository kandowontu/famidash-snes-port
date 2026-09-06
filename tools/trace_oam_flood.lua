-- What is putting 124 sprites in OAM?
--
-- verify_framerate.lua found a 300-frame window at 22% speed with the sprite
-- table essentially full. This reports the game state, the sprid cursor and the
-- tiles in use across that window, so the answer is "this state machine arm" or
-- "this metasprite", not a guess.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local FIRST, LAST, STEP = 2400, 2900, 50

emu.addEventCallback(function() emu.setInput({ a = true }, 0) end,
                     emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
  emu.write(A.cube_data + 1, emu.read(A.cube_data + 1, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local function wram(addr, n)
  local v = 0
  for i = 0, (n or 1) - 1 do
    v = v + emu.read(addr + i, emu.memType.snesWorkRam) * (256 ^ i)
  end
  return v
end

-- Count the calls that can put sprites in the table, to apportion the flood.
local calls = {}
for _, n in ipairs({ "oam_spr", "oam_meta_spr", "oam_meta_spr_disco",
                     "oam_meta_spr_flipped", "oam_clear", "drawplayerone",
                     "draw_sprites", "trail_loop", "put_number",
                     "put_progress_bar_sprite", "state_lvldone", "state_game",
                     "death_animation", "reset_level" }) do
  if A.code[n] then
    calls[n] = 0
    emu.addMemoryCallback(function() calls[n] = calls[n] + 1 end,
                          emu.callbackType.exec, A.code[n], A.code[n])
  end
end

local frames, rows, prev = 0, {}, {}
emu.addEventCallback(function()
  frames = frames + 1
  if frames < FIRST or frames > LAST or frames % STEP ~= 0 then
    if frames == LAST + 1 then
      local f = io.open(OUT .. "oam_flood.txt", "w")
      f:write(table.concat(rows, "\n") .. "\n"); f:close()
      emu.stop(0)
    end
    return
  end

  local live, tiles = 0, {}
  for s = 0, 127 do
    if emu.read(s * 4 + 1, emu.memType.snesSpriteRam) < 225 then
      live = live + 1
      local t = emu.read(s * 4 + 2, emu.memType.snesSpriteRam)
      local a = emu.read(s * 4 + 3, emu.memType.snesSpriteRam)
      local tile = t + (a % 2) * 256
      tiles[tile] = (tiles[tile] or 0) + 1
    end
  end
  local tl = {}
  for t, n in pairs(tiles) do tl[#tl + 1] = string.format("%d x%d", t, n) end
  table.sort(tl, function(a, b)
    return tonumber(a:match("^%d+")) < tonumber(b:match("^%d+")) end)

  local delta = {}
  for n, v in pairs(calls) do
    local d = v - (prev[n] or 0)
    if d > 0 then delta[#delta + 1] = string.format("%s x%d", n, d) end
    prev[n] = v
  end
  table.sort(delta)

  rows[#rows + 1] = string.format(
    "f%-5d gameState=%02X live=%-4d sprid=%-4d scroll_x=%-6d exittimer=%d",
    frames, wram(A.gameState), live, wram(A.sprid, 2), wram(A.scroll_x, 2),
    wram(A.exittimer))
  rows[#rows + 1] = "    since last: " .. table.concat(delta, ", ")
  rows[#rows + 1] = "    tiles: " .. table.concat(tl, ", ")
end, emu.eventType.startFrame)
