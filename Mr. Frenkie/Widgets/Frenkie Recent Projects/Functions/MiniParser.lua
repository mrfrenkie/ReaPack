-- @noindex

local MiniRPPParser = {}

local function has_video_in_str(s)
    local v = tostring(s or ""):lower()
    if v == "" then return false end
    if v:find(".mp4", 1, true) or v:find(".mov", 1, true) or v:find(".avi", 1, true)
        or v:find(".mkv", 1, true) or v:find(".webm", 1, true) or v:find(".mpg", 1, true)
        or v:find(".m4v", 1, true) or v:find(".flv", 1, true) then
        return true
    end
    return false
end

local function split_tokens(line)
    local parts = {}
    for part in tostring(line or ""):gmatch("%S+") do
        parts[#parts + 1] = part
    end
    return parts
end

function MiniRPPParser.read_project_metadata(project_path)
    local p = tostring(project_path or "")
    if p == "" then
        return nil
    end

    local f = io.open(p, "r")
    if not f then
        return nil
    end

    local meta = {
        song_length_sec = nil,
        timebase_mode = nil,
        bpm = nil,
        tracks_count = nil,
        notes_title = nil,
        notes_author = nil,
        notes_body = nil,
        has_video = nil,
        regions = nil,
    }

    local tracks_count = 0
    local timebase_mode = nil
    local bpm = nil
    local markers_raw = {}
    local regions = {}
    local has_video = false

    local in_track = false
    local in_item = false
    local in_notes = false
    local in_projmetadata = false
    local item_pos = nil
    local item_len = nil

    local notes_lines = {}
    local span_start = nil
    local span_end = nil
    local max_item_end = 0.0

    while true do
        local line = f:read("*l")
        if not line then
            break
        end

        local stripped = tostring(line or ""):gsub("\r", "")
        local trimmed = stripped:match("^%s*(.-)%s*$") or ""
        if trimmed == "" then
            if in_notes then
                notes_lines[#notes_lines + 1] = ""
            end
        else
            if not has_video and has_video_in_str(trimmed) then
                has_video = true
            end

            if trimmed:sub(1, 1) == "<" then
                local tag = trimmed:match("^<(%S+)")
                if tag == "TRACK" then
                    tracks_count = tracks_count + 1
                    in_track = true
                    in_item = false
                elseif tag == "ITEM" then
                    in_item = true
                    item_pos = nil
                    item_len = nil
                elseif tag == "NOTES" and not meta.notes_body then
                    in_notes = true
                    notes_lines = {}
                elseif tag == "PROJMETADATA" then
                    in_projmetadata = true
                end
            elseif trimmed == ">" then
                if in_item then
                    if item_pos and item_len and item_pos >= 0 and item_len > 0 then
                        local e = item_pos + item_len
                        if e > max_item_end then
                            max_item_end = e
                        end
                    end
                    in_item = false
                    item_pos = nil
                    item_len = nil
                elseif in_notes then
                    in_notes = false
                    if #notes_lines > 0 and not meta.notes_body then
                        meta.notes_body = table.concat(notes_lines, "\n")
                    end
                elseif in_projmetadata then
                    in_projmetadata = false
                else
                    in_track = false
                end
            else
                if in_notes then
                    notes_lines[#notes_lines + 1] = trimmed
                end

                local tokens = split_tokens(trimmed)
                local tag = tokens[1]

                if (tag == "MARKER" or tag == "REGION") and #tokens >= 4 then
                    local id = tonumber(tokens[2])
                    local pos = tonumber(tokens[3])
                    if pos then
                        local first_name_i = 4
                        local name_end_i = #tokens + 1
                        for i = first_name_i, #tokens do
                            local num = tonumber(tokens[i])
                            if num ~= nil then
                                name_end_i = i
                                break
                            end
                        end
                        local name = ""
                        if name_end_i > first_name_i then
                            name = table.concat(tokens, " ", first_name_i, name_end_i - 1)
                            name = name:gsub('^"(.*)"$', "%1")
                        end
                        local isrgn = 0
                        local color = nil
                        if name_end_i <= #tokens then
                            local v = tonumber(tokens[name_end_i])
                            if v then
                                isrgn = v
                            end
                            if name_end_i + 1 <= #tokens then
                                local cv = tonumber(tokens[name_end_i + 1])
                                if cv and cv ~= 0 then
                                    color = cv
                                end
                            end
                        end
                        markers_raw[#markers_raw + 1] = {
                            id = id,
                            pos = pos,
                            name = name,
                            isrgn = isrgn,
                            color = color,
                        }
                    end
                end

                if not bpm and tag == "TEMPO" and #tokens >= 2 then
                    local v = tonumber(tokens[2])
                    if v ~= nil and v > 0 then
                        bpm = v
                    end
                end

                if tag == "TITLE" and not meta.notes_title and #tokens >= 2 then
                    local v = tokens[2]
                    if #tokens > 2 then
                        v = table.concat(tokens, " ", 2)
                    end
                    v = tostring(v or "")
                    v = v:gsub('^"(.*)"$', "%1")
                    if v ~= "" then
                        meta.notes_title = v
                    end
                elseif tag == "AUTHOR" and not meta.notes_author and #tokens >= 2 then
                    local v = tokens[2]
                    if #tokens > 2 then
                        v = table.concat(tokens, " ", 2)
                    end
                    v = tostring(v or "")
                    v = v:gsub('^"(.*)"$', "%1")
                    if v ~= "" then
                        meta.notes_author = v
                    end
                end

                if not timebase_mode and not in_track and tag == "TIMEBASE" and #tokens >= 2 then
                    local v = tonumber(tokens[2])
                    if v ~= nil then
                        timebase_mode = v
                    end
                end

                if in_item and #tokens >= 2 then
                    if tag == "POSITION" and not item_pos then
                        local v = tonumber(tokens[2])
                        if v and v >= 0 then
                            item_pos = v
                        end
                    elseif tag == "LENGTH" and not item_len then
                        local v = tonumber(tokens[2])
                        if v and v > 0 then
                            item_len = v
                        end
                    end
                end
            end
        end
    end

    f:close()

    if #markers_raw > 0 then
        for _, m in ipairs(markers_raw) do
            local name = tostring(m.name or "")
            if name ~= "" and name:sub(1, 1) == "=" then
                local u = string.upper(name)
                local pos = tonumber(m.pos)
                if pos then
                    if u == "=START" and span_start == nil then
                        span_start = pos
                    elseif u == "=END" and span_start ~= nil and span_end == nil and pos > span_start then
                        span_end = pos
                        break
                    end
                end
            end
        end
    end

    if #markers_raw > 0 then
        for i, m in ipairs(markers_raw) do
            local name = tostring(m.name or "")
            if name ~= "" and name:sub(1, 1) ~= "=" then
                local start_pos = tonumber(m.pos)
                local end_pos = nil
                local idx = m.id
                if start_pos and idx ~= nil then
                    for j = i + 1, #markers_raw do
                        local n = markers_raw[j]
                        if n and n.id == idx then
                            local epos = tonumber(n.pos)
                            if epos and epos > start_pos then
                                end_pos = epos
                                break
                            end
                        end
                    end
                end
                if start_pos and end_pos and end_pos > start_pos then
                    local col = m.color
                    regions[#regions + 1] = {
                        start = start_pos,
                        finish = end_pos,
                        name = name,
                        color = col,
                    }
                end
            end
        end
    end

    if tracks_count > 0 then
        meta.tracks_count = tracks_count
    end

    if timebase_mode == nil then
        timebase_mode = 1
    end
    meta.timebase_mode = timebase_mode
    meta.bpm = bpm

    if #regions > 0 then
        table.sort(regions, function(a, b)
            return (tonumber(a.start) or 0) < (tonumber(b.start) or 0)
        end)
        meta.regions = regions
    end

    if span_start and span_end and span_end > span_start then
        meta.regions_span_start = span_start
        meta.regions_span_end = span_end
    end

    if max_item_end > 0 then
        meta.song_length_sec = max_item_end
    end

    if meta.notes_body and meta.notes_body ~= "" then
        local title = meta.notes_title
        local author = meta.notes_author
        local body_lines = {}
        for line in (meta.notes_body .. "\n"):gmatch("([^\r\n]*)\r?\n") do
            local trimmed = tostring(line):match("^%s*(.-)%s*$") or ""
            local lower = trimmed:lower()
            local consumed = false
            if (not title) and lower:match("^title%s*:") then
                title = trimmed:match("^.-:%s*(.*)$") or ""
                consumed = true
            elseif (not author) and lower:match("^author%s*:") then
                author = trimmed:match("^.-:%s*(.*)$") or ""
                consumed = true
            end
            local is_meta_line = false
            if not consumed and trimmed ~= "" then
                if lower:match("^%s*|%s*$") then
                    is_meta_line = true
                elseif lower:match("^%s*|%s*flags") then
                    is_meta_line = true
                elseif lower:match("^flags%s*[:%s]") then
                    is_meta_line = true
                end
            end
            if not consumed and not is_meta_line and trimmed ~= "" then
                local line_text = trimmed
                local without_bar = line_text:match("^|%s*(.+)$")
                if without_bar and without_bar ~= "" then
                    line_text = without_bar
                end
                body_lines[#body_lines + 1] = line_text
            end
        end
        meta.notes_title = (title and title ~= "") and title or nil
        meta.notes_author = (author and author ~= "") and author or nil
        if #body_lines > 0 then
            meta.notes_body = table.concat(body_lines, "\n")
        else
            meta.notes_body = nil
        end
    end

    meta.has_video = has_video

    return meta
end

return MiniRPPParser
