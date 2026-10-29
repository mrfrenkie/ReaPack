-- @noindex
---@diagnostic disable: undefined-global, undefined-field
local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Utils = require("Utils")
local Take = require("Take")
local Theme = require("Theme")

-- Vol:/Vel: row. Logic lives in the extension (FIP_LevelBox*); this file draws and forwards mouse input.
local Fader = {}
local _missing_ext_warned = false
local value_edit = { active = false, text = '', want_focus = false }

-- Fixed width for every state (dB, -inf, x1.25, Mixed, editing) so nothing to the right ever shifts.
-- Sized for four digits with dB, e.g. "-150.0 dB".
local function BoxWidth(ctx)
    local pad_x = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())
    return r.ImGui_CalcTextSize(ctx, '-888.8 dB') + pad_x * 2
end

local function MissingExtensionControl(ctx, items, props, bar_color, UI)
    if not _missing_ext_warned then
        _missing_ext_warned = true
        r.ShowConsoleMsg("FIP: extension API missing/outdated. Rebuild & reload reaper_frenkie_core.dylib.\n")
    end
    UI.StyledResetButton(ctx, 'Vol:', 35, false, function() end, true)
    r.ImGui_SameLine(ctx, 0, 2)
    UI.LevelBox(ctx, '##FIP_ExtMissing', 'n/a', BoxWidth(ctx), true)
    Take.Render(ctx, items, props, UI, bar_color)
end

local function ValueInput(ctx, width, tooltip, UI)
    r.ImGui_SetNextItemWidth(ctx, width)
    if value_edit.want_focus then
        r.ImGui_SetKeyboardFocusHere(ctx)
        value_edit.want_focus = false
    end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_42'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), Theme.get('gray_74'))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 4)
    local input_flags = r.ImGui_InputTextFlags_EnterReturnsTrue()
                      | r.ImGui_InputTextFlags_AutoSelectAll()
    local submitted, new_text = r.ImGui_InputText(ctx, '##LevelValue', value_edit.text, input_flags)
    value_edit.text = new_text
    local deactivated = Utils.ReturnFocusOnDeactivation(ctx)
    r.ImGui_PopStyleVar(ctx, 2)
    r.ImGui_PopStyleColor(ctx, 2)
    UI.QueueStyledTooltipDelayed(ctx, 'fip_lvl_box', tooltip, 1.0)
    if submitted or deactivated then
        r.FIP_LevelBoxSetText(value_edit.text, 0)
        value_edit.active = false
    end
end

function Fader.RenderFaders(ctx, items, props, bar_color, UI)
    if not (r.APIExists and r.APIExists("FIP_LevelBoxGetStateStr")) then
        MissingExtensionControl(ctx, items, props, bar_color, UI)
        return
    end

    local st = Utils.ParseKeyValues(r.FIP_LevelBoxGetStateStr("", 0))
    if st.kind ~= 'vol' and st.kind ~= 'vel' and st.kind ~= 'mixed' then return end
    local is_mixed = st.kind == 'mixed'
    local is_multi = (tonumber(st.count) or 0) > 1
    local tooltip
    if is_mixed then
        tooltip = UI.GetLevelMixedTooltipLines()
        value_edit.active = false
    elseif st.kind == 'vel' then
        tooltip = UI.GetVelocityFaderTooltipLines()
    else
        tooltip = UI.GetVolumeFaderTooltipLines(st.target)
    end

    UI.StyledResetButton(ctx, st.kind == 'vel' and 'Vel:' or 'Vol:', 35, st.modified == '1', function()
        r.FIP_LevelBoxReset("", 0)
    end, is_mixed, st.differ == '1')
    if is_multi then
        UI.ExtendAggHoverRegion(ctx)
    end
    if not is_mixed then
        UI.QueueStyledTooltipDelayed(ctx, 'fip_lvl_rst', tooltip, 1.0)
    end
    r.ImGui_SameLine(ctx, 0, 2)

    local box_w = BoxWidth(ctx)
    if value_edit.active then
        ValueInput(ctx, box_w, tooltip, UI)
    elseif is_mixed then
        local hovered = UI.LevelBox(ctx, '##LevelBox', st.text or '', box_w, true)
        UI.QueueStyledTooltipDelayedGeneric(ctx, 'fip_lvl_box', tooltip, 1.0, hovered)
    else
        local activated, active, deactivated, dx, alt_clicked, dbl_clicked =
            UI.LevelBox(ctx, '##LevelBox', st.text or '', box_w, false)
        UI.QueueStyledTooltipDelayed(ctx, 'fip_lvl_box', tooltip, 1.0)
        if alt_clicked then
            value_edit.active = true
            value_edit.text = ((st.text or ''):gsub(' dB$', ''))
            value_edit.want_focus = true
        elseif dbl_clicked then
            r.FIP_LevelBoxReset("", 0)
        else
            local fine = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0
            if activated then
                r.FIP_LevelBoxDrag(0, 0, 0)
            end
            if active and dx ~= 0 then
                r.FIP_LevelBoxDrag(1, dx, fine and 1 or 0)
            end
        end
        if deactivated then
            r.FIP_LevelBoxDrag(2, 0, 0)
        end
    end
    if is_multi then
        if not is_mixed then
            UI.DrawAggregationOutline(ctx, nil, 4, 0)
        end
        UI.ExtendAggHoverRegion(ctx)
    end
    Take.Render(ctx, items, props, UI, bar_color)
end

return Fader
