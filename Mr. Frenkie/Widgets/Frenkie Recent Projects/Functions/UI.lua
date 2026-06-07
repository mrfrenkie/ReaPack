-- @noindex

-- Frenkie Recent Projects - UI Module
---@diagnostic disable: undefined-global, redefined-local -- reaper is provided by REAPER at runtime

if not reaper.ImGui_CreateContext then
    if reaper.APIExists and reaper.APIExists("ReaPack_BrowsePackages") and reaper.ReaPack_BrowsePackages then
        local ok = pcall(reaper.ReaPack_BrowsePackages, "ReaImGui")
        if not ok then
            pcall(reaper.ReaPack_BrowsePackages)
        end
    elseif reaper.ShowMessageBox then
        reaper.ShowMessageBox(
            "ReaImGUI not found!\n\nInstall ReaImGUI via ReaPack:\nExtensions > ReaPack > Browse packages\nSearch for: ReaImGUI",
            "Error",
            0
        )
    end
    return
end

UI = {}

local ctx = nil
local font = nil
local ICON_PLAY = "▶"
local ICON_STOP = "■"
local ICON_LIST_VIEW = "☰"
local ICON_PIN = "◉"
local ICON_PIN_HOVER = "◎"
local ICON_CLOSE = "×"
local ICON_CLOSE_HOVER = "×"
local ICON_MDI_REPEAT = "↺"
local first_frame = true
local font_size = 15.0
local filter_id_version = 0
local filter_focus_next_frame = false
local filter_has_focus = false
local filter_focused_last_frame = false
local hover_start_time = {}
local hover_last_pos = {}
local hover_delay = 1.0  -- 1.0 second delay for tooltip
local timeline_state = {}
local function get_timeline_state(id)
    local key = tostring(id or "")
    local st = timeline_state[key]
    if st then return st end
    st = {
        is_scrubbing = false,
        scrub_ratio = 0.0,
        seek_override_ratio = nil,
        seek_override_until = 0.0,
        scrub_snap_active = false,
        scrub_snap_ratio = 0.0,
        scrub_snap_x = 0,
        scrub_snap_tol = 0,
    }
    timeline_state[key] = st
    return st
end
local function set_timeline_seek_override(id, ratio, until_t)
    local st = get_timeline_state(id)
    st.seek_override_ratio = ratio
    st.seek_override_until = tonumber(until_t) or 0.0
end
local durations_cache = {}
local Theme = FRPTheme or {}
local COLORS = Theme.colors or Theme or {}

local COLOR_TEXT_MUTED = COLORS.text_muted
local COLOR_TEXT = COLORS.text
local COLOR_TEXT_BLACK = COLORS.text_black
local COLOR_TEXT_INVERTED = COLORS.text_inverted

local COLOR_ACCENT = COLORS.accent
local COLOR_ACCENT_DARK = COLOR_ACCENT
local COLOR_ACCENT_GREEN = COLORS.accent_green or COLOR_ACCENT
if reaper.ImGui_ColorConvertU32ToDouble4 and reaper.ImGui_ColorConvertDouble4ToU32 then
    local dr, dg, db, da = reaper.ImGui_ColorConvertU32ToDouble4(COLOR_ACCENT)
    local df = 0.35
    COLOR_ACCENT_DARK = reaper.ImGui_ColorConvertDouble4ToU32(dr * df, dg * df, db * df, da)
end

local COLOR_BG_WINDOW = COLORS.bg_window
local COLOR_BG_TITLE = COLORS.bg_title
local COLOR_BG_TITLE_ACTIVE = COLORS.bg_title_active

local COLOR_FRAME_BG = COLORS.frame_bg
local COLOR_FRAME_BG_HOVERED = COLORS.frame_bg_hovered
local COLOR_FRAME_BG_ACTIVE = COLORS.frame_bg_active

local COLOR_BG_BUTTON = COLORS.button_bg
local COLOR_BG_BUTTON_HOVER = COLORS.button_bg_hover
local COLOR_BG_BUTTON_ACTIVE = COLORS.button_bg_active
local COLOR_BUTTON_DISABLED = COLORS.button_disabled_bg

local COLOR_BLACK_TRANSPARENT = COLORS.black_transparent
local COLOR_BLACK_BG_SOFT = COLORS.black_bg_soft
local COLOR_BLACK_BG_TIP = COLORS.black_bg_tip

local COLOR_WHITE_LINE = COLORS.white_line

local COLOR_TABLE_ROW_BG = COLORS.table_row_bg or COLOR_BLACK_TRANSPARENT
local COLOR_TABLE_ROW_BG_ALT = COLORS.table_row_bg_alt or COLOR_BLACK_BG_SOFT
local COLOR_TABLE_EMPTY_BG = COLORS.table_empty_bg
local COLOR_BORDER = COLORS.border or COLOR_BG_BUTTON
local COLOR_POPUP_BG = COLORS.popup_bg or COLOR_BG_WINDOW
local COLOR_DARK_30 = COLORS.dark_30

local COLOR_HEADER_HOVER = COLORS.header_hover or COLOR_BG_BUTTON_HOVER
local COLOR_HEADER_ACTIVE = COLORS.header_active or COLOR_BG_BUTTON_ACTIVE

local COLOR_BORDER_SHADOW = COLORS.border_shadow

local COLOR_SCROLLBAR_BG = COLORS.scrollbar_bg
local COLOR_SCROLLBAR_GRAB = COLORS.scrollbar_grab
local COLOR_SCROLLBAR_GRAB_HOVERED = COLORS.scrollbar_grab_hovered
local COLOR_SCROLLBAR_GRAB_ACTIVE = COLORS.scrollbar_grab_active

local COLOR_RESIZE_GRIP = COLORS.resize_grip
local COLOR_RESIZE_GRIP_HOVERED = COLORS.resize_grip_hovered
local COLOR_RESIZE_GRIP_ACTIVE = COLORS.resize_grip_active

local COLOR_CLOSE_BASE = COLORS.close_button_base
local COLOR_CLOSE_HOVER = COLORS.close_button_hover
local COLOR_CLOSE_ACTIVE = COLORS.close_button_active
local COLOR_CLOSE_CROSS = COLORS.close_button_cross

local COLOR_TOOLTIP_BG = COLORS.tooltip_bg
local COLOR_TOOLTIP_BORDER = COLORS.tooltip_border
local COLOR_TOOLTIP_TEXT = COLORS.tooltip_text or COLOR_TEXT_BLACK

local COLOR_TIMELINE_BG_ENABLED = COLORS.timeline_bg_enabled
local COLOR_TIMELINE_BG_DISABLED = COLORS.timeline_bg_disabled
local COLOR_TIMELINE_PLAYBAR_FILL = COLORS.timeline_playbar_fill
local COLOR_TIMELINE_REGION_SEPARATOR = COLORS.timeline_region_separator
local COLOR_TIMELINE_REGION_SEPARATOR_SOFT = COLORS.timeline_region_separator_soft

local COLOR_META_TEXT_SECONDARY = COLORS.meta_text_secondary
local COLOR_PROJECT_MISSING_TEXT = COLORS.project_missing_text

local COLOR_SEARCH_PLACEHOLDER = COLORS.search_placeholder

local COLOR_INLINE_BG_SELECTED = COLORS.inline_bg_selected
local COLOR_INLINE_BG_FILL = COLORS.inline_bg_fill
local COLOR_INLINE_BORDER_LIGHT = COLORS.inline_border_light
local COLOR_INLINE_BORDER_DARK = COLORS.inline_border_dark
local COLOR_META_PANEL_BG = COLORS.meta_panel_bg or COLOR_BG_WINDOW
local COLOR_META_PANEL_BORDER = COLORS.meta_panel_border or COLOR_INLINE_BORDER_DARK

local COLOR_ROW_BG_SELECTED = COLORS.row_bg_selected
local COLOR_ROW_BG_PINNED = COLORS.row_bg_pinned
local COLOR_ROW_BG_HOVER = COLORS.row_bg_hover
local COLOR_ROW_BG_FOCUS = COLORS.row_bg_focus
local COLOR_ROW_BG_HOVER_SOFT = COLORS.row_bg_hover_soft

local COLOR_SLIDER_GRAB_ACTIVE = COLORS.slider_grab_active

local COLOR_BOTTOM_LINE_SEPARATOR = COLORS.bottom_line_separator

local COLOR_FOOTER_TEXT_MUTED = COLORS.footer_text_muted

local COLOR_FOOTER_POPUP_BG = COLORS.footer_popup_bg
local COLOR_FOOTER_POPUP_TEXT = COLORS.footer_popup_text
local COLOR_FOOTER_POPUP_ITEM_HOVER = COLORS.footer_popup_item_hover

local COLOR_MENU_TEXT = COLORS.menu_text or COLOR_META_TEXT_SECONDARY

local region_label_color = COLOR_TEXT_MUTED
local current_region_label_color = COLOR_TEXT
local playhead_marker_color = COLORS.playhead_marker
local compute_timeline = nil
local draw_timeline = nil
local draw_player_timeline = nil
local fit_text_to_width = nil
local wrap_text_to_width = nil
local format_time_mmss = nil
local projects_scroll_target_y = nil
local projects_scroll_last_t = nil
local projects_scroll_restore_done = false
local play_column_center_x = nil
local pin_column_center_x = nil
local bottom_splitter_active = false
local bottom_splitter_start_mouse_y = 0
local bottom_splitter_start_h = 0
local bottom_panel_h_current = 0
local bottom_panel_target_h = 0
local bottom_panel_last_t = nil

local function clamp01(x)
    x = tonumber(x) or 0
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

local function normalize_path(path)
    local s = tostring(path or "")
    if s == "" then return "" end
    return (s:gsub("\\", "/")):lower()
end

local function color_set_alpha(color, alpha)
    local c = tonumber(color) or 0
    local a = tonumber(alpha) or 0
    if a < 0 then a = 0 end
    if a > 255 then a = 255 end
    return (math.floor(c / 256) * 256) + a
end
local function color_mul_rgb(color, factor)
    if reaper.ImGui_ColorConvertU32ToDouble4 and reaper.ImGui_ColorConvertDouble4ToU32 then
        local r, g, b, a = reaper.ImGui_ColorConvertU32ToDouble4(color)
        local f = tonumber(factor) or 1.0
        return reaper.ImGui_ColorConvertDouble4ToU32(r * f, g * f, b * f, a)
    end
    return color
end
local bottom_panel_ever_opened = false
local bottom_player_closed = false
local last_preview_playing = false
local undock_next_frame = false
local preview_vol_ignore_until = 0.0
local meta_panel_h_current = 0
local meta_panel_target_h = 0
local meta_panel_last_t = nil
local meta_panel_pending_path = nil
local PATH_MIN_WINDOW_W = 700
local PATH_SCROLL_SPEED = 40
local PATH_SCROLL_GAP = 40
local PATH_RIGHT_ICON_RESERVE = 40

local function get_history_file_path_from_ui()
    local src = debug.getinfo(1, "S")
    local script_path = src and src.source and src.source:match("@(.+)") or ""
    local dir = script_path:match("(.+)[/\\][^/\\]+$") or ""
    if dir == "" then
        return "My Recent Projects List.json"
    end
    local parent_dir = dir:match("(.+)[/\\][^/\\]+$") or dir
    if parent_dir == "" then
        return "My Recent Projects List.json"
    end
    return parent_dir .. "/My Recent Projects List.json"
end

local function apply_smooth_scroll(ctx, wheel_delta, scroll_step, target_y, last_t, speed)
    local now = reaper.time_precise()
    local dt = now - (last_t or now)
    last_t = now
    if dt < 0 then dt = 0 end
    if dt > 0.05 then dt = 0.05 end

    if wheel_delta ~= 0 and reaper.ImGui_GetScrollY then
        local current_y = reaper.ImGui_GetScrollY(ctx) or 0
        if target_y == nil then
            target_y = current_y
        end
        target_y = target_y - wheel_delta * scroll_step
        if target_y < 0 then target_y = 0 end
        if reaper.ImGui_GetScrollMaxY then
            local max_y = reaper.ImGui_GetScrollMaxY(ctx)
            if max_y and target_y > max_y then
                target_y = max_y
            end
        end
    end

    if target_y ~= nil and reaper.ImGui_SetScrollY then
        local current_y = reaper.ImGui_GetScrollY(ctx) or 0
        local alpha = 1.0 - math.exp(-(dt or 0) * (speed or 18.0))
        if alpha < 0 then alpha = 0 end
        if alpha > 1 then alpha = 1 end
        local new_y = current_y + (target_y - current_y) * alpha
        reaper.ImGui_SetScrollY(ctx, new_y)
        if math.abs(target_y - new_y) < 0.5 then
            target_y = nil
        end
    end

    return target_y, last_t
end

-- Constants
local WINDOW_FLAGS = reaper.ImGui_WindowFlags_NoCollapse()
if reaper.ImGui_WindowFlags_NoTitleBar then
    WINDOW_FLAGS = WINDOW_FLAGS | reaper.ImGui_WindowFlags_NoTitleBar()
end
if reaper.ImGui_WindowFlags_NoScrollbar then
    WINDOW_FLAGS = WINDOW_FLAGS | reaper.ImGui_WindowFlags_NoScrollbar()
end
if reaper.ImGui_WindowFlags_NoScrollWithMouse then
    WINDOW_FLAGS = WINDOW_FLAGS | reaper.ImGui_WindowFlags_NoScrollWithMouse()
end
if reaper.ImGui_WindowFlags_NoDocking then
    WINDOW_FLAGS = WINDOW_FLAGS | reaper.ImGui_WindowFlags_NoDocking()
end
local CHILD_LIST_WINDOW_FLAGS = 0
if reaper.ImGui_WindowFlags_NoScrollWithMouse then
    CHILD_LIST_WINDOW_FLAGS = CHILD_LIST_WINDOW_FLAGS | reaper.ImGui_WindowFlags_NoScrollWithMouse()
end
local BOTTOM_PLAYER_WINDOW_FLAGS = 0
if reaper.ImGui_WindowFlags_NoScrollbar then
    BOTTOM_PLAYER_WINDOW_FLAGS = BOTTOM_PLAYER_WINDOW_FLAGS | reaper.ImGui_WindowFlags_NoScrollbar()
end
if reaper.ImGui_WindowFlags_NoScrollWithMouse then
    BOTTOM_PLAYER_WINDOW_FLAGS = BOTTOM_PLAYER_WINDOW_FLAGS | reaper.ImGui_WindowFlags_NoScrollWithMouse()
end
function UI.init()
    ctx = reaper.ImGui_CreateContext('Frenkie Recent Projects')
    if not ctx then
        reaper.ShowMessageBox("Failed to create ImGui context!", "Error", 0)
        return false
    end

    local script_path = debug.getinfo(1, "S").source:match("@(.+)")
    local script_dir = script_path:match("(.+)[/\\][^/\\]+$")

    local font_path = script_dir .. "/Fonts/Roboto-Regular.ttf"
    if not reaper.file_exists(font_path) then
        font_path = script_dir .. "/fonts/Roboto-Regular.ttf"
    end
    if reaper.file_exists(font_path) then
        font = reaper.ImGui_CreateFont(font_path, font_size)
        if font then
            local ok = pcall(reaper.ImGui_Attach, ctx, font)
            if not ok then
                font = nil
            end
        end
    end

    return true
end

local footer_popup_visible = false

local function apply_item_properties_style(imgui_ctx)
    reaper.ImGui_PushStyleVar(imgui_ctx, reaper.ImGui_StyleVar_WindowRounding(), 8)
    reaper.ImGui_PushStyleVar(imgui_ctx, reaper.ImGui_StyleVar_FrameRounding(), 6)
    reaper.ImGui_PushStyleVar(imgui_ctx, reaper.ImGui_StyleVar_ItemSpacing(), 12, 6)
    reaper.ImGui_PushStyleVar(imgui_ctx, reaper.ImGui_StyleVar_WindowPadding(), 12, 10)
    reaper.ImGui_PushStyleVar(imgui_ctx, reaper.ImGui_StyleVar_FramePadding(), 8, 4)
    reaper.ImGui_PushStyleVar(imgui_ctx, reaper.ImGui_StyleVar_ScrollbarSize(), 6)

    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_WindowBg(), COLOR_BG_WINDOW)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TitleBg(), COLOR_BG_TITLE)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TitleBgActive(), COLOR_BG_TITLE_ACTIVE)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_FrameBg(), COLOR_FRAME_BG)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_FrameBgHovered(), COLOR_FRAME_BG_HOVERED)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_FrameBgActive(), COLOR_FRAME_BG_ACTIVE)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_Button(), COLOR_BG_BUTTON)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ButtonHovered(), COLOR_BG_BUTTON_HOVER)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ButtonActive(), COLOR_BG_BUTTON_ACTIVE)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_CheckMark(), COLOR_ACCENT)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_Header(), COLOR_BG_BUTTON)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_HeaderHovered(), COLOR_HEADER_HOVER)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_HeaderActive(), COLOR_HEADER_ACTIVE)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TableRowBg(), COLOR_TABLE_ROW_BG)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TableRowBgAlt(), COLOR_TABLE_ROW_BG_ALT)

    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_Border(), COLOR_BORDER)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_BorderShadow(), COLOR_BORDER_SHADOW)

    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ScrollbarBg(), COLOR_SCROLLBAR_BG)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ScrollbarGrab(), COLOR_SCROLLBAR_GRAB)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), COLOR_SCROLLBAR_GRAB_HOVERED)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ScrollbarGrabActive(), COLOR_SCROLLBAR_GRAB_ACTIVE)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ResizeGrip(), COLOR_RESIZE_GRIP)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ResizeGripHovered(), COLOR_RESIZE_GRIP_HOVERED)
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ResizeGripActive(), COLOR_RESIZE_GRIP_ACTIVE)
end
local function pop_item_properties_style(imgui_ctx)
    reaper.ImGui_PopStyleColor(imgui_ctx, 24)
    reaper.ImGui_PopStyleVar(imgui_ctx, 6)
end
local function is_macos()
    local os = reaper.GetOS and tostring(reaper.GetOS()) or ""
    return os:match("OSX") ~= nil or os:lower():match("mac") ~= nil
end
local function draw_custom_close_button(imgui_ctx)
    local frame_padding_x, frame_padding_y = reaper.ImGui_GetStyleVar(imgui_ctx, reaper.ImGui_StyleVar_FramePadding())
    frame_padding_x = tonumber(frame_padding_x) or 0
    frame_padding_y = tonumber(frame_padding_y) or 0
    local win_x, win_y = reaper.ImGui_GetWindowPos(imgui_ctx)
    local win_w, win_h = reaper.ImGui_GetWindowSize(imgui_ctx)
    if not win_x or not win_y or not win_w or not win_h then
        return false
    end
    local title_h = reaper.ImGui_GetFontSize(imgui_ctx) + (frame_padding_y * 2)
    local window_rounding = reaper.ImGui_GetStyleVar(imgui_ctx, reaper.ImGui_StyleVar_WindowRounding())
    window_rounding = tonumber(window_rounding) or 8
    local btn_size = math.max(14, math.floor(window_rounding * 1.1))
    if btn_size > title_h - 2 then
        btn_size = math.max(12, title_h - 2)
    end
    local btn_x
    local btn_y
    if is_macos() then
        local _, text_h = reaper.ImGui_CalcTextSize(imgui_ctx, "Recent Projects")
        text_h = tonumber(text_h) or reaper.ImGui_GetFontSize(imgui_ctx)
        local margin = frame_padding_y + math.floor((title_h - text_h) * 0.5)
        margin = math.max(2, margin)
        btn_x = math.floor(win_x + margin)
        btn_y = math.floor(win_y + margin)
    else
        local cx = win_x + win_w - window_rounding
        local cy = win_y + window_rounding
        btn_x = math.floor(cx - (btn_size * 0.5))
        btn_y = math.floor(cy - (btn_size * 0.5))
    end
    local clip_min_x = win_x
    local clip_min_y = win_y
    local clip_max_x = win_x + win_w
    local clip_max_y = win_y + title_h
    reaper.ImGui_PushClipRect(imgui_ctx, clip_min_x, clip_min_y, clip_max_x, clip_max_y, false)
    local pos_x, pos_y = reaper.ImGui_GetCursorPos(imgui_ctx)
    local clicked = false
    if reaper.ImGui_InvisibleButton and reaper.ImGui_DrawList_AddText then
        reaper.ImGui_SetCursorScreenPos(imgui_ctx, btn_x, btn_y)
        clicked = reaper.ImGui_InvisibleButton(imgui_ctx, "##custom_close", btn_size, btn_size)
        local hovered = reaper.ImGui_IsItemHovered(imgui_ctx)
        local draw_list = reaper.ImGui_GetWindowDrawList(imgui_ctx)
        if draw_list then
            local x1, y1 = reaper.ImGui_GetItemRectMin(imgui_ctx)
            local x2, y2 = reaper.ImGui_GetItemRectMax(imgui_ctx)
            if x1 and y1 and x2 and y2 then
                local w = x2 - x1
                local h = y2 - y1
                local cx = x1 + math.floor(w * 0.5)
                local cy = y1 + math.floor(h * 0.5)
                local mark = ICON_CLOSE or "×"
                if hovered and ICON_CLOSE_HOVER then
                    mark = ICON_CLOSE_HOVER
                end
                local font_pushed = false
                if font and reaper.ImGui_PushFont then
                    local ok_font = pcall(reaper.ImGui_PushFont, imgui_ctx, font, font_size + 4.0)
                    if ok_font then
                        font_pushed = true
                    end
                end
                local tw, th = reaper.ImGui_CalcTextSize(imgui_ctx, mark)
                local tx = cx - math.floor(tw * 0.5)
                local ty = cy - math.floor(th * 0.5)
                local col = hovered and COLOR_TEXT or COLOR_TEXT_MUTED
                reaper.ImGui_DrawList_AddText(draw_list, tx, ty, col, mark)
                if font_pushed and reaper.ImGui_PopFont then
                    pcall(reaper.ImGui_PopFont, imgui_ctx)
                end
            end
        end
    else
        reaper.ImGui_SetCursorScreenPos(imgui_ctx, btn_x, btn_y)
        reaper.ImGui_PushStyleVar(imgui_ctx, reaper.ImGui_StyleVar_FramePadding(), 4, 2)
        clicked = reaper.ImGui_SmallButton(imgui_ctx, "×##custom_close")
        reaper.ImGui_PopStyleVar(imgui_ctx, 1)
    end
    reaper.ImGui_SetCursorPos(imgui_ctx, pos_x, pos_y)
    reaper.ImGui_PopClipRect(imgui_ctx)
    return clicked
end

local function draw_gray_button(imgui_ctx, label, w, h, is_active)
    local function color_mul_rgb(color, factor)
        if reaper.ImGui_ColorConvertU32ToDouble4 and reaper.ImGui_ColorConvertDouble4ToU32 then
            local r, g, b, a = reaper.ImGui_ColorConvertU32ToDouble4(color)
            local f = tonumber(factor) or 1.0
            return reaper.ImGui_ColorConvertDouble4ToU32(r * f, g * f, b * f, a)
        end
        return color
    end

    local color_count = 0
    local btn_col = COLORS.toolbar_button_bg or COLOR_BG_BUTTON
    local hover_col = COLORS.toolbar_button_hover or COLOR_FRAME_BG_HOVERED
    local active_col = COLORS.toolbar_button_active or COLOR_FRAME_BG_ACTIVE
    local text_col = nil

    if is_active ~= nil and is_active ~= false then
        local active_style = is_active
        local label_s = tostring(label or "")
        if label_s:find("##pin_on_screen", 1, true) then
            btn_col = color_mul_rgb(playhead_marker_color, 0.65)
            hover_col = color_mul_rgb(playhead_marker_color, 0.75)
            active_col = color_mul_rgb(playhead_marker_color, 0.85)
            text_col = COLOR_TEXT_BLACK
        elseif label_s:find("##compact_view", 1, true) then
            btn_col = COLORS.toolbar_compact_button_bg or btn_col
            hover_col = COLORS.toolbar_compact_button_hover or hover_col
            active_col = COLORS.toolbar_compact_button_active or active_col
            text_col = COLOR_TEXT_BLACK
        elseif active_style == "orange" then
            btn_col = color_mul_rgb(playhead_marker_color, 0.65)
            hover_col = color_mul_rgb(playhead_marker_color, 0.75)
            active_col = color_mul_rgb(playhead_marker_color, 0.85)
            text_col = COLOR_TEXT_BLACK
        else
            btn_col = color_set_alpha(COLOR_ACCENT, 0xCC)
            hover_col = color_set_alpha(COLOR_ACCENT, 0xE0)
            active_col = color_set_alpha(COLOR_ACCENT, 0xFF)
            text_col = COLOR_TEXT_BLACK
        end
    end

    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_Button(), btn_col); color_count = color_count + 1
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ButtonHovered(), hover_col); color_count = color_count + 1
    reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ButtonActive(), active_col); color_count = color_count + 1
    if text_col ~= nil then
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_Text(), text_col); color_count = color_count + 1
    end

    local clicked
    if w ~= nil and h ~= nil then
        clicked = reaper.ImGui_Button(imgui_ctx, label, w, h)
    else
        clicked = reaper.ImGui_Button(imgui_ctx, label)
    end

    if color_count > 0 then
        reaper.ImGui_PopStyleColor(imgui_ctx, color_count)
    end
    return clicked
end

local function draw_uix_disabled_button(imgui_ctx, label, w, h)
    if w ~= nil and h ~= nil then
        reaper.ImGui_Button(imgui_ctx, label, w, h)
    else
        reaper.ImGui_Button(imgui_ctx, label)
    end
    return false
end

local function draw_transport_icon_button(imgui_ctx, id, icon_text, size, is_enabled, is_active, style)
    local btn_size = size or reaper.ImGui_GetFrameHeight(imgui_ctx)
    local x, y = reaper.ImGui_GetCursorScreenPos(imgui_ctx)
    reaper.ImGui_InvisibleButton(imgui_ctx, id, btn_size, btn_size)
    local hovered = reaper.ImGui_IsItemHovered(imgui_ctx)
    local clicked = reaper.ImGui_IsItemClicked(imgui_ctx, 0)
    local draw_list = reaper.ImGui_GetWindowDrawList(imgui_ctx)
    local col
    local open_row_style = style and style.variant == "open_row"
    if open_row_style then
        if not is_enabled then
            col = color_mul_rgb(COLOR_TEXT_MUTED, 0.85)
        elseif is_active then
            col = COLOR_TEXT_BLACK
        else
            if hovered then
                col = COLOR_TEXT_BLACK
            else
                col = color_mul_rgb(COLOR_TEXT_MUTED, 0.35)
            end
        end
    else
        if not is_enabled then
            col = COLOR_DARK_30
        elseif is_active then
            if icon_text == ICON_MDI_REPEAT then
                col = COLOR_ACCENT_GREEN
            else
                col = hovered and COLOR_ACCENT or COLOR_TEXT
            end
        else
            col = hovered and COLOR_TEXT or COLOR_TEXT_MUTED
        end
    end
    local font_pushed = false
    if font and reaper.ImGui_PushFont then
        local target_size = nil
        if icon_text == ICON_PLAY or icon_text == ICON_STOP then
            target_size = (font_size or 15.0) + 1.0
        else
            local icon_scale = 0.9
            if icon_text == ICON_MDI_REPEAT then
                icon_scale = 0.85
            end
            target_size = btn_size * icon_scale
        end
        local ok = pcall(reaper.ImGui_PushFont, imgui_ctx, font, target_size)
        if ok then
            font_pushed = true
        end
    end
    local tw, th = reaper.ImGui_CalcTextSize(imgui_ctx, icon_text)
    local tx = x + math.floor((btn_size - tw) * 0.5)
    local ty = y + math.floor((btn_size - th) * 0.5)
    if icon_text == ICON_MDI_REPEAT then
        ty = ty + 1
    end
    reaper.ImGui_DrawList_AddText(draw_list, tx, ty, col, icon_text)
    if font_pushed and reaper.ImGui_PopFont then
        pcall(reaper.ImGui_PopFont, imgui_ctx)
    end
    return clicked, hovered
end

local function get_play_control_sizes(imgui_ctx)
    local frame_h_ctrl = reaper.ImGui_GetFrameHeight(imgui_ctx)
    local ctrl_size = math.floor(frame_h_ctrl * 0.5)
    local play_size = math.max(ctrl_size, math.floor(ctrl_size * 1.15 + 0.5))
    return ctrl_size, play_size
end

local function draw_uix_slider_01(imgui_ctx, id, value, w, h, col_track, col_fill, col_thumb)
    value = clamp01(value)
    w = tonumber(w) or 0
    h = tonumber(h) or 0
    if w < 1 then w = 1 end
    if h < 1 then h = 1 end

    local x, y = reaper.ImGui_GetCursorScreenPos(imgui_ctx)
    local draw_list = reaper.ImGui_GetWindowDrawList(imgui_ctx)
    if not x or not y or not draw_list then
        reaper.ImGui_InvisibleButton(imgui_ctx, id, w, h)
        return false, value, false, false
    end

    reaper.ImGui_InvisibleButton(imgui_ctx, id, w, h)
    local hovered = false
    if reaper.ImGui_HoveredFlags_AllowWhenActive then
        hovered = reaper.ImGui_IsItemHovered(imgui_ctx, reaper.ImGui_HoveredFlags_AllowWhenActive())
    else
        hovered = reaper.ImGui_IsItemHovered(imgui_ctx)
    end
    local active = reaper.ImGui_IsItemActive(imgui_ctx)

    local changed = false
    local new_value = value
    local mx, my = reaper.ImGui_GetMousePos(imgui_ctx)
    if mx and my then
        local clicked = reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(imgui_ctx, 0) or false
        if active or clicked then
            local t = (mx - x) / w
            t = clamp01(t)
            if t ~= new_value then
                new_value = t
                changed = true
            end
        end
    end

    local track_h = math.max(4, math.floor(h * 0.32 + 0.5))
    local track_y1 = y + math.floor((h - track_h) * 0.5 + 0.5)
    local track_y2 = track_y1 + track_h
    local rounding = track_h * 0.5

    local tx1 = x
    local tx2 = x + w
    reaper.ImGui_DrawList_AddRectFilled(draw_list, tx1, track_y1, tx2, track_y2, col_track, rounding)

    local fill_x2 = x + (w * new_value)
    if fill_x2 < tx1 then fill_x2 = tx1 end
    if fill_x2 > tx2 then fill_x2 = tx2 end
    reaper.ImGui_DrawList_AddRectFilled(draw_list, tx1, track_y1, fill_x2, track_y2, col_fill, rounding)

    local thumb_r = math.max(2, math.floor(h * 0.15 + 0.5))
    local cx = fill_x2
    local cy = y + (h * 0.5)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, thumb_r, col_thumb)

    return changed, new_value, hovered, active
end

local function show_styled_tooltip(lines)
    local color_count = 0
    local var_count = 0
    if type(lines) == "string" then
        lines = { lines }
    end
    local font_pushed = false
    if font and reaper.ImGui_PushFont then
        local ok = pcall(reaper.ImGui_PushFont, ctx, font, math.max(10.0, font_size * 0.85))
        if ok then
            font_pushed = true
        end
    end
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), COLOR_TOOLTIP_BG)
    color_count = color_count + 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), COLOR_TOOLTIP_BORDER)
    color_count = color_count + 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), COLOR_TOOLTIP_TEXT)
    color_count = color_count + 1
    if reaper.ImGui_StyleVar_WindowBorderSize then
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 0.0)
        var_count = var_count + 1
    end
    if reaper.ImGui_StyleVar_PopupBorderSize then
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupBorderSize(), 0.0)
        var_count = var_count + 1
    end
    if reaper.ImGui_BeginTooltip and reaper.ImGui_EndTooltip then
        if reaper.ImGui_BeginTooltip(ctx) then
            for _, line in ipairs(lines or {}) do
                if line and line ~= "" then
                    reaper.ImGui_Text(ctx, line)
                end
            end
            reaper.ImGui_EndTooltip(ctx)
        end
    else
        local text = table.concat(lines or {}, "\n")
        reaper.ImGui_SetTooltip(ctx, text)
    end
    if var_count > 0 then
        reaper.ImGui_PopStyleVar(ctx, var_count)
    end
    if color_count > 0 then
        reaper.ImGui_PopStyleColor(ctx, color_count)
    end
    if font_pushed and reaper.ImGui_PopFont then
        pcall(reaper.ImGui_PopFont, ctx)
    end
end

local function show_delayed_tooltip(id, lines, is_hovered_override)
    if not id or id == "" then
        return
    end
    local is_hovered = is_hovered_override
    if is_hovered == nil then
        if not reaper.ImGui_IsItemHovered then
            return
        end
        is_hovered = reaper.ImGui_IsItemHovered(ctx)
    end
    if not is_hovered then
        hover_start_time[id] = nil
        hover_last_pos[id] = nil
        return
    end
    local mx, my = reaper.ImGui_GetMousePos(ctx)
    if not mx or not my then
        return
    end
    local now = reaper.time_precise()
    local moved = false
    local last = hover_last_pos[id]
    if last and (mx ~= last.x or my ~= last.y) then
        moved = true
    end
    hover_last_pos[id] = { x = mx, y = my }
    if moved or not hover_start_time[id] then
        hover_start_time[id] = now
        return
    end
    if (now - hover_start_time[id]) >= hover_delay then
        show_styled_tooltip(lines)
    end
end

local function draw_compact_view_toggle(ctx, app_state)
    local settings = app_state and app_state.settings or nil
    if not settings then
        return false
    end

    local compact_view = settings.compact_view == true
    local btn_size = math.floor(reaper.ImGui_GetFrameHeight(ctx))
    local clicked = false

    if reaper.ImGui_InvisibleButton and reaper.ImGui_DrawList_AddText then
        local pos_x, pos_y = reaper.ImGui_GetCursorScreenPos(ctx)
        clicked = reaper.ImGui_InvisibleButton(ctx, "##compact_view", btn_size, btn_size)
        local hovered = reaper.ImGui_IsItemHovered(ctx)
        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        if draw_list then
            local x1, y1 = reaper.ImGui_GetItemRectMin(ctx)
            local x2, y2 = reaper.ImGui_GetItemRectMax(ctx)
            if x1 and y1 and x2 and y2 then
                local w = x2 - x1
                local h = y2 - y1
                local cx = x1 + math.floor(w * 0.5)
                local cy = y1 + math.floor(h * 0.5)
                local mark = "☷"
                local tw, th = reaper.ImGui_CalcTextSize(ctx, mark)
                local tx = cx - math.floor(tw * 0.5)
                local ty = cy - math.floor(th * 0.5)
                local col = COLOR_META_TEXT_SECONDARY
                if compact_view or hovered then
                    col = COLOR_TEXT
                end
                reaper.ImGui_DrawList_AddText(draw_list, tx, ty, col, mark)
            end
        end
        reaper.ImGui_SetCursorScreenPos(ctx, pos_x, pos_y)
    else
        clicked = draw_gray_button(ctx, "☷##compact_view", btn_size, btn_size, compact_view)
    end

    show_delayed_tooltip("compact_view_toggle", "Compact List")

    if clicked then
        local keymods = reaper.ImGui_GetKeyMods and reaper.ImGui_GetKeyMods(ctx) or 0
        local super_mod = reaper.ImGui_Mod_Super and reaper.ImGui_Mod_Super() or 0
        local ctrl_mod = reaper.ImGui_Mod_Ctrl and reaper.ImGui_Mod_Ctrl() or 0
        local alt_mod = reaper.ImGui_Mod_Alt and reaper.ImGui_Mod_Alt() or 0
        local cmd_down = false
        if ctrl_mod ~= 0 then
            cmd_down = (keymods & ctrl_mod) ~= 0
        elseif super_mod ~= 0 then
            cmd_down = (keymods & super_mod) ~= 0
        end
        local alt_down = (alt_mod ~= 0) and ((keymods & alt_mod) ~= 0) or false

        if alt_down and ProjectList and ProjectList.show_in_file_manager then
            local history_path = (ProjectList and ProjectList.get_history_file_path_for_ui and ProjectList.get_history_file_path_for_ui()) or get_history_file_path_from_ui()
            ProjectList.show_in_file_manager(history_path)
        elseif cmd_down then
            local any_reset = false
            if ProjectList and ProjectList.reset_hint_state then
                local ok_reset = ProjectList.reset_hint_state()
                if ok_reset then
                    any_reset = true
                end
            end
            if reaper.DeleteExtState and reaper.HasExtState then
                local section = "FrenkieRecentProjects"
                local key = "observer_hint_shown_v1"
                if reaper.HasExtState(section, key) then
                    reaper.DeleteExtState(section, key, true)
                    any_reset = true
                end
            end
            if any_reset and reaper.ShowMessageBox then
                reaper.ShowMessageBox("Hints have been reset. They will be shown again.", "Frenkie Recent Projects", 0)
            end
        else
            settings.compact_view = not compact_view
            if app_state.save_settings then
                app_state.save_settings(settings)
            end
        end
    end

    return clicked
end

local function draw_projects_counter(ctx, app_state, row_x, row_y, right_x, btn_size)
    local projects = app_state and app_state.filtered_projects
    if not projects then
        return
    end
    local count = #projects
    if count <= 0 then
        return
    end
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    if not draw_list then
        return
    end
    local text = string.format("Projects: %d", count)
    local tw, th = reaper.ImGui_CalcTextSize(ctx, text)
    if not tw or not th then
        return
    end
    local gap = 8
    local tx2 = right_x - gap
    local tx = tx2 - tw
    if tx < row_x then
        tx = row_x
    end
    local ty = row_y + math.floor((btn_size - th) * 0.5)
    reaper.ImGui_DrawList_AddText(draw_list, tx, ty, COLOR_FOOTER_TEXT_MUTED, text)
end

local function format_time_open_work(sec)
    if sec == nil or sec < 0 then return "0m 0s" end
    sec = math.floor(tonumber(sec) + 0.5)
    if sec < 60 then
        return string.format("%ds", sec)
    elseif sec < 3600 then
        local m = math.floor(sec / 60)
        local s = sec % 60
        return s > 0 and string.format("%dm %ds", m, s) or string.format("%dm", m)
    else
        local h = math.floor(sec / 3600)
        local m = math.floor((sec % 3600) / 60)
        local s = sec % 60
        if m == 0 and s == 0 then
            return string.format("%dh", h)
        elseif s == 0 then
            return string.format("%dh %dm", h, m)
        else
            return string.format("%dh %dm %ds", h, m, s)
        end
    end
end

local function draw_project_meta_panel(imgui_ctx, draw_list, x1, y1, x2, y2, meta, project)
    if not meta or not draw_list then return end
    local pad_x = 12
    local pad_y_top = 10
    local pad_y_bottom = 6
    local line_h = reaper.ImGui_GetTextLineHeight(imgui_ctx)
    local label_x = x1 + pad_x
    local cur_y = y1 + pad_y_top

    local song_len = nil
    if meta.song_length_sec and meta.song_length_sec > 0 then
        local s = math.floor(meta.song_length_sec + 0.5)
        local m = math.floor(s / 60)
        local r = s % 60
        song_len = string.format("%d:%02d", m, r)
    end

    local timebase_str = nil
    if meta.timebase_mode ~= nil then
        local tb = tonumber(meta.timebase_mode) or 0
        if tb == 0 then
            timebase_str = "Time"
        elseif tb == 1 then
            timebase_str = "Beats (position, length, rate)"
        elseif tb == 2 then
            timebase_str = "Beats (position only)"
        else
            timebase_str = tostring(tb)
        end
    end

    local bpm_str = nil
    if meta.bpm and meta.bpm > 0 then
        bpm_str = string.format("%.2f", meta.bpm)
    end

    local tracks_str = nil
    if meta.tracks_count and meta.tracks_count > 0 then
        tracks_str = tostring(meta.tracks_count)
    end

    local has_video_str = nil
    if meta.has_video ~= nil then
        has_video_str = meta.has_video and "Yes" or "No"
    end

    local function val_or_empty(v)
        if v == nil or v == "" then
            return "Empty"
        end
        return tostring(v)
    end

    local function build_copy_text()
        local lines = {}
        local function add(label, value)
            lines[#lines + 1] = label .. ": " .. val_or_empty(value)
        end

        add("Project Title", meta.notes_title)
        add("Project Author", meta.notes_author)
        add("Video Track", has_video_str)
        add("Project Notes", meta.notes_body)
        add("Song Length", song_len)
        add("Timebase", timebase_str)
        add("BPM", bpm_str)
        add("Tracks count", tracks_str)
        if project then
            local open_sec = tonumber(project.total_open_sec) or 0
            local work_sec = tonumber(project.total_work_sec) or 0
            add("Time open", format_time_open_work(open_sec))
            add("Work time", format_time_open_work(work_sec))
            add("Idle time", format_time_open_work(math.max(0, open_sec - work_sec)))
        end

        return table.concat(lines, "\n")
    end

    local col_gap = 40
    local content_w = math.max(0, (x2 - x1) - pad_x * 2)
    local col_w = math.floor((content_w - col_gap) * 0.5)
    if col_w < 40 then col_w = 40 end
    local label_x_left = label_x
    local label_x_right = label_x_left + col_w + col_gap
    local cur_y_left = cur_y
    local cur_y_right = cur_y

    local function draw_row(column, label, value)
        local row_y = column == 1 and cur_y_left or cur_y_right
        local lx = column == 1 and label_x_left or label_x_right
        local label_text = label .. ":"
        local label_w = select(1, reaper.ImGui_CalcTextSize(imgui_ctx, label_text)) or 0
        local value_x = lx + label_w + 8
        local max_value_w = col_w - (label_w + 8)
        if max_value_w < 0 then max_value_w = 0 end
        reaper.ImGui_DrawList_AddText(draw_list, lx, row_y, COLOR_META_TEXT_SECONDARY, label_text)
        local v = val_or_empty(value)
        local lines = (wrap_text_to_width and wrap_text_to_width(imgui_ctx, v, max_value_w)) or { v }
        if #lines == 0 then
            lines = { "" }
        end
        for i = 1, #lines do
            local vy = row_y + (i - 1) * line_h
            reaper.ImGui_DrawList_AddText(draw_list, value_x, vy, COLOR_TEXT, lines[i])
        end
        local row_h = line_h * math.max(1, #lines)
        if column == 1 then
            cur_y_left = row_y + row_h
        else
            cur_y_right = row_y + row_h
        end
    end

    draw_row(1, "Project Title", meta.notes_title)
    draw_row(1, "Project Author", meta.notes_author)
    draw_row(1, "Video Track", has_video_str)
    draw_row(1, "Project Notes", meta.notes_body)
    draw_row(1, "Song Length", song_len)
    draw_row(1, "Timebase", timebase_str)
    draw_row(2, "BPM", bpm_str)
    draw_row(2, "Tracks count", tracks_str)
    if project then
        local open_sec = tonumber(project.total_open_sec) or 0
        local work_sec = tonumber(project.total_work_sec) or 0
        local idle_sec = math.max(0, open_sec - work_sec)
        draw_row(2, "Time open", format_time_open_work(open_sec))
        draw_row(2, "Work time", format_time_open_work(work_sec))
        draw_row(2, "Idle time", format_time_open_work(idle_sec))
    end

    cur_y = math.max(cur_y_left, cur_y_right) + pad_y_bottom

    if project then
        local regions = meta.regions
        local duration = meta.song_length_sec

        local tl_x = x1 + pad_x
        local tl_w = math.max(0, (x2 - x1) - pad_x * 2)
        local tl_h = math.floor(line_h * 1.8)
        local bottom_limit_y = y2 - pad_y_bottom
        local free_h = bottom_limit_y - cur_y
        if free_h < tl_h then
            tl_h = math.max(6, free_h)
        end
        local bottom_gap = math.floor(line_h * 0.40)
        if bottom_gap < pad_y_bottom then bottom_gap = pad_y_bottom end
        local tl_y = bottom_limit_y - bottom_gap - tl_h
        if tl_y < cur_y then tl_y = cur_y end

        local timeline_min = 0.0
        local timeline_span = duration
        local timeline_origin = 0.0
        local span_start = meta.regions_span_start
        local span_end = meta.regions_span_end
        if span_start and span_end and span_end > span_start then
            timeline_min = span_start
            timeline_origin = span_start
            timeline_span = span_end - span_start
        end

        if tl_w > 10 and tl_h > 6 and draw_player_timeline and regions and timeline_span and timeline_span > 0 then
            local tl_id = "##meta_regions"
            if project then
                local p = project.full_path or project.path or ""
                if p ~= "" then
                    tl_id = tl_id .. "_" .. normalize_path(p)
                end
            end
            draw_player_timeline(imgui_ctx, draw_list, tl_id, tl_x, tl_y, tl_w, tl_h, {
                is_enabled = true,
                preview_path = nil,
                regions = regions,
                timeline_min = timeline_min,
                timeline_span = timeline_span,
                timeline_origin = timeline_origin,
                status = nil,
                is_playing = false,
            })
        end
    end

    do
        local panel_w = math.max(0, x2 - x1)
        local panel_h = math.max(0, y2 - y1)
        if panel_w > 0 and panel_h > 0 and reaper.ImGui_InvisibleButton and reaper.ImGui_BeginPopupContextItem then
            local ctx_id = "##meta_panel_ctx"
            if project then
                local p = project.full_path or project.path or ""
                if p ~= "" then
                    ctx_id = ctx_id .. "_" .. normalize_path(p)
                end
            end
            reaper.ImGui_SetCursorScreenPos(imgui_ctx, x1, y1)
            reaper.ImGui_InvisibleButton(imgui_ctx, ctx_id, panel_w, panel_h)
            if reaper.ImGui_BeginPopupContextItem(imgui_ctx, ctx_id) then
                if reaper.ImGui_MenuItem(imgui_ctx, "Copy Metadata") then
                    local text = build_copy_text()
                    if text ~= "" and reaper.ImGui_SetClipboardText then
                        reaper.ImGui_SetClipboardText(imgui_ctx, text)
                    end
                end
                reaper.ImGui_EndPopup(imgui_ctx)
            end
        end
    end

    if reaper.ImGui_DrawList_AddRectFilledMultiColor then
        local shadow_h = math.min(12, math.floor((y2 - y1) * 0.25))
        if shadow_h > 0 then
            local top_y1 = y1
            local top_y2 = y1 + shadow_h
            reaper.ImGui_DrawList_AddRectFilledMultiColor(
                draw_list,
                x1, top_y1, x2, top_y2,
                COLOR_BLACK_BG_SOFT, COLOR_BLACK_BG_SOFT,
                COLOR_BLACK_TRANSPARENT, COLOR_BLACK_TRANSPARENT
            )
            local bottom_y1 = y2 - shadow_h
            local bottom_y2 = y2
            reaper.ImGui_DrawList_AddRectFilledMultiColor(
                draw_list,
                x1, bottom_y1, x2, bottom_y2,
                COLOR_BLACK_TRANSPARENT, COLOR_BLACK_TRANSPARENT,
                COLOR_BLACK_BG_SOFT, COLOR_BLACK_BG_SOFT
            )
        end
    end
end

local function native_to_u32_alpha(color, alpha)
    local v = tonumber(color) or 0
    v = v % 0x1000000
    local r, g, b = reaper.ColorFromNative(v)
    if not r or not g or not b or v == 0 then
        return reaper.ImGui_ColorConvertDouble4ToU32(0.38, 0.38, 0.38, alpha or 1)
    end
    return reaper.ImGui_ColorConvertDouble4ToU32(r / 255, g / 255, b / 255, alpha or 1)
end

local function native_to_u32_alpha_mix_to_white(color, alpha, mix)
    local v = tonumber(color) or 0
    v = v % 0x1000000
    local r, g, b = reaper.ColorFromNative(v)
    local rr, gg, bb = 0.38, 0.38, 0.38
    if r and g and b and v ~= 0 then
        rr = r / 255
        gg = g / 255
        bb = b / 255
    end
    local m = tonumber(mix) or 0.3
    if m < 0 then m = 0 end
    if m > 1 then m = 1 end
    rr = (rr * m) + (1.0 - m)
    gg = (gg * m) + (1.0 - m)
    bb = (bb * m) + (1.0 - m)
    local ceil_v = 0.96
    if rr > ceil_v then rr = ceil_v end
    if gg > ceil_v then gg = ceil_v end
    if bb > ceil_v then bb = ceil_v end
    return reaper.ImGui_ColorConvertDouble4ToU32(rr, gg, bb, alpha or 1)
end

local function _srgb_lin_byte(c)
    local s = (tonumber(c) or 0) / 255.0
    if s <= 0.03928 then return s / 12.92 end
    return ((s + 0.055) / 1.055) ^ 2.4
end

local function should_use_black_text(r_val, g_val, b_val)
    local L = 0.2126 * _srgb_lin_byte(r_val) + 0.7152 * _srgb_lin_byte(g_val) + 0.0722 * _srgb_lin_byte(b_val)
    return L >= 0.179
end

local function region_label_color_for_native(native_color, default_u32)
    local v = tonumber(native_color) or 0
    v = v % 0x1000000
    if v == 0 then return default_u32 end
    local r, g, b = reaper.ColorFromNative(v)
    if not r or not g or not b then return default_u32 end
    if should_use_black_text(r, g, b) then return COLOR_TEXT_BLACK end
    return COLOR_TEXT_INVERTED
end

local function regroup_filtered_projects(app_state)
    if ProjectList and ProjectList.rebuild_filtered_projects then
        ProjectList.rebuild_filtered_projects(app_state)
    end
end

local function is_digits_only(s)
    s = tostring(s or "")
    if s == "" then return false end
    return s:match("^%d+$") ~= nil
end

local function find_project_by_preview_path(app_state, preview_path)
    local needle = normalize_path(preview_path)
    if needle == "" then return nil end
    local projects = (app_state and app_state.projects) or {}
    for _, p in ipairs(projects) do
        local pp = p and p.preview_path
        if pp and normalize_path(pp) == needle then
            return p
        end
    end
    return nil
end

local function get_preview_path_for_project(project)
    if not project then return nil end
    if project.preview_path and project.preview_path ~= "" then
        return project.preview_path
    end
    if ProjectList and ProjectList.get_preview_path then
        return ProjectList.get_preview_path(project.full_path or project.path)
    end
    return nil
end

local function get_duration_cached(preview_path)
    if not preview_path or preview_path == "" then return nil end
    local d = durations_cache[preview_path]
    if d then return d end
    if ProjectList and ProjectList.get_preview_duration then
        d = ProjectList.get_preview_duration(preview_path)
        durations_cache[preview_path] = d
        return d
    end
    return nil
end

compute_timeline = function(regions, duration, status)
    local timeline_min = 0.0
    local timeline_span = nil
    local timeline_origin = 0.0
    local start_t = nil
    local end_t = nil
    local dur = tonumber(duration)
    if (not dur or dur <= 0) and status and status.duration then
        dur = tonumber(status.duration)
    end
    if dur and dur <= 0 then dur = nil end

    if regions then
        for _, r in ipairs(regions) do
            if r and r.start ~= nil then
                local nm = r.name or ""
                if nm ~= "" and string.sub(nm, 1, 1) == "=" then
                    local u = string.upper(nm)
                    if u == "=START" and start_t == nil then
                        start_t = r.start
                    elseif u == "=END" and start_t ~= nil and end_t == nil and r.start > start_t then
                        end_t = r.start
                        break
                    end
                end
            end
        end
    end

    if start_t ~= nil then
        timeline_origin = start_t
        timeline_min = start_t
        if end_t ~= nil and end_t > start_t then
            timeline_span = end_t - start_t
        elseif dur then
            timeline_span = dur
        end
    elseif dur then
        timeline_span = dur
    end

    if timeline_span and dur then
        timeline_span = math.min(timeline_span, dur)
    end

    return timeline_min, timeline_span, timeline_origin
end

draw_timeline = function(ctx, draw_list, id, x, y, w, h, opts)
    if not draw_list then return end
    opts = opts or {}

    local st = get_timeline_state(id)

    local is_enabled = opts.is_enabled == true
    local preview_path = opts.preview_path
    local regions = opts.regions
    local timeline_min = opts.timeline_min or 0.0
    local timeline_span = opts.timeline_span
    local timeline_origin = opts.timeline_origin or 0.0
    local ratio_play = opts.ratio_play or 0.0
    local status = opts.status
    local is_playing = opts.is_playing

    local tooltip_key = opts.tooltip_key or tostring(id or "timeline")
    local radius = tonumber(opts.radius) or 3
    local snap_mode = tostring(opts.snap_mode or "start")

    local tooltip_snap_tol = tonumber(opts.tooltip_snap_tol)
    local click_snap_tol = tonumber(opts.click_snap_tol)
    local hover_snap_tol = tonumber(opts.hover_snap_tol)

    local enable_hover_snap = opts.enable_hover_snap == true
    local enable_tooltip_inside_region = opts.enable_tooltip_inside_region == true

    local draw_play_fill = opts.draw_play_fill == true
    local show_playhead = opts.show_playhead ~= false
    local show_nav_line = opts.show_nav_line == true
    local draw_region_blocks = opts.draw_region_blocks == true
    local draw_region_separators = opts.draw_region_separators == true
    local separator_style = tostring(opts.separator_style or "solid")
    local draw_waveform = opts.draw_waveform == true
    local draw_marker_labels = opts.draw_marker_labels == true
    local draw_region_labels = opts.draw_region_labels == true
    local show_no_preview_label = opts.show_no_preview_label == true
    local seek_override_duration = tonumber(opts.seek_override_duration) or 0.12

    local is_map_only = (opts.is_map_only == nil and ((not preview_path) and (not is_playing))) or (opts.is_map_only == true)

    local hit_margin_factor = tonumber(opts.hit_margin_factor) or 0.25
    local hit_margin = math.max(2, math.floor(h * hit_margin_factor))
    local hit_y = y - hit_margin
    local hit_h = h + (hit_margin * 2)
    reaper.ImGui_SetCursorScreenPos(ctx, x, hit_y)
    reaper.ImGui_InvisibleButton(ctx, id, w, hit_h)
    local x1 = reaper.ImGui_GetItemRectMin(ctx)
    local x2 = select(1, reaper.ImGui_GetItemRectMax(ctx))
    local mx = select(1, reaper.ImGui_GetMousePos(ctx))
    local hover_ratio = nil

    if is_enabled and reaper.ImGui_IsItemHovered(ctx) and timeline_span and timeline_span > 0 then
        local ratio_hover = math.max(0.0, math.min(1.0, (mx - x1) / math.max(1, (x2 - x1))))
        hover_ratio = ratio_hover
        local t = timeline_min + (timeline_span * ratio_hover)
        local mode = regions and regions.timemode_mode
        local fps = regions and regions.timemode_fps
        local tip = (format_time_mmss and format_time_mmss(t, mode, fps)) or ""
        local hit_name = nil

        if regions then
            local tol = tooltip_snap_tol or 6
            local timeline_end = timeline_min + timeline_span
            local best_named_dx, best_named_nm = nil, nil
            local function consider_snap_point(at_t, nm)
                if at_t ~= nil and at_t >= timeline_min and at_t <= timeline_end then
                    local s = math.max(0.0, math.min(timeline_span, (at_t - timeline_min)))
                    local rx = x1 + ((x2 - x1) * (s / timeline_span))
                    local dx = math.abs(mx - rx)
                    nm = nm or ""
                    if nm ~= "" and dx <= tol and (best_named_dx == nil or dx < best_named_dx) then
                        best_named_dx = dx
                        best_named_nm = nm
                    end
                end
            end

            for _, r in ipairs(regions) do
                local nm = r.name or ""
                if snap_mode == "start" then
                    if r.start then
                        consider_snap_point(r.start, nm)
                    end
                else
                    if r.start and r.finish == nil then
                        consider_snap_point(r.start, nm)
                    elseif r.start ~= nil and r.finish ~= nil and r.finish > r.start then
                        consider_snap_point(r.start, nm)
                        consider_snap_point(r.finish, nm)
                    elseif r.start then
                        consider_snap_point(r.start, nm)
                    end
                end
            end

            if best_named_nm then
                hit_name = best_named_nm
            elseif enable_tooltip_inside_region then
                for _, r in ipairs(regions) do
                    local nm = r.name or ""
                    if nm ~= "" and r.start ~= nil and r.finish ~= nil and t >= r.start and t <= r.finish then
                        hit_name = nm
                        break
                    end
                end
            end

            if enable_hover_snap and w > 0 then
                local tol = hover_snap_tol or 10
                local best_dx = nil
                local best_ratio = nil
                local timeline_end = timeline_min + timeline_span
                local function consider_snap_point(at_t)
                    if at_t ~= nil and at_t >= timeline_min and at_t <= timeline_end then
                        local s = math.max(0.0, math.min(timeline_span, (at_t - timeline_min)))
                        local xrf = x1 + ((x2 - x1) * (s / timeline_span))
                        local xr = math.floor(xrf + 0.0)
                        local dx = math.abs(mx - xr)
                        if dx <= tol and (best_dx == nil or dx < best_dx) then
                            best_dx = dx
                            best_ratio = math.max(0.0, math.min(1.0, (s / timeline_span)))
                        end
                    end
                end
                for _, r in ipairs(regions) do
                    if snap_mode == "start" then
                        if r.start then
                            consider_snap_point(r.start)
                        end
                    else
                        if r.start and r.finish == nil then
                            consider_snap_point(r.start)
                        elseif r.start ~= nil and r.finish ~= nil and r.finish > r.start then
                            consider_snap_point(r.start)
                            consider_snap_point(r.finish)
                        elseif r.start then
                            consider_snap_point(r.start)
                        end
                    end
                end
                if best_ratio ~= nil then
                    hover_ratio = best_ratio
                end
            end
        end

        if hit_name then
            tip = tip .. "\n" .. hit_name
        end
        show_delayed_tooltip(tooltip_key, tip, true)
    end

    local clicked_timeline = is_enabled and reaper.ImGui_IsItemClicked(ctx, 0)
    if clicked_timeline and regions and timeline_span and timeline_span > 0 and w > 0 then
        local tol = click_snap_tol or 10
        local best_dx = nil
        local best_ratio = nil
        local best_x = nil
        local timeline_end = timeline_min + timeline_span
        local function consider_snap_point(at_t)
            if at_t ~= nil and at_t >= timeline_min and at_t <= timeline_end then
                local s = math.max(0.0, math.min(timeline_span, (at_t - timeline_min)))
                local xrf = x1 + ((x2 - x1) * (s / timeline_span))
                local xr = math.floor(xrf + 0.0)
                local dx = math.abs(mx - xr)
                if dx <= tol and (best_dx == nil or dx < best_dx) then
                    best_dx = dx
                    best_ratio = math.max(0.0, math.min(1.0, (s / timeline_span)))
                    best_x = xr
                end
            end
        end

        for _, r in ipairs(regions) do
            if snap_mode == "start" then
                if r.start then
                    consider_snap_point(r.start)
                end
            else
                if r.start and r.finish == nil then
                    consider_snap_point(r.start)
                elseif r.start ~= nil and r.finish ~= nil and r.finish > r.start then
                    consider_snap_point(r.start)
                    consider_snap_point(r.finish)
                elseif r.start then
                    consider_snap_point(r.start)
                end
            end
        end

        if best_ratio ~= nil then
            st.scrub_snap_active = true
            st.scrub_snap_ratio = best_ratio
            st.scrub_snap_x = best_x or 0
            st.scrub_snap_tol = tol
            st.scrub_ratio = best_ratio
            st.is_scrubbing = true
        else
            st.scrub_snap_active = false
        end
    end

    if is_enabled and reaper.ImGui_IsItemActive(ctx) then
        local ratio = nil
        if st.scrub_snap_active and math.abs(mx - (st.scrub_snap_x or 0)) <= (st.scrub_snap_tol or 0) then
            ratio = st.scrub_snap_ratio
        else
            st.scrub_snap_active = false
            ratio = (mx - x1) / math.max(1, (x2 - x1))
        end
        st.scrub_ratio = math.max(0.0, math.min(1.0, ratio))
        st.is_scrubbing = true
    elseif is_enabled and st.is_scrubbing and reaper.ImGui_IsMouseReleased(ctx, 0) then
        if opts.on_seek and timeline_span and timeline_span > 0 then
            local seek_t = timeline_min + (timeline_span * (st.scrub_ratio or 0.0))
            local seek_pos = seek_t - timeline_origin
            if seek_pos < 0 then seek_pos = 0 end
            opts.on_seek(seek_pos, st.scrub_ratio)
            set_timeline_seek_override(id, st.scrub_ratio, reaper.time_precise() + seek_override_duration)
        end
        st.scrub_snap_active = false
        st.is_scrubbing = false
    end

    local now = reaper.time_precise()
    local has_override = (st.seek_override_ratio ~= nil) and (now < (st.seek_override_until or 0.0))

    local bg_col = is_enabled and COLOR_TIMELINE_BG_ENABLED or COLOR_TIMELINE_BG_DISABLED
    if tooltip_key and type(tooltip_key) == "string" then
        if tooltip_key:sub(1, 9) == "row_seek_" then
            bg_col = COLOR_FOOTER_POPUP_BG
        end
    end
    reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h, bg_col, radius)

    local ratio_playback = 0.0
    if (not is_map_only) and timeline_span and timeline_span > 0 and is_enabled and is_playing and status and status.elapsed then
        ratio_playback = math.min(1.0, math.max(0.0, (((status.elapsed or 0) + (timeline_origin or 0.0)) - (timeline_min or 0.0)) / timeline_span))
    end
    local played_x = x + math.floor(w * ratio_playback)

    if draw_play_fill and is_enabled and timeline_span and timeline_span > 0 then
        local ratio = ratio_play or 0.0
        if st.is_scrubbing then
            ratio = st.scrub_ratio
        elseif has_override then
            ratio = st.seek_override_ratio
        end
        local px = x + math.floor(w * math.max(0.0, math.min(1.0, ratio)))
        if px > x then
            reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, px, y + h, COLOR_TIMELINE_PLAYBAR_FILL, radius)
        end
        if show_playhead then
            reaper.ImGui_DrawList_AddLine(draw_list, px, y, px, y + h, playhead_marker_color, 1.0)
        end
    end

    if draw_region_blocks and regions and timeline_span and timeline_span > 0 then
        local timeline_end = timeline_min + timeline_span
        for _, r in ipairs(regions) do
            if r.finish and r.start and r.finish > r.start and r.finish > timeline_min and r.start < timeline_end then
                local s = math.max(0.0, math.min(timeline_span, (r.start - timeline_min)))
                local e = math.max(0.0, math.min(timeline_span, (r.finish - timeline_min)))
                if e > s then
                    local x1f = x + (w * (s / timeline_span))
                    local x2f = x + (w * (e / timeline_span))
                    local rx1 = math.max(x, math.floor(x1f + 0.0))
                    local rx2 = math.min(x + w, math.floor(x2f + 0.999))
                    if rx2 <= rx1 then rx2 = rx1 + 1 end
                    if is_map_only then
                        local col = native_to_u32_alpha(r.color or 0, 1.0)
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, rx1, y, rx2, y + h, col, radius)
                        reaper.ImGui_DrawList_AddRect(draw_list, rx1 + 0.5, y + 0.5, rx2 - 0.5, y + h - 0.5, col, radius)
                    else
                        local col_dim = native_to_u32_alpha(r.color or 0, 0.35)
                        local col_full = native_to_u32_alpha(r.color or 0, 1.0)
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, rx1, y, rx2, y + h, col_dim)
                        if is_enabled and is_playing and played_x > rx1 then
                            local rx2p = math.min(rx2, played_x)
                            if rx2p > rx1 then
                                reaper.ImGui_DrawList_AddRectFilled(draw_list, rx1, y, rx2p, y + h, col_full)
                            end
                        end
                    end
                end
            end
        end
    end

    if draw_region_separators and regions and timeline_span and timeline_span > 0 then
        local timeline_end = timeline_min + timeline_span
        local sep_col = COLOR_TIMELINE_REGION_SEPARATOR
        local line_top = y + 1
        local line_bottom = y + h - 1
        if line_bottom <= line_top then line_bottom = line_top + 1 end
        if separator_style == "dashed" then
            if not is_map_only then
                local segment_h = 4
                local gap_h = 4
                for _, r in ipairs(regions) do
                    if r.start and r.start >= timeline_min and r.start <= timeline_end then
                        local s = math.max(0.0, math.min(timeline_span, (r.start - timeline_min)))
                        local rx = x + math.floor(w * (s / timeline_span))
                        local yy = line_top
                        while yy < line_bottom do
                            local y_end = yy + segment_h
                            if y_end > line_bottom then y_end = line_bottom end
                            reaper.ImGui_DrawList_AddLine(draw_list, rx, yy, rx, y_end, sep_col, 1.0)
                            yy = yy + segment_h + gap_h
                        end
                    end
                end
            end
        else
            for _, r in ipairs(regions) do
                if r.start and r.start >= timeline_min and r.start <= timeline_end then
                    local s = math.max(0.0, math.min(timeline_span, (r.start - timeline_min)))
                    local rx = x + math.floor(w * (s / timeline_span))
                    reaper.ImGui_DrawList_AddLine(draw_list, rx, line_top, rx, line_bottom, sep_col, 1.0)
                end
            end
        end
    end

    local wf_cols = nil
    local wf_mid_y = nil
    local wf_hh_by_i = nil
    local wf_dbg = nil
    if draw_waveform and is_enabled and preview_path and ProjectList and ProjectList.get_preview_waveform_for_span and timeline_span and timeline_span > 0 and w > 10 and h > 10 then
        local cols = nil
        if ProjectList.waveform_full_test then
            local pr = tonumber(ProjectList.waveform_full_peakrate) or 2000
            if pr < 1 then pr = 1 end
            cols = math.floor(timeline_span * pr)
        else
            cols = math.floor(w)
            if cols < 1 then cols = 1 end
            if cols > 2048 then cols = 2048 end
        end
        local wf = nil
        wf, wf_dbg = ProjectList.get_preview_waveform_for_span(preview_path, cols, timeline_span, timeline_min or 0.0, timeline_origin or 0.0)
        if wf and wf.peaks and wf.columns and wf.columns > 0 then
            cols = wf.columns
            local peaks = wf.peaks
            local mid_y = y + math.floor(h / 2)
            local half_h = math.max(1, math.floor((h - 2) / 2))
            local col_by_i = nil
            if regions and timeline_span and timeline_span > 0 then
                col_by_i = {}
                local timeline_end = timeline_min + timeline_span
                for _, r in ipairs(regions) do
                    if r.finish and r.start and r.finish > r.start and r.finish > timeline_min and r.start < timeline_end then
                        local s = math.max(0.0, math.min(timeline_span, (r.start - timeline_min)))
                        local e = math.max(0.0, math.min(timeline_span, (r.finish - timeline_min)))
                        if e > s then
                            local xr1 = (s / timeline_span)
                            local xr2 = (e / timeline_span)
                            local i1 = math.max(1, math.min(cols, math.floor((cols * xr1) + 1)))
                            local i2 = math.max(1, math.min(cols, math.ceil((cols * xr2))))
                            if i2 >= i1 then
                                local col = native_to_u32_alpha_mix_to_white(r.color or 0, 0.32, 0.28)
                                for ii = i1, i2 do
                                    col_by_i[ii] = col
                                end
                            end
                        end
                    end
                end
            end
            local fallback_col = reaper.ImGui_ColorConvertDouble4ToU32(0.86, 0.86, 0.86, 0.35)
            wf_cols = cols
            wf_mid_y = mid_y
            wf_hh_by_i = {}
            for ii = 1, cols do
                local amp_raw = tonumber(peaks[ii]) or 0.0
                if amp_raw < 0 then amp_raw = 0 end
                local amp = amp_raw
                if amp <= 1.0 then
                    amp = math.sqrt(amp)
                else
                    amp = 1.0 - math.exp(-amp)
                end
                local hh = math.floor((amp * half_h) + 0.5)
                if hh < 1 and amp_raw > 0 then hh = 1 end
                wf_hh_by_i[ii] = hh
                if hh > 0 then
                    local px = x + math.floor((w * (ii - 0.5)) / cols)
                    if px < x then px = x end
                    if px > x + w - 1 then px = x + w - 1 end
                    local py1 = mid_y - hh
                    local py2 = mid_y + hh
                    if py1 < y then py1 = y end
                    if py2 > y + h then py2 = y + h end
                    if py2 > py1 then
                        local col = (col_by_i and col_by_i[ii]) or fallback_col
                        reaper.ImGui_DrawList_AddLine(draw_list, px, py1, px, py2, col, 1.0)
                    end
                end
            end
        end
    end

    if (not wf_cols) and wf_dbg and (tonumber(wf_dbg.buildpeaks) == 1) then
        local mid_y = y + math.floor(h / 2)
        reaper.ImGui_DrawList_AddLine(draw_list, x, mid_y, x + w, mid_y, COLOR_WHITE_LINE, 1.0)
    end

    if show_nav_line and is_enabled and timeline_span and timeline_span > 0 then
        local nav_ratio = nil
        if st.is_scrubbing then
            nav_ratio = st.scrub_ratio
        elseif has_override then
            nav_ratio = st.seek_override_ratio
        elseif hover_ratio ~= nil then
            nav_ratio = hover_ratio
        end
        if nav_ratio ~= nil then
            nav_ratio = math.max(0.0, math.min(1.0, nav_ratio))
            local nav_x = x + math.floor(w * nav_ratio)
            if nav_x ~= played_x then
                local a = playhead_marker_color & 0xFF
                local ha = math.floor((a * 0.5) + 0.5)
                local col = (playhead_marker_color & 0xFFFFFF00) | ha
                reaper.ImGui_DrawList_AddLine(draw_list, nav_x, y, nav_x, y + h, col, 1.0)
            end
        end
    end

    if show_playhead and (not is_map_only) and is_enabled and (not draw_play_fill) then
        reaper.ImGui_DrawList_AddLine(draw_list, played_x, y, played_x, y + h, playhead_marker_color, 1.0)
    end

    if draw_marker_labels and regions and timeline_span and timeline_span > 0 then
        local label_font_pushed = false
        if font then
            local ok = pcall(reaper.ImGui_PushFont, ctx, font, math.max(10.0, font_size * 0.80))
            if ok then
                label_font_pushed = true
            end
        end
        local marker_items = {}
        local timeline_end = timeline_min + timeline_span
        for _, r in ipairs(regions) do
            if r.start and r.start >= timeline_min and r.start <= timeline_end then
                local nm = r.name or ""
                if nm ~= "" and (not is_digits_only(nm)) and (nm:sub(1, 1) ~= "=") then
                    marker_items[#marker_items + 1] = r
                end
            end
        end
        table.sort(marker_items, function(a, b)
            return (tonumber(a.start) or 0) < (tonumber(b.start) or 0)
        end)
        for idx, r in ipairs(marker_items) do
            local nm = r.name or ""
            local s = math.max(0.0, math.min(timeline_span, (r.start - timeline_min)))
            local rx = x + math.floor(w * (s / timeline_span))
            local next_start_x = nil
            local next_r = marker_items[idx + 1]
            if next_r and next_r.start ~= nil then
                local ns = math.max(0.0, math.min(timeline_span, (next_r.start - timeline_min)))
                local nsf = x + (w * (ns / timeline_span))
                next_start_x = math.max(x, math.min(x + w, math.floor(nsf + 0.0)))
            end
            local pad = 4
            local right_limit = x + w
            if next_start_x ~= nil then
                right_limit = math.min(right_limit, next_start_x)
            end
            local max_w_seg = (right_limit - rx) - pad * 2
            if max_w_seg > 6 then
                local stext = (fit_text_to_width and fit_text_to_width(ctx, nm, max_w_seg)) or ""
                if stext ~= "" then
                    local _, th = reaper.ImGui_CalcTextSize(ctx, stext)
                    local lx = rx + pad
                    local ly = y + math.floor((h - th) / 2)
                    if ly < y then ly = y end
                    if ly + th > y + h then
                        ly = y + math.max(0, math.floor(h - th))
                    end
                    reaper.ImGui_DrawList_AddText(draw_list, lx, ly, current_region_label_color, stext)
                end
            end
        end
        if label_font_pushed then
            pcall(reaper.ImGui_PopFont, ctx)
        end
    end

    if draw_region_labels and regions and timeline_span and timeline_span > 0 then
        local label_font_pushed = false
        if font then
            local ok = pcall(reaper.ImGui_PushFont, ctx, font, math.max(10.0, font_size * 0.80))
            if ok then
                label_font_pushed = true
            end
        end
        local region_items = {}
        local timeline_end = timeline_min + timeline_span
        for _, r in ipairs(regions) do
            if r.finish and r.start and r.finish > r.start and r.finish > timeline_min and r.start < timeline_end then
                region_items[#region_items + 1] = r
            end
        end
        for _, r in ipairs(region_items) do
            local nm = r.name or ""
            local s = math.max(0.0, math.min(timeline_span, (r.start - timeline_min)))
            local e = math.max(0.0, math.min(timeline_span, (r.finish - timeline_min)))
            if e > s then
                local x1f = x + (w * (s / timeline_span))
                local x2f = x + (w * (e / timeline_span))
                local rx1 = math.max(x, math.floor(x1f + 0.0))
                local rx2 = math.min(x + w, math.floor(x2f + 0.999))
                if rx2 <= rx1 then rx2 = rx1 + 1 end
                if nm ~= "" then
                    local pad = 4
                    local right_limit = rx2
                    local max_w_seg = (right_limit - rx1) - pad * 2
                    if max_w_seg > 2 then
                        local stext = (fit_text_to_width and fit_text_to_width(ctx, nm, max_w_seg)) or ""
                        if stext ~= "" then
                            local tw, th = reaper.ImGui_CalcTextSize(ctx, stext)
                            local lx = rx1 + pad
                            local ly = y + math.floor((h - th) / 2)
                            local text_col = nil
                            local use_black = false
                            if wf_cols and wf_mid_y and wf_hh_by_i and w > 0 then
                                local tx1 = lx
                                local tx2 = lx + tw
                                local i1 = math.floor(((tx1 - x) / w) * wf_cols) + 1
                                local i2 = math.ceil(((tx2 - x) / w) * wf_cols) + 1
                                if i1 < 1 then i1 = 1 end
                                if i2 > wf_cols then i2 = wf_cols end
                                if i2 >= i1 then
                                    local ly1 = ly
                                    local ly2 = ly + th
                                    for ii = i1, i2 do
                                        local hh = wf_hh_by_i[ii] or 0
                                        if hh > 0 then
                                            local wy1 = wf_mid_y - hh
                                            local wy2 = wf_mid_y + hh
                                            if wy2 >= ly1 and wy1 <= ly2 then
                                                use_black = true
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                            if use_black then
                                text_col = COLOR_TEXT_BLACK
                            else
                                text_col = region_label_color_for_native(r.color or 0, region_label_color)
                            end
                            reaper.ImGui_DrawList_AddText(draw_list, lx, ly, text_col, stext)
                        end
                    end
                end
            end
        end
        if label_font_pushed then
            pcall(reaper.ImGui_PopFont, ctx)
        end
    end

    if show_no_preview_label and (not is_enabled) and w > 20 and h > 18 then
        local msg = "No Preview Yet"
        local shown = (fit_text_to_width and fit_text_to_width(ctx, msg, math.max(0, w - 10))) or msg
        local tw, th = reaper.ImGui_CalcTextSize(ctx, shown)
        local lx = x + math.floor((w - tw) / 2)
        local ly = y + math.floor((h - th) / 2)
        local pad = 4
        reaper.ImGui_DrawList_AddRectFilled(draw_list, lx - pad, ly - 1, lx + tw + pad, ly + th + 1, COLOR_BLACK_BG_TIP, 4)
        reaper.ImGui_DrawList_AddText(draw_list, lx, ly, COLOR_TEXT, shown)
    end
end

local function draw_seekbar(ctx, draw_list, id, x, y, w, h, opts)
    local is_enabled = opts and opts.is_enabled
    local regions = opts and opts.regions
    local timeline_min = opts and opts.timeline_min or 0.0
    local timeline_span = opts and opts.timeline_span
    local timeline_origin = opts and opts.timeline_origin or 0.0
    local ratio_play = opts and opts.ratio_play or 0.0
    local preview_path = opts and opts.preview_path

    draw_timeline(ctx, draw_list, id, x, y, w, h, {
        is_enabled = is_enabled,
        preview_path = preview_path,
        regions = regions,
        timeline_min = timeline_min,
        timeline_span = timeline_span,
        timeline_origin = timeline_origin,
        ratio_play = ratio_play,
        on_seek = opts and opts.on_seek,
        tooltip_key = "seekbar_top",
        radius = 3,
        snap_mode = "start",
        enable_hover_snap = true,
        draw_play_fill = true,
        show_playhead = true,
        show_nav_line = true,
        draw_region_blocks = false,
        draw_region_separators = true,
        separator_style = "solid",
        tooltip_snap_tol = math.max(6, math.floor(h * 0.60)),
        click_snap_tol = math.max(10, math.floor(h * 2.0)),
        seek_override_duration = 0.12,
    })
end

draw_player_timeline = function(ctx, draw_list, id, x, y, w, h, opts)
    local is_enabled = opts and opts.is_enabled
    local preview_path = opts and opts.preview_path
    local regions = opts and opts.regions
    local timeline_min = opts and opts.timeline_min or 0.0
    local timeline_span = opts and opts.timeline_span
    local timeline_origin = opts and opts.timeline_origin or 0.0
    local status = opts and opts.status
    local is_playing = opts and opts.is_playing

    draw_timeline(ctx, draw_list, id, x, y, w, h, {
        is_enabled = is_enabled,
        preview_path = preview_path,
        regions = regions,
        timeline_min = timeline_min,
        timeline_span = timeline_span,
        timeline_origin = timeline_origin,
        status = status,
        is_playing = is_playing,
        on_seek = opts and opts.on_seek,
        tooltip_key = "seekbar_bottom",
        radius = 6,
        snap_mode = "start_finish",
        enable_hover_snap = true,
        enable_tooltip_inside_region = true,
        draw_play_fill = false,
        show_playhead = true,
        show_nav_line = true,
        draw_region_blocks = true,
        draw_region_separators = true,
        separator_style = "dashed",
        draw_waveform = true,
        draw_marker_labels = true,
        draw_region_labels = true,
        show_no_preview_label = true,
        tooltip_snap_tol = 6,
        click_snap_tol = 10,
        hover_snap_tol = 10,
        hit_margin_factor = 0.0,
        seek_override_duration = 0.12,
    })
end
fit_text_to_width = function(ctx, text, max_w)
    if not text or text == "" then return "" end
    local tw = select(1, reaper.ImGui_CalcTextSize(ctx, text))
    if tw <= max_w then return text end
    local ell = "..."
    local ell_w = select(1, reaper.ImGui_CalcTextSize(ctx, ell))
    local budget = max_w - ell_w
    if budget <= 0 then return ell end
    local low, high = 1, #text
    local best = ""
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local s = string.sub(text, 1, mid)
        local w = select(1, reaper.ImGui_CalcTextSize(ctx, s))
        if w <= budget then
            best = s
            low = mid + 1
        else
            high = mid - 1
        end
    end
    return best .. ell
end
wrap_text_to_width = function(ctx, text, max_w)
    local lines = {}
    if not text then
        lines[1] = ""
        return lines
    end
    local t = tostring(text)
    if max_w == nil or max_w <= 0 then
        lines[1] = t
        return lines
    end
    local len = #t
    local i = 1
    while i <= len do
        while i <= len and string.sub(t, i, i):match("%s") do
            i = i + 1
        end
        if i > len then break end
        local start_i = i
        local last_space = nil
        local best_i = i
        for j = i, len do
            local s = string.sub(t, start_i, j)
            local w = select(1, reaper.ImGui_CalcTextSize(ctx, s))
            if w > max_w then
                if last_space and last_space >= start_i then
                    best_i = last_space
                else
                    best_i = j - 1
                end
                break
            else
                best_i = j
            end
            if string.sub(t, j, j) == " " then
                last_space = j
            end
        end
        local line = string.sub(t, start_i, best_i)
        line = line:gsub("^%s+", "")
        lines[#lines + 1] = line
        i = best_i + 1
    end
    if #lines == 0 then
        lines[1] = ""
    end
    return lines
end
format_time_mmss = function(seconds, mode, fps)
    seconds = tonumber(seconds) or 0
    local sign = ""
    if seconds < 0 then
        sign = "-"
        seconds = -seconds
    end

    if tonumber(mode) == 7 then
        local fps_i = tonumber(fps) or 0
        fps_i = math.floor(fps_i + 0.5)
        if fps_i > 0 then
            local total_frames = math.floor((seconds * fps_i) + 0.5)
            local total_seconds = math.floor(total_frames / fps_i)
            local ff = total_frames - (total_seconds * fps_i)
            local hh = math.floor(total_seconds / 3600)
            local mm = math.floor((total_seconds % 3600) / 60)
            local ss = total_seconds % 60
            return string.format("%s%02d:%02d:%02d:%02d", sign, hh, mm, ss, ff)
        end
    end

    local s = math.floor(seconds + 0.5)
    local m = math.floor(s / 60)
    local ss = s % 60
    return string.format("%s%02d:%02d", sign, m, ss)
end

local function format_bytes_iec(bytes)
    local b = tonumber(bytes)
    if not b or b < 0 then return nil end
    if b < 1024 then
        return string.format("%d B", math.floor(b + 0.5))
    end
    local units = { "KB", "MB", "GB", "TB" }
    local v = b / 1024.0
    local u = 1
    while v >= 1024.0 and u < #units do
        v = v / 1024.0
        u = u + 1
    end
    if v >= 10.0 then
        return string.format("%.0f %s", v, units[u])
    end
    return string.format("%.1f %s", v, units[u])
end

local function format_sample_rate(sr)
    local n = tonumber(sr)
    if not n or n <= 0 then return nil end
    if n >= 1000 then
        local khz = n / 1000.0
        if math.abs(khz - math.floor(khz + 0.5)) < 0.0001 then
            return string.format("%d kHz", math.floor(khz + 0.5))
        end
        return string.format("%.1f kHz", khz)
    end
    return string.format("%d Hz", math.floor(n + 0.5))
end

local function format_dbfs(dbfs)
    local v = tonumber(dbfs)
    if v == nil then return nil end
    if v == -math.huge or v < -1000 then
        return "-inf dBFS"
    end
    return string.format("%.1f dBFS", v)
end

local function vol_to_db(vol)
    local v = tonumber(vol)
    if not v or v <= 0 then
        return -150.0
    end
    return (20.0 * (math.log(v) / math.log(10)))
end

local function db_to_vol(db)
    local d = tonumber(db)
    if d == nil then
        return 1.0
    end
    return 10 ^ (d / 20.0)
end

local function join_parts(parts, sep)
    local out = {}
    for _, p in ipairs(parts or {}) do
        if p and p ~= "" then
            out[#out + 1] = p
        end
    end
    return table.concat(out, sep or "  |  ")
end

local function format_stale_age(stale_seconds)
    local s = tonumber(stale_seconds)
    if s == nil then return nil end

    if s <= 0 then
        return "Stale: 00:00"
    end

    if s < 86400 then
        local total_minutes = math.floor(s / 60)
        local hh = math.floor(total_minutes / 60)
        local mm = total_minutes % 60
        if hh > 23 then
            hh = 23
            mm = 59
        end
        return string.format("Stale: %02d:%02d", hh, mm)
    end

    local d = math.floor(s / 86400)
    if d < 1 then d = 1 end
    return string.format("Stale: %dd", d)
end

local function safe_get_preview_meta(ProjectList, project, preview_path)
    if not ProjectList or not preview_path or preview_path == "" then return nil end
    if reaper.file_exists and not reaper.file_exists(preview_path) then
        return nil
    end
    local meta = {}
    meta.duration = get_duration_cached(preview_path)
    local project_path = project and (project.full_path or project.path) or nil
    meta.created = (project and project.preview_created_date) or (ProjectList.get_preview_created_date and ProjectList.get_preview_created_date(preview_path)) or nil
    meta.stale_seconds = (project and project.preview_stale_seconds)
        or ((project_path and ProjectList.get_preview_staleness_seconds) and ProjectList.get_preview_staleness_seconds(project_path, preview_path) or nil)
    if meta.stale_seconds == nil then
        local stale_days = nil
        if project and project.preview_stale_days then
            stale_days = tonumber(project.preview_stale_days)
        end
        if stale_days == nil and project_path and ProjectList.get_preview_staleness_days then
            local d = ProjectList.get_preview_staleness_days(project_path, preview_path)
            if d ~= nil then
                stale_days = tonumber(d)
            end
        end
        if stale_days ~= nil then
            meta.stale_seconds = stale_days * 86400
        end
    end
    meta.media = (ProjectList.get_preview_media_info and ProjectList.get_preview_media_info(preview_path)) or {}
    return meta
end

local function is_project_meta_open(app_state, project)
    if not app_state or not project then return false end
    local p = project and (project.full_path or project.path) or ""
    if p == "" then return false end
    local key = normalize_path(p)
    if key == "" then return false end
    app_state.open_meta_paths = app_state.open_meta_paths or {}
    return app_state.open_meta_paths[key] == true
end

local function toggle_project_metadata(app_state, project)
    if not project or not app_state then return end
    local p = project and (project.full_path or project.path) or ""
    if p == "" then return end

    local key = normalize_path(p)
    if key == "" then return end

    app_state.open_meta_paths = app_state.open_meta_paths or {}

    if app_state.open_meta_paths[key] and project.parsed_meta then
        app_state.open_meta_paths[key] = nil
        return
    end

    local meta = nil
    if ProjectList and ProjectList.get_project_metadata then
        local m = ProjectList.get_project_metadata(p)
        if type(m) == "table" then
            meta = m
        end
    end

    if meta then
        project.parsed_meta = meta
        app_state.open_meta_paths[key] = true
    end
end

local function push_context_menu_style(ctx)
    local color_count = 0
    local var_count = 0

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), COLOR_POPUP_BG); color_count = color_count + 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), COLOR_BG_BUTTON_ACTIVE); color_count = color_count + 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), COLOR_ROW_BG_HOVER_SOFT); color_count = color_count + 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), COLOR_ROW_BG_HOVER); color_count = color_count + 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), COLOR_ROW_BG_SELECTED); color_count = color_count + 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), COLOR_MENU_TEXT); color_count = color_count + 1

    local rounding = select(1, reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding()))
    if type(rounding) ~= "number" then
        rounding = tonumber(rounding)
    end
    rounding = rounding or 8

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), rounding); var_count = var_count + 1
    if reaper.ImGui_StyleVar_PopupRounding then
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(), rounding); var_count = var_count + 1
    end
    if reaper.ImGui_StyleVar_PopupBorderSize then
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupBorderSize(), 1.0); var_count = var_count + 1
    end
    if reaper.ImGui_StyleVar_WindowBorderSize then
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 1.0); var_count = var_count + 1
    end

    return color_count, var_count
end

local function pop_context_menu_style(ctx, color_count, var_count)
    if var_count and var_count > 0 then
        reaper.ImGui_PopStyleVar(ctx, var_count)
    end
    if color_count and color_count > 0 then
        reaper.ImGui_PopStyleColor(ctx, color_count)
    end
end

local function draw_menu_from_table(ctx, items, env)
    for _, item in ipairs(items or {}) do
        if item and item.separator == true then
            reaper.ImGui_Separator(ctx)
        else
            local visible = true
            if item and item.visible ~= nil then
                if type(item.visible) == "function" then
                    visible = item.visible(env) == true
                else
                    visible = item.visible == true
                end
            end
            if visible and item then
                local clicked = false
                if item.render then
                    clicked = item.render(ctx, env) == true
                else
                    local label = item.label
                    if type(label) == "function" then
                        label = label(env)
                    end
                    label = tostring(label or "")

                    local shortcut = item.shortcut
                    if type(shortcut) == "function" then
                        shortcut = shortcut(env)
                    end

                    local checked = item.checked
                    if type(checked) == "function" then
                        checked = checked(env)
                    end

                    local enabled = item.enabled
                    if type(enabled) == "function" then
                        enabled = enabled(env)
                    end

                    if checked == nil and shortcut == nil and enabled == nil then
                        clicked = reaper.ImGui_MenuItem(ctx, label)
                    else
                        if checked == nil then checked = false end
                        if enabled == nil then enabled = true end
                        clicked = reaper.ImGui_MenuItem(ctx, label, shortcut, checked, enabled)
                    end
                end
                if clicked and item.action then
                    item.action(env)
                end
            end
        end
    end
end

local function show_context_menu(app_state, project)
    local is_unavailable = project and project.is_unavailable
    if is_unavailable then
        draw_menu_from_table(ctx, {
            {
                label = "Open Last Existing Folder",
                action = function(env)
                    if env.project_path ~= "" and ProjectList and ProjectList.open_last_existing_folder then
                        local ok, err = ProjectList.open_last_existing_folder(env.project_path)
                        if not ok then
                            reaper.ShowMessageBox("Open last existing folder failed:\n" .. tostring(err or "unknown error"), "Frenkie Recent Projects", 0)
                        end
                    else
                        reaper.ShowMessageBox("Open last existing folder failed:\ninvalid project path", "Frenkie Recent Projects", 0)
                    end
                end
            },
            {
                label = "Remove From List",
                action = function(env)
                    local remover = ProjectList and (ProjectList.remove_project_from_history or ProjectList.remove_project_from_recent_list) or nil
                    if env.project_path ~= "" and remover then
                        local ok, err = remover(env.project_path)
                        if not ok then
                            reaper.ShowMessageBox("Remove from recent list failed:\n" .. tostring(err or "unknown error"), "Frenkie Recent Projects", 0)
                        end
                    else
                        reaper.ShowMessageBox("Remove from recent list failed:\ninvalid project path", "Frenkie Recent Projects", 0)
                    end
                end
            },
        }, { app_state = app_state, project = project, project_path = project and (project.full_path or project.path) or "" })
        return
    end

    app_state.selected_rows = app_state.selected_rows or {}
    local selection_section = app_state.selection_section or "rest"
    local selected_count = 0
    local selected_indices = {}
    if app_state.filtered_projects then
        for idx, v in pairs(app_state.selected_rows) do
            if v and app_state.filtered_projects[idx] then
                selected_count = selected_count + 1
                selected_indices[#selected_indices + 1] = idx
            end
        end
    end
    table.sort(selected_indices)

    local is_multi = selected_count > 1

    if is_multi then
        draw_menu_from_table(ctx, {
            {
                label = "Open on New Tab",
                visible = function(env)
                    return env.selection_section == "rest"
                end,
                action = function(env)
                    for _, idx in ipairs(env.selected_indices) do
                        local prj = env.app_state.filtered_projects[idx]
                        if prj and (prj.full_path or prj.path) then
                            ProjectList.open_project_new_tab(prj.full_path or prj.path)
                        end
                    end
                    env.app_state.request_close = true
                end
            },
            {
                label = "Close Project",
                visible = function(env)
                    return env.selection_section ~= "rest"
                end,
                action = function(env)
                    if ProjectList and ProjectList.close_project then
                        for _, idx in ipairs(env.selected_indices) do
                            local prj = env.app_state.filtered_projects[idx]
                            if prj and prj.is_open and (prj.full_path or prj.path) then
                                ProjectList.close_project(prj.full_path or prj.path)
                            end
                        end
                    end
                end
            },
            {
                label = "Remove Project(s) from List",
                action = function(env)
                    local remover = ProjectList and (ProjectList.remove_project_from_history or ProjectList.remove_project_from_recent_list) or nil
                    if remover then
                        local any_error = nil
                        for _, idx in ipairs(env.selected_indices) do
                            local prj = env.app_state.filtered_projects[idx]
                            local p = prj and (prj.full_path or prj.path) or ""
                            if p ~= "" then
                                local ok, err = remover(p)
                                if not ok and not any_error then
                                    any_error = err or "unknown error"
                                end
                            end
                        end
                        if any_error then
                            reaper.ShowMessageBox("Remove from recent list failed:\n" .. tostring(any_error), "Frenkie Recent Projects", 0)
                        end
                    else
                        reaper.ShowMessageBox("Remove from recent list failed:\ninvalid remover", "Frenkie Recent Projects", 0)
                    end
                end
            },
        }, {
            app_state = app_state,
            selection_section = selection_section,
            selected_indices = selected_indices,
        })

        return
    end

    local project_path = project and (project.full_path or project.path) or ""
    local settings = app_state and app_state.settings or nil
    if ProjectList and ProjectList.ensure_pinned_paths then
        ProjectList.ensure_pinned_paths(settings)
    end
    local is_pinned = (ProjectList and ProjectList.is_project_pinned) and ProjectList.is_project_pinned(settings, project_path) or false

    local is_meta_open = is_project_meta_open(app_state, project)
    local is_open_or_current = project and (project.is_current or project.is_open)

    draw_menu_from_table(ctx, {
        {
            label = "Open Project",
            action = function(env)
                ProjectList.open_project(env.project.full_path)
                env.app_state.request_close = true
            end
        },
        {
            label = "Open Project on New Tab",
            action = function(env)
                ProjectList.open_project_new_tab(env.project.full_path)
                env.app_state.request_close = true
            end
        },
        {
            label = function(env)
                return (env.is_pinned == true) and "Unpin from List" or "Pin to List"
            end,
            action = function(env)
                if ProjectList and ProjectList.toggle_project_pinned then
                    ProjectList.toggle_project_pinned(env.app_state.settings, env.project_path)
                end
                if env.app_state and env.app_state.save_settings and env.app_state.settings then
                    env.app_state.save_settings(env.app_state.settings)
                end
                regroup_filtered_projects(env.app_state)
            end
        },
        { separator = true },
        {
            label = (function()
                local os = reaper.GetOS and tostring(reaper.GetOS()) or ""
                if os:match("OSX") or os:lower():match("mac") then
                    return "Show in Finder"
                elseif os:match("Win") then
                    return "Show in Explorer"
                else
                    return "Show in File Manager"
                end
            end)(),
            action = function(env)
                ProjectList.show_in_file_manager(env.project.full_path)
            end
        },
        {
            label = "Open in Media Explorer",
            action = function(env)
                local p = env.project_path
                if reaper.OpenMediaExplorer then
                    local ok = pcall(reaper.OpenMediaExplorer, p, true)
                    if not ok then
                        local folder = p:match("(.+)[/\\][^/\\]+$") or ""
                        if folder ~= "" then
                            pcall(reaper.OpenMediaExplorer, folder, true)
                        else
                            pcall(reaper.OpenMediaExplorer, "", true)
                        end
                    end
                elseif reaper.Main_OnCommand then
                    reaper.Main_OnCommand(50124, 0)
                end
            end
        },
        {
            label = "Copy Project Name",
            action = function(env)
                local name = env.project and env.project.name or ""
                if name == "" then
                    local fp = env.project and (env.project.full_path or env.project.path) or ""
                    name = fp:match("([^/\\]+)%.rpp$") or fp:match("([^/\\]+)$") or ""
                end
                if name ~= "" and reaper.ImGui_SetClipboardText then
                    reaper.ImGui_SetClipboardText(ctx, name)
                end
            end
        },
        {
            visible = function(env)
                return env.is_open_or_current ~= true
            end,
            render = function(ctx, env)
                if env.is_meta_open == true then
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), COLOR_HEADER_HOVER)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), COLOR_HEADER_ACTIVE)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), COLOR_HEADER_ACTIVE)
                    local clicked = reaper.ImGui_MenuItem(ctx, "Close Metadata")
                    reaper.ImGui_PopStyleColor(ctx, 3)
                    return clicked
                end
                return reaper.ImGui_MenuItem(ctx, "! Get Metadata")
            end,
            action = function(env)
                toggle_project_metadata(env.app_state, env.project)
            end
        },
        {
            separator = true,
            visible = function(env)
                return env.is_open_or_current ~= true
            end
        },
        {
            label = "Create Preview",
            action = function(env)
                ProjectList.create_preview(env.project.full_path or env.project.path)
            end
        },
        { separator = true },
        {
            label = "Close Project",
            visible = function(env)
                return env.project and env.project.is_open
            end,
            action = function(env)
                if ProjectList and ProjectList.close_project then
                    ProjectList.close_project(env.project.full_path or env.project.path)
                end
            end
        },
        {
            label = "Remove Project from List",
            visible = function(env)
                return not (env.project and env.project.is_open)
            end,
            action = function(env)
                local p = env.project_path
                local remover = ProjectList and (ProjectList.remove_project_from_history or ProjectList.remove_project_from_recent_list) or nil
                if p ~= "" and remover then
                    local ok, err = remover(p)
                    if not ok then
                        reaper.ShowMessageBox("Remove from recent list failed:\n" .. tostring(err or "unknown error"), "Frenkie Recent Projects", 0)
                    end
                else
                    reaper.ShowMessageBox("Remove from recent list failed:\ninvalid project path", "Frenkie Recent Projects", 0)
                end
            end
        },
    }, {
        app_state = app_state,
        project = project,
        project_path = project_path,
        is_pinned = is_pinned,
        is_meta_open = is_meta_open,
        is_open_or_current = is_open_or_current,
    })

end

function UI.draw(app_state)
    if not ctx or not reaper.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
        return false
    end

    apply_item_properties_style(ctx)

    -- Set window size - ReaImGUI automatically saves/restores window size
    reaper.ImGui_SetNextWindowSize(ctx, 900, 640, reaper.ImGui_Cond_FirstUseEver())
    do
        local min_w, min_h = 420, 360
        local max_w, max_h = 1400, 900
        if reaper.ImGui_GetMainViewport and reaper.ImGui_Viewport_GetWorkSize then
            local vp = reaper.ImGui_GetMainViewport(ctx)
            if vp then
                local work_w, work_h = reaper.ImGui_Viewport_GetWorkSize(vp)
                if work_w and work_h then
                    max_w = math.floor(work_w * 0.9)
                    max_h = math.floor(work_h * 0.9)
                end
            end
        end
        if max_w < min_w then max_w = min_w end
        if max_h < min_h then max_h = min_h end
        reaper.ImGui_SetNextWindowSizeConstraints(ctx, min_w, min_h, max_w, max_h)
    end

    if undock_next_frame and reaper.ImGui_SetNextWindowDockID then
        reaper.ImGui_SetNextWindowDockID(ctx, 0)
        undock_next_frame = false
    end

    local visible, open = reaper.ImGui_Begin(ctx, 'Recent Projects', true, WINDOW_FLAGS)

    if reaper.ImGui_IsWindowDocked and reaper.ImGui_IsWindowDocked(ctx) then
        undock_next_frame = true
    end

    if visible then
        local esc_pressed = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())
        if draw_custom_close_button(ctx) then
            open = false
        end
        do
            local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
            local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
            local pad_x, pad_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding())
            pad_x = tonumber(pad_x) or 0
            pad_y = tonumber(pad_y) or 0
            if win_x and win_y and win_w and win_h then
                local title = "Recent Projects"
                local tw, th = reaper.ImGui_CalcTextSize(ctx, title)
                if tw and th then
                    local title_h = reaper.ImGui_GetFontSize(ctx) + (pad_y * 2)
                    local top_y = win_y + pad_y
                    local text_y = top_y + math.floor((title_h - th) * 0.5)
                    local text_x = win_x + math.floor((win_w - tw) * 0.5)
                    local dl = reaper.ImGui_GetWindowDrawList(ctx)
                    if dl then
                        reaper.ImGui_DrawList_AddText(dl, text_x, text_y, COLOR_TEXT_MUTED, title)
                    end
                end
            end
        end
        app_state.settings = app_state.settings or {}

        reaper.ImGui_Dummy(ctx, 1, math.floor(reaper.ImGui_GetFrameHeight(ctx) + 2))

        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 8, 4)

        local row_x, row_y = reaper.ImGui_GetCursorScreenPos(ctx)
        local row_w = reaper.ImGui_GetContentRegionAvail(ctx)
        local btn_size = math.floor(reaper.ImGui_GetFrameHeight(ctx))
        local tight_x = row_x + row_w - btn_size
        if tight_x < row_x then
            tight_x = row_x
        end

        draw_projects_counter(ctx, app_state, row_x, row_y, tight_x, btn_size)

        local pos_x, pos_y = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorScreenPos(ctx, tight_x, row_y)
        draw_compact_view_toggle(ctx, app_state)
        reaper.ImGui_SetCursorPos(ctx, pos_x, pos_y)
        app_state.settings = app_state.settings or {}
        local sort_mode = tostring(app_state.settings.sort_mode or "opened")
        local sort_dir_opened = tostring(app_state.settings.sort_dir_opened or "desc")
        local sort_dir_modified = tostring(app_state.settings.sort_dir_modified or "desc")

        local opened_arrow = (sort_dir_opened == "asc") and "▲" or "▼"
        local modified_arrow = (sort_dir_modified == "asc") and "▲" or "▼"

        local sort_modified_active = (sort_mode == "modified")
        local sort_modified_style = sort_modified_active and ((sort_dir_modified == "asc") and "orange" or true) or false
        local sort_modified = draw_gray_button(ctx, "Modified " .. modified_arrow .. "##sort_modified", nil, nil, sort_modified_style)
        if sort_modified then
            if sort_mode == "modified" then
                app_state.settings.sort_dir_modified = (sort_dir_modified == "asc") and "desc" or "asc"
            else
                app_state.settings.sort_mode = "modified"
            end
            if app_state.save_settings then
                app_state.save_settings(app_state.settings)
            end
            if ProjectList and ProjectList.rebuild_filtered_projects then
                ProjectList.rebuild_filtered_projects(app_state)
            end
        end

        reaper.ImGui_SameLine(ctx)
        local sort_opened_active = (sort_mode == "opened")
        local sort_opened_style = sort_opened_active and ((sort_dir_opened == "asc") and "orange" or true) or false
        local sort_opened = draw_gray_button(ctx, "Opened " .. opened_arrow .. "##sort_opened", nil, nil, sort_opened_style)
        if sort_opened then
            if sort_mode == "opened" then
                app_state.settings.sort_dir_opened = (sort_dir_opened == "asc") and "desc" or "asc"
            else
                app_state.settings.sort_mode = "opened"
            end
            if app_state.save_settings then
                app_state.save_settings(app_state.settings)
            end
            if ProjectList and ProjectList.rebuild_filtered_projects then
                ProjectList.rebuild_filtered_projects(app_state)
            end
        end

        reaper.ImGui_SameLine(ctx)
        local pin_active = app_state.pin_on_screen == true
        local pin_clicked = draw_gray_button(ctx, "Pin##pin_on_screen", nil, nil, pin_active)
        show_delayed_tooltip("pin_on_screen_button", "Keep window open after opening project")
        if pin_clicked then
            app_state.pin_on_screen = not pin_active
        end

        reaper.ImGui_SameLine(ctx)
        local open_clicked = draw_gray_button(ctx, "Open##open_projects", nil, nil, false)
        show_delayed_tooltip("open_projects_button", "File: Choose project(s) to open...")
        if open_clicked then
            if reaper.Main_OnCommand then
                reaper.Main_OnCommand(43697, 0)
            end
        end

        reaper.ImGui_SameLine(ctx)
        local rescan_clicked = draw_gray_button(ctx, "Rescan##rescan_projects", nil, nil, false)
        show_delayed_tooltip("rescan_projects_button", "Rescan disk for missing projects")
        if rescan_clicked and ProjectList then
            if ProjectList.migrate_txt_to_json then
                ProjectList.migrate_txt_to_json()
            end
            if ProjectList.find_missing_projects then
                local missing = ProjectList.find_missing_projects() or {}
            if #missing == 0 then
                reaper.ShowMessageBox("All projects exist on disk.", "Frenkie Recent Projects", 0)
            else
                local ret = reaper.ShowMessageBox("Some projects do not exist on disk.\n\nRemove them from the recent projects list?", "Frenkie Recent Projects", 4)
                if ret == 6 then
                    local remover = ProjectList.remove_project_from_history or ProjectList.remove_project_from_recent_list
                    if remover then
                        local any_error = nil
                        for _, p in ipairs(missing) do
                            local ok, err = remover(p)
                            if not ok and not any_error then
                                any_error = err or "unknown error"
                            end
                        end
                        if any_error then
                            reaper.ShowMessageBox("Remove from recent list failed:\n" .. tostring(any_error), "Frenkie Recent Projects", 0)
                        end
                    else
                        reaper.ShowMessageBox("Remove from recent list failed:\ninvalid remover", "Frenkie Recent Projects", 0)
                    end
                else
                    if app_state and app_state.filtered_projects then
                        local missing_norm = {}
                        for _, p in ipairs(missing) do
                            local n = normalize_path(p)
                            if n ~= "" then
                                missing_norm[n] = true
                            end
                        end
                        for _, prj in ipairs(app_state.filtered_projects) do
                            local path = prj and (prj.full_path or prj.path) or ""
                            local n = normalize_path(path)
                            if n ~= "" and missing_norm[n] then
                                prj.is_unavailable = true
                                prj.has_preview = false
                                prj.preview_path = nil
                            end
                        end
                    end
                end
            end
            end
        end

        reaper.ImGui_PopStyleVar(ctx, 2)

        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 8, 4)
        reaper.ImGui_SetNextItemWidth(ctx, -1)

        local filter_focus_assigned_this_frame = false
        if first_frame then
            reaper.ImGui_SetKeyboardFocusHere(ctx)
            first_frame = false
            filter_focus_assigned_this_frame = true
        end

        if filter_focus_next_frame then
            reaper.ImGui_SetKeyboardFocusHere(ctx)
            filter_focus_next_frame = false
            filter_focus_assigned_this_frame = true
        end

        local prev_filter_text = tostring(app_state.filter_text or "")

        local filter_input_flags = 0
        if reaper.ImGui_InputTextFlags_EscapeClearsAll then
            filter_input_flags = filter_input_flags | reaper.ImGui_InputTextFlags_EscapeClearsAll()
        end

        local filter_id = "##filter_" .. tostring(filter_id_version)
        local changed, new_filter
        if reaper.ImGui_InputTextWithHint then
            changed, new_filter = reaper.ImGui_InputTextWithHint(ctx, filter_id, "Search", prev_filter_text, filter_input_flags)
        else
            changed, new_filter = reaper.ImGui_InputText(ctx, filter_id, prev_filter_text, filter_input_flags)
        end
        local filter_is_active = reaper.ImGui_IsItemActive(ctx)
        local filter_is_focused = filter_is_active
        if (not filter_is_focused) and reaper.ImGui_IsItemFocused then
            filter_is_focused = reaper.ImGui_IsItemFocused(ctx)
        end

        local fx1, fy1 = reaper.ImGui_GetItemRectMin(ctx)
        local fx2, fy2 = reaper.ImGui_GetItemRectMax(ctx)

        if filter_is_focused or filter_focus_assigned_this_frame then
            filter_has_focus = true
        end

        if reaper.ImGui_IsMouseClicked and reaper.ImGui_IsWindowHovered and reaper.ImGui_GetMousePos then
            if reaper.ImGui_IsMouseClicked(ctx, 0) and reaper.ImGui_IsWindowHovered(ctx) then
                local mx, my = reaper.ImGui_GetMousePos(ctx)
                if mx and my then
                    local inside = mx >= fx1 and mx <= fx2 and my >= fy1 and my <= fy2
                    filter_has_focus = inside
                end
            end
        end

        local was_focused = filter_has_focus or filter_focused_last_frame
        filter_focused_last_frame = filter_has_focus

        if (not reaper.ImGui_InputTextWithHint) and (not app_state.filter_text or app_state.filter_text == "") and (not filter_is_active) then
            local pad_x, pad_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding())
            local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
            reaper.ImGui_DrawList_AddText(draw_list, fx1 + pad_x, fy1 + pad_y, COLOR_SEARCH_PLACEHOLDER, "Search")
        end

        local cur_text = (new_filter ~= nil) and tostring(new_filter) or tostring(app_state.filter_text or "")
        local esc_in_filter = esc_pressed and was_focused
        local cleared_by_inputtext_esc = esc_in_filter and prev_filter_text ~= "" and cur_text == ""
        local clear_by_esc = (not cleared_by_inputtext_esc) and esc_in_filter and cur_text ~= ""
        local clear_by_click = false

        if cur_text ~= "" then
            local pad_x, _ = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding())
            local btn_sz = math.max(10, math.floor((fy2 - fy1) - 2))
            local bx2 = fx2 - pad_x
            local bx1 = bx2 - btn_sz
            local by1 = fy1 + math.floor(((fy2 - fy1) - btn_sz) / 2)
            local by2 = by1 + btn_sz

            local mx, my = reaper.ImGui_GetMousePos(ctx)
            local hovered = mx and my and mx >= bx1 and mx <= bx2 and my >= by1 and my <= by2
            if hovered and reaper.ImGui_IsMouseClicked then
                clear_by_click = reaper.ImGui_IsMouseClicked(ctx, 0)
            end

            local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
            local col = hovered and COLOR_TEXT or COLOR_META_TEXT_SECONDARY
            local inset = math.max(3, math.floor(btn_sz * 0.28))
            reaper.ImGui_DrawList_AddLine(draw_list, bx1 + inset, by1 + inset, bx1 + btn_sz - inset, by1 + btn_sz - inset, col, 1.5)
            reaper.ImGui_DrawList_AddLine(draw_list, bx1 + inset, by1 + btn_sz - inset, bx1 + btn_sz - inset, by1 + inset, col, 1.5)
        end

        local clear_clicked = clear_by_esc or clear_by_click or cleared_by_inputtext_esc
        if clear_clicked then
            filter_id_version = filter_id_version + 1
            filter_focus_next_frame = true
            new_filter = ""
            changed = true
        elseif esc_pressed and (not esc_in_filter or cur_text == "") then
            open = false
        end

        reaper.ImGui_PopStyleVar(ctx, 2)
        if changed then
            app_state.filter_text = new_filter
            if ProjectList and ProjectList.rebuild_filtered_projects then
                ProjectList.rebuild_filtered_projects(app_state)
            end
        end

        local _, avail_height = reaper.ImGui_GetContentRegionAvail(ctx)
        local content_origin_y = select(2, reaper.ImGui_GetCursorScreenPos(ctx))
        local frame_h = reaper.ImGui_GetFrameHeight(ctx)
        local bottom_border_h = math.max(24, math.floor(frame_h * 1.5))
        if avail_height < bottom_border_h then
            bottom_border_h = avail_height
        end
        local content_height = math.max(0, avail_height - bottom_border_h)
        local status = ProjectList.get_preview_status and ProjectList.get_preview_status()
        if status and status.playing and status.duration and status.duration > 0 and status.elapsed >= (status.duration - 0.01) then
            if app_state.preview_repeat then
                if ProjectList.seek_preview then
                    ProjectList.seek_preview(0)
                    status = ProjectList.get_preview_status and ProjectList.get_preview_status()
                end
            else
                ProjectList.stop_preview()
                status = ProjectList.get_preview_status and ProjectList.get_preview_status()
            end
        end

        local is_playing_preview = status and status.playing == true
        if is_playing_preview and not last_preview_playing then
            bottom_player_closed = false
        end
        last_preview_playing = is_playing_preview

        local show_bottom_player = is_playing_preview and (not bottom_player_closed)
        if show_bottom_player then
            bottom_panel_ever_opened = true
        end

        local player_has_audio = false
        do
            local chosen_project = nil
            if status and status.playing and status.path then
                chosen_project = find_project_by_preview_path(app_state, status.path)
            end
            if not chosen_project then
                local idx = app_state.selected_project
                if idx and app_state.filtered_projects and app_state.filtered_projects[idx] then
                    chosen_project = app_state.filtered_projects[idx]
                end
            end
            local preview_path = get_preview_path_for_project(chosen_project)
            player_has_audio = preview_path ~= nil
        end

        local compact_view = (app_state.settings and app_state.settings.compact_view) == true

        local reserved_height = 0
        do
            local text_h = reaper.ImGui_GetTextLineHeight(ctx)
            local _, play_size_for_list = get_play_control_sizes(ctx)
            if compact_view then
                local name_pad_y = 3
                local bottom_pad_y = 3
                local inline_icon_size_sel = play_size_for_list
                local name_block_h = math.max(text_h, inline_icon_size_sel)
                reserved_height = name_pad_y + name_block_h + bottom_pad_y
            else
                local name_pad_y = 4
                local meta_gap_y = 6
                local bar_gap_y = 2
                local bottom_pad_y = 4
                local inline_icon_size_sel = play_size_for_list
                local name_block_h = math.max(text_h, inline_icon_size_sel)
                local frame_h = reaper.ImGui_GetFrameHeight(ctx)
                local seek_h = math.max(6, math.floor(frame_h * 0.35))
                local meta_h = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
                reserved_height = name_pad_y + name_block_h + meta_gap_y + meta_h + bar_gap_y + seek_h + bottom_pad_y
            end
        end
        local base_footer = 1
        local default_bottom_panel_h = math.max(70, math.floor(frame_h * 5.0))
        app_state.settings = app_state.settings or {}
        local bottom_panel_pref_h = tonumber(app_state.settings.bottom_panel_h)
        if bottom_panel_pref_h == nil then
            bottom_panel_pref_h = default_bottom_panel_h
            app_state.settings.bottom_panel_h = bottom_panel_pref_h
        end
        local show_bottom_panel_ui = bottom_panel_ever_opened and (not bottom_player_closed)
        local idle_bottom_panel_h = math.max(70, math.floor(frame_h * 4.0))
        local base_bottom_panel_h = show_bottom_panel_ui and (player_has_audio and bottom_panel_pref_h or idle_bottom_panel_h) or 0
        local splitter_h = 0
        local bottom_pad_top = 4
        local min_timeline_h = 12
        local meta_gap = 8
        local meta_pad_y = 6
        local meta_line_h = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
        local fixed_meta_lines = 2
        local text_h = reaper.ImGui_GetTextLineHeight(ctx)
        local bottom_controls_h = math.max(text_h, math.floor(frame_h * 0.6))
        local _, window_pad_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding())
        window_pad_y = tonumber(window_pad_y) or 0
        local _, item_sp_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
        item_sp_y = tonumber(item_sp_y) or 0
        local meta_extra_h = math.min(item_sp_y * 3, math.floor(meta_line_h))
        local fixed_meta_reserve_h = player_has_audio and (meta_gap + meta_pad_y + (fixed_meta_lines * meta_line_h) + meta_pad_y + meta_extra_h) or 0
        local bottom_needed_min_h = math.floor(bottom_controls_h + bottom_pad_top + min_timeline_h + fixed_meta_reserve_h + item_sp_y + (window_pad_y * 2) + 4)
        local min_bottom_panel_h = math.max(60, math.floor(frame_h * 4.0), bottom_needed_min_h)
        local layout_gap_y = item_sp_y * 2
        local max_bottom_panel_h = math.max(min_bottom_panel_h, math.floor(content_height - (base_footer + layout_gap_y + 80)))

        local now_bottom = reaper.time_precise()
        local dt_bottom = now_bottom - (bottom_panel_last_t or now_bottom)
        bottom_panel_last_t = now_bottom

        if show_bottom_player or show_bottom_panel_ui then
            local clamped_base_h = math.max(min_bottom_panel_h, math.min(base_bottom_panel_h, max_bottom_panel_h))
            if bottom_splitter_active then
                local _, my = reaper.ImGui_GetMousePos(ctx)
                local delta = (my or 0) - (bottom_splitter_start_mouse_y or 0)
                local new_h = (bottom_splitter_start_h or clamped_base_h) - delta
                new_h = math.max(min_bottom_panel_h, math.min(new_h, max_bottom_panel_h))
                new_h = math.floor(new_h + 0.5)
                bottom_panel_h_current = new_h
                bottom_panel_target_h = new_h
                if player_has_audio then
                    app_state.settings.bottom_panel_h = new_h
                end
            else
                bottom_panel_target_h = math.floor(clamped_base_h + 0.5)
            end
        elseif not bottom_splitter_active then
            bottom_panel_target_h = 0
        end

        bottom_panel_h_current = bottom_panel_h_current or 0
        local speed_bottom = 24.0
        local alpha_bottom = 1.0 - math.exp(-(dt_bottom or 0) * speed_bottom)
        if alpha_bottom < 0 then alpha_bottom = 0 end
        if alpha_bottom > 1 then alpha_bottom = 1 end
        local ease_bottom = alpha_bottom * alpha_bottom * alpha_bottom * (alpha_bottom * (alpha_bottom * 6.0 - 15.0) + 10.0)
        bottom_panel_h_current = bottom_panel_h_current + (bottom_panel_target_h - bottom_panel_h_current) * ease_bottom
        if math.abs(bottom_panel_target_h - bottom_panel_h_current) < 0.5 then
            bottom_panel_h_current = bottom_panel_target_h
        end

        local bottom_panel_h_raw = math.max(0, bottom_panel_h_current)
        local bottom_panel_h = bottom_panel_h_raw
        local bottom_panel_visible = bottom_panel_h > 0.1
        local bottom_panel_ratio = 0.0
        if max_bottom_panel_h > 0 then
            bottom_panel_ratio = math.min(1.0, math.max(0.0, bottom_panel_h_raw / max_bottom_panel_h))
        end

        if bottom_panel_target_h == 0 and bottom_panel_h_raw < 1.0 then
            bottom_panel_h = 0
            bottom_panel_visible = false
        end
        local base_splitter_h = 10
        splitter_h = base_splitter_h * bottom_panel_ratio

        local panel_gap_y = 2 * bottom_panel_ratio
        local footer_for_table = base_footer
        local layout_gap_for_table = layout_gap_y
        local extra_bottom_for_panel = 0
        if bottom_panel_visible and bottom_panel_h > 0 then
            extra_bottom_for_panel = panel_gap_y + bottom_panel_h
        end
        local table_height = math.max(0, content_height - (footer_for_table + layout_gap_for_table + extra_bottom_for_panel))

        local open_indices, rest_indices = {}, {}
        if ProjectList and ProjectList.build_ui_section_indices then
            open_indices, rest_indices = ProjectList.build_ui_section_indices(app_state.filtered_projects)
        else
            for i, project in ipairs(app_state.filtered_projects) do
                if project and (project.is_current or project.is_open) then
                    open_indices[#open_indices + 1] = i
                else
                    rest_indices[#rest_indices + 1] = i
                end
            end
        end
        local inline_hovered_index = nil

        local function draw_project_row(i, project, row_index, is_last_row, section)
            local row_x, row_y = reaper.ImGui_GetCursorScreenPos(ctx)
            local row_w = reaper.ImGui_GetContentRegionAvail(ctx)
            local row_bottom_y = row_y + reserved_height + 1
            local row_visual_top = row_y
            do
                local _, item_sp_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
                item_sp_y = tonumber(item_sp_y) or 0
                if item_sp_y > 0 then
                    row_visual_top = row_y - (item_sp_y + 1)
                else
                    row_visual_top = row_y - 1
                end
            end

            local is_open_row = section == "open"
            local project_path = project and (project.full_path or project.path) or nil
            local is_unavailable = project and project.is_unavailable
            if project_path and project_path ~= "" and not is_unavailable and reaper.file_exists then
                if not reaper.file_exists(project_path) then
                    is_unavailable = true
                    project.is_unavailable = true
                    project.has_preview = false
                    project.preview_path = nil
                end
            end

            local row_hovered = false
            local row_left_click = false
            local row_right_click = false
            local row_double_click = false
            do
                if reaper.ImGui_IsWindowHovered(ctx) then
                    local mx, my = reaper.ImGui_GetMousePos(ctx)
                    if mx and my and mx >= row_x and mx <= (row_x + row_w) and my >= row_visual_top and my <= row_bottom_y then
                        row_hovered = true
                        if reaper.ImGui_IsMouseClicked then
                            row_left_click = reaper.ImGui_IsMouseClicked(ctx, 0)
                            row_right_click = reaper.ImGui_IsMouseClicked(ctx, 1)
                        elseif reaper.ImGui_IsMouseReleased then
                            row_left_click = reaper.ImGui_IsMouseReleased(ctx, 0)
                            row_right_click = reaper.ImGui_IsMouseReleased(ctx, 1)
                        end
                        row_double_click = reaper.ImGui_IsMouseDoubleClicked(ctx, 0)
                    end
                end
            end

            if is_unavailable then
                row_left_click = false
                row_double_click = false
            end

            local meta_icon_clicked = false

            if is_open_row then
                local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
                reaper.ImGui_DrawList_AddRectFilled(draw_list, row_x, row_visual_top, row_x + row_w, row_bottom_y, COLOR_TEXT_MUTED)
            else
                local n = tonumber(row_index) or i
                if n % 2 == 0 then
                    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, row_x, row_visual_top, row_x + row_w, row_bottom_y, COLOR_TABLE_ROW_BG_ALT)
                end
            end

            local selectable_flags = reaper.ImGui_SelectableFlags_AllowDoubleClick()
            app_state.selected_rows = app_state.selected_rows or {}
            local is_selected = app_state.selected_rows[i] == true or (app_state.selected_project == i)
            do
                local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
                if is_selected then
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, row_x, row_visual_top, row_x + row_w, row_bottom_y, COLOR_ROW_BG_HOVER)
                elseif row_hovered and not is_unavailable then
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, row_x, row_visual_top, row_x + row_w, row_bottom_y, COLOR_ROW_BG_HOVER_SOFT)
                end
            end

            local display_text = project.name
            if is_unavailable then
                if not display_text or display_text == "" then
                    display_text = "Unavailable"
                else
                    display_text = display_text .. " (Unavailable)"
                end
            end

            local name_col = COLOR_TEXT
            if is_open_row then
                name_col = COLOR_TEXT_BLACK
            end
            if is_unavailable then
                name_col = COLOR_PROJECT_MISSING_TEXT
            end
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), name_col)

            local meta_font_size = font_size or 15.0
            meta_font_size = meta_font_size - 2.0
            if meta_font_size < 8.0 then meta_font_size = 8.0 end

            local orig_x = select(1, reaper.ImGui_GetCursorScreenPos(ctx))
            local line_h_for_icon = reaper.ImGui_GetTextLineHeight(ctx)
            local _, inline_icon_size_sel = get_play_control_sizes(ctx)
            if compact_view then
                inline_icon_size_sel = inline_icon_size_sel
            else
                inline_icon_size_sel = inline_icon_size_sel
            end
            local indent_w = inline_icon_size_sel + (compact_view and 10 or 14)
            reaper.ImGui_Indent(ctx, indent_w)
            local text_left_x = orig_x + indent_w + 8

            local unique_id = "##project_" .. i
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), COLOR_BLACK_TRANSPARENT)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), COLOR_BLACK_TRANSPARENT)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), COLOR_BLACK_TRANSPARENT)
            reaper.ImGui_Selectable(ctx, unique_id, is_selected, selectable_flags, -1, reserved_height)
            reaper.ImGui_PopStyleColor(ctx, 3)
            do
                local text_h = reaper.ImGui_GetTextLineHeight(ctx)
                local name_block_h = math.max(text_h, inline_icon_size_sel)
                local name_pad_y = compact_view and 3 or 4
                local meta_gap_y = compact_view and 0 or 6
                local meta_h = compact_view and 0 or reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
                local preview_path = get_preview_path_for_project(project)
                local is_enabled = (not is_unavailable) and (preview_path ~= nil)

                local row_area_h = row_bottom_y - row_visual_top
                local content_h
                if compact_view then
                    content_h = name_block_h
                else
                    content_h = name_block_h + meta_gap_y + meta_h
                end
                local slack = row_area_h - content_h
                if slack < 0 then slack = 0 end
                local title_top_y = row_visual_top + math.floor(slack / 2)

                local name_text_y = title_top_y + math.floor((name_block_h - text_h) / 2)
                local name_center_y = name_text_y + math.floor(text_h * 0.5)
                if compact_view then
                    name_text_y = name_text_y - 1
                end
                local date_text = nil
                local date_x = nil
                local right_limit = nil
                local primary_part = nil
                local primary_label = nil
                local primary_value = nil
                local secondary_label = nil
                local secondary_value = nil
                local open_row_dates = false
                local open_row_is_dirty = false
                local min_dates_w = 0
                if compact_view then
                    local modified_text = project.date or ""
                    local opened_text = project.opened_date or "Unknown"
                    if opened_text == "" then opened_text = "Unknown" end
                    local sort_mode_row = tostring((app_state.settings and app_state.settings.sort_mode) or "opened")
                    if is_open_row then
                        open_row_dates = true
                        if ProjectList and ProjectList.is_project_dirty then
                            local p_dirty = project and (project.full_path or project.path) or ""
                            if p_dirty ~= "" then
                                open_row_is_dirty = ProjectList.is_project_dirty(p_dirty) == true
                            end
                        end
                        primary_label = ""
                        primary_value = "Currently Open"
                        primary_part = primary_value
                        secondary_label = "Modified: "
                        secondary_value = open_row_is_dirty and (tostring(modified_text) .. " *") or modified_text
                    else
                        if sort_mode_row == "modified" then
                            primary_label = "Modified: "
                            primary_value = modified_text
                            primary_part = primary_label .. primary_value
                            secondary_label = "Opened: "
                            secondary_value = opened_text
                        else
                            primary_label = "Opened: "
                            primary_value = opened_text
                            primary_part = primary_label .. primary_value
                            secondary_label = "Modified: "
                            secondary_value = modified_text
                        end
                    end

                    local pin_pad_x = 8
                    local pin_w = 0
                    if reaper.ImGui_CalcTextSize then
                        if font and ICON_PIN and reaper.ImGui_PushFont and reaper.ImGui_PopFont then
                            local ok_push = pcall(reaper.ImGui_PushFont, ctx, font, font_size + 4.0)
                            if ok_push then
                                local w1 = select(1, reaper.ImGui_CalcTextSize(ctx, ICON_PIN)) or 0
                                local w2 = 0
                                if ICON_PIN_HOVER then
                                    w2 = select(1, reaper.ImGui_CalcTextSize(ctx, ICON_PIN_HOVER)) or 0
                                end
                                pin_w = math.max(w1, w2)
                                pcall(reaper.ImGui_PopFont, ctx)
                            end
                        end
                        if pin_w <= 0 then
                            pin_w = select(1, reaper.ImGui_CalcTextSize(ctx, "^")) or 0
                        end
                    end

                    local dates_extra_gap = 6
                    right_limit = (row_x + row_w) - pin_w - (pin_pad_x * 6) - dates_extra_gap
                    min_dates_w = select(1, reaper.ImGui_CalcTextSize(ctx, primary_part or "")) or 0
                end

                local name_max_w = math.max(0, (row_x + row_w) - (text_left_x + 2))
                local text_right_limit = nil
                if compact_view and right_limit ~= nil then
                    text_right_limit = (right_limit - (min_dates_w or 0) - 12)
                    name_max_w = math.max(0, text_right_limit - text_left_x)
                end
                local title_font_size = (font_size or 15.0) + 1.0
                local title_font_pushed = false
                if font and reaper.ImGui_PushFont then
                    local ok_title = pcall(reaper.ImGui_PushFont, ctx, font, title_font_size)
                    if ok_title then
                        title_font_pushed = true
                    end
                end
                local shown_name = fit_text_to_width(ctx, display_text or "", name_max_w)
                local name_x = text_left_x
                local name_w = select(1, reaper.ImGui_CalcTextSize(ctx, shown_name))
                reaper.ImGui_SetCursorScreenPos(ctx, name_x, name_text_y)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), name_col)
                reaper.ImGui_Text(ctx, shown_name)
                reaper.ImGui_PopStyleColor(ctx)
                if title_font_pushed and reaper.ImGui_PopFont then
                    pcall(reaper.ImGui_PopFont, ctx)
                end
                local left_end_x = name_x + (name_w or 0)
                if compact_view and right_limit ~= nil and primary_part ~= nil then
                    local avail_for_dates = right_limit - (left_end_x + 12)
                    if avail_for_dates < 0 then avail_for_dates = 0 end

                    local gap_s = "    "
                    local gap_w = select(1, reaper.ImGui_CalcTextSize(ctx, gap_s)) or 0
                    local secondary_label_w = select(1, reaper.ImGui_CalcTextSize(ctx, secondary_label or "")) or 0
                    local ellipsis_w = select(1, reaper.ImGui_CalcTextSize(ctx, "...")) or 0
                    local primary_w = select(1, reaper.ImGui_CalcTextSize(ctx, primary_part)) or 0

                    date_text = primary_part
                    if primary_label ~= nil and primary_value ~= nil and avail_for_dates < primary_w then
                        local label_w = select(1, reaper.ImGui_CalcTextSize(ctx, primary_label)) or 0
                        local max_val_w = avail_for_dates - label_w
                        if max_val_w < 0 then max_val_w = 0 end
                        local shown_val = fit_text_to_width(ctx, tostring(primary_value or ""), max_val_w)
                        date_text = primary_label .. shown_val
                        primary_w = select(1, reaper.ImGui_CalcTextSize(ctx, date_text)) or 0
                    end
                    if secondary_label ~= nil and secondary_value ~= nil then
                        local min_secondary_w = gap_w + secondary_label_w + ellipsis_w
                        if avail_for_dates >= (primary_w + min_secondary_w) then
                            local max_val_w = avail_for_dates - (primary_w + gap_w + secondary_label_w)
                            if max_val_w < ellipsis_w then
                                date_text = primary_part .. gap_s .. secondary_label .. "..."
                            else
                                local shown_val = fit_text_to_width(ctx, tostring(secondary_value or ""), max_val_w)
                                date_text = primary_part .. gap_s .. secondary_label .. shown_val
                            end
                        end
                    end

                    local date_w = select(1, reaper.ImGui_CalcTextSize(ctx, date_text)) or 0
                    date_x = math.floor((right_limit - date_w) + 0.5)
                    local dl = reaper.ImGui_GetWindowDrawList(ctx)
                    if dl then
                        local compact_font_pushed = false
                        if font and reaper.ImGui_PushFont then
                            local ok_font = pcall(reaper.ImGui_PushFont, ctx, font, meta_font_size)
                            if ok_font then
                                compact_font_pushed = true
                            end
                        end
                        local meta_text_h = reaper.ImGui_GetTextLineHeight(ctx)
                        local date_text_y = name_center_y - math.floor(meta_text_h * 0.5)
                        if open_row_dates then
                            local open_text = fit_text_to_width(ctx, "Currently Open", avail_for_dates)
                            local open_w = select(1, reaper.ImGui_CalcTextSize(ctx, open_text)) or 0
                            local mod_col = open_row_is_dirty and COLOR_CLOSE_BASE or COLOR_TEXT_BLACK
                            local mod_text = nil
                            local mod_w = 0
                            if open_w + gap_w + secondary_label_w + ellipsis_w <= avail_for_dates then
                                local max_mod_w = avail_for_dates - (open_w + gap_w)
                                mod_text = fit_text_to_width(ctx, tostring(secondary_label or "") .. tostring(secondary_value or ""), max_mod_w)
                                mod_w = select(1, reaper.ImGui_CalcTextSize(ctx, mod_text)) or 0
                            end
                            local total_w = open_w + ((mod_text and mod_w > 0) and (gap_w + mod_w) or 0)
                            local start_x = math.floor((right_limit - total_w) + 0.5)
                            reaper.ImGui_DrawList_AddText(dl, start_x, date_text_y, COLOR_ACCENT_DARK, open_text)
                            if mod_text and mod_w > 0 then
                                reaper.ImGui_DrawList_AddText(dl, start_x + open_w + gap_w, date_text_y, mod_col, mod_text)
                            end
                        else
                            reaper.ImGui_DrawList_AddText(dl, date_x, date_text_y, COLOR_META_TEXT_SECONDARY, date_text)
                        end
                        if compact_font_pushed and reaper.ImGui_PopFont then
                            pcall(reaper.ImGui_PopFont, ctx)
                        end
                    end
                end
            end
            if not (reaper.ImGui_OpenPopup and reaper.ImGui_BeginPopup) then
                local cc, vc = push_context_menu_style(ctx)
                if reaper.ImGui_BeginPopupContextItem(ctx) then
                    app_state.selected_rows = app_state.selected_rows or {}
                    local current_section_ctx = section or ((ProjectList and ProjectList.get_project_ui_section) and ProjectList.get_project_ui_section(project) or "rest")
                    if app_state.selection_section ~= nil and app_state.selection_section ~= current_section_ctx then
                        for k in pairs(app_state.selected_rows) do
                            app_state.selected_rows[k] = nil
                        end
                        app_state.selection_anchor_index = nil
                    end
                    app_state.selection_section = current_section_ctx
                    app_state.selected_rows[i] = true
                    app_state.selected_project = i
                    if app_state.settings then
                        local p = project and (project.full_path or project.path) or nil
                        if p and p ~= "" then
                            app_state.settings.selected_project_path = p
                            if app_state.save_settings then
                                app_state.save_settings(app_state.settings)
                            end
                        end
                    end
                    show_context_menu(app_state, project)
                    reaper.ImGui_EndPopup(ctx)
                end
                pop_context_menu_style(ctx, cc, vc)
            end

            reaper.ImGui_Unindent(ctx, indent_w)
            reaper.ImGui_PopStyleColor(ctx)

            do
                local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
                if is_unavailable then
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, row_x, row_visual_top, row_x + row_w, row_bottom_y, COLOR_ROW_BG_SELECTED)
                end
                local cur_x = select(1, reaper.ImGui_GetCursorScreenPos(ctx))
                local avail_w_line = reaper.ImGui_GetContentRegionAvail(ctx)
                local text_h = reaper.ImGui_GetTextLineHeight(ctx)
                local name_pad_y = compact_view and 3 or 4
                local meta_gap_y = compact_view and 0 or 6
                local bar_gap_y = 2
                local meta_h = compact_view and 0 or reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
                local inline_icon_size = inline_icon_size_sel
                local name_block_h = math.max(text_h, inline_icon_size)
                local seek_h = math.max(6, math.floor(reaper.ImGui_GetFrameHeight(ctx) * 0.35))

                local is_selected_row = app_state.selected_rows[i] == true or (app_state.selected_project == i)
                local preview_path = get_preview_path_for_project(project)
                local is_enabled = preview_path ~= nil

                local title_top_y
                if compact_view then
                    local slack = reserved_height - name_block_h
                    if slack < 0 then slack = 0 end
                    title_top_y = row_y + math.floor(slack / 2)
                else
                    local content_h = name_block_h + meta_gap_y + meta_h
                    local slack = reserved_height - content_h
                    if slack < 0 then slack = 0 end
                    title_top_y = row_y + math.floor(slack / 2)
                end

                local icon_zone_w = math.max(0, text_left_x - orig_x)
                local icon_x = orig_x + math.floor((icon_zone_w - inline_icon_size) / 2)
                local row_area_h = row_bottom_y - row_visual_top
                local icon_y = row_visual_top + math.floor((row_area_h - inline_icon_size) / 2)
                reaper.ImGui_SetCursorScreenPos(ctx, icon_x, icon_y)
                play_column_center_x = icon_x + math.floor(inline_icon_size * 0.5)
                local is_playing_row = false
                if status and status.playing and status.path and preview_path and normalize_path(status.path) == normalize_path(preview_path) then
                    is_playing_row = true
                end
                local play_id_inline = "##play_inline_" .. i
                local active_icon = is_playing_row and is_enabled
                local icon_text = ICON_PLAY
                if active_icon then
                    icon_text = ICON_STOP
                end
                local style_inline = nil
                if is_open_row then
                    style_inline = { variant = "open_row" }
                end
                local inline_play_clicked, is_hovered_inline =
                    draw_transport_icon_button(ctx, play_id_inline, icon_text, inline_icon_size, is_enabled, active_icon, style_inline)
                if is_hovered_inline then
                    inline_hovered_index = i
                elseif inline_hovered_index == i then
                    inline_hovered_index = nil
                end
                if is_hovered_inline then
                    if not is_enabled then
                        show_delayed_tooltip(
                            "play_inline_" .. i,
                            { "No preview yet.", "You can create a preview via the context menu." },
                            true
                        )
                    else
                        local modified_text = project.date or ""
                        local opened_text = project.opened_date or "Unknown"
                        local sort_mode_tip = tostring((app_state.settings and app_state.settings.sort_mode) or "opened")
                        local line1
                        local line2
                        if sort_mode_tip == "modified" then
                            line1 = "Modified: " .. modified_text
                            line2 = "Opened: " .. opened_text
                        else
                            line1 = "Opened: " .. opened_text
                            line2 = "Modified: " .. modified_text
                        end
                        local lines = { line1, line2 }
                        local pm = safe_get_preview_meta(ProjectList, project, preview_path)
                        if pm and pm.stale_seconds ~= nil then
                            local stale_s = format_stale_age(pm.stale_seconds)
                            if stale_s and stale_s ~= "" then
                                lines[#lines + 1] = stale_s
                            end
                        end
                        show_delayed_tooltip("play_inline_" .. i, lines, true)
                    end
                end
                local draw_list_btn = reaper.ImGui_GetWindowDrawList(ctx)
                if font and ICON_PIN and reaper.ImGui_PushFont and reaper.ImGui_GetMousePos then
                    local pin_font_pushed = false
                    local ok_pin = pcall(reaper.ImGui_PushFont, ctx, font, font_size + 4.0)
                    if ok_pin then
                        pin_font_pushed = true
                        local pin_mark = ICON_PIN
                        local tw, th = reaper.ImGui_CalcTextSize(ctx, pin_mark)
                        local pin_pad_x = compact_view and 8 or 10
                        local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
                        local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
                        local right_x = cur_x + avail_w_line - pin_pad_x
                        if win_x and win_w then
                            right_x = win_x + win_w - (pin_pad_x + 10)
                        end
                        local tx = right_x - tw
                        local row_area_h = row_bottom_y - row_visual_top
                        local function compute_pin_ty(h_text)
                            local base = title_top_y + math.floor((name_block_h - h_text) / 2)
                            if compact_view then
                                return base - 1
                            end
                            return base
                        end
                        local ty = compute_pin_ty(th)
                        pin_column_center_x = right_x - math.floor(tw * 0.5)
                        local mx, my = reaper.ImGui_GetMousePos(ctx)
                        local icon_hovered = false
                        if mx and my then
                            if mx >= tx and mx <= (tx + tw) and my >= ty and my <= (ty + th) then
                                icon_hovered = true
                            end
                        end
                        local is_pinned_row = project and project.is_pinned
                        if is_pinned_row then
                            if icon_hovered and ICON_PIN_HOVER then
                                pin_mark = ICON_PIN_HOVER
                                tw, th = reaper.ImGui_CalcTextSize(ctx, pin_mark)
                                tx = right_x - tw
                                ty = compute_pin_ty(th)
                            end
                        else
                            if ICON_PIN_HOVER then
                                pin_mark = ICON_PIN_HOVER
                                tw, th = reaper.ImGui_CalcTextSize(ctx, pin_mark)
                                tx = right_x - tw
                                ty = compute_pin_ty(th)
                            end
                            if icon_hovered and ICON_PIN then
                                pin_mark = ICON_PIN
                                tw, th = reaper.ImGui_CalcTextSize(ctx, pin_mark)
                                tx = right_x - tw
                                ty = compute_pin_ty(th)
                            end
                        end
                        local draw_pin = false
                        local pin_col = COLOR_META_TEXT_SECONDARY
                        if is_open_row then
                            if is_pinned_row or row_hovered then
                                draw_pin = true
                                if icon_hovered then
                                    pin_col = COLOR_TEXT_BLACK
                                else
                                    pin_col = color_mul_rgb(COLOR_TEXT_MUTED, 0.35)
                                end
                            end
                        else
                            if is_pinned_row then
                                draw_pin = true
                                if icon_hovered then
                                    pin_col = COLOR_TEXT
                                else
                                    pin_col = COLOR_META_TEXT_SECONDARY
                                end
                            elseif row_hovered then
                                draw_pin = true
                                if icon_hovered then
                                    pin_col = COLOR_TEXT
                                else
                                    pin_col = COLOR_META_TEXT_SECONDARY
                                end
                            end
                        end
                        local pin_clicked = icon_hovered and reaper.ImGui_IsMouseClicked and reaper.ImGui_IsMouseClicked(ctx, 0)
                        if icon_hovered then
                            local tip = is_pinned_row and "Unpin Track" or "Pin Track"
                            show_delayed_tooltip("pin_project_" .. i, { tip }, true)
                        end
                        if draw_pin then
                            reaper.ImGui_DrawList_AddText(draw_list_btn, tx, ty, pin_col, pin_mark)
                        end
                        if pin_clicked and ProjectList and ProjectList.toggle_project_pinned and app_state and app_state.settings then
                            local project_path = project and (project.full_path or project.path) or ""
                            if project_path ~= "" then
                                ProjectList.toggle_project_pinned(app_state.settings, project_path)
                                project.is_pinned = not not ((ProjectList.is_project_pinned and ProjectList.is_project_pinned(app_state.settings, project_path)) or false)
                                if app_state.save_settings then
                                    app_state.save_settings(app_state.settings)
                                end
                                regroup_filtered_projects(app_state)
                            end
                        end
                        if row_hovered and not is_open_row then
                            local caret_char = "▾"
                            local caret_open = false
                            if is_project_meta_open(app_state, project) then
                                caret_open = true
                            end
                            if caret_open then
                                caret_char = "▴"
                            end
                            local caret_font_pushed = false
                            if font and reaper.ImGui_PushFont then
                                local ok_caret = pcall(reaper.ImGui_PushFont, ctx, font, font_size + 12.0)
                                if ok_caret then
                                    caret_font_pushed = true
                                end
                            end
                            local cw, ch = reaper.ImGui_CalcTextSize(ctx, caret_char)
                            local caret_tx
                            if compact_view then
                                local gap_x = 4
                                if pin_column_center_x ~= nil then
                                    local pin_left = pin_column_center_x - math.floor(tw * 0.5)
                                    caret_tx = pin_left - gap_x - cw
                                else
                                    caret_tx = tx - gap_x - cw
                                end
                            else
                                local caret_cx = tx + math.floor(tw * 0.5)
                                if pin_column_center_x ~= nil then
                                    caret_cx = pin_column_center_x
                                end
                                caret_tx = caret_cx - math.floor(cw * 0.5)
                            end
                            local caret_ty = row_bottom_y - ch - 2
                            local hit_x1 = caret_tx - 3
                            local hit_x2 = caret_tx + cw + 3
                            local hit_y1 = caret_ty - 2
                            local hit_y2 = row_bottom_y
                            local mx2, my2 = reaper.ImGui_GetMousePos(ctx)
                            local caret_hovered = false
                            if mx2 and my2 then
                                if mx2 >= hit_x1 and mx2 <= hit_x2 and my2 >= hit_y1 and my2 <= hit_y2 then
                                    caret_hovered = true
                                end
                            end
                            local caret_col = COLOR_META_TEXT_SECONDARY
                            if caret_hovered then
                                caret_col = COLOR_TEXT
                            end
                            reaper.ImGui_DrawList_AddText(draw_list_btn, caret_tx, caret_ty, caret_col, caret_char)
                            if caret_hovered then
                                local tip = "Get Metadata"
                                show_delayed_tooltip("meta_toggle_" .. i, { tip }, true)
                            end
                            if caret_font_pushed and reaper.ImGui_PopFont then
                                pcall(reaper.ImGui_PopFont, ctx)
                            end
                            if caret_hovered and reaper.ImGui_IsMouseClicked and reaper.ImGui_IsMouseClicked(ctx, 0) then
                                toggle_project_metadata(app_state, project)
                                meta_icon_clicked = true
                            end
                        end
                    end
                    if pin_font_pushed and reaper.ImGui_PopFont then
                        pcall(reaper.ImGui_PopFont, ctx)
                    end
                elseif project and project.is_pinned then
                    local pin_mark = "^"
                    local tw, th = reaper.ImGui_CalcTextSize(ctx, pin_mark)
                    local pin_pad_x = compact_view and 8 or 10
                    local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
                    local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
                    local right_x = cur_x + avail_w_line - pin_pad_x
                    if win_x and win_w then
                        right_x = win_x + win_w - (pin_pad_x + 10)
                    end
                    local tx = right_x - tw
                    local row_area_h = row_bottom_y - row_visual_top
                    local ty
                    if compact_view then
                        ty = row_visual_top + math.floor((row_area_h - th) / 2) - 1
                    else
                        ty = title_top_y + math.floor((name_block_h - th) / 2)
                    end
                    reaper.ImGui_DrawList_AddText(draw_list_btn, tx, ty, playhead_marker_color, pin_mark)
                end
                if inline_play_clicked and not is_unavailable then
                    app_state.selected_rows = app_state.selected_rows or {}
                    local current_section = section or ((ProjectList and ProjectList.get_project_ui_section) and ProjectList.get_project_ui_section(project) or "rest")
                    -- При клике по Play всегда делаем одиночное выделение строки
                    for k in pairs(app_state.selected_rows) do
                        app_state.selected_rows[k] = nil
                    end
                    app_state.selection_section = current_section
                    app_state.selected_rows[i] = true
                    app_state.selected_project = i
                    app_state.selection_anchor_index = i
                    if app_state.settings then
                        local p = project and (project.full_path or project.path) or nil
                        if p and p ~= "" then
                            app_state.settings.selected_project_path = p
                            if app_state.save_settings then
                                app_state.save_settings(app_state.settings)
                            end
                        end
                    end
                    project.preview_path = preview_path
                    project.has_preview = preview_path ~= nil
                    if ProjectList and ProjectList.refresh_project_meta then
                        ProjectList.refresh_project_meta(project)
                    end
                    if is_enabled then
                        if is_playing_row then
                            ProjectList.stop_preview()
                            status = ProjectList.get_preview_status and ProjectList.get_preview_status()
                        else
                            local path = get_preview_path_for_project(project)
                            if path and ProjectList.play_preview(path) then
                                status = ProjectList.get_preview_status and ProjectList.get_preview_status()
                            end
                        end
                    end
                    if status and status.playing and status.path and preview_path and normalize_path(status.path) == normalize_path(preview_path) then
                        is_playing_row = true
                    else
                        is_playing_row = false
                    end
                end
                if compact_view then
                    reaper.ImGui_SetCursorScreenPos(ctx, cur_x, row_bottom_y)
                    reaper.ImGui_Dummy(ctx, 1, 1)
                else
                    local meta_y = title_top_y + name_block_h + meta_gap_y
                    local bar_x = text_left_x
                    local right_limit = cur_x + avail_w_line - 6
                    local bar_right = right_limit - 40
                    if bar_right < bar_x then
                        bar_right = bar_x
                    end
                    local bar_w = math.max(0, bar_right - bar_x)
                    local next_y = row_bottom_y

                    local modified_text = project.date or ""
                    local opened_text = project.opened_date or "Unknown"
                    local meta_x = text_left_x
                    local meta_h_local = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
                    local sort_mode_row = tostring((app_state.settings and app_state.settings.sort_mode) or "opened")
                    local meta_line = nil
                    local meta_col = COLOR_META_TEXT_SECONDARY

                    local meta_font_pushed = false
                    if font and reaper.ImGui_PushFont then
                        local ok_meta = pcall(reaper.ImGui_PushFont, ctx, font, meta_font_size)
                        if ok_meta then
                            meta_font_pushed = true
                        end
                    end

                    local size_s = nil
                    local project_path = project and (project.full_path or project.path) or ""
                    if ProjectList and ProjectList.get_project_file_size and project_path ~= "" then
                        local size_bytes = ProjectList.get_project_file_size(project_path)
                        if size_bytes and size_bytes > 0 then
                            size_s = format_bytes_iec(size_bytes)
                        end
                    end

                    if not (is_selected_row and is_enabled and is_playing_row) then
                        if is_open_row then
                            local is_dirty = false
                            if ProjectList and ProjectList.is_project_dirty then
                                local p_dirty = project and (project.full_path or project.path) or ""
                                if p_dirty ~= "" then
                                    is_dirty = ProjectList.is_project_dirty(p_dirty)
                                end
                            end
                            local modified_label = is_dirty and ("Modified: " .. modified_text .. " *") or ("Modified: " .. modified_text)
                            if size_s then
                                modified_label = modified_label .. "    Size: " .. size_s
                            end
                            local label_open = "Currently Open    "
                            local label_mod = modified_label
                            reaper.ImGui_SetCursorScreenPos(ctx, meta_x, meta_y)
                            local draw_list_meta = reaper.ImGui_GetWindowDrawList(ctx)
                            if draw_list_meta then
                                local lx, ly = reaper.ImGui_GetCursorScreenPos(ctx)
                                reaper.ImGui_DrawList_AddText(draw_list_meta, lx, ly, COLOR_ACCENT_DARK, label_open)
                                local w_open = select(1, reaper.ImGui_CalcTextSize(ctx, label_open))
                                local mod_col = is_dirty and COLOR_CLOSE_BASE or COLOR_TEXT_BLACK
                                reaper.ImGui_DrawList_AddText(draw_list_meta, lx + w_open, ly, mod_col, label_mod)
                            end
                        else
                            if sort_mode_row == "modified" then
                                meta_line = "Modified: " .. modified_text .. "    Opened: " .. opened_text
                            else
                                meta_line = "Opened: " .. opened_text .. "    Modified: " .. modified_text
                            end
                            if size_s then
                                meta_line = meta_line .. "    Size: " .. size_s
                            end
                            local path_label = ""
                            if project_path and project_path ~= "" then
                                local folder = project_path:match("(.+)[/\\][^/\\]+$") or ""
                                if folder ~= "" then
                                    local last = folder:sub(-1)
                                    if last ~= "/" and last ~= "\\" then
                                        folder = folder .. "/"
                                    end
                                end
                                path_label = folder
                            end
                            local win_w = select(1, reaper.ImGui_GetWindowSize(ctx)) or 0
                            local show_path = path_label ~= "" and win_w >= PATH_MIN_WINDOW_W
                            if show_path then
                                local base_line = meta_line
                                local sep = "    "
                                local base_text = base_line .. sep
                                local base_w = select(1, reaper.ImGui_CalcTextSize(ctx, base_text)) or 0
                                local right_for_path = right_limit - PATH_RIGHT_ICON_RESERVE
                                if right_for_path < (meta_x + base_w) then
                                    right_for_path = meta_x + base_w
                                end
                                local avail_total = math.max(0, right_for_path - meta_x)
                                local avail_path = math.max(0, avail_total - base_w)

                                reaper.ImGui_SetCursorScreenPos(ctx, meta_x, meta_y)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), meta_col)
                                reaper.ImGui_Text(ctx, base_text)
                                reaper.ImGui_PopStyleColor(ctx, 1)

                                if avail_path > 0 then
                                    local draw_list_meta = reaper.ImGui_GetWindowDrawList(ctx)
                                    if draw_list_meta then
                                        local path_w = select(1, reaper.ImGui_CalcTextSize(ctx, path_label)) or 0
                                        local path_x = meta_x + base_w
                                        local path_y = meta_y
                                        local line_h = meta_h_local
                                        local mx, my = reaper.ImGui_GetMousePos(ctx)
                                        local hit_x1 = path_x
                                        local hit_y1 = path_y
                                        local hit_x2 = path_x + avail_path
                                        local hit_y2 = path_y + line_h
                                        local hovered_path = false
                                        if mx and my then
                                            if mx >= hit_x1 and mx <= hit_x2 and my >= hit_y1 and my <= hit_y2 then
                                                hovered_path = true
                                            end
                                        end
                                        local path_col = hovered_path and COLOR_TEXT or meta_col

                                        if path_w <= avail_path then
                                            if reaper.ImGui_PushClipRect and reaper.ImGui_PopClipRect then
                                                reaper.ImGui_PushClipRect(ctx, path_x, path_y, path_x + avail_path, path_y + line_h, true)
                                                reaper.ImGui_DrawList_AddText(draw_list_meta, path_x, path_y, path_col, path_label)
                                                reaper.ImGui_PopClipRect(ctx)
                                            else
                                                reaper.ImGui_DrawList_AddText(draw_list_meta, path_x, path_y, path_col, path_label)
                                            end
                                        else
                                            local now = reaper.time_precise and reaper.time_precise() or os.clock()
                                            local speed = PATH_SCROLL_SPEED
                                            local gap = PATH_SCROLL_GAP
                                            local loop_w = path_w + gap
                                            local offset = 0
                                            if loop_w > 0 then
                                                offset = (now * speed) % loop_w
                                            end
                                            local base_x = path_x - offset
                                            if reaper.ImGui_PushClipRect and reaper.ImGui_PopClipRect then
                                                reaper.ImGui_PushClipRect(ctx, path_x, path_y, path_x + avail_path, path_y + line_h, true)
                                                reaper.ImGui_DrawList_AddText(draw_list_meta, base_x, path_y, path_col, path_label)
                                                reaper.ImGui_DrawList_AddText(draw_list_meta, base_x + loop_w, path_y, path_col, path_label)
                                                reaper.ImGui_PopClipRect(ctx)
                                            else
                                                reaper.ImGui_DrawList_AddText(draw_list_meta, path_x, path_y, path_col, path_label)
                                            end
                                        end

                                        if hovered_path and ProjectList and ProjectList.show_in_file_manager and reaper.ImGui_IsMouseClicked and reaper.ImGui_IsMouseClicked(ctx, 0) then
                                            ProjectList.show_in_file_manager(project_path)
                                        end
                                    end
                                end
                            else
                                reaper.ImGui_SetCursorScreenPos(ctx, meta_x, meta_y)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), meta_col)
                                reaper.ImGui_Text(ctx, meta_line)
                                reaper.ImGui_PopStyleColor(ctx, 1)
                            end
                        end
                    end

                    if meta_font_pushed and reaper.ImGui_PopFont then
                        pcall(reaper.ImGui_PopFont, ctx)
                    end

                    if is_selected_row and is_enabled and is_playing_row then
                        local regions = nil
                        if ProjectList and ProjectList.get_project_regions then
                            regions = ProjectList.get_project_regions(project.full_path or project.path)
                        end
                        local duration = preview_path and get_duration_cached(preview_path) or nil
                        local timeline_min, timeline_span, timeline_origin = compute_timeline(regions, duration, status)

                        local ratio_play = 0.0
                        if is_playing_row and timeline_span and timeline_span > 0 and status and status.elapsed then
                            ratio_play = math.min(1.0, math.max(0.0, (((status.elapsed or 0) + (timeline_origin or 0.0)) - (timeline_min or 0.0)) / timeline_span))
                        end

                        local bar_y = meta_y + math.floor((meta_h_local - seek_h) * 0.5)
                        draw_timeline(ctx, draw_list, "##row_seek_" .. i, bar_x, bar_y, bar_w, seek_h, {
                            is_enabled = is_enabled,
                            preview_path = preview_path,
                            regions = regions,
                            timeline_min = timeline_min,
                            timeline_span = timeline_span,
                            timeline_origin = timeline_origin,
                            ratio_play = ratio_play,
                            on_seek = function(seek_pos)
                                if not preview_path or not is_enabled then return end
                                local st = ProjectList.get_preview_status and ProjectList.get_preview_status()
                                local is_this = st and st.playing and st.path and normalize_path(st.path) == normalize_path(preview_path)
                                if not is_this then
                                    if ProjectList.stop_preview then
                                        ProjectList.stop_preview()
                                    end
                                    if ProjectList.play_preview then
                                        ProjectList.play_preview(preview_path)
                                    end
                                end
                                if ProjectList and ProjectList.seek_preview and ProjectList.seek_preview(seek_pos) then
                                    status = ProjectList.get_preview_status and ProjectList.get_preview_status()
                                else
                                    status = ProjectList.get_preview_status and ProjectList.get_preview_status()
                                end
                            end,
                            tooltip_key = "row_seek_" .. i,
                            radius = 3,
                            snap_mode = "start",
                            enable_hover_snap = true,
                            enable_tooltip_inside_region = true,
                            draw_play_fill = true,
                            show_playhead = true,
                            show_nav_line = true,
                            draw_region_blocks = false,
                            draw_region_separators = true,
                            separator_style = "solid",
                            tooltip_snap_tol = math.max(6, math.floor(seek_h * 0.60)),
                            click_snap_tol = math.max(10, math.floor(seek_h * 2.0)),
                            hover_snap_tol = math.max(10, math.floor(seek_h * 2.0)),
                            hit_margin_factor = 1.0,
                            seek_override_duration = 0.12,
                        })
                    end
                    reaper.ImGui_SetCursorScreenPos(ctx, cur_x, next_y)
                    reaper.ImGui_Dummy(ctx, 1, 1)
                end

                do
                    local any_click = (row_left_click or row_double_click) and not meta_icon_clicked
                    if any_click and not inline_play_clicked and not is_unavailable then
                        app_state.selected_rows = app_state.selected_rows or {}
                        local keymods = reaper.ImGui_GetKeyMods and reaper.ImGui_GetKeyMods(ctx) or 0
                        local super_mod = reaper.ImGui_Mod_Super and reaper.ImGui_Mod_Super() or 0
                        local ctrl_mod = reaper.ImGui_Mod_Ctrl and reaper.ImGui_Mod_Ctrl() or 0
                        local shift_mod = reaper.ImGui_Mod_Shift and reaper.ImGui_Mod_Shift() or 0
                        local cmd_down = false
                        if ctrl_mod ~= 0 then
                            cmd_down = (keymods & ctrl_mod) ~= 0
                        elseif super_mod ~= 0 then
                            cmd_down = (keymods & super_mod) ~= 0
                        end
                        local shift_down = (shift_mod ~= 0 and (keymods & shift_mod) ~= 0)

                        local current_section = section or "rest"
                        if app_state.selection_section ~= nil and app_state.selection_section ~= current_section then
                            for k in pairs(app_state.selected_rows) do
                                app_state.selected_rows[k] = nil
                            end
                            app_state.selection_anchor_index = nil
                        end
                        app_state.selection_section = current_section

                        if row_left_click and not row_right_click then
                            if shift_down then
                                local anchor = app_state.selection_anchor_index or app_state.selected_project or i
                                if not anchor or anchor < 1 or anchor > #app_state.filtered_projects then
                                    anchor = i
                                end
                                for k in pairs(app_state.selected_rows) do
                                    app_state.selected_rows[k] = nil
                                end
                                local from_i = math.min(anchor, i)
                                local to_i = math.max(anchor, i)
                                for idx = from_i, to_i do
                                    app_state.selected_rows[idx] = true
                                    app_state.selected_project = idx
                                end
                                app_state.selection_anchor_index = anchor
                            elseif cmd_down then
                                local already = app_state.selected_rows[i] == true
                                if already then
                                    app_state.selected_rows[i] = nil
                                    if app_state.selected_project == i then
                                        local new_sel = nil
                                        for idx in pairs(app_state.selected_rows) do
                                            if not new_sel or idx < new_sel then
                                                new_sel = idx
                                            end
                                        end
                                        app_state.selected_project = new_sel
                                        app_state.selection_anchor_index = new_sel
                                    end
                                else
                                    app_state.selected_rows[i] = true
                                    app_state.selected_project = i
                                    app_state.selection_anchor_index = i
                                end
                            else
                                for k in pairs(app_state.selected_rows) do
                                    app_state.selected_rows[k] = nil
                                end
                                app_state.selected_rows[i] = true
                                app_state.selected_project = i
                                app_state.selection_anchor_index = i
                            end
                        else
                            if row_right_click then
                                if not app_state.selected_rows[i] then
                                    for k in pairs(app_state.selected_rows) do
                                        app_state.selected_rows[k] = nil
                                    end
                                    app_state.selected_rows[i] = true
                                    app_state.selected_project = i
                                    app_state.selection_anchor_index = i
                                end
                            else
                                for k in pairs(app_state.selected_rows) do
                                    app_state.selected_rows[k] = nil
                                end
                                app_state.selected_rows[i] = true
                                app_state.selected_project = i
                                app_state.selection_anchor_index = i
                            end
                        end

                        if app_state.settings then
                            local p = project and (project.full_path or project.path) or nil
                            if p and p ~= "" then
                                app_state.settings.selected_project_path = p
                                if app_state.save_settings then
                                    app_state.save_settings(app_state.settings)
                                end
                            end
                        end
                        local pp = get_preview_path_for_project(project)
                        project.preview_path = pp
                        project.has_preview = pp ~= nil
                        if ProjectList and ProjectList.refresh_project_meta then
                            ProjectList.refresh_project_meta(project)
                        end

                        if row_double_click and not is_open_row then
                            local mods = reaper.ImGui_GetKeyMods and reaper.ImGui_GetKeyMods(ctx) or 0
                            local shift_flag = reaper.ImGui_Mod_Shift and reaper.ImGui_Mod_Shift() or 0
                            local ctrl_flag = reaper.ImGui_Mod_Ctrl and reaper.ImGui_Mod_Ctrl() or 0
                            local super_flag = reaper.ImGui_Mod_Super and reaper.ImGui_Mod_Super() or 0
                            local has_shift = (shift_flag ~= 0) and ((mods & shift_flag) ~= 0) or false
                            local has_cmd = (ctrl_flag ~= 0 and (mods & ctrl_flag) ~= 0)
                                or (super_flag ~= 0 and (mods & super_flag) ~= 0)
                            if has_cmd then
                                toggle_project_metadata(app_state, project)
                            else
                                if has_shift then
                                    ProjectList.open_project_new_tab(project.full_path)
                                else
                                    ProjectList.open_project(project.full_path)
                                end
                                if not app_state.pin_on_screen then
                                    open = false
                                end
                            end
                        else
                            if row_left_click and status and status.playing then
                                if pp and ProjectList and ProjectList.play_preview then
                                    if not (status.path and normalize_path(status.path) == normalize_path(pp)) then
                                        if ProjectList.stop_preview then
                                            ProjectList.stop_preview()
                                        end
                                        if ProjectList.play_preview(pp) then
                                            status = ProjectList.get_preview_status and ProjectList.get_preview_status()
                                        end
                                    end
                                elseif ProjectList and ProjectList.stop_preview then
                                    ProjectList.stop_preview()
                                    status = ProjectList.get_preview_status and ProjectList.get_preview_status()
                                end
                            end
                        end
                    end
                end

                do
                    local has_popup = reaper.ImGui_OpenPopup and reaper.ImGui_BeginPopup
                    local popup_id = "##project_ctx_" .. i
                    if has_popup and row_right_click then
                        app_state.selected_project = i
                        if app_state.settings then
                            local p = project and (project.full_path or project.path) or nil
                            if p and p ~= "" then
                                app_state.settings.selected_project_path = p
                                if app_state.save_settings then
                                    app_state.save_settings(app_state.settings)
                                end
                            end
                        end
                        reaper.ImGui_OpenPopup(ctx, popup_id)
                    end
                    if has_popup then
                        local cc, vc = push_context_menu_style(ctx)
                        if reaper.ImGui_BeginPopup(ctx, popup_id) then
                            show_context_menu(app_state, project)
                            reaper.ImGui_EndPopup(ctx)
                        end
                        pop_context_menu_style(ctx, cc, vc)
                    end
                end
            end

            if not is_last_row and not compact_view then
                local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
                local sep_x1 = row_x
                local sep_x2 = row_x + row_w
                local sep_y1 = row_bottom_y
                local sep_y2 = row_bottom_y + 1
                reaper.ImGui_DrawList_AddLine(draw_list, sep_x1, sep_y1, sep_x2, sep_y1, COLOR_INLINE_BORDER_LIGHT)
                reaper.ImGui_DrawList_AddLine(draw_list, sep_x1, sep_y2, sep_x2, sep_y2, COLOR_INLINE_BORDER_DARK)
            end
        end

        local open_count = #open_indices

        local header_pad_top = 2
        local header_pad_bottom = 2
        local header_sep_pad_bottom = 1
        local header_text_pad_x = 8
        local separator_pad_bottom = 6
        local open_section_footer = false
        local function draw_section_header(label)
            local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
            local w = select(1, reaper.ImGui_GetContentRegionAvail(ctx)) or 0
            if w < 0 then w = 0 end

            local font_pushed = false
            if font and reaper.ImGui_PushFont then
                local ok = pcall(reaper.ImGui_PushFont, ctx, font, math.max(10.0, font_size * 0.85))
                if ok then
                    font_pushed = true
                end
            end

            local pad_scale = 0.6
            local pad_top = math.max(1, math.floor(header_pad_top * pad_scale + 0.5))
            local pad_bottom = math.max(1, math.floor(header_pad_bottom * pad_scale + 0.5))
            local sep_pad_bottom = math.max(1, math.floor(header_sep_pad_bottom * pad_scale + 0.5))

            local line_h = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
            local header_h = pad_top + pad_bottom + line_h
            local _, th = reaper.ImGui_CalcTextSize(ctx, label)
            local dl = reaper.ImGui_GetWindowDrawList(ctx)
            if dl and x and y then
                local header_bg_col = COLOR_META_PANEL_BG
                if w > 0 and header_h > 0 then
                    reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + header_h, header_bg_col)
                end
                local tx = x + header_text_pad_x
                local ty = y + math.floor((header_h - th) * 0.5)
                reaper.ImGui_DrawList_AddText(dl, tx, ty, COLOR_META_TEXT_SECONDARY, label)
            end
            reaper.ImGui_Dummy(ctx, 1, header_h)
            local sep_x, sep_y = reaper.ImGui_GetCursorScreenPos(ctx)
            local sep_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx)) or 0
            if sep_w > 0 then
                local dl2 = reaper.ImGui_GetWindowDrawList(ctx)
                reaper.ImGui_DrawList_AddLine(dl2, sep_x, sep_y, sep_x + sep_w, sep_y, COLOR_TIMELINE_REGION_SEPARATOR_SOFT, 1.0)
            end
            reaper.ImGui_Dummy(ctx, 1, sep_pad_bottom)

            if font_pushed and reaper.ImGui_PopFont then
                pcall(reaper.ImGui_PopFont, ctx)
            end
        end

        local function draw_section_separator()
            local sep_x, sep_y = reaper.ImGui_GetCursorScreenPos(ctx)
            local sep_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx)) or 0
            if sep_w > 0 and open_section_footer then
                local dl = reaper.ImGui_GetWindowDrawList(ctx)
                if dl then
                    reaper.ImGui_DrawList_AddLine(dl, sep_x, sep_y, sep_x + sep_w, sep_y, COLOR_TIMELINE_REGION_SEPARATOR_SOFT, 1.0)
                end
            end
            local pad = open_section_footer and 1 or separator_pad_bottom
            reaper.ImGui_Dummy(ctx, 1, pad)
        end

        local open_h = 0
        if open_count > 0 then
            local row_gap_h = (tonumber(item_sp_y) or 0) + 1
            local open_content_h = (open_count * reserved_height) + (open_count * row_gap_h)
            local header_h = header_pad_top + header_pad_bottom + reaper.ImGui_GetTextLineHeightWithSpacing(ctx) + 1 + header_sep_pad_bottom
            local desired_h = header_h + open_content_h + 2
            local min_recent_h = math.max(60, math.min(reserved_height * 2, math.floor(table_height * 0.35)))
            local max_open_h = math.max(0, table_height - min_recent_h)
            open_h = math.min(desired_h, max_open_h)
        end

        if open_h > 0 then
            local open_flags = 0
            if reaper.ImGui_WindowFlags_NoScrollbar then
                open_flags = open_flags | reaper.ImGui_WindowFlags_NoScrollbar()
            end
            if reaper.ImGui_WindowFlags_NoScrollWithMouse then
                open_flags = open_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
            end
            if reaper.ImGui_BeginChild(ctx, "running_projects", 0, open_h, 0, open_flags) then
                draw_section_header("Running Projects")
                for row_i, idx in ipairs(open_indices) do
                    local project = app_state.filtered_projects[idx]
                    draw_project_row(idx, project, row_i, row_i == #open_indices, "open")
                end
                open_section_footer = true
                draw_section_separator()
                open_section_footer = false
            end
            reaper.ImGui_EndChild(ctx)
        end

        local list_x, list_y = reaper.ImGui_GetCursorScreenPos(ctx)
        local list_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx)) or 0
        if list_w < 0 then list_w = 0 end
        local list_h = math.max(0, table_height - open_h)
        local list_scroll = { y = 0.0, max = 0.0 }

        local mx, my = nil, nil
        local wheel_v_raw = 0
        if reaper.ImGui_GetMousePos and reaper.ImGui_GetMouseWheel then
            mx, my = reaper.ImGui_GetMousePos(ctx)
            if mx and my and mx >= list_x and mx <= (list_x + list_w) and my >= list_y and my <= (list_y + list_h) then
                local wv = select(1, reaper.ImGui_GetMouseWheel(ctx))
                if wv and wv ~= 0 then
                    wheel_v_raw = wv
                end
            end
        end

        if list_h > 0 and reaper.ImGui_BeginChild(ctx, "projects_list", 0, list_h, 0, CHILD_LIST_WINDOW_FLAGS) then
            local draw_list_count = reaper.ImGui_GetWindowDrawList(ctx)
            local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
            local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
            local function compute_meta_panel_height(meta)
                if not meta or not wrap_text_to_width then
                    return 0
                end
                local line_h_meta = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
                local pad_y_meta = 10
                local gap_meta_timeline = math.floor(line_h_meta * 0.15)
                local timeline_h_meta = math.floor(line_h_meta * 1.8)
                local rows = 4
                local pad_x_meta = 12
                local col_gap_meta = 40
                local panel_w_meta = select(1, reaper.ImGui_GetContentRegionAvail(ctx)) or 0
                local content_w_meta = math.max(0, panel_w_meta - pad_x_meta * 2)
                local col_w_meta = math.floor((content_w_meta - col_gap_meta) * 0.5)
                if col_w_meta < 20 then col_w_meta = 20 end
                local function val_or_empty_meta(v)
                    if v == nil or v == "" then
                        return "Empty"
                    end
                    return tostring(v)
                end
                local function count_lines(label, value)
                    local label_text = label .. ":"
                    local label_w = select(1, reaper.ImGui_CalcTextSize(ctx, label_text)) or 0
                    local max_value_w = col_w_meta - (label_w + 8)
                    if max_value_w <= 0 then
                        return 1
                    end
                    local text = val_or_empty_meta(value)
                    local lines = wrap_text_to_width(ctx, text, max_value_w)
                    return #lines > 0 and #lines or 1
                end
                local left_rows = 0
                left_rows = left_rows + count_lines("Project Title", meta.notes_title)
                left_rows = left_rows + count_lines("Project Author", meta.notes_author)
                left_rows = left_rows + count_lines("Video Track", (meta.has_video ~= nil) and (meta.has_video and "Yes" or "No") or nil)
                left_rows = left_rows + count_lines("Project Notes", meta.notes_body)
                local song_len_meta = nil
                if meta.song_length_sec and meta.song_length_sec > 0 then
                    local s = math.floor(meta.song_length_sec + 0.5)
                    local m = math.floor(s / 60)
                    local r = s % 60
                    song_len_meta = string.format("%d:%02d", m, r)
                end
                local timebase_str_meta = nil
                if meta.timebase_mode ~= nil then
                    local tb = tonumber(meta.timebase_mode) or 0
                    if tb == 0 then
                        timebase_str_meta = "Time"
                    elseif tb == 1 then
                        timebase_str_meta = "Beats (position, length, rate)"
                    elseif tb == 2 then
                        timebase_str_meta = "Beats (position only)"
                    else
                        timebase_str_meta = tostring(tb)
                    end
                end
                local bpm_str_meta = nil
                if meta.bpm and meta.bpm > 0 then
                    bpm_str_meta = string.format("%.2f", meta.bpm)
                end
                local tracks_str_meta = nil
                if meta.tracks_count and meta.tracks_count > 0 then
                    tracks_str_meta = tostring(meta.tracks_count)
                end
                local right_rows = 0
                right_rows = right_rows + count_lines("Song Length", song_len_meta)
                right_rows = right_rows + count_lines("Timebase", timebase_str_meta)
                right_rows = right_rows + count_lines("BPM", bpm_str_meta)
                right_rows = right_rows + count_lines("Tracks count", tracks_str_meta)
                local est_rows = math.max(left_rows, right_rows)
                if est_rows > 0 then
                    rows = est_rows
                end
                return pad_y_meta + (rows * line_h_meta) + gap_meta_timeline + timeline_h_meta + pad_y_meta
            end

            if not projects_scroll_restore_done then
                local saved_y = (app_state and app_state.settings and tonumber(app_state.settings.projects_scroll_y)) or nil
                if saved_y ~= nil and reaper.ImGui_SetScrollY then
                    reaper.ImGui_SetScrollY(ctx, saved_y)
                end
                projects_scroll_restore_done = true
            end
            local scroll_step = math.max(5, math.floor(reserved_height * 0.125))
            local last_row_bottom = nil
            local rest_count = #rest_indices

            local function draw_meta_panel_if_needed(project, row_bottom_y)
                if not app_state then
                    return 0
                end
                if not project or not project.parsed_meta then
                    return 0
                end
                local p = project.full_path or project.path or ""
                if p == "" then
                    return 0
                end
                local key = normalize_path(p)
                if key == "" then
                    return 0
                end

                app_state.meta_panel_state = app_state.meta_panel_state or {}
                local state = app_state.meta_panel_state[key]

                local now_meta = reaper.time_precise()
                if not state then
                    state = { h_current = 0, last_t = now_meta }
                    app_state.meta_panel_state[key] = state
                end

                local base_h = compute_meta_panel_height(project.parsed_meta)
                if base_h < 0 then base_h = 0 end

                local is_open = is_project_meta_open(app_state, project)
                local target_h = is_open and base_h or 0

                local dt_meta = now_meta - (state.last_t or now_meta)
                state.last_t = now_meta
                if dt_meta < 0 then dt_meta = 0 end
                if dt_meta > 0.05 then dt_meta = 0.05 end

                local speed_meta = 24.0
                local alpha_meta = 1.0 - math.exp(-(dt_meta or 0) * speed_meta)
                if alpha_meta < 0 then alpha_meta = 0 end
                if alpha_meta > 1 then alpha_meta = 1 end
                local ease_meta = alpha_meta * alpha_meta * alpha_meta * (alpha_meta * (alpha_meta * 6.0 - 15.0) + 10.0)

                local h_current = state.h_current or 0
                h_current = h_current + (target_h - h_current) * ease_meta
                if math.abs(target_h - h_current) < 0.5 then
                    h_current = target_h
                end
                state.h_current = h_current

                if h_current <= 0.5 then
                    if not is_open then
                        app_state.meta_panel_state[key] = nil
                    end
                    return 0
                end

                local panel_h = h_current
                local panel_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx)) or 0
                if panel_w < 0 then panel_w = 0 end
                reaper.ImGui_Dummy(ctx, panel_w, panel_h)
                local px1, py1 = reaper.ImGui_GetItemRectMin(ctx)
                local px2, py2 = reaper.ImGui_GetItemRectMax(ctx)
                local dl_panel = reaper.ImGui_GetWindowDrawList(ctx)
                local box_y2 = py2 - 1
                if box_y2 < py1 then box_y2 = py1 end
                reaper.ImGui_DrawList_AddRectFilled(dl_panel, px1, py1, px2, box_y2, COLOR_META_PANEL_BG, 6)
                reaper.ImGui_DrawList_AddRect(dl_panel, px1, py1, px2, box_y2, COLOR_META_PANEL_BORDER, 6)
                if reaper.ImGui_PushClipRect and reaper.ImGui_PopClipRect then
                    reaper.ImGui_PushClipRect(ctx, px1, py1, px2, py2, true)
                    draw_project_meta_panel(ctx, dl_panel, px1, py1, px2, py2, project.parsed_meta, project)
                    reaper.ImGui_PopClipRect(ctx)
                else
                    draw_project_meta_panel(ctx, dl_panel, px1, py1, px2, py2, project.parsed_meta, project)
                end
                return panel_h
            end

            if rest_count > 0 then
                draw_section_header("Recent Projects")
                for row_i, idx in ipairs(rest_indices) do
                    local project = app_state.filtered_projects[idx]
                    local _, row_y_top = reaper.ImGui_GetCursorScreenPos(ctx)
                    draw_project_row(idx, project, row_i, row_i == rest_count, "rest")
                    local _, row_y_bottom = reaper.ImGui_GetCursorScreenPos(ctx)
                    local row_bottom_y = row_y_bottom
                    local added_meta_h = draw_meta_panel_if_needed(project, row_bottom_y)
                    local content_bottom_y = row_bottom_y + added_meta_h
                    last_row_bottom = content_bottom_y
                end
                draw_section_separator()
            end

            projects_scroll_target_y, projects_scroll_last_t =
                apply_smooth_scroll(ctx, wheel_v_raw, scroll_step, projects_scroll_target_y, projects_scroll_last_t, 18.0)

            if (#app_state.filtered_projects > 0) and last_row_bottom and win_x and win_y and win_w and win_h then
                local fill_y1 = math.max(last_row_bottom, win_y)
                local fill_y2 = win_y + win_h
                if fill_y2 > fill_y1 then
                    reaper.ImGui_DrawList_AddRectFilled(draw_list_count, win_x, fill_y1, win_x + win_w, fill_y2, COLOR_TABLE_EMPTY_BG)
                end
            end

            if reaper.ImGui_GetScrollY then
                list_scroll.y = reaper.ImGui_GetScrollY(ctx) or 0.0
                if app_state and app_state.settings then
                    app_state.settings.projects_scroll_y = list_scroll.y
                end
            end
            if reaper.ImGui_GetScrollMaxY then
                list_scroll.max = reaper.ImGui_GetScrollMaxY(ctx) or 0.0
            end
        end

        if list_h > 0 then
            reaper.ImGui_EndChild(ctx)
        end

        if #app_state.filtered_projects == 0 and list_w > 0 and list_h > 0 then
            local draw_list_empty = reaper.ImGui_GetWindowDrawList(ctx)
            reaper.ImGui_DrawList_AddRectFilled(draw_list_empty, list_x, list_y, list_x + list_w, list_y + list_h, COLOR_TABLE_EMPTY_BG)
        end

        if reaper.ImGui_DrawList_AddRectFilledMultiColor and list_w > 0 and list_h > 0 then
            local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
            local shadow_h = math.max(10, math.floor(frame_h * 0.9))
            shadow_h = math.min(shadow_h, math.floor(list_h * 0.5))
            if shadow_h > 0 then
                local sy = tonumber(list_scroll.y) or 0.0
                local maxy = tonumber(list_scroll.max) or 0.0
                local shadow_y = list_y

                local a_top = 0x66
                local a_bot = 0x66
                if maxy <= 0.5 then
                    a_top = 0x22
                    a_bot = 0x22
                else
                    if sy <= 0.5 then
                        a_top = 0
                    else
                        local t = sy / shadow_h
                        if t < 0 then t = 0 end
                        if t > 1 then t = 1 end
                        a_top = math.floor((0x66 * t) + 0.5)
                    end
                    local rem = maxy - sy
                    if rem <= 0.5 then
                        a_bot = 0
                    else
                        local t = rem / shadow_h
                        if t < 0 then t = 0 end
                        if t > 1 then t = 1 end
                        a_bot = math.floor((0x66 * t) + 0.5)
                    end
                end

                local col_trans = COLOR_BLACK_TRANSPARENT
                if a_top ~= 0 then
                    reaper.ImGui_DrawList_AddRectFilledMultiColor(draw_list, list_x, shadow_y, list_x + list_w, shadow_y + shadow_h, a_top, a_top, col_trans, col_trans)
                end

                if a_bot ~= 0 then
                    local y2 = list_y + list_h
                    reaper.ImGui_DrawList_AddRectFilledMultiColor(draw_list, list_x, y2 - shadow_h, list_x + list_w, y2, col_trans, col_trans, a_bot, a_bot)
                end
            end
        end

        if bottom_panel_visible and bottom_panel_h > 0 then
            if panel_gap_y and panel_gap_y > 0 then
                reaper.ImGui_Dummy(ctx, 1, panel_gap_y)
            end

            local content_w = math.max(0, select(1, reaper.ImGui_GetContentRegionAvail(ctx)) or 0)
            local player_h = math.floor(((tonumber(bottom_panel_h) or 0) - (splitter_h or 0)) + 0.5)
            if player_h < 40 then
                player_h = 40
            end

            if splitter_h and splitter_h > 0 then
                reaper.ImGui_InvisibleButton(ctx, "##bottom_panel_splitter", content_w, splitter_h)
                do
                    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
                    local sx1, sy1 = reaper.ImGui_GetItemRectMin(ctx)
                    local sx2, sy2 = reaper.ImGui_GetItemRectMax(ctx)
                    local col_bg = COLOR_INLINE_BG_FILL
                    local col_line1 = COLOR_INLINE_BORDER_LIGHT
                    local col_line2 = COLOR_INLINE_BORDER_DARK
                    if reaper.ImGui_IsItemHovered(ctx) or reaper.ImGui_IsItemActive(ctx) then
                        col_bg = COLOR_INLINE_BG_SELECTED
                    end
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, sx1, sy1, sx2, sy2, col_bg)
                    local mid_y = math.floor((sy1 + sy2) * 0.5)
                    reaper.ImGui_DrawList_AddLine(draw_list, sx1, mid_y, sx2, mid_y, col_line1)
                    reaper.ImGui_DrawList_AddLine(draw_list, sx1, mid_y + 1, sx2, mid_y + 1, col_line2)
                end
                if (reaper.ImGui_IsItemHovered(ctx) or reaper.ImGui_IsItemActive(ctx)) and reaper.ImGui_SetMouseCursor and reaper.ImGui_MouseCursor_ResizeNS then
                    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeNS())
                end
                if reaper.ImGui_IsItemActivated and reaper.ImGui_IsItemActivated(ctx) then
                    local _, my = reaper.ImGui_GetMousePos(ctx)
                    bottom_splitter_active = true
                    bottom_splitter_start_mouse_y = my or 0
                    bottom_splitter_start_h = bottom_panel_h
                end
                if bottom_splitter_active then
                    local mouse_down = nil
                    if reaper.ImGui_IsMouseDown then
                        mouse_down = reaper.ImGui_IsMouseDown(ctx, 0)
                    elseif reaper.ImGui_IsMouseReleased then
                        mouse_down = not reaper.ImGui_IsMouseReleased(ctx, 0)
                    end
                    if mouse_down == false then
                        bottom_splitter_active = false
                        if app_state.save_settings then
                            app_state.save_settings(app_state.settings)
                        end
                    end
                end
            end

            local bottom_child_open = reaper.ImGui_BeginChild(ctx, "bottom_player", content_w, player_h, 0, BOTTOM_PLAYER_WINDOW_FLAGS)
            if bottom_child_open then
                local min_content_h = bottom_controls_h + bottom_pad_top + min_timeline_h + fixed_meta_reserve_h
                if player_h < min_content_h then
                    reaper.ImGui_EndChild(ctx)
                else
                local content_x, content_y = reaper.ImGui_GetCursorScreenPos(ctx)
                local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
                local chosen_project = nil
                if status and status.playing and status.path then
                    chosen_project = find_project_by_preview_path(app_state, status.path)
                end
                if not chosen_project then
                    local idx = app_state.selected_project
                    if idx and app_state.filtered_projects and app_state.filtered_projects[idx] then
                        chosen_project = app_state.filtered_projects[idx]
                    end
                end

                local preview_path = get_preview_path_for_project(chosen_project)
                local is_enabled = preview_path ~= nil
                local is_playing = status and status.playing
                local is_playing_this = false
                if is_playing and status and status.path and preview_path and normalize_path(status.path) == normalize_path(preview_path) then
                    is_playing_this = true
                end

                local duration_cached = nil
                if preview_path then
                    duration_cached = get_duration_cached(preview_path)
                end

                local can_play = is_enabled and preview_path ~= nil
                local ctrl_size, play_size = get_play_control_sizes(ctx)
                local vol_h = math.floor(ctrl_size * 0.8)
                if vol_h < 10 then vol_h = 10 end
                local controls_offset_y = 0
                if bottom_controls_h and vol_h then
                    local slack = bottom_controls_h - vol_h
                    if slack > 0 then
                        controls_offset_y = math.floor(slack * 0.5)
                    end
                end
                local transport_x = content_x
                if play_column_center_x ~= nil then
                    local desired_center = play_column_center_x
                    local button_w = play_size
                    local candidate_x = desired_center - math.floor(button_w * 0.5)
                    local min_x = content_x
                    if candidate_x < min_x then
                        candidate_x = min_x
                    end
                    transport_x = candidate_x
                end
                reaper.ImGui_SetCursorScreenPos(ctx, transport_x, content_y + controls_offset_y)

                local transport_id = "##bottom_transport_toggle"
                local transport_icon = is_playing_this and ICON_STOP or ICON_PLAY

                if not can_play then
                    draw_transport_icon_button(ctx, transport_id, transport_icon, play_size, false, false)
                    show_delayed_tooltip("bottom_transport_no_preview", "No Preview Yet")
                else
                    local clicked_play = select(1, draw_transport_icon_button(ctx, transport_id, transport_icon, play_size, true, is_playing_this))
                    if clicked_play then
                        if is_playing_this then
                            ProjectList.stop_preview()
                            status = ProjectList.get_preview_status and ProjectList.get_preview_status()
                            is_playing = status and status.playing
                            is_playing_this = false
                        else
                            if ProjectList.stop_preview then
                                ProjectList.stop_preview()
                            end
                            if ProjectList.play_preview(preview_path) then
                                status = ProjectList.get_preview_status and ProjectList.get_preview_status()
                                is_playing = status and status.playing
                                is_playing_this = true
                            end
                        end
                    end
                end

                reaper.ImGui_SameLine(ctx)
                local rep_enabled = app_state.preview_repeat or false
                local repeat_id = "##bottom_preview_repeat"
                local repeat_icon = ICON_MDI_REPEAT
                local clicked_rep = select(1, draw_transport_icon_button(ctx, repeat_id, repeat_icon, play_size, true, rep_enabled))
                if clicked_rep then
                    app_state.preview_repeat = not rep_enabled
                end

            reaper.ImGui_SameLine(ctx)
            local vol_use_group =
                reaper.ImGui_BeginGroup and reaper.ImGui_EndGroup and reaper.ImGui_GetCursorScreenPos and reaper.ImGui_SetCursorScreenPos
            if vol_use_group then
                reaper.ImGui_BeginGroup(ctx)
                local vol_line_x, vol_line_y = reaper.ImGui_GetCursorScreenPos(ctx)
                local vol_center_offset_y = 0
                if play_size and vol_h and play_size > vol_h then
                    vol_center_offset_y = math.floor((play_size - vol_h) * 0.5 + 0.5)
                end
                reaper.ImGui_SetCursorScreenPos(ctx, vol_line_x, vol_line_y + vol_center_offset_y)
            end
            local vol = app_state.preview_volume
            if ProjectList and ProjectList.get_preview_volume then
                vol = ProjectList.get_preview_volume()
            end
            vol = tonumber(vol) or 1.0
            if vol < 0 then vol = 0 end
            local vol_db = vol_to_db(vol)
            local db_min = -60.0
            local db_max = 0.0
            if vol_db < db_min then vol_db = db_min end
            if vol_db > db_max then vol_db = db_max end
            local db_span = db_max - db_min
            local norm = (vol_db - db_min) / db_span
            if norm < 0 then norm = 0 end
            if norm > 1 then norm = 1 end
            local curve_k = 0.5
            local slider_pos = norm ^ (1.0 / curve_k)
            local vol_w = 72

            local track_col = color_set_alpha(COLOR_TEXT, 0x18)
            local fill_col = COLOR_ACCENT
            local thumb_col = COLOR_SLIDER_GRAB_ACTIVE

            local vol_db_slider = vol_db
            local vol_changed = false

            local changed_pos, new_slider_pos, vol_hovered, vol_active =
                draw_uix_slider_01(ctx, "##bottom_preview_volume", slider_pos, vol_w, vol_h, track_col, fill_col, thumb_col)
            if vol_use_group then
                reaper.ImGui_EndGroup(ctx)
            end

            local double_clicked = false
            if vol_hovered and reaper.ImGui_IsMouseDoubleClicked and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                preview_vol_ignore_until = reaper.time_precise() + 0.25
                double_clicked = true
                vol_db_slider = 0.0
                vol_changed = true
            end

            if changed_pos and (reaper.time_precise() >= (preview_vol_ignore_until or 0.0)) then
                local new_norm = clamp01(new_slider_pos) ^ curve_k
                vol_db_slider = db_min + (db_span * new_norm)
                vol_changed = true
            end

            if vol_hovered then
                local line1 = string.format("Preview volume: %.1f dB", vol_db_slider)
                local line2 = "Double-click to reset to 0.0 dB"
                show_delayed_tooltip("preview_volume_slider", { line1, line2 })
            end

            if vol_changed or double_clicked then
                local new_vol = db_to_vol(vol_db_slider)
                app_state.preview_volume = new_vol
                if ProjectList and ProjectList.set_preview_volume then
                    ProjectList.set_preview_volume(new_vol)
                end
            end

            local elapsed = nil
            local total = nil
            if is_playing_this and status and status.duration and status.duration > 0 then
                elapsed = status.elapsed or 0
                total = status.duration
            elseif duration_cached and duration_cached > 0 then
                elapsed = 0
                total = duration_cached
            end
            if total and total > 0 then
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_Dummy(ctx, 12, 1)
                reaper.ImGui_SameLine(ctx)

                local elapsed_s = format_time_mmss(elapsed)
                local total_s = format_time_mmss(total)
                local widest_elapsed_s = "88:88"
                local elapsed_box_w = select(1, reaper.ImGui_CalcTextSize(ctx, widest_elapsed_s))
                local suffix_s = " / " .. total_s
                local suffix_w = select(1, reaper.ImGui_CalcTextSize(ctx, suffix_s))
                local block_w = elapsed_box_w + suffix_w
                local text_h = reaper.ImGui_GetTextLineHeight(ctx)

                reaper.ImGui_Dummy(ctx, block_w, text_h)
                local bx1, by1 = reaper.ImGui_GetItemRectMin(ctx)
                local draw_list_ctrl = reaper.ImGui_GetWindowDrawList(ctx)
                local elapsed_w = select(1, reaper.ImGui_CalcTextSize(ctx, elapsed_s))
                local col = COLOR_TEXT_MUTED
                reaper.ImGui_DrawList_AddText(draw_list_ctrl, bx1 + (elapsed_box_w - elapsed_w), by1, col, elapsed_s)
                reaper.ImGui_DrawList_AddText(draw_list_ctrl, bx1 + elapsed_box_w, by1, col, suffix_s)
            end

            do
                if font and ICON_CLOSE and reaper.ImGui_PushFont and reaper.ImGui_GetMousePos then
                    local pin_font_pushed = false
                    local ok_pin = pcall(reaper.ImGui_PushFont, ctx, font, font_size + 4.0)
                    if ok_pin then
                        pin_font_pushed = true
                        local icon_mark = ICON_CLOSE
                        local tw, th = reaper.ImGui_CalcTextSize(ctx, icon_mark)
                        local right_pad = 10
                        local px
                        if pin_column_center_x ~= nil then
                            px = pin_column_center_x - math.floor(tw * 0.5)
                        else
                            px = content_x + content_w - right_pad - tw
                        end
                        local py = content_y + controls_offset_y + math.floor((play_size - th) / 2)
                        local mx, my = reaper.ImGui_GetMousePos(ctx)
                        local hovered = false
                        if mx and my then
                            if mx >= px and mx <= (px + tw) and my >= py and my <= (py + th) then
                                hovered = true
                            end
                        end
                        if hovered and ICON_CLOSE_HOVER then
                            icon_mark = ICON_CLOSE_HOVER
                            tw, th = reaper.ImGui_CalcTextSize(ctx, icon_mark)
                            if pin_column_center_x ~= nil then
                                px = pin_column_center_x - math.floor(tw * 0.5)
                            else
                                px = content_x + content_w - right_pad - tw
                            end
                            py = content_y + controls_offset_y + math.floor((play_size - th) / 2)
                        end
                        local icon_col = COLOR_META_TEXT_SECONDARY
                        if hovered then
                            icon_col = COLOR_TEXT
                        end
                        reaper.ImGui_DrawList_AddText(draw_list_ctrl or reaper.ImGui_GetWindowDrawList(ctx), px, py, icon_col, icon_mark)
                        local clicked = hovered and reaper.ImGui_IsMouseClicked and reaper.ImGui_IsMouseClicked(ctx, 0)
                        if clicked then
                            bottom_player_closed = true
                            bottom_panel_target_h = 0
                        end
                    end
                    if pin_font_pushed and reaper.ImGui_PopFont then
                        pcall(reaper.ImGui_PopFont, ctx)
                    end
                end
            end

            local regions = nil
            if chosen_project and ProjectList and ProjectList.get_project_regions then
                regions = ProjectList.get_project_regions(chosen_project.full_path or chosen_project.path)
            end
            local duration = duration_cached
            local timeline_min, timeline_span, timeline_origin = compute_timeline(regions, duration, status)

            local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
            local pad_top = 8
            local meta_lines = {}
            local meta_line_h = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
            local meta_gap = 8
            local meta_pad_y = 6
            if is_enabled and preview_path then
                local pm = safe_get_preview_meta(ProjectList, chosen_project, preview_path)
                local line1_parts = {}
                local line2_parts = {}

                if pm and pm.created and pm.created ~= "" and pm.created ~= "Unknown" then
                    line1_parts[#line1_parts + 1] = "Created: " .. tostring(pm.created)
                end

                if pm and pm.stale_seconds ~= nil then
                    local stale_s = format_stale_age(pm.stale_seconds)
                    if stale_s then
                        line1_parts[#line1_parts + 1] = stale_s
                    end
                end

                local media = pm and pm.media or nil

                local fmt_parts = {}
                if media and tonumber(media.bits_per_sample) then
                    fmt_parts[#fmt_parts + 1] = string.format("%d-bit", math.floor(tonumber(media.bits_per_sample) + 0.5))
                end
                local sr_s = media and format_sample_rate(media.sample_rate) or nil
                if sr_s then
                    fmt_parts[#fmt_parts + 1] = sr_s
                end
                if #fmt_parts > 0 then
                    line2_parts[#line2_parts + 1] = table.concat(fmt_parts, " ")
                end

                if pm and pm.duration and pm.duration > 0 then
                    line2_parts[#line2_parts + 1] = "Length: " .. format_time_mmss(pm.duration)
                end

                local size_s = media and format_bytes_iec(media.size_bytes) or nil
                if size_s then
                    line2_parts[#line2_parts + 1] = "Size: " .. size_s
                end

                local peak_s = media and format_dbfs(media.peak_dbfs) or nil
                if peak_s then
                    line2_parts[#line2_parts + 1] = "Peak: " .. peak_s
                end

                if media and tonumber(media.lufs_i) then
                    line2_parts[#line2_parts + 1] = string.format("LUFS-I: %.1f", tonumber(media.lufs_i))
                end

                local line1 = join_parts(line1_parts, "  |  ")
                local line2 = join_parts(line2_parts, "  |  ")
                if line1 ~= "" then meta_lines[#meta_lines + 1] = line1 end
                if line2 ~= "" then meta_lines[#meta_lines + 1] = line2 end
            end

            local tl_w = math.max(0, math.floor(avail_w))
            local fixed_meta_lines = 2
            local meta_enabled = is_enabled and preview_path ~= nil
            local tl_x, cur_y = reaper.ImGui_GetCursorScreenPos(ctx)
            local _, item_sp_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
            item_sp_y = tonumber(item_sp_y) or 0
            local meta_extra_h = math.min(item_sp_y * 3, math.floor(meta_line_h))
            local fixed_meta_reserve_h = (meta_pad_y * 2) + meta_extra_h
            if meta_enabled then
                fixed_meta_reserve_h = fixed_meta_reserve_h + meta_gap + (fixed_meta_lines * meta_line_h)
            end
            local tl_top_y = cur_y + pad_top
            local tl_h = math.floor((tonumber(avail_h) or 0) - pad_top - fixed_meta_reserve_h)
            if tl_h < 12 then tl_h = 12 end

            local saved_x, saved_y = tl_x, cur_y
            reaper.ImGui_SetCursorScreenPos(ctx, tl_x, tl_top_y)
            draw_player_timeline(ctx, draw_list, "##bottom_timeline", tl_x, tl_top_y, tl_w, tl_h, {
                is_enabled = is_enabled,
                preview_path = preview_path,
                regions = regions,
                timeline_min = timeline_min,
                timeline_span = timeline_span,
                timeline_origin = timeline_origin,
                status = status,
                is_playing = is_playing_this,
                on_seek = function(seek_pos)
                    if not preview_path or not is_enabled then return end
                    local st = ProjectList.get_preview_status and ProjectList.get_preview_status()
                    local is_this = st and st.playing and st.path and normalize_path(st.path) == normalize_path(preview_path)
                    if not is_this then
                        if ProjectList.stop_preview then
                            ProjectList.stop_preview()
                        end
                        if ProjectList.play_preview then
                            ProjectList.play_preview(preview_path)
                        end
                    end
                    if ProjectList and ProjectList.seek_preview and ProjectList.seek_preview(seek_pos) then
                        status = ProjectList.get_preview_status and ProjectList.get_preview_status()
                    else
                        status = ProjectList.get_preview_status and ProjectList.get_preview_status()
                    end
                end
            })
            reaper.ImGui_SetCursorScreenPos(ctx, tl_x, tl_top_y + tl_h)

            if meta_enabled and tl_w > 40 then
                reaper.ImGui_Dummy(ctx, 1, meta_gap)
                reaper.ImGui_Indent(ctx, 8)
                local meta_w = math.max(0, tl_w - 16)
                local meta_font_pushed = false
                if font and reaper.ImGui_PushFont then
                    local target_size = (font_size or 15.0) - 2.0
                    if target_size < 8.0 then target_size = 8.0 end
                    local ok_meta = pcall(reaper.ImGui_PushFont, ctx, font, target_size)
                    if ok_meta then
                        meta_font_pushed = true
                    end
                end
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), COLOR_META_TEXT_SECONDARY)
                for i = 1, fixed_meta_lines do
                    local line = meta_lines[i]
                    if line and line ~= "" then
                        local s = fit_text_to_width(ctx, line, meta_w)
                        reaper.ImGui_Text(ctx, s)
                    else
                        reaper.ImGui_Dummy(ctx, 1, meta_line_h)
                    end
                end
                reaper.ImGui_PopStyleColor(ctx, 1)
                if meta_font_pushed and reaper.ImGui_PopFont then
                    pcall(reaper.ImGui_PopFont, ctx)
                end
                reaper.ImGui_Unindent(ctx, 8)
            end

            reaper.ImGui_Dummy(ctx, 1, meta_pad_y)
            if tl_w > 0 then
                local sx, sy = reaper.ImGui_GetCursorScreenPos(ctx)
                reaper.ImGui_DrawList_AddLine(draw_list, sx, sy, sx + tl_w, sy, COLOR_BOTTOM_LINE_SEPARATOR, 1.0)
            end
            reaper.ImGui_Dummy(ctx, 1, meta_pad_y)
            reaper.ImGui_SetCursorScreenPos(ctx, saved_x, saved_y)
            reaper.ImGui_EndChild(ctx)
            end
            end
        end

        do
            local footer_text = "by Mr. Frenkie"
            local version_text = "1.1"
            local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
            local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
            local tw, th = reaper.ImGui_CalcTextSize(ctx, footer_text)
            local vtw, vth = reaper.ImGui_CalcTextSize(ctx, version_text)
            if win_x and win_y and win_w and win_h and tw and th and vtw and vth then
                local pad_x, pad_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding())
                pad_x = tonumber(pad_x) or 0
                pad_y = tonumber(pad_y) or 0
                local footer_top = (content_origin_y or (win_y + pad_y)) + (tonumber(content_height) or 0)
                local footer_h = tonumber(bottom_border_h) or 0
                local footer_bottom = footer_top + footer_h
                local px = math.floor((win_x + win_w - pad_x - tw - 2) + 0.5)
                local py = math.floor((footer_bottom - th - 2) + 0.5)
                local vx = math.floor((win_x + pad_x + 2) + 0.5)
                local vy = math.floor((footer_bottom - vth - 2) + 0.5)
                local dl = reaper.ImGui_GetWindowDrawList(ctx)
                if dl then
                    reaper.ImGui_DrawList_AddText(dl, vx, vy, COLOR_BG_BUTTON_HOVER, version_text)
                    local hover_pad = 3
                    local bx1 = px - hover_pad
                    local by1 = py - hover_pad
                    local bx2 = px + tw + hover_pad
                    local by2 = py + th + hover_pad
                    reaper.ImGui_SetCursorScreenPos(ctx, bx1, by1)
                    reaper.ImGui_InvisibleButton(ctx, "##footer_signature", bx2 - bx1, by2 - by1)
                    local hovered = reaper.ImGui_IsItemHovered(ctx)
                    local clicked = reaper.ImGui_IsItemClicked(ctx, 0)
                    local text_col = hovered and COLOR_FOOTER_POPUP_ITEM_HOVER or COLOR_BG_BUTTON_HOVER
                    reaper.ImGui_DrawList_AddText(dl, px, py, text_col, footer_text)
                    if clicked then
                        footer_popup_visible = true
                        if reaper.ImGui_OpenPopup then
                            reaper.ImGui_OpenPopup(ctx, "footer_links_popup")
                        end
                    end
                end
            end
        end

        if reaper.ImGui_BeginPopup and reaper.ImGui_BeginPopup(ctx, "footer_links_popup") then
            if not footer_popup_visible then
                reaper.ImGui_CloseCurrentPopup(ctx)
            else
                local color_count = 0
                local var_count = 0
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), COLOR_FOOTER_POPUP_BG); color_count = color_count + 1
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), COLOR_BORDER); color_count = color_count + 1
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), COLOR_FOOTER_POPUP_TEXT); color_count = color_count + 1
                local rounding = 10
                if reaper.ImGui_StyleVar_WindowRounding then
                    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), rounding); var_count = var_count + 1
                end
                if reaper.ImGui_StyleVar_PopupRounding then
                    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(), rounding); var_count = var_count + 1
                end
                local function footer_link(label, url)
                    if reaper.ImGui_Selectable(ctx, label, false) then
                        if reaper.CF_ShellExecute then
                            reaper.CF_ShellExecute(url)
                        elseif reaper.OpenURL then
                            reaper.OpenURL(url)
                        end
                        reaper.ImGui_CloseCurrentPopup(ctx)
                        footer_popup_visible = false
                    end
                end
                footer_link("Donat / Update", "https://boosty.to/mrfrenkie?postsTagsIds=16663143")
                footer_link("YouTube (ru)", "https://www.youtube.com/@MrFrenkie")
                footer_link("Telegram Blog (ru)", "https://t.me/mrfrenkie")
                footer_link("ass Symptom", "https://youtu.be/ztionFS-590?si=RSC_yuYjiU6zhPAF")
                if var_count > 0 then
                    reaper.ImGui_PopStyleVar(ctx, var_count)
                end
                if color_count > 0 then
                    reaper.ImGui_PopStyleColor(ctx, color_count)
                end
            end
            reaper.ImGui_EndPopup(ctx)
        else
            footer_popup_visible = false
        end

        if app_state.request_close and not app_state.pin_on_screen then
            open = false
            app_state.request_close = false
        end
    end

    reaper.ImGui_End(ctx)

    pop_item_properties_style(ctx)

    if not open then
        first_frame = true
        filter_focus_next_frame = false
        filter_has_focus = false
        filter_focused_last_frame = false
        if app_state and app_state.save_settings then
            app_state.save_settings(app_state.settings)
        end
    end

    return open
end

function UI.cleanup()
    if font then
        reaper.ImGui_Detach(ctx, font)
        font = nil
    end
    if ProjectList and ProjectList.stop_preview then
        ProjectList.stop_preview()
    end
    ctx = nil
end

return UI
