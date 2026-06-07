-- @noindex

local r = reaper

if not r.ImGui_CreateContext then
  if r.ShowMessageBox then
    r.ShowMessageBox("ReaImGui not found. Install it via ReaPack.", "Frenkie Transient UI", 0)
  end
  return
end

-- JSON config path (shared via REAPER resource path)
local config_dir = r.GetResourcePath() .. "/Scripts/Mr. Frenkie Scripts/Audio Editing/Transient Detector"
reaper.RecursiveCreateDirectory(config_dir, 0)
local json_path = config_dir .. "/reaper_frenkie_TransientDetector.json"

local function default_config()
  return {
    low_cut = 199.0,
    high_cut = 20000.0,
    filter_gain = 3.6,
    threshold = -37.0,
    sensitivity = 6.4,
    retrig = 30.0,
    reduce = 52,
  }
end

local function read_json_config()
  local f = io.open(json_path, "r")
  if not f then return default_config() end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then return default_config() end

  local cfg = default_config()

  local function extract(key)
    local escaped = key:gsub("([%.%+%-%*%?%[%]%(%)%^%$%%])", "%%%1")
    local pat = '"' .. escaped .. '"%s*:%s*([%-%d%.]+)'
    local val = content:match(pat)
    return val and tonumber(val)
  end
  local function extract_bool(key)
    local escaped = key:gsub("([%.%+%-%*%?%[%]%(%)%^%$%%])", "%%%1")
    local bool_pat = '"' .. escaped .. '"%s*:%s*([%a]+)'
    local bool_val = content:match(bool_pat)
    if bool_val then
      local l = bool_val:lower()
      if l == "true" then return true end
      if l == "false" then return false end
    end
    local num_pat = '"' .. escaped .. '"%s*:%s*([%-%d%.]+)'
    local num_val = content:match(num_pat)
    if num_val then
      return (tonumber(num_val) or 0) ~= 0
    end
    return nil
  end

  cfg.low_cut         = extract("Low Cut")         or cfg.low_cut
  cfg.high_cut        = extract("High Cut")        or cfg.high_cut
  cfg.filter_gain     = extract("Gain")            or cfg.filter_gain
  cfg.threshold       = extract("Threshold")       or cfg.threshold
  cfg.sensitivity     = extract("Sensivity")       or cfg.sensitivity
  cfg.retrig          = extract("Retrig")          or cfg.retrig
  cfg.reduce          = extract("Reduce")          or cfg.reduce

  if cfg.low_cut < 0 then cfg.low_cut = 0 end
  if cfg.high_cut <= 0 then cfg.high_cut = 20000 end
  if cfg.high_cut < cfg.low_cut then cfg.low_cut, cfg.high_cut = cfg.high_cut, cfg.low_cut end
  if cfg.sensitivity < 1 then cfg.sensitivity = 1 elseif cfg.sensitivity > 10 then cfg.sensitivity = 10 end
  if cfg.reduce < 1 then cfg.reduce = 1 end

  return cfg
end

local function write_json_config(cfg)
  local f = io.open(json_path, "w")
  if not f then return end
  f:write("{\n")
  f:write(string.format("  \"Low Cut\": %.1f,\n", cfg.low_cut))
  f:write(string.format("  \"High Cut\": %.1f,\n", cfg.high_cut))
  f:write(string.format("  \"Gain\": %.1f,\n", cfg.filter_gain))
  f:write(string.format("  \"Threshold\": %.1f,\n", cfg.threshold))
  f:write(string.format("  \"Sensivity\": %.1f,\n", cfg.sensitivity))
  f:write(string.format("  \"Retrig\": %.1f,\n", cfg.retrig))
  f:write(string.format("  \"Reduce\": %d\n", math.floor(cfg.reduce)))
  f:write("}\n")
  f:close()
end

local ext_cmd_id = nil
local slice_cmd_id = nil

local function resolve_cmd(name, cache)
  if cache then return cache end
  local cmd = r.NamedCommandLookup("_" .. name)
  if cmd and cmd ~= 0 then return cmd end
  cmd = r.NamedCommandLookup(name)
  if cmd and cmd ~= 0 then return cmd end
  return nil
end

local function trigger_extension()
  ext_cmd_id = resolve_cmd("FrenkieStretchMarkers", ext_cmd_id)
  if not ext_cmd_id then
    -- extension not found, silently skip
    return false
  end
  r.Main_OnCommand(ext_cmd_id, 0)
  return true
end

local function trigger_slice()
  slice_cmd_id = resolve_cmd("FrenkieSliceToTransients", slice_cmd_id)
  if not slice_cmd_id then
    return false
  end
  r.Main_OnCommand(slice_cmd_id, 0)
  return true
end

local function dbg(msg)
  -- r.ShowConsoleMsg(tostring(msg) .. "\n")
end

-- Load peaks for the visible range at screen resolution (1 peak per pixel)
local function build_view_peaks(take, view_start, view_len, num_pixels)
  if num_pixels < 2 or view_len <= 0 then return nil end
  local peakrate = num_pixels / view_len
  local buf = r.new_array(num_pixels * 2)
  buf.clear()
  local retval = r.GetMediaItemTake_Peaks(take, peakrate, view_start, 1, num_pixels, 0, buf)
  local spl_cnt = retval & 0xfffff
  if spl_cnt <= 0 then return nil end
  local maxs = {}
  local mins = {}
  for i = 1, spl_cnt do
    maxs[i] = buf[i]
    mins[i] = buf[num_pixels + i]
  end
  for i = spl_cnt + 1, num_pixels do
    maxs[i] = 0
    mins[i] = 0
  end
  return { maxs = maxs, mins = mins, count = num_pixels }
end

local function detect_transients(item_start)
  if not r.FrenkieDetectTransients then return {} end
  local csv = r.FrenkieDetectTransients()
  if not csv or csv == "" then return {} end
  local markers = {}
  for val in csv:gmatch("[^,]+") do
    local t = tonumber(val)
    if t then
      markers[#markers + 1] = item_start + t
    end
  end
  return markers
end

-- Colors
local COL = {
  text_muted = 0xB0B0B0FF,
  text = 0xD0D0D0FF,
  accent = 0x26A69AFF,
  bg_window = 0x1E1E1EFF,
  bg_title = 0x2D2D2DFF,
  bg_title_active = 0x3D3D3DFF,
  frame_bg = 0x2A2A2AFF,
  frame_bg_hovered = 0x3A3A3AFF,
  frame_bg_active = 0x4A4A4AFF,
  button_bg = 0x404040FF,
  button_bg_hover = 0x505050FF,
  button_bg_active = 0x606060FF,
  border = 0x404040FF,
  border_shadow = 0x00000080,
  scrollbar_bg = 0x00000010,
  scrollbar_grab = 0x8A8A8A40,
  scrollbar_grab_hovered = 0x9A9A9A70,
  scrollbar_grab_active = 0xAAAAAA90,
  resize_grip = 0x50505080,
  resize_grip_hovered = 0x707070C0,
  resize_grip_active = 0x909090FF,
  table_row_bg = 0x00000000,
  table_row_bg_alt = 0x00000022,
  header_hover = 0x50505040,
  header_active = 0x60606060,
  timeline_bg_enabled = 0x30303080,
  project_missing_text = 0xFF4040FF,
  playhead_marker = 0xCC6600FF,
}

local function apply_frp_style(ctx)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 4)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 8)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 3)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), COL.bg_window)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), COL.bg_title)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), COL.bg_title_active)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COL.frame_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), COL.frame_bg_hovered)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), COL.frame_bg_active)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL.button_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COL.button_bg_hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COL.button_bg_active)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL.text)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), COL.accent)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), COL.button_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), COL.header_hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), COL.header_active)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TableRowBg(), COL.table_row_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TableRowBgAlt(), COL.table_row_bg_alt)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), COL.border)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_BorderShadow(), COL.border_shadow)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarBg(), COL.scrollbar_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrab(), COL.scrollbar_grab)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabHovered(), COL.scrollbar_grab_hovered)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabActive(), COL.scrollbar_grab_active)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGrip(), COL.resize_grip)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGripHovered(), COL.resize_grip_hovered)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGripActive(), COL.resize_grip_active)
end

local function pop_frp_style(ctx)
  r.ImGui_PopStyleColor(ctx, 25)
  r.ImGui_PopStyleVar(ctx, 6)
end

-- ImGui context (must be created before functions that reference ctx)
local ctx = r.ImGui_CreateContext("Frenkie Transient UI")
local font = r.ImGui_CreateFont("Arial", 14)
r.ImGui_Attach(ctx, font)

-- Slider styling
local defaults = default_config()
local COL_LABEL_MOD = 0x995500FF

local SLIDER_GRAB = {
  { 0x3A8888FF, 0x50AAAAFF },  -- 1: Low Cut: teal
  { 0x4A6A9AFF, 0x6088BBFF },  -- 2: High Cut: steel blue
  { 0x6A4A8AFF, 0x8866AAFF },  -- 3: Gain: purple
  { 0x8A4040FF, 0xAA5555FF },  -- 4: Threshold: red
  { 0x4A7A4AFF, 0x66996BFF },  -- 5: Sensitivity: green
  { 0x8A7030FF, 0xAA8844FF },  -- 6: Retrig: amber
  { 0x8A5040FF, 0xAA6655FF },  -- 7: Reduce: salmon
}

local function styled_slider(label, value, v_min, v_max, fmt, default_val, grab_idx)
  local is_mod = math.abs(value - default_val) > 0.01
  local n_pop = 2
  if is_mod then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL_LABEL_MOD)
    n_pop = 3
  end
  local gc = SLIDER_GRAB[grab_idx]
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), gc[1])
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), gc[2])

  -- NoInput flag prevents double-click from opening text-input mode
  local flags = r.ImGui_SliderFlags_NoInput()
  local _, new_val = r.ImGui_SliderDouble(ctx, label, value, v_min, v_max, fmt, flags)
  local released = r.ImGui_IsItemDeactivatedAfterEdit(ctx)

  -- Double-click to reset to default
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    new_val = default_val
    released = true
  end

  r.ImGui_PopStyleColor(ctx, n_pop)
  return new_val, released
end

local cfg = read_json_config()
local last_item_key = ""
local last_proj_change = -1
local last_item_fingerprint = ""
local item_start_g = 0
local item_len_g = 0
local wave_zoom = 1.0
local wave_scroll = 0.0
local preview_markers = {}

local function draw()
  r.ImGui_SetNextWindowSize(ctx, 520, 480, r.ImGui_Cond_FirstUseEver())
  apply_frp_style(ctx)
  local window_flags = r.ImGui_WindowFlags_NoDocking()
  if r.ImGui_WindowFlags_NoScrollbar then
    window_flags = window_flags | r.ImGui_WindowFlags_NoScrollbar()
  end
  local visible, open = r.ImGui_Begin(ctx, "Transient Detector", true, window_flags)

  if visible then
    local need_detect = false
    local val, rel

    r.ImGui_TextWrapped(ctx,
      "Bandpass, rectifier, envelope follower — teal overlay matches this detector.")
    r.ImGui_Spacing(ctx)

    val, rel = styled_slider("Low Cut", cfg.low_cut, 20.0, 2000.0, "%.0f Hz", defaults.low_cut, 1)
    cfg.low_cut = val; if rel then need_detect = true end

    val, rel = styled_slider("High Cut", cfg.high_cut, 1000.0, 20000.0, "%.0f Hz", defaults.high_cut, 2)
    cfg.high_cut = val; if rel then need_detect = true end

    val, rel = styled_slider("Gain", cfg.filter_gain, 0.0, 20.0, "%.1f dB", defaults.filter_gain, 3)
    cfg.filter_gain = val; if rel then need_detect = true end

    val, rel = styled_slider("Threshold", cfg.threshold, -60.0, 0.0, "%.1f dB", defaults.threshold, 4)
    cfg.threshold = val; if rel then need_detect = true end

    val, rel = styled_slider("Sensitivity", cfg.sensitivity, 1.0, 10.0, "%.1f", defaults.sensitivity, 5)
    cfg.sensitivity = val; if rel then need_detect = true end

    val, rel = styled_slider("Retrig", cfg.retrig, 1.0, 200.0, "%.0f ms", defaults.retrig, 6)
    cfg.retrig = val; if rel then need_detect = true end

    val, rel = styled_slider("Reduce", cfg.reduce + 0.0, 1.0, 500.0, "%.0f", defaults.reduce + 0.0, 7)
    cfg.reduce = math.floor(val + 0.5); if rel then need_detect = true end

    if need_detect then
      write_json_config(cfg)
      local sel_item = r.GetSelectedMediaItem(0, 0)
      if sel_item then
        local sel_start = r.GetMediaItemInfo_Value(sel_item, "D_POSITION")
        preview_markers = detect_transients(sel_start)
      end
    end

    r.ImGui_Spacing(ctx)
    if r.ImGui_Button(ctx, "Stretch Markers") then
      write_json_config(cfg)
      trigger_extension()
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Slice") then
      write_json_config(cfg)
      trigger_slice()
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Debug → console") then
      if r.ShowConsoleMsg and r.FrenkieTransient_GetLastDebugReport then
        local s = r.FrenkieTransient_GetLastDebugReport()
        if s and s ~= "" then
          r.ShowConsoleMsg(tostring(s) .. "\n")
        else
          r.ShowConsoleMsg("(no debug — run preview or detection first)\n")
        end
      end
    end

    r.ImGui_Separator(ctx)

    -- Item and waveform display
    local item = r.GetSelectedMediaItem(0, 0)
    local item_key = item and tostring(item) or ""

    if not item then
      r.ImGui_TextColored(ctx, COL.project_missing_text, "No item selected")
    else
      local take = r.GetActiveTake(item)
      if not take or r.TakeIsMIDI(take) then
        r.ImGui_TextColored(ctx, COL.project_missing_text, "No audio take")
      else
        -- Re-detect on item change or item property change
        local proj_change = r.GetProjectStateChangeCount(0)
        local i_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local i_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        local i_rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
        local i_offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
        local fingerprint = string.format("%.6f_%.6f_%.6f_%.6f", i_start, i_len, i_rate, i_offs)

        if item_key ~= last_item_key then
          wave_zoom = 1.0
          wave_scroll = 0.0
          item_start_g = i_start
          item_len_g = i_len
          preview_markers = detect_transients(i_start)
          last_item_key = item_key
          last_item_fingerprint = fingerprint
          last_proj_change = proj_change
        elseif proj_change ~= last_proj_change then
          item_start_g = i_start
          item_len_g = i_len
          last_proj_change = proj_change
          if fingerprint ~= last_item_fingerprint then
            last_item_fingerprint = fingerprint
            preview_markers = detect_transients(i_start)
          end
        end

        -- Info (extension debug: use button "Debug → console" or REAPER Actions → Transient Detector debug)
        local _, take_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        local info_line = string.format("%s  |  Detected: %d", take_name or "", #preview_markers)
        r.ImGui_Text(ctx, info_line)

        -- Canvas
        if item_len_g > 0 then
          r.ImGui_Spacing(ctx)
          local pad = 8
          r.ImGui_Indent(ctx, pad)
          local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
          local canvas_w = math.max(10, avail_w - pad)
          local canvas_h = math.max(60, avail_h - pad)

          r.ImGui_InvisibleButton(ctx, "##waveform_canvas", canvas_w, canvas_h)
          local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
          local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
          local draw_list = r.ImGui_GetWindowDrawList(ctx)

          local item_end = item_start_g + item_len_g

          -- Zoom and scroll
          if wave_zoom < 1.0 then wave_zoom = 1.0 end
          if wave_zoom > 64.0 then wave_zoom = 64.0 end
          local vis_len = item_len_g / wave_zoom
          if vis_len > item_len_g then vis_len = item_len_g end
          local max_scroll = math.max(0.0, item_len_g - vis_len)
          if max_scroll <= 0.0 then
            wave_scroll = 0.0
          else
            if wave_scroll < 0.0 then wave_scroll = 0.0 end
            if wave_scroll > 1.0 then wave_scroll = 1.0 end
          end

          local view_start = item_start_g
          local view_end = item_end
          if max_scroll > 0.0 then
            local offset = wave_scroll * max_scroll
            view_start = item_start_g + offset
            view_end = view_start + vis_len
          end

          -- Mouse interaction: pan + zoom
          if r.ImGui_IsItemHovered(ctx) then
            if max_scroll > 0.0 and r.ImGui_IsMouseDown(ctx, 0) and r.ImGui_IsMouseDragging(ctx, 0) and r.ImGui_GetMouseDelta then
              local dx, _ = r.ImGui_GetMouseDelta(ctx)
              if dx ~= 0.0 then
                local cur_offset = wave_scroll * max_scroll
                local pan_time = -dx / math.max(1.0, (max_x - min_x)) * vis_len
                local new_offset = cur_offset + pan_time
                if new_offset < 0.0 then new_offset = 0.0 end
                if new_offset > max_scroll then new_offset = max_scroll end
                if max_scroll > 0.0 then
                  wave_scroll = new_offset / max_scroll
                  view_start = item_start_g + new_offset
                  view_end = view_start + vis_len
                end
              end
            end

            local wheel = r.ImGui_GetMouseWheel(ctx)
            if wheel ~= 0.0 then
              local mx, _ = r.ImGui_GetMousePos(ctx)
              if mx < min_x then mx = min_x end
              if mx > max_x then mx = max_x end
              local cursor_u = (mx - min_x) / (max_x - min_x)
              local cursor_time = view_start + cursor_u * (view_end - view_start)

              local factor = (wheel > 0) and (1.0 / 1.25) or 1.25
              local new_zoom = wave_zoom * factor
              if new_zoom < 1.0 then new_zoom = 1.0 end
              if new_zoom > 64.0 then new_zoom = 64.0 end
              wave_zoom = new_zoom

              local new_vis = item_len_g / new_zoom
              if new_vis > item_len_g then new_vis = item_len_g end
              local new_start = cursor_time - cursor_u * new_vis
              if new_start < item_start_g then new_start = item_start_g end
              if new_start + new_vis > item_end then new_start = item_end - new_vis end

              local new_max_scroll = math.max(0.0, item_len_g - new_vis)
              if new_max_scroll <= 0.0 then
                wave_scroll = 0.0
              else
                wave_scroll = (new_start - item_start_g) / new_max_scroll
                if wave_scroll < 0.0 then wave_scroll = 0.0 end
                if wave_scroll > 1.0 then wave_scroll = 1.0 end
              end
              vis_len = new_vis
              max_scroll = new_max_scroll
              view_start = new_start
              view_end = new_start + new_vis
            end
          end

          local function time_to_x(t)
            if t <= view_start then return min_x end
            if t >= view_end   then return max_x end
            return min_x + (t - view_start) / (view_end - view_start) * (max_x - min_x)
          end

          local mid_y = (min_y + max_y) * 0.5
          local half_h = (max_y - min_y) * 0.5 * 0.9
          local corner_r = 6

          -- Background with rounded corners
          r.ImGui_DrawList_AddRectFilled(draw_list, min_x, min_y, max_x, max_y, COL.timeline_bg_enabled, corner_r)

          -- Clip drawing to canvas bounds
          r.ImGui_DrawList_PushClipRect(draw_list, min_x, min_y, max_x, max_y, true)

          -- Center line
          r.ImGui_DrawList_AddLine(draw_list, min_x, mid_y, max_x, mid_y,
            r.ImGui_ColorConvertDouble4ToU32(0.4, 0.4, 0.4, 0.3), 1.0)

          -- Load peaks at screen resolution for visible range
          local num_px = math.floor(canvas_w + 0.5)
          local item_view_start = view_start - item_start_g
          local item_view_len = view_end - view_start

          -- Raw source peaks (ignores stretch markers) — same coords as teal
          local peaks = nil
          if r.FrenkieTransient_GetSourcePeaks then
            local csv = r.FrenkieTransient_GetSourcePeaks(num_px, item_view_start, item_view_len)
            if csv and csv ~= "" then
              local max_csv, min_csv = csv:match("([^;]*);(.*)")
              if max_csv and min_csv then
                local maxs, mins = {}, {}
                local i = 1
                for v in max_csv:gmatch("[^,]+") do maxs[i] = tonumber(v) or 0; i = i + 1 end
                i = 1
                for v in min_csv:gmatch("[^,]+") do mins[i] = tonumber(v) or 0; i = i + 1 end
                for j = #maxs + 1, num_px do maxs[j] = 0 end
                for j = #mins + 1, num_px do mins[j] = 0 end
                peaks = { maxs = maxs, mins = mins, count = num_px }
              end
            end
          end
          if not peaks then
            peaks = build_view_peaks(take, view_start, item_view_len, num_px)
          end

          if peaks then
            local DL_QuadFilled = r.ImGui_DrawList_AddQuadFilled
            local DL_PathLineTo = r.ImGui_DrawList_PathLineTo
            local DL_PathStroke = r.ImGui_DrawList_PathStroke
            local DL_AddLine = r.ImGui_DrawList_AddLine
            local has_path = DL_PathLineTo ~= nil

            local col_fill = r.ImGui_ColorConvertDouble4ToU32(0.55, 0.55, 0.55, 0.55)
            local col_outline = r.ImGui_ColorConvertDouble4ToU32(0.75, 0.75, 0.75, 0.8)

            -- Auto vertical fit: find max amplitude in visible peaks
            local max_amp = 0
            for i = 1, num_px do
              local a = math.abs(peaks.maxs[i])
              local b = math.abs(peaks.mins[i])
              if a > max_amp then max_amp = a end
              if b > max_amp then max_amp = b end
            end
            if max_amp < 0.0001 then max_amp = 1.0 end

            -- Compute top/bottom y per pixel column (normalized to max amplitude)
            local tops = {}
            local bots = {}
            for i = 1, num_px do
              local a = math.abs(peaks.maxs[i])
              local b = math.abs(peaks.mins[i])
              if b > a then a = b end
              local extent = (a / max_amp) * half_h
              if extent < 0.5 then extent = 0.5 end
              tops[i] = mid_y - extent
              bots[i] = mid_y + extent
            end

            -- Filled quads between adjacent columns
            for i = 1, num_px - 1 do
              local px1 = min_x + (i - 1)
              local px2 = min_x + i
              DL_QuadFilled(draw_list,
                px1, tops[i], px2, tops[i + 1],
                px2, bots[i + 1], px1, bots[i],
                col_fill)
            end

            -- Outlines via path API
            if has_path then
              for i = 1, num_px do
                DL_PathLineTo(draw_list, min_x + (i - 1), tops[i])
              end
              DL_PathStroke(draw_list, col_outline, 0, 1)
              for i = 1, num_px do
                DL_PathLineTo(draw_list, min_x + (i - 1), bots[i])
              end
              DL_PathStroke(draw_list, col_outline, 0, 1)
            else
              for i = 2, num_px do
                local px1 = min_x + (i - 2)
                local px2 = min_x + (i - 1)
                DL_AddLine(draw_list, px1, tops[i - 1], px2, tops[i], col_outline, 1)
                DL_AddLine(draw_list, px1, bots[i - 1], px2, bots[i], col_outline, 1)
              end
            end

            if r.FrenkieTransient_GetFilteredPeaks then
              local csv = r.FrenkieTransient_GetFilteredPeaks(num_px, item_view_start, item_view_len)
              if csv and csv ~= "" then
                local filt_vals = {}
                for v in csv:gmatch("[^,]+") do filt_vals[#filt_vals + 1] = tonumber(v) or 0 end

                -- Find max for auto-fit (use original max_amp so both share scale)
                local filt_max = 0
                for i = 1, #filt_vals do
                  if filt_vals[i] > filt_max then filt_max = filt_vals[i] end
                end
                if filt_max < 1e-7 then filt_max = 1 end

                -- Independent normalization: filtered waveform fills its own vertical space
                local filt_tops = {}
                local filt_bots = {}
                for i = 1, #filt_vals do
                  local extent = (filt_vals[i] / filt_max) * half_h
                  if extent < 0.3 then extent = 0.3 end
                  filt_tops[i] = mid_y - extent
                  filt_bots[i] = mid_y + extent
                end

                local col_filt_fill = r.ImGui_ColorConvertDouble4ToU32(0.15, 0.65, 0.60, 0.45)
                local col_filt_outline = r.ImGui_ColorConvertDouble4ToU32(0.15, 0.75, 0.70, 0.8)

                for i = 1, #filt_vals - 1 do
                  local px1 = min_x + (i - 1)
                  local px2 = min_x + i
                  DL_QuadFilled(draw_list,
                    px1, filt_tops[i], px2, filt_tops[i + 1],
                    px2, filt_bots[i + 1], px1, filt_bots[i],
                    col_filt_fill)
                end

                if has_path then
                  for i = 1, #filt_vals do
                    DL_PathLineTo(draw_list, min_x + (i - 1), filt_tops[i])
                  end
                  DL_PathStroke(draw_list, col_filt_outline, 0, 1)
                  for i = 1, #filt_vals do
                    DL_PathLineTo(draw_list, min_x + (i - 1), filt_bots[i])
                  end
                  DL_PathStroke(draw_list, col_filt_outline, 0, 1)
                else
                  for i = 2, #filt_vals do
                    local px1 = min_x + (i - 2)
                    local px2 = min_x + (i - 1)
                    DL_AddLine(draw_list, px1, filt_tops[i - 1], px2, filt_tops[i], col_filt_outline, 1)
                    DL_AddLine(draw_list, px1, filt_bots[i - 1], px2, filt_bots[i], col_filt_outline, 1)
                  end
                end
              end
            end
          end

          -- Draw detected transient preview markers (orange vertical lines)
          for i = 1, #preview_markers do
            local t = preview_markers[i]
            if t >= view_start and t <= view_end then
              local x = time_to_x(t)
              r.ImGui_DrawList_AddLine(draw_list, x, min_y, x, max_y, COL.playhead_marker, 1.2)
            end
          end

          -- Playhead
          local play_state = r.GetPlayState()
          if play_state & 1 == 1 or play_state & 4 == 4 then
            local play_pos = r.GetPlayPosition()
            if play_pos >= view_start and play_pos <= view_end then
              local px = time_to_x(play_pos)
              r.ImGui_DrawList_AddLine(draw_list, px, min_y, px, max_y, COL.accent, 1.5)
            end
          end

          r.ImGui_DrawList_PopClipRect(draw_list)

          -- Inner shadow (top and left edges)
          for s = 1, 3 do
            local a = 0.18 * (4 - s) / 3
            local sc = r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, a)
            r.ImGui_DrawList_AddLine(draw_list, min_x + corner_r, min_y + s - 1, max_x - corner_r, min_y + s - 1, sc, 1)
            r.ImGui_DrawList_AddLine(draw_list, min_x + s - 1, min_y + corner_r, min_x + s - 1, max_y - corner_r, sc, 1)
          end

          -- Rounded border
          r.ImGui_DrawList_AddRect(draw_list, min_x, min_y, max_x, max_y,
            r.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 0.5), corner_r, 0, 1)

          r.ImGui_Unindent(ctx, pad)
        end
      end
    end
  end

  if visible then
    r.ImGui_End(ctx)
  end
  pop_frp_style(ctx)
  return open
end

local function loop()
  local open = draw()
  if open then
    r.defer(loop)
  else
    if r.ImGui_DestroyContext then
      r.ImGui_DestroyContext(ctx)
    end
  end
end

loop()
