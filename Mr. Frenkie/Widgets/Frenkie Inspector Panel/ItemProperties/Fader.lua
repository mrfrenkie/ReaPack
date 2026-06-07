-- @noindex

-- @noindex
---@diagnostic disable: undefined-global, undefined-field
local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Utils = require("Utils")
local Take = require("Take")
local Theme = require("Theme")

local Fader = {}
local _missing_ext_warned = false
local vol_value_edit = { active = false, text = '', want_focus = false }
local vel_value_edit = { active = false, text = '', want_focus = false }

local function FaderExtensionAvailable()
    if not (r.APIExists and r.APIExists("FIP_GetSelectedItemsFaderKind")) then
        return false
    end
    if not (r.APIExists("FIP_VolumeFaderApplyDb") and r.APIExists("FIP_VelocityFaderApplyScale")) then
        return false
    end
    return true
end

local function MissingExtensionControl(ctx, items, props, bar_color, UI)
    if not _missing_ext_warned then
        _missing_ext_warned = true
        r.ShowConsoleMsg("FIP: extension API missing/outdated. Rebuild & reload reaper_frenkie_core.dylib.\n")
    end
    UI.StyledResetButton(ctx, 'Vol:', 35, false, function() end, true)
    r.ImGui_SameLine(ctx, 0, 2)
    r.ImGui_SetNextItemWidth(ctx, 120)
    r.ImGui_BeginDisabled(ctx, true)
    r.ImGui_SliderDouble(ctx, '##FIP_ExtMissing', 0.0, 0.0, 1.0, "Extension missing")
    r.ImGui_EndDisabled(ctx)
    Take.Render(ctx, items, props, UI, bar_color)
end

function Fader.ResetAccumulatedValues()
    if r.APIExists and r.APIExists("FIP_ResetFaderSessions") then
        r.FIP_ResetFaderSessions("", 0)
    end
end


function Fader.VolumeControl(ctx, items, props, bar_color, UI)
    local is_vol_modified = false
    local is_vol_mixed = false
    local item_count = (props and props.sel_item_count) or 0
    if item_count == 0 then
        if r.APIExists and r.APIExists("FIP_CountSelectedItems") then
            item_count = math.floor(tonumber((r.FIP_CountSelectedItems("", 0))) or 0)
        end
    end

    local is_multi = item_count > 1
    local vol_val = -1.0
    if is_multi then
        local vol_state = (r.APIExists and r.APIExists("FIP_GetSelectedItemsVolumeStateVal"))
            and (r.FIP_GetSelectedItemsVolumeStateVal("", 0) or 0)
            or 0
        is_vol_mixed = (vol_state < 0)
        is_vol_modified = (vol_state > 0)
    else
        vol_val = (r.APIExists and r.APIExists("FIP_GetAggregatedVolumeVal")) and r.FIP_GetAggregatedVolumeVal("", 0) or -1.0
        is_vol_mixed = (type(vol_val) == "number" and vol_val < 0.0) or false
        is_vol_modified = (type(vol_val) == "number" and vol_val >= 0.0) and (math.abs(vol_val - 1.0) > 0.001) or false
    end

    local function reset_volume_action()
        props.volume = 1.0
        if is_multi and (r.APIExists and r.APIExists("FIP_ResetSelectedItemsVolumeDeltaDbVal")) then
            if r.APIExists and r.APIExists("FIP_SetSelectedItemsVolume") then
                r.FIP_SetSelectedItemsVolume("1.0", 0)
            end
            r.FIP_ResetSelectedItemsVolumeDeltaDbVal("", 0)
        elseif r.APIExists and r.APIExists("FIP_VolumeFaderReset") then
            r.FIP_VolumeFaderReset("", 0)
        elseif r.APIExists and r.APIExists("FIP_SetSelectedItemsVolume") then
            Utils.with_undo("Reset Volume", function()
                r.FIP_SetSelectedItemsVolume("1.0", 0)
            end)
        end
    end
    UI.StyledResetButton(ctx, 'Vol:', 35, is_vol_modified, reset_volume_action, false, is_vol_mixed)
    if item_count > 1 then
        UI.ExtendAggHoverRegion(ctx)
    end
    UI.QueueStyledTooltipDelayed(ctx, 'fip_vol_rst', UI.GetVolumeFaderTooltipLines(), 1.0)
    r.ImGui_SameLine(ctx, 0, 2)

    local display_db = 0.0
    if is_multi then
        display_db = (r.APIExists and r.APIExists("FIP_GetSelectedItemsVolumeDeltaDbVal"))
            and (r.FIP_GetSelectedItemsVolumeDeltaDbVal("", 0) or 0)
            or 0
    else
        if r.APIExists and r.APIExists("FIP_VolumeFaderGetDisplayDb") then
            display_db = r.FIP_VolumeFaderGetDisplayDb("", 0)
        else
            local base = (type(vol_val) == "number" and vol_val >= 0.0) and vol_val or 1.0
            display_db = Utils.vol_to_db(base)
        end
    end

    if not vol_value_edit.active then
        r.ImGui_SetNextItemWidth(ctx, 120)
        local vol_changed, new_vol_db, vol_deactivated, vol_alt_clicked, vol_dbl_clicked = UI.StyledSlider(ctx, '##Volume', display_db, -60.0, 12.0, "%.1f dB", bar_color)
        local vol_activated = r.ImGui_IsItemActivated(ctx)
        if item_count > 1 then
            UI.DrawAggregationOutline(ctx, nil, 4, 0)
            UI.ExtendAggHoverRegion(ctx)
        end
        UI.QueueStyledTooltipDelayed(ctx, 'fip_vol_slider', UI.GetVolumeFaderTooltipLines(), 1.0)
        if vol_alt_clicked then
            vol_value_edit.active = true
            vol_value_edit.text = string.format('%.2f', display_db)
            vol_value_edit.want_focus = true
            vol_changed = false
            vol_deactivated = false
            vol_activated = false
        elseif vol_dbl_clicked then
            reset_volume_action()
            vol_changed = false
            vol_deactivated = false
            vol_activated = false
        end
        if (not is_multi) and vol_activated and r.APIExists and r.APIExists("FIP_VolumeFaderBegin") then
            r.FIP_VolumeFaderBegin("", 0)
        end
        if vol_changed then
            if is_multi then
                local delta = new_vol_db - display_db
                if math.abs(delta) > 0.0001 and r.APIExists and r.APIExists("FIP_ApplyAddSelectedItemsVolumeDbDeltaVal") then
                    r.FIP_ApplyAddSelectedItemsVolumeDbDeltaVal(tostring(delta), 0)
                end
            else
                if r.APIExists and r.APIExists("FIP_VolumeFaderApplyDb") then
                    r.FIP_VolumeFaderApplyDb(tostring(new_vol_db), 0)
                else
                    local new_volume = Utils.db_to_vol(new_vol_db)
                    props.volume = new_volume
                    if r.APIExists and r.APIExists("FIP_SetSelectedItemsVolume") then
                        r.FIP_SetSelectedItemsVolume(tostring(props.volume), 0)
                    end
                end
            end
        end
        if vol_deactivated then
            if is_multi then
                Utils.with_undo("Change Volume", function() end)
            elseif r.APIExists and r.APIExists("FIP_VolumeFaderEnd") then
                r.FIP_VolumeFaderEnd("Change Volume", 0)
            end
        end
    else
        r.ImGui_SetNextItemWidth(ctx, 120)
        if vol_value_edit.want_focus then
            r.ImGui_SetKeyboardFocusHere(ctx)
            vol_value_edit.want_focus = false
        end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_42'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), Theme.get('gray_74'))
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 4)
        local input_flags = r.ImGui_InputTextFlags_CharsDecimal()
                          | r.ImGui_InputTextFlags_EnterReturnsTrue()
                          | r.ImGui_InputTextFlags_AutoSelectAll()
        local vol_submitted, new_text = r.ImGui_InputText(ctx, '##VolumeValue', vol_value_edit.text, input_flags)
        vol_value_edit.text = new_text
        local vol_d = Utils.ClearCursorContextOnDeactivation(ctx)
        r.ImGui_PopStyleVar(ctx, 2)
        r.ImGui_PopStyleColor(ctx, 2)
        if item_count > 1 then
            UI.DrawAggregationOutline(ctx, nil, 4, 0)
            UI.ExtendAggHoverRegion(ctx)
        end
        UI.QueueStyledTooltipDelayed(ctx, 'fip_vol_slider', UI.GetVolumeFaderTooltipLines(), 1.0)
        if vol_submitted or vol_d then
            local parsed = tonumber(((vol_value_edit.text or ''):gsub(',', '.')))
            if parsed then
                if parsed < -60.0 then parsed = -60.0 end
                if parsed > 12.0 then parsed = 12.0 end
                if is_multi then
                    local delta = parsed - display_db
                    if math.abs(delta) > 0.0001 and r.APIExists and r.APIExists("FIP_ApplyAddSelectedItemsVolumeDbDeltaVal") then
                        r.FIP_ApplyAddSelectedItemsVolumeDbDeltaVal(tostring(delta), 0)
                    end
                    Utils.with_undo("Change Volume", function() end)
                else
                    props.volume = Utils.db_to_vol(parsed)
                    if r.APIExists and r.APIExists("FIP_SetSelectedItemsVolume") then
                        r.FIP_SetSelectedItemsVolume(tostring(props.volume), 0)
                    end
                    Utils.with_undo("Change Volume", function() end)
                end
            end
            vol_value_edit.active = false
        end
    end
    Take.Render(ctx, items, props, UI, bar_color)
end

function Fader.VelocityControl(ctx, items, props, bar_color, UI)
    local is_vel_modified = false
    local is_vel_mixed = false
    local item_count = (props and props.sel_item_count) or 0
    if item_count == 0 then
        if r.APIExists and r.APIExists("FIP_CountSelectedItems") then
            item_count = math.floor(tonumber((r.FIP_CountSelectedItems("", 0))) or 0)
        end
    end

    local is_multi = item_count > 1
    local vel_val = -1.0
    if is_multi then
        local vel_state = (r.APIExists and r.APIExists("FIP_GetSelectedItemsVelocityScaleStateVal"))
            and (r.FIP_GetSelectedItemsVelocityScaleStateVal("", 0) or 0)
            or 0
        is_vel_mixed = (vel_state < 0)
        is_vel_modified = (vel_state > 0)
    else
        vel_val = (r.APIExists and r.APIExists("FIP_GetAggregatedVelocityScaleVal")) and r.FIP_GetAggregatedVelocityScaleVal("", 0) or -1.0
        is_vel_mixed = (type(vel_val) == "number" and vel_val < 0.0) or false
        is_vel_modified = (type(vel_val) == "number" and vel_val >= 0.0) and (math.abs(vel_val - 1.0) > 0.001) or false
    end

    local function reset_velocity_action()
        props.velocity_scale = 1.0
        if is_multi and (r.APIExists and r.APIExists("FIP_ResetSelectedItemsVelocityScaleDeltaVal")) then
            if r.APIExists and r.APIExists("FIP_SetSelectedMIDIVelocityScale") then
                r.FIP_SetSelectedMIDIVelocityScale("1.0", 0)
            end
            r.FIP_ResetSelectedItemsVelocityScaleDeltaVal("", 0)
        elseif r.APIExists and r.APIExists("FIP_VelocityFaderReset") then
            r.FIP_VelocityFaderReset("", 0)
        elseif r.APIExists and r.APIExists("FIP_SetSelectedMIDIVelocityScale") then
            Utils.with_undo("Reset Velocity", function()
                r.FIP_SetSelectedMIDIVelocityScale("1.0", 0)
            end)
        end
    end
    UI.StyledResetButton(ctx, 'Vel:', 35, is_vel_modified, reset_velocity_action, false, is_vel_mixed)
    if item_count > 1 then
        UI.ExtendAggHoverRegion(ctx)
    end
    UI.QueueStyledTooltipDelayed(ctx, 'fip_vel_rst', UI.GetVelocityFaderTooltipLines(), 1.0)
    r.ImGui_SameLine(ctx, 0, 2)

    local display_velocity = 1.0
    if is_multi then
        local delta = (r.APIExists and r.APIExists("FIP_GetSelectedItemsVelocityScaleDeltaVal"))
            and (r.FIP_GetSelectedItemsVelocityScaleDeltaVal("", 0) or 0)
            or 0
        display_velocity = 1.0 + delta
    else
        if r.APIExists and r.APIExists("FIP_VelocityFaderGetDisplayScale") then
            display_velocity = r.FIP_VelocityFaderGetDisplayScale("", 0)
        else
            display_velocity = (type(vel_val) == "number" and vel_val >= 0.0) and vel_val or 1.0
        end
    end

    if not vel_value_edit.active then
        r.ImGui_SetNextItemWidth(ctx, 120)
        local vel_changed, vel, vel_deactivated, vel_alt_clicked, vel_dbl_clicked = UI.StyledSlider(ctx, '##Velocity', display_velocity, 0.0, 2.0, "x%.2f", bar_color)
        local vel_activated = r.ImGui_IsItemActivated(ctx)
        if item_count > 1 then
            UI.DrawAggregationOutline(ctx, nil, 4, 0)
            UI.ExtendAggHoverRegion(ctx)
        end
        UI.QueueStyledTooltipDelayed(ctx, 'fip_vel_slider', UI.GetVelocityFaderTooltipLines(), 1.0)
        if vel_alt_clicked then
            vel_value_edit.active = true
            vel_value_edit.text = string.format('%.2f', display_velocity)
            vel_value_edit.want_focus = true
            vel_changed = false
            vel_deactivated = false
            vel_activated = false
        elseif vel_dbl_clicked then
            reset_velocity_action()
            vel_changed = false
            vel_deactivated = false
            vel_activated = false
        end
        if (not is_multi) and vel_activated and r.APIExists and r.APIExists("FIP_VelocityFaderBegin") then
            r.FIP_VelocityFaderBegin("", 0)
        end
        if vel_changed then
            if is_multi then
                local delta = vel - display_velocity
                if math.abs(delta) > 0.0001 and r.APIExists and r.APIExists("FIP_ApplyAddSelectedItemsVelocityScaleDeltaVal") then
                    r.FIP_ApplyAddSelectedItemsVelocityScaleDeltaVal(tostring(delta), 0)
                end
            else
                if r.APIExists and r.APIExists("FIP_VelocityFaderApplyScale") then
                    r.FIP_VelocityFaderApplyScale(tostring(vel), 0)
                else
                    props.velocity_scale = vel
                    if r.APIExists and r.APIExists("FIP_SetSelectedMIDIVelocityScale") then
                        r.FIP_SetSelectedMIDIVelocityScale(tostring(vel), 0)
                    end
                end
            end
        end
        if vel_deactivated then
            if is_multi then
                Utils.with_undo("Change Velocity", function() end)
            elseif r.APIExists and r.APIExists("FIP_VelocityFaderEnd") then
                r.FIP_VelocityFaderEnd("Change Velocity", 0)
            end
        end
    else
        r.ImGui_SetNextItemWidth(ctx, 120)
        if vel_value_edit.want_focus then
            r.ImGui_SetKeyboardFocusHere(ctx)
            vel_value_edit.want_focus = false
        end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_42'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), Theme.get('gray_74'))
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 4)
        local input_flags = r.ImGui_InputTextFlags_CharsDecimal()
                          | r.ImGui_InputTextFlags_EnterReturnsTrue()
                          | r.ImGui_InputTextFlags_AutoSelectAll()
        local vel_submitted, new_text = r.ImGui_InputText(ctx, '##VelocityValue', vel_value_edit.text, input_flags)
        vel_value_edit.text = new_text
        local vel_d = Utils.ClearCursorContextOnDeactivation(ctx)
        r.ImGui_PopStyleVar(ctx, 2)
        r.ImGui_PopStyleColor(ctx, 2)
        if item_count > 1 then
            UI.DrawAggregationOutline(ctx, nil, 4, 0)
            UI.ExtendAggHoverRegion(ctx)
        end
        UI.QueueStyledTooltipDelayed(ctx, 'fip_vel_slider', UI.GetVelocityFaderTooltipLines(), 1.0)
        if vel_submitted or vel_d then
            local parsed = tonumber(((vel_value_edit.text or ''):gsub(',', '.')))
            if parsed then
                if parsed < 0.0 then parsed = 0.0 end
                if parsed > 2.0 then parsed = 2.0 end
                if is_multi then
                    local delta = parsed - display_velocity
                    if math.abs(delta) > 0.0001 and r.APIExists and r.APIExists("FIP_ApplyAddSelectedItemsVelocityScaleDeltaVal") then
                        r.FIP_ApplyAddSelectedItemsVelocityScaleDeltaVal(tostring(delta), 0)
                    end
                    Utils.with_undo("Change Velocity", function() end)
                else
                    props.velocity_scale = parsed
                    if r.APIExists and r.APIExists("FIP_SetSelectedMIDIVelocityScale") then
                        r.FIP_SetSelectedMIDIVelocityScale(tostring(parsed), 0)
                    end
                    Utils.with_undo("Change Velocity", function() end)
                end
            end
            vel_value_edit.active = false
        end
    end
    Take.Render(ctx, items, props, UI, bar_color)
end

function Fader.MixedVolumeControl(ctx, items, props, bar_color, UI)
    local item_count = (props and props.sel_item_count) or 0
    if item_count == 0 then
        if r.APIExists and r.APIExists("FIP_CountSelectedItems") then
            item_count = math.floor(tonumber((r.FIP_CountSelectedItems("", 0))) or 0)
        end
    end
    UI.StyledResetButton(ctx, 'Vol:', 35, false, function()
    end, true)
    if item_count > 1 then
        UI.ExtendAggHoverRegion(ctx)
    end
    r.ImGui_SameLine(ctx, 0, 2)
    r.ImGui_SetNextItemWidth(ctx, 120)
    r.ImGui_BeginDisabled(ctx, true)
    r.ImGui_SliderDouble(ctx, '##VolumeMixed', 1.0, 0.0, 2.0, "Mixed")
    r.ImGui_EndDisabled(ctx)
    if item_count > 1 then
        UI.ExtendAggHoverRegion(ctx)
    end
    Take.Render(ctx, items, props, UI, bar_color)
end

function Fader.RenderFaders(ctx, items, props, bar_color, UI)
    if not FaderExtensionAvailable() then
        MissingExtensionControl(ctx, items, props, bar_color, UI)
        return
    end

    local kind = nil
    if r.APIExists and r.APIExists("FIP_GetSelectedItemsFaderKind") then
        kind = r.FIP_GetSelectedItemsFaderKind("", 0)
    end

    if kind ~= nil then
        if kind == 0 then
            Fader.VolumeControl(ctx, items, props, bar_color, UI)
        elseif kind == 1 then
            Fader.VelocityControl(ctx, items, props, bar_color, UI)
        elseif kind == 2 then
            Fader.MixedVolumeControl(ctx, items, props, bar_color, UI)
        end
        return
    end

    if props.take_type == "Audio" then
        Fader.VolumeControl(ctx, items, props, bar_color, UI)
    elseif props.take_type == "MIDI" then
        Fader.VelocityControl(ctx, items, props, bar_color, UI)
    elseif props.take_type == "Mult" then
        Fader.MixedVolumeControl(ctx, items, props, bar_color, UI)
    end
end

return Fader
