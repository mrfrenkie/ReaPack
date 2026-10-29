-- @noindex
---@diagnostic disable: undefined-global, undefined-field
local r = reaper
local Utils = require("Utils")

local Track = {}
local parse_fip_state_str
local get_fip_track_state

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

function Track.FindMidiTransposeFX(track)
    local state = Track.GetMidiTransposeState(track)
    return state.exists and state.fxidx >= 0 and state.fxidx or nil
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

---------------------------------------------------------------------------
-- Last Touched Parameter (per-track memory for Track inspector)
---------------------------------------------------------------------------

local LTP_EXT_KEY = "P_EXT:FIP_LTP"
local _ltp_by_track = {} -- [track_guid] = { fxguid=, parm=, fxidx= }

local function ltp_fx_guid_string(track, fxidx)
    if not track or fxidx == nil then return nil end
    local guid = r.TrackFX_GetFXGUID(track, fxidx)
    if type(guid) == "string" and guid ~= "" then return guid end
    if guid and r.guidToString then
        local s = r.guidToString(guid, "")
        if s and s ~= "" then return s end
    end
    return nil
end

local function ltp_find_fx_by_guid(track, fxguid)
    if not track or not fxguid or fxguid == "" then return nil end
    local function scan(base, count)
        for i = 0, count - 1 do
            local fx = base + i
            if ltp_fx_guid_string(track, fx) == fxguid then
                return fx
            end
        end
        return nil
    end
    local found = scan(0, r.TrackFX_GetCount(track) or 0)
    if found ~= nil then return found end
    local rec = r.TrackFX_GetRecCount and (r.TrackFX_GetRecCount(track) or 0) or 0
    if rec > 0 then
        found = scan(0x1000000, rec)
        if found ~= nil then return found end
    end
    return nil
end

local function ltp_track_guid(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    return r.GetTrackGUID(track)
end

local function ltp_read_ext(track)
    if not track then return nil end
    local ok, val = r.GetSetMediaTrackInfo_String(track, LTP_EXT_KEY, "", false)
    if not ok or not val or val == "" then return nil end
    local fxguid, parm_s, fxidx_s = val:match("^([^|]+)|(%-?%d+)|(%-?%d+)$")
    if not fxguid then
        fxguid, parm_s = val:match("^([^|]+)|(%-?%d+)$")
    end
    if not fxguid or not parm_s then return nil end
    return {
        fxguid = fxguid,
        parm = tonumber(parm_s),
        fxidx = fxidx_s and tonumber(fxidx_s) or nil,
    }
end

local function ltp_write_ext(track, fxguid, parm, fxidx)
    if not track then return end
    local payload = ""
    if fxguid and parm ~= nil and fxidx ~= nil then
        payload = string.format("%s|%d|%d", fxguid, math.floor(parm), math.floor(fxidx))
    end
    r.GetSetMediaTrackInfo_String(track, LTP_EXT_KEY, payload, true)
end

local function ltp_resolve_entry(track, entry)
    if not track or not entry or not entry.fxguid or entry.parm == nil then return nil end
    local fxidx = ltp_find_fx_by_guid(track, entry.fxguid)
    if fxidx == nil and entry.fxidx ~= nil then
        if ltp_fx_guid_string(track, entry.fxidx) == entry.fxguid then
            fxidx = entry.fxidx
        end
    end
    if fxidx == nil then return nil end
    local nparams = r.TrackFX_GetNumParams(track, fxidx) or 0
    local parm = math.floor(entry.parm)
    if parm < 0 or parm >= nparams then return nil end
    entry.fxidx = fxidx
    entry.parm = parm
    return entry
end

local function ltp_store(track, fxidx, parm)
    local tguid = ltp_track_guid(track)
    if not tguid then return end
    local fxguid = ltp_fx_guid_string(track, fxidx)
    if not fxguid then return end
    parm = math.floor(parm)
    fxidx = math.floor(fxidx)
    local prev = _ltp_by_track[tguid]
    if prev and prev.fxguid == fxguid and prev.parm == parm and prev.fxidx == fxidx then
        return
    end
    local entry = { fxguid = fxguid, parm = parm, fxidx = fxidx }
    _ltp_by_track[tguid] = entry
    ltp_write_ext(track, fxguid, parm, fxidx)
end

local function ltp_touched_track_ptr(trackidx)
    if trackidx == nil then return nil end
    if trackidx < 0 then
        return r.GetMasterTrack(0)
    end
    return r.GetTrack(0, trackidx)
end

local function ltp_clean_fx_name(name)
    if not name or name == "" then return "" end
    return (name:gsub("^[^:]+:%s*", ""))
end

--- Poll project last-touched FX param; remember it on the owning track.
function Track.PollLastTouchedParam()
    if not (r.APIExists and r.APIExists("GetTouchedOrFocusedFX")) then return end
    local ok, trackidx, itemidx, _takeidx, fxidx, parm = r.GetTouchedOrFocusedFX(0)
    if not ok then return end
    if itemidx ~= nil and itemidx >= 0 then return end -- take/item FX — ignore
    if fxidx == nil or parm == nil or parm < 0 then return end
    local tr = ltp_touched_track_ptr(trackidx)
    if not tr or not r.ValidatePtr(tr, "MediaTrack*") then return end
    local nparams = r.TrackFX_GetNumParams(tr, fxidx) or 0
    if parm >= nparams then return end
    ltp_store(tr, fxidx, parm)
end

--- Returns display/edit info for this track's remembered last touched param, or nil.
function Track.GetLastTouchedParamInfo(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end

    local tguid = ltp_track_guid(track)
    if not tguid then return nil end

    local entry = _ltp_by_track[tguid]
    if not entry then
        entry = ltp_read_ext(track)
        if entry then
            _ltp_by_track[tguid] = entry
        end
    end
    if not entry then return nil end

    entry = ltp_resolve_entry(track, entry)
    if not entry then
        _ltp_by_track[tguid] = nil
        ltp_write_ext(track, nil, nil, nil)
        return nil
    end
    _ltp_by_track[tguid] = entry

    local fxidx, parm = entry.fxidx, entry.parm
    local ok_pn, param_name = r.TrackFX_GetParamName(track, fxidx, parm, "")
    if not ok_pn then param_name = "" end
    local ok_fx, fx_name = r.TrackFX_GetFXName(track, fxidx, "")
    if not ok_fx then fx_name = "" end

    local val, minv, maxv = r.TrackFX_GetParam(track, fxidx, parm)
    if val == nil then return nil end
    minv = minv or 0
    maxv = maxv or 1

    local formatted = ""
    local ok_fmt, fmt = r.TrackFX_GetFormattedParamValue(track, fxidx, parm, "")
    if ok_fmt and fmt then formatted = fmt end

    return {
        fxidx = fxidx,
        parm = parm,
        fxguid = entry.fxguid,
        param_name = param_name or "",
        fx_name = ltp_clean_fx_name(fx_name),
        value = val,
        min_val = minv,
        max_val = maxv,
        default_value = (minv + maxv) * 0.5,
        formatted = formatted,
    }
end

function Track.SetLastTouchedParamValue(track, fxidx, parm, value)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    if fxidx == nil or parm == nil or value == nil then return end
    r.TrackFX_SetParam(track, fxidx, parm, value)
    ltp_store(track, fxidx, parm)
end

-- A drag spans many defer calls: the ticks change the parameter without undo and the end commits one named undo
-- point. An undo block left open across defer calls would be closed by REAPER as "ReaScript: Run".
local _ltp_param_edit_active = false

function Track.BeginLastTouchedParamEdit()
    _ltp_param_edit_active = true
end

function Track.EndLastTouchedParamEdit()
    if not _ltp_param_edit_active then return end
    r.Undo_OnStateChangeEx2(0, "Adjust FX parameter", 2, -1) -- 2 = UNDO_STATE_FX
    _ltp_param_edit_active = false
end

--- Create (if needed) and show the automation envelope lane for this FX parameter.
function Track.ShowLastTouchedParamEnvelope(track, fxidx, parm)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if fxidx == nil or parm == nil then return false end
    if not (r.APIExists and r.APIExists("GetFXEnvelope")) then return false end

    local created = false
    Utils.with_undo("FX parameter envelope", function()
        local env = r.GetFXEnvelope(track, fxidx, parm, true)
        if not env then return end
        created = true
        local ok_chunk, chunk = r.GetEnvelopeStateChunk(env, "", false)
        if ok_chunk and chunk and chunk ~= "" then
            local new_chunk = chunk
            if new_chunk:find("VIS%s+0") then
                new_chunk = new_chunk:gsub("VIS%s+%d+", "VIS 1 1 1", 1)
            elseif not new_chunk:find("VIS%s+") then
                new_chunk = new_chunk:gsub("\n", "\nVIS 1 1 1\n", 1)
            end
            if new_chunk ~= chunk then
                r.SetEnvelopeStateChunk(env, new_chunk, false)
            end
        end
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
    end)
    return created
end

return Track
