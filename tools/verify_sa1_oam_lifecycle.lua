-- SA-1 OAM lifecycle regression.
--
-- At the S-CPU flush boundary, sprid is the exact byte count emitted by the
-- SA-1 for this frame. After the flush, every entry below it must match the
-- captured shadow and every entry above it must be hidden. This catches stale
-- tail entries independently of which level object happened to own the slot.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")

local B = emu.memType.snesSaveRam
local O = emu.memType.snesSpriteRam
local TEST_LEVEL = tonumber(os.getenv("LEVEL")) or 0
local STOP_AT = tonumber(os.getenv("FRAMES")) or 1800

local frames, gameplay, menu_frames = 0, 0, 0
local entered, press = false, false
local pending = false
local expected_used = 0
local expected_y = {}
local checked, ghost_frames, mismatch_frames = 0, 0, 0
local worst_ghosts, worst_mismatch = 0, 0
local first_problem

local function rd(addr, width)
  local value = 0
  for i = 0, (width or 1) - 1 do
    value = value + emu.read(addr + i, B, false) * (256 ^ i)
  end
  return value
end

emu.addEventCallback(function()
  if press or entered then emu.setInput({a = true}, 0) end
end, emu.eventType.inputPolled)

-- This routine runs on the S-CPU and is therefore observable even though the
-- producer gameplay code runs on the SA-1.
emu.addMemoryCallback(function()
  if not entered then return end
  expected_used = rd(A.sprid, 2) // 4
  if expected_used > 128 then expected_used = 128 end
  for sprite = 0, expected_used - 1 do
    expected_y[sprite] = rd(A.oam_buf + sprite * 4 + 1)
  end
  pending = true
end, emu.callbackType.exec, A.code.shim_scpu_flush, A.code.shim_scpu_flush)

local function finish()
  local ok = entered and checked > 300
             and ghost_frames == 0 and mismatch_frames == 0
  local rows = {
    string.format("level=%d gameplay=%d checked flushes=%d",
                  TEST_LEVEL, gameplay, checked),
    string.format("ghost frames=%d worst stale tail=%d",
                  ghost_frames, worst_ghosts),
    string.format("mismatch frames=%d worst live-prefix mismatch=%d",
                  mismatch_frames, worst_mismatch),
    first_problem and ("first problem: " .. first_problem)
                  or "first problem: none",
    ok and "RESULT: SA-1 OAM LIFECYCLE OK"
       or "RESULT: FAIL - STALE OR MISMATCHED SA-1 OAM",
  }
  local file = assert(io.open(OUT .. "sa1_oam_lifecycle.txt", "w"))
  file:write(table.concat(rows, "\n") .. "\n")
  file:close()
  emu.stop(ok and 0 or 1)
end

emu.addEventCallback(function()
  frames = frames + 1
  if not entered then
    if rd(A.shim_menu_active) ~= 0 then
      menu_frames = menu_frames + 1
      emu.write(A.menu_sel, TEST_LEVEL, B)
      press = menu_frames >= 30 and menu_frames <= 45
    else
      press = false
      if menu_frames > 0 and rd(A.gameState) == 2
         and rd(A.level) == TEST_LEVEL then
        entered = true
      end
    end
    if frames >= 1200 and not entered then finish() end
    return
  end

  gameplay = gameplay + 1
  -- Keep the run moving through hazards so sprite-heavy windows are reached.
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, B)

  if pending then
    local ghosts, mismatch = 0, 0
    for sprite = 0, 127 do
      local y = emu.read(sprite * 4 + 1, O, false)
      if sprite < expected_used then
        if y ~= expected_y[sprite] then mismatch = mismatch + 1 end
      elseif y < 225 then
        ghosts = ghosts + 1
      end
    end
    checked = checked + 1
    if ghosts ~= 0 then
      ghost_frames = ghost_frames + 1
      if ghosts > worst_ghosts then worst_ghosts = ghosts end
    end
    if mismatch ~= 0 then
      mismatch_frames = mismatch_frames + 1
      if mismatch > worst_mismatch then worst_mismatch = mismatch end
    end
    if not first_problem and (ghosts ~= 0 or mismatch ~= 0) then
      first_problem = string.format(
        "video=%d gameplay=%d used=%d ghosts=%d mismatch=%d scroll=%d",
        frames, gameplay, expected_used, ghosts, mismatch, rd(A.scroll_x, 2))
    end
    pending = false
  end

  if gameplay >= STOP_AT then finish() end
end, emu.eventType.endFrame)
