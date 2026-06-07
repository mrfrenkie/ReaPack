-- @noindex

---@diagnostic disable: undefined-global, undefined-field
local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Utils = require("Utils")

local original_props = {}
local base_values = {}
local current_selection = {}
local accumulated_pitch = 0

local last_mouse_state = false
local cached_items = {}
local cached_props = nil
local cached_tracks = {}
local _freeze_sel_key = nil
local _freeze_proj_cc = 0
local freeze_stats = nil
local _items_proj_cc = 0
local cache_time = 0
local cache_duration = 0.2
local last_update_time = 0
local update_interval = 1/30
local last_gc_time = 0
local gc_interval = 10
local prefer_track_context = false
local force_track_context = false
local hovered_track = nil
local last_mouse_button = 0
local manual_context_override = false   -- true = user switched context via right-click in widget
local manual_context_prefer_track = false -- when override: true = Track, false = Item

local ItemPropsCore = {}


function ItemPropsCore.CheckExtensions()
    if not r.ImGui_CreateContext then
        r.ShowMessageBox("ReaImGui extension is required for this script.", "Missing Extension", 0)
        return false
    end
    local required_api = {
        "FIP_GetMouseButtonsStateVal",
        "FIP_GetMouseCursorContextWindowStr",
        "FIP_GetMouseCursorContextItem",
        "FIP_GetMouseCursorContextTrack",
    }
    for _, api_name in ipairs(required_api) do
        if not (r.APIExists and r.APIExists(api_name)) then
            r.ShowMessageBox("Frenkie core extension with mouse context APIs is required for this script.", "Missing Extension", 0)
            return false
        end
    end
    return true
end

function ItemPropsCore.GetSelectedItems()
    local items = {}
    local count = r.CountSelectedMediaItems(0)
    for i = 0, count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        if item and r.ValidatePtr(item, "MediaItem*") then
            items[#items + 1] = item
        end
    end
    return items
end

function ItemPropsCore.GetTake(item)
    if not item then return nil end
    return r.GetActiveTake(item)
end

function ItemPropsCore.GetTakeType(take)
    if not take then return "Empty" end
    local source = r.GetMediaItemTake_Source(take)
    if not source then return "Empty" end
    local source_type = r.GetMediaSourceType(source, "")
    return source_type == "MIDI" and "MIDI" or "Audio"
end

function ItemPropsCore.GetTakeSourceReverse(take)
    if not take then return false end
    local src = r.GetMediaItemTake_Source(take)
    if not src then return false end
    local ok, offs, len, rev = r.PCM_Source_GetSectionInfo(src)
    if ok then return rev == true end
    return false
end

function ItemPropsCore.IsItemReversed(item)
    if not item or not r.ValidatePtr(item, "MediaItem*") then return false end
    local take = ItemPropsCore.GetTake(item)
    if not take then return false end
    if r.GetMediaItemTakeInfo_Value(take, "B_REVERSE") == 1 then return true end
    if ItemPropsCore.GetTakeSourceReverse(take) then return true end
    return false
end

function ItemPropsCore.ItemHasFX(item)
    if not item then return false end
    local take = ItemPropsCore.GetTake(item)
    if not take then return false end
    return r.TakeFX_GetCount(take) > 0
end

function ItemPropsCore.GetMIDIVelocityScale(take)
    if not take then return 1.0 end
    return r.GetMediaItemTakeInfo_Value(take, "D_VOL")
end

function ItemPropsCore.FormatRateValue(rate)
    if not rate then return "1.000" end
    return string.format("%.3f", rate)
end

function ItemPropsCore.GetItemProps(item)
    if not item then return nil end
    local take = ItemPropsCore.GetTake(item)
    local take_type = ItemPropsCore.GetTakeType(take)
    if not take_type then return nil end
    if take_type == "Empty" then
        return {
            take_type = "Empty",
            mute = r.GetMediaItemInfo_Value(item, "B_MUTE") == 1,
            loop = r.GetMediaItemInfo_Value(item, "B_LOOPSRC") == 1,
            lock = r.GetMediaItemInfo_Value(item, "C_LOCK") == 1
        }
    end
    local props = {
        take_type = take_type,
        mute = r.GetMediaItemInfo_Value(item, "B_MUTE") == 1,
        loop = r.GetMediaItemInfo_Value(item, "B_LOOPSRC") == 1,
        lock = r.GetMediaItemInfo_Value(item, "C_LOCK") == 1,
        pitch = r.GetMediaItemTakeInfo_Value(take, "D_PITCH"),
        playback_rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"),
        preserve_pitch = r.GetMediaItemTakeInfo_Value(take, "B_PPITCH") == 1,
        reverse = ItemPropsCore.IsItemReversed(item),
        mode = r.GetMediaItemTakeInfo_Value(take, "I_PITCHMODE"),
        name = r.GetTakeName(take)
    }
    local pitchmode_value = r.GetMediaItemTakeInfo_Value(take, "I_PITCHMODE")
    if pitchmode_value == -1 then
        props.mode = -1
    else
        props.mode = math.floor(pitchmode_value / 65536)
    end
    if take_type == "MIDI" then
        props.velocity_scale = ItemPropsCore.GetMIDIVelocityScale(take)
    else
        props.volume = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
    end
    props.bpm = r.Master_GetTempo() / props.playback_rate
    return props
end

function ItemPropsCore.GetAggregatedProps(items)
    if not (r.APIExists and r.APIExists("FIP_GetAggregatedPropsStateStr")) then
        accumulated_pitch = 0
        current_selection = {}
        return nil
    end
    local raw_state = r.FIP_GetAggregatedPropsStateStr("", 0)
    if type(raw_state) ~= "string" or raw_state == "" then
        accumulated_pitch = 0
        current_selection = {}
        return nil
    end
    local raw = {}
    for pair in raw_state:gmatch("[^\t]+") do
        local k, v = pair:match("^(.-)=(.*)$")
        if k and v then raw[k] = v end
    end
    local sel_count = tonumber(raw.count) or 0
    if sel_count <= 0 then
        accumulated_pitch = 0
        current_selection = {}
        return nil
    end
    local function parse_num(v)
        if v == nil or v == "" or v == "nil" then return nil end
        return tonumber(v)
    end
    local function parse_bool(v)
        if v == nil or v == "" or v == "nil" then return nil end
        return tonumber(v) == 1
    end
    local aggregated = {}
    aggregated.sel_item_count = sel_count
    aggregated.take_type = raw.take_type or "Audio"
    aggregated.name = (raw.name and raw.name ~= "") and raw.name or nil
    aggregated.mode = parse_num(raw.mode)
    aggregated.mode_bits = tonumber(raw.mode_bits) or 0
    aggregated.playback_rate = parse_num(raw.rate)
    aggregated.preserve_pitch = parse_bool(raw.pp)
    aggregated.loop = parse_bool(raw.loop)
    aggregated.mute = parse_bool(raw.mute)
    aggregated.lock = parse_bool(raw.lock)
    aggregated.reverse = parse_bool(raw.reverse)
    aggregated.volume = parse_num(raw.vol)
    aggregated.velocity_scale = parse_num(raw.vel)
    aggregated.pitch = parse_num(raw.pitch)
    aggregated.bpm = parse_num(raw.bpm)
    if aggregated.take_type == "Mult" then
        aggregated.volume = aggregated.volume or 1.0
        aggregated.velocity_scale = aggregated.velocity_scale or 1.0
    end
    return aggregated
end

function ItemPropsCore.OpenItemFXChain(item)
    if not item then return end
    r.SetMediaItemSelected(item, true)
    r.Main_OnCommand(40638, 0)
end

function ItemPropsCore.ClearOriginalPropsForSelection()
    local items = ItemPropsCore.GetSelectedItems()
    for _, item in ipairs(items) do
        local item_ptr = r.GetMediaItemGUID(item)
        if original_props[item_ptr] then
            original_props[item_ptr] = nil
        end
    end
end

function ItemPropsCore.CleanupOriginalProps()
    if not original_props then return end
    if not (r.APIExists and r.APIExists("FIP_GetSelectedItemsSignatureAndGUIDsStr")) then return end
    local raw = r.FIP_GetSelectedItemsSignatureAndGUIDsStr("\n", 0) or ""
    if raw == "" then return end
    local sel_sig, list = raw:match("^(.-)\n(.*)$")
    if not sel_sig then
        sel_sig = raw
        list = ""
    end
    if sel_sig == "" then return end
    if ItemPropsCore._last_cleanup_sig == sel_sig then
        return
    end
    ItemPropsCore._last_cleanup_sig = sel_sig
    local cnt = tonumber(sel_sig:match("^(%d+):")) or 0
    if cnt <= 0 then
        original_props = {}
        base_values = {}
        cached_items = {}
        cached_props = nil
        collectgarbage("collect")
        return
    end
    if list == "" then
        original_props = {}
        base_values = {}
        cached_items = {}
        cached_props = nil
        collectgarbage("collect")
        return
    end
    local selected = {}
    for guid in list:gmatch("[^\n]+") do
        selected[guid] = true
    end
    local valid_props = {}
    for item_ptr, props in pairs(original_props) do
        if selected[item_ptr] then
            valid_props[item_ptr] = props
        end
    end
    original_props = valid_props
    if #base_values > 50 then
        local new_base_values = {}
        local start_idx = #base_values - 25 + 1
        for i = start_idx, #base_values do
            new_base_values[#new_base_values + 1] = base_values[i]
        end
        base_values = new_base_values
    end
end


function ItemPropsCore.GetState()
    return {
        original_props = original_props,
        base_values = base_values,
        current_selection = current_selection,
        last_mouse_state = last_mouse_state,
        last_mouse_button = last_mouse_button,
        prefer_track_context = prefer_track_context,
        force_track_context = force_track_context,
        hovered_track = hovered_track,
        manual_context_override = manual_context_override,
        manual_context_prefer_track = manual_context_prefer_track,
        cached_items = cached_items,
        cached_tracks = cached_tracks,
        cached_props = cached_props,
        cache_time = cache_time,
        cache_duration = cache_duration,
        last_update_time = last_update_time,
        update_interval = update_interval,
        last_gc_time = last_gc_time,
        gc_interval = gc_interval,
        _freeze_sel_key = _freeze_sel_key,
        _freeze_proj_cc = _freeze_proj_cc,
        freeze_stats = freeze_stats,
        _items_proj_cc = _items_proj_cc
    }
end

function ItemPropsCore.SetState(state)
    original_props = state.original_props or {}
    base_values = state.base_values or {}
    current_selection = state.current_selection or {}
    last_mouse_state = state.last_mouse_state or false
    last_mouse_button = state.last_mouse_button or 0
    prefer_track_context = state.prefer_track_context or false
    force_track_context = state.force_track_context or false
    hovered_track = state.hovered_track
    manual_context_override = state.manual_context_override or false
    manual_context_prefer_track = state.manual_context_prefer_track or false
    cached_items = state.cached_items or {}
    cached_tracks = state.cached_tracks or {}
    cached_props = state.cached_props
    cache_time = state.cache_time or 0
    cache_duration = state.cache_duration or 0.2
    last_update_time = state.last_update_time or 0
    update_interval = state.update_interval or (1/30)
    last_gc_time = state.last_gc_time or 0
    gc_interval = state.gc_interval or 10
    _freeze_sel_key = state._freeze_sel_key
    _freeze_proj_cc = state._freeze_proj_cc
    freeze_stats = state.freeze_stats
    _items_proj_cc = state._items_proj_cc
end

function ItemPropsCore.UpdatePreservePitch(items, preserve)
    Utils.with_undo("Toggle Preserve Pitch", function()
        if r.APIExists and r.APIExists("FIP_SetSelectedItemsPreservePitch") then
            r.FIP_SetSelectedItemsPreservePitch(preserve and "1" or "0", 0)
        else
            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPreservePitch not available\n")
        end
    end)
end

function ItemPropsCore.UpdateLoop(items, loop)
    Utils.with_undo("Toggle Loop", function()
        if r.APIExists and r.APIExists("FIP_SetSelectedItemsLoop") then
            r.FIP_SetSelectedItemsLoop(loop and "1" or "0", 0)
        else
            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsLoop not available\n")
        end
        local aggregated = ItemPropsCore.GetAggregatedProps(items)
        ItemPropsCore.DebugAggregated(items, aggregated)
    end)
end

function ItemPropsCore.UpdateMute(items, mute)
    Utils.with_undo("Toggle Mute", function()
        if r.APIExists and r.APIExists("FIP_SetSelectedItemsMute") then
            r.FIP_SetSelectedItemsMute(mute and "1" or "0", 0)
        else
            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsMute not available\n")
        end
        local aggregated = ItemPropsCore.GetAggregatedProps(items)
        ItemPropsCore.DebugAggregated(items, aggregated)
    end)
end

function ItemPropsCore.UpdateLock(items, lock)
    Utils.with_undo("Toggle Lock", function()
        if r.APIExists and r.APIExists("FIP_SetSelectedItemsLock") then
            r.FIP_SetSelectedItemsLock(lock and "1" or "0", 0)
        else
            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsLock not available\n")
        end
        local aggregated = ItemPropsCore.GetAggregatedProps(items)
        ItemPropsCore.DebugAggregated(items, aggregated)
    end)
end

function ItemPropsCore.UpdateReverse(items, reverse)
    Utils.with_undo("Toggle Reverse", function()
        if r.APIExists and r.APIExists("FIP_SetSelectedItemsReverse") then
            r.FIP_SetSelectedItemsReverse(reverse and "1" or "0", 0)
        else
            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsReverse not available\n")
        end
        local aggregated = ItemPropsCore.GetAggregatedProps(items)
        ItemPropsCore.DebugAggregated(items, aggregated)
    end)
end

function ItemPropsCore.RemoveAllFX(items)
    Utils.with_undo('Remove all item FX', function()
        for _, item in ipairs(items) do
            local take = ItemPropsCore.GetTake(item)
            if take then
                local fx_count = r.TakeFX_GetCount(take)
                for fx_idx = fx_count - 1, 0, -1 do
                    r.TakeFX_Delete(take, fx_idx)
                end
            end
        end
    end)
end

function ItemPropsCore.OpenFXChain(items)
    r.Main_OnCommand(40638, 0)
end

return ItemPropsCore
