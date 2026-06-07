-- @noindex

--Author - Mr. Frenkie
--Inspired by FeedTheCat Lil Chordbox

local editor = reaper.MIDIEditor_GetActive()
if not editor then reaper.MB("Open the MIDI Editor.", "Error", 0) return end

local take = reaper.MIDIEditor_GetTake(editor)
if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then reaper.MB("No active take in the MIDI Editor.", "Error", 0) return end

do
  local now = reaper.time_precise()
  local ext = reaper.GetExtState("UniversalTriad", "last_time")
  local last = (ext == nil or ext == "") and 0 or (tonumber(ext) or 0)
  if last > 0 and (now - last) < 0.2 then return end
  reaper.SetExtState("UniversalTriad", "last_time", tostring(now), false)
end

local is_key_snap, scale_root, scale_mask = reaper.MIDI_GetScale(take)
local scale_enabled = (scale_mask and scale_mask ~= 0)

local steps = {}
if scale_enabled then
  for i = 0, 11 do
    local mask = (1 << i)
    if (scale_mask & mask) ~= 0 then steps[#steps + 1] = i end
  end
  if #steps < 3 then reaper.MB("Current scale contains fewer than 3 degrees.", "Error", 0) return end
end

local retval, note_cnt, cc_cnt, sysex_cnt = reaper.MIDI_CountEvts(take)

local sel_pitch, sel_chan, sel_vel, sel_len_ppq
for i = 0, note_cnt - 1 do
  local _, selected, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
  if selected and not muted then sel_pitch = pitch sel_chan = chan sel_vel = vel sel_len_ppq = eppq - sppq break end
end
if not sel_pitch then
  local row = reaper.MIDIEditor_GetSetting_int(editor, 'active_note_row')
  if type(row) == 'number' and row >= 0 and row <= 127 then
    sel_pitch = row
    sel_chan = 0
    sel_vel = 96
  else
    return
  end
end

local function mod12(x)
  local r = x % 12
  if r < 0 then r = r + 12 end
  return r
end

local pc = mod12(sel_pitch - scale_root)
local deg_idx
if scale_enabled then
  for i = 1, #steps do if steps[i] == pc then deg_idx = i break end end
  if not deg_idx then
    local best_i, best_d = nil, 99
    for i = 1, #steps do
      local d = math.abs(pc - steps[i])
      if d > 6 then d = 12 - d end
      if d < best_d then best_d = d best_i = i end
    end
    deg_idx = best_i
  end
  if not deg_idx then reaper.MB("Could not determine the degree for the selected note.", "Error", 0) return end
end

local r, int3, int5, quality
if scale_enabled then
  r = steps[deg_idx]
  local i3 = ((deg_idx + 2 - 1) % #steps) + 1
  local i5 = ((deg_idx + 4 - 1) % #steps) + 1
  local t3 = steps[i3]
  local t5 = steps[i5]
  if i3 <= deg_idx then t3 = t3 + 12 end
  if i5 <= deg_idx then t5 = t5 + 12 end
  int3 = mod12(t3 - r)
  int5 = mod12(t5 - r)
  if int3 == 4 and int5 == 7 then quality = "major"
  elseif int3 == 3 and int5 == 7 then quality = "minor"
  elseif int3 == 3 and int5 == 6 then quality = "diminished"
  elseif int3 == 4 and int5 == 8 then quality = "augmented"
  else quality = "undefined" end
else
  int3 = 3
  int5 = 7
  quality = "minor"
end

local row_pitch = reaper.MIDIEditor_GetSetting_int(editor, 'active_note_row')
if type(row_pitch) ~= 'number' or row_pitch < 0 or row_pitch > 127 then return end
local target_root
if scale_enabled then
  local sel_pc_abs = mod12(sel_pitch)
  local target_pc_abs = mod12(scale_root + r)
  local delta = target_pc_abs - sel_pc_abs
  if delta > 6 then delta = delta - 12 end
  if delta < -6 then delta = delta + 12 end
  target_root = sel_pitch + delta
else
  target_root = sel_pitch
end
local offset = target_root - row_pitch
while offset > 12 do offset = offset - 12 end
while offset < -12 do offset = offset + 12 end
reaper.Undo_BeginBlock2(0)
reaper.PreventUIRefresh(1)
reaper.MIDI_SelectAll(take, false)
reaper.MIDIEditor_OnCommand(editor, 40164 + offset)
local _, new_note_cnt = reaper.MIDI_CountEvts(take)
local root_sppq, root_eppq, root_pitch_ins, root_vel_ins, root_chan_ins
for i = 0, new_note_cnt - 1 do
  local _, selected, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
  if selected and not muted and eppq and sppq and eppq > sppq then
    root_sppq = sppq
    root_eppq = eppq
    root_pitch_ins = pitch
    root_vel_ins = vel
    root_chan_ins = chan
    break
  end
end
if not root_pitch_ins or not root_sppq or not root_eppq then reaper.PreventUIRefresh(-1) reaper.Undo_EndBlock2(0, "Insert triad: canceled", -1) return end
local len_ppq = math.max(1, math.floor(root_eppq - root_sppq + 0.5))
local third_pitch = root_pitch_ins + int3
local fifth_pitch = root_pitch_ins + int5
reaper.MIDI_InsertNote(take, true, false, root_sppq, root_sppq + len_ppq, root_chan_ins or (sel_chan or 0), third_pitch, root_vel_ins or (sel_vel or 96), false)
reaper.MIDI_InsertNote(take, true, false, root_sppq, root_sppq + len_ppq, root_chan_ins or (sel_chan or 0), fifth_pitch, root_vel_ins or (sel_vel or 96), false)
reaper.MIDI_Sort(take)
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock2(0, "Insert triad: " .. quality, -1)
