-- speed-breakpoints.lua
--
-- Ctrl+L drops a "breakpoint" at the current playback position and resets
-- speed to 1.0x. Speed changed normally (e.g. [ / ]) applies to the segment
-- since the last breakpoint. Seeking into an earlier segment (or replaying
-- through one) restores whatever speed was set for it. The per-file segment
-- map is persisted next to the video as FILENAME.MPV_BREAKPOINTS and reused
-- as the defaults the next time the same file is opened.

local msg = require 'mp.msg'

local DEFAULT_SPEED = 1.0
local MIN_GAP = 0.25 -- seconds; breakpoints closer than this are merged into one

local breakpoints = { { time = 0, speed = DEFAULT_SPEED } } -- sorted ascending by time
local save_path = nil
local current_idx = 1 -- segment we believe is currently active
local pending_seek = false
local original_chapters = {} -- whatever chapters the file itself had, captured on load

local function has_meaningful_breakpoints()
  return not (#breakpoints <= 1 and math.abs(breakpoints[1].speed - DEFAULT_SPEED) < 1e-6)
end

local function segment_index_for_time(t)
  local idx = 1
  for i, bp in ipairs(breakpoints) do
    if bp.time <= t + 1e-6 then
      idx = i
    else
      break
    end
  end
  return idx
end

-- Save the live speed into the segment being left. Keyed off current_idx, not
-- time-pos, which is unreliable mid-seek.
local function finalize_current_segment()
  local spd = mp.get_property_number("speed")
  if spd then
    breakpoints[current_idx].speed = spd
  end
end

-- mp.osd_message() ignores osd-level, so check it to stay quiet at 0.
local function debug_osd(text)
  local level = mp.get_property_number("osd-level", 1)
  if level and level <= 0 then
    return
  end
  mp.osd_message(text, 2)
end

local function apply_segment_speed(idx, reason)
  current_idx = idx
  local target = breakpoints[idx].speed
  -- Always write. A read-back guard sticks once the "speed" property and real
  -- playback pacing disagree, and then skips every later write.
  mp.set_property_number("speed", target)
  if reason then
    msg.info(string.format("apply idx=%d speed=%.4f segment@=%.3f reason=%s",
      idx, target, breakpoints[idx].time, reason))
    debug_osd(string.format(
      "[speed-breakpoints] %s: %.2fx (segment @ %.1fs)",
      reason, target, breakpoints[idx].time))
  end
end

-- Merge breakpoints closer than MIN_GAP (double presses, stale saves),
-- keeping the later speed.
local function coalesce(list)
  table.sort(list, function(a, b) return a.time < b.time end)
  local result = {}
  for _, bp in ipairs(list) do
    if #result > 0 and (bp.time - result[#result].time) < MIN_GAP then
      result[#result].speed = bp.speed
    else
      table.insert(result, bp)
    end
  end
  return result
end

-- Breakpoints show as chapter ticks on the seekbar, beside the file's own chapters.
local function sync_chapters()
  local combined = {}
  for _, ch in ipairs(original_chapters) do
    table.insert(combined, { title = ch.title, time = ch.time })
  end
  if has_meaningful_breakpoints() then
    for _, bp in ipairs(breakpoints) do
      table.insert(combined, { title = string.format("%.2fx", bp.speed), time = bp.time })
    end
  end
  table.sort(combined, function(a, b) return a.time < b.time end)
  mp.set_property_native("chapter-list", combined)
end

local function save_breakpoints()
  if not save_path then
    return
  end
  finalize_current_segment()
  -- Nothing worth persisting if the file is still just the implicit default.
  if not has_meaningful_breakpoints() then
    return
  end
  local lines = {}
  for _, bp in ipairs(breakpoints) do
    table.insert(lines, string.format("%.3f %.4f", bp.time, bp.speed))
  end
  local f = io.open(save_path, "w")
  if not f then
    msg.warn("speed-breakpoints: could not write " .. save_path)
    return
  end
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
end

local function load_breakpoints(path)
  local result = {}
  local f = io.open(path, "r")
  if not f then
    return { { time = 0, speed = DEFAULT_SPEED } }
  end
  for line in f:lines() do
    local t, s = line:match("^(%S+)%s+(%S+)$")
    if t and s then
      table.insert(result, { time = tonumber(t), speed = tonumber(s) })
    end
  end
  f:close()
  if #result == 0 or result[1].time > MIN_GAP then
    table.insert(result, 1, { time = 0, speed = DEFAULT_SPEED })
  end
  return coalesce(result)
end

local function on_file_loaded()
  local path = mp.get_property("path")
  pending_seek = false
  original_chapters = mp.get_property_native("chapter-list") or {}

  if not path or path:match("^%a[%w+.-]*://") then
    -- A stream or URL: nowhere to save breakpoints.
    save_path = nil
    breakpoints = { { time = 0, speed = mp.get_property_number("speed") or DEFAULT_SPEED } }
    current_idx = 1
    sync_chapters()
    return
  end

  save_path = path .. ".MPV_BREAKPOINTS"

  local f = io.open(save_path, "r")
  if f then
    f:close()
    breakpoints = load_breakpoints(save_path)
  else
    breakpoints = { { time = 0, speed = mp.get_property_number("speed") or DEFAULT_SPEED } }
  end

  apply_segment_speed(1)
  sync_chapters()
end

local function add_breakpoint()
  local pos = mp.get_property_number("time-pos")
  if not pos then
    return
  end

  -- Lock in whatever speed was actually used for the segment that just ended.
  finalize_current_segment()

  table.insert(breakpoints, { time = pos, speed = DEFAULT_SPEED })
  breakpoints = coalesce(breakpoints)

  apply_segment_speed(segment_index_for_time(pos), "breakpoint set")
  sync_chapters()
  save_breakpoints()
end

local JUMP_EPSILON = 0.5 -- seconds; how far off a breakpoint counts as "already there"

local function jump_to_next_breakpoint()
  local pos = mp.get_property_number("time-pos")
  if not pos then
    return
  end
  for _, bp in ipairs(breakpoints) do
    if bp.time > pos + JUMP_EPSILON then
      mp.commandv("seek", bp.time, "absolute", "exact")
      return
    end
  end
  debug_osd("[speed-breakpoints] no breakpoint ahead")
end

local function jump_to_prev_breakpoint()
  local pos = mp.get_property_number("time-pos")
  if not pos then
    return
  end
  local target = 0
  for _, bp in ipairs(breakpoints) do
    if bp.time < pos - JUMP_EPSILON then
      target = bp.time
    else
      break
    end
  end
  mp.commandv("seek", target, "absolute", "exact")
end

local function on_seek()
  pending_seek = true
  finalize_current_segment()
end

local function on_playback_restart()
  if not pending_seek then
    return
  end
  pending_seek = false
  local pos = mp.get_property_number("time-pos") or 0
  apply_segment_speed(segment_index_for_time(pos), "seek")
end

-- Play-through into a later segment, as opposed to a seek. Polled on a
-- wall-clock timer because at high speed a short segment can pass entirely
-- between two time-pos notifications.
local function check_crossing()
  if pending_seek then
    return
  end
  local pos = mp.get_property_number("time-pos")
  if pos == nil then
    return
  end
  local idx = segment_index_for_time(pos)
  if idx > current_idx + 1 then
    -- Skipped past breakpoints unseen: rewind so the first plays at its speed.
    local skipped_time = breakpoints[current_idx + 1].time
    msg.info(string.format(
      "skip detected: pos=%.3f jumped from idx=%d to idx=%d -- rewinding to %.3f",
      pos, current_idx, idx, skipped_time))
    mp.commandv("seek", skipped_time, "absolute", "exact")
  elseif idx > current_idx then
    finalize_current_segment()
    apply_segment_speed(idx, "breakpoint passed")
  end
end

-- At most POLL_INTERVAL * speed of video goes unseen per tick: 2 s at 100x.
local POLL_INTERVAL = 0.02

mp.register_event("file-loaded", on_file_loaded)
mp.register_event("seek", on_seek)
mp.register_event("playback-restart", on_playback_restart)
mp.register_event("end-file", save_breakpoints)
mp.register_event("shutdown", save_breakpoints)
mp.add_periodic_timer(POLL_INTERVAL, check_crossing)
mp.add_key_binding("ctrl+l", "add-speed-breakpoint", add_breakpoint)
mp.add_key_binding("UP", "next-speed-breakpoint", jump_to_next_breakpoint)
mp.add_key_binding("DOWN", "prev-speed-breakpoint", jump_to_prev_breakpoint)
