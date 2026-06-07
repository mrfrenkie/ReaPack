-- @noindex

---@diagnostic disable: undefined-global, undefined-field
local r = reaper
local Utils = require("Utils")

local Track = {}
local parse_fip_state_str
local get_fip_track_state

function Track.GetSelectedTracks()
    local count = r.CountSelectedTracks(0)
    if count == 0 then
        return {}
    end
    local tracks = {}
    for i = 0, count - 1 do
        local track = r.GetSelectedTrack(0, i)
        if track and r.ValidatePtr(track, "MediaTrack*") then
            tracks[#tracks + 1] = track
        end
    end
    return tracks
end

function Track.FreezeTracks(tracks)
    r.Main_OnCommand(41223, 0)
end

function Track.UnfreezeTracks(tracks)
    r.Main_OnCommand(41644, 0)
end

function Track.GetFreezeCountForTrack(track)
    if not track or not r.ValidatePtr(track, 'MediaTrack*') then return 0 end
    local val = r.FIP_GetTrackFreezeCountVal(track, "", 0)
    return math.floor(val or 0)
end

function Track.GetTrackName(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return "" end
    if not (r.APIExists and r.APIExists("FIP_GetTrackNameStr")) then return "" end
    return r.FIP_GetTrackNameStr(track, "", 0) or ""
end

function Track.SetTrackName(track, name)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if not (r.APIExists and r.APIExists("FIP_SetTrackNameStr")) then return false end
    local ret = r.FIP_SetTrackNameStr(track, name or "", 0)
    return (tonumber(ret) or 0) > 0.5
end

function Track.GetTrackNotes(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return "" end
    if not (r.APIExists and r.APIExists("FIP_GetTrackNotesStr")) then return "" end
    return r.FIP_GetTrackNotesStr(track, "", 0) or ""
end

function Track.GetInstrumentFXIndex(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    if not (r.APIExists and r.APIExists("FIP_GetTrackInstrumentFXIndexVal")) then return nil end
    local raw_idx = r.FIP_GetTrackInstrumentFXIndexVal(track, "", 0)
    local idx = math.floor(tonumber(raw_idx) or -1)
    return idx >= 0 and idx or nil
end

function Track.HasInstrument(track)
    return Track.GetInstrumentFXIndex(track) ~= nil
end

function Track.OpenInstrumentUI(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if not (r.APIExists and r.APIExists("FIP_OpenTrackInstrumentUIVal")) then return false end
    local ret = r.FIP_OpenTrackInstrumentUIVal(track, "", 0)
    return (tonumber(ret) or 0) > 0.5
end

function Track.IsInstrumentUIOpen(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if not (r.APIExists and r.APIExists("FIP_GetTrackInstrumentUIOpenVal")) then return false end
    local ret = r.FIP_GetTrackInstrumentUIOpenVal(track, "", 0)
    return (tonumber(ret) or 0) > 0.5
end

function Track.GetMidiTransposeState(track)
    local state = get_fip_track_state(track, "FIP_GetTrackMidiTransposeStateStr") or {}
    state.exists = (tonumber(state.exists) or 0) > 0
    state.semitones = tonumber(state.semitones) or 0
    state.paramidx = math.floor(tonumber(state.paramidx) or -1)
    state.fxidx = math.floor(tonumber(state.fxidx) or -1)
    return state
end

function Track.GetHPFilterState(track)
    local state = get_fip_track_state(track, "FIP_GetTrackHPFilterStateStr") or {}
    state.exists = (tonumber(state.exists) or 0) > 0
    state.norm = tonumber(state.norm)
    state.slope24 = (tonumber(state.slope24) or 0) > 0
    state.fxidx = math.floor(tonumber(state.fxidx) or -1)
    return state
end

function Track.GetLPFilterState(track)
    local state = get_fip_track_state(track, "FIP_GetTrackLPFilterStateStr") or {}
    state.exists = (tonumber(state.exists) or 0) > 0
    state.norm = tonumber(state.norm)
    state.slope24 = (tonumber(state.slope24) or 0) > 0
    state.fxidx = math.floor(tonumber(state.fxidx) or -1)
    return state
end

function Track.GetFreezeStats(tracks)
    local total = 0
    local track_count = 0
    local frozen_count = 0
    if tracks then
        for _, tr in ipairs(tracks) do
            local cnt = Track.GetFreezeCountForTrack(tr)
            total = total + cnt
            track_count = track_count + 1
            if cnt > 0 then frozen_count = frozen_count + 1 end
        end
    end
    local has = (frozen_count > 0)
    local all_frozen = (track_count > 0 and frozen_count == track_count)
    local none_frozen = (frozen_count == 0)
    local mixed = (frozen_count > 0 and frozen_count < track_count)
    return {
        total = total,
        has = has,
        track_count = track_count,
        frozen_count = frozen_count,
        all_frozen = all_frozen,
        none_frozen = none_frozen,
        mixed = mixed,
    }
end

function Track.GetTotalFXLatency(track)
    if not track or not r.ValidatePtr(track, 'MediaTrack*') then return nil end
    if r.APIExists and r.APIExists("FIP_GetTrackPDCVal") then
        return r.FIP_GetTrackPDCVal(track, "", 0)
    end
    return nil
end

function Track.GetPerfInfo(track)
    return {
        pdc_spl = Track.GetTotalFXLatency(track)
    }
end

local HP_FX_NAME = "JS: Mr. Frenkie/Low Cut 24 dB/oct"
local LP_FX_NAME = "JS: Mr. Frenkie/High Cut 24 dB/oct"

parse_fip_state_str = function(s)
    local out = {}
    if type(s) ~= "string" or s == "" then return out end
    for entry in s:gmatch("[^\t]+") do
        local key, value = entry:match("^([^=]+)=(.*)$")
        if key then
            local num = tonumber(value)
            out[key] = (num ~= nil) and num or value
        end
    end
    return out
end

get_fip_track_state = function(track, api_name)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    if not (r.APIExists and r.APIExists(api_name)) then return nil end
    return parse_fip_state_str(r[api_name](track, "", 0) or "")
end

local function ensure_mt_front(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    if not (r.APIExists and r.APIExists("FIP_EnsureMidiTransposeFront")) then return nil end
    local idx = r.FIP_EnsureMidiTransposeFront(track, "", 0)
    if idx == nil or idx < 0 then return nil end
    return idx
end

local function find_fx_by_name(track, name)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    local fx_cnt = r.TrackFX_GetCount(track) or 0
    for i = 0, fx_cnt - 1 do
        local ok, fx_name = r.TrackFX_GetFXName(track, i, "")
        if ok and fx_name and fx_name:find(name, 1, true) then
            return i
        end
    end
    return nil
end

-- norm_when_create, slope_when_create: used only when adding NEW FX (no existing). When re-adding we read from existing.
local function ensure_hp_only_at_end(track, norm_when_create, slope_when_create)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    if not (r.APIExists and r.APIExists("FIP_EnsureHPFilterOnly")) then return nil end
    local norm = norm_when_create
    local slope = slope_when_create
    if norm == nil then norm = 0 end
    if slope == nil then slope = 1 end
    slope = slope and 1 or 0
    local idx = r.FIP_EnsureHPFilterOnly(track, norm, slope, 0)
    if idx == nil or idx < 0 then return nil end
    return idx
end

local function ensure_lp_only_at_end(track, norm_when_create, slope_when_create)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    if not (r.APIExists and r.APIExists("FIP_EnsureLPFilterOnly")) then return nil end
    local norm = norm_when_create
    local slope = slope_when_create
    if norm == nil then norm = 1 end
    if slope == nil then slope = 1 end
    slope = slope and 1 or 0
    local idx = r.FIP_EnsureLPFilterOnly(track, norm, slope, 0)
    if idx == nil or idx < 0 then return nil end
    return idx
end

local function ensure_filters_at_end(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    if not (r.APIExists and r.APIExists("FIP_EnsureFiltersAtEnd")) then return end
    r.FIP_EnsureFiltersAtEnd(track, "", 0)
end

local function find_transpose_param(track, fx_idx)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    if fx_idx == nil or fx_idx < 0 then return nil end
    local param_count = r.TrackFX_GetNumParams(track, fx_idx) or 0
    for p = 0, param_count - 1 do
        local ok, name = r.TrackFX_GetParamName(track, fx_idx, p, "")
        if ok and name then
            local n = name:lower()
            if n:find("transpose") or n:find("semitone") or n:find("semitones") or n:find("shift") then
                return p
            end
        end
    end
    if param_count > 0 then return 0 end
    return nil
end

function Track.FindMidiTransposeFX(track)
    local state = Track.GetMidiTransposeState(track)
    return state.exists and state.fxidx >= 0 and state.fxidx or nil
end

function Track.FindHPFilterFX(track)
    local state = Track.GetHPFilterState(track)
    return state.exists and state.fxidx >= 0 and state.fxidx or nil
end

function Track.FindLPFilterFX(track)
    local state = Track.GetLPFilterState(track)
    return state.exists and state.fxidx >= 0 and state.fxidx or nil
end

function Track.EnsureFiltersAtEnd(track)
    ensure_filters_at_end(track)
end

function Track.EnsureHPFilterOnly(track, norm_when_create, slope_when_create)
    return ensure_hp_only_at_end(track, norm_when_create, slope_when_create)
end

function Track.EnsureLPFilterOnly(track, norm_when_create, slope_when_create)
    return ensure_lp_only_at_end(track, norm_when_create, slope_when_create)
end

function Track.RemoveHPFilterFX(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    if r.APIExists and r.APIExists("FIP_RemoveHPFilterFX") then
        r.FIP_RemoveHPFilterFX(track, "", 0)
    end
end

function Track.RemoveLPFilterFX(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    if r.APIExists and r.APIExists("FIP_RemoveLPFilterFX") then
        r.FIP_RemoveLPFilterFX(track, "", 0)
    end
end

-- JSFX slider1: 20..20000 Hz with :log. GetParam returns inf; Normalized API for :log uses 0-1 in LOG space (same as our norm).
local FILTER_HZ_MIN, FILTER_HZ_MAX = 20, 20000
local FILTER_HZ_SPAN = FILTER_HZ_MAX - FILTER_HZ_MIN

function Track.GetFilterFreqNorm(track, fx_idx)
    if not track or fx_idx == nil or fx_idx < 0 then return nil end
    local hp_state = Track.GetHPFilterState(track)
    if hp_state.exists and hp_state.fxidx == fx_idx then
        return hp_state.norm
    end
    local lp_state = Track.GetLPFilterState(track)
    if lp_state.exists and lp_state.fxidx == fx_idx then
        return lp_state.norm
    end
    return nil
end

function Track.SetFilterFreqNorm(track, fx_idx, norm)
    if not track or fx_idx == nil or fx_idx < 0 then return end
    norm = math.max(0, math.min(1, norm))
    r.TrackFX_SetParamNormalized(track, fx_idx, 0, norm)
end

function Track.GetFilterSlope24(track, fx_idx)
    if not track or fx_idx == nil or fx_idx < 0 then return nil end
    local hp_state = Track.GetHPFilterState(track)
    if hp_state.exists and hp_state.fxidx == fx_idx then
        return hp_state.slope24
    end
    local lp_state = Track.GetLPFilterState(track)
    if lp_state.exists and lp_state.fxidx == fx_idx then
        return lp_state.slope24
    end
    return nil
end

function Track.SetFilterSlope24(track, fx_idx, is_24, freq_norm)
    if not track or fx_idx == nil or fx_idx < 0 then return end
    r.TrackFX_SetParam(track, fx_idx, 1, is_24 and 1 or 0)
    if freq_norm ~= nil then
        r.TrackFX_SetParamNormalized(track, fx_idx, 0, math.max(0, math.min(1, freq_norm)))
    end
end

-- Standard DSP log scale: Hz = 20 * 1000^norm (20Hz to 20kHz)
function Track.NormToFreq(norm)
    if norm == nil then return 20 end
    norm = math.max(0, math.min(1, norm))
    return 20 * (1000 ^ norm)
end

function Track.FreqToNorm(freq)
    if freq == nil or freq ~= freq or freq == math.huge or freq == -math.huge then return 0 end -- nil, NaN, inf
    freq = math.max(20, math.min(20000, freq))
    return math.log(freq / 20) / math.log(1000)
end

function Track.GetMidiTransposeValue(track)
    local state = Track.GetMidiTransposeState(track)
    if not state.exists then return nil end
    return state.semitones
end


function Track.TransposeMidiFX(tracks, semitone_delta)
    if not tracks or #tracks == 0 then return end
    Utils.with_undo(semitone_delta > 0 and "Transpose MIDI +1 st" or "Transpose MIDI -1 st", function()
        for _, tr in ipairs(tracks) do
            if tr and r.ValidatePtr(tr, "MediaTrack*") then
                local fx_idx = ensure_mt_front(tr)
                if fx_idx ~= nil then
                    local p_idx = find_transpose_param(tr, fx_idx)
                    if p_idx ~= nil then
                        local val, minv, maxv = r.TrackFX_GetParam(tr, fx_idx, p_idx)
                        if val ~= nil and minv ~= nil and maxv ~= nil then
                            local new_val = val + semitone_delta
                            if new_val < minv then new_val = minv end
                            if new_val > maxv then new_val = maxv end
                            r.TrackFX_SetParam(tr, fx_idx, p_idx, new_val)
                            pcall(r.TrackFX_SetOpen, tr, fx_idx, false)
                        end
                    end
                end
            end
        end
    end)
end

function Track.SetMidiTransposeAbsolute(tracks, target)
    if not tracks or #tracks == 0 then return end
    Utils.with_undo("Set MIDI Transpose", function()
        for _, tr in ipairs(tracks) do
            if tr and r.ValidatePtr(tr, "MediaTrack*") then
                local fx_idx = ensure_mt_front(tr)
                if fx_idx ~= nil then
                    local p_idx = find_transpose_param(tr, fx_idx)
                    if p_idx ~= nil then
                        local _, minv, maxv = r.TrackFX_GetParam(tr, fx_idx, p_idx)
                        local new_val = target
                        if minv ~= nil and maxv ~= nil then
                            if new_val < minv then new_val = minv end
                            if new_val > maxv then new_val = maxv end
                        end
                        r.TrackFX_SetParam(tr, fx_idx, p_idx, new_val)
                        pcall(r.TrackFX_SetOpen, tr, fx_idx, false)
                    end
                end
            end
        end
    end)
end

function Track.UpdateMidiTransposeImmediate(tracks, target)
    if not tracks or #tracks == 0 then return end
    for _, tr in ipairs(tracks) do
        if tr and r.ValidatePtr(tr, "MediaTrack*") then
            local fx_idx = ensure_mt_front(tr)
            if fx_idx ~= nil then
                local p_idx = find_transpose_param(tr, fx_idx)
                if p_idx ~= nil then
                    local _, minv, maxv = r.TrackFX_GetParam(tr, fx_idx, p_idx)
                    local new_val = target
                    if minv ~= nil and maxv ~= nil then
                        if new_val < minv then new_val = minv end
                        if new_val > maxv then new_val = maxv end
                    end
                    r.TrackFX_SetParam(tr, fx_idx, p_idx, new_val)
                    pcall(r.TrackFX_SetOpen, tr, fx_idx, false)
                end
            end
        end
    end
end

function Track.FinalizeMidiTranspose()
    Utils.with_undo("Transpose MIDI", function() end)
end

function Track.ResetMidiTranspose(tracks)
    Track.RemoveMidiTransposeFX(tracks)
end

function Track.RemoveMidiTransposeFX(tracks)
    if not tracks or #tracks == 0 then return end
    Utils.with_undo("Remove MIDI Transpose", function()
        for _, tr in ipairs(tracks) do
            if tr and r.ValidatePtr(tr, "MediaTrack*") then
                if r.APIExists and r.APIExists("FIP_RemoveMidiTransposeFX") then
                    r.FIP_RemoveMidiTransposeFX(tr, "", 0)
                end
            end
        end
    end)
end

-- Phase-based API wrappers (undo managed in C++)
-- phase: 0=begin, 1=tick, 2=end, 3=click (atomic)

function Track.FilterEdit(track, type, norm, slope, phase)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return -1 end
    if not (r.APIExists and r.APIExists("FIP_FilterEdit")) then return -1 end
    return r.FIP_FilterEdit(track, type, norm, slope and 1.0 or 0.0, phase)
end

function Track.FilterRemove(track, type, phase)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return 0 end
    if not (r.APIExists and r.APIExists("FIP_FilterRemove")) then return 0 end
    return r.FIP_FilterRemove(track, type, phase)
end

function Track.MidiTransposeEdit(track, semitones, phase)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return -1 end
    if not (r.APIExists and r.APIExists("FIP_MidiTransposeEdit")) then return -1 end
    return r.FIP_MidiTransposeEdit(track, semitones, phase)
end

function Track.MidiTransposeRemove(track, phase)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return 0 end
    if not (r.APIExists and r.APIExists("FIP_MidiTransposeRemove")) then return 0 end
    return r.FIP_MidiTransposeRemove(track, phase)
end

return Track
