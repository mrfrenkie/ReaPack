-- @noindex

---@diagnostic disable: undefined-global, undefined-field
local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Core = require("Core")
local Utils = require("Utils")

local Item = {}

function Item.GetSelectedItems()
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

function Item.GetTake(item)
    if not item then return nil end
    return r.GetActiveTake(item)
end

function Item.GetTakeType(take)
    if not take then return "Empty" end
    local source = r.GetMediaItemTake_Source(take)
    if not source then return "Empty" end
    local source_type = r.GetMediaSourceType(source, "")
    return source_type == "MIDI" and "MIDI" or "Audio"
end

function Item.GetTakeSourceReverse(take)
    if not take then return false end
    local src = r.GetMediaItemTake_Source(take)
    if not src then return false end
    local ok, offs, len, rev = r.PCM_Source_GetSectionInfo(src)
    if ok then return rev == true end
    return false
end

function Item.IsItemReversed(item)
    if not item or not r.ValidatePtr(item, "MediaItem*") then return false end
    local take = Item.GetTake(item)
    if not take then return false end
    if r.GetMediaItemTakeInfo_Value(take, "B_REVERSE") == 1 then return true end
    if Item.GetTakeSourceReverse(take) then return true end
    return false
end

function Item.ItemHasFX(item)
    if not item then return false end
    local take = Item.GetTake(item)
    if not take then return false end
    return r.TakeFX_GetCount(take) > 0
end

function Item.FormatRateValue(rate)
    if not rate then return "1.000" end
    return string.format("%.3f", rate)
end

function Item.GetAggregatedProps(items)
    return Core.GetAggregatedProps(items)
end

function Item.UpdatePreservePitch(items, preserve)
    Utils.with_undo("Toggle Preserve Pitch", function()
        if r.APIExists and r.APIExists("FIP_SetSelectedItemsPreservePitch") then
            r.FIP_SetSelectedItemsPreservePitch(preserve and "1" or "0", 0)
        else
            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPreservePitch not available\n")
        end
    end)
end

function Item.UpdateLoop(items, loop)
    Utils.with_undo("Toggle Loop", function()
        if r.APIExists and r.APIExists("FIP_SetSelectedItemsLoop") then
            r.FIP_SetSelectedItemsLoop(loop and "1" or "0", 0)
        else
            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsLoop not available\n")
        end
    end)
end

function Item.UpdateMute(items, mute)
    Utils.with_undo("Toggle Mute", function()
        if r.APIExists and r.APIExists("FIP_SetSelectedItemsMute") then
            r.FIP_SetSelectedItemsMute(mute and "1" or "0", 0)
        else
            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsMute not available\n")
        end
    end)
end

function Item.UpdateLock(items, lock)
    Utils.with_undo("Toggle Lock", function()
        if r.APIExists and r.APIExists("FIP_SetSelectedItemsLock") then
            r.FIP_SetSelectedItemsLock(lock and "1" or "0", 0)
        else
            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsLock not available\n")
        end
    end)
end

function Item.UpdateReverse(items, reverse)
    Utils.with_undo("Toggle Reverse", function()
        if r.APIExists and r.APIExists("FIP_SetSelectedItemsReverse") then
            r.FIP_SetSelectedItemsReverse(reverse and "1" or "0", 0)
        else
            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsReverse not available\n")
        end
    end)
end

function Item.RemoveAllFX(items)
    Utils.with_undo('Remove all item FX', function()
        for _, item in ipairs(items) do
            local take = Item.GetTake(item)
            if take then
                local fx_count = r.TakeFX_GetCount(take)
                for fx_idx = fx_count - 1, 0, -1 do
                    r.TakeFX_Delete(take, fx_idx)
                end
            end
        end
    end)
end

function Item.OpenFXChain(items)
    r.Main_OnCommand(40638, 0)
end

return Item
