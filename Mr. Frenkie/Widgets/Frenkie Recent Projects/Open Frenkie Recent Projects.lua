-- @noindex

-- Frenkie Recent Projects - Main Entry Point
-- Author: Mr. Frenkie / ChatGPT
-- Description: Recent Projects Manager v.1.1
---@diagnostic disable: undefined-global -- reaper is provided by REAPER at runtime

-- Check for ReaImGUI
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

local script_path = debug.getinfo(1, "S").source:match("@(.+)")
local script_dir = script_path:match("(.+)[/\\][^/\\]+$")
local functions_dir = script_dir .. "/Functions"

local settings_section = "FrenkieRecentProjects"

local function load_theme_from_settings()
    local theme_name = "dark"
    if reaper.GetExtState then
        local stored = tostring(reaper.GetExtState(settings_section, "theme") or "")
        if stored == "light" or stored == "dark" then
            theme_name = stored
        end
    end

    local function try_load_theme(path)
        local ok, result = pcall(dofile, path)
        if not ok then
            return nil
        end
        if type(result) == "table" then
            return result
        end
        if type(FRPTheme) == "table" then
            return FRPTheme
        end
        return nil
    end

    local primary_filename = (theme_name == "light") and "Theme Light.lua" or "Theme Dark.lua"
    local primary_path = functions_dir .. "/" .. primary_filename
    local theme = nil

    if not reaper.file_exists or reaper.file_exists(primary_path) then
        theme = try_load_theme(primary_path)
    end

    if not theme then
        local fallback_filename = (theme_name == "light") and "Theme Dark.lua" or "Theme Light.lua"
        local fallback_path = functions_dir .. "/" .. fallback_filename
        if not reaper.file_exists or reaper.file_exists(fallback_path) then
            theme = try_load_theme(fallback_path)
        end
    end

    if type(theme) ~= "table" then
        FRPTheme = FRPTheme or {}
    else
        FRPTheme = theme
    end
end

dofile(functions_dir .. "/List.lua")
load_theme_from_settings()
dofile(functions_dir .. "/UI.lua")
local HISTORY_SECTION = "FrenkieRecentProjectsHistory"
local HISTORY_KEY_REV = "rev_v1"
local HISTORY_KEY_HB = "hb_v1"
local HISTORY_KEY_OBSERVER_CMD = "observer_cmd_id_v1"
local HISTORY_KEY_OBSERVER_SECTION = "observer_section_id_v1"
local HISTORY_KEY_OPEN_REV = "open_rev_v1"
local OBSERVER_FILENAME = "Frenkie Recent Projects Observer.lua"
local OBSERVER_HEARTBEAT_STALE_MS = 2500
local OPEN_POLL_INTERVAL_SEC = 1.0

local last_observer_start_t = 0.0
local cached_observer_cmd_id = 0

local function get_toggle_state(sectionID, cmdID)
    local sid = tonumber(sectionID) or 0
    local cid = tonumber(cmdID) or 0
    if cid <= 0 then
        return 0
    end
    if reaper.GetToggleCommandStateEx then
        return reaper.GetToggleCommandStateEx(sid, cid)
    end
    if reaper.GetToggleCommandState and sid == 0 then
        return reaper.GetToggleCommandState(cid)
    end
    return 0
end

local function is_observer_running()
    if not reaper.GetExtState then
        return false
    end

    local sectionID = tonumber(reaper.GetExtState(HISTORY_SECTION, HISTORY_KEY_OBSERVER_SECTION) or "") or 0
    local cmdID = tonumber(reaper.GetExtState(HISTORY_SECTION, HISTORY_KEY_OBSERVER_CMD) or "") or 0

    if get_toggle_state(sectionID, cmdID) == 1 then
        return true
    end

    local now = reaper.time_precise()
    local hb_ms = tonumber(reaper.GetExtState(HISTORY_SECTION, HISTORY_KEY_HB) or "") or 0
    local alive = (hb_ms > 0) and ((math.floor(now * 1000) - hb_ms) <= OBSERVER_HEARTBEAT_STALE_MS)
    return alive
end

local function ensure_observer_running()
    if not reaper.GetExtState then
        return false
    end

    if is_observer_running() then
        return true
    end

    local now = reaper.time_precise()
    if (now - last_observer_start_t) < 2.0 then
        return is_observer_running()
    end
    last_observer_start_t = now

    local observer_path = functions_dir .. "/" .. OBSERVER_FILENAME
    if not reaper.file_exists or not reaper.file_exists(observer_path) then
        return false
    end

    local start_requested = false
    if reaper.AddRemoveReaScript and reaper.Main_OnCommand then
        if cached_observer_cmd_id <= 0 then
            cached_observer_cmd_id = tonumber(reaper.AddRemoveReaScript(true, 0, observer_path, true) or 0) or 0
        end
        local cmd_id = cached_observer_cmd_id
        if cmd_id and cmd_id > 0 then
            local state = get_toggle_state(0, cmd_id)
            if state ~= 1 then
                reaper.Main_OnCommand(cmd_id, 0)
            end
            start_requested = true
        end
    end

    local ok = is_observer_running()
    if ok then
        return true
    end

    if start_requested then
        return true
    end

    return false
end

local PINNED_KEY = "pinned_paths_v1"
local FIRST_RUN_HINT_KEY = "observer_hint_shown_v1"

local function normalize_path(p)
    local s = tostring(p or "")
    if s == "" then return "" end
    return (s:gsub("\\", "/")):lower()
end

-- Function to set toggle state for action list
local function setToggleState(state)
    local _, _, sectionID, cmdID = reaper.get_action_context()
    reaper.SetToggleCommandState(sectionID, cmdID, state or 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
end

-- Function to load settings
local function load_settings()
    local settings = {}

    local bottom_panel_h = reaper.GetExtState(settings_section, "bottom_panel_h")
    if bottom_panel_h and bottom_panel_h ~= "" then
        settings.bottom_panel_h = tonumber(bottom_panel_h)
    end

    local sort_mode = reaper.GetExtState(settings_section, "sort_mode")
    if sort_mode and sort_mode ~= "" then
        settings.sort_mode = tostring(sort_mode)
    else
        settings.sort_mode = "modified"
    end

    local sort_dir_opened = reaper.GetExtState(settings_section, "sort_dir_opened")
    if sort_dir_opened and sort_dir_opened ~= "" then
        settings.sort_dir_opened = tostring(sort_dir_opened)
    end

    local sort_dir_modified = reaper.GetExtState(settings_section, "sort_dir_modified")
    if sort_dir_modified and sort_dir_modified ~= "" then
        settings.sort_dir_modified = tostring(sort_dir_modified)
    end

    local projects_scroll_y = reaper.GetExtState(settings_section, "projects_scroll_y")
    if projects_scroll_y and projects_scroll_y ~= "" then
        settings.projects_scroll_y = tonumber(projects_scroll_y)
    end

    local selected_project_path = reaper.GetExtState(settings_section, "selected_project_path")
    if selected_project_path and selected_project_path ~= "" then
        settings.selected_project_path = tostring(selected_project_path)
    end

    do
        local compact_view = tostring(reaper.GetExtState(settings_section, "compact_view") or "")
        if compact_view ~= "" then
            settings.compact_view = (compact_view == "1" or compact_view == "true")
        end
    end

    do
        local pinned_raw = tostring(reaper.GetExtState(settings_section, PINNED_KEY) or "")
        local pinned = {}
        for line in (pinned_raw .. "\n"):gmatch("(.-)\n") do
            if line ~= "" then
                pinned[line] = true
            end
        end
        settings.pinned_paths = pinned
    end

    do
        local theme = tostring(reaper.GetExtState(settings_section, "theme") or "")
        if theme == "light" or theme == "dark" then
            settings.theme = theme
        else
            settings.theme = "dark"
        end
    end

    return settings
end

local function save_settings(settings)
    if not settings then return end
    if settings.bottom_panel_h ~= nil then
        reaper.SetExtState(settings_section, "bottom_panel_h", tostring(settings.bottom_panel_h), true)
    end
    if settings.sort_mode ~= nil then
        reaper.SetExtState(settings_section, "sort_mode", tostring(settings.sort_mode), true)
    end
    if settings.sort_dir_opened ~= nil then
        reaper.SetExtState(settings_section, "sort_dir_opened", tostring(settings.sort_dir_opened), true)
    end
    if settings.sort_dir_modified ~= nil then
        reaper.SetExtState(settings_section, "sort_dir_modified", tostring(settings.sort_dir_modified), true)
    end
    if settings.projects_scroll_y ~= nil then
        reaper.SetExtState(settings_section, "projects_scroll_y", tostring(settings.projects_scroll_y), true)
    end
    if settings.selected_project_path ~= nil then
        reaper.SetExtState(settings_section, "selected_project_path", tostring(settings.selected_project_path), true)
    end
    if settings.compact_view ~= nil then
        reaper.SetExtState(settings_section, "compact_view", settings.compact_view and "1" or "0", true)
    end

    if settings.theme ~= nil then
        local theme = tostring(settings.theme)
        if theme ~= "" then
            reaper.SetExtState(settings_section, "theme", theme, true)
        end
    end

    do
        local pinned = settings.pinned_paths
        if type(pinned) == "table" then
            local keys = {}
            for k, v in pairs(pinned) do
                if v == true and tostring(k) ~= "" then
                    keys[#keys + 1] = tostring(k)
                end
            end
            table.sort(keys)
            reaper.SetExtState(settings_section, PINNED_KEY, table.concat(keys, "\n"), true)
        else
            reaper.SetExtState(settings_section, PINNED_KEY, "", true)
        end
    end
end

local function show_observer_first_run_hint()
    if not reaper.GetExtState or not reaper.SetExtState then
        return
    end
    local shown = tostring(reaper.GetExtState(settings_section, FIRST_RUN_HINT_KEY) or "")
    if shown ~= "" then
        return
    end
    if reaper.ShowMessageBox then
        reaper.ShowMessageBox(
            "Frenkie Recent Projects uses a background observer script to track recent projects.\n\n" ..
            "For best results, keep 'Frenkie Recent Projects Observer.lua' running at all times, " ..
            "for example by adding it to REAPER's startup actions.",
            "Frenkie Recent Projects - Notice",
            0
        )
    end
    reaper.SetExtState(settings_section, FIRST_RUN_HINT_KEY, "1", true)
end
ensure_observer_running()

do
    local observer_path = functions_dir .. "/" .. OBSERVER_FILENAME
    if not reaper.file_exists or not reaper.file_exists(observer_path) then
        reaper.ShowMessageBox(
            "Frenkie Recent Projects observer script not found.\n\nExpected at:\n" .. observer_path,
            "Error",
            0
        )
        return
    end
end

show_observer_first_run_hint()

-- Load settings
local user_settings = load_settings()

-- Global state
local app_state = {
    running = true,
    projects = {},
    filtered_projects = {},
    filter_text = "",
    selected_index = -1,
    selected_project = nil,
    selected_rows = {},
    selection_anchor_index = nil,
    selection_section = nil,
    pin_on_screen = false,
    request_close = false,
    preview_volume = 1.0,
    settings = user_settings,
    save_settings = save_settings
}

-- Initialize modules
ProjectList.init()
if ProjectList.ensure_reaper_ini_import then
    ProjectList.ensure_reaper_ini_import()
end
if ProjectList.set_preview_volume then
    ProjectList.set_preview_volume(app_state.preview_volume)
end
if not UI.init() then
    reaper.ShowMessageBox("Failed to initialize UI module!", "Error", 0)
    return
end

-- Function to refresh project list
local function refresh_projects()
    -- Clear caches for fresh data
    if ProjectList.refresh_open_projects_cache then
        ProjectList.refresh_open_projects_cache()
    end
    if ProjectList.clear_file_date_cache then
        ProjectList.clear_file_date_cache()
    end

    app_state.projects = ProjectList.get_recent_projects()
    if ProjectList and ProjectList.rebuild_filtered_projects then
        ProjectList.rebuild_filtered_projects(app_state)
    end
end

-- Main application loop
local last_history_rev = nil
local last_open_rev = nil
local next_open_poll_t = 0.0
do
    last_history_rev = tostring(reaper.GetExtState(HISTORY_SECTION, HISTORY_KEY_REV) or "")
    last_open_rev = tostring(reaper.GetExtState(HISTORY_SECTION, HISTORY_KEY_OPEN_REV) or "")
end

local function main_loop()
    do
        local rev = tostring(reaper.GetExtState(HISTORY_SECTION, HISTORY_KEY_REV) or "")
        if rev ~= last_history_rev then
            last_history_rev = rev
            refresh_projects()
        end
    end
    do
        local now = reaper.time_precise()
        if now >= next_open_poll_t then
            next_open_poll_t = now + OPEN_POLL_INTERVAL_SEC
            local open_rev = tostring(reaper.GetExtState(HISTORY_SECTION, HISTORY_KEY_OPEN_REV) or "")
            if open_rev ~= last_open_rev then
                last_open_rev = open_rev
                refresh_projects()
            end
        end
    end
    -- Update UI
    app_state.running = UI.draw(app_state)

    if app_state.running then
        reaper.defer(main_loop)
    else
        if UI and UI.cleanup then
            UI.cleanup()
        end
        setToggleState(0) -- Set to off when closing
    end
end

-- Set toggle state to "on" when script starts
setToggleState(1)

-- Set toggle state to "off" when script exits
reaper.atexit(function()
    setToggleState(0)
    if app_state and app_state.save_settings and app_state.settings then
        app_state.save_settings(app_state.settings)
    end
    if ProjectList and ProjectList.stop_preview then
        ProjectList.stop_preview()
    end
end)

-- Start the application
refresh_projects()
main_loop()
