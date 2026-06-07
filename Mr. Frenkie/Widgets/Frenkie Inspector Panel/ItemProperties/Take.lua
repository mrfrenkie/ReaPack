-- @noindex

---@diagnostic disable: undefined-global, undefined-field
local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Core = require("Core")
local Theme = require("Theme")

local Take = {}
Take._take_menu_cache = Take._take_menu_cache or { key = "", names = {} }

function Take.Render(ctx, items, props, UI, bar_color)
    UI.Separator(ctx)
    local label_text = 'Take'
    local active_display = nil
    local total_takes = nil
    local has_count_api = r.APIExists and r.APIExists("FIP_GetSingleSelectedItemTakeCountVal")
    local has_index_api = r.APIExists and r.APIExists("FIP_GetSingleSelectedItemActiveTakeIndexVal")
    local has_names_api = r.APIExists and r.APIExists("FIP_GetSingleSelectedItemTakeNamesStr")
    local has_set_api = r.APIExists and r.APIExists("FIP_ApplySingleSelectedItemActiveTakeIndexVal")
    local has_shift_api = r.APIExists and r.APIExists("FIP_ApplyShiftSingleSelectedItemActiveTakeVal")
    local has_toggle_api = r.APIExists and r.APIExists("FIP_GetTakeButtonToggleStateVal")
    local has_action_api = r.APIExists and r.APIExists("FIP_RunTakeButtonActionVal")
    local take_count = has_count_api and r.FIP_GetSingleSelectedItemTakeCountVal("", 0) or -1
    local active_index = has_index_api and r.FIP_GetSingleSelectedItemActiveTakeIndexVal("", 0) or -1
    if type(take_count) == "number" and take_count > 0 and type(active_index) == "number" and active_index >= 0 then
        total_takes = math.floor(take_count)
        active_display = math.floor(active_index) + 1
        label_text = string.format('Take %d/%d', active_display, total_takes)
    end
    local _, _, _, _, _, bar_fg = UI.GetBarColorAndUseBlack(items, {}, props)
    if not label_text:match(":$") then
        label_text = label_text .. ":"
    end
    local is_on = has_toggle_api and (r.FIP_GetTakeButtonToggleStateVal("", 0) == 1.0) or false
    if not is_on then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray')) end
    if not (has_toggle_api and has_action_api) then r.ImGui_BeginDisabled(ctx, true) end
    UI.StyledResetButton(ctx, label_text, 70, false, function()
        local mods = r.ImGui_GetKeyMods(ctx)
        local has_cmd = (mods & r.ImGui_Mod_Super()) ~= 0
        local has_ctrl = (mods & r.ImGui_Mod_Ctrl()) ~= 0
        local has_shift = (mods & r.ImGui_Mod_Shift()) ~= 0
        local has_alt = (mods & r.ImGui_Mod_Alt()) ~= 0
        local mask = 0
        if has_cmd or has_ctrl then mask = mask | 1 end
        if has_shift then mask = mask | 2 end
        if has_alt then mask = mask | 4 end
        r.FIP_RunTakeButtonActionVal(tostring(mask), 0)
    end, false)
    if has_toggle_api and has_action_api then
        UI.QueueStyledTooltipDelayed(ctx, 'fip_take_tcp', UI.GetTakeTcpMirrorTooltipLines(), 1.0)
    end
    if not (has_toggle_api and has_action_api) then r.ImGui_EndDisabled(ctx) end
    if not is_on then r.ImGui_PopStyleColor(ctx, 1) end
    r.ImGui_SameLine(ctx, 0, 5)
    if #items == 1 then
        local can_edit_takes = has_count_api and has_index_api and has_names_api and has_set_api and has_shift_api
        if can_edit_takes and type(take_count) == "number" and take_count > 0 and type(active_index) == "number" and active_index >= 0 then
            local take_count_i = math.floor(take_count)
            local active_index_i = math.floor(active_index)
            local state = Core.GetState()
            local sig = state.cached_items_sig or ""
            local cache_key = sig .. ":" .. tostring(take_count_i)
            local cache = Take._take_menu_cache
            if cache.key ~= cache_key then
                local names = {}
                local raw = r.FIP_GetSingleSelectedItemTakeNamesStr("\n", 0) or ""
                local idx = 0
                if raw ~= "" then
                    for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
                        if idx >= take_count_i then break end
                        if line ~= "" then
                            names[idx + 1] = tostring(idx + 1) .. ": " .. line
                        else
                            names[idx + 1] = tostring(idx + 1)
                        end
                        idx = idx + 1
                    end
                end
                while idx < take_count_i do
                    names[idx + 1] = tostring(idx + 1)
                    idx = idx + 1
                end
                cache.key = cache_key
                cache.names = names
            end
            local names = cache.names or {}
            r.ImGui_SetNextItemWidth(ctx, 120)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), bar_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), bar_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), bar_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), bar_color)
            local preview = names[active_index_i + 1]
            if type(preview) ~= "string" then preview = "" end
            UI.PushBarForegroundText(ctx, bar_fg)
            local opened
            do
                local ok_flag, no_arrow = pcall(r.ImGui_ComboFlags_NoArrowButton)
                if ok_flag and no_arrow then
                    opened = r.ImGui_BeginCombo(ctx, '##TakeSelectInline', preview, no_arrow)
                else
                    opened = r.ImGui_BeginCombo(ctx, '##TakeSelectInline', preview)
                end
            end
            UI.PopBarForegroundText(ctx)
            UI.DrawHoverActiveOverlay(ctx)
            r.ImGui_PopStyleColor(ctx, 4)
            if opened then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), Theme.get('gray_30'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), Theme.get('gray_58'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), Theme.get('gray_64'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), Theme.get('gray_74'))
                for i = 0, take_count_i - 1 do
                    local sel = (i == active_index_i)
                    local display_name = names[i + 1]
                    if type(display_name) ~= "string" then display_name = "" end
                    local label = display_name .. "##Take_" .. i
                    if r.ImGui_Selectable(ctx, label, sel) then
                        r.FIP_ApplySingleSelectedItemActiveTakeIndexVal(tostring(i), 0)
                        local state = Core.GetState()
                        state.cached_props = Core.GetAggregatedProps(items)
                        Core.SetState(state)
                    end
                end
                r.ImGui_PopStyleColor(ctx, 4)
                r.ImGui_EndCombo(ctx)
            end
            UI.QueueStyledTooltipDelayed(ctx, 'fip_take_combo', UI.GetTakeSelectTooltipLines(), 1.0)
            r.ImGui_SameLine(ctx, 0, 4)
            UI.PushTransparentButtonStates(ctx, false)
            local prev_disabled = (active_index_i <= 0)
            local prev_clicked
            if prev_disabled then
                r.ImGui_BeginDisabled(ctx, true)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('frame_disabled'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('frame_disabled'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('frame_disabled'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray'))
                local ok_dir, dir_left = pcall(r.ImGui_Dir_Left)
                if ok_dir and dir_left then
                    prev_clicked = r.ImGui_ArrowButton(ctx, '##TakePrev', dir_left)
                else
                    prev_clicked = r.ImGui_Button(ctx, '<', 20)
                end
                r.ImGui_EndDisabled(ctx)
                r.ImGui_PopStyleColor(ctx, 4)
            else
                local ok_dir, dir_left = pcall(r.ImGui_Dir_Left)
                if ok_dir and dir_left then
                    prev_clicked = r.ImGui_ArrowButton(ctx, '##TakePrev', dir_left)
                else
                    prev_clicked = r.ImGui_Button(ctx, '<', 20)
                end
            end
            UI.DrawHoverActiveOverlay(ctx)
            UI.QueueStyledTooltipDelayed(ctx, 'fip_take_prev', UI.GetTakePrevTooltipLines(), 1.0)
            r.ImGui_SameLine(ctx, 0, 2)
            local next_disabled = (active_index_i >= take_count_i - 1)
            local next_clicked
            if next_disabled then
                r.ImGui_BeginDisabled(ctx, true)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('frame_disabled'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('frame_disabled'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('frame_disabled'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray'))
                local ok_dir2, dir_right = pcall(r.ImGui_Dir_Right)
                if ok_dir2 and dir_right then
                    next_clicked = r.ImGui_ArrowButton(ctx, '##TakeNext', dir_right)
                else
                    next_clicked = r.ImGui_Button(ctx, '>', 20)
                end
                r.ImGui_EndDisabled(ctx)
                r.ImGui_PopStyleColor(ctx, 4)
            else
                local ok_dir2, dir_right = pcall(r.ImGui_Dir_Right)
                if ok_dir2 and dir_right then
                    next_clicked = r.ImGui_ArrowButton(ctx, '##TakeNext', dir_right)
                else
                    next_clicked = r.ImGui_Button(ctx, '>', 20)
                end
            end
            UI.DrawHoverActiveOverlay(ctx)
            UI.QueueStyledTooltipDelayed(ctx, 'fip_take_next', UI.GetTakeNextTooltipLines(), 1.0)
            r.ImGui_PopStyleColor(ctx, 3)
            if (prev_clicked and not prev_disabled) or (next_clicked and not next_disabled) then
                local delta = prev_clicked and -1 or 1
                r.FIP_ApplyShiftSingleSelectedItemActiveTakeVal(tostring(delta), 0)
                local state = Core.GetState()
                state.cached_props = Core.GetAggregatedProps(items)
                Core.SetState(state)
            end
        end
    else
        r.ImGui_SetNextItemWidth(ctx, 120)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), bar_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), bar_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), bar_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), bar_color)
        r.ImGui_BeginDisabled(ctx, true)
        local preview_multi = UI.GetSingleItemOnlyLabel()
        UI.PushBarForegroundText(ctx, bar_fg)
        local opened_multi
        do
            local ok_flag2, no_arrow2 = pcall(r.ImGui_ComboFlags_NoArrowButton)
            if ok_flag2 and no_arrow2 then
                opened_multi = r.ImGui_BeginCombo(ctx, '##TakeSelectInline', preview_multi, no_arrow2)
            else
                opened_multi = r.ImGui_BeginCombo(ctx, '##TakeSelectInline', preview_multi)
            end
        end
        UI.PopBarForegroundText(ctx)
        if opened_multi then r.ImGui_EndCombo(ctx) end
        r.ImGui_EndDisabled(ctx)
        UI.QueueStyledTooltipDelayed(ctx, 'fip_take_combo_disabled', UI.GetTakeSingleItemOnlyTooltipLines(), 1.0)
        r.ImGui_PopStyleColor(ctx, 4)
        r.ImGui_SameLine(ctx, 0, 4)
        r.ImGui_BeginDisabled(ctx, true)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('frame_disabled'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('frame_disabled'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('frame_disabled'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray'))
        local _ = r.ImGui_Button(ctx, '<', 20)
        r.ImGui_SameLine(ctx, 0, 2)
        local __ = r.ImGui_Button(ctx, '>', 20)
        r.ImGui_EndDisabled(ctx)
        r.ImGui_PopStyleColor(ctx, 4)
    end
end

return Take
