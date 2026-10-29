-- @noindex
---@diagnostic disable: undefined-global, undefined-field
local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""
package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Theme = require("Theme")
local Utils = require("Utils")

local UIComponents = {}

-- Width of the item value boxes (Rate, Pitch), fixed so controls to their right never shift.
UIComponents.VALUE_BOX_W = 62

-- Icon font: fonts/FIPIcons.ttf, loaded by UI.lua with CreateFontFromFile and handed over via SetIconFont.
-- Glyphs sit in the private use area and are ink-centered in their 1000x1000 cells.
local _icon_font = nil

UIComponents.GLYPH = {
    track = 0xE100, reverse = 0xE101, lock = 0xE102, instrument = 0xE103, reset = 0xE104,
    letter_L = 0xE105, letter_M = 0xE106, eye = 0xE107, eye_off = 0xE108, trash = 0xE109,
    audio = 0xE110, midi = 0xE111, ara = 0xE112, video = 0xE113, videofx = 0xE114,
    click = 0xE115, ltc = 0xE116, subproject = 0xE117, empty = 0xE118, mixed = 0xE119,
    env_lane = 0xE130, env_point = 0xE131, env_razor = 0xE132, env_segment = 0xE133,
}

-- Header columns. The first two buttons of the parameter row use the same widths and gap,
-- so they sit right under the header icon and the track spine in both modes.
UIComponents.HEADER_SLOT_W = 24
UIComponents.HEADER_SLOT_GAP = 7
UIComponents.HEADER_SPINE_W = 24
UIComponents.HEADER_SPINE_GAP = 4
-- The name part starts this far under the number tab, which covers its left rounding (one block).
UIComponents.HEADER_TAB_OVERLAP = 6
-- Text padding of a name field joined to the tab: regular 8 px plus the overlap.
UIComponents.HEADER_JOINED_PAD_X = 8 + UIComponents.HEADER_TAB_OVERLAP

function UIComponents.SetIconFont(font)
    _icon_font = font
end

function UIComponents.GetIconFont()
    return _icon_font
end

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

function UIComponents.RenderPendingTooltip(ctx)
    if _pending_tooltip_lines and #_pending_tooltip_lines > 0 then
        render_styled_tooltip_lines(ctx, _pending_tooltip_lines)
        _pending_tooltip_lines = nil
    end
end

-- Tooltip of a panel the extension draws: it already ran the hover delays; shown like a queued one.
function UIComponents.SetPendingTooltipText(text)
    if text and text ~= '' then _pending_tooltip_lines = split_tooltip_lines(text) end
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

function UIComponents.GetVolumeFaderTooltipLines(target)
    return {
        (target == 'item' and 'Drag — Item Volume (dB)' or 'Drag — Take Volume (dB)'),
        shift_label() .. '+Drag — Fine',
        'Double-Click — Reset',
        alt_label() .. '+Click — Enter Value (dB or -inf)',
        'Reset Button — Unity Gain',
        'Multiple Items — Relative Change',
    }
end

function UIComponents.GetVelocityFaderTooltipLines()
    return {
        'Drag — MIDI Velocity Scale',
        shift_label() .. '+Drag — Fine',
        'Double-Click — Reset',
        alt_label() .. '+Click — Enter Value',
        'Reset Button — 1.00x',
        'Multiple Items — Relative Change',
    }
end

function UIComponents.GetLevelMixedTooltipLines()
    return {
        'Mixed Selection — Audio + MIDI or Empty Items',
        'Select one type to edit Volume or Velocity',
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

local SEPARATOR_PAD = 8

function UIComponents.Separator(ctx, left, right)
    left = left or SEPARATOR_PAD
    right = right or left
    r.ImGui_SameLine(ctx, 0, left)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('pipe_gray'))
    r.ImGui_Text(ctx, "|")
    r.ImGui_PopStyleColor(ctx, 1)
    r.ImGui_SameLine(ctx, 0, right)
end

function UIComponents.DrawGlyphCentered(ctx, x1, y1, w, h, cp, size, col)
    if not _icon_font or not cp then return end
    local s = utf8.char(cp)
    r.ImGui_PushFont(ctx, _icon_font, size)
    local tw, th = r.ImGui_CalcTextSize(ctx, s)
    r.ImGui_PopFont(ctx)
    r.ImGui_DrawList_AddTextEx(r.ImGui_GetWindowDrawList(ctx), _icon_font, size,
        x1 + (w - tw) * 0.5, y1 + (h - th) * 0.5, col, s)
end

function UIComponents.DrawGlyphInLastItem(ctx, cp, size, col)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    UIComponents.DrawGlyphCentered(ctx, x1, y1, x2 - x1, y2 - y1, cp, size, col)
end

-- Height of the header row: the name field frame (padding 8,4).
function UIComponents.HeaderHeight(ctx)
    return r.ImGui_GetTextLineHeight(ctx) + 8
end

-- Track / item kind icon; one fixed slot for every kind so the name never shifts. opts (optional):
-- clickable (hover highlight; returns clicked, hovered — hover counts while a popup is open),
-- badge (color of a dot in the top-right corner).
function UIComponents.HeaderIconSlot(ctx, cp, opts)
    local w, h = UIComponents.HEADER_SLOT_W, UIComponents.HeaderHeight(ctx)
    local clicked, hovered = false, false
    local dl = r.ImGui_GetWindowDrawList(ctx)
    if opts and opts.clickable then
        clicked = r.ImGui_InvisibleButton(ctx, '##fip_header_icon', w, h)
        local active = r.ImGui_IsItemActive(ctx)
        hovered = r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_AllowWhenBlockedByPopup())
        if active or hovered then
            local x1, y1 = r.ImGui_GetItemRectMin(ctx)
            r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x1 + w, y1 + h,
                Theme.get(active and 'active_white_64' or 'hover_white_32'), 4)
        end
    else
        r.ImGui_Dummy(ctx, w, h)
    end
    UIComponents.DrawGlyphInLastItem(ctx, cp, 17, Theme.get('text_white_soft'))
    if opts and opts.badge then
        local x2 = r.ImGui_GetItemRectMax(ctx)
        local _, y1 = r.ImGui_GetItemRectMin(ctx)
        r.ImGui_DrawList_AddCircleFilled(dl, x2 - 4, y1 + 4, 4.5, Theme.get('gray_30'))
        r.ImGui_DrawList_AddCircleFilled(dl, x2 - 4, y1 + 4, 3, opts.badge)
    end
    r.ImGui_SameLine(ctx, 0, UIComponents.HEADER_SLOT_GAP)
    return clicked, hovered
end

-- Track automation (FIP_TrackAutomation*). The badge on the track icon: no dot without envelopes, yellow when
-- some are hidden (automation you cannot see in the arrange), gray when all are bypassed, white otherwise.
UIComponents.AUTOMATION_POPUP = '##fip_track_automation'
local AUTOMATION_NAME_W = 220
-- The list opens when the icon is hovered this long (not when the mouse just passes by) and closes when
-- the mouse has been away from both the icon and the list this long (the gap between them is crossed).
local AUTOMATION_OPEN_DELAY, AUTOMATION_CLOSE_DELAY = 0.12, 0.35
local _automation_hover_since, _automation_away_since = nil, nil

function UIComponents.AutomationBadge(st)
    if (tonumber(st.envs) or 0) == 0 then return nil end
    if (tonumber(st.hidden) or 0) > 0 then return Theme.get('toggle_mixed') end
    if (tonumber(st.active) or 0) == 0 then return Theme.get('text_gray') end
    return Theme.get('text_white_soft')
end

-- Envelope list of the selected tracks, under the track icon (anchor = { x, y, hovered, clicked, has_envs }):
-- it opens on hover when there are envelopes (or on click), eye = show / hide that envelope, name = show it
-- and select it, footer = show all / only active / hide all. The list is read only while it is open.
function UIComponents.TrackAutomationPopup(ctx, anchor)
    local id, now = UIComponents.AUTOMATION_POPUP, r.time_precise()
    if not r.ImGui_IsPopupOpen(ctx, id) then
        _automation_away_since = nil
        _automation_hover_since = (anchor.hovered and anchor.has_envs) and (_automation_hover_since or now) or nil
        if anchor.clicked or (_automation_hover_since and now - _automation_hover_since >= AUTOMATION_OPEN_DELAY) then
            r.ImGui_OpenPopup(ctx, id)
            _automation_hover_since = nil
        end
    end
    r.ImGui_SetNextWindowPos(ctx, anchor.x, anchor.y, r.ImGui_Cond_Appearing())
    if not r.ImGui_BeginPopup(ctx, id) then return end
    local st = Utils.ParseKeyValues(r.FIP_TrackAutomationGetStateStr('', 1))
    local envs = tonumber(st.envs) or 0
    local multi = (tonumber(st.tracks) or 0) > 1
    local gray, white = Theme.get('text_gray'), Theme.get('text_white_soft')
    if envs == 0 then
        r.ImGui_TextColored(ctx, gray, multi and 'No envelopes on the selected tracks' or 'No envelopes on this track')
    end
    local line_h = r.ImGui_GetTextLineHeight(ctx)
    local last_tr
    for i = 1, envs do
        local tr, env = tonumber(st['tr' .. i]) or 0, tonumber(st['env' .. i]) or 0
        if multi and tr ~= last_tr then
            if last_tr then r.ImGui_Spacing(ctx) end
            r.ImGui_TextColored(ctx, gray, (st['trnum' .. (tr + 1)] or '') .. '  ' .. (st['trname' .. (tr + 1)] or ''))
            last_tr = tr
        end
        local vis, act = st['vis' .. i] == '1', st['act' .. i] == '1'
        if r.ImGui_InvisibleButton(ctx, '##fip_env_vis' .. i, 20, line_h) then
            r.FIP_TrackAutomationSetVisible(tr, env, vis and 0 or 1)
        end
        UIComponents.DrawGlyphInLastItem(ctx, vis and UIComponents.GLYPH.eye or UIComponents.GLYPH.eye_off, 14,
            vis and white or gray)
        r.ImGui_SameLine(ctx, 0, 6)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), act and white or gray)
        if r.ImGui_Selectable(ctx, (st['name' .. i] or '?') .. '##fip_env_name' .. i, false, 0, AUTOMATION_NAME_W, 0) then
            r.FIP_TrackAutomationReveal(tr, env)
        end
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_SameLine(ctx, 0, 8)
        local pts, ai = tonumber(st['pts' .. i]) or 0, tonumber(st['ai' .. i]) or 0
        local info = ('%d pt%s'):format(pts, pts == 1 and '' or 's')
        if ai > 0 then info = info .. (', %d AI'):format(ai) end
        if not act then info = info .. ', bypassed' end
        r.ImGui_TextColored(ctx, gray, info)
    end
    if envs > 0 then
        r.ImGui_Separator(ctx)
        if r.ImGui_Button(ctx, 'Show all') then r.FIP_TrackAutomationSetVisible(-1, -1, 1) end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, 'Only active') then r.FIP_TrackAutomationSetVisible(-1, -1, 2) end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, 'Hide all') then r.FIP_TrackAutomationSetVisible(-1, -1, 0) end
    end
    if anchor.hovered or r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_RootAndChildWindows()) then
        _automation_away_since = nil
    else
        _automation_away_since = _automation_away_since or now
        if now - _automation_away_since >= AUTOMATION_CLOSE_DELAY then
            r.ImGui_CloseCurrentPopup(ctx)
            _automation_away_since = nil
        end
    end
    r.ImGui_EndPopup(ctx)
end

-- Track number tab in the track color (or a count for several tracks), rounded on the left only:
-- it is the left end of one block with the track name next to it.
function UIComponents.DrawHeaderTab(ctx, x1, y1, text, bg, fg)
    local w, h = UIComponents.HEADER_SPINE_W, UIComponents.HeaderHeight(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x1 + w, y1 + h, bg, 6, r.ImGui_DrawFlags_RoundCornersLeft())
    local tw, th = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddText(dl, x1 + (w - tw) * 0.5, y1 + (h - th) * 0.5, fg, text)
end

-- Cuts text on UTF-8 character boundaries and adds an ellipsis until it fits max_w.
local function fit_text_end(ctx, text, max_w)
    if r.ImGui_CalcTextSize(ctx, text) <= max_w then return text end
    local n = utf8.len(text)
    if not n then return text end
    for k = n - 1, 1, -1 do
        local cut = text:sub(1, utf8.offset(text, k + 1) - 1) .. '…'
        if r.ImGui_CalcTextSize(ctx, cut) <= max_w then return cut end
    end
    return '…'
end

-- Width of the item mode track block: it starts above N and ends where the Rate box ends in the
-- parameter row (UI.lua: N, |, reset 24, |, "Rate:" 40 + 2, value box). It depends only on the font,
-- so the item name bar never shifts.
local function header_track_block_w(ctx)
    local sep_w = SEPARATOR_PAD * 2 + r.ImGui_CalcTextSize(ctx, '|')
    return UIComponents.HEADER_SPINE_W + sep_w + 24 + sep_w + 40 + 2 + UIComponents.VALUE_BOX_W
end

-- Item mode: the item's track as one fixed-width block, number tab + "‹ Name" (back up to the track). A click anywhere on it
-- returns true (the caller switches to track mode).
function UIComponents.HeaderTrackBlock(ctx, number_text, tab_bg, tab_fg, name)
    local h = UIComponents.HeaderHeight(ctx)
    local tab_w = UIComponents.HEADER_SPINE_W
    local name_w = header_track_block_w(ctx) - tab_w
    local clicked = r.ImGui_InvisibleButton(ctx, '##fip_track_block', tab_w + name_w, h)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local active, hovered = r.ImGui_IsItemActive(ctx), r.ImGui_IsItemHovered(ctx)
    local name_bg = active and Theme.get('gray_74') or (hovered and Theme.get('gray_58') or Theme.get('gray_42'))
    r.ImGui_DrawList_AddRectFilled(dl, x1 + tab_w - UIComponents.HEADER_TAB_OVERLAP, y1, x1 + tab_w + name_w, y1 + h,
        name_bg, 6, r.ImGui_DrawFlags_RoundCornersRight())
    UIComponents.DrawHeaderTab(ctx, x1, y1, number_text, tab_bg, tab_fg)
    if active or hovered then
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x1 + tab_w, y1 + h,
            Theme.get(active and 'active_white_64' or 'hover_white_32'), 6, r.ImGui_DrawFlags_RoundCornersLeft())
    end
    local arrow = '‹  ' -- back up to the track
    local label = arrow .. fit_text_end(ctx, name or '', name_w - 16 - r.ImGui_CalcTextSize(ctx, arrow))
    local _, th = r.ImGui_CalcTextSize(ctx, label)
    r.ImGui_DrawList_AddText(dl, x1 + tab_w + 8, y1 + (h - th) * 0.5, Theme.get('text_white_soft'), label)
    r.ImGui_SameLine(ctx, 0, UIComponents.HEADER_SPINE_GAP)
    return clicked
end

-- Item textures, one per item kind; each draws inside [x0, x2] x [y1, y2] (the caller clips).
local ITEM_PATTERNS = {}

function ITEM_PATTERNS.audio(dl, x0, x2, y1, y2, col) -- waveform
    local cy = (y1 + y2) * 0.5
    for x = x0, x2, 3 do
        local u = x - x0
        local a = (math.abs(math.sin(u * 0.13)) * 0.6 + math.abs(math.sin(u * 0.047)) * 0.4) * (y2 - y1) * 0.36
        r.ImGui_DrawList_AddLine(dl, x, cy - a, x, cy + a, col, 1)
    end
end

function ITEM_PATTERNS.midi(dl, x0, x2, y1, y2, col) -- piano roll: chords and single notes
    local rows = 6
    local step = (y2 - y1 - 6) / (rows - 1)
    local x, i = x0, 0
    while x < x2 do
        local len = 8 + (i * 5) % 10
        local root = (i * 3 + i // 2) % 3
        local voices = (i % 3 == 2) and 1 or (2 + i % 2)
        for v = 0, voices - 1 do
            local y = y2 - 3 - (root + v * 2) % rows * step
            r.ImGui_DrawList_AddLine(dl, x, y, x + len, y, col, 2)
        end
        x = x + len + 4
        i = i + 1
    end
end

function ITEM_PATTERNS.ara(dl, x0, x2, y1, y2, col) -- Melodyne-like blobs at different pitches
    local x, i = x0, 0
    while x < x2 do
        local len = 14 + (i * 9) % 18
        local cy = y1 + 6 + ((i * 5 + i // 2) % 4) * (y2 - y1 - 12) / 3
        for dx = 0, len, 2 do
            local a = math.sin(math.pi * dx / len) * 3.5 + 0.5
            r.ImGui_DrawList_AddLine(dl, x + dx, cy - a, x + dx, cy + a, col, 1)
        end
        x = x + len + 6
        i = i + 1
    end
end

function ITEM_PATTERNS.video(dl, x0, x2, y1, y2, col) -- film strip
    for x = x0, x2, 6 do
        r.ImGui_DrawList_AddRectFilled(dl, x, y1 + 2, x + 3, y1 + 4, col)
        r.ImGui_DrawList_AddRectFilled(dl, x, y2 - 4, x + 3, y2 - 2, col)
    end
    for x = x0, x2, 24 do
        r.ImGui_DrawList_AddLine(dl, x, y1 + 6, x, y2 - 6, col, 1)
    end
end

function ITEM_PATTERNS.videofx(dl, x0, x2, y1, y2, col) -- frames with scan lines
    for y = y1 + 4, y2 - 4, 3 do
        r.ImGui_DrawList_AddLine(dl, x0, y, x2, y, col, 1)
    end
    for x = x0, x2, 24 do
        r.ImGui_DrawList_AddLine(dl, x, y1 + 2, x, y2 - 2, col, 2)
    end
end

function ITEM_PATTERNS.click(dl, x0, x2, y1, y2, col) -- beat ticks, every 4th taller
    local i = 0
    for x = x0, x2, 8 do
        local downbeat = (i % 4 == 0)
        local inset = downbeat and 3 or (y2 - y1) * 0.32
        r.ImGui_DrawList_AddLine(dl, x, y1 + inset, x, y2 - inset, col, downbeat and 2 or 1)
        i = i + 1
    end
end

function ITEM_PATTERNS.ltc(dl, x0, x2, y1, y2, col) -- bi-phase timecode square wave
    local hi, lo = y1 + 5, y2 - 5
    local bits = { 1, 0, 0, 1, 1, 0, 1, 0, 0, 0, 1, 1, 0, 1 }
    local y, x, i, cell = hi, x0, 0, 8
    local function flip(at)
        local ny = (y == hi) and lo or hi
        r.ImGui_DrawList_AddLine(dl, at, y, at, ny, col, 1)
        y = ny
    end
    while x < x2 do
        flip(x)
        if bits[i % #bits + 1] == 1 then
            r.ImGui_DrawList_AddLine(dl, x, y, x + cell / 2, y, col, 1)
            flip(x + cell / 2)
            r.ImGui_DrawList_AddLine(dl, x + cell / 2, y, x + cell, y, col, 1)
        else
            r.ImGui_DrawList_AddLine(dl, x, y, x + cell, y, col, 1)
        end
        x = x + cell
        i = i + 1
    end
end

function ITEM_PATTERNS.subproject(dl, x0, x2, y1, y2, col) -- mini tracks with item blocks
    local lanes = 3
    local lh = (y2 - y1 - 6) / lanes
    for l = 0, lanes - 1 do
        local y = y1 + 3 + l * lh
        local x, i = x0 + (l * 9) % 17, l
        while x < x2 do
            local len = 14 + (i * 17) % 26
            r.ImGui_DrawList_AddRectFilled(dl, x, y + 1, x + len, y + lh - 1, col, 1)
            x = x + len + 6 + (i * 7) % 12
            i = i + 1
        end
    end
end

function ITEM_PATTERNS.empty(dl, x0, x2, y1, y2, col) -- diagonal hatching
    local h = y2 - y1
    for x = x0 - h, x2, 7 do
        r.ImGui_DrawList_AddLine(dl, x, y2, x + h, y1, col, 1)
    end
end

-- Texture of the item kind over the last item (the name bar). The pattern is anchored to the bar's left
-- edge, so it never moves between items; the name masks it and the texture shows from just after the name.
function UIComponents.DrawItemTexture(ctx, kind, text, col)
    local pattern = ITEM_PATTERNS[kind]
    if not pattern then return end
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local origin, x_end = x1, x2 - 8
    local visible_from = x1 + 8 + r.ImGui_CalcTextSize(ctx, text or '') + 16
    if visible_from >= x_end then return end
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_PushClipRect(dl, visible_from, y1, x_end, y2, true)
    pattern(dl, origin, x_end, y1, y2, col)
    r.ImGui_DrawList_PopClipRect(dl)
end

-- Item info line (FIP_ItemInfoGetStateStr): REAPER's mouse editing help for the selected or edited item,
-- right-aligned in the rest of the current row. Each value gets a column as wide as its text with every
-- digit set to 8, so the line does not jitter while dragging. When the full line does not fit, values drop
-- the secondary time unit; when that does not fit either, the line is hidden.
local INFO_INNER_GAP, INFO_FIELD_GAP, INFO_MIN_GAP = 4, 12, 16

local function info_cell_w(ctx, text)
    if text == '' then return 0 end
    return (r.ImGui_CalcTextSize(ctx, (text:gsub('%d', '8'))))
end

function UIComponents.ItemInfoLine(ctx, raw)
    local st = Utils.ParseKeyValues(raw)
    local n = tonumber(st.n) or 0
    if n == 0 then return end
    local fields = {}
    for i = 1, n do
        local d, e = st['d' .. i] or '', st['e' .. i] or ''
        fields[i] = {
            label = (st['l' .. i] or '') .. ':',
            full = { st['v' .. i] or '', d ~= '' and ('[' .. d .. ']') or '' },
            short = { st['s' .. i] or '', e ~= '' and ('[' .. e .. ']') or '' },
        }
    end
    local function width(form)
        local w = 0
        for i, f in ipairs(fields) do
            local v = f[form]
            w = w + (i > 1 and INFO_FIELD_GAP or 0) + r.ImGui_CalcTextSize(ctx, f.label) + INFO_INNER_GAP + info_cell_w(ctx, v[1])
            if v[2] ~= '' then w = w + INFO_INNER_GAP + info_cell_w(ctx, v[2]) end
        end
        return w
    end
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local room = r.ImGui_GetContentRegionAvail(ctx) - INFO_MIN_GAP
    local form, w = 'full', width('full')
    if w > room then form, w = 'short', width('short') end
    if w > room then return end

    local dl = r.ImGui_GetWindowDrawList(ctx)
    local _, pad_y = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())
    local cx, ty = x + INFO_MIN_GAP + room - w, y + pad_y
    local label_col, value_col, delta_col = Theme.get('text_gray'), Theme.get('text_white_soft'), Theme.get('green_accent')
    for i, f in ipairs(fields) do
        local v = f[form]
        if i > 1 then cx = cx + INFO_FIELD_GAP end
        r.ImGui_DrawList_AddText(dl, cx, ty, label_col, f.label)
        cx = cx + r.ImGui_CalcTextSize(ctx, f.label) + INFO_INNER_GAP
        r.ImGui_DrawList_AddText(dl, cx, ty, value_col, v[1])
        cx = cx + info_cell_w(ctx, v[1])
        if v[2] ~= '' then
            cx = cx + INFO_INNER_GAP
            r.ImGui_DrawList_AddText(dl, cx, ty, delta_col, v[2])
            cx = cx + info_cell_w(ctx, v[2])
        end
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

function UIComponents.StyledInputCommon(ctx, label, hint_text, value, width, bar_color, use_hint, pad_x)
    bar_color = bar_color or Theme.get('gray_64')
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), bar_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), bar_color)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), pad_x or 8, 4)
    if width then
        r.ImGui_SetNextItemWidth(ctx, width)
    end
    local changed, new_value
    if use_hint then
        changed, new_value = r.ImGui_InputTextWithHint(ctx, label, hint_text or '', value, r.ImGui_InputTextFlags_None())
    else
        changed, new_value = r.ImGui_InputText(ctx, label, value, r.ImGui_InputTextFlags_AutoSelectAll())
    end
    local deactivated = Utils.ReturnFocusOnDeactivation(ctx)
    r.ImGui_PopStyleVar(ctx, 2)
    r.ImGui_PopStyleColor(ctx, 2)
    return changed, new_value, deactivated
end

function UIComponents.StyledInput(ctx, label, value, width, bar_color, pad_x)
    return UIComponents.StyledInputCommon(ctx, label, nil, value, width, bar_color, false, pad_x)
end

function UIComponents.MultiItemInput(ctx, label, hint_text, value, width, bar_color, pad_x)
    return UIComponents.StyledInputCommon(ctx, label, hint_text, value, width, bar_color, true, pad_x)
end

-- Vol/Vel numeric box, styled like the pitch box: neutral text, reports per-frame horizontal mouse movement.
-- id must start with '##' so the item keeps its identity while the text changes.
-- disabled: dimmed and inert (Mixed selection); returns is_hovered only.
-- The value changes while it is dragged, so the ID must not depend on it: ImGui hashes the whole label for
-- "text##id" and only the part after "###" for "text###id". A changing ID would end the drag after one step.
function UIComponents.LevelBox(ctx, id, text, width, disabled)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('gray_42'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('gray_58'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('gray_74'))
    if disabled then r.ImGui_BeginDisabled(ctx, true) end
    r.ImGui_Button(ctx, text .. (id:sub(1, 3) == '###' and id or ('#' .. id)), width)
    if disabled then r.ImGui_EndDisabled(ctx) end
    r.ImGui_PopStyleColor(ctx, 3)
    if disabled then
        return r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_AllowWhenDisabled())
    end

    local activated = r.ImGui_IsItemActivated(ctx)
    local active = r.ImGui_IsItemActive(ctx)
    local deactivated = Utils.ReturnFocusOnDeactivation(ctx)
    local alt_clicked = is_last_item_alt_clicked(ctx)
    local dbl_clicked = r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0)
    local dx = 0
    if active then
        dx = r.ImGui_GetMouseDelta(ctx)
    end
    return activated, active, deactivated, dx, alt_clicked, dbl_clicked
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
    local deactivated = Utils.ReturnFocusOnDeactivation(ctx)
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

-- Tri-state toggle: colored square with a glyph (on / mixed / off colors from Theme toggle_*).
-- Returns changed, new_state; clicking a mixed toggle turns it on.
function UIComponents.GlyphToggle(ctx, id, cp, on_color, state, is_mixed, size)
    size = size or 20
    local mixed = (state == nil and is_mixed)
    local current = mixed and false or (state or false)
    local clicked = r.ImGui_InvisibleButton(ctx, id, size, size)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local bg = mixed and Theme.get('toggle_mixed') or (current and on_color or Theme.get('toggle_off'))
    r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x1 + size, y1 + size, bg, 3)
    if r.ImGui_IsItemActive(ctx) then
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x1 + size, y1 + size, Theme.get('active_white_64'), 3)
    elseif r.ImGui_IsItemHovered(ctx) then
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x1 + size, y1 + size, Theme.get('hover_white_32'), 3)
    end
    local fg = (mixed or current) and Theme.get('black') or Theme.get('toggle_off_symbol')
    UIComponents.DrawGlyphCentered(ctx, x1, y1, size, size, cp, 13, fg)
    if clicked then
        return true, mixed and true or not current
    end
    return false, mixed and nil or current
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

-- Up to 6 decimals of the rate (3 in the x1000 display below 1), trailing zeros dropped.
-- Boxes shorten long values in the middle (FitTextMiddle), so nothing is rounded away.
function UIComponents.FormatRateDisplayValue(rate)
    local display = UIComponents.RateToDisplayValue(rate)
    local text = string.format(display < 0 and '%.3f' or '%.6f', display)
    return (text:gsub('0+$', ''):gsub('%.$', ''))
end

-- Shortens text in the middle ("1.05…3") so its start and end both stay visible within max_w.
function UIComponents.FitTextMiddle(ctx, text, max_w)
    if r.ImGui_CalcTextSize(ctx, text) <= max_w then return text end
    local suffix = text:sub(-1)
    for n = #text - 2, 1, -1 do
        local candidate = text:sub(1, n) .. '…' .. suffix
        if r.ImGui_CalcTextSize(ctx, candidate) <= max_w then return candidate end
    end
    return text:sub(1, 1) .. '…' .. suffix
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
            Utils.DeferReturnFocus()
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
            Utils.DeferReturnFocus()
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
    local w = width or UIComponents.VALUE_BOX_W
    local pad_x = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())
    text = UIComponents.FitTextMiddle(ctx, text, w - pad_x * 2 - r.ImGui_CalcTextSize(ctx, ' '))
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
            Utils.DeferReturnFocus()
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
            Utils.DeferReturnFocus()
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

function UIComponents.RenderInfoButton(ctx, command_id, width)
    UIComponents.StyledButton(ctx, 'i', width or 18, function()
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

function UIComponents.RenderTrackInstrumentButton(ctx, track, has_instrument, is_open, on_click)
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
    UIComponents.DrawGlyphInLastItem(ctx, UIComponents.GLYPH.instrument, 15, tint)

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

local _ltp_drag_state = {}

-- Fixed width so the docked widget never grows.
local LTP_BOX_W = 224

function UIComponents.GetLastTouchedParamTooltipLines()
    return {
        'Last Touched Parameter',
        'Drag — Change Value',
        shift_label() .. '+Drag — Fine',
        'Double-Click — Default Value',
        cmd_label() .. '+Click — Show Envelope',
    }
end

function UIComponents.GetLastTouchedParamEmptyTooltipLines()
    return { 'No parameter touched on this track yet' }
end

--- Last Touched Parameter box: "FX · Param" on the left, value on the right.
--- Drag vertically to change the value (Shift = fine), double-click = default, Cmd/Ctrl+click = envelope.
function UIComponents.RenderLastTouchedParamBox(ctx, info, font, on_value_change, on_value_end, on_automate)
    local has = info ~= nil
    r.ImGui_PushID(ctx, 'fip_ltp_box')
    local h = r.ImGui_GetFrameHeight(ctx)
    r.ImGui_InvisibleButton(ctx, '##ltp', LTP_BOX_W, h)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local active = has and r.ImGui_IsItemActive(ctx)
    local hovered = has and r.ImGui_IsItemHovered(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local bg = active and Theme.get('gray_74') or (hovered and Theme.get('gray_58') or Theme.get('gray_42'))
    r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, bg, 4)

    local pad = 8
    local value = has and (info.formatted or '') or ''
    local vw = (value ~= '') and r.ImGui_CalcTextSize(ctx, value) or 0
    local name = has and ((info.fx_name or '') .. ' · ' .. (info.param_name or '')) or 'No parameter'
    local _, th = r.ImGui_CalcTextSize(ctx, name)
    local ty = y1 + (h - th) * 0.5
    r.ImGui_DrawList_PushClipRect(dl, x1 + pad, y1, x2 - pad - (vw > 0 and vw + 8 or 0), y2, true)
    r.ImGui_DrawList_AddText(dl, x1 + pad, ty, has and Theme.get('text_white_soft') or Theme.get('text_gray'), name)
    r.ImGui_DrawList_PopClipRect(dl)
    if vw > 0 then
        r.ImGui_DrawList_PushClipRect(dl, x1 + pad, y1, x2 - pad, y2, true)
        r.ImGui_DrawList_AddText(dl, x2 - pad - vw, ty, Theme.get('text_white_soft'), value)
        r.ImGui_DrawList_PopClipRect(dl)
    end

    if has then
        local id_key = 'ltp_val'
        local mods = r.ImGui_GetKeyMods(ctx)
        local cmd_held = (mods & r.ImGui_Mod_Super()) ~= 0 or (mods & r.ImGui_Mod_Ctrl()) ~= 0
        if r.ImGui_IsItemActivated(ctx) then
            _ltp_drag_state.automate_click = cmd_held
            if cmd_held and on_automate then on_automate() end
        end

        local changed = false
        local new_value = info.value or 0
        local min_val = info.min_val or 0
        local max_val = info.max_val or 1
        local range = max_val - min_val
        if range <= 0 then range = 1 end

        if active and not _ltp_drag_state.automate_click then
            local state = _ltp_drag_state[id_key]
            if not state then
                _ltp_drag_state[id_key] = { start = new_value }
                state = _ltp_drag_state[id_key]
            end
            local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
            local speed = range / 200.0
            local shift = (mods & r.ImGui_Mod_Shift()) ~= 0
            if shift then speed = speed * 0.05 end
            local v = state.start + (-dy) * speed
            if v < min_val then v = min_val end
            if v > max_val then v = max_val end
            if v ~= new_value then
                new_value = v
                changed = true
            end
        end

        if hovered and r.ImGui_IsMouseDoubleClicked(ctx, 0) and info.default_value ~= nil then
            new_value = info.default_value
            changed = true
        end

        if changed and on_value_change then
            _ltp_drag_state._dirty = true
            on_value_change(new_value)
        end

        local deactivated = Utils.ReturnFocusOnDeactivation(ctx)
        if deactivated then
            _ltp_drag_state[id_key] = nil
            _ltp_drag_state.automate_click = false
            if _ltp_drag_state._dirty then
                _ltp_drag_state._dirty = false
                if on_value_end then on_value_end() end
            end
        end
        UIComponents.QueueStyledTooltipDelayed(ctx, 'fip_ltp_box_tt',
            UIComponents.GetLastTouchedParamTooltipLines(), STYLED_TOOLTIP_DELAY_DEFAULT)
    else
        UIComponents.QueueStyledTooltipDelayed(ctx, 'fip_ltp_box_tt',
            UIComponents.GetLastTouchedParamEmptyTooltipLines(), STYLED_TOOLTIP_DELAY_DEFAULT)
    end

    r.ImGui_PopID(ctx)
end

return UIComponents
