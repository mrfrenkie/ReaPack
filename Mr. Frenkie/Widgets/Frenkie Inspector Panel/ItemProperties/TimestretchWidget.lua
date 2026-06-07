-- @noindex

---@diagnostic disable: undefined-global, undefined-field
local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Utils = require("Utils")
local UI = require("UIComponents")
local Theme = require("Theme")
local Core = require("Core")
local Item = require("Item")

local TimestrechWidget = {}
local cached_modes = nil

local function parse_modes_str(s)
    local out = {}
    if type(s) ~= "string" or s == "" then return out end
    for line in s:gmatch("[^\n]+") do
        local m, n = line:match("^(%-?%d+)%s+(.+)$")
        if m and n then
            out[#out + 1] = { mode = tonumber(m), name = n }
        end
    end
    return out
end

local function enum_modes()
    if cached_modes then return cached_modes end
    if r.APIExists and r.APIExists("FIP_EnumPitchShiftModesSortedStr") then
        local rows = r.FIP_EnumPitchShiftModesSortedStr("\n", 0)
        cached_modes = parse_modes_str(rows)
        if cached_modes and #cached_modes > 0 then
            return cached_modes
        end
    end
    cached_modes = {}
    cached_modes[#cached_modes + 1] = { mode = -1, name = "Project Default" }
    for mode = 0, 4096 do
        local ok, name = r.EnumPitchShiftModes(mode)
        if not ok then break end
        if name and name ~= "" then
            cached_modes[#cached_modes + 1] = { mode = mode, name = name }
        end
    end
    return cached_modes
end

local function get_mode_name(mode)
    if mode == -1 then return "Project Default" end
    if r.APIExists and r.APIExists("FIP_GetPitchShiftModeNameStr") then
        local s = r.FIP_GetPitchShiftModeNameStr(tostring(mode), 0)
        if s and s ~= "" then return s end
    end
    local ok, s = r.EnumPitchShiftModes(mode)
    if ok and s and s ~= "" then return s end
    return "Unknown"
end

local function mode_sort_key(name, mode)
    if mode == -1 then return 0 end
    local s = tostring(name or ""):lower()
    local function has(a) return s:find(a, 1, true) ~= nil end
    if has("élastique") or has("elastique") then
        if has(" pro") then return 10 end
        if has(" efficient") then return 11 end
        if has(" soloist") then return 12 end
        return 19
    end
    if has("rubber band") then return 20 end
    if has("rrreee") then return 30 end
    if has("soundtouch") then return 40 end
    if has("rearearea") then return 50 end
    if has("simple windowed") then return 60 end
    return 999
end

local function sorted_modes()
    local modes = enum_modes()
    local out = {}
    for i = 1, #modes do out[i] = modes[i] end
    table.sort(out, function(a, b)
        local ka = mode_sort_key(a.name, a.mode)
        local kb = mode_sort_key(b.name, b.mode)
        if ka ~= kb then return ka < kb end
        return a.mode < b.mode
    end)
    return out
end

local function is_mode_modified(mode_value)
    return mode_value ~= nil and mode_value ~= -1
end

local function parse_state_str(state_str)
    if type(state_str) ~= "string" or state_str == "" then return nil end
    local tt, ms, a, b = state_str:match("^(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)$")
    if not tt then return nil end
    return tonumber(tt), tonumber(ms), tonumber(a), tonumber(b)
end

local function take_type_from_int(v)
    if v == 0 then return "Audio"
    elseif v == 1 then return "MIDI"
    elseif v == 2 then return "Mult"
    end
    return "Audio"
end

local function RenderDisabledModeLabel(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('transparent'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('transparent'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('transparent'))
    r.ImGui_BeginDisabled(ctx, true)
    r.ImGui_Button(ctx, 'Mode:', 40)
    r.ImGui_EndDisabled(ctx)
    r.ImGui_PopStyleColor(ctx, 3)
end

local function PushStretchModeComboStyle(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_42'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), Theme.get('gray_74'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), Theme.get('gray_58'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), Theme.get('gray_74'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), Theme.get('gray_30'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), Theme.get('gray_58'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), Theme.get('gray_64'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), Theme.get('gray_74'))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, 3)
end

local function PopStretchModeComboStyle(ctx)
    r.ImGui_PopStyleVar(ctx, 2)
    r.ImGui_PopStyleColor(ctx, 8)
end

local function NudgeStretchModeComboUp(ctx)
    local y = r.ImGui_GetCursorPosY(ctx)
    r.ImGui_SetCursorPosY(ctx, y - 1)
end

local function RenderDisabledModeCombo(ctx, preview)
    NudgeStretchModeComboUp(ctx)
    r.ImGui_SetNextItemWidth(ctx, 120)
    PushStretchModeComboStyle(ctx)
    r.ImGui_BeginDisabled(ctx, true)
    r.ImGui_Combo(ctx, '##Mode', 0, (preview or 'Audio Only') .. '\0\0')
    r.ImGui_EndDisabled(ctx)
    PopStretchModeComboStyle(ctx)
end

local function apply_mode(props, items, alg, bits)
    props.mode = alg
    props.mode_bits = bits or 0
    if r.APIExists and r.APIExists("FIP_ApplySelectedItemsStretchModeStrEx") then
        local state_str = r.FIP_ApplySelectedItemsStretchModeStrEx(tostring(alg) .. "," .. tostring(bits or 0), 0)
        local tt, ms, a, b = parse_state_str(state_str)
        if tt and ms and a and b then
            props.take_type = take_type_from_int(tt)
            if ms == -1 then
                props.mode = nil
            elseif ms == 0 then
                props.mode = -1
                props.mode_bits = 0
            elseif ms == 1 and type(a) == "number" and a >= 0 then
                props.mode = math.floor(a)
                props.mode_bits = (type(b) == "number" and b >= 0) and math.floor(b) or 0
            end
            local state = Core.GetState()
            local cached = state.cached_props or {}
            cached.take_type = props.take_type
            cached.mode = props.mode
            cached.mode_bits = props.mode_bits
            state.cached_props = cached
            Core.SetState(state)
            Utils.DeferClearCursorContext()
            return
        end
    end
    if r.APIExists and r.APIExists("FIP_ApplySelectedItemsStretchModeStr") then
        r.FIP_ApplySelectedItemsStretchModeStr(tostring(alg) .. "," .. tostring(bits or 0), 0)
    else
        Utils.with_undo("Change Mode", function()
            if r.APIExists and r.APIExists("FIP_SetSelectedItemsStretchModeStr") then
                r.FIP_SetSelectedItemsStretchModeStr(tostring(alg) .. "," .. tostring(bits or 0), 0)
            else
                r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsStretchModeStr not available\n")
            end
        end)
    end
    Utils.DeferClearCursorContext()
    local state = Core.GetState()
    state.cached_props = Item.GetAggregatedProps(items)
    Core.SetState(state)
end

function TimestrechWidget.Render(ctx, props, items, core, StyledResetButton, accent_color, accent_text_color)
    if props.take_type == "MIDI" then
        RenderDisabledModeLabel(ctx)
        r.ImGui_SameLine(ctx, 0, 5)
        RenderDisabledModeCombo(ctx, 'Audio Only')
    elseif props.take_type == "Mult" then
        RenderDisabledModeLabel(ctx)
        r.ImGui_SameLine(ctx, 0, 5)
        RenderDisabledModeCombo(ctx, 'Audio Only')
    else
        local is_mode_mixed = (props.mode == nil)
        local is_modified = is_mode_modified(props.mode)
        StyledResetButton(ctx, 'Mode:', 40, is_modified, function()
            apply_mode(props, items, -1, 0)
        end, nil, is_mode_mixed)
        UI.QueueStyledTooltipDelayed(ctx, 'fip_mode_rst', UI.GetStretchModeResetTooltipLines(), 1.0)
        r.ImGui_SameLine(ctx, 0, 5)
        local current_name = "Project Default"
        if is_mode_mixed then
            current_name = "Multiple"
        else
            local m = props.mode or -1
            current_name = get_mode_name(m)
        end
        local modes = sorted_modes()
        NudgeStretchModeComboUp(ctx)
        r.ImGui_SetNextItemWidth(ctx, 120)
        PushStretchModeComboStyle(ctx)
        local opened = r.ImGui_BeginCombo(ctx, '##PitchModeMenu', current_name or "Project Default",
            r.ImGui_ComboFlags_HeightLargest())
        UI.QueueStyledTooltipDelayed(ctx, 'fip_mode_menu', UI.GetStretchModeMenuTooltipLines(), 1.0)
        if opened then
            local selection_color = accent_color or Theme.get('green_accent')
            local selection_text_color = accent_text_color or Theme.get('text_white_soft')
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), selection_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), Theme.get('gray_64'))
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), selection_color)
            for _, m in ipairs(modes) do
                local mode = m.mode
                local name = m.name ~= "" and m.name or get_mode_name(mode)
                local selected = (not is_mode_mixed) and ((props.mode or -1) == mode)
                local pushed_text = false
                if selected and selection_text_color ~= Theme.get('text_white_soft') then
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), selection_text_color)
                    pushed_text = true
                end
                if r.ImGui_Selectable(ctx, name .. "##mode_" .. tostring(mode), selected) then
                    if mode == -1 then
                        apply_mode(props, items, -1, 0)
                    else
                        apply_mode(props, items, mode, 0)
                    end
                end
                if pushed_text then
                    r.ImGui_PopStyleColor(ctx, 1)
                end
            end
            r.ImGui_PopStyleColor(ctx, 3)
            r.ImGui_EndCombo(ctx)
        end
        PopStretchModeComboStyle(ctx)
    end
end

return TimestrechWidget
