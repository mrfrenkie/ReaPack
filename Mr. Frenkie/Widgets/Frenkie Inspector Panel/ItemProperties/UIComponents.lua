-- @noindex

-- @noindex
---@diagnostic disable: undefined-global, undefined-field
local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""
package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Theme = require("Theme")
local Utils = require("Utils")

local UIComponents = {}

local ITEM_INFO_PROPERTIES_ACTION = 40009
local STYLED_TOOLTIP_DELAY_DEFAULT = 1.0

local _hover_timers = {}
local _pending_tooltip_lines = nil
local _italic_font = nil
local _agg_region = nil
local _tooltip_font = nil
local _tooltip_font_size = 13
local _styled_tt_hover_start = {}
local _styled_tt_hover_last_pos = {}

local function is_mouse_inside_rect(ctx, x1, y1, x2, y2)
    local mx, my = r.ImGui_GetMousePos(ctx)
    return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
end

local function is_last_item_left_clicked(ctx)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    return is_mouse_inside_rect(ctx, x1, y1, x2, y2) and r.ImGui_IsMouseClicked(ctx, 0)
end

local function is_last_item_alt_clicked(ctx)
    if not is_last_item_left_clicked(ctx) then
        return false
    end
    local mods = r.ImGui_GetKeyMods(ctx)
    return (mods & r.ImGui_Mod_Alt()) ~= 0
end

local function split_tooltip_lines(text)
    if not text or text == '' then return {} end
    local lines = {}
    local pos = 1
    local len = #text
    while pos <= len do
        local idx = string.find(text, '\n', pos, true)
        if not idx then
            lines[#lines + 1] = string.sub(text, pos)
            break
        end
        lines[#lines + 1] = string.sub(text, pos, idx - 1)
        pos = idx + 1
    end
    return lines
end

local function is_mac_os()
    local os_str = r.GetOS() or ''
    local low = os_str:lower()
    if low ~= '' and low:find('win', 1, true) then
        return false
    end
    if low:find('darwin', 1, true)
        or low:find('osx', 1, true)
        or low:find('macos', 1, true)
        or low:find('mac os', 1, true) then
        return true
    end
    local ot = (os.getenv('OSTYPE') or ''):lower()
    return ot:find('darwin', 1, true) ~= nil
end

local function is_windows_os()
    local os_str = r.GetOS()
    return os_str and os_str ~= '' and os_str:lower():find('win', 1, true) ~= nil
end

local function cmd_label()
    return is_mac_os() and '⌘' or 'Ctrl'
end

local function alt_label()
    return is_mac_os() and '⌥' or 'Alt'
end

local function shift_label()
    return '⇧'
end

local function combo_label(...)
    local parts = { ... }
    if is_mac_os() then
        return table.concat(parts, '')
    end
    return table.concat(parts, '+')
end

local function render_styled_tooltip_lines(ctx, lines)
    local color_count = 0
    local var_count = 0
    local font_pushed = false
    local tooltip_round = 8.0
    if _tooltip_font and r.ImGui_PushFont then
        local sz = math.max(10, math.floor((_tooltip_font_size or 13) * 0.85 + 0.5))
        font_pushed = pcall(r.ImGui_PushFont, ctx, _tooltip_font, sz)
        if not font_pushed then
            font_pushed = pcall(r.ImGui_PushFont, ctx, _tooltip_font)
        end
    end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), Theme.get('tooltip_bg'))
    color_count = color_count + 1
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), Theme.get('tooltip_border'))
    color_count = color_count + 1
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('tooltip_text'))
    color_count = color_count + 1
    if r.ImGui_StyleVar_WindowRounding then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), tooltip_round)
        var_count = var_count + 1
    end
    if r.ImGui_StyleVar_PopupRounding then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), tooltip_round)
        var_count = var_count + 1
    end
    if r.ImGui_StyleVar_WindowBorderSize then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0.0)
        var_count = var_count + 1
    end
    if r.ImGui_StyleVar_PopupBorderSize then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupBorderSize(), 0.0)
        var_count = var_count + 1
    end
    local ok_tt = pcall(r.ImGui_BeginTooltip, ctx)
    if ok_tt then
        for _, line in ipairs(lines or {}) do
            if line ~= nil then
                if type(line) == 'table' and line.text ~= nil then
                    local col = line.color or Theme.get('tooltip_text')
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col)
                    r.ImGui_Text(ctx, line.text)
                    r.ImGui_PopStyleColor(ctx, 1)
                else
                    r.ImGui_Text(ctx, line)
                end
            end
        end
        r.ImGui_EndTooltip(ctx)
    else
        local plain = {}
        for _, line in ipairs(lines or {}) do
            if type(line) == 'table' and line.text ~= nil then
                plain[#plain + 1] = line.text
            elseif type(line) == 'string' then
                plain[#plain + 1] = line
            end
        end
        r.ImGui_SetTooltip(ctx, table.concat(plain, '\n'))
    end
    if var_count > 0 then r.ImGui_PopStyleVar(ctx, var_count) end
    if color_count > 0 then r.ImGui_PopStyleColor(ctx, color_count) end
    if font_pushed and r.ImGui_PopFont then pcall(r.ImGui_PopFont, ctx) end
end

local function _srgb_lin(c)
    local s = c / 255.0
    if s <= 0.03928 then return s / 12.92 end
    return ((s + 0.055) / 1.055) ^ 2.4
end

local function norm_bar_rgb255(rr, gg, bb)
    local function q(v, dflt)
        v = tonumber(v) or dflt or 64
        v = math.floor(v + 0.5)
        if v < 0 then return 0 end
        if v > 255 then return 255 end
        return v
    end
    return q(rr, 64), q(gg, 64), q(bb, 64)
end

-- WCAG 2 contrast ratio for relative luminances L in 0..1
local function wcag_cr(Lbg, Lfg)
    local a = math.max(Lbg, Lfg) + 0.05
    local b = math.min(Lbg, Lfg) + 0.05
    return a / b
end

-- Returns ImGui foreground u32 plus whether the choice is dark ink (black vs light text).
function UIComponents.BarForegroundPick(rr, gg, bb)
    rr, gg, bb = norm_bar_rgb255(rr, gg, bb)
    local function L255(r, g, b)
        return 0.2126 * _srgb_lin(r) + 0.7152 * _srgb_lin(g) + 0.0722 * _srgb_lin(b)
    end
    local Lbg = L255(rr, gg, bb)
    local cands = {
        { Theme.get('black'), L255(0, 0, 0), true },
        { Theme.get('text_white_soft'), L255(220, 220, 220), false },
        { Theme.rgba(255, 255, 255, 255), L255(255, 255, 255), false },
    }
    local min_aa = 4.5
    local best_u, best_cr, best_dark = nil, nil, nil
    for _, tri in ipairs(cands) do
        local crt = wcag_cr(Lbg, tri[2])
        if crt >= min_aa and (best_cr == nil or crt > best_cr) then
            best_cr = crt
            best_u = tri[1]
            best_dark = tri[3]
        end
    end
    if best_u ~= nil then
        return best_u, best_dark
    end
    local fb_u, fb_cr, fb_dark = Theme.get('black'), -1.0, true
    for _, tri in ipairs(cands) do
        local crt = wcag_cr(Lbg, tri[2])
        if crt > fb_cr then
            fb_cr = crt
            fb_u = tri[1]
            fb_dark = tri[3]
        end
    end
    return fb_u, fb_dark
end

-- Button fill trio from same normalized bar RGB (+ lighten), no unpacking ImGui packed pixels.
function UIComponents.BarColorButtonVariants(rr, gg, bb)
    rr, gg, bb = norm_bar_rgb255(rr, gg, bb)
    local aa = 255
    local function clamp255(v)
        if v < 0 then return 0 end
        if v > 255 then return 255 end
        return v
    end
    local dh1, dh2 = 15, 30
    return Theme.rgba(rr, gg, bb, aa),
        Theme.rgba(clamp255(rr + dh1), clamp255(gg + dh1), clamp255(bb + dh1), aa),
        Theme.rgba(clamp255(rr + dh2), clamp255(gg + dh2), clamp255(bb + dh2), aa)
end

function UIComponents.BarForegroundU32(rr, gg, bb)
    local u, _ = UIComponents.BarForegroundPick(rr, gg, bb)
    return u
end

function UIComponents.PushBlackText(ctx, flag)
    if flag then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('black'))
        local ok, col = pcall(r.ImGui_Col_TextDisabled)
        if ok then r.ImGui_PushStyleColor(ctx, col, Theme.get('black')) end
    end
end

function UIComponents.PopBlackText(ctx, flag)
    if flag then
        local ok = pcall(r.ImGui_Col_TextDisabled)
        if ok then r.ImGui_PopStyleColor(ctx, 2) else r.ImGui_PopStyleColor(ctx, 1) end
    end
end

-- Always pushes Text (+ TextDisabled when available).
function UIComponents.PushBarForegroundText(ctx, foreground_u32)
    local fg = foreground_u32 or Theme.get('text_white_soft')
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), fg)
    local ok, col = pcall(r.ImGui_Col_TextDisabled)
    if ok then r.ImGui_PushStyleColor(ctx, col, fg) end
end

function UIComponents.PopBarForegroundText(ctx)
    local ok = pcall(r.ImGui_Col_TextDisabled)
    if ok then r.ImGui_PopStyleColor(ctx, 2) else r.ImGui_PopStyleColor(ctx, 1) end
end

function UIComponents.ShouldUseBlackText(r_val, g_val, b_val)
    local _, dark = UIComponents.BarForegroundPick(r_val, g_val, b_val)
    return dark
end

function UIComponents.GetBarColorAndUseBlack(items, tracks, props)
    local br, gg, bb = norm_bar_rgb255(64, 64, 64)
    local color = Theme.rgba(br, gg, bb, 255)
    if props.take_type == 'Track' then
        if #tracks == 1 and r.ValidatePtr(tracks[1], 'MediaTrack*') then
            local n = r.GetTrackColor(tracks[1]) or 0
            if n ~= 0 then
                local rr, rg, rb = r.ColorFromNative(n)
                br, gg, bb = norm_bar_rgb255(rr, rg, rb)
                color = Theme.rgba(br, gg, bb, 255)
            end
        elseif #tracks > 1 then
            local first = nil
            local all_same = true
            for _, tr in ipairs(tracks) do
                if r.ValidatePtr(tr, 'MediaTrack*') then
                    local n = r.GetTrackColor(tr) or 0
                    if n == 0 then all_same = false break end
                    if not first then first = n elseif n ~= first then all_same = false break end
                end
            end
            if all_same and first then
                local rr, rg, rb = r.ColorFromNative(first)
                br, gg, bb = norm_bar_rgb255(rr, rg, rb)
                color = Theme.rgba(br, gg, bb, 255)
            end
        end
    else
        if #items == 1 then
            if items[1] and r.ValidatePtr(items[1], 'MediaItem*') then
                local n = r.GetDisplayedMediaItemColor(items[1]) or 0
                if n ~= 0 then
                    local rr, rg, rb = r.ColorFromNative(n)
                    br, gg, bb = norm_bar_rgb255(rr, rg, rb)
                    color = Theme.rgba(br, gg, bb, 255)
                end
            end
        elseif #items > 1 and props.common_color and not props.colors_differ then
            local rr, rg, rb = r.ColorFromNative(props.common_color)
            br, gg, bb = norm_bar_rgb255(rr, rg, rb)
            color = Theme.rgba(br, gg, bb, 255)
        end
    end
    local fg_u32, use_black = UIComponents.BarForegroundPick(br, gg, bb)
    return color, use_black, br, gg, bb, fg_u32
end

function UIComponents.StyledButton(ctx, label, width, action)
    UIComponents.ColoredButton(ctx, label, width, Theme.get('transparent'), Theme.get('hover_white_32'), Theme.get('active_white_64'), action)
end

function UIComponents.StyledResetButton(ctx, label, width, is_modified, action, disabled, is_mixed)
    disabled = disabled or false
    local pop_label = UIComponents.PushLabelStateColor(ctx, disabled, is_mixed, is_modified)
    UIComponents.PushTransparentButtonStates(ctx, disabled)
    if disabled then r.ImGui_BeginDisabled(ctx, true) end
    if r.ImGui_Button(ctx, label, width) then
        if not disabled then
            action()
        end
    end
    if disabled then r.ImGui_EndDisabled(ctx) end
    r.ImGui_PopStyleColor(ctx, 3)
    if pop_label > 0 then r.ImGui_PopStyleColor(ctx, pop_label) end
end

function UIComponents.StyledImageButton(ctx, id, icon, size, action, disabled, tint_color, button_colors, use_overlay)
    disabled = disabled or false
    use_overlay = use_overlay == true
    local tint = tint_color or Theme.get('text_white_soft')
    local colors = button_colors
    if colors then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), colors.base or Theme.get('transparent'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), colors.hover or colors.base or Theme.get('transparent'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), colors.active or colors.hover or colors.base or Theme.get('transparent'))
    else
        UIComponents.PushTransparentButtonStates(ctx, disabled)
    end
    if disabled then r.ImGui_BeginDisabled(ctx, true) end

    local clicked = false
    if icon then
        clicked = r.ImGui_ImageButton(ctx, id or '##img_btn', icon, size, size, 0, 0, 1, 1, nil, tint)
        if use_overlay then UIComponents.DrawHoverActiveOverlay(ctx) end
    else
        clicked = r.ImGui_Button(ctx, '', size, size)
    end

    if clicked and not disabled and action then
        action()
    end

    if disabled then r.ImGui_EndDisabled(ctx) end
    r.ImGui_PopStyleColor(ctx, 3)
end

function UIComponents.DrawImageCenteredInLastItem(ctx, icon, tint_color, padding)
    if not icon then return end
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local rect_w = x2 - x1
    local rect_h = y2 - y1
    local tex_w, tex_h = r.ImGui_Image_GetSize(icon)
    tex_w = tonumber(tex_w) or 1
    tex_h = tonumber(tex_h) or 1
    if tex_w <= 0 then tex_w = 1 end
    if tex_h <= 0 then tex_h = 1 end

    local inner_pad = padding or 3
    local max_w = math.max(1, rect_w - inner_pad * 2)
    local max_h = math.max(1, rect_h - inner_pad * 2)
    local scale = math.min(max_w / tex_w, max_h / tex_h)
    local draw_w = tex_w * scale
    local draw_h = tex_h * scale
    local draw_x1 = x1 + (rect_w - draw_w) * 0.5
    local draw_y1 = y1 + (rect_h - draw_h) * 0.5
    local draw_x2 = draw_x1 + draw_w
    local draw_y2 = draw_y1 + draw_h

    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddImage(dl, icon, draw_x1, draw_y1, draw_x2, draw_y2, 0, 0, 1, 1,
        tint_color or Theme.get('text_white_soft'))
end

function UIComponents.ShowTooltipDelayedIfHovered(ctx, key, text, delay)
    local hovered = r.ImGui_IsItemHovered(ctx)
    if hovered and text and text ~= '' then
        local now = r.time_precise()
        local t = _hover_timers[key]
        if not t then
            _hover_timers[key] = now
        elseif now - t >= (delay or 0.5) then
            _pending_tooltip_lines = split_tooltip_lines(text)
        end
    else
        _hover_timers[key] = nil
    end
end

function UIComponents.ResetAggHoverRegion()
    _agg_region = nil
end

function UIComponents.ExtendAggHoverRegion(ctx)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    if not _agg_region then
        _agg_region = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
    else
        if x1 < _agg_region.x1 then _agg_region.x1 = x1 end
        if y1 < _agg_region.y1 then _agg_region.y1 = y1 end
        if x2 > _agg_region.x2 then _agg_region.x2 = x2 end
        if y2 > _agg_region.y2 then _agg_region.y2 = y2 end
    end
end

function UIComponents.ShowTooltipDelayedIfHoveredInAggRegion(ctx, key, text, delay)
    if not _agg_region then return end
    local mx, my = r.ImGui_GetMousePos(ctx)
    local inside = (mx >= _agg_region.x1 and mx <= _agg_region.x2 and my >= _agg_region.y1 and my <= _agg_region.y2)
    if inside and text and text ~= '' then
        local now = r.time_precise()
        local t = _hover_timers[key]
        if not t then
            _hover_timers[key] = now
        elseif now - t >= (delay or 0.5) then
            _pending_tooltip_lines = split_tooltip_lines(text)
        end
    else
        _hover_timers[key] = nil
    end
end

function UIComponents.IsMouseInsideAggRegion(ctx)
    if not _agg_region then return false end
    local mx, my = r.ImGui_GetMousePos(ctx)
    return mx >= _agg_region.x1 and mx <= _agg_region.x2 and my >= _agg_region.y1 and my <= _agg_region.y2
end

function UIComponents.RenderPendingTooltip(ctx)
    if _pending_tooltip_lines and #_pending_tooltip_lines > 0 then
        render_styled_tooltip_lines(ctx, _pending_tooltip_lines)
        _pending_tooltip_lines = nil
    end
end

function UIComponents.SetTooltipFont(font, pixel_size)
    _tooltip_font = font
    _tooltip_font_size = pixel_size or 13
end

function UIComponents.QueueStyledTooltipDelayed(ctx, id, lines, delay)
    UIComponents.QueueStyledTooltipDelayedGeneric(ctx, id, lines, delay, r.ImGui_IsItemHovered(ctx))
end

function UIComponents.QueueStyledTooltipDelayedGeneric(ctx, id, lines, delay, is_hovered)
    if not id or id == '' or lines == nil then return end
    if type(lines) == 'table' and #lines == 0 then return end
    if not is_hovered then
        _styled_tt_hover_start[id] = nil
        _styled_tt_hover_last_pos[id] = nil
        return
    end
    local mx, my = r.ImGui_GetMousePos(ctx)
    local last = _styled_tt_hover_last_pos[id]
    local moved = last and (mx ~= last.x or my ~= last.y)
    _styled_tt_hover_last_pos[id] = { x = mx, y = my }
    local now = r.time_precise()
    if moved or not _styled_tt_hover_start[id] then
        _styled_tt_hover_start[id] = now
        return
    end
    if (now - _styled_tt_hover_start[id]) >= (delay or STYLED_TOOLTIP_DELAY_DEFAULT) then
        local ln = lines
        if type(ln) == 'function' then
            ln = ln()
        end
        if ln and type(ln) == 'table' and #ln > 0 then
            _pending_tooltip_lines = ln
        end
    end
end

function UIComponents.ClearStyledTooltipHoverState(id)
    if not id or id == '' then return end
    _styled_tt_hover_start[id] = nil
    _styled_tt_hover_last_pos[id] = nil
end

function UIComponents.SetItalicFont(font)
    _italic_font = font
end

local function get_first_selected_disk_media_path()
    if not (r.APIExists and r.APIExists('FIP_GetSelectedItemsFirstSourceFilePathStr')) then
        return nil
    end
    local path = r.FIP_GetSelectedItemsFirstSourceFilePathStr('', 0)
    if path and path ~= '' then return path end
    return nil
end

local function reveal_media_path_in_system_browser(path)
    if not path or path == '' then return end
    if is_windows_os() then
        os.execute(string.format('explorer /select,%q', path))
    else
        os.execute(string.format('open -R %q', path))
    end
end

function UIComponents.GetItemInfoButtonTooltipLines()
    return {
        'Click — Open Item Properties',
        cmd_label() .. '+Click — Open in Media Explorer',
        alt_label() .. '+Click — Open Source File Properties',
        combo_label(cmd_label(), shift_label()) .. '+Click — ' .. (is_mac_os() and 'Reveal in Finder' or (is_windows_os() and 'Reveal in File Explorer' or 'Reveal in File Manager')),
    }
end

function UIComponents.GetTrackInfoButtonTooltipLines()
    return {
        'Click — Open Track Properties',
        cmd_label() .. '+Click — Open Source File Properties',
        combo_label(cmd_label(), shift_label()) .. '+Click — ' .. (is_mac_os() and 'Reveal in Finder' or (is_windows_os() and 'Reveal in File Explorer' or 'Reveal in File Manager')),
    }
end

function UIComponents.GetTrackInstrumentButtonTooltipLines()
    return { 'Click — Open Instrument UI' }
end

function UIComponents.GetTrackInstrumentMissingTooltipLines()
    return { 'No Instrument on Track' }
end

function UIComponents.GetSingleTrackOnlyTooltipLines()
    return { 'Single Track Only' }
end

function UIComponents.GetItemNotesButtonTooltipLines()
    return { 'Click — Open Item Notes' }
end

function UIComponents.GetPreservePitchTooltipLines()
    return { 'Toggle Preserve Pitch While Changing Playback Rate' }
end

function UIComponents.GetStretchModeResetTooltipLines()
    return { 'Click — Reset to Project Default Stretch Mode' }
end

function UIComponents.GetStretchModeMenuTooltipLines()
    return { 'Click — Choose Time/Pitch Stretch Mode' }
end

function UIComponents.GetItemPitchTooltipLines(continuous_item_pitch)
    if continuous_item_pitch == false then
        return {
            'Drag — Semitones',
            shift_label() .. '+Drag — Octaves',
            'Double-Click — Reset to 0',
            alt_label() .. '+Click — Enter Value',
        }
    end
    return {
        'Drag — Semitones',
        shift_label() .. '+Drag — Octaves',
        'Double-Click — Reset to 0',
        alt_label() .. '+Click — Enter Value',
    }
end

function UIComponents.GetVolumeFaderTooltipLines()
    return {
        'Drag — Item Volume (dB)',
        'Double-Click — Reset',
        alt_label() .. '+Click — Enter Value',
        'Reset Button — Unity Gain',
        'Multiple Items — Relative Change',
    }
end

function UIComponents.GetVelocityFaderTooltipLines()
    return {
        'Drag — MIDI Velocity Scale',
        'Double-Click — Reset',
        alt_label() .. '+Click — Enter Value',
        'Reset Button — 1.00x',
        'Multiple Items — Relative Change',
    }
end

function UIComponents.GetRateTooltipLines()
    return {
        'Drag — x2 or /2',
        shift_label() .. '+Drag — 0.01 Raw Rate',
        'Double-Click — Reset',
        alt_label() .. '+Click — Enter Value',
        'Reset Button — 1',
    }
end

function UIComponents.GetBPMTooltipLines()
    return {
        'Drag — Whole BPM',
        shift_label() .. '+Drag — 0.01 BPM',
        'Double-Click — Reset',
        alt_label() .. '+Click — Enter Value',
        'Reset Button — Project Tempo',
    }
end

function UIComponents.GetFilterFreqTooltipLines(label)
    label = label or 'Filter'
    return {
        'Drag — Adjust ' .. label .. ' Frequency',
        alt_label() .. '+Click — Enter Value',
        'Double-Click — Reset / Remove',
    }
end

function UIComponents.GetTakeTcpMirrorTooltipLines()
    return {
        'Click — Toggle Show All Takes in Lanes',
        cmd_label() .. '+Click — Crop to Active Take',
        combo_label(cmd_label(), shift_label()) .. '+Click — Explode Takes to Lanes',
        alt_label() .. '+Click — Explode Takes in Order',
    }
end

function UIComponents.GetTakeSelectTooltipLines()
    return {
        'Click — Choose Active Take',
    }
end

function UIComponents.GetTakePrevTooltipLines()
    return {
        'Click — Previous Take',
    }
end

function UIComponents.GetTakeNextTooltipLines()
    return {
        'Click — Next Take',
    }
end

function UIComponents.GetTakeSingleItemOnlyTooltipLines()
    return {
        'Single Item Only',
    }
end

function UIComponents.GetFxChainButtonTooltipLines()
    return {
        'Click — Open Item FX Chain',
        cmd_label() .. '+Click — Focus FX Chain Window',
        alt_label() .. '+Click — Remove All Item FX',
    }
end

function UIComponents.GetPanelBackgroundTooltipLines()
    return {
        'Right-Click — Switch Between Item and Track Panels',
    }
end

function UIComponents.GetSingleItemOnlyLabel()
    return 'Single item only'
end

function UIComponents.GetNoFxTooltipLines()
    return {
        'No FX in Slot',
    }
end

function UIComponents.Separator(ctx, left, right)
    left = left or 8
    right = right or left
    r.ImGui_SameLine(ctx, 0, left)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('pipe_gray'))
    r.ImGui_Text(ctx, "|")
    r.ImGui_PopStyleColor(ctx, 1)
    r.ImGui_SameLine(ctx, 0, right)
end

function UIComponents.IconDisplay(ctx, icon, size)
    size = size or 19
    if icon then
        r.ImGui_Image(ctx, icon, size, size)
        r.ImGui_SameLine(ctx)
    end
end

function UIComponents.ColoredButton(ctx, label, width, color, hover_color, active_color, action)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), color or Theme.get('gray_64'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), hover_color or Theme.get('gray_80'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), active_color or Theme.get('gray_96'))
    if r.ImGui_Button(ctx, label, width) then
        action()
    end
    r.ImGui_PopStyleColor(ctx, 3)
end

function UIComponents.TextButton(ctx, text, width)
    UIComponents.PushTransparentButtonStates(ctx, false)
    local clicked = r.ImGui_Button(ctx, text, width)
    local alt_clicked = is_last_item_alt_clicked(ctx)
    r.ImGui_PopStyleColor(ctx, 3)
    return clicked, alt_clicked
end

function UIComponents.AggregationBadge(ctx, tooltip)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('green_accent'))
    UIComponents.PushTransparentButtonStates(ctx, false)
    r.ImGui_Button(ctx, 'Δ', 18)
    r.ImGui_PopStyleColor(ctx, 4)
    if r.ImGui_IsItemHovered(ctx) and tooltip then
        r.ImGui_SetTooltip(ctx, tooltip)
    end
end

function UIComponents.StyledInputCommon(ctx, label, hint_text, value, width, bar_color, use_hint)
    bar_color = bar_color or Theme.get('gray_64')
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), bar_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), bar_color)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, 4)
    if width then
        r.ImGui_SetNextItemWidth(ctx, width)
    end
    local changed, new_value
    if use_hint then
        changed, new_value = r.ImGui_InputTextWithHint(ctx, label, hint_text or '', value, r.ImGui_InputTextFlags_None())
    else
        changed, new_value = r.ImGui_InputText(ctx, label, value, r.ImGui_InputTextFlags_AutoSelectAll())
    end
    local deactivated = Utils.ClearCursorContextOnDeactivation(ctx)
    r.ImGui_PopStyleVar(ctx, 2)
    r.ImGui_PopStyleColor(ctx, 2)
    return changed, new_value, deactivated
end

function UIComponents.StyledInput(ctx, label, value, width, bar_color)
    return UIComponents.StyledInputCommon(ctx, label, nil, value, width, bar_color, false)
end

function UIComponents.MultiItemInput(ctx, label, hint_text, value, width, bar_color)
    return UIComponents.StyledInputCommon(ctx, label, hint_text, value, width, bar_color, true)
end

function UIComponents.PureColorBar(ctx, width, bar_color)
    local w_avail, _ = r.ImGui_GetContentRegionAvail(ctx)
    local w = width or w_avail
    local h = 23
    r.ImGui_Dummy(ctx, w, h)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, bar_color, 6)
end

function UIComponents.StyledCombo(ctx, label, current_index, items_str, width, bar_color, items_count)
    bar_color = bar_color or Theme.get('gray_64')
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), bar_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), bar_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), Theme.get('gray_30'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), Theme.get('gray_58'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), Theme.get('gray_64'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), Theme.get('gray_74'))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, 4)
    if width then
        r.ImGui_SetNextItemWidth(ctx, width)
    end
    local changed, new_index
    if items_count then
        changed, new_index = r.ImGui_Combo(ctx, label, current_index, items_str, items_count)
    else
        changed, new_index = r.ImGui_Combo(ctx, label, current_index, items_str)
    end
    r.ImGui_PopStyleVar(ctx, 2)
    r.ImGui_PopStyleColor(ctx, 6)
    return changed, new_index
end

function UIComponents.StyledSlider(ctx, label, value, min_val, max_val, format, bar_color)
    bar_color = bar_color or Theme.get('green_accent')
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), bar_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), bar_color)
    local changed, new_value = r.ImGui_SliderDouble(ctx, label, value, min_val, max_val, format)
    local alt_clicked = is_last_item_alt_clicked(ctx)
    local dbl_clicked = r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0)
    local deactivated = Utils.ClearCursorContextOnDeactivation(ctx)
    r.ImGui_PopStyleColor(ctx, 2)
    return changed, new_value, deactivated, alt_clicked, dbl_clicked
end

function UIComponents.DragDoubleInput(ctx, id, value, width, speed, min_val, max_val, format)
    if width then
        r.ImGui_SetNextItemWidth(ctx, width)
    end
    local changed, new_value = r.ImGui_DragDouble(ctx, id, value, speed or 0.1, min_val or -999, max_val or 999, format or "%.0f")
    local deactivated = Utils.ClearCursorContextOnDeactivation(ctx)
    return changed, new_value, deactivated
end

local _freqbox_drag_state = {}
local _freqbox_last_activated = {}
local FREQBOX_DOUBLE_CLICK_SEC = 0.45

-- Numeric box: "20k"/"1k"/"999 Hz", left-mouse drag. reset_norm: double-click sets to this (0=20Hz HP, 1=20k LP).
function UIComponents.FreqBox(ctx, id, norm, width, color, inverted, display_fn, reset_norm)
    local box_h = 18
    r.ImGui_InvisibleButton(ctx, id, width, box_h)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local bg = Theme.get('gray_42')
    local border = Theme.get('gray_74')
    r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, bg, 4)
    r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, border, 4, 0, 1.0)
    local display_str = display_fn(norm)
    local tw, th = r.ImGui_CalcTextSize(ctx, display_str)
    local pad = 4
    local ty = y1 + (box_h - th) * 0.5
    r.ImGui_DrawList_AddText(dl, x1 + pad, ty, color, display_str)

    local changed = false
    local new_norm = norm
    local activated = r.ImGui_IsItemActivated(ctx)
    local active = r.ImGui_IsItemActive(ctx)
    local deactivated = Utils.ClearCursorContextOnDeactivation(ctx)
    local alt_clicked = is_last_item_alt_clicked(ctx)

    if reset_norm ~= nil and activated then
        local now = r.time_precise()
        local last = _freqbox_last_activated[id]
        if last and (now - last) <= FREQBOX_DOUBLE_CLICK_SEC then
            new_norm = math.max(0, math.min(1, reset_norm))
            changed = true
            _freqbox_last_activated[id] = nil
        else
            _freqbox_last_activated[id] = now
        end
    end

    if activated and not changed and not alt_clicked then
        _freqbox_drag_state[id] = { start = norm }
    end
    if active and _freqbox_drag_state[id] and not changed then
        local state = _freqbox_drag_state[id]
        local dx, _dy = r.ImGui_GetMouseDragDelta(ctx, 0)
        local dx_val = (type(dx) == "number") and dx or (type(dx) == "table" and dx.x)
        if dx_val and type(dx_val) == "number" then
            local sens = (width and width > 0) and (0.8 / (width * 3)) or 0.000033
            local shift = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0
            if shift then sens = sens * 0.1 end
            -- HP: drag right (dx>0) -> norm up. LP: drag left (dx<0) -> norm down.
            local delta_norm = dx_val * sens
            new_norm = state.start + delta_norm
            if new_norm < 0 then new_norm = 0 end
            if new_norm > 1 then new_norm = 1 end
            if math.abs(new_norm - norm) > 1e-7 then
                changed = true
            end
        end
    end
    if deactivated then
        _freqbox_drag_state[id] = nil
    end
    UIComponents.DrawHoverActiveOverlay(ctx)
    return changed, new_norm, activated, deactivated, alt_clicked
end

-- FreqBoxHz: works with Hz directly, logarithmic drag behavior
function UIComponents.FreqBoxHz(ctx, id, freq_hz, width, color, inverted, display_fn, reset_freq_hz)
    local box_h = 18
    r.ImGui_InvisibleButton(ctx, id, width, box_h)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local bg = Theme.get('gray_42')
    local border = Theme.get('gray_74')
    r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, bg, 4)
    r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, border, 4, 0, 1.0)
    local display_str = display_fn(freq_hz)
    local tw, th = r.ImGui_CalcTextSize(ctx, display_str)
    local pad = 4
    local ty = y1 + (box_h - th) * 0.5
    r.ImGui_DrawList_AddText(dl, x1 + pad, ty, color, display_str)

    local changed = false
    local new_freq = freq_hz
    local activated = r.ImGui_IsItemActivated(ctx)
    local active = r.ImGui_IsItemActive(ctx)
    local deactivated = Utils.ClearCursorContextOnDeactivation(ctx)

    if reset_freq_hz ~= nil and activated then
        local now = r.time_precise()
        local last = _freqbox_last_activated[id]
        if last and (now - last) <= FREQBOX_DOUBLE_CLICK_SEC then
            new_freq = reset_freq_hz
            changed = true
            _freqbox_last_activated[id] = nil
        else
            _freqbox_last_activated[id] = now
        end
    end

    if activated and not changed then
        _freqbox_drag_state[id] = { start = freq_hz }
    end
    if active and _freqbox_drag_state[id] and not changed then
        local state = _freqbox_drag_state[id]
        local dx = r.ImGui_GetMouseDragDelta(ctx, 0)
        if dx and type(dx) == "number" then
            -- Logarithmic drag: multiply by exp(dx * factor)
            local factor = 0.005 -- base sensitivity
            local shift = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0
            if shift then factor = factor * 0.1 end
            local delta_factor = dx * factor
            if inverted then delta_factor = -delta_factor end
            new_freq = state.start * math.exp(delta_factor)
            new_freq = math.max(20, math.min(20000, new_freq))
            if new_freq ~= freq_hz then changed = true end
        end
    end
    if deactivated then
        _freqbox_drag_state[id] = nil
    end
    UIComponents.DrawHoverActiveOverlay(ctx)
    return changed, new_freq
end

function UIComponents.ApplyWindowStyle(ctx)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 12, 6)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), Theme.getMainWindowTransportBackground())
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), Theme.get('gray_45'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), Theme.get('gray_61'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_42'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), Theme.get('gray_58'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), Theme.get('gray_74'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('gray_64'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('gray_80'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('gray_96'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), Theme.get('green_accent'))
end

function UIComponents.PopWindowStyle(ctx)
    r.ImGui_PopStyleColor(ctx, 10)
    r.ImGui_PopStyleVar(ctx, 3)
end

function UIComponents.StyledCheckbox(ctx, label, value, is_mixed, disabled)
    disabled = disabled or false
    local mixed = (value == nil and is_mixed)
    if disabled then
        UIComponents.PushLabelStateColor(ctx, true, false, false)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), Theme.get('pipe_gray'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('frame_disabled'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), Theme.get('frame_disabled'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), Theme.get('frame_disabled'))
        r.ImGui_BeginDisabled(ctx, true)
    elseif mixed then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), Theme.get('yellow'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_64'))
    end
    local changed, new_value = r.ImGui_Checkbox(ctx, label, mixed or (value or false))
    if disabled then
        r.ImGui_EndDisabled(ctx)
        r.ImGui_PopStyleColor(ctx, 5)
        changed = false
    elseif mixed then
        r.ImGui_PopStyleColor(ctx, 2)
    end
    return changed, new_value
end

function UIComponents.IconToggle(ctx, id, icons, state, is_mixed, size)
    size = size or 20
    local mixed = (state == nil and is_mixed)
    local current = mixed and false or (state or false)
    local icon = nil
    if icons then
        icon = mixed and icons.mixed or (current and icons.on or icons.off)
    end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('transparent'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('hover_white_32'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('active_white_64'))
    if id then r.ImGui_PushID(ctx, id) end
    local clicked = false
    if icon then
        clicked = r.ImGui_ImageButton(ctx, '##img_toggle', icon, size, size, 0, 0, 1, 1, nil, Theme.get('text_white_soft'))
        UIComponents.DrawHoverActiveOverlay(ctx)
    else
        clicked = r.ImGui_Button(ctx, current and 'On' or 'Off', size)
    end
    if id then r.ImGui_PopID(ctx) end
    r.ImGui_PopStyleColor(ctx, 3)
    if clicked then
        if mixed then
            return true, true
        else
            return true, not current
        end
    end
    return false, mixed and nil or current
end

function UIComponents.IconToggleDual(ctx, id, icon_on, icon_off, state, size)
    return UIComponents.IconToggle(ctx, id, { on = icon_on, off = icon_off }, state, false, size)
end

function UIComponents.IconToggleTri(ctx, id, icon_on, icon_off, icon_mixed, state, is_mixed, size)
    return UIComponents.IconToggle(ctx, id, { on = icon_on, off = icon_off, mixed = icon_mixed }, state, is_mixed, size)
end

function UIComponents.ParameterControl(ctx, label, value, width, speed, min_val, max_val, format, reset_action, label_width, has_different_values, is_modified)
    if is_modified == nil then
        is_modified = (value ~= 0)
    end
    UIComponents.StyledResetButton(ctx, label, label_width or 40, is_modified, reset_action)
    r.ImGui_SameLine(ctx, 0, 2)
    local changed, new_value, deactivated = UIComponents.DragDoubleInput(ctx, '##' .. label, value, width or 50, speed, min_val, max_val, format)
    return changed, new_value, deactivated
end

local _knob_drag_state = {}

function UIComponents.Knob(ctx, id, value, min_val, max_val, default_value, radius, active)
    radius = radius or 9
    local size = radius * 2 + 4
    if id then r.ImGui_PushID(ctx, id) end
    r.ImGui_InvisibleButton(ctx, '##knob', size, size)
    if id then r.ImGui_PopID(ctx) end

    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local cx = (x1 + x2) * 0.5
    local cy = (y1 + y2) * 0.5
    local dl = r.ImGui_GetWindowDrawList(ctx)

    local bg = Theme.get('gray_42')
    local border = Theme.get('gray_74')
    local accent = (active == false) and Theme.get('pipe_gray') or Theme.get('green_accent')

    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, radius, bg, 32)
    r.ImGui_DrawList_AddCircle(dl, cx, cy, radius, border, 32, 1.0)
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 2.0, Theme.get('black'), 16)

    local range = max_val - min_val
    if range <= 0 then range = 1 end
    local t = (value - min_val) / range
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local angle_start = -math.pi * 1.25
    local angle_end = math.pi * 0.25
    local angle = angle_start + t * (angle_end - angle_start)
    local r_inner = radius * 0.65
    local x_end = cx + math.cos(angle) * r_inner
    local y_end = cy + math.sin(angle) * r_inner
    r.ImGui_DrawList_AddLine(dl, cx, cy, x_end, y_end, accent, 2.0)

    local id_key = id or 'knob'
    local changed = false
    local new_value = value
    local reset = false

    local active = r.ImGui_IsItemActive(ctx)
    if active then
        local state = _knob_drag_state[id_key]
        if not state then
            _knob_drag_state[id_key] = { start = value }
            state = _knob_drag_state[id_key]
        end
        local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
        local speed = range / 200.0
        local shift = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0
        if shift then speed = speed * 0.05 end
        local v = state.start + (-dy) * speed
        if shift then
            v = math.floor(v + 0.5)
        end
        if v < min_val then v = min_val end
        if v > max_val then v = max_val end
        if v ~= new_value then
            new_value = v
            changed = true
        end
    end

    local hovered = r.ImGui_IsItemHovered(ctx)
    if hovered and r.ImGui_IsMouseDoubleClicked(ctx, 0) and default_value ~= nil then
        new_value = default_value
        changed = true
        reset = true
    end

    local deactivated = Utils.ClearCursorContextOnDeactivation(ctx)
    if deactivated then
        _knob_drag_state[id_key] = nil
    end

    return changed, new_value, deactivated, reset
end

local _pitch_drag_state = {}
local _item_pitch_drag_state = {}

function UIComponents.IsAnyPitchDragActive()
    return next(_pitch_drag_state) ~= nil or next(_item_pitch_drag_state) ~= nil
end

local function round_to_cents(v)
    v = tonumber(v) or 0
    if v >= 0 then return math.floor(v * 100 + 0.5) / 100 end
    return math.ceil(v * 100 - 0.5) / 100
end

local function round_to_nearest(v)
    v = tonumber(v) or 0
    if v >= 0 then return math.floor(v + 0.5) end
    return math.ceil(v - 0.5)
end

function UIComponents.FormatItemPitchValue(value)
    return string.format('%.2f', round_to_cents(value or 0))
end

function UIComponents.FormatBPMValue(value)
    return string.format('%.2f', round_to_cents(value or 0))
end

function UIComponents.RateToDisplayValue(rate)
    local raw = tonumber(rate) or 1.0
    if raw >= 1.0 then return raw end
    return -(raw * 1000.0)
end

function UIComponents.DisplayToRateValue(display)
    local v = tonumber(display)
    if not v then return nil end
    if v < 0 then return math.abs(v) / 1000.0 end
    return v
end

function UIComponents.FormatRateDisplayValue(rate)
    local display = UIComponents.RateToDisplayValue(rate)
    local rounded_int = round_to_nearest(display)
    if math.abs(display - rounded_int) < 0.0005 then
        return string.format('%.0f', rounded_int)
    end
    if display < 0 then
        return string.format('%.1f', display)
    end
    return string.format('%.3f', display)
end

function UIComponents.ParseRateInput(text, min_rate, max_rate)
    local normalized = ((text or ''):gsub(',', '.'))
    local parsed = tonumber(normalized)
    if not parsed then return nil end
    local rate = UIComponents.DisplayToRateValue(parsed)
    if not rate then return nil end
    local mn = min_rate or 0.01
    local mx = max_rate or 100
    if rate < mn then rate = mn end
    if rate > mx then rate = mx end
    return rate
end

function UIComponents.ParseItemPitchValue(text, min_val, max_val)
    local normalized = ((text or ''):gsub(',', '.'))
    local parsed = tonumber(normalized)
    if not parsed then return nil end
    parsed = round_to_cents(parsed)
    local mn = min_val or -96
    local mx = max_val or 96
    if parsed < mn then parsed = mn end
    if parsed > mx then parsed = mx end
    return parsed
end

function UIComponents.ParseBPMValue(text, min_val, max_val)
    local normalized = ((text or ''):gsub(',', '.'))
    local parsed = tonumber(normalized)
    if not parsed then return nil end
    parsed = round_to_cents(parsed)
    local mn = min_val or 20
    local mx = max_val or 999
    if parsed < mn then parsed = mn end
    if parsed > mx then parsed = mx end
    return parsed
end

function UIComponents.FormatFrequencyInput(freq_hz)
    return string.format('%.0f', tonumber(freq_hz) or 20)
end

function UIComponents.ParseFrequencyInput(text, min_hz, max_hz)
    local s = ((text or ''):lower():gsub(',', '.'):gsub('%s+', ''))
    if s == '' then return nil end
    local mult = 1
    if s:sub(-3) == 'khz' then
        mult = 1000
        s = s:sub(1, -4)
    elseif s:sub(-1) == 'k' then
        mult = 1000
        s = s:sub(1, -2)
    elseif s:sub(-2) == 'hz' then
        s = s:sub(1, -3)
    end
    local parsed = tonumber(s)
    if not parsed then return nil end
    parsed = parsed * mult
    local mn = min_hz or 20
    local mx = max_hz or 20000
    if parsed < mn then parsed = mn end
    if parsed > mx then parsed = mx end
    return parsed
end

function UIComponents.VerticalPitchControl(ctx, label, value, width, speed, min_val, max_val, format, reset_action, label_width, has_different_values, is_modified, is_mixed, agg_count, color_by_sign, octave_drag_default, on_cmd_click, tooltip_lines, use_alt_click)
    if is_modified == nil then
        is_modified = (value ~= 0)
    end
    local id = label
    local disp_val = (_pitch_drag_state[id] and _pitch_drag_state[id].last) or value
    local disp_int = math.floor(disp_val + 0.5)
    local pushed_custom = false
    if color_by_sign and not is_mixed then
        local col = (disp_int > 0) and Theme.get('turquoise') or ((disp_int < 0) and Theme.get('orange_dark') or Theme.get('text_white_soft'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col)
        pushed_custom = true
        UIComponents.StyledResetButton(ctx, label, label_width or 40, false, reset_action, nil, false)
        r.ImGui_PopStyleColor(ctx, 1)
    else
        UIComponents.StyledResetButton(ctx, label, label_width or 40, is_modified, reset_action, nil, is_mixed)
    end
    local tt_lines = tooltip_lines
    local tt_id = nil
    local r1x1, r1y1, r1x2, r1y2
    if tt_lines and #tt_lines > 0 then
        tt_id = 'vp_' .. string.gsub(label, '[^%w]', '_')
        r1x1, r1y1 = r.ImGui_GetItemRectMin(ctx)
        r1x2, r1y2 = r.ImGui_GetItemRectMax(ctx)
    end
    if agg_count and agg_count > 1 then UIComponents.ExtendAggHoverRegion(ctx) end
    r.ImGui_SameLine(ctx, 0, 2)
    local w = width or 50
    local fmt = format or "%.0f"
    local text = string.format(fmt, disp_int)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('gray_42'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('gray_58'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('gray_74'))
    r.ImGui_Button(ctx, ' ' .. text .. '##' .. label, w)
    local clicked = is_last_item_left_clicked(ctx)
    if agg_count and agg_count > 1 then
        UIComponents.DrawAggregationOutline(ctx, nil, 4, 0)
        UIComponents.ExtendAggHoverRegion(ctx)
    end
    r.ImGui_PopStyleColor(ctx, 3)
    local item_deactivated = r.ImGui_IsItemDeactivated(ctx)
    local activated = r.ImGui_IsItemActivated(ctx)
    local mouse_down = r.ImGui_IsMouseDown(ctx, 0)
    local cmd_click_handled = false
    local reset_by_double_click = false
    if clicked and on_cmd_click then
        local mods = r.ImGui_GetKeyMods(ctx)
        local modifier_held
        if use_alt_click then
            modifier_held = (mods & r.ImGui_Mod_Alt()) ~= 0
        else
            modifier_held = (mods & r.ImGui_Mod_Super()) ~= 0 or (mods & r.ImGui_Mod_Ctrl()) ~= 0
        end
        if modifier_held then
            on_cmd_click()
            cmd_click_handled = true
        end
    end
    if activated and not cmd_click_handled then
        _pitch_drag_state[id] = { start = value, last = value }
    end
    local changed = false
    local new_value = value
    if _pitch_drag_state[id] and mouse_down then
        local dx, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
        local s = speed or 0.1
        local shift = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0
        local octave_mode = (octave_drag_default ~= false)
        local s2
        if octave_mode then
            s2 = shift and s or (s * 5)
        else
            s2 = shift and (s * 5) or s
        end
        local raw = _pitch_drag_state[id].start + (-dy) * s2
        if octave_mode then
            if shift then
                new_value = math.floor(raw + 0.5)
            else
                local diff = raw - _pitch_drag_state[id].start
                local steps = math.floor(diff / 12 + 0.5)
                new_value = _pitch_drag_state[id].start + steps * 12
            end
        else
            if shift then
                local diff = raw - _pitch_drag_state[id].start
                local steps = math.floor(diff / 12 + 0.5)
                new_value = _pitch_drag_state[id].start + steps * 12
            else
                new_value = math.floor(raw + 0.5)
            end
        end
        local mn = min_val or -999
        local mx = max_val or 999
        if new_value < mn then new_value = mn end
        if new_value > mx then new_value = mx end
        if new_value ~= _pitch_drag_state[id].last then
            changed = true
            _pitch_drag_state[id].last = new_value
        end
    end
    local hovered = r.ImGui_IsItemHovered(ctx)
    local dbl = hovered and r.ImGui_IsMouseDoubleClicked(ctx, 0)
    if dbl and reset_action then
        reset_action()
        changed = false
        reset_by_double_click = true
    end
    local deactivated = false
    if reset_by_double_click then
        _pitch_drag_state[id] = nil
    elseif not mouse_down and _pitch_drag_state[id] then
        _pitch_drag_state[id] = nil
        local ok = pcall(r.ImGui_ResetMouseDragDelta, ctx, 0)
        local hovered = r.ImGui_IsWindowHovered(ctx)
        if not hovered then
            Utils.DeferClearCursorContext()
        end
        deactivated = true
    elseif item_deactivated and not mouse_down then
        deactivated = true
    end
    if tt_id and tt_lines and #tt_lines > 0 and r1x1 then
        local r2x1, r2y1 = r.ImGui_GetItemRectMin(ctx)
        local r2x2, r2y2 = r.ImGui_GetItemRectMax(ctx)
        local mx, my = r.ImGui_GetMousePos(ctx)
        local ux1 = math.min(r1x1, r2x1)
        local uy1 = math.min(r1y1, r2y1)
        local ux2 = math.max(r1x2, r2x2)
        local uy2 = math.max(r1y2, r2y2)
        local inside = mx >= ux1 and mx <= ux2 and my >= uy1 and my <= uy2
        UIComponents.QueueStyledTooltipDelayedGeneric(ctx, tt_id, tt_lines, STYLED_TOOLTIP_DELAY_DEFAULT, inside)
    end
    return changed, new_value, deactivated, activated
end

local _continuous_value_drag_state = {}
local _rate_drag_state = {}

function UIComponents.ContinuousValueControl(ctx, label, value, width, speed, min_val, max_val, format, reset_action, label_width, is_modified, is_mixed, agg_count, on_cmd_click, tooltip_lines, use_alt_click)
    if is_modified == nil then
        is_modified = (math.abs(value or 0) > 0.0001)
    end
    local id = label
    local disp_val = (_continuous_value_drag_state[id] and _continuous_value_drag_state[id].last) or value or 0
    local text = string.format(format or '%.2f', round_to_cents(disp_val))

    UIComponents.StyledResetButton(ctx, label, label_width or 40, is_modified, reset_action, nil, is_mixed)
    local tt_lines = tooltip_lines
    local tt_id = nil
    local r1x1, r1y1, r1x2, r1y2
    if tt_lines and #tt_lines > 0 then
        tt_id = 'cv_' .. string.gsub(label, '[^%w]', '_')
        r1x1, r1y1 = r.ImGui_GetItemRectMin(ctx)
        r1x2, r1y2 = r.ImGui_GetItemRectMax(ctx)
    end
    if agg_count and agg_count > 1 then UIComponents.ExtendAggHoverRegion(ctx) end
    r.ImGui_SameLine(ctx, 0, 2)
    local w = width or 62
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('gray_42'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('gray_58'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('gray_74'))
    r.ImGui_Button(ctx, ' ' .. text .. '##' .. label, w)
    local clicked = is_last_item_left_clicked(ctx)
    local dbl_clicked = r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0)
    if agg_count and agg_count > 1 then
        UIComponents.DrawAggregationOutline(ctx, nil, 4, 0)
        UIComponents.ExtendAggHoverRegion(ctx)
    end
    r.ImGui_PopStyleColor(ctx, 3)

    local item_deactivated = r.ImGui_IsItemDeactivated(ctx)
    local activated = r.ImGui_IsItemActivated(ctx)
    local mouse_down = r.ImGui_IsMouseDown(ctx, 0)
    local cmd_click_handled = false
    if clicked and on_cmd_click then
        local mods = r.ImGui_GetKeyMods(ctx)
        local modifier_held
        if use_alt_click then
            modifier_held = (mods & r.ImGui_Mod_Alt()) ~= 0
        else
            modifier_held = (mods & r.ImGui_Mod_Super()) ~= 0 or (mods & r.ImGui_Mod_Ctrl()) ~= 0
        end
        if modifier_held then
            on_cmd_click()
            cmd_click_handled = true
        end
    end
    if activated and not cmd_click_handled then
        local start = round_to_cents(value or 0)
        _continuous_value_drag_state[id] = { start = start, last = start }
    end

    local changed = false
    local new_value = round_to_cents(value or 0)
    if _continuous_value_drag_state[id] and mouse_down then
        local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
        local mods = r.ImGui_GetKeyMods(ctx)
        local shift = (mods & r.ImGui_Mod_Shift()) ~= 0
        local start = _continuous_value_drag_state[id].start
        if shift then
            local fine_speed = (speed or 0.1) * 0.1
            local raw = start + (-dy) * fine_speed
            new_value = round_to_cents(raw)
        else
            local whole_steps = round_to_nearest((-dy) * (speed or 0.1))
            new_value = start + whole_steps
        end
        local mn = min_val or -999
        local mx = max_val or 999
        if new_value < mn then new_value = mn end
        if new_value > mx then new_value = mx end
        if math.abs(new_value - _continuous_value_drag_state[id].last) > 0.00001 then
            changed = true
            _continuous_value_drag_state[id].last = new_value
        end
    end

    local deactivated = false
    if not mouse_down and _continuous_value_drag_state[id] then
        _continuous_value_drag_state[id] = nil
        pcall(r.ImGui_ResetMouseDragDelta, ctx, 0)
        local hovered_window = r.ImGui_IsWindowHovered(ctx)
        if not hovered_window then
            Utils.DeferClearCursorContext()
        end
        deactivated = true
    elseif item_deactivated and not mouse_down then
        deactivated = true
    end

    if tt_id and tt_lines and #tt_lines > 0 and r1x1 then
        local r2x1, r2y1 = r.ImGui_GetItemRectMin(ctx)
        local r2x2, r2y2 = r.ImGui_GetItemRectMax(ctx)
        local mx, my = r.ImGui_GetMousePos(ctx)
        local ux1 = math.min(r1x1, r2x1)
        local uy1 = math.min(r1y1, r2y1)
        local ux2 = math.max(r1x2, r2x2)
        local uy2 = math.max(r1y2, r2y2)
        local inside = mx >= ux1 and mx <= ux2 and my >= uy1 and my <= uy2
        UIComponents.QueueStyledTooltipDelayedGeneric(ctx, tt_id, tt_lines, STYLED_TOOLTIP_DELAY_DEFAULT, inside)
    end

    return changed, new_value, deactivated, activated, dbl_clicked
end

function UIComponents.RateControl(ctx, label, value, width, speed, min_val, max_val, reset_action, label_width, is_modified, is_mixed, agg_count, on_cmd_click, tooltip_lines, use_alt_click)
    if is_modified == nil then
        is_modified = math.abs((value or 1.0) - 1.0) > 0.0001
    end
    local id = label
    local disp_rate = (_rate_drag_state[id] and _rate_drag_state[id].last) or value or 1.0
    local text = UIComponents.FormatRateDisplayValue(disp_rate)

    UIComponents.StyledResetButton(ctx, label, label_width or 40, is_modified, reset_action, nil, is_mixed)
    local tt_lines = tooltip_lines
    local tt_id = nil
    local r1x1, r1y1, r1x2, r1y2
    if tt_lines and #tt_lines > 0 then
        tt_id = 'rate_' .. string.gsub(label, '[^%w]', '_')
        r1x1, r1y1 = r.ImGui_GetItemRectMin(ctx)
        r1x2, r1y2 = r.ImGui_GetItemRectMax(ctx)
    end
    if agg_count and agg_count > 1 then UIComponents.ExtendAggHoverRegion(ctx) end
    r.ImGui_SameLine(ctx, 0, 2)
    local w = width or 70
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('gray_42'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('gray_58'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('gray_74'))
    r.ImGui_Button(ctx, ' ' .. text .. '##' .. label, w)
    local clicked = is_last_item_left_clicked(ctx)
    local dbl_clicked = r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0)
    if agg_count and agg_count > 1 then
        UIComponents.DrawAggregationOutline(ctx, nil, 4, 0)
        UIComponents.ExtendAggHoverRegion(ctx)
    end
    r.ImGui_PopStyleColor(ctx, 3)

    local item_deactivated = r.ImGui_IsItemDeactivated(ctx)
    local activated = r.ImGui_IsItemActivated(ctx)
    local mouse_down = r.ImGui_IsMouseDown(ctx, 0)
    local cmd_click_handled = false
    if clicked and on_cmd_click then
        local mods = r.ImGui_GetKeyMods(ctx)
        local modifier_held
        if use_alt_click then
            modifier_held = (mods & r.ImGui_Mod_Alt()) ~= 0
        else
            modifier_held = (mods & r.ImGui_Mod_Super()) ~= 0 or (mods & r.ImGui_Mod_Ctrl()) ~= 0
        end
        if modifier_held then
            on_cmd_click()
            cmd_click_handled = true
        end
    end
    if activated and not cmd_click_handled then
        local start = tonumber(value) or 1.0
        _rate_drag_state[id] = { start = start, last = start }
    end

    local changed = false
    local new_value = tonumber(value) or 1.0
    if _rate_drag_state[id] and mouse_down then
        local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
        local mods = r.ImGui_GetKeyMods(ctx)
        local shift = (mods & r.ImGui_Mod_Shift()) ~= 0
        local start = _rate_drag_state[id].start
        if shift then
            local fine_speed = (speed or 0.1) * 0.1
            new_value = start + (-dy) * fine_speed
            new_value = round_to_cents(new_value)
        else
            local whole_steps = round_to_nearest((-dy) * (speed or 0.1))
            new_value = start * (2 ^ whole_steps)
        end
        local mn = min_val or 0.01
        local mx = max_val or 100
        if new_value < mn then new_value = mn end
        if new_value > mx then new_value = mx end
        if math.abs(new_value - _rate_drag_state[id].last) > 0.00001 then
            changed = true
            _rate_drag_state[id].last = new_value
        end
    end

    local deactivated = false
    if not mouse_down and _rate_drag_state[id] then
        _rate_drag_state[id] = nil
        pcall(r.ImGui_ResetMouseDragDelta, ctx, 0)
        local hovered_window = r.ImGui_IsWindowHovered(ctx)
        if not hovered_window then
            Utils.DeferClearCursorContext()
        end
        deactivated = true
    elseif item_deactivated and not mouse_down then
        deactivated = true
    end

    if tt_id and tt_lines and #tt_lines > 0 and r1x1 then
        local r2x1, r2y1 = r.ImGui_GetItemRectMin(ctx)
        local r2x2, r2y2 = r.ImGui_GetItemRectMax(ctx)
        local mx, my = r.ImGui_GetMousePos(ctx)
        local ux1 = math.min(r1x1, r2x1)
        local uy1 = math.min(r1y1, r2y1)
        local ux2 = math.max(r1x2, r2x2)
        local uy2 = math.max(r1y2, r2y2)
        local inside = mx >= ux1 and mx <= ux2 and my >= uy1 and my <= uy2
        UIComponents.QueueStyledTooltipDelayedGeneric(ctx, tt_id, tt_lines, STYLED_TOOLTIP_DELAY_DEFAULT, inside)
    end

    return changed, new_value, deactivated, activated, dbl_clicked
end

function UIComponents.ItemPitchControl(ctx, label, value, width, min_val, max_val, reset_action, label_width, is_modified, is_mixed, agg_count, on_cmd_click, tooltip_lines)
    if is_modified == nil then
        is_modified = (math.abs(value or 0) > 0.0001)
    end
    local id = label
    local disp_val = (_item_pitch_drag_state[id] and _item_pitch_drag_state[id].last) or value or 0
    local text = UIComponents.FormatItemPitchValue(disp_val)

    UIComponents.StyledResetButton(ctx, label, label_width or 40, is_modified, reset_action, nil, is_mixed)
    local tt_lines = tooltip_lines
    local tt_id = nil
    local r1x1, r1y1, r1x2, r1y2
    if tt_lines and #tt_lines > 0 then
        tt_id = 'ip_' .. string.gsub(label, '[^%w]', '_')
        r1x1, r1y1 = r.ImGui_GetItemRectMin(ctx)
        r1x2, r1y2 = r.ImGui_GetItemRectMax(ctx)
    end
    if agg_count and agg_count > 1 then UIComponents.ExtendAggHoverRegion(ctx) end
    r.ImGui_SameLine(ctx, 0, 2)
    local w = width or 62
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('gray_42'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('gray_58'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('gray_74'))
    r.ImGui_Button(ctx, ' ' .. text .. '##' .. label, w)
    local clicked = is_last_item_left_clicked(ctx)
    if agg_count and agg_count > 1 then
        UIComponents.DrawAggregationOutline(ctx, nil, 4, 0)
        UIComponents.ExtendAggHoverRegion(ctx)
    end
    r.ImGui_PopStyleColor(ctx, 3)

    local item_deactivated = r.ImGui_IsItemDeactivated(ctx)
    local activated = r.ImGui_IsItemActivated(ctx)
    local mouse_down = r.ImGui_IsMouseDown(ctx, 0)
    local cmd_click_handled = false
    local reset_by_double_click = false
    if clicked and on_cmd_click then
        local mods = r.ImGui_GetKeyMods(ctx)
        local alt_held = (mods & r.ImGui_Mod_Alt()) ~= 0
        if alt_held then
            on_cmd_click()
            cmd_click_handled = true
        end
    end
    if activated and not cmd_click_handled then
        local start = round_to_cents(value or 0)
        _item_pitch_drag_state[id] = { start = start, last = start }
    end

    local changed = false
    local new_value = round_to_cents(value or 0)
    if _item_pitch_drag_state[id] and mouse_down then
        local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
        local mods = r.ImGui_GetKeyMods(ctx)
        local shift = (mods & r.ImGui_Mod_Shift()) ~= 0
        local alt = (mods & r.ImGui_Mod_Alt()) ~= 0
        local start = _item_pitch_drag_state[id].start
        if alt then
            local octave_steps = round_to_nearest((-dy) / 24.0)
            new_value = start + octave_steps * 12.0
        elseif shift then
            new_value = start + (-dy) * 0.01
        else
            local semi_steps = round_to_nearest((-dy) * 0.1)
            new_value = start + semi_steps
        end
        new_value = round_to_cents(new_value)
        local mn = min_val or -96
        local mx = max_val or 96
        if new_value < mn then new_value = mn end
        if new_value > mx then new_value = mx end
        if math.abs(new_value - _item_pitch_drag_state[id].last) > 0.00001 then
            changed = true
            _item_pitch_drag_state[id].last = new_value
        end
    end

    local hovered = r.ImGui_IsItemHovered(ctx)
    local dbl = hovered and r.ImGui_IsMouseDoubleClicked(ctx, 0)
    if dbl and reset_action then
        reset_action()
        changed = false
        reset_by_double_click = true
    end

    local deactivated = false
    if reset_by_double_click then
        _item_pitch_drag_state[id] = nil
    elseif not mouse_down and _item_pitch_drag_state[id] then
        _item_pitch_drag_state[id] = nil
        pcall(r.ImGui_ResetMouseDragDelta, ctx, 0)
        local hovered_window = r.ImGui_IsWindowHovered(ctx)
        if not hovered_window then
            Utils.DeferClearCursorContext()
        end
        deactivated = true
    elseif item_deactivated and not mouse_down then
        deactivated = true
    end

    if tt_id and tt_lines and #tt_lines > 0 and r1x1 then
        local r2x1, r2y1 = r.ImGui_GetItemRectMin(ctx)
        local r2x2, r2y2 = r.ImGui_GetItemRectMax(ctx)
        local mx, my = r.ImGui_GetMousePos(ctx)
        local ux1 = math.min(r1x1, r2x1)
        local uy1 = math.min(r1y1, r2y1)
        local ux2 = math.max(r1x2, r2x2)
        local uy2 = math.max(r1y2, r2y2)
        local inside = mx >= ux1 and mx <= ux2 and my >= uy1 and my <= uy2
        UIComponents.QueueStyledTooltipDelayedGeneric(ctx, tt_id, tt_lines, STYLED_TOOLTIP_DELAY_DEFAULT, inside)
    end

    return changed, new_value, deactivated, activated
end


function UIComponents.RenderInfoButton(ctx, command_id)
    UIComponents.StyledButton(ctx, 'i', 18, function()
        local mods = r.ImGui_GetKeyMods(ctx)
        local alt_pressed = (mods & r.ImGui_Mod_Alt()) ~= 0
        local shift_pressed = (mods & r.ImGui_Mod_Shift()) ~= 0
        local cmd_pressed = (mods & r.ImGui_Mod_Super()) ~= 0
        local ctrl_pressed = (mods & r.ImGui_Mod_Ctrl()) ~= 0
        local cmd_or_ctrl = cmd_pressed or ctrl_pressed
        local path = get_first_selected_disk_media_path()

        if shift_pressed and cmd_or_ctrl then
            reveal_media_path_in_system_browser(path)
            return
        end

        if command_id == ITEM_INFO_PROPERTIES_ACTION then
            if alt_pressed then
                r.Main_OnCommand(40011, 0)
            elseif cmd_or_ctrl then
                if path and r.APIExists and r.APIExists('OpenMediaExplorer') then
                    pcall(r.OpenMediaExplorer, path, false)
                end
            else
                r.Main_OnCommand(command_id, 0)
            end
        else
            if cmd_or_ctrl then
                r.Main_OnCommand(40011, 0)
            else
                r.Main_OnCommand(command_id, 0)
            end
        end
    end)

    local tip_lines = (command_id == ITEM_INFO_PROPERTIES_ACTION)
        and UIComponents.GetItemInfoButtonTooltipLines()
        or UIComponents.GetTrackInfoButtonTooltipLines()
    UIComponents.QueueStyledTooltipDelayed(ctx, 'frenkie_info_btn_' .. tostring(command_id), tip_lines, STYLED_TOOLTIP_DELAY_DEFAULT)
end

function UIComponents.RenderTrackInstrumentButton(ctx, icon, track, has_instrument, is_open, on_click)
    local tint = Theme.get('text_white_soft')
    if not has_instrument then
        tint = Theme.get('text_gray')
    elseif not is_open then
        tint = Theme.get('text_gray')
    end

    local button_colors
    if has_instrument then
        button_colors = {
            base = Theme.get('gray_64'),
            hover = Theme.get('gray_80'),
            active = Theme.get('gray_96'),
        }
    else
        button_colors = {
            base = Theme.get('transparent'),
            hover = Theme.get('transparent'),
            active = Theme.get('transparent'),
        }
    end

    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), button_colors.base)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), button_colors.hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), button_colors.active)
    local clicked = r.ImGui_Button(ctx, '##track_instrument', 24)
    r.ImGui_PopStyleColor(ctx, 3)
    UIComponents.DrawImageCenteredInLastItem(ctx, icon, tint, 3)

    if clicked and has_instrument and track ~= nil and on_click then
        on_click()
    end

    local tip_lines
    if track == nil then
        tip_lines = UIComponents.GetSingleTrackOnlyTooltipLines()
    elseif has_instrument then
        tip_lines = UIComponents.GetTrackInstrumentButtonTooltipLines()
    else
        tip_lines = UIComponents.GetTrackInstrumentMissingTooltipLines()
    end

    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local mx, my = r.ImGui_GetMousePos(ctx)
    local inside = mx >= x1 and mx <= x2 and my >= y1 and my <= y2
    local tip_id = 'frenkie_track_instrument_btn_' .. tostring(track and r.GetTrackGUID(track) or 'none')
    UIComponents.QueueStyledTooltipDelayedGeneric(ctx, tip_id, tip_lines, STYLED_TOOLTIP_DELAY_DEFAULT, inside)
end

function UIComponents.PushLabelStateColor(ctx, disabled, is_mixed, is_modified)
    if disabled then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray'))
        return 1
    elseif is_mixed then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('yellow'))
        return 1
    elseif is_modified then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('green_accent'))
        return 1
    end
    return 0
end

function UIComponents.PushTransparentButtonStates(ctx, disabled)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('transparent'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), disabled and Theme.get('transparent') or Theme.get('hover_white_32'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), disabled and Theme.get('transparent') or Theme.get('active_white_64'))
end

function UIComponents.GetFreezeAccentColors(stats)
    if not stats then return nil, nil, nil, false end
    local blue = Theme.get('blue_freeze')
    local yellow = Theme.get('yellow')
    if (stats.track_count == 1 and stats.has) or stats.all_frozen then
        return blue, blue, blue, false
    elseif stats.mixed then
        return yellow, yellow, yellow, true
    end
    return nil, nil, nil, false
end

function UIComponents.DrawHoverActiveOverlay(ctx)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local active = r.ImGui_IsItemActive(ctx)
    if hovered or active then
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local x1, y1 = r.ImGui_GetItemRectMin(ctx)
        local x2, y2 = r.ImGui_GetItemRectMax(ctx)
        local col = active and Theme.get('active_white_64') or Theme.get('hover_white_32')
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, col)
    end
end

function UIComponents.DrawAggregationOutline(ctx, color, rounding, inset)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local col = color or Theme.get('red_hover')
    local rads = rounding or 4
    local pad = inset or 0
    local thickness = 1.0
    r.ImGui_DrawList_AddRect(dl, x1 + pad, y1 + pad, x2 - pad, y2 - pad, col, rads, 0, thickness)
end

return UIComponents
