-- @noindex

---@diagnostic disable: undefined-global, undefined-field
local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Utils = require("Utils")

local transpose_drag_active = false
local transpose_drag_start = 0
local transpose_drag_last = 0

local ItemPropsPitch = {}
ItemPropsPitch._sel_tracks_pitch_cache = ItemPropsPitch._sel_tracks_pitch_cache or { sig = "", proj_cc = -1, stats = nil }

local function parse_pitch_stats(s)
    if type(s) ~= "string" or s == "" then
        return { count = 0, sum = 0, first = 0, all_equal = true, all_zero = true, max_up = 0, max_down = 0 }
    end
    local parts = {}
    for part in s:gmatch("[^\t]+") do
        parts[#parts + 1] = part
    end
    local cnt = tonumber(parts[1]) or 0
    return {
        count = cnt,
        sum = tonumber(parts[2]) or 0,
        first = tonumber(parts[3]) or 0,
        all_equal = (tonumber(parts[4]) or 0) ~= 0,
        all_zero = (tonumber(parts[5]) or 0) ~= 0,
        max_up = tonumber(parts[6]) or 0,
        max_down = tonumber(parts[7]) or 0
    }
end

local function get_selected_tracks_pitch_stats()
    local has_sig_api = r.APIExists and r.APIExists("FIP_GetSelectedTracksSignatureStr")
    local has_stats_api = r.APIExists and r.APIExists("FIP_GetSelectedTracksItemsPitchStatsStr")
    if not (has_sig_api and has_stats_api) then
        return { count = 0, sum = 0, first = 0, all_equal = true, all_zero = true, max_up = 0, max_down = 0 }
    end
    local sig = r.FIP_GetSelectedTracksSignatureStr("", 0) or ""
    local proj_cc = r.GetProjectStateChangeCount(0) or 0
    local cache = ItemPropsPitch._sel_tracks_pitch_cache
    if cache.sig == sig and cache.proj_cc == proj_cc and cache.stats then
        return cache.stats
    end
    local _, raw = r.FIP_GetSelectedTracksItemsPitchStatsStr("", 512)
    local stats = parse_pitch_stats(raw)
    cache.sig = sig
    cache.proj_cc = proj_cc
    cache.stats = stats
    return stats
end

function ItemPropsPitch.GetSelectedTracksItemsPitchInfo()
    local stats = get_selected_tracks_pitch_stats()
    local count = stats.count or 0
    local display = 0
    if count > 0 and (r.APIExists and r.APIExists("FIP_GetSelectedTracksItemsPitchDeltaVal")) then
        display = r.FIP_GetSelectedTracksItemsPitchDeltaVal("", 0) or 0
    end
    local modified, mixed = false, false
    if count > 0 and not stats.all_zero then
        if stats.all_equal then
            modified, mixed = true, false
        else
            modified, mixed = false, true
        end
    end
    return count, display, modified, mixed, stats
end

function ItemPropsPitch.ResetSelectedTracksItemsPitchDelta()
    if r.APIExists and r.APIExists("FIP_ResetSelectedTracksItemsPitchDeltaVal") then
        r.FIP_ResetSelectedTracksItemsPitchDeltaVal("", 0)
    end
end

function ItemPropsPitch.HandleSelectedTracksItemsPitchReset()
    if not (r.APIExists and r.APIExists("FIP_ResetSelectedTracksItemsPitchVal")) then
        r.ShowConsoleMsg("ERROR: FIP_ResetSelectedTracksItemsPitchVal not available\n")
        return
    end
    Utils.with_undo("Reset Track Items Pitch", function()
        r.FIP_ResetSelectedTracksItemsPitchVal("", 0)
    end)
    ItemPropsPitch._sel_tracks_pitch_cache.proj_cc = -1
    if r.APIExists and r.APIExists("FIP_ResetSelectedTracksItemsPitchDeltaVal") then
        r.FIP_ResetSelectedTracksItemsPitchDeltaVal("", 0)
    end
end

function ItemPropsPitch.HandleSelectedTracksItemsPitchChange(new_pitch, current_pitch)
    if not (r.APIExists and r.APIExists("FIP_ApplyAddSelectedTracksItemsPitchDeltaVal")) then
        r.ShowConsoleMsg("ERROR: FIP_ApplyAddSelectedTracksItemsPitchDeltaVal not available\n")
        return current_pitch or 0
    end
    local stats = get_selected_tracks_pitch_stats()
    new_pitch = math.floor((new_pitch or 0) + 0.5)
    new_pitch = math.max(-96, math.min(96, new_pitch))
    local desired_delta = new_pitch - (current_pitch or 0)
    if math.abs(desired_delta) < 0.0001 then
        return current_pitch or 0
    end
    local delta = desired_delta
    if delta > 0 and stats.max_up ~= nil and delta > stats.max_up then
        delta = stats.max_up
    elseif delta < 0 and stats.max_down ~= nil and delta < stats.max_down then
        delta = stats.max_down
    end
    if math.abs(delta) < 0.0001 then
        return current_pitch or 0
    end
    local updated = r.FIP_ApplyAddSelectedTracksItemsPitchDeltaVal(tostring(delta), 0)
    ItemPropsPitch._sel_tracks_pitch_cache.proj_cc = -1
    return (type(updated) == "number") and updated or ((current_pitch or 0) + delta)
end

function ItemPropsPitch.GetPitch(take)
    if not take then return 0 end
    return r.GetMediaItemTakeInfo_Value(take, "D_PITCH")
end

function ItemPropsPitch.SetPitch(take, pitch)
    if not take or pitch == nil then return end
    r.SetMediaItemTakeInfo_Value(take, "D_PITCH", pitch)
end

function ItemPropsPitch.UpdateAccumulatedPitch(pitch_delta)
    if not (r.APIExists and r.APIExists("FIP_ApplyAddSelectedItemsPitchDeltaVal")) then
        r.ShowConsoleMsg("ERROR: FIP_ApplyAddSelectedItemsPitchDeltaVal not available\n")
        return 0
    end
    return r.FIP_ApplyAddSelectedItemsPitchDeltaVal(tostring(pitch_delta or 0), 0) or 0
end

function ItemPropsPitch.ResetAccumulatedPitch()
    if r.APIExists and r.APIExists("FIP_ResetSelectedItemsPitchDeltaVal") then
        r.FIP_ResetSelectedItemsPitchDeltaVal("", 0)
    end
end

function ItemPropsPitch.GetAccumulatedPitch()
    if r.APIExists and r.APIExists("FIP_GetSelectedItemsPitchDeltaVal") then
        return r.FIP_GetSelectedItemsPitchDeltaVal("", 0) or 0
    end
    return 0
end

function ItemPropsPitch.CheckSelectionChange(items)
    if r.APIExists and r.APIExists("FIP_GetSelectedItemsSignatureStr") then
        local sig = r.FIP_GetSelectedItemsSignatureStr("", 0) or ""
        if ItemPropsPitch._last_items_sig ~= sig then
            ItemPropsPitch._last_items_sig = sig
            return true
        end
    end
    return false
end

function ItemPropsPitch.ResetPitch(items)
    Utils.with_undo("Reset Pitch", function()
        if r.APIExists and r.APIExists("FIP_SetSelectedItemsPitch") then
            r.FIP_SetSelectedItemsPitch("0", 0)
        else
            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPitch not available\n")
        end
    end)
    r.UpdateArrange()
end

function ItemPropsPitch.UpdatePitch(items, pitch_delta, base_values)
    if not items or #items == 0 then return end
    if r.APIExists and r.APIExists("FIP_AddSelectedItemsPitch") then
        r.FIP_AddSelectedItemsPitch(tostring(pitch_delta or 0), 0)
    else
        r.ShowConsoleMsg("ERROR: FIP_AddSelectedItemsPitch not available\n")
    end
    r.UpdateArrange()
end

function ItemPropsPitch.SetAbsolutePitch(items, pitch)
    if not items or #items == 0 then return end
    local clamped_pitch = math.max(-96, math.min(96, pitch or 0))
    if r.APIExists and r.APIExists("FIP_SetSelectedItemsPitch") then
        r.FIP_SetSelectedItemsPitch(tostring(clamped_pitch), 0)
    else
        r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPitch not available\n")
    end
    r.UpdateArrange()
end

function ItemPropsPitch.HandlePitchChange(items, new_pitch, current_pitch, base_values)
    if not items or #items == 0 then return current_pitch or 0 end
    new_pitch = math.floor(new_pitch + 0.5)
    new_pitch = math.max(-96, math.min(96, new_pitch))
    local desired_delta = new_pitch - (current_pitch or 0)
    if desired_delta == 0 then return current_pitch or 0 end
    if #items > 1 then
        local updated = ItemPropsPitch.UpdateAccumulatedPitch(desired_delta)
        return (type(updated) == "number") and updated or ((current_pitch or 0) + desired_delta)
    end
    if r.APIExists and r.APIExists("FIP_SetSelectedItemsPitch") then
        r.FIP_SetSelectedItemsPitch(tostring(new_pitch), 0)
    else
        r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPitch not available\n")
    end
    return new_pitch
end

function ItemPropsPitch.FinalizePitchChange()
    Utils.with_undo("Change Pitch", function() end)
end

local function TransposeMIDIItems(items, interval)
    if not items or #items == 0 or interval == 0 then return end
    if r.APIExists("FIP_TransposeSelectedItemsMIDI") then
        r.FIP_TransposeSelectedItemsMIDI(interval, 0)
    else
        r.ShowConsoleMsg("ERROR: FIP_TransposeSelectedItemsMIDI not available\n")
    end
    r.UpdateArrange()
end

function ItemPropsPitch.MIDITransposeDragUpdate(items, new_pitch, current_pitch)
    new_pitch = math.floor(new_pitch + 0.5)
    current_pitch = math.floor((current_pitch or 0) + 0.5)
    
    if not transpose_drag_active then
        transpose_drag_active = true
        transpose_drag_start = current_pitch
        transpose_drag_last = current_pitch
    end
    
    local delta = new_pitch - transpose_drag_last
    if delta ~= 0 then
        TransposeMIDIItems(items, delta)
        transpose_drag_last = new_pitch
    end
end

function ItemPropsPitch.FinalizeMIDITranspose(items)
    if not transpose_drag_active then return end
    
    -- Delta has been applied incrementally.
    -- We just clean up and register Undo.
    
    transpose_drag_active = false
    transpose_drag_start = 0
    transpose_drag_last = 0
    
    Utils.with_undo("Transpose MIDI", function()
        -- Just to register state change
        if r.APIExists("FIP_ResetSelectedItemsPitchDeltaVal") then
            r.FIP_ResetSelectedItemsPitchDeltaVal("", 0)
        end
        r.UpdateArrange()
    end)
end

function ItemPropsPitch.HandlePitchReset(items, base_values)
    Utils.with_undo("Reset Pitch", function()
        if r.APIExists and r.APIExists("FIP_SetSelectedItemsPitch") then
            r.FIP_SetSelectedItemsPitch("0", 0)
        else
            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPitch not available\n")
        end
    end)
    ItemPropsPitch.ResetAccumulatedPitch()
    if base_values then
        for i, item in ipairs(items) do
            local take = r.GetActiveTake(item)
            if take and base_values[i] then
                base_values[i].pitch = ItemPropsPitch.GetPitch(take)
            end
        end
    end
end

function ItemPropsPitch.RevertAggregatedPitchChanges(items, base_values)
    local delta = -ItemPropsPitch.GetAccumulatedPitch()
    if math.abs(delta) < 0.001 then
        ItemPropsPitch.ResetAccumulatedPitch()
        return
    end
    Utils.with_undo("Reset Pitch", function()
        ItemPropsPitch.UpdateAccumulatedPitch(delta)
    end)
    ItemPropsPitch.ResetAccumulatedPitch()
    if base_values then
        for i, item in ipairs(items) do
            local take = r.GetActiveTake(item)
            if take and base_values[i] then
                base_values[i].pitch = ItemPropsPitch.GetPitch(take)
            end
        end
    end
end

function ItemPropsPitch.GetAggregatedPitch(items)
    if r.APIExists and r.APIExists("FIP_GetAggregatedPitch") then
        local s = r.FIP_GetAggregatedPitch("", 0) or ""
        if s == "" or s == "MIXED" then return 0 end
        return tonumber(s) or 0
    end
    return 0
end

return ItemPropsPitch
