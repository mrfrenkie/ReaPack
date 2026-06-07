-- @noindex

-- Frenkie Recent Projects - List Module
-- Handles project discovery, filtering, and management
---@diagnostic disable: undefined-global -- reaper is provided by REAPER at runtime

ProjectList = {}

local function api_exists(name)
    if reaper.APIExists then
        local ok = reaper.APIExists(name)
        if ok then return true end
    end
    return type(reaper[name]) == "function"
end

local function get_project_preview_path(project_path)
    if not project_path or project_path == "" then
        return nil
    end
    local low = tostring(project_path):lower()
    if low:sub(-5) == "-prox" then
        if reaper.file_exists(project_path) then
            return project_path
        end
        return nil
    end
    local candidates = {
        project_path .. "-PROX",
        project_path .. "-prox",
        project_path .. "-Prox"
    }
    for _, p in ipairs(candidates) do
        if reaper.file_exists(p) then
            return p
        end
    end
    return nil
end

local current_preview_source = nil
local current_preview_handle = nil
local is_preview_playing = false
local current_preview_path = nil
local preview_start_time = nil
local preview_duration = nil
local preview_seek_pos = 0.0
local preview_volume = 1.0
local preview_paused = false
local preview_pause_pos = 0.0
local preview_markers_cache = {}
local project_meta_cache = {}
local mini_rpp_parser = nil
local mini_rpp_parser_failed = false
local get_source_length = nil

local function load_mini_rpp_parser()
    if mini_rpp_parser then return mini_rpp_parser end
    if mini_rpp_parser_failed then return nil end

    local src = debug.getinfo(1, "S")
    local script_path = (src and src.source and src.source:match("@(.+)")) or ""
    local dir = script_path:match("(.+)[/\\][^/\\]+$") or ""
    if dir == "" then
        mini_rpp_parser_failed = true
        return nil
    end

    local parser_path = dir .. "/MiniParser.lua"
    if not (reaper and reaper.file_exists and reaper.file_exists(parser_path)) then
        mini_rpp_parser_failed = true
        return nil
    end

    local ok, mod = pcall(dofile, parser_path)
    if not ok or type(mod) ~= "table" or type(mod.read_project_metadata) ~= "function" then
        mini_rpp_parser_failed = true
        return nil
    end

    mini_rpp_parser = mod
    return mini_rpp_parser
end


function ProjectList.get_project_metadata(project_path)
    local p = tostring(project_path or "")
    if p == "" then return nil, false end
    if not reaper.file_exists or not reaper.file_exists(p) then return nil, false end

    local cached = project_meta_cache[p]
    if cached ~= nil then
        if cached == false then
            if mini_rpp_parser then
                return nil, true
            end
            return nil, false
        end
        return cached, true
    end

    local parser = load_mini_rpp_parser()
    if not parser then
        project_meta_cache[p] = false
        return nil, false
    end

    local ok, meta = pcall(parser.read_project_metadata, p)
    if not ok or not meta or type(meta) ~= "table" then
        project_meta_cache[p] = false
        return nil, true
    end

    project_meta_cache[p] = meta
    return meta, true
end

local function read_u32_le(s, i)
    local b1, b2, b3, b4 = s:byte(i, i + 3)
    if not b4 then return nil end
    return b1 + (b2 * 256) + (b3 * 65536) + (b4 * 16777216)
end

local function read_u16_le(s, i)
    local b1, b2 = s:byte(i, i + 1)
    if not b2 then return nil end
    return b1 + (b2 * 256)
end

local function read_u64_le(s, i)
    local lo = read_u32_le(s, i)
    local hi = read_u32_le(s, i + 4)
    if lo == nil or hi == nil then return nil end
    return lo + (hi * 4294967296.0)
end

local function trim_cstr(s)
    s = tostring(s or "")
    local z = s:find("\0", 1, true)
    if z then
        return s:sub(1, z - 1)
    end
    return s
end

local function read_wav_markers(preview_path)
    local entries = {}
    if not preview_path or preview_path == "" then return entries end
    if not reaper.file_exists(preview_path) then return entries end

    local f = io.open(preview_path, "rb")
    if not f then return entries end

    local function read_n(n)
        if n <= 0 then return "" end
        local s = f:read(n)
        if not s or #s < n then return nil end
        return s
    end

    local head = read_n(12)
    local riff_id = head and head:sub(1, 4) or ""
    if not head or (riff_id ~= "RIFF" and riff_id ~= "RF64") or head:sub(9, 12) ~= "WAVE" then
        f:close()
        return entries
    end

    local sample_rate = nil
    local cue_offsets = {}
    local cue_labels = {}
    local cue_lengths = {}
    local ixml_text = nil
    local rf64_data_size = nil

    local function parse_ixml_cues(xml)
        local out = {}
        if not xml or xml == "" then return out end
        local auto_id = 1
        for block in xml:gmatch("<CUE_POINT.-</CUE_POINT>") do
            local name = block:match("<NAME>(.-)</NAME>") or block:match("<LABEL>(.-)</LABEL>") or block:match("<NOTE>(.-)</NOTE>") or ""
            name = trim_cstr(name:gsub("^%s+", ""):gsub("%s+$", ""))
            local id_s = block:match("<ID>(.-)</ID>") or block:match("<CUE_ID>(.-)</CUE_ID>") or block:match("<CUEID>(.-)</CUEID>")
            local cue_id = nil
            if id_s then
                id_s = tostring(id_s):gsub("^%s+", ""):gsub("%s+$", "")
                cue_id = tonumber(id_s)
            end
            if not cue_id then
                cue_id = auto_id
                auto_id = auto_id + 1
            end
            local pos = block:match("<SAMPLE_OFFSET>([^<]+)</SAMPLE_OFFSET>")
                or block:match("<SAMPLE_POSITION>([^<]+)</SAMPLE_POSITION>")
                or block:match("<POSITION>([^<]+)</POSITION>")
                or block:match("<START>([^<]+)</START>")
            local len = block:match("<SAMPLE_LENGTH>([^<]+)</SAMPLE_LENGTH>")
                or block:match("<LENGTH>([^<]+)</LENGTH>")
                or block:match("<DURATION>([^<]+)</DURATION>")
            local t = nil
            local finish = nil
            local sample_off = nil
            if pos then
                local pv = tostring(pos):gsub("^%s+", ""):gsub("%s+$", "")
                local n = tonumber(pv)
                if n then
                    if pv:find("%.", 1, true) then
                        t = n
                        if sample_rate and sample_rate > 0 then
                            sample_off = math.max(0, math.floor((n * sample_rate) + 0.5))
                        end
                    elseif sample_rate and sample_rate > 0 then
                        sample_off = math.max(0, math.floor(n + 0.5))
                        t = sample_off / sample_rate
                    end
                end
            end
            if len then
                local lv = tostring(len):gsub("^%s+", ""):gsub("%s+$", "")
                local n = tonumber(lv)
                if n and t ~= nil then
                    if lv:find("%.", 1, true) then
                        finish = t + n
                    elseif sample_rate and sample_rate > 0 then
                        local len_samp = math.max(0, math.floor(n + 0.5))
                        finish = t + (len_samp / sample_rate)
                    end
                end
            end
            if t ~= nil then
                out[#out + 1] = {
                    cue_id = cue_id,
                    t = t,
                    finish = finish,
                    name = name,
                    sample_off = sample_off,
                }
            end
        end
        return out
    end

    while true do
        local ch = read_n(8)
        if not ch then break end

        local chunk_id = ch:sub(1, 4)
        local chunk_size = read_u32_le(ch, 5) or 0
        if chunk_size < 0 then chunk_size = 0 end

        if riff_id == "RF64" and chunk_id == "ds64" then
            local max_read = 1024 * 1024
            if chunk_size > max_read then
                f:seek("cur", chunk_size)
            else
                local data = (chunk_size > 0) and read_n(chunk_size) or ""
                if data and #data >= 28 then
                    local data_size = read_u64_le(data, 9)
                    if data_size and data_size > 0 then
                        rf64_data_size = data_size
                    end
                end
            end
        elseif chunk_id == "fmt " then
            local data = read_n(math.min(chunk_size, 16))
            if data and #data >= 8 then
                sample_rate = read_u32_le(data, 5) or sample_rate
            end
            local remaining = chunk_size - (data and #data or 0)
            if remaining > 0 then
                f:seek("cur", remaining)
            end
        elseif chunk_id == "cue " then
            local max_cues = 100000
            local num_s = read_n(4)
            if not num_s then break end
            local num = read_u32_le(num_s, 1) or 0
            local bytes_left = chunk_size - 4
            if num < 0 then num = 0 end
            if num > max_cues then num = max_cues end
            for _ = 1, num do
                if bytes_left < 24 then break end
                local pt = read_n(24)
                if not pt then bytes_left = 0 break end
                local cue_id = read_u32_le(pt, 1)
                local pos = read_u32_le(pt, 5)
                local sample_off = read_u32_le(pt, 21)
                local use = nil
                if pos and pos > 0 then
                    use = pos
                elseif sample_off and sample_off > 0 then
                    use = sample_off
                elseif sample_off then
                    use = sample_off
                end
                if cue_id and use then
                    cue_offsets[cue_id] = use
                end
                bytes_left = bytes_left - 24
            end
            if bytes_left > 0 then
                f:seek("cur", bytes_left)
            end
        elseif chunk_id == "LIST" then
            local list_type = read_n(4)
            if not list_type then break end
            local bytes_left = chunk_size - 4
            if list_type == "adtl" then
                while bytes_left >= 8 do
                    local sub_head = read_n(8)
                    if not sub_head then bytes_left = 0 break end
                    local sub_id = sub_head:sub(1, 4)
                    local sub_size = read_u32_le(sub_head, 5) or 0
                    bytes_left = bytes_left - 8
                    if sub_size < 0 then sub_size = 0 end
                    local payload = ""
                    if sub_size > 0 then
                        local p = read_n(sub_size)
                        if not p then bytes_left = 0 break end
                        payload = p
                    end
                    bytes_left = bytes_left - sub_size

                    if (sub_id == "labl" or sub_id == "note") and #payload >= 4 then
                        local cue_id = read_u32_le(payload, 1)
                        if cue_id then
                            cue_labels[cue_id] = trim_cstr(payload:sub(5))
                        end
                    elseif sub_id == "ltxt" and #payload >= 8 then
                        local cue_id = read_u32_le(payload, 1)
                        local sample_len = read_u32_le(payload, 5)
                        if cue_id and sample_len and sample_len > 0 then
                            cue_lengths[cue_id] = sample_len
                        end
                        if cue_id and (not cue_labels[cue_id] or cue_labels[cue_id] == "") and #payload > 20 then
                            local txt = trim_cstr(payload:sub(21))
                            if txt ~= "" then
                                cue_labels[cue_id] = txt
                            end
                        end
                    end

                    if (sub_size % 2) == 1 then
                        if bytes_left <= 0 then break end
                        read_n(1)
                        bytes_left = bytes_left - 1
                    end
                end
                if bytes_left > 0 then
                    f:seek("cur", bytes_left)
                end
            else
                if bytes_left > 0 then
                    f:seek("cur", bytes_left)
                end
            end
        elseif chunk_id == "iXML" then
            local max_read = 4 * 1024 * 1024
            if chunk_size > max_read then
                f:seek("cur", chunk_size)
            else
                local data = (chunk_size > 0) and read_n(chunk_size) or ""
                if data and data ~= "" then
                    ixml_text = data
                end
            end
        else
            local skip = chunk_size
            if riff_id == "RF64" and chunk_id == "data" and (chunk_size == 4294967295 or chunk_size == 0xFFFFFFFF) and rf64_data_size then
                skip = rf64_data_size
            end
            if skip and skip > 0 then
                pcall(function()
                    f:seek("cur", skip)
                end)
            end
        end

        if (chunk_size % 2) == 1 then
            f:seek("cur", 1)
        end
    end

    f:close()

    if not sample_rate or sample_rate <= 0 then
        if ixml_text and ixml_text ~= "" then
            local ixml = parse_ixml_cues(ixml_text)
            table.sort(ixml, function(a, b)
                return (tonumber(a.t) or 0) < (tonumber(b.t) or 0)
            end)
            for _, it in ipairs(ixml) do
                entries[#entries + 1] = {
                    is_region = it.finish ~= nil,
                    start = it.t,
                    finish = it.finish,
                    name = (it.name and it.name ~= "") and it.name or tostring(it.cue_id or ""),
                    color = 0,
                }
            end
        end
        return entries
    end

    local tmp = {}
    local ixml = nil
    local ixml_by_off = nil
    if ixml_text and ixml_text ~= "" then
        ixml = parse_ixml_cues(ixml_text)
        if #ixml > 0 then
            table.sort(ixml, function(a, b)
                return (tonumber(a.t) or 0) < (tonumber(b.t) or 0)
            end)
            ixml_by_off = {}
            for _, it in ipairs(ixml) do
                local off = tonumber(it.sample_off)
                if off and off >= 0 then
                    ixml_by_off[off] = it
                end
            end
        end
    end
    for cue_id, sample_off in pairs(cue_offsets) do
        local name = cue_labels[cue_id] or ""
        local finish_t = nil
        if ixml_by_off then
            local off = tonumber(sample_off)
            local hit = nil
            if off ~= nil then
                hit = ixml_by_off[off]
                if not hit then
                    for d = -16, 16 do
                        hit = ixml_by_off[off + d]
                        if hit then break end
                    end
                end
            end
            if hit then
                if (not name or name == "") and hit.name and hit.name ~= "" then
                    name = hit.name
                end
                if hit.finish ~= nil then
                    finish_t = hit.finish
                end
            end
        end
        tmp[#tmp + 1] = {
            cue_id = cue_id,
            sample_off = sample_off,
            name = name or "",
            sample_len = cue_lengths[cue_id],
            finish_t = finish_t,
        }
    end
    if #tmp == 0 and ixml_text and ixml_text ~= "" then
        ixml = parse_ixml_cues(ixml_text)
        for _, it in ipairs(ixml) do
            local off = math.max(0, math.floor((it.t or 0) * sample_rate + 0.5))
            tmp[#tmp + 1] = {
                cue_id = it.cue_id,
                sample_off = off,
                name = it.name or "",
                finish_t = it.finish,
            }
        end
    end
    table.sort(tmp, function(a, b)
        local ta = (tonumber(a.sample_off) or 0) / sample_rate
        local tb = (tonumber(b.sample_off) or 0) / sample_rate
        if ta ~= tb then return ta < tb end
        local na = tostring(a.name or "")
        local nb = tostring(b.name or "")
        if na ~= nb then return na < nb end
        return (tonumber(a.cue_id) or 0) < (tonumber(b.cue_id) or 0)
    end)

    if ixml and #ixml > 0 then
        local all_empty = true
        for _, it in ipairs(tmp) do
            if it.name and it.name ~= "" then
                all_empty = false
                break
            end
        end
        if all_empty and #tmp == #ixml then
            for i = 1, #tmp do
                local src = ixml[i]
                if src and src.name and src.name ~= "" then
                    tmp[i].name = src.name
                end
                if tmp[i].finish_t == nil and src and src.finish ~= nil then
                    tmp[i].finish_t = src.finish
                end
            end
        end
    end

    for _, it in ipairs(tmp) do
        local t = (tonumber(it.sample_off) or 0) / sample_rate
        local finish = nil
        if it.finish_t ~= nil then
            finish = it.finish_t
        elseif it.sample_len and it.sample_len > 0 then
            finish = t + ((tonumber(it.sample_len) or 0) / sample_rate)
        end
        entries[#entries + 1] = {
            is_region = finish ~= nil,
            start = t,
            finish = finish,
            name = (it.name and it.name ~= "") and it.name or tostring(it.cue_id or ""),
            color = 0,
        }
    end

    return entries
end

get_source_length = function(src)
    if not src then return nil end
    if api_exists("PCM_Source_GetLength") then
        local ok, a, b = pcall(reaper.PCM_Source_GetLength, src)
        if ok then
            if type(a) == "number" and a > 0 then
                return a
            end
            if type(b) == "number" and b > 0 then
                return b
            end
        end
    end
    if api_exists("GetMediaSourceLength") then
        local ok, len = pcall(reaper.GetMediaSourceLength, src)
        if ok and type(len) == "number" and len > 0 then
            return len
        end
    end
    return nil
end

function ProjectList.play_preview(preview_path)
    if not preview_path or preview_path == "" then return false end
    if not reaper.file_exists(preview_path) then
        return false
    end
    local has_cf_create = api_exists("CF_CreatePreview")
    local has_cf_play = api_exists("CF_Preview_Play")
    local has_pcm_create = api_exists("PCM_Source_CreateFromFile")
    local has_prev_play = api_exists("Preview_Play")
    local has_prev_stop = api_exists("Preview_Stop")
    if has_cf_create and has_cf_play and has_pcm_create then
        if current_preview_handle then
            if api_exists("CF_Preview_Destroy") then
                reaper.CF_Preview_Destroy(current_preview_handle)
            elseif api_exists("CF_Preview_Stop") then
                reaper.CF_Preview_Stop(current_preview_handle)
            end
            current_preview_handle = nil
        end
        if current_preview_source then
            reaper.PCM_Source_Destroy(current_preview_source)
            current_preview_source = nil
        end
        local src = reaper.PCM_Source_CreateFromFile(preview_path)
        if not src then
            return false
        end
        local handle = reaper.CF_CreatePreview(src)
        if not handle then
            reaper.PCM_Source_Destroy(src)
            return false
        end
        if api_exists("CF_Preview_SetValue") and preview_volume and type(preview_volume) == "number" and preview_volume >= 0 then
            pcall(reaper.CF_Preview_SetValue, handle, "D_VOLUME", preview_volume)
        end
        reaper.CF_Preview_Play(handle)
        preview_duration = get_source_length(src)
        current_preview_source = src
        current_preview_handle = handle
        current_preview_path = preview_path
        is_preview_playing = true
        preview_start_time = reaper.time_precise()
        preview_seek_pos = 0.0
        preview_paused = false
        preview_pause_pos = 0.0
        return true
    elseif has_pcm_create and has_prev_play then
        if current_preview_source then
            if has_prev_stop then
                reaper.Preview_Stop()
            end
            reaper.PCM_Source_Destroy(current_preview_source)
            current_preview_source = nil
        end
        local src = reaper.PCM_Source_CreateFromFile(preview_path)
        if not src then
            return false
        end
        reaper.Preview_Play(src)
        preview_duration = get_source_length(src)
        current_preview_source = src
        current_preview_handle = nil
        current_preview_path = preview_path
        is_preview_playing = true
        preview_start_time = reaper.time_precise()
        preview_seek_pos = 0.0
        preview_paused = false
        preview_pause_pos = 0.0
        return true
    end
    return false
end

function ProjectList.stop_preview()
    if api_exists("CF_Preview_Destroy") or api_exists("CF_Preview_Stop") then
        if current_preview_handle then
            if api_exists("CF_Preview_Destroy") then
                reaper.CF_Preview_Destroy(current_preview_handle)
            else
                reaper.CF_Preview_Stop(current_preview_handle)
            end
            current_preview_handle = nil
        end
        if current_preview_source then
            reaper.PCM_Source_Destroy(current_preview_source)
            current_preview_source = nil
        end
    elseif api_exists("Preview_Stop") then
        if current_preview_source then
            reaper.Preview_Stop()
            reaper.PCM_Source_Destroy(current_preview_source)
            current_preview_source = nil
        else
            reaper.Preview_Stop()
        end
    end
    is_preview_playing = false
    current_preview_path = nil
    preview_start_time = nil
    preview_duration = nil
    preview_seek_pos = 0.0
    preview_paused = false
    preview_pause_pos = 0.0
end

function ProjectList.toggle_preview(preview_path)
    local path = tostring(preview_path or current_preview_path or "")
    if path == "" then return false end

    local function same_path(a, b)
        a = tostring(a or "")
        b = tostring(b or "")
        if a == "" or b == "" then return false end
        if a == b then return true end
        if ProjectList and ProjectList.normalize_path then
            return ProjectList.normalize_path(a) == ProjectList.normalize_path(b)
        end
        return a:lower() == b:lower()
    end

    if is_preview_playing and current_preview_path and same_path(path, current_preview_path) then
        local elapsed = 0.0
        if preview_start_time then
            elapsed = math.max(0, preview_seek_pos + (reaper.time_precise() - preview_start_time))
        end
        preview_pause_pos = elapsed
        preview_paused = true
        if api_exists("CF_Preview_Stop") and current_preview_handle then
            reaper.CF_Preview_Stop(current_preview_handle)
        elseif api_exists("Preview_Stop") and current_preview_source then
            reaper.Preview_Stop()
        end
        is_preview_playing = false
        preview_start_time = nil
        return true
    end

    if (not is_preview_playing) and preview_paused and current_preview_path and same_path(path, current_preview_path) then
        if api_exists("CF_Preview_Play") and current_preview_handle then
            reaper.CF_Preview_Play(current_preview_handle)
            if api_exists("CF_Preview_SetValue") then
                reaper.CF_Preview_SetValue(current_preview_handle, "D_POSITION", preview_pause_pos or 0.0)
            end
            preview_seek_pos = preview_pause_pos or 0.0
            preview_start_time = reaper.time_precise()
            is_preview_playing = true
            preview_paused = false
            return true
        elseif api_exists("Preview_Play") and current_preview_source then
            reaper.Preview_Play(current_preview_source)
            preview_seek_pos = preview_pause_pos or 0.0
            preview_start_time = reaper.time_precise()
            is_preview_playing = true
            preview_paused = false
            return true
        end
    end

    preview_paused = false
    preview_pause_pos = 0.0
    return ProjectList.play_preview(path)
end

function ProjectList.set_preview_volume(volume)
    local v = tonumber(volume)
    if v == nil then return false end
    if v < 0 then v = 0 end
    preview_volume = v
    if api_exists("CF_Preview_SetValue") and current_preview_handle then
        pcall(reaper.CF_Preview_SetValue, current_preview_handle, "D_VOLUME", v)
    end
    return true
end

function ProjectList.get_preview_volume()
    return preview_volume
end

function ProjectList.is_preview_playing()
    return is_preview_playing
end

function ProjectList.get_preview_path(project_path)
    return get_project_preview_path(project_path)
end

function ProjectList.get_preview_status()
    if not is_preview_playing then return nil end
    local elapsed = 0.0
    if preview_start_time then
        elapsed = math.max(0, preview_seek_pos + (reaper.time_precise() - preview_start_time))
    end
    local duration = preview_duration or 0.0
    if (not preview_duration or preview_duration <= 0) and current_preview_source then
        local len = get_source_length(current_preview_source)
        if len and len > 0 then
            preview_duration = len
            duration = len
        end
    end
    local progress = 0.0
    if duration > 0 then
        progress = math.min(1.0, elapsed / duration)
    end
    return {
        playing = is_preview_playing,
        path = current_preview_path,
        elapsed = elapsed,
        duration = duration,
        progress = progress
    }
end

function ProjectList.get_preview_duration(preview_path)
    if not preview_path or preview_path == "" then return nil end
    if not reaper.file_exists(preview_path) then return nil end
    if not api_exists("PCM_Source_CreateFromFile") then return nil end
    local src = reaper.PCM_Source_CreateFromFile(preview_path)
    if not src then return nil end
    local len = get_source_length(src)
    reaper.PCM_Source_Destroy(src)
    if len and len > 0 then
        return len
    end
    return nil
end

local function normalize_path(path)
    if not path or path == "" then return "" end
    return path:gsub("\\", "/"):lower()
end

local waveform_cache = {}
local waveform_cache_keys = {}
local waveform_cache_max_entries = 24
local waveform_cache_version = 7

local function _round_ms(v)
    local x = tonumber(v) or 0.0
    if x >= 0 then
        return math.floor((x * 1000) + 0.5)
    end
    return -math.floor(((-x) * 1000) + 0.5)
end

local function waveform_cache_key(preview_path, columns, span, start_time, timeline_origin)
    local p = normalize_path(preview_path)
    local c = tonumber(columns) or 0
    local sp = tonumber(span) or 0.0
    local st = tonumber(start_time) or 0.0
    local org = tonumber(timeline_origin) or 0.0
    local sp_ms = _round_ms(sp)
    local st_ms = _round_ms(st)
    local org_ms = _round_ms(org)
    return tostring(waveform_cache_version) .. "|" .. p .. "|" .. tostring(c) .. "|" .. tostring(sp_ms) .. "|" .. tostring(st_ms) .. "|" .. tostring(org_ms)
end

local function waveform_cache_put(key, value)
    if waveform_cache[key] == nil then
        waveform_cache_keys[#waveform_cache_keys + 1] = key
        if #waveform_cache_keys > waveform_cache_max_entries then
            local old_key = table.remove(waveform_cache_keys, 1)
            if old_key then
                waveform_cache[old_key] = nil
            end
        end
    end
    waveform_cache[key] = value
end

function ProjectList.get_preview_waveform_for_span(preview_path, columns, timeline_span, timeline_min, timeline_origin)
    local dbg = {
        preview_path = preview_path,
        columns_req = columns,
        timeline_span = timeline_span,
        timeline_min = timeline_min,
        api_pcm_create = api_exists("PCM_Source_CreateFromFile"),
        api_get_peaks = api_exists("GetMediaSourcePeaks"),
        api_pcm_get_peaks = api_exists("PCM_Source_GetPeaks"),
        api_pcm_get_samples = api_exists("PCM_Source_GetSamples"),
    }

    if not preview_path or preview_path == "" then
        dbg.reason = "no_preview_path"
        return nil, dbg
    end
    if not reaper.file_exists(preview_path) then
        dbg.reason = "file_missing"
        return nil, dbg
    end
    if not dbg.api_pcm_create then
        dbg.reason = "no_pcm_source_create"
        return nil, dbg
    end

    local cols = math.floor(tonumber(columns) or 0)
    dbg.columns = cols
    if cols < 1 then
        dbg.reason = "bad_columns"
        return nil, dbg
    end

    local span = tonumber(timeline_span) or 0.0
    dbg.span = span
    if span <= 0 then
        dbg.reason = "bad_span"
        return nil, dbg
    end

    local view_min_timeline = tonumber(timeline_min) or 0.0
    local view_max_timeline = view_min_timeline + span
    dbg.view_min = view_min_timeline
    dbg.view_max = view_max_timeline

    local use_existing_source = false
    local src = nil
    if current_preview_source and current_preview_path and normalize_path(current_preview_path) == normalize_path(preview_path) then
        src = current_preview_source
        use_existing_source = true
    else
        src = reaper.PCM_Source_CreateFromFile(preview_path)
    end
    dbg.use_existing_source = use_existing_source
    if not src then
        dbg.reason = "pcm_source_create_failed"
        return nil, dbg
    end

    local duration = get_source_length and get_source_length(src) or nil
    dbg.duration = duration
    local org = tonumber(timeline_origin) or 0.0
    dbg.timeline_origin = org

    local key = waveform_cache_key(preview_path, cols, span, view_min_timeline, org)
    local cached = waveform_cache[key]
    if cached then
        if not use_existing_source then
            reaper.PCM_Source_Destroy(src)
        end
        dbg.cached = true
        dbg.reason = "cache_hit"
        dbg.peaks_method = cached.peaks_method or cached.method
        dbg.peaks_layout = cached.peaks_layout or cached.layout
        dbg.has_any = cached.has_any
        dbg.max_amp = cached.max_amp
        return cached, dbg
    end

    local start_time_raw = view_min_timeline - org
    local end_time_raw = start_time_raw + span
    dbg.start_time_raw = start_time_raw
    dbg.end_time_raw = end_time_raw

    if duration and duration > 0 then
        if start_time_raw >= duration then
            if not use_existing_source then
                reaper.PCM_Source_Destroy(src)
            end
            dbg.reason = "start_past_end"
            return nil, dbg
        end
        if end_time_raw <= 0 then
            if not use_existing_source then
                reaper.PCM_Source_Destroy(src)
            end
            dbg.reason = "range_before_start"
            return nil, dbg
        end
    end

    local left_pad_s = 0.0
    local right_pad_s = 0.0
    local start_time = start_time_raw
    if start_time < 0 then
        left_pad_s = math.min(span, -start_time)
        start_time = 0.0
    end
    if duration and duration > 0 and end_time_raw > duration then
        right_pad_s = math.min(span, end_time_raw - duration)
    end
    dbg.start_time = start_time
    dbg.pad_left_s = left_pad_s
    dbg.pad_right_s = right_pad_s

    local left_cols = math.floor(((left_pad_s * cols) / span) + 0.5)
    local right_cols = math.floor(((right_pad_s * cols) / span) + 0.5)
    if left_cols < 0 then left_cols = 0 end
    if left_cols > cols then left_cols = cols end
    if right_cols < 0 then right_cols = 0 end
    if right_cols > (cols - left_cols) then right_cols = cols - left_cols end
    local cols_eff = cols - left_cols - right_cols
    local span_eff = span - left_pad_s - right_pad_s
    dbg.pad_left_cols = left_cols
    dbg.pad_right_cols = right_cols
    dbg.cols_eff = cols_eff
    dbg.span_eff = span_eff
    if cols_eff <= 0 or span_eff <= 0 then
        if not use_existing_source then
            reaper.PCM_Source_Destroy(src)
        end
        dbg.reason = "span_empty"
        return nil, dbg
    end

    local num_channels = 2
    if api_exists("GetMediaSourceNumChannels") then
        local ch = reaper.GetMediaSourceNumChannels(src)
        if type(ch) == "number" and ch >= 1 then
            num_channels = math.floor(ch)
        end
    end
    if num_channels < 1 then num_channels = 1 end
    if num_channels > 2 then num_channels = 2 end
    dbg.num_channels = num_channels

    local peakrate = cols_eff / span_eff
    if peakrate < 1 then peakrate = 1 end
    if peakrate > 12000 then peakrate = 12000 end
    dbg.peakrate = peakrate

    local buf_sz = cols_eff * num_channels * 2
    dbg.buf_sz = buf_sz
    local buf = reaper.new_array(buf_sz)
    buf.clear()

    local function try_build_samples()
        if not api_exists("PCM_Source_GetSamples") then
            return nil
        end

        local samples_per_col = 256
        local sr = math.floor(((cols_eff * samples_per_col) / span_eff) + 0.5)
        if sr < 8000 then sr = 8000 end
        if sr > 44100 then sr = 44100 end
        dbg.samples_sr = sr

        local total_samples = math.max(1, math.floor((span_eff * sr) + 0.5))
        local chunk_samples = 32768
        local peaks_s = {}
        for i = 1, cols_eff do peaks_s[i] = 0.0 end

        local buf_samples = reaper.new_array(chunk_samples * num_channels)
        local global_i = 0
        local max_amp_s = 0.0
        local has_any_s = false

        while global_i < total_samples do
            local remaining = total_samples - global_i
            local n = remaining
            if n > chunk_samples then n = chunk_samples end
            buf_samples.clear()
            local ok_call, ret = pcall(reaper.PCM_Source_GetSamples, src, sr, num_channels, start_time + (global_i / sr), n, buf_samples)
            dbg.samples_retval = ret
            if not ok_call or (type(ret) == "number" and ret <= 0) then
                break
            end

            local bt = buf_samples.table(1, n * num_channels)
            for s = 1, n do
                global_i = global_i + 1
                local col = math.floor(((global_i - 1) * cols_eff) / total_samples) + 1
                if col < 1 then col = 1 end
                if col > cols_eff then col = cols_eff end
                local sum = 0.0
                local base = ((s - 1) * num_channels)
                for ch = 1, num_channels do
                    local v = bt[base + ch] or 0.0
                    if v < 0 then v = -v end
                    sum = sum + v
                end
                local mono = sum / num_channels
                if mono > 1 then mono = 1 end
                if mono > peaks_s[col] then peaks_s[col] = mono end
            end
        end

        for i = 1, cols_eff do
            local v = peaks_s[i] or 0.0
            if v > 0 then has_any_s = true end
            if v > max_amp_s then max_amp_s = v end
        end

        if has_any_s then
            return peaks_s, max_amp_s
        end
        return nil
    end

    local ok_peaks = false
    local peaks_method = nil
    if api_exists("PCM_Source_GetPeaks") then
        local ok_call, ret = pcall(reaper.PCM_Source_GetPeaks, src, peakrate, start_time, num_channels, cols_eff, 0, buf)
        dbg.peaks_retval = ret
        ok_peaks = ok_call
        if ok_peaks then peaks_method = "PCM_Source_GetPeaks" end
    elseif api_exists("GetMediaSourcePeaks") then
        local ok_call, ret = pcall(reaper.GetMediaSourcePeaks, src, peakrate, start_time, num_channels, cols_eff, 0, buf)
        dbg.peaks_retval = ret
        ok_peaks = ok_call
        if ok_peaks then peaks_method = "GetMediaSourcePeaks" end
    end
    if ok_peaks and (type(dbg.peaks_retval) == "number" and dbg.peaks_retval <= 0) and api_exists("PCM_Source_BuildPeaks") and api_exists("PCM_Source_GetPeaks") then
        local ok_bp = pcall(reaper.PCM_Source_BuildPeaks, src, 0)
        dbg.buildpeaks = ok_bp and 1 or 0
        local ok_call, ret = pcall(reaper.PCM_Source_GetPeaks, src, peakrate, start_time, num_channels, cols_eff, 0, buf)
        dbg.peaks_retval2 = ret
        ok_peaks = ok_call
        if ok_peaks then peaks_method = "PCM_Source_GetPeaks" end
    end
    dbg.ok_peaks = ok_peaks
    dbg.peaks_method = peaks_method
    if not ok_peaks then
        local peaks_s, max_amp_s = try_build_samples()
        if peaks_s then
            if not use_existing_source then
                reaper.PCM_Source_Destroy(src)
            end
            local peaks_out = peaks_s
            if left_cols > 0 or right_cols > 0 then
                local padded = {}
                for i = 1, left_cols do padded[i] = 0.0 end
                for i = 1, cols_eff do padded[left_cols + i] = peaks_s[i] or 0.0 end
                for i = 1, right_cols do padded[left_cols + cols_eff + i] = 0.0 end
                peaks_out = padded
            end
            local out = { columns = cols, peaks = peaks_out }
            out.method = "PCM_Source_GetSamples"
            out.layout = "samples"
            out.peaks_method = "PCM_Source_GetSamples"
            out.peaks_layout = "samples"
            out.has_any = true
            out.max_amp = max_amp_s
            waveform_cache_put(key, out)
            dbg.peaks_method = "PCM_Source_GetSamples"
            dbg.peaks_layout = "samples"
            dbg.has_any = true
            dbg.max_amp = max_amp_s
            dbg.reason = "ok_samples"
            return out, dbg
        end
        if not use_existing_source then
            reaper.PCM_Source_Destroy(src)
        end
        dbg.reason = "peaks_call_failed"
        return nil, dbg
    end

    local function decode_peaks_ret(ret)
        if type(ret) ~= "number" then
            return nil, nil, nil
        end
        local sample_count = ret % 1048576
        local output_mode = math.floor(ret / 1048576) % 16
        local has_extra = (math.floor(ret / 16777216) % 2) == 1
        return sample_count, output_mode, has_extra
    end

    local ret_used = dbg.peaks_retval2
    if type(ret_used) ~= "number" then
        ret_used = dbg.peaks_retval
    end
    local ret_samples, ret_mode, ret_extra = decode_peaks_ret(ret_used)
    dbg.peaks_ret_samples = ret_samples
    dbg.peaks_ret_mode = ret_mode
    dbg.peaks_ret_extra = ret_extra and 1 or 0
    if not ret_samples or ret_samples <= 0 then
        ok_peaks = false
    end

    if not ok_peaks then
        local peaks_s, max_amp_s = try_build_samples()
        if peaks_s then
            if not use_existing_source then
                reaper.PCM_Source_Destroy(src)
            end
            local peaks_out = peaks_s
            if left_cols > 0 or right_cols > 0 then
                local padded = {}
                for i = 1, left_cols do padded[i] = 0.0 end
                for i = 1, cols_eff do padded[left_cols + i] = peaks_s[i] or 0.0 end
                for i = 1, right_cols do padded[left_cols + cols_eff + i] = 0.0 end
                peaks_out = padded
            end
            local out = { columns = cols, peaks = peaks_out }
            out.method = "PCM_Source_GetSamples"
            out.layout = "samples"
            out.peaks_method = "PCM_Source_GetSamples"
            out.peaks_layout = "samples"
            out.has_any = true
            out.max_amp = max_amp_s
            waveform_cache_put(key, out)
            dbg.peaks_method = "PCM_Source_GetSamples"
            dbg.peaks_layout = "samples"
            dbg.has_any = true
            dbg.max_amp = max_amp_s
            dbg.reason = "ok_samples"
            return out, dbg
        end
        if not use_existing_source then
            reaper.PCM_Source_Destroy(src)
        end
        dbg.reason = "peaks_zero"
        return nil, dbg
    end

    local buf_t = buf.table(1, buf_sz)

    local function build_peaks()
        local peaks = {}
        local has_any = false
        local max_amp = 0.0
        local base_min = cols_eff * num_channels
        local n = ret_samples or cols_eff
        if n > cols_eff then n = cols_eff end

        for i = 1, cols_eff do
            if i > n then
                peaks[i] = 0.0
            else
                local sum = 0.0
                local base = ((i - 1) * num_channels)
                for ch = 1, num_channels do
                    local v_max = buf_t[base + ch] or 0.0
                    local v_min = buf_t[base_min + base + ch] or 0.0
                    local a = math.max(math.abs(v_max), math.abs(v_min))
                    sum = sum + a
                end
                local mono = sum / num_channels
                if mono < 0 then mono = 0 end
                if mono > 1 then mono = 1 end
                if mono > 0 then has_any = true end
                if mono > max_amp then max_amp = mono end
                peaks[i] = mono
            end
        end
        return peaks, has_any, max_amp
    end

    local peaks, has_any, max_amp = build_peaks()
    dbg.peaks_layout = "blocks_interleaved"
    dbg.has_any = has_any
    dbg.max_amp = max_amp

    if not has_any then
        local peaks_s, max_amp_s = try_build_samples()
        if peaks_s then
            if not use_existing_source then
                reaper.PCM_Source_Destroy(src)
            end
            local peaks_out = peaks_s
            if left_cols > 0 or right_cols > 0 then
                local padded = {}
                for i = 1, left_cols do padded[i] = 0.0 end
                for i = 1, cols_eff do padded[left_cols + i] = peaks_s[i] or 0.0 end
                for i = 1, right_cols do padded[left_cols + cols_eff + i] = 0.0 end
                peaks_out = padded
            end
            local out = { columns = cols, peaks = peaks_out }
            out.method = "PCM_Source_GetSamples"
            out.layout = "samples"
            out.peaks_method = "PCM_Source_GetSamples"
            out.peaks_layout = "samples"
            out.has_any = true
            out.max_amp = max_amp_s
            waveform_cache_put(key, out)
            dbg.peaks_method = "PCM_Source_GetSamples"
            dbg.peaks_layout = "samples"
            dbg.has_any = true
            dbg.max_amp = max_amp_s
            dbg.reason = "ok_samples"
            return out, dbg
        end

        if not use_existing_source then
            reaper.PCM_Source_Destroy(src)
        end
        dbg.reason = "all_zero"
        return nil, dbg
    end

    if not use_existing_source then
        reaper.PCM_Source_Destroy(src)
    end

    local peaks_out = peaks
    if left_cols > 0 or right_cols > 0 then
        local padded = {}
        for i = 1, left_cols do padded[i] = 0.0 end
        for i = 1, cols_eff do padded[left_cols + i] = peaks[i] or 0.0 end
        for i = 1, right_cols do padded[left_cols + cols_eff + i] = 0.0 end
        peaks_out = padded
    end

    local out = { columns = cols, peaks = peaks_out }
    out.method = dbg.peaks_method
    out.layout = dbg.peaks_layout
    out.peaks_method = dbg.peaks_method
    out.peaks_layout = dbg.peaks_layout
    out.has_any = dbg.has_any
    out.max_amp = dbg.max_amp
    waveform_cache_put(key, out)
    dbg.reason = "ok_peaks"
    return out, dbg
end

local function get_open_project_instance_by_path(project_path)
    local needle = normalize_path(project_path)
    if needle == "" then return nil end
    local project_index = 0
    while true do
        local project, open_project_path = reaper.EnumProjects(project_index, "")
        if not project then break end
        if normalize_path(open_project_path) == needle then
            return project
        end
        project_index = project_index + 1
        if project_index >= 100 then break end
    end
    return nil
end

function ProjectList.is_project_dirty(project_path)
    local p = tostring(project_path or "")
    if p == "" then
        return false
    end
    if not reaper.IsProjectDirty then
        return false
    end
    local proj = get_open_project_instance_by_path(p)
    if not proj then
        return false
    end
    return reaper.IsProjectDirty(proj) ~= 0
end

local function run_main_command_in_project(command_id, project)
    if reaper.Main_OnCommandEx and project then
        reaper.Main_OnCommandEx(command_id, 0, project)
        return
    end
    if project and reaper.SelectProjectInstance then
        local current_project = nil
        if reaper.EnumProjects then
            current_project = reaper.EnumProjects(-1, "")
        end
        reaper.SelectProjectInstance(project)
        reaper.Main_OnCommand(command_id, 0)
        if current_project then
            reaper.SelectProjectInstance(current_project)
        end
        return
    end
    reaper.Main_OnCommand(command_id, 0)
end

local IMPORT_EXT_SECTION = "FrenkieRecentProjects"
local IMPORT_EXT_KEY_DONE = "reaper_ini_import_done_v1"
local PREVIEW_HINT_KEY = "preview_hint_shown_count_v1"

local function maybe_show_preview_hint()
    if not reaper.GetExtState or not reaper.SetExtState or not reaper.ShowMessageBox then
        return
    end
    local raw = tostring(reaper.GetExtState(IMPORT_EXT_SECTION, PREVIEW_HINT_KEY) or "")
    local count = tonumber(raw) or 0
    if count >= 2 then
        return
    end
    local idx = count + 1
    local title = "Frenkie Recent Projects - Preview tips"
    local line1 = "1. For best results, set the '=START' and '=END' arrange markers before creating a dedicated track range.\n\n"
    local line2 = "2. REAPER may regularly show a prompt asking to automatically render a new preview (subproject).\n" ..
        "   You can disable this by right-clicking the project tab and choosing:\n" ..
        "   Subproject rendering > Do not automatically render subprojects (require manual render).\n\n"
    local footer = string.format("This message will be shown twice (%d/2).", idx)
    local msg = line1 .. line2 .. footer
    reaper.ShowMessageBox(msg, title, 0)
    reaper.SetExtState(IMPORT_EXT_SECTION, PREVIEW_HINT_KEY, tostring(idx), true)
end

function ProjectList.create_preview(project_path)
    if not project_path or project_path == "" then return false end
    if not reaper.file_exists(project_path) then return false end
    maybe_show_preview_hint()
    local CMD_NEW_PROJECT_TAB = 40859
    local CMD_SAVE_AND_RENDER_RPP_PROX = 42332

    local open_project = get_open_project_instance_by_path(project_path)
    if open_project then
        run_main_command_in_project(CMD_SAVE_AND_RENDER_RPP_PROX, open_project)
        return true
    end

    reaper.Main_OnCommand(CMD_NEW_PROJECT_TAB, 0)
    reaper.Main_openProject(project_path)
    reaper.Main_OnCommand(CMD_SAVE_AND_RENDER_RPP_PROX, 0)
    return true
end


function ProjectList.refresh_project_regions(project_path)
    local preview_path = get_project_preview_path(project_path)
    if not preview_path then
        return false
    end
    local regs = read_wav_markers(preview_path)
    preview_markers_cache[preview_path] = regs
    return regs ~= nil
end


function ProjectList.get_project_regions(project_path)
    if not project_path or project_path == "" then return {} end
    local preview_path = get_project_preview_path(project_path)
    if not preview_path then return {} end
    local key = preview_path
    local cached = preview_markers_cache[key]
    if cached == nil then
        cached = read_wav_markers(preview_path)
        preview_markers_cache[key] = cached
    end
    return cached
end


function ProjectList.seek_preview(pos_seconds)
    if not is_preview_playing then return false end
    if not pos_seconds or pos_seconds < 0 then pos_seconds = 0 end
    local duration = preview_duration or 0
    if duration > 0 and pos_seconds > duration then
        pos_seconds = duration
    end
    if api_exists("CF_Preview_SetValue") and current_preview_handle then
        reaper.CF_Preview_SetValue(current_preview_handle, "D_POSITION", pos_seconds)
        preview_seek_pos = pos_seconds
        preview_start_time = reaper.time_precise()
        return true
    end
    return false
end

-- Cache for file dates to avoid repeated system calls
local file_date_cache = {}
local file_access_cache = {}
local file_mtime_cache = {}
local file_atime_cache = {}
local file_birth_cache = {}
local file_size_cache = {}

local preview_media_info_cache = {}
local preview_media_info_keys = {}
local preview_media_info_max_entries = 64

local preview_peak_cache = {}
local preview_peak_keys = {}
local preview_peak_max_entries = 32

-- Clear file date cache (useful when refreshing)
local function clear_file_date_cache()
    file_date_cache = {}
    file_access_cache = {}
    file_mtime_cache = {}
    file_atime_cache = {}
    file_birth_cache = {}
    file_size_cache = {}
    preview_media_info_cache = {}
    preview_media_info_keys = {}
    preview_peak_cache = {}
    preview_peak_keys = {}
end

-- Get file modification date
local function get_file_date(file_path)
    -- Check cache first
    if file_date_cache[file_path] then
        return file_date_cache[file_path]
    end
    
    if not reaper.file_exists(file_path) then
        return "Unknown"
    end
    
    -- Use system command to get file modification date
    local date_str = nil
    local handle = io.popen('stat -c "%y" "' .. file_path .. '" 2>/dev/null || stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "' .. file_path .. '" 2>/dev/null')
    
    if handle then
        local result = handle:read("*a")
        handle:close()
        
        if result and result ~= "" and not result:match("stat:") then
            local raw_date = result:gsub("\n", ""):gsub("%.%d+", "")
            local year, month, day, hour, min = raw_date:match("(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d)")
            
            if year and month and day and hour and min then
                -- Check if it's today
                local today = os.date("*t")
                local file_year, file_month, file_day = tonumber(year), tonumber(month), tonumber(day)
                
                if file_year == today.year and file_month == today.month and file_day == today.day then
                    -- Show "Today HH:MM" for today's files
                    date_str = string.format("Today %s:%s", hour, min)
                else
                    -- Convert to DD.MM.YYYY HH:MM format for other dates
                    date_str = string.format("%s.%s.%s %s:%s", day, month, year, hour, min)
                end
            end
        end
    end
    
    -- Fallback
    if not date_str then
        date_str = "Recent"
    end
    
    -- Cache the result
    file_date_cache[file_path] = date_str
    
    return date_str
end

local function get_file_access_date(file_path)
    if not file_path or file_path == "" then
        return "Unknown"
    end

    if file_access_cache[file_path] then
        return file_access_cache[file_path]
    end

    if not reaper.file_exists(file_path) then
        return "Unknown"
    end

    local date_str = nil
    local handle = io.popen('stat -c "%x" "' .. file_path .. '" 2>/dev/null || stat -f "%Sa" -t "%Y-%m-%d %H:%M:%S" "' .. file_path .. '" 2>/dev/null')
    if handle then
        local result = handle:read("*a")
        handle:close()

        if result and result ~= "" and not result:match("stat:") then
            local raw_date = result:gsub("\n", ""):gsub("%.%d+", "")
            local year, month, day, hour, min = raw_date:match("(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d)")
            if year and month and day and hour and min then
                local today = os.date("*t")
                local file_year, file_month, file_day = tonumber(year), tonumber(month), tonumber(day)
                if file_year == today.year and file_month == today.month and file_day == today.day then
                    date_str = string.format("Today %s:%s", hour, min)
                else
                    date_str = string.format("%s.%s.%s %s:%s", day, month, year, hour, min)
                end
            end
        end
    end

    if not date_str then
        date_str = "Unknown"
    end

    file_access_cache[file_path] = date_str
    return date_str
end

local function get_file_size_bytes(file_path)
    if not file_path or file_path == "" then return nil end
    local cached = file_size_cache[file_path]
    if cached ~= nil then
        return cached or nil
    end
    if not reaper.file_exists(file_path) then
        file_size_cache[file_path] = false
        return nil
    end
    local f = io.open(file_path, "rb")
    if not f then
        file_size_cache[file_path] = false
        return nil
    end
    local ok_seek, size = pcall(function()
        local s = f:seek("end")
        return s
    end)
    f:close()
    if not ok_seek or type(size) ~= "number" or size < 0 then
        file_size_cache[file_path] = false
        return nil
    end
    file_size_cache[file_path] = size
    return size
end

function ProjectList.get_project_file_size(project_path)
    local p = tostring(project_path or "")
    if p == "" then return nil end
    return get_file_size_bytes(p)
end

local function extract_lufs_from_text(text)
    local s = tostring(text or "")
    if s == "" then return nil end
    local n = s:match("<INTEGRATED_LOUDNESS>%s*([%+%-]?%d+%.?%d*)%s*</INTEGRATED_LOUDNESS>")
        or s:match("<LOUDNESS_I>%s*([%+%-]?%d+%.?%d*)%s*</LOUDNESS_I>")
        or s:match("<I_LOUDNESS>%s*([%+%-]?%d+%.?%d*)%s*</I_LOUDNESS>")
        or s:match("([%+%-]?%d+%.?%d*)%s*LUFS")
    local v = tonumber(n)
    if v == nil then return nil end
    if v < -200 or v > 200 then return nil end
    return v
end

local function read_wav_format_and_ixml(file_path)
    local out = {}
    if not file_path or file_path == "" then return out end
    if not reaper.file_exists(file_path) then return out end
    local f = io.open(file_path, "rb")
    if not f then return out end

    local function read_n(n)
        if n <= 0 then return "" end
        local s = f:read(n)
        if not s or #s < n then return nil end
        return s
    end

    local head = read_n(12)
    local riff_id = head and head:sub(1, 4) or ""
    if not head or (riff_id ~= "RIFF" and riff_id ~= "RF64") or head:sub(9, 12) ~= "WAVE" then
        f:close()
        return out
    end

    while true do
        local ch = read_n(8)
        if not ch then break end
        local chunk_id = ch:sub(1, 4)
        local chunk_size = read_u32_le(ch, 5) or 0
        if chunk_size < 0 then chunk_size = 0 end

        if chunk_id == "fmt " then
            local data = read_n(math.min(chunk_size, 32))
            if data and #data >= 16 then
                out.channels = read_u16_le(data, 3) or out.channels
                out.sample_rate = read_u32_le(data, 5) or out.sample_rate
                out.bits_per_sample = read_u16_le(data, 15) or out.bits_per_sample
            end
            local remaining = chunk_size - (data and #data or 0)
            if remaining > 0 then
                f:seek("cur", remaining)
            end
        elseif chunk_id == "iXML" then
            local max_read = 2 * 1024 * 1024
            if chunk_size > max_read then
                f:seek("cur", chunk_size)
            else
                local data = (chunk_size > 0) and read_n(chunk_size) or ""
                if data and data ~= "" then
                    out.lufs_i = extract_lufs_from_text(data)
                end
            end
        else
            if chunk_size > 0 then
                pcall(function()
                    f:seek("cur", chunk_size)
                end)
            end
        end

        if (chunk_size % 2) == 1 then
            f:seek("cur", 1)
        end

        if out.sample_rate and out.bits_per_sample and out.channels and (out.lufs_i ~= nil or chunk_id == "iXML") then
            if out.lufs_i ~= nil then
                break
            end
        end
    end

    f:close()
    return out
end

local function format_date_like_file(date_table)
    if not date_table then
        return "Unknown"
    end

    local year = tonumber(date_table.year)
    local month = tonumber(date_table.month)
    local day = tonumber(date_table.day)
    local hour = tonumber(date_table.hour)
    local min = tonumber(date_table.min)

    if not (year and month and day and hour and min) then
        return "Unknown"
    end

    local today = os.date("*t")
    if year == today.year and month == today.month and day == today.day then
        return string.format("Today %02d:%02d", hour, min)
    end

    return string.format("%02d.%02d.%04d %02d:%02d", day, month, year, hour, min)
end

local function get_file_epoch_from_stat(file_path, stat_fmt_linux, stat_fmt_macos)
    if not file_path or file_path == "" then return nil end
    if not reaper.file_exists(file_path) then return nil end
    local handle = io.popen('stat -c "' .. stat_fmt_linux .. '" "' .. file_path .. '" 2>/dev/null || stat -f "' .. stat_fmt_macos .. '" "' .. file_path .. '" 2>/dev/null')
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()
    if not result or result == "" or result:match("stat:") then return nil end
    local s = tostring(result):gsub("\n", ""):match("^%s*(.-)%s*$")
    if s == "" then return nil end
    local n = tonumber(s)
    if not n or n <= 0 then return nil end
    return n
end

local function get_file_mtime_epoch(file_path)
    local cached = file_mtime_cache[file_path]
    if cached ~= nil then return cached end
    local n = get_file_epoch_from_stat(file_path, "%Y", "%m")
    file_mtime_cache[file_path] = n or false
    return n
end

local function get_file_atime_epoch(file_path)
    local cached = file_atime_cache[file_path]
    if cached ~= nil then return cached end
    local n = get_file_epoch_from_stat(file_path, "%X", "%a")
    file_atime_cache[file_path] = n or false
    return n
end

local function get_file_birth_epoch(file_path)
    local cached = file_birth_cache[file_path]
    if cached ~= nil then return cached end
    local n = get_file_epoch_from_stat(file_path, "%W", "%B")
    if not n then
        n = get_file_mtime_epoch(file_path)
    end
    file_birth_cache[file_path] = n or false
    return n
end

local function format_epoch_like_file(ts)
    local n = tonumber(ts)
    if not n or n <= 0 then return "Unknown" end
    return format_date_like_file(os.date("*t", math.floor(n)))
end

local function get_preview_created_epoch(preview_path)
    local mt = get_file_mtime_epoch(preview_path)
    if mt and tonumber(mt) and tonumber(mt) > 0 then
        return tonumber(mt)
    end
    local ts = get_file_birth_epoch(preview_path)
    if ts and tonumber(ts) and tonumber(ts) > 0 then
        return tonumber(ts)
    end
    return nil
end

function ProjectList.get_preview_created_date(preview_path)
    local ts = get_preview_created_epoch(preview_path)
    if ts then
        return format_epoch_like_file(ts)
    end
    return get_file_date(preview_path)
end

function ProjectList.get_preview_staleness_seconds(project_path, preview_path)
    local prev_ts = get_preview_created_epoch(preview_path)
    local proj_ts = get_file_mtime_epoch(project_path)
    if not prev_ts or not proj_ts then return nil end

    if proj_ts <= prev_ts then
        return 0
    end

    local diff = proj_ts - prev_ts
    if diff <= 0 then return 0 end
    return diff
end

function ProjectList.get_preview_staleness_days(project_path, preview_path)
    local diff = ProjectList.get_preview_staleness_seconds(project_path, preview_path)
    if diff == nil then return nil end
    return math.floor(diff / 86400)
end

local function cache_put(cache_tbl, keys_tbl, max_entries, key, value)
    if cache_tbl[key] == nil then
        keys_tbl[#keys_tbl + 1] = key
        if #keys_tbl > max_entries then
            local old_key = table.remove(keys_tbl, 1)
            if old_key then
                cache_tbl[old_key] = nil
            end
        end
    end
    cache_tbl[key] = value
end

local function amp_to_dbfs(amp)
    local a = tonumber(amp)
    if not a then return nil end
    if a <= 0 then return -math.huge end
    return 20.0 * (math.log(a) / math.log(10))
end

local function decode_peaks_ret(ret)
    if type(ret) ~= "number" then
        return nil, nil, nil
    end
    local sample_count = ret % 1048576
    local output_mode = math.floor(ret / 1048576) % 16
    local has_extra = (math.floor(ret / 16777216) % 2) == 1
    return sample_count, output_mode, has_extra
end

local function get_preview_peak_max_amp(preview_path)
    if not preview_path or preview_path == "" then return nil end
    local cached = preview_peak_cache[preview_path]
    if cached ~= nil then
        return cached or nil
    end
    if not reaper.file_exists(preview_path) then
        cache_put(preview_peak_cache, preview_peak_keys, preview_peak_max_entries, preview_path, false)
        return nil
    end
    if not api_exists("PCM_Source_CreateFromFile") then
        cache_put(preview_peak_cache, preview_peak_keys, preview_peak_max_entries, preview_path, false)
        return nil
    end

    local src = reaper.PCM_Source_CreateFromFile(preview_path)
    if not src then
        cache_put(preview_peak_cache, preview_peak_keys, preview_peak_max_entries, preview_path, false)
        return nil
    end

    local dur = get_source_length and get_source_length(src) or nil
    if not dur or dur <= 0 then
        reaper.PCM_Source_Destroy(src)
        cache_put(preview_peak_cache, preview_peak_keys, preview_peak_max_entries, preview_path, false)
        return nil
    end

    local cols = 2048
    local peakrate = cols / dur
    if peakrate < 1 then peakrate = 1 end
    if peakrate > 12000 then peakrate = 12000 end

    local num_channels = 2
    if api_exists("GetMediaSourceNumChannels") then
        local ch = reaper.GetMediaSourceNumChannels(src)
        if type(ch) == "number" and ch >= 1 then
            num_channels = math.floor(ch)
        end
    end
    if num_channels < 1 then num_channels = 1 end
    if num_channels > 2 then num_channels = 2 end

    local buf_sz = cols * num_channels * 2
    local buf = reaper.new_array(buf_sz)
    buf.clear()

    local ret = nil
    local ok_peaks = false
    if api_exists("PCM_Source_GetPeaks") then
        local ok_call, r = pcall(reaper.PCM_Source_GetPeaks, src, peakrate, 0.0, num_channels, cols, 0, buf)
        ok_peaks = ok_call
        ret = r
    elseif api_exists("GetMediaSourcePeaks") then
        local ok_call, r = pcall(reaper.GetMediaSourcePeaks, src, peakrate, 0.0, num_channels, cols, 0, buf)
        ok_peaks = ok_call
        ret = r
    end

    if not ok_peaks then
        reaper.PCM_Source_Destroy(src)
        cache_put(preview_peak_cache, preview_peak_keys, preview_peak_max_entries, preview_path, false)
        return nil
    end

    local ret_samples = nil
    if type(ret) == "number" then
        ret_samples = select(1, decode_peaks_ret(ret))
    end
    local n = ret_samples or cols
    if n > cols then n = cols end
    if n < 1 then n = 1 end

    local max_amp = 0.0
    local base_min = cols * num_channels
    local bt = buf.table(1, buf_sz)
    for i = 1, n do
        local base = ((i - 1) * num_channels)
        for ch = 1, num_channels do
            local v_max = bt[base + ch] or 0.0
            local v_min = bt[base_min + base + ch] or 0.0
            local a = math.max(math.abs(v_max), math.abs(v_min))
            if a > max_amp then max_amp = a end
        end
    end
    if max_amp > 1 then max_amp = 1 end
    if max_amp < 0 then max_amp = 0 end

    reaper.PCM_Source_Destroy(src)
    cache_put(preview_peak_cache, preview_peak_keys, preview_peak_max_entries, preview_path, max_amp)
    return max_amp
end

function ProjectList.get_preview_media_info(preview_path)
    if not preview_path or preview_path == "" then return {} end
    local cached = preview_media_info_cache[preview_path]
    if cached then return cached end

    local info = {}
    info.size_bytes = get_file_size_bytes(preview_path)

    local wav = read_wav_format_and_ixml(preview_path)
    if wav then
        info.channels = wav.channels
        info.sample_rate = wav.sample_rate
        info.bits_per_sample = wav.bits_per_sample
        info.lufs_i = wav.lufs_i
    end

    local max_amp = get_preview_peak_max_amp(preview_path)
    if max_amp ~= nil then
        info.peak_max_amp = max_amp
        info.peak_dbfs = amp_to_dbfs(max_amp)
    end

    cache_put(preview_media_info_cache, preview_media_info_keys, preview_media_info_max_entries, preview_path, info)
    return info
end

local get_opened_date = function()
    return nil
end

local function refresh_project_dates(project)
    if not project then return false end
    local project_path = project.full_path or project.path
    if not project_path or project_path == "" then return false end
    file_date_cache[project_path] = nil
    file_access_cache[project_path] = nil
    file_mtime_cache[project_path] = nil
    project.date = get_file_date(project_path)
    project.opened_date = get_opened_date(project.time or "", project_path)
    return true
end

local function refresh_project_preview_dates(project)
    if not project then return false end
    local project_path = project.full_path or project.path
    local preview_path = project.preview_path
    if not preview_path or preview_path == "" or not reaper.file_exists(preview_path) then
        project.preview_created_date = nil
        project.preview_stale_days = nil
        project.preview_stale_seconds = nil
        return false
    end
    file_date_cache[preview_path] = nil
    file_birth_cache[preview_path] = nil
    file_mtime_cache[preview_path] = nil
    project.preview_created_date = ProjectList.get_preview_created_date(preview_path)
    project.preview_stale_seconds = ProjectList.get_preview_staleness_seconds(project_path, preview_path)
    project.preview_stale_days = ProjectList.get_preview_staleness_days(project_path, preview_path)
    return true
end

function ProjectList.refresh_project_meta(project)
    refresh_project_dates(project)
    refresh_project_preview_dates(project)
end

function ProjectList.refresh_projects_meta(projects)
    if not projects then return end
    for _, p in ipairs(projects) do
        ProjectList.refresh_project_meta(p)
    end
end

get_opened_date = function(ini_time, file_path)
    local s = tostring(ini_time or ""):match("^%s*(.-)%s*$")
    if s == "" then
        return get_file_access_date(file_path)
    end

    local n = tonumber(s)
    if n and n > 0 then
        if n > 20000000000 then
            n = n / 1000
        end
        local t = math.floor(n)
        if t > 0 then
            return format_date_like_file(os.date("*t", t))
        end
    end

    local y, mo, d, h, mi, se = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)%s+(%d%d):(%d%d):?(%d*)")
    if y and mo and d and h and mi then
        local year = tonumber(y)
        local month = tonumber(mo)
        local day = tonumber(d)
        local hour = tonumber(h)
        local min = tonumber(mi)
        local sec = tonumber(se) or 0
        if year and month and day and hour and min then
            local ts = os.time({
                year = year,
                month = month,
                day = day,
                hour = hour,
                min = min,
                sec = sec
            })
            if ts and ts > 0 then
                return format_date_like_file(os.date("*t", ts))
            end
        end
    end

    return get_file_access_date(file_path)
end

local function get_opened_epoch(ini_time, file_path)
    local s = tostring(ini_time or ""):match("^%s*(.-)%s*$")
    local n = tonumber(s)
    if n and n > 0 then
        if n > 20000000000 then
            n = n / 1000
        end
        local t = math.floor(n)
        if t > 0 then
            return t
        end
    end

    local y, mo, d, h, mi, se = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)%s+(%d%d):(%d%d):?(%d*)")
    if y and mo and d and h and mi then
        local year = tonumber(y)
        local month = tonumber(mo)
        local day = tonumber(d)
        local hour = tonumber(h)
        local min = tonumber(mi)
        local sec = tonumber(se) or 0
        if year and month and day and hour and min then
            local ts = os.time({
                year = year,
                month = month,
                day = day,
                hour = hour,
                min = min,
                sec = sec
            })
            if ts and ts > 0 then
                return ts
            end
        end
    end

    local at_num = tonumber(get_file_atime_epoch(file_path))
    if at_num and at_num > 0 then
        return math.floor(at_num)
    end
    return nil
end

-- Cache for open projects to avoid repeated EnumProjects calls
local open_projects_cache = {}
local cache_timestamp = 0

-- Check if a project is currently open (with caching)
local function is_project_open(project_path)
    if not project_path or project_path == "" then
        return false
    end
    
    -- Update cache if it's older than 1 second or empty
    local current_time = reaper.time_precise()
    if current_time - cache_timestamp > 1.0 or not next(open_projects_cache) then
        open_projects_cache = {}
        cache_timestamp = current_time
        
        -- Build cache of all open projects
        local project_index = 0
        while true do
            local project, open_project_path = reaper.EnumProjects(project_index, "")
            if not project then break end
            
            if open_project_path and open_project_path ~= "" then
                local normalized_path = open_project_path:gsub("\\", "/"):lower()
                open_projects_cache[normalized_path] = true
            end
            
            project_index = project_index + 1
            if project_index >= 100 then break end -- Protection from infinite loop
        end
    end
    
    -- Check against cache
    local normalized_path = project_path:gsub("\\", "/"):lower()
    return open_projects_cache[normalized_path] == true
end

-- Force refresh of open projects cache
local function refresh_open_projects_cache()
    open_projects_cache = {}
    cache_timestamp = 0
end

local HISTORY_SECTION = "FrenkieRecentProjectsHistory"
local HISTORY_KEY_REV = "rev_v1"

local HISTORY_JSON_FILENAME = "My Recent Projects List.json"
local HISTORY_TXT_FALLBACK = "My Recent Projects List.txt"
local LEGACY_HISTORY_FILENAME = "Frenkie Recent Projects History.txt"
local HISTORY_FILENAME_OLD_TYPO = "My Resent Projects List.txt"

local function history_unesc(s)
    s = tostring(s or "")
    s = s:gsub("%%0D", "\r")
    s = s:gsub("%%0A", "\n")
    s = s:gsub("%%09", "\t")
    s = s:gsub("%%25", "%%")
    return s
end

local function history_esc(s)
    s = tostring(s or "")
    s = s:gsub("%%", "%%25")
    s = s:gsub("\r", "%%0D")
    s = s:gsub("\n", "%%0A")
    s = s:gsub("\t", "%%09")
    return s
end

local function normalize_history_path(p)
    return tostring(p or ""):gsub("\\", "/"):lower()
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

local function history_to_json(records)
    local parts = {}
    for i = 1, #records do
        local it = records[i]
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
            local name = tostring(obj.name or "")
            if name == "" then name = obj.path:match("([^/\\]+)%.rpp$") or obj.path:match("([^/\\]+)$") or obj.path end
            out[#out + 1] = {
                path = obj.path,
                norm = normalize_history_path(obj.path),
                name = name,
                last_opened = tonumber(obj.last_opened) or 0,
                open_count = tonumber(obj.open_count) or 0,
                total_open_sec = tonumber(obj.total_open_sec) or 0,
                total_work_sec = tonumber(obj.total_work_sec) or 0
            }
        end
        skip_ws()
        if raw:sub(pos, pos) == "]" then break end
        if raw:sub(pos, pos) ~= "," then break end
        pos = pos + 1
    end
    return out
end

local history_file_path = nil

local function get_history_dir()
    local src = debug.getinfo(1, "S")
    local script_path = src and src.source and src.source:match("@(.+)") or ""
    local dir = script_path:match("(.+)[/\\][^/\\]+$") or ""
    return dir:match("(.+)[/\\][^/\\]+$") or dir
end

local function get_history_file_path()
    if history_file_path then
        return history_file_path
    end
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

local function parse_history_records_raw(raw)
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
                path = history_unesc(path_s)
                name = history_unesc(name_s or "")
                last_opened = tonumber(ts_s) or 0
                open_count = tonumber(cnt_s) or 0
            else
                local ts3_s, name3_s, path3_s = line4:match("^(%d+)\t(.-)\t(.*)$")
                if ts3_s and path3_s then
                    path = history_unesc(path3_s)
                    name = history_unesc(name3_s or "")
                    last_opened = tonumber(ts3_s) or 0
                    open_count = 0
                else
                    local ts2_s, path2_s = line4:match("^(%d+)\t(.*)$")
                    if ts2_s and path2_s then
                        path = history_unesc(path2_s)
                        name = ""
                        last_opened = tonumber(ts2_s) or 0
                        open_count = 0
                    else
                        path = history_unesc(line4)
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
                    name = path:match("([^/\\]+)%.rpp$") or path:match("([^/\\]+)$") or path
                end
                out[#out + 1] = {
                    path = path,
                    norm = normalize_history_path(path),
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

local function write_history_records_to_path(path, records)
    local tmp_path = path .. ".tmp"
    local f = io.open(tmp_path, "w")
    if not f then return false end
    if path:lower():match("%.json%s*$") then
        f:write(history_to_json(records))
    else
        for i = 1, #records do
            local it = records[i]
            f:write(string.format(
                "%d\t%d\t%s\t%s\t%d\t%d\n",
                tonumber(it.last_opened) or 0,
                tonumber(it.open_count) or 0,
                history_esc(it.name or ""),
                history_esc(it.path or ""),
                math.floor(tonumber(it.total_open_sec) or 0),
                math.floor(tonumber(it.total_work_sec) or 0)
            ))
        end
    end
    f:close()
    local ok = os.rename(tmp_path, path)
    if not ok then os.remove(tmp_path) end
    return ok
end

local function write_history_records(records)
    local path = get_history_file_path()
    if not write_history_records_to_path(path, records) then
        return false
    end
    if reaper.SetExtState then
        reaper.SetExtState(HISTORY_SECTION, HISTORY_KEY_REV, tostring(math.floor(reaper.time_precise() * 1000)), true)
    end
    return true
end

local function read_history_records()
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
    return parse_history_records_raw(raw)
end

function ProjectList.migrate_txt_to_json()
    local dir = get_history_dir()
    local json_path = (dir ~= "" and (dir .. "/" .. HISTORY_JSON_FILENAME)) or HISTORY_JSON_FILENAME
    local has_file_exists = reaper and reaper.file_exists
    if has_file_exists and reaper.file_exists(json_path) then
        return true
    end
    local txt_candidates = (dir ~= "" and { dir .. "/" .. HISTORY_TXT_FALLBACK, dir .. "/" .. HISTORY_FILENAME_OLD_TYPO, dir .. "/" .. LEGACY_HISTORY_FILENAME }) or { HISTORY_TXT_FALLBACK, HISTORY_FILENAME_OLD_TYPO, LEGACY_HISTORY_FILENAME }
    for _, txt_path in ipairs(txt_candidates) do
        if has_file_exists and reaper.file_exists(txt_path) then
            local f = io.open(txt_path, "r")
            if f then
                local raw = f:read("*a") or ""
                f:close()
                local records = parse_history_records_raw(raw)
                if #records > 0 and write_history_records_to_path(json_path, records) then
                    history_file_path = nil
                    if reaper.SetExtState then
                        reaper.SetExtState(HISTORY_SECTION, HISTORY_KEY_REV, tostring(math.floor(reaper.time_precise() * 1000)), true)
                    end
                    return true
                end
            end
        end
    end
    return false
end

function ProjectList.get_history_file_path_for_ui()
    return get_history_file_path()
end

local function save_history_records(records)
    return write_history_records(records)
end


local function get_reaper_ini_path()
    if reaper.get_ini_file then
        local ok, path = pcall(reaper.get_ini_file)
        if ok and type(path) == "string" and path ~= "" then
            return path
        end
    end
    if reaper.GetResourcePath then
        local base = reaper.GetResourcePath()
        if base and base ~= "" then
            return tostring(base) .. "/reaper.ini"
        end
    end
    return nil
end

local function read_reaper_ini_recent_paths()
    if not reaper.BR_Win32_GetPrivateProfileString then
        return {}
    end
    local ini_path = get_reaper_ini_path()
    if not ini_path or ini_path == "" then
        return {}
    end
    local paths = {}
    local max_recent = 100
    for i = 1, max_recent do
        local key = string.format("recent%02d", i)
        local _, full_path = reaper.BR_Win32_GetPrivateProfileString("recent", key, "", ini_path)
        full_path = tostring(full_path or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if full_path ~= "" and looks_like_project_path(full_path) then
            paths[#paths + 1] = full_path
        end
    end
    return paths
end

local function import_reaper_ini_recent_to_history()
    local ini_paths = read_reaper_ini_recent_paths()
    if #ini_paths == 0 then
        return false, "no recent projects found"
    end
    local records = read_history_records()
    local existing_by_norm = {}
    for i = 1, #records do
        local rec = records[i]
        local n = normalize_history_path(rec and rec.path)
        if n ~= "" and not existing_by_norm[n] then
            existing_by_norm[n] = i
        end
    end
    local seen_new = {}
    local now = os.time()
    for idx = 1, #ini_paths do
        local p = tostring(ini_paths[idx] or "")
        local n = normalize_history_path(p)
        if p ~= "" and n ~= "" and not existing_by_norm[n] and not seen_new[n] then
            seen_new[n] = true
            local name = p:match("([^/\\]+)%.rpp$") or p:match("([^/\\]+)$") or p
            local last_opened = nil
            if reaper.file_exists and reaper.file_exists(p) then
                local at = get_file_atime_epoch(p)
                if at and tonumber(at) and tonumber(at) > 0 then
                    last_opened = math.floor(tonumber(at))
                else
                    local mt = get_file_mtime_epoch(p)
                    if mt and tonumber(mt) and tonumber(mt) > 0 then
                        last_opened = math.floor(tonumber(mt))
                    end
                end
            end
            if not last_opened then
                last_opened = now - (idx - 1)
            end
            records[#records + 1] = {
                path = p,
                norm = n,
                name = name,
                last_opened = last_opened,
                open_count = 0
            }
        end
    end
    if #records == 0 then
        return true, "nothing to import"
    end
    local ok = save_history_records(records)
    if not ok then
        return false, "failed to save history"
    end
    return true, nil
end

function ProjectList.ensure_reaper_ini_import()
    if not reaper.GetExtState or not reaper.SetExtState then
        return
    end
    local done = tostring(reaper.GetExtState(IMPORT_EXT_SECTION, IMPORT_EXT_KEY_DONE) or "")
    if done ~= "" then
        return
    end
    local msg = "All your projects will be imported into the list. Further history will be managed by the widget.\n\nDo you want to import recent projects from REAPER now?"
    local title = "Frenkie Recent Projects"
    local ret = 6
    if reaper.ShowMessageBox then
        ret = reaper.ShowMessageBox(msg, title, 4)
    end
    if ret ~= 6 then
        reaper.SetExtState(IMPORT_EXT_SECTION, IMPORT_EXT_KEY_DONE, "1", true)
        return
    end
    local ok, err = import_reaper_ini_recent_to_history()
    reaper.SetExtState(IMPORT_EXT_SECTION, IMPORT_EXT_KEY_DONE, "1", true)
    if not ok and err and err ~= "" and reaper.ShowMessageBox then
        reaper.ShowMessageBox("Import from reaper.ini failed:\n" .. tostring(err), title, 0)
    end
end

function ProjectList.reset_hint_state()
    if not reaper.DeleteExtState then
        return false
    end
    local deleted_any = false
    if reaper.HasExtState and reaper.HasExtState(IMPORT_EXT_SECTION, IMPORT_EXT_KEY_DONE) then
        reaper.DeleteExtState(IMPORT_EXT_SECTION, IMPORT_EXT_KEY_DONE, true)
        deleted_any = true
    end
    if reaper.HasExtState and reaper.HasExtState(IMPORT_EXT_SECTION, PREVIEW_HINT_KEY) then
        reaper.DeleteExtState(IMPORT_EXT_SECTION, PREVIEW_HINT_KEY, true)
        deleted_any = true
    end
    return deleted_any
end


local function read_recent_projects_from_extstate_history()
    local projects = {}
    local records = read_history_records()
    local idx = 0
    for _, rec in ipairs(records) do
        local project_path = tostring(rec.path or "")
        if project_path ~= "" then
            local ini_time = tostring(tonumber(rec.last_opened) or 0)
            local project_name = tostring(rec.name or "")
            if project_name == "" then
                project_name = project_path:match("([^/\\]+)%.rpp$") or project_path:match("([^/\\]+)$") or project_path
            end
            local exists = true
            if reaper.file_exists and not reaper.file_exists(project_path) then
                exists = false
            end
            local preview_path = nil
            if exists then
                preview_path = get_project_preview_path(project_path)
            end
            projects[#projects + 1] = {
                name = project_name,
                path = project_path,
                full_path = project_path,
                time = ini_time,
                date = get_file_date(project_path),
                opened_date = get_opened_date(ini_time, project_path),
                index = idx,
                is_open = is_project_open(project_path),
                is_unavailable = not exists,
                has_preview = preview_path ~= nil,
                preview_path = preview_path,
                open_count = tonumber(rec.open_count) or 0,
                total_open_sec = tonumber(rec.total_open_sec) or 0,
                total_work_sec = tonumber(rec.total_work_sec) or 0
            }
            idx = idx + 1
        end
    end
    return projects
end

-- Initialize the module
function ProjectList.init()
    -- Module initialization if needed
end

local function normalize_project_path(p)
    return tostring(p or ""):gsub("\\", "/"):lower()
end

local function get_current_project_path()
    if not reaper.EnumProjects then
        return ""
    end
    local proj, path = reaper.EnumProjects(-1, "")
    if not proj then
        return ""
    end
    return tostring(path or "")
end

function ProjectList.get_recent_projects()
    local projects = read_recent_projects_from_extstate_history()

    local cur_path = get_current_project_path()
    if cur_path ~= "" then
        local needle = normalize_project_path(cur_path)
        local found_i = nil
        for i, p in ipairs(projects) do
            local pp = normalize_project_path(p and (p.full_path or p.path))
            if pp ~= "" and pp == needle then
                found_i = i
                p.is_current = true
                p.is_open = true
                break
            end
        end

        if found_i then
            local cur = table.remove(projects, found_i)
            table.insert(projects, 1, cur)
        else
            local project_name = cur_path:match("([^/\\]+)%.rpp$") or cur_path:match("([^/\\]+)$") or cur_path
            local preview_path = get_project_preview_path(cur_path)
            table.insert(projects, 1, {
                name = project_name,
                path = cur_path,
                full_path = cur_path,
                time = "",
                date = get_file_date(cur_path),
                opened_date = get_opened_date("", cur_path),
                index = -1,
                is_open = true,
                is_current = true,
                has_preview = preview_path ~= nil,
                preview_path = preview_path,
                total_open_sec = 0,
                total_work_sec = 0
            })
        end
    end

    return projects
end

local function normalize_search_text(s)
    s = tostring(s or ""):lower()
    s = s:gsub("%s+", " ")
    s = s:match("^%s*(.-)%s*$") or ""
    return s
end

local function split_search_terms(s)
    local terms = {}
    for term in tostring(s or ""):gmatch("%S+") do
        terms[#terms + 1] = term
    end
    return terms
end

local function project_match_score(project, filter_text)
    if not project then return nil end
    local q = normalize_search_text(filter_text)
    if q == "" then return 0 end

    local name = tostring(project.name or ""):lower()
    local path = tostring(project.full_path or project.path or ""):lower()
    local date = tostring(project.date or ""):lower()
    local haystack = name .. " " .. path

    local terms = split_search_terms(q)
    if #terms == 0 then return 0 end

    local total = 0
    for _, term in ipairs(terms) do
        if term ~= "" then
            local term_score = 0
            local name_pos = name:find(term, 1, true)
            local path_pos = path:find(term, 1, true)
            local date_pos = date:find(term, 1, true)

            if name_pos then
                term_score = term_score + 100
                if name_pos == 1 or name:sub(name_pos - 1, name_pos - 1):match("[%s%p]") then
                    term_score = term_score + 20
                end
                if #term >= 3 then
                    term_score = term_score + math.min(#term, 10)
                end
            elseif path_pos then
                term_score = term_score + 40
                if #term >= 3 then
                    term_score = term_score + math.min(#term, 5)
                end
            elseif date_pos then
                term_score = term_score + 10
            else
                return nil
            end

            total = total + term_score
        end
    end

    if haystack:find(q, 1, true) then
        total = total + 30
    end

    return total
end

-- Filter projects based on search criteria
function ProjectList.filter_projects(projects, filter_text)
    local filtered = {}

    for _, project in ipairs(projects) do
        if project and project.is_current then
            table.insert(filtered, project)
        else
            local score = project_match_score(project, filter_text)
            if not filter_text or filter_text == "" or (score and score > 0) then
                table.insert(filtered, project)
            end
        end
    end

    return filtered
end

function ProjectList.ensure_pinned_paths(settings)
    if type(settings) ~= "table" then
        return {}
    end
    local pinned_paths = settings.pinned_paths
    if type(pinned_paths) ~= "table" then
        pinned_paths = {}
        settings.pinned_paths = pinned_paths
    end
    return pinned_paths
end

function ProjectList.is_project_pinned(settings, project_path)
    if type(settings) ~= "table" then
        return false
    end
    local pinned_paths = settings.pinned_paths
    if type(pinned_paths) ~= "table" then
        return false
    end
    local n = normalize_path(project_path)
    return n ~= "" and pinned_paths[n] == true
end

function ProjectList.toggle_project_pinned(settings, project_path)
    local pinned_paths = ProjectList.ensure_pinned_paths(settings)
    local n = normalize_path(project_path)
    if n == "" then
        return false
    end
    if pinned_paths[n] == true then
        pinned_paths[n] = nil
        return false
    end
    pinned_paths[n] = true
    return true
end

function ProjectList.get_project_section(project)
    if project and project.is_current then
        return "current"
    end
    if project and project.is_open then
        return "open"
    end
    if project and project.is_pinned then
        return "pinned"
    end
    return "rest"
end

function ProjectList.get_project_ui_section(project)
    local s = ProjectList.get_project_section(project)
    if s == "current" or s == "open" then
        return "open"
    end
    return "rest"
end

function ProjectList.build_ui_section_indices(projects)
    local open_indices = {}
    local rest_indices = {}
    for i, p in ipairs(projects or {}) do
        if ProjectList.get_project_ui_section(p) == "open" then
            open_indices[#open_indices + 1] = i
        else
            rest_indices[#rest_indices + 1] = i
        end
    end
    return open_indices, rest_indices
end

local function collect_selected_paths(app_state)
    local selected = {}
    local selected_map = {}
    if not app_state then
        return selected, selected_map
    end

    local projects = app_state.filtered_projects or {}
    local rows = app_state.selected_rows or {}
    for idx, v in pairs(rows) do
        if v == true then
            local p = projects[idx]
            local path = p and (p.full_path or p.path) or ""
            local n = normalize_path(path)
            if n ~= "" and selected_map[n] ~= true then
                selected[#selected + 1] = n
                selected_map[n] = true
            end
        end
    end

    local idx = app_state.selected_project
    if idx ~= nil then
        local p = projects[idx]
        local path = p and (p.full_path or p.path) or ""
        local n = normalize_path(path)
        if n ~= "" and selected_map[n] ~= true then
            selected[#selected + 1] = n
            selected_map[n] = true
        end
    end

    local settings = app_state.settings or {}
    local saved_path = tostring(settings.selected_project_path or "")
    if saved_path ~= "" then
        local n = normalize_path(saved_path)
        if n ~= "" and selected_map[n] ~= true then
            selected[#selected + 1] = n
            selected_map[n] = true
        end
    end

    return selected, selected_map
end

local function restore_selection(app_state, selected_paths, selected_map)
    if not app_state then
        return
    end
    selected_paths = selected_paths or {}
    selected_map = selected_map or {}

    app_state.selected_rows = app_state.selected_rows or {}
    for k in pairs(app_state.selected_rows) do
        app_state.selected_rows[k] = nil
    end

    local last_selected = nil
    local projects = app_state.filtered_projects or {}
    for i, p in ipairs(projects) do
        local path = p and (p.full_path or p.path) or ""
        local n = normalize_path(path)
        if n ~= "" and selected_map[n] == true then
            app_state.selected_rows[i] = true
            last_selected = i
        end
    end

    if last_selected ~= nil then
        app_state.selected_project = last_selected
        app_state.selection_anchor_index = last_selected
        local p = projects[last_selected]
        app_state.selection_section = ProjectList.get_project_ui_section(p)
        return
    end

    app_state.selected_project = nil
    app_state.selection_anchor_index = nil
    app_state.selection_section = nil
end

function ProjectList.rebuild_filtered_projects(app_state)
    if not app_state then
        return
    end

    local settings = app_state.settings or {}
    local pinned_paths = ProjectList.ensure_pinned_paths(settings)
    if app_state.projects then
        ProjectList.apply_pinned_flags(app_state.projects, pinned_paths)
    end

    local selected_paths, selected_map = collect_selected_paths(app_state)

    local filter_text = tostring(app_state.filter_text or "")
    local filtered = ProjectList.filter_projects(app_state.projects or {}, filter_text)
    ProjectList.apply_pinned_flags(filtered, pinned_paths)
    app_state.filtered_projects = ProjectList.sort_and_group_projects(filtered, settings)

    restore_selection(app_state, selected_paths, selected_map)
end

function ProjectList.apply_pinned_flags(projects, pinned_paths)
    local pinned = (type(pinned_paths) == "table") and pinned_paths or {}
    for _, p in ipairs(projects or {}) do
        if p then
            local path = p.full_path or p.path
            local n = normalize_path(path)
            if n ~= "" and pinned[n] == true then
                p.is_pinned = true
            else
                p.is_pinned = false
            end
        end
    end
end

function ProjectList.group_projects(projects)
    local cur = {}
    local open = {}
    local pinned = {}
    local rest = {}

    for _, p in ipairs(projects or {}) do
        if p and p.is_current then
            cur[#cur + 1] = p
        elseif p and p.is_open then
            open[#open + 1] = p
        elseif p and p.is_pinned then
            pinned[#pinned + 1] = p
        else
            rest[#rest + 1] = p
        end
    end

    local out = {}
    for i = 1, #cur do out[#out + 1] = cur[i] end
    for i = 1, #open do out[#out + 1] = open[i] end
    for i = 1, #pinned do out[#out + 1] = pinned[i] end
    for i = 1, #rest do out[#out + 1] = rest[i] end
    return out
end

function ProjectList.sort_and_group_projects(projects, settings)
    local s = settings or {}
    local sm = tostring(s.sort_mode or "opened")
    local sd = "desc"
    if sm == "modified" then
        sd = tostring(s.sort_dir_modified or "desc")
    else
        sd = tostring(s.sort_dir_opened or "desc")
    end
    local sorted = ProjectList.sort_projects(projects or {}, sm, sd)
    return ProjectList.group_projects(sorted)
end

function ProjectList.sort_projects(projects, sort_mode, sort_dir)
    local mode = tostring(sort_mode or "opened")
    if mode == "1" or mode == "opened" or mode == "recent" then
        mode = "opened"
    elseif mode == "2" or mode == "modified" or mode == "mtime" then
        mode = "modified"
    else
        mode = "opened"
    end

    local dir = tostring(sort_dir or "desc")
    local asc = (dir == "asc" or dir == "up" or dir == "old" or dir == "older")

    local out = {}
    for i = 1, #(projects or {}) do
        out[i] = projects[i]
    end

    local function project_key(p)
        if not p then return nil end
        local path = p.full_path or p.path
        if mode == "modified" then
            local mt = get_file_mtime_epoch(path)
            if mt == false then return nil end
            return tonumber(mt)
        end
        local ot = get_opened_epoch(p.time or "", path)
        return tonumber(ot)
    end

    local function group_rank(p)
        if not p then return 3 end
        if p.is_current then
            return 0
        end
        if p.is_open then
            return 1
        end
        if p.is_pinned then
            return 2
        end
        return 3
    end

    table.sort(out, function(a, b)
        local ga = group_rank(a)
        local gb = group_rank(b)
        if ga ~= gb then
            return ga < gb
        end

        local ta = project_key(a) or 0
        local tb = project_key(b) or 0
        if ta == tb then
            local ia = tonumber(a and a.index) or 0
            local ib = tonumber(b and b.index) or 0
            if ia ~= ib then
                return ia < ib
            end
            return tostring(a and a.name or "") < tostring(b and b.name or "")
        end
        if asc then
            return ta < tb
        end
        return ta > tb
    end)

    return out
end

-- Open project
function ProjectList.open_project(project_path)
    if reaper.file_exists(project_path) then
        reaper.Main_openProject(project_path)
        -- Refresh cache after opening project
        refresh_open_projects_cache()
    else
        reaper.ShowMessageBox("File not found:\n" .. project_path, "Error", 0)
    end
end

-- Open project in new tab
function ProjectList.open_project_new_tab(project_path)
    if reaper.file_exists(project_path) then
        -- First create new tab
        reaper.Main_OnCommand(40859, 0) -- New project tab
        -- Then open project in new tab
        reaper.Main_openProject(project_path)
        -- Refresh cache after opening project
        refresh_open_projects_cache()
    else
        reaper.ShowMessageBox("File not found:\n" .. project_path, "Error", 0)
    end
end

function ProjectList.close_project(project_path)
    local p = tostring(project_path or "")
    if p == "" then
        return false
    end

    local open_project = get_open_project_instance_by_path(p)
    if not open_project then
        return false
    end

    run_main_command_in_project(40860, open_project)
    refresh_open_projects_cache()
    return true
end

-- Show project in system file manager
function ProjectList.show_in_file_manager(project_path)
    local path = tostring(project_path or "")
    if path == "" then return end

    local os_name = reaper.GetOS and tostring(reaper.GetOS()) or ""
    local is_mac = os_name:match("OSX") ~= nil or os_name:lower():match("mac") ~= nil
    local is_win = os_name:match("Win") ~= nil

    local target = path
    if not reaper.file_exists(path) then
        local folder = path:match("(.+)[/\\][^/\\]+$")
        if folder and folder ~= "" then
            target = folder
        end
    end

    if is_mac then
        if reaper.CF_LocateInExplorer and reaper.file_exists(path) then
            reaper.CF_LocateInExplorer(path)
            return
        end
        if reaper.CF_ShellExecute then
            reaper.CF_ShellExecute(target)
        end
    elseif is_win then
        if reaper.CF_LocateInExplorer and reaper.file_exists(path) then
            reaper.CF_LocateInExplorer(path)
            return
        end
        if reaper.CF_ShellExecute then
            reaper.CF_ShellExecute(target)
        end
    else
        if reaper.CF_ShellExecute then
            reaper.CF_ShellExecute(target)
        elseif reaper.OpenURL then
            reaper.OpenURL(target)
        end
    end
end

local function get_last_existing_folder(project_path)
    local s = tostring(project_path or "")
    if s == "" then return nil end
    local folder = s:match("(.+)[/\\][^/\\]+$") or s
    local function path_exists(path)
        if not path or path == "" then return false end
        local ok, _, code = os.rename(path, path)
        if ok then return true end
        if code == 13 then return true end
        return false
    end
    while folder and folder ~= "" do
        if path_exists(folder) then
            return folder
        end
        local parent = folder:match("(.+)[/\\][^/\\]+$") or nil
        if not parent or parent == folder then
            break
        end
        folder = parent
    end
    return nil
end

function ProjectList.open_last_existing_folder(project_path)
    local folder = get_last_existing_folder(project_path)
    if not folder then
        return false, "no existing folder found"
    end
    if reaper.CF_ShellExecute then
        reaper.CF_ShellExecute(folder)
        return true
    end
    return false, "CF_ShellExecute is not available"
end

function ProjectList.remove_project_from_history(project_path)
    local target = tostring(project_path or "")
    if target == "" then
        return false, "empty project path"
    end

    local target_n = normalize_history_path(target)
    local records = read_history_records()
    if #records == 0 then
        return false, "history is empty"
    end

    local kept = {}
    local removed = false
    for _, r in ipairs(records) do
        if r and r.norm == target_n then
            removed = true
        else
            kept[#kept + 1] = r
        end
    end

    if not removed then
        return false, "not found"
    end

    local ok = save_history_records(kept)
    if not ok then
        return false, "failed to save history"
    end
    return true
end

function ProjectList.remove_project_from_recent_list(project_path)
    return ProjectList.remove_project_from_history(project_path)
end

function ProjectList.find_missing_projects()
    local missing = {}
    local records = read_history_records()
    for _, rec in ipairs(records) do
        local project_path = tostring(rec.path or "")
        if project_path ~= "" and reaper.file_exists and not reaper.file_exists(project_path) then
            missing[#missing + 1] = project_path
        end
    end
    return missing
end

-- Export cache management functions
ProjectList.refresh_open_projects_cache = refresh_open_projects_cache
ProjectList.clear_file_date_cache = clear_file_date_cache

return ProjectList
