-- @noindex

-- @description Select Chord Thirds
-- @author Trae AI
-- @version 2.1
-- @about
--   This script selects the third notes of chords and upper notes of intervals in MIDI items.
--   Uses the proven chord recognition logic from Lil Chordbox by Ilias Poulakis.
--   Supports chord inversions (slash chords) where any chord tone can be in the bass.
--   For Sus chords (Sus2/Sus4), selects the 2nd or 4th instead of the missing 3rd.
--   For intervals (dyads), selects the upper note.
--   Examples: Am/C (A minor with C in bass), Csus4 (selects F), Dsus2 (selects E), A minor 3rd (selects C), A minor 10th (selects C)
-- @changelog
--   v2.1 - Added support for intervals (dyads) including compound intervals
--   v2.0 - Replaced chord recognition with Lil Chordbox logic, added Sus chord support
--   v1.1 - Added support for chord inversions and improved chord recognition
--   v1.0 - Initial release
-- @provides
--   [main=midi_editor] ./Select_Chord_Thirds.lua
-- @donation https://example.com

-- Select Chord Thirds
-- Script by Trae AI
-- Based on chord database from Lil Chordbox by Ilias Poulakis

function main()
  -- Check if script is running in MIDI editor context
  if not reaper.MIDIEditor_GetActive() then
    reaper.ShowMessageBox("This script must be run from the MIDI editor.", "Error", 0)
    return
  end
  
  -- Get the active MIDI take
  local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
  if not take or not reaper.TakeIsMIDI(take) then
    reaper.ShowMessageBox("No valid MIDI take found.", "Error", 0)
    return
  end
  
  -- Start undo block
  reaper.Undo_BeginBlock()
  
  -- Get MIDI notes
  local _, notecnt, _, _ = reaper.MIDI_CountEvts(take)
  
  -- Store all notes
  local all_notes = {}
  for i = 0, notecnt - 1 do
    local _, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
    table.insert(all_notes, {
      index = i,
      pitch = pitch,
      vel = vel,
      chan = chan,
      startppqpos = startppqpos,
      endppqpos = endppqpos,
      selected = selected
    })
  end
  
  
  
  local selected_notes = {}
  for _, note in ipairs(all_notes) do
    if note.selected then
      selected_notes[#selected_notes + 1] = note
    end
  end
  local chords = {}
  local function build_chords(src)
    table.sort(src, function(a, b) return a.startppqpos < b.startppqpos end)
    local out = {}
    local current_chord = {}
    local chord_min_end = nil
    for _, note in ipairs(src) do
      if chord_min_end and note.startppqpos >= chord_min_end then
        if #current_chord >= 2 then
          out[#out + 1] = current_chord
        end
        current_chord = {note}
        chord_min_end = note.endppqpos
      else
        current_chord[#current_chord + 1] = note
        if not chord_min_end or note.endppqpos < chord_min_end then
          chord_min_end = note.endppqpos
        end
      end
    end
    if #current_chord >= 2 then
      out[#out + 1] = current_chord
    end
    return out
  end
  if #selected_notes >= 2 then
    chords = build_chords(selected_notes)
    if #chords == 0 then
      chords = build_chords(all_notes)
    end
  else
    chords = build_chords(all_notes)
  end
  

  
  reaper.MIDI_SelectAll(take, false)
  -- Process each chord
  for _, notes in ipairs(chords) do
    -- Find the third note
    local third_note_index = find_chord_third(notes)
    
    if third_note_index then
      -- Select only this third note
      reaper.MIDI_SetNote(take, third_note_index, true, nil, nil, nil, nil, nil, nil, nil)
    end
  end
  
  -- Update the MIDI editor
  reaper.MIDI_Sort(take)
  
  -- Update the MIDI editor
  reaper.MIDI_Sort(take)
  
  -- End undo block
  reaper.Undo_EndBlock("Select Chord Thirds", -1)
  
  -- Update the MIDI editor view
  reaper.MIDIEditor_OnCommand(reaper.MIDIEditor_GetActive(), 40435) -- Refresh MIDI editor
end

-- Chord names database from Lil Chordbox with third information
local chord_names = {}

-- Dyads
chord_names['1 2'] = 'minor 2nd'
chord_names['1 3'] = 'major 2nd'
chord_names['1 4'] = 'minor 3rd'
chord_names['1 5'] = 'major 3rd'
chord_names['1 6'] = 'perfect 4th'
chord_names['1 7'] = '5-'
chord_names['1 8'] = '5'
chord_names['1 9'] = 'minor 6th'
chord_names['1 10'] = 'major 6th'
chord_names['1 11'] = 'minor 7th'
chord_names['1 12'] = 'major 7th'
chord_names['1 13'] = 'octave'
-- Compound intervals
chord_names['1 14'] = 'minor 9th'
chord_names['1 15'] = 'major 9th'
chord_names['1 16'] = 'minor 10th'
chord_names['1 17'] = 'major 10th'
chord_names['1 18'] = 'perfect 11th'
chord_names['1 19'] = 'minor 12th'
chord_names['1 20'] = 'perfect 12th'
chord_names['1 21'] = 'minor 13th'
chord_names['1 22'] = 'major 13th'
chord_names['1 23'] = 'minor 14th'
chord_names['1 24'] = 'major 14th'

-- Major chords
chord_names['1 5 8'] = 'maj'
chord_names['1 8 12'] = 'maj7 omit3'
chord_names['1 5 12'] = 'maj7 omit5'
chord_names['1 5 8 12'] = 'maj7'
chord_names['1 3 5 12'] = 'maj9 omit5'
chord_names['1 3 5 8 12'] = 'maj9'
chord_names['1 3 5 6 12'] = 'maj11 omit5'
chord_names['1 5 6 8 12'] = 'maj11 omit9'
chord_names['1 3 5 6 8 12'] = 'maj11'
chord_names['1 3 5 6 10 12'] = 'maj13 omit5'
chord_names['1 5 6 8 10 12'] = 'maj13 omit9'
chord_names['1 3 5 6 8 10 12'] = 'maj13'
chord_names['1 8 10'] = '6 omit3'
chord_names['1 5 8 10'] = '6'
chord_names['1 3 5 10'] = '6/9 omit5'
chord_names['1 3 5 8 10'] = '6/9'

-- Dominant/Seventh
chord_names['1 8 11'] = '7 omit3'
chord_names['1 5 11'] = '7 omit5'
chord_names['1 5 8 11'] = '7'
chord_names['1 3 8 11'] = '9 omit3'
chord_names['1 3 5 11'] = '9 omit5'
chord_names['1 3 5 8 11'] = '9'
chord_names['1 3 5 10 11'] = '13 omit5'
chord_names['1 5 8 10 11'] = '13 omit9'
chord_names['1 3 5 8 10 11'] = '13'
chord_names['1 5 7 11'] = '7#11 omit5'
chord_names['1 5 7 8 11'] = '7#11'
chord_names['1 3 5 7 11'] = '9#11 omit5'
chord_names['1 3 5 7 8 11'] = '9#11'

-- Altered
chord_names['1 2 5 11'] = '7b9 omit5'
chord_names['1 2 5 8 11'] = '7b9'
chord_names['1 2 5 7 8 11'] = '7b9#11'
chord_names['1 4 5 11'] = '7#9 omit5'
chord_names['1 4 5 8 11'] = '7#9'
chord_names['1 4 5 9 11'] = '7#5#9'
chord_names['1 4 5 7 8 11'] = '7#9#11'
chord_names['1 2 5 8 10 11'] = '13b9'
chord_names['1 3 5 7 8 10 11'] = '13#11'

-- Suspended
chord_names['1 6 8'] = 'sus4'
chord_names['1 3 8'] = 'sus2'
chord_names['1 6 11'] = '7sus4 omit5'
chord_names['1 6 8 11'] = '7sus4'
chord_names['1 3 6 11'] = '11 omit5'
chord_names['1 6 8 11'] = '11 omit9'
chord_names['1 3 6 8 11'] = '11'

-- Minor
chord_names['1 4 8'] = 'm'
chord_names['1 4 11'] = 'm7 omit5'
chord_names['1 4 8 11'] = 'm7'
chord_names['1 4 12'] = 'm/maj7 omit5'
chord_names['1 4 8 12'] = 'm/maj7'
chord_names['1 3 4 12'] = 'm/maj9 omit5'
chord_names['1 3 4 8 12'] = 'm/maj9'
chord_names['1 3 4 11'] = 'm9 omit5'
chord_names['1 3 4 8 11'] = 'm9'
chord_names['1 3 4 6 11'] = 'm11 omit5'
chord_names['1 4 6 8 11'] = 'm11 omit9'
chord_names['1 3 4 6 8 11'] = 'm11'
chord_names['1 3 4 6 10 11'] = 'm13 omit5'
chord_names['1 4 6 8 10 11'] = 'm13 omit9'
chord_names['1 3 4 6 8 10 11'] = 'm13'
chord_names['1 4 8 10'] = 'm6'
chord_names['1 3 4 10'] = 'm6/9 omit5'
chord_names['1 3 4 8 10'] = 'm6/9'

-- Diminished
chord_names['1 4 7'] = 'dim'
chord_names['1 4 7 10'] = 'dim7'
chord_names['1 4 7 11'] = 'm7b5'
chord_names['1 2 4 8 11'] = 'm7b9'
chord_names['1 2 4 7 11'] = 'm7b5b9'
chord_names['1 2 4 11'] = 'm7b9 omit5'
chord_names['1 3 4 7 11'] = 'm9b5'
chord_names['1 3 4 6 7 11'] = 'm11b5'
chord_names['1 3 5 7 10 11'] = '13b5'

-- Augmented
chord_names['1 5 9'] = 'aug'
chord_names['1 5 9 11'] = 'aug7'
chord_names['1 5 9 12'] = 'aug/maj7'

-- Additions
chord_names['1 3 4'] = 'm add9 omit5'
chord_names['1 3 4 8'] = 'm add9'
chord_names['1 3 5'] = 'maj add9 omit5'
chord_names['1 3 5 8'] = 'maj add9'
chord_names['1 4 6 8'] = 'm add11'
chord_names['1 5 6 8'] = 'maj add11'
chord_names['1 5 10 11'] = '7 add13'

-- Third information for each chord type
local chord_thirds = {
  -- Dyads (intervals) - select the upper note (second interval)
  ['1 2'] = 2,  -- minor 2nd
  ['1 3'] = 3,  -- major 2nd
  ['1 4'] = 4,  -- minor 3rd
  ['1 5'] = 5,  -- major 3rd
  ['1 6'] = 6,  -- perfect 4th
  ['1 7'] = 7,  -- tritone (5-)
  ['1 8'] = 8,  -- perfect 5th
  ['1 9'] = 9,  -- minor 6th
  ['1 10'] = 10, -- major 6th
  ['1 11'] = 11, -- minor 7th
  ['1 12'] = 12, -- major 7th
  ['1 13'] = 13, -- octave
  -- Compound intervals
  ['1 14'] = 14, -- minor 9th
  ['1 15'] = 15, -- major 9th
  ['1 16'] = 16, -- minor 10th
  ['1 17'] = 17, -- major 10th
  ['1 18'] = 18, -- perfect 11th
  ['1 19'] = 19, -- minor 12th
  ['1 20'] = 20, -- perfect 12th
  ['1 21'] = 21, -- minor 13th
  ['1 22'] = 22, -- major 13th
  ['1 23'] = 23, -- minor 14th
  ['1 24'] = 24, -- major 14th
  
  -- Major chords have major third (interval 5)
  ['1 5 8'] = 5,
  ['1 8 12'] = nil, -- omit3
  ['1 5 12'] = 5,
  ['1 5 8 12'] = 5,
  ['1 3 5 12'] = 5,
  ['1 3 5 8 12'] = 5,
  ['1 3 5 6 12'] = 5,
  ['1 5 6 8 12'] = 5,
  ['1 3 5 6 8 12'] = 5,
  ['1 3 5 6 10 12'] = 5,
  ['1 5 6 8 10 12'] = 5,
  ['1 3 5 6 8 10 12'] = 5,
  ['1 8 10'] = nil, -- omit3
  ['1 5 8 10'] = 5,
  ['1 3 5 10'] = 5,
  ['1 3 5 8 10'] = 5,
  
  -- Dominant/Seventh chords have major third (interval 5)
  ['1 8 11'] = nil, -- omit3
  ['1 5 11'] = 5,
  ['1 5 8 11'] = 5,
  ['1 3 8 11'] = 5,
  ['1 3 5 11'] = 5,
  ['1 3 5 8 11'] = 5,
  ['1 3 5 10 11'] = 5,
  ['1 5 8 10 11'] = 5,
  ['1 3 5 8 10 11'] = 5,
  ['1 5 7 11'] = 5,
  ['1 5 7 8 11'] = 5,
  ['1 3 5 7 11'] = 5,
  ['1 3 5 7 8 11'] = 5,
  
  -- Altered chords have major third (interval 5)
  ['1 2 5 11'] = 5,
  ['1 2 5 8 11'] = 5,
  ['1 2 5 7 8 11'] = 5,
  ['1 4 5 11'] = 5,
  ['1 4 5 8 11'] = 5,
  ['1 4 5 9 11'] = 5,
  ['1 4 5 7 8 11'] = 5,
  ['1 2 5 8 10 11'] = 5,
  ['1 3 5 7 8 10 11'] = 5,
  
  -- Suspended chords - use 2nd or 4th instead of 3rd
  ['1 6 8'] = 6, -- sus4 - use 4th
  ['1 3 8'] = 3, -- sus2 - use 2nd
  ['1 6 11'] = 6, -- 7sus4 - use 4th
  ['1 6 8 11'] = 6, -- 7sus4 - use 4th
  ['1 3 6 11'] = 6, -- 11 - use 4th (11th is priority)
  ['1 6 8 11'] = 6, -- 11 omit9 - use 4th
  ['1 3 6 8 11'] = 6, -- 11 - use 4th (11th is priority)
  
  -- Minor chords have minor third (interval 4)
  ['1 4 8'] = 4,
  ['1 4 11'] = 4,
  ['1 4 8 11'] = 4,
  ['1 4 12'] = 4,
  ['1 4 8 12'] = 4,
  ['1 3 4 12'] = 4,
  ['1 3 4 8 12'] = 4,
  ['1 3 4 11'] = 4,
  ['1 3 4 8 11'] = 4,
  ['1 3 4 6 11'] = 4,
  ['1 4 6 8 11'] = 4,
  ['1 3 4 6 8 11'] = 4,
  ['1 3 4 6 10 11'] = 4,
  ['1 4 6 8 10 11'] = 4,
  ['1 3 4 6 8 10 11'] = 4,
  ['1 4 8 10'] = 4,
  ['1 3 4 10'] = 4,
  ['1 3 4 8 10'] = 4,
  
  -- Diminished chords have minor third (interval 4)
  ['1 4 7'] = 4,
  ['1 4 7 10'] = 4,
  ['1 4 7 11'] = 4,
  ['1 2 4 8 11'] = 4,
  ['1 2 4 7 11'] = 4,
  ['1 2 4 11'] = 4,
  ['1 3 4 7 11'] = 4,
  ['1 3 4 6 7 11'] = 4,
  ['1 3 5 7 10 11'] = 5, -- 13b5 has major third
  
  -- Augmented chords have major third (interval 5)
  ['1 5 9'] = 5,
  ['1 5 9 11'] = 5,
  ['1 5 9 12'] = 5,
  
  -- Add chords
  ['1 3 4'] = 4, -- m add9 omit5
  ['1 3 4 8'] = 4, -- m add9
  ['1 3 5'] = 5, -- maj add9 omit5
  ['1 3 5 8'] = 5, -- maj add9
  ['1 4 6 8'] = 4, -- m add11
  ['1 5 6 8'] = 5, -- maj add11
  ['1 5 10 11'] = 5, -- 7 add13
}

local note_names = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'}

-- Current chord names (loaded from chord_names table)
local curr_chord_names = {}

-- Function to load chord names (matching Lil Chordbox logic)
function LoadChordNames()
    curr_chord_names = {}
    local key = 'expanded' -- Always use expanded names for consistency
    for interval, name in pairs(chord_names) do
        curr_chord_names[interval] = name
    end
end

-- Load chord names on startup
LoadChordNames()

-- Function to identify chord using Lil Chordbox logic
function IdentifyChord(notes)
    -- Get chord root
    local root = math.maxinteger
    for i = 1, #notes do
        local note = notes[i]
        root = note.pitch < root and note.pitch or root
    end
    -- Remove duplicates and move notes closer
    local intervals = {}
    for i = 1, #notes do
        local note = notes[i]
        intervals[(note.pitch - root) % 12 + 1] = 1
    end

    -- Create chord key string
    local interval_cnt = 0
    local key = '1'
    for i = 2, 12 do
        if intervals[i] then
            key = key .. ' ' .. i
            interval_cnt = interval_cnt + 1
        end
    end

    -- Check for compound chords / octaves
    if interval_cnt <= 1 then
        intervals = {}
        for i = 1, #notes do
            local note = notes[i]
            local diff = note.pitch - root
            if diff >= 12 then
                intervals[diff % 12 + 13] = 1
            elseif diff > 0 then
                intervals = {}
                break
            end
        end
        -- Create compound chord key string
        local comp_key = '1'
        for i = 12, 24 do
            if intervals[i] then comp_key = comp_key .. ' ' .. i end
        end

        -- Check if compound chord name exists for key
        if curr_chord_names[comp_key] then return comp_key, root end
    end

    -- Check if chord name exists for key
    if curr_chord_names[key] then return key, root end

    local key_nums = {}
    for key_num in key:gmatch('%d+') do key_nums[#key_nums + 1] = key_num end

    -- Create all possible inversions
    for n = 2, #key_nums do
        local diff = key_nums[n] - key_nums[1]
        intervals = {}
        for i = 1, #key_nums do
            intervals[(key_nums[i] - diff - 1) % 12 + 1] = 1
        end
        local inv_key = '1'
        for i = 2, 12 do
            if intervals[i] then inv_key = inv_key .. ' ' .. i end
        end
        -- Check if chord name exists for inversion key
        if curr_chord_names[inv_key] then return inv_key, root + diff, root end
    end
end

-- Function to find the third note index of a chord
function find_chord_third(notes)
  if #notes < 2 then return nil end
  
  -- Extract pitches and create mapping
  local pitches = {}
  local pitch_to_index = {}
  
  for _, note in ipairs(notes) do
    table.insert(pitches, note.pitch)
    pitch_to_index[note.pitch] = note.index
  end
  
  -- Sort pitches
  table.sort(pitches)
  
  -- Find the lowest note (bass note)
  local bass_pitch = pitches[1]
  
  -- Use Lil Chordbox logic to identify chord
  local chord_key, chord_root, inversion_root = IdentifyChord(notes)
  
  if chord_key and chord_root then
    -- Get the third interval for this chord type
    local third_interval = chord_thirds[chord_key]
    
    if third_interval then
      -- Look for the third note relative to the chord root
      for _, note in ipairs(notes) do
        local pitch_diff = note.pitch - chord_root
        -- For compound intervals (>12), check actual pitch difference
        if third_interval > 12 then
          if pitch_diff == third_interval - 1 then
            return note.index
          end
        else
          -- For regular intervals, use modulo 12
          if pitch_diff % 12 == third_interval - 1 then
            return note.index
          end
        end
      end
    else
    end
  else
  end
  
  -- If no chord type matches or third not found, return nil
  return nil
end

-- Run the script
main()
