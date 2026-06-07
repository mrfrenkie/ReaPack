-- @noindex

---@diagnostic disable: undefined-global -- reaper is provided by REAPER at runtime

local SECTION = "FrenkieRecentProjectsHistory"
local KEY_REV = "rev_v1"
local KEY_HB = "hb_v1"
local KEY_OBSERVER_CMD = "observer_cmd_id_v1"
local KEY_OBSERVER_SECTION = "observer_section_id_v1"
local KEY_OBSERVER_RUNNING = "observer_running_v1"
local KEY_OPEN_LIST = "open_list_v1"
local KEY_OPEN_REV = "open_rev_v1"

local MAX_ITEMS = 1000
local POLL_INTERVAL_SEC = 0.5
local SIGNAL_THRESHOLD_LINEAR = 0.001
local IDLE_GRACE_SEC = 20
local TIME_SAVE_INTERVAL_SEC = 30

local HISTORY_JSON_FILENAME = "My Recent Projects List.json"
local HISTORY_TXT_FALLBACK = "My Recent Projects List.txt"
local LEGACY_HISTORY_FILENAME = "Frenkie Recent Projects History.txt"
local HISTORY_FILENAME_OLD_TYPO = "My Resent Projects List.txt"
local SESSIONS_LOG_FILENAME = "Frenkie Recent Projects Sessions.log"

local function get_history_dir()
  local src = debug.getinfo(1, "S")
  local script_path = src and src.source and src.source:match("@(.+)") or ""
  local dir = script_path:match("(.+)[/\\][^/\\]+$") or ""
  return dir:match("(.+)[/\\][^/\\]+$") or dir
end

local function get_history_file_path()
  local dir = get_history_dir()
  local has_file_exists = reaper and reaper.file_exists
  local json_path = (dir ~= "" and (dir .. "/" .. HISTORY_JSON_FILENAME)) or HISTORY_JSON_FILENAME
  if has_file_exists and reaper.file_exists(json_path) then
    return json_path
  end
  local txt_candidates = (dir ~= "" and { dir .. "/" .. HISTORY_TXT_FALLBACK, dir .. "/" .. HISTORY_FILENAME_OLD_TYPO, dir .. "/" .. LEGACY_HISTORY_FILENAME }) or { HISTORY_TXT_FALLBACK, HISTORY_FILENAME_OLD_TYPO, LEGACY_HISTORY_FILENAME }
  for _, p in ipairs(txt_candidates) do
    if has_file_exists and reaper.file_exists(p) then
      return p
    end
  end
  return (dir ~= "" and (dir .. "/" .. HISTORY_TXT_FALLBACK)) or HISTORY_TXT_FALLBACK
end

local function get_sessions_log_path()
  local dir = get_history_file_path():match("(.+)[/\\][^/\\]+$") or ""
  if dir == "" then return SESSIONS_LOG_FILENAME end
  return dir .. "/" .. SESSIONS_LOG_FILENAME
end

local function append_session_log(epoch_sec, project_norm, open_delta, work_delta)
  local path = get_sessions_log_path()
  local f = io.open(path, "a")
  if not f then return end
  f:write(string.format("%d\t%s\t%.2f\t%.2f\n",
    math.floor(epoch_sec),
    tostring(project_norm):gsub("\t", " "):gsub("\n", " "),
    tonumber(open_delta) or 0,
    tonumber(work_delta) or 0))
  f:close()
end

local function setToggleState(sectionID, cmdID, state)
  if not sectionID or not cmdID then return end
  if reaper.SetToggleCommandState and reaper.RefreshToolbar2 then
    reaper.SetToggleCommandState(sectionID, cmdID, state or 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
  end
end

local function norm_path(p)
  return tostring(p or ""):gsub("\\", "/"):lower()
end

local function base_name(p)
  local s = tostring(p or "")
  local n = s:match("([^/\\]+)%.rpp$") or s:match("([^/\\]+)$") or s
  return n
end

local function esc(s)
  s = tostring(s or "")
  s = s:gsub("%%", "%%25")
  s = s:gsub("\r", "%%0D")
  s = s:gsub("\n", "%%0A")
  s = s:gsub("\t", "%%09")
  return s
end

local function unesc(s)
  s = tostring(s or "")
  s = s:gsub("%%0D", "\r")
  s = s:gsub("%%0A", "\n")
  s = s:gsub("%%09", "\t")
  s = s:gsub("%%25", "%%")
  return s
end

local function looks_like_project_path(p)
  local s = tostring(p or "")
  if s == "" then return false end
  local low = s:lower()
  if low:match("%.rpp$") then return true end
  if low:match("%.rpp%-bak$") then return true end
  return s:match("[/\\]") ~= nil and low:find(".rpp", 1, true) ~= nil
end

local function json_escape(s)
  s = tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
  return s
end

local function history_to_json(history)
  local parts = {}
  for i = 1, math.min(#history, MAX_ITEMS) do
    local it = history[i]
    parts[#parts + 1] = string.format(
      '{"path":"%s","norm":"%s","name":"%s","last_opened":%d,"open_count":%d,"total_open_sec":%d,"total_work_sec":%d}',
      json_escape(it.path or ""),
      json_escape(it.norm or ""),
      json_escape(it.name or ""),
      tonumber(it.last_opened) or 0,
      tonumber(it.open_count) or 0,
      math.floor(tonumber(it.total_open_sec) or 0),
      math.floor(tonumber(it.total_work_sec) or 0)
    )
  end
  return "[" .. table.concat(parts, ",") .. "]"
end

local function json_decode_history(raw)
  local out = {}
  raw = tostring(raw or ""):match("^%s*(.-)%s*$") or ""
  if raw == "" or not raw:match("^%[") then return out end
  local pos = 1
  local function skip_ws()
    while pos <= #raw and raw:sub(pos, pos):match("%s") do pos = pos + 1 end
  end
  local function parse_string()
    if raw:sub(pos, pos) ~= '"' then return nil end
    pos = pos + 1
    local start = pos
    local s = ""
    while pos <= #raw do
      local c = raw:sub(pos, pos)
      if c == '\\' and pos < #raw then
        pos = pos + 1
        local e = raw:sub(pos, pos)
        if e == 'n' then s = s .. "\n"
        elseif e == 'r' then s = s .. "\r"
        elseif e == 't' then s = s .. "\t"
        elseif e == '"' then s = s .. '"'
        elseif e == '\\' then s = s .. '\\'
        else s = s .. e
        end
        pos = pos + 1
      elseif c == '"' then
        pos = pos + 1
        return s
      else
        s = s .. c
        pos = pos + 1
      end
    end
    return nil
  end
  local function parse_number()
    local from = pos
    while pos <= #raw and raw:sub(pos, pos):match("[%d%-]") or (pos > from and raw:sub(pos, pos) == ".") do pos = pos + 1 end
    return tonumber(raw:sub(from, pos - 1))
  end
  local function parse_object()
    skip_ws()
    if raw:sub(pos, pos) ~= "{" then return nil end
    pos = pos + 1
    local obj = {}
    while true do
      skip_ws()
      if raw:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      local key = parse_string()
      if not key then return nil end
      skip_ws()
      if raw:sub(pos, pos) ~= ":" then return nil end
      pos = pos + 1
      skip_ws()
      local val
      if raw:sub(pos, pos) == '"' then val = parse_string()
      else val = parse_number()
      end
      if val == nil and raw:sub(pos, pos) ~= '"' then return nil end
      obj[key] = val
      skip_ws()
      if raw:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      if raw:sub(pos, pos) ~= "," then return nil end
      pos = pos + 1
    end
  end
  skip_ws()
  if raw:sub(pos, pos) ~= "[" then return out end
  pos = pos + 1
  while true do
    skip_ws()
    if raw:sub(pos, pos) == "]" then break end
    local obj = parse_object()
    if not obj or not obj.path then break end
    if looks_like_project_path(obj.path) then
      out[#out + 1] = {
        path = obj.path,
        norm = tostring(obj.norm or ""):gsub("\\", "/"):lower(),
        name = tostring(obj.name or ""),
        last_opened = tonumber(obj.last_opened) or 0,
        open_count = tonumber(obj.open_count) or 0,
        total_open_sec = tonumber(obj.total_open_sec) or 0,
        total_work_sec = tonumber(obj.total_work_sec) or 0
      }
      if out[#out].name == "" then out[#out].name = base_name(obj.path) end
    end
    skip_ws()
    if raw:sub(pos, pos) == "]" then break end
    if raw:sub(pos, pos) ~= "," then break end
    pos = pos + 1
  end
  return out
end

local function parse_history_raw(raw)
  local out = {}
  raw = tostring(raw or "")
  if raw == "" then return out end

  for line in (raw .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then
      local total_open_sec = 0
      local total_work_sec = 0
      local line4 = line
      local o1, o2 = line:match("\t([%d%.]+)\t([%d%.]+)$")
      if o1 and o2 then
        total_open_sec = tonumber(o1) or 0
        total_work_sec = tonumber(o2) or 0
        line4 = line:gsub("\t[%d%.]+\t[%d%.]+$", "")
      end

      local ts_s, cnt_s, name_s, path_s = line4:match("^(%d+)\t(%d+)\t(.-)\t(.*)$")
      local path = nil
      local name = nil
      local last_opened = 0
      local open_count = 0

      if ts_s and cnt_s and path_s then
        path = unesc(path_s)
        name = unesc(name_s or "")
        last_opened = tonumber(ts_s) or 0
        open_count = tonumber(cnt_s) or 0
      else
        local ts3_s, name3_s, path3_s = line4:match("^(%d+)\t(.-)\t(.*)$")
        if ts3_s and path3_s then
          path = unesc(path3_s)
          name = unesc(name3_s or "")
          last_opened = tonumber(ts3_s) or 0
          open_count = 0
        else
          local ts2_s, path2_s = line4:match("^(%d+)\t(.*)$")
          if ts2_s and path2_s then
            path = unesc(path2_s)
            name = ""
            last_opened = tonumber(ts2_s) or 0
            open_count = 0
          else
            path = unesc(line4)
            name = ""
            last_opened = 0
            open_count = 0
          end
        end
      end

      path = tostring(path or "")
      if looks_like_project_path(path) then
        name = tostring(name or "")
        if name == "" then
          name = base_name(path)
        end
        out[#out + 1] = {
          path = path,
          norm = norm_path(path),
          name = name,
          last_opened = last_opened,
          open_count = open_count,
          total_open_sec = total_open_sec,
          total_work_sec = total_work_sec
        }
      end
    end
  end
  return out
end

local write_history_file

local function read_history_file()
  local path = get_history_file_path()
  local f = io.open(path, "r")
  if not f then
    return {}
  end
  local raw = f:read("*a") or ""
  f:close()
  if path:lower():match("%.json%s*$") then
    return json_decode_history(raw)
  end
  return parse_history_raw(raw)
end

function write_history_file(history)
  local path = get_history_file_path()
  local tmp_path = path .. ".tmp"
  local f = io.open(tmp_path, "w")
  if not f then
    return false
  end
  if path:lower():match("%.json%s*$") then
    f:write(history_to_json(history))
  else
    for i = 1, math.min(#history, MAX_ITEMS) do
      local it = history[i]
      f:write(string.format(
        "%d\t%d\t%s\t%s\t%d\t%d\n",
        tonumber(it.last_opened) or 0,
        tonumber(it.open_count) or 0,
        esc(it.name or ""),
        esc(it.path or ""),
        math.floor(tonumber(it.total_open_sec) or 0),
        math.floor(tonumber(it.total_work_sec) or 0)
      ))
    end
  end
  f:close()
  local ok = os.rename(tmp_path, path)
  if not ok then
    os.remove(tmp_path)
    return false
  end
  return true
end

local function load_history()
  local items = read_history_file()
  return items
end

local last_history_rev = ""

local function save_history(history)
  write_history_file(history)
  if reaper.SetExtState then
    local rev = tostring(math.floor(reaper.time_precise() * 1000))
    reaper.SetExtState(SECTION, KEY_REV, rev, true)
    last_history_rev = rev
  end
end

local function find_index(history, norm)
  for i = 1, #history do
    if history[i] and history[i].norm == norm then
      return i
    end
  end
  return nil
end

local history = load_history()
do
  local rev = tostring(math.floor(reaper.time_precise() * 1000))
  if reaper.SetExtState then
    reaper.SetExtState(SECTION, KEY_REV, rev, true)
  end
  last_history_rev = rev
end

local seen_open = {}
local function rebuild_seen_open()
  seen_open = {}
  for i = 1, #history do
    local it = history[i]
    if it and it.norm and it.norm ~= "" then
      seen_open[it.norm] = true
    end
  end
end
rebuild_seen_open()

local last_current_norm = ""
local next_poll_t = 0.0
local last_open_sig = ""
local last_poll_time = 0.0
local last_signal_time = 0.0
local last_time_save = 0.0
local session_open_sec = 0.0
local session_work_sec = 0.0

local function build_open_signature()
  if not reaper.EnumProjects then
    return ""
  end
  local paths = {}
  local i = 0
  while true do
    local proj, p = reaper.EnumProjects(i, "")
    if not proj then break end
    p = tostring(p or "")
    local n = norm_path(p)
    if n ~= "" then
      paths[#paths + 1] = n
    end
    i = i + 1
    if i >= 256 then break end
  end
  table.sort(paths)
  return table.concat(paths, "\n")
end

local function record_open(path, now)
  path = tostring(path or "")
  if path == "" then return false end

  local norm = norm_path(path)
  if norm == "" then return false end

  local idx = find_index(history, norm)
  if idx then
    local it = history[idx]
    it.last_opened = now
    it.open_count = (tonumber(it.open_count) or 0) + 1
    it.name = it.name ~= "" and it.name or base_name(path)
    if idx ~= 1 then
      table.remove(history, idx)
      table.insert(history, 1, it)
    end
  else
    table.insert(history, 1, {
      path = path,
      norm = norm,
      name = base_name(path),
      last_opened = now,
      open_count = 1,
      total_open_sec = 0,
      total_work_sec = 0
    })
    if #history > MAX_ITEMS then
      history[MAX_ITEMS + 1] = nil
    end
  end
  return true
end

local function get_master_peak_linear()
  if not reaper.GetMasterTrack or not reaper.APIExists or not reaper.APIExists("Track_GetPeakInfo") then
    return 0
  end
  local master = reaper.GetMasterTrack(0)
  if not master then return 0 end
  local L = reaper.Track_GetPeakInfo(master, 0)
  local R = reaper.Track_GetPeakInfo(master, 1)
  return math.max(tonumber(L) or 0, tonumber(R) or 0)
end

local function poll_once()
  if reaper.GetExtState then
    local rev = tostring(reaper.GetExtState(SECTION, KEY_REV) or "")
    if rev ~= "" and rev ~= last_history_rev then
      last_history_rev = rev
      history = load_history()
      rebuild_seen_open()
    end
  end
  local now = reaper.time_precise()
  local now_epoch = math.floor(now)

  local changed = false
  local time_changed = false

  if reaper.EnumProjects then
    local _, cur_path = reaper.EnumProjects(-1, "")
    cur_path = tostring(cur_path or "")
    local cur_norm = norm_path(cur_path)
    if cur_norm ~= "" and cur_norm ~= last_current_norm then
      last_current_norm = cur_norm
      last_signal_time = 0
      session_open_sec = 0.0
      session_work_sec = 0.0
      changed = record_open(cur_path, now_epoch) or changed
    end

    local i = 0
    while true do
      local proj, p = reaper.EnumProjects(i, "")
      if not proj then break end
      p = tostring(p or "")
      local n = norm_path(p)
      if n ~= "" and not seen_open[n] then
        seen_open[n] = true
        changed = record_open(p, now_epoch) or changed
      end
      i = i + 1
      if i >= 256 then break end
    end

    local peak = get_master_peak_linear()
    if peak >= SIGNAL_THRESHOLD_LINEAR then
      last_signal_time = now
    end
    local is_working = (peak >= SIGNAL_THRESHOLD_LINEAR) or
      (last_signal_time > 0 and (now - last_signal_time) < IDLE_GRACE_SEC)

    if last_poll_time > 0 and cur_norm ~= "" then
      local delta = now - last_poll_time
      local idx = find_index(history, cur_norm)
      if idx then
        local it = history[idx]
        it.total_open_sec = (tonumber(it.total_open_sec) or 0) + delta
        session_open_sec = session_open_sec + delta
        if is_working then
          it.total_work_sec = (tonumber(it.total_work_sec) or 0) + delta
          session_work_sec = session_work_sec + delta
        end
        time_changed = true
      end
    end
    last_poll_time = now
  end

  if reaper.SetExtState then
    local sig = build_open_signature()
    if sig ~= last_open_sig then
      last_open_sig = sig
      reaper.SetExtState(SECTION, KEY_OPEN_LIST, sig, true)
      reaper.SetExtState(SECTION, KEY_OPEN_REV, tostring(math.floor(now * 1000)), true)
    end
  end

  if changed then
    save_history(history)
    last_time_save = now
  elseif time_changed and (now - last_time_save) >= TIME_SAVE_INTERVAL_SEC then
    if last_current_norm ~= "" and (session_open_sec > 0 or session_work_sec > 0) then
      append_session_log(now, last_current_norm, session_open_sec, session_work_sec)
      session_open_sec = 0.0
      session_work_sec = 0.0
    end
    save_history(history)
    last_time_save = now
  end
end

local Observer = {}
Observer.SECTION = SECTION
Observer.KEY_LIST = KEY_OPEN_LIST
Observer.KEY_REV = KEY_REV
Observer.KEY_HB = KEY_HB

function Observer.update()
  local now = reaper.time_precise()
  reaper.SetExtState(SECTION, KEY_HB, tostring(math.floor(now * 1000)), true)
  if now >= next_poll_t then
    next_poll_t = now + POLL_INTERVAL_SEC
    poll_once()
  end
end

local embedded = rawget(_G, "FrenkieRecentProjects_EmbedObserver") == true
if embedded then
  return Observer
end

local _, _, sectionID, cmdID = reaper.get_action_context()
sectionID = tonumber(sectionID)
cmdID = tonumber(cmdID)

if reaper.SetExtState then
  reaper.SetExtState(SECTION, KEY_OBSERVER_SECTION, tostring(sectionID or ""), true)
  reaper.SetExtState(SECTION, KEY_OBSERVER_CMD, tostring(cmdID or ""), true)
  reaper.SetExtState(SECTION, KEY_OBSERVER_RUNNING, "1", true)
end

setToggleState(sectionID, cmdID, 1)
reaper.atexit(function()
  setToggleState(sectionID, cmdID, 0)
  if reaper.SetExtState then
    reaper.SetExtState(SECTION, KEY_OBSERVER_RUNNING, "0", true)
  end
end)

local function standalone_loop()
  Observer.update()
  reaper.defer(standalone_loop)
end

standalone_loop()
