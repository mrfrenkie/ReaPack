-- @noindex
---@diagnostic disable: undefined-global, undefined-field
-- Item panel bridge: the extension computes and edits everything (reaper_my_extension.cpp); this module turns
-- its state string into the props table the layout reads and forwards the toggles (each makes its own undo point).
local r = reaper

local Item = {}

local function api(name)
    return r.APIExists and r.APIExists(name)
end

local function parse_num(v)
    if v == nil or v == "" or v == "nil" then return nil end
    return tonumber(v)
end

local function parse_bool(v)
    if v == nil or v == "" or v == "nil" then return nil end
    return tonumber(v) == 1
end

-- Aggregated props of the selected items (FIP_GetAggregatedPropsStateStr); nil when nothing is selected.
-- A field is nil when the items differ.
function Item.GetAggregatedProps()
    if not api("FIP_GetAggregatedPropsStateStr") then return nil end
    local raw = {}
    for pair in (r.FIP_GetAggregatedPropsStateStr("", 0) or ""):gmatch("[^\t]+") do
        local k, v = pair:match("^(.-)=(.*)$")
        if k then raw[k] = v end
    end
    local count = tonumber(raw.count) or 0
    if count <= 0 then return nil end
    return {
        sel_item_count = count,
        take_type = raw.take_type or "Audio",
        name = (raw.name and raw.name ~= "") and raw.name or nil,
        mode = parse_num(raw.mode),
        mode_bits = tonumber(raw.mode_bits) or 0,
        playback_rate = parse_num(raw.rate),
        preserve_pitch = parse_bool(raw.pp),
        loop = parse_bool(raw.loop),
        mute = parse_bool(raw.mute),
        lock = parse_bool(raw.lock),
        reverse = parse_bool(raw.reverse),
        pitch = parse_num(raw.pitch),
        bpm = parse_num(raw.bpm),
    }
end

local function toggle(name, on)
    if api(name) then r[name](on and "1" or "0", 0) end
end

function Item.UpdatePreservePitch(_, preserve) toggle("FIP_SetSelectedItemsPreservePitch", preserve) end
function Item.UpdateLoop(_, loop) toggle("FIP_SetSelectedItemsLoop", loop) end
function Item.UpdateMute(_, mute) toggle("FIP_SetSelectedItemsMute", mute) end
function Item.UpdateLock(_, lock) toggle("FIP_SetSelectedItemsLock", lock) end
function Item.UpdateReverse(_, reverse) toggle("FIP_SetSelectedItemsReverse", reverse) end

return Item
