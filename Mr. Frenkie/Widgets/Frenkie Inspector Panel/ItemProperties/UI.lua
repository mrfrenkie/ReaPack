-- @noindex
---@diagnostic disable: undefined-global, undefined-field
local r = reaper
local script_path_full = debug.getinfo(1, 'S').source:match('@(.*)')
local script_dir = script_path_full:match('(.*[\\/])') or ''
package.path = script_dir .. '?.lua;' .. script_dir .. '?/init.lua;' .. package.path
local TimestrechWidget = require('TimestretchWidget')
local UI = require('UIComponents')
local Theme = require('Theme')
local pitch_module = require('Pitch')
local Fader = require('Fader')
local Utils = require('Utils')
local Track = require('Track')
local Item = require('Item')

-- The widget draws with ReaImGui; everything it shows comes from the reaper_frenkie_core extension.
local function CheckExtensions()
    if not r.ImGui_CreateContext then
        r.ShowMessageBox("ReaImGui extension is required for this script.", "Missing Extension", 0)
        return false
    end
    if not (r.APIExists and r.APIExists('FIP_ContextUpdateStr')) then
        r.ShowMessageBox("The Frenkie core extension (reaper_frenkie_core) is required for this script.", "Missing Extension", 0)
        return false
    end
    return true
end

if not CheckExtensions() then
    return
end

local ctx = nil
local font = nil
local font_italic = nil
local font_bold = nil
local icon_font = nil
local first_auto_resize = true
local initial_item_width = 1100
local bpm_value_edit = { active = false, text = '', want_focus = false }
local rate_value_edit = { active = false, text = '', want_focus = false }
local pitch_value_edit = { active = false, text = '', want_focus = false }
local mt_value_edit = { active = false, text = '', want_focus = false }
local track_items_pitch_value_edit = { active = false, text = '', want_focus = false }
local hp_value_edit = { active = false, text = '', want_focus = false }
local lp_value_edit = { active = false, text = '', want_focus = false }
-- Name typed for an empty item (= first line of its notes) and the selection it belongs to.
local empty_name_edit = { text = nil, sig = nil }
local value_input_reset_grace_frames = 0
local multi_item_pitch_session = { active = false, sig = '', display = 0 }
local midi_item_pitch_session = { active = false, sig = '', display = 0 }

local function reset_multi_item_pitch_session()
    multi_item_pitch_session.active = false
    multi_item_pitch_session.sig = ''
    multi_item_pitch_session.display = 0
end

local function reset_midi_item_pitch_session()
    midi_item_pitch_session.active = false
    midi_item_pitch_session.sig = ''
    midi_item_pitch_session.display = 0
end

--- Last-frame screen-space rect of the FX snapshot row (A–F, +) for hit-testing before item/track context toggle.
local fip_fxsnap_row_screen_rect = { valid = false, x1 = 0, y1 = 0, x2 = 0, y2 = 0 }

--- Normalize values returned from extension APIs (number, or ReaScript-wrapped types).
local function fip_api_double(v)
    if v == nil then return nil end
    local t = type(v)
    if t == 'number' then return v end
    if t == 'boolean' then return v and 1.0 or 0.0 end
    local n = tonumber(v)
    if n ~= nil then return n end
    return tonumber(tostring(v))
end

local function parse_fx_snap_tooltip_ml(s)
    if not s or s == '' then
        return nil
    end
    local rows = {}
    for line in s:gmatch('[^\r\n]+') do
        local bar = line:find('|', 1, true)
        if bar and bar > 1 then
            local code = line:sub(1, bar - 1)
            local rest = line:sub(bar + 1)
            if #code == 1 and code >= '0' and code <= '2' then
                local c = Theme.get('tooltip_text')
                if code == '1' then
                    c = Theme.get('tooltip_fx_bypass')
                elseif code == '2' then
                    c = Theme.get('tooltip_fx_disabled')
                end
                rows[#rows + 1] = { text = rest, color = c }
            else
                rows[#rows + 1] = line
            end
        else
            rows[#rows + 1] = line
        end
    end
    if #rows == 0 then
        return nil
    end
    return rows
end

local function get_fx_snap_slot_tooltip_lines(track, btn_idx)
    if not (track and r.ValidatePtr(track, 'MediaTrack*')) then
        return {}
    end
    local raw = ''
    if r.APIExists and r.APIExists('FIP_TrackFXSnap_GetSlotFxTooltipStr') then
        local n_snap = fip_api_double(r.FIP_TrackFXSnap_GetSlotCountVal(track, '', 0)) or -1
        local sel_slot = fip_api_double(r.FIP_TrackFXSnap_GetSelectedSlotVal(track, '', 0)) or -1
        local can_recall = (n_snap >= 2)
        local is_active = can_recall and (sel_slot == btn_idx)
        local use_live = (not can_recall) or is_active
        local p = use_live and 0.0 or (btn_idx + 0.0)
        raw = r.FIP_TrackFXSnap_GetSlotFxTooltipStr(track, '', p) or ''
    end
    local parsed = parse_fx_snap_tooltip_ml(raw)
    if not parsed then
        local fallback = UI.GetNoFxTooltipLines()
        parsed = { { text = fallback[1], color = Theme.get('tooltip_text') } }
    end
    return parsed
end

local function fip_clear_fxsnap_slot_tooltips(track)
    local g = track and r.GetTrackGUID(track)
    if g and g ~= '' then
        for ti = 1, 8 do
            UI.ClearStyledTooltipHoverState('fip_fxsnap_tt_' .. g .. '_' .. tostring(ti))
        end
    end
end

local function fip_try_fxsnap_slot_context_menu(ctx, slot_1_based, track)
    if not (track and r.ValidatePtr(track, 'MediaTrack*')) then
        return
    end
    local has_rm = r.APIExists and r.APIExists('FIP_TrackFXSnap_RemoveSnapshotSlot')
    local has_cp = r.APIExists and r.APIExists('FIP_TrackFXSnap_CopySnapshotSlot')
    local has_ps = r.APIExists and r.APIExists('FIP_TrackFXSnap_PasteSnapshotSlot')
    local has_cb = r.APIExists and r.APIExists('FIP_TrackFXSnap_ClipboardHasSnapshotVal')
    if not (has_rm or has_cp or has_ps) then
        return
    end
    local pid = 'fip_ctx_fxsnap##' .. tostring(slot_1_based)
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, pid)
    end
    if r.ImGui_BeginPopup(ctx, pid) then
        local can_paste = has_ps and has_cb
            and ((fip_api_double(r.FIP_TrackFXSnap_ClipboardHasSnapshotVal(track, '', 0)) or 0) > 0.5)
        if has_cp then
            if r.ImGui_Selectable(ctx, 'Copy Snapshot##fip_cp_' .. tostring(slot_1_based)) then
                r.FIP_TrackFXSnap_CopySnapshotSlot(track, slot_1_based + 0.0, 0)
                r.ImGui_CloseCurrentPopup(ctx)
            end
        end
        if has_ps then
            if not can_paste then
                r.ImGui_BeginDisabled(ctx, true)
            end
            if r.ImGui_Selectable(ctx, 'Paste Snapshot##fip_ps_' .. tostring(slot_1_based)) then
                local ps = fip_api_double(r.FIP_TrackFXSnap_PasteSnapshotSlot(track, slot_1_based + 0.0, 0))
                if ps ~= nil and ps ~= -1 then
                    fip_clear_fxsnap_slot_tooltips(track)
                    r.UpdateArrange()
                end
                r.ImGui_CloseCurrentPopup(ctx)
            end
            if not can_paste then
                r.ImGui_EndDisabled(ctx)
            end
        end
        if has_rm then
            if r.ImGui_Selectable(ctx, 'Remove Snapshot##fip_rm_' .. tostring(slot_1_based)) then
                local rm = fip_api_double(r.FIP_TrackFXSnap_RemoveSnapshotSlot(track, slot_1_based + 0.0, 0))
                if rm ~= nil and rm ~= -1 then
                    fip_clear_fxsnap_slot_tooltips(track)
                    r.UpdateArrange()
                end
                r.ImGui_CloseCurrentPopup(ctx)
            end
        end
        r.ImGui_EndPopup(ctx)
    end
end

-- ReaImGui 0.10: CreateFont takes a font family name; font files need CreateFontFromFile.
local function CreateFont(file_path)
    return r.ImGui_CreateFontFromFile(file_path)
end

local function PushFont(ctx, font, size)
    r.ImGui_PushFont(ctx, font, size)
end

local function PushFontCompat(ctx, font, size)
    local ok = pcall(r.ImGui_PushFont, ctx, font)
    if not ok then
        r.ImGui_PushFont(ctx, font, size)
    end
end

function EnsureImGuiContext()
    if not ctx then
        local script_path_full = debug.getinfo(1, 'S').source:match('@(.*)')
        local script_dir = script_path_full:match('(.*[\\/])') or ''

        ctx = r.ImGui_CreateContext('Frenkie Item Properties')
        -- System font (with the OS fallback for any script in names and the ⌥⇧⌘ tooltip symbols).
        -- Roboto from fonts/ would need CreateFontFromFile and has no fallback for missing characters.
        font = r.ImGui_CreateFont('sans-serif')
        pcall(r.ImGui_Attach, ctx, font)
        icon_font = CreateFont(script_dir .. 'fonts/FIPIcons.ttf')
        pcall(r.ImGui_Attach, ctx, icon_font)
        UI.SetIconFont(icon_font)
        UI.SetTooltipFont(font, 13)
        local italic_path = script_dir .. 'fonts/Roboto-Italic.ttf'
        local f = io.open(italic_path, 'rb')
        if f then
            f:close()
            font_italic = CreateFont(italic_path)
            pcall(r.ImGui_Attach, ctx, font_italic)
            UI.SetItalicFont(font_italic)
        else
            UI.SetItalicFont(nil)
        end
        local bold_path = script_dir .. 'fonts/Roboto-Bold.ttf'
        local bf = io.open(bold_path, 'rb')
        if bf then
            bf:close()
            font_bold = CreateFont(bold_path)
            pcall(r.ImGui_Attach, ctx, font_bold)
        end
    end
end

local function GetTrackSelectionKey(tracks)
    local parts = {}
    for _, tr in ipairs(tracks or {}) do
        parts[#parts + 1] = r.GetTrackGUID(tr) or ''
    end
    return table.concat(parts, '|')
end

local function IsItemSelection(props)
    return props.take_type == 'Audio' or props.take_type == 'MIDI' or props.take_type == 'Mult' or props.take_type == 'Empty'
end

-- Position / length info at the right end of the item row (REAPER's mouse editing help, see fip_item_info).
local function DrawItemInfoLine(ctx)
    if r.APIExists and r.APIExists('FIP_ItemInfoGetStateStr') then
        UI.ItemInfoLine(ctx, r.FIP_ItemInfoGetStateStr('', 0))
    end
end

local function IsTrackSelection(props)
    return props.take_type == 'Track'
end

local function RoundUpPow2(n)
    if not n or n <= 0 then return 0 end
    local p = 1
    while p < n do p = p * 2 end
    return p
end


-- Frame-to-frame UI memory (the context itself lives in the extension, fip_context.cpp).
local last_items_sig = nil   -- text inputs and pitch sessions reset when the item selection changes
local last_item_props = nil  -- kept while a pitch drag runs, so the boxes do not jump
local freeze_cache = { key = nil, cc = nil, stats = nil }

local function Main()
    if not ctx or not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
        return
    end

    PushFont(ctx, font, 13)
    UI.ApplyWindowStyle(ctx)

    r.ImGui_SetNextWindowSize(ctx, initial_item_width or 1000, 600, r.ImGui_Cond_FirstUseEver())
    local flags = r.ImGui_WindowFlags_None()
    if first_auto_resize then flags = flags | r.ImGui_WindowFlags_AlwaysAutoResize() end

    -- «Язычок» раздока (треугольник в углу окна, которым виджет вытягивают из дока)
    -- ReaImGui рисует цветом ImGuiCol_Button прямо внутри Begin(). Убрать его нельзя
    -- (нет доступа к флагам dock node), поэтому на время Begin() красим кнопочные
    -- цвета в цвет фона окна — треугольник сливается с фоном.
    local window_bg = Theme.getMainWindowTransportBackground()
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), window_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), window_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), window_bg)

    local visible, open = r.ImGui_Begin(ctx, 'Item Properties', true, flags)

    r.ImGui_PopStyleColor(ctx, 3)

    -- Край окна: фон взят из темы REAPER и сливается с ней, а штатная рамка ImGui-окна
    -- (WindowBorderSize/Col_Border) у ReaImGui не читается. Поэтому рисуем линию сами —
    -- 2 px по периметру окна, со скруглением фона. Цвет — Theme.getMainWindowBorder().
    do
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local wx, wy = r.ImGui_GetWindowPos(ctx)
        local ww, wh = r.ImGui_GetWindowSize(ctx)
        local x1, y1 = math.floor(wx) + 1, math.floor(wy) + 1
        local x2, y2 = math.floor(wx + ww) - 1, math.floor(wy + wh) - 1
        r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2,
            Theme.getMainWindowBorder(), 7, r.ImGui_DrawFlags_None(), 2)
    end

    if r.ImGui_IsWindowAppearing(ctx) then first_auto_resize = false end

    if visible then
        Track.PollLastTouchedParam()
    end

    local hover_flags = r.ImGui_HoveredFlags_ChildWindows()
                      | r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem()
                      | r.ImGui_HoveredFlags_AllowWhenBlockedByPopup()
    local window_hovered = visible and r.ImGui_IsWindowHovered(ctx, hover_flags)

    local suppress_rclick_item_track_for_fxsnap_row = false
    if fip_fxsnap_row_screen_rect.valid and r.ImGui_IsMouseClicked(ctx, 1) then
        local R = fip_fxsnap_row_screen_rect
        local mx, my = r.ImGui_GetMousePos(ctx)
        if mx >= R.x1 and mx <= R.x2 and my >= R.y1 and my <= R.y2 then
            suppress_rclick_item_track_for_fxsnap_row = true
        end
    end

    local right_clicked_in_widget = visible
        and r.ImGui_IsMouseClicked(ctx, 1)
        and window_hovered
        and not suppress_rclick_item_track_for_fxsnap_row

    -- Which panel to show: the extension mirrors REAPER's focus and selections; the right-click toggle moves the focus.
    local context = Utils.ParseKeyValues(r.FIP_ContextUpdateStr('', right_clicked_in_widget and 2 or 0))

    if visible then
        local fip_fxsnap_strip_committed = false

        local items_count = tonumber(context.items) or 0
        local items_sig = (r.APIExists and r.APIExists("FIP_GetSelectedItemsSignatureStr"))
            and (r.FIP_GetSelectedItemsSignatureStr("", 0) or "")
            or ""
        local items = {}
        if items_count == 1 then
            local it = r.GetSelectedMediaItem(0, 0)
            if it then items[1] = it end
        end
        local tracks = {}
        for i = 0, (tonumber(context.tracks) or 0) - 1 do
            local tr = r.FIP_ContextGetTrack('', i)
            if tr then tracks[#tracks + 1] = tr end
        end
        local items_changed = items_sig ~= last_items_sig
        last_items_sig = items_sig

        local proj_cc = r.GetProjectStateChangeCount(0)
        local any_pitch_drag_active = UI.IsAnyPitchDragActive and UI.IsAnyPitchDragActive() or false
        local freeze_sel_key = GetTrackSelectionKey(tracks)
        if freeze_cache.key ~= freeze_sel_key or freeze_cache.cc ~= proj_cc or freeze_cache.stats == nil then
            freeze_cache.stats = Track.GetFreezeStats(tracks)
            freeze_cache.key, freeze_cache.cc = freeze_sel_key, proj_cc
        end
        local freeze_stats = freeze_cache.stats

        local props = nil
        if context.ctx == 'track' then
            props = { take_type = 'Track', name = 'Selected Track' }
        elseif context.ctx == 'item' then
            props = (any_pitch_drag_active and last_item_props) or Item.GetAggregatedProps()
            last_item_props = props
        end

        local any_value_input_active =
            pitch_value_edit.active or mt_value_edit.active or track_items_pitch_value_edit.active
            or hp_value_edit.active or lp_value_edit.active or rate_value_edit.active or bpm_value_edit.active

        if items_changed then
            if not any_value_input_active and not any_pitch_drag_active and value_input_reset_grace_frames <= 0 then
                pitch_value_edit.active = false
                pitch_value_edit.want_focus = false
                mt_value_edit.active = false
                mt_value_edit.want_focus = false
                track_items_pitch_value_edit.active = false
                track_items_pitch_value_edit.want_focus = false
                hp_value_edit.active = false
                hp_value_edit.want_focus = false
                lp_value_edit.active = false
                lp_value_edit.want_focus = false
                rate_value_edit.active = false
                rate_value_edit.want_focus = false
                bpm_value_edit.active = false
                bpm_value_edit.want_focus = false
                reset_multi_item_pitch_session()
                reset_midi_item_pitch_session()
                if r.APIExists and r.APIExists("FIP_ResetSelectedItemsPitchDeltaVal") then
                    r.FIP_ResetSelectedItemsPitchDeltaVal("", 0)
                end
            end
            if value_input_reset_grace_frames > 0 then
                value_input_reset_grace_frames = value_input_reset_grace_frames - 1
            end
        end

        local item_count = items_count
        if item_count > 1000 then
            props = { take_type = 'Warning', name = string.format('Too many items (%d). Performance may be affected.', item_count) }
        end

        -- Automation context: the extension draws its panel (fip_envelope_panel.cpp). Its crumb in the lane context
        -- selects the owner track and shows the track panel; its tooltip goes to the styled tooltip. pcall: if this
        -- REAPER / ReaImGui cannot pass the context to an extension, the panel is missing but the widget keeps running.
        local env = {}
        if context.ctx == 'envelope' and r.APIExists('FIP_EnvelopePanel') then
            local ok, res = pcall(r.FIP_EnvelopePanel, ctx, UI.GetIconFont(), 0)
            env = Utils.ParseKeyValues(ok and res or '')
            UI.SetPendingTooltipText(env.tooltip)
            if env.track == '1' then r.FIP_ContextShowTrack('', 1) end
        end

        if env.drawn == '1' then
            -- the automation context panel is drawn
        elseif not props and item_count == 0 and #tracks == 0 then
            r.ImGui_Text(ctx, 'No items or tracks selected')
        elseif props then
            props.sel_item_count = item_count
            local color, _, bar_rr, bar_gg, bar_bb, bar_fg = UI.GetBarColorAndUseBlack(items, tracks, props)
            local bar_color = color
            local G = UI.GLYPH

            -- Item mode header data from the extension: item kind, whether the row has controls, crumb track.
            local item_header = nil
            if props.take_type ~= 'Track' then
                if r.APIExists and r.APIExists('FIP_ItemHeaderGetStateStr') then
                    item_header = Utils.ParseKeyValues(r.FIP_ItemHeaderGetStateStr('', 0))
                    item_header.editable = item_header.editable == '1'
                    item_header.tracks = tonumber(item_header.tracks) or 0
                    item_header.track_color = tonumber(item_header.track_color) or 0
                else
                    local tt = props.take_type
                    local kind = (tt == 'MIDI' and 'midi') or (tt == 'Empty' and 'empty') or (tt == 'Mult' and 'mixed') or 'audio'
                    item_header = { kind = kind, editable = kind ~= 'empty', tracks = 0, track_color = 0 }
                end
            end

            -- Crumb click: select the items' track and switch the inspector to track mode.
            local function show_items_track()
                r.FIP_ContextShowTrack('', 0)
            end

            r.ImGui_BeginGroup(ctx)

            local changed, new_name
            if props.take_type == 'Track' then
                -- Track: fader icon (dot = the track has automation, click = envelope list), color spine with
                -- the number, neutral name field.
                local automation = (r.APIExists and r.APIExists('FIP_TrackAutomationGetStateStr'))
                    and Utils.ParseKeyValues(r.FIP_TrackAutomationGetStateStr('', 0)) or nil
                local icon_clicked, icon_hovered = UI.HeaderIconSlot(ctx, G.track, automation and {
                    clickable = true, badge = UI.AutomationBadge(automation),
                })
                local icon_x = r.ImGui_GetItemRectMin(ctx)
                local _, icon_y2 = r.ImGui_GetItemRectMax(ctx)
                local spine_text = tostring(#tracks) .. '×'
                if #tracks == 1 and r.ValidatePtr(tracks[1], 'MediaTrack*') then
                    spine_text = tostring(math.floor(r.GetMediaTrackInfo_Value(tracks[1], 'IP_TRACKNUMBER')))
                end
                -- Number tab + name field are one block: the field starts under the tab, which is drawn on
                -- top afterwards and covers the field's left rounding.
                local tab_x, tab_y = r.ImGui_GetCursorScreenPos(ctx)
                r.ImGui_SetCursorScreenPos(ctx, tab_x + UI.HEADER_SPINE_W - UI.HEADER_TAB_OVERLAP, tab_y)
                UI.PushBarForegroundText(ctx, Theme.get('text_white_soft'))
                if #tracks > 1 then
                    local hint_text = 'Multiple Tracks (' .. #tracks .. '):'
                    changed, new_name = UI.MultiItemInput(ctx, '##MultipleTracks', hint_text, '', -1, Theme.get('gray_42'), UI.HEADER_JOINED_PAD_X)
                    if changed and new_name ~= '' then
                        for _, tr in ipairs(tracks) do
                            if tr and r.ValidatePtr(tr, 'MediaTrack*') then
                                Track.SetTrackName(tr, new_name)
                            end
                        end
                        props.name = new_name
                    end
                elseif #tracks == 1 and r.ValidatePtr(tracks[1], 'MediaTrack*') then
                    local tname = Track.GetTrackName(tracks[1])
                    local current_name = (props.name and props.name ~= 'Selected Track') and props.name or (tname or '')
                    changed, new_name = UI.StyledInput(ctx, '##TrackName', current_name, -1, Theme.get('gray_42'), UI.HEADER_JOINED_PAD_X)
                    if changed and new_name ~= current_name then
                        Track.SetTrackName(tracks[1], new_name)
                        props.name = new_name
                    end
                else
                    r.ImGui_Text(ctx, 'No tracks selected')
                end
                UI.PopBarForegroundText(ctx)
                UI.DrawHeaderTab(ctx, tab_x, tab_y, spine_text, bar_color, bar_fg)
                if automation then
                    UI.TrackAutomationPopup(ctx, { x = icon_x, y = icon_y2 + 2, hovered = icon_hovered,
                        clicked = icon_clicked, has_envs = (tonumber(automation.envs) or 0) > 0 })
                end
            else
                -- Item: kind icon, the item's track (spine + crumb), colored name bar with the kind texture.
                UI.HeaderIconSlot(ctx, G[item_header.kind] or G.audio)
                if item_header.tracks == 1 then
                    local tr_r, tr_g, tr_b = 64, 64, 64
                    if item_header.track_color ~= 0 then
                        tr_r, tr_g, tr_b = r.ColorFromNative(item_header.track_color)
                    end
                    local tr_fg = UI.BarForegroundPick(tr_r, tr_g, tr_b)
                    if UI.HeaderTrackBlock(ctx, item_header.track_num or '', Theme.rgba(tr_r, tr_g, tr_b, 255), tr_fg,
                        item_header.track_name) then
                        show_items_track()
                    end
                elseif item_header.tracks > 1 then
                    if UI.HeaderTrackBlock(ctx, tostring(item_header.tracks) .. '×', Theme.get('gray_64'),
                        Theme.get('text_white_soft'), item_header.tracks .. ' tracks') then
                        show_items_track()
                    end
                end
                UI.PushBarForegroundText(ctx, bar_fg)
                local bar_text = props.name or ''
                if props.take_type == 'Empty' then
                    -- An item without takes is named by the first line of its notes (what the arrange shows).
                    -- The name is written once, when the field is left: written per key, a cleared field would
                    -- make the next notes line the first one, and the next key would overwrite it.
                    local notes = item_header.notes or ''
                    local value = empty_name_edit.text or notes
                    local hint = item_count > 1 and ('Multiple Items (' .. item_count .. ')') or 'Empty item'
                    local edited, typed, left = UI.MultiItemInput(ctx, '##EmptyItemName', hint, value, -1, bar_color)
                    if edited then
                        empty_name_edit.sig = empty_name_edit.sig or items_sig
                        empty_name_edit.text = typed
                    end
                    if left then
                        local name = empty_name_edit.text
                        if name and name ~= notes and empty_name_edit.sig == items_sig
                            and r.APIExists and r.APIExists('FIP_SetSelectedItemsName') then
                            Utils.with_undo('Rename empty item', function() r.FIP_SetSelectedItemsName(name, 0) end)
                        end
                        empty_name_edit.text, empty_name_edit.sig = nil, nil
                    end
                    bar_text = value ~= '' and value or hint
                elseif item_count > 1 then
                    local hint_text = 'Multiple Items (' .. item_count .. '):'
                    if props.name and not props.name:match('^Multiple Items') then
                        hint_text = 'Multiple Items (' .. item_count .. '): ' .. props.name
                    end
                    bar_text = hint_text
                    changed, new_name = UI.MultiItemInput(ctx, '##MultipleItems', hint_text, '', -1, bar_color)
                    if new_name and new_name ~= '' then bar_text = new_name end -- the texture follows what is typed
                    if changed and new_name ~= '' then
                        if r.APIExists and r.APIExists("FIP_SetSelectedItemsName") then
                            r.FIP_SetSelectedItemsName(new_name, 0)
                        else
                            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsName not available\n")
                        end
                        props.name = new_name
                    end
                else
                    changed, new_name = UI.StyledInput(ctx, '##ObjectName', props.name or '', -1, bar_color)
                    bar_text = new_name or bar_text
                    if changed and new_name ~= (props.name or '') then
                        if r.APIExists and r.APIExists("FIP_SetSelectedItemsName") then
                            r.FIP_SetSelectedItemsName(new_name, 0)
                        else
                            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsName not available\n")
                        end
                        props.name = new_name
                    end
                end
                UI.PopBarForegroundText(ctx)
                UI.DrawItemTexture(ctx, item_header.kind, bar_text, (bar_fg & ~0xFF) | 0x50)
            end

            r.ImGui_EndGroup(ctx)

            if IsTrackSelection(props) then
                r.ImGui_BeginGroup(ctx)
                local single_track = (#tracks >= 1 and r.ValidatePtr(tracks[1], 'MediaTrack*')) and tracks[1] or nil
                if #tracks ~= 1 then
                    single_track = nil
                end
                local has_track_instrument = single_track and Track.HasInstrument(single_track) or false
                local is_track_instrument_open = has_track_instrument and Track.IsInstrumentUIOpen(single_track) or false
                -- Instrument under the header icon: the same place as 'i' in item mode.
                UI.RenderTrackInstrumentButton(ctx, single_track, has_track_instrument,
                    is_track_instrument_open, function()
                    Track.OpenInstrumentUI(single_track)
                end)
                -- No second slot here (REAPER has no track notes): the row follows the instrument button directly.
                UI.Separator(ctx)
                if single_track and #tracks == 1 then
                    local ltp = Track.GetLastTouchedParamInfo(single_track)
                    UI.RenderLastTouchedParamBox(ctx, ltp, font,
                        function(new_val)
                            if not ltp then return end
                            Track.BeginLastTouchedParamEdit()
                            Track.SetLastTouchedParamValue(single_track, ltp.fxidx, ltp.parm, new_val)
                        end,
                        function()
                            Track.EndLastTouchedParamEdit()
                        end,
                        function()
                            if ltp then
                                Track.ShowLastTouchedParamEnvelope(single_track, ltp.fxidx, ltp.parm)
                            end
                        end)
                    UI.Separator(ctx)
                end
                if single_track and #tracks == 1 and r.APIExists and r.APIExists('FIP_TrackFXSnap_GetSlotCountVal') then
                    local snap_tt_api = (r.APIExists and r.APIExists('FIP_TrackFXSnap_GetSlotFxTooltipStr')) or false
                    local track_guid_tt = (snap_tt_api and single_track and r.GetTrackGUID(single_track)) or nil

                    local function queue_snap_slot_tt(btn_idx)
                        if not (snap_tt_api and track_guid_tt) then return end
                        UI.QueueStyledTooltipDelayedGeneric(ctx,
                            'fip_fxsnap_tt_' .. track_guid_tt .. '_' .. tostring(btn_idx),
                            function()
                                return get_fx_snap_slot_tooltip_lines(single_track, btn_idx)
                            end,
                            1.0,
                            r.ImGui_IsItemHovered(ctx))
                    end

                    local max_snap = 6
                    local n_snap = fip_api_double(r.FIP_TrackFXSnap_GetSlotCountVal(single_track, '', 0)) or -1
                    local sel_slot = fip_api_double(r.FIP_TrackFXSnap_GetSelectedSlotVal(single_track, '', 0)) or -1
                    local letter_count = math.min((n_snap >= 2) and n_snap or 1, max_snap)
                    local at_snap_limit = (n_snap >= max_snap)
                    r.ImGui_PushID(ctx, string.format('fip_fxsnap_strip_%d_%d', math.floor(n_snap + 0.5), math.floor(sel_slot + 0.5)))
                    r.ImGui_BeginGroup(ctx)
                    for si = 1, letter_count do
                        local btn_i = si
                        if btn_i > 1 then
                            r.ImGui_SameLine(ctx, 0, 4)
                        end
                        local label = string.char(64 + btn_i)
                        local can_recall = (n_snap >= 2)
                        local is_active = can_recall and (sel_slot == btn_i)
                        if can_recall then
                            if is_active then
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), bar_fg)
                                local c0, ch, ca = UI.BarColorButtonVariants(bar_rr, bar_gg, bar_bb)
                                UI.ColoredButton(ctx, label, 24, c0, ch, ca, function()
                                    r.FIP_TrackFXSnap_SelectSlot(single_track, btn_i + 0.0, 0)
                                end)
                                r.ImGui_PopStyleColor(ctx, 1)
                                queue_snap_slot_tt(btn_i)
                                fip_try_fxsnap_slot_context_menu(ctx, btn_i + 0.0, single_track)
                            else
                                UI.StyledButton(ctx, label, 24, function()
                                    r.FIP_TrackFXSnap_SelectSlot(single_track, btn_i + 0.0, 0)
                                end)
                                queue_snap_slot_tt(btn_i)
                                fip_try_fxsnap_slot_context_menu(ctx, btn_i + 0.0, single_track)
                            end
                        else
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray'))
                            UI.ColoredButton(ctx, label, 24, Theme.get('gray_42'), Theme.get('gray_58'),
                                Theme.get('gray_74'), function() end)
                            r.ImGui_PopStyleColor(ctx, 1)
                            queue_snap_slot_tt(btn_i)
                        end
                    end
                    r.ImGui_SameLine(ctx, 0, 6)
                    if at_snap_limit then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray'))
                        UI.ColoredButton(ctx, '+', 24, Theme.get('gray_42'), Theme.get('gray_58'),
                            Theme.get('gray_74'), function() end)
                        r.ImGui_PopStyleColor(ctx, 1)
                    else
                        UI.StyledButton(ctx, '+', 24, function()
                            r.FIP_TrackFXSnap_AddSnapshotSlot(single_track, '', 0)
                        end)
                    end
                    r.ImGui_EndGroup(ctx)
                    do
                        local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
                        local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
                        fip_fxsnap_row_screen_rect = {
                            valid = true,
                            x1 = min_x,
                            y1 = min_y,
                            x2 = max_x,
                            y2 = max_y
                        }
                        fip_fxsnap_strip_committed = true
                    end
                    r.ImGui_PopID(ctx)
                    UI.Separator(ctx)
                end
                local current_val = 0
                local has_mt_fx = false
                if single_track then
                    local mt_state = Track.GetMidiTransposeState(single_track)
                    if mt_state.exists then
                        current_val = mt_state.semitones or 0
                        has_mt_fx = true
                    end
                end
                local mt_label = 'MIDI Input:'
                local mt_label_w = select(1, r.ImGui_CalcTextSize(ctx, mt_label))
                if not mt_value_edit.active then
                    local mt_changed, mt_new, mt_deactivated, mt_activated = UI.VerticalPitchControl(ctx, mt_label, current_val, 50, 0.1, -48, 48, '%.0f st', function()
                        if single_track then
                            local fx_idx = Track.FindMidiTransposeFX(single_track)
                            if fx_idx ~= nil then
                                Track.MidiTransposeRemove(single_track, 3)
                            else
                                Track.MidiTransposeEdit(single_track, 0, 3)
                            end
                        end
                    end, mt_label_w + 8, nil, has_mt_fx, nil, nil, true, true, function()
                        mt_value_edit.active = true
                        mt_value_edit.text = string.format('%.0f', math.floor((current_val or 0) + 0.5))
                        mt_value_edit.want_focus = true
                        value_input_reset_grace_frames = 2
                    end, UI.GetItemPitchTooltipLines(false), true)
                    if single_track then
                        if mt_activated and has_mt_fx then
                            Track.MidiTransposeEdit(single_track, mt_new, 0)
                        end
                        if mt_changed and not mt_activated then
                            if not has_mt_fx then
                                Track.MidiTransposeEdit(single_track, mt_new, 0)
                            else
                                Track.MidiTransposeEdit(single_track, mt_new, 1)
                            end
                        end
                        if mt_deactivated and (has_mt_fx or mt_changed) then
                            Track.MidiTransposeEdit(single_track, mt_new, 2)
                        end
                    end
                else
                    UI.StyledResetButton(ctx, mt_label, mt_label_w + 8, has_mt_fx, function()
                        mt_value_edit.active = false
                        mt_value_edit.want_focus = false
                        if single_track then
                            local fx_idx = Track.FindMidiTransposeFX(single_track)
                            if fx_idx ~= nil then
                                Track.MidiTransposeRemove(single_track, 3)
                            else
                                Track.MidiTransposeEdit(single_track, 0, 3)
                            end
                        end
                    end)
                    r.ImGui_SameLine(ctx, 0, 2)
                    r.ImGui_SetNextItemWidth(ctx, 50)
                    if mt_value_edit.want_focus then
                        r.ImGui_SetKeyboardFocusHere(ctx)
                        mt_value_edit.want_focus = false
                    end
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_42'))
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), Theme.get('gray_74'))
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 4)
                    local input_flags = r.ImGui_InputTextFlags_CharsDecimal()
                                      | r.ImGui_InputTextFlags_EnterReturnsTrue()
                                      | r.ImGui_InputTextFlags_AutoSelectAll()
                    local mt_submitted, new_text = r.ImGui_InputText(ctx, '##MidiTransposeValue', mt_value_edit.text, input_flags)
                    mt_value_edit.text = new_text
                    local mt_d = Utils.ReturnFocusOnDeactivation(ctx)
                    r.ImGui_PopStyleVar(ctx, 2)
                    r.ImGui_PopStyleColor(ctx, 2)
                    UI.QueueStyledTooltipDelayed(ctx, 'fip_mt_input', UI.GetItemPitchTooltipLines(false), 1.0)
                    if mt_submitted or mt_d then
                        local parsed = tonumber(((mt_value_edit.text or ''):gsub(',', '.')))
                        if parsed then
                            if parsed < -48 then parsed = -48 end
                            if parsed > 48 then parsed = 48 end
                            if single_track and (has_mt_fx or math.abs(parsed) > 0.0001) then
                                Track.MidiTransposeEdit(single_track, parsed, 0)
                                Track.MidiTransposeEdit(single_track, parsed, 2)
                            end
                        end
                        mt_value_edit.active = false
                    end
                end
                UI.Separator(ctx)
                -- HP/LP filters: one row, thin font, compact; width = content only (no extra space after LP)
                local freq_box_w = select(1, r.ImGui_CalcTextSize(ctx, "999 Hz")) + 16
                local FILTER_BLOCK_W = 32 + 2 + 4 + freq_box_w + 8 + 32 + 2 + 4 + freq_box_w + 8  -- HP btn + : + FreqBox + gap + LP btn + : + FreqBox + pad
                local FILTER_BLOCK_H = 22
                local hp_state = single_track and Track.GetHPFilterState(single_track) or nil
                local lp_state = single_track and Track.GetLPFilterState(single_track) or nil
                local hp_idx = (hp_state and hp_state.exists) and hp_state.fxidx or nil
                local lp_idx = (lp_state and lp_state.exists) and lp_state.fxidx or nil
                r.ImGui_PushID(ctx, "TrackFilters")
                PushFont(ctx, font, 12)
                r.ImGui_BeginChild(ctx, "##FilterBlock", FILTER_BLOCK_W, FILTER_BLOCK_H, r.ImGui_ChildFlags_None())
                if single_track then
                    local sr = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 44100
                    local fmax = math.min(sr * 0.499, 20000)
                    local hp_norm = 0
                    local lp_norm = 1
                    local hp_24 = true
                    local lp_24 = true
                    if hp_state and hp_state.exists then
                        hp_norm = hp_state.norm or 0
                        hp_24 = hp_state.slope24
                    end
                    if lp_state and lp_state.exists then
                        lp_norm = lp_state.norm or 1
                        lp_24 = lp_state.slope24
                    end
                    local hp_freq = Track.NormToFreq(hp_norm)
                    local lp_freq = Track.NormToFreq(lp_norm)
                    local hp_label = hp_24 and "HP4" or "HP2"
                    local lp_label = lp_24 and "LP4" or "LP2"
                    -- Hue from norm like JSFX: hue = norm * 0.78, L=0.75, S=1 -> RGB
                    local function freq_norm_to_color(norm)
                        norm = math.max(0, math.min(1, norm or 0))
                        local h = norm * 0.78
                        local L, S = 0.75, 1
                        local q = L < 0.5 and (L * (1 + S)) or (L + S - L * S)
                        local p = 2 * L - q
                        local function hue2rgb(t)
                            if t < 0 then t = t + 1 elseif t > 1 then t = t - 1 end
                            if t < 0.166667 then return p + (q - p) * 6 * t end
                            if t < 0.5 then return q end
                            if t < 0.666667 then return p + (q - p) * (0.666667 - t) * 6 end
                            return p
                        end
                        local rv = hue2rgb(h + 0.333333)
                        local gv = hue2rgb(h)
                        local bv = hue2rgb(h - 0.333333)
                        return Theme.rgba(rv * 255, gv * 255, bv * 255, 255)
                    end
                    -- Display in box: "20k", "1.5k", "999" (no "Hz": the k values have no unit either)
                    local function format_freq_display(f)
                        if f >= 10000 then return string.format("%.0fk", f / 1000) end
                        if f >= 1000 then return string.format("%.1fk", f / 1000) end
                        return string.format("%.0f", f)
                    end
                    local function hp_display_fn(norm) return format_freq_display(Track.NormToFreq(norm)) end
                    local function lp_display_fn(norm) return format_freq_display(Track.NormToFreq(norm)) end
                    -- HP: label (slope) + numeric box, phase-based undo via C++
                    r.ImGui_PushID(ctx, "HP")
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_white_soft'))
                    UI.StyledButton(ctx, hp_label .. "##HP", 32, function()
                        Track.FilterEdit(single_track, 0, hp_norm, not hp_24, 3)
                    end)
                    r.ImGui_PopStyleColor(ctx, 1)
                    r.ImGui_SameLine(ctx, 0, 0)
                    r.ImGui_Text(ctx, ":")
                    r.ImGui_SameLine(ctx, 0, 4)
                    if not hp_value_edit.active then
                        local hp_changed, hp_new_norm, hp_activated, hp_deactivated, hp_alt_clicked = UI.FreqBox(ctx, "##HPFreq", hp_norm, freq_box_w, freq_norm_to_color(hp_norm), false, hp_display_fn, 0)
                        UI.QueueStyledTooltipDelayed(ctx, 'fip_hp_freq', UI.GetFilterFreqTooltipLines('HP'), 1.0)
                        if hp_alt_clicked then
                            hp_value_edit.active = true
                            hp_value_edit.text = UI.FormatFrequencyInput(Track.NormToFreq(hp_norm))
                            hp_value_edit.want_focus = true
                            value_input_reset_grace_frames = 2
                        elseif hp_activated and hp_changed and hp_idx ~= nil then
                            Track.FilterRemove(single_track, 0, 3)
                        elseif hp_activated and hp_idx ~= nil then
                            Track.FilterEdit(single_track, 0, hp_norm, hp_24, 0)
                        end
                        if hp_changed and not hp_activated then
                            local hp_new_freq = Track.NormToFreq(hp_new_norm)
                            if hp_idx == nil and hp_new_freq > 20 then
                                Track.FilterEdit(single_track, 0, hp_new_norm, hp_24, 0)
                            elseif hp_idx ~= nil then
                                Track.FilterEdit(single_track, 0, hp_new_norm, hp_24, 1)
                            end
                        end
                        if hp_deactivated and hp_idx ~= nil and not (hp_activated and hp_changed) then
                            local hp_end_freq = Track.NormToFreq(hp_new_norm)
                            if hp_end_freq <= 20 then
                                Track.FilterRemove(single_track, 0, 2)
                            else
                                Track.FilterEdit(single_track, 0, hp_new_norm, hp_24, 2)
                            end
                        end
                    else
                        r.ImGui_SetNextItemWidth(ctx, freq_box_w)
                        if hp_value_edit.want_focus then
                            r.ImGui_SetKeyboardFocusHere(ctx)
                            hp_value_edit.want_focus = false
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_42'))
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), Theme.get('gray_74'))
                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 2)
                        local input_flags = r.ImGui_InputTextFlags_CharsDecimal()
                                          | r.ImGui_InputTextFlags_EnterReturnsTrue()
                                          | r.ImGui_InputTextFlags_AutoSelectAll()
                        local hp_submitted, new_text = r.ImGui_InputText(ctx, '##HPFreqInput', hp_value_edit.text, input_flags)
                        hp_value_edit.text = new_text
                        local hp_d = Utils.ReturnFocusOnDeactivation(ctx)
                        r.ImGui_PopStyleVar(ctx, 2)
                        r.ImGui_PopStyleColor(ctx, 2)
                        UI.QueueStyledTooltipDelayed(ctx, 'fip_hp_freq', UI.GetFilterFreqTooltipLines('HP'), 1.0)
                        if hp_submitted or hp_d then
                            local parsed_hz = UI.ParseFrequencyInput(hp_value_edit.text, 20, fmax)
                            if parsed_hz then
                                if parsed_hz <= 20 then
                                    if hp_idx ~= nil then
                                        Track.FilterRemove(single_track, 0, 3)
                                    end
                                else
                                    local new_norm = Track.FreqToNorm(parsed_hz)
                                    Track.FilterEdit(single_track, 0, new_norm, hp_24, 0)
                                    Track.FilterEdit(single_track, 0, new_norm, hp_24, 2)
                                end
                            end
                            hp_value_edit.active = false
                        end
                    end
                    r.ImGui_PopID(ctx)
                    -- LP: same pattern, inverted boundary (20kHz = off)
                    r.ImGui_SameLine(ctx, 0, 8)
                    r.ImGui_PushID(ctx, "LP")
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_white_soft'))
                    UI.StyledButton(ctx, lp_label .. "##LP", 32, function()
                        Track.FilterEdit(single_track, 1, lp_norm, not lp_24, 3)
                    end)
                    r.ImGui_PopStyleColor(ctx, 1)
                    r.ImGui_SameLine(ctx, 0, 0)
                    r.ImGui_Text(ctx, ":")
                    r.ImGui_SameLine(ctx, 0, 4)
                    if not lp_value_edit.active then
                        local lp_changed, lp_new_norm, lp_activated, lp_deactivated, lp_alt_clicked = UI.FreqBox(ctx, "##LPFreq", lp_norm, freq_box_w, freq_norm_to_color(lp_norm), true, lp_display_fn, 1)
                        UI.QueueStyledTooltipDelayed(ctx, 'fip_lp_freq', UI.GetFilterFreqTooltipLines('LP'), 1.0)
                        if lp_alt_clicked then
                            lp_value_edit.active = true
                            lp_value_edit.text = UI.FormatFrequencyInput(Track.NormToFreq(lp_norm))
                            lp_value_edit.want_focus = true
                            value_input_reset_grace_frames = 2
                        elseif lp_activated and lp_changed and lp_idx ~= nil then
                            Track.FilterRemove(single_track, 1, 3)
                        elseif lp_activated and lp_idx ~= nil then
                            Track.FilterEdit(single_track, 1, lp_norm, lp_24, 0)
                        end
                        if lp_changed and not lp_activated then
                            local lp_new_freq = Track.NormToFreq(lp_new_norm)
                            if lp_idx == nil and lp_new_freq < fmax then
                                Track.FilterEdit(single_track, 1, lp_new_norm, lp_24, 0)
                            elseif lp_idx ~= nil then
                                Track.FilterEdit(single_track, 1, lp_new_norm, lp_24, 1)
                            end
                        end
                        if lp_deactivated and lp_idx ~= nil and not (lp_activated and lp_changed) then
                            local lp_end_freq = Track.NormToFreq(lp_new_norm)
                            if lp_end_freq >= fmax then
                                Track.FilterRemove(single_track, 1, 2)
                            else
                                Track.FilterEdit(single_track, 1, lp_new_norm, lp_24, 2)
                            end
                        end
                    else
                        r.ImGui_SetNextItemWidth(ctx, freq_box_w)
                        if lp_value_edit.want_focus then
                            r.ImGui_SetKeyboardFocusHere(ctx)
                            lp_value_edit.want_focus = false
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_42'))
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), Theme.get('gray_74'))
                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 2)
                        local input_flags = r.ImGui_InputTextFlags_CharsDecimal()
                                          | r.ImGui_InputTextFlags_EnterReturnsTrue()
                                          | r.ImGui_InputTextFlags_AutoSelectAll()
                        local lp_submitted, new_text = r.ImGui_InputText(ctx, '##LPFreqInput', lp_value_edit.text, input_flags)
                        lp_value_edit.text = new_text
                        local lp_d = Utils.ReturnFocusOnDeactivation(ctx)
                        r.ImGui_PopStyleVar(ctx, 2)
                        r.ImGui_PopStyleColor(ctx, 2)
                        UI.QueueStyledTooltipDelayed(ctx, 'fip_lp_freq', UI.GetFilterFreqTooltipLines('LP'), 1.0)
                        if lp_submitted or lp_d then
                            local parsed_hz = UI.ParseFrequencyInput(lp_value_edit.text, 20, fmax)
                            if parsed_hz then
                                if parsed_hz >= fmax then
                                    if lp_idx ~= nil then
                                        Track.FilterRemove(single_track, 1, 3)
                                    end
                                else
                                    local new_norm = Track.FreqToNorm(parsed_hz)
                                    Track.FilterEdit(single_track, 1, new_norm, lp_24, 0)
                                    Track.FilterEdit(single_track, 1, new_norm, lp_24, 2)
                                end
                            end
                            lp_value_edit.active = false
                        end
                    end
                    r.ImGui_PopID(ctx)
                else
                    r.ImGui_Text(ctx, "HP / LP")
                end
                r.ImGui_EndChild(ctx)
                r.ImGui_PopFont(ctx)
                r.ImGui_PopID(ctx)
                UI.Separator(ctx)
                local has_track_pitch_api = (r.APIExists and r.APIExists("FIP_GetSelectedTracksItemsPitchStatsStr"))
                    and (r.APIExists and r.APIExists("FIP_AddSelectedTracksItemsPitchVal"))
                    and (r.APIExists and r.APIExists("FIP_ResetSelectedTracksItemsPitchVal"))
                local track_item_count, items_pitch, items_modified, items_mixed = 0, 0, false, false
                if has_track_pitch_api and #tracks > 0 then
                    track_item_count, items_pitch, items_modified, items_mixed = pitch_module.GetSelectedTracksItemsPitchInfo()
                end
                local has_track_items = has_track_pitch_api and (track_item_count > 0)
                if not has_track_items then
                    r.ImGui_BeginDisabled(ctx, true)
                end
                local it_label = 'Track Items Transpose'
                local it_label_w = select(1, r.ImGui_CalcTextSize(ctx, it_label))
                local it_changed, it_new, it_deactivated = false, items_pitch, false
                if not track_items_pitch_value_edit.active then
                    it_changed, it_new, it_deactivated = UI.VerticalPitchControl(ctx, it_label, items_pitch, 50, 0.1, -96, 96, '%.0f st', function()
                        if has_track_items then
                            pitch_module.HandleSelectedTracksItemsPitchReset()
                        end
                    end, it_label_w + 8, nil, items_modified, items_mixed, has_track_items and track_item_count or 0, nil, false, function()
                        track_items_pitch_value_edit.active = true
                        track_items_pitch_value_edit.text = string.format('%.0f', math.floor((items_pitch or 0) + 0.5))
                        track_items_pitch_value_edit.want_focus = true
                        value_input_reset_grace_frames = 2
                    end, UI.GetItemPitchTooltipLines(false), true)
                else
                    UI.StyledResetButton(ctx, it_label, it_label_w + 8, items_modified, function()
                        track_items_pitch_value_edit.active = false
                        track_items_pitch_value_edit.want_focus = false
                        if has_track_items then
                            pitch_module.HandleSelectedTracksItemsPitchReset()
                        end
                    end, false, items_mixed)
                    if has_track_items and track_item_count > 0 then
                        UI.ExtendAggHoverRegion(ctx)
                    end
                    r.ImGui_SameLine(ctx, 0, 2)
                    r.ImGui_SetNextItemWidth(ctx, 50)
                    if track_items_pitch_value_edit.want_focus then
                        r.ImGui_SetKeyboardFocusHere(ctx)
                        track_items_pitch_value_edit.want_focus = false
                    end
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_42'))
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), Theme.get('gray_74'))
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 4)
                    local input_flags = r.ImGui_InputTextFlags_CharsDecimal()
                                      | r.ImGui_InputTextFlags_EnterReturnsTrue()
                                      | r.ImGui_InputTextFlags_AutoSelectAll()
                    local it_submitted, new_text = r.ImGui_InputText(ctx, '##TrackItemsPitchValue', track_items_pitch_value_edit.text, input_flags)
                    track_items_pitch_value_edit.text = new_text
                    local it_d = Utils.ReturnFocusOnDeactivation(ctx)
                    r.ImGui_PopStyleVar(ctx, 2)
                    r.ImGui_PopStyleColor(ctx, 2)
                    if has_track_items and track_item_count > 0 then
                        UI.DrawAggregationOutline(ctx, nil, 4, 0)
                        UI.ExtendAggHoverRegion(ctx)
                    end
                    UI.QueueStyledTooltipDelayed(ctx, 'fip_track_items_pitch_input', UI.GetItemPitchTooltipLines(false), 1.0)
                    if it_submitted or it_d then
                        local parsed = tonumber(((track_items_pitch_value_edit.text or ''):gsub(',', '.')))
                        if parsed then
                            if parsed < -96 then parsed = -96 end
                            if parsed > 96 then parsed = 96 end
                            local updated_pitch = pitch_module.HandleSelectedTracksItemsPitchChange(parsed, items_pitch)
                            items_pitch = updated_pitch
                            pitch_module.ResetSelectedTracksItemsPitchDelta()
                            pitch_module.FinalizePitchChange()
                        end
                        track_items_pitch_value_edit.active = false
                    end
                end
                if not has_track_items then
                    r.ImGui_EndDisabled(ctx)
                    it_changed = false
                    it_deactivated = false
                elseif it_changed then
                    local updated_pitch = pitch_module.HandleSelectedTracksItemsPitchChange(it_new, items_pitch)
                    items_pitch = updated_pitch
                end
                if has_track_items and it_deactivated then
                    pitch_module.ResetSelectedTracksItemsPitchDelta()
                    pitch_module.FinalizePitchChange()
                end
                UI.Separator(ctx)
                local fs = freeze_stats or { total = 0, has = false, track_count = #tracks, mixed = false, all_frozen = false }
                local base, hover, active, push_black = UI.GetFreezeAccentColors(fs)
                local label = 'Unfreeze'
                local width = 80
                if fs.track_count == 1 and fs.has then
                    label = string.format('Unfreeze (%d)', fs.total)
                    width = 100
                end
                UI.StyledButton(ctx, 'Freeze', 70, function()
                    Track.FreezeTracks(tracks)
                end)
                r.ImGui_SameLine(ctx, 0, 2)
                if base then
                    if push_black then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('black')) end
                    UI.ColoredButton(ctx, label, width, base, hover, active, function()
                        Track.UnfreezeTracks(tracks)
                    end)
                    if push_black then r.ImGui_PopStyleColor(ctx, 1) end
                else
                    UI.StyledButton(ctx, label, width, function()
                        Track.UnfreezeTracks(tracks)
                    end)
                end
                UI.Separator(ctx)
                local pdc_value = '-'
                if #tracks == 1 and r.ValidatePtr(tracks[1], 'MediaTrack*') then
                    local perf = Track.GetPerfInfo(tracks[1])
                    local pdc = perf and perf.pdc_spl or nil
                    if pdc then
                        local rounded = RoundUpPow2(math.floor(pdc))
                        local sr = r.GetSetProjectInfo(0, 'PROJECT_SRATE', 0, false) or 0
                        if sr and sr > 0 then
                            local ms = (rounded / sr) * 1000.0
                            pdc_value = string.format('%d spl (%.2f ms)', rounded, ms)
                        else
                            pdc_value = string.format('%d spl', rounded)
                        end
                    end
                elseif #tracks > 1 then
                    pdc_value = 'mixed'
                end
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_white_soft'))
                if font_bold then
                    PushFontCompat(ctx, font_bold, 0)
                end
                r.ImGui_Text(ctx, 'PDC:')
                if font_bold then
                    r.ImGui_PopFont(ctx)
                end
                r.ImGui_PopStyleColor(ctx, 1)
                r.ImGui_SameLine(ctx, 0, 6)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray'))
                r.ImGui_Text(ctx, pdc_value)
                r.ImGui_PopStyleColor(ctx, 1)
                r.ImGui_EndGroup(ctx)
            end

            if IsItemSelection(props) then
                r.ImGui_BeginGroup(ctx)
                UI.ResetAggHoverRegion()
                UI.RenderInfoButton(ctx, 40009, UI.HEADER_SLOT_W)
                r.ImGui_SameLine(ctx, 0, UI.HEADER_SLOT_GAP)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('black'))
                UI.ColoredButton(ctx, 'N', UI.HEADER_SPINE_W, Theme.get('beige_base'), Theme.get('beige_hover'), Theme.get('beige_active'), function()
                    r.Main_OnCommand(40850, 0)
                end)
                UI.QueueStyledTooltipDelayed(ctx, 'fip_item_notes', UI.GetItemNotesButtonTooltipLines(), 1.0)
                r.ImGui_PopStyleColor(ctx, 1)
                UI.Separator(ctx)
                if not item_header.editable then
                    -- Video, video processor, click, timecode, subproject and empty items: no controls yet.
                    DrawItemInfoLine(ctx)
                    r.ImGui_EndGroup(ctx)
                else
                local base_red = Theme.get('red_base')
                local hover_red = Theme.get('red_hover')
                local active_red = Theme.get('red_active')
                local blue = Theme.get('blue_freeze')
                local yellow = Theme.get('yellow')
                local item_tracks = {}
                local seen = {}
                for _, it in ipairs(items) do
                    local tr = r.GetMediaItem_Track(it)
                    if tr and r.ValidatePtr(tr, 'MediaTrack*') then
                        local guid = r.GetTrackGUID(tr)
                        if guid and not seen[guid] then
                            seen[guid] = true
                            item_tracks[#item_tracks + 1] = tr
                        end
                    end
                end
                local fs_items = Track.GetFreezeStats(item_tracks)
                local btn_base, btn_hover, btn_active, push_black = UI.GetFreezeAccentColors(fs_items)
                if not btn_base then
                    btn_base = base_red
                    btn_hover = hover_red
                    btn_active = active_red
                end
                UI.ColoredButton(ctx, '##fip_reset_item', 24, btn_base, btn_hover, btn_active, function()
                    local cmd1 = r.NamedCommandLookup('_SWS_RESETRATE')
                    local cmd2 = r.NamedCommandLookup('_XENAKIOS_RESETITEMLENMEDOFFS')
                    local cmd3 = r.NamedCommandLookup('_XENAKIOS_RESETITEMPITCHANDRATE')
                    if cmd1 ~= 0 then r.Main_OnCommand(cmd1, 0) end
                    if cmd2 ~= 0 then r.Main_OnCommand(cmd2, 0) end
                    if cmd3 ~= 0 then r.Main_OnCommand(cmd3, 0) end
                end)
                UI.DrawGlyphInLastItem(ctx, UI.GLYPH.reset, 14, push_black and Theme.get('black') or Theme.get('text_white_soft'))
                UI.Separator(ctx)
                local is_rate_modified = (props.playback_rate or 1.0) ~= 1.0
                local function reset_rate_action()
                    rate_value_edit.active = false
                    rate_value_edit.want_focus = false
                    props.playback_rate = 1.0
                    props.bpm = r.Master_GetTempo()
                    Utils.with_undo('Reset Rate', function()
                        if r.APIExists and r.APIExists("FIP_SetSelectedItemsPlaybackRate") then
                            r.FIP_SetSelectedItemsPlaybackRate("1.0", 0)
                        else
                            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPlaybackRate not available\n")
                        end
                    end)
                end
                if not rate_value_edit.active then
                    local rate_changed, rate_value, rate_deactivated, _, rate_dbl_clicked = UI.RateControl(ctx, 'Rate:', props.playback_rate or 1.0, UI.VALUE_BOX_W, 0.1, 0.01, 100, reset_rate_action, 40, is_rate_modified, false, item_count, function()
                        rate_value_edit.active = true
                        rate_value_edit.text = UI.FormatRateDisplayValue(props.playback_rate or 1.0)
                        rate_value_edit.want_focus = true
                        value_input_reset_grace_frames = 2
                    end, UI.GetRateTooltipLines(), true)
                    if rate_dbl_clicked then
                        reset_rate_action()
                    elseif rate_changed then
                        props.playback_rate = rate_value
                        props.bpm = r.Master_GetTempo() / rate_value
                        if r.APIExists and r.APIExists("FIP_SetSelectedItemsPlaybackRate") then
                            r.FIP_SetSelectedItemsPlaybackRate(tostring(rate_value), 0)
                        else
                            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPlaybackRate not available\n")
                        end
                    end
                    if rate_deactivated then
                        Utils.with_undo('Change Rate', function() end)
                    end
                    UI.QueueStyledTooltipDelayed(ctx, 'fip_rate_value', UI.GetRateTooltipLines(), 1.0)
                else
                    UI.StyledResetButton(ctx, 'Rate:', 40, is_rate_modified, reset_rate_action)
                    r.ImGui_SameLine(ctx, 0, 2)
                    r.ImGui_SetNextItemWidth(ctx, UI.VALUE_BOX_W)
                    if rate_value_edit.want_focus then
                        r.ImGui_SetKeyboardFocusHere(ctx)
                        rate_value_edit.want_focus = false
                    end
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_42'))
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), Theme.get('gray_74'))
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 4)
                    local input_flags = r.ImGui_InputTextFlags_CharsDecimal()
                                      | r.ImGui_InputTextFlags_EnterReturnsTrue()
                                      | r.ImGui_InputTextFlags_AutoSelectAll()
                    local rate_submitted, new_text = r.ImGui_InputText(ctx, '##RateValue', rate_value_edit.text, input_flags)
                    rate_value_edit.text = new_text
                    local rate_d = Utils.ReturnFocusOnDeactivation(ctx)
                    r.ImGui_PopStyleVar(ctx, 2)
                    r.ImGui_PopStyleColor(ctx, 2)
                    UI.QueueStyledTooltipDelayed(ctx, 'fip_rate_value', UI.GetRateTooltipLines(), 1.0)
                    if rate_submitted or rate_d then
                        local parsed = UI.ParseRateInput(rate_value_edit.text, 0.01, 100)
                        if parsed then
                            props.playback_rate = parsed
                            props.bpm = r.Master_GetTempo() / parsed
                            if r.APIExists and r.APIExists("FIP_SetSelectedItemsPlaybackRate") then
                                r.FIP_SetSelectedItemsPlaybackRate(tostring(parsed), 0)
                            else
                                r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPlaybackRate not available\n")
                            end
                            Utils.with_undo('Change Rate', function() end)
                        end
                        rate_value_edit.active = false
                    end
                end
                UI.Separator(ctx)
                local project_tempo = r.Master_GetTempo()
                local current_bpm = props.bpm or project_tempo
                local bpm_modified = math.abs(current_bpm - project_tempo) > 0.0001
                local function reset_bpm_action()
                    bpm_value_edit.active = false
                    bpm_value_edit.want_focus = false
                    props.bpm = project_tempo
                    props.playback_rate = 1.0
                    Utils.with_undo('Reset BPM', function()
                        if r.APIExists and r.APIExists("FIP_SetSelectedItemsPlaybackRate") then
                            r.FIP_SetSelectedItemsPlaybackRate("1.0", 0)
                        else
                            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPlaybackRate not available\n")
                        end
                    end)
                end
                if not bpm_value_edit.active then
                    local bmp_changed, bpm, bpm_deactivated, _, bpm_dbl_clicked = UI.ContinuousValueControl(ctx, 'BPM:', current_bpm, 62, 0.1, 20, 999, '%.2f', reset_bpm_action, 40, bpm_modified, false, item_count, function()
                        bpm_value_edit.active = true
                        bpm_value_edit.text = UI.FormatBPMValue(current_bpm or project_tempo)
                        bpm_value_edit.want_focus = true
                        value_input_reset_grace_frames = 2
                    end, UI.GetBPMTooltipLines(), true)
                    if bpm_dbl_clicked then
                        reset_bpm_action()
                    elseif bmp_changed then
                        if bpm <= 0 then
                            props.bpm = project_tempo
                            props.playback_rate = 1.0
                            if r.APIExists and r.APIExists("FIP_SetSelectedItemsPlaybackRate") then
                                r.FIP_SetSelectedItemsPlaybackRate("1.0", 0)
                            else
                                r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPlaybackRate not available\n")
                            end
                            Utils.with_undo('Reset BPM', function() end)
                        else
                            props.bpm = bpm
                            props.playback_rate = project_tempo / bpm
                            if r.APIExists and r.APIExists("FIP_SetSelectedItemsPlaybackRate") then
                                r.FIP_SetSelectedItemsPlaybackRate(tostring(props.playback_rate), 0)
                            else
                                r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPlaybackRate not available\n")
                            end
                        end
                    end
                    if bpm_deactivated then
                        Utils.with_undo('Change BPM', function() end)
                    end
                    UI.QueueStyledTooltipDelayed(ctx, 'fip_bpm_value', UI.GetBPMTooltipLines(), 1.0)
                else
                    local w_bpm = 62
                    UI.StyledResetButton(ctx, 'BPM:', 40, bpm_modified, reset_bpm_action, false, false)
                    if item_count and item_count > 1 then
                        UI.ExtendAggHoverRegion(ctx)
                    end
                    r.ImGui_SameLine(ctx, 0, 2)
                    r.ImGui_SetNextItemWidth(ctx, w_bpm)
                    if bpm_value_edit.want_focus then
                        r.ImGui_SetKeyboardFocusHere(ctx)
                        bpm_value_edit.want_focus = false
                    end
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_42'))
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), Theme.get('gray_74'))
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 4)
                    local input_flags = r.ImGui_InputTextFlags_CharsDecimal()
                                      | r.ImGui_InputTextFlags_EnterReturnsTrue()
                                      | r.ImGui_InputTextFlags_AutoSelectAll()
                    local bpm_submitted, new_text = r.ImGui_InputText(ctx, '##BpmValue', bpm_value_edit.text, input_flags)
                    bpm_value_edit.text = new_text
                    local bpm_d = Utils.ReturnFocusOnDeactivation(ctx)
                    r.ImGui_PopStyleVar(ctx, 2)
                    r.ImGui_PopStyleColor(ctx, 2)
                    UI.QueueStyledTooltipDelayed(ctx, 'fip_bpm_value', UI.GetBPMTooltipLines(), 1.0)
                    local commit = bpm_submitted or bpm_d
                    if commit then
                        local parsed = UI.ParseBPMValue(bpm_value_edit.text, 20, 999)
                        if parsed then
                            props.bpm = parsed
                            props.playback_rate = project_tempo / parsed
                            if r.APIExists and r.APIExists("FIP_SetSelectedItemsPlaybackRate") then
                                r.FIP_SetSelectedItemsPlaybackRate(tostring(props.playback_rate), 0)
                            else
                                r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPlaybackRate not available\n")
                            end
                            Utils.with_undo('Change BPM', function() end)
                        end
                        bpm_value_edit.active = false
                    end
                    if item_count and item_count > 1 then
                        UI.DrawAggregationOutline(ctx, nil, 4, 0)
                        UI.ExtendAggHoverRegion(ctx)
                    end
                end
                UI.Separator(ctx)
                local preserve_value = props.preserve_pitch
                local preserve_mixed = (preserve_value == nil)
                local preserve_disabled = (props.take_type == 'MIDI')
                local preserve_changed, preserve = UI.StyledCheckbox(ctx, 'Preserve', preserve_value, preserve_mixed, preserve_disabled)
                UI.QueueStyledTooltipDelayed(ctx, 'fip_preserve_pitch', UI.GetPreservePitchTooltipLines(), 1.0)
                if preserve_changed and not preserve_disabled then
                    props.preserve_pitch = preserve
                    Item.UpdatePreservePitch(items, preserve)
                end
                UI.Separator(ctx)
                TimestrechWidget.Render(ctx, props, items, Item, UI.StyledResetButton, bar_color, bar_fg)
                UI.Separator(ctx)
                if props.take_type == 'Audio' or props.take_type == 'MIDI' or props.take_type == 'Mult' then
                    local is_multi = (item_count > 1)
                    local transpose_midi_mode = (r.GetExtState("Frenkie_Inspector", "TransposeMIDI") == "1")
                    -- Use Delta/Accumulator mode for Multi-selection OR when Transpose MIDI is active (since we need relative edits for MIDI)
                    local use_delta_mode = is_multi or (transpose_midi_mode and (props.take_type == 'MIDI' or props.take_type == 'Mult'))
                    
                    local base_pitch = 0
                    local is_mixed = false
                    local is_modified = false
                    local midi_transpose_drag_mode = transpose_midi_mode and (props.take_type == 'MIDI' or props.take_type == 'Mult')
                    local continuous_item_pitch = not midi_transpose_drag_mode
                    local multi_audio_pitch_mode = is_multi and continuous_item_pitch
                    
                    if use_delta_mode then
                        local pitch_state = (r.APIExists and r.APIExists("FIP_GetSelectedItemsPitchStateVal"))
                            and (r.FIP_GetSelectedItemsPitchStateVal("", 0) or 0)
                            or 0
                        is_mixed = (pitch_state < 0)
                        is_modified = (pitch_state > 0)
                        base_pitch = (r.APIExists and r.APIExists("FIP_GetSelectedItemsPitchDeltaVal"))
                            and (r.FIP_GetSelectedItemsPitchDeltaVal("", 0) or 0)
                            or 0
                        if multi_audio_pitch_mode then
                            local actual_agg_pitch = props.pitch or 0
                            is_modified = (pitch_state ~= 0)
                            if multi_item_pitch_session.sig ~= items_sig then
                                reset_multi_item_pitch_session()
                                multi_item_pitch_session.sig = items_sig
                            end
                            if multi_item_pitch_session.active then
                                base_pitch = multi_item_pitch_session.display or 0
                            else
                                base_pitch = is_mixed and 0 or actual_agg_pitch
                            end
                        elseif midi_transpose_drag_mode then
                            if midi_item_pitch_session.sig ~= items_sig then
                                reset_midi_item_pitch_session()
                                midi_item_pitch_session.sig = items_sig
                            end
                            if midi_item_pitch_session.active then
                                base_pitch = midi_item_pitch_session.display or 0
                                is_modified = math.abs(base_pitch) > 0.0001
                            end
                        end
                    else
                        local pitch_str = (r.APIExists and r.APIExists("FIP_GetAggregatedPitch")) and r.FIP_GetAggregatedPitch("", 0) or "0"
                        is_mixed = (pitch_str == "MIXED")
                        base_pitch = is_mixed and 0 or tonumber(pitch_str or "0") or 0
                        is_modified = (not is_mixed) and math.abs(base_pitch) > 0.001
                    end
                    local function pitch_reset_action()
                        pitch_value_edit.active = false
                        pitch_value_edit.want_focus = false
                        local transpose_midi_mode_cb = (r.GetExtState("Frenkie_Inspector", "TransposeMIDI") == "1")
                        if transpose_midi_mode_cb and midi_transpose_drag_mode then
                            local current_display = midi_item_pitch_session.active and (midi_item_pitch_session.display or 0) or base_pitch
                            if math.abs(current_display) > 0.0001 then
                                if r.APIExists and r.APIExists("FIP_ApplyAddSelectedItemsPitchDeltaVal") then
                                    r.FIP_ApplyAddSelectedItemsPitchDeltaVal(tostring(-current_display), 0)
                                else
                                    r.ShowConsoleMsg("ERROR: FIP_ApplyAddSelectedItemsPitchDeltaVal not available\n")
                                end
                            end
                            reset_midi_item_pitch_session()
                            if r.APIExists and r.APIExists("FIP_ResetSelectedItemsPitchDeltaVal") then
                                r.FIP_ResetSelectedItemsPitchDeltaVal("", 0)
                            end
                            props.pitch = 0
                        else
                            if use_delta_mode then
                                if multi_audio_pitch_mode then
                                    if r.APIExists and r.APIExists("FIP_SetSelectedItemsPitch") then
                                        r.FIP_SetSelectedItemsPitch("0", 0)
                                    else
                                        r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPitch not available\n")
                                    end
                                    reset_multi_item_pitch_session()
                                elseif r.APIExists and r.APIExists("FIP_SetSelectedItemsPitch") then
                                    r.FIP_SetSelectedItemsPitch("0", 0)
                                else
                                    r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPitch not available\n")
                                end
                                if r.APIExists and r.APIExists("FIP_ResetSelectedItemsPitchDeltaVal") then
                                    r.FIP_ResetSelectedItemsPitchDeltaVal("", 0)
                                end
                                props.pitch = 0
                            else
                                if r.APIExists and r.APIExists("FIP_SetSelectedItemsPitch") then
                                    r.FIP_SetSelectedItemsPitch("0", 0)
                                else
                                    r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPitch not available\n")
                                end
                                props.pitch = 0
                            end
                        end
                    end
                    local function apply_pitch_value(new_pitch_val)
                        if use_delta_mode then
                            if multi_audio_pitch_mode then
                                local prev_pitch = multi_item_pitch_session.active and (multi_item_pitch_session.display or 0) or base_pitch
                                local delta = new_pitch_val - prev_pitch
                                if math.abs(delta) > 0.0001 then
                                    if r.APIExists and r.APIExists("FIP_AddSelectedItemsPitch") then
                                        r.FIP_AddSelectedItemsPitch(tostring(delta), 0)
                                    else
                                        r.ShowConsoleMsg("ERROR: FIP_AddSelectedItemsPitch not available\n")
                                    end
                                end
                                multi_item_pitch_session.active = true
                                multi_item_pitch_session.sig = items_sig
                                multi_item_pitch_session.display = new_pitch_val
                            elseif midi_transpose_drag_mode then
                                local prev_pitch = midi_item_pitch_session.active and (midi_item_pitch_session.display or 0) or base_pitch
                                local delta = new_pitch_val - prev_pitch
                                if math.abs(delta) > 0.0001 then
                                    if r.APIExists and r.APIExists("FIP_ApplyAddSelectedItemsPitchDeltaVal") then
                                        r.FIP_ApplyAddSelectedItemsPitchDeltaVal(tostring(delta), 0)
                                    else
                                        r.ShowConsoleMsg("ERROR: FIP_ApplyAddSelectedItemsPitchDeltaVal not available\n")
                                    end
                                end
                                midi_item_pitch_session.active = true
                                midi_item_pitch_session.sig = items_sig
                                midi_item_pitch_session.display = new_pitch_val
                            else
                                local delta = new_pitch_val - base_pitch
                                if math.abs(delta) > 0.0001 then
                                    if r.APIExists and r.APIExists("FIP_ApplyAddSelectedItemsPitchDeltaVal") then
                                        r.FIP_ApplyAddSelectedItemsPitchDeltaVal(tostring(delta), 0)
                                    else
                                        r.ShowConsoleMsg("ERROR: FIP_ApplyAddSelectedItemsPitchDeltaVal not available\n")
                                    end
                                end
                            end
                            props.pitch = new_pitch_val
                        else
                            if r.APIExists and r.APIExists("FIP_SetSelectedItemsPitch") then
                                r.FIP_SetSelectedItemsPitch(tostring(new_pitch_val), 0)
                            else
                                r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPitch not available\n")
                            end
                            props.pitch = new_pitch_val
                        end
                    end
                    -- Same width for audio ("-12.34") and MIDI ("-12 st") so controls to the right never shift.
                    local pitch_box_w = UI.VALUE_BOX_W
                    if not pitch_value_edit.active then
                        local pitch_changed, new_pitch, pitch_deactivated
                        if continuous_item_pitch then
                            pitch_changed, new_pitch, pitch_deactivated = UI.ItemPitchControl(ctx, 'Pitch:', base_pitch, pitch_box_w, -96, 96, pitch_reset_action, nil, is_modified, is_mixed, item_count, function()
                                pitch_value_edit.active = true
                                pitch_value_edit.text = UI.FormatItemPitchValue(base_pitch)
                                pitch_value_edit.want_focus = true
                                value_input_reset_grace_frames = 2
                            end, UI.GetItemPitchTooltipLines(continuous_item_pitch))
                        else
                            pitch_changed, new_pitch, pitch_deactivated = UI.VerticalPitchControl(ctx, 'Pitch:', base_pitch, pitch_box_w, 0.1, -96, 96, '%.0f st', pitch_reset_action, nil, false, is_modified, is_mixed, item_count, nil, false, function()
                                pitch_value_edit.active = true
                                pitch_value_edit.text = string.format('%.0f', math.floor((base_pitch or 0) + 0.5))
                                pitch_value_edit.want_focus = true
                                value_input_reset_grace_frames = 2
                            end, UI.GetItemPitchTooltipLines(continuous_item_pitch), true)
                        end
                        if pitch_changed then
                            apply_pitch_value(new_pitch)
                        end
                        if pitch_deactivated then
                            if use_delta_mode then
                                if midi_transpose_drag_mode then
                                    pitch_module.FinalizeMIDITranspose(items)
                                else
                                    pitch_module.FinalizePitchChange()
                                    if multi_audio_pitch_mode then
                                        reset_multi_item_pitch_session()
                                        if r.APIExists and r.APIExists("FIP_ResetSelectedItemsPitchDeltaVal") then
                                            r.FIP_ResetSelectedItemsPitchDeltaVal("", 0)
                                        end
                                    end
                                end
                            else
                                Utils.with_undo("Change Pitch", function() end)
                            end
                        end
                    else
                        local pit_tt = UI.GetItemPitchTooltipLines(continuous_item_pitch)
                        UI.StyledResetButton(ctx, 'Pitch:', 40, is_modified, pitch_reset_action, nil, is_mixed)
                        local pr1x1, pr1y1 = r.ImGui_GetItemRectMin(ctx)
                        local pr1x2, pr1y2 = r.ImGui_GetItemRectMax(ctx)
                        if item_count and item_count > 1 then
                            UI.ExtendAggHoverRegion(ctx)
                        end
                        r.ImGui_SameLine(ctx, 0, 2)
                        r.ImGui_SetNextItemWidth(ctx, pitch_box_w)
                        if pitch_value_edit.want_focus then
                            r.ImGui_SetKeyboardFocusHere(ctx)
                            pitch_value_edit.want_focus = false
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_42'))
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), Theme.get('gray_74'))
                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 4)
                        local input_flags = r.ImGui_InputTextFlags_CharsDecimal()
                                          | r.ImGui_InputTextFlags_EnterReturnsTrue()
                                          | r.ImGui_InputTextFlags_AutoSelectAll()
                        local pitch_submitted, new_text = r.ImGui_InputText(ctx, '##PitchValue', pitch_value_edit.text, input_flags)
                        pitch_value_edit.text = new_text
                        local pitch_d = Utils.ReturnFocusOnDeactivation(ctx)
                        r.ImGui_PopStyleVar(ctx, 2)
                        r.ImGui_PopStyleColor(ctx, 2)
                        local pr2x1, pr2y1 = r.ImGui_GetItemRectMin(ctx)
                        local pr2x2, pr2y2 = r.ImGui_GetItemRectMax(ctx)
                        if pitch_submitted or pitch_d then
                            local parsed
                            if continuous_item_pitch then
                                parsed = UI.ParseItemPitchValue(pitch_value_edit.text, -96, 96)
                            else
                                local normalized = ((pitch_value_edit.text or ''):gsub(',', '.'))
                                parsed = tonumber(normalized)
                                if parsed then
                                    if parsed < -96 then parsed = -96 end
                                    if parsed > 96 then parsed = 96 end
                                end
                            end
                            if parsed then
                                apply_pitch_value(parsed)
                                if use_delta_mode then
                                    if midi_transpose_drag_mode then
                                        pitch_module.FinalizeMIDITranspose(items)
                                    else
                                        pitch_module.FinalizePitchChange()
                                        if multi_audio_pitch_mode then
                                            reset_multi_item_pitch_session()
                                            if r.APIExists and r.APIExists("FIP_ResetSelectedItemsPitchDeltaVal") then
                                                r.FIP_ResetSelectedItemsPitchDeltaVal("", 0)
                                            end
                                        end
                                    end
                                else
                                    Utils.with_undo("Change Pitch", function() end)
                                end
                            end
                            pitch_value_edit.active = false
                        end
                        if item_count and item_count > 1 then
                            UI.DrawAggregationOutline(ctx, nil, 4, 0)
                            UI.ExtendAggHoverRegion(ctx)
                        end
                        local mx, my = r.ImGui_GetMousePos(ctx)
                        local pux1 = math.min(pr1x1, pr2x1)
                        local puy1 = math.min(pr1y1, pr2y1)
                        local pux2 = math.max(pr1x2, pr2x2)
                        local puy2 = math.max(pr1y2, pr2y2)
                        local pin = mx >= pux1 and mx <= pux2 and my >= puy1 and my <= puy2
                        UI.QueueStyledTooltipDelayedGeneric(ctx, 'fip_pitch_edit', pit_tt, 1.0, pin)
                    end
                    UI.Separator(ctx)
                end
                Fader.RenderFaders(ctx, items, props, bar_color, UI)
                
                if item_count > 1 then
                    UI.ShowTooltipDelayedIfHoveredInAggRegion(ctx, 'agg_unified', "Aggregation Mode\nEdits add to each selected item's values.", 1.0)
                end
                UI.Separator(ctx)
                local has_fx = item_count == 1 and r.APIExists and r.APIExists('FIP_GetSelectedItemsWithFXCountVal')
                    and (r.FIP_GetSelectedItemsWithFXCountVal('', 0) or 0) > 0 or false
                -- Alt: remove all take FX; Cmd/Ctrl: apply take FX if any, else open the chain; click: open the chain.
                local function fx_action()
                    local mods = r.ImGui_GetKeyMods(ctx)
                    local flags = ((mods & r.ImGui_Mod_Alt()) ~= 0 and 1 or 0)
                        | (((mods & r.ImGui_Mod_Super()) ~= 0 or (mods & r.ImGui_Mod_Ctrl()) ~= 0) and 2 or 0)
                    if r.APIExists and r.APIExists('FIP_ItemFXClick') then r.FIP_ItemFXClick('', flags) end
                end
                if has_fx then
                    local green = Theme.get('green_accent')
                    UI.ColoredButton(ctx, 'FX', 30, green, green, green, fx_action)
                else
                    UI.StyledButton(ctx, 'FX', 30, fx_action)
                end
                UI.QueueStyledTooltipDelayed(ctx, 'fip_fx_btn', UI.GetFxChainButtonTooltipLines(), 1.0)
                UI.Separator(ctx)
                local loop_value = props.loop
                local loop_mixed = (loop_value == nil)
                local loop_changed, loop = UI.GlyphToggle(ctx, '##LoopIcon', UI.GLYPH.letter_L, Theme.get('toggle_loop'), loop_value, loop_mixed, 20)
                if loop_changed then
                    props.loop = loop
                    Item.UpdateLoop(items, loop)
                end
                r.ImGui_SameLine(ctx, 0, 8)
                local reverse_value = props.reverse
                local reverse_mixed = (reverse_value == nil)
                local reverse_changed, reverse = UI.GlyphToggle(ctx, '##ReverseIcon', UI.GLYPH.reverse, Theme.get('toggle_reverse'), reverse_value, reverse_mixed, 20)
                if reverse_changed then
                    props.reverse = reverse
                    Item.UpdateReverse(items, reverse)
                end
                r.ImGui_SameLine(ctx, 0, 8)
                local mute_value = props.mute
                local mute_mixed = (mute_value == nil)
                local mute_changed, mute = UI.GlyphToggle(ctx, '##MuteIcon', UI.GLYPH.letter_M, Theme.get('toggle_red'), mute_value, mute_mixed, 20)
                if mute_changed then
                    props.mute = mute
                    Item.UpdateMute(items, mute)
                end
                r.ImGui_SameLine(ctx, 0, 8)
                local lock_value = props.lock
                local lock_mixed = (lock_value == nil)
                local lock_changed, lock = UI.GlyphToggle(ctx, '##LockIcon', UI.GLYPH.lock, Theme.get('toggle_red'), lock_value, lock_mixed, 20)
                if lock_changed then
                    props.lock = lock
                    Item.UpdateLock(items, lock)
                end
                UI.Separator(ctx)
                DrawItemInfoLine(ctx)
                r.ImGui_EndGroup(ctx)
            end
            end
        end
        if not fip_fxsnap_strip_committed then
            fip_fxsnap_row_screen_rect.valid = false
        end
        do
            local hf = r.ImGui_HoveredFlags_ChildWindows()
                      | r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem()
                      | r.ImGui_HoveredFlags_AllowWhenBlockedByPopup()
            local win_hov = r.ImGui_IsWindowHovered(ctx, hf)
            local any_item = true
            local ok_any = pcall(function()
                any_item = r.ImGui_IsAnyItemHovered(ctx)
            end)
            if not ok_any then any_item = true end
            if fip_fxsnap_row_screen_rect.valid then
                local R = fip_fxsnap_row_screen_rect
                local mx, my = r.ImGui_GetMousePos(ctx)
                if mx >= R.x1 and mx <= R.x2 and my >= R.y1 and my <= R.y2 then
                    any_item = true
                end
            end
            if win_hov and not any_item then
                UI.QueueStyledTooltipDelayedGeneric(ctx, 'fip_panel_bg', UI.GetPanelBackgroundTooltipLines(), 1.0, true)
            else
                UI.ClearStyledTooltipHoverState('fip_panel_bg')
            end
        end
        r.ImGui_End(ctx)
    end
    UI.PopWindowStyle(ctx)
    r.ImGui_PopFont(ctx)
    UI.RenderPendingTooltip(ctx)
    if open then
        r.defer(Main)
    end
end

local function loop()
    EnsureImGuiContext()
    Main()
end

loop()
